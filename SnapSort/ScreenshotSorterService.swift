import Combine
import CoreServices
import Foundation

@MainActor
final class ScreenshotSorterService: ObservableObject {
    @Published private(set) var watchedDirectoryDisplay: String = "Resolving screenshot location..."
    @Published private(set) var statusMessage: String = "Starting"

    private let settings: SnapSortSettings
    private let resolver = ScreenshotLocationResolver()
    private let fileManager = FileManager.default

    private var watcher: DirectoryWatcher?
    private var watchedDirectory: URL?
    private var knownEntries: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private var locationPollTimer: Timer?

    private let supportedExtensions: Set<String> = ["png", "heic", "jpg", "jpeg", "tiff", "gif"]
    private let temporaryExtensions: Set<String> = ["tmp", "temp", "partial", "download", "crdownload"]
    private let screenshotMetadataKeys: [CFString] = [
        "kMDItemIsScreenCapture" as CFString,
        "kMDItemImageIsScreenshot" as CFString
    ]

    init(settings: SnapSortSettings) {
        self.settings = settings
        bindSettings()
        refreshWatchDirectory(force: true)
        startLocationPolling()
    }

    deinit {
        locationPollTimer?.invalidate()
        watcher?.stop()
    }

    private func bindSettings() {
        settings.$sortingEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.statusMessage = enabled ? "Folder sorting enabled" : "Folder sorting disabled"
            }
            .store(in: &cancellables)

        settings.$sortMode
            .dropFirst()
            .sink { [weak self] mode in
                self?.statusMessage = "Sort mode: \(mode.displayName)"
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$useDefaultFolderName, settings.$customFolderName)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.statusMessage = "Destination folder: \(self?.settings.effectiveFolderName ?? "Screenshots")"
            }
            .store(in: &cancellables)
    }

    private func startLocationPolling() {
        locationPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWatchDirectory(force: false)
            }
        }
    }

    private func refreshWatchDirectory(force: Bool) {
        let resolved = resolver.currentScreenshotDirectory().standardizedFileURL

        if !force, resolved == watchedDirectory {
            return
        }

        watchedDirectory = resolved
        watchedDirectoryDisplay = resolved.path
        knownEntries = snapshotEntries(in: resolved)

        watcher?.stop()

        do {
            let watcher = DirectoryWatcher(url: resolved) { [weak self] in
                Task { @MainActor in
                    self?.processDirectoryChange()
                }
            }
            try watcher.start()
            self.watcher = watcher
            statusMessage = "Watching \(resolved.lastPathComponent)"
        } catch {
            statusMessage = "Unable to watch folder: \(error.localizedDescription)"
            self.watcher = nil
        }
    }

    private func processDirectoryChange() {
        guard let directory = watchedDirectory else {
            return
        }

        let currentEntries = snapshotEntries(in: directory)
        let newEntries = currentEntries.subtracting(knownEntries).sorted()
        knownEntries = currentEntries

        guard !newEntries.isEmpty else {
            return
        }

        guard settings.sortingEnabled else {
            statusMessage = "Detected \(newEntries.count) new file(s); sorting is off"
            return
        }

        Task { [weak self] in
            await self?.moveNewScreenshots(newEntries, baseDirectory: directory)
        }
    }

    private func snapshotEntries(in directory: URL) -> Set<String> {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return Set(urls.map(\.path))
    }

    private func shouldSortFile(at url: URL) -> Bool {
        let fileName = url.lastPathComponent
        if shouldIgnoreFileName(fileName) {
            return false
        }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    private func shouldIgnoreFileName(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        if lowercased == ".ds_store" {
            return true
        }
        if lowercased.hasPrefix(".") || lowercased.hasSuffix("~") {
            return true
        }

        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return temporaryExtensions.contains(ext)
    }

    private func sortScreenshot(at sourceURL: URL, screenshotDate: Date, baseDirectory: URL) throws -> Bool {
        let destinationFolder = destinationFolder(for: screenshotDate, baseDirectory: baseDirectory, mode: settings.sortMode)

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let destinationURL = uniqueDestination(for: sourceURL, in: destinationFolder)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return true
    }

    private func fileDate(for url: URL) -> Date {
        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            return values.creationDate ?? values.contentModificationDate ?? Date()
        }
        return Date()
    }

    private func isWithinCurrentSortWindow(_ screenshotDate: Date, now: Date = Date()) -> Bool {
        switch settings.sortMode {
        case .daily:
            return Calendar.current.isDate(screenshotDate, inSameDayAs: now)
        case .monthly:
            let screenshotComponents = Calendar.current.dateComponents([.year, .month], from: screenshotDate)
            let nowComponents = Calendar.current.dateComponents([.year, .month], from: now)
            return screenshotComponents.year == nowComponents.year &&
                screenshotComponents.month == nowComponents.month
        }
    }

    private func destinationFolder(for date: Date, baseDirectory: URL, mode: SortMode) -> URL {
        let folderName = settings.effectiveFolderName
        let dateComponent = formattedDateComponent(from: date, mode: mode)
        return baseDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(dateComponent, isDirectory: true)
    }

    private func formattedDateComponent(from date: Date, mode: SortMode) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        switch mode {
        case .monthly:
            formatter.dateFormat = "yyyy-MM"
        case .daily:
            formatter.dateFormat = "yyyy-MM-dd"
        }

        return formatter.string(from: date)
    }

    private func uniqueDestination(for sourceURL: URL, in directory: URL) -> URL {
        let fileName = sourceURL.lastPathComponent
        var candidate = directory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        var index = 1
        while true {
            let numberedName = ext.isEmpty ? "\(baseName) (\(index))" : "\(baseName) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(numberedName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func moveNewScreenshots(_ newEntries: [String], baseDirectory: URL) async {
        var movedCount = 0

        for path in newEntries {
            let sourceURL = URL(fileURLWithPath: path)
            guard shouldSortFile(at: sourceURL) else {
                continue
            }

            guard await waitUntilFileIsStable(at: sourceURL) else {
                // Let a subsequent filesystem event retry this path.
                knownEntries.remove(sourceURL.path)
                continue
            }

            guard await confirmsScreenshotMetadata(at: sourceURL) else {
                continue
            }

            let screenshotDate = fileDate(for: sourceURL)
            guard isWithinCurrentSortWindow(screenshotDate) else {
                continue
            }

            do {
                if try sortScreenshot(at: sourceURL, screenshotDate: screenshotDate, baseDirectory: baseDirectory) {
                    movedCount += 1
                }
            } catch {
                statusMessage = "Failed to move \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if movedCount > 0 {
            statusMessage = "Moved \(movedCount) screenshot(s)"
        }
    }

    private func waitUntilFileIsStable(at url: URL, maxAttempts: Int = 5, intervalNanoseconds: UInt64 = 300_000_000) async -> Bool {
        var previousSize: Int?
        var previousModifiedAt: Date?

        for attempt in 0..<maxAttempts {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                return false
            }

            let currentSize = values.fileSize
            let currentModifiedAt = values.contentModificationDate
            let isReadable = fileManager.isReadableFile(atPath: url.path)

            if isReadable,
               let previousSize,
               let previousModifiedAt,
               previousSize == currentSize,
               previousModifiedAt == currentModifiedAt {
                return true
            }

            previousSize = currentSize
            previousModifiedAt = currentModifiedAt

            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        return false
    }

    private func confirmsScreenshotMetadata(at url: URL, maxAttempts: Int = 4, intervalNanoseconds: UInt64 = 300_000_000) async -> Bool {
        for attempt in 0..<maxAttempts {
            if isScreenshotFromMetadata(url) {
                return true
            }

            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        return false
    }

    private func isScreenshotFromMetadata(_ url: URL) -> Bool {
        guard let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return false
        }

        for key in screenshotMetadataKeys {
            guard let attributeValue = MDItemCopyAttribute(mdItem, key) else {
                continue
            }

            if metadataFlagIsTrue(attributeValue) {
                return true
            }
        }

        return false
    }

    private func metadataFlagIsTrue(_ value: CFTypeRef) -> Bool {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = value as? NSString {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }
        return false
    }
}
