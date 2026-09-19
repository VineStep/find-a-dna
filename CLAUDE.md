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
- **The place is group-owned, so `upload_image` is useless here.** It always
  uploads as the signed-in *user*, and those ids 403 with
  `assetFetchFailedNoExperienceAccess`. Reuse the verified free Creator Store ids
  already in GameConfig. `search_asset` wrongly reports `creatorType: User` for
  this place — don't trust it.
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
- Bridge/connection failure modes: `~/.claude/skills/roblox/references/connection.md`
- Accumulated Roblox findings: `~/.claude/skills/roblox/learned.md`
