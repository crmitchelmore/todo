import XCTest
@testable import CaptureCore

final class MarkdownListParserTests: XCTestCase {
    func testPlainProseIsNotAList() {
        XCTAssertNil(MarkdownListParser.parse("buy milk"))
        XCTAssertNil(MarkdownListParser.parse("Hello world.\nThis is a paragraph of prose."))
    }

    func testStrayDashInProseStaysSingle() {
        // One bullet amid prose should not explode into a list.
        XCTAssertNil(MarkdownListParser.parse("Some intro line\n- a single point\nmore prose here too"))
    }

    func testSimpleBullets() {
        let items = MarkdownListParser.parse("- buy milk\n- call dentist\n* water plants")
        XCTAssertEqual(items?.map(\.title), ["buy milk", "call dentist", "water plants"])
        XCTAssertEqual(items?.allSatisfy { !$0.isDone }, true)
        XCTAssertEqual(items?.allSatisfy { $0.tags.isEmpty }, true)
    }

    func testNumberedList() {
        let items = MarkdownListParser.parse("1. first\n2) second\n3. third")
        XCTAssertEqual(items?.map(\.title), ["first", "second", "third"])
    }

    func testCheckboxesDoneState() {
        let items = MarkdownListParser.parse("- [ ] todo one\n- [x] done two\n- [X] done three")
        XCTAssertEqual(items?.map(\.title), ["todo one", "done two", "done three"])
        XCTAssertEqual(items?.map(\.isDone), [false, true, true])
    }

    func testSingleCheckboxCountsAsList() {
        // A lone ticked checkbox is meaningful (done-import), so it parses.
        let items = MarkdownListParser.parse("- [x] shipped the release")
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?.isDone, true)
        XCTAssertEqual(items?.first?.title, "shipped the release")
    }

    func testNestingBecomesProjectParentLinksAndCompatibilityTags() {
        let text = """
        - Acme launch
          - draft the brief
          - book the venue
        - Personal
          - call mum
        """
        let items = MarkdownListParser.parse(text)
        XCTAssertEqual(items?.map(\.title), ["Acme launch", "draft the brief", "book the venue", "Personal", "call mum"])
        XCTAssertEqual(items?[0].tags, [])               // top-level header: no tags
        XCTAssertEqual(items?[1].tags, ["Acme launch"])  // children inherit the project
        XCTAssertEqual(items?[2].tags, ["Acme launch"])
        XCTAssertEqual(items?[3].tags, [])
        XCTAssertEqual(items?[4].tags, ["Personal"])
        XCTAssertEqual(items?.map(\.parentIndex), [nil, 0, 0, nil, 3])
        XCTAssertEqual(items?.map(\.depth), [0, 1, 1, 0, 1])
    }

    func testDeepNestingInheritsAllAncestors() {
        let text = """
        - Work
            - Project X
                - sub task
        """
        let items = MarkdownListParser.parse(text)
        XCTAssertEqual(items?.last?.title, "sub task")
        XCTAssertEqual(items?.last?.tags, ["Work", "Project X"])
        XCTAssertEqual(items?.map(\.parentIndex), [nil, 0, 1])
    }

    func testTabIndentation() {
        let text = "- Parent\n\t- child task"
        let items = MarkdownListParser.parse(text)
        XCTAssertEqual(items?.last?.tags, ["Parent"])
    }

    func testInlineHashtagsExtractedAndStripped() {
        let items = MarkdownListParser.parse("- call mum #personal #urgent\n- review PR #work")
        XCTAssertEqual(items?[0].title, "call mum")
        XCTAssertEqual(items?[0].tags, ["personal", "urgent"])
        XCTAssertEqual(items?[1].title, "review PR")
        XCTAssertEqual(items?[1].tags, ["work"])
    }

    func testProjectAndInlineTagsCombineDeduped() {
        let text = """
        - Acme
          - task #acme #ship
        """
        let items = MarkdownListParser.parse(text)
        // "Acme" project tag + inline "acme" should dedupe case-insensitively.
        XCTAssertEqual(items?.last?.tags.map { $0.lowercased() }, ["acme", "ship"])
    }

    func testNonListLinesIgnoredWhenListDominates() {
        let text = "- a\n- b\n- c\nsome trailing note"
        let items = MarkdownListParser.parse(text)
        XCTAssertEqual(items?.map(\.title), ["a", "b", "c"])
    }
}
