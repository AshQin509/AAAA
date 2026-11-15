import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

@MainActor final class AppModel: ObservableObject {
    let reasoning=ReasoningModel()
    @Published var capturedSource:EditorCode?
    @Published var running = false
    @Published var busy = false
    @Published var status = "Click Start to check Java source."
    @Published var issue: String?
    @Published var editorName = "Waiting for source connection"
    @Published var currentFile = ""
    @Published var connectionHint = "Connect an editor or select a saved Java file. Files are not uploaded."
    @Published var permissionGranted = EditorReader.trusted
    @Published var records: [ErrorRecord] = []
    @Published var stats: [TopicStat] = []
    @Published var chosenTopic:String?
    @Published var chosenReferenceID:String?
    @Published var quizReference:Diagnostic?
    @Published var quiz: Quiz?
    @Published var selected: Int?
    @Published var submitted = false
    @Published var generating = false
    @Published var explanations:[String:ErrorExplanation] = [:]
    @Published var explainingID:String?
    @Published var aiStatus = ""
    @Published var onlineConsent = false { didSet { if !onlineConsent { cancelQuiz() } } }
    @Published var provider: AIProvider = .databricks { didSet {
        cancelQuiz(); onlineConsent=false; explanations=[:]; aiStatus=""
        model=defaults.string(forKey:provider.rawValue+"Model") ?? (provider == .openai ? "gpt-4.1-mini" : DatabricksConfig.model)
        do { keyPresent=try Keychain.contains(service:provider.credentialService) } catch { keyPresent=false; issue=error.localizedDescription }
    } }
    @Published var selectedFile: URL?
    @Published var model: String { didSet { cancelQuiz(); defaults.set(model, forKey:provider.rawValue+"Model") } }
    @Published var javac: String { didSet { defaults.set(javac, forKey:"javac"); configurationChanged() } }
    @Published var keyPresent = false
    private let defaults = UserDefaults.standard
    private var store: ErrorStore?
    private var watch: Task<Void,Never>?
    private var quizTask: Task<Void,Never>?
    private var cancel = CancellationFlag()
    private var generation = UUID()
    private var quizGeneration = UUID()
    private var quizID = UUID().uuidString
    private var quizTopic = "Java fundamentals"
    private var editorID = ""
    var projectID: String { "live:" + editorID }
    var activeCount: Int { LearningSelection.problems(records,resolved:false).count }
    var historyCount:Int { LearningSelection.problems(records,resolved:true).count }
    var practiceStats:[TopicStat] { LearningSelection.context(stats,topic:chosenTopic) }
    var practiceTopic:String? { practiceStats.first?.topic }
    var practiceReferences:[Diagnostic] { LearningSelection.references(records,topic:practiceTopic) }
    var practiceReference:Diagnostic? { practiceReferences.first(where: { $0.id==chosenReferenceID }) ?? practiceReferences.first }
    func selectTopic(_ topic:String) {
        guard chosenTopic != topic else { return }
        cancelQuiz();chosenTopic=topic;chosenReferenceID=nil;quiz=nil;quizReference=nil;selected=nil;submitted=false
    }
    func selectReference(_ id:String) {
        guard chosenReferenceID != id else { return }
        cancelQuiz();chosenReferenceID=id;quiz=nil;quizReference=nil;selected=nil;submitted=false
    }
    var payload: String { (try? QuizClient.preview(practiceStats)) ?? "[]" }
    init() {
        model=UserDefaults.standard.string(forKey:"DatabricksModel") ?? UserDefaults.standard.string(forKey:"databricksModel") ?? DatabricksConfig.model
        javac=JavaAnalyzer.findJavac() ?? UserDefaults.standard.string(forKey:"javac") ?? ""
        do {
            let dir=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("CodeCoach",isDirectory:true)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            store=try ErrorStore(url:dir.appendingPathComponent("learning.sqlite"))
            keyPresent = try Keychain.contains(service:provider.credentialService)
            try reload()
        } catch { issue=error.localizedDescription }
    }
    func configurationChanged() { if running { pause(); status="Compiler configuration changed. Start again." } }
    func requestPermission() {
        EditorReader.requestPermission()
        permissionGranted=EditorReader.trusted
        status="Allow Don't Crash in System Settings > Privacy & Security > Accessibility, then click Start."
    }
    func chooseSourceFile() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        panel.message="Select a source file. Works with any editor; reads saved content only."
        if panel.runModal() == .OK, let url=panel.url, EditorReader.language(url.lastPathComponent) != nil {
            disconnect(); selectedFile=url; connectionHint="File selected. Click Start to check saved content."; currentFile=url.lastPathComponent; start()
            let token=generation
            Task {
                let result=await Task.detached(priority:.utility) { EditorReader.read(file:url) }.value
                guard generation == token,running,selectedFile == url else { return }
                if case .code(let source)=result { capturedSource=source;previewCapturedSource() }
                else if case .unavailable(let reason)=result { issue=reason }
            }
        }
    }
    func useEditor() { disconnect(); selectedFile=nil; start() }
    func discoverJava() { javac=JavaAnalyzer.findJavac() ?? ""; if javac.isEmpty { issue="No installed JDK found. Install a JDK, then click Detect again." } }
    func chooseJavac() {
        let picker=NSOpenPanel(); picker.canChooseDirectories=false; picker.canChooseFiles=true; picker.message="Select the JDK's Contents/Home/bin/javac, not the system launcher."
        if picker.runModal() == .OK, let url=picker.url { javac=url.path }
    }
    func start() {
        permissionGranted=EditorReader.trusted
        guard selectedFile != nil || permissionGranted else { requestPermission(); return }
        guard store != nil else { issue="Learning records are unavailable. Reopen the app."; return }
        if let discovered=JavaAnalyzer.findJavac() { javac=discovered }

        pause(); running=true; issue=nil; status="Switch to a Java editor and click its code area, or use the selected file."
        let token=UUID(); generation=token; let flag=CancellationFlag(); cancel=flag; let compiler=javac
        watch=Task { [weak self] in
            var candidate=""; var lastChecked=""
            while !Task.isCancelled {
                guard let self, self.generation == token, self.running else { return }
                let target=EditorReader.foregroundTarget()
                let file=self.selectedFile
                let reading=await Task.detached(priority:.utility) { file.map { EditorReader.read(file:$0) } ?? EditorReader.read(target:target) }.value
                guard self.generation == token, self.running, !Task.isCancelled else { return }
                switch reading {
                case .ownApplication: break
                case .unavailable(let hint):
                    self.connectionHint=hint + (self.capturedSource == nil ? "" : " Last captured snapshot is still available for preview."); self.status="Waiting for readable Java source"; self.editorName="Disconnected"; self.currentFile=""
                    candidate=""; lastChecked=""
                case .code(let source):
                    self.capturedSource=source
                    if self.editorID != source.identity {
                        self.cancelQuiz(); self.chosenTopic=nil; self.chosenReferenceID=nil; self.quizReference=nil; self.explanations=[:]; self.quiz=nil; self.selected=nil; self.submitted=false
                        self.editorID=source.identity
                        do { try self.reload() } catch { self.issue=error.localizedDescription }
                    }
                    let fingerprint=Diagnostic.digest(source.identity+"|"+source.text)
                    self.editorName=source.application; self.currentFile=source.filename
                    self.connectionHint=file == nil ? "Reading editor source, including unsaved edits." : "Checking the selected file on disk. Save edits in your editor."
                    if fingerprint != lastChecked {
                        if candidate == fingerprint {
                            if EditorReader.language(source.filename) != "java" || compiler.isEmpty {
                                lastChecked=fingerprint; self.status="Source captured. Use Preview captured code to request reasoning analysis."
                                try? await Task.sleep(nanoseconds:700_000_000)
                                continue
                            }
                            self.busy=true; self.status="Checking source…"
                            do {
                                let results=try await Task.detached(priority:.utility) { try LiveSource.analyze(text:source.text,filename:source.filename,javac:compiler,cancellation:flag) }.value
                                guard self.generation == token, self.running, !Task.isCancelled else { return }
                                self.busy=false
                                // Never publish a result for text that changed during compilation.
                                let latestTarget=EditorReader.foregroundTarget()
                                let latestReading=await Task.detached(priority:.utility) { file.map { EditorReader.read(file:$0) } ?? EditorReader.read(target:latestTarget) }.value
                                guard self.generation == token, self.running, !Task.isCancelled else { return }
                                guard case .code(let latest)=latestReading, latest.identity == source.identity, latest.text == source.text else { candidate=""; continue }
                                if self.editorID != source.identity {
                                    self.cancelQuiz(); self.chosenTopic=nil; self.chosenReferenceID=nil; self.quizReference=nil; self.explanations=[:]; self.quiz=nil; self.selected=nil; self.submitted=false
                                    self.editorID=source.identity
                                }
                                try self.store?.reconcile(project:self.projectID,diagnostics:results); try self.reload()
                                lastChecked=fingerprint
                                self.status=results.isEmpty ? "No problems found in this single-file check" : "\(results.count) diagnostics · click to view"
                            } catch {
                                guard self.generation == token, !Task.isCancelled else { return }
                                self.busy=false
                                self.issue="Compiler check unavailable: "+error.localizedDescription+" You can still preview the captured code and request reasoning analysis."
                                lastChecked=fingerprint
                            }
                        }
                        candidate=fingerprint
                    }
                }
                try? await Task.sleep(nanoseconds:700_000_000)
            }
        }
    }
    func previewCapturedSource() {
        guard let source=capturedSource else { issue="No source captured yet. Start monitoring and focus your editor, or choose a source file."; return }
        guard source.text.utf8.count <= 30_000 else { issue="Captured file exceeds the 30 KB AI limit. Paste a smaller method into Coach."; return }
        reasoning.code=source.text;reasoning.language=EditorReader.language(source.filename) ?? "java"
        reasoning.message="Captured snapshot: "+source.filename+". Review it, then click Analyze my reasoning. Nothing has been sent."
    }
    func pause() { generation=UUID(); cancel.cancel(); watch?.cancel(); watch=nil; running=false; busy=false; status="Paused · no source reading" }
    func reload() throws { records=try store?.records(project:projectID) ?? []; stats=try store?.stats(project:projectID) ?? [] }
    func saveKey(_ key: String) {
        do { guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CoachError.message("Enter an API credential.") }; try Keychain.save(key.trimmingCharacters(in:.whitespacesAndNewlines),service:provider.credentialService); keyPresent=true; issue=nil } catch { issue=error.localizedDescription }
    }
    func deleteKey() { cancelQuiz(); do { try Keychain.delete(service:provider.credentialService); keyPresent=false } catch { issue=error.localizedDescription } }
    func cancelQuiz() { quizGeneration=UUID(); quizTask?.cancel(); quizTask=nil; generating=false; explainingID=nil }
    func generate() {
        guard onlineConsent, !generating, !practiceStats.isEmpty else { return }
        let token=UUID(); quizGeneration=token
        guard let capturedReference=practiceReference else { issue="No diagnostic reference for this topic. Select another topic or recheck Java source.";return }
        let capturedStats=practiceStats; let capturedProject=projectID; let capturedModel=model; let capturedProvider=provider
        generating=true; issue=nil
        quizTask=Task {
            defer { if quizGeneration == token { generating=false } }
            do {
                guard let key=try Keychain.read(service:capturedProvider.credentialService) else { throw CoachError.message("Save an API credential first.") }
                let q=try await DatabricksClient(provider:capturedProvider).generate(stats:capturedStats,key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, projectID == capturedProject, onlineConsent else { return }
                quiz=q; quizReference=capturedReference; selected=nil; submitted=false; quizID=UUID().uuidString
                quizTopic=capturedStats.first?.topic ?? "Java fundamentals"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription } }
        }
    }
    func explain(_ diagnostic:Diagnostic) {
        guard onlineConsent, keyPresent, !generating else { return }
        let token=UUID(); quizGeneration=token
        let capturedProject=projectID, capturedModel=model; let capturedProvider=provider
        generating=true; explainingID=diagnostic.id; issue=nil; aiStatus="Requesting explanation…"
        quizTask=Task {
            defer { if quizGeneration == token { generating=false; explainingID=nil } }
            do {
                guard let key=try Keychain.read(service:capturedProvider.credentialService) else { throw CoachError.message("Save an API credential first.") }
                let result=try await DatabricksClient(provider:capturedProvider).explain(diagnostic,key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, projectID == capturedProject, onlineConsent else { return }
                explanations[diagnostic.id]=result; aiStatus="Explanation ready · verify AI suggestions in your IDE"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription; aiStatus="Explanation failed. You can retry." } }
        }
    }
    func testConnection() {
        guard onlineConsent, keyPresent, !generating else { return }
        let token=UUID(); quizGeneration=token; let capturedModel=model; let capturedProvider=provider
        generating=true; issue=nil; aiStatus="Testing AI connection…"
        quizTask=Task {
            defer { if quizGeneration == token { generating=false } }
            do {
                guard let key=try Keychain.read(service:capturedProvider.credentialService) else { throw CoachError.message("Save an API credential first.") }
                try await DatabricksClient(provider:capturedProvider).testConnection(key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, onlineConsent else { return }
                aiStatus="Connection and structured output test succeeded"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription; aiStatus="Connection test failed. You can retry." } }
        }
    }
    func submit() {
        guard let quiz, let selected, !submitted else { return }
        do { try store?.answer(id:quizID,project:projectID,topic:quizTopic,correct:selected == quiz.answer); submitted=true; try reload() } catch { issue=error.localizedDescription }
    }
    func erase() {
        pause(); cancelQuiz()
        do { try store?.erase(); records=[]; stats=[]; chosenTopic=nil; chosenReferenceID=nil; quizReference=nil; explanations=[:]; quiz=nil; selected=nil; submitted=false; issue=nil; status="All learning records have been cleared." } catch { issue=error.localizedDescription }
    }
    func disconnect() {
        pause(); cancelQuiz(); capturedSource=nil; selectedFile=nil; editorID=""; records=[]; stats=[]; chosenTopic=nil; chosenReferenceID=nil; quizReference=nil; explanations=[:]; quiz=nil
        selected=nil; submitted=false; editorName="Waiting for source connection"; currentFile=""
        connectionHint="Connect an editor or select a saved Java file. Files are not uploaded."
    }
}
