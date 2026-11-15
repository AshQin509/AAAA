import AppKit
import ApplicationServices
#if SWIFT_PACKAGE
import CodeCoachCore
#endif

struct EditorCode: Sendable {
    let application: String
    let identity: String
    let filename: String
    let text: String
}
enum EditorReadResult:Sendable {
    case code(EditorCode)
    case unavailable(String)
    case ownApplication
}
struct EditorTarget:Sendable {
    let pid:pid_t
    let bundle:String
    let name:String
    let isOwnApplication:Bool
}
enum EditorReader {
    static var trusted: Bool { AXIsProcessTrusted() }
    @MainActor static func requestPermission() {
        let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _=AXIsProcessTrustedWithOptions(options)
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element,0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success else { return nil }
        return value
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value,to:AXUIElement.self)
    }
    @MainActor static func foregroundTarget() -> EditorTarget? {
        guard let front=NSWorkspace.shared.frontmostApplication, let bundle=front.bundleIdentifier else { return nil }
        return EditorTarget(pid:front.processIdentifier,bundle:bundle,name:front.localizedName ?? "编辑器",isOwnApplication:front.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }
    /// All potentially blocking AX messages run on a worker, never on the UI actor.
    static func read(target:EditorTarget?) -> EditorReadResult {
        guard trusted else { return .unavailable("请先允许辅助功能访问，才能读取正在编辑的代码。") }
        guard let target else { return .unavailable("请切换到代码编辑器。") }
        if target.isOwnApplication { return .ownApplication }
        let bundle=target.bundle
        // Never read browsers, chat, password managers, terminals or arbitrary applications.
        let supported = bundle.hasPrefix("com.jetbrains.") || ["com.microsoft.VSCode","com.microsoft.VSCodeInsiders","com.vscodium","com.todesktop.230313mzl4w4u92","dev.zed.Zed","com.sublimetext.4","com.sublimetext.3","org.eclipse.platform.ide","org.eclipse.eclipse","org.netbeans.ide","com.apple.TextEdit"].contains(bundle)
        guard supported else { return .unavailable("切换到 Java 编辑器后继续；当前应用不会被读取。") }
        let app=AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app,0.2)
        guard let focused=element(attribute(app,kAXFocusedUIElementAttribute)), let role=attribute(focused,kAXRoleAttribute) as? String, role == kAXTextAreaRole as String else { return .unavailable("请点击编辑器中的 Java 代码区域。若仍无法连接，此编辑器可能未提供可读取的代码。") }
        let window=element(attribute(app,kAXFocusedWindowAttribute))
        let document=window.flatMap { attribute($0,kAXDocumentAttribute) as? String }
        let title=window.flatMap { attribute($0,kAXTitleAttribute) as? String } ?? ""
        let javaDocument=document.flatMap(URL.init(string:))?.pathExtension.lowercased() == "java"
        let javaTitle=title.range(of:#"\.java\b"#,options:.regularExpression) != nil
        let untitled=["untitled","无标题","未命名"].contains { title.localizedCaseInsensitiveContains($0) }
        guard javaDocument || javaTitle || untitled else { return .unavailable("当前窗口不是 Java 源文件，不会读取其中内容。请打开 .java 文件。") }
        guard let text=attribute(focused,kAXValueAttribute) as? String, !text.isEmpty else { return .unavailable("当前编辑器没有提供代码文本。VS Code 可尝试在设置中启用无障碍支持；本模式不会截图。") }
        do {
            let filename=try LiveSource.filename(text:text,document:document,title:title)
            return .code(EditorCode(application:target.name,identity:Diagnostic.digest(bundle+"|"+(document ?? title)),filename:filename,text:text))
        } catch { return .unavailable(error.localizedDescription) }
    }
}
