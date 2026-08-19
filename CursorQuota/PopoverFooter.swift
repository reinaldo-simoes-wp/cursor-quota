import SwiftUI

struct PopoverFooter: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    appState.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .disabled(appState.isRefreshing)

                Button("Dashboard") {
                    PopoverActions.openURL(AppConstants.dashboardURL)
                }
                .font(.system(size: 12))

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

                Spacer(minLength: 8)

                Button("Quit") {
                    PopoverActions.quit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            // Only above the row: the panel's own padding provides the bottom inset.
            .padding(.top, 12)
        }
    }
}
