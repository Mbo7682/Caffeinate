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

/// Shared template SF Symbols for menu items (Apple Menus HIG: icons sparingly, with purpose).
private enum MenuSymbol {
    static func image(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Menu bar extra with a standard `NSMenu` (Apple HIG: menu, not popover).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let manager: CaffeinateManager
    private let updateChecker: UpdateChecker

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

        // Template glyph — system tints for light/dark menu bar and highlight (HIG).
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
        // Only rebuild the root status-item menu (not Duration/Settings submenus).
        guard menu == statusItem?.menu else { return }
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // Primary action — icon matches the menu-bar glyph (HIG: highlight key features).
        let keepAwake = NSMenuItem(
            title: manager.menuToggleTitle,
            action: #selector(toggleCaffeinate),
            keyEquivalent: ""
        )
        keepAwake.target = self
        keepAwake.state = manager.isActive ? .on : .off
        keepAwake.image = MenuSymbol.image(
            manager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves"
        )
        menu.addItem(keepAwake)

        // Show current selection on the parent (common status-menu pattern).
        let duration = NSMenuItem(
            title: "Duration",
            action: nil,
            keyEquivalent: ""
        )
        duration.image = MenuSymbol.image("timer")
        duration.submenu = makeDurationMenu()
        // Trailing hint via tool tip; submenu checkmarks carry the selection.
        duration.toolTip = manager.duration.menuTitle
        menu.addItem(duration)

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.image = MenuSymbol.image("gearshape")
        settings.submenu = makeSettingsMenu()
        menu.addItem(settings)

        menu.addItem(.separator())

        if case .updateAvailable(_, let latest, let url) = updateChecker.state {
            let update = NSMenuItem(
                title: "Update to v\(latest)…",
                action: #selector(openUpdate(_:)),
                keyEquivalent: ""
            )
            update.target = self
            update.representedObject = url
            update.image = MenuSymbol.image("arrow.down.circle")
            menu.addItem(update)
            menu.addItem(.separator())
        }

        // Quit stays text-only — system convention; avoid icon noise on destructive exit.
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
            let item = NSMenuItem(
                title: preset.menuTitle,
                action: #selector(selectDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = manager.duration == preset ? .on : .off
            item.image = MenuSymbol.image(preset.menuSymbolName)
            menu.addItem(item)
        }
        return menu
    }

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")
        menu.addItem(settingsItem(
            "Launch at Login",
            symbol: "power.circle",
            tag: .launchAtLogin,
            on: manager.launchAtLogin
        ))
        menu.addItem(settingsItem(
            "Activate at Launch",
            symbol: "bolt.circle",
            tag: .activateAtLaunch,
            on: manager.activateAtLaunch
        ))
        menu.addItem(settingsItem(
            "Allow Display Sleep",
            symbol: "sun.max",
            tag: .allowDisplaySleep,
            on: manager.allowDisplaySleep
        ))
        menu.addItem(settingsItem(
            "Allow Notifications",
            symbol: "bell",
            tag: .allowNotifications,
            on: manager.allowNotifications
        ))
        menu.addItem(.separator())
        menu.addItem(settingsItem(
            "On Power Connect",
            symbol: "cable.connector",
            tag: .activateOnPowerConnect,
            on: manager.activateOnPowerConnect
        ))
        menu.addItem(settingsItem(
            "On Power Disconnect",
            symbol: "battery.25",
            tag: .deactivateOnPowerDisconnect,
            on: manager.deactivateOnPowerDisconnect
        ))

        let version = NSMenuItem(title: appVersionLabel, action: nil, keyEquivalent: "")
        version.isEnabled = false
        version.image = MenuSymbol.image("info.circle")
        menu.addItem(.separator())
        menu.addItem(version)
        return menu
    }

    private func settingsItem(
        _ title: String,
        symbol: String,
        tag: SettingsMenuTag,
        on: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag.rawValue
        item.state = on ? .on : .off
        item.image = MenuSymbol.image(symbol)
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

    @objc private func openUpdate(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
