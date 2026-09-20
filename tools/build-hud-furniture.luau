--[[
	build-hud-furniture — a ONE-OFF, run in Studio's EDIT datamodel.

	Creates the StarterGui instances that HUDController and AdminController used to
	build from scratch at runtime: HUD.Counters (the coin and gem readouts) and
	HUD.AdminPanel (the admin shell, including its crown title icon).

	WHY THEY HAVE TO BE REAL INSTANCES: Studio's Edit viewport does not run
	LocalScripts, so anything a controller creates in Play is invisible while you
	are authoring the place. Putting the shape in StarterGui is the only way to see
	and nudge these in the normal Studio view.

	Both controllers ADOPT what they find here (find-or-create) and still compute
	every size and position themselves, so the values set below only have to be
	plausible enough to look right in Edit — they are overwritten in Play.

	This is not part of the game and nothing requires it. It lives in the repo
	because the .rbxl is gitignored, so without it the StarterGui additions are
	not reproducible from a fresh clone. Re-running it is safe: every instance is
	found-or-created, never duplicated.

	Run with: execute_luau, datamodel_type = "Edit".
]]

local CONFIG = require(game:GetService("ReplicatedStorage"):WaitForChild("GameConfig"))
local P = CONFIG.Shop.Palette
local CUR = CONFIG.Currency
local ADMIN = CONFIG.Admin

local hud = game:GetService("StarterGui"):WaitForChild("HUD")

local log = {}

local function ensure(parent, name, class)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(class) then return found, false end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = parent
	table.insert(log, ("created %s (%s)"):format(made:GetFullName(), class))
	return made, true
end

------------------------------------------------------------------- counters
-- Under the 2x3 tile grid on the left. Scale-based here so it lands somewhere
-- sensible at any Edit viewport size; HUDController.counterFit replaces both
-- Position and Size in pixels the moment it runs.
--
-- 0.63, walked down twice. fitScale does not run in Edit, so ButtonBar keeps the
-- 166x255 pixel size it carries in the tree and its bottom edge sits lower than
-- the figure the runtime layout produces: 0.455 put the counters across the middle
-- row of tiles, and 0.58 still clipped the bottom row, because the tile ARTWORK
-- overhangs its slot. This clears it. Only the Edit view depends on the number —
-- counterFit replaces it with a pixel offset measured off the bar the moment it
-- runs in Play.
local counters = ensure(hud, "Counters", "Frame")
counters.BackgroundTransparency = 1
counters.AnchorPoint = Vector2.new(0, 0)
counters.Position = UDim2.fromScale(0.025, 0.63)
counters.Size = UDim2.fromScale(0.08, 0.09)
counters.ZIndex = 6

local clist = ensure(counters, "UIListLayout", "UIListLayout")
clist.FillDirection = Enum.FillDirection.Vertical
clist.SortOrder = Enum.SortOrder.LayoutOrder
clist.Padding = UDim.new(0, 6)

local function counterRow(kind, image, order, sample)
	local row = ensure(counters, kind .. "Counter", "Frame")
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0.46, 0)
	row.ZIndex = 6

	local icon = ensure(row, "Icon", "ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.Image = image or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 7
	local ar = ensure(icon, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.DominantAxis = Enum.DominantAxis.Height

	local amount = ensure(row, "Amount", "TextLabel")
	amount.BackgroundTransparency = 1
	amount.AnchorPoint = Vector2.new(0, 0.5)
	-- COUNTER_TEXT_X is 1.12 of the row's HEIGHT, and the runtime sets it in
	-- pixels. A UDim2 X scale is a fraction of the parent's WIDTH, so 1.12 here
	-- put the number 131px from a 34px icon — the gap that made this look broken
	-- in Edit. Converted: 1.12 * H / W for the static shape above (a row 0.08 of
	-- viewport width by 0.0414 of its height), which at 16:9 is about a third.
	-- Approximate by construction, and replaced the moment counterFit runs.
	amount.Position = UDim2.new(0.33, 0, 0.5, 0)
	amount.Size = UDim2.fromScale(1.6, 0.78)
	amount.Text = sample
	amount.TextColor3 = Color3.new(1, 1, 1)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	amount.TextScaled = true
	amount.ZIndex = 7
	local ink = ensure(amount, "UIStroke", "UIStroke")
	ink.Color = P.Ink
	ink.Thickness = 2.8
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ink.LineJoinMode = Enum.LineJoinMode.Round
	return row
end

counterRow("Coins", CUR and CUR.CoinIcon, 1, "12K")
counterRow("Gems", CUR and CUR.GemIcon, 2, "86")

---------------------------------------------------------------- admin button
-- The crown key in the top-right. VISIBLE here, unlike the panel: it is 54px in
-- a corner rather than 62% of the screen, so it shows in the Edit viewport
-- without getting in the way of anything.
--
-- Position is a scale approximation for Edit only. At runtime sizeButton replaces
-- it with a PIXEL offset measured off GuiService:GetGuiInset(), because the HUD
-- sets IgnoreGuiInset and its local space starts above the visible screen — a
-- scale cannot express "below the topbar".
local abtn = ensure(hud, "AdminButton", "ImageButton")
abtn.AutoButtonColor = false
abtn.AnchorPoint = Vector2.new(1, 0.5)
abtn.Position = UDim2.fromScale(0.975, 0.105)
abtn.Size = UDim2.fromScale(0.042, 0.075)
-- BARE ARTWORK, no plate — the same treatment every tile in the HUD grid gets.
abtn.BackgroundTransparency = 1
abtn.BorderSizePixel = 0
abtn.Image = ""
abtn.Visible = true
abtn.ZIndex = 130

-- An earlier build of this key had a violet plate. Its corner and border stroke
-- have to GO, not just be left unset: a UIStroke strokes the button's border, so
-- on a transparent button it draws a rounded rectangle around nothing.
for _, c in ipairs(abtn:GetChildren()) do
	if c:IsA("UIStroke") or c:IsA("UICorner") or c:IsA("UIGradient") then
		table.insert(log, "removed " .. c:GetFullName())
		c:Destroy()
	end
end

local abar = ensure(abtn, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
abar.AspectRatio = 1
abar.DominantAxis = Enum.DominantAxis.Height

-- A CHILD label rather than the button's own Image, so the artwork can be sized
-- and nudged without touching the hit area, which has to stay a full square for
-- the tap floor.
local abicon = ensure(abtn, "Crown", "ImageLabel")
abicon.BackgroundTransparency = 1
abicon.AnchorPoint = Vector2.new(0.5, 0.5)
abicon.Position = UDim2.fromScale(0.5, 0.5)
abicon.Size = UDim2.fromScale(1, 1)
abicon.Image = ADMIN and ADMIN.TitleIcon or ""
abicon.ScaleType = Enum.ScaleType.Fit
abicon.ZIndex = 131

----------------------------------------------------------------- admin panel
-- SHUT in the tree. It was Visible = true so the crown showed in the Edit
-- viewport, and that is exactly the problem: a panel 62% of the screen wide sits
-- over everything you are trying to author. A Frame hides its children, so the
-- crown goes with it — tick Visible in the Explorer when you want to work on the
-- panel itself, and untick it after. The instances are all there to select and
-- nudge either way, which is the part that needed them to be real.
--
-- AdminController sets Visible = false as it adopts it regardless, so this is
-- belt and braces at join, and it destroys the whole panel on a non-admin client.
local panel = ensure(hud, "AdminPanel", "Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.62, 0.62)
panel.BackgroundColor3 = P.Panel
panel.BorderSizePixel = 0
panel.ClipsDescendants = false
panel.Visible = false
panel.ZIndex = 50

ensure(panel, "Scale", "UIScale")
local par = ensure(panel, "UIAspectRatioConstraint", "UIAspectRatioConstraint")
par.AspectRatio = 1.5
local pcorner = ensure(panel, "UICorner", "UICorner")
pcorner.CornerRadius = UDim.new(0.045, 0)
local pring = ensure(panel, "UIStroke", "UIStroke")
pring.Color = Color3.new(1, 1, 1)
pring.Thickness = 4

local shadow = ensure(panel, "Shadow", "Frame")
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.508)
shadow.Size = UDim2.fromScale(1, 1)
shadow.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.80)
shadow.BorderSizePixel = 0
shadow.ZIndex = 49
local scorner = ensure(shadow, "UICorner", "UICorner")
scorner.CornerRadius = UDim.new(0.045, 0)

local title = ensure(panel, "Title", "TextLabel")
title.BackgroundTransparency = 1
title.Text = ADMIN and ADMIN.Title or "Admin!"
title.TextColor3 = Color3.new(1, 1, 1)
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.fromScale(0.075, 0)
title.Size = UDim2.fromScale(0.58, 0.075 * 1.5)
title.TextXAlignment = Enum.TextXAlignment.Left
title.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
title.TextScaled = true
title.ZIndex = 61
local tstroke = ensure(title, "UIStroke", "UIStroke")
tstroke.Color = P.Ink
tstroke.Thickness = 3
tstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
tstroke.LineJoinMode = Enum.LineJoinMode.Round

-- THE CROWN, on the panel's top-left corner, half outside on both axes. This is
-- the thing that has to be visible in the Edit viewport.
local icon = ensure(panel, "TitleIcon", "ImageLabel")
icon.BackgroundTransparency = 1
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.018, 0)
icon.Size = UDim2.fromScale(0.11, 0.11 * 1.5)
icon.Rotation = -8
icon.Image = ADMIN and ADMIN.TitleIcon or ""
icon.ScaleType = Enum.ScaleType.Fit
icon.ZIndex = 62

local close = ensure(panel, "CloseButton", "TextButton")
close.AutoButtonColor = false
close.Text = ""
close.BorderSizePixel = 0
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.fromScale(0.978, 0.012)
close.Size = UDim2.fromScale(0.063, 0.063 * 1.5)
close.BackgroundColor3 = P.Close
close.ZIndex = 62
ensure(close, "Scale", "UIScale")
local ccorner = ensure(close, "UICorner", "UICorner")
ccorner.CornerRadius = UDim.new(0.3, 0)
-- chrome RE-COLOURS these two rather than creating them; without them it dies
-- part-built on s.Color and then g.Rotation.
local cstroke = ensure(close, "UIStroke", "UIStroke")
cstroke.Color = Color3.new(1, 1, 1)
cstroke.Thickness = 3.4
ensure(close, "UIGradient", "UIGradient")
local cpad = ensure(close, "UIPadding", "UIPadding")
cpad.PaddingTop = UDim.new(0.2, 0)
cpad.PaddingBottom = UDim.new(0.2, 0)
cpad.PaddingLeft = UDim.new(0.2, 0)
cpad.PaddingRight = UDim.new(0.2, 0)

local rows = ensure(panel, "Rows", "Frame")
rows.BackgroundTransparency = 1
rows.Position = UDim2.fromScale(0.05, 0.17)
rows.Size = UDim2.fromScale(0.9, 0.77)
rows.ZIndex = 53
local rlist = ensure(rows, "UIListLayout", "UIListLayout")
rlist.FillDirection = Enum.FillDirection.Vertical
rlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
rlist.SortOrder = Enum.SortOrder.LayoutOrder

if #log == 0 then
	table.insert(log, "nothing to create — every instance was already present")
end
return table.concat(log, "\n")
