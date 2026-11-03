# A future “Upload unlisted” button

This is a plan, not a version 1 feature. Nothing signs in, uploads or creates Google resources today. Matt's local MP4 should remain intact throughout any future upload.

## What Matt would set up

1. Use Matt's Google account to create a Google Cloud project for mac-videos. Enable **YouTube Data API v3** in that project. The signed-in account needs a YouTube channel to receive the uploads.
2. Configure Google Auth Platform's app name, audience and consent screen. For an initial personal test, choose an external testing audience and add Matt as a test user. Ask only for `https://www.googleapis.com/auth/youtube.upload`. No service account or API key can replace Matt authorizing access to his channel.
3. Create an OAuth client of type **Desktop app**. Keep its downloaded configuration outside git. A desktop client ID identifies the application; a packaged desktop client cannot keep a client secret confidential. Use Google's installed-app flow with **PKCE**, a random state, the system browser and a temporary loopback listener bound to `127.0.0.1`. Verify the returned state and close the listener after one response. Do not ask for a Google password in the app. [Google's desktop authorization guide](https://developers.google.com/identity/protocols/oauth2/native-app)
4. Expect test sign-in to need repeating: for an external app left in Testing, YouTube-scoped refresh tokens expire after seven days. Before ongoing use, review publishing status and Google's consent/verification requirements. Production status alone does not mean Google has verified the app. Revoked or expired credentials must always lead to a friendly re-sign-in flow. [Google's token lifetime rules](https://developers.google.com/identity/protocols/oauth2#expiration)

There is no reason to create a paid server for a single-user desktop uploader. Check the project's current YouTube quota before implementation rather than hard-coding an old upload cost. Do not create resources, enable billing, submit verification or upload on Matt's behalf as part of this plan.

## Keep sign-in safe

After Matt signs in, store the refresh token as a generic-password item in **macOS Keychain**, scoped to this app and Google account, with access limited to the unlocked local session. Keep short-lived access tokens in memory and refresh them when necessary. Do not put tokens in UserDefaults, source code, logs, reports or committed configuration. Add a Disconnect button that revokes the grant when possible and deletes the local Keychain item, with a clear result if revocation fails. Keep the client configuration outside version control too; no actual keys or client identifiers belong in example files.

A future implementation needs its own security review of browser redirects, PKCE/state validation, Keychain access, token redaction and disconnect handling before merge.

## Smallest useful upload flow

1. After a successful save, show **Upload unlisted** beside the local file. Open a confirmation with the filename, title, destination channel/account and “Unlisted — anyone with the link can view.” Uploading is always an explicit action, never automatic after Stop.
2. Sign in if necessary; show which Google account/channel was authorized. Let Matt cancel before any file leaves the Mac. Ask for a title, defaulting to the filename; leave the description optional. Handle YouTube's required audience/made-for-kids choice explicitly.
3. Begin a resumable `videos.insert` upload with `part=snippet,status`, the local MP4 and an explicitly set `status.privacyStatus` of **unlisted**. Set `status.embeddable` to true. Never rely on YouTube's default privacy, which can be public. Stream the file from disk rather than loading the whole recording into memory. [Upload API](https://developers.google.com/youtube/data/reference/rest/v3/videos/insert), [video privacy and embedding fields](https://developers.google.com/youtube/data/reference/rest/v3/videos)
4. Show progress, cancellation, retry and understandable errors (sign-in expired, quota exhausted, disconnected network, channel not configured). Persist only the minimal resumable session state locally; treat the upload-session URL as sensitive and never log it. A retry should continue the same session, avoiding duplicate uploads. [Resumable upload protocol](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol)
5. On success, show the YouTube watch link and a copyable embed snippet from the returned video ID. Confirm the returned privacy/embedding status before saying it is ready; YouTube processing or account restrictions may delay playback. If status polling needs a broader read scope, explain and request that separately rather than expanding initial access silently. The local file stays available even if upload fails or is cancelled.

As checked on 2026-11-03, the current `videos.insert` reference says uploads from unverified API projects are no longer forced private. Older guides may still describe that restriction. Recheck current policy and test actual unlisted/embedding behavior with Matt's channel before shipping the button. OAuth consent verification and YouTube API policy compliance remain separate concerns. [Current upload reference](https://developers.google.com/youtube/data/reference/rest/v3/videos/insert)
