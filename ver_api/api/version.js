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

function findApkAsset(release) {
  if (!release || !Array.isArray(release.assets)) return null;
  const usable = (asset) =>
    asset &&
    typeof asset.name === "string" &&
    typeof asset.browser_download_url === "string" &&
    asset.browser_download_url.length > 0;
  const exact = release.assets.find((a) => usable(a) && a.name === "app-release.apk");
  if (exact) return exact;
  return (
    release.assets.find(
      (a) => usable(a) && a.name.toLowerCase().endsWith(".apk"),
    ) || null
  );
}

async function fetchLatestRelease(owner, repository, token, fetchImpl) {
  const impl = fetchImpl || fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const headers = { Accept: GITHUB_ACCEPT, "User-Agent": USER_AGENT };
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await impl(
      `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/releases/latest`,
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

  let release;
  try {
    release = await fetchLatestRelease(owner, repository, env.GITHUB_TOKEN, fetchImpl);
  } catch (err) {
    if (err && err.statusCode === 404) {
      return { statusCode: 404, body: { error: "No released version found" } };
    }
    return { statusCode: 502, body: { error: "Unable to retrieve latest release" } };
  }

  const parsed = parseVersionTag(release.tag_name);
  if (!parsed) {
    return { statusCode: 500, body: { error: "Latest release tag is invalid" } };
  }

  const asset = findApkAsset(release);
  if (!asset) {
    return { statusCode: 500, body: { error: "No APK found in latest release" } };
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
module.exports.findApkAsset = findApkAsset;
module.exports.fetchLatestRelease = fetchLatestRelease;
module.exports.getVersionPayload = getVersionPayload;