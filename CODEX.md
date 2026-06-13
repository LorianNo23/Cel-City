# CODEX.md

This is the shared project guide for human developers and AI coding agents working on Cel-City. Read it before changing code.

## Project Snapshot

Cel-City is a Roblox city-builder prototype written in plain Luau and synced into Roblox Studio with Rojo 7.6.1.

The project deliberately stays small:

- No roblox-ts.
- No large framework layer.
- No monetization work.
- No final shop/UI polish before core systems are stable.
- Manual Studio Play testing is the real integration test.

Current core systems:

- Grid-based building placement.
- Server-authoritative placement validation.
- Session economy with money UI.
- SaveService data shape and restore flow, with DataStore disabled by default.
- Procedural terrain with random seed, river, streams, meadow rises, pond, forests, grass details, and cel-shading setup.
- Prototype building picker and imported building models.

## Required Workflow

Follow `BRANCHES.md`.

- Never commit directly to `main`.
- Work on `feature/<kebab-case-name>` branches created from `develop`.
- One branch should represent one coherent feature or fix group.
- Keep commits small and focused.
- Commit messages use `type: short description`, for example `feat: add grid system`, `fix: reject invalid placement`, `docs: update project guide`.
- Merge finished feature branches into `develop`, but do not delete the feature branch.
- Push only when the user explicitly asks.
- If local changes are present, identify whether they are yours before editing nearby files. Do not revert user work.

TODO tracking is mandatory:

- `TODO.md` is the source of planned work and completed task tracking.
- It is written in German with `ae/ue/oe` transliterations. Match that style.
- When completing a user-approved task, mark the matching TODO item `[x]`.
- If no item exists, add it to the matching section or to an `Abgeschlossen in feature/...` section and mark it done.

## Local Development

Start Rojo:

```powershell
& 'C:\Program Files\Rojo\rojo.exe' serve default.project.json
```

Notes:

- `rojo` may not be on PATH. On this machine, use `C:\Program Files\Rojo\rojo.exe`.
- The Rojo server listens on `localhost:34872`.
- Connect from the Rojo plugin in Roblox Studio.
- Server-side services only re-run `Init()` after restarting Play mode.
- There is no automated test runner or linter.

Useful validation command:

```powershell
& 'C:\Program Files\Rojo\rojo.exe' build default.project.json -o C:\tmp\cel-city-check.rbxlx
```

Run this after meaningful Luau/Rojo mapping changes when possible.

## Rojo Mapping

`default.project.json` maps these folders into the Roblox DataModel:

| Repo path | Roblox location | Notes |
| --- | --- | --- |
| `src/ReplicatedStorage` | `ReplicatedStorage` | Shared modules and `Remotes` metadata. |
| `assets/models` | `ServerStorage.BuildingModels` | Imported building assets used by server placement. |
| `src/ServerScriptService` | `ServerScriptService` | Server entry script and services. |
| `src/StarterPlayer/StarterPlayerScripts` | `StarterPlayer.StarterPlayerScripts` | Client entry script and controllers. |
| `src/Workspace` | `Workspace` | Static workspace folders such as `PlacedBuildings`. |

Assets or settings outside this mapping live only in the Studio place file unless explicitly added to Rojo. Examples: `ServerStorage.TreeModels` and `Lighting.Technology`.

## Architecture Rules

The game is server-authoritative.

- The client may preview, select, and request.
- The server validates and mutates world state.
- Validation must never exist only on the client.
- Shared math belongs in `ReplicatedStorage.Shared`.
- Server-only ownership stays in services under `ServerScriptService.Services`.
- Client-only UI and input stay in controllers under `StarterPlayerScripts.Controllers`.

New systems should follow the existing lifecycle:

- Server: module table with `Init()`, required and started from `Server.server.lua`.
- Client: module table with `Init()`, required and started from `Client.client.lua`.

Current services:

- `TerrainService`
- `PlacementService`
- `SaveService`
- `EconomyService`
- `CelShadingService`

Current controllers:

- `PlacementController`
- `EconomyController`
- `SprintController`

## Shared Modules

`ReplicatedStorage.Shared.Util.Grid`

- `TileSize = 4`.
- Bounds are `MinX..MaxX` and `MinY..MaxY`.
- Converts between world positions and grid cells.
- Computes building footprints and rotated footprints.
- Provides `cellKey(cell)` for occupied-cell maps.

`ReplicatedStorage.Shared.Config.Buildings`

- Defines server-validated building IDs.
- Current IDs: `House`, `Shop`.
- Both use imported models from `ServerStorage.BuildingModels`.
- Both currently use a `2x2` grid footprint.

## Placement System

Client flow:

- `B` toggles build mode.
- `R` rotates preview by 90 degrees.
- Left-click requests placement.
- The prototype GUI selects `House` or `Shop`.
- The client sends only `buildingId`, requested position, and rotation.

Server flow:

1. Re-snap requested position to grid.
2. Validate building ID, position type, rotation, distance to player, grid bounds.
3. Reject water, gravel banks, pond/shore, meadow tree blockers, pond plant blockers, and too-uneven ground.
4. Reject occupied cells.
5. Check money.
6. Clone the server model or placeholder.
7. Remove blocking grass tufts from the footprint.
8. Parent the building under `Workspace.PlacedBuildings`.
9. Mark cells occupied.
10. Spend money and update session save data.

`PlacementResult.Reason` values currently include:

- `InvalidBuildingId`
- `InvalidPosition`
- `InvalidRotation`
- `UnknownBuilding`
- `TooFar`
- `OutOfBounds`
- `Water`
- `Tree`
- `Slope`
- `Occupied`
- `NotEnoughMoney`
- `Placed`

Important limitation:

- Occupied cells are session-only and not yet synced to other players' previews.
- Terrain flattening under buildings is not implemented yet. See the special TODO about unified build height and platform shaping.

## Terrain System

`TerrainService` generates the map on server start and clears prior generated terrain/details.

Current generation:

- Random active seed per server start, with `FIXED_SEED` available in code for reproducibility.
- `GetSeed()` exposes the active seed for future SaveService persistence.
- Flat buildable plateau with procedural meadow rises.
- Meandering river and streams with water plus Slate banks.
- Pond in the largest meadow compartment, with dirt shore and cattail-style plants.
- One smaller meadow compartment with loose forest.
- Hill-ring forests and stylized grass tufts.
- Custom terrain material colors.

Public terrain APIs used by other systems:

- `GetSeed()`
- `GetGroundHeight(x, z)`
- `GetRiverXAt(z)`
- `IsWaterArea(x, z)`
- `IsTreeArea(x, z, clearance)`

When changing terrain:

- Keep generation deterministic for a fixed seed unless intentionally using unseeded decorative randomness.
- Do not let water overlap meadow rises.
- Keep placement blockers in sync with generated features.
- Restart Studio Play mode after service changes.
- Prefer small, inspectable changes over large terrain rewrites.

## Save System

`SaveService` owns the intended persisted data shape:

- `Money`
- placed buildings with `BuildingId`, `OriginX`, `OriginY`, `Rotation`

DataStore access is currently disabled:

```lua
local DATASTORE_ENABLED = false
```

Session data and restore flow exist. Before enabling DataStore, the terrain seed must be persisted and restored, otherwise saved buildings may reload into a newly generated river, pond, forest, or hill.

## Economy System

`EconomyService` manages session money.

- Players start with `1000`.
- Balance is mirrored to `leaderstats/Money`.
- Money is spent only after every placement validation passes.
- `EconomyController` renders the money UI and spend popup.

## Visual Style

`CelShadingService` approximates a toon/cel-shaded look:

- Hard shadows through lighting settings.
- Color correction for stylized contrast/saturation.
- `Highlight` outlines for `PlacedBuildings` and `GeneratedMap`.

Roblox `Lighting.Technology` cannot be set reliably from scripts. Set it in Studio if hard-shadow behavior changes.

## Current Priorities

Use `TODO.md` as the live source, but the current high-priority areas are:

- Finish `feature/random-world-seed` terrain/placement followups.
- Persist terrain seed before enabling DataStore.
- Improve placement feedback and delete workflow.
- Keep building/terrain alignment clean, especially the planned unified build-height platform.
- Avoid expanding content packs before save/economy/UI behavior is stable.

## Coding Guidelines

- Plain Luau only.
- Prefer existing services/controllers/config modules over new abstractions.
- Keep client and server math shared when it affects placement.
- Keep server validation authoritative.
- Avoid hidden Studio-only assumptions unless documented.
- Add comments only where they clarify non-obvious terrain, save, or placement behavior.
- Do not use broad refactors while fixing a narrow gameplay issue.
- Update `CODEX.md`, `README.md`, or `TODO.md` when behavior, architecture, or workflow changes.

## AI Agent Checklist

Before work:

- Check current branch and `git status`.
- Read `CODEX.md`, `TODO.md`, and relevant source files.
- Pull when the user asks or when branch freshness matters.
- Identify uncommitted changes and avoid overwriting them.

During work:

- Make the smallest change that satisfies the task.
- Keep commits focused when committing is requested.
- Keep TODO state accurate.
- Validate with Rojo build when code or mapping changes.

Before final response:

- Report changed files and commit hashes if commits were made.
- Report validation performed or why it was not run.
- Mention uncommitted changes clearly.
