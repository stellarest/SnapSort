import Foundation

enum SortMode: String, CaseIterable, Identifiable {
    case monthly
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .daily:
            return "Daily"
        }
    }
}
