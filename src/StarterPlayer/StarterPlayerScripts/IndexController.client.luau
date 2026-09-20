--[[
	IndexController — fills StarterGui.HUD.IndexPanel.

	The Collection shape: a labelled rail down the left, a filter pill row and a
	search field across the top, a paged grid of every pet in the game, a
	collected counter over the grid's bottom-right, and a pager under it.

	It is the inventory's sibling and is built from the same parts on purpose.
	The shell — white ring, pale lip, stacked shadow, body gradient, title,
	close-button restyle, stroke and text-cap registries — is UIKit.chrome, the
	same call ShopController and InventoryController make. The pet art is the
	inventory's ViewportFrame technique, not flat icons, for the same reason it
	is there: this place is group-owned, uploaded images need an experience-access
	grant each, and the place already holds six rigged pets.

	What makes it an INDEX rather than an inventory is that it draws what the
	player has not got. An uncollected pet renders through the same flat pass the
	inventory uses for its outlines — every part recoloured, every texture
	stripped — which costs no new art and is what gives the counter something to
	count.

	NOTHING HERE IS AUTHORITATIVE. ServerScriptService is empty: there is no pet
	system and no DataStore, so the rail's other three categories are inert, the
	filter pills are inert, and pressing a tile pops it and does nothing else.
	The one seam where real data arrives is readRoster() below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local IDX = CONFIG.Index
local INV = CONFIG.Inventory
-- The SHOP's palette, deliberately, exactly as the inventory takes it. Three
-- panels in one game do not get three palettes.
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("IndexPanel")

------------------------------------------------------------------------ spec
-- Panel-relative throughout. Nothing below is a pixel except stroke weights,
-- the tap floor, and the cell minimum.

-- The reference is 1024x576 of which the panel is very nearly the whole frame.
-- Wider than the shop's 1.75 because it carries a four-wide grid AND a rail.
local PANEL_ASPECT = 1.78
local PANEL_CORNER = 0.045

-- The rail overhangs the panel's left edge, the way the inventory's does.
local RAIL_X, RAIL_Y = 0.115, 0.545
local RAIL_W, RAIL_H = 0.215, 0.86

-- The grid occupies everything right of the rail.
local GRID_X0, GRID_X1 = 0.255, 0.985
-- The grid stops short of the panel's bottom so the collected counter has its
-- own corner. The reference lets the two touch; at this cell size they collided
-- squarely with the twelfth pet instead.
local GRID_Y0, GRID_Y1 = 0.215, 0.845

-- Header furniture overhangs the top edge, so it is positioned against the
-- panel and drawn above it.
local SEARCH_Y = 0.045

local MIN_TAP_PX = 44

-- Drawn in bands so a child never sorts under its own parent: ZIndexBehavior is
-- Global on this HUD, so every one of these is absolute.
local Z_PANEL = 50
local Z_GRID = 52
local Z_CELL = 54
local Z_PET_STROKE = 55
local Z_PET = 56
local Z_TEXT = 57
local Z_RAIL = 58
local Z_HEADER = 62

-- Pet viewport constants, lifted from InventoryController so the two panels
-- frame the same models identically. Changing one without the other is what
-- makes the same pet look like two different pets across two screens.
local PET_MODELS = ReplicatedStorage:WaitForChild(INV.PetModelFolder)
local PET_VIEW_DIR = Vector3.new(-0.30, 0.16, -1).Unit
local PET_FOV = 30
local PET_PAD = 1.12
local PET_AMBIENT = Color3.fromRGB(235, 235, 235)
local PET_STROKE_COLOUR = Color3.fromRGB(28, 28, 40)

local EASE_POP = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

------------------------------------------------------------------------- data
-- THE SEAM. Returns the whole roster, each row flagged owned or not. Today that
-- is GameConfig: the player's stacks plus the undiscovered list. When something
-- owns pets for real, this is the only function that changes.
local function readRoster()
	local rows = {}
	for _, pet in ipairs(INV.Pets) do
		table.insert(rows, {
			Name = pet.Name,
			Rarity = pet.Rarity,
			Model = pet.Model,
			Yaw = pet.Yaw,
			Owned = (pet.Count or 0) > 0,
		})
	end
	for _, pet in ipairs(IDX.Undiscovered or {}) do
		table.insert(rows, {
			Name = pet.Name,
			Rarity = pet.Rarity,
			Model = pet.Model,
			Yaw = pet.Yaw,
			Owned = false,
		})
	end
	return rows
end

local roster = readRoster()

local function ownedCount()
	local n = 0
	for _, r in ipairs(roster) do
		if r.Owned then n += 1 end
	end
	return n
end

------------------------------------------------------------------------ chrome
local kit = UIKit.chrome(panel, {
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = IDX.Title,
	TitleIcon = IDX.TitleIcon,
	Palette = P,
})

-- Height-limited like the inventory's: UIKit sizes the title box off the shop's
-- much longer string, where WIDTH is what TextScaled lands on.
kit.title.Size = UDim2.fromScale(0.46, 0.082)
-- The book is a wider object than the crown UIKit's default sizing assumed, and
-- it left the title's first letter touching it — measured 0.073 against 0.075,
-- which is clearance in the numbers and a collision to the eye. Shrink the icon
-- and start the title further in.
local titleIcon = panel:FindFirstChild("TitleIcon")
if titleIcon then
	titleIcon.Size = UDim2.fromScale(0.088, 0.157)
end
kit.title.Position = UDim2.fromScale(0.105, 0)

-- The shop's own halftone sheet, at the inventory's much fainter strength. A
-- pale panel does not need the dots a saturated card does.
UIKit.halftone(panel, PANEL_CORNER, 0.88)

-- Shell furniture this layout has no use for. Hidden rather than destroyed,
-- matching how the inventory leaves Rule and Body.
local banner = panel:FindFirstChild("Banner")
if banner then banner.Visible = false end

--------------------------------------------------------------------- the rail
-- Labelled plates, not the inventory's icon cells, because the reference's are
-- and because four words carry categories four unfamiliar icons could not.
--
-- They are BUTTONS now and they really do select: the panel switches category,
-- the plate lights, and the grid shows that category's contents. Three of the
-- four have no contents, so what they show is an empty state saying so. That is
-- the difference between an inert control and a dishonest one — the inventory's
-- rail draws no selection precisely because its cells cannot do this.
local SELECTED_PAIR = INV.Rarities.Uncommon
local UNSELECTED_TOP = Color3.fromRGB(214, 216, 226)
local UNSELECTED_BOT = Color3.fromRGB(176, 178, 192)

local currentCategory = IDX.Rail[1] and IDX.Rail[1].Category or "Pets"
local rail = Instance.new("Frame")
rail.Name = "Rail"
rail.AnchorPoint = Vector2.new(0.5, 0.5)
rail.Position = UDim2.fromScale(RAIL_X, RAIL_Y)
rail.Size = UDim2.fromScale(RAIL_W, RAIL_H)
rail.BackgroundColor3 = P.Panel
rail.BorderSizePixel = 0
rail.ZIndex = Z_RAIL
kit:corner(rail, 0.07)
kit:stroke(rail, P.Ink, 2)
rail.Parent = panel

local railCells = {}

-- `fixed` is a pair the plate always wears whatever the selection is — Rewards
-- keeps its green, because it is a standing call to action rather than one of
-- the categories. Everything else swaps between the selected pair and grey.
local function paintPlate(cell, selected)
	local fixed = cell:GetAttribute("Fixed")
	local g = cell:FindFirstChildOfClass("UIGradient")
	local top, bot
	if fixed then
		top, bot = IDX.Reward.Grad[1], IDX.Reward.Grad[2]
	elseif selected then
		top, bot = SELECTED_PAIR[1], SELECTED_PAIR[2]
	else
		top, bot = UNSELECTED_TOP, UNSELECTED_BOT
	end
	cell.BackgroundColor3 = top
	if g then g.Color = ColorSequence.new(top, bot) end
end

local function makeRailPlate(name, text, fixedGrad, order)
	-- A TextButton, not a Frame. Its own Text stays empty — the label below is a
	-- separate child so it can carry the outline the plates need, and
	-- ApplyStrokeMode.Contextual on a button with no text draws nothing at all.
	local cell = Instance.new("TextButton")
	cell.Name = name
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BorderSizePixel = 0
	cell.LayoutOrder = order
	cell.ZIndex = Z_RAIL + 1
	if fixedGrad then cell:SetAttribute("Fixed", true) end
	kit:corner(cell, 0.22)
	kit:stroke(cell, P.Ink, 2.2)

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Parent = cell
	paintPlate(cell, false)

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = cell

	-- The house hover-and-click pair, one call, with the global hover cooldown
	-- that stops a sweep down the rail machine-gunning the tick.
	UIKit.audible(cell)
	cell.MouseButton1Down:Connect(function()
		TweenService:Create(scale, EASE_POP, { Scale = 0.95 }):Play()
	end)
	local function release()
		TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
	end
	cell.MouseButton1Up:Connect(release)
	cell.MouseLeave:Connect(release)

	-- The shop's own top-edge sheen, which is what makes these read as moulded
	-- plastic rather than as flat swatches.
	UIKit.gloss(cell, 0.42, 0.22, 0.7)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.88, 0.62)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.FontFace = FONT
	label.Text = text
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.ZIndex = Z_RAIL + 2
	kit:outline(label, 2)
	kit:capText(label, 0.30)
	label.Parent = cell

	cell.Parent = rail
	return cell
end

do
	-- The four categories fill the rail's upper run; Rewards is pinned to the
	-- bottom in its own colour, apart from them, as the reference has it.
	local n = #IDX.Rail
	-- Derived from the entry count, so adding a category needs no other edit.
	local padY, gap = 0.035, 0.022
	local cellH = ((1 - padY * 2) - gap * n) / (n + 1)

	for i, entry in ipairs(IDX.Rail) do
		local cell = makeRailPlate(entry.Name, entry.Name, nil, i)
		cell.AnchorPoint = Vector2.new(0.5, 0)
		cell.Position = UDim2.fromScale(0.5, padY + (i - 1) * (cellH + gap))
		cell.Size = UDim2.fromScale(0.88, cellH)
		cell:SetAttribute("Category", entry.Category)
		railCells[entry.Category] = cell
	end

	-- Rewards is NOT a category: it keeps its green whatever is selected and
	-- selecting it would mean showing an empty grid where a reward screen goes.
	-- It clicks and sounds like the rest, and lands nowhere, which is the honest
	-- shape of a button whose destination does not exist yet.
	local reward = makeRailPlate("Rewards", IDX.Reward.Name, IDX.Reward.Grad, n + 1)
	reward.AnchorPoint = Vector2.new(0.5, 1)
	reward.Position = UDim2.fromScale(0.5, 1 - padY)
	reward.Size = UDim2.fromScale(0.88, cellH)
	railCells.Rewards = reward
end

-- Assigned once refresh exists; the plates are built before it.
local selectCategory

-------------------------------------------------------------- the search field
-- Lifted wholesale from the inventory: same capsule, same ink stroke, same
-- placeholder treatment. It filters the grid live and nothing else.
local search = Instance.new("Frame")
search.Name = "Search"
search.AnchorPoint = Vector2.new(1, 0.5)
search.Position = UDim2.fromScale(0.86, SEARCH_Y)
search.Size = UDim2.fromScale(0.30, 0.105)
search.BackgroundColor3 = WHITE
search.BorderSizePixel = 0
search.ZIndex = Z_HEADER
kit:corner(search, 0.42)
kit:stroke(search, P.Ink, 2.6)
search.Parent = panel

local searchIcon = Instance.new("ImageLabel")
searchIcon.Name = "Glass"
searchIcon.BackgroundTransparency = 1
searchIcon.AnchorPoint = Vector2.new(0, 0.5)
searchIcon.Position = UDim2.fromScale(0.055, 0.5)
searchIcon.Size = UDim2.fromScale(0.6, 0.6)
searchIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
searchIcon.Image = IDX.SearchIcon
searchIcon.ImageColor3 = Color3.fromRGB(120, 124, 142)
searchIcon.ScaleType = Enum.ScaleType.Fit
searchIcon.ZIndex = Z_HEADER + 1
searchIcon.Parent = search

local box = Instance.new("TextBox")
box.Name = "Box"
box.BackgroundTransparency = 1
box.AnchorPoint = Vector2.new(1, 0.5)
box.Position = UDim2.fromScale(0.94, 0.5)
box.Size = UDim2.fromScale(0.72, 0.62)
box.FontFace = FONT
box.Text = ""
box.PlaceholderText = IDX.SearchPlaceholder
box.PlaceholderColor3 = Color3.fromRGB(168, 170, 186)
box.TextColor3 = P.Ink
box.TextXAlignment = Enum.TextXAlignment.Right
box.TextScaled = true
box.ClearTextOnFocus = false
box.ZIndex = Z_HEADER + 1
kit:capText(box, 0.26)
box.Parent = search

------------------------------------------------------------------------ tiles
-- The pet's own viewport. `flat` is the uncollected pass: the same model with
-- every part recoloured and every texture stripped, which is also what the
-- inventory uses behind each pet to make its outline.
local function buildPetViewport(entry, source, flat)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	-- A viewport ignores the place's Lighting and starts near black, so it has
	-- to carry its own. The flat pass wants no directional light at all or the
	-- silhouette comes out shaded and stops reading as one flat shape.
	vp.Ambient = flat and Color3.new(1, 1, 1) or PET_AMBIENT
	vp.LightColor = flat and Color3.new(0, 0, 0) or WHITE
	vp.LightDirection = Vector3.new(-0.5, -1, -0.5)

	local model = source:Clone()
	if flat then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				-- A UnionOperation IGNORES .Color unless UsePartColor is set: it
				-- renders the colours of the parts it was built from instead. Every
				-- face on these pets is a union — the dog's eyes, the cat's red
				-- ears — so without this the silhouettes came out staring, with
				-- .Color dutifully assigned and doing nothing.
				if d:IsA("UnionOperation") then d.UsePartColor = true end
				d.Color = flat
				d.Material = Enum.Material.SmoothPlastic
				-- A MeshPart keeps its texture through a Color change, so the
				-- silhouette would otherwise wear the pet's own face.
				if d:IsA("MeshPart") then d.TextureID = "" end
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			elseif d:IsA("SurfaceAppearance") then
				-- Clearing TextureID is NOT enough on its own: a SurfaceAppearance
				-- overrides it entirely and keeps drawing the pet's face on a
				-- silhouette that is supposed to be featureless.
				d:Destroy()
			end
		end
	end
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = PET_FOV
	-- Framed off the world-space bounding box. Do NOT PivotTo a staged model:
	-- resetting the pivot tips upright rigs onto their backs.
	local centre, size = model:GetBoundingBox()
	-- The LONGEST AXIS, not the diagonal: fitting the diagonal frames a sphere
	-- the pet never fills and renders everything at a third of its cell.
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local dist = (radius * PET_PAD) / math.tan(math.rad(PET_FOV / 2))
	local dir = PET_VIEW_DIR
	if entry.Yaw then
		dir = CFrame.Angles(0, math.rad(entry.Yaw), 0) * dir
	end
	cam.CFrame = CFrame.lookAt(centre.Position + dir * dist, centre.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- The inventory's scribble, rebuilt here off the same numbers in GameConfig so
-- the two panels cannot drift apart. Built once per colour and cloned: eleven
-- frames per cell times a full page is not something to construct twice.
local SC = IDX.Scribble
local scribbleCache = {}

local function makeScribble(colour)
	local cached = scribbleCache[colour]
	if cached then return cached:Clone() end

	-- A CANVASGROUP, not a Frame. The bars have to overlap to read as a scribble,
	-- and overlapping semi-transparent frames COMPOUND — every crossing comes out
	-- darker than its neighbours. A CanvasGroup renders its children to one buffer
	-- and applies the fade to the result, so the bars are opaque to each other.
	local box = Instance.new("CanvasGroup")
	box.Name = "Scribble"
	box.BackgroundTransparency = 1
	box.GroupTransparency = SC.Fade
	box.Rotation = SC.Angle
	-- The GROUP's band, and the BARS get it too further down. A CanvasGroup does
	-- NOT isolate its children from ZIndexBehavior.Global: at the default 1 the
	-- bars sort below the panel itself and never draw at all, with the group
	-- reporting Visible and a real AbsoluteSize the whole time.
	box.ZIndex = Z_CELL

	for i = 1, SC.Strokes do
		local t = (i - 1) / (SC.Strokes - 1)
		-- Longest through the middle, short at the ends, which is what gives the
		-- patch a blob silhouette rather than a rectangle.
		local w = SC.MaxWidth * (0.40 + 0.60 * math.sin(t * math.pi))
		-- Deterministic wobble, NOT math.random: the scribble has to be the same
		-- every time the panel opens or it flickers into a new shape per rebuild.
		local jitter = math.sin(i * 2.399) * 0.04

		local bar = Instance.new("Frame")
		bar.Name = "S" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5 + jitter, 0.12 + t * 0.76)
		bar.Size = UDim2.fromScale(w, SC.BarHeight)
		bar.BackgroundColor3 = colour
		bar.BorderSizePixel = 0
		-- Alternating tilt: one continuous back-and-forth stroke rather than a
		-- stack of separate lines.
		bar.Rotation = (i % 2 == 0) and SC.Tilt or -SC.Tilt
		bar.ZIndex = Z_CELL
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = bar
		bar.Parent = box
	end

	scribbleCache[colour] = box
	return box:Clone()
end

local function makeCell(entry, order)
	local cell = Instance.new("TextButton")
	cell.Name = entry.Name
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BackgroundColor3 = WHITE
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.LayoutOrder = order
	cell.ZIndex = Z_CELL

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = cell

	local pair = INV.Rarities[entry.Rarity]
	local source = entry.Model and PET_MODELS:FindFirstChild(entry.Model)

	if source then
		if entry.Owned then
			-- The collected pet, with the inventory's dark stamped contour behind
			-- it. Four flat copies offset on each axis, NOT one scaled copy:
			-- scaling offsets every edge radially from the image centre, which is
			-- fat far from centre and absent near it.
			local stroke = 0.018
			for _, off in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local s = buildPetViewport(entry, source, PET_STROKE_COLOUR)
				s.Name = "Stamp"
				s.Position = UDim2.fromScale(0.5 + off[1] * stroke, 0.5 + off[2] * stroke)
				s.ZIndex = Z_PET_STROKE
				s.Parent = cell
			end
			local vp = buildPetViewport(entry, source, nil)
			vp.Name = "Pet"
			vp.ZIndex = Z_PET
			vp.Parent = cell
		else
			-- Uncollected: the flat pass on its own, in the locked tint. No
			-- contour behind it — a silhouette does not need outlining, and the
			-- four extra viewports would be spent on something nobody can see.
			local vp = buildPetViewport(entry, source, IDX.LockedTint)
			vp.Name = "Locked"
			vp.ZIndex = Z_PET
			vp.Parent = cell
		end
	else
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.8, 0.8)
		img.Image = INV.PetIcon
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageColor3 = entry.Owned and WHITE or IDX.LockedTint
		img.ZIndex = Z_PET
		img.Parent = cell
	end

	-- The inventory's scribble, in the rarity colour, carrying the rarity read
	-- now that there is no plate. Uncollected pets get the flat grey one: the
	-- colour is part of the reward for finding the pet.
	local scribble = makeScribble(entry.Owned and (pair and pair[1] or WHITE) or SC.LockedColour)
	scribble.AnchorPoint = Vector2.new(0.5, 0.5)
	scribble.Position = UDim2.fromScale(0.5, 0.52)
	scribble.Size = UDim2.fromScale(0.88, 0.88)
	scribble.Parent = cell

	-- Press pop, and nothing else: there is nothing behind a tile to open.
	cell.MouseButton1Down:Connect(function()
		TweenService:Create(scale, EASE_POP, { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
	end
	cell.MouseButton1Up:Connect(release)
	cell.MouseLeave:Connect(release)

	return cell
end

------------------------------------------------------------------------- grid
local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.AnchorPoint = Vector2.new(0, 0)
grid.Position = UDim2.fromScale(GRID_X0, GRID_Y0)
grid.Size = UDim2.fromScale(GRID_X1 - GRID_X0, GRID_Y1 - GRID_Y0)
grid.ZIndex = Z_GRID
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
-- Left, not Center: a final row of two would otherwise float in the middle of
-- the grid instead of sitting under the row above it.
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
gridLayout.Parent = grid

-- Parented to the PANEL, not the grid. A UIGridLayout owns every GuiObject
-- child of its parent and there is no opting out: inside the grid this label was
-- laid out as an 85px cell and wrapped itself into a four-line column in the
-- top-left corner. It is positioned over the grid's span instead.
local noMatch = Instance.new("TextLabel")
noMatch.Name = "NoMatch"
noMatch.BackgroundTransparency = 1
noMatch.AnchorPoint = Vector2.new(0.5, 0.5)
noMatch.Position = UDim2.fromScale((GRID_X0 + GRID_X1) / 2, (GRID_Y0 + GRID_Y1) / 2)
noMatch.Size = UDim2.fromScale(0.5, 0.12)
noMatch.FontFace = FONT
noMatch.Text = "No pets match that."
noMatch.TextColor3 = Color3.fromRGB(150, 152, 168)
noMatch.TextScaled = true
noMatch.Visible = false
noMatch.ZIndex = Z_TEXT
kit:capText(noMatch, 0.24)
noMatch.Parent = panel

--------------------------------------------------------------- collected count
-- Over the grid's bottom-right, the way the reference has it: a small label
-- above a big cyan fraction.
local collected = Instance.new("Frame")
collected.Name = "Collected"
collected.BackgroundTransparency = 1
collected.AnchorPoint = Vector2.new(1, 1)
-- BELOW the grid, not over it. The reference lets the counter sit on the grid's
-- bottom-right corner, but at this cell size it landed squarely on the last
-- pet's feet — measured overlapping y 0.815..0.840 against a cell ending 0.840.
collected.Position = UDim2.fromScale(0.985, 0.995)
collected.Size = UDim2.fromScale(0.18, 0.15)
collected.ZIndex = Z_TEXT
collected.Parent = panel

local collectedLabel = Instance.new("TextLabel")
collectedLabel.Name = "Label"
collectedLabel.BackgroundTransparency = 1
collectedLabel.Position = UDim2.fromScale(0, 0)
collectedLabel.Size = UDim2.fromScale(1, 0.44)
collectedLabel.FontFace = FONT
collectedLabel.Text = IDX.CollectedLabel
collectedLabel.TextColor3 = WHITE
collectedLabel.TextScaled = true
collectedLabel.ZIndex = Z_TEXT
kit:outline(collectedLabel, 2.4)
kit:capText(collectedLabel, 0.28)
collectedLabel.Parent = collected

local collectedValue = Instance.new("TextLabel")
collectedValue.Name = "Value"
collectedValue.BackgroundTransparency = 1
collectedValue.Position = UDim2.fromScale(0, 0.42)
collectedValue.Size = UDim2.fromScale(1, 0.58)
collectedValue.FontFace = FONT
collectedValue.Text = string.format("%d/%d", ownedCount(), #roster)
collectedValue.TextColor3 = Color3.fromRGB(96, 214, 255)
collectedValue.TextScaled = true
collectedValue.ZIndex = Z_TEXT
kit:outline(collectedValue, 2.8)
kit:capText(collectedValue, 0.42)
collectedValue.Parent = collected

----------------------------------------------------------------------- pager
-- Overhangs the panel's bottom edge, centred under the grid.
local pager = Instance.new("Frame")
pager.Name = "Pager"
pager.AnchorPoint = Vector2.new(0.5, 0.5)
pager.Position = UDim2.fromScale(0.62, 0.975)
pager.Size = UDim2.fromScale(0.16, 0.10)
pager.BackgroundColor3 = WHITE
pager.BorderSizePixel = 0
pager.ZIndex = Z_HEADER
kit:corner(pager, 0.5)
kit:stroke(pager, P.Ink, 2.6)
pager.Parent = panel

local page = 1
local pageCount = 1

local function makeArrow(name, x, dir)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(x, 0.5)
	b.Size = UDim2.fromScale(0.34, 0.62)
	b.SizeConstraint = Enum.SizeConstraint.RelativeYY
	b.BackgroundTransparency = 1
	b.FontFace = FONT
	b.Text = dir < 0 and "\u{25C0}" or "\u{25B6}"
	b.TextColor3 = P.Ink
	b.TextScaled = true
	b.AutoButtonColor = false
	b.ZIndex = Z_HEADER + 1
	-- Same hover-and-click pair as the rail and every HUD tile.
	UIKit.audible(b)
	b.Parent = pager
	return b
end

local prevBtn = makeArrow("Prev", 0.2, -1)
local nextBtn = makeArrow("Next", 0.8, 1)

local pageLabel = Instance.new("TextLabel")
pageLabel.Name = "Page"
pageLabel.BackgroundTransparency = 1
pageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
pageLabel.Position = UDim2.fromScale(0.5, 0.5)
pageLabel.Size = UDim2.fromScale(0.34, 0.6)
pageLabel.FontFace = FONT
pageLabel.Text = "1"
pageLabel.TextColor3 = P.Ink
pageLabel.TextScaled = true
pageLabel.ZIndex = Z_HEADER + 1
kit:capText(pageLabel, 0.5)
pageLabel.Parent = pager

--------------------------------------------------------------------- filling
local cells = {}
-- Forward-declared: relayout calls this when the column count changes, and it is
-- defined below because it needs the pager and the grid to exist first.
local refresh

-- Only Pets has a roster. The rest resolve to nothing, and the grid says so
-- rather than drawing an empty rectangle.
local function categoryRoster()
	if currentCategory == "Pets" then return roster end
	return {}
end

local function matching()
	local rows = categoryRoster()
	local q = string.lower(box.Text or "")
	if q == "" then return rows end
	local out = {}
	for _, r in ipairs(rows) do
		if string.find(string.lower(r.Name), q, 1, true) then
			table.insert(out, r)
		end
	end
	return out
end

-- Filled by the layout. Columns are derived from the width now, so the page size
-- is not known until the panel has been measured — and it CHANGES when the
-- window does, which is why refresh is re-run from the layout.
local gridCols = 4

local function perPage()
	return gridCols * IDX.Rows
end

function refresh()
	for _, c in ipairs(cells) do c:Destroy() end
	table.clear(cells)

	local rows = matching()
	pageCount = math.max(1, math.ceil(#rows / perPage()))
	page = math.clamp(page, 1, pageCount)
	pageLabel.Text = tostring(page)

	-- Dimmed rather than hidden at the ends: a control that vanishes moves
	-- everything beside it, and the pager is a fixed capsule.
	prevBtn.TextTransparency = page > 1 and 0 or 0.72
	nextBtn.TextTransparency = page < pageCount and 0 or 0.72

	noMatch.Visible = #rows == 0
	-- Two different kinds of empty, and saying "no pets match that" on a
	-- category that has no pets at all would send the player hunting the search
	-- field for a mistake they did not make.
	if currentCategory ~= "Pets" then
		noMatch.Text = currentCategory .. " are coming soon."
	else
		noMatch.Text = "No pets match that."
	end

	local first = (page - 1) * perPage() + 1
	local last = math.min(first + perPage() - 1, #rows)
	for i = first, last do
		local cell = makeCell(rows[i], i)
		cell.Parent = grid
		table.insert(cells, cell)
	end

	local pool = categoryRoster()
	local have = 0
	for _, r in ipairs(pool) do
		if r.Owned then have += 1 end
	end
	collectedValue.Text = string.format("%d/%d", have, #pool)
end

-- Switching category resets to the first page: staying on page 3 of a category
-- that has one page would land on an empty grid that looks like a bug.
function selectCategory(category)
	if currentCategory == category then return end
	currentCategory = category
	for cat, cell in railCells do
		if cat ~= "Rewards" then
			paintPlate(cell, cat == category)
		end
	end
	page = 1
	refresh()
end

for cat, cell in railCells do
	if cat ~= "Rewards" then
		cell.Activated:Connect(function()
			selectCategory(cat)
		end)
		paintPlate(cell, cat == currentCategory)
	end
end

prevBtn.Activated:Connect(function()
	if page > 1 then page -= 1; refresh() end
end)
nextBtn.Activated:Connect(function()
	if page < pageCount then page += 1; refresh() end
end)
box:GetPropertyChangedSignal("Text"):Connect(function()
	page = 1
	refresh()
end)

----------------------------------------------------------------------- layout
-- A PLAIN function driven off the viewport, not a kit:onLayout hook. The hook
-- list is what kit:relayout runs, and this has to CALL kit:relayout to resolve
-- the text caps — registering it as a hook as well would have it re-enter
-- itself forever. InventoryController is wired the same way for the same reason.
local function relayout()
	local w = grid.AbsoluteSize.X
	local h = grid.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end

	local rows = IDX.Rows
	local gap = math.floor(w * 0.022)
	-- The ROW count fixes the cell and the columns follow from the width. Fixing
	-- both is what left a wide dead margin down the right of the grid: the cell
	-- came out of the tighter axis, which here is always the height, so four of
	-- them never spanned the panel.
	-- FLOORED. UDim offsets are integers and a fractional cell rounds UP, which
	-- overflows the row and drops a column onto the next line without a word.
	local cell = math.max(math.floor((h - gap * (rows - 1)) / rows), MIN_TAP_PX)
	if cell < IDX.MinCell then
		cell = math.max(IDX.MinCell, MIN_TAP_PX)
	end
	local cols = math.max(1, math.floor((w + gap) / (cell + gap)))

	gridLayout.CellSize = UDim2.fromOffset(cell, cell)
	gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	-- Wrap at the column count we sized FOR. Without this the layout fits as many
	-- cells per row as the width happens to allow, which need not be the same.
	gridLayout.FillDirectionMaxCells = cols

	kit:relayout(cell)

	-- A different column count is a different page size, so the page is rebuilt
	-- rather than left showing the previous one's worth.
	if cols ~= gridCols then
		gridCols = cols
		refresh()
	end
end

-- Both signals, as the inventory does: the grid's own is direct, the HUD's is
-- the one that definitely moves when the viewport does.
grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

refresh()
relayout()
