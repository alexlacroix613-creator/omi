import XCTest

@testable import Omi_Computer

final class AgentPillSpokenSummaryTests: XCTestCase {

  func testStripsMarkdownHeaders() {
    let input = "## Summary\n\nThe agent found 3 results."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("##"))
    XCTAssertTrue(result.contains("Summary"))
    XCTAssertTrue(result.contains("The agent found 3 results."))
  }

  func testStripsBoldAndItalic() {
    let input = "This is **bold** and this is *italic* and this is ***both***."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("**"))
    XCTAssertFalse(result.contains("*"))
    XCTAssertTrue(result.contains("bold"))
    XCTAssertTrue(result.contains("italic"))
  }

  func testStripsCodeBlocks() {
    let input = "Here's the code:\n```swift\nlet x = 42\n```\nDone."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("```"))
    XCTAssertFalse(result.contains("let x = 42"))
    XCTAssertTrue(result.contains("[code block]"))
    XCTAssertTrue(result.contains("Done."))
  }

  func testStripsInlineCode() {
    let input = "Use `npm install` to install deps."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("`"))
    XCTAssertFalse(result.contains("npm install"))
  }

  func testStripsLinks() {
    let input = "See [the docs](https://example.com) for details."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("https://"))
    XCTAssertFalse(result.contains("]("))
    XCTAssertTrue(result.contains("the docs"))
    XCTAssertTrue(result.contains("for details."))
  }

  func testStripsBulletPoints() {
    let input = "- First item\n- Second item\n- Third item"
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("- "))
    XCTAssertTrue(result.contains("First item"))
    XCTAssertTrue(result.contains("Second item"))
  }

  func testTruncatesLongText() {
    let longText = String(repeating: "word ", count: 200) // ~1000 chars
    let result = AgentPillsManager.spokenSummary(from: longText)
    XCTAssertLessThanOrEqual(result.count, 502) // 500 + "…"
    XCTAssertTrue(result.hasSuffix("…"))
  }

  func testDoesNotTruncateShortText() {
    let input = "Short answer."
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertEqual(result, "Short answer.")
    XCTAssertFalse(result.hasSuffix("…"))
  }

  func testCollapsesWhitespace() {
    let input = "Too\n\n\nmuch   \t\twhitespace   here"
    let result = AgentPillsManager.spokenSummary(from: input)
    XCTAssertFalse(result.contains("\n\n"))
    XCTAssertFalse(result.contains("\t"))
    XCTAssertTrue(result.contains("Too"))
    XCTAssertTrue(result.contains("here"))
  }

  func testEmptyInput() {
    let result = AgentPillsManager.spokenSummary(from: "")
    XCTAssertEqual(result, "")
  }
}
