import type { AccountUser, ApiErrorPayload, InboxNotification, ManualOrder, RobloxFile, SessionResponse, SceneResponse } from "./types";

export type QualityMode = "terra" | "astra_max";

export class ApiError extends Error {
  constructor(public payload: ApiErrorPayload, public status: number) {
    super(payload.message || errorPayloadText(payload.errors) || payload.error || `HTTP ${status}`);
  }
}

function errorPayloadText(errors: ApiErrorPayload["errors"]): string | undefined {
  if (!errors) return undefined;
  if (Array.isArray(errors)) {
    return errors.map((item) => typeof item === "string" ? item : `${item.path}: ${item.message}`).join("\n");
  }
  return Object.entries(errors).flatMap(([field, messages]) => messages.map((message) => `${field}: ${message}`)).join("\n");
}

async function parseResponse(response: Response): Promise<SceneResponse> {
  const body = (await response.json()) as SceneResponse & ApiErrorPayload;
  if (!response.ok) throw new ApiError(body, response.status);
  return body;
}

async function parseJson<T>(response: Response): Promise<T> {
  const body = (await response.json()) as T & ApiErrorPayload;
  if (!response.ok) throw new ApiError(body, response.status);
  return body;
}

async function secureFetch<T>(url: string, csrfToken: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("X-CSRF-Token", csrfToken);
  return parseJson<T>(await fetch(url, { ...init, headers }));
}

export function getSession(): Promise<SessionResponse> {
  return fetch("/api/v1/auth/session").then((response) => parseJson<SessionResponse>(response));
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

export function logoutAccount(csrfToken: string): Promise<{ ok: boolean }> {
  return secureFetch("/api/v1/auth/logout", csrfToken, { method: "DELETE" });
}

export async function startOAuth(csrfToken: string, provider: string): Promise<void> {
  const response = await secureFetch<{ authorization_url: string }>(`/api/v1/auth/oauth/${provider}`, csrfToken, { method: "POST" });
  window.location.assign(response.authorization_url);
}

export function createManualOrder(csrfToken: string, form: FormData): Promise<{ order: ManualOrder }> {
  return secureFetch("/api/v1/orders", csrfToken, { method: "POST", body: form });
}

export function listOrders(): Promise<{ orders: ManualOrder[] }> {
  return fetch("/api/v1/orders").then((response) => parseJson<{ orders: ManualOrder[] }>(response));
}

export function requestPurchase(csrfToken: string, publicId: string): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/orders/${publicId}/purchase`, csrfToken, { method: "POST" });
}

export function listNotifications(): Promise<{ notifications: InboxNotification[] }> {
  return fetch("/api/v1/notifications").then((response) => parseJson<{ notifications: InboxNotification[] }>(response));
}

export function listAdminOrders(): Promise<{ orders: ManualOrder[] }> {
  return fetch("/api/v1/admin/orders").then((response) => parseJson<{ orders: ManualOrder[] }>(response));
}

export function updateAdminOrder(csrfToken: string, publicId: string, form: FormData): Promise<{ order: ManualOrder }> {
  return secureFetch(`/api/v1/admin/orders/${publicId}`, csrfToken, { method: "PATCH", body: form });
}

export async function analyzePhoto(photo: File, hint: string, qualityMode: QualityMode): Promise<SceneResponse> {
  const body = new FormData();
  body.append("photo", photo);
  body.append("quality_mode", qualityMode);
  body.append("include_map", "true");
  if (hint.trim()) body.append("hint", hint.trim());
  return parseResponse(await fetch("/api/v1/scenes/analyze", { method: "POST", body }));
}

export function downloadReadyRoblox(file: RobloxFile): void {
  if (file.encoding !== "base64") throw new Error(`Unsupported map encoding: ${file.encoding}`);

  const binary = window.atob(file.data);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  const url = URL.createObjectURL(new Blob([bytes], { type: file.media_type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = file.filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}

export async function compileScene(sceneSpec: Record<string, unknown>): Promise<SceneResponse> {
  return parseResponse(
    await fetch("/api/v1/scenes/compile", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ scene_spec: sceneSpec, include_map: true }),
    }),
  );
}

export async function downloadRoblox(sceneSpec: Record<string, unknown>): Promise<void> {
  const response = await fetch("/api/v1/scenes/export", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ scene_spec: sceneSpec }),
  });
  if (!response.ok) {
    const payload = (await response.json()) as ApiErrorPayload;
    throw new ApiError(payload, response.status);
  }
  const disposition = response.headers.get("Content-Disposition") || "";
  const filename = disposition.match(/filename="?([^";]+)"?/)?.[1] || "roblox-scene.rbxlx";
  const url = URL.createObjectURL(await response.blob());
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}
