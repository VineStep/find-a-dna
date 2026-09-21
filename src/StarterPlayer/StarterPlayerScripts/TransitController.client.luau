--[[
	TransitController — walk-up doorways. A plate on a piece of the world that
	moves you somewhere else when you click it.

	The honest counterpart to the Portals panel: that is a menu you open from
	anywhere, which is right for crossing the map, but the mouth of a tunnel
	should be a thing you walk to and press. GameConfig.Transit.Places is the
	whole list; today it holds one, the cave's Entry arch through to the mine.

	It shares WorldPrompt with the DNA machine, so a doorway looks and behaves
	exactly like the machine does — same plate, same pop, same hover and press,
	same sounds. Adding a second doorway is a row of config and nothing else.

	CLIENT-SIDE, like the Portals panel and for the same reason: Roblox gives a
	client network ownership of its own character, so PivotTo on it is a real
	teleport rather than a mock. Nothing is granted and nothing replicates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local WorldPrompt = require(ReplicatedStorage:WaitForChild("WorldPrompt"))

local TRANSIT = CONFIG.Transit
if not TRANSIT or not TRANSIT.Places or #TRANSIT.Places == 0 then
	-- No config, no doorways. Not a failure: this is the state the place was in
	-- before the first one existed.
	return
end

local P = CONFIG.Shop.Palette
local player = Players.LocalPlayer
local DROP = TRANSIT.DropHeight or 6

local built, missing = 0, {}

for _, place in ipairs(TRANSIT.Places) do
	-- WaitForChild with a timeout rather than an indefinite yield: a doorway whose
	-- part has been renamed or deleted should say so once and let the others
	-- build, not hang this script forever on the first bad row.
	local target = workspace:WaitForChild(place.Part, 20)
	if not target then
		table.insert(missing, tostring(place.Part))
	else
		local prompt = WorldPrompt.new({
			Name = place.Part,
			Target = target,
			Palette = P,
			ActionText = place.ActionText or "Enter",
			ObjectText = place.ObjectText or "",
			Height = place.Height or 3.4,
			Aspect = place.Aspect or 3.15,
			Rise = place.Rise or 0,
			ShowDistance = place.ShowDistance or 55,
			PopIn = place.PopIn,
			PopOut = place.PopOut,
			PopFrom = place.PopFrom,
			-- NO HIGHLIGHT. The machine gets one because it is a device among other
			-- devices and has to be picked out; a doorway is a hole in a wall you
			-- are already walking towards, and outlining the whole 32-stud neon
			-- block would light up a third of the cave.
			Highlight = nil,
			OnActivate = function()
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root then return end
				-- PivotTo the MODEL, not the root part, so accessories and tools
				-- come along instead of being left standing in the cave.
				local dest = place.Pos + Vector3.new(0, DROP, 0)
				char:PivotTo(CFrame.new(dest))
			end,
		})
		if prompt then
			built += 1
			prompt:watch()
		end
	end
end

if #missing > 0 then
	warn(("TransitController: no Workspace.%s — that doorway is not built.")
		:format(table.concat(missing, ", Workspace.")))
end

print(("TransitController: %d doorway%s wired."):format(built, built == 1 and "" or "s"))
