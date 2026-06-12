# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Cel-City is a Roblox city-builder written in plain Luau, synced into Roblox Studio with Rojo (v7.6.1). There is no build step, no test runner, and no linter — testing happens manually in Studio Play mode. Deliberately out of scope (see TODO.md): no complex frameworks, no roblox-ts, no monetization, no final shop UI, no big content packs before save/economy/UI are stable.

## Developing

```
rojo serve default.project.json
```

Notes for this machine:

- `rojo` is **not on PATH** — use the full path `%LOCALAPPDATA%\rojo\rojo.exe` (`C:\Users\wirzl\AppData\Local\rojo\rojo.exe`).
- The server listens on `localhost:34872`; connect from the Rojo plugin inside Roblox Studio. Whether it is running can be checked via `http://localhost:34872/`.
- Changes sync live into Studio, but server-side services only re-run their `Init()` when Play mode is restarted.

`default.project.json` maps `src/` onto the Roblox DataModel:

| Repo path | DataModel location |
| --- | --- |
| `src/ReplicatedStorage/Shared` | `ReplicatedStorage.Shared` (+ an empty `Remotes` folder) |
| `src/ServerScriptService` | `ServerScriptService.Server` |
| `src/StarterPlayer/StarterPlayerScripts` | `StarterPlayer.StarterPlayerScripts` |
| `src/Workspace` | `Workspace` (baseplate/spawn) |

Anything outside these folders lives **only in the Studio place file** and cannot be changed from this repo — e.g. `ServerStorage.TreeModels`, `ServerStorage.BuildingModels`, and the `Lighting.Technology` setting. Flag such changes for the user instead of trying to script them.

## Workflow rules (binding)

Git rules from BRANCHES.md:

- **Never commit directly to `main`.** Work happens on `feature/<kebab-case-name>` branches created from `develop`; one branch = one feature, keep them small.
- Merge feature → `develop` when finished; **keep** the feature branch after merging (do not delete). `develop` → `main` only when multiple features are tested together.
- Commits: `type: short description` (`feat:`, `fix:`, `refactor:`, `docs:`). Multiple small commits over one big one.
- BRANCHES.md contains the planned feature-branch roadmap and build order; update README.md when the architecture changes.

Additional rules from the user:

- **TODO.md tracking:** after completing a user-approved task, mark it `[x]` in TODO.md; if it isn't listed there yet, add it to the matching section (or an `## Abgeschlossen in feature/...` section) and mark it done immediately. TODO.md is written in German with ae/ue/oe transliterations — match that style.
- Commit and push only when the user explicitly asks.

## Architecture

The game is strictly server-authoritative. The client only renders previews and sends requests; the server re-validates everything before mutating the world. Validation logic must never live only on the client.

### Entry points and lifecycle

`src/ServerScriptService/Server.server.lua` creates the RemoteEvents in `ReplicatedStorage/Remotes` (`PlaceBuilding`, `PlacementResult`), then requires each module in `Services/` and calls its `Init()`. `src/StarterPlayer/StarterPlayerScripts/Client.client.lua` does the same for `Controllers/`. New systems follow this pattern: a module table with an `Init()` function, registered in the matching entry script — services on the server, controllers on the client.

Current services: `EconomyService`, `TerrainService`, `PlacementService`, `CelShadingService`.
Current controllers: `EconomyController`, `PlacementController`, `SprintController`.

### Controls

- `B` toggles build mode, `R` rotates the preview, left-click places.
- Holding `Shift` sprints at 2x walk speed (`SprintController`, client-only; it remembers the spawn `WalkSpeed` as base so other systems can change it).

### Placement flow (the core loop)

1. `PlacementController` (client) shows a grid-snapped ghost preview and fires `PlaceBuilding` with only `buildingId`, position, and rotation.
2. `PlacementService` (server) re-snaps and validates in order, replying via `PlacementResult` with `{ Success, Reason, Cells }`. Reason strings: `InvalidBuildingId`, `InvalidPosition`, `InvalidRotation` (only 0/90/180/270), `UnknownBuilding`, `TooFar` (player must be within 80 studs), `OutOfBounds`, `Water` (analytic river/stream check **plus** terrain raycast for Water/Slate materials, since gravel banks extend past the analytic radius), `Occupied`, `NotEnoughMoney`, `Placed`.
3. On success the server clones the model from `ServerStorage.BuildingModels[ModelName]` (green placeholder Part if missing), parents it to `Workspace/PlacedBuildings`, marks the cells occupied, and only then deducts money.

Occupied cells are stored server-side as a `{ [cellKey]: boolean }` map keyed by `Grid.cellKey` (`"x:y"`). They are session-only and currently not synced to other players' previews (known TODO). `PlacementService` has a `DEBUG_GRID` flag that renders grid lines when enabled.

### Shared code

`ReplicatedStorage/Shared` is readable by both sides; client and server must use these same modules so their math agrees — but the server's result is always final.

- `Util/Grid.lua`: TileSize 4 studs, bounds −50..50 in grid cells, `worldToGrid`/`gridToWorld`/`snapToGrid`, footprint rotation (90/270 swaps X/Y), `getOccupiedCells`, `cellKey`. Has backwards-compatible PascalCase aliases (`WorldToCell` etc.).
- `Config/Buildings.lua`: building definitions — currently `House` (Cost 100, Size 2x2) and `Shop` (Cost 250, Size 3x2), each with `DisplayName` and `ModelName`.

### Economy

`EconomyService` holds session-only money in a `{ [Player]: number }` table (start: 1000, no DataStore yet), mirrored to `leaderstats/Money` (IntValue). API: `GetBalance`, `CanAfford`, `Spend`. Money is deducted only after all placement checks pass. `EconomyController` renders the money display and a red minus popup when money is spent.

### World generation (`TerrainService`)

Generates the map on every server start into `Workspace/GeneratedMap` (cleared before regeneration), with step-by-step `[TerrainService]` logs:

- Flat buildable plateau (half-size 256 studs) with its top at Y = 0, matching `Grid.gridToWorld`.
- Hill/mountain ring around it (fractal `math.noise`, fixed `SEED = 1337` so hills/river/streams are reproducible), with height-based materials (grass → dirt → rock).
- A meandering north-south river plus small streams flowing into it; both carve water with Slate gravel banks. Exposes `IsWaterArea(x, z)`, `GetGroundHeight`, `GetRiverXAt` for other systems (PlacementService uses `IsWaterArea`).
- Randomized forests (count/size/density random per start, intentionally not seeded) cloning tree models from `ServerStorage.TreeModels` with a placeholder fallback; shore pebbles and grass tufts as temporary stylized details.
- Custom terrain material colors (stylized palette set via `SetMaterialColor`).

### Cel-shading look (`CelShadingService`)

Roblox has no custom shaders, so the toon look is faked with three building blocks:

1. Flat lighting: `GlobalShadows = true`, `ShadowSoftness = 0` (hard edges), `EnvironmentDiffuseScale/SpecularScale = 0`, `Brightness = 3`, `ClockTime = 10`. **Shadow darkness is controlled by `Ambient` (currently 125,125,125) and `OutdoorAmbient` (currently 195,195,195)** — raise these to brighten shadowed areas (e.g. forests) while keeping hard edges.
2. A `ColorCorrectionEffect` (Saturation 0.3, Contrast 0.25, Brightness 0.02).
3. Cartoon outlines via `Highlight` instances attached to the `PlacedBuildings` and `GeneratedMap` folders as they appear (one Highlight per folder outlines everything inside and counts once toward the engine limit of 31 Highlights).

`Lighting.Technology` cannot be set by scripts and must be ShadowMap or Future in Studio for hard shadows to render.

### Roadmap context

TODO.md tracks the current state and next steps in detail; the next planned system is `feature/save-system` (DataStore persistence for placed buildings — `BuildingId`, grid origin, rotation — and money). After that: `feature/ui` (building selection, placement-error display). Completed so far: grid/placement prototype, economy, terrain generation, cel shading, sprint + lighting tweaks.
