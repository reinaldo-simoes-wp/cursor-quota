import SwiftUI

struct PopoverFooter: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 6) {
                Button {
                    appState.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .disabled(appState.isRefreshing)
                // Buttons share a cramped row, so they keep their width instead of
                // truncating their titles.
                .fixedSize()

                Button("Dashboard") {
                    PopoverActions.openURL(AppConstants.dashboardURL)
                }
                .font(.system(size: 12))
                .fixedSize()

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
    }
}
