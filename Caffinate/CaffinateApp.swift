import SwiftUI
import AppKit

@main
struct CaffinateApp: App {
    @StateObject private var caffeinateManager = CaffeinateManager()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(manager: caffeinateManager, updateChecker: updateChecker)
        } label: {
            Image(systemName: caffeinateManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .contextMenu {
                    Button(caffeinateManager.isActive ? "Stop" : "Start") {
                        if caffeinateManager.isActive {
                            caffeinateManager.stop()
                        } else {
                            caffeinateManager.start()
                        }
                    }
                    Divider()
                    Button("Quit Caffinate") {
                        NSApplication.shared.terminate(nil)
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 280, height: 420)
    }
}

