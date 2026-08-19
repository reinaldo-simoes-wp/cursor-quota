import SwiftUI

@main
struct CursorQuotaApp: App {
    @StateObject private var appState = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(appState: appState)
        } label: {
            gaugeLabel
                .id(labelIdentity)
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var gaugeLabel: some View {
        if let image = GaugeLabelView(
            gauge: appState.gauge,
            trendLevels: appState.trendLevels,
            loadingPhase: loadingPhase
        ).renderedImage() {
            Image(nsImage: image)
        } else {
            Text(appState.gauge.title)
        }
    }

    private var loadingPhase: Double? {
        appState.isRefreshing ? appState.loadingPhase : nil
    }

    /// MenuBarExtra caches its label aggressively; the phase keeps each frame distinct.
    private var labelIdentity: String {
        let frame = appState.isRefreshing ? String(appState.loadingFrame) : "idle"
        let trend = appState.trendLevels?
            .map { String(Int(($0 * 100).rounded())) }
            .joined(separator: ",") ?? "none"
        let color = appState.gauge.limitColor.map(String.init(describing:)) ?? "none"
        return "\(appState.gauge.title)|\(color)|\(trend)|\(frame)"
    }
}
