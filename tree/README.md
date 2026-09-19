# Instance tree dump

A text snapshot of the non-script contents of the place, exported from Studio.
One JSON file per service, one instance per line, keys sorted — so `git diff`
shows exactly which instance changed and how.

| file | instances |
| --- | --- |
| `Workspace.json` | 3156 |
| `ServerStorage.json` | 272 |
| `StarterGui.json` | 226 |
| `Lighting.json` | 6 |
| `StarterPlayer.json` | 2 |

## What each record holds

`path`, `class`, `name` always. Then whichever of these the instance actually has:

- **BaseParts** — `pos`, `rot` (degrees), `size`, `Color`, `Material`,
  `Transparency`, `Anchored`, `CanCollide`, `Shape`
- **MeshParts** — `MeshId`, `TextureID`
- **GuiObjects** — `udimPos` / `udimSize` as `[scale, offset, scale, offset]`,
  `anchor`, `ZIndex`, `Visible`, `ClipsDescendants`
- **Text / Image** — `Text`, `TextSize`, `Font`, `TextColor3`, `Image`,
  `ImageColor3`, `ScaleType`, `ImageTransparency`
- **Modifiers** — `CornerRadius`, `Thickness`, `AspectRatio`, layout properties
- **Lights / Sounds / Values** — `Brightness`, `Range`, `SoundId`, `Volume`, `Value`

## What this is NOT

**This cannot rebuild the place.** It is a reviewable record, not a backup:

- **`UnionOperation` geometry is absent.** 30 unions in Workspace carry a
  `note` field saying so. Solid-modelling results are not reachable from any
  script API — their shape exists only inside the place file.
- **Meshes and textures are ids, not data.** The assets live on Roblox.
- **Welds, constraints and joint wiring** are recorded as instances but their
  attachment relationships are not fully reconstructable from these fields.
- **No terrain.**

For a complete, re-openable snapshot you need the `.rbxl` place file itself,
saved from Studio (File → Save to File As). That is binary and is currently
excluded by `.gitignore`.

## Excluded

`Workspace.Bannthemann` — two copies of a test avatar left in the world, 240
instances of stock character rig, not game content.
