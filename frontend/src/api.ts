import type { AccountUser, ApiErrorPayload, InboxNotification, ManualOrder, RobloxFile, SessionResponse, SceneResponse } from "./types";

export type QualityMode = "terra" | "astra_max";

export class ApiError extends Error {
  constructor(public payload: ApiErrorPayload, public status: number) {
    super(payload.message || errorPayloadText(payload.errors) || payload.error || `HTTP ${status}`);
    this.name = "ApiError";
  }
}

function errorPayloadText(errors: ApiErrorPayload["errors"]): string | undefined {
  if (!errors) return undefined;
  if (Array.isArray(errors)) {
    return errors.map((item) => typeof item === "string" ? item : `${item.path}: ${item.message}`).join("\n");
  }
  return Object.entries(errors).flatMap(([field, messages]) => Array.isArray(messages) ? messages.map((message) => `${field}: ${message}`) : []).join("\n");
}

export interface RequestOptions {
  signal?: AbortSignal;
  timeoutMs?: number;
}

function pause(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    signal.throwIfAborted();
    const abort = () => { clearTimeout(timer); reject(signal.reason); };
    const timer = setTimeout(() => { signal.removeEventListener("abort", abort); resolve(); }, ms);
    signal.addEventListener("abort", abort, { once: true });
  });
}

async function readJson<T>(response: Response): Promise<T> {
  const text = await response.text();
  try {
    const body: unknown = JSON.parse(text);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("Invalid envelope");
    return body as T;
  } catch {
    throw new ApiError({ error: "invalid_response", message: `HTTP ${response.status}: the server returned an invalid response. Please try again later.` }, response.status);
  }
}

async function readError(response: Response): Promise<ApiError> {
  try {
    const body = await readJson<ApiErrorPayload>(response);
    return new ApiError(body, response.status);
  } catch (error) {
    if (error instanceof ApiError) return error;
    throw error;
  }
}

async function request<T>(url: string, init: RequestInit, options: RequestOptions, decode: (response: Response) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  const cancel = () => controller.abort(options.signal?.reason);
  options.signal?.addEventListener("abort", cancel, { once: true });
  if (options.signal?.aborted) cancel();
  const timer = setTimeout(() => controller.abort(new DOMException("Request timed out", "TimeoutError")), options.timeoutMs ?? 30_000);
  const headers = new Headers(init.headers);
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  const canRetry = (init.method || "GET").toUpperCase() === "GET";
  try {
    for (let attempt = 0; ; attempt += 1) {
      controller.signal.throwIfAborted();
      const response = await fetch(url, { ...init, headers, credentials: "same-origin", cache: "no-store", signal: controller.signal });
      if (response.ok) return await decode(response);
      if (canRetry && attempt < 2 && [429, 502, 503, 504].includes(response.status)) {
        const retryAfter = response.headers.get("Retry-After");
        const seconds = retryAfter === null ? NaN : Number(retryAfter);
        const delay = retryAfter === null ? 500 * 2 ** attempt : Number.isFinite(seconds) ? seconds * 1000 : Date.parse(retryAfter) - Date.now();
        // Do not retry earlier than a long server-requested delay.
        if (Number.isFinite(delay) && delay >= 0 && delay <= 5_000) {
          await response.body?.cancel();
          await pause(delay, controller.signal);
          continue;
        }
      }
      throw await readError(response);
    }
  } catch (error) {
    if (options.signal?.aborted) throw options.signal.reason;
    if (controller.signal.aborted) throw new ApiError({ error: "request_timeout", message: "The request timed out. It may still be processing; check its status before starting it again." }, 0);
    if (error instanceof TypeError) throw new ApiError({ error: "network_error", message: "The server could not be reached. Check your connection and try again." }, 0);
    throw error;
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener("abort", cancel);
  }
}

export function fetchJson<T>(url: string, options: RequestOptions = {}): Promise<T> {
  return request(url, {}, options, readJson<T>);
}

let activeCsrfToken = "";
let sessionRequest: Promise<SessionResponse> | undefined;

async function secureRequest<T>(url: string, csrfToken: string, init: RequestInit, options: RequestOptions, decode: (response: Response) => Promise<T>): Promise<T> {
  let token = activeCsrfToken || csrfToken || (await getSession()).csrf_token;
  for (let attempt = 0; ; attempt += 1) {
    const headers = new Headers(init.headers);
    headers.set("X-CSRF-Token", token);
    try {
      const parsed = await request(url, { ...init, headers }, options, decode);
      if (typeof parsed === "object" && parsed && "csrf_token" in parsed) activeCsrfToken = String(parsed.csrf_token);
      return parsed;
    } catch (error) {
      // Only replay an explicit CSRF rejection, which occurs before any mutation.
      if (attempt === 0 && error instanceof ApiError && error.status === 422 && error.payload.error === "invalid_csrf_token") {
        token = (await getSession()).csrf_token;
      } else throw error;
    }
  }
}

function secureFetch<T>(url: string, csrfToken: string, init: RequestInit = {}, options: RequestOptions = {}): Promise<T> {
  return secureRequest(url, csrfToken, init, options, readJson<T>);
}

export function getSession(): Promise<SessionResponse> {
  sessionRequest ||= fetchJson<SessionResponse>("/api/v1/auth/session")
    .then((session) => { activeCsrfToken = session.csrf_token; return session; })
    .finally(() => { sessionRequest = undefined; });
  return sessionRequest;
}

export function registerAccount(csrfToken: string, payload: { displayName: string; email: string; password: string }): Promise<{ user: AccountUser; csrf_token: string }> {
  return secureFetch("/api/v1/auth/register", csrfToken, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ display_name: payload.displayName, email: payload.email, password: payload.password, password_confirmation: payload.password, terms_accepted: true }),
  });
}

export function loginAccount(csrfToken: string, email: string, password: string): Promise<{ user: AccountUser; csrf_token: string }> {
  return secureFetch("/api/v1/auth/login", csrfToken, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
}

export function requestPasswordReset(csrfToken: string, email: string): Promise<{ ok: boolean; message: string }> {
  return secureFetch("/api/v1/auth/password/forgot", csrfToken, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email }),
  });
}

export function resetPassword(csrfToken: string, token: string, password: string, passwordConfirmation: string): Promise<{ user: AccountUser; csrf_token: string }> {
  return secureFetch("/api/v1/auth/password/reset", csrfToken, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token, password, password_confirmation: passwordConfirmation }),
  });
}

export async function logoutAccount(csrfToken: string): Promise<{ ok: boolean }> {
  const result = await secureFetch<{ ok: boolean }>("/api/v1/auth/logout", csrfToken, { method: "DELETE" });
  activeCsrfToken = "";
  return result;
}

export async function startOAuth(csrfToken: string, provider: string): Promise<void> {
  const response = await secureFetch<{ authorization_url: string }>(`/api/v1/auth/oauth/${provider}`, csrfToken, { method: "POST" });
  window.location.assign(response.authorization_url);
}

export function createManualOrder(csrfToken: string, form: FormData): Promise<{ order: ManualOrder }> {
  return secureFetch("/api/v1/orders", csrfToken, { method: "POST", body: form });
}

export function listOrders(options: RequestOptions = {}): Promise<{ orders: ManualOrder[] }> {
  return fetchJson("/api/v1/orders", options);
}

export function getOrder(publicId: string): Promise<{ order: ManualOrder }> {
  return fetchJson(`/api/v1/orders/${encodeURIComponent(publicId)}`);
}

export function authorizeOrderPayment(csrfToken: string, publicId: string): Promise<{ order: ManualOrder; checkout_url: string }> {
  return secureFetch(`/api/v1/orders/${publicId}/authorize_payment`, csrfToken, { method: "POST" });
}

export function cancelOrder(csrfToken: string, publicId: string): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/orders/${publicId}/cancel`, csrfToken, { method: "POST" });
}

export function listNotifications(): Promise<{ notifications: InboxNotification[] }> {
  return fetchJson("/api/v1/notifications");
}

export function listAdminOrders(options: RequestOptions = {}): Promise<{ orders: ManualOrder[] }> {
  return fetchJson("/api/v1/admin/orders", options);
}

export function updateAdminOrder(csrfToken: string, publicId: string, form: FormData): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/admin/orders/${publicId}`, csrfToken, { method: "PATCH", body: form });
}

export function acceptAdminOrder(csrfToken: string, publicId: string): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/admin/orders/${publicId}/accept`, csrfToken, { method: "POST" });
}

export function declineAdminOrder(csrfToken: string, publicId: string): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/admin/orders/${publicId}/decline`, csrfToken, { method: "POST" });
}

export function approveAdminOrder(csrfToken: string, publicId: string): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/admin/orders/${publicId}/approve`, csrfToken, { method: "POST" });
}

export async function analyzePhoto(photo: File, hint: string, qualityMode: QualityMode, csrfToken: string, options: RequestOptions = {}): Promise<SceneResponse> {
  const body = new FormData();
  body.append("photo", photo);
  body.append("quality_mode", qualityMode);
  body.append("include_map", "true");
  if (hint.trim()) body.append("hint", hint.trim());
  return secureFetch("/api/v1/scenes/analyze", csrfToken, { method: "POST", body }, { timeoutMs: qualityMode === "astra_max" ? 2_460_000 : 660_000, ...options });
}

export async function downloadReadyRoblox(file: RobloxFile): Promise<void> {
  if (file.encoding !== "base64") throw new Error(`Unsupported map encoding: ${file.encoding}`);

  const binary = window.atob(file.data);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  if (bytes.byteLength !== file.byte_size) throw new Error("The downloaded map is incomplete. Please rebuild it.");
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const checksum = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  if (checksum !== file.sha256) throw new Error("The map checksum does not match. Please rebuild it.");
  const url = URL.createObjectURL(new Blob([bytes], { type: file.media_type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = file.filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}

export async function compileScene(sceneSpec: Record<string, unknown>, csrfToken: string, options: RequestOptions = {}): Promise<SceneResponse> {
  return secureFetch("/api/v1/scenes/compile", csrfToken, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ scene_spec: sceneSpec, include_map: true }),
  }, options);
}

export async function downloadRoblox(sceneSpec: Record<string, unknown>, csrfToken = ""): Promise<void> {
  const { blob, disposition } = await secureRequest("/api/v1/scenes/export", csrfToken, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/xml" },
    body: JSON.stringify({ scene_spec: sceneSpec }),
  }, {}, async (response) => ({ blob: await response.blob(), disposition: response.headers.get("Content-Disposition") || "" }));
  const filename = disposition.match(/filename="?([^";]+)"?/)?.[1] || "roblox-scene.rbxlx";
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}
