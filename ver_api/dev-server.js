const http = require("http");
const handler = require("./api/version.js");

const PORT = process.env.PORT || 3000;
http
  .createServer((req, res) => handler(req, res))
  .listen(PORT, () => {
    console.log(`FreeVibe Update API listening on http://localhost:${PORT}/api/version`);
    if (!process.env.GITHUB_OWNER || !process.env.GITHUB_REPOSITORY) {
      console.warn("GITHUB_OWNER and GITHUB_REPOSITORY environment variables are not set.");
    }
  });