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

When you publish a GitHub Release (with the right tag name and an APK asset),
every FreeVibe installation that checks `/api/version` automatically sees the
new version. No change to this API project is needed.

## API endpoint

`GET /api/version`

Example response:

```json
{
  "version": "1.4.0",
  "versionCode": 8,
  "downloadUrl": "https://github.com/OWNER/REPOSITORY/releases/download/v1.4.0+8/app-release.apk",
  "forceUpdate": false
}
```

- `version` — the human-readable version (from the release tag).
- `versionCode` — the Android build/version code (from the release tag).
- `downloadUrl` — direct link to the APK asset on GitHub Releases.
- `forceUpdate` — `true` or `false` as a real boolean (from `FORCE_UPDATE`).

Non-GET methods (for example `POST /api/version`) return `405 Method not allowed`.

CORS is enabled so the Flutter Android app can call the API directly.

## GitHub Release requirements

For the API to work, the latest GitHub Release must have:

1. A tag in the format `vMAJOR.MINOR.PATCH+VERSION_CODE`, for example `v1.4.0+8`.
2. An APK asset uploaded to that release.

### Tag format

The tag is the Flutter app version with the version code:

```text
v1.4.0+8
```

is parsed into:

```text
version     = 1.4.0
versionCode = 8
```

A leading `v` is optional but recommended:

```text
v1.0.0+1
v1.2.3+5
v2.0.0+17
```

If the latest release tag does not contain a valid version code, the API returns
an error instead of guessing.

### APK asset

The API looks for `app-release.apk` first. If that exact name is missing, it
falls back to the first asset whose name ends with `.apk`. If there is no APK
asset at all, the API returns an error. It never manufactures a fake download
URL.

### Releases vs drafts

The API uses GitHub's official "latest release" behavior. It only returns
published, non-draft stable releases.

## Environment variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `GITHUB_OWNER` | Yes | GitHub username or organization that owns the repository. |
| `GITHUB_REPOSITORY` | Yes | Name of the repository, for example `FreeVibe`. |
| `FORCE_UPDATE` | Yes | Set to `true` to force all users to update, `false` to let them skip. Defaults to `false` if unset. |
| `GITHUB_TOKEN` | No | Only needed when the repository is private. |

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
$env:GITHUB_OWNER = "YOUR_GITHUB_USERNAME"
$env:GITHUB_REPOSITORY = "FreeVibe"
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

The tests cover version tag parsing, valid releases, invalid tags, missing APK
assets, GitHub API failures, caching, CORS, and HTTP method handling.

## Deploy to Vercel

1. Push this folder to a GitHub repository.
2. Go to https://vercel.com and click **Add New Project**.
3. Import the GitHub repository. If the folder lives inside a monorepo, set the
   **Root Directory** to this folder (`ver_api`).
4. Leave the **Build Command** empty and the **Framework Preset** set to **Other**.
5. Add the environment variables above:
   - `GITHUB_OWNER`
   - `GITHUB_REPOSITORY`
   - `FORCE_UPDATE`
   - `GITHUB_TOKEN` (only for a private repository)
6. Click **Deploy**. Vercel builds `api/version.js` as a Serverless Function.

> **Important:** this project must use Vercel Serverless Functions, not a Node
> server. Do **not** add a `start` script to `package.json`. Vercel treats a
> project that has a `start` script as a long-running Node server and will run
> `npm start` during the build, which hangs the deployment. This project uses
> `npm run dev` only for local testing. If your Vercel settings still show a
> build command of `npm run start`, clear it in **Project → Settings → General →
> Build Command**.

You get a URL like:

```
https://YOUR-PROJECT.vercel.app/api/version
```

Open it in a browser — you should see the JSON response.

## Releasing a new version

No changes are needed in this project. Just:

1. Bump the version in the Flutter app: `version: 1.4.0+8` in `pubspec.yaml`.
2. Build the APK: `flutter build apk --release`.
3. On GitHub, create a new release with tag `v1.4.0+8`.
4. Upload `app-release.apk` to the release.
5. Publish the release.

The API automatically discovers the new tag and APK on the next check.

## Error responses

The API always returns JSON, never an HTML error page:

| Situation | Status | Body |
| --------- | ------ | ---- |
| Successful response | 200 | version information |
| Wrong HTTP method | 405 | `{"error": "Method not allowed"}` |
| Repository not configured (missing env vars) | 500 | `{"error": "Server not configured"}` |
| Invalid release tag | 500 | `{"error": "Latest release tag is invalid"}` |
| No APK in the release | 500 | `{"error": "No APK found in latest release"}` |
| No released version yet | 404 | `{"error": "No released version found"}` |
| GitHub unreachable or API error | 502 | `{"error": "Unable to retrieve latest release"}` |

## Project structure

```text
freevibe-update-api/
├── api/
│   └── version.js       # the Vercel serverless function
├── test/
│   ├── api.test.js      # API behavior tests
│   └── version-parser.test.js  # tag parsing tests
├── .env.example         # environment variable template
├── .gitignore
├── package.json
└── README.md
```