import SwiftUI

/// The kinds of group people can start. Home is a standard group that begins with a house symbol.
enum GroupTemplate: String, CaseIterable, Identifiable, Hashable, Sendable {
    case standard
    case trip
    case couple
    case home

    var id: String { rawValue }

    var kind: GroupKind {
        switch self {
        case .standard, .home: .standard
        case .trip: .trip
        case .couple: .couple
        }
    }

    var defaultSymbol: String {
        switch self {
        case .standard: "person.3.fill"
        case .trip: "airplane"
        case .couple: "heart.fill"
        case .home: "house.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .trip: "Trip"
        case .couple: "Couple"
        case .home: "Home"
        }
    }

    var systemImage: String { defaultSymbol }
}
