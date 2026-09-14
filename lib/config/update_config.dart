/// Central configuration for the app-update feature.
///
/// The FreeVibe app talks ONLY to the Vercel Update API. It never talks to
/// GitHub Releases directly, so the GitHub repository can move without
/// rebuilding the app. Point this at the deployed Vercel project:
///
///   GET `updateApiUrl` -> { "version", "versionCode", "downloadUrl",
///                           "forceUpdate" }
///
/// TODO: replace with the real deployed Vercel Update API URL before release.
const String updateApiUrl = 'https://your-vercel-project.vercel.app/api/version';