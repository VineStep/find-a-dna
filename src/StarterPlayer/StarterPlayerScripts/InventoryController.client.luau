--[[
	InventoryController — fills StarterGui.HUD.InventoryPanel.

	The Pet Simulator 99 inventory shape, rendered in this game's own surfacing:
	header chrome overhanging the panel's top edge (title, a search field, the
	close key), a rail overhanging its left edge, then a shelf of
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
local RAIL_X = 0.008      -- rail CENTRE, of panel width: just over half outside
-- The rail's own padding and gap, of its own box. Named rather than inlined
-- because the capsule's HEIGHT is solved from them below.
local RAIL_PAD_SIDE = 0.10
local RAIL_PAD_TB = 0.02
local RAIL_GAP = 0.012
-- Starts below the title icon, which hangs off the same corner and is drawn over
-- the rail (ZIndex 62 against 56) if the two are allowed to meet.
local RAIL_TOP = 0.11
-- The rail runs nearly the panel's full height, so the solve runs the other way
-- round from before: HEIGHT is the fixed thing, a cell is that height divided by
-- the roster, and the capsule's WIDTH is whatever makes a cell square. It used to
-- be width-first, with the height falling out of it — which is why the rail was a
-- narrow strip of small icons instead of the reference's full-height column.
local RAIL_H = 0.86
local RAIL_Y = RAIL_TOP + RAIL_H / 2
local RAIL_CELL = RAIL_H
	* (1 - RAIL_GAP * (#INV.Rail - 1) - RAIL_PAD_TB * 2)
	/ #INV.Rail
-- Panel-height units back into panel-WIDTH units, then out through the rail's own
-- side padding. The aspect divide is the whole reason this cannot be a constant.
local RAIL_W = RAIL_CELL / (PANEL_ASPECT * (1 - RAIL_PAD_SIDE * 2))
local CONTENT_X = 0.062   -- the scroll's left edge, of panel width
-- Side inset INSIDE the scroll, of its window width. Tiles are sized to fill the
-- row exactly, so the outer column's UIStroke — drawn outside the tile's bounds —
-- would be clipped by the scroll's edge, and the hover pop would then push a
-- visible slice of the tile itself out of view. This is the room both need.
local EDGE = 0.02
local GUTTER = 0.014      -- of content width
-- The rarity scribble behind a floating pet, as a fraction of the tile. Under 1:
-- the strokes are tilted, so their corners swing outside the box they are sized
-- in, and at 1.0 the widest ones clipped against the neighbouring tile.
local BLOB_SIZE = 0.96

-- The empty shelf slot. Smaller than a pet cell, with a short thick cross built
-- from two bars rather than a "+" glyph.
local PLUS_SIZE = 0.86
-- How far the moulded lip sits below the key, of the slot.
local PLUS_LIP = 0.035
local PLUS_CORNER = 0.22
local PLUS_ARM = 0.50
local PLUS_THICK = 0.155
-- How far the outline cross stands proud of the white one, in tile scale.
local PLUS_STROKE = 0.032

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
-- already carries it in StarterGui; the search field is the only other thing
-- here that can be typed into.
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
-- A white capsule overhanging the panel's left edge, running nearly its full
-- height, with one round icon cell per Rail entry. Every cell is inert ON
-- PURPOSE — there is nothing behind any of them yet — so they are Frames and not
-- buttons, and none is drawn as selected. A dead button that pops when you press
-- it is worse than a label, and a highlight on one of six cells that all do
-- nothing is worse still.
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
	-- CIRCLES. A square cell inside a capsule is two different corner radii in one
	-- control; round cells in a round column is one shape repeated.
	kit:corner(tile, 0.5)

	-- NO SELECTED STATE. Every cell is drawn the same. The highlight said "you are
	-- looking at Pets" while the other five cells did nothing at all when pressed,
	-- which promised navigation this panel does not have. When a rail cell can
	-- actually change what the grid shows, the highlight comes back with it.
	tile.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.88)

	if entry.Icon then
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

-------------------------------------------------------------------- sorting
-- The header's two-key sort pill is GONE. It was a POWER / A-Z segmented control
-- sitting between the title and the search field, and it read as clutter there
-- however it was styled — the reference puts two small icon cells in that slot,
-- not a pair of words, and this panel has neither glyph.
--
-- The order it chose is kept as the only order: power descending. Restoring the
-- control means putting a Sorts table back in GameConfig.Inventory and making
-- this a variable again; nothing else in this file reads it.
local sortKey = "Power"

local rebuildGrid -- forward declaration; the search box calls it

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
--
-- Nearly head-on. It was (-0.6, 0.35, -1), a three-quarter view from well above,
-- which showed a lot of flank and the top of the skull; a pet in an inventory
-- slot should be looking AT the player, turned just enough off-axis to have a
-- near side and a far side.
local PET_VIEW_DIR = Vector3.new(-0.30, 0.16, -1).Unit
local PET_FOV = 30
-- Slack around the fitted axis. Barely over 1: these are 70px tiles and a pet that
-- does not fill its frame reads as a bug, not as breathing room.
local PET_PAD = 1.06
-- Viewport lighting is NOT the place's lighting, and it starts near black. These
-- pets are dark-textured, so the viewport has to supply nearly all of the light
-- itself or every tile renders a silhouette.
local PET_AMBIENT = Color3.fromRGB(235, 235, 235)
-- The outline pass: how much larger its viewport is than the pet's, and what
-- colour it paints.
--
-- 1.06 was judged on a 300px probe viewport, where it is a healthy 9px contour.
-- On a real 60px tile the same 6% is under two pixels and the outline is all but
-- invisible — which is the whole trap with a proportional stroke: it is judged at
-- one size and shipped at another. Proportional is still right (the tile is
-- responsive), the number just has to be chosen at TILE size.
local PET_STROKE = 1.14
local PET_STROKE_COLOUR = Color3.fromRGB(28, 28, 40)

-- The tile's stack, bottom to top. Named because the pet is now two layers and a
-- tie between any two of these is resolved by tree order, which is not something
-- to leave to chance under ZIndexBehavior.Global.
local Z_SCRIBBLE = 54
local Z_PET_STROKE = 55
local Z_PET = 56
local Z_TEXT = 57

-- The pets DO NOT MOVE. An idle sway lived here — each tile turning slowly on its
-- own phase — and it was rejected: eighteen pets drifting at once is motion
-- competing with the grid the player is reading, not life. The entrance stagger
-- is the only animation left on a tile, and it ends.

-- ponytail: one ViewportFrame per tile, ~28 of them on an open panel. Fine at this
-- roster size; if the grid ever pages past a few hundred, render each model once to
-- a pooled viewport and reuse it rather than giving every tile its own camera.
-- One pass of a pet: the model, framed, in its own viewport. `flat` paints every
-- surface a single dark colour and kills its textures and lights, which is the
-- OUTLINE pass — see makePetIcon.
local function buildPetViewport(pet, source, flat)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	-- The tile's own surface is the background; the model must not be lit by the
	-- place's Lighting or it picks up the world's time of day inside a GUI.
	-- A flat pass wants NO directional light at all, or its silhouette comes out
	-- shaded and stops reading as an outline.
	vp.Ambient = flat and Color3.new(1, 1, 1) or PET_AMBIENT
	vp.LightColor = flat and Color3.new(0, 0, 0) or Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.5, -1, -0.5)

	local model = source:Clone()
	if flat then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = PET_STROKE_COLOUR
				d.Material = Enum.Material.SmoothPlastic
				-- A MeshPart keeps its texture through a Color change, so the
				-- silhouette would come out wearing the pet's own face.
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			end
		end
	end
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = PET_FOV
	local centre, size = model:GetBoundingBox()
	-- The LONGEST AXIS, not the box's diagonal. Fitting the diagonal is what
	-- guarantees nothing ever clips, and it is also why the first pass rendered
	-- every pet at a third of its frame: the diagonal of a 25x15x17 box is 33, so
	-- the camera backs off far enough to frame a sphere the pet never fills.
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local dist = (radius * PET_PAD) / math.tan(math.rad(PET_FOV / 2))
	local dir = PET_VIEW_DIR
	if pet.Yaw then
		dir = CFrame.Angles(0, math.rad(pet.Yaw), 0) * dir
	end
	cam.CFrame = CFrame.lookAt(centre.Position + dir * dist, centre.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

-- A pet and its outline. The outline is the SAME model rendered a second time,
-- flat dark, in a viewport scaled up a few percent behind the real one — its
-- silhouette is what shows around the edges.
--
-- It is done this way because the obvious ways do not work. A Highlight does not
-- render inside a ViewportFrame at all (tested: AlwaysOnTop, Occluded and no
-- highlight are pixel-identical). A UIStroke on the ViewportFrame outlines the
-- rectangle, not the pet. A true inverted hull needs flipped normals, which no
-- script API exposes. Scaling the GUI frame scales the rendered image with it,
-- which is the whole trick, and it costs no 3D maths.
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

	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)

	local outline = buildPetViewport(pet, source, true)
	outline.Name = "Stroke"
	outline.Size = UDim2.fromScale(PET_STROKE, PET_STROKE)
	outline.ZIndex = Z_PET_STROKE
	outline.Parent = holder

	local body = buildPetViewport(pet, source, false)
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = Z_PET
	body.Parent = holder

	return holder
end

-- A SCRIBBLE, drawn rather than fetched. A marker scribble is a stack of
-- overlapping strokes, so that is literally what this builds: rounded bars, each
-- tilted a little, each a different length and offset, densest through the middle
-- and tapering at both ends so the silhouette reads as a rough patch.
--
-- Drawn because it cannot be fetched. search_asset cannot surface Decals at all
-- in this place (every query returns Models), uploads 403 because the place is
-- group-owned, and generate_texture needs a mesh selection. A soft-edged circle
-- image was tried in its place and was rejected on sight — correctly; a clean
-- circle is not a scribble, it is a dot.
--
-- Built ONCE per rarity and cloned per tile: the arithmetic below is identical
-- for every pet of a given rarity, and doing it 28 times over is 28 times the
-- work for the same pixels.
--
-- ponytail: ~11 frames a tile, ~300 across an open panel. Fine here (measured at
-- a locked 60fps); if the grid ever pages past a few hundred tiles, bake one
-- scribble per rarity into an image and swap this for an ImageLabel.
local SCRIBBLE_STROKES = 11
-- Of the scribble box. Bars are far taller than the gap between them, so they
-- overlap heavily and the middle fills in solid the way a real scribble does.
local SCRIBBLE_BAR_H = 0.16
local SCRIBBLE_TILT = 6          -- degrees, alternating
-- The whole patch is tilted, which is what makes the strokes read as diagonal
-- hatching rather than as a stack of horizontal lines.
local SCRIBBLE_ANGLE = -32
-- Paired with the LIGHT end of the rarity gradient, which the bars are drawn in.
-- The two knobs have to move together and in opposite directions: light colour
-- plus the 0.7 that suited the dark one composites to within a few percent of the
-- white panel, and the scribble disappears completely. Light colour, less fade.
local SCRIBBLE_FADE = 0.42
-- Bars must stay inside the box: a CanvasGroup CLIPS its descendants to its own
-- bounds, and a scribble clipped flat on one side stops being a scribble.
local SCRIBBLE_MAX_W = 0.84

local scribbleCache = {}

local function makeScribble(colour)
	local cached = scribbleCache[colour]
	if cached then return cached:Clone() end

	-- A CANVASGROUP, not a Frame. The bars have to overlap for this to read as a
	-- scribble, and semi-transparent bars that overlap COMPOUND — every crossing
	-- came out darker than the strokes around it, so the patch read as a stack of
	-- separate translucent sticks instead of one scribbled-in shape. A CanvasGroup
	-- renders its children to one buffer first and applies GroupTransparency to
	-- the result, so the bars are opaque to each other and the fade lands once.
	local box = Instance.new("CanvasGroup")
	box.Name = "Scribble"
	box.BackgroundTransparency = 1
	box.GroupTransparency = SCRIBBLE_FADE
	box.Rotation = SCRIBBLE_ANGLE

	for i = 1, SCRIBBLE_STROKES do
		-- 0 at the top, 1 at the bottom.
		local t = (i - 1) / (SCRIBBLE_STROKES - 1)
		-- Bars are longest through the middle and short at the ends, which is what
		-- gives the patch a blob silhouette instead of a rectangle. sin() over the
		-- half-turn is that shape with no table of magic widths.
		local w = SCRIBBLE_MAX_W * (0.40 + 0.60 * math.sin(t * math.pi))
		-- Deterministic wobble, not math.random: the scribble must be the same
		-- every time the panel opens, or it flickers into a new shape per rebuild.
		local jitter = math.sin(i * 2.399) * 0.04

		local bar = Instance.new("Frame")
		bar.Name = "S" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Kept clear of the top and bottom edges by half a bar, so the rounded
		-- ends are not shaved off by the canvas.
		bar.Position = UDim2.fromScale(0.5 + jitter, 0.12 + t * 0.76)
		bar.Size = UDim2.fromScale(w, SCRIBBLE_BAR_H)
		bar.BackgroundColor3 = colour
		bar.BackgroundTransparency = 0
		bar.BorderSizePixel = 0
		-- Alternating tilt is what makes it read as one continuous back-and-forth
		-- stroke rather than as a stack of separate lines.
		bar.Rotation = (i % 2 == 0) and SCRIBBLE_TILT or -SCRIBBLE_TILT
		-- The GROUP's ZIndex, not 1. A CanvasGroup composites its descendants, but
		-- it does NOT isolate them from ZIndexBehavior.Global — the bars are still
		-- compared against every other element in the ScreenGui, and at 1 they sit
		-- below the panel itself (50) and never draw. The scribble vanished
		-- completely, with the CanvasGroup reporting Visible, a sane
		-- GroupTransparency and a real AbsoluteSize the whole time.
		bar.ZIndex = Z_SCRIBBLE
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = bar
		bar.Parent = box
	end

	scribbleCache[colour] = box
	return box:Clone()
end

-- A pet floats. Behind it sits the scribble in its rarity colour — the whole
-- rarity read, now that there is no plate to carry it — then the power number
-- across the bottom in outlined white and the xN badge in the corner.
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

	-- grad[1], the LIGHT end of the rarity pair, not grad[2]. The dark end is the
	-- colour a saturated plate is made of; with nothing on top of it, it sat as
	-- heavy behind the pet as the pet itself.
	local blob = makeScribble(grad[1])
	blob.AnchorPoint = Vector2.new(0.5, 0.5)
	blob.Position = UDim2.fromScale(0.5, 0.44)
	blob.Size = UDim2.fromScale(BLOB_SIZE, BLOB_SIZE)
	blob.ZIndex = Z_SCRIBBLE
	blob.Parent = tile

	local icon = makePetIcon(pet)
	-- High in the tile: the power number owns the bottom quarter.
	icon.Position = UDim2.fromScale(0.5, 0.41)
	-- Larger than the three-quarter view needed. Head-on, a pet presents its
	-- narrowest silhouette, so the same framing box renders it visibly smaller.
	icon.Size = UDim2.fromScale(0.84, 0.70)
	icon.ZIndex = Z_PET_STROKE
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
	power.ZIndex = Z_TEXT
	kit:capText(power, 0.25)
	kit:outline(power, 2)
	power.Parent = tile

	-- One entry is one STACK, so the badge is the stack depth. Type with nothing
	-- behind it, like every other call-out in this game: a bordered plate in the
	-- corner of a tile that is itself a button gives two things to press.
	if (pet.Count or 1) > 1 then
		local badge = kit:tag("Count", "x" .. pet.Count, Z_TEXT)
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

	-- A RAISED KEY, not a recess. It was drawn as a hole pressed into the shelf —
	-- dark at the top, pale at the bottom, no lip and no sheen — and it read as
	-- empty space rather than as something you could press. Everything that makes
	-- a moulded button in this game is now on it: a lip beneath, a bevel lit from
	-- its own top, a gloss sheet, and an ink edge.
	--
	-- It is still a Frame. Nothing can be equipped yet, and a button that pops
	-- when pressed and then does nothing is a worse lie than a flat plate. It
	-- becomes a TextButton on the day the equip remote exists.
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.AnchorPoint = Vector2.new(0.5, 0.5)
	lip.Position = UDim2.fromScale(0.5, 0.5 + PLUS_LIP)
	lip.Size = UDim2.fromScale(PLUS_SIZE, PLUS_SIZE)
	lip.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.52)
	lip.BorderSizePixel = 0
	lip.ZIndex = 53
	kit:corner(lip, PLUS_CORNER)
	lip.Parent = slot

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(PLUS_SIZE, PLUS_SIZE)
	tile.BorderSizePixel = 0
	tile.ZIndex = 54
	kit:corner(tile, PLUS_CORNER)
	kit:stroke(tile, P.Ink, 2.4)
	-- grad[1] on top, grad[2] below: the same call every pet tile used to make,
	-- in grey. Lit from its own top is what reads as standing proud.
	UIKit.bevel(tile, {
		P.Ink:Lerp(P.Panel, 0.94),
		P.Ink:Lerp(P.Panel, 0.66),
	})
	UIKit.gloss(tile, 0.46, PLUS_CORNER, 0.78)

	-- TWO BARS, not a "+" glyph. TextScaled on this font gives a thin, mean cross
	-- with a lot of air around it; the reference's is short, thick and centred,
	-- which is a shape the font simply does not have.
	--
	-- The outline is a SECOND CROSS DRAWN BEHIND, grown by the stroke width on
	-- every side — not a UIStroke. A UIStroke on each bar would draw its outline
	-- straight through the other bar where the two cross, leaving a seam across
	-- the middle of the plus. Two layers have no interior edges to show.
	local layers = {
		{ grow = PLUS_STROKE, colour = P.Ink:Lerp(P.Panel, 0.42), z = 55 },
		{ grow = 0, colour = WHITE, z = 56 },
	}
	for _, layer in ipairs(layers) do
		for i = 1, 2 do
			local long = PLUS_ARM + layer.grow * 2
			local short = PLUS_THICK + layer.grow * 2
			local bar = Instance.new("Frame")
			bar.Name = (layer.grow > 0 and "Edge" or "Plus") .. (i == 1 and "H" or "V")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = i == 1
				and UDim2.fromScale(long, short)
				or UDim2.fromScale(short, long)
			bar.BackgroundColor3 = layer.colour
			bar.BorderSizePixel = 0
			bar.ZIndex = layer.z
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.35, 0)
			c.Parent = bar
			bar.Parent = tile
		end
	end

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

-- The text pair lives in its OWN box, centred in the row, and the UIListLayout
-- goes on that box rather than on the row. A UIListLayout owns every GuiObject
-- child of its parent — there is no opting out — so rules parented beside it were
-- laid out as list items, came out zero-wide, and were counted into
-- AbsoluteContentSize on top of that.
local headCenter = Instance.new("Frame")
headCenter.Name = "Center"
headCenter.BackgroundTransparency = 1
headCenter.AnchorPoint = Vector2.new(0.5, 0.5)
headCenter.Position = UDim2.fromScale(0.5, 0.5)
headCenter.Size = UDim2.fromScale(0, 1)
headCenter.AutomaticSize = Enum.AutomaticSize.X
headCenter.ZIndex = 54
headCenter.Parent = headRow

local headLay = Instance.new("UIListLayout")
headLay.FillDirection = Enum.FillDirection.Horizontal
headLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
headLay.VerticalAlignment = Enum.VerticalAlignment.Center
headLay.SortOrder = Enum.SortOrder.LayoutOrder
headLay.Parent = headCenter

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
headLabel.Parent = headCenter

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
countLabel.Parent = headCenter

-- The reference runs a hairline out to each edge from the header text, which is
-- what makes "Your Best Pets" read as a section rule and not as a floating
-- caption. Two Frames rather than one behind the text: the text has no background
-- of its own to mask a line running under it, and giving it one would show as a
-- white patch the moment the panel's body gradient moved beneath it.
--
-- They are NOT in the UIListLayout — it centres its children, so a flexible rule
-- inside it would be centred too. They are absolutely placed, and their length is
-- solved in the layout hook from the layout's own measured content width.
local headRules = {}
-- Both resolved in the layout hook, where the cell edge is finally known.
local headRuleThick = 2
local headRuleGap = 12
for i = 1, 2 do
	local r = Instance.new("Frame")
	r.Name = i == 1 and "RuleLeft" or "RuleRight"
	r.AnchorPoint = Vector2.new(i == 1 and 0 or 1, 0.5)
	r.Position = UDim2.fromScale(i == 1 and 0 or 1, 0.5)
	r.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.74)
	r.BorderSizePixel = 0
	r.ZIndex = 53
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = r
	r.Parent = headRow
	headRules[i] = r
end

-- Sized from whatever the two boxes CURRENTLY measure, and re-run whenever
-- either changes. Computing it once inside the layout hook read an AbsoluteSize
-- that the hook had itself set microseconds earlier — Roblox resolves that at the
-- next render step, so the first pass saw 0 and the rules stayed zero-wide
-- forever. Anything that reads AbsoluteSize in the same frame it sets Size has
-- this bug; driving it off the change signal has no ordering to get wrong.
local function sizeHeadRules()
	local rowW = headRow.AbsoluteSize.X
	local half = headCenter.AbsoluteSize.X / 2
	if rowW <= 0 or half <= 0 then return end
	local len = math.max(0, rowW / 2 - half - headRuleGap)
	for _, r in ipairs(headRules) do
		r.Size = UDim2.fromOffset(len, headRuleThick)
	end
end

headRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeHeadRules)
headCenter:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeHeadRules)

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

	headRuleGap = cellW * 0.34
	headRuleThick = math.max(1, math.floor(cellW * 0.028))
	sizeHeadRules()

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
