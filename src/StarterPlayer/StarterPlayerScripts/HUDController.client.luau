--[[
	HUDController — drives StarterGui.HUD.

	Renders intent only: the six left-edge tiles, the lone top-right Settings
	tile, their feel, and six empty panels. Every sprint number comes from
	ReplicatedStorage.GameConfig.Sprint.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPRINT = require(ReplicatedStorage:WaitForChild("GameConfig")).Sprint

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
local BOB_SPRINT_PERIOD = 0.85
local BOB_RISE = 0.045
local BOB_TILT = 1.6

------------------------------------------------------------------ responsive
local barScale = bar:WaitForChild("Scale")

-- Tile edge as a fraction of viewport height. The column holds six tiles now,
-- so each is bar height (0.686) x tile share (0.149); at four it was 0.155.
-- Keep this in step with ButtonBar's slot Size or the tap floor below lies.
local TILE_HEIGHT_SCALE = 0.1067
local MIN_TAP_PX = 44

local rightBarScale = rightBar:WaitForChild("Scale")

local function fitScale()
	-- Tiles are already proportional to viewport height, so this only grows the
	-- column back up on a screen short enough to push a tile under the 44px tap
	-- floor. Never shrinks: the UISizeConstraint caps the tile on big screens.
	-- Both columns get the same scale, or the right one sits at 1 and its tiles
	-- render visibly smaller than the left's (46px against 52px, measured).
	local h = hud.AbsoluteSize.Y
	local s = 1
	if h > 0 then
		s = math.clamp(MIN_TAP_PX / (TILE_HEIGHT_SCALE * h), 1, 1.3)
	end
	barScale.Scale = s
	rightBarScale.Scale = s
end

-- The HUD sets IgnoreGuiInset, so its local space starts above the screen and a
-- top-anchored tile lands underneath the Roblox topbar unless the inset is added
-- back by hand. The inset is device-dependent and changes when the topbar is
-- toggled, so it is re-read whenever the viewport changes rather than baked in.
local settingsSlot = hud:WaitForChild("SettingsSlot")
local SETTINGS_MARGIN_PX = 14

local function placeSettings()
	local y = GuiService:GetGuiInset().Y + SETTINGS_MARGIN_PX
	if IS_TOUCH then
		-- On touch, Settings is the first item of the right-hand column, so the
		-- column carries the inset and the tile's own Position is layout-owned.
		-- Left as a free-floating tile it overlapped the column's first entry
		-- (measured: Settings y=14..60 against Inventory y=44..90).
		rightBar.Position = UDim2.new(0.975, 0, 0, y)
	else
		settingsSlot.Position = UDim2.new(0.975, 0, 0, y)
	end
end

local function relayout()
	fitScale()
	placeSettings()
end

hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

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
	tiles[name] = {
		name = name,
		slot = slot,
		bobber = slot:WaitForChild("Bobber"),
		button = slot.Bobber:WaitForChild(name .. "Button"),
		shadow = slot:WaitForChild("Shadow"),
		hovered = false,
		glowing = false,
	}
end

for _, name in ipairs({ "Shop", "Index", "Rebirth", "Sprint", "Inventory", "Teleport" }) do
	makeTile(name, bar:WaitForChild(name .. "Slot"))
end

-- Settings sits in the top-right on its own, so its slot is a child of the HUD
-- rather than of ButtonBar — otherwise the list layout would pull it into the
-- column. Its innards are identical, so every helper below works on it as-is.
makeTile("Settings", hud:WaitForChild("SettingsSlot"))

-- Sprint is the one tile that performs an action instead of opening a panel,
-- and on anything with a keyboard LeftShift already does it — so the tile is
-- touch-only. It is unparented rather than hidden, because UIListLayout would
-- otherwise still reserve its slot and leave a gap in the column. The sprint
-- logic further down stays live on every device either way.
local SPRINT_TILE_SHOWN = IS_TOUCH

-- Which tiles cross to the right edge on a phone. Shop/Index/Rebirth stay left
-- because they are the ones opened most; these two are the newer additions.
local RIGHT_EDGE_TILES = { "Inventory", "Teleport" }

-- The puck's size is written against the bar (whose height is 0.686 of the
-- viewport) while it lives in the column. Parented straight to the HUD it is
-- measured against the viewport instead, so the fraction has to be folded in or
-- it jumps a third bigger. Width gets a generous scale rather than 0 because
-- UIAspectRatioConstraint only ever shrinks an axis, never derives one.
local SPRINT_PUCK_SCALE = 0.686 * 0.111966558
local SPRINT_PUCK_POS = Vector2.new(0.17, 0.72)

-- Slot height as a fraction of the bar, matching ButtonBar's own slots. Settings
-- is sized against the viewport while it floats, so it has to be restated in bar
-- terms when it joins the column.
local TILE_SLOT_SCALE = 0.155509114

if IS_TOUCH then
	-- Six controls down a single edge is a wall on a phone, so the column is
	-- split across both edges. The right column runs from the top with Settings
	-- at its head, which keeps Settings in the corner it already occupied while
	-- removing the overlap it had with the column's first tile.
	rightBar.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rightBar.AnchorPoint = Vector2.new(1, 0)

	local sSlot = tiles.Settings.slot
	sSlot.Size = UDim2.new(1, 0, TILE_SLOT_SCALE, 0)
	sSlot.AnchorPoint = Vector2.new(0, 0)
	sSlot.LayoutOrder = 0
	sSlot.Parent = rightBar

	for i, name in ipairs(RIGHT_EDGE_TILES) do
		local slot = tiles[name].slot
		slot.LayoutOrder = i
		slot.Parent = rightBar
	end

	-- Sprint leaves the list layout altogether so it can sit clear of the tile
	-- stack and of the touch thumbstick in the bottom-left.
	local sp = tiles.Sprint.slot
	sp.AnchorPoint = Vector2.new(0.5, 0.5)
	sp.Size = UDim2.new(0.5, 0, SPRINT_PUCK_SCALE, 0)
	sp.Position = UDim2.fromScale(SPRINT_PUCK_POS.X, SPRINT_PUCK_POS.Y)
	sp.Parent = hud
else
	tiles.Sprint.slot.Parent = nil
end

local function refreshShadow(tile)
	local size = tile.hovered and 1.12 or (tile.glowing and 1.06 or 0.94)
	tween(tile.shadow, "shadow", EASE_OUT_BACK, {
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = tile.glowing and 0.1 or (tile.hovered and 0.28 or 0.45),
		BackgroundColor3 = tile.glowing and Color3.fromRGB(150, 255, 130) or Color3.new(0, 0, 0),
	})
end

local function startBob(tile, period)
	tile.bobber.Position = UDim2.fromScale(0.5, 0.5 - BOB_RISE)
	tile.bobber.Rotation = -BOB_TILT
	tween(tile.bobber, "bob", TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.fromScale(0.5, 0.5 + BOB_RISE),
		Rotation = BOB_TILT,
	})
end

---------------------------------------------------------------------- panels
local panels = {
	Shop = hud:WaitForChild("ShopPanel"),
	Index = hud:WaitForChild("IndexPanel"),
	Rebirth = hud:WaitForChild("RebirthPanel"),
	Inventory = hud:WaitForChild("InventoryPanel"),
	Teleport = hud:WaitForChild("TeleportPanel"),
	Settings = hud:WaitForChild("SettingsPanel"),
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

local function closePanel(panel)
	if not panel.Visible then return end
	if openPanel == panel then openPanel = nil end
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
	panel.Scale.Scale = 0.8
	panel.Visible = true
	buildStuds(panel) -- first open is when AbsoluteSize is finally real
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

---------------------------------------------------------------------- sprint
-- ponytail: sprint is client-only, no remote. Ceiling: an exploiter can set
-- WalkSpeed themselves anyway, and a server round-trip per toggle would make
-- the button feel laggy. Upgrade path: if speed ever gates real rewards, move
-- the authority server-side and have this send intent only.
local sprintTile = tiles.Sprint

-- No stamina readout by design: the tile's glow is the only sprint feedback.
-- Stamina still gates the sprint, it just isn't drawn.
local stamina = SPRINT.MaxStamina
local sprinting = false
local lastDrain = 0
local humanoid = nil
local staminaConn = nil
local setSprint

-- Standing still costs nothing: sprint only burns stamina while the character
-- is actually being moved. MoveDirection is input-derived, so it covers
-- keyboard, gamepad and the touch thumbstick alike, and it goes to zero the
-- moment the player lets go.
local function isMoving()
	return humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.05
end

local function ensureStaminaLoop()
	if staminaConn then return end
	staminaConn = RunService.Heartbeat:Connect(function(dt)
		if sprinting and isMoving() then
			lastDrain = os.clock()
			stamina = math.max(0, stamina - SPRINT.DrainPerSecond * dt)
			if stamina <= 0 then
				setSprint(false)
			end
		elseif os.clock() - lastDrain >= SPRINT.RegenDelay then
			-- Regenerates whether sprint is toggled on or off, as long as nothing
			-- has drained recently. Idling with sprint armed refills, which is the
			-- point of the change.
			stamina = math.min(SPRINT.MaxStamina, stamina + SPRINT.RegenPerSecond * dt)
		end

		-- Only safe to stop the loop when sprint is off; while it is armed the
		-- loop is what watches for the player starting to move again.
		if not sprinting and stamina >= SPRINT.MaxStamina then
			staminaConn:Disconnect()
			staminaConn = nil
		end
	end)
end

function setSprint(on)
	if on and stamina <= 1 then return end
	if sprinting == on then return end
	sprinting = on

	if humanoid then
		humanoid.WalkSpeed = on and SPRINT.SprintWalkSpeed or SPRINT.BaseWalkSpeed
	end

	sprintTile.glowing = on
	refreshShadow(sprintTile)
	startBob(sprintTile, on and BOB_SPRINT_PERIOD or BOB_PERIOD)
	tween(sprintTile.button, "tint", EASE_TINT, {
		ImageColor3 = on and Color3.fromRGB(190, 255, 180) or Color3.new(1, 1, 1),
	})
	ensureStaminaLoop()
end

local function bindCharacter(char)
	humanoid = char:WaitForChild("Humanoid")
	setSprint(false)
	humanoid.WalkSpeed = SPRINT.BaseWalkSpeed
end

if player.Character then
	task.spawn(bindCharacter, player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

ContextActionService:BindAction("HUDSprintToggle", function(_, state)
	if state == Enum.UserInputState.Begin then
		setSprint(not sprinting)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.LeftShift)

------------------------------------------------------------------------ wire
local ACTIONS = {
	Shop = function() togglePanel(panels.Shop) end,
	Index = function() togglePanel(panels.Index) end,
	Rebirth = function() togglePanel(panels.Rebirth) end,
	Sprint = function() setSprint(not sprinting) end,
	Inventory = function() togglePanel(panels.Inventory) end,
	Teleport = function() togglePanel(panels.Teleport) end,
	Settings = function() togglePanel(panels.Settings) end,
}

local order = { "Shop", "Index", "Rebirth", "Inventory", "Teleport", "Sprint", "Settings" }
for i, name in ipairs(order) do
	local tile = tiles[name]
	if name ~= "Sprint" or SPRINT_TILE_SHOWN then
		attachFeel(tile.button, {
			onHover = function(on)
				tile.hovered = on
				refreshShadow(tile)
			end,
			onActivate = ACTIONS[name],
		})
		-- stagger so the column ripples instead of pulsing in unison
		task.delay((i - 1) * 0.15, function()
			startBob(tile, BOB_PERIOD)
		end)
	end
end

hud.Destroying:Connect(function()
	if staminaConn then
		staminaConn:Disconnect()
		staminaConn = nil
	end
	ContextActionService:UnbindAction("HUDSprintToggle")
end)
