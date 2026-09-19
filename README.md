# FIND A DNA

Source export of the Roblox experience **FIND A DNA** (placeId `80770322297854`).

A retro-slop pet/garden game in the *Pet Simulator × Grow a Garden* lineage. The
intended loop, as stated in `GameConfig`:

> plant → crops grow on a timer (offline too) → harvest → currency → eggs → pets
> boost yield → rebirth multiplies everything

## Current state

**This is a UI prototype.** The presentation layer is well developed; the game
underneath it is not built yet.

| Area | State |
|---|---|
| Shop panel | Full visual implementation, data-driven from config |
| Inventory panel | Full visual implementation, data-driven from config |
| HUD (tile rail, sprint, panels) | Implemented; four of six panels are empty shells |
| Sprint / stamina | Implemented client-side |
| DNA machine set dressing | Implemented (helix spin) |
| Purchases | **Not wired.** No remotes, no `MarketplaceService`, no product ids — prices are display text |
| Plant / grow / harvest | **Not implemented** |
| Currency, eggs, pets, rebirth | **Not implemented** — pets exist as inventory artwork only |
| Persistence | **None.** No DataStore code |
| Server authority | **None.** There are no server scripts in the place at all |

Everything currently in the repo runs on the client.

## Layout

Paths mirror the Roblox instance tree, so a file's location is its path in the
data model.

```
src/
  ReplicatedStorage/
    GameConfig.luau      -- every tunable number and string; the design of record
    UIKit.luau           -- panel primitives (bevel, gloss, halftone, rays, shadow, chrome)
  StarterPlayer/StarterPlayerScripts/
    HUDController.client.luau        -- the tile rail, sprint, panel open/close
    ShopController.client.luau       -- fills HUD.ShopPanel
    InventoryController.client.luau  -- fills HUD.InventoryPanel
    DnaSpin.client.luau              -- spins the helix in the extractor tank
```

`.client.luau` marks a `LocalScript`; a bare `.luau` is a `ModuleScript`. This is
the Rojo naming convention, but there is no `default.project.json` yet — the
export is currently an archive, not a live two-way sync.

## GameConfig is the design of record

`ReplicatedStorage/GameConfig.luau` holds every tunable: palettes, card
gradients, asset ids, copy, section order, the pet roster, sprint numbers.

**Adding a shop product or a pet is an edit to this file, never a GUI edit.**
Both controllers build their entire contents from it, so a new item or a whole
re-tint is a config change.

The file is heavily commented, and deliberately so: the comments record which
approaches were tried and rejected and why (asset ids that render as blobs,
sunbursts with hot centres, ribbon styles that read as extra buttons). Read them
before changing a constant — most of them are load-bearing.

## Asset id gotchas

Two traps are documented in `GameConfig` and worth repeating:

- **Creator Store page ids are not image ids.** A store page for artwork serves a
  `Decal` that *wraps* the image. Setting `ImageLabel.Image` to the store id gives
  `AssetFetchStatus.Failure`. Resolve the real id with
  `InsertService:LoadAsset(storeId)` and read the `Decal`'s `.Texture`.
- **This place is group-owned.** Images uploaded by a signed-in *user* account
  fail with `assetFetchFailedNoExperienceAccess` regardless of permissions on the
  asset itself. Every id in the config is a free Creator Store asset already
  verified to preload successfully here — reuse those before hunting new ones.

## Re-importing into Studio

There is no sync tool wired up. To push a file back, paste its contents into the
matching instance's `Source`, or use an MCP `multi_edit` against the dot-notation
path (`game.ReplicatedStorage.GameConfig`).

Note that `execute_luau` cannot *create* or reparent script instances in this
place — `ReplicatedStorage` has restricted `Capabilities` — so new scripts must be
created via `multi_edit`, which uses a privileged path.

## The world

`tree/` holds a text dump of the non-script contents — Workspace, StarterGui,
ServerStorage, Lighting — one JSON file per service, one instance per line, so
changes to the built world show up in `git diff`.

See `tree/README.md` for the field reference and, more importantly, the limits:
**it cannot rebuild the place.** Union geometry, mesh data and terrain are not
reachable from any script API, so the `.rbxl` place file remains the only
complete snapshot. It is binary and currently excluded by `.gitignore`.

## Not in this repo

The `.rbxl` place file itself. `Workspace.Bannthemann` (a test avatar left in the
world) and its stock `Animate` script were excluded as not being game content.
