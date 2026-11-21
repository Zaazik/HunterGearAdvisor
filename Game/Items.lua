-- Item records: tooltip lines parsed with the client's templates, plus C_Item.GetItemStats.
-- The tooltip is the main source (it is what the player sees and includes enchants, effects,
-- weapon speed and red restriction lines); GetItemStats fills stats the text has no template
-- for and is kept next to the parse so /hga dump can show disagreements.
local _, ns = ...
local Items = {}
ns.Items = Items

local cache = {}   -- link -> record
local pending = {} -- itemID -> true while waiting for item data
local parser

local function getParser()
	if not parser then parser = ns.Parse.New(ns.BuildTemplates()) end
	return parser
end

local function isRed(c)
	return c ~= nil and c.r ~= nil and c.r > 0.95 and c.g < 0.25 and c.b < 0.25
end

-- GetItemStats key (without ITEM_MOD_ and _SHORT) -> our stat key.
local API_MAP = {
	AGILITY = "AGI", STRENGTH = "STR", STAMINA = "STA", INTELLECT = "INT", SPIRIT = "SPI",
	HEALTH = "HEALTH", MANA = "MANA",
	ATTACK_POWER = "AP", RANGED_ATTACK_POWER = "RAP", MELEE_ATTACK_POWER = "MAP",
	MANA_REGENERATION = "MP5", HEALTH_REGEN = "HP5", HEALTH_REGENERATION = "HP5",
	DAMAGE_PER_SECOND = "DPS", ATTACK_POWER_VS_BEAST = "AP_VS_BEAST",
	BOWS = "SKILL_BOWS", GUNS = "SKILL_GUNS", CROSSBOWS = "SKILL_CROSSBOWS",
	-- the melee weapon lines (Score.MELEE_SKILL): the Forever client's ITEM_MOD_<LINE>_SHORT stat names (GlobalStrings
	-- 58882-58908: TWOHANDED_AXES, TWOHANDED_MACES, TWOHANDED_SWORDS, AXES, DAGGERS, FIST_WEAPONS, MACES, POLEARMS, STAVES,
	-- SWORDS), the names GetItemStats keys its table by (its statTable is a LuaValueVariant in Forever
	-- ItemDocumentation.lua:1004-1017; the in-game dumps of 2026-11-12 hold ITEM_MOD_*_SHORT keys, the ranged lines' among
	-- the client's names above); raid-mode design 18.9
	TWOHANDED_AXES = "SKILL_2H_AXES", TWOHANDED_MACES = "SKILL_2H_MACES", TWOHANDED_SWORDS = "SKILL_2H_SWORDS",
	AXES = "SKILL_AXES", DAGGERS = "SKILL_DAGGERS", FIST_WEAPONS = "SKILL_FIST", MACES = "SKILL_MACES",
	POLEARMS = "SKILL_POLEARMS", STAVES = "SKILL_STAVES", SWORDS = "SKILL_SWORDS",
}
-- Keys only GetItemStats can give (no tooltip template): copied into the stats.
local API_ONLY = { MAP = true }
Items.API_MAP = API_MAP

local function normalizeApi(raw)
	local out = {}
	for k, v in pairs(raw or {}) do
		local short = k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")
		local key = API_MAP[short]
		if key then out[key] = (out[key] or 0) + v end
		if k == "RESISTANCE0_NAME" then out.ARMOR = (out.ARMOR or 0) + v end
	end
	return out
end

-- The damage procs of an item record, linked to the Forever DB2 (Game/ProcData.lua, tools/gen_proc_data.py). Each proc
-- Parse reads ({ avg, hits, equip, school }) is linked to the one ProcData[itemID] entry of its kind (an "Equip:" line:
-- "equip"; a "Chance on hit:" line: "hit") whose mean is the parsed average within 0.5 (the tooltip's range is the
-- entry's min and max, its average their midpoint, the entry's mean wowsims'): the proc takes the entry's school
-- ("physical" when the SchoolMask holds the physical bit, wowsims SpellSchool.Matches; the mask as schoolMask),
-- defense (its DefenseType), crit (false: the spell cannot crit) and, for an equip aura, mask, chance, ppm and icd,
-- and linked = true. A proc with no such entry, or with two (an item newer than build 70888, a level-scaled damage, a
-- text that matches two), stays unlinked: Score prices it with wowsims' rule for a damage spell of no stated
-- DefenseType (defense 0: its table by the school its tooltip names, Parse) that can crit, at Parse's hits and the
-- measured rate alone (Score.ProcRateSource; raid-mode design 4.6.2, approximation A14). A linked entry's damage over time
-- (its dot: tick, period, ticks, canCrit) comes with it (raid-mode design 17.4: a direct damage and its damage over time
-- priced together, Score.ProcValue).
-- Two kinds of entry have no mean a tooltip range can match, and link instead by item and kind to the item's effect lines
-- of that kind Parse leaves not counted: a "Chance on hit:" line (ITEM_SPELL_TRIGGER_ONPROC) with no damage range for
-- "hit", an "Equip:" line (ITEM_SPELL_TRIGGER_ONEQUIP) Parse reads nothing of for "equip". The linked line becomes a proc
-- of its own (a "hit" one rolls on its weapon's hits, "weapon", as a chance on hit does; an "equip" one by its mask) and
-- is marked counted (effect.linked); a line one entry links is open to no other. The procs and the effects are the
-- parse's own tables, filled in place.
-- - A fixed direct damage (min == max above 0: a damage effect of Variance 0, whose tooltip shows one number where Parse
--   needs a range; raid-mode design 24.2, approximation DA4) no parsed proc links: the one such line that states its
--   amount as damage (Parse.StatesDamage), a line no other such entry of the kind claims; its proc takes the entry's mean
--   as its direct damage (avg) and its dot. No such line, two, or a line two such entries claim leave it unlinked and
--   unpriced, as an item newer than build 70888.
-- - A damage over time and no direct damage (dot, avg 0): the tooltip texts of a damage over time take many forms (DB2
--   Spell descriptions "$s1 Nature damage every $t1 sec for $d", "bleed for $o1 damage over $d"; ruRU likewise) and
--   Parse reads none of them; it links (raid-mode design 17.4) to the item's one such line the fixed entries leave (no
--   avg on its proc: no direct damage). With no such line, more than one, or more than one such entry of the kind, the
--   entry stays unlinked and unpriced (approximation DA2: an item newer than build 70888, a text no line reads).
local function linkFields(p, match, kind)
	p.linked = true
	p.school = match.school % 2 == 1 and "physical" or "magic"
	p.schoolMask, p.defense, p.crit = match.school, match.defense, match.crit
	p.spell = match.spell
	p.dot = match.dot
	-- the factor its trigger deals against creature types (wowsims' VersusBonuses row, Game/ProcData.lua versus;
	-- Score.VersusFactor)
	p.versus = match.versus
	-- the rate wowsims' override data gives the entry (Game/ProcData.lua ppm or chance with its source; a
	-- chance-on-hit entry has a ppm only so), Score.ProcRateSource
	p.source = match.source
	if kind == "equip" then
		p.mask, p.chance, p.ppm, p.icd = match.mask, match.chance, match.ppm, match.icd
		-- wowsims rolls it on every hit of its mask (Game/ProcData.lua always; Score.ProcRateSource)
		p.always = match.always == true
		-- it hears the main hand's melee hits alone (Game/ProcData.lua mainHand; Score.ProcRate)
		p.mainHand = match.mainHand == true
	else
		p.ppm = match.ppm
	end
end
-- an entry with a damage over time and no direct damage (Game/ProcData.lua: avg 0 beside a dot)
local function dotOnly(e) return e.dot ~= nil and e.avg == 0 end
-- an entry with a fixed direct damage (Game/ProcData.lua: min == max above 0, the floored base points of Variance 0)
local function fixedDirect(e) return e.avg > 0 and e.min == e.max end
-- an effect line of the kind Parse leaves not counted that no entry links yet
local function openLine(ef, kind)
	if ef.linked then return false end
	if kind == "hit" then return ef.kind == "proc" and ef.avg == nil end
	return ef.kind == "equip"
end
-- the linked line's proc: the entry's fields, the line's text, avg (nil for no direct damage)
local function lineProc(procs, line, entry, kind, avg)
	local p = { text = line.text, avg = avg }
	if kind == "hit" then p.hits = "weapon" else p.equip = true end
	linkFields(p, entry, kind)
	line.linked = true
	procs[#procs + 1] = p
end
local NO_ENTRIES = {}
local function linkProcs(itemID, procs, effects)
	if type(effects) ~= "table" then error("HunterGearAdvisor: Items.LinkProcs without the parse's effects: " .. tostring(effects), 2) end
	local entries = ns.ProcData[itemID] or NO_ENTRIES
	local taken = {} -- the entries a parsed proc links
	for _, p in ipairs(procs) do
		local kind = p.equip and "equip" or "hit"
		local match, count = nil, 0
		for _, e in ipairs(entries) do
			if e.kind == kind and not dotOnly(e) and math.abs(e.avg - p.avg) <= 0.5 then match, count = e, count + 1 end
		end
		if count == 1 then
			linkFields(p, match, kind)
			taken[match] = true
		else
			p.linked = false
			p.defense, p.crit = 0, true
		end
	end
	for _, kind in ipairs({ "hit", "equip" }) do
		-- the fixed direct damages: each entry's one open line of its amount, then the lines one entry alone claims
		local lineOf, claims = {}, {}
		for _, e in ipairs(entries) do
			if e.kind == kind and not taken[e] and fixedDirect(e) then
				local line, nLines = nil, 0
				for _, ef in ipairs(effects) do
					if openLine(ef, kind) and ns.Parse.StatesDamage(ef.text, e.min) then line, nLines = ef, nLines + 1 end
				end
				if nLines == 1 then
					lineOf[e] = line
					claims[line] = (claims[line] or 0) + 1
				end
			end
		end
		for _, e in ipairs(entries) do
			local line = lineOf[e]
			if line and claims[line] == 1 then lineProc(procs, line, e, kind, e.avg) end
		end
		-- the damage over time alone: the one open line left
		local entry, nEntries = nil, 0
		for _, e in ipairs(entries) do
			if e.kind == kind and dotOnly(e) then entry, nEntries = e, nEntries + 1 end
		end
		if nEntries == 1 then
			local line, nLines = nil, 0
			for _, ef in ipairs(effects) do
				if openLine(ef, kind) then line, nLines = ef, nLines + 1 end
			end
			if nLines == 1 then lineProc(procs, line, entry, kind, nil) end
		end
	end
	return procs
end
Items.LinkProcs = linkProcs

-- Asks the client for item data once; GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT
-- then invalidate the results so everything is evaluated again.
function Items.Request(itemID)
	if not pending[itemID] then
		pending[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
end

function Items.TooltipLines(link)
	local data = C_TooltipInfo.GetHyperlink(link)
	if not data or not data.lines then return nil end
	local lines = {}
	for i, l in ipairs(data.lines) do
		lines[i] = {
			left = l.leftText, right = l.rightText,
			leftRed = isRed(l.leftColor), rightRed = isRed(l.rightColor),
		}
	end
	return lines
end

-- Returns the record for an item link, or nil while the client has no data for it yet.
function Items.Get(link)
	if not link then return nil end
	local rec = cache[link]
	if rec then return rec end

	local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
	if not itemID then return nil end
	if not C_Item.IsItemDataCachedByID(itemID) then
		Items.Request(itemID)
		return nil
	end
	-- the item's set is C_Item.GetItemInfo's return 16, setID (Forever
	-- Blizzard_APIDocumentationGenerated/ItemDocumentation.lua, Nilable); the client's ItemSparse.ItemSet
	-- column holds 0 for an item outside any set, so 0 is no set as well
	local infoName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = C_Item.GetItemInfo(link)
	if not infoName then
		Items.Request(itemID)
		return nil
	end
	if setID == 0 then setID = nil end
	local lines = Items.TooltipLines(link)
	if not lines or #lines < 2 then return nil end

	local parsed = getParser():Lines(lines)
	local apiRaw = C_Item.GetItemStats(link) or {}
	local api = normalizeApi(apiRaw)

	local stats = parsed.stats
	local mismatch = {}
	for k, v in pairs(api) do
		if API_ONLY[k] then
			stats[k] = v
		elseif k == "DPS" and classID ~= 2 then
			-- ammo reports a DPS value of its own in GetItemStats (seen: 4.33 for 13-DPS bullets);
			-- only weapons have a weapon DPS
			if stats.DPS == nil then mismatch[#mismatch + 1] = "DPS: api " .. v .. " ignored (not a weapon)" end
		elseif stats[k] == nil then
			-- the text had no line for a stat the API reports: take the API value, note it
			stats[k] = v
			mismatch[#mismatch + 1] = k .. ": api " .. v .. ", tooltip none"
		elseif math.abs(stats[k] - v) > 0.06 then
			-- usually an enchant: the tooltip includes it, GetItemStats does not
			mismatch[#mismatch + 1] = k .. ": api " .. v .. ", tooltip " .. stats[k]
		end
	end

	rec = {
		link = link, id = itemID, name = lines[1].left, equipLoc = equipLoc,
		classID = classID, subclassID = subclassID, setID = setID,
		stats = stats, apiStats = api, apiRaw = apiRaw, mismatch = mismatch,
		speed = parsed.speed, reqLevel = parsed.reqLevel,
		restricted = parsed.restricted, restrictText = parsed.restrictText,
		uniqueEquipped = parsed.uniqueEquipped,
		procs = linkProcs(itemID, parsed.procs, parsed.effects), effects = parsed.effects, unparsed = parsed.unparsed,
		-- the on-use stat buff of the item's "Use:" effect (Game/UseData.lua, from the DB2), nil for none
		use = ns.UseData[itemID],
		lines = lines,
	}
	cache[link] = rec
	return rec
end

-- A per-location copy of a record, so two identical items are two different pieces.
function Items.Piece(rec, where)
	local piece = { where = where }
	return setmetatable(piece, { __index = rec })
end

-- Red restriction lines change when a skill, profession or reputation is learned: the
-- tooltip has to be read again then.
function Items.ClearCache()
	cache = {}
	parser = nil
end

local function onLoaded(_, itemID)
	if itemID and pending[itemID] then
		pending[itemID] = nil
		ns.Invalidate()
	end
end
ns.On("GET_ITEM_INFO_RECEIVED", onLoaded)
ns.On("ITEM_DATA_LOAD_RESULT", onLoaded)
