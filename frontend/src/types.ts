export type Vector3 = [number, number, number];

export interface ScenePart {
  id: string;
  source_id: string;
  group: string;
  name: string;
  shape: "block" | "ball" | "cylinder" | "wedge";
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

export type OAuthProviderName = "google";

export interface OAuthProviderStatus {
  name: OAuthProviderName;
  configured: boolean;
}

export interface SessionResponse {
  user: AccountUser | null;
  csrf_token: string;
  oauth_providers: OAuthProviderStatus[];
}

export type OrderStatus =
  | "payment_pending"
  | "submitted"
  | "accepted"
  | "building"
  | "reviewing"
  | "preview_ready"
  | "ready"
  | "delivered"
  | "declined"
  | "cancelled"
  | "failed";

export type PaymentStatus =
  | "unpaid"
  | "authorization_pending"
  | "authorized"
  | "capture_pending"
  | "paid"
  | "released"
  | "refund_pending"
  | "refunded"
  | "failed";

export interface GenerationMetrics extends Metrics {
  model?: string;
  provider?: string;
  elapsed_ms?: number;
  latency_ms?: number;
  cost_usd?: number | null;
  [key: string]: string | number | boolean | null | undefined;
}

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
  submitted_at: string | null;
  delivery_due_at: string | null;
  completed_at: string | null;
  purchase_requested_at?: string | null;
  paid_at: string | null;
  authorization_expires_at: string | null;
  authorized_at: string | null;
  capture_requested_at: string | null;
  captured_at?: string | null;
  released_at: string | null;
  refunded_at?: string | null;
  generation_started_at: string | null;
  generation_finished_at: string | null;
  generation_attempts: number;
  generation_metrics?: GenerationMetrics | null;
  generation_error?: string | null;
  payment_error?: string | null;
  rights_confirmed: boolean;
  source_photos: Array<{ id?: number; filename: string; byte_size: number; content_type: string; download_url?: string }>;
  preview_url: string | null;
  preview_scene_ir: SceneIR | null;
  result_url: string | null;
  user?: { email: string; display_name: string };
  admin_notes?: string | null;
  can_authorize: boolean;
  can_cancel: boolean;
  can_accept: boolean;
  can_decline: boolean;
  can_approve: boolean;
  can_download: boolean;
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
