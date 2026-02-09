import Foundation

/// Represents the update status of the app.
enum UpdateStatus: Equatable {
    /// Not yet checked for updates.
    case idle
    /// Currently checking for updates.
    case checking
    /// The app is up to date.
    case upToDate
    /// A newer version is available.
    case updateAvailable(version: String, url: URL)
    /// The check failed (offline, network error, etc.) — silently ignored.
    case failed
}

/// Checks for app updates via the GitHub Releases API.
///
/// Uses the public endpoint:
/// `GET https://api.github.com/repos/Cyronlee/TransFlow/releases/latest`
///
/// The service is `@Observable` so SwiftUI views can react to status changes.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Current update status.
    private(set) var status: UpdateStatus = .idle

    /// Whether a check has already been performed in this app session.
    private var hasChecked = false

    private let owner = "Cyronlee"
    private let repo = "TransFlow"

    private init() {}

    /// Check for updates once per app launch. Subsequent calls are no-ops.
    func checkOnceOnLaunch() {
        guard !hasChecked else { return }
        hasChecked = true

        Task {
            await check()
        }
    }

    // MARK: - Private

    private func check() async {
        status = .checking

        do {
            let release = try await fetchLatestRelease()
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let currentVersion = currentAppVersion

            if isVersion(latestVersion, newerThan: currentVersion) {
                let releaseURL = URL(string: release.htmlURL)
                    ?? URL(string: "https://github.com/\(owner)/\(repo)/releases")!
                status = .updateAvailable(version: latestVersion, url: releaseURL)
            } else {
                status = .upToDate
            }
        } catch {
            // Silently fail — offline or API error should not affect the user.
            ErrorLogger.shared.log("Update check failed: \(error.localizedDescription)", source: "UpdateChecker")
            status = .failed
        }
    }

    /// Fetches the latest release metadata from GitHub.
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The current app version from the bundle (e.g. "1.0.0").
    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Simple semantic-version comparison: returns true when `lhs` > `rhs`.
    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }

        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - GitHub API Model

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum UpdateError: Error {
    case invalidResponse
}
