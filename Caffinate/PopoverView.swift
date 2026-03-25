import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var manager: CaffeinateManager
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            header
            if case .updateAvailable = updateChecker.state {
                Divider()
                updatesRow
            }
            Divider()
            optionsSection
            Divider()
            timeoutSection
            Divider()
            lockScreenSection
            Divider()
            quitButton
        }
        .frame(width: 280)
        .padding(.bottom, 12)
        .background(popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            Task { await manager.requestNotificationPermission() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Caffinate")
                    .font(.headline)
                if manager.isActive {
                    if manager.hasTimeout {
                        Text("Keeping Mac awake — \(manager.remainingSeconds)s remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Keeping Mac awake")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if manager.isActive {
                    manager.stop()
                } else {
                    manager.start()
                }
            } label: {
                Text(manager.isActive ? "Stop" : "Start")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(manager.isActive ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(manager.isActive ? Color.red.opacity(0.15) : Color.clear)
    }

    @ViewBuilder
    private var updatesRow: some View {
        if case .updateAvailable(_, let latest, let url) = updateChecker.state {
            HStack(spacing: 10) {
                Text("Updates")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Update v\(latest)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ForEach(CaffeinateManager.Option.allCases, id: \.self) { option in
                OptionRow(
                    option: option,
                    isOn: manager.options.contains(option),
                    action: { manager.toggle(option) }
                )
            }
        }
        .padding(.bottom, 8)
    }

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $manager.hasTimeout) {
                Text("Timeout (seconds)")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.top, 12)

            if manager.hasTimeout {
                TextField("e.g. 3600", text: $manager.timeoutSeconds)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
            }

            Toggle(isOn: $manager.lidClosedTimerMode) {
                Text("Lid closed mode (requires timeout)")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.top, 4)
            .onChange(of: manager.lidClosedTimerMode) { _, newValue in
                // Lid-closed mode must be time-bounded, so keep Timeout enabled while it is on.
                if newValue {
                    manager.hasTimeout = true
                }
            }

            Text("Uses caffeinate’s system-sleep prevention (best with a timeout).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
                .padding(.trailing, 16)
        }
        .padding(.bottom, 8)
    }

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $manager.showOnLockScreen) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.square")
                        .foregroundStyle(.secondary)
                    Text("Show on lock screen")
                        .font(.subheadline)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if manager.showOnLockScreen, manager.lockScreenSetupDone {
                Label("Password not needed for start/stop", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if manager.showOnLockScreen, (!manager.lockScreenSetupDone || manager.lockScreenPasswordReentryNeeded) {
                Button {
                    manager.runLockScreenOneTimeSetup()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text("Re-enter password")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }

            Text("Shows “Caffinate is keeping this Mac awake” on the lock screen. You’ll be asked for your password only when you turn this option on.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Image(systemName: "power")
                Text("Quit Caffinate")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var popoverBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}

struct OptionRow: View {
    let option: CaffeinateManager.Option
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue)
                        .font(.subheadline)
                    Text(option.help)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PopoverView(manager: CaffeinateManager(), updateChecker: UpdateChecker())
        .frame(width: 280)
}
