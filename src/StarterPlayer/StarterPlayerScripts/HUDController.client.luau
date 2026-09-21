--[[
	HUDController — drives StarterGui.HUD.

	Renders intent only: a 2x3 grid of tiles at the left edge, a coin and a gem
	counter hanging under it, the bag at bottom-centre, their feel, and six empty
	panels. Sprint has been removed — GameConfig.Sprint is still read, but only for
	the base walk speed.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local SPRINT = CONFIG.Sprint
local CUR = CONFIG.Currency
local PAL = CONFIG.Shop.Palette

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local bar = hud:WaitForChild("ButtonBar")
local rightBar = hud:WaitForChild("ButtonBarRight")

-- Declared up here because the responsive code below has to know which layout
-- it is arranging, and that code runs long before the tiles are built.
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- The Settings tile sits in the top-right, which is exactly where Roblox's
-- default leaderboard draws. Rather than tuck the tile somewhere worse, the
-- leaderboard goes: this game will want its own anyway. SetCoreGuiEnabled can
-- fire before the CoreGui is ready on a slow client, so it is retried.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		if ok then return end
		task.wait(0.2)
	end
end)

--------------------------------------------------------------------- tweens
-- One live tween per (instance, channel). Starting a new one on a channel
-- cancels the old one, so hover / press / idle never fight over a property.
local running = {}

local function tween(obj, channel, info, goal)
	local chans = running[obj]
	if not chans then
		chans = {}
		running[obj] = chans
	end
	if chans[channel] then
		chans[channel]:Cancel()
	end
	local t = TweenService:Create(obj, info, goal)
	chans[channel] = t
	t:Play()
	return t
end

local EASE_OUT_BACK = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EASE_SQUASH = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EASE_POP = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local EASE_TINT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

---------------------------------------------------------------------- sound
-- Roblox's own UI SFX, chosen because first-party audio carries no asset
-- permission of its own — a third-party sound would have to be shared with
-- this experience the way the button art had to be.
local function uiSound(id, volume)
	local s = Instance.new("Sound")
	s.Name = "HUD_" .. id
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end

local SFX_HOVER = uiSound("10066931761", 0.35) -- RBLX UI Hover 01
local SFX_CLICK = uiSound("10128760939", 0.55) -- RBLX UI Select 01

-- TimePosition reset so a rapid second trigger restarts the sample instead of
-- being swallowed by the one already playing.
local function play(sound)
	sound.TimePosition = 0
	sound:Play()
end

-- Every tile shares one hover sound, so dragging the cursor down the column
-- crosses five buttons in a couple of hundred milliseconds and machine-guns the
-- tick. Measured: one sweep fired it three times. The floor is global rather
-- than per-button for exactly that reason — a per-button one would let a sweep
-- through untouched, since each button is only entered once.
local HOVER_SFX_COOLDOWN = 0.12
local lastHoverSfx = 0

local function playHover()
	local now = os.clock()
	if now - lastHoverSfx < HOVER_SFX_COOLDOWN then return end
	lastHoverSfx = now
	play(SFX_HOVER)
end

local BOB_PERIOD = 2.2
local BOB_RISE = 0.045
local BOB_TILT = 1.6

------------------------------------------------------------------ responsive
local barScale = bar:WaitForChild("Scale")

-- Tile edge as a fraction of viewport height. The column holds six tiles now,
-- so each is bar height (0.686) x tile share (0.149); at four it was 0.155.
-- Keep this in step with ButtonBar's slot Size or the tap floor below lies.
local TILE_HEIGHT_SCALE = 0.1067
local MIN_TAP_PX = 44

-- The left panel is a GRID now, not a column: six tiles at 2 across, 3 down.
-- Settings and Car joined it, and nothing crosses to the right edge any more.
local BAR_COLUMNS = 2
local TILE_MIN_PX, TILE_MAX_PX = 44, 116
local barGrid = bar:WaitForChild("UIGridLayout")

-- COUNTED, not a constant. It was 3, which was true for exactly as long as the
-- bar held six tiles — and AdminController now adds a SEVENTH on an admin's
-- client only (the crown, which used to float alone in the top-right corner).
-- A hardcoded 3 sized the bar to six cells and the crown hung out below it,
-- underneath the coin and gem counters that hang off the bar's own bottom edge.
--
-- Deriving it means the bar is correct for whatever is actually parented to it
-- and stays correct for the next tile, and it costs one GetChildren per resize.
-- Non-admins are unaffected: they still have six children and still get 3 rows,
-- which is the whole reason a seventh tile is allowed to exist at all.
local function barRows()
	local n = 0
	for _, c in ipairs(bar:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then n += 1 end
	end
	return math.max(math.ceil(n / BAR_COLUMNS), 1)
end

local function fitScale()
	local h = hud.AbsoluteSize.Y
	if h <= 0 then return end
	-- FLOORED, and this is not cosmetic: UDim offsets are integers and a
	-- fractional cell rounds UP, so two cells plus padding can exceed the bar by
	-- a pixel and UIGridLayout silently wraps the second column onto its own row.
	local cell = math.floor(math.clamp(TILE_HEIGHT_SCALE * h, TILE_MIN_PX, TILE_MAX_PX))
	local gap = math.floor(cell * 0.16)
	local rows = barRows()
	barGrid.CellSize = UDim2.fromOffset(cell, cell)
	barGrid.CellPadding = UDim2.fromOffset(gap, gap)
	-- Size the bar to the grid exactly, in pixels. Left as a scale it either
	-- clipped the last row or left a dead column the tiles did not fill.
	bar.Size = UDim2.fromOffset(
		BAR_COLUMNS * cell + (BAR_COLUMNS - 1) * gap,
		rows * cell + (rows - 1) * gap
	)
	barScale.Scale = 1
end

-- Assigned further down, once tiles and panels both exist: the bag/panel
-- spacing needs both and they are built well after this point.
local panelFit = nil
-- Same deal for the currency counters, which hang off the bottom of the bar and
-- so have to be re-placed every time fitScale picks a new cell size.
local counterFit = nil

local function relayout()
	fitScale()
	if counterFit then counterFit() end
	if panelFit then panelFit() end
end

hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
-- AdminController parents its tile here AFTER the server has answered WhoAmI,
-- which is well after this point — so the bar has to re-fit on the child arriving
-- rather than only on a viewport resize. Without this an admin sees the crown
-- overlapping the coin counter until they resize the window.
bar.ChildAdded:Connect(relayout)
bar.ChildRemoved:Connect(relayout)
relayout()

-- Exposed so the badge can be driven from outside once something authoritative
-- exists to drive it.
local hudApi = Instance.new("BindableFunction")
hudApi.Name = "HUDSetBadge"
hudApi.Parent = hud

-- Lets a panel's own controller ask the HUD to show it — DailyController does
-- this on join when a reward is waiting. Parented here rather than where its
-- handler is bound, so a caller's WaitForChild resolves as early as possible;
-- an Invoke that lands before OnInvoke is set simply returns nil, which is why
-- the caller below retries rather than assuming.
local openApi = Instance.new("BindableFunction")
openApi.Name = "HUDOpenPanel"
openApi.Parent = hud

-------------------------------------------------------------------- feedback
local function ripple(button)
	local r = Instance.new("Frame")
	r.Name = "Ripple"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.fromScale(0, 0)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BackgroundTransparency = 0.5
	r.BorderSizePixel = 0
	r.ZIndex = 20
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = r
	r.Parent = button

	local t = TweenService:Create(r, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(2.4, 2.4),
		BackgroundTransparency = 1,
	})
	t.Completed:Connect(function()
		r:Destroy()
	end)
	t:Play()
end

-- attachFeel wires hover / press / click on any button that owns a UIScale.
local function attachFeel(button, opts)
	opts = opts or {}
	local scale = button:WaitForChild("Scale")
	local hovered = false
	local held = false

	local function restScale()
		return hovered and 1.12 or 1
	end

	local function release()
		tween(scale, "scale", EASE_POP, { Scale = restScale() })
	end

	button.MouseEnter:Connect(function()
		hovered = true
		if not held then
			tween(scale, "scale", EASE_OUT_BACK, { Scale = 1.12 })
		end
		tween(button, "rot", EASE_OUT_BACK, { Rotation = -4 })
		playHover()
		if opts.onHover then opts.onHover(true) end
	end)

	button.MouseLeave:Connect(function()
		hovered = false
		held = false
		tween(scale, "scale", EASE_OUT_BACK, { Scale = 1 })
		tween(button, "rot", EASE_OUT_BACK, { Rotation = 0 })
		if opts.onHover then opts.onHover(false) end
	end)

	button.MouseButton1Down:Connect(function()
		held = true
		tween(scale, "scale", EASE_SQUASH, { Scale = 0.9 })
	end)

	button.MouseButton1Up:Connect(function()
		held = false
		release()
	end)

	button.Activated:Connect(function()
		held = false
		release()
		ripple(button)
		play(SFX_CLICK)
		if opts.onActivate then opts.onActivate() end
	end)
end

----------------------------------------------------------------------- tiles
local tiles = {}

local function makeTile(name, slot)
	local tile = {
		name = name,
		slot = slot,
		bobber = slot:WaitForChild("Bobber"),
		button = slot.Bobber:WaitForChild(name .. "Button"),
		shadow = slot:WaitForChild("Shadow"),
		hovered = false,
		glowing = false,
		-- Every tile is bare artwork on a transparent ground now, not an opaque
		-- plate with its label baked in, so the square Shadow behind it would
		-- show through as a grey box on all six exactly as it did on the bag.
		-- Nothing is lost by switching it off: attachFeel already pops the
		-- button to 1.12 and tilts it -4 degrees on hover, which is feedback
		-- enough without a plate behind it to grow.
		shadowless = true,
	}
	tile.shadow.BackgroundTransparency = 1
	tiles[name] = tile
end

for _, name in ipairs({ "DailyGift", "Shop", "Index", "Teleport", "Settings", "Car" }) do
	makeTile(name, bar:WaitForChild(name .. "Slot"))
end

-- The shop is the one tile being SOLD rather than merely offered, so it alone
-- carries the treatment the shop panel uses on its own cards: a slow burst behind
-- the basket and an occasional glint on it.
--
-- NOT UIKit.rays. That one is built for a card — it magnifies the burst to 1.8x
-- and crops it to the card's rectangle so the rays can be AIMED at a product icon
-- off-centre. Here the burst is the whole point and has to stay a circle, so it is
-- sized to its own holder and never cropped. The holder is a CanvasGroup all the
-- same, because ClipsDescendants does not clip a ROTATED child and this one turns.
local SHOP_BURST = {
	Image = require(ReplicatedStorage:WaitForChild("GameConfig")).Shop.Rays,
	Fade = 0.18,   -- NOT fainter than a card's 0.25, which is the surprise here: a
	               -- card gives the burst a saturated plate to lighten, and this has
	               -- an unpredictable 3D world behind it instead. At 0.45 it was
	               -- invisible on grass and on stone alike. Judged in Play against
	               -- both, not on a swatch.
	Zoom = 1.0,    -- THE CLIP, of the tile, EXACTLY. At 1.45 the group was 110px
	               -- behind a 76px button, so the burst legitimately overhung it by
	               -- 17px a side and read as spikes poking out of the icon's box.
	               -- The group clips, so at 1.0 the rays stop dead on the tile's edge.
	Spread = 1.5,  -- THE BURST, inside that clip. Separate from Zoom, and that is the
	               -- whole point: the burst was fromScale(1,1) of a clip the size of
	               -- the tile, and ScaleType.Fit then inscribes a CIRCLE in a square
	               -- box — so the rays fanned out well short of the corners and faded
	               -- before even reaching that circle's edge. Barely visible, and no
	               -- amount of opacity fixes a burst that is simply too small.
	               -- Magnifying the IMAGE while the group stays at 1.0 reaches the
	               -- tile's edges and still cannot overhang, because the group is what
	               -- clips. Same separation the shop cards needed.
	               --
	               -- 1.5, not the 2.3 this first shipped at. A card's burst can take
	               -- 2.6 because it sits behind a product icon on a 272px plate; this
	               -- one is behind a 76px basket that is itself the subject, and at 2.3
	               -- the rays were thicker than the basket's own handle and the tile
	               -- read as a sunburst with something in front of it. Tuned in Play at
	               -- 76px, which is the only size it is ever drawn at.
	Spin = 26,
}

local function shopBurst(tile)
	if not SHOP_BURST.Image then return end
	local group = Instance.new("CanvasGroup")
	group.Name = "Burst"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(SHOP_BURST.Zoom, SHOP_BURST.Zoom)
	group.ClipsDescendants = true
	-- Behind the basket, which needs a band of its own. A child of the ImageButton
	-- would draw OVER its artwork, so this is a sibling in the bobber — but the
	-- button sits at 3 and the slot frames at 2, and at 2 the burst does not draw
	-- at all. There is no integer in between, so the BUTTON goes up rather than the
	-- burst going down; the badge pip reads button.ZIndex + 1 and follows it.
	group.ZIndex = tile.button.ZIndex
	tile.button.ZIndex = tile.button.ZIndex + 1

	local im = Instance.new("ImageLabel")
	im.Name = "Rays"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Size = UDim2.fromScale(SHOP_BURST.Spread, SHOP_BURST.Spread)
	im.Image = SHOP_BURST.Image
	im.ImageTransparency = SHOP_BURST.Fade
	-- Fit keeps it circular; Crop would stretch it to the holder's aspect.
	im.ScaleType = Enum.ScaleType.Fit
	-- A CanvasGroup does not isolate its children from ZIndexBehavior.Global.
	im.ZIndex = group.ZIndex
	im.Parent = group

	local spin = TweenService:Create(im,
		TweenInfo.new(SHOP_BURST.Spin, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 })
	-- SettingsController publishes ReduceMotion as an attribute on the HUD. Paused
	-- rather than cancelled, so turning it back on resumes from where the burst
	-- was instead of snapping to zero.
	local function motion()
		if hud:GetAttribute("ReduceMotion") then
			spin:Pause()
		else
			spin:Play()
		end
	end
	hud:GetAttributeChangedSignal("ReduceMotion"):Connect(motion)
	motion()

	group.Parent = tile.bobber
end


do
	local shop = tiles.Shop
	if shop then
		shopBurst(shop)
		-- No glints here. Tried, and on a 76px tile against a moving 3D world they
		-- read as a notification badge blinking, not as sparkle.
	end
end

-- Inventory sits bottom-centre and Settings top-right, so both are children of
-- the HUD rather than of ButtonBar — the list layout would drag either into the
-- column. StarterGui now holds them in their final places, so what Studio shows
-- in Edit is what the player gets; the block further down only re-asserts it.
makeTile("Inventory", hud:WaitForChild("InventorySlot"))

-- Inventory is the one panel reached constantly, so it leaves the column
-- altogether and takes the bottom-centre spot the genre reserves for a bag —
-- clear of the touch thumbstick bottom-left and the jump button bottom-right.
-- Its height was written against the bar, so parented to the HUD the bar's own
-- fraction has to be folded in or the tile jumps a third bigger. Its
-- UIAspectRatioConstraint is DominantAxis.Height, so the wide scale is a ceiling.
-- NOTE: the core Backpack hotbar also lives bottom-centre. It draws nothing
-- while the game has no Tools, which is why this spot is free today. Adding a
-- Tool means moving one of the two.
local INVENTORY_SCALE = 0.686 * 0.1555091142654419
-- 0.96, not 0.92. Anchored at its own bottom edge, so this is how far down the
-- viewport the bag's base sits — about 29px of clearance on a 720px screen. Not
-- lower: the tile bobs, and on a phone the gesture bar wants the last few percent.
local INVENTORY_POS = Vector2.new(0.5, 0.96)

-- The bag is a cut-out and does not reach the edges of its slot, so at the
-- column's tile size it reads visibly smaller than the plate tiles beside it.
-- This buys back the weight the transparent margin costs. It has to be applied
-- to the UISizeConstraint as well: that caps the tile at 116px on a big screen,
-- and left alone it would swallow the whole increase and change nothing.
local INVENTORY_BOOST = 1.3
-- The column tile's own UISizeConstraint ceiling, carried up by the same factor.
local INVENTORY_MAX_PX = 116 * INVENTORY_BOOST
-- Clear of the panels, which sit at 50 and reach 63 inside.
local BAG_Z = 120

-- Its own bob: slower and wider than the column's, so it reads as a separate
-- object rather than a tile that wandered out of the stack.
local INVENTORY_BOB_PERIOD = BOB_PERIOD * 1.4
local INVENTORY_BOB_AMP = 1.45

-- The right-hand column is gone. It existed to stop six controls stacking down
-- one edge on a phone; a 2x3 grid is compact enough that they all fit on the
-- left, and the grid clears the touch thumbstick in the bottom-left either way.
rightBar.Visible = false

do
	local t = tiles.Inventory
	local inv = t.slot
	inv.AnchorPoint = Vector2.new(0.5, 1)
	inv.Size = UDim2.new(0.5, 0, INVENTORY_SCALE * INVENTORY_BOOST, 0)
	inv.Position = UDim2.fromScale(INVENTORY_POS.X, INVENTORY_POS.Y)
	inv.Parent = hud

	-- Absolute, not multiplied. StarterGui now ships the boosted cap, and a
	-- multiply would compound it every time this ran against an already-boosted
	-- instance. Idempotent is the only safe shape once the layout is baked in.
	local cap = inv:FindFirstChildOfClass("UISizeConstraint")
	if cap then
		cap.MaxSize = Vector2.new(INVENTORY_MAX_PX, INVENTORY_MAX_PX)
	end

	t.bobPeriod = INVENTORY_BOB_PERIOD
	t.bobAmp = INVENTORY_BOB_AMP

	-- A silhouette shadow — a second copy of the image, flat black and offset —
	-- was tried here and rejected. The art already carries a thick dark outline,
	-- so an offset dark copy peers out from one side of it and reads as a
	-- misprint rather than as depth. The bag carries its own weight; it needs no
	-- shadow behind it. shadowless stops refreshShadow from tweening the plate
	-- back to opaque on hover, which is what would otherwise return the grey box.
	-- The bag stays on screen while a panel is open, so it has to out-rank one.
	-- Panels are ZIndex 50 and reach 63 inside (ShopPanel's close glyph), and a
	-- panel's lower edge crosses the bag's top by 17-31px at every common window
	-- height — it only clears around 1440, which is why the clipping came and
	-- went. At this band the bag draws over the panel instead of under it, and
	-- clicking it closes the panel, since togglePanel already treats a second
	-- press on the open panel as a close.
	inv.ZIndex = BAG_Z
	t.shadow.ZIndex = BAG_Z
	t.bobber.ZIndex = BAG_Z + 1
	t.button.ZIndex = BAG_Z + 1
end

------------------------------------------------------------------- counters
-- Coins and gems, stacked under the tile grid. The genre puts these top-centre or
-- top-right; here the grid already owns the left edge and the counters belong to
-- it, so they hang off its bottom and read as part of the same block rather than
-- as two more floating things.
--
-- NO PLATE. They shipped as bevelled pills and both read as PROGRESS BARS — a
-- rounded gradient capsule with a mark at one end and a number at the other is a
-- health meter, and no amount of narrowing fixed the shape. The reference does
-- what this game already does for every other call-out (the power number, the xN
-- badge, the shop's ribbons): the artwork, then outlined type beside it, with
-- nothing behind either. Deleting the pill deleted the problem.
--
-- NOT children of the bar: it is a UIGridLayout, and anything parented there
-- becomes a seventh cell. They live in the HUD and are positioned from the bar's
-- own Position/AnchorPoint each relayout — computed from the numbers fitScale just
-- chose, not from AbsolutePosition, which has not been recalculated yet at that
-- point in the frame.
--
-- Below the panels (50), like the tiles: a panel covers them.
local COUNTER_Z = 6
-- Row height as a fraction of the bar's cell. The icon is square and fills the
-- row, so this is really the icon size.
local COUNTER_HEIGHT = 0.52
-- The number's box, in row heights, starting just right of the icon. 1.12, not
-- the 0.92 this shipped at: the icon is one row-height wide and the artwork's own
-- contour reaches its edge, so a number starting at 0.92 had the coin's outline
-- running into its first digit.
local COUNTER_TEXT_X = 1.12
local COUNTER_TEXT_W = 2.6

-- FIND OR CREATE, every instance below. The counters now also exist in
-- StarterGui, so they are visible in Studio's own Edit viewport instead of only
-- appearing once a LocalScript has run in Play — Edit does not run LocalScripts,
-- which is why anything built purely at runtime is invisible while you are
-- authoring the place. Adopting what is there rather than adding a second copy is
-- what keeps the two from both existing; everything about their SIZE and position
-- is still computed here, because the tree cannot do arithmetic.
local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(class) then return found, false end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = parent
	return made, true
end

local counters = ensure(hud, "Counters", "Frame")
counters.BackgroundTransparency = 1
counters.ZIndex = COUNTER_Z

local counterList = ensure(counters, "UIListLayout", "UIListLayout")
counterList.FillDirection = Enum.FillDirection.Vertical
counterList.SortOrder = Enum.SortOrder.LayoutOrder

-- 12450 -> "12.4K". A raw figure outgrows its row the moment an economy exists,
-- and the genre abbreviates anyway.
local function short(n)
	n = math.max(math.floor(n or 0), 0)
	for _, u in ipairs({ { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if n >= u[1] then
			local v = n / u[1]
			return string.format(v < 10 and "%.1f%s" or "%.0f%s", v, u[2])
		end
	end
	return tostring(n)
end

local counterPlates = {}

local function makeCounter(kind, icon, order)
	-- A transparent row, so the icon and the number are siblings sized off its
	-- height rather than two things positioned against each other.
	local row = ensure(counters, kind .. "Counter", "Frame")
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 1)
	row.ZIndex = COUNTER_Z

	local art = ensure(row, "Icon", "ImageLabel")
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0, 0.5)
	art.Position = UDim2.fromScale(0, 0.5)
	-- Square off the row's HEIGHT, which is what the aspect constraint resolves;
	-- the width scale is only a ceiling for it to shrink from.
	art.Size = UDim2.new(1, 0, 1, 0)
	art.Image = icon
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = COUNTER_Z + 1
	local ar = ensure(art, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.DominantAxis = Enum.DominantAxis.Height

	local num = ensure(row, "Amount", "TextLabel")
	num.BackgroundTransparency = 1
	num.AnchorPoint = Vector2.new(0, 0.5)
	num.Position = UDim2.fromScale(0, 0.5)
	num.Size = UDim2.fromScale(1, 0.78)
	num.Text = "0"
	num.TextColor3 = UIKit.WHITE
	-- LEFT, hard against the icon. Right-aligned in a fixed box it drifted away
	-- from the artwork as the figure got shorter, which is the gap that made the
	-- pill version read as a half-empty bar.
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.FontFace = UIKit.FONT
	num.TextScaled = true
	num.ZIndex = COUNTER_Z + 1
	-- Contextual, so the stroke follows the digits instead of boxing the label —
	-- the same trap UIKit's Kit:outline exists for. Heavy: this is type on an
	-- unpredictable 3D world, not on a panel, and it is the only thing holding it.
	local ink = ensure(num, "UIStroke", "UIStroke")
	ink.Color = PAL.Ink
	ink.Thickness = 2.8
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ink.LineJoinMode = Enum.LineJoinMode.Round

	local plate = { row = row, num = num, ink = ink, value = 0 }
	counterPlates[kind] = plate
	return plate
end

local function setCurrency(kind, value)
	local plate = counterPlates[kind]
	if not plate then return end
	plate.value = math.max(math.floor(value or 0), 0)
	plate.num.Text = short(plate.value)
end

if CUR then
	makeCounter("Coins", CUR.CoinIcon, 1)
	makeCounter("Gems", CUR.GemIcon, 2)
	setCurrency("Coins", CUR.Coins)
	setCurrency("Gems", CUR.Gems)
end

-- The seam. Nothing drives these today — there is no economy and no server — so
-- GameConfig's figures are display state, exactly as the inventory roster is.
-- Invoke("Coins", 500) is what a server-fed client script will call.
local currencyApi = Instance.new("BindableFunction")
currencyApi.Name = "HUDSetCurrency"
currencyApi.OnInvoke = function(kind, value)
	setCurrency(kind, value)
end
currencyApi.Parent = hud

counterFit = function()
	local w, h = hud.AbsoluteSize.X, hud.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	local cell = barGrid.CellSize.Y.Offset
	local gap = barGrid.CellPadding.Y.Offset
	if cell <= 0 then return end

	local barW = bar.Size.X.Offset
	local barH = bar.Size.Y.Offset
	local px = bar.Position.X.Scale * w + bar.Position.X.Offset
	local py = bar.Position.Y.Scale * h + bar.Position.Y.Offset
	-- The bar is anchored mid-left, so its bottom is its own height past its
	-- anchor by (1 - AnchorPoint.Y). Read rather than assumed, because the bar's
	-- anchor lives in StarterGui and has moved before.
	local left = px - barW * bar.AnchorPoint.X
	local top = py + barH * (1 - bar.AnchorPoint.Y) + gap

	local rowH = math.max(math.floor(cell * COUNTER_HEIGHT), 18)
	local inner = math.floor(rowH * 0.18)
	counterList.Padding = UDim.new(0, inner)
	counters.Position = UDim2.fromOffset(math.floor(left), math.floor(top))
	-- Wide enough for the longest figure the abbreviation can produce; nothing is
	-- drawn on this box, so overshooting it costs nothing and clipping a digit
	-- would be the one visible failure.
	counters.Size = UDim2.fromOffset(math.floor(rowH * (COUNTER_TEXT_X + COUNTER_TEXT_W)), rowH * 2 + inner)
	for _, plate in pairs(counterPlates) do
		plate.row.Size = UDim2.new(1, 0, 0, rowH)
		plate.num.Position = UDim2.fromOffset(math.floor(rowH * COUNTER_TEXT_X), math.floor(rowH * 0.5))
		plate.num.Size = UDim2.fromOffset(math.floor(rowH * COUNTER_TEXT_W), math.floor(rowH * 0.78))
		plate.ink.Thickness = math.max(1.6, rowH * 0.075)
	end
end

counterFit()

local GLOW_TINT = Color3.fromRGB(150, 255, 130)

--------------------------------------------------------------------- badges
-- The pet-sim notification pip: a red disc clinging to the tile's top-right
-- corner with a count on it.
--
-- It hangs off the BOBBER, not the button. The button sets ClipsDescendants so
-- that ripple() can grow a white disc to 2.4x inside it without spilling over
-- the tile, and anything parented there that reaches past the edge — which is
-- the whole point of a corner pip — gets cut in half by the same clip.
--
-- Riding the bobber also means it bobs with the tile but does not inherit the
-- hover pop, which is the behaviour the genre actually uses: the icon grows
-- under the pip and the pip stays put.
local BADGE_SIZE = 0.44
local BADGE_POS = Vector2.new(0.8, 0.2)
local BADGE_FILL = Color3.fromRGB(232, 46, 52)
local BADGE_INK = Color3.fromRGB(26, 22, 34)
-- The ring reads on the disc; the text stroke has to stay thinner or it closes
-- up the counters inside a 6, 8 or 9 at this size.
local BADGE_RING_PX = 2.5
local BADGE_TEXT_STROKE_PX = 1.5
-- Mirrors UIKit.FONT. Stated here rather than requiring the kit, which this
-- controller otherwise has no need of.
local BADGE_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function setBadge(name, value)
	local tile = tiles[name]
	if not tile then return end
	local pip = tile.bobber:FindFirstChild("Badge")

	-- nil clears it: there is no "empty badge" state, a pip with nothing in it
	-- is just a red dot promising something that is not there.
	if value == nil or value == 0 or value == "" then
		if pip then pip:Destroy() end
		return
	end

	if not pip then
		-- TWO instances, and it has to be two: a GuiObject takes only ONE
		-- UIStroke, and the disc and the digits need different modes. Border
		-- follows the element's edge (and its UICorner, so it rings the circle);
		-- Contextual traces the glyph contours. One stroke cannot do both, and
		-- Border on the label would box the text rather than outline it.
		pip = Instance.new("Frame")
		pip.Name = "Badge"
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromScale(BADGE_POS.X, BADGE_POS.Y)
		pip.Size = UDim2.fromScale(BADGE_SIZE, BADGE_SIZE)
		pip.BackgroundColor3 = BADGE_FILL
		pip.BorderSizePixel = 0
		-- ZIndexBehavior is Global, so this is an absolute band and has to clear
		-- the button it sits on rather than merely being a later child.
		pip.ZIndex = tile.button.ZIndex + 1

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = pip

		-- Square, or a two-digit count stretches the disc into a pill.
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1
		ratio.Parent = pip

		local ring = Instance.new("UIStroke")
		ring.Color = BADGE_INK
		ring.Thickness = BADGE_RING_PX
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = pip

		local label = Instance.new("TextLabel")
		label.Name = "Count"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = BADGE_FONT
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.ZIndex = pip.ZIndex + 1
		-- TextScaled fills the LABEL, which inside a circle means the digits
		-- reach the ring at the corners. The padding keeps them off it.
		local pad = Instance.new("UIPadding")
		local p = UDim.new(0.2, 0)
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = p, p, p, p
		pad.Parent = label

		local textStroke = Instance.new("UIStroke")
		textStroke.Color = BADGE_INK
		textStroke.Thickness = BADGE_TEXT_STROKE_PX
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = label

		label.Parent = pip
		pip.Parent = tile.bobber
	end

	pip.Count.Text = tostring(value)
end

local function refreshShadow(tile)
	if tile.shadowless then return end
	local size = tile.hovered and 1.12 or (tile.glowing and 1.06 or 0.94)
	tween(tile.shadow, "shadow", EASE_OUT_BACK, {
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = tile.glowing and 0.1 or (tile.hovered and 0.28 or 0.45),
		BackgroundColor3 = tile.glowing and GLOW_TINT or Color3.new(0, 0, 0),
	})
end

local function startBob(tile, period, amp)
	amp = amp or 1
	local rise, tilt = BOB_RISE * amp, BOB_TILT * amp
	tile.bobber.Position = UDim2.fromScale(0.5, 0.5 - rise)
	tile.bobber.Rotation = -tilt
	tween(tile.bobber, "bob", TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.fromScale(0.5, 0.5 + rise),
		Rotation = tilt,
	})
end

---------------------------------------------------------------------- panels
local panels = {
	Shop = hud:WaitForChild("ShopPanel"),
	Index = hud:WaitForChild("IndexPanel"),
	Inventory = hud:WaitForChild("InventoryPanel"),
	Teleport = hud:WaitForChild("TeleportPanel"),
	Settings = hud:WaitForChild("SettingsPanel"),
	DailyGift = hud:WaitForChild("DailyPanel"),
}

-- The tiles are studded, so the panels are too: one tiled ImageLabel per panel.
-- The store id in the URL (16861118642) is a Decal wrapper, and ImageLabel.Image
-- needs the texture inside it, which is a different id.
local STUDS_IMAGE = "rbxassetid://16861118611" -- "Studs Background"
-- ImageColor3 only multiplies, so a mid-grey texture can never be made lighter than
-- itself — the plate underneath has to carry the colour and the texture only darkens
-- it. That is why the plate is a saturated cyan rather than the panel's pale one: the
-- studs pull it down, and starting pale gave grey mush.
-- This is the panel's surface, not a wash over it, so the fade is mild.
--
-- The texture is an OPAQUE DARK GREY baseplate grid, which is the thing to know about
-- it: composited over a colour it can only ever darken, so aiming for bright cyan studs
-- by tinting the plate alone just produced flat grey-cyan. The grid itself has to be
-- tinted (STUDS_TINT multiplies into it) and the plate under it kept bright.
local STUDS_FADE = 0.34
local STUDS_PLATE = Color3.fromRGB(130, 216, 244)
local STUDS_TINT = Color3.fromRGB(176, 240, 255)
-- One stud grid per 72px. Tiling the whole image into a small cell (48px and below)
-- averages it to a flat field — the relief stops resolving and it reads as paint.
local STUDS_TILE = 72

-- Per-panel surface override, keyed by panel name. ShopPanel is near-white by
-- design (GameConfig.Shop.Palette.Panel) and the cyan plate above would fight it,
-- so it gets a white plate with the sheet faded almost out — a ~5% watermark rather
-- than a surface. The other five panels are untouched.
-- Skip = true means the panel gets NO studded sheet at all and shows its own body
-- gradient instead. InventoryPanel is the reference's plain white sheet: its pets
-- float with no plate under them, and a stud grid behind floating art is texture
-- competing with the subject rather than a surface supporting it.
local STUDS_OVERRIDE = {
	ShopPanel = {
		Plate = Color3.fromRGB(253, 253, 253),
		Fade = 0.93,
		Tint = Color3.fromRGB(150, 164, 200),
	},
	InventoryPanel = { Skip = true },
	-- Same reasoning as the inventory, and it only shows once the panel is
	-- actually opened: buildStuds runs on first open, so a panel can look right
	-- while it is being built and turn slate the moment the button is pressed.
	-- The collection is a pale panel of floating pets on rarity blobs; a cyan
	-- stud grid behind them is texture competing with the subject.
	IndexPanel = { Skip = true },
	-- Same reasoning again: the daily panel is six saturated reward cards and a
	-- full-height violet plate on a pale sheet. A cyan stud grid behind that is a
	-- seventh colour competing with the six that carry meaning.
	DailyPanel = { Skip = true },
	-- Four saturated destination cards on a pale sheet, same story. The cyan stud
	-- plate also drove the body text off a cliff: the panel blurb is navy, which is
	-- legible on the pale gradient and invisible on dark slate.
	TeleportPanel = { Skip = true },
	-- Rows of controls, not art. A stud grid behind a settings list is texture
	-- behind reading matter.
	SettingsPanel = { Skip = true },
}

local function buildStuds(panel)
	if panel:FindFirstChild("Studs") then return end
	local over = STUDS_OVERRIDE[panel.Name] or {}
	if over.Skip then return end

	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	-- Nearly the whole panel. Confined to the content band it was ~90% occluded by the
	-- cards and only showed through as slivers in the gutters, which is not a background.
	-- At full size it reads around the title, in the margins and between cards.
	studs.AnchorPoint = Vector2.new(0.5, 0.5)
	studs.Position = UDim2.fromScale(0.5, 0.5)
	studs.Size = UDim2.fromScale(0.965, 0.955)
	studs.BackgroundColor3 = over.Plate or STUDS_PLATE
	studs.BackgroundTransparency = 0
	studs.ImageTransparency = over.Fade or STUDS_FADE
	studs.Image = STUDS_IMAGE
	studs.ImageColor3 = over.Tint or STUDS_TINT
	-- Tile at a fixed pixel size, not Crop. Crop stretches ONE copy to cover the frame,
	-- so the stud size floated with the panel's size and at panel scale resolved to
	-- almost nothing. This image is a full grid of studs, so its own edges line up and
	-- the seam that ruled tiling out for other textures does not appear.
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(STUDS_TILE, STUDS_TILE)
	studs.ZIndex = panel.ZIndex
	studs.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.05, 0)
	corner.Parent = studs

	-- No stroke of its own. At nearly panel size its edge sits a few pixels inside the
	-- panel's own outline, and two dark lines that close together read as a printing
	-- error rather than as depth.

	studs.Parent = panel
end

local openPanel = nil

-- Clearance between a panel's lower edge and the top of the bag.
local BAG_GAP_PX = 16
-- Roblox's own top bar. Fixed pixels, so it eats proportionally more of a short
-- screen — which is exactly when the headroom below runs out.
local TOPBAR_PX = 36
local TOPBAR_MARGIN = 8

-- A panel is 0.62 of the viewport and the bag sits at 0.92, so the two overlap
-- by 17-31px at every common height and only come apart around 1440. Rather
-- than let the bag cover the panel, open a real gap: move the panel up as far as
-- its own furniture allows, then push the bag down for whatever is left over.
-- The title icon and close button hang ABOVE the panel's top edge (47px at
-- 720h), so the headroom is measured from the highest child, not the panel —
-- moving a panel up by its own top edge would slide that icon into the topbar.
local function layoutForPanel(panel)
	local vy = hud.AbsoluteSize.Y
	local bag = tiles.Inventory and tiles.Inventory.slot
	if vy <= 0 or not bag or not panel then return end

	-- Size.Y.Scale is NOT the rendered height. Every panel carries a
	-- UIAspectRatioConstraint, and when the box is narrower than the ratio wants
	-- the width wins and the height is derived from it instead. ShopPanel is the
	-- one that actually hits this: 0.78 of 720 asks for 562px and it renders 526.
	-- Reading AbsoluteSize back here would be the obvious alternative, but this
	-- runs while the open tween still has UIScale at 0.8, so the measurement
	-- would be of a shrunken panel. Deriving it is exact and frame-independent.
	local availW = panel.Size.X.Scale * hud.AbsoluteSize.X
	local availH = panel.Size.Y.Scale * vy
	local ar = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
	local panelH = availH
	if ar and ar.AspectRatio > 0 and availH > 0 and (availW / availH) <= ar.AspectRatio then
		panelH = availW / ar.AspectRatio
	end

	local panelTop = (vy - panelH) / 2
	local bagTop = INVENTORY_POS.Y * vy - bag.AbsoluteSize.Y
	local need = (panelTop + panelH - bagTop) + BAG_GAP_PX
	if need <= 0 then
		panel.Position = UDim2.fromScale(0.5, 0.5)
		bag.Position = UDim2.fromScale(INVENTORY_POS.X, INVENTORY_POS.Y)
		return
	end

	-- DIRECT children only. Furniture that deliberately hangs outside the panel
	-- (the title icon, the close button) is parented to the panel itself; a deep
	-- descendant that reaches past the top edge is decoration inside a clipped
	-- card, not something the player sees up there. ShopPanel proves it: its
	-- feature banner holds a Burst whose box starts 391px above the panel, which
	-- as an overhang figure drove headroom to zero and pinned the panel in place.
	--
	-- Overhang is a DIFFERENCE between two AbsolutePositions, so it is the same
	-- whatever shift is currently applied. That is what lets it be read without
	-- resetting the panel first: setting Position and reading AbsolutePosition
	-- back in the same frame would hand back the stale value.
	local overhang = 0
	for _, d in panel:GetChildren() do
		if d:IsA("GuiObject") and d.AbsoluteSize.Y > 0 then
			local o = panel.AbsolutePosition.Y - d.AbsolutePosition.Y
			if o > overhang then overhang = o end
		end
	end

	local up = math.min(need, math.max(0, (panelTop - overhang) - TOPBAR_PX - TOPBAR_MARGIN))
	-- Whatever the panel could not absorb goes to the bag, but never so far that
	-- it walks off the bottom of a very short screen.
	local down = math.min(need - up, math.max(0, vy - 8 - INVENTORY_POS.Y * vy))
	panel.Position = UDim2.new(0.5, 0, 0.5, -up)
	bag.Position = UDim2.new(INVENTORY_POS.X, 0, INVENTORY_POS.Y, down)
end

local function restBag()
	local bag = tiles.Inventory and tiles.Inventory.slot
	if bag then
		bag.Position = UDim2.fromScale(INVENTORY_POS.X, INVENTORY_POS.Y)
	end
end

panelFit = function()
	if openPanel then layoutForPanel(openPanel) end
end

-- Background blur, on whenever ANY panel is open. One BlurEffect for all six
-- rather than one each: only one panel is ever open (togglePanel closes the
-- previous), so the state that matters is simply whether openPanel is nil.
--
-- Driven by syncBlur() rather than by the open and close paths setting it
-- themselves, so the two can never disagree — it reads openPanel after the fact
-- instead of predicting it. closePanel in particular only clears openPanel when
-- the panel being closed is the open one, which is exactly the kind of condition
-- a second copy of the logic gets wrong.
--
-- Lighting, client-side: this is a local effect on the player's own camera and
-- nothing about it replicates.
local BLUR_SIZE = 16
local blur = Instance.new("BlurEffect")
blur.Name = "PanelBlur"
blur.Size = 0
-- Disabled at rest. A BlurEffect at Size 0 is still a full-screen pass every
-- frame, and this is off far more often than it is on.
blur.Enabled = false
blur.Parent = Lighting

local blurToken = 0
local function syncBlur()
	-- SettingsController owns this switch and publishes it as an attribute on the
	-- HUD rather than reaching in here. Absent means on, so a client that never
	-- opens settings behaves exactly as before.
	local allowed = hud:GetAttribute("MenuBlur")
	local want = openPanel ~= nil and allowed ~= false
	blurToken += 1
	local token = blurToken
	if want then blur.Enabled = true end
	-- Out faster than in, matching the panel's own 0.28 open / 0.16 close.
	tween(blur, "blur", TweenInfo.new(want and 0.28 or 0.16, Enum.EasingStyle.Quad),
		{ Size = want and BLUR_SIZE or 0 })
	if not want then
		task.delay(0.16, function()
			-- Only if nothing re-opened in the meantime; the token is what makes a
			-- fast close-then-open not switch the effect off under the new panel.
			if token == blurToken and openPanel == nil then
				blur.Enabled = false
			end
		end)
	end
end

local function closePanel(panel)
	if not panel.Visible then return end
	if openPanel == panel then
		openPanel = nil
		-- Published for anything that is not one of the six — AdminController builds
		-- its own panel outside this system and has to know to get out of the way.
		hud:SetAttribute("OpenPanel", nil)
		restBag()
		syncBlur()
	end
	tween(panel.Scale, "panel", TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.82 })
	task.delay(0.16, function()
		if openPanel ~= panel then
			panel.Visible = false
		end
	end)
end

local function togglePanel(panel)
	if openPanel == panel then
		closePanel(panel)
		return
	end
	if openPanel then closePanel(openPanel) end
	openPanel = panel
	hud:SetAttribute("OpenPanel", panel.Name)
	syncBlur()
	panel.Scale.Scale = 0.8
	panel.Visible = true
	buildStuds(panel) -- first open is when AbsoluteSize is finally real
	layoutForPanel(panel)
	tween(panel.Scale, "panel", TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

for _, panel in pairs(panels) do
	-- Recursive: the close button was moved out of the header onto the panel's
	-- top-right corner, so it is no longer a fixed path.
	attachFeel(panel:FindFirstChild("CloseButton", true), {
		onActivate = function()
			closePanel(panel)
		end,
	})
end

------------------------------------------------------------------- character
-- Sprint is GONE: the tile that drove it is now Car, and the LeftShift binding
-- is removed, so nothing can turn it on. The stamina drain/regen loop and the
-- tile glow went with it rather than being left dormant — setSprint reached into
-- tiles.Sprint, which no longer exists, so leaving it would have been a nil
-- index waiting for whoever wired it back up.
--
-- GameConfig.Sprint survives as the design of record and still supplies the base
-- walk speed below; re-reading it is all that remains of the system here.

local humanoid = nil

local function bindCharacter(char)
	humanoid = char:WaitForChild("Humanoid")
	humanoid.WalkSpeed = SPRINT.BaseWalkSpeed
end

if player.Character then
	task.spawn(bindCharacter, player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

------------------------------------------------------------------------ wire
local ACTIONS = {
	Shop = function() togglePanel(panels.Shop) end,
	Index = function() togglePanel(panels.Index) end,
	Inventory = function() togglePanel(panels.Inventory) end,
	Teleport = function() togglePanel(panels.Teleport) end,
	Settings = function() togglePanel(panels.Settings) end,
	DailyGift = function() togglePanel(panels.DailyGift) end,
}

-- Car has no entry in ACTIONS: it is a real, hoverable button with nothing behind
-- it yet, like the inventory rail cells. attachFeel with a nil onActivate still
-- gives it the hover pop, the press squash and the click ripple, so it reads as
-- live rather than disabled. DailyGift used to be in the same position and now
-- opens DailyPanel.
local order = { "DailyGift", "Shop", "Index", "Teleport", "Settings", "Car", "Inventory" }
for i, name in ipairs(order) do
	local tile = tiles[name]
	do
		attachFeel(tile.button, {
			onHover = function(on)
				tile.hovered = on
				refreshShadow(tile)
			end,
			onActivate = ACTIONS[name],
		})
		-- stagger so the column ripples instead of pulsing in unison
		task.delay((i - 1) * 0.15, function()
			startBob(tile, tile.bobPeriod or BOB_PERIOD, tile.bobAmp)
		end)
	end
end

-- Nothing DRIVES these yet: there is no server, so no unread count exists to
-- read. The pip and its placement are the deliverable; pointing it at real data
-- later is one call per tile. Set a name to nil to clear it.
local BADGES = { Car = 1 }
for name, value in BADGES do
	setBadge(name, value)
end

-- Reachable from any other client script: hud.HUDSetBadge:Invoke("Shop", 3).
hudApi.OnInvoke = function(name, value)
	setBadge(name, value)
end

-- OPEN, not toggle. A panel controller asking for itself on join must not close
-- the panel if something else already opened it, and toggle semantics would make
-- that depend on call order. hud.HUDOpenPanel:Invoke("DailyGift").
--
-- Pass false as the second argument to CLOSE instead — TeleportController does
-- this after a jump, because leaving the panel up hides the place you pressed the
-- button to see. Closing is explicit for the same reason opening is not a toggle:
-- the caller says what it wants rather than what it wants flipped.
openApi.OnInvoke = function(name, open)
	-- Invoke(nil, false) closes WHATEVER is open, which is what a caller outside
	-- these six needs: AdminController has to clear the screen before showing its
	-- own panel and has no business knowing which of them is up.
	if name == nil and open == false then
		if openPanel then closePanel(openPanel) end
		return true
	end
	local panel = panels[name]
	if not panel then return false end
	if open == false then
		if openPanel == panel then closePanel(panel) end
		return true
	end
	if openPanel == panel then return true end
	togglePanel(panel)
	return true
end


