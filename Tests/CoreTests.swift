import XCTest
@testable import MacVideosCore

final class CoreTests: XCTestCase {
    func testFilenameUsesLocalDateAndSafeCharacters() {
        XCTAssertEqual(RecordingFiles.filename(date: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!, suffix: "test"), "mac-videos_1970-01-01_00-00-00_test.mp4")
    }
    func testSameSecondDoesNotOverwrite() {
        let date = Date()
        XCTAssertNotEqual(RecordingFiles.filename(date: date), RecordingFiles.filename(date: date))
    }
    func testSettingsRoundTripAndDefaults() {
        let suite = "mac-videos-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.bubbleVisible)
        XCTAssertEqual(preferences.bubbleSize, .medium)
        XCTAssertTrue(preferences.outputFolder.path.hasSuffix("Movies/mac-videos"))
        preferences.cameraID = "camera"; preferences.microphoneID = "usb"
        preferences.displayID = 42; preferences.bubbleVisible = false
        preferences.bubbleSize = .large
        preferences.outputFolder = URL(fileURLWithPath: "/Volumes/Test/Videos", isDirectory: true)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.cameraID, "camera"); XCTAssertEqual(restored.microphoneID, "usb")
        XCTAssertEqual(restored.displayID, 42); XCTAssertFalse(restored.bubbleVisible)
        XCTAssertEqual(restored.bubbleSize, .large)
        XCTAssertEqual(restored.outputFolder.path, "/Volumes/Test/Videos")
    }
    func testStaleDeviceSelectionAndEmptyLists() {
        let devices = [DeviceOption(id: "built-in", name: "Built-in"), DeviceOption(id: "usb", name: "USB")]
        XCTAssertEqual(DeviceOption.selection(saved: "usb", devices: devices, defaultID: "built-in"), "usb")
        XCTAssertEqual(DeviceOption.selection(saved: "gone", devices: devices, defaultID: "usb"), "usb")
        XCTAssertEqual(DeviceOption.selection(saved: "gone", devices: devices, defaultID: "missing"), "built-in")
        XCTAssertEqual(DeviceOption.selection(saved: "usb", devices: [], defaultID: nil), "")
    }
    func testDeviceListKeepsDuplicateNamesButDeduplicatesIDs() {
        let result = DeviceOption.sortedUnique([.init(id: "b", name: "USB"), .init(id: "a", name: "USB"), .init(id: "b", name: "USB")])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)), ["a", "b"])
    }
    func testH264DimensionsPreserveDisplayAndAreEven() {
        let retina = RecordingFiles.videoSize(width: 6048, height: 3928)
        XCTAssertEqual(retina.width, 3840)
        XCTAssertEqual(retina.height % 2, 0)
        XCTAssertEqual(Double(retina.width) / Double(retina.height), 6048 / 3928, accuracy: 0.002)
        let portrait = RecordingFiles.videoSize(width: 2160, height: 3840)
        XCTAssertEqual(portrait.width, 2160); XCTAssertEqual(portrait.height, 3840)
    }
}
