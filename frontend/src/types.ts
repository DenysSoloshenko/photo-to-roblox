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
  vision_ms?: number;
  compile_ms?: number;
  total_ms?: number;
  input_tokens?: number;
  output_tokens?: number;
  api_cost_usd?: number | null;
  pricing_basis?: string;
  budget_adjusted?: boolean;
  original_estimated_parts?: number;
  estimated_parts?: number;
  removed_group_instances?: number;
  geometry_adjusted?: boolean;
  geometry_scale?: number;
}

export interface SceneResponse {
  scene_spec: Record<string, unknown>;
  scene_ir: SceneIR;
  metrics: Metrics;
}

export interface ApiErrorPayload {
  error?: string;
  message?: string;
  errors?: Array<{ path: string; message: string; id?: string }>;
}
