import SwiftUI
import AppKit

@main
struct CaffinateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item + menus are AppKit (no Settings window).
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: CaffeinateManager?
    private var updateChecker: UpdateChecker?
    private var statusItemController: StatusItemController?
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // XCTest hosts the app process; skip UI so `xcodebuild test` can exit.
        if NSClassFromString("XCTestCase") != nil {
            return
        }
        let manager = CaffeinateManager(lockScreen: LockScreenMessageService())
        let updateChecker = UpdateChecker()
        self.manager = manager
        self.updateChecker = updateChecker
        updateChecker.startPeriodicChecks()
        statusItemController = StatusItemController(manager: manager, updateChecker: updateChecker)
        manager.handleAppDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.prepareForTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { [weak self, weak sender] in
            await manager.prepareForTermination()
            guard !Task.isCancelled else { return }
            self?.finishTermination(sender)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak sender] in
            guard let self, self.terminationTask != nil else { return }
            self.terminationTask?.cancel()
            self.finishTermination(sender)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func finishTermination(_ application: NSApplication?) {
        guard terminationTask != nil else { return }
        terminationTask = nil
        application?.reply(toApplicationShouldTerminate: true)
    }
}
