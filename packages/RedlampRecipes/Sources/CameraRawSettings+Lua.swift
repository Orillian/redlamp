import Foundation

public extension CameraRawSettings {
    /// The develop settings a Lightroom Classic catalog keeps for a photo or a snapshot
    /// (`Adobe_imageDevelopSettings.text`): a Lua table assigned to `s` (`s = { Exposure2012 = 0.35, … }`),
    /// read as data, never run (`LuaTable`).
    init(lua text: String) throws(LuaTableError) {
        try self.init(lua: LuaTable(parsing: text))
    }

    /// The settings a Lua table holds, by its keys. A table with keys is a structure, its values without keys
    /// left out as XMP has no place for them; a table of tables is an array of structures, and a table of
    /// simple values a list, a point curve's flat list of numbers (`{ 0, 0, 255, 255 }`) paired as XMP
    /// writes its points (`"0, 0"`). A number is kept as its shortest text (`0.35`, `5500`) and a boolean as
    /// XMP writes one (`True`), so `number` and `flag` read them as they read XMP's text.
    init(lua table: LuaTable) {
        var values: [String: Value] = [:]
        values.reserveCapacity(table.fields.count)
        for (name, value) in table.fields {
            values[name] = Self.value(value, named: name)
        }
        self.init(values)
    }
}

extension CameraRawSettings {
    /// The point curves in ExifTool's table of `crs` tags, the profile's (`Look`'s `Parameters`) included.
    private static let curves: Set = [
        "ToneCurve", "ToneCurveRed", "ToneCurveGreen", "ToneCurveBlue", "ToneCurvePV2012", "ToneCurvePV2012Red",
        "ToneCurvePV2012Green", "ToneCurvePV2012Blue",
    ]

    private static func value(_ value: LuaValue, named name: String) -> Value {
        guard case let .table(table) = value else { return .text(text(of: value)) }
        let items = table.items
        if !table.fields.isEmpty {
            return .structure(CameraRawSettings(lua: table))
        }
        if items.contains(where: { $0.table != nil }) {
            return .structures(items.map { item in
                item.table.map { CameraRawSettings(lua: $0) } ?? CameraRawSettings()
            })
        }
        if curves.contains(name), items.count.isMultiple(of: 2), items.allSatisfy(\.isNumber) {
            return .list(stride(from: 0, to: items.count, by: 2).map {
                "\(text(of: items[$0])), \(text(of: items[$0 + 1]))"
            })
        }
        return .list(items.map { text(of: $0) })
    }

    /// A simple value's text: a whole number without a fraction, as Lightroom writes XMP's.
    private static func text(of value: LuaValue) -> String {
        switch value {
        case let .string(text): text
        case let .number(number):
            number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case let .bool(flag): flag ? "True" : "False"
        case .table: ""
        }
    }
}

private extension LuaValue {
    var isNumber: Bool {
        if case .number = self {
            return true
        }
        return false
    }
}
