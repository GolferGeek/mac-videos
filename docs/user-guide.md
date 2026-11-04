# Getting started with mac-videos

1. On macOS 27 or later, download the ZIP from [GitHub Releases](https://github.com/GolferGeek/mac-videos/releases/latest), unzip it and drag **mac-videos.app** into **Applications**. Open it there. macOS may ask you to confirm opening an app downloaded from the internet. No Apple developer account or Xcode is required.
2. Choose your display, microphone and camera. Turn **Show camera bubble** off for screen-only recording. Recordings save in `~/Movies/mac-videos`; **Change…** selects another folder.
3. Click **Start recording**. Allow **Microphone** for your voice, **Camera** for the bubble, and **Screen & System Audio Recording** for your screen. System audio is not recorded. These are macOS permissions, not a Google sign-in. If denied, open **System Settings → Privacy & Security**, enable mac-videos in the matching pane, then quit and reopen the app. A first grant may require starting again after reopening.
4. Move the bubble during the countdown or recording. Stop with **Shift–Command–S**, the app's Stop button, or the menu bar. Wait until the file finishes saving, then reveal it in Finder and play it in QuickTime to check picture and sound. Your local MP4 stays on your Mac.

## Optional YouTube uploads

Recording needs no account or setup. To upload, follow [one-time YouTube setup](youtube-setup.md) using **your own Google Cloud project and Desktop OAuth client**. No shared client ID or secret is included. Save the client configuration in Settings, sign in with your Google account and confirm each **Move to YouTube** upload. Uploads are unlisted: anyone with the link can watch. The local MP4 is kept.

After upgrading from an earlier development build, paste your existing client configuration once and sign in again. Older Keychain items are untouched; the release stores new setup and refresh tokens in its provisioned data protection Keychain group. A new user can open the app and record without any Keychain or Google setup prompt. A locked/inaccessible Keychain produces an error when using YouTube rather than a password dialog.

If Screen Recording stops working after the signing update, quit the app, remove its old entry in the Screen & System Audio Recording privacy pane, add the copy in Applications and reopen. Do not bypass Gatekeeper warnings: download the official release again and report the warning if it persists.
