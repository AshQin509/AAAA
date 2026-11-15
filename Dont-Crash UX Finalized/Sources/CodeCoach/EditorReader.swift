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
    static func language(_ filename:String) -> String? {
        ["java":"java","py":"python","js":"javascript","mjs":"javascript","c":"c","h":"c","cpp":"cpp","cc":"cpp","hpp":"cpp","r":"r"][URL(fileURLWithPath:filename).pathExtension.lowercased()]
    }
    static func read(file:URL) -> EditorReadResult {
        do {
            guard language(file.lastPathComponent) != nil else { throw CoachError.message("Select a Java, Python, JavaScript, C, C++, or R source file.") }
            let handle=try FileHandle(forReadingFrom:file)
            defer { try? handle.close() }
            let data=try handle.read(upToCount:2_000_001) ?? Data()
            guard data.count <= 2_000_000 else { throw CoachError.message("File exceeds 2 MB.") }
            guard let text=String(data:data,encoding:.utf8) else { throw CoachError.message("Save this source file as UTF-8.") }
            return .code(EditorCode(application:"Selected file (any editor)",identity:Diagnostic.digest(file.standardizedFileURL.path),filename:file.lastPathComponent,text:text))
        } catch { return .unavailable("Could not read the selected file: "+error.localizedDescription) }
    }

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
        return EditorTarget(pid:front.processIdentifier,bundle:bundle,name:front.localizedName ?? "Editor",isOwnApplication:front.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }
    /// All potentially blocking AX messages run on a worker, never on the UI actor.
    static func read(target:EditorTarget?) -> EditorReadResult {
        guard trusted else { return .unavailable("Allow Accessibility access to read editor source, or select a saved Java file.") }
        guard let target else { return .unavailable("Switch to a code editor.") }
        if target.isOwnApplication { return .ownApplication }
        let bundle=target.bundle
        // Never read browsers, chat, password managers, terminals or arbitrary applications.
        let supported = bundle.hasPrefix("com.jetbrains.") || ["com.microsoft.VSCode","com.microsoft.VSCodeInsiders","com.vscodium","com.todesktop.230313mzl4w4u92","dev.zed.Zed","com.sublimetext.4","com.sublimetext.3","org.eclipse.platform.ide","org.eclipse.eclipse","org.netbeans.ide","com.apple.TextEdit","com.apple.dt.Xcode"].contains(bundle)
        guard supported else { return .unavailable("Switch to a supported Java editor. This application will not be read.") }
        let app=AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app,0.2)
        guard let focused=element(attribute(app,kAXFocusedUIElementAttribute)), let role=attribute(focused,kAXRoleAttribute) as? String, role == kAXTextAreaRole as String else { return .unavailable("Click the Java code area. If it remains unreadable, use saved-file mode.") }
        let window=element(attribute(app,kAXFocusedWindowAttribute))
        let document=window.flatMap { attribute($0,kAXDocumentAttribute) as? String }
        let title=window.flatMap { attribute($0,kAXTitleAttribute) as? String } ?? ""
        let javaDocument=document.flatMap(URL.init(string:)).flatMap { language($0.lastPathComponent) } != nil
        let javaTitle=title.range(of:#"\.(java|py|js|mjs|cpp|cc|hpp|c|h|r)\b"#,options:.regularExpression) != nil
        let untitled=["untitled"].contains { title.localizedCaseInsensitiveContains($0) }
        guard javaDocument || javaTitle || untitled else { return .unavailable("This window is not identified as Java source and will not be read. Open a .java file.") }
        guard let text=attribute(focused,kAXValueAttribute) as? String, !text.isEmpty else { return .unavailable("The editor did not provide source text. Try enabling Accessibility support in VS Code, or select a saved file. No screenshots are taken.") }
        do {
            let pattern=try NSRegularExpression(pattern:#"[\w.-]+\.(?:java|py|js|mjs|cpp|cc|hpp|c|h|r)\b"#,options:.caseInsensitive)
            let ns=title as NSString
            let match=pattern.firstMatch(in:title,range:NSRange(location:0,length:ns.length))
            let filename=document.flatMap(URL.init(string:)).flatMap { language($0.lastPathComponent) == nil ? nil : $0.lastPathComponent } ?? match.map { ns.substring(with:$0.range) } ?? "Untitled.java"
            guard text.utf8.count <= 2_000_000 else { throw CoachError.message("Source exceeds 2 MB.") }
            return .code(EditorCode(application:target.name,identity:Diagnostic.digest(bundle+"|"+(document ?? title)),filename:filename,text:text))
        } catch { return .unavailable(error.localizedDescription) }
    }
}
