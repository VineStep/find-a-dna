--[[
	MusicController — zone background music.

	One looping Sound per track in GameConfig.Music.Tracks, all of them alive from
	the start and all but one at zero volume. Changing zone crossfades; it never
	stops and restarts a track, because a track that restarts from 0:00 every time
	you step out of a cave and back in is the thing that makes a player notice the
	system instead of the place.

	Client-side on purpose. There is no server in this place, and there would be no
	reason to involve one if there were: what a player hears is local.

	THE SOUNDS LIVE INSIDE THEIR OWN SoundGroup, not in SoundService. That is not
	tidiness — SettingsController walks SoundService's children and adopts every
	Sound it finds into the UISfx group so the SFX slider governs it, and it
	connects ChildAdded to keep doing that. Parented to SoundService these three
	would be swallowed by the sound-effects slider within a frame of being created.
	(That adopt is now also guarded to leave any sound that already has a group,
	which is the general fix; this parenting is the local one, and both are cheap.)

	There is no music slider yet. The group is the seam: one Settings row keyed to
	SoundService.Music.Volume is all it takes, and every switch on that panel has
	to do something, which this would.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MUSIC = require(ReplicatedStorage:WaitForChild("GameConfig")).Music

local player = Players.LocalPlayer

if not MUSIC or not MUSIC.Tracks then return end

---------------------------------------------------------------------- group
local group = SoundService:FindFirstChild("Music")
if not group then
	group = Instance.new("SoundGroup")
	group.Name = "Music"
	group.Volume = 1
	group.Parent = SoundService
end

---------------------------------------------------------------------- tracks
local tracks = {}
for name, id in pairs(MUSIC.Tracks) do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	-- Silent, not stopped. Every track plays for the whole session and the fade
	-- moves volume only, so returning to a zone rejoins its track where it got to.
	s.Volume = 0
	s.SoundGroup = group
	s.Parent = group
	s:Play()
	tracks[name] = s
end

local fades = {}

local function fadeTo(sound, volume)
	if fades[sound] then
		fades[sound]:Cancel()
	end
	local t = TweenService:Create(
		sound,
		TweenInfo.new(MUSIC.Fade or 2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = volume }
	)
	fades[sound] = t
	t:Play()
end

----------------------------------------------------------------------- zones
-- Half-extents once, rather than dividing by two on every test.
local zones = {}
for _, z in ipairs(MUSIC.Zones or {}) do
	if tracks[z.Track] then
		table.insert(zones, { track = z.Track, centre = z.Centre, half = z.Size / 2 })
	else
		warn(("MusicController: zone names track %q, which has no entry in Tracks"):format(tostring(z.Track)))
	end
end

-- FIRST match wins, so a box inside another box has to come first in the config.
-- That is the whole ordering rule and it is why the mineshaft is listed above the
-- cave that contains it.
local function trackFor(pos)
	for _, z in ipairs(zones) do
		local d = pos - z.centre
		if math.abs(d.X) <= z.half.X
			and math.abs(d.Y) <= z.half.Y
			and math.abs(d.Z) <= z.half.Z
		then
			return z.track
		end
	end
	return MUSIC.Default
end

----------------------------------------------------------------------- drive
local current = nil

local function switchTo(name)
	if name == current or not tracks[name] then return end
	if current then
		fadeTo(tracks[current], 0)
	end
	fadeTo(tracks[name], MUSIC.Volume or 0.35)
	current = name
end

-- Exposed so the zone can be forced — the admin panel's Music row auditions a
-- track with it, and it is what a boss stinger or a cutscene would use.
--
-- A FORCED ZONE HOLDS. It did not, at first: Invoke set the track and the
-- position poll below put it straight back on its next tick 0.4s later, so the
-- admin row pressed Cave and heard Overworld. A control that does nothing
-- perceptible is worse than no control. While forced is set the poll stands
-- down; Invoke("Auto") — or nil — clears it and hands the poll back.
local forced = nil

local api = Instance.new("BindableFunction")
api.Name = "SetMusicZone"
api.OnInvoke = function(name)
	if name == nil or name == "Auto" then
		forced = nil
		-- Apply the real zone NOW rather than waiting up to Poll seconds for it.
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			switchTo(trackFor(root.Position))
		end
		return "Auto"
	end
	if not tracks[name] then
		return current
	end
	forced = name
	switchTo(name)
	return current
end
api.Parent = SoundService

-- The default starts immediately rather than waiting for the first poll: the
-- character does not exist for the first second or so of a join, and silence at
-- the moment the world appears reads as broken audio.
switchTo(MUSIC.Default)

task.spawn(function()
	while true do
		-- Stands down while a zone is forced. Without this the poll is in a fight
		-- with whoever called SetMusicZone and wins it every time.
		if not forced then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				switchTo(trackFor(root.Position))
			end
		end
		task.wait(MUSIC.Poll or 0.4)
	end
end)
