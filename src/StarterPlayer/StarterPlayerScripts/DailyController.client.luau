--[[
	DailyController — fills StarterGui.HUD.DailyPanel.

	The Daily Rewards ladder: six day cards in a 3x2 grid down the left, and a
	seventh on its own tall plate down the right, because the week's payoff should
	not look like another Tuesday.

	Built from UIKit.chrome like IndexController and InventoryController, and it
	takes the SHOP's palette for the same reason they do — four panels in one game
	do not get four palettes. The cards are the shop's card, minus the price row:
	bevel, burst, halftone, gloss, cast shadow, ink border, hover pop.

	NOTHING HERE IS AUTHORITATIVE. ServerScriptService is empty: there is no clock,
	no DataStore and no way to grant anything, so the streak is display state read
	from GameConfig and claiming advances it ON THIS CLIENT ONLY. Rejoin and it is
	back to GameConfig.Daily.Streak. The one seam where real data arrives is
	readStreak() below; every other thing on this screen already works off it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DAILY = CONFIG.Daily
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("DailyPanel")

------------------------------------------------------------------------ spec
-- Panel-relative throughout. Nothing here is a pixel except stroke weights and
-- the tap floor.

-- Squarer than the shop's 1.75: this panel carries a 3x2 grid beside a full-height
-- plate rather than a long scrolling list, and at 1.75 the cards came out as letter
-- slots with the art squeezed between two lines of type.
local PANEL_ASPECT = 1.55
local PANEL_CORNER = 0.045

-- The status line under the header, over the grid only — it belongs to the six
-- cards, not to the Day 7 plate, which says its own thing.
local STATUS_Y = 0.165

-- The grid's box. Its right edge is where the mega plate's gutter begins.
local GRID_X0, GRID_X1 = 0.030, 0.640
local GRID_Y0, GRID_Y1 = 0.235, 0.945
local GRID_COLS, GRID_ROWS = 3, 2

-- The Day 7 plate. Taller than the grid because it starts level with the status
-- line: it is the thing being advertised and it gets the full body height.
local MEGA_X0, MEGA_X1 = 0.665, 0.972
local MEGA_Y0, MEGA_Y1 = 0.140, 0.945

local MIN_TAP_PX = 44

-- Drawn in bands. ZIndexBehavior is Global on this HUD, so every one of these is
-- absolute and a child never sorts under its own parent by accident.
local Z_PANEL = 50
local Z_CARD = 54
local Z_ART = 56
local Z_TEXT = 57
local Z_PILL = 58

-- The claimable card's border. Gold, and thicker than the ink one it replaces,
-- because it is the only signal on the panel saying WHICH of seven things to
-- press — the Claim pill says "press", this says "here".
local READY_STROKE = 4.2

local kit = UIKit.chrome(panel, {
	Palette = P,
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = DAILY.Title,
	TitleIcon = DAILY.TitleIcon,
})

---------------------------------------------------------------------- state
-- Days already claimed; the claimable day is streak + 1. THE SEAM: when a server
-- exists this reads a replicated value instead of a config constant, and nothing
-- below has to change.
local function readStreak()
	return math.clamp(DAILY.Streak or 0, 0, 7)
end

local streak = readStreak()

local function stateOf(day)
	if day <= streak then return "claimed" end
	if day == streak + 1 then return "ready" end
	return "locked"
end

----------------------------------------------------------------------- build
local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.AnchorPoint = Vector2.new(0, 0)
grid.Position = UDim2.fromScale(GRID_X0, GRID_Y0)
grid.Size = UDim2.fromScale(GRID_X1 - GRID_X0, GRID_Y1 - GRID_Y0)
grid.ZIndex = Z_CARD - 1
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
-- Pinned. A UIGridLayout fits as many cells per row as the width allows, which
-- need not be the count the cell was sized FOR — three cards sized for three
-- columns will happily lay out four if the arithmetic leaves room.
gridLayout.FillDirectionMaxCells = GRID_COLS
gridLayout.Parent = grid

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale((GRID_X0 + GRID_X1) / 2, STATUS_Y)
status.Size = UDim2.fromScale(GRID_X1 - GRID_X0, 0.095)
-- Green, not the panel's body navy: it is a state readout, and the one state it
-- spends most of its life in is "there is something here for you".
-- WHITE under the rainbow, because a UIGradient MULTIPLIES what is under it: at
-- the green this used to be, every colour in the ramp came out a shade of green.
-- The plain-text state below sets its own colour and switches the ramp off.
status.TextColor3 = WHITE
status.FontFace = FONT
status.TextScaled = true
status.ZIndex = Z_TEXT
kit:outline(status, 3)
kit:capText(status, 0.26)

-- A UIGradient on a TextLabel tints the GLYPHS and leaves the UIStroke alone, so
-- the ink contour survives it and the text stays legible over the pale panel —
-- which is the whole reason a rainbow works here at all. Horizontal, so the full
-- ramp spans the line rather than banding each letter top to bottom.
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  92, 112)),
	ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 176,  64)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 232,  74)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB( 96, 222, 106)),
	ColorSequenceKeypoint.new(0.68, Color3.fromRGB( 74, 196, 255)),
	ColorSequenceKeypoint.new(0.84, Color3.fromRGB(150, 130, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 122, 216)),
})
local statusRamp = Instance.new("UIGradient")
statusRamp.Color = RAINBOW
statusRamp.Parent = status
status.Parent = panel

-- It travels. A static ramp across one short line reads as a gradient, not as a
-- rainbow; sliding the offset is what makes it obviously alive, and it is the one
-- thing on this panel that is meant to catch the eye. Offset wraps at 1, so it
-- steps back to -1 and runs again rather than snapping.
task.spawn(function()
	while statusRamp.Parent do
		-- Nothing to animate while the panel is shut, and this would otherwise run
		-- all session for a screen nobody is looking at.
		if panel.Visible and statusRamp.Enabled
			and not hud:GetAttribute("ReduceMotion") then
			local t = (tick() * 0.35) % 2 - 1
			statusRamp.Offset = Vector2.new(t, 0)
		end
		task.wait(1 / 30)
	end
end)

-- Rebuilt rather than mutated: six cards is nothing to recreate, and a claim
-- changes a card's whole shape (footer becomes a pill, border becomes gold, art
-- dims) rather than one property of it.
local cards = {}

local function clearCards()
	for _, c in ipairs(cards) do
		c:Destroy()
	end
	table.clear(cards)
end

local claim -- forward declared; the pill needs it and it needs refresh()
local refresh

local function makeCard(day, spec)
	local state = stateOf(day)
	local grad = spec.Grad or P.Violet

	local card = Instance.new("TextButton")
	card.Name = "Day" .. day
	card.Text = ""
	card.AutoButtonColor = false
	card.LayoutOrder = day
	card.BackgroundColor3 = grad[1]
	card.BorderSizePixel = 0
	card.ZIndex = Z_CARD
	kit:corner(card, 0.115)
	-- Gold and heavier on the one card that can be pressed. Everything else keeps
	-- the ink border every plate in this game wears.
	kit:stroke(card, state == "ready" and P.Tag or P.Ink, state == "ready" and READY_STROKE or 2.6)
	UIKit.bevel(card, grad)
	UIKit.rays(card, 0.115, 0.5, 0.52)
	UIKit.halftone(card, 0.115)
	UIKit.gloss(card, 0.46, 0.115, 0.74)
	UIKit.castShadow(card, 0.045, 0.115, Z_CARD - 1, 0.5)

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.045)
	name.Size = UDim2.fromScale(0.88, 0.235)
	name.Text = spec.Name or ""
	name.TextColor3 = WHITE
	name.FontFace = FONT
	name.TextScaled = true
	-- Wrapped: "Random Fruits" is two words and the reference stacks them rather
	-- than shrinking the type to fit one line across a card this narrow.
	name.TextWrapped = true
	name.ZIndex = Z_TEXT
	kit:outline(name, 2.2)
	kit:capText(name, 0.15)
	name.Parent = card

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.505)
	-- Generous both ways with a square constraint, which only ever SHRINKS: the
	-- art then takes the biggest square the card allows instead of being stretched
	-- into the card's own oblong.
	art.Size = UDim2.fromScale(0.62, 0.46)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = art
	art.Image = spec.Icon or ""
	-- ImageColor3 MULTIPLIES, so a light tint recolours the art and keeps both its
	-- own shading and its own black outline. See GameConfig.Daily.Days.
	if spec.Tint then art.ImageColor3 = spec.Tint end
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = Z_ART
	art.Parent = card

	-- The quantity, over the art's bottom-right corner. A yellow outlined tag with
	-- nothing behind it, the same treatment ribbons get in the shop — as a bordered
	-- pill it would be a second button-shaped thing on a card that is a button.
	if spec.Qty then
		local qty = kit:tag("Qty", spec.Qty, Z_TEXT)
		qty.AnchorPoint = Vector2.new(0.5, 0.5)
		qty.Position = UDim2.fromScale(0.755, 0.615)
		qty.Size = UDim2.fromScale(0.36, 0.17)
		kit:capText(qty, 0.17)
		qty.Parent = card
	end

	-- The footer is the state. "Day N" while it waits, a pressable green pill on
	-- the day that is ready, and the claimed line once it has been taken.
	if state == "ready" then
		local pill = Instance.new("TextButton")
		pill.Name = "Claim"
		pill.Text = DAILY.ClaimLabel or "Claim!"
		pill.AutoButtonColor = false
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.fromScale(0.5, 0.955)
		pill.Size = UDim2.fromScale(0.78, 0.215)
		pill.BackgroundColor3 = P.Green[1]
		pill.BorderSizePixel = 0
		pill.TextColor3 = WHITE
		pill.FontFace = FONT
		pill.TextScaled = true
		pill.ZIndex = Z_PILL
		kit:corner(pill, 0.3)
		kit:stroke(pill, P.Ink, 2.4)
		UIKit.bevel(pill, P.Green)
		UIKit.gloss(pill, 0.5, 0.3, 0.6)
		kit:outline(pill, 2.2)
		kit:capText(pill, 0.17)
		UIKit.audible(pill)
		pill.MouseButton1Click:Connect(function()
			claim(day)
		end)
		pill.Parent = card
	else
		local foot = Instance.new("TextLabel")
		foot.Name = "Footer"
		foot.BackgroundTransparency = 1
		foot.AnchorPoint = Vector2.new(0.5, 1)
		foot.Position = UDim2.fromScale(0.5, 0.965)
		foot.Size = UDim2.fromScale(0.9, 0.185)
		foot.Text = state == "claimed" and (DAILY.ClaimedLabel or "Claimed")
		                               or string.format(DAILY.DayLabel or "Day %d", day)
		foot.TextColor3 = WHITE
		foot.FontFace = FONT
		foot.TextScaled = true
		foot.ZIndex = Z_TEXT
		kit:outline(foot, 2.4)
		kit:capText(foot, 0.155)
		foot.Parent = card
	end

	-- A claimed card is DIMMED, not hidden or greyed by recolouring: it keeps its
	-- own gradient underneath so the week still reads as a row of different
	-- rewards, and the sheet says plainly that this one is spent. Parented last so
	-- it covers the art and the footer, and non-interactive so the card still pops.
	if state == "claimed" then
		local spent = Instance.new("Frame")
		spent.Name = "Spent"
		spent.BackgroundColor3 = P.Ink
		spent.BackgroundTransparency = 0.52
		spent.BorderSizePixel = 0
		spent.AnchorPoint = Vector2.new(0.5, 0.5)
		spent.Position = UDim2.fromScale(0.5, 0.5)
		spent.Size = UDim2.fromScale(1, 1)
		spent.ZIndex = Z_PILL
		kit:corner(spent, 0.115)
		spent.Parent = card
	end

	-- The reference pops its cards rather than tinting them, and a scale reads on
	-- touch too, where there is no hover at all.
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
	card.MouseButton1Down:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
	end)
	card.MouseButton1Click:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	card.Parent = grid
	table.insert(cards, card)
	return card
end

------------------------------------------------------------------- day seven
-- Built ONCE, unlike the six cards: nothing about it changes with the streak
-- except its border and its footer, and those are cheap to set in place.
local mega = Instance.new("Frame")
mega.Name = "DaySeven"
mega.BackgroundColor3 = (DAILY.Mega and DAILY.Mega.Grad or P.Violet)[1]
mega.BorderSizePixel = 0
mega.AnchorPoint = Vector2.new(0, 0)
mega.Position = UDim2.fromScale(MEGA_X0, MEGA_Y0)
mega.Size = UDim2.fromScale(MEGA_X1 - MEGA_X0, MEGA_Y1 - MEGA_Y0)
mega.ZIndex = Z_CARD
-- Clipped, like the shop's offer plate and for the same reason: the burst and the
-- halftone are square sheets that would otherwise show their corners outside the
-- radius. The cast shadow therefore cannot live inside it — see below.
mega.ClipsDescendants = true
mega.Parent = panel

local megaStroke, megaFooter, megaClaim
do
	local M = DAILY.Mega or {}
	local grad = M.Grad or P.Violet
	kit:corner(mega, 0.085)
	megaStroke = kit:stroke(mega, P.Ink, 3)
	UIKit.bevel(mega, grad)
	-- Centred on the art, not on the plate: a burst whose centre sits off the
	-- object it lights reads as a second light source.
	UIKit.rays(mega, 0.085, 0.5, 0.57)
	UIKit.halftone(mega, 0.085, 0.88)
	UIKit.gloss(mega, 0.42, 0.085, 0.66)

	-- The light rim inside the ink border — the moulded edge the panel itself
	-- carries. An instance holds only ONE UIStroke and the plate's is already the
	-- ink border, so the highlight has to be its own inset frame.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.BackgroundTransparency = 1
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -7, 1, -7)
	rim.ZIndex = Z_PILL
	kit:corner(rim, 0.085)
	kit:stroke(rim, WHITE, 2).Transparency = 0.6
	rim.Parent = mega

	-- "OP REWARDS!" as two labels in a row so the halves can take different
	-- colours, which is what the reference does and what stops it reading as one
	-- long yellow shout.
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.BackgroundTransparency = 1
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.035)
	head.Size = UDim2.fromScale(0.94, 0.085)
	head.ZIndex = Z_TEXT
	local hrow = Instance.new("UIListLayout")
	hrow.FillDirection = Enum.FillDirection.Horizontal
	hrow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hrow.VerticalAlignment = Enum.VerticalAlignment.Center
	hrow.SortOrder = Enum.SortOrder.LayoutOrder
	hrow.Padding = UDim.new(0.02, 0)
	hrow.Parent = head

	local function headPart(text, colour, order)
		if not text or text == "" then return end
		local t = Instance.new("TextLabel")
		t.Name = "Head" .. order
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.new(0, 0, 1, 0)
		t.LayoutOrder = order
		t.Text = text
		t.TextColor3 = colour
		t.FontFace = FONT
		t.TextScaled = true
		t.ZIndex = Z_TEXT
		kit:outline(t, 2.6)
		kit:capText(t, 0.2)
		t.Parent = head
	end
	headPart(M.HeaderLead, P.Cyan[1], 1)
	headPart(M.HeaderRest, P.Tag, 2)
	head.Parent = mega

	-- The contents, one line each, stacked under the header.
	if M.Lines then
		local lines = Instance.new("Frame")
		lines.Name = "Lines"
		lines.BackgroundTransparency = 1
		lines.AnchorPoint = Vector2.new(0.5, 0)
		lines.Position = UDim2.fromScale(0.5, 0.125)
		lines.Size = UDim2.fromScale(0.94, 0.125)
		lines.ZIndex = Z_TEXT
		local col = Instance.new("UIListLayout")
		col.FillDirection = Enum.FillDirection.Vertical
		col.HorizontalAlignment = Enum.HorizontalAlignment.Center
		col.SortOrder = Enum.SortOrder.LayoutOrder
		col.Parent = lines
		for i, text in ipairs(M.Lines) do
			local t = Instance.new("TextLabel")
			t.Name = "Line" .. i
			t.BackgroundTransparency = 1
			t.LayoutOrder = i
			t.Size = UDim2.fromScale(1, 1 / #M.Lines)
			t.Text = text
			t.TextColor3 = WHITE
			t.FontFace = FONT
			t.TextScaled = true
			t.ZIndex = Z_TEXT
			kit:outline(t, 2)
			kit:capText(t, 0.115)
			t.Parent = lines
		end
		lines.Parent = mega
	end

	-- The crown sits behind and below the egg so the two read as a pile rather
	-- than as two icons side by side. Parented FIRST, so the egg draws over it.
	if M.ArtExtra then
		local extra = Instance.new("ImageLabel")
		extra.Name = "ArtExtra"
		extra.BackgroundTransparency = 1
		extra.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Big enough to be an object. At 0.30 it sat almost entirely behind the egg
		-- and read as a smudge on its shoulder rather than as a second prize.
		extra.Position = UDim2.fromScale(0.72, 0.745)
		extra.Size = UDim2.fromScale(0.60, 0.34)
		local ear = Instance.new("UIAspectRatioConstraint")
		ear.AspectRatio = 1
		ear.Parent = extra
		extra.Image = M.ArtExtra
		extra.ScaleType = Enum.ScaleType.Fit
		extra.ZIndex = Z_ART - 1
		extra.Parent = mega
	end

	if M.Art then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.42, 0.545)
		art.Size = UDim2.fromScale(0.78, 0.40)
		local aar = Instance.new("UIAspectRatioConstraint")
		aar.AspectRatio = 1
		aar.Parent = art
		art.Image = M.Art
		if M.ArtTint then art.ImageColor3 = M.ArtTint end
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = Z_ART
		art.Parent = mega
	end

	local seven = Instance.new("TextLabel")
	seven.Name = "Footer"
	seven.BackgroundTransparency = 1
	seven.AnchorPoint = Vector2.new(0.5, 1)
	seven.Position = UDim2.fromScale(0.5, 0.965)
	seven.Size = UDim2.fromScale(0.9, 0.135)
	seven.Text = M.DayLabel or "Day 7"
	seven.TextColor3 = WHITE
	seven.FontFace = FONT
	seven.TextScaled = true
	seven.ZIndex = Z_TEXT
	kit:outline(seven, 3)
	kit:capText(seven, 0.26)
	-- The reference runs this one through a colour ramp rather than leaving it
	-- white, which is the whole difference between "day seven" and "DAY SEVEN".
	-- A UIGradient on a TextLabel tints the glyphs and leaves the outline alone,
	-- so the ink contour survives it.
	local ramp = Instance.new("UIGradient")
	ramp.Rotation = 90
	ramp.Color = ColorSequence.new(WHITE, P.Tag)
	ramp.Parent = seven
	seven.Parent = mega
	megaFooter = seven

	-- Day seven swaps its label for a Claim pill exactly as a card does. It costs
	-- the plate its big "Day 7", which is the whole identity of the thing — but a
	-- card that is ready and offers nothing to press is worse, and the grid already
	-- establishes that the claimable day shows a pill where its day used to be.
	-- Built once and toggled, because unlike the cards this plate is not rebuilt.
	local pill = Instance.new("TextButton")
	pill.Name = "Claim"
	pill.Text = DAILY.ClaimLabel or "Claim!"
	pill.AutoButtonColor = false
	pill.Visible = false
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.fromScale(0.5, 0.955)
	pill.Size = UDim2.fromScale(0.82, 0.13)
	pill.BackgroundColor3 = P.Green[1]
	pill.BorderSizePixel = 0
	pill.TextColor3 = WHITE
	pill.FontFace = FONT
	pill.TextScaled = true
	pill.ZIndex = Z_PILL
	kit:corner(pill, 0.3)
	kit:stroke(pill, P.Ink, 2.6)
	UIKit.bevel(pill, P.Green)
	UIKit.gloss(pill, 0.5, 0.3, 0.6)
	kit:outline(pill, 2.4)
	kit:capText(pill, 0.2)
	UIKit.audible(pill)
	pill.MouseButton1Click:Connect(function()
		claim(7)
	end)
	pill.Parent = mega
	megaClaim = pill
end

-- OUTSIDE the plate, because the plate clips: a shadow parented into a
-- ClipsDescendants element is offset below its bottom edge and clipped away
-- entirely. A transparent slot exactly over the plate carries it instead.
do
	local slot = Instance.new("Frame")
	slot.Name = "DaySevenShadow"
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = mega.AnchorPoint
	slot.Position = mega.Position
	slot.Size = mega.Size
	slot.ZIndex = Z_CARD - 1
	UIKit.castShadow(slot, 0.022, 0.085, Z_CARD - 1, 0.55)
	slot.Parent = panel
end

------------------------------------------------------------------- refresh
refresh = function()
	clearCards()
	for day, spec in ipairs(DAILY.Days or {}) do
		makeCard(day, spec)
	end

	local ready = streak < 7
	status.Text = ready and (DAILY.ReadyLabel or "") or (DAILY.WaitingLabel or "")
	-- Rainbow only while there is something to claim. "Come back tomorrow" is not
	-- a call to action and a rainbow on it would say the opposite of what it means.
	statusRamp.Enabled = ready
	status.TextColor3 = ready and WHITE or P.BodyText

	-- Day seven only ever changes in these two ways, so it is set in place rather
	-- than rebuilt with the grid.
	local sevenState = stateOf(7)
	megaClaim.Visible = sevenState == "ready"
	megaFooter.Visible = sevenState ~= "ready"
	megaStroke.Color = sevenState == "ready" and P.Tag or P.Ink
	megaStroke.Thickness = math.max(1,
		(sevenState == "ready" and READY_STROKE or 3) * kit.strokeK)
	local spent = mega:FindFirstChild("Spent")
	if sevenState == "claimed" and not spent then
		spent = Instance.new("Frame")
		spent.Name = "Spent"
		spent.BackgroundColor3 = P.Ink
		spent.BackgroundTransparency = 0.52
		spent.BorderSizePixel = 0
		spent.Size = UDim2.fromScale(1, 1)
		spent.ZIndex = Z_PILL
		kit:corner(spent, 0.085)
		spent.Parent = mega
	elseif sevenState ~= "claimed" and spent then
		spent:Destroy()
	end
end

claim = function(day)
	-- CLIENT-ONLY, and deliberately loud about it: there is no remote to fire and
	-- nothing is granted. All this does is advance the local streak so the ladder
	-- can be seen working. When a server exists this fires a remote and waits for
	-- the replicated streak to come back instead of moving it itself.
	if day ~= streak + 1 then return end
	streak = math.min(streak + 1, 7)
	refresh()
end

------------------------------------------------------------------- layout
-- NOT registered with kit:onLayout. Kit:relayout runs every registered hook and
-- then resolves the text caps, so a function that is both a hook AND calls
-- kit:relayout at its end re-enters itself forever. Every other controller here
-- is wired the same way: a plain function on the AbsoluteSize signals that calls
-- kit:relayout once.
local function relayout()
	-- DIVIDE THE UISCALE BACK OUT, exactly as Kit:rescale does for stroke weights
	-- and for the same reason. HUDController pops the panel 0.8 -> 1 on every open,
	-- with a Back ease that overshoots past 1, so AbsoluteSize changes every frame
	-- of that animation. A UIGridLayout CellSize is in OFFSET, so recomputing it
	-- from the scaled box makes the six cards physically RE-FLOW — new cell, new
	-- padding, new text caps — while the panel is also being scaled. Two scalings
	-- fighting, and what it looks like is the grid assembling itself as the window
	-- opens. Measured: the cell ran 105x121 at scale 0.8 and 132x152 at 1.0.
	--
	-- Off the UNSCALED box the cell is a constant and the pop is left to UIScale
	-- alone, which is the one thing that should be animating.
	local k = math.max(panel.Scale.Scale, 0.01)
	local w = grid.AbsoluteSize.X / k
	local h = grid.AbsoluteSize.Y / k
	if w <= 0 or h <= 0 then return end

	local gap = math.floor(w * 0.030)
	-- FLOORED, both: UDim offsets are integers and UIGridLayout rounds a fractional
	-- cell UP, which overflows the row and silently drops a card onto the next line.
	local cw = math.floor((w - gap * (GRID_COLS - 1)) / GRID_COLS)
	local ch = math.floor((h - gap * (GRID_ROWS - 1)) / GRID_ROWS)
	cw = math.max(cw, MIN_TAP_PX)
	ch = math.max(ch, MIN_TAP_PX)

	gridLayout.CellSize = UDim2.fromOffset(cw, ch)
	gridLayout.CellPadding = UDim2.fromOffset(gap, gap)

	-- The card HEIGHT is the unit every text cap on this panel was chosen against,
	-- the same way the shop measures everything against its card height.
	kit:relayout(ch)
	kit:rescale()
end

-- Both signals, as the other panels do: the grid's own is direct, the HUD's is the
-- one that definitely moves when the viewport does.
grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

refresh()
relayout()

-- Open on join when a reward is waiting — the whole point of a daily is that the
-- player does not have to remember to go looking for it. Once the week is claimed
-- out it stays shut and the tile is the only way back in.
--
-- HUDController owns opening and closing, so this asks rather than reaching into
-- its state. Its OnInvoke is bound at the very END of that script, which may not
-- have run when this one reaches here: an Invoke before then returns nil rather
-- than erroring, so this retries instead of racing and losing silently.
if DAILY.AutoOpen ~= false and streak < 7 then
	task.spawn(function()
		local api = hud:WaitForChild("HUDOpenPanel", 10)
		if not api then return end
		for _ = 1, 40 do
			if api:Invoke("DailyGift") then return end
			task.wait(0.1)
		end
	end)
end
