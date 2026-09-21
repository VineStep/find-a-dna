--[[
	AdminService — the first server script in this place.

	Everything here exists because a client cannot do it:

	  * A client cannot send anything to another client. Global messages have to
	    come through here to reach anybody else.
	  * A client's opinion of whether it is an admin is worth nothing. The check
	    lives here, and it is re-run on EVERY request rather than once at join —
	    the client is told yes or no only so it knows whether to build the panel.
	  * Walk speed and time of day are applied here so they are real: a client that
	    sets its own WalkSpeed has only persuaded itself.

	FLY IS THE EXCEPTION and is honest about it. Roblox gives the client network
	ownership of its own character, so client-side flight is something any exploiter
	can do in any experience regardless of this script. Gating it here would buy
	nothing. What is gated is the PANEL and everything that reaches other players.

	The remotes are created by this script rather than kept in the tree, so there is
	one place that defines the contract and no chance of a stale RemoteEvent sitting
	in ReplicatedStorage with nothing behind it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ADMIN = CONFIG.Admin

--------------------------------------------------------------------- remotes
local folder = Instance.new("Folder")
folder.Name = "AdminRemotes"
folder.Parent = ReplicatedStorage

local whoAmI = Instance.new("RemoteFunction")
whoAmI.Name = "WhoAmI"
whoAmI.Parent = folder

local announce = Instance.new("RemoteEvent")
announce.Name = "Announce"
announce.Parent = folder

local command = Instance.new("RemoteEvent")
command.Name = "Command"
command.Parent = folder

------------------------------------------------------------------ the check
local function isAdmin(player)
	if not player or not player.Parent then return false end
	for _, id in ipairs(ADMIN.UserIds or {}) do
		if player.UserId == id then return true end
	end
	if ADMIN.GroupId and ADMIN.MinGroupRank then
		-- pcall: GetRankInGroup is a web call and throws when the group service is
		-- having a bad day. Throwing here would turn an outage into "nobody can do
		-- anything", and the explicit UserIds list above is the way back in.
		local ok, rank = pcall(function()
			return player:GetRankInGroup(ADMIN.GroupId)
		end)
		if ok and rank and rank >= ADMIN.MinGroupRank then return true end
	end
	return false
end

whoAmI.OnServerInvoke = function(player)
	return isAdmin(player)
end

------------------------------------------------------------------ validation
-- Everything below this line is a TRUST BOUNDARY. Every value arriving from a
-- client is the wrong type, the wrong length or missing until proven otherwise.

local MAX = ADMIN.MaxMessageLength or 140

local function cleanText(raw)
	if type(raw) ~= "string" then return nil end
	-- Control characters out, newlines included: the message is drawn as ONE line
	-- and a newline would let one announcement push every other player's screen
	-- around. %c covers tab, CR, LF and the rest.
	local text = raw:gsub("%c", " ")
	-- Collapse runs of spaces, then trim. A wall of spaces is how you make a
	-- 140-character message that renders as an empty banner nobody can dismiss.
	text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
	if text == "" then return nil end
	if #text > MAX then
		text = text:sub(1, MAX)
	end
	return text
end

-- Per-player, not global: one admin spamming must not lock the others out.
local lastAnnounce = {}

announce.OnServerEvent:Connect(function(player, raw)
	if not isAdmin(player) then return end

	local text = cleanText(raw)
	if not text then return end

	local now = os.clock()
	local cooldown = ADMIN.AnnounceCooldown or 2
	if lastAnnounce[player] and now - lastAnnounce[player] < cooldown then return end
	lastAnnounce[player] = now

	-- The NAME comes from the Player object, never from the payload. A client that
	-- supplies its own name can announce as anybody, which is the whole reason the
	-- client sends nothing but the text.
	announce:FireAllClients({
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		Text = text,
	})
end)

------------------------------------------------------------------- commands
local function applySpeed(player, value)
	if type(value) ~= "number" or value ~= value then return end
	local speeds = ADMIN.Speeds or { 16 }
	local lo, hi = speeds[1], speeds[1]
	for _, v in ipairs(speeds) do
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	-- Clamped to the configured range rather than trusted: the panel only offers
	-- the listed steps, and a client is not the panel.
	local speed = math.clamp(value, lo, hi)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = speed
	end
	-- So a respawn does not silently undo it.
	player:SetAttribute("AdminWalkSpeed", speed)
end

------------------------------------------------------------------ god mode
-- NOT MaxHealth = inf, which is the obvious version and breaks every health bar
-- in the game including Roblox's own. A flag plus a HealthChanged connection
-- restores the bar to full instead, so the character is unkillable and still
-- reads as a normal 100hp humanoid.
--
-- Server-side because it has to be: damage is applied wherever the damager runs,
-- and a client that refuses to lower its own health has only lied to itself.
local godOn = {}
local godConns = {}

local function bindGod(player, char)
	if godConns[player] then
		godConns[player]:Disconnect()
		godConns[player] = nil
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	godConns[player] = hum.HealthChanged:Connect(function(health)
		if godOn[player] and health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)
	if godOn[player] then
		hum.Health = hum.MaxHealth
	end
end

local function applyGod(player, value)
	godOn[player] = value and true or false
	local char = player.Character
	bindGod(player, char)
	-- Published so the panel's pill can be repainted from the truth rather than
	-- from what the client last asked for.
	player:SetAttribute("AdminGod", godOn[player])
end

------------------------------------------------------------------- jump
local function applyJump(player, value)
	if type(value) ~= "number" or value ~= value then return end
	local jumps = ADMIN.Jumps or { 50 }
	local lo, hi = jumps[1], jumps[1]
	for _, v in ipairs(jumps) do
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	local power = math.clamp(value, lo, hi)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		-- A Humanoid obeys JumpPower or JumpHeight depending on this flag, and
		-- newer places default it to false — setting JumpPower alone does nothing
		-- at all there, which is a silent no-op rather than an error.
		hum.UseJumpPower = true
		hum.JumpPower = power
	end
	player:SetAttribute("AdminJumpPower", power)
end

----------------------------------------------------------------- gravity
-- GLOBAL, and the only control here that changes physics for everybody at once.
-- Clamped well away from negatives: a negative gravity throws every player in the
-- server at the skybox with no way back short of a rejoin.
local function applyGravity(value)
	if type(value) ~= "number" or value ~= value then return end
	workspace.Gravity = math.clamp(value, 0, 500)
end

-- GLOBAL TIME. The sky follows real-world UTC, set on the server, so it is the
-- same hour for every player in the server and the same hour as the world outside
-- it. This is the default state; an admin pressing Dawn/Noon/Night PINS it, and
-- pressing Live hands it back.
--
-- UTC, not the server machine's local zone: Roblox servers run wherever Roblox
-- puts them, so os.date("*t") would give a different sky per datacentre — which
-- is the one thing "global time" must not do.
local liveTime = true

local function realClockTime()
	local t = os.date("!*t")
	return t.hour + t.min / 60
end

local function applyTime(value)
	if value == "Live" then
		liveTime = true
		Lighting.ClockTime = realClockTime()
		return
	end
	if type(value) ~= "number" or value ~= value then return end
	-- Pinned until someone asks for Live again.
	liveTime = false
	Lighting.ClockTime = math.clamp(value, 0, 24)
end

--------------------------------------------------------------- blood moon
-- GLOBAL, like gravity and time: it is a change to the SKY, and a sky that is
-- red for one player and blue for the next is not a sky.
--
-- It PINS the clock while it is on, because a blood moon at two in the afternoon
-- is just a red filter. Switching it off restores every property it touched and
-- hands the clock back to whatever the Time row had — Live unless an admin pinned
-- an hour.
--
-- THE ORIGINAL VALUES ARE CAPTURED, not hardcoded as a "normal" preset: the
-- place's lighting is somebody's art and this has no business deciding what it
-- should be. Captured on first use rather than at startup so a later re-tint is
-- picked up, and only once, or turning it on twice would capture the red.
local BLOOD = ADMIN.BloodMoon or {}
local bloodOn = false
local bloodWas = nil
local bloodWasAtmos = nil
local bloodWasLive = true

-- The Atmosphere is a CHILD of Lighting, not a property of it, so it is captured
-- and restored separately — and only if the place actually has one, because it
-- is art somebody added and could be removed again.
local function atmosphere()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function captureAtmosphere()
	local a = atmosphere()
	if not a then return nil end
	return { Density = a.Density, Color = a.Color, Decay = a.Decay,
	         Haze = a.Haze, Glare = a.Glare }
end

local function applyAtmosphere(values)
	local a = atmosphere()
	if not a or not values then return end
	for k, v in pairs(values) do
		a[k] = v
	end
end

local function captureLighting()
	return {
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		ColorShift_Top = Lighting.ColorShift_Top,
		ColorShift_Bottom = Lighting.ColorShift_Bottom,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
end

local function applyBloodMoon(on)
	on = on == true
	if on == bloodOn then return end
	bloodOn = on

	if on then
		bloodWas = captureLighting()
		bloodWasAtmos = captureAtmosphere()
		-- Remembered separately: the clock is pinned for the duration, and the Time
		-- row's own state has to survive that.
		bloodWasLive = liveTime
		liveTime = false

		Lighting.ClockTime = BLOOD.ClockTime or 0
		Lighting.Ambient = BLOOD.Ambient or Color3.fromRGB(58, 12, 16)
		Lighting.OutdoorAmbient = BLOOD.OutdoorAmbient or Color3.fromRGB(74, 14, 18)
		Lighting.Brightness = BLOOD.Brightness or 1.4
		Lighting.ColorShift_Top = BLOOD.ColorShiftTop or Color3.fromRGB(120, 24, 24)
		Lighting.ColorShift_Bottom = BLOOD.ColorShiftBottom or Color3.fromRGB(40, 8, 10)
		Lighting.FogColor = BLOOD.FogColor or Color3.fromRGB(46, 8, 12)
		Lighting.FogEnd = BLOOD.FogEnd or 620
		Lighting.FogStart = BLOOD.FogStart or 40
		Lighting.ExposureCompensation = BLOOD.ExposureCompensation or -0.25
		applyAtmosphere(BLOOD.Atmosphere)
	elseif bloodWas then
		for k, v in pairs(bloodWas) do
			Lighting[k] = v
		end
		applyAtmosphere(bloodWasAtmos)
		liveTime = bloodWasLive
		if liveTime then
			Lighting.ClockTime = realClockTime()
		end
	end

	-- Published so a client can read the true state rather than what it last
	-- asked for — the same rule the God pill follows.
	workspace:SetAttribute("AdminBloodMoon", bloodOn)
end

workspace:SetAttribute("AdminBloodMoon", false)

task.spawn(function()
	while true do
		-- liveTime is false for the whole of a blood moon, so this leaves the
		-- pinned midnight alone without needing to know about it.
		if liveTime then
			Lighting.ClockTime = realClockTime()
		end
		task.wait(ADMIN.TimeSync or 30)
	end
end)

command.OnServerEvent:Connect(function(player, name, value)
	if not isAdmin(player) then return end
	if type(name) ~= "string" then return end

	if name == "Speed" then
		applySpeed(player, value)
	elseif name == "God" then
		applyGod(player, value == true)
	elseif name == "Jump" then
		applyJump(player, value)
	elseif name == "Gravity" then
		applyGravity(value)
	elseif name == "Time" then
		-- Either a number or the literal "Live"; applyTime rejects anything else.
		if type(value) == "number" or value == "Live" then
			applyTime(value)
		end
	elseif name == "BloodMoon" then
		applyBloodMoon(value == true)
	end
	-- Anything else is ignored in silence. A client naming a command that does not
	-- exist is either a stale build or someone probing; neither deserves an answer.
end)

-------------------------------------------------------------------- lifecycle
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		-- Everything admin-applied is re-applied on respawn, or the panel's state
		-- silently stops being true the first time the character dies.
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if not hum then return end
		local speed = player:GetAttribute("AdminWalkSpeed")
		if speed then hum.WalkSpeed = speed end
		local jump = player:GetAttribute("AdminJumpPower")
		if jump then
			hum.UseJumpPower = true
			hum.JumpPower = jump
		end
		bindGod(player, char)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Keyed by the Player instance, so without this the tables hold a reference to
	-- every player who has ever joined for the life of the server.
	lastAnnounce[player] = nil
	godOn[player] = nil
	if godConns[player] then
		godConns[player]:Disconnect()
		godConns[player] = nil
	end
end)
