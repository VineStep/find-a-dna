--[[
	UIKit — the panel primitives every GUI in FIND A DNA is built from.

	Lifted out of StarterPlayerScripts.ShopController, which is the reference
	implementation and where every constant below was actually chosen and argued.
	The comments came with them on purpose: they are the reason ShopController is
	worth anything, and a UIKit of bare functions would lose the whole point.

	Two halves:

	  * Module-level and stateless — bevel / gloss / halftone / rays / castShadow /
	    sound / audible, plus the three constants that are not palette. Anything
	    can call these without owning any state.
	  * UIKit.chrome(panel, opts) -> kit. The per-panel half. One call does the
	    whole panel treatment — body gradient, studs tint, white ring, the pale
	    opaque lip on the existing Shadow frame, the 30-layer stacked shadow, the
	    overhanging title and rotated title icon, the close-button restyle — and
	    hands back an object carrying the two registries that HAVE to be per-panel:
	    the UIStrokes to rescale and the UITextSizeConstraints to resolve.

	ponytail: ShopController still carries its own verbatim copy of everything in
	here and is deliberately NOT migrated this pass — it works, and porting 1,334
	lines is real risk for no visible gain today. Upgrade path: delete its helper
	block (uiSound..castShadow) and its "panel" and "header chrome" sections,
	require this, and replace them with one UIKit.chrome(panel, {...}) call plus a
	kit: prefix on corner/stroke/outline/tag/capText — the constants are identical,
	so the diff is almost all deletions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Rays and Halftone are HOUSE textures that every panel wants, but they live
-- under GameConfig.Shop for historical reasons — the shop is where they were
-- found and vetted. Moving them to a top-level key would force an edit to
-- ShopController, which this pass deliberately does not touch. Read them from
-- where they are; relocate them when the shop is finally folded in here.
local SHOP = require(ReplicatedStorage:WaitForChild("GameConfig")).Shop

local UIKit = {}

-- The only three constants that are not palette: white, which is a ring and a
-- text fill rather than an item colour; black, which is shadow; and the font.
-- Everything with a hue comes from GameConfig.Shop.Palette or an item's own Grad.
UIKit.WHITE = Color3.new(1, 1, 1)
UIKit.BLACK = Color3.new(0, 0, 0)
UIKit.FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local WHITE, BLACK = UIKit.WHITE, UIKit.BLACK

------------------------------------------------------------------------ sound
-- Roblox's own first-party UI set, chosen because third-party audio has to have
-- the experience granted access to each asset before it will play in a
-- group-owned place, and these do not.
function UIKit.sound(id, volume)
	local s = Instance.new("Sound")
	s.Name = "UIKit_" .. id
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end

local SFX_HOVER = UIKit.sound(10066931761, 0.25) -- "Hover 01"
local SFX_CLICK = UIKit.sound(10128760939, 0.45) -- "Select 01"

-- GLOBAL, not per-button, and that is the whole point of it. Dragging the cursor
-- down a column of six buttons crosses all of them inside a couple of hundred
-- milliseconds and machine-guns the tick; a per-button floor never fires, because
-- each button is entered exactly once on the way past. HUDController measured it:
-- one sweep played the sample three times.
local HOVER_COOLDOWN = 0.12
local lastHover = 0

-- Sounds are created once per id and shared by every caller that asks for it: a
-- Sound per tile is eighteen instances playing one sample.
local hoverSounds = {}

-- Every interactive thing gets the same pair, so it is one call rather than two
-- Connects copied everywhere.
--
-- hoverId overrides the hover sample only. The inventory's pet tiles use it: a
-- pet is not a button and the UI tick makes picking up a creature sound like
-- pressing a menu key. The click stays shared — a press is a press.
--
-- The COOLDOWN stays global even with an override, which is the whole reason it
-- is not per-button: dragging across a grid of eighteen pets enters eighteen
-- tiles in a couple of hundred milliseconds, and a per-button floor never fires
-- because each is entered exactly once on the way past.
function UIKit.audible(button, hoverId)
	local hover = SFX_HOVER
	if hoverId then
		hover = hoverSounds[hoverId] or UIKit.sound(hoverId, 0.3)
		hoverSounds[hoverId] = hover
	end
	button.MouseEnter:Connect(function()
		local now = os.clock()
		if now - lastHover < HOVER_COOLDOWN then return end
		lastHover = now
		-- TimePosition reset first, or a rapid second trigger is swallowed by the
		-- sample already playing instead of restarting it.
		hover.TimePosition = 0
		hover:Play()
	end)
	button.MouseButton1Click:Connect(function()
		SFX_CLICK.TimePosition = 0
		SFX_CLICK:Play()
	end)
end

--------------------------------------------------------------------- rainbow
-- A UIGradient on a TextLabel tints the GLYPHS and leaves the UIStroke alone, so
-- the ink contour survives it and the text stays legible over a pale panel —
-- which is the whole reason a rainbow works on type here at all. Horizontal, so
-- the ramp spans the line rather than banding each letter top to bottom.
--
-- THE LABEL MUST BE WHITE UNDERNEATH. A gradient MULTIPLIES what is under it, so
-- on a coloured label every stop in the ramp comes out a shade of that colour.
--
-- It travels: a static ramp across one short line reads as a gradient, not as a
-- rainbow. Offset wraps at 1, so it steps back to -1 and runs again rather than
-- snapping.
--
-- ponytail: DailyController carries its own verbatim copy of this and is NOT
-- migrated, the same call the header makes about ShopController — it works, and
-- the diff is risk for no visible gain. Upgrade path: delete its RAINBOW,
-- statusRamp and the task.spawn under them and call this instead.
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  92, 112)),
	ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 176,  64)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 232,  74)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB( 96, 222, 106)),
	ColorSequenceKeypoint.new(0.68, Color3.fromRGB( 74, 196, 255)),
	ColorSequenceKeypoint.new(0.84, Color3.fromRGB(150, 130, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 122, 216)),
})

-- gate: optional GuiObject whose Visible gates the animation, so a rainbow on a
-- closed panel is not driving a 30Hz loop for a screen nobody is looking at.
function UIKit.rainbow(label, gate, speed)
	label.TextColor3 = WHITE
	local ramp = label:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	ramp.Color = RAINBOW
	ramp.Parent = label

	local hud = label:FindFirstAncestorWhichIsA("ScreenGui")
	task.spawn(function()
		while ramp.Parent do
			-- ReduceMotion is the settings toggle every animation here honours.
			if ramp.Enabled
				and (not gate or gate.Visible)
				and not (hud and hud:GetAttribute("ReduceMotion")) then
				ramp.Offset = Vector2.new((tick() * (speed or 0.35)) % 2 - 1, 0)
			end
			task.wait(1 / 30)
		end
	end)
	return ramp
end

----------------------------------------------------------------------- feel
-- Hover pop, press squash, release pop. The shop's cards and the inventory's pet
-- tiles both grew their own copy of this; anything built after them gets it from
-- here instead.
--
-- One UIScale, REUSED if the element already has one, because an element takes
-- only the first and a second is silently ignored — which looks exactly like a
-- button that does not respond.
--
-- SCALE ONLY, no rotation by default. The HUD tiles tilt -4 degrees on hover and
-- that reads well on a square piece of artwork; on a wide pill it looks like the
-- row came unglued. Pass Tilt to opt in.
local FEEL_POP = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FEEL_SQUASH = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FEEL_BACK = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function UIKit.feel(button, opts)
	opts = opts or {}
	local grow = opts.Grow or 1.08
	local press = opts.Press or 0.94
	local tilt = opts.Tilt or 0
	local rest = button.Rotation

	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button

	-- Tracked, because releasing the mouse INSIDE the button has to return to the
	-- hover size and releasing it after leaving has to return to 1 — without this
	-- a press-and-drag-off leaves the element stuck at 0.94.
	local hovered = false

	local function go(target, info)
		TweenService:Create(scale, info, { Scale = target }):Play()
	end

	button.MouseEnter:Connect(function()
		hovered = true
		go(grow, FEEL_POP)
		if tilt ~= 0 then
			TweenService:Create(button, FEEL_POP, { Rotation = rest + tilt }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		go(1, FEEL_POP)
		if tilt ~= 0 then
			TweenService:Create(button, FEEL_POP, { Rotation = rest }):Play()
		end
	end)
	button.MouseButton1Down:Connect(function()
		go(press, FEEL_SQUASH)
	end)
	button.MouseButton1Up:Connect(function()
		go(hovered and grow or 1, FEEL_BACK)
	end)
	return scale
end

--------------------------------------------------------------------- surfaces
-- A vertical light-to-dark gradient is the whole bevel trick: it reads as moulded
-- plastic without stacking a second frame behind every element.
--
-- Four stops rather than two. The two-stop version was a flat ramp between the
-- item's own pair; the extra stop at each end is what adds the shading — a lit
-- crown above the pale colour and a shaded lip below the saturated one — while
-- the middle 22%..80% still runs exactly the pair GameConfig declares, so nothing
-- changes hue.
function UIKit.bevel(obj, grad)
	local g = obj:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, grad[1]:Lerp(WHITE, 0.32)),
		ColorSequenceKeypoint.new(0.22, grad[1]),
		ColorSequenceKeypoint.new(0.80, grad[2]),
		ColorSequenceKeypoint.new(1.00, grad[2]:Lerp(BLACK, 0.20)),
	})
	g.Rotation = 90
	g.Parent = obj
	return g
end

-- The specular pass: a white sheet over the top of an element, fading out
-- downward. One frame with a transparency ramp rather than a second gradient on
-- the element itself, because an element only takes one UIGradient and bevel()
-- already has it. Purely decorative, and a Frame consumes no input, so the button
-- underneath still gets its own hover and click.
function UIKit.gloss(obj, frac, cornerScale, strength)
	frac = frac or 0.46
	local g = Instance.new("Frame")
	g.Name = "Gloss"
	g.BackgroundColor3 = WHITE
	g.BorderSizePixel = 0
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.fromScale(0.5, 0)
	g.Size = UDim2.fromScale(1, frac)
	g.ZIndex = obj.ZIndex

	-- UICorner is a fraction of the SHORTER side, so the sheet's own radius has to
	-- be the element's radius divided by the sheet's share of its height, or the
	-- white would square off the rounded top corners it is sitting in.
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new((cornerScale or 0.066) / frac, 0)
	c.Parent = g

	local ug = Instance.new("UIGradient")
	ug.Rotation = 90
	ug.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, strength or 0.62),
		NumberSequenceKeypoint.new(0.55, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	ug.Parent = g

	g.Parent = obj
	return g
end

-- The printed-dot pass, over the burst and under everything that carries meaning.
--
-- Note what this does NOT do: it takes no gradient and no tint. Every other layer
-- here is multiplied by the element's own ramp so it keeps its hue; this one is
-- white dots at low opacity, which lifts the surface identically on a pink card
-- and a cyan one. That is the point — one id, every colour, no per-element tuning.
--
-- 1:1 with ScaleType.Crop and its own UICorner, no wrapper. A UICorner DOES round
-- an ImageLabel's image; what it does not round is a clip region.
function UIKit.halftone(obj, cornerScale, strength)
	if not SHOP.Halftone then return nil end
	local im = Instance.new("ImageLabel")
	im.Name = "Halftone"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Size = UDim2.fromScale(1, 1)
	im.Image = SHOP.Halftone
	-- Judged at 1:1, not on a magnified copy. Blown up 2.5x the dots looked right
	-- at 0.82 and nearly vanished on a real 272px card — the pattern's scale
	-- shrinks with the element but the eye's threshold does not.
	im.ImageTransparency = strength or 0.76
	-- Crop, not Fit: Fit letterboxes a square source inside a wide element and
	-- leaves the dots floating in a band with bare gradient either side.
	im.ScaleType = Enum.ScaleType.Crop
	im.ZIndex = obj.ZIndex
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(cornerScale or 0.18, 0)
	c.Parent = im
	im.Parent = obj
	return im
end

-- The sunburst, radiating FROM a point you name rather than from the element's
-- centre. That aim is the whole point: centred, the rays fan out of blank gradient
-- and read as wallpaper; aimed at the product icon they read as the element
-- pointing at what it sells. Aiming means magnifying the burst and pushing its
-- centre to (cx, cy), which means it overflows, which means it has to be clipped.
--
-- Two things about that clipping wrapper, both learned the hard way:
--
--   ClipsDescendants clips to the RECTANGLE. A UICorner on the clipping frame
--   rounds that frame's own background but NOT what it clips (proved by giving the
--   wrapper an opaque fill: the fill came out rounded, the burst inside it still
--   reached the square corners). So the wrapper is INSET instead: a corner of
--   radius r has its arc passing r(1 - 1/sqrt2) = 0.293r from the corner along the
--   diagonal, so a rectangle inset by a little more than that on every side lies
--   entirely inside the rounded shape and has no square corner left to show.
--
--   Insetting costs the burst a few pixels around the perimeter, and with a
--   cream-GROUND source that was its own artifact: such an image darkens
--   everything it covers, so the ~5px it stopped short read as four washed-out
--   corners. GameConfig.Shop.Rays is white on a TRANSPARENT ground and only ADDS
--   light, so there is nothing for the gap to fail to darken. Put an opaque burst
--   back in GameConfig and the discoloured corners come back with it.
local RAYS_INSET = 0.34 -- of the corner radius; 0.293 is the exact minimum
-- How much LIGHTER the rays make the surface, not how strong an image reads: the
-- source is white and the element underneath supplies the hue.
local RAYS_ZOOM = 1.8
local RAYS_FADE = 0.25

function UIKit.rays(obj, cornerScale, cx, cy)
	if not SHOP.Rays then return nil end
	local clip = Instance.new("Frame")
	clip.Name = "Rays"
	clip.BackgroundTransparency = 1
	clip.AnchorPoint = Vector2.new(0.5, 0.5)
	clip.Position = UDim2.fromScale(0.5, 0.5)
	clip.ClipsDescendants = true
	clip.ZIndex = obj.ZIndex

	local im = Instance.new("ImageLabel")
	im.Name = "Burst"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(cx or 0.5, cy or 0.5)
	im.Image = SHOP.Rays
	im.ImageTransparency = RAYS_FADE
	im.ScaleType = Enum.ScaleType.Fit
	im.ZIndex = obj.ZIndex
	im.Size = UDim2.fromScale(RAYS_ZOOM, RAYS_ZOOM)
	im.Parent = clip

	-- Oversized and CROPPED by the wrapper, which is what lets it be aimed off
	-- centre. It does not spin: a rotated GuiObject is not clipped, so a turning
	-- burst escapes its element. Only the shop TILE's burst turns, in
	-- HUDController, where it sits alone in its own group.
	local function fit()
		local sz = obj.AbsoluteSize
		local d = RAYS_INSET * (cornerScale or 0.18) * math.min(sz.X, sz.Y)
		clip.Size = UDim2.new(1, -d * 2, 1, -d * 2)
	end
	obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	-- Parented FIRST, before the halftone, the gloss and every label, because ties
	-- on ZIndex are broken by child order and this has to sit under all of them.
	clip.Parent = obj
	return clip
end

-- A cast shadow: the element's own shape, behind it and offset down, with a
-- transparency ramp that starts invisible at the element's top and reaches full
-- strength below its bottom edge. Ramped rather than flat, because a flat
-- translucent rectangle poking out from behind something reads as a GAP in it
-- rather than as a shadow.
function UIKit.castShadow(obj, drop, cornerScale, z, strength)
	local s = Instance.new("Frame")
	s.Name = "Cast"
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromScale(0.5, 0.5 + drop)
	s.Size = UDim2.fromScale(1, 1)
	s.BackgroundColor3 = BLACK
	s.BackgroundTransparency = strength or 0.58
	s.BorderSizePixel = 0
	-- The HUD is ZIndexBehavior.Global, which is what lets a CHILD sit behind its
	-- own parent. Being a child is the point: it inherits the hover pop, so the
	-- shadow grows with the element instead of being left behind.
	s.ZIndex = z
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(cornerScale or 0.18, 0)
	c.Parent = s

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.62, 0.74),
		NumberSequenceKeypoint.new(1, 0),
	})
	g.Parent = s

	s.Parent = obj
	return s
end

------------------------------------------------------------------ panel chrome
-- UIStroke.Thickness is in PIXELS and follows neither UIScale nor a resize, so an
-- outline judged on a 550px-wide panel is a hairline on a phone and a slab on a
-- 4K monitor. Every stroke records the weight it was chosen at and is rescaled
-- from the panel's real width against this reference.
local STROKE_REF_WIDTH = 550

-- The panel's white ring, in pixels at STROKE_REF_WIDTH. The thin grey outline
-- OUTSIDE it is the Shadow frame's own stroke, sized off this, because only one
-- UIStroke per instance takes effect.
local RING = 5.5

-- The panel's shadow on the world. NOT one frame: a single translucent rounded
-- rect has a hard outer edge and reads as a grey slab taped underneath. Roblox has
-- no blur for GUI, so the falloff is built by stacking — each layer a little
-- larger and a little lower than the last, each almost transparent, compounding
-- into a dark core that thins smoothly outwards.
--
-- Thirty, not fourteen. Fourteen put the step between adjacent layers near 6% and
-- the rings were individually countable against a flat background, which is the
-- one thing a stacked shadow must not do: a visible ring reads as a BUG, where a
-- hard edge only reads as cheap. Thirty puts it near 3%, under the threshold.
local SHADOW_LAYERS = 30
-- DROP exceeds SPREAD, which is what makes this a drop shadow rather than a halo.
-- While spread dominated, every layer stuck out as far above the panel as below
-- and the result was a glow centred on it. With the drop larger, the outer layers'
-- top edges sit at or below the panel's own top edge and hide behind it: a tight
-- contact line above and a long throw below, one light source, overhead.
local SHADOW_SPREAD = 24 -- px at STROKE_REF_WIDTH, outermost layer
local SHADOW_DROP = 30   -- px at STROKE_REF_WIDTH, outermost layer
-- How dark the shadow gets where every layer overlaps.
local SHADOW_CORE = 0.55
-- N layers of transparency t leave t^N of the background showing, so solving that
-- for the core above gives each layer's share. DERIVED, not tuned: change the
-- count and the shadow keeps the same depth, only smoother. At 30 this is ~0.974.
local SHADOW_ALPHA = (1 - SHADOW_CORE) ^ (1 / SHADOW_LAYERS)

-- The close button wears the panel's own treatment at button scale: a thick WHITE
-- ring, and a thin ink line OUTSIDE it. That is two outlines and an instance only
-- ever renders one UIStroke, so the white one is the button's and the ink one is a
-- frame behind it — exactly the split the panel makes between its own stroke and
-- the Shadow frame's. The lip is nudged down, so more of it shows along the bottom
-- edge than the top and the key reads as moulded rather than outlined.
local CLOSE_SIZE = 0.063  -- of panel WIDTH; the button is square
local CLOSE_CORNER = 0.30 -- UICorner scale: a rounded square, not a circle
local CLOSE_RING = 3.4    -- white ring, px at STROKE_REF_WIDTH
local CLOSE_EDGE = 2.6    -- ink line outside the white ring, same units
local CLOSE_Y = 0.012     -- of panel height; centred just below the top edge

local Kit = {}
Kit.__index = Kit

function Kit:corner(obj, scale)
	local c = obj:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.18, 0)
	c.Parent = obj
	return c
end

-- Weak keys, so nothing in here pins a destroyed tile.
function Kit:stroke(obj, color, thickness)
	local base = thickness or 2
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = math.max(1, base * self.strokeK)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	self.strokes[s] = base
	return s
end

-- Contextual, NOT Border. Kit:stroke forces Border, which on a TextLabel with a
-- transparent background strokes the label's bounding BOX instead of the glyphs —
-- every product name sat inside a drawn-on plate for several iterations before
-- that was spotted. Contextual is what makes a UIStroke follow the letterforms.
-- One UIStroke per instance is all that takes effect, so anything that already has
-- a Kit:stroke border must not also call this.
function Kit:outline(label, thickness)
	local s = self:stroke(label, self.P.Ink, thickness or 2)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	-- FredokaOne is round; without this the stroke spikes at the letter joins.
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

-- Ribbons, count badges and the line under a price: TEXT, with nothing behind it.
-- As bordered plates they put two more button-shaped things on an element that is
-- itself a button — three things to press and only one of them live. Yellow with a
-- heavy ink outline is the reference's own treatment and needs no frame, no
-- gradient and no second instance for the stroke.
function Kit:tag(name, text, z)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = self.P.Tag
	t.FontFace = UIKit.FONT
	t.TextScaled = true
	t.ZIndex = z
	self:outline(t, 2.2)
	return t
end

-- TextScaled fills whatever box it is given, so a three-word blurb in a tall box
-- renders half again the size of a long one. Each cap records the fraction of the
-- layout UNIT it was chosen at and is resolved in Kit:relayout, where the real
-- pixel figure is finally known.
function Kit:capText(label, frac)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 100
	c.Parent = label
	self.textCaps[c] = frac
	return c
end

function Kit:onLayout(fn)
	table.insert(self.hooks, fn)
	return fn
end

-- unitPx is whatever the panel measures everything against — a card height in the
-- shop, a cell edge in the inventory. Hooks first, then every registered text cap.
function Kit:relayout(unitPx)
	self.unit = unitPx
	for _, f in ipairs(self.hooks) do
		f()
	end
	for c, frac in pairs(self.textCaps) do
		c.MaxTextSize = math.max(1, unitPx * frac)
	end
end

function Kit:rescale()
	local panel, shadow = self.panel, self.shadow
	-- Divide the UIScale back out. HUDController pops the panel from 0.8 to 1 on
	-- every open, and without this the outlines would thin and thicken through the
	-- animation and hold whatever weight the last frame landed on.
	local w = panel.AbsoluteSize.X / math.max(self.scale.Scale, 0.01)
	if w <= 0 then return end
	self.strokeK = w / STROKE_REF_WIDTH
	for s, base in pairs(self.strokes) do
		s.Thickness = math.max(1, base * self.strokeK)
	end

	-- The spec wants a thick white ring and then a thin cool-grey line OUTSIDE it.
	-- That is two instances, so the grey lives on the Shadow frame behind the
	-- panel, grown to exactly the white ring's reach. The same frame's downward
	-- offset is the moulded lip: it is what shows below the ring and nowhere else.
	local ring = RING * self.strokeK

	-- The shadow stack starts OUTSIDE the lip, or the innermost layers would darken
	-- the pale grey lip and the two would read as one muddy band. Everything here
	-- is in UNSCALED pixels, for the same reason the strokes are: UIScale must not
	-- change the shadow's softness while the panel pops open.
	local minSide = math.min(w, w / self.aspect)
	local baseR = self.cornerScale * minSide
	for i, f in ipairs(self.shadowLayers) do
		local t = i / SHADOW_LAYERS
		-- Superlinear, so the layers bunch up near the panel and spread out further
		-- away. That puts the dark part of the ramp against the edge where contact
		-- shadow belongs, instead of smearing it evenly across the whole spread.
		local spread = ring + SHADOW_SPREAD * self.strokeK * t ^ 1.35
		local drop = SHADOW_DROP * self.strokeK * t
		f.Size = UDim2.new(1, spread * 2, 1, spread * 2)
		f.Position = UDim2.new(0.5, 0, 0.5, drop)
		-- Concentric: a layer's radius has to grow with its own spread or the outer
		-- ones square off and the stack reads as a box behind a rounded panel.
		f.Corner.CornerRadius = UDim.new((baseR + spread) / (minSide + spread * 2), 0)
	end

	local lip = self.closeLip
	if lip then
		-- Far enough out to clear the white ring, which is drawn OUTSIDE the
		-- button's bounds, or the ink would sit under it and never show.
		local out = (CLOSE_RING + CLOSE_EDGE) * self.strokeK
		-- Sized in OFFSET, not scale. The button carries a symmetric 20% UIPadding,
		-- so a child sized 1,1 in scale fills the inset content box and would land
		-- INSIDE the button instead of behind it. Its real side is read back rather
		-- than computed from CLOSE_SIZE, because a UISizeConstraint can clamp it on
		-- a small viewport. Position is unaffected: the padding is symmetric.
		local side = lip.Parent.AbsoluteSize.X / math.max(self.scale.Scale, 0.01)
		lip.Size = UDim2.fromOffset(side + out * 2, side + out * 2)
		lip.Position = UDim2.new(0.5, 0, 0.5, CLOSE_EDGE * self.strokeK * 0.6)
		lip.Corner.CornerRadius =
			UDim.new((CLOSE_CORNER * side + out) / (side + out * 2), 0)
	end

	shadow.Size = UDim2.new(1, ring * 2, 1, ring * 2)
	-- Three quarters of the ring. The frame is OPAQUE (see chrome below), so what
	-- shows below the white ring is a solid moulded lip and its depth is a
	-- deliberate size rather than whatever a translucent version left uncovered.
	shadow.Position = UDim2.new(0.5, 0, 0.5, ring * 0.75)
end

-- The panel body itself: white at the top falling to a cool off-white at the
-- bottom. HUDController's studded sheet covers all but a hairline of the panel, so
-- the same ramp goes on both or the margin around the sheet reads as a seam.
local function shadeBody(obj)
	local g = obj:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, WHITE),
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(248, 248, 252)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(226, 228, 242)),
	})
	g.Parent = obj
end

-- opts: Aspect, Corner, Title, TitleIcon, Palette.
function UIKit.chrome(panel, opts)
	local P = opts.Palette
	local aspect = opts.Aspect or 1.75
	local cornerScale = opts.Corner or 0.045

	local self = setmetatable({
		panel = panel,
		P = P,
		aspect = aspect,
		cornerScale = cornerScale,
		strokeK = 1,
		unit = 0,
		-- Weak keys on both registries, so a destroyed tile's stroke and text cap
		-- go with it instead of being rescaled forever.
		strokes = setmetatable({}, { __mode = "k" }),
		textCaps = setmetatable({}, { __mode = "k" }),
		hooks = {},
		shadowLayers = {},
	}, Kit)

	local hud = panel:FindFirstAncestorWhichIsA("ScreenGui")
	self.hud = hud
	self.scale = panel:WaitForChild("Scale")
	self.shadow = panel:WaitForChild("Shadow")

	panel.BackgroundColor3 = P.Panel
	panel.UIAspectRatioConstraint.AspectRatio = aspect
	panel.UICorner.CornerRadius = UDim.new(cornerScale, 0)
	do
		-- The ring stays WHITE while every border inside the panel is ink. It is the
		-- panel's own edge against the 3D world, not one of the things drawn on it,
		-- and it is the most recognisable thing about the shape after the
		-- overhanging header.
		local s = panel:FindFirstChildOfClass("UIStroke")
		s.Color = WHITE
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		self.strokes[s] = RING
	end

	-- OPAQUE, and pale. It was ink at 0.78 transparency, which put a see-through
	-- sliver of the 3D world between the white ring and the grey outline along the
	-- bottom edge — read as a gap in the panel rather than as a shadow, because that
	-- is what it was. Solid pale grey in the same place reads as the moulded lip of
	-- a thick plastic panel instead, and there is nothing left to see through.
	--
	-- Both greys are MIXED from the palette rather than picked: a grey chosen by eye
	-- drifts against the panel the moment Panel or Ink is re-tuned.
	local shadow = self.shadow
	shadow.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.80)
	shadow.BackgroundTransparency = 0
	shadow.ZIndex = panel.ZIndex - 1
	shadow.UICorner.CornerRadius = UDim.new(cornerScale, 0)
	-- Thin. At RING + 1.6 it was a slab as wide as the white ring itself, which is
	-- what made the sliver between them read as a channel between two borders.
	self:stroke(shadow, P.Ink:Lerp(P.Panel, 0.46), 2.2)
	-- The lip is lit at its own top, which is the whole reason it reads as thickness
	-- and not as a second border drawn in a different colour.
	local lipGrad = Instance.new("UIGradient")
	lipGrad.Rotation = 90
	lipGrad.Color = ColorSequence.new(P.Ink:Lerp(P.Panel, 0.88), P.Ink:Lerp(P.Panel, 0.62))
	lipGrad.Parent = shadow

	for i = 1, SHADOW_LAYERS do
		local f = Instance.new("Frame")
		f.Name = "Cast" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = BLACK
		f.BackgroundTransparency = SHADOW_ALPHA
		f.BorderSizePixel = 0
		-- The HUD is ZIndexBehavior.Global, so a child below its parent's ZIndex
		-- draws behind it. Being a CHILD is the point: the stack inherits the panel's
		-- open pop and its shadow grows with it instead of being left behind.
		-- Largest layer furthest back, so the compounding runs the right way.
		--
		-- Counted DOWN from the lip rather than up from a fixed floor. The stack is
		-- as many ZIndex values deep as it has layers, so a fixed floor silently
		-- couples the layer count to the panel's own ZIndex — raising it from 6 to 14
		-- once ran the top of the range past the panel, its studs and its scroll, and
		-- the shadow drew over the panel's face and greyed the whole thing out.
		f.ZIndex = shadow.ZIndex - SHADOW_LAYERS - 1 + i
		local c = Instance.new("UICorner")
		c.Name = "Corner"
		c.Parent = f
		f.Parent = panel
		-- Outermost first, so index order matches the ramp rescale() walks.
		self.shadowLayers[SHADOW_LAYERS + 1 - i] = f
	end

	shadeBody(panel)
	task.spawn(function()
		-- Studs is HUDController's, built on its own schedule (first open is when
		-- AbsoluteSize is finally real); this only tints it.
		local studs = panel:WaitForChild("Studs", 20)
		if studs then shadeBody(studs) end
	end)

	-- Static shell children with no job left in this layout. Hidden, not destroyed:
	-- the panels are shared StarterGui furniture and something else may yet want them.
	local rule = panel:FindFirstChild("Rule")
	if rule then rule.Visible = false end
	local body = panel:FindFirstChild("Body")
	if body then body.Visible = false end

	----------------------------------------------------------- overhanging header
	-- The title, its icon and the close button all overhang the panel's top edge,
	-- roughly half above and half below. The panel's ClipsDescendants is false,
	-- which is what allows it.
	local title = panel:WaitForChild("Title")
	title.Text = opts.Title or ""
	title.TextColor3 = WHITE
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(0.075, 0)
	-- Font ends up ~7.5% of panel width: the box is 7.5% of width expressed in
	-- height units, and TextScaled takes the tighter of the two limits. A panel with
	-- a much shorter title than the shop's should override this.
	title.Size = UDim2.fromScale(0.58, 0.075 * aspect)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 61
	title.Visible = true
	do
		local s = title:FindFirstChildOfClass("UIStroke")
		s.Color = P.Ink
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		self.strokes[s] = 3
	end
	self.title = title

	if opts.TitleIcon then
		local icon = panel:FindFirstChild("TitleIcon") or Instance.new("ImageLabel")
		icon.Name = "TitleIcon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		-- On the top-LEFT corner itself, half outside on both axes.
		icon.Position = UDim2.fromScale(0.018, 0)
		icon.Size = UDim2.fromScale(0.11, 0.11 * aspect)
		icon.Rotation = -8
		icon.Image = opts.TitleIcon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 62
		icon.Parent = panel
		self.titleIcon = icon
	end

	------------------------------------------------------------------ close button
	-- HUDController finds this recursively and does button:WaitForChild("Scale"), so
	-- it keeps its name, its place under the panel and its UIScale child. Only the
	-- look and the position move.
	local close = panel:FindFirstChild("CloseButton", true)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromScale(0.978, CLOSE_Y)
	close.Size = UDim2.fromScale(CLOSE_SIZE, CLOSE_SIZE * aspect)
	close.BackgroundColor3 = P.Close
	close.TextColor3 = WHITE
	close.ZIndex = 62
	-- The glyph moves OUT of the button and into a child label. A UIGradient colours
	-- everything the object draws, its TEXT included, so the hard stop that gives the
	-- button its dark lower band was also painting a straight dark line across the X.
	-- A gradient does not reach into children, so a child label is drawn flat white.
	close.Text = ""
	do
		local glyph = close:FindFirstChild("Glyph") or Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.46)
		-- Over 1, deliberately. The button's 20% UIPadding is what centres this
		-- label, but it also means a label sized 1,1 gets a box only 60% of the
		-- button and TextScaled then draws an X too small to be the button's whole
		-- subject. Overflowing the content box costs nothing — the button does not
		-- clip — and AnchorPoint keeps it centred at any size.
		glyph.Size = UDim2.fromScale(1.34, 1.34)
		glyph.Text = "X"
		glyph.TextColor3 = WHITE
		glyph.FontFace = UIKit.FONT
		glyph.TextScaled = true
		glyph.ZIndex = 63
		glyph.Parent = close
		-- Thin. This is the lightest outline anywhere: every other one sits on type
		-- several times this size, where 2-3px reads as a contour, while on a glyph
		-- about 30px tall the same weight closed up the X's own gaps and left a dark
		-- blob with a white cross scratched into it.
		if not glyph:FindFirstChildOfClass("UIStroke") then
			self:outline(glyph, 1.3)
		end
	end
	UIKit.audible(close)
	do
		close.UICorner.CornerRadius = UDim.new(CLOSE_CORNER, 0)

		-- WHITE, not ink. Same argument as the panel's own ring: this is the button's
		-- edge against the world rather than one of the marks drawn on it, and the
		-- dark line it used to have made a red square with a thin border instead of
		-- a key.
		local s = close:FindFirstChildOfClass("UIStroke")
		s.Color = WHITE
		self.strokes[s] = CLOSE_RING
		-- Border, EXPLICITLY. The stroke comes out of StarterGui set to Contextual,
		-- and Contextual on a TextButton means the contour of its TEXT — which has
		-- been empty since the glyph moved into a child label, so the stroke drew
		-- nothing at all and the outline was silently absent.
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		-- The ink line outside the white ring, and the moulded lip under it. Sized by
		-- rescale(); a child, so it inherits the hover pop and rotation HUDController's
		-- attachFeel puts on the button. A ZIndex below its own parent's is legal here
		-- because the HUD is ZIndexBehavior.Global.
		local lip = close:FindFirstChild("Lip") or Instance.new("Frame")
		lip.Name = "Lip"
		lip.AnchorPoint = Vector2.new(0.5, 0.5)
		lip.BackgroundColor3 = P.Ink
		lip.BackgroundTransparency = 0
		lip.BorderSizePixel = 0
		lip.ZIndex = close.ZIndex - 1
		if not lip:FindFirstChild("Corner") then
			local c = Instance.new("UICorner")
			c.Name = "Corner"
			c.Parent = lip
		end
		lip.Parent = close
		self.closeLip = lip

		-- A darker red BAND across the bottom quarter, not a smooth gradient: the
		-- reference's close button reads as a moulded key with a lip, and a ramp reads
		-- as a lighting effect instead. Hard stops in one UIGradient, no extra frame.
		local g = close:FindFirstChildOfClass("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, P.Close),
			ColorSequenceKeypoint.new(0.74, P.Close),
			ColorSequenceKeypoint.new(0.75, P.CloseDeep),
			ColorSequenceKeypoint.new(1, P.CloseDeep),
		})
	end
	self.close = close
	self.closeY = CLOSE_Y

	-- Both signals: the panel's own is the direct one, and the ScreenGui's is the
	-- one that definitely moves when the viewport does.
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:rescale() end)
	if hud then
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:rescale() end)
	end
	self:rescale()

	return self
end

return UIKit
