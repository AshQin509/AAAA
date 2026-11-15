import Foundation

/// Inspects only a complete Java compilation unit provided by an opted-in editor.
/// No workspace enumeration, screenshot, OCR or network operation occurs here.
public enum LiveSource {
    public static func filename(text:String, document:String?, title:String) throws -> String {
        guard text.utf8.count <= 2_000_000 else { throw CoachError.message("当前代码过大，已停止读取。请使用较小的 Java 文件。") }
        guard !text.contains("\0") else { throw CoachError.message("当前内容不是可检查的 Java 文本。") }
        let ns=text as NSString
        let declaration=try NSRegularExpression(pattern:#"\b(?:class|interface|enum|record)\s+([\p{L}_$][\p{L}\p{N}_$]*)"#)
        guard let match=declaration.firstMatch(in:text,range:NSRange(location:0,length:ns.length)) else { throw CoachError.message("未读到完整 Java 类。请打开完整的 Java 源文件；单行或截断内容无法可靠检查。") }
        if let document, let url=URL(string:document), url.isFileURL, url.pathExtension.lowercased() == "java" { return url.lastPathComponent }
        let titlePattern=try NSRegularExpression(pattern:#"([\p{L}\p{N}_$-]+\.java)\b"#)
        let titleNS=title as NSString
        if let found=titlePattern.firstMatch(in:title,range:NSRange(location:0,length:titleNS.length)) { return titleNS.substring(with:found.range(at:1)) }
        // Unsaved untitled buffers can still be checked with a filename derived from the public type.
        let publicType=try NSRegularExpression(pattern:#"\bpublic\s+(?:(?:abstract|final|sealed|non-sealed|strictfp)\s+)*(?:class|interface|enum|record)\s+([\p{L}_$][\p{L}\p{N}_$]*)"#)
        let type=publicType.firstMatch(in:text,range:NSRange(location:0,length:ns.length)) ?? match
        return ns.substring(with:type.range(at:1))+".java"
    }
    public static func analyze(text:String,filename:String,javac:String,cancellation:CancellationFlag) throws -> [Diagnostic] {
        guard filename == URL(fileURLWithPath:filename).lastPathComponent, filename.hasSuffix(".java"), !filename.hasPrefix(".") else { throw CoachError.message("无法确定 Java 文件名。") }
        _=try self.filename(text:text,document:nil,title:filename)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("CodeCoach-Live-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:temp) }
        try Data(text.utf8).write(to:temp.appendingPathComponent(filename),options:.atomic)
        let lines=text.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").components(separatedBy:"\n")
        return try JavaAnalyzer.analyze(root:temp,snapshot:ProjectSnapshot.scan(temp,cancellation:cancellation),javac:javac,classpath:"",release:"",cancellation:cancellation).map { diagnostic in
            var d=diagnostic
            if d.line>0 && d.line<=lines.count { d.sourceLine=String(lines[d.line-1].prefix(1000)) }
            return d
        }
    }
}
