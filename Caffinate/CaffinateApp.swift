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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // XCTest hosts the app process; skip UI so `xcodebuild test` can exit.
        if NSClassFromString("XCTestCase") != nil {
            return
        }
        let manager = CaffeinateManager()
        let updateChecker = UpdateChecker()
        self.manager = manager
        self.updateChecker = updateChecker
        statusItemController = StatusItemController(manager: manager, updateChecker: updateChecker)
        manager.handleAppDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.prepareForTermination()
        statusItemController?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
