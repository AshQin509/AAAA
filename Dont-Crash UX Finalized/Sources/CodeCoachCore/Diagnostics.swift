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
        if code.contains("cant.resolve") { return "Symbols and scope" }
        if code.contains("incompatible") || code.contains("prob.found.req") { return "Types and conversions" }
        if code.contains("cant.apply") { return "Methods and arguments" }
        if code.contains("non-static") { return "Static and instance members" }
        if code.contains("expected") || code.contains("illegal") || code.contains("premature") { return "Syntax and structure" }
        return "Java fundamentals"
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
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw CoachError.message("The project folder moved or is unreadable. Select it again.") }
        var scanError: Error?
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else { throw CoachError.message("Could not read the project folder. Select it again.") }
        let excluded: Set<String> = ["target", "build", "out", "bin", "node_modules", ".git", ".gradle"]
        var files: [URL] = []
        for case let url as URL in e {
            if cancellation?.cancelled == true { throw CancellationError() }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true || (values.isDirectory == true && excluded.contains(url.lastPathComponent)) { e.skipDescendants(); continue }
            if values.isRegularFile == true && url.pathExtension == "java" { files.append(url) }
            if files.count > 300 { throw CoachError.message("At most 300 Java files can be checked. Choose a smaller source folder.") }
        }
        if let scanError { throw scanError }
        files.sort { $0.path < $1.path }
        var hash = SHA256()
        var totalSize = 0
        for url in files {
            if cancellation?.cancelled == true { throw CancellationError() }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            totalSize += size
            guard totalSize <= 64_000_000 else { throw CoachError.message("Total source exceeds 64 MB. Select a smaller folder.") }
            guard size <= 2_000_000 else { throw CoachError.message("A Java file exceeds 2 MB. Checking stopped.") }
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
        let fm=FileManager.default
        // GUI applications do not inherit a shell's PATH. java_home knows registered JDKs.
        let process=Process(); let pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:"/usr/libexec/java_home")
        process.standardOutput=pipe; process.standardError=FileHandle.nullDevice
        if (try? process.run()) != nil {
            let deadline=Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.02) }
            if process.isRunning { process.terminate() } else {
                let home=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
                let candidate=home+"/bin/javac"
                if !home.isEmpty && fm.isExecutableFile(atPath:candidate) { return candidate }
            }
        }
        let roots=["/Library/Java/JavaVirtualMachines",NSHomeDirectory()+"/Library/Java/JavaVirtualMachines","/opt/homebrew/opt","/usr/local/opt",NSHomeDirectory()+"/.sdkman/candidates/java"]
        for root in roots {
            let entries=(try? fm.contentsOfDirectory(atPath:root)) ?? []
            for entry in entries.sorted().reversed() {
                for suffix in ["/Contents/Home/bin/javac","/libexec/openjdk.jdk/Contents/Home/bin/javac","/bin/javac"] {
                    let candidate=root+"/"+entry+suffix
                    if fm.isExecutableFile(atPath:candidate) { return candidate }
                }
            }
        }
        return nil
    }
    public static func analyze(root: URL, snapshot: ProjectSnapshot, javac: String, classpath: String, release: String, cancellation: CancellationFlag) throws -> [Diagnostic] {
        if cancellation.cancelled { throw CancellationError() }
        guard !snapshot.files.isEmpty else { return [] }
        // javac's raw formatter may omit directories. Reject ambiguous basenames rather than misattribute an error.
        if let duplicate = Dictionary(grouping:snapshot.files,by: { $0.lastPathComponent }).first(where: { $0.value.count > 1 }) {
            throw CoachError.message("Duplicate Java filenames are not supported in one source set (" + duplicate.key + "). Choose one source set or a smaller folder.")
        }
        guard FileManager.default.isExecutableFile(atPath: javac), !javac.isEmpty else { throw CoachError.message("Select an installed JDK's bin/javac. /usr/bin/javac may only be a system launcher.") }
        guard release.isEmpty || (Int(release).map { $0 >= 8 && $0 <= 99 } ?? false) else { throw CoachError.message("Java release must be a number from 8 to 99, or empty.") }
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
            guard classpath.split(separator: ":", omittingEmptySubsequences: false).allSatisfy({ $0.hasPrefix("/") && FileManager.default.fileExists(atPath: String($0)) }) else { throw CoachError.message("Each classpath entry must be an existing absolute folder or JAR path, separated by colons. Wildcards are not supported.") }
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
                throw CoachError.message(cancellation.cancelled ? "Check cancelled." : "Compiler check timed out after 20 seconds. Use a smaller source set.")
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
        if process.terminationStatus != 0 && diagnostics.isEmpty { throw CoachError.message("javac could not complete the check. Check the JDK, release, dependencies, or module configuration.\n" + String(text.prefix(600))) }
        return diagnostics
    }
}
