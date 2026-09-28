import Foundation
import XCTest
@testable import qBitX

final class TorrentAddOptionsDraftTests: XCTestCase {
    func testLoadsAndEncodesAllTorrentAddOptionsWithoutDroppingUnknownFields() throws {
        let source = """
        {
          "category": "Linux",
          "tags": ["daily", "seed"],
          "use_auto_tmm": false,
          "save_path": "/downloads",
          "use_download_path": true,
          "download_path": "/incomplete",
          "seed_mode": true,
          "stopped": false,
          "stop_condition": "FilesChecked",
          "add_to_top_of_queue": true,
          "content_layout": "Subfolder",
          "ratio_limit": 2.5,
          "seeding_time_limit": -1,
          "inactive_seeding_time_limit": 45,
          "share_limits_mode": "MatchAll",
          "share_limit_action": "Stop",
          "future_qbittorrent_option": "preserve"
        }
        """
        var draft = TorrentAddOptionsDraft(json: source)

        XCTAssertEqual(draft.managementMode, .no)
        XCTAssertEqual(draft.savePath, "/downloads")
        XCTAssertEqual(draft.useDownloadPath, .yes)
        XCTAssertEqual(draft.downloadPath, "/incomplete")
        XCTAssertEqual(draft.category, "Linux")
        XCTAssertEqual(draft.tags, "daily, seed")
        XCTAssertTrue(draft.seedMode)
        XCTAssertEqual(draft.startTorrent, .yes)
        XCTAssertEqual(draft.stopCondition, "FilesChecked")
        XCTAssertEqual(draft.addToQueueTop, .yes)
        XCTAssertEqual(draft.contentLayout, "Subfolder")
        XCTAssertEqual(draft.ratioMode, .setValue)
        XCTAssertEqual(draft.ratioValue, "2.5")
        XCTAssertEqual(draft.seedingTimeMode, .unlimited)
        XCTAssertEqual(draft.inactiveTimeMode, .setValue)
        XCTAssertEqual(draft.inactiveTimeValue, "45")
        XCTAssertEqual(draft.shareLimitsMode, "MatchAll")
        XCTAssertEqual(draft.shareLimitAction, "Stop")

        draft.managementMode = .no
        draft.savePath = "/finished"
        draft.useDownloadPath = .yes
        draft.downloadPath = "/partial"
        draft.category = "Movies"
        draft.tags = "film, 4k"
        draft.seedMode = false
        draft.startTorrent = .no
        draft.stopCondition = "MetadataReceived"
        draft.addToQueueTop = .no
        draft.contentLayout = "NoSubfolder"
        draft.ratioMode = .unlimited
        draft.seedingTimeMode = .defaultValue
        draft.inactiveTimeMode = .setValue
        draft.inactiveTimeValue = "90"
        draft.shareLimitsMode = "MatchAny"
        draft.shareLimitAction = "RemoveWithContent"

        let encoded = try XCTUnwrap(draft.encodedJSON(preserving: source))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])

        XCTAssertEqual(object["category"] as? String, "Movies")
        XCTAssertEqual(object["tags"] as? [String], ["film", "4k"])
        XCTAssertEqual(object["use_auto_tmm"] as? Bool, false)
        XCTAssertEqual(object["save_path"] as? String, "/finished")
        XCTAssertEqual(object["use_download_path"] as? Bool, true)
        XCTAssertEqual(object["download_path"] as? String, "/partial")
        XCTAssertEqual(object["seed_mode"] as? Bool, false)
        XCTAssertEqual(object["stopped"] as? Bool, true)
        XCTAssertEqual(object["stop_condition"] as? String, "MetadataReceived")
        XCTAssertEqual(object["add_to_top_of_queue"] as? Bool, false)
        XCTAssertEqual(object["content_layout"] as? String, "NoSubfolder")
        XCTAssertEqual((object["ratio_limit"] as? NSNumber)?.doubleValue, -1)
        XCTAssertEqual((object["seeding_time_limit"] as? NSNumber)?.intValue, -2)
        XCTAssertEqual((object["inactive_seeding_time_limit"] as? NSNumber)?.intValue, 90)
        XCTAssertEqual(object["share_limits_mode"] as? String, "MatchAny")
        XCTAssertEqual(object["share_limit_action"] as? String, "RemoveWithContent")
        XCTAssertEqual(object["future_qbittorrent_option"] as? String, "preserve")
    }

    func testAutomaticManagementClearsManualPathsAndKeepsDefaultsUnspecified() throws {
        var draft = TorrentAddOptionsDraft(json: """
        {"use_auto_tmm":false,"save_path":"/old","use_download_path":true,"download_path":"/partial","stopped":true}
        """)
        draft.managementMode = .yes
        draft.useDownloadPath = .yes
        draft.startTorrent = .default

        let encoded = try XCTUnwrap(draft.encodedJSON(preserving: "{}"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])

        XCTAssertEqual(object["use_auto_tmm"] as? Bool, true)
        XCTAssertEqual(object["save_path"] as? String, "")
        XCTAssertNil(object["use_download_path"])
        XCTAssertEqual(object["download_path"] as? String, "")
        XCTAssertNil(object["stopped"])
    }

    func testInvalidShareLimitCannotBeSaved() {
        var draft = TorrentAddOptionsDraft(json: "{}")
        draft.ratioMode = .setValue
        draft.ratioValue = "not a number"

        XCTAssertFalse(draft.hasValidValues)
        XCTAssertNil(draft.encodedJSON(preserving: "{}"))
    }
}
