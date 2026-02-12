import Combine
import Foundation

@MainActor
final class SnapSortSettings: ObservableObject {
    @Published var sortingEnabled: Bool
    @Published var sortMode: SortMode
    @Published var useDefaultFolderName: Bool
    @Published var customFolderName: String

    var effectiveFolderName: String {
        if useDefaultFolderName {
            return Self.defaultFolderName
        }

        let trimmed = customFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = sanitizeFolderName(trimmed)
        return sanitized.isEmpty ? Self.defaultFolderName : sanitized
    }

    private static let defaultFolderName = "Screenshots"

    private enum Key {
        static let sortingEnabled = "sortingEnabled"
        static let sortMode = "sortMode"
        static let useDefaultFolderName = "useDefaultFolderName"
        static let customFolderName = "customFolderName"
    }

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sortingEnabled = defaults.object(forKey: Key.sortingEnabled) as? Bool ?? true
        sortMode = SortMode(rawValue: defaults.string(forKey: Key.sortMode) ?? "") ?? .monthly
        useDefaultFolderName = defaults.object(forKey: Key.useDefaultFolderName) as? Bool ?? true
        customFolderName = defaults.string(forKey: Key.customFolderName) ?? ""

        bindPersistence()
    }

    private func bindPersistence() {
        $sortingEnabled
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: Key.sortingEnabled) }
            .store(in: &cancellables)

        $sortMode
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0.rawValue, forKey: Key.sortMode) }
            .store(in: &cancellables)

        $useDefaultFolderName
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: Key.useDefaultFolderName) }
            .store(in: &cancellables)

        $customFolderName
            .dropFirst()
            .sink { [weak self] in self?.defaults.set($0, forKey: Key.customFolderName) }
            .store(in: &cancellables)
    }

    private func sanitizeFolderName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        return name.components(separatedBy: invalidCharacters).joined(separator: "-")
    }
}
