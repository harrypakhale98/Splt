import Foundation

/// The symbols offered in the picker, each with the name VoiceOver reads for it.
enum GroupSymbols {
    static let all: [String] = [
        "person.3.fill", "house.fill", "airplane", "car.fill", "fork.knife", "cart.fill",
        "cup.and.saucer.fill", "wineglass.fill", "gift.fill", "heart.fill", "tent.fill",
        "beach.umbrella.fill", "ticket.fill", "film.fill", "music.note", "gamecontroller.fill",
        "figure.run", "dumbbell.fill", "bicycle", "tram.fill", "bus.fill", "fuelpump.fill",
        "bed.double.fill", "building.2.fill", "briefcase.fill", "graduationcap.fill", "book.fill",
        "pawprint.fill", "leaf.fill", "sun.max.fill", "snowflake", "mountain.2.fill",
        "sailboat.fill", "figure.skiing.downhill", "sportscourt.fill", "camera.fill",
        "bag.fill", "creditcard.fill", "party.popper.fill", "balloon.fill"
    ]

    /// A written name for a symbol, rather than one pieced together from its file name.
    static func label(for symbol: String) -> String {
        switch symbol {
        case "person.3.fill": String(localized: "People")
        case "house.fill": String(localized: "Home")
        case "airplane": String(localized: "Plane")
        case "car.fill": String(localized: "Car")
        case "fork.knife": String(localized: "Food")
        case "cart.fill": String(localized: "Groceries")
        case "cup.and.saucer.fill": String(localized: "Coffee")
        case "wineglass.fill": String(localized: "Drinks")
        case "gift.fill": String(localized: "Gift")
        case "heart.fill": String(localized: "Heart")
        case "tent.fill": String(localized: "Camping")
        case "beach.umbrella.fill": String(localized: "Beach")
        case "ticket.fill": String(localized: "Tickets")
        case "film.fill": String(localized: "Film")
        case "music.note": String(localized: "Music")
        case "gamecontroller.fill": String(localized: "Games")
        case "figure.run": String(localized: "Running")
        case "dumbbell.fill": String(localized: "Gym")
        case "bicycle": String(localized: "Bike")
        case "tram.fill": String(localized: "Tram")
        case "bus.fill": String(localized: "Bus")
        case "fuelpump.fill": String(localized: "Fuel")
        case "bed.double.fill": String(localized: "Stay")
        case "building.2.fill": String(localized: "City")
        case "briefcase.fill": String(localized: "Work")
        case "graduationcap.fill": String(localized: "School")
        case "book.fill": String(localized: "Books")
        case "pawprint.fill": String(localized: "Pets")
        case "leaf.fill": String(localized: "Nature")
        case "sun.max.fill": String(localized: "Sun")
        case "snowflake": String(localized: "Snow")
        case "mountain.2.fill": String(localized: "Mountains")
        case "sailboat.fill": String(localized: "Sailing")
        case "figure.skiing.downhill": String(localized: "Skiing")
        case "sportscourt.fill": String(localized: "Sports")
        case "camera.fill": String(localized: "Camera")
        case "bag.fill": String(localized: "Shopping")
        case "creditcard.fill": String(localized: "Card")
        case "party.popper.fill": String(localized: "Party")
        case "balloon.fill": String(localized: "Celebration")
        default: String(localized: "Symbol")
        }
    }
}
