export type Vector3 = [number, number, number];

export interface ScenePart {
  id: string;
  source_id: string;
  group: string;
  name: string;
  shape: "block" | "ball" | "cylinder";
  position: Vector3;
  size: Vector3;
  rotation: Vector3;
  material: string;
  color: string;
  transparency: number;
  collidable: boolean;
  cast_shadow: boolean;
  class?: "SpawnLocation";
}

export interface SceneIR {
  version: string;
  component_version: string;
  name: string;
  seed: number;
  spec_digest: string;
  bounds: { width: number; depth: number; max_height: number };
  parts: ScenePart[];
  spawn: { position: Vector3; rotation_y: number };
  camera: { position: Vector3; target: Vector3; fov: number };
  stats: { part_count: number; triangle_estimate: number; compile_ms: number };
}

export interface Metrics {
  order_id?: string;
  vision_model?: string;
  quality_mode?: "terra" | "astra_max";
  reasoning_effort?: string | null;
  refinement_enabled?: boolean;
  refinement_reasoning_effort?: string | null;
  draft_vision_ms?: number;
  refinement_ms?: number;
  draft_api_cost_usd?: number | null;
  refinement_api_cost_usd?: number | null;
  vision_ms?: number;
  compile_ms?: number;
  export_ms?: number;
  rbxlx_bytes?: number;
  map_ready?: boolean;
  total_ms?: number;
  input_tokens?: number;
  cached_input_tokens?: number;
  cache_write_tokens?: number;
  output_tokens?: number;
  api_cost_usd?: number | null;
  pricing_basis?: string;
  budget_adjusted?: boolean;
  original_estimated_parts?: number;
  estimated_parts?: number;
  removed_group_instances?: number;
  geometry_adjusted?: boolean;
  geometry_scale?: number;
  bounds_expanded?: boolean;
}

export interface RobloxFile {
  filename: string;
  media_type: "application/xml";
  encoding: "base64";
  data: string;
  byte_size: number;
  sha256: string;
  spec_digest: string;
}

export interface SceneResponse {
  scene_spec: Record<string, unknown>;
  scene_ir: SceneIR;
  roblox_file?: RobloxFile;
  metrics: Metrics;
}

export interface ApiErrorPayload {
  error?: string;
  message?: string;
  errors?: Array<{ path: string; message: string; id?: string }> | Record<string, string[]> | string[];
}

export interface AccountUser {
  id: number;
  email: string;
  display_name: string;
  admin: boolean;
  oauth_only: boolean;
}

export interface SessionResponse {
  user: AccountUser | null;
  csrf_token: string;
  oauth_providers: Array<"google" | "github" | "discord">;
}

export type OrderStatus = "submitted" | "reviewing" | "building" | "preview_ready" | "ready" | "delivered" | "cancelled";
export type PaymentStatus = "unpaid" | "requested" | "paid" | "refunded";

export interface ManualOrder {
  public_id: string;
  status: OrderStatus;
  payment_status: PaymentStatus;
  title: string;
  scene_type: string;
  style: string;
  must_preserve: string | null;
  instructions: string | null;
  price_cents: number;
  currency: string;
  submitted_at: string;
  delivery_due_at: string;
  completed_at: string | null;
  purchase_requested_at: string | null;
  paid_at: string | null;
  rights_confirmed: boolean;
  source_photos: Array<{ id?: number; filename: string; byte_size: number; content_type: string; download_url?: string }>;
  preview_url: string | null;
  result_url: string | null;
  user?: { email: string; display_name: string };
  admin_notes?: string | null;
}

export interface InboxNotification {
  id: number;
  order_public_id: string;
  kind: string;
  title: string;
  body: string;
  read: boolean;
  created_at: string;
}
