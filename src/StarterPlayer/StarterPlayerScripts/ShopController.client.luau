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

local CONFIG = require(ReplicatedStorage:WaitForChild("GameConfig"))
local SHOP = CONFIG.Shop
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

-- The reward chime, shared with the daily panel through GameConfig.Sfx so the
-- two cannot drift into two different "you got it" sounds. Built with uiSound
-- like the other two, so it lands groupless under SoundService and
-- SettingsController adopts it into UISfx with them.
--
-- NOT first-party, unlike the pair above, so it is the one sound in this file
-- that could in principle need the experience granted access to it — verified
-- loading here (IsLoaded true, 0.94s), because it is a Creator Store PAGE id and
-- audio needs no unwrapping the way an image does.
--
-- HONEST ABOUT WHAT IT MARKS: nothing in this panel buys anything — there is no
-- purchase remote and no product ids — so this is the sound of PRESSING a buy
-- control, not of a grant. When the remote exists it moves to the remote's reply
-- and a refused purchase stops playing it.
local SFX_REWARD = uiSound(
	(CONFIG.Sfx and CONFIG.Sfx.Reward) or 130452529897520,
	(CONFIG.Sfx and CONFIG.Sfx.RewardVolume) or 0.55
)

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
-- Empty space ABOVE a section header, of card height. Every header except the first
-- one in the scroll gets it. Without it a shelf's last row of cards and the next
-- shelf's title are separated only by the list's own 0.05 padding, so "Limited
-- Offers" and "More Permanent Passes" read as one continuous run of product rather
-- than as two shelves. The gap goes above only — put it around the header and it
-- pushes the title away from the grid it names.
local SECTION_GAP = 0.16
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
-- The Robux mark, as a multiple of the price's TextSize. Still above 1 — a mark
-- matched to the bare glyph height sits small beside a number — but lower than the
-- 1.32 it was: that figure also compensated for a mark drawn with no outline at all
-- next to a heavily outlined number, and robuxMark's stamped ink contour now carries
-- that weight. At 1.32 with the contour the coin was bigger than the digits.
local MARK_SCALE = 1.15
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
-- This sets how much LIGHTER the rays make the surface, not how strong an image reads:
-- the source is white and the card underneath supplies the hue. Judge it on a card, not
-- on the banner — the banner is darker and shows the rays at roughly half this strength.
local RAYS_FADE = 0.25
-- The burst is drawn far bigger than its host and CROPPED by the wrapper. That is
-- what lets it be AIMED at the product icon and still cover the element.
--
-- It does not spin, and that is deliberate. A rotated GuiObject is not clipped —
-- not by its own wrapper once it is a few levels deep, and not by the scroll — so
-- a spinning burst either escapes its card or has to shrink to a circle that fits
-- unaided, and a circle that fits is far smaller than the aimed, cropped burst
-- below. Both were tried on this panel and both were worse than a still one. The
-- only burst that turns in this game is the shop TILE's, in HUDController, where
-- it sits alone in its own group with nothing to escape into.
-- 2.6, up from 1.8, because at 1.8 the rays on a card were barely there. More
-- zoom shows LESS of the source and more of each ray: the burst's spokes converge
-- toward its middle, so magnifying it makes the few that remain in frame wider and
-- longer instead of packing more of them into the card. The plate below passes its
-- own figure and is unaffected.
local RAYS_ZOOM = 2.6

local function rays(obj, grad, cornerScale, cx, cy, zoom)
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
	-- Fit, on a box that fit() keeps SQUARE, so the burst stays circular. Crop would
	-- fill a non-square box and stretch the rays along its wider axis.
	im.ScaleType = Enum.ScaleType.Fit
	im.ZIndex = obj.ZIndex
	-- Deliberately NO bevel() here. The source is white, and white multiplied by the
	-- element's own ramp is exactly the element's own colour — the rays would vanish
	-- into it. The card underneath carries the hue; this only lightens.
	im.Parent = clip

	-- No UICorner on the clip: it would not clip anything. The inset IS the
	-- mechanism, and it is recomputed whenever the element resizes, because the
	-- radius it comes from is a fraction of the element's own shorter side — which
	-- changes on every relayout and on every hover pop.
	--
	-- The burst box is sized here too, SQUARE and in PIXELS off the clip's LONGER
	-- axis. It used to be UDim2.fromScale(RAYS_ZOOM, RAYS_ZOOM), which is fine on a
	-- near-square card and throws the zoom away on the 2.5:1 offer plate: Fit takes
	-- the SMALLER side of the box, so a 721x273 clip at zoom 1.8 gave a 1298x491 box
	-- and only a 491px circle. Aimed at the egg 631px from the far edge, a 245px
	-- radius stopped dead in open plate on one side and was sliced flat by the border
	-- on the other — rays ending in a mid-air arc and in a straight cut, which is
	-- what "cuts off weird" looks like. Square off the longer axis gives a 1298px
	-- circle, radius 649, clearing the 631 it has to reach and bleeding off every
	-- edge the way it always did on a card.
	local function fit()
		local sz = obj.AbsoluteSize
		local d = RAYS_INSET * (cornerScale or 0.18) * math.min(sz.X, sz.Y)
		clip.Size = UDim2.new(1, -d * 2, 1, -d * 2)
		local s = math.max(1, math.floor((zoom or RAYS_ZOOM) * math.max(sz.X, sz.Y)))
		im.Size = UDim2.fromOffset(s, s)
	end
	obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

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
local function halftone(obj, cornerScale, strength, tileFrac)
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
	if tileFrac then
		-- TILED, because this element is WIDER than the source is big. Crop scales a
		-- square source to COVER, so on the 745x297 offer plate the 512px sheet is
		-- blown up to 1.46x and its dots stop being a tone and become spots — the one
		-- element in the shop where that happens, which is why it is the only one
		-- asking for this. A 272px card DOWNscales the same sheet to 0.53x and is
		-- fine on Crop. Tiling redraws the source at a chosen pitch instead of
		-- stretching it once, so the dots come back to native resolution or finer.
		-- This sheet tiles without a visible seam; checked on the plate at 100 and
		-- 150 before settling.
		im.ScaleType = Enum.ScaleType.Tile
		-- A FIXED pixel pitch would hold on this monitor and give under three dots
		-- across a phone-sized plate, so the pitch comes off cellH in the layout pass
		-- like every other size in this file. Square in PIXELS, which is why it is one
		-- number and not a UDim2 scale: scale is taken per-axis, of a box that is not
		-- square, and the dots would come out elliptical.
		table.insert(hooks, function()
			local s = math.max(8, math.floor(cellH * tileFrac))
			im.TileSize = UDim2.fromOffset(s, s)
		end)
	else
		-- Crop, not Fit: Fit letterboxes a square source inside a wide element and
		-- leaves the dots floating in a band with bare gradient either side of them.
		im.ScaleType = Enum.ScaleType.Crop
	end
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

-- The Robux mark, drawn the one way the whole shop draws it: WHITE with a stamped
-- ink contour, so it matches the price number beside it, which is always white with
-- a heavy ink outline. Card prices and the feature banner used to draw a bare BLACK
-- mark instead; on a gold or cyan card that put a dark glyph next to a light number
-- and the two stopped reading as one price.
--
-- STAMPED, not stroked. A UIStroke on an ImageLabel outlines the LABEL'S RECTANGLE,
-- not the glyph — it draws a box round the coin. Four ink copies offset one step on
-- each axis, behind a white one, give a real contour, the same answer the pets reach
-- for the same reason. They live in a holder so a list layout still sees one item.
--
-- Returns the holder. The caller owns Name, LayoutOrder, Size and Parent; the holder
-- is kept square by its own constraint, which only ever SHRINKS, so give it a
-- generous size on both axes or it renders nothing.
local MARK_STAMP = 0.09     -- of the mark's own box, per axis
local function robuxMark(z)
	local holder = Instance.new("Frame")
	holder.Name = "RobuxMark"
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	local hr = Instance.new("UIAspectRatioConstraint")
	hr.AspectRatio = 1
	hr.Parent = holder

	for _, dir in ipairs({ Vector2.new(1, 0), Vector2.new(-1, 0),
	                       Vector2.new(0, 1), Vector2.new(0, -1) }) do
		local e = Instance.new("ImageLabel")
		e.Name = "Edge"
		e.BackgroundTransparency = 1
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromScale(0.5 + dir.X * MARK_STAMP, 0.5 + dir.Y * MARK_STAMP)
		e.Size = UDim2.fromScale(1, 1)
		e.Image = SHOP.PriceIcon
		-- ImageColor3 MULTIPLIES, so a white source takes the ink cleanly and the
		-- transparent square stays punched through it.
		e.ImageColor3 = P.Ink
		e.ScaleType = Enum.ScaleType.Fit
		e.ZIndex = z
		e.Parent = holder
	end

	local m = Instance.new("ImageLabel")
	m.Name = "RobuxIcon"
	m.BackgroundTransparency = 1
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = UDim2.fromScale(0.5, 0.5)
	m.Size = UDim2.fromScale(1, 1)
	m.Image = SHOP.PriceIcon
	m.ImageColor3 = WHITE
	m.ScaleType = Enum.ScaleType.Fit
	m.ZIndex = z + 1
	m.Parent = holder

	return holder
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

-- A light rim INSIDE the ink border — the same two-line edge the panel itself
-- carries, and the thing that makes a big plate read as moulded rather than as a
-- flat rectangle with a line round it. An instance holds only ONE UIStroke, and
-- the element's is already the ink border, so the highlight has to be its own
-- inset frame. Topmost ZIndex on its host: a rim that anything can draw over is
-- not a rim.
local function rim(obj, cornerScale, z, inset)
	local r = Instance.new("Frame")
	r.Name = "Rim"
	r.BackgroundTransparency = 1
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.new(1, -(inset or 7), 1, -(inset or 7))
	r.ZIndex = z
	corner(r, cornerScale)
	stroke(r, WHITE, 2).Transparency = 0.6
	r.Parent = obj
	return r
end

-- castShadow parents the shadow INSIDE its element, which is right for a card —
-- the shadow then inherits the hover pop and grows with it — and useless for the
-- feature banner and the offer plate. Both of those ClipsDescendants, because their
-- burst and halftone are square sheets that would otherwise show their corners
-- outside the radius, so a child offset below the bottom edge is clipped away
-- entirely. The answer is a transparent slot around the element, exactly its size,
-- holding the shadow. The slot takes over the element's place in the list layout,
-- so whatever sized the element now sizes the slot.
local function shadowSlot(obj, drop, cornerScale, z, strength)
	local slot = Instance.new("Frame")
	slot.Name = obj.Name .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Size = obj.Size
	slot.LayoutOrder = obj.LayoutOrder
	slot.ZIndex = obj.ZIndex
	castShadow(slot, drop, cornerScale, z, strength)
	obj.Size = UDim2.fromScale(1, 1)
	obj.Position = UDim2.fromScale(0.5, 0.5)
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Parent = slot
	return slot
end

-- Every green Robux pill in the shop — the feature banner's and the offer's three
-- quantity tiers — gets this and nothing else does. They were bevelled plates with
-- a border and no sheen, no ground and no response to being pointed at, which is
-- the wrong way round for the one thing on a surface you are being asked to press.
--
-- Cards already pop on hover; these pop with them AND brighten, because a pill is
-- small enough that a 5% scale on its own barely registers — the colour change is
-- what actually reads at pill size. The press dips below rest rather than just
-- returning to it, so a click lands even when the pointer never moves.
--
-- Returns a transparent CONTENT frame filling the pill, and the caller must put the
-- mark and the number in THAT, not in the pill. Both pills arrange their contents
-- with a UIListLayout, and a UIListLayout lays out every GuiObject child it has —
-- so a gloss sheet and a cast shadow parented straight onto the pill become two
-- more items in the row and shove the price off the end of it.
local PILL_LIFT = 0.16    -- how far the hover colour travels toward white
local function pillFeel(pill, base, cornerScale)
	gloss(pill, 0.5, cornerScale, 0.6)
	castShadow(pill, 0.07, cornerScale, pill.ZIndex - 1, 0.55)

	local pop = Instance.new("UIScale")
	pop.Parent = pill
	local hot = base:Lerp(WHITE, PILL_LIFT)

	audible(pill)
	pill.MouseEnter:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1.07 }):Play()
		TweenService:Create(pill, TweenInfo.new(0.12), { BackgroundColor3 = hot }):Play()
	end)
	pill.MouseLeave:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 1 }):Play()
		TweenService:Create(pill, TweenInfo.new(0.16), { BackgroundColor3 = base }):Play()
	end)
	pill.MouseButton1Down:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	pill.MouseButton1Click:Connect(function()
		TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1.07 }):Play()
		-- Every buy control in this panel comes through here — the feature banner's
		-- pill and all three tier pills — so the chime is wired once rather than at
		-- four call sites that would drift.
		SFX_REWARD:Play()
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = pill.ZIndex + 1
	content.Parent = pill
	return content
end

------------------------------------------------------------------------- panel
panel.BackgroundColor3 = P.Panel
panel.Size = UDim2.fromScale(0.72, 0.65)
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
	-- The same moulded edge the offer plate and the panel itself carry. The banner
	-- was the only large plate in the shop drawn with a single flat ink line.
	rim(banner, 0.14, 58)
	-- Every card casts a shadow and the two biggest surfaces in the panel cast none,
	-- so they sat flat on the white while the small things floated over it. Shallower
	-- drop than a card's: these are full-width, and a card's 0.045 of a much shorter
	-- box is a far smaller shadow in pixels than the same fraction of this one.
	local bannerSlot = shadowSlot(banner, 0.028, 0.14, 52, 0.55)
	bannerSlot.Parent = scroll

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
		-- A TextButton, not a Frame. It was the one thing on the banner you are being
		-- asked to press and the only unpressable green plate in the panel — no hover,
		-- no sound, no dip. NOT_WIRED like every other price here: there is no remote
		-- and no product id, so the button is the feel and nothing else.
		local pp = Instance.new("TextButton")
		pp.Name = "FeaturePrice"
		pp.Text = ""
		pp.AutoButtonColor = false
		pp.AnchorPoint = Vector2.new(1, 0.5)
		pp.Position = UDim2.fromScale(0.975, 0.5)
		pp.Size = UDim2.fromScale(0.16, 0.38)
		pp.BackgroundColor3 = P.Green[1]
		pp.BorderSizePixel = 0
		pp.ZIndex = 55
		corner(pp, 0.4)
		stroke(pp, P.Ink, 2.4)
		bevel(pp, P.Green)
		local ppc = pillFeel(pp, P.Green[1], 0.4)

		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0.04, 0)
		lay.Parent = ppc

		if SHOP.PriceIcon then
			local m = robuxMark(56)
			m.LayoutOrder = 1
			-- Generous width, squared off the pill's height by the constraint — which
			-- only ever shrinks, so a zero width would render nothing at all.
			m.Size = UDim2.fromScale(0.4, 0.74)
			m.Parent = ppc
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
		pl.Parent = ppc

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
		-- The SLOT, not the banner: the banner now fills its slot at scale 1,1 so the
		-- shadow outside the banner's own clip region tracks it.
		bannerSlot.Size = UDim2.new(1, 0, 0, math.max(1, cellH * FEATURE_H))
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
	-- The card is still inert as a PURCHASE. It is not inert as a press: the chime
	-- says the game heard you, which is the one thing a dead button owes the
	-- player until there is a remote behind it.
	SFX_REWARD:Play()
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

		-- The amount, ON the art. A coin pack's whole proposition is the number,
		-- and until now it lived only in the blurb — a line of 12px body copy
		-- beside the picture, which is the one place a player scanning a shelf
		-- does not look. Yellow outlined text with nothing behind it, the same
		-- treatment ribbons and tags get here and quantities get on the daily
		-- cards: a bordered pill would put a second button-shaped thing on a card
		-- that is already a button.
		--
		-- Low and slightly right of the icon's centre, so it overlaps the art's
		-- lower edge rather than its middle, where it would cover the coin faces
		-- that make the icon legible at all.
		--
		-- ON the icon, NOT under it. The card's body band is 0.28 .. 0.72 and the
		-- price row starts at 0.70 on a card that carries a tag — so a quantity
		-- hung below the art lands exactly on top of the price, which is what the
		-- first pass did: "6,000" and the Robux figure printed through each other.
		-- The art is a coin pile with room at its foot; the number goes there.
		if item.Qty then
			local qty = tag("Qty", item.Qty, 57)
			qty.AnchorPoint = Vector2.new(0.5, 0.5)
			qty.Position = UDim2.fromScale(ICON_X + 0.055, ICON_Y + 0.125)
			qty.Size = UDim2.fromScale(0.36, 0.125)
			capText(qty, 0.115)
			qty.Parent = card
		end
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
		-- Sized in the layout pass off the price's own TextSize rather than fitted to
		-- the row's height, so the mark tracks the number at every card size.
		mark = robuxMark(56)
		mark.LayoutOrder = 1
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
local function makeHeader(section, order, gap)
	local row = Instance.new("Frame")
	row.Name = section.Name .. "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 1)
	row.LayoutOrder = order
	row.ZIndex = 53

	local inner = Instance.new("UIListLayout")
	inner.FillDirection = Enum.FillDirection.Horizontal
	inner.HorizontalAlignment = Enum.HorizontalAlignment.Center
	-- Bottom, when there is a gap: the row is taller than the title band and the
	-- extra height is meant to be empty space ABOVE the title, not around it.
	inner.VerticalAlignment = gap and Enum.VerticalAlignment.Bottom
	                              or Enum.VerticalAlignment.Center
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
	-- Height resolved in the layout pass, not 1,0: on a gapped header the row is
	-- taller than the title band and a full-height label would centre its text in
	-- the whole thing, splitting the gap above and below instead of stacking it on
	-- top.
	label.Size = UDim2.new(0, 0, 0, 1)
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
		row.Size = UDim2.new(1, 0, 0, h + (gap and math.floor(cellH * SECTION_GAP) or 0))
		label.Size = UDim2.new(0, 0, 0, h)
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

------------------------------------------------------------------------ offer
-- The egg offer: one wide plate carrying four things no card carries at once —
-- a title, a rarity flag, a strip of hatch odds and a row of quantity tiers.
-- Every position below is a fraction of the plate, so the relayout that resizes
-- every other row resizes this one too and nothing has to be restated in pixels.
local OFFER_H = 1.36        -- of card height. The feature banner is 0.62; this
                            -- stacks odds OVER tiers, and at 0.95 the plate came
                            -- out 3.6:1 and squashed each pet into a 37px sliver.

-- ponytail: third copy of the pet-viewport builder — InventoryController and
-- IndexController hold the other two. It belongs in UIKit; factor all three out
-- when one of them next needs a real change, not today for five pets.
local PET_MODELS = ReplicatedStorage:FindFirstChild(
	require(ReplicatedStorage:WaitForChild("GameConfig")).Inventory.PetModelFolder)
local PET_VIEW_DIR = Vector3.new(-0.30, 0.16, -1).Unit
local PET_FOV, PET_PAD = 30, 1.12
local PET_AMBIENT = Color3.fromRGB(235, 235, 235)
-- STAMPED, not scaled. Scaling a dark copy up behind the pet offsets every edge
-- radially from the image centre, so the contour is fat far from centre, absent
-- near it, and shows the dark copy's own depth through the gaps. Four flat copies
-- offset one stroke-width on each axis give an even contour that follows the
-- silhouette. Four rather than eight: each one is a whole viewport.
local PET_STROKE_OFFSETS = {
	Vector2.new(1, 0), Vector2.new(-1, 0),
	Vector2.new(0, 1), Vector2.new(0, -1),
}
local PET_STROKE = 0.05                              -- of the drop's own box
local PET_STROKE_COLOUR = Color3.fromRGB(28, 28, 40)

-- `flat` paints every part one colour and kills the directional light, which is
-- what turns a pass into a silhouette.
local function petViewport(drop, z, flat)
	local source = PET_MODELS and PET_MODELS:FindFirstChild(drop.Model or "")
	if not source then return nil end

	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.ZIndex = z
	-- A viewport ignores the place's Lighting and starts near black. The flat pass
	-- wants NO directional light or the silhouette comes out shaded and stops
	-- reading as one solid shape.
	vp.Ambient = flat and Color3.new(1, 1, 1) or PET_AMBIENT
	vp.LightColor = flat and Color3.new(0, 0, 0) or WHITE
	vp.LightDirection = Vector3.new(-0.5, -1, -0.5)

	local model = source:Clone()
	if flat then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				-- A UnionOperation IGNORES .Color unless UsePartColor is set: it
				-- renders the colours of the parts it was built from. Every face on
				-- these pets is a union, so without this the silhouettes stare back.
				if d:IsA("UnionOperation") then d.UsePartColor = true end
				d.Color = flat
				d.Material = Enum.Material.SmoothPlastic
				if d:IsA("MeshPart") then d.TextureID = "" end
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			elseif d:IsA("SurfaceAppearance") then
				-- Clearing TextureID is not enough on its own: a SurfaceAppearance
				-- overrides it and keeps drawing the face on a flat silhouette.
				d:Destroy()
			end
		end
	end
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = PET_FOV
	-- Framed off the world-space bounding box. Do NOT PivotTo a staged model:
	-- resetting the pivot tips upright rigs onto their backs.
	local centre, size = model:GetBoundingBox()
	-- Longest axis, not the diagonal: the diagonal frames a sphere the pet never
	-- fills and renders it at a third of its cell.
	local radius = math.max(size.X, size.Y, size.Z) / 2
	local dist = (radius * PET_PAD) / math.tan(math.rad(PET_FOV / 2))
	local dir = PET_VIEW_DIR
	if drop.Yaw then dir = CFrame.Angles(0, math.rad(drop.Yaw), 0) * dir end
	cam.CFrame = CFrame.lookAt(centre.Position + dir * dist, centre.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- Glints: a handful of four-pointed stars that fade in somewhere inside the
-- element, fade out, and move before they come back. A fixed few read as many
-- because each one picks a new spot every cycle, which is far cheaper than a
-- particle emitter and is the whole effect at this size.
-- ponytail: one task per glint, looping for the life of the panel. Six of them is
-- nothing; if glints ever go on every card, drive them all from one heartbeat.
local GLINT = "\u{2726}"
local function glitter(parent, count, z, tint)
	for i = 1, count do
		local g = Instance.new("TextLabel")
		g.Name = "Glint" .. i
		g.BackgroundTransparency = 1
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Square, via the constraint, because the parents are not: on the egg's tall
		-- box a 0.1x0.26 glint came out 15x54 and TextScaled drew a 15px star in it.
		-- The constraint only ever SHRINKS, so both scales have to be generous.
		g.Size = UDim2.fromScale(0.3, 0.3)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = g
		g.Text = GLINT
		g.TextColor3 = tint or WHITE
		g.FontFace = FONT
		g.TextScaled = true
		g.TextTransparency = 1
		g.ZIndex = z
		g.Parent = parent

		task.spawn(function()
			-- Stagger the first appearance or all of them blink in unison.
			task.wait(math.random(0, 220) / 100)
			while g.Parent do
				-- Nothing to draw while the shop is shut, and the tweens would run
				-- all session for a panel nobody is looking at.
				if panel.Visible then
					g.Position = UDim2.fromScale(0.06 + math.random() * 0.88,
					                             0.12 + math.random() * 0.76)
					g.Rotation = math.random(-40, 40)
					local up = TweenService:Create(g,
						TweenInfo.new(0.38, Enum.EasingStyle.Quad), { TextTransparency = 0.1 })
					local down = TweenService:Create(g,
						TweenInfo.new(0.46, Enum.EasingStyle.Quad), { TextTransparency = 1 })
					up:Play(); up.Completed:Wait()
					down:Play(); down.Completed:Wait()
				end
				task.wait(math.random(70, 260) / 100)
			end
		end)
	end
end

local offer = SHOP.Offer
if offer then
	local plate = Instance.new("Frame")
	plate.Name = "Offer"
	plate.BackgroundColor3 = offer.Grad[1]
	plate.BorderSizePixel = 0
	plate.Size = UDim2.new(1, 0, 0, 1)
	plate.LayoutOrder = 3
	plate.ZIndex = 53
	-- Same reasoning as the feature banner: UICorner scale is of the SHORTER side,
	-- and this plate is far wider than it is tall, so the card radius would round
	-- the ends into a lozenge.
	corner(plate, 0.12)
	-- Clipped for the same reason the banner is: the burst and the halftone are
	-- square sheets that would otherwise show their corners outside the radius.
	-- The egg is the one thing meant to reach the edge, so it sits inside.
	plate.ClipsDescendants = true
	stroke(plate, P.Ink, 3)
	bevel(plate, offer.Grad)
	rim(plate, 0.12, 58)
	-- Centred on the EGG, not on the odds strip: the egg is what the burst is
	-- behind, and a burst whose centre sits off the object it lights reads as a
	-- second light source. The egg's own centre is its right edge less half its
	-- width, so these two numbers track the egg's placement below.
	-- Zoomed past the shop-wide 1.8. At 1.8 the burst exactly reaches the plate's far
	-- edge and no further, so its outer ring sits right on the border; a little more
	-- puts the whole fade off-plate and reads as a bigger, softer glow behind the egg.
	rays(plate, offer.Grad, 0.12, 0.875, 0.56, 2.15)
	-- Tiled, unlike every other halftone in the shop. See halftone(): this plate is
	-- the only element wide enough to magnify the 512px sheet. 0.69 of cellH lands
	-- on a ~150px pitch at the size it ships at, which was picked on the real plate
	-- rather than on a probe — at 100 the dots wash out into a flat haze.
	halftone(plate, 0.12, 0.88, 0.69)
	gloss(plate, 0.5, 0.22, 0.66)

	-- The egg, big on the right end, and the only element allowed to crowd the
	-- edge. Fit rather than Crop: the plate's box is nothing like square and Crop
	-- would fill it with a stretched ellipse of an egg.
	if offer.Egg then
		local egg = Instance.new("ImageLabel")
		egg.Name = "Egg"
		egg.BackgroundTransparency = 1
		egg.AnchorPoint = Vector2.new(1, 0.5)
		egg.Position = UDim2.fromScale(0.980, 0.56)
		-- Generous on both axes with a square constraint, which only ever SHRINKS:
		-- the egg then gets the largest square the plate's height allows instead of
		-- being boxed into the plate's own oblong aspect.
		egg.Size = UDim2.fromScale(0.28, 0.93)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = egg
		egg.Image = offer.Egg
		-- NO stamped contour, unlike the pets and the Robux mark. This artwork ships
		-- its OWN heavy dark outline and its own highlights (that is the whole reason
		-- to prefer it to the plain white egg that was here), so stamping four ink
		-- copies behind it only thickens and softens an outline that is already
		-- drawn. A UIStroke is wrong here for the usual reason — it outlines the
		-- ImageLabel's rectangle, not the egg.
		--
		-- ImageColor3 MULTIPLIES. The source is a cream egg, and the tint is what
		-- makes it the galaxy egg the offer is named after; the artwork's own black
		-- outline is what keeps it separate from the violet plate, so the tint is
		-- free to sit close to the plate's own hue.
		if offer.EggTint then egg.ImageColor3 = offer.EggTint end
		egg.ScaleType = Enum.ScaleType.Fit
		egg.ZIndex = 55
		egg.Parent = plate
		-- On the egg rather than on the plate, so they follow it and stay off the
		-- odds strip where they would read as another rarity pip. Yellow, not white:
		-- white glints sit directly on the white burst behind the egg and vanish.
		glitter(egg, 3, 57, P.Tag)
	end

	-- Title over the left three quarters, clear of the egg.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.40, 0.03)
	title.Size = UDim2.fromScale(0.60, 0.20)
	title.Text = offer.Title or ""
	-- White on ink, like every heading in the panel. Yellow is the flag's colour
	-- and using it here would put two yellow call-outs on one plate.
	title.TextColor3 = WHITE
	title.FontFace = FONT
	title.TextScaled = true
	title.ZIndex = 56
	outline(title, 3)
	title.Parent = plate
	glitter(title, 3, 57, P.Tag)

	-- The flag, top-right, above the egg rather than beside it.
	if offer.Flag then
		local flag = tag("Flag", offer.Flag, 56)
		flag.AnchorPoint = Vector2.new(1, 0)
		flag.Position = UDim2.fromScale(0.975, 0.045)
		flag.Size = UDim2.fromScale(0.26, 0.13)
		flag.Parent = plate
	end

	-- The odds strip. Each drop is a column: pips, then the pet, then its chance.
	if offer.Drops and #offer.Drops > 0 then
		local strip = Instance.new("Frame")
		strip.Name = "Drops"
		strip.BackgroundTransparency = 1
		strip.AnchorPoint = Vector2.new(0, 0.5)
		strip.Position = UDim2.fromScale(0.035, 0.42)
		strip.Size = UDim2.fromScale(0.70, 0.42)
		strip.ZIndex = 55
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Left
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Parent = strip

		for i, drop in ipairs(offer.Drops) do
			local col = Instance.new("Frame")
			col.Name = "Drop" .. i
			col.BackgroundTransparency = 1
			col.LayoutOrder = i
			col.Size = UDim2.fromScale(1 / #offer.Drops, 1)
			col.ZIndex = 55

			local pips = Instance.new("TextLabel")
			pips.Name = "Pips"
			pips.BackgroundTransparency = 1
			pips.AnchorPoint = Vector2.new(0.5, 0)
			pips.Position = UDim2.fromScale(0.5, 0)
			pips.Size = UDim2.fromScale(0.92, 0.17)
			pips.Text = string.rep("\u{2605}", drop.Stars or 1)
			pips.TextColor3 = P.Tag
			pips.FontFace = FONT
			pips.TextScaled = true
			pips.ZIndex = 56
			outline(pips, 2)
			pips.Parent = col

			-- The pet itself: the real rig in a viewport, the same answer the
			-- inventory and the index give. A drop with no model falls back to a
			-- flat Icon, and one with neither simply shows its odds.
			-- The pet and its contour. Four flat copies behind the real pass, the
			-- same answer the inventory reached: a Highlight does not render inside
			-- a ViewportFrame at all, and a UIStroke would outline the rectangle.
			local art = nil
			local source = PET_MODELS and PET_MODELS:FindFirstChild(drop.Model or "")
			if source then
				art = Instance.new("Frame")
				art.BackgroundTransparency = 1
				for k, dir in ipairs(PET_STROKE_OFFSETS) do
					local edge = petViewport(drop, 55, PET_STROKE_COLOUR)
					edge.Name = "Stroke" .. k
					edge.AnchorPoint = Vector2.new(0.5, 0.5)
					edge.Position = UDim2.fromScale(0.5 + dir.X * PET_STROKE,
					                                0.5 + dir.Y * PET_STROKE)
					edge.Parent = art
				end
				local body = petViewport(drop, 56)
				body.Name = "Body"
				body.AnchorPoint = Vector2.new(0.5, 0.5)
				body.Position = UDim2.fromScale(0.5, 0.5)
				body.Parent = art
			end
			if not art and drop.Icon then
				art = Instance.new("ImageLabel")
				art.BackgroundTransparency = 1
				art.Image = drop.Icon
				art.ScaleType = Enum.ScaleType.Fit
				art.ZIndex = 56
			end
			if art then
				art.Name = "Art"
				art.AnchorPoint = Vector2.new(0.5, 0.5)
				art.Position = UDim2.fromScale(0.5, 0.51)
				art.Size = UDim2.fromScale(0.94, 0.62)
				art.Parent = col
			end

			local pct = Instance.new("TextLabel")
			pct.Name = "Pct"
			pct.BackgroundTransparency = 1
			pct.AnchorPoint = Vector2.new(0.5, 1)
			-- Right of centre, as the reference has it: the number sits under the
			-- pet's body rather than under the whole cell, and the cell is wider
			-- than the pet.
			pct.Position = UDim2.fromScale(0.58, 1)
			pct.Size = UDim2.fromScale(0.92, 0.20)
			pct.Text = drop.Pct or ""
			pct.TextColor3 = WHITE
			pct.FontFace = FONT
			pct.TextScaled = true
			pct.ZIndex = 56
			outline(pct, 2.2)
			pct.Parent = col

			col.Parent = strip
		end
		strip.Parent = plate
	end

	-- The quantity ladder along the bottom. Each tier is its own column: the count
	-- above, a green pill under it, and the saving under that on the tier that has
	-- one. Green because the feature banner already establishes green as the thing
	-- you press.
	if offer.Tiers and #offer.Tiers > 0 then
		local tiers = Instance.new("Frame")
		tiers.Name = "Tiers"
		tiers.BackgroundTransparency = 1
		tiers.AnchorPoint = Vector2.new(0, 1)
		-- 0.93, not 0.955. The bulk tier's saving hangs BELOW its pill, and at 0.955
		-- that line sat on the plate's rim with its descenders touching it.
		tiers.Position = UDim2.fromScale(0.035, 0.93)
		tiers.Size = UDim2.fromScale(0.66, 0.28)
		tiers.ZIndex = 55
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.HorizontalAlignment = Enum.HorizontalAlignment.Left
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Padding = UDim.new(0.03, 0)
		row.Parent = tiers

		for i, tier in ipairs(offer.Tiers) do
			local col = Instance.new("Frame")
			col.Name = "Tier" .. i
			col.BackgroundTransparency = 1
			col.LayoutOrder = i
			col.Size = UDim2.fromScale(0.31, 1)
			col.ZIndex = 55

			local count = Instance.new("TextLabel")
			count.Name = "Count"
			count.BackgroundTransparency = 1
			count.AnchorPoint = Vector2.new(0.5, 0)
			count.Position = UDim2.fromScale(0.5, 0)
			count.Size = UDim2.fromScale(1, 0.30)
			count.Text = tier.Label or ""
			count.TextColor3 = WHITE
			count.FontFace = FONT
			count.TextScaled = true
			count.ZIndex = 56
			outline(count, 2)
			count.Parent = col

			-- NOT_WIRED, same as every card: no remote, no product id, so the pill
			-- is a TextButton for the hover and the click sound and nothing else.
			local pill = Instance.new("TextButton")
			pill.Name = "Buy"
			pill.Text = ""
			pill.AutoButtonColor = false
			pill.AnchorPoint = Vector2.new(0.5, 0.5)
			-- 0.55, not 0.50. The pill and the caption share ZIndex 56 and the pill
			-- is built second, so wherever they overlap the pill wins — at 0.50 its
			-- top edge cut the descenders off the caption and "x1 Egg" rendered as
			-- "x1 Eaa". The caption ends at 0.30; this starts at 0.34.
			pill.Position = UDim2.fromScale(0.5, 0.55)
			pill.Size = UDim2.fromScale(1, 0.42)
			pill.BackgroundColor3 = P.Green[1]
			pill.BorderSizePixel = 0
			pill.ZIndex = 56
			-- 0.22, not the 0.4 the feature banner's pill uses: the reference's
			-- quantity buttons are rounded rectangles, not lozenges, and three of
			-- them in a row at 0.4 read as a row of capsules.
			corner(pill, 0.22)
			stroke(pill, P.Ink, 2.4)
			bevel(pill, P.Green)
			-- Sheen, ground and hover, the same as the banner's pill. audible() comes
			-- with it; it used to be the ONLY thing these three had.
			local pc = pillFeel(pill, P.Green[1], 0.22)

			local lay = Instance.new("UIListLayout")
			lay.FillDirection = Enum.FillDirection.Horizontal
			lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
			lay.VerticalAlignment = Enum.VerticalAlignment.Center
			lay.SortOrder = Enum.SortOrder.LayoutOrder
			lay.Padding = UDim.new(0.04, 0)
			lay.Parent = pc

			local plabel = Instance.new("TextLabel")
			plabel.Name = "Label"
			plabel.BackgroundTransparency = 1
			-- Mark first, then the number — the order the cards and the feature
			-- banner use. These three were the only prices in the shop reading the
			-- other way round, and with the marks now identical everywhere the
			-- mirrored order was the only thing left making them look different.
			plabel.LayoutOrder = 2
			plabel.Size = UDim2.fromScale(0.52, 0.62)
			plabel.Text = tier.Price or ""
			plabel.TextColor3 = WHITE
			plabel.FontFace = FONT
			plabel.TextScaled = true
			plabel.ZIndex = 57
			outline(plabel, 2.2)
			plabel.Parent = pc

			if SHOP.PriceIcon then
				local m = robuxMark(57)
				m.LayoutOrder = 1
				-- Generous width, squared off the pill's height by the constraint,
				-- which only ever SHRINKS — a zero width renders nothing at all.
				m.Size = UDim2.fromScale(0.4, 0.66)
				m.Parent = pc
			end

			pill.Parent = col

			if tier.Off then
				local off = Instance.new("TextLabel")
				off.Name = "Off"
				off.BackgroundTransparency = 1
				off.AnchorPoint = Vector2.new(0.5, 1)
				off.Position = UDim2.fromScale(0.5, 1)
				off.Size = UDim2.fromScale(1, 0.22)
				off.Text = tier.Off
				off.TextColor3 = P.Close
				off.FontFace = FONT
				off.TextScaled = true
				off.ZIndex = 57
				outline(off, 1.8)
				off.Parent = col
			end

			col.Parent = tiers
		end
		tiers.Parent = plate
	end

	if offer.Header then
		makeHeader({ Name = "Offer", Header = offer.Header }, 2).Parent = scroll
	end
	-- As the banner: the plate clips, so its shadow has to live in a slot around it.
	local plateSlot = shadowSlot(plate, 0.028, 0.12, 52, 0.55)
	plateSlot.Parent = scroll

	table.insert(hooks, function()
		plateSlot.Size = UDim2.new(1, 0, 0, math.max(1, cellH * OFFER_H))
	end)
end

for i, section in ipairs(SHOP.Sections) do
	-- Gap above every shelf title. Not the first: it already follows the offer
	-- header, which is the top of the scroll.
	makeHeader(section, i * 10, i > 1).Parent = scroll
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

