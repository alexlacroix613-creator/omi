import XCTest

@testable import Omi_Computer

final class CostAwareModelRouterTests: XCTestCase {

  // MARK: - Cheap

  func testCheapAllConnectedPrefersFreeOpenRouter() {
    // Even when every provider is connected, .cheap wants the free model.
    let route = CostAwareModelRouter.route(
      workload: .cheap,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: true,
        chatGPTConnected: true,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "qwen/qwen3-coder:free")
    XCTAssertEqual(route.providerLabel, "OpenRouter (free)")
  }

  func testCheapOnlyOpenRouterKeyUsesFreeModel() {
    let route = CostAwareModelRouter.route(
      workload: .cheap,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "qwen/qwen3-coder:free")
    XCTAssertEqual(route.providerLabel, "OpenRouter (free)")
  }

  func testCheapNothingConnectedFallsBackToOnDevice() {
    let route = CostAwareModelRouter.route(
      workload: .cheap,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: false
      )
    )
    XCTAssertEqual(route.modelIdentifier, "on-device")
    XCTAssertEqual(route.providerLabel, "On-device")
  }

  // MARK: - Balanced

  func testBalancedAllConnectedPrefersClaude() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: true,
        chatGPTConnected: true,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "claude-sonnet")
    XCTAssertEqual(route.providerLabel, "Claude")
  }

  func testBalancedOnlyOpenRouterKeyUsesFreeModel() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "qwen/qwen3-coder:free")
    XCTAssertEqual(route.providerLabel, "OpenRouter (free)")
  }

  func testBalancedNothingConnectedFallsBackToOnDevice() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: false
      )
    )
    XCTAssertEqual(route.modelIdentifier, "on-device")
    XCTAssertEqual(route.providerLabel, "On-device")
  }

  // MARK: - Heavy

  func testHeavyAllConnectedPrefersClaudeOpus() {
    let route = CostAwareModelRouter.route(
      workload: .heavy,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: true,
        chatGPTConnected: true,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "claude-opus")
    XCTAssertEqual(route.providerLabel, "Claude")
  }

  func testHeavyOnlyOpenRouterKeyUsesFreeModel() {
    let route = CostAwareModelRouter.route(
      workload: .heavy,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(route.modelIdentifier, "qwen/qwen3-coder:free")
    XCTAssertEqual(route.providerLabel, "OpenRouter (free)")
  }

  func testHeavyNothingConnectedFallsBackToOnDevice() {
    let route = CostAwareModelRouter.route(
      workload: .heavy,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: false
      )
    )
    XCTAssertEqual(route.modelIdentifier, "on-device")
    XCTAssertEqual(route.providerLabel, "On-device")
  }

  // MARK: - Bridge Mode Mapping (live cost-router)

  func testBridgeModeForClaudeRoute() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: true,
        chatGPTConnected: true,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(CostAwareModelRouter.bridgeMode(for: route), .userClaude)
  }

  func testBridgeModeForChatGPTRoute() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: true,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(CostAwareModelRouter.bridgeMode(for: route), .userChatGPT)
  }

  func testBridgeModeForOpenRouterRoute() {
    let route = CostAwareModelRouter.route(
      workload: .cheap,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: true
      )
    )
    XCTAssertEqual(CostAwareModelRouter.bridgeMode(for: route), .openRouter)
  }

  func testBridgeModeForOnDeviceRoute() {
    let route = CostAwareModelRouter.route(
      workload: .balanced,
      availability: CostAwareModelRouter.Availability(
        claudeConnected: false,
        chatGPTConnected: false,
        openRouterKeyPresent: false
      )
    )
    XCTAssertEqual(CostAwareModelRouter.bridgeMode(for: route), .piMono)
  }
}
