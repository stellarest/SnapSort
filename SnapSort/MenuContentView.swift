import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var settings: SnapSortSettings
    @ObservedObject var service: ScreenshotSorterService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Folder sorting", isOn: $settings.sortingEnabled)

            if settings.sortingEnabled {
                Picker("Sort mode", selection: $settings.sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("Use default folder name (Screenshots)", isOn: $settings.useDefaultFolderName)

                if !settings.useDefaultFolderName {
                    TextField("Custom folder name", text: $settings.customFolderName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            Text("Watching:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(service.watchedDirectoryDisplay)
                .font(.caption)
                .textSelection(.enabled)

            Text("Status: \(service.statusMessage)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit SnapSort") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
