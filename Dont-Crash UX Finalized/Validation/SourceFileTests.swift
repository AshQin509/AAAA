import Foundation

@main struct SourceFileTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let file=root.appendingPathComponent("Demo.java")
        try Data("class Demo {}".utf8).write(to:file)
        guard case .code(let original)=EditorReader.read(file:file) else { fatalError("Selected file must work without Accessibility permission") }
        try Data("class Demo { int n = missing; }".utf8).write(to:file,options:.atomic)
        guard case .code(let changed)=EditorReader.read(file:file), changed.text != original.text, changed.identity == original.identity else { fatalError("Saved edits must update text with stable identity") }
        try FileManager.default.removeItem(at:file)
        guard case .unavailable=EditorReader.read(file:file) else { fatalError("Deleted file must be unavailable") }
        try Data(repeating:65,count:2_000_001).write(to:file)
        guard case .unavailable=EditorReader.read(file:file) else { fatalError("Oversize file must be rejected") }
        print("PASS: selected file without Accessibility, saved edits, stable identity, deletion, and size limit")
    }
}
