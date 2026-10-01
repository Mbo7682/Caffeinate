import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, releaseURL: URL, assetURL: URL?)
        case failed(message: String)
    }

    struct GitHubAsset: Decodable, Equatable {
        let name: String?
        let browserDownloadUrl: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    @Published private(set) var state: State = .idle

    private var periodicTask: Task<Void, Never>?
    private let session: URLSession
    private let owner: String
    private let repo: String

    init(
        owner: String = "Mbo7682",
        repo: String = "Caffeinate",
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repo = repo
        self.session = session

        Task { [weak self] in
            guard let self else { return }
            await self.check()
        }
    }

    func startPeriodicChecks(interval: TimeInterval = 86_400) {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await self.check()
            }
        }
    }

    static func preferredZipAssetURL(from assets: [GitHubAsset]) -> URL? {
        let zips = assets.compactMap { asset -> (String, URL)? in
            guard let name = asset.name, name.lowercased().hasSuffix(".zip"),
                  let s = asset.browserDownloadUrl, let url = URL(string: s) else { return nil }
            return (name, url)
        }
        if let preferred = zips.first(where: { $0.0 == "Caffinate-macOS.zip" }) {
            return preferred.1
        }
        return zips.first?.1
    }

    func check() async {
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentVersion = (current?.isEmpty == false) ? current! : "0.0.0"

        state = .checking
        do {
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Caffinate", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed(message: "Unexpected response.")
                return
            }
            guard (200...299).contains(http.statusCode) else {
                // No releases yet on the fork is common — treat as up to date.
                if http.statusCode == 404 {
                    state = .upToDate(current: currentVersion)
                    return
                }
                state = .failed(message: "GitHub check failed (\(http.statusCode)).")
                return
            }

            let decoded = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            let latest = (decoded.tagName ?? decoded.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let latestVersion = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
            let htmlUrl = decoded.htmlUrl ?? "https://github.com/\(owner)/\(repo)/releases/latest"
            let releaseUrl = URL(string: htmlUrl) ?? URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
            let assetURL = Self.preferredZipAssetURL(from: decoded.assets ?? [])

            if latestVersion.isEmpty {
                state = .failed(message: "No release version found.")
                return
            }

            if VersionCompare.isNewer(latestVersion, than: currentVersion) {
                state = .updateAvailable(
                    current: currentVersion,
                    latest: latestVersion,
                    releaseURL: releaseUrl,
                    assetURL: assetURL
                )
            } else {
                state = .upToDate(current: currentVersion)
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private struct GitHubLatestRelease: Decodable {
        let tagName: String?
        let name: String?
        let htmlUrl: String?
        let assets: [GitHubAsset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlUrl = "html_url"
            case assets
        }
    }
}
