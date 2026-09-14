const { test } = require("node:test");
const assert = require("node:assert/strict");
const mod = require("../api/version.js");

const { getVersionPayload, handler, parseVersionFromApkName, findApkAsset, selectRelease } = mod;

const baseEnv = {
  GITHUB_OWNER: "zay-yar-lin-htut",
  GITHUB_REPOSITORY: "youtube-mp3-downloader---player",
  FORCE_UPDATE: "false",
};

function makeRes() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    end(content) {
      this.body = content;
    },
  };
}

function githubResponse(status, payload) {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: async () => payload,
  };
}

function ghRelease(tag, assets, extra = {}) {
  return { tag_name: tag, assets, ...extra };
}

function asset(name, url) {
  return { name, browser_download_url: url };
}

const APK_URL = "https://github.com/owner/repo/releases/download/v1.4.0+8/app-release.apk";
const REAL_URL =
  "https://github.com/zay-yar-lin-htut/youtube-mp3-downloader---player/releases/download/yt-mp3/v2.1.1.apk";

test("valid release returns 200 with full payload", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)])]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(result.body, {
    version: "1.4.0",
    versionCode: 8,
    downloadUrl: APK_URL,
    forceUpdate: false,
  });
  assert.equal(typeof result.body.forceUpdate, "boolean");
});

test("forceUpdate is boolean true when FORCE_UPDATE=true", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [ghRelease("v1.0.0+1", [asset("app-release.apk", "u")])]);
  const result = await getVersionPayload({
    fetchImpl,
    env: { ...baseEnv, FORCE_UPDATE: "true" },
    slot: {},
  });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.forceUpdate, true);
});

test("detects the APK asset for the yt-mp3 release and returns the real browser_download_url", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [ghRelease("yt-mp3", [asset("v2.1.1.apk", REAL_URL), asset("README.txt", "u")])]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(result.body, {
    version: "2.1.1",
    versionCode: 211,
    downloadUrl: REAL_URL,
    forceUpdate: false,
  });
});

test("parses the app version from the APK filename, not the release tag", async () => {
  for (const [name, version, versionCode, url] of [
    ["v2.1.2.apk", "2.1.2", 212, "https://github.com/zay-yar-lin-htut/youtube-mp3-downloader---player/releases/download/yt-mp3/v2.1.2.apk"],
    ["v2.2.0.apk", "2.2.0", 220, "https://example.com/v2.2.0.apk"],
    ["v3.0.0.apk", "3.0.0", 300, "https://example.com/v3.0.0.apk"],
  ]) {
    const fetchImpl = async () => githubResponse(200, [ghRelease("yt-mp3", [asset(name, url)])]);
    const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
    assert.equal(result.statusCode, 200, `expected ${name} to succeed`);
    assert.equal(result.body.version, version);
    assert.equal(result.body.versionCode, versionCode);
    assert.equal(result.body.downloadUrl, url);
    assert.notEqual(result.body.version, "yt-mp3");
  }
});

test("ignores non-APK assets and picks the release that has an APK", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [
      ghRelease("yt-mp3", [asset("v2.1.1.apk", REAL_URL)]),
      ghRelease("v0.1.0", [asset("readme.txt", "u")]),
    ]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.version, "2.1.1");
  assert.equal(result.body.downloadUrl, REAL_URL);
});

test("handles a release with no APK safely", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [
      ghRelease("yt-mp3", [asset("readme.txt", "u")]),
      ghRelease("v0.1.0", [asset("notes.md", "u")]),
    ]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 500);
  assert.deepEqual(result.body, { error: "No APK found in latest release" });
});

test("handles malformed APK version filenames safely", async () => {
  for (const name of ["latest.apk", "v2.apk", "abc.apk", "v2.1.1.debug.apk", "app-release.apk"]) {
    const fetchImpl = async () =>
      githubResponse(200, [ghRelease("yt-mp3", [asset(name, "https://example.com/x.apk")])]);
    const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
    assert.equal(result.statusCode, 500, `expected ${name} to fail`);
    assert.deepEqual(result.body, { error: "Latest release version is invalid" });
  }
});

test("prefers a version-bearing APK over app-release.apk", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [
      ghRelease("yt-mp3", [
        asset("app-release.apk", "https://example.com/app-release.apk"),
        asset("v2.1.1.apk", REAL_URL),
      ]),
    ]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.version, "2.1.1");
  assert.equal(result.body.downloadUrl, REAL_URL);
});

test("falls back to prerelease-with-APK when no stable release has an APK", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [
      ghRelease("yt-mp3-beta", [asset("v2.2.0.apk", "https://example.com/v2.2.0.apk")], { prerelease: true }),
      ghRelease("v0.1.0", [asset("readme.txt", "u")]),
    ]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.version, "2.2.0");
  assert.equal(result.body.downloadUrl, "https://example.com/v2.2.0.apk");
});

test("returns 404 when the repo has no releases at all", async () => {
  const fetchImpl = async () => githubResponse(200, []);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 404);
  assert.deepEqual(result.body, { error: "No released version found" });
});

test("returns error when latest release version cannot be determined", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [ghRelease("yt-mp3", [asset("app-release.apk", "u")])]);
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 500);
  assert.deepEqual(result.body, { error: "Latest release version is invalid" });
});

test("maps GitHub 401/403/500 to 502 with safe message", async () => {
  for (const status of [401, 403, 500, 502]) {
    const fetchImpl = async () => githubResponse(status, {});
    const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
    assert.equal(result.statusCode, 502, `expected status ${status} to map to 502`);
    assert.deepEqual(result.body, { error: "Unable to retrieve latest release" });
  }
});

test("maps GitHub 404 to 404 with safe message", async () => {
  const fetchImpl = async () => githubResponse(404, { message: "Not Found" });
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 404);
  assert.deepEqual(result.body, { error: "No released version found" });
});

test("handles network/timeout failures as 502", async () => {
  const fetchImpl = async () => {
    throw new Error("aborted");
  };
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 502);
  assert.deepEqual(result.body, { error: "Unable to retrieve latest release" });
});

test("handles invalid JSON from GitHub as 502", async () => {
  const fetchImpl = async () => ({
    status: 200,
    ok: true,
    json: async () => {
      throw new SyntaxError("Unexpected token");
    },
  });
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 502);
  assert.deepEqual(result.body, { error: "Unable to retrieve latest release" });
});

test("returns 500 when repository configuration is missing", async () => {
  const fetchImpl = async () => {
    throw new Error("must not be called");
  };
  const result = await getVersionPayload({ fetchImpl, env: {}, slot: {} });
  assert.equal(result.statusCode, 500);
  assert.deepEqual(result.body, { error: "Server not configured" });
});

test("caches a successful response within the TTL", async () => {
  const slot = {};
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return githubResponse(200, [ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)])]);
  };
  const env = baseEnv;
  const first = await getVersionPayload({ fetchImpl, env, slot, now: () => 0 });
  const second = await getVersionPayload({ fetchImpl, env, slot, now: () => 30_000 });
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.equal(calls, 1);
});

test("refetches after the cache TTL expires", async () => {
  const slot = {};
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return githubResponse(200, [ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)])]);
  };
  const env = baseEnv;
  await getVersionPayload({ fetchImpl, env, slot, now: () => 0 });
  await getVersionPayload({ fetchImpl, env, slot, now: () => 120_000 });
  assert.equal(calls, 2);
});

test("handler allows GET, rejects other methods, and sets CORS", async () => {
  const fetchImpl = async () =>
    githubResponse(200, [ghRelease("v1.0.0+1", [asset("app-release.apk", "https://example.com/app-release.apk")])]);
  const opts = { fetchImpl, env: baseEnv, slot: {} };

  const getRes = makeRes();
  await handler({ method: "GET" }, getRes, opts);
  assert.equal(getRes.statusCode, 200);
  assert.equal(getRes.headers["Access-Control-Allow-Origin"], "*");
  assert.deepEqual(JSON.parse(getRes.body), {
    version: "1.0.0",
    versionCode: 1,
    downloadUrl: "https://example.com/app-release.apk",
    forceUpdate: false,
  });

  const postRes = makeRes();
  await handler({ method: "POST" }, postRes, opts);
  assert.equal(postRes.statusCode, 405);
  assert.deepEqual(JSON.parse(postRes.body), { error: "Method not allowed" });

  const putRes = makeRes();
  await handler({ method: "PUT" }, putRes, opts);
  assert.equal(putRes.statusCode, 405);

  const optionsRes = makeRes();
  await handler({ method: "OPTIONS" }, optionsRes, opts);
  assert.equal(optionsRes.statusCode, 200);
});

test("handler passes through 404 when no release exists", async () => {
  const opts = {
    fetchImpl: async () => githubResponse(404, {}),
    env: baseEnv,
    slot: {},
  };
  const res = makeRes();
  await handler({ method: "GET" }, res, opts);
  assert.equal(res.statusCode, 404);
  assert.deepEqual(JSON.parse(res.body), { error: "No released version found" });
});

test("parseVersionFromApkName parses v2.1.1.apk", () => {
  assert.deepEqual(parseVersionFromApkName("v2.1.1.apk"), { version: "2.1.1", versionCode: 211 });
  assert.deepEqual(parseVersionFromApkName("2.1.1.apk"), { version: "2.1.1", versionCode: 211 });
  assert.equal(parseVersionFromApkName("app-release.apk"), null);
  assert.equal(parseVersionFromApkName("latest.apk"), null);
  assert.equal(parseVersionFromApkName("v2.apk"), null);
  assert.equal(parseVersionFromApkName(null), null);
});

test("findApkAsset returns an .apk asset only", () => {
  const release = ghRelease("yt-mp3", [
    asset("README.txt", "u"),
    asset("v2.1.1.apk", REAL_URL),
    asset("notes.md", "u"),
  ]);
  const found = findApkAsset(release);
  assert.equal(found.name, "v2.1.1.apk");
  assert.equal(found.browser_download_url, REAL_URL);
});

test("selectRelease picks a released (non-draft) release with an APK", () => {
  const releases = [
    ghRelease("yt-mp3", [asset("v2.1.1.apk", REAL_URL)]),
    ghRelease("draft", [asset("v9.9.9.apk", "u")], { draft: true }),
  ];
  const selected = selectRelease(releases);
  assert.equal(selected.tag_name, "yt-mp3");
  assert.equal(selectRelease([]), null);
});