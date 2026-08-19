import SwiftUI

struct LimitsControl: View {
    @ObservedObject var appState: AppState
    /// When true, renders only preset actions (for embedding in a Menu).
    var embedded: Bool = false

    var body: some View {
        if embedded {
            embeddedPresets
        } else {
            standaloneSection
        }
    }

    @ViewBuilder
    private var standaloneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spend ceiling")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(currentLimitLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Menu("Set limit for \(appState.selectedPeriod.label.lowercased())") {
                embeddedPresets
            }
            .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var embeddedPresets: some View {
        let scope = appState.effectiveScope
        let period = appState.selectedPeriod
        let current = appState.limits[LimitKey(scope: scope, period: period)]

        if current != nil {
            Button("Off") {
                appState.setLimit(scope: scope, period: period, action: "off")
            }
            Divider()
        }

        ForEach(LimitPresets.presets(scope: scope, period: period), id: \.self) { preset in
            Button {
                appState.setLimit(scope: scope, period: period, action: String(format: "%.0f", preset))
            } label: {
                if current == preset {
                    Label(Formatters.limitDollars(preset), systemImage: "checkmark")
                } else {
                    Text(Formatters.limitDollars(preset))
                }
            }
        }
    }

    private var currentLimitLabel: String {
        if let limit = appState.limit(for: appState.selectedPeriod) {
            return Formatters.limitDollars(limit)
        }
        return "Off"
    }
}
