import AppKit
import AVFoundation
import MacVideosCore

/// AVFoundation session mutations run on one queue, away from the UI thread.
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "mac-videos.camera")

    func start(deviceID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                        throw RecorderError.message("The camera was disconnected. Refresh sources and choose a camera.")
                    }
                    self.session.beginConfiguration()
                    self.session.inputs.forEach { self.session.removeInput($0) }
                    self.session.sessionPreset = .high
                    let input: AVCaptureDeviceInput
                    do { input = try AVCaptureDeviceInput(device: device) }
                    catch { self.session.commitConfiguration(); throw error }
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        throw RecorderError.message("The selected camera is unavailable. Close other camera apps and try again.")
                    }
                    self.session.addInput(input)
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    guard self.session.isRunning else { throw RecorderError.message("The camera could not start. Close other camera apps and try again.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.stopRunning()
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.commitConfiguration()
                continuation.resume()
            }
        }
    }
}

private final class BubblePreview: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        toolTip = "Drag the camera bubble anywhere on the selected display"
        setAccessibilityLabel("Draggable camera bubble")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { true }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.frame = bounds
        layer?.cornerRadius = bounds.width / 2
        CATransaction.commit()
    }
}

@MainActor final class CameraBubble {
    let camera = CameraSession()
    let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 80, y: 80, width: 220, height: 220),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "mac-videos camera bubble"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = BubblePreview(session: camera.session)
    }

    func place(size: BubbleSize, displayID: CGDirectDisplayID) {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID } ?? NSScreen.main
        guard let screen else { return }
        let diameter = size.diameter
        let area = screen.visibleFrame
        let old = panel.frame.origin
        let origin = area.contains(panel.frame) ? old : NSPoint(x: area.maxX - diameter - 32, y: area.minY + 32)
        panel.setFrame(NSRect(x: min(max(origin.x, area.minX), area.maxX - diameter),
                             y: min(max(origin.y, area.minY), area.maxY - diameter),
                             width: diameter, height: diameter), display: true)
    }

    func show(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}
