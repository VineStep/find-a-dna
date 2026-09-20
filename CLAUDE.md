# FIND A DNA — working notes

Roblox experience, placeId `80770322297854`, **group-owned** (group 155271859).
Retro-slop pet/garden game: *Pet Simulator × Grow a Garden*.

This file is the operational knowledge. `README.md` is the public description of
the project; `tree/README.md` covers the world dump's fields and limits.

## The one thing to know first

**There is exactly ONE server script, and it is not the game.**
`ServerScriptService.AdminService` was the first ever added here; it exists
because global messages and an admin check cannot be done on a client at all.
Everything else is still client-only: no economy, no persistence, no purchase
wiring, and the plant/grow/harvest loop named in GameConfig's own header does not
exist. The UI is far ahead of the game.

Anything that grants, spends, rolls or saves still has to be built server-side
first — AdminService is the pattern to copy (remotes created in code, admin
re-checked on every request, nothing trusted from the client), not a foundation
that already carries any of it.

## Layout

```
tools/          # one-offs, not part of the game (build-hud-furniture)
src/            # scripts, mirroring the instance tree (Rojo naming)
  ReplicatedStorage/GameConfig.luau   # the design of record
  ReplicatedStorage/UIKit.luau        # panel primitives
  ServerScriptService/*.server.luau   # AdminService, and so far only that
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
- **For AUDIO the store page id works verbatim** — the opposite of the rule
  above, because audio has no Decal wrapper. All three music ids were set
  straight onto a `Sound` and reported `IsLoaded` with a real `TimeLength`
  (205s / 211s / 322s). Store audio needs no experience grant either; that is
  only for user uploads.
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
  than its neighbours. The group carries the diagonal rotation.
  A `CanvasGroup` does **not** isolate its children from `ZIndexBehavior.Global`
  — give them the group's own ZIndex band or they sort below the panel and never
  draw. Two consequences of that hoisting, both verified by capture:
  **`GroupTransparency` is inert** (set to 1 on all eighteen scribbles, every one
  still drew — so `SCRIBBLE_FADE` has never done anything; the light rarity
  colour is what you see, and the real lever is the bar colour), and
  **an ancestor's `ClipsDescendants` does not clip it** — scribbles from rows
  above and below the inventory scroll drew outside the panel, over the 3D world,
  while pets and numbers clipped correctly. Worst on phones, where a narrow
  viewport always leaves rows off both edges. `Visible` **is** respected, so
  `InventoryController.cullScribbles` hides any scribble whose slot is not
  wholly inside the scroll window; it walks `shelf` and `grid`, the container
  frames, not `shelfGrid`, which is the layout and has no children.
  The scribble uses the **light** end of the rarity pair, and since there is no
  working fade on top of it, that colour is the whole result — the dark end sat
  as heavy behind the pet as the pet itself.
- **Pets are still, near head-on, and outlined.** No idle sway — eighteen pets
  drifting is motion competing with the grid. The outline is the same model
  rendered a second time, flat dark, in a viewport scaled 1.06 behind the real
  one: `Highlight` does not render inside a `ViewportFrame` at all (verified),
  and `UIStroke` would outline the rectangle. **Stamped, not scaled** — four flat
  copies offset on each axis. Scaling offsets every edge radially from the image
  centre, which is fat far from centre, absent near it, and shows the dark copy's
  own depth through the gaps; that is the "3D outline" look and no scale factor
  fixes it. The pet's holder is square so the contour is not elliptical.
- **Shop borrows.** `UIKit` exports the shop's whole design language —
  `halftone`, `rays`, `castShadow`, `bevel`, `gloss`. The inventory panel carries
  the shop's own halftone sheet (much fainter: a card is 272px of saturated
  colour that the dots must fight, a pale panel is not), and the rail cells and
  the `+` key are built from the same `bevel` + `gloss` pair its cards use.
  `rays` is available and unused here — the scribble already occupies that slot.
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
  lie. Size matters for opaque overlays too: `UIKit.gloss` at `frac 0.5` reads
  correct on a 130px pill and turns a 65px key white, because the sheet is
  opaque and owns half of whatever it is on.
- **Studio's Edit viewport does not run LocalScripts.** Any GUI a controller
  builds at runtime simply is not there while you author the place. The only fix
  is real instances in StarterGui that the controller adopts.
- **`execute_luau` can `loadstring`** even though `ServerScriptService
  .LoadStringEnabled` is not exposed to it (reading that property errors). So a
  long one-off can be fetched over HTTP and run rather than pasted into the call:
  `HttpEnabled = true`, `RequestAsync`, `loadstring(body)()`, restore. That is how
  `tools/build-hud-furniture.luau` was applied — served from the repo ROOT on
  **8744**, since 8742 is rooted at `src/`.
- **A UIGridLayout cell sized to the whole grid assumes ONE row.** The teleport
  panel's cell height was `math.floor(h)`, correct for four places in a row and
  overflowing by a whole card top and bottom the moment a fifth wrapped. Divide by
  the row count, and give the panel a shape that fits them: `ROW_ASPECT` carries
  1.62 for one row and 1.02 for two, because squashing the cards to fit a
  letterbox panel is what stops them looking like the shop's cards.
- **A currency counter must not be a rounded gradient pill.** Icon at one end,
  number at the other, and a gap between them is a progress bar — narrowing it
  did not help. The HUD counters are artwork plus outlined type on nothing, the
  same treatment as the power number, the xN badge and the shop's ribbons.

## Admin

A **crown key in the top-right**, or `F2`, opens `HUD.AdminPanel` — global
message, fly, walk speed, time of day. Not a seventh HUD tile: that grid is a
full 2x3, a seventh cell reflows it for every player, and it would be carrying a
control almost nobody can open. The key is built at runtime *below* the admin
check, so a non-admin is never sent it — which also keeps it out of the Edit
viewport. It is what gives touch admins a way in at all, since there is no F2 on
a phone.

Its Y is set in **pixels off `GuiService:GetGuiInset()`**, not as a scale: the HUD
sets `IgnoreGuiInset`, so its local space starts ~36-58px above the visible
screen and a scale of 0.075 put the key 2px from the top of the display — under
the topbar on desktop, in the notch on a phone. Same trap `placeHeader`
documents.

**The panel's shell IS StarterGui furniture now**, and so are the HUD currency
counters — `tools/build-hud-furniture.luau` creates both. They have to be real
instances to be visible in Studio's own Edit viewport, which does not run
LocalScripts: anything a controller builds at runtime is invisible while you are
authoring the place. Both controllers **adopt** what they find (a local `ensure`
find-or-create) and still compute every size and position themselves, so the tree
only carries the shape — its static values are approximations that are overwritten
in Play, and the comments in the builder say so where they differ (a UDim2 X scale
is a fraction of the parent's WIDTH, which is not what a figure expressed in row
HEIGHTS means).

The cost is that StarterGui replicates to everyone, so **`AdminController`
destroys `hud.AdminPanel` outright on a non-admin client** rather than trusting
`Visible = false`. The server refuses every request regardless; that destroy is
the second lock, not the only one. Admin row plates are rebuilt each run, so the
controller clears `Rows` first or the list stacks two of each.

Building a shell by hand means supplying what `UIKit.chrome` re-colours rather
than creates: the `Scale`,
`Shadow` (with its own `UICorner`), aspect constraint, corner, `UIStroke`,
`Title` + its stroke, and a `CloseButton` carrying a `UIScale`, a `UICorner`,
**a `UIStroke` and a `UIGradient`**. Those last two are the ones that are easy to
miss; chrome dies part-built on `s.Color` and then `g.Rotation` without them.
Everything else it reaches for (`TitleIcon`, `Glyph`, `Lip`, `Studs`, `Rule`,
`Body`) it creates on demand or skips.

Admin is decided by `AdminService` only — UserId list **or** rank in the owning
group (>= `MinGroupRank`) — and re-checked on every request. Verified by
de-adminning the config and firing the remotes by hand: no panel, no broadcast,
no speed change, no time change. The message feed is built for **everybody**; a
global message only admins can see is not a global message.

The title runs `UIKit.rainbow(kit.title, panel)` — a travelling gradient gated on
the panel so it is not driving a 30Hz loop for a closed screen. The label must be
WHITE underneath, since a `UIGradient` multiplies what is under it. It honours
`ReduceMotion`. (`DailyController` still carries its own verbatim copy, the same
call the UIKit header makes about `ShopController`.)

The global message icon is **the sender's avatar head**, not an asset: the payload
carries the UserId, so the client fetches `GetUserThumbnailAsync(HeadShot)`. That
yields, so it is fetched in a `task.spawn` and the crown is the fallback for a
brand-new account with no rendered avatar. Round via the ImageLabel's own
`UICorner` — `ClipsDescendants` would not do it, as it ignores `UICorner`.

**Time of day is global in both senses.** `AdminService` sets `Lighting.ClockTime`
from real-world **UTC** every 30s, so every player in every server sees the same
sky as each other and as the actual hour. `os.date("!*t")`, not `"*t"` — Roblox
servers run wherever Roblox puts them, and the local zone would give a different
sky per datacentre, which is the one thing this must not do. An admin pressing
Dawn/Noon/Night **pins** it; `Live` hands it back. Without `Live` there is no way
to undo a pin short of restarting the server.

`hud:GetAttribute("OpenPanel")` is now the name of whichever of the six HUD panels
is open, or nil, and `HUDOpenPanel:Invoke(nil, false)` closes whatever is up.
Both exist so the admin panel and the HUD's own six cannot both be on screen —
the daily auto-opens at join and F2 went straight through it.

Fly is client-side and honest about it: Roblox gives the client network ownership
of its own character, so an exploiter can fly in any experience regardless. What
is gated is the panel and everything that reaches other players. Direction comes
from `Humanoid.MoveDirection`, not from reading WASD, which is the one line that
makes it work on a thumbstick too.

## Sound

`MusicController.client.luau` plays one looping track per zone from
`GameConfig.Music`, crossfading on change. Zones are **world-space boxes, first
match wins**, so a region inside another is listed first — the `mineshaft` plate
sits inside the cave enclosure and therefore comes before it. The numbers are
measured off the place, not chosen; the comment in `GameConfig.Music` records
which geometry each came from. Everything outside every box gets `Default`.
Tracks are never stopped and restarted, only faded, so re-entering a zone rejoins
its track where it was.

**Music lives in its own `Music` SoundGroup, and must.** `SettingsController`
adopts sounds under `SoundService` into `UISfx` so the SFX slider governs them,
`ChildAdded` included — unguarded, that silenced the music within a frame. It now
adopts only sounds with **no** group of their own (UIKit creates its sounds
groupless, so nothing changed for the UI: all 9 still land in `UISfx`). There is
no music slider yet; the group is the seam for one.

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
