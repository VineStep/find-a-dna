--[[
	GameConfig — every tunable number in the game.

	Retro-slop: Pet Simulator x Grow a Garden.
	Plant -> crops grow on a timer (offline too) -> harvest -> currency
	-> eggs -> pets boost yield -> rebirth multiplies everything.

	Owned by rblx-orchestrator. Other agents read; they do not edit.

	CUSTOM ICONS (uploaded 2026-09-20, NOT Creator Store)

	Six commissioned icons were uploaded through upload_image, which always
	uploads as the signed-in USER. This place is group-owned, so each one 403s
	with AssetDelivery403InvalidPermission until the EXPERIENCE is granted
	access to it — do that once per id at create.roblox.com (Creations -> the
	asset -> share access), or click the error in Studio's Output. After
	granting, restart Studio: ContentProvider caches the Failure for the whole
	session and re-probing returns the cached verdict with no network request.

	  settings   105459200031829   UNUSED - the old gear (131580947637053) was
	                              kept; this one was rejected on sight.
	  teleport   129530271227629   HUD TeleportSlot
	  shop        76348742925796   HUD ShopSlot
	  index      128325335852740   HUD IndexSlot
	  dailygift  115491811384418   HUD DailyGiftSlot (new, bottom-right cell)
	  coins       82131632401064   RETIRED - superseded by the COIN_* set below
	  halftone    79477047982140   Shop.Halftone (every card, banner and plate)
	  coin_small 109678637627142   COIN_S (granted)
	  coin_med   101588193234939   COIN_M (granted)
	  coin_large  96948739390264   COIN_L (granted)

	COIN_S/M/L are the only coin art in the game; see the block by their
	declaration for which tier goes where and why.

	Sources are 512x512 trimmed PNGs; the originals are not in this repo.
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

-- The Robux mark, drawn instead of an "R$" prefix. The shop draws it ONE way
-- everywhere — white with a stamped ink contour, matching the price number beside
-- it, which is always white with a heavy ink outline (ShopController.robuxMark).
-- A bare black mark was used on cards and the feature banner and is wrong: on a
-- gold or cyan card a dark glyph beside a light number stops reading as one price.
-- This is the THICK-ringed cut of the glyph; the thinner cut read light at any
-- size. Store page 11713337409 is a Decal wrapper; this is the texture inside it,
-- per the Icon note below.
local ROBUX = "rbxassetid://11713337390"

-- The egg, everywhere one is drawn: the Galaxy Helix offer and every card that
-- sells eggs. One id so the object the shop keeps showing you is the same object.
--
-- NOTE THE NUMBER. The store page is 15498677811 ("[FREE] Egg Icon" by nico_dev090)
-- and that id is assetTypeId 13 — a DECAL WRAPPER, not an image; setting it on an
-- ImageLabel returns AssetFetchStatus.Failure. This is the texture inside it,
-- resolved with InsertService:LoadAsset(15498677811) and read off the Decal's
-- .Texture, then verified to preload Success in this group-owned place.
local EGG = "rbxassetid://15498677766"

-- THE COIN. Three tiers of one commissioned, branded set — a single DNA coin, a
-- stack of three, a pile — and between them they are now the ONLY coin art in the
-- game. Everything that used to draw a coin drew a different creator's coin: a
-- generic gold "$" disc, a fan of flat ellipses, a tall plain stack. Six different
-- coins across one game is six different currencies as far as a player is
-- concerned, which is exactly the thing a branded set exists to stop.
--
-- Pick by AMOUNT, not by product: the tier says how much, the label says what.
-- That is why Coin Chest and Coin Vault share COIN_L and are told apart by the
-- figure drawn on them — a fourth, bigger piece of art is the honest fix and does
-- not exist yet.
--
-- All three are USER-owned uploads in a GROUP-owned place and needed the
-- experience granted access by hand before they would fetch; that is done.
local COIN_S = "rbxassetid://109678637627142"
local COIN_M = "rbxassetid://101588193234939"
local COIN_L = "rbxassetid://96948739390264"

-- THE REWARD CHIME, played when the player is GIVEN something: a daily card
-- claimed, anything pressed in the shop. One id in one place because the two
-- panels must not drift into two different "you got it" sounds — that is the
-- same argument the coin set makes about six creators' coins being six
-- currencies as far as a player is concerned.
--
-- A Creator Store PAGE id, used verbatim. That works for audio and only for
-- audio: an image served from a store page is wrapped in a Decal and has to be
-- unwrapped first (see the EGG note), but a sound has no wrapper. Verified here:
-- SoundId set, IsLoaded true, TimeLength 0.94s.
local SFX_REWARD = 130452529897520

-- THE TIKTOK. One constant because it is about to be drawn in more than one
-- place — codes drop there, so the codes row names it — and a handle typed twice
-- is a handle that goes stale once.
local TIKTOK = "@find_a_dna"

-- THE GEM, in three tiers, and THE CROWN. Commissioned to match the coin set:
-- same heavy black contour, same flat facets, same cut-out-on-transparent. The
-- gems replace three DIFFERENT creators' gems that were standing in — a pale
-- diamond, a violet cluster and a pink crystal — which between them made the
-- one currency look like three.
--
-- Picked by AMOUNT, exactly as the coins are: the tier says how much, the label
-- says what. 25 -> S, 150 -> M, 900 -> L, in the shop and on the daily cards
-- alike, so the same quantity is always the same picture.
--
-- USER-owned uploads in a GROUP-owned place: each id 403s with
-- AssetDelivery403InvalidPermission until the EXPERIENCE is granted access by
-- hand (create.roblox.com -> Creations -> the asset -> share access), and Studio
-- must be RESTARTED afterwards because ContentProvider caches the failure for the
-- whole session. Uploaded 2026-09-20; grant state tracked in the session notes.
local GEM_S = "rbxassetid://122880024876163"
local GEM_M = "rbxassetid://106998530940587"
local GEM_L = "rbxassetid://102260103936882"
-- The VIP crown. Replaces 8002852553, a flat gold crown borrowed from the store
-- that had no contour and read as clip art beside the branded coins.
local CROWN = "rbxassetid://135359935892473"

return {
	-- Sounds shared by more than one panel. Anything used by exactly one panel
	-- stays in that panel's own block (Inventory.PetHoverSound is the example);
	-- this table exists for the ones that would otherwise be typed twice.
	Sfx = {
		Reward = SFX_REWARD,
		RewardVolume = 0.55,
	},

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
	-- verified to preload Success in this group-owned place. An image uploaded by
	-- the signed-in user works here ONLY after the experience is granted access to
	-- it by hand (see the CUSTOM ICONS block at the top); reuse a verified id
	-- before hunting a new one, and upload only when nothing existing will do.
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
		TitleIcon = "rbxassetid://115638707143734",

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
		--
		-- REPLACED 2026-09-20. The old sheet's dots were sized for a 272px card and
		-- the offer plate is 745px wide: at that size they read as spots rather than
		-- as a tone. This one is "Halftone Pattern" from ui-resources.com (its API is
		-- at /api/resources now, not the Supabase table the notes describe — 1102
		-- rows), a finer and denser grid, resized to 512 square. Like every image
		-- uploaded here it is user-owned and needed the experience-access grant.
		-- BACK to the old sheet. The finer replacement (79477047982140) is uploaded
		-- and correct but still 403s — it has not been granted experience access, and
		-- an un-granted id does not fall back to anything: every dot in the shop just
		-- vanished. Swap the id back the moment that grant lands.
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

		-- NO FEATURE BANNER. This held "Super Starter Pack!" — a mascot overhanging
		-- the left end, a centred stack of title / contents strip / sub-line, and a
		-- price pill on the right, with "Top Seller" on its own line underneath.
		-- Removed 2026-09-20 at the owner's call.
		--
		-- The banner is the FIRST row of the scroll and it scrolls with the list; it
		-- was never pinned chrome. Omitting this table is the supported way to drop
		-- it: ShopController builds nothing when Feature is nil, and the Banner frame
		-- that ships in the place is Visible = false until the controller turns it on,
		-- so nothing is left behind. The Galaxy Helix offer is now the first thing in
		-- the panel.
		--
		-- Restoring it means putting a Feature table back here — Title, Sub, Tag,
		-- Price, Mascot, Icons (the ids the cards use, NOT the crown 8002852553:
		-- it is a dark detailed badge that collapses into a brown smudge at strip
		-- size), and Grad. Nothing else reads it.

		-- The egg offer: one wide card under its own header, between the feature
		-- banner and the first shelf. It is the reference's busiest surface — a
		-- title, a rarity flag, a row of hatch odds and three quantity tiers all on
		-- one plate — and it earns the room because it is the only thing in the shop
		-- that shows you WHAT you get rather than naming it.
		--
		-- Drops are left to right, commonest first, which is the order the reference
		-- uses and the order the odds read in. Stars is the pip count above a drop,
		-- climbing with rarity; Pct is display text, not a number, because the real
		-- roll has to live on the server and these must not look authoritative.
		-- A drop names a Model in ReplicatedStorage.PetModels and renders as a
		-- ViewportFrame of the real rig, for the same reason the inventory does:
		-- uploads 403 here and there is no pet art to buy. Icon is the flat
		-- fallback for a drop with no model.
		--
		-- Tiers are the quantity ladder. Off is the strike-through saving on the
		-- bulk tier, drawn in red under its pill; omit it and nothing is drawn.
		Offer = {
			Header = "Exclusive & Special!",
			Title  = "Galaxy Helix",
			Flag   = "Limited Time!",
			-- The egg itself, big on the right end. Same id the Lucky Eggs pass
			-- uses, so the two read as the same object in two places.
			Egg    = EGG,
			-- That egg is plain WHITE — and the artwork's own shading is in that
			-- white. ImageColor3 multiplies, so a tint scales every one of those
			-- values together: at the deep violet this used to carry (116,74,196)
			-- the highlights came down to the shadows and the egg rendered as one
			-- flat dark blob, which is the last thing the object the offer is NAMED
			-- after should be. Light enough to keep the form, tinted enough to be
			-- the galaxy egg the name promises.
			--
			-- The old note here said the egg had to be the darkest thing on that end
			-- or it dissolved into the gradient. True when it had nothing round it;
			-- ShopController now stamps an ink contour behind it, and separation is
			-- that contour's job rather than the tint's.
			EggTint = Color3.fromRGB(196, 170, 252),
			Grad   = VIOLET,
			Drops = {
				{ Model = "Chicken",  Pct = "65%",   Stars = 1 },
				{ Model = "Dog",      Pct = "30%",   Stars = 2 },
				{ Model = "Cat",      Pct = "3%",    Stars = 3 },
				{ Model = "Scorpion", Pct = "1.7%",  Stars = 4 },
				{ Model = "ghostly",  Pct = "0.3%",  Stars = 5 },
			},
			Tiers = {
				{ Label = "x1 Egg",  Price = "195" },
				{ Label = "x3 Eggs", Price = "545" },
				{ Label = "x8 Eggs", Price = "1,495", Off = "-6.7%" },
			},
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
					  Price = "149", Icon = COIN_M,
					  Grad = GOLD, Tag = "Resets daily" },
					{ Name = "Weekend Bundle", Blurb = "Coins, gems and a lucky egg in one!",
					  Price = "499", Icon = EGG,
					  Grad = VIOLET, Ribbon = "BEST!", Tag = "Weekend only" },
				},
			},
			{
				Name = "Gamepasses",
				Header = "More Permanent Passes",
				HeaderIcon = CROWN,
				Items = {
					{ Name = "2x Coins", Blurb = "Double every harvest, forever!",
					  Price = "299", Icon = COIN_M,
					  Grad = GOLD },
					{ Name = "Lucky Eggs", Blurb = "Bonus chance hatching rare pets!",
					  Price = "399", Icon = EGG,
					  Grad = CYAN, Ribbon = "NEW!" },
					-- A plain transparent crown. The obvious "VIP" search hits are badge
					-- images with their own background baked in, which read as a
					-- screenshot pasted next to the cut-out icons either side of them.
					{ Name = "VIP", Blurb = "Chat tag, daily gems and more!",
					  Price = "499", Icon = CROWN,
					  Grad = VIOLET, Tag = "Tons of benefits!" },
				},
			},
			{
				Name = "Gems",
				Header = "Gems",
				Items = {
					{ Name = "Gem Handful", Blurb = "25 gems, a taste of the good stuff.",
					  Price = "49", Icon = GEM_S, Grad = CYAN },
					{ Name = "Gem Pouch", Blurb = "150 gems for the serious gardener!",
					  Price = "199", Icon = GEM_M,
					  Grad = VIOLET, Tag = "Popular" },
					{ Name = "Gem Hoard", Blurb = "900 gems and a fat bonus on top!",
					  Price = "799", Icon = GEM_L,
					  Grad = PINK, Ribbon = "BEST!", Tag = "+20% Bonus" },
				},
			},
			{
				Name = "Coins",
				Header = "Coins",
				Items = {
					-- Qty is the headline number, drawn BY ShopController over the art's
					-- bottom edge as yellow outlined text. It used to live only in the
					-- blurb, which is 12px of body copy beside the picture and the one
					-- place nobody scanning a shelf looks — so the blurbs below no longer
					-- repeat the figure. Say it once, say it big.
					--
					-- COMMISSIONED SET, uploaded 2026-09-20 and LIVE. Three branded
					-- DNA coins — one coin / a stack of three / a pile — which is the
					-- ascending family the old note here kept asking for. They are
					-- USER-owned in a GROUP-owned place, so each needed the experience
					-- granted access by hand before it would fetch; that is done and all
					-- three probe Success (see the CUSTOM ICONS block at the top).
					--
					-- Coin Vault has no art of its own and repeats COIN_L. It used to
					-- keep a generic stack so the top rung would at least be a different
					-- OBJECT — but that stack read as SMALLER than the pile above it, so
					-- the ladder ran backwards at the one rung that has to feel biggest.
					-- Two identical piles told apart by 35,000 vs 200,000 is the lesser
					-- fault. A fourth tier of art retires this note.
					{ Name = "Pocket Change", Blurb = "Enough to tide you over.",
					  Qty = "1,000",
					  Price = "25", Icon = COIN_S, Grad = GOLD },
					{ Name = "Coin Purse", Blurb = "The usual pick.",
					  Qty = "6,000",
					  Price = "99", Icon = COIN_M,
					  Grad = GREEN, Tag = "Popular" },
					{ Name = "Coin Chest", Blurb = "With a bonus baked in!",
					  Qty = "35,000",
					  Price = "399", Icon = COIN_L,
					  Grad = GOLD, Ribbon = "NEW!", Tag = "+10% Bonus" },
					{ Name = "Coin Vault", Blurb = "And the biggest bonus of all!",
					  Qty = "200,000",
					  Price = "1,499", Icon = COIN_L,
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
	-- The Portals panel. A grid of places to jump to, which is the one HUD tile
	-- whose job can be done honestly with no server at all: a client owns its own
	-- character, so PivotTo on it is a real teleport and not a mock.
	--
	-- Pos is a world position; the controller drops the player a little above it so
	-- they land on the ground rather than inside it. These were read off the place
	-- itself — the spawn ring, the fuse machine in Overworld, and the ore/merchant
	-- cluster that sits 140 studs down and 12,000 out. Move the geometry and these
	-- go stale; nothing validates them.
	Teleport = {
		Title = "Portals!",
		TitleIcon = "rbxassetid://129530271227629",
		Blurb = "Jump anywhere you have found.",
		-- Drawn on the card that matches where the player already is.
		HereLabel = "You are here",
		GoLabel = "Travel",
		-- Studs above Pos to release the character. The world is blocky and a
		-- landing exactly on a surface intersects it; a short drop is what the
		-- reference games do and it costs nothing.
		DropHeight = 6,
		-- THREE PLACES, down from six. The Mine, Merchant and Fuse Machine were cut
		-- on 2026-09-21 — not because their coordinates were wrong (they were
		-- measured and they worked) but because a portal is a promise that there is
		-- something to do where it drops you, and at those three there is not. The
		-- ore cluster and the merchant stall are set dressing with no interaction on
		-- them at all, and the Fuse Machine's job moved onto the DNA machine, which
		-- you walk up to rather than teleport to. Bringing one back is a row here
		-- and nothing else; do it when the destination does something.
		Places = {
			{ Name = "Home", Blurb = "The spawn ring and your plots.",
			  Pos = Vector3.new(-166, -71, -195),
			  Icon = "rbxassetid://128442519585600", Grad = GREEN },
			-- WRONG PLACE FOR A REVISION, and worth recording because the name
			-- collision is still in the file. There are TWO things in this place
			-- called "cave":
			--
			--   Workspace.Cave      a real torch-lit cavern at x 240, z -11. Floor
			--                       slab top y -18.2, ceiling y -1..14, and the 27
			--                       Workspace.torch models all sit in it.
			--   the Music "Cave"    a 241x88x277 box at x 783, z -298 — which is
			--     zone below        the MINE cavern, with the rails, the carts and
			--                       the mineshaft plate inside it.
			--
			-- This portal pointed at (800, 11, -330), which is in the second one —
			-- about 60 studs from the Mineshaft portal's own landing spot. So the
			-- two portals dropped you in the same timbered mine and neither went to
			-- the cave. It now goes to the cave with the torches in it.
			--
			-- Pos is where a character actually COMES TO REST after being dropped
			-- there, read off HumanoidRootPart rather than taken off the geometry:
			-- the floor is uneven (rest height ranges -6 to -15 across the chamber)
			-- and a landing computed from the slab would be wrong nearly everywhere.
			{ Name = "The Cave", Blurb = "Dark, torchlit and full of ore.",
			  Pos = Vector3.new(239.5, -15.4, -11.5),
			  Icon = GEM_L, Grad = CYAN },
			-- ICON DEBT, and deliberate: COIN_S is the game's own coin at its
			-- smallest tier and this bends the amount-tier rule the coin block
			-- states, because there is no pickaxe, ore or lantern glyph in the
			-- place and a mineshaft is not a quantity of anything. It wants its
			-- own art; until then this at least keeps it inside the branded set.
			{ Name = "Mineshaft", Blurb = "The cart, the rails, the timber.",
			  Pos = Vector3.new(739.5, 17, -244),
			  Icon = COIN_S, Grad = GOLD },
		},
	},

	-- The Settings panel. Every switch on it DOES SOMETHING — that is the whole
	-- design rule here, and it is why the list is short. This game's other panels
	-- are full of inert controls waiting on a server; settings are the one thing a
	-- client can own outright, so there was no excuse for a row of dead toggles.
	--
	-- Key is what SettingsController switches on, and adding a row means teaching
	-- it a new one. Default is what a fresh client gets. Nothing persists: there is
	-- no DataStore, so these last until the player leaves.
	Settings = {
		Title = "Settings!",
		TitleIcon = "rbxassetid://131580947637053",
		Rows = {
			{ Key = "SfxVolume", Kind = "Slider", Name = "Sound Effects",
			  Blurb = "Clicks, hovers and purchases.", Default = 1 },
			-- Key must match a handler in SettingsController's APPLY table EXACTLY;
			-- this one was "PanelBlur" against a handler named MenuBlur and the
			-- toggle flipped its pill while doing nothing at all. The controller
			-- now warns on startup for any row it cannot wire.
			{ Key = "MenuBlur", Kind = "Toggle", Name = "Menu Blur",
			  Blurb = "Blur the world behind a panel.", Default = true },
			{ Key = "Shadows", Kind = "Toggle", Name = "Shadows",
			  Blurb = "Turn off for a few more frames.", Default = true },
			-- NOT a "daily popup" toggle, which was the obvious fourth row and is a
			-- dead one: the auto-open fires at join, before this panel has been
			-- touched, and nothing persists to the next session. It could never do
			-- anything. This can.
			{ Key = "ReduceMotion", Kind = "Toggle", Name = "Reduce Motion",
			  Blurb = "Stop the spinning and sparkling.", Default = false },
			-- The ONE row that is not a setting, and the one exception to the rule
			-- above: a code cannot grant anything without a server, so this
			-- validates and answers and nothing else. Kind = "Code" has no APPLY
			-- handler by design and SettingsController skips it in the wiring
			-- check. Last in the list because it is the odd one out.
			{ Key = "Codes", Kind = "Code", Name = "Codes",
			  Blurb = "New codes drop on TikTok " .. TIKTOK .. "!", Default = "" },
		},
		OnLabel = "ON",
		OffLabel = "OFF",

		-- Codes, CLIENT-SIDE. The key is compared uppercased with spaces stripped,
		-- so case and stray taps do not matter; the value is what the row says back.
		-- ponytail: recognition only, no grant and no persistence — there is no
		-- server to grant from. Upgrade path: a RedeemCode RemoteFunction that
		-- returns this same message, with the table moved server-side so the
		-- answers are not sitting in a client module for anyone to read.
		Codes = {
			FINDADNA  = "Welcome! Code accepted.",
			TIKTOK    = "Thanks for following " .. TIKTOK .. "!",
			SLOP      = "Certified slop. Accepted!",
			RELEASE   = "Day one code accepted!",
		},
		CodePlaceholder = "Enter code...",
		CodeButton = "GO",
		-- Said back on the row's own blurb line, which then returns to the TikTok
		-- tag. A dedicated result label was tried and is a fifth thing on a row
		-- that is already the busiest one here.
		CodeBad = "That code is not real!",
		CodeUsed = "Already used that one!",
		CodeFlash = 2.6,
		TikTok = TIKTOK,
	},

	-- THE ADMIN PANEL, and the first thing in this game that genuinely cannot be
	-- done on the client. A client cannot send anything to another client, and an
	-- admin check a client makes about itself is decoration — so this is the config
	-- for a real server script, ServerScriptService.AdminService, which is the
	-- FIRST server script this place has ever had.
	--
	-- WHO IS AN ADMIN is decided on the server and nowhere else. Two ways in, and
	-- either is enough:
	--   UserIds       an explicit list, for people outside the group.
	--   MinGroupRank  rank in the owning group, which is how this scales without
	--                 editing a table — 816135141 is rank 254 (owner) today.
	-- The client is told yes or no by a RemoteFunction and uses the answer only to
	-- decide whether to BUILD the panel. Every request it then sends is re-checked
	-- server-side, because the answer to "am I an admin" arriving on a client is a
	-- value an exploiter can lie about to itself all day.
	Admin = {
		UserIds = { 816135141 },
		GroupId = 155271859,
		MinGroupRank = 200,

		Title = "Admin!",
		TitleIcon = CROWN,
		Keybind = Enum.KeyCode.F2,

		-- THE BUTTON. A standalone key in the TOP-RIGHT corner — free space, since
		-- HUDController turns off Roblox's own leaderboard and the message feed is
		-- top-CENTRE.
		--
		-- It spent one revision as a seventh tile in the HUD's left grid and came
		-- back here by decision. Both placements work; the corner is the one that
		-- keeps the left stack meaning "things every player has". A seventh cell
		-- reflows that stack into 2x4 on an admin's screen and nobody else's, so
		-- the one player who most needs to recognise the HUD at a glance is the one
		-- looking at a different HUD from everyone they are moderating.
		--
		-- Built at runtime by AdminController, after the server has answered, so a
		-- non-admin is never sent the instance at all. That also keeps it out of
		-- Studio's Edit viewport.
		--
		-- F2 still works and is still the faster way in. This exists because the
		-- keybind is invisible — and because touch has no F2 at all, which was the
		-- hole in the keybind-only version.
		Button = {
			Pos = Vector2.new(0.975, 0.075),   -- of viewport, anchored at its own centre-right
			Size = 0.075,                      -- of viewport HEIGHT; the key is square
			MinPx = 44,                        -- the tap floor every HUD control here honours
			MaxPx = 84,
		},

		-- Global messages: [icon] USER: TEXT, exactly that shape.
		-- The icon is the VIP crown, which is the authority mark this game already
		-- has. It 403s until the experience is granted access to it — see the
		-- CROWN declaration — so the line renders without its icon until then.
		MessageIcon = CROWN,
		-- The NAME is filled in by the server from the Player object. It is never
		-- taken from the client: a client that supplies its own display name in the
		-- payload can announce as anybody.
		MessageDuration = 7,
		MessageMax = 5,          -- lines on screen; the oldest goes
		MaxMessageLength = 140,
		AnnounceCooldown = 2,    -- seconds per admin, enforced on the server
		NameColour = Color3.fromRGB(255, 221, 74),

		-- Walk speed steps the panel cycles through. Applied on the SERVER, so it
		-- is a real change and not a client that has talked itself into running
		-- faster.
		Speeds = { 16, 32, 64, 120, 200 },
		FlySpeed = 70,

		-- Jump, also server-applied. Roblox has two jump models and a Humanoid
		-- obeys whichever UseJumpPower selects, so the server sets that too or
		-- these numbers are read and ignored.
		Jumps = { 50, 80, 120, 200, 350 },

		-- GRAVITY IS GLOBAL — workspace.Gravity is one number for the whole
		-- server, so this is the one control here that changes how the game plays
		-- for every other player at once. 196.2 is Roblox's default and is first
		-- in the list so the way back is the obvious press.
		Gravities = { 196.2, 100, 50, 15, 0 },

		-- Which music zone to force, cycling through MusicController's own tracks
		-- plus an "Auto" that hands control back to the position poll. Client-side
		-- like the music itself: what one admin hears is nobody else's business,
		-- and this is for checking a track without walking to the zone.
		MusicZones = { "Auto", "Overworld", "Cave", "Mineshaft" },

		-- Time of day, as presses rather than a slider: the panel needs no drag
		-- logic for a control with four useful values. Server-set, so it changes
		-- the world for everybody.
		--
		-- LIVE is the default state and the point of the row: the sky follows REAL
		-- WORLD time (UTC), on the server, so every player in every server sees the
		-- same sky as each other AND as the actual hour. An admin press pins it and
		-- LIVE hands it back. Without Live there is no way to undo a pin short of
		-- restarting the server.
		Times = {
			{ Label = "Live", Live = true },
			{ Label = "Dawn", Clock = 6.5 },
			{ Label = "Noon", Clock = 13 },
			{ Label = "Night", Clock = 0 },
		},
		-- How often the live clock is re-read. The sky moves 0.5 of an hour per
		-- 30s of real time at ClockTime's resolution, so anything tighter is
		-- writing the same number repeatedly.
		TimeSync = 30,

		-- HOW MANY ROWS FILL THE SCROLL WINDOW, and the .5 is the whole point.
		--
		-- It was a flat 4, which divided the window so four rows fitted it exactly
		-- — and a row boundary landing exactly on the clip edge is what made the
		-- fourth row look SLICED rather than scrolled. Its UIStroke is drawn
		-- outside the frame, so the clip cut the stroke off and the plate ended in
		-- a hard flat line.
		--
		-- At 3.5 the fourth row is deliberately half-visible. Nothing is cut at a
		-- boundary, the half-row is the standard "there is more below" affordance,
		-- and the rows come out bigger (about 85px against 76) into the bargain.
		VisibleRows = 3.5,

		-- THE BLOOD MOON. Server-applied and GLOBAL, like Gravity and Time — it is
		-- a change to the sky, and a sky that is red for one player and blue for
		-- the next is not a sky.
		--
		-- It PINS the clock the way Dawn/Noon/Night do, because a blood moon at
		-- two in the afternoon is just a red filter. Turning it off hands the time
		-- back to whatever the Time row was last set to, which is Live unless an
		-- admin pinned it.
		--
		-- Every value here is a DELTA from the place's own lighting, captured on
		-- the server the first time it is switched on and restored when it is
		-- switched off — so re-tinting the game does not strand these numbers.
		BloodMoon = {
			ClockTime = 0,
			Ambient = Color3.fromRGB(58, 12, 16),
			OutdoorAmbient = Color3.fromRGB(74, 14, 18),
			Brightness = 1.4,
			-- The moon itself, tinted through ColorShift_Top, plus a red haze on
			-- the horizon. FogEnd is what makes it feel close rather than merely
			-- dark; the place ships with fog effectively off at 100000.
			ColorShiftTop = Color3.fromRGB(120, 24, 24),
			ColorShiftBottom = Color3.fromRGB(40, 8, 10),
			FogColor = Color3.fromRGB(46, 8, 12),
			FogEnd = 620,
			FogStart = 40,
			-- Pushed down, not up: a blood moon is a dark night with one red light
			-- in it, and lifting exposure turns it into a red afternoon.
			ExposureCompensation = -0.25,

			-- THE ATMOSPHERE, and without it the effect only half lands. The place
			-- has an Atmosphere whose Color is near-cyan, and it owns the HORIZON —
			-- so with only the Lighting properties changed the ground and cliffs
			-- went red while a bright blue band sat across the skyline behind them,
			-- which is the one part of the frame the eye goes to. Density up and
			-- Haze well up is what closes the distance and makes it feel like a
			-- night you cannot see far into.
			Atmosphere = {
				Density = 0.42,
				Color = Color3.fromRGB(120, 34, 30),
				Decay = Color3.fromRGB(58, 12, 14),
				Haze = 2.4,
				Glare = 0.35,
			},
		},
	},

	-- THE DNA MACHINE — the first thing in this game you walk up to rather than
	-- press a HUD tile for, and the reason the Fuse Machine portal was deleted
	-- from Teleport.Places above. A machine you teleport to is furniture; a
	-- machine you find is a place.
	--
	-- STILL CLIENT-ONLY, and honest about it. Picking two strands and pressing
	-- SPLICE shows you the result and grants nothing, because granting needs a
	-- server and this game has exactly one server script. The seam is deliberate
	-- and narrow: FuseController computes the outcome in one function, and the
	-- day that becomes a RemoteFunction call nothing else in the file moves.
	Fuse = {
		-- Found by name under Workspace. The model's name carries a lowercase "n"
		-- and a space; that is what is actually in the place and renaming it there
		-- would strand the world dump in tree/.
		ModelName = "Dna machine",

		Title = "Splice!",
		TitleIcon = COIN_S,

		-- THE PLATE over the machine. It is a CLICK TARGET, not a key prompt.
		--
		-- A real ProximityPrompt with Style = Custom drove this for several
		-- revisions and was the right call while the interaction was "press E" —
		-- it brought Roblox's distance tracking, its arbitration and its touch
		-- button for free. With the key gone, all that was left of it was a second
		-- distance check that could disagree with the highlight's, so it went too.
		-- WorldPrompt owns the whole widget now and both callers share it.
		Prompt = {
			ActionText = "Splice",
			ObjectText = "DNA MACHINE",
			-- NO KeyCode and no key cap. Clicking the plate or the machine is the
			-- only way in, so a key legend would be an instruction to press
			-- something that does nothing.
			--
			-- The plate now appears at the SAME range the border does — see
			-- Select.ShowDistance — rather than at a short press-range of its own.
			-- A machine that lights up from across the plot and only tells you what
			-- it is once you are standing in it was telling you last.
			HoldDuration = 0,
			-- Studs above the box top the plate floats; 0 puts it at the centre,
			-- which is where Roblox's own default prompt drew. It spent a revision
			-- four studs above the roof, which on a two-storey tank is the sky.
			Rise = 0,
			-- Billboard height in STUDS, and its aspect. Studs rather than pixels so
			-- it shrinks with distance like the object it belongs to; a pixel-sized
			-- billboard is the same size across the whole map and stops reading as
			-- attached to anything.
			Height = 3.6,
			Aspect = 3.15,
			-- THE POP. In with a Back ease, out faster and plain — the same
			-- asymmetry every panel in this game opens and closes with. Without it
			-- the plate blinks on at a fixed radius, which reads as a rendering
			-- glitch rather than as the machine noticing you.
			PopIn = 0.24,
			PopOut = 0.14,
			-- The scale it springs from and collapses back to.
			PopFrom = 0.4,
		},

		-- THE SELECTION, and it is ONE effect now: a Highlight on the model. That
		-- IS the machine's border — it traces the real silhouette rather than a box
		-- approximating it.
		--
		-- THE DASHED OUTLINE IS GONE, after three attempts. A rectangle on the
		-- FLOOR marked the area the machine stands in rather than the machine; one
		-- cage round the model's bounding box was a box in the air; a cage per big
		-- part traced the shape but cost 184 marching bricks and read busy. All
		-- three were a lot of machinery to say "this object", and the Highlight
		-- says it directly. Bringing one back means a DashLength/DashGap/DashWidth
		-- block here and the edge walk in the controller; nothing else reads them.
		--
		-- NOTE WHAT IS NOT AVAILABLE: Highlight has FillColor, FillTransparency,
		-- OutlineColor, OutlineTransparency and DepthMode and NOTHING ELSE. There is
		-- no thickness property, so "stronger" cannot mean wider — it means the
		-- three levers below.
		Select = {
			-- CYAN, not white, and this is the single biggest gain. A white contour
			-- on a pale grey machine under a bright sky is white on white and it
			-- vanished at any distance. Cyan is the game's own accent — the selected
			-- rail cell and the armed slot ring are already this colour — so it
			-- reads as "picked" rather than as a new colour for one object.
			FillColour = Color3.fromRGB(168, 230, 255),
			OutlineColour = Color3.fromRGB(74, 176, 232),
			-- Fully opaque. There is nowhere further to go on the contour itself.
			OutlineTransparency = 0,

			-- ALWAYSONTOP, which is the OTHER half of "stronger" and the thing that
			-- actually made it a border. Occluded draws the contour only where the
			-- object is already visible, and most of this machine is a glass tank —
			-- so a cyan outline at full opacity still came out as a faint edge you
			-- had to look for. Forced in front, it is a hard line round the
			-- silhouette.
			--
			-- It was rejected twice before on a real objection: the machine is big
			-- enough to stand inside, and an always-on-top FILL paints over the
			-- whole world through it. That objection is about the fill, not the
			-- contour — so the fill goes nearly transparent and the outline does the
			-- work. Both halves of this pair have to move together; raise the fill
			-- again and the paint-through comes back.
			DepthMode = "AlwaysOnTop",
			FillTransparency = 0.88,
			-- What the fill goes to while the pointer is ON the machine. A visible
			-- step, and still light enough not to flood the screen from inside.
			HoverFillTransparency = 0.72,

			-- HOW FAR THE MACHINE IS LIVE, in studs: the border, the plate and the
			-- click all use this one figure. It was 24 — the old prompt's range —
			-- which meant the machine only lit up once you were already walking
			-- into it, the one moment you can already see it.
			--
			-- ONE range, not two. An earlier pass gave the border 140 and left the
			-- plate at 24, which is a machine that glows from across the plot and
			-- will not say what it is until you are on top of it.
			ShowDistance = 140,
			-- Seconds between distance checks. A vector subtract is nothing, but
			-- this does not need to run every frame to catch somebody walking.
			ShowPoll = 0.25,

			-- THE FILL GETS STRONGER WITH DISTANCE, which is the other half of
			-- "visible from farther" and the half that actually shows.
			--
			-- Turning the border on at 140 studs was not enough on its own: a
			-- Highlight's contour is a fixed ~2px in SCREEN space, so on a machine
			-- that is eighty pixels tall it is a hairline you have to look for. The
			-- two jobs are different at the two ranges — far away it has to say
			-- "there is a thing over there", which needs MASS; up close it has to
			-- say "this is its edge", which needs PRECISION and must not wash out
			-- the object you are looking at. So the fill ramps between them and the
			-- contour stays constant.
			FarFillTransparency = 0.55,
			-- Studs at which the far value is fully reached; below NearFillAt it is
			-- entirely the near value, and it lerps between the two.
			FarFillAt = 90,
			NearFillAt = 24,
		},

		-- PRESSING THE MACHINE. A ClickDetector on the model, so walking up and
		-- clicking it opens the screen — the prompt's key is now the shortcut
		-- rather than the only way in. Hover and press both answer: the Highlight
		-- steps up under the pointer, the plate pops, and both use the HUD's own
		-- hover and click samples so the machine sounds like the rest of the game.
		Click = {
			-- The click range is Select.ShowDistance, set by WorldPrompt from the
			-- same figure that shows the plate: what you can read you can press.
			-- Two radii would mean a plate you can see and cannot use.
			HoverSound = 10066931761,   -- Roblox first-party "Hover 01", as UIKit uses
			ClickSound = 10128760939,   -- "Select 01"
			HoverVolume = 0.3,
			ClickVolume = 0.5,
			-- What the prompt plate does under the pointer and on the press. The
			-- same feel UIKit.feel gives every button in the game, by hand, because
			-- a BillboardGui's contents are not a GuiButton.
			HoverGrow = 1.08,
			PressDrop = 0.93,
		},

		-- THE SCREEN, and it is NOT a panel. Everything floats on the blurred world
		-- — no white body, no ring, no moulded lip, no studs. The shell instance is
		-- still there (it carries the title, the close key and the layout box) but
		-- its surface is switched off, because a splice happens AT the machine and a
		-- solid menu in front of it hides the thing you walked over to use.
		--
		-- The dim is what keeps the floating controls readable against whatever the
		-- machine is doing behind them. Light: the blur is already doing most of
		-- the separating, and at 0.3 this stopped being "transparent" and became a
		-- dark panel with soft edges.
		Panel = {
			Aspect = 1.62,
			LeftLabel = "STRAND A",
			RightLabel = "STRAND B",
			EmptyGlyph = "+",
			Idle = "Choose two strands to splice.",
			Ready = "Ready to splice!",
			Button = "SPLICE",
			Dim = 0.62,
			BlurSize = 20,
		},

		-- THE STRANDS: six animals, each with ITS OWN ICON.
		--
		-- They were ViewportFrames of the real rigged models for one revision, which
		-- is free and unmistakable and also wrong for a picker cell: a lit 3D rig at
		-- 60px reads as a dark blob, and every one of them needed its own camera.
		-- Flat art is what a cell that size wants.
		--
		-- ALL SIX ARE FREE CREATOR STORE ASSETS, verified here by hand — resolved
		-- from their store pages (an image served from a store page is a DECAL
		-- WRAPPER, so the id below is the TEXTURE inside it, not the page) and then
		-- PreloadAsync'd in this group-owned place: all six Success, no experience
		-- grant needed. That is the whole reason for using store assets rather than
		-- uploading a matched set — an upload 403s here until the experience is
		-- granted access to each id by hand.
		--
		-- FIVE OF THE SIX ARE EMOJI, and that is the closest thing to a family this
		-- place could get for free: same weight, same flat shading, same
		-- cut-out-on-transparent. Every candidate was rendered at 1:1 ON MID GREY
		-- before being picked, because roughly half the free "icon" decals in the
		-- store carry an opaque white box that is invisible against a pale panel and
		-- obvious against anything else. The ghost is the odd one out — outlined
		-- cartoon rather than emoji — and stays because no emoji ghost in the store
		-- came back transparent.
		Strands = {
			{ Name = "Chicken DNA",  Rarity = "Common",    Icon = "rbxassetid://83369122551896" },
			{ Name = "Dog DNA",      Rarity = "Common",    Icon = "rbxassetid://453168269" },
			{ Name = "Cat DNA",      Rarity = "Uncommon",  Icon = "rbxassetid://4251852174" },
			{ Name = "Scorpion DNA", Rarity = "Rare",      Icon = "rbxassetid://883464404" },
			{ Name = "Ghost DNA",    Rarity = "Epic",      Icon = "rbxassetid://132829823221460" },
			{ Name = "Bigfoot DNA",  Rarity = "Legendary", Icon = "rbxassetid://4754948535" },
		},
		-- What a strand with no Icon of its own falls back to.
		StrandIcon = COIN_S,

		-- THE MACHINE'S OWN SCREEN. There is a 3D-text model on the front of the
		-- monitor reading "TEXT + TEXT" — eight letter meshes named uni0054 and so
		-- on, one mesh per glyph, from a 3D-text plugin.
		--
		-- IT CANNOT BE RETYPED. The only glyphs in the place are T, E, X and +, so
		-- there is no D, no N, no A and no digits to spell anything else with. The
		-- letters are therefore HIDDEN and a SurfaceGui is put on the same bounding
		-- box part instead, which can say anything and costs nothing.
		Display = {
			-- What it reads before anything is chosen, and the thing the player sees
			-- from across the plot.
			DefaultLeft = "DNA 1",
			DefaultRight = "DNA 2",
			Operator = "+",
			-- Pixels of SurfaceGui canvas per stud. The part is about 2.2 x 2.6
			-- studs, so this gives a ~440 x 520 canvas — enough that the type is not
			-- a blur up close.
			PixelsPerStud = 200,
			Colour = Color3.fromRGB(150, 236, 255),
			-- The name is shortened to its first word on the screen: "Scorpion DNA"
			-- across a 2-stud monitor is four-point type, and every entry ends in
			-- "DNA" anyway, so the word that tells them apart is the one that gets
			-- the room.
			ShortNames = true,
		},

		-- THE CUTSCENE. Pressing SPLICE hands the screen over to the machine: the
		-- menu goes, the camera takes a framing shot, the gravity rig lights up,
		-- two helices fly in and become one, and the screen whites out.
		--
		-- THE GRAVITY RIG is Workspace.Gravity — an invisible 29-stud box sitting
		-- on the machine carrying 27 particle emitters and a point light. It ships
		-- switched ON, which is why the machine has always had a column of sparks
		-- standing in it doing nothing. It is switched OFF at join and only runs
		-- for the length of a splice, which is what makes it read as an event.
		--
		-- Client-side, like everything else here: what one player sees the machine
		-- do is not yet anybody else's business, and there is no server to make it
		-- so.
		Cutscene = {
			VfxPartName = "Gravity",

			-- The wind-up, cut before its own tail. The asset is 4.03s and its last
			-- second is a decay that would run underneath the impact sound; stopping
			-- at 3.03 lands the two back to back instead of overlapping.
			BuildSound = 101937236820642,
			BuildCut = 1.0,          -- seconds trimmed off the END
			BuildVolume = 0.65,
			-- The payoff, on the frame the two helices become one.
			FinishSound = 9125661438,
			FinishVolume = 0.8,

			-- The white-out. In fast, out slow: the flash IS the cut, and a slow
			-- fade in reads as a fog rolling over rather than as an event.
			FlashIn = 0.12,
			FlashHold = 0.16,
			FlashOut = 0.65,

			-- Where the camera stands, in studs relative to the machine's own
			-- bounding box centre. Chosen off the place rather than picked: far
			-- enough out that the whole tank and the monitor are both in frame, and
			-- above centre so the floor ring of the gravity rig shows.
			CameraOffset = Vector3.new(0, 5.5, 26),
			CameraLookLift = 1.5,    -- studs above centre the camera aims
			CameraEase = 0.8,        -- seconds to glide in, and again to hand back

			-- The two helices fly in from this far either side of the tank, on the
			-- machine's own left/right axis, and meet at the centre.
			Spread = 7.5,
			-- Revolutions each helix turns on the way in. They counter-rotate, so
			-- the pair reads as two strands winding together rather than as two
			-- copies of one object sliding.
			Turns = 2.5,
			-- Seconds. The whole thing is BuildCut-trimmed sound plus the flash, so
			-- these add up to the build sound's playable length.
			Approach = 2.1,
			Merge = 0.55,
			-- How long the merged helix is held before the camera hands back.
			Settle = 0.9,

			-- MORE GOING ON, because a splice that is two objects sliding together
			-- is not an event. Each of these is cheap and none of them needs art.

			-- THE HELIX IN THE TANK SPINS UP. DnaSpin owns that rotation and reads
			-- this multiplier off an attribute on the machine, so the wind-up is a
			-- number here rather than a second copy of the spin loop. Ramped in over
			-- the approach and released when the cutscene ends.
			SpinBoost = 9,
			SpinAttribute = "SpinBoost",

			-- CAMERA SHAKE, in studs of positional jitter at full strength. Ramps
			-- with the approach and peaks at the merge. Small: this is a machine
			-- working, not an earthquake, and past about 0.3 it reads as the camera
			-- being broken rather than the machine being powerful.
			Shake = 0.16,

			-- THE FOV PUNCH on the merge frame — a fast pull-in and a slower
			-- release, which is what sells an impact when there is no impact to
			-- render. Degrees off the camera's own FieldOfView.
			FovKick = -9,
			FovIn = 0.12,
			FovOut = 0.5,

			-- The tank's own light, pulsed up as the two strands close. Uses the
			-- gravity rig's PointLight rather than adding one: it is already there,
			-- already aimed and already switched on for the cutscene.
			LightPeak = 6,
		},
	},

	-- WALK-UP TRANSITS. A plate on a piece of the world that moves you somewhere
	-- else when you click it — the same WorldPrompt widget the DNA machine uses,
	-- with a teleport behind it instead of a screen.
	--
	-- This is the honest version of a portal: the Portals panel is a menu you open
	-- from anywhere, and that is right for crossing the map, but the mouth of a
	-- tunnel should be a thing you walk to. The cave's Entry arch is one: it is
	-- literally the way through to the mine.
	--
	-- CLIENT-SIDE, like everything else here: a client owns its own character, so
	-- PivotTo on it is a real teleport and not a mock. Nothing is granted and
	-- nothing replicates.
	Transit = {
		-- Studs above Pos to release the character, same rule Teleport uses: the
		-- world is blocky and a landing exactly on a surface intersects it.
		DropHeight = 6,
		Places = {
			{
				-- Workspace.Entry: a 32x22x20 neon block at the east end of the
				-- cave (x 272, z -62), which is the cave's mouth toward the mine.
				-- It is already there and already lit; all it was missing was
				-- anything telling you it does something.
				Part = "Entry",
				ActionText = "Enter",
				ObjectText = "MINESHAFT",
				-- The Mineshaft portal's own landing spot, measured the same way:
				-- where a character actually COMES TO REST after being dropped
				-- there, read off HumanoidRootPart rather than off the geometry.
				Pos = Vector3.new(739.5, 17.7, -244),
				-- Closer than the machine's 140. A tunnel mouth is a thing you walk
				-- up to, and a plate readable from the far side of the cave would
				-- be floating in the dark over nothing you can see.
				ShowDistance = 55,
				Height = 3.4,
				Aspect = 3.15,
				-- The arch is 22 studs tall and the plate sits at its box centre by
				-- default, which is inside the neon. Lifted clear of the top.
				Rise = 13,
			},
		},
	},

	-- THE LOADING SCREEN, which replaces Roblox's default one. Lives in
	-- ReplicatedFirst because that is the only container whose scripts run before
	-- the rest of the game arrives; anywhere else and the player has already seen
	-- the world load in behind it.
	--
	-- The bar is driven by a REAL count. ContentProvider:PreloadAsync takes a
	-- per-asset callback, so the fraction is assets actually fetched rather than a
	-- timer pretending to be progress — which is the thing that makes a fake bar
	-- obvious the second the connection is slow.
	--
	-- WHAT IS PRELOADED: every rbxassetid string anywhere in this table, found by
	-- walking it. That is deliberate over a hand-kept list, which would rot the
	-- first time somebody adds a product. Audio is NOT preloaded — the three music
	-- tracks are 200-320 seconds each and would hold the player at the door for
	-- something that streams perfectly well on its own.
	Loading = {
		Title = "FIND A DNA",
		Subtitle = "Splice it. Grow it. Hatch it.",

		-- The floor stops the screen flashing past on a warm cache, which reads as
		-- a glitch rather than as a fast load. The ceiling is the more important
		-- number: one asset that never resolves must not trap somebody at the door
		-- forever, so at MaxWait the screen leaves regardless of the count.
		MinTime = 1.4,
		MaxWait = 20,
		FadeTime = 0.45,

		-- Seconds per revolution of the coin above the title. Slow: it is a
		-- flourish, and a fast spin on a screen somebody stares at reads as
		-- impatience.
		SpinPeriod = 3.2,

		-- Rotated while the bar fills. Written to be read in about two seconds
		-- each, because that is all the time most of them will get.
		Tips = {
			"Pets boost every harvest. Equip your best.",
			"Rarer strands hatch from rarer eggs.",
			"Codes drop on TikTok " .. TIKTOK .. "!",
			"The mine runs deeper than it looks.",
			"Rebirth multiplies everything you have earned.",
			"Check back daily — day seven is the good one.",
		},
		TipEvery = 3.2,
	},

	-- ZONE MUSIC. One looping track per area, picked from where the character is
	-- standing and crossfaded when it changes. Client-side and needs no server:
	-- what a player hears is nobody else's business.
	--
	-- THE CAVE ID IS A CREATOR STORE PAGE ID and it works verbatim. That is the
	-- opposite of the rule for artwork — a store page for an image serves a Decal
	-- wrapping the real texture, so the page id fails on an ImageLabel — but audio
	-- has no wrapper: all three ids below were set on a Sound and reported
	-- IsLoaded with a real TimeLength (205s, 211s, 322s). No experience grant is
	-- needed either; these are store assets, not user uploads.
	--
	-- Zones are BOXES, in world space, and the order matters: the first one that
	-- contains the character wins, so a region sitting inside another must come
	-- first. Everything outside every box gets Default.
	--
	-- The numbers are MEASURED off the place, not chosen:
	--   Cave      the enclosure at x 662..903, z -437..-160 — its floor and
	--             ceiling are the two 241 x 3.3 x 277 slabs at y -0.4 and 86.8,
	--             and inside it is a dark timbered mine interior.
	--   Mineshaft Workspace.mineshaft, a 69 x 6 x 66 plate at (739.5, 12, -244)
	--             INSIDE that enclosure — hence first in the list. The box is
	--             padded 8 studs on each side so stepping a stud off the plate
	--             does not flip the track, and 50 studs tall because a player
	--             stands above the plate, not in it.
	--
	-- NOT covered: the Teleport list's "The Mine" at (28, -206, 11670) is a
	-- separate area 12,000 studs away and was not named in the brief, so it plays
	-- the overworld track. Giving it Mineshaft is one more entry in Zones.
	Music = {
		Tracks = {
			Overworld = 117798839485945,
			Mineshaft = 135969530798848,
			Cave = 131824229597484,
		},
		-- FIRST MATCH WINS, so a region inside another is listed first: the
		-- mineshaft plate sits inside the mine cavern and therefore comes before it.
		Zones = {
			{ Track = "Mineshaft", Centre = Vector3.new(739.5, 34, -244),
			  Size = Vector3.new(85, 50, 82) },
			-- THE MINE CAVERN, not the cave — the box around the rails, the carts
			-- and the mineshaft. It has carried the "Cave" track since the zones
			-- were first measured and it keeps it: it is a cavern, and the track
			-- suits it. The NAME is the only thing that was ever misleading, and
			-- Teleport.Places records what that cost.
			{ Track = "Cave", Centre = Vector3.new(783, 43, -298.4),
			  Size = Vector3.new(241, 88, 277) },
			-- THE ACTUAL CAVE, which had no zone at all and so played Overworld —
			-- audible the moment the portal above started landing here instead of
			-- in the mine. Measured off the place: the 27 torches span x 161..305,
			-- z -79..65, the floor slab tops out at y -18.2 and raycasts put the
			-- ceiling between y -1 and 14. The box is that, with a little margin,
			-- and capped at y 12 so it does not catch anyone walking on the
			-- plateau above the cave.
			{ Track = "Cave", Centre = Vector3.new(233, -5, -7),
			  Size = Vector3.new(160, 34, 156) },
		},
		Default = "Overworld",

		-- Well under the UI, which is the mix every one of these games uses: music
		-- is the floor of the sound stage, not an event on it.
		Volume = 0.35,
		-- Seconds to cross from one track to the next. Long: a hard cut at a cave
		-- mouth is the thing that makes zone music feel like a switch being thrown.
		Fade = 2.5,
		-- How often the character's position is tested. A box test is a handful of
		-- comparisons, so this could run every frame and does not need to.
		Poll = 0.4,
	},

	-- The two counters under the HUD's tile grid.
	--
	-- DISPLAY STATE, like the inventory roster and the daily streak: there is no
	-- economy, no DataStore and nothing that earns or spends, so these are
	-- hand-set numbers that never move on their own. The seam is the HUD's
	-- HUDSetCurrency BindableFunction — Invoke("Coins", n) — which is what a
	-- server-fed client script will drive the day one exists.
	--
	-- Icons are picked from art already in the game: COIN_S is the game's own
	-- branded coin at its smallest tier, and the gem is the one the shop's
	-- smallest gem product draws. A counter showing different art from the shop
	-- that sells it reads as a different currency.
	Currency = {
		Coins = 12450,
		Gems = 86,
		CoinIcon = COIN_S,
		GemIcon = GEM_S,
		CoinGrad = GOLD,
		GemGrad = CYAN,
	},

	-- The Daily Rewards panel. Seven days on a ladder: six small cards in a 3x2
	-- grid down the left, and a seventh that is its own tall plate down the right
	-- because the week's payoff should not look like another Tuesday.
	--
	-- NOTHING HERE PERSISTS. ServerScriptService is empty — no DataStore, no clock,
	-- no grant — so Streak below is DISPLAY STATE, hand-set, exactly as the
	-- inventory's roster is. Claiming pops the card and advances the streak on this
	-- client only; rejoin and it is back to whatever Streak says. The day a real
	-- daily system exists, the seam is DailyController.readStreak(), and everything
	-- else on this screen already works off it.
	--
	-- Streak = days ALREADY CLAIMED, so the claimable day is Streak + 1. At 0 the
	-- panel opens on the reference's own state: Day 1 gold and offering a Claim
	-- pill, Days 2..7 waiting.
	Daily = {
		Title = "Daily Rewards!",
		-- The HUD's own DailyGiftSlot icon, so the tile and the panel it opens are
		-- one object — the same rule the Collection panel follows.
		TitleIcon = "rbxassetid://115491811384418",

		Streak = 0,

		-- Show the panel on join whenever a reward is waiting. The whole point of a
		-- daily is that the player does not have to remember to come looking; set
		-- false to make the HUD tile the only way in.
		AutoOpen = true,

		-- Copy. Ready is shown while a reward is waiting, Waiting once the day's
		-- card has been taken — the line never disappears, because an empty band
		-- above the grid reads as a panel that failed to load.
		ReadyLabel = "Reward ready to Claim!",
		WaitingLabel = "Come back tomorrow!",
		ClaimLabel = "Claim!",
		ClaimedLabel = "Claimed",
		DayLabel = "Day %d",

		-- Six cards, in order, left to right then down. Qty is display text and is
		-- drawn as a yellow tag over the art's bottom-right; omit it and nothing is
		-- drawn. Grad names a palette pair, same vocabulary the shop cards use, and
		-- the sequence is deliberately varied — six cards in one gradient is a
		-- colour field, not six rewards.
		-- Tint is optional and MULTIPLIES the art (ImageColor3). Three of these seven
		-- rewards are eggs and there is exactly one egg image in the game, so without
		-- it Days 3, 6 and 7 are the same cream egg three times and the ladder stops
		-- reading as three different prizes. The source is cream with its own shading
		-- and its own black outline, so a LIGHT tint recolours it and keeps both;
		-- a dark one flattens the shading into a blob, which is the mistake the
		-- Galaxy Helix egg made before it.
		Days = {
			{ Name = "Coin Stash",  Qty = "x3",   Icon = COIN_S,                        Grad = GOLD },
			{ Name = "Gem Pouch",   Qty = "x25",  Icon = GEM_S,                         Grad = GREEN },
			{ Name = "Lucky Egg",   Qty = "x1",   Icon = EGG,                           Grad = PINK,
			  Tint = Color3.fromRGB(255, 226, 140) },
			{ Name = "Coin Chest",  Qty = "x5",   Icon = COIN_L,                        Grad = CYAN },
			{ Name = "Gem Hoard",   Qty = "x150", Icon = GEM_M,                         Grad = GREEN },
			{ Name = "Party Egg",   Qty = "x8",   Icon = EGG,                           Grad = VIOLET,
			  Tint = Color3.fromRGB(255, 176, 214) },
		},

		-- Day seven, on its own plate. Header is drawn as two labels so the two
		-- halves can take different colours the way the reference does; Lines are
		-- the contents, one per row, plain white under it.
		Mega = {
			HeaderLead = "OP",
			HeaderRest = "REWARDS!",
			Lines = { "x3 Exclusive Galaxy Egg", "One Random Crown" },
			Art = EGG,
			-- Cyan, against a violet plate: the two eggs on the grid are gold and
			-- pink and this one has to be neither, and a violet egg on the violet
			-- plate would dissolve into it. Light, for the reason in Days above.
			ArtTint = Color3.fromRGB(176, 236, 255),
			-- The crown is a dark, detailed badge that collapses into a smudge at
			-- strip size and is fine LARGE — which this is. It sits behind and below
			-- the egg so the two read as a pile rather than as two icons.
			ArtExtra = "rbxassetid://8002852553",
			DayLabel = "Day 7",
			Grad = VIOLET,
		},
	},

	-- The Collection panel. Structurally the inventory's sibling — rail on the
	-- left, grid in the middle, search top-right — so it borrows that panel's
	-- geometry language and the SHOP's palette, same as the inventory does. What
	-- makes it an index rather than an inventory is that it shows the whole
	-- roster including what the player has NOT got, and counts the difference.
	Index = {
		Title = "Collection!",
		-- The commissioned index icon — the SAME id the HUD's IndexSlot carries, so
		-- the tile you press and the corner of the panel it opens are one object.
		-- They had drifted: the HUD moved to the uploaded set on 2026-09-20 and this
		-- was left on the old Creator Store book (111762720282001), which is a
		-- different drawing in a different style sitting in the panel's loudest
		-- corner. Before this the crown (8002852553, the inventory rail's Index
		-- icon) was here and read as a rank badge rather than as a collection.
		TitleIcon = "rbxassetid://128325335852740",
		SearchIcon = "rbxasset://textures/ui/SearchIcon.png",
		SearchPlaceholder = "Search",

		-- Drawn bottom-right over the grid, the way the reference has it.
		CollectedLabel = "Collected",

		-- There is no filter row. Four inert icon tabs sat between the title and
		-- the search field and were cut for the same reason the inventory's sort
		-- pill was: they promised filtering the panel cannot do, and the icons
		-- standing in for paw / star / rainbow / sparkle were unrecognisable.
		-- Bringing it back means putting a Filters table here; nothing else reads it.

		-- The left rail. Unlike the inventory's, these are LABELLED plates rather
		-- than icon cells, because the reference's are — and because four words
		-- carry categories that four unfamiliar icons could not.
		--
		-- Only Pets has anything behind it. The rest are inert, and they are drawn
		-- unselected rather than hidden: an index with one category reads as
		-- broken, and the shape is what is being built here.
		Rail = {
			{ Name = "Pets",      Category = "Pets" },
			{ Name = "Mutations", Category = "Mutations" },
			{ Name = "Cars",      Category = "Cars" },
			{ Name = "DNA",       Category = "DNA" },
		},
		-- The odd one out, pinned to the rail's bottom in its own colour.
		Reward = { Name = "Rewards", Grad = GREEN },

		-- Grid columns at full size; the layout drops one at a time while a cell
		-- would come out under MinCell pixels, exactly as the shop and inventory do.
		-- Rows are fixed and COLUMNS are derived: the cell is sized off the row
		-- count and then as many columns as fit the width are used. Pinning both
		-- left a wide empty margin down the right of the grid, because the cell
		-- comes out of whichever axis is tighter and that is always the height here.
		Rows = 3,
		MinCell = 64,

		-- The patch behind each pet is the inventory's procedural SCRIBBLE in the
		-- rarity colour, not a soft blob image — the same ~11 tilted bars in a
		-- CanvasGroup, for the same reason it exists there: no scribble texture
		-- can be fetched in this place, and a clean circle is a dot, not a scribble.
		Scribble = {
			Strokes = 11,
			BarHeight = 0.16,
			Tilt = 6,
			Angle = -32,
			Fade = 0.42,
			MaxWidth = 0.84,
			-- Uncollected entries get a flat grey one. The rarity is part of the
			-- reward for finding the pet, so it is not spent on a silhouette.
			LockedColour = Color3.fromRGB(214, 216, 228),
		},

		-- Entries the player has not collected draw as the FLAT DARK SILHOUETTE
		-- pass that already exists for the pet outline — same model, same viewport,
		-- every part recoloured and its texture stripped. That is what makes the
		-- counter below mean anything, and it costs no new art in a place where
		-- new art costs an experience-access grant each time.
		-- DARK. At a pale grey the silhouette all but vanished against the panel's
		-- own near-white body — an uncollected pet has to read as a shape from
		-- across the grid, which is the whole point of showing it at all.
		LockedTint = Color3.fromRGB(96, 100, 124),

		-- The roster is Inventory.Pets for what the player HAS, plus the list below
		-- for what exists and they have not got. Owned is decided at the seam in
		-- IndexController, which today reads Count > 0 off Inventory.Pets and
		-- tomorrow reads replicated state — adding a pet there needs nothing here.
		--
		-- Undiscovered is a separate list rather than an Owned = false flag inside
		-- Inventory.Pets, because that table means "the player's stacks" and a row
		-- in it for something they do not own would be a lie the inventory panel
		-- would then have to filter back out.
		PetSource = "Inventory",
		Undiscovered = {
			{ Name = "Helix Hatchling", Rarity = "Uncommon",  Model = "Chicken" },
			{ Name = "Gene Gremlin",    Rarity = "Rare",      Model = "Scorpion" },
			{ Name = "Codon Cub",       Rarity = "Rare",      Model = "Dog" },
			{ Name = "Marrow Moth",     Rarity = "Epic",      Model = "ghostly" },
			{ Name = "Chromo Cat",      Rarity = "Epic",      Model = "Cat" },
			{ Name = "Titan Telomere",  Rarity = "Legendary", Model = "Bigfoot" },
			{ Name = "Null Sequence",   Rarity = "Legendary", Model = "ghostly" },
			{ Name = "Plasmid Pup",     Rarity = "Common",    Model = "Dog" },
		},
	},

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

		-- The left rail, top to bottom, overhanging the panel's left edge. The cell
		-- height is DERIVED from how many entries are here, so adding or removing
		-- one needs no other change.
		--
		-- FIVE CATEGORIES, and the rail is no longer inert. Category is what the
		-- grid switches on: "Pets" is the one with a roster behind it (Inventory.Pets
		-- below), and the other four draw Empty instead. That is why a SELECTED
		-- highlight is back after being cut twice — it was cut when every cell did
		-- nothing and the highlight promised navigation the panel did not have.
		-- Pressing a cell now genuinely changes what the grid shows, so the
		-- highlight is describing something true.
		--
		-- ICON DEBT, all five of it, and deliberate. Nothing here is drawn for the
		-- slot it sits in — every id is borrowed from somewhere else in the game,
		-- because an upload 403s in this group-owned place until the experience is
		-- granted access by hand (see the header). They are at least all from the
		-- branded set, so the rail reads as one object:
		--   Pets    the Collection tile's paw book — the ONLY paw in the place
		--   Potions the old rail's flask-ish gem; the nearest thing to a bottle
		--   DNA     COIN_S, which is literally a helix struck on a coin
		--   Cars    the HUD CarSlot truck, the same drawing as the tile
		--   Charms  GEM_M, a trinket standing in for a charm
		-- Each wants its own glyph; swapping one in is a line here and nothing else.
		Rail = {
			{ Name = "Pets",    Category = "Pets",    Icon = "rbxassetid://128325335852740" },
			{ Name = "Potions", Category = "Potions", Icon = "rbxassetid://743807896" },
			{ Name = "DNA",     Category = "DNA",     Icon = COIN_S },
			{ Name = "Cars",    Category = "Cars",    Icon = "rbxassetid://88572848097120" },
			-- GEM_M, the CLUSTER, not GEM_S. The single pale gem sat directly under
			-- the Potions cell's own pale diamond and the two read as one item
			-- listed twice; three stones together is a different silhouette at rail
			-- size, which is the only size that matters here.
			{ Name = "Charms",  Category = "Charms",  Icon = GEM_M },
		},
		-- Which cell the panel opens on, and the one category with content.
		DefaultCategory = "Pets",
		-- Drawn over the grid for a category with nothing in it. An empty grid with
		-- no words on it reads as a panel that failed to load; this says the shelf
		-- is empty, which is the truth and is not the same thing.
		EmptyLine = "Nothing here yet!",
		EmptySub = "%s are coming soon.",

		-- Rarity drives a tile's gradient and nothing else. Reusing the shop's five
		-- pairs rather than inventing a sixth is what keeps the two panels one family.
		Rarities = {
			Common = GREEN, Uncommon = CYAN, Rare = VIOLET,
			Epic = PINK, Legendary = GOLD,
		},

		-- What a pet with no Model of its own draws.
		PetIcon = "rbxassetid://128442519585600",

		-- A pet tile is not a button and must not sound like one. The HUD's tick
		-- is a UI click; picking up a creature wants something softer, so the pet
		-- grid gets its own hover sample and every actual button keeps UIKit's.
		PetHoverSound = 6895079853,

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

		-- The soft-edged blob behind a floating pet, tinted with the pet's rarity
		-- colour. Neutral white-on-transparent so one image serves all five
		-- rarities — ImageColor3 multiplies, so a tinted source could only ever be
		-- darkened towards its own hue.
		-- Verified to load in this group-owned place (PreloadAsync: Success).
		-- A soft-edged CIRCLE. The soft-edged square (1316045217, also verified)
		-- filled the cell corner to corner and read as the plastic plate this was
		-- meant to replace, only blurrier.
		PetBlob = "rbxassetid://2851920938",

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
