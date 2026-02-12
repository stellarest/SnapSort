import Foundation

struct ScreenshotLocationResolver {
    private let fileManager = FileManager.default

    func currentScreenshotDirectory() -> URL {
        let fallback = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)

        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture"),
              let location = domain["location"] as? String,
              !location.isEmpty else {
            return fallback
        }

        let expandedPath = (location as NSString).expandingTildeInPath
        let resolvedURL = URL(fileURLWithPath: expandedPath, isDirectory: true)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return resolvedURL
        }

        return fallback
    }
}
