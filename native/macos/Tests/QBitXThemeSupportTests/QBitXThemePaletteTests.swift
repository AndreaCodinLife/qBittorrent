import Foundation
import XCTest
@testable import QBitXThemeSupport

final class QBitXThemePaletteTests: XCTestCase {
    func testImportsSharedAndLightAndDarkColorOverrides() throws {
        let config = """
        {
          "colors": {
            "TransferList.Downloading": "#12abef",
            "TransferList.Error": "#cc3300",
            "Unsupported.QtWidget": "#ffffff"
          },
          "colors.light": {
            "TransferList.Downloading": "rgb(0, 128, 255)"
          },
          "colors.dark": {
            "TransferList.Downloading": "#80402010",
            "PiecesBar.Piece": "white"
          }
        }
        """

        let palette = try QBitXThemePalette(configData: Data(config.utf8))

        XCTAssertEqual(palette.colorCount, 3)
        XCTAssertEqual(palette.color(for: "TransferList.Downloading", isDark: false), QBitXThemeColor(qBittorrentValue: "#0080ff"))
        XCTAssertEqual(palette.color(for: "TransferList.Downloading", isDark: true), QBitXThemeColor(qBittorrentValue: "#80402010"))
        XCTAssertEqual(palette.color(for: "TransferList.Error", isDark: true), QBitXThemeColor(qBittorrentValue: "#cc3300"))
        XCTAssertNil(palette.color(for: "Unsupported.QtWidget", isDark: false))
    }

    func testStoredPaletteRoundTrips() throws {
        let palette = try QBitXThemePalette(configData: Data(##"{"colors":{"ProgressBar":"#336699"}}"##.utf8))

        let restored = try XCTUnwrap(QBitXThemePalette(storedJSON: palette.storedJSON()))

        XCTAssertEqual(restored, palette)
    }

    func testRejectsMalformedAndUnrelatedThemeFiles() {
        XCTAssertThrowsError(try QBitXThemePalette(configData: Data("not json".utf8)))
        XCTAssertThrowsError(try QBitXThemePalette(configData: Data(##"{"colors":{"Unsupported.QtWidget":"#fff"}}"##.utf8)))
    }

    func testRejectsUnsupportedColorStringsButKeepsValidOverrides() throws {
        let palette = try QBitXThemePalette(configData: Data(#"{"colors":{"TransferList.Error":"not-a-color","TransferList.Downloading":"rgba(20, 40, 60, 0.5)"}}"#.utf8))

        XCTAssertEqual(palette.colorCount, 1)
        XCTAssertEqual(palette.color(for: "TransferList.Downloading", isDark: false), QBitXThemeColor(qBittorrentValue: "rgba(20, 40, 60, 0.5)"))
    }

    func testQtEightDigitHexUsesAlphaThenRGB() throws {
        let color = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "#80402010"))

        XCTAssertEqual(color.alpha, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.red, 64.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.green, 32.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 16.0 / 255, accuracy: 0.0001)
    }

    func testParsesCommonSVGColorNames() throws {
        let green = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "green"))
        let darkGray = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "darkgray"))
        let steelBlue = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "steelblue"))

        XCTAssertEqual(green.green, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(darkGray.red, 169.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(steelBlue.blue, 180.0 / 255, accuracy: 0.0001)
    }

    func testParsesQtExtendedPrecisionHexValues() throws {
        let color12Bit = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "#abc123def"))
        let color16Bit = try XCTUnwrap(QBitXThemeColor(qBittorrentValue: "#abcd1234ef01"))

        XCTAssertEqual(color12Bit.red, 0xabc / 4095.0, accuracy: 0.0001)
        XCTAssertEqual(color12Bit.green, 0x123 / 4095.0, accuracy: 0.0001)
        XCTAssertEqual(color12Bit.blue, 0xdef / 4095.0, accuracy: 0.0001)
        XCTAssertEqual(color16Bit.red, 0xabcd / 65535.0, accuracy: 0.0001)
        XCTAssertEqual(color16Bit.green, 0x1234 / 65535.0, accuracy: 0.0001)
        XCTAssertEqual(color16Bit.blue, 0xef01 / 65535.0, accuracy: 0.0001)
    }

    func testRejectsThemeConfigurationLargerThanQtLimit() throws {
        let config = Data(repeating: 0x20, count: 1_048_577)

        XCTAssertThrowsError(try QBitXThemePalette(configData: config)) { error in
            XCTAssertEqual(error as? QBitXThemeImportError, .fileTooLarge)
        }
    }
}
