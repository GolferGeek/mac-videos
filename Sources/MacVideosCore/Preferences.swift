import Foundation

public struct DeviceOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }

    /// Keep a saved choice only when it still exists. Prefer the OS default next.
    public static func selection(saved: String, devices: [DeviceOption], defaultID: String?) -> String {
        if devices.contains(where: { $0.id == saved }) { return saved }
        if let defaultID, devices.contains(where: { $0.id == defaultID }) { return defaultID }
        return devices.first?.id ?? ""
    }

    public static func sortedUnique(_ devices: [DeviceOption]) -> [DeviceOption] {
        var seen = Set<String>()
        return devices.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public enum BubbleSize: String, CaseIterable, Sendable {
    case small, medium, large
    public var diameter: Double {
        switch self { case .small: 140; case .medium: 220; case .large: 320 }
    }
}

public struct Preferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var microphoneID: String {
        get { defaults.string(forKey: "microphoneID") ?? "" }
        nonmutating set { defaults.set(newValue, forKey: "microphoneID") }
    }
    public var cameraID: String {
        get { defaults.string(forKey: "cameraID") ?? "" }
        nonmutating set { defaults.set(newValue, forKey: "cameraID") }
    }
    public var displayID: UInt32 {
        get { UInt32(clamping: defaults.integer(forKey: "displayID")) }
        nonmutating set { defaults.set(Int(newValue), forKey: "displayID") }
    }
    public var bubbleVisible: Bool {
        get { defaults.object(forKey: "bubbleVisible") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "bubbleVisible") }
    }
    public var bubbleSize: BubbleSize {
        get { BubbleSize(rawValue: defaults.string(forKey: "bubbleSize") ?? "") ?? .medium }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "bubbleSize") }
    }
    public var outputFolder: URL {
        get {
            if let path = defaults.string(forKey: "outputFolder") { return URL(fileURLWithPath: path, isDirectory: true) }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/mac-videos", isDirectory: true)
        }
        nonmutating set { defaults.set(newValue.path, forKey: "outputFolder") }
    }
}

public enum RecordingFiles {
    public static func filename(date: Date, timeZone: TimeZone = .current, suffix: String = UUID().uuidString) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "mac-videos_\(formatter.string(from: date))_\(suffix).mp4"
    }

    /// Limit H.264 to a supported resolution, preserving the entire display and even dimensions.
    public static func videoSize(width: Double, height: Double) -> (width: Int, height: Int) {
        let scale = min(1, 3840 / max(width, height))
        return (max(2, Int(width * scale) / 2 * 2), max(2, Int(height * scale) / 2 * 2))
    }
}
