# Springer Park: open-data neighbourhood study

Public route: `/?case=springer-park`. This case is available without an account in English and French, with overview, source plan, closer view, on-demand interactive geometry, a downloadable Roblox place, and a captioned 60-second video.

## Honest scope

This is an operator-built example, not a customer order or live AI generation. The photo-order product remains a separate manual-first beta. The standard $19 authorization does not include a district-scale reconstruction.

The 440 × 290 metre study contains 20 OSM building footprints, 145 decorative trees and 5,682 editable parts. Five buildings have estimated floor counts. Heights, facades, landscaping and paths are approximate. No Google photos, map tiles, Street View, customer files or third-party textures were used for this rebuild.

## Sources and reproduction

Map data © OpenStreetMap contributors, ODbL 1.0. The source and derived database are published in `frontend/public/cases/springer-park/`, along with the licence and persistent in-game attribution. Preserve attribution and review ODbL obligations when redistributing adaptations.

```sh
python3 scripts/build_neighbourhood_case.py
bundle exec rails runner scripts/export_neighbourhood_case.rb
bin/verify
```

The builder reads the checked-in sanitized `source.json`; no network access is needed to rebuild. The initial import used the official OSM map API and discards contributor account metadata. Facades and planting are procedural. The preview and `.rbxlx` share `scene.json`, and export uses the application's existing trusted serializer. Export contains no scripts or external assets.

Three.js uses instanced geometry to reduce draw calls. Static imagery is available before loading the interactive 3D chunk. Local authoring mode offers a PNG export button; it is excluded from production.

## Evidence still needed

- Open this exact `.rbxlx` in Roblox Studio; check import warnings and the attribution HUD.
- Run Play: spawn, collisions, stairs/curbs, map boundaries and pedestrian routes.
- Measure desktop and mobile performance; decide a part/draw-call budget and add streaming/LOD if necessary.
- Confirm export after editing and publish a private test experience before calling it game-ready.

The walkthrough is a screenshot-based presentation with English captions and no audio. It shows actual beta UI and the case renderer, not a recording from Roblox Studio or evidence of a successful paid order.
