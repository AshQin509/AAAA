import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

let coachAccent = Color(red:0.12,green:0.30,blue:0.70)
struct CoachPanel: View {
    @ObservedObject var model: AppModel
    let collapse: () -> Void
    var companion: () -> Void = {}
    @State private var tab=0
    @State private var showResolved=false
    private var visibleProblems:[ErrorRecord] { LearningSelection.problems(model.records,resolved:showResolved) }
    @State private var key=""
    @State private var confirmErase=false
    var body: some View {
        VStack(spacing:0) {
            PanelTitlebar(collapse:collapse).frame(height:76)
            HStack { Spacer(); Button("Show companion",systemImage:"arrow.down.right.and.arrow.up.left") { companion() }.buttonStyle(.borderless) }.padding(.horizontal,20).padding(.bottom,8)
            HStack { Circle().fill(model.running ? coachAccent : .gray).frame(width:6,height:6); Text(model.running ? "Checking active" : "Checking paused").font(.system(size:14)); Spacer(); Button(model.running ? "Pause" : "Start",systemImage:model.running ? "pause.fill":"play.fill") { model.running ? model.pause() : model.start() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.white) }.padding(.horizontal,20).padding(.bottom,14)
            Picker("Page",selection:$tab) { Text("Coach").tag(0); Text("Habits").tag(1); Text("Practice").tag(2); Text("Progress").tag(3); Text("Settings").tag(4) }.pickerStyle(.segmented).padding(.horizontal,20).padding(.bottom,16)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if let issue=model.issue {
                        VStack(alignment:.leading,spacing:8) { Label("Attention",systemImage:"exclamationmark.triangle").foregroundStyle(.orange); Text(issue).font(.system(size:14)).textSelection(.enabled); Button("Dismiss") { model.issue=nil } }.padding(12).background(.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                    }
                    switch tab {
                    case 0:
                        Label(model.editorName,systemImage:"macwindow").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
                        HStack { Button("Choose source file…") { model.chooseSourceFile() }; Button("Use editor") { model.useEditor() } }
                        Text(model.connectionHint).font(.callout)
                        Button(model.running ? "Preview captured code" : "Preview last captured snapshot") { model.previewCapturedSource() }.disabled(model.capturedSource == nil)
                        Divider().padding(.vertical,4)
                        ReasoningView(model:model.reasoning,section:0)
                        DisclosureGroup("Java compiler diagnostics") { overview }
                    case 1: ReasoningView(model:model.reasoning,section:1)
                    case 2:
                        ReasoningView(model:model.reasoning,section:2)
                        DisclosureGroup("Earlier diagnostic-based practice") { practice }
                    case 3: ReasoningView(model:model.reasoning,section:3)
                    default: settings
                    }
                }.padding(20)
            }
            Divider()
            HStack(spacing:8) { if model.busy { ProgressView().controlSize(.mini) }; Text(model.status).font(.system(size:13)).foregroundStyle(.secondary).lineLimit(2); Spacer() }.padding(12)
        }.frame(width:620,height:720).background(Color.white).preferredColorScheme(.light).font(.system(size:15)).tint(coachAccent)
        .onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()) { _ in model.permissionGranted=EditorReader.trusted }
        .confirmationDialog("Clear all diagnostic and answer records? This cannot be undone.",isPresented:$confirmErase) { Button("Clear all learning records",role:.destructive) { model.erase(); model.reasoning.clearLearning() } }
    }
    var overview: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:18) {
                Label(model.editorName,systemImage:"macwindow").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
                if !model.currentFile.isEmpty { Text(model.currentFile).font(.system(size:14,design:.monospaced)).foregroundStyle(coachAccent) }
                Text(model.connectionHint).font(.callout).foregroundStyle(.secondary)
                if !model.permissionGranted {
                    Text("Editor mode needs Accessibility permission. It reads Java text without screenshots. You can instead select a saved file in Settings without this permission.").font(.system(size:14)).foregroundStyle(.secondary)
                    Button("Allow editor access…") { model.requestPermission() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.white)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
            HStack(spacing:12) {
                problemFilter("Current problems",count:model.activeCount,resolved:false)
                problemFilter("History",count:model.historyCount,resolved:true)
            }
            Text(showResolved ? "Resolved history":"Current unresolved problems").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Text("Shows matching problems from the latest 500 records. The last results remain visible when disconnected.").font(.system(size:13)).foregroundStyle(.secondary)
            if visibleProblems.isEmpty {
                Label(showResolved ? "No resolved history yet":"No unresolved problems recorded",systemImage:showResolved ? "clock":"checkmark.circle").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(visibleProblems) { record in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(record.active ? "Unresolved":"Resolved").foregroundStyle(record.active ? .orange : coachAccent); Text("· \(record.diagnostic.category)") }.font(.system(size:14))
                        Text("\(record.diagnostic.file):\(record.diagnostic.line)").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                        if let sourceLine=record.diagnostic.sourceLine {
                            Text(sourceLine).font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                        }
                        Button("Practice this topic") { model.selectTopic(record.diagnostic.category);model.selectReference(record.id);tab=2 }.font(.system(size:14))

                        Text(record.diagnostic.code + ": " + record.diagnostic.message).font(.system(size:13)).foregroundStyle(.secondary).textSelection(.enabled)
                        DisclosureGroup("Explain with AI · preview data first") {
                            VStack(alignment:.leading,spacing:10) {
                                Text("This diagnostic will be sent to the selected AI provider. No full source file or separate path field is attached. Diagnostic text itself may contain names, paths, or code fragments. Review it first.").font(.system(size:13)).foregroundStyle(.secondary)
                                Text((try? DatabricksClient.explanationPreview(record.diagnostic)) ?? "Preview unavailable").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                                Toggle("Allow sending previewed data this session",isOn:$model.onlineConsent).font(.system(size:14))
                                Button(model.explainingID == record.id ? "Explaining…":"Send diagnostic and explain") { model.explain(record.diagnostic) }.disabled(!model.onlineConsent || !model.keyPresent || model.generating)
                                if !model.keyPresent { Text("Save an API credential in Settings first.").font(.system(size:13)) }
                                if model.explainingID == record.id { Button("Cancel request") { model.cancelQuiz() } }
                                if let explanation=model.explanations[record.id] {
                                    explanationSection("What this means",explanation.summary)
                                    explanationSection("Possible causes",explanation.cause)
                                    explanationSection("How to fix it",explanation.fix)
                                    Text(explanation.example).font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                                    explanationSection("Verify this",explanation.caveat)
                                }
                            }.padding(.top,8)
                        }.font(.system(size:14))

                    }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                }
            }
        }
    }
    func explanationSection(_ title:String,_ text:String) -> some View { VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:14,weight:.semibold)); Text(text).font(.system(size:14)).textSelection(.enabled) } }
    func problemFilter(_ label:String,count:Int,resolved:Bool) -> some View {
        Button { showResolved=resolved } label: {
            VStack(alignment:.leading,spacing:7) {
                Text("\(count)").font(.system(size:26,weight:.semibold,design:.rounded)).foregroundStyle(coachAccent)
                Text(label).font(.system(size:14)).foregroundStyle(.primary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
                .background(showResolved==resolved ? coachAccent.opacity(0.12):.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(showResolved==resolved ? coachAccent:.clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(label + "，" + String(count) + " items")
    }
    func referenceView(_ reference:Diagnostic,heading:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(heading).font(.system(size:14,weight:.semibold))
            Text(reference.category).font(.system(size:14)).foregroundStyle(coachAccent)
            Text(reference.file + " · line " + String(reference.line) + "").font(.system(size:14,design:.monospaced)).textSelection(.enabled)
            if let sourceLine=reference.sourceLine {
                Text(sourceLine).font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                Text("Locally saved diagnostic line. Not sent to the question model.").font(.system(size:13)).foregroundStyle(.secondary)
            } else { Text("This older record has no source snapshot. Only its saved filename and line number are shown.").font(.system(size:13)).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
    var practice: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Build understanding, one insight at a time.").font(.title3.bold())
            Text("Your learning patterns").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Text("Choose a topic to generate practice. Diagnostic locations stay local. Questions use topic statistics, without sending your source code.").font(.system(size:14)).foregroundStyle(.secondary)
            ForEach(model.stats,id:\.topic) { stat in
                Button { model.selectTopic(stat.topic) } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Text(stat.topic).font(.callout)
                            Text("\(stat.occurrences) occurrences · \(stat.correct)/\(stat.answered) correct").font(.system(size:14)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:model.practiceTopic==stat.topic ? "checkmark.circle.fill":"circle").foregroundStyle(coachAccent)
                    }.padding(12).background(model.practiceTopic==stat.topic ? coachAccent.opacity(0.12):.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
                }.buttonStyle(.plain)
            }
            if let topic=model.practiceTopic { Text("Practice topic: " + topic).font(.system(size:14)).foregroundStyle(coachAccent) }
            if !model.practiceReferences.isEmpty {
                Picker("Related diagnostic",selection:Binding(get:{ model.practiceReference?.id ?? "" },set:{ model.selectReference($0) })) {
                    ForEach(model.practiceReferences) { diagnostic in
                        Text(diagnostic.file + " · line " + String(diagnostic.line) + "").tag(diagnostic.id)
                    }
                }
            }
            if model.quiz == nil, let reference=model.practiceReference { referenceView(reference,heading:"Question topic from this diagnostic") }
            if !model.practiceStats.isEmpty && model.practiceReference == nil { Text("No diagnostic reference for this topic. Select another topic or check source again.").font(.system(size:14)).foregroundStyle(.secondary) }

            Text("Only the topic statistics below are sent. No file paths, raw diagnostics, or source code. Each click requests one question and may incur API charges.").font(.system(size:14)).foregroundStyle(.secondary)
            DisclosureGroup("Preview request data") { Text(model.payload).font(.system(size:14,design:.monospaced)).textSelection(.enabled).padding(.top,8) }
            Toggle("Allow sending previewed data this session",isOn:$model.onlineConsent).tint(coachAccent)
            HStack { Button(model.generating ? "Generating…":"Generate practice question",systemImage:"sparkles") { model.generate() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.white).disabled(!model.onlineConsent || !model.keyPresent || model.practiceStats.isEmpty || model.practiceReference == nil || model.generating); if model.generating { Button("Cancel") { model.cancelQuiz() } } }
            if !model.keyPresent { Text("Save your own API credential in Settings.").font(.system(size:14)).foregroundStyle(.secondary) }
            if model.stats.isEmpty { Text("Start checking Java source. Recorded problems unlock practice.").font(.system(size:14)).foregroundStyle(.secondary) }
            if let quiz=model.quiz {
                Divider()
                if let reference=model.quizReference { referenceView(reference,heading:"Related diagnostic (snapshot at generation time)") }
                Text(quiz.question).font(.system(size:14,design:.monospaced)).textSelection(.enabled)
                ForEach(0..<quiz.choices.count,id:\.self) { i in
                    Button { model.selected=i } label: {
                        HStack(alignment:.top) { Image(systemName:model.selected == i ? "largecircle.fill.circle":"circle"); Text("\(String(UnicodeScalar(65+i)!)). \(quiz.choices[i])").frame(maxWidth:.infinity,alignment:.leading) }.padding(12).foregroundStyle(model.submitted && quiz.answer == i ? coachAccent : .primary).background(model.selected == i ? coachAccent.opacity(0.12):.blue.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain).disabled(model.submitted)
                }
                if model.submitted { Label(model.selected == quiz.answer ? "Correct!":"Keep thinking — review the explanation",systemImage:model.selected == quiz.answer ? "checkmark.circle.fill":"lightbulb").foregroundStyle(coachAccent); Text(quiz.explanation).font(.callout).textSelection(.enabled) }
                else { Button("Submit answer") { model.submit() }.disabled(model.selected == nil) }
                Text("AI questions and explanations can be wrong. Check the JDK documentation. Only your first answer is recorded.").font(.system(size:13)).foregroundStyle(.secondary)
            }
        }
    }
    var settings: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Local by default · you stay in control",systemImage:"lock.shield").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Text("Monitoring stays on your Mac. AI receives only what you choose to send.").font(.system(size:14)).foregroundStyle(.secondary)
            Divider()
            Text("Source connection").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Button("Choose source file…") { model.chooseSourceFile() }
            Button("Use Accessibility editor mode") { model.useEditor() }
            Text("If your editor cannot share code, choose a saved source file instead.").font(.system(size:14)).foregroundStyle(.secondary)
            Button("Check / request Accessibility permission…") { model.requestPermission() }
            Button("Disconnect source") { model.disconnect() }
            DisclosureGroup("Java compiler (advanced)") {
                VStack(alignment:.leading,spacing:10) {
                    Button("Detect / refresh JDK") { model.discoverJava() }
                    Text(model.javac.isEmpty ? "No JDK detected" : "Detected: "+model.javac).font(.system(size:13)).textSelection(.enabled).textFieldStyle(.roundedBorder)
                    Button("Select installed javac…") { model.chooseJavac() }
                    Link("Install a Java compiler (Temurin JDK)",destination:URL(string:"https://adoptium.net/temurin/releases/")!)
                    Text("Source is copied to a local temporary directory for a single-file check. Project dependencies are not resolved. Libraries, Lombok, and cross-file references may produce misleading diagnostics. Verify in your IDE.").font(.system(size:13)).foregroundStyle(.secondary)
                }.padding(.top,8)
            }
            Divider()
            ReasoningView(model:model.reasoning,section:4)
            DisclosureGroup("Earlier provider tools (not used by the demo coach)") {
                VStack(alignment:.leading,spacing:16) {
            Text("AI · manual requests only").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Picker("Provider",selection:$model.provider) { ForEach(AIProvider.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.onChange(of:model.provider) { _ in key="" }
            Text("Selected provider: "+model.provider.rawValue).font(.system(size:14))
            Text("OpenAI calls a cloud model over the internet. It does not run locally. Supply your own API key, model access, and available API credits. Do not assume a ChatGPT subscription includes API usage.").font(.system(size:13)).foregroundStyle(.secondary)
            SecureField("API credential (stored in Keychain)",text:$key).textFieldStyle(.roundedBorder)
            Button("Paste credential") {
                if let text=NSPasteboard.general.string(forType:.string), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    key=text.trimmingCharacters(in:.whitespacesAndNewlines)
                } else { model.issue="No text is available on the clipboard." }
            }
            Text("Use Command-V or Paste. The credential is written to Keychain only when you click Save.").font(.system(size:13)).foregroundStyle(.secondary)
            HStack { Button("Save credential") { model.saveKey(key); key="" }.disabled(key.isEmpty); Text(model.keyPresent ? "Saved":"Not saved").font(.system(size:14)).foregroundStyle(.secondary); Spacer(); Button("Delete credential",role:.destructive) { model.deleteKey(); key="" } }
            TextField("Model ID with structured output support",text:$model.model).textFieldStyle(.roundedBorder)
            Text(model.provider == .openai ? "Service: api.openai.com · Responses API · store=false" : "Workspace: " + DatabricksConfig.host).font(.system(size:13)).textSelection(.enabled)
            Toggle("Allow sending previewed data this session",isOn:$model.onlineConsent).tint(coachAccent)
            Button("Test connection (may incur charges)") { model.testConnection() }.disabled(!model.onlineConsent || !model.keyPresent || model.generating)
            if model.generating { Button("Cancel AI request") { model.cancelQuiz() } }
            if !model.aiStatus.isEmpty { Text(model.aiStatus).font(.system(size:14)).foregroundStyle(.secondary) }
            Text("Questions send anonymous statistics. Explanations send only the diagnostic you select and preview. Requests are manual and may cost money. OpenAI uses store=false; this does not mean zero retention. Databricks logging and retention depend on workspace settings. Credentials are stored separately in Keychain. Switching providers revokes consent.").font(.system(size:13)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Local learning records").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.indigo)
            Text("History is saved on this Mac and may include code excerpts.").font(.system(size:14)).foregroundStyle(.secondary)
            Button("Clear all learning records…",role:.destructive) { confirmErase=true }
            Text("Clearing removes compiler records, reasoning observations, and practice history. Keychain credentials are kept.").font(.system(size:13)).foregroundStyle(.secondary)
        }
    }
}

struct CompactCoach: View {
    @ObservedObject var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse=false
    var body:some View {
        Image(nsImage:CompanionArtwork.image)
            .resizable().scaledToFit().padding(4).frame(width:88,height:88)
            .opacity(pulse ? 0.55 : 1)
            .onChange(of:model.activeCount) { value in
                guard value > 0,!reduceMotion else { return }
                withAnimation(.easeInOut(duration:0.25).repeatCount(4,autoreverses:true)) { pulse=true }
                DispatchQueue.main.asyncAfter(deadline:.now()+1.2) { pulse=false }
            }
            .accessibilityLabel("Don't Crash assistant. Click to open; right-click for Quit.")
    }
}
