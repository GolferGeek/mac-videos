import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacVideosCore

struct YouTubeRecordingsView: View {
    @ObservedObject var youtube: YouTubeModel
    var body: some View {
        GroupBox("Saved recordings") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(youtube.recent.prefix(3), id: \.path) { file in
                    HStack {
                        Text(file.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle).help(file.path)
                        Spacer()
                        Button(youtube.links[file.path] == nil ? "Move to YouTube" : "Open on YouTube") { youtube.open(file) }
                    }
                    if let video = youtube.links[file.path] {
                        HStack {
                            Button("Copy link") { youtube.copy(video.watchURL.absoluteString) }
                            Button("Copy embed code") { youtube.copy(video.embedCode) }
                        }.font(.caption)
                    }
                }
                HStack {
                    Button("Choose saved MP4…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { youtube.remember(url); youtube.open(url) }
                    }
                    Spacer()
                    Text("Uploads a copy; keeps your MP4.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10)
        }
        .sheet(item: $youtube.sheet) { sheet in
            switch sheet {
            case .setup: YouTubeSetupView(youtube: youtube)
            case .confirmation: YouTubeConfirmationView(youtube: youtube)
            }
        }
    }
}

struct YouTubeSetupView: View {
    @ObservedObject var youtube: YouTubeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up YouTube").font(.title2.bold())
            Text("Do this once with your own Google account. Your video stays on your Mac until you confirm an upload.")
            Text("1. Create a project in Google Cloud.\n2. Enable YouTube Data API v3.\n3. Set up Google Auth Platform: External, Testing. Add yourself as a test user.\n4. Create an OAuth client: Desktop app.\n5. Paste its client ID below. If Google supplies a client secret, paste that too.")
                .fixedSize(horizontal: false, vertical: true)
            Link("Open Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/")!)
            Link("Open the step-by-step setup guide", destination: URL(string: "https://github.com/GolferGeek/mac-videos/blob/main/docs/youtube-setup.md")!)
            Text("You also need a YouTube channel. No API key, server or paid billing setup is needed for this test.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Desktop client ID", text: $youtube.clientID).disabled(!youtube.account.isEmpty || youtube.pending != nil || youtube.working)
            SecureField("Desktop client secret (if supplied)", text: $youtube.clientSecret).disabled(!youtube.account.isEmpty || youtube.pending != nil || youtube.working)
            Text("Stored in this Mac’s Keychain. Testing sign-ins may expire after seven days. Disconnect before changing the client.")
                .font(.caption).foregroundStyle(.secondary)
            if !youtube.account.isEmpty { Text("Signed in: \(youtube.account)").textSelection(.enabled) }
            if let message = youtube.message { Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if !youtube.account.isEmpty || youtube.pending != nil {
                    Button("Disconnect YouTube") { youtube.disconnect() }.disabled(youtube.working)
                }
                Spacer()
                Button("Done") { dismiss() }.disabled(youtube.working)
                Button("Save setup") { youtube.saveConfiguration() }
                    .disabled(!youtube.configured || youtube.working || !youtube.account.isEmpty || youtube.pending != nil || youtube.preview)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 540)
    }
}

struct YouTubeConfirmationView: View {
    @ObservedObject var youtube: YouTubeModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var audience = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move to YouTube").font(.title2.bold())
            if youtube.preview { Text("Offline layout preview — no sign-in or upload").font(.caption).foregroundStyle(.orange) }
            Text(youtube.selected?.lastPathComponent ?? "Saved recording").font(.headline).textSelection(.enabled)
            Text("Your original MP4 stays where it is. This uploads a copy.").foregroundStyle(.secondary)
            TextField("Title", text: $title).disabled(youtube.working || youtube.pending != nil)
            TextField("Description (optional)", text: $description, axis: .vertical).lineLimit(3...5).disabled(youtube.working || youtube.pending != nil)
            Picker("Audience", selection: $audience) {
                Text("Choose an audience…").tag(0)
                Text("No, this is not made for kids").tag(1)
                Text("Yes, this is made for kids").tag(2)
            }
            .disabled(youtube.working || youtube.pending != nil)
            Text("Unlisted: anyone with the link can watch.").font(.headline)
            Text("Google account: \(youtube.account.isEmpty ? "Not signed in" : youtube.account)").textSelection(.enabled)
            Text("Uploads go to the YouTube channel selected during Google sign-in. Check the account before confirming.")
                .font(.caption).foregroundStyle(.secondary)
            if youtube.pending?.session.file == youtube.selected {
                Text("Retry uses the title and audience from the first attempt. Check YouTube Studio before forgetting a session or starting over.").font(.caption)
            }
            if youtube.working { ProgressView(value: youtube.progress); Text("\(Int(youtube.progress * 100))% sent").font(.caption) }
            if let message = youtube.message { Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if let video = youtube.video {
                Link(video.watchURL.absoluteString, destination: video.watchURL)
                HStack {
                    Button("Copy link") { youtube.copy(video.watchURL.absoluteString) }
                    Button("Copy embed code") { youtube.copy(video.embedCode) }
                }
            }
            HStack {
                if youtube.working { Button("Cancel") { youtube.cancel() } }
                else {
                    Button("Close") { dismiss() }
                    Spacer()
                    if youtube.account.isEmpty {
                        Button("Set up YouTube") { youtube.sheet = .setup }
                        Button("Sign in with Google") { youtube.signIn() }.disabled(!youtube.configured || youtube.preview)
                    } else if youtube.video == nil {
                        Button("Sign in again") { youtube.signIn() }
                        Button(youtube.pending == nil ? "Upload copy" : "Retry upload") {
                            youtube.upload(title: title, description: description, madeForKids: audience == 2)
                        }.buttonStyle(.borderedProminent).disabled(audience == 0 && youtube.pending == nil || title.isEmpty)
                    }
                }
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 540)
            .interactiveDismissDisabled(youtube.working)
            .onAppear { title = youtube.selected?.lastPathComponent ?? "" }
    }
}
