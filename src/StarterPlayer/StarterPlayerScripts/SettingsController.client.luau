--[[
	SettingsController — fills StarterGui.HUD.SettingsPanel.

	EVERY SWITCH ON THIS PANEL DOES SOMETHING. That is the design rule, and it is
	why the list is four rows rather than twelve. The rest of this game is full of
	controls waiting on a server that does not exist yet — the inventory rail, the
	index categories, every price in the shop. Settings are the one thing a client
	can own outright, so there was no excuse for a row of dead toggles here.

	What each key actually drives:

	  SfxVolume    a SoundGroup that every UI sound is moved into, including ones
	               created later by UIKit.sound.
	  MenuBlur     an attribute on the HUD that HUDController's syncBlur reads.
	  Shadows      Lighting.GlobalShadows, directly.
	  ReduceMotion an attribute read by the shop tile's spin and the daily panel's
	               rainbow, both of which stop when it is on.
	  Codes        NOT a setting, and the one exception to the rule above: a text
	               field that recognises a code and answers on the row's blurb
	               line. It grants nothing — there is no server — and the blurb
	               at rest is the TikTok handle the codes come from.

	Every control also carries UIKit.feel — hover pop, press squash, release —
	because a switch with a click sound and no movement reads as a dead control
	that beeps. The slider is deliberately excluded: its knob already follows the
	drag, and a pop on top of that fights the gesture.

	Nothing PERSISTS — there is no DataStore — so these last until the player
	leaves. The seam for that is store()/load() at the bottom.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local SET = CONFIG.Settings
local P = CONFIG.Shop.Palette

local WHITE = UIKit.WHITE
local FONT = UIKit.FONT

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("SettingsPanel")

------------------------------------------------------------------------ spec
local PANEL_ASPECT = 1.62
local PANEL_CORNER = 0.045

local LIST_X0, LIST_X1 = 0.05, 0.95
local LIST_Y0, LIST_Y1 = 0.17, 0.94

local Z_ROW = 54
local Z_CTRL = 56
local Z_TEXT = 57
local Z_KNOB = 58

local kit = UIKit.chrome(panel, {
	Palette = P,
	Aspect = PANEL_ASPECT,
	Corner = PANEL_CORNER,
	Title = SET.Title,
	TitleIcon = SET.TitleIcon,
})

------------------------------------------------------------------ the sounds
-- Every UI sound in the game is created by UIKit.sound and parented straight to
-- SoundService. A SoundGroup is the only handle that scales all of them at once —
-- and, unlike walking the list and setting Volume, it does not destroy each
-- sound's own mix, because SoundGroup.Volume multiplies rather than replaces.
local sfxGroup = SoundService:FindFirstChild("UISfx")
if not sfxGroup then
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "UISfx"
	sfxGroup.Parent = SoundService
end
-- ONLY sounds with no group of their own. It used to adopt every Sound under
-- SoundService unconditionally, which is fine while the only sounds in the game
-- are UI ones and wrong the moment anything else exists: MusicController's three
-- tracks were swallowed into UISfx within a frame of being created, so the sound
-- effects slider silenced the music. UIKit creates its sounds with no group, so
-- the guard costs this nothing.
local function adopt(inst)
	if inst:IsA("Sound") and inst.SoundGroup == nil then
		inst.SoundGroup = sfxGroup
	end
end
for _, c in ipairs(SoundService:GetChildren()) do
	adopt(c)
end
-- Controllers build at their own pace and some create their sounds after this one
-- has run, so later arrivals are adopted too rather than silently escaping the
-- volume slider.
SoundService.ChildAdded:Connect(adopt)

----------------------------------------------------------------------- state
local values = {}
for _, row in ipairs(SET.Rows or {}) do
	values[row.Key] = row.Default
end

local APPLY = {
	SfxVolume = function(v)
		sfxGroup.Volume = math.clamp(v, 0, 1)
	end,
	MenuBlur = function(v)
		-- Published, not reached for. HUDController owns the BlurEffect and reads
		-- this in syncBlur; an attribute keeps that one-way.
		hud:SetAttribute("MenuBlur", v and true or false)
		local blur = Lighting:FindFirstChild("PanelBlur")
		-- Take effect NOW as well as on the next open, or a player turning it off
		-- with a panel already in front of them sees nothing happen.
		if blur and not v then
			blur.Enabled = false
		end
	end,
	Shadows = function(v)
		Lighting.GlobalShadows = v and true or false
	end,
	ReduceMotion = function(v)
		hud:SetAttribute("ReduceMotion", v and true or false)
	end,
}

local function apply(key)
	local fn = APPLY[key]
	if fn then fn(values[key]) end
end

----------------------------------------------------------------------- build
local list = Instance.new("Frame")
list.Name = "Rows"
list.BackgroundTransparency = 1
list.Position = UDim2.fromScale(LIST_X0, LIST_Y0)
list.Size = UDim2.fromScale(LIST_X1 - LIST_X0, LIST_Y1 - LIST_Y0)
list.ZIndex = Z_ROW - 1
list.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local function makeToggle(row, plate)
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
	-- It had the sound and none of the movement, which is the combination that
	-- reads as a dead control that happens to beep. Anchored at its right edge, so
	-- the pop grows leftward into the row rather than out past the panel.
	UIKit.feel(pill)

	-- OFF is the close button's red, which is already this panel family's "no".
	local OFF_PAIR = { P.Close, P.CloseDeep }
	local grad -- the bevel's gradient; rebuilt on every flip
	local function paint()
		local on = values[row.Key] and true or false
		local pair = on and P.Green or OFF_PAIR
		pill.Text = on and (SET.OnLabel or "ON") or (SET.OffLabel or "OFF")
		pill.BackgroundColor3 = pair[1]
		if grad then grad:Destroy() end
		-- bevel() adds a UIGradient, and an instance takes only one — so the old
		-- one has to go before the new colour's is applied or the pill keeps the
		-- ramp of whichever state it was built in.
		grad = UIKit.bevel(pill, pair)
	end

	pill.MouseButton1Click:Connect(function()
		values[row.Key] = not values[row.Key]
		paint()
		apply(row.Key)
	end)

	paint()
	pill.Parent = plate
	return pill
end

local function makeSlider(row, plate)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(0.97, 0.5)
	track.Size = UDim2.fromScale(0.28, 0.3)
	track.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.55)
	track.BorderSizePixel = 0
	-- ACTIVE. A Frame does not receive InputBegan for mouse BUTTONS unless this is
	-- true — the press passes straight through it — which a TextButton never has to
	-- ask for and is why this was missed. Without it the slider renders perfectly,
	-- responds to nothing, and reports no error of any kind.
	track.Active = true
	track.ZIndex = Z_CTRL
	kit:corner(track, 0.5)
	kit:stroke(track, P.Ink, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.BackgroundColor3 = P.Green[1]
	fill.BorderSizePixel = 0
	fill.ZIndex = Z_CTRL + 1
	kit:corner(fill, 0.5)
	fill.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromScale(1, 2.1)
	-- Square via the constraint, which only ever SHRINKS — so both scales are
	-- generous and the square it settles on comes off the track's height.
	local kar = Instance.new("UIAspectRatioConstraint")
	kar.AspectRatio = 1
	kar.Parent = knob
	knob.BackgroundColor3 = WHITE
	knob.BorderSizePixel = 0
	knob.ZIndex = Z_KNOB
	kit:corner(knob, 0.5)
	kit:stroke(knob, P.Ink, 2.2)
	knob.Parent = track

	local function paint()
		local v = math.clamp(values[row.Key] or 0, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
	end

	-- Dragging, by hand: Roblox has no slider widget. The whole gesture is owned
	-- here rather than on the knob, because a fast drag outruns the knob and the
	-- pointer leaves it — tracking on the TRACK and following UserInputService
	-- until the button comes up is what makes it not slip.
	local dragging = false
	local function setFromX(x)
		local left = track.AbsolutePosition.X
		local wide = math.max(track.AbsoluteSize.X, 1)
		values[row.Key] = math.clamp((x - left) / wide, 0, 1)
		paint()
		apply(row.Key)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	paint()
	track.Parent = plate
	return track
end

-- A code is not a setting, so it has no APPLY handler and no entry in values
-- that anything reads. What it has is a text field, a GO key, and an answer.
--
-- ponytail: RECOGNITION ONLY. GameConfig.Settings.Codes maps code -> what the row
-- says back; nothing is granted, because there is no server to grant it and a
-- client that hands itself coins is the first thing an exploiter finds. Upgrade
-- path: a RedeemCode RemoteFunction returning the same string, table moved
-- server-side.
local redeemed = {}

local function redeem(text)
	-- Uppercased with every space stripped: players paste codes with a trailing
	-- space off TikTok more often than they type them clean.
	local key = (text:upper():gsub("%s", ""))
	if key == "" then return nil end
	local msg = SET.Codes and SET.Codes[key]
	if not msg then return SET.CodeBad or "That code is not real!" end
	if redeemed[key] then return SET.CodeUsed or "Already used that one!" end
	redeemed[key] = true
	return msg
end

local function makeCode(row, plate, sub)
	local resting = sub.Text

	-- The answer lands on the row's own blurb and the blurb comes back, so the
	-- TikTok tag is what the row reads as at rest. Token, not a cancelled task:
	-- two fast submissions each schedule a restore, and without it the first one
	-- wipes the second one's answer.
	local token = 0
	local function say(msg)
		token += 1
		local mine = token
		sub.Text = msg
		task.delay(SET.CodeFlash or 2.6, function()
			if token == mine then sub.Text = resting end
		end)
	end

	local wrap = Instance.new("Frame")
	wrap.Name = "Code"
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(1, 0.5)
	wrap.Position = UDim2.fromScale(0.97, 0.5)
	wrap.Size = UDim2.fromScale(0.42, 0.56)
	wrap.ZIndex = Z_CTRL

	local box = Instance.new("TextBox")
	box.Name = "Field"
	box.Size = UDim2.fromScale(0.6, 1)
	box.BackgroundColor3 = WHITE
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = SET.CodePlaceholder or "Enter code..."
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

	local go = Instance.new("TextButton")
	go.Name = "Go"
	go.AutoButtonColor = false
	go.AnchorPoint = Vector2.new(1, 0)
	go.Position = UDim2.fromScale(1, 0)
	go.Size = UDim2.fromScale(0.36, 1)
	go.BackgroundColor3 = P.Green[1]
	go.BorderSizePixel = 0
	go.Text = SET.CodeButton or "GO"
	go.TextColor3 = WHITE
	go.FontFace = FONT
	go.TextScaled = true
	go.ZIndex = Z_CTRL
	kit:corner(go, 0.3)
	kit:stroke(go, P.Ink, 2.2)
	kit:outline(go, 2)
	kit:capText(go, 0.32)
	UIKit.bevel(go, P.Green)
	-- 0.38, not the toggle pill's 0.5. The gloss sheet is OPAQUE white, and this
	-- key is 65px wide against the pill's 130 — at half its height the white owned
	-- the whole thing and the key read grey next to green ON pills three rows up.
	-- Judged at 1:1 in Play, which is the only place the size difference shows.
	UIKit.gloss(go, 0.38, 0.3, 0.6)
	UIKit.audible(go)
	UIKit.feel(go)
	go.Parent = wrap

	local function submit()
		local msg = redeem(box.Text)
		if msg then
			say(msg)
			box.Text = ""
		end
	end

	go.MouseButton1Click:Connect(submit)
	-- Enter submits too; enterPressed is false when focus is merely lost, which is
	-- the difference between a player pressing Return and one clicking elsewhere.
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	wrap.Parent = plate
	return wrap
end

local rows = {}

local function makeRow(index, row)
	local plate = Instance.new("Frame")
	plate.Name = row.Key
	plate.BackgroundColor3 = P.Panel
	plate.BorderSizePixel = 0
	plate.LayoutOrder = index
	plate.Size = UDim2.new(1, 0, 0, 1)
	plate.ZIndex = Z_ROW
	kit:corner(plate, 0.22)
	kit:stroke(plate, P.Ink:Lerp(P.Panel, 0.55), 2)

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0, 0)
	name.Position = UDim2.fromScale(0.035, 0.12)
	name.Size = UDim2.fromScale(0.6, 0.4)
	name.Text = row.Name or row.Key
	name.TextColor3 = P.BodyText
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.FontFace = FONT
	name.TextScaled = true
	name.ZIndex = Z_TEXT
	kit:capText(name, 0.3)
	name.Parent = plate

	local sub = Instance.new("TextLabel")
	sub.Name = "Blurb"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0, 1)
	sub.Position = UDim2.fromScale(0.035, 0.9)
	sub.Size = UDim2.fromScale(0.6, 0.34)
	sub.Text = row.Blurb or ""
	-- Greyed against the row's own name, not another navy line: the two sit three
	-- pixels apart and at the same colour they read as one wrapped sentence.
	sub.TextColor3 = P.BodyText:Lerp(P.Panel, 0.42)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.FontFace = FONT
	sub.TextScaled = true
	sub.ZIndex = Z_TEXT
	kit:capText(sub, 0.21)
	sub.Parent = plate

	if row.Kind == "Slider" then
		makeSlider(row, plate)
	elseif row.Kind == "Code" then
		makeCode(row, plate, sub)
	else
		makeToggle(row, plate)
	end

	plate.Parent = list
	table.insert(rows, plate)
	return plate
end

for i, row in ipairs(SET.Rows or {}) do
	makeRow(i, row)
end

-- Apply every default once at startup, so the world matches what the panel claims
-- before anybody opens it.
for key in pairs(values) do
	apply(key)
end

-- THE CHECK. A row whose Key has no handler renders perfectly, flips its pill on
-- click, and does nothing — which is the exact failure this panel exists to avoid,
-- and it is invisible from the screen. It already happened once: GameConfig said
-- "PanelBlur" and the handler was "MenuBlur". A settings row is a two-part thing
-- across two files, so the halves get checked against each other here.
for _, row in ipairs(SET.Rows or {}) do
	-- A Code row is wired to its own submit handler, not to APPLY, so it is
	-- legitimately handler-less and must not be reported as dead.
	if row.Kind == "Code" then
		continue
	end
	if not APPLY[row.Key] then
		warn(("SettingsController: row %q (%s) has no APPLY handler — it will do nothing")
			:format(row.Key, row.Name or "?"))
	end
end

------------------------------------------------------------------- layout
local function relayout()
	-- Divide the UIScale back out, as every panel here does: HUDController pops the
	-- panel 0.8 -> 1 on open with a Back ease that overshoots, and a row height in
	-- OFFSET recomputed from the scaled box re-flows the list while it is also
	-- being scaled.
	local k = math.max(panel.Scale.Scale, 0.01)
	local w = list.AbsoluteSize.X / k
	local h = list.AbsoluteSize.Y / k
	if w <= 0 or h <= 0 then return end

	local n = math.max(#rows, 1)
	local gap = math.floor(h * 0.045)
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
