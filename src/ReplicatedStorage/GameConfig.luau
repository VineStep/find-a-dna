--[[
	GameConfig — every tunable number in the game.

	Retro-slop: Pet Simulator x Grow a Garden.
	Plant -> crops grow on a timer (offline too) -> harvest -> currency
	-> eggs -> pets boost yield -> rebirth multiplies everything.

	Owned by rblx-orchestrator. Other agents read; they do not edit.
]]

-- Pet Simulator 99 shop palette. Every colour the shop draws comes from here, so
-- the whole thing can be re-tinted without touching ShopController.
local INK        = Color3.fromRGB( 20,  28,  58)  -- every stroke, everywhere
local PANEL      = Color3.fromRGB(253, 253, 253)  -- the near-white panel body
local BODY_TEXT  = Color3.fromRGB( 26,  38,  72)  -- descriptions, section headers
local CLOSE_RED  = Color3.fromRGB(242,  63,  90)
local CLOSE_DEEP = Color3.fromRGB(198,  24,  54)

-- Ribbons ("NEW!", "BEST!") and the line under a price ("Popular", "+10% Bonus")
-- are TEXT, not plates. As bordered pills they read as two more buttons stacked on
-- a card that is itself a button, which is three things to press and only one that
-- does anything. Bright yellow with a heavy ink outline is what the reference draws
-- and it holds on all five card gradients.
local TAG = Color3.fromRGB(255, 221,  74)

-- Card gradients: pale at the top, saturated at the bottom, always. A card that
-- is flat or dark-topped stops reading as the same family.
local GOLD   = { Color3.fromRGB(255, 214,  92), Color3.fromRGB(250, 160,  30) }
local PINK   = { Color3.fromRGB(255, 176, 214), Color3.fromRGB(236,  74, 140) }
local VIOLET = { Color3.fromRGB(198, 168, 255), Color3.fromRGB(138,  92, 232) }
local GREEN  = { Color3.fromRGB(160, 232, 120), Color3.fromRGB( 74, 180,  70) }
local CYAN   = { Color3.fromRGB(168, 230, 255), Color3.fromRGB( 74, 176, 232) }

-- The Robux mark, drawn instead of an "R$" prefix, and tinted black by the shop.
-- This is the THICK-ringed cut of the glyph: the number beside it is drawn with a
-- heavy outline, and the thinner cut read light next to it at any size. Outlining
-- the mark to compensate was tried and is wrong — a UIStroke rounds the hexagon's
-- corners into a blob and reads as a border around the icon rather than as a
-- heavier icon. Store page 11713337409 is a Decal wrapper; this is the texture
-- inside it, per the Icon note below.
local ROBUX = "rbxassetid://11713337390"

return {
	Sprint = {
		BaseWalkSpeed = 16,
		SprintWalkSpeed = 28,
		MaxStamina = 100,
		DrainPerSecond = 22,
		RegenPerSecond = 16,
		RegenDelay = 0.8,   -- seconds after sprint stops before regen starts
	},

	-- The shop is ONE scrolling list: feature banner, then section header + 3-wide
	-- grid, repeated. There are no tabs. Adding a product is an edit here, never a
	-- GUI edit — append to a section's Items and it appears.
	--
	-- Nothing is wired to a purchase: no remote, no MarketplaceService call, no
	-- DevProduct or pass ids. Price is display text until those exist.
	--
	-- Icon is the IMAGE id, not the Creator Store id. A store page for artwork
	-- serves a Decal that wraps the image, and ImageLabel.Image needs the id
	-- inside the wrapper — setting it to the store id yields AssetFetchStatus
	-- .Failure. Resolve a new one with InsertService:LoadAsset(storeId) and read
	-- the Decal's .Texture. Every id below is a free Creator Store asset already
	-- verified to preload Success in this group-owned place; images uploaded by
	-- the signed-in user do NOT work here, so reuse these before hunting new ones.
	--
	-- Per item: Grad is the card's vertical gradient pair {top, bottom}; Ribbon is
	-- a line of type that floats ABOVE the card on the panel background; Tag is a
	-- line BELOW the price. Both are drawn as yellow outlined text with nothing
	-- behind them. Both are optional and a card without them is a plain card on
	-- purpose — if every product shouts, none of them do.
	Shop = {
		Palette = {
			Ink = INK, Panel = PANEL, BodyText = BODY_TEXT,
			Close = CLOSE_RED, CloseDeep = CLOSE_DEEP,
			Gold = GOLD, Pink = PINK, Violet = VIOLET, Green = GREEN, Cyan = CYAN,
			Tag = TAG,
		},

		Title = "Exclusive Shop!",
		-- Overlaps the panel's top-LEFT corner, half outside it. The reference draws a
		-- red shopping basket, and this is that, with a transparent background and the
		-- same heavy dark outline as the card icons. The gift box that was here before
		-- carried an opaque dark backing plate, which over the panel's edge read as a
		-- muddy brown blob rather than an icon.
		TitleIcon = "rbxassetid://16672867186",

		-- There is no header counter. A Robux balance pill sat top-right until it was
		-- cut: it showed a hard-coded 0 because nothing reads the player's balance, and
		-- Roblox already draws the real one in its own topbar a few pixels above it.

		-- Drawn immediately left of every card's price, which is why Price below is a
		-- bare number.
		PriceIcon = ROBUX,

		-- The sunburst behind every card and the feature banner. WHITE RAYS ON A FULLY
		-- TRANSPARENT GROUND, and every property of that matters:
		--
		--   * Transparent ground means the burst ADDS light instead of multiplying the
		--     whole surface. The cream-ground image this replaces darkened everything it
		--     covered, so anywhere it stopped short — the few pixels a clip has to give up
		--     at a rounded corner — came out visibly paler. Nothing to darken, nothing to
		--     miss. It is also why no gradient is applied to it: white multiplied by the
		--     card's own ramp is exactly the card's own colour, i.e. invisible rays.
		--   * No hot centre, so it does not bleach whatever it sits behind.
		--   * The rays fade out before the image's own edge, which is what lets it be
		--     magnified and pushed off-centre onto the product icon at all.
		--
		-- Checked by eye over a saturated ground in Studio, which is the only way to tell:
		-- a Creator Store thumbnail renders an opaque cream ground and a transparent one
		-- identically. Rejected on the same pass: 15308188563 and 136265912903677 (hot
		-- centres), 72870059659250 and 123936208223327 (spikes, not rays), and
		-- 122230714263528 — correct in every structural way but so faint that it was still
		-- invisible on a card at ImageTransparency 0, which is the one fault you cannot
		-- tune your way out of.
		--
		-- Store page 4917649610 ("Shine") is a Decal wrapper; this is its texture.
		Rays = "rbxassetid://4917649592",

		-- The printed-dot pass over every card and the banner: a corner halftone, dots
		-- large at one corner and shrinking to nothing across the element. It is the
		-- texture the genre uses to stop a flat gradient reading as plastic, and it is
		-- the one layer here that is NOT tinted — white dots at low opacity lift the
		-- surface without touching its hue, so the same id works on every colour.
		--
		-- This source is WHITE ON TRANSPARENT, which is what makes it safe. The
		-- alternatives found alongside it (15141325228, 18791544730, 98404664951364)
		-- ship an OPAQUE white or grey ground and paint a square over the card; there is
		-- no way to tell from a Creator Store thumbnail, which renders both the same.
		-- Drawn over a coloured ground in Studio is the only honest check.
		--
		-- Store page 115843222521749 is a Decal wrapper; this is its texture.
		Halftone = "rbxassetid://89854195038597",

		-- BLOCKED, pending one click. Four higher-quality sources were pulled from
		-- ui-resources.com and uploaded, and all four 403 in this place:
		--
		--   107950320583442  card sunburst   (white on transparent, 2215px)
		--   79919458244608   banner sunburst (hard rays + halftone ring, 965px)
		--   136241956798882  corner halftone (895px)
		--   124158131297121  four-point sparkle glint (1080px)
		--
		-- The reason is ownership, not moderation: this experience is GROUP-owned
		-- (game.CreatorType == Group, 155271859) and the upload path signs in as the
		-- USER, so the assets belong to someone the experience has no grant for. Studio's
		-- Output says it exactly — "The experience doesn't have access permission to use
		-- asset id N. Click to share access" — and that link is the whole fix. Do NOT
		-- re-upload; a second copy lands in the same place.
		--
		-- After granting, Studio must be RESTARTED before they will load: ContentProvider
		-- caches the failure for the session and will keep serving it without making a
		-- network request.
		--
		-- The two sunbursts are the reason to bother. Rays above is a cream-GROUND image,
		-- which is why it has to be zoomed past its hot centre and why any hue in it drags
		-- every card; these are white on transparent, so they tint cleanly and need none
		-- of that care.

		-- Cards per row. The reference uses 3; 2 is the other observed value.
		Columns = 3,

		-- First row of the scroll content. It scrolls with the list — it is not
		-- pinned chrome. Omit this table and the banner does not render at all: it
		-- exists to carry a real offer, not to fill the header.
		-- Laid out as the reference's own starter offer: a mascot overhanging the left
		-- end, then a centred stack of title / contents strip / sub-line, then the price
		-- on the right. Tag is NOT drawn on the banner — it is its own centred line
		-- underneath, which is where the reference puts "Top Seller".
		Feature = {
			Title  = "Super Starter Pack!",
			Sub    = "Exclusive Egg included!",
			Tag    = "\u{2b50} Top Seller \u{2b50}",
			Price  = "240",
			Mascot = "rbxassetid://128442519585600",
			-- The contents strip, left to right. These are what is IN the pack, so they
			-- are the same icons the cards use rather than a decorative set.
			Icons  = {
				"rbxassetid://97906064855506", "rbxassetid://743807896",
				"rbxassetid://7106672194", "rbxassetid://2795768574",
				-- Not the crown (8002852553): it is a dark, detailed badge and at strip
				-- size it collapses into a brown smudge. Fine large on the VIP card.
				"rbxassetid://743807522",
			},
			Grad   = VIOLET,
		},

		-- Rendered top to bottom in this order. HeaderIcon is optional and is drawn
		-- on BOTH sides of the header text when present.
		Sections = {
			{
				Name = "Offers",
				Header = "Limited Offers",
				Items = {
					{ Name = "Starter Pack", Blurb = "5,000 coins and 50 gems to get going!",
					  Price = "99", Icon = "rbxassetid://128442519585600",
					  Grad = PINK, Ribbon = "NEW!" },
					{ Name = "Daily Deal", Blurb = "A fresh discounted bundle every day!",
					  Price = "149", Icon = "rbxassetid://2795768574",
					  Grad = GOLD, Tag = "Resets daily" },
					{ Name = "Weekend Bundle", Blurb = "Coins, gems and a lucky egg in one!",
					  Price = "499", Icon = "rbxassetid://7106672194",
					  Grad = VIOLET, Ribbon = "BEST!", Tag = "Weekend only" },
				},
			},
			{
				Name = "Gamepasses",
				Header = "More Permanent Passes",
				HeaderIcon = "rbxassetid://8002852553",
				Items = {
					{ Name = "2x Coins", Blurb = "Double every harvest, forever!",
					  Price = "299", Icon = "rbxassetid://97906064855506",
					  Grad = GOLD },
					{ Name = "Lucky Eggs", Blurb = "Bonus chance hatching rare pets!",
					  Price = "399", Icon = "rbxassetid://7106672194",
					  Grad = CYAN, Ribbon = "NEW!" },
					-- A plain transparent crown. The obvious "VIP" search hits are badge
					-- images with their own background baked in, which read as a
					-- screenshot pasted next to the cut-out icons either side of them.
					{ Name = "VIP", Blurb = "Chat tag, daily gems and more!",
					  Price = "499", Icon = "rbxassetid://8002852553",
					  Grad = VIOLET, Tag = "Tons of benefits!" },
				},
			},
			{
				Name = "Gems",
				Header = "Gems",
				Items = {
					{ Name = "Gem Handful", Blurb = "25 gems, a taste of the good stuff.",
					  Price = "49", Icon = "rbxassetid://743807896", Grad = CYAN },
					{ Name = "Gem Pouch", Blurb = "150 gems for the serious gardener!",
					  Price = "199", Icon = "rbxassetid://743807522",
					  Grad = VIOLET, Tag = "Popular" },
					{ Name = "Gem Hoard", Blurb = "900 gems and a fat bonus on top!",
					  Price = "799", Icon = "rbxassetid://228648908",
					  Grad = PINK, Ribbon = "BEST!", Tag = "+20% Bonus" },
				},
			},
			{
				Name = "Coins",
				Header = "Coins",
				Items = {
					-- The coin tier icons are deliberately one family: flat gold with a
					-- heavy dark outline, ascending 1 coin -> 3 fanned -> small stack ->
					-- tall stack. Keep them together or the shelf looks scavenged.
					{ Name = "Pocket Change", Blurb = "1,000 coins to tide you over.",
					  Price = "25", Icon = "rbxassetid://13249575568", Grad = GOLD },
					{ Name = "Coin Purse", Blurb = "6,000 coins, the usual pick.",
					  Price = "99", Icon = "rbxassetid://97906064855506",
					  Grad = GREEN, Tag = "Popular" },
					{ Name = "Coin Chest", Blurb = "35,000 coins with a bonus baked in!",
					  Price = "399", Icon = "rbxassetid://2795768574",
					  Grad = GOLD, Ribbon = "NEW!", Tag = "+10% Bonus" },
					{ Name = "Coin Vault", Blurb = "200,000 coins and the biggest bonus!",
					  Price = "1,499", Icon = "rbxassetid://113086469759355",
					  Grad = PINK, Ribbon = "BEST!", Tag = "+25% Bonus" },
				},
			},
		},
	},

	-- The inventory panel. Same property the shop has: a new pet, a re-tint, a
	-- different rail or a different column count is an edit HERE, never a GUI edit.
	--
	-- Nothing in here is owned by anybody. ServerScriptService is empty — no pet
	-- system, no DataStore, no remote — so Pets below is a placeholder roster and the
	-- panel renders INTENT, exactly as the shop does. When real data lands it arrives
	-- at InventoryController's readInventory() seam and this table becomes the
	-- fallback rather than the source. Do not grow a persistence layer in here.
	--
	-- ART: none of these icons is actually a pet. Every rbxassetid in this file is a
	-- free Creator Store asset already verified to load in this GROUP-owned place;
	-- art uploaded by the signed-in user 403s here (see the Shop notes above), so
	-- real pet art is its own pass — find ids, verify they preload, swap them in
	-- below and nothing else changes. The grid deliberately REPEATS one mascot the
	-- way the reference repeats one pet, rather than showing a dozen unrelated
	-- objects: a repeated pet reads as a collection, twelve coins read as a bug.
	--
	-- rbxasset:// paths are files inside the client's own install, so they carry no
	-- asset permission at all and cannot 403. That is why the search and bag glyphs
	-- are rbxasset rather than uploads.
	Inventory = {
		Title = "Inventory!",
		TitleIcon = "rbxassetid://128442519585600",
		SearchIcon = "rbxasset://textures/ui/SearchIcon.png",
		SearchPlaceholder = "Search",

		-- The shelf above the divider.
		EquippedHeader = "Your Best Pets",
		-- How many cells the shelf draws. Pets flagged Equipped fill it in order and
		-- the remainder render as grey "+" slots. The count beside the header and the
		-- number of + tiles therefore cannot disagree — both fall out of this one
		-- number. The reference reads "10/10" with a + tile also showing, which is
		-- the screenshot contradicting itself; 9 of 10 is the same shape and honest.
		EquippedCapacity = 10,

		-- Main grid columns at full size. The reference uses 8. The layout pass drops
		-- a column at a time while the cell would come out under MinCell pixels —
		-- the same phone rule as the shop's MIN_CELL_H.
		Columns = 8,
		-- Pixels. A tile carries a power number across its bottom and an xN badge in
		-- its corner; below this the number stops being readable well before the tile
		-- stops being tappable.
		MinCell = 64,

		-- The header pill, two cells. The reference draws a padlock and a grid mark.
		-- Neither glyph exists in the client's own texture set, and uploads do not
		-- work in this place, so the pill is TYPE instead of icons — and it actually
		-- sorts rather than being decoration. Same silhouette, one less lie.
		Sorts = {
			{ Key = "Power", Label = "POWER" },
			{ Key = "Name",  Label = "A-Z" },
		},

		-- The left rail, top to bottom, overhanging the panel's left edge. A Locked
		-- tile draws desaturated with a "?" where its icon would go — the reference
		-- puts a padlock there and we have no padlock (see Sorts above).
		Rail = {
			{ Name = "Pets",    Icon = "rbxassetid://128442519585600" },
			{ Name = "Bag",     Icon = "rbxasset://textures/ui/Backpack/Backpack.png" },
			{ Name = "Potions", Icon = "rbxassetid://743807896" },
			{ Name = "Index",   Icon = "rbxassetid://8002852553" },
			{ Name = "Locked1", Locked = true },
			{ Name = "Boosts",  Icon = "rbxassetid://97906064855506" },
			{ Name = "Eggs",    Icon = "rbxassetid://7106672194" },
			{ Name = "Locked2", Locked = true },
		},
		-- Which rail tile starts selected. Only this one has content behind it; the
		-- rest are inert on purpose, because there is nothing to show yet.
		RailSelected = 1,

		-- Rarity drives a tile's gradient and nothing else. Reusing the shop's five
		-- pairs rather than inventing a sixth is what keeps the two panels one family.
		Rarities = {
			Common = GREEN, Uncommon = CYAN, Rare = VIOLET,
			Epic = PINK, Legendary = GOLD,
		},

		-- What a pet with no Model of its own draws.
		PetIcon = "rbxassetid://128442519585600",

		-- Pets render as the REAL MODEL in a ViewportFrame, not as flat art. This
		-- place is group-owned, so uploaded images 403 and the Creator Store has no
		-- pet set worth the name — but the place already contains six rigged pets,
		-- and a viewport of the actual thing is what PS99 does anyway. Model names
		-- index ReplicatedStorage.PetModels, cloned from Workspace.Pets by hand.
		-- A pet with no Model falls back to PetIcon as a flat image.
		-- Adding a pet model: clone it into PetModels, anchor every part, set a
		-- PrimaryPart, PivotTo(CFrame.new()). The viewport frames it off its own
		-- bounding box, so size does not matter — Bigfoot is 25 studs and ghostly 4.
		PetModelFolder = "PetModels",

		-- One entry is one STACK. Power is the number across the tile's bottom; omit
		-- it and the tile draws "??", which is what the reference does for its rarest
		-- pet. Count > 1 draws the xN badge. Equipped fills the shelf, in this order.
		Pets = {
			{ Name = "Prime Helix",   Rarity = "Legendary", Count = 1,  Equipped = true, Model = "ghostly" },
			{ Name = "Solar Strand",  Rarity = "Legendary", Power = 320, Count = 2,  Equipped = true, Model = "Bigfoot" },
			{ Name = "Splice Slime",  Rarity = "Common",    Power = 313, Count = 11, Equipped = true, Model = "Chicken" },
			{ Name = "Gel Node",      Rarity = "Common",    Power = 306, Count = 4,  Equipped = true, Model = "Chicken" },
			{ Name = "Bit Beetle",    Rarity = "Uncommon",  Power = 298, Count = 2,  Equipped = true, Model = "Scorpion" },
			{ Name = "Neon Nucleus",  Rarity = "Rare",      Power = 287, Count = 1,  Equipped = true, Model = "Cat" },
			{ Name = "Chrome Cell",   Rarity = "Rare",      Power = 271, Count = 3,  Equipped = true, Model = "Cat" },
			{ Name = "Mud Mitosis",   Rarity = "Uncommon",  Power = 264, Count = 1,  Equipped = true, Model = "Dog" },
			{ Name = "Plasma Pup",    Rarity = "Epic",      Power = 250, Count = 1,  Equipped = true, Model = "Dog" },
			{ Name = "Vial Vermin",   Rarity = "Common",    Power = 222, Count = 5, Model = "Scorpion" },
			{ Name = "Petri Pal",     Rarity = "Common",    Power = 202, Count = 2, Model = "Chicken" },
			{ Name = "Clone Cluster", Rarity = "Uncommon",  Power = 172, Count = 1, Model = "ghostly" },
			{ Name = "Beaker Bat",    Rarity = "Uncommon",  Power = 150, Count = 3, Model = "ghostly" },
			{ Name = "Agar Ape",      Rarity = "Rare",      Power = 128, Count = 1, Model = "Bigfoot" },
			{ Name = "Enzyme Egg",    Rarity = "Common",    Power = 96,  Count = 9, Model = "Chicken" },
			{ Name = "Slop Sprout",   Rarity = "Common",    Power = 85,  Count = 2, Model = "Dog" },
			{ Name = "Test Tube Tot", Rarity = "Common",    Power = 62,  Count = 4, Model = "Cat" },
			{ Name = "Base Pair",     Rarity = "Common",    Power = 37,  Count = 1, Model = "Chicken" },
		},
	},
}
