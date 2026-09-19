--[[
	InventoryController — fills StarterGui.HUD.InventoryPanel.

	The Pet Simulator 99 inventory shape, rendered in this game's own surfacing:
	header chrome overhanging the panel's top edge (title, a two-cell sort pill, a
	search field, the close key), a rail overhanging its left edge, then a shelf of
	equipped pets, a divider, and the whole roster as a scrolling grid. Order,
	copy, icons, rarity colours, column counts and the roster itself all come from
	ReplicatedStorage.GameConfig.Inventory and GameConfig.Shop.Palette, so a new
	pet or a re-tint is a config edit rather than a GUI edit — the same property
	the shop has.

	The panel chrome — white ring, pale lip, 30-layer stacked shadow, body
	gradient, title, close-button restyle, and the stroke / text-cap registries —
	is ReplicatedStorage.UIKit, shared with every panel still to come.
	HUDController still owns the open/close pop, the close button's feel and the
	studded plate.

	Pets FLOAT, the way the reference has them: no plastic tile, no ink outline, no
	gloss. Behind each one is a soft-edged blob tinted with its rarity colour, which
	is what carries the rarity read now that the tile is gone. An earlier pass gave
	every pet a bevelled shop-style tile on the argument that floating art abandoned
	the house language; it was rejected on sight — eight saturated plates in a row
	is a wall of colour, and the pet stops being the subject.

	NOTHING HERE EQUIPS ANYTHING, and nothing here buys, sells, locks or deletes
	anything either. ServerScriptService is empty: there is no pet system, no
	DataStore and no remote, so pressing a tile pops it and does nothing else. The
	ONE seam where real inventory data will arrive is readInventory() below, which
	returns GameConfig.Inventory.Pets today and will return replicated state when
	something owns it. Do not grow a persistence layer in here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local INV = CONFIG.Inventory
-- The SHOP's palette, deliberately. Two panels in one game do not get two
-- palettes; that is what keeps them reading as one family.
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("InventoryPanel")
local panelScale = panel:WaitForChild("Scale")

------------------------------------------------------------------------ spec
-- Panel-relative or cell-relative throughout, so everything survives any
-- viewport. Nothing below is a pixel except stroke weights and the 44px tap floor.

-- Measured off the reference screenshot: the panel is 755 x 395 of it, i.e.
-- 1.91:1. The shop's is 1.75 — this one is wider and shorter because it carries a
-- grid eight wide instead of three.
local PANEL_ASPECT = 1.9
local PANEL_CORNER = 0.045
local INSET = 0.02        -- scroll inset from the panel edge, of panel WIDTH
-- The rail overhangs the LEFT edge the way the header overhangs the top, so the
-- content has to start clear of the half of it that is on the panel.
local RAIL_W = 0.055      -- of panel width
local RAIL_X = 0.014      -- rail CENTRE, of panel width: just over half outside
-- The rail's own padding and gap, of its own box. Named rather than inlined
-- because the capsule's HEIGHT is solved from them below.
local RAIL_PAD_SIDE = 0.10
local RAIL_PAD_TB = 0.02
local RAIL_GAP = 0.012
-- Starts below the title icon, which hangs off the same corner and is drawn over
-- the rail (ZIndex 62 against 56) if the two are allowed to meet. The TOP is the
-- fixed end; the capsule grows downward from it.
local RAIL_TOP = 0.22
-- DERIVED, not chosen. A cell is squared by a UIAspectRatioConstraint, so its
-- height is the rail's usable WIDTH converted to panel-height units — and the
-- capsule is however tall it takes to hold #Rail of them plus the gaps. Dropping
-- the two locked cells from eight to six left a quarter of the old fixed 0.75
-- capsule empty below the last icon, which is the bug this replaces.
local RAIL_CELL = RAIL_W * PANEL_ASPECT * (1 - RAIL_PAD_SIDE * 2)
local RAIL_H = (#INV.Rail * RAIL_CELL)
	/ (1 - RAIL_GAP * (#INV.Rail - 1) - RAIL_PAD_TB * 2)
local RAIL_Y = RAIL_TOP + RAIL_H / 2
local CONTENT_X = 0.062   -- the scroll's left edge, of panel width
-- Side inset INSIDE the scroll, of its window width. Tiles are sized to fill the
-- row exactly, so the outer column's UIStroke — drawn outside the tile's bounds —
-- would be clipped by the scroll's edge, and the hover pop would then push a
-- visible slice of the tile itself out of view. This is the room both need.
local EDGE = 0.02
local GUTTER = 0.014      -- of content width
-- The rarity blob behind a floating pet, as a fraction of the tile. OVER 1: the
-- image's soft edge has to run out past the tile's bounds or it reads as a
-- cropped square instead of a blob.
local BLOB_SIZE = 1.0
-- Faint. It is a tint under the pet, not a plate behind it — at full strength the
-- grid goes back to being eight saturated squares, which is what this replaced.
local BLOB_FADE = 0.62

-- Entrance stagger: per-tile delay, and the ceiling no tile waits past.
local ENTRY_STEP = 0.022
local ENTRY_MAX = 0.28

-- A tile is square: an icon over a power number, with the count badge in the
-- corner. UICorner scale is of the shorter side, which here is either.
local TILE_CORNER = 0.16
-- Of panel height, added under the lowest piece of header chrome before the
-- content starts.
local HEADER_GAP = 0.03
-- Pixels below the Roblox topbar that the header chrome must clear. See
-- placeHeader().
local TOPBAR_MARGIN = 6
-- The 44px tap floor, the one other pixel figure in this file. The close button
-- already carries it in StarterGui; the sort pill and the search field are the
-- only other things here that can be pressed or typed into.
local MIN_TAP_PX = 44

------------------------------------------------------------------------- data
-- THE SEAM. Everything below renders whatever this returns, in this shape:
--   { Name = string, Rarity = string, Power = number?, Count = number, Equipped = boolean? }
-- Today that is the placeholder roster in GameConfig. When a server owns pets
-- this becomes a read of replicated state and nothing else in this file changes.
local function readInventory()
	return INV.Pets
end

-- NOT_WIRED: pressing a tile is deliberately inert. Wiring it means an equip
-- remote and a server that owns the equipped set; doing it on the client would
-- be a number that only exists here, which is a lie that desyncs the moment
-- anything else reads it.
local function onTilePressed(_pet)
end

------------------------------------------------------------------------ chrome
local kit = UIKit.chrome(panel, {
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = INV.Title,
	TitleIcon = INV.TitleIcon,
	Palette = P,
})

-- UIKit sizes the title box off the shop's fifteen-character string, where the
-- WIDTH limit is what TextScaled lands on. "Inventory!" is two thirds of that and
-- would come out half again too big, so this one is height-limited instead.
-- Measured on the reference: the title's cap height is 7.6% of panel height.
kit.title.Size = UDim2.fromScale(0.5, 0.082)

-- The shell's Banner is ShopPanel furniture; this layout has no feature row.
-- Hidden rather than destroyed, like Rule and Body.
local banner = panel:FindFirstChild("Banner")
if banner then banner.Visible = false end

local close = kit.close

--------------------------------------------------------------------- the rail
-- A white rounded column overhanging the panel's left edge, eight square icon
-- tiles down it. Only RailSelected has anything behind it — the other seven are
-- inert ON PURPOSE, because there is nothing to show yet, so they are Frames and
-- not buttons. A dead button that pops when you press it is worse than a label.
local rail = Instance.new("Frame")
rail.Name = "Rail"
rail.AnchorPoint = Vector2.new(0.5, 0.5)
rail.Position = UDim2.fromScale(RAIL_X, RAIL_Y)
rail.Size = UDim2.fromScale(RAIL_W, RAIL_H)
rail.BackgroundColor3 = P.Panel
rail.BorderSizePixel = 0
-- Above the panel (50) and its scroll (52), because it overhangs the panel's
-- edge; below the header chrome (61+), which overhangs the same corner.
rail.ZIndex = 56
kit:corner(rail, 0.30) -- of the shorter side, which is its width: a capsule
-- Thinner than the panel's own chrome. The rail is a shelf the panel carries, not
-- a second panel, and at 3 it read as heavily outlined as the thing it sits on.
kit:stroke(rail, P.Ink, 2)
rail.Parent = panel

local railPad = Instance.new("UIPadding")
railPad.PaddingLeft = UDim.new(RAIL_PAD_SIDE, 0)
railPad.PaddingRight = UDim.new(RAIL_PAD_SIDE, 0)
railPad.PaddingTop = UDim.new(RAIL_PAD_TB, 0)
railPad.PaddingBottom = UDim.new(RAIL_PAD_TB, 0)
railPad.Parent = rail

local railList = Instance.new("UIListLayout")
railList.FillDirection = Enum.FillDirection.Vertical
railList.HorizontalAlignment = Enum.HorizontalAlignment.Center
railList.VerticalAlignment = Enum.VerticalAlignment.Center
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.Padding = UDim.new(RAIL_GAP, 0)
railList.Parent = rail

for i, entry in ipairs(INV.Rail) do
	local tile = Instance.new("Frame")
	tile.Name = entry.Name
	tile.LayoutOrder = i
	-- A generous free axis, then squared by the constraint. A
	-- UIAspectRatioConstraint only ever SHRINKS — it never derives a zero axis —
	-- so a width of 0 here would render nothing at all.
	--
	-- Height DERIVED from the roster length, not the 0.108 that eight cells wanted:
	-- the two locked "?" cells are gone, and six cells at the old height left a
	-- quarter of the capsule empty below them.
	tile.Size = UDim2.fromScale(1, RAIL_CELL / RAIL_H)
	tile.BorderSizePixel = 0
	tile.ZIndex = 57
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = tile
	kit:corner(tile, 0.24)

	local selected = i == (INV.RailSelected or 1)
	if entry.Locked then
		-- Desaturated, which on a greyscale rail means simply darker and duller.
		tile.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.58)
	elseif selected then
		-- Visibly lighter than its neighbours, and the only one with an outline.
		tile.BackgroundColor3 = WHITE
		kit:stroke(tile, P.Ink, 1.8)
	else
		-- Paler than it was. These are inert cells behind a selected one; at 0.80
		-- they were dark enough to compete with it for the eye.
		tile.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.88)
	end

	if entry.Locked then
		-- The reference puts a padlock here. The client's own texture set has no
		-- padlock and uploads 403 in this group-owned place, so it is a "?" — see
		-- the note in GameConfig.Inventory.Rail.
		local q = Instance.new("TextLabel")
		q.Name = "Locked"
		q.BackgroundTransparency = 1
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Position = UDim2.fromScale(0.5, 0.5)
		q.Size = UDim2.fromScale(0.8, 0.7)
		q.Text = "?"
		q.TextColor3 = P.Ink:Lerp(P.Panel, 0.22)
		q.FontFace = FONT
		q.TextScaled = true
		q.ZIndex = 58
		kit:capText(q, 0.42)
		q.Parent = tile
	elseif entry.Icon then
		local im = Instance.new("ImageLabel")
		im.Name = "Icon"
		im.BackgroundTransparency = 1
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(0.5, 0.5)
		-- Nearly the whole cell. At 0.78 the icons read as small marks floating in
		-- their plates rather than as the plate's content, which is what the
		-- reference's rail looks like.
		im.Size = UDim2.fromScale(0.86, 0.86)
		im.Image = entry.Icon
		-- Fit, not Stretch: these come from half a dozen creators at half a dozen
		-- aspect ratios and stretching turns round things into ovals.
		im.ScaleType = Enum.ScaleType.Fit
		im.ZIndex = 58
		im.Parent = tile
	end

	tile.Parent = rail
end

---------------------------------------------------------------- the sort pill
-- The reference's centre pill is two icon cells, a padlock and a grid mark.
-- Neither glyph is in the client's own texture set and uploads do not work here,
-- so this is TYPE — and unlike the reference's it actually sorts the main grid.
-- Same silhouette, one less lie. Labels and keys: GameConfig.Inventory.Sorts.
local sortKey = INV.Sorts[1].Key
local sortCells = {}
local rebuildGrid -- forward declaration; the cells call it

local pill = Instance.new("Frame")
pill.Name = "SortPill"
pill.AnchorPoint = Vector2.new(0.5, 0.5)
pill.Position = UDim2.fromScale(0.50, 0)
pill.Size = UDim2.fromScale(0.24, 0.115)
-- The dark navy of the reference, mixed from the palette rather than picked: Ink
-- is the darkest thing here and BodyText the navy, so the blend between them is
-- the only navy that cannot drift when either is re-tuned.
pill.BackgroundColor3 = P.Ink:Lerp(P.BodyText, 0.6)
pill.BorderSizePixel = 0
pill.ZIndex = 58
kit:corner(pill, 0.40)
kit:stroke(pill, P.Ink, 2.6)
do
	-- The tap floor. Two cells side by side in a pill this short are otherwise
	-- ~18px tall on the smallest phone preset.
	local c = Instance.new("UISizeConstraint")
	c.MinSize = Vector2.new(0, MIN_TAP_PX)
	c.Parent = pill
end
pill.Parent = panel

local pillPad = Instance.new("UIPadding")
pillPad.PaddingTop = UDim.new(0.10, 0)
pillPad.PaddingBottom = UDim.new(0.10, 0)
pillPad.PaddingLeft = UDim.new(0.02, 0)
pillPad.PaddingRight = UDim.new(0.02, 0)
pillPad.Parent = pill

local pillRow = Instance.new("UIListLayout")
pillRow.FillDirection = Enum.FillDirection.Horizontal
pillRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
pillRow.VerticalAlignment = Enum.VerticalAlignment.Center
pillRow.SortOrder = Enum.SortOrder.LayoutOrder
pillRow.Parent = pill

local function paintSorts()
	for _, c in ipairs(sortCells) do
		local on = c.key == sortKey
		-- Lifted, not tinted: the active cell gets the raised plate and sits a
		-- couple of percent higher, which reads on touch where a hover never does.
		c.plate.Visible = on
		c.label.TextTransparency = on and 0 or 0.35
		c.label.Position = UDim2.fromScale(0.5, on and 0.44 or 0.5)
	end
end

for i, entry in ipairs(INV.Sorts) do
	local b = Instance.new("TextButton")
	b.Name = entry.Key
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.LayoutOrder = i
	b.Size = UDim2.fromScale(1 / #INV.Sorts, 1)
	b.ZIndex = 59

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Sits a touch above centre, so the pill's own floor shows below it and the
	-- cell reads as a key standing proud of the plate rather than as a fill.
	plate.Position = UDim2.fromScale(0.5, 0.44)
	plate.Size = UDim2.fromScale(0.94, 1)
	plate.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.34)
	plate.BorderSizePixel = 0
	plate.ZIndex = 59
	kit:corner(plate, 0.34)
	UIKit.gloss(plate, 0.5, 0.34, 0.76)
	plate.Parent = b

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.84, 0.54)
	label.Text = entry.Label
	label.TextColor3 = WHITE
	label.FontFace = FONT
	label.TextScaled = true
	label.ZIndex = 60
	kit:capText(label, 0.26)
	kit:outline(label, 1.8)
	label.Parent = b

	UIKit.audible(b)
	b.Activated:Connect(function()
		if sortKey == entry.Key then return end
		sortKey = entry.Key
		paintSorts()
		rebuildGrid()
	end)

	b.Parent = pill
	table.insert(sortCells, { key = entry.Key, plate = plate, label = label })
end
paintSorts()

-------------------------------------------------------------- the search field
local search = Instance.new("Frame")
search.Name = "SearchField"
search.AnchorPoint = Vector2.new(1, 0.5)
search.Position = UDim2.fromScale(0.905, 0)
search.Size = UDim2.fromScale(0.25, 0.115)
search.BackgroundColor3 = WHITE
search.BorderSizePixel = 0
search.ZIndex = 58
kit:corner(search, 0.42)
kit:stroke(search, P.Ink, 2.6)
do
	local c = Instance.new("UISizeConstraint")
	c.MinSize = Vector2.new(0, MIN_TAP_PX)
	c.Parent = search
end
search.Parent = panel

local mag = Instance.new("ImageLabel")
mag.Name = "Magnifier"
mag.BackgroundTransparency = 1
mag.AnchorPoint = Vector2.new(0, 0.5)
mag.Position = UDim2.fromScale(0.05, 0.5)
-- Generous free axis, squared by the constraint (which only ever shrinks).
mag.Size = UDim2.fromScale(0.5, 0.52)
mag.Image = INV.SearchIcon
-- ImageColor3 MULTIPLIES, so this can only darken. The glyph ships dark already;
-- this only takes it from black to the panel's own grey.
mag.ImageColor3 = P.Ink:Lerp(P.Panel, 0.30)
mag.ScaleType = Enum.ScaleType.Fit
mag.ZIndex = 59
do
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = mag
end
mag.Parent = search

local box = Instance.new("TextBox")
box.Name = "Query"
box.BackgroundTransparency = 1
box.AnchorPoint = Vector2.new(1, 0.5)
box.Position = UDim2.fromScale(0.95, 0.5)
box.Size = UDim2.fromScale(0.72, 0.56)
box.Text = ""
box.PlaceholderText = INV.SearchPlaceholder
box.PlaceholderColor3 = P.Ink:Lerp(P.Panel, 0.52)
box.TextColor3 = P.BodyText
box.FontFace = FONT
box.TextScaled = true
box.TextXAlignment = Enum.TextXAlignment.Right
-- False: typing the second letter of a query must not wipe the first, and a
-- player who taps the field to correct a typo expects their text still there.
box.ClearTextOnFocus = false
box.ZIndex = 59
kit:capText(box, 0.26)
box.Parent = search

------------------------------------------------------------------------ scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Scroll"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.AnchorPoint = Vector2.new(0, 0)
scroll.Position = UDim2.fromScale(CONTENT_X, 0.12)
scroll.Size = UDim2.fromScale(1 - CONTENT_X - INSET, 0.8)
scroll.ZIndex = 52
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
-- Inset rather than overlay, so AbsoluteWindowSize is the real content width and
-- eight tiles plus seven gutters still fit inside it.
scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
scroll.ScrollBarImageColor3 = P.Ink:Lerp(P.Panel, 0.25)
scroll.ScrollBarImageTransparency = 0.15
scroll.Parent = panel

local scrollPad = Instance.new("UIPadding")
scrollPad.Parent = scroll

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
-- Without this the list sorts by NAME, which put the divider above the shelf.
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

------------------------------------------------------------------------- tiles
-- A pet's art is the REAL MODEL in a ViewportFrame, not flat 2D. Uploads 403 in
-- this group-owned place and the Creator Store has no pet set worth using, but
-- the place already ships six rigged pets — and a viewport of the actual model is
-- what the reference game does anyway.
--
-- Framing is one rule for every pet: take the model's own bounding box, point a
-- fixed three-quarter camera at its centre, and back off far enough that the
-- longest axis fits the frame. That is why a 25-stud Bigfoot and a 4-stud ghostly
-- come out the same size on the tile with no per-pet tuning.
local PET_MODELS = ReplicatedStorage:WaitForChild(INV.PetModelFolder)
-- Looking down and across, the angle that reads as "a pet posing for its portrait"
-- rather than a side elevation. Y is lifted so we see a little of the top.
--
-- NEGATIVE Z is what puts the camera in FRONT of the pet. All six models in
-- PetModels face -Z, so the first pass -- which used +Z -- rendered every tile as
-- the back of a pet's head, and the ones without a tail read as featureless
-- blobs. A pet whose model faces elsewhere sets Yaw in GameConfig (degrees about
-- Y) rather than getting its own camera.
local PET_VIEW_DIR = Vector3.new(-0.6, 0.35, -1).Unit
local PET_FOV = 30
-- Slack around the fitted axis. Barely over 1: these are 70px tiles and a pet that
-- does not fill its frame reads as a bug, not as breathing room.
local PET_PAD = 1.06
-- Viewport lighting is NOT the place's lighting, and it starts near black. These
-- pets are dark-textured, so the viewport has to supply nearly all of the light
-- itself or every tile renders a silhouette.
local PET_AMBIENT = Color3.fromRGB(235, 235, 235)

-- Idle sway. The pets turn slowly back and forth rather than spinning: a full
-- spin reads as a turntable and drags the eye across the whole grid at once,
-- where a shallow sway just says the panel is alive. Each tile gets its own phase
-- so the grid never moves in lockstep, which is the thing that looks mechanical.
local SWAY_DEGREES = 13
local SWAY_PERIOD = 3.4
-- STRONG keys, pruned by hand in the loop below. A weak-keyed table was the
-- obvious choice and silently emptied itself within a frame: a parented Instance
-- is reachable from the DataModel, but nothing holds a reference to its LUA
-- wrapper, and a weak key is exactly the thing that does not count as one. The
-- symptom is the worst kind — no error, no warning, the loop running happily over
-- an empty table. Pruning on cam.Parent == nil does the same job honestly, and
-- Destroy() unparents descendants, so a rebuilt grid drops out on the next frame.
local swaying = {}

-- ponytail: one ViewportFrame per tile, ~28 of them on an open panel. Fine at this
-- roster size; if the grid ever pages past a few hundred, render each model once to
-- a pooled viewport and reuse it rather than giving every tile its own camera.
local function makePetIcon(pet)
	local source = pet.Model and PET_MODELS:FindFirstChild(pet.Model)
	if not source then
		-- No model named, or the folder does not have it: fall back to flat art
		-- rather than drawing an empty box.
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Image = pet.Icon or INV.PetIcon
		img.ScaleType = Enum.ScaleType.Fit
		return img
	end

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Icon"
	vp.BackgroundTransparency = 1
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	-- The tile's own gradient is the background; the model must not be lit by the
	-- place's Lighting or it picks up the world's time of day inside a GUI.
	vp.Ambient = PET_AMBIENT
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.5, -1, -0.5)

	local model = source:Clone()
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = PET_FOV
	local centre, size = model:GetBoundingBox()
	-- The LONGEST AXIS, not the box's diagonal. Fitting the diagonal is what
	-- guarantees nothing ever clips, and it is also why the first pass rendered
	-- every pet at a third of its frame: the diagonal of a 25x15x17 box is 33, so
	-- the camera backs off far enough to frame a sphere the pet never fills.
	-- Fitting the longest axis fills the tile, and the padding above covers the
	-- little the three-quarter angle adds.
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local dist = (radius * PET_PAD) / math.tan(math.rad(PET_FOV / 2))
	local dir = PET_VIEW_DIR
	if pet.Yaw then
		dir = CFrame.Angles(0, math.rad(pet.Yaw), 0) * dir
	end
	cam.CFrame = CFrame.lookAt(centre.Position + dir * dist, centre.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam

	swaying[cam] = {
		focus = centre.Position,
		dir = dir,
		dist = dist,
		-- Deterministic per pet, not random: a rebuild (a keystroke in the search
		-- box) must not make the whole grid jump to a new set of phases.
		phase = (#pet.Name * 0.7 + (pet.Power or 0) * 0.013) % (math.pi * 2),
	}
	return vp
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for cam, e in pairs(swaying) do
		if cam.Parent == nil then
			swaying[cam] = nil
		else
			local a = math.sin(t * (math.pi * 2 / SWAY_PERIOD) + e.phase)
				* math.rad(SWAY_DEGREES)
			local d = CFrame.Angles(0, a, 0) * e.dir
			cam.CFrame = CFrame.lookAt(e.focus + d * e.dist, e.focus)
		end
	end
end)

-- A pet floats. Behind it sits a soft-edged blob in its rarity colour — the whole
-- rarity read, now that there is no plate to carry it — then the power number
-- across the bottom in outlined white and the xN badge in the corner.
--
-- The blob is ONE image, not a stack of rounded frames: the panel shadow's
-- 30-layer technique gives a softer falloff but costs 30 instances a tile, and at
-- ~28 tiles that is nearly a thousand frames for a texture an 8KB image already
-- has. Tinted, so one neutral source serves all five rarities.
local function makeTile(pet, order)
	local grad = INV.Rarities[pet.Rarity] or P.Gold

	-- The grid positions this SLOT and the tile floats inside it at its own
	-- centre. A UIScale on a grid cell scales about the cell's AnchorPoint, which
	-- is (0,0), so a hover pop on the cell itself grows down and right and pushes
	-- the outer column straight out of the scroll's clip. Anchored centre inside a
	-- transparent slot, the pop spreads evenly into the gutter EDGE reserves.
	local slot = Instance.new("Frame")
	slot.Name = pet.Name
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = order
	slot.ZIndex = 53

	-- Invisible: it exists to be pressed and to carry the hover pop. Everything
	-- visible is a child, so the pop scales blob, pet, number and badge together.
	local tile = Instance.new("TextButton")
	tile.Name = "Tile"
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.ZIndex = 54

	-- Bigger than the tile: a soft edge that ENDS at the tile's bounds reads as a
	-- cropped square, which is the one thing a blob must not look like.
	local blob = Instance.new("ImageLabel")
	blob.Name = "Blob"
	blob.BackgroundTransparency = 1
	blob.AnchorPoint = Vector2.new(0.5, 0.5)
	blob.Position = UDim2.fromScale(0.5, 0.47)
	blob.Size = UDim2.fromScale(BLOB_SIZE, BLOB_SIZE)
	blob.Image = INV.PetBlob
	blob.ImageColor3 = grad[2]
	blob.ImageTransparency = BLOB_FADE
	blob.ScaleType = Enum.ScaleType.Fit
	blob.ZIndex = 54
	blob.Parent = tile

	local icon = makePetIcon(pet)
	-- High in the tile: the power number owns the bottom quarter.
	icon.Position = UDim2.fromScale(0.5, 0.41)
	icon.Size = UDim2.fromScale(0.76, 0.62)
	icon.ZIndex = 55
	icon.Parent = tile

	-- Omitted Power draws "??", which is what the reference does for its rarest
	-- pet. White with a heavy ink outline: navy would disappear into the saturated
	-- bottom half of a violet or a pink tile, and outlined white holds on all five.
	local power = Instance.new("TextLabel")
	power.Name = "Power"
	power.BackgroundTransparency = 1
	power.AnchorPoint = Vector2.new(0.5, 1)
	power.Position = UDim2.fromScale(0.5, 0.99)
	power.Size = UDim2.fromScale(0.92, 0.28)
	power.Text = pet.Power and tostring(pet.Power) or "??"
	power.TextColor3 = WHITE
	power.FontFace = FONT
	power.TextScaled = true
	power.ZIndex = 56
	kit:capText(power, 0.25)
	kit:outline(power, 2)
	power.Parent = tile

	-- One entry is one STACK, so the badge is the stack depth. Type with nothing
	-- behind it, like every other call-out in this game: a bordered plate in the
	-- corner of a tile that is itself a button gives two things to press.
	if (pet.Count or 1) > 1 then
		local badge = kit:tag("Count", "x" .. pet.Count, 56)
		-- WHITE, not the shop's gold Tag. On a plate the gold had a saturated field
		-- to sit against; floating over the panel it reads as a loose yellow mark.
		badge.TextColor3 = WHITE
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.fromScale(1.0, 0.01)
		badge.Size = UDim2.fromScale(0.52, 0.2)
		badge.TextXAlignment = Enum.TextXAlignment.Right
		kit:capText(badge, 0.2)
		badge.Parent = tile
	end

	-- Pop rather than tint, the same 0.12s Back Out the shop's cards use: a scale
	-- reads on touch, where there is no hover at all.
	local pop = Instance.new("UIScale")
	pop.Parent = tile

	-- Entrance: each tile springs up in turn. The delay is CAPPED rather than
	-- order * step, because rebuildGrid also runs on every keystroke in the search
	-- box — uncapped, the twentieth match would sit invisible for a third of a
	-- second after the letter that found it, which reads as lag, not as polish.
	pop.Scale = 0
	task.delay(math.min(order * ENTRY_STEP, ENTRY_MAX), function()
		if not pop.Parent then return end
		TweenService:Create(
			pop,
			TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)

	UIKit.audible(tile)
	tile.MouseEnter:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.08 }):Play()
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	tile.MouseButton1Down:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	tile.MouseButton1Click:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		onTilePressed(pet)
	end)

	tile.Parent = slot
	return slot
end

-- An empty shelf cell. Grey, rounded, a "+" in the middle — and a Frame, not a
-- button, because there is nothing to equip into it yet.
local function makePlus(order)
	local slot = Instance.new("Frame")
	slot.Name = "Empty" .. order
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = order
	slot.ZIndex = 53

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.78)
	tile.BorderSizePixel = 0
	tile.ZIndex = 54
	kit:corner(tile, TILE_CORNER)
	kit:stroke(tile, P.Ink:Lerp(P.Panel, 0.40), 2.4)

	local plus = Instance.new("TextLabel")
	plus.Name = "Plus"
	plus.BackgroundTransparency = 1
	plus.AnchorPoint = Vector2.new(0.5, 0.5)
	plus.Position = UDim2.fromScale(0.5, 0.5)
	plus.Size = UDim2.fromScale(0.64, 0.64)
	plus.Text = "+"
	plus.TextColor3 = P.Ink:Lerp(P.Panel, 0.30)
	plus.FontFace = FONT
	plus.TextScaled = true
	plus.ZIndex = 55
	kit:capText(plus, 0.62)
	plus.Parent = tile

	tile.Parent = slot
	return slot
end

------------------------------------------------------------- shelf and header
local equipped = {}
for _, pet in ipairs(readInventory()) do
	if pet.Equipped then table.insert(equipped, pet) end
end
local capacity = INV.EquippedCapacity or 10

local headRow = Instance.new("Frame")
headRow.Name = "ShelfHeader"
headRow.BackgroundTransparency = 1
headRow.Size = UDim2.new(1, 0, 0, 1)
headRow.LayoutOrder = 0
headRow.ZIndex = 53

local headLay = Instance.new("UIListLayout")
headLay.FillDirection = Enum.FillDirection.Horizontal
headLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
headLay.VerticalAlignment = Enum.VerticalAlignment.Center
headLay.SortOrder = Enum.SortOrder.LayoutOrder
headLay.Parent = headRow

-- AutomaticSize.X on both, not TextScaled: the count sits immediately after the
-- header rather than centred in a box of its own, so each label has to be exactly
-- as wide as its own glyphs. That means an explicit TextSize, resolved from the
-- cell edge in the layout pass.
local headLabel = Instance.new("TextLabel")
headLabel.Name = "Label"
headLabel.BackgroundTransparency = 1
headLabel.AutomaticSize = Enum.AutomaticSize.X
headLabel.Size = UDim2.new(0, 0, 1, 0)
headLabel.LayoutOrder = 1
headLabel.Text = INV.EquippedHeader
-- BLACK, not the palette's navy. The reference's header is plainly black, and on
-- a panel this pale the navy read as a washed-out grey rather than as a heading.
-- Not outlined: it sits on the panel body, not on a saturated tile.
headLabel.TextColor3 = P.Ink
headLabel.FontFace = FONT
headLabel.ZIndex = 54
headLabel.Parent = headRow

-- DERIVED, never stated: the number of + tiles and this count both fall out of
-- EquippedCapacity, so they cannot disagree. (The reference reads 10/10 with a +
-- tile also showing, which is the screenshot contradicting itself.)
local countLabel = Instance.new("TextLabel")
countLabel.Name = "Count"
countLabel.BackgroundTransparency = 1
countLabel.AutomaticSize = Enum.AutomaticSize.X
countLabel.Size = UDim2.new(0, 0, 1, 0)
countLabel.LayoutOrder = 2
countLabel.Text = ("%d/%d"):format(math.min(#equipped, capacity), capacity)
countLabel.TextColor3 = P.Cyan[2]
countLabel.FontFace = FONT
countLabel.ZIndex = 54
countLabel.Parent = headRow
headRow.Parent = scroll

local shelf = Instance.new("Frame")
shelf.Name = "Equipped"
shelf.BackgroundTransparency = 1
shelf.Size = UDim2.new(1, 0, 0, 0)
-- AutomaticSize.Y with the cells in OFFSET below. UIGridLayout cell sizes in
-- SCALE inside a frame with AutomaticSize.Y never resolve — each axis waits on
-- the other.
shelf.AutomaticSize = Enum.AutomaticSize.Y
shelf.LayoutOrder = 1
shelf.ZIndex = 53

local shelfGrid = Instance.new("UIGridLayout")
shelfGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
shelfGrid.SortOrder = Enum.SortOrder.LayoutOrder
shelfGrid.Parent = shelf

for i = 1, capacity do
	local cell = equipped[i] and makeTile(equipped[i], i) or makePlus(i)
	cell.Parent = shelf
end
shelf.Parent = scroll

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.72)
divider.BorderSizePixel = 0
divider.Size = UDim2.new(0.99, 0, 0, 2)
divider.LayoutOrder = 2
divider.ZIndex = 53
kit:corner(divider, 0.5)
divider.Parent = scroll

--------------------------------------------------------------- the main grid
local grid = Instance.new("Frame")
grid.Name = "AllPets"
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(1, 0, 0, 0)
grid.AutomaticSize = Enum.AutomaticSize.Y
grid.LayoutOrder = 3
grid.ZIndex = 53

local mainGrid = Instance.new("UIGridLayout")
mainGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
mainGrid.SortOrder = Enum.SortOrder.LayoutOrder
mainGrid.Parent = grid
grid.Parent = scroll

local noMatch = Instance.new("TextLabel")
noMatch.Name = "NoMatch"
noMatch.BackgroundTransparency = 1
noMatch.Size = UDim2.new(1, 0, 0, 1)
noMatch.LayoutOrder = 4
noMatch.Text = "No pet by that name."
noMatch.TextColor3 = P.BodyText
noMatch.FontFace = FONT
noMatch.TextScaled = true
noMatch.ZIndex = 53
noMatch.Visible = false
kit:capText(noMatch, 0.24)
noMatch.Parent = scroll

local relayout -- forward declaration; rebuildGrid runs a layout pass after it

local function sortedPets()
	local out = table.clone(readInventory())
	if sortKey == "Name" then
		table.sort(out, function(a, b) return a.Name < b.Name end)
	else
		-- Power descending. A pet with no Power — the reference's "??" rarest —
		-- sorts to the TOP rather than the bottom: it is the one you are proudest
		-- of, not the one worth least.
		table.sort(out, function(a, b)
			return (a.Power or math.huge) > (b.Power or math.huge)
		end)
	end
	return out
end

-- Destroy and rebuild rather than hide and reorder. Eighteen tiles is free, and
-- a visibility dance across two layouts is more code than this is.
function rebuildGrid()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	-- Case-insensitive substring on the pet's name, plain find (the fourth
	-- argument), so a query containing a Lua pattern character is a literal.
	local q = string.lower(box.Text)
	local n = 0
	for _, pet in ipairs(sortedPets()) do
		-- EQUIPPED PETS ARE NOT REPEATED HERE. They already have the shelf above
		-- the divider, and drawing them again made the first grid row a pixel copy
		-- of the shelf row — which reads as a rendering bug, not as a roster. The
		-- divider now separates two disjoint sets: what is equipped, and the rest.
		if not pet.Equipped
			and (q == "" or string.find(string.lower(pet.Name), q, 1, true))
		then
			n += 1
			makeTile(pet, n).Parent = grid
		end
	end
	noMatch.Visible = n == 0
	-- The new tiles' text caps are registered but unresolved until a layout pass.
	relayout()
end

box:GetPropertyChangedSignal("Text"):Connect(rebuildGrid)

------------------------------------------------------------------ header place
-- Every piece of header chrome is centred ON the panel's top edge, which is what
-- makes it overhang. On a short viewport that edge is inside the Roblox topbar:
-- measured on ShopPanel at 705x338, its title landed 100% under the topbar and
-- its close button — the only way to shut the panel — 90%. So the whole header
-- slides down together by however much it takes to clear the inset, and the
-- content band follows it. On desktop the shift is 0 and nothing moves.
--
-- GuiService:GetGuiInset() is re-read on every call rather than baked in, because
-- it is device-dependent and moves when the topbar is toggled. Same idiom as
-- HUDController.placeSettings().
local headerItems = {
	{ obj = kit.title, x = 0.075, y = 0 },
	-- Decorative and the tallest thing here by far; it rides along but does not
	-- get a vote, or the whole header would be pushed a fifth of the way down the
	-- panel to keep a rotated icon off the topbar.
	{ obj = kit.titleIcon, x = 0.018, y = 0, measure = false },
	{ obj = pill, x = 0.50, y = 0 },
	{ obj = search, x = 0.905, y = 0 },
	{ obj = close, x = 0.978, y = kit.closeY },
}

local function placeHeader()
	local s = math.max(panelScale.Scale, 0.01)
	local absH = panel.AbsoluteSize.Y
	if absH <= 1 then return end
	-- UIScale shrinks the panel about its centre, so the centre is the only
	-- UIScale-invariant reference; the top edge has to be derived from it.
	local panelH = absH / s
	local inset = GuiService:GetGuiInset().Y
	-- Real screen Y is AbsolutePosition.Y + inset, because the HUD sets
	-- IgnoreGuiInset and its local space therefore starts above the screen.
	local topS = panel.AbsolutePosition.Y + absH * 0.5 + inset - panelH * 0.5

	local rise, drop = 0, 0
	for _, it in ipairs(headerItems) do
		if it.obj and it.measure ~= false then
			local half = (it.obj.AbsoluteSize.Y / s) * 0.5
			rise = math.max(rise, half - it.y * panelH)
			drop = math.max(drop, half + it.y * panelH)
		end
	end

	local shift = math.max(0, (inset + TOPBAR_MARGIN) - (topS - rise)) / panelH
	for _, it in ipairs(headerItems) do
		if it.obj then
			it.obj.Position = UDim2.new(it.x, 0, it.y + shift, 0)
		end
	end

	local top = shift + drop / panelH + HEADER_GAP
	scroll.Position = UDim2.fromScale(CONTENT_X, top)
	-- The bottom inset is the same 2% of panel WIDTH as the sides, which in panel
	-- height units is that times the aspect.
	scroll.Size = UDim2.fromScale(1 - CONTENT_X - INSET, 1 - top - INSET * PANEL_ASPECT)
end

----------------------------------------------------------------------- layout
-- Resolved by relayout() from the scroll's real width; the hooks below close over
-- them. A tile is square, so the cell edge is the one unit everything in the
-- content is measured against, and it is what kit:relayout resolves text caps on.
local gutterW, cellW, edgeW = 0, 0, 0

kit:onLayout(function()
	scrollPad.PaddingTop = UDim.new(0, cellW * 0.05)
	-- Bottom padding is what keeps the last row from being cut flush against the
	-- panel edge, which reads as a rendering fault rather than as more content.
	scrollPad.PaddingBottom = UDim.new(0, cellW * 0.16)
	-- The side gutters the tiles' strokes and their hover pop live in.
	scrollPad.PaddingLeft = UDim.new(0, edgeW)
	scrollPad.PaddingRight = UDim.new(0, edgeW)
	list.Padding = UDim.new(0, cellW * 0.10)
	scroll.ScrollBarThickness = math.max(4, panel.AbsoluteSize.X * 0.014)

	headRow.Size = UDim2.new(1, 0, 0, math.max(1, cellW * 0.42))
	local headSize = math.max(12, cellW * 0.30)
	headLabel.TextSize = headSize
	countLabel.TextSize = headSize
	headLay.Padding = UDim.new(0, cellW * 0.10)

	for _, g in ipairs({ shelfGrid, mainGrid }) do
		g.CellSize = UDim2.fromOffset(cellW, cellW)
		g.CellPadding = UDim2.fromOffset(gutterW, math.floor(cellW * 0.12))
	end

	divider.Size = UDim2.new(0.99, 0, 0, math.max(2, math.floor(cellW * 0.035)))
	noMatch.Size = UDim2.new(1, 0, 0, noMatch.Visible and math.max(1, cellW * 0.6) or 1)
end)

function relayout()
	placeHeader()
	-- AbsoluteWindowSize, not AbsoluteSize: the scrollbar is inset, and eight
	-- tiles plus seven gutters fill the row almost exactly — a 12px error loses a
	-- column. AbsoluteWindowSize does NOT account for the scroll's own UIPadding,
	-- so the side gutters come off it by hand before anything is sized against it.
	local w = scroll.AbsoluteWindowSize.X
	if w <= 1 then return end
	edgeW = math.floor(w * EDGE)
	w -= edgeW * 2
	if w <= 1 then return end
	-- FLOORED, both of them, because UDim.Offset is an INTEGER and UIGridLayout
	-- rounds a fractional cell UP: one pixel over and the last column silently
	-- wraps onto its own row, which reads as a deliberate narrower layout.
	gutterW = math.floor(w * GUTTER)
	local cols = INV.Columns or 8
	local minCell = INV.MinCell or 64
	while true do
		cellW = math.floor((w - gutterW * (cols - 1)) / cols)
		-- Drop a column at a time rather than crush the cell: below MinCell the
		-- power number stops being readable well before the tile stops being
		-- tappable. The shop's own rule, in its own shape.
		if cellW >= minCell or cols <= 3 then break end
		cols -= 1
	end
	kit:relayout(cellW)
end

-- Both signals: the scroll's own is the direct one, and the HUD's is the one that
-- definitely moves when the viewport does.
scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
-- The header's own furniture carries a pixel MinSize for the tap floor, so its
-- height is not a pure fraction of the panel and placeHeader has to re-measure it
-- after the panel settles rather than at the same instant.
panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeHeader)

rebuildGrid()
task.defer(relayout)
