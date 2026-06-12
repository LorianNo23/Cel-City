# feature/buildings-pack-01

## Goal

Add a small prototype building picker and make the restored building models placeable without changing terrain generation.

## Constraints

- Keep TerrainService unchanged unless placement absolutely requires a small compatibility fix.
- Work in small commits so each step can be inspected or reverted independently.
- Prefer existing placement, grid, economy, and save-service patterns.

## TODO

- [x] Create this temporary feature checklist.
- [x] Wire the restored GLB assets into the Roblox project as server building models.
- [x] Add building config entries for the asset-backed house and shop.
- [x] Add a small prototype client GUI to select the active building.
- [x] Verify placement requests still use existing server validation.
- [ ] Run available checks or lightweight validation.
