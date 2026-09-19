# FIND A DNA — working notes

Roblox experience, placeId `80770322297854`, **group-owned** (group 155271859).
Retro-slop pet/garden game: *Pet Simulator × Grow a Garden*.

This file is the operational knowledge. `README.md` is the public description of
the project; `tree/README.md` covers the world dump's fields and limits.

## The one thing to know first

**There are no server scripts in the place.** Not thin — zero. Shop and inventory
look finished, but nothing behind them is authoritative: no economy, no
persistence, no purchase wiring, and the plant/grow/harvest loop named in
GameConfig's own header does not exist. The UI is far ahead of the game.

Anything that grants, spends, rolls or saves has to be built server-side first.

## Layout

```
src/            # scripts, mirroring the instance tree (Rojo naming)
  ReplicatedStorage/GameConfig.luau   # the design of record
  ReplicatedStorage/UIKit.luau        # panel primitives
  StarterPlayer/StarterPlayerScripts/*.client.luau
tree/           # JSON dump of non-script instances, one per line
```

`.client.luau` = LocalScript, bare `.luau` = ModuleScript. There is no
`default.project.json`, so this is a one-way archive, not a live Rojo sync.

## GameConfig is the design of record

Every tunable lives in `ReplicatedStorage/GameConfig.luau`: palettes, gradients,
asset ids, copy, section order, pet roster, sprint numbers. Both controllers
build their whole contents from it.

**Adding a product or a pet is an edit to that file, never a GUI edit.**

Its comments record what was tried and rejected and why. They are load-bearing —
read before changing a constant. Owned by rblx-orchestrator; other agents read.

## Studio traps (all learned the hard way here)

- **`execute_luau` cannot create or reparent script instances.**
  `ReplicatedStorage` has restricted `Capabilities`, so parenting a
  Script/LocalScript/ModuleScript fails — it checks descendants too, so a Folder
  containing one is refused. Use `multi_edit` (privileged path) to create;
  `execute_luau` can then set `.Source` on the existing script.
- **`datamodel_type` is capitalised** — `Edit` / `Client` / `Server`. Lowercase
  is rejected.
- **Creator Store page ids are not image ids.** A store page serves a `Decal`
  wrapping the image; `ImageLabel.Image = storeId` gives
  `AssetFetchStatus.Failure`. Resolve with `InsertService:LoadAsset(storeId)` and
  read the Decal's `.Texture`.
- **`store_image` is not an upload.** It returns an `IMAGEID_<id>` URI for the
  generation tools only; it cannot produce an `rbxassetid` for an `ImageLabel`.
  There is no way around the grant below.
- **The place is group-owned, so `upload_image` is useless here.** It always
  uploads as the signed-in *user*, and those ids 403 with
  `assetFetchFailedNoExperienceAccess`. Reuse the verified free Creator Store ids
  already in GameConfig. `search_asset` wrongly reports `creatorType: User` for
  this place — don't trust it.
- **Pets float; they do not sit on tiles.** The inventory's pets have no plate,
  no ink outline and no gloss — just a **procedural scribble** in the rarity
  colour behind them, on a plain white panel. The scribble is drawn from ~11
  tilted rounded bars (`makeScribble`, built once per rarity and cloned) because
  it cannot be fetched: `search_asset` returns only Models for any texture query,
  uploads 403, and `generate_texture` needs a mesh selection. A soft-edged circle
  image was tried here and rejected — a clean circle is a dot, not a scribble.
  The bars are **opaque inside a `CanvasGroup`**, not semi-transparent:
  overlapping translucent frames compound, and every crossing came out darker
  than its neighbours. The group carries the fade and the diagonal rotation.
  A `CanvasGroup` does **not** isolate its children from `ZIndexBehavior.Global`
  — give them the group's own ZIndex band or they sort below the panel and never
  draw. Colour and fade move together: the scribble uses the **light** end of the
  rarity pair, so the fade has to come down with it or it composites to white.
- **Pets are still, near head-on, and outlined.** No idle sway — eighteen pets
  drifting is motion competing with the grid. The outline is the same model
  rendered a second time, flat dark, in a viewport scaled 1.06 behind the real
  one: `Highlight` does not render inside a `ViewportFrame` at all (verified),
  and `UIStroke` would outline the rectangle.
- **The header has no sort control.** A POWER / A-Z pill sat between the title
  and the search field and read as clutter however it was styled. The order it
  chose is now the only order (power descending). Restoring it means putting a
  `Sorts` table back in `GameConfig.Inventory`; nothing else reads `sortKey`.
- **No rail cell is drawn as selected.** All six are inert, and a highlight on
  one of them promised navigation the panel does not have. It comes back when a
  cell can actually change what the grid shows. An earlier pass gave each one a bevelled shop-style tile
  and `InventoryPanel` the standard studded sheet; both were rejected — eight
  saturated plates in a row is a wall of colour and the pet stops being the
  subject. `HUDController.STUDS_OVERRIDE` carries `InventoryPanel = { Skip = true }`.
- **Pet art is a `ViewportFrame` of the real model, not a 2D icon.** That is the
  way around the upload block: `ReplicatedStorage.PetModels` holds six rigged
  pets cloned from `Workspace.Pets` (`Chicken`, `Dog`, `Cat`, `Scorpion`,
  `Bigfoot`, `ghostly`), and a pet entry names one in `Model`. All six face
  **-Z**; a pet whose model faces elsewhere sets `Yaw` (degrees about Y) rather
  than getting its own camera. A viewport ignores the place's Lighting and starts
  near black, so it sets its own `Ambient`. Do not `PivotTo` a staged model —
  framing is world-space off `GetBoundingBox()`, and resetting the pivot tips
  upright rigs onto their backs.
- **ContentProvider caches asset failures for the whole session.** After granting
  access, a re-probe still returns Failure with no network request. Only a Studio
  restart clears it.
- **`ClipsDescendants` ignores `UICorner`** — the clip region is always the
  rectangle. Prefer sizing an image 1:1 with `ScaleType.Crop` over clipping it.
- **Judge GUI textures at 1:1, never on a magnified clone.** Pixel-offset
  children and UIStroke don't scale with the clone, so corners and opacity both
  lie.

## Exporting from Studio

Pulling `.Source` through `execute_luau` dumps every byte into the model's
context (~45K tokens for this place). Instead:

1. Run a small HTTP receiver on localhost that writes POST bodies to paths.
2. `HttpService.HttpEnabled` defaults to **false** — set it `true` from
   `execute_luau`, export, then **restore it to false**. It is a persisted place
   setting.
3. One `execute_luau` loops instances and POSTs to `http://127.0.0.1:PORT/...`.
   The Vinegar flatpak shares the host network namespace, so localhost resolves.

`GetDescendants()` includes `Workspace.Bannthemann` — a test avatar, two copies,
240 instances of stock rig. Exclude it; it is not game content.

## Pushing source back INTO Studio

The same trick in reverse, and worth setting up the moment you expect more than
one edit round — `multi_edit` needs an exact `old_string` per change, and a
restyling pass is a dozen of them.

```
cd src && python3 -m http.server 8742 --bind 127.0.0.1 &
```

Then one `execute_luau` per round: set `HttpEnabled = true`, `RequestAsync` each
file from `http://127.0.0.1:8742/<path under src>`, assign `.Source`, restore
`HttpEnabled`. The repo is then the source of truth and Studio is the mirror —
check byte counts against `wc -c` after every push.

Port **8731 is already taken** by the POST receiver from the export side, which
answers `GET` with `501`. Pick another.

## What cannot be exported as text

`tree/` records structure, not geometry. **It cannot rebuild the place.**

- `UnionOperation` shapes are unreachable from any script API — only the bounding
  box survives. 30 of them in Workspace.
- Meshes and textures are asset ids, not data.
- Weld/constraint wiring and terrain don't survive.

The `.rbxl` place file is the only complete snapshot (Studio: File → Save to
File As). Save into `~/Documents` — the Vinegar sandbox cannot see `~/Downloads`.
It is currently gitignored, and the repo is **public**.

## Agents

`rblx-orchestrator` (lead, owns GameConfig and the Studio session),
`rblx-scripter` (server/shared Luau), `rblx-frontend` (GUI, client feel),
`rblx-builder` (Workspace, assets), `rblx-tester` (QA, modifies nothing).

Studio access is serial — one agent in the place at a time.

## Elsewhere

- Repo: <https://github.com/VineStep/find-a-dna> (public)
- Notion: "FIND A DNA — Roblox Game" + its task database (14 tasks, 4 P0
  blockers, all gated on standing up a server)
- ui-resources.com: the catalogue IS enumerable — its Supabase URL, anon key and
  `resources` table are in `/js/Rresourcespage.js`, and `download_url` serves raw
  PNGs. 400 rows; no scribble and no soft-shadow image in the whole set. Every
  image from it still needs the experience-access grant below.
- Bridge/connection failure modes: `~/.claude/skills/roblox/references/connection.md`
- Accumulated Roblox findings: `~/.claude/skills/roblox/learned.md`
