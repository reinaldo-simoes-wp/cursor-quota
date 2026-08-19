import SwiftUI

struct PopoverFooter: View {
    @ObservedObject var appState: AppState

    /// Copy has no destination to point at, so the control says it worked itself.
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 6) {
                // The row has to fit five controls inside the panel's width, so the
                // three secondary ones are glyphs and only the two that need naming
                // keep their titles.
                Button {
                    appState.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .disabled(appState.isRefreshing)
                .fixedSize()
                .help("Refresh now")
                .accessibilityLabel("Refresh")

                Button {
                    PopoverActions.openURL(AppConstants.dashboardURL)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                }
                .fixedSize()
                .help("Open the Cursor dashboard")
                .accessibilityLabel("Open the Cursor dashboard")

                Menu {
                    Text("cursor-quota v\(AppConstants.version)")
                    Text("Token usage & spend for Cursor")
                    Text("Inspired by claude-quota")
                    Divider()
                    Button("GitHub") { PopoverActions.openURL(AppConstants.repoURL) }
                    Button("Latest release") {
                        PopoverActions.openURL("\(AppConstants.repoURL)/releases/latest")
                    }
                    Button("Report an issue") {
                        PopoverActions.openURL("\(AppConstants.repoURL)/issues")
                    }
                    Divider()
                    Text("Uses Cursor's undocumented dashboard API")
                    Text("Reads your login token locally (read-only)")
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                // Without this the menu stretches and strands its chevron mid-row.
                .menuIndicator(.hidden)
                .fixedSize()
                .help("About cursor-quota")
                .accessibilityLabel("About cursor-quota")

                Spacer(minLength: 6)

                Menu {
                    Button("Copy image") { copyImage() }
                    Button("Save as PNG…") {
                        UsageGraphExport.save(
                            levels: exportLevels,
                            period: appState.selectedPeriod
                        )
                    }
                } label: {
                    Label(
                        didCopy ? "Copied" : "Export",
                        systemImage: didCopy ? "checkmark" : "square.and.arrow.up"
                    )
                    .font(.system(size: 12))
                }
                // A refresh leaves the last trend in place, so the artwork stays
                // exportable while one is in flight. A period with no spend at all
                // would only draw a bare floor, which is not worth sharing.
                .disabled(!hasSpendToExport)
                .fixedSize()
                .help("Copy or save this trend as artwork")

                Button("Quit") {
                    PopoverActions.quit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            // Only above the row: the panel's own padding provides the bottom inset.
            .padding(.top, 12)
        }
        .onDisappear {
            copyResetTask?.cancel()
            didCopy = false
        }
    }

    private var exportLevels: [Double] {
        appState.trendLevels ?? []
    }

    private var hasSpendToExport: Bool {
        exportLevels.contains { $0 > 0 }
    }

    private func copyImage() {
        guard UsageGraphExport.copyToClipboard(levels: exportLevels) else { return }
        didCopy = true

        // Each copy owns the confirmation, so an earlier one cannot clear a later one.
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
