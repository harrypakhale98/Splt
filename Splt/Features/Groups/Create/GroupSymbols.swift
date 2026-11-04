/// The symbols offered in the picker.
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

    /// What VoiceOver says for a symbol, instead of its system name such as "fork knife".
    static func spokenName(for symbol: String) -> String {
        switch symbol {
        case "person.3.fill": String(localized: "People")
        case "house.fill": String(localized: "House")
        case "airplane": String(localized: "Airplane")
        case "car.fill": String(localized: "Car")
        case "fork.knife": String(localized: "Fork and knife")
        case "cart.fill": String(localized: "Shopping cart")
        case "cup.and.saucer.fill": String(localized: "Coffee cup")
        case "wineglass.fill": String(localized: "Wine glass")
        case "gift.fill": String(localized: "Gift")
        case "heart.fill": String(localized: "Heart")
        case "tent.fill": String(localized: "Tent")
        case "beach.umbrella.fill": String(localized: "Beach umbrella")
        case "ticket.fill": String(localized: "Ticket")
        case "film.fill": String(localized: "Film")
        case "music.note": String(localized: "Music")
        case "gamecontroller.fill": String(localized: "Game controller")
        case "figure.run": String(localized: "Runner")
        case "dumbbell.fill": String(localized: "Dumbbell")
        case "bicycle": String(localized: "Bicycle")
        case "tram.fill": String(localized: "Tram")
        case "bus.fill": String(localized: "Bus")
        case "fuelpump.fill": String(localized: "Fuel pump")
        case "bed.double.fill": String(localized: "Bed")
        case "building.2.fill": String(localized: "Buildings")
        case "briefcase.fill": String(localized: "Briefcase")
        case "graduationcap.fill": String(localized: "Graduation cap")
        case "book.fill": String(localized: "Book")
        case "pawprint.fill": String(localized: "Paw print")
        case "leaf.fill": String(localized: "Leaf")
        case "sun.max.fill": String(localized: "Sun")
        case "snowflake": String(localized: "Snowflake")
        case "mountain.2.fill": String(localized: "Mountains")
        case "sailboat.fill": String(localized: "Sailboat")
        case "figure.skiing.downhill": String(localized: "Skier")
        case "sportscourt.fill": String(localized: "Sports court")
        case "camera.fill": String(localized: "Camera")
        case "bag.fill": String(localized: "Bag")
        case "creditcard.fill": String(localized: "Credit card")
        case "party.popper.fill": String(localized: "Party popper")
        case "balloon.fill": String(localized: "Balloon")
        default: String(localized: "Symbol")
        }
    }
}
