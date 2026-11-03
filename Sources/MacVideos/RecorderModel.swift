import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import MacVideosCore

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct DisplayOption: Identifiable {
    let id: CGDirectDisplayID
    let name: String
}

@MainActor final class RecorderModel: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, preparing, countdown(Int), starting, recording, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var microphones: [DeviceOption] = []
    @Published private(set) var cameras: [DeviceOption] = []
    @Published private(set) var displays: [DisplayOption] = []
    @Published var microphoneID: String { didSet { preferences.microphoneID = microphoneID } }
    @Published var cameraID: String { didSet { preferences.cameraID = cameraID } }
    @Published var displayID: UInt32 { didSet { preferences.displayID = displayID } }
    @Published var bubbleVisible: Bool { didSet { preferences.bubbleVisible = bubbleVisible; bubble.show(bubbleVisible && isBusy) } }
    @Published var bubbleSize: BubbleSize { didSet { preferences.bubbleSize = bubbleSize; bubble.place(size: bubbleSize, displayID: displayID) } }
    @Published private(set) var outputFolder: URL
    @Published private(set) var lastRecording: URL?
    @Published var errorMessage: String?
    @Published private(set) var shortcutAvailable = false
    @Published private(set) var startedAt: Date?
    private let preferences: Preferences
    let bubble = CameraBubble()
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var pendingURL: URL?
    private var startTask: Task<Void, Never>?
    private var shortcut: StopShortcut?
    private var observers: [NSObjectProtocol] = []
    private var completion: CheckedContinuation<Void, Never>?
    private var completionTimeout: Task<Void, Never>?
    private var recordingFailure: String?
    private var outputEnded = false
    private var runID = UUID()
    private var startupTimeout: Task<Void, Never>?

    var isBusy: Bool { phase != .idle }
    var canStop: Bool { switch phase { case .countdown, .recording: true; default: false } }
    var status: String {
        switch phase {
        case .idle: "Ready to record"
        case .preparing: "Checking permissions and sources…"
        case .countdown(let seconds): "Recording in \(seconds)…"
        case .starting: "Starting recording…"
        case .recording: "Recording — ⇧⌘S to stop"
        case .stopping: "Finishing your MP4…"
        }
    }

    override init() {
        let preferences = Preferences()
        self.preferences = preferences
        microphoneID = preferences.microphoneID; cameraID = preferences.cameraID
        displayID = preferences.displayID
        bubbleVisible = preferences.bubbleVisible; bubbleSize = preferences.bubbleSize
        outputFolder = preferences.outputFolder
        super.init()
        shortcut = StopShortcut { [weak self] in self?.stop() }
        shortcutAvailable = shortcut?.register() ?? false
        refreshDevices()
        refreshDisplays()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.devicesChanged() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isBusy { self.failAndStop("The display configuration changed. Recording was stopped; check the saved file before continuing.") }
                else { self.refreshDisplays() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: bubble.camera.session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.failAndStop("The camera stopped unexpectedly. Check that it is connected and not in use by another app.") }
        })
    }

    func refreshDevices() {
        // Audio discovery includes USB devices; video discovery includes external and Continuity cameras.
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
        microphones = DeviceOption.sortedUnique(audio.map { .init(id: $0.uniqueID, name: $0.localizedName) })
        cameras = DeviceOption.sortedUnique(video.map { .init(id: $0.uniqueID, name: $0.localizedName) })
        microphoneID = DeviceOption.selection(saved: microphoneID, devices: microphones, defaultID: AVCaptureDevice.default(for: .audio)?.uniqueID)
        cameraID = DeviceOption.selection(saved: cameraID, devices: cameras, defaultID: AVCaptureDevice.default(for: .video)?.uniqueID)
    }

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return DisplayOption(id: id, name: "\(screen.localizedName)\(id == CGMainDisplayID() ? " (main)" : "")")
        }
        if !displays.contains(where: { $0.id == displayID }) { displayID = displays.first(where: { $0.id == CGMainDisplayID() })?.id ?? displays.first?.id ?? 0 }
    }

    private func devicesChanged() {
        if isBusy {
            if AVCaptureDevice(uniqueID: microphoneID) == nil || (bubbleVisible && AVCaptureDevice(uniqueID: cameraID) == nil) {
                failAndStop("A selected microphone or camera was disconnected. Check the saved file, reconnect it, then refresh sources.")
            }
        } else { refreshDevices() }
    }

    func chooseFolder() {
        guard !isBusy else { return }
        let picker = NSOpenPanel()
        picker.title = "Choose where to save recordings"
        picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.canCreateDirectories = true; picker.allowsMultipleSelection = false
        picker.directoryURL = outputFolder
        if picker.runModal() == .OK, let url = picker.url { outputFolder = url; preferences.outputFolder = url }
    }

    func revealRecording() {
        if let lastRecording { NSWorkspace.shared.activateFileViewerSelecting([lastRecording]) }
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") { NSWorkspace.shared.open(url) }
    }

    private func requirePermission(_ type: AVMediaType, label: String) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: type)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: type) }
        guard allowed else { throw RecorderError.message("\(label) permission is off. Open System Settings → Privacy & Security → \(label), enable mac-videos, then quit and reopen the app.") }
    }

    func start() {
        guard !isBusy else { return }
        phase = .preparing; errorMessage = nil; recordingFailure = nil; outputEnded = false; runID = UUID()
        startTask = Task { await prepareAndStart() }
    }

    private func prepareAndStart() async {
        do {
            guard !microphoneID.isEmpty else { throw RecorderError.message("No microphone found. Connect your USB microphone and click Refresh sources.") }
            try await requirePermission(.audio, label: "Microphone")
            if bubbleVisible {
                guard !cameraID.isEmpty else { throw RecorderError.message("No camera found. Connect a camera or turn off the camera bubble.") }
                try await requirePermission(.video, label: "Camera")
                try await bubble.camera.start(deviceID: cameraID)
            }
            try Task.checkCancellation()
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw RecorderError.message("Screen Recording permission is off. Open System Settings → Privacy & Security → Screen & System Audio Recording, enable mac-videos, then quit and reopen the app.")
            }
            // Never recreate a missing external volume's path on the internal drive.
            if outputFolder.path.hasPrefix("/Volumes/") && !FileManager.default.fileExists(atPath: outputFolder.path) {
                throw RecorderError.message("The save folder is unavailable. Mount the external drive and choose its folder again.")
            }
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            // Reserve the name without overwriting an earlier recording; remove the empty reservation before SCK opens it.
            let url = outputFolder.appendingPathComponent(RecordingFiles.filename(date: Date()))
            try Data().write(to: url, options: .withoutOverwriting)
            try FileManager.default.removeItem(at: url)
            pendingURL = url
            bubble.place(size: bubbleSize, displayID: displayID)
            // Make the panel discoverable even in screen-only mode, so its window ID can be excepted.
            bubble.show(true)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            bubble.show(bubbleVisible)
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecorderError.message("The selected display is unavailable. Refresh sources and choose a display.")
            }
            guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }),
                  let cameraWindow = content.windows.first(where: { $0.windowID == CGWindowID(bubble.panel.windowNumber) }) else {
                throw RecorderError.message("Could not safely exclude the controls from capture. Try starting again.")
            }
            let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [cameraWindow])
            let configuration = SCStreamConfiguration()
            let size = RecordingFiles.videoSize(width: filter.contentRect.width * Double(filter.pointPixelScale), height: filter.contentRect.height * Double(filter.pointPixelScale))
            configuration.width = size.width; configuration.height = size.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = true
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = microphoneID
            configuration.capturesAudio = false // Walkthrough narration only, no system audio.
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = url
            recordingConfiguration.videoCodecType = .h264
            recordingConfiguration.outputFileType = .mp4
            let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addRecordingOutput(output)
            self.stream = stream; self.recordingOutput = output
            for seconds in (1...3).reversed() {
                phase = .countdown(seconds)
                try await Task.sleep(for: .seconds(1))
            }
            try Task.checkCancellation()
            phase = .starting
            try await stream.startCapture()
            try Task.checkCancellation()
            // didStartRecording is authoritative; never claim a file is recording before that callback.
            if phase == .starting {
                startupTimeout = Task {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, phase == .starting else { return }
                    recordingFailure = "The recording did not start. Check permissions and try again."
                    phase = .stopping
                    await finish()
                }
            }
        } catch {
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
            if let stream { try? await stream.stopCapture() }
            self.stream = nil; recordingOutput = nil; pendingURL = nil
            bubble.show(false); await bubble.camera.stop()
            phase = .idle; startedAt = nil
        }
        startTask = nil
    }

    func stop() {
        switch phase {
        case .countdown, .preparing:
            startTask?.cancel()
        case .recording:
            phase = .stopping
            Task { await finish() }
        default: break
        }
    }

    private func failAndStop(_ message: String) {
        errorMessage = message
        if phase == .starting {
            if let startTask { startTask.cancel() }
            else { phase = .stopping; Task { await finish() } }
        }
        else { stop() }
    }

    private func finish() async {
        let finishingRun = runID
        let finishingStream = stream
        do {
            // Install the waiter before stopping: the recording callback may arrive immediately.
            if outputEnded {
                try? await finishingStream?.stopCapture()
            } else {
                await withCheckedContinuation { continuation in
                    completion = continuation
                    completionTimeout = Task {
                        try? await Task.sleep(for: .seconds(20))
                        guard !Task.isCancelled, runID == finishingRun, completion != nil else { return }
                        recordingFailure = "Recording did not finish in time. A partial file may remain in the save folder."
                        resolveCompletion()
                    }
                    Task {
                        do { try await finishingStream?.stopCapture() }
                        catch {
                            guard runID == finishingRun else { return }
                            recordingFailure = error.localizedDescription
                            resolveCompletion()
                        }
                    }
                }
            }
            if let recordingFailure { throw RecorderError.message(recordingFailure) }
            if let pendingURL {
                let asset = AVURLAsset(url: pendingURL)
                let videos = try await asset.loadTracks(withMediaType: .video)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                let duration = try await asset.load(.duration)
                guard !videos.isEmpty, !audio.isEmpty, duration.seconds > 0 else {
                    throw RecorderError.message("The recording is missing video or microphone audio. A partial file may remain in the save folder; check permissions and sources.")
                }
                let formats = try await audio[0].load(.formatDescriptions)
                guard formats.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }) else {
                    throw RecorderError.message("The audio was not encoded as AAC. The file remains in the save folder for inspection.")
                }
                lastRecording = pendingURL
            }
        } catch { errorMessage = "Could not finish recording: \(error.localizedDescription)" }
        startupTimeout?.cancel(); startupTimeout = nil
        stream = nil; recordingOutput = nil; pendingURL = nil
        bubble.show(false); await bubble.camera.stop()
        phase = .idle; startedAt = nil
    }

    private func resolveCompletion() {
        completionTimeout?.cancel(); completionTimeout = nil
        completion?.resume(); completion = nil
    }
}

extension RecorderModel: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let identifier = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard self.recordingOutput.map(ObjectIdentifier.init) == identifier, phase == .starting else { return }
            startupTimeout?.cancel(); startupTimeout = nil
            phase = .recording; startedAt = Date()
        }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let identifier = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard self.recordingOutput.map(ObjectIdentifier.init) == identifier else { return }
            outputEnded = true
            if phase == .recording || phase == .starting { phase = .stopping; Task { await finishAfterUnexpectedEnd() } }
            else { resolveCompletion() }
        }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let identifier = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard self.recordingOutput.map(ObjectIdentifier.init) == identifier else { return }
            outputEnded = true
            recordingFailure = error.localizedDescription
            resolveCompletion()
            failAndStop("Recording failed: \(error.localizedDescription). Check the save folder's free space and connection.")
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let identifier = ObjectIdentifier(stream)
        Task { @MainActor in
            guard self.stream.map(ObjectIdentifier.init) == identifier else { return }
            outputEnded = true
            recordingFailure = error.localizedDescription
            resolveCompletion()
            failAndStop("Screen capture stopped: \(error.localizedDescription)")
        }
    }
    private func finishAfterUnexpectedEnd() async {
        // Output already finished; stopping the stream must not wait for a second finish callback.
        recordingFailure = "The recording ended unexpectedly. A partial file may remain in the save folder."
        try? await stream?.stopCapture()
        startupTimeout?.cancel(); startupTimeout = nil
        stream = nil; recordingOutput = nil; pendingURL = nil
        bubble.show(false); await bubble.camera.stop()
        phase = .idle; startedAt = nil; errorMessage = recordingFailure
    }
}
