import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

@MainActor final class AppModel: ObservableObject {
    @Published var running = false
    @Published var busy = false
    @Published var status = "点击开始，连接当前 Java 编辑区域。"
    @Published var issue: String?
    @Published var editorName = "等待连接编辑器"
    @Published var currentFile = ""
    @Published var connectionHint = "无需选择文件夹，也不上传文件。"
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
    @Published var model: String { didSet { defaults.set(model, forKey:"databricksModel") } }
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
    private var quizTopic = "Java 编译基础"
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
        model=UserDefaults.standard.string(forKey:"databricksModel") ?? DatabricksConfig.model
        javac=JavaAnalyzer.findJavac() ?? UserDefaults.standard.string(forKey:"javac") ?? ""
        do {
            let dir=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("CodeCoach",isDirectory:true)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            store=try ErrorStore(url:dir.appendingPathComponent("learning.sqlite"))
            keyPresent = try Keychain.contains(service:DatabricksConfig.credentialService)
            try reload()
        } catch { issue=error.localizedDescription }
    }
    func configurationChanged() { if running { pause(); status="检查配置已修改，请重新开始。" } }
    func requestPermission() {
        EditorReader.requestPermission()
        permissionGranted=EditorReader.trusted
        status="请在系统设置中允许 Code Coach 的辅助功能访问，然后点击开始。"
    }
    func chooseJavac() {
        let picker=NSOpenPanel(); picker.canChooseDirectories=false; picker.canChooseFiles=true; picker.message="选择 JDK 的 Contents/Home/bin/javac（不要选择系统占位程序）。"
        if picker.runModal() == .OK, let url=picker.url { javac=url.path }
    }
    func start() {
        permissionGranted=EditorReader.trusted
        guard permissionGranted else { requestPermission(); return }
        guard store != nil else { issue="学习记录暂不可用，请重新打开应用。"; return }
        guard !javac.isEmpty, FileManager.default.isExecutableFile(atPath:javac) else { issue="需要先安装 Java 检查组件（JDK）。请在设置中查看安装帮助。"; return }
        pause(); running=true; issue=nil; status="切换到 Java 编辑器并点击代码区域。"
        let token=UUID(); generation=token; let flag=CancellationFlag(); cancel=flag; let compiler=javac
        watch=Task { [weak self] in
            var candidate=""; var lastChecked=""
            while !Task.isCancelled {
                guard let self, self.generation == token, self.running else { return }
                let target=EditorReader.foregroundTarget()
                let reading=await Task.detached(priority:.utility) { EditorReader.read(target:target) }.value
                guard self.generation == token, self.running, !Task.isCancelled else { return }
                switch reading {
                case .ownApplication: break
                case .unavailable(let hint):
                    self.connectionHint=hint; self.status="等待可读取的 Java 编辑区域"; self.editorName="尚未连接"; self.currentFile=""
                    candidate=""; lastChecked=""
                case .code(let source):
                    if self.editorID != source.identity {
                        self.cancelQuiz(); self.chosenTopic=nil; self.chosenReferenceID=nil; self.quizReference=nil; self.explanations=[:]; self.quiz=nil; self.selected=nil; self.submitted=false
                        self.editorID=source.identity
                        do { try self.reload() } catch { self.issue=error.localizedDescription }
                    }
                    let fingerprint=Diagnostic.digest(source.identity+"|"+source.text)
                    self.editorName=source.application; self.currentFile=source.filename
                    self.connectionHint="正在读取当前编辑区，未保存的修改也会检查。"
                    if fingerprint != lastChecked {
                        if candidate == fingerprint {
                            self.busy=true; self.status="检查当前代码…"
                            do {
                                let results=try await Task.detached(priority:.utility) { try LiveSource.analyze(text:source.text,filename:source.filename,javac:compiler,cancellation:flag) }.value
                                guard self.generation == token, self.running, !Task.isCancelled else { return }
                                self.busy=false
                                // Never publish a result for text that changed during compilation.
                                let latestTarget=EditorReader.foregroundTarget()
                                let latestReading=await Task.detached(priority:.utility) { EditorReader.read(target:latestTarget) }.value
                                guard self.generation == token, self.running, !Task.isCancelled else { return }
                                guard case .code(let latest)=latestReading, latest.identity == source.identity, latest.text == source.text else { candidate=""; continue }
                                if self.editorID != source.identity {
                                    self.cancelQuiz(); self.chosenTopic=nil; self.chosenReferenceID=nil; self.quizReference=nil; self.explanations=[:]; self.quiz=nil; self.selected=nil; self.submitted=false
                                    self.editorID=source.identity
                                }
                                try self.store?.reconcile(project:self.projectID,diagnostics:results); try self.reload()
                                lastChecked=fingerprint
                                self.status=results.isEmpty ? "本次单文件检查未发现问题" : "发现 \(results.count) 条提示 · 点击查看"
                            } catch {
                                guard self.generation == token, !Task.isCancelled else { return }
                                self.issue=error.localizedDescription; self.pause(); return
                            }
                        }
                        candidate=fingerprint
                    }
                }
                try? await Task.sleep(nanoseconds:700_000_000)
            }
        }
    }
    func pause() { generation=UUID(); cancel.cancel(); watch?.cancel(); watch=nil; running=false; busy=false; status="已暂停 · 不读取编辑区" }
    func reload() throws { records=try store?.records(project:projectID) ?? []; stats=try store?.stats(project:projectID) ?? [] }
    func saveKey(_ key: String) {
        do { guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CoachError.message("请输入 Databricks Token。") }; try Keychain.save(key.trimmingCharacters(in:.whitespacesAndNewlines),service:DatabricksConfig.credentialService); keyPresent=true; issue=nil } catch { issue=error.localizedDescription }
    }
    func deleteKey() { cancelQuiz(); do { try Keychain.delete(service:DatabricksConfig.credentialService); keyPresent=false } catch { issue=error.localizedDescription } }
    func cancelQuiz() { quizGeneration=UUID(); quizTask?.cancel(); quizTask=nil; generating=false; explainingID=nil }
    func generate() {
        guard onlineConsent, !generating, !practiceStats.isEmpty else { return }
        let token=UUID(); quizGeneration=token
        guard let capturedReference=practiceReference else { issue="该分类暂无可定位的错误记录，请选择其他分类或先重新检查 Java 代码。";return }
        let capturedStats=practiceStats; let capturedProject=projectID; let capturedModel=model
        generating=true; issue=nil
        quizTask=Task {
            defer { if quizGeneration == token { generating=false } }
            do {
                guard let key=try Keychain.read(service:DatabricksConfig.credentialService) else { throw CoachError.message("请先保存 Databricks Token。") }
                let q=try await DatabricksClient().generate(stats:capturedStats,key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, projectID == capturedProject, onlineConsent else { return }
                quiz=q; quizReference=capturedReference; selected=nil; submitted=false; quizID=UUID().uuidString
                quizTopic=capturedStats.first?.topic ?? "Java 编译基础"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription } }
        }
    }
    func explain(_ diagnostic:Diagnostic) {
        guard onlineConsent, keyPresent, !generating else { return }
        let token=UUID(); quizGeneration=token
        let capturedProject=projectID, capturedModel=model
        generating=true; explainingID=diagnostic.id; issue=nil; aiStatus="正在请求错误解释…"
        quizTask=Task {
            defer { if quizGeneration == token { generating=false; explainingID=nil } }
            do {
                guard let key=try Keychain.read(service:DatabricksConfig.credentialService) else { throw CoachError.message("请先保存 Databricks Token。") }
                let result=try await DatabricksClient().explain(diagnostic,key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, projectID == capturedProject, onlineConsent else { return }
                explanations[diagnostic.id]=result; aiStatus="解释已返回 · AI 可能有误，请结合 IDE 核对"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription; aiStatus="解释请求失败，可重试" } }
        }
    }
    func testConnection() {
        guard onlineConsent, keyPresent, !generating else { return }
        let token=UUID(); quizGeneration=token; let capturedModel=model
        generating=true; issue=nil; aiStatus="正在测试 Databricks 连接…"
        quizTask=Task {
            defer { if quizGeneration == token { generating=false } }
            do {
                guard let key=try Keychain.read(service:DatabricksConfig.credentialService) else { throw CoachError.message("请先保存 Databricks Token。") }
                try await DatabricksClient().testConnection(key:key,model:capturedModel)
                guard !Task.isCancelled, quizGeneration == token, onlineConsent else { return }
                aiStatus="连接与结构化输出测试成功"
            } catch { if !Task.isCancelled && quizGeneration == token { issue=error.localizedDescription; aiStatus="连接测试失败，可重试" } }
        }
    }
    func submit() {
        guard let quiz, let selected, !submitted else { return }
        do { try store?.answer(id:quizID,project:projectID,topic:quizTopic,correct:selected == quiz.answer); submitted=true; try reload() } catch { issue=error.localizedDescription }
    }
    func erase() {
        pause(); cancelQuiz()
        do { try store?.erase(); records=[]; stats=[]; chosenTopic=nil; chosenReferenceID=nil; quizReference=nil; explanations=[:]; quiz=nil; selected=nil; submitted=false; issue=nil; status="所有项目的学习记录已清除。" } catch { issue=error.localizedDescription }
    }
    func disconnect() {
        pause(); cancelQuiz(); editorID=""; records=[]; stats=[]; chosenTopic=nil; chosenReferenceID=nil; quizReference=nil; explanations=[:]; quiz=nil
        selected=nil; submitted=false; editorName="等待连接编辑器"; currentFile=""
        connectionHint="无需选择文件夹，也不上传文件。"
    }
}
