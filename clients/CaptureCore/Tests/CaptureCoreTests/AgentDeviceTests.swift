import XCTest
@testable import CaptureCore

final class AgentDeviceTests: XCTestCase {
    func testUpsertAgentDeviceRegistersAndUpdatesSameDevice() async throws {
        let store = TaskStore(config: .localDev)
        let id = "11111111-1111-4111-8111-111111111111"
        try await store.resetLocalData()

        try await store.upsertAgentDevice(
            id: id,
            deviceName: "  Test Mac  ",
            harnessKind: .openclaw,
            harnessLabel: "  OpenClaw  ",
            capabilities: ["research", "research", "attempt"],
            selectedBackend: true
        )
        try await store.upsertAgentDevice(
            id: id,
            deviceName: "Renamed Mac",
            harnessKind: .copilotCLI,
            harnessLabel: "Copilot CLI",
            capabilities: ["attempt"],
            selectedBackend: false
        )

        let devices = try await store.db.getAll(
            sql: "SELECT * FROM \(AGENT_DEVICES_TABLE) WHERE id = ?",
            parameters: [id],
            mapper: TaskStore.mapAgentDevice
        )
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.deviceName, "Renamed Mac")
        XCTAssertEqual(devices.first?.harnessKind, .copilotCLI)
        XCTAssertEqual(devices.first?.harnessLabel, "Copilot CLI")
        XCTAssertEqual(devices.first?.capabilities, ["attempt"])
        XCTAssertEqual(devices.first?.isSelectedBackend, false)

        try await store.resetLocalData()
    }
}
