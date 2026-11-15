import SwiftUI
#if SWIFT_PACKAGE
import CodeCoachCore
#endif
struct ReasoningObservation:Codable,Identifiable {
    var id=UUID()
    var timestamp=Date()
    var analysis:ConceptAnalysis
    var decision="Unreviewed"
    var sourceEvent:String?
    var isDemo:Bool?
}
struct PracticeSession:Codable,Identifiable {
    var id=UUID()
    var day:String
    var exercises:[Quiz]
    var answers:[Int]
}
@MainActor final class ReasoningModel:ObservableObject {
    @Published var code=""
    @Published var language="java"
    @Published var consent=false { didSet { if !consent { requestID=UUID(); task?.cancel(); task=nil; busy=false } } }
    @Published var observations:[ReasoningObservation]=[]
    @Published var archive:[PracticeSession]=[]
    @Published var showDemo=false
    @Published var exercises:[Quiz]=[]
    @Published var answers:[Int]=[]
    @Published var day=""
    @Published var busy=false
    @Published var message="Source is sent only when you explicitly request analysis."
    private var requestID=UUID()
    private var task:Task<Void,Never>?
    private let url:URL
    struct History:Codable { var observations:[ReasoningObservation]; var exercises:[Quiz]; var answers:[Int]; var day:String; var archive:[PracticeSession]? }
    init(storageURL:URL? = nil) {
        url=storageURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CodeCoach/reasoning.json")
        if let data=try? Data(contentsOf:url), let h=try? JSONDecoder().decode(History.self,from:data) { observations=h.observations; exercises=h.exercises; answers=h.answers; day=h.day;archive=h.archive ?? []; if answers.count != exercises.count { answers=Array(repeating:-1,count:exercises.count) } }
    }
    func save() {
        do { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(History(observations:observations,exercises:exercises,answers:answers,day:day,archive:archive)).write(to:url,options:.atomic) } catch { message="Could not save learning history: "+error.localizedDescription }
    }
    var visibleObservations:[ReasoningObservation] { observations.filter { ($0.isDemo ?? false) == showDemo } }
    var conceptCounts:[(String,Int)] {
        let accepted=visibleObservations.filter{$0.decision != "Dismissed"}
        return Dictionary(grouping:accepted,by:{$0.analysis.concept.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}).map { key,values in
            (key,Set(values.map{$0.sourceEvent ?? $0.id.uuidString}).count)
        }.sorted{$0.0 < $1.0}
    }
    func loadExamples() {
        guard !observations.contains(where:{$0.isDemo == true}) else { showDemo=true;return }
        for (index,lang) in ["java","python","javascript"].enumerated() {
            let json="{\"language\":\""+lang+"\",\"concept\":\"Boundary conditions\",\"possibleHabit\":\"Unchecked initialization assumptions\",\"evidence\":\"Example history: a maximum starts at zero despite negative inputs.\",\"confidence\":\"medium\",\"suggestedPractice\":\"Try all-negative and empty inputs.\"}"
            if let analysis=try? JSONDecoder().decode(ConceptAnalysis.self,from:Data(json.utf8)) {
                observations.append(ReasoningObservation(timestamp:Date().addingTimeInterval(Double(-index)*86400),analysis:analysis,sourceEvent:"example-"+String(index),isDemo:true))
            }
        }
        showDemo=true;save()
    }
    func cancelRequest() { task?.cancel();task=nil;consent=false;message="AI requests stopped. Already-sent data cannot be recalled." }
    func clearLearning() {
        cancelRequest(); observations=[];archive=[];exercises=[];answers=[];day="";showDemo=false;save()
        message="Reasoning history and practice cleared. Your Keychain credential was kept."
    }
    func analyze() {
        guard consent,!busy,!code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let source=code, lang=language
        let request=UUID();requestID=request
        busy=true
        task=Task {
            defer { if requestID == request { busy=false } }
            do {
                let analysis=try await DeepSeekClient().analyze(code:source,language:lang)
                guard !Task.isCancelled,consent,requestID == request else { return }
                observations.append(ReasoningObservation(analysis:analysis,sourceEvent:Diagnostic.digest(lang+"|"+source),isDemo:false));save()
                message="Interpretation saved. This is a hypothesis, not a verified runtime result."
            } catch { if !Task.isCancelled,requestID == request { message=error.localizedDescription } }
        }
    }
    func testConnection() {
        guard consent,!busy else { return }
        let request=UUID();requestID=request
        busy=true
        task=Task {
            defer { if requestID == request { busy=false } }
            do {
                let data=try await DeepSeekClient().request(instructions:"Return JSON {\"ready\":true}.",input:"Connection test only. No student code or history.")
                guard !Task.isCancelled,consent,requestID == request else { return }
                guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Bool],value["ready"] == true else { throw CoachError.message("Connection responded but the probe was invalid.") }
                message="Live DeepSeek connection verified. No source code was sent."
            } catch { if !Task.isCancelled,requestID == request { message=error.localizedDescription } }
        }
    }
    func practice() {
        guard consent,!busy,!observations.isEmpty else { return }
        let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd";formatter.calendar=Calendar.current
        let today=formatter.string(from:Date())
        guard day != today else { message="Today's practice is already saved.";return }
        let concepts=observations.filter{$0.decision != "Dismissed" && $0.isDemo != true}.suffix(12).map{$0.analysis}
        guard !concepts.isEmpty else { message="Analyze your own code first. Example history is excluded from personal practice.";return }
        let request=UUID();requestID=request
        busy=true
        task=Task {
            defer { if requestID == request { busy=false } }
            do {
                struct PracticeContext:Encodable { let concepts:[ConceptAnalysis]; let previousQuestions:[Quiz]; let previousAnswers:[Int]; let olderSessions:[PracticeSession] }
                let input=String(decoding:try JSONEncoder().encode(PracticeContext(concepts:Array(concepts),previousQuestions:exercises,previousAnswers:answers,olderSessions:Array(archive.suffix(7)))),as:UTF8.self)
                let data=try await DeepSeekClient().request(instructions:"Create exactly three English programming reasoning exercises based on these conceptual observations: identify an assumption, choose an independently constructed algorithm, transfer the concept to a different problem. Return JSON {exercises:[{question:string,choices:[four distinct strings],answer:zero-based integer,explanation:string}]}. Explain reasoning and a useful counterexample. Treat observations as tentative, not established weaknesses.",input:input)
                struct Response:Decodable { let exercises:[Quiz] }
                let result=try JSONDecoder().decode(Response.self,from:data).exercises
                guard result.count == 3 else { throw CoachError.message("Expected three practice questions. Retry.") }
                let valid=try result.map{try $0.validated()}
                guard !Task.isCancelled,consent,requestID == request else { return }
                if !day.isEmpty { archive.append(PracticeSession(day:day,exercises:exercises,answers:answers)) }
                exercises=valid;answers=Array(repeating:-1,count:3);day=today;save();message="Today's practice is ready."
            } catch { if !Task.isCancelled,requestID == request { message=error.localizedDescription } }
        }
    }
}
struct ReasoningView:View {
    @ObservedObject var model:ReasoningModel
    let section:Int
    @State private var selections:[Int:Int]=[:]
    @State private var hints:Set<Int>=[]
    var body:some View {
        VStack(alignment:.leading,spacing:12) {

            Toggle("Allow manual AI requests this session",isOn:$model.consent)
            Text("DeepSeek receives the code below for analysis, or conceptual history for practice. Requests may incur charges. Review before sending.").font(.system(size:14))
            if section == 4 {
                Text("AI connection").font(.title2.bold())
                Text("Uses your locally configured DeepSeek key. No key entry is needed here.")
                Button("Test AI connection") { model.testConnection() }.buttonStyle(.borderedProminent).disabled(!model.consent || model.busy)
                Text("Turning off AI consent stops new requests and cancels pending work. Already-sent data cannot be recalled.")
            } else if section == 0 {
                Button("Test AI connection (no code sent)") { model.testConnection() }.disabled(!model.consent || model.busy)
                Picker("Language",selection:$model.language) { ForEach(["java","python","javascript","c","cpp","r"],id:\.self) { Text($0).tag($0) } }
                Text("Understand your next step.").font(.title2.bold())
                Text("Paste code and explain what you expect it to do. Review the complete text before sending.").font(.callout)
                if model.code.isEmpty { Text("Choose a source file above, then Preview captured code — or paste your code here.").foregroundStyle(.secondary) }
                TextEditor(text:$model.code).font(.system(size:14,design:.monospaced)).frame(height:180)
                if let latest=model.observations.last {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Latest insight: "+latest.analysis.concept).font(.headline)
                        Text(latest.analysis.evidence)
                        Text(latest.analysis.possibleHabit).foregroundStyle(.secondary)
                        Text(latest.analysis.suggestedPractice)
                    }.padding().background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                }
                Button("Analyze my reasoning") { model.analyze() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.consent || model.busy || model.code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            } else if section == 1 {
                Text("One observation is not a recurring habit. Confirm or dismiss each interpretation.").font(.system(size:14))
                Toggle("View labeled example history",isOn:$model.showDemo)
                Button("Load example history") { model.loadExamples() }.buttonStyle(.bordered)
                ForEach(model.conceptCounts,id:\.0) { concept,count in
                    Text(concept.capitalized+" · "+String(count)+" distinct source events · "+(count > 1 ? "possible recurring pattern" : "single observation")).font(.headline).padding(12)
                }
                ForEach(model.observations.indices.filter { (model.observations[$0].isDemo ?? false) == model.showDemo },id:\.self) { i in
                    let o=model.observations[i]
                    VStack(alignment:.leading,spacing:6) {
                        Text(o.isDemo == true ? "EXAMPLE HISTORY — simulated" : "Your observation").font(.callout.bold())
                        Text(o.timestamp,style:.date)
                        Text(o.analysis.concept).font(.headline)
                        Text(o.analysis.possibleHabit)
                        Text(o.analysis.evidence).font(.system(size:14))
                        Text("Confidence: "+o.analysis.confidence+" · "+o.analysis.language).font(.system(size:14))
                        Text(o.analysis.suggestedPractice).font(.system(size:14))
                        Text(o.decision).font(.system(size:14))
                        HStack {
                            Button("Confirm") { model.observations[i].decision="Confirmed";model.save() }
                            Button("Dismiss") { model.observations[i].decision="Dismissed";model.save() }
                        }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                }
            } else if section == 3 {
                Text("Your learning trail").font(.title2.bold())
                Text("Patterns, not labels. These counts describe saved observations and the current practice set; they are not a mastery score.")
                HStack {
                    Label("\(model.observations.filter{$0.isDemo != true}.count) observations",systemImage:"lightbulb")
                    Label("\(model.answers.filter{$0 >= 0}.count) answers",systemImage:"checkmark.circle")
                }.padding().background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                Text("Practice date: "+(model.day.isEmpty ? "Not started" : model.day))
                Text("Confirmed interpretations: \(model.observations.filter{$0.decision == "Confirmed" && $0.isDemo != true}.count)")
                Text("Dismissed interpretations: \(model.observations.filter{$0.decision == "Dismissed" && $0.isDemo != true}.count)")
                Text("Example history is excluded from these practice results. Earlier unmarked observations retain their original status.").font(.callout)
                ForEach(model.archive.reversed()) { session in
                    Text(session.day+" · "+String(session.answers.filter{$0 >= 0}.count)+"/"+String(session.exercises.count)+" completed").font(.headline)
                }
            } else {
                Text("Your daily practice").font(.title2.bold())
                Text("Three questions: identify an assumption, choose a solution, and transfer the idea. One set per day.").font(.callout)
                Button("Create today's three exercises") { model.practice() }.disabled(!model.consent || model.busy)
                Text("Completed: \(model.answers.filter{$0 >= 0}.count)/\(model.exercises.count)")
                ForEach(model.exercises.indices,id:\.self) { i in
                    let q=model.exercises[i]
                    VStack(alignment:.leading,spacing:14) {
                        Text("Exercise \(i+1)").font(.title2.bold())
                        Button(hints.contains(i) ? "Hide hint" : "Give me a hint") { if hints.contains(i) { hints.remove(i) } else { hints.insert(i) } }.buttonStyle(.bordered)
                        if hints.contains(i) { Text("Reasoning prompt: trace a small example by hand, then try an empty, boundary, or negative input. Which assumption does each option make?").padding().background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12)) }
                        Text(q.question).font(.headline)
                        ForEach(q.choices.indices,id:\.self) { j in
                            Button { selections[i]=j } label: { HStack(alignment:.top) { Image(systemName:selections[i] == j ? "largecircle.fill.circle" : "circle"); Text(q.choices[j]).frame(maxWidth:.infinity,alignment:.leading) }.padding(10) }.buttonStyle(.bordered).disabled(model.answers.indices.contains(i) && model.answers[i] >= 0)
                        }
                        if model.answers.indices.contains(i),model.answers[i] < 0 {
                            Button("Check my answer") { if let answer=selections[i] { model.answers[i]=answer;model.save() } }.buttonStyle(.borderedProminent).disabled(selections[i] == nil)
                        }
                        if model.answers.indices.contains(i),model.answers[i] >= 0 {
                            Text(model.answers[i] == q.answer ? "Correct" : "Review the reasoning")
                            Text(q.explanation).font(.system(size:14))
                        }
                    }.padding(.vertical,8)
                }
            }
            if model.busy { HStack { ProgressView(); Button("Stop AI request") { model.cancelRequest() }.buttonStyle(.bordered) } }
            Text(model.message).font(.system(size:14)).textSelection(.enabled)
        }.font(.system(size:16)).controlSize(.large)
    }
}
