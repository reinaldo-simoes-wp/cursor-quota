import SwiftUI

enum PopoverTheme {
    static let width: CGFloat = 340
    static let padding: CGFloat = 16
    /// The footer's buttons carry bezel chrome below their labels, so the panel needs
    /// a deeper bottom inset than the top to look evenly spaced.
    static let bottomPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 14
    static let cornerRadius: CGFloat = 10
    /// Keeps the panel a fixed, glanceable height regardless of how many models ran.
    static let maxModelRows = 6
    /// Shared timing so every figure in the panel settles together.
    static let valueAnimation: Animation = .easeInOut(duration: 0.3)
    /// Used when a section appears or disappears and the window has to resize.
    static let layoutAnimation: Animation = .easeInOut(duration: 0.22)
}

enum PopoverActions {
    static var appIcon: NSImage? {
        NSImage(named: NSImage.applicationIconName)
    }

    static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppState {
    func limit(for period: PeriodKey) -> Double? {
        limits[LimitKey(scope: effectiveScope, period: period)]
    }

    func limitPercent(costCents: Int, limit: Double) -> Double {
        Double(costCents) / 100.0 / limit
    }

    func limitSwiftUIColor(costCents: Int, limit: Double) -> Color {
        switch LimitColor.forPercent(limitPercent(costCents: costCents, limit: limit)) {
        case .red: .red
        case .orange: .orange
        case .none: .primary
        }
    }
}
