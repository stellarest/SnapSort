import SwiftUI

@main
struct SnapSortApp: App {
    @StateObject private var settings: SnapSortSettings
    @StateObject private var service: ScreenshotSorterService

    init() {
        let settings = SnapSortSettings()
        _settings = StateObject(wrappedValue: settings)
        _service = StateObject(wrappedValue: ScreenshotSorterService(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra("SnapSort", systemImage: "camera.viewfinder") {
            MenuContentView(settings: settings, service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
