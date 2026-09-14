const { test } = require("node:test");
const assert = require("node:assert/strict");
const mod = require("../api/version.js");

const { getVersionPayload, handler } = mod;

const baseEnv = {
  GITHUB_OWNER: "owner",
  GITHUB_REPOSITORY: "repo",
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

function ghRelease(tag, assets) {
  return { tag_name: tag, assets };
}

function asset(name, url) {
  return { name, browser_download_url: url };
}

const APK_URL = "https://github.com/owner/repo/releases/download/v1.4.0+8/app-release.apk";

test("valid release returns 200 with full payload", async () => {
  const fetchImpl = async () =>
    githubResponse(200, ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)]));
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
    githubResponse(200, ghRelease("v1.0.0+1", [asset("app-release.apk", "u")]));
  const result = await getVersionPayload({
    fetchImpl,
    env: { ...baseEnv, FORCE_UPDATE: "true" },
    slot: {},
  });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.forceUpdate, true);
});

test("falls back to any .apk asset when app-release.apk is absent", async () => {
  const fetchImpl = async () =>
    githubResponse(200, ghRelease("v1.2.3+5", [asset("release.apk", "https://example.com/release.apk")]));
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.downloadUrl, "https://example.com/release.apk");
});

test("returns error when no APK asset exists", async () => {
  const fetchImpl = async () =>
    githubResponse(200, ghRelease("v1.0.0+1", [asset("readme.txt", "u")]));
  const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
  assert.equal(result.statusCode, 500);
  assert.deepEqual(result.body, { error: "No APK found in latest release" });
});

test("returns error when latest release tag is invalid", async () => {
  for (const tag of ["latest", "v1.4.0", "v1.4.0-beta", "abc", "v1.4.0+"]) {
    const fetchImpl = async () =>
      githubResponse(200, ghRelease(tag, [asset("app-release.apk", "u")]));
    const result = await getVersionPayload({ fetchImpl, env: baseEnv, slot: {} });
    assert.equal(result.statusCode, 500, `expected ${tag} to fail`);
    assert.deepEqual(result.body, { error: "Latest release tag is invalid" });
  }
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
    return githubResponse(200, ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)]));
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
    return githubResponse(200, ghRelease("v1.4.0+8", [asset("app-release.apk", APK_URL)]));
  };
  const env = baseEnv;
  await getVersionPayload({ fetchImpl, env, slot, now: () => 0 });
  await getVersionPayload({ fetchImpl, env, slot, now: () => 120_000 });
  assert.equal(calls, 2);
});

test("handler allows GET, rejects other methods, and sets CORS", async () => {
  const fetchImpl = async () =>
    githubResponse(200, ghRelease("v1.0.0+1", [asset("app-release.apk", "https://example.com/app-release.apk")]));
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