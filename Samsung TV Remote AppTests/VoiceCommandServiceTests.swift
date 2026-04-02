//
//  VoiceCommandServiceTests.swift
//  Samsung TV Remote AppTests
//
//  XCTest suite for VoiceCommandService command parsing.
//  Written TDD-first (before implementation of fixes).
//
//  Tests:
//  1. "go back" → KEY_RETURN (NOT KEY_REWIND) — regression for voice go-back bug
//  2. "rewind" → KEY_REWIND
//  3. "one" → KEY_1 (number word parsing)
//  4. "open netflix" → launchApp("3201907018807")
//

import XCTest
@testable import Samsung_TV_Remote_App

@MainActor
final class VoiceCommandServiceTests: XCTestCase {

    var service: VoiceCommandService!

    override func setUp() {
        super.setUp()
        service = VoiceCommandService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Bug Regression: "go back" must map to KEY_RETURN, not KEY_REWIND

    func testGoBackMapsToKeyReturn() {
        service.handleTranscript("go back")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'go back', got \(String(describing: service.lastResult))")
            return
        }
        XCTAssertEqual(key, "KEY_RETURN",
            "'go back' should map to KEY_RETURN, not KEY_REWIND. Bug: 'go back' was in both rewind and return phrase lists; rewind was parsed first.")
    }

    func testGoBackDoesNotTriggerRewind() {
        service.handleTranscript("go back")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'go back'")
            return
        }
        XCTAssertNotEqual(key, "KEY_REWIND",
            "'go back' must NOT map to KEY_REWIND after the fix.")
    }

    // MARK: - "rewind" must still map to KEY_REWIND

    func testRewindMapsToKeyRewind() {
        service.handleTranscript("rewind")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'rewind', got \(String(describing: service.lastResult))")
            return
        }
        XCTAssertEqual(key, "KEY_REWIND",
            "'rewind' should still map to KEY_REWIND.")
    }

    func testSkipBackMapsToKeyRewind() {
        service.handleTranscript("skip back")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'skip back'")
            return
        }
        XCTAssertEqual(key, "KEY_REWIND",
            "'skip back' should map to KEY_REWIND.")
    }

    func testBackwardsMapsToKeyRewind() {
        service.handleTranscript("backwards")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'backwards'")
            return
        }
        XCTAssertEqual(key, "KEY_REWIND",
            "'backwards' should map to KEY_REWIND.")
    }

    // MARK: - Number word parsing

    func testOneMapsToKey1() {
        service.handleTranscript("one")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'one', got \(String(describing: service.lastResult))")
            return
        }
        XCTAssertEqual(key, "KEY_1",
            "'one' should map to KEY_1.")
    }

    func testZeroMapsToKey0() {
        service.handleTranscript("zero")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'zero'")
            return
        }
        XCTAssertEqual(key, "KEY_0",
            "'zero' should map to KEY_0.")
    }

    func testChannelOnePrefixMapsToKey1() {
        service.handleTranscript("channel one")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'channel one'")
            return
        }
        XCTAssertEqual(key, "KEY_1",
            "'channel one' should map to KEY_1.")
    }

    // MARK: - App launch parsing

    func testOpenNetflixLaunchesNetflix() {
        service.handleTranscript("open netflix")
        guard case .launchApp(let appId) = service.lastResult else {
            XCTFail("Expected .launchApp result for 'open netflix', got \(String(describing: service.lastResult))")
            return
        }
        XCTAssertEqual(appId, "3201907018807",
            "'open netflix' should launch Netflix app ID 3201907018807.")
    }

    func testLaunchNetflixVariant() {
        service.handleTranscript("launch netflix")
        guard case .launchApp(let appId) = service.lastResult else {
            XCTFail("Expected .launchApp result for 'launch netflix'")
            return
        }
        XCTAssertEqual(appId, "3201907018807")
    }

    func testOpenYouTubeLaunchesYouTube() {
        service.handleTranscript("open youtube")
        guard case .launchApp(let appId) = service.lastResult else {
            XCTFail("Expected .launchApp result for 'open youtube'")
            return
        }
        XCTAssertEqual(appId, "111299001912",
            "'open youtube' should launch YouTube app ID 111299001912.")
    }

    // MARK: - Additional navigation commands

    func testBackMapsToKeyReturn() {
        service.handleTranscript("back")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'back'")
            return
        }
        XCTAssertEqual(key, "KEY_RETURN")
    }

    func testReturnMapsToKeyReturn() {
        service.handleTranscript("return")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'return'")
            return
        }
        XCTAssertEqual(key, "KEY_RETURN")
    }

    func testHomeMapsToKeyHome() {
        service.handleTranscript("home")
        guard case .key(let key) = service.lastResult else {
            XCTFail("Expected .key result for 'home'")
            return
        }
        XCTAssertEqual(key, "KEY_HOME")
    }

    func testUnrecognizedCommandReturnsUnknown() {
        service.handleTranscript("xyzzy gibberish foobar")
        guard case .unknown = service.lastResult else {
            XCTFail("Expected .unknown result for unrecognized command")
            return
        }
    }
}
