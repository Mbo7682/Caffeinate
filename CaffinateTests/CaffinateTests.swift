import XCTest
@testable import Caffinate

final class CaffinateTests: XCTestCase {
    /// Never let a test reach the real helper: that spawns `sudo` / an admin prompt.
    @MainActor
    private func makeManager(now: @escaping () -> Date = { Date() }) -> CaffeinateManager {
        let lockScreen = LockScreenMessageService(
            readMessage: { .missing },
            writeMessage: { _ in true },
            clearMessage: { true }
        )
        return CaffeinateManager(lockScreen: lockScreen, now: now)
    }

    func testLockScreenMessageIndefinite() {
        XCTAssertEqual(
            LockScreenMessageService.message(end: nil),
            "Caffinate is keeping this Mac awake"
        )
    }

    @MainActor
    func testLockScreenMessageReadFailureAbortsWithoutSnapshotting() async {
        var readResults: [LockScreenMessageService.SnapshotReadResult] = [.failure, .missing]
        var writtenMessages: [String] = []
        let service = LockScreenMessageService(
            readMessage: { readResults.removeFirst() },
            writeMessage: {
                writtenMessages.append($0)
                return true
            },
            clearMessage: { true }
        )

        XCTAssertFalse(await service.applyForSession(end: nil))
        XCTAssertTrue(await service.applyForSession(end: nil))
        XCTAssertEqual(writtenMessages, ["Caffinate is keeping this Mac awake"])
        XCTAssertTrue(readResults.isEmpty)
    }

    @MainActor
    func testLockScreenMessageRestoresEmptySnapshotByWritingEmptyString() async {
        var writtenMessages: [String] = []
        var clearCount = 0
        let service = LockScreenMessageService(
            readMessage: { .value("") },
            writeMessage: {
                writtenMessages.append($0)
                return true
            },
            clearMessage: {
                clearCount += 1
                return true
            }
        )

        XCTAssertTrue(await service.applyForSession(end: nil))
        await service.restoreAfterSession()

        XCTAssertEqual(writtenMessages, ["Caffinate is keeping this Mac awake", ""])
        XCTAssertEqual(clearCount, 0)
    }

    @MainActor
    func testLockScreenMessageRetriesRestoreAfterWriteFailure() async {
        var restoreAttempts = 0
        let service = LockScreenMessageService(
            readMessage: { .value("Original") },
            writeMessage: { message in
                guard message == "Original" else { return true }
                restoreAttempts += 1
                return restoreAttempts > 1
            },
            clearMessage: { true }
        )

        XCTAssertTrue(await service.applyForSession(end: nil))
        await service.restoreAfterSession()
        await service.restoreAfterSession()

        XCTAssertEqual(restoreAttempts, 2)
    }

    @MainActor
    func testLockScreenMessageRetriesClearAfterFailure() async {
        var clearAttempts = 0
        let service = LockScreenMessageService(
            readMessage: { .missing },
            writeMessage: { _ in true },
            clearMessage: {
                clearAttempts += 1
                return clearAttempts > 1
            }
        )

        XCTAssertTrue(await service.applyForSession(end: nil))
        await service.restoreAfterSession()
        await service.restoreAfterSession()

        XCTAssertEqual(clearAttempts, 2)
    }

    @MainActor
    func testManagerAppliesAndRestoresLockScreenMessage() async {
        let applied = expectation(description: "lock screen message applied")
        let restored = expectation(description: "lock screen message restored")
        let service = LockScreenMessageService(
            readMessage: { .value("Original") },
            writeMessage: { message in
                if message == "Original" {
                    restored.fulfill()
                } else {
                    applied.fulfill()
                }
                return true
            },
            clearMessage: { true }
        )
        let manager = CaffeinateManager(lockScreen: service)
        manager.allowNotifications = false

        manager.start()
        await fulfillment(of: [applied], timeout: 2)
        manager.stop()
        await fulfillment(of: [restored], timeout: 2)
    }

    @MainActor
    func testManagerWaitsForPendingApplyBeforeRestoring() async {
        var readContinuation: CheckedContinuation<LockScreenMessageService.SnapshotReadResult, Never>?
        var writtenMessages: [String] = []
        let readStarted = expectation(description: "snapshot read started")
        let restored = expectation(description: "lock screen message restored")
        let service = LockScreenMessageService(
            readMessage: {
                await withCheckedContinuation { continuation in
                    readContinuation = continuation
                    readStarted.fulfill()
                }
            },
            writeMessage: { message in
                writtenMessages.append(message)
                if message == "Original" {
                    restored.fulfill()
                }
                return true
            },
            clearMessage: { true }
        )
        let manager = CaffeinateManager(lockScreen: service)
        manager.allowNotifications = false

        manager.start()
        await fulfillment(of: [readStarted], timeout: 2)
        manager.stop()
        readContinuation?.resume(returning: .value("Original"))
        await fulfillment(of: [restored], timeout: 2)

        XCTAssertEqual(
            writtenMessages,
            ["Caffinate is keeping this Mac awake", "Original"]
        )
    }

    @MainActor
    func testTerminationPreparationWaitsForPendingApplyAndRestore() async {
        var readContinuation: CheckedContinuation<LockScreenMessageService.SnapshotReadResult, Never>?
        let readStarted = expectation(description: "snapshot read started")
        let restored = expectation(description: "lock screen message restored")
        let terminationFinished = expectation(description: "termination preparation finished")
        terminationFinished.isInverted = true
        let service = LockScreenMessageService(
            readMessage: {
                await withCheckedContinuation { continuation in
                    readContinuation = continuation
                    readStarted.fulfill()
                }
            },
            writeMessage: { message in
                if message == "Original" {
                    restored.fulfill()
                }
                return true
            },
            clearMessage: { true }
        )
        let manager = CaffeinateManager(lockScreen: service)
        manager.allowNotifications = false

        manager.start()
        await fulfillment(of: [readStarted], timeout: 2)
        let terminationTask = Task {
            await manager.prepareForTermination()
            terminationFinished.fulfill()
        }

        await fulfillment(of: [terminationFinished], timeout: 0.1)
        terminationFinished.isInverted = false
        readContinuation?.resume(returning: .value("Original"))
        await terminationTask.value
        await fulfillment(of: [restored, terminationFinished], timeout: 2)
    }

    @MainActor
    func testDurationRestartUpdatesWithoutResnapshottingLockScreenMessage() async {
        var readCount = 0
        let initialApplied = expectation(description: "initial lock screen message applied")
        let timedMessageApplied = expectation(description: "timed lock screen message applied")
        let restored = expectation(description: "lock screen message restored")
        let service = LockScreenMessageService(
            readMessage: {
                readCount += 1
                return .value("Original")
            },
            writeMessage: { message in
                if message == "Original" {
                    restored.fulfill()
                } else if message.contains(" until ") {
                    timedMessageApplied.fulfill()
                } else {
                    initialApplied.fulfill()
                }
                return true
            },
            clearMessage: { true }
        )
        let manager = CaffeinateManager(lockScreen: service)
        manager.allowNotifications = false
        manager.duration = .indefinite

        manager.start()
        await fulfillment(of: [initialApplied], timeout: 2)
        manager.duration = .minutes(15)
        await fulfillment(of: [timedMessageApplied], timeout: 2)

        XCTAssertEqual(readCount, 1)
        manager.stop()
        await fulfillment(of: [restored], timeout: 2)
    }

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

    func testUntilMenuTitle() {
        XCTAssertEqual(SessionDuration.until(hour: 17, minute: 30).menuTitle, "Until 17:30")
    }

    func testNextOccurrenceRollsToTomorrowWhenPast() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 18, minute: 0))!
        let end = SessionDuration.nextOccurrence(hour: 17, minute: 30, from: now, calendar: cal)
        let parts = cal.dateComponents([.day, .hour, .minute], from: end)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(cal.component(.day, from: end), 1)
        XCTAssertEqual(cal.component(.month, from: end), 10)
        XCTAssertEqual(cal.component(.hour, from: end), 17)
        XCTAssertEqual(cal.component(.minute, from: end), 30)
    }

    func testUntilSecondsFromNow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 16, minute: 0))!
        let seconds = SessionDuration.until(hour: 17, minute: 0).seconds(from: now, calendar: cal)
        XCTAssertEqual(seconds, 3600)
    }

    @MainActor
    func testDesiredArgumentsIncludeWaitPIDAndRespectDisplaySleep() {
        let manager = makeManager()
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
        let manager = makeManager()
        manager.allowDisplaySleep = false
        manager.duration = .minutes(15)
        let args = manager.desiredArguments()
        XCTAssertTrue(args.contains("-d"))
        XCTAssertEqual(args.firstIndex(of: "-t").map { args[$0 + 1] }, Optional("900"))
    }

    @MainActor
    func testDesiredArgumentsPreservingRemaining() {
        let manager = makeManager()
        manager.duration = .minutes(30)
        manager.allowDisplaySleep = true
        let args = manager.desiredArguments(preservingRemaining: 120)
        XCTAssertEqual(args.firstIndex(of: "-t").map { args[$0 + 1] }, Optional("120"))
    }

    @MainActor
    func testSelectUntilSetsUntilDuration() {
        let manager = makeManager()
        defer { manager.stop() }

        manager.selectUntil(hour: 17, minute: 30)

        XCTAssertEqual(manager.duration, .until(hour: 17, minute: 30))
    }

    @MainActor
    func testUntilSessionKeepsEndTimeWhenReapplied() {
        let startedAt = Date()
        var clock = startedAt
        let manager = makeManager(now: { clock })
        manager.allowNotifications = false
        manager.allowDisplaySleep = true
        defer { manager.stop() }

        let target = startedAt.addingTimeInterval(3600)
        manager.duration = .until(
            hour: Calendar.current.component(.hour, from: target),
            minute: Calendar.current.component(.minute, from: target)
        )
        manager.start()

        guard let originalEnd = manager.sessionEndsAt else {
            return XCTFail("expected a session end time")
        }
        let total = Int(originalEnd.timeIntervalSince(startedAt))

        clock = startedAt.addingTimeInterval(600)
        manager.allowDisplaySleep = false

        XCTAssertEqual(manager.sessionEndsAt, originalEnd)
        XCTAssertEqual(manager.remainingSeconds, total - 600)
        XCTAssertEqual(
            manager.activeArguments.firstIndex(of: "-t").map { manager.activeArguments[$0 + 1] },
            Optional("\(total - 600)")
        )
    }

    @MainActor
    func testReconcileRestoresPersistedSnapshotAfterUnexpectedExit() async {
        let beforeCrash = LockScreenMessageService(
            readMessage: { .value("Original") },
            writeMessage: { _ in true },
            clearMessage: { true }
        )
        XCTAssertTrue(await beforeCrash.applyForSession(end: nil))

        var writtenMessages: [String] = []
        let afterRelaunch = LockScreenMessageService(
            readMessage: { .value(LockScreenMessageService.message(end: nil)) },
            writeMessage: {
                writtenMessages.append($0)
                return true
            },
            clearMessage: { true }
        )

        await afterRelaunch.reconcileAfterUnexpectedExit()
        XCTAssertEqual(writtenMessages, ["Original"])

        // The snapshot is consumed, so a later launch leaves the message alone.
        await afterRelaunch.reconcileAfterUnexpectedExit()
        XCTAssertEqual(writtenMessages, ["Original"])
    }

    @MainActor
    func testReconcileLeavesForeignLockScreenMessageAlone() async {
        let beforeCrash = LockScreenMessageService(
            readMessage: { .value("Original") },
            writeMessage: { _ in true },
            clearMessage: { true }
        )
        XCTAssertTrue(await beforeCrash.applyForSession(end: nil))

        var writtenMessages: [String] = []
        let afterRelaunch = LockScreenMessageService(
            readMessage: { .value("Set by someone else") },
            writeMessage: {
                writtenMessages.append($0)
                return true
            },
            clearMessage: { true }
        )

        await afterRelaunch.reconcileAfterUnexpectedExit()
        XCTAssertTrue(writtenMessages.isEmpty)
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

    func testPreferredZipAssetPrefersNamedZip() {
        let assets = [
            UpdateChecker.GitHubAsset(name: "notes.txt", browserDownloadUrl: "https://example.com/notes.txt"),
            UpdateChecker.GitHubAsset(name: "Caffinate-macOS.zip", browserDownloadUrl: "https://example.com/Caffinate-macOS.zip"),
            UpdateChecker.GitHubAsset(name: "other.zip", browserDownloadUrl: "https://example.com/other.zip")
        ]
        XCTAssertEqual(
            UpdateChecker.preferredZipAssetURL(from: assets)?.absoluteString,
            "https://example.com/Caffinate-macOS.zip"
        )
    }

    func testPreferredZipAssetFallsBackToFirstZip() {
        let assets = [
            UpdateChecker.GitHubAsset(name: "readme.md", browserDownloadUrl: "https://example.com/readme.md"),
            UpdateChecker.GitHubAsset(name: "build.zip", browserDownloadUrl: "https://example.com/build.zip")
        ]
        XCTAssertEqual(
            UpdateChecker.preferredZipAssetURL(from: assets)?.absoluteString,
            "https://example.com/build.zip"
        )
    }
}
