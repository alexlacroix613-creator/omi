import XCTest

@testable import Omi_Computer

/// Guards the invariant from `docs-fork/EXECUTE_REROUTE_DESIGN.md` §3a/§3b: the
/// cloud VM (`AgentVMService`) is a one-way memory-backup pipeline and must
/// never become a task-execution path. Every user-triggered Execute already
/// routes through `AgentPillsManager.spawn` / `spawnFromUserQuery` instead
/// (verified in the design doc's §1b caller trace).
///
/// There is no call-graph/SourceKit tooling wired into this package's test
/// target, so the closest robust equivalent (per the design doc's test plan,
/// §5) is a deterministic source scan: read every `.swift` file under
/// `Sources/` from disk (located via `#filePath`, the same technique
/// `StartupWarmupPolicyTests` already uses to read sibling source files) and
/// assert the set of files that call `AgentVMService.shared.<method>` is
/// EXACTLY the known background trio the design doc traced. If a future PR
/// points any Execute surface (or anything else) at `AgentVMService`, this
/// test fails loudly instead of the routing silently drifting.
///
/// Limitation (honest, stated per the task brief): this is a textual scan, not
/// a real compiler/call-graph check — it cannot see indirection through a
/// closure, a protocol, or a renamed/aliased reference to `AgentVMService`.
/// It is exact for the direct `AgentVMService.shared.foo(...)` call shape used
/// by all three known callers today, which is the shape a careless "just wire
/// Execute to the VM" change would also use.
final class AgentVMCallerInvariantTests: XCTestCase {

    /// The only callers allowed to dispatch into `AgentVMService.shared`,
    /// traced in EXECUTE_REROUTE_DESIGN.md §1a — all background/lifecycle,
    /// none user-Execute. Paths are relative to `Sources/`.
    private static let knownBackgroundCallers: Set<String> = [
        "MainWindow/DesktopHomeView.swift",   // app-launch warmup: ensureProvisioned()
        "OnboardingView.swift",               // onboarding completion: startPipeline()
        "AgentSyncService.swift",             // sync repair: reuploadDatabase(...)
    ]

    private static let callerPattern = "AgentVMService.shared."

    private func sourcesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // Desktop/
            .appendingPathComponent("Sources", isDirectory: true)
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw XCTSkip("Could not enumerate \(root.path) — skipping source scan")
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    func testAgentVMServiceHasNoCallersOutsideTheKnownBackgroundTrio() throws {
        let root = sourcesRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("Sources/ not found at \(root.path) — skipping source scan")
        }

        var actualCallers: Set<String> = []
        for fileURL in try swiftFiles(under: root) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            guard source.contains(Self.callerPattern) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            actualCallers.insert(relativePath)
        }

        XCTAssertEqual(
            actualCallers,
            Self.knownBackgroundCallers,
            """
            AgentVMService.shared caller set changed. Per EXECUTE_REROUTE_DESIGN.md \
            §3a, AgentVMService is a one-way memory-backup pipeline and must NEVER \
            carry a user-initiated Execute task — Execute must route through \
            AgentPillsManager.spawn / spawnFromUserQuery instead. If this is a new \
            legitimate background caller, add it to knownBackgroundCallers above \
            deliberately. If it is an Execute surface, redirect it to \
            AgentPillsManager instead of editing this test.
            """
        )
    }

    /// Companion check on the other side of the chokepoint: every known
    /// Execute surface traced in the design doc's §1b must still resolve to
    /// `AgentPillsManager`, not to `AgentVMService`. Textual, same limitation
    /// as above — it proves the surfaces call the pill manager, not that they
    /// are the only way to trigger Execute (a wholly new surface would need a
    /// new line in this list, same as the caller-trio list above).
    func testKnownExecuteSurfacesRouteThroughAgentPillsManagerNotTheVM() throws {
        let root = sourcesRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("Sources/ not found at \(root.path) — skipping source scan")
        }

        let executeSurfaces: [String: String] = [
            "MainWindow/Pages/TasksPage.swift": "AgentPillsManager.shared.spawn",
            "FloatingControlBar/FloatingControlBarView.swift": "AgentPillsManager.shared.spawn",
            "MemoryExportExecutor.swift": "AgentPillsManager.shared.spawn",
        ]

        for (relativePath, expectedCall) in executeSurfaces {
            let fileURL = root.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw XCTSkip("\(relativePath) not found — skipping (file may have moved)")
            }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(
                source.contains(expectedCall),
                "\(relativePath) is a known Execute surface and must call \(expectedCall); " +
                "if it now dispatches elsewhere, confirm it isn't routing to AgentVMService."
            )
            XCTAssertFalse(
                source.contains(Self.callerPattern),
                "\(relativePath) is a user-Execute surface and must never call AgentVMService directly."
            )
        }
    }
}
