import XCTest
@testable import CaptureCore

final class SuggesterTests: XCTestCase {
    func testCategoryEngineering() {
        XCTAssertEqual(Suggester.category(for: "review the PR before deploy").category, "engineering")
    }

    func testCategoryLeadership() {
        XCTAssertEqual(Suggester.category(for: "prepare roadmap for hiring strategy 1:1").category, "leadership")
    }

    func testCategoryHealth() {
        XCTAssertEqual(Suggester.category(for: "book dentist appointment").category, "health")
    }

    func testCategoryNoneWhenUnmatched() {
        XCTAssertNil(Suggester.category(for: "ponder the universe").category)
    }

    func testDetectsAbsoluteDate() {
        let date = Suggester.detectDate(in: "submit taxes on January 31 2027")
        XCTAssertNotNil(date)
    }

    func testNoDateWhenAbsent() {
        XCTAssertNil(Suggester.detectDate(in: "tidy the desk"))
    }

    func testConfidenceCombines() {
        // category hit (0.25) only, no date
        let s = Suggester.suggest("call mum")
        XCTAssertEqual(s.category, "personal")
        XCTAssertGreaterThan(s.confidence, 0)
        XCTAssertLessThanOrEqual(s.confidence, 1)
    }

    func testISORoundTrip() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let s = ISO8601.string(now)
        let back = ISO8601.date(s)
        XCTAssertNotNil(back)
        XCTAssertEqual(back!.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.01)
    }
}
