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

    /// One row: the current ceiling doubles as the control that changes it, which keeps
    /// this section the same shape as the panel's other headers.
    @ViewBuilder
    private var standaloneSection: some View {
        HStack {
            Text("Spend ceiling")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 8)

            Menu {
                embeddedPresets
            } label: {
                Text(currentLimitLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(ceilingHint)
            .accessibilityLabel(ceilingHint)
            .accessibilityValue(currentLimitLabel)
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

    private var ceilingHint: String {
        "Set the \(appState.selectedPeriod.label.lowercased()) spend ceiling"
    }

    private var currentLimitLabel: String {
        if let limit = appState.limit(for: appState.selectedPeriod) {
            return Formatters.limitDollars(limit)
        }
        return "Off"
    }
}
