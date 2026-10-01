import AppKit
import Foundation

enum AppUpdateInstaller {
    enum InstallError: LocalizedError {
        case downloadFailed
        case invalidZip

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Could not download the update."
            case .invalidZip: return "The update archive did not contain Caffinate.app."
            }
        }
    }

    @MainActor
    static func confirmAndInstall(
        assetURL: URL?,
        releaseURL: URL,
        latest: String,
        prepareForQuit: () async -> Void
    ) async {
        let alert = NSAlert()
        alert.messageText = "Update to v\(latest)?"
        alert.informativeText = "Download and install Caffinate v\(latest)? The app will quit and reopen."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let assetURL else {
            NSWorkspace.shared.open(releaseURL)
            return
        }

        do {
            let newApp = try await downloadAndUnzip(assetURL: assetURL)
            try launchReplaceHandoff(
                newAppURL: newApp,
                targetAppURL: Bundle.main.bundleURL,
                releaseURL: releaseURL
            )
            await prepareForQuit()
            NSApp.terminate(nil)
        } catch {
            let fail = NSAlert()
            fail.messageText = "Update failed"
            fail.informativeText = error.localizedDescription + "\n\nOpening the release page instead."
            fail.runModal()
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private static func downloadAndUnzip(assetURL: URL) async throws -> URL {
        let (fileURL, response) = try await URLSession.shared.download(from: assetURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.downloadFailed
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaffinateUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("Caffinate-macOS.zip")
        try? FileManager.default.removeItem(at: zipPath)
        try FileManager.default.moveItem(at: fileURL, to: zipPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipPath.path, work.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.invalidZip }

        let appURL = work.appendingPathComponent("Caffinate.app")
        guard FileManager.default.fileExists(
            atPath: appURL.appendingPathComponent("Contents/Info.plist").path
        ) else {
            throw InstallError.invalidZip
        }
        return appURL
    }

    private static func launchReplaceHandoff(
        newAppURL: URL,
        targetAppURL: URL,
        releaseURL: URL
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        source_app="$1"
        target_app="$2"
        release_url="$3"
        stage_app="${target_app}.update"
        backup_app="${target_app}.backup"
        work_dir="$(dirname "$source_app")"

        cleanup() {
            rm -rf "$stage_app" "$work_dir"
            rm -f "$0"
        }

        fallback() {
            cleanup
            open "$release_url"
            exit 1
        }

        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done

        if ! rm -rf "$stage_app" || [ -e "$stage_app" ] || [ -e "$backup_app" ]; then
            fallback
        fi
        if ! ditto "$source_app" "$stage_app"; then
            fallback
        fi
        if ! mv "$target_app" "$backup_app"; then
            fallback
        fi
        if ! mv "$stage_app" "$target_app"; then
            mv "$backup_app" "$target_app" || true
            fallback
        fi
        if ! open "$target_app"; then
            if rm -rf "$target_app"; then
                mv "$backup_app" "$target_app" || true
            fi
            fallback
        fi

        rm -rf "$backup_app"
        cleanup
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffinate-update-handoff-\(pid).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            scriptURL.path,
            newAppURL.path,
            targetAppURL.path,
            releaseURL.absoluteString
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
    }
}
