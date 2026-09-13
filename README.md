# SceneFoundry — Photo to Editable Roblox Map

SceneFoundry is a manual-first service and an end-to-end AI prototype for turning photographs of real locations into editable Roblox places.

The customer-facing beta uses a reservation-first offer: creating the request is free, Stripe places a $19 authorization hold, and an operator either accepts the order and captures it or declines it and releases the hold. Only a captured order can enter the premium Astra pipeline, and generated output remains private until a human approves it.

The separate AI Lab keeps the automated pipeline available for internal experiments:

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

- Email/password registration with bcrypt password hashing and encrypted, HttpOnly cookie sessions.
- Google, GitHub, and Discord OAuth login controls with clear setup state until provider credentials are configured.
- Private customer accounts with a persistent order history.
- Requests containing one to three private source photos, a scene/style brief, and a recorded image-rights confirmation.
- A manual operator queue with source downloads, private notes, replacement artifacts, an interactive QA preview, and explicit accept/capture, decline/release, and approve/deliver actions.
- Automatic extraction of safe browser-preview geometry from the operator's `.rbxlx`; no second JSON upload is required.
- A $19 Stripe Checkout authorization using manual capture: placing a hold does not charge the customer, acceptance captures once, and decline/cancel releases an uncaptured authorization.
- Persisted Stripe-event deduplication, row-locked transitions, amount/currency/customer validation, and idempotency keys protect against duplicate capture and replayed webhooks.
- A guarded background job runs Astra Max only after verified capture, enforces concurrency and daily-spend ceilings, records cost/latency, and leaves the result in private operator review.
- Customer progress for every order and payment state; interactive preview and `.rbxlx` download become visible only after approval.
- In-app notifications and email when the preview or paid download becomes ready.
- JPEG, PNG, and WebP uploads up to 10 MB.
- A fully localized interface in English and French, with English as the default and the selected language saved in the browser.
- Image analysis through the OpenAI Responses API using a Base64 data URL.
- Two quality profiles: the default two-pass Terra analysis (`high` spatial draft + `medium` composition review), and an explicitly enabled Astra Max profile (`gpt-6-astra` `max` draft + `high` review).
- Strict structured output using the versioned `SceneSpec 1.1` schema.
- Rectangular, elliptical, and arbitrary polygon surfaces; straight or curved bordered paths; semantic objects; repeated groups; procedural composition patterns; spawn position; camera; and source assumptions.
- Reusable procedural patterns for formal gardens, terraces, mountain ridges, and forest framing. These are selected only when the photograph contains that scene structure.
- A generic solid-mass fallback keeps unfamiliar but important objects in the composition instead of silently dropping them.
- Server-side validation of numeric ranges, semantic IDs, references, spawn safety, and scene budgets with precise JSON error paths.
- Automatic proportional normalization of oversized vision geometry and repeated groups before validation, preserving the scene layout while keeping exports within safe limits.
- Deterministic compilation: the same `SceneSpec + seed + component_version` produces the same geometry.
- A shared `SceneIR` consumed by both the interactive Three.js preview and the Roblox exporter.
- A genuine `.rbxlx` XML place containing editable `Model`, `Part`, and `SpawnLocation` instances, plus camera and lighting configuration.
- An opt-in ready-map response: requests with `include_map=true` receive the compiled `.rbxlx` as a checksummed Base64 `roblox_file`, so the browser can download it without a second export request.
- Per-order timing, token usage, estimated API cost, and an `order_id` in the API response.
- Structured `scene_order_completed` events in the Rails log.
- Safe geometry generation without model-produced executable code, Roblox scripts, or untrusted external asset IDs.

## Architecture

| Layer | Responsibility |
| --- | --- |
| React + TypeScript | Customer accounts, authorization/progress workflow, operator controls, AI Lab, Three.js preview, and `.rbxlx` download |
| Rails API + PostgreSQL | Authentication, private orders, guarded state transitions, Stripe event ledger, generation metrics, notifications, validation, orchestration, compilation, and export |
| Active Storage + Action Mailer | Private local order artifacts (S3-ready) and preview/download-ready email delivery |
| Stripe Checkout + signed webhook | Hosted manual-capture authorization, authoritative capture/release/refund state, and replay-safe reconciliation |
| Active Job | Post-capture Astra generation with PostgreSQL advisory locking, concurrency limits, and a daily spend ceiling |
| OpenAI Vision | Creates a strict `SceneSpec 1.1` draft and reviews its visual composition using the request-selected Terra or Astra Max profile |
| Geometry and budget normalizers | Scale oversized scenes uniformly and reduce only repeated groups when required |
| `Scene::Validator` | Enforces semantic, geometric, reference, spawn, and budget constraints |
| `Scene::Compiler` | Expands registered components into deterministic, portable `SceneIR` |
| `Roblox::Exporter` | Serializes the same `SceneIR` into an editable Roblox XML place |

The coordinate system is fixed to `Y up` and `-Z forward`, with dimensions expressed in Roblox studs. Inferred content outside the photograph is recorded in `source.assumptions`, while `source.scale_confidence` communicates scale uncertainty.

### Processing flow

1. `POST /api/v1/scenes/analyze` validates the uploaded image and selects the requested quality profile. Terra remains the default; `quality_mode=astra_max` is available only when `ASTRA_QUALITY_ENABLED=true`.
2. The selected model identifies the scene family, camera, depth layers, major footprints, paths, terrain, and composition anchors as strict `SceneSpec 1.1` data. The Astra Max profile uses `gpt-6-astra` with `max` reasoning for this draft.
3. A second pass audits the draft against the same photograph and corrects material composition gaps. Terra uses `medium` reasoning; Astra Max uses `high` reasoning.
4. Geometry and budget normalizers uniformly scale unsupported dimensions and reduce procedural density when required.
5. `Scene::Validator` applies the constraints intentionally kept outside the Structured Outputs-compatible schema.
6. `Scene::Compiler` expands registered semantic components, generic masses, arbitrary contours, curved paths, and matching procedural patterns into deterministic geometry.
7. A semantic object's seed is derived from the global seed, semantic ID, and component-library version, so editing one object does not reshuffle unrelated geometry.
8. React/Three.js renders the resulting `SceneIR`.
9. `Roblox::Exporter` converts that same `SceneIR` into `.rbxlx`, grouping parts by semantic ID. With `include_map=true`, the API includes this ready file in the response as `roblox_file`.

The model still returns structured scene data internally; it does not write executable code or arbitrary Roblox XML. The trusted Ruby compiler and exporter create the final map immediately in the same request, which keeps the `.rbxlx` valid, deterministic, and safe to edit.

No coordinates or rules are tied to a particular photograph. A garden can use `formal_garden`, while a house, street, coast, or unknown scene is assembled from the same reusable surfaces, paths, buildings, masses, elevation patterns, and distributions.

## Quick Start

Requirements:

- Ruby 3.3.4
- Bundler
- Node.js 22 or newer
- npm
- PostgreSQL 16 or newer

```bash
cp .env.example .env
# Add OPENAI_API_KEY to .env
# Set ADMIN_EMAILS to the account that will fulfill orders
# Add Stripe test keys and OAuth credentials when testing those integrations
# Defaults: Terra high draft + Terra medium refinement
# Optional premium profile, after configuring authentication, quotas, and spend limits:
# ASTRA_QUALITY_ENABLED=true
# Enable paid-order generation only after Stripe test webhooks are verified:
# ASTRA_ORDER_AUTOMATION_ENABLED=true
bin/setup --skip-server
bin/dev
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). `bin/dev` starts Rails on port `3000`, Vite on port `5173`, and loads the local `.env` file. Existing environment variables take precedence.

Without an API key, the UI blocks photograph analysis and explains why. The development example remains available only in `development` and `test`; it is never reported as a vision result.

An order can be created without an OpenAI key, but automatic fulfillment stays disabled until both Astra flags and `OPENAI_API_KEY` are configured. PostgreSQL is required. In development, notification emails are written to `tmp/mails` unless SMTP variables are supplied. Register using an address listed in `ADMIN_EMAILS` to reveal the operator queue.

### Social login

Create OAuth applications for the providers you want to enable, then put their client ID and secret in `.env`. All supported options stay visible in the account dialog; unconfigured providers are disabled and labeled “Setup required.” For the default local setup, register these callback URLs:

- Google: `http://127.0.0.1:3000/api/v1/auth/oauth/google/callback`
- GitHub: `http://127.0.0.1:3000/api/v1/auth/oauth/github/callback`
- Discord: `http://127.0.0.1:3000/api/v1/auth/oauth/discord/callback`

Set `APP_URL` to the browser-facing origin and `API_URL` to the Rails origin. Verified provider email addresses are required before a social identity is linked to an existing account.

### Payments and private files

Set `STRIPE_SECRET_KEY` to a Stripe test-mode secret. For local webhook testing, install the Stripe CLI and run:

```bash
stripe listen --forward-to 127.0.0.1:3000/api/v1/payments/stripe/webhook
```

Copy the emitted `whsec_…` value to `STRIPE_WEBHOOK_SECRET`, then restart `bin/dev`. Checkout creates an uncaptured PaymentIntent. A matching signed webhook confirms the authorization; only an operator acceptance can capture it and queue generation. Decline or customer cancellation releases the hold. Use Stripe test mode until the complete flow has been exercised.

The production order path is:

`upload → authorize $19 hold → operator accepts/captures → guarded Astra job → operator QA → approved preview + .rbxlx`

`ASTRA_ORDER_AUTOMATION_ENABLED` defaults to `false`. `ASTRA_ORDER_MAX_CONCURRENT`, `ASTRA_ORDER_DAILY_SPEND_LIMIT_USD`, and `ASTRA_ORDER_COST_RESERVATION_USD` provide conservative server-side spend controls. See [`docs/order_workflow_contract.md`](docs/order_workflow_contract.md) for the complete state and endpoint contract.

PostgreSQL stores relational data and the compact preview SceneIR. Active Storage stores source photos, optional preview images, and `.rbxlx` files under private local `storage/` during development. Set `ACTIVE_STORAGE_SERVICE=amazon` plus the AWS/S3 variables in `.env` to move binaries to private S3 later without changing the order model.

The interface opens in English. Use the `EN` / `FR` control in the header to switch languages; the choice persists across browser sessions. Localization is implemented with `i18next` and `react-i18next`, and the document language is updated for assistive technologies.

## API

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/status` | Vision readiness, selected model, and component version |
| `GET` | `/api/v1/auth/session` | Current account, CSRF token, and enabled OAuth providers |
| `POST` | `/api/v1/auth/register` | Create an email/password account |
| `POST` | `/api/v1/auth/login` | Start an encrypted browser session |
| `POST` | `/api/v1/auth/oauth/:provider` | Start Google, GitHub, or Discord OAuth |
| `GET, POST` | `/api/v1/orders` | List private orders or create a request awaiting payment authorization |
| `POST` | `/api/v1/orders/:public_id/authorize_payment` | Create or reuse a hosted $19 manual-capture Stripe Checkout session |
| `POST` | `/api/v1/orders/:public_id/cancel` | Cancel before capture and release/expire the authorization |
| `POST` | `/api/v1/admin/orders/:public_id/accept` | Capture an authorized order exactly once and queue generation |
| `POST` | `/api/v1/admin/orders/:public_id/decline` | Decline before capture and release the hold |
| `POST` | `/api/v1/admin/orders/:public_id/approve` | Publish a reviewed paid result to the customer |
| `POST` | `/api/v1/payments/stripe/webhook` | Verify and deduplicate authorization, capture, release, failure, and refund events |
| `GET` | `/api/v1/notifications` | List in-app order notifications |
| `GET, PATCH` | `/api/v1/admin/orders` | Operate the manual fulfillment queue |
| `GET` | `/api/v1/scenes/schema` | Structured-generation JSON Schema |
| `POST` | `/api/v1/scenes/analyze` | Multipart `photo`, optional `hint`, `quality_mode`, and `include_map` → SceneSpec, SceneIR, metrics, and optionally a ready map |
| `POST` | `/api/v1/scenes/compile` | Edited `scene_spec`, with optional `include_map` → SceneIR and optionally a ready map |
| `POST` | `/api/v1/scenes/export` | Edited `scene_spec` → `.rbxlx` |

Terra is the default quality mode and requires no request parameter. Astra Max is deliberately opt-in because it can be materially slower and more expensive: set `ASTRA_QUALITY_ENABLED=true`, then send `quality_mode=astra_max`. The profile is fixed to a `gpt-6-astra` `max` draft followed by a `high`-reasoning review; clients cannot override those efforts per request.

The frontend asks for `include_map=true` during analysis and recompilation. That makes the response self-contained: the map is compiled by `Scene::Compiler` and `Roblox::Exporter`, then returned as:

```json
{
  "scene_spec": {},
  "scene_ir": {},
  "roblox_file": {
    "filename": "coastal-garden.rbxlx",
    "media_type": "application/xml",
    "encoding": "base64",
    "data": "PHJvYmxveC4uLg==",
    "byte_size": 123456,
    "sha256": "...",
    "spec_digest": "..."
  },
  "metrics": {
    "map_ready": true,
    "export_ms": 0,
    "rbxlx_bytes": 123456
  }
}
```

Without `include_map=true`, analysis, compilation, and development-example responses remain lean and backward-compatible: they return `scene_spec`, `scene_ir`, and metrics with `map_ready: false`, but omit `roblox_file`. The existing streaming `/export` endpoint also remains available.

Base64 is practical for this local prototype and lets the browser download the exact artifact already built by the server. For production, upload the `.rbxlx` to private object storage and return a short-lived signed URL instead; that avoids Base64's size overhead and large JSON responses.

A successful analysis includes operational metrics:

```json
{
  "metrics": {
    "order_id": "request-id",
    "vision_model": "gpt-5.6-terra",
    "quality_mode": "terra",
    "reasoning_effort": "high",
    "refinement_enabled": true,
    "refinement_reasoning_effort": "medium",
    "draft_vision_ms": 0,
    "refinement_ms": 0,
    "vision_ms": 0,
    "compile_ms": 0,
    "map_ready": false,
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

- Customer and operator mutations require a per-session CSRF token; login sessions are encrypted and HttpOnly.
- Source photos, previews, and result files are served only after owner/admin authorization.
- A customer cannot download the `.rbxlx` until Stripe confirms capture, generation produces a result, and an operator approves it.
- Stripe webhooks are deduplicated in PostgreSQL and every payment transition validates the order ID, amount, currency, and PaymentIntent identity.
- Astra order generation starts only for a paid order in `building`, runs once by default, and is disabled unless explicit automation and spend-limit configuration is present.
- Social accounts are linked by email only when the provider confirms that email is verified.
- Default limits are 1,500 parts and 120,000 estimated triangles.
- Repeated-group expansion is checked before geometry is produced.
- Semantic IDs must be unique, and surface/path references must resolve.
- Spawn locations are rejected when they intersect water or buildings.
- The model produces data, not executable source code.
- The compiler uses a fixed component registry and the exporter emits no Roblox scripts.
- Astra Max is disabled by default and guarded by `ASTRA_QUALITY_ENABLED`; enable it only after configuring authentication, quotas, and spend limits.
- Local secrets such as `.env`, `config/master.key`, and API keys are excluded from Git.

## Verification

```bash
bin/verify
bundle exec rails scenes:generate
```

`bin/verify` runs the Rails test suite, TypeScript type checking, the Vite production build, and `git diff --check`. The scene generator writes all development fixtures to `generated_maps/` and records actual local processing time and file sizes in `generated_maps/generation_metrics.json`.

Latest verified AI-pipeline baseline (the account/order suite is also run by `bin/verify`):

- Rails: 57 tests, 319 assertions, 0 failures. The suite covers accounts, CSRF, OAuth identity linking, private orders and result files, state-transition guards, manual-capture Stripe authorization, event deduplication, capture/release, Astra job gating and reserved spend, operator approval, `.rbxlx` preview extraction, notifications, four unrelated scene families, exact quality profiles, incomplete API responses, and ready-map integrity.
- Frontend: TypeScript type check and Vite production build pass.
- Live two-pass Terra workflow: a new garden image completed in 75.73 seconds for an estimated $0.116264 (45.86-second high-reasoning draft plus 29.57-second medium review), normalized an over-budget draft from 1,720 to 1,244 estimated parts, and compiled without photo-specific code.
- Live Astra Max workflow on a new 5.14 MB garden photograph: 830.44 seconds of vision work (634.56-second `max` draft plus 195.88-second `high` review), estimated API cost $2.999685 from 15,444 input and 56,133 output tokens, then a 1.40 MB ready `.rbxlx` response with 1,040 compiled parts. End-to-end server time was 832.27 seconds.
- Roblox export: XML parses successfully, the part count matches SceneIR, exactly one `SpawnLocation` exists, and no scripts are present.
- Fixture compilation: coast — 98 parts; courtyard — 148 parts; formal garden — 971 parts; park — 194 parts.

The live verification used a local ignored `OPENAI_API_KEY`; no secret is committed. The Responses API contract is also covered by a fake-transport test, while the multipart upload → analyzer → normalization → validator → compiler path is covered by integration tests.

## Current Limitations

- Stripe manual-capture code is complete, but checkout is disabled until test/live Stripe keys and a webhook secret are supplied in the deployment environment. Exercise authorization, capture, release, expiry, and refund webhooks in test mode before accepting real orders.
- The development queue adapter is in-process. Production should use a durable Active Job backend before enabling automatic Astra fulfillment.
- Generation failure remains a private operator state; refunds are reconciled from Stripe events but an operator must initiate a refund in Stripe Dashboard in this milestone.
- PostgreSQL is production-ready for relational data, while local Active Storage is suitable only for a single persistent instance. Set the existing S3 environment variables before horizontally scaling or deploying to ephemeral storage.
- OAuth controls remain disabled until provider credentials and matching callback URLs are configured.
- A single photograph cannot reveal true depth or hidden geometry. SceneFoundry preserves the recognizable composition and records assumptions, but it does not claim photogrammetric accuracy.
- This milestone builds geometry from Roblox primitives. A visually unusual object can be preserved as an editable approximate mass, but dedicated assets, `MeshPart`, terrain voxels, and textures will be required for product-grade object fidelity.
- The second pass reviews structured composition, not a rendered preview. The largest remaining quality improvement is a render-and-compare loop that lets the model correct the actual generated image.
- Astra Max is an optional quality experiment, not a guarantee of ChatGPT UI-equivalent results. The live benchmark revealed that survey-scale distant scenery could shrink the playable foreground; the vision contract now explicitly requests a compact diorama and compressed background layers. That prompt correction has not been re-run on Astra because doing so would incur another roughly $3 experiment.
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
- `app/services/roblox/map_artifact.rb` — checksummed Base64 ready-map response envelope.
- `app/services/roblox/preview_extractor.rb` — safe interactive preview extraction from an operator-delivered `.rbxlx`.
- `app/services/payments/stripe_checkout.rb` — hosted manual-capture authorization.
- `app/services/payments/order_actions.rb` — idempotent capture, decline/release, and customer cancellation actions.
- `app/services/payments/stripe_event_handler.rb` — deduplicated verified payment-state reconciliation.
- `app/jobs/generate_order_job.rb` — sole automatic paid-order generation entry point.
- `app/services/orders/generation_gate.rb` — automation, concurrency, and daily-spend guardrails.
- `app/services/orders/premium_generator.rb` — Astra-to-SceneIR-to-`.rbxlx` fulfillment pipeline.
- `frontend/src/App.tsx` — account shell and AI Lab.
- `frontend/src/OrderWorkflow.tsx` — customer and operator reserved-payment workflow.
- `frontend/src/i18n.ts` — English and French interface resources and language persistence.
- `frontend/src/SceneViewer.tsx` — interactive Three.js scene preview.
