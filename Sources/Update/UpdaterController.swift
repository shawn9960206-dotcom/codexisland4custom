import AppKit
import Foundation
import Sparkle
import SwiftUI

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app
/// can talk to Sparkle without importing it directly. Holds Sparkle's UI
/// driver (alert + download window) too — no extra delegate plumbing needed.
///
/// Auto-check cadence and the "automatically download" preference are stored
/// by Sparkle itself in NSUserDefaults under SU* keys, so we don't duplicate
/// that state here.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage: String?

    @Published var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        guard let feedURL else {
            showUpdateUnavailable(
                message: "This build does not include an update feed URL."
            )
            return
        }

        // Sparkle surfaces a low-level network error if the appcast URL is
        // missing (404), which is common before the first GitHub Release is
        // published. Probe the feed first so Settings shows a clear message
        // instead of Sparkle's generic failure dialog.
        isChecking = true
        statusMessage = "Checking update feed…"

        Task {
            let result = await probeFeed(feedURL)
            isChecking = false

            switch result {
            case .available:
                statusMessage = nil
                controller.checkForUpdates(nil)
            case .notPublished:
                statusMessage = "Update feed has not been published yet."
                showUpdateUnavailable(
                    message: "No appcast was found on GitHub yet. Create the first GitHub Release with appcast.xml, then Check again."
                )
            case .failed(let message):
                statusMessage = "Update feed is temporarily unavailable."
                showUpdateUnavailable(message: message)
            }
        }
    }

    private var feedURL: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return URL(string: raw)
    }

    private nonisolated func probeFeed(_ url: URL) async -> FeedProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 8
        request.setValue("codexisland4custom-updater", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("The update feed did not return a valid HTTP response.")
            }

            switch http.statusCode {
            case 200..<300:
                return .available
            case 404:
                return .notPublished
            default:
                return .failed("The update feed returned HTTP \(http.statusCode). Please try again later.")
            }
        } catch {
            return .failed("Could not reach the update feed: \(error.localizedDescription)")
        }
    }

    private func showUpdateUnavailable(message: String) {
        let alert = NSAlert()
        alert.messageText = "Updates are not available yet"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private enum FeedProbeResult {
    case available
    case notPublished
    case failed(String)
}
