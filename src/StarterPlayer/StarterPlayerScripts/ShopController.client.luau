--[[
	ShopController — fills StarterGui.HUD.ShopPanel.

	One long scrolling list, the Pet Simulator 99 shape: a feature banner, then a
	section header and a 3-wide grid of cards, then the next section header, and so
	on. There are no tabs. Order, copy, icons and every single colour come from
	ReplicatedStorage.GameConfig.Shop, so a new product — or a whole re-tint — is a
	config edit rather than a GUI edit.

	HUDController still owns the panel's open/close pop, the close button's feel and
	the studded plate. This owns everything drawn inside and the header chrome that
	overhangs the panel's top edge.

	Nothing here buys anything. There is no purchase remote and no product ids yet,
	so a card press fires nothing — see NOT_WIRED below. When the economy lands,
	that is the one function to fill in.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SHOP = require(ReplicatedStorage:WaitForChild("GameConfig")).Shop
local P = SHOP.Palette

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = hud:WaitForChild("ShopPanel")
local shadow = panel:WaitForChild("Shadow")

-- The only two constants that are not palette: white, which is a ring and a text
-- fill rather than a product colour, and the font. Everything with a hue comes
-- from P or from an item's own Grad.
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

-- Roblox's own first-party UI set. Third-party audio has to have the experience
-- granted access to each asset before it will play in a group-owned place; these
-- do not, which is the whole reason for picking them over anything prettier.
local function uiSound(id, volume)
	local s = Instance.new("Sound")
	s.Name = "ShopSfx" .. id
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end

local SFX_HOVER = uiSound(10066931761, 0.25)  -- "Hover 01"
local SFX_CLICK = uiSound(10128760939, 0.45)  -- "Select 01"

-- Every interactive thing in the shop gets the same pair, so it is one call rather
-- than four copies of the same two Connects.
local function audible(button)
	button.MouseEnter:Connect(function() SFX_HOVER:Play() end)
	button.MouseButton1Click:Connect(function() SFX_CLICK:Play() end)
end

-- Spec fractions. Panel-relative or card-relative throughout so they survive any
-- viewport; nothing here is a pixel.
local PANEL_ASPECT = 1.75   -- w : h
-- The panel's own corner, as a UICorner scale. Shared by the panel, its lip and every
-- layer of its shadow, so the four stay concentric when it is retuned.
local PANEL_CORNER = 0.045
local INSET = 0.02          -- scroll inset from the panel edge, of panel WIDTH
local HEADER_BAND = 0.075   -- of panel height: clears the close button
-- Side inset INSIDE the scroll, of its window width. Cards used to be sized to fill
-- the row exactly, so the outer column's UIStroke — drawn outside the card's bounds
-- — was clipped by the scroll's edge, and the hover pop then pushed a visible slice
-- of the card itself out of view. This is the room both of them need.
local EDGE = 0.02
-- Card width is derived from Columns and GUTTER rather than stated: at 3 columns it
-- comes out at 32.3% of content width, which is the spec's own figure.
local GUTTER = 0.014        -- of content width
local CARD_ASPECT = 1.10    -- w : h
local SECTION_H = 0.22      -- section header height, of card height
local SECTION_TEXT = 0.16   -- of card height
-- Of card height. Was 0.26, when the banner was one left-aligned title over one
-- sub-line; it now carries a centred stack of three rows flanked by a mascot and a
-- price, and none of them resolve at that height.
local FEATURE_H = 0.62
local RIBBON_H = 0.15       -- of card height; also each grid block's top padding
-- Measured floor, not a guess: a 3-wide grid on the smallest phone preset (Galaxy
-- A06, 705x338) makes a 141x128 card, at which size the pill label renders at 9px
-- and the description at 12px. Below this card height the grid drops a column — the
-- reference's own other layout — rather than ship type that small on a phone.
local MIN_CELL_H = 160
-- The panel's white ring, in pixels at STROKE_REF_WIDTH. Spec: ~10px on a 990px
-- panel. The grey outline outside it is the Shadow frame's own stroke, sized off
-- this, because only one UIStroke per instance takes effect.
local RING = 5.5
-- The Robux mark, as a multiple of the price's TextSize. Above 1 on purpose: the
-- number carries a heavy ink outline and the mark carries none, so a mark matched
-- to the bare glyph height sits visibly light next to it.
local MARK_SCALE = 1.32
-- Where a card's product icon sits, and therefore where its sunburst radiates from.
local ICON_X, ICON_Y = 0.28, 0.5

-- Resolved by relayout() from the scroll's real width. Declared here so the layout
-- hooks below can close over them.
local gutterW, cellW, cellH, edgeW = 0, 0, 0, 0
local hooks = {}

local function corner(parent, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.18, 0)
	c.Parent = parent
	return c
end

-- UIStroke.Thickness is in PIXELS and follows neither UIScale nor the panel's own
-- resize, so an outline judged on a 550px-wide panel is a hairline on a phone and a
-- slab on a 4K monitor. Each stroke records the weight it was chosen at and is
-- rescaled from the real width. Weak keys so nothing here pins a destroyed card.
local STROKE_REF_WIDTH = 550
local strokes = setmetatable({}, { __mode = "k" })
local strokeK = 1

local function stroke(parent, color, thickness)
	local base = thickness or 2
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = math.max(1, base * strokeK)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	strokes[s] = base
	return s
end

-- TextScaled fills whatever box it is given, so a three-word blurb in a tall box
-- renders half again the size of a long one. Each cap records the fraction of card
-- height it was chosen at and is resolved in the layout pass, where the card's real
-- pixel height is finally known.
local textCaps = setmetatable({}, { __mode = "k" })

local function capText(label, frac)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 100
	c.Parent = label
	textCaps[c] = frac
	return c
end

local panelScale = panel:WaitForChild("Scale")

-- The panel's shadow on the world. NOT one frame: a single translucent rounded rect
-- has a hard outer edge, and a hard-edged shadow reads as a grey slab taped under the
-- panel rather than as light being blocked — which is the same complaint that got the
-- panel's lip rebuilt. Roblox has no blur for GUI, so the falloff is built by
-- stacking: each layer is a little larger and a little lower than the last and is
-- individually almost transparent, and where many overlap they compound into a dark
-- core that thins smoothly outwards.
--
-- The layer COUNT is the whole quality knob, and six was not enough: against a flat
-- background the rings were individually countable, which is worse than the hard slab
-- it replaced because it reads as a mistake rather than a choice. What has to be
-- invisible is the step between adjacent layers, so the count is set high and the
-- per-layer alpha falls out of it rather than being picked.
--
-- The stack grows DOWNWARD as well as outward, so the shadow is tight along the top
-- edge and long below — one light source, above and slightly in front, the same
-- direction every bevel, gloss and cast shadow in this file already assumes.
--
-- Built by the panel section below; rescaleStrokes() sizes them and runs after.
-- Thirty, not fourteen. Fourteen put the step at ~6% and the rings were still
-- individually countable against a flat background — which is the one thing a stacked
-- shadow must not do, because a visible ring reads as a bug where a hard edge only
-- reads as cheap. Thirty puts it near 3%, under the threshold. Frames are cheap and
-- there is exactly one panel.
local SHADOW_LAYERS = 30
-- DROP now exceeds SPREAD, which is what makes this a drop shadow rather than a halo.
-- While spread dominated, every layer stuck out as far above the panel as below and the
-- result was a glow centred on the panel. With the drop larger, the outer layers' top
-- edges sit at or below the panel's own top edge and hide behind it, so the shadow is a
-- tight contact line above and a long throw below — one light source, overhead.
local SHADOW_SPREAD = 24    -- px at STROKE_REF_WIDTH, outermost layer
local SHADOW_DROP = 30      -- px at STROKE_REF_WIDTH, outermost layer
-- How dark the shadow gets where every layer overlaps. The old single frame was a
-- flat 0.52 everywhere; this is the bottom of a ramp rather than the whole of it.
local SHADOW_CORE = 0.55
-- N layers of transparency t leave t^N of the background showing, so solving that for
-- the core above gives each layer's share. Derived, not tuned: change the count and
-- the shadow keeps the same depth, only smoother. At 30 layers this is ~0.974.
local SHADOW_ALPHA = (1 - SHADOW_CORE) ^ (1 / SHADOW_LAYERS)
local shadowLayers = {}

-- The close button wears the panel's own treatment at button scale: a thick WHITE
-- ring, and a thin ink line OUTSIDE it. That is two outlines and an instance only
-- ever renders one UIStroke, so the white one is the button's and the ink one is a
-- frame behind it — exactly the split the panel makes between its own stroke and the
-- Shadow frame's. The lip is also nudged down, so more of it shows along the bottom
-- edge than the top and the key reads as moulded rather than outlined.
local CLOSE_SIZE = 0.063   -- of panel WIDTH; the button is square
local CLOSE_CORNER = 0.30  -- UICorner scale: a rounded square, not a circle
local CLOSE_RING = 3.4     -- white ring, px at STROKE_REF_WIDTH
local CLOSE_EDGE = 2.6     -- ink line outside the white ring, same units
local closeLip = nil

local function rescaleStrokes()
	-- Divide the UIScale back out. HUDController pops the panel from 0.8 to 1 on
	-- every open, and without this the outlines would thin and thicken through the
	-- animation and hold whatever weight the last frame landed on.
	local w = panel.AbsoluteSize.X / math.max(panelScale.Scale, 0.01)
	if w <= 0 then return end
	strokeK = w / STROKE_REF_WIDTH
	for s, base in pairs(strokes) do
		s.Thickness = math.max(1, base * strokeK)
	end
	-- Spec §1 wants a thick white ring and then a thin cool-grey line OUTSIDE it.
	-- That is two instances, so the grey lives on the Shadow frame behind the panel,
	-- grown to exactly the white ring's reach. The same frame's downward offset is
	-- the drop shadow: it is what shows below the ring and nowhere else.
	local ring = RING * strokeK

	-- The shadow starts OUTSIDE the lip, or the innermost layers would darken the pale
	-- grey lip and the two would read as one muddy band. Everything below is in
	-- unscaled pixels for the same reason the strokes are: UIScale must not change the
	-- shadow's softness while the panel pops open.
	local minSide = math.min(w, w / PANEL_ASPECT)
	local baseR = PANEL_CORNER * minSide
	for i, f in ipairs(shadowLayers) do
		local t = i / SHADOW_LAYERS
		-- Superlinear, so the layers bunch up near the panel and spread out further away.
		-- That is what puts the dark part of the ramp against the edge where contact
		-- shadow belongs, instead of smearing it evenly across the whole spread.
		local spread = ring + SHADOW_SPREAD * strokeK * t ^ 1.35
		local drop = SHADOW_DROP * strokeK * t
		f.Size = UDim2.new(1, spread * 2, 1, spread * 2)
		f.Position = UDim2.new(0.5, 0, 0.5, drop)
		-- Concentric: a layer's radius has to grow with its own spread or the outer ones
		-- square off and the stack reads as a box behind a rounded panel. Expressed as a
		-- scale of the layer's own shorter side so UIScale carries it.
		f.Corner.CornerRadius = UDim.new((baseR + spread) / (minSide + spread * 2), 0)
	end

	if closeLip then
		-- Far enough out to clear the white ring, which is drawn OUTSIDE the button's
		-- bounds, or the ink would sit under it and never show.
		local out = (CLOSE_RING + CLOSE_EDGE) * strokeK
		-- Sized in OFFSET, not scale. The button carries a symmetric 20% UIPadding, so a
		-- child sized 1,1 in scale fills the inset content box and would land INSIDE the
		-- button instead of behind it. Its real side is read back rather than computed
		-- from CLOSE_SIZE because a UISizeConstraint can clamp it on a small viewport.
		-- Position is unaffected: the padding is symmetric, so 0.5 is still the centre.
		local side = closeLip.Parent.AbsoluteSize.X / math.max(panelScale.Scale, 0.01)
		closeLip.Size = UDim2.fromOffset(side + out * 2, side + out * 2)
		closeLip.Position = UDim2.new(0.5, 0, 0.5, CLOSE_EDGE * strokeK * 0.6)
		closeLip.Corner.CornerRadius =
			UDim.new((CLOSE_CORNER * side + out) / (side + out * 2), 0)
	end
	shadow.Size = UDim2.new(1, ring * 2, 1, ring * 2)
	-- Three quarters of the ring, not nine tenths. The frame is opaque now (see
	-- below), so what shows below the white ring is a solid moulded lip and its
	-- depth is a deliberate size rather than whatever the old translucent version
	-- happened to leave uncovered.
	shadow.Position = UDim2.new(0.5, 0, 0.5, ring * 0.75)
end

-- A vertical light-to-dark gradient is the whole bevel trick: it reads as moulded
-- plastic without stacking a second frame behind every element.
--
-- Four stops rather than two. The two-stop version was a flat ramp between the
-- item's own pair; the extra stop at each end is what adds the shading — a lit
-- crown above the pale colour and a shaded lip below the saturated one — while the
-- middle 22%..80% still runs exactly the pair GameConfig declares, so no card
-- changes hue.
local function bevel(obj, grad)
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

-- The sunburst, radiating FROM the product icon. That aim is the whole point of it:
-- centred on the card the rays fan out of a patch of blank gradient between the icon and
-- the blurb and read as wallpaper. Aiming them means magnifying the burst and pushing
-- its centre to (ICON_X, ICON_Y), which means it overflows the element, which means it
-- has to be clipped — cards do NOT clip their own children, the ribbons overhang, so the
-- burst gets a clipping wrapper of its own.
--
-- Two things about that wrapper, both learned the hard way on this panel:
--
--   ClipsDescendants clips to the RECTANGLE. A UICorner on the clipping frame rounds
--   that frame's own background but NOT what it clips (proved by giving the wrapper an
--   opaque fill: the fill came out rounded, the burst inside it still reached the square
--   corners). So the wrapper is INSET instead: a corner of radius r has its arc passing
--   r(1 - 1/sqrt2) = 0.293r from the corner along the diagonal, so a rectangle inset by
--   a little more than that on every side lies entirely inside the rounded shape and has
--   no square corner left to show.
--
--   Insetting costs the burst a few pixels around the perimeter, and with the old
--   cream-GROUND source that was its own artifact: that image darkened everything it
--   covered, so the ~5px it stopped short read as four washed-out corners. The source is
--   now white on a TRANSPARENT ground (see GameConfig.Shop.Rays) and only ADDS light, so
--   there is nothing for the gap to fail to darken. Fading rays that stop 5px early are
--   invisible in a way that a paler corner never was.
--
-- So the inset is only safe because the source is transparent. Put an opaque burst back
-- in GameConfig and the discoloured corners come back with it.
local RAYS_INSET = 0.34 -- of the corner radius; 0.293 is the exact minimum
local RAYS_ZOOM = 1.8
-- This sets how much LIGHTER the rays make the surface, not how strong an image reads:
-- the source is white and the card underneath supplies the hue. Judge it on a card, not
-- on the banner — the banner is darker and shows the rays at roughly half this strength.
local RAYS_FADE = 0.25

-- cx, cy place the burst's own centre in the element's space.
local function rays(obj, grad, cornerScale, cx, cy)
	if not SHOP.Rays then return nil end
	local clip = Instance.new("Frame")
	clip.Name = "Rays"
	clip.BackgroundTransparency = 1
	clip.AnchorPoint = Vector2.new(0.5, 0.5)
	clip.Position = UDim2.fromScale(0.5, 0.5)
	clip.ClipsDescendants = true
	clip.ZIndex = obj.ZIndex

	-- No UICorner here: it would not clip anything (see above). The inset IS the
	-- mechanism, and it is recomputed whenever the element resizes, because the radius
	-- it comes from is a fraction of the element's own shorter side — which changes on
	-- every relayout and on every hover pop.
	local function fit()
		local sz = obj.AbsoluteSize
		local d = RAYS_INSET * (cornerScale or 0.18) * math.min(sz.X, sz.Y)
		clip.Size = UDim2.new(1, -d * 2, 1, -d * 2)
	end
	obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local im = Instance.new("ImageLabel")
	im.Name = "Burst"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(cx or 0.5, cy or 0.5)
	im.Size = UDim2.fromScale(RAYS_ZOOM, RAYS_ZOOM)
	im.Image = SHOP.Rays
	im.ImageTransparency = RAYS_FADE
	-- Fit, not Crop. The burst is radial and the box it is given has the element's
	-- aspect rather than a square one; Crop would fill that box and draw an ELLIPTICAL
	-- burst with the rays stretched along the wider axis. Fit keeps it circular and
	-- centres it in the box, which is what puts its middle on (cx, cy).
	im.ScaleType = Enum.ScaleType.Fit
	im.ZIndex = obj.ZIndex
	-- Deliberately NO bevel() here. The source is white, and white multiplied by the
	-- element's own ramp is exactly the element's own colour — the rays would vanish
	-- into it. The card underneath carries the hue; this only lightens.
	im.Parent = clip

	-- Parented FIRST, before the halftone, the gloss and every label, because ties on
	-- ZIndex are broken by child order and this has to sit under all of them.
	clip.Parent = obj
	return clip
end

-- The printed-dot pass, over the burst and under everything that carries meaning.
--
-- Note what this does NOT do: it takes no gradient and no tint. Every other layer in
-- this file is multiplied by the element's own ramp so the card keeps its hue; this one
-- is white dots at low opacity, which lifts the surface identically on a pink card and
-- a cyan one. That is the point of it — one id, every colour, no per-card tuning.
--
-- Built exactly like rays(): 1:1, ScaleType.Crop, its own UICorner, no wrapper. A
-- UICorner DOES round an ImageLabel's image; what it does not round is a clip region.
-- This layer is where that was established, and rays() was rebuilt to match it.
local function halftone(obj, cornerScale, strength)
	if not SHOP.Halftone then return nil end
	local im = Instance.new("ImageLabel")
	im.Name = "Halftone"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Size = UDim2.fromScale(1, 1)
	im.Image = SHOP.Halftone
	-- Judged at 1:1, not on a magnified copy. Blown up 2.5x the dots looked right at
	-- 0.82 and nearly vanished on a real 272px card — the pattern's scale shrinks with
	-- the element but the eye's threshold does not.
	im.ImageTransparency = strength or 0.76
	-- Crop, not Fit: Fit letterboxes a square source inside a wide element and leaves
	-- the dots floating in a band with bare gradient either side of them.
	im.ScaleType = Enum.ScaleType.Crop
	im.ZIndex = obj.ZIndex
	corner(im, cornerScale)
	im.Parent = obj
	return im
end

-- The specular pass: a white sheet over the top of an element, fading out downward.
-- It is one frame with a transparency ramp rather than a second gradient on the
-- element itself, because an element only takes one UIGradient and bevel() already
-- has it. Purely decorative, and a Frame consumes no input, so the card underneath
-- still gets its own hover and click.
local function gloss(obj, frac, cornerScale, strength)
	frac = frac or 0.46
	local g = Instance.new("Frame")
	g.Name = "Gloss"
	g.BackgroundColor3 = WHITE
	g.BorderSizePixel = 0
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.fromScale(0.5, 0)
	g.Size = UDim2.fromScale(1, frac)
	g.ZIndex = obj.ZIndex

	-- UICorner is a fraction of the SHORTER side, so the sheet's own radius has to be
	-- the element's radius divided by the sheet's share of its height, or the white
	-- would square off the rounded top corners it is sitting in.
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

-- Contextual, NOT Border. stroke() above forces Border, which on a TextLabel with a
-- transparent background strokes the label's bounding box instead of the glyphs.
-- Contextual is what makes a UIStroke follow the letterforms. One UIStroke per
-- instance is all that takes effect, so anything that already has a stroke() border
-- must not also call this.
local function outline(label, thickness)
	local s = stroke(label, P.Ink, thickness or 2)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	-- FredokaOne is round; without this the stroke spikes at the letter joins.
	s.LineJoinMode = Enum.LineJoinMode.Round
	return s
end

-- Ribbons and the line under a price: TEXT, with nothing behind it. These were
-- bordered plates, which put two more button-shaped things on a card that is itself
-- a button — three things to press and only one of them live. Yellow with a heavy
-- ink outline is the reference's own treatment and needs no frame, no gradient and
-- no second instance for the stroke.
local function tag(name, text, z)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = P.Tag
	t.FontFace = FONT
	t.TextScaled = true
	t.ZIndex = z
	outline(t, 2.2)
	return t
end

-- A cast shadow: the element's own shape, behind it and offset down, with a
-- transparency ramp that starts invisible at the element's top and reaches full
-- strength below its bottom edge. Ramped rather than flat, because a flat
-- translucent rectangle poking out from behind a panel reads as a gap in the panel
-- rather than as a shadow — which is precisely what the panel's own lip had to be
-- rebuilt to answer.
local function castShadow(obj, drop, cornerScale, z, strength)
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
	-- shadow grows with the card instead of being left behind by it.
	s.ZIndex = z
	corner(s, cornerScale)

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

------------------------------------------------------------------------- panel
panel.BackgroundColor3 = P.Panel
panel.Size = UDim2.fromScale(0.72, 0.78)
panel.UIAspectRatioConstraint.AspectRatio = PANEL_ASPECT
panel.UICorner.CornerRadius = UDim.new(PANEL_CORNER, 0)
do
	-- The ring stays WHITE while every border inside the panel is ink. It is the
	-- panel's own edge against the 3D world, not one of the things drawn on it, and
	-- it is the single most recognisable thing about the shape after the
	-- overhanging header.
	local s = panel:FindFirstChildOfClass("UIStroke")
	s.Color = WHITE
	strokes[s] = RING
end

-- OPAQUE, and pale. It was ink at 0.78 transparency, which put a see-through sliver
-- of the 3D world between the white ring and the grey outline along the bottom edge
-- — read as a gap in the panel rather than as a shadow, because that is what it
-- was. Solid pale grey in the same place reads as the moulded lip of a thick plastic
-- panel instead, and there is nothing left to see through.
--
-- Both greys are mixed from the palette rather than picked: a grey chosen by eye
-- drifts against the panel the moment PANEL or INK is re-tuned.
shadow.BackgroundColor3 = P.Ink:Lerp(P.Panel, 0.80)
shadow.BackgroundTransparency = 0
shadow.ZIndex = 49
shadow.UICorner.CornerRadius = UDim.new(PANEL_CORNER, 0)
-- Thin now. At RING + 1.6 it was a slab as wide as the white ring itself, which is
-- what made the sliver between them read as a channel between two borders.
stroke(shadow, P.Ink:Lerp(P.Panel, 0.46), 2.2)
-- The lip is lit at its own top, which is the whole reason it reads as thickness
-- and not as a second border drawn in a different colour.
local shadowGrad = Instance.new("UIGradient")
shadowGrad.Rotation = 90
shadowGrad.Color = ColorSequence.new(P.Ink:Lerp(P.Panel, 0.88), P.Ink:Lerp(P.Panel, 0.62))
shadowGrad.Parent = shadow

-- The panel's shadow on the world, distinct from the lip: it sits further out and
-- further down, and is sized by rescaleStrokes off the same ring. See SHADOW_LAYERS.
for i = 1, SHADOW_LAYERS do
	local f = Instance.new("Frame")
	f.Name = "Cast" .. i
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = BLACK
	f.BackgroundTransparency = SHADOW_ALPHA
	f.BorderSizePixel = 0
	-- The HUD is ZIndexBehavior.Global, so a child below its parent's ZIndex draws
	-- behind it. Being a CHILD is the point: the stack inherits the panel's open pop
	-- and its shadow grows with it instead of being left behind. Largest layer
	-- furthest back, so the compounding runs the right way.
	--
	-- Counted DOWN from the lip rather than up from a fixed floor. The stack is as many
	-- ZIndex values deep as it has layers, so a fixed floor silently couples the layer
	-- count to the panel's own ZIndex — raising it from 6 to 14 ran the top of the range
	-- past the panel (50), the studs (50) and the scroll (52), and the shadow drew over
	-- the panel's face and greyed the whole thing out.
	f.ZIndex = shadow.ZIndex - SHADOW_LAYERS - 1 + i
	local c = Instance.new("UICorner")
	c.Name = "Corner"
	c.Parent = f
	f.Parent = panel
	-- Outermost first, so index order matches the ramp rescaleStrokes walks.
	shadowLayers[SHADOW_LAYERS + 1 - i] = f
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

shadeBody(panel)
task.spawn(function()
	-- Studs is HUDController's, built on its own schedule; this only tints it.
	local studs = panel:WaitForChild("Studs", 10)
	if studs then shadeBody(studs) end
end)

-- Static children with no job left in this layout. Hidden, not destroyed: the panel
-- is shared StarterGui furniture and something else may yet want them.
panel:WaitForChild("Rule").Visible = false
panel:WaitForChild("Body").Visible = false

------------------------------------------------------------------ header chrome
-- All three of these overhang the panel's top edge, roughly half above and half
-- below. ShopPanel.ClipsDescendants is false, which is what allows it.
local title = panel:WaitForChild("Title")
title.Text = SHOP.Title or "Shop!"
title.TextColor3 = WHITE
title.AnchorPoint = Vector2.new(0, 0.5)
title.Position = UDim2.fromScale(0.075, 0)
-- Font ends up ~7.5% of panel width: the box is 7.5% of width expressed in height
-- units, and TextScaled takes the tighter of the two limits.
title.Size = UDim2.fromScale(0.58, 0.075 * PANEL_ASPECT)
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 61
title.Visible = true
do
	local s = title:FindFirstChildOfClass("UIStroke")
	s.Color = P.Ink
	strokes[s] = 3
end

if SHOP.TitleIcon then
	local icon = Instance.new("ImageLabel")
	icon.Name = "TitleIcon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	-- On the top-LEFT corner itself, half outside on both axes.
	icon.Position = UDim2.fromScale(0.018, 0)
	icon.Size = UDim2.fromScale(0.11, 0.11 * PANEL_ASPECT)
	icon.Rotation = -8
	icon.Image = SHOP.TitleIcon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 62
	icon.Parent = panel
end

-- There is NO counter pill top-right. It showed a hard-coded 0 because nothing
-- reads the player's balance, and Roblox draws the real Robux figure in its own
-- topbar a few pixels above where this sat. Removing it is also what let
-- HEADER_BAND drop from 0.115 to 0.075 and gave the content that height back.

-- HUDController finds this recursively and does button:WaitForChild("Scale"), so it
-- keeps its name, its place under the panel and its UIScale child. Only the look and
-- the position move.
local close = panel:FindFirstChild("CloseButton", true)
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.fromScale(0.978, 0.012)
close.Size = UDim2.fromScale(CLOSE_SIZE, CLOSE_SIZE * PANEL_ASPECT)
close.BackgroundColor3 = P.Close
close.TextColor3 = WHITE
close.ZIndex = 62
-- The glyph moves OUT of the button and into a child label. A UIGradient colours
-- everything the object draws, its text included, so the hard stop that gives the
-- button its dark lower band was also painting a straight dark line straight across
-- the X. A gradient does not reach into children, so a child label is drawn in flat
-- white. The button's UIPadding is a symmetric 20%, so the label fills that inset
-- box and stays centred.
close.Text = ""
do
	local glyph = close:FindFirstChild("Glyph") or Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.46)
	-- Over 1, deliberately. The button's 20% UIPadding is what centres this label, but
	-- it also means a label sized 1,1 gets a box only 60% of the button and TextScaled
	-- then draws an X too small to be the button's whole subject. Overflowing the
	-- content box costs nothing — the button does not clip — and AnchorPoint keeps it
	-- centred at any size.
	glyph.Size = UDim2.fromScale(1.34, 1.34)
	glyph.Text = "X"
	glyph.TextColor3 = WHITE
	glyph.FontFace = FONT
	glyph.TextScaled = true
	glyph.ZIndex = 63
	glyph.Parent = close
	-- The X gets its own ink contour, the same one every other piece of type in this
	-- panel wears. Without it a white glyph on red, ringed by a white stroke a few
	-- pixels away, has two whites competing at the same weight and the X stops being
	-- the thing you read first. Contextual, so it follows the letterform — outline()
	-- handles that, and registers the stroke for rescaling with the rest.
	--
	-- Thin. This is the lightest outline in the file, and it has to be: every other one
	-- sits on type several times this size, where 2-3px reads as a contour, while on a
	-- glyph about 30px tall the same weight closed up the X's own gaps and left a dark
	-- blob with a white cross scratched into it.
	if not glyph:FindFirstChildOfClass("UIStroke") then
		outline(glyph, 1.3)
	end
end
audible(close)
do
	close.UICorner.CornerRadius = UDim.new(CLOSE_CORNER, 0)

	-- WHITE, not ink. It is the same argument as the panel's own ring: this is the
	-- button's edge against the world rather than one of the marks drawn on it, and the
	-- dark line it used to have made a red square with a thin border instead of a key.
	local s = close:FindFirstChildOfClass("UIStroke")
	s.Color = WHITE
	strokes[s] = CLOSE_RING
	-- Border, explicitly. The stroke came out of StarterGui set to Contextual, and
	-- Contextual on a TextButton means the CONTOUR OF ITS TEXT — which has been empty
	-- since the glyph moved into a child label, so the stroke was drawing nothing at
	-- all. The ink outline this replaces had not been visible for some time either.
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- The ink line outside the white ring, and the moulded lip under it. Sized by
	-- rescaleStrokes; a child, so it inherits the hover pop and rotation attachFeel
	-- puts on the button. ZIndex below its own parent's is legal here because the HUD
	-- is ZIndexBehavior.Global.
	closeLip = close:FindFirstChild("Lip") or Instance.new("Frame")
	closeLip.Name = "Lip"
	closeLip.AnchorPoint = Vector2.new(0.5, 0.5)
	closeLip.BackgroundColor3 = P.Ink
	closeLip.BackgroundTransparency = 0
	closeLip.BorderSizePixel = 0
	closeLip.ZIndex = close.ZIndex - 1
	if not closeLip:FindFirstChild("Corner") then
		local c = Instance.new("UICorner")
		c.Name = "Corner"
		c.Parent = closeLip
	end
	closeLip.Parent = close
	-- A darker red BAND across the bottom quarter, not a gradient: the reference's
	-- close button reads as a moulded key with a lip, and a smooth ramp reads as a
	-- lighting effect instead. Hard stops in one UIGradient, no extra frame.
	local g = close:FindFirstChildOfClass("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, P.Close),
		ColorSequenceKeypoint.new(0.74, P.Close),
		ColorSequenceKeypoint.new(0.75, P.CloseDeep),
		ColorSequenceKeypoint.new(1, P.CloseDeep),
	})
end

------------------------------------------------------------------------ scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Scroll"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.AnchorPoint = Vector2.new(0, 0)
scroll.Position = UDim2.fromScale(INSET, HEADER_BAND)
-- Bottom inset is the same 2% of panel WIDTH as the sides, which is 2% * aspect of
-- panel height.
scroll.Size = UDim2.fromScale(1 - INSET * 2, 1 - HEADER_BAND - INSET * PANEL_ASPECT)
scroll.ZIndex = 52
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
-- Inset rather than overlay, so AbsoluteWindowSize is the real content width and
-- three cards plus two gutters (99.7% of it) still fit.
scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
scroll.ScrollBarImageColor3 = P.Ink:Lerp(P.Panel, 0.25)
scroll.ScrollBarImageTransparency = 0.15
scroll.Parent = panel

local scrollPad = Instance.new("UIPadding")
scrollPad.Parent = scroll

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
-- Without this the list sorts by name, which put Coins above Offers.
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

table.insert(hooks, function()
	scrollPad.PaddingTop = UDim.new(0, cellH * 0.06)
	-- Bottom padding is what keeps the last row from being cut flush against the
	-- panel edge, which reads as a rendering fault rather than as more content.
	scrollPad.PaddingBottom = UDim.new(0, cellH * 0.14)
	-- The side gutters the cards' strokes and their hover pop live in.
	scrollPad.PaddingLeft = UDim.new(0, edgeW)
	scrollPad.PaddingRight = UDim.new(0, edgeW)
	list.Padding = UDim.new(0, cellH * 0.05)
	scroll.ScrollBarThickness = math.max(4, panel.AbsoluteSize.X * 0.014)
end)

----------------------------------------------------------------------- feature
-- The static Banner frame, reparented into the scroll as the list's first row. It
-- scrolls with the content: it is an offer, not pinned chrome.
local feature = SHOP.Feature
if feature then
	local banner = panel:WaitForChild("Banner")
	banner.Name = "Feature"
	banner.Visible = true
	banner.AnchorPoint = Vector2.new(0, 0)
	banner.Position = UDim2.fromScale(0, 0)
	banner.LayoutOrder = 0
	banner.ZIndex = 53
	banner.BackgroundColor3 = feature.Grad[1]
	bevel(banner, feature.Grad)
	-- 0.14, not 0.4. UICorner scale is of the shorter side, and the banner is much
	-- taller now that it carries three stacked rows — at 0.4 it rounded into a
	-- lozenge rather than the gently rounded plate the reference uses.
	banner.UICorner.CornerRadius = UDim.new(0.14, 0)
	-- A UICorner scale clamps at half the shorter side, so a gloss sheet that is only
	-- part of the banner's height can never round as hard as the banner does and its
	-- white corners would sit outside it. Clipping the banner settles that, and the
	-- burst behind it. The mascot is the one thing meant to overhang, so it is placed
	-- inside the banner's bounds rather than over its edge. Cards are NOT clipped —
	-- their ribbons overhang — which is why their burst and gloss match radius by
	-- arithmetic instead.
	banner.ClipsDescendants = true
	-- Centred on the contents strip, which is what this banner is selling.
	-- Centred on the contents strip, which is what this banner is selling.
	rays(banner, feature.Grad, 0.14, 0.5, 0.53)
	-- Parented after the burst and before the gloss, so the dots sit on the rays and the
	-- specular sheet sits on both. Lighter than the cards': the banner is already the
	-- busiest element on the panel and a full-strength dot field competed with the
	-- contents strip.
	halftone(banner, 0.14, 0.88)
	gloss(banner, 0.5, 0.25, 0.66)
	do
		local s = banner:FindFirstChildOfClass("UIStroke")
		s.Color = P.Ink
		strokes[s] = 3
	end
	banner.Parent = scroll

	-- The mascot, overhanging the left end. It is what the reference leads with and
	-- it is why the centre column starts at 0.2 rather than at the banner's edge.
	if feature.Mascot then
		local m = Instance.new("ImageLabel")
		m.Name = "Mascot"
		m.BackgroundTransparency = 1
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.075, 0.52)
		m.Size = UDim2.fromScale(0.115, 0.84)
		m.Image = feature.Mascot
		m.ScaleType = Enum.ScaleType.Fit
		m.ZIndex = 55
		m.Parent = banner
	end

	-- Title, contents strip and sub-line are a CENTRED stack, not a left-aligned
	-- block: the reference reads title over contents over promise, with the mascot
	-- and the price flanking it.
	local head = Instance.new("TextLabel")
	head.Name = "FeatureTitle"
	head.BackgroundTransparency = 1
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.045)
	head.Size = UDim2.fromScale(0.56, 0.29)
	head.Text = feature.Title or ""
	-- Yellow with an ink outline, like every other call-out in the panel. Navy read
	-- as a caption once the title moved on top of the stack and grew.
	head.TextColor3 = P.Tag
	head.FontFace = FONT
	head.TextScaled = true
	head.ZIndex = 54
	outline(head, 2.6)
	head.Parent = banner

	local sub = Instance.new("TextLabel")
	sub.Name = "FeatureSub"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.Position = UDim2.fromScale(0.5, 0.965)
	sub.Size = UDim2.fromScale(0.56, 0.21)
	sub.Text = feature.Sub or ""
	-- White with an ink outline rather than navy: this line is well under half the
	-- height of the title, and navy on the gradient's saturated end does not hold at
	-- that size.
	sub.TextColor3 = WHITE
	sub.FontFace = FONT
	sub.TextScaled = true
	sub.ZIndex = 54
	outline(sub, 1.8)
	sub.Parent = banner

	if feature.Icons and #feature.Icons > 0 then
		local strip = Instance.new("Frame")
		strip.Name = "Icons"
		strip.BackgroundTransparency = 1
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		-- The middle band of the centred stack: between the title above and the
		-- sub-line below, clear of the mascot at 0.02..0.13 and the price at 0.80..0.98.
		strip.Position = UDim2.fromScale(0.5, 0.53)
		strip.Size = UDim2.fromScale(0.5, 0.3)
		strip.ZIndex = 54
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Parent = strip
		for i, id in ipairs(feature.Icons) do
			local im = Instance.new("ImageLabel")
			im.Name = "Icon" .. i
			im.BackgroundTransparency = 1
			im.LayoutOrder = i
			im.Size = UDim2.fromScale(1 / #feature.Icons, 1)
			im.Image = id
			im.ScaleType = Enum.ScaleType.Fit
			im.ZIndex = 55
			im.Parent = strip
		end
		strip.Parent = banner
	end

	-- The price. The ONLY remaining pill in the shop, and deliberately so: it is the
	-- one thing on the banner you are being asked to press, and the reference draws
	-- it as a green plate for exactly that reason. Card prices are bare because a
	-- whole card is already the button.
	if feature.Price then
		local pp = Instance.new("Frame")
		pp.Name = "FeaturePrice"
		pp.AnchorPoint = Vector2.new(1, 0.5)
		pp.Position = UDim2.fromScale(0.975, 0.5)
		pp.Size = UDim2.fromScale(0.16, 0.38)
		pp.BackgroundColor3 = P.Green[1]
		pp.BorderSizePixel = 0
		pp.ZIndex = 55
		corner(pp, 0.4)
		stroke(pp, P.Ink, 2.4)
		bevel(pp, P.Green)

		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0.04, 0)
		lay.Parent = pp

		if SHOP.PriceIcon then
			local m = Instance.new("ImageLabel")
			m.Name = "RobuxIcon"
			m.BackgroundTransparency = 1
			m.LayoutOrder = 1
			-- Generous width, squared off the pill's height by the constraint — which
			-- only ever shrinks, so a zero width would render nothing at all.
			m.Size = UDim2.fromScale(0.4, 0.74)
			m.Image = SHOP.PriceIcon
			m.ImageColor3 = BLACK
			m.ScaleType = Enum.ScaleType.Fit
			m.ZIndex = 56
			local ar = Instance.new("UIAspectRatioConstraint")
			ar.AspectRatio = 1
			ar.Parent = m
			m.Parent = pp
		end

		local pl = Instance.new("TextLabel")
		pl.Name = "Label"
		pl.BackgroundTransparency = 1
		pl.LayoutOrder = 2
		pl.Size = UDim2.fromScale(0.44, 0.62)
		pl.Text = feature.Price
		pl.TextColor3 = WHITE
		pl.FontFace = FONT
		pl.TextScaled = true
		pl.ZIndex = 56
		outline(pl, 2.2)
		pl.Parent = pp

		pp.Parent = banner
	end

	-- "Top Seller" is its own centred line UNDER the banner, on the panel, which is
	-- where the reference puts it. On the banner it would be a fourth stacked row
	-- competing with the three that are already there.
	local ftag = nil
	if feature.Tag then
		ftag = tag("FeatureTag", feature.Tag, 54)
		ftag.Size = UDim2.new(1, 0, 0, 1)
		ftag.LayoutOrder = 1
		ftag.Parent = scroll
	end

	table.insert(hooks, function()
		banner.Size = UDim2.new(1, 0, 0, math.max(1, cellH * FEATURE_H))
		if ftag then
			ftag.Size = UDim2.new(1, 0, 0, math.max(1, cellH * 0.13))
		end
	end)
end

------------------------------------------------------------------------- cards
-- NOT_WIRED: pressing a card is deliberately inert. Wiring it means a server remote
-- that calls MarketplaceService:PromptProductPurchase with a real id; doing it from
-- the client with a fake id would just error in front of the player.
local function onPressed(_item)
end

local function makeCard(item, order)
	local grad = item.Grad or P.Gold

	-- The grid positions this SLOT, and the card floats inside it anchored at the
	-- centre. Before, the grid positioned the card itself, whose UIScale pop then
	-- grew from its top-left corner: the outer column expanded rightwards straight
	-- out of the scroll's clip, so a hovered card lost a slice of itself and its
	-- stroke was cut even at rest. Anchored centre, the pop spreads evenly into the
	-- gutter that EDGE now reserves on both sides.
	local slot = Instance.new("Frame")
	slot.Name = item.Name
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = order
	slot.ZIndex = 53

	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.Text = ""
	card.AutoButtonColor = false
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = grad[1]
	card.BorderSizePixel = 0
	card.ZIndex = 54
	-- UICorner scale is of the SHORTER side, which on a 1.10:1 card is the height,
	-- so the spec's 6% of card WIDTH is 6.6% of card height.
	corner(card, 0.066)
	-- Ink, not white. Every border drawn INSIDE the panel is ink; the white ring is
	-- the panel's own edge against the world and is the only one left.
	stroke(card, P.Ink, 3.5)
	-- bevel() on the card itself is what shows if the burst image fails to load; the
	-- burst covers it completely and carries the same ramp.
	bevel(card, grad)
	-- Centred on the product icon at (0.28, 0.5), not on the card.
	rays(card, grad, 0.066, ICON_X, ICON_Y)
	halftone(card, 0.066)
	-- Weaker than it was: the burst already lifts the card's top half, and the two
	-- together flattened it out.
	gloss(card, 0.46, 0.066, 0.74)
	castShadow(card, 0.045, 0.066, 53, 0.5)

	-- Title band, 0.08 .. 0.28 of card height.
	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.18)
	-- The box is 14.5% of card height, so TextScaled cannot exceed the spec's size.
	name.Size = UDim2.fromScale(0.92, 0.145)
	name.Text = item.Name
	name.TextColor3 = WHITE
	name.FontFace = FONT
	name.TextScaled = true
	name.ZIndex = 55
	outline(name, 2)
	name.Parent = card

	-- Body band, 0.28 .. 0.72: icon LEFT at x 0.09 .. 0.47.
	-- Fit, not Stretch: these icons come from a dozen creators at a dozen aspect
	-- ratios, and stretching turned round coins into ovals.
	if item.Icon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(ICON_X, ICON_Y)
		icon.Size = UDim2.fromScale(0.38, 0.44)
		icon.Image = item.Icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 55
		icon.Parent = card
	end

	-- Description RIGHT at x 0.50 .. 0.95. White with an ink outline, matching the
	-- reference: navy body copy disappeared into the saturated bottom half of a
	-- violet or pink card, and outlined white is legible on all five gradients. It
	-- does not compete with the product name because it is a third of the size.
	local blurb = Instance.new("TextLabel")
	blurb.Name = "Blurb"
	blurb.BackgroundTransparency = 1
	blurb.AnchorPoint = Vector2.new(0.5, 0.5)
	blurb.Position = UDim2.fromScale(0.725, 0.5)
	blurb.Size = UDim2.fromScale(0.45, 0.42)
	blurb.Text = item.Blurb or ""
	blurb.TextColor3 = WHITE
	blurb.FontFace = FONT
	blurb.TextScaled = true
	blurb.TextWrapped = true
	blurb.ZIndex = 55
	capText(blurb, 0.098)
	outline(blurb, 1.6)
	blurb.Parent = card

	-- Price row, 0.74 .. 0.96: the Robux mark and then the number, centred together
	-- as one unit. GameConfig's Price is a bare number for exactly this reason — it
	-- used to carry its own "R$" and a drawn mark would then say it twice. When a
	-- tag follows, the row moves up to make room.
	local hasTag = item.Tag ~= nil
	local row = Instance.new("Frame")
	row.Name = "PriceRow"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, hasTag and 0.78 or 0.85)
	row.Size = UDim2.fromScale(0.86, hasTag and 0.16 or 0.19)
	row.ZIndex = 55

	local rowLay = Instance.new("UIListLayout")
	rowLay.FillDirection = Enum.FillDirection.Horizontal
	rowLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLay.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLay.SortOrder = Enum.SortOrder.LayoutOrder
	rowLay.Parent = row

	local mark = nil
	if SHOP.PriceIcon then
		mark = Instance.new("ImageLabel")
		mark.Name = "RobuxIcon"
		mark.BackgroundTransparency = 1
		mark.LayoutOrder = 1
		-- Sized in the layout pass off the price's own TextSize rather than fitted to
		-- the row's height, because the number is drawn with a heavy outline that the
		-- mark does not have: matched to the bare glyph height it reads a size small
		-- beside it. MARK_SCALE is that correction.
		mark.Image = SHOP.PriceIcon
		-- The artwork ships white; ImageColor3 multiplies, so black gives a solid black
		-- glyph with the transparent square still punched through it.
		mark.ImageColor3 = BLACK
		mark.ScaleType = Enum.ScaleType.Fit
		mark.ZIndex = 56
		-- No UIStroke. Outlining the mark to match the number's weight rounded its
		-- corners into a blob and read as a border drawn around it rather than as a
		-- heavier glyph. The weight comes from the artwork instead — GameConfig's ROBUX
		-- is the thicker-ringed variant — plus MARK_SCALE.
		mark.Parent = row
	end

	-- AutomaticSize.X so the number sits tight against the mark instead of centring
	-- inside a box of its own. That rules out TextScaled, so the size is resolved
	-- from the card height in the layout pass, the same way section headers are.
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.AutomaticSize = Enum.AutomaticSize.X
	price.Size = UDim2.new(0, 0, 1, 0)
	price.LayoutOrder = 2
	price.Text = item.Price or ""
	price.TextColor3 = WHITE
	price.FontFace = FONT
	price.ZIndex = 56
	outline(price, 2.6)
	price.Parent = row
	row.Parent = card

	table.insert(hooks, function()
		local size = math.max(10, cellH * (hasTag and 0.13 or 0.15))
		price.TextSize = size
		rowLay.Padding = UDim.new(0, cellH * 0.02)
		if mark then
			local s = math.floor(size * MARK_SCALE)
			mark.Size = UDim2.fromOffset(s, s)
		end
	end)

	-- The line under the price: type, not a plate.
	if item.Tag then
		local tg = tag("Tag", item.Tag, 56)
		tg.AnchorPoint = Vector2.new(0.5, 0.5)
		tg.Position = UDim2.fromScale(0.5, 0.925)
		tg.Size = UDim2.fromScale(0.9, 0.1)
		tg.Parent = card
	end

	-- The ribbon floats on the PANEL above the card, not on it. The grid block
	-- reserves one ribbon's height of top padding so AutomaticSize accounts for it
	-- and the first row's ribbons are neither clipped by the scroll's top edge nor
	-- sitting on the section header.
	if item.Ribbon then
		local rb = tag("Ribbon", item.Ribbon, 56)
		rb.AnchorPoint = Vector2.new(0.5, 1)
		rb.Position = UDim2.fromScale(0.5, -0.015)
		rb.Size = UDim2.fromScale(0.5, 0.12)
		rb.Parent = card
	end

	-- The reference pops its cards rather than tinting them, and a scale reads on
	-- touch too, where there is no hover at all. The card is anchored at its own
	-- centre inside the slot, so this grows in every direction equally.
	local pop = Instance.new("UIScale")
	pop.Parent = card

	audible(card)

	card.MouseEnter:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	card.MouseButton1Down:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
	end)
	card.MouseButton1Click:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		onPressed(item)
	end)

	card.Parent = slot
	return slot
end

---------------------------------------------------------------------- sections
local function makeHeader(section, order)
	local row = Instance.new("Frame")
	row.Name = section.Name .. "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 1)
	row.LayoutOrder = order
	row.ZIndex = 53

	local inner = Instance.new("UIListLayout")
	inner.FillDirection = Enum.FillDirection.Horizontal
	inner.HorizontalAlignment = Enum.HorizontalAlignment.Center
	inner.VerticalAlignment = Enum.VerticalAlignment.Center
	inner.SortOrder = Enum.SortOrder.LayoutOrder
	inner.Parent = row

	-- HeaderIcon is drawn on BOTH sides of the text when present.
	local icons = {}
	local function addIcon(o)
		if not section.HeaderIcon then return end
		local im = Instance.new("ImageLabel")
		im.Name = "HeaderIcon"
		im.BackgroundTransparency = 1
		im.LayoutOrder = o
		im.Image = section.HeaderIcon
		im.ScaleType = Enum.ScaleType.Fit
		im.ZIndex = 54
		im.Parent = row
		table.insert(icons, im)
	end

	addIcon(1)

	-- AutomaticSize.X, not TextScaled: the icons sit immediately either side of the
	-- text, so the label has to be exactly as wide as its own glyphs. That means an
	-- explicit TextSize, which the layout pass resolves from the card height.
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.LayoutOrder = 2
	label.Text = section.Header or section.Name
	-- White on a heavy ink outline, bigger than it was, matching every other heading
	-- in the panel. Flat navy at 12% of card height read as body copy that happened
	-- to be centred, not as the name of a shelf.
	label.TextColor3 = WHITE
	label.FontFace = FONT
	label.ZIndex = 54
	outline(label, 3)
	label.Parent = row

	addIcon(3)

	table.insert(hooks, function()
		local h = math.max(1, cellH * SECTION_H)
		row.Size = UDim2.new(1, 0, 0, h)
		label.TextSize = math.max(12, cellH * SECTION_TEXT)
		inner.Padding = UDim.new(0, cellH * 0.04)
		for _, im in ipairs(icons) do
			im.Size = UDim2.fromOffset(h * 0.85, h * 0.85)
		end
	end)

	return row
end

local function makeGrid(section, order)
	local block = Instance.new("Frame")
	block.Name = section.Name
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, 0, 0, 0)
	-- Non-circular because the cells below are OFFSETS. UIGridLayout cells in SCALE
	-- inside a frame with AutomaticSize.Y never resolve — each side waits on the
	-- other.
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.LayoutOrder = order
	block.ZIndex = 53

	local pad = Instance.new("UIPadding")
	pad.Parent = block

	local grid = Instance.new("UIGridLayout")
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = block

	for i, item in ipairs(section.Items) do
		makeCard(item, i).Parent = block
	end

	table.insert(hooks, function()
		grid.CellSize = UDim2.fromOffset(cellW, cellH)
		-- Vertical gutter clears a ribbon too, or the second row's ribbons would sit
		-- on the first row's cards.
		grid.CellPadding = UDim2.fromOffset(gutterW, cellH * (RIBBON_H + 0.06))
		pad.PaddingTop = UDim.new(0, cellH * RIBBON_H)
	end)

	return block
end

for i, section in ipairs(SHOP.Sections) do
	makeHeader(section, i * 10).Parent = scroll
	makeGrid(section, i * 10 + 1).Parent = scroll
end

------------------------------------------------------------------------ layout
local function relayout()
	-- AbsoluteWindowSize, not AbsoluteSize: the scrollbar is inset, and three cards
	-- plus two gutters come to 99.7% of the content width — a 12px error loses a
	-- column.
	-- AbsoluteWindowSize does NOT account for the scroll's own UIPadding, so the
	-- side gutters have to come off it by hand before anything is sized against it.
	local w = scroll.AbsoluteWindowSize.X
	if w <= 1 then return end
	edgeW = math.floor(w * EDGE)
	w -= edgeW * 2
	if w <= 1 then return end
	-- FLOORED, both of them, because UDim.Offset is an integer and UIGridLayout
	-- rounds a fractional cell UP. At a 872px content width the exact figures are a
	-- 282.5px cell and a 12.2px gutter, which round to 283 and 12 — 873px for three
	-- cards and two gutters, one pixel over, and the grid quietly wrapped the third
	-- card onto its own row. Every section was rendering two-wide.
	gutterW = math.floor(w * GUTTER)
	-- Columns is what sizes the cell; at 3 it lands on the spec's 32.3% of content
	-- width on its own, so the card width is derived rather than restated.
	local cols = SHOP.Columns or 3
	while true do
		cellW = math.floor((w - gutterW * (cols - 1)) / cols)
		cellH = math.floor(cellW / CARD_ASPECT)
		if cellH >= MIN_CELL_H or cols <= 2 then break end
		cols -= 1
	end
	for _, f in ipairs(hooks) do
		f()
	end
	for c, frac in pairs(textCaps) do
		c.MaxTextSize = math.max(1, cellH * frac)
	end
end

-- Both signals: the scroll's own is the direct one, and the HUD's is the one that
-- definitely moves when the viewport does.
scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescaleStrokes)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescaleStrokes)
relayout()
rescaleStrokes()
