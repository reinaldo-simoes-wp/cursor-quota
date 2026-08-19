import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Group {
            if let tokenError = appState.tokenError {
                Text("⚠ \(tokenError)")
                Button("Refresh now") { appState.refreshNow() }
                Divider()
                Button("Open Cursor dashboard") { openURL(AppConstants.dashboardURL) }
                Button("Check for Updates…") { updateController.checkForUpdates() }
                    .disabled(!updateController.canCheckForUpdates)
                // Without this the app cannot be quit while stuck on a token error.
                Button("Quit CursorQuota") { NSApplication.shared.terminate(nil) }
            } else {
                menuContent
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        let effective = appState.effectiveScope
        let periodLabel = appState.selectedPeriod.label
        let headerSuffix = appState.display == .total ? "" : " · \(appState.display.label)"

        Text("\(appState.header) — \(periodLabel)\(headerSuffix)")
            .font(.system(size: 12))

        Divider()

        if let identity = appState.identity, identity.isAdmin, identity.teamID != nil {
            scopeSection(identity: identity)
            Divider()
        }

        displaySection
        Divider()
        periodSection(effectiveScope: effective)
        modelSection
        limitsSection
        Divider()

        Button("Refresh now") { appState.refreshNow() }
            .disabled(appState.isRefreshing)

        Button("Open Cursor dashboard") {
            openURL(AppConstants.dashboardURL)
        }

        Button("Check for Updates…") {
            updateController.checkForUpdates()
        }
        .disabled(!updateController.canCheckForUpdates)

        Button("Quit CursorQuota") {
            NSApplication.shared.terminate(nil)
        }

        Menu("About") {
            Text("cursor-quota v\(AppConstants.version)")
            Text("Token usage & spend for Cursor, in your menu bar")
            Text("Inspired by claude-quota")
            Divider()
            Button("GitHub") { openURL(AppConstants.repoURL) }
            Button("Report an issue") { openURL("\(AppConstants.repoURL)/issues") }
            Divider()
            Text("Uses Cursor's undocumented dashboard API — may break without notice")
            Text("Reads your Cursor login token locally (read-only); nothing leaves your Mac except calls to cursor.com")
        }
    }

    @ViewBuilder
    private func scopeSection(identity: CursorIdentity) -> some View {
        Button {
            appState.selectScope(.you)
        } label: {
            Label("Scope: You", systemImage: appState.scope == .you ? "checkmark" : "")
        }

        Button {
            appState.selectScope(.team)
        } label: {
            Label("Scope: Team (\(identity.teamName))", systemImage: appState.scope == .team ? "checkmark" : "")
        }
    }

    private var displaySection: some View {
        Menu("Display: \(appState.display.label)") {
            ForEach(DisplayKey.allCases) { key in
                Button {
                    appState.selectDisplay(key)
                } label: {
                    if appState.display == key {
                        Label(key.label, systemImage: "checkmark")
                    } else {
                        Text(key.label)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func periodSection(effectiveScope: ScopeKey) -> some View {
        ForEach(PeriodKey.allCases) { period in
            Button {
                appState.selectPeriod(period)
            } label: {
                Text(periodRowText(period: period, effectiveScope: effectiveScope))
            }
            .foregroundStyle(periodColor(period: period, effectiveScope: effectiveScope))
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        if let data = appState.results[appState.selectedPeriod] {
            let label = appState.selectedPeriod.label.lowercased()
            let aggs = data.aggregations.sorted { $0.totalCents > $1.totalCents }

            if !aggs.isEmpty {
                Divider()
                Text("Models (\(label))")
                    .font(.system(size: 12))

                ForEach(Array(aggs.enumerated()), id: \.offset) { _, agg in
                    let io = agg.inputTokens + agg.outputTokens
                    let cache = agg.cacheReadTokens + agg.cacheWriteTokens
                    Text(
                        "\(agg.modelIntent): \(Formatters.cost(cents: agg.totalCents)) · \(Formatters.tokens(io)) io · \(Formatters.tokens(cache)) cache"
                    )
                    .font(.system(size: 11, design: .monospaced))
                }
            }

            Text("Cache tokens (\(label)): \(Formatters.tokens(data.cacheTokens()))")
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        Divider()
        Menu("Limits") {
            limitsScopeMenus(scopeRows: limitScopeRows)
        }
    }

    private var limitScopeRows: [(ScopeKey, String)] {
        var rows: [(ScopeKey, String)] = [(.you, "You")]
        if let identity = appState.identity, identity.isAdmin, identity.teamID != nil {
            rows.append((.team, "Team (\(identity.teamName))"))
        }
        return rows
    }

    @ViewBuilder
    private func limitsScopeMenus(scopeRows: [(ScopeKey, String)]) -> some View {
        ForEach(scopeRows, id: \.0.rawValue) { scopeKey, scopeName in
            ForEach(PeriodKey.allCases) { period in
                limitMenu(scopeKey: scopeKey, scopeName: scopeName, period: period)
            }
        }
    }

    @ViewBuilder
    private func limitMenu(scopeKey: ScopeKey, scopeName: String, period: PeriodKey) -> some View {
        let current = appState.limits[LimitKey(scope: scopeKey, period: period)]
        let shown = current.map { Formatters.limitDollars($0) } ?? "off"

        Menu("\(scopeName) · \(period.label): \(shown)") {
            if current != nil {
                Button("Off") {
                    appState.setLimit(scope: scopeKey, period: period, action: "off")
                }
                Divider()
            }
            ForEach(LimitPresets.presets(scope: scopeKey, period: period), id: \.self) { preset in
                Button {
                    appState.setLimit(scope: scopeKey, period: period, action: String(format: "%.0f", preset))
                } label: {
                    if current == preset {
                        Label(Formatters.limitDollars(preset), systemImage: "checkmark")
                    } else {
                        Text(Formatters.limitDollars(preset))
                    }
                }
            }
        }
    }

    private func periodRowText(period: PeriodKey, effectiveScope: ScopeKey) -> String {
        let mark = period == appState.selectedPeriod ? "✓ " : "   "
        if let data = appState.results[period] {
            var text = "\(mark)\(period.label): \(Formatters.cost(cents: data.totalCostCents)) · \(Formatters.tokens(data.ioTokens())) tokens"
            if let limit = appState.limits[LimitKey(scope: effectiveScope, period: period)] {
                let pct = Double(data.totalCostCents) / 100.0 / limit
                text += String(format: " · %.0f%% of %@", pct * 100, Formatters.limitDollars(limit))
            }
            return text
        }
        let err = appState.errors[period] ?? "no data"
        return "\(mark)\(period.label): ⚠ \(err)"
    }

    private func periodColor(period: PeriodKey, effectiveScope: ScopeKey) -> Color {
        guard let data = appState.results[period],
              let limit = appState.limits[LimitKey(scope: effectiveScope, period: period)] else {
            return .primary
        }
        let pct = Double(data.totalCostCents) / 100.0 / limit
        switch LimitColor.forPercent(pct) {
        case .red: return .red
        case .orange: return .orange
        case .none: return .primary
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
