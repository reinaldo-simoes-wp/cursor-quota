import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if let tokenError = appState.tokenError {
                tokenErrorPanel(tokenError)
            } else {
                contentPanel
            }
        }
        .frame(width: PopoverTheme.width)
        .animation(PopoverTheme.layoutAnimation, value: layoutSignature)
        .onAppear {
            // Menu-bar extra windows are often non-key; activation keeps nested menus usable.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Laid out at its intrinsic height: a menu bar window sizes itself from the
    /// content, and a ScrollView reports no ideal height, which collapses the panel.
    @ViewBuilder
    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: PopoverTheme.sectionSpacing) {
            headerSection

            if appState.identity?.isAdmin == true, appState.identity?.teamID != nil {
                scopeSegment
            }

            HeroSpendView(appState: appState)
            PeriodPills(appState: appState)

            if selectedPeriodHasError {
                periodErrorBanner
            } else {
                TrendLandscape(appState: appState)
                ModelMixView(appState: appState)
                LimitsControl(appState: appState)
            }

            PopoverFooter(appState: appState)
        }
        .padding(.horizontal, PopoverTheme.padding)
        .padding(.top, PopoverTheme.padding)
        .padding(.bottom, PopoverTheme.bottomPadding)
    }

    private var selectedPeriodHasError: Bool {
        appState.errors[appState.selectedPeriod] != nil
    }

    /// Everything that changes the panel's height, so the window resize is animated
    /// rather than snapping between layouts.
    private var layoutSignature: String {
        let models = appState.results[appState.selectedPeriod]?.aggregations.count ?? -1
        let error = appState.errors[appState.selectedPeriod] ?? ""
        return [
            appState.selectedPeriod.rawValue,
            appState.display.rawValue,
            appState.tokenError ?? "",
            error,
            String(models),
            appState.selectedModel ?? "",
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var periodErrorBanner: some View {
        if let error = appState.errors[appState.selectedPeriod] {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 8) {
            if let icon = PopoverActions.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            }

            Text("Cursor Usage")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)
            metricToggle
        }
    }

    /// Drives the headline figure, the period pills, and the menu bar together.
    private var metricToggle: some View {
        Picker("Figure", selection: Binding(
            get: { appState.display },
            set: { appState.selectDisplay($0) }
        )) {
            ForEach(DisplayKey.allCases) { key in
                Text(key.label).tag(key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var scopeSegment: some View {
        if let identity = appState.identity {
            Picker("Scope", selection: Binding(
                get: { appState.scope },
                set: { appState.selectScope($0) }
            )) {
                Text("You").tag(ScopeKey.you)
                Text("Team").tag(ScopeKey.team)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Team (\(identity.teamName))")
        }
    }

    @ViewBuilder
    private func tokenErrorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)

            Text("Open Cursor once to refresh your session token, or add a manual token in ~/.config/cursor-quota/token.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Refresh now") { appState.refreshNow() }
                Button("Open dashboard") {
                    PopoverActions.openURL(AppConstants.dashboardURL)
                }
                Spacer()
                Button("Quit") { PopoverActions.quit() }
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, PopoverTheme.padding)
        .padding(.top, PopoverTheme.padding)
        .padding(.bottom, PopoverTheme.bottomPadding)
    }
}
