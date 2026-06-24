import XCTest
@testable import CaptureCore

final class UserMemoryTests: XCTestCase {
    func testCleanMemoryTrimsBoundsAndClampsConfidence() {
        let cleaned = TaskStore.cleanMemory(
            content: "  " + String(repeating: "x", count: 1200) + "  ",
            domain: " " + String(repeating: "shopping", count: 20) + " ",
            confidence: 3,
            tags: [" Kitchen Stuff ", "kitchen stuff", "fast delivery"],
            status: .active
        )

        XCTAssertNotNil(cleaned)
        XCTAssertEqual(cleaned?.content.count, 1000)
        XCTAssertEqual(cleaned?.domain?.count, 80)
        XCTAssertEqual(cleaned?.confidence, 1)
        XCTAssertEqual(cleaned?.tags, ["Kitchen Stuff", "fast delivery"])
        XCTAssertEqual(cleaned?.status, .active)
    }

    func testCleanMemoryRejectsEmptyContent() {
        XCTAssertNil(TaskStore.cleanMemory(content: "  ", domain: nil, confidence: 0.5, tags: [], status: .active))
    }

    func testCleanMemoryPreservesDisabledStatusAndClampsLowConfidence() {
        let cleaned = TaskStore.cleanMemory(
            content: "Temporary childcare preference",
            domain: nil,
            confidence: -2,
            tags: [],
            status: .disabled
        )

        XCTAssertEqual(cleaned?.confidence, 0)
        XCTAssertEqual(cleaned?.status, .disabled)
    }
}
