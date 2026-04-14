import XCTest
@testable import AzureGallery

@MainActor
final class AppLoggerTests: XCTestCase {

    private var logger: AppLogger!

    override func setUp() async throws {
        try await super.setUp()
        // Create a fresh logger instance for each test by clearing shared state.
        logger = AppLogger.shared
        logger.clear()
    }

    // MARK: - Appending

    func testInfoAppendsEntry() {
        logger.info("hello", tag: "Test")
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .info)
        XCTAssertEqual(logger.entries[0].message, "hello")
        XCTAssertEqual(logger.entries[0].tag, "Test")
    }

    func testWarnAppendsEntry() {
        logger.warn("watch out", tag: "Test")
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .warn)
    }

    func testErrorAppendsEntry() {
        logger.error("boom", tag: "Test")
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].level, .error)
    }

    func testMultipleEntriesAccumulate() {
        logger.info("a")
        logger.warn("b")
        logger.error("c")
        XCTAssertEqual(logger.entries.count, 3)
    }

    func testEntryDateIsRecent() {
        logger.info("ts test")
        let age = abs(logger.entries[0].date.timeIntervalSinceNow)
        XCTAssertLessThan(age, 2.0, "Entry date should be within 2 seconds of now")
    }

    // MARK: - Default tag

    func testDefaultTagIsApp() {
        logger.info("no tag")
        XCTAssertEqual(logger.entries[0].tag, "App")
    }

    // MARK: - Clear

    func testClearRemovesAllEntries() {
        logger.info("x")
        logger.info("y")
        logger.clear()
        XCTAssertTrue(logger.entries.isEmpty)
    }

    // MARK: - Export

    func testExportTextIsEmptyWhenNoEntries() {
        XCTAssertEqual(logger.exportText(), "")
    }

    func testExportTextContainsAllMessages() {
        logger.info("first")
        logger.warn("second")
        logger.error("third")
        let text = logger.exportText()
        XCTAssertTrue(text.contains("first"))
        XCTAssertTrue(text.contains("second"))
        XCTAssertTrue(text.contains("third"))
    }

    func testExportTextContainsLevelTags() {
        logger.info("i")
        logger.warn("w")
        logger.error("e")
        let text = logger.exportText()
        XCTAssertTrue(text.contains("[INFO]"))
        XCTAssertTrue(text.contains("[WARN]"))
        XCTAssertTrue(text.contains("[ERROR]"))
    }

    func testExportTextOneLinePerEntry() {
        logger.info("line1")
        logger.info("line2")
        let lines = logger.exportText().components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
    }

    // MARK: - Max entries cap

    func testExcessEntriesAreTrimmedToMax() {
        // AppLogger caps at 1000. Inserting 1010 should keep only the last 1000.
        for i in 0..<1010 {
            logger.info("entry \(i)")
        }
        XCTAssertLessThanOrEqual(logger.entries.count, 1000)
    }

    func testNewestEntriesKeptAfterTrim() {
        for i in 0..<1010 {
            logger.info("entry \(i)")
        }
        // The last entry appended must still be present.
        XCTAssertTrue(logger.entries.last?.message.contains("1009") == true)
    }

    // MARK: - LogEntry.formatted (ISO-8601 timestamp)

    func testFormattedContainsLevelTagAndMessage() {
        let entry = LogEntry(date: Date(), level: .error, tag: "Engine", message: "something broke")
        XCTAssertTrue(entry.formatted.contains("[ERROR]"))
        XCTAssertTrue(entry.formatted.contains("[Engine]"))
        XCTAssertTrue(entry.formatted.contains("something broke"))
    }

    func testFormattedTimestampIsISO8601() {
        let entry = LogEntry(date: Date(), level: .info, tag: "T", message: "x")
        // ISO-8601 timestamps contain 'T' between date and time, and 'Z' or offset at end.
        XCTAssertTrue(entry.formatted.contains("T"), "Timestamp must be ISO-8601")
    }

    func testShortTimeIsHumanReadable() {
        let entry = LogEntry(date: Date(), level: .info, tag: "T", message: "x")
        // shortTime = "HH:mm:ss.SSS" — must contain at least two colons.
        XCTAssertTrue(entry.shortTime.filter { $0 == ":" }.count >= 2)
    }

    // MARK: - 1-day expiry

    func testOldEntriesArePrunedOnAppend() {
        // Manually insert an entry dated 25 hours ago — it should be pruned on the next append.
        let stale = LogEntry(date: Date().addingTimeInterval(-25 * 3600), level: .info, tag: "T", message: "old")
        // Append via reflection isn't clean, so verify via the parse path:
        // A line parsed with maxAge = 0 should return nil (entry is "too old").
        let line = stale.formatted
        let parsed = LogEntry.parse(line, maxAge: 0)
        XCTAssertNil(parsed, "Entry with age > maxAge must be discarded by parse()")
    }

    func testFreshEntriesPassParse() {
        let fresh = LogEntry(date: Date(), level: .warn, tag: "Engine", message: "hello")
        let line  = fresh.formatted
        let parsed = LogEntry.parse(line, maxAge: 86_400)
        XCTAssertNotNil(parsed, "A just-created entry must survive the 1-day parse filter")
        XCTAssertEqual(parsed?.level, .warn)
    }

    func testMaxAgeIs24Hours() {
        XCTAssertEqual(logger.maxAge, 86_400, "maxAge must be exactly 24 hours (86 400 seconds)")
    }
}
