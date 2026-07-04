import XCTest

@testable import Omi_Computer

final class ProviderHealthModelTests: XCTestCase {

  func testAllFourConnected() {
    let model = ProviderHealthModel.build(
      claude: true,
      chatGPT: true,
      openRouter: true,
      gemini: true
    )

    XCTAssertEqual(model.connectedCount, 4)
    XCTAssertEqual(model.total, 4)
    XCTAssertEqual(model.summary, "4 of 4 connected")
    XCTAssertTrue(model.allConnected, "allConnected is true only when every provider is wired up")

    XCTAssertEqual(
      model.providers,
      [
        ProviderHealthModel.ProviderHealth(name: "Claude", status: .connected),
        ProviderHealthModel.ProviderHealth(name: "ChatGPT", status: .connected),
        ProviderHealthModel.ProviderHealth(name: "OpenRouter", status: .connected),
        ProviderHealthModel.ProviderHealth(name: "Gemini", status: .connected),
      ]
    )
  }

  func testNoneConnected() {
    let model = ProviderHealthModel.build(
      claude: false,
      chatGPT: false,
      openRouter: false,
      gemini: false
    )

    XCTAssertEqual(model.connectedCount, 0)
    XCTAssertEqual(model.total, 4)
    XCTAssertEqual(model.summary, "0 of 4 connected")
    XCTAssertFalse(model.allConnected)

    XCTAssertEqual(
      model.providers.map(\.status),
      [.needsSetup, .needsSetup, .needsSetup, .needsSetup]
    )
    XCTAssertEqual(
      model.providers.map(\.name),
      ["Claude", "ChatGPT", "OpenRouter", "Gemini"],
      "Provider order is fixed for stable UI rendering"
    )
  }

  func testMixedCaseClaudeAndOpenRouterConnected() {
    let model = ProviderHealthModel.build(
      claude: true,
      chatGPT: false,
      openRouter: true,
      gemini: false
    )

    XCTAssertEqual(model.connectedCount, 2)
    XCTAssertEqual(model.total, 4)
    XCTAssertEqual(model.summary, "2 of 4 connected")
    XCTAssertFalse(model.allConnected)

    XCTAssertEqual(
      model.providers,
      [
        ProviderHealthModel.ProviderHealth(name: "Claude", status: .connected),
        ProviderHealthModel.ProviderHealth(name: "ChatGPT", status: .needsSetup),
        ProviderHealthModel.ProviderHealth(name: "OpenRouter", status: .connected),
        ProviderHealthModel.ProviderHealth(name: "Gemini", status: .needsSetup),
      ]
    )
  }
}
