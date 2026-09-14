# FreeVibe Update API

A tiny Node.js API for the FreeVibe Flutter app. It tells the app the latest
version, the Android version code, where to download the latest APK, and whether
the update is required.

**GitHub Releases is the source of truth.** The API reads the latest GitHub
Release automatically. You never edit version numbers in this project when you
ship a new APK.

Deployed on Vercel as a Serverless Function. No databases, no authentication
system, no extra frameworks, no hard-coded version values.

## How it works

```text
Flutter App
     ↓
Vercel /api/version
     ↓
GitHub Releases
     ↓
Latest APK
```

When you publish a GitHub Release that has an APK asset, every FreeVibe
installation that checks `/api/version` automatically sees the new version. No
change to this API project is needed.

## API endpoint

`GET /api/version`

Example response (real current release):

```json
{
  "version": "2.1.1",
  "versionCode": 211,
  "downloadUrl": "https://github.com/zay-yar-lin-htut/youtube-mp3-downloader---player/releases/download/yt-mp3/v2.1.1.apk",
  "forceUpdate": false
}
```

- `version` — the human-readable version (`2.1.1`).
- `versionCode` — the Android build/version code (`211`).
- `downloadUrl` — the real `browser_download_url` of the APK asset on GitHub
  Releases, taken from GitHub's API. It is never constructed manually.
- `forceUpdate` — `true` or `false` as a real boolean (from `FORCE_UPDATE`).

Non-GET methods (for example `POST /api/version`) return `405 Method not allowed`.

CORS is enabled so the Flutter Android app can call the API directly.

## GitHub Release requirements

For the API to work, the repository must have published releases that contain an
APK asset. The release tag does **not** have to be a version. For example, the
current release uses:

```text
Release tag:   yt-mp3
APK asset:     v2.1.1.apk
```

### How the version is detected

The API lists the published releases and picks the newest stable (non-draft)
release that has an APK asset. The app version is then parsed from the **APK
asset filename**, not from the release tag:

```text
v2.1.1.apk  →  version = 2.1.1
```

The Android `versionCode` is the three numbers concatenated:

```text
2.1.1  →  211
2.2.0  →  220
3.0.0  →  300
```

Future releases just upload new assets such as `v2.1.2.apk`, `v2.2.0.apk` or
`v3.0.0.apk`. The tag can stay `yt-mp3`.

If the release tag happens to use the `v1.4.0+8` convention (where `+8` is the
version code) and the APK filename has no version, the API falls back to parsing
the tag. If neither source has a valid version, the API returns an error instead
of guessing.

### APK asset selection

Inside the chosen release, the API inspects `assets[]`:

1. Prefers an asset named like a version, e.g. `v2.1.1.apk`.
2. Otherwise prefers the exact name `app-release.apk`.
3. Otherwise picks the first asset ending in `.apk`.

If there is no `.apk` asset at all, the API returns an error. It never
manufactures a fake download URL — it always uses GitHub's
`browser_download_url`.

### Releases vs drafts

The API lists `GET /repos/{owner}/{repo}/releases` (newest first), skips drafts,
prefers non-prerelease releases, and returns the newest published release that
has an APK. If the repository is private, set `GITHUB_TOKEN` so the API can see
the releases.

## Environment variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `GITHUB_OWNER` | Yes | GitHub username or organization that owns the repository. |
| `GITHUB_REPOSITORY` | Yes | Name of the repository. |
| `FORCE_UPDATE` | Yes | Set to `true` to force all users to update, `false` to let them skip. Defaults to `false` if unset. |
| `GITHUB_TOKEN` | No | Only needed when the repository is private. |

Current expected values (see `.env.example`):

```text
GITHUB_OWNER=zay-yar-lin-htut
GITHUB_REPOSITORY=youtube-mp3-downloader---player
FORCE_UPDATE=false
```

A template is provided in `.env.example` — copy it to `.env` for local use.

Never commit a real token. The token is never exposed to the Flutter app and
never appears in the API response.

## Run locally

Requires Node.js 18 or newer.

```bash
npm install
```

Set the environment variables (PowerShell example):

```powershell
$env:GITHUB_OWNER = "zay-yar-lin-htut"
$env:GITHUB_REPOSITORY = "youtube-mp3-downloader---player"
$env:FORCE_UPDATE = "false"
```

Start the local server (note: `dev`, not `start` — see the Vercel note below):

```bash
npm run dev
```

Then check the endpoint:

```bash
curl http://localhost:3000/api/version
```

You should see the same JSON response shape as production. Unsupported methods
are rejected:

```bash
curl -X POST http://localhost:3000/api/version
```

### Run the tests

```bash
npm test
```

The tests cover APK asset detection, version parsing from asset filenames,
release selection, invalid/missing versions, missing APK assets, GitHub API
failures, caching, CORS, and HTTP method handling.

## Deploy to Vercel

Exactly one file keeps the project in **Other** mode so it deploys as
Serverless Functions, not a Node server — `vercel.json`:

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "framework": null
}
```

1. Push this folder to a GitHub repository.
2. Go to https://vercel.com and click **Add New Project**.
3. Import the GitHub repository. If the folder lives inside a monorepo, set the
   **Root Directory** to this folder (`ver_api`).
4. Confirm the settings:
   - **Framework Preset:** Other (`framework: null` from `vercel.json`)
   - **Build Command:** empty
   - **Output Directory:** empty
5. Add the environment variables above:
   - `GITHUB_OWNER`
   - `GITHUB_REPOSITORY`
   - `FORCE_UPDATE`
   - `GITHUB_TOKEN` (only for a private repository)
6. Click **Deploy**. Vercel builds `api/version.js` as a Serverless Function.

> **Important:** this project must use Vercel Serverless Functions, not a Node
> server. Do **not** add a `start` script to `package.json`, and never put
> `server.js`, `index.js` or `app.js` at the project root — Vercel would treat
> them as a Node server entrypoint. This project runs locally with
> `npm run dev` (`dev-server.js`), which is for local development only. If your
> Vercel settings still show a build command of `npm run start`, clear it in
> **Project → Settings → General → Build Command**.

You get a URL like:

```
https://YOUR-PROJECT.vercel.app/api/version
```

Open it in a browser — you should see the JSON response.

## Releasing a new version

No changes are needed in this project. Just:

1. Bump the version in the Flutter app: `version: 2.1.1` in `pubspec.yaml`.
2. Build the APK: `flutter build apk --release`.
3. On GitHub, create a new release. The tag can stay the same (for example
   `yt-mp3`) — the tag is **not** used as the app version.
4. Upload the APK with the version in its filename, for example `v2.1.1.apk`.
5. Publish the release.

The API automatically finds the newest published release that has an `.apk`
asset, parses the version from the asset filename, and returns the real
`browser_download_url` on the next check.

## Error responses

The API always returns JSON, never an HTML error page:

| Situation | Status | Body |
| --------- | ------ | ---- |
| Successful response | 200 | version information |
| Wrong HTTP method | 405 | `{"error": "Method not allowed"}` |
| Repository not configured (missing env vars) | 500 | `{"error": "Server not configured"}` |
| No downloadable version (invalid asset/tag version) | 500 | `{"error": "Latest release version is invalid"}` |
| No APK in any release | 500 | `{"error": "No APK found in latest release"}` |
| No released version yet | 404 | `{"error": "No released version found"}` |
| GitHub unreachable, rate-limited, or API error | 502 | `{"error": "Unable to retrieve latest release"}` |

## Project structure

```text
freevibe-update-api/
├── api/
│   └── version.js       # the Vercel serverless function (exports a handler)
├── dev-server.js        # local-only test server (npm run dev)
├── test/
│   ├── api.test.js      # API behavior tests
│   └── version-parser.test.js  # version parsing tests
├── .env.example         # environment variable template
├── .gitignore
├── package.json
├── vercel.json          # forces the "Other" preset (Serverless Functions)
└── README.md
```