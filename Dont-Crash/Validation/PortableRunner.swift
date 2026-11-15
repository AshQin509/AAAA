// Runs the SAME CoreTests.swift assertions when Command Line Tools lack XCTest.
import Foundation
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
struct XCTSkip: Error { let reason: String; init(_ reason: String) { self.reason=reason } }
struct AssertionError: Error {}
var failures=0
func XCTFail(_ message:String="Failure",file:StaticString=#filePath,line:UInt=#line) { failures += 1; print("FAIL \(file):\(line): \(message)") }
func XCTAssertTrue(_ value:@autoclosure () throws -> Bool,file:StaticString=#filePath,line:UInt=#line) { do { if try !value() { XCTFail("Expected true",file:file,line:line) } } catch { XCTFail("Unexpected error: \(error)",file:file,line:line) } }
func XCTAssertFalse(_ value:@autoclosure () throws -> Bool,file:StaticString=#filePath,line:UInt=#line) { do { if try value() { XCTFail("Expected false",file:file,line:line) } } catch { XCTFail("Unexpected error: \(error)",file:file,line:line) } }
func XCTAssertEqual<T:Equatable>(_ a:@autoclosure () throws -> T,_ b:@autoclosure () throws -> T,file:StaticString=#filePath,line:UInt=#line) { do { let av=try a(),bv=try b(); if av != bv { XCTFail("\(av) != \(bv)",file:file,line:line) } } catch { XCTFail("Unexpected error: \(error)",file:file,line:line) } }
func XCTAssertNotEqual<T:Equatable>(_ a:@autoclosure () throws -> T,_ b:@autoclosure () throws -> T,file:StaticString=#filePath,line:UInt=#line) { do { if try a() == b() { XCTFail("Expected different values",file:file,line:line) } } catch { XCTFail("Unexpected error: \(error)",file:file,line:line) } }
func XCTUnwrap<T>(_ value:T?,file:StaticString=#filePath,line:UInt=#line) throws -> T { guard let value else { XCTFail("Unexpected nil",file:file,line:line); throw AssertionError() }; return value }
func XCTAssertThrowsError<T>(_ value:@autoclosure () throws -> T,file:StaticString=#filePath,line:UInt=#line) { do { _=try value(); XCTFail("Expected error",file:file,line:line) } catch {} }
@main struct PortableRunner {
    static func main() async {
        let c=CoreTests()
        let tests:[(String,() throws -> Void)]=[
            ("parser",c.testParserHandlesPathsSpacesUnicodeAndDeduplicates),
            ("legacy topic migration",c.testLegacyTopicMigrationPreservesAnswers),
            ("dedup, recurrence, project isolation and persistence",c.testStoreDedupRecurrenceIsolationAndPersistence),
            ("answer idempotency, stats and erase",c.testAnswerIdempotencyStatsAndErase),
            ("saved content changes, exclusions, symlinks and deletion",c.testSnapshotDetectsSameSizeSaveAndIgnoresGeneratedAndSymlinks),
            ("source size limit",c.testSnapshotLimit),
            ("quiz validation and privacy payload",c.testQuizValidationAndPrivacyPayload),
            ("real javac, multiple files and Unicode paths",c.testActualJavacValidBrokenMultipleFilesAndSpaces),
            ("explicit dependencies and running compiler cancellation",c.testClasspathAndCancellation),
            ("live buffer filename and rejected inputs",c.testLiveSourceFilenameAndInputValidation),
            ("unsaved code checks and temporary source cleanup",c.testUnsavedLiveSourceUsesSuppliedBufferAndCleansUp),
            ("click versus drag, return-to-origin and reset",c.testClickVersusDrag),
            ("current/history resolution and recurrence",c.testCurrentHistoryPartitionAndRecurrence),
            ("selected topic and local error references",c.testTopicSelectionAndLocalReferences),
            ("old diagnostics decoding and private snippet",c.testSourceLineLegacyDecodingAndFingerprint),
            ("CRLF source-line alignment",c.testLiveSourceLineWithCRLF),
            ("invalid compiler and release",c.testInvalidCompilerAndRelease)]
        var passed=0,skipped=0
        for (name,body) in tests {
            let before=failures
            do { try c.setUpWithError(); defer { try? c.tearDownWithError() }; try body(); if failures == before { passed += 1; print("PASS \(name)") } }
            catch let skip as XCTSkip { skipped += 1; print("SKIP \(name): \(skip.reason)") }
            catch { XCTFail("\(name): \(error)") }
        }
        let q=QuizClientTests()
        let before=failures
        do { try await q.testStructuredResponseAndRequestPrivacy() } catch { XCTFail("API response: \(error)") }
        await q.testAPIErrorDoesNotExposeResponseBody(); await q.testRefusalAndIncomplete()
        if before == failures { passed += 3; print("PASS mock API structured output, privacy, HTTP errors, refusal and incomplete responses") }
        let db=DatabricksTests()
        let dbTests:[(String,() async throws -> Void)]=[
            ("Databricks request, model and anonymous quiz",db.testConfiguredRequestAndAnonymousQuiz),
            ("OpenAI explanation privacy and English",db.testOpenAIExplanationPrivacyAndEnglish),
            ("OpenAI connection and header validation",db.testOpenAIConnectionAndHeaderValidation),
            ("GPT-OSS text blocks exclude reasoning",db.testGPTOSSBlocksExcludeReasoning),
            ("selected diagnostic privacy and explanation",db.testDiagnosticPreviewAndExplanation),
            ("sanitized HTTP failures and redirects",db.testHTTPFailuresAreSanitized),
            ("truncated and invalid model output",db.testIncompleteAndInvalidOutput),
            ("connection probe and invalid header",db.testConnectionAndInvalidTokenHeader)]
        for (name,body) in dbTests {
            let before=failures
            do { try await body();if failures==before { passed += 1;print("PASS \(name)") } }
            catch { XCTFail("\(name): \(error)") }
        }
        print("RESULT: \(passed) tests passed, \(skipped) skipped, \(failures) assertion failures")
        exit(failures == 0 ? 0:1)
    }
}
