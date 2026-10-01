import AppKit
import Combine

private enum SettingsMenuTag: Int {
    case launchAtLogin = 1
    case activateAtLaunch
    case allowDisplaySleep
    case allowNotifications
    case activateOnPowerConnect
    case deactivateOnPowerDisconnect
}

/// Leading emoji for status-item menu titles (NSMenuItem.image is unreliable here).
/// Keep these colorful/emoji-style for a consistent, scannable look.
private enum MenuGlyph {
    static let awake = "☕️"
    static let duration = "⏱️"
    static let settings = "⚙️"
    static let update = "⬇️"
    static let indefinite = "♾️"
    static let timed = "⏲️"
    static let login = "🚀"
    static let launch = "⚡️"
    static let display = "☀️"
    static let bell = "🔔"
    static let plugIn = "🔌"
    static let unplug = "🔋"
    static let info = "ℹ️"

    static func titled(_ glyph: String, _ title: String) -> String {
        "\(glyph)  \(title)"
    }
}

private struct UpdateMenuContext {
    let releaseURL: URL
    let assetURL: URL?
    let latest: String
}

/// Menu bar extra with a standard `NSMenu` (Apple HIG: menu, not popover).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let manager: CaffeinateManager
    private let updateChecker: UpdateChecker
    private let untilPanelController = UntilTimePanelController()

    private var statusItem: NSStatusItem?
    private var activeObservation: AnyCancellable?
    private var healthObservation: AnyCancellable?
    private var durationObservation: AnyCancellable?
    private var updateObservation: AnyCancellable?
    private var remainingObservation: AnyCancellable?

    init(manager: CaffeinateManager, updateChecker: UpdateChecker) {
        self.manager = manager
        self.updateChecker = updateChecker
        super.init()
        installStatusItem()
        observeState()
    }

    func prepareForTermination() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = true
        item.menu = menu
        statusItem = item
        refreshStatusItemAppearance()
        rebuildMenu(menu)
    }

    private func observeState() {
        activeObservation = manager.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemAppearance() }
        healthObservation = manager.$health
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemAppearance() }
        durationObservation = manager.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemAppearance() }
        remainingObservation = manager.$remainingSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemAppearance() }
        updateObservation = updateChecker.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItemAppearance() }
    }

    private func refreshStatusItemAppearance() {
        updateStatusItemImage()
        statusItem?.button?.toolTip = "Caffinate — \(manager.statusSubtitle)"
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }

        let isBroken: Bool = {
            if case .broken = manager.health { return true }
            return false
        }()

        let symbolName = manager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Caffinate")?
            .withSymbolConfiguration(config) else { return }

        image.isTemplate = true
        button.image = image
        button.appearsDisabled = false
        button.contentTintColor = isBroken ? .systemRed : nil
        button.alphaValue = 1.0
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let keepAwake = NSMenuItem(
            title: MenuGlyph.titled(MenuGlyph.awake, manager.menuToggleTitle),
            action: #selector(toggleCaffeinate),
            keyEquivalent: ""
        )
        keepAwake.target = self
        keepAwake.state = manager.isActive ? .on : .off
        menu.addItem(keepAwake)

        let duration = NSMenuItem(
            title: MenuGlyph.titled(
                MenuGlyph.duration,
                "Duration — \(manager.duration.menuTitle)"
            ),
            action: nil,
            keyEquivalent: ""
        )
        duration.submenu = makeDurationMenu()
        menu.addItem(duration)

        let settings = NSMenuItem(
            title: MenuGlyph.titled(MenuGlyph.settings, "Settings"),
            action: nil,
            keyEquivalent: ""
        )
        settings.submenu = makeSettingsMenu()
        menu.addItem(settings)

        menu.addItem(.separator())

        switch updateChecker.state {
        case .updateAvailable(_, let latest, let releaseURL, let assetURL):
            let update = NSMenuItem(
                title: MenuGlyph.titled(MenuGlyph.update, "Update to v\(latest)…"),
                action: #selector(installUpdate(_:)),
                keyEquivalent: ""
            )
            update.target = self
            update.representedObject = UpdateMenuContext(
                releaseURL: releaseURL,
                assetURL: assetURL,
                latest: latest
            )
            menu.addItem(update)
        case .checking:
            let checking = NSMenuItem(
                title: "Checking for Updates…",
                action: nil,
                keyEquivalent: ""
            )
            checking.isEnabled = false
            menu.addItem(checking)
        default:
            let check = NSMenuItem(
                title: MenuGlyph.titled(MenuGlyph.update, "Check for Updates…"),
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            check.target = self
            menu.addItem(check)
        }

        let quit = NSMenuItem(
            title: "Quit Caffinate",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    private func makeDurationMenu() -> NSMenu {
        let menu = NSMenu(title: "Duration")
        for (index, preset) in SessionDuration.presets.enumerated() {
            let glyph = preset == .indefinite ? MenuGlyph.indefinite : MenuGlyph.timed
            let item = NSMenuItem(
                title: MenuGlyph.titled(glyph, preset.menuTitle),
                action: #selector(selectDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = manager.duration == preset ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let untilItem = NSMenuItem(
            title: MenuGlyph.titled(MenuGlyph.timed, "Until…"),
            action: #selector(openUntilPanel),
            keyEquivalent: ""
        )
        untilItem.target = self
        if case .until = manager.duration {
            untilItem.state = .on
        }
        menu.addItem(untilItem)
        return menu
    }

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")
        menu.addItem(settingsItem(MenuGlyph.login, "Launch at Login", tag: .launchAtLogin, on: manager.launchAtLogin))
        menu.addItem(settingsItem(MenuGlyph.launch, "Activate at Launch", tag: .activateAtLaunch, on: manager.activateAtLaunch))
        menu.addItem(settingsItem(MenuGlyph.display, "Allow Display Sleep", tag: .allowDisplaySleep, on: manager.allowDisplaySleep))
        menu.addItem(settingsItem(MenuGlyph.bell, "Allow Notifications", tag: .allowNotifications, on: manager.allowNotifications))
        menu.addItem(.separator())
        menu.addItem(settingsItem(MenuGlyph.plugIn, "On Power Connect", tag: .activateOnPowerConnect, on: manager.activateOnPowerConnect))
        menu.addItem(settingsItem(MenuGlyph.unplug, "On Power Disconnect", tag: .deactivateOnPowerDisconnect, on: manager.deactivateOnPowerDisconnect))

        let version = NSMenuItem(
            title: MenuGlyph.titled(MenuGlyph.info, appVersionLabel),
            action: nil,
            keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(version)
        return menu
    }

    private func settingsItem(_ glyph: String, _ title: String, tag: SettingsMenuTag, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(
            title: MenuGlyph.titled(glyph, title),
            action: #selector(toggleSetting(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = tag.rawValue
        item.state = on ? .on : .off
        return item
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    // MARK: - Actions

    @objc private func toggleCaffeinate() {
        if manager.isActive {
            manager.stop()
        } else {
            manager.start()
        }
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        let presets = SessionDuration.presets
        guard presets.indices.contains(sender.tag) else { return }
        manager.selectDuration(presets[sender.tag])
    }

    @objc private func openUntilPanel() {
        untilPanelController.present { [weak self] hour, minute in
            self?.manager.selectUntil(hour: hour, minute: minute)
        }
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let tag = SettingsMenuTag(rawValue: sender.tag) else { return }
        switch tag {
        case .launchAtLogin:
            manager.launchAtLogin.toggle()
        case .activateAtLaunch:
            manager.activateAtLaunch.toggle()
        case .allowDisplaySleep:
            manager.allowDisplaySleep.toggle()
        case .allowNotifications:
            manager.allowNotifications.toggle()
        case .activateOnPowerConnect:
            manager.activateOnPowerConnect.toggle()
        case .deactivateOnPowerDisconnect:
            manager.deactivateOnPowerDisconnect.toggle()
        }
    }

    @objc private func checkForUpdates() {
        Task { await updateChecker.check() }
    }

    @objc private func installUpdate(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? UpdateMenuContext else { return }
        Task { @MainActor in
            await AppUpdateInstaller.confirmAndInstall(
                assetURL: ctx.assetURL,
                releaseURL: ctx.releaseURL,
                latest: ctx.latest,
                prepareForQuit: { [weak self] in
                    if let manager = self?.manager {
                        await manager.prepareForTermination()
                    }
                }
            )
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
