import XCTest
@testable import Caffinate

final class CaffinateTests: XCTestCase {
    func testBuildArgumentsIndefiniteStayAwakeAllowDisplaySleep() {
        let args = CaffeinateCommandBuilder.buildArguments(
            preventIdleSleep: true,
            preventDisplaySleep: false,
            timeoutSeconds: nil
        )
        XCTAssertEqual(args, ["-i"])
    }

    func testBuildArgumentsWithScreenAndTimeout() {
        let args = CaffeinateCommandBuilder.buildArguments(
            preventIdleSleep: true,
            preventDisplaySleep: true,
            timeoutSeconds: 900
        )
        XCTAssertEqual(args, ["-i", "-d", "-t", "900"])
    }

    func testHasEffectiveKeepAwakeFlags() {
        XCTAssertTrue(CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(["-i", "-w", "1"]))
        XCTAssertTrue(CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(["-d"]))
        XCTAssertFalse(CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(["-w", "1"]))
        XCTAssertFalse(CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(["-t", "10"]))
    }

    func testSessionDurationSeconds() {
        XCTAssertNil(SessionDuration.indefinite.seconds)
        XCTAssertEqual(SessionDuration.minutes(15).seconds, 900)
        XCTAssertEqual(SessionDuration.minutes(60).seconds, 3600)
    }

    @MainActor
    func testDesiredArgumentsIncludeWaitPIDAndRespectDisplaySleep() {
        let manager = CaffeinateManager()
        manager.allowDisplaySleep = true
        manager.duration = .indefinite
        let args = manager.desiredArguments()
        XCTAssertTrue(args.contains("-i"))
        XCTAssertFalse(args.contains("-d"))
        guard let wIndex = args.firstIndex(of: "-w") else {
            return XCTFail("expected -w")
        }
        XCTAssertEqual(args[wIndex + 1], "\(ProcessInfo.processInfo.processIdentifier)")
    }

    @MainActor
    func testDesiredArgumentsIncludeDisplayWhenNotAllowedToSleep() {
        let manager = CaffeinateManager()
        manager.allowDisplaySleep = false
        manager.duration = .minutes(15)
        let args = manager.desiredArguments()
        XCTAssertTrue(args.contains("-d"))
        XCTAssertEqual(args.firstIndex(of: "-t").map { args[$0 + 1] }, Optional("900"))
    }

    func testExpectedTypesFromArguments() {
        XCTAssertEqual(
            PowerAssertionProbe.expectedTypes(fromArguments: ["-i", "-d"]),
            Set(["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"])
        )
        XCTAssertEqual(
            PowerAssertionProbe.expectedTypes(fromArguments: ["-i"]),
            Set(["PreventUserIdleSystemSleep"])
        )
    }

    func testEvaluateHealth() {
        let expected = Set(["PreventUserIdleSystemSleep"])
        XCTAssertEqual(
            PowerAssertionProbe.evaluate(
                processAlive: true,
                heldTypes: expected,
                expectedTypes: expected
            ),
            .working(heldLabels: ["Stay awake"])
        )
    }

    func testVersionCompare() {
        XCTAssertTrue(VersionCompare.isNewer("2.1.0", than: "2.0.0"))
        XCTAssertFalse(VersionCompare.isNewer("2.0.0", than: "2.0.0"))
    }
}
