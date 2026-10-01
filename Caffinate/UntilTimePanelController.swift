import AppKit

@MainActor
final class UntilTimePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var picker: NSDatePicker?
    private var onSet: ((Int, Int) -> Void)?

    func present(onSet: @escaping (Int, Int) -> Void) {
        self.onSet = onSet

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keep awake until"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let picker = NSDatePicker(frame: NSRect(x: 40, y: 60, width: 200, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.datePickerMode = .single
        picker.dateValue = Date().addingTimeInterval(30 * 60)
        panel.contentView?.addSubview(picker)

        let set = NSButton(title: "Set", target: self, action: #selector(setTapped))
        set.frame = NSRect(x: 150, y: 16, width: 80, height: 32)
        set.keyEquivalent = "\r"
        panel.contentView?.addSubview(set)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.frame = NSRect(x: 60, y: 16, width: 80, height: 32)
        panel.contentView?.addSubview(cancel)

        self.picker = picker
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func setTapped() {
        guard let date = picker?.dateValue else { return }
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        onSet?(hour, minute)
        closePanel()
    }

    @objc private func cancelTapped() {
        closePanel()
    }

    func windowWillClose(_ notification: Notification) {
        clearState()
    }

    private func closePanel() {
        let closing = panel
        clearState()
        closing?.close()
    }

    private func clearState() {
        panel?.delegate = nil
        panel = nil
        picker = nil
        onSet = nil
    }
}
