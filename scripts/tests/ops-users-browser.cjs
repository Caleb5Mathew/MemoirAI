"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");

(async () => {
  const root = path.resolve(__dirname, "../../public/ops");
  const server = http.createServer((req, res) => {
    const file = req.url.split("?")[0].endsWith("app.js") ? "app.js" : "index.html";
    res.setHeader("Content-Type", file.endsWith("js") ? "text/javascript" : "text/html");
    res.end(fs.readFileSync(path.join(root, file)));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  server.unref();
  const browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL || "chrome" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const calls = [];
  const errors = [];
  const state = { failMemories: false, delayUser: null, failUsers: false };
  const users = [
    { userId: "new-user", displayName: "Newest parent", email: "new@example.test", createdAt: "2026-09-24T12:00:00Z", lastActiveAt: "2026-09-24T13:00:00Z" },
    { userId: "older-user", displayName: "Older parent", email: "older@example.test", createdAt: "2026-09-20T12:00:00Z" }
  ];
  page.on("pageerror", err => errors.push(err.message));
  await page.exposeFunction("fixtureCall", async (name, data) => {
    calls.push({ name, data });
    if (name === "adminListPrintOrders") return { data: { all: [], stats: {}, userCount: 2 } };
    if (name === "adminListUsers" && state.failUsers) throw new Error("Temporary users failure");
    if (name === "adminListUsers") return { data: { users: data.cursor ? [{ ...users[1], userId: "third-user", displayName: "Another parent" }] : data.sort === "oldest" ? [...users].reverse() : users, nextCursor: data.cursor ? null : "users-page-two" } };
    if (data.userId === state.delayUser) await new Promise(resolve => setTimeout(resolve, 500));
    if (name === "adminListUserBooks") return { data: { books: data.userId === "empty-user" ? [] : [
      { bookVersionId: data.cursor ? "past-book" : "new-book", printTitle: data.userId + (data.cursor ? " past book" : " latest book"), createdAt: data.cursor ? "2026-09-01T12:00:00Z" : "2026-09-24T12:00:00Z", pdfURL: "https://example.test/book.pdf" },
      ...data.cursor ? [] : [{ bookVersionId: "unsafe-book", printTitle: "<img src=x onerror=window.injected=true>", createdAt: "2026-09-20T12:00:00Z", pdfURL: "javascript:alert(1)" }]
    ], nextCursor: data.cursor || data.userId === "empty-user" ? null : "books-page-two" } };
    if (name === "adminListUserMemories") {
      if (state.failMemories) throw new Error("Temporary memory failure");
      return { data: { memories: data.userId === "empty-user" ? [] : [{ memoryId: data.cursor ? "memory-two" : "memory-one", prompt: data.userId + (data.cursor ? " past memory" : " memory"), text: "A quiet afternoon.\n<svg onload=window.injected=true>", createdAt: data.cursor ? "2026-09-01T12:00:00Z" : "2026-09-24T12:00:00Z", profileName: "Parent", chapter: "Childhood", textTruncated: true }], nextCursor: data.cursor || data.userId === "empty-user" ? null : "memories-page-two" } };
    }
    throw new Error("Unexpected callable: " + name);
  });
  await page.route("**/*", async route => {
    const url = route.request().url();
    if (url.startsWith("http://127.0.0.1:")) return route.continue();
    if (url.includes("firebase-app-compat.js")) return route.fulfill({ contentType: "text/javascript", body: `
      const fixtureAuth = { currentUser: {uid:'admin-fixture',email:'admin@example.test'}, onAuthStateChanged(cb) { window.authCallback = cb; setTimeout(() => cb(this.currentUser),0); }, signOut() { this.currentUser = null; window.authCallback(null); return Promise.resolve(); } };
      window.fixtureAuth = fixtureAuth;
      window.firebase = {
        initializeApp() {},
        auth: Object.assign(() => fixtureAuth, { GoogleAuthProvider: function() { this.setCustomParameters = () => {}; } }),
        app: () => ({ functions: () => ({ httpsCallable: name => data => window.fixtureCall(name, data || {}) }) })
      };` });
    return route.fulfill({ contentType: url.endsWith(".js") ? "text/javascript" : "text/css", body: "" });
  });
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}/ops/`);
    await page.locator('[data-view="users"]').click();
    const waitText = async (selector, text) => page.waitForFunction(({selector, text}) => document.querySelector(selector)?.textContent.includes(text), {selector, text});
    const choose = async (uid) => {
      await page.locator("#user-id-input").fill(uid);
      await page.locator("#load-books-btn").click();
      await waitText("#selected-user-id", uid);
    };
    await page.getByText("Newest parent", { exact: true }).waitFor();
    assert.equal(calls.find(c => c.name === "adminListUsers").data.sort, "newest");
    assert.equal(await page.locator(".user-open").first().textContent(), "Newest parent");
    await page.locator("#user-sort").selectOption("oldest");
    await page.waitForFunction(() => document.querySelector('.user-open')?.textContent === 'Older parent');
    await page.locator("#more-users").click();
    await page.getByText("Another parent", {exact:true}).waitFor();
    assert.equal(await page.locator(".user-open").count(), 3);
    await page.locator("#user-sort").selectOption("newest");
    await page.locator('.user-open[data-uid="new-user"]').click();
    await waitText("#books-list", "new-user latest book");
    await waitText("#memories-list", "new-user memory");
    assert.equal(await page.locator("#books-list .book-row").first().locator("strong").textContent(), "new-user latest book");
    assert.equal(await page.locator('#books-list a[href^="javascript:"]').count(), 0);
    assert.equal(await page.locator("#books-list img").count(), 0);
    await page.locator("#memories-list summary").first().click();
    assert.equal(await page.locator("#memories-list svg").count(), 0);
    assert.ok(await page.getByText("View full memory in Firebase").isVisible());
    assert.equal(await page.evaluate(() => window.injected), undefined);
    await page.locator("#more-books").click();
    await waitText("#books-list", "past book");
    assert.equal(await page.locator("#books-list .book-row").count(), 3);
    assert.ok((await page.locator("#books-list .book-row").last().textContent()).includes("past book"));
    await page.locator("#more-memories").click();
    await waitText("#memories-list", "past memory");
    assert.equal(await page.locator("#memories-list details").count(), 2);
    assert.ok((await page.locator("#memories-list details").last().textContent()).includes("past memory"));
    await page.screenshot({path:"/tmp/memoir-ops-users-desktop.png", fullPage:true});

    state.failMemories = true;
    await choose("older-user");
    await waitText("#memories-status", "Temporary memory failure");
    await waitText("#books-list", "older-user latest book");
    assert.ok(await page.locator("#retry-memories").isVisible());
    state.failMemories = false;
    await page.locator("#retry-memories").click();
    await waitText("#memories-list", "older-user memory");
    state.failUsers = true;
    await page.locator("#refresh-users").click();
    await waitText("#users-status", "Temporary users failure");
    assert.ok((await page.locator("#books-list").textContent()).includes("older-user latest book"));
    state.failUsers = false;
    await page.locator("#retry-users").click();
    await page.locator('.user-open[data-uid="new-user"]').waitFor();

    state.delayUser = "older-user";
    await choose("older-user");
    await choose("new-user");
    await waitText("#books-list", "new-user latest book");
    await page.waitForTimeout(650);
    assert.ok(!(await page.locator("#books-list").textContent()).includes("older-user"));
    assert.ok(!(await page.locator("#memories-list").textContent()).includes("older-user"));
    await choose("empty-user");
    await waitText("#books-status", "No books saved");
    await waitText("#memories-status", "No memories saved");
    await choose("new-user");
    await waitText("#books-list", "latest book");
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:"/tmp/memoir-ops-users-mobile.png", fullPage:true});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
    state.delayUser = "older-user";
    await choose("older-user");
    await page.locator("#sign-out").click();
    await page.waitForTimeout(650);
    assert.equal(await page.locator("#books-list").textContent(), "");
    assert.equal(await page.locator("#memories-list").textContent(), "");
    assert.equal(await page.locator("#users-tbody").textContent(), "");
    assert.equal(await page.locator("#user-id-input").inputValue(), "");
    assert.equal(await page.locator("#user-sort").inputValue(), "newest");
    assert.deepEqual(errors, []);
    console.log("Users browser: sorting, pagination, content, errors/retries, stale selection, sign-out, escaping, and mobile checks passed");
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(err => { console.error(err); process.exitCode = 1; });
