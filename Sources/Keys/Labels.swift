import Foundation

// The names and symbols the interface shows for the model's choices.

/// The icons to pick from, by theme, for projects and accesses alike. Each one exists on every
/// macOS the app runs on (a test checks), in thin, bold and filled forms.
struct IconCategory: Identifiable {
    let id: String
    let symbols: [String]

    var title: String {
        switch id {
        case "access": localized("Acesso e segurança")
        case "tech": localized("Tecnologia")
        case "business": localized("Negócios e comércio")
        case "people": localized("Pessoas e comunicação")
        case "tools": localized("Ferramentas e lugares")
        case "creative": localized("Criação e mídia")
        case "science": localized("Ciência e estudo")
        case "play": localized("Lazer e esporte")
        case "life": localized("Vida e natureza")
        default: id
        }
    }

    static let all: [IconCategory] = [
        IconCategory(id: "tech", symbols: [
            "shippingbox", "globe", "server.rack", "desktopcomputer", "laptopcomputer", "iphone", "ipad", "applewatch", "cpu",
            "memorychip", "cloud", "externaldrive", "cylinder.split.1x2", "network", "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "ladybug",
            "app.badge", "wifi", "antenna.radiowaves.left.and.right", "keyboard", "printer", "display", "tv", "point.3.connected.trianglepath.dotted", "square.stack.3d.up",
            "doc.text", "folder", "tray.full", "archivebox", "bolt", "cable.connector", "externaldrive.badge.icloud", "icloud", "arrow.triangle.branch",
        ]),
        IconCategory(id: "access", symbols: [
            "key", "key.horizontal", "lock", "lock.open", "lock.shield", "shield", "checkmark.shield", "exclamationmark.shield", "person.badge.key",
            "person.crop.circle", "touchid", "faceid", "eye", "eye.slash", "hand.raised", "lock.rectangle", "key.icloud", "lock.laptopcomputer",
        ]),
        IconCategory(id: "business", symbols: [
            "cart", "bag", "basket", "storefront", "creditcard", "banknote", "dollarsign.circle", "eurosign.circle", "brazilianrealsign.circle",
            "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "briefcase", "building.2", "building.columns", "building", "signature", "percent",
            "tag", "barcode", "qrcode", "truck.box", "box.truck", "doc.richtext", "list.clipboard", "scalemass", "giftcard",
        ]),
        IconCategory(id: "people", symbols: [
            "person", "person.2", "person.3", "megaphone", "newspaper", "bubble.left", "bubble.left.and.bubble.right", "text.bubble", "quote.bubble",
            "envelope", "paperplane", "at", "phone", "video", "bell", "calendar", "link", "person.crop.square",
        ]),
        IconCategory(id: "tools", symbols: [
            "gearshape", "gearshape.2", "wrench.and.screwdriver", "hammer", "screwdriver", "puzzlepiece", "target", "lightbulb", "slider.horizontal.3",
            "ruler", "pencil", "scissors", "paperclip", "magnifyingglass", "flag", "bookmark", "pin", "mappin",
            "map", "location", "house", "building.2.crop.circle", "signpost.right", "clock", "hourglass", "alarm", "stopwatch",
        ]),
        IconCategory(id: "creative", symbols: [
            "paintbrush", "paintpalette", "camera", "photo", "film", "play.rectangle", "music.note", "mic", "headphones",
            "scribble", "theatermasks", "guitars", "speaker.wave.2", "photo.on.rectangle", "square.and.pencil", "wand.and.stars", "sparkles", "pencil.and.outline",
        ]),
        IconCategory(id: "science", symbols: [
            "book", "books.vertical", "graduationcap", "brain", "flask", "atom", "cube", "testtube.2", "function",
            "sum", "binoculars", "backpack", "pencil.and.ruler", "globe.americas", "text.book.closed", "lightbulb.max", "compass.drawing", "magazine",
        ]),
        IconCategory(id: "play", symbols: [
            "gamecontroller", "ticket", "gift", "trophy", "star", "flame", "crown", "dice", "sportscourt",
            "soccerball", "basketball", "tennis.racket", "bicycle", "figure.run", "dumbbell", "balloon", "party.popper", "medal",
        ]),
        IconCategory(id: "life", symbols: [
            "leaf", "tree", "heart", "cross.case", "stethoscope", "pills", "fork.knife", "cup.and.saucer", "wineglass",
            "carrot", "birthday.cake", "airplane", "car", "bus", "tram", "sailboat", "pawprint", "sun.max",
            "moon", "cloud.sun", "drop", "snowflake", "mountain.2", "bed.double", "globe.europe.africa", "beach.umbrella", "tent",
        ]),
    ]

    /// Every icon, in the order of the categories.
    static let symbols: [String] = all.flatMap(\.symbols)

    /// The categories with only the icons whose name or category matches `query`, the empty ones left out.
    static func matching(_ query: String, in categories: [IconCategory] = all) -> [IconCategory] {
        let words = Search.words(query)
        guard !words.isEmpty else { return categories }
        return categories.compactMap { category in
            let title = category.title
            let symbols = category.symbols.filter { symbol in
                Search.contains(query, in: [symbol.replacingOccurrences(of: ".", with: " "), title])
            }
            return symbols.isEmpty ? nil : IconCategory(id: category.id, symbols: symbols)
        }
    }
}

extension Project {
    /// Every icon a project can take.
    static var symbols: [String] { IconCategory.symbols }

    /// The categories as the project picker shows them: technology first.
    static var symbolCategories: [IconCategory] { IconCategory.all }
}

extension Project.IconStyle {
    var label: String {
        switch self {
        case .line: localized("Linha")
        case .bold: localized("Bold")
        case .filled: localized("Preenchido")
        }
    }
}

extension Project.Tint {
    var label: String {
        switch self {
        case .lavender: localized("Lavanda")
        case .sky: localized("Céu")
        case .mint: localized("Menta")
        case .lime: localized("Lima")
        case .amber: localized("Âmbar")
        case .coral: localized("Coral")
        case .rose: localized("Rosa")
        case .slate: localized("Ardósia")
        }
    }
}

extension Credential {
    /// Every icon an access can take: the same as a project's.
    static var symbols: [String] { IconCategory.symbols }

    /// The categories as the access picker shows them: access and security first.
    static var symbolCategories: [IconCategory] {
        IconCategory.all.filter { $0.id == "access" } + IconCategory.all.filter { $0.id != "access" }
    }
}

extension Credential.Kind {
    var label: String {
        switch self {
        case .website: localized("Site ou painel")
        case .database: localized("Banco de dados")
        case .server: localized("Servidor")
        case .apiKey: localized("Chave de API")
        case .email: localized("E-mail")
        case .other: localized("Outro")
        }
    }

    var symbol: String {
        switch self {
        case .website: "globe"
        case .database: "cylinder.split.1x2"
        case .server: "server.rack"
        case .apiKey: "key"
        case .email: "envelope"
        case .other: "lock"
        }
    }
}
