import Foundation

/// The trademark notices in Help › Acknowledgements, for the names of other companies' apps, films
/// and cameras that Redlamp's menus, settings, looks and import name. The wording is counsel's to
/// settle (DEC-94), so all of it is here: the sentence each notice makes, and the two paragraphs
/// that follow them.
public struct TrademarkNotice: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case apps = "Apps and services"
        case film = "Films and papers"
        case cameras = "Cameras and their log formats"
    }

    public var kind: Kind
    /// The owner as the notice names it: "Adobe Inc.".
    public var owner: String
    /// The owner as the second sentence names it: "Adobe".
    public var shortOwner: String
    /// The names Redlamp shows, as it shows them.
    public var marks: [String]

    public var id: String {
        owner
    }

    /// "Lightroom and Photoshop are trademarks of Adobe Inc. Redlamp isn't affiliated with or
    /// endorsed by Adobe."
    public var text: String {
        let list = marks.count < 2
            ? marks.joined()
            : "\(marks.dropLast().joined(separator: ", ")) and \(marks.last ?? "")"
        let verb = marks.count < 2 ? "is a trademark" : "are trademarks"
        let end = owner.hasSuffix(".") ? "" : "."
        return "\(list) \(verb) of \(owner)\(end) Redlamp isn't affiliated with or endorsed by \(shortOwner)."
    }
}

public enum TrademarkNotices {
    public static let all: [TrademarkNotice] = [
        TrademarkNotice(
            kind: .apps, owner: "Adobe Inc.", shortOwner: "Adobe",
            marks: ["Adobe", "Lightroom", "Lightroom Classic", "Adobe Bridge", "Camera Raw", "Photoshop"],
        ),
        TrademarkNotice(kind: .apps, owner: "Camera Bits, Inc.", shortOwner: "Camera Bits", marks: ["Photo Mechanic"]),
        TrademarkNotice(kind: .apps, owner: "Capture One A/S", shortOwner: "Capture One", marks: ["Capture One"]),
        TrademarkNotice(kind: .apps, owner: "GitHub, Inc.", shortOwner: "GitHub", marks: ["GitHub"]),
        TrademarkNotice(
            kind: .apps, owner: "Apple Inc., registered in the U.S. and other countries and regions",
            shortOwner: "Apple", marks: ["Apple", "Apple Log", "iPhone", "iCloud", "ProRAW"],
        ),
        TrademarkNotice(
            kind: .film, owner: "Eastman Kodak Company", shortOwner: "Kodak",
            marks: [
                "Kodak", "Portra", "Ektar", "Gold", "UltraMax", "Tri-X", "T-Max", "Ektachrome", "Kodachrome", "Vision3",
            ],
        ),
        TrademarkNotice(
            kind: .film, owner: "FUJIFILM Corporation", shortOwner: "Fujifilm",
            marks: [
                "Fujifilm", "Superia", "Pro 400H", "Provia", "Velvia", "Astia", "Eterna", "Acros", "Classic Chrome",
                "Classic Neg.", "Nostalgic Neg.", "Pro Neg.", "Reala Ace", "F-Log", "F-Gamut",
            ],
        ),
        TrademarkNotice(
            kind: .film, owner: "HARMAN technology Limited", shortOwner: "Harman",
            marks: ["Ilford", "HP5 Plus", "FP4 Plus", "Delta", "Pan F Plus", "Multigrade"],
        ),
        TrademarkNotice(kind: .film, owner: "CineStill Film", shortOwner: "CineStill", marks: ["CineStill"]),
        TrademarkNotice(
            kind: .cameras, owner: "Sony Group Corporation", shortOwner: "Sony", marks: ["Sony", "S-Log3", "S-Gamut3"],
        ),
        TrademarkNotice(
            kind: .cameras, owner: "Arnold & Richter Cine Technik GmbH & Co. Betriebs KG", shortOwner: "ARRI",
            marks: ["ARRI", "LogC"],
        ),
        TrademarkNotice(
            kind: .cameras, owner: "Panasonic Holdings Corporation", shortOwner: "Panasonic",
            marks: ["Panasonic", "V-Log", "V-Gamut"],
        ),
    ]

    public static let filmLooks = """
    Redlamp's film looks are its own, modelled on the published datasheets of the films they're \
    named after, and its film icons are its own drawings, not the makers' packaging. Where Redlamp \
    names one of Fujifilm's film simulations, it's to say which look, or which of your own LUTs, \
    is meant.
    """

    public static let others = """
    Other names, such as those of camera makers and their cameras, are trademarks of their owners. \
    Redlamp names them only to identify the cameras, files and apps it works with.
    """

    /// The notice whose marks include `name`, ignoring case.
    public static func notice(naming name: String) -> TrademarkNotice? {
        all.first { $0.marks.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }
}
