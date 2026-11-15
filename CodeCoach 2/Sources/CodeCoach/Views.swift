import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

let coachAccent = Color(red:0.35,green:0.85,blue:0.72)
struct CoachPanel: View {
    @ObservedObject var model: AppModel
    let collapse: () -> Void
    @State private var tab=0
    @State private var showResolved=false
    private var visibleProblems:[ErrorRecord] { LearningSelection.problems(model.records,resolved:showResolved) }
    @State private var key=""
    @State private var confirmErase=false
    var body: some View {
        VStack(spacing:0) {
            PanelTitlebar(collapse:collapse).frame(height:76)
            HStack { Circle().fill(model.running ? coachAccent : .gray).frame(width:6,height:6); Text(model.running ? "实时检查已开启" : "实时检查已暂停").font(.caption); Spacer(); Button(model.running ? "暂停" : "开始",systemImage:model.running ? "pause.fill":"play.fill") { model.running ? model.pause() : model.start() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.black) }.padding(.horizontal,20).padding(.bottom,14)
            Picker("页面",selection:$tab) { Text("概览").tag(0); Text("练习").tag(1); Text("隐私与设置").tag(2) }.pickerStyle(.segmented).padding(.horizontal,20).padding(.bottom,16)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if let issue=model.issue {
                        VStack(alignment:.leading,spacing:8) { Label("需要留意",systemImage:"exclamationmark.triangle").foregroundStyle(.orange); Text(issue).font(.caption).textSelection(.enabled); Button("关闭提示") { model.issue=nil } }.padding(12).background(.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                    }
                    switch tab { case 0: overview; case 1: practice; default: settings }
                }.padding(20)
            }
            Divider()
            HStack(spacing:8) { if model.busy { ProgressView().controlSize(.mini) }; Text(model.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2); Spacer() }.padding(12)
        }.frame(width:440,height:650).background(Color(red:0.065,green:0.085,blue:0.105)).preferredColorScheme(.dark)
        .onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()) { _ in model.permissionGranted=EditorReader.trusted }
        .confirmationDialog("清除所有项目的错误和答题记录？此操作无法撤销。",isPresented:$confirmErase) { Button("清除所有学习记录",role:.destructive) { model.erase() } }
    }
    var overview: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:12) {
                Label(model.editorName,systemImage:"macwindow").font(.headline)
                if !model.currentFile.isEmpty { Text(model.currentFile).font(.system(size:12,design:.monospaced)).foregroundStyle(coachAccent) }
                Text(model.connectionHint).font(.callout).foregroundStyle(.secondary)
                if !model.permissionGranted {
                    Text("首次使用需要你允许辅助功能访问，才能读取当前编辑器的代码。只检查 Java 编辑区，不截屏、不上传代码。").font(.caption).foregroundStyle(.secondary)
                    Button("允许实时读取…") { model.requestPermission() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.black)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
            Text("使用方法：点击开始 → 切换到 Java 编辑器 → 点击代码区域。停下输入后自动检查，不用保存或导入文件。").font(.caption).foregroundStyle(.secondary)
            Text("通用模式并非所有编辑器都支持。只检查当前可读取的单个文件；项目依赖相关报错请在 IDE 中确认。").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing:12) {
                problemFilter("当前问题",count:model.activeCount,resolved:false)
                problemFilter("历史问题",count:model.historyCount,resolved:true)
            }
            Text(showResolved ? "已解决的历史问题":"尚未解决的当前问题").font(.headline)
            Text("仅显示最近 500 条记录中此筛选对应的问题；未连接编辑区时保留上一份检查结果。").font(.caption2).foregroundStyle(.secondary)
            if visibleProblems.isEmpty {
                Label(showResolved ? "还没有已解决的历史问题":"当前没有未解决的问题记录",systemImage:showResolved ? "clock":"checkmark.circle").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(visibleProblems) { record in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(record.active ? "未解决":"已解决").foregroundStyle(record.active ? .orange : coachAccent); Text("· \(record.diagnostic.category)") }.font(.caption)
                        Text("\(record.diagnostic.file):\(record.diagnostic.line)").font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                        if let sourceLine=record.diagnostic.sourceLine {
                            Text(sourceLine).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                        }
                        Button("按此知识点练习") { model.selectTopic(record.diagnostic.category);model.selectReference(record.id);tab=1 }.font(.caption)

                        Text(record.diagnostic.code + ": " + record.diagnostic.message).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        DisclosureGroup("AI 解释此错误 · 先预览发送内容") {
                            VStack(alignment:.leading,spacing:10) {
                                Text("将把这条诊断文字发送到你的 Databricks 工作区。不附加源码全文或文件路径；诊断本身可能包含变量名、类型名和片段。").font(.caption2).foregroundStyle(.secondary)
                                Text((try? DatabricksClient.explanationPreview(record.diagnostic)) ?? "无法预览").font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                                Toggle("允许本次启动期间使用 Databricks",isOn:$model.onlineConsent).font(.caption)
                                Button(model.explainingID == record.id ? "正在解释…":"发送这条诊断并解释") { model.explain(record.diagnostic) }.disabled(!model.onlineConsent || !model.keyPresent || model.generating)
                                if !model.keyPresent { Text("请先在设置中保存 Databricks Token。").font(.caption2) }
                                if model.explainingID == record.id { Button("取消请求") { model.cancelQuiz() } }
                                if let explanation=model.explanations[record.id] {
                                    explanationSection("这是什么",explanation.summary)
                                    explanationSection("可能原因",explanation.cause)
                                    explanationSection("如何修复",explanation.fix)
                                    Text(explanation.example).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                                    explanationSection("需要核对",explanation.caveat)
                                }
                            }.padding(.top,8)
                        }.font(.caption)

                    }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                }
            }
        }
    }
    func explanationSection(_ title:String,_ text:String) -> some View { VStack(alignment:.leading,spacing:4) { Text(title).font(.caption.bold()); Text(text).font(.caption).textSelection(.enabled) } }
    func problemFilter(_ label:String,count:Int,resolved:Bool) -> some View {
        Button { showResolved=resolved } label: {
            VStack(alignment:.leading,spacing:7) {
                Text("\(count)").font(.system(size:26,weight:.semibold,design:.rounded)).foregroundStyle(coachAccent)
                Text(label).font(.caption).foregroundStyle(.primary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(14)
                .background(showResolved==resolved ? coachAccent.opacity(0.12):.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(showResolved==resolved ? coachAccent:.clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(label + "，" + String(count) + " 个")
    }
    func referenceView(_ reference:Diagnostic,heading:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(heading).font(.caption.bold())
            Text(reference.category).font(.caption).foregroundStyle(coachAccent)
            Text(reference.file + " · 第 " + String(reference.line) + " 行").font(.system(size:12,design:.monospaced)).textSelection(.enabled)
            if let sourceLine=reference.sourceLine {
                Text(sourceLine).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                Text("本机保留的报错行快照，未发送给出题模型。").font(.caption2).foregroundStyle(.secondary)
            } else { Text("旧记录未保留代码片段；仅展示当时记录的文件和行号。").font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
    var practice: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("把错误变成下一次的直觉。").font(.title3.bold())
            Text("你的学习线索").font(.headline)
            Text("选择知识点分类，再生成对应练习。关联错误的位置仅在本机展示；新题按该知识点生成，不会把你的整段代码发给模型。").font(.caption).foregroundStyle(.secondary)
            ForEach(model.stats,id:\.topic) { stat in
                Button { model.selectTopic(stat.topic) } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Text(stat.topic).font(.callout)
                            Text("出现 \(stat.occurrences) 次 · 答对 \(stat.correct)/\(stat.answered)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:model.practiceTopic==stat.topic ? "checkmark.circle.fill":"circle").foregroundStyle(coachAccent)
                    }.padding(12).background(model.practiceTopic==stat.topic ? coachAccent.opacity(0.12):.white.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
                }.buttonStyle(.plain)
            }
            if let topic=model.practiceTopic { Text("本次主题：" + topic).font(.caption).foregroundStyle(coachAccent) }
            if !model.practiceReferences.isEmpty {
                Picker("关联错误",selection:Binding(get:{ model.practiceReference?.id ?? "" },set:{ model.selectReference($0) })) {
                    ForEach(model.practiceReferences) { diagnostic in
                        Text(diagnostic.file + " · 第 " + String(diagnostic.line) + " 行").tag(diagnostic.id)
                    }
                }
            }
            if model.quiz == nil, let reference=model.practiceReference { referenceView(reference,heading:"将根据此错误所属知识点出题") }
            if !model.practiceStats.isEmpty && model.practiceReference == nil { Text("此分类暂无可定位的错误记录；请选择其他分类或重新检查代码后再出题。").font(.caption).foregroundStyle(.secondary) }

            Text("只发送下面的匿名知识点统计，不发送文件路径、报错原文或源码。每次点击只请求一道题，可能产生 Databricks API 费用。").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("查看将发送的数据") { Text(model.payload).font(.system(size:10,design:.monospaced)).textSelection(.enabled).padding(.top,8) }
            Toggle("允许本次启动期间使用 Databricks",isOn:$model.onlineConsent).tint(coachAccent)
            HStack { Button(model.generating ? "正在生成…":"生成个性化练习",systemImage:"sparkles") { model.generate() }.buttonStyle(.borderedProminent).tint(coachAccent).foregroundStyle(.black).disabled(!model.onlineConsent || !model.keyPresent || model.practiceStats.isEmpty || model.practiceReference == nil || model.generating); if model.generating { Button("取消") { model.cancelQuiz() } } }
            if !model.keyPresent { Text("请在设置中保存自己的 Databricks Token。").font(.caption).foregroundStyle(.secondary) }
            if model.stats.isEmpty { Text("开启实时检查并连接 Java 编辑区；记录问题后即可练习。").font(.caption).foregroundStyle(.secondary) }
            if let quiz=model.quiz {
                Divider()
                if let reference=model.quizReference { referenceView(reference,heading:"本题关联的原始错误（出题时快照）") }
                Text(quiz.question).font(.system(size:13,design:.monospaced)).textSelection(.enabled)
                ForEach(0..<quiz.choices.count,id:\.self) { i in
                    Button { model.selected=i } label: {
                        HStack(alignment:.top) { Image(systemName:model.selected == i ? "largecircle.fill.circle":"circle"); Text("\(String(UnicodeScalar(65+i)!)). \(quiz.choices[i])").frame(maxWidth:.infinity,alignment:.leading) }.padding(12).foregroundStyle(model.submitted && quiz.answer == i ? coachAccent : .primary).background(model.selected == i ? coachAccent.opacity(0.12):.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain).disabled(model.submitted)
                }
                if model.submitted { Label(model.selected == quiz.answer ? "答对了":"继续想一想，下次就会了",systemImage:model.selected == quiz.answer ? "checkmark.circle.fill":"lightbulb").foregroundStyle(coachAccent); Text(quiz.explanation).font(.callout).textSelection(.enabled) }
                else { Button("提交答案") { model.submit() }.disabled(model.selected == nil) }
                Text("AI 题目和解析可能出错，请结合 JDK 文档核对。每道题只记录首次提交。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    var settings: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("默认本地 · 始终由你开启",systemImage:"lock.shield").font(.headline)
            Text("授权并开始后，使用辅助功能读取当前支持的编辑器中的 Java 文本，包含未保存内容。不截图、不监听键盘、不上传源码。暂停即停止读取；每次启动默认暂停。关闭联网开关会取消 AI 请求，但不能撤回已发送的数据。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("实时连接").font(.headline)
            Button("检查 / 请求辅助功能权限…") { model.requestPermission() }
            Button("断开当前编辑区") { model.disconnect() }
            Text("系统授权需要你亲自完成。部分编辑器需要开启其无障碍支持才能提供代码；读不到时会明确提示，无法保证适用于所有 IDE。").font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Java 检查组件（高级）") {
                VStack(alignment:.leading,spacing:10) {
                    TextField("JDK bin/javac 路径",text:$model.javac).textFieldStyle(.roundedBorder)
                    Button("选择已安装的 javac…") { model.chooseJavac() }
                    Link("安装 Java 检查组件（Temurin JDK）",destination:URL(string:"https://adoptium.net/temurin/releases/")!)
                    Text("无需导入项目。当前模式将编辑区内容复制到本机临时目录进行单文件检查，不解析整个项目；外部依赖、Lombok 等可能产生不准确提示，需在 IDE 中确认。").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top,8)
            }
            Divider()
            Text("Databricks · 仅手动请求").font(.headline)
            SecureField("输入 Databricks Token（仅存入系统钥匙串）",text:$key).textFieldStyle(.roundedBorder)
            Button("从剪贴板粘贴 Token") {
                if let text=NSPasteboard.general.string(forType:.string), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    key=text.trimmingCharacters(in:.whitespacesAndNewlines)
                } else { model.issue="剪贴板中没有可粘贴的文字。" }
            }
            Text("支持 ⌘V；也可点击上方粘贴按钮。粘贴后点击保存，才会写入钥匙串。").font(.caption2).foregroundStyle(.secondary)
            HStack { Button("保存 Token") { model.saveKey(key); key="" }.disabled(key.isEmpty); Text(model.keyPresent ? "已保存":"尚未保存").font(.caption).foregroundStyle(.secondary); Spacer(); Button("删除 Token",role:.destructive) { model.deleteKey(); key="" } }
            TextField("支持结构化输出的模型 ID",text:$model.model).textFieldStyle(.roundedBorder)
            Text("工作区：" + DatabricksConfig.host).font(.caption2).textSelection(.enabled)
            Toggle("允许本次启动期间使用 Databricks",isOn:$model.onlineConsent).tint(coachAccent)
            Button("测试连接（可能产生 API 费用）") { model.testConnection() }.disabled(!model.onlineConsent || !model.keyPresent || model.generating)
            if model.generating { Button("取消 AI 请求") { model.cancelQuiz() } }
            if !model.aiStatus.isEmpty { Text(model.aiStatus).font(.caption).foregroundStyle(.secondary) }
            Text("出题只发送匿名统计；错误解释仅发送你选择并预览的诊断文字。两者均手动请求，可能产生费用。工作区的日志、保留和数据策略由你的 Databricks 配置决定。Token 单独存入钥匙串，与原 OpenAI Key 分开保存。").font(.caption2).foregroundStyle(.secondary)
            Divider()
            Text("本机学习记录").font(.headline)
            Text("SQLite 保存在 ~/Library/Application Support/CodeCoach。包含文件名、行号、检查信息、出现次数和答题统计。编译时会生成本机源码临时副本，结束清理；意外退出可能残留。数据库不保存源码全文，但会保存每条新诊断对应的一行代码快照（最多1000字符），用于已解决记录和练习定位；检查信息也可能含代码片段。无遥测，系统备份可能保留历史副本。").font(.caption2).foregroundStyle(.secondary)
            Button("清除所有项目学习记录…",role:.destructive) { confirmErase=true }
            Text("清除记录不会删除 Token；删除 Token 需单独点击上方按钮。").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct CompactCoach: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack(alignment:.bottomTrailing) {
            Circle().fill(Color(red:0.065,green:0.11,blue:0.13))
                .overlay(Circle().strokeBorder(coachAccent.opacity(0.45),lineWidth:1))
            Image(systemName:"curlybraces").font(.system(size:19,weight:.semibold))
                .foregroundStyle(coachAccent).frame(maxWidth:.infinity,maxHeight:.infinity)
            if model.running {
                Circle().fill(model.activeCount > 0 ? .orange : coachAccent)
                    .frame(width:6,height:6).overlay(Circle().stroke(Color(red:0.065,green:0.11,blue:0.13),lineWidth:2)).padding(2)
            }
        }.frame(width:40,height:40).padding(2).frame(width:44,height:44).preferredColorScheme(.dark)

    }
}
