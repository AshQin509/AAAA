import Foundation
import CryptoKit

public struct Diagnostic: Codable, Identifiable, Equatable, Sendable {
    public var file: String
    public var line: Int
    public var code: String
    public var message: String
    public var sourceLine: String?
    public var id: String { Self.digest("\(file)|\(line)|\(code)|\(message)") }
    public var category: String {
        if code.contains("cant.resolve") { return "符号与作用域" }
        if code.contains("incompatible") || code.contains("prob.found.req") { return "类型与转换" }
        if code.contains("cant.apply") { return "方法与参数" }
        if code.contains("non-static") { return "static 与实例" }
        if code.contains("expected") || code.contains("illegal") || code.contains("premature") { return "语法与结构" }
        return "Java 编译基础"
    }
    public init(file: String, line: Int, code: String, message: String, sourceLine: String? = nil) { self.file = file; self.line = line; self.code = code; self.message = message; self.sourceLine=sourceLine }
    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public enum DiagnosticParser {
    public static func parse(_ output: String, root: URL) -> [Diagnostic] {
        let regex = try! NSRegularExpression(pattern: #"^(.+\.java):(\d+):(?:(\d+):)?\s*(compiler\.err\.[^: ,]+)(?::\s*(.*))?$"#)
        var result: [Diagnostic] = []
        for line in output.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            func group(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            var file = group(1)
            if file.hasPrefix(root.path + "/") { file = String(file.dropFirst(root.path.count + 1)) }
            result.append(Diagnostic(file: file, line: Int(group(2)) ?? 1, code: group(4), message: String(group(5).prefix(2000))))
        }
        return Array(Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values).sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }
}

public enum CoachError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): return text } }
}

public struct ProjectSnapshot: Sendable {
    public let files: [URL]
    public let digest: String
    public static func scan(_ root: URL, cancellation: CancellationFlag? = nil) throws -> ProjectSnapshot {
        let fm = FileManager.default
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw CoachError.message("项目文件夹已移走或无法读取，请重新选择。") }
        var scanError: Error?
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else { throw CoachError.message("无法读取项目文件夹。请重新选择。") }
        let excluded: Set<String> = ["target", "build", "out", "bin", "node_modules", ".git", ".gradle"]
        var files: [URL] = []
        for case let url as URL in e {
            if cancellation?.cancelled == true { throw CancellationError() }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true || (values.isDirectory == true && excluded.contains(url.lastPathComponent)) { e.skipDescendants(); continue }
            if values.isRegularFile == true && url.pathExtension == "java" { files.append(url) }
            if files.count > 300 { throw CoachError.message("MVP 最多检查 300 个 Java 文件。请选择较小的源码文件夹。") }
        }
        if let scanError { throw scanError }
        files.sort { $0.path < $1.path }
        var hash = SHA256()
        var totalSize = 0
        for url in files {
            if cancellation?.cancelled == true { throw CancellationError() }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            totalSize += size
            guard totalSize <= 64_000_000 else { throw CoachError.message("源码总量超过 64 MB，请选择较小的文件夹。") }
            guard size <= 2_000_000 else { throw CoachError.message("单个 Java 文件超过 2 MB，已停止检查。") }
            hash.update(data: Data(url.path.utf8)); hash.update(data: try Data(contentsOf: url))
        }
        return ProjectSnapshot(files: files, digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public enum JavaAnalyzer {
    public static func findJavac() -> String? {
        if let bundled=Bundle.main.resourceURL?.appendingPathComponent("JDK/bin/javac").path, FileManager.default.isExecutableFile(atPath:bundled) { return bundled }
        let base = URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines")
        let homes = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return homes.sorted { $0.path > $1.path }.map { $0.appendingPathComponent("Contents/Home/bin/javac").path }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public static func analyze(root: URL, snapshot: ProjectSnapshot, javac: String, classpath: String, release: String, cancellation: CancellationFlag) throws -> [Diagnostic] {
        if cancellation.cancelled { throw CancellationError() }
        guard !snapshot.files.isEmpty else { return [] }
        // javac's raw formatter may omit directories. Reject ambiguous basenames rather than misattribute an error.
        if let duplicate = Dictionary(grouping:snapshot.files,by: { $0.lastPathComponent }).first(where: { $0.value.count > 1 }) {
            throw CoachError.message("MVP 暂不支持同一源码集合内的重复文件名（" + duplicate.key + "）。请选择单个源码集或较小的文件夹。")
        }
        guard FileManager.default.isExecutableFile(atPath: javac), !javac.isEmpty else { throw CoachError.message("请选择已安装 JDK 的 bin/javac。系统自带 /usr/bin/javac 可能只是占位程序。") }
        guard release.isEmpty || (Int(release).map { $0 >= 8 && $0 <= 99 } ?? false) else { throw CoachError.message("Java release 必须是 8–99 之间的数字，或留空。") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let output = temp.appendingPathComponent("compiler.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output); defer { try? handle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: javac); process.currentDirectoryURL = root
        var args = ["-XDrawDiagnostics", "-Xmaxerrs", "100", "-proc:none", "-implicit:none", "-encoding", "UTF-8", "-d", temp.path]
        // Explicit empty classpath avoids an inherited CLASSPATH and accidental project-root dependencies.
        if !classpath.isEmpty {
            guard classpath.split(separator: ":", omittingEmptySubsequences: false).allSatisfy({ $0.hasPrefix("/") && FileManager.default.fileExists(atPath: String($0)) }) else { throw CoachError.message("classpath 每项必须是已存在的绝对文件夹或 JAR 路径，以 : 分隔，不支持通配符。") }
        }
        args += ["-classpath", classpath.isEmpty ? temp.path : classpath, "-sourcepath", temp.path]
        if !release.isEmpty { args += ["--release", release] }
        args += snapshot.files.map(\.path)
        process.arguments = args; process.standardOutput = handle; process.standardError = handle
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning {
            if cancellation.cancelled || Date() > deadline {
                process.terminate(); Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw CoachError.message(cancellation.cancelled ? "检查已取消。" : "编译检查超时（20 秒）。请选择较小的项目。")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: output); defer { try? reader.close() }
        let data = try reader.read(upToCount: 1_000_000) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let diagnostics = DiagnosticParser.parse(text, root: root).map { d -> Diagnostic in
            var mapped = d
            if let original = snapshot.files.first(where: { $0.lastPathComponent == URL(fileURLWithPath:d.file).lastPathComponent }) {
                let base = root.resolvingSymlinksInPath().standardizedFileURL.path
                let path = original.resolvingSymlinksInPath().standardizedFileURL.path
                if path.hasPrefix(base + "/") { mapped.file = String(path.dropFirst(base.count + 1)) }
            }
            return mapped
        }
        if process.terminationStatus != 0 && diagnostics.isEmpty { throw CoachError.message("javac 未能完成检查。请检查 JDK、release、依赖路径或模块配置。\n" + String(text.prefix(600))) }
        return diagnostics
    }
}
