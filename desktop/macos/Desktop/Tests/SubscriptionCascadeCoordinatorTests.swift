import XCTest

@testable import Omi_Computer

/// Verifies `SubscriptionCascadeCoordinator` — DREAM_BACKLOG item 8 Pass 2 — with
/// fakes for all three injected legs (ChatGPT connection, reasoning, playback),
/// per docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md §5. No real codex login, mic,
/// or TTS engine involved; that manual verification is documented as out of scope
/// for this automated suite.
@MainActor
final class SubscriptionCascadeCoordinatorTests: XCTestCase {

  // MARK: - Test harness

  /// Records every call made to the reasoning/playback legs so tests can
  /// assert both the RESULT and the ORDER/ARGUMENTS of a turn.
  @MainActor
  private final class Spy {
    var connected = true
    var codexInstalled = true
    var reasonResult = CascadeReasoningResult(replyText: "a reply", errorMessage: nil)
    private(set) var reasonCalls: [String] = []
    private(set) var speakCalls: [String] = []
    /// Optional hook so a test can observe coordinator state WHILE the
    /// reasoning leg is still in flight (proves `.thinking` is set before
    /// the await resolves, not just after).
    var onReason: (() -> Void)?

    func makeCoordinator() -> SubscriptionCascadeCoordinator {
      SubscriptionCascadeCoordinator(
        isChatGPTConnected: { [weak self] in self?.connected ?? false },
        isCodexInstalled: { [weak self] in self?.codexInstalled ?? false },
        reason: { [weak self] text in
          guard let self else { return CascadeReasoningResult(replyText: nil, errorMessage: nil) }
          self.reasonCalls.append(text)
          self.onReason?()
          return self.reasonResult
        },
        speak: { [weak self] text in self?.speakCalls.append(text) }
      )
    }
  }

  /// Test-only box letting a synchronous continuation-capture callback hand a
  /// `CheckedContinuation` out to the enclosing test, which resumes it later —
  /// used to deterministically suspend/resume a fake reasoning leg mid-turn
  /// instead of relying on sleeps or thread timing.
  private final class ReleaseBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    func store(_ continuation: CheckedContinuation<Void, Never>) {
      self.continuation = continuation
    }
    func release() {
      continuation?.resume()
      continuation = nil
    }
  }

  // MARK: - precondition (pure, no I/O)

  func testPrecondition_allGood_returnsNil() {
    XCTAssertNil(
      SubscriptionCascadeCoordinator.precondition(
        transcript: "hello", chatGPTConnected: true, codexInstalled: true))
  }

  func testPrecondition_chatGPTNotConnected_takesPriority() {
    XCTAssertEqual(
      SubscriptionCascadeCoordinator.precondition(
        transcript: "hello", chatGPTConnected: false, codexInstalled: false),
      .chatGPTNotConnected)
  }

  func testPrecondition_codexNotInstalled_whenConnectedButNoBinary() {
    XCTAssertEqual(
      SubscriptionCascadeCoordinator.precondition(
        transcript: "hello", chatGPTConnected: true, codexInstalled: false),
      .codexNotInstalled)
  }

  func testPrecondition_emptyTranscript_afterAuthChecksPass() {
    XCTAssertEqual(
      SubscriptionCascadeCoordinator.precondition(
        transcript: "   ", chatGPTConnected: true, codexInstalled: true),
      .emptyTranscript)
  }

  func testPrecondition_blankTranscriptVariants_allTreatedAsEmpty() {
    for transcript in ["", "  ", "\n\t "] {
      XCTAssertEqual(
        SubscriptionCascadeCoordinator.precondition(
          transcript: transcript, chatGPTConnected: true, codexInstalled: true),
        .emptyTranscript)
    }
  }

  // MARK: - CascadeTurnError.userMessage

  func testUserMessage_everyCaseIsNonEmptyAndActionable() {
    let cases: [SubscriptionCascadeCoordinator.CascadeTurnError] = [
      .chatGPTNotConnected, .codexNotInstalled, .emptyTranscript, .providerError("boom"),
    ]
    for c in cases {
      XCTAssertFalse(c.userMessage.isEmpty)
    }
    XCTAssertTrue(
      SubscriptionCascadeCoordinator.CascadeTurnError.chatGPTNotConnected.userMessage
        .localizedCaseInsensitiveContains("connect"))
    XCTAssertTrue(
      SubscriptionCascadeCoordinator.CascadeTurnError.codexNotInstalled.userMessage
        .localizedCaseInsensitiveContains("install"))
  }

  func testUserMessage_providerError_fallsBackToGenericCopyWhenMessageIsBlank() {
    let error = SubscriptionCascadeCoordinator.CascadeTurnError.providerError("  ")
    XCTAssertFalse(error.userMessage.isEmpty)
    XCTAssertTrue(error.userMessage.localizedCaseInsensitiveContains("try again"))
  }

  func testUserMessage_providerError_passesThroughRealMessage() {
    let error = SubscriptionCascadeCoordinator.CascadeTurnError.providerError("bridge crashed")
    XCTAssertEqual(error.userMessage, "bridge crashed")
  }

  // MARK: - runTurn: happy path

  func testRunTurn_happyPath_speaksReplyAndReturnsToIdle() async {
    let spy = Spy()
    spy.reasonResult = CascadeReasoningResult(replyText: "here's your answer", errorMessage: nil)
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "what's the weather")

    XCTAssertEqual(spy.reasonCalls, ["what's the weather"])
    XCTAssertEqual(spy.speakCalls, ["here's your answer"])
    XCTAssertEqual(coordinator.state, .idle)
  }

  func testRunTurn_setsThinkingStateWhileReasoningIsInFlight() async {
    let spy = Spy()
    var observedThinking = false
    let coordinator = spy.makeCoordinator()
    spy.onReason = {
      if case .thinking = coordinator.state { observedThinking = true }
    }

    await coordinator.runTurn(transcript: "hello")

    XCTAssertTrue(observedThinking, "state must be .thinking while the reasoning leg runs")
  }

  // MARK: - runTurn: precondition failures never touch reason/speak

  func testRunTurn_chatGPTNotConnected_failsWithoutCallingReasonOrSpeak() async {
    let spy = Spy()
    spy.connected = false
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "hello")

    XCTAssertEqual(coordinator.state, .failed(.chatGPTNotConnected))
    XCTAssertTrue(spy.reasonCalls.isEmpty)
    XCTAssertTrue(spy.speakCalls.isEmpty)
  }

  func testRunTurn_codexNotInstalled_failsWithoutCallingReasonOrSpeak() async {
    let spy = Spy()
    spy.codexInstalled = false
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "hello")

    XCTAssertEqual(coordinator.state, .failed(.codexNotInstalled))
    XCTAssertTrue(spy.reasonCalls.isEmpty)
  }

  func testRunTurn_emptyTranscript_failsWithoutCallingReasonOrSpeak() async {
    let spy = Spy()
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "   ")

    XCTAssertEqual(coordinator.state, .failed(.emptyTranscript))
    XCTAssertTrue(spy.reasonCalls.isEmpty)
  }

  // MARK: - runTurn: reasoning-leg failures

  func testRunTurn_providerReturnsNilReply_whileStillConnected_isProviderError() async {
    let spy = Spy()
    spy.reasonResult = CascadeReasoningResult(replyText: nil, errorMessage: "tool timed out")
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "hello")

    XCTAssertEqual(coordinator.state, .failed(.providerError("tool timed out")))
    XCTAssertTrue(spy.speakCalls.isEmpty, "must not speak a nil/empty reply")
  }

  func testRunTurn_providerReturnsBlankReply_treatedSameAsNil() async {
    let spy = Spy()
    spy.reasonResult = CascadeReasoningResult(replyText: "   ", errorMessage: "empty")
    let coordinator = spy.makeCoordinator()

    await coordinator.runTurn(transcript: "hello")

    if case .failed(.providerError) = coordinator.state {
      // expected
    } else {
      XCTFail("expected .failed(.providerError), got \(coordinator.state)")
    }
    XCTAssertTrue(spy.speakCalls.isEmpty)
  }

  /// The design doc's "auth expired mid-turn" failure mode: connected at the
  /// precondition check, but the reasoning leg's own auth flag has flipped
  /// false by the time it returns (token expired while codex-acp ran).
  func testRunTurn_authExpiresMidTurn_classifiedAsChatGPTNotConnected() async {
    let spy = Spy()
    spy.connected = true
    spy.reasonResult = CascadeReasoningResult(replyText: nil, errorMessage: "auth required")
    let coordinator = spy.makeCoordinator()
    // Flip connection state at the moment reasoning resolves, simulating a
    // token expiring mid-turn.
    spy.onReason = { spy.connected = false }

    await coordinator.runTurn(transcript: "hello")

    XCTAssertEqual(coordinator.state, .failed(.chatGPTNotConnected))
  }

  // MARK: - runTurn: never stacks a second turn

  /// Deterministic version of the "never stacks a second turn" guarantee:
  /// holds the FIRST turn's reasoning leg suspended on a manually-resumed
  /// continuation so the second call is guaranteed to observe `.thinking`
  /// (no timing races / sleeps).
  func testRunTurn_ignoredWhileAlreadyThinking() async {
    var reasonCalls: [String] = []
    var speakCalls: [String] = []
    let firstTurnReasoningStarted = XCTestExpectation()
    let releaseBox = ReleaseBox()

    let coordinator = SubscriptionCascadeCoordinator(
      isChatGPTConnected: { true },
      isCodexInstalled: { true },
      reason: { text in
        reasonCalls.append(text)
        firstTurnReasoningStarted.fulfill()
        await withCheckedContinuation { continuation in
          releaseBox.store(continuation)
        }
        return CascadeReasoningResult(replyText: "first reply", errorMessage: nil)
      },
      speak: { text in speakCalls.append(text) }
    )

    let firstTurn = Task { await coordinator.runTurn(transcript: "first") }
    await fulfillment(of: [firstTurnReasoningStarted], timeout: 2)

    if case .thinking = coordinator.state {
      // expected
    } else {
      XCTFail("expected .thinking while the first turn's reasoning leg is suspended")
    }

    // Second call while the first is genuinely still in flight — must be
    // dropped, not queued or stacked.
    await coordinator.runTurn(transcript: "second")
    XCTAssertEqual(reasonCalls, ["first"], "second call must be dropped while thinking")

    releaseBox.release()
    _ = await firstTurn.value
    XCTAssertEqual(speakCalls, ["first reply"])
  }

  // MARK: - reset()

  func testReset_clearsFailedStateToIdle() async {
    let spy = Spy()
    spy.connected = false
    let coordinator = spy.makeCoordinator()
    await coordinator.runTurn(transcript: "hello")
    XCTAssertEqual(coordinator.state, .failed(.chatGPTNotConnected))

    coordinator.reset()

    XCTAssertEqual(coordinator.state, .idle)
  }

  func testReset_fromIdle_isANoOp() {
    let spy = Spy()
    let coordinator = spy.makeCoordinator()
    coordinator.reset()
    XCTAssertEqual(coordinator.state, .idle)
  }

  // MARK: - Failed turns self-heal (a later runTurn is not blocked by a stale failure)

  func testRunTurn_afterAPriorFailure_isNotBlocked() async {
    let spy = Spy()
    spy.connected = false
    let coordinator = spy.makeCoordinator()
    await coordinator.runTurn(transcript: "first")
    XCTAssertEqual(coordinator.state, .failed(.chatGPTNotConnected))

    spy.connected = true
    spy.reasonResult = CascadeReasoningResult(replyText: "second reply", errorMessage: nil)
    await coordinator.runTurn(transcript: "second")

    XCTAssertEqual(coordinator.state, .idle)
    XCTAssertEqual(spy.speakCalls, ["second reply"])
  }
}
