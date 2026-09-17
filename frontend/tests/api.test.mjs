import { test, afterEach, mock } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import ts from "typescript";

const source = await readFile(new URL("../src/api.ts", import.meta.url), "utf8");
let moduleId = 0;
async function api() {
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(`${compiled}\n// test instance ${moduleId++}`).toString("base64")}`);
}
const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } });
afterEach(() => mock.restoreAll());

test("coalesces concurrent session reads and never caches private responses", async () => {
  const client = await api();
  const fetch = mock.method(globalThis, "fetch", async (_url, init) => {
    assert.equal(init.credentials, "same-origin");
    assert.equal(init.cache, "no-store");
    return json({ csrf_token: "current", user: null });
  });
  const sessions = await Promise.all([client.getSession(), client.getSession(), client.getSession()]);
  assert.equal(fetch.mock.callCount(), 1);
  assert.equal(sessions[2].csrf_token, "current");
});

test("preserves an HTTP failure when a proxy returns HTML", async () => {
  const client = await api();
  mock.method(globalThis, "fetch", async () => new Response("<h1>Unavailable</h1>", { status: 503, headers: { "Retry-After": "90" } }));
  await assert.rejects(client.listOrders(), (error) => error instanceof client.ApiError && error.status === 503 && error.payload.error === "invalid_response");
});

test("rejects empty and non-object success responses", async () => {
  const client = await api();
  for (const value of ["", "null", "[]"]) {
    mock.method(globalThis, "fetch", async () => new Response(value));
    await assert.rejects(client.listOrders(), (error) => error.payload.error === "invalid_response");
    mock.restoreAll();
  }
});

test("retries transient GET failures within a fixed attempt limit", async () => {
  const client = await api();
  let calls = 0;
  mock.method(globalThis, "fetch", async () => ++calls < 3 ? json({ error: "busy" }, 429, { "Retry-After": "0" }) : json({ orders: [] }));
  assert.deepEqual(await client.listOrders(), { orders: [] });
  assert.equal(calls, 3);
});

test("never replays a paid analysis or order mutation after HTTP failure", async () => {
  const client = await api();
  const fetch = mock.method(globalThis, "fetch", async () => json({ error: "vision_timeout" }, 504));
  await assert.rejects(client.analyzePhoto(new File(["photo"], "photo.png", { type: "image/png" }), "", "terra", "csrf"));
  assert.equal(fetch.mock.callCount(), 1);
});

test("refreshes CSRF once and retains the rotated token for later mutations", async () => {
  const client = await api();
  const tokens = [];
  let sessions = 0;
  mock.method(globalThis, "fetch", async (url, init) => {
    if (url.endsWith("/session")) { sessions++; return json({ csrf_token: "fresh" }); }
    tokens.push(init.headers.get("X-CSRF-Token"));
    return tokens.length === 1 ? json({ error: "invalid_csrf_token" }, 422) : json({ order: {} });
  });
  await client.cancelOrder("old", "order-id");
  await client.cancelOrder("old", "order-id");
  assert.equal(sessions, 1);
  assert.deepEqual(tokens, ["old", "fresh", "fresh"]);
});

test("does not retry validation failures or an endless CSRF rejection", async () => {
  const client = await api();
  let mutations = 0;
  mock.method(globalThis, "fetch", async (url) => {
    if (url.endsWith("/session")) return json({ csrf_token: "fresh" });
    mutations++;
    return json({ error: "invalid_csrf_token" }, 422);
  });
  await assert.rejects(client.cancelOrder("old", "order-id"));
  assert.equal(mutations, 2);
});

test("reports a timeout and forwards explicit cancellation without retry", async () => {
  const client = await api();
  const fetch = mock.method(globalThis, "fetch", (_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener("abort", () => reject(init.signal.reason), { once: true });
  }));
  await assert.rejects(client.fetchJson("/api/test", { timeoutMs: 5 }), (error) => error.payload.error === "request_timeout");
  const controller = new AbortController();
  const pending = client.listOrders({ signal: controller.signal });
  controller.abort();
  await assert.rejects(pending, (error) => error.name === "AbortError");
  assert.equal(fetch.mock.callCount(), 2);
});

test("export sends CSRF and handles JSON rejection before downloading a blob", async () => {
  const client = await api();
  mock.method(globalThis, "fetch", async (_url, init) => {
    assert.equal(init.headers.get("X-CSRF-Token"), "export-token");
    assert.equal(init.headers.get("Accept"), "application/xml");
    return json({ error: "admin_required" }, 403);
  });
  await assert.rejects(client.downloadRoblox({}, "export-token"), (error) => error.status === 403);
});

test("checks map length and checksum before creating a download", async (t) => {
  const client = await api();
  const previousWindow = globalThis.window;
  globalThis.window = { atob: globalThis.atob };
  t.after(() => { if (previousWindow === undefined) delete globalThis.window; else globalThis.window = previousWindow; });
  const file = { encoding: "base64", data: btoa("xml"), byte_size: 99, sha256: "wrong" };
  await assert.rejects(client.downloadReadyRoblox(file), /incomplete/);
  await assert.rejects(client.downloadReadyRoblox({ ...file, byte_size: 3 }), /checksum/);
});
