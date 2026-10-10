import AppKit
import ApplicationServices
import CoreGraphics

/// Tracks the two TCC permissions the host needs. Polled so grants and revocations made in
/// System Settings while the app runs are picked up without user action.
@MainActor @Observable
final class Permissions {
    enum Kind: CaseIterable, Identifiable {
        case screenRecording, accessibility
        var id: Self { self }

        var title: String {
            switch self {
            case .screenRecording: "Screen Recording"
            case .accessibility: "Accessibility"
            }
        }

        var purpose: String {
            switch self {
            case .screenRecording: "Needed to show this Mac's screen on your Android device."
            case .accessibility: "Needed to control the pointer and keyboard from your Android device."
            }
        }

        var missingHelp: String {
            switch self {
            case .screenRecording:
                "Open System Settings › Privacy & Security › Screen & System Audio Recording, turn on Tetherly, then relaunch Tetherly. If it is already on, remove it with − and add it again."
            case .accessibility:
                "Open System Settings › Privacy & Security › Accessibility and turn on Tetherly. If it is already on, remove it with − and add it again."
            }
        }

        var settingsURL: URL {
            switch self {
            case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            }
        }
    }

    private(set) var granted: [Kind: Bool] = [:]
    private(set) var relaunchError: String?
    var allGranted: Bool { Kind.allCases.allSatisfy { granted[$0] == true } }

    init() {
        refresh()
        // Self is only borrowed for each refresh, never across the sleep; the loop ends once the model is gone.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func refresh() {
        granted = [
            .screenRecording: CGPreflightScreenCaptureAccess(),
            .accessibility: AXIsProcessTrusted(),
        ]
    }

    /// Triggers the system prompt (macOS only shows it once per app), then opens the right Settings pane.
    func request(_ kind: Kind) {
        switch kind {
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .accessibility:
            // String literal instead of kAXTrustedCheckOptionPrompt, which Swift 6 treats as non-Sendable global state.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        NSWorkspace.shared.open(kind.settingsURL)
    }

    /// Screen Recording grants often only take effect in a fresh process. Quits only once the new instance launched.
    func relaunch() {
        relaunchError = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.relaunchError = "Couldn't relaunch (\(error.localizedDescription)). Quit and reopen Tetherly manually."
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
