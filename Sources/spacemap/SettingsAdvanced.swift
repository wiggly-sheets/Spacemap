import SwiftUI

struct SettingsAdvanced: View {
    @Binding var isYabaiHealthy: Bool?
    @Binding var isSocketHealthy: Bool?
    @Binding var isRefreshingDiagnostics: Bool
    @Binding var socketHealthInterval: Int
    @Binding var showExtraWindows: Bool

    let refreshDiagnostics: () -> Void
    let saveConfig: () -> Void

    private let socketHealthOptions = [15, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticStatusRow(title: "Yabai Process", isHealthy: isYabaiHealthy)
            DiagnosticStatusRow(title: "Spacemap Signal Socket", isHealthy: isSocketHealthy)

            Button("Refresh Status") {
                refreshDiagnostics()
            }
            .disabled(isRefreshingDiagnostics)

            SettingsFootnote(text: "Confirms yabai is running and its signals can reach Spacemap's Unix socket.")

            Picker("Socket Health Interval (s)", selection: $socketHealthInterval) {
                ForEach(socketHealthOptions, id: \.self) { v in
                    Text("\(v)").tag(v as Int)
                }
            }
            .onChange(of: socketHealthInterval) { _ in saveConfig() }

            Toggle("Show Extra Windows", isOn: $showExtraWindows)
                .onChange(of: showExtraWindows) { _ in saveConfig() }

            Text("Shows nonstandard utility and background window records. Regular app windows are always shown, whether tiled or floating.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}