import XCTest
@testable import AzureGallery

/// Tests the pause/resume state machine on BackupEngine.
/// Does not require a live photo library or Azure credentials.
@MainActor
final class BackupEnginePauseTests: XCTestCase {

    private var engine: BackupEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = BackupEngine.shared
        // Ensure we start from a known, unpaused state.
        if engine.isPaused { engine.resume() }
    }

    override func tearDown() async throws {
        // Always leave the engine unpaused after each test.
        if engine.isPaused { engine.resume() }
        try await super.tearDown()
    }

    // MARK: - Initial state

    func testInitialStateIsNotPaused() {
        XCTAssertFalse(engine.isPaused)
    }

    // MARK: - pause()

    func testPauseSetsIsPaused() {
        engine.pause()
        XCTAssertTrue(engine.isPaused)
    }

    func testPauseIsIdempotent() {
        engine.pause()
        engine.pause()   // second call should be a no-op
        XCTAssertTrue(engine.isPaused)
    }

    // MARK: - resume()

    func testResumeClears_isPaused() {
        engine.pause()
        engine.resume()
        XCTAssertFalse(engine.isPaused)
    }

    func testResumeOnUnpausedEngineIsNoop() {
        // Should not crash or toggle to true.
        engine.resume()
        XCTAssertFalse(engine.isPaused)
    }

    // MARK: - Round-trip

    func testPauseResumeCycle() {
        engine.pause()
        XCTAssertTrue(engine.isPaused, "Should be paused after pause()")
        engine.resume()
        XCTAssertFalse(engine.isPaused, "Should be running after resume()")
    }

    func testMultiplePauseResumeCycles() {
        for _ in 0..<5 {
            engine.pause()
            XCTAssertTrue(engine.isPaused)
            engine.resume()
            XCTAssertFalse(engine.isPaused)
        }
    }
}
