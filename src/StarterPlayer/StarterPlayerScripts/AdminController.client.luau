--[[
	AdminController — the admin panel, and the global message feed.

	TWO JOBS, and the split matters: the FEED runs for everybody, because a global
	message that only admins can see is not a global message. The PANEL is built
	only after the server says this player is an admin — not hidden, not disabled,
	NOT BUILT. A non-admin's client never receives the instances.

	The server is the authority on all of it (see AdminService). What the answer to
	WhoAmI buys here is purely whether to spend the instances; every button below
	sends a request that is checked again on arrival.

	The panel is built here rather than kept in StarterGui like the other six, for
	the same reason: StarterGui furniture is replicated to every player who joins.
	That means assembling the shell UIKit.chrome expects — Scale, Shadow, Title,
	CloseButton and the rest — which buildShell does, once.

	FLY is client-side and cannot be otherwise: Roblox gives the client network
	ownership of its own character. An exploiter can fly in any experience whether
	this exists or not, so nothing is lost by putting the admin's own flight here.
	Direction comes from Humanoid.MoveDirection rather than reading WASD, which is
	the one line that makes it work on a thumbstick as well as a keyboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ADMIN = CONFIG.Admin
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")

local remotes = ReplicatedStorage:WaitForChild("AdminRemotes", 30)
if not remotes then
	-- No server script, no admin anything. This is the state the whole place was
	-- in until AdminService existed, so it is a real case and not a defensive
	-- flourish: say so once and stop.
	warn("AdminController: ReplicatedStorage.AdminRemotes never appeared — is AdminService running?")
	return
end

local announce = remotes:WaitForChild("Announce")
local command = remotes:WaitForChild("Command")
local whoAmI = remotes:WaitForChild("WhoAmI")

--=========================================================== THE MESSAGE FEED
-- Everybody gets this, admin or not.

local FEED_Z = 200          -- over the panels (50..63) and the bag (120): an
                            -- announcement that a panel can cover is not one
local FEED_TOP = 0.02       -- of viewport height, below the topbar
local FEED_ROW_H = 0.042    -- of viewport height
local FEED_WIDTH = 0.62

local layoutFeed -- assigned below; pushMessage calls it on every new row

local feed = Instance.new("Frame")
feed.Name = "AdminFeed"
feed.BackgroundTransparency = 1
feed.AnchorPoint = Vector2.new(0.5, 0)
feed.Position = UDim2.fromScale(0.5, FEED_TOP)
feed.Size = UDim2.fromScale(FEED_WIDTH, 0.3)
feed.ZIndex = FEED_Z
feed.Parent = hud

local feedList = Instance.new("UIListLayout")
feedList.FillDirection = Enum.FillDirection.Vertical
feedList.HorizontalAlignment = Enum.HorizontalAlignment.Center
feedList.SortOrder = Enum.SortOrder.LayoutOrder
feedList.Padding = UDim.new(0, 4)
feedList.Parent = feed

local feedOrder = 0
local feedRows = {}

-- Declared before pushMessage, which calls it on every new row.
function layoutFeed()
	local h = hud.AbsoluteSize.Y
	if h <= 0 then return end
	local rowH = math.max(math.floor(h * FEED_ROW_H), 14)
	feedList.Padding = UDim.new(0, math.max(2, math.floor(rowH * 0.2)))
	for _, row in ipairs(feedRows) do
		row.Size = UDim2.new(1, 0, 0, rowH)
		local lay = row:FindFirstChildOfClass("UIListLayout")
		if lay then
			lay.Padding = UDim.new(0, math.floor(rowH * 0.16))
		end
		local icon = row:FindFirstChild("Icon")
		if icon then
			icon.Size = UDim2.fromOffset(rowH, rowH)
		end
		local line = row:FindFirstChild("Line")
		if line then
			-- 0.72 of the row rather than filling it: the stroke is drawn OUTSIDE
			-- the glyphs, and type sized to the full row height has its contour
			-- clipped by the row above and below.
			line.TextSize = math.max(10, math.floor(rowH * 0.72))
			line.Size = UDim2.fromOffset(0, rowH)
		end
	end
end

-- RichText, so the name and the message are two colours in ONE label. Two labels
-- side by side would need the name's width measured to place the text after it,
-- and TextScaled makes that width a moving target.
local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function pushMessage(payload)
	if type(payload) ~= "table" then return end
	local name = tostring(payload.DisplayName or payload.Name or "?")
	local text = tostring(payload.Text or "")
	if text == "" then return end

	feedOrder += 1
	local row = Instance.new("Frame")
	row.Name = "Message"
	row.BackgroundTransparency = 1
	row.LayoutOrder = feedOrder
	row.Size = UDim2.new(1, 0, 0, 1)
	row.ZIndex = FEED_Z

	-- A horizontal list, CENTRED, rather than the icon and the text positioned
	-- against the row: the line has to sit in the middle of the screen whatever
	-- its length, and a full-width row with a left-aligned label put every message
	-- hard against the left edge of a box 62% of the screen wide.
	local rowLay = Instance.new("UIListLayout")
	rowLay.FillDirection = Enum.FillDirection.Horizontal
	rowLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLay.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLay.SortOrder = Enum.SortOrder.LayoutOrder
	rowLay.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromOffset(1, 1)
	-- THE SENDER'S HEAD, not a crown. The UserId comes from the server with the
	-- message, so the head cannot be spoofed either.
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Crop
	icon.ZIndex = FEED_Z + 1
	-- Round, like every head pip in the genre. ClipsDescendants would not do it —
	-- it ignores UICorner — but an ImageLabel's own corner clips its image fine.
	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(0.5, 0)
	headCorner.Parent = icon
	local headRing = Instance.new("UIStroke")
	headRing.Color = P.Ink
	headRing.Thickness = 2
	headRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headRing.Parent = icon
	icon.Parent = row

	-- GetUserThumbnailAsync YIELDS, and a yield here would hold up the whole feed
	-- row, so the head arrives when it arrives. The fallback is MessageIcon (the
	-- crown), which is also what a brand-new account with no rendered avatar gets.
	local userId = tonumber(payload.UserId)
	if userId then
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)
			if ok and url and icon.Parent then
				icon.Image = url
			elseif icon.Parent then
				icon.Image = ADMIN.MessageIcon or ""
			end
		end)
	else
		icon.Image = ADMIN.MessageIcon or ""
	end

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.LayoutOrder = 2
	-- MEASURED, not TextScaled, and AutomaticSize on X. TextScaled fills whatever
	-- box it is given, so a short message renders huge and a long one small — and
	-- it cannot be combined with AutomaticSize, which is what lets the layout
	-- centre a line whose width nobody knows in advance.
	line.TextScaled = false
	line.AutomaticSize = Enum.AutomaticSize.X
	line.Size = UDim2.fromOffset(0, 1)
	line.RichText = true
	local nameHex = (ADMIN.NameColour or Color3.fromRGB(255, 221, 74)):ToHex()
	line.Text = ('<font color="#%s">%s:</font> %s'):format(nameHex, escape(name), escape(text))
	line.TextColor3 = WHITE
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.FontFace = FONT
	line.ZIndex = FEED_Z + 1
	-- Type on an unpredictable 3D world, so the contour is the only thing holding
	-- it: Contextual, or the stroke boxes the label instead of the letters.
	local ink = Instance.new("UIStroke")
	ink.Color = P.Ink
	ink.Thickness = 2.4
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ink.LineJoinMode = Enum.LineJoinMode.Round
	ink.Parent = line
	line.Parent = row

	row.Parent = feed
	table.insert(feedRows, row)
	-- NOW, not on the next viewport change. The row is created with a placeholder
	-- one-pixel size and everything about its scale is resolved in layoutFeed; the
	-- first message went out 10px tall because nothing called this until the window
	-- happened to be resized.
	layoutFeed()

	-- Oldest out first, so a burst cannot push the newest line off the screen.
	while #feedRows > (ADMIN.MessageMax or 5) do
		local old = table.remove(feedRows, 1)
		if old then old:Destroy() end
	end

	task.delay(ADMIN.MessageDuration or 7, function()
		if not row.Parent then return end
		local fade = TweenService:Create(line, TweenInfo.new(0.5), { TextTransparency = 1 })
		TweenService:Create(ink, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(icon, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
		fade.Completed:Connect(function()
			for i, r in ipairs(feedRows) do
				if r == row then
					table.remove(feedRows, i)
					break
				end
			end
			row:Destroy()
		end)
		fade:Play()
	end)
end

announce.OnClientEvent:Connect(pushMessage)

hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	layoutFeed()
end)

--============================================================== ADMIN OR NOT
-- Blocking, and deliberately so: nothing below this line should exist for a
-- player the server does not vouch for. pcall because a RemoteFunction throws if
-- the server errors, and a thrown error here would take the feed down with it.
local ok, admin = pcall(function()
	return whoAmI:InvokeServer()
end)
if not ok then
	warn("AdminController: WhoAmI failed — " .. tostring(admin))
	return
end
if not admin then
	-- The panel now also exists in StarterGui so it can be seen and edited in
	-- Studio's Edit viewport — which means every player is sent a copy of it. On a
	-- non-admin that copy goes, here, within a frame of joining. It is Visible =
	-- false in the tree and there is no controller left to open it, but leaving an
	-- "Admin!" panel sitting in a stranger's PlayerGui is not something to rely on
	-- invisibility for. The server refuses every request it could possibly send
	-- regardless; this is the second lock, not the only one.
	for _, name in ipairs({ "AdminPanel", "AdminButton" }) do
		local stray = hud:FindFirstChild(name)
		if stray then stray:Destroy() end
	end
	return
end

--=================================================================== THE FLY
local FLY_SPEED = ADMIN.FlySpeed or 70

local flying = false
local flyConn, flyForce, flyGyro

local function stopFly()
	flying = false
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if flyForce then
		flyForce:Destroy()
		flyForce = nil
	end
	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
	end
end

local function startFly()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return false end

	-- BodyVelocity, because it is the one that cancels gravity by simply being
	-- there: it drives velocity to a target every step, so a target of zero is a
	-- hover with no counter-force to compute.
	flyForce = Instance.new("BodyVelocity")
	flyForce.Name = "AdminFly"
	flyForce.MaxForce = Vector3.new(1, 1, 1) * math.huge
	flyForce.Velocity = Vector3.zero
	flyForce.Parent = root

	-- Keeps the character upright and pointed where the camera looks; without it
	-- the rig tumbles as soon as it leaves the ground.
	flyGyro = Instance.new("BodyGyro")
	flyGyro.Name = "AdminFlyGyro"
	flyGyro.MaxTorque = Vector3.new(1, 1, 1) * 4e5
	flyGyro.P = 2e4
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root

	-- Stops the walk/fall state machine fighting the velocity, and stops the
	-- character playing a falling animation for the whole flight.
	hum.PlatformStand = true

	flyConn = RunService.RenderStepped:Connect(function()
		if not flyForce or not flyForce.Parent then return end
		local cam = workspace.CurrentCamera
		-- MoveDirection, not IsKeyDown: it is already the world-space intent from
		-- whatever the player is using, so this works on a phone thumbstick with no
		-- extra code. It is flat, so vertical is added separately.
		local move = hum.MoveDirection
		local up = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then up += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			up -= 1
		end
		local dir = Vector3.new(move.X, 0, move.Z)
		if cam and move.Magnitude > 0 then
			-- Pitch the horizontal intent along the camera's look, so pushing
			-- forward while looking down descends. That is what makes it feel like
			-- flying rather than like a hovering walk.
			local look = cam.CFrame.LookVector
			dir = dir + Vector3.new(0, look.Y * move.Magnitude, 0)
		end
		dir = dir + Vector3.new(0, up, 0)
		if dir.Magnitude > 0 then
			dir = dir.Unit
		end
		flyForce.Velocity = dir * FLY_SPEED
		if cam then
			flyGyro.CFrame = CFrame.new(Vector3.zero, cam.CFrame.LookVector)
		end
	end)
	flying = true
	return true
end

-- A respawn destroys the force with the old character, so the flag has to come
-- down with it or the panel claims to be flying a character that is walking.
player.CharacterAdded:Connect(function()
	if flying then stopFly() end
end)

--================================================================= THE PANEL
local PANEL_ASPECT = 1.5
local PANEL_CORNER = 0.045

local Z_PANEL = 50
local Z_ROW = 54
local Z_CTRL = 56
local Z_TEXT = 57

-- UIKit.chrome expects the shell the other six panels get from StarterGui:
-- a UIScale named Scale, a Shadow frame with its own UICorner, an aspect
-- constraint, a corner, a UIStroke, a Title label carrying a UIStroke, and a
-- CloseButton with a UIScale. Built once, here, because this panel must not be
-- StarterGui furniture that replicates to every player.
-- Same find-or-create as the HUD counters, and for the same reason: the shell now
-- ships in StarterGui so it is visible in Studio's Edit viewport, and Edit does
-- not run LocalScripts. Adopting what is there rather than building a second copy
-- is what stops two panels existing; the look is still applied here, so the tree
-- only has to carry the shape.
local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(class) then return found end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = parent
	return made
end

local function buildShell()
	local panel = ensure(hud, "AdminPanel", "Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.62, 0.62)
	panel.BackgroundColor3 = P.Panel
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Visible = false
	panel.ZIndex = Z_PANEL

	local scale = ensure(panel, "Scale", "UIScale")

	local ar = ensure(panel, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
	ar.AspectRatio = PANEL_ASPECT

	local corner = ensure(panel, "UICorner", "UICorner")
	corner.CornerRadius = UDim.new(PANEL_CORNER, 0)

	local ring = ensure(panel, "UIStroke", "UIStroke")
	ring.Thickness = 4

	local shadow = ensure(panel, "Shadow", "Frame")
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Just below the panel, which is where the other panels' shells put it.
	shadow.Position = UDim2.fromScale(0.5, 0.508)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = Z_PANEL - 1
	ensure(shadow, "UICorner", "UICorner")

	local title = ensure(panel, "Title", "TextLabel")
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.TextScaled = true
	title.Text = ""
	ensure(title, "UIStroke", "UIStroke")

	local close = ensure(panel, "CloseButton", "TextButton")
	close.AutoButtonColor = false
	close.Text = ""
	close.BorderSizePixel = 0
	ensure(close, "Scale", "UIScale")
	local closeCorner = ensure(close, "UICorner", "UICorner")
	closeCorner.CornerRadius = UDim.new(0.3, 0)
	-- chrome RE-COLOURS these rather than creating them, because on the StarterGui
	-- panels they arrive with the shell — so a shell built in code has to supply
	-- them or chrome dies part-built. Checked against every FindFirstChildOfClass
	-- and .UICorner in chrome: the stroke and the gradient on the close button are
	-- the only two that are not created on demand. Everything else it reaches for
	-- (TitleIcon, Glyph, Lip, Studs, Rule, Body) it makes itself or skips.
	ensure(close, "UIStroke", "UIStroke")
	ensure(close, "UIGradient", "UIGradient")
	-- chrome centres the close glyph with this padding; without it the X sits high.
	local closePad = ensure(close, "UIPadding", "UIPadding")
	closePad.PaddingTop = UDim.new(0.2, 0)
	closePad.PaddingBottom = UDim.new(0.2, 0)
	closePad.PaddingLeft = UDim.new(0.2, 0)
	closePad.PaddingRight = UDim.new(0.2, 0)

	return panel, close
end

local panel, closeButton = buildShell()

local kit = UIKit.chrome(panel, {
	Palette = P,
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = ADMIN.Title or "Admin!",
	TitleIcon = ADMIN.TitleIcon,
})

-- The title runs a travelling rainbow, gated on the panel so it is not driving a
-- 30Hz loop while the panel is shut. chrome already leaves the title white, which
-- it has to be: the gradient multiplies what is under it.
UIKit.rainbow(kit.title, panel)

----------------------------------------------------------------------- rows
local list = ensure(panel, "Rows", "Frame")
list.BackgroundTransparency = 1
list.Position = UDim2.fromScale(0.05, 0.17)
list.Size = UDim2.fromScale(0.9, 0.77)
list.ZIndex = Z_ROW - 1
list.Parent = panel

local listLayout = ensure(list, "UIListLayout", "UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

local rows = {}

-- The tree may carry row plates from a previous build (they are real instances in
-- StarterGui now). They are rebuilt here every run, so the old ones go first or
-- the list layout stacks two of each.
for _, c in ipairs(list:GetChildren()) do
	if c:IsA("GuiObject") then c:Destroy() end
end

-- The same plate the Settings panel's rows are: name, blurb, control on the
-- right. Copied in shape rather than imported because SettingsController's
-- makeRow closes over its own values table and pulling it into UIKit would be a
-- refactor of a working panel for one caller.
local function makeRow(index, name, blurb)
	local plate = Instance.new("Frame")
	plate.Name = name
	plate.BackgroundColor3 = P.Panel
	plate.BorderSizePixel = 0
	plate.LayoutOrder = index
	plate.Size = UDim2.new(1, 0, 0, 1)
	plate.ZIndex = Z_ROW
	kit:corner(plate, 0.22)
	kit:stroke(plate, P.Ink:Lerp(P.Panel, 0.55), 2)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.035, 0.12)
	label.Size = UDim2.fromScale(0.5, 0.4)
	label.Text = name
	label.TextColor3 = P.BodyText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.FontFace = FONT
	label.TextScaled = true
	label.ZIndex = Z_TEXT
	kit:capText(label, 0.3)
	label.Parent = plate

	local sub = Instance.new("TextLabel")
	sub.Name = "Blurb"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0, 1)
	sub.Position = UDim2.fromScale(0.035, 0.9)
	sub.Size = UDim2.fromScale(0.5, 0.34)
	sub.Text = blurb or ""
	sub.TextColor3 = P.BodyText:Lerp(P.Panel, 0.42)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.FontFace = FONT
	sub.TextScaled = true
	sub.ZIndex = Z_TEXT
	kit:capText(sub, 0.21)
	sub.Parent = plate

	plate.Parent = list
	table.insert(rows, plate)
	return plate, sub
end

-- Every control on this panel is a button or a text field. That is not a style
-- choice: a slider is the one widget here that needs drag tracking, and Speed and
-- Time both have a handful of useful values, so stepping through them costs no
-- code at all next to a second copy of SettingsController's slider.
local function makeKey(parent, text, widthScale, xScale, pair)
	local key = Instance.new("TextButton")
	key.Name = text
	key.AutoButtonColor = false
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(xScale, 0.5)
	key.Size = UDim2.fromScale(widthScale, 0.56)
	key.BackgroundColor3 = pair[1]
	key.BorderSizePixel = 0
	key.Text = text
	key.TextColor3 = WHITE
	key.FontFace = FONT
	key.TextScaled = true
	key.ZIndex = Z_CTRL
	kit:corner(key, 0.3)
	kit:stroke(key, P.Ink, 2.2)
	kit:capText(key, 0.3)
	-- The TEXT contour, which the Settings pills also carry. Without it white type
	-- on a pale green or gold key has nothing holding it and SEND, + and Dawn all
	-- read as washed out. One UIStroke takes effect per instance, so this replaces
	-- the border from kit:stroke above — on a key this small the letterforms are
	-- worth more than the outline.
	kit:outline(key, 2)
	UIKit.bevel(key, pair)
	-- 0.38, not half: the gloss sheet is opaque and on a key this small at half
	-- height the white owns the whole thing. Same figure the Settings GO key needed.
	UIKit.gloss(key, 0.38, 0.3, 0.6)
	UIKit.audible(key)
	UIKit.feel(key)
	key.Parent = parent
	return key
end

------------------------------------------------------------------- 1. message
do
	local plate, sub = makeRow(1, "Global Message", "Everyone sees it. Your name is on it.")
	local resting = sub.Text

	local token = 0
	local function say(msg)
		token += 1
		local mine = token
		sub.Text = msg
		task.delay(2.6, function()
			if token == mine then sub.Text = resting end
		end)
	end

	local wrap = Instance.new("Frame")
	wrap.Name = "Compose"
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(1, 0.5)
	wrap.Position = UDim2.fromScale(0.97, 0.5)
	wrap.Size = UDim2.fromScale(0.46, 0.56)
	wrap.ZIndex = Z_CTRL

	local box = Instance.new("TextBox")
	box.Name = "Field"
	box.Size = UDim2.fromScale(0.62, 1)
	box.BackgroundColor3 = WHITE
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = "Say something..."
	box.PlaceholderColor3 = P.BodyText:Lerp(P.Panel, 0.55)
	box.TextColor3 = P.BodyText
	box.ClearTextOnFocus = false
	box.FontFace = FONT
	box.TextScaled = true
	box.ZIndex = Z_CTRL
	kit:corner(box, 0.3)
	kit:stroke(box, P.Ink, 2.2)
	kit:capText(box, 0.3)
	box.Parent = wrap

	local send = makeKey(wrap, "SEND", 0.32, 0.84, P.Green)

	local function submit()
		local text = box.Text:gsub("%s+", " "):match("^%s*(.-)%s*$")
		if text == "" then return end
		-- Only the TEXT goes up. The server fills in who said it, which is why a
		-- client cannot announce as somebody else.
		announce:FireServer(text)
		box.Text = ""
		say("Sent!")
	end

	send.MouseButton1Click:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	wrap.Parent = plate
end

----------------------------------------------------------------------- 2. fly
do
	local plate = makeRow(2, "Fly", "Space up, Shift down. Stick works too.")

	local pill = Instance.new("TextButton")
	pill.Name = "Toggle"
	pill.AutoButtonColor = false
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.fromScale(0.97, 0.5)
	pill.Size = UDim2.fromScale(0.2, 0.56)
	pill.BorderSizePixel = 0
	pill.TextColor3 = WHITE
	pill.FontFace = FONT
	pill.TextScaled = true
	pill.ZIndex = Z_CTRL
	kit:corner(pill, 0.4)
	kit:stroke(pill, P.Ink, 2.2)
	kit:outline(pill, 2)
	kit:capText(pill, 0.32)
	UIKit.gloss(pill, 0.5, 0.4, 0.6)
	UIKit.audible(pill)
	UIKit.feel(pill)

	local OFF_PAIR = { P.Close, P.CloseDeep }
	local grad
	local function paint()
		local pair = flying and P.Green or OFF_PAIR
		pill.Text = flying and "ON" or "OFF"
		pill.BackgroundColor3 = pair[1]
		-- An instance takes one UIGradient, so the old one goes before the new
		-- colour's is applied or the pill keeps the ramp it was built in.
		if grad then grad:Destroy() end
		grad = UIKit.bevel(pill, pair)
	end

	pill.MouseButton1Click:Connect(function()
		if flying then
			stopFly()
		else
			startFly()
		end
		paint()
	end)

	paint()
	pill.Parent = plate

	-- The flag can come down without the pill being touched — a respawn stops the
	-- flight — so the pill follows the flag rather than assuming it owns it.
	player.CharacterAdded:Connect(function()
		task.defer(paint)
	end)
end

--------------------------------------------------------------------- 3. speed
do
	local plate, sub = makeRow(3, "Speed", "Applied by the server, so it is real.")
	local speeds = ADMIN.Speeds or { 16 }
	local at = 1
	local resting = sub.Text

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.83, 0.5)
	value.Size = UDim2.fromScale(0.14, 0.5)
	value.Text = tostring(speeds[at])
	value.TextColor3 = P.BodyText
	value.FontFace = FONT
	value.TextScaled = true
	value.ZIndex = Z_TEXT
	kit:capText(value, 0.32)
	value.Parent = plate

	local function apply()
		value.Text = tostring(speeds[at])
		command:FireServer("Speed", speeds[at])
		sub.Text = ("WalkSpeed %d"):format(speeds[at])
		task.delay(2.6, function()
			if sub.Text == ("WalkSpeed %d"):format(speeds[at]) then sub.Text = resting end
		end)
	end

	local minus = makeKey(plate, "-", 0.09, 0.73, { P.Close, P.CloseDeep })
	local plus = makeKey(plate, "+", 0.09, 0.94, P.Green)
	minus.MouseButton1Click:Connect(function()
		at = math.max(1, at - 1)
		apply()
	end)
	plus.MouseButton1Click:Connect(function()
		at = math.min(#speeds, at + 1)
		apply()
	end)
end

---------------------------------------------------------------------- 4. time
do
	local plate = makeRow(4, "Time", "Live follows real world time, for everyone.")
	local times = ADMIN.Times or {}
	-- Right-aligned as a group: the rightmost key sits where every other row's
	-- control sits, and the rest run back from it. Narrower now that there are
	-- four of them.
	local w = 0.135
	local gap = 0.015
	for i, t in ipairs(times) do
		local fromRight = #times - i
		local x = 0.97 - w / 2 - fromRight * (w + gap)
		local pair = (t.Label == "Night") and { P.Ink:Lerp(P.Panel, 0.35), P.Ink }
			or (t.Label == "Noon") and P.Gold
			or (t.Label == "Live") and P.Green
			or P.Cyan
		local key = makeKey(plate, t.Label, w, x, pair or P.Green)
		key.MouseButton1Click:Connect(function()
			-- "Live" as a string, a number for a pinned hour. The server accepts
			-- exactly those two and ignores anything else.
			command:FireServer("Time", t.Live and "Live" or t.Clock)
		end)
	end
end

------------------------------------------------------------------- the button
-- A crown key in the top-right. Created HERE, which is below the admin check, so
-- the instance does not exist on a non-admin client — the same rule the panel
-- follows, and the reason neither shows up in Studio's Edit viewport.
local BTN = ADMIN.Button or {}
local Z_BUTTON = 130   -- over the panels (50..63) and the bag (120), under the
                       -- message feed (200): the way in must not be coverable

-- Adopted, not created: it ships in StarterGui so it is visible in Studio's Edit
-- viewport, which means every player is sent one and the non-admin branch above
-- destroys it. ensure() is defined with buildShell, for the same reason.
local button = ensure(hud, "AdminButton", "ImageButton")
button.AutoButtonColor = false
button.AnchorPoint = Vector2.new(1, 0.5)
-- Y is set in sizeButton, in PIXELS off the GUI inset — see the note there.
button.Position = UDim2.fromScale((BTN.Pos or Vector2.new(0.975, 0.075)).X, 0)
-- BARE ARTWORK on a transparent ground, which is what every tile in the HUD grid
-- is — see makeTile's note in HUDController. It shipped as a bevelled violet key
-- and that made it the only plated control on the screen, a lone purple square in
-- a corner surrounded by cut-out icons.
--
-- Nothing is lost by dropping the plate: UIKit.feel already pops it to 1.12 and
-- tilts it 4 degrees on hover, which is the same feedback the tiles get and is
-- enough without a plate behind it to grow.
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.Image = ""
button.ZIndex = Z_BUTTON
button.Visible = true

-- A plate's furniture drawn on a transparent button is worse than useless: a
-- UIStroke strokes the button's BORDER, so it would draw a rounded rectangle
-- around nothing, and a UIGradient from bevel() tints the artwork. They are
-- destroyed rather than skipped because the tree may still carry them from an
-- earlier build of this key.
for _, c in ipairs(button:GetChildren()) do
	if c:IsA("UIStroke") or c:IsA("UICorner") or c:IsA("UIGradient")
		or c.Name == "Gloss" then
		c:Destroy()
	end
end
UIKit.audible(button)
UIKit.feel(button, { Grow = 1.12, Tilt = -4 })

-- Square off the HEIGHT, and floored to a whole pixel: the constraint only ever
-- shrinks, so both scales are generous and the square comes off the shorter side.
local btnAspect = ensure(button, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
btnAspect.AspectRatio = 1
btnAspect.DominantAxis = Enum.DominantAxis.Height

local btnCap = ensure(button, "UISizeConstraint", "UISizeConstraint")
btnCap.MinSize = Vector2.new(BTN.MinPx or 44, BTN.MinPx or 44)
btnCap.MaxSize = Vector2.new(BTN.MaxPx or 84, BTN.MaxPx or 84)

-- Still a CHILD label rather than the button's own Image, now that there is no
-- gradient to hide from: a child can be scaled and nudged independently of the
-- button's hit area, and the hit area is what has to stay a full square for the
-- 44px tap floor.
local btnIcon = ensure(button, "Crown", "ImageLabel")
btnIcon.BackgroundTransparency = 1
btnIcon.AnchorPoint = Vector2.new(0.5, 0.5)
btnIcon.Position = UDim2.fromScale(0.5, 0.5)
-- Fills it: with no plate around it the artwork IS the button, so the 0.78 it
-- sat at inside the key is just a smaller crown.
btnIcon.Size = UDim2.fromScale(1, 1)
btnIcon.Image = ADMIN.TitleIcon or ""
btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.ZIndex = Z_BUTTON + 1

--------------------------------------------------------------------- open/close
local open = false

local hudOpen = hud:WaitForChild("HUDOpenPanel", 20)

local function setOpen(state)
	open = state
	panel.Visible = state
	if state then
		-- Clear whichever of the six is up. Two panels at ZIndex 50 on screen at
		-- once is what this looked like without it: the daily auto-opens at join,
		-- and F2 put this one straight through it.
		if hudOpen then
			pcall(function() hudOpen:Invoke(nil, false) end)
		end
		local scale = panel:FindFirstChild("Scale")
		if scale then
			scale.Scale = 0.8
			TweenService:Create(
				scale,
				TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end
end

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)

button.MouseButton1Click:Connect(function()
	setOpen(not open)
end)

-- And the other direction: opening a shop or an inventory closes this one, so the
-- two systems cannot both have a panel up. HUDController publishes the name.
hud:GetAttributeChangedSignal("OpenPanel"):Connect(function()
	if open and hud:GetAttribute("OpenPanel") ~= nil then
		setOpen(false)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	-- processed: the keybind must not fire while the admin is typing INTO the
	-- panel's own message box.
	if processed then return end
	if input.KeyCode == (ADMIN.Keybind or Enum.KeyCode.F2) then
		setOpen(not open)
	end
end)

------------------------------------------------------------------- layout
local function sizeButton()
	local h = hud.AbsoluteSize.Y
	if h <= 0 then return end
	local edge = math.floor(h * (BTN.Size or 0.075))
	button.Size = UDim2.fromOffset(edge, edge)

	-- THE GUI INSET. The HUD sets IgnoreGuiInset, so its local space starts about
	-- 36px ABOVE the visible screen — the same trap InventoryController's
	-- placeHeader documents. A scale position of 0.075 therefore put this key's
	-- top edge 2px from the top of the display, under the topbar on a desktop and
	-- into the notch on a phone. Anchored at its own centre, so the centre goes
	-- one half-edge plus a margin below where the screen actually starts.
	local inset = GuiService:GetGuiInset().Y
	button.Position = UDim2.new(
		(BTN.Pos or Vector2.new(0.975, 0.075)).X, 0,
		0, inset + math.floor(edge * 0.5) + math.floor(h * 0.018)
	)
end

local function relayout()
	sizeButton()
	local k = math.max(panel:FindFirstChild("Scale") and panel.Scale.Scale or 1, 0.01)
	local h = list.AbsoluteSize.Y / k
	if h <= 0 then return end
	local n = math.max(#rows, 1)
	local gap = math.floor(h * 0.05)
	local rh = math.max(math.floor((h - gap * (n - 1)) / n), 1)
	listLayout.Padding = UDim.new(0, gap)
	for _, plate in ipairs(rows) do
		plate.Size = UDim2.new(1, 0, 0, rh)
	end
	kit:relayout(rh)
	kit:rescale()
end

list:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()
layoutFeed()

print(("AdminController: panel built for %s — crown in the top-right, or %s")
	:format(player.Name, (ADMIN.Keybind or Enum.KeyCode.F2).Name))
