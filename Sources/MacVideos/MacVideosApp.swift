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
        .defaultSize(width: 560, height: 720)
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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    settingRow("Display") {
                        Picker("Display", selection: $recorder.displayID) {
                            ForEach(recorder.displays) { Text($0.name).tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu).buttonSizing(.flexible)
                    }
                    settingRow("Microphone") {
                        Picker("Microphone", selection: $recorder.microphoneID) {
                            if recorder.microphones.isEmpty { Text("No microphones found").tag("") }
                            ForEach(recorder.microphones) { Text("\($0.name) · \($0.id.suffix(6))").tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu).buttonSizing(.flexible)
                    }
                    settingRow("Camera") {
                        Picker("Camera", selection: $recorder.cameraID) {
                            if recorder.cameras.isEmpty { Text("No cameras found").tag("") }
                            ForEach(recorder.cameras) { Text("\($0.name) · \($0.id.suffix(6))").tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu).buttonSizing(.flexible)
                    }
                    settingRow("") {
                        Button("Refresh sources") { recorder.refreshDevices(); recorder.refreshDisplays() }
                    }
                }.padding(12)
            }.disabled(recorder.isBusy)
            GroupBox("Camera bubble") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    settingRow("Visibility") {
                        Toggle("Show camera bubble", isOn: $recorder.bubbleVisible)
                            .disabled(recorder.isBusy && !recorder.bubble.camera.session.isRunning)
                    }
                    settingRow("Size") {
                        Picker("Size", selection: $recorder.bubbleSize) {
                            ForEach(BubbleSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).buttonSizing(.flexible)
                    }
                    settingRow("") {
                        Text("Drag the circle on the selected display. Turn it on before starting; hide or show it while recording.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(12)
            }
            GroupBox("Saving") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    settingRow("Folder") {
                        Text(recorder.outputFolder.path)
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    settingRow("") {
                        HStack(spacing: 12) {
                            Button("Choose folder…") { recorder.chooseFolder() }
                            Button("Show in Finder") { recorder.revealRecording() }
                                .disabled(recorder.lastRecording == nil)
                        }.disabled(recorder.isBusy)
                    }
                    if let last = recorder.lastRecording {
                        settingRow("Last recording") {
                            Label {
                                Text(last.lastPathComponent).textSelection(.enabled)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(12)
            }
            Divider()
            VStack(spacing: 10) {
                Text(recorder.status).font(.headline).accessibilityIdentifier("recordingStatus")
                if let start = recorder.startedAt {
                    Text(start, style: .timer).monospacedDigit().foregroundStyle(.red)
                } else {
                    Text("3-second countdown · H.264 MP4 · Microphone audio")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if recorder.isBusy {
                    Button(recorder.phase == .recording ? "Stop" : "Cancel") { recorder.stop() }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                        .disabled(!recorder.canStop)
                } else {
                    Button("Start recording") { recorder.start() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Text("Stop recording: ⇧⌘S").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
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
        }.padding(24).frame(width: 560)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .frame(width: 100, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
