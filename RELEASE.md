# YT Local Music 2.1.1

Build: `3`

## Release Summary

This release provides a local-first music experience for finding, downloading,
organizing, and playing music from one Flutter app.

## Highlights

- Search for music and view search suggestions.
- Download tracks for offline listening.
- Browse downloaded music and music already stored on the device.
- Create and manage custom playlists.
- Rename songs stored in the local library.
- Play individual tracks or complete song lists.
- Use queue controls with next, previous, shuffle, and repeat playback.
- Continue tracks from their saved listening position.
- Use the mini player to keep playback available while navigating the app.
- Open the full Now Playing screen with artwork, progress, and seek controls.
- Set a sleep timer with preset or custom durations.
- Continue playback with Android media notification and lock-screen controls.
- Keep playback settings such as shuffle and repeat across app launches.
- Handle offline states with clear network-required prompts.

## Platforms

The app is structured as a Flutter application with platform support for:

- Android
- iOS
- Windows
- macOS
- Linux

## Build

```bash
flutter pub get
flutter test
flutter build apk --release
```

## Versioning

The app version is defined in `pubspec.yaml`:

```yaml
version: 2.1.1+3
```

- `2.1.1` is the user-facing release version.
- `3` is the build number used by platform packaging.