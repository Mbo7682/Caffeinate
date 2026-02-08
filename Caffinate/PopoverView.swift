import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var manager: CaffeinateManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            optionsSection
            Divider()
            timeoutSection
            Divider()
            lockScreenSection
            Divider()
            mainToggle
            Divider()
            quitButton
        }
        .frame(width: 280)
        .padding(.vertical, 12)
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
                Text(manager.isActive ? "Keeping Mac awake" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if manager.hasTimeout {
                TextField("e.g. 3600", text: $manager.timeoutSeconds)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
            }
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

            Text("Shows “Caffinate is keeping this Mac awake” on the lock screen. You’ll be asked for your password only when you turn this option on.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var mainToggle: some View {
        Button {
            if manager.isActive {
                manager.stop()
            } else {
                manager.start()
            }
        } label: {
            HStack {
                Image(systemName: manager.isActive ? "stop.circle.fill" : "play.circle.fill")
                Text(manager.isActive ? "Stop" : "Start")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(manager.isActive ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
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
    PopoverView(manager: CaffeinateManager())
        .frame(width: 280)
}
