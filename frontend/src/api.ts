import type { ApiErrorPayload, SceneResponse } from "./types";

export class ApiError extends Error {
  constructor(public payload: ApiErrorPayload, public status: number) {
    super(payload.message || payload.errors?.map((item) => `${item.path}: ${item.message}`).join("\n") || `HTTP ${status}`);
  }
}

async function parseResponse(response: Response): Promise<SceneResponse> {
  const body = (await response.json()) as SceneResponse & ApiErrorPayload;
  if (!response.ok) throw new ApiError(body, response.status);
  return body;
}

export async function analyzePhoto(photo: File, hint: string): Promise<SceneResponse> {
  const body = new FormData();
  body.append("photo", photo);
  if (hint.trim()) body.append("hint", hint.trim());
  return parseResponse(await fetch("/api/v1/scenes/analyze", { method: "POST", body }));
}

export async function compileScene(sceneSpec: Record<string, unknown>): Promise<SceneResponse> {
  return parseResponse(
    await fetch("/api/v1/scenes/compile", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ scene_spec: sceneSpec }),
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
  link.click();
  URL.revokeObjectURL(url);
}
