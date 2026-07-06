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
    XCTAssertLessThanOrEqual(result.count, 302) // 300 + "…"
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

  // MARK: - Structured summary (question / answer / next steps / follow-up)

  func testStructuredSummaryIncludesAllFourParts() {
    let query = "What's the weather in Lisbon?"
    let answer = "It's sunny and 24 degrees Celsius in Lisbon today. You should wear light clothes."
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: query, answer: answer, followUps: [])
    XCTAssertTrue(spoken.contains("You asked:"))
    XCTAssertTrue(spoken.contains("What's the weather in Lisbon?"))
    XCTAssertTrue(spoken.contains("Here's what I found:"))
    XCTAssertTrue(spoken.contains("24 degrees"))
    XCTAssertTrue(spoken.contains("Next:"))
    XCTAssertTrue(spoken.contains("Want me to go further?"))
  }

  func testStructuredSummaryFallsBackToFollowUpsWhenNoActionsInAnswer() {
    let query = "Search my emails for receipts"
    let answer = "Found 3 receipts in your inbox from last week."
    // No action keywords or imperative starters in the answer → fall back to followUps.
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: query, answer: answer, followUps: ["Open results", "Refine search"])
    XCTAssertTrue(spoken.contains("Next:"))
    XCTAssertTrue(spoken.contains("Open results"))
    XCTAssertTrue(spoken.contains("Refine search"))
  }

  func testStructuredSummaryExtractsNextStepsFromAnswer() {
    let query = "Check the build status"
    let answer = "The build passed. Next, you should deploy to staging. Then verify the logs."
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: query, answer: answer, followUps: ["Run again"])
    // "Next, you should deploy to staging" contains "next" → extracted as a next step.
    XCTAssertTrue(spoken.contains("Next:"))
    XCTAssertTrue(spoken.contains("deploy"))
  }

  func testStructuredSummaryOmitsQuestionLineWhenQueryEmpty() {
    let answer = "The result is 42."
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: "", answer: answer, followUps: [])
    XCTAssertFalse(spoken.contains("You asked:"))
    XCTAssertTrue(spoken.contains("Here's what I found:"))
  }

  func testStructuredSummaryTruncatesLongQuery() {
    let longQuery = String(repeating: "a", count: 200)
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: longQuery, answer: "Short answer.", followUps: [])
    // Question line truncated to 157 + "…"
    XCTAssertLessThanOrEqual(spoken.components(separatedBy: "You asked: ")[1].components(separatedBy: ".")[0].count, 160)
    XCTAssertTrue(spoken.contains("…"))
  }

  func testStructuredSummaryOmitsNextLineWhenNoFollowUpsAndNoActions() {
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: "What is 2+2?", answer: "It's 4.", followUps: [])
    XCTAssertFalse(spoken.contains("Next:"))
    XCTAssertTrue(spoken.contains("Here's what I found:"))
    XCTAssertTrue(spoken.contains("Want me to go further?"))
  }

  func testExtractNextStepsFindsImperativeStarters() {
    let text = "Open the file. Check the logs. The result was 42."
    let steps = AgentPillsManager.extractNextSteps(from: text)
    XCTAssertTrue(steps.contains(where: { $0.lowercased().hasPrefix("open") }))
    XCTAssertTrue(steps.contains(where: { $0.lowercased().hasPrefix("check") }))
  }

  func testExtractNextStepsFindsActionKeywords() {
    let text = "Build succeeded. Next, I will deploy. You should verify after."
    let steps = AgentPillsManager.extractNextSteps(from: text)
    XCTAssertFalse(steps.isEmpty)
    // "I will deploy" contains "i will" + "next"; "You should verify" contains "should"
    XCTAssertTrue(steps.contains(where: { $0.lowercased().contains("deploy") || $0.lowercased().contains("verify") }))
  }

  func testExtractNextStepsCapsAtTwoCandidates() {
    let text = "Open file one. Check the logs. Run the tests. Verify the output."
    let steps = AgentPillsManager.extractNextSteps(from: text)
    XCTAssertLessThanOrEqual(steps.count, 2)
  }

  func testExtractNextStepsReturnsEmptyForNoActions() {
    let text = "The weather is nice today. The build passed. All tests green."
    let steps = AgentPillsManager.extractNextSteps(from: text)
    XCTAssertTrue(steps.isEmpty)
  }

  func testStructuredSummaryAlwaysEndsWithFollowUp() {
    let spoken = AgentPillsManager.structuredSpokenSummary(
      query: "Q", answer: "A", followUps: [])
    XCTAssertTrue(spoken.hasSuffix("Want me to go further? Just say so."))
  }
}
