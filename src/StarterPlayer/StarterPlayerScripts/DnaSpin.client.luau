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

local PERIOD = 5 -- seconds per revolution; the one knob worth turning

local dna = workspace:WaitForChild("Dna machine"):WaitForChild("Dna"):WaitForChild("dna")
local base = dna.CFrame -- the helix stands on its local Y, which is world up here

RunService.RenderStepped:Connect(function()
	dna.CFrame = base * CFrame.Angles(0, os.clock() * (2 * math.pi / PERIOD), 0)
end)
