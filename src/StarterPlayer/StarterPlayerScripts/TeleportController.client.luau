--[[
	TeleportController — fills StarterGui.HUD.TeleportPanel.

	A grid of places to jump to. This is the one HUD tile whose job can be done
	honestly with no server: a client owns its own character, so PivotTo on it is a
	real teleport, not a mock. Every card here works.

	Shell is UIKit.chrome, same call the shop, inventory, index and daily panels
	make, and the cards are the shop's card with a Travel pill where the price goes.

	The card the player is already standing on is drawn differently and does not
	travel — the destination list is short enough that a dead-end press on the
	place you are already at is the most likely misclick on the panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local TP = CONFIG.Teleport
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("TeleportPanel")

------------------------------------------------------------------------ spec
local GRID_COLS_MAX = 4

-- PANEL SHAPE BY ROW COUNT. The panel was 1.62 — a wide letterbox — because the
-- list was four places in one row. Adding The Cave and the Mineshaft made it six,
-- the grid wrapped, and a letterbox panel has nowhere to put a second row: the
-- cards overflowed the body top and bottom and drew over the title.
--
-- A roughly square panel is what two rows of the same PORTRAIT card needs. The
-- card shape is the thing being preserved here — squashing the cards to fit the
-- old panel is what makes them stop looking like the shop's cards, which is where
-- this whole family of cards comes from.
--
-- Indexed by rows, so four places still get exactly the panel they had. Past two
-- rows the aspect stays put and the cards shrink; at that point this list wants
-- the inventory's scrolling grid rather than a third entry here.
local ROW_ASPECT = { 1.62, 1.02 }

local PLACE_COUNT = #(TP.Places or {})
local GRID_ROWS = math.max(math.ceil(PLACE_COUNT / GRID_COLS_MAX), 1)

-- BALANCED. Six places at a hard four columns is a row of four and a row of two,
-- with half the second row empty — it fits, but it reads as a panel with two
-- places missing. Dividing the count by the rows it needs gives 3 + 3 instead,
-- and for any count it gives the squarest arrangement that still fits.
local GRID_FILL = math.ceil(PLACE_COUNT / GRID_ROWS)

local PANEL_ASPECT = ROW_ASPECT[math.min(GRID_ROWS, #ROW_ASPECT)]
local PANEL_CORNER = 0.045

local BLURB_Y = 0.16
local GRID_X0, GRID_X1 = 0.035, 0.965
local GRID_Y0, GRID_Y1 = 0.245, 0.945
-- Never more columns than there are places: with three destinations a four-column
-- grid left a visible empty cell, which reads as a place that failed to load.
local GRID_COLS = math.min(GRID_FILL, math.max(PLACE_COUNT, 1))

local MIN_TAP_PX = 44

local Z_CARD = 54
local Z_ART = 56
local Z_TEXT = 57
local Z_PILL = 58

-- How close counts as "already here". Generous: these are areas, not points, and
-- the whole purpose is to stop a press that would visibly do nothing.
local HERE_RADIUS = 90

-- BIGGER, once there is more than one row. The panel's StarterGui size was
-- chosen for a single row of four cards in a letterbox; two rows in the same box
-- makes every card small and the whole thing cramped. Set here rather than in the
-- tree because it depends on the place count, which lives in GameConfig.
if GRID_ROWS > 1 then
	panel.Size = UDim2.fromScale(0.62, 0.86)
end

local kit = UIKit.chrome(panel, {
	Palette = P,
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = TP.Title,
	TitleIcon = TP.TitleIcon,
})

----------------------------------------------------------------------- build
local blurb = Instance.new("TextLabel")
blurb.Name = "Blurb"
blurb.BackgroundTransparency = 1
blurb.AnchorPoint = Vector2.new(0.5, 0.5)
blurb.Position = UDim2.fromScale(0.5, BLURB_Y)
blurb.Size = UDim2.fromScale(0.8, 0.085)
blurb.Text = TP.Blurb or ""
blurb.TextColor3 = P.BodyText
blurb.FontFace = FONT
blurb.TextScaled = true
blurb.ZIndex = Z_TEXT
kit:capText(blurb, 0.22)
blurb.Parent = panel

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromScale(GRID_X0, GRID_Y0)
grid.Size = UDim2.fromScale(GRID_X1 - GRID_X0, GRID_Y1 - GRID_Y0)
grid.ZIndex = Z_CARD - 1
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
-- Pinned to the count the cell was sized FOR. A UIGridLayout otherwise fits as
-- many per row as the width happens to allow, which need not be the same number.
gridLayout.FillDirectionMaxCells = GRID_COLS
gridLayout.Parent = grid

-- THE TELEPORT. A client has network ownership of its own character, so this is
-- authoritative enough to be real — no remote, and nothing a server would need to
-- confirm. PivotTo moves the whole model including anything welded to it, which
-- SetPrimaryPartCFrame would not.
local function travel(place)
	local char = player.Character
	if not char or not char.PrimaryPart then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then return false end
	-- Released a little ABOVE the target. The world is blocky and landing exactly
	-- on a surface intersects it, which either wedges the character or fires them
	-- out sideways.
	char:PivotTo(CFrame.new(place.Pos + Vector3.new(0, TP.DropHeight or 6, 0)))
	return true
end

local function hereNow()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local best, bestD = nil, HERE_RADIUS
	for i, place in ipairs(TP.Places or {}) do
		local d = (root.Position - place.Pos).Magnitude
		if d < bestD then best, bestD = i, d end
	end
	return best
end

local cards = {}
local refresh

local function makeCard(index, place)
	local grad = place.Grad or P.Violet

	local card = Instance.new("TextButton")
	card.Name = "Place" .. index
	card.Text = ""
	card.AutoButtonColor = false
	card.LayoutOrder = index
	card.BackgroundColor3 = grad[1]
	card.BorderSizePixel = 0
	card.ZIndex = Z_CARD
	kit:corner(card, 0.1)
	kit:stroke(card, P.Ink, 2.6)
	UIKit.bevel(card, grad)
	UIKit.rays(card, 0.1, 0.5, 0.44)
	UIKit.halftone(card, 0.1)
	UIKit.gloss(card, 0.44, 0.1, 0.74)
	UIKit.castShadow(card, 0.04, 0.1, Z_CARD - 1, 0.5)

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.04)
	name.Size = UDim2.fromScale(0.9, 0.16)
	name.Text = place.Name or ""
	name.TextColor3 = WHITE
	name.FontFace = FONT
	name.TextScaled = true
	name.ZIndex = Z_TEXT
	kit:outline(name, 2.2)
	-- 0.105, not 0.135. TextScaled fills its box, and a cap is a CEILING: a short
	-- name like "Home" reaches it and a long one like "Fuse Machine" is limited by
	-- width first, so a generous cap makes the two render at visibly different
	-- sizes on identical cards. Low enough that every name is width-limited puts
	-- them all on one size.
	kit:capText(name, 0.105)
	name.Parent = card

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.40)
	-- Generous on both axes with a square constraint, which only ever SHRINKS, so
	-- the art takes the biggest square the card allows instead of being stretched.
	art.Size = UDim2.fromScale(0.5, 0.34)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = art
	art.Image = place.Icon or ""
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = Z_ART
	art.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Name = "Blurb"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.635)
	sub.Size = UDim2.fromScale(0.88, 0.17)
	sub.Text = place.Blurb or ""
	sub.TextColor3 = WHITE
	sub.FontFace = FONT
	sub.TextScaled = true
	sub.TextWrapped = true
	sub.ZIndex = Z_TEXT
	kit:outline(sub, 1.6)
	kit:capText(sub, 0.082)
	sub.Parent = card

	local here = hereNow() == index

	if here then
		-- No pill. Pressing "Travel" on the place you are standing in is the most
		-- likely misclick on a panel this small, and it would appear to do nothing
		-- at all — the screen would not even move. Saying so is better than a
		-- button that silently no-ops.
		local tag = kit:tag("Here", TP.HereLabel or "You are here", Z_TEXT)
		tag.AnchorPoint = Vector2.new(0.5, 1)
		tag.Position = UDim2.fromScale(0.5, 0.95)
		tag.Size = UDim2.fromScale(0.9, 0.16)
		kit:capText(tag, 0.11)
		tag.Parent = card
	else
		local pill = Instance.new("TextButton")
		pill.Name = "Go"
		pill.Text = TP.GoLabel or "Travel"
		pill.AutoButtonColor = false
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.fromScale(0.5, 0.95)
		pill.Size = UDim2.fromScale(0.8, 0.19)
		pill.BackgroundColor3 = P.Green[1]
		pill.BorderSizePixel = 0
		pill.TextColor3 = WHITE
		pill.FontFace = FONT
		pill.TextScaled = true
		pill.ZIndex = Z_PILL
		kit:corner(pill, 0.3)
		kit:stroke(pill, P.Ink, 2.2)
		UIKit.bevel(pill, P.Green)
		UIKit.gloss(pill, 0.5, 0.3, 0.6)
		kit:outline(pill, 2)
		kit:capText(pill, 0.13)
		UIKit.audible(pill)
		pill.MouseButton1Click:Connect(function()
			if travel(place) then
				-- The panel closes itself. Leaving it open over the place you just
				-- travelled to hides the thing you pressed the button to see.
				-- Second arg false = CLOSE. HUDOpenPanel deliberately refuses to
				-- toggle — a controller asking for its own panel must not shut one
				-- something else opened — so closing has to be asked for explicitly.
				local api = hud:FindFirstChild("HUDOpenPanel")
				if api then api:Invoke("Teleport", false) end
			end
		end)
		pill.Parent = card
	end

	local pop = Instance.new("UIScale")
	pop.Parent = card
	UIKit.audible(card)
	card.MouseEnter:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	card.Parent = grid
	table.insert(cards, card)
end

refresh = function()
	for _, c in ipairs(cards) do
		c:Destroy()
	end
	table.clear(cards)
	for i, place in ipairs(TP.Places or {}) do
		makeCard(i, place)
	end
end

------------------------------------------------------------------- layout
-- NOT registered with kit:onLayout: Kit:relayout runs every hook and then resolves
-- the text caps, so a function that is both a hook and calls kit:relayout at its
-- end re-enters itself forever. Every controller here is wired this way.
local function relayout()
	-- Divide the UIScale back out. HUDController pops the panel 0.8 -> 1 on every
	-- open with a Back ease that overshoots, so AbsoluteSize changes every frame of
	-- the animation — and a UIGridLayout CellSize is in OFFSET, so sizing it off the
	-- scaled box makes the cards re-flow while the panel is also being scaled. Two
	-- scalings fighting, which reads as the grid assembling itself as it opens.
	local k = math.max(panel.Scale.Scale, 0.01)
	local w = grid.AbsoluteSize.X / k
	local h = grid.AbsoluteSize.Y / k
	if w <= 0 or h <= 0 then return end

	local gap = math.floor(w * 0.022)
	-- FLOORED: UDim offsets are integers and UIGridLayout rounds a fractional cell
	-- UP, which overflows the row and silently drops a card onto the next line.
	local cw = math.max(math.floor((w - gap * (GRID_COLS - 1)) / GRID_COLS), MIN_TAP_PX)
	-- DIVIDED BY THE ROWS. This was math.floor(h) — the full grid height — which is
	-- correct for exactly one row and overflows by a whole card for two, top and
	-- bottom, because the grid is centred vertically.
	local ch = math.max(math.floor((h - gap * (GRID_ROWS - 1)) / GRID_ROWS), MIN_TAP_PX)

	gridLayout.CellSize = UDim2.fromOffset(cw, ch)
	gridLayout.CellPadding = UDim2.fromOffset(gap, gap)

	kit:relayout(ch)
	kit:rescale()
end

grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

-- "You are here" has to be right at the moment the panel opens, not at the moment
-- it was built — the player walks around between openings. Rebuilt on show rather
-- than polled: the position only matters while the panel is visible.
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then
		refresh()
		relayout()
	end
end)

refresh()
relayout()
