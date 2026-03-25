import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String, url: URL)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

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

        // Auto-check on app launch so the header button is immediately accurate.
        Task { [weak self] in
            guard let self else { return }
            await self.check()
        }
    }

    func check() async {
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
                state = .failed(message: "GitHub check failed (\(http.statusCode)).")
                return
            }

            let decoded = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            let latest = (decoded.tagName ?? decoded.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let latestVersion = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
            let htmlUrl = decoded.htmlUrl ?? "https://github.com/\(owner)/\(repo)/releases/latest"
            let releaseUrl = URL(string: htmlUrl) ?? URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!

            if latestVersion.isEmpty {
                state = .failed(message: "No release version found.")
                return
            }

            if Self.isNewer(latestVersion, than: currentVersion) {
                state = .updateAvailable(current: currentVersion, latest: latestVersion, url: releaseUrl)
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

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlUrl = "html_url"
        }
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 }
        }
        let ap = parts(a)
        let bp = parts(b)
        let n = max(ap.count, bp.count)
        for i in 0..<n {
            let ai = i < ap.count ? ap[i] : 0
            let bi = i < bp.count ? bp[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}

