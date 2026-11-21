-- Auction prices for the pre-raid tools, from the price database Auctionator saves:
--   lua ah.lua <WTF/Account/<account>/SavedVariables/Auctionator.lua> <out.tsv> [realm key]
-- writes one line per item: itemID, price (copper), time (unix), count, gone ("true" / "false"), tab-separated, the
-- columns opt.py and rescore/avail.py read. Loaded with no arguments it returns its functions (tests/test_preraid.lua).
--
-- The saved layout, as Auctionator 349 writes it:
--   AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, [realm key] = house } (Source/Variables/Main.lua
--   InitializeDatabase). A realm key on Forever is "<realm or ruleset> <faction>", e.g. "PvP Horde"
--   (Source_ModernAH/Variables/Main.lua GetConnectedRealmRoot adds " " .. UnitFactionGroup on Forever).
--   A house is a table, or that table as a CBOR string: at logout the current realm's house is turned into CBOR with
--   C_EncodingUtil.SerializeCBOR, which the Forever client has (Blizzard_APIDocumentationGenerated/
--   EncodingUtilDocumentation.lua), and the other realms' houses are turned into CBOR one per login.
--   house = { [item key] = { m = the lowest buyout of the last scan that saw it, h = { [day] = the highest low price
--   of that day }, l = { [day] = the lowest low price }, a = { [day] = the most listed } } } (Source/Database/Mixin.lua
--   SetPrice); a day is a string, whole days since 2020-01-01 00:00 local time (Source/Constants/Main.lua SCAN_DAY_0).
--   SetPrice writes today's day into h each time it records an item and only then drops that item's days at or below
--   today minus price_history_days (21 by default), so every entry keeps a day: an entry with none is an error here.
--   An entry may lack a, which databases from before December 2020 have no field for (SetPrice's comment). Item keys:
--   "<itemID>", gear at or above an item level threshold "g:<itemID>:<item level>", battle pets "p:<speciesID>"
--   (Source/Utilities/DBKeyFromLink.lua); InitializeDatabase also puts version = 2 into each house it holds as a table.
-- The account's own file (SavedVariables/Auctionator.lua of 2026-11-21) holds just that: __dbversion = 8 and one key,
--   "PvP Horde", its house a CBOR string of 240624 bytes; in it 6819 entries keyed "<itemID>", each with m, h, l and
--   a and a day in h, and version = 2. Its strings are CBOR byte strings (major type 2), an empty table is an empty
--   array (byte 0x80), as l is on every entry there. The game writes the string's bytes as they are, 0x1A among them:
--   the file is read as bytes (M.ReadSaved).
-- An item's line: the lowest m of its keys, the time and count of its newest day, gone when that day is older than
-- the house's newest day (the last day anything was recorded).
local M = {}

---------------------------------------------------------------------------------------------------------------------
-- CBOR (RFC 8949): unsigned and negative integers, byte and text strings, arrays, maps, tags (their item is kept),
-- false / true / null and half, single and double floats; definite and indefinite lengths. Integers above 2^53 lose
-- their low bits (Lua numbers), which no price reaches.
---------------------------------------------------------------------------------------------------------------------
-- exponent and fraction bits of the three float sizes, by their byte count
local FLOAT_BITS = { [2] = { 5, 10 }, [4] = { 8, 23 }, [8] = { 11, 52 } }

function M.DecodeCBOR(data)
	local pos = 1
	local function nextByte()
		local b = data:byte(pos)
		if b == nil then error("CBOR: the data ends at byte " .. pos) end
		pos = pos + 1
		return b
	end
	local function bigEndian(count)
		local v = 0
		for _ = 1, count do v = v * 256 + nextByte() end
		return v
	end
	local function argument(info)
		if info < 24 then return info end
		local size = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
		if size == nil then error("CBOR: argument code " .. info .. " at byte " .. (pos - 1)) end
		return bigEndian(size)
	end
	-- sign, exponent and fraction straight from the bytes, so a double's 52 fraction bits stay exact
	local function float(count)
		local bytes = {}
		for i = 1, count do bytes[i] = nextByte() end
		local expBits, fracBits = FLOAT_BITS[count][1], FLOAT_BITS[count][2]
		local bitsLeft = 8 - 1 - expBits % 8 -- fraction bits in the byte where the exponent ends
		local expByteCount = math.floor((1 + expBits) / 8) + 1
		local exp = bytes[1] % 128
		for i = 2, expByteCount do exp = exp * 256 + bytes[i] end
		local frac = exp % 2 ^ bitsLeft
		exp = math.floor(exp / 2 ^ bitsLeft)
		for i = expByteCount + 1, count do frac = frac * 256 + bytes[i] end
		local bias = 2 ^ (expBits - 1) - 1
		local value
		if exp == 0 then
			value = frac * 2 ^ (1 - bias - fracBits)
		elseif exp == 2 ^ expBits - 1 then
			value = frac == 0 and math.huge or 0 / 0
		else
			value = (1 + frac / 2 ^ fracBits) * 2 ^ (exp - bias)
		end
		return bytes[1] >= 128 and -value or value
	end
	local readItem
	local function atBreak()
		if data:byte(pos) == 0xFF then pos = pos + 1; return true end
		return false
	end
	readItem = function()
		local head = nextByte()
		local major, info = math.floor(head / 32), head % 32
		if major == 0 then return argument(info) end
		if major == 1 then return -1 - argument(info) end
		if major == 2 or major == 3 then
			if info == 31 then
				local chunks = {}
				while not atBreak() do chunks[#chunks + 1] = readItem() end
				return table.concat(chunks)
			end
			local length = argument(info)
			if pos + length - 1 > #data then error("CBOR: a string of " .. length .. " bytes runs past the data at byte " .. pos) end
			local s = data:sub(pos, pos + length - 1)
			pos = pos + length
			return s
		end
		if major == 4 then
			local list = {}
			if info == 31 then
				while not atBreak() do list[#list + 1] = readItem() end
			else
				for i = 1, argument(info) do list[i] = readItem() end
			end
			return list
		end
		if major == 5 then
			local map = {}
			local function pair() local k = readItem(); map[k] = readItem() end
			if info == 31 then
				while not atBreak() do pair() end
			else
				for _ = 1, argument(info) do pair() end
			end
			return map
		end
		if major == 6 then
			argument(info)
			return readItem()
		end
		if info == 20 then return false end
		if info == 21 then return true end
		if info == 22 or info == 23 then return nil end
		local floatSize = ({ [25] = 2, [26] = 4, [27] = 8 })[info]
		if floatSize then return float(floatSize) end
		error("CBOR: simple value " .. info .. " at byte " .. (pos - 1))
	end
	local value = readItem()
	if pos <= #data then error("CBOR: " .. (#data - pos + 1) .. " bytes after the value") end
	return value
end

---------------------------------------------------------------------------------------------------------------------
-- Lines of one house
---------------------------------------------------------------------------------------------------------------------
local SCAN_DAY_0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 })

local function itemOf(key)
	if type(key) == "number" then return key end
	return tonumber(key) or tonumber(key:match("^g:(%d+):"))
end

-- the newest day of the entry at `key`, a number; an entry with no day in h is none SetPrice wrote (the head)
local function newestDay(key, entry)
	if type(entry.h) ~= "table" then error("house entry '" .. key .. "' has no day table h") end
	local newest
	for day in pairs(entry.h) do
		local d = tonumber(day)
		if newest == nil or d > newest then newest = d end
	end
	if newest == nil then error("house entry '" .. key .. "' has no day in h") end
	return newest
end

-- house: a table or its CBOR string. Returns { { itemID, price, time, count, gone }, ... } sorted by itemID.
function M.Lines(house)
	if type(house) == "string" then house = M.DecodeCBOR(house) end
	-- entriesOf[itemID] = { { newest day, entry }, ... }, one per key of the item
	local entriesOf, houseNewest = {}, nil
	for key, entry in pairs(house) do
		local id = itemOf(key)
		if id then
			local day = newestDay(key, entry)
			entriesOf[id] = entriesOf[id] or {}
			table.insert(entriesOf[id], { day, entry })
			if houseNewest == nil or day > houseNewest then houseNewest = day end
		end
	end
	local lines = {}
	for id, entries in pairs(entriesOf) do
		local price, day = entries[1][2].m, entries[1][1]
		for _, e in ipairs(entries) do
			if e[2].m < price then price = e[2].m end
			if e[1] > day then day = e[1] end
		end
		-- the count of that day; a price the selling tab recorded carries none (SetPrice's available is nil)
		local count = 0
		for _, e in ipairs(entries) do count = count + ((e[2].a or {})[tostring(day)] or 0) end
		lines[#lines + 1] = { id, price, SCAN_DAY_0 + day * 86400, count, day < houseNewest }
	end
	table.sort(lines, function(a, b) return a[1] < b[1] end)
	return lines
end

-- The realm key to read: the one asked for, else the only key of the faction. Errors list the keys there are.
function M.PickRealm(db, faction, asked)
	local keys, ours = {}, {}
	for key in pairs(db) do
		if key ~= "__dbversion" then
			keys[#keys + 1] = key
			if key:sub(-(#faction + 1)) == " " .. faction then ours[#ours + 1] = key end
		end
	end
	table.sort(keys)
	table.sort(ours)
	if asked then
		if db[asked] == nil then error("no realm key '" .. asked .. "' (there are: " .. table.concat(keys, ", ") .. ")") end
		return asked
	end
	if #ours ~= 1 then
		error(#ours .. " realm keys of the " .. faction .. " (" .. table.concat(ours, ", ") .. "); pass one as the third argument")
	end
	return ours[1]
end

-- The variables a saved file assigns, as a table: the file runs in it, not in the tool's globals (load's env in Lua
-- 5.2+, setfenv in 5.1). The file is read as bytes and handed to load: loadfile opens a text chunk with fopen "r"
-- (lauxlib.c luaL_loadfilex, 5.1 and 5.4), and the Windows C runtime ends a text-mode read at byte 0x1A, which the
-- CBOR strings hold (the account's file has 1415 of them, the first its byte 4087).
function M.ReadSaved(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	local saved = {}
	local chunk
	if setfenv then
		chunk = assert(loadstring(text, "@" .. path))
		setfenv(chunk, saved)
	else
		chunk = assert(load(text, "@" .. path, "t", saved))
	end
	chunk()
	return saved
end

-- Writes the lines of the Horde house (or of the realm key asked for) of a saved Auctionator.lua to `output`;
-- returns the realm key it read.
function M.Write(input, output, asked)
	local db = M.ReadSaved(input).AUCTIONATOR_PRICE_DATABASE
	if type(db) ~= "table" then error(input .. " holds no AUCTIONATOR_PRICE_DATABASE") end
	local realm = M.PickRealm(db, "Horde", asked)
	local out = assert(io.open(output, "w"))
	for _, l in ipairs(M.Lines(db[realm])) do
		out:write(string.format("%d\t%d\t%d\t%d\t%s\n", l[1], l[2], l[3], l[4], tostring(l[5])))
	end
	out:close()
	return realm
end

local input, output, asked = ...
if input == nil then return M end
print(M.Write(input, output, asked) .. ": " .. output)
