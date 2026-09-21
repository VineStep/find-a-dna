--[[
	WorldPrompt — a plate floating over a thing in the world that you CLICK.

	Two callers now (the DNA machine and the cave's Entry arch), which is why it
	is a module rather than a second copy: everything about how one of these
	looks, appears, disappears and answers a press lives here once.

	NOT A ProximityPrompt. The DNA machine used one for several revisions and it
	was the right call while the interaction was "press E" — Style = Custom kept
	Roblox's distance tracking, arbitration and touch button and only took away
	the default grey pill. Once the keyboard key went and clicking became the only
	way in, all that was left of it was a distance check this already does for the
	highlight, and a second range that could disagree with the first. So the
	prompt's own range tracking went with the key.

	WHAT DRIVES VISIBILITY is one throttled distance poll, shared by the plate and
	the highlight, so they cannot fall out of step. Both appear at ShowDistance and
	the plate POPS in and out rather than blinking — a billboard that snaps on at a
	fixed radius reads as a rendering glitch, and the pop is what makes it read as
	the object noticing you.

	A BillboardGui MUST be parented to PlayerGui, never inside a ScreenGui: nested
	in one it renders nothing at all — no error, no warning, it simply never
	appears. Its MaxDistance is also measured from the CAMERA while everything else
	here measures from the CHARACTER, so it is left at infinity and this module
	owns visibility outright.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local WorldPrompt = {}
WorldPrompt.__index = WorldPrompt

local player = Players.LocalPlayer

-- The world AABB of a model or part. Model:GetBoundingBox returns an ORIENTED box
-- in the model's own pivot frame, and a rotated pivot comes back with the axes
-- swapped — so anything axis-aligned has to be computed by projecting each part's
-- half-extents onto the world axes.
function WorldPrompt.worldBox(inst)
	local mn, mx
	local parts = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
	for _, d in ipairs(parts) do
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

-- WAIT FOR THE PARTS, not just for the instance. WaitForChild returns a Model the
-- instant it replicates and its descendants arrive after, so measuring straight
-- away finds nothing. Settles on the part COUNT rather than the first part: the
-- box is sized off the FULL extent, and building it from the three that happened
-- to arrive first would frame a third of the object.
function WorldPrompt.awaitParts(inst, timeout)
	local deadline = os.clock() + (timeout or 20)
	local last = -1
	while os.clock() < deadline do
		local n = 0
		if inst:IsA("BasePart") then n = 1 end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
		end
		if n > 0 and n == last then return true end
		last = n
		task.wait(0.25)
	end
	return last > 0
end

--[[
	opts:
	  Target        Model or BasePart the plate belongs to and the click lands on
	  Palette       GameConfig.Shop.Palette
	  ActionText    the big line
	  ObjectText    the small line under it
	  Height        plate height in STUDS (scale on a BillboardGui is studs)
	  Aspect        plate width / height
	  Rise          studs above the target's box top; 0 sits at its centre
	  ShowDistance  studs at which the plate and the highlight appear
	  ShowPoll      seconds between distance checks
	  PopIn/PopOut  seconds for the pop animation
	  Highlight     nil, or a table of Fill/Outline colours and transparencies
	  OnActivate    called when the plate or the target is clicked
]]
function WorldPrompt.new(opts)
	local self = setmetatable({}, WorldPrompt)
	local P = opts.Palette
	local target = opts.Target

	WorldPrompt.awaitParts(target)
	local mn, mx = WorldPrompt.worldBox(target)
	if not mn then
		warn(("WorldPrompt: %s has no BaseParts."):format(target:GetFullName()))
		return nil
	end

	self.centre = (mn + mx) / 2
	self.onActivate = opts.OnActivate
	self.showDistance = opts.ShowDistance or 140
	self.shown = false
	self.hovering = false

	------------------------------------------------------------------ the anchor
	-- The plate needs one fixed home. Adorned to the target itself, a multi-part
	-- object makes the billboard jump between pieces; an invisible part at the box
	-- centre does not move.
	local anchor = Instance.new("Part")
	anchor.Name = "PromptAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false      -- must never intercept the click meant for the target
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(self.centre)
	anchor.Parent = opts.Parent or workspace
	self.anchor = anchor

	------------------------------------------------------------------- the plate
	local h = opts.Height or 3.6
	local gui = Instance.new("BillboardGui")
	gui.Name = (opts.Name or "World") .. "Prompt"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	-- ACTIVE, and this is not optional: a BillboardGui's descendants receive NO
	-- mouse input at all unless the BillboardGui itself is Active. It defaults to
	-- false, so the plate was a perfectly laid-out button that never fired
	-- MouseEnter, let alone MouseButton1Click — the machine only worked because
	-- its ClickDetector was doing all the pressing. On the Entry arch, where cave
	-- rock sits between the camera and the block and the ray never reaches the
	-- ClickDetector, the plate was the only way in and there was no way in.
	gui.Active = true
	gui.LightInfluence = 0
	gui.MaxDistance = math.huge   -- camera-relative; this module owns visibility
	gui.Size = UDim2.fromScale(h * (opts.Aspect or 3.15), h)
	gui.StudsOffsetWorldSpace = Vector3.new(0, opts.Rise or 0, 0)
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui

	local plate = Instance.new("TextButton")
	plate.Name = "Plate"
	plate.AutoButtonColor = false
	plate.Text = ""
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = P.Panel
	plate.BorderSizePixel = 0
	plate.Parent = gui
	self.plate = plate

	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = plate
		local s = Instance.new("UIStroke")
		s.Color = P.Ink
		s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = plate
	end
	UIKit.gloss(plate, 0.4, 0.3, 0.7)

	local scale = Instance.new("UIScale")
	scale.Parent = plate
	self.scale = scale

	-- NO KEY CAP. The plate carried a cyan "E" while a ProximityPrompt was driving
	-- it; clicking is now the only way in, so a key legend would be an instruction
	-- to press something that does nothing. The text takes the whole plate.
	local action = Instance.new("TextLabel")
	action.Name = "Action"
	action.BackgroundTransparency = 1
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.fromScale(0.5, 0.55)
	action.Size = UDim2.fromScale(0.9, 0.36)
	action.Text = opts.ActionText or ""
	action.TextColor3 = P.BodyText
	action.FontFace = UIKit.FONT
	action.TextScaled = true
	action.ZIndex = 2
	action.Parent = plate

	local object = Instance.new("TextLabel")
	object.Name = "Object"
	object.BackgroundTransparency = 1
	object.AnchorPoint = Vector2.new(0.5, 0)
	object.Position = UDim2.fromScale(0.5, 0.58)
	object.Size = UDim2.fromScale(0.9, 0.24)
	object.Text = opts.ObjectText or ""
	object.TextColor3 = P.BodyText:Lerp(P.Panel, 0.45)
	object.FontFace = UIKit.FONT
	object.TextScaled = true
	object.ZIndex = 2
	object.Parent = plate
	self.action, self.object = action, object

	--------------------------------------------------------------- the highlight
	-- Optional: the Entry arch does not want one, the DNA machine does.
	local hl = opts.Highlight
	if hl then
		local glow = Instance.new("Highlight")
		glow.Name = "PromptGlow"
		-- ALWAYSONTOP is what turns a Highlight into a border. Occluded draws the
		-- contour only where the object is already visible, which on anything with
		-- transparent parts is almost nowhere. The usual objection to AlwaysOnTop is
		-- the FILL painting over the world on a model you can stand inside — that is
		-- about the fill, so the fill stays near-transparent and the outline works.
		glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		glow.FillColor = hl.FillColour or P.Cyan[1]
		glow.OutlineColor = hl.OutlineColour or P.Cyan[2]
		glow.FillTransparency = hl.FillTransparency or 0.88
		glow.OutlineTransparency = hl.OutlineTransparency or 0
		glow.Enabled = false
		glow.Adornee = target
		glow.Parent = target
		self.glow = glow
		self.hl = hl
	end

	------------------------------------------------------------------- the click
	-- On the MODEL where the target is one: a ClickDetector on a single part only
	-- answers clicks on that part, and these objects are several pieces.
	local sfxHover = UIKit.sound(opts.HoverSound or 10066931761, opts.HoverVolume or 0.3)
	local sfxClick = UIKit.sound(opts.ClickSound or 10128760939, opts.ClickVolume or 0.5)

	local click = Instance.new("ClickDetector")
	click.Name = "PromptClick"
	-- THE SAME RANGE the plate appears at. Two ranges would mean a plate you can
	-- read and cannot press, which is worse than no plate.
	click.MaxActivationDistance = self.showDistance
	click.CursorIcon = ""
	click.Parent = target
	self.click = click

	local function press()
		sfxClick:Play()
		scale.Scale = (opts.PressDrop or 0.93) * (self.hovering and (opts.HoverGrow or 1.08) or 1)
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out),
			{ Scale = self.hovering and (opts.HoverGrow or 1.08) or 1 }):Play()
		if self.onActivate then self.onActivate() end
	end

	click.MouseHoverEnter:Connect(function()
		if self.hovering or not self.shown then return end
		self.hovering = true
		sfxHover:Play()
		self:paint()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = opts.HoverGrow or 1.08 }):Play()
	end)
	click.MouseHoverLeave:Connect(function()
		if not self.hovering then return end
		self.hovering = false
		self:paint()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad),
			{ Scale = 1 }):Play()
	end)
	click.MouseClick:Connect(press)
	-- The plate itself is a button too, which is what makes this work on touch
	-- where there is no hover and no cursor to put on the object.
	plate.MouseButton1Click:Connect(press)

	self.popIn = opts.PopIn or 0.22
	self.popOut = opts.PopOut or 0.14
	self.popFrom = opts.PopFrom or 0.4
	self.hoverGrow = opts.HoverGrow or 1.08
	self.farFill = hl and hl.FarFillTransparency or nil
	self.farAt = hl and hl.FarFillAt or 90
	self.nearAt = hl and hl.NearFillAt or 24

	return self
end

-- The fill a given distance wants. A Highlight's contour is a fixed ~2px in
-- SCREEN space, so it thins to a hairline on a distant object — far away the mark
-- has to be carried by MASS, and up close by PRECISION without washing out the
-- thing being looked at.
function WorldPrompt:fillFor(dist)
	local hl = self.hl
	if not hl then return 1 end
	if self.hovering then return hl.HoverFillTransparency or 0.72 end
	local near = hl.FillTransparency or 0.88
	local far = hl.FarFillTransparency
	if not far then return near end
	local t = math.clamp((dist - self.nearAt) / math.max(self.farAt - self.nearAt, 1), 0, 1)
	return near + (far - near) * t
end

function WorldPrompt:paint(dist)
	if not self.glow or not self.glow.Enabled then return end
	dist = dist or self.lastDist or self.nearAt
	TweenService:Create(self.glow, TweenInfo.new(0.14, Enum.EasingStyle.Quad),
		{ FillTransparency = self:fillFor(dist) }):Play()
end

-- POP, not blink. A billboard that snaps on at a fixed radius reads as a
-- rendering glitch; a plate that springs out reads as the object noticing you.
-- Back easing on the way in, plain Quad on the way out — the same asymmetry every
-- panel in this game opens and closes with.
function WorldPrompt:setShown(on, dist)
	if self.shown == on then
		if on then self.lastDist = dist end
		return
	end
	self.shown = on
	self.lastDist = dist

	if self.glow then
		self.glow.Enabled = on
		if on then self.glow.FillTransparency = self:fillFor(dist or self.nearAt) end
	end

	if self.popTween then self.popTween:Cancel() end
	if on then
		self.gui.Enabled = true
		self.scale.Scale = self.popFrom
		self.popTween = TweenService:Create(self.scale,
			TweenInfo.new(self.popIn, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 })
		self.popTween:Play()
	else
		self.hovering = false
		self.popTween = TweenService:Create(self.scale,
			TweenInfo.new(self.popOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = self.popFrom })
		self.popTween:Play()
		-- Disabled only once the pop has finished, and only if nothing re-showed
		-- it in the meantime — a fast walk past the edge of the radius would
		-- otherwise leave the plate hidden at full scale.
		local token = (self.hideToken or 0) + 1
		self.hideToken = token
		task.delay(self.popOut, function()
			if self.hideToken == token and not self.shown then
				self.gui.Enabled = false
			end
		end)
	end
end

-- Force it off and keep it off until the next poll tick puts it back — used by
-- anything that takes the screen over, like the splice cutscene.
function WorldPrompt:suppress()
	if self.glow then self.glow.Enabled = false end
	self.gui.Enabled = false
	self.shown = false
	self.hovering = false
	self.scale.Scale = 1
end

-- ONE throttled poll for the plate and the highlight together, so the two cannot
-- disagree about whether the player is there. Reads the character fresh each tick
-- so a respawn needs no re-wiring.
function WorldPrompt:watch(gate)
	task.spawn(function()
		while self.gui.Parent do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and not (gate and gate()) then
				local dist = (root.Position - self.centre).Magnitude
				self:setShown(dist <= self.showDistance, dist)
				if self.shown and self.glow then
					self.glow.FillTransparency = self:fillFor(dist)
				end
			else
				self:setShown(false)
			end
			task.wait(self.pollEvery or 0.2)
		end
	end)
end

return WorldPrompt
