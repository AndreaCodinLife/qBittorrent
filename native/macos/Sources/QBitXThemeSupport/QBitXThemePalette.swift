import Foundation

public enum QBitXThemeImportError: Error, LocalizedError, Equatable {
    case fileTooLarge
    case invalidJSON
    case noSupportedColors

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The theme configuration is larger than 1 MB."
        case .invalidJSON:
            "The theme configuration must be a JSON object."
        case .noSupportedColors:
            "This theme configuration does not contain any supported qBitX color settings."
        }
    }
}

public struct QBitXThemeColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init?(qBittorrentValue: String) {
        let value = qBittorrentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") {
            guard let parsed = Self.parseHex(String(value.dropFirst())) else { return nil }
            red = parsed.red
            green = parsed.green
            blue = parsed.blue
            alpha = parsed.alpha
            return
        }

        if let hex = Self.namedColors[value], let named = Self.parseHex(hex) {
            red = named.red
            green = named.green
            blue = named.blue
            alpha = named.alpha
            return
        }

        guard let parsed = Self.parseRGBFunction(value) else { return nil }
        red = parsed.red
        green = parsed.green
        blue = parsed.blue
        alpha = parsed.alpha
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private static func parseHex(_ value: String) -> QBitXThemeColor? {
        let values = Array(value)
        func byte(_ start: Int, _ length: Int) -> Double? {
            guard let number = UInt32(String(values[start..<(start + length)]), radix: 16) else { return nil }
            let maximum = Double((1 << (length * 4)) - 1)
            return Double(number) / maximum
        }

        switch values.count {
        case 3:
            guard let r = byte(0, 1), let g = byte(1, 1), let b = byte(2, 1) else { return nil }
            return QBitXThemeColor(red: r, green: g, blue: b, alpha: 1)
        case 6:
            guard let r = byte(0, 2), let g = byte(2, 2), let b = byte(4, 2) else { return nil }
            return QBitXThemeColor(red: r, green: g, blue: b, alpha: 1)
        case 8:
            // Qt's 8-digit color syntax places alpha before the RGB channels.
            guard let a = byte(0, 2), let r = byte(2, 2), let g = byte(4, 2), let b = byte(6, 2) else { return nil }
            return QBitXThemeColor(red: r, green: g, blue: b, alpha: a)
        case 9:
            guard let r = byte(0, 3), let g = byte(3, 3), let b = byte(6, 3) else { return nil }
            return QBitXThemeColor(red: r, green: g, blue: b, alpha: 1)
        case 12:
            guard let r = byte(0, 4), let g = byte(4, 4), let b = byte(8, 4) else { return nil }
            return QBitXThemeColor(red: r, green: g, blue: b, alpha: 1)
        default:
            return nil
        }
    }

    private static func parseRGBFunction(_ value: String) -> QBitXThemeColor? {
        guard let open = value.firstIndex(of: "("), value.last == ")" else { return nil }
        let function = value[..<open]
        guard function == "rgb" || function == "rgba" else { return nil }
        let components = value[value.index(after: open)..<value.index(before: value.endIndex)]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count == (function == "rgb" ? 3 : 4),
              let red = channel(components[0]),
              let green = channel(components[1]),
              let blue = channel(components[2])
        else { return nil }

        let alpha: Double
        if components.count == 4 {
            guard let parsedAlpha = alphaChannel(components[3]) else { return nil }
            alpha = parsedAlpha
        } else {
            alpha = 1
        }
        return QBitXThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func channel(_ value: String) -> Double? {
        if value.hasSuffix("%"), let percentage = Double(value.dropLast()), (0...100).contains(percentage) {
            return percentage / 100
        }
        guard let number = Double(value), (0...255).contains(number) else { return nil }
        return number / 255
    }

    private static func alphaChannel(_ value: String) -> Double? {
        if value.hasSuffix("%"), let percentage = Double(value.dropLast()), (0...100).contains(percentage) {
            return percentage / 100
        }
        guard let number = Double(value), number >= 0 else { return nil }
        if number <= 1 { return number }
        guard number <= 255 else { return nil }
        return number / 255
    }

    private static let namedColors: [String: String] = {
        let namesAndHexValues = """
        aliceblue=f0f8ff antiquewhite=faebd7 aqua=00ffff aquamarine=7fffd4 azure=f0ffff beige=f5f5dc bisque=ffe4c4 black=000000 blanchedalmond=ffebcd blue=0000ff blueviolet=8a2be2 brown=a52a2a burlywood=deb887 cadetblue=5f9ea0 chartreuse=7fff00 chocolate=d2691e coral=ff7f50 cornflowerblue=6495ed cornsilk=fff8dc crimson=dc143c cyan=00ffff
        darkblue=00008b darkcyan=008b8b darkgoldenrod=b8860b darkgray=a9a9a9 darkgreen=006400 darkgrey=a9a9a9 darkkhaki=bdb76b darkmagenta=8b008b darkolivegreen=556b2f darkorange=ff8c00 darkorchid=9932cc darkred=8b0000 darksalmon=e9967a darkseagreen=8fbc8f darkslateblue=483d8b darkslategray=2f4f4f darkslategrey=2f4f4f darkturquoise=00ced1 darkviolet=9400d3 deeppink=ff1493 deepskyblue=00bfff dimgray=696969 dimgrey=696969 dodgerblue=1e90ff
        firebrick=b22222 floralwhite=fffaf0 forestgreen=228b22 fuchsia=ff00ff gainsboro=dcdcdc ghostwhite=f8f8ff gold=ffd700 goldenrod=daa520 gray=808080 grey=808080 green=008000 greenyellow=adff2f honeydew=f0fff0 hotpink=ff69b4 indianred=cd5c5c indigo=4b0082 ivory=fffff0 khaki=f0e68c lavender=e6e6fa lavenderblush=fff0f5 lawngreen=7cfc00 lemonchiffon=fffacd lightblue=add8e6 lightcoral=f08080 lightcyan=e0ffff lightgoldenrodyellow=fafad2
        lightgray=d3d3d3 lightgreen=90ee90 lightgrey=d3d3d3 lightpink=ffb6c1 lightsalmon=ffa07a lightseagreen=20b2aa lightskyblue=87cefa lightslategray=778899 lightslategrey=778899 lightsteelblue=b0c4de lightyellow=ffffe0 lime=00ff00 limegreen=32cd32 linen=faf0e6 magenta=ff00ff maroon=800000 mediumaquamarine=66cdaa mediumblue=0000cd mediumorchid=ba55d3 mediumpurple=9370db mediumseagreen=3cb371 mediumslateblue=7b68ee mediumspringgreen=00fa9a mediumturquoise=48d1cc mediumvioletred=c71585 midnightblue=191970
        mintcream=f5fffa mistyrose=ffe4e1 moccasin=ffe4b5 navajowhite=ffdead navy=000080 oldlace=fdf5e6 olive=808000 olivedrab=6b8e23 orange=ffa500 orangered=ff4500 orchid=da70d6 palegoldenrod=eee8aa palegreen=98fb98 paleturquoise=afeeee palevioletred=db7093 papayawhip=ffefd5 peachpuff=ffdab9 peru=cd853f pink=ffc0cb plum=dda0dd powderblue=b0e0e6 purple=800080 red=ff0000 rosybrown=bc8f8f royalblue=4169e1 saddlebrown=8b4513 salmon=fa8072 sandybrown=f4a460 seagreen=2e8b57 seashell=fff5ee
        sienna=a0522d silver=c0c0c0 skyblue=87ceeb slateblue=6a5acd slategray=708090 slategrey=708090 snow=fffafa springgreen=00ff7f steelblue=4682b4 tan=d2b48c teal=008080 thistle=d8bfd8 tomato=ff6347 turquoise=40e0d0 violet=ee82ee wheat=f5deb3 white=ffffff whitesmoke=f5f5f5 yellow=ffff00 yellowgreen=9acd32 transparent=00000000
        """
        return namesAndHexValues
            .split(whereSeparator: \.isWhitespace)
            .reduce(into: [:]) { result, entry in
                let pair = entry.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { return }
                result[String(pair[0])] = String(pair[1])
            }
    }()
}

public struct QBitXThemePalette: Codable, Equatable, Sendable {
    public static let supportedColorIDs: Set<String> = Set([
        "TransferList.Downloading",
        "TransferList.StalledDownloading",
        "TransferList.DownloadingMetadata",
        "TransferList.ForcedDownloadingMetadata",
        "TransferList.ForcedDownloading",
        "TransferList.Uploading",
        "TransferList.StalledUploading",
        "TransferList.ForcedUploading",
        "TransferList.QueuedDownloading",
        "TransferList.QueuedUploading",
        "TransferList.CheckingDownloading",
        "TransferList.CheckingUploading",
        "TransferList.CheckingResumeData",
        "TransferList.StoppedDownloading",
        "TransferList.StoppedUploading",
        "TransferList.Moving",
        "TransferList.MissingFiles",
        "TransferList.Error",
        "PiecesBar.Border",
        "PiecesBar.Piece",
        "PiecesBar.PartialPiece",
        "PiecesBar.MissingPiece",
        "ProgressBar"
    ])

    public private(set) var shared: [String: QBitXThemeColor]
    public private(set) var light: [String: QBitXThemeColor]
    public private(set) var dark: [String: QBitXThemeColor]

    public init() {
        shared = [:]
        light = [:]
        dark = [:]
    }

    public init(contentsOf url: URL) throws {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_048_576 {
            throw QBitXThemeImportError.fileTooLarge
        }
        try self.init(configData: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(configData: Data) throws {
        guard configData.count <= 1_048_576 else { throw QBitXThemeImportError.fileTooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw QBitXThemeImportError.invalidJSON
        }

        shared = Self.colors(in: root["colors"])
        light = Self.colors(in: root["colors.light"])
        dark = Self.colors(in: root["colors.dark"])
        guard !shared.isEmpty || !light.isEmpty || !dark.isEmpty else {
            throw QBitXThemeImportError.noSupportedColors
        }
    }

    public init?(storedJSON: String) {
        guard let data = storedJSON.data(using: .utf8),
              let palette = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = palette
    }

    public var colorCount: Int {
        Set(shared.keys).union(light.keys).union(dark.keys).count
    }

    public func color(for id: String, isDark: Bool) -> QBitXThemeColor? {
        (isDark ? dark[id] : light[id]) ?? shared[id]
    }

    public func storedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return value
    }

    private static func colors(in value: Any?) -> [String: QBitXThemeColor] {
        guard let object = value as? [String: Any] else { return [:] }
        return object.reduce(into: [:]) { result, entry in
            guard supportedColorIDs.contains(entry.key),
                  let value = entry.value as? String,
                  let color = QBitXThemeColor(qBittorrentValue: value)
            else { return }
            result[entry.key] = color
        }
    }
}
