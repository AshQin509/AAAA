import XCTest
@testable import CodeCoachCore
final class ReasoningTests:XCTestCase {
 func testValidResponse() throws {
  let data=Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"ready\":true}"}}]}"#.utf8)
  XCTAssertEqual(String(decoding:try DeepSeekClient.parse(data),as:UTF8.self),#"{"ready":true}"#)
 }
 func testMalformedEmptyAndTruncated() {
  for text in ["not JSON",#"{"choices":[]}"#,#"{"choices":[{"finish_reason":"length","message":{"content":"{}"}}]}"#,#"{"choices":[{"finish_reason":"stop","message":{"content":""}}]}"#] {
   XCTAssertThrowsError(try DeepSeekClient.parse(Data(text.utf8)))
  }
 }
 func testConceptRepresentation() throws {
  let data=Data(#"{"language":"java","concept":"Boundary conditions","possibleHabit":"Unchecked initialization assumptions","evidence":"max starts at zero","confidence":"medium","suggestedPractice":"Consider an all-negative array"}"#.utf8)
  let analysis=try JSONDecoder().decode(ConceptAnalysis.self,from:data).validated()
  XCTAssertEqual(analysis.concept,"Boundary conditions")
  // This tests schema validation, not live AI classification.
 }
}
