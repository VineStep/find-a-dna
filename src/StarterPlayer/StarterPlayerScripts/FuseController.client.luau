--[[
	FuseController — the DNA machine: what it looks like when you are near it, the
	overlay it opens, and the splice cutscene.

	SIX THINGS, and they are separable on purpose:

	  1. THE WORLD BITS    a folder for the prompt's anchor and the cutscene's
	                       two flying helices.
	  2. THE BORDER        a Highlight on the model — the only selection mark.
	  3. THE MONITOR       a SurfaceGui replacing the machine's dead 3D text.
	  4. THE PROMPT        a real ProximityPrompt with Style = Custom, drawn by us
	                       as a billboard in the panel language.
	  5. THE OVERLAY       two circular slots, an animal picker and SPLICE — with
	                       NO panel under them.
	  6. THE CUTSCENE      camera, gravity rig, two helices becoming one, white-out.

	THE BORDER AND THE PROMPT HAVE DIFFERENT RANGES. The prompt plate hangs off
	Roblox's own PromptShown/PromptHidden — right for "close enough to press". The
	border gets its own, much longer radius (Select.ShowDistance) on a throttled
	poll, because a border that only appears once you are already walking into the
	machine is telling you where it is at the one moment you can already see it. Rolling that by
	hand would be a RunService loop reimplementing the arbitration, gamepad
	handling and touch button a ProximityPrompt already has — Custom only takes
	away the default grey pill, which is the one part of it that does not belong in
	this game.

	CLIENT-ONLY, and honest about it. Every instance here is created on the client,
	so nothing replicates: the Highlight, the prompt and the whole cutscene happen
	in this player's world and nobody else's. SPLICE grants nothing, because
	granting needs a server and this game has one server script.
	The seam is `resultFor` and nothing else — the day it becomes a RemoteFunction
	call, no other line in this file moves.

	THE GRAVITY RIG (Workspace.Gravity) ships switched ON, which is why the machine
	has always had a column of sparks standing in it doing nothing. It is switched
	OFF at join here and only runs for the length of a splice.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local WorldPrompt = require(ReplicatedStorage:WaitForChild("WorldPrompt"))

local FUSE = CONFIG.Fuse
if not FUSE then
	warn("FuseController: GameConfig.Fuse is missing — nothing to build.")
	return
end

local P = CONFIG.Shop.Palette
local INV = CONFIG.Inventory
local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local SEL = FUSE.Select or {}
local PROMPT = FUSE.Prompt or {}
local PANEL = FUSE.Panel or {}
local DISPLAY = FUSE.Display or {}
local CUT = FUSE.Cutscene or {}
local CLICK_CFG = FUSE.Click or {}

-- Assigned once the overlay exists; the plate's OnActivate closes over it, and
-- the plate is built before the overlay because the overlay is the longer half.
local openScreen

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")

--=============================================================== THE MACHINE

local machine = workspace:WaitForChild(FUSE.ModelName, 30)
if not machine then
	warn(("FuseController: no Workspace.%s — the machine is not in this place.")
		:format(tostring(FUSE.ModelName)))
	return
end

-- Model:GetBoundingBox returns an ORIENTED box in the model's own pivot frame,
-- and this model's pivot is rotated a quarter turn — its "size" comes back with
-- the axes swapped, which put the dotted rectangle across the machine rather than
-- round it. The world axis-aligned box has to be computed, by projecting each
-- part's half-extents onto the world axes.
local function worldBox(model)
	local mn, mx
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local h = Vector3.new(
				math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2,
				math.abs(r.Y) * s.X / 2 + math.abs(u.Y) * s.Y / 2 + math.abs(l.Y) * s.Z / 2,
				math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
			)
			local lo, hi = cf.Position - h, cf.Position + h
			mn = mn and Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z)) or lo
			mx = mx and Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z)) or hi
		end
	end
	return mn, mx
end

-- WAIT FOR THE PARTS, not just for the model. WaitForChild returns the Model the
-- instant it replicates and its descendants arrive after — so on a cold join
-- worldBox ran against an empty Model, found no BasePart and the whole feature
-- bailed out. It is a race, so it came and went: the first run after a push was
-- usually fine and a fresh Play was not.
--
-- Settling rather than first-part: the dotted rectangle is sized off the FULL
-- extent, and building it from the three parts that happened to arrive first
-- would draw a box round a third of the machine.
local boxMin, boxMax
do
	local DEADLINE = os.clock() + 20
	local last = -1
	while os.clock() < DEADLINE do
		local n = 0
		for _, d in ipairs(machine:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
		end
		if n > 0 and n == last then break end
		last = n
		task.wait(0.25)
	end
	boxMin, boxMax = worldBox(machine)
end

if not boxMin then
	warn("FuseController: the machine still has no BaseParts after 20s — nothing to outline.")
	return
end
local boxCentre = (boxMin + boxMax) / 2

--============================================================ 1. THE WORLD BITS
-- A folder for the things this controller puts in the world: the prompt's anchor
-- part, and the two helices the cutscene flies in. Kept as one parent so the
-- whole lot is obvious in the Explorer and goes in one line if it ever needs to.
local worldFolder = Instance.new("Folder")
worldFolder.Name = "FuseParts"
worldFolder.Parent = workspace

-- THE DASHED OUTLINE IS GONE. Three versions of it were built — a rectangle on
-- the floor, one cage round the model's bounding box, and a cage per big part —
-- and all three were marching white bricks standing off the geometry, which is a
-- lot of machinery to say "this object". The Highlight below says it directly and
-- traces the machine's real silhouette rather than a box approximating it, so the
-- border is now the only mark and it carries the whole job.

--============================================================ 2. THE BORDER
-- Built by WorldPrompt from GameConfig.Fuse.Select, together with the plate, so
-- the two cannot disagree about whether the machine is live. What that block
-- says, and why every value in it is what it is, lives in GameConfig — including
-- the two things worth repeating here: a Highlight has NO thickness property, so
-- "stronger" is colour, opacity and DepthMode and nothing else; and AlwaysOnTop
-- is what makes it a border on a machine that is mostly glass.

--======================================================== THE GRAVITY RIG, OFF
-- Workspace.Gravity is an invisible 29-stud box sitting on the machine carrying
-- 27 particle emitters and a point light, and it ships ENABLED — a permanent
-- column of sparks in the tank that means nothing because it is always there.
--
-- FindFirstChild, not workspace.Gravity: that name is also the Workspace's own
-- physics property, so the dot form returns the NUMBER 196.2 and indexing it
-- errors with "attempt to index number". Easy to lose an hour to.
--
-- Every emitter's own Enabled is remembered before switching it off, so the
-- cutscene restores what the artist set rather than turning everything on.
local vfxPart = workspace:FindFirstChild(CUT.VfxPartName or "Gravity")
local vfxBits = {}
local vfxLights = {}
if vfxPart then
	for _, d in ipairs(vfxPart:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			table.insert(vfxBits, d)
			if d:IsA("Light") then
				table.insert(vfxLights, { inst = d, base = d.Brightness })
			end
			d.Enabled = false
		end
	end
end

-- FORCED, not restored. An earlier version remembered each emitter's Enabled at
-- startup and put that back — which was right while the rig shipped switched ON,
-- and became a no-op the moment it was switched OFF in the place file so Studio's
-- Edit viewport would stop showing a permanent column of sparks. Remembering
-- "false" and faithfully restoring it meant the cutscene lit nothing at all.
local function setVfx(on)
	for _, inst in ipairs(vfxBits) do
		inst.Enabled = on
	end
	if not on then
		for _, l in ipairs(vfxLights) do
			l.inst.Brightness = l.base
		end
	end
end

--============================================================== 3. THE MONITOR
-- The machine's front panel carries a 3D-text model reading "TEXT + TEXT" — eight
-- letter meshes named uni0054, uni0045 and so on, one mesh per glyph, left behind
-- by a 3D-text plugin.
--
-- IT CANNOT BE RETYPED. The only glyphs present are T, E, X and +, so there is no
-- D, no N, no A and no digits to spell anything else with, and the plugin is not
-- in the place to regenerate them. So the letters are HIDDEN and a SurfaceGui
-- goes on the same bounding-box part, which can say anything and costs nothing.
local monitorLeft, monitorRight

do
	local textModel = machine:FindFirstChild("ThreeDTextObject")
	if textModel then
		-- Hidden rather than destroyed: it is the only record of what the sign used
		-- to be, and a local Transparency change costs nothing.
		for _, d in ipairs(textModel:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:match("^uni%x%x%x%x$") then
				d.Transparency = 1
			end
		end

		local face = textModel:FindFirstChild("ThreeDTextBoundingBox")
		if face then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "FuseDisplay"
			gui.Adornee = face
			-- Front is the face along the part's own -Z, which is the machine's
			-- LookVector — the side the 3D letters stood on.
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = DISPLAY.PixelsPerStud or 200
			gui.LightInfluence = 0
			gui.AlwaysOnTop = false
			gui.Parent = face

			local col = DISPLAY.Colour or Color3.fromRGB(150, 236, 255)
			local function line(name, y, h)
				local t = Instance.new("TextLabel")
				t.Name = name
				t.BackgroundTransparency = 1
				t.AnchorPoint = Vector2.new(0.5, 0.5)
				t.Position = UDim2.fromScale(0.5, y)
				t.Size = UDim2.fromScale(0.94, h)
				t.TextColor3 = col
				t.FontFace = FONT
				t.TextScaled = true
				t.Parent = gui
				return t
			end

			-- Three rows, matching the layout the 3D letters had: a word, the
			-- operator, a word.
			monitorLeft = line("Left", 0.2, 0.3)
			monitorLeft.Text = DISPLAY.DefaultLeft or "DNA 1"
			local op = line("Op", 0.5, 0.2)
			op.Text = DISPLAY.Operator or "+"
			monitorRight = line("Right", 0.8, 0.3)
			monitorRight.Text = DISPLAY.DefaultRight or "DNA 2"
		end
	end
end

-- "Scorpion DNA" across a two-stud monitor is four-point type, and every entry
-- ends in "DNA" anyway, so the word that tells them apart is the one that gets
-- the room.
local function shortName(name)
	if not name then return nil end
	if DISPLAY.ShortNames == false then return name end
	return (name:match("^(%S+)")) or name
end

local function setMonitor(a, b)
	if monitorLeft then
		monitorLeft.Text = a and string.upper(shortName(a.Name)) or (DISPLAY.DefaultLeft or "DNA 1")
	end
	if monitorRight then
		monitorRight.Text = b and string.upper(shortName(b.Name)) or (DISPLAY.DefaultRight or "DNA 2")
	end
end

--=============================================================== 4. THE PLATE
-- WorldPrompt owns the whole widget: the billboard, its pop in and out, the
-- ClickDetector on the model, the hover feel and the Highlight. Two things in
-- this game now want one — this machine and the cave's Entry arch — so it lives
-- in ReplicatedStorage rather than being copied.
--
-- THE PROXIMITY PROMPT IS GONE, key and all. It was right while the interaction
-- was "press E": Style = Custom brought Roblox's distance tracking, arbitration
-- and touch button for free. With the key removed, all it contributed was a
-- second range that could disagree with the highlight's — so the plate, the
-- border and the click now share ONE distance, and clicking is the only way in.
local prompt = WorldPrompt.new({
	Name = "Fuse",
	Target = machine,
	Parent = worldFolder,
	Palette = P,
	ActionText = PROMPT.ActionText or "Splice",
	ObjectText = PROMPT.ObjectText or "DNA MACHINE",
	Height = PROMPT.Height or 3.6,
	Aspect = PROMPT.Aspect or 3.15,
	Rise = PROMPT.Rise or 0,
	PopIn = PROMPT.PopIn or 0.24,
	PopOut = PROMPT.PopOut or 0.14,
	PopFrom = PROMPT.PopFrom or 0.4,
	ShowDistance = SEL.ShowDistance or 140,
	HoverSound = CLICK_CFG.HoverSound,
	ClickSound = CLICK_CFG.ClickSound,
	HoverVolume = CLICK_CFG.HoverVolume,
	ClickVolume = CLICK_CFG.ClickVolume,
	HoverGrow = CLICK_CFG.HoverGrow,
	PressDrop = CLICK_CFG.PressDrop,
	Highlight = SEL,
	OnActivate = function()
		-- Assigned below, once the overlay exists.
		if openScreen then openScreen() end
	end,
})

if not prompt then
	warn("FuseController: WorldPrompt refused the machine — nothing to click.")
	return
end
prompt.pollEvery = SEL.ShowPoll or 0.25

--============================================================== 5. THE OVERLAY

local panel = hud:WaitForChild("FusePanel", 20)
if not panel then
	warn("FuseController: StarterGui.HUD.FusePanel is missing.")
	return
end

local ASPECT = PANEL.Aspect or 1.62

-- Rebuilt every run. The shell is real StarterGui furniture, so anything built
-- into it last run is still there — including the chrome an earlier build put on
-- it, which is why the strokes and gradients go too.
for _, c in ipairs(panel:GetChildren()) do
	if c:IsA("GuiObject") or c:IsA("UIStroke") or c:IsA("UIGradient") then
		c:Destroy()
	end
end

-- NO CHROME. UIKit.chrome makes a PANEL — opaque body, white ring, moulded lip, a
-- thirty-layer cast shadow, a studded sheet — and that is exactly what this must
-- not be. A splice happens AT the machine, and a solid menu in front of it hides
-- the thing you walked over to use. So the shell is kept only as a layout box
-- (its aspect constraint and UIScale) and everything is drawn floating on it.
--
-- The cost of skipping chrome is that its helpers go too, so the few that are
-- needed are local. They are small, and the alternative is calling chrome and
-- then undoing six of the things it just did.
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.ZIndex = 50
panel.Visible = false

local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
scale.Name = "Scale"
scale.Parent = panel

do
	local ar = panel:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = ASPECT
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = panel
end
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.62, 0.62 * ASPECT)

-- Stroke weights and text sizes both scale off the panel's real pixel width, the
-- same way Kit:rescale does, so the overlay reads the same on a phone and a
-- monitor. Registries are weak-keyed so a destroyed element takes its entries
-- with it.
local STROKE_REF = 980
local strokes = setmetatable({}, { __mode = "k" })
local textCaps = setmetatable({}, { __mode = "k" })

local function corner(obj, s)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(s, 0)
	c.Parent = obj
	return c
end

local function stroke(obj, colour, base)
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = base
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	strokes[s] = base
	return s
end

-- Contextual, NOT Border: on a TextLabel with a transparent background, Border
-- strokes the label's bounding BOX rather than the glyphs.
local function outline(label, base)
	local s = stroke(label, P.Ink, base or 2)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

local function capText(label, frac)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 100
	c.Parent = label
	textCaps[c] = frac
	return c
end

-- A square element on a panel of aspect A: a Size of fromScale(s, s * A) is s of
-- the panel's WIDTH on both axes, because the height scale is taken against a
-- height that is A times smaller.
local function square(s)
	return UDim2.fromScale(s, s * ASPECT)
end

local Z_BODY = 54
local Z_MARK = 56

-------------------------------------------------------------------- the dim
-- A full-screen wash BEHIND the overlay, not a background on it. The blur is
-- already doing most of the separating; this is what stops white type
-- disappearing when the machine's own white VFX is behind it.
--
-- Parented to the HUD rather than to the panel, because it has to cover the whole
-- screen and the panel is a 62%-wide box in the middle of it.
local dim = Instance.new("Frame")
dim.Name = "FuseDim"
dim.BackgroundColor3 = P.Ink
dim.BackgroundTransparency = PANEL.Dim or 0.62
dim.BorderSizePixel = 0
dim.Size = UDim2.fromScale(1, 1)
dim.Position = UDim2.fromScale(0, 0)
dim.ZIndex = 49
dim.Visible = false
dim.Parent = hud

--------------------------------------------------------------- title and close
-- Floating type, no plate. Same treatment the HUD counters and the shop's ribbons
-- get: artwork and outlined type on nothing.
local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
-- LEFT-ALIGNED off centre, with the icon anchored to its right edge, so the two
-- sit side by side. Centred, they were drawn on top of each other: a centred
-- TextLabel puts its glyphs around 0.5 whatever its box is, which is exactly
-- where an icon anchored (1, 0.5) at 0.5 ends up.
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.fromScale(0.5, 0.055)
title.Size = UDim2.fromScale(0.4, 0.1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = FUSE.Title or "Splice!"
title.TextColor3 = WHITE
title.FontFace = FONT
title.TextScaled = true
title.ZIndex = Z_MARK
outline(title, 3.4)
capText(title, 0.5)
title.Parent = panel

local titleIcon
if FUSE.TitleIcon then
	titleIcon = Instance.new("ImageLabel")
	titleIcon.Name = "TitleIcon"
	titleIcon.BackgroundTransparency = 1
	titleIcon.AnchorPoint = Vector2.new(1, 0.5)
	-- 0.485, not 0.5: a small gap between the crown and the S, rather than the
	-- icon's own bounding box touching the letterform.
	titleIcon.Position = UDim2.fromScale(0.485, 0.055)
	titleIcon.Size = square(0.075)
	titleIcon.Image = FUSE.TitleIcon
	titleIcon.ScaleType = Enum.ScaleType.Fit
	titleIcon.Rotation = -8
	titleIcon.ZIndex = Z_MARK
	titleIcon.Parent = panel
end

local closeKey = Instance.new("TextButton")
closeKey.Name = "CloseButton"
closeKey.AutoButtonColor = false
closeKey.Text = ""
closeKey.AnchorPoint = Vector2.new(0.5, 0.5)
closeKey.Position = UDim2.fromScale(0.965, 0.05)
closeKey.Size = square(0.075)
closeKey.BackgroundColor3 = P.Close
closeKey.BorderSizePixel = 0
closeKey.ZIndex = Z_MARK
corner(closeKey, 0.3)
stroke(closeKey, WHITE, 3)
UIKit.bevel(closeKey, { P.Close, P.CloseDeep })
UIKit.audible(closeKey)
UIKit.feel(closeKey)
closeKey.Parent = panel

local closeGlyph = Instance.new("TextLabel")
closeGlyph.Name = "Glyph"
closeGlyph.BackgroundTransparency = 1
closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
closeGlyph.Position = UDim2.fromScale(0.5, 0.46)
closeGlyph.Size = UDim2.fromScale(0.92, 0.92)
closeGlyph.Text = "X"
closeGlyph.TextColor3 = WHITE
closeGlyph.FontFace = FONT
closeGlyph.TextScaled = true
closeGlyph.ZIndex = Z_MARK + 1
-- Thin. On a glyph this small a 2-3px contour closes the X's own gaps and leaves
-- a dark blob with a white cross scratched into it.
outline(closeGlyph, 1.3)
closeGlyph.Parent = closeKey

----------------------------------------------------------------- strand art
-- FLAT ICONS, one per strand, not a ViewportFrame of the rigged model. The
-- models were free and unmistakable and also wrong for a cell this size: a lit 3D
-- rig at 60px reads as a dark blob, and every cell needed its own camera and its
-- own clone of the rig.
--
-- Every id in GameConfig.Fuse.Strands is the TEXTURE inside a store page's Decal
-- wrapper, already resolved and already verified to preload in this group-owned
-- place. A strand with no Icon falls back to the game's own coin, so a bad id is
-- a wrong picture rather than an empty cell.
local function strandArt(strand)
	local im = Instance.new("ImageLabel")
	im.Name = "Icon"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Image = strand.Icon or FUSE.StrandIcon or ""
	-- Fit, not Stretch: these come from half a dozen creators at half a dozen
	-- aspect ratios and stretching turns round things into ovals.
	im.ScaleType = Enum.ScaleType.Fit
	return im
end

------------------------------------------------------------------- the slots
local slots = {}
local active = 1           -- which slot the picker fills; 1 is left, 2 is right
local chosen = { nil, nil }

local caption
local spliceKey
local refresh
local layout

local function makeSlot(index, xScale, label)
	local holder = Instance.new("Frame")
	holder.Name = "Slot" .. index
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(xScale, 0.33)
	holder.Size = square(0.21)
	holder.ZIndex = Z_BODY
	holder.Parent = panel

	local cap2 = Instance.new("TextLabel")
	cap2.Name = "Caption"
	cap2.BackgroundTransparency = 1
	cap2.AnchorPoint = Vector2.new(0.5, 1)
	cap2.Position = UDim2.fromScale(0.5, -0.06)
	cap2.Size = UDim2.fromScale(1.4, 0.2)
	cap2.Text = label
	-- WHITE with a contour, not the panel's navy: there is no white body behind
	-- this any more, only the blurred world.
	cap2.TextColor3 = WHITE
	cap2.FontFace = FONT
	cap2.TextScaled = true
	cap2.ZIndex = Z_BODY + 1
	outline(cap2, 2)
	capText(cap2, 0.16)
	cap2.Parent = holder

	-- THE DISC STAYS, and it is the one plated thing left on this screen. The rail
	-- cells in the inventory lost theirs because five plates in a column made the
	-- rail the subject; here there are exactly two and they ARE the subject —
	-- without a surface there is nothing for the + to sit in and nothing to show
	-- which slot is armed.
	local disc = Instance.new("TextButton")
	disc.Name = "Disc"
	disc.AutoButtonColor = false
	disc.Text = ""
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = P.Panel
	disc.BorderSizePixel = 0
	disc.ZIndex = Z_BODY + 1
	corner(disc, 0.5)
	disc.Parent = holder

	local ring = stroke(disc, P.Ink, 3)
	ring.Name = "Ring"

	UIKit.gloss(disc, 0.44, 0.5, 0.8)
	UIKit.audible(disc)
	UIKit.feel(disc, { Grow = 1.07, Tilt = 0 })

	local plus = Instance.new("TextLabel")
	plus.Name = "Plus"
	plus.BackgroundTransparency = 1
	plus.AnchorPoint = Vector2.new(0.5, 0.5)
	plus.Position = UDim2.fromScale(0.5, 0.5)
	plus.Size = UDim2.fromScale(0.74, 0.74)
	plus.Text = PANEL.EmptyGlyph or "+"
	plus.TextColor3 = P.Ink:Lerp(P.Panel, 0.45)
	plus.FontFace = FONT
	plus.TextScaled = true
	plus.ZIndex = Z_BODY + 2
	plus.Parent = disc

	-- The animal goes in here. Rebuilt on every change rather than pooled: a slot
	-- changes a handful of times per visit and one ViewportFrame is cheap.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(0.94, 0.94)
	stage.ZIndex = Z_BODY + 2
	stage.Parent = disc

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 1.02)
	name.Size = UDim2.fromScale(1.5, 0.14)
	name.Text = ""
	name.TextColor3 = WHITE
	name.FontFace = FONT
	name.TextScaled = true
	name.ZIndex = Z_BODY + 1
	outline(name, 2)
	capText(name, 0.17)
	name.Parent = holder

	local slot = {
		index = index, disc = disc, ring = ring,
		plus = plus, stage = stage, name = name,
	}

	disc.MouseButton1Click:Connect(function()
		-- A press on a FULL slot empties it. That is the only way to take something
		-- back out, and without it a player who picked wrong has to close the screen
		-- and walk back into the prompt.
		if chosen[index] then
			chosen[index] = nil
		end
		active = index
		refresh()
	end)

	slots[index] = slot
	return slot
end

makeSlot(1, 0.30, PANEL.LeftLabel or "STRAND A")
makeSlot(2, 0.70, PANEL.RightLabel or "STRAND B")

-- The operator between them. A "+" and not an "x": the machine takes two strands
-- and gives one back, which is addition as anybody reads it.
local operator = Instance.new("TextLabel")
operator.Name = "Operator"
operator.BackgroundTransparency = 1
operator.AnchorPoint = Vector2.new(0.5, 0.5)
operator.Position = UDim2.fromScale(0.5, 0.33)
operator.Size = square(0.13)
operator.Text = "+"
operator.TextColor3 = WHITE
operator.FontFace = FONT
operator.TextScaled = true
operator.ZIndex = Z_MARK
-- 1.8, not 3. FredokaOne's + is a fat round cross and a heavy round-joined stroke
-- closes its own inner corners, leaving a dark blob with no cross in it.
outline(operator, 1.8)
operator.Parent = panel

------------------------------------------------------------------- the caption
caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.BackgroundTransparency = 1
caption.AnchorPoint = Vector2.new(0.5, 0.5)
caption.Position = UDim2.fromScale(0.5, 0.605)
caption.Size = UDim2.fromScale(0.86, 0.075)
caption.Text = PANEL.Idle or ""
caption.TextColor3 = WHITE
caption.FontFace = FONT
caption.TextScaled = true
caption.ZIndex = Z_BODY
outline(caption, 2.4)
capText(caption, 0.28)
caption.Parent = panel

-------------------------------------------------------------- the strand picker
local picker = Instance.new("Frame")
picker.Name = "Strands"
picker.BackgroundTransparency = 1
picker.AnchorPoint = Vector2.new(0.5, 0.5)
picker.Position = UDim2.fromScale(0.5, 0.755)
picker.Size = UDim2.fromScale(0.88, 0.17)
picker.ZIndex = Z_BODY
picker.Parent = panel

local pickerList = Instance.new("UIListLayout")
pickerList.FillDirection = Enum.FillDirection.Horizontal
pickerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
pickerList.VerticalAlignment = Enum.VerticalAlignment.Center
pickerList.SortOrder = Enum.SortOrder.LayoutOrder
-- Six cells at 0.145 of the row plus five gaps at 0.025 is 0.995 — inside the row
-- with a hair to spare. Stated as a SCALE so it survives a phone: a pixel gap that
-- looks right at desk size is a third of a cell on a 400px-wide panel.
pickerList.Padding = UDim.new(0.025, 0)
pickerList.Parent = picker

local STRANDS = FUSE.Strands or {}
local pickerCells = {}

-- THE EXCLUSIVITY RULE, in one function. Both slots offer the same roster, and
-- what stops a player splicing a thing with itself is that a strand already
-- sitting in one slot is refused by the other. One roster, one rule, and no way
-- for the two sides to drift apart — which a second, shorter list for slot B
-- would have guaranteed the first time somebody added a strand.
local function usedElsewhere(strand)
	local other = active == 1 and 2 or 1
	return chosen[other] ~= nil and chosen[other].Name == strand.Name
end

for i, strand in ipairs(STRANDS) do
	local cell = Instance.new("TextButton")
	cell.Name = strand.Name
	cell.AutoButtonColor = false
	cell.Text = ""
	cell.LayoutOrder = i
	cell.Size = UDim2.fromScale(0.145, 1)
	cell.BackgroundColor3 = P.Panel
	cell.BorderSizePixel = 0
	cell.ZIndex = Z_BODY + 1
	corner(cell, 0.26)
	cell.Parent = picker

	stroke(cell, P.Ink, 2.4)

	-- The rarity's own gradient, so a Legendary strand and a Legendary pet are the
	-- same gold. INV.Rarities is the shop's five pairs and reusing them is what
	-- keeps every panel in this game one family.
	local grad = (INV.Rarities or {})[strand.Rarity] or P.Cyan
	UIKit.bevel(cell, grad)
	UIKit.gloss(cell, 0.42, 0.26, 0.62)
	UIKit.audible(cell)
	UIKit.feel(cell, { Grow = 1.08, Tilt = -3 })

	local art = strandArt(strand)
	art.Size = UDim2.fromScale(0.74, 0.62)
	art.Position = UDim2.fromScale(0.5, 0.4)
	art.ZIndex = Z_BODY + 2
	art.Parent = cell

	local nm = Instance.new("TextLabel")
	nm.Name = "Name"
	nm.BackgroundTransparency = 1
	nm.AnchorPoint = Vector2.new(0.5, 1)
	nm.Position = UDim2.fromScale(0.5, 0.99)
	nm.Size = UDim2.fromScale(0.94, 0.26)
	nm.Text = shortName(strand.Name)
	nm.TextColor3 = WHITE
	nm.FontFace = FONT
	nm.TextScaled = true
	nm.ZIndex = Z_BODY + 3
	outline(nm, 2)
	capText(nm, 0.2)
	nm.Parent = cell

	cell.MouseButton1Click:Connect(function()
		if usedElsewhere(strand) then
			-- Says why rather than doing nothing. A cell that is visibly dimmed and
			-- also silent when pressed reads as broken.
			caption.Text = ("%s is already in the other slot."):format(shortName(strand.Name))
			return
		end
		chosen[active] = strand
		-- Straight to the other slot after filling one. Two clicks fill both slots,
		-- which is the whole interaction; making the player aim at the second disc
		-- in between is a third click for nothing.
		active = active == 1 and 2 or 1
		refresh()
	end)

	pickerCells[i] = { cell = cell, strand = strand }
end

---------------------------------------------------------------- the splice key
spliceKey = Instance.new("TextButton")
spliceKey.Name = "Splice"
spliceKey.AutoButtonColor = false
spliceKey.AnchorPoint = Vector2.new(0.5, 0.5)
spliceKey.Position = UDim2.fromScale(0.5, 0.925)
spliceKey.Size = UDim2.fromScale(0.3, 0.1)
spliceKey.BackgroundColor3 = P.Green[1]
spliceKey.BorderSizePixel = 0
spliceKey.Text = ""
spliceKey.ZIndex = Z_BODY + 1
corner(spliceKey, 0.3)
spliceKey.Parent = panel

stroke(spliceKey, P.Ink, 2.6)
UIKit.gloss(spliceKey, 0.38, 0.3, 0.6)
UIKit.audible(spliceKey)
UIKit.feel(spliceKey)

local spliceText = Instance.new("TextLabel")
spliceText.Name = "Glyph"
spliceText.BackgroundTransparency = 1
spliceText.AnchorPoint = Vector2.new(0.5, 0.5)
spliceText.Position = UDim2.fromScale(0.5, 0.5)
spliceText.Size = UDim2.fromScale(0.9, 0.66)
spliceText.Text = PANEL.Button or "SPLICE"
spliceText.TextColor3 = WHITE
spliceText.FontFace = FONT
spliceText.TextScaled = true
spliceText.ZIndex = Z_BODY + 2
outline(spliceText, 2.4)
capText(spliceText, 0.42)
spliceText.Parent = spliceKey

---------------------------------------------------------------------- layout
-- capText only REGISTERS a cap; the pixel figure is resolved here. Without this
-- every capped label sits at the 100px default and TextScaled fills its box,
-- which is how a two-word slot caption ends up the size of the title.
--
-- The unit is the SLOT DIAMETER, because that is what every figure on this
-- overlay was chosen against. Divided by the UIScale for the same reason chrome's
-- rescale does it: the panel pops from 0.86 on every open, and text sized through
-- the animation settles on whatever the last frame happened to be.
function layout()
	local w = panel.AbsoluteSize.X / math.max(scale.Scale, 0.01)
	if w <= 0 then return end
	local unit = w * 0.21
	for c, frac in pairs(textCaps) do
		c.MaxTextSize = math.max(1, unit * frac)
	end
	local k = w / STROKE_REF
	for s, base in pairs(strokes) do
		s.Thickness = math.max(1, base * k)
	end
end

panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

--------------------------------------------------------------------- the state
-- THE SEAM. Everything about what a pair of strands makes is this one function,
-- so the day a server owns it the change is `resultFor` calling a RemoteFunction
-- and nothing else in this file moves.
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

local function resultFor(a, b)
	local ra = RARITY_ORDER[a.Rarity] or 1
	local rb = RARITY_ORDER[b.Rarity] or 1
	local best = ra >= rb and a or b
	return ("%s + %s makes a %s strand!"):format(
		shortName(a.Name), shortName(b.Name), string.lower(best.Rarity or "new")
	)
end

function refresh()
	for i, slot in ipairs(slots) do
		local strand = chosen[i]
		slot.plus.Visible = strand == nil
		slot.name.Text = strand and strand.Name or ""

		-- The stage is emptied and refilled rather than hidden: a ViewportFrame
		-- holding a cloned rig is the expensive thing on this screen and leaving six
		-- of them parked would be six rigs rendering behind a hidden frame.
		for _, c in ipairs(slot.stage:GetChildren()) do c:Destroy() end
		if strand then
			local art = strandArt(strand)
			art.Size = UDim2.fromScale(0.86, 0.86)
			art.ZIndex = Z_BODY + 3
			art.Parent = slot.stage
			local grad = (INV.Rarities or {})[strand.Rarity] or P.Cyan
			UIKit.bevel(slot.disc, grad)
		else
			-- Back to the empty disc. bevel() replaces its own gradient on each call,
			-- so this is a repaint and not a teardown.
			UIKit.bevel(slot.disc, { P.Panel, P.Ink:Lerp(P.Panel, 0.86) })
		end

		-- The ACTIVE slot is the one the picker fills, and it has to be obvious which
		-- that is or the row below looks like it fills a slot at random.
		local isActive = active == i
		slot.ring.Color = isActive and P.Cyan[2] or P.Ink
		strokes[slot.ring] = isActive and 4.6 or 3
	end

	-- A cell holding what the OTHER slot already has is dimmed. Not hidden and not
	-- removed: the roster is the same six every time, and a row that changes length
	-- as you fill slots reads as items disappearing.
	for _, pc in ipairs(pickerCells) do
		local blocked = usedElsewhere(pc.strand)
		pc.cell.BackgroundTransparency = blocked and 0.55 or 0
		for _, d in ipairs(pc.cell:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.TextTransparency = blocked and 0.5 or 0
			elseif d:IsA("ImageLabel") and d.Name == "Icon" then
				d.ImageTransparency = blocked and 0.6 or 0
			end
		end
	end

	local a, b = chosen[1], chosen[2]
	local ready = a ~= nil and b ~= nil
	-- Greyed rather than hidden: a button that appears when you are done is a
	-- button you did not know you were working towards.
	UIKit.bevel(spliceKey, ready and P.Green
		or { P.Ink:Lerp(P.Panel, 0.8), P.Ink:Lerp(P.Panel, 0.62) })

	caption.Text = ready and (PANEL.Ready or "Ready to splice!") or (PANEL.Idle or "")
	setMonitor(a, b)
	layout()
end

--=============================================================== 6. THE CUTSCENE

local function fuseSound(id, volume)
	local s = Instance.new("Sound")
	s.Name = "FuseSfx" .. tostring(id)
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume
	s.Parent = SoundService
	return s
end

local buildSfx = CUT.BuildSound and fuseSound(CUT.BuildSound, CUT.BuildVolume or 0.65)
local finishSfx = CUT.FinishSound and fuseSound(CUT.FinishSound, CUT.FinishVolume or 0.8)

-- The white-out, on the HUD above everything the HUD draws — the message feed
-- sits at 200 and this has to cover that too, because the flash IS the cut.
local flash = Instance.new("Frame")
flash.Name = "FuseFlash"
flash.BackgroundColor3 = WHITE
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.ZIndex = 400
flash.Visible = false
flash.Parent = hud

-- The helix the machine already contains, which DnaSpin turns. The cutscene
-- clones it twice rather than modelling anything new: the object the player has
-- been watching spin in the tank is the object that should fly in.
--
-- LocalTransparencyModifier, not Transparency: DnaSpin writes this part's CFrame
-- every RenderStepped and the part is replicated furniture, so a local visibility
-- change is the one that cannot be seen by anybody else or fought over.
local helixSource = machine:FindFirstChild("Dna") and machine.Dna:FindFirstChild("dna")

local busy = false

-- Assigned in the OPEN AND CLOSE block below. The cutscene needs it before that
-- block exists, because the first thing a splice does is take the blur off.
local setBlur

local function runCutscene(a, b)
	local cam = workspace.CurrentCamera
	local camWas = cam.CameraType
	local camCF = cam.CFrame

	-- 1. THE SCREEN GOES, and SO DOES THE BLUR. The blur exists to push the world
	--    back behind a menu; a cutscene IS the world, and leaving it on rendered
	--    the whole shot as a smear — the two helices and the gravity rig were
	--    genuinely there and genuinely unreadable. Verified by capture: frames
	--    through the merge were a blurred white wash with the machine barely
	--    visible in it.
	panel.Visible = false
	dim.Visible = false
	if setBlur then setBlur(false) end
	-- The border and the plate are a "you can use this" mark and the shot is of
	-- the machine using itself, so they go for the duration. The poll is gated on
	-- `busy`, so the first tick after the cutscene ends puts them back.
	prompt:suppress()

	-- 2. THE CAMERA takes over and glides in.
	local look = boxCentre + Vector3.new(0, CUT.CameraLookLift or 1.5, 0)
	local offset = CUT.CameraOffset or Vector3.new(0, 5.5, 26)
	local fovWas = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local target = CFrame.lookAt(boxCentre + offset, look)
	-- The GLIDE is a tween; the SHAKE is added on top of wherever the tween has
	-- got to, by the animation loop below. Tweening CFrame and also writing CFrame
	-- every frame would be two things fighting for the same property, so the loop
	-- reads the tweened value and offsets it instead of replacing it.
	local glide = TweenService:Create(cam, TweenInfo.new(CUT.CameraEase or 0.8,
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target })
	glide:Play()

	-- 3. THE RIG LIGHTS UP and the wind-up starts.
	setVfx(true)
	if buildSfx then
		buildSfx.TimePosition = 0
		buildSfx:Play()
	end

	-- 4. TWO HELICES fly in from either side and counter-rotate on the way, so the
	--    pair reads as two strands winding together rather than two copies of one
	--    object sliding. The machine's own helix is hidden for the duration and
	--    comes back underneath them as they fade — so what is left standing in the
	--    tank is ONE strand, which is the whole point of the shot.
	local spread = CUT.Spread or 7.5
	local approach = CUT.Approach or 2.1
	local merge = CUT.Merge or 0.55
	local turns = CUT.Turns or 2.5

	local flyers = {}
	if helixSource then
		helixSource.LocalTransparencyModifier = 1
		local base = helixSource.CFrame
		-- The machine's own left/right, so the two arrive across its face rather
		-- than along whichever world axis happened to be sideways.
		local side = machine:GetPivot().RightVector
		for s = -1, 1, 2 do
			local f = helixSource:Clone()
			f.Anchored = true
			f.CanCollide = false
			f.CanQuery = false
			f.CanTouch = false
			f.Parent = worldFolder
			table.insert(flyers, { part = f, from = base.Position + side * (spread * s), dir = s })
		end
	end

	-- THE TANK SPINS UP. DnaSpin reads this attribute every frame, so the wind-up
	-- is one number set from here rather than a second copy of the spin loop.
	local spinAttr = CUT.SpinAttribute or "SpinBoost"
	local spinPeak = CUT.SpinBoost or 9

	local shakeAmp = CUT.Shake or 0.16
	local lightPeak = CUT.LightPeak or 6

	local t0 = os.clock()
	local anim
	anim = RunService.RenderStepped:Connect(function()
		if not helixSource then return end
		local t = os.clock() - t0
		local base = helixSource.CFrame

		-- RAMPED, not switched: the helix accelerates through the approach and is
		-- at full speed on the frame the two strands meet. A step change reads as a
		-- dropped frame rather than as a machine spinning up.
		local ramp = math.clamp(t / approach, 0, 1)
		machine:SetAttribute(spinAttr, 1 + (spinPeak - 1) * ramp)

		-- The gravity rig's own PointLight, pulsed with the same ramp. Reusing it
		-- rather than adding a light: it is already there, already aimed, and
		-- already switched on for this shot.
		for _, l in ipairs(vfxLights) do
			l.inst.Brightness = l.base + (lightPeak - l.base) * ramp
		end

		-- SHAKE, added on top of the glide rather than replacing it. Ramps with the
		-- approach so it is nothing at the start and strongest at the merge. Small
		-- on purpose: past about 0.3 studs it reads as the camera being broken
		-- rather than the machine being powerful.
		if shakeAmp > 0 then
			local k = shakeAmp * ramp
			cam.CFrame = cam.CFrame * CFrame.new(
				(math.random() - 0.5) * 2 * k,
				(math.random() - 0.5) * 2 * k,
				0
			)
		end

		for _, f in ipairs(flyers) do
			-- Ease-out on the approach, so the two rush together and settle rather
			-- than arriving at constant speed.
			local p = math.clamp(t / approach, 0, 1)
			local eased = 1 - (1 - p) ^ 3
			local pos = f.from:Lerp(base.Position, eased)
			local spin = eased * turns * 2 * math.pi * f.dir
			f.part.CFrame = CFrame.new(pos) * (base - base.Position) * CFrame.Angles(0, spin, 0)
			if t > approach then
				local m = math.clamp((t - approach) / merge, 0, 1)
				f.part.Transparency = m
				helixSource.LocalTransparencyModifier = 1 - m
			end
		end
	end)

	-- 5. The wind-up is cut before its own tail: its last second is a decay that
	--    would run underneath the impact, so it stops and the two land back to back
	--    instead of overlapping.
	if buildSfx then
		local len = buildSfx.TimeLength > 0 and buildSfx.TimeLength or 4.03
		local playable = math.max(len - (CUT.BuildCut or 1.0), 0.2)
		task.delay(playable, function()
			if buildSfx.IsPlaying then buildSfx:Stop() end
		end)
	end

	task.wait(approach + merge)

	-- 6. THE WHITE-OUT, on the frame the two become one. In fast, out slow: the
	--    flash IS the cut, and a slow fade in reads as fog rolling over.
	flash.Visible = true
	flash.BackgroundTransparency = 1
	TweenService:Create(flash, TweenInfo.new(CUT.FlashIn or 0.12), { BackgroundTransparency = 0 }):Play()
	if finishSfx then finishSfx:Play() end
	-- THE FOV PUNCH: a fast pull-in and a slower release. It is what sells an
	-- impact when there is no impact to render, and it lands under the white so
	-- the player feels it more than sees it.
	if (CUT.FovKick or 0) ~= 0 then
		TweenService:Create(cam, TweenInfo.new(CUT.FovIn or 0.12, Enum.EasingStyle.Quad),
			{ FieldOfView = fovWas + CUT.FovKick }):Play()
		task.delay((CUT.FovIn or 0.12) + 0.05, function()
			TweenService:Create(cam, TweenInfo.new(CUT.FovOut or 0.5, Enum.EasingStyle.Quad),
				{ FieldOfView = fovWas }):Play()
		end)
	end
	task.wait((CUT.FlashIn or 0.12) + (CUT.FlashHold or 0.16))

	-- Behind the white: the flyers go, the real helix is fully back.
	if anim then anim:Disconnect() end
	for _, f in ipairs(flyers) do f.part:Destroy() end
	if helixSource then helixSource.LocalTransparencyModifier = 0 end

	TweenService:Create(flash, TweenInfo.new(CUT.FlashOut or 0.65), { BackgroundTransparency = 1 }):Play()
	task.wait(CUT.FlashOut or 0.65)
	flash.Visible = false

	task.wait(CUT.Settle or 0.9)

	-- 7. HAND BACK. The camera type is restored LAST, after the glide home, or the
	--    player's own camera snaps to the character mid-move.
	-- The spin comes back down over the hand-back rather than snapping: the tank
	-- is still on screen for the whole glide home.
	do
		local easeBack = CUT.CameraEase or 0.8
		task.spawn(function()
			local t1 = os.clock()
			while os.clock() - t1 < easeBack do
				local k = 1 - ((os.clock() - t1) / easeBack)
				machine:SetAttribute(spinAttr, 1 + (spinPeak - 1) * k)
				task.wait()
			end
			machine:SetAttribute(spinAttr, 1)
		end)
	end

	TweenService:Create(cam, TweenInfo.new(CUT.CameraEase or 0.8, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { CFrame = camCF }):Play()
	task.wait(CUT.CameraEase or 0.8)
	cam.CameraType = camWas
	cam.FieldOfView = fovWas

	setVfx(false)
end

--=========================================================== OPEN AND CLOSE

-- ITS OWN BlurEffect, not HUDController's PanelBlur. That one is driven by
-- syncBlur(), which reads HUDController's `openPanel` — this screen is not one of
-- the six it owns, so syncBlur would switch the blur off underneath it the moment
-- anything else changed. Honours the same MenuBlur setting, because a player who
-- turned blur off meant all of it.
local blur = Instance.new("BlurEffect")
blur.Name = "FuseBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local open = false
local hudOpen = hud:WaitForChild("HUDOpenPanel", 20)

function setBlur(want)
	if hud:GetAttribute("MenuBlur") == false then want = false end
	if want then blur.Enabled = true end
	TweenService:Create(
		blur,
		TweenInfo.new(want and 0.28 or 0.16, Enum.EasingStyle.Quad),
		{ Size = want and (PANEL.BlurSize or 20) or 0 }
	):Play()
	if not want then
		task.delay(0.18, function()
			if not open then blur.Enabled = false end
		end)
	end
end

local function setOpen(state)
	if open == state then return end
	if state and busy then return end   -- no reopening mid-cutscene
	open = state
	panel.Visible = state
	dim.Visible = state
	setBlur(state)
	if state then
		-- Clear whichever of the HUD's six is up. Two screens at once is what this
		-- looks like without it — the same rule AdminController follows.
		if hudOpen then
			pcall(function() hudOpen:Invoke(nil, false) end)
		end
		scale.Scale = 0.86
		TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1 }):Play()
		layout()
	end
end

closeKey.MouseButton1Click:Connect(function() setOpen(false) end)

spliceKey.MouseButton1Click:Connect(function()
	local a, b = chosen[1], chosen[2]
	if not (a and b) then
		caption.Text = PANEL.Idle or ""
		return
	end
	if busy then return end
	busy = true
	caption.Text = resultFor(a, b)
	open = false
	task.spawn(function()
		local ok, err = pcall(runCutscene, a, b)
		if not ok then
			-- The cutscene takes the camera. If it throws halfway the player is left
			-- looking at the machine with no way back, so the camera and the rig are
			-- put right here whatever happened.
			warn("FuseController: cutscene failed — " .. tostring(err))
			local cam = workspace.CurrentCamera
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
			setVfx(false)
			flash.Visible = false
			-- The spin boost is an ATTRIBUTE, so it outlives the coroutine that set
			-- it: without this the tank keeps spinning at nine times speed forever.
			machine:SetAttribute(CUT.SpinAttribute or "SpinBoost", 1)
			if helixSource then helixSource.LocalTransparencyModifier = 0 end
		end
		-- Reset for the next one. Both slots empty, the monitor back to its
		-- defaults, and the screen left closed — the splice is finished, and
		-- reopening it is the player's call.
		chosen[1], chosen[2] = nil, nil
		active = 1
		busy = false
		-- setBorder refuses while `busy`, so the poll could not turn it back on
		-- during the cutscene; the next tick after this picks it up.
		-- The blur went off at the top of the cutscene, not here. Nothing to undo.
		refresh()
	end)
end)

-- The other direction: opening a shop or an inventory closes this one.
hud:GetAttributeChangedSignal("OpenPanel"):Connect(function()
	if open and hud:GetAttribute("OpenPanel") ~= nil then
		setOpen(false)
	end
end)

--=========================================== PRESSING THE MACHINE ITSELF
-- All of it — the ClickDetector on the model, the hover feel, the press, the
-- distance poll that shows the plate and the border together — is WorldPrompt's
-- now. What is left here is the one line that says what a press DOES.
function openScreen()
	setOpen(true)
end

-- The poll is gated on `busy` so the cutscene owns the machine's look while it
-- runs, and the next tick after it finishes puts the plate and border back.
prompt:watch(function() return busy end)

layout()
refresh()

print(("FuseController: %s wired — %d strands, %d vfx bits.")
	:format(FUSE.ModelName, #STRANDS, #vfxBits))
