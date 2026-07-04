import XCTest

@testable import Omi_Computer

/// Direct behavioral coverage for `AgentPillsManager.describeActivity(for:)` —
/// the pill-bar activity label shown while an agent is running. Backlog item:
/// the bare "Working…" fallback should name what's actually known (an
/// in-flight tool, or failing that the agent's own reasoning) rather than a
/// frozen ellipsis. Made `static` (not `private`) specifically so this test
/// can call it directly with synthetic `ChatMessage`s — no pill/provider/
/// MainActor state required, matching `AgentStallNarrationTests`' style.
final class AgentPillDescribeActivityTests: XCTestCase {

  private func message(
    text: String = "",
    isStreaming: Bool = false,
    contentBlocks: [ChatContentBlock] = []
  ) -> ChatMessage {
    ChatMessage(text: text, sender: .ai, isStreaming: isStreaming, contentBlocks: contentBlocks)
  }

  // MARK: - Existing behavior (regression coverage)

  func testToolCallNamesTheTool() {
    let msg = message(contentBlocks: [
      .toolCall(id: "1", name: "Bash", status: .running)
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Running command")
  }

  func testToolCallWithSummaryAppendsIt() {
    let msg = message(contentBlocks: [
      .toolCall(id: "1", name: "Read", status: .running, input: ToolCallInput(summary: "main.swift", details: nil))
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Reading file — main.swift")
  }

  func testMostRecentToolCallWinsOverEarlierOne() {
    let msg = message(contentBlocks: [
      .toolCall(id: "1", name: "Read", status: .completed),
      .thinking(id: "2", text: "Now let me search for the caller."),
      .toolCall(id: "3", name: "Grep", status: .running),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Searching code")
  }

  func testFinishedTextIsShown() {
    let msg = message(contentBlocks: [
      .text(id: "1", text: "Here is the summary you asked for.")
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Here is the summary you asked for.")
  }

  func testStreamingTextBlockIsSkipped() {
    // A partial text block mid-stream must not flicker onto the pill —
    // falls through to the (also-streaming) message.text fallback, which is
    // itself skipped, landing on the bare "Working…" since there's no
    // thinking block either.
    let msg = message(
      text: "O",
      isStreaming: true,
      contentBlocks: [.text(id: "1", text: "O")]
    )
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Working…")
  }

  func testStreamingTextFallsBackToEarlierToolCall() {
    let msg = message(
      isStreaming: true,
      contentBlocks: [
        .toolCall(id: "1", name: "WebSearch", status: .completed),
        .text(id: "2", text: "partial toke"),
      ]
    )
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Searching the web")
  }

  func testEmptyMessageWithNoBlocksReturnsWorking() {
    XCTAssertEqual(AgentPillsManager.describeActivity(for: message()), "Working…")
  }

  // MARK: - New behavior: thinking-text fallback

  func testThinkingOnlyMessageUsesReasoningSnippetInsteadOfWorking() {
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "Let me check the calendar for conflicts before booking.")
    ])
    XCTAssertEqual(
      AgentPillsManager.describeActivity(for: msg),
      "Let me check the calendar for conflicts before booking."
    )
  }

  func testMostRecentThinkingBlockWinsOverOlderOne() {
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "First I'll look at the inbox."),
      .thinking(id: "2", text: "Actually, let me check the calendar first."),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Actually, let me check the calendar first.")
  }

  func testThinkingFallbackIsTruncatedTo110Characters() {
    let long = String(repeating: "reasoning ", count: 20)  // 200 chars
    let msg = message(contentBlocks: [.thinking(id: "1", text: long)])
    let result = AgentPillsManager.describeActivity(for: msg)
    XCTAssertEqual(result, String(long.prefix(110)))
    XCTAssertEqual(result.count, 110)
  }

  func testEmptyThinkingTextDoesNotSuppressWorkingFallback() {
    let msg = message(contentBlocks: [.thinking(id: "1", text: "   ")])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Working…")
  }

  func testToolCallStillWinsOverEarlierThinkingText() {
    // Thinking came first (older), then the tool actually started — the
    // tool call is still the most specific, most recent signal.
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "I should search for this."),
      .toolCall(id: "2", name: "Grep", status: .running),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Searching code")
  }

  func testFinishedTextStillWinsOverEarlierThinkingText() {
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "I should summarize now."),
      .text(id: "2", text: "Done — here's the summary."),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Done — here's the summary.")
  }

  func testThinkingFallbackDoesNotLeakPastAFollowingEmptyTextBlock() {
    // An empty finished text block (e.g. a placeholder) must not itself
    // return "" and must not stop the scan from finding the thinking text.
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "Considering the best approach."),
      .text(id: "2", text: "   "),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Considering the best approach.")
  }

  func testDiscoveryCardIsSkippedAndDoesNotBlockThinkingFallback() {
    let msg = message(contentBlocks: [
      .thinking(id: "1", text: "Building your profile."),
      .discoveryCard(id: "2", title: "Profile", summary: "summary", fullText: "full"),
    ])
    XCTAssertEqual(AgentPillsManager.describeActivity(for: msg), "Building your profile.")
  }
}
