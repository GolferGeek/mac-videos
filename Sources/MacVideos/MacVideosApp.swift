import SwiftUI
import AppKit
import MacVideosCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var recorder: RecorderModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder?.isBusy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the recording before quitting"
        alert.informativeText = "Use Stop or ⇧⌘S, then wait for the MP4 to finish saving."
        alert.addButton(withTitle: "Keep recording")
        alert.runModal()
        return .terminateCancel
    }
}

@main struct MacVideosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var recorder = RecorderModel()

    var body: some Scene {
        Window("mac-videos", id: "controls") {
            ControlsView(recorder: recorder)
                .onAppear { delegate.recorder = recorder }
        }
        .defaultSize(width: 440, height: 560)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Recording") {
                Button("Start recording") { recorder.start() }.disabled(recorder.isBusy)
                Button("Stop recording") { recorder.stop() }.disabled(!recorder.canStop)
            }
        }
        MenuBarExtra {
            RecorderMenu(recorder: recorder)
        } label: {
            Label(recorder.phase == .recording ? "Recording" : "mac-videos",
                  systemImage: recorder.phase == .recording ? "record.circle.fill" : "video.circle")
        }
    }
}

private struct RecorderMenu: View {
    @ObservedObject var recorder: RecorderModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(recorder.status)
        Button("Open controls") { openWindow(id: "controls"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Start recording") { recorder.start() }.disabled(recorder.isBusy)
        Button("Stop recording (⇧⌘S)") { recorder.stop() }.disabled(!recorder.canStop)
        Button("Show last recording in Finder") { recorder.revealRecording() }.disabled(recorder.lastRecording == nil || recorder.isBusy)
        Divider()
        Button("Quit mac-videos") { NSApp.terminate(nil) }
    }
}

private struct ControlsView: View {
    @ObservedObject var recorder: RecorderModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "video.circle.fill").font(.system(size: 42)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("mac-videos").font(.title2.bold())
                    Text("Your screen. Your walkthrough.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox("Sources") {
                VStack(spacing: 12) {
                    Picker("Display", selection: $recorder.displayID) {
                        ForEach(recorder.displays) { Text($0.name).tag($0.id) }
                    }
                    Picker("Microphone", selection: $recorder.microphoneID) {
                        if recorder.microphones.isEmpty { Text("No microphones found").tag("") }
                        ForEach(recorder.microphones) { Text("\($0.name) · \($0.id.suffix(6))").tag($0.id) }
                    }
                    Picker("Camera", selection: $recorder.cameraID) {
                        if recorder.cameras.isEmpty { Text("No cameras found").tag("") }
                        ForEach(recorder.cameras) { Text("\($0.name) · \($0.id.suffix(6))").tag($0.id) }
                    }
                    HStack { Spacer(); Button("Refresh sources") { recorder.refreshDevices(); recorder.refreshDisplays() } }
                }.padding(8)
            }.disabled(recorder.isBusy)
            GroupBox("Camera bubble") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show camera bubble", isOn: $recorder.bubbleVisible)
                        .disabled(recorder.isBusy && !recorder.bubble.camera.session.isRunning)
                    Picker("Size", selection: $recorder.bubbleSize) {
                        ForEach(BubbleSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Drag the circle anywhere on the selected display. Enable it before starting; you can hide and show it during recording.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Save recordings to").font(.headline)
                    Spacer()
                    Button("Change…") { recorder.chooseFolder() }.disabled(recorder.isBusy)
                }
                Text(recorder.outputFolder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recorder.status).font(.headline).accessibilityIdentifier("recordingStatus")
                    if let start = recorder.startedAt {
                        Text(start, style: .timer).monospacedDigit().foregroundStyle(.red)
                    } else { Text("3-second countdown · H.264 MP4 + microphone audio").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if recorder.isBusy {
                    Button(recorder.phase == .recording ? "Stop" : "Cancel") { recorder.stop() }
                        .disabled(!recorder.canStop).tint(.red)
                } else {
                    Button("Start recording") { recorder.start() }.buttonStyle(.borderedProminent)
                }
            }
            if !recorder.shortcutAvailable {
                Text("⇧⌘S is unavailable (another app may use it). Stop from the menu bar or controls.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = recorder.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Screen permission") { recorder.openPrivacy("ScreenCapture") }
                    Button("Camera") { recorder.openPrivacy("Camera") }
                    Button("Microphone") { recorder.openPrivacy("Microphone") }
                }.font(.caption).disabled(recorder.isBusy)
            }
            if let last = recorder.lastRecording {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(last.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") { recorder.revealRecording() }.disabled(recorder.isBusy)
                }
            }
        }.padding(24).frame(width: 480)
    }
}
