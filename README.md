# SceneFoundry — Photo to Editable Roblox Map

SceneFoundry is an end-to-end prototype that turns a photograph of a real location into an editable Roblox place:

`photo → OpenAI Vision → SceneSpec JSON → deterministic compiler → SceneIR → Three.js preview / .rbxlx`

The production workflow does not require a user to write JSON or custom code for each photograph. The vision model creates a compact, structured scene description; trusted application code validates it, builds the geometry, renders the preview, and exports a real Roblox XML place file.

## Visual Gallery

### House and landscaped grounds

![A reconstructed Roblox house with landscaped grounds, a pool, trees, and paths](docs/images/house-scene.png)

This representative environment was created during prototype development and demonstrates the level of composition the project is designed to preserve: the building footprint, surrounding paths, vegetation, elevation changes, and pool remain individually editable.

### Park scene in the English interface

![SceneFoundry English interface showing an editable Riverside Park SceneIR preview](docs/images/park-editor-en.jpg)

The park is the checked-in development fixture rendered by the running application. It demonstrates the localized editor, editable SceneIR, Three.js preview, metrics, and export workflow. It is not presented as a live vision inference result. Add `OPENAI_API_KEY` and upload a new image to exercise the complete vision path.

## What Works

- JPEG, PNG, and WebP uploads up to 10 MB.
- A fully localized interface in English and French, with English as the default and the selected language saved in the browser.
- Image analysis through the OpenAI Responses API using a Base64 data URL.
- Two-pass Terra analysis: a high-reasoning spatial draft followed by a lower-cost composition review.
- Strict structured output using the versioned `SceneSpec 1.1` schema.
- Rectangular, elliptical, and arbitrary polygon surfaces; straight or curved bordered paths; semantic objects; repeated groups; procedural composition patterns; spawn position; camera; and source assumptions.
- Reusable procedural patterns for formal gardens, terraces, mountain ridges, and forest framing. These are selected only when the photograph contains that scene structure.
- A generic solid-mass fallback keeps unfamiliar but important objects in the composition instead of silently dropping them.
- Server-side validation of numeric ranges, semantic IDs, references, spawn safety, and scene budgets with precise JSON error paths.
- Automatic proportional normalization of oversized vision geometry and repeated groups before validation, preserving the scene layout while keeping exports within safe limits.
- Deterministic compilation: the same `SceneSpec + seed + component_version` produces the same geometry.
- A shared `SceneIR` consumed by both the interactive Three.js preview and the Roblox exporter.
- A genuine `.rbxlx` XML place containing editable `Model`, `Part`, and `SpawnLocation` instances, plus camera and lighting configuration.
- Per-order timing, token usage, estimated API cost, and an `order_id` in the API response.
- Structured `scene_order_completed` events in the Rails log.
- Safe geometry generation without model-produced executable code, Roblox scripts, or untrusted external asset IDs.

## Architecture

| Layer | Responsibility |
| --- | --- |
| React + TypeScript | Upload workflow, SceneSpec editor, metrics, Three.js preview, and `.rbxlx` download |
| Rails API | File validation, orchestration, compilation, export, and error handling |
| OpenAI Vision | Creates a high-reasoning `SceneSpec 1.1` draft and reviews its visual composition in a cheaper second pass |
| Geometry and budget normalizers | Scale oversized scenes uniformly and reduce only repeated groups when required |
| `Scene::Validator` | Enforces semantic, geometric, reference, spawn, and budget constraints |
| `Scene::Compiler` | Expands registered components into deterministic, portable `SceneIR` |
| `Roblox::Exporter` | Serializes the same `SceneIR` into an editable Roblox XML place |

The coordinate system is fixed to `Y up` and `-Z forward`, with dimensions expressed in Roblox studs. Inferred content outside the photograph is recorded in `source.assumptions`, while `source.scale_confidence` communicates scale uncertainty.

### Processing flow

1. `POST /api/v1/scenes/analyze` validates the uploaded image and sends it to Terra at `high` reasoning effort.
2. Terra identifies the scene family, camera, depth layers, major footprints, paths, terrain, and composition anchors as strict `SceneSpec 1.1` data.
3. A second Terra pass at `medium` effort audits the draft against the same photograph and corrects material composition gaps.
4. Geometry and budget normalizers uniformly scale unsupported dimensions and reduce procedural density when required.
5. `Scene::Validator` applies the constraints intentionally kept outside the Structured Outputs-compatible schema.
6. `Scene::Compiler` expands registered semantic components, generic masses, arbitrary contours, curved paths, and matching procedural patterns into deterministic geometry.
7. A semantic object's seed is derived from the global seed, semantic ID, and component-library version, so editing one object does not reshuffle unrelated geometry.
8. React/Three.js renders the resulting `SceneIR`.
9. `Roblox::Exporter` converts that same `SceneIR` into `.rbxlx`, grouping parts by semantic ID.

No coordinates or rules are tied to a particular photograph. A garden can use `formal_garden`, while a house, street, coast, or unknown scene is assembled from the same reusable surfaces, paths, buildings, masses, elevation patterns, and distributions.

## Quick Start

Requirements:

- Ruby 3.3.4
- Bundler
- Node.js 22 or newer
- npm

```bash
cp .env.example .env
# Add OPENAI_API_KEY to .env
# Defaults: Terra high draft + Terra medium refinement
bin/setup --skip-server
bin/dev
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). `bin/dev` starts Rails on port `3000`, Vite on port `5173`, and loads the local `.env` file. Existing environment variables take precedence.

Without an API key, the UI blocks photograph analysis and explains why. The development example remains available only in `development` and `test`; it is never reported as a vision result.

The interface opens in English. Use the `EN` / `FR` control in the header to switch languages; the choice persists across browser sessions. Localization is implemented with `i18next` and `react-i18next`, and the document language is updated for assistive technologies.

## API

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/status` | Vision readiness, selected model, and component version |
| `GET` | `/api/v1/scenes/schema` | Structured-generation JSON Schema |
| `POST` | `/api/v1/scenes/analyze` | Multipart `photo` and optional `hint` → SceneSpec, SceneIR, and metrics |
| `POST` | `/api/v1/scenes/compile` | Edited `scene_spec` → SceneIR |
| `POST` | `/api/v1/scenes/export` | Edited `scene_spec` → `.rbxlx` |

A successful analysis includes operational metrics:

```json
{
  "metrics": {
    "order_id": "request-id",
    "vision_model": "gpt-5.6-terra",
    "reasoning_effort": "high",
    "refinement_enabled": true,
    "refinement_reasoning_effort": "medium",
    "draft_vision_ms": 0,
    "refinement_ms": 0,
    "vision_ms": 0,
    "compile_ms": 0,
    "total_ms": 0,
    "input_tokens": 0,
    "cached_input_tokens": 0,
    "output_tokens": 0,
    "api_cost_usd": 0
  }
}
```

Estimated cost is calculated from the response's actual token usage. Pricing entries in `Vision::SceneAnalyzer` were last checked on 2026-09-10. An unknown model returns `null` for cost rather than inventing an estimate.

## Determinism and Safety

- Default limits are 1,500 parts and 120,000 estimated triangles.
- Repeated-group expansion is checked before geometry is produced.
- Semantic IDs must be unique, and surface/path references must resolve.
- Spawn locations are rejected when they intersect water or buildings.
- The model produces data, not executable source code.
- The compiler uses a fixed component registry and the exporter emits no Roblox scripts.
- Local secrets such as `.env`, `config/master.key`, and API keys are excluded from Git.

## Verification

```bash
bin/verify
bundle exec rails scenes:generate
```

`bin/verify` runs the Rails test suite, TypeScript type checking, the Vite production build, and `git diff --check`. The scene generator writes all development fixtures to `generated_maps/` and records actual local processing time and file sizes in `generated_maps/generation_metrics.json`.

Latest verified baseline:

- Rails: 26 tests, 134 assertions, 0 failures. The compiler suite covers four unrelated scene families (formal garden, residential courtyard, public park, and coast) plus the generic unknown-object fallback.
- Frontend: TypeScript type check and Vite production build pass.
- Live two-pass Terra workflow: a new garden image completed in 75.73 seconds for an estimated $0.116264 (45.86-second high-reasoning draft plus 29.57-second medium review), normalized an over-budget draft from 1,720 to 1,244 estimated parts, and compiled without photo-specific code.
- Roblox export: XML parses successfully, the part count matches SceneIR, exactly one `SpawnLocation` exists, and no scripts are present.
- Fixture compilation: coast — 98 parts; courtyard — 148 parts; formal garden — 971 parts; park — 194 parts.

The live verification used a local ignored `OPENAI_API_KEY`; no secret is committed. The Responses API contract is also covered by a fake-transport test, while the multipart upload → analyzer → normalization → validator → compiler path is covered by integration tests.

## Current Limitations

- A single photograph cannot reveal true depth or hidden geometry. SceneFoundry preserves the recognizable composition and records assumptions, but it does not claim photogrammetric accuracy.
- This milestone builds geometry from Roblox primitives. A visually unusual object can be preserved as an editable approximate mass, but dedicated assets, `MeshPart`, terrain voxels, and textures will be required for product-grade object fidelity.
- The second pass reviews structured composition, not a rendered preview. The largest remaining quality improvement is a render-and-compare loop that lets the model correct the actual generated image.
- API cost is an estimate derived from token usage, not a billing receipt.

## Key Files

- `config/schema/scene_spec.schema.json` — structured-output contract.
- `app/services/vision/scene_analyzer.rb` — vision request and usage metrics.
- `app/services/scene/validator.rb` — semantic and budget validation.
- `app/services/scene/geometry_normalizer.rb` — proportional scaling and numeric range normalization.
- `app/services/scene/budget_normalizer.rb` — deterministic reduction of repeated groups when needed.
- `app/services/scene/compiler.rb` — deterministic scene compilation.
- `app/services/scene/component_registry.rb` — trusted component library.
- `app/services/roblox/exporter.rb` — `.rbxlx` export.
- `frontend/src/App.tsx` — upload, editing, metrics, and export workflow.
- `frontend/src/i18n.ts` — English and French interface resources and language persistence.
- `frontend/src/SceneViewer.tsx` — interactive Three.js scene preview.
