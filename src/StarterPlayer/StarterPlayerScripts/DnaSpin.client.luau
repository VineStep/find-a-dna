-- Spins the DNA helix in the extractor tank.
--
-- Stands in for the Moon Animator export on Dna.dna.AnimationController: asset
-- 122704088813644 was published as an empty KeyframeSequence (0 keyframes), and the
-- Moon save in ServerStorage kept no frame data either, so the original motion is gone.
-- All that survived was "looped, 300 frames" -- 5s at Moon's 60fps -- hence PERIOD.
--
-- Client-side on purpose: it is decoration, so there is no reason to replicate a CFrame
-- every frame from the server.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PERIOD = 5 -- seconds per revolution at rest; the one knob worth turning

local machine = workspace:WaitForChild("Dna machine")
local dna = machine:WaitForChild("Dna"):WaitForChild("dna")
local base = dna.CFrame -- the helix stands on its local Y, which is world up here

-- THE SPEED IS AN ATTRIBUTE, read every frame off the machine. FuseController
-- ramps it up during a splice so the tank visibly spins up, and drops it back
-- afterwards -- a number it sets rather than a second copy of this loop.
local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local SPIN_ATTR = (CONFIG.Fuse and CONFIG.Fuse.Cutscene and CONFIG.Fuse.Cutscene.SpinAttribute)
	or "SpinBoost"

-- ACCUMULATED, not derived from os.clock(). The old line was
-- `base * CFrame.Angles(0, os.clock() * k, 0)`, which is correct only while k
-- never changes: multiply the WHOLE elapsed clock by a new speed and the helix
-- jumps to a different angle on the frame the multiplier moves. Integrating the
-- speed instead means a change in rate is a change in rate and nothing else.
local angle = 0
local RATE = 2 * math.pi / PERIOD

RunService.RenderStepped:Connect(function(dt)
	local boost = machine:GetAttribute(SPIN_ATTR)
	angle += dt * RATE * (type(boost) == "number" and boost or 1)
	dna.CFrame = base * CFrame.Angles(0, angle, 0)
end)
