import SwiftUI

@main
struct CaffinateApp: App {
    @StateObject private var caffeinateManager = CaffeinateManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(manager: caffeinateManager)
        } label: {
            Image(systemName: caffeinateManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 280, height: 420)
    }
}

