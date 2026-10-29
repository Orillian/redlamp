import Foundation

/// A photo's alias in a report, and its file name.
public struct PhotoName: Codable, Sendable, Hashable {
    public var alias: String
    public var fileName: String
}

/// Takes out of a report's text what could say who someone is or where their files are: the
/// home folder, folders, Photos' identifiers, the albums kept in Apple Photos, and (unless they
/// ask to include them) file names, which become the photos' aliases. Reports are public, so
/// everything they hold goes through `redact`.
public struct FeedbackRedactor: Sendable {
    public var home: String
    /// Folders the app knows about (the open folder, the working set), longest first.
    public var folders: [String]
    public var photos: [PhotoName]
    /// The titles of the albums kept in Apple Photos, and of Photos' folders holding them (LIB-62).
    public var albums: [String]
    public var albumFolders: [String]
    /// Photos' identifiers of the photo the report is on (LIB-62), longest first.
    public var identifiers: [String]
    public var keepsFileNames: Bool

    public init(
        home: String = NSHomeDirectory(), folders: [String] = [], photos: [PhotoName] = [], albums: [String] = [],
        albumFolders: [String] = [], identifiers: [String] = [], keepsFileNames: Bool = false,
    ) {
        self.home = home
        self.folders = folders.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        self.photos = photos
        self.albums = albums
        self.albumFolders = albumFolders
        self.identifiers = identifiers.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        self.keepsFileNames = keepsFileNames
    }

    /// Absolute paths (and ones under `~`), up to the first space or quote: what's left of a path
    /// with spaces after the known folders and the home folder are taken out.
    private static var path: Regex<Substring> {
        /~?(?:\/[^\s"'“”‘’<>|()\[\],;:]+){2,}/
    }

    public func redact(_ text: String) -> String {
        var text = text
        for folder in folders {
            text = text.replacingOccurrences(of: folder + "/", with: "…/")
            text = text.replacingOccurrences(of: folder, with: "a folder")
        }
        // After the folders: a photo kept in Photos has its key in the names of its folders.
        for identifier in identifiers {
            text = text.replacingOccurrences(of: identifier, with: "…")
        }
        if home.count > 1 {
            text = text.replacingOccurrences(of: home, with: "~")
        }
        let original = text
        text = original.replacing(Self.path) { match in
            // Part of a URL ("https://…") or of words ("ProRAW/HEIC/TIFF"), not a path.
            if match.range.lowerBound > original.startIndex {
                let previous = original[original.index(before: match.range.lowerBound)]
                if previous == ":" || previous == "/" || previous.isLetter || previous.isNumber {
                    return String(match.output)
                }
            }
            let components = match.output.split(separator: "/")
            return "…/" + (components.last.map(String.init) ?? "")
        }
        for (title, name) in albumReplacements() {
            text = Self.replacingWhole(title, with: name, in: text)
        }
        if !keepsFileNames {
            for (name, alias) in fileNameReplacements() {
                text = text.replacingOccurrences(of: name, with: alias)
            }
        }
        return text
    }

    /// Each photo's file name, and its name without the extension, longest first.
    private func fileNameReplacements() -> [(String, String)] {
        photos.flatMap { photo -> [(String, String)] in
            let stem = (photo.fileName as NSString).deletingPathExtension
            return stem.count >= 3 && stem != photo.fileName
                ? [(photo.fileName, photo.alias), (stem, photo.alias)] : [(photo.fileName, photo.alias)]
        }
        .sorted { $0.0.count > $1.0.count }
    }

    /// Each album's title, which becomes "an album", and each of Photos' folders', "a folder", longest first: those
    /// of three characters or more, as file names' stems.
    private func albumReplacements() -> [(String, String)] {
        (albums.map { ($0, "an album") } + albumFolders.map { ($0, "a folder") })
            .filter { $0.0.count >= 3 }
            .sorted { $0.0.count > $1.0.count }
    }

    /// `text` with `word` replaced by `replacement` wherever it's whole, not part of a longer word or number.
    private static func replacingWhole(_ word: String, with replacement: String, in text: String) -> String {
        var result = ""
        var position = text.startIndex
        while let found = text.range(of: word, range: position ..< text.endIndex) {
            let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
            let after = found.upperBound < text.endIndex ? text[found.upperBound] : nil
            let whole = [before, after].allSatisfy { $0.map { !$0.isLetter && !$0.isNumber } ?? true }
            result += text[position ..< found.lowerBound]
            result += whole ? replacement : String(text[found])
            position = found.upperBound
        }
        return result + text[position...]
    }
}
