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

task.spawn(function()
	while true do
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
	elseif name == "Time" then
		-- Either a number or the literal "Live"; applyTime rejects anything else.
		if type(value) == "number" or value == "Live" then
			applyTime(value)
		end
	end
	-- Anything else is ignored in silence. A client naming a command that does not
	-- exist is either a stale build or someone probing; neither deserves an answer.
end)

-------------------------------------------------------------------- lifecycle
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local speed = player:GetAttribute("AdminWalkSpeed")
		if not speed then return end
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			hum.WalkSpeed = speed
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Keyed by the Player instance, so without this the table holds a reference to
	-- every player who has ever joined for the life of the server.
	lastAnnounce[player] = nil
end)
