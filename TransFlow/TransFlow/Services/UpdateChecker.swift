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

/// Checks for app updates via the TransFlow backend API.
///
/// Uses the endpoint: `GET https://transflow.cyron.space/api/version`
///
/// The service is `@Observable` so SwiftUI views can react to status changes.
/// Failures are silent — they never block or interrupt the user.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Current update status.
    private(set) var status: UpdateStatus = .idle

    /// Whether a successful check has been performed in this app session.
    private var hasSucceeded = false

    private static let versionAPI = "https://transflow.cyron.space/api/version"

    private init() {}

    /// Check for updates once per app launch.
    /// If a previous check succeeded, subsequent calls are no-ops.
    /// If the previous check failed, it will retry.
    func checkOnceOnLaunch() {
        guard !hasSucceeded else { return }

        Task {
            await check()
        }
    }

    // MARK: - Private

    private func check() async {
        status = .checking

        do {
            let response = try await fetchVersionInfo()
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

            hasSucceeded = true
            if response.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                let url = URL(string: response.url) ?? URL(string: "https://github.com/Cyronlee/TransFlow/releases/latest")!
                status = .updateAvailable(version: response.version, url: url)
            } else {
                status = .upToDate
            }
        } catch {
            ErrorLogger.shared.log("Update check failed: \(error.localizedDescription)", source: "UpdateChecker")
            status = .failed
        }
    }

    private func fetchVersionInfo() async throws -> VersionResponse {
        let url = URL(string: Self.versionAPI)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(VersionResponse.self, from: data)
    }
}

// MARK: - API Response Model

private struct VersionResponse: Codable {
    let version: String
    let url: String
    let release_date: String
}
