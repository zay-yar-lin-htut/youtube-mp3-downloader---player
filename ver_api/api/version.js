const REQUEST_TIMEOUT_MS = 10_000;
const CACHE_TTL_MS = 60_000;
const USER_AGENT = "FreeVibe-Update-API";
const GITHUB_ACCEPT = "application/vnd.github+json";

let sharedCache = { current: null };

function parseVersionTag(tag) {
  if (typeof tag !== "string") return null;
  const match = /^v?(\d+)\.(\d+)\.(\d+)\+(\d+)$/.exec(tag.trim());
  if (!match) return null;
  return {
    version: `${match[1]}.${match[2]}.${match[3]}`,
    versionCode: Number(match[4]),
  };
}

function parseVersionFromApkName(name) {
  if (typeof name !== "string") return null;
  const withoutExt = name.replace(/\.apk$/i, "").trim();
  const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(withoutExt);
  if (!match) return null;
  return {
    version: `${match[1]}.${match[2]}.${match[3]}`,
    versionCode: Number(`${match[1]}${match[2]}${match[3]}`),
  };
}

function resolveVersion(release, asset) {
  const fromName = asset ? parseVersionFromApkName(asset.name) : null;
  if (fromName) return fromName;
  return parseVersionTag(release && release.tag_name);
}

function findApkAsset(release) {
  if (!release || !Array.isArray(release.assets)) return null;
  const usable = (asset) =>
    asset &&
    typeof asset.name === "string" &&
    typeof asset.browser_download_url === "string" &&
    asset.browser_download_url.length > 0;
  const apks = release.assets.filter(
    (a) => usable(a) && a.name.toLowerCase().endsWith(".apk"),
  );
  if (apks.length === 0) return null;
  return (
    apks.find((a) => parseVersionFromApkName(a.name)) ||
    apks.find((a) => a.name === "app-release.apk") ||
    apks[0]
  );
}

function selectRelease(releases) {
  if (!Array.isArray(releases)) return null;
  const published = releases.filter((r) => r && r.draft !== true);
  const stable = published.find((r) => !r.prerelease && findApkAsset(r));
  if (stable) return stable;
  return published.find((r) => findApkAsset(r)) || null;
}

async function fetchReleases(owner, repository, token, fetchImpl) {
  const impl = fetchImpl || fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const headers = { Accept: GITHUB_ACCEPT, "User-Agent": USER_AGENT };
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await impl(
      `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/releases?per_page=100`,
      { headers, signal: controller.signal },
    );
    if (!response.ok) {
      const error = new Error(`GitHub API HTTP ${response.status}`);
      error.statusCode = response.status;
      throw error;
    }
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function getVersionPayload(opts = {}) {
  const env = opts.env || process.env;
  const fetchImpl = opts.fetchImpl;
  const now = opts.now || Date.now;
  const slot = opts.slot || sharedCache;

  const owner = env.GITHUB_OWNER;
  const repository = env.GITHUB_REPOSITORY;
  if (!owner || !repository) {
    return { statusCode: 500, body: { error: "Server not configured" } };
  }

  const cached = slot.current;
  if (cached && now() - cached.timestamp < CACHE_TTL_MS) {
    return { statusCode: 200, body: cached.data };
  }

  let releases;
  try {
    releases = await fetchReleases(owner, repository, env.GITHUB_TOKEN, fetchImpl);
  } catch (err) {
    if (err && err.statusCode === 404) {
      return { statusCode: 404, body: { error: "No released version found" } };
    }
    return { statusCode: 502, body: { error: "Unable to retrieve latest release" } };
  }

  const release = selectRelease(releases);
  if (!release) {
    if (!Array.isArray(releases) || releases.length === 0) {
      return { statusCode: 404, body: { error: "No released version found" } };
    }
    return { statusCode: 500, body: { error: "No APK found in latest release" } };
  }

  const asset = findApkAsset(release);
  const parsed = resolveVersion(release, asset);
  if (!parsed) {
    return { statusCode: 500, body: { error: "Latest release version is invalid" } };
  }

  const data = {
    version: parsed.version,
    versionCode: parsed.versionCode,
    downloadUrl: asset.browser_download_url,
    forceUpdate: env.FORCE_UPDATE === "true",
  };
  slot.current = { timestamp: now(), data };
  return { statusCode: 200, body: data };
}

function sendJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
}

async function handler(req, res, opts) {
  try {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.statusCode = 200;
      res.end();
      return;
    }

    if (req.method !== "GET") {
      sendJson(res, 405, { error: "Method not allowed" });
      return;
    }

    const result = await getVersionPayload(opts);
    if (result.statusCode === 200) {
      res.setHeader("Cache-Control", "public, max-age=60");
      res.setHeader("Content-Type", "application/json");
    }
    sendJson(res, result.statusCode, result.body);
  } catch (err) {
    sendJson(res, 500, { error: "Internal server error" });
  }
}

module.exports = handler;
module.exports.handler = handler;
module.exports.parseVersionTag = parseVersionTag;
module.exports.parseVersionFromApkName = parseVersionFromApkName;
module.exports.resolveVersion = resolveVersion;
module.exports.findApkAsset = findApkAsset;
module.exports.selectRelease = selectRelease;
module.exports.fetchReleases = fetchReleases;
module.exports.getVersionPayload = getVersionPayload;