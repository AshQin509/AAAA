import CoreGraphics
import SQLite3
#if canImport(XCTest) && !PORTABLE_TESTS
import XCTest
@testable import CodeCoachCore
#else
import Foundation
#endif

final class CoreTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws { temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:temp) }
    func diagnostic() -> Diagnostic { Diagnostic(file:"src/A.java",line:2,code:"compiler.err.cant.resolve.location",message:"kindname.variable, missing") }
    func testParserHandlesPathsSpacesUnicodeAndDeduplicates() {
        let text="/my project/源码/A.java:2:9: compiler.err.cant.resolve.location: kindname.variable, missing\n/my project/源码/A.java:2:9: compiler.err.cant.resolve.location: kindname.variable, missing\n1 error\nA.java:3: warning: ignored"
        let parsed=DiagnosticParser.parse(text,root:URL(fileURLWithPath:"/my project"))
        XCTAssertEqual(parsed.count,1); XCTAssertEqual(parsed[0].file,"源码/A.java"); XCTAssertEqual(parsed[0].line,2); XCTAssertEqual(parsed[0].category,"Symbols and scope")
    }
    func testStoreDedupRecurrenceIsolationAndPersistence() throws {
        let url=temp.appendingPathComponent("db.sqlite"); let d=diagnostic()
        do {
            let store=try ErrorStore(url:url)
            try store.reconcile(project:"a",diagnostics:[d,d]); try store.reconcile(project:"a",diagnostics:[d])
            XCTAssertEqual(try store.records(project:"a").first?.occurrences,1)
            try store.reconcile(project:"a",diagnostics:[]); XCTAssertFalse(try XCTUnwrap(store.records(project:"a").first).active)
            try store.reconcile(project:"a",diagnostics:[d]); XCTAssertEqual(try store.records(project:"a").first?.occurrences,2)
            XCTAssertTrue(try store.records(project:"b").isEmpty)
        }
        let reopened=try ErrorStore(url:url); XCTAssertEqual(try reopened.records(project:"a").count,1)
    }
    func testAnswerIdempotencyStatsAndErase() throws {
        let store=try ErrorStore(url:temp.appendingPathComponent("db")); let d=diagnostic()
        try store.reconcile(project:"'quoted",diagnostics:[d])
        try store.answer(id:"q1",project:"'quoted",topic:d.category,correct:true)
        try store.answer(id:"q1",project:"'quoted",topic:d.category,correct:false)
        try store.answer(id:"q2",project:"'quoted",topic:d.category,correct:false)
        let stats=try XCTUnwrap(store.stats(project:"'quoted").first)
        XCTAssertEqual(stats.answered,2); XCTAssertEqual(stats.correct,1); XCTAssertEqual(stats.occurrences,1)
        try store.erase(); XCTAssertTrue(try store.records(project:"'quoted").isEmpty); XCTAssertTrue(try store.stats(project:"'quoted").isEmpty)
    }
    func testSnapshotDetectsSameSizeSaveAndIgnoresGeneratedAndSymlinks() throws {
        let file=temp.appendingPathComponent("A.java")
        try Data("class A {}".utf8).write(to:file)
        let first=try ProjectSnapshot.scan(temp)
        try Data("class B {}".utf8).write(to:file)
        let second=try ProjectSnapshot.scan(temp)
        XCTAssertNotEqual(first.digest,second.digest)
        let generated=temp.appendingPathComponent("target"); try FileManager.default.createDirectory(at:generated,withIntermediateDirectories:true)
        try Data("broken".utf8).write(to:generated.appendingPathComponent("B.java"))
        try FileManager.default.createSymbolicLink(at:temp.appendingPathComponent("link.java"),withDestinationURL:file)
        XCTAssertEqual(try ProjectSnapshot.scan(temp).files.count,1)
        try FileManager.default.removeItem(at:file); XCTAssertTrue(try ProjectSnapshot.scan(temp).files.isEmpty)
    }
    func testSnapshotLimit() throws {
        try Data(repeating:65,count:2_000_001).write(to:temp.appendingPathComponent("Big.java"))
        XCTAssertThrowsError(try ProjectSnapshot.scan(temp))
    }
    func testQuizValidationAndPrivacyPayload() throws {
        let valid=Quiz(question:"Q",choices:["a","b","c","d"],answer:2,explanation:"Because")
        XCTAssertEqual(try valid.validated(),valid)
        XCTAssertThrowsError(try Quiz(question:"Q",choices:["a","a","b","c"],answer:4,explanation:"").validated())
        let payload=try QuizClient.preview([TopicStat(topic:"Types and conversions",occurrences:3,answered:2,correct:1)])
        XCTAssertFalse(payload.contains("file")); XCTAssertFalse(payload.contains("message")); XCTAssertFalse(payload.contains("project")); XCTAssertTrue(payload.contains("occurrences"))
    }
    func testActualJavacValidBrokenMultipleFilesAndSpaces() throws {
        guard let javac=ProcessInfo.processInfo.environment["CODECOACH_TEST_JAVAC"] ?? JavaAnalyzer.findJavac() else { throw XCTSkip("Set CODECOACH_TEST_JAVAC to run real JDK integration") }
        let root=temp.appendingPathComponent("space 项目"); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let a=root.appendingPathComponent("A.java"), b=root.appendingPathComponent("B.java")
        try Data("class A { B value = new B(); }".utf8).write(to:a); try Data("class B {}".utf8).write(to:b)
        let analyze = { () throws -> [Diagnostic] in try JavaAnalyzer.analyze(root:root,snapshot:ProjectSnapshot.scan(root),javac:javac,classpath:"",release:"17",cancellation:CancellationFlag()) }
        XCTAssertTrue(try analyze().isEmpty)
        try Data("class A { int value = \"wrong\"; }".utf8).write(to:a)
        let errors=try analyze(); XCTAssertFalse(errors.isEmpty); XCTAssertEqual(errors.first?.file,"A.java")
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("A.class").path))
        try Data("class A { int value = missing; }".utf8).write(to:a)
        XCTAssertEqual(try analyze().first?.category,"Symbols and scope")
        let nested=root.appendingPathComponent("nested"); try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:true)
        try FileManager.default.moveItem(at:a,to:nested.appendingPathComponent("A.java"))
        XCTAssertEqual(try analyze().first?.file,"nested/A.java")
        try Data("package other; class A {}".utf8).write(to:root.appendingPathComponent("A.java"))
        XCTAssertThrowsError(try analyze())

    }
    func testClasspathAndCancellation() throws {
        guard let javac=ProcessInfo.processInfo.environment["CODECOACH_TEST_JAVAC"] ?? JavaAnalyzer.findJavac() else { throw XCTSkip("JDK not configured") }
        let dep=temp.appendingPathComponent("dependency"); try FileManager.default.createDirectory(at:dep,withIntermediateDirectories:true)
        let source=dep.appendingPathComponent("Library.java"); try Data("public class Library { public static int value=1; }".utf8).write(to:source)
        let p=Process(); p.executableURL=URL(fileURLWithPath:javac); p.arguments=["-proc:none","-d",dep.path,source.path]; try p.run(); p.waitUntilExit(); XCTAssertEqual(p.terminationStatus,0)
        let project=temp.appendingPathComponent("app"); try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
        try Data("class App { int n=Library.value; }".utf8).write(to:project.appendingPathComponent("App.java"))
        let snap=try ProjectSnapshot.scan(project)
        let withDependency=try JavaAnalyzer.analyze(root:project,snapshot:snap,javac:javac,classpath:dep.path,release:"",cancellation:CancellationFlag())
        XCTAssertTrue(withDependency.isEmpty)
        let withoutDependency=try JavaAnalyzer.analyze(root:project,snapshot:snap,javac:javac,classpath:"",release:"",cancellation:CancellationFlag())
        XCTAssertFalse(withoutDependency.isEmpty)
        let fake=temp.appendingPathComponent("fake-javac"); try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to:fake)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:fake.path)
        let flag=CancellationFlag(); DispatchQueue.global().asyncAfter(deadline:.now()+0.3) { flag.cancel() }
        let start=Date()
        XCTAssertThrowsError(try JavaAnalyzer.analyze(root:project,snapshot:snap,javac:fake.path,classpath:"",release:"",cancellation:flag))
        XCTAssertTrue(Date().timeIntervalSince(start)<3)
    }
    func testLiveSourceFilenameAndInputValidation() throws {
        XCTAssertEqual(try LiveSource.filename(text:"public class Demo {}",document:nil,title:"Untitled-1"),"Demo.java")
        XCTAssertEqual(try LiveSource.filename(text:"class Demo {}",document:"file:///tmp/Space%20Path/Original.java",title:"Other.java"),"Original.java")
        XCTAssertEqual(try LiveSource.filename(text:"record Point(int x) {}",document:nil,title:"Point.java — Editor"),"Point.java")
        XCTAssertThrowsError(try LiveSource.filename(text:"private notes and passwords",document:nil,title:"Notes.txt"))
        XCTAssertThrowsError(try LiveSource.filename(text:String(repeating:"a",count:2_000_001),document:nil,title:"A.java"))
    }
    func testUnsavedLiveSourceUsesSuppliedBufferAndCleansUp() throws {
        guard let javac=ProcessInfo.processInfo.environment["CODECOACH_TEST_JAVAC"] ?? JavaAnalyzer.findJavac() else { throw XCTSkip("JDK not configured") }
        let before=Set((try FileManager.default.contentsOfDirectory(atPath:FileManager.default.temporaryDirectory.path)).filter { $0.hasPrefix("CodeCoach-Live-") })
        let valid=try LiveSource.analyze(text:"public class Live { int n = 1; }",filename:"Live.java",javac:javac,cancellation:CancellationFlag())
        XCTAssertTrue(valid.isEmpty)
        let errors=try LiveSource.analyze(text:"public class Live { int n = \"bad\"; }",filename:"Live.java",javac:javac,cancellation:CancellationFlag())
        XCTAssertFalse(errors.isEmpty); XCTAssertEqual(errors.first?.file,"Live.java")
        XCTAssertThrowsError(try LiveSource.analyze(text:"class Live {}",filename:"../../Live.java",javac:javac,cancellation:CancellationFlag()))
        let after=Set((try FileManager.default.contentsOfDirectory(atPath:FileManager.default.temporaryDirectory.path)).filter { $0.hasPrefix("CodeCoach-Live-") })
        XCTAssertEqual(before,after)
    }
    func testClickVersusDrag() {
        var gesture=PointerGesture()
        XCTAssertEqual(gesture.end(at:.zero),.none)
        gesture.begin(at:CGPoint(x:10,y:10)); gesture.update(at:CGPoint(x:12,y:11))
        XCTAssertEqual(gesture.end(at:CGPoint(x:12,y:11)),.click)
        gesture.begin(at:.zero); gesture.update(at:CGPoint(x:40,y:10)); gesture.update(at:.zero)
        XCTAssertEqual(gesture.end(at:.zero),.drag)
        gesture.begin(at:.zero)
        XCTAssertEqual(gesture.end(at:CGPoint(x:10,y:0)),.drag)
        XCTAssertEqual(gesture.end(at:.zero),.none)
        gesture.begin(at:.zero)
        XCTAssertEqual(gesture.end(at:.zero),.click)
    }
    func testCurrentHistoryPartitionAndRecurrence() throws {
        let store=try ErrorStore(url:temp.appendingPathComponent("filter.sqlite"))
        let first=Diagnostic(file:"A.java",line:2,code:"compiler.err.prob.found.req",message:"String,int",sourceLine:"int n = \"bad\";")
        let second=diagnostic()
        try store.reconcile(project:"p",diagnostics:[first,second])
        try store.reconcile(project:"p",diagnostics:[second])
        let records=try store.records(project:"p")
        XCTAssertEqual(LearningSelection.problems(records,resolved:false).map(\.id),[second.id])
        XCTAssertEqual(LearningSelection.problems(records,resolved:true).map(\.id),[first.id])
        XCTAssertEqual(try XCTUnwrap(LearningSelection.problems(records,resolved:true).first).diagnostic.sourceLine,first.sourceLine)
        try store.reconcile(project:"p",diagnostics:[first,second])
        XCTAssertTrue(LearningSelection.problems(try store.records(project:"p"),resolved:true).isEmpty)
        XCTAssertEqual(LearningSelection.problems(try store.records(project:"p"),resolved:false).count,2)
    }
    func testTopicSelectionAndLocalReferences() throws {
        let a=Diagnostic(file:"A.java",line:3,code:"compiler.err.prob.found.req",message:"String,int",sourceLine:"private marker only local")
        let b=diagnostic()
        let records=[ErrorRecord(id:a.id,diagnostic:a,occurrences:1,active:false),ErrorRecord(id:b.id,diagnostic:b,occurrences:1,active:true)]
        let stats=[TopicStat(topic:a.category,occurrences:3,answered:2,correct:1),TopicStat(topic:b.category,occurrences:1,answered:0,correct:0)]
        let selected=LearningSelection.context(stats,topic:b.category)
        XCTAssertEqual(selected.count,1);XCTAssertEqual(selected.first?.topic,b.category)
        XCTAssertEqual(LearningSelection.references(records,topic:b.category).map(\.id),[b.id])
        XCTAssertEqual(LearningSelection.references(records,topic:a.category).first?.line,3)
        let payload=try QuizClient.preview(selected)
        XCTAssertFalse(payload.contains(a.category));XCTAssertFalse(payload.contains("private marker"));XCTAssertFalse(payload.contains("A.java"))
        XCTAssertTrue(LearningSelection.context(stats,topic:"missing").isEmpty)
    }
    func testSourceLineLegacyDecodingAndFingerprint() throws {
        let old=diagnostic()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any]);json.removeValue(forKey:"sourceLine")
        let decoded=try JSONDecoder().decode(Diagnostic.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(decoded.sourceLine == nil);XCTAssertEqual(decoded.id,old.id)
        var enriched=decoded;enriched.sourceLine="sensitive snippet"
        XCTAssertEqual(enriched.id,decoded.id)
        XCTAssertFalse(try DatabricksClient.explanationPreview(enriched).contains("sensitive snippet"))
    }
    func testLiveSourceLineWithCRLF() throws {
        guard let javac=ProcessInfo.processInfo.environment["CODECOACH_TEST_JAVAC"] ?? JavaAnalyzer.findJavac() else { throw XCTSkip("JDK not configured") }
        let errors=try LiveSource.analyze(text:"public class A {\r\n\r\n  int value = \"wrong\";\r\n}\r\n",filename:"A.java",javac:javac,cancellation:CancellationFlag())
        let d=try XCTUnwrap(errors.first)
        XCTAssertEqual(d.line,3);XCTAssertEqual(d.sourceLine,"  int value = \"wrong\";")
    }
    func testLegacyTopicMigrationPreservesAnswers() throws {
        let url=temp.appendingPathComponent("legacy.sqlite")
        let d=diagnostic()
        do {
            let store=try ErrorStore(url:url)
            try store.reconcile(project:"legacy",diagnostics:[d])
            try store.answer(id:"answer",project:"legacy",topic:d.category,correct:true)
        }
        var db:OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        let old="\u{7b26}\u{53f7}\u{4e0e}\u{4f5c}\u{7528}\u{57df}"
        XCTAssertEqual(sqlite3_exec(db,"UPDATE errors SET category='"+old+"'; UPDATE attempts SET topic='"+old+"';",nil,nil,nil),SQLITE_OK)
        sqlite3_close(db)
        let reopened=try ErrorStore(url:url)
        let stat=try XCTUnwrap(reopened.stats(project:"legacy").first)
        XCTAssertEqual(stat.topic,"Symbols and scope"); XCTAssertEqual(stat.answered,1); XCTAssertEqual(stat.correct,1)
        XCTAssertEqual(try reopened.records(project:"legacy").count,1)
    }
    func testInvalidCompilerAndRelease() throws {
        try Data("class A {}".utf8).write(to:temp.appendingPathComponent("A.java"))
        let snap=try ProjectSnapshot.scan(temp)
        XCTAssertThrowsError(try JavaAnalyzer.analyze(root:temp,snapshot:snap,javac:"/does/not/exist",classpath:"",release:"",cancellation:CancellationFlag()))
        XCTAssertThrowsError(try JavaAnalyzer.analyze(root:temp,snapshot:snap,javac:"/bin/echo",classpath:"",release:"invalid",cancellation:CancellationFlag()))
    }
}

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))?
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (code,data)=try Self.handler!(request); client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed); client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class QuizClientTests: XCTestCase {
    func client() -> QuizClient { let c=URLSessionConfiguration.ephemeral; c.protocolClasses=[MockProtocol.self]; return QuizClient(session:URLSession(configuration:c)) }
    func testStructuredResponseAndRequestPrivacy() async throws {
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString,"https://api.openai.com/v1/responses"); XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer test-key")
            var data=request.httpBody
            if data == nil, let stream=request.httpBodyStream { stream.open(); defer { stream.close() }; var buffer=[UInt8](repeating:0,count:4096); var collected=Data(); while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; collected.append(buffer,count:n) }; data=collected }
            let body=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(data)) as? [String:Any]); XCTAssertEqual(body["store"] as? Bool,false)
            let input=try XCTUnwrap(body["input"] as? String); XCTAssertFalse(input.contains("file")); XCTAssertFalse(input.contains("message"))
            let quiz=Quiz(question:"Q",choices:["A","B","C","D"],answer:0,explanation:"Explanation")
            let text=String(decoding:try JSONEncoder().encode(quiz),as:UTF8.self)
            return (200,try JSONSerialization.data(withJSONObject:["status":"completed","output":[["content":[["type":"output_text","text":text]]]]]))
        }
        let quiz=try await client().generate(stats:[],key:"test-key",model:"test-model"); XCTAssertEqual(quiz.answer,0)
    }
    func testAPIErrorDoesNotExposeResponseBody() async {
        MockProtocol.handler={ _ in (401,Data("secret-response".utf8)) }
        do { _=try await client().generate(stats:[],key:"test",model:"test"); XCTFail("Expected error") } catch { XCTAssertFalse(error.localizedDescription.contains("secret-response")); XCTAssertTrue(error.localizedDescription.contains("Key")) }
    }
    func testRefusalAndIncomplete() async {
        for status in ["completed","incomplete"] {
            MockProtocol.handler={ _ in (200,try JSONSerialization.data(withJSONObject:["status":status,"output":[["content":[["type":"refusal","refusal":"No"]]]]])) }
            do { _=try await client().generate(stats:[],key:"test",model:"test"); XCTFail("Expected rejection") } catch { }
        }
    }
}

final class DatabricksTests:XCTestCase {
    func openAIClient() -> DatabricksClient { let c=URLSessionConfiguration.ephemeral; c.protocolClasses=[MockProtocol.self]; return DatabricksClient(session:URLSession(configuration:c),provider:.openai) }
    func client() -> DatabricksClient { let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[MockProtocol.self];return DatabricksClient(session:URLSession(configuration:c)) }
    func body(_ request:URLRequest) throws -> [String:Any] {
        var data=request.httpBody
        if data == nil, let stream=request.httpBodyStream {
            stream.open();defer { stream.close() };var buffer=[UInt8](repeating:0,count:4096);var all=Data()
            while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 { break };all.append(buffer,count:n) };data=all
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(data)) as? [String:Any])
    }
    func response(_ content:Any,finish:String="stop") throws -> Data { try JSONSerialization.data(withJSONObject:["choices":[["finish_reason":finish,"message":["role":"assistant","content":content]]]]) }
    func quizText() throws -> String { String(decoding:try JSONEncoder().encode(Quiz(question:"Question",choices:["A","B","C","D"],answer:1,explanation:"Explanation")),as:UTF8.self) }
    func testConfiguredRequestAndAnonymousQuiz() async throws {
        MockProtocol.handler={ request in
            XCTAssertEqual(request.url,DatabricksConfig.endpoint);XCTAssertEqual(request.httpMethod,"POST")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer dummy-token")
            let body=try self.body(request);XCTAssertEqual(body["model"] as? String,"system.ai.gpt-oss-120b");XCTAssertEqual(body["max_tokens"] as? Int,5000)
            XCTAssertTrue(body["input"] == nil);XCTAssertTrue(body["store"] == nil)
            let messages=try XCTUnwrap(body["messages"] as? [[String:String]])
            let input=try XCTUnwrap(messages.last?["content"]);XCTAssertFalse(input.contains("file"));XCTAssertFalse(input.contains("diagnostic_message"));XCTAssertFalse(input.contains("source"))
            let format=try XCTUnwrap(body["response_format"] as? [String:Any]);XCTAssertEqual(format["type"] as? String,"json_schema")
            return (200,try self.response(self.quizText()))
        }
        let quiz=try await client().generate(stats:[TopicStat(topic:"Types",occurrences:2,answered:1,correct:0)],key:"dummy-token",model:DatabricksConfig.model)
        XCTAssertEqual(quiz.answer,1)
    }
    func testGPTOSSBlocksExcludeReasoning() async throws {
        MockProtocol.handler={ _ in (200,try self.response([["type":"reasoning","text":"not JSON, must never be parsed"],["type":"text","text":try self.quizText()]])) }
        let quiz=try await client().generate(stats:[],key:"dummy",model:DatabricksConfig.model);XCTAssertEqual(quiz.choices.count,4)
    }
    func testDiagnosticPreviewAndExplanation() async throws {
        let d=Diagnostic(file:"private/project/Secret.java",line:42,code:"compiler.err.prob.found.req",message:"java.lang.String cannot convert to int")
        let preview=try DatabricksClient.explanationPreview(d)
        XCTAssertFalse(preview.contains("Secret.java"));XCTAssertFalse(preview.contains("private/project"));XCTAssertTrue(preview.contains(d.message))
        MockProtocol.handler={ request in
            let messages=try XCTUnwrap(self.body(request)["messages"] as? [[String:String]])
            XCTAssertEqual(messages.last?["content"],preview)
            let text=String(decoding:try JSONSerialization.data(withJSONObject:["summary":"Summary","cause":"Cause","fix":"Fix","example":"int n = 1;","caveat":"No full project context"]),as:UTF8.self)
            return (200,try self.response([["type":"text","text":text]]))
        }
        let explanation=try await client().explain(d,key:"dummy",model:DatabricksConfig.model);XCTAssertEqual(explanation.fix,"Fix")
    }
    func testHTTPFailuresAreSanitized() async {
        for code in [400,401,403,404,429,500,302] {
            MockProtocol.handler={ _ in (code,Data("sensitive-server-response".utf8)) }
            do { _=try await client().generate(stats:[],key:"dummy",model:DatabricksConfig.model);XCTFail("Must reject HTTP error") }
            catch { XCTAssertFalse(error.localizedDescription.contains("sensitive-server-response")) }
        }
    }
    func testIncompleteAndInvalidOutput() async {
        for content in ["not JSON","{\"question\":\"missing fields\"}"] {
            MockProtocol.handler={ _ in (200,try self.response(content)) }
            do { _=try await client().generate(stats:[],key:"dummy",model:DatabricksConfig.model);XCTFail("Must reject invalid quiz") } catch { }
        }
        MockProtocol.handler={ _ in (200,try self.response(self.quizText(),finish:"length")) }
        do { _=try await client().generate(stats:[],key:"dummy",model:DatabricksConfig.model);XCTFail("Must reject truncated response") } catch { }
    }
    func testConnectionAndInvalidTokenHeader() async throws {
        MockProtocol.handler={ request in
            let messages=try XCTUnwrap(self.body(request)["messages"] as? [[String:String]])
            XCTAssertEqual(messages.last?["content"],"Connection test. No project data is included.")
            return (200,try self.response("{\"ready\":true}"))
        }
        try await client().testConnection(key:"dummy",model:DatabricksConfig.model)
        do { try await client().testConnection(key:"bad\nheader",model:DatabricksConfig.model);XCTFail("Must reject header injection") } catch { }
    }
}


extension DatabricksTests {
    func testOpenAIExplanationPrivacyAndEnglish() async throws {
        let diagnostic=Diagnostic(file:"private/Secret.java",line:2,code:"compiler.err.expected",message:"semicolon expected",sourceLine:"private secret code")
        MockProtocol.handler={ request in
            XCTAssertEqual(request.url?.absoluteString,"https://api.openai.com/v1/responses")
            let body=try self.body(request)
            XCTAssertEqual(body["store"] as? Bool,false)
            XCTAssertTrue((body["instructions"] as? String ?? "").contains("English"))
            let input=try XCTUnwrap(body["input"] as? String)
            XCTAssertFalse(input.contains("Secret.java")); XCTAssertFalse(input.contains("private secret code"))
            XCTAssertTrue(input.contains("semicolon expected"))
            let text="{\"summary\":\"Summary\",\"cause\":\"Cause\",\"fix\":\"Fix\",\"example\":\"int n = 1;\",\"caveat\":\"Verify in IDE\"}"
            return (200,try JSONSerialization.data(withJSONObject:["status":"completed","output":[["content":[["type":"output_text","text":text]]]]]))
        }
        let result=try await openAIClient().explain(diagnostic,key:"dummy",model:"demo-model")
        XCTAssertEqual(result.fix,"Fix")
        XCTAssertNotEqual(AIProvider.openai.credentialService,AIProvider.databricks.credentialService)
    }
    func testOpenAIConnectionAndHeaderValidation() async throws {
        MockProtocol.handler={ request in
            let body=try self.body(request)
            XCTAssertEqual(body["input"] as? String,"Connection test. No project data is included.")
            return (200,try JSONSerialization.data(withJSONObject:["status":"completed","output":[["content":[["type":"output_text","text":"{\"ready\":true}"]]]]]))
        }
        try await openAIClient().testConnection(key:"dummy",model:"demo")
        do { try await openAIClient().testConnection(key:"bad\rheader",model:"demo"); XCTFail("Header injection must be rejected") } catch { }
    }
}
