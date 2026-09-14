const { test } = require("node:test");
const assert = require("node:assert/strict");
const { parseVersionTag } = require("../api/version.js");

test("parses tag with leading v", () => {
  assert.deepEqual(parseVersionTag("v1.4.0+8"), { version: "1.4.0", versionCode: 8 });
});

test("parses tag without leading v", () => {
  assert.deepEqual(parseVersionTag("1.0.0+1"), { version: "1.0.0", versionCode: 1 });
});

test("parses additional valid tags", () => {
  assert.deepEqual(parseVersionTag("v1.2.3+5"), { version: "1.2.3", versionCode: 5 });
  assert.deepEqual(parseVersionTag("v2.10.1+27"), { version: "2.10.1", versionCode: 27 });
  assert.deepEqual(parseVersionTag("v2.0.0+17"), { version: "2.0.0", versionCode: 17 });
});

test("rejects tags without a valid versionCode", () => {
  for (const tag of ["latest", "v1.4.0", "v1.4.0-beta", "abc", "v1.4.0+"]) {
    assert.equal(parseVersionTag(tag), null, `expected ${tag} to be rejected`);
  }
});

test("rejects non-string input", () => {
  assert.equal(parseVersionTag(null), null);
  assert.equal(parseVersionTag(undefined), null);
  assert.equal(parseVersionTag(""), null);
});