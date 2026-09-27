<div align="center">

# FreeVibe

### Local-first music search, download, and playback app

[English](#english) | [မြန်မာ](#myanmar)

</div>

<a id="english"></a>

## English

FreeVibe is a Flutter music app for searching YouTube, downloading tracks for
offline listening, organizing a local music library, and playing music with a
full-featured audio player.

The app is designed to be **offline-first**: Internet is required for search,
preview, and download, but downloaded and device-local music can be organized
and played without an Internet connection.

## Features

- Search YouTube and view search suggestions.
- Preview and download music when connected to the Internet.
- Browse downloaded tracks and music already stored on the device.
- Create and manage custom playlists.
- Rename songs in the local library.
- Play individual tracks or complete lists.
- Queue controls: next, previous, shuffle, and repeat.
- Resume tracks from their saved listening position.
- Mini player and full Now Playing screen.
- Artwork, progress display, and seek controls.
- Sleep timer with preset or custom durations.
- Android media notification, lock-screen, and media-button controls.
- Persistent playback settings such as shuffle and repeat.
- Clear network-required prompts when an online action is unavailable.
- Optional update checking through a Vercel/GitHub Releases API.

## Platforms

The Flutter project contains platform support for:

- Android
- iOS
- Windows
- macOS
- Linux

The update/download installer flow is primarily intended for Android.

## Technology

- Flutter and Dart
- `just_audio` and `audio_service` for playback and media controls
- `youtube_explode_dart` for YouTube search and stream resolution
- `sqflite` for local data and playback resume state
- `on_audio_query` for device music library access
- `path_provider` for local file storage
- `connectivity_plus` and `http` for network-aware features

## Getting started

### Requirements

- Flutter SDK compatible with the Dart SDK constraint in `pubspec.yaml`
- Android Studio/Android SDK for Android builds
- A configured Flutter desktop toolchain for Windows, macOS, or Linux builds

### Install dependencies

```bash
flutter pub get
```

### Run the app

```bash
flutter run
```

### Run tests

```bash
flutter test
```

### Build an Android APK

```bash
flutter build apk --release
```

The generated APK is normally located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Versioning

The app version is defined in `pubspec.yaml`:

```yaml
version: 2.1.1+3
```

- `2.1.1` is the user-facing version name.
- `3` is the platform build number/version code.

For Android updates, every new APK must use a build number greater than the
previous installed APK.

## Automatic GitHub Releases

The recommended release flow is to use GitHub Actions. A workflow can build an
APK whenever a version tag such as `v2.1.2` is pushed, rename it to
`v2.1.2.apk`, and upload it to a GitHub Release.

Typical release commands are:

```bash
git add .
git commit -m "Prepare release v2.1.2"
git push origin main
git tag v2.1.2
git push origin v2.1.2
```

Before publishing production updates, configure Android release signing with a
keystore and GitHub Secrets. Do not rely on a temporary debug signing key for
public releases, because a differently signed APK may not install as an update.

## Update API

The app can check a small Node.js API in `ver_api/`. The API reads the latest
published GitHub Release and returns the APK download URL, version, version
code, and force-update flag.

Configure the app URL in:

```text
lib/config/update_config.dart
```

Replace the placeholder URL with the deployed API URL:

```dart
const String updateApiUrl =
    'https://YOUR-PROJECT.vercel.app/api/version';
```

The API project has its own documentation in [`ver_api/README.md`](ver_api/README.md).

## Project structure

```text
lib/
├── models/       Data models and update parsing
├── player/       Queue, playback controller, and audio engine
├── screens/      Search, playlist, downloads, and now-playing screens
├── services/     YouTube, database, downloads, playlists, and updates
├── theme/        App colors, typography, spacing, and radius
└── widgets/      Reusable UI components

ver_api/
├── api/           Vercel serverless update endpoint
├── test/          Node.js API tests
└── dev-server.js  Local API development server
```

## Responsible use

Only download or use content that you are authorized to access. Respect
YouTube's Terms of Service, copyright laws, and the rights of content owners.

<a id="myanmar"></a>

## မြန်မာ

FreeVibe သည် YouTube မှ သီချင်းများကို ရှာဖွေခြင်း၊ download လုပ်ခြင်း၊
ဖုန်းထဲတွင် စုစည်းခြင်းနှင့် offline နားထောင်ခြင်းများ ပြုလုပ်နိုင်သော Flutter
music app ဖြစ်ပါတယ်။

App ကို **offline-first** ပုံစံဖြင့် တည်ဆောက်ထားပါတယ်။ Search၊ preview နှင့်
download အတွက် Internet လိုအပ်ပေမယ့် download လုပ်ပြီးသား သီချင်းများနှင့်
ဖုန်းထဲတွင်ရှိပြီးသား music များကို Internet မရှိဘဲ စီမံပြီး ဖွင့်နိုင်ပါတယ်။

## အဓိကလုပ်ဆောင်ချက်များ

- YouTube တွင် သီချင်းရှာဖွေခြင်းနှင့် search suggestion ပြသခြင်း
- Internet ရှိချိန်တွင် preview နှင့် download လုပ်ခြင်း
- Download လုပ်ထားသောသီချင်းများနှင့် device music များကို ကြည့်ရှုခြင်း
- ကိုယ်ပိုင် playlist များ ဖန်တီးစီမံခြင်း
- Local library ထဲရှိ သီချင်းအမည်များ ပြောင်းခြင်း
- Queue ထဲတွင် next၊ previous၊ shuffle နှင့် repeat အသုံးပြုခြင်း
- နားထောင်နေရာကို မှတ်ထားပြီး နောက်မှ ဆက်ဖွင့်ခြင်း
- Mini player နှင့် Now Playing screen အသုံးပြုခြင်း
- Artwork၊ progress နှင့် seek controls
- Preset/custom sleep timer
- Android notification၊ lock-screen နှင့် media-button controls
- Shuffle/repeat settings များကို သိမ်းထားခြင်း
- Internet မရှိချိန်တွင် ရှင်းလင်းသော network message ပြသခြင်း
- GitHub Releases/Vercel API မှတစ်ဆင့် update စစ်ဆေးခြင်း

## အသုံးပြုထားသောနည်းပညာများ

- Flutter နှင့် Dart
- `just_audio`၊ `audio_service` — audio playback နှင့် media controls
- `youtube_explode_dart` — YouTube search နှင့် stream resolution
- `sqflite` — local data နှင့် playback resume state
- `on_audio_query` — device music library ရယူခြင်း
- `path_provider` — local file storage
- `connectivity_plus`၊ `http` — network feature များ

## စတင်အသုံးပြုခြင်း

လိုအပ်ချက်များ:

- `pubspec.yaml` ထဲရှိ Dart SDK requirement နှင့် ကိုက်ညီသော Flutter SDK
- Android build အတွက် Android Studio/Android SDK

Dependencies ထည့်ရန်:

```bash
flutter pub get
```

App run ရန်:

```bash
flutter run
```

Test run ရန်:

```bash
flutter test
```

Android APK build ရန်:

```bash
flutter build apk --release
```

APK ဖိုင်သည် ပုံမှန်အားဖြင့် အောက်ပါနေရာတွင် ထွက်ပါမယ်:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Version နှင့် Update စနစ်

App version ကို `pubspec.yaml` ထဲတွင် သတ်မှတ်ထားပါတယ်။

```yaml
version: 2.1.1+3
```

- `2.1.1` သည် user မြင်ရသော version name ဖြစ်ပါတယ်။
- `3` သည် Android build number/version code ဖြစ်ပါတယ်။

GitHub Actions ဖြင့် `v2.1.2` ကဲ့သို့ tag တင်လိုက်ပါက APK build လုပ်ပြီး
GitHub Release ထဲသို့ အလိုအလျောက် upload လုပ်နိုင်ပါတယ်။ Production release
မလုပ်မီ Android release keystore နှင့် signing ကို သေချာ configure လုပ်ပါ။

Update API သည် `ver_api/` ထဲတွင်ရှိပြီး GitHub Release ထဲမှ နောက်ဆုံး APK ကို
ရှာကာ version၊ version code နှင့် download URL ပြန်ပေးပါတယ်။ App အတွင်း API URL
ကို အောက်ပါဖိုင်တွင် သတ်မှတ်ရပါမယ်:

```text
lib/config/update_config.dart
```

API အသေးစိတ်ကို [`ver_api/README.md`](ver_api/README.md) တွင် ဖတ်နိုင်ပါတယ်။

## တာဝန်ရှိစွာ အသုံးပြုရန်

မိမိအသုံးပြုခွင့်ရှိသော content များကိုသာ download သို့မဟုတ် အသုံးပြုပါ။
YouTube Terms of Service၊ copyright laws နှင့် content owner များ၏ အခွင့်အရေးကို
လေးစားပါ။
