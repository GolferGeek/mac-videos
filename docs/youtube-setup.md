# Set up YouTube once

When upgrading from a development build to the notarized release, open **Settings**, paste your **existing** desktop client ID and secret, then click **Save setup** once. You do not need another Google project. The release uses separate data protection Keychain storage and leaves all previous items untouched. On your next upload, use **Sign in with Google** again. New users can skip this entire guide unless they want YouTube uploads.

“Move to YouTube” uploads **a copy**. Your MP4 stays on your Mac. Nothing uploads until you click **Upload copy** after signing in and reviewing the details.

You need your Google account and a YouTube channel. If you have never made a channel, visit [YouTube](https://www.youtube.com/), sign in, click your picture, and choose **Create a channel** first.

## 1. Make a Google project

1. Open [Google Cloud Console](https://console.cloud.google.com/) in your browser. Sign in with the Google account you want to use.
2. At the top, click the project name or **Select a project**. Click **New project**.
3. Name it **mac-videos** and click **Create**. Select that project when it is ready.
4. You do not need to rent a server or set up billing for this personal test. If Google asks for payment, stop and ask for help.

## 2. Turn on the YouTube API

1. Use the search box at the top to find **YouTube Data API v3**.
2. Open its page and click **Enable**. If it says **Manage**, it is already enabled.

## 3. Tell Google this is your test app

1. Search for **Google Auth Platform**. Open it and click **Get started** if shown.
2. Under **Branding**, use **mac-videos** as the app name and your email for the support/contact email. Save.
3. Under **Audience**, choose **External**, keep the app in **Testing**, and add your own Google email under **Test users**. Save. Do not publish the app or request verification for this first test.
4. Under **Data Access**, choose **Add or remove scopes**. Add `https://www.googleapis.com/auth/youtube.upload`, `openid`, and `https://www.googleapis.com/auth/userinfo.email` if Google asks you to list scopes. The app requests upload access and your email so it can show which account is signed in. It does not request access to read your other videos.

Google sometimes changes these page labels. If a screen looks different, keep the project in Testing and ask for help rather than enabling extra permissions.

## 4. Make the desktop client

1. In Google Auth Platform, open **Clients**, then **Create client**.
2. For **Application type**, choose **Desktop app**. Name it **mac-videos on my Mac**. Click **Create**.
3. Google shows a **Client ID**. Copy it. You may also see a **Client secret**; keep that available too. Desktop apps cannot keep this value confidential, but Google may require it for token exchange.
4. Do not put these values in GitHub, a report, a chat message, or the project files. No API key is needed. Do not choose Web application or a service account.

## 5. Paste it into mac-videos

1. Open **mac-videos → Settings…** (Command–comma), or click **Move to YouTube** beside a saved recording to see **Set up YouTube**.
2. Paste the desktop **Client ID** into its box. Paste the **Client secret** into the second box if Google supplied one.
3. Click **Save setup**, then **Done**. The app keeps the configuration in this Mac’s Keychain, outside the repository. There is no bundled client ID. An empty configuration makes no Google requests.

## 6. Upload your first copy

1. Click **Move to YouTube** beside a saved recording, or **Choose saved MP4…** for an older one.
2. Click **Sign in with Google**. The normal system browser opens. Choose the right Google account and YouTube channel if asked, and grant the requested access. The browser returns to a temporary address on your own Mac. Return to mac-videos.
3. If Google warns that this is an unverified test app, check that it is your own mac-videos project and your account is a test user. If you are unsure, stop and ask for help.
4. Check the file, title, optional description, account and audience choice. Choose whether the video is made for kids. **Unlisted: anyone with the link can watch.** Unlisted is not private.
5. Click **Upload copy**. **Cancel** stops further transfer; it cannot take back bytes already received by YouTube. **Retry upload** checks and continues the same upload, including after restarting the app. One unfinished upload is retained at a time. Its original title and audience are kept.
6. On success, use **Copy link** or **Copy embed code**. The saved recording now has **Open on YouTube**. Wait for YouTube processing, open the link, and play the video with sound before sharing or embedding it. Some accounts, videos or sites may restrict playback or embedding.

## If something goes wrong

- **Sign-in expired:** click **Sign in again** in the upload sheet and choose the same Google account. This keeps the resumable upload. To change accounts, check YouTube Studio first, then use **Disconnect YouTube** in Settings. In Google’s Testing mode, this may happen after seven days.
- **Quota used up:** wait for the project’s YouTube quota to reset. Check Google Cloud’s quota page; upload limits can change. No automatic paid quota is purchased.
- **No channel:** create a channel on YouTube for the account you chose, then sign in again.
- **No network:** reconnect and click Retry. The app checks how much YouTube received before continuing; it does not create a new video for Retry.
- **Session expired or uncertain result:** check **YouTube Studio → Content** before starting another upload. Disconnect forgets the saved upload session, so a later new upload could make a duplicate. Cancel and Disconnect do not delete a video already on YouTube.
- **Disconnect could not reach Google:** the app removes its local sign-in; also remove mac-videos under [Google Account connections](https://myaccount.google.com/connections). If Keychain was locked, unlock it and disconnect again.

Matt still needs to verify the first real upload is unlisted, plays with sound and embeds as expected. Development uses mocked requests and does not create a Google project or upload a recording.

References checked 2026-11-04: [Google desktop sign-in](https://developers.google.com/identity/protocols/oauth2/native-app), [resumable uploads](https://developers.google.com/youtube/data/guides/using_resumable_upload_protocol), [videos.insert](https://developers.google.com/youtube/data/reference/rest/v3/videos/insert). See the current API page for quota and project restrictions; do not rely on older upload-cost figures.
