import AppKit
import Combine
import Sparkle

/// Owns Sparkle for the lifetime of this menu-bar-only application.
///
/// Sparkle performs a scheduled background check once per day and presents
/// its standard, signed update UI when an update is available. Users can also
/// initiate the same flow from the menu.
@MainActor
final class UpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false

    lazy var updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    private var canCheckObservation: AnyCancellable?

    override init() {
        super.init()
        let updater = updaterController.updater
        canCheckObservation = updater
            .publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Menu bar apps have no ordinary foreground window, so Sparkle needs
    /// permission to surface scheduled update reminders itself.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        // Sparkle otherwise orders scheduled alerts behind other apps for an
        // LSUIElement process. Temporarily showing in the Dock makes the alert
        // visible and focusable; the accessory policy is restored afterwards.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
