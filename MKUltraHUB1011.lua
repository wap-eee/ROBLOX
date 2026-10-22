--!nonstrict
-- ===========================================================================
--  MKUltraHUB -- GENERATED BUNDLE. DO NOT EDIT.
--  Source of truth: src\**\*.luau   Builder: tools\bundle.ps1
--  Modules: 73   Entry: main
--  Generated: 2026-10-22 12:21:05
-- ===========================================================================

local __modules = {}
local __cache = {}
local __loading = {}

local function __require(name)
	local hit = __cache[name]
	if hit ~= nil then
		return hit
	end
	local factory = __modules[name]
	if factory == nil then
		error("MKUltraHUB: module not found: " .. tostring(name), 2)
	end
	-- The bundler topologically sorts and rejects cycles, so this cannot fire
	-- for a bundle this script produced. It is here so that a hand-assembled
	-- or hand-edited bundle reports WHICH module recursed instead of dying
	-- with a stack overflow and no usable line number.
	if __loading[name] then
		error("MKUltraHUB: circular require: " .. tostring(name), 2)
	end
	__loading[name] = true
	local value = factory()
	__loading[name] = nil
	if value == nil then
		value = true
	end
	__cache[name] = value
	return value
end

__modules["core/Format"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Format -- number and duration presentation. Pure: no Roblox, no globals.

	The tier is chosen from the value AS DISPLAYED (rounded first), so 999.5 is
	"1.000K" and not "1000"; both boundaries resolve consistently.
]]

local Format = {}

local SUFFIXES: { string } = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

local NAN = 0 / 0

local function sign(negative: boolean): string
	return if negative then "-" else ""
end

-- Round half away from zero at the given precision.
local function roundTo(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

-- Format a number for display. `abbreviated == false` prints the rounded value
-- with no suffix and never falls back to scientific notation.
function Format.number(value: number?, abbreviated: boolean?): string
	local n = value or 0
	if n ~= n or n == math.huge or n == -math.huge or n == NAN then
		return "0"
	end

	local negative = n < 0
	n = math.abs(n)

	if abbreviated == false then
		local rounded = roundTo(n, 0)
		if rounded == 0 then
			negative = false
		end
		return sign(negative) .. string.format("%.0f", rounded)
	end

	local tier = 1
	while tier < #SUFFIXES do
		local decimals = if tier == 1 then 0 else 3
		if roundTo(n / 1000 ^ (tier - 1), decimals) < 1000 then
			break
		end
		tier += 1
	end

	local decimals = if tier == 1 then 0 else 3
	local shown = roundTo(n / 1000 ^ (tier - 1), decimals)
	-- A value that rounds to zero must not print "-0": the sign is about the
	-- DISPLAYED number, and -0 is not a number the UI should ever show.
	if shown == 0 then
		negative = false
	end
	return sign(negative) .. string.format("%." .. tostring(decimals) .. "f", shown) .. SUFFIXES[tier]
end

-- Format a duration in seconds: "45s", "1m 30s", "2h 5m".
function Format.duration(seconds: number?): string
	local total = math.floor(seconds or 0)
	if total < 0 then
		total = 0
	end
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	if minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- Format a signed delta with an explicit sign, e.g. "+1.234K" / "-12".
function Format.delta(value: number?): string
	local n = value or 0
	if n >= 0 then
		return "+" .. Format.number(n)
	end
	return Format.number(n)
end

return Format
end

__modules["core/Signal"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Signal -- synchronous publish/subscribe. Pure: no Roblox, no globals.

	State lives in ONE place (see core/Store) and every view subscribes to it;
	updates are pushed, so nothing has to be polled or reconciled.

	Semantics that matter:
	  * fire() iterates a snapshot, so a handler that connects or disconnects
	    during dispatch cannot corrupt the iteration;
	  * a disconnected handler is never invoked, even if it was in the snapshot;
	  * disconnect() is idempotent.
]]

local Signal = {}
Signal.__index = Signal

export type Handler = (...any) -> ()

type Record = {
	alive: boolean,
	handler: Handler,
}

export type Connection = {
	disconnect: (Connection) -> (),
	connected: (Connection) -> boolean,
}

export type Signal = {
	_records: { Record },
	connect: (Signal, Handler) -> Connection,
	fire: (Signal, ...any) -> (),
	clear: (Signal) -> (),
	count: (Signal) -> number,
}

local function newConnection(signal: Signal, record: Record): Connection
	return {
		disconnect = function()
			if not record.alive then
				return
			end
			record.alive = false
			local list = signal._records
			for i = #list, 1, -1 do
				if list[i] == record then
					table.remove(list, i)
					break
				end
			end
		end,
		connected = function(): boolean
			return record.alive
		end,
	}
end

function Signal.new(): Signal
	local self = setmetatable({ _records = {} }, Signal)
	return (self :: any) :: Signal
end

function Signal.connect(self: Signal, handler: Handler): Connection
	local record: Record = { alive = true, handler = handler }
	table.insert(self._records, record)
	return newConnection(self, record)
end

function Signal.fire(self: Signal, ...: any)
	local snapshot = table.clone(self._records)
	for _, record in ipairs(snapshot) do
		if record.alive then
			record.handler(...)
		end
	end
end

function Signal.clear(self: Signal)
	for _, record in ipairs(self._records) do
		record.alive = false
	end
	table.clear(self._records)
end

function Signal.count(self: Signal): number
	local n = 0
	for _, record in ipairs(self._records) do
		if record.alive then
			n += 1
		end
	end
	return n
end

return Signal
end

__modules["core/RateLimiter"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	RateLimiter -- token bucket with failure backpressure. Pure: no Roblox.

	Send throttling must not be a hard-coded `true` ("fast training is implemented
	by firing as fast as possible"): that is a safety valve wired open, and the
	moment the server starts throttling the client has no idea, no fallback, and
	the player gets kicked.

	This module makes the limiter *measurable* rather than a boolean switch:

	  * allow() is a hard token bucket: rate per second, capped burst.
	  * reportFailure() applies multiplicative backoff, so a server that starts
	    rejecting makes us slow down on our own, before it escalates to a kick.
	  * reportSuccess() recovers the rate gradually.
	  * stats() exposes allowed / denied / penalty so the UI and the log can see
	    what is happening instead of guessing.

	The clock is passed in, never read: that is what makes it unit-testable.
]]

local RateLimiter = {}

export type Options = {
	minPenalty: number?,
	backoff: number?,
	recoverStep: number?,
}

export type Stats = {
	allowed: number,
	denied: number,
	penalty: number,
	effectiveRate: number,
	tokens: number,
}

export type Limiter = {
	allow: (Limiter, now: number, cost: number?) -> boolean,
	reportFailure: (Limiter, now: number) -> (),
	reportSuccess: (Limiter, now: number) -> (),
	configure: (Limiter, rate: number, burst: number?) -> (),
	stats: (Limiter, now: number) -> Stats,
	reset: (Limiter, now: number) -> (),
}

local DEFAULT_MIN_PENALTY = 0.1
local DEFAULT_BACKOFF = 0.5
local DEFAULT_RECOVER = 0.25

local RateLimiterImpl = {}
RateLimiterImpl.__index = RateLimiterImpl

type State = {
	_rate: number,
	_burst: number,
	_tokens: number,
	_last: number?,
	_penalty: number,
	_allowed: number,
	_denied: number,
	_minPenalty: number,
	_backoff: number,
	_recover: number,
}

function RateLimiter.new(rate: number, burst: number?, options: Options?): Limiter
	local opts: Options = options or {}
	local self: State = {
		_rate = math.max(0, rate),
		_burst = math.max(1, burst or math.max(1, rate * 0.25)),
		_tokens = math.max(1, burst or math.max(1, rate * 0.25)),
		_last = nil,
		_penalty = 1,
		_allowed = 0,
		_denied = 0,
		_minPenalty = opts.minPenalty or DEFAULT_MIN_PENALTY,
		_backoff = opts.backoff or DEFAULT_BACKOFF,
		_recover = opts.recoverStep or DEFAULT_RECOVER,
	}
	return (setmetatable(self, RateLimiterImpl) :: any) :: Limiter
end

local function state(self: Limiter): State
	return self :: any
end

-- Refill, clamping dt so a long stall (alt-tab, loading screen) cannot bank an
-- unbounded burst and then dump it in one instant.
local function refill(s: State, now: number)
	local previous = s._last
	if previous == nil then
		s._last = now
		return
	end
	local dt = now - previous
	s._last = now
	if dt <= 0 then
		return
	end
	if dt > 1 then
		dt = 1
	end
	s._tokens = math.min(s._burst, s._tokens + s._rate * s._penalty * dt)
end

function RateLimiterImpl.allow(self: Limiter, now: number, cost: number?): boolean
	local s = state(self)
	refill(s, now)
	local spend = cost or 1
	if spend <= 0 then
		return true
	end
	if s._tokens >= spend then
		s._tokens -= spend
		s._allowed += 1
		return true
	end
	s._denied += 1
	return false
end

function RateLimiterImpl.reportFailure(self: Limiter, now: number)
	local s = state(self)
	s._penalty = math.max(s._minPenalty, s._penalty * s._backoff)
	s._tokens = 0
	s._last = now
end

function RateLimiterImpl.reportSuccess(self: Limiter, now: number)
	local s = state(self)
	s._last = now
	if s._penalty < 1 then
		s._penalty = math.min(1, s._penalty + s._recover)
	end
end

function RateLimiterImpl.configure(self: Limiter, rate: number, burst: number?)
	local s = state(self)
	s._rate = math.max(0, rate)
	if burst ~= nil then
		s._burst = math.max(1, burst)
	end
	if s._tokens > s._burst then
		s._tokens = s._burst
	end
end

function RateLimiterImpl.stats(self: Limiter, now: number): Stats
	local s = state(self)
	refill(s, now)
	return {
		allowed = s._allowed,
		denied = s._denied,
		penalty = s._penalty,
		effectiveRate = s._rate * s._penalty,
		tokens = s._tokens,
	}
end

function RateLimiterImpl.reset(self: Limiter, now: number)
	local s = state(self)
	s._tokens = s._burst
	s._penalty = 1
	s._last = now
	s._allowed = 0
	s._denied = 0
end

return RateLimiter
end

__modules["core/Store"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Store -- the single source of truth. Pure: no Roblox, no globals.

	Keeping one setting in a mutable global table AND a copy inside each UI widget,
	reconciled by a 1 Hz polling loop, cannot work: polling cannot express "this
	changed", so the copies drift apart and a missed pass means a control that
	silently stops working.

	A Store holds every value exactly once, addressed by a dotted path
	("train.auto"), and pushes changes to whoever subscribed. Nothing polls.

	Values are kept FLAT (path -> value) rather than nested: reads and writes are
	a single table lookup with no string splitting on the hot path, and
	persistence is a direct mapping. Nesting is only materialised on demand by
	`Store.nest`, which is what the config writer/reader uses.

	Subscribing to a prefix ("train") delivers changes to any descendant
	("train.auto"), because a settings page wants exactly that.
]]

local Store = {}
Store.__index = Store

export type Listener = (path: string, value: any, previous: any) -> ()
export type LeafPredicate = (path: string) -> boolean

export type Connection = {
	disconnect: (Connection) -> (),
	connected: (Connection) -> boolean,
}

type Subscription = {
	path: string,
	handler: Listener,
	alive: boolean,
}

export type Store = {
	_values: { [string]: any },
	_subs: { Subscription },
	get: (Store, path: string, default: any?) -> any,
	set: (Store, path: string, value: any) -> boolean,
	update: (Store, path: string, fn: (any) -> any) -> boolean,
	has: (Store, path: string) -> boolean,
	remove: (Store, path: string) -> boolean,
	subscribe: (Store, path: string, handler: Listener) -> Connection,
	subscribeAll: (Store, handler: Listener) -> Connection,
	clear: (Store) -> (),
	keys: (Store) -> { string },
	snapshot: (Store) -> { [string]: any },
	load: (Store, flat: { [string]: any }) -> number,
}

local function newConnection(store: Store, sub: Subscription): Connection
	return {
		disconnect = function()
			if not sub.alive then
				return
			end
			sub.alive = false
			for i = #store._subs, 1, -1 do
				if store._subs[i] == sub then
					table.remove(store._subs, i)
					break
				end
			end
		end,
		connected = function(): boolean
			return sub.alive
		end,
	}
end

-- A container is treated as an array (and therefore as a leaf value, not a
-- subtree) when it has a [1] entry. Preset lists rely on this.
local function isArray(value: any): boolean
	return type(value) == "table" and rawget(value, 1) ~= nil
end

-- Flatten a nested table into path -> value.
--
-- `isLeaf` lets the caller stop the recursion at paths whose values are records
-- rather than subtrees. Without it a position record like
-- { xs = 0, xo = 640, ... } would be flattened into savedMain.xs, savedMain.xo,
-- ... and could never be validated as a unit.
function Store.flatten(nested: { [string]: any }, isLeaf: LeafPredicate?): { [string]: any }
	local out: { [string]: any } = {}
	-- Narrow the optional ONCE, outside the closure: Luau does not narrow a
	-- captured optional inside a nested function, so `if isLeaf ~= nil then
	-- isLeaf(path) end` inside walk() still reports "could be nil".
	local predicate: LeafPredicate = isLeaf or function(_path: string): boolean
		return false
	end
	local function walk(node: { [string]: any }, prefix: string)
		for key, value in pairs(node) do
			local path = if prefix == "" then tostring(key) else prefix .. "." .. tostring(key)
			local stop = predicate(path)
			if type(value) == "table" and not stop and not isArray(value) and next(value) ~= nil then
				walk(value, path)
			else
				out[path] = value
			end
		end
	end
	walk(nested, "")
	return out
end

-- Rebuild the nested shape from a flat map, for serialisation.
-- If both "a" and "a.b" are present the deeper key wins and the scalar is lost --
-- setting a value and one of its own descendants is a modelling bug.
function Store.nest(flat: { [string]: any }): { [string]: any }
	local root: { [string]: any } = {}
	for path, value in pairs(flat) do
		local node = root
		local start = 1
		while true do
			local dot = string.find(path, ".", start, true)
			if dot == nil then
				node[string.sub(path, start)] = value
				break
			end
			local key = string.sub(path, start, dot - 1)
			local child = node[key]
			if type(child) ~= "table" then
				child = {}
				node[key] = child
			end
			node = child
			start = dot + 1
		end
	end
	return root
end

function Store.new(): Store
	local self = setmetatable({ _values = {}, _subs = {} }, Store)
	return (self :: any) :: Store
end

function Store.get(self: Store, path: string, default: any?): any
	local value = self._values[path]
	if value == nil then
		return default
	end
	return value
end

function Store.has(self: Store, path: string): boolean
	return self._values[path] ~= nil
end

-- Does a subscription on `subPath` care about a change at `changedPath`?
local function covers(subPath: string, changedPath: string): boolean
	if subPath == "" then
		return true
	end
	if subPath == changedPath then
		return true
	end
	return string.sub(changedPath, 1, #subPath + 1) == subPath .. "."
end

-- Write a value. Returns true when something actually changed, and only then are
-- subscribers notified -- an unchanged value is not an event, which is precisely
-- what makes polling unnecessary.
function Store.set(self: Store, path: string, value: any): boolean
	local previous = self._values[path]
	if previous == value then
		return false
	end
	self._values[path] = value
	local snapshot = table.clone(self._subs)
	for _, sub in ipairs(snapshot) do
		if sub.alive and covers(sub.path, path) then
			sub.handler(path, value, previous)
		end
	end
	return true
end

function Store.update(self: Store, path: string, fn: (any) -> any): boolean
	return Store.set(self, path, fn(self._values[path]))
end

function Store.remove(self: Store, path: string): boolean
	if self._values[path] == nil then
		return false
	end
	return Store.set(self, path, nil)
end

function Store.subscribe(self: Store, path: string, handler: Listener): Connection
	local sub: Subscription = { path = path, handler = handler, alive = true }
	table.insert(self._subs, sub)
	return newConnection(self, sub)
end

function Store.subscribeAll(self: Store, handler: Listener): Connection
	return Store.subscribe(self, "", handler)
end

function Store.clear(self: Store)
	for _, sub in ipairs(self._subs) do
		sub.alive = false
	end
	table.clear(self._subs)
	table.clear(self._values)
end

function Store.keys(self: Store): { string }
	local out: { string } = {}
	for path in pairs(self._values) do
		table.insert(out, path)
	end
	table.sort(out)
	return out
end

function Store.snapshot(self: Store): { [string]: any }
	return Store.nest(self._values)
end

-- Apply many values at once (config load). Returns how many paths changed.
function Store.load(self: Store, flat: { [string]: any }): number
	local changed = 0
	for path, value in pairs(flat) do
		if Store.set(self, path, value) then
			changed += 1
		end
	end
	return changed
end

return Store
end

__modules["core/BossInfo"] = function()
	local require = __require
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	BossInfo -- identifying a boss and deciding whether it is wanted. Pure.

	Three rules live here:

	1. RARITY FROM A NAME, in a FIXED order. A `pairs` lookup over a keyword->rarity
	   hash table has no defined order, so a name matching two keywords resolved
	   differently between runs; the list is ordered here (most specific first) and
	   that ordering is the specification.

	2. AN UNIDENTIFIED BOSS IS ATTACKED, NOT IGNORED. "?" is treated as selected.
	   Refusing to act on a boss you failed to classify would make the feature
	   silently do nothing whenever the game renames something.

	3. THERE ARE TWO GROUPS OF BOSS. The fixed arena slots (Boss1..BossRainbow)
	   are the NORMAL group. The seasonal arenas added a second, separate group:
	   four event bosses, each its own model carrying a `BossId` attribute, all of
	   which can be alive AT THE SAME TIME and which the user wants killed one
	   after another, Grim Reaper first. The two groups have their own selection
	   switches, their own hover height, and a settable priority between them, so
	   "which boss is this" has to be answerable here rather than in game/Boss.
]]

local Format = require("core/Format")

local BossInfo = {}

export type Info = {
	alive: boolean,
	id: string,
	rarity: string,
	hp: number,
	maxHp: number,
	position: any?,
	--[[
		Which group the boss belongs to: "normal" -- a fixed arena slot
		(Boss1..BossRainbow), "event" -- one of the seasonal bosses (see EVENTS).
		Carried on the record because THREE decisions key off it: which selection
		switches apply, which hover height the fight uses, and which group
		`boss.priority` puts first.
	]]
	group: string?,
	-- The event boss's stable key, or nil for a normal boss.
	eventKey: string?,
}

-- The arena's fixed slots.
local FIXED: { { id: string, rarity: string } } = {
	{ id = "Boss1", rarity = "Common" },
	{ id = "Boss2", rarity = "Rare" },
	{ id = "Boss3", rarity = "Epic" },
	{ id = "Boss4", rarity = "Legendary" },
	{ id = "Boss5", rarity = "Mythic" },
	{ id = "BossRainbow", rarity = "Rainbow" },
}

-- Ordered on purpose: the first keyword that matches wins, deterministically.
local RARITY_KEYWORDS: { { keyword: string, rarity: string } } = {
	{ keyword = "rainbow", rarity = "Rainbow" },
	{ keyword = "mythic", rarity = "Mythic" },
	{ keyword = "legendary", rarity = "Legendary" },
	{ keyword = "epic", rarity = "Epic" },
	{ keyword = "rare", rarity = "Rare" },
	{ keyword = "common", rarity = "Common" },
}

local RARITIES: { string } = { "Common", "Rare", "Epic", "Legendary", "Rainbow", "Mythic" }

BossInfo.RARITIES = RARITIES
BossInfo.UNKNOWN = "?"

-- The two groups, as plain strings so both game/Boss and the UI can compare
-- against them without importing a private enum.
BossInfo.NORMAL_GROUP = "normal"
BossInfo.EVENT_GROUP = "event"

--[[
	EVENT BOSSES -- the seasonal arena bosses.

	They are NOT the fixed Boss1..BossRainbow slots. Each one is its own model,
	identified by a `BossId` attribute, all four can be alive at the same time,
	and they live outside `Workspace.Events.BossArena`.

	THE ORDER OF THIS LIST IS THE KILL ORDER: Grim Reaper first, then the other
	three one after another -- "优先挑这个打 GRIMREAPER，打完了这个再去打剩下的三个，
	每打完一个再去打下一个". game/Boss walks this list and takes the first boss that
	is still alive, so the sequence is data rather than control flow.

	`names` are what the live game calls the instance, used for a recursive name
	lookup before any tree walk. `keywords` are the rename-proof fallback:
	plain-text, case-folded, first match wins, most specific first.
]]
export type EventBoss = {
	key: string,
	label: string,
	-- Fixed hover height for THIS boss. They are not one number (Frankenbrute
	-- needs nearly twice the height of the rest), so the value belongs to the
	-- entry, not to a shared setting.
	hover: number,
	names: { string },
	keywords: { string },
}

local EVENTS: { EventBoss } = {
	{
		key = "grimReaper",
		label = "死神 Grim Reaper",
		hover = 50,
		names = { "Grim Reaper", "GrimReaper" },
		keywords = { "grimreaper", "grim reaper", "reaper", "死神" },
	},
	{
		key = "frankenBrute",
		label = "科学怪人 Frankenbrute",
		hover = 120,
		names = { "Frankenbrute", "FrankenBrute", "Franken Brute" },
		keywords = { "frankenbrute", "franken brute", "franken", "科学怪人" },
	},
	{
		key = "scarecrowColossus",
		label = "稻草人 Scarecrow Colossus",
		hover = 24,
		names = { "Scarecrow Colossus", "ScarecrowColossus" },
		keywords = { "scarecrowcolossus", "scarecrow", "稻草人" },
	},
	{
		key = "pumpkinTitan",
		label = "南瓜泰坦 Pumpkin Titan",
		hover = 50,
		names = { "Pumpkin Titan", "PumpkinTitan" },
		keywords = { "pumpkintitan", "pumpkin", "南瓜" },
	},
}

BossInfo.EVENTS = EVENTS

-- The attribute the game writes on an event boss. Matching it is exact, so it is
-- preferred over the name keywords.
BossInfo.EVENT_ID = "BossId"

--[[
	The NORMAL group's fixed hover height: every arena boss uses 70 studs. Also the
	fallback for an event boss whose entry cannot be found (a save file naming a
	boss this build does not know), so a missing entry degrades to a sane number
	instead of dropping the fight to the ground.

	Fixed numbers on purpose: they are geometry facts about each rig, not
	preferences, and a slider that could break the punch reach was worse than
	useless.
]]
BossInfo.NORMAL_HOVER = 70
BossInfo.EVENT_HOVER = 50

function BossInfo.fixed(): { { id: string, rarity: string } }
	return FIXED
end

function BossInfo.rarityFromName(name: string?): string
	if name == nil or name == "" then
		return BossInfo.UNKNOWN
	end
	local lowered = string.lower(name)
	for _, entry in ipairs(RARITY_KEYWORDS) do
		if string.find(lowered, entry.keyword, 1, true) ~= nil then
			return entry.rarity
		end
	end
	return BossInfo.UNKNOWN
end

-- A rarity the user did not switch off is wanted. "?" is always wanted.
function BossInfo.selected(rarity: string?, selection: { [string]: boolean }?): boolean
	if rarity == nil or rarity == BossInfo.UNKNOWN then
		return true
	end
	if selection == nil then
		return true
	end
	return selection[rarity] ~= false
end

-- Has the user switched ANY known rarity off?
--
-- This is the only thing that may narrow the "?" rule. With everything on, an
-- unidentified boss is still attacked (rule 2 above); once the user has
-- actually built a filter, a rig the classifier cannot name is exactly the
-- "没有勾选也会去打" case and has to fall on the opt-out side.
function BossInfo.narrowed(selection: { [string]: boolean }?): boolean
	if selection == nil then
		return false
	end
	for _, rarity in ipairs(RARITIES) do
		if selection[rarity] == false then
			return true
		end
	end
	return false
end

-- Every event boss, in KILL ORDER (Grim Reaper first).
function BossInfo.events(): { EventBoss }
	return EVENTS
end

function BossInfo.event(key: string?): EventBoss?
	if key == nil then
		return nil
	end
	for _, entry in ipairs(EVENTS) do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

function BossInfo.eventLabel(key: string?): string?
	local entry = BossInfo.event(key)
	if entry ~= nil then
		return entry.label
	end
	return nil
end

-- Which event boss does this name look like? nil when it is none of them.
function BossInfo.eventKeyFromName(name: string?): string?
	if name == nil or name == "" then
		return nil
	end
	local lowered = string.lower(name)
	for _, entry in ipairs(EVENTS) do
		for _, keyword in ipairs(entry.keywords) do
			if string.find(lowered, keyword, 1, true) ~= nil then
				return entry.key
			end
		end
	end
	return nil
end

--[[
	Identify an event boss from the two things a candidate instance can tell us.

	The `BossId` attribute wins when present (it is the game's own id, e.g.
	"GrimReaper"), then its own keywords, and only then the instance NAME -- so a
	rig whose attribute has not replicated yet still resolves, and a renamed
	attribute still resolves through the name.
]]
function BossInfo.eventKeyFor(attributeId: string?, name: string?): string?
	if attributeId ~= nil and attributeId ~= "" then
		local lowered = string.lower(attributeId)
		for _, entry in ipairs(EVENTS) do
			if string.lower(entry.key) == lowered then
				return entry.key
			end
		end
		local fromAttribute = BossInfo.eventKeyFromName(attributeId)
		if fromAttribute ~= nil then
			return fromAttribute
		end
	end
	return BossInfo.eventKeyFromName(name)
end

--[[
	An event boss the user did not switch off is wanted.

	Same rule as `selected`: an unknown or missing key is WANTED, because
	silently refusing to attack the boss you failed to name would make the
	feature look broken the moment the game renames something.
]]
function BossInfo.eventSelected(key: string?, selection: { [string]: boolean }?): boolean
	if key == nil or selection == nil then
		return true
	end
	return selection[key] ~= false
end

function BossInfo.empty(): Info
	return {
		alive = false,
		id = "?",
		rarity = BossInfo.UNKNOWN,
		hp = 0,
		maxHp = 0,
		position = nil,
		group = BossInfo.NORMAL_GROUP,
		eventKey = nil,
	}
end

function BossInfo.describe(info: Info?): string
	if info == nil or info.alive ~= true then
		return "等待 Boss 刷新..."
	end
	if info.group == BossInfo.EVENT_GROUP then
		-- The event bosses carry no rarity, so the label IS the identification.
		local label = BossInfo.eventLabel(info.eventKey) or info.id
		return string.format("活动 Boss  %s\nHP  %s / %s",
			label, Format.number(info.hp), Format.number(info.maxHp))
	end
	return string.format("存活  %s (%s)\nHP  %s / %s",
		info.id, info.rarity, Format.number(info.hp), Format.number(info.maxHp))
end

return BossInfo
end

__modules["core/Config"] = function()
	local require = __require
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Config -- the persistence schema and its migration chain. Pure: it validates
	and rewrites plain tables, it does no file IO (the adapter owns that).

	Why this exists: V1007 persisted state by copying whole Core subtables into a
	JSON encoder. That is why the config "never saved": Core.machine holds
	Instance fields, JSONEncode threw, the surrounding pcall swallowed it, and
	every setting was silently discarded. Copying live state also means there is
	no definition anywhere of what is actually persisted, no validation on load,
	and no way to evolve the format.

	Here every persisted key is declared once, with a type, a default and a
	range/enum constraint. Loading is then a pure function of the file contents:

	    raw JSON -> flatten -> migrate -> validate -> flat values + warnings

	Two behaviours are deliberate and are covered by tests:

	  * An EMPTY preset table is a value ("this preset was cleared"), not a
	    missing key. Treating the two the same is the data-loss bug this schema
	    replaces.
	  * Nothing is ever silently dropped: every correction adds a warning, so the
	    caller can surface it instead of guessing.
]]

local Store = require("core/Store")
--[[
	The EVENT boss list is required, not duplicated.

	The per-boss switches (`boss.event.<key>`) have to name the same keys the
	detector looks for: a schema that listed a stale key would produce a toggle
	that does nothing while the real boss stayed unselectable, which is a bug no
	test would see. Deriving the paths from core/BossInfo makes the two
	impossible to disagree. Both modules are pure, so this stays pure.
]]
local BossInfo = require("core/BossInfo")

local Config = {}

Config.VERSION = 1010

export type Spec = {
	path: string,
	kind: string,
	default: any,
	min: number?,
	max: number?,
	values: { string }?,
	-- false marks a LIVE key: declared here so the store's key vocabulary is
	-- complete and validation still covers it, but never written to disk and
	-- never read back from a file. See `live` below.
	persist: boolean?,
}

export type Steps = { [number]: ({ [string]: any }) -> () }

export type Report = {
	values: { [string]: any },
	warnings: { string },
	migratedFrom: number?,
}

local THEMES = { "light", "dark", "ocean", "sakura", "forest", "flame" }
local ANTI_PULL = { "off", "normal", "strict" }
local REJOIN_MODES = { "same", "crowded", "private", "sparse", "player" }
local RARITIES = { "Common", "Rare", "Epic", "Legendary", "Rainbow", "Mythic" }
-- Which GROUP of boss to attack first when both are available. "event" is the
-- default because the event bosses are the time-limited ones.
local BOSS_PRIORITY = { "event", "normal" }
--[[
	Where the post-event server hop lands.

	Deliberately NOT `REJOIN_MODES`: "same" (back to this server) would make the
	hop pointless -- the four bosses are already dead HERE, which is the reason
	the hop fires -- so the option is not offered. The private code comes from
	the same `rejoin.privId` the rejoin page already uses.
]]
local HOP_MODES = { "sparse", "crowded", "private" }

local function bool(path: string, default: boolean): Spec
	return { path = path, kind = "boolean", default = default }
end

local function num(path: string, default: number, min: number, max: number): Spec
	return { path = path, kind = "number", default = default, min = min, max = max }
end

local function str(path: string, default: string): Spec
	return { path = path, kind = "string", default = default }
end

local function enm(path: string, default: string, values: { string }): Spec
	return { path = path, kind = "enum", default = default, values = values }
end

local function pos(path: string): Spec
	return { path = path, kind = "position", default = nil }
end

local function preset(path: string): Spec
	return { path = path, kind = "preset", default = {} }
end

--[[
	A MAP: `{ [name] = boolean }`, or `{ [name] = { [name] = boolean } }` at most
	one level deep.

	Added for the crystal auto-sell list, which is per CRYSTAL ("让我来选择出售
	哪些宠物，就是该水晶的哪些宠物"): the selection has to survive a crystal
	change and a reload, and `preset` (a flat array of {name,count}) cannot express
	"which crystal this name belongs to".

	Like `preset` and `position`, it is a LEAF kind: flattening must stop at the
	path or the inner names would become un-validatable individual keys.
]]
local function map(path: string): Spec
	return { path = path, kind = "map", default = {} }
end

-- A key the running script owns rather than the user's saved settings (pause,
-- and anything else that must not survive a reload). It is in the schema so
-- that `Config.defaults`, validation and the "unknown key" check all know about
-- it, but `project` drops it so it can never reach the encoder.
local function live(path: string, default: boolean): Spec
	return { path = path, kind = "boolean", default = default, persist = false }
end

-- The numeric / string forms of a live key. Same rule as `live`: in the schema
-- (so defaults, validation and the unknown-key check all know about it) but
-- dropped by `project` so it can never reach the encoder.
local function liveNum(path: string, default: number): Spec
	return { path = path, kind = "number", default = default, persist = false }
end

local function liveStr(path: string, default: string): Spec
	return { path = path, kind = "string", default = default, persist = false }
end

--[[
	Retired keys: settings for features that were REMOVED on purpose.

	They are not in SCHEMA any more, so a file written by an older build would
	otherwise print one "unknown key dropped" warning per key on every single
	load (`follow.*`, `train.adaptive*`, `train.eventAdaptive`,
	`train.eventPingTarget`, `boss.event.hopAfterKill` -- fifteen lines of noise
	in the executor console).

	A dropped key is reported so a typo in a hand-edited file is not silent, but
	these are not typos: the feature is gone, the value is meaningless, and it is
	dropped either way. The entry only silences the warning.
]]
local RETIRED: { [string]: boolean } = {
	["follow.enabled"] = true,
	["follow.poll"] = true,
	["follow.gap"] = true,
	["follow.waitSeconds"] = true,
	["follow.maxAttempts"] = true,
	["follow.sweep"] = true,
	["follow.sweepGap"] = true,
	["follow.sweepCursor"] = true,
	["follow.sweepAt"] = true,
	["train.adaptive"] = true,
	["train.adaptiveThresh"] = true,
	["train.adaptiveMax"] = true,
	["train.eventAdaptive"] = true,
	["train.eventPingTarget"] = true,
	["boss.event.hopAfterKill"] = true,
}

local SCHEMA: { Spec } = {
	-- training ---------------------------------------------------------------
	bool("train.auto", false),
	bool("train.fast", false),
	num("train.rate", 20, 1, 2000),
	bool("train.duringKill", true),
	bool("train.duringBoss", true),
	bool("train.toolDumbbell", false),
	bool("train.toolPush", false),
	bool("train.toolHand", false),
	bool("train.toolSit", false),
	--[[
		The rate the pacing layer actually resolved, plus why.

		LIVE: it is a statement about right now. "Why is it sending at 40/s when I
		typed 900" is otherwise unanswerable without reading the source.
	]]
	liveNum("train.effRate", 0),
	liveStr("train.rateSource", ""),
	--[[
		Which hand the tool arbiter is currently holding: "punch" or "train".

		LIVE and shared through the store because TWO subsystems write the same
		hand: the tool arbiter equips the training tool, and Combat.punch equips
		the glove on every punch. Without one agreed flag the glove (re-equipped
		up to 120x/s) always won and training never got a window -- which is the
		"切换拳套的速度远远超过切换锻炼工具的速度" the user reported.
	]]
	liveStr("train.dualTool", "punch"),
	--[[
		The resolved arbitration depth, published by game/Train for the UI.

		LIVE, not persisted: it describes what is happening right now (which rung
		of the depth ladder training is on, and which requirement pushed it
		there), so restoring it from a file would be restoring a stale claim.
	]]
	liveNum("train.depth", 0),
	liveStr("train.depthLabel", ""),
	liveStr("train.depthReason", ""),

	-- rebirth ----------------------------------------------------------------
	num("rebirth.target", 0, 0, 1000000),
	num("rebirth.rate", 0, 0, 300),
	bool("rebirth.lock", false),
	bool("rebirth.duringBoss", true),
	bool("rebirth.duringKill", true),

	-- pets -------------------------------------------------------------------
	bool("pet.autoBuy", false),
	str("pet.selected", ""),
	bool("pet.autoWheel", false),
	bool("pet.autoEgg", false),
	num("pet.eggBatch", 10, 1, 500),
	bool("pet.autoPack", false),

	-- crystals ---------------------------------------------------------------
	--[[
		CRYSTALS (`openCrystalRemote`).

		The protocol was confirmed from a Cobalt recording of the game calling
		itself: `InvokeServer("openCrystal", "<name>")` to hatch and
		`InvokeServer("saveAutoSell", "<name>", { Pets = {..}, Enabled = .., Auras = {} })`
		to persist an auto-sell list. Both are per-crystal, so the selection is a
		NAME from the catalogue rather than a hard-coded one.

		`crystal.auto` defaults OFF like every other action-performing switch:
		opening crystals spends the player's currency.
	]]
	bool("crystal.auto", false),
	str("crystal.selected", ""),
	num("crystal.rate", 2, 1, 20),
	bool("crystal.autoSell", false),
	--[[
		WHICH PETS OF EACH CRYSTAL ARE SOLD.

		`{ [crystalName] = { [petName] = true } }` -- a ticked pet is sold, and
		everything NOT ticked is kept. That is the user's correction of the old
		behaviour, where one button dumped the crystal's entire pool into the sell
		list: "实际上应该是让我来选择出售哪些宠物，就是该水晶的哪些宠物，并且都是
		会保留的".

		Per crystal rather than one flat list, because the pools overlap by name
		and switching crystals must not silently change what is sold.
	]]
	map("crystal.sellByCrystal"),
	--[[
		DEPRECATED, and declared only so an older config still parses.

		The previous build stored one flat `{ name, count }` list here; 1008 -> 1009
		converts it into `crystal.sellByCrystal` under the crystal that was
		selected at the time, and removes it. It stays declared because `preset` is
		a LEAF kind: without the declaration the loader would FLATTEN the old array
		into `crystal.sellPets.1.name` keys and the migration would never see the
		list it has to convert.
	]]
	preset("crystal.sellPets"),

	-- teleport ---------------------------------------------------------------
	bool("tp.autoMK", false),
	bool("tp.loop", false),
	num("tp.loopIdx", 1, 1, 100),

	-- combat -----------------------------------------------------------------
	bool("kill.enabled", false),
	bool("kill.friendWL", false),
	bool("kill.autoKing", false),
	bool("kill.dualEnabled", true),
	bool("kill.single", false),
	str("kill.singleName", ""),
	bool("kill.approach", true),
	--[[
		DEPRECATED, and LIVE on purpose: 全图杀戮 no longer has a range cap.

		The user's rule is "搜索范围是不限制的，它是搜索全图玩家", so the free scan
		asks for the whole map and this number is never read. It stays declared (as
		a LIVE key, so a file from the previous build neither warns "unknown key
		dropped" nor has its value honoured) purely so old configs keep loading
		cleanly -- the same treatment `boss.hoverHeight` got when its slider went
		away.
	]]
	liveNum("kill.range", 400),
	--[[
		CAN WE ACTUALLY WIN? On by default, because the user asked for it as part
		of what 全图杀戮 should do: "计算是否打得过。如果打不过直接跳过".

		`kill.powerMaxHits` is the "相差过大 → 打不死" half: a target whose
		durability needs more than this many punches is skipped even when we would
		win the race. 0 disables that half entirely (it is the only part of the
		comparison that assumes Durability and one punch of Strength share a
		unit). Everything else about the comparison (命中数赛跑) is core/Duel's, and
		it is pure and tested.
	]]
	bool("kill.powerCheck", true),
	num("kill.powerMaxHits", 30, 0, 500),
	--[[
		HOW LONG ONE TARGET MAY HOLD THE LOCK ("如果超时 10 秒没打过，那就给它跳过").

		`kill.targetSkip` is what makes that mean anything: a timed-out player is
		remembered for this long and not considered again, so the loop does not
		simply re-pick the same nearest player on the next scan.
	]]
	num("kill.targetTimeout", 10, 2, 120),
	num("kill.targetSkip", 60, 0, 3600),
	--[[
		SKIP THE NO-DAMAGE AREAS (the seasonal gym, the island, the boss arena).

		On by default because the user asked for all three, but switchable: the
		first version over-skipped ("有很多人异常打不到，很多玩家都被异常跳过了")
		and the fix for that has to be one click away as well as narrower.
	]]
	bool("kill.skipSafeZones", true),
	--[[
		HOW LONG EACH HAND KEEPS THE TOOL.

		Training and punching cannot both hold the hand, so with training enabled
		during combat the hand alternates. The bug this replaces was a pacing
		asymmetry, not a missing feature: the alternation flipped every 0.05 s
		while the glove was ALSO re-equipped on every punch, so the training tool
		never stayed on long enough to register a rep. Both halves now hold for
		the same `kill.dualInterval` seconds.

		The DEFAULT is 0.15 s: the user's own number after two rounds of "工具切换
		太慢了" ("比如说 0.15 秒切换换一次"). One number for both halves keeps the
		swap rates equal by construction; the setting still spans 0.1-3 s.
	]]
	num("kill.dualInterval", 0.15, 0.1, 3),
	--[[
		THE OVERHEAD APPROACH.

		A punch thrown from the target's own height flies over its shoulder --
		the boss fight never had that problem because it hovers above the boss and
		looks DOWN at it. `kill.hoverHeight` gives the kill loop the same shape,
		with a deliberately small default: the target still has to be inside the
		game's punch reach, and for a player-sized hitbox that is a body height,
		not the boss's 70 studs (which is `boss.hoverHeight`).
	]]
	num("kill.hoverHeight", 12, 1, 200),
	--[[
		DIRECT 0.025 s PIN while approaching a PLAYER target.

		Separate from `boss.directPin` on purpose: the two features chase
		different objects with their own positions and their own timers, so one
		switch for both would mean tuning one breaks the other. This one can be
		turned off if a particular place dislikes the write rate.
	]]
	bool("kill.directPin", true),
	bool("kill.lookDown", true),
	bool("kill.targetSizeEnabled", false),
	num("kill.targetSizeMul", 5, 1, 20),

	-- boss -------------------------------------------------------------------
	--[[
		`boss.auto` and `boss.autoChest` and `boss.sizeEnabled` all default OFF.

		`boss.autoChest` used to default TRUE, and the chest task is gated by that
		key ALONE -- so a fresh install (no config file, pure defaults) would watch
		for a boss to die, then TELEPORT the player to the chest and press E, with
		the user having enabled nothing. `boss.sizeEnabled` was TRUE too, and
		`SizePolicy.wanted` returns the boss multiplier whenever a boss is simply
		ALIVE, so it fired a resize remote unprompted as well.

		Anything that moves the character, presses keys or fires a remote must be
		an explicit opt-in. tests/Config.spec.luau pins that invariant.
	]]
	bool("boss.auto", false),
	bool("boss.sizeEnabled", false),
	num("boss.sizeMul", 5, 1, 20),
	--[[
		HOW HIGH THE FIGHT HOVERS -- now FIXED, not a setting.

		The number is geometry, not preference: the arena bosses all use 70 studs
		(`BossInfo.NORMAL_HOVER`) and each event boss carries its own (see
		core/BossInfo's EVENTS table). A slider could break the punch reach, and
		the one that existed defaulted to a value the event bosses could not use.

		The key is kept as a LIVE key (declared so validation and the unknown-key
		check know it, never read, never written) purely so a config file written
		by the previous build does not print "unknown key dropped" -- the value in
		it is ignored.
	]]
	liveNum("boss.hoverHeight", BossInfo.NORMAL_HOVER),
	bool("boss.autoChest", false),
	num("boss.chestDelay", 3, 0, 30),

	--[[
		EVENT BOSSES (万圣节 / 圣诞 等活动 Boss).

		The seasonal arena is a SECOND group: four bosses that can all be alive at
		once, each selected by its own switch, killed one after another in the
		order core/BossInfo lists them (Grim Reaper first). They are NOT part of
		`boss.select.<rarity>`; the checkbox area is two sections.

		NONE of these defaults starts anything on its own: every one of them is
		gated by `boss.auto`, which is still OFF by default -- exactly like the
		per-rarity switches above.
	]]
	enm("boss.priority", "event", BOSS_PRIORITY),
	--[[
		DIRECT 0.025 s PIN while hovering on a boss.

		The user's requirement is a write every 0.025 s with the facing set in the
		same write, and it is a setting rather than a constant because it is the
		one thing to switch off if a place reacts badly to the write rate (it is
		independent of `kill.directPin`: different target, different timer).
	]]
	bool("boss.directPin", true),
	bool("boss.event.enabled", true),
	-- Superseded: each event boss now carries its own fixed hover height
	-- (BossInfo.EVENTS). Live key, same reasoning as `boss.hoverHeight` above.
	liveNum("boss.eventHoverHeight", BossInfo.EVENT_HOVER),
	--[[
		MANUAL SERVER HOP.

		The bosses are per-server, so farming them means leaving once they are all
		down. `boss.event.hopMode` only decides which server the manual button
		goes to; the hop itself goes through the rejoin service, so it is a real
		teleport with the same 3-second CANCELLABLE countdown.
	]]
	enm("boss.event.hopMode", "sparse", HOP_MODES),
	num("boss.event.hopDelay", 5, 0, 120),

	-- own character ----------------------------------------------------------
	bool("size.selfEnabled", false),
	num("size.selfMul", 3, 1, 20),

	-- performance ------------------------------------------------------------
	--[[
		`perf.antiLag` is the master switch; the three below say WHAT it does.

		They exist because the old pass only hid particles and shadows -- "深度防卡顿"
		did nothing about textures or draw distance, which is most of what makes a
		big Roblox place heavy. Each is independently reversible, and every object
		it touches is put back when the switch goes off (see game/Perf).
	]]
	bool("perf.antiLag", false),
	bool("perf.disabled", false),
	bool("perf.removeEffects", true),
	bool("perf.removeTextures", true),
	bool("perf.cull", true),

	-- rejoin -----------------------------------------------------------------
	bool("rejoin.enabled", false),
	bool("rejoin.timedEnabled", false),
	num("rejoin.timedMin", 30, 3, 1440),
	bool("rejoin.emergEnabled", false),
	bool("rejoin.memTrigger", true),
	num("rejoin.memThresh", 4000, 500, 100000),
	bool("rejoin.fpsTrigger", true),
	num("rejoin.fpsThresh", 8, 1, 60),
	bool("rejoin.pingTrigger", true),
	num("rejoin.pingThresh", 800, 100, 5000),
	enm("rejoin.mode", "same", REJOIN_MODES),
	str("rejoin.privId", ""),
	--[[
		跳到一个指定玩家所在的服务器 ("前往目标用户名的服务器").

		The NAME is what the user types; the job id is resolved at rejoin time
		(users.roblox.com -> presence.roblox.com), so a renamed or offline player
		simply falls through to the next rung of the fallback chain instead of
		being an error.
	]]
	str("rejoin.targetPlayer", ""),

	--[[
		Metadata that travels INSIDE a config file rather than describing a
		setting: the display label of a numbered config slot.

		It is declared here so that loading a named save does not warn "unknown
		key dropped" -- the slot label is written by game/Persist after the
		projection, so validation has to know about it. It defaults to empty and
		is never set by a control.
	]]
	str("meta.slotLabel", ""),

	-- machines ---------------------------------------------------------------
	bool("machine.enabled", false),
	str("machine.gymFilter", ""),
	str("machine.nameFilter", ""),
	num("machine.indexFilter", 0, 0, 500),
	--[[
		LET THE MACHINE WIN OVER COMBAT.

		Default OFF, because the arbiter's point is that a machine blocks damage
		(打 Boss > 全城杀戮 > 器械). But with auto-boss on there is almost always a
		boss alive, so the machine stands down essentially forever and reads as
		"启用了器械还是不上". This switch is the explicit override, and when it is
		on the blocked reason says so instead of silently doing nothing.
	]]
	bool("machine.overridesCombat", false),

	-- anti afk ---------------------------------------------------------------
	num("antiAfk.interval", 300, 60, 1140),

	-- behaviour switches -----------------------------------------------------
	enm("cfg.antiPull", "normal", ANTI_PULL),
	bool("cfg.tpPath", true),
	num("cfg.tpMaxTime", 0.5, 0.05, 5),
	bool("cfg.tpStage", true),
	num("cfg.tpRetry", 3, 0, 20),
	num("cfg.tpVerify", 6, 1, 60),
	bool("cfg.tpFallback", true),
	bool("cfg.platform", false),
	bool("cfg.keepPunch", true),
	bool("cfg.autoSuicide", false),
	bool("cfg.toast", true),
	bool("cfg.hotkeys", true),
	num("cfg.netBurst", 40, 1, 500),
	bool("cfg.announce", true),
	-- Wire throttling for the training channel. V1007 had no such switch because
	-- it had no limiter at all; leaving it off preserves the throughput that
	-- "fast training" exists for, while turning it on puts the channel behind a
	-- real token bucket with visible drop/penalty stats.
	bool("cfg.trainThrottle", false),
	-- How often the session's settings are written to disk, in seconds. The user's
	-- requirement is "every 10 seconds, and once immediately when the script is
	-- closed" -- the close-side save lives in `session.stop` and this is the
	-- periodic half. A setting rather than a constant because the write is the
	-- expensive part and a slow executor may want it rarer.
	num("cfg.saveSeconds", 10, 3, 300),
	--[[
		THE 功能存档 MASTER SWITCH (default ON).

		OFF turns the whole persistence layer read-only for this session: the
		autosave and the close-side save stop writing, and the 配置存档 card on
		the settings page answers "已禁用" instead of listing slots. The values
		still load at boot as usual -- this switch only ever decides whether
		anything is WRITTEN back.

		It exists because the file layer is the one part of the script a user
		cannot see: on an executor whose writefile is slow, sandboxed or absent,
		a save that quietly fails is indistinguishable from a save that silently
		overwrites a good profile. One click now stops all writing.
	]]
	bool("cfg.saveEnabled", true),

	-- ui state ---------------------------------------------------------------
	num("uiState.widthPct", 45, 30, 100),
	num("uiState.heightPct", 52, 30, 100),
	num("uiState.uiScale", 100, 50, 125),
	num("uiState.infoScale", 100, 50, 250),
	num("uiState.fontScale", 1, 0.8, 1.5),
	bool("uiState.formatNum", true),
	bool("uiState.infoVisible", false),
	--[[
		Should collapsing the main window also hide the info panel?

		Default OFF: the panel is an overlay whose whole point is to be readable
		while the main window is out of the way (that is what minimising and the
		pill are for). The user's own wording is the spec: the panel "does not
		disappear with the main panel's minimise/pill, unless the player closed it
		themselves". The switch exists so the opposite is one click away instead
		of an argument.
	]]
	bool("uiState.infoHideWithShell", false),
	enm("uiState.theme", "light", THEMES),
	bool("uiState.minimized", false),
	--[[
		Bumped once the in-place theme repaint has FINISHED.

		The repaint tweens colours over ~0.4 s, and a second pass re-runs at
		+0.55 s to catch widgets that were mid-tween. Pages that own colours no
		remap can reach (the theme page's own selected marker) would otherwise be
		left holding a colour from the previous palette -- the "仍然残存绿色" the
		user reported twice. Subscribing to this counter is how a page knows the
		repaint is over and it may re-assert its own colours.
	]]
	liveNum("uiState.themeEpoch", 0),
	-- The collapsed pill is a window mode exactly like `minimized`, so it lives
	-- in the store too rather than in a field only the shell can see -- but as a
	-- LIVE key: a reload always comes back as a normal window, and only the
	-- pill's dragged position (`uiState.savedPill` below) is remembered.
	live("uiState.pill", false),
	pos("uiState.savedMain"),
	pos("uiState.savedPill"),
	pos("uiState.savedInfo"),
	pos("uiState.savedInfoSize"),

	-- pet presets ------------------------------------------------------------
	bool("petPreset.autoSwitch", false),
	preset("petPreset.train"),
	preset("petPreset.rebirth"),
	preset("petPreset.kill"),
	preset("petPreset.boss"),

	-- live runtime state -----------------------------------------------------
	-- Written by the UI and read by the scheduler, but deliberately NOT
	-- persisted: a reload must never come up paused.
	live("runtime.paused", false),
}

for _, rarity in ipairs(RARITIES) do
	table.insert(SCHEMA, bool("boss.select." .. rarity, true))
end

-- One switch per EVENT boss, derived from the same list the detector walks so
-- the two can never name different bosses. Path shape: `boss.event.<key>`.
for _, entry in ipairs(BossInfo.events()) do
	table.insert(SCHEMA, bool("boss.event." .. entry.key, true))
end

Config.SCHEMA = SCHEMA

--[[
	Which paths actually reach the file?

	Built after the schema is complete (the rarity loop above appends to it) and
	used by the save path's dirty tracking: a change to a live key -- the pause
	switch, the pill mode -- must NOT mark the config dirty, or those keys would
	trigger a pointless disk write on every toggle.
]]
local PERSISTABLE: { [string]: boolean } = {}
for _, spec in ipairs(SCHEMA) do
	if spec.persist ~= false then
		PERSISTABLE[spec.path] = true
	end
end

function Config.isPersisted(path: string): boolean
	return PERSISTABLE[path] == true
end

--[[
	Is the 功能存档 layer allowed to write?

	Read from the FLAT store map rather than from a live Store so the rule is
	pure and testable, and so there is exactly one spelling of it: the game-side
	Persist asks this question before the autosave and before both slot paths.

	Only an explicit `false` disables writing. A missing key (an OLD config that
	predates the switch, or a test double with no schema) means ON, because
	defaulting to "do not save" would silently stop persisting for every user who
	upgrades.
]]
function Config.canSave(values: { [string]: any }?): boolean
	if type(values) ~= "table" then
		return true
	end
	return values["cfg.saveEnabled"] ~= false
end

-- Kinds whose value is a record, not a subtree: flattening must stop here or a
-- position like { xs = 0, xo = 640 } would become un-validatable leaf paths.
local LEAF_KINDS: { [string]: boolean } = { position = true, preset = true, map = true }

--[[
	Migrations, keyed by the version they upgrade FROM.

	Each step mutates the flat map in place and the chain is walked up to
	Config.VERSION. Declaring them here (instead of branching inside the loader)
	means an old config is upgraded by a fixed, testable sequence.
]]
local MIGRATIONS: Steps = {
	-- 1007 -> 1008: V1007 wrote this same shape under mk_v1007.json, so the step
	-- only has to stamp the version. It exists as a real entry so that the next
	-- rename has an obvious home.
	[1007] = function(_data: { [string]: any }) end,
	--[[
		1008 -> 1009: the crystal auto-sell list became per crystal.

		The old shape was one flat `{ name, count }` array at
		`crystal.sellPets`; it is moved under whatever crystal was selected at the
		time, because the old list was always "the pets of the crystal you had
		chosen". The old key is then REMOVED, so a converted file does not keep
		carrying a second copy of the same selection (and so the deprecated schema
		entry only ever holds its default).
	]]
	[1008] = function(data: { [string]: any })
		local old = data["crystal.sellPets"]
		if type(old) ~= "table" then
			return
		end
		local crystal = data["crystal.selected"]
		if type(crystal) ~= "string" or crystal == "" then
			-- No crystal recorded: there is nothing to attach the names to, so
			-- they are dropped rather than filed under a placeholder that no
			-- crystal picker could ever match.
			data["crystal.sellPets"] = nil
			return
		end
		local byCrystal = data["crystal.sellByCrystal"]
		if type(byCrystal) ~= "table" then
			byCrystal = {}
			data["crystal.sellByCrystal"] = byCrystal
		end
		local entry = byCrystal[crystal]
		if type(entry) ~= "table" then
			entry = {}
			byCrystal[crystal] = entry
		end
		for _, row in ipairs(old) do
			if type(row) == "table" and type(row.name) == "string" and row.name ~= "" then
				entry[row.name] = true
			end
		end
		data["crystal.sellPets"] = nil
	end,
}

local function defaultFor(spec: Spec): any
	if type(spec.default) == "table" then
		return table.clone(spec.default)
	end
	return spec.default
end

local function validate(spec: Spec, raw: any): (any, string?)
	if raw == nil then
		return defaultFor(spec)
	end

	local kind = spec.kind
	if kind == "boolean" then
		if type(raw) == "boolean" then
			return raw
		end
		return defaultFor(spec), "expected boolean, got " .. type(raw)
	end

	if kind == "number" then
		if type(raw) ~= "number" or raw ~= raw then
			return defaultFor(spec), "expected number, got " .. type(raw)
		end
		if spec.min ~= nil and raw < spec.min then
			return spec.min, string.format("below minimum %s, clamped", tostring(spec.min))
		end
		if spec.max ~= nil and raw > spec.max then
			return spec.max, string.format("above maximum %s, clamped", tostring(spec.max))
		end
		return raw
	end

	if kind == "string" then
		if type(raw) == "string" then
			return raw
		end
		return defaultFor(spec), "expected string, got " .. type(raw)
	end

	if kind == "enum" then
		if type(raw) == "string" then
			for _, allowed in ipairs(spec.values or {}) do
				if allowed == raw then
					return raw
				end
			end
		end
		return defaultFor(spec), string.format("'%s' is not an allowed value", tostring(raw))
	end

	if kind == "position" then
		if type(raw) == "table" then
			local xs, xo, ys, yo = raw.xs, raw.xo, raw.ys, raw.yo
			if type(xs) == "number" and type(xo) == "number" and type(ys) == "number" and type(yo) == "number" then
				return { xs = xs, xo = xo, ys = ys, yo = yo }
			end
		end
		return defaultFor(spec), "expected a position record"
	end

	if kind == "preset" then
		if type(raw) ~= "table" then
			return defaultFor(spec), "expected a preset table"
		end
		local out: { { name: string, count: number } } = {}
		for _, entry in ipairs(raw) do
			if type(entry) == "table" and type(entry.name) == "string" then
				-- `entry` narrows to `{ read name: string }` after the check above,
				-- so the sibling field has to be read through `any`.
				local count = tonumber((entry :: any).count) or 1
				table.insert(out, {
					name = entry.name,
					count = math.max(1, math.floor(count)),
				})
			end
		end
		return out
	end

	if kind == "map" then
		if type(raw) ~= "table" then
			return defaultFor(spec), "expected a map table"
		end
		--[[
			One level of nesting, strings for keys and booleans for values.

			Anything else is DROPPED (and warned about) rather than repaired: this
			holds user selections from a UI, so an unexpected shape means the file
			was hand-edited or written by a different build -- guessing what was
			meant would be worse than starting that entry empty.
		]]
		local out: { [string]: any } = {}
		local dropped = false
		for key, value in pairs(raw) do
			if type(key) == "string" then
				if type(value) == "boolean" then
					out[key] = value
				elseif type(value) == "table" then
					local nested: { [string]: boolean } = {}
					for innerKey, innerValue in pairs(value) do
						if type(innerKey) == "string" and type(innerValue) == "boolean" then
							nested[innerKey] = innerValue
						else
							dropped = true
						end
					end
					out[key] = nested
				else
					dropped = true
				end
			else
				dropped = true
			end
		end
		if dropped then
			return out, "some map entries were not name -> boolean and were dropped"
		end
		return out
	end

	return defaultFor(spec), "unknown schema kind '" .. tostring(kind) .. "'"
end

--[[
	Walk the migration chain from the file's version up to Config.VERSION.
	`steps` is injectable so the sequence itself can be tested without inventing
	real historical formats.
]]
function Config.migrate(flat: { [string]: any }, steps: Steps?): { [string]: any }
	local chain = steps or MIGRATIONS
	local data = table.clone(flat)
	local version = tonumber(data["version"]) or 1007
	while version < Config.VERSION do
		local step = chain[version]
		if step ~= nil then
			step(data)
		end
		version += 1
	end
	data["version"] = Config.VERSION
	return data
end

--[[
	Turn raw decoded JSON into validated flat state.

	Accepts the nested shape V1007 wrote (and any older one), and returns a flat
	path -> value map plus the list of corrections that were applied.
]]
function Config.normalize(raw: any, steps: Steps?): Report
	local warnings: { string } = {}
	local flat: { [string]: any } = {}
	if type(raw) == "table" then
		local leafPaths: { [string]: boolean } = {}
		for _, spec in ipairs(SCHEMA) do
			if LEAF_KINDS[spec.kind] then
				leafPaths[spec.path] = true
			end
		end
		flat = Store.flatten(raw, function(path: string): boolean
			return leafPaths[path] == true
		end)
	end

	local version = tonumber(flat["version"])
	local migratedFrom: number? = nil
	if version == nil or version < Config.VERSION then
		migratedFrom = version
		flat = Config.migrate(flat, steps)
		table.insert(warnings, string.format("config upgraded from %s to %d",
			if version == nil then "an unversioned file" else tostring(version), Config.VERSION))
	elseif version > Config.VERSION then
		table.insert(warnings, string.format("config version %d is newer than %d; validating anyway", version, Config.VERSION))
	end

	local values: { [string]: any } = {}
	local known: { [string]: boolean } = {}
	for _, spec in ipairs(SCHEMA) do
		known[spec.path] = true
		if spec.persist == false then
			-- Live keys are never taken from the file. A file that happens to
			-- contain one (an older build, a hand edit) must not be able to boot
			-- the script paused, and reporting it as a dropped unknown key would
			-- be wrong -- it IS a declared key, just not a persisted one.
			values[spec.path] = defaultFor(spec)
		else
			local value, problem = validate(spec, flat[spec.path])
			if problem ~= nil then
				table.insert(warnings, spec.path .. ": " .. problem)
			end
			values[spec.path] = value
		end
	end

	for path in pairs(flat) do
		if path ~= "version" and not known[path] and RETIRED[path] ~= true then
			table.insert(warnings, path .. ": unknown key dropped")
		end
	end

	return { values = values, warnings = warnings, migratedFrom = migratedFrom }
end

-- Every default, as a flat map. Used to seed a store before a file is read.
function Config.defaults(): { [string]: any }
	local out: { [string]: any } = {}
	for _, spec in ipairs(SCHEMA) do
		out[spec.path] = defaultFor(spec)
	end
	return out
end

--[[
	Keep only the keys the schema declares AND that are meant to be persisted.

	This is the structural fix for "the config never saved". V1007 handed live
	state straight to JSONEncode; Core.machine held Instance fields, the encoder
	threw, and the surrounding pcall swallowed it -- every setting was silently
	discarded, forever. Projecting through the schema first makes that impossible
	by construction: a value with no schema entry cannot reach the encoder.

	Live keys (`persist = false`) are filtered out here too, so this is the ONE
	place that decides what is written. Persist.save delegates to it rather than
	re-deriving the list, which is how a filter added here would otherwise be
	silently bypassed on the save path.
]]
function Config.project(flat: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, spec in ipairs(SCHEMA) do
		if spec.persist ~= false then
			local value = flat[spec.path]
			if value ~= nil then
				out[spec.path] = value
			end
		end
	end
	return out
end

return Config
end

__modules["core/Path"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Path -- teleport path planning. Pure: plain {x,y,z} records, no Roblox.

	The reasoning behind the algorithm is the whole anti-pullback strategy:

	  * Teleporting hundreds of studs in a single frame trips a server-side
	    distance check, which snaps the player back. Walking the distance in small
	    steps mostly stays under that check.
	  * The trip must still feel instant, so the step size is derived from a TIME
	    BUDGET: hops = budget / interval, and each step carries total/hops studs.
	    Close targets get many small steps, far targets get fewer larger ones.
	  * An optional vertical arc keeps the path off the ground.

	This module only computes the waypoints, so the arithmetic is unit-testable.
]]

local Path = {}

export type Vec3 = { x: number, y: number, z: number }

export type Options = {
	maxTime: number?,
	interval: number?,
	minStep: number?,
	arc: number?,
}

export type Plan = {
	points: { Vec3 },
	hops: number,
	step: number,
	total: number,
	duration: number,
}

local DEFAULT_MAX_TIME = 0.5
local DEFAULT_INTERVAL = 0.015
local DEFAULT_MIN_STEP = 22

local function vec(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

function Path.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Plan a stepped path from `from` to `to`.
-- The returned point list always ends EXACTLY on `to` (no accumulated floating
-- point drift), and never contains more than maxTime/interval points.
function Path.plan(from: Vec3, to: Vec3, options: Options?): Plan
	local opts: Options = options or {}
	local interval = math.max(0.001, opts.interval or DEFAULT_INTERVAL)
	local budget = math.max(interval, opts.maxTime or DEFAULT_MAX_TIME)
	local minStep = math.max(0.001, opts.minStep or DEFAULT_MIN_STEP)
	local arc = opts.arc or 0

	local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
	local total = math.sqrt(dx * dx + dy * dy + dz * dz)

	if total <= 0.001 then
		return {
			points = { vec(to.x, to.y, to.z) },
			hops = 1,
			step = 0,
			total = total,
			duration = 0,
		}
	end

	local maxHops = math.max(2, math.floor(budget / interval))
	local step = math.max(minStep, total / maxHops)
	local hops = math.max(1, math.min(maxHops, math.ceil(total / math.max(4, step))))
	local ux, uy, uz = dx / total, dy / total, dz / total

	local points: { Vec3 } = {}
	for k = 1, hops do
		local travelled = math.min(total, step * k)
		local px = from.x + ux * travelled
		local py = from.y + uy * travelled
		local pz = from.z + uz * travelled
		if arc ~= 0 then
			local fraction = travelled / total
			py += arc * math.sin(fraction * math.pi)
		end
		if k >= hops then
			px, py, pz = to.x, to.y, to.z
		end
		table.insert(points, vec(px, py, pz))
	end

	return {
		points = points,
		hops = hops,
		step = step,
		total = total,
		duration = hops * interval,
	}
end

return Path
end

__modules["core/Timers"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Timers -- cancellable delayed and repeating callbacks. Pure: no task.delay.

	Raw `task.delay(...)` cannot be cancelled, so on unload every pending callback
	still ran and had to defend itself with `if d.Parent then ... end` guards.
	Guards are a symptom; the fix is that a timer is an object you can cancel, and
	that all of them die together when the script unloads.

	There is no scheduler thread here on purpose. The host calls `step(now)` once
	per frame and this registry decides what is due: no coroutine per timer, no
	wake-ups on frames where nothing is due, deterministic ordering, and the whole
	thing is unit-testable with a virtual clock.

	`now` is always passed in rather than read from os.clock, so a test can drive
	time by hand and a caller can share one timestamp across many timers.
]]

local Timers = {}
Timers.__index = Timers

export type Handle = {
	cancel: (Handle) -> (),
	active: (Handle) -> boolean,
}

export type ErrorHandler = (message: string) -> ()

type Entry = {
	due: number,
	interval: number?,
	fn: () -> (),
	alive: boolean,
	seq: number,
}

export type Timers = {
	_entries: { Entry },
	_seq: number,
	_onError: ErrorHandler?,
	after: (Timers, now: number, delay: number, fn: () -> ()) -> Handle,
	every: (Timers, now: number, interval: number, fn: () -> (), immediate: boolean?) -> Handle,
	step: (Timers, now: number) -> (number, number),
	cancelAll: (Timers) -> (),
	count: (Timers) -> number,
}

local function newHandle(owner: Timers, entry: Entry): Handle
	return {
		cancel = function()
			if not entry.alive then
				return
			end
			entry.alive = false
			for i = #owner._entries, 1, -1 do
				if owner._entries[i] == entry then
					table.remove(owner._entries, i)
					break
				end
			end
		end,
		active = function(): boolean
			return entry.alive
		end,
	}
end

function Timers.new(onError: ErrorHandler?): Timers
	local self = setmetatable({ _entries = {}, _seq = 0, _onError = onError }, Timers)
	return (self :: any) :: Timers
end

-- One-shot. Fires on the first step whose `now` has reached the deadline.
function Timers.after(self: Timers, now: number, delay: number, fn: () -> ()): Handle
	self._seq += 1
	local entry: Entry = {
		due = now + math.max(0, delay),
		interval = nil,
		fn = fn,
		alive = true,
		seq = self._seq,
	}
	table.insert(self._entries, entry)
	return newHandle(self, entry)
end

-- Repeating. Without `immediate` the first run happens one interval from now.
-- The next run is scheduled from the CURRENT time, not from the previous
-- deadline, so a slow frame cannot make a repeating timer fire several times in
-- a row to "catch up".
function Timers.every(self: Timers, now: number, interval: number, fn: () -> (), immediate: boolean?): Handle
	local period = math.max(0.001, interval)
	self._seq += 1
	local entry: Entry = {
		due = if immediate then now else now + period,
		interval = period,
		fn = fn,
		alive = true,
		seq = self._seq,
	}
	table.insert(self._entries, entry)
	return newHandle(self, entry)
end

-- Fire everything that is due at `now`. Returns (fired, failed). A callback that
-- throws never stops the others: the error is counted and handed to onError.
function Timers.step(self: Timers, now: number): (number, number)
	local due: { Entry } = {}
	for _, entry in ipairs(self._entries) do
		if entry.alive and entry.due <= now then
			table.insert(due, entry)
		end
	end

	-- Deterministic order: earliest deadline first, ties broken by insertion.
	table.sort(due, function(a: Entry, b: Entry): boolean
		if a.due == b.due then
			return a.seq < b.seq
		end
		return a.due < b.due
	end)

	local fired = 0
	local failed = 0
	for _, entry in ipairs(due) do
		if not entry.alive then
			continue
		end
		if entry.interval == nil then
			entry.alive = false
		else
			entry.due = now + entry.interval
		end
		fired += 1
		local ok, err = pcall(entry.fn)
		if not ok then
			failed += 1
			local handler = self._onError
			if handler ~= nil then
				handler(tostring(err))
			end
		end
	end

	for i = #self._entries, 1, -1 do
		if not self._entries[i].alive then
			table.remove(self._entries, i)
		end
	end

	return fired, failed
end

function Timers.cancelAll(self: Timers)
	for _, entry in ipairs(self._entries) do
		entry.alive = false
	end
	table.clear(self._entries)
end

function Timers.count(self: Timers): number
	local n = 0
	for _, entry in ipairs(self._entries) do
		if entry.alive then
			n += 1
		end
	end
	return n
end

return Timers
end

__modules["core/Scheduler"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Scheduler -- one task model, replacing three. Pure: the host drives `step`.

	V1007 ran three overlapping concurrency APIs at once (ad-hoc coroutines via
	spawn/threads/cancel, interval loops via startWorker/workers, and the real
	registerTask/tasks/cancelTask scheduler), plus 20-odd task coroutines that each
	woke EVERY frame (`while ... do task.wait(); pcall(t.enabled); pcall(t.tick) end`).
	A frame cost 20+ coroutine switches and 40+ pcalls even when nothing was
	enabled, and cancellation relied on `coroutine.status` before `task.cancel` -- a
	check-then-act race that only `pcall` was hiding.

	So tasks are plain records with an `enabled()` predicate and a `tick(dt, now)`
	callback; the host calls `step(dt, now)` once per frame. Cost is proportional
	to tasks that actually run, there is no `coroutine.status` check and no TOCTOU
	race, enable/disable transitions are explicit so `onEnable`/`onDisable` fire
	exactly once each, and repeated failures disable a task for a backoff window
	and report why.

	Ordering is priority (high first), then registration order, so the same input
	always produces the same sequence.
]]

local Scheduler = {}
Scheduler.__index = Scheduler

export type Task = {
	id: string,
	priority: number?,
	essential: boolean?,
	enabled: () -> boolean,
	tick: ((dt: number, now: number) -> ())?,
	onEnable: (() -> ())?,
	onDisable: (() -> ())?,
}

export type Options = {
	failureLimit: number?,
	backoff: number?,
	onError: ((taskId: string, message: string) -> ())?,
}

export type Snapshot = {
	id: string,
	active: boolean,
	failures: number,
	disabledUntil: number,
}

type Entry = {
	task: Task,
	active: boolean,
	failures: number,
	disabledUntil: number,
	order: number,
	removed: boolean,
	-- `now` of the last tick that ran, for the liveness watchdog.
	lastRun: number,
	-- `now` the entry became active, so a task that has never ticked can be told
	-- apart from one that stopped.
	activeSince: number,
	-- Last `step` in which this entry held the body slot. See Scheduler.claim.
	claimStep: number,
}

export type Scheduler = {
	_entries: { Entry },
	_dirty: boolean,
	_seq: number,
	_paused: boolean,
	_failureLimit: number,
	_backoff: number,
	_onError: ((string, string) -> ())?,
	register: (Scheduler, Task) -> (),
	unregister: (Scheduler, string) -> (),
	has: (Scheduler, string) -> boolean,
	step: (Scheduler, dt: number, now: number) -> number,
	setPaused: (Scheduler, boolean) -> (),
	isPaused: (Scheduler) -> boolean,
	active: (Scheduler) -> { string },
	snapshot: (Scheduler) -> { Snapshot },
	stalled: (Scheduler, number, number?) -> { string },
	current: (Scheduler) -> string?,
	claim: (Scheduler, string) -> (boolean, string?),
	bodyOwner: (Scheduler) -> string?,
	release: (Scheduler, string) -> (),
	_frames: number,
	_current: string?,
}

local DEFAULT_FAILURE_LIMIT = 60
local DEFAULT_BACKOFF = 30
-- How long an ACTIVE task may go without ticking before `stalled` reports it.
local DEFAULT_STALE_SECONDS = 8

function Scheduler.new(options: Options?): Scheduler
	local opts: Options = options or {}
	local self = setmetatable({
		_entries = {},
		_dirty = false,
		_seq = 0,
		_paused = false,
		_failureLimit = opts.failureLimit or DEFAULT_FAILURE_LIMIT,
		_backoff = opts.backoff or DEFAULT_BACKOFF,
		_onError = opts.onError,
		_frames = 0,
		_current = nil,
	}, Scheduler)
	return (self :: any) :: Scheduler
end

local function report(scheduler: Scheduler, taskId: string, err: any)
	local handler = scheduler._onError
	if handler ~= nil then
		handler(taskId, tostring(err))
	end
end

local function findEntry(self: Scheduler, id: string): Entry?
	for _, entry in ipairs(self._entries) do
		if entry.task.id == id then
			return entry
		end
	end
	return nil
end

function Scheduler.has(self: Scheduler, id: string): boolean
	return findEntry(self, id) ~= nil
end

function Scheduler.register(self: Scheduler, definition: Task)
	local existing = findEntry(self, definition.id)
	if existing ~= nil then
		--[[
			Re-registering replaces the definition and DEACTIVATES the entry, so the
			next step re-evaluates enablement and fires the NEW definition's onEnable.
			The old definition's onDisable fires first, because the new task is not a
			continuation of the old: leaving the entry `active` would carry the
			previous task's setup into its replacement and the new onEnable would
			never run.

			Failure accounting is reset for the same reason -- a re-registered task is
			a fresh task, and inheriting a backoff window would delay it for nothing.
		]]
		if existing.active then
			existing.active = false
			local hook = existing.task.onDisable
			if hook ~= nil then
				pcall(hook)
			end
		end
		existing.task = definition
		existing.failures = 0
		existing.disabledUntil = 0
		existing.lastRun = 0
		existing.activeSince = 0
		self._dirty = true
		return
	end
	self._seq += 1
	table.insert(self._entries, {
		task = definition,
		active = false,
		failures = 0,
		disabledUntil = 0,
		order = self._seq,
		removed = false,
		lastRun = 0,
		activeSince = 0,
		claimStep = 0,
	})
	self._dirty = true
end

function Scheduler.unregister(self: Scheduler, id: string)
	for i = #self._entries, 1, -1 do
		local entry = self._entries[i]
		if entry.task.id == id then
			if entry.active then
				entry.active = false
				local hook = entry.task.onDisable
				if hook ~= nil then
					pcall(hook)
				end
			end
			entry.removed = true
			table.remove(self._entries, i)
		end
	end
	self._dirty = true
end

function Scheduler.setPaused(self: Scheduler, paused: boolean)
	self._paused = paused
end

function Scheduler.isPaused(self: Scheduler): boolean
	return self._paused
end

local function sortEntries(self: Scheduler)
	if not self._dirty then
		return
	end
	self._dirty = false
	table.sort(self._entries, function(a: Entry, b: Entry): boolean
		local pa = a.task.priority or 0
		local pb = b.task.priority or 0
		if pa == pb then
			return a.order < b.order
		end
		return pa > pb
	end)
end

-- Run one frame.
--
-- Returns how many tasks ticked. A task that stops being enabled (or is skipped
-- because the scheduler is paused and it is not essential) gets `onDisable`
-- exactly once, on the transition out of active state.
function Scheduler.step(self: Scheduler, dt: number, now: number): number
	sortEntries(self)
	local ran = 0
	--[[
		THE FRAME COUNTER, and why the body slot is measured in FRAMES.

		A claim is only valid for the frame that made it: a task that stops asking
		(its `enabled()` went false, its guard latched, it threw) loses the slot on
		the very next step instead of holding it until some timeout. Frames, not
		seconds, because the answer has to be identical on a 240 Hz desktop and a
		30 Hz phone.
	]]
	self._frames += 1

	-- Iterate a snapshot: a tick is allowed to register or unregister tasks, and
	-- mutating the live list mid-iteration would silently skip entries.
	local entries = table.clone(self._entries)
	for _, entry in ipairs(entries) do
		if entry.removed then
			continue
		end
		-- Named `current`, not `task`: a local called `task` shadows the Roblox
		-- global task table, so any task.wait/spawn inside this scope would
		-- resolve to the task DEFINITION and fail.
		local current = entry.task
		-- Published so a hook inside the tick can ask "who is asking?".
		self._current = current.id

		if entry.disabledUntil ~= 0 and entry.disabledUntil <= now then
			entry.disabledUntil = 0
			entry.failures = 0
		end

		local allowed = true
		if self._paused and current.essential ~= true then
			allowed = false
		end
		if entry.disabledUntil > now then
			allowed = false
		end

		local enabled = false
		if allowed then
			local ok, result = pcall(current.enabled)
			if ok then
				enabled = result == true
			else
				entry.failures += 1
				report(self, current.id, result)
				if entry.failures >= self._failureLimit then
					entry.disabledUntil = now + self._backoff
					entry.failures = 0
				end
			end
		end

		if allowed and enabled then
			if not entry.active then
				entry.active = true
				entry.activeSince = now
				local hook = current.onEnable
				if hook ~= nil then
					local ok, err = pcall(hook)
					if not ok then
						report(self, current.id, err)
					end
				end
			end
			local tick = current.tick
			if tick ~= nil then
				local ok, err = pcall(tick, dt, now)
				if ok then
					entry.failures = 0
					entry.lastRun = now
				else
					entry.failures += 1
					report(self, current.id, err)
					if entry.failures >= self._failureLimit then
						entry.disabledUntil = now + self._backoff
						entry.failures = 0
					end
				end
			else
				-- A task with no `tick` runs nothing on purpose (`stalled` excludes
				-- those); the stamp only keeps the entry's timeline coherent.
				entry.lastRun = now
			end
			ran += 1
		elseif entry.active then
			entry.active = false
			local hook = current.onDisable
			if hook ~= nil then
				local ok, err = pcall(hook)
				if not ok then
					report(self, current.id, err)
				end
			end
		end
	end

	self._current = nil
	return ran
end

--[[
	WHO IS DRIVING THE CHARACTER THIS FRAME?

	Priority order answers "who may START first" -- which turned out not to be the
	question that mattered. Two tasks can both be enabled and both write the
	character's position, and the one that runs LAST wins, so a low-priority loop
	undid a higher-priority task that had already run in the same frame:
	"多个不同的循环传送任务会互相挤占，并且有的时候会忽略优先级" -- the character is
	flung between destinations and reaches neither.

	So a task that MOVES THE CHARACTER has to claim the slot:

	  * a task that never claims may still move (nothing is taken from code that
	    has not opted in);
	  * among tasks claiming in the same frame the highest priority owns it, ties
	    going to the earlier registration;
	  * a claim lives for ONE frame, so standing down is enough to hand the
	    character over -- there is no lock to forget to release.

	Returns `true` when the caller may move, or `false` plus the id of the task
	that owns the body instead, so the loser can say why it stood down.
]]
function Scheduler.current(self: Scheduler): string?
	return self._current
end

function Scheduler.bodyOwner(self: Scheduler): string?
	local frame = self._frames
	for _, entry in ipairs(self._entries) do
		if entry.claimStep == frame and not entry.removed then
			return entry.task.id
		end
	end
	return nil
end

function Scheduler.claim(self: Scheduler, id: string): (boolean, string?)
	local me = findEntry(self, id)
	if me == nil then
		-- An unregistered id (a timer, a UI button, a task acting for another) is
		-- not part of the arbitration: it always gets the body. The slot only ever
		-- excludes REGISTERED tasks from each other.
		return true, nil
	end
	local frame = self._frames
	local holder: Entry? = nil
	for _, entry in ipairs(self._entries) do
		if entry.claimStep == frame and not entry.removed and entry ~= me then
			holder = entry
			break
		end
	end
	if holder == nil then
		me.claimStep = frame
		return true, nil
	end
	local mine = me.task.priority or 0
	local theirs = holder.task.priority or 0
	local wins = mine > theirs or (mine == theirs and me.order < holder.order)
	if not wins then
		return false, holder.task.id
	end
	-- Preemption: the loser's claim is dropped for this frame, so re-asking later
	-- in the same frame gives the same answer -- stable inside a frame, which is
	-- what makes it testable.
	holder.claimStep = 0
	me.claimStep = frame
	return true, nil
end

function Scheduler.release(self: Scheduler, id: string)
	local entry = findEntry(self, id)
	if entry ~= nil then
		entry.claimStep = 0
	end
end

function Scheduler.active(self: Scheduler): { string }
	sortEntries(self)
	local out: { string } = {}
	for _, entry in ipairs(self._entries) do
		if entry.active then
			table.insert(out, entry.task.id)
		end
	end
	return out
end

function Scheduler.snapshot(self: Scheduler): { Snapshot }
	sortEntries(self)
	local out: { Snapshot } = {}
	for _, entry in ipairs(self._entries) do
		table.insert(out, {
			id = entry.task.id,
			active = entry.active,
			failures = entry.failures,
			disabledUntil = entry.disabledUntil,
		})
	end
	return out
end

--[[
	Tasks that are active but have not ticked for `staleSeconds`.

	The scheduler handles a task that THROWS (failures, then a backoff window);
	it cannot see one that simply stops doing anything -- an `enabled()` that began
	returning false for the wrong reason, a guard that latched, a `tick` returning
	early because a clock it reads went backwards. From the outside those look
	exactly like a working task.

	Deliberately a REPORT, not an action: restarting a task that stopped on purpose
	would undo whatever the guard was protecting against, so the host decides. The
	threshold is generous -- the slowest real cadence in this script is the 60 s
	metrics sample, and those are timers rather than tasks; every registered task
	is expected to tick within a second or two.
]]
function Scheduler.stalled(self: Scheduler, now: number, staleSeconds: number?): { string }
	local limit = staleSeconds or DEFAULT_STALE_SECONDS
	local out: { string } = {}
	for _, entry in ipairs(self._entries) do
		-- A task with no `tick` is a pure enable/disable hook: "has not run" is its
		-- normal state, and stamping its clock would not help -- the stamp never
		-- advances, so it would be reported again as soon as the window elapsed.
		if entry.active and not entry.removed and entry.task.tick ~= nil then
			local since = if entry.lastRun > 0 then entry.lastRun else entry.activeSince
			if since > 0 and now - since > limit then
				table.insert(out, entry.task.id)
			end
		end
	end
	return out
end

return Scheduler
end

__modules["core/Net"] = function()
	local require = __require
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Net -- sends that cannot flood. Pure: the transport is injected.

	A channel declared with no rate really is unlimited (fast training needs
	that), but it is now a visible per-channel decision:

	  * every channel owns a token bucket (core/RateLimiter);
	  * a send the limiter refuses is either queued (bounded) or dropped, and
	    drops are counted per channel;
	  * a transport error feeds multiplicative backoff, so a server that starts
	    rejecting makes us slow down on our own before it escalates;
	  * stats() reports sent / dropped / queued / penalty, so the UI can show it
	    instead of the user guessing.
]]

local RateLimiter = require("core/RateLimiter")

local Net = {}
Net.__index = Net

export type Sender = (...any) -> (boolean, string?)

export type ChannelOptions = {
	rate: number?,
	burst: number?,
	queue: number?,
	dropOldest: boolean?,
}

export type ChannelStats = {
	sent: number,
	dropped: number,
	queued: number,
	denied: number,
	penalty: number,
}

export type Stats = { [string]: ChannelStats }

export type Options = {
	onError: ((channel: string, message: string) -> ())?,
	onDrop: ((channel: string, total: number) -> ())?,
}

-- Structural stand-in for core/RateLimiter's exported type: keeps this module
-- free of a cross-module type dependency that the analyzer would have to
-- resolve through require().
type LimiterLike = {
	allow: (LimiterLike, number, number?) -> boolean,
	reportFailure: (LimiterLike, number) -> (),
	reportSuccess: (LimiterLike, number) -> (),
	reset: (LimiterLike, number) -> (),
	stats: (LimiterLike, number) -> any,
}

type Packed = { [number]: any, n: number }

export type Channel = {
	name: string,
	sender: Sender,
	limiter: LimiterLike?,
	queue: { Packed },
	capacity: number,
	dropOldest: boolean,
	dropped: number,
	sent: number,
}

export type Dispatcher = {
	_channels: { [string]: Channel },
	_order: { string },
	_onError: ((string, string) -> ())?,
	_onDrop: ((string, number) -> ())?,
	addChannel: (Dispatcher, string, Sender, ChannelOptions?) -> Channel,
	channel: (Dispatcher, string) -> Channel?,
	send: (Dispatcher, string, number, ...any) -> boolean,
	-- `burst` is the training path's entry point (attempt N sends, stop at the
	-- first refusal) and is part of the public surface.
	burst: (Dispatcher, string, number, number, ...any) -> number,
	enqueue: (Dispatcher, string, ...any) -> boolean,
	flush: (Dispatcher, number) -> number,
	reportFailure: (Dispatcher, string, number) -> (),
	reportSuccess: (Dispatcher, string, number) -> (),
	stats: (Dispatcher, number) -> Stats,
	pending: (Dispatcher) -> number,
	reset: (Dispatcher, number) -> (),
}

local function report(self: Dispatcher, channel: string, message: string)
	local handler = self._onError
	if handler ~= nil then
		handler(channel, message)
	end
end

local function notifyDrop(self: Dispatcher, channel: Channel)
	local handler = self._onDrop
	if handler ~= nil then
		handler(channel.name, channel.dropped)
	end
end

-- Dispatch one payload.
--
-- Returns (sent, denied): `denied` means the limiter refused, so retrying later
-- is meaningful. A transport failure is (false, false): the payload is bad or
-- the remote is gone, and re-queueing it would just fail again.
local function trySend(self: Dispatcher, channel: Channel, now: number, args: Packed): (boolean, boolean)
	local limiter = channel.limiter
	if limiter ~= nil and not limiter:allow(now) then
		return false, true
	end

	local ok, sent, message = pcall(channel.sender, table.unpack(args, 1, args.n))
	if not ok then
		if limiter ~= nil then
			limiter:reportFailure(now)
		end
		report(self, channel.name, tostring(sent))
		return false, false
	end
	if sent == true then
		channel.sent += 1
		if limiter ~= nil then
			limiter:reportSuccess(now)
		end
		return true, false
	end

	if limiter ~= nil then
		limiter:reportFailure(now)
	end
	report(self, channel.name, tostring(message))
	return false, false
end

local function queueOrDrop(self: Dispatcher, channel: Channel, args: Packed): boolean
	if channel.capacity <= 0 then
		channel.dropped += 1
		notifyDrop(self, channel)
		return false
	end
	if #channel.queue >= channel.capacity then
		if channel.dropOldest then
			table.remove(channel.queue, 1)
			channel.dropped += 1
			notifyDrop(self, channel)
		else
			channel.dropped += 1
			notifyDrop(self, channel)
			return false
		end
	end
	table.insert(channel.queue, args)
	return true
end

function Net.new(options: Options?): Dispatcher
	local opts: Options = options or {}
	local self = setmetatable({
		_channels = {},
		_order = {},
		_onError = opts.onError,
		_onDrop = opts.onDrop,
	}, Net)
	return (self :: any) :: Dispatcher
end

-- Declare a channel. `rate` nil or <= 0 means UNLIMITED: sends go straight out,
-- no limiter, no queueing.
function Net.addChannel(self: Dispatcher, name: string, sender: Sender, options: ChannelOptions?): Channel
	local opts: ChannelOptions = options or {}
	local rate = opts.rate
	local limiter: LimiterLike? = nil
	if rate ~= nil and rate > 0 then
		limiter = RateLimiter.new(rate, opts.burst, { minPenalty = 0.1 })
	end
	local channel: Channel = {
		name = name,
		sender = sender,
		limiter = limiter,
		queue = {},
		capacity = math.max(0, math.floor(opts.queue or 0)),
		dropOldest = opts.dropOldest == true,
		dropped = 0,
		sent = 0,
	}
	if self._channels[name] == nil then
		table.insert(self._order, name)
	end
	self._channels[name] = channel
	return channel
end

-- Send the same payload up to `count` times, stopping at the first refusal.
-- This is the training path: a refused burst is NOT counted as drops -- nothing
-- was lost, the remainder is simply not due yet.
function Net.burst(self: Dispatcher, name: string, now: number, count: number, ...: any): number
	local channel = self._channels[name]
	if channel == nil then
		report(self, name, "unknown channel")
		return 0
	end
	if count <= 0 then
		return 0
	end
	local args = table.pack(...)
	local delivered = 0
	for _ = 1, count do
		local sent = trySend(self, channel, now, args)
		if not sent then
			break
		end
		delivered += 1
	end
	return delivered
end

function Net.channel(self: Dispatcher, name: string): Channel?
	return self._channels[name]
end

-- Send now if allowed; otherwise queue it (bounded) or drop it.
function Net.send(self: Dispatcher, name: string, now: number, ...: any): boolean
	local channel = self._channels[name]
	if channel == nil then
		report(self, name, "unknown channel")
		return false
	end
	local args = table.pack(...)
	local sent, denied = trySend(self, channel, now, args)
	if sent then
		return true
	end
	if not denied then
		return false
	end
	return queueOrDrop(self, channel, args)
end

-- Queue unconditionally (bounded). Used for events that must not be lost while
-- still never being allowed to build an unbounded backlog.
function Net.enqueue(self: Dispatcher, name: string, ...: any): boolean
	local channel = self._channels[name]
	if channel == nil then
		report(self, name, "unknown channel")
		return false
	end
	return queueOrDrop(self, channel, table.pack(...))
end

-- Drain queued payloads, respecting each channel's limiter. Call once per frame.
function Net.flush(self: Dispatcher, now: number): number
	local sent = 0
	for _, name in ipairs(self._order) do
		local channel = self._channels[name]
		if channel ~= nil then
			while #channel.queue > 0 do
				local args = channel.queue[1]
				local ok, denied = trySend(self, channel, now, args)
				if ok then
					table.remove(channel.queue, 1)
					sent += 1
				else
					if not denied then
						-- The head cannot be delivered at all; drop it rather than
						-- blocking everything queued behind it forever.
						table.remove(channel.queue, 1)
						channel.dropped += 1
						notifyDrop(self, channel)
					end
					break
				end
			end
		end
	end
	return sent
end

function Net.reportFailure(self: Dispatcher, name: string, now: number)
	local channel = self._channels[name]
	if channel == nil then
		return
	end
	local limiter = channel.limiter
	if limiter ~= nil then
		limiter:reportFailure(now)
	end
end

function Net.reportSuccess(self: Dispatcher, name: string, now: number)
	local channel = self._channels[name]
	if channel == nil then
		return
	end
	local limiter = channel.limiter
	if limiter ~= nil then
		limiter:reportSuccess(now)
	end
end

function Net.stats(self: Dispatcher, now: number): Stats
	local out: Stats = {}
	for name, channel in pairs(self._channels) do
		local denied = 0
		local penalty = 1
		local limiter = channel.limiter
		if limiter ~= nil then
			local limiterStats = limiter:stats(now)
			denied = limiterStats.denied
			penalty = limiterStats.penalty
		end
		out[name] = {
			sent = channel.sent,
			dropped = channel.dropped,
			queued = #channel.queue,
			denied = denied,
			penalty = penalty,
		}
	end
	return out
end

function Net.pending(self: Dispatcher): number
	local n = 0
	for _, channel in pairs(self._channels) do
		n += #channel.queue
	end
	return n
end

function Net.reset(self: Dispatcher, now: number)
	for _, channel in pairs(self._channels) do
		table.clear(channel.queue)
		channel.dropped = 0
		channel.sent = 0
		local limiter = channel.limiter
		if limiter ~= nil then
			limiter:reset(now)
		end
	end
end

return Net
end

__modules["core/TrainRate"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	TrainRate -- how many training packets to attempt this frame. Pure.

	  * "fast" fires at the configured rate (capped), "auto" at a fixed trickle;
	  * fractional progress accumulates across frames, so a low frame rate does
	    not silently halve the throughput;
	  * the accumulator is capped, so a long stall cannot bank a huge burst;
	  * only a limited number go out per frame and the remainder is KEPT, so the
	    average rate is unchanged while a single frame cannot dump everything;
	  * whatever the network layer refuses is handed back instead of being lost.
]]

local TrainRate = {}

export type Settings = {
	auto: boolean,
	fast: boolean,
	rate: number,
}

export type State = {
	tokens: number,
}

TrainRate.AUTO_RATE = 10
TrainRate.FAST_CAP = 2000
TrainRate.CEILING = 400
TrainRate.PER_FRAME = 40

function TrainRate.newState(): State
	return { tokens = 0 }
end

-- The target rate in packets per second, or 0 when training is off.
-- Two modes only: "fast" at the configured rate (capped), "auto" at a fixed
-- trickle. `_fps` is ignored on purpose -- the frame-rate scaler is gone.
function TrainRate.compute(settings: Settings, _fps: number): number
	local base = 0
	if settings.fast then
		base = math.min(settings.rate, TrainRate.FAST_CAP)
	elseif settings.auto then
		base = TrainRate.AUTO_RATE
	end
	if base <= 0 then
		return 0
	end
	return base
end

-- Advance the accumulator and return how many packets to ATTEMPT this frame.
-- The caller must report back what was not actually delivered via `refund`.
function TrainRate.step(state: State, rate: number, dt: number, perFrameCap: number?, ceiling: number?): number
	if rate <= 0 or dt <= 0 then
		return 0
	end
	local limit = ceiling or TrainRate.CEILING
	local cap = perFrameCap or TrainRate.PER_FRAME

	local tokens = math.min(state.tokens + rate * dt, limit)
	local count = math.floor(tokens)
	if count <= 0 then
		state.tokens = tokens
		return 0
	end

	tokens -= count
	if count > cap then
		tokens = math.min(limit, tokens + (count - cap))
		count = cap
	end
	state.tokens = tokens
	return count
end

-- Hand back attempts that never went out, so the average rate is preserved
-- without ever letting the accumulator exceed its ceiling.
function TrainRate.refund(state: State, count: number, ceiling: number?): ()
	if count <= 0 then
		return
	end
	state.tokens = math.min(ceiling or TrainRate.CEILING, state.tokens + count)
end

return TrainRate
end

__modules["core/Hold"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Hold -- the "keep the character where I put it" state machine. Pure. The other
	half, writing CFrames, stays in src/game.

	  * a hold is either PERSISTENT (combat/boss: kept as long as the feature is
	    on) or VERIFIED (a teleport or chest: released the moment the arrival
	    window ends). Releasing is what gives control back -- holding forever
	    left the player unable to move after teleporting.
	  * while verifying, the distance to the target is sampled at a fixed rate and
	    must exceed the threshold for several CONSECUTIVE samples before it counts
	    as a pullback. A single odd frame, or a target that is itself moving, must
	    not start a retry storm.
	  * pullbacks are retried up to a limit, after which the caller is told to
	    give up.

	Two deliberate deviations from V1007: `start` always resets the counters
	(otherwise a teleport issued while a hold was live inherited the previous
	retry count and gave up early), and `giveup` fires once (V1007 kept sampling
	and fired the give-up callback every ten samples, forever).
]]

local Hold = {}
Hold.__index = Hold

export type Options = {
	verifySeconds: number?,
	retries: number?,
	driftThreshold: number?,
	driftSamples: number?,
	sampleInterval: number?,
}

export type Outcome = "ok" | "lost" | "retry" | "giveup" | "skipped"

export type Stats = {
	pulled: number,
	retries: number,
	failures: number,
}

export type Hold = {
	_active: boolean,
	_persistent: boolean,
	_exhausted: boolean,
	_verifyUntil: number,
	_lastSample: number,
	_lostStreak: number,
	_attempts: number,
	_verifySeconds: number,
	_maxRetries: number,
	_driftThreshold: number,
	_driftSamples: number,
	_sampleInterval: number,
	stats: Stats,
	configure: (Hold, Options) -> (),
	start: (Hold, number, boolean) -> (),
	isActive: (Hold) -> boolean,
	isPersistent: (Hold) -> boolean,
	sampleDue: (Hold, number) -> boolean,
	sample: (Hold, number, number) -> Outcome,
	shouldHold: (Hold, number) -> boolean,
	attempts: (Hold) -> number,
	finish: (Hold) -> (),
}

Hold.DEFAULT_VERIFY_SECONDS = 6
Hold.DEFAULT_RETRIES = 3
Hold.DEFAULT_DRIFT_THRESHOLD = 30
Hold.DEFAULT_DRIFT_SAMPLES = 10
Hold.DEFAULT_SAMPLE_INTERVAL = 0.1

-- Modes that keep holding for as long as the feature is switched on; everything
-- else is a one-shot "put me here" that must release control after verification.
--
-- NOTE: the annotation has to live on a local -- `Hold.X: T = {...}` is not valid
-- Luau, a type annotation is only allowed on a declaration.
local PERSISTENT_MODES: { [string]: boolean } = {
	combat = true,
	boss = true,
}

Hold.PERSISTENT_MODES = PERSISTENT_MODES

function Hold.isPersistentMode(mode: string?): boolean
	return mode ~= nil and PERSISTENT_MODES[mode] == true
end

function Hold.new(options: Options?): Hold
	local opts: Options = options or {}
	local self = setmetatable({
		_active = false,
		_persistent = false,
		_exhausted = false,
		_verifyUntil = 0,
		_lastSample = 0,
		_lostStreak = 0,
		_attempts = 0,
		_verifySeconds = opts.verifySeconds or Hold.DEFAULT_VERIFY_SECONDS,
		_maxRetries = opts.retries or Hold.DEFAULT_RETRIES,
		_driftThreshold = opts.driftThreshold or Hold.DEFAULT_DRIFT_THRESHOLD,
		_driftSamples = opts.driftSamples or Hold.DEFAULT_DRIFT_SAMPLES,
		_sampleInterval = opts.sampleInterval or Hold.DEFAULT_SAMPLE_INTERVAL,
		stats = { pulled = 0, retries = 0, failures = 0 },
	}, Hold)
	return (self :: any) :: Hold
end

-- Update the tuning numbers without disturbing the counters or an in-flight
-- hold. Motion re-reads the config on every begin(), because the user can change
-- the retry limit while a teleport is in progress.
function Hold.configure(self: Hold, options: Options)
	local opts: Options = options or {}
	self._verifySeconds = opts.verifySeconds or self._verifySeconds
	self._maxRetries = opts.retries or self._maxRetries
	self._driftThreshold = opts.driftThreshold or self._driftThreshold
	self._driftSamples = opts.driftSamples or self._driftSamples
	self._sampleInterval = opts.sampleInterval or self._sampleInterval
end

function Hold.start(self: Hold, now: number, persistent: boolean)
	self._active = true
	self._persistent = persistent
	self._exhausted = false
	self._verifyUntil = now + self._verifySeconds
	-- Due immediately: the first distance measurement after a hold begins should
	-- not wait a whole sample interval. V1007 got this for free because it
	-- compared against os.clock() (machine uptime, never near zero); anchoring it
	-- to `now` makes the behaviour explicit and testable.
	self._lastSample = now - self._sampleInterval
	self._lostStreak = 0
	self._attempts = 0
end

function Hold.isActive(self: Hold): boolean
	return self._active
end

function Hold.isPersistent(self: Hold): boolean
	return self._persistent
end

function Hold.attempts(self: Hold): number
	return self._attempts
end

-- A verified hold stops caring once the window closes; a persistent one does
-- not. This is the single condition that decides whether the player gets to
-- move again.
function Hold.shouldHold(self: Hold, now: number): boolean
	if not self._active then
		return false
	end
	if self._persistent then
		return true
	end
	return now <= self._verifyUntil
end

-- Tolerance for the sample-interval comparison. Without it the sampler misses
-- beats: 0.3 - 0.2 evaluates to 0.09999999999999998 in IEEE754, so a plain
-- `>= 0.1` there reports "not due yet" and the sample is skipped.
Hold.SAMPLE_EPSILON = 1e-9

-- Is a distance measurement worth taking this frame? Kept separate so the
-- caller only reads the character's position when it will be used.
function Hold.sampleDue(self: Hold, now: number): boolean
	if not self._active or self._exhausted then
		return false
	end
	if now > self._verifyUntil then
		return false
	end
	return now - self._lastSample >= self._sampleInterval - Hold.SAMPLE_EPSILON
end

-- Feed one distance measurement in.
--
--   "ok"      -- within tolerance, the streak is cleared
--   "lost"    -- over tolerance, but not yet enough consecutive samples
--   "retry"   -- the caller should re-apply the position
--   "giveup"  -- the caller should fall back; fires at most once per hold
--   "skipped" -- not due, already exhausted, or past the verification window
function Hold.sample(self: Hold, now: number, distance: number): Outcome
	if not Hold.sampleDue(self, now) then
		return "skipped"
	end
	self._lastSample = now

	if distance <= self._driftThreshold then
		self._lostStreak = 0
		return "ok"
	end

	self._lostStreak += 1
	if self._lostStreak < self._driftSamples then
		return "lost"
	end

	self._lostStreak = 0
	self._attempts += 1
	self.stats.pulled += 1

	if self._attempts <= self._maxRetries then
		self.stats.retries += 1
		return "retry"
	end

	self._exhausted = true
	self.stats.failures += 1
	return "giveup"
end

function Hold.finish(self: Hold)
	self._active = false
	self._persistent = false
	self._exhausted = false
	self._lostStreak = 0
	self._attempts = 0
	self._verifyUntil = 0
end

return Hold
end

__modules["core/Keyword"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Keyword -- fuzzy name matching for game objects. Pure.

	The search is PLAIN (`string.find(..., true)`), so keywords containing Lua
	pattern characters ("push-up", "hand-stand") match literally; both sides are
	lowercased, so "Punch" still matches "PunchTool".
]]

local Keyword = {}

function Keyword.matches(name: string?, keywords: { string }): boolean
	if name == nil or name == "" then
		return false
	end
	local lowered = string.lower(name)
	for _, keyword in ipairs(keywords) do
		if keyword ~= "" and string.find(lowered, string.lower(keyword), 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- Index of the first keyword group that matches, or nil. Used where several
-- groups are tried in priority order (preferred training tools).
function Keyword.groupIndex(name: string?, groups: { { string } }): number?
	if name == nil then
		return nil
	end
	for index, group in ipairs(groups) do
		if Keyword.matches(name, group) then
			return index
		end
	end
	return nil
end

return Keyword
end

__modules["core/Targeting"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Targeting -- choosing who to attack. Pure.

	The old "single target kill does nothing" chain came from one shared number:
	the free-scan range was also applied to a hand-picked target. Pick someone
	slightly too far away and the selection silently returned nothing, every
	frame, forever.

	So the rules are explicit here, and the two modes are genuinely different:

	    LOCKED   the user named a target. Distance is irrelevant -- they asked for
	             that one. Only self / dead / (optionally) friend can veto it.
	    FREE     nobody named. The nearest eligible candidate inside `range` wins.

	Rather than returning nil on failure, select() returns a REASON, because "why
	did nothing happen" was previously unanswerable without reading the source.
]]

local Targeting = {}

export type Vec3 = { x: number, y: number, z: number }

export type Candidate = {
	id: string,
	position: Vec3,
	alive: boolean,
	friend: boolean,
	self: boolean,
	--[[
		In an area where damage does not apply (the seasonal gym, the island),
		where the player cannot be killed (如果目标玩家在万圣节健身房，或者在小岛，
		那么就直接跳过). Never chosen by the FREE scan -- but it does not veto a
		LOCKED target, because naming someone explicitly is a different statement
		from "kill whoever is reachable".
	]]
	protected: boolean?,
	--[[
		Would we actually win the fight? Computed by the caller from both sides'
		strength and durability (see core/Duel) because only the adapter can read
		those numbers. `false` means "cannot win", `nil` means "not judged"
		(missing data), and only the FREE scan skips it -- a hand-picked target is
		still attacked, which is what "单独击杀" means.
	]]
	winnable: boolean?,
	--[[
		We have already spent `kill.targetTimeout` seconds on this player without
		killing them (see core/TargetLock), so they are out of the pool until the
		skip expires. Without this the timeout alone changes nothing: the next
		scan picks the same nearest player again and the loop rotates between two
		candidates forever.
	]]
	skipped: boolean?,
}

export type Rules = {
	range: number,
	respectFriends: boolean,
	lockedId: string?,
}

export type Decision = {
	id: string?,
	reason: string,
}

function Targeting.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function findById(candidates: { Candidate }, id: string): Candidate?
	for _, candidate in ipairs(candidates) do
		if candidate.id == id then
			return candidate
		end
	end
	return nil
end

--[[
	Choose a target.

	Reasons returned:
	    "locked"            -- the named target is valid
	    "locked-missing"    -- the named target is not present any more
	    "locked-dead"       -- present but not alive
	    "locked-self"       -- the named target is the local player
	    "locked-friend"     -- the named target is a friend and friends are protected
	    "nearest"           -- the closest eligible candidate in range
	    "no-candidates"     -- nobody was even visible
	    "only-self"         -- the local player was the only candidate
	    "all-dead"          -- every candidate was dead
	    "all-friends"       -- every live candidate is a friend
	    "all-protected"     -- everyone left is in a no-damage area (gym / island / arena)
	    "all-unwinnable"    -- everyone left would win the fight (core/Duel)
	    "all-skipped"       -- everyone left is on a timeout cooldown (core/TargetLock)
	    "all-out-of-range"  -- live, non-friend candidates exist but none is close enough
]]
function Targeting.select(candidates: { Candidate }, origin: Vec3, rules: Rules): Decision
	local lockedId = rules.lockedId
	if lockedId ~= nil then
		local candidate = findById(candidates, lockedId)
		if candidate == nil then
			return { id = nil, reason = "locked-missing" }
		end
		if candidate.self then
			return { id = nil, reason = "locked-self" }
		end
		if not candidate.alive then
			return { id = nil, reason = "locked-dead" }
		end
		if rules.respectFriends and candidate.friend then
			return { id = nil, reason = "locked-friend" }
		end
		-- Deliberately no range check, no safe-zone check and no power check: the
		-- user named this target, so the only vetoes are the ones about the
		-- target being attackable at all.
		return { id = candidate.id, reason = "locked" }
	end

	local total = #candidates
	if total == 0 then
		return { id = nil, reason = "no-candidates" }
	end

	local otherThanSelf = 0
	local aliveOthers = 0
	local eligible = 0
	local reachable = 0
	local bestId: string? = nil
	local bestDistance: number? = nil

	for _, candidate in ipairs(candidates) do
		if candidate.self then
			continue
		end
		otherThanSelf += 1
		if not candidate.alive then
			continue
		end
		aliveOthers += 1
		if rules.respectFriends and candidate.friend then
			continue
		end
		eligible += 1
		-- The two "not worth attacking" filters. Both are about the FREE scan
		-- only, and both are counted separately from `eligible` so the reason
		-- below can name the one that actually emptied the pool.
		if candidate.protected == true then
			continue
		end
		if candidate.winnable == false then
			continue
		end
		if candidate.skipped == true then
			continue
		end
		reachable += 1
		local distance = Targeting.distance(candidate.position, origin)
		if distance <= rules.range and (bestDistance == nil or distance < bestDistance) then
			bestDistance = distance
			bestId = candidate.id
		end
	end

	if bestId ~= nil then
		return { id = bestId, reason = "nearest" }
	end

	-- Nothing was chosen: report the first filter that emptied the pool, so the
	-- caller can say something more useful than "no target".
	if otherThanSelf == 0 then
		return { id = nil, reason = "only-self" }
	end
	if aliveOthers == 0 then
		return { id = nil, reason = "all-dead" }
	end
	if eligible == 0 then
		return { id = nil, reason = "all-friends" }
	end
	if reachable == 0 then
		-- Which of the three filters did it is worth distinguishing: "everyone is
		-- in the gym", "everyone out-punches me" and "everyone is on a timeout
		-- cooldown" are three different answers to "why is nothing being
		-- attacked".
		for _, candidate in ipairs(candidates) do
			if not candidate.self and candidate.alive and candidate.protected == true then
				return { id = nil, reason = "all-protected" }
			end
		end
		for _, candidate in ipairs(candidates) do
			if not candidate.self and candidate.alive and candidate.skipped == true then
				return { id = nil, reason = "all-skipped" }
			end
		end
		return { id = nil, reason = "all-unwinnable" }
	end
	return { id = nil, reason = "all-out-of-range" }
end

return Targeting
end

__modules["core/ChestTimer"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	ChestTimer -- "the boss just died, go and open the chest" timing. Pure.

	The rules (each was a separate early-return branch before):
	    a live boss keeps resetting the timer, so a new spawn cannot inherit the
	    previous death;
	    the death is timestamped exactly once, AND only if the boss was seen alive
	    first -- otherwise every idle frame before a spawn would open a window to
	    loot a chest that never existed;
	    the chest is approached only after `delay` seconds and only within
	    `window` seconds -- after that the attempt is abandoned, because an old
	    death position is a wild goose chase.

	observe() is a pure function of (alive, now) and returns what the caller
	should do, which is what makes the timing testable at all.
]]

local ChestTimer = {}
ChestTimer.__index = ChestTimer

export type Options = {
	delay: number?,
	window: number?,
}

export type Status = "idle" | "blocked" | "waiting" | "ready" | "expired"

export type ChestTimer = {
	_delay: number,
	_window: number,
	_wasAlive: boolean,
	_killedAt: number?,
	observe: (ChestTimer, boolean, number) -> Status,
	killedAt: (ChestTimer) -> number?,
	reset: (ChestTimer) -> (),
}

ChestTimer.DEFAULT_DELAY = 3
-- How long after a boss death the chest is still worth chasing.
--
-- 30 seconds is too short when the approach has to be retried (a walk that lands
-- in the void, a prompt somebody else is standing in) -- "有的时候会漏开宝箱" was
-- a window expiring while the character was still being put back in range. A
-- minute allows a retry and still does not chase an old death position forever.
ChestTimer.DEFAULT_WINDOW = 60

function ChestTimer.new(options: Options?): ChestTimer
	local opts: Options = options or {}
	local self = setmetatable({
		_delay = opts.delay or ChestTimer.DEFAULT_DELAY,
		_window = opts.window or ChestTimer.DEFAULT_WINDOW,
		_wasAlive = false,
		_killedAt = nil,
	}, ChestTimer)
	return (self :: any) :: ChestTimer
end

-- Re-read the delay from the config without losing an in-flight countdown.
function ChestTimer.configure(self: ChestTimer, options: Options)
	local opts: Options = options or {}
	self._delay = opts.delay or self._delay
	self._window = opts.window or self._window
end

function ChestTimer.killedAt(self: ChestTimer): number?
	return self._killedAt
end

--[[
	Feed in the current boss state.

	    "blocked" -- a boss is alive; nothing to collect
	    "waiting" -- recorded a death, or the delay has not elapsed yet
	    "ready"   -- approach and open the chest
	    "expired" -- the window passed; the attempt is dropped
	    "idle"    -- no boss has died since the last reset
]]
function ChestTimer.observe(self: ChestTimer, alive: boolean, now: number): Status
	if alive then
		self._wasAlive = true
		self._killedAt = nil
		return "blocked"
	end

	-- Timestamp the death exactly once, on the first frame the boss is gone.
	if self._wasAlive then
		self._wasAlive = false
		self._killedAt = now
	end

	local killedAt = self._killedAt
	if killedAt == nil then
		return "idle"
	end

	local since = now - killedAt
	if since > self._window then
		self._killedAt = nil
		return "expired"
	end
	if since < self._delay then
		return "waiting"
	end
	return "ready"
end

function ChestTimer.reset(self: ChestTimer)
	self._wasAlive = false
	self._killedAt = nil
end

return ChestTimer
end

__modules["core/SizePolicy"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	SizePolicy -- which self-resize to request, and when to ask for it. Pure.

	Three states (boss size / own size / back to normal) drive a REMOTE, so it is
	split into "what size is wanted" and "is that a change worth sending".
]]

local SizePolicy = {}

export type Inputs = {
	bossAlive: boolean,
	bossSizeEnabled: boolean,
	bossSizeMul: number,
	selfSizeEnabled: boolean,
	selfSizeMul: number,
}

-- The size the current state calls for, or nil when nothing is requested.
-- NOTE: during a boss fight the boss size wins, otherwise the user's own
-- multiplier applies (mutually exclusive, never additive).
function SizePolicy.wanted(inputs: Inputs): number?
	if inputs.bossAlive and inputs.bossSizeEnabled then
		return inputs.bossSizeMul
	end
	if inputs.selfSizeEnabled then
		return inputs.selfSizeMul
	end
	return nil
end

-- Turn "what is wanted" into "what to send", or nil when nothing should be sent.
-- `last` is the last value this function returned. Falling back to 1 is explicit
-- because forgetting it leaves the player permanently enlarged.
function SizePolicy.transition(last: number?, wanted: number?): number?
	if wanted ~= nil then
		if last ~= wanted then
			return wanted
		end
		return nil
	end
	if last ~= nil and last ~= 1 then
		return 1
	end
	return nil
end

return SizePolicy
end

__modules["core/RepBonus"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	RepBonus -- the "rep speed" arithmetic. Pure.

	Not a multiplier bonus: the summed repTimeBoostPercent values are SUBTRACTED
	FROM THE COOLDOWN, so 100% total means zero cooldown and unbounded speed.

	    total = sum(pet perks) + 5% per ultimate level
	    total >= 100  ->  no meaningful multiplier at all
	    otherwise     ->  1 / (1 - total/100), doubled by the x2 gamepass
]]

local RepBonus = {}

export type Inputs = {
	petPercent: number?,
	petCount: number?,
	equippedCount: number?,
	ultimateLevel: number?,
	ultimatePerLevel: number?,
	hasGamepass: boolean?,
}

export type Result = {
	total: number,
	petPercent: number,
	ultimatePercent: number,
	petCount: number,
	equippedCount: number,
	multiplier: number?,
	uncapped: boolean,
}

RepBonus.ULTIMATE_PER_LEVEL = 5
RepBonus.GAMEPASS_MULTIPLIER = 2
RepBonus.UNCAP_PERCENT = 100

function RepBonus.compute(inputs: Inputs): Result
	local petPercent = math.max(0, inputs.petPercent or 0)
	local perLevel = inputs.ultimatePerLevel or RepBonus.ULTIMATE_PER_LEVEL
	local ultimatePercent = math.max(0, (inputs.ultimateLevel or 0) * perLevel)
	local total = petPercent + ultimatePercent

	local result: Result = {
		total = total,
		petPercent = petPercent,
		ultimatePercent = ultimatePercent,
		petCount = inputs.petCount or 0,
		equippedCount = inputs.equippedCount or 0,
		-- nil means "no finite multiplier": the cooldown has reached zero.
		multiplier = nil,
		uncapped = false,
	}

	if total >= RepBonus.UNCAP_PERCENT then
		result.uncapped = true
		return result
	end

	local multiplier = 1 / (1 - total / RepBonus.UNCAP_PERCENT)
	if inputs.hasGamepass == true then
		multiplier *= RepBonus.GAMEPASS_MULTIPLIER
	end
	result.multiplier = multiplier
	return result
end

-- The label shown in the info window (unbounded shows as "无上限").
function RepBonus.describe(result: Result): string
	local multiplier = result.multiplier
	if result.uncapped or multiplier == nil then
		return "无上限"
	end
	return string.format("%.2fx", multiplier)
end

return RepBonus
end

__modules["core/PetPlan"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	PetPlan -- turning a saved preset into a sequence of equip actions. Pure.

	Two consequences of doing this inline (as V1007 did, with a task.wait(0.1)
	between each remote call inside a task.spawn'd coroutine): the whole thing was
	uncancellable, and the case where the preset names pets you do not own was
	invisible. A preset entry asking for more copies than are owned is clamped
	rather than dropped; when EVERY entry is missing the plan reports `unusable`,
	because unequipAllPets() has already run by then and switching to a preset you
	own none of would leave the player with NO pets -- training silently stopped.
]]

local PetPlan = {}

export type Entry = { name: string, count: number? }
export type Availability = { [string]: number }

export type Action = {
	kind: string,
	name: string,
	index: number,
}

export type Step = {
	kind: string,
	name: string?,
	index: number?,
}

export type Plan = {
	unequipFirst: boolean,
	actions: { Action },
	missing: { string },
	total: number,
	unusable: boolean,
}

local function clampCount(value: number?): number
	local count = tonumber(value) or 1
	count = math.floor(count)
	if count < 1 then
		return 1
	end
	return count
end

-- Build the plan for a preset.
-- `availability` maps a pet name to how many copies the player owns.
function PetPlan.build(preset: { Entry }?, availability: Availability?): Plan
	local owned = availability or {}
	local actions: { Action } = {}
	local missing: { string } = {}
	local entries = 0

	if preset ~= nil then
		entries = #preset
		for _, entry in ipairs(preset) do
			local want = clampCount(entry.count)
			local have = math.max(0, math.floor(owned[entry.name] or 0))
			if have <= 0 then
				table.insert(missing, entry.name)
			else
				for index = 1, math.min(want, have) do
					table.insert(actions, { kind = "equip", name = entry.name, index = index })
				end
			end
		end
	end

	return {
		-- Slots have to be freed before anything can be equipped, so a non-empty
		-- preset always begins by unequipping everything.
		unequipFirst = entries > 0,
		actions = actions,
		missing = missing,
		total = #actions,
		-- Non-empty preset, nothing equippable: stripping the player's pets would
		-- leave them worse off than doing nothing.
		unusable = entries > 0 and #actions == 0,
	}
end

-- Flatten a plan into the steps to execute, one per tick. The unequip is a step
-- like any other, so the caller has one code path and the pacing is uniform.
function PetPlan.steps(plan: Plan): { Step }
	local steps: { Step } = {}
	if plan.unequipFirst then
		table.insert(steps, { kind = "unequip" })
	end
	for _, action in ipairs(plan.actions) do
		table.insert(steps, { kind = "equip", name = action.name, index = action.index })
	end
	return steps
end

-- "Equip the first N pets I own", for farming mode. `names` is the flattened
-- list of owned pet instance names in discovery order.
function PetPlan.farming(names: { string }?, max: number?): Plan
	local limit = math.max(0, math.floor(tonumber(max) or 12))
	local actions: { Action } = {}
	if names ~= nil then
		for index, name in ipairs(names) do
			if #actions >= limit then
				break
			end
			table.insert(actions, { kind = "equip", name = name, index = index })
		end
	end
	return {
		unequipFirst = true,
		actions = actions,
		missing = {},
		total = #actions,
		unusable = #actions == 0,
	}
end

return PetPlan
end

__modules["core/MachinePlan"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	MachinePlan -- choosing which gym machine to use. Pure.

	Ported from Core.resolveMachineTarget and friends. The rules are small but
	they are the whole feature: filter to a gym, filter to a machine name, drop
	the seats somebody is already sitting in, sort, then pick either the Nth or a
	random one.

	Two things the original had that are worth naming:

	  * the sort key is (name, folder index), NOT folder order. So "第 3 台" means
	    the third machine of that name in sorted order, which is stable across
	    sessions even if the folder order is not.
	  * an out-of-range index falls back to the LAST candidate rather than to
	    nothing, so asking for "第 9 台" of 4 machines still gets you a machine
	    instead of silently doing nothing.

	`random` is a parameter, not math.random, so the choice is testable.
]]

local MachinePlan = {}

export type Vec3 = { x: number, y: number, z: number }

export type Seat = {
	id: string,
	name: string,
	gym: string,
	index: number,
	occupied: boolean,
}

export type Rules = {
	gym: string?,
	name: string?,
	index: number?,
}

export type Random = (upper: number) -> number

-- Gym positions, confirmed against the game. Kept as data so the nearest-gym
-- classification can be tested without a place to run in.
local GYMS: { { name: string, x: number, y: number, z: number } } = {
	{ name = "冰霜健身房", x = -2623.41, y = 6.99, z = -409.34 },
	{ name = "神话健身房", x = 2250.39, y = 6.99, z = 1072.77 },
	{ name = "永恒健身房", x = -6758.39, y = 6.99, z = -1284.45 },
	{ name = "传奇健身房", x = 4603.40, y = 990.99, z = -3897.44 },
	{ name = "肌肉之王健身房", x = -8625.40, y = 16.99, z = -5730.41 },
	{ name = "丛林健身房", x = -8685.01, y = 5.99, z = 2392.06 },
	{ name = "工业健身房", x = -5496.68, y = 59.04, z = 4927.74 },
	{ name = "超载健身房", x = -3045.30, y = 165.41, z = 4990.69 },
	-- The seasonal gym (2026-10: "Hallowed Gym"), probed in game. Its machines
	-- are named "Hallowed Bench / Squat / Boulder / Bar Lift / Pullup /
	-- Treadmill / Rock", and without this entry every one of them classified as
	-- the nearest OLD gym and showed the wrong Chinese label.
	{ name = "万圣节健身房", x = 5505.53, y = 96.32, z = 5893.50 },
	{ name = "海滩", x = -32.14, y = 8.51, z = 1904.41 },
}

local GYM_LABELS: { [string]: string } = {
	["冰霜健身房"] = "冰霜",
	["神话健身房"] = "神话",
	["永恒健身房"] = "永恒",
	["传奇健身房"] = "传奇",
	["肌肉之王健身房"] = "王·健身房",
	["丛林健身房"] = "丛林",
	["工业健身房"] = "工业",
	["超载健身房"] = "超载",
	["万圣节健身房"] = "万圣节",
	["海滩"] = "海滩",
	["未知"] = "未知",
}

--[[
	Display names for machines.

	The NAME LIST comes from a live scan of `Workspace.machinesFolder` (see
	game/Machine.luau) and this build of the game names them per gym, e.g.
	"Frost Squat", "Industrial Bench", "Legends Throw", "Overcharged Bar Lift",
	"Muscle King Bench", "Jungle Boulder". A dump of the real game shows 40+
	distinct names, and the original five-entry table left almost every one of
	them rendering in English while the rest of the interface was Chinese.

	Composed per (gym prefix, machine type) rather than listed one by one: the set
	grows as new gyms are added, and a lookup that silently falls back to English
	would go stale again on the next update.
]]
local MACHINE_LABELS: { [string]: string } = {
	["Squat Rack"] = "深蹲架",
	["Bench Press"] = "卧推台",
	["Deadlift"] = "硬拉台",
	["Pullups"] = "引体向上",
	["Boulder Throw"] = "巨石投掷",
	["Treadmill"] = "跑步机",
	-- The durability "rocks" are named individually rather than per gym.
	["Tiny Rock"] = "小岩石",
	["Punching Rock"] = "拳击岩",
	["Frozen Rock"] = "冰封岩",
	["Inferno Rock"] = "炼狱岩",
	["Rock Of Legends"] = "传奇之岩",
	["Muscle King Mountain"] = "肌肉之王山",
	["Ancient Jungle Rock"] = "远古丛林岩",
	["Industrial Rock"] = "工业岩",
	["Overcharged Rock"] = "超载岩",
}

-- The gym prefix each machine family is named after, and its Chinese form.
type Prefix = { en: string, cn: string }
type Suffix = { en: string, cn: string }

local GYM_PREFIXES: { Prefix } = {
	{ en = "Frost", cn = "冰霜" },
	{ en = "Mythical", cn = "神话" },
	{ en = "Eternal", cn = "永恒" },
	{ en = "Legends", cn = "传奇" },
	{ en = "Jungle", cn = "丛林" },
	{ en = "Industrial", cn = "工业" },
	{ en = "Overcharged", cn = "超载" },
	{ en = "Muscle King", cn = "肌肉之王" },
	-- The seasonal gym's family: "Hallowed Bench" -> 万圣节卧推, `Hallowed Rock`
	-- -> 万圣节岩石.
	{ en = "Hallowed", cn = "万圣节" },
}

-- The trailing machine word, longest first so "Bar Lift" wins over "Lift".
local MACHINE_SUFFIXES: { Suffix } = {
	{ en = "Bar Lift", cn = "硬拉" },
	{ en = "Boulder", cn = "巨石" },
	{ en = "Bench", cn = "卧推" },
	{ en = "Squat", cn = "深蹲" },
	{ en = "Press", cn = "卧推" },
	{ en = "Pullup", cn = "引体向上" },
	{ en = "Lift", cn = "硬拉" },
	{ en = "Throw", cn = "投掷" },
	{ en = "Treadmill", cn = "跑步机" },
	{ en = "Rock", cn = "岩石" },
}

MachinePlan.UNKNOWN_GYM = "未知"

function MachinePlan.gyms(): { { name: string, x: number, y: number, z: number } }
	return GYMS
end

-- The nearest gym to a position, or "未知" when there is nothing to compare to.
function MachinePlan.gymOf(position: Vec3?, gyms: { { name: string, x: number, y: number, z: number } }?): string
	if position == nil then
		return MachinePlan.UNKNOWN_GYM
	end
	local list = gyms or GYMS
	local best = MachinePlan.UNKNOWN_GYM
	local bestDistance = math.huge
	for _, gym in ipairs(list) do
		local dx, dy, dz = position.x - gym.x, position.y - gym.y, position.z - gym.z
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance < bestDistance then
			bestDistance = distance
			best = gym.name
		end
	end
	return best
end

function MachinePlan.gymLabel(gym: string?): string
	if gym == nil then
		return GYM_LABELS[MachinePlan.UNKNOWN_GYM]
	end
	return GYM_LABELS[gym] or gym
end

--[[
	A display name for a machine.

	Exact names first (the five canonical ones), then "gym prefix + machine word"
	for the per-gym families, and finally the raw name so an unknown machine is
	shown rather than swallowed.
]]
function MachinePlan.machineLabel(name: string?): string
	if name == nil or name == "" then
		return ""
	end
	local exact = MACHINE_LABELS[name]
	if exact ~= nil then
		return exact
	end

	-- "Frost Squat" -> 冰霜深蹲, "Muscle King Bench" -> 肌肉之王卧推
	for _, prefix in ipairs(GYM_PREFIXES) do
		if string.sub(name, 1, #prefix.en) == prefix.en then
			local rest = string.sub(name, #prefix.en + 2)
			for _, suffix in ipairs(MACHINE_SUFFIXES) do
				if rest == suffix.en then
					return prefix.cn .. suffix.cn
				end
			end
		end
	end

	return name
end

function MachinePlan.byGym(seats: { Seat }, gym: string?): { Seat }
	local out: { Seat } = {}
	if gym == nil or gym == "" then
		for _, seat in ipairs(seats) do
			table.insert(out, seat)
		end
		return out
	end
	for _, seat in ipairs(seats) do
		if seat.gym == gym then
			table.insert(out, seat)
		end
	end
	return out
end

-- Unique machine names, sorted.
function MachinePlan.names(seats: { Seat }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, seat in ipairs(seats) do
		if seen[seat.name] ~= true then
			seen[seat.name] = true
			table.insert(out, seat.name)
		end
	end
	table.sort(out)
	return out
end

function MachinePlan.count(seats: { Seat }, name: string?): number
	local total = 0
	for _, seat in ipairs(seats) do
		if name == nil or name == "" or seat.name == name then
			total += 1
		end
	end
	return total
end

--[[
	Pick a seat.

	Returns nil when nothing matches. Otherwise the candidate list is sorted by
	(name, index) and the requested slot is taken from it:

	    index > 0 and in range  -> that slot
	    index > 0 and too large -> the last slot
	    index == 0              -> a random slot (via the injected generator)
]]
function MachinePlan.resolve(seats: { Seat }, rules: Rules, random: Random?): Seat?
	local gymFilter = rules.gym
	local nameFilter = rules.name
	local wanted = math.floor(rules.index or 0)

	local candidates: { Seat } = {}
	for _, seat in ipairs(seats) do
		local gymOk = gymFilter == nil or gymFilter == "" or seat.gym == gymFilter
		local nameOk = nameFilter == nil or nameFilter == "" or seat.name == nameFilter
		if gymOk and nameOk and not seat.occupied then
			table.insert(candidates, seat)
		end
	end
	if #candidates == 0 then
		return nil
	end

	table.sort(candidates, function(a: Seat, b: Seat): boolean
		if a.name == b.name then
			return a.index < b.index
		end
		return a.name < b.name
	end)

	if wanted > 0 then
		if wanted <= #candidates then
			return candidates[wanted]
		end
		return candidates[#candidates]
	end

	local pick = random or math.random
	local slot = math.floor(pick(#candidates))
	if slot < 1 then
		slot = 1
	elseif slot > #candidates then
		slot = #candidates
	end
	return candidates[slot]
end

return MachinePlan
end

__modules["core/MountState"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	MountState -- the sit-on-a-machine state machine. Pure.

	    idle --(0.8s of hovering)--> approaching --> mounting --(seated)--> mounted
	                                       ^                       |
	                                       +---- 3s timeout -------+

	Everything is gated by a 0.35s retry interval, which means the whole sequence
	takes a bit over a second, not the 0.8s the constant suggests. That is the
	actual observed pacing and is preserved deliberately.

	The caller performs the side effects; this returns what to do:

	    "aim"     -- anchor the player above the seat
	    "sit"     -- fire the interact remote and try to sit
	    "release" -- unanchor and stand up
	    "none"    -- nothing this tick
]]

local MountState = {}
MountState.__index = MountState

export type Options = {
	holdSeconds: number?,
	timeout: number?,
	retryInterval: number?,
}

export type Input = {
	enabled: boolean,
	blocked: boolean,
	training: boolean,
	hasCharacter: boolean,
	targetValid: boolean,
	seated: boolean,
}

export type Step = {
	phase: string,
	action: string,
	timedOut: boolean,
}

export type MountState = {
	phase: string,
	holdStart: number,
	mountStart: number,
	lastTry: number?,
	_holdSeconds: number,
	_timeout: number,
	_retryInterval: number,
	step: (MountState, Input, number) -> Step,
	reset: (MountState) -> (),
}

MountState.DEFAULT_HOLD = 0.8
MountState.DEFAULT_TIMEOUT = 3
MountState.DEFAULT_RETRY = 0.35

-- Tolerance for the interval comparisons: 0.9 - 0.8 evaluates to
-- 0.09999999999999998 in IEEE754, so a plain `>= 0.1` reports "too soon" and the
-- action is skipped for a tick. The same makes a hover of 0.8 measure short.
MountState.EPSILON = 1e-9

MountState.IDLE = "idle"
MountState.APPROACHING = "approaching"
MountState.MOUNTING = "mounting"
MountState.MOUNTED = "mounted"

function MountState.new(options: Options?): MountState
	local opts: Options = options or {}
	local self = setmetatable({
		phase = MountState.IDLE,
		holdStart = 0,
		mountStart = 0,
		-- nil means "never tried". Starting at 0 would throttle the very first
		-- attempt whenever `now` is small; V1007 got away with it only because it
		-- compared against os.clock(), which is machine uptime.
		lastTry = nil,
		_holdSeconds = opts.holdSeconds or MountState.DEFAULT_HOLD,
		_timeout = opts.timeout or MountState.DEFAULT_TIMEOUT,
		_retryInterval = opts.retryInterval or MountState.DEFAULT_RETRY,
	}, MountState)
	return (self :: any) :: MountState
end

function MountState.reset(self: MountState)
	self.phase = MountState.IDLE
	self.holdStart = 0
	self.mountStart = 0
	self.lastTry = nil
end

--[[
	Disengage: the feature was switched off, or combat took over. A "release" is
	only needed if we were actually attached or attaching; the caller unanchors in
	the other cases anyway.
]]
local function disengage(self: MountState): Step
	local wasEngaged = self.phase == MountState.MOUNTING or self.phase == MountState.MOUNTED
	MountState.reset(self)
	return {
		phase = MountState.IDLE,
		action = if wasEngaged then "release" else "none",
		timedOut = false,
	}
end

function MountState.step(self: MountState, input: Input, now: number): Step
	if not input.enabled or input.blocked then
		if self.phase == MountState.IDLE then
			return { phase = MountState.IDLE, action = "none", timedOut = false }
		end
		return disengage(self)
	end

	-- Nothing to sit on yet, or no character to sit with: hold the phase.
	if not input.training or not input.hasCharacter then
		return { phase = self.phase, action = "none", timedOut = false }
	end

	-- Already seated (by us or by the game): accept it, whatever the phase was.
	if input.seated and input.targetValid then
		self.phase = MountState.MOUNTED
		self.mountStart = 0
		return { phase = MountState.MOUNTED, action = "none", timedOut = false }
	end

	-- We believed we were mounted, but we are not any more: we fell off.
	if self.phase == MountState.MOUNTED then
		self.phase = MountState.IDLE
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = false }
	end

	-- The sit attempt is not converging. Give up on this seat entirely, so the
	-- caller resolves a different one instead of retrying forever.
	if self.phase == MountState.MOUNTING and now - self.mountStart > self._timeout then
		self.phase = MountState.IDLE
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = true }
	end

	-- The seat is gone or was taken by somebody else.
	if not input.targetValid then
		self.phase = MountState.IDLE
		self.holdStart = 0
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = false }
	end

	-- Everything below is rate limited: one action per retry interval.
	local lastTry = self.lastTry
	if lastTry ~= nil and now - lastTry < self._retryInterval - MountState.EPSILON then
		return { phase = self.phase, action = "none", timedOut = false }
	end
	self.lastTry = now

	if self.phase == MountState.IDLE or self.phase == MountState.APPROACHING then
		if self.phase == MountState.IDLE then
			self.phase = MountState.APPROACHING
			self.holdStart = now
		end
		if now - self.holdStart < self._holdSeconds - MountState.EPSILON then
			return { phase = MountState.APPROACHING, action = "aim", timedOut = false }
		end
		-- The hold is long enough; switch to mounting. The actual sit happens on
		-- the NEXT tick, which is what the original did.
		self.phase = MountState.MOUNTING
		self.mountStart = now
		return { phase = MountState.MOUNTING, action = "none", timedOut = false }
	end

	if self.phase == MountState.MOUNTING then
		return { phase = MountState.MOUNTING, action = "sit", timedOut = false }
	end

	return { phase = self.phase, action = "none", timedOut = false }
end

return MountState
end

__modules["core/RebirthState"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	RebirthState -- "ask to rebirth, then watch what happens". Pure.

	    idle ----(interval elapsed)----> request sent, pending
	    pending --(strength collapsed)--> succeeded, short cooldown, failures reset
	    pending --(no reaction in 5s)----> failed, backoff grows with the failures

	The failure path is the point: a request the server ignores is indistinguishable
	from one that never arrived, so the only safe response is to slow down rather
	than hammer -- the cooldown grows by one second per consecutive failure up to
	ten, and warns once at three.

	"Strength collapsed" is the success signal and the test is deliberately loose:
	strength <= 0.01, OR below 5% of what it was. A rebirth zeroes strength, but
	other things move it too, and a hard equality check would miss a reset that
	landed on a small non-zero value.
]]

local RebirthState = {}
RebirthState.__index = RebirthState

export type Options = {
	timeout: number?,
	successCooldown: number?,
	maxBackoff: number?,
	warnAt: number?,
	minInterval: number?,
}

export type Input = {
	strength: number,
	rebirths: number,
	target: number,
	rate: number,
}

export type Result = {
	action: string,
	outcome: string,
	fails: number,
	-- Named shouldWarn rather than warn: a local called `warn` shadows the global
	-- warn(), which the analyzer flags as LocalShadow (and which would quietly
	-- turn a debug warn() in this module into a nil call).
	shouldWarn: boolean,
}

export type RebirthState = {
	_pending: boolean,
	_fails: number,
	_cooldown: number,
	_lastAt: number?,
	_reqAt: number,
	_beforeStrength: number,
	_timeout: number,
	_successCooldown: number,
	_maxBackoff: number,
	_warnAt: number,
	_minInterval: number,
	step: (RebirthState, Input, number) -> Result,
	abort: (RebirthState) -> (),
	reset: (RebirthState) -> (),
	isPending: (RebirthState) -> boolean,
	failures: (RebirthState) -> number,
	cooldown: (RebirthState) -> number,
}

RebirthState.DEFAULT_TIMEOUT = 5
RebirthState.DEFAULT_SUCCESS_COOLDOWN = 1
RebirthState.DEFAULT_MAX_BACKOFF = 10
RebirthState.DEFAULT_WARN_AT = 3
RebirthState.DEFAULT_MIN_INTERVAL = 0.02

-- Tolerance for the interval comparison: `now - lastAt` on two nearby floats can
-- land a hair under the interval and skip a whole attempt.
RebirthState.EPSILON = 1e-9

-- The strength a "pack rebirth" aims for before it tries to rebirth.
RebirthState.PACK_BASE = 5000
RebirthState.PACK_PER_REBIRTH = 2550

function RebirthState.packTarget(rebirths: number?): number
	return RebirthState.PACK_BASE + (rebirths or 0) * RebirthState.PACK_PER_REBIRTH
end

function RebirthState.new(options: Options?): RebirthState
	local opts: Options = options or {}
	local self = setmetatable({
		_pending = false,
		_fails = 0,
		_cooldown = 0,
		_lastAt = nil,
		_reqAt = 0,
		_beforeStrength = 0,
		_timeout = opts.timeout or RebirthState.DEFAULT_TIMEOUT,
		_successCooldown = opts.successCooldown or RebirthState.DEFAULT_SUCCESS_COOLDOWN,
		_maxBackoff = opts.maxBackoff or RebirthState.DEFAULT_MAX_BACKOFF,
		_warnAt = opts.warnAt or RebirthState.DEFAULT_WARN_AT,
		_minInterval = opts.minInterval or RebirthState.DEFAULT_MIN_INTERVAL,
	}, RebirthState)
	return (self :: any) :: RebirthState
end

local function result(self: RebirthState, action: string, outcome: string, shouldWarn: boolean): Result
	return { action = action, outcome = outcome, fails = self._fails, shouldWarn = shouldWarn }
end

function RebirthState.isPending(self: RebirthState): boolean
	return self._pending
end

function RebirthState.failures(self: RebirthState): number
	return self._fails
end

-- The timestamp before which nothing will be attempted.
function RebirthState.cooldown(self: RebirthState): number
	return self._cooldown
end

-- The request never made it out (no remote, rate limited away). Undo the
-- pending flag so the next interval can try again.
function RebirthState.abort(self: RebirthState)
	self._pending = false
end

function RebirthState.reset(self: RebirthState)
	self._pending = false
	self._fails = 0
	self._cooldown = 0
	self._lastAt = nil
	self._reqAt = 0
	self._beforeStrength = 0
end

function RebirthState.step(self: RebirthState, input: Input, now: number): Result
	if input.rate <= 0 then
		return result(self, "none", "disabled", false)
	end

	if now < self._cooldown then
		return result(self, "none", "cooldown", false)
	end

	if self._pending then
		local before = self._beforeStrength
		local collapsed = input.strength <= 0.01
			or (before > 0 and input.strength < before * 0.05)
		if collapsed then
			self._pending = false
			self._fails = 0
			self._cooldown = now + self._successCooldown
			return result(self, "none", "succeeded", false)
		end
		if now - self._reqAt > self._timeout then
			self._pending = false
			self._fails += 1
			self._cooldown = now + math.min(self._maxBackoff, self._fails)
			return result(self, "none", "failed", self._fails == self._warnAt)
		end
		return result(self, "none", "waiting", false)
	end

	if input.target > 0 and input.rebirths >= input.target then
		return result(self, "none", "target-reached", false)
	end

	local interval = math.max(self._minInterval, 1 / math.max(1, input.rate))
	local lastAt = self._lastAt
	if lastAt ~= nil and now - lastAt < interval - RebirthState.EPSILON then
		return result(self, "none", "interval", false)
	end

	self._lastAt = now
	self._reqAt = now
	self._beforeStrength = input.strength
	self._pending = true
	return result(self, "send", "sent", false)
end

return RebirthState
end

__modules["core/PackState"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	PackState -- the multi-phase "pack rebirth" sequence. Pure.

	The original was a sequential coroutine (a loop, then a call, then a
	repeat-until, all with task.wait() inside), which cannot be cancelled, cannot
	report progress, and hides its own timeouts. The same sequence as an explicit
	phase machine can do all three:

	    training --> equipping --> requesting --> done

	Two details preserved: the training phase gives up on its own after a time
	limit and proceeds anyway (a rebirth that is slow is better than one that
	never happens), and the requesting phase stops as soon as the rebirth counter
	moves, rather than after a fixed number of attempts.
]]

local PackState = {}
PackState.__index = PackState

export type Options = {
	timeLimit: number?,
	maxTries: number?,
	equipDelay: number?,
	tryInterval: number?,
}

export type Input = {
	strength: number,
	rebirths: number,
	rebirthsBefore: number,
	target: number,
	busy: boolean?,
}

export type Step = {
	phase: string,
	action: string,
	tries: number,
	done: boolean,
	success: boolean,
	timedOut: boolean,
}

export type PackState = {
	phase: string,
	startedAt: number?,
	equipAt: number,
	lastTry: number?,
	tries: number,
	_timeLimit: number,
	_maxTries: number,
	_equipDelay: number,
	_tryInterval: number,
	step: (PackState, Input, number) -> Step,
	reset: (PackState) -> (),
}

PackState.PHASE_TRAINING = "training"
PackState.PHASE_EQUIPPING = "equipping"
PackState.PHASE_REQUESTING = "requesting"
PackState.PHASE_DONE = "done"

PackState.DEFAULT_TIME_LIMIT = 60
PackState.DEFAULT_MAX_TRIES = 20
PackState.DEFAULT_EQUIP_DELAY = 0.25
PackState.DEFAULT_TRY_INTERVAL = 0.15

PackState.EPSILON = 1e-9

function PackState.new(options: Options?): PackState
	local opts: Options = options or {}
	local self = setmetatable({
		phase = PackState.PHASE_TRAINING,
		startedAt = nil,
		equipAt = 0,
		lastTry = nil,
		tries = 0,
		_timeLimit = opts.timeLimit or PackState.DEFAULT_TIME_LIMIT,
		_maxTries = opts.maxTries or PackState.DEFAULT_MAX_TRIES,
		_equipDelay = opts.equipDelay or PackState.DEFAULT_EQUIP_DELAY,
		_tryInterval = opts.tryInterval or PackState.DEFAULT_TRY_INTERVAL,
	}, PackState)
	return (self :: any) :: PackState
end

function PackState.reset(self: PackState)
	self.phase = PackState.PHASE_TRAINING
	self.startedAt = nil
	self.equipAt = 0
	self.lastTry = nil
	self.tries = 0
end

local function step(self: PackState, phase: string, action: string, done: boolean, success: boolean, timedOut: boolean): Step
	return {
		phase = phase,
		action = action,
		tries = self.tries,
		done = done,
		success = success,
		timedOut = timedOut,
	}
end

function PackState.step(self: PackState, input: Input, now: number): Step
	if self.startedAt == nil then
		self.startedAt = now
	end

	if self.phase == PackState.PHASE_TRAINING then
		local reached = input.strength >= input.target
		local expired = now - (self.startedAt or now) > self._timeLimit
		if reached or expired then
			-- Either way the next thing to do is put the farming pets on.
			self.phase = PackState.PHASE_EQUIPPING
			self.equipAt = now
			return step(self, PackState.PHASE_EQUIPPING, "equip", false, false, expired)
		end
		return step(self, PackState.PHASE_TRAINING, "train", false, false, false)
	end

	if self.phase == PackState.PHASE_EQUIPPING then
		local waited = now - self.equipAt >= self._equipDelay - PackState.EPSILON
		-- `busy` keeps the sequence from firing a rebirth while the pets are
		-- still being equipped one step at a time.
		if not waited or input.busy == true then
			return step(self, PackState.PHASE_EQUIPPING, "wait", false, false, false)
		end
		self.phase = PackState.PHASE_REQUESTING
		self.lastTry = nil
		self.tries = 0
		return step(self, PackState.PHASE_REQUESTING, "wait", false, false, false)
	end

	if self.phase == PackState.PHASE_REQUESTING then
		if input.rebirths > input.rebirthsBefore then
			self.phase = PackState.PHASE_DONE
			return step(self, PackState.PHASE_DONE, "none", true, true, false)
		end
		if self.tries >= self._maxTries then
			self.phase = PackState.PHASE_DONE
			return step(self, PackState.PHASE_DONE, "none", true, false, false)
		end
		local lastTry = self.lastTry
		if lastTry ~= nil and now - lastTry < self._tryInterval - PackState.EPSILON then
			return step(self, PackState.PHASE_REQUESTING, "wait", false, false, false)
		end
		self.lastTry = now
		self.tries += 1
		return step(self, PackState.PHASE_REQUESTING, "request", false, false, false)
	end

	return step(self, PackState.PHASE_DONE, "none", true, false, false)
end

return PackState
end

__modules["core/RejoinTriggers"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	RejoinTriggers -- "should we rejoin?" as a pure function. Pure.

	Two rules were buried in V1007's shared 10-second sustain and are worth making
	explicit:

	  * the FPS and ping triggers require the condition to hold for 10 seconds,
	    because a single stuttering frame or one lag spike is not a reason to
	    abandon a session;
	  * the MEMORY trigger does not. It fires as soon as the threshold is crossed,
	    because memory only grows -- waiting would just delay an inevitable rejoin,
	    and the sample is taken once every 15 seconds anyway.

	A reading of zero or less means "no sample yet" and never trips anything
	(V1007 checked `mem > 0`, `fps > 0`, `ping > 0` for exactly that reason).
]]

local RejoinTriggers = {}
RejoinTriggers.__index = RejoinTriggers

export type Options = {
	sustain: number?,
	memorySustain: number?,
}

export type Thresholds = {
	memEnabled: boolean,
	memThreshold: number,
	fpsEnabled: boolean,
	fpsThreshold: number,
	pingEnabled: boolean,
	pingThreshold: number,
}

export type Reading = {
	memory: number,
	fps: number,
	ping: number,
}

export type Evaluator = {
	_since: { [string]: number? },
	sustain: number,
	memorySustain: number,
	evaluate: (Evaluator, Thresholds, Reading, number) -> { string },
	reset: (Evaluator) -> (),
}

RejoinTriggers.DEFAULT_SUSTAIN = 10
RejoinTriggers.DEFAULT_MEMORY_SUSTAIN = 0

-- See Hold/MountState: `now - since` on two nearby floats can land a hair under
-- the threshold and delay a trigger by a whole tick.
RejoinTriggers.EPSILON = 1e-9

function RejoinTriggers.new(options: Options?): Evaluator
	local opts: Options = options or {}
	local self = setmetatable({
		_since = {},
		sustain = opts.sustain or RejoinTriggers.DEFAULT_SUSTAIN,
		memorySustain = opts.memorySustain or RejoinTriggers.DEFAULT_MEMORY_SUSTAIN,
	}, RejoinTriggers)
	return (self :: any) :: Evaluator
end

function RejoinTriggers.reset(self: Evaluator)
	table.clear(self._since)
end

-- Has the condition held long enough? Starts the clock on the first breach.
local function sustained(self: Evaluator, key: string, breached: boolean, now: number, sustain: number): boolean
	if not breached then
		self._since[key] = nil
		return false
	end
	-- `since` is assigned from a fresh local rather than reassigned: Luau does not
	-- narrow an optional that is reassigned inside its own nil-check branch.
	local since: number
	local stored = self._since[key]
	if stored == nil then
		since = now
		self._since[key] = now
	else
		since = stored
	end
	return now - since >= sustain - RejoinTriggers.EPSILON
end

-- Returns the list of reasons to rejoin; empty means "stay".
function RejoinTriggers.evaluate(self: Evaluator, thresholds: Thresholds, reading: Reading, now: number): { string }
	local reasons: { string } = {}

	local memoryOver = thresholds.memEnabled and reading.memory > 0 and reading.memory > thresholds.memThreshold
	if sustained(self, "memory", memoryOver, now, self.memorySustain) then
		table.insert(reasons, string.format("内存 %dMB", reading.memory))
	end

	local fpsUnder = thresholds.fpsEnabled and reading.fps > 0 and reading.fps < thresholds.fpsThreshold
	if sustained(self, "fps", fpsUnder, now, self.sustain) then
		table.insert(reasons, string.format("帧率 %.0f", reading.fps))
	end

	-- THE MEAN, NOT THE WORST -- and the difference matters here.
	--
	-- This trigger LEAVES THE SESSION, and the sustain window already answers "is
	-- it still bad". The worst sample is the info panel's figure (it must show the
	-- spike), but acting on it would abandon a healthy session for the next 30 s
	-- because of a single spike, so the mean is what may trip a rejoin.
	local ping = reading.ping or 0
	local pingOver = thresholds.pingEnabled and ping > 0 and ping > thresholds.pingThreshold
	if sustained(self, "ping", pingOver, now, self.sustain) then
		table.insert(reasons, string.format("延迟 %d", ping))
	end

	return reasons
end

return RejoinTriggers
end

__modules["core/ServerPick"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	ServerPick -- turning the public server list into an ordered plan. Pure.

	Ported from Core.fetchServers and the mode branches of Core.doRejoin. The
	mode names are the user's, and they mean:

	    same     -- back to this server; if that fails, the most crowded one
	    crowded  -- most players first, this server last
	    sparse   -- fewest players first, this server last
	    private  -- a private server code, falling back to this server
	    player   -- one named player's server, then the gradient fallback

	Every mode ends with a fallback rather than a dead end, because the failure
	mode of "cannot rejoin" is staying in a session the user asked to leave.

	The private-server code extraction is real string parsing (a link, a query
	parameter, or a bare code) and was inline in three chained `:match` calls
	before; it is now one tested function.
]]

local ServerPick = {}

export type Server = {
	id: string,
	playing: number,
	maxPlayers: number,
}

export type Plan = {
	mode: string,
	code: string?,
	ids: { string },
}

ServerPick.MODES = { "same", "crowded", "sparse", "private", "player" }

--[[
	Pull the usable servers out of the games API response.

	Full servers and the server we are already on are dropped: the first would
	fail and the second is not a rejoin.
]]
function ServerPick.parse(payload: any, currentJobId: string?): { Server }
	local out: { Server } = {}
	if type(payload) ~= "table" then
		return out
	end
	local record = payload :: any
	local rows = record.data
	if type(rows) ~= "table" then
		return out
	end
	for _, row in ipairs(rows) do
		if type(row) == "table" then
			local entry = row :: any
			local id = entry.id
			if type(id) == "string" and id ~= currentJobId then
				local playing = tonumber(entry.playing) or 0
				local maxPlayers = tonumber(entry.maxPlayers) or 0
				if playing < maxPlayers then
					table.insert(out, { id = id, playing = playing, maxPlayers = maxPlayers })
				end
			end
		end
	end
	return out
end

-- "privateServerLinkCode=ABC", "?code=ABC", or a bare "ABC".
function ServerPick.privateCode(text: string?): string?
	if text == nil or text == "" then
		return nil
	end
	local fromLink = string.match(text, "privateServerLinkCode=([%w%-_]+)")
	if fromLink ~= nil then
		return fromLink
	end
	local fromQuery = string.match(text, "[%?&]code=([%w%-_]+)")
	if fromQuery ~= nil then
		return fromQuery
	end
	-- A LINK we could not parse is not a code. Returning it would make the
	-- "private" rung attempt a doomed teleport and delay the next rung, which is
	-- exactly what `chain`'s addPrivate guard is documented to avoid.
	if string.find(text, "://", 1, true) ~= nil then
		return nil
	end
	return text
end

local function idsForJob(currentJobId: string?): { string }
	local ids: { string } = {}
	if currentJobId ~= nil and currentJobId ~= "" then
		table.insert(ids, currentJobId)
	end
	return ids
end

ServerPick.idsForJob = idsForJob

local function sortByPlayers(servers: { Server }, descending: boolean): { Server }
	local sorted = table.clone(servers)
	table.sort(sorted, function(a: Server, b: Server): boolean
		if a.playing == b.playing then
			-- Stable and deterministic: equal populations order by id.
			return a.id < b.id
		end
		if descending then
			return a.playing > b.playing
		end
		return a.playing < b.playing
	end)
	return sorted
end

--[[
	Build the attempt order for a mode.

	`currentJobId` is appended as the final attempt in every mode except when it
	is already at the front, so the plan always has somewhere to land.
]]
function ServerPick.plan(mode: string?, servers: { Server }, currentJobId: string?, privateInput: string?): Plan
	local resolved = mode or "same"

	if resolved == "private" then
		return {
			mode = resolved,
			code = ServerPick.privateCode(privateInput),
			ids = idsForJob(currentJobId),
		}
	end

	local ordered: { string } = {}
	local function append(id: string?)
		if id == nil or id == "" then
			return
		end
		for _, existing in ipairs(ordered) do
			if existing == id then
				return
			end
		end
		table.insert(ordered, id)
	end

	if resolved == "crowded" then
		for _, server in ipairs(sortByPlayers(servers, true)) do
			append(server.id)
		end
		append(currentJobId)
	elseif resolved == "sparse" then
		for _, server in ipairs(sortByPlayers(servers, false)) do
			append(server.id)
		end
		append(currentJobId)
	else
		-- "same" and anything unrecognised: this server first, then the busiest
		-- alternatives.
		append(currentJobId)
		for _, server in ipairs(sortByPlayers(servers, true)) do
			append(server.id)
		end
	end

	return { mode = resolved, code = nil, ids = ordered }
end

--[[
	THE GRADIENT FALLBACK CHAIN ("梯度降级机制").

	`plan` answers "in which order do we try servers for THIS mode". This answers
	the question the user actually asked: "what do we try WHEN that fails, and
	what if the player we were looking for is not there?"

	One ordered attempt list, most specific first, each rung reached only after the
	previous one demonstrably failed to change the server:

	    player    -- the named player's own server (nil when not resolvable)
	    private   -- the private code, when one is configured AND looks valid
	    servers   -- the busiest / quietest public servers
	    current   -- this server, which always succeeds at "somewhere"

	Returned as data because both halves are decisions: WHICH rung is next (pure,
	tested) and HOW it is attempted (game/Rejoin, engine calls).
]]
export type Attempt = {
	kind: string, -- "job" | "private"
	id: string?,
	code: string?,
	label: string,
}

function ServerPick.chain(
	mode: string?,
	servers: { Server },
	currentJobId: string?,
	privateInput: string?,
	targetJobId: string?
): { Attempt }
	local resolved = mode or "same"
	local attempts: { Attempt } = {}

	local function hasId(id: string?): boolean
		if id == nil or id == "" then
			return false
		end
		for _, attempt in ipairs(attempts) do
			if attempt.id == id then
				return true
			end
		end
		return false
	end

	local function addJob(id: string?, label: string)
		--[[
			A MISSING id IS NOT AN ATTEMPT.

			Without this guard the `player` mode inserted a `{ kind = "job", id = nil }`
			rung when the named player could not be resolved, which the caller then
			had to recognise and skip -- and "skip the empty rung" is exactly the
			kind of bookkeeping that ends up wrong (the first version of the chain
			did not skip it at all). The chain must contain only real targets.
		]]
		if id == nil or id == "" then
			return
		end
		if hasId(id) then
			return
		end
		table.insert(attempts, { kind = "job", id = id, code = nil, label = label })
	end

	local code = ServerPick.privateCode(privateInput)
	local function addPrivate(label: string)
		-- A code that is not a code (empty, or a URL that did not parse) is NOT an
		-- attempt: trying it would fail and delay the next rung.
		if code == nil or code == "" then
			return
		end
		table.insert(attempts, { kind = "private", id = nil, code = code, label = label })
	end

	if resolved == "player" then
		-- 1) the named player's server, 2) private, 3) quiet public servers,
		-- 4) this server.
		addJob(targetJobId, "目标玩家所在服")
		addPrivate("私服")
		for _, server in ipairs(sortByPlayers(servers, false)) do
			addJob(server.id, "人少的服务器")
		end
	elseif resolved == "private" then
		addPrivate("私服")
		for _, server in ipairs(sortByPlayers(servers, false)) do
			addJob(server.id, "人少的服务器")
		end
	elseif resolved == "crowded" then
		for _, server in ipairs(sortByPlayers(servers, true)) do
			addJob(server.id, "人多的服务器")
		end
	elseif resolved == "sparse" then
		for _, server in ipairs(sortByPlayers(servers, false)) do
			addJob(server.id, "人少的服务器")
		end
	else
		addJob(currentJobId, "原服务器")
		for _, server in ipairs(sortByPlayers(servers, true)) do
			addJob(server.id, "人多的服务器")
		end
	end

	--[[
		The last rung always exists: staying/returning here beats "cannot rejoin".
	]]
	if resolved ~= "same" then
		addJob(currentJobId, "原服务器")
	end
	if #attempts == 0 and currentJobId ~= nil and currentJobId ~= "" then
		addJob(currentJobId, "原服务器")
	end
	return attempts
end

return ServerPick
end

__modules["core/Metrics"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Metrics -- the rolling frame/memory/ping figures. Pure.

	Three accumulators with boundaries that are easy to get subtly wrong:

	  * the frame rate is measured over a WINDOW (frames / elapsed), not per
	    frame, so it does not read 240 on one frame and 12 on the next;
	  * the ping is the average of the last N samples, so one spike does not
	    decide the trigger;
	  * both windows reset exactly when they are full.

	The host supplies the clock and the raw numbers, so all of it is testable.
]]

local Metrics = {}
Metrics.__index = Metrics

export type Options = {
	fpsWindow: number?,
	pingSamples: number?,
	startFps: number?,
}

export type Reading = {
	fps: number,
	memory: number,
	ping: number,
	pingWorst: number,
	-- True when the sample came from the client-side estimate rather than the
	-- game's own server-side figure (see `setPingEstimated`).
	pingEstimated: boolean,
}

export type Metrics = {
	_window: number,
	_maxPing: number,
	_startFps: number,
	_frames: number,
	_elapsed: number,
	_fps: number,
	_ping: { number },
	_worst: { number },
	_pingValue: number,
	_pingWorst: number,
	_pingEstimated: boolean,
	_memory: number,
	frame: (Metrics, number) -> number,
	fps: (Metrics) -> number,
	pushPing: (Metrics, number) -> number,
	ping: (Metrics) -> number,
	pingWorst: (Metrics) -> number,
	setPingEstimated: (Metrics, boolean) -> (),
	setMemory: (Metrics, number) -> (),
	memory: (Metrics) -> number,
	reading: (Metrics) -> Reading,
	reset: (Metrics) -> (),
}

Metrics.DEFAULT_FPS_WINDOW = 0.5
Metrics.DEFAULT_PING_SAMPLES = 5
-- The worst-case window is much longer than the mean's on purpose: the mean
-- answers "how is the link now", the worst answers "how bad did it get", and a
-- 1000 ms spike must stay visible (30 samples at 1 Hz = half a minute).
Metrics.DEFAULT_WORST_SAMPLES = 30
Metrics.DEFAULT_START_FPS = 60

function Metrics.new(options: Options?): Metrics
	local opts: Options = options or {}
	local startFps = opts.startFps or Metrics.DEFAULT_START_FPS
	local self = setmetatable({
		_window = opts.fpsWindow or Metrics.DEFAULT_FPS_WINDOW,
		_maxPing = math.max(1, math.floor(opts.pingSamples or Metrics.DEFAULT_PING_SAMPLES)),
		_startFps = startFps,
		_frames = 0,
		_elapsed = 0,
		_fps = startFps,
		_ping = {},
		_worst = {},
		_pingValue = 0,
		_pingWorst = 0,
		_pingEstimated = false,
		_memory = 0,
	}, Metrics)
	return (self :: any) :: Metrics
end

function Metrics.reset(self: Metrics)
	self._frames = 0
	self._elapsed = 0
	-- The configured start rate, not the constant: a caller that asked for a
	-- different one had it ignored after the first reset.
	self._fps = self._startFps
	table.clear(self._ping)
	table.clear(self._worst)
	self._pingValue = 0
	self._pingWorst = 0
	-- The next sample decides where the number came from, so a stale "estimate"
	-- flag must not outlive the data it described.
	self._pingEstimated = false
end

-- Call once per frame. Returns the current frame rate (which only changes when
-- a window completes).
function Metrics.frame(self: Metrics, dt: number): number
	if dt <= 0 then
		return self._fps
	end
	self._frames += 1
	self._elapsed += dt
	if self._elapsed >= self._window then
		self._fps = self._frames / self._elapsed
		self._frames = 0
		self._elapsed = 0
	end
	return self._fps
end

function Metrics.fps(self: Metrics): number
	return self._fps
end

-- Add one latency sample (in milliseconds). Zero or negative means "no sample".
--
-- `_pingValue` is the MEAN of the window -- what the rejoin trigger and the
-- status read-out want, since a single spike must not move them. `_pingWorst`
-- is the WORST sample still in the window, which is what the info panel shows:
-- a mean of five samples hides a 1000 ms spike behind four quiet seconds
-- ((1000 + 4 * 1) / 5 = 200), and "网络延迟" must show how bad the link got.
function Metrics.pushPing(self: Metrics, millis: number): number
	if millis <= 0 then
		return self._pingValue
	end
	table.insert(self._ping, millis)
	while #self._ping > self._maxPing do
		table.remove(self._ping, 1)
	end
	table.insert(self._worst, millis)
	while #self._worst > Metrics.DEFAULT_WORST_SAMPLES do
		table.remove(self._worst, 1)
	end
	local total = 0
	for _, value in ipairs(self._ping) do
		total += value
	end
	local worst = 0
	for _, value in ipairs(self._worst) do
		if value > worst then
			worst = value
		end
	end
	self._pingValue = math.floor(total / #self._ping)
	self._pingWorst = math.floor(worst)
	return self._pingValue
end

-- Record that the latest sample was an ESTIMATE. The game's own "Data Ping" is
-- the figure the player sees in F9; the client estimate is a different quantity,
-- often several times smaller, so the flag lets the panel say "估算" instead of
-- silently lying.
function Metrics.setPingEstimated(self: Metrics, estimated: boolean)
	self._pingEstimated = estimated == true
end

function Metrics.ping(self: Metrics): number
	return self._pingValue
end

-- The worst latency still inside the window (0 = no sample yet).
function Metrics.pingWorst(self: Metrics): number
	return self._pingWorst
end

function Metrics.setMemory(self: Metrics, megabytes: number)
	if megabytes > 0 then
		self._memory = math.floor(megabytes)
	end
end

function Metrics.memory(self: Metrics): number
	return self._memory
end

function Metrics.reading(self: Metrics): Reading
	return {
		memory = self._memory,
		fps = self._fps,
		ping = self._pingValue,
		pingWorst = self._pingWorst,
		pingEstimated = self._pingEstimated,
	}
end

return Metrics
end

__modules["core/Palette"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Palette -- mapping colour roles from one theme to another. Pure, over plain
	{r, g, b} integers.

	The theme switch relates old colours to new ones, and Color3 must NOT be used
	as a table key: it is userdata, so lookup compares by REFERENCE, and a colour
	read back from a property is a different object from the one that went into
	the table -- almost every lookup missed and the switch "only changed a little
	bit".

	Doing the arithmetic on integer triples removes the problem by construction --
	equal components are equal, full stop -- and makes it testable without a
	Roblox runtime.
]]

local Palette = {}

export type RGB = { r: number, g: number, b: number }
export type Roles = { [string]: RGB }

export type Entry = { from: RGB, to: RGB }

export type Remap = {
	exact: { [string]: RGB },
	entries: { Entry },
}

local function clampByte(value: number): number
	local rounded = math.floor(value + 0.5)
	if rounded < 0 then
		return 0
	end
	if rounded > 255 then
		return 255
	end
	return rounded
end

-- Components, not identity: this is the whole point of the module.
function Palette.key(rgb: RGB): string
	return string.format("%d_%d_%d", clampByte(rgb.r), clampByte(rgb.g), clampByte(rgb.b))
end

function Palette.same(a: RGB, b: RGB): boolean
	return Palette.key(a) == Palette.key(b)
end

-- Build the old -> new mapping for the roles both palettes define.
-- A role whose colour did not change produces no entry: there is nothing to
-- animate, and including it would waste a tween per widget per role.
function Palette.build(from: Roles, to: Roles): Remap
	local remap: Remap = { exact = {}, entries = {} }
	for role, old in pairs(from) do
		local new = to[role]
		if new ~= nil and not Palette.same(old, new) then
			remap.exact[Palette.key(old)] = new
			table.insert(remap.entries, { from = old, to = new })
		end
	end
	return remap
end

function Palette.count(remap: Remap): number
	return #remap.entries
end

-- Exact lookup by components.
function Palette.exact(remap: Remap, rgb: RGB): RGB?
	return remap.exact[Palette.key(rgb)]
end

-- Nearest entry within `tolerance` per channel, or nil.
--
-- Exact first, then a tolerance sweep: a widget caught mid-tween, or hovered, is
-- not sitting on a palette value, and those are exactly the widgets that used to
-- keep their old theme's colour and make the switch look patchy. Distance is the
-- largest per-channel difference (Chebyshev).
function Palette.nearest(remap: Remap, rgb: RGB, tolerance: number?): RGB?
	local direct = Palette.exact(remap, rgb)
	if direct ~= nil then
		return direct
	end
	local limit = tolerance or 0
	if limit <= 0 then
		return nil
	end

	local best: RGB? = nil
	local bestDistance = math.huge
	for _, entry in ipairs(remap.entries) do
		local dr = math.abs(clampByte(rgb.r) - clampByte(entry.from.r))
		local dg = math.abs(clampByte(rgb.g) - clampByte(entry.from.g))
		local db = math.abs(clampByte(rgb.b) - clampByte(entry.from.b))
		local distance = math.max(dr, math.max(dg, db))
		if distance <= limit and distance < bestDistance then
			bestDistance = distance
			best = entry.to
		end
	end
	return best
end

return Palette
end

__modules["core/Arbiter"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Arbiter -- the depth ladder, the interference matrix and the avoid/insert
	protocol. Pure: no engine access, no clock, no `task`.

	WHY THIS EXISTS
	---------------

	core/Scheduler runs tasks in priority order and lets each task answer
	`enabled()`. That is enough while tasks are independent, and wrong here:
	this script's subsystems fight over one body and one pair of hands.

	The case that motivated this module:

	    auto-training can hang the player on a gym machine ("use equipment"),
	    and a machine makes it impossible to produce damage. While a kill or boss
	    task wants to hit something the machine has to be released -- and
	    released only TEMPORARILY, because when the damage task finishes the
	    machine is the strongest way to train again.

	The old shape of this was a pile of predicates consulted from every
	direction (`isCombatBusy`, `isMachineBusy`, `isBossAlive`), which can give
	exactly three answers: run, do not run, and -- the one that never existed --
	run at a LOWER DEPTH. There was nowhere to say "not as you are, but you may
	still work at level 2".

	THE MODEL
	---------

	  * DEPTH is how much of the world a task claims. Higher claims more, so it
	    is blocked by more and blocks more.
	  * A task declares the depth it WANTS and the depth it NEEDS (`floor`).
	    Below the floor it is refused: refusing is explainable, silently
	    degrading a mechanical lift into a push-up is not.
	  * REQUIREMENTS are flags other subsystems hold while they run (`damage`,
	    `standing`, `seat`). One implication carries the whole feature:
	    `damage` forbids equipment, so any `damage` hold caps every task at
	    `Depth.BODY`.
	  * An INSERT is the avoid protocol: hold a flag, run the interloper, release
	    it. Holds nest, and releasing the last one restores exactly what was
	    there before the first -- which a boolean cannot express and a counter
	    can.

	WHAT IT DELIBERATELY IS NOT
	---------------------------

	It runs nothing, waits for nothing and knows no time. `resolve` answers "at
	what depth may this run, and why"; the caller acts. That keeps the whole
	decision table provable in standalone Luau -- see tests/Arbiter.spec.luau.
]]

local Arbiter = {}

--[[
	The ladder. Higher claims more.

	MACHINE is the top rung because sitting on one is exclusive in both
	directions: it stops the player attacking and stops anything else moving
	them. That exclusivity is the entire reason this module exists.
]]
Arbiter.Depth = {
	IDLE = 0,
	BODY = 1, -- push-ups, handstand, sit-ups: free, and they damage
	FREE_WEIGHT = 2, -- dumbbell: free, and it damages
	MACHINE = 3, -- strongest, and the only rung that blocks damage
}

Arbiter.LABELS = {
	[0] = "空闲",
	[1] = "徒手",
	[2] = "哑铃",
	[3] = "器械",
}

Arbiter.REQUIREMENTS = { "damage", "standing", "seat" }

--[[
	The interference matrix: what each requirement forbids.

	`blocks` is the highest depth the requirement tolerates. `damage` sitting at
	BODY is the heart of the module -- it is what turns "using equipment blocks
	damage" into "training steps down to push-ups while something needs to hit".
]]
Arbiter.MATRIX = {
	damage = { blocks = Arbiter.Depth.BODY, reason = "需要造成伤害：器械会阻断出拳" },
	standing = { blocks = Arbiter.Depth.MACHINE, reason = "需要保持站姿" },
	seat = { blocks = Arbiter.Depth.MACHINE, reason = "需要占用座位" },
}

local REQUIREMENT_ORDER = { "damage", "seat", "standing" }

--[[
	Present-counts -> membership booleans.

	The two shapes are deliberately different: the pure helpers take
	`{ damage = true }` because that is what reads well in a test, while a live
	Arbiter stores COUNTS so holds can nest. This is the one place they meet.
]]
local function countsOf(active: { [string]: number }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for flag in pairs(active) do
		out[flag] = true
	end
	return out
end

--[[
	Every requirement that is currently active, in a fixed order.

	Deliberately NOT filtered by whether it strictly lowers `wanted`: the point
	of this list is to be shown to the user ("why did my equipment stop?"), and
	a requirement that is active but happens to allow the current depth is still
	the reason the depth is what it is. An earlier revision kept only strict
	offenders, which reported an empty list in exactly the case a user would be
	asking about.
]]
function Arbiter.blockersOf(active: { [string]: boolean }): { string }
	local out: { string } = {}
	for _, name in ipairs(REQUIREMENT_ORDER) do
		if Arbiter.MATRIX[name] ~= nil and active[name] == true then
			table.insert(out, name)
		end
	end
	return out
end

-- The cap the active requirements impose, plus the reason to display.
--[[
	Named `capOf` / `blockersOf` for the pure form: the instance methods
	`Arbiter.cap(self)` and `Arbiter.blockers(self, wanted)` are defined further
	down on the SAME table, and in Lua the later definition simply wins. Keeping
	the pure helpers under their own names is what stops one from silently
	replacing the other.
]]
function Arbiter.capOf(active: { [string]: boolean }): (number, string?)
	local limit = Arbiter.Depth.MACHINE
	local reason: string? = nil
	for _, name in ipairs(REQUIREMENT_ORDER) do
		local rule = Arbiter.MATRIX[name]
		if rule ~= nil and active[name] == true and rule.blocks < limit then
			limit = rule.blocks
			reason = rule.reason
		end
	end
	return limit, reason
end

--[[
	The pure decision. No instance, no owner: just the arithmetic.

	    allowed  may it run at all?
	    depth    the depth it may run at
	    reason   why it was capped or refused; nil when uncapped
]]
function Arbiter.decide(
	wanted: number,
	floor: number,
	active: { [string]: boolean }
): (boolean, number, string?)
	local limit, reason = Arbiter.capOf(active)
	if wanted <= limit then
		return true, wanted, nil
	end
	if limit < floor then
		return false, limit, reason
	end
	return true, limit, reason
end

export type Verdict = {
	allowed: boolean,
	depth: number,
	label: string,
	reason: string?,
	blockers: { string },
	pinned: boolean,
}

export type Frequency = {
	base: number,
	current: number,
	min: number,
	max: number,
	factor: number,
}

export type Instance = {
	kind: string,
	path: string?,
	wanted: number,
	floor: number,
	held: { [string]: number },
	pinned: number?,
	owner: Arbiter,
	resolve: (Instance) -> Verdict,
	label: (Instance, number?) -> string,
	setWanted: (Instance, number) -> (),
	hold: (Instance, string) -> boolean,
	releaseFlag: (Instance, string) -> boolean,
	preempt: (Instance, number) -> (),
	unpreempt: (Instance) -> boolean,
	isPreempted: (Instance) -> boolean,
	reset: (Instance) -> (),
	ok: (Instance) -> boolean,
}

export type Arbiter = {
	--[[
		Flag -> hold COUNT, not a boolean. Every active flag is present with a
		positive count, so `active[name] ~= nil` is the membership test and the
		`true` in `{ damage = true }` a caller passes to the pure helpers is
		simply the count 1.
	]]
	active: { [string]: number },
	instances: { Instance },
	frequency: { [string]: Frequency },
	onChange: ((string, boolean, string?) -> ())?,
	new: () -> Arbiter,
	instance: (Arbiter, string, string?, number?, number?) -> Instance,
	state: (Arbiter) -> { [string]: boolean },
	decideWith: (Arbiter, number, number?) -> (boolean, number, string?),
	hold: (Arbiter, string, string?) -> boolean,
	release: (Arbiter, string) -> boolean,
	required: (Arbiter, string) -> boolean,
	require: (Arbiter, string, string?) -> boolean,
	relieve: (Arbiter, string) -> boolean,
	activeList: (Arbiter) -> { string },
	report: (Arbiter) -> { { kind: string, allowed: boolean, depth: number, label: string, reason: string?, pinned: boolean } },
	depthOf: (Arbiter, string) -> number,
	interval: (Arbiter, string, number?, number?, number?) -> number,
	speedup: (Arbiter, string, number) -> number,
	slowdown: (Arbiter, string, number) -> number,
	adjustTo: (Arbiter, string, number) -> number,
	load: (Arbiter, string) -> number,
}

local InstanceMT = {}
InstanceMT.__index = InstanceMT

function InstanceMT.resolve(self: Instance): Verdict
	local allowed, depth, reason = Arbiter.decide(
		self.pinned or self.wanted,
		self.floor,
		countsOf(self.owner.active)
	)
	local mine: { string } = {}
	for flag in pairs(self.held) do
		table.insert(mine, flag)
	end
	table.sort(mine)
	return {
		allowed = allowed,
		depth = depth,
		label = Arbiter.LABELS[depth] or tostring(depth),
		reason = reason,
		blockers = mine,
		pinned = self.pinned ~= nil,
	}
end

function InstanceMT.label(self: Instance, depth: number?): string
	local level = depth or self.pinned or self.wanted
	return Arbiter.LABELS[level] or tostring(level)
end

function InstanceMT.setWanted(self: Instance, depth: number)
	self.wanted = depth
end

--[[
	The INSERT half: hold a requirement while this instance acts, release after.

	Nested holds are counted, so an inner insert can never drop an outer one's
	claim -- the failure mode a boolean would have.
]]
function InstanceMT.hold(self: Instance, flag: string): boolean
	if Arbiter.MATRIX[flag] == nil then
		return false
	end
	self.held[flag] = (self.held[flag] or 0) + 1
	return Arbiter.hold(self.owner, flag, self.kind)
end

function InstanceMT.releaseFlag(self: Instance, flag: string): boolean
	local held = self.held[flag] or 0
	if held <= 1 then
		self.held[flag] = nil
	else
		self.held[flag] = held - 1
	end
	return Arbiter.release(self.owner, flag)
end

--[[
	The avoid protocol: run at `depth` for a while, then `unpreempt`.

	The pin replaces `wanted` until released, so "lower the depth, do the main
	task, raise it back" is two calls and no bookkeeping at the call site.

	The requested depth is CLAMPED to the current cap. A pin above the cap would
	be a contradiction -- it would ask to run at a depth an active requirement
	forbids -- and clamping keeps `preempt(d) ; resolve().depth == d` true for
	every `d` the caller may legally ask for.
]]
function InstanceMT.preempt(self: Instance, depth: number)
	local limit = Arbiter.capOf(countsOf(self.owner.active))
	local clamped = if depth > limit then limit else depth
	self.pinned = clamped
end

-- Returns true when a pin was actually dropped (false when there was none).
function InstanceMT.unpreempt(self: Instance): boolean
	if self.pinned == nil then
		return false
	end
	self.pinned = nil
	return true
end

function InstanceMT.isPreempted(self: Instance): boolean
	return self.pinned ~= nil
end

function InstanceMT.reset(self: Instance)
	self.pinned = nil
end

function InstanceMT.ok(self: Instance): boolean
	return InstanceMT.resolve(self).allowed
end

local ArbiterMT = {}
-- Instances look their methods up on the Arbiter table itself: the metatable is
-- only a marker, so it must fall through to `Arbiter` and not to itself.
ArbiterMT.__index = Arbiter

function Arbiter.new(): Arbiter
	local self = setmetatable({
		active = {},
		instances = {},
		frequency = {},
		onChange = nil,
	}, ArbiterMT)
	return (self :: any) :: Arbiter
end

function Arbiter.instance(
	self: Arbiter,
	kind: string,
	path: string?,
	wanted: number?,
	floor: number?
): Instance
	local instance: Instance = {
		kind = kind,
		path = path,
		wanted = wanted or Arbiter.Depth.IDLE,
		floor = floor or Arbiter.Depth.IDLE,
		held = {},
		pinned = nil,
		owner = self,
		resolve = InstanceMT.resolve,
		label = InstanceMT.label,
		setWanted = InstanceMT.setWanted,
		hold = InstanceMT.hold,
		releaseFlag = InstanceMT.releaseFlag,
		preempt = InstanceMT.preempt,
		unpreempt = InstanceMT.unpreempt,
		isPreempted = InstanceMT.isPreempted,
		reset = InstanceMT.reset,
		ok = InstanceMT.ok,
	}
	table.insert(self.instances, instance)
	return instance
end

-- The pure helper's shape for callers that already hold an Arbiter, so nobody
-- has to reach into `.active` and re-derive the boolean view.
function Arbiter.state(self: Arbiter): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for flag in pairs(self.active) do
		out[flag] = true
	end
	return out
end

--[[
	The instance-flavoured decision, for a caller that already has an Arbiter.

	Deliberately NOT named `Arbiter.resolve`: `InstanceMT.resolve` calls the PURE
	`Arbiter.decide`, and an earlier revision declaring `Arbiter.resolve(self,
	...)` on this same table replaced the pure `decide` wrapper's arguments --
	which silently made every instance resolve at its FULL wanted depth, i.e.
	exactly the bug this module exists to prevent. `tests/Arbiter.spec.luau`
	pins the capped depth so that failure cannot come back unnoticed.
]]
function Arbiter.decideWith(self: Arbiter, wanted: number, floor: number?): (boolean, number, string?)
	local limit, reason = Arbiter.capOf(countsOf(self.active))
	if wanted <= limit then
		return true, wanted, nil
	end
	local atLeast = floor or wanted
	if limit < atLeast then
		return false, limit, reason
	end
	return true, limit, reason
end

--[[
	Hold a requirement. Returns true only on the transition from unheld, which is
	what an `onEnable`-style hook keys off; nested holds return false.
]]
function Arbiter.hold(self: Arbiter, flag: string, by: string?): boolean
	if Arbiter.MATRIX[flag] == nil then
		return false
	end
	local was = self.active[flag]
	self.active[flag] = (was or 0) + 1
	if was == nil then
		if self.onChange ~= nil then
			pcall(self.onChange, flag, true, by)
		end
		return true
	end
	return false
end

-- Returns true only when the LAST hold dropped, so a nested insert cannot flap
-- the rest of the script.
function Arbiter.release(self: Arbiter, flag: string): boolean
	local held = self.active[flag] or 0
	if held <= 1 then
		self.active[flag] = nil
		if held == 1 and self.onChange ~= nil then
			pcall(self.onChange, flag, false, nil)
		end
		return true
	end
	self.active[flag] = held - 1
	return false
end

Arbiter.require = Arbiter.hold
Arbiter.relieve = Arbiter.release

function Arbiter.required(self: Arbiter, flag: string): boolean
	return self.active[flag] ~= nil
end

function Arbiter.activeList(self: Arbiter): { string }
	local out: { string } = {}
	for flag in pairs(self.active) do
		table.insert(out, flag)
	end
	table.sort(out)
	return out
end

function Arbiter.report(self: Arbiter)
	local out = {}
	for _, instance in ipairs(self.instances) do
		local verdict = InstanceMT.resolve(instance)
		table.insert(out, {
			kind = instance.kind,
			allowed = verdict.allowed,
			depth = verdict.depth,
			label = verdict.label,
			reason = verdict.reason,
			pinned = verdict.pinned,
		})
	end
	return out
end

function Arbiter.depthOf(self: Arbiter, kind: string): number
	for _, instance in ipairs(self.instances) do
		if instance.kind == kind then
			return InstanceMT.resolve(instance).depth
		end
	end
	return Arbiter.Depth.IDLE
end

------------------------------------------------------------------ frequency --

--[[
	Frequency control.

	The arbiter owns one interval per shaped task, so "run slower while
	something more important is happening" is a call rather than a hand-rolled
	`if` in each subsystem.

	`speedup` raises the rate, `slowdown` lowers it; both clamp to the
	configured bounds. The clamp is not cosmetic: an unclamped factor is how a
	"temporary" adjustment becomes permanent, since 0.5 applied four times is
	1/16th and every intermediate value looked reasonable.
]]
function Arbiter.interval(self: Arbiter, kind: string, base: number?, min: number?, max: number?): number
	local entry = self.frequency[kind]
	if entry == nil then
		local b = base or 1
		entry = { base = b, current = b, min = min or b / 64, max = max or b * 64, factor = 1 }
		self.frequency[kind] = entry
	end
	return entry.current
end

local function clampEntry(entry: Frequency)
	local value = entry.base / entry.factor
	if value < entry.min then
		value = entry.min
	elseif value > entry.max then
		value = entry.max
	end
	entry.current = value
end

function Arbiter.speedup(self: Arbiter, kind: string, factor: number): number
	local entry = self.frequency[kind]
	if entry == nil then
		return Arbiter.interval(self, kind)
	end
	local safe = if factor > 0 then factor else 1
	entry.factor = math.max(0.01, entry.factor * safe)
	clampEntry(entry)
	return entry.current
end

function Arbiter.slowdown(self: Arbiter, kind: string, factor: number): number
	local entry = self.frequency[kind]
	if entry == nil then
		return Arbiter.interval(self, kind)
	end
	local safe = if factor > 0 then factor else 1
	entry.factor = math.max(0.01, entry.factor / safe)
	clampEntry(entry)
	return entry.current
end

function Arbiter.adjustTo(self: Arbiter, kind: string, factor: number): number
	local entry = self.frequency[kind]
	if entry == nil then
		return Arbiter.interval(self, kind)
	end
	entry.factor = math.max(0.01, factor)
	clampEntry(entry)
	return entry.current
end

function Arbiter.load(self: Arbiter, kind: string): number
	local entry = self.frequency[kind]
	if entry == nil then
		return 1
	end
	return entry.factor
end

return Arbiter
end

__modules["game/Runtime"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Runtime -- the single frame loop.

	Exactly one Heartbeat connection for the whole script, doing three things in
	this order every frame:

	    1. timers:step(now)       -- fire whatever is due
	    2. net:flush(now)         -- drain queued remote payloads
	    3. scheduler:step(dt, now)-- run enabled tasks, in priority order

	Nothing else in the script is allowed to connect to Heartbeat or
	RenderStepped. That invariant is what makes "destroy" trustworthy.
]]

local RunService = game:GetService("RunService")

local Timers = require("core/Timers")
local Scheduler = require("core/Scheduler")

local Runtime = {}
Runtime.__index = Runtime

export type Options = {
	net: any?,
	onError: ((source: string, message: string) -> ())?,
	failureLimit: number?,
	backoff: number?,
}

function Runtime.new(options: Options?)
	local opts: Options = options or {}

	local onError = opts.onError
	local function timersError(message: string)
		if onError ~= nil then
			onError("timer", message)
		end
	end
	local function taskError(taskId: string, message: string)
		if onError ~= nil then
			onError("task:" .. taskId, message)
		end
	end

	local self = setmetatable({
		timers = Timers.new(timersError),
		scheduler = Scheduler.new({
			onError = taskError,
			failureLimit = opts.failureLimit,
			backoff = opts.backoff,
		}),
		net = opts.net,
		now = os.clock(),
		frames = 0,
		destroyed = false,
		_preRender = {},
		_extra = {},
	}, Runtime)

	self._connection = RunService.Heartbeat:Connect(function(dt: number)
		Runtime.step(self, dt)
	end)

	return self
end

-- Position overriding has to happen on RenderStepped -- after physics has
-- settled and before the frame is drawn; on Heartbeat the correction lands a
-- frame late and the snap-back is visible. The Runtime owns this connection too,
-- so destroy() remains a complete teardown.
function Runtime.connectPreRender(self, fn)
	local connection = RunService.RenderStepped:Connect(function(_dt: number)
		if self.destroyed then
			return
		end
		fn(os.clock())
	end)
	table.insert(self._preRender, connection)
	return connection
end

-- Subsystems hand their engine connections over instead of keeping them, so
-- every connection in the script is owned by the Runtime and destroy() is a
-- complete teardown.
function Runtime.trackConnection(self, connection)
	if connection == nil then
		return nil
	end
	table.insert(self._extra, connection)
	return connection
end

function Runtime.step(self, dt: number)
	if self.destroyed then
		return
	end
	local now = os.clock()
	self.now = now
	self.frames += 1

	self.timers:step(now)
	if self.net ~= nil then
		self.net:flush(now)
	end
	self.scheduler:step(dt, now)
end

function Runtime.destroy(self)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self._connection ~= nil then
		self._connection:Disconnect()
		self._connection = nil
	end
	for _, connection in ipairs(self._preRender) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._preRender)
	for _, connection in ipairs(self._extra) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._extra)
	self.timers:cancelAll()
	self.scheduler:setPaused(true)
end

return Runtime
end

__modules["game/Character"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Character -- event-driven character tracking.

	The cache is driven by events instead of a per-Heartbeat refresh:

	    Player.CharacterAdded      -> adopt the new model
	    ChildAdded on the model    -> pick up a Humanoid / root that streams in late
	    Humanoid.Died              -> mark dead
	    CharacterRemoving / model.AncestryChanged -> clear

	`runtime.frames` therefore costs nothing when nothing happens, and `isAlive()`
	is a field read rather than a tree walk.
]]

local Signal = require("core/Signal")

local Character = {}
Character.__index = Character

--[[
	The cached humanoid and root live in `_humanoid` / `_root`, not `humanoid` /
	`root`: those are this class's METHOD names, and a nil-valued field is an
	ABSENT key, so `self.humanoid` fell through `__index` to the function and
	`self.humanoid.Parent` raised "attempt to index function with 'Parent'" on the
	first character resolution. `_clearModel` sets the field back to nil, so
	initialising it is not enough either.
]]
export type Entry = {
	player: any,
	character: any?,
	_humanoid: any?,
	_root: any?,
	alive: boolean,
	generation: number,
}

function Character.new(player)
	local self = setmetatable({
		player = player,
		character = nil,
		_humanoid = nil,
		_root = nil,
		alive = false,
		generation = 0,
		changed = Signal.new(),
		_connections = {},
	}, Character)

	self:_bind(player)
	self:_adopt(player.Character)
	return self
end

--[[
	Connections are stored as RECORDS ({ connection, owner }), not as connections
	tagged with a field: an RBXScriptConnection is engine userdata and rejects
	unknown members ("_mkOwner is not a valid member of RBXScriptConnection"),
	and attributes exist on Instances, not on connections.
]]
function Character._track(self, connection, owner)
	table.insert(self._connections, { connection = connection, owner = owner })
	return connection
end

function Character._clearModel(self)
	local character = self.character
	if character ~= nil then
		for i = #self._connections, 1, -1 do
			local record = self._connections[i]
			-- Player-level records carry no owner and are kept; model-level ones
			-- were created with owner set to the model being watched.
			if record.owner == character then
				pcall(function()
					record.connection:Disconnect()
				end)
				table.remove(self._connections, i)
			end
		end
	end
	self.character = nil
	self._humanoid = nil
	self._root = nil
	self.alive = false
end

function Character._resolve(self)
	local character = self.character
	if character == nil then
		return false
	end
	local changed = false

	if self._humanoid == nil or self._humanoid.Parent == nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			self._humanoid = humanoid
			changed = true
			self:_trackOwner(humanoid.Died:Connect(function()
				self.alive = false
				self.changed:fire("died", self)
			end), character)
		end
	end

	if self._root == nil or self._root.Parent == nil then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root ~= nil then
			self._root = root
			changed = true
		end
	end

	if self._humanoid ~= nil then
		self.alive = self._humanoid.Health > 0
	end
	return changed
end

function Character._trackOwner(self, connection, owner)
	return self:_track(connection, owner)
end

function Character._adopt(self, character)
	self:_clearModel(self)
	if character == nil then
		self.changed:fire("removed", self)
		return
	end
	self.character = character
	self.generation += 1

	self:_resolve(self)

	-- Humanoid / HumanoidRootPart can stream in after CharacterAdded fires, so
	-- watch the model instead of polling it.
	self:_trackOwner(character.ChildAdded:Connect(function()
		if self:_resolve(self) then
			self.changed:fire("part", self)
		end
	end), character)

	self:_trackOwner(character.AncestryChanged:Connect(function()
		if character.Parent == nil then
			self:_clearModel(self)
			self.changed:fire("removed", self)
		end
	end), character)

	self.changed:fire("spawned", self)
end

function Character._bind(self, player)
	self:_track(player.CharacterAdded:Connect(function(character)
		self:_adopt(character)
	end))
	self:_track(player.CharacterRemoving:Connect(function()
		self:_clearModel(self)
		self.changed:fire("removing", self)
	end))
end

function Character.current(self): any?
	return self.character
end

function Character.humanoid(self): any?
	return self._humanoid
end

function Character.root(self): any?
	return self._root
end

function Character.isAlive(self): boolean
	local humanoid = self._humanoid
	if humanoid == nil or humanoid.Parent == nil then
		return false
	end
	return humanoid.Health > 0
end

-- Resolve lazily: the common case is a cache hit, and a miss costs one
-- FindFirstChild, not one per frame.
function Character.requireRoot(self): any?
	local root = self._root
	if root ~= nil and root.Parent ~= nil then
		return root
	end
	self:_resolve(self)
	return self._root
end

-- handler(reason, entry) with reason: "spawned" | "part" | "died" | "removing" | "removed"
function Character.onChanged(self, handler)
	return self.changed:connect(handler)
end

function Character.destroy(self)
	for _, record in ipairs(self._connections) do
		pcall(function()
			record.connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	self.changed:clear()
	self:_clearModel(self)
end

return Character
end

__modules["game/Remotes"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Remotes -- locating the game's remote objects, with caching and invalidation.

	  * a cached remote is only trusted while it is still parented where it was
	    found, so a re-created remote is picked up automatically;
	  * the expensive scan (walking ReplicatedStorage) is throttled, but a failed
	    scan is not cached as a permanent "not found".

	`LocalPlayer` is read lazily because this module can be required before the
	player exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local cache = {}
local lastScan = {}

local function player()
	return Players.LocalPlayer
end

local function isRemote(instance)
	local class = instance.ClassName
	return class == "RemoteEvent" or class == "RemoteFunction"
end

local function firstMatching(parent, needle)
	if parent == nil then
		return nil
	end
	for _, child in ipairs(parent:GetChildren()) do
		if isRemote(child) and string.find(string.lower(child.Name), needle, 1, true) then
			return child
		end
	end
	return nil
end

function Remotes.rEvents()
	return ReplicatedStorage:FindFirstChild("rEvents")
end

function Remotes.onPlayer(exactName, keyword)
	local user = player()
	if user == nil then
		return nil
	end

	local key = "p:" .. exactName
	local cached = cache[key]
	if cached ~= nil and cached.Parent == user then
		return cached
	end

	local direct = user:FindFirstChild(exactName)
	if direct ~= nil and isRemote(direct) then
		cache[key] = direct
		return direct
	end

	local found = firstMatching(user, keyword)
	cache[key] = found
	return found
end

-- A failed scan is not cached, so a later spawn is still discoverable.
function Remotes.inREvents(keyword, throttle)
	local key = "re:" .. keyword
	local cached = cache[key]
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end

	local now = os.clock()
	local wait = throttle or 3
	local scanned = lastScan[key]
	if scanned ~= nil and now - scanned < wait then
		return nil
	end
	lastScan[key] = now

	local found = firstMatching(Remotes.rEvents(), keyword)
	if found ~= nil then
		cache[key] = found
	end
	return found
end

function Remotes.muscle()
	return Remotes.onPlayer("muscleEvent", "muscle")
end

function Remotes.rebirth()
	return Remotes.inREvents("rebirth", 3)
end

function Remotes.equipPet()
	return Remotes.inREvents("equippetevent", 5)
end

function Remotes.petShop()
	return Remotes.inREvents("cpetshopremote", 5)
end

function Remotes.wheel()
	return Remotes.inREvents("openfortunewheelremote", 5)
end

-- Exact name first: a keyword like "size" or "machine" can pick up an unrelated
-- remote whose name merely contains it.
local function exactOrKeyword(exactName, keyword, throttle)
	local events = Remotes.rEvents()
	if events ~= nil then
		local exact = events:FindFirstChild(exactName)
		if exact ~= nil and isRemote(exact) then
			cache["re:" .. keyword] = exact
			return exact
		end
	end
	return Remotes.inREvents(keyword, throttle)
end

function Remotes.size()
	return exactOrKeyword("changeSpeedSizeRemote", "changespeedsizeremote", 10)
end

function Remotes.machine()
	return exactOrKeyword("machineInteractRemote", "machineinteractremote", 5)
end

--[[
	One RemoteFunction for the whole crystal feature (`openCrystalRemote`) --
	shape confirmed from recordings of the game calling itself:

	    InvokeServer("openCrystal", "<Crystal Name>")            -- hatch one
	    InvokeServer("saveAutoSell", "<Crystal Name>", {          -- auto-sell
	        Pets = { ["<Pet>"] = true }, Enabled = <bool>, Auras = {}
	    })
]]
function Remotes.crystal()
	return exactOrKeyword("openCrystalRemote", "opencrystalremote", 5)
end

--[[
	The game's own "move me to another gym" RemoteFunction, the same one its Travel
	menu uses:

	    local args = { "travelToArea", workspace.areaCircles.hallowedGymCircle }
	    ReplicatedStorage.rEvents.areaTravelRemote:InvokeServer(unpack(args))

	RemoteFunction means it YIELDS (see game/Boss.requestTravel); the circle
	selects the destination, so both halves are looked up together here.
]]
function Remotes.areaTravel()
	return exactOrKeyword("areaTravelRemote", "areatravelremote", 5)
end

-- Nil when the game is not running the seasonal area at all, which the caller
-- reports instead of teleporting somewhere arbitrary.
function Remotes.hallowedGymCircle()
	local circles = Workspace:FindFirstChild("areaCircles")
	if circles == nil then
		return nil
	end
	return circles:FindFirstChild("hallowedGymCircle")
end

function Remotes.clear()
	table.clear(cache)
	table.clear(lastScan)
end

return Remotes
end

__modules["game/Net"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	GameNet -- the Roblox side of the network layer; all policy (token buckets,
	queues, drop accounting, backoff) lives in core/Net. Two gotchas:

	  1. The remote is resolved at SEND time, not when the channel is created: a
	     re-created remote (respawn, rejoin) would leave channels holding a dead
	     instance.
	  2. The payload is packed BEFORE the pcall. `remote:FireServer(...)` inside
	     the closure does not compile -- `...` is unavailable in a non-vararg
	     anonymous function ("Cannot use '...' outside of a vararg function").
]]

local CoreNet = require("core/Net")
local Remotes = require("game/Remotes")

local GameNet = {}

GameNet.MUSCLE_CHANNEL = "muscle"

function GameNet.senderFor(resolve)
	return function(...)
		local remote = resolve()
		if remote == nil or remote.Parent == nil then
			return false, "remote unavailable"
		end

		local args = table.pack(...)
		local count = args.n

		local ok, err = pcall(function()
			if remote:IsA("RemoteFunction") then
				remote:InvokeServer(table.unpack(args, 1, count))
			else
				remote:FireServer(table.unpack(args, 1, count))
			end
		end)

		if ok then
			return true
		end
		return false, tostring(err)
	end
end

function GameNet.new(options)
	return CoreNet.new(options)
end

function GameNet.channel(net, name, resolve, options)
	return net:addChannel(name, GameNet.senderFor(resolve), options)
end

-- The muscle remote is shared by training, egg dropping and the pack-rebirth
-- burst; the first installer creates the channel and the others reuse it, so a
-- channel with no rate limit is not replaced by a throttled one.
function GameNet.ensureMuscle(net, throttleRate)
	if net:channel(GameNet.MUSCLE_CHANNEL) ~= nil then
		return false
	end
	net:addChannel(GameNet.MUSCLE_CHANNEL, GameNet.senderFor(function()
		return Remotes.muscle()
	end), {
		rate = throttleRate,
		burst = 64,
		queue = 0,
	})
	return true
end

return GameNet
end

__modules["game/Persist"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Persist -- reading and writing the config file.

	This is the layer whose absence made "the config never saved" possible. In
	V1007 the save path was:

	    buildConfigData()              -- copies whole live subtables
	    HttpService:JSONEncode(data)   -- throws: Core.machine holds Instances
	    pcall(...)                     -- swallows the error
	    -- and nothing is ever written

	Two guarantees are enforced here instead:

	  1. SAVE projects through Config.project first, so only schema-declared
	     scalar values can reach the encoder. A live object cannot get in even by
	     accident, and the version is always stamped.
	  2. LOAD never raises. A missing file, an unreadable file, malformed JSON and
	     an out-of-range value all produce defaults plus a warning that the caller
	     can surface, because silently falling back is how the original hid the
	     problem for so long.
]]

local HttpService = game:GetService("HttpService")

local Config = require("core/Config")
local Store = require("core/Store")

local Persist = {}

Persist.FILE = "mk_v1008.json"
Persist.FALLBACKS = { "mk_v1007.json", "mk_v1006.json" }

--[[
	NUMBERED CONFIG SLOTS.

	V1008 had exactly one config file and no way to keep a second setup, which is
	the "保存配置 / 切换配置" the user asked for: one file means saving a new setup
	destroys the old one, so a user with a training profile and a boss profile
	cannot keep both.

	A slot is `mk_v1008.slot.N.json`. Numbered rather than named because the name
	would arrive from a TextBox and become a filename, which is how a config
	system acquires a path-traversal bug; the UI stores a display label INSIDE
	the file instead, so a label can be anything.
]]
Persist.SLOT_COUNT = 8
Persist.SLOT_PREFIX = "mk_v1008.slot."
Persist.SLOT_SUFFIX = ".json"
-- The label lives in the file, under a key the schema knows about but the user
-- cannot collide with (see core/Config's `meta` spec).
Persist.SLOT_LABEL_KEY = "meta.slotLabel"

function Persist.slotFile(index: number): string?
	if type(index) ~= "number" then
		return nil
	end
	local slot = math.floor(index)
	if slot < 1 or slot > Persist.SLOT_COUNT then
		return nil
	end
	return Persist.SLOT_PREFIX .. tostring(slot) .. Persist.SLOT_SUFFIX
end

--[[
	Is the 功能存档 layer allowed to WRITE?

	The master switch (`cfg.saveEnabled`) is deliberately consulted inside this
	module rather than at each call site: there is exactly one place that writes
	the config file and the slots, and a gate that lives at the call sites is how
	one of them keeps writing after the switch says no.

	Reading is never gated -- a config that is already on disk still loads, so
	switching this off does not strand the user on defaults.
]]
function Persist.canWrite(store): boolean
	if type(store) ~= "table" then
		return true
	end
	local values = {}
	local ok, keys = pcall(function()
		return store:keys()
	end)
	if ok and type(keys) == "table" then
		for _, path in ipairs(keys) do
			values[path] = store:get(path)
		end
	end
	return Config.canSave(values)
end

function Persist.hasFilesystem(): boolean
	return type(readfile) == "function" and type(writefile) == "function"
end

function Persist.firstExisting(): string?
	if type(isfile) ~= "function" then
		return nil
	end
	local ok, found = pcall(isfile, Persist.FILE)
	if ok and found then
		return Persist.FILE
	end
	for _, name in ipairs(Persist.FALLBACKS) do
		local okFallback, exists = pcall(isfile, name)
		if okFallback and exists then
			return name
		end
	end
	return nil
end

local function defaultsWith(warning: string)
	return {
		values = Config.defaults(),
		warnings = { warning },
		migratedFrom = nil,
	}
end

--[[
	Read the saved config and apply it to `store`.

	Returns the Config.normalize report: { values, warnings, migratedFrom }.
]]
function Persist.load(store)
	if type(readfile) ~= "function" then
		return defaultsWith("no filesystem available; using defaults")
	end

	local name = Persist.firstExisting()
	if name == nil then
		return defaultsWith("no saved config; using defaults")
	end

	local okRead, content = pcall(readfile, name)
	if not okRead or type(content) ~= "string" or content == "" then
		return defaultsWith("could not read " .. name .. "; using defaults")
	end

	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if not okDecode or type(decoded) ~= "table" then
		return defaultsWith(name .. " is not valid JSON; using defaults")
	end

	local report = Config.normalize(decoded)
	store:load(report.values)
	if name ~= Persist.FILE then
		table.insert(report.warnings, "loaded legacy config " .. name)
	end
	return report
end

--[[
	Track whether anything persistable has changed since the last successful save.

	The autosave fires every 8 seconds for the whole session, and the previous
	implementation wrote the file unconditionally: an eight-hour session that was
	opened and never touched still encoded and rewrote an identical config
	thousands of times.

	Only PERSISTABLE paths count. A change to a live key (the pause switch, the
	pill mode) is not going to the file, so it must not schedule a write.

	The tracker starts dirty, because at that point nothing has been saved yet.
]]
function Persist.tracker(store)
	local tracker = { dirty = true }
	tracker.connection = store:subscribeAll(function(path)
		if Config.isPersisted(path) then
			tracker.dirty = true
		end
	end)
	return tracker
end

--[[
	Write the store's schema-declared values to disk.

	The filtering is NOT repeated here: `Config.project` is the single place that
	decides which keys are persistable (schema membership, live-key exclusion),
	and re-deriving that list locally is exactly how the save path can silently
	disagree with the load path -- which is the class of bug this module exists
	to eliminate.

	Pass a `tracker` from Persist.tracker to skip the write when nothing has
	changed. Omitting it forces a write, which is what shutdown wants.

	Returns (ok, err).
]]
function Persist.save(store, tracker)
	if not Persist.canWrite(store) then
		-- Disabled is not a failure: the caller logs a failed save, and a switch
		-- the user turned off must not look like one. Nothing is written and the
		-- tracker is left dirty, so re-enabling saves the pending changes.
		return true
	end

	if type(writefile) ~= "function" then
		return false, "no filesystem available"
	end

	if tracker ~= nil and tracker.dirty ~= true then
		return true
	end

	local flat = {}
	for _, path in ipairs(store:keys()) do
		flat[path] = store:get(path)
	end

	local payload = Store.nest(Config.project(flat))
	payload.version = Config.VERSION

	local okEncode, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not okEncode then
		return false, "encode failed: " .. tostring(encoded)
	end

	local okWrite, err = pcall(writefile, Persist.FILE, encoded)
	if not okWrite then
		return false, "write failed: " .. tostring(err)
	end

	-- Only cleared on a successful write, so a failed save is retried by the next
	-- autosave instead of being silently skipped as "already saved".
	if tracker ~= nil then
		tracker.dirty = false
	end
	return true
end

--[[
	Write the current store into slot `index`.

	Shares the projection with the main save -- there is exactly one place that
	decides what is persistable, and a slot that encoded a different key set
	would be a config file that silently restores a different subset than the
	autosave does.
]]
function Persist.saveSlot(store, index, label): (boolean, string?)
	if not Persist.canWrite(store) then
		return false, "功能存档已禁用"
	end
	if type(writefile) ~= "function" then
		return false, "no filesystem available"
	end
	local name = Persist.slotFile(index)
	if name == nil then
		return false, "slot out of range"
	end

	local flat = {}
	for _, path in ipairs(store:keys()) do
		flat[path] = store:get(path)
	end

	local payload = Store.nest(Config.project(flat))
	payload.version = Config.VERSION
	-- Stamped after projecting so it cannot be dropped as a non-schema key.
	payload.meta = { slotLabel = tostring(label or ("存档 " .. tostring(math.floor(index)))) }

	local okEncode, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not okEncode then
		return false, "encode failed: " .. tostring(encoded)
	end

	local okWrite, err = pcall(writefile, name, encoded)
	if not okWrite then
		return false, "write failed: " .. tostring(err)
	end
	return true
end

--[[
	Load slot `index` into the store.

	Goes through the same Config.normalize as the boot load, so a slot written by
	an older version is migrated and a corrupted one reports a warning instead of
	half-applying.
]]
function Persist.loadSlot(store, index)
	-- NOT gated by `cfg.saveEnabled`: the switch stops WRITES, and the module's
	-- own rule (see `canWrite`) is that reading is never gated. The UI hides the
	-- card while it is off, but a disabled writer must not make a saved profile
	-- unreadable.
	if type(readfile) ~= "function" then
		return nil, "no filesystem available"
	end
	local name = Persist.slotFile(index)
	if name == nil then
		return nil, "slot out of range"
	end

	local okRead, content = pcall(readfile, name)
	if not okRead or type(content) ~= "string" or content == "" then
		return nil, "存档为空或不存在"
	end
	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if not okDecode or type(decoded) ~= "table" then
		return nil, "存档不是有效 JSON"
	end

	local report = Config.normalize(decoded)
	store:load(report.values)
	return report, nil
end

-- The label each slot carries, or nil when the slot is empty.
function Persist.slotLabel(index): string?
	if type(readfile) ~= "function" then
		return nil
	end
	local name = Persist.slotFile(index)
	if name == nil then
		return nil
	end
	local ok, content = pcall(readfile, name)
	if not ok or type(content) ~= "string" or content == "" then
		return nil
	end
	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if not okDecode or type(decoded) ~= "table" then
		return nil
	end
	local meta = decoded.meta
	if type(meta) == "table" and type(meta.slotLabel) == "string" then
		return meta.slotLabel
	end
	return "(未命名)"
end

function Persist.listSlots(): { { index: number, label: string? } }
	local out = {}
	for index = 1, Persist.SLOT_COUNT do
		table.insert(out, { index = index, label = Persist.slotLabel(index) })
	end
	return out
end

return Persist
end

__modules["game/Platforms"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Platforms -- an invisible floor under a held position. Optional.

	A client-side hold does not stop the server from resolving gravity: if the
	server wins a frame the character falls and the next frame snaps it back, so
	it shudders. OFF by default because strict anti-pull anchors the root, and
	all parts are destroyed together with the hold.
]]

local Platforms = {}

local OFFSETS = {
	{ 0, 0, 0 },
	{ -18, 0, -18 },
	{ 18, 0, -18 },
	{ -18, 0, 18 },
	{ 18, 0, 18 },
	{ 0, 0, -18 },
	{ 0, 0, 18 },
	{ -18, 0, 0 },
	{ 18, 0, 0 },
}

local list = {}

function Platforms.ensure(center)
	if typeof(center) ~= "Vector3" then
		return
	end
	for index, offset in ipairs(OFFSETS) do
		local part = list[index]
		if part == nil or part.Parent == nil then
			part = Instance.new("Part")
			part.Name = "_MK_PLATFORM_" .. index
			part.Size = Vector3.new(18, 2, 18)
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 1
			part.Parent = Workspace
			list[index] = part
		end
		part.CFrame = CFrame.new(center + Vector3.new(offset[1], offset[2] - 8, offset[3]))
	end
end

function Platforms.remove()
	for index = #list, 1, -1 do
		local part = list[index]
		if part ~= nil then
			pcall(function()
				part:Destroy()
			end)
		end
		list[index] = nil
	end
end

function Platforms.count()
	local n = 0
	for _, part in ipairs(list) do
		if part ~= nil and part.Parent ~= nil then
			n += 1
		end
	end
	return n
end

return Platforms
end

__modules["core/Attributes"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Attributes -- the names of the attributes this script writes onto instances.

	These strings are a cross-module CONTRACT, which is why they live in one
	place. Nothing in the type system connects the module that writes one to the
	module that reads it back:

	    ui/Kit        writes _MK_Base          (a button's resting colour)
	    ui/Theme      reads  _MK_Base          (recolour without losing hover)
	    game/Combat   writes _MK_Pet / _MK_OriginalSize
	    game/Motion   writes _MK_Offset

	so a rename or a typo on one side fails silently -- the widget simply keeps
	the old theme's colour, the pet check simply re-walks the tree every call.
	Declaring them once makes that a change the analyzer can see.

	Pure data: no Roblox API, no globals, safe to require from anywhere.
]]

export type Names = {
	-- The resting colour of an animated button. Theme.apply rewrites it so that
	-- a later MouseLeave does not restore the previous theme's colour.
	BASE_COLOR: string,
	-- UIListLayout ordering counter, stored per container.
	ORDER: string,
	-- Marks a frame as a card (used by the theme pass).
	CARD: string,
	-- Cached "is this part part of a pet" answer, per part.
	PET: string,
	-- A part's original size, so a client-side resize can be undone.
	ORIGINAL_SIZE: string,
	-- A part's offset from the root, so the model can be resynced as a unit.
	OFFSET: string,
	-- A text object's ORIGINAL TextSize, so the font-scale setting can be
	-- applied repeatedly without compounding (base * scale, never size * scale).
	FONT_BASE: string,
}

local Attributes: Names = {
	BASE_COLOR = "_MK_Base",
	ORDER = "_MK_Order",
	CARD = "_MK_Card",
	PET = "_MK_Pet",
	ORIGINAL_SIZE = "_MK_OriginalSize",
	OFFSET = "_MK_Offset",
	FONT_BASE = "_MK_FontBase",
}

return Attributes
end

__modules["game/Motion"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Motion -- the client half of the anti-pullback kernel. The decision half
	(when to hold, release, retry, give up) is core/Hold and is unit-tested; this
	file only touches the engine: freeze the humanoid state machine (PlatformStand
	+ Physics), anchor the root (strict mode only), zero the velocities and write
	CFrame every frame, and PivotTo the WHOLE model rather than just the root --
	writing only HumanoidRootPart lets the server snap the other parts back (the
	"my real position is here but the model is on the floor" symptom).

	Anti-pull mode comes from the config and is re-read on every begin():
	  off     -- never freeze, never anchor; plain teleporting
	  normal  -- clear velocities and write position, but leave the player mobile
	  strict  -- additionally anchor the root and freeze the state machine
]]

local Hold = require("core/Hold")
local Attributes = require("core/Attributes")
local Platforms = require("game/Platforms")

-- How long a held position must stay stable before it counts as accepted: long
-- enough that a server pull-back (which moves the character within a frame or
-- two) can never qualify, short enough that a normal walk crossing 1.5 seconds
-- produces a fallback point.
local GOOD_AFTER = 1.5
-- How far the character may be from the held position and still count as
-- "sitting where we put it". Generous, because the server's own character
-- controller nudges the root every frame.
local GOOD_TOLERANCE = 2
-- Model-vs-root separation that counts as broken, and the notification throttle.
local DRIFT_LIMIT = 8
local DRIFT_NOTICE_INTERVAL = 12

local Motion = {}
Motion.__index = Motion

export type Options = {
	character: any,
	store: any,
	onLost: ((attempt: number) -> ())?,
	onGiveUp: ((attempt: number) -> ())?,
	--[[
		"May `job` drive the character this frame?", answered by the one place that
		knows every task's priority (core/Scheduler.claim). Injected rather than
		global; nil (no rules installed) means "yes to everyone".
	]]
	claim: ((job: string) -> (boolean, string?))?,
}

function Motion.new(options: Options?)
	local opts: Options = options or {}
	local self = setmetatable({
		character = opts.character,
		store = opts.store,
		onLost = opts.onLost,
		onGiveUp = opts.onGiveUp,
		claim = opts.claim,
		-- The job currently driving the hold, and why it last stood down. Both
		-- exist so "nothing is moving" can be answered instead of guessed.
		owner = nil,
		refusedBy = nil,
		refusals = 0,
		hold = Hold.new(),
		pos = nil,
		get = nil,
		look = nil,
		-- Optional downward gaze added to the look direction; see Motion.apply.
		lookBias = nil,
		mode = "hover",
		anchored = false,
		frozen = false,
		saved = nil,
		safe = nil,
		-- The last HELD position the server demonstrably accepted, and when the
		-- current hold started looking stable. See Motion.tick and safePosition.
		goodPos = nil,
		goodSince = 0,
		-- Drift-watchdog bookkeeping: when we last notified, and how many times.
		lastDriftNotice = 0,
		driftNotices = 0,
		lastApply = 0,
		applies = 0,
		resyncs = 0,
	}, Motion)
	return self
end

function Motion.isActive(self): boolean
	return self.hold:isActive()
end

--[[
	Ask the host whether `job` may drive the character in this frame; `true` when
	no rule is installed. The refusal is REMEMBERED for the read-out. Nothing
	here blocks finish/release/unfreeze: a job must always be able to let go.
]]
function Motion.claim(self, job: string): (boolean, string?)
	local ask = self.claim
	if type(ask) ~= "function" then
		self.owner = job
		self.refusedBy = nil
		return true, nil
	end
	local ok, allowed, other = pcall(ask, job)
	if not ok then
		self.owner = job
		self.refusedBy = nil
		return true, nil
	end
	if allowed == true then
		self.owner = job
		self.refusedBy = nil
		return true, nil
	end
	if type(other) == "string" and other ~= "" then
		self.refusedBy = other
	else
		self.refusedBy = nil
	end
	self.refusals += 1
	return false, self.refusedBy
end

-- Who last took the body, and who it was refused in favour of. Both are for
-- the UI: "没有在动" is unanswerable without them.
function Motion.ownerOf(self): string?
	return self.owner
end

function Motion.refused(self): string?
	return self.refusedBy
end

function Motion.mode(self): string
	return self.mode
end

-- The position currently being held, or nil; callers use it to decide whether a
-- new destination is worth issuing (re-targeting every frame made the chest task
-- thrash in V1007).
function Motion.targetPosition(self)
	return self.pos
end

function Motion.setTarget(self, position, getter)
	if typeof(position) == "Vector3" then
		self.pos = position
	end
	if getter ~= nil then
		self.get = getter
	end
end

-- Where to face, and how far to tilt the gaze downward. `bias` is optional:
-- omitting it leaves whatever the current hold was set to.
function Motion.setLook(self, look, bias)
	self.look = look
	if bias ~= nil then
		self.lookBias = if typeof(bias) == "Vector3" then bias else nil
	end
end

-- Start (or re-aim) a hold. `get` is ALWAYS overwritten, even with nil: leaving
-- a previous dynamic target in place is how a teleport ends up being dragged back
-- to wherever the last combat target was.
function Motion.begin(self, options): boolean
	local opts = options or {}
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	if humanoid == nil or root == nil then
		return false
	end

	-- The body slot: a hold is exclusive (one character, one Motion) but nothing
	-- enforced that, so two subsystems calling `begin` in the same second simply
	-- overwrote each other and the LAST writer won. The job's name comes from the
	-- caller (`job`, defaulting to the mode).
	local job = if type(opts.job) == "string" then opts.job else (opts.mode or "hover")
	local allowed = Motion.claim(self, job)
	if not allowed then
		return false
	end
	-- Remembered so `apply` can re-ask EVERY FRAME (see the claim there): the
	-- body slot only remembers claims made in the current frame, so a hold that
	-- claimed once at `begin` became invisible to `bodyOwner` on the next frame
	-- and any higher-priority task could take the character out from under it.
	self.job = job

	local antiPull = self.store:get("cfg.antiPull") or "normal"
	local mode = opts.mode or "hover"

	self.pos = opts.pos
	self.get = opts.get
	self.look = opts.look
	self.lookBias = opts.lookBias
	self.mode = mode

	local wantsFreeze = opts.freeze
	if wantsFreeze == nil then
		wantsFreeze = Hold.isPersistentMode(mode)
	end
	if antiPull == "off" then
		wantsFreeze = false
	end
	self.frozen = wantsFreeze == true

	self.anchored = self.frozen and antiPull == "strict"
	if opts.anchored ~= nil then
		self.anchored = opts.anchored == true and antiPull == "strict"
	end

	if self.saved == nil then
		-- Snapshot the two properties release() restores. There is deliberately
		-- NO gravity here: `Humanoid.Gravity` does not exist (gravity lives on
		-- Workspace), and nothing in this module changes gravity.
		self.saved = {
			walk = humanoid.WalkSpeed,
			jump = humanoid.JumpPower,
		}
	end

	self.hold:configure({
		verifySeconds = tonumber(self.store:get("cfg.tpVerify")) or nil,
		retries = tonumber(self.store:get("cfg.tpRetry")) or nil,
	})
	self.hold:start(os.clock(), Hold.isPersistentMode(mode))

	if self.frozen then
		pcall(function()
			humanoid.PlatformStand = true
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.AutoRotate = false
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	else
		-- Clear any "cannot move" state a previous hold may have left behind.
		pcall(function()
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			if humanoid.WalkSpeed == 0 then
				humanoid.WalkSpeed = 16
			end
			if humanoid.JumpPower == 0 then
				humanoid.JumpPower = 50
			end
		end)
	end

	if self.store:get("cfg.platform") == true then
		Platforms.ensure(self.pos)
	end

	Motion.apply(self, os.clock())
	return true
end

-- Write the position for this frame.
function Motion.apply(self, now: number): boolean
	if not self.hold:isActive() then
		return false
	end
	-- Re-claim every frame: the slot is per-frame (Scheduler.claim stamps the
	-- current frame), so a claim made once in `begin` stops meaning anything
	-- 16 ms later, and a higher-priority task could write the same character.
	if self.job ~= nil and not Motion.claim(self, self.job) then
		return false
	end
	local entry = self.character:current()
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end

	local target = self.pos
	if self.get ~= nil then
		local ok, value = pcall(self.get)
		if ok and typeof(value) == "Vector3" then
			target = value
		end
	end
	if typeof(target) ~= "Vector3" then
		return false
	end
	self.pos = target

	local cf
	if typeof(self.look) == "Vector3" then
	--[[
		THE DOWNWARD BIAS. CFrame.lookAt(pos, target) with both at the same height
		aims the character HORIZONTALLY, and a punch from that pose travels level
		-- over the target's shoulder. The legacy boss fight hovered above the boss
		and looked down at it, i.e. a 45-degree gaze, which is what makes the
		punch land. `lookBias` is that tilt, added to the unit direction toward the
		target and re-normalised; when the eye is directly above the target the
		horizontal component degenerates to zero and -Z is used instead.
	]]
		local bias = self.lookBias
		if typeof(bias) == "Vector3" then
			local flat = self.look - target
			flat = Vector3.new(flat.X, 0, flat.Z)
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			cf = CFrame.lookAt(target, target + (direction + bias).Unit)
		else
			cf = CFrame.lookAt(target, self.look)
		end
	else
		cf = CFrame.new(target)
	end

	if self.anchored and not root.Anchored then
		pcall(function()
			root.Anchored = true
		end)
	end

	-- Each write is guarded SEPARATELY: these three once shared one pcall, so a
	-- failure on the velocity property skipped the CFrame write -- the only one
	-- that actually holds the player -- and the correction silently vanished for
	-- that frame. The CFrame is written last on purpose: it is authoritative.
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	pcall(function()
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)
	pcall(function()
		root.CFrame = cf
	end)

	if entry ~= nil and entry.PrimaryPart ~= nil then
		pcall(function()
			entry:PivotTo(cf)
		end)
	elseif Motion.drift(self) > 4 then
		Motion.resync(self)
	end

	self.lastApply = now
	self.applies += 1
	return true
end

--[[
	Drift watchdog -- called from a periodic timer, NOT from the frame loop. A
	hold measures its own drift; this covers the gaps between holds. Rate-limited
	notifications because, once the model is separated, the watchdog fires every
	second until it is fixed.
]]
function Motion.watchDrift(self, now: number): boolean
	if self.hold:isActive() then
		-- A hold owns the position and measures drift itself; the watchdog only
		-- covers the gaps between holds.
		return false
	end
	if self.character:isAlive() ~= true then
		return false
	end
	if Motion.drift(self) <= DRIFT_LIMIT then
		return false
	end
	Motion.resync(self)

	if now - self.lastDriftNotice < DRIFT_NOTICE_INTERVAL then
		return true
	end
	self.lastDriftNotice = now
	self.driftNotices += 1
	if self.onDrift ~= nil then
		pcall(self.onDrift, Motion.drift(self), self.driftNotices)
	end
	return true
end

-- How far the rendered model has separated from the root.
function Motion.drift(self): number
	local entry = self.character:current()
	local root = self.character:requireRoot()
	if entry == nil or root == nil then
		return 0
	end
	local reference = entry:FindFirstChild("Head")
		or entry:FindFirstChild("UpperTorso")
		or entry:FindFirstChild("Torso")
		or entry:FindFirstChild("LowerTorso")
	if reference == nil then
		return 0
	end
	local okReference, a = pcall(function()
		return reference.Position
	end)
	local okRoot, b = pcall(function()
		return root.Position
	end)
	if not okReference or not okRoot then
		return 0
	end
	return (a - b).Magnitude
end

-- Pull the whole model back onto the root. This is the fix for a model that has
-- sunk through the floor or is floating: moving the root alone cannot repair it.
function Motion.resync(self): boolean
	local entry = self.character:current()
	local root = self.character:requireRoot()
	if entry == nil or root == nil then
		return false
	end
	local ok, position = pcall(function()
		return root.Position
	end)
	if not ok or typeof(position) ~= "Vector3" then
		return false
	end

	pcall(function()
		if entry.PrimaryPart ~= nil then
			entry:PivotTo(CFrame.new(position))
		else
			for _, part in ipairs(entry:GetDescendants()) do
				if part:IsA("BasePart") then
					local offset = part:GetAttribute(Attributes.OFFSET)
					if offset == nil then
						offset = part.Position - position
						part:SetAttribute(Attributes.OFFSET, offset)
					end
					part.CFrame = CFrame.new(position + offset)
				end
			end
		end
	end)
	self.resyncs += 1
	return true
end

-- Called once per frame from the Runtime's pre-render hook.
function Motion.tick(self, now: number)
	if not self.hold:isActive() then
		return
	end
	if not self.hold:shouldHold(now) then
		Motion.finish(self)
		return
	end

	Motion.apply(self, now)

	if not self.hold:sampleDue(now) then
		return
	end
	local root = self.character:requireRoot()
	if root == nil or typeof(self.pos) ~= "Vector3" then
		return
	end
	local ok, position = pcall(function()
		return root.Position
	end)
	if not ok or typeof(position) ~= "Vector3" then
		return
	end

	local outcome = self.hold:sample(now, (position - self.pos).Magnitude)
	--[[
		Record the held position ONCE THE SERVER HAS ACCEPTED IT: markSafe refuses
		to record while a hold is active (correctly), so a session holding almost
		continuously would otherwise never have a fallback point. The signal is
		"enforced for GOOD_AFTER seconds with a small measured error" -- a rejected
		position cannot satisfy that, because the pull-back moves the character
		immediately and the timer never reaches its threshold.
	]]
	local offset = (position - self.pos).Magnitude
	if offset <= GOOD_TOLERANCE then
		if self.goodSince == 0 then
			self.goodSince = now
		elseif self.goodPos == nil and now - self.goodSince >= GOOD_AFTER then
			self.goodPos = self.pos
		end
	else
		-- The character drifted away from the target: this attempt is not a
		-- validated position, so the clock restarts.
		self.goodSince = 0
		self.goodPos = nil
	end

	if outcome == "retry" then
		if self.onLost ~= nil then
			pcall(self.onLost, self.hold:attempts())
		end
		Motion.apply(self, now)
	elseif outcome == "giveup" then
		if self.onGiveUp ~= nil then
			pcall(self.onGiveUp, self.hold:attempts())
		end
	end
end

-- Release the hold and give control back to the player.
function Motion.finish(self)
	if not self.hold:isActive() then
		return
	end
	self.hold:finish()
	self.get = nil
	-- The published owner dies with the hold too: `ownerOf` kept naming a job that
	-- had already finished, which the read-out showed as "still driven by X".
	self.owner = nil
	self.refusedBy = nil
	-- The held position dies with the hold. Leaving it set made
	-- `targetPosition()` answer "we are still going to the OLD target" forever
	-- after the first completed trip, which is how a loop teleport decided it
	-- had already arrived at the next destination and stopped after one hop.
	self.pos = nil
	self.job = nil
	self.look = nil
	self.lookBias = nil
	Platforms.remove()

	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false
	-- The validated-position clock belongs to ONE hold: a new hold must earn its
	-- own acceptance rather than inheriting the previous one's timer.
	self.goodSince = 0
end

-- Restore the humanoid and unanchor, without requiring an active hold.
function Motion.release(self)
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	local saved = self.saved

	if root ~= nil then
		pcall(function()
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end)
	end
	if humanoid ~= nil then
		pcall(function()
			local walk = if saved ~= nil then saved.walk else nil
			local jump = if saved ~= nil then saved.jump else nil
			humanoid.PlatformStand = false
			humanoid.Sit = false
			humanoid.AutoRotate = true
			humanoid.WalkSpeed = (walk ~= nil and walk > 0) and walk or 16
			humanoid.JumpPower = (jump ~= nil and jump > 0) and jump or 50
			-- No gravity write: `Humanoid.Gravity` does not exist. Gravity lives
			-- on `Workspace`, and this module never changes it.
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

-- The "I cannot move" escape hatch: drop everything and force a clean state.
function Motion.unfreeze(self)
	self.hold:finish()
	self.get = nil
	self.look = nil
	self.lookBias = nil
	-- Same as finish: an unfreeze that kept `pos`/`job` left targetPosition
	-- answering with a destination the character was no longer being taken to.
	self.pos = nil
	self.job = nil
	self.owner = nil
	self.refusedBy = nil
	self.goodSince = 0
	Platforms.remove()
	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false
end

-- Remember a position known to be safe (on the ground, inside the map). Only
-- while no hold is active: a position the server is rejecting is not somewhere
-- to fall back to. This is what cfg.tpFallback returns to.
function Motion.markSafe(self): boolean
	if self.hold:isActive() then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end
	local ok, position = pcall(function()
		return root.Position
	end)
	if not ok or typeof(position) ~= "Vector3" or position.Y < -50 then
		return false
	end
	self.safe = position
	return true
end

--[[
	Where to send the player when a hold is given up on. `safe` (recorded while
	nothing is held) is preferred because the player actually stood there;
	`goodPos` covers a session holding almost continuously, which never runs the
	markSafe timer -- see Motion.tick.
]]
function Motion.safePosition(self)
	if self.safe ~= nil then
		return self.safe
	end
	return self.goodPos
end

function Motion.stats(self)
	return {
		applies = self.applies,
		resyncs = self.resyncs,
		hold = self.hold.stats,
	}
end

return Motion
end

__modules["core/Teleports"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Teleports -- the map's named destinations. Pure data.

	The coordinates were probed in game and are the whole point of the feature, so
	they live in one place with a lookup. Coordinates are plain numbers; the
	adapter converts to Vector3.
]]

local Teleports = {}

export type Entry = {
	name: string,
	x: number,
	y: number,
	z: number,
}

local LIST: { Entry } = {
	{ name = "大厅", x = -0.75, y = 93.61, z = 242.78 },
	{ name = "小岛", x = -32.14, y = 11.51, z = 1904.41 },
	{ name = "冰霜健身房", x = -2623.41, y = 9.99, z = -409.34 },
	{ name = "神话健身房", x = 2250.39, y = 9.99, z = 1072.77 },
	{ name = "永恒健身房", x = -6758.39, y = 9.99, z = -1284.45 },
	{ name = "传奇健身房", x = 4603.40, y = 993.99, z = -3897.44 },
	{ name = "肌肉之王健身房", x = -8625.40, y = 19.99, z = -5730.41 },
	{ name = "丛林健身房", x = -8685.01, y = 8.99, z = 2392.06 },
	{ name = "工业健身房", x = -5496.68, y = 62.04, z = 4927.74 },
	{ name = "超载健身房", x = -3045.30, y = 168.41, z = 4990.69 },
	{ name = "无转盘岛", x = 1952.09, y = 4.00, z = 6179.98 },
	{ name = "熔岩争斗", x = 4472.53, y = 121.90, z = -8848.54 },
	{ name = "沙漠争斗", x = 973.62, y = 18.92, z = -7277.01 },
	{ name = "海滩争斗", x = -1880.89, y = 18.87, z = -6137.75 },
	-- The seasonal gym (the 2026-10 Halloween event calls it "Hallowed Gym"; the
	-- four event bosses live there). APPENDED rather than inserted so every index
	-- a saved config already holds still points at the same destination.
	{ name = "万圣节健身房", x = 5505.53, y = 96.32, z = 5893.50 },
}

Teleports.LIST = LIST

function Teleports.count(): number
	return #LIST
end

function Teleports.labels(): { string }
	local out: { string } = {}
	for _, entry in ipairs(LIST) do
		table.insert(out, entry.name)
	end
	return out
end

function Teleports.byIndex(index: number?): Entry?
	local position = math.floor(tonumber(index) or 0)
	if position < 1 or position > #LIST then
		return nil
	end
	return LIST[position]
end

function Teleports.byName(name: string?): Entry?
	if name == nil then
		return nil
	end
	for _, entry in ipairs(LIST) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

-- The stored index for a display name, defaulting to the first entry so a
-- dropdown can never write an index the loop task cannot resolve.
function Teleports.indexOf(name: string?): number
	for index, entry in ipairs(LIST) do
		if entry.name == name then
			return index
		end
	end
	return 1
end

-- Clamp a stored index into the valid range, so a saved config from a version
-- with a shorter list cannot leave the loop task pointing at nothing.
function Teleports.clampIndex(index: number?): number
	local position = math.floor(tonumber(index) or 1)
	if position < 1 then
		return 1
	end
	if position > #LIST then
		return #LIST
	end
	return position
end

return Teleports
end

__modules["game/Teleport"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Teleport -- stepped movement that survives a server-side distance check.

	    core/Path    decides the waypoints   (pure, tested)
	    core/Timers  paces the hops          (cancellable, counted)
	    this file    writes the CFrames      (the only engine part)

	Why stepping at all: teleporting hundreds of studs in one frame trips the
	server's distance validation, which then snaps the player back. Small hops
	mostly stay under it, while a time budget keeps the trip feeling instant.

	On arrival the movement kernel is armed for a verification window, so the
	first few frames of any residual snap-back are corrected -- then released so
	the player can walk again.
]]

local Path = require("core/Path")
local Teleports = require("core/Teleports")

local Teleport = {}
Teleport.__index = Teleport

export type Options = {
	maxTime: number?,
	interval: number?,
	minStep: number?,
	arc: number?,
	mode: string?,
	-- Force (or forbid) staged pathing for this call, overriding cfg.tpPath.
	path: boolean?,
	get: (() -> any)?,
	hold: boolean?,
	--[[
		Who is moving the character. This module writes CFrames directly
		(`snap`/`pin`) and through `Motion` (`walk`), so it asks the body slot on
		behalf of every caller. Defaults to the names the old code used implicitly
		("tp"/"chest"/"combat"/"boss" by mode).
	]]
	job: string?,
	onLost: ((attempt: number) -> ())?,
	onGiveUp: ((attempt: number) -> ())?,
}

function Teleport.new(context)
	local self = setmetatable({
		character = context.character,
		store = context.store,
		motion = context.motion,
		timers = context.timers,
		handle = nil,
		busy = false,
		-- Job that owns the walk currently in flight, so one loop standing down
		-- cannot cancel a walk another loop legitimately started (both loops
		-- share this single instance).
		walkJob = nil,
		arrivals = 0,
		lastArrival = 0,
		retargets = 0,
	}, Teleport)
	return self
end

function Teleport.isBusy(self): boolean
	return self.busy
end

-- Stop the walk in flight. `job` scopes the cancel: when a DIFFERENT job owns the
-- walk nothing happens, because two teleport loops share one Teleport and an
-- unconditional cancel made toggling one loop kill the other's walk mid-path.
function Teleport.cancel(self, job)
	if job ~= nil and self.walkJob ~= nil and self.walkJob ~= job then
		return
	end
	if self.handle ~= nil then
		self.handle:cancel()
		self.handle = nil
	end
	self.busy = false
	self.walkJob = nil
end

local function moveTo(self, point)
	local entry = self.character:current()
	local root = self.character:requireRoot()
	if root == nil then
		return
	end
	local cf = CFrame.new(point.x, point.y, point.z)
	if entry ~= nil and entry.PrimaryPart ~= nil then
		pcall(function()
			entry:PivotTo(cf)
		end)
	else
		pcall(function()
			root.CFrame = cf
		end)
	end
end

function Teleport._arrive(self, target, options)
	self.arrivals += 1
	self.lastArrival = os.clock()

	-- The model can be left behind by the hops (pets, accessories, limbs), so the
	-- whole thing is snapped back onto the root before the hold begins.
	if self.motion ~= nil then
		self.motion:resync()
	end

	if options.hold == false or self.motion == nil then
		return
	end
	self.motion:begin({
		pos = target,
		mode = options.mode or "tp",
		get = options.get,
		job = options.job or options.mode or "tp",
		onLost = options.onLost,
		onGiveUp = options.onGiveUp,
	})
end

-- Walk to `target`. Returns false if there is no character to move; the walk is
-- asynchronous but cancellable -- starting a second one cancels the first.
function Teleport.walk(self, target, options): boolean
	local opts: Options = options or {}
	if typeof(target) ~= "Vector3" then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end

	--[[
		The body slot, claimed BEFORE anything is cancelled: a walk that is
		refused must not first destroy the walk that legitimately owns the body.
		The hops re-claim as well (in `step`), because the slot only remembers
		claims made in the current frame.
	]]
	local job = if type(opts.job) == "string" and opts.job ~= "" then opts.job else nil
	if job ~= nil and self.motion ~= nil and not self.motion:claim(job) then
		return false
	end

	Teleport.cancel(self)
	self.walkJob = job
	self.retargets += 1

	local from = root.Position
	--[[
		`cfg.tpPath` -- the "分跳传送" switch. Off means "one hop, then arrive" (the
		plan is cut to its final point): the same endpoint, but it can rubber-band
		more, which is what the setting is for. `opts.path` still overrides the
		store because the teleport page's callers pass it explicitly.
	]]
	local staged = opts.path
	if staged == nil then
		staged = self.store:get("cfg.tpPath") ~= false
	end
	local distance = (target - from).Magnitude

	--[[
		`cfg.tpStage` -- "分段传送：长距离先抬高再落点". The equivalent of the
		legacy initial lift is the path's arc, which lifts the midpoint of the hop
		chain; an explicit `opts.arc` still wins.
	]]
	local arc = opts.arc
	if arc == nil then
		if self.store:get("cfg.tpStage") ~= false and distance > 60 then
			arc = 60
		else
			arc = 0
		end
	end

	local plan = Path.plan(
		{ x = from.X, y = from.Y, z = from.Z },
		{ x = target.X, y = target.Y, z = target.Z },
		{
			maxTime = tonumber(opts.maxTime) or tonumber(self.store:get("cfg.tpMaxTime")) or 0.5,
			interval = tonumber(opts.interval) or 0.015,
			minStep = tonumber(opts.minStep) or 22,
			arc = arc,
		}
	)

	-- A single hop: keep only the endpoint, which makes the hop timer below fire
	-- once and then arrive.
	if staged ~= true and distance > 0 then
		plan.points = { plan.points[#plan.points] }
	end

	local interval = tonumber(opts.interval) or 0.015
	local index = 0
	self.busy = true

	local function step()
		-- Each hop asks again: the timer runs outside the scheduler's frame, and
		-- a higher-priority task that took the body since the last hop ends this
		-- walk instead of fighting it for the CFrame.
		if job ~= nil and self.motion ~= nil and not self.motion:claim(job) then
			Teleport.cancel(self)
			return
		end
		index += 1
		local point = plan.points[index]
		if point == nil then
			Teleport.cancel(self)
			Teleport._arrive(self, target, opts)
			return
		end
		moveTo(self, point)
	end

	-- First hop now, remainder on a timer. Doing the first one synchronously means
	-- a short teleport completes within the frame it was requested.
	step()
	if self.busy then
		self.handle = self.timers:every(os.clock(), interval, step, false)
	end
	return true
end

--[[
	A single-frame move: write the position now, once -- for callers that re-issue
	it at a high rate (the loop teleport every 0.025 s, the boss pin every frame).
	Planning a staged path each time would be pure overhead because the next write
	replaces the previous one anyway; this is the "snap" the reference
	implementation does (`hrp.CFrame = CFrame.new(pos)`).

	Any staged walk in flight is cancelled first: it would otherwise keep writing
	the old waypoints between two snaps. `job` names the caller for the body slot.
]]
function Teleport.snap(self, target, job): boolean
	if typeof(target) ~= "Vector3" then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end
	if job ~= nil and self.motion ~= nil then
		local allowed = self.motion:claim(job)
		if not allowed then
			return false
		end
	end
	Teleport.cancel(self)

	--[[
		A motion HOLD would overwrite this write on the next RenderStepped
		(`Motion.apply` rewrites the CFrame to `self.pos` every frame), so a stale
		hold has to go: the callers of `snap` are exactly the ones that own the
		body outright. `finish` is a no-op when no hold is active.
	]]
	if self.motion ~= nil then
		pcall(function()
			self.motion:finish()
		end)
	end

	local entry = self.character:current()
	if entry ~= nil and entry.PrimaryPart ~= nil then
		pcall(function()
			entry:PivotTo(CFrame.new(target))
		end)
	else
		pcall(function()
			root.CFrame = CFrame.new(target)
		end)
	end
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	pcall(function()
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)
	return true
end

--[[
	PIN: write the POSITION AND THE FACING, now, for callers that re-issue it on a
	0.025 s cadence (the boss hover, the kill approach).

	Why next to the motion hold: the hold writes once per RenderStepped and only
	while active, with verify/retry bookkeeping (samples, drift streaks) around it.
	The pin is unconditional and immediate, so "贴上去" cannot be delayed by that
	bookkeeping -- and it sets the ROTATION in the same write, which is what makes
	the punch land on the target instead of over its shoulder.

	`bias` is the downward gaze (Vector3.new(0, -1, 0) = the legacy 45 degrees); a
	nil bias keeps the horizontal aim.
]]
function Teleport.pin(self, target, look, bias, job): boolean
	if typeof(target) ~= "Vector3" then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end
	if job ~= nil and self.motion ~= nil then
		local allowed = self.motion:claim(job)
		if not allowed then
			return false
		end
	end

	local cf
	if typeof(look) == "Vector3" then
		if typeof(bias) == "Vector3" then
			local flat = look - target
			flat = Vector3.new(flat.X, 0, flat.Z)
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			cf = CFrame.lookAt(target, target + (direction + bias).Unit)
		else
			cf = CFrame.lookAt(target, look)
		end
	else
		cf = CFrame.new(target)
	end

	--[[
		ROOT CFrame ONLY -- deliberately no `PivotTo`: pivoting the whole model
		moves every limb and re-seats the assembly, and done 40 times a second it
		fights the humanoid's own state machine and the punch animation while the
		punch is aimed from the ROOT -- which is why punches started missing.
		`Motion.apply` can afford `PivotTo` once per frame to repair a model that
		has come apart; a 0.025 s pin cannot.
	]]
	pcall(function()
		root.CFrame = cf
	end)
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	pcall(function()
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)
	return true
end

function Teleport.stats(self)
	return {
		arrivals = self.arrivals,
		retargets = self.retargets,
		busy = self.busy,
	}
end

-- Walk to a named destination.
function Teleport.goTo(self, name: string?)
	local entry = Teleports.byName(name)
	if entry == nil then
		return false
	end
	return Teleport.walk(self, Vector3.new(entry.x, entry.y, entry.z), {
		mode = "tp",
		arc = 120,
		job = "teleport",
	})
end

--[[
	The muscle-king shortcut: the portal sits above the beach, and arriving straight
	at it drops the player through the map, so the trip is two hops -- high above
	the arena first, then down onto the portal.
]]
function Teleport.goToMuscleKing(self)
	Teleport.walk(self, Vector3.new(-8727.1, 100, -5796.4), { mode = "tp", hold = false, job = "teleport" })
	local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
	local destination = if portal ~= nil
		then portal.Position + Vector3.new(0, -14, 0)
		else Vector3.new(-8727.1, 389.7, -5796.4)
	-- Scheduled rather than slept: the original blocked its coroutine for 0.1s
	-- between the two hops.
	self.timers:after(os.clock(), 0.1, function()
		Teleport.walk(self, destination, { mode = "tp", arc = 200, job = "teleport" })
	end)
	return true
end

function Teleport.install(context)
	local self = Teleport.new(context)
	local store = context.store
	local scheduler = context.scheduler
	--[[
		BOSS OUTRANKS EVERY MOVEMENT FEATURE: 打 Boss > 全图杀戮 > 单独击杀 /
		肌肉之王 > 器械. Both teleport tasks stand down while the boss fight owns
		the body (see the body-slot check inside them). There is no `isBossFight`
		predicate: "a boss model exists" is not "the boss task is moving the
		character", and treating it as one switched the loop off for the session.
	]]
	-- The machine's live phase ("mounting"/"mounted"), injected rather than
	-- reached for: Machine is installed after Teleport, and the loop has to see
	-- a mount the same way it sees a boss -- as something that owns the body.
	local machinePhase = context.machinePhase or function()
		return nil
	end
	-- WHO ELSE IS HOLDING THE BODY: the scheduler's per-frame answer, exposed as a
	-- predicate so this module keeps no dependency on the scheduler.
	local bodyOwner = context.bodyOwner or function()
		return nil
	end
	--[[
		The switch above is not enough on its own: `isBossFight` is "boss.auto is on
		and a boss is alive", true for the whole fight INCLUDING the seconds between
		approaches. The authoritative check is the body slot (whose claim counted
		last frame); the switches are the cheap early-outs.
	]]
	local function foreignOwner(): string?
		local owner = bodyOwner()
		if type(owner) ~= "string" or owner == "" then
			return nil
		end
		return owner
	end

	scheduler:register({
		id = "teleportLoop",
		priority = 80,
		enabled = function()
			if store:get("tp.loop") ~= true then
				return false
			end
			-- Only one thing may drive the position at a time.
			if store:get("tp.autoMK") == true then
				return false
			end
			if store:get("kill.enabled") == true then
				return false
			end
			--[[
				No `isBossFight` gate: it was `boss.auto and Boss.isAlive()`, i.e.
				"a boss model exists on the map", so once a boss spawned anywhere
				the loop switched itself off forever -- a permanent switch
				expressed as a live condition. The arbitration below covers the real
				intent without disabling the loop while the boss task is idle.
			]]
			--[[
				Anything that actually holds the body outranks this loop.
				`tp.autoMK` and `kill.enabled` above are switches; this is the live
				answer, and it is why "循环传送 ignores 优先级" is impossible: a
				chest (430), a boss approach (410), a kill (370) or a machine mount
				(90) that moved the character last frame keeps the body, and the
				loop resumes by itself the frame the other task stops.

				Deliberately "anyone but us" rather than a list of names, so a new
				moving subsystem outranks the loop without being added here.
			]]
			if store:get("machine.enabled") == true then
				local phase = machinePhase()
				if phase == "mounting" or phase == "mounted" then
					return false
				end
			end
			--[[
				"Anyone but us", with NO whitelist: letting "teleport" and
				"machine" through produced the reported "多个循环传送互相挤占". A
				task that claimed the body this frame owns it for this frame, and
				this loop asks again next frame.
			]]
			local owner = foreignOwner()
			if owner ~= nil and owner ~= "teleportLoop" then
				return false
			end
			return true
		end,
		onDisable = function()
			Teleport.cancel(self, "teleportLoop")
		end,
		tick = function(_dt, now)
			--[[
				0.025 s, and a SNAP rather than a staged walk: the old tick
				skipped whenever `farFromCurrent` thought the held position was
				already the destination (always true after the first teleport), so
				the loop idled forever. Re-asserting the destination is what
				"循环传送" means.
			]]
			if now - (self.lastLoop or 0) < 0.025 then
				return
			end
			self.lastLoop = now
			local entry = Teleports.byIndex(store:get("tp.loopIdx"))
			if entry == nil then
				return
			end
			Teleport.snap(self, Vector3.new(entry.x, entry.y, entry.z), "teleportLoop")
		end,
	})

	scheduler:register({
		id = "teleport",
		--[[
			85, above the loop (80) and below the machine (90): the two "keep me
			somewhere" loops used to share 80, so ties were decided by registration
			order and the loop always won. The muscle-king flight is the more
			specific instruction (transport for a named kill), so it outranks the
			generic loop while yielding to the machine, combat and the boss.
		]]
		priority = 85,
		enabled = function()
			if store:get("tp.autoMK") ~= true then
				return false
			end
			--[[
				Live arbitration instead of `isBossFight`: the switch-based gate
				disabled the flight for the whole session as soon as any boss model
				existed. "Do not fight the boss" is what the body slot answers,
				live, every frame.
			]]
			local owner = foreignOwner()
			if owner ~= nil and owner ~= "teleport" then
				return false
			end
			return true
		end,
		onDisable = function()
			Teleport.cancel(self, "teleport")
		end,
		tick = function(_dt, now)
			if now - (self.lastMK or 0) < 0.5 then
				return
			end
			self.lastMK = now
			if Teleport.isBusy(self) then
				return
			end
			local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
			local target = if portal ~= nil
				then portal.Position + Vector3.new(0, -14, 0)
				else Vector3.new(-8727.1, 389.7, -5796.4)
			--[[
				The LIVE position, not the remembered target: comparing against
				`motion:targetPosition()` left the guard false forever after the
				first arrival, so this loop flew exactly once per session. Reading
				the root also covers a server pull-back, a boss fight and a void
				rescue, none of which produce a new hold.
			]]
			local root = self.character:requireRoot()
			local here = if root ~= nil then root.Position else nil
			if typeof(here) ~= "Vector3" or (here - target).Magnitude > 12 then
				Teleport.walk(self, target, { mode = "tp", arc = 200, job = "teleport" })
			end
		end,
	})

	return self
end

return Teleport
end

__modules["game/Tools"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Tools -- finding and equipping the game's tools.

	The matching rules live in core/Keyword (tested); this file only walks a
	character and a backpack. The keyword sets are deliberately loose and
	bilingual because tool names in this game are localised, and they are the
	real names observed in game.
]]

local Keyword = require("core/Keyword")

local Tools = {}

Tools.PUNCH = { "punch", "拳", "fist", "空手", "拳头" }
Tools.DUMBBELL = { "barbell", "dumbbell", "weight", "哑铃", "杠铃" }
Tools.PUSHUP = { "pushup", "push up", "push-up", "俯卧撑" }
Tools.HANDSTAND = { "handstand", "hand stand", "hand-stand", "倒立" }
Tools.SITUP = { "situp", "sit up", "sit-up", "仰卧起坐" }

function Tools.equipped(character, keywords)
	if character == nil then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and Keyword.matches(child.Name, keywords) then
			return child
		end
	end
	return nil
end

function Tools.inBackpack(player, keywords)
	if player == nil then
		return nil
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack == nil then
		return nil
	end
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and Keyword.matches(child.Name, keywords) then
			return child
		end
	end
	return nil
end

--[[
	Equip a matching tool. Returns true when the tool is (now) held.

	The humanoid is the only thing that can equip, and it may be gone by the time
	this runs, so every step is guarded.

	The answer is a READ-BACK, not the pcall result: `EquipTool` can return
	without raising and still not put the tool in hand (dead character, tool
	consumed between the scan and the call, game-side cooldown).
]]
function Tools.equip(character, humanoid, player, keywords): boolean
	if Tools.equipped(character, keywords) ~= nil then
		return true
	end
	if humanoid == nil or humanoid.Parent == nil then
		return false
	end
	local tool = Tools.inBackpack(player, keywords)
	if tool == nil then
		return false
	end
	pcall(function()
		humanoid:EquipTool(tool)
	end)
	return Tools.equipped(character, keywords) ~= nil
end

return Tools
end

__modules["core/Duel"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Duel -- "can we actually kill this player?" Pure.

	The user's rule for 全图杀戮: 会通过计算我方的力量和耐力和对方的力量和耐力来计算
	是否打得过。如果打不过直接跳过……如果我方力量跟对方的耐力相差过大，那也跳过

	Two independent skip conditions, both from the same four numbers. 耐力 equals
	HP and a punch's damage scales with 力量, so the fight is a RACE of hit counts:

	    we need      theirDurability / ourStrength   punches
	    they need    ourDurability   / theirStrength punches

	Whoever needs fewer wins; if THEY need markedly fewer, we lose -- skip. And
	even if we win the race, a target whose durability is far above our strength
	takes an absurd number of punches, which is the separate `maxHits` cap.

	Everything is a plain ratio, so the game's damage formula never has to be
	known exactly: the absolute scale cancels out of the race, and the only number
	with a unit is `maxHits`, which the user can tune.

	MISSING DATA NEVER SKIPS: if our strength, their durability or their strength
	cannot be read, `winnable` answers true with a reason of nil -- refusing to
	attack because a leaderboard value did not load would make the feature look
	broken.
]]

local Duel = {}

export type Side = {
	strength: number?,
	durability: number?,
}

export type Options = {
	maxHits: number?,
	--[[
		HOW CLEAR the loss has to be before we skip. A bare `theirHits <= ourHits`
		fires on a tie and on a 1% difference, and the two leaderboard numbers are
		not guaranteed to be on the same scale (one may be a damage figure and the
		other a health figure with different bases). Requiring the target to be
		this many times better turns "we would probably lose" into "we would
		certainly lose" -- which is what the user actually asked for.
	]]
	margin: number?,
}

export type Verdict = {
	winnable: boolean,
	reason: string?,
	-- Diagnostics for the UI: how many punches each side would need, when known.
	ourHits: number?,
	theirHits: number?,
}

Duel.DEFAULT_MAX_HITS = 30
Duel.DEFAULT_MARGIN = 2

local function positive(value: number?): number?
	if value == nil or value ~= value or value <= 0 then
		return nil
	end
	return value
end

-- A hit count safe to render with %d. `string.format("%d", 1e300)` raises
-- "number has no integer representation", and these numbers are ratios of
-- leaderboard values that can be arbitrarily large, so the message itself could
-- throw inside the kill loop.
local function hits(value: number): number
	if value ~= value or value <= 0 then
		return 0
	end
	if value > 1e15 then
		return 1e15
	end
	return math.ceil(value)
end

function Duel.verdict(mine: Side, theirs: Side, options: Options?): Verdict
	local opts: Options = options or {}
	local maxHits = opts.maxHits or Duel.DEFAULT_MAX_HITS
	--[[
		A non-positive cap means "do not cap at all", not "cap at one punch".

		`ourHits = theirDurability / myStrength` assumes the game's Durability is
		in the same unit as one punch of Strength. If it is not, the number is
		arbitrary and a low cap silently skips perfectly good targets ("误判，很多
		人不打"). The slider therefore reaches 0, and 0 must mean unlimited.
	]]
	if maxHits <= 0 then
		maxHits = math.huge
	end

	local myStrength = positive(mine.strength)
	local theirDurability = positive(theirs.durability)
	local theirStrength = positive(theirs.strength)

	-- No usable numbers on either side: not judged, so not skipped.
	if myStrength == nil or theirDurability == nil then
		return { winnable = true, reason = nil, ourHits = nil, theirHits = nil }
	end

	local ourHits = theirDurability / myStrength
	-- Their durability is known but their strength is not: the race cannot be
	-- judged, so only the "too many hits" cap applies.
	if theirStrength == nil then
		if ourHits > maxHits then
			return {
				winnable = false,
				reason = string.format("打不死：要 %d 拳（力量 %s vs 耐力 %s）",
					hits(ourHits), tostring(math.floor(myStrength)), tostring(math.floor(theirDurability))),
				ourHits = ourHits,
				theirHits = nil,
			}
		end
		return { winnable = true, reason = nil, ourHits = ourHits, theirHits = nil }
	end

	local myDurability = positive(mine.durability)
	if myDurability == nil then
		-- Our own HP is unreadable: we cannot say they would win, so only the
		-- hit-count cap decides.
		if ourHits > maxHits then
			return {
				winnable = false,
				reason = string.format("打不死：要 %d 拳", hits(ourHits)),
				ourHits = ourHits,
				theirHits = nil,
			}
		end
		return { winnable = true, reason = nil, ourHits = ourHits, theirHits = nil }
	end

	local theirHits = myDurability / theirStrength
	local margin = opts.margin or Duel.DEFAULT_MARGIN
	if margin < 1 then
		margin = 1
	end
	-- A CLEAR loss, not a tie and not a coin flip: they must need fewer punches
	-- by a factor of `margin` before we refuse to fight. See Options.margin.
	if theirHits * margin <= ourHits then
		return {
			winnable = false,
			reason = string.format("打不过：他会先打死你（他 %d 拳 / 你 %d 拳）",
				math.ceil(theirHits), math.ceil(ourHits)),
			ourHits = ourHits,
			theirHits = theirHits,
		}
	end
	if ourHits > maxHits then
		return {
			winnable = false,
			reason = string.format("打不死：要 %d 拳（超过上限 %d）", math.ceil(ourHits), maxHits),
			ourHits = ourHits,
			theirHits = theirHits,
		}
	end

	return { winnable = true, reason = nil, ourHits = ourHits, theirHits = theirHits }
end

return Duel
end

__modules["core/SafeZones"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	SafeZones -- where a player cannot be killed. Pure.

	The rule for 全图杀戮: the search itself is unlimited, but a player inside
	万圣节健身房 or on 小岛 directly cannot be killed and is skipped.

	Two areas, stated as DATA rather than as a radius buried in the kill loop:

	    万圣节健身房 (Hallowed Gym)  the seasonal area -- a different map entirely,
	                                and the arena's own damage rules do not apply
	                                outside it
	    小岛 (the island)            the beach area at the same coordinates the
	                                teleport list calls 小岛 and the gym list calls
	                                海滩

	TWO WAYS TO KNOW, and the union of them is deliberate:

	  * the game's own NAME -- `currentMap` is a StringValue the game publishes,
	    and each character carries an `InHalloweenArena` attribute. That is an
	    answer from the game, not a guess.
	  * the DISTANCE from the two known centres, as the fallback: a remote
	    player's `currentMap` is not guaranteed to replicate to us, so relying on
	    the name alone would silently stop protecting anyone.
]]

local SafeZones = {}

export type Vec3 = { x: number, y: number, z: number }

-- The protected areas, by the coordinates this project already uses everywhere
-- else (core/Teleports, core/MachinePlan).
--
-- Typed LOCALS rather than annotated field assignments: `SafeZones.AREAS: T = {}`
-- is not valid Luau -- an annotation is only allowed on a declaration.
--
-- THE BOSS ARENA IS NOT HERE, deliberately: it is a folder whose position only
-- the engine knows, so the adapter computes its centre and passes it in as an
-- EXTRA area (see areaAt / isProtected).
export type Area = {
	name: string,
	label: string,
	x: number,
	y: number,
	z: number,
	radius: number,
}

local AREAS: { Area } = {
	{ name = "hallowedGym", label = "万圣节健身房", x = 5505.53, y = 96.32, z = 5893.50, radius = 320 },
	{ name = "island", label = "小岛", x = -32.14, y = 11.51, z = 1904.41, radius = 260 },
}

-- Name fragments that mean "this is a protected area".
--
-- DELIBERATELY NARROW. Accepting "island", "beach" or "arena"/"竞技场" skipped
-- too many players (有很多人异常打不到): a map string that merely contains one
-- of those words is not an area where damage is disabled, and a false positive
-- silently removes a player from the kill list. The island and the boss arena
-- are matched by COORDINATES and by the character attribute instead.
local KEYWORDS: { string } = {
	"hallowed",
	"halloween",
	"万圣节",
}

SafeZones.AREAS = AREAS
SafeZones.KEYWORDS = KEYWORDS

function SafeZones.matches(mapName: string?): boolean
	if mapName == nil or mapName == "" then
		return false
	end
	local lowered = string.lower(mapName)
	for _, keyword in ipairs(SafeZones.KEYWORDS) do
		if string.find(lowered, string.lower(keyword), 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- Which area (if any) is this position inside? nil when it is in the open world.
-- `extra` carries the areas only the caller can compute (the boss arena's centre
-- comes from `Workspace.Events.BossArena`) and is checked the same way.
function SafeZones.areaAt(position: Vec3?, extra: { Area }?): string?
	if position == nil then
		return nil
	end
	for _, area in ipairs(AREAS) do
		local dx, dy, dz = position.x - area.x, position.y - area.y, position.z - area.z
		if math.sqrt(dx * dx + dy * dy + dz * dz) <= area.radius then
			return area.name
		end
	end
	if extra ~= nil then
		for _, area in ipairs(extra) do
			local dx, dy, dz = position.x - area.x, position.y - area.y, position.z - area.z
			if math.sqrt(dx * dx + dy * dy + dz * dz) <= area.radius then
				return area.name
			end
		end
	end
	return nil
end

-- Should this candidate be skipped? `mapName` is the game's own name for where
-- the player is (nil when not readable), `inArena` is the character's
-- `InHalloweenArena` attribute, `position` is where the player actually is, and
-- `extra` are the runtime areas (see areaAt).
function SafeZones.isProtected(
	position: Vec3?,
	mapName: string?,
	inArena: boolean?,
	extra: { Area }?
): boolean
	if inArena == true then
		return true
	end
	if SafeZones.matches(mapName) then
		return true
	end
	return SafeZones.areaAt(position, extra) ~= nil
end

-- A label for the UI/log, or nil when the area is unknown.
function SafeZones.labelFor(position: Vec3?, mapName: string?, extra: { Area }?): string?
	if SafeZones.matches(mapName) then
		return "安全区"
	end
	local area = SafeZones.areaAt(position, extra)
	if area == nil then
		return nil
	end
	for _, entry in ipairs(AREAS) do
		if entry.name == area then
			return entry.label
		end
	end
	if extra ~= nil then
		for _, entry in ipairs(extra) do
			if entry.name == area then
				return entry.label
			end
		end
	end
	return area
end

return SafeZones
end

__modules["core/TargetLock"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	TargetLock -- how long we may keep attacking the same player, and who we have
	given up on. Pure.

	The user's report, and the two rules it implies: 老是执着于打一个人……应该有一个
	超时机制，就是如果超时 10 秒没打过，那就给它跳过.

	Step one is a TIMEOUT: a lock older than `timeout` is dropped, because a target
	we have been hitting for ten seconds without killing is either out of reach,
	out-healing us, or protected -- and the loop should try somebody else.

	Step two is what makes that mean anything: a SKIP MEMORY. Dropping a lock
	alone changes nothing, because the very next scan picks the same player again
	(they were the nearest) and the loop rotates between two candidates forever.
	So a timed-out target is remembered with an expiry and is not considered
	again until then.

	Deliberately separate from core/Targeting (which decides WHO, given the
	candidates) and from the adapter (which knows what "still valid" means): this
	is only the bookkeeping over time, which is what makes it testable.
]]

local TargetLock = {}
TargetLock.__index = TargetLock

export type Options = {
	-- How long one target may hold the lock before we move on.
	timeout: number?,
	-- How long a timed-out target stays out of the candidate pool.
	skipSeconds: number?,
}

export type Verdict = {
	-- "keep"    -- stay on this target
	-- "timeout" -- held too long; the lock is dropped and the target skipped
	-- "invalid" -- the caller said it is no longer attackable; lock dropped
	action: string,
	reason: string,
	id: string?,
}

export type TargetLock = {
	_timeout: number,
	_skipSeconds: number,
	_id: string?,
	_lockedAt: number,
	_skips: { [string]: number },
	_timeouts: number,
	status: (TargetLock) -> { id: string?, held: number, timeouts: number, skipped: number },
	configure: (TargetLock, Options?) -> (),
	lock: (TargetLock, string?, number) -> (),
	release: (TargetLock) -> (),
	target: (TargetLock) -> string?,
	held: (TargetLock, number) -> number,
	step: (TargetLock, number, boolean) -> Verdict,
	skip: (TargetLock, string?, number) -> (),
	unskip: (TargetLock, string?) -> (),
	isSkipped: (TargetLock, string?, number) -> boolean,
	skipCount: (TargetLock, number) -> number,
	skippedIds: (TargetLock, number) -> { string },
	clear: (TargetLock) -> (),
}

TargetLock.DEFAULT_TIMEOUT = 10
TargetLock.DEFAULT_SKIP = 60

local function clampNumber(value: number?, fallback: number, low: number, high: number): number
	local resolved = value or fallback
	if resolved ~= resolved then
		resolved = fallback
	end
	if resolved < low then
		return low
	end
	if resolved > high then
		return high
	end
	return resolved
end

local function prune(self: TargetLock, now: number)
	for id, until_ in pairs(self._skips) do
		if until_ <= now then
			self._skips[id] = nil
		end
	end
end

function TargetLock.new(options: Options?): TargetLock
	local opts: Options = options or {}
	local self = setmetatable({
		_timeout = clampNumber(opts.timeout, TargetLock.DEFAULT_TIMEOUT, 0.5, 3600),
		_skipSeconds = clampNumber(opts.skipSeconds, TargetLock.DEFAULT_SKIP, 0, 86400),
		_id = nil,
		_lockedAt = 0,
		_skips = {},
		_timeouts = 0,
	}, TargetLock)
	return (self :: any) :: TargetLock
end

function TargetLock.configure(self: TargetLock, options: Options?)
	local opts: Options = options or {}
	self._timeout = clampNumber(opts.timeout, self._timeout, 0.5, 3600)
	self._skipSeconds = clampNumber(opts.skipSeconds, self._skipSeconds, 0, 86400)
end

-- Take (or keep) the lock.
--
-- The clock is NOT restarted when the same id is locked again: the caller may
-- re-select the same target on every scan, and restarting the clock each time
-- would mean the timeout never fires -- exactly the "执着于打一个人" it exists to
-- end.
function TargetLock.lock(self: TargetLock, id: string?, now: number)
	if id == nil or id == "" then
		TargetLock.release(self)
		return
	end
	if self._id ~= id then
		self._id = id
		self._lockedAt = now
	end
end

function TargetLock.release(self: TargetLock)
	self._id = nil
	self._lockedAt = 0
end

function TargetLock.target(self: TargetLock): string?
	return self._id
end

function TargetLock.held(self: TargetLock, now: number): number
	if self._id == nil then
		return 0
	end
	return math.max(0, now - self._lockedAt)
end

-- One frame's decision about the current lock. `valid` is the caller's answer to
-- "is this still attackable right now" (present, alive, not a friend). An invalid
-- target is dropped WITHOUT being skipped: it is gone or dead, so there is
-- nothing to remember.
function TargetLock.step(self: TargetLock, now: number, valid: boolean): Verdict
	local id = self._id
	if id == nil then
		return { action = "keep", reason = "无锁定", id = nil }
	end
	if valid ~= true then
		self._id = nil
		self._lockedAt = 0
		return { action = "invalid", reason = "目标已不可攻击", id = id }
	end
	if now - self._lockedAt > self._timeout then
		self._id = nil
		self._lockedAt = 0
		TargetLock.skip(self, id, now)
		self._timeouts += 1
		return { action = "timeout", reason = "超时未击杀，换下一个目标", id = id }
	end
	return { action = "keep", reason = "", id = id }
end

-- Put a target out of consideration for `skipSeconds`.
function TargetLock.skip(self: TargetLock, id: string?, now: number)
	if id == nil or id == "" or self._skipSeconds <= 0 then
		return
	end
	self._skips[id] = now + self._skipSeconds
end

-- Forget a skip.
--
-- `step` skips on timeout, but a timeout is only evidence of a BAD TARGET when
-- something was actually thrown at it. Combat calls this when the lock expired
-- without a single punch: an unreachable target was being blacklisted for
-- `kill.targetSkip` seconds, and enough of those drained the whole candidate
-- list ("很多人不打").
function TargetLock.unskip(self: TargetLock, id: string?)
	if id == nil or id == "" then
		return
	end
	self._skips[id] = nil
end

function TargetLock.isSkipped(self: TargetLock, id: string?, now: number): boolean
	if id == nil then
		return false
	end
	local until_ = self._skips[id]
	if until_ == nil then
		return false
	end
	if until_ <= now then
		self._skips[id] = nil
		return false
	end
	return true
end

function TargetLock.skipCount(self: TargetLock, now: number): number
	prune(self, now)
	local count = 0
	for _ in pairs(self._skips) do
		count += 1
	end
	return count
end

function TargetLock.skippedIds(self: TargetLock, now: number): { string }
	prune(self, now)
	local out: { string } = {}
	for id in pairs(self._skips) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function TargetLock.clear(self: TargetLock)
	table.clear(self._skips)
	TargetLock.release(self)
end

function TargetLock.status(self: TargetLock)
	local skipped = 0
	for _ in pairs(self._skips) do
		skipped += 1
	end
	return {
		id = self._id,
		held = if self._id == nil then 0 else -1,
		timeouts = self._timeouts,
		skipped = skipped,
	}
end

return TargetLock
end

__modules["game/Pets"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Pets -- presets, the shop, eggs and the fortune wheel.

	Preset application is executed one step per tick by a timer instead of a
	task.spawn'd loop with task.wait between calls: it can be cancelled, it shows
	up in the scheduler's accounting, and a "preset names pets you do not own" can
	be refused instead of stripping every pet the player has.

	Every remote goes through a named channel, so the pet operations have their
	own rates and their own counters instead of sharing one global valve.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetPlan = require("core/PetPlan")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")

local Pets = {}
Pets.__index = Pets

Pets.PRESET_KEYS = { "train", "rebirth", "kill", "boss" }

local STEP_INTERVAL = 0.1
local UNEQUIP_CAP = 60
local BUY_INTERVAL = 0.6
local EGG_INTERVAL = 0.5
local WHEEL_INTERVAL = 1

function Pets.new(context)
	local self = setmetatable({
		store = context.store,
		net = context.net,
		scheduler = context.scheduler,
		timers = context.timers,
		character = context.character,
		notify = context.notify or function() end,
		activeType = nil,
		sequence = nil,
		sequenceHandle = nil,
		equipped = 0,
		pending = nil,
		pendingAt = 0,
		-- Last preset key we warned about being empty, so `scheduleSwap` (called
		-- every frame while a task is busy) does not spam the toast stack.
		lastEmptyWarned = nil,
		lastBuy = 0,
		lastEgg = 0,
		lastWheel = 0,
		bought = 0,
		eggs = 0,
		spins = 0,
	}, Pets)
	return self
end

local function player()
	return Players.LocalPlayer
end

function Pets.petsFolder(self)
	local user = player()
	if user == nil then
		return nil
	end
	return user:FindFirstChild("petsFolder")
end

-- Flattened instance names in discovery order, for farming mode.
function Pets.ownedNames(self)
	local names = {}
	local folder = Pets.petsFolder(self)
	if folder == nil then
		return names
	end
	for _, group in ipairs(folder:GetChildren()) do
		if group:IsA("Folder") then
			for _, pet in ipairs(group:GetChildren()) do
				table.insert(names, pet.Name)
			end
		end
	end
	return names
end

function Pets.ownedCounts(self)
	local counts = {}
	local folder = Pets.petsFolder(self)
	if folder == nil then
		return counts
	end
	for _, group in ipairs(folder:GetChildren()) do
		if group:IsA("Folder") then
			for _, pet in ipairs(group:GetChildren()) do
				counts[pet.Name] = (counts[pet.Name] or 0) + 1
			end
		end
	end
	return counts
end

function Pets.unequipAll(self)
	local folder = Pets.petsFolder(self)
	local remote = Remotes.equipPet()
	if folder == nil or remote == nil then
		return 0
	end
	local now = os.clock()
	local sent = 0
	for _, group in ipairs(folder:GetChildren()) do
		if group:IsA("Folder") then
			for _, pet in ipairs(group:GetChildren()) do
				if sent >= UNEQUIP_CAP then
					break
				end
				self.net:send("petop", now, "unequipPet", pet)
				sent += 1
			end
		end
	end
	return sent
end

-- Equip the index-th owned copy of `name`.
function Pets.equip(self, name, index)
	local folder = Pets.petsFolder(self)
	if folder == nil or Remotes.equipPet() == nil then
		return false
	end
	local seen = 0
	for _, group in ipairs(folder:GetChildren()) do
		if group:IsA("Folder") then
			for _, pet in ipairs(group:GetChildren()) do
				if pet.Name == name then
					seen += 1
					if seen == index then
						return self.net:send("petop", os.clock(), "equipPet", pet)
					end
				end
			end
		end
	end
	return false
end

function Pets.cancelSequence(self)
	if self.sequenceHandle ~= nil then
		self.sequenceHandle:cancel()
		self.sequenceHandle = nil
	end
	self.sequence = nil
end

function Pets.stepSequence(self, key)
	local sequence = self.sequence
	if sequence == nil then
		Pets.cancelSequence(self)
		return
	end

	sequence.index += 1
	local step = sequence.steps[sequence.index]
	if step == nil then
		Pets.cancelSequence(self)
		self.notify(string.format("预设 [%s] 装备 %d 只", key, self.equipped), "info")
		return
	end

	if step.kind == "unequip" then
		Pets.unequipAll(self)
	elseif step.kind == "equip" then
		if Pets.equip(self, step.name, step.index) then
			self.equipped += 1
		end
	end
end

-- Apply a saved preset, one remote call per tick. Returns false when there is
-- nothing sensible to do, including a preset whose pets the player does not own.
function Pets.applyPreset(self, key): boolean
	local preset = self.store:get("petPreset." .. key)
	local plan = PetPlan.build(preset, Pets.ownedCounts(self))

	if plan.unusable then
		self.notify(
			string.format("预设 [%s] 里没有一只是你拥有的，已跳过（否则会把当前宠物全卸掉）", key),
			"warn"
		)
		return false
	end
	--[[
		Distinguish "this preset is empty" (never saved) from "this preset has
		nothing usable" (the game moved on) -- both used to return false silently
		and they mean different things to the user.
	]]
	if plan.total == 0 and plan.unequipFirst then
		local stored = self.store:get("petPreset." .. key)
		if type(stored) == "table" and #stored == 0 then
			self.notify(string.format("预设 [%s] 为空，未做任何改动", key), "warn")
		else
			self.notify(string.format("预设 [%s] 无可用配置，未做任何改动", key), "warn")
		end
		return false
	end
	if #plan.missing > 0 then
		self.notify(string.format("预设 [%s] 缺少：%s", key, table.concat(plan.missing, "、")), "warn")
	end

	Pets.cancelSequence(self)
	self.activeType = key
	self.equipped = 0
	self.sequence = { steps = PetPlan.steps(plan), index = 0 }

	self.sequenceHandle = self.timers:every(os.clock(), STEP_INTERVAL, function()
		Pets.stepSequence(self, key)
	end, true)
	return true
end

--[[
	The auto-switch request: apply `key` after `delay` seconds, if it is different
	from what is already active. Both skips below are reported rather than silent,
	because from outside they look identical to "the feature is broken":

	  * an empty preset: the request is dropped and any previous preset stays on;
	  * a re-request inside the delay window: `pendingAt` is re-armed on every
	    call (that is what the delay is for), but a key change genuinely replaces
	    the earlier request.
]]
function Pets.scheduleSwap(self, key, delay)
	if self.store:get("petPreset.autoSwitch") ~= true then
		return
	end
	if self.activeType == key then
		return
	end
	local preset = self.store:get("petPreset." .. key)
	if type(preset) ~= "table" or #preset == 0 then
		-- Only report on an actual change of intent, not on every frame that the
		-- task stays busy with an empty preset configured.
		if self.pending ~= key and self.lastEmptyWarned ~= key then
			self.lastEmptyWarned = key
			self.notify(string.format("自动换宠：预设 [%s] 为空，已跳过", key), "warn")
		end
		return
	end
	self.lastEmptyWarned = nil

	if self.pending ~= nil and self.pending ~= key then
		self.notify(string.format("自动换宠：改为切换到预设 [%s]", key), "info")
	end
	self.pending = key
	self.pendingAt = os.clock() + (delay or 0)
end

function Pets.tickSwap(self, now)
	local key = self.pending
	if key == nil or now < self.pendingAt then
		return
	end
	self.pending = nil
	Pets.applyPreset(self, key)
end

function Pets.activePreset(self)
	return self.activeType
end

function Pets.clearActiveType(self)
	self.activeType = nil
end

-- True while a preset or farming equip sequence is still running.
function Pets.isBusy(self): boolean
	return self.sequenceHandle ~= nil
end

-- Equip the first N pets the player owns, for farming. Shares the step machinery
-- with preset application, so it is cancellable and paced the same way.
function Pets.equipFarming(self, max): boolean
	local plan = PetPlan.farming(Pets.ownedNames(self), max)
	if plan.unusable then
		return false
	end
	Pets.cancelSequence(self)
	self.equipped = 0
	self.sequence = { steps = PetPlan.steps(plan), index = 0 }
	self.sequenceHandle = self.timers:every(os.clock(), STEP_INTERVAL, function()
		Pets.stepSequence(self, "farming")
	end, true)
	return true
end

function Pets.shopFolder()
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local runtime = shared and shared:FindFirstChild("runtime")
	return runtime and runtime:FindFirstChild("cPetShopFolder")
end

function Pets.shopList()
	local names = {}
	local folder = Pets.shopFolder()
	if folder ~= nil then
		for _, item in ipairs(folder:GetChildren()) do
			table.insert(names, item.Name)
		end
	end
	table.sort(names)
	return names
end

function Pets.buySelected(self)
	local name = self.store:get("pet.selected")
	if type(name) ~= "string" or name == "" then
		return false
	end
	local remote = Remotes.petShop()
	local folder = Pets.shopFolder()
	if remote == nil or folder == nil then
		return false
	end
	local pet = folder:FindFirstChild(name)
	if pet == nil then
		return false
	end
	local sent = self.net:send("petbuy", os.clock(), pet)
	if sent then
		self.bought += 1
	end
	return sent
end

function Pets.dropEgg(self, now)
	local user = player()
	if user == nil then
		return 0
	end
	local character = self.character:current()
	local backpack = user:FindFirstChild("Backpack")
	local egg = (character ~= nil and character:FindFirstChild("Protein Egg"))
		or (backpack ~= nil and backpack:FindFirstChild("Protein Egg"))
	if egg == nil then
		return 0
	end
	local batch = math.max(1, math.floor(tonumber(self.store:get("pet.eggBatch")) or 10))
	local sent = self.net:burst("egg", now, batch, "proteinEgg", egg)
	self.eggs += sent
	return sent
end

function Pets.spinWheel(self, now)
	local remote = Remotes.wheel()
	if remote == nil then
		return false
	end
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local catalogs = shared and shared:FindFirstChild("catalogs")
	local chances = catalogs and catalogs:FindFirstChild("fortuneWheelChances")
	local wheel = chances and chances:FindFirstChild("Fortune Wheel")
	if wheel == nil then
		return false
	end
	local sent = self.net:send("wheel", now, "openFortuneWheel", wheel)
	if sent then
		self.spins += 1
	end
	return sent
end

-- The pet models currently attached to the player, by name. Equipped pets are
-- published as Models under Workspace.<playerName> carrying an `equippedSlot`
-- StringValue.
function Pets.equippedModels(self)
	local out = {}
	local user = player()
	if user == nil then
		return out
	end
	local own = Workspace:FindFirstChild(user.Name)
	if own == nil then
		return out
	end
	for _, child in ipairs(own:GetChildren()) do
		if child:IsA("Model") then
			local slot = child:FindFirstChild("equippedSlot")
			if slot ~= nil and slot:IsA("StringValue") and slot.Value ~= "" then
				table.insert(out, child.Name)
			end
		end
	end
	return out
end

-- Snapshot what is equipped into a preset, preserving first-seen order and
-- collapsing duplicates into counts.
function Pets.savePreset(self, key): number
	local counts = {}
	local order = {}
	for _, name in ipairs(Pets.equippedModels(self)) do
		if counts[name] == nil then
			counts[name] = 0
			table.insert(order, name)
		end
		counts[name] += 1
	end

	local preset = {}
	for _, name in ipairs(order) do
		table.insert(preset, { name = name, count = counts[name] })
	end
	self.store:set("petPreset." .. key, preset)
	self.activeType = nil
	return #preset
end

function Pets.presetCount(self, key): number
	local preset = self.store:get("petPreset." .. key)
	if type(preset) ~= "table" then
		return 0
	end
	return #preset
end

function Pets.clearPreset(self, key)
	self.store:set("petPreset." .. key, {})
	self.activeType = nil
end

function Pets.stats(self)
	return {
		activeType = self.activeType,
		equipped = self.equipped,
		pending = self.pending,
		bought = self.bought,
		eggs = self.eggs,
		spins = self.spins,
	}
end

function Pets.install(context)
	local self = Pets.new(context)
	local store = self.store

	-- Pet operations are chained (unequip, then equip, then equip...) so the
	-- channel needs a queue: dropping one would leave the preset half applied.
	self.net:addChannel("petop", GameNet.senderFor(function()
		return Remotes.equipPet()
	end), { rate = 12, burst = 8, queue = 64 })

	self.net:addChannel("petbuy", GameNet.senderFor(function()
		return Remotes.petShop()
	end), { rate = 4, burst = 2, queue = 4 })

	self.net:addChannel("egg", GameNet.senderFor(function()
		return Remotes.muscle()
	end), { rate = 20, burst = 5, queue = 0 })

	self.net:addChannel("wheel", GameNet.senderFor(function()
		return Remotes.wheel()
	end), { rate = 2, burst = 1, queue = 1 })

	self.scheduler:register({
		id = "petSwap",
		priority = 60,
		enabled = function()
			return self.pending ~= nil
		end,
		tick = function(_dt, now)
			Pets.tickSwap(self, now)
		end,
	})

	self.scheduler:register({
		id = "petbuy",
		priority = 40,
		enabled = function()
			return store:get("pet.autoBuy") == true and (store:get("pet.selected") or "") ~= ""
		end,
		tick = function(_dt, now)
			if now - self.lastBuy < BUY_INTERVAL then
				return
			end
			self.lastBuy = now
			Pets.buySelected(self)
		end,
	})

	self.scheduler:register({
		id = "egg",
		priority = 40,
		enabled = function()
			return store:get("pet.autoEgg") == true
		end,
		tick = function(_dt, now)
			if now - self.lastEgg < EGG_INTERVAL then
				return
			end
			self.lastEgg = now
			Pets.dropEgg(self, now)
		end,
	})

	self.scheduler:register({
		id = "wheel",
		priority = 40,
		enabled = function()
			return store:get("pet.autoWheel") == true
		end,
		tick = function(_dt, now)
			if now - self.lastWheel < WHEEL_INTERVAL then
				return
			end
			self.lastWheel = now
			Pets.spinWheel(self, now)
		end,
	})

	return self
end

return Pets
end

__modules["game/PlayerStats"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)

local PlayerStats = {}

function PlayerStats.value(player, name): number
	if player == nil or name == nil then
		return 0
	end
	-- Nearly always a miss, but some versions expose these flat; one failed lookup is cheap.
	local direct = player:FindFirstChild(name)
	if direct ~= nil and direct:IsA("ValueBase") then
		return tonumber(direct.Value) or 0
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		local value = leaderstats:FindFirstChild(name)
		if value ~= nil and value:IsA("ValueBase") then
			return tonumber(value.Value) or 0
		end
	end
	return 0
end

function PlayerStats.snapshot(player)
	return {
		strength = PlayerStats.value(player, "Strength"),
		rebirths = PlayerStats.value(player, "Rebirths"),
		gems = PlayerStats.value(player, "Gems"),
		durability = PlayerStats.value(player, "Durability"),
	}
end

return PlayerStats
end

__modules["game/Combat"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Combat -- global killing, single-target killing, and the muscle king.

	The three modes are one concept with three ways of naming a target; treating
	them as three features is what broke single-target mode, because "is combat
	happening right now?" was answered differently in four places (the scheduler,
	the punch guard, the tool task, and the selection range).

	So there is one answer, Combat.isBusy(), and the selection rules live in
	core/Targeting where the locked/free distinction is explicit and tested.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Targeting = require("core/Targeting")
local Arbiter = require("core/Arbiter")
local Duel = require("core/Duel")
local SafeZones = require("core/SafeZones")
local TargetLock = require("core/TargetLock")
local Tools = require("game/Tools")
local Remotes = require("game/Remotes")
local GameNet = require("game/Net")
local Pets = require("game/Pets")
local PlayerStats = require("game/PlayerStats")
local Attributes = require("core/Attributes")

local Combat = {}
Combat.__index = Combat

local PUNCH_LEFT = "rbxassetid://3638729053"
local PUNCH_RIGHT = "rbxassetid://3638767427"

local SCAN_INTERVAL = 0.3
local VALIDATE_INTERVAL = 0.1
local KING_INTERVAL = 0.5
local PUNCH_MISSING_GRACE = 1.5

--[[
	The boss punch cadence: 0.025 s is 40 punches a second, with no animation wait
	in between. The remote is what deals damage and the game's own cooldown value
	is what caps it (Combat.punch zeroes the tool's cooldown NumberValue).
]]
local BOSS_PUNCH_INTERVAL = 0.025
--[[
	Horizontal reach for the boss punch, in studs. The intended pose hovers
	DIRECTLY ABOVE the rig (`boss.hoverHeight`, 70 by default), so the vertical
	offset is large by design and only the horizontal distance says "am I at the
	boss". Firing the global punch remote from across the map hits nothing, breaks
	seat welds and keeps the damage hold up.
]]
local BOSS_REACH = 30

-- How often the approach pose is written DIRECTLY (position + facing) while
-- chasing a player. This subsystem keeps its OWN timestamp (`self.pinAt`) so it
-- never shares a timer with the boss hover.
local PIN_INTERVAL = 0.025

local function localPlayer()
	return Players.LocalPlayer
end

-- Root and humanoid may exist while the humanoid is dead; callers that need a
-- live target use aliveRoot.
local function rootOf(player)
	local character = player ~= nil and player.Character or nil
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		return nil, nil
	end
	return root, humanoid
end

local function aliveRoot(player)
	local root, humanoid = rootOf(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return root
end

--[[
	Friend check. An external friend-list script may install a predicate at
	MK_HUB_IS_FRIEND, or publish a whitelist at MK_HUB_FRIEND_WL. When a
	whitelist exists but has not finished loading, every player counts as a
	friend: refusing to attack is the safe direction to fail in.
]]
local function environment()
	return (type(getgenv) == "function" and getgenv()) or _G
end

local function isFriend(player)
	local env = environment()

	local predicate = env["MK_HUB_IS_FRIEND"]
	if type(predicate) == "function" then
		local ok, result = pcall(predicate, player)
		if ok then
			return result == true
		end
	end

	local whitelist = env["MK_HUB_FRIEND_WL"]
	if type(whitelist) ~= "table" then
		--[[
			NO LIST AT ALL IS NOT THE SAME AS A LIST STILL LOADING: with nothing
			published, "everyone is a friend" would disable the kill loop silently
			when the switch is on with no friend script installed. An absent list
			means "no information, so nobody is filtered"; the transient case (a
			list that has not finished loading) keeps failing safe, below.
		]]
		return false
	end
	if whitelist.loaded ~= true then
		return true
	end
	return (whitelist.ids or {})[player.UserId] == true
end

--[[
	Ask the external friend script to refresh, and read what it published. Both
	halves of the contract (MK_HUB_REFRESH_FRIENDS and the MK_HUB_FRIEND_WL read)
	are optional and probed: an executor with neither key is not an error, it just
	means no friend list is available.
]]
function Combat.refreshFriends(self): number
	local env = environment()

	local refresh = env["MK_HUB_REFRESH_FRIENDS"]
	if type(refresh) == "function" then
		pcall(refresh)
	end

	local whitelist = env["MK_HUB_FRIEND_WL"]
	if type(whitelist) == "table" then
		self.friendIds = whitelist.ids or {}
		self.friendsLoaded = whitelist.loaded == true
	else
		self.friendIds = {}
		self.friendsLoaded = false
	end

	local count = 0
	for _ in pairs(self.friendIds) do
		count += 1
	end
	self.friendCount = count
	return count
end

-- What the UI reports: how many ids are loaded, and whether the list is ready.
function Combat.friendStatus(self)
	return {
		count = self.friendCount,
		loaded = self.friendsLoaded,
	}
end

function Combat.new(context)
	local notify = context.notify
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		character = context.character,
		motion = context.motion,
		net = context.net,
		isBossAlive = context.isBossAlive or function()
			return false
		end,
		--[[
			"the boss task is actually holding the body", not "a boss exists
			somewhere": the damage hold is a claim on the machine seat, so it may
			only be raised while a fight is really happening.
		]]
		isBossEngaged = context.isBossEngaged or context.isBossAlive or function()
			return false
		end,
		-- Where the tracked boss rig is, for the punch range gate. nil when there
		-- is no rig to punch.
		bossPosition = context.bossPosition or nil,
		--[[
			The arbitration handle: while its hold is up, any task above the BODY
			rung (the gym machine) is capped and the machine steps off the seat.
			Missing it is not an error -- this subsystem runs, it just cannot ask
			anyone to make way.
		]]
		arbiter = context.arbiter or nil,
		damageHeld = false,
		--[[
			Pet presets follow the task, like the rebirth path: `petPreset.kill`
			and `petPreset.boss` were configurable and never applied because
			Pets.scheduleSwap had a single call site (the rebirth one).
		]]
		pets = context.pets or nil,
		-- The teleport kernel, for the 0.025 s direct pin. Its OWN `pinAt`
		-- lives on this subsystem: the boss hover has one too, and the two must
		-- not share a timer.
		teleport = context.teleport or nil,
		-- Late-bound "is the gym machine holding the body" check (see
		-- Combat.machineHeld): Machine is installed after Combat.
		machineSeated = context.machineSeated or nil,
		pinAt = 0,
		lastPresetKey = nil,
		-- Friend-whitelist state, refreshed through the external contract.
		friendIds = {},
		friendsLoaded = false,
		friendCount = 0,
		lastFriendTry = 0,
		notify = notify or function(message)
			warn("[MKUltraHUB][combat] " .. message)
		end,
		locked = nil,
		lockTime = 0,
		validatedAt = 0,
		scanAt = 0,
		resized = nil,
		resizedAt = 0,
		lastKing = 0,
		kingActive = false,
		animator = nil,
		tracks = {},
		punchMissingSince = 0,
		punches = 0,
		-- Player-target punches only. `punches` also counts the boss cadence, so
		-- using it to decide "did the target take a hit" convicted a player of
		-- being unreachable whenever the boss threw punches in the same window.
		killPunches = 0,
		-- Punch count when the current kill target was locked, so a timeout with
		-- zero punches does not blacklist a target we could not even reach.
		punchAtLock = 0,
		lastReason = "idle",
		--[[
			The lock's clock and its skip memory, so the next scan cannot re-pick
			the player we just gave up on.
		]]
		lock = TargetLock.new(),
		-- Counts for the page: how many candidates the skip rules removed, and
		-- why.
		skipStats = { protected = 0, unwinnable = 0, skipped = 0, total = 0 },
		-- The boss arena's computed centre (`Workspace.Events.BossArena`), cached
		-- because it is a tree walk.
		arenaAreas = nil,
		arenaAt = 0,
		-- Boss attack state, mirroring the boss-punch loop.
		bossPunchAt = 0,
		bossHandLeft = false,
		bossPunches = 0,
	}, Combat)
	return self
end

-- The user-named target, resolved from the store on demand so it is always
-- fresh (a cached Player instance needs a sync task to survive a rejoin).
function Combat.singleTarget(self)
	if self.store:get("kill.single") ~= true then
		return nil
	end
	local name = self.store:get("kill.singleName")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return Players:FindFirstChild(name)
end

--[[
	Is combat happening right now? This single predicate is what the motion hold,
	the punch guard and the tool task all consult; splitting it into "enabled" and
	"single" is exactly what broke single-target mode.
]]
function Combat.isBusy(self): boolean
	if self.store:get("kill.enabled") == true then
		return true
	end
	if self.kingActive then
		return true
	end
	local single = Combat.singleTarget(self)
	if single ~= nil and aliveRoot(single) ~= nil then
		return true
	end
	return false
end

--[[
	Is something being FOUGHT right now? The distinction `isBusy` cannot make:
	"kill is switched on" is not a fight. `isBusy` answers true for the whole
	session once the global switch is on -- correct for the guards that ask it,
	wrong for every priority question (the machine stood off the seat while the
	script punched nothing, and training was capped at the same time).

	So this is the narrower truth: a target is IN THE CROSSHAIRS -- a locked
	player, a pending king kill, or the named single-target player. It decides who
	gets the body and whose hold is up, and goes false the moment the scan finds
	nobody.
]]
function Combat.engaged(self): boolean
	if self.locked ~= nil then
		return true
	end
	if self.kingActive then
		return true
	end
	local single = Combat.singleTarget(self)
	if single ~= nil and aliveRoot(single) ~= nil then
		return true
	end
	return false
end

--[[
	THE BOSS ARENA, as areas: the user wants the arena to be a skip area too, and
	it is the one protected place whose coordinates are NOT in the shipped tables
	-- it is a folder of slots (`Workspace.Events.BossArena.Boss1` …) whose
	position only the engine knows. One area PER SLOT is computed here with the
	slot's own radius, cached because this is a tree walk and the slots do not move.
]]
local ARENA_CACHE = 10
local ARENA_SLOT_RADIUS = 250

function Combat.arenaAreas(self)
	local now = os.clock()
	if self.arenaAreas ~= nil and now - (self.arenaAt or 0) < ARENA_CACHE then
		return self.arenaAreas
	end
	self.arenaAt = now
	local out = {}
	local events = Workspace:FindFirstChild("Events")
	local arena = events ~= nil and events:FindFirstChild("BossArena") or nil
	if arena ~= nil then
		for _, slot in ipairs(arena:GetChildren()) do
			local ok, position = pcall(function()
				if slot:IsA("Model") then
					return slot:GetPivot().Position
				end
				local part = slot:FindFirstChildWhichIsA("BasePart", true)
				return if part ~= nil then part.Position else nil
			end)
			if ok and typeof(position) == "Vector3" then
				table.insert(out, {
					name = "bossArena",
					label = "Boss 竞技场",
					x = position.X,
					y = position.Y,
					z = position.Z,
					radius = ARENA_SLOT_RADIUS,
				})
			end
		end
	end
	self.arenaAreas = out
	return out
end

--[[
	EVERY player in the server, with the judgements the free scan needs:

	    protected -- damage does not apply there: the seasonal gym, the island, or
	                 the boss arena (switchable via `kill.skipSafeZones`)
	    winnable  -- core/Duel's verdict on strength-vs-durability
	    skipped   -- already spent `kill.targetTimeout` seconds on him without a kill

	All three are computed HERE because they need engine data; the DECISION to
	skip lives in core/Targeting, and the counts are kept in `skipStats` for the
	page.
]]
function Combat.candidates(self)
	local list = {}
	local me = localPlayer()
	local now = os.clock()
	local powerCheck = self.store:get("kill.powerCheck") ~= false
	local maxHits = tonumber(self.store:get("kill.powerMaxHits")) or Duel.DEFAULT_MAX_HITS
	local safeZoneCheck = self.store:get("kill.skipSafeZones") ~= false
	local arena = if safeZoneCheck then Combat.arenaAreas(self) else nil

	local mine = nil
	if powerCheck and me ~= nil then
		mine = {
			strength = PlayerStats.value(me, "Strength"),
			durability = PlayerStats.value(me, "Durability"),
		}
	end

	local stats = { protected = 0, unwinnable = 0, skipped = 0, total = 0 }

	for _, player in ipairs(Players:GetPlayers()) do
		local root, humanoid = rootOf(player)
		if root ~= nil and humanoid ~= nil then
			local ok, position = pcall(function()
				return root.Position
			end)
			if ok and typeof(position) == "Vector3" then
				local plain = { x = position.X, y = position.Y, z = position.Z }
				--[[
					The map name is read from the PLAYER ("currentMap" is the
					game's own StringValue and exists on every player, not just
					ours); the attribute is the character's own flag. Both are
					secondary: the coordinates are the authority (see core/SafeZones
					about the over-skipping this replaced).
				]]
				local mapValue = player:FindFirstChild("currentMap")
				local mapName = if mapValue ~= nil and mapValue:IsA("StringValue")
					then tostring(mapValue.Value)
					else nil
				local inArena = false
				local character = player.Character
				if character ~= nil then
					inArena = character:GetAttribute("InHalloweenArena") == true
				end

				local protected = false
				if safeZoneCheck and player ~= me then
					protected = SafeZones.isProtected(plain, mapName, inArena, arena)
				end

				local winnable = nil
				if powerCheck and (player ~= me) and me ~= nil then
					local verdict = Duel.verdict(mine, {
						strength = PlayerStats.value(player, "Strength"),
						durability = PlayerStats.value(player, "Durability"),
					}, { maxHits = maxHits })
					winnable = verdict.winnable
				end

				local skipped = self.lock:isSkipped(player.Name, now)

				stats.total += 1
				if protected then
					stats.protected += 1
				end
				if winnable == false then
					stats.unwinnable += 1
				end
				if skipped then
					stats.skipped += 1
				end

				table.insert(list, {
					id = player.Name,
					position = plain,
					alive = humanoid.Health > 0,
					friend = isFriend(player),
					self = (player == me),
					protected = protected,
					winnable = winnable,
					skipped = skipped,
				})
			end
		end
	end
	self.skipStats = stats
	return list
end

-- Returns (player, reason). The reason is surfaced in the UI and in the log,
-- because "nothing happened" used to be undiagnosable.
function Combat.select(self)
	local origin = self.character:requireRoot()
	if origin == nil then
		return nil, "no-character"
	end
	local ok, position = pcall(function()
		return origin.Position
	end)
	if not ok or typeof(position) ~= "Vector3" then
		return nil, "no-position"
	end

	local lockedId = nil
	--[[
		GLOBAL KILL OUTRANKS A HAND-PICKED TARGET ("打 Boss > 全图杀戮 > 单独击杀 /
		肌肉之王 > 器械"): `kill.single` only wins when global kill is OFF, and it
		is deliberately NOT forced off, so switching global kill back off returns
		to the target the user chose.
	]]
	if self.store:get("kill.single") == true and self.store:get("kill.enabled") ~= true then
		lockedId = tostring(self.store:get("kill.singleName") or "")
	end

	local decision = Targeting.select(Combat.candidates(self), { x = position.X, y = position.Y, z = position.Z }, {
		--[[
			UNLIMITED, because 全图杀戮 means the whole map: a distance cap only hid
			work, since a far target is exactly the case the approach logic exists
			for. `math.huge` keeps the nearest-candidate arithmetic unchanged and
			makes `all-out-of-range` unreachable for the free scan.
		]]
		range = math.huge,
		respectFriends = self.store:get("kill.friendWL") == true,
		lockedId = lockedId,
	})

	self.lastReason = decision.reason
	if decision.id == nil then
		return nil, decision.reason
	end
	return Players:FindFirstChild(decision.id), decision.reason
end

function Combat.playAnimation(self, humanoid, left)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	-- A respawn replaces the humanoid, and with it every loaded track.
	if self.animator ~= animator then
		self.animator = animator
		table.clear(self.tracks)
	end

	local key = if left then "left" else "right"
	local track = self.tracks[key]
	if track == nil then
		local animation = Instance.new("Animation")
		animation.AnimationId = if left then PUNCH_LEFT else PUNCH_RIGHT
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or loaded == nil then
			return
		end
		track = loaded
		self.tracks[key] = track
	end
	pcall(function()
		track:Stop(0)
		track:Play(0.1)
	end)
end

--[[
	Throw one punch.

	No mouse simulation: injecting a click every 0.05 s consumed the player's real
	clicks ("opening auto-boss makes the whole screen unclickable"). Punches are
	the remote plus an animation only, through the network layer, so the rate is
	bounded and counted instead of an invisible flood.
]]
function Combat.punch(self, left, now, force)
	if self.character:isAlive() ~= true then
		return
	end
	local character = self.character:current()
	local humanoid = self.character:humanoid()
	if character == nil or humanoid == nil then
		return
	end

	--[[
		The tool arbiter's half of the hand. A punch re-equips the glove, and it is
		thrown up to 120 times a second (twice per attack tick, plus the boss
		cadence), so the glove would win every frame against the training task and
		no rep would ever register. While the arbiter owns the hand for training,
		this function does nothing at all: no equip, no punch, no animation.

		`force` is the boss path's exemption: the boss task outranks the dual-tool
		window and must not be muted for half of every 0.3 s.
	]]
	if not force and self.store:get("train.dualTool") == "train" then
		return
	end

	local player = localPlayer()
	Tools.equip(character, humanoid, player, Tools.PUNCH)

	local tool = Tools.equipped(character, Tools.PUNCH)
	if tool ~= nil then
		pcall(function()
			local cooldown = tool:FindFirstChildOfClass("NumberValue")
			if cooldown ~= nil then
				cooldown.Value = 0.01
			end
		end)
	end

	self.net:send("punch", now or os.clock(), "punch", if left then "leftHand" else "rightHand")
	self.punches += 1
	if not force then
		self.killPunches += 1
	end
	Combat.playAnimation(self, humanoid, left)
end

--[[
	Is something in this script currently required to be able to deal damage? The
	boss attack and this module's kill loops both raise the SAME `damage`
	requirement, because the consequence for everything else is identical: the gym
	machine has to get out of the way.

	`engaged`, NOT `isBusy`: with global kill on and nobody in range, `isBusy`
	held the requirement up forever, so the machine was blocked and training capped
	while nothing was fought. The boss half has the same shape of bug one level
	down: "a boss exists" is not "we are fighting it".
]]
function Combat.wantsDamage(self): boolean
	if self.store:get("boss.auto") == true and self.isBossEngaged() then
		return true
	end
	return Combat.engaged(self)
end

--[[
	Hold the damage requirement for exactly as long as it is true. Held on the
	instance, not the arbiter, so the hold is tied to this subsystem's lifetime and
	a leftover hold from a dead subsystem can never keep the machine locked out.
]]
function Combat.maintainDamageHold(self)
	local wanted = Combat.wantsDamage(self)
	local instance = self.damageInstance
	if instance == nil then
		return wanted
	end
	if wanted and not self.damageHeld then
		self.damageHeld = true
		instance:hold("damage")
	elseif not wanted and self.damageHeld then
		self.damageHeld = false
		instance:releaseFlag("damage")
	end
	return wanted
end

--[[
	Is the tracked boss rig within punching distance? Firing the global punch
	remote from wherever the player is (including a gym machine across the map)
	does nothing, breaks the seat weld and keeps the damage hold up.

	Horizontal distance only -- hovering above the rig is the intended pose.
	Without an injected `bossPosition` this stays permissive so the feature still
	works on older hosts; with a getter that cannot name a rig it is strict.
]]
function Combat.bossInReach(self): boolean
	if self.bossPosition == nil then
		return true
	end
	local bossAt = self.bossPosition()
	if bossAt == nil then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end
	local ok, position = pcall(function()
		return root.Position
	end)
	if not ok or position == nil then
		return false
	end
	local dx = position.X - bossAt.X
	local dz = position.Z - bossAt.Z
	return dx * dx + dz * dz <= BOSS_REACH * BOSS_REACH
end

--[[
	One boss punch cycle: alternate hands, paced at BOSS_PUNCH_INTERVAL, only when
	the rig is in reach, and always forcing past the dual-tool train window -- the
	boss task outranks that window.
]]
function Combat.bossPunchTick(self, now)
	if self.store:get("boss.auto") ~= true or not self.isBossAlive() then
		self.bossPunchAt = 0
		return
	end
	if not Combat.bossInReach(self) then
		return
	end
	if now - self.bossPunchAt < BOSS_PUNCH_INTERVAL then
		return
	end
	self.bossPunchAt = now
	self.bossHandLeft = not self.bossHandLeft
	Combat.punch(self, self.bossHandLeft, now, true)
	self.bossPunches += 1
end

--[[
	Which pet preset the current activity wants, or nil for "none". Order matters:
	a boss fight outranks a kill loop.
]]
function Combat.presetFor(self): string?
	if self.store:get("boss.auto") == true and self.isBossAlive() then
		return "boss"
	end
	if Combat.isBusy(self) then
		return "kill"
	end
	return nil
end

--[[
	Follow the preset when the desired key CHANGES. Re-requesting every frame would
	keep re-arming scheduleSwap's 0.4 s delay, so the preset would never be applied
	while the task stayed busy.
]]
function Combat.followPreset(self)
	if self.pets == nil then
		return
	end
	local key = Combat.presetFor(self)
	if key == self.lastPresetKey then
		return
	end
	self.lastPresetKey = key
	if key ~= nil then
		Pets.scheduleSwap(self.pets, key, 0.4)
	end
end

--[[
	Is the GYM MACHINE holding the body right now? Late-bound because Machine is
	installed after Combat. While it has the seat the fight must not hold the
	character, or the seat weld breaks and the machine remounts forever.
]]
function Combat.machineHeld(self): boolean
	local check = self.machineSeated
	if type(check) ~= "function" then
		return false
	end
	local ok, seated = pcall(check)
	return ok and seated == true
end

-- Close the distance through the motion kernel (so a pullback is corrected) and
-- strike.
function Combat.attack(self, target)
	--[[
		The machine wins when it was allowed to: `machine.overridesCombat` lets the
		gym machine keep the seat during a fight, and the approach below holds the
		body (a hold sets `PlatformStand`), which would stand the player up. So the
		approach stands down while the machine has the seat, and resumes by itself
		once the player is off it.
	]]
	if Combat.machineHeld(self) then
		return
	end

	local myRoot = self.character:requireRoot()
	local targetRoot = rootOf(target)
	if myRoot == nil or targetRoot == nil then
		return
	end
	local okMine, myPosition = pcall(function()
		return myRoot.Position
	end)
	local okTarget, targetPosition = pcall(function()
		return targetRoot.Position
	end)
	if not okMine or not okTarget then
		return
	end

	if self.store:get("kill.approach") ~= false then
		--[[
			The overhead approach (the boss fight's geometry): standing behind the
			target at its own height makes the punch travel level and pass over the
			shoulder of anything shorter. So stand `kill.hoverHeight` ABOVE the
			target and look down at it. The default height is a body (12 studs),
			not the boss's 70: a player is not a huge hitbox and has to stay inside
			the game's punch reach. The tilt is what makes the punch land.
		]]
		local height = tonumber(self.store:get("kill.hoverHeight")) or 12
		local destination = targetPosition + Vector3.new(0, math.max(1, height), 0)
		local bias = if self.store:get("kill.lookDown") == false then nil else Vector3.new(0, -1, 0)

		--[[
			The direct pin, on its OWN timer: this chases a PLAYER whose position is
			re-read every tick, and it runs at the same time as the boss fight, so
			sharing one timestamp would make each pin starve the other's. 0.025 s,
			position AND facing in the same write; `kill.directPin` turns it off
			for a place that dislikes the rate.
		]]
		if self.teleport ~= nil and self.store:get("kill.directPin") ~= false then
			local stamp = os.clock()
			if stamp - (self.pinAt or 0) >= PIN_INTERVAL then
				self.pinAt = stamp
				--[[
					A REGISTERED TASK ID, not "combat": `Scheduler.claim` only
					arbitrates registered ids and waves an unknown one through, so
					the machine, the chest and the loops all thought the body was
					free while combat wrote it every 0.025 s.
				]]
				self.teleport:pin(destination, targetPosition, bias,
					if self.kingActive then "kingKill" else "kill")
			end
		end

		self.motion:setTarget(destination)
		if not self.motion:isActive() then
			self.motion:begin({
				pos = destination,
				mode = "combat",
				job = if self.kingActive then "kingKill" else "kill",
				look = targetPosition,
				lookBias = bias,
			})
		end
		self.motion:setLook(targetPosition, bias)
	else
		local flat = Vector3.new(targetPosition.X - myPosition.X, 0, targetPosition.Z - myPosition.Z)
		if flat.Magnitude > 0.1 then
			pcall(function()
				myRoot.CFrame = CFrame.lookAt(myPosition, myPosition + flat.Unit)
			end)
		end
	end

	local now = os.clock()
	Combat.punch(self, false, now)
	Combat.punch(self, true, now)

	if self.store:get("kill.targetSizeEnabled") == true then
		Combat.resize(self, target)
	end
end

function Combat.tick(self, now)
	--[[
		How long one target may hold the lock, re-read every frame. core/TargetLock
		owns the clock AND the skip memory that goes with it: dropping the lock on
		its own just makes the next scan pick the same nearest player again.
	]]
	self.lock:configure({
		timeout = tonumber(self.store:get("kill.targetTimeout")),
		skipSeconds = tonumber(self.store:get("kill.targetSkip")),
	})

	if self.locked ~= nil then
		-- The liveness test walks the target's character (a root + humanoid
		-- lookup), so it is throttled; the timeout itself is arithmetic and is
		-- checked by `step` on every frame.
		local valid = true
		if now - self.validatedAt >= VALIDATE_INTERVAL then
			self.validatedAt = now
			--[[
				`aliveRoot` answers nil for a player who LEFT as well as for a
				corpse, so "扫描不存在的对象" cannot keep a departed player locked.
			]]
			valid = (self.locked.Parent ~= nil) and (aliveRoot(self.locked) ~= nil)
		end

		local verdict = self.lock:step(now, valid)
		if verdict.action ~= "keep" then
			if verdict.action == "timeout" then
				--[[
					A timeout only convicts the target if we actually HIT it: a
					target that was never reachable collected a 10 s timeout and a
					60 s skip without ever taking a punch, and enough of those empty
					the candidate list. No punch, no skip: the lock is dropped and
					the next scan may pick it again.
				]]
				if self.killPunches == self.punchAtLock then
					self.lock:unskip(verdict.id)
				else
					self.lastReason = string.format("超时跳过 %s（%d 秒没打死）",
						tostring(verdict.id), math.floor(self.lock._timeout))
					-- Report once per couple of seconds, not once per timeout.
					if now - (self.lastSkipNotice or 0) > 3 then
						self.lastSkipNotice = now
						self.notify(string.format("目标 %s %d 秒内没打死，已跳过",
							tostring(verdict.id), math.floor(self.lock._timeout)), "warn")
					end
				end
			end
			self.locked = nil
			self.lockTime = 0
			self.validatedAt = 0
			self.resized = nil
		end
	end

	if self.locked == nil and now - self.scanAt >= SCAN_INTERVAL then
		self.scanAt = now
		local target = self.select(self)
		if target ~= nil then
			self.locked = target
			self.lockTime = now
			self.validatedAt = now
			self.resized = nil
			--[[
				The clock is NOT restarted when the same player is re-selected (see
				TargetLock.lock): a scan that kept re-picking it would reset the
				timeout forever, which is the "执着" the timeout exists to end.
			]]
			self.lock:lock(target.Name, now)
			-- Punch count at lock time: whether the target took a hit between lock
			-- and timeout is what the timeout rule above checks. Only the PLAYER
			-- punches count (see killPunches), or a boss fight running beside the
			-- kill loop would convict the target for us.
			self.punchAtLock = self.killPunches
		end
	end

	if self.locked ~= nil then
		self.attack(self, self.locked)
	end
end

--[[
	The muscle king is published by the game as an ObjectValue or StringValue. A
	value that points at nothing usable answers nil rather than a dead instance:
	the ObjectValue branch used to keep chasing a model that had outlived its
	character.
]]
function Combat.findKing()
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local state = shared and shared:FindFirstChild("state")
	local world = state and state:FindFirstChild("World")
	local value = world and world:FindFirstChild("muscleKing")
	if value == nil then
		return nil
	end
	if value:IsA("ObjectValue") then
		local pointed = value.Value
		if pointed == nil or pointed.Parent == nil then
			return nil
		end
		if not pointed:IsA("Player") and not pointed:IsA("Model") then
			return nil
		end
		return pointed
	end
	if value:IsA("StringValue") and value.Value ~= "" then
		local found = Players:FindFirstChild(value.Value)
		if found == nil or found.Parent == nil then
			return nil
		end
		return found
	end
	return nil
end

function Combat.kingTick(self, now)
	if now - self.lastKing < KING_INTERVAL then
		return
	end
	self.lastKing = now

	local king = Combat.findKing()
	if king == nil or king == localPlayer() then
		self.kingActive = false
		return
	end
	if self.store:get("kill.friendWL") == true and isFriend(king) then
		self.kingActive = false
		return
	end
	if aliveRoot(king) == nil then
		self.kingActive = false
		return
	end
	self.kingActive = true
	Combat.attack(self, king)
end

--[[
	Keep a punch tool in hand while combat is running. This has to consult
	Combat.wantsDamage rather than `kill.enabled`: in single-target mode the glove
	was never restored after anything replaced it, and the attacks silently did
	nothing.
]]
function Combat.guardPunch(self, now)
	if self.store:get("cfg.keepPunch") ~= true or not Combat.wantsDamage(self) then
		self.punchMissingSince = 0
		return
	end
	-- The tool arbiter is holding the training tool on purpose: re-equipping the
	-- glove here would end the training half of the alternation immediately.
	if self.store:get("train.dualTool") == "train" then
		self.punchMissingSince = 0
		return
	end
	if self.character:isAlive() ~= true then
		self.punchMissingSince = 0
		return
	end

	local character = self.character:current()
	local humanoid = self.character:humanoid()
	if Tools.equipped(character, Tools.PUNCH) ~= nil then
		self.punchMissingSince = 0
		return
	end
	if Tools.equip(character, humanoid, localPlayer(), Tools.PUNCH) then
		self.punchMissingSince = 0
		return
	end

	if self.punchMissingSince == 0 then
		self.punchMissingSince = now
		return
	end
	if now - self.punchMissingSince < PUNCH_MISSING_GRACE then
		return
	end

	self.punchMissingSince = 0
	if self.store:get("cfg.autoSuicide") == true then
		self.notify("punch tool missing; respawning", "warn")
		Combat.suicide(self)
	else
		self.notify("no punch tool available (enable auto respawn in settings)", "warn")
	end
end

function Combat.suicide(self)
	local humanoid = self.character:humanoid()
	if humanoid ~= nil and humanoid.Health > 0 then
		pcall(function()
			humanoid.Health = 0
		end)
	end
end

local function isPetPart(part, character)
	local node = part
	while node ~= nil and node ~= character do
		if string.find(string.lower(node.Name), "pet", 1, true) ~= nil then
			return true
		end
		node = node.Parent
	end
	return false
end

--[[
	Client-side resize of another player's model: purely cosmetic locally, the
	server model is untouched.

	The pet check walks the ancestor chain, so its result is cached as an
	attribute on the part. The cache is assumed to outlive the part: a pet is
	identified by its ancestor chain, which is fixed for that part's lifetime. If
	that ever changes, clear `_MK_Pet` on the character's ChildAdded/ChildRemoved
	rather than dropping the cache.
]]
function Combat.resize(self, player)
	local character = player ~= nil and player.Character or nil
	if character == nil then
		return
	end
	local now = os.clock()
	if self.resized == player and now - self.resizedAt < 1 then
		return
	end
	self.resized = player
	self.resizedAt = now

	local multiplier = tonumber(self.store:get("kill.targetSizeMul")) or 5
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			local isPet = object:GetAttribute(Attributes.PET)
			if isPet == nil then
				isPet = isPetPart(object, character)
				object:SetAttribute(Attributes.PET, isPet)
			end
			if isPet ~= true then
				local original = object:GetAttribute(Attributes.ORIGINAL_SIZE)
				if original == nil then
					original = object.Size
					object:SetAttribute(Attributes.ORIGINAL_SIZE, original)
				end
				pcall(function()
					object.Size = original * multiplier
				end)
			end
		end
	end
end

function Combat.restoreAll(self)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer() then
			local character = player.Character
			if character ~= nil then
				for _, object in ipairs(character:GetDescendants()) do
					if object:IsA("BasePart") then
						local original = object:GetAttribute(Attributes.ORIGINAL_SIZE)
						if original ~= nil then
							pcall(function()
								object.Size = original
							end)
						end
					end
				end
			end
		end
	end
	self.resized = nil
end

function Combat.stats(self)
	local now = os.clock()
	return {
		punches = self.punches,
		locked = if self.locked ~= nil then self.locked.Name else nil,
		kingActive = self.kingActive,
		lastReason = self.lastReason,
		--[[
			The skip read-out: whether it is the safe zones, the win/lose check or
			a timeout that is removing people, which cannot be answered from
			outside.
		]]
		held = self.lock:held(now),
		timeouts = self.lock._timeouts,
		skippedCount = self.lock:skipCount(now),
		skippedIds = self.lock:skippedIds(now),
		skipStats = self.skipStats,
	}
end

-- Let go of the body -- but only if the hold is the FIGHT's. A hold in mode
-- "combat" was started by Combat.attack; anything else (boss hover, chest walk,
-- machine mount) belongs to another subsystem and must survive a kill switch.
function Combat.releaseHold(self): boolean
	if self.motion == nil then
		return false
	end
	local ok, mode = pcall(function()
		return self.motion:mode()
	end)
	if not ok or mode ~= "combat" then
		return false
	end
	pcall(function()
		self.motion:finish()
	end)
	return true
end

function Combat.install(context)
	local self = Combat.new(context)

	--[[
		Punches are event-driven rather than bursty: the kill loop throws two
		punches per frame (one per hand) and the boss cadence adds its own, so a
		60/s channel cap -- not the game -- set the punch rate. 400/s with a
		matching burst leaves the limiter as a flood guard for a runaway loop.
	]]
	self.net:addChannel("punch", GameNet.senderFor(Remotes.muscle), {
		rate = 400,
		burst = 60,
		queue = 0,
	})

	local store = self.store

	--[[
		The damage requirement lives on its own instance, not on the kill task: two
		tasks can want it (boss attack and kill loop) and the hold has to be up
		whenever EITHER does, so it is driven from one place rather than duplicated
		inside each task where the two would release each other's hold.
	]]
	if self.arbiter ~= nil then
		self.damageInstance = self.arbiter:instance("combat", "kill.enabled", Arbiter.Depth.BODY, Arbiter.Depth.BODY)
	end

	self.scheduler:register({
		id = "kingKill",
		priority = 380,
		enabled = function()
			if store:get("kill.autoKing") ~= true then
				return false
			end
			if store:get("tp.autoMK") ~= true then
				return false
			end
			if store:get("kill.enabled") == true then
				return false
			end
			if store:get("boss.auto") == true and self.isBossAlive() then
				return false
			end
			return true
		end,
		onDisable = function()
			self.kingActive = false
		end,
		tick = function(_dt, now)
			Combat.kingTick(self, now)
		end,
	})

	self.scheduler:register({
		id = "kill",
		priority = 370,
		enabled = function()
			local single = Combat.singleTarget(self)
			local hasSingle = single ~= nil and single.Parent ~= nil
			if not (store:get("kill.enabled") == true or hasSingle) then
				return false
			end
			if self.kingActive then
				return false
			end
			if store:get("boss.auto") == true and self.isBossAlive() then
				return false
			end
			return true
		end,
		onEnable = function()
			self.locked = nil
			self.lockTime = 0
			self.validatedAt = 0
			self.scanAt = 0
			self.resized = nil
		end,
		onDisable = function()
			self.locked = nil
			self.lockTime = 0
			self.validatedAt = 0
			Combat.restoreAll(self)
			Combat.releaseHold(self)
			--[[
				Hand the pet preset back to training: a kill session used to leave
				the player wearing the "kill" pets while training, permanently.
			]]
			self.lastPresetKey = "train"
			if self.pets ~= nil then
				Pets.scheduleSwap(self.pets, "train", 0.5)
			end
		end,
		tick = function(_dt, now)
			Combat.tick(self, now)
		end,
	})

	self.scheduler:register({
		id = "punchGuard",
		priority = 200,
		enabled = function()
			return store:get("cfg.keepPunch") == true and Combat.wantsDamage(self)
		end,
		onDisable = function()
			self.punchMissingSince = 0
		end,
		tick = function(_dt, now)
			Combat.guardPunch(self, now)
		end,
	})

	--[[
		The boss attack. Priority 385 is above the kill loop (370) and the tool task
		(60) and just under kingKill (380), which is inert while a boss is alive. It
		runs while `boss.auto` is on and this subsystem is actually ENGAGED with the
		boss, and is deliberately NOT gated on `kill.enabled`.

		`isBossEngaged`, not `isBossAlive`: a task that is enabled holds its rung of
		the body arbiter, so "does a boss exist anywhere" made a boss idling across
		the map disable the gym machine. This task is also the whole reason the
		damage requirement exists.
	]]
	self.scheduler:register({
		id = "bossPunch",
		priority = 385,
		enabled = function()
			return store:get("boss.auto") == true and self.isBossEngaged()
		end,
		onEnable = function()
			self.bossPunchAt = 0
			self.bossHandLeft = false
		end,
		onDisable = function()
			self.bossPunchAt = 0
		end,
		tick = function(_dt, now)
			-- Kept up to date before the punch so the machine has already been
			-- told to step off by the time the first hand goes out.
			Combat.maintainDamageHold(self)
			Combat.bossPunchTick(self, now)
		end,
	})

	--[[
		Keep the requirement honest even when the boss task is not the one that
		needs it: this drops it the moment neither source wants damage, so a boss
		dying mid-kill does not leave the hold up and the machine locked out.
	]]
	self.scheduler:register({
		id = "damageHold",
		priority = 386,
		enabled = function()
			return self.damageInstance ~= nil
		end,
		tick = function()
			Combat.maintainDamageHold(self)
			Combat.followPreset(self)
		end,
		onDisable = function()
			if self.damageInstance ~= nil and self.damageHeld then
				self.damageHeld = false
				self.damageInstance:releaseFlag("damage")
			end
		end,
	})

	--[[
		Keep the friend whitelist loaded while "不打好友" is on. The external friend
		script may not be ready at load, and a whitelist that never loads makes
		`isFriend` answer `true` for everyone -- so combat refuses every target with
		no explanation. The retry is what makes that self-healing; the button on the
		kill page is the manual override.
	]]
	self.scheduler:register({
		id = "friendRefresh",
		priority = 45,
		enabled = function()
			return store:get("kill.friendWL") == true
		end,
		onEnable = function()
			-- A fresh enable is a fresh attempt.
			self.lastFriendTry = 0
		end,
		tick = function(_dt, now)
			if now - self.lastFriendTry < 10 then
				return
			end
			self.lastFriendTry = now
			Combat.refreshFriends(self)
			-- Say it once: "不打好友" with no friend list is not a filter, it is a
			-- promise the executor cannot keep (see isFriend).
			if self.friendWarned ~= true and self.friendsLoaded ~= true then
				self.friendWarned = true
				self.notify("没有可用的好友名单（MK_HUB_FRIEND_WL），「不打好友」当前不生效", "warn")
			end
		end,
	})

	return self
end

return Combat
end

__modules["game/Boss"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Boss -- detecting the boss, attacking it, and looting the chest.

	The decision rules live in core (core/BossInfo, core/ChestTimer); this file is
	the traversal and the engine calls.

	Detection is cached for half a second: the alive-check is consulted by several
	subsystems every frame, and each miss walks Workspace.Events.BossArena.

	The structure is probed in two passes: the arena's fixed slots (Boss1..Boss5,
	BossRainbow), then a fallback scan of every child reading the rarity out of the
	name, so a renamed or newly added arena still works.
]]

local VirtualInputManager = game:GetService("VirtualInputManager")

local BossInfo = require("core/BossInfo")
local ChestTimer = require("core/ChestTimer")
local Pets = require("game/Pets")
local Remotes = require("game/Remotes")
-- The Teleport MODULE (not the instance in `self.teleport`): the boss pin needs
-- `isBusy` / `cancel` / `snap`, which are module functions.
local Teleport = require("game/Teleport")

local Players = game:GetService("Players")

local Boss = {}
Boss.__index = Boss

local DETECT_CACHE = 0.5
local INTERACT_INTERVAL = 0.4
local TOUCH_TAIL = 0.05
-- How far above the chest's base part the player is put before interacting.
-- See Boss.chestTick: the prompt volume is above the rig, and the legacy offset
-- of 5 studs sat the character on the hinge line where E usually did nothing.
local CHEST_STAND_HEIGHT = 15
-- How long the chest keeps the body after the first successful interaction (see
-- Boss.chestTick): long enough for the prompt to register, short enough that the
-- fight is not paused for the rest of the chest timer's 60 s window.
local CHEST_HOLD = 4

local function selectionOf(store)
	local selection = {}
	for _, rarity in ipairs(BossInfo.RARITIES) do
		selection[rarity] = store:get("boss.select." .. rarity) ~= false
	end
	return selection
end

--[[
	The EVENT bosses the user wants attacked, as a { key = true } set. An EMPTY
	set means "this group is off", which is what makes eventWanted a single lookup.
]]
local function eventSelection(store)
	local selection = {}
	if store:get("boss.event.enabled") == false then
		return selection
	end
	for _, entry in ipairs(BossInfo.events()) do
		selection[entry.key] = store:get("boss.event." .. entry.key) ~= false
	end
	return selection
end

local function eventWanted(selection, key): boolean
	return selection[key] == true
end

--[[
	The boss's HP, from wherever this build publishes it: "Health"/"MaxHealth"
	attributes on the holder, on the model, on a child part, or only a Humanoid.
	Reading all of them keeps the HP line honest instead of printing 0 / 0, and
	the HP decides "he is dead, move on" (see bossDown).

	The DESCENDANT scan is last and bounded: a rig that publishes health somewhere
	we did not guess would otherwise read nil, and nil means "not dead" by design.
]]
local HEALTH_NAMES = { "Health", "health", "HP", "hp", "CurrentHealth", "currentHealth" }
local HEALTH_SCAN_NODES = 400

local function healthFromAttributes(object)
	if object == nil then
		return nil, nil
	end
	local ok, health = pcall(function()
		for _, name in ipairs(HEALTH_NAMES) do
			local value = tonumber(object:GetAttribute(name))
			if value ~= nil then
				return value
			end
		end
		return nil
	end)
	if not ok then
		return nil, nil
	end
	local okMax, maxHp = pcall(function()
		return tonumber(object:GetAttribute("MaxHealth")) or tonumber(object:GetAttribute("maxHealth"))
	end)
	return health, if okMax then maxHp else nil
end

local function healthFromDescendants(holder)
	if holder == nil then
		return nil, nil
	end
	local scanned = 0
	local ok, health, maxHp = pcall(function()
		for _, object in ipairs(holder:GetDescendants()) do
			scanned += 1
			if scanned > HEALTH_SCAN_NODES then
				break
			end
			local value, maximum = healthFromAttributes(object)
			if value == nil and object:IsA("ValueBase") then
				value = tonumber(object.Value)
			end
			if value ~= nil then
				return value, maximum
			end
		end
		return nil, nil
	end)
	if not ok then
		return nil, nil
	end
	return health, maxHp
end

local function readHealth(holder, model)
	local health, maxHp = healthFromAttributes(holder)
	if health == nil and model ~= nil and model ~= holder then
		health, maxHp = healthFromAttributes(model)
	end
	if health == nil then
		local humanoid = holder:FindFirstChildWhichIsA("Humanoid", true)
		if humanoid == nil and model ~= nil and model ~= holder then
			humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
		end
		if humanoid ~= nil then
			health = humanoid.Health
			maxHp = humanoid.MaxHealth
		end
	end
	if health == nil then
		-- Last resort, and bounded: see the note above. The model is scanned
		-- before the holder so a rig that keeps its own health on a part is read
		-- from there rather than from a stale wrapper attribute.
		health, maxHp = healthFromDescendants(model)
		if health == nil and model ~= holder then
			health, maxHp = healthFromDescendants(holder)
		end
	end
	return health, maxHp
end

-- Where an object is, whether it is a Model, a BasePart, or a container holding
-- one. nil when the instance has no readable position at all.
local function objectPosition(object)
	if object == nil then
		return nil
	end
	local ok, position = pcall(function()
		if object:IsA("Model") then
			return object:GetPivot().Position
		end
		if object:IsA("BasePart") then
			return object.Position
		end
		local part = object:FindFirstChildWhichIsA("BasePart", true)
		if part ~= nil then
			return part.Position
		end
		return nil
	end)
	if ok and typeof(position) == "Vector3" then
		return position
	end
	return nil
end

--[[
	At least one visible BasePart? `HumanoidRootPart` is excluded because it is
	invisible on every healthy rig. A rig too large to check within the budget
	counts as visible: "probably hidden" must never abandon a fight.
]]
local VISIBLE_PARTS_LIMIT = 60

local function hasVisiblePart(model): boolean
	if model == nil then
		return true
	end
	local total = 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			total += 1
			if total > VISIBLE_PARTS_LIMIT then
				return true
			end
			if part.Name ~= "HumanoidRootPart" then
				local ok, transparency = pcall(function()
					return part.Transparency
				end)
				if not ok or type(transparency) ~= "number" or transparency < 0.99 then
					return true
				end
			end
		end
	end
	-- No parts at all: nothing to judge, so not "hidden".
	return total == 0
end

--[[
	IS THIS RIG DOWN?

	THE GAME DOES NOT DELETE A DEFEATED BOSS, it hides it: the model stays in the
	arena with `Health = 0` and its parts made invisible. "Does a model exist" as
	the alive test therefore kept the fight punching a corpse, never reached the
	next boss, and never observed the death that opens the chest.

	"Down" is any of: HP <= 0, a dead Humanoid, or no visible BasePart left.
	`nil` HP means "unmeasurable", deliberately NOT down.
]]
local function bossDown(holder, model): boolean
	local health = readHealth(holder, model)
	if health ~= nil and health <= 0 then
		return true
	end
	local humanoid = holder:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid == nil and model ~= nil and model ~= holder then
		humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	end
	if humanoid ~= nil and humanoid.Health <= 0 then
		return true
	end
	return not hasVisiblePart(model)
end

-- Fill a record. `group` is "normal" or "event": it decides which selection
-- switches apply, which hover height the fight uses, and which group
-- `boss.priority` puts first.
local function fill(info, holder, model, id, rarity, group, eventKey)
	info.alive = true
	info.id = id
	info.rarity = rarity
	info.group = group
	info.eventKey = eventKey
	local health, maxHealth = readHealth(holder, model)
	info.hp = health or 0
	info.maxHp = maxHealth or 0
	info.position = objectPosition(model or holder)
	return info
end

function Boss.new(context)
	local self = setmetatable({
		store = context.store,
		character = context.character,
		motion = context.motion,
		teleport = context.teleport,
		timers = context.timers,
		scheduler = context.scheduler,
		notify = context.notify or function() end,
		-- The pet preset follows the task: "boss" while the fight runs, back to
		-- "train" when it ends.
		pets = context.pets or nil,
		-- Used on exit to restore the body size. A FUNCTION, not the service:
		-- main.luau installs Size AFTER Boss, so a captured value would be nil.
		sizeRef = context.size or nil,
		-- The rejoin service, for the post-event server hop. Installed BEFORE
		-- Boss in main.luau, so this is a real value rather than a getter.
		rejoin = context.rejoin or nil,
		--[[
			The persistence module, so the SERVER HOP can save the config first: a
			hop leaves the session, and the autosave polls at 1 Hz and only writes
			on change, so a switch flipped just before the last boss died would
			otherwise be lost.
		]]
		persist = context.persist or nil,
		-- Late-bound "is the gym machine holding the body" check: Machine is
		-- installed after Boss.
		machineSeated = context.machineSeated or nil,
		-- Where to put the player back when the boss task turns off.
		lastPosition = nil,
		cacheAt = 0,
		cacheInfo = BossInfo.empty(),
		-- The rig the current fight is on, so position and health can be re-read
		-- every frame instead of once per DETECT_CACHE (see liveDown).
		trackedHolder = nil,
		trackedModel = nil,
		chest = ChestTimer.new(),
		lastInteract = 0,
		loots = 0,
		--[[
			The chest claim: true while a chest is READY and the chest task is
			working on it; Boss.approach yields the body while this is up. The user's
			rule is "捡宝箱的任务高于打 boss": without the claim the boss motion
			hold rewrites the CFrame every frame, so the chest walk can never arrive.
		]]
		chestClaim = false,
		chestStatus = "idle",
		--[[
			Is the fight HOLDING THE CHARACTER right now? Not "auto-boss is on" and
			not "a boss is on the map": this is the boss task's own answer, published
			for the gym machine (step off the seat) and training (do not compete for
			the hand). Wiring those to `bossAlive` is the reported deadlock: a boss
			merely alive blocked the machine from mounting, and the machine holding
			the seat stopped the fight from engaging.
		]]
		engaged = false,
		-- When the chest was first interacted with, so the claim can be released
		-- without waiting out the timer's whole window.
		chestLootedAt = nil,
		-- Event-boss holder cache, so the scan is not repeated every tick.
		eventHolderCache = nil,
		eventHolderCacheAt = 0,
		-- "get me into the Hallowed Gym first" bookkeeping. See Boss.ensureArena.
		travelAt = 0,
		travelFirstAt = 0,
		travelTries = 0,
		travelGaveUp = false,
		travelWarned = false,
		-- Last direct hover write (`Teleport.pin`), on the 0.025 s cadence.
		pinAt = 0,
	}, Boss)
	return self
end

--[[
	THE CHEST'S BASE PART(S), not just "some base part under the chest". The live
	object is a Model holding `["Epic Chest"] -> EpicChest_Base` and friends, and
	"PrimaryPart or the first BasePart found" can be a lid hinge, i.e. not where
	the player stands; the game's own `_Base` suffix is preferred.

	Several chests exist at once, so the base parts are collected and the caller
	picks: a VISIBLE one if exactly one is visible, otherwise the one nearest the
	player. The wrong one means teleporting to an empty rig and pressing E forever.
]]
local function collectBaseParts(chest, out)
	if chest == nil then
		return
	end
	if chest:IsA("BasePart") then
		table.insert(out, chest)
		return
	end
	local descendants = chest:GetDescendants()
	for _, object in ipairs(descendants) do
		if object:IsA("BasePart") and string.sub(object.Name, -5) == "_Base" then
			table.insert(out, object)
		end
	end
	if #out > 0 then
		return
	end

	local primary = chest.PrimaryPart
	if primary ~= nil then
		table.insert(out, primary)
	end
	-- Direct children before a deep scan: the named chest folders are one level
	-- down, and a deep scan is what picked up a hinge.
	for _, object in ipairs(chest:GetChildren()) do
		if object:IsA("BasePart") then
			table.insert(out, object)
		end
	end
	for _, object in ipairs(chest:GetChildren()) do
		local found = object:FindFirstChildWhichIsA("BasePart", true)
		if found ~= nil then
			table.insert(out, found)
		end
	end
	if #out == 0 then
		for _, object in ipairs(descendants) do
			if object:IsA("BasePart") then
				table.insert(out, object)
			end
		end
	end
end

local function partPosition(part)
	local ok, position = pcall(function()
		return part.Position
	end)
	if not ok or typeof(position) ~= "Vector3" then
		return nil
	end
	return position
end

local function partVisible(part)
	local ok, transparency = pcall(function()
		return part.Transparency
	end)
	if not ok or type(transparency) ~= "number" then
		return true
	end
	return transparency < 1
end

-- Where to stand: `reference` is the player's current position and is only used
-- to break a tie between two identified chests.
local function chestPosition(chest, reference)
	local parts = {}
	collectBaseParts(chest, parts)
	if #parts == 0 then
		return nil
	end

	local visible = {}
	for _, part in ipairs(parts) do
		local position = partPosition(part)
		if position ~= nil then
			table.insert(visible, { part = part, position = position, shown = partVisible(part) })
		end
	end
	if #visible == 0 then
		return nil
	end

	local shown = {}
	for _, entry in ipairs(visible) do
		if entry.shown then
			table.insert(shown, entry)
		end
	end

	-- Exactly one chest is actually on screen: that is the one the boss dropped.
	if #shown == 1 then
		return shown[1].position
	end

	local pool = if #shown > 0 then shown else visible
	if typeof(reference) ~= "Vector3" or #pool == 1 then
		return pool[1].position
	end

	local best = pool[1].position
	local bestDistance = (best - reference).Magnitude
	for index = 2, #pool do
		local distance = (pool[index].position - reference).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = pool[index].position
		end
	end
	return best
end

--[[
	LOCATING AN EVENT BOSS.

	Two passes, cheapest first:

	  1. a recursive NAME lookup for the names the live game uses ("Grim Reaper",
	     "Frankenbrute", "Scarecrow Colossus", "Pumpkin Titan"). One engine-side
	     call per name, and it finds the rig wherever the build parents it.
	  2. a bounded Lua walk of the boss-ish roots (`Workspace.Events` and any
	     direct child named like an arena), matching the `BossId` attribute. That
	     is the rename-proof half, and it never walks the whole map.

	Deliberately NO `Workspace:GetDescendants()` fallback: on this map that is
	tens of thousands of instances every half second, and it is exactly what the
	anti-lag feature exists to avoid. If a future build parents the event arena
	somewhere this cannot reach, adding its name to EVENT_ROOT_KEYWORDS is the fix.
]]
local EVENT_ROOT_KEYWORDS = { "event", "boss", "arena", "hall" }
local EVENT_SCAN_DEPTH = 5
local EVENT_SCAN_NODES = 600
local EVENT_HOLDER_CACHE = 2

local function findEventByName(root, entry)
	for _, name in ipairs(entry.names) do
		local holder = nil
		if root ~= nil then
			holder = root:FindFirstChild(name, true)
		end
		if holder == nil then
			holder = Workspace:FindFirstChild(name, true)
		end
		if holder ~= nil then
			local key = BossInfo.eventKeyFor(holder:GetAttribute(BossInfo.EVENT_ID), holder.Name)
			if key == entry.key then
				return holder
			end
		end
	end
	return nil
end

local function scanForEventIds(root, found, budget)
	if root == nil or budget.nodes <= 0 then
		return
	end
	local queue = { { object = root, depth = 0 } }
	local index = 1
	while index <= #queue and budget.nodes > 0 do
		local node = queue[index]
		index += 1
		budget.nodes -= 1
		local object = node.object
		local key = BossInfo.eventKeyFor(object:GetAttribute(BossInfo.EVENT_ID), object.Name)
		if key ~= nil and found[key] == nil then
			found[key] = object
		end
		if node.depth < EVENT_SCAN_DEPTH then
			for _, child in ipairs(object:GetChildren()) do
				table.insert(queue, { object = child, depth = node.depth + 1 })
			end
		end
	end
end

-- The live holder of every event boss, keyed by core/BossInfo's key. Cached for
-- EVENT_HOLDER_CACHE seconds; aliveness is read FRESH from the holder every
-- detect, which is what lets the fight move on to the next boss immediately.
function Boss.eventHolders(self)
	local now = os.clock()
	local cached = self.eventHolderCache
	if cached ~= nil and now - (self.eventHolderCacheAt or 0) < EVENT_HOLDER_CACHE then
		return cached
	end
	self.eventHolderCacheAt = now

	local found = {}
	local events = Workspace:FindFirstChild("Events")

	local missing = false
	for _, entry in ipairs(BossInfo.events()) do
		local holder = findEventByName(events, entry)
		if holder ~= nil then
			found[entry.key] = holder
		else
			missing = true
		end
	end

	if missing then
		local budget = { nodes = EVENT_SCAN_NODES }
		scanForEventIds(events, found, budget)
		if budget.nodes > 0 then
			for _, child in ipairs(Workspace:GetChildren()) do
				if budget.nodes <= 0 then
					break
				end
				local name = string.lower(child.Name)
				for _, keyword in ipairs(EVENT_ROOT_KEYWORDS) do
					if string.find(name, keyword, 1, true) ~= nil then
						scanForEventIds(child, found, budget)
						break
					end
				end
			end
		end
	end

	self.eventHolderCache = found
	return found
end

--[[
	The next event boss to attack, or nil. The FIRST ALIVE boss wins, walking
	core/BossInfo's list in order (Grim Reaper first): when the current target
	dies it stops being alive, the walk moves on, and Boss.approach flies over.
]]
function Boss.detectEvent(self)
	local selection = eventSelection(self.store)
	local holders = Boss.eventHolders(self)
	-- Cleared first: with nothing alive this scan the stale rig from the last one
	-- must not survive as a teleport target.
	self.eventRig = nil
	self.eventModel = nil
	for _, entry in ipairs(BossInfo.events()) do
		if eventWanted(selection, entry.key) then
			local holder = holders[entry.key]
			if holder ~= nil and holder.Parent ~= nil then
				local model = holder:FindFirstChild("Boss") or holder
				-- `bossDown`, not just "HP > 0": a defeated rig is HIDDEN in place.
				if not bossDown(holder, model) then
					-- Parked on `eventRig` so only the winner of Boss.detect writes
					-- `tracked*`, and the rig can be re-read live (livePosition).
					self.eventRig = holder
					self.eventModel = model
					return fill(
						BossInfo.empty(),
						holder,
						model,
						entry.label,
						BossInfo.EVENT_GROUP,
						BossInfo.EVENT_GROUP,
						entry.key
					)
				end
			end
		end
	end
	return nil
end

-- The event group's state, for the detector, the hop, and the read-out:
-- (anyAlive, anyPresent, aliveCount, wantedCount). wantedCount is how many the
-- user switched ON, so a page can say "2/3 存活".
function Boss.eventState(self)
	local selection = eventSelection(self.store)
	local holders = Boss.eventHolders(self)
	local alive = 0
	local present = 0
	local wanted = 0
	for _, entry in ipairs(BossInfo.events()) do
		if eventWanted(selection, entry.key) then
			wanted += 1
			local holder = holders[entry.key]
			if holder ~= nil and holder.Parent ~= nil then
				present += 1
				local model = holder:FindFirstChild("Boss") or holder
				-- Same "down" rule as the detector: a hidden corpse is DEAD, so the
				-- hop can fire instead of waiting for a boss that will never move.
				if not bossDown(holder, model) then
					alive += 1
				end
			end
		end
	end
	return alive > 0, present > 0, alive, wanted
end

--[[
	IS THIS HOLDER AN EVENT RIG? An event rig sitting in the arena folder is still
	one: it carries no rarity keyword, so without this check it is classified "?"
	(always wanted), attacked with the 70-stud arena hover, and the event switches
	are bypassed -- and the chest timer would wait on a boss that drops no chest.
]]
local function isEventRig(holder): boolean
	if holder == nil then
		return false
	end
	local attributeId = holder:GetAttribute(BossInfo.EVENT_ID)
	if typeof(attributeId) ~= "string" then
		attributeId = nil
	end
	return BossInfo.eventKeyFor(attributeId, holder.Name) ~= nil
end

--[[
	WHAT RARITY IS THIS ARENA HOLDER? The slot table first, the name second --
	and that order is the bug fix: an arena rig is called `Boss1`/`BossRainbow`,
	i.e. it carries NO rarity keyword, so the name-only lookup answered "?" for
	every fixed slot, and "?" is always-wanted -- unchecking 普通 still fought
	Boss1. A holder that is neither a slot id nor a rarity keyword stays
	genuinely unidentified (and always-wanted).
]]
local function slotRarity(name: string): string
	local fixed = BossInfo.fixed()
	local lowered = string.lower(name)
	for _, entry in ipairs(fixed) do
		if string.lower(entry.id) == lowered then
			return entry.rarity
		end
	end
	-- `BossRainbow_info`-style suffixes: the LONGEST slot id that occurs in the
	-- name wins, not the first in table order (probing in order mis-resolved
	-- decorated names, and "Boss1" hits inside "Boss10").
	local best = nil
	local bestRarity = nil
	for _, entry in ipairs(fixed) do
		local id = string.lower(entry.id)
		if string.find(lowered, id, 1, true) ~= nil and (best == nil or #id > #best) then
			best = id
			bestRarity = entry.rarity
		end
	end
	if bestRarity ~= nil then
		return bestRarity
	end
	return BossInfo.rarityFromName(name)
end

-- A holder whose Name is a fixed slot id belongs to pass 1, whichever rarity that
-- slot carries: pass 1 already answered "the user switched this rarity off", and
-- re-deciding from the name is how an unchecked slot got attacked anyway.
local function isFixedSlotName(name: string): boolean
	for _, entry in ipairs(BossInfo.fixed()) do
		if entry.id == name then
			return true
		end
	end
	return false
end

--[[
	Which holder in `Events.BossArena` is a NORMAL boss we are meant to fight?
	Two passes: the fixed slots by id (an event rig occupying a slot is skipped),
	then every other holder filtered by name rarity and `isEventRig`. Split out of
	`detectNormal` so `isNormalAlive` can ask the same question without the
	position/HP bookkeeping `fill` does.
]]
local function normalHolder(selection)
	local events = Workspace:FindFirstChild("Events")
	local arena = events ~= nil and events:FindFirstChild("BossArena") or nil
	if arena == nil then
		return nil
	end

	-- Pass 1 answers with the rarity from the SLOT TABLE, not from the name:
	-- `rarityFromName("Boss1")` is "?" (always-wanted), which would undo the
	-- whole filter one line after applying it.
	for _, entry in ipairs(BossInfo.fixed()) do
		if BossInfo.selected(entry.rarity, selection) then
			local holder = arena:FindFirstChild(entry.id)
			local model = holder ~= nil and holder:FindFirstChild("Boss") or nil
			if model ~= nil and not isEventRig(holder) and not bossDown(holder, model) then
				local info = fill(
					BossInfo.empty(),
					holder,
					model,
					holder.Name,
					entry.rarity,
					BossInfo.NORMAL_GROUP,
					nil
				)
				return holder, model, info
			end
		end
	end

	-- A rig the classifier cannot name is only wanted while the filter is wide
	-- open: once any rarity is switched off the user HAS a filter, and "?" used
	-- to be attacked no matter what was ticked ("没有勾选也会去打").
	local narrowed = BossInfo.narrowed(selection)
	for _, holder in ipairs(arena:GetChildren()) do
		local model = holder:FindFirstChild("Boss")
		if model ~= nil and not isEventRig(holder) and not bossDown(holder, model) then
			-- A slot id was already answered by pass 1; pass 2 must not
			-- reconsider it from the name.
			if not isFixedSlotName(holder.Name) then
				local rarity = slotRarity(holder.Name)
				if rarity == BossInfo.UNKNOWN then
					-- The rig's own name often carries the word when the holder's
					-- does not ("BossX" > "BossX_Rainbow").
					rarity = slotRarity(model.Name)
				end
				local wanted = if rarity == BossInfo.UNKNOWN
					then not narrowed
					else BossInfo.selected(rarity, selection)
				if wanted then
					-- The INFO RECORD is the point of this return: returning only
					-- `holder, model` made detectNormal report a live arena boss as
					-- NOT ALIVE, and the chest claim fired while it was still up.
					return holder, model, fill(
						BossInfo.empty(),
						holder,
						model,
						holder.Name,
						rarity,
						BossInfo.NORMAL_GROUP,
						nil
					)
				end
			end
		end
	end

	return nil
end

function Boss.detectNormal(self)
	local selection = selectionOf(self.store)
	local holder, model, info = normalHolder(selection)
	-- The RIG, parked next to the record instead of on `tracked*`: a detector
	-- that wrote the tracking directly here would be overwritten by the event
	-- detector a few lines later (see Boss.detect).
	self.normalRig = holder
	self.normalModel = model
	if info ~= nil then
		return info
	end

	-- Last resort: the flat attributes on Workspace, with no position at all.
	-- THE SELECTION APPLIES HERE TOO: this branch used to return a boss
	-- unconditionally, so an UNCHECKED rarity was attacked anyway.
	if Workspace:GetAttribute("BossActive") then
		local rarity = tostring(Workspace:GetAttribute("BossRarityName") or "?")
		local health = tonumber(Workspace:GetAttribute("BossHealth"))
		if BossInfo.selected(rarity, selection) and (health == nil or health > 0) then
			local flat = BossInfo.empty()
			flat.alive = true
			flat.hp = health or 0
			flat.maxHp = tonumber(Workspace:GetAttribute("BossMaxHealth")) or 0
			flat.rarity = rarity
			flat.id = tostring(Workspace:GetAttribute("BossDisplayName") or "?")
			flat.group = BossInfo.NORMAL_GROUP
			-- No rig to track: this branch exists for a build that publishes the
			-- fight only as Workspace attributes. The chest does NOT trust this
			-- group claim; it asks `Boss.arenaSlotAlive`, which only ever sees
			-- arena slots.
			return flat
		end
	end

	return nil
end

--[[
	Scan for a boss, cached for DETECT_CACHE seconds. Both groups are detected and
	`boss.priority` decides which wins ("event" first by default, since the event
	bosses are time-limited). The loser is not ignored: the moment the winner dies
	the next detect returns it.
]]
function Boss.detect(self)
	local now = os.clock()
	if now - self.cacheAt < DETECT_CACHE then
		return self.cacheInfo
	end
	self.cacheAt = now

	local normal = Boss.detectNormal(self)
	local event = Boss.detectEvent(self)
	local preferEvent = self.store:get("boss.priority") ~= "normal"

	local chosen = if preferEvent then (event or normal) else (normal or event)
	self.cacheInfo = chosen or BossInfo.empty()

	-- THE WINNER OWNS THE TRACKING, and this assignment has to happen AFTER the
	-- winner is chosen: both detectors used to write `tracked*` themselves, the
	-- event detector ran second and always won, so priority "normal" still flew
	-- to the event rig ("boss 优先级功能异常").
	if chosen ~= nil and chosen.alive == true then
		if chosen.group == BossInfo.EVENT_GROUP then
			self.trackedHolder = self.eventRig
			self.trackedModel = self.eventModel
		else
			self.trackedHolder = self.normalRig
			self.trackedModel = self.normalModel
		end
	else
		-- Nothing is tracked when nothing is alive, so `liveDown` cannot report a
		-- dead rig from a previous scan as "the current target is dead".
		self.trackedHolder = nil
		self.trackedModel = nil
	end
	return self.cacheInfo
end

--[[
	Throw away the cached detection when something makes the answer immediately
	wrong: the priority switch flipping mid-fight, and a tracked boss dying (see
	liveDown). Without it the fight keeps acting on a scan up to DETECT_CACHE old.
]]
function Boss.invalidate(self)
	self.cacheAt = 0
end

--[[
	IS THE *ARENA* GROUP ALIVE? Deliberately NOT `Boss.isAlive`: the chest timer
	was fed "is any boss alive", so fighting an EVENT boss alongside a normal one
	kept the timer's answer "alive" forever and the chest never opened. Event
	bosses drop no chest; only the arena slots do.

	RIG ONLY, the second half of the same fix: going through `detectNormal` let
	the attribute-only fallback answer (group "normal" while an event boss was
	up). And this walk is deliberately blind to the rarity filter -- an unchecked
	rarity still drops a chest, so switching one off must not clear the arena.
]]
function Boss.arenaSlotAlive(self): boolean
	local events = Workspace:FindFirstChild("Events")
	local arena = events ~= nil and events:FindFirstChild("BossArena") or nil
	if arena == nil then
		return false
	end
	for _, entry in ipairs(BossInfo.fixed()) do
		local holder = arena:FindFirstChild(entry.id)
		local model = holder ~= nil and holder:FindFirstChild("Boss") or nil
		if model ~= nil and not isEventRig(holder) and not bossDown(holder, model) then
			return true
		end
	end
	return false
end

-- Is a NORMAL boss alive, for the chest timer? Rig evidence first; the flat
-- attributes only for a build with no rigs at all, and never while an event boss
-- is up -- their pair is collective and belongs to whatever is spawning.
function Boss.isNormalAlive(self): boolean
	if Boss.arenaSlotAlive(self) then
		return true
	end
	if Boss.detectEvent(self) ~= nil then
		return false
	end
	local info = Boss.detectNormal(self)
	return info ~= nil and info.alive == true and info.group == BossInfo.NORMAL_GROUP and info.position == nil
end

-- Where the tracked rig is RIGHT NOW, or nil.
function Boss.livePosition(self)
	local model = self.trackedModel
	if model == nil or model.Parent == nil then
		return nil
	end
	return objectPosition(model)
end

-- Is the tracked rig dead RIGHT NOW? nil when there is nothing to check.
function Boss.liveDown(self)
	local holder = self.trackedHolder
	local model = self.trackedModel
	if holder == nil or model == nil or holder.Parent == nil or model.Parent == nil then
		return nil
	end
	return bossDown(holder, model)
end

function Boss.isAlive(self): boolean
	return Boss.detect(self).alive
end

function Boss.status(self): string
	return BossInfo.describe(Boss.detect(self))
end

function Boss.info(self)
	return Boss.detect(self)
end

--[[
	ARE WE IN THE HALLOWED GYM? `Players.<me>.currentMap` (a StringValue, live
	value "Hallowed Gym") is the game's own answer; the character's
	`InHalloweenArena` attribute is the fallback for a renamed display string.
	Both are read fresh: this decides whether the fight may start at all.
]]
local function inHallowedGym(): boolean
	local user = Players.LocalPlayer
	if user ~= nil then
		local map = user:FindFirstChild("currentMap")
		if map ~= nil and map:IsA("StringValue") then
			local name = string.lower(tostring(map.Value))
			if string.find(name, "hallowed", 1, true) ~= nil
				or string.find(name, "halloween", 1, true) ~= nil then
				return true
			end
		end
		local character = user.Character
		if character ~= nil and character:GetAttribute("InHalloweenArena") == true then
			return true
		end
	end
	return false
end

local ARENA_REACH = 250
--[[
	HOW OFTEN THE TRAVEL MAY BE ASKED FOR AGAIN. Was 4 seconds, the reported
	"前往万圣节健身房太慢": the stamp is taken at DISPATCH, and an accepted travel
	takes about a second to show in `Players.<me>.currentMap`, so the client sat
	blind for three more seconds -- and the attempt cap then gave up and fought
	from outside. Half a second is still far more than a round trip, and the
	character is re-snapped to the mark while waiting.
]]
local TRAVEL_RETRY = 0.5
-- The staging snap is re-issued on this cadence while the travel is in flight.
local STAGING_RESNAP = 0.1
-- HOW MANY DISPATCHES BEFORE GIVING UP AND FIGHTING FROM WHERE WE STAND. Was 3
-- (one and a half seconds), shorter than the accepted travel takes to appear, so
-- the fight regularly began OUTSIDE the gym; eight dispatches over four seconds
-- gives the map a real chance to catch up.
local TRAVEL_ATTEMPT_LIMIT = 8
-- THE HARD DEADLINE, in seconds since the first dispatch: the backstop for the
-- case where NOTHING ever changes (remote missing, area refused). After it the
-- feature proceeds and says so once, rather than standing there forever.
local TRAVEL_DEADLINE = 6
--[[
	THE STAGING POINT: be at 283, 19, 372 FIRST, then fire `areaTravelRemote`
	(firing it from wherever the player is does not take -- "前往 boss 前并没有按
	我的要求先传送到我给你的坐标，然后再触发传送门的 Event").

	BUT THE COORDINATE IS NOT VERIFIED, per the user's own instruction: snap there,
	wait one beat, fire. A large character can be *at* the point and still read as
	"not there" (server pushes the root off the spot, or the snap is rejected), and
	a gate that waits for the position to agree never opens ("前往圣诞节健身房时会
	卡住"). The position is where we PUT the character, not something we require
	back.
]]
local HALLOWED_STAGING = Vector3.new(283, 19, 372)
local STAGING_REACH = 25
-- The beat between the snap and the event: the server has to move the character
-- before the area travel is accepted, and one frame is not enough.
local TRAVEL_BEAT = 0.12

-- The staging point is not something we read back -- see HALLOWED_STAGING: a
-- "walk there, then check you arrived" protocol is the one that stalls forever
-- whenever the snap is rejected, and none of that machinery exists here.

--[[
	Travel to the Hallowed Gym through the game's own remote:

	    ReplicatedStorage.rEvents.areaTravelRemote:InvokeServer("travelToArea", circle)

	`InvokeServer` on a RemoteFunction YIELDS, and this is reached from a scheduler
	tick that runs inside the Heartbeat callback -- invoking it inline would stall
	the whole frame loop for a network round trip, so it runs in a task.spawn (the
	same reasoning as Rejoin's blocking HTTP call).

	Returns true when an attempt was dispatched (so the caller can count it).
]]
function Boss.requestTravel(self): boolean
	-- STEP 1: PUT THE CHARACTER ON THE MARK, deliberately without checking
	-- afterwards (see HALLOWED_STAGING). `snap` also cancels any staged walk and
	-- motion hold, which stops a big character from being dragged back off the
	-- spot while the event is fired.
	if self.teleport ~= nil then
		local ok, position = pcall(function()
			local root = self.character:requireRoot()
			return if root ~= nil then root.Position else nil
		end)
		if ok and typeof(position) == "Vector3" and (position - HALLOWED_STAGING).Magnitude > 1 then
			pcall(function()
				self.teleport:snap(HALLOWED_STAGING, "boss")
			end)
		end
	end

	local remote = Remotes.areaTravel()
	local circle = Remotes.hallowedGymCircle()
	if remote == nil or circle == nil then
		self.notify("找不到 areaTravelRemote / hallowedGymCircle，无法自动前往万圣节健身房", "warn")
		return false
	end

	-- STEP 2: FIRE THE EVENT, ONE BEAT LATER, so the server has processed the
	-- position first. Scheduled rather than slept through: this runs in a tick.
	local function fire()
		pcall(function()
			if remote:IsA("RemoteFunction") then
				remote:InvokeServer("travelToArea", circle)
			else
				remote:FireServer("travelToArea", circle)
			end
		end)
	end
	-- ALWAYS IN A task.spawn: `Timers:after` callbacks run INLINE from the single
	-- Heartbeat loop, and `InvokeServer` yields, which stalled the whole frame for
	-- a round trip. The beat is still scheduled so the server sees the position
	-- first; only the invoke moved off the frame.
	if self.timers ~= nil then
		self.timers:after(os.clock(), TRAVEL_BEAT, function()
			task.spawn(fire)
		end)
	else
		task.spawn(fire)
	end
	return true
end

--[[
	DO NOT PUNCH AN EVENT BOSS FROM OUTSIDE THE ARENA: if the game says we are not
	in "Hallowed Gym", travel there first -- fighting from outside is how the
	character ends up dead instead of farming. Returns true when it is safe to
	proceed this frame; three exits so a broken remote cannot stall forever: the
	map says Hallowed Gym; the target is already within ARENA_REACH (the map string
	is the stale thing); TRAVEL_ATTEMPT_LIMIT tries and still not there (warn once,
	proceed). Otherwise ask the remote and wait, rate limited by TRAVEL_RETRY.
]]
function Boss.ensureArena(self, now, info): boolean
	if inHallowedGym() then
		self.travelAt = 0
		self.travelTries = 0
		self.travelFirstAt = 0
		self.travelGaveUp = false
		self.travelWarned = false
		return true
	end

	-- STAND ON THE MARK WHILE THE TRAVEL IS IN FLIGHT: Boss.approach releases its
	-- hold the moment this returns false, so without a re-snap the server pulls
	-- the character back toward its last acknowledged position. Re-issued on a
	-- short cadence rather than every frame because `snap` also cancels the
	-- Motion hold.
	local root = self.character:requireRoot()
	local position = if root ~= nil then root.Position else nil
	if typeof(position) == "Vector3" and (position - HALLOWED_STAGING).Magnitude > STAGING_REACH then
		if now - (self.stagingAt or 0) >= STAGING_RESNAP and self.teleport ~= nil then
			self.stagingAt = now
			self.teleport:snap(HALLOWED_STAGING, "boss")
		end
	end

	if typeof(info.position) == "Vector3" and typeof(position) == "Vector3"
		and (position - info.position).Magnitude <= ARENA_REACH then
		return true
	end

	-- THE DEADLINE ONLY COUNTS ATTEMPTS WE ACTUALLY MADE. `travelFirstAt` starts
	-- at 0 while `now` is os.clock() (always far past 6 on a loaded client), so
	-- the old `now - travelFirstAt > TRAVEL_DEADLINE` was true on the very FIRST
	-- call: it gave up before firing a single remote, latched traveledGaveUp, and
	-- the latch only cleared once the character was ALREADY inside the gym -- the
	-- reported "前往万圣节健身房太慢", which never started at all.
	local tries = self.travelTries or 0
	local timedOut = tries > 0 and (self.travelFirstAt or 0) > 0
		and now - self.travelFirstAt > TRAVEL_DEADLINE
	if tries >= TRAVEL_ATTEMPT_LIMIT or timedOut then
		if self.travelGaveUp ~= true then
			self.travelGaveUp = true
			self.notify("多次传送都没到万圣节健身房，仍尝试直接打（检查 areaTravelRemote）", "warn")
		end
		return true
	end

	-- ONE SPEED NOW (the mark is where we PUT the character, not something we read
	-- back), and THE FIRST DISPATCH IS IMMEDIATE: the old shape stamped travelAt
	-- and bailed before the first dispatch, so every fight began half a second
	-- late.
	if (self.travelTries or 0) > 0 and now - (self.travelAt or 0) < TRAVEL_RETRY then
		return false
	end
	if (self.travelTries or 0) == 0 then
		self.travelFirstAt = now
	end
	self.travelAt = now
	if self.travelWarned ~= true then
		self.travelWarned = true
		self.notify("不在万圣节健身房：传送到集结点后直接触发区域传送", "info")
	end
	if Boss.requestTravel(self) then
		self.travelTries = (self.travelTries or 0) + 1
	end
	return false
end

--[[
	Get onto the boss, properly. The old shape was ONLY a motion hold
	(setTarget + begin, then Motion.apply rewrites the CFrame every frame), which
	pinned the character where it started instead of carrying it to a distant
	boss, and skipped begin() entirely when a hold was already active.

	The fix is the PIN: the hold is armed on the first tick (see Boss.approach) and
	Motion.apply writes the hover position every RenderStepped -- about 0.016 s,
	tighter than the 0.025 s the user asked for -- wherever the boss moves to.
	No walk, no approach interval, no arrival distance.
]]
--[[
	Hover height above the boss: close enough for the punches to land, high enough
	that the boss's own attacks mostly miss. These are FIXED geometry facts per
	rig (normal arena 70 studs for all six slots; Grim Reaper 50; Frankenbrute 120,
	far taller; Scarecrow Colossus 24; Pumpkin Titan 50), and they live in
	core/BossInfo next to the boss they belong to.
]]
local function hoverHeight(store, info)
	if info ~= nil and info.group == BossInfo.EVENT_GROUP then
		local entry = BossInfo.event(info.eventKey)
		if entry ~= nil and entry.hover >= 1 then
			return entry.hover
		end
		return BossInfo.EVENT_HOVER
	end
	return BossInfo.NORMAL_HOVER
end

-- The legacy downward gaze: 45 degrees below the line to the target. See
-- Motion.apply for why the tilt is what makes a punch land.
local function lookBias(store)
	if store:get("kill.lookDown") == false then
		return nil
	end
	return Vector3.new(0, -1, 0)
end

-- Let go of the body -- but only if the hold is OURS. A hold in mode "boss" was
-- started here; anything else (chest walk, teleport, combat approach, machine
-- mount) belongs to another subsystem and must not be torn down from this file.
function Boss.releaseHold(self): boolean
	if self.motion == nil then
		return false
	end
	local ok, mode = pcall(function()
		return self.motion:mode()
	end)
	if not ok or mode ~= "boss" then
		return false
	end
	pcall(function()
		self.motion:finish()
	end)
	return true
end

-- Is a chest waiting for the body right now? True only while the chest task is
-- on AND its timer says a chest is READY -- not while waiting out
-- boss.chestDelay, so the fight keeps going during the delay.
function Boss.chestPending(self): boolean
	return self.store:get("boss.autoChest") == true and self.chestClaim == true
end

-- Is the GYM MACHINE holding the body right now? A function rather than a value
-- because Machine is installed AFTER Boss in main.luau. While this answers true
-- the machine owns the body (machine.overridesCombat), so the fight must not pin
-- the character off the seat.
function Boss.machineHeld(self): boolean
	local check = self.machineSeated
	if type(check) ~= "function" then
		return false
	end
	local ok, seated = pcall(check)
	return ok and seated == true
end

function Boss.approach(self, now)
	local info = self.detect(self)

	-- THE CHEST OUTRANKS THE FIGHT ("捡宝箱的任务高于打 boss"). A boss fight HOLDS
	-- the body, so while a chest is waiting to be looted the fight has to let go
	-- -- and BEFORE it decides anything else, because a normal boss dying while
	-- an event boss is up is exactly the reported case.
	if Boss.chestPending(self) then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	-- THE MACHINE, WHEN IT WAS ALLOWED TO WIN: `machine.overridesCombat` lets the
	-- gym machine keep the seat while a fight runs, and a hover hold sets
	-- PlatformStand and stands the player up out of it.
	if Boss.machineHeld(self) then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	-- NO LIVE TARGET -> LET GO. This early return used to leave the hold active,
	-- which kept the character frozen on the spot after the boss died. Only a hold
	-- this subsystem owns is released.
	if not info.alive or typeof(info.position) ~= "Vector3" then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	-- DEATH IS CHECKED LIVE, not from the 0.5 s old scan: one attribute read is
	-- cheap enough per frame, and the moment it says dead the cache is dropped so
	-- the NEXT detect returns the next boss of the sequence.
	if Boss.liveDown(self) == true then
		Boss.invalidate(self)
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	local root = self.character:requireRoot()
	if root == nil then
		return
	end
	local ok, position = pcall(function()
		return root.Position
	end)
	if not ok or typeof(position) ~= "Vector3" then
		return
	end

	-- Remembered BEFORE we move, so a boss that dies mid-fight leaves the player
	-- near where they came in rather than stranded above an empty arena.
	self.lastPosition = position

	-- EVENT BOSSES ARE ONLY FOUGHT FROM INSIDE THE HALLOWED GYM: from outside, the
	-- fight asks the game's own area travel remote and stands down until it lands.
	if info.group == BossInfo.EVENT_GROUP and not Boss.ensureArena(self, now, info) then
		Boss.releaseHold(self)
		self.engaged = false
		return
	end

	-- WHERE THE BOSS IS *NOW*, not where the last scan saw it: info.position is up
	-- to DETECT_CACHE (0.5 s) old, and pinning to that glued the character to
	-- where a walking boss had been.
	local target = Boss.livePosition(self) or info.position

	-- Hover height: close enough for the punches to land, high enough that the
	-- boss's own attacks mostly miss.
	local destination = target + Vector3.new(0, hoverHeight(self.store, info), 0)

	-- PIN THE BODY ON THE BOSS -- NOW, EVERY FRAME. Was: stage a walk there while
	-- farther than 12 studs, and start the hold only on arrival, which took a
	-- second or more to reach a distant boss and did nothing at all when another
	-- hold was already active. The motion hold re-writes the CFrame on
	-- RenderStepped (~0.016 s), so setTarget re-aims an active hold and the pin
	-- then follows the boss wherever it moves.
	self.approachAt = now
	if self.teleport ~= nil and Teleport.isBusy(self.teleport) then
		-- A staged walk in flight would fight the pin (and be cancelled by it).
		Teleport.cancel(self.teleport)
	end

	-- THE PIN: EVERY FRAME, WITH THE FACING. Was gated to one write per
	-- PIN_INTERVAL (0.025 s), which read as "not holding" -- the direct write is
	-- unconditional and one per frame is tighter than asked for. Position AND
	-- rotation go in the SAME write on purpose: a punch is aimed from the root's
	-- CFrame, so a position-only pin leaves the glove pointing elsewhere.
	local pinned = false
	if self.teleport ~= nil and self.store:get("boss.directPin") ~= false then
		self.pinAt = now
		pinned = self.teleport:pin(destination, target, lookBias(self.store), "boss")
	end

	self.motion:setTarget(destination)
	if not self.motion:isActive() then
		self.motion:begin({
			pos = destination,
			mode = "boss",
			look = target,
			lookBias = lookBias(self.store),
		})
	end
	-- FACE the boss, tilted down: without this the hold wrote a CFrame with no
	-- rotation and the punches went nowhere near the target.
	self.motion:setLook(target, lookBias(self.store))

	-- Everything above is the "stand down" path; reaching here means the body is
	-- being driven. The HOLD IS THE PROOF: `begin`/`pin` can both refuse the body
	-- slot (a higher-priority task owns it), and reporting `engaged` anyway kept
	-- the machine off the seat and the tool arbiter out of the hand for a fight
	-- that was not actually writing the character.
	self.engaged = self.motion:isActive() or pinned == true
end

--[[
	Leave the boss area when the boss task turns off. V1007's onDisable did three
	things; only the punch stop had been ported, so turning auto-boss off left the
	character frozen 70 studs above an empty arena -- "the script broke" rather
	than "the feature is off".
]]
function Boss.leave(self)
	if self.pets ~= nil then
		Pets.scheduleSwap(self.pets, "train", 0.5)
	end

	-- Put the body back, restoring the size EXPLICITLY rather than waiting for the
	-- size task to notice: SizePolicy.wanted gates the boss branch on `bossAlive
	-- AND boss.sizeEnabled`, so switching auto-boss OFF while the boss is still
	-- alive does not change what the policy wants and the player stays enlarged.
	-- Only when the user has no size setting of their own -- otherwise Size.tick
	-- owns the value and forcing 1 here would fight it.
	local size = self.sizeRef
	if type(size) == "function" then
		size = size()
	end
	if size ~= nil and self.store:get("size.selfEnabled") ~= true then
		size.last = nil
		size:apply(1)
	end

	local destination = nil
	if typeof(self.lastPosition) == "Vector3" then
		destination = self.lastPosition + Vector3.new(0, 5, 0)
	end

	-- Ours only: this used to be `self.motion:finish()` unconditionally, so turning
	-- auto-boss off tore down whatever hold owned the body (a machine mount, the
	-- chest walk) instead of only the fight's pin.
	Boss.releaseHold(self)
	if destination ~= nil and self.teleport ~= nil then
		-- hold = false: arrive and hand control straight back. Without a recorded
		-- position there is nothing better to do than release, which finish()
		-- already did.
		self.teleport:walk(destination, { mode = "tp", hold = false, job = "boss" })
	end
	self.lastPosition = nil
end

--[[
	Open whatever the chest responds to. Three mechanisms, because chests are
	inconsistent: a ProximityPrompt, a ClickDetector, or plain touch interest,
	plus the E key for prompts that only react to real input. The release steps
	(touch end, key up) are scheduled rather than task.wait-ed: the original
	blocked a coroutine for 0.05 s, and a blocked task cannot be cancelled when
	the script unloads.
]]
function Boss.interact(self, chest)
	local root = self.character:requireRoot()
	for _, object in ipairs(chest:GetDescendants()) do
		if object:IsA("ProximityPrompt") and object.Enabled then
			if type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, object)
			end
		elseif object:IsA("ClickDetector") then
			if type(fireclickdetector) == "function" then
				pcall(fireclickdetector, object)
			end
		elseif object:IsA("BasePart") and object.CanTouch and object.Transparency < 1 then
			if type(firetouchinterest) == "function" and root ~= nil then
				pcall(firetouchinterest, object, root, 0)
				self.timers:after(os.clock(), TOUCH_TAIL, function()
					-- The chest can be destroyed (looted, streamed out, boss
					-- reset) inside the 0.05s tail; firing the release at a dead
					-- instance is pointless and can raise.
					if object.Parent == nil then
						return
					end
					pcall(firetouchinterest, object, root, 1)
				end)
			end
		end
	end

	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
	end)
	self.timers:after(os.clock(), TOUCH_TAIL, function()
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		end)
	end)
end

function Boss.chestTick(self, now)
	self.chest:configure({
		delay = tonumber(self.store:get("boss.chestDelay")) or nil,
	})

	-- THE CHEST WATCHES THE *ARENA* GROUP, NOT "ANY BOSS": Boss.isAlive answers
	-- "is a boss of EITHER group alive", so an event boss kept the timer's answer
	-- "alive" forever and the normal boss's death -- which drops the chest -- was
	-- never observed. Event bosses drop no chest.
	local status = self.chest:observe(Boss.isNormalAlive(self), now)
	self.chestStatus = status
	if status ~= "ready" then
		self.chestClaim = false
		-- A fresh death re-arms everything: the next chest is a new chest.
		self.chestLootedAt = nil
		return
	end

	-- HAND THE BODY BACK ONCE IT IS OPENED: the timer keeps saying "ready" for
	-- the rest of its 60 s window, and the claim is what makes the fight stand
	-- down, so without this the fight would pause for a minute after every chest.
	if self.chestLootedAt ~= nil and now - self.chestLootedAt > CHEST_HOLD then
		self.chestClaim = false
		return
	end

	local chest = Workspace:FindFirstChild("BossChest")
	local root = self.character:requireRoot()
	local origin = nil
	if root ~= nil then
		local ok, position = pcall(function()
			return root.Position
		end)
		if ok and typeof(position) == "Vector3" then
			origin = position
		end
	end
	local position = chestPosition(chest, origin)
	if position == nil or position.Y < -100 then
		self.chestClaim = false
		return
	end
	local stand = position + Vector3.new(0, CHEST_STAND_HEIGHT, 0)

	-- THE CLAIM GOES UP BEFORE THE WALK: Boss.approach yields the body while this
	-- is true. Set here (the chest task runs FIRST: priority 430 against the boss's
	-- 410) so the boss task in the same frame already sees it.
	self.chestClaim = true

	-- FALLING SHORT OF THE CHEST COUNTS AS "NOT THERE YET". The chest walk lands
	-- the player above the rig, the verification hold releases, and anything that
	-- puts the character BELOW that point (arena pull, missed hop, the void under
	-- a stadium) left the task hammering E from a position the prompt could not
	-- reach while `nearby` still compared only the HELD position. A large downward
	-- error is now a failed approach: re-walk until the chest window closes.
	local fell = origin ~= nil and (origin.Y < stand.Y - 40 or origin.Y < -50)

	local current = self.motion:targetPosition()
	local nearby = self.motion:isActive()
		and typeof(current) == "Vector3"
		and (current - stand).Magnitude <= 5
		and not fell
	if not nearby then
		-- STAND ~15 STUDS ABOVE THE CHEST'S BASE PART: walking at the part itself
		-- lands the character inside the rig, while the prompt's reachable volume
		-- is above it (the legacy offset of 5 put the player on the hinge line,
		-- where E often did nothing).
		self.teleport:walk(stand, { mode = "chest", arc = 120, job = "chest" })
		-- Re-walking owns the character; interacting from here would fire at a
		-- prompt the player is not in range of yet.
		return
	end

	-- Once every 0.4s. Interaction is not rate limited on the wire, but clicking
	-- E every frame is pointless and noisy.
	if now - self.lastInteract < INTERACT_INTERVAL then
		return
	end
	self.lastInteract = now
	Boss.interact(self, chest)
	-- ONE CHEST, ONE COUNT. The counter lives on the chest -- not on every press of
	-- E: `interact` runs every 0.4 s for as long as CHEST_HOLD keeps the claim, so
	-- counting there reported ten "loots" for a single chest.
	if self.chestLootedAt == nil then
		self.loots += 1
		self.chestLootedAt = now
	end
end

-- Save the config, before a hop. Best-effort and reported: a hop must still
-- happen if the write fails (an executor without a filesystem is legitimate), but
-- the user is told, because "my settings were not saved" is otherwise invisible.
function Boss.saveBeforeHop(self)
	local persist = self.persist
	if persist == nil or persist.save == nil then
		return false
	end
	local ok, saved, err = pcall(function()
		return persist.save(self.store)
	end)
	if not ok then
		self.notify("换服前保存配置失败：" .. tostring(saved), "warn")
		return false
	end
	if saved ~= true then
		self.notify("换服前保存配置失败：" .. tostring(err), "warn")
		return false
	end
	return true
end

function Boss.requestHop(self, reason): boolean
	local rejoin = self.rejoin
	if rejoin == nil then
		self.notify("活动 Boss 已清空，但重进模块不可用", "warn")
		return false
	end

	-- SAVE FIRST, THEN LEAVE -- the one step of the hop the user asked for by name
	-- ("换服前也会自动触发一次保存配置"). BEFORE the countdown so the write has
	-- happened by the time the dialog appears; a save that raced the teleport
	-- would sometimes not happen at all.
	Boss.saveBeforeHop(self)

	local mode = self.store:get("boss.event.hopMode")
	if type(mode) ~= "string" or mode == "" then
		mode = "sparse"
	end
	local ok, result = pcall(function()
		return rejoin:requestNow(reason, mode)
	end)
	if not ok then
		self.notify("换服请求失败：" .. tostring(result), "warn")
		return false
	end
	return result == true
end

function Boss.eventStatus(self): string
	local _, _, aliveCount, wanted = Boss.eventState(self)
	if wanted == 0 then
		return "活动 Boss：已关闭"
	end
	if aliveCount > 0 then
		local info = Boss.detectEvent(self)
		local label = if info ~= nil then info.id else "?"
		if not inHallowedGym() and (self.travelTries or 0) > 0 then
			return string.format("活动 Boss：正在前往万圣节健身房（目标 %s）", label)
		end
		return string.format("活动 Boss：%d/%d 存活 · 正在打 %s", aliveCount, wanted, label)
	end
	return "活动 Boss：等待刷新"
end

function Boss.stats(self)
	local info = Boss.detect(self)
	return {
		alive = info.alive,
		id = info.id,
		rarity = info.rarity,
		hp = info.hp,
		loots = self.loots,
		-- Published for the machine and the training task; see `engaged` in the
		-- state table. `alive` answers "is one on the map", this answers "are we
		-- on it", and the two callers need the second.
		engaged = self.engaged == true,
	}
end

function Boss.install(context)
	local self = Boss.new(context)
	local store = self.store

	self.scheduler:register({
		id = "boss",
		priority = 410,
		enabled = function()
			return store:get("boss.auto") == true
		end,
		onDisable = function()
			-- The hold is dropped here too, so the published answer must not stay
			-- "engaged" after the task went away -- a stale true would keep the
			-- machine off the seat until the next time a boss showed up.
			self.engaged = false
			Boss.leave(self)
		end,
		tick = function(_dt, now)
			Boss.approach(self, now)
		end,
	})

	--[[
		THE CHEST OUTRANKS THE FIGHT ("宝箱是最最尖端的优先级"). Priority 430 puts it
		above the boss task (410) and its punch task (385), so on the frame a chest
		becomes ready the claim is already up when Boss.approach runs.
	]]
	self.scheduler:register({
		id = "chest",
		priority = 430,
		enabled = function()
			return store:get("boss.autoChest") == true
		end,
		onDisable = function()
			self.chestClaim = false
			self.chestStatus = "idle"
		end,
		tick = function(_dt, now)
			Boss.chestTick(self, now)
		end,
	})

	-- Changing the priority takes effect NOW: Boss.detect caches its scan for
	-- DETECT_CACHE, so without this the switch looked stuck for up to half a second
	-- while the OLD target's hold still had the character.
	store:subscribe("boss.priority", function()
		Boss.invalidate(self)
	end)
	-- The same for the two group switches: turning the event bosses off should
	-- move the fight to the arena immediately, not after a cached scan.
	for _, path in ipairs({ "boss.event.enabled", "boss.auto" }) do
		store:subscribe(path, function()
			Boss.invalidate(self)
		end)
	end

	return self
end

return Boss
end

__modules["game/Size"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Size -- applying the self-resize decided by core/SizePolicy.

	One guarded remote call, driven by a change detector; the policy itself is
	unit-tested in core/SizePolicy.
]]

local SizePolicy = require("core/SizePolicy")
local Remotes = require("game/Remotes")

local Size = {}
Size.__index = Size

function Size.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		isBossAlive = context.isBossAlive or function()
			return false
		end,
		last = nil,
		applied = 0,
	}, Size)
	return self
end

function Size.apply(self, multiplier)
	local remote = Remotes.size()
	if remote == nil then
		return false
	end
	local ok = pcall(function()
		if remote:IsA("RemoteFunction") then
			remote:InvokeServer("changeSize", multiplier)
		else
			remote:FireServer("changeSize", multiplier)
		end
	end)
	if ok then
		self.applied += 1
	end
	return ok
end

function Size.tick(self)
	local wanted = SizePolicy.wanted({
		bossAlive = self.isBossAlive(),
		bossSizeEnabled = self.store:get("boss.sizeEnabled") == true,
		bossSizeMul = tonumber(self.store:get("boss.sizeMul")) or 1,
		selfSizeEnabled = self.store:get("size.selfEnabled") == true,
		selfSizeMul = tonumber(self.store:get("size.selfMul")) or 1,
	})

	local send = SizePolicy.transition(self.last, wanted)
	if send == nil then
		return
	end
	self.last = send
	Size.apply(self, send)
end

-- Called when the script shuts down, so the player is not left enlarged.
function Size.restore(self)
	self.last = nil
	Size.apply(self, 1)
end

function Size.install(context)
	local self = Size.new(context)
	self.scheduler:register({
		id = "size",
		priority = 120,
		enabled = function()
			return true
		end,
		tick = function()
			Size.tick(self)
		end,
	})
	return self
end

return Size
end

__modules["core/CrystalList"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	CrystalList -- the crystal catalogue, as pure data handling.

	The game publishes every crystal under
	`ReplicatedStorage.shared.catalogs.crystalChances`, one child per crystal
	("Hallowed Crystal", "Overcharged Crystal", ...) whose CHILDREN are that
	crystal's possible pets. Prices live next door in `crystalPrices`, as
	`{ price = <number>, priceType = "Gems" | "CandyCorn" | ... }`.

	This module only turns those tables into lists, so the shape is testable
	without a game. The engine reads live in game/Crystals.

	Ordering is the specification, as everywhere else in this project: sorted by
	name, so a dropdown does not reshuffle between scans.
]]

local CrystalList = {}

export type Entry = {
	name: string,
	price: number?,
	priceType: string?,
	label: string,
}

-- Every crystal, sorted, with its price when the catalogue has one.
--
-- `chances` is the `crystalChances` folder's shape as a plain table: key -> any
-- truthy value. Only the KEYS matter, which lets the same function serve the
-- live folder (keys read by the caller) and a test fixture.
function CrystalList.parse(chances: { [string]: any }?, prices: { [string]: any }?): { Entry }
	local out: { Entry } = {}
	if chances == nil then
		return out
	end
	-- The keys are copied out with `tostring` and SORTED first: `pairs` over a
	-- table typed as `{ [string]: any }` yields `unknown` for the key in this
	-- analyzer (building the record inline was a type error), and sorting makes
	-- the output order a property of this function rather than of the hash
	-- iteration.
	local names: { string } = {}
	for rawName in pairs(chances) do
		table.insert(names, tostring(rawName))
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local price = nil
		local priceType = nil
		local record = prices ~= nil and prices[name] or nil
		if type(record) == "table" then
			price = tonumber((record :: any).price)
			local kind = (record :: any).priceType
			if type(kind) == "string" then
				priceType = kind
			end
		end
		-- Built from TYPED locals rather than an inline `if`-expression: the
		-- analyzer resolved the nested one as `unknown` and reported "Expected
		-- this to be 'string', but got 'unknown'" at the `string.format` call.
		local label: string = name
		if price ~= nil and price > 0 then
			local kind: string = "价格"
			if priceType ~= nil then
				kind = priceType
			end
			local amount: string = tostring(math.floor(price))
			-- Concatenation rather than `string.format`: the analyzer resolved the
			-- format arguments as `unknown` and reported the same "Expected this to
			-- be 'string'" error on a call that is well typed. Output is identical.
			label = tostring(name) .. "（" .. tostring(kind) .. " " .. amount .. "）"
		end
		table.insert(out, { name = name, price = price, priceType = priceType, label = label })
	end
	return out
end

function CrystalList.has(entries: { Entry }, name: string?): boolean
	if name == nil or name == "" then
		return false
	end
	for _, entry in ipairs(entries) do
		if entry.name == name then
			return true
		end
	end
	return false
end

-- The display labels, in list order.
function CrystalList.labels(entries: { Entry }): { string }
	local out: { string } = {}
	for _, entry in ipairs(entries) do
		table.insert(out, entry.label)
	end
	return out
end

function CrystalList.labelFor(entries: { Entry }, name: string?): string
	if name == nil or name == "" then
		return ""
	end
	for _, entry in ipairs(entries) do
		if entry.name == name then
			return entry.label
		end
	end
	return name
end

--[[
	The reverse: the NAME behind a display label.

	THE DROPDOWN MUST NOT PARSE ITS OWN LABELS. A label is
	`<name>（<kind> <amount>）` for a priced crystal and the bare name otherwise, and
	the Halloween crystal is the one that carries a price -- so it is the one whose
	label differs from the name the remote takes. Stripping at "（" only works
	while the separator is exactly the full-width character: any format change
	hands the WHOLE label to the server as a crystal name, which then matches
	nothing (nothing opens) and breaks the per-crystal sell map.

	Exact label lookup cannot drift, because the option list is built from these
	same entries (`CrystalList.labels`). An unknown label is returned unchanged so
	the caller can still fall back to the old stripping.
]]
function CrystalList.nameForLabel(entries: { Entry }, label: string?): string
	if label == nil or label == "" then
		return ""
	end
	for _, entry in ipairs(entries) do
		if entry.name == label or entry.label == label then
			return entry.name
		end
	end
	return label
end

--[[
	The auto-sell payload.

	The game's own shape (from a Cobalt recording of the game calling itself):

	    { Pets = { ["Candy Cube"] = true, ... }, Enabled = <bool>, Auras = {} }

	i.e. a SET of pet names to sell, and the set is what the user CHOSE for this
	crystal: "实际上应该是让我来选择出售哪些宠物，就是该水晶的哪些宠物，并且都是
	会保留的". Anything not in the set is kept by the game -- the old code filled the
	set with the crystal's entire pool, so "auto sell" meant "sell everything".
]]
function CrystalList.sellNames(
	byCrystal: { [string]: any }?,
	crystal: string?
): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if byCrystal == nil or crystal == nil or crystal == "" then
		return out
	end
	local entry = byCrystal[crystal]
	if type(entry) ~= "table" then
		return out
	end
	for name, wanted in pairs(entry) do
		-- Only names the user ticked: `false` means "keep", the same as absent for
		-- the payload, so a UI that stores `false` cannot accidentally sell a pet.
		if type(name) == "string" and name ~= "" and wanted == true then
			out[name] = true
		end
	end
	return out
end

-- How many pets are selected for one crystal (the UI's read-out).
function CrystalList.sellCount(byCrystal: { [string]: any }?, crystal: string?): number
	local sell = CrystalList.sellNames(byCrystal, crystal)
	local count = 0
	for _ in pairs(sell) do
		count += 1
	end
	return count
end

function CrystalList.isMarked(byCrystal: { [string]: any }?, crystal: string?, pet: string?): boolean
	if byCrystal == nil or crystal == nil or pet == nil then
		return false
	end
	local entry = byCrystal[crystal]
	if type(entry) ~= "table" then
		return false
	end
	return entry[pet] == true
end

--[[
	Set one pet's mark, returning a NEW map.

	Immutable on purpose: the caller writes the result into the store, and the
	store's "one source of truth" rule is what keeps the checkbox and the payload
	from disagreeing.
]]
function CrystalList.withMark(
	byCrystal: { [string]: any }?,
	crystal: string?,
	pet: string?,
	marked: boolean
): { [string]: any }
	local out: { [string]: any } = {}
	if byCrystal ~= nil then
		for rawKey, value in pairs(byCrystal) do
			local key = tostring(rawKey)
			local copy: { [string]: boolean } = {}
			if type(value) == "table" then
				-- Keys narrowed with `type(...) == "string"`, not assumed: `pairs`
				-- over an `any`-valued table hands the analyzer `unknown`, which is a
				-- type error when indexing a `{ [string]: boolean }`.
				for rawName, flag in pairs(value) do
					if type(rawName) == "string" then
						copy[rawName] = flag == true
					end
				end
			end
			out[key] = copy
		end
	end
	if crystal == nil or crystal == "" or pet == nil or pet == "" then
		return out
	end
	local entry = out[crystal]
	if type(entry) ~= "table" then
		entry = {}
		out[crystal] = entry
	end
	entry[pet] = marked == true
	return out
end

-- Mark every pet of `pool` at once (全选 / 全不选).
function CrystalList.withPoolMark(
	byCrystal: { [string]: any }?,
	crystal: string?,
	pool: { string }?,
	marked: boolean
): { [string]: any }
	local out = CrystalList.withMark(byCrystal, crystal, nil, false)
	if crystal == nil or crystal == "" or pool == nil then
		return out
	end
	local entry: { [string]: boolean } = {}
	for _, pet in ipairs(pool) do
		if type(pet) == "string" and pet ~= "" then
			entry[pet] = marked == true
		end
	end
	out[crystal] = entry
	return out
end

function CrystalList.sellPayload(sell: { [string]: boolean }, enabled: boolean?): { [string]: any }
	return {
		Pets = sell,
		Enabled = enabled == true,
		Auras = {},
	}
end

-- The pool names of one crystal, sorted, given the folder's shape.
function CrystalList.pool(pools: { [string]: { [string]: any } }?, name: string?): { string }
	local out: { string } = {}
	if pools == nil or name == nil then
		return out
	end
	local pool = pools[name]
	if pool == nil then
		return out
	end
	-- `tostring` for the same reason as `parse`: `pairs` over a `{ [string]: any }`
	-- hands the analyzer `unknown` for the key.
	for rawPet in pairs(pool) do
		table.insert(out, tostring(rawPet))
	end
	table.sort(out)
	return out
end

return CrystalList
end

__modules["game/Crystals"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Crystals -- opening crystals, and the auto-sell list that goes with them.

	The adapter for one RemoteFunction (`openCrystalRemote`), whose protocol a
	Cobalt recording of the game calling itself pins down:

	    Remote:InvokeServer("openCrystal", "Hallowed Crystal")
	    Remote:InvokeServer("saveAutoSell", "Hallowed Crystal", {
	        Pets = { ["Candy Cube"] = true, ["Cursed Candle"] = true, ... },
	        Enabled = false,
	        Auras = {},
	    })

	Two properties of that remote shape the design here:

	  * it is a **RemoteFunction**, so `InvokeServer` YIELDS. Every call runs in a
	    `task.spawn`, and the number of opens allowed to wait at once is the rate
	    setting itself (`inFlightLimit`), capped so a slow server cannot accumulate
	    an unbounded queue. A single-in-flight rule caps the feature at one open
	    per round trip whatever the slider says;
	  * it takes the crystal NAME as a string, so the feature is data-driven from
	    the catalogue (`shared.catalogs.crystalChances`) instead of hard-coding
	    the one crystal that happened to be recorded.

	Auto-sell is pushed WHEN IT CHANGES (store subscription, debounced), not on
	every open: it is a saved server-side preference. The manual button covers a
	server that lost it (a rejoin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrystalList = require("core/CrystalList")
local Remotes = require("game/Remotes")

local Crystals = {}
Crystals.__index = Crystals

--[[
	When a pending open is given up on. Only a leak guard for an invocation that
	never returns -- it must NOT fire while a call is merely slow, and at a 1000 ms
	round trip a fixed 3 s timeout expires on live calls (which is how the old
	code dispatched a second `InvokeServer` on the same RemoteFunction). The
	ceiling scales with measured latency so a slow link waits proportionally.
]]
local OPEN_TIMEOUT = 3
local OPEN_TIMEOUT_RTT = 3
-- The most concurrent opens allowed, however high the rate slider goes. The
-- limit is derived from the rate and the round trip, so it has to be able to
-- hold `rate * RTT` calls; 48 covers a 20/s setting on a 2 s link.
local MAX_IN_FLIGHT = 48
-- One warning per this many seconds: the tick runs every frame.
local WARN_INTERVAL = 5
-- Re-applying the sell list is not urgent; coalesce rapid edits.
local SAVE_DEBOUNCE = 0.6

local function sharedFolder()
	return ReplicatedStorage:FindFirstChild("shared")
end

local function catalogsFolder()
	local shared = sharedFolder()
	return shared and shared:FindFirstChild("catalogs") or nil
end

--[[
	The catalogue as plain tables: `chances[name] = true` for every crystal and
	`pools[name][pet] = true` for each crystal's possible drops. Read from the
	live folders; `core/CrystalList` turns them into the sorted lists.
]]
local function readCatalogue()
	local chances = {}
	local pools = {}
	local prices = {}
	local catalogs = catalogsFolder()
	if catalogs == nil then
		return chances, prices, pools
	end

	local chanceFolder = catalogs:FindFirstChild("crystalChances")
	if chanceFolder ~= nil then
		for _, crystal in ipairs(chanceFolder:GetChildren()) do
			chances[crystal.Name] = true
			local pool = {}
			for _, drop in ipairs(crystal:GetChildren()) do
				--[[
					Pool rows are read LIVE, so a new pet or crystal needs no code
					change. A row may name the pet two ways, so both are accepted:
					the CHILD's own Name (the common shape), or a value carrying it
					(`petName` / `itemValue`), for a build that names rows "1", "2".
				]]
				local name = drop.Name
				local attribute = drop:GetAttribute("petName")
				if type(attribute) == "string" and attribute ~= "" then
					name = attribute
				else
					local value = drop:FindFirstChild("itemValue") or drop:FindFirstChild("petValue")
					if value ~= nil and value:IsA("ValueBase") and type(value.Value) == "string" and value.Value ~= "" then
						name = value.Value
					end
				end
				pool[name] = true
			end
			pools[crystal.Name] = pool
		end
	end

	local priceFolder = catalogs:FindFirstChild("crystalPrices")
	if priceFolder ~= nil then
		for _, crystal in ipairs(priceFolder:GetChildren()) do
			prices[crystal.Name] = {
				price = tonumber(crystal:GetAttribute("price"))
					or tonumber((crystal:FindFirstChild("price") or {}).Value),
				priceType = crystal:GetAttribute("priceType")
					or tostring((crystal:FindFirstChild("priceType") or {}).Value or ""),
			}
		end
	end

	return chances, prices, pools
end

function Crystals.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		timers = context.timers,
		-- Optional: only the give-up timeout uses it (see `install.opts.tick`).
		metrics = context.metrics,
		notify = context.notify or function() end,
		entries = {},
		pools = {},
		catalogueAt = 0,
		lastOpen = 0,
		inFlight = 0,
		-- One entry per call awaiting a reply: ticket -> dispatch time. The
		-- timeout sweeps THIS table instead of zeroing the counter, because
		-- zeroing forgets calls that are still in flight -- their replies then
		-- free a slot somebody else holds.
		tickets = {},
		opened = 0,
		applied = 0,
		saveAt = nil,
		lastResult = "-",
	}, Crystals)
	return self
end

-- The catalogue, cached for a few seconds: it is a tree walk over two folders.
function Crystals.catalogue(self, force)
	local now = os.clock()
	if not force and now - self.catalogueAt < 5 and #self.entries > 0 then
		return self.entries
	end
	self.catalogueAt = now
	local chances, prices, pools = readCatalogue()
	self.entries = CrystalList.parse(chances, prices)
	self.pools = pools
	return self.entries
end

function Crystals.labels(self): { string }
	return CrystalList.labels(Crystals.catalogue(self))
end

-- The stored NAME -> the label the dropdown shows. One mapping, so the two
-- directions (toStore strips the price, fromStore re-adds it) cannot drift.
function Crystals.labelFor(self, name: string?): string
	local entries = Crystals.catalogue(self)
	local label = CrystalList.labelFor(entries, name)
	if label == nil or label == "" then
		return "—"
	end
	return label
end

-- The reverse of `labelFor`: the NAME behind an option's display text. The
-- dropdown is generated from the catalogue, so this is an exact lookup rather
-- than parsing the label.
function Crystals.nameForLabel(self, label: string?): string
	return CrystalList.nameForLabel(Crystals.catalogue(self), label)
end

-- The selected crystal as the NAME the remote takes. The dropdown stores the
-- LABEL for a priced crystal (Hallowed is the only priced one), so every
-- consumer that builds a remote argument -- open, auto-sell, the pool's sell
-- list -- has to come through here; reading `crystal.selected` raw is what made
-- only the Hallowed crystal silently do nothing.
function Crystals.selectedName(self): string?
	local raw = self.store:get("crystal.selected")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local name = Crystals.nameForLabel(self, raw)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

-- The pool of the SELECTED crystal, i.e. what the auto-sell list can be built
-- from. Falls back to the whole catalogue's pets when the pool is unreadable.
function Crystals.selectedPool(self): { string }
	local name = self.store:get("crystal.selected")
	Crystals.catalogue(self)
	return CrystalList.pool(self.pools, if type(name) == "string" then name else nil)
end

--[[
	How many opens may be in flight at once.

	THE RATE IS A THROUGHPUT, NOT A CONCURRENCY: a yielding call completes at
	`inFlight / RTT` per second, so a budget of `floor(rate)` only reached
	`floor(rate) / RTT` per second -- at ~1000 ms every setting from 11 to 20
	opened the same ten a second.

	`rate * RTT` calls must be waiting to sustain the rate, plus one for the
	reply in progress.
]]
local function inFlightLimit(rate: number, rtt: number): number
	local wanted = math.ceil(math.max(rate, 0) * math.max(rtt, 1)) + 1
	if wanted < 1 then
		wanted = 1
	end
	if wanted > MAX_IN_FLIGHT then
		wanted = MAX_IN_FLIGHT
	end
	return wanted
end

--[[
	Hatch one crystal, off the frame path.

	The in-flight BUDGET is the flood control (see `inFlightLimit`), and the reply
	is READ: treating any non-throwing return as success counted a server refusal
	as a successful open.
]]
function Crystals.open(self): boolean
	local remote = Remotes.crystal()
	local name = Crystals.selectedName(self)
	if remote == nil then
		if os.clock() - (self.warnAt or 0) > WARN_INTERVAL then
			self.warnAt = os.clock()
			self.notify("找不到 openCrystalRemote，水晶无法开启", "warn")
		end
		return false
	end
	if name == nil then
		if os.clock() - (self.warnAt or 0) > WARN_INTERVAL then
			self.warnAt = os.clock()
			self.notify("先选一个水晶", "warn")
		end
		return false
	end
	if not CrystalList.has(Crystals.catalogue(self), name) then
		-- The remote would answer "rejected" for an unknown name, which reads
		-- like a server fault. Say what is actually wrong, once.
		if os.clock() - (self.warnAt or 0) > WARN_INTERVAL then
			self.warnAt = os.clock()
			self.notify("选择的水晶不在图鉴里：" .. tostring(name), "warn")
		end
		return false
	end

	local ticket = {}
	self.tickets[ticket] = os.clock()
	self.inFlight += 1
	task.spawn(function()
		local ok, reply = pcall(function()
			return remote:InvokeServer("openCrystal", name)
		end)
		-- A call the timeout already wrote off must not free a slot again.
		if self.tickets[ticket] == nil then
			return
		end
		self.tickets[ticket] = nil
		self.inFlight = math.max(0, self.inFlight - 1)
		if not ok then
			self.lastResult = tostring(reply)
			return
		end
		if reply ~= nil and reply ~= false then
			self.opened += 1
			self.lastResult = "ok"
		else
			-- The server answered and refused. Say so instead of banking it.
			self.lastResult = if reply == nil then "服务器未返回结果" else "服务器拒绝"
		end
	end)
	return true
end

--[[
	Push the auto-sell configuration: its own call because it is a PERSISTED
	SERVER PREFERENCE, not part of a hatch. The payload shape is the game's own,
	reproduced exactly (`Pets` as a set, `Enabled`, `Auras`).
]]
function Crystals.applyAutoSell(self): boolean
	local remote = Remotes.crystal()
	local name = Crystals.selectedName(self)
	if remote == nil or name == nil then
		return false
	end
	-- The set the USER ticked for this crystal; everything else is kept.
	local sell = CrystalList.sellNames(self.store:get("crystal.sellByCrystal"), name)
	local payload = CrystalList.sellPayload(sell, self.store:get("crystal.autoSell") == true)

	task.spawn(function()
		local ok = pcall(function()
			remote:InvokeServer("saveAutoSell", name, payload)
		end)
		-- Counted only when the server accepted it, so the read-out is successes
		-- rather than attempts.
		if ok then
			self.applied += 1
		end
	end)
	return true
end

-- The pets ticked for the selected crystal (for the page's checkboxes).
function Crystals.sellSelection(self)
	return CrystalList.sellNames(
		self.store:get("crystal.sellByCrystal"),
		Crystals.selectedName(self)
	)
end

-- Tick / untick ONE pet of the selected crystal. The store write is the whole
-- action: the page's checkbox is bound to the same map.
function Crystals.setSell(self, pet: string?, marked: boolean)
	local name = Crystals.selectedName(self)
	if name == nil then
		self.notify("先选一个水晶", "warn")
		return
	end
	self.store:set("crystal.sellByCrystal",
		CrystalList.withMark(self.store:get("crystal.sellByCrystal"), name, pet, marked))
end

-- Mark the whole pool of the selected crystal (全选 / 全不选).
function Crystals.setPoolSell(self, marked: boolean): number
	local name = Crystals.selectedName(self)
	if name == nil then
		self.notify("先选一个水晶", "warn")
		return 0
	end
	local pool = Crystals.selectedPool(self)
	if #pool == 0 then
		self.notify("读不到该水晶的宠物池（crystalChances）", "warn")
		return 0
	end
	self.store:set("crystal.sellByCrystal",
		CrystalList.withPoolMark(self.store:get("crystal.sellByCrystal"), name, pool, marked))
	return #pool
end

-- How many pets of the selected crystal are marked for selling.
function Crystals.sellCount(self): number
	return CrystalList.sellCount(
		self.store:get("crystal.sellByCrystal"),
		Crystals.selectedName(self)
	)
end

function Crystals.stats(self)
	local name = self.store:get("crystal.selected")
	return {
		crystal = if type(name) == "string" then name else "",
		opened = self.opened,
		applied = self.applied,
		-- How many opens are waiting on the server right now (the rate budget
		-- above is what limits it).
		inFlight = self.inFlight,
		last = self.lastResult,
		count = #Crystals.catalogue(self),
	}
end

function Crystals.install(context)
	local self = Crystals.new(context)
	local store = self.store

	self.scheduler:register({
		id = "crystal",
		priority = 40,
		enabled = function()
			return store:get("crystal.auto") == true
		end,
		onEnable = function()
			self.inFlight = 0
			self.tickets = {}
			self.lastOpen = 0
			-- A fresh enable re-pushes the sell preference: the server may have
			-- been replaced (a rejoin) since it was last sent.
			Crystals.applyAutoSell(self)
		end,
		tick = function(_dt, now)
			--[[
				Abandon an invocation that never returned -- PER TICKET, and before
				the rate gate: at rate 0 the old order returned first, so dead
				tickets kept their slots for the rest of the session.
			]]
			local timeout = OPEN_TIMEOUT
			local metrics = self.metrics
			local rtt = 0
			if metrics ~= nil then
				-- The worst sample, not the mean: sizing from an averaged 200 ms
				-- link writes off requests that need a full second.
				local reading = metrics:reading()
				rtt = math.max(reading.pingWorst or 0, reading.ping or 0) / 1000
				if rtt > 0 then
					timeout = math.max(OPEN_TIMEOUT, OPEN_TIMEOUT_RTT * rtt)
				end
			end
			local stale = nil
			for ticket, at in pairs(self.tickets) do
				if now - at > timeout then
					self.tickets[ticket] = nil
					self.inFlight = math.max(0, self.inFlight - 1)
					stale = true
				end
			end
			if stale then
				self.lastResult = "请求超时"
			end

			local rate = tonumber(store:get("crystal.rate")) or 2
			if rate <= 0 then
				return
			end
			local interval = 1 / math.max(0.05, rate)
			if now - (self.lastOpen or 0) < interval then
				return
			end
			if self.inFlight >= inFlightLimit(rate, rtt) then
				return
			end
			self.lastOpen = now
			Crystals.open(self)
		end,
	})

	--[[
		AUTO-SELL FOLLOWS THE SETTINGS, debounced through the runtime's Timers so
		dragging the sell list (or flipping the switch) sends ONE call, not one per
		keystroke.
	]]
	local function scheduleApply()
		local timers = self.timers
		if timers == nil then
			Crystals.applyAutoSell(self)
			return
		end
		if self.saveHandle ~= nil then
			self.saveHandle:cancel()
		end
		self.saveHandle = timers:after(os.clock(), SAVE_DEBOUNCE, function()
			self.saveHandle = nil
			Crystals.applyAutoSell(self)
		end)
	end

	for _, path in ipairs({ "crystal.autoSell", "crystal.sellByCrystal", "crystal.selected" }) do
		store:subscribe(path, scheduleApply)
	end

	return self
end

return Crystals
end

__modules["game/PetMetrics"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	PetMetrics -- reading the player's rep-speed bonuses off the object tree.

	The arithmetic lives in core/RepBonus; this file is the traversal and the
	field names, which were confirmed against the game -- getting one wrong
	silently reports zero:

	    equipped pets : Players.<me>.equippedPets.pet1..petN   (ValueBase = name)
	    pet bonus     : <pet>.perksFolder.repTimeBoostPercent  (Boss pets 5/7/10,
	                                                           Inferno Drake 40)
	    ultimate      : catalogs.gameUltimatesFolder["+5% Rep Speed"], 5% per level
	    gamepass      : Players.<me>.ownedGamepasses["x2 Rep Time"]

	The scan is throttled because it walks several containers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RepBonus = require("core/RepBonus")

local PetMetrics = {}
PetMetrics.__index = PetMetrics

local SCAN_INTERVAL = 5
local SLOT_LIMIT = 20
local ULTIMATE_NAME = "+5% Rep Speed"
local GAMEPASS_NAME = "x2 Rep Time"

function PetMetrics.new()
	local self = setmetatable({
		lastScan = 0,
		result = RepBonus.compute({}),
		ultimateSource = nil,
		passNames = {},
	}, PetMetrics)
	return self
end

local function player()
	return Players.LocalPlayer
end

local function runtimeFolder()
	local shared = ReplicatedStorage:FindFirstChild("shared")
	return shared and shared:FindFirstChild("runtime")
end

-- Equipped pets are recorded as name slots, not models.
function PetMetrics.equippedNames(self)
	local out = {}
	local user = player()
	if user == nil then
		return out
	end
	local container = user:FindFirstChild("equippedPets")
	if container == nil then
		return out
	end
	for index = 1, SLOT_LIMIT do
		local value = container:FindFirstChild("pet" .. index)
		if value ~= nil and value:IsA("ValueBase") then
			local name = tostring(value.Value or "")
			if name ~= "" then
				table.insert(out, { name = name, slot = "pet" .. index })
			end
		end
	end
	return out
end

local function perkPercent(model)
	if model == nil then
		return nil
	end
	local perks = model:FindFirstChild("perksFolder")
	local value = perks and perks:FindFirstChild("repTimeBoostPercent")
	if value ~= nil and value:IsA("ValueBase") then
		return tonumber(value.Value)
	end
	return nil
end

--[[
	Prefer the live model, because an individual pet may have been upgraded; the
	static preview catalogue is the fallback for one not yet streamed in.
]]
function PetMetrics.percentFor(self, name)
	local user = player()
	local own = user ~= nil and Workspace:FindFirstChild(user.Name) or nil
	local live = perkPercent(own and own:FindFirstChild(name))
	if live ~= nil then
		return live
	end
	local previews = runtimeFolder()
	local catalogue = previews and previews:FindFirstChild("petPreviews")
	return perkPercent(catalogue and catalogue:FindFirstChild(name))
end

local function readLevel(instance)
	if instance == nil then
		return nil
	end
	if instance:IsA("ValueBase") then
		return tonumber(instance.Value)
	end
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("ValueBase") then
			return tonumber(child.Value)
		end
	end
	local attribute = instance:GetAttribute("Level")
		or instance:GetAttribute("level")
		or instance:GetAttribute("Upgrades")
		or instance:GetAttribute("Amount")
	if attribute ~= nil then
		return tonumber(attribute)
	end
	return nil
end

--[[
	Container names changed between game versions, so several are tried. Order
	matters: the PLAYER containers first (the player's own levels), then the shared
	catalogue, whose `ReplicatedStorage.shared.catalogs.gameUltimatesFolder` path
	is the documented source of truth and must not be missing from the list.
]]
function PetMetrics.ultimateLevel(self, name)
	local user = player()
	if user == nil then
		return nil, nil
	end
	local roots = {
		user:FindFirstChild("ultimatesFolder"),
		user:FindFirstChild("gameUltimatesFolder"),
		user:FindFirstChild("ultimates"),
		user:FindFirstChild("upgradesFolder"),
		user:FindFirstChild("gameUpgrades"),
	}

	local shared = ReplicatedStorage:FindFirstChild("shared")
	local catalogs = shared and shared:FindFirstChild("catalogs")
	if catalogs ~= nil then
		table.insert(roots, catalogs:FindFirstChild("gameUltimatesFolder"))
		table.insert(roots, catalogs:FindFirstChild("ultimatesFolder"))
		table.insert(roots, catalogs)
	end

	for _, root in ipairs(roots) do
		if root ~= nil then
			local level = readLevel(root:FindFirstChild(name))
			if level ~= nil then
				return level, root.Name
			end
		end
	end
	for _, key in ipairs({ name, name .. "Level", name .. "Levels", name .. "Upgrades" }) do
		local attribute = user:GetAttribute(key)
		if attribute ~= nil then
			return tonumber(attribute) or 0, "attribute"
		end
	end
	return nil, nil
end

function PetMetrics.hasGamepass(self, name): boolean
	local user = player()
	if user == nil then
		return false
	end
	local owned = user:FindFirstChild("ownedGamepasses")
	return owned ~= nil and owned:FindFirstChild(name) ~= nil
end

function PetMetrics.passNames(self)
	local out = {}
	local user = player()
	if user == nil then
		return out
	end
	local owned = user:FindFirstChild("ownedGamepasses")
	if owned ~= nil then
		for _, child in ipairs(owned:GetChildren()) do
			table.insert(out, child.Name)
		end
	end
	return out
end

function PetMetrics.scan(self, now, force)
	local stamp = now or os.clock()
	if not force and stamp - self.lastScan < SCAN_INTERVAL then
		return self.result
	end
	self.lastScan = stamp

	local equipped = PetMetrics.equippedNames(self)
	local percent, counted = 0, 0
	for _, entry in ipairs(equipped) do
		local value = PetMetrics.percentFor(self, entry.name)
		if value ~= nil then
			percent += value
			counted += 1
		end
	end

	local level, source = PetMetrics.ultimateLevel(self, ULTIMATE_NAME)
	self.ultimateSource = source
	self.passNames = PetMetrics.passNames(self)
	self.result = RepBonus.compute({
		petPercent = percent,
		petCount = counted,
		equippedCount = #equipped,
		ultimateLevel = level or 0,
		hasGamepass = PetMetrics.hasGamepass(self, GAMEPASS_NAME),
	})
	return self.result
end

function PetMetrics.stats(self)
	return {
		result = self.result,
		label = RepBonus.describe(self.result),
		ultimateSource = self.ultimateSource,
		passNames = self.passNames,
	}
end

return PetMetrics
end

__modules["game/Machine"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Machine -- sitting on a gym machine.

	WHICH machine is a pure decision and lives in core/MachinePlan (tested there).
	Everything else -- finding the seat, putting the body on it, asking the game --
	is here, and it is DIRECT rather than state-machine paced: the reported faults
	were pacing, not traversal (see the constants below).

	The seat is read through occupantOf, which only touches `Occupant` on an
	actual Seat or VehicleSeat: `interactSeat` is often a plain Part, where reading
	`seat.Occupant` raises "Occupant is not a valid member".
]]

local VirtualInputManager = game:GetService("VirtualInputManager")

local MachinePlan = require("core/MachinePlan")
local Remotes = require("game/Remotes")

local Machine = {}
Machine.__index = Machine

local SCAN_CACHE = 2
-- How far above the seat the body is placed before sitting.
local SIT_HEIGHT = 1.2
local KEY_TAIL = 0.05
--[[
	The pacing: re-assert the position ~16x a second, ask the game ~8x a second,
	and give up on a single stubborn seat after 4 s so the next one is tried. A
	multi-second hover plus a per-action retry gate is what the player perceived
	as "延迟非常高 / 等个几十秒".
]]
local SIT_INTERVAL = 0.06
local SEND_INTERVAL = 0.12
local SEAT_TIMEOUT = 4

-- Reading `Occupant` on a non-seat part errors, so it is only read where it is
-- actually a property.
local function occupantOf(seat)
	if seat == nil then
		return nil
	end
	local ok, occupant = pcall(function()
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			return seat.Occupant
		end
		return nil
	end)
	if ok then
		return occupant
	end
	return nil
end

local function toTable(position)
	return { x = position.X, y = position.Y, z = position.Z }
end

function Machine.new(context)
	local self = setmetatable({
		store = context.store,
		net = context.net,
		scheduler = context.scheduler,
		timers = context.timers,
		character = context.character,
		-- Used to put the body on the seat in one frame (Teleport.snap), which
		-- also clears a stale motion hold that would drag it back off.
		teleport = context.teleport or nil,
		isCombatBusy = context.isCombatBusy or function()
			return false
		end,
		isBossAlive = context.isBossAlive or function()
			return false
		end,
		--[[
			The arbitration handle. `isDamageNeeded` is the ONE question this
			subsystem needs answered: "would sitting here cost us a punch?" A
			machine blocks damage, so while the answer is yes the seat is released
			-- and it is re-asked every frame, so the mount resumes by itself.
		]]
		isDamageNeeded = context.isDamageNeeded or function()
			return false
		end,
		notify = context.notify or function() end,
		cache = {},
		cacheAt = 0,
		target = nil,
		attempts = 0,
		lastPhase = "idle",
		-- Why the machine is standing down right now, kept for the page even when
		-- `blockedState` stops reporting one (see Machine.stats).
		blockReason = nil,
		placeAt = nil,
		sendAt = nil,
		seatSince = nil,
	}, Machine)
	return self
end

-- Every seat in the world, cached for two seconds: the scan walks machinesFolder,
-- and machines are streamed in and out as the player moves.
function Machine.seats(self, force)
	local now = os.clock()
	if not force and now - self.cacheAt < SCAN_CACHE and #self.cache > 0 then
		return self.cache
	end
	self.cacheAt = now

	local out = {}
	local folder = Workspace:FindFirstChild("machinesFolder")
	if folder ~= nil then
		for index, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") then
				--[[
					`interactSeat` is found RECURSIVELY: the live machines nest it
					below the model, and a one-level lookup returned nil for most
					of them -- which made `seats()` empty and the feature do
					nothing.
				]]
				local seat = model:FindFirstChild("interactSeat", true)
				if seat == nil or not seat:IsA("BasePart") then
					seat = nil
					local found = model:FindFirstChildWhichIsA("Seat", true)
					if found == nil then
						found = model:FindFirstChildWhichIsA("VehicleSeat", true)
					end
					if found ~= nil then
						seat = found
					end
				end
				if seat ~= nil and seat:IsA("BasePart") then
					local ok, position = pcall(function()
						return seat.Position
					end)
					table.insert(out, {
						id = model.Name .. "#" .. tostring(index),
						model = model,
						seat = seat,
						name = model.Name,
						gym = MachinePlan.gymOf(ok and toTable(position) or nil),
						index = index,
						occupied = occupantOf(seat) ~= nil,
					})
				end
			end
		end
	end

	self.cache = out
	return out
end

function Machine.names(self)
	return MachinePlan.names(Machine.seats(self))
end

function Machine.count(self, name)
	return MachinePlan.count(Machine.seats(self), name)
end

function Machine.resolve(self)
	return MachinePlan.resolve(Machine.seats(self), {
		gym = self.store:get("machine.gymFilter"),
		name = self.store:get("machine.nameFilter"),
		index = tonumber(self.store:get("machine.indexFilter")) or 0,
	})
end

--[[
	Should the seat be given up right now? Three independent reasons.

	ALL THREE PREDICATES MEAN "IS IT ACTUALLY HAPPENING", not "is the feature
	switched on": `isCombatBusy` answers "a target is in the crosshairs" and
	`isBossAlive` is wired to the boss task's ACTIVE state. Wired to the switches
	instead, merely leaving global kill on stood the player off the seat forever
	with nothing being fought. `isDamageNeeded` covers what neither other reason
	does (a boss being attacked while `kill.enabled` is off).
]]
function Machine.blocked(self): boolean
	local blocked = Machine.blockedState(self)
	return blocked
end

-- The same answer WITH THE REASON, so the page can say why nothing is moving: a
-- blocked machine and a machine with no target look identical from outside.
function Machine.blockedState(self): (boolean, string?)
	--[[
		The explicit override. With it on the machine is never asked to step
		aside -- a user decision, not a policy change, and the UI says so.
	]]
	if self.store:get("machine.overridesCombat") == true then
		return false, nil
	end
	if self.isDamageNeeded() then
		return true, "有击杀/Boss 任务需要出拳"
	end
	if self.isCombatBusy() then
		return true, "正在打人"
	end
	if self.isBossAlive() then
		return true, "正在打 Boss"
	end
	return false, nil
end

function Machine.dismount(self)
	local root = self.character:requireRoot()
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
	end)
	self.timers:after(os.clock(), KEY_TAIL, function()
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		end)
	end)
	if root ~= nil then
		pcall(function()
			root.Anchored = false
		end)
	end
	self.target = nil
	self.seatSince = nil
	self.placeAt = nil
	self.sendAt = nil
	self.lastPhase = "idle"
end

--[[
	Use the machine now.

	`InvokeServer` YIELDS (the game's remote is a RemoteFunction) and this runs on
	the Heartbeat tick, so invoking it inline would stall the frame loop for a
	round trip; it therefore runs in a task.spawn. There is no rate channel: a
	one-shot interaction has nothing to throttle and the caller paces itself, while
	a queue of duplicate "useMachine" calls was the reported latency.
]]
function Machine.use(self, seat): boolean
	local remote = Remotes.machine()
	if remote == nil then
		return false
	end
	-- ONE INVOKE IN FLIGHT. `InvokeServer` yields for a round trip and this is
	-- called every 0.12 s: without the guard a laggy server queued a second and a
	-- third call behind the first, which is the "延迟非常高" the pacing was meant
	-- to remove. The stamp is the escape hatch: an invoke that never returns
	-- cannot wedge the feature for the rest of the session.
	local now = os.clock()
	if self.using and now - (self.usingAt or 0) < 2 then
		return true
	end
	self.using = true
	self.usingAt = now
	task.spawn(function()
		pcall(function()
			if remote:IsA("RemoteFunction") then
				remote:InvokeServer("useMachine", seat)
			else
				remote:FireServer("useMachine", seat)
			end
		end)
		self.using = false
	end)
	return true
end

--[[
	Put the body ON the seat and sit, immediately.

	`Anchored` is cleared FIRST and that is not cosmetic: `aim` anchors the root
	while hovering, and a Roblox character cannot sit while its root is anchored,
	so every `seat:Sit` would be silently undone.
]]
local function mountSeat(self, root, humanoid, seat, now)
	local ok, position = pcall(function()
		return seat.Position
	end)

	if self.teleport ~= nil and ok and typeof(position) == "Vector3" then
		-- Clears any stale motion hold too (snap calls motion:finish), which
		-- would otherwise drag the character back off the seat every frame.
		self.teleport:snap(position + Vector3.new(0, SIT_HEIGHT, 0), "machine")
	else
		pcall(function()
			root.Anchored = false
		end)
		if ok and typeof(position) == "Vector3" then
			pcall(function()
				root.CFrame = CFrame.new(position + Vector3.new(0, SIT_HEIGHT, 0))
			end)
		end
	end
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	pcall(function()
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)

	pcall(function()
		seat:Sit(humanoid)
	end)

	-- The touch pulse is what registers with some machines. The release is
	-- scheduled rather than slept through: a blocked task cannot be cancelled on
	-- unload.
	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, seat, root, 0)
		self.timers:after(now, KEY_TAIL, function()
			pcall(firetouchinterest, seat, root, 1)
		end)
	end
end

--[[
	Is the player on a machine right now?

	While this is true the machine was ALLOWED to own the body (machine.overridesCombat
	let it mount), so the boss hover and combat approach must not hold the
	character: a motion hold sets `PlatformStand`, which breaks the seat's weld and
	makes the player drop straight back off.
]]
function Machine.isSeated(self): boolean
	if self.lastPhase ~= "mounted" then
		return false
	end
	local humanoid = self.character:humanoid()
	if humanoid == nil then
		return false
	end
	if humanoid.Sit == true then
		return true
	end
	-- `Sit` can be false for a frame while the seat re-welds; the occupant check
	-- is the second opinion, and it only asks it on an actual Seat.
	local seat = if self.target ~= nil then self.target.seat else nil
	return occupantOf(seat) == humanoid
end

function Machine.tick(self, now)
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	local hasCharacter = humanoid ~= nil and root ~= nil

	--[[
		The block is a STATE: the fight's motion hold sets `PlatformStand` and
		stands the character up, so a tick that never asked whether the machine was
		ALLOWED to be used would see "not seated", re-mount, get stood up again and
		loop until the seat timeout. Dismount once, then stay off until the reason
		goes away; `blockedState` is re-asked every tick so the mount resumes by
		itself.
	]]
	local blocked, reason = Machine.blockedState(self)
	self.blockReason = reason
	if blocked then
		if self.lastPhase ~= "blocked" then
			-- One dismount per block, never one per tick.
			if self.lastPhase == "mounted" or self.lastPhase == "mounting" then
				Machine.dismount(self)
			end
			self.lastPhase = "blocked"
			self.target = nil
		end
		return
	end

	--[[
		`self.target` IS A SEAT RECORD ({ model, seat, name, gym, index }), NOT A
		SEAT PART: reading `.Parent` or `occupantOf()` on the record made it look
		invalid on the very first line, and the tick then refused to act at all.
	]]
	if self.target ~= nil then
		local model = self.target.model
		local seat = self.target.seat
		if model == nil or model.Parent == nil or seat == nil or seat.Parent == nil then
			self.target = nil
			self.seatSince = nil
		end
	end
	if hasCharacter and self.target == nil then
		self.target = Machine.resolve(self)
		self.attempts = 0
		self.placeAt = nil
		self.sendAt = nil
	end

	local target = self.target
	if not hasCharacter or target == nil then
		if self.lastPhase == "blocked" then
			return
		end
		self.lastPhase = "idle"
		return
	end

	local seat = target.seat
	local occupant = occupantOf(seat)

	-- Somebody else took it: hands off, pick again. The seat clock belongs to the
	-- abandoned seat, so it is cleared with it -- otherwise the freshly resolved
	-- seat inherits the old start time and is dropped on its first tick.
	if occupant ~= nil and occupant ~= humanoid then
		self.target = nil
		self.seatSince = nil
		return
	end

	--[[
		SEATED: STOP PUSHING. Only an occupant who is us counts -- accepting
		`humanoid.Sit == true` (which the mount path sets itself) made a seat that
		never took the player count as mounted, so `use` stopped firing.
	]]
	if occupant == humanoid then
		if root.Anchored then
			pcall(function()
				root.Anchored = false
			end)
		end
		self.lastPhase = "mounted"
		return
	end

	self.lastPhase = "mounting"

	--[[
		Pacing "as fast as useful": position re-asserted every SIT_INTERVAL, the
		remote every SEND_INTERVAL, and a seat that will not take the player is
		abandoned after SEAT_TIMEOUT so a broken one cannot wedge the feature.
	]]
	local startedAt = self.seatSince or now
	self.seatSince = startedAt
	if now - startedAt > SEAT_TIMEOUT then
		self.target = nil
		self.seatSince = nil
		return
	end

	if now - (self.placeAt or 0) >= SIT_INTERVAL then
		self.placeAt = now
		mountSeat(self, root, humanoid, seat, now)
	end

	if now - (self.sendAt or 0) >= SEND_INTERVAL then
		self.sendAt = now
		self.attempts += 1
		Machine.use(self, seat)
	end
end

function Machine.stats(self)
	local blocked, reason = Machine.blockedState(self)
	return {
		phase = self.lastPhase,
		attempts = self.attempts,
		target = if self.target ~= nil then self.target.name else nil,
		seats = #Machine.seats(self),
		blocked = blocked,
		-- The LIVE reason, not the one remembered when the block started: the
		-- page prints this to answer "启用了器械为什么不上".
		reason = reason or self.blockReason,
	}
end

function Machine.install(context)
	local self = Machine.new(context)
	local store = self.store

	self.scheduler:register({
		id = "machine",
		priority = 90,
		enabled = function()
			return store:get("machine.enabled") == true
		end,
		onDisable = function()
			Machine.dismount(self)
		end,
		tick = function(_dt, now)
			Machine.tick(self, now)
		end,
	})

	return self
end

return Machine
end

__modules["game/Rebirth"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Rebirth -- automatic rebirth, and the "pack rebirth" sequence.

	The rules live in core/RebirthState and core/PackState (both a pure function
	of state and a step), so this file only performs the actions they ask for.
	Pack rebirth is an explicit training -> equipping -> requesting sequence
	instead of a cancellable, unreportable task.wait() loop.
]]

local Players = game:GetService("Players")

local RebirthState = require("core/RebirthState")
local PackState = require("core/PackState")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")
local PlayerStats = require("game/PlayerStats")
local Pets = require("game/Pets")

local Rebirth = {}
Rebirth.__index = Rebirth

local TRAIN_BURST = 20
local TRAIN_INTERVAL = 0.05
local FARMING_PETS = 12

function Rebirth.new(context)
	local self = setmetatable({
		store = context.store,
		net = context.net,
		scheduler = context.scheduler,
		pets = context.pets,
		isBossAlive = context.isBossAlive or function()
			return false
		end,
		notify = context.notify or function() end,
		state = RebirthState.new(),
		pack = PackState.new(),
		packBefore = 0,
		packTarget = 0,
		lastBurst = 0,
		requests = 0,
		successes = 0,
	}, Rebirth)
	return self
end

local function player()
	return Players.LocalPlayer
end

function Rebirth.tick(self, now)
	local store = self.store
	local user = player()

	-- scheduleSwap is a no-op when auto-switch is off, the preset is empty, or
	-- it is already active.
	if self.pets ~= nil then
		Pets.scheduleSwap(self.pets, "rebirth", 0)
	end

	local target = tonumber(store:get("rebirth.target")) or 0
	local result = self.state:step({
		strength = PlayerStats.value(user, "Strength"),
		rebirths = PlayerStats.value(user, "Rebirths"),
		target = target,
		rate = tonumber(store:get("rebirth.rate")) or 0,
	}, now)

	if result.outcome == "target-reached" then
		store:set("rebirth.rate", 0)
		self.notify(string.format("已达到目标重生数 %d，自动重生已关闭", target), "info")
		return
	end

	if result.outcome == "failed" then
		if result.shouldWarn then
			self.notify("重生请求连续失败，已自动降频", "warn")
		end
		return
	end

	if result.outcome == "succeeded" then
		self.successes += 1
		-- The pet preset is stale now: a rebirth reshuffles what is worth wearing.
		if self.pets ~= nil then
			Pets.clearActiveType(self.pets)
		end
		return
	end

	if result.action == "send" then
		self.requests += 1
		if not self.net:send("rebirth", now, "rebirthRequest") then
			-- Nothing went out, so there is nothing to wait for.
			RebirthState.abort(self.state)
		end
	end
end

function Rebirth.packTick(self, now)
	local user = player()
	local result = self.pack:step({
		strength = PlayerStats.value(user, "Strength"),
		rebirths = PlayerStats.value(user, "Rebirths"),
		rebirthsBefore = self.packBefore,
		target = self.packTarget,
		busy = self.pets ~= nil and Pets.isBusy(self.pets),
	}, now)

	if result.action == "train" then
		GameNet.ensureMuscle(self.net, nil)
		if now - self.lastBurst >= TRAIN_INTERVAL then
			self.lastBurst = now
			self.net:burst(GameNet.MUSCLE_CHANNEL, now, TRAIN_BURST, "rep")
		end
	elseif result.action == "equip" then
		if self.pets ~= nil then
			Pets.equipFarming(self.pets, FARMING_PETS)
		end
	elseif result.action == "request" then
		self.net:send("rebirth", now, "rebirthRequest")
	end

	if result.done then
		if result.success then
			self.notify("换包重生成功", "info")
		else
			self.notify("换包重生未确认成功（重生次数没有变化）", "warn")
		end
		self.pack:reset()
	end
end

function Rebirth.stats(self)
	return {
		pending = self.state:isPending(),
		fails = self.state:failures(),
		requests = self.requests,
		successes = self.successes,
		packPhase = self.pack.phase,
	}
end

function Rebirth.install(context)
	local self = Rebirth.new(context)
	local store = self.store

	self.net:addChannel("rebirth", GameNet.senderFor(function()
		return Remotes.rebirth()
	end), { rate = 10, burst = 3, queue = 2 })

	self.scheduler:register({
		id = "rebirth",
		priority = 70,
		enabled = function()
			if store:get("rebirth.lock") == true then
				return false
			end
			if (tonumber(store:get("rebirth.rate")) or 0) <= 0 then
				return false
			end
			if store:get("boss.auto") == true and self.isBossAlive() and store:get("rebirth.duringBoss") ~= true then
				return false
			end
			if store:get("kill.enabled") == true and store:get("rebirth.duringKill") ~= true then
				return false
			end
			return true
		end,
		onEnable = function()
			-- A fresh enable is a fresh attempt: a failure streak from minutes ago
			-- should not delay it.
			RebirthState.reset(self.state)
			if self.pets ~= nil then
				Pets.scheduleSwap(self.pets, "rebirth", 1.5)
			end
		end,
		tick = function(_dt, now)
			Rebirth.tick(self, now)
		end,
	})

	self.scheduler:register({
		id = "packrebirth",
		priority = 70,
		enabled = function()
			return store:get("pet.autoPack") == true
		end,
		onEnable = function()
			local rebirths = PlayerStats.value(player(), "Rebirths")
			self.packBefore = rebirths
			self.packTarget = RebirthState.packTarget(rebirths)
			self.pack:reset()
		end,
		tick = function(_dt, now)
			Rebirth.packTick(self, now)
		end,
	})

	return self
end

return Rebirth
end

__modules["game/Metrics"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Metrics -- the engine side of the frame/memory/ping figures; the accumulators
	and windows are core/Metrics (tested). What is left here is three engine calls
	and their throttles:

	    frame rate   -- every frame, but the measurement only lands when the
	                    window closes
	    memory       -- every 15 s: Stats:GetTotalMemoryUsageMb is a known hitch
	                    source
	    ping         -- once a second: the game's own `Data Ping` (the F9 figure)
	                    when the network stats have one, else the engine's
	                    `GetNetworkPing` estimate, then windowed by the core

	Every subsystem that needs "how is the client doing" reads this one object
	rather than sampling the engine itself.
]]

local Players = game:GetService("Players")
local StatsService = game:GetService("Stats")

local Metrics = require("core/Metrics")
local PlayerStats = require("game/PlayerStats")

local GameMetrics = {}
GameMetrics.__index = GameMetrics

local MEMORY_INTERVAL = 15
local PING_INTERVAL = 1
local STATS_INTERVAL = 0.25

-- Time-bounded (seconds) plus a hard sample cap, so the window means the same
-- thing at any sampling cadence and cannot grow without bound.
local STRENGTH_WINDOW_SECONDS = 15
local STRENGTH_WINDOW_CAP = 90
local REBIRTH_WINDOW_SECONDS = 600
local REBIRTH_WINDOW_CAP = 30

function GameMetrics.new(context)
	local self = setmetatable({
		scheduler = context.scheduler,
		metrics = Metrics.new(),
		memoryAt = 0,
		pingAt = 0,
	}, GameMetrics)
	return self
end

function GameMetrics.tick(self, dt, now)
	self.metrics:frame(dt)

	if now - self.memoryAt > MEMORY_INTERVAL then
		self.memoryAt = now
		local ok, megabytes = pcall(function()
			return StatsService:GetTotalMemoryUsageMb()
		end)
		if ok and megabytes ~= nil then
			self.metrics:setMemory(megabytes)
		end
	end

	if now - self.pingAt > PING_INTERVAL then
		self.pingAt = now
		local user = Players.LocalPlayer
		if user ~= nil then
			--[[
				The game's own number first: `Player:GetNetworkPing()` is a
				client-side estimate, NOT the F9 "Data Ping" figure the player
				reads. `Stats.Network.ServerStatsItem["Data Ping"]` is that source
				and is ALREADY milliseconds. Looked up by name per sample because
				the item is created when network stats come up, so a missing key
				must fall back rather than freeze the row at "-".
			]]
			local millis = nil
			local estimated = false
			local okStats, value = pcall(function()
				local network = StatsService:FindFirstChild("Network")
				local item = network ~= nil and network:FindFirstChild("ServerStatsItem") or nil
				local dataPing = item ~= nil and item:FindFirstChild("Data Ping") or nil
				if dataPing == nil then
					return nil
				end
				return tonumber(dataPing:GetValue())
			end)
			if okStats and value ~= nil and value > 0 then
				millis = value
			end
			if millis == nil then
				local ok, seconds = pcall(function()
					return user:GetNetworkPing()
				end)
				if ok and seconds ~= nil and seconds > 0 then
					millis = seconds * 1000
					-- The fallback is a client-side estimate, not the figure the
					-- game reports; the panel says so rather than passing it off as
					-- the real latency.
					estimated = true
				end
			end
			if millis ~= nil then
				self.metrics:setPingEstimated(estimated)
				self.metrics:pushPing(millis)
			end
		end
	end

	--[[
		Leaderboard reads are throttled: each walks the player's children (direct
		lookup AND `leaderstats`), and these numbers move at human speed. 4 Hz is
		far more than the 5 Hz panel or the 15 s / 600 s windows need.
	]]
	if now - (self.statsAt or 0) >= STATS_INTERVAL then
		self.statsAt = now
		GameMetrics.trackStrength(self, now)
		GameMetrics.trackRebirths(self, now)
	end
end

-- Session strength, and the rate it is climbing at. The rate is measured between
-- samples rather than averaged over the session, so a slow start does not
-- flatter the current figure.
--[[
	Push one sample into a bounded rolling window and return the window's rate.

	A two-sample measurement would report an absurd per-second figure from one
	40 ms frame that gained strength, and a rate that stopped changing would
	FREEZE at its last value instead of decaying. The window is time-bounded and
	anchored at the first sample still inside it, so the elapsed time is that
	sample's age, not the newest one's.
]]
local function pushSample(window, value, now, seconds, cap)
	table.insert(window, { value = value, at = now })
	local oldest = now - seconds
	while #window > 1 and window[1].at < oldest do
		table.remove(window, 1)
	end
	while #window > cap do
		table.remove(window, 1)
	end

	local first = window[1]
	local last = window[#window]
	local elapsed = last.at - first.at
	if elapsed <= 0 then
		return 0
	end
	return (last.value - first.value) / elapsed
end

function GameMetrics.trackStrength(self, now)
	local user = Players.LocalPlayer
	if user == nil then
		return
	end
	local value = PlayerStats.value(user, "Strength")
	if self.sessionStart == nil then
		self.sessionStart = value
		self.lastValue = value
		self.strengthAt = now
		self.strengthWindow = { { value = value, at = now } }
		return
	end
	self.delta = value - self.sessionStart

	local elapsed = now - (self.strengthAt or now)
	if elapsed < 1 then
		return
	end
	self.strengthAt = now
	self.lastValue = value

	self.strengthWindow = self.strengthWindow or {}
	-- Cap the sample rate: the window only needs enough points to smooth the
	-- figure, and this function runs on a fast timer.
	local rate = pushSample(self.strengthWindow, value, now, STRENGTH_WINDOW_SECONDS, STRENGTH_WINDOW_CAP)
	if rate >= 0 then
		self.perSec = rate
	end
end

function GameMetrics.strengthStats(self)
	return {
		value = self.lastValue or 0,
		delta = self.delta or 0,
		perSec = self.perSec or 0,
	}
end

-- Rebirths, and how fast they are arriving. Measured between consecutive changes
-- in the count, not over the whole session; kept separate from the strength
-- tracker because the two change at completely different rates.
function GameMetrics.trackRebirths(self, now)
	local user = Players.LocalPlayer
	if user == nil then
		return
	end
	local value = PlayerStats.value(user, "Rebirths")

	if self.rebirthValue == nil then
		self.rebirthValue = value
		self.rebirthAt = now
		self.rebirthSampleAt = now
		self.rebirthWindow = { { value = value, at = now } }
		return
	end
	self.rebirthWindow = self.rebirthWindow or {}
	if value == self.rebirthValue then
		-- No change: keep pushing the SAME count, or the window freezes and
		-- "重生/小时" reports the last burst forever. The rate decays because the
		-- window's first sample ages while its value stays behind the count.
		if now - (self.rebirthSampleAt or 0) >= 5 then
			self.rebirthSampleAt = now
			local perSecond = pushSample(self.rebirthWindow, value, now, REBIRTH_WINDOW_SECONDS, REBIRTH_WINDOW_CAP)
			self.rebirthPerHour = if perSecond > 0 then perSecond * 3600 else 0
		end
		return
	end

	local elapsed = now - (self.rebirthAt or now)
	local gained = value - self.rebirthValue
	self.rebirthValue = value
	self.rebirthAt = now
	self.rebirthSampleAt = now
	-- A rebirth counter only ever goes up; a decrease means a rejoin or a reset,
	-- and the rate from it would be nonsense.
	if gained > 0 and elapsed > 1 then
		local perSecond = pushSample(self.rebirthWindow, value, now, REBIRTH_WINDOW_SECONDS, REBIRTH_WINDOW_CAP)
		if perSecond > 0 then
			self.rebirthPerHour = perSecond * 3600
		end
	end
end

function GameMetrics.rebirthStats(self)
	return {
		value = self.rebirthValue or 0,
		perHour = self.rebirthPerHour or 0,
	}
end

-- The player's rebirth multiplier (e.g. 67690 means 67.7K%), or 0 when the game
-- does not expose it.
function GameMetrics.rebirthMultiplier(self)
	local user = Players.LocalPlayer
	if user == nil then
		return 0
	end
	local value = user:FindFirstChild("rebirthMultiplier")
	if value ~= nil and value:IsA("ValueBase") then
		return tonumber(value.Value) or 0
	end
	return 0
end

function GameMetrics.reading(self)
	return self.metrics:reading()
end

-- The current frame rate, for callers that want just that number (the FPS rejoin
-- trigger); the core accumulator stays the only thing that knows how it is
-- measured.
function GameMetrics.fps(self): number
	return self.metrics:fps()
end

function GameMetrics.core(self)
	return self.metrics
end

function GameMetrics.stats(self)
	local reading = self.metrics:reading()
	return {
		fps = reading.fps,
		ping = reading.ping,
		-- The mean above; this is the worst sample in the same window (see
		-- core/Metrics.pushPing) and is what the info panel shows.
		pingWorst = reading.pingWorst,
		pingEstimated = reading.pingEstimated == true,
		memory = reading.memory,
	}
end

function GameMetrics.install(context)
	local self = GameMetrics.new(context)
	self.scheduler:register({
		id = "metrics",
		priority = 150,
		enabled = function()
			return true
		end,
		tick = function(dt, now)
			GameMetrics.tick(self, dt, now)
		end,
	})
	return self
end

return GameMetrics
end

__modules["game/Rejoin"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Rejoin -- leaving and coming back: on a timer, on a bad-client trigger, on an
	error prompt, or on "go to the server a named player is in".

	The decision rules are pure and tested (core/RejoinTriggers,
	core/ServerPick). This file is the HTTP call, the teleport call, and the tasks
	that drive them.

	One deliberate exception to "no ad-hoc coroutines": a rejoin performs a
	BLOCKING http request, and blocking the frame for a round trip would freeze the
	game. It runs in a task.spawn for that reason alone, and it ends in a teleport.
	The player lookup runs the same way.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")

local RejoinTriggers = require("core/RejoinTriggers")
local ServerPick = require("core/ServerPick")

local Rejoin = {}
Rejoin.__index = Rejoin

local STARTUP_GRACE = 15
local CONFIRM_DELAY = 3
local CHECK_INTERVAL = 1
local HTTP_COOLDOWN = 300
--[[
	How long a hop is given to happen. The teleport CALL returns immediately; the
	join does not, and a full target server fails silently, so the only honest
	test is "did `game.JobId` change?" -- which needs a window. 20 s covers a real
	join (and Roblox's own error prompt) without a long wait.
]]
local HOP_TIMEOUT = 20
--[[
	A POSITIVE username -> job id answer is cached for a minute; a NEGATIVE one is
	not, because "he is not in this game" is the most volatile answer this module
	asks about and a stale miss would keep the manual player-targeted rejoin on the
	fallback chain after he came online.
]]
local PLAYER_CACHE = 60
local PLAYER_MISS_TTL = 5

function Rejoin.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		timers = context.timers,
		metrics = context.metrics,
		notify = context.notify or function() end,
		-- Assigned by the UI after it exists (Rejoin is installed BEFORE the
		-- shell in main.luau), so it starts nil and the countdown simply runs
		-- uncancellably until something sets it.
		onPending = context.onPending or nil,
		triggers = RejoinTriggers.new(),
		startedAt = os.clock(),
		timedLast = os.clock(),
		checkAt = 0,
		httpFailedAt = 0,
		-- Private bookkeeping: read it through stats(), change it through
		-- reset()/requestNow(). The UI must never assign these directly.
		_state = "idle",
		_triggered = false,
		pendingHandle = nil,
		-- The gradient chain of the rejoin in flight, and the hop watchdog's
		-- bookkeeping (`hopJobId` is the job id we were on when we tried).
		plan = nil,
		planIndex = 0,
		hopAt = 0,
		hopJobId = "",
		hopLabel = nil,
		playerCache = nil,
		attempts = 0,
	}, Rejoin)
	return self
end

--[[
	The executor's HTTP functions, probed as a LIST because two callers need the
	same answer: `httpRequest` (which needs a function) and the player lookup
	(which needs to know whether a POST was even possible). A list rather than an
	`or` chain because the handlers are not interchangeable -- each candidate is
	tried in turn.
]]
local function httpExecutors()
	local out = {}
	local function add(candidate)
		if type(candidate) == "function" then
			table.insert(out, candidate)
		end
	end
	if type(syn) == "table" then
		add(syn.request)
	end
	if type(http) == "table" then
		add(http.request)
	end
	if type(fluxus) == "table" then
		add(fluxus.request)
	end
	add(request)
	add(http_request)
	return out
end

--[[
	One HTTP call, across every shape of executor.

	THE TWO KEY CASINGS MATTER: the widely-used `request` shim takes LOWERCASE
	keys (`url`, `method`, `body`, `headers`) while `syn.request` and most others
	take them capitalised. A handler handed the wrong casing does not raise -- it
	returns nil or an empty body, which reads as "the player is not there".

	Returns (body, status) where status is the HTTP status code when the executor
	reports one.
]]
local function httpRequest(url, method, body, contentType)
	local verb = method or "GET"
	local headers = if body ~= nil
		then { ["Content-Type"] = contentType or "application/json" }
		else nil

	for _, executor in ipairs(httpExecutors()) do
		-- Capitalised first (the documented shape), then lowercase (the `request`
		-- shim's shape).
		local shapes = {
			{ Url = url, Method = verb, Body = body, Headers = headers },
			{ url = url, method = verb, body = body, headers = headers },
		}
		for _, payload in ipairs(shapes) do
			local ok, response = pcall(executor, payload)
			if ok and type(response) == "table" then
				local text = response.Body or response.body
				if type(text) == "string" and text ~= "" then
					local status = tonumber(response.StatusCode) or tonumber(response.status) or tonumber(response.Status)
					return text, status
				end
			end
		end
	end

	-- `game:HttpGet` is a real Roblox global and works without any executor at
	-- all, so it is worth trying LAST rather than instead.
	if verb == "GET" then
		for _, name in ipairs({ "HttpGetAsync", "HttpGet" }) do
			local fetch = game[name]
			if type(fetch) == "function" then
				local ok, text = pcall(function()
					return fetch(game, url)
				end)
				if ok and type(text) == "string" and text ~= "" then
					return text, nil
				end
			end
		end
	end
	return nil, nil
end

local function httpGet(url)
	return httpRequest(url, "GET", nil, nil)
end

--[[
	Percent-encode a query parameter. Roblox usernames are [%w_] so this is mostly
	a formality -- but the GET fallback puts the name in a URL, and an unencoded
	name is a request for a DIFFERENT user.
]]
local function urlEncode(text: string): string
	return (string.gsub(text, "[^%w%-%._~]", function(character)
		return string.format("%%%02X", string.byte(character))
	end))
end

local function decodeJson(text)
	local ok, payload = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or type(payload) ~= "table" then
		return nil
	end
	return payload :: any
end

-- The id out of `users.roblox.com/v1/usernames/users` (POST).
local function idFromResolve(text)
	local payload = decodeJson(text)
	if payload == nil or type(payload.data) ~= "table" then
		return nil
	end
	for _, entry in ipairs(payload.data) do
		if type(entry) == "table" and entry.id ~= nil then
			return entry.id
		end
	end
	return nil
end

--[[
	The id out of `users.roblox.com/v1/users/search` (GET). The name is matched
	EXACTLY rather than taking the first row: the endpoint is a fuzzy search, and
	following the wrong player is worse than failing to follow one.
]]
local function idFromSearch(text, name)
	local payload = decodeJson(text)
	if payload == nil or type(payload.data) ~= "table" then
		return nil
	end
	local wanted = string.lower(name)
	for _, entry in ipairs(payload.data) do
		if type(entry) == "table" and entry.id ~= nil and type(entry.name) == "string" then
			if string.lower(entry.name) == wanted then
				return entry.id
			end
		end
	end
	return nil
end

--[[
	The job id out of `presence.roblox.com/v1/presence/users` (POST), plus WHY
	there is none -- two different answers for the user:

	    "in-game"     -- here is the server id
	    "offline"     -- not in a game right now (wait for him)
	    "other-place" -- in this game but a different PlaceId, which cannot be
	                     joined with TeleportToPlaceInstance at all
	    "unknown"     -- the answer was not a presence payload

	`gameId` IS the job id Roblox accepts. Its own `placeId` decides whether we
	could join it: a teleport only works inside this PlaceId.
]]
local function jobFromPresence(text)
	local payload = decodeJson(text)
	if payload == nil or type(payload.userPresences) ~= "table" then
		return nil, "unknown"
	end
	for _, entry in ipairs(payload.userPresences) do
		if type(entry) == "table" then
			local gameId = entry.gameId
			local placeId = tonumber(entry.placeId)
			if type(gameId) == "string" and gameId ~= "" then
				if placeId ~= nil and placeId ~= game.PlaceId then
					return nil, "other-place"
				end
				return gameId, "in-game"
			end
		end
	end
	return nil, "offline"
end

--[[
	NAME -> the server he is in, or nil + why. Two API calls in the same
	executor-agnostic wrapper the server list uses; the username lookup is a POST
	(the documented endpoint) with a GET SEARCH fallback, because an executor that
	only implements `game:HttpGet` is a real configuration.
]]
local function lookupPlayerJob(name)
	local userId = nil
	local resolveText = httpRequest(
		"https://users.roblox.com/v1/usernames/users",
		"POST",
		HttpService:JSONEncode({ usernames = { name }, excludeBannedUsers = false })
	)
	if type(resolveText) == "string" and resolveText ~= "" then
		userId = idFromResolve(resolveText)
	end
	if userId == nil then
		local searchText = httpGet(
			"https://users.roblox.com/v1/users/search?keyword=" .. urlEncode(name) .. "&limit=10"
		)
		if type(searchText) == "string" and searchText ~= "" then
			userId = idFromSearch(searchText, name)
		end
	end
	if userId == nil then
		if #httpExecutors() == 0 then
			return nil, "no-http"
		end
		return nil, "unknown"
	end

	local presenceText = httpRequest(
		"https://presence.roblox.com/v1/presence/users",
		"POST",
		HttpService:JSONEncode({ userIds = { userId } })
	)
	if type(presenceText) ~= "string" or presenceText == "" then
		return nil, "no-http"
	end
	return jobFromPresence(presenceText)
end

--[[
	Which server is a named player in? Returns `(jobId, status)`. The status is
	what lets the caller distinguish "he is offline, keep waiting" from "this
	executor cannot look anyone up" -- a single value reported both as "not found"
	and silently downgraded to the next rung of the fallback chain.

	`force` skips the cache.
]]
function Rejoin.playerJobId(self, name, force)
	if name == nil or name == "" then
		return nil, "no-name"
	end
	local cached = self.playerCache
	if force ~= true and cached ~= nil and cached.name == name then
		-- A hit is good for a minute, a miss only for a moment (see PLAYER_MISS_TTL).
		local ttl = if cached.jobId ~= nil and cached.jobId ~= "" then PLAYER_CACHE else PLAYER_MISS_TTL
		if os.clock() - cached.at < ttl then
			return cached.jobId, cached.status
		end
	end

	local jobId, status = lookupPlayerJob(name)
	self.playerCache = { name = name, jobId = jobId, at = os.clock(), status = status }
	return jobId, status
end

-- Fetch the public server list. A failure starts a five-minute cooldown: the
-- endpoint is rate limited and a rejoin is not urgent enough to hammer it.
function Rejoin.fetchServers(self, order)
	local now = os.clock()
	if self.httpFailedAt > 0 and now - self.httpFailedAt < HTTP_COOLDOWN then
		return nil
	end

	local url = string.format(
		"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100",
		game.PlaceId, order
	)
	local body = httpGet(url)
	if body == nil then
		self.httpFailedAt = now
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	local payload = decoded :: any
	if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
		self.httpFailedAt = now
		return nil
	end

	return ServerPick.parse(payload, game.JobId)
end

--[[
	Actually leave -- ONE ATTEMPT AT A TIME, AND VERIFIED.

	`TeleportToPlaceInstance` returns immediately and the join happens afterwards,
	so a FULL server fails SILENTLY: firing every candidate in a loop and stopping
	at the first call that did not raise is not "we joined". The attempt is
	recorded and `hopWatch` checks a few seconds later whether `game.JobId`
	actually changed; if not, the next rung is tried, and when the chain runs out
	the state machine is released rather than latched.

	`modeOverride` lets a caller name its own target for THIS request.
	`exactJobId` is a destination already resolved by the caller, passed in
	rather than looked up again because the player lookup BLOCKS: doing it a second
	time would delay the teleport and risk a different answer.
]]
function Rejoin.perform(self, reason, modeOverride, exactJobId)
	self.notify("正在重进...", "warn")

	local mode = modeOverride or self.store:get("rejoin.mode") or "same"
	local servers = {}
	local order = if mode == "sparse" or mode == "player" or mode == "private" then "Asc" else "Desc"
	servers = if mode == "private" then {} else (Rejoin.fetchServers(self, order) or {})

	-- The player lookup only happens for the mode that needs it, and it is
	-- cached (PLAYER_CACHE / PLAYER_MISS_TTL), so a retry loop does not hammer
	-- the presence API.
	local targetJobId = exactJobId
	if mode == "player" and targetJobId == nil then
		local name = self.store:get("rejoin.targetPlayer")
		local jobId, status = Rejoin.playerJobId(self, if type(name) == "string" then name else "")
		targetJobId = jobId
		if jobId == nil then
			self.notify(string.format("找不到目标玩家 %s（%s），按梯度降级",
				tostring(name or ""), tostring(status)), "warn")
		end
	end

	local attempts = ServerPick.chain(mode, servers, game.JobId, self.store:get("rejoin.privId"), targetJobId)
	self.plan = attempts
	self.planIndex = 0
	return Rejoin.attemptNext(self, reason)
end

-- Try the next rung. Returns true when an attempt was actually dispatched.
function Rejoin.attemptNext(self, reason)
	local attempts = self.plan
	if attempts == nil then
		return false
	end
	local user = Players.LocalPlayer
	if user == nil then
		return false
	end

	while true do
		self.planIndex += 1
		local attempt = attempts[self.planIndex]
		if attempt == nil then
			--[[
				THE CHAIN IS EXHAUSTED. Latching `_triggered` here would make the
				rejoin feature dead for the rest of the session, so the state
				machine is RELEASED and the user is told.
			]]
			self.notify("换服失败：所有目标都没进去（可能都满了）", "error")
			Rejoin.reset(self)
			self.plan = nil
			return false
		end

		-- The rung we are already on is not a rejoin.
		if attempt.kind == "job" and (attempt.id == nil or attempt.id == "" or attempt.id == game.JobId) then
			if attempt.id == game.JobId and self.planIndex < #attempts then
				continue
			end
			if attempt.id == nil or attempt.id == "" then
				continue
			end
			-- Same server as the last rung and nothing else left: stop.
			self.notify("没有可换的服务器，留在当前服", "warn")
			Rejoin.reset(self)
			self.plan = nil
			return false
		end

		self.hopJobId = game.JobId
		self.hopAt = os.clock()
		self.hopLabel = attempt.label
		self.attempts += 1

		local ok = false
		if attempt.kind == "private" then
			ok = pcall(function()
				TeleportService:TeleportToPrivateServer(game.PlaceId, attempt.code, { user })
			end)
		else
			ok = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, attempt.id, user)
			end)
		end

		if ok then
			self.notify(string.format("尝试换服：%s", attempt.label), "info")
			return true
		end

		-- The call itself failed: this rung is not usable, try the next now.
		self.notify(string.format("%s 无法传送，试下一个目标", attempt.label), "warn")
	end
end

--[[
	Did the hop actually happen? Checked from a 1 Hz task: `game.JobId` is the only
	honest answer, because a teleport call succeeding while the server stays the
	same means the target was full.
]]
function Rejoin.hopWatch(self, now)
	if self.hopAt == nil or self.hopAt == 0 then
		return
	end
	if now - self.hopAt < HOP_TIMEOUT then
		return
	end

	if game.JobId ~= self.hopJobId then
		-- We are somewhere else: nothing left to do (the session is being
		-- replaced by whatever the hop landed in).
		self.hopAt = 0
		return
	end

	self.hopAt = 0
	self.notify(string.format("%s 超时未生效（多半已满），自动降级", tostring(self.hopLabel or "目标服务器")), "warn")
	if Rejoin.attemptNext(self, "hop-timeout") == false then
		-- attemptNext released the state machine when the chain ran out.
		self.hopAt = 0
	end
end

--[[
	Off-frame wrapper: the HTTP calls a rejoin makes BLOCK, so they must not run on
	the frame the request arrives -- `perform` can be reached from a scheduler tick
	inside the Heartbeat callback.
]]
function Rejoin.spawnPerform(self, reason, modeOverride, exactJobId)
	task.spawn(function()
		pcall(function()
			Rejoin.perform(self, reason, modeOverride, exactJobId)
		end)
	end)
end

--[[
	Start an urgent rejoin NOW: no countdown, no dialog. The boot grace is NOT
	re-checked here -- it was already applied against the clock the SCHEDULER
	supplied, and checking it again against `os.clock()` would make the grace
	depend on two different clocks.
]]
function Rejoin.beginUrgent(self, reason, modeOverride, exactJobId)
	self._state = "running"
	self._triggered = true
	Rejoin.spawnPerform(self, reason, modeOverride, exactJobId)
	return true
end

--[[
	Ask to rejoin: urgent requests go immediately, everything else gets a
	three-second cancellable countdown. `modeOverride` and `exactJobId` are
	threaded through untouched -- they are the caller's target (see Rejoin.perform).
]]
function Rejoin.request(self, reason, urgent, modeOverride, exactJobId)
	if os.clock() - self.startedAt < STARTUP_GRACE then
		self.notify("游戏正在加载，15 秒内禁止重进", "warn")
		return false
	end
	if self._triggered or self._state ~= "idle" then
		return false
	end

	if urgent then
		return Rejoin.beginUrgent(self, reason, modeOverride, exactJobId)
	end

	self._state = "pending"
	self.notify(string.format("原因：%s\n3 秒后自动重进（可取消）", tostring(reason or "")), "warn")

	--[[
		The cancel dialog: the toast promises "可取消", so `cancelPending` needs a
		caller -- otherwise the countdown cannot be stopped. The UI is injected
		rather than constructed here because this module must stay ui-free.
	]]
	if self.onPending ~= nil then
		pcall(self.onPending, tostring(reason or ""), function()
			return Rejoin.cancelPending(self)
		end, function()
			-- Confirm means "go now", not "wait out the rest of the countdown".
			if self._state ~= "pending" then
				return false
			end
			if self.pendingHandle ~= nil then
				self.pendingHandle:cancel()
				self.pendingHandle = nil
			end
			return Rejoin.beginUrgent(self, reason, modeOverride, exactJobId)
		end)
	end

	self.pendingHandle = self.timers:after(os.clock(), CONFIRM_DELAY, function()
		if self._state ~= "pending" then
			return
		end
		self.pendingHandle = nil
		Rejoin.beginUrgent(self, reason, modeOverride, exactJobId)
	end)
	return true
end

function Rejoin.cancelPending(self)
	if self._state ~= "pending" then
		return false
	end
	if self.pendingHandle ~= nil then
		self.pendingHandle:cancel()
		self.pendingHandle = nil
	end
	self._state = "idle"
	self.notify("已取消重进", "info")
	return true
end

--[[
	Put the state machine back to idle, dropping any pending countdown. Callers
	(the manual button, a keybind) never assign `_state` / `_triggered`
	themselves: writing them from outside couples the UI to the implementation.
]]
function Rejoin.reset(self)
	self._state = "idle"
	self._triggered = false
	if self.pendingHandle ~= nil then
		self.pendingHandle:cancel()
		self.pendingHandle = nil
	end
end

-- A user-initiated rejoin: clear anything latched, then ask normally (with the
-- cancellable countdown, not the urgent path). `modeOverride` names the target
-- server for this request alone (the event-boss hop uses it).
function Rejoin.requestNow(self, reason, modeOverride)
	Rejoin.reset(self)
	return Rejoin.request(self, reason, false, modeOverride)
end

function Rejoin.tick(self, now)
	local store = self.store
	if self._triggered or self._state ~= "idle" then
		return
	end
	if now - self.checkAt < CHECK_INTERVAL then
		return
	end
	self.checkAt = now

	local reasons = self.triggers:evaluate({
		memEnabled = store:get("rejoin.memTrigger") == true,
		memThreshold = tonumber(store:get("rejoin.memThresh")) or 4000,
		fpsEnabled = store:get("rejoin.fpsTrigger") == true,
		fpsThreshold = tonumber(store:get("rejoin.fpsThresh")) or 8,
		pingEnabled = store:get("rejoin.pingTrigger") == true,
		pingThreshold = tonumber(store:get("rejoin.pingThresh")) or 800,
	}, self.metrics:reading(), now)

	if #reasons > 0 then
		Rejoin.request(self, table.concat(reasons, "，"), false)
	end
end

function Rejoin.timedTick(self, now)
	if self.store:get("rejoin.timedEnabled") ~= true then
		return
	end
	if self._triggered or self._state ~= "idle" then
		return
	end
	local minutes = tonumber(self.store:get("rejoin.timedMin")) or 30
	if now - self.timedLast < minutes * 60 then
		return
	end
	self.timedLast = now
	self._state = "running"
	self._triggered = true
	Rejoin.spawnPerform(self, string.format("定时重进（%d 分钟）", minutes))
end

-- The error prompt Roblox shows on a disconnect.
function Rejoin.errorMessage()
	local ok, gui = pcall(function()
		return CoreGui
	end)
	if not ok or gui == nil then
		return nil
	end
	local prompt = gui:FindFirstChild("RobloxPromptGui")
	if prompt == nil then
		return nil
	end
	local overlay = prompt:FindFirstChild("promptOverlay")
	if overlay == nil then
		return nil
	end

	--[[
		`promptOverlay` is a Frame, and a Frame has no `Enabled` property: reading
		`overlay.Enabled` raised "Enabled is not a valid member of Frame" on every
		tick, flooding the log and never detecting a disconnect. `Visible` is the
		property a Frame has and the one that means "on screen"; the read is
		guarded so a Roblox change to this container cannot flood again.
	]]
	local okVisible, visible = pcall(function()
		return overlay.Visible
	end)
	if not okVisible or visible ~= true then
		return nil
	end
	local title = overlay:FindFirstChild("ErrorTitle")
	local body = overlay:FindFirstChild("ErrorMsg")
	local text = ((title ~= nil and title.Text) or "") .. " " .. ((body ~= nil and body.Text) or "")
	if #text > 3 then
		return text
	end
	return nil
end

function Rejoin.emergencyTick(self, now)
	if self.store:get("rejoin.emergEnabled") ~= true then
		return
	end
	if self._triggered or self._state ~= "idle" then
		return
	end
	local message = Rejoin.errorMessage()
	if message == nil then
		return
	end
	self.notify("紧急重进：" .. string.sub(message, 1, 30), "warn")
	Rejoin.request(self, "紧急：" .. string.sub(message, 1, 25), true)
end

function Rejoin.stats(self)
	return {
		state = self._state,
		triggered = self._triggered,
		attempts = self.attempts,
	}
end

function Rejoin.install(context)
	local self = Rejoin.new(context)
	local store = self.store

	self.scheduler:register({
		id = "rejoin",
		priority = 50,
		enabled = function()
			return store:get("rejoin.enabled") == true
		end,
		tick = function(_dt, now)
			Rejoin.tick(self, now)
		end,
	})

	self.scheduler:register({
		id = "timedRejoin",
		priority = 50,
		enabled = function()
			return store:get("rejoin.timedEnabled") == true
		end,
		tick = function(_dt, now)
			Rejoin.timedTick(self, now)
		end,
	})

	self.scheduler:register({
		id = "emergency",
		priority = 50,
		enabled = function()
			return store:get("rejoin.emergEnabled") == true
		end,
		tick = function(_dt, now)
			Rejoin.emergencyTick(self, now)
		end,
	})

	--[[
		The hop watchdog -- always on, deliberately NOT gated on any switch. Many
		callers start a hop, and once one is in flight THIS decides whether it
		worked; gating it on `rejoin.enabled` would leave the event-boss hop stuck
		forever with `_triggered` set.
	]]
	self.scheduler:register({
		id = "hopWatch",
		priority = 48,
		enabled = function()
			return true
		end,
		tick = function(_dt, now)
			Rejoin.hopWatch(self, now)
		end,
	})

	return self
end

return Rejoin
end

__modules["game/AntiAfk"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	AntiAfk -- staying connected while idle.

	Two mechanisms, because one is not enough: `Player.Idled` is the reliable
	signal (Roblox raises it before treating the player as away; capturing the
	controller and clicking is the documented response), and a periodic click
	covers anything that does not raise it. The interval is capped at 1140s by
	the config schema, so it always fires before Roblox's 20-minute limit.

	The periodic task is `essential`, so "pause" stops the automation without
	stopping the thing that keeps the player connected. The Idled connection is
	handed to the Runtime so the single-owner invariant holds.
]]

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local AntiAfk = {}
AntiAfk.__index = AntiAfk

local CLICK_TAIL = 0.02

function AntiAfk.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		timers = context.timers,
		runtime = context.runtime,
		-- Set by bindKick on disconnect; also stops the timer fighting teardown.
		kicked = false,
		last = os.clock(),
		count = 0,
	}, AntiAfk)
	return self
end

function AntiAfk.tick(self, now)
	local interval = tonumber(self.store:get("antiAfk.interval")) or 300
	if now - self.last < interval then
		return
	end
	self.last = now

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	self.count += 1

	-- Bottom-right corner: a real click in a harmless place.
	local viewport = camera.ViewportSize
	local position = Vector2.new(math.max(1, viewport.X - 1), math.max(1, viewport.Y - 1))
	pcall(function()
		VirtualUser:Button2Down(position, camera.CFrame)
	end)
	self.timers:after(now, CLICK_TAIL, function()
		pcall(function()
			VirtualUser:Button2Up(position, camera.CFrame)
		end)
	end)
end

function AntiAfk.bind(self)
	local user = Players.LocalPlayer
	if user == nil then
		return
	end
	local connection = user.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
		self.last = os.clock()
	end)
	if self.runtime ~= nil then
		self.runtime:trackConnection(connection)
	end
end

--[[
	AncestryChanged with `Parent == nil` means the client was disconnected
	(kicked, dropped or shut down). Requests URGENT rejoin: the 3-second countdown
	window has already passed, so waiting would only delay the requeue.
]]
function AntiAfk.bindKick(self, rejoin)
	local user = Players.LocalPlayer
	if user == nil or rejoin == nil then
		return
	end
	-- Probe rather than assume: AncestryChanged is not present on every executor
	-- or test-harness Player proxy, and a missing signal must not fail the boot.
	local changed = user.AncestryChanged
	if changed == nil then
		return
	end
	local connection = changed:Connect(function(_, parent)
		if parent ~= nil or self.kicked then
			return
		end
		self.kicked = true
		warn("[MKUltraHUB][afk] 检测到离开游戏（被踢出或掉线）")
		-- Delay so a genuine shutdown is not fought with a remote call in teardown.
		task.delay(0.5, function()
			pcall(function()
				rejoin:request("被踢出", true)
			end)
		end)
	end)
	if self.runtime ~= nil then
		self.runtime:trackConnection(connection)
	end
end

function AntiAfk.stats(self)
	return {
		count = self.count,
		interval = tonumber(self.store:get("antiAfk.interval")) or 300,
	}
end

function AntiAfk.install(context)
	local self = AntiAfk.new(context)
	AntiAfk.bind(self)
	AntiAfk.bindKick(self, context.rejoin)

	self.scheduler:register({
		id = "afk",
		priority = 30,
		-- Runs while the scheduler is paused: staying connected is not part of
		-- the automation the pause switch turns off.
		essential = true,
		enabled = function()
			return true
		end,
		tick = function(_dt, now)
			AntiAfk.tick(self, now)
		end,
	})

	return self
end

return AntiAfk
end

__modules["game/Perf"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Perf -- the anti-lag pass: effects off, textures off, shadows and lighting
	culled, all of it reversible.

	Three independently switchable groups (`perf.removeEffects`,
	`perf.removeTextures`, `perf.cull`):

	  EFFECTS   ParticleEmitter, Trail, Beam, Fire, Smoke, Sparkles, the three
	            light classes, Bloom/Blur/SunRays/DepthOfField/ColorCorrection ->
	            `Enabled = false`; Atmosphere.Density -> 0; Clouds off.
	  TEXTURES  Decal and Texture -> `Transparency = 1`: still there and still
	            scriptable, just not drawn or sampled.
	  CULLING   BasePart.CastShadow -> false, Lighting.GlobalShadows off,
	            ShadowSoftness 0, EnvironmentDiffuse/SpecularScale -> 0.

	DELIBERATELY NOT TOUCHED:
	  * `BasePart.Material` / `Reflectance` -- Material feeds the physics
	    material (friction, elasticity), so a performance switch must not be able
	    to alter gameplay.
	  * `BasePart.Transparency` -- turning the world invisible is not
	    optimisation.
	  * Anything under `PlayerGui` -- `ImageLabel.ImageTransparency` has the same
	    shape as `Decal.Transparency`, so only the Workspace walk keeps "hide
	    every image" off the interface.

	Every change is recorded as {object, property, original} and replayed on
	disable, so switching the option off -- or unloading -- restores the world
	exactly. Objects that stream out are skipped on restore, not resurrected.
]]

local Lighting = game:GetService("Lighting")

local Perf = {}
Perf.__index = Perf

-- How much of the sweep runs per frame, and how long between sweeps. A sweep
-- builds `Workspace:GetDescendants()` plus `Lighting:GetDescendants()` and then
-- writes hundreds of properties: that is a real frame spike, and a spike looks
-- like a client crash from outside. The work is idempotent, so a slower sweep
-- costs only latency.
local BUDGET_PER_TICK = 250
local RESCAN_SECONDS = 90

-- Class -> the single property that switches it off, and the value to write.
-- `true` means "record whatever it was and set it false"; `1` means
-- "record whatever it was and set it to 1 (fully transparent)".
local EFFECT_OFF = {
	ParticleEmitter = "Enabled",
	Trail = "Enabled",
	Beam = "Enabled",
	Fire = "Enabled",
	Smoke = "Enabled",
	Sparkles = "Enabled",
	-- NOTE: `Explosion` is deliberately absent: it has no `Enabled` member (only
	-- `Visible`) and is a one-frame event, so listing it would cost a failed
	-- property read each time.
	PointLight = "Enabled",
	SpotLight = "Enabled",
	SurfaceLight = "Enabled",
	BloomEffect = "Enabled",
	BlurEffect = "Enabled",
	SunRaysEffect = "Enabled",
	DepthOfFieldEffect = "Enabled",
	ColorCorrectionEffect = "Enabled",
	Clouds = "Enabled",
}

local TEXTURE_HIDE = {
	Decal = "Transparency",
	Texture = "Transparency",
}

function Perf.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		lighting = nil,
		snapshot = nil,
		cursor = 0,
		disabled = 0,
		nextScanAt = nil,
		-- One list of reversible edits: {object = , prop = , value = }.
		restores = {},
		groups = { effects = 0, textures = 0, culled = 0 },
	}, Perf)
	return self
end

-- Record the original value and apply the new one. Called for one object and one
-- property; skipping the record when nothing would change keeps `restores` (and
-- the counter the UI reads) honest.
local function setProp(self, object, prop, value, group)
	local ok, current = pcall(function()
		return object[prop]
	end)
	if not ok or current == value then
		return false
	end
	table.insert(self.restores, { object = object, prop = prop, value = current, group = group })
	local applied = pcall(function()
		object[prop] = value
	end)
	if applied then
		self.disabled += 1
		self.groups[group] += 1
		return true
	end
	-- The write failed: drop the record, or disable() would "restore" a value
	-- that was never changed.
	table.remove(self.restores)
	return false
end

function Perf.enable(self)
	if self.lighting ~= nil then
		return
	end

	--[[
		Lighting globals are read ONCE per enable and replayed on disable: they
		are not instances so they are not in the descendant walk, and they are the
		cheapest big win -- `GlobalShadows` off removes the shadow map pass for
		the whole map.
	]]
	local saved = {
		GlobalShadows = nil,
		ShadowSoftness = nil,
		EnvironmentDiffuseScale = nil,
		EnvironmentSpecularScale = nil,
	}
	pcall(function()
		saved.GlobalShadows = Lighting.GlobalShadows
	end)
	pcall(function()
		saved.ShadowSoftness = Lighting.ShadowSoftness
	end)
	pcall(function()
		saved.EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale
	end)
	pcall(function()
		saved.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
	end)
	self.lighting = saved

	self.restores = {}
	self.groups = { effects = 0, textures = 0, culled = 0 }
	self.disabled = 0
	self.snapshot = nil
	self.cursor = 0
	-- Due immediately: the first sweep starts on the next tick.
	self.nextScanAt = 0
end

local function applyCulling(self)
	pcall(function()
		Lighting.GlobalShadows = false
	end)
	pcall(function()
		Lighting.ShadowSoftness = 0
	end)
	pcall(function()
		Lighting.EnvironmentDiffuseScale = 0
	end)
	pcall(function()
		Lighting.EnvironmentSpecularScale = 0
	end)
end

function Perf.tick(self, now)
	if self.lighting == nil then
		return
	end

	local list = self.snapshot
	if list == nil then
		-- Between sweeps. Without this gate the snapshot was cleared on
		-- completion and the next tick re-walked every descendant, turning the
		-- anti-lag pass into a recurring frame spike.
		if now < (self.nextScanAt or 0) then
			return
		end
		local ok, descendants = pcall(function()
			--[[
				WORKSPACE **AND LIGHTING**: post-processing (Bloom, Blur,
				SunRays, DepthOfField, ColorCorrection, Atmosphere, Clouds)
				lives under `Lighting`, so a Workspace-only walk could never
				reach the "移除特效" group. `Sky` is left alone on purpose --
				turning the background off is a different game, not optimisation.
			]]
			local out = Workspace:GetDescendants()
			local effects = Lighting:GetDescendants()
			for _, object in ipairs(effects) do
				table.insert(out, object)
			end
			return out
		end)
		if not ok then
			-- A failed walk must not be retried every frame either.
			self.nextScanAt = now + RESCAN_SECONDS
			return
		end
		self.snapshot = descendants
		self.cursor = 0

		--[[
			The switch state is read ONCE per sweep, not once per object: four
			store reads 500 times a tick would cost more than the walk, and a
			sweep that changed its mind half way would leave the world in a state
			no single setting describes.
		]]
		self.wantEffects = self.store:get("perf.removeEffects") ~= false
		self.wantTextures = self.store:get("perf.removeTextures") ~= false
		self.wantCull = self.store:get("perf.cull") ~= false
		if self.wantCull then
			applyCulling(self)
		end
		return
	end

	local last = math.min(#list, self.cursor + BUDGET_PER_TICK)
	for index = self.cursor + 1, last do
		local object = list[index]
		if object.Parent ~= nil then
			local class = object.ClassName
			local effectProp = if self.wantEffects then EFFECT_OFF[class] else nil
			if effectProp ~= nil then
				setProp(self, object, effectProp, false, "effects")
			elseif class == "Atmosphere" then
				if self.wantEffects then
					setProp(self, object, "Density", 0, "effects")
				end
			else
				local textureProp = if self.wantTextures then TEXTURE_HIDE[class] else nil
				if textureProp ~= nil then
					setProp(self, object, textureProp, 1, "textures")
				elseif self.wantCull and object:IsA("BasePart") then
					setProp(self, object, "CastShadow", false, "culled")
				end
			end
		end
	end
	self.cursor = last

	if self.cursor >= #list then
		self.snapshot = nil
		self.nextScanAt = now + RESCAN_SECONDS
	end
end

function Perf.disable(self)
	self.snapshot = nil
	self.cursor = 0
	self.nextScanAt = nil
	-- The read-out means "objects disabled right now", so it goes back to zero
	-- with them; leaving the old total made the counter climb forever.
	self.disabled = 0
	self.groups = { effects = 0, textures = 0, culled = 0 }

	-- Reverse order, so anything that was touched twice ends on its first value.
	for index = #self.restores, 1, -1 do
		local record = self.restores[index]
		local object = record.object
		if object ~= nil and object.Parent ~= nil then
			pcall(function()
				object[record.prop] = record.value
			end)
		end
	end
	table.clear(self.restores)

	local saved = self.lighting
	if saved ~= nil then
		self.lighting = nil
		Perf.restoreLighting(saved)
	end
end

-- Put the four global Lighting values back. Split out so the `perf.cull`
-- subscription can undo just this group without tearing the whole pass down.
function Perf.restoreLighting(saved)
	if saved == nil then
		return
	end
	if saved.GlobalShadows ~= nil then
		pcall(function()
			Lighting.GlobalShadows = saved.GlobalShadows
		end)
	end
	if saved.ShadowSoftness ~= nil then
		pcall(function()
			Lighting.ShadowSoftness = saved.ShadowSoftness
		end)
	end
	if saved.EnvironmentDiffuseScale ~= nil then
		pcall(function()
			Lighting.EnvironmentDiffuseScale = saved.EnvironmentDiffuseScale
		end)
	end
	if saved.EnvironmentSpecularScale ~= nil then
		pcall(function()
			Lighting.EnvironmentSpecularScale = saved.EnvironmentSpecularScale
		end)
	end
end

--[[
	Undo ONE group and forget its records -- used when the user switches one of the
	three sub-options back off. The sweep can only ever switch things OFF, so
	waiting for the next one to "notice" reads as a broken control. The remaining
	groups keep their records, so the pass stays half-applied exactly as the
	switch state says.
]]
function Perf.restoreGroup(self, group)
	local kept = {}
	for _, record in ipairs(self.restores) do
		if record.group == group then
			local object = record.object
			if object ~= nil and object.Parent ~= nil then
				pcall(function()
					object[record.prop] = record.value
				end)
			end
			self.disabled = math.max(0, self.disabled - 1)
			self.groups[group] = math.max(0, self.groups[group] - 1)
		else
			table.insert(kept, record)
		end
	end
	self.restores = kept
	if group == "culled" then
		Perf.restoreLighting(self.lighting)
	end
	-- A fresh sweep with the new switch state; the old snapshot's decisions are
	-- no longer the current ones.
	self.snapshot = nil
	self.cursor = 0
	self.nextScanAt = 0
end

local GROUP_OF_PATH = {
	["perf.removeEffects"] = "effects",
	["perf.removeTextures"] = "textures",
	["perf.cull"] = "culled",
}

function Perf.stats(self)
	return {
		active = self.lighting ~= nil,
		disabled = self.disabled,
		scanning = self.snapshot ~= nil,
		effects = self.groups.effects,
		textures = self.groups.textures,
		culled = self.groups.culled,
	}
end

function Perf.install(context)
	local self = Perf.new(context)
	local store = context.store

	self.scheduler:register({
		id = "antilag",
		priority = 140,
		enabled = function()
			return store:get("perf.antiLag") == true and store:get("perf.disabled") ~= true
		end,
		onEnable = function()
			Perf.enable(self)
		end,
		onDisable = function()
			Perf.disable(self)
		end,
		tick = function(_dt, now)
			Perf.tick(self, now)
		end,
	})

	-- The "disable performance options" switch has to undo whatever is running,
	-- rather than only preventing future work.
	self.scheduler:register({
		id = "perfGuard",
		priority = 139,
		enabled = function()
			return store:get("perf.disabled") == true and self.lighting ~= nil
		end,
		tick = function()
			Perf.disable(self)
		end,
	})

	--[[
		Turning one of the three sub-switches OFF has to undo that group now, not
		wait for the next sweep; the subscription undoes it immediately.
	]]
	for _, path in ipairs({ "perf.removeEffects", "perf.removeTextures", "perf.cull" }) do
		store:subscribe(path, function(_, value)
			if value == true or self.lighting == nil then
				return
			end
			Perf.restoreGroup(self, GROUP_OF_PATH[path] or "culled")
		end)
	end

	return self
end

return Perf
end

__modules["game/Train"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Train -- the automatic training subsystem.

	Three lines of policy plus one call:

	    read the settings from the store
	    ask TrainRate how many packets this frame is worth   (pure, tested)
	    ask Net to burst that many                         (pure, tested)

	Wire throttling follows cfg.trainThrottle: OFF leaves the "muscle" channel
	unlimited (what fast training is for); ON puts it behind a real token bucket.
	Either way the pacing arithmetic is the same and the channel keeps its own
	sent/dropped/penalty counters.
]]

local TrainRate = require("core/TrainRate")
local Arbiter = require("core/Arbiter")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")
local Tools = require("game/Tools")
local Pets = require("game/Pets")

local Players = game:GetService("Players")

local Train = {}

Train.CHANNEL = "muscle"

-- 2000/s matches TrainRate.FAST_CAP: beyond that the switch would silently
-- change the user's configured rate rather than just guarding the wire.
Train.THROTTLE_RATE = 2000
Train.THROTTLE_BURST = 64

--[[
	Consecutive-send-failure latch: fail N times, sit out a window, then try
	again. `Net.burst` only breaks the burst it is in, so a muscle remote that
	exists but rejects every call would otherwise be retried at full rate every
	frame -- a waste and a plausible kick trigger. The window matters more than
	the count, because a transient failure must not disable training for the
	session.
]]
Train.FAILURE_LIMIT = 15
Train.FAILURE_BACKOFF = 10

function Train.install(context)
	local store = context.store
	local net = context.net
	local scheduler = context.scheduler
	local character = context.character
	local isCombatBusy = context.isCombatBusy or function()
		return false
	end
	local isBossAlive = context.isBossAlive or function()
		return false
	end
	local isMachineBusy = context.isMachineBusy or function()
		return false
	end
	local pets = context.pets or nil
	local arbiter = context.arbiter or nil
	local notify = context.notify or function() end

	local state = TrainRate.newState()
	local delivered = 0
	local refused = 0
	local throttled = nil
	local failures = 0
	local disabledUntil = 0

	--[[
		One question, asked by two tasks: "does training need the hand right
		now?" Training and punching cannot both hold the tool, so training enabled
		DURING combat has to be arbitrated. `arbitrationActive` is shared by the
		tool arbiter (`dualTool`, which alternates the hand on a symmetric dwell)
		and the plain tool task (`tool`, which must stand down or the two equip
		different tools in the same frame).

		It is true for "global kill" and for a boss fight because both re-equip
		the glove on every punch. Both halves are the NARROW truth -- a target
		actually in the crosshairs, a boss task actually holding the body --
		rather than the switches: reading the switches stood the arbiter up for the
		whole session and training never held a tool long enough to count.
	]]
	local function combatActive()
		if isCombatBusy() then
			return true
		end
		return store:get("boss.auto") == true and isBossAlive()
	end

	local function arbitrationActive()
		if not (store:get("train.auto") == true or store:get("train.fast") == true) then
			return false
		end
		if not combatActive() then
			return false
		end
		if store:get("kill.dualEnabled") == true then
			return true
		end
		if store:get("train.duringKill") == true and isCombatBusy() then
			return true
		end
		if store:get("train.duringBoss") == true and store:get("boss.auto") == true and isBossAlive() then
			return true
		end
		return false
	end

	-- The tool "sets" the user can enable, ordered STRONGEST FIRST: push-up,
	-- handstand and sit-up are the level-2 exercises and pay more per rep than the
	-- level-1 dumbbell. `holdTrainingTool` takes the first one the backpack can
	-- equip, so enabling a level-2 tool keeps the level-1 one as a fallback rather
	-- than as an equal turn in a rotation.
	local function toolGroups()
		local groups = {}
		if store:get("train.toolPush") == true then
			table.insert(groups, Tools.PUSHUP)
		end
		if store:get("train.toolHand") == true then
			table.insert(groups, Tools.HANDSTAND)
		end
		if store:get("train.toolSit") == true then
			table.insert(groups, Tools.SITUP)
		end
		if store:get("train.toolDumbbell") == true then
			table.insert(groups, Tools.DUMBBELL)
		end
		return groups
	end

	--[[
		Hold the BEST training tool the player has -- and keep it.

		The tiers are not equal: push-up / handstand / sit-up are the level-2
		exercises and pay more per rep than the level-1 dumbbell. A rotation
		between them spent half the session on the weaker exercise, which is the
		"为什么一直在哑铃和俯卧撑之间来回换" report. The list is ordered strongest
		first; the first group the backpack can actually equip wins and stays
		there, and the weaker ones are fallbacks for when it is missing -- not
		turns in a rotation.

		A missing tool is not treated as a hold: the game can take it back (a
		death, a zone reset), and parking the hand on something that is not there
		would cost both the reps AND the punches for the whole window.
	]]
	local function holdTrainingTool(humanoid, player, character)
		local groups = toolGroups()
		if #groups == 0 then
			state.toolGroup = nil
			return false
		end
		for _, group in ipairs(groups) do
			if Tools.equip(character, humanoid, player, group) then
				state.toolGroup = group
				return true
			end
		end
		state.toolGroup = nil
		return false
	end

	-- The channel has to be (re)created when the throttle switch flips, because
	-- "unlimited" and "rate-limited" are different objects, not a setting.
	local function ensureChannel()
		local want = store:get("cfg.trainThrottle") == true
		if throttled == want then
			return
		end
		throttled = want
		net:addChannel(Train.CHANNEL, GameNet.senderFor(Remotes.muscle), {
			rate = if want then Train.THROTTLE_RATE else nil,
			burst = Train.THROTTLE_BURST,
			queue = 0,
		})
	end

	-- Named `definition`, not `task`: a local called `task` shadows the Roblox
	-- global task table.
	local definition = {
		id = "train",
		priority = 100,
		enabled = function()
			return store:get("train.fast") == true or store:get("train.auto") == true
		end,
		onDisable = function()
			state.tokens = 0
		end,
		tick = function(dt, now)
			ensureChannel()

			-- The latch: after FAILURE_LIMIT consecutive frames in which nothing
			-- was accepted, sit out FAILURE_BACKOFF seconds before trying again.
			if disabledUntil ~= 0 then
				if now < disabledUntil then
					return
				end
				disabledUntil = 0
				failures = 0
			end

			local settings = {
				auto = store:get("train.auto") == true,
				fast = store:get("train.fast") == true,
				rate = tonumber(store:get("train.rate")) or 20,
			}

			local rate = TrainRate.compute(settings, 60)
			local source = if settings.fast then "手动" elseif settings.auto then "自动" else "关闭"
			-- Published for the page: "why is it sending at 40/s when I typed 900"
			-- is otherwise unanswerable without reading this file.
			store:set("train.effRate", math.floor(rate + 0.5))
			store:set("train.rateSource", source)
			local perFrame = math.max(1, math.floor(tonumber(store:get("cfg.netBurst")) or 40))
			local budget = TrainRate.step(state, rate, dt, perFrame)
			if budget <= 0 then
				return
			end

			-- Cheap cached lookup: without it a missing remote would report an
			-- error every single frame.
			if Remotes.muscle() == nil then
				TrainRate.refund(state, budget)
				return
			end

			local sent = net:burst(Train.CHANNEL, now, budget, "rep")
			delivered += sent
			if sent < budget then
				refused += (budget - sent)
				TrainRate.refund(state, budget - sent)

				--[[
					Nothing at all got through: one failure step. The latch is
					keyed on `sent == 0` rather than on `refused`, which counts
					REFUSED payloads including a rate limiter doing its job -- one
					frame of backpressure is not a failure.
				]]
				if sent == 0 then
					failures += 1
					if failures >= Train.FAILURE_LIMIT then
						failures = 0
						disabledUntil = now + Train.FAILURE_BACKOFF
						warn(string.format("[MKUltraHUB][train] 连续 %d 次发包失败，暂停 %d 秒",
							Train.FAILURE_LIMIT, Train.FAILURE_BACKOFF))
					end
				else
					failures = 0
				end
			else
				failures = 0
			end
		end,
	}

	--[[
		快速锻炼 / 自动锻炼 are mutually exclusive but nothing enforced it, so both
		keys could be on and `TrainRate.compute` silently let `fast` win. A store
		subscription (not onChange) so a loaded config or slot is covered too.
	]]
	store:subscribe("train.fast", function(_, value)
		if value == true and store:get("train.auto") == true then
			store:set("train.auto", false)
		end
	end)
	store:subscribe("train.auto", function(_, value)
		if value == true and store:get("train.fast") == true then
			store:set("train.fast", false)
		end
	end)

	scheduler:register(definition)

	--[[
		Announce the depth, and switch the training pet preset.

		A low-priority reporter (priority 5, so everything that can change the
		answer has run) publishing the resolved depth for the UI, and asking for
		the "train" pet preset while training actually happens -- only the rebirth
		path used to call Pets.scheduleSwap, so train/kill/boss presets were
		configurable and never applied in game.
	]]
	if arbiter ~= nil then
		local trainInstance = arbiter:instance("train", "train.auto", Arbiter.Depth.MACHINE, Arbiter.Depth.BODY)
		scheduler:register({
			id = "trainDepth",
			priority = 5,
			enabled = function()
				return store:get("train.auto") == true or store:get("train.fast") == true
			end,
			tick = function()
				local verdict = trainInstance:resolve()
				-- Refused (floor above the cap) is reported as idle rather than as
				-- a depth: claiming a rung we may not use would be a lie the UI
				-- then repeats.
				local level = if verdict.allowed then verdict.depth else Arbiter.Depth.IDLE
				store:set("train.depth", level)
				store:set("train.depthLabel", Arbiter.LABELS[level] or "空闲")
				store:set("train.depthReason", verdict.reason or "")
				if pets ~= nil and verdict.allowed and verdict.depth > Arbiter.Depth.IDLE then
					Pets.scheduleSwap(pets, "train", 0.5)
				end
			end,
		})
	else
		-- No arbiter: still publish a truthful depth so the read-out is not blank.
		scheduler:register({
			id = "trainDepth",
			priority = 5,
			enabled = function()
				return store:get("train.auto") == true or store:get("train.fast") == true
			end,
			tick = function()
				store:set("train.depth", Arbiter.Depth.FREE_WEIGHT)
				store:set("train.depthLabel", Arbiter.LABELS[Arbiter.Depth.FREE_WEIGHT] or "")
				store:set("train.depthReason", "")
			end,
		})
	end

	--[[
		Keep the best training tool in hand. The preference order is expressed as
		a list of keyword groups so "which tool would we rather hold" is data
		rather than four nested ifs.

		One guard matters: the task stands down while dual-tool combat has taken
		over the glove. It does NOT stand down for a machine any more -- a seat
		does not take the hand away, and the two channels pay separately.
	]]
	local missingSince = 0
	local lastAttempt = 0
	local lastRespawn = 0
	local respawns = 0
	local cooldown = false
	-- While a seat holds the player the tool is only re-asserted once a second:
	-- the hand is already where it should be, and re-equipping is the one action
	-- that could stand the player up in a game that refuses tools while seated.
	local machineToolAt = 0

	--[[
		Clear the give-up latch when the user asks for a tool. Without a way back
		it was a ONE-WAY DOOR for the session: the UI showed the toggles, turning
		one back on did nothing, and only reloading helped.

		Only `value == true` clears it: the give-up path writes these keys as
		false, and reacting to that would immediately un-latch the task.
	]]
	for _, path in ipairs({ "train.toolDumbbell", "train.toolPush", "train.toolHand", "train.toolSit" }) do
		store:subscribe(path, function(_, value)
			if value == true then
				cooldown = false
				missingSince = 0
				-- A fresh user request gets a fresh respawn budget.
				respawns = 0
			end
		end)
	end

	scheduler:register({
		id = "tool",
		priority = 60,
		--[[
			The "同时锻炼 / 同时重生" policy: `train.duringBoss` and
			`train.duringKill` used to be toggles with no reader, and the real
			gating was unconditional. What the user wants is not "ignore the
			conflict" but "step down and carry on": training lowers its depth (the
			machine releases the seat) and keeps going on the lower rungs, so the
			flags decide whether this task stands down or steps down.
		]]
		enabled = function()
			if not (store:get("train.auto") == true or store:get("train.fast") == true) then
				return false
			end
			if cooldown then
				return false
			end
			--[[
				The arbiter owns the hand whenever combat and training overlap:
				two tasks equipping two different tools in the same frame made
				"同时锻炼" useless -- whichever ran last won, and the glove is
				re-equipped on every punch (up to 120x/s) while this task only gets
				a look every 0.12 s. Exactly ONE of them may own the hand, and when
				both want it the alternation below is the owner.
			]]
			if arbitrationActive() then
				return false
			end
			--[[
				NO `isMachineBusy` stand-down. Sitting on a machine and holding a
				training tool are two separate channels in this game: the seat pays
				its own reps, and the tool in hand pays on top of it. Some machines
				also cap how long they can be used, so the tool is exactly what
				keeps production up while the seat is on cooldown. Equipping a tool
				does not take the seat away.
			]]
			return true
		end,
		tick = function(_dt, now)
			-- 0.05 s rather than 0.12: the tool task only runs OUTSIDE the dual
			-- arbiter, and the user's report is about how long a swap takes.
			if now - lastAttempt < 0.05 then
				return
			end
			lastAttempt = now

			local groups = toolGroups()
			if #groups == 0 then
				missingSince = 0
				return
			end

			local humanoid = character:humanoid()
			local model = character:current()
			local seated = isMachineBusy()
			if seated and now - machineToolAt < 1 then
				return
			end
			if seated then
				machineToolAt = now
			end
			if holdTrainingTool(humanoid, Players.LocalPlayer, model) then
				missingSince = 0
				return
			end
			--[[
				While a machine holds the player, the seat is doing the training. A
				seat that refuses the equip is not a missing tool, so it must never
				start the "找不到训练工具" respawn countdown.
			]]
			if seated then
				missingSince = 0
				return
			end

			if missingSince == 0 then
				missingSince = now
				return
			end
			if now - missingSince < 3 or now - lastRespawn < 90 then
				return
			end

			lastRespawn = now
			respawns += 1
			if store:get("cfg.autoSuicide") == true and respawns <= 2 then
				notify(string.format("找不到训练工具，重生 %d/2", respawns), "warn")
				if humanoid ~= nil then
					pcall(function()
						humanoid.Health = 0
					end)
				end
			else
				-- Stop trying rather than killing the player over and over.
				cooldown = true
				notify("找不到训练工具，已停止自动切换", "error")
				store:set("train.toolDumbbell", false)
				store:set("train.toolPush", false)
				store:set("train.toolHand", false)
				store:set("train.toolSit", false)
			end
		end,
		onDisable = function()
			missingSince = 0
			state.toolGroup = nil
		end,
	})

	--[[
		The tool arbiter: alternate the glove and a training tool while fighting.

		The asymmetry this replaces: `Combat.punch` re-equips the glove on every
		punch (twice per attack tick, plus the 0.05 s boss cadence -- up to 120x a
		second) while the training tool was offered once per 0.05 s flip, so the
		glove won every frame and a rep never registered. What makes the halves
		equal:

		  * ONE DWELL for both, `kill.dualInterval` (default 0.15 s, tunable);
		  * the held tool is published as `train.dualTool` and BOTH punch paths
		    stand down while it reads "train", so the training half is a real
		    window rather than a race;
		  * the hand is re-asserted every 0.03 s, so the game taking the tool away
		    is repaired inside the same window.

		The mode only becomes "train" after the tool is actually in hand: parking
		the hand on a tool the player does not own would mean no punches AND no
		reps for the whole dwell.
	]]
	local dualMode = "punch"
	local dualSince = 0
	local dualAssertAt = 0

	local function setDualMode(mode, now)
		dualMode = mode
		dualSince = now
		store:set("train.dualTool", mode)
	end

	scheduler:register({
		id = "dual",
		priority = 62,
		enabled = arbitrationActive,
		onEnable = function()
			dualAssertAt = 0
			setDualMode("punch", os.clock())
		end,
		onDisable = function()
			-- Leaving the arbitration must hand the glove back immediately, or
			-- the guard would refuse to re-equip while nothing is training.
			setDualMode("punch", os.clock())
		end,
		tick = function(_dt, now)
			--[[
				The re-assert rate, part of keeping the alternation tight: at
				0.08 s on a 0.15 s dwell the swap could be delayed by 80 ms on
				either side. 0.03 s is still slower than a frame.
			]]
			if now - dualAssertAt < 0.03 then
				return
			end
			dualAssertAt = now

			local humanoid = character:humanoid()
			local model = character:current()
			if humanoid == nil or model == nil then
				return
			end
			local player = Players.LocalPlayer
			local dwell = math.max(0.1, tonumber(store:get("kill.dualInterval")) or 0.15)

			if dualMode == "train" then
				-- Argument order is (humanoid, player, character) -- passing the
				-- character first made every re-assert fail, so the alternation fell
				-- back to "punch" on the next tick and the training half never
				-- existed.
				if holdTrainingTool(humanoid, player, model) then
					if now - dualSince >= dwell then
						setDualMode("punch", now)
					end
					return
				end
				-- No usable training tool: never park the hand on a tool that is
				-- not there. Back to punching at once.
				setDualMode("punch", now)
				return
			end

			Tools.equip(model, humanoid, player, Tools.PUNCH)
			if now - dualSince >= dwell then
				-- The start of a train half: take the best tool available, not "the
				-- next one in a rotation".
				if holdTrainingTool(humanoid, player, model) then
					setDualMode("train", now)
				end
			end
		end,
	})

	return {
		task = definition,
		state = state,
		stats = function()
			return {
				delivered = delivered,
				refused = refused,
				dualTool = dualMode,
			}
		end,
	}
end

return Train
end

__modules["ui/Theme"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- Theme -- the colour roles, and repainting a live UI when the theme changes.
-- The mapping decision is core/Palette (pure, tested); this file holds the role
-- tables, converts to Color3, and walks a GUI tree applying the remap.
-- Repainting in place rather than rebuilding (as V1007 did) keeps the colours
-- tweening and the window still.

local TweenService = game:GetService("TweenService")

local Palette = require("core/Palette")
local Attributes = require("core/Attributes")

local Theme = {}

-- The palette types are declared locally rather than referenced as
-- Palette.RGB / Palette.Roles / Palette.Remap: a cross-module type annotation
-- does not survive bundling (`Palette` stops being a type namespace, and the
-- dist gate reports "Unknown type 'Palette.RGB'"). The src gate cannot see it.
type RGB = { r: number, g: number, b: number }
type Roles = { [string]: RGB }
type RemapEntry = { from: RGB, to: RGB }
type Remap = { exact: { [string]: RGB }, entries: { RemapEntry } }

Theme.NAMES = { "light", "dark", "ocean", "sakura", "forest", "flame" }
Theme.FALLBACK = "light"
-- Per-channel tolerance for "is this widget wearing the old theme's colour?".
-- 6/255 catches widgets caught mid-tween or on a hover shade while staying
-- inside the ~15-unit gaps between palette roles, so nothing is remapped to a
-- neighbouring colour.
Theme.RECOLOR_TOLERANCE = 6
Theme.RECOLOR_TIME = 0.38

Theme.ROLES = {
	"White", "Bg", "BgSoft", "BgHover", "Border", "Divider",
	"TextPrimary", "TextSecond", "TextMuted", "Green", "Red", "Yellow", "Accent",
}

local function rgb(r, g, b)
	return { r = r, g = g, b = b }
end

local PALETTES = {
	light = {
		White = rgb(255, 255, 255), Bg = rgb(242, 244, 246), BgSoft = rgb(236, 238, 242),
		BgHover = rgb(226, 230, 236), Border = rgb(28, 30, 34), Divider = rgb(208, 212, 218),
		TextPrimary = rgb(24, 26, 30), TextSecond = rgb(90, 95, 105), TextMuted = rgb(140, 145, 155),
		Green = rgb(46, 170, 82), Red = rgb(214, 55, 60), Yellow = rgb(228, 175, 45),
		Accent = rgb(64, 120, 255),
	},
	dark = {
		White = rgb(34, 36, 42), Bg = rgb(20, 22, 26), BgSoft = rgb(44, 48, 55),
		BgHover = rgb(58, 64, 72), Border = rgb(90, 95, 105), Divider = rgb(64, 70, 80),
		TextPrimary = rgb(240, 242, 245), TextSecond = rgb(180, 185, 195), TextMuted = rgb(130, 135, 145),
		Green = rgb(90, 200, 120), Red = rgb(240, 90, 95), Yellow = rgb(240, 200, 80),
		Accent = rgb(88, 150, 255),
	},
	ocean = {
		White = rgb(34, 58, 82), Bg = rgb(15, 32, 52), BgSoft = rgb(34, 58, 82),
		BgHover = rgb(50, 80, 110), Border = rgb(70, 110, 140), Divider = rgb(55, 85, 110),
		TextPrimary = rgb(220, 235, 250), TextSecond = rgb(160, 190, 220), TextMuted = rgb(110, 140, 170),
		Green = rgb(70, 200, 180), Red = rgb(240, 90, 100), Yellow = rgb(240, 200, 90),
		Accent = rgb(64, 196, 255),
	},
	sakura = {
		White = rgb(92, 58, 82), Bg = rgb(52, 32, 46), BgSoft = rgb(72, 48, 68),
		BgHover = rgb(98, 68, 92), Border = rgb(200, 140, 175), Divider = rgb(140, 90, 120),
		TextPrimary = rgb(255, 225, 240), TextSecond = rgb(240, 185, 215), TextMuted = rgb(195, 145, 175),
		Green = rgb(140, 230, 170), Red = rgb(255, 110, 140), Yellow = rgb(255, 210, 110),
		Accent = rgb(255, 120, 180),
	},
	forest = {
		White = rgb(44, 72, 48), Bg = rgb(20, 40, 25), BgSoft = rgb(38, 62, 44),
		BgHover = rgb(52, 88, 58), Border = rgb(80, 130, 85), Divider = rgb(58, 88, 62),
		TextPrimary = rgb(225, 245, 225), TextSecond = rgb(175, 215, 175), TextMuted = rgb(125, 165, 125),
		Green = rgb(120, 220, 120), Red = rgb(230, 90, 90), Yellow = rgb(230, 200, 80),
		Accent = rgb(96, 200, 120),
	},
	flame = {
		White = rgb(92, 42, 32), Bg = rgb(46, 22, 16), BgSoft = rgb(72, 36, 26),
		BgHover = rgb(102, 58, 42), Border = rgb(180, 90, 60), Divider = rgb(122, 62, 42),
		TextPrimary = rgb(255, 230, 210), TextSecond = rgb(240, 180, 150), TextMuted = rgb(185, 135, 110),
		Green = rgb(150, 220, 120), Red = rgb(255, 110, 80), Yellow = rgb(255, 200, 80),
		Accent = rgb(255, 140, 80),
	},
}

local ROLE_CACHE: { [string]: { [string]: Color3 } } = {}

function Theme.palette(name: string?): Roles
	return PALETTES[name or Theme.FALLBACK] or PALETTES[Theme.FALLBACK]
end

-- A membership set, because `Theme.palette` falls back to the default instead of
-- returning nil: a nil check would be dead code, and a typo'd name would sail
-- through and be written to the store.
local NAME_SET: { [string]: boolean } = {}
for _, entry in ipairs(Theme.NAMES) do
	NAME_SET[entry] = true
end

function Theme.has(name: string?): boolean
	return name ~= nil and NAME_SET[name] == true
end

function Theme.toColor3(triple: RGB): Color3
	return Color3.fromRGB(triple.r, triple.g, triple.b)
end

-- Colour -> integer RGB, or nil for anything that is not one. `Theme.apply`
-- walks every widget, so returning nil skips one unreadable property instead of
-- aborting the repaint halfway (the "主题切换后颜色残留在旧主题" symptom).
function Theme.toRGB(color: Color3): RGB?
	if typeof(color) ~= "Color3" then
		return nil
	end
	local ok, red, green, blue = pcall(function()
		return color.R, color.G, color.B
	end)
	if not ok or type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
		return nil
	end
	return {
		r = math.floor(red * 255 + 0.5),
		g = math.floor(green * 255 + 0.5),
		b = math.floor(blue * 255 + 0.5),
	}
end

-- Role -> Color3, cached per theme because widgets ask constantly.
function Theme.roles(name: string?): { [string]: Color3 }
	local key = name or Theme.FALLBACK
	local cached = ROLE_CACHE[key]
	if cached ~= nil then
		return cached
	end
	local built = {}
	for role, triple in pairs(Theme.palette(key)) do
		built[role] = Theme.toColor3(triple)
	end
	ROLE_CACHE[key] = built
	return built
end

function Theme.remap(fromName: string?, toName: string?): Remap
	return Palette.build(Theme.palette(fromName), Theme.palette(toName))
end

local COLOR_PROPERTIES = {
	"BackgroundColor3",
	"TextColor3",
	"PlaceholderColor3",
	"ImageColor3",
	"ScrollBarImageColor3",
	"TextStrokeColor3",
}

-- Repaint a GUI tree in place, returning how many properties changed so a
-- silent zero is visible to the caller. The tolerance means a widget caught
-- mid-tween or in a hover state is still recognised as the old theme's colour.
function Theme.apply(root: Instance?, remap: Remap, duration: number?): number
	if root == nil then
		return 0
	end
	local time = duration or Theme.RECOLOR_TIME
	local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local changed = 0

	-- Every object is repainted inside its own pcall: one widget that throws
	-- costs that widget's colour, not the whole repaint. `Theme.toRGB` returns
	-- nil for a colour it cannot read, so each branch below checks first.
	for _, object in ipairs(root:GetDescendants()) do
		pcall(function()
			for _, property in ipairs(COLOR_PROPERTIES) do
				local ok, current = pcall(function()
					return object[property]
				end)
				local rgb = if ok then Theme.toRGB(current) else nil
				if rgb ~= nil then
					local mapped = Palette.nearest(remap, rgb, Theme.RECOLOR_TOLERANCE)
					if mapped ~= nil then
						TweenService:Create(object, tweenInfo, { [property] = Theme.toColor3(mapped) }):Play()
						changed += 1
					end
				end
			end

			local stroke = object:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				local rgb = Theme.toRGB(stroke.Color)
				local mapped = if rgb ~= nil then Palette.nearest(remap, rgb, Theme.RECOLOR_TOLERANCE) else nil
				if mapped ~= nil then
					TweenService:Create(stroke, tweenInfo, { Color = Theme.toColor3(mapped) }):Play()
					changed += 1
				end
			end

			local gradient = object:FindFirstChildOfClass("UIGradient")
			if gradient ~= nil then
				local sequence = gradient.Color
				if sequence ~= nil and sequence.Keypoints ~= nil then
					local keypoints = {}
					local touched = false
					for _, keypoint in ipairs(sequence.Keypoints) do
						local rgb = Theme.toRGB(keypoint.Value)
						local mapped = if rgb ~= nil then Palette.nearest(remap, rgb, Theme.RECOLOR_TOLERANCE) else nil
						if mapped ~= nil then
							touched = true
							table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, Theme.toColor3(mapped)))
						else
							table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, keypoint.Value))
						end
					end
					if touched then
						TweenService:Create(gradient, tweenInfo, { Color = ColorSequence.new(keypoints) }):Play()
						changed += 1
					end
				end
			end

			-- Buttons remember their resting colour in an attribute so that a hover
			-- leaving cannot write the previous theme's colour back.
			local base = object:GetAttribute(Attributes.BASE_COLOR)
			local baseRGB = Theme.toRGB(base)
			if baseRGB ~= nil then
				local mapped = Palette.nearest(remap, baseRGB, Theme.RECOLOR_TOLERANCE)
				if mapped ~= nil then
					object:SetAttribute(Attributes.BASE_COLOR, Theme.toColor3(mapped))
					changed += 1
				end
			end
		end)
	end

	return changed
end

return Theme
end

__modules["ui/Kit"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- Kit -- the interface component library.
-- The one thing that matters: a bound component READS and WRITES the Store and
-- re-renders from a Store subscription; it never keeps its own copy. V1007's
-- `UI.toggle` held a local `val` while `Core.train.auto` held the real one, reconciled
-- by a one-hertz polling loop, so the copies drifted and a missed pass left a control
-- permanently out of step. Here `spec.path` is the single place the value lives: the
-- click handler writes it, the subscription repaints. Pathless components (buttons,
-- notes) keep no state at all.

local TweenService = game:GetService("TweenService")
-- The GLOBAL input stream, and the reason the slider below can be dragged at all:
-- pressing on the 18px track captures the mouse, but the pointer leaves that
-- rectangle immediately, so a handler on the GuiObject's own `InputChanged` stops
-- receiving movement the moment the drag starts.
local UserInputService = game:GetService("UserInputService")

local Attributes = require("core/Attributes")

local Kit = {}
Kit.__index = Kit

local ROW_HEIGHT = 40
local ROW_HEIGHT_WITH_HINT = 52
local DROPDOWN_MAX_HEIGHT = 300
local DROPDOWN_OPTION_HEIGHT = 26
-- How far a finger has to travel before a slider takes over the gesture from
-- the page's scroll (pixels). Mouse presses are exempt; see Kit.slider.
local TOUCH_ARM = 8

function Kit.new(context)
	-- Guard against the collision that silently broke the entire interface. The widget
	-- factory is `Kit.instance(class, props, parent)`, and calling the CONSTRUCTOR as
	-- if it were that factory does not raise in either form: `self:new(...)` passes the
	-- Kit as `context` (bringing a perfectly good `.store` and `.roles`), `Kit.new("Frame",
	-- ...)` passes a string that indexes to nil. Either way a Kit came back where an
	-- Instance was expected, so every widget became a Kit and the damage only showed up
	-- later, at the first `uiCorner.Parent = <kit>`, as an empty page.
	if type(context) ~= "table" then
		error("Kit.new expects a context table; the widget factory is Kit.instance(class, props, parent)", 2)
	end
	if getmetatable(context) == Kit then
		error("Kit.new was called as a widget factory (self:new(class, ...)); use Kit.instance(class, props, parent)", 2)
	end
	local self = setmetatable({
		store = context.store,
		screen = context.screen,
		roles = context.roles,
		-- Optional: when the runtime's Timers is injected, delayed UI callbacks
		-- are cancellable and die with `Runtime.destroy()`.
		timers = context.timers,
		connections = {},
		destroyed = false,
	}, Kit)
	return self
end

-- plumbing --------------------------------------------------------------------

-- Resolve a role to a colour. Three levels, because the return value is assigned
-- straight to Roblox colour properties: a miss on both the role and its fallback used
-- to return nil, and `BackgroundColor3 = nil` is a hard error. A mistyped role should
-- look wrong, not crash the window; the last resort is opaque white, which every theme
-- has as a surface colour.
function Kit.color(self, role, fallback)
	local color = self.roles[role]
	if color ~= nil then
		return color
	end
	local substitute = self.roles[fallback or "TextPrimary"]
	if substitute ~= nil then
		return substitute
	end
	return Color3.new(1, 1, 1)
end

-- Ordering is a counter per parent, not `#parent:GetChildren() * 10`: the original
-- recomputed that for every widget, which is quadratic over a page with fifty controls.
function Kit.nextOrder(self, parent)
	local current = parent:GetAttribute(Attributes.ORDER)
	if current == nil then
		current = 0
	end
	local next = current + 1
	parent:SetAttribute(Attributes.ORDER, next)
	return next
end

function Kit.instance(self, class, props, parent)
	local object = Instance.new(class)
	if props ~= nil then
		for key, value in pairs(props) do
			if key ~= "Parent" then
				object[key] = value
			end
		end
	end
	if parent ~= nil then
		object.Parent = parent
	end
	return object
end

function Kit.corner(self, object, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = object
	return corner
end

function Kit.stroke(self, object, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or self:color("Border")
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

-- A wide, very transparent black stroke reads as a drop shadow and follows the
-- widget automatically, so there is no second object to keep in sync.
function Kit.shadow(self, object, thickness, transparency)
	local shadow = Instance.new("UIStroke")
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Thickness = thickness or 14
	shadow.Transparency = transparency or 0.88
	shadow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shadow.Parent = object
	return shadow
end

function Kit.pad(self, object, top, bottom, left, right)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top or 0)
	padding.PaddingBottom = UDim.new(0, bottom or 0)
	padding.PaddingLeft = UDim.new(0, left or 0)
	padding.PaddingRight = UDim.new(0, right or 0)
	padding.Parent = object
	return padding
end

function Kit.list(self, object, spacing, horizontal)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing or 6)
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = object
	return layout
end

function Kit.tween(self, object, time, props, style, direction)
	if object == nil or object.Parent == nil then
		return nil
	end
	local ok, tween = pcall(function()
		return TweenService:Create(
			object,
			TweenInfo.new(time or 0.14, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
			props
		)
	end)
	if ok and tween ~= nil then
		tween:Play()
		return tween
	end
	return nil
end

function Kit.track(self, connection)
	if connection ~= nil then
		table.insert(self.connections, connection)
	end
	return connection
end

-- Report something the user just did. The Kit does not own the toast stack (that
-- lives in ui/Toast and needs the screen), so `main.luau` installs `kit.onToast` once
-- the stack exists; before that -- and in a headless test -- this is a silent no-op
-- rather than an error.
function Kit.toast(self, text, kind, duration)
	if self.onToast == nil then
		return
	end
	pcall(self.onToast, text, kind, duration)
end

-- Schedule a delayed UI callback through the runtime's Timers when one was injected,
-- so `Runtime.destroy()` cancels it: a raw `task.delay` cannot be cancelled, so on
-- unload every pending one still fires and each has to defend itself with a
-- `self.destroyed` / `parent ~= nil` guard -- those guards are the symptom, the timer
-- dying with the runtime is the fix. `task.delay` stays the fallback for a Kit built
-- without a runtime (e.g. a unit test), so a missing dependency is never a crash.
function Kit.delay(self, seconds, fn)
	local timers = self.timers
	if timers ~= nil then
		return timers:after(os.clock(), seconds, fn)
	end
	task.delay(seconds, fn)
	return nil
end

function Kit.destroy(self)
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self.connections)
end

-- Bind a widget to a store path. `apply` renders a value: it runs once immediately
-- with the current value (or `default` when the store has none) and again on every
-- subsequent change -- including changes made by another subsystem, which is what makes
-- the widget and the state structurally incapable of disagreeing.
-- The second argument tells `apply` this is the initial paint; an animating widget must
-- snap on it, because tweening the in-frame correction made every control on a freshly
-- opened page visibly flip itself.
function Kit.bind(self, path, default, apply)
	local current = self.store:get(path)
	apply(if current == nil then default else current, true)
	self:track(self.store:subscribe(path, function(_, value)
		if value ~= nil then
			apply(value, false)
		end
	end))
end

-- layout ----------------------------------------------------------------------

function Kit.section(self, parent, text)
	local holder = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
	self:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -8, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = self:color("TextPrimary"),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, holder)
	return holder
end

-- Returns the inner container (where rows go) and the card Frame itself.
function Kit.card(self, parent)
	local card = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
	self:corner(card, 8)
	self:stroke(card, self:color("Border"), 1, 0)
	self:shadow(card, 7, 0.93)
	card:SetAttribute(Attributes.CARD, true)

	local highlight = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = self:color("Accent"),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, card)
	self:corner(highlight, 1)

	local inner = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, card)
	self:list(inner, 8)
	self:pad(inner, 10, 10, 12, 12)
	return inner, card
end

function Kit.note(self, parent, text)
	return self:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = text,
		TextColor3 = self:color("TextMuted"),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
end

function Kit.divider(self, parent)
	return self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = self:color("Divider"),
		BorderSizePixel = 0,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
end

function Kit.row(self, parent, withHint)
	local height = if withHint then ROW_HEIGHT_WITH_HINT else ROW_HEIGHT
	local row = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
	return row
end

function Kit.rowLabel(self, row, text, hint, reserve)
	local label = self:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, if hint ~= nil then 8 else 0),
		Size = UDim2.new(1, -(reserve or 60), 0, 20),
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = self:color("TextPrimary"),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
	local hintLabel = nil
	if hint ~= nil then
		hintLabel = self:instance("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, -(reserve or 60), 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Font = Enum.Font.Gotham,
			Text = hint,
			TextColor3 = self:color("TextMuted"),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, row)
	end
	return label, hintLabel
end

-- Hover/press feedback shared by every button in the UI.
function Kit.animate(self, button, base)
	local resting = base or button.BackgroundColor3
	button:SetAttribute(Attributes.BASE_COLOR, resting)
	button.AutoButtonColor = false

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button
	local stroke = button:FindFirstChildOfClass("UIStroke")

	self:track(button.MouseEnter:Connect(function()
		if self.theming then
			return
		end
		self:tween(button, 0.12, { BackgroundColor3 = self:color("BgHover") })
		self:tween(scale, 0.12, { Scale = 1.02 })
		if stroke ~= nil then
			self:tween(stroke, 0.12, { Color = self:color("Accent"), Transparency = 0.15, Thickness = 1.6 })
		end
	end))
	self:track(button.MouseLeave:Connect(function()
		-- Deliberately NOT gated on `theming`: restoring the resting colour is always
		-- correct, and the resting colour kept in `_MK_Base` is itself remapped by the
		-- theme pass -- suppressing this during a theme switch only left a button the
		-- pointer had been over stuck on the hover colour (one of the ways "颜色残留"
		-- showed up).
		local stored = button:GetAttribute(Attributes.BASE_COLOR) or resting
		self:tween(button, 0.12, { BackgroundColor3 = stored })
		self:tween(scale, 0.12, { Scale = 1 })
		if stroke ~= nil then
			self:tween(stroke, 0.12, { Color = self:color("Border"), Transparency = 0, Thickness = 1 })
		end
	end))
	self:track(button.MouseButton1Down:Connect(function()
		self:tween(scale, 0.07, { Scale = 0.96 })
	end))
	self:track(button.MouseButton1Up:Connect(function()
		self:tween(scale, 0.12, { Scale = 1 })
	end))
	return button
end

-- widgets --------------------------------------------------------------------

-- spec = { label, path?, default?, onChange?, hint? }
-- With `path` the toggle is a view onto that store key: clicking writes it and the
-- subscription repaints. Without one the toggle keeps its own value and calls
-- `onChange` -- for the rare control that has no state.
function Kit.toggle(self, parent, spec)
	local row = self:row(parent, spec.hint ~= nil)
	self:rowLabel(row, spec.label, spec.hint)

	local track = self:instance("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(46, 24),
		BackgroundColor3 = self:color("BgSoft"),
		BorderSizePixel = 0,
	}, row)
	self:corner(track, 12)
	self:stroke(track, self:color("Border"), 1, 0.45)

	local knob = self:instance("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = self:color("TextMuted"),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	self:corner(knob, 10)
	local knobScale = Instance.new("UIScale")
	knobScale.Scale = 1
	knobScale.Parent = knob

	local value = spec.default == true

	-- `instant` snaps rather than tweens. It is the initial paint and the
	-- programmatic seeding path that pass it; a user click always animates.
	local function render(on, instant)
		local onColor = self:color("Green")
		local offColor = self:color("BgSoft")
		if instant then
			track.BackgroundColor3 = if on then onColor else offColor
			knob.Position = if on then UDim2.new(1, -22, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
			knob.BackgroundColor3 = if on then self:color("White") else self:color("TextMuted")
			return
		end
		self:tween(track, 0.18, { BackgroundColor3 = if on then onColor else offColor })
		self:tween(knob, 0.2, {
			Position = if on then UDim2.new(1, -22, 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
		}, Enum.EasingStyle.Quint)
		knob.BackgroundColor3 = if on then self:color("White") else self:color("TextMuted")
		knobScale.Scale = 0.84
		self:tween(knobScale, 0.26, { Scale = 1 }, Enum.EasingStyle.Quint)
	end

	if spec.path ~= nil then
		self:bind(spec.path, spec.default == true, function(raw, initial)
			value = raw == true
			render(value, initial == true)
		end)
	elseif spec.get ~= nil and spec.watch ~= nil then
		-- A switch that drives a derived value rather than a boolean key: "auto
		-- rebirth" is really `rebirth.rate > 0`. Reading and writing go through the
		-- caller, and it re-renders whenever the watched key moves.
		value = spec.get() == true
		render(value, true)
		self:track(self.store:subscribe(spec.watch, function()
			value = spec.get() == true
			render(value)
		end))
	else
		render(value, true)
	end

	local hit = self:instance("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(70, 34),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 3,
	}, row)

	self:track(hit.MouseButton1Click:Connect(function()
		local next = not value
		if spec.path ~= nil then
			-- Writing the store is the whole handler: the subscription repaints.
			self.store:set(spec.path, next)
		elseif spec.write ~= nil then
			spec.write(next)
		else
			value = next
			render(next)
			if spec.onChange ~= nil then
				task.spawn(spec.onChange, next)
			end
		end
		-- Report the flip: most switches give no feedback beyond the knob moving, and
		-- on a page of twenty switches that is indistinguishable from a dead click.
		-- Toast coalescing keeps a rapid sequence from stacking.
		if spec.silent ~= true then
			self:toast(tostring(spec.label) .. (if next then "：已开启" else "：已关闭"), if next then "success" else "info", 1.2)
		end
	end))

	return {
		get = function()
			return value
		end,
		set = function(v)
			if spec.path ~= nil then
				self.store:set(spec.path, v == true)
			else
				value = v == true
			end
		end,
	}
end

-- spec = { label, path?, min, max, default?, hint? } -- a whole number box.
function Kit.input(self, parent, spec)
	local row = self:row(parent, spec.hint ~= nil)
	self:rowLabel(row, spec.label, spec.hint, 110)

	local minimum = spec.min or 0
	local maximum = spec.max or 100
	local fallback = spec.default or minimum

	local box = self:instance("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(90, 30),
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = tostring(fallback),
		TextColor3 = self:color("TextPrimary"),
		TextSize = 14,
		PlaceholderText = string.format("%d-%d", minimum, maximum),
		PlaceholderColor3 = self:color("TextMuted"),
		ClearTextOnFocus = false,
	}, row)
	self:corner(box, 6)
	self:stroke(box, self:color("Border"), 1, 0)

	if spec.path ~= nil then
		self:bind(spec.path, fallback, function(raw)
			box.Text = tostring(math.floor(tonumber(raw) or fallback))
		end)
	end

	self:track(box.FocusLost:Connect(function()
		local parsed = tonumber(box.Text)
		if parsed == nil then
			box.Text = tostring(fallback)
			return
		end
		local clamped = math.clamp(math.floor(parsed), minimum, maximum)
		box.Text = tostring(clamped)
		if spec.path ~= nil then
			self.store:set(spec.path, clamped)
		end
		if spec.onChange ~= nil then
			task.spawn(spec.onChange, clamped)
		end
		if spec.silent ~= true then
			self:toast(string.format("[%s] = %d", tostring(spec.label), clamped), "info", 1.4)
		end
	end))

	return box
end

-- spec = { label, path?, default?, hint?, placeholder? } -- free text
function Kit.textInput(self, parent, spec)
	local row = self:row(parent, spec.hint ~= nil)
	self:rowLabel(row, spec.label, spec.hint, 110)

	local box = self:instance("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 30),
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = tostring(spec.default or ""),
		TextColor3 = self:color("TextPrimary"),
		TextSize = 13,
		PlaceholderText = spec.placeholder or "",
		PlaceholderColor3 = self:color("TextMuted"),
		ClearTextOnFocus = false,
	}, row)
	self:corner(box, 6)
	self:stroke(box, self:color("Border"), 1, 0)

	if spec.path ~= nil then
		self:bind(spec.path, spec.default or "", function(raw)
			box.Text = tostring(raw or "")
		end)
	end

	self:track(box.FocusLost:Connect(function()
		if spec.path ~= nil then
			self.store:set(spec.path, box.Text)
		end
		if spec.onChange ~= nil then
			task.spawn(spec.onChange, box.Text)
		end
	end))

	return box
end

-- spec = { label, path?, min, max, default?, hint?, commitOnly? }
function Kit.slider(self, parent, spec)
	local minimum = spec.min or 0
	local maximum = spec.max or 100
	local fallback = spec.default or minimum
	local mapping = spec.map

	-- The stored value and the displayed value can be different things: the font
	-- scale is stored as a multiplier (0.8-1.5) but shown as a percentage.
	local function toStore(displayed)
		if mapping ~= nil and mapping.toStore ~= nil then
			return mapping.toStore(displayed)
		end
		return displayed
	end
	local function fromStore(stored)
		if mapping ~= nil and mapping.fromStore ~= nil then
			return mapping.fromStore(stored)
		end
		return stored
	end

	local row = self:row(parent, spec.hint ~= nil)
	self:rowLabel(row, spec.label, spec.hint, 70)

	local valueLabel = self:instance("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(70, 20),
		Font = Enum.Font.GothamBold,
		Text = tostring(fallback),
		TextColor3 = self:color("TextPrimary"),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, row)

	local trackBar = self:instance("Frame", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundColor3 = self:color("BgSoft"),
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, row)
	self:corner(trackBar, 9)

	local function fraction(value)
		return (value - minimum) / math.max(1, maximum - minimum)
	end

	local fill = self:instance("Frame", {
		Size = UDim2.new(fraction(fallback), 0, 1, 0),
		BackgroundColor3 = self:color("Accent"),
		BorderSizePixel = 0,
	}, trackBar)
	self:corner(fill, 9)

	local knob = self:instance("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(fraction(fallback), 0, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, trackBar)
	self:corner(knob, 10)
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = self:color("Accent")
	knobStroke.Thickness = 3
	knobStroke.Transparency = 0.3
	knobStroke.Parent = knob

	-- A 44-PIXEL TOUCH TARGET AROUND AN 18-PIXEL STRIP: the visual track stays thin,
	-- but the hit area WAS the strip itself, so on a phone a finger aimed at the row
	-- below can land on the slider, and a finger trying to hit the slider needs pixel
	-- accuracy. The button overflows the track (which does not clip).
	local hit = self:instance("TextButton", {
		Position = UDim2.fromOffset(0, -13),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		ZIndex = 4,
	}, trackBar)

	-- FREEZE THE PAGE WHILE THE SLIDER OWNS THE GESTURE: otherwise a horizontal drag
	-- that started on the track also scrolled the page by the vertical part of the same
	-- movement, which on touch reads as the slider "fighting" the list.
	local scrollLock = nil
	local function scrollingAncestor()
		local node: Instance? = trackBar.Parent
		while node ~= nil do
			if node:IsA("ScrollingFrame") then
				return node
			end
			node = node.Parent
		end
		return nil
	end
	local function lockScroll(on: boolean)
		if on then
			if scrollLock == nil then
				local frame = scrollingAncestor()
				if frame ~= nil and frame.ScrollingEnabled then
					scrollLock = frame
					frame.ScrollingEnabled = false
				end
			end
		elseif scrollLock ~= nil then
			scrollLock.ScrollingEnabled = true
			scrollLock = nil
		end
	end

	local current = fallback

	-- `instant` snaps rather than tweens (the initial paint and setRange);
	-- dragging and store updates animate.
	local function render(value, instant)
		current = math.clamp(math.floor(value), minimum, maximum)
		valueLabel.Text = tostring(current)
		local f = fraction(current)
		if instant then
			fill.Size = UDim2.new(f, 0, 1, 0)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
		else
			self:tween(fill, 0.09, { Size = UDim2.new(f, 0, 1, 0) })
			self:tween(knob, 0.09, { Position = UDim2.new(f, 0, 0.5, 0) })
		end
	end

	if spec.path ~= nil then
		self:bind(spec.path, fallback, function(raw, initial)
			render(tonumber(fromStore(raw)) or fallback, initial == true)
		end)
	else
		render(fallback, true)
	end

	-- The drag rectangle is captured on press and held for the whole gesture: re-reading
	-- AbsolutePosition on every event made a slider that resizes the window move the
	-- track underneath the finger, so 45 jumped to 15 and then to 40.
	-- ONE GESTURE, ONE OWNER, AND A TOUCH HAS TO EARN THE DRAG ("滑块移动端极容易误触" had
	-- three causes in a scrollable page): the press ALREADY wrote a value, so a finger
	-- that came down on the strip to flick the list jumped the number; the move handler
	-- accepted movement on any axis, so a vertical scroll wrote values down the page;
	-- and `dragging` was a bare boolean, so the second finger of a two-finger scroll
	-- drove the value and an ended event of an unexpected type left the slider armed for
	-- the NEXT gesture. The gesture is now identified by its input object, the axis is
	-- locked on the first mostly-horizontal move, and the value only moves after the
	-- finger has travelled past TOUCH_ARM. A mouse still jumps on press: that is the
	-- desktop convention and there is no scrolling to protect.
	local activeGesture = nil
	local gestureStart = nil
	local rect = nil
	local dragging = false
	local gestureChanged = false
	local function trackRect()
		local okPosition, position = pcall(function()
			return trackBar.AbsolutePosition
		end)
		local okSize, size = pcall(function()
			return trackBar.AbsoluteSize
		end)
		if not okPosition or not okSize then
			return
		end
		rect = { x = position.X, width = size.X }
		-- The track re-anchors when a slider resizes the window (uiScale, widthPct,
		-- heightPct, infoScale all do); holding the old rectangle for the whole gesture
		-- made the value chase a rectangle that had moved away, so the anchor is
		-- re-read whenever the track moved by more than a pixel.
		if gestureStart ~= nil and math.abs(position.X - gestureStart.rectX) > 1 then
			gestureStart.x = gestureStart.x + (position.X - gestureStart.rectX)
			gestureStart.rectX = position.X
		end
	end
	local function applyFromX(x)
		if rect == nil or rect.width <= 0 then
			return
		end
		local f = math.clamp((x - rect.x) / rect.width, 0, 1)
		local next = math.clamp(math.floor(minimum + (maximum - minimum) * f + 0.5), minimum, maximum)
		if next ~= current then
			gestureChanged = true
			render(next)
			-- `commitOnly` MEANS "WRITE ON RELEASE", INCLUDING THE STORE: it used to skip
			-- only `onChange`, so every pixel of a drag still wrote the store (which
			-- persists, with a save queue behind it) and re-bound the control through
			-- `Kit.bind`. A cheap gesture needs the store write on release too.
			if not spec.commitOnly then
				if spec.path ~= nil then
					self.store:set(spec.path, toStore(next))
				end
				if spec.onChange ~= nil then
					task.spawn(spec.onChange, next)
				end
			end
		end
	end

	local function sliderToast()
		if spec.silent == true or spec.label == nil then
			return
		end
		self:toast(string.format("[%s] = %d", tostring(spec.label), current), "info", 1.2)
	end

	self:track(hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		activeGesture = input
		gestureStart = nil
		gestureChanged = false
		trackRect()
		if rect == nil then
			activeGesture = nil
			return
		end
		gestureStart = {
			x = input.Position.X,
			y = input.Position.Y,
			rectX = rect.x,
			mouse = input.UserInputType == Enum.UserInputType.MouseButton1,
		}
		if gestureStart.mouse then
			-- Desktop keeps the click-to-set behaviour.
			dragging = true
			lockScroll(true)
			self:tween(knob, 0.1, { Size = UDim2.fromOffset(26, 26) })
			applyFromX(input.Position.X)
		end
	end))

	-- THE MOVE HANDLER IS ON THE GLOBAL INPUT SERVICE -- the line that makes dragging
	-- work. The hit target is an 18-pixel-tall strip, so the pointer leaves it on the
	-- first movement and a handler on the GuiObject's own InputChanged gets one event and
	-- then nothing, which is why the control could only be clicked, never dragged.
	-- Touch is deliberately strict: the finger must travel TOUCH_ARM before the slider
	-- arms, and only a mostly-horizontal move lets it steal the gesture from the page's
	-- scroll.
	self:track(UserInputService.InputChanged:Connect(function(input)
		if activeGesture == nil or input ~= activeGesture then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if gestureStart == nil then
			return
		end
		local dx = input.Position.X - gestureStart.x
		local dy = input.Position.Y - gestureStart.y
		if not dragging then
			-- Unarmed: only a decisive, mostly-horizontal travel arms the drag.
			if math.abs(dx) < TOUCH_ARM or math.abs(dx) < math.abs(dy) then
				return
			end
			dragging = true
			lockScroll(true)
			self:tween(knob, 0.1, { Size = UDim2.fromOffset(26, 26) })
		end
		trackRect()
		-- The track may have moved under the finger (see trackRect): a
		-- horizontal jump of that size is not part of the press offset, so
		-- re-anchor the gesture instead of letting the value leap.
		local shift = rect.x - gestureStart.rectX
		if math.abs(shift) > 24 then
			gestureStart.x = input.Position.X - shift
			gestureStart.rectX = rect.x
		end
		applyFromX(input.Position.X)
	end))

	local function finishGesture(input)
		local wasDragging = dragging
		activeGesture = nil
		gestureStart = nil
		dragging = false
		rect = nil
		lockScroll(false)
		self:tween(knob, 0.16, { Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Quint)
		if not wasDragging then
			return
		end
		if spec.commitOnly then
			-- The deferred write that makes `commitOnly` cheap.
			if spec.path ~= nil then
				self.store:set(spec.path, toStore(current))
			end
			if spec.onChange ~= nil then
				task.spawn(spec.onChange, current)
			end
		end
		-- ONE toast per gesture, on release: that shape makes the notification useful
		-- instead of a per-pixel flood, and a press that did not move the value says
		-- nothing ("no change" was the usual outcome of the accidental presses anyway).
		if gestureChanged then
			sliderToast()
		end
	end

	self:track(hit.InputEnded:Connect(function(input)
		if activeGesture ~= nil and input ~= activeGesture then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		finishGesture(input)
	end))

	-- THE GESTURE MUST ALWAYS END. `hit.InputEnded` is not guaranteed to arrive when
	-- the touch leaves the button (a page scroll or a notification taking focus can
	-- steal it), and an armed slider leaves the page's ScrollingFrame DISABLED -- the
	-- page would stop scrolling until the slider was pressed again. The global
	-- stream always reports the release.
	self:track(UserInputService.InputEnded:Connect(function(input)
		if activeGesture == nil or input ~= activeGesture then
			return
		end
		finishGesture(input)
	end))

	return {
		get = function()
			return current
		end,
		set = function(v)
			if spec.path ~= nil then
				self.store:set(spec.path, toStore(v))
			else
				render(v)
			end
		end,
		-- Legal range can change at runtime (the window's width limit depends on
		-- its scale), so the page can re-declare it and the slider re-renders.
		setRange = function(low, high)
			minimum = low
			maximum = high
			if current < minimum then
				current = minimum
			end
			if current > maximum then
				current = maximum
			end
			render(current)
		end,
	}
end

-- spec = { label, values, path?, default?, map?, onSelect? }
-- `map.toStore(display)` / `map.fromStore(stored)` translate between what the
-- user sees and what the store holds (display names vs ids, for instance).
function Kit.dropdown(self, parent, spec)
	local values = spec.values or {}
	local mapping = spec.map

	local row = self:row(parent, false)
	self:rowLabel(row, spec.label, nil, 110)

	local function displayOf(stored)
		if mapping ~= nil and mapping.fromStore ~= nil then
			return mapping.fromStore(stored)
		end
		return tostring(stored)
	end

	local currentDisplay = displayOf(spec.default)

	local button = self:instance("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 30),
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = tostring(currentDisplay) .. "  ▾",
		TextColor3 = self:color("TextPrimary"),
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 10,
		AutoButtonColor = false,
	}, row)
	self:corner(button, 6)
	self:stroke(button, self:color("Border"), 1, 0)

	-- A full-screen invisible button eats every click outside the panel: relying on an
	-- InputBegan check alone let clicks fall through to whatever was under the open panel.
	local backdrop = self:instance("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		ZIndex = 4990,
		AutoButtonColor = false,
	}, self.screen)

	local panel = self:instance("Frame", {
		Size = UDim2.fromOffset(220, 6),
		BackgroundColor3 = self:color("White"),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5000,
		Active = true,
		ClipsDescendants = true,
	}, self.screen)
	self:corner(panel, 8)
	self:stroke(panel, self:color("Border"), 1.4, 0)
	self:shadow(panel, 8, 0.9)

	local listFrame = self:instance("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = self:color("TextMuted"),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 5001,
	}, panel)
	self:pad(listFrame, 4, 4, 4, 4)
	self:list(listFrame, 2)

	local open = false

	local function closePanel()
		if not open then
			return
		end
		open = false
		backdrop.Visible = false
		self:tween(panel, 0.16, {
			Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, 6),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		-- The hide is deferred until the close tween has run, and it must only apply to
		-- the close it belongs to: reopening during those 0.17 s used to leave the old
		-- hide pending, so the freshly opened panel was hidden again the moment it
		-- appeared ("clicked it twice quickly and it did not open"). Re-checking `open`
		-- ties the callback to its own close.
		self:delay(0.17, function()
			if open then
				return
			end
			pcall(function()
				panel.Visible = false
				panel.BackgroundTransparency = 0
			end)
		end)
		self:tween(button, 0.16, { BackgroundColor3 = self:color("White") })
	end

	-- THE OPTION LIST IS POOLED, AND ONLY BUILT WHEN IT IS OPENED. Two pages rebuild a
	-- dropdown on a timer (the training machine list every 2 s, 160+ entries in the live
	-- dump; the kill page's player list on every UI tick) and the old `draw()` destroyed
	-- and recreated every option button each time -- hundreds of Instance.new + Destroy +
	-- UIListLayout passes per second for a list nobody was looking at. Now a `refresh`
	-- with unchanged values does not redraw at all, `draw()` reuses the buttons it already
	-- made and only hides the surplus, and the list is built lazily on open.
	local entries = {}
	local entryOption = {}
	local drawn = false
	local function sameValues(a, b)
		if #a ~= #b then
			return false
		end
		for index = 1, #a do
			if a[index] ~= b[index] then
				return false
			end
		end
		return true
	end

	local function ensureEntry(index, option)
		local entry = entries[index]
		if entry == nil then
			entry = self:instance("TextButton", {
				Size = UDim2.new(1, 0, 0, DROPDOWN_OPTION_HEIGHT),
				BackgroundColor3 = self:color("BgSoft"),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				Text = tostring(option),
				TextColor3 = self:color("TextPrimary"),
				TextSize = 13,
				LayoutOrder = index,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 5002,
				AutoButtonColor = false,
			}, listFrame)
			self:corner(entry, 5)
			self:pad(entry, 0, 0, 8, 8)
			self:track(entry.MouseEnter:Connect(function()
				self:tween(entry, 0.1, { BackgroundColor3 = self:color("BgHover") })
			end))
			self:track(entry.MouseLeave:Connect(function()
				self:tween(entry, 0.1, { BackgroundColor3 = self:color("BgSoft") })
			end))
			-- The option this button currently stands for is kept on OUR side: an
			-- Instance rejects unknown members, so a button cannot carry a custom field.
			self:track(entry.MouseButton1Click:Connect(function()
				local chosen = entryOption[index]
				if chosen == nil then
					return
				end
				currentDisplay = tostring(chosen)
				button.Text = currentDisplay .. "  ▾"
				if spec.path ~= nil then
					local stored = chosen
					if mapping ~= nil and mapping.toStore ~= nil then
						stored = mapping.toStore(chosen)
					end
					self.store:set(spec.path, stored)
				end
				if spec.onSelect ~= nil then
					task.spawn(spec.onSelect, chosen)
				end
				if spec.silent ~= true then
					self:toast(string.format("[%s] = %s", tostring(spec.label), tostring(chosen)), "info", 1.4)
				end
				closePanel()
			end))
			entries[index] = entry
		end
		entryOption[index] = option
		entry.Text = tostring(option)
		entry.LayoutOrder = index
		entry.Visible = true
		return entry
	end

	local function draw()
		for index, option in ipairs(values) do
			ensureEntry(index, option)
		end
		-- Surplus buttons are hidden, not destroyed: a shrinking list (machines
		-- streaming out, players leaving) would otherwise churn them.
		for index = #values + 1, #entries do
			entries[index].Visible = false
		end
		drawn = true
	end

	local function place()
		local buttonPosition = button.AbsolutePosition
		local buttonSize = button.AbsoluteSize
		local screenPosition = self.screen.AbsolutePosition
		local screenSize = self.screen.AbsoluteSize
		local width = math.max(150, buttonSize.X)
		local height = math.min(DROPDOWN_MAX_HEIGHT, math.max(38, #values * 28 + 8))
		local x = (buttonPosition.X - screenPosition.X) + buttonSize.X - width
		x = math.clamp(x, 4, math.max(4, screenSize.X - 4 - width))
		local below = (buttonPosition.Y - screenPosition.Y) + buttonSize.Y + 4
		local y = below
		if below + height > screenSize.Y - 6 then
			local above = (buttonPosition.Y - screenPosition.Y) - height - 4
			y = if above >= 6 then above else math.max(6, screenSize.Y - 6 - height)
		end
		panel.Position = UDim2.fromOffset(x, y)
		return width, height
	end

	local function openPanel()
		draw()
		local width, height = place()
		open = true
		backdrop.Visible = true
		panel.Visible = true
		panel.BackgroundTransparency = 0.3
		panel.Size = UDim2.fromOffset(width, 6)
		self:tween(panel, 0.28, { Size = UDim2.fromOffset(width, height), BackgroundTransparency = 0 }, Enum.EasingStyle.Back)
		self:tween(button, 0.16, { BackgroundColor3 = self:color("BgHover") })
	end

	self:track(button.MouseButton1Click:Connect(function()
		if open then
			closePanel()
		else
			openPanel()
		end
	end))
	self:track(backdrop.MouseButton1Click:Connect(closePanel))

	-- SCROLLING THE LIST MUST NOT CLOSE IT. The panel is parented to the ScreenGui to
	-- escape the page's clipping, so something has to dismiss it when the page underneath
	-- scrolls -- otherwise a floating panel stays pinned over content that scrolled away
	-- from its trigger. But closing on ANY wheel event reaching this frame collapsed the
	-- list mid-scroll, and `AutomaticCanvasSize` makes `CanvasSize` unreliable, so the
	-- content height is computed instead: dismiss only when there is nothing to scroll.
	-- Touch is a drag ON the list, so it never dismisses.
	self:track(listFrame.InputChanged:Connect(function(input)
		if not open then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local content = (#values * (DROPDOWN_OPTION_HEIGHT + 2)) + 8
		if content <= listFrame.AbsoluteSize.Y + 1 then
			closePanel()
		end
	end))

	if spec.path ~= nil then
		self:bind(spec.path, spec.default, function(raw)
			currentDisplay = displayOf(raw)
			button.Text = tostring(currentDisplay) .. "  ▾"
		end)
	end

	return {
		get = function()
			return currentDisplay
		end,
		refresh = function(nextValues, nextDefault)
			local changed = not sameValues(values, nextValues)
			values = nextValues
			if nextDefault ~= nil then
				currentDisplay = tostring(nextDefault)
				button.Text = currentDisplay .. "  ▾"
			end
			-- Only rebuild when the list actually moved, and only if it has been
			-- built at least once (otherwise it will be built on open).
			if changed and drawn then
				draw()
			end
		end,
		-- Show a value without re-declaring the option list. `refresh(values, nil)`
		-- deliberately PRESERVES the selection, whereas `set` is the explicit "make the
		-- button say this" call -- conflating the two is how a refresh silently reset a
		-- user's choice.
		set = function(display)
			currentDisplay = tostring(display)
			button.Text = currentDisplay .. "  ▾"
		end,
	}
end

-- spec = { label, onClick, role?, width? }
function Kit.button(self, parent, spec)
	local button = self:instance("TextButton", {
		Size = UDim2.new(spec.width or 1, 0, 0, 36),
		BackgroundColor3 = self:color(spec.role or "White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = spec.label,
		TextColor3 = if spec.role == "Green" or spec.role == "Red" then self:color("White") else self:color("TextPrimary"),
		TextSize = 14,
		AutoButtonColor = false,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
	self:corner(button, 6)
	self:stroke(button, self:color("Border"), 1, 0)
	self:animate(button, self:color(spec.role or "White"))

	self:track(button.MouseButton1Click:Connect(function()
		if spec.onClick == nil then
			return
		end
		task.spawn(function()
			local ok, err = pcall(spec.onClick)
			if not ok then
				warn("[MKUltraHUB][ui] " .. tostring(spec.label) .. ": " .. tostring(err))
			end
		end)
	end))
	return button
end

-- Two buttons side by side.
function Kit.dualButtons(self, parent, leftSpec, rightSpec)
	local row = self:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = self:nextOrder(parent),
	}, parent)
	self:list(row, 6, true)

	local function make(spec)
		local button = self:instance("TextButton", {
			Size = UDim2.new(0.5, -3, 1, 0),
			BackgroundColor3 = self:color(spec.role or "White"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = spec.label,
			TextColor3 = if spec.role == "Green" or spec.role == "Red" then self:color("White") else self:color("TextPrimary"),
			TextSize = 14,
		}, row)
		self:corner(button, 6)
		self:stroke(button, self:color("Border"), 1, 0)
		self:animate(button, self:color(spec.role or "White"))
		self:track(button.MouseButton1Click:Connect(function()
			if spec.onClick == nil then
				return
			end
			task.spawn(function()
				local ok, err = pcall(spec.onClick)
				if not ok then
					warn("[MKUltraHUB][ui] " .. tostring(spec.label) .. ": " .. tostring(err))
				end
			end)
		end))
		return button
	end

	return make(leftSpec), make(rightSpec)
end

return Kit
end

__modules["core/ShellState"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	ShellState -- the window's visual state as a pure function.

	The main window has three shapes (normal, minimised title bar, floating pill)
	and each decides four things (size, corner radius, which layers are visible,
	whether the pill overlay is up). Computing that in ONE function over (pill,
	minimized, width, height) makes every combination enumerable and testable --
	the old split across applySize/setMinimized/setPill disagreed with itself:
	setMinimized had NO restore branch, the collapsed bar was sized to the SCREEN
	width instead of the width of the window it collapsed from, and applySize
	recomputed the same three cases with its own copy of the constants.

	Per-shape visibility, and why:

	    topBar     the drag handle and the window buttons; up in normal and
	               minimised, down in pill (the pill IS the handle)
	    nav        the page list; only meaningful when there is a content area
	    content    the page area; down whenever the window is a bar or a pill
	    topFill    squares off the bottom of the top bar so it does not show a
	               rounded seam against the content; there is content below it
	               only in normal mode
	    status     the status line; kept while minimised (the only feedback left),
	               hidden in pill because the pill has its own live line
	    pillLayer  the pill overlay itself
]]

local ShellState = {}

export type Mode = "window" | "minimized" | "pill"

export type Layout = {
	width: number,
	height: number,
	corner: number,
}

export type Layers = {
	topBar: boolean,
	nav: boolean,
	content: boolean,
	topFill: boolean,
	status: boolean,
	pillLayer: boolean,
}

export type State = {
	mode: Mode,
	layout: Layout,
	layers: Layers,
}

ShellState.PILL_WIDTH = 196
ShellState.PILL_HEIGHT = 38
ShellState.MINIMIZED_HEIGHT = 50
ShellState.WINDOW_CORNER = 12
ShellState.PILL_CORNER = 20

ShellState.MODES = { "window", "minimized", "pill" }

-- The pill wins over the minimised flag: they are two ways of collapsing the
-- same window and the pill is the smaller of the two, so it is the one that
-- must be shown if both are somehow set.
function ShellState.mode(pill: boolean, minimized: boolean): Mode
	if pill then
		return "pill"
	end
	if minimized then
		return "minimized"
	end
	return "window"
end

function ShellState.compute(pill: boolean, minimized: boolean, windowWidth: number, windowHeight: number): State
	local mode = ShellState.mode(pill, minimized)

	if mode == "pill" then
		return {
			mode = mode,
			layout = {
				width = ShellState.PILL_WIDTH,
				height = ShellState.PILL_HEIGHT,
				corner = ShellState.PILL_CORNER,
			},
			layers = {
				topBar = false,
				nav = false,
				content = false,
				topFill = false,
				status = false,
				pillLayer = true,
			},
		}
	end

	if mode == "minimized" then
		return {
			mode = mode,
			layout = {
				-- The WINDOW's width, not the screen's: a collapsed window has to
				-- still look like the window it collapsed from.
				width = windowWidth,
				height = ShellState.MINIMIZED_HEIGHT,
				corner = ShellState.WINDOW_CORNER,
			},
			layers = {
				topBar = true,
				nav = false,
				content = false,
				topFill = false,
				status = true,
				pillLayer = false,
			},
		}
	end

	return {
		mode = mode,
		layout = {
			width = windowWidth,
			height = windowHeight,
			corner = ShellState.WINDOW_CORNER,
		},
		layers = {
			topBar = true,
			nav = true,
			content = true,
			topFill = true,
			status = true,
			pillLayer = false,
		},
	}
end

return ShellState
end

__modules["ui/Shell"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- Shell -- the window: top bar, navigation, pages, dragging, pill mode, theme.
-- Everything the shell owns is driven by the Store (uiState.theme / minimized /
-- widthPct / heightPct / uiScale / savedMain), so a change made anywhere -- a
-- settings slider, a keybind, the config file -- moves the window; there is no
-- second copy of "is it minimised" to fall out of step.
-- Unlike V1007 the size range is computed from real screen coverage (100% used to
-- cover 160% of a 4K screen) and dragging uses the scale the shell sets, not one
-- probed by moving the window eight pixels.

local UserInputService = game:GetService("UserInputService")
-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).

local Theme = require("ui/Theme")
local ShellState = require("core/ShellState")
local Format = require("core/Format")
local Attributes = require("core/Attributes")

local Shell = {}
Shell.__index = Shell

-- Human-readable names for the scheduler's task ids, used by the status bar and
-- the pill: without them the status line can only show "空闲中", because a raw id
-- like "kingKill" is not something to put in front of a user.
Shell.TASK_LABELS = {
	["boss"] = "打Boss",
	["chest"] = "开宝箱",
	["kingKill"] = "杀肌肉之王",
	["kill"] = "全图杀戮",
	["dual"] = "双工具",
	["rebirth"] = "重生",
	["packrebirth"] = "换包重生",
	["machine"] = "器械",
	["teleport"] = "前往肌肉之王",
	["teleportLoop"] = "循环传送",
	["train"] = "锻炼",
	["tool"] = "工具切换",
	["egg"] = "吃蛋",
	["petbuy"] = "买宠物",
	["wheel"] = "轮盘",
	["petSwap"] = "换宠",
	["rejoin"] = "重进",
	["timedRejoin"] = "定时重进",
	["emergency"] = "紧急重进",
	["antilag"] = "防卡顿",
	-- `Shell.bindStatus` walks the scheduler's ACTIVE list, so any running task
	-- without an entry here was silently dropped from the status bar and the pill
	-- ("空闲中" while five tasks were in fact running). These are exactly the ids
	-- the scheduler registers.
	["bossPunch"] = "打Boss出拳",
	["crystal"] = "开水晶",
	["punchGuard"] = "保持拳套",
	["damageHold"] = "伤害优先",
	["trainDepth"] = "锻炼深度",
	["perfGuard"] = "防卡顿",
	["afk"] = "反挂机",
	["size"] = "体型",
	["metrics"] = "指标采样",
}

local MIN_PCT = 30
local MAX_COVERAGE = 90
local TOP_BAR_HEIGHT = 50
local NAV_WIDTH = 120
local TOP_BUTTON_ZONE = 130

-- The three shapes' sizes and layers live in core/ShellState, so the pure state
-- table is the single source of truth for them; re-declaring the numbers here is
-- how applySize / setMinimized / setPill came to disagree.
-- The window's internal scale follows the display, so the same percentage looks
-- the same on a 1080p and a 1440p screen.
function Shell.resFactor(): number
	local camera = Workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1920, 1080)
	return math.clamp(viewport.Y / 1080, 0.85, 1.6)
end

function Shell.new(context)
	local self = setmetatable({
		store = context.store,
		kit = context.kit,
		notify = context.notify or function() end,
		version = context.version or "V1008",
		onClose = context.onClose,
		timers = context.timers,
		-- Subsystems a hotkey may need to reach (motion, teleport); avoids a
		-- getter per action.
		services = context.services or {},
		-- Read for the status bar's "what is running" list.
		scheduler = context.scheduler,
		uiTicks = {},
		pages = {},
		built = false,
		activeTab = nil,
		themeName = context.store:get("uiState.theme") or "light",
		connections = {},
		-- Incremented by every morph: a morph's delayed steps abort as soon as a
		-- newer one starts, so a fast minimise -> restore -> minimise cannot leave
		-- two animation chains fighting over the same size, corner and visibility.
		morphSeq = 0,
		-- os.clock() when the in-flight morph started, or 0 when none is in
		-- flight. Only the stuck-cover watchdog reads it.
		morphAt = 0,
	}, Shell)
	return self
end

function Shell.registerPage(self, spec)
	table.insert(self.pages, spec)
	return spec
end

-- Register a slow refresh for read-outs that are not bound to a store key (a retry
-- counter, a scan result). They run on a timer rather than per frame, so a page never
-- has to open its own loop.
function Shell.addUiTick(self, fn)
	table.insert(self.uiTicks, fn)
	return fn
end

-- Pages report through the shell, so they never need a reference to the toast stack
-- (and keep working before it exists). `duration` is optional; see Toast.show.
function Shell.toast(self, text, kind, duration)
	if self.onToast ~= nil then
		pcall(self.onToast, text, kind, duration)
	end
end

function Shell.screenGui(self)
	return self.screen
end

-- Through the runtime's Timers when available, else a raw delay. A raw
-- task.delay outlives Runtime.destroy() and then runs its callback against a
-- torn-down GUI; routing it through the Timers makes the teardown complete.
-- See Kit.delay for the same reasoning.
function Shell.delay(self, seconds, fn)
	local timers = self.timers
	if timers ~= nil then
		return timers:after(os.clock(), seconds, fn)
	end
	-- Deliberately the raw scheduler here: this IS the fallback.
	task.delay(seconds, fn)
	return nil
end

-- geometry -------------------------------------------------------------------

-- The legal range for widthPct / heightPct: coverage = pct/100 * uiScale *
-- resolutionFactor, and it must not exceed 90%. V1007 computed it from uiScale
-- alone, which silently under-counted on any display above 1080p.
function Shell.pctRange(self): (number, number)
	local factor = Shell.resFactor()
	local scale = (self.store:get("uiState.uiScale") or 100) / 100
	local maxPct = math.clamp(math.floor(MAX_COVERAGE / math.max(0.1, scale * factor)), MIN_PCT, 100)
	return MIN_PCT, maxPct
end

function Shell.windowSize(self): (number, number)
	local camera = Workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
	local factor = Shell.resFactor()
	local minimum, maximum = Shell.pctRange(self)
	local widthPct = math.clamp(tonumber(self.store:get("uiState.widthPct")) or 45, minimum, maximum)
	local heightPct = math.clamp(tonumber(self.store:get("uiState.heightPct")) or 52, minimum, maximum)
	local width = math.max(240, math.floor(viewport.X * widthPct / 100 / factor))
	local height = math.max(180, math.floor(viewport.Y * heightPct / 100 / factor))
	return width, height
end

-- The current visual state: the window size from the store/viewport, then the
-- pure decision from core/ShellState.
function Shell.visualState(self)
	local width, height = Shell.windowSize(self)
	return ShellState.compute(self.pill == true, self.minimized == true, width, height)
end

local function applyLayers(self, layers)
	self.topBar.Visible = layers.topBar
	self.nav.Visible = layers.nav
	self.content.Visible = layers.content
	self.topFill.Visible = layers.topFill
	self.status.Visible = layers.status
	self.pillLayer.Visible = layers.pillLayer
end

-- The one place that writes a computed state onto the widgets.
function Shell.applyVisualState(self, state)
	self.main.Size = UDim2.fromOffset(state.layout.width, state.layout.height)
	self.mainCorner.CornerRadius = UDim.new(0, state.layout.corner)
	applyLayers(self, state.layers)

	-- The InfoWindow lives on the SAME ScreenGui but is not a child of the main
	-- frame, so collapsing the window left the info panel sitting on screen (the
	-- reported "minimised and it is still showing"). Wired as a callback because
	-- the Shell is built before the panel exists and must not depend on a panel
	-- it does not own.
	if self.onVisualState ~= nil then
		pcall(self.onVisualState, state)
	end
end

function Shell.applySize(self, instant)
	-- A size change is ANIMATED unless the caller says otherwise: `applySize` runs
	-- at build (nothing to animate from) and on every width/height/scale edit (the
	-- user drags a slider and expects to SEE the window follow). Writing `Size`
	-- directly in both cases is why resizing looked like a jump cut next to morphs
	-- that tween. The `instant` path is used by build and by anything that must
	-- land before layout is read (the reset button, which then measures the result).
	local state = Shell.visualState(self)
	local targetScale = ((self.store:get("uiState.uiScale") or 100) / 100) * Shell.resFactor()
	if instant then
		Shell.applyVisualState(self, state)
		self.mainScale.Scale = targetScale
	else
		-- A size edit CANCELS a shape change that is still in flight: `morph`
		-- re-applies its end state when it lands with a hard `Size` write, so a
		-- width/scale edit during those ~0.25 s would be overwritten and the window
		-- would jump. A new sequence number stands the OLDER chain down; both
		-- compute from `Shell.visualState`, so the layers and the size agree.
		self.morphSeq += 1
		self.kit:tween(self.main, 0.2, {
			Size = UDim2.fromOffset(state.layout.width, state.layout.height),
		}, Enum.EasingStyle.Quint)
		self.kit:tween(self.mainCorner, 0.2, { CornerRadius = UDim.new(0, state.layout.corner) },
			Enum.EasingStyle.Quint)
		-- The internal scale is animated too: "整体缩放" is the one slider whose
		-- whole effect IS a size change, and snapping it made the control feel
		-- different from every other one on the page.
		self.kit:tween(self.mainScale, 0.2, { Scale = targetScale }, Enum.EasingStyle.Quint)
		-- The layers do not change here: a width/height edit while minimised or
		-- in the pill keeps that shape (see ShellState.compute).
		applyLayers(self, state.layers)
		if self.onVisualState ~= nil then
			pcall(self.onVisualState, state)
		end
	end

	if self.syncSliders ~= nil then
		self.syncSliders()
	end

	-- Every geometry pass ENDS here, with the position re-derived from the store.
	-- Deferred until the new size has been laid out: `AbsolutePosition` /
	-- `AbsoluteSize` are only meaningful after the writes above have propagated, and
	-- on the `instant` path the entrance animation (0.32 s of UIScale) must land
	-- first, since the clamp needs the FINAL rendered size. `reapplyPosition`
	-- replaces a bare `clampOnScreen` call because a nudge from wherever the window
	-- happens to be cannot repair a position the store never agreed to; it also
	-- writes the clamped value back, so what is on screen is what is restored next.
	self:delay(if instant then 0.35 else 0.26, function()
		if self.destroyed then
			return
		end
		Shell.reapplyPosition(self, false)
		-- The info panel is placed relative to this window's rect, so it has to be
		-- re-placed once that rect has settled (the shell does not own the panel,
		-- hence the callback).
		if self.onGeometrySettled ~= nil then
			pcall(self.onGeometrySettled)
		end
	end)
end

-- Apply `uiState.fontScale` to every text object on the screen. The stored value
-- is a MULTIPLIER (0.8 - 1.5): each object's original TextSize is remembered in an
-- attribute the first time it is touched, so the result is always `base * scale` --
-- scaling the CURRENT size would compound on every slider move (1.5 then 1.5 ->
-- 2.25x). pcall because most GUI objects have no TextSize at all.
function Shell.applyFontScale(self)
	local screen = self.screen
	if screen == nil then
		return
	end
	local scale = tonumber(self.store:get("uiState.fontScale")) or 1

	for _, object in ipairs(screen:GetDescendants()) do
		local ok, current = pcall(function()
			return object.TextSize
		end)
		if ok and type(current) == "number" and current > 0 then
			local base = object:GetAttribute(Attributes.FONT_BASE)
			if type(base) ~= "number" then
				base = current
				pcall(function()
					object:SetAttribute(Attributes.FONT_BASE, base)
				end)
			end
			pcall(function()
				object.TextSize = math.max(1, math.floor(base * scale + 0.5))
			end)
		end
	end
end

-- The viewport, but only when it can be trusted: both the clamp and the panel
-- placement are computed against this, and a viewport reported while the client was
-- still loading is exactly the input that must not be acted on -- the window would
-- be pulled somewhere the user never put it while the store kept the old coordinate
-- ("每次重进后窗口位置异常位移"). A camera with no usable size answers nil rather
-- than a default, so a caller cannot clamp against 0x0 and shove the window into the
-- corner.
function Shell.viewport(self)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local viewport = camera.ViewportSize
	if viewport == nil or type(viewport.X) ~= "number" or type(viewport.Y) ~= "number" then
		return nil
	end
	if viewport.X < 320 or viewport.Y < 240 then
		return nil
	end
	return viewport
end

-- Where the STORE says the window's centre is (the project rule: state lives in the
-- Store). The live `main.Position` is not it -- the entrance animation, a morph and
-- a clamp all move the window without writing the store, and a session that trusted
-- the live value came back in a different place every time.
function Shell.positionFromStore(self): UDim2
	local saved = self.store:get("uiState.savedMain")
	if type(saved) ~= "table" then
		return UDim2.new(0.5, 0, 0.5, 0)
	end
	return UDim2.new(saved.xs or 0.5, saved.xo or 0, saved.ys or 0.5, saved.yo or 0)
end

-- Keep a centre inside `[size/2, extent - size/2]`. When the window is larger
-- than the screen there is no such interval, so it is centred instead of being
-- pushed to an edge it does not fit into either.
local function clampCentre(centre: number, size: number, extent: number): number
	local half = size / 2
	if size >= extent then
		return extent / 2
	end
	if centre < half then
		return half
	end
	if centre > extent - half then
		return extent - half
	end
	return centre
end

-- Move the window there, tweened unless the caller says otherwise. Deliberately NOT
-- a store write: `reapplyPosition` owns that decision.
function Shell.setPosition(self, target: UDim2, animate: boolean?)
	if self.main == nil or self.destroyed then
		return
	end
	if animate ~= true or self.main.Position == target then
		self.main.Position = target
		return
	end
	self.kit:tween(self.main, 0.2, { Position = target }, Enum.EasingStyle.Quint)
end

-- PUT THE WINDOW WHERE THE STORE SAYS IT GOES, clamped into a usable viewport.
-- Deliberately NOT `clampOnScreen`: that nudges from wherever the window currently
-- IS, so a position the store never agreed to can survive a whole session and the
-- next session restores the store value and lands somewhere else. This re-derives
-- the position, which is what makes it reproducible across a rejoin; when the clamp
-- DOES move it, the clamped value is written BACK, so what is on screen is what will
-- be restored. Returns true when it had to move the window.
function Shell.reapplyPosition(self, animate)
	if self.main == nil or self.destroyed then
		return false
	end

	-- The pill is a different shape with its own remembered position; deriving
	-- from `savedMain` here would jump it to where the WINDOW belongs.
	if self.pill == true then
		return Shell.clampOnScreen(self)
	end

	local target = Shell.positionFromStore(self)
	local viewport = Shell.viewport(self)
	if viewport == nil then
		-- Nothing trustworthy to clamp against: apply the stored value verbatim
		-- rather than guessing from a bad viewport.
		Shell.setPosition(self, target, false)
		return false
	end

	-- The RENDERED size, which includes the UIScale (the window's Size is stored
	-- in unscaled units).
	local size = self.main.AbsoluteSize
	local width = if size ~= nil and type(size.X) == "number" then size.X else 0
	local height = if size ~= nil and type(size.Y) == "number" then size.Y else 0
	if width <= 0 or height <= 0 then
		local state = Shell.visualState(self)
		local scale = if self.mainScale ~= nil then self.mainScale.Scale else 1
		width = state.layout.width * scale
		height = state.layout.height * scale
	end

	local centreX = target.X.Scale * viewport.X + target.X.Offset
	local centreY = target.Y.Scale * viewport.Y + target.Y.Offset
	local clampedX = clampCentre(centreX, width, viewport.X)
	local clampedY = clampCentre(centreY, height, viewport.Y)
	local moved = math.abs(clampedX - centreX) > 1 or math.abs(clampedY - centreY) > 1

	if moved then
		-- Persist the clamped coordinate and let the `uiState.savedMain`
		-- subscriber move the window: ONE place writes the position, so the two
		-- cannot disagree. (Written as absolute offsets -- the same shape the info
		-- panel uses -- which is exactly "this spot on this screen".)
		self.store:set("uiState.savedMain", {
			xs = 0,
			xo = math.floor(clampedX + 0.5),
			ys = 0,
			yo = math.floor(clampedY + 0.5),
		})
		return true
	end

	Shell.setPosition(self, target, animate == true)
	return false
end

-- The main window's rect as GEOMETRY says it will be, not as the screen currently
-- shows it. `PanelPlacement` used to be handed `main.AbsolutePosition/AbsoluteSize`;
-- read mid-tween (entrance animation, a clamp, a morph) those describe a rectangle
-- the window is only passing through, so the SAME saved panel position resolved to a
-- different side from one session to the next.
function Shell.mainRect(self)
	if self.main == nil or self.pill == true then
		return nil
	end
	local viewport = Shell.viewport(self)
	if viewport == nil then
		return nil
	end
	local state = Shell.visualState(self)
	local scale = if self.mainScale ~= nil then self.mainScale.Scale else 1
	local width = state.layout.width * scale
	local height = state.layout.height * scale
	local target = Shell.positionFromStore(self)
	local centreX = target.X.Scale * viewport.X + target.X.Offset
	local centreY = target.Y.Scale * viewport.Y + target.Y.Offset
	return {
		x = centreX - width / 2,
		y = centreY - height / 2,
		w = width,
		h = height,
	}
end

-- Keep the window on screen after a drag, or after a shape change. Returns true
-- when it actually moved the window (i.e. a tween is in flight), so a caller that
-- persists the position can wait for the move to land instead of saving an
-- intermediate coordinate. This is the "nudge from where it is" half, right for a
-- drag (the cursor decided where it is) and for a morph; the AUTHORITATIVE position
-- pass is `reapplyPosition`.
function Shell.clampOnScreen(self)
	local viewport = Shell.viewport(self)
	if viewport == nil then
		return false
	end
	local position = self.main.AbsolutePosition
	local size = self.main.AbsoluteSize
	local dx, dy = 0, 0
	if position.X < 0 then
		dx = -position.X
	end
	if position.Y < 0 then
		dy = -position.Y
	end
	if position.X + size.X > viewport.X then
		dx = viewport.X - (position.X + size.X)
	end
	if position.Y + size.Y > viewport.Y then
		dy = viewport.Y - (position.Y + size.Y)
	end
	if math.abs(dx) < 2 and math.abs(dy) < 2 then
		return false
	end
	local factor = self.mainScale.Scale
	local stored = self.main.Position
	self.kit:tween(self.main, 0.24, {
		Position = UDim2.new(stored.X.Scale, stored.X.Offset + dx / factor, stored.Y.Scale, stored.Y.Offset + dy / factor),
	}, Enum.EasingStyle.Quint)
	return true
end

-- build

function Shell.build(self)
	if self.built then
		return self.screen
	end
	self.built = true

	local kit = self.kit
	self.roles = Theme.roles(self.themeName)
	kit.roles = self.roles

	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = kit:instance("ScreenGui", {
		Name = "MKUltraHUB",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 99999,
		IgnoreGuiInset = true,
	}, playerGui)
	self.screen = screen
	kit.screen = screen

	local savedMain = self.store:get("uiState.savedMain")
	local startPosition = if type(savedMain) == "table"
		then UDim2.new(savedMain.xs or 0.5, savedMain.xo or 0, savedMain.ys or 0.5, savedMain.yo or 0)
		else UDim2.new(0.5, 0, 0.5, 0)

	local main = kit:instance("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = startPosition,
		Size = UDim2.fromOffset(640, 480),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
	}, screen)
	self.main = main
	self.mainCorner = kit:corner(main, 12)
	kit:stroke(main, kit:color("Border"), 1.2, 0)
	kit:shadow(main, 14, 0.88)

	local mainScale = Instance.new("UIScale")
	mainScale.Scale = 1
	mainScale.Parent = main
	self.mainScale = mainScale

	local topBar = kit:instance("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, TOP_BAR_HEIGHT),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 5,
	}, main)
	kit:corner(topBar, 12)
	self.topBar = topBar

	-- Squares off the bottom edge of the bar so the rounded corners do not show a
	-- seam. Hidden while minimised, otherwise it covers the window's own corner.
	local topFill = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -10),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, topBar)
	self.topFill = topFill

	local title = kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(0, 190, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = "MKUltraHUB",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 7,
	}, topBar)
	self.title = title

	kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(190, 0),
		Size = UDim2.new(0, 90, 1, 0),
		Font = Enum.Font.Gotham,
		Text = self.version or "V1008",
		TextColor3 = kit:color("TextMuted"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 7,
	}, topBar)

	local function topButton(text, offset, role, textRole)
		local button = kit:instance("TextButton", {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, offset, 0.5, -14),
			BackgroundColor3 = kit:color(role or "White"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = kit:color(textRole or "TextPrimary"),
			TextSize = 15,
			ZIndex = 7,
		}, topBar)
		kit:corner(button, 6)
		kit:stroke(button, kit:color("Border"), 1, 0)
		kit:animate(button, kit:color(role or "White"))
		return button
	end

	local minimizeButton = topButton("—", -110)
	local pillButton = topButton("◯", -76)
	local closeButton = topButton("✕", -42, "Red", "White")

	local nav = kit:instance("ScrollingFrame", {
		Name = "Nav",
		Size = UDim2.new(0, NAV_WIDTH, 1, -TOP_BAR_HEIGHT),
		Position = UDim2.fromOffset(0, TOP_BAR_HEIGHT),
		BackgroundColor3 = kit:color("White"),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = kit:color("TextMuted"),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
	}, main)
	kit:corner(nav, 12)
	self.nav = nav

	local indicator = kit:instance("Frame", {
		Size = UDim2.fromOffset(3, 24),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = kit:color("Accent"),
		BorderSizePixel = 0,
		ZIndex = 5,
	}, nav)
	kit:corner(indicator, 1.5)
	self.indicator = indicator

	local content = kit:instance("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -NAV_WIDTH, 1, -TOP_BAR_HEIGHT),
		Position = UDim2.fromOffset(NAV_WIDTH, TOP_BAR_HEIGHT),
		BackgroundColor3 = kit:color("Bg"),
		BorderSizePixel = 0,
	}, main)
	kit:corner(content, 12)
	self.content = content

	-- A cover used during shape changes: resizing and toggling which layer is
	-- visible happen in the same tick and read as a hard cut; with it, every switch
	-- happens while the window is hidden.
	local cover = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = kit:color("White"),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 15,
	}, main)
	kit:corner(cover, 12)
	self.cover = cover

	local pill = kit:instance("Frame", {
		Name = "Pill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Active = true,
	}, main)
	self.pillLayer = pill

	local bars = {}
	for index = 1, 3 do
		local bar = kit:instance("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(20, 13 + (index - 1) * 6),
			Size = UDim2.fromOffset(15, 2),
			BackgroundColor3 = kit:color("TextPrimary"),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
		}, pill)
		kit:corner(bar, 1)
		table.insert(bars, bar)
	end
	self.pillBars = bars

	local pillTitle = kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(60, 3),
		Size = UDim2.fromOffset(132, 16),
		Font = Enum.Font.GothamBold,
		Text = "MKUltraHUB",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, pill)
	self.pillTitle = pillTitle

	local pillLive = kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(60, 19),
		Size = UDim2.fromOffset(132, 15),
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = kit:color("TextMuted"),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, pill)
	self.pillLive = pillLive

	-- The pill's status dot: green while tasks run, amber while paused. Colour is
	-- the only way the collapsed form can be read at a glance, and the dot is
	-- driven from the same `bindStatus` tick that writes the text.
	local pillDot = kit:instance("Frame", {
		Name = "PillDot",
		Position = UDim2.fromOffset(48, 17),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = kit:color("Green"),
		BorderSizePixel = 0,
	}, pill)
	kit:corner(pillDot, 4)
	self.pillDot = pillDot

	-- Status line along the bottom of the screen.
	local status = kit:instance("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -16),
		Size = UDim2.fromOffset(560, 26),
		BackgroundColor3 = kit:color("White"),
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		Text = "空闲中",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 1999,
	}, screen)
	kit:corner(status, 6)
	kit:pad(status, 0, 0, 8, 8)
	self.status = status

	-- ORDER MATTERS, and this is not cosmetic. `bindStore` subscribes the SHELL to
	-- `uiState.theme` and the theme page subscribes to the same key from inside
	-- `buildPages`; subscribers run in registration order, so building the pages
	-- FIRST let the shell's `Theme.apply` overwrite the page's own render -- one way
	-- "选择主题后仍然残存绿色" appeared. Subscribing the shell first makes the page
	-- render the last word on its own buttons.
	Shell.bindStore(self)
	Shell.buildNavigation(self)
	Shell.buildPages(self)
	Shell.bindDrag(self, topBar)
	Shell.bindInput(self)
	Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	Shell.bindHotkeys(self)
	Shell.buildResetButton(self, screen)
	Shell.bindStatus(self)

	-- Instant: at build there is no previous size to animate from.
	Shell.applySize(self, true)
	if #self.pages > 0 then
		-- Select the first page unconditionally: the minimised state hides the
		-- layers, it does not change which tab is selected.
		Shell.switchTab(self, self.pages[1].id)
	end

	if self.store:get("uiState.minimized") == true then
		Shell.setMinimized(self, true, true)
	end

	-- THE WINDOW'S ENTRANCE: "只要任何 UI 大小发生变化，或者窗口出现消失等，都必须要有
	-- 动画". A short Back-eased scale-up from 92% reads as "it opened" without moving
	-- the layout, because the transform is the UIScale and nothing reflows.
	Shell.playEntrance(self)

	if self.timers ~= nil and #self.uiTicks > 0 then
		self.timers:every(os.clock(), 0.5, function()
			for _, tick in ipairs(self.uiTicks) do
				pcall(tick)
			end
		end)
	end

	return screen
end

-- Scale the window up from 92% on load. See the call site for why.
function Shell.playEntrance(self)
	if self.mainScale == nil then
		return
	end
	local target = self.mainScale.Scale
	if target <= 0.01 then
		return
	end
	self.mainScale.Scale = target * 0.92
	self.kit:tween(self.mainScale, 0.32, { Scale = target }, Enum.EasingStyle.Back)
end

-- Close the window with a motion, then hand off to `onClose`: calling `onClose`
-- directly destroyed the ScreenGui between one frame and the next -- a hard cut
-- with no exit at all.
function Shell.closeAnimated(self)
	if self.closing then
		return
	end
	self.closing = true
	local target = self.mainScale.Scale
	self.kit:tween(self.mainScale, 0.22, { Scale = target * 0.88 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if self.cover ~= nil then
		self.cover.BackgroundColor3 = self.kit:color("Bg")
		self.cover.Visible = true
		self.cover.BackgroundTransparency = 1
		self.kit:tween(self.cover, 0.22, { BackgroundTransparency = 0 })
	end
	self:delay(0.24, function()
		if self.onClose ~= nil then
			task.spawn(self.onClose)
		end
	end)
end

function Shell.buildNavigation(self)
	local kit = self.kit
	self.navButtons = {}
	for index, page in ipairs(self.pages) do
		local button = kit:instance("TextButton", {
			Name = "Nav_" .. page.id,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, (index - 1) * 40),
			BackgroundColor3 = kit:color("White"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = page.label,
			TextColor3 = kit:color("TextSecond"),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, self.nav)
		self.navButtons[index] = button
		self.nav.CanvasSize = UDim2.new(0, 0, 0, index * 40)

		kit:track(button.MouseEnter:Connect(function()
			kit:tween(button, 0.12, {
				BackgroundColor3 = kit:color("BgHover"),
				TextColor3 = kit:color("TextPrimary"),
			})
		end))
		kit:track(button.MouseLeave:Connect(function()
			local active = self.activeTab == page.id
			kit:tween(button, 0.12, {
				BackgroundColor3 = if active then kit:color("BgSoft") else kit:color("White"),
				TextColor3 = if active then kit:color("TextPrimary") else kit:color("TextSecond"),
			})
		end))
		kit:track(button.MouseButton1Click:Connect(function()
			Shell.switchTab(self, page.id)
		end))
	end
end

function Shell.buildPages(self)
	local kit = self.kit
	self.pageFrames = {}
	for _, page in ipairs(self.pages) do
		local frame = kit:instance("ScrollingFrame", {
			Name = "Page_" .. page.id,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = kit:color("TextMuted"),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			ClipsDescendants = true,
		}, self.content)
		kit:pad(frame, 14, 14, 14, 14)
		kit:list(frame, 10)
		self.pageFrames[page.id] = frame
		if page.build ~= nil then
			local ok, err = pcall(page.build, kit, frame, self)
			if not ok then
				warn(string.format("[MKUltraHUB][ui] page %s failed to build: %s", page.id, tostring(err)))
			end
		end
	end
end

-- Stagger the cards of one page in with a short scale pop. TWO paths need it --
-- switching to a tab and coming back from the pill -- and a UIScale is used rather
-- than Size so the layout pass is untouched: animating AutomaticSize frames' sizes
-- is how cards get permanently misaligned.
function Shell.replayCards(self, id)
	if id == nil then
		return
	end
	local frame = self.pageFrames[id]
	if frame == nil or frame.Visible ~= true then
		return
	end

	local order = 0
	for _, object in ipairs(frame:GetDescendants()) do
		if object:GetAttribute(Attributes.CARD) == true then
			order += 1
			if order > 12 then
				break
			end
			local cardScale = object:FindFirstChild("_MK_CardScale")
			if cardScale == nil then
				cardScale = Instance.new("UIScale")
				cardScale.Name = "_MK_CardScale"
				cardScale.Parent = object
			end
			cardScale.Scale = 0.96
			self.kit:delay((order - 1) * 0.022, function()
				if object.Parent ~= nil then
					self.kit:tween(cardScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			end)
		end
	end
end

function Shell.switchTab(self, id)
	if id == nil then
		return
	end
	self.activeTab = id
	for pageId, frame in pairs(self.pageFrames) do
		frame.Visible = pageId == id
		if pageId == id then
			frame.Position = UDim2.fromOffset(14, 0)
			self.kit:tween(frame, 0.16, { Position = UDim2.fromOffset(0, 0) })
			Shell.replayCards(self, id)
		end
	end
	for index, page in ipairs(self.pages) do
		local active = page.id == id
		self.kit:tween(self.navButtons[index], 0.14, {
			BackgroundColor3 = if active then self.kit:color("BgSoft") else self.kit:color("White"),
			TextColor3 = if active then self.kit:color("TextPrimary") else self.kit:color("TextSecond"),
		})
		if active then
			self.kit:tween(self.indicator, 0.18, {
				Position = UDim2.fromOffset(0, (index - 1) * 40 + 8),
			}, Enum.EasingStyle.Quint)
		end
	end
end

-- behaviour

-- Does an OVERLAY (the info panel) own this screen point right now? Roblox's own
-- input routing cannot answer this for us: the panel is a SIBLING of the main frame,
-- so a press that lands on one of its non-Active children (a label, the read-out
-- list) never reaches the panel's own drag handler -- but it does reach the main
-- window's title bar underneath: "如果实时信息面板与主面板的标题栏重叠，我拖动它会同时
-- 拖动主面板，这是点击穿透问题". `main.luau` installs the predicate (the shell does not
-- own the panel); a missing one means nothing is layered over the window.
function Shell.overlayTakes(self, position): boolean
	local check = self.isOverlayAt
	if type(check) ~= "function" or position == nil then
		return false
	end
	local ok, taken = pcall(check, position.X, position.Y)
	return ok and taken == true
end

function Shell.bindDrag(self, handle)
	local dragging = false
	local startInput = nil
	local startPosition = nil

	self.kit:track(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local position = handle.AbsolutePosition
		local size = handle.AbsoluteSize
		-- The panel above wins the cursor: see Shell.overlayTakes. Checked BEFORE the
		-- button-strip exemption below, because that strip is exactly where the info
		-- panel's bar tends to sit -- the exemption used to swallow the press instead
		-- of leaving it to the panel.
		if Shell.overlayTakes(self, input.Position) then
			return
		end
		-- THE EXEMPTION IS IN RENDERED PIXELS: `TOP_BUTTON_ZONE` is measured in
		-- UNSCALED units, but `input.Position` and `handle.AbsoluteSize` are rendered
		-- ones and the buttons' offsets are multiplied by the window's UIScale. Above
		-- ~120% scale the minimise button sat further left than the flat 130 px strip,
		-- so pressing it also armed a window drag.
		local factor = 1
		if self.mainScale ~= nil then
			local scale = tonumber(self.mainScale.Scale)
			if scale ~= nil and scale > 0 then
				factor = scale
			end
		end
		local zone = TOP_BUTTON_ZONE * math.max(1, factor)
		if input.Position.X >= position.X + size.X - zone then
			return
		end
		dragging = true
		startInput = input.Position
		startPosition = self.main.Position
	end))

	self.kit:track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local factor = self.mainScale.Scale
		if factor <= 0.01 then
			factor = 1
		end
		local delta = input.Position - startInput
		self.main.Position = UDim2.new(
			startPosition.X.Scale, startPosition.X.Offset + delta.X / factor,
			startPosition.Y.Scale, startPosition.Y.Offset + delta.Y / factor
		)
	end))

	self.kit:track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not dragging then
			return
		end
		dragging = false
		if self.pill then
			local position = self.main.Position
			self.store:set("uiState.savedPill", { xs = position.X.Scale, xo = position.X.Offset, ys = position.Y.Scale, yo = position.Y.Offset })
			return
		end

		-- Put the window back on screen BEFORE saving where it is: the saved position
		-- is what the next session restores, so persisting an off-screen one makes the
		-- problem permanent -- the window returns where it cannot be reached, and the
		-- controls that would move it are precisely the ones out of reach. The save is
		-- deferred by the clamp tween's duration, because reading `main.Position` while
		-- it animates would record an intermediate value.
		local function saveMain()
			local position = self.main.Position
			self.store:set("uiState.savedMain", {
				xs = position.X.Scale, xo = position.X.Offset,
				ys = position.Y.Scale, yo = position.Y.Offset,
			})
		end

		if Shell.clampOnScreen(self) then
			self:delay(0.28, saveMain)
		else
			saveMain()
		end
	end))
end

-- Change the window's shape -- VISIBLY. "我点最小化和最大化按钮没有动画，没有那种变大变小
-- 的动画": both the legacy script and the refactor tweened Size/Position/CornerRadius,
-- but BEHIND an opaque white cover (fade in 0.13 s, tween unseen, fade out), so the
-- net effect was a white flash and a window already at the new size.
-- Now the motion is what you see: the shell's properties tween directly (Quint, as
-- legacy `morphShell` did); the layers that must SURVIVE are made visible first so
-- `main.ClipsDescendants` reveals them progressively; the layers that must be GONE
-- at rest are switched off only after the motion lands (`onCovered`); and the window
-- is re-clamped at the end -- otherwise a restore from y≈0 left "最小化后把标题栏拖到最
-- 上面，再最大化，UI 卡在屏幕外". `morphSeq` still guards overlapping chains: every
-- delayed step bails out when a newer morph has started.
function Shell.morph(self, options)
	self.morphSeq += 1
	local seq = self.morphSeq
	self.morphAt = os.clock()
	local move = options.move or 0.22

	if options.before ~= nil then
		pcall(options.before)
	end

	if options.corner ~= nil then
		self.kit:tween(self.mainCorner, move, { CornerRadius = UDim.new(0, options.corner) }, Enum.EasingStyle.Quint)
	end

	local props = {}
	if options.size ~= nil then
		props.Size = options.size
	end
	if options.position ~= nil then
		props.Position = options.position
	end
	self.kit:tween(self.main, move, props, Enum.EasingStyle.Quint)

	self:delay(move + 0.02, function()
		if self.destroyed or self.morphSeq ~= seq then
			return
		end
		if options.onCovered ~= nil then
			pcall(options.onCovered)
		end
		self.morphAt = 0
		-- Absolute* are only meaningful once the new size has propagated, so the
		-- clamp gets its own beat. `clampOnScreen` returns true when it had to move
		-- the window; nothing to persist here (a morph is not a user-chosen
		-- position), so the result is only used for the reveal.
		self:delay(0.06, function()
			if self.destroyed or self.morphSeq ~= seq then
				return
			end
			Shell.clampOnScreen(self)
			if options.onRevealed ~= nil then
				pcall(options.onRevealed)
			end
		end)
	end)
end

-- Fade the pill's own contents: entering the pill has to look like the window
-- collapsing ONTO its label, not a bare rectangle appearing (legacy V1007's
-- `setPillContent(alpha, time)` did exactly this over the bars, title, live line and
-- status dot).
function Shell.setPillContent(self, alpha, time)
	local duration = time or 0.18
	local transparency = math.clamp(alpha, 0, 1)
	for _, bar in ipairs(self.pillBars or {}) do
		self.kit:tween(bar, duration, { BackgroundTransparency = transparency })
	end
	if self.pillTitle ~= nil then
		self.kit:tween(self.pillTitle, duration, { TextTransparency = transparency })
	end
	if self.pillLive ~= nil then
		self.kit:tween(self.pillLive, duration, { TextTransparency = transparency })
	end
	if self.pillDot ~= nil then
		self.kit:tween(self.pillDot, duration, { BackgroundTransparency = math.min(1, transparency + 0.1) })
	end
end

-- Collapse to the title bar, or restore the window. `instant` applies the end state
-- with no morph (used at build, when there is nothing to animate from). Both
-- directions go through Shell.visualState, which is what makes the restore work at
-- all: the previous version had no restore branch -- it always morphed to
-- MINIMIZED_HEIGHT and hid the panels, so un-minimising collapsed the window again
-- and the minimise button could only ever go one way.
function Shell.setMinimized(self, minimized, instant)
	self.minimized = minimized
	local state = Shell.visualState(self)

	-- Show what the button will DO: without this the button read "—" in both
	-- states, so a collapsed window looked like a dead end -- nothing on screen said
	-- that pressing it again would bring the window back.
	if self.minimizeButton ~= nil then
		self.minimizeButton.Text = if minimized then "+" else "—"
	end

	if instant then
		Shell.applyVisualState(self, state)
		return
	end

	Shell.morph(self, {
		move = 0.24,
		size = UDim2.fromOffset(state.layout.width, state.layout.height),
		corner = state.layout.corner,
		-- RESTORING has to make the layers visible BEFORE the window grows:
		-- `main.ClipsDescendants` is what turns "these are visible" into "they are
		-- revealed as the window passes over them"; doing it afterwards would pop
		-- them into an already-grown window.
		before = function()
			if self.nav ~= nil then
				self.nav.Visible = true
			end
			if self.content ~= nil then
				self.content.Visible = true
			end
			if self.topFill ~= nil then
				self.topFill.Visible = true
			end
		end,
		onCovered = function()
			Shell.applyVisualState(self, state)
		end,
	})
end

function Shell.setPill(self, enabled)
	if enabled == self.pill then
		return
	end
	self.pill = enabled
	-- Mirror into the store. The guard above is what makes the subscription in
	-- bindStore a no-op for our own write, so this is a single source of truth
	-- rather than a second copy: a config load or any other writer moves the window
	-- through the same path.
	self.store:set("uiState.pill", enabled)

	local state = Shell.visualState(self)

	-- The pill's position is its own; leaving it stays where the window was
	-- saved to.
	local position = nil
	if enabled then
		position = self.pillPosition or UDim2.new(0.5, 0, 0.18, 0)
	else
		local saved = self.store:get("uiState.savedMain")
		position = if type(saved) == "table"
			then UDim2.new(saved.xs or 0.5, saved.xo or 0, saved.ys or 0.5, saved.yo or 0)
			else UDim2.new(0.5, 0, 0.5, 0)
	end

	Shell.morph(self, {
		move = if enabled then 0.26 else 0.28,
		size = UDim2.fromOffset(state.layout.width, state.layout.height),
		corner = state.layout.corner,
		position = position,
		before = function()
			if enabled then
				-- Collapsing onto the pill: the label fades IN while the box
				-- shrinks around it.
				self.pillLayer.Visible = true
				Shell.setPillContent(self, 1, 0.02)
				Shell.setPillContent(self, 0, 0.24)
			else
				-- Growing back: the window's layers have to be visible for the
				-- growth to reveal them, and the pill label fades out.
				self.topBar.Visible = true
				self.nav.Visible = true
				self.content.Visible = true
				self.status.Visible = true
				self.topFill.Visible = self.minimized ~= true
				Shell.setPillContent(self, 1, 0.16)
			end
		end,
		onCovered = function()
			Shell.applyVisualState(self, state)
			if not enabled and self.pillLayer ~= nil then
				self.pillLayer.Visible = false
			end
		end,
		-- Coming back from the pill re-pops the active page; going INTO the pill has
		-- nothing to pop.
		onRevealed = function()
			if not enabled then
				Shell.replayCards(self, self.activeTab)
			end
		end,
	})
end

function Shell.setTheme(self, name)
	-- `Theme.has`, not a nil check on `Theme.palette`: the palette accessor falls
	-- back instead of returning nil, so a nil guard is dead and any unknown name
	-- would be accepted.
	if name == self.themeName or not Theme.has(name) then
		return
	end
	local remap = Theme.remap(self.themeName, name)
	self.themeName = name
	self.roles = Theme.roles(name)
	self.kit.roles = self.roles
	self.kit.theming = true
	local changed = Theme.apply(self.screen, remap)
	self.kit.theming = false
	self.store:set("uiState.theme", name)

	-- SECOND PASS, and then the settle signal. A widget caught mid-tween (a button
	-- the pointer just left, a card still popping in) is not sitting on a palette
	-- value, so the first pass has to match it within a tolerance and can miss.
	-- This second pass is a SNAP (duration 0): by then the first has landed, so any
	-- widget still off-palette is one a tween is actively holding, and snapping it
	-- removes the residue rather than nudging it.
	-- `uiState.themeEpoch` is then bumped so pages that own colours the remap cannot
	-- reach (the theme page's selected marker) can re-assert them after the repaint
	-- instead of racing it.
	self:delay(Theme.RECOLOR_TIME + 0.12, function()
		if self.destroyed then
			return
		end
		self.kit.theming = true
		Theme.apply(self.screen, remap, 0)
		self.kit.theming = false
		self.store:set("uiState.themeEpoch", (tonumber(self.store:get("uiState.themeEpoch")) or 0) + 1)
		if self.onThemeSettled ~= nil then
			pcall(self.onThemeSettled)
		end
	end)

	-- Persist the theme immediately: the autosave fires on a timer and would get
	-- there eventually, but a theme is a visible choice the user just made -- if the
	-- session ends (crash, kick, rejoin) inside that window, the choice is lost.
	if self.services.persist ~= nil then
		local ok, err = self.services.persist.save(self.store)
		if not ok then
			warn("[MKUltraHUB][config] theme save failed: " .. tostring(err))
		end
	end
	return changed
end

function Shell.bindInput(self)
	local kit = self.kit
	kit:track(self.pillLayer.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- THE SAME OVERLAY GUARD THE WINDOW DRAG HAS. The info panel stays visible
		-- while the main window is a pill (`uiState.infoHideWithShell` defaults to
		-- false), so the two normally sit on top of each other -- and a press on the
		-- panel therefore armed BOTH drags at once: one finger, two windows, the
		-- reported "拖动一个同时拖动另一个".
		if Shell.overlayTakes(self, input.Position) then
			return
		end
		self.pillDragging = true
		self.pillStart = input.Position
		self.pillStartPosition = self.main.Position
		self.pillStartAt = os.clock()
	end))
	kit:track(UserInputService.InputChanged:Connect(function(input)
		if not self.pillDragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local factor = self.mainScale.Scale
		if factor <= 0.01 then
			factor = 1
		end
		local delta = input.Position - self.pillStart
		self.main.Position = UDim2.new(
			self.pillStartPosition.X.Scale, self.pillStartPosition.X.Offset + delta.X / factor,
			self.pillStartPosition.Y.Scale, self.pillStartPosition.Y.Offset + delta.Y / factor
		)
	end))
	kit:track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not self.pillDragging then
			return
		end
		self.pillDragging = false
		local moved = if self.pillStart ~= nil then (input.Position - self.pillStart).Magnitude else 0
		if moved < 5 and os.clock() - self.pillStartAt < 0.35 then
			Shell.setPill(self, false)
		else
			self.pillPosition = self.main.Position
		end
	end))
end

-- The shell follows the store, so a change from anywhere moves the window.
function Shell.bindStore(self)
	local store = self.store
	self.kit:track(store:subscribe("uiState.theme", function(_, value)
		if typeof(value) == "string" then
			Shell.setTheme(self, value)
		end
	end))
	self.kit:track(store:subscribe("uiState.minimized", function(_, value)
		Shell.setMinimized(self, value == true)
	end))
	self.kit:track(store:subscribe("uiState.pill", function(_, value)
		Shell.setPill(self, value == true)
	end))
	self.kit:track(store:subscribe("uiState.uiScale", function()
		Shell.applySize(self)
	end))
	self.kit:track(store:subscribe("uiState.widthPct", function()
		Shell.applySize(self)
	end))
	self.kit:track(store:subscribe("uiState.heightPct", function()
		Shell.applySize(self)
	end))
	-- Saved positions are written by dragging, so only react to external changes
	-- (a config load, a reset) rather than echoing our own.
	self.kit:track(store:subscribe("uiState.savedPill", function(_, value)
		if type(value) == "table" and self.pill then
			self.pillPosition = UDim2.new(value.xs or 0.5, value.xo or 0, value.ys or 0.5, value.yo or 0)
		end
	end))

	-- `uiState.savedMain` needs a subscriber, or the settings button that writes it
	-- ("reset window position") does nothing at all: the store changes, the window
	-- stays where it is, and the control looks broken. Dragging also writes this
	-- key, which is why the move is skipped when the window is already at the
	-- target.
	self.kit:track(store:subscribe("uiState.savedMain", function(_, value)
		if type(value) ~= "table" or self.pill or self.destroyed then
			return
		end
		local target = UDim2.new(value.xs or 0.5, value.xo or 0, value.ys or 0.5, value.yo or 0)
		if self.main.Position == target then
			return
		end
		self.kit:tween(self.main, 0.24, { Position = target }, Enum.EasingStyle.Quint)
	end))

	-- `uiState.fontScale` used to be written by a settings slider that NOTHING read,
	-- so the slider moved and the interface never changed; applying it here gives the
	-- control the effect it promises.
	self.kit:track(store:subscribe("uiState.fontScale", function()
		Shell.applyFontScale(self)
	end))

	-- Re-layout when the viewport changes: `Shell.windowSize` derives the size from
	-- `Camera.ViewportSize` and the width/height percentages, so resizing the Roblox
	-- window (or going fullscreen) left the panel at the old resolution's proportions
	-- with stale clamps -- and because the size is stored in percentages, the CORRECT
	-- size is computable at any moment; only the notification was missing.
	-- Debounced through the runtime's Timers rather than run inline: a window drag
	-- emits this signal continuously and each pass re-tweens the shell.
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local pending = nil
		self.kit:track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if pending ~= nil then
				return
			end
			pending = false
			self:delay(0.1, function()
				pending = nil
				if self.destroyed then
					return
				end
				-- `applySize` ends in `reapplyPosition`, which re-derives the position
				-- from the store for the NEW viewport, so a resolution change cannot
				-- leave the panel somewhere the store disagrees with.
				Shell.applySize(self)
			end)
		end))
	end
end

function Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	local kit = self.kit
	local store = self.store

	-- Kept on the instance: setMinimized flips the button's glyph.
	self.minimizeButton = minimizeButton
	self.pillButton = pillButton
	self.closeButton = closeButton

	kit:track(minimizeButton.MouseButton1Click:Connect(function()
		-- Writing the store is the whole action: the subscription collapses it.
		store:set("uiState.minimized", store:get("uiState.minimized") ~= true)
	end))

	kit:track(pillButton.MouseButton1Click:Connect(function()
		self.pillPosition = self.main.Position
		Shell.setPill(self, not self.pill)
	end))

	kit:track(closeButton.MouseButton1Click:Connect(function()
		Shell.confirm(self, "关闭确认", "确定要关闭脚本吗？", function()
			-- Animated exit, then teardown: see Shell.closeAnimated.
			Shell.closeAnimated(self)
		end)
	end))
end

-- Keyboard shortcuts (V1007 had these and the settings page still advertises them):
--     RightShift  show / hide the window (pill)
--     RightCtrl   pause / resume
--     RightAlt    unfreeze (the "I cannot move" escape hatch)
--     Space       step off a gym machine
-- `gameProcessedEvent` is honoured so typing in a TextBox is never treated as a
-- shortcut, and the whole binding is gated on `cfg.hotkeys`, the switch the settings
-- page already exposes.
function Shell.bindHotkeys(self)
	local UserInputService = game:GetService("UserInputService")
	local store = self.store

	self.kit:track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if store:get("cfg.hotkeys") ~= true then
			return
		end

		local code = input.KeyCode
		if code == Enum.KeyCode.RightShift then
			if self.pill then
				Shell.setPill(self, false)
			else
				self.pillPosition = self.main.Position
				Shell.setPill(self, true)
			end
		elseif code == Enum.KeyCode.RightControl then
			-- The pause switch is a store key, so this drives exactly the same
			-- path as the settings toggle and the scheduler subscription.
			store:set("runtime.paused", store:get("runtime.paused") ~= true)
		elseif code == Enum.KeyCode.RightAlt then
			local motion = self.services.motion
			local teleport = self.services.teleport
			if teleport ~= nil then
				pcall(function()
					teleport:cancel()
				end)
			end
			if motion ~= nil then
				pcall(function()
					motion:unfreeze()
				end)
			end
			Shell.toast(self, "已解除冻结，可以自己移动了", "success")
		elseif code == Enum.KeyCode.Space then
			-- Step off the gym machine: the machine itself is escaped with a Space key
			-- event, so pressing it by hand is the natural manual override. Only acts
			-- while a machine is actually engaged, or it would swallow the jump key.
			local machine = self.services.machine
			if machine == nil then
				return
			end
			local phase = machine:stats().phase
			if phase ~= "mounting" and phase ~= "mounted" then
				return
			end
			pcall(function()
				machine:dismount()
			end)
			Shell.toast(self, "已下器械", "info")
		end
	end))
end

-- Long-press reset: a floating button that restores every UI state value to its
-- default after a 3-second hold, with the fill as visible progress. It is the only
-- recovery path when the window has been dragged off screen or scaled to something
-- unusable -- a situation the user cannot fix by clicking, because the controls are
-- the thing that is broken.
function Shell.buildResetButton(self, screen)
	if screen == nil then
		return
	end
	local kit = self.kit
	local HOLD_SECONDS = 3

	local button = kit:instance("TextButton", {
		Name = "ResetButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -56),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = kit:color("Red"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "复位",
		TextColor3 = kit:color("White"),
		TextSize = 12,
		TextWrapped = true,
		ZIndex = 2100,
		AutoButtonColor = false,
	}, screen)
	kit:corner(button, 27)
	local resetStroke = kit:stroke(button, kit:color("Border"), 1.5, 0.35)

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	-- A rotating red->yellow gradient, spun by the hold loop as a progress ring: the
	-- only feedback the button gives besides the percentage (the fill bar is 4px
	-- tall), on the one control that must work when the rest of the UI does not.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, kit:color("Red")),
		ColorSequenceKeypoint.new(1, kit:color("Yellow")),
	})
	gradient.Transparency = NumberSequence.new(0.3)
	gradient.Rotation = 0
	gradient.Parent = button

	-- Hover feedback, the same shape every other button in the UI uses.
	kit:track(button.MouseEnter:Connect(function()
		kit:tween(button, 0.14, { BackgroundColor3 = kit:color("Yellow") })
		kit:tween(resetStroke, 0.14, { Transparency = 0 })
		kit:tween(scale, 0.16, { Scale = 1.08 }, Enum.EasingStyle.Back)
	end))
	kit:track(button.MouseLeave:Connect(function()
		kit:tween(button, 0.14, { BackgroundColor3 = kit:color("Red") })
		kit:tween(resetStroke, 0.14, { Transparency = 0.35 })
		kit:tween(scale, 0.16, { Scale = 1 })
	end))

	local progress = kit:instance("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.new(0, 0, 0, 4),
		BackgroundColor3 = kit:color("Yellow"),
		BorderSizePixel = 0,
		ZIndex = 2101,
	}, button)
	kit:corner(progress, 2)

	local holding = false
	local startedAt = 0

	kit:track(button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		holding = true
		startedAt = os.clock()

		task.spawn(function()
			while holding and not self.destroyed do
				local fraction = math.clamp((os.clock() - startedAt) / HOLD_SECONDS, 0, 1)
				progress.Size = UDim2.new(fraction, 0, 0, 4)
				button.Text = string.format("%d%%", math.floor(fraction * 100))
				gradient.Rotation = (gradient.Rotation + 8) % 360
				if fraction >= 1 then
					holding = false
					button.Text = "复位"
					progress.Size = UDim2.new(0, 0, 0, 4)
					Shell.resetLayout(self)
					return
				end
				task.wait(0.03)
			end
		end)
	end))

	kit:track(button.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		holding = false
		button.Text = "复位"
		progress.Size = UDim2.new(0, 0, 0, 4)
	end))

	self.resetButton = button
end

-- Put every layout value back to its default and re-apply it. The reset has to be
-- complete: this button exists for the case where the window is off-screen or scaled
-- into uselessness, and the INFO panel has its own size, scale and saved position --
-- all store keys a partial reset would leave broken. `onReset` is the hook main.luau
-- uses to re-apply those panel values, because the Shell does not own the InfoWindow.
function Shell.resetLayout(self)
	local store = self.store
	store:set("uiState.widthPct", 45)
	store:set("uiState.heightPct", 52)
	store:set("uiState.uiScale", 100)
	store:set("uiState.fontScale", 1)
	store:set("uiState.minimized", false)
	store:set("uiState.pill", false)
	-- The info panel's own layout.
	store:set("uiState.infoScale", 100)
	store:set("uiState.savedInfo", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
	store:set("uiState.savedInfoSize", { xs = 0, xo = 320, ys = 0, yo = 470 })

	-- The centre is reached by WRITING THE STORE, not by assigning `Position`: the
	-- subscriber in `bindStore` tweens the window there, so the reset is animated like
	-- every other move instead of teleporting (assigning directly also made that
	-- subscriber a no-op, "already at the target").
	store:set("uiState.savedMain", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
	self.pillPosition = UDim2.new(0.5, 0, 0.18, 0)

	Shell.applySize(self)
	Shell.applyFontScale(self)
	if self.onReset ~= nil then
		pcall(self.onReset)
	end
	Shell.toast(self, "界面已复位", "success")
end

-- Live read-outs that are not bound to a store key: "运行中: 打Boss + 全图杀戮" along
-- the bottom, and "力量/秒 · 当前任务" on the pill.
function Shell.bindStatus(self)
	local scheduler = self.scheduler
	local metrics = self.services.metrics

	Shell.addUiTick(self, function()
		-- Stuck-cover watchdog. The cover is a full-window opaque frame used only by
		-- the CLOSE animation now (shape changes tween the shell itself -- see
		-- Shell.morph). If its delayed step is dropped, the entire interface is a flat
		-- rectangle with the controls still live underneath, which reads as a rendering
		-- bug rather than a state bug. The check is deliberately generous: a legitimate
		-- close is over in 0.24 s, so anything still covered after 2 s is not a close
		-- in progress.
		if self.cover ~= nil and self.cover.Visible == true then
			local since = if self.morphAt ~= nil and self.morphAt > 0 then os.clock() - self.morphAt else 999
			if since > 2 then
				self.cover.Visible = false
				self.cover.BackgroundTransparency = 1
				self.morphAt = 0
				warn("[MKUltraHUB][ui] 形态切换遮罩卡住，已强制清除")
			end
		end

		-- Per-task liveness watchdog. The scheduler notices a task that THROWS and
		-- backs it off; it cannot notice one that has silently stopped doing anything
		-- (a latched guard, an `enabled()` that started answering false for the wrong
		-- reason, a `tick` returning early), which from the outside looks exactly like
		-- a task that is working. REPORTED, never restarted: a task that stopped on
		-- purpose must not be revived behind the guard that stopped it. Naming the task
		-- is the whole value -- it turns "锻炼没反应" into "任务 train 超过 8 秒没运行".
		if self.scheduler ~= nil and self.scheduler.stalled ~= nil then
			local quiet = self.scheduler:stalled(os.clock(), 8)
			self._stalledLogged = self._stalledLogged or {}
			for _, id in ipairs(quiet) do
				local last = self._stalledLogged[id]
				if last == nil or os.clock() - last > 60 then
					self._stalledLogged[id] = os.clock()
					warn(string.format("[MKUltraHUB][ui] 任务 %s 已激活但超过 8 秒没有运行", id))
				end
			end
		end

		local running = {}
		if scheduler ~= nil then
			for _, entry in ipairs(scheduler:snapshot()) do
				if entry.active then
					local label = Shell.TASK_LABELS[entry.id]
					if label ~= nil then
						table.insert(running, label)
					end
				end
			end
		end

		if self.status ~= nil then
			if #running == 0 then
				self.status.Text = "空闲中"
			else
				self.status.Text = "运行中: " .. table.concat(running, " + ")
			end
		end

		if self.pillLive ~= nil then
			if self.store:get("runtime.paused") == true then
				self.pillLive.Text = "已暂停"
				if self.pillDot ~= nil then
					self.pillDot.BackgroundColor3 = self.kit:color("Yellow")
				end
			else
				local perSec = 0
				if metrics ~= nil and metrics.strengthStats ~= nil then
					perSec = metrics:strengthStats().perSec or 0
				end
				-- The first label is the highest-priority running task, matching the
				-- order the scheduler runs them in. The rate respects "数字格式化显示"
				-- like the info panel does: the pill is the most-read read-out, so a
				-- toggle that changed only the panel would look broken here.
				local perSecText = if self.store:get("uiState.formatNum") == false
					then Format.number(perSec, false)
					else Format.number(perSec)
				self.pillLive.Text = string.format("%s/s · %s", perSecText, running[1] or "空闲")
				if self.pillDot ~= nil then
					self.pillDot.BackgroundColor3 = self.kit:color("Green")
				end
			end
		end
	end)
end

-- A small confirm dialog. The holder is what gets destroyed -- it is the full-screen
-- click absorber; destroying only the inner card left a black overlay permanently
-- covering the screen and eating every click. `onCancel` is optional and runs for
-- EVERY dismissal that is not `确认` (the 取消 button, a click on the backdrop, the
-- close tween): a caller whose action keeps running in the background after the
-- dialog closes (the rejoin countdown) must be told, or cancelling it would still
-- fire three seconds later.
function Shell.confirm(self, title, text, onConfirm, onCancel)
	local kit = self.kit
	local holder = kit:instance("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 900,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		-- Same reasoning as Shell.preview: a live full-screen button reports
		-- `gameProcessedEvent`, so it would swallow every drag and click meant for the
		-- window underneath; the dialog's own buttons close it, this layer is the dim.
		Active = false,
	}, self.screen)
	local card = kit:instance("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(340, 150),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ZIndex = 901,
		Active = true,
	}, holder)
	kit:corner(card, 12)
	kit:stroke(card, kit:color("Border"), 1.5, 0)
	kit:shadow(card, 12, 0.88)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = card
	kit:tween(holder, 0.2, { BackgroundTransparency = 0.5 })
	kit:tween(scale, 0.26, { Scale = 1 }, Enum.EasingStyle.Back)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -32, 0, 28),
		Position = UDim2.fromOffset(16, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 902,
	}, card)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -32, 1, -100),
		Position = UDim2.fromOffset(16, 48),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = kit:color("TextSecond"),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 902,
	}, card)

	local closed = false
	-- Set by the 确认 handler before `close()` runs, so the shared close path can
	-- tell "confirmed" from "dismissed" without a second callback.
	local confirmed = false
	local function close()
		if closed then
			return
		end
		closed = true
		kit:tween(scale, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		kit:tween(holder, 0.18, { BackgroundTransparency = 1 })
		if not confirmed and onCancel ~= nil then
			pcall(onCancel)
		end
		self:delay(0.2, function()
			pcall(function()
				holder:Destroy()
			end)
		end)
	end

	local cancel = kit:instance("TextButton", {
		Size = UDim2.fromOffset(110, 34),
		Position = UDim2.new(1, -276, 1, -50),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "取消",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 14,
		ZIndex = 903,
	}, card)
	kit:corner(cancel, 6)
	kit:stroke(cancel, kit:color("Border"), 1, 0)
	kit:animate(cancel, kit:color("White"))

	local confirm = kit:instance("TextButton", {
		Size = UDim2.fromOffset(110, 34),
		Position = UDim2.new(1, -156, 1, -50),
		BackgroundColor3 = kit:color("Green"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "确认",
		TextColor3 = kit:color("White"),
		TextSize = 14,
		ZIndex = 903,
	}, card)
	kit:corner(confirm, 6)
	kit:animate(confirm, kit:color("Green"))

	kit:track(confirm.MouseButton1Click:Connect(function()
		confirmed = true
		close()
		if onConfirm ~= nil then
			task.spawn(onConfirm)
		end
	end))
	kit:track(cancel.MouseButton1Click:Connect(close))
	-- Clicking the backdrop dismisses without confirming, so it is a cancel too.
	kit:track(holder.MouseButton1Click:Connect(close))

	return { destroy = close }
end

-- A dismissible detail card (V1007's `Core.showPreview`): a small card anchored to
-- the control that opened it, listing whatever the caller wants, closed by clicking
-- anywhere or after a timeout. The content is a LIST ("每只名字 × 数量"), and a list
-- that vanishes on a timer cannot be read carefully or copied from -- which is why a
-- toast is a poor substitute. Only one card at a time: opening a second replaces the
-- first.
function Shell.preview(self, title, lines, lifetime, anchor)
	local kit = self.kit

	if self.previewCard ~= nil then
		pcall(function()
			self.previewCard:Destroy()
		end)
		self.previewCard = nil
	end

	local lineCount = math.max(1, #lines)
	local height = math.min(360, 46 + lineCount * 18)
	local holder = kit:instance("TextButton", {
		Name = "Preview",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 910,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		-- The full-screen dismiss layer must NOT be a live button: it was one, and that
		-- is why "点了问号之后整个窗口拖不动" happened -- a Button reports
		-- `gameProcessedEvent = true`, so while the preview was up every drag of the
		-- main window was swallowed by this transparent layer instead of reaching the
		-- title bar underneath. With `Active = false` the card still closes on click
		-- and the rest of the interface keeps working.
		Active = false,
	}, self.screen)

	-- Anchored to the control that opened it when one is given (offset to its left and
	-- just below it); centring is the fallback, because a card whose anchor has
	-- scrolled out of view is better centred than off-screen.
	local position = UDim2.new(0.5, 0, 0.5, 0)
	if anchor ~= nil and anchor.Parent ~= nil then
		local okAnchor, buttonPosition = pcall(function()
			return anchor.AbsolutePosition
		end)
		local okSize, buttonSize = pcall(function()
			return anchor.AbsoluteSize
		end)
		local okScreen, screenPosition = pcall(function()
			return self.screen.AbsolutePosition
		end)
		local okViewport, viewport = pcall(function()
			local camera = Workspace.CurrentCamera
			return if camera ~= nil then camera.ViewportSize else nil
		end)
		if okAnchor and okSize and okScreen and okViewport and viewport ~= nil then
			local x = (buttonPosition.X - screenPosition.X) + buttonSize.X - 320
			local y = (buttonPosition.Y - screenPosition.Y) + buttonSize.Y + 6
			-- Clamp into the viewport: the card is 320 wide and `height` tall.
			if x < 4 then
				x = 4
			elseif x + 320 > viewport.X - 4 then
				x = math.max(4, viewport.X - 4 - 320)
			end
			if y + height > viewport.Y - 4 then
				local above = (buttonPosition.Y - screenPosition.Y) - height - 6
				y = if above >= 4 then above else math.max(4, viewport.Y - 4 - height)
			end
			position = UDim2.fromOffset(x, y)
		end
	end

	local card = kit:instance("Frame", {
		Position = position,
		Size = UDim2.fromOffset(320, height),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ZIndex = 911,
		Active = true,
	}, holder)
	kit:corner(card, 10)
	kit:stroke(card, kit:color("Border"), 1.4, 0)
	kit:shadow(card, 10, 0.9)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = card
	kit:tween(holder, 0.18, { BackgroundTransparency = 0.55 })
	kit:tween(scale, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 912,
	}, card)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -24, 1, -48),
		Position = UDim2.fromOffset(12, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = table.concat(lines, "\n"),
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 912,
	}, card)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 1, -20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "点击任意处关闭",
		TextColor3 = kit:color("TextMuted"),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 912,
	}, card)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if self.previewCard == holder then
			self.previewCard = nil
		end
		kit:tween(scale, 0.14, { Scale = 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		kit:tween(holder, 0.16, { BackgroundTransparency = 1 })
		self:delay(0.18, function()
			pcall(function()
				holder:Destroy()
			end)
		end)
	end

	kit:track(holder.MouseButton1Click:Connect(close))
	self.previewCard = holder
	-- A generous default: this is readable content, not a notification.
	self:delay(tonumber(lifetime) or 20, close)
	return { destroy = close }
end

function Shell.destroy(self)
	self.destroyed = true
	if self.screen ~= nil then
		pcall(function()
			self.screen:Destroy()
		end)
	end
	self.kit:destroy()
end

return Shell
end

__modules["ui/Toast"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- Toast -- the notification stack: the only place that decides how a message
-- looks, so a subsystem never has to know whether there is a UI at all.
-- Card height, accent bar and text animate together, and the stack is capped.

local TweenService = game:GetService("TweenService")

local Toast = {}
Toast.__index = Toast

local CARD_WIDTH = 300
local CARD_HEIGHT = 44
local CARD_LIFETIME = 3
local MAX_VISIBLE = 5
local MAX_SCREEN_FRACTION = 0.8

function Toast.new(context)
	local self = setmetatable({
		screen = context.screen,
		kit = context.kit,
		store = context.store,
		-- Optional: with the runtime's Timers injected, a card's retirement
		-- timers are cancelled by `Runtime.destroy()` rather than firing into a
		-- torn-down GUI.
		timers = context.timers,
		holder = nil,
		layout = nil,
		sequence = 0,
		live = {},
		-- key -> { card, accent, label, at, timer, retire }.
		byKey = {},
	}, Toast)
	return self
end

-- Through the runtime's Timers when available, else a raw delay. See Kit.delay.
function Toast.delay(self, seconds, fn)
	local timers = self.timers
	if timers ~= nil then
		return timers:after(os.clock(), seconds, fn)
	end
	task.delay(seconds, fn)
	return nil
end

function Toast.ensureHolder(self)
	if self.holder ~= nil and self.holder.Parent ~= nil then
		return self.holder
	end
	local holder = self.kit:instance("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(CARD_WIDTH, 0),
		BackgroundTransparency = 1,
		ZIndex = 900,
	}, self.screen)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = holder

	self.holder = holder
	self.layout = layout
	return holder
end

local function colorFor(self, kind)
	if kind == "success" then
		return self.kit:color("Green")
	end
	if kind == "error" then
		return self.kit:color("Red")
	end
	if kind == "warn" then
		return self.kit:color("Yellow")
	end
	return self.kit:color("TextPrimary")
end

-- Show a card. `duration` is optional: a caller can keep an important message
-- up longer than CARD_LIFETIME.
function Toast.show(self, text, kind, duration)
	if self.store:get("cfg.toast") == false then
		return nil
	end
	local lifetime = tonumber(duration) or CARD_LIFETIME
	if lifetime <= 0 then
		lifetime = CARD_LIFETIME
	end
	local holder = Toast.ensureHolder(self)
	local kit = self.kit
	local message = tostring(text)

	-- Coalesce: the same message still on screen is refreshed rather than
	-- duplicated, so a slider notifying on release and a toggle notifying on
	-- click cannot flood the corner.
	local key = tostring(kind) .. "\n" .. message
	local existing = self.byKey[key]
	if existing ~= nil and existing.card ~= nil and existing.card.Parent ~= nil then
		existing.at = os.clock()
		if existing.timer ~= nil then
			existing.timer:cancel()
		end
		local accent = existing.accent
		if accent ~= nil and accent.Parent ~= nil then
			accent.Size = UDim2.new(0, 4, 1, -12)
			kit:tween(accent, lifetime, { Size = UDim2.new(0, 4, 0, 0) }, Enum.EasingStyle.Linear)
		end
		local label = existing.label
		if label ~= nil and label.Parent ~= nil then
			label.Text = message
			label.TextTransparency = 0
		end
		existing.timer = self:delay(lifetime, function()
			self.byKey[key] = nil
			if existing.retire ~= nil then
				existing.retire()
			end
		end)
		return existing.card
	end

	self.sequence += 1
	local card = kit:instance("Frame", {
		Name = "Toast_" .. tostring(self.sequence),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		LayoutOrder = self.sequence,
		ZIndex = 901,
	}, holder)
	kit:corner(card, 8)
	kit:stroke(card, kit:color("Border"), 1, 0)

	local accent = kit:instance("Frame", {
		Size = UDim2.new(0, 4, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = colorFor(self, kind),
		BorderSizePixel = 0,
		ZIndex = 902,
	}, card)
	kit:corner(accent, 2)

	local label = kit:instance("TextLabel", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = message,
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTransparency = 1,
		ZIndex = 902,
	}, card)

	-- The card grows, the text fades in with it, and the accent bar drains as a
	-- countdown; animating all three stops the "box appeared around some
	-- already-visible text" look.
	kit:tween(card, 0.22, { Size = UDim2.new(1, 0, 0, CARD_HEIGHT) }, Enum.EasingStyle.Quint)
	kit:tween(label, 0.24, { TextTransparency = 0 })
	kit:tween(accent, lifetime, { Size = UDim2.new(0, 4, 0, 0) }, Enum.EasingStyle.Linear)

	table.insert(self.live, card)

	local record = { card = card, accent = accent, label = label, at = os.clock(), timer = nil }

	local function retire()
		if card.Parent == nil then
			return
		end
		local info = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		kit:tween(card, 0.24, { BackgroundTransparency = 1 })
		kit:tween(label, 0.2, { TextTransparency = 1 })
		kit:tween(accent, 0.2, { BackgroundTransparency = 1 })
		pcall(function()
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				TweenService:Create(stroke, info, { Transparency = 1 }):Play()
			end
		end)
		self:delay(0.28, function()
			for index = #self.live, 1, -1 do
				if self.live[index] == card then
					table.remove(self.live, index)
				end
			end
			if self.byKey[key] == record then
				self.byKey[key] = nil
			end
			pcall(function()
				card:Destroy()
			end)
		end)
	end
	record.retire = retire
	self.byKey[key] = record

	record.timer = self:delay(lifetime, function()
		self.byKey[key] = nil
		retire()
	end)

	-- Evicting a card has to forget its BOOKKEEPING too: destroying the frame but
	-- leaving `live` and `byKey` pointing at it made the counter keep evicting real
	-- cards, and the dead card's pending timer cleared `byKey[key]` for a NEWER
	-- card with the same message (coalescing then silently stopped working).
	local function drop(card)
		for index = #self.live, 1, -1 do
			if self.live[index] == card then
				table.remove(self.live, index)
			end
		end
		for rowKey, row in pairs(self.byKey) do
			if row.card == card then
				if row.timer ~= nil then
					row.timer:cancel()
				end
				self.byKey[rowKey] = nil
			end
		end
		pcall(function()
			card:Destroy()
		end)
	end

	-- Cap the stack: over MAX_VISIBLE cards, or taller than 80% of the screen,
	-- retire the oldest rather than letting toasts cover the game.
	while #self.live > MAX_VISIBLE do
		local oldest = self.live[1]
		if oldest == nil then
			break
		end
		drop(oldest)
	end

	local camera = workspace.CurrentCamera
	local viewportHeight = if camera ~= nil then camera.ViewportSize.Y else 720
	local stackHeight = #self.live * (CARD_HEIGHT + 5)
	if stackHeight > viewportHeight * MAX_SCREEN_FRACTION then
		local oldest = self.live[1]
		if oldest ~= nil then
			drop(oldest)
		end
	end

	return card
end

function Toast.destroy(self)
	if self.holder ~= nil then
		pcall(function()
			self.holder:Destroy()
		end)
		self.holder = nil
	end
	table.clear(self.live)
	table.clear(self.byKey)
end

return Toast
end

__modules["core/PanelPlacement"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	PanelPlacement -- where to put a second panel so it does not cover the first.

	Pure geometry. V1007 decided "does the panel overlap the main window" from the
	SAVED position rather than the live one, and both windows carry
	IgnoreGuiInset = true specifically so their coordinate systems match.

	The rule, preserved:

	    if the panel does not overlap the main window, keep it where it was
	    otherwise prefer, in order: right of it, left of it, below it, above it
	    if every side is blocked (a small screen), pick the least-overlapping
	    position on the screen edge

	"Keep it where it was" matters more than it sounds: dragging the info window
	somewhere and then reopening it must not teleport it back.
]]

local PanelPlacement = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Input = {
	screen: { w: number, h: number },
	panel: { w: number, h: number },
	main: Rect?,
	preferred: { x: number, y: number },
	gap: number?,
	margin: number?,
}

export type Result = {
	x: number,
	y: number,
	reason: string,
}

local DEFAULT_GAP = 12
local DEFAULT_MARGIN = 8

function PanelPlacement.overlap(a: Rect, b: Rect): number
	local overlapX = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local overlapY = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if overlapX <= 0 or overlapY <= 0 then
		return 0
	end
	return overlapX * overlapY
end

function PanelPlacement.resolve(input: Input): Result
	local margin = input.margin or DEFAULT_MARGIN
	local gap = input.gap or DEFAULT_GAP
	local panelWidth = input.panel.w
	local panelHeight = input.panel.h
	local maxX = math.max(margin, input.screen.w - panelWidth - margin)
	local maxY = math.max(margin, input.screen.h - panelHeight - margin)

	local function clampX(value: number): number
		return math.clamp(value, margin, maxX)
	end
	local function clampY(value: number): number
		return math.clamp(value, margin, maxY)
	end
	local function rectAt(x: number, y: number): Rect
		return { x = x, y = y, w = panelWidth, h = panelHeight }
	end

	local main = input.main
	local preferredX = clampX(input.preferred.x)
	local preferredY = clampY(input.preferred.y)

	if main == nil or PanelPlacement.overlap(rectAt(preferredX, preferredY), main) == 0 then
		return { x = preferredX, y = preferredY, reason = "kept" }
	end

	-- Right and left first: sitting alongside keeps both panels fully visible,
	-- which is what "parallel to the main window" means in practice.
	local candidates = {
		{ x = main.x + main.w + gap, y = main.y },
		{ x = main.x - gap - panelWidth, y = main.y },
		{ x = main.x, y = main.y + main.h + gap },
		{ x = main.x, y = main.y - gap - panelHeight },
	}

	-- Accumulators are initialised rather than optional: comparing and indexing
	-- an optional inside the loop is what the type checker objects to.
	--
	-- The index keeps the DOCUMENTED preference order rather than "nearest to the
	-- old position": right and left both avoid the main window, so without a
	-- preference term the panel would flip sides depending on where it was.
	local bestX, bestY, bestScore = 0, 0, math.huge
	for index, candidate in ipairs(candidates) do
		local x = clampX(candidate.x)
		local y = clampY(candidate.y)
		local overlap = PanelPlacement.overlap(rectAt(x, y), main)
		local pushed = math.abs(x - candidate.x) + math.abs(y - candidate.y)
		-- Not overlapping dominates; then how little the screen had to push it;
		-- then the declared preference order.
		local score = overlap * 1000000 + pushed * 100 + index
		if score < bestScore then
			bestScore = score
			bestX = x
			bestY = y
		end
	end

	if PanelPlacement.overlap(rectAt(bestX, bestY), main) == 0 then
		return { x = bestX, y = bestY, reason = "side" }
	end

	-- Every side is blocked: take the least-overlapping edge position.
	local edges = {
		{ x = margin, y = margin },
		{ x = maxX, y = margin },
		{ x = margin, y = maxY },
		{ x = maxX, y = maxY },
		{ x = margin, y = main.y },
		{ x = maxX, y = main.y },
		{ x = main.x, y = margin },
		{ x = main.x, y = maxY },
	}
	local edgeX, edgeY, edgeOverlap, edgeDistance = 0, 0, math.huge, math.huge
	for _, edge in ipairs(edges) do
		local x = clampX(edge.x)
		local y = clampY(edge.y)
		local overlap = PanelPlacement.overlap(rectAt(x, y), main)
		local distance = math.abs(x - preferredX) + math.abs(y - preferredY)
		if overlap < edgeOverlap or (overlap == edgeOverlap and distance < edgeDistance) then
			edgeOverlap = overlap
			edgeDistance = distance
			edgeX = x
			edgeY = y
		end
	end

	return { x = edgeX, y = edgeY, reason = "fallback" }
end

return PanelPlacement
end

__modules["ui/InfoWindow"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- InfoWindow -- the live read-out panel.
-- It lives on the SAME ScreenGui as the main window: V1007 gave it its own ScreenGui
-- and had to set IgnoreGuiInset on both so their coordinate systems lined up, and
-- sharing one screen removes that whole class of off-by-inset bugs plus lets
-- core/PanelPlacement compare the two rectangles directly.
-- The rows are read-outs, not bound controls: they refresh on a timer, because what
-- they show (frame rate, memory, per-second strength) is computed rather than stored.

local Format = require("core/Format")
local PanelPlacement = require("core/PanelPlacement")
local PlayerStats = require("game/PlayerStats")

local InfoWindow = {}
InfoWindow.__index = InfoWindow

local WIDTH = 320
local HEIGHT = 470
local MINIMIZED_HEIGHT = 36
-- Drag-to-resize bounds, matching V1007's grip.
local MIN_WIDTH = 240
local MAX_WIDTH = 1200
local MIN_HEIGHT = 160
local MAX_HEIGHT = 1200
-- 0.2 s was 5 refreshes a second, each walking the leaderboard and formatting a
-- dozen labels. 0.3 s is still visually instant and takes a third of that work
-- out of the frame budget.
local REFRESH_SECONDS = 0.3
-- How far past the screen edge the panel may be pulled while dragging. Enough
-- to feel like a rubber band, small enough that it never hides the title bar.
local DRAG_OVER = 48
-- Bounce time for the spring back (`InfoWindow.clampOnScreen`).
local BOUNCE_SECONDS = 0.24

local ROWS = {
	{ key = "strength", label = "力量" },
	{ key = "strengthDelta", label = "力量增量" },
	{ key = "perSec", label = "每秒增长" },
	{ key = "perHour", label = "每小时预计" },
	{ key = "gems", label = "宝石" },
	{ key = "durability", label = "耐力" },
	{ key = "rebirths", label = "重生" },
	{ key = "rebirthRate", label = "重生 / 小时" },
	{ key = "rebPredict", label = "重生预测" },
	{ key = "petRep", label = "反复 %" },
	{ key = "ultRep", label = "终极反复 %" },
	{ key = "passRep", label = "通行证" },
	{ key = "speedMul", label = "综合速度" },
	{ key = "rebMul", label = "重生倍率" },
	{ key = "fpsRow", label = "帧率" },
	{ key = "pingRow", label = "网络延迟" },
	{ key = "memRow", label = "内存占用" },
	{ key = "uptimeRow", label = "运行时长" },
	{ key = "tpRow", label = "被拉回 / 重试" },
}

local function screenSize()
	local camera = Workspace.CurrentCamera
	return (camera and camera.ViewportSize) or Vector2.new(1920, 1080)
end

-- The read-out number formatter. `uiState.formatNum` USED TO HAVE NO READER AT ALL:
-- the settings page offered "数字格式化显示（1.000K）" and flipping it changed the
-- checkbox and nothing else. V1007 read the same flag in its `Core.fmt`, so off means
-- the plain rounded integer and on means the abbreviated suffix form. Read through the
-- store rather than captured at build, because the toggle is on a different page and the
-- panel refreshes on a timer anyway -- no subscription to maintain.
local function number(self, value)
	if self.store:get("uiState.formatNum") == false then
		return Format.number(value, false)
	end
	return Format.number(value)
end

function InfoWindow.new(context)
	local self = setmetatable({
		store = context.store,
		kit = context.kit,
		shell = context.shell,
		services = context.services or {},
		rows = {},
		viewing = nil,
		visible = false,
		-- The main window's SHAPE, not a pre-computed "hide me" boolean: keeping the
		-- mode (rather than the answer) lets the setting below be flipped while the
		-- window is already collapsed, and keeps the two questions separate --
		-- `visible` is the user's intent, `shellMode` is what the main window is doing.
		shellMode = "window",
		lastRefresh = 0,
		-- Which show/hide animation is the CURRENT one: both hand geometry back to
		-- `place()` from a non-cancellable `kit:delay` (0.32 s / 0.24 s), so a quick
		-- close-then-open let the OLDER chain run last and stomp the newer animation's
		-- anchor and size -- one visible snap per fast toggle. `Shell.morph` guards
		-- itself the same way with `morphSeq`.
		animSeq = 0,
	}, InfoWindow)
	return self
end

-- The panel's BASE size, in unscaled units; `uiState.infoScale` is applied on top of
-- it by the UIScale. A saved size is honoured here, which is what makes the
-- drag-to-resize grip below persist across sessions -- the refactor kept the schema key
-- (`uiState.savedInfoSize`) but never wrote or read it, so a resized panel always came
-- back at the default size.
function InfoWindow.loadBaseSize(self)
	local saved = self.store:get("uiState.savedInfoSize")
	if type(saved) == "table" then
		local w = tonumber(saved.xo)
		local h = tonumber(saved.yo)
		if w ~= nil and h ~= nil then
			self.baseWidth = math.clamp(w, MIN_WIDTH, MAX_WIDTH)
			self.baseHeight = math.clamp(h, MIN_HEIGHT, MAX_HEIGHT)
			return
		end
	end
	self.baseWidth = WIDTH
	self.baseHeight = HEIGHT
end

function InfoWindow.applyBaseSize(self)
	if self.frame == nil then
		return
	end
	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	self.frame.Size = UDim2.fromOffset(self.baseWidth, height)
end

function InfoWindow.saveBaseSize(self)
	self.store:set("uiState.savedInfoSize", {
		xs = 0,
		xo = math.floor(self.baseWidth),
		ys = 0,
		yo = math.floor(self.baseHeight),
	})
end

function InfoWindow.build(self)
	local kit = self.kit
	local screen = self.shell:screenGui()

	InfoWindow.loadBaseSize(self)

	local frame = kit:instance("Frame", {
		Name = "InfoWindow",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(self.baseWidth, self.baseHeight),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 600,
		Active = true,
		-- Required, or minimising does nothing visible: collapsing tweens the frame's
		-- HEIGHT to MINIMIZED_HEIGHT (36), and a Frame does NOT clip its descendants by
		-- default, so every child below that line stayed rendered -- "最小化之后服务器
		-- 信息、Place ID、查看自己还在". V1007 set this on the equivalent frame.
		ClipsDescendants = true,
	}, screen)
	kit:corner(frame, 10)
	kit:stroke(frame, kit:color("Border"), 1.2, 0)
	kit:shadow(frame, 10, 0.9)
	self.frame = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = frame
	self.scale = scale

	local bar = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 601,
	}, frame)
	kit:corner(bar, 10)
	self.bar = bar

	kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = "实时信息",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 602,
	}, bar)

	local function barButton(text, offset, role, textRole)
		local button = kit:instance("TextButton", {
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, offset, 0.5, -12),
			BackgroundColor3 = kit:color(role),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = kit:color(textRole or "TextPrimary"),
			TextSize = 13,
			ZIndex = 602,
		}, bar)
		kit:corner(button, 6)
		kit:animate(button, kit:color(role))
		return button
	end

	local minimize = barButton("—", -62, "White")
	self.minimizeButton = minimize
	local close = barButton("✕", -34, "Red", "White")

	kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.GothamMedium,
		Text = "服务器：" .. string.sub(game.JobId or "", 1, 22),
		TextColor3 = kit:color("TextSecond"),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 602,
	}, frame)

	kit:instance("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 0, 16),
		Font = Enum.Font.GothamMedium,
		Text = "Place ID：" .. tostring(game.PlaceId),
		TextColor3 = kit:color("TextSecond"),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 602,
	}, frame)

	local playerButton = kit:instance("TextButton", {
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 0, 30),
		BackgroundColor3 = kit:color("BgSoft"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "查看：自己",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 13,
		ZIndex = 602,
	}, frame)
	kit:corner(playerButton, 6)
	kit:animate(playerButton, kit:color("BgSoft"))
	self.playerButton = playerButton

	-- The player picker list. The button used to only CYCLE through the server's
	-- players; V1007 opened a list showing every player with strength, rebirths and
	-- DisplayName so one could be picked -- cycling cannot show who is available.
	local listFrame = kit:instance("ScrollingFrame", {
		Name = "PlayerList",
		Position = UDim2.fromOffset(12, 112),
		Size = UDim2.new(1, -24, 0, 200),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = kit:color("TextMuted"),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		ZIndex = 620,
	}, frame)
	kit:corner(listFrame, 6)
	kit:stroke(listFrame, kit:color("Border"), 1, 0)
	kit:pad(listFrame, 5, 5, 5, 5)
	kit:list(listFrame, 3)
	self.listFrame = listFrame

	local data = kit:instance("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 114),
		Size = UDim2.new(1, 0, 1, -114),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = kit:color("TextMuted"),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 602,
	}, frame)
	kit:pad(data, 8, 10, 12, 12)
	kit:list(data, 4)

	for index, spec in ipairs(ROWS) do
		local row = kit:instance("Frame", {
			Size = UDim2.new(1, 0, 0, 21),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, data)
		kit:instance("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0.55, 0, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = spec.label,
			TextColor3 = kit:color("TextSecond"),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, row)
		local value = kit:instance("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.55, 0, 0, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			Font = Enum.Font.GothamBold,
			Text = "-",
			TextColor3 = kit:color("TextPrimary"),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, row)
		self.rows[spec.key] = value
	end

-- Apply the size the user just picked, IN PLACE. The panel's own `Size` stays in
-- unscaled units and `self.scale` (a UIScale) is the only thing carrying
-- `uiState.infoScale`, so this writes the scale and then re-clamps the panel onto the
-- screen -- the frame's *rendered* size changed even though `Size` did not. Deliberately
-- NOT `place()`, which would also re-run the placement decision and slide the panel
-- sideways while the user is dragging the slider.
function InfoWindow.applyScale(self)
	if self.frame == nil or self.scale == nil then
		return
	end
	local factor = (tonumber(self.store:get("uiState.infoScale")) or 100) / 100
	self.scale.Scale = factor
	InfoWindow.clampOnScreen(self, false)
end

-- Put the panel fully back on screen ("触边回弹") and return where it landed. The drag
-- may leave it a little past an edge and this is the spring back; it returns the clamped
-- coordinates because the bounce is a TWEEN -- reading `frame.Position` straight after
-- starting it would persist the pre-bounce value. The bar's height is kept visible at
-- the top and left, so the drag handle can never end up outside the screen.
function InfoWindow.clampOnScreen(self, animate): (number, number)
	if self.frame == nil then
		return 0, 0
	end
	local screen = screenSize()
	local size = self.frame.AbsoluteSize
	local position = self.frame.Position
	local maxX = math.max(0, screen.X - size.X)
	local maxY = math.max(0, screen.Y - size.Y)
	local x = math.clamp(position.X.Offset, 0, maxX)
	local y = math.clamp(position.Y.Offset, 0, maxY)

	if animate and (x ~= position.X.Offset or y ~= position.Y.Offset) then
		self.kit:tween(self.frame, BOUNCE_SECONDS, {
			Position = UDim2.fromOffset(x, y),
		}, Enum.EasingStyle.Back)
	else
		self.frame.Position = UDim2.fromOffset(x, y)
	end
	return x, y
end

-- Drag by the title bar.
	local dragging = false
	local startInput = nil
	local startPosition = nil
	-- THE BUTTONS ARE EXEMPT, measured from the buttons themselves: this used to be a
	-- flat 80 px from the bar's right edge in unscaled units, while the buttons are laid
	-- out with offsets the UIScale multiplies -- above ~130% infoScale the minimise
	-- button's left edge fell outside that strip, so pressing it also armed a title-bar
	-- drag ("点击穿透") and the panel moved instead of collapsing. Reading the rendered
	-- rectangles is exact at every scale.
	local function onBarButton(position: Vector2): boolean
		for _, button in ipairs({ minimize, close }) do
			local okPosition, corner = pcall(function()
				return button.AbsolutePosition
			end)
			local okSize, size = pcall(function()
				return button.AbsoluteSize
			end)
			if okPosition and okSize then
				if position.X >= corner.X - 2 and position.X <= corner.X + size.X + 2
					and position.Y >= corner.Y - 2 and position.Y <= corner.Y + size.Y + 2 then
					return true
				end
			end
		end
		return false
	end
	kit:track(bar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if onBarButton(input.Position) then
			return
		end
		dragging = true
		startInput = input.Position
		startPosition = frame.Position
	end))
	kit:track(game:GetService("UserInputService").InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- RUBBER BAND AT THE EDGE ("触边回弹"): the panel used to follow the cursor
		-- anywhere including off the screen, and its title bar is the ONLY drag handle,
		-- so dragging it out of reach was unrecoverable. While dragging it may overshoot
		-- the edge by DRAG_OVER pixels (the "pull"); on release `clampOnScreen` springs
		-- it back fully inside with a Back tween, which is the bounce.
		local screen = screenSize()
		local size = frame.AbsoluteSize
		local looseX = math.max(0, screen.X - size.X)
		local looseY = math.max(0, screen.Y - size.Y)
		local delta = input.Position - startInput
		local x = math.clamp(startPosition.X.Offset + delta.X, -DRAG_OVER, looseX + DRAG_OVER)
		local y = math.clamp(startPosition.Y.Offset + delta.Y, -DRAG_OVER, looseY + DRAG_OVER)
		frame.Position = UDim2.fromOffset(x, y)
	end))
	kit:track(game:GetService("UserInputService").InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not dragging then
			return
		end
		dragging = false
		-- Bounce back INSIDE first, then persist what the bounce settled on (a
		-- tween is asynchronous, so the saved value comes from the clamp itself).
		local x, y = InfoWindow.clampOnScreen(self, true)
		self.store:set("uiState.savedInfo", { xs = 0, xo = x, ys = 0, yo = y })
	end))

	kit:track(close.MouseButton1Click:Connect(function()
		InfoWindow.hide(self)
		self.store:set("uiState.infoVisible", false)
	end))
	kit:track(minimize.MouseButton1Click:Connect(function()
		InfoWindow.toggleMinimized(self)
	end))

	kit:track(playerButton.MouseButton1Click:Connect(function()
		InfoWindow.togglePlayerList(self)
	end))

	-- Drag-to-resize grip (bottom-right corner). V1007 had this and the refactor dropped
	-- it, leaving "infoScale" as the only way to change the panel's size and no control
	-- for it at all. The grip adjusts the BASE size by the mouse delta divided by the
	-- scale, so the panel keeps up with the cursor at any `uiState.infoScale`.
	local grip = kit:instance("TextButton", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Text = "◢",
		TextColor3 = kit:color("TextMuted"),
		TextSize = 13,
		ZIndex = 5,
		Active = true,
	}, frame)
	self.grip = grip

	local resizing = false
	local resizeStart = nil
	local baseAtStart = nil

	kit:track(grip.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		resizing = true
		resizeStart = input.Position
		baseAtStart = { w = self.baseWidth, h = self.baseHeight }
	end))

	kit:track(game:GetService("UserInputService").InputChanged:Connect(function(input)
		if not resizing then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local factor = (self.store:get("uiState.infoScale") or 100) / 100
		if factor <= 0.01 then
			factor = 1
		end
		local delta = input.Position - resizeStart
		self.baseWidth = math.clamp(baseAtStart.w + delta.X / factor, MIN_WIDTH, MAX_WIDTH)
		self.baseHeight = math.clamp(baseAtStart.h + delta.Y / factor, MIN_HEIGHT, MAX_HEIGHT)
		InfoWindow.applyBaseSize(self)
	end))

	kit:track(game:GetService("UserInputService").InputEnded:Connect(function(input)
		if not resizing then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		resizing = false
		InfoWindow.saveBaseSize(self)
	end))

	-- Read-outs refresh on a timer rather than a frame connection.
	local timers = self.shell.timers
	if timers ~= nil then
		timers:every(os.clock(), REFRESH_SECONDS, function()
			if self.visible then
				InfoWindow.refresh(self)
			end
		end)
	end

	self.timers = timers

	-- Flipping "最小化时隐藏信息窗" while the main window is ALREADY collapsed has
	-- to take effect immediately; without this the setting would only apply on
	-- the next shape change.
	kit:track(self.store:subscribe("uiState.infoHideWithShell", function()
		InfoWindow.applyVisibility(self)
	end))

	-- THE SIZE SLIDERS, which had NO listener at all: `uiState.infoScale` was read in
	-- exactly one place -- inside `place()` -- so changing it did nothing until the panel
	-- was hidden and shown again ("信息窗大小调节无效"). Both writers are covered: the
	-- settings slider (`infoScale`, a multiplier) and the panel's own drag grip
	-- (`savedInfoSize`, a pixel size).
	kit:track(self.store:subscribe("uiState.infoScale", function()
		InfoWindow.applyScale(self)
	end))
	kit:track(self.store:subscribe("uiState.savedInfoSize", function()
		InfoWindow.loadBaseSize(self)
		InfoWindow.applyBaseSize(self)
		InfoWindow.clampOnScreen(self, false)
	end))

	-- Honour a visibility request that arrived BEFORE the frame existed. main.luau
	-- subscribes to `uiState.infoVisible` and calls `show()` before `build()` runs, and
	-- every method guards on `self.frame == nil`, so that early call set the flags and
	-- changed nothing -- the frame was then created with `Visible = false` and left that
	-- way, so the panel only appeared if the user toggled the switch a second time.
	-- Re-applying here makes the build order irrelevant.
	if self.visible then
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
		InfoWindow.applyVisibility(self)
		InfoWindow.animateIn(self)
	end
	return frame
end

-- The screen, but only when it can be trusted. `screenSize` falls back to 1920x1080
-- without a camera, and the camera really can be nil for a moment during a rejoin --
-- placing the panel against a GUESSED screen is how it ended up off-screen ("有概率的
-- 时候我重进游戏，那个实时信息面板它老是飘到屏幕外去"). So the fallback is only used
-- while the panel is being BUILT; once it exists, a missing camera means "keep the
-- position you have".
local function usableScreen(self)
	local viewport = nil
	if self.shell ~= nil and self.shell.viewport ~= nil then
		local ok, value = pcall(function()
			return self.shell:viewport()
		end)
		if ok and value ~= nil then
			viewport = value
		end
	end
	if viewport == nil then
		return nil
	end
	if type(viewport.X) ~= "number" or type(viewport.Y) ~= "number" then
		return nil
	end
	return viewport
end

-- Is this screen point inside the panel? The shell asks before starting a drag of the
-- MAIN window, because the panel floats over it: a press that lands on the panel must
-- move the panel, not both ("如果实时信息面板与主面板的标题栏重叠，拖动它会同时拖动主面板，
-- 这是点击穿透问题"). Roblox input routing alone cannot answer reliably here -- the panel
-- is a sibling of the main frame, and a press inside a non-Active child never reaches
-- the panel's own handler.
function InfoWindow.overRect(self, x, y): boolean
	local frame = self.frame
	if frame == nil or frame.Visible ~= true then
		return false
	end
	-- A PANEL THAT IS NOT DRAWN MUST NOT EAT THE CURSOR: `animateIn` starts from
	-- `BackgroundTransparency = 1` and `animateOut` tweens back to it, but the guard used
	-- to answer "mine" for the whole rendered rectangle the entire time, so during the pop
	-- and the suck-in presses on the main window's title bar were silently swallowed by
	-- an invisible panel.
	local okTransparency, transparency = pcall(function()
		return frame.BackgroundTransparency
	end)
	if okTransparency and type(transparency) == "number" and transparency >= 1 then
		return false
	end
	local okPosition, position = pcall(function()
		return frame.AbsolutePosition
	end)
	local okSize, size = pcall(function()
		return frame.AbsoluteSize
	end)
	if not okPosition or not okSize then
		return false
	end
	if type(x) ~= "number" or type(y) ~= "number" then
		return false
	end
	return x >= position.X and x <= position.X + size.X
		and y >= position.Y and y <= position.Y + size.Y
end

-- Put the panel somewhere that does not cover the main window. The decision is
-- core/PanelPlacement; this only gathers the rectangles. The main window's rect comes
-- from `Shell.mainRect` -- the geometry the shell COMPUTED -- rather than from
-- `main.AbsolutePosition/AbsoluteSize`: the live values are mid-tween for most of the
-- first second of a session and a placement decided from a rectangle the window was only
-- passing through is not reproducible, so the same saved position resolved to a different
-- side every reload (the reported "重进后位置异常位移").
function InfoWindow.place(self)
	local screen = usableScreen(self)
	if screen == nil then
		-- No trustworthy screen: keep the panel where it is rather than push it to a
		-- coordinate computed from a guessed viewport. `self.placed` is dropped too -- it
		-- described a rectangle resolved against the PREVIOUS session's viewport, and
		-- `animateIn` prefers it over the live rectangle, so a rejoin (camera not up yet)
		-- animated the panel toward a place that no longer existed. The entrance now falls
		-- back to the frame's own position, which is always real.
		self.placed = nil
		return nil
	end
	local main = self.shell.main
	local mainRect = nil
	if main ~= nil and main.Visible and not self.shell.pill then
		if self.shell.mainRect ~= nil then
			mainRect = self.shell:mainRect()
		end
	end

	local saved = self.store:get("uiState.savedInfo")
	local preferred = { x = screen.X - WIDTH - 40, y = screen.Y - HEIGHT - 40 }
	if type(saved) == "table" then
		preferred = {
			x = (saved.xs or 0) * screen.X + (saved.xo or 0),
			y = (saved.ys or 0) * screen.Y + (saved.yo or 0),
		}
	end

	local factor = (self.store:get("uiState.infoScale") or 100) / 100
	local unscaledHeight = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	local result = PanelPlacement.resolve({
		screen = { w = screen.X, h = screen.Y },
		-- The placement rectangle has to describe what is actually on screen,
		-- which is the unscaled size times the UIScale.
		panel = { w = self.baseWidth * factor, h = unscaledHeight * factor },
		main = mainRect,
		preferred = preferred,
	})

	self.frame.Position = UDim2.fromOffset(result.x, result.y)
	self.scale.Scale = factor
	-- Remember what was just placed: `animateIn` grows the panel out of the main window
	-- and has to end on exactly this rectangle, so the geometry is computed ONCE (by
	-- PanelPlacement) rather than derived a second time, incorrectly.
	self.placed = {
		x = result.x,
		y = result.y,
		w = self.baseWidth * factor,
		h = unscaledHeight * factor,
	}
	return result
end

-- The panel's own visibility, as the user set it. Kept separate from `frame.Visible`
-- because the two are different questions and conflating them is a bug: `visible` is
-- "the user wants this open", while the frame is visible only when the user wants it AND
-- (if the setting says so) the main window is not collapsed -- writing the user's intent
-- over the top of a collapse would reopen the panel on top of a minimised window.
-- Put the panel back in its default spot, and PERSIST THAT SPOT ("重置位置实时信息窗口
-- 它位置会乱跳"). `Shell.resetLayout` wrote `uiState.savedInfo = { xs = 0.5, xo = 0,
-- ys = 0.5, yo = 0 }` -- a SCALE-based centre -- while this panel always stores ABSOLUTE
-- offsets, so `place()` read the centre as a preferred position, PanelPlacement moved the
-- panel off the main window, the panel's own next save rewrote the other shape and the
-- next reset moved it somewhere else again. The panel therefore owns its own reset: one
-- shape (absolute), one place (the same default `place()` falls back to).
function InfoWindow.resetPlacement(self)
	InfoWindow.loadBaseSize(self)
	InfoWindow.applyBaseSize(self)

	local screen = usableScreen(self) or screenSize()
	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	self.store:set("uiState.savedInfo", {
		xs = 0,
		xo = math.max(0, math.floor(screen.X - self.baseWidth - 40)),
		ys = 0,
		yo = math.max(0, math.floor(screen.Y - height - 40)),
	})
	InfoWindow.place(self)
end

function InfoWindow.applyVisibility(self)
	if self.frame == nil then
		return
	end
	-- DEFAULT: the panel SURVIVES minimising and the pill -- the user's wording is the
	-- spec ("does not disappear with the main panel's minimise/pill, unless the player
	-- closed it themselves"), and collapsing the main window is how you get it out of the
	-- way while KEEPING the read-outs. The opposite is one switch away
	-- (`uiState.infoHideWithShell`).
	local collapsed = self.shellMode == "minimized" or self.shellMode == "pill"
	local hidden = collapsed and self.store:get("uiState.infoHideWithShell") == true
	local open = self.visible and not hidden
	if self.frame.Visible == open then
		return
	end
	self.frame.Visible = open
	if open and self.timers ~= nil then
		InfoWindow.refresh(self)
	end
end

-- Called by the Shell whenever the main window changes shape (minimise, pill).
-- Collapsing hides the panel only when the setting says it should, and the window mode
-- restores it if the user had it open: minimise then restore must not conjure a panel the
-- user had closed, and must not lose one they had open.
function InfoWindow.setShellMode(self, mode)
	local next = if mode == "minimized" or mode == "pill" then mode else "window"
	if self.shellMode == next then
		return
	end
	self.shellMode = next
	InfoWindow.applyVisibility(self)
end

function InfoWindow.show(self)
	self.visible = true
	InfoWindow.applyVisibility(self)
	if self.frame == nil then
		return
	end
	if self.anim == "in" then
		--[[
			ALREADY OPENING. `show()` runs twice per open: the button calls it and
			then writes `uiState.infoVisible`, and main.luau's subscription calls
			it back. The second call must not re-place the frame: the entrance has
			the frame centre-anchored at 20% size, and `place()` writes TOP-LEFT
			coordinates -- the panel jumped by half its size and then snapped back
			when the tween landed.
		]]
		InfoWindow.refresh(self)
		return
	end
	-- Re-assert the base size: `place()` only writes the scale, so a panel that
	-- was resized or minimised while hidden must be restored to its own size.
	InfoWindow.applyBaseSize(self)
	InfoWindow.place(self)
	InfoWindow.refresh(self)
	InfoWindow.animateIn(self)
	self.store:set("uiState.infoVisible", true)
end

function InfoWindow.hide(self)
	self.visible = false
	InfoWindow.animateOut(self)
	self.store:set("uiState.infoVisible", false)
end

-- Entrance / exit motion for the panel. Both were instant next to a main window that
-- morphs over 0.22 s and page cards that stagger in, which is why the panel read as
-- pasted on. The transform is the panel's UIScale, NOT its Size: Size carries the user's
-- saved size and `place()` owns the scale factor, so growing Size here would fight both
-- (the same trap that once made the panel come back at factor squared). A tween on a
-- hidden object still runs, so the exit animates the SAME scale down and only then flips
-- Visible -- and the delayed hide re-checks `visible`, so a rapid off/on is not hidden by
-- an exit that is no longer current.
-- Where the panel collapses INTO: the main window's centre. The panel shares the
-- ScreenGui with the main window, so "fuse back into the main panel" is a real motion
-- here rather than a fade; V1007 did exactly this and the refactor reduced it to a
-- visibility flip, which is why the close read as "只是缩小了一点" with no merge.
function InfoWindow.mergeTarget(self)
	local main = self.shell ~= nil and self.shell.main or nil
	if main == nil then
		return nil
	end
	local ok, position = pcall(function()
		return main.AbsolutePosition
	end)
	local okSize, size = pcall(function()
		return main.AbsoluteSize
	end)
	if not ok or not okSize then
		return nil
	end
	-- Absolute screen coords. The frame's own Position is 0,0 and its parent is
	-- the ScreenGui, so screen coords and frame coords coincide.
	return Vector2.new(position.X + size.X / 2, position.Y + size.Y / 2)
end

-- Entrance / exit motion: show grows OUT of the main window's centre with a Back
-- (overshoot) ease, hide shrinks back INTO that same point so closing reads as fusing
-- back in. WHAT WAS WRONG ("它会在原地跳一下，然后突然卡到目标位置去"): the panel's
-- AnchorPoint is the CENTRE for this motion, but the tween's end Position was computed as
-- if it were the TOP-LEFT corner, so it animated to a spot half its size up and to the
-- left and the delayed step snapped it to the real place. The end position is now the
-- CENTRE of the rectangle `place()` actually resolved; the size stays in UNSCALED units
-- (the UIScale multiplies it) while the position is in rendered pixels -- mixing those
-- two was the other half of the error.

-- FADE THE CONTENTS, NOT JUST THE FRAME: the entrance only faded the frame's own
-- `BackgroundTransparency`, so the bar, the title and every button stayed fully opaque
-- while the body was invisible at 20% size ("吸附动画的时候里面的字和按钮是硬的"). Each
-- descendant is tweened through every transparency channel it actually has, and the frame
-- is skipped -- its own tween owns that channel. `Active` is switched off with the contents
-- so the invisible panel stops swallowing presses for the 0.2-0.3 s it is not drawn.
local function collectFade(frame, includeFrame)
	local entries = {}
	if frame == nil then
		return entries
	end
	local ok, descendants = pcall(function()
		return frame:GetDescendants()
	end)
	if not ok or type(descendants) ~= "table" then
		return entries
	end
	for _, child in ipairs(descendants) do
		if child ~= frame or includeFrame then
			local fields = {}
			if child:IsA("GuiObject") then
				fields.background = child.BackgroundTransparency
			end
			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				fields.text = child.TextTransparency
			end
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				fields.image = child.ImageTransparency
			end
			if child:IsA("TextButton") or child:IsA("ImageButton") then
				fields.active = child.Active
			end
			if next(fields) ~= nil then
				table.insert(entries, { item = child, fields = fields })
			end
		end
	end
	return entries
end

-- The rectangle the entrance animation should end on: `self.placed`, the layout's answer
-- from the last successful `place()`, else the frame's own rendered rectangle unless the
-- panel is hidden (then it is not drawn at all). Returns nil when neither can be trusted,
-- and `animateIn` falls back to the merge point.
function InfoWindow.placedRect(self)
	if self.placed ~= nil and type(self.placed.x) == "number" then
		return self.placed
	end
	if self.frame == nil or self.frame.Visible ~= true then
		return nil
	end
	local okPosition, position = pcall(function()
		return self.frame.AbsolutePosition
	end)
	local okSize, size = pcall(function()
		return self.frame.AbsoluteSize
	end)
	if not okPosition or not okSize then
		return nil
	end
	return { x = position.X, y = position.Y, w = size.X, h = size.Y }
end

function InfoWindow.animateIn(self)
	if self.frame == nil or self.scale == nil then
		return
	end
	-- ONE ENTRANCE PER OPEN: `show()` is called from the toggle button AND from the store
	-- subscription in main.luau, so every open ran this twice, and the second run re-read
	-- AbsolutePosition after the first had already re-anchored to the centre -- the panel
	-- visibly jumped and replayed the pop ("信息面板的弹出/吸入主面板的动画异常"). The flag is
	-- cleared when the tween lands so a later open animates normally.
	if self.anim == "in" then
		return
	end
	self.anim = "in"
	self.animSeq = (self.animSeq or 0) + 1
	local seq = self.animSeq
	local merge = InfoWindow.mergeTarget(self)
	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight

	if merge == nil then
		-- Nothing to grow out of: a plain pop. It scales the EXISTING factor down and
		-- back up rather than writing 0.94 and tweening to 1 -- the second form threw
		-- away the `uiState.infoScale` factor `place()` had just applied, so the panel
		-- opened at 100% and then jumped to the user's size.
		local factor = tonumber(self.scale.Scale) or 1
		self.scale.Scale = factor * 0.94
		self.kit:tween(self.scale, 0.26, { Scale = factor }, Enum.EasingStyle.Back)
		self.kit:delay(0.28, function()
			if self.anim == "in" then
				self.anim = nil
			end
		end)
		return
	end

	-- STALE-RECT GUARD: `self.placed` is the layout's answer from the last successful
	-- `place()` and `place()` returns nil with no camera, but a rectangle from a previous
	-- viewport is still worse than the live one -- if the panel already exists on screen,
	-- its own rendered rect is the truth. Only when the frame cannot answer either (not
	-- built, hidden itself) fall back to the merge point.
	local placed = InfoWindow.placedRect(self)
	local targetCentreX = if placed ~= nil then placed.x + placed.w / 2 else merge.X
	local targetCentreY = if placed ~= nil then placed.y + placed.h / 2 else merge.Y

	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.frame.Position = UDim2.fromOffset(merge.X, merge.Y)
	self.frame.Size = UDim2.fromOffset(self.baseWidth * 0.2, height * 0.2)
	self.frame.BackgroundTransparency = 1

	local fade = collectFade(self.frame, false)
	for _, entry in ipairs(fade) do
		local fields = entry.fields
		if fields.background ~= nil then
			entry.item.BackgroundTransparency = 1
		end
		if fields.text ~= nil then
			entry.item.TextTransparency = 1
		end
		if fields.image ~= nil then
			entry.item.ImageTransparency = 1
		end
		if fields.active ~= nil then
			entry.item.Active = false
		end
	end
	task.spawn(function()
		for _, entry in ipairs(fade) do
			local fields = entry.fields
			local goal = {}
			if fields.background ~= nil then
				goal.BackgroundTransparency = fields.background
			end
			if fields.text ~= nil then
				goal.TextTransparency = fields.text
			end
			if fields.image ~= nil then
				goal.ImageTransparency = fields.image
			end
			self.kit:tween(entry.item, 0.22, goal)
		end
		for _, entry in ipairs(fade) do
			if entry.fields.active ~= nil then
				entry.item.Active = entry.fields.active
			end
		end
	end)

	self.kit:tween(self.frame, 0.3, {
		Position = UDim2.fromOffset(targetCentreX, targetCentreY),
		Size = UDim2.fromOffset(self.baseWidth, height),
		BackgroundTransparency = 0,
	}, Enum.EasingStyle.Back)
	self.kit:delay(0.32, function()
		if self.frame == nil or seq ~= self.animSeq then
			return
		end
		self.anim = nil
		-- Hand geometry back to the layout owner. This is now a NO-OP in
		-- practice: the tween already landed on the resolved rectangle.
		self.frame.AnchorPoint = Vector2.new(0, 0)
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
	end)
end

function InfoWindow.animateOut(self)
	if self.frame == nil or self.scale == nil or self.frame.Visible ~= true then
		-- Already hidden (e.g. the main window is collapsed): no motion to run,
		-- just make the state consistent.
		InfoWindow.applyVisibility(self)
		return
	end
	-- Same double-call as `animateIn`: `hide()` writes the store and the
	-- subscription calls it back. Replaying the exit re-anchored an already
	-- centre-anchored frame, which is what threw the panel half its size.
	if self.anim == "out" then
		return
	end
	self.anim = "out"
	self.animSeq = (self.animSeq or 0) + 1
	local seq = self.animSeq
	local merge = InfoWindow.mergeTarget(self)
	if merge == nil then
		self.anim = nil
		InfoWindow.applyVisibility(self)
		return
	end

	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	-- THE CENTRE, CAPTURED BEFORE THE ANCHOR MOVES: `AbsolutePosition` is derived from
	-- the CURRENT AnchorPoint, so reading it after writing (0.5, 0.5) returns the old
	-- top-left minus half the size, and adding half the size back therefore yields the old
	-- TOP-LEFT, not the old centre -- written back as a centre-anchored Position the panel
	-- jumped up and left by half its own size the instant it started closing
	-- ("弹出/吸入主面板动画异常"). Capture first, then re-anchor.
	local absolute = self.frame.AbsolutePosition
	local rendered = self.frame.AbsoluteSize
	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.frame.Position = UDim2.fromOffset(absolute.X + rendered.X / 2, absolute.Y + rendered.Y / 2)

	-- The contents fade out with the body, and stop taking input immediately:
	-- an invisible panel that still swallows presses is the click-through bug.
	local fade = collectFade(self.frame, false)
	for _, entry in ipairs(fade) do
		local fields = entry.fields
		if fields.active ~= nil then
			entry.item.Active = false
		end
		local goal = {}
		if fields.background ~= nil and fields.background < 1 then
			goal.BackgroundTransparency = 1
		end
		if fields.text ~= nil and fields.text < 1 then
			goal.TextTransparency = 1
		end
		if fields.image ~= nil and fields.image < 1 then
			goal.ImageTransparency = 1
		end
		if next(goal) ~= nil then
			self.kit:tween(entry.item, 0.18, goal)
		end
	end

	self.kit:tween(self.frame, 0.22, {
		Position = UDim2.fromOffset(merge.X, merge.Y),
		Size = UDim2.fromOffset(self.baseWidth * 0.2, height * 0.2),
		BackgroundTransparency = 1,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	self.kit:delay(0.24, function()
		if self.frame == nil or seq ~= self.animSeq then
			return
		end
		self.frame.AnchorPoint = Vector2.new(0, 0)
		InfoWindow.applyVisibility(self)
		-- Restore the real geometry for the next show, which animates from
		-- scratch -- leaving the 20%-size here would make the reopen jump.
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
		-- The contents have to come back too: the next entrance captures the
		-- ORIGINAL transparencies, so leaving them at 1 would fade them to 1.
		for _, entry in ipairs(fade) do
			local fields = entry.fields
			if fields.background ~= nil then
				entry.item.BackgroundTransparency = fields.background
			end
			if fields.text ~= nil then
				entry.item.TextTransparency = fields.text
			end
			if fields.image ~= nil then
				entry.item.ImageTransparency = fields.image
			end
			if fields.active ~= nil then
				entry.item.Active = fields.active
			end
		end
		self.anim = nil
	end)
end

function InfoWindow.toggle(self)
	if self.visible then
		InfoWindow.hide(self)
	else
		InfoWindow.show(self)
	end
end

-- Collapse / expand the panel. `Size` is kept in UNSCALED units and `scale` (a UIScale)
-- is the only thing that applies `uiState.infoScale`. The previous version pre-multiplied
-- the size here AND reset the scale to 1, while `place()` set the scale to `factor` on
-- every show: minimise once, reopen, and both applied -- the panel came back at factor
-- squared (250% at a 160% setting) and grew a little on every toggle.
function InfoWindow.toggleMinimized(self)
	if self.frame == nil then
		return
	end
	self.minimized = not self.minimized
	local target = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	-- THE GLYPH FLIPS, like the main window's does. It never did, so the panel's one
	-- collapse button read "—" in both states ("最小化按钮与最大化按钮图标相同"). Shell does
	-- exactly this in `Shell.setMinimized`.
	if self.minimizeButton ~= nil then
		self.minimizeButton.Text = if self.minimized then "+" else "—"
	end
	-- RE-CLAMP FOR THE SIZE WE ARE ABOUT TO BECOME: the panel is clamped against its
	-- CURRENT rendered size when a drag ends, so a minimised panel can legitimately be
	-- parked at the bottom edge -- and expanding it then grew those ~430 extra pixels
	-- straight off-screen with nothing to pull it back ("最小化信息面板后拖到屏幕边缘再最大化，
	-- UI 出现在屏幕外"). Clamp against the TARGET height before the tween, so the expanded
	-- panel is already inside the viewport when it starts growing.
	local factor = (tonumber(self.store:get("uiState.infoScale")) or 100) / 100
	-- NO GUESSED VIEWPORT HERE: `screenSize()` invents 1920x1080 when there is no camera,
	-- and `place()` deliberately refuses to act on that guess -- so clamping against it
	-- wrote a position the layout owner would never have chosen (on a 1280x720 display a
	-- max-Y derived from 1080 parks the panel below the bottom edge). When the screen
	-- cannot be trusted the position is left alone; the entering camera makes `place()`
	-- clamp it.
	local screen = usableScreen(self)
	if screen ~= nil then
		local size = self.frame.AbsoluteSize or Vector2.new(0, 0)
		local current = self.frame.Position
		local maxX = math.max(0, screen.X - size.X)
		local maxY = math.max(0, screen.Y - target * factor)
		local x = math.clamp(current.X.Offset, 0, maxX)
		local y = math.clamp(current.Y.Offset, 0, maxY)
		if x ~= current.X.Offset or y ~= current.Y.Offset then
			self.frame.Position = UDim2.fromOffset(x, y)
			self.store:set("uiState.savedInfo", { xs = 0, xo = x, ys = 0, yo = y })
		end
	end
	-- Animate the collapse rather than snapping it: the main window morphs over 0.22 s,
	-- so an instant jump beside it looked like a glitch. `self.scale` is deliberately
	-- untouched (place() owns it), which is what keeps this from compounding on reopen.
	self.kit:tween(self.frame, 0.18, { Size = UDim2.fromOffset(self.baseWidth, target) },
		Enum.EasingStyle.Quint)
end

-- Open / close the player picker and fill it with everyone in the server. Replaces a
-- single cycling button: cycling cannot show who is available and reaching the Nth player
-- takes N clicks -- V1007 shipped the list, and this brings it back with the same
-- information (DisplayName, strength, rebirths).
function InfoWindow.togglePlayerList(self)
	local listFrame = self.listFrame
	if listFrame == nil then
		return
	end
	if listFrame.Visible then
		listFrame.Visible = false
		return
	end

	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local Players = game:GetService("Players")
	local me = Players.LocalPlayer
	local entries = {}
	if me ~= nil then
		table.insert(entries, me)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= me then
			table.insert(entries, player)
		end
	end

	for index, player in ipairs(entries) do
		local display = player.DisplayName
		local name = player.Name
		local head = if type(display) == "string" and display ~= "" and display ~= name
			then string.format("%s (@%s)", display, name)
			else name
		if player == me then
			head = head .. "  ⭐"
		end

		local row = self.kit:instance("TextButton", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundColor3 = self.kit:color("BgSoft"),
			BorderSizePixel = 0,
			Text = "",
			LayoutOrder = index,
			AutoButtonColor = false,
			ZIndex = 621,
		}, listFrame)
		self.kit:corner(row, 6)

		self.kit:instance("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -16, 0, 20),
			Font = Enum.Font.GothamBold,
			Text = head,
			TextColor3 = self.kit:color("TextPrimary"),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 622,
		}, row)

		self.kit:instance("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 22),
			Size = UDim2.new(1, -16, 0, 18),
			Font = Enum.Font.GothamMedium,
			Text = string.format("重生 %s   力量 %s",
				Format.number(PlayerStats.value(player, "Rebirths")),
				Format.number(PlayerStats.value(player, "Strength"))),
			TextColor3 = self.kit:color("TextSecond"),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 622,
		}, row)

		self.kit:track(row.MouseButton1Click:Connect(function()
			InfoWindow.view(self, player)
		end))
	end

	listFrame.Visible = true
end

-- Point every read-out at one player.
function InfoWindow.view(self, player)
	if player == nil then
		return
	end
	self.viewing = player
	if self.playerButton ~= nil then
		local me = game:GetService("Players").LocalPlayer
		self.playerButton.Text = if player == me
			then "查看：自己"
			else "查看：" .. player.Name
	end
	if self.listFrame ~= nil then
		self.listFrame.Visible = false
	end
	InfoWindow.refresh(self)
end

function InfoWindow.setRow(self, key, text, color)
	local row = self.rows[key]
	if row == nil then
		return
	end
	row.Text = text
	if color ~= nil then
		row.TextColor3 = color
	end
end

-- One read-out row, with the colour chosen from the value. Naming the intermediate value
-- instead of inlining `if x > 0 then kit:color("Green") else ...` in every `setRow` keeps
-- the BUNDLED artifact under Luau's type-inference budget ("Code is too complex to
-- typecheck!" here plus 35 downstream findings, while `gate src` reported 0 errors).
local function row(self, key, text, condition, good, bad)
	if condition then
		InfoWindow.setRow(self, key, text, good)
	else
		InfoWindow.setRow(self, key, text, bad)
	end
end

function InfoWindow.refresh(self)
	local kit = self.kit
	local Players = game:GetService("Players")
	local me = Players.LocalPlayer
	if self.viewing == nil or self.viewing.Parent == nil then
		self.viewing = me
	end
	local target = self.viewing
	if target == nil then
		return
	end

	-- Annotated service handles: `self.services` is a plain table built in main.luau, so
	-- every field is `any` and each `metrics:reading()` is an unresolved call whose result
	-- type the checker must guess -- see the note on `row` above.
	local metrics: any = self.services.metrics
	local petMetrics: any = self.services.petMetrics
	local motion: any = self.services.motion

	local primary = kit:color("TextPrimary")
	local muted = kit:color("TextMuted")
	local green = kit:color("Green")
	local yellow = kit:color("Yellow")
	local red = kit:color("Red")

	local strength = PlayerStats.value(target, "Strength")
	local rebirths = PlayerStats.value(target, "Rebirths")
	InfoWindow.setRow(self, "strength", number(self, strength), primary)
	InfoWindow.setRow(self, "gems", number(self, PlayerStats.value(target, "Gems")), primary)
	InfoWindow.setRow(self, "durability", number(self, PlayerStats.value(target, "Durability")), primary)
	InfoWindow.setRow(self, "rebirths", number(self, rebirths), primary)

	local uptime = 0

	if target == me and metrics ~= nil then
		local reading = metrics:reading()
		local fps: number = reading.fps
		local memory: any = reading.memory
		-- THE ROW SHOWS THE WORST SAMPLE, NOT THE MEAN. `reading.ping` averages the last
		-- five one-second samples, which is exactly how a 1000 ms link reads as 200
		-- (`(1000 + 4 * 1) / 5 = 200`): "获取的 ping 是假的（实际 1000，显示 200）".
		-- core/Metrics keeps both numbers, holding the worst sample for a much longer
		-- window, and the row reports the worst -- what the player actually felt. A value
		-- from the client-side estimate is labelled "估算" rather than presented as truth.
		local ping: number = reading.pingWorst or reading.ping
		local estimated = reading.pingEstimated == true
		local fpsColor = muted
		if fps >= 50 then
			fpsColor = green
		elseif fps >= 25 then
			fpsColor = yellow
		else
			fpsColor = red
		end
		InfoWindow.setRow(self, "fpsRow", string.format("%.0f", fps), fpsColor)

		local pingText = "-"
		local pingColor = muted
		if ping > 0 then
			pingText = tostring(ping) .. " ms" .. if estimated then " ·估算" else ""
			if ping < 80 then
				pingColor = green
			elseif ping < 200 then
				pingColor = yellow
			else
				pingColor = red
			end
		end
		InfoWindow.setRow(self, "pingRow", pingText, pingColor)
		InfoWindow.setRow(self, "memRow", tostring(memory) .. " MB", primary)

		local uptimeFn: any = self.services.uptime
		uptime = if uptimeFn ~= nil then uptimeFn() else 0
		InfoWindow.setRow(self, "uptimeRow", Format.duration(uptime), primary)

		local hold: any = motion ~= nil and motion.hold or nil
		if hold ~= nil then
			local stats: any = hold.stats
			local pulled: number = stats.pulled
			local tpText = string.format("%d / %d", pulled, stats.retries)
			InfoWindow.setRow(self, "tpRow", tpText, if pulled > 0 then yellow else muted)
		end
	else
		for _, key in ipairs({ "fpsRow", "pingRow", "memRow", "uptimeRow", "tpRow" }) do
			InfoWindow.setRow(self, key, "-", muted)
		end
	end

	if target ~= me then
		-- Per-second figures only make sense for the local player.
		for _, key in ipairs({
			"strengthDelta", "perSec", "perHour", "rebirthRate", "rebPredict",
			"petRep", "ultRep", "passRep", "speedMul", "rebMul",
		}) do
			InfoWindow.setRow(self, key, "-", muted)
		end
		return
	end

	local strengthStats: any = nil
	if metrics ~= nil and metrics.strengthStats ~= nil then
		strengthStats = metrics:strengthStats()
	end
	if strengthStats ~= nil then
		local delta: number = strengthStats.delta or 0
		local perSec: number = strengthStats.perSec or 0
		row(self, "strengthDelta", Format.delta(delta), delta >= 0, green, red)
		row(self, "perSec", number(self, perSec), perSec > 0, green, muted)
		InfoWindow.setRow(self, "perHour", number(self, perSec * 3600), primary)
	end

	-- These three rows existed with labels and a "-" placeholder but nothing ever wrote to
	-- them -- the tracking behind them was dropped in the refactor. V1007 filled all three.
	if metrics ~= nil and metrics.rebirthStats ~= nil then
		-- Named `rebirthRates`, not `rebirths`: the count from `PlayerStats` is
		-- already in scope above, and shadowing it is a lint finding.
		local rebirthRates: any = metrics:rebirthStats()
		local perHour: number = rebirthRates.perHour or 0
		if perHour > 0 then
			InfoWindow.setRow(self, "rebirthRate", string.format("%.0f", perHour), green)
			InfoWindow.setRow(self, "rebPredict",
				string.format("+%s / %s / %s",
					Format.number(perHour * 24),
					Format.number(perHour * 24 * 7),
					Format.number(perHour * 24 * 30)),
				primary)
		else
			InfoWindow.setRow(self, "rebirthRate", "0", muted)
			InfoWindow.setRow(self, "rebPredict", "-", muted)
		end
	end
	if metrics ~= nil and metrics.rebirthMultiplier ~= nil then
		local multiplier: number = metrics:rebirthMultiplier()
		if multiplier >= 1000 then
			InfoWindow.setRow(self, "rebMul", string.format("%.1fK%%", multiplier / 1000), primary)
		elseif multiplier > 0 then
			InfoWindow.setRow(self, "rebMul", string.format("%d%%", multiplier), primary)
		else
			InfoWindow.setRow(self, "rebMul", "-", muted)
		end
	end

	if petMetrics ~= nil then
		local stats: any = petMetrics:stats()
		local result: any = stats.result
		local petPercent: number = result.petPercent
		local petCount: number = result.petCount
		local ultimatePercent: number = result.ultimatePercent
		local passNames: { string } = stats.passNames
		local passText = "无"
		if #passNames > 0 then
			passText = table.concat(passNames, ", ")
		end
		-- "N 只" is the number of pets actually WORN, not the number whose rep bonus could
		-- be read: `petCount` counts only equipped pets with a readable boost, so a pet
		-- whose perks are not published made this row under-report what the player is
		-- wearing ("12%（10 只）" with sixteen pets out). `equippedCount` is the honest
		-- denominator and the one the label promises.
		local charged = result.equippedCount or petCount
		InfoWindow.setRow(self, "petRep", string.format("%d%%  (%d 只)", petPercent, charged), primary)
		row(self, "ultRep", string.format("%d%%", ultimatePercent), ultimatePercent > 0, green, muted)
		row(self, "passRep", passText, #passNames > 0, green, muted)
		row(self, "speedMul", stats.label, result.uncapped == true, green, primary)
	end
end

return InfoWindow
end

__modules["ui/Announce"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- Announce -- the one-off notice shown on load.
-- Deliberately not part of the interface: a single card that must be dismissed
-- with the button (the backdrop does NOT close it, so it gets read). Nothing is
-- built at all when cfg.announce is off.

local Announce = {}

Announce.GROUP = "1029329039"

function Announce.show(kit, store)
	if store:get("cfg.announce") == false then
		return nil
	end

	local holder = kit:instance("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 1300,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, kit.screen)

	local card = kit:instance("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(400, 236),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		ZIndex = 1301,
		Active = true,
	}, holder)
	kit:corner(card, 14)
	kit:stroke(card, kit:color("Border"), 1.4, 0)
	kit:shadow(card, 14, 0.86)

	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.9
	cardScale.Parent = card

	local bar = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = kit:color("Accent"),
		BorderSizePixel = 0,
		ZIndex = 1302,
	}, card)
	kit:corner(bar, 2)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.fromOffset(20, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "免费脚本",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 1302,
	}, card)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -40, 0, 52),
		Position = UDim2.fromOffset(20, 52),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "本脚本为免费脚本，请勿付费购买、请勿倒卖。\n有问题或建议欢迎进群反馈。",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 1302,
	}, card)

	local groupBox = kit:instance("Frame", {
		Size = UDim2.new(1, -40, 0, 44),
		Position = UDim2.fromOffset(20, 112),
		BackgroundColor3 = kit:color("BgSoft"),
		BorderSizePixel = 0,
		ZIndex = 1302,
	}, card)
	kit:corner(groupBox, 10)

	kit:instance("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "脚本群号：" .. Announce.GROUP,
		TextColor3 = kit:color("Accent"),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 1303,
	}, groupBox)

	local copy = kit:instance("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(84, 30),
		BackgroundColor3 = kit:color("White"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "复制群号",
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 12,
		ZIndex = 1303,
	}, groupBox)
	kit:corner(copy, 8)
	kit:stroke(copy, kit:color("Border"), 1, 0)
	kit:animate(copy, kit:color("White"))

	kit:track(copy.MouseButton1Click:Connect(function()
		local ok = pcall(function()
			if type(setclipboard) == "function" then
				setclipboard(Announce.GROUP)
			end
		end)
		copy.Text = if ok then "已复制 ✓" else "复制失败"
	end))

	local confirm = kit:instance("TextButton", {
		Size = UDim2.new(1, -40, 0, 38),
		Position = UDim2.fromOffset(20, 172),
		BackgroundColor3 = kit:color("Green"),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "确定",
		TextColor3 = kit:color("White"),
		TextSize = 15,
		ZIndex = 1303,
		AutoButtonColor = false,
	}, card)
	kit:corner(confirm, 8)
	kit:animate(confirm, kit:color("Green"))

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		kit:tween(cardScale, 0.16, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		kit:tween(holder, 0.2, { BackgroundTransparency = 1 })
		kit:tween(card, 0.18, { BackgroundTransparency = 1 })
		for _, child in ipairs(card:GetDescendants()) do
			if child:IsA("TextLabel") then
				kit:tween(child, 0.14, { TextTransparency = 1 })
			elseif child:IsA("TextButton") then
				kit:tween(child, 0.14, { TextTransparency = 1, BackgroundTransparency = 1 })
			elseif child:IsA("Frame") then
				kit:tween(child, 0.16, { BackgroundTransparency = 1 })
			elseif child:IsA("UIStroke") then
				kit:tween(child, 0.16, { Transparency = 1 })
			end
		end
		-- Through the Kit's Timers (the runtime's), so destroy() cancels this
		-- pending teardown instead of running it against a destroyed GUI.
		kit:delay(0.24, function()
			pcall(function()
				holder:Destroy()
			end)
		end)
	end

	kit:track(confirm.MouseButton1Click:Connect(close))

	kit:tween(holder, 0.24, { BackgroundTransparency = 0.5 })
	kit:tween(cardScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)

	return { destroy = close }
end

return Announce
end

__modules["ui/Pages/Train"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The training page. Every control that has state declares a `path` into the
-- Store -- nothing here keeps or mirrors a value: the toggle writes the key, the
-- subscription repaints it, and a change made from anywhere else shows up here
-- on its own.

local MachinePlan = require("core/MachinePlan")

local Page = {}

Page.id = "train"
Page.label = "锻炼"

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local machineService = services.machine

	kit:section(page, "基本锻炼")
	local basics = kit:card(page)
	kit:toggle(basics, { label = "自动锻炼", path = "train.auto" })
	kit:toggle(basics, {
		label = "快速锻炼",
		path = "train.fast",
		hint = "与自动锻炼互斥；用很高的发包频率换取锻炼速度",
	})
	kit:input(basics, {
		label = "频率",
		path = "train.rate",
		min = 1,
		max = 2000,
		default = 20,
		hint = "每秒发包次数（1~2000）",
	})
	kit:divider(basics)

	-- A read-out, not a control: which pacing mode resolved, and to what.
	local rateLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "实际发包 -",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(basics),
	}, basics)
	shell:addUiTick(function()
		local rate = tonumber(kit.store:get("train.effRate")) or 0
		local source = tostring(kit.store:get("train.rateSource") or "")
		rateLabel.Text = string.format("实际发包 %d /s · 来源 %s", rate, source)
		rateLabel.TextColor3 = if rate > 0 then kit:color("Green") else kit:color("TextMuted")
	end)

	kit:section(page, "训练工具")
	local tools = kit:card(page)
	kit:toggle(tools, { label = "自动切换哑铃（L1）", path = "train.toolDumbbell" })
	kit:toggle(tools, { label = "自动切换俯卧撑（L2）", path = "train.toolPush" })
	kit:toggle(tools, { label = "自动切换倒立（L2）", path = "train.toolHand" })
	kit:toggle(tools, { label = "自动切换仰卧起坐（L2）", path = "train.toolSit" })
	kit:note(tools, "同时开启多个时固定优先 俯卧撑 → 倒立 → 仰卧起坐 → 哑铃，取第一个背包里有的；L2 不会因为开了哑铃就来回换。器械与工具可同时使用。")

	kit:section(page, "器械")
	local machines = kit:card(page)

	kit:toggle(machines, {
		label = "启用器械",
		path = "machine.enabled",
		hint = "随时可用，不依赖自动锻炼",
	})

	-- Machines do not need training switched on ("这个功能其实是什么时候都可以打
	-- 开的"), so neither this switch nor `Machine.tick` gates on the training flags.

	-- Forward-declared because the gym dropdown (below) re-classifies the machine
	-- list, and that list's widgets do not exist yet. It is only ever CALLED after
	-- they do -- the same pattern the config-slot page uses.
	local refreshMachines

	-- EVERY gym, not just the ones with streamed-in machines: the picker used to
	-- be built from `machineService:seats()`, so 全部 was the only choice unless
	-- the player happened to be standing in a gym at that moment ("我没法选择具体
	-- 是哪个健身房"). It is now the static gym table plus anything the live scan
	-- found, so gyms are a real CATEGORY.
	local function gymOptions()
		local seen = { ["全部"] = true }
		local out = { "全部" }
		for _, gym in ipairs(MachinePlan.gyms()) do
			local label = MachinePlan.gymLabel(gym.name)
			if seen[label] ~= true then
				seen[label] = true
				table.insert(out, label)
			end
		end
		if machineService ~= nil then
			for _, seat in ipairs(machineService:seats()) do
				local label = MachinePlan.gymLabel(seat.gym)
				if seen[label] ~= true then
					seen[label] = true
					table.insert(out, label)
				end
			end
		end
		table.sort(out, function(a, b)
			if a == "全部" then
				return true
			end
			if b == "全部" then
				return false
			end
			return a < b
		end)
		return out
	end

	-- The seats of the SELECTED gym, which is what makes the name and index
	-- lists follow the gym category rather than the whole world.
	local function seatsForGym()
		if machineService == nil then
			return {}
		end
		return MachinePlan.byGym(machineService:seats(), kit.store:get("machine.gymFilter"))
	end

	kit:dropdown(machines, {
		label = "健身房",
		values = gymOptions(),
		path = "machine.gymFilter",
		default = "",
		map = {
			toStore = function(display)
				if display == "全部" then
					return ""
				end
				for _, gym in ipairs(MachinePlan.gyms()) do
					if MachinePlan.gymLabel(gym.name) == display then
						return gym.name
					end
				end
				return display
			end,
			fromStore = function(stored)
				if stored == nil or stored == "" then
					return "全部"
				end
				return MachinePlan.gymLabel(stored)
			end,
		},
		onSelect = function()
			-- A machine name belongs to ONE gym: keeping the old one would leave the
			-- filter matching nothing in the new gym, and the machine would look
			-- broken rather than unfiltered. The slot index goes with it.
			kit.store:set("machine.nameFilter", "")
			kit.store:set("machine.indexFilter", 0)
			refreshMachines(true)
		end,
	})

	local nameDropdown
	local indexDropdown

	-- Rebuild the machine-name and index lists from a live scan. `default` is what
	-- the dropdown SHOWS when the store has nothing (or has something the scan no
	-- longer finds); it is nil unless we are actually resetting the selection --
	-- passing a label unconditionally made the old version look like it worked,
	-- since it "refreshed" by overwriting the user's pick with 全部.
	local function refreshMachinesImpl(resetSelection)
		if nameDropdown == nil or indexDropdown == nil or machineService == nil then
			return
		end

		-- Names OF THE SELECTED GYM: the gym filter is a category, and the list
		-- under it has to belong to that category.
		local seats = seatsForGym()
		local names = { "全部" }
		for _, name in ipairs(MachinePlan.names(seats)) do
			table.insert(names, MachinePlan.machineLabel(name))
		end
		local resetName = if resetSelection then "全部" else nil
		nameDropdown.refresh(names, resetName)

		local stored = kit.store:get("machine.nameFilter")
		local count = MachinePlan.count(seats, stored)
		local indexes = { "随机" }
		for position = 1, math.max(1, count) do
			table.insert(indexes, "第" .. position .. "台")
		end
		local resetIndex = if resetSelection then "随机" else nil
		indexDropdown.refresh(indexes, resetIndex)
	end
	refreshMachines = refreshMachinesImpl

	local function nameOptions()
		local out = { "全部" }
		for _, name in ipairs(MachinePlan.names(seatsForGym())) do
			table.insert(out, MachinePlan.machineLabel(name))
		end
		return out
	end

	nameDropdown = kit:dropdown(machines, {
		label = "器械名",
		values = nameOptions(),
		path = "machine.nameFilter",
		default = "",
		map = {
			toStore = function(display)
				if display == "全部" then
					return ""
				end
				local known = MachinePlan.names(seatsForGym())
				for _, name in ipairs(known) do
					if MachinePlan.machineLabel(name) == display then
						return name
					end
				end
				-- An unknown label is stored as-is rather than dropped: the scan is
				-- cached, and a name that is missing right now may exist a second
				-- later. Refusing it would silently unset the user's choice.
				return display
			end,
			fromStore = function(stored)
				if stored == nil or stored == "" then
					return "全部"
				end
				return MachinePlan.machineLabel(stored)
			end,
		},
		onSelect = function()
			-- The available slot count depends on which machine is chosen, so the
			-- index list follows the name. The stored slot points at the PREVIOUS
			-- machine's list, so it goes back to 随机 with it.
			kit.store:set("machine.indexFilter", 0)
			refreshMachines(false)
		end,
	})

	indexDropdown = kit:dropdown(machines, {
		label = "编号",
		values = { "随机" },
		path = "machine.indexFilter",
		default = 0,
		map = {
			toStore = function(display)
				return tonumber(string.match(display, "%d+")) or 0
			end,
			fromStore = function(stored)
				local value = tonumber(stored) or 0
				if value <= 0 then
					return "随机"
				end
				return "第" .. value .. "台"
			end,
		},
	})

	-- Keep the name list current: seats stream in as the player moves, so a list
	-- built once at page build is empty for anyone not standing in a gym then,
	-- which is why "器械名" had nothing to choose from.
	-- Polled every 6 s rather than 2: each pass asks game/Machine for the seat
	-- list, which walks `machinesFolder` once its own 2 s cache has expired (the
	-- dropdown itself only rebuilds when the list actually moved).
	local timers = shell.timers
	if timers ~= nil then
		timers:every(os.clock(), 6, function()
			refreshMachines(false)
		end)
	else
		kit:delay(6, function()
			refreshMachines(false)
		end)
	end

	kit:note(machines, "健身房是分类：选了健身房，下面的器械名和编号只列那个健身房的")
	kit:note(machines, "多人同器械时会自动换一台空闲的；列表每 6 秒重新扫描一次")
	-- 器械 vs 战斗. Default OFF keeps the documented priority (打 Boss > 全城杀戮 >
	-- 器械): the machine releases the seat while something needs to punch. But
	-- with auto-boss on there is nearly always a boss alive, so the machine looks
	-- permanently "不上" -- this switch is the explicit opposite, and when it is
	-- on the status line below stops reporting a block.
	kit:toggle(machines, {
		label = "器械优先（战斗中也不让位）",
		path = "machine.overridesCombat",
		hint = "默认关闭：打 Boss / 杀戮时会自动让位；打开后器械不再被抢占",
	})
	-- NOT a reset: the stored gym/name/index are authoritative on load. Passing a
	-- label here overwrote them, so the button could say 全部 while the filter still
	-- applied (or the loaded name while the store had been cleared).
	refreshMachines(false)

	-- A status line for the machine, because "使用器械无效" is otherwise
	-- unanswerable: the phase says whether it is hovering, sitting or blocked,
	-- and the seat count says whether the scan found anything at all.
	local machineStatus = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "器械状态：-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(machines),
	}, machines)
	shell:addUiTick(function()
		if machineService == nil then
			return
		end
		local stats = machineService:stats()
		machineStatus.Text = string.format(
			"器械状态：%s · 目标 %s · 扫描到 %d 台 · 尝试 %d 次",
			tostring(stats.phase), tostring(stats.target or "无"), stats.seats, stats.attempts
		)
	end)

	kit:section(page, "锻炼时机")
	local timing = kit:card(page)
	kit:toggle(timing, { label = "杀戮时同时锻炼", path = "train.duringKill" })
	kit:toggle(timing, { label = "打 Boss 时同时锻炼", path = "train.duringBoss" })
	-- The tool hand is arbitrated, and the pacing is explained here: training and
	-- punching cannot both hold the tool, so while they overlap the hand
	-- alternates between glove and training tool on ONE symmetric dwell
	-- (`杀戮 → 双工具切换间隔`).
	kit:note(timing, "同时锻炼时，拳套与训练工具按「杀戮 → 双工具切换间隔」轮流持握，两半时间相同")
	kit:toggle(timing, {
		label = "找不到工具时自动重生",
		path = "cfg.autoSuicide",
		hint = "默认关闭：没工具时只提示，不会把你杀掉",
	})
end

return Page
end

__modules["ui/Pages/Teleport"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The teleport page. The destination list comes from core/Teleports, and both
-- the dropdown and the grid write the INDEX into the store, so the two can
-- never disagree about what is selected.

local Teleports = require("core/Teleports")
local Platforms = require("game/Platforms")

local Page = {}

Page.id = "tele"
Page.label = "传送"

local PULL_MODES = {
	{ display = "严格（锚定 + 冻结）", value = "strict" },
	{ display = "普通（只写坐标）", value = "normal" },
	{ display = "关闭", value = "off" },
}

local function pullLabels()
	local out = {}
	for _, mode in ipairs(PULL_MODES) do
		table.insert(out, mode.display)
	end
	return out
end

local function pullToStore(display)
	for _, mode in ipairs(PULL_MODES) do
		if mode.display == display then
			return mode.value
		end
	end
	return "normal"
end

local function pullFromStore(value)
	for _, mode in ipairs(PULL_MODES) do
		if mode.value == value then
			return mode.display
		end
	end
	return PULL_MODES[2].display
end

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local teleport = services.teleport
	local motion = services.motion

	kit:section(page, "自动前往肌肉之王")
	local auto = kit:card(page)
	kit:toggle(auto, {
		label = "循环前往肌肉之王",
		path = "tp.autoMK",
		hint = "自动传送并停在那里；与「循环传送」互斥",
	})
	kit:button(auto, {
		label = "强制传送肌肉之王",
		role = "Green",
		onClick = function()
			if teleport ~= nil then
				teleport:goToMuscleKing()
			end
		end,
	})

	kit:section(page, "传送点")
	local points = kit:card(page)

	-- A read-out of the resolved destination, so you can see that the grid click
	-- and the dropdown agree. It follows the store rather than being written by
	-- the two controls that set the same key.
	local selectedLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "当前选择：-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(points),
	}, points)

	local function paintSelected()
		local entry = Teleports.byIndex(kit.store:get("tp.loopIdx"))
		local name = if entry ~= nil then entry.name else "-"
		selectedLabel.Text = "当前选择：" .. name
	end
	paintSelected()
	kit:track(kit.store:subscribe("tp.loopIdx", paintSelected))

	kit:dropdown(points, {
		label = "选择传送点",
		values = Teleports.labels(),
		path = "tp.loopIdx",
		default = 1,
		map = {
			toStore = function(display)
				return Teleports.indexOf(display)
			end,
			fromStore = function(stored)
				local entry = Teleports.byIndex(stored)
				return if entry ~= nil then entry.name else Teleports.labels()[1]
			end,
		},
	})

	kit:dualButtons(points, {
		label = "单次传送",
		role = "Green",
		onClick = function()
			-- Refuse while the auto-MK loop owns the character: the manual
			-- teleport would land and then be walked back within half a second,
			-- which reads as "the button does not work".
			if kit.store:get("tp.autoMK") == true then
				shell:toast("请先关闭「循环前往肌肉之王」再重试", "warn")
				return
			end
			local entry = Teleports.byIndex(kit.store:get("tp.loopIdx"))
			if entry ~= nil and teleport ~= nil then
				teleport:goTo(entry.name)
			end
		end,
	}, {
		label = "解除冻结（恢复正常移动）",
		role = "Yellow",
		onClick = function()
			if motion ~= nil then
				motion:unfreeze()
			end
		end,
	})

	kit:toggle(points, {
		label = "循环传送",
		path = "tp.loop",
		hint = "反复把角色送到所选传送点；与自动前往肌肉之王互斥，打 Boss 时会自动让位",
	})

	-- Keep the two "keep me somewhere" features mutually exclusive AT THE SWITCH.
	-- The scheduler already excludes them, but then the losing switch stays ARMED
	-- and turning auto-MK off later silently starts the forgotten loop.
	local function exclusive(key, otherKey, label)
		return kit.store:subscribe(key, function(_, value)
			if value ~= true or kit.store:get(otherKey) ~= true then
				return
			end
			shell:toast(string.format("已关闭%s（两者互斥）", label), "warn")
			kit.store:set(otherKey, false)
		end)
	end
	kit:track(exclusive("tp.autoMK", "tp.loop", "循环传送"))
	kit:track(exclusive("tp.loop", "tp.autoMK", "循环前往肌肉之王"))

	kit:section(page, "地图传送点")
	local grid = kit:card(page)
	local gridFrame = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = kit:nextOrder(grid),
	}, grid)
	kit:instance("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 36),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, gridFrame)

	for index, entry in ipairs(Teleports.LIST) do
		local button = kit:instance("TextButton", {
			LayoutOrder = index,
			BackgroundColor3 = kit:color("White"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Text = entry.name,
			TextColor3 = kit:color("TextPrimary"),
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, gridFrame)
		kit:corner(button, 6)
		kit:stroke(button, kit:color("Border"), 1, 0)
		kit:animate(button, kit:color("White"))
		kit:track(button.MouseButton1Click:Connect(function()
			-- Selecting and travelling are separate: the grid must not teleport
			-- the player by accident.
			kit.store:set("tp.loopIdx", index)
		end))
	end

	kit:note(grid, "点一下只是选中；再按上面的「单次传送」才会过去")

	kit:section(page, "防拉回")
	local anti = kit:card(page)
	kit:dropdown(anti, {
		label = "防拉回模式",
		values = pullLabels(),
		path = "cfg.antiPull",
		default = "normal",
		map = { toStore = pullToStore, fromStore = pullFromStore },
	})
	kit:toggle(anti, {
		label = "分跳推进传送",
		path = "cfg.tpPath",
		hint = "关闭后长距离一步到位；开启则分多跳推进，更不容易被判定拉回",
	})
	kit:toggle(anti, {
		label = "分段传送",
		path = "cfg.tpStage",
		hint = "长距离先抬高再落点，降低被判定",
	})
	kit:input(anti, {
		label = "传送时长上限（秒）",
		path = "cfg.tpMaxTime",
		min = 0.05,
		max = 5,
		default = 0.5,
		hint = "单次传送允许花费的最长时间",
	})
	kit:toggle(anti, { label = "失败退回安全点", path = "cfg.tpFallback" })
	kit:toggle(anti, {
		label = "开启悬停平台",
		path = "cfg.platform",
		hint = "严格模式下不需要，默认关闭",
	})

	-- Turning 悬停平台 off must also tear down the parts it already spawned:
	-- `Platforms.ensure` only ever ADDS (Motion.apply calls it while the flag is
	-- on) and nothing removes them on the flag going false, so the invisible
	-- parts stayed in Workspace until a hold ended.
	kit:track(kit.store:subscribe("cfg.platform", function(_, value)
		if value == false then
			Platforms.remove()
		end
	end))
	kit:input(anti, { label = "被拉回重试次数", path = "cfg.tpRetry", min = 0, max = 20, default = 3 })
	kit:input(anti, { label = "到达校验（秒）", path = "cfg.tpVerify", min = 1, max = 60, default = 6 })

	local statsLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "被拉回 0 次 / 重试 0 次",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(anti),
	}, anti)

	kit:button(anti, {
		label = "记录当前点为安全点",
		onClick = function()
			if motion ~= nil then
				motion:markSafe()
			end
		end,
	})

	-- The two escape hatches beside 记录安全点. `解除冻结` is the one that matters:
	-- the anti-pull kernel anchors the character, so when something goes wrong
	-- the player literally cannot move, and this (or the RightAlt hotkey, which
	-- calls the same thing) is the only way out.
	kit:dualButtons(
		anti,
		{
			label = "清空统计",
			onClick = function()
				local hold = motion ~= nil and motion.hold or nil
				if hold == nil then
					return
				end
				hold.stats.pulled = 0
				hold.stats.retries = 0
				hold.stats.failures = 0
				shell:toast("被拉回统计已清空", "success")
			end,
		},
		{
			label = "解除冻结",
			role = "Yellow",
			onClick = function()
				if motion ~= nil then
					motion:unfreeze()
				end
				shell:toast("已解除冻结", "success")
			end,
		}
	)

	kit:note(anti, "严格模式会锚定角色；走不动时按 RightAlt 或点上面「解除冻结」")

	-- A read-out, not a bound control: it refreshes on the shell's slow UI tick
	-- rather than on a frame connection of its own.
	shell:addUiTick(function()
		local hold = motion ~= nil and motion.hold or nil
		if hold == nil then
			return
		end
		statsLabel.Text = string.format("被拉回 %d 次 / 重试 %d 次 / 放弃 %d 次",
			hold.stats.pulled, hold.stats.retries, hold.stats.failures)
	end)
end

return Page
end

__modules["ui/Pages/Rebirth"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The rebirth page.
-- "Automatic rebirth" is not a store boolean: it is `rebirth.rate > 0`, because
-- the rate is what actually drives it. The switch reads and writes through that
-- derived pair instead of owning a second flag that could disagree (V1007's
-- duplicate flag left the toggle lit while the target counter had switched
-- rebirth off).

local Page = {}

Page.id = "reb"
Page.label = "重生"

Page.build = function(kit, page, shell)
	local store = kit.store

	kit:section(page, "自动重生")
	local auto = kit:card(page)
	kit:toggle(auto, {
		label = "自动重生",
		watch = "rebirth.rate",
		get = function()
			return (tonumber(store:get("rebirth.rate")) or 0) > 0
		end,
		write = function(on)
			store:set("rebirth.rate", if on then 2 else 0)
		end,
	})
	kit:input(auto, {
		label = "频率",
		path = "rebirth.rate",
		min = 0,
		max = 300,
		default = 2,
		hint = "每秒请求次数；填 0 等于关闭（与上面的开关是同一个东西）",
	})
	kit:input(auto, {
		label = "目标重生数",
		path = "rebirth.target",
		min = 0,
		max = 1000000,
		default = 0,
		hint = "0 = 不设上限；达到后自动关闭",
	})

	kit:section(page, "重生时机")
	local timing = kit:card(page)
	kit:toggle(timing, { label = "打 Boss 时也重生", path = "rebirth.duringBoss" })
	kit:toggle(timing, { label = "杀戮时也重生", path = "rebirth.duringKill" })

	kit:section(page, "重生锁 / 换包重生")
	local locks = kit:card(page)
	kit:toggle(locks, {
		label = "启用重生锁",
		path = "rebirth.lock",
		hint = "锁上之后不再自动重生（会顺手把频率清零）",
	})

	-- The lock zeroes the frequency, as its hint says: without this the 自动重生
	-- switch (the "rate > 0" view) would stay lit while locked and rebirth would
	-- resume the moment the lock was lifted. A store subscription, so a loaded
	-- config takes the same path as a click.
	kit:track(kit.store:subscribe("rebirth.lock", function(_, value)
		if value == true then
			kit.store:set("rebirth.rate", 0)
		end
	end))
	kit:toggle(locks, {
		label = "换包重生",
		path = "pet.autoPack",
		hint = "先练到目标力量、换上收益宠物，再请求重生",
	})

	kit:section(page, "状态")
	local status = kit:card(page)
	local label = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(status),
	}, status)

	local rebirth = (shell.services or {}).rebirth
	shell:addUiTick(function()
		if rebirth == nil then
			return
		end
		local stats = rebirth:stats()
		local phase = if stats.pending then "等待确认" else "空闲"
		label.Text = string.format("%s · 请求 %d · 成功 %d · 连续失败 %d · 换包阶段 %s",
			phase, stats.requests, stats.successes, stats.fails, stats.packPhase)
	end)
end

return Page
end

__modules["ui/Pages/Kill"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The combat page. The single-target dropdown is the one place a page reads the
-- game directly (the candidate list is whoever is in the server right now, which
-- is not state the store should hold), so it refreshes itself on its own slow
-- tick rather than opening a loop.

local Players = game:GetService("Players")

local Page = {}

Page.id = "kill"
Page.label = "杀戮"

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local combat = services.combat

	kit:section(page, "全图杀戮")
	local area = kit:card(page)
	kit:toggle(area, { label = "开启全图杀戮", path = "kill.enabled" })
	-- No range input any more: "搜索范围是不限制的，它是搜索全图玩家". The old
	-- `kill.range` key stays in the schema as a LIVE key, never read, only so an
	-- older config file loads without an "unknown key" warning.
	kit:note(area, "搜索范围不限制：扫描全图玩家，只挑最近的打")
	kit:toggle(area, {
		label = "打完就换下一个（跳过打不过的）",
		path = "kill.powerCheck",
		hint = "用双方力量/耐力（耐力=血量）算命中数赛跑：对方明显更强才跳过（不是差一点就跳）",
	})
	kit:input(area, {
		label = "最多需要几拳",
		path = "kill.powerMaxHits",
		min = 0,
		max = 500,
		default = 30,
		hint = "对方耐力 ÷ 我方力量超过这个数就算「打不死」，直接跳过；0 = 不限制",
	})
	-- The lock timeout, on the user's own numbers ("如果超时 10 秒没打过，那就给它
	-- 跳过"). The second box is what makes that stick: a skipped player is not
	-- re-picked until the cooldown runs out.
	kit:input(area, {
		label = "单个目标超时（秒）",
		path = "kill.targetTimeout",
		min = 2,
		max = 120,
		default = 10,
		hint = "同一个人打这么久还没死就换人",
	})
	kit:input(area, {
		label = "跳过冷却（秒）",
		path = "kill.targetSkip",
		min = 0,
		max = 3600,
		default = 60,
		hint = "被超时跳过的人多久之内不再选他（0 = 立刻可以再选）",
	})
	-- The safe-zone skip, switchable: the first version over-skipped ("很多人异常
	-- 打不到，很多玩家都被异常跳过了"), so one click has to be enough to turn it off.
	kit:toggle(area, {
		label = "跳过打不死的地方（万圣节健身房 / 小岛 / Boss 竞技场）",
		path = "kill.skipSafeZones",
		hint = "关闭后这些地方的人也会被打（但通常打不死）",
	})
	kit:toggle(area, {
		label = "贴身攻击",
		path = "kill.approach",
		hint = "关闭后原地出拳，不移动自己",
	})

	kit:section(page, "独立功能")
	local extras = kit:card(page)
	kit:toggle(extras, {
		label = "自动击杀肌肉之王",
		path = "kill.autoKing",
		hint = "需要同时开着「循环前往肌肉之王」",
	})
	kit:toggle(extras, { label = "杀戮时切换训练工具（双工具）", path = "kill.dualEnabled" })
	-- The dwell each hand keeps the tool. One number for BOTH halves, so the swap
	-- rates are equal by construction ("工具切换速度要两两齐平"); too short and
	-- neither a rep nor a punch lands. 0.15 (the user's own number) because 0.6
	-- meant a full glove -> tool -> glove cycle took 1.2 s.
	kit:slider(extras, {
		label = "双工具切换间隔（秒）",
		path = "kill.dualInterval",
		min = 0.1,
		max = 3,
		default = 0.15,
		commitOnly = true,
		hint = "每个半程持握工具的时长；两半相同，越小切换越快",
	})

	-- The priority ladder, written down where it is decided: enforced in three
	-- places (Boss > everything in the teleport and kill gates, 全图杀戮 > 单独
	-- 击杀 in the selection, everything > 器械 via the arbiter's `damage` hold),
	-- which is why it is stated once in the interface instead of being
	-- rediscovered by trying combinations.
	kit:note(extras, "优先级：打 Boss > 全图杀戮 > 单独击杀 / 肌肉之王 > 器械；高优先级运行时会自动让位")

	kit:section(page, "贴身方式")
	local approach = kit:card(page)
	-- The overhead approach: a punch thrown from the target's own height flies
	-- over its shoulder ("保证拳头一定打到对面身上"). The default is deliberately
	-- small (12 studs, about a body) rather than the boss's 70 -- for a
	-- player-sized hitbox the target has to stay inside the game's punch reach.
	kit:slider(approach, {
		label = "悬停高度（格）",
		path = "kill.hoverHeight",
		min = 1,
		max = 200,
		default = 12,
		commitOnly = true,
		hint = "站在目标上方多少格；太高会超出拳击距离",
	})
	kit:toggle(approach, {
		label = "俯视朝向（照打 Boss 的角度）",
		path = "kill.lookDown",
		hint = "关闭则平视目标，拳头容易从头顶飞过；打 Boss 也用这个开关",
	})
	-- 打人的 0.025 秒直写：和打 Boss 是两个独立开关 + 两个独立计时器（目标不同、
	-- 位置刷新节奏不同，共用会互相饿死）。
	kit:toggle(approach, {
		label = "贴脸直写 0.025 秒（位置+朝向）",
		path = "kill.directPin",
		hint = "关闭后只用每帧的保持修正；打不到人时可以先关掉试试",
	})

	kit:section(page, "单独击杀")
	local single = kit:card(page)
	kit:toggle(single, { label = "启用单独击杀", path = "kill.single" })

	-- The option list always includes the stored selection. `refresh(values,
	-- current)` PRESERVES the selection by keeping the display string -- but only
	-- if that string is still one of the values. A saved target that has left the
	-- server would otherwise be dropped, the dropdown would fall back to its first
	-- entry while the store kept the old name, and the kill task would keep
	-- hunting a player who is not there.
	local function playerNames()
		local out = {}
		local present = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= Players.LocalPlayer then
				table.insert(out, player.Name)
				present[player.Name] = true
			end
		end
		table.sort(out)

		local stored = kit.store:get("kill.singleName")
		if type(stored) == "string" and stored ~= "" and present[stored] ~= true then
			table.insert(out, 1, stored)
		end

		if #out == 0 then
			table.insert(out, "—")
		end
		return out
	end

	local targetDropdown
	targetDropdown = kit:dropdown(single, {
		label = "选择目标",
		values = playerNames(),
		path = "kill.singleName",
		default = "—",
		map = {
			toStore = function(display)
				return if display == "—" then "" else display
			end,
			fromStore = function(stored)
				if stored == nil or stored == "" then
					return "—"
				end
				return tostring(stored)
			end,
		},
		-- Selection feedback: without it a name from a saved config that no longer
		-- resolves fails SILENTLY -- the kill task looks it up, finds nobody, and
		-- reports nothing, so single-target mode looks on and idle.
		onSelect = function(display)
			if display == nil or display == "—" then
				return
			end
			local found = Players:FindFirstChild(display)
			if found ~= nil then
				shell:toast(string.format("单独击杀目标：%s", display), "success")
			else
				shell:toast(string.format("找不到玩家 %s（可能已离开）", display), "warn")
			end
		end,
	})

	kit:button(single, {
		label = "刷新玩家列表",
		onClick = function()
			if targetDropdown ~= nil then
				targetDropdown.refresh(playerNames(), targetDropdown.get())
			end
		end,
	})

	-- The list refreshes itself ("列表每 2 秒自动刷新"). It is throttled to 2 s
	-- rather than run on every UI tick (0.5 s): rebuilding the candidate list means
	-- walking `Players:GetPlayers()`, allocating and sorting, and the Kit only
	-- SKIPS the redraw when nothing changed -- the walk itself is not free. The
	-- stored selection is passed as `default` so a refresh never moves the user's
	-- choice.
	local lastPlayerScan = 0
	shell:addUiTick(function()
		if targetDropdown == nil then
			return
		end
		local now = os.clock()
		if now - lastPlayerScan < 2 then
			return
		end
		lastPlayerScan = now
		targetDropdown.refresh(playerNames(), targetDropdown.get())
	end)
	kit:note(single, "目标按名字记住，玩家重进后会重新绑定；不受搜索范围限制")

	kit:section(page, "好友白名单")
	local friends = kit:card(page)
	kit:toggle(friends, { label = "不打好友", path = "kill.friendWL" })

	local friendLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "名单状态：未加载",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(friends),
	}, friends)

	-- The whitelist is filled by an EXTERNAL script through two environment keys,
	-- so when that script is not ready the list stays empty and "不打好友" refuses
	-- every target; this manual refresh (and the 10-second retry in Combat) is the
	-- way back short of reloading.
	kit:button(friends, {
		label = "刷新好友列表",
		onClick = function()
			if combat == nil then
				shell:toast("战斗模块未加载", "warn")
				return
			end
			local count = combat:refreshFriends()
			if combat:friendStatus().loaded then
				shell:toast(string.format("好友列表已加载 %d 个", count), "success")
			else
				shell:toast("没有找到好友列表脚本提供的名单（MK_HUB_FRIEND_WL）", "warn")
			end
		end,
	})

	-- A read-out rather than a repeated note: it says whether the list is
	-- actually usable, which is what the user needs to know before relying on
	-- "不打好友".
	shell:addUiTick(function()
		if combat == nil then
			return
		end
		local status = combat:friendStatus()
		if status.loaded then
			friendLabel.Text = string.format("名单状态：已加载 %d 个好友", status.count)
		else
			-- "不打好友" is ON but there is no list: nobody can be proven a friend,
			-- so the switch does nothing and everyone is attackable. Saying "不会攻击
			-- 任何人" here described the OLD fail-safe and sent users hunting a bug
			-- that did not exist.
			friendLabel.Text = "名单状态：未加载（「不打好友」暂不生效，会攻击所有人）"
		end
	end)

	kit:note(friends, "需要外部好友列表脚本提供名单；名单未加载时「不打好友」不会拦下任何人")

	kit:section(page, "目标体型")
	local sizeCard = kit:card(page)
	kit:toggle(sizeCard, { label = "杀戮时调整目标体型", path = "kill.targetSizeEnabled" })
	kit:slider(sizeCard, {
		label = "目标体型倍率",
		path = "kill.targetSizeMul",
		min = 1,
		max = 20,
		default = 5,
		commitOnly = true,
	})
	kit:note(sizeCard, "只在自己视角可见（客户端改模型不会同步给服务器）")

	kit:section(page, "状态")
	local status = kit:card(page)
	local label = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(status),
	}, status)

	-- WHY PEOPLE ARE NOT BEING ATTACKED, spelled out: "很多人异常打不到，很多玩家都被异常
	-- 跳过了" is unanswerable from the outside, so this row counts each skip rule and names
	-- the players the timeout took out.
	local skipLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "跳过统计：-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = kit:nextOrder(status),
	}, status)

	shell:addUiTick(function()
		if combat == nil then
			return
		end
		local stats = combat:stats()
		-- The reason string is what makes "nothing is happening" answerable.
		label.Text = string.format("目标 %s · 出拳 %d · 选敌结果 %s",
			tostring(stats.locked or "无"), stats.punches, tostring(stats.lastReason))

		local skips = stats.skipStats or {}
		local parts = { string.format("扫描 %d 人", skips.total or 0) }
		if (skips.protected or 0) > 0 then
			table.insert(parts, string.format("安全区 %d", skips.protected))
		end
		if (skips.unwinnable or 0) > 0 then
			table.insert(parts, string.format("打不过 %d", skips.unwinnable))
		end
		if (skips.skipped or 0) > 0 then
			table.insert(parts, string.format("超时跳过 %d", skips.skipped))
		end
		local text = "跳过统计：" .. table.concat(parts, " · ")
		if stats.skippedCount ~= nil and stats.skippedCount > 0 then
			local names = stats.skippedIds or {}
			local shown = {}
			for index, name in ipairs(names) do
				if index > 4 then
					break
				end
				table.insert(shown, name)
			end
			text = text .. string.format("\n冷却中：%s%s", table.concat(shown, "、"),
				if #names > #shown then "…" else "")
		end
		skipLabel.Text = text
	end)
end

return Page
end

__modules["ui/Pages/Boss"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The boss page: one bound control per switch against the store, status lines
-- refreshed on the shell's slow tick (detection is cached for half a second
-- inside the service, so reading it here is cheap).
-- TWO SELECTION AREAS: 普通 Boss is the fixed arena, chosen by RARITY; 活动 Boss
-- (万圣节 / 圣诞 ...) is chosen ONE BY ONE and killed in a fixed order (Grim
-- Reaper first), with a settable cross-group priority and an optional server hop.
-- The event rows come from `core/BossInfo.events()` -- the same list the detector
-- walks -- so the page cannot offer a switch for a boss it does not know.

local BossInfo = require("core/BossInfo")

local Page = {}

Page.id = "boss"
Page.label = "Boss"

local RARITIES = {
	{ key = "Common", label = "普通" },
	{ key = "Rare", label = "稀有" },
	{ key = "Epic", label = "史诗" },
	{ key = "Legendary", label = "传奇" },
	{ key = "Rainbow", label = "彩虹" },
	{ key = "Mythic", label = "神话" },
}

local PRIORITY = {
	{ display = "优先打活动 Boss", value = "event" },
	{ display = "优先打普通 Boss", value = "normal" },
}

local HOP_MODES = {
	{ display = "人少的服务器（多半是新服）", value = "sparse" },
	{ display = "人多的服务器", value = "crowded" },
	{ display = "私服（用设置里的 code）", value = "private" },
}

local function displayToValue(list, display, fallback)
	for _, entry in ipairs(list) do
		if entry.display == display then
			return entry.value
		end
	end
	return fallback
end

local function valueToDisplay(list, value)
	for _, entry in ipairs(list) do
		if entry.value == value then
			return entry.display
		end
	end
	return list[1].display
end

local function labels(list)
	local out = {}
	for _, entry in ipairs(list) do
		table.insert(out, entry.display)
	end
	return out
end

local function readout(kit, card, text)
	local label = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(card),
	}, card)
	return label
end

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local boss = services.boss
	local rejoin = services.rejoin

	kit:section(page, "自动打 Boss")
	local auto = kit:card(page)
	kit:toggle(auto, {
		label = "自动打 Boss",
		path = "boss.auto",
		hint = "优先于全图杀戮；打开时会悬停在 Boss 上方",
	})

	-- Which group wins when both are up. Both are always tracked; this only
	-- decides who is attacked first -- the loser is picked up the moment the
	-- winner dies.
	kit:dropdown(auto, {
		label = "打 Boss 优先级",
		values = labels(PRIORITY),
		path = "boss.priority",
		default = "event",
		map = {
			toStore = function(display)
				return displayToValue(PRIORITY, display, "event")
			end,
			fromStore = function(stored)
				return valueToDisplay(PRIORITY, stored)
			end,
		},
	})
	kit:note(auto, "两组只影响谁先打；打完一组后会自动接着打另一组")
	-- The 0.025 s direct pin: on by default and switchable because it is the one
	-- thing to turn off if a place reacts badly to 40 pose writes a second. The
	-- kill feature has its own equivalent switch (different target, timer).
	kit:toggle(auto, {
		label = "贴脸直写 0.025 秒（位置+朝向）",
		path = "boss.directPin",
		hint = "关闭后只用每帧的保持修正；打不到 Boss 时可以先关掉试试",
	})

	local statusBox = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = kit:color("BgSoft"),
		BorderSizePixel = 0,
		LayoutOrder = kit:nextOrder(auto),
	}, auto)
	kit:corner(statusBox, 6)
	local statusLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, -16, 1, -10),
		Position = UDim2.fromOffset(8, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "等待 Boss 刷新...",
		TextColor3 = kit:color("TextMuted"),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, statusBox)

	local eventLabel = readout(kit, auto, "活动 Boss：等待刷新")

	shell:addUiTick(function()
		if boss == nil then
			return
		end
		-- The formatting lives in core/BossInfo, so the label and the service
		-- cannot disagree about what "waiting" looks like.
		statusLabel.Text = boss:status()
		statusLabel.TextColor3 = if boss:isAlive() then kit:color("Red") else kit:color("TextMuted")
		if boss.eventStatus ~= nil then
			eventLabel.Text = boss:eventStatus()
		end
	end)

	kit:section(page, "普通 Boss（固定竞技场 · 按品级）")
	local rarityCard = kit:card(page)
	for _, rarity in ipairs(RARITIES) do
		kit:toggle(rarityCard, {
			label = rarity.label,
			path = "boss.select." .. rarity.key,
		})
	end
	kit:note(rarityCard, "识别不出品级的 Boss 一律算作要打，避免游戏改名后功能静默失效")
	kit:note(rarityCard, "悬停高度固定 70 格（几何写死，不能改）")

	kit:section(page, "活动 Boss（万圣节 / 圣诞等）")
	local eventCard = kit:card(page)
	kit:toggle(eventCard, {
		label = "启用活动 Boss",
		path = "boss.event.enabled",
		hint = "关掉后完全不打活动 Boss，只打上面的普通 Boss",
	})

	-- One row per event boss, in kill order: the order is core/BossInfo's and the
	-- number in the label makes it visible, since the fight takes the first one
	-- still alive. Turning one off skips it without disturbing the others.
	for index, entry in ipairs(BossInfo.events()) do
		kit:toggle(eventCard, {
			label = string.format("%d. %s", index, entry.label),
			path = "boss.event." .. entry.key,
		})
	end
	kit:note(eventCard, "按顺序击杀：打完一个自动飞下一个；关掉的会被跳过")

	-- The fixed hover heights, spelled out in the label: each number is geometry
	-- about that boss's rig (Frankenbrute is twice the rest, Scarecrow is small),
	-- so there is no slider, and the read-out answers "why did it hover there".
	local heights = {}
	for _, entry in ipairs(BossInfo.events()) do
		table.insert(heights, string.format("%s %d", entry.label:match("^%S+"), entry.hover))
	end
	kit:note(eventCard, "悬停高度固定：" .. table.concat(heights, " · ") .. " 格")
	kit:note(eventCard, "不在万圣节健身房时，会先用游戏自己的 areaTravelRemote 传送过去，再开始打")

	kit:section(page, "手动换服")
	local hop = kit:card(page)
	kit:dropdown(hop, {
		label = "换服目标",
		values = labels(HOP_MODES),
		path = "boss.event.hopMode",
		default = "sparse",
		map = {
			toStore = function(display)
				return displayToValue(HOP_MODES, display, "sparse")
			end,
			fromStore = function(stored)
				return valueToDisplay(HOP_MODES, stored)
			end,
		},
	})
	kit:button(hop, {
		label = "立即换服",
		role = "Yellow",
		onClick = function()
			if boss ~= nil then
				boss:requestHop("手动换服")
				return
			end
			if rejoin ~= nil then
				rejoin:requestNow("手动换服")
			end
		end,
	})
	kit:note(hop, "换服前会自动保存一次配置；换服目标只用这里的选择，私服模式读取「设置 → 重进」里的私服 code")

	kit:section(page, "体型与宝箱")
	local extra = kit:card(page)
	kit:toggle(extra, { label = "打 Boss 时调整体型", path = "boss.sizeEnabled" })
	kit:slider(extra, {
		label = "体型大小",
		path = "boss.sizeMul",
		min = 1,
		max = 20,
		default = 5,
		commitOnly = true,
	})
	kit:divider(extra)
	kit:toggle(extra, { label = "自动开宝箱", path = "boss.autoChest" })
	kit:slider(extra, {
		label = "宝箱延迟（秒）",
		path = "boss.chestDelay",
		min = 0,
		max = 30,
		default = 3,
		commitOnly = true,
	})
end

return Page
end

__modules["ui/Pages/Pets"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The pet page. The four preset rows all do the same three things -- snapshot what
-- is worn, apply a saved preset, clear it -- so they are built from one helper
-- rather than copied four times, which is how the original ended up with four
-- nearly identical blocks that had drifted apart.

local Shell = require("ui/Shell")
local CrystalList = require("core/CrystalList")

local Page = {}

Page.id = "pet"
Page.label = "宠物"

local PRESETS = {
	{ key = "train", label = "锻炼" },
	{ key = "rebirth", label = "重生" },
	{ key = "kill", label = "杀戮" },
	{ key = "boss", label = "Boss" },
}

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local pets = services.pets

	kit:section(page, "自动换宠")
	local auto = kit:card(page)
	kit:toggle(auto, {
		label = "启用自动切换宠物",
		path = "petPreset.autoSwitch",
		hint = "切换任务时自动套用对应预设",
	})

	for _, preset in ipairs(PRESETS) do
		local row = kit:instance("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			LayoutOrder = kit:nextOrder(auto),
		}, auto)

		local tag = kit:instance("TextLabel", {
			Size = UDim2.new(0, 56, 1, 0),
			BackgroundColor3 = kit:color("BgSoft"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = preset.label,
			TextColor3 = kit:color("TextPrimary"),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, row)
		kit:corner(tag, 6)

		local holder = kit:instance("Frame", {
			Size = UDim2.new(1, -62, 1, 0),
			Position = UDim2.fromOffset(62, 0),
			BackgroundTransparency = 1,
		}, row)
		kit:list(holder, 5, true)

		local function slotButton(label, role, onClick)
			local button = kit:instance("TextButton", {
				Size = UDim2.new(0.25, -4, 1, 0),
				BackgroundColor3 = kit:color(role),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Text = label,
				TextColor3 = if role == "Green" or role == "Red" then kit:color("White") else kit:color("TextPrimary"),
				TextSize = 12,
			}, holder)
			kit:corner(button, 6)
			kit:stroke(button, kit:color("Border"), 1, 0)
			kit:animate(button, kit:color(role))
			kit:track(button.MouseButton1Click:Connect(function()
				task.spawn(onClick)
			end))
			return button
		end

		slotButton("保存", "White", function()
			if pets == nil then
				return
			end

			-- The overwrite confirmation: a preset is pure user data with no other
			-- copy, so replacing a non-empty one must ask. An empty preset saves
			-- immediately -- a confirmation for the common first-time case is
			-- just friction.
			local existing = kit.store:get("petPreset." .. preset.key)
			local function commit()
				local count = pets:savePreset(preset.key)
				if count == 0 then
					shell:toast(string.format("预设 [%s] 没有可保存的宠物", preset.label), "warn")
				else
					shell:toast(string.format("预设 [%s] 已保存 %d 只", preset.label, count), "success")
				end
			end

			if type(existing) == "table" and #existing > 0 then
				Shell.confirm(
					shell,
					"覆盖预设",
					string.format("预设 [%s] 已有 %d 种配置，是否覆盖？", preset.label, #existing),
					commit
				)
				return
			end
			commit()
		end)

		slotButton("应用", "Green", function()
			if pets ~= nil then
				pets:applyPreset(preset.key)
			end
		end)

		slotButton("清除", "Red", function()
			if pets ~= nil then
				pets:clearPreset(preset.key)
				shell:toast(string.format("预设 [%s] 已清除", preset.label), "success")
			end
		end)

		-- "?" reports WHAT is in a preset, not just how many pets: a list of names
		-- is content to read, so it goes to `Shell.preview` (a dismissible card)
		-- rather than a toast.
		local questionButton
		questionButton = slotButton("?", "White", function()
			local entries = kit.store:get("petPreset." .. preset.key)
			local lines = {}
			if type(entries) ~= "table" or #entries == 0 then
				-- "never saved" and "cleared" are different states, and the store
				-- can only tell them apart by whether the key holds an empty table
				-- (cleared) or nothing at all (never saved).
				lines = { if entries == nil then "尚未保存过这个预设" else "这个预设已被清除" }
			else
				for _, entry in ipairs(entries) do
					table.insert(lines, string.format("%s × %d", entry.name, entry.count or 1))
				end
			end
			-- Anchored to the "?" that opened it.
			Shell.preview(shell, string.format("预设 [%s] · %d 种", preset.label, #lines), lines, nil, questionButton)
		end)
	end

	kit:section(page, "吃蛋 / 轮盘")
	local extras = kit:card(page)
	kit:toggle(extras, { label = "自动吃蛋", path = "pet.autoEgg" })
	kit:input(extras, { label = "吃蛋数量", path = "pet.eggBatch", min = 1, max = 500, default = 10 })
	kit:toggle(extras, { label = "自动轮盘", path = "pet.autoWheel" })

	kit:section(page, "宠物商店")
	local shop = kit:card(page)

	local shopDropdown

	-- Same trap as the single-target dropdown: `refresh(values, current)` keeps
	-- the selection only while the display string is still in `values`, so a saved
	-- pet that has scrolled out of the shop would vanish from the list while
	-- `pet.selected` still named it -- 购买 would look armed and fail.
	local function shopOptions()
		local out = if pets ~= nil then pets:shopList() else {}
		local stored = kit.store:get("pet.selected")
		if type(stored) == "string" and stored ~= "" then
			local found = false
			for _, name in ipairs(out) do
				if name == stored then
					found = true
					break
				end
			end
			if not found then
				table.insert(out, 1, stored)
			end
		end
		if #out == 0 then
			table.insert(out, "—")
		end
		return out
	end

	shopDropdown = kit:dropdown(shop, {
		label = "选择宠物",
		values = shopOptions(),
		path = "pet.selected",
		default = "—",
		map = {
			toStore = function(display)
				return if display == "—" then "" else display
			end,
			fromStore = function(stored)
				if stored == nil or stored == "" then
					return "—"
				end
				return tostring(stored)
			end,
		},
	})
	kit:dualButtons(shop, {
		label = "刷新列表",
		onClick = function()
			if pets ~= nil and shopDropdown ~= nil then
				-- Re-select what the store holds, rather than resetting to the
				-- first option: a refresh must not change the user's choice.
				shopDropdown.refresh(shopOptions(), shopDropdown.get())
			end
		end,
	}, {
		label = "购买",
		role = "Green",
		onClick = function()
			if pets ~= nil then
				pets:buySelected()
			end
		end,
	})

	kit:toggle(shop, { label = "自动购买", path = "pet.autoBuy" })

	-- CRYSTALS -- hatching, and the auto-sell list that goes with it. The game's
	-- own protocol (confirmed from a Cobalt recording):
	--   Remote:InvokeServer("openCrystal", "Hallowed Crystal")
	--   Remote:InvokeServer("saveAutoSell", "Hallowed Crystal",
	--       { Pets = { ["Candy Cube"] = true, ... }, Enabled = false, Auras = {} })
	-- Both are per-crystal, so the picker is built from the live catalogue
	-- (`shared.catalogs.crystalChances`) instead of hard-coding the crystal the
	-- recording happened to use -- the next event brings a new one.
	kit:section(page, "水晶（开蛋 / 自动出售）")
	local crystals = services.crystals
	local crystalCard = kit:card(page)

	local crystalDropdown
	if crystals == nil then
		kit:note(crystalCard, "水晶模块未加载")
	else
		local function crystalLabels()
			local out = crystals:labels()
			if #out == 0 then
				return { "—" }
			end
			return out
		end
		crystalDropdown = kit:dropdown(crystalCard, {
			label = "选择水晶",
			values = crystalLabels(),
			path = "crystal.selected",
			default = "",
			map = {
				-- The dropdown shows "名字（价格）" but the remote takes the bare
				-- NAME, so the LABEL IS LOOKED UP rather than parsed. The Halloween
				-- crystal is the only one with a price, i.e. the only one whose
				-- label is not the name -- and a name-strip silently fails on it the
				-- moment the label format changes, in which case the server receives
				-- a display string, matches no crystal, and nothing opens.
				toStore = function(display)
					if display == "—" then
						return ""
					end
					local name = crystals:nameForLabel(tostring(display))
					if name ~= "" and name ~= tostring(display) then
						return name
					end
					-- Not in the catalogue: keep the old strip as a last resort.
					local stripped = string.match(display, "^(.-)（")
					return if stripped ~= nil and stripped ~= "" then stripped else display
				end,
				fromStore = function(stored)
					if stored == nil or stored == "" then
						return "—"
					end
					return crystals:labelFor(tostring(stored))
				end,
			},
		})
		kit:button(crystalCard, {
			label = "刷新水晶列表",
			onClick = function()
				if crystalDropdown ~= nil then
					crystalDropdown.refresh(crystalLabels(), crystalDropdown.get())
				end
			end,
		})
		-- 6 s, like the machine list: the catalogue arrives with the game data.
		local timers = shell.timers
		if timers ~= nil then
			timers:every(os.clock(), 6, function()
				if crystalDropdown ~= nil then
					crystalDropdown.refresh(crystalLabels(), nil)
				end
			end)
		end
	end

	kit:toggle(crystalCard, {
		label = "自动开水晶",
		path = "crystal.auto",
		hint = "按下面的频率对着所选水晶调用 openCrystal",
	})
	kit:slider(crystalCard, {
		label = "开水晶频率（次/秒）",
		path = "crystal.rate",
		min = 1,
		max = 20,
		default = 2,
		commitOnly = true,
		hint = "同时最多这么多请求在等服务器（每次调用要走一个往返）；高延迟下这个值决定实际速度",
	})

	kit:toggle(crystalCard, {
		label = "自动出售该水晶的宠物",
		path = "crystal.autoSell",
		hint = "保存到服务器的自动出售配置（saveAutoSell）",
	})

	-- Which pets are sold, chosen one by one: "实际上应该是让我来选择出售哪些宠物，
	-- 就是该水晶的哪些宠物，并且都是会保留的" -- so this is a checkbox per pet, a
	-- ticked pet is sold and everything unticked is kept. The selection is per
	-- crystal in `crystal.sellByCrystal`, so switching crystals shows that
	-- crystal's own list and a reload remembers every one of them.
	kit:note(crystalCard, "下面勾选的是「要卖掉」的宠物；没勾的都会保留（按水晶分别记住）")

	local sellList = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = kit:nextOrder(crystalCard),
	}, crystalCard)
	kit:list(sellList, 2)

	-- The live widgets, keyed by pet name, rebuilt when the crystal's pool
	-- changes (a different crystal, or the catalogue arriving late).
	--
	-- The row type is deliberately plain (`any` for the instances): this
	-- analyzer's host whitelist has no Roblox class types, so `TextButton` is an
	-- unknown type here.
	local rows: { [string]: { frame: any, box: any, mark: any, name: string } } = {}
	local rowOrder = 0
	local builtFor = nil
	-- The POOL's content, not its length: a crystal swap can keep the same count
	-- while changing every name (several crystals share a pet list size), and a
	-- length check left the previous crystal's rows behind -- ticking a row then
	-- marked the WRONG pet.
	local builtKey = nil
	local function poolKey(crystalName, pool)
		return crystalName .. "\n" .. table.concat(pool, "\n")
	end

	local function clearRows()
		for _, row in pairs(rows) do
			pcall(function()
				row.frame:Destroy()
			end)
		end
		table.clear(rows)
	end

	local function paint(row, marked)
		row.mark.BackgroundColor3 = if marked then kit:color("Green") else kit:color("BgSoft")
		row.mark.Text = if marked then "✓" else ""
		row.mark.TextColor3 = if marked then kit:color("White") else kit:color("TextMuted")
	end

	local function buildRows(pool, crystalName)
		clearRows()
		rowOrder = 0
		for _, pet in ipairs(pool) do
			rowOrder += 1
			local row = kit:instance("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				LayoutOrder = rowOrder,
			}, sellList)

			local box = kit:instance("TextButton", {
				Size = UDim2.fromOffset(22, 22),
				Position = UDim2.fromOffset(0, 2),
				BackgroundColor3 = kit:color("BgSoft"),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Text = "",
				TextSize = 14,
				ZIndex = 2,
			}, row)
			kit:corner(box, 5)
			kit:stroke(box, kit:color("Border"), 1, 0)

			kit:instance("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(30, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Font = Enum.Font.GothamMedium,
				Text = pet,
				TextColor3 = kit:color("TextPrimary"),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, row)

			local entry = { frame = row, box = box, mark = box, name = pet }
			rows[pet] = entry

			kit:track(box.MouseButton1Click:Connect(function()
				if crystals == nil then
					return
				end
				local next = not CrystalList.isMarked(kit.store:get("crystal.sellByCrystal"), crystalName, pet)
				crystals:setSell(pet, next)
			end))
		end
		builtFor = crystalName
		builtKey = poolKey(crystalName, pool)
	end

	-- Repaint from the STORE, not from the click: the click only writes
	-- `crystal.sellByCrystal`, and the subscription below is what ticks the box --
	-- so a change from a loaded config slot, or from a second window, shows up
	-- here too.
	local function repaint()
		local selected = kit.store:get("crystal.selected")
		local crystalName = if type(selected) == "string" then selected else ""
		local pool = if crystals ~= nil then crystals:selectedPool() else {}
		if builtFor ~= crystalName or builtKey ~= poolKey(crystalName, pool) then
			buildRows(pool, crystalName)
		end
		local map = kit.store:get("crystal.sellByCrystal")
		for pet, row in pairs(rows) do
			paint(row, CrystalList.isMarked(map, crystalName, pet))
		end
	end

	kit:track(kit.store:subscribe("crystal.sellByCrystal", repaint))
	kit:track(kit.store:subscribe("crystal.selected", repaint))
	shell:addUiTick(function()
		-- The catalogue arrives with the game data, so the pool can go from
		-- empty to full without any store change at all.
		local selected = kit.store:get("crystal.selected")
		local crystalName = if type(selected) == "string" then selected else ""
		local pool = if crystals ~= nil then crystals:selectedPool() else {}
		if builtFor ~= crystalName or builtKey ~= poolKey(crystalName, pool) then
			repaint()
		end
	end)

	kit:dualButtons(crystalCard, {
		label = "全选（该水晶全部出售）",
		onClick = function()
			if crystals == nil then
				return
			end
			local count = crystals:setPoolSell(true)
			if count > 0 then
				shell:toast(string.format("已勾选该水晶的 %d 种宠物", count), "success")
			end
		end,
	}, {
		label = "全不选（全部保留）",
		onClick = function()
			if crystals == nil then
				return
			end
			local count = crystals:setPoolSell(false)
			if count > 0 then
				shell:toast(string.format("已取消该水晶的 %d 种宠物（全部保留）", count), "info")
			end
		end,
	})

	kit:button(crystalCard, {
		label = "应用出售配置",
		role = "Green",
		onClick = function()
			if crystals ~= nil and crystals:applyAutoSell() then
				shell:toast("已把自动出售配置发给服务器", "success")
			end
		end,
	})

	local sellLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "出售列表：-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(crystalCard),
	}, crystalCard)

	local crystalStatus = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "水晶状态：-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = kit:nextOrder(crystalCard),
	}, crystalCard)

	shell:addUiTick(function()
		-- The count and the names come from the SELECTION, so the read-out and
		-- the checkboxes can never disagree.
		if crystals ~= nil then
			local sell = crystals:sellSelection()
			local names = {}
			for name in pairs(sell) do
				table.insert(names, name)
			end
			table.sort(names)
			sellLabel.Text = if #names == 0
				then "出售列表：（空，一个都不卖，全部保留）"
				else string.format("要卖掉 %d 种：%s", #names, table.concat(names, "、"))
		end
		if crystals ~= nil then
			local stats = crystals:stats()
			-- The waiting count is part of the read-out: counters alone made "no
			-- crystal selected", "openCrystalRemote missing", "auto off" and "the
			-- server refused" all look identical ("水晶抽取功能异常"). The
			-- in-flight / last-reply pair is what distinguishes them.
			crystalStatus.Text = string.format(
				"水晶状态：已开 %d · 配置 %d 次 · 列表 %d 个 · 等待 %d · 最近 %s",
				stats.opened, stats.applied, stats.count, stats.inFlight or 0, tostring(stats.last))
		end
	end)

	repaint()

	kit:section(page, "宠物收益")
	local metricsCard = kit:card(page)
	local metricsLabel = kit:instance("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "-",
		TextColor3 = kit:color("TextSecond"),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = kit:nextOrder(metricsCard),
	}, metricsCard)

	local petMetrics = services.petMetrics
	shell:addUiTick(function()
		if petMetrics == nil then
			return
		end
		local stats = petMetrics:stats()
		metricsLabel.Text = string.format("反复 %d%%（%d 只）· 终极 %d%% · 通行证 %s · 综合 %s",
			stats.result.total - stats.result.ultimatePercent,
			stats.result.petCount,
			stats.result.ultimatePercent,
			if stats.result.uncapped then "无上限" else "见信息窗",
			stats.label)
	end)
end

return Page
end

__modules["ui/Pages/Settings"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	The settings page.

	Almost everything here is a bound control. The exceptions are the two sliders
	whose legal range depends on the window's own scale -- they are re-declared
	through setRange whenever the shell resizes, which is why the page hands the
	shell a syncSliders callback instead of owning that logic.
]]

local Page = {}

Page.id = "set"
Page.label = "设置"

local REJOIN_MODES = {
	{ display = "回原服务器", value = "same" },
	{ display = "人多的服务器", value = "crowded" },
	{ display = "私服", value = "private" },
	{ display = "人少的服务器", value = "sparse" },
	--[[
		目标玩家所在服务器.

		The username is resolved at rejoin time (users.roblox.com -> presence) and
		the fallback chain is the point of the mode: that player's server, else the
		private code if one is configured, else the quietest public servers, else
		this server. See core/ServerPick.chain.
	]]
	{ display = "目标玩家所在服务器", value = "player" },
}

local function rejoinLabels()
	local out = {}
	for _, mode in ipairs(REJOIN_MODES) do
		table.insert(out, mode.display)
	end
	return out
end

local function rejoinToStore(display)
	for _, mode in ipairs(REJOIN_MODES) do
		if mode.display == display then
			return mode.value
		end
	end
	return "same"
end

local function rejoinFromStore(value)
	for _, mode in ipairs(REJOIN_MODES) do
		if mode.value == value then
			return mode.display
		end
	end
	return REJOIN_MODES[1].display
end

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local motion = services.motion
	local teleport = services.teleport

	kit:section(page, "全局控制")
	local control = kit:card(page)
	kit:toggle(control, {
		label = "暂停脚本",
		path = "runtime.paused",
		hint = "暂停后只有反挂机、保存、信息窗继续运行",
	})
	kit:toggle(control, {
		label = "禁用性能优化",
		path = "perf.disabled",
		hint = "会把已经做过的优化恢复回去",
	})
	kit:toggle(control, { label = "深度防卡顿（总开关）", path = "perf.antiLag" })
	--[[
		WHAT "深度" ACTUALLY DOES.

		The old pass hid particles and shadows only, which is why the user
		reported it as "完全无效" -- on a big place the textures and the lighting
		are the cost. Three independent, individually reversible groups now, all
		on by default so the master switch keeps its promise.
	]]
	kit:toggle(control, {
		label = "· 移除特效（粒子 / 光束 / 灯光 / 后处理）",
		path = "perf.removeEffects",
	})
	kit:toggle(control, {
		label = "· 移除纹理（贴花 / 纹理贴图）",
		path = "perf.removeTextures",
	})
	kit:toggle(control, {
		label = "· 渲染剔除（阴影 / 环境光照）",
		path = "perf.cull",
	})
	kit:toggle(control, { label = "显示通知气泡", path = "cfg.toast" })
	--[[
		THE 功能存档 MASTER SWITCH.

		OFF stops every write this session -- the autosave below it, the
		close-side save, and the 配置存档 slot card at the bottom of this page.
		Already-saved values still load at boot, so it is safe to try; the point
		of exposing it is that writing is the one thing a user cannot see.
	]]
	kit:toggle(control, {
		label = "启用功能存档",
		path = "cfg.saveEnabled",
		hint = "关闭后本次运行不再写入任何配置文件；已保存的配置仍然照常读取",
	})
	--[[
		THE AUTOSAVE INTERVAL.

		The requirement is "every 10 seconds, and once immediately when the script
		is closed". The close-side save lives in `session.stop`; this is the
		periodic half, exposed because the write is the expensive part.
	]]
	kit:slider(control, {
		label = "自动保存间隔（秒）",
		path = "cfg.saveSeconds",
		min = 3,
		max = 300,
		default = 10,
		commitOnly = true,
		hint = "关闭脚本时无论如何都会立即保存一次",
	})

	kit:section(page, "操作与快捷键")
	local hotkeys = kit:card(page)
	kit:toggle(hotkeys, {
		label = "保留拳套（丢失自动补）",
		path = "cfg.keepPunch",
	})
	kit:toggle(hotkeys, {
		label = "键盘快捷键",
		path = "cfg.hotkeys",
		hint = "RightShift 最小化 / 药丸，RightCtrl 暂停，RightAlt 解除冻结，Space 下器械",
	})

	--[[
		The load-announce toggle was MISSING.

		`Announce.show` reads `cfg.announce` and the key is in the schema with a
		true default, but nothing in src/ ever wrote it -- so the announcement
		could not be turned off and the settings page did not mention it. V1007 had
		this control ("加载公告", hint "免费脚本 + 群号提示（关闭后下次加载不再弹）").
	]]
	kit:toggle(hotkeys, {
		label = "加载公告",
		hint = "启动时的说明弹窗（关闭后下次加载不再弹）",
		path = "cfg.announce",
	})

	kit:section(page, "窗口外观")
	local appearance = kit:card(page)
	kit:slider(appearance, {
		label = "字体大小 %",
		path = "uiState.fontScale",
		min = 80,
		max = 150,
		default = 100,
		commitOnly = true,
		-- Stored as a multiplier, shown as a percentage.
		map = {
			toStore = function(displayed)
				return displayed / 100
			end,
			fromStore = function(stored)
				return math.floor((tonumber(stored) or 1) * 100 + 0.5)
			end,
		},
	})

	kit:slider(appearance, {
		label = "整体缩放 %",
		path = "uiState.uiScale",
		min = 50,
		max = 125,
		default = 100,
		commitOnly = true,
	})

	local widthSlider = kit:slider(appearance, {
		label = "窗口宽度 %",
		path = "uiState.widthPct",
		min = 30,
		max = 100,
		default = 45,
		commitOnly = true,
	})
	local heightSlider = kit:slider(appearance, {
		label = "窗口高度 %",
		path = "uiState.heightPct",
		min = 30,
		max = 100,
		default = 52,
		commitOnly = true,
	})

	kit:note(appearance, "宽/高是「整体缩放 100%」时占屏幕的比例；上限会随缩放与分辨率自动收紧")

	-- The shell owns the range calculation, so it owns the sync.
	shell.syncSliders = function()
		local low, high = shell:pctRange()
		widthSlider.setRange(low, high)
		heightSlider.setRange(low, high)
		widthSlider.set(kit.store:get("uiState.widthPct"))
		heightSlider.set(kit.store:get("uiState.heightPct"))
	end

	--[[
		The info panel's own scale, and its base size.

		`uiState.infoScale` was READ by the info window but had no control anywhere,
		and `uiState.savedInfoSize` was written by nothing -- so the panel could
		neither be scaled from the UI nor remember a resize. Both are restored here
		(V1007 shipped an "信息窗大小 %" slider).
	]]
	kit:slider(appearance, {
		label = "信息窗大小 %",
		path = "uiState.infoScale",
		min = 50,
		max = 250,
		default = 100,
		commitOnly = true,
	})

	kit:toggle(appearance, { label = "数字格式化显示（1.000K）", path = "uiState.formatNum" })
	kit:toggle(appearance, {
		label = "显示实时信息悬浮窗",
		path = "uiState.infoVisible",
		hint = "会自动避开主面板摆放；右下角可拖拽缩放",
	})
	--[[
		Should collapsing the MAIN window also hide the info panel?

		Default OFF, which is the user's stated behaviour: the panel stays up
		through minimise and pill mode and is only removed by its own ✕. The switch
		is the one-click answer for the opposite preference, so this is a choice
		rather than an argument.
	]]
	kit:toggle(appearance, {
		label = "最小化 / 药丸时隐藏信息窗",
		path = "uiState.infoHideWithShell",
		hint = "默认关闭：信息窗只有在你自己点 ✕ 时才消失",
	})
	kit:button(appearance, {
		label = "重置窗口位置",
		onClick = function()
			kit.store:set("uiState.savedMain", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
		end,
	})
	kit:button(appearance, {
		label = "重置界面（全部布局恢复默认）",
		role = "Yellow",
		onClick = function()
			-- Same action as the long-press reset button: every layout value back
			-- to its default. V1007 had both entry points.
			shell:resetLayout()
		end,
	})

	kit:section(page, "自己角色体型")
	local sizeCard = kit:card(page)
	kit:toggle(sizeCard, { label = "启用自己体型调整", path = "size.selfEnabled" })
	kit:slider(sizeCard, {
		label = "自己体型",
		path = "size.selfMul",
		min = 1,
		max = 20,
		default = 3,
		commitOnly = true,
	})

	kit:section(page, "重进")
	local rejoin = kit:card(page)
	kit:toggle(rejoin, { label = "启用自动重进（内存 / 帧率 / 延迟）", path = "rejoin.enabled" })
	kit:toggle(rejoin, { label = "启用定时重进", path = "rejoin.timedEnabled" })
	kit:input(rejoin, { label = "间隔（分钟）", path = "rejoin.timedMin", min = 3, max = 1440, default = 30 })
	kit:dropdown(rejoin, {
		label = "重进目标",
		values = rejoinLabels(),
		path = "rejoin.mode",
		default = "same",
		map = { toStore = rejoinToStore, fromStore = rejoinFromStore },
	})
	-- "目标玩家所在服务器" is a MODE: it only chooses where an already triggered
	-- rejoin lands. Saying so here is cheaper than a user concluding the mode is
	-- broken.
	kit:note(rejoin, "「目标玩家所在服务器」对手动 / 定时重进生效")
	kit:textInput(rejoin, {
		label = "私服 code",
		path = "rejoin.privId",
		default = "",
		placeholder = "链接或 code",
	})
	-- 目标玩家, read by `rejoin.mode == "player"`.
	kit:textInput(rejoin, {
		label = "目标玩家用户名",
		path = "rejoin.targetPlayer",
		default = "",
		placeholder = "例如 Notch",
		hint = "重进目标选「目标玩家所在服务器」时用这个名字",
	})
	kit:toggle(rejoin, { label = "紧急重进（掉线 / 报错弹窗）", path = "rejoin.emergEnabled" })
	kit:divider(rejoin)
	kit:toggle(rejoin, { label = "内存触发器", path = "rejoin.memTrigger" })
	kit:input(rejoin, { label = "内存阈值 MB", path = "rejoin.memThresh", min = 500, max = 100000, default = 4000 })
	kit:toggle(rejoin, { label = "帧率触发器", path = "rejoin.fpsTrigger" })
	kit:input(rejoin, { label = "帧率下限", path = "rejoin.fpsThresh", min = 1, max = 60, default = 8 })
	kit:toggle(rejoin, { label = "延迟触发器", path = "rejoin.pingTrigger" })
	kit:input(rejoin, { label = "延迟上限 ms", path = "rejoin.pingThresh", min = 100, max = 5000, default = 800 })
	kit:button(rejoin, {
		label = "手动重进",
		role = "Yellow",
		onClick = function()
			local handle = services.rejoin
			if handle ~= nil then
				-- One call. Poking `state`/`triggered` from here coupled the page
				-- to Rejoin's internals and would have broken silently on any
				-- refactor of the state machine.
				handle:requestNow("手动")
			end
		end,
	})

	kit:section(page, "自我操作")
	local self_ops = kit:card(page)
	kit:dualButtons(self_ops, {
		label = "强制自杀",
		role = "Red",
		onClick = function()
			local character = services.character
			if character ~= nil then
				local humanoid = character:humanoid()
				if humanoid ~= nil then
					pcall(function()
						humanoid.Health = 0
					end)
				end
			end
		end,
	}, {
		label = "解除冻结",
		role = "Green",
		onClick = function()
			if teleport ~= nil then
				teleport:cancel()
			end
			if motion ~= nil then
				motion:unfreeze()
			end
		end,
	})

	--[[
		"强制归位" and "清空统计": both existed in V1007 and neither was carried
		over.

		归位 is the recovery for "I am stuck somewhere I cannot get out of": it
		releases the hold and puts the character back on the last position the
		motion kernel recorded as safe. 清空统计 zeroes the pull-back counters that
		the Teleport page displays, so a scary-looking total can be cleared once the
		cause is understood.
	]]
	kit:dualButtons(self_ops, {
		label = "强制归位",
		onClick = function()
			if teleport ~= nil then
				teleport:cancel()
			end
			if motion == nil then
				return
			end
			motion:unfreeze()
			local safe = motion:safePosition()
			if safe ~= nil and teleport ~= nil then
				-- hold = false: arrive and hand control straight back.
				teleport:walk(safe + Vector3.new(0, 5, 0), { mode = "tp", hold = false })
				shell:toast("已归位到安全点", "success")
			else
				shell:toast("还没有记录安全点（站稳几秒后会自动记录）", "warn")
			end
		end,
	}, {
		label = "清空统计",
		onClick = function()
			if motion ~= nil and motion.hold ~= nil then
				local stats = motion.hold.stats
				stats.pulled = 0
				stats.retries = 0
				stats.failures = 0
				shell:toast("被拉回统计已清空", "success")
			end
		end,
	})

	kit:section(page, "反挂机")
	local afk = kit:card(page)
	kit:slider(afk, {
		label = "触发间隔（秒）",
		path = "antiAfk.interval",
		min = 60,
		max = 1140,
		default = 300,
		commitOnly = true,
	})
	kit:note(afk, "另外已挂 Idled 事件，基本不会被判定挂机")

	--[[
		CONFIG SLOTS ("保存配置 / 切换配置").

		V1008 had one config file and no way to keep a second setup, so saving a
		new profile destroyed the old one. There are now 8 numbered slots; the name
		you type is stored INSIDE the file, so the filename never comes from user
		input (which is how a config system acquires a path-traversal bug).

		The slot list refreshes whenever one is written or read -- there is no
		watcher on the filesystem, so the read-out would otherwise keep showing
		the label a slot had when the page was built.
	]]
	local Persist = services.persist

	local section = kit:section(page, "配置存档")
	local slots = kit:card(page)

	local slotRow
	local slotNote
	local slotButtons

	--[[
		THE MASTER SWITCH, GATE THE SLOT CARD.

		Reading `cfg.saveEnabled` and storing whether the feature is available is
		not enough on its own: the switch above can be flipped at any moment, and
		the card has to answer immediately -- a card that still lists slots and
		still offers 保存 while the layer is disabled is the confusing half of
		this feature. Both the notice and every control are hidden together, and
		the notice says which of the two reasons applies.
	]]
	local SLOT_NOTE = "共 8 个存档位，可随时切换；读取后当前设置会被覆盖"

	local function applySaveGate()
		local enabled = kit.store:get("cfg.saveEnabled") ~= false
		local available = Persist ~= nil

		for _, object in ipairs({ section, slotNote, slotRow, slotButtons }) do
			if object ~= nil then
				object.Visible = available and enabled
			end
		end
		if available then
			if slotNote ~= nil then
				if enabled then
					slotNote.Text = SLOT_NOTE
				else
					-- The card is hidden, but "why did my config stop saving" needs
					-- an answer on the page itself. The note stays up with the reason.
					slotNote.Text = "功能存档已禁用：本次会话不写入任何配置（读取照常）"
					slotNote.Visible = true
				end
			end
			return
		end
		-- No filesystem at all: the notice stays up whatever the switch says.
		if slotNote ~= nil then
			slotNote.Text = "存档功能不可用：当前执行器没有文件读写接口"
			slotNote.Visible = true
		end
	end

	if Persist == nil then
		-- `slotNote` is what the gate above patches, so the no-filesystem notice
		-- has to BE that note. It used to be an anonymous `kit:note`, and the
		-- gate then wrote to a nil slotNote on this exact path.
		slotNote = kit:note(slots, "存档功能不可用：当前执行器没有文件读写接口")
	else
		local names = {}
		-- Forward-declared because the refresher is defined before the widget it
		-- drives exists, and it is only ever CALLED after that assignment.
		local slotDropdown

		local function currentSlot()
			local display = slotDropdown.get() or "1."
			local index = tonumber(string.match(display, "^%d+")) or 1
			return math.clamp(index, 1, Persist.SLOT_COUNT)
		end

		local function refreshSlots()
			--[[
				Rebuild the labels from disk, and RE-SEED THE TRIGGER with the
				label of the slot that is selected NOW.

				This is the reported bug: refresh used to keep the trigger's old
				text whenever the old text was no longer in the list -- and after
				saving into an empty slot, the old text ("1. （空）") is exactly
				what is no longer in the list. So the trigger kept saying the slot
				was empty until you opened the panel a second time and clicked an
				entry. Selecting by INDEX and taking that index's fresh label is
				what makes one save update the display immediately.
			]]
			local index = currentSlot()
			names = {}
			for position = 1, Persist.SLOT_COUNT do
				local label = Persist.slotLabel(position)
				table.insert(names, string.format("%d. %s", position, label or "（空）"))
			end
			slotDropdown.refresh(names, names[index] or names[1])
		end

		slotDropdown = kit:dropdown(slots, {
			label = "选择存档位",
			values = { "1. （空）" },
			default = "1. （空）",
			map = {
				toStore = function(display)
					return tonumber(string.match(display, "^%d+")) or 1
				end,
				fromStore = function(stored)
					return string.format("%d. %s", tonumber(stored) or 1, "（空）")
				end,
			},
		})
		slotRow = slotDropdown

		local labelBox = kit:textInput(slots, {
			label = "存档名",
			placeholder = "例如：锻炼配置",
			default = "",
		})

		local function saveCurrent()
			local index = currentSlot()
			local ok, err = Persist.saveSlot(kit.store, index, labelBox.Text)
			if ok then
				shell:toast(string.format("已保存到存档 %d", index), "success")
			else
				shell:toast("保存失败：" .. tostring(err), "error")
			end
			refreshSlots()
		end

		local function loadCurrent()
			local index = currentSlot()
			local report, err = Persist.loadSlot(kit.store, index)
			if report == nil then
				shell:toast("读取失败：" .. tostring(err), "warn")
				return
			end
			for _, warning in ipairs(report.warnings) do
				warn("[MKUltraHUB][slot] " .. warning)
			end
			shell:toast(string.format("已读取存档 %d", index), "success")
			refreshSlots()
		end

		local buttons = kit:dualButtons(
			slots,
			{ label = "保存到该存档位", role = "Green", onClick = saveCurrent },
			{ label = "读取该存档位", onClick = loadCurrent }
		)
		slotButtons = buttons

		slotNote = kit:note(slots, SLOT_NOTE)
		refreshSlots()
	end

	--[[
		The switch drives the card, and the card is re-asked at build time so a
		config restored with the feature already off opens in the right state.

		The subscription is on the store rather than on the toggle's handle:
		`kit:toggle` returns { get, set } and no way to observe a flip, and the
		switch can also be moved by a loaded slot or a config migration.
	]]
	kit:track(kit.store:subscribe("cfg.saveEnabled", function()
		applySaveGate()
	end))
	applySaveGate()
end

return Page
end

__modules["ui/Pages/Theme"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
-- The theme page: clicking a theme only writes `uiState.theme`. The shell
-- subscribes to that key and repaints, which is why the selected marker here is
-- driven by a binding rather than by the click handler.

local Theme = require("ui/Theme")
local Attributes = require("core/Attributes")

local Page = {}

Page.id = "theme"
Page.label = "主题"

local CHOICES = {
	{ key = "light", label = "默认亮色" },
	{ key = "dark", label = "深色模式" },
	{ key = "ocean", label = "深海蓝" },
	{ key = "sakura", label = "樱花粉" },
	{ key = "forest", label = "森林绿" },
	{ key = "flame", label = "烈焰红" },
}

Page.build = function(kit, page, shell)
	kit:section(page, "选择主题")
	local card = kit:card(page)
	kit:note(card, "切换主题只把颜色补间过去，不重建界面，也不会中断脚本运行")

	local grid = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = kit:nextOrder(card),
	}, card)
	kit:instance("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 40),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	local buttons = {}
	for index, choice in ipairs(CHOICES) do
		local button = kit:instance("TextButton", {
			LayoutOrder = index,
			BackgroundColor3 = kit:color("White"),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = choice.label,
			TextColor3 = kit:color("TextPrimary"),
			TextSize = 13,
		}, grid)
		kit:corner(button, 6)
		kit:stroke(button, kit:color("Border"), 1, 0)
		kit:animate(button, kit:color("White"))
		buttons[choice.key] = button

		kit:track(button.MouseButton1Click:Connect(function()
			kit.store:set("uiState.theme", choice.key)
		end))
	end

	-- The selected marker follows the store, so it is correct on load and after a
	-- change made anywhere else; the initial paint snaps so the page does not
	-- visibly "select" its theme as it opens. Every button is re-rendered from
	-- one function, and the resting colour is re-asserted here so a hovered
	-- button cannot keep a stale colour and show several "selected" at once.
	local function render(active, initial)
		for _, choice in ipairs(CHOICES) do
			local button = buttons[choice.key]
			if button ~= nil then
				local selected = choice.key == active
				local base = if selected then kit:color("Green") else kit:color("White")
				local textColor = if selected then kit:color("White") else kit:color("TextPrimary")
				-- Keep the hover path's resting colour in step, or the next
				-- mouse-leave puts this button back to the OLD theme's colour.
				button:SetAttribute(Attributes.BASE_COLOR, base)
				button.Text = choice.label .. (if selected then "  ✓" else "")
				if initial == true then
					button.BackgroundColor3 = base
					button.TextColor3 = textColor
				else
					kit:tween(button, 0.2, {
						BackgroundColor3 = base,
						TextColor3 = textColor,
					})
				end
			end
		end
	end

	kit:bind("uiState.theme", "light", render)

	kit:section(page, "预览")
	local preview = kit:card(page)
	kit:note(preview, "下面这排色块就是当前主题的全部角色色")

	local strip = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = kit:nextOrder(preview),
	}, preview)
	kit:list(strip, 4, true)

	local squares = {}
	for index, role in ipairs(Theme.ROLES) do
		local square = kit:instance("Frame", {
			Size = UDim2.new(1 / #Theme.ROLES, -4, 1, 0),
			BackgroundColor3 = kit:color(role),
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, strip)
		kit:corner(square, 4)
		squares[role] = square
	end

	-- The colour strip is rebuilt from the palette whenever the theme changes,
	-- because these swatches have no colour in the remap to be found by.
	local function renderSwatches(name, initial)
		local roles = Theme.roles(name)
		kit.roles = roles
		for role, square in pairs(squares) do
			local color = roles[role]
			if color ~= nil then
				if initial == true then
					square.BackgroundColor3 = color
				else
					kit:tween(square, 0.3, { BackgroundColor3 = color })
				end
			end
		end
	end

	kit:bind("uiState.theme", "light", renderSwatches)

	-- The final word on this page's own colours ("仍然残存绿色"): the shell bumps
	-- `uiState.themeEpoch` once its repaint tweens have landed, and this re-asserts
	-- every button and swatch with SNAPS (not tweens) so nothing can overwrite
	-- them afterwards.
	kit:track(kit.store:subscribe("uiState.themeEpoch", function()
		local active = kit.store:get("uiState.theme")
		render(active, true)
		renderSwatches(active, true)
	end))
end

return Page
end

__modules["main"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Entry point of the bundled script.

	This module owns the LIFECYCLE. Every subsystem is installed into one session
	in a fixed order and torn down the same way:

	    store      <- defaults, then the saved file (validated + migrated)
	    net        <- channels, each with its own limiter and counters
	    runtime    <- the single heartbeat + the single pre-render hook
	    character  <- event-driven player model tracking
	    motion     <- the anti-pullback kernel (uses character + store)
	    teleport   <- stepped movement (uses motion + timers)
	    train      <- the first migrated subsystem

	V1007 had no such thing. Each subsystem was constructed wherever it was first
	needed, connections were collected into two global arrays, and "destroy" was a
	long hand-written list of things to undo -- which is why missing a step (a
	pending task.delay, an anchored root, a resized target) was routine.

	Loading this module IS the instruction to run it: the file ends by calling
	`Main.start()` under pcall (see "Auto-start" at the bottom). `Main.stop()` and
	`Main.unfreeze()` stay exposed as the manual escape hatches.
]]

local Players = game:GetService("Players")

local Format = require("core/Format")
local Signal = require("core/Signal")
local RateLimiter = require("core/RateLimiter")
local Store = require("core/Store")
local Config = require("core/Config")
local Path = require("core/Path")
local Timers = require("core/Timers")
local Scheduler = require("core/Scheduler")
local Net = require("core/Net")
local TrainRate = require("core/TrainRate")
local Hold = require("core/Hold")
local Keyword = require("core/Keyword")
local Targeting = require("core/Targeting")
local BossInfo = require("core/BossInfo")
local ChestTimer = require("core/ChestTimer")
local SizePolicy = require("core/SizePolicy")
local RepBonus = require("core/RepBonus")
local PetPlan = require("core/PetPlan")
local MachinePlan = require("core/MachinePlan")
local MountState = require("core/MountState")
local RebirthState = require("core/RebirthState")
local PackState = require("core/PackState")
local RejoinTriggers = require("core/RejoinTriggers")
local ServerPick = require("core/ServerPick")
local Metrics = require("core/Metrics")
local Palette = require("core/Palette")
local Arbiter = require("core/Arbiter")

local Runtime = require("game/Runtime")
local Character = require("game/Character")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")
local Persist = require("game/Persist")
local Platforms = require("game/Platforms")
local Motion = require("game/Motion")
local Teleport = require("game/Teleport")
local Tools = require("game/Tools")
local Combat = require("game/Combat")
local Boss = require("game/Boss")
local Size = require("game/Size")
local Pets = require("game/Pets")
local Crystals = require("game/Crystals")
local PetMetrics = require("game/PetMetrics")
local Machine = require("game/Machine")
local PlayerStats = require("game/PlayerStats")
local Rebirth = require("game/Rebirth")
local GameMetrics = require("game/Metrics")
local Rejoin = require("game/Rejoin")
local AntiAfk = require("game/AntiAfk")
local Perf = require("game/Perf")
local Train = require("game/Train")

local Theme = require("ui/Theme")
local Kit = require("ui/Kit")
local Shell = require("ui/Shell")
local Toast = require("ui/Toast")
local InfoWindow = require("ui/InfoWindow")
local Announce = require("ui/Announce")
local TrainPage = require("ui/Pages/Train")
local TeleportPage = require("ui/Pages/Teleport")
local RebirthPage = require("ui/Pages/Rebirth")
local KillPage = require("ui/Pages/Kill")
local BossPage = require("ui/Pages/Boss")
local PetsPage = require("ui/Pages/Pets")
local SettingsPage = require("ui/Pages/Settings")
local ThemePage = require("ui/Pages/Theme")

local Main = {
	version = "V1011",
}

--[[
	The global handle, and the stale-build cleanup that goes with it.

	V1007 published `_G[<PLUGIN_ID>]` and, on a re-run, first asked the previous
	instance to clean itself up and destroyed the previous ScreenGuis by name
	(`MK_V1000`, `MK_V1000_INFO`, `MK_V1007`, `MK_V1007_INFO`). Re-running a
	script without that leaves the old interface stacked on top of the new one
	with both frame loops running -- two copies of every task, one of them
	invisible and unreachable.

	`PLUGIN_ID` is deliberately the old one: a user reloading the new build over a
	running old build should still get the old one cleaned up.
]]
Main.PLUGIN_ID = "__MKUltraHUB_V1007__"
Main.STALE_GUI_NAMES = { "MK_V1000", "MK_V1000_INFO", "MK_V1007", "MK_V1007_INFO", "MKUltraHUB" }

--[[
	The `getgenv()` table is not always writable.

	The smoke harness freezes it on purpose (to model an executor that returns a
	read-only table), and the real thing varies by executor. Every access is
	therefore guarded: publishing the handle is a convenience, and failing to
	publish it must never take the boot down with it. This exact write crashed
	the boot the first time it was tried.
]]
local function environment()
	local ok, env = pcall(function()
		return (type(getgenv) == "function" and getgenv()) or _G
	end)
	if ok and type(env) == "table" then
		return env
	end
	return nil
end

local function environmentRead(key)
	local env = environment()
	if env == nil then
		return nil
	end
	local ok, value = pcall(function()
		return env[key]
	end)
	if ok then
		return value
	end
	return nil
end

local function environmentWrite(key, value)
	local env = environment()
	if env == nil then
		return false
	end
	local ok = pcall(function()
		env[key] = value
	end)
	return ok
end

--[[
	Ask a previous instance to stop, then destroy anything it left behind.

	Called BEFORE the new interface is built. Every step is best-effort: a
	previous build that does not expose `cleanup` is still cleaned up by name.
]]
function Main.cleanupPrevious()
	local previous = environmentRead(Main.PLUGIN_ID)
	if type(previous) == "table" and type(previous.cleanup) == "function" then
		pcall(previous.cleanup)
	end
	environmentWrite(Main.PLUGIN_ID, nil)

	local player = Players.LocalPlayer
	local playerGui = player ~= nil and player:FindFirstChild("PlayerGui") or nil
	if playerGui == nil then
		return
	end
	for _, name in ipairs(Main.STALE_GUI_NAMES) do
		local stale = playerGui:FindFirstChild(name)
		while stale ~= nil do
			pcall(function()
				stale:Destroy()
			end)
			stale = playerGui:FindFirstChild(name)
		end
	end
end

Main.core = {
	Format = Format,
	Signal = Signal,
	RateLimiter = RateLimiter,
	Store = Store,
	Config = Config,
	Path = Path,
	Timers = Timers,
	Scheduler = Scheduler,
	Net = Net,
	TrainRate = TrainRate,
	Hold = Hold,
	Keyword = Keyword,
	Targeting = Targeting,
	BossInfo = BossInfo,
	ChestTimer = ChestTimer,
	SizePolicy = SizePolicy,
	RepBonus = RepBonus,
	PetPlan = PetPlan,
	MachinePlan = MachinePlan,
	MountState = MountState,
	RebirthState = RebirthState,
	PackState = PackState,
	RejoinTriggers = RejoinTriggers,
	ServerPick = ServerPick,
	Metrics = Metrics,
	Palette = Palette,
}

Main.ui = {
	Theme = Theme,
	Kit = Kit,
	Shell = Shell,
	Toast = Toast,
	InfoWindow = InfoWindow,
	Announce = Announce,
	Pages = {
		Train = TrainPage,
		Teleport = TeleportPage,
		Rebirth = RebirthPage,
		Kill = KillPage,
		Boss = BossPage,
		Pets = PetsPage,
		Settings = SettingsPage,
		Theme = ThemePage,
	},
}

Main.game = {
	Runtime = Runtime,
	Character = Character,
	Net = GameNet,
	Remotes = Remotes,
	Persist = Persist,
	Platforms = Platforms,
	Motion = Motion,
	Teleport = Teleport,
	Tools = Tools,
	Combat = Combat,
	Boss = Boss,
	Size = Size,
	Pets = Pets,
	PetMetrics = PetMetrics,
	Machine = Machine,
	PlayerStats = PlayerStats,
	Rebirth = Rebirth,
	Metrics = GameMetrics,
	Rejoin = Rejoin,
	AntiAfk = AntiAfk,
	Train = Train,
}

-- How often the config is written. The EFFECTIVE interval is `cfg.saveSeconds`
-- (default 10, user-settable); this constant is only the poll that honours it.
-- See the autosave timer in Main.start.
Main.SAVE_POLL_SECONDS = 1
Main.METRICS_SECONDS = 5
-- Interval for the explicit collectgarbage hint (V1007 used 120 s).
Main.GC_SECONDS = 120
-- Minimum seconds between two warnings for the same failure source. See the
-- throttle built in Main.start.
Main.LOG_THROTTLE_SECONDS = 5
Main.session = nil

-- Objects a boot creates before it can finish. `Main.start` builds a Heartbeat
-- connection, task registrations, timers and event connections well before it
-- produces a session to hand back; if a later step throws, `Main.session` is
-- never set, so `Main.stop()` has nothing to clean up and the runtime keeps
-- ticking invisibly for the rest of the session. These handles let `Main.abort`
-- roll the failed boot back.
Main._runtime = nil
Main._character = nil

--[[
	Bring the script up. Returns the session; calling it twice returns the same
	session rather than stacking a second frame loop.
]]
function Main.start()
	if Main.session ~= nil then
		return Main.session
	end

	-- Before anything is built: stop a previous instance and clear its interface.
	Main.cleanupPrevious()

	local toastRef = nil
	--[[
		NOTHING IS DROPPED BEFORE THE TOAST STACK EXISTS.

		`toastRef` is nil for the whole boot: the stack needs the screen, and the
		screen is built last. Every subsystem installed before that reported into
		nothing -- which is part of the user's "很多东西的通知气泡消失了". Messages
		raised during the boot are buffered here and flushed once the stack is up.
	]]
	local pendingToasts = {}

	-- One place that turns a subsystem message into console output plus a toast.
	-- Defined first because the early subsystems below already need it.
	local function notify(source)
		return function(message, kind, duration)
			local text = string.format("[%s] %s", source, tostring(message))
			if kind == "warn" or kind == "error" then
				warn("[MKUltraHUB] " .. text)
			else
				print("[MKUltraHUB] " .. text)
			end
			--[[
				Isolated on purpose.

				`notify` is called from inside subsystem code -- including from
				catch handlers that are already reporting a failure. V1007's
				`Core.notify` pcall'd its implementation and logged, and that is
				not decoration: an error thrown while building a toast would
				otherwise propagate back into the subsystem that reported the
				problem, turning a recoverable warning into a second failure (and,
				where the caller is a scheduler tick, into the task being counted
				as failed).
			]]
			if toastRef == nil then
				-- Bounded: a boot that fails in a loop must not grow this forever.
				if #pendingToasts < 20 then
					table.insert(pendingToasts, { text = text, kind = kind, duration = duration })
				end
				return
			end
			local ok, err = pcall(Toast.show, toastRef, text, kind, duration)
			if not ok then
				warn("[MKUltraHUB][ui] toast failed: " .. tostring(err))
			end
		end
	end

	local store = Store.new()
	store:load(Config.defaults())

	local configReport = Persist.load(store)
	for _, warning in ipairs(configReport.warnings) do
		warn("[MKUltraHUB][config] " .. warning)
	end

	local net = Net.new({
		onError = function(channel, message)
			warn(string.format("[MKUltraHUB][net:%s] %s", channel, message))
		end,
	})

	--[[
		ONE arbiter for the whole session.

		It is the shared answer to "who is claiming the body right now", and it
		must be the same object for every subsystem -- two arbiters would each
		believe they were alone and the machine would never step aside. It is
		created before the runtime so the subsystems installed below can all be
		handed the same handle.
	]]
	local arbiter = Arbiter.new()
	local lastArbiterReason = nil
	arbiter.onChange = function(flag, up, by)
		if not up then
			return
		end
		-- Reported once per transition, not once per frame: the whole point of
		-- the arbiter's counted holds is that a transition is a meaningful edge.
		local _, reason = Arbiter.capOf(arbiter:state())
		if reason ~= lastArbiterReason then
			lastArbiterReason = reason
			warn(string.format("[MKUltraHUB][arbiter] %s 已接管（%s），锻炼降深至%s",
				by or flag, reason or flag, Arbiter.LABELS[Arbiter.Depth.BODY]))
		end
	end

	--[[
		Throttled diagnostic logging.

		V1007 kept a per-key log throttle (`Core.logErr`) in front of its error
		path. Without one, a task that throws on every tick writes a warning every
		frame -- which is both a real performance cost (string formatting plus
		console I/O per frame) and useless to read, because the useful information
		is "this is happening repeatedly", not the ten thousandth copy.

		Five seconds per key, and the suppressed count is reported when the window
		reopens so nothing is silently hidden.
	]]
	local logKeys: { [string]: { at: number, suppressed: number } } = {}
	local function throttled(source, message)
		local now = os.clock()
		local entry = logKeys[source]
		if entry == nil then
			logKeys[source] = { at = now, suppressed = 0 }
			warn(string.format("[MKUltraHUB][%s] %s", source, message))
			return
		end
		entry.suppressed += 1
		if now - entry.at < Main.LOG_THROTTLE_SECONDS then
			return
		end
		local extra = if entry.suppressed > 1
			then string.format("（另有 %d 条同类错误被折叠）", entry.suppressed - 1)
			else ""
		entry.at = now
		entry.suppressed = 0
		warn(string.format("[MKUltraHUB][%s] %s%s", source, message, extra))
	end

	local runtime = Runtime.new({
		net = net,
		onError = throttled,
	})
	-- Published immediately: from this line on, the Heartbeat connection exists,
	-- so a failure later in the boot must be able to find and destroy it.
	Main._runtime = runtime

	local player = Players.LocalPlayer

	--[[
		Say so when there is no LocalPlayer.

		The whole interface branch below is guarded on `player ~= nil` (it has to
		be: every panel and page resolves services against the local character).
		On a slow join `LocalPlayer` can still be nil when an executor runs the
		script, and the previous behaviour was to skip the UI SILENTLY -- the
		modules load, the frame loop starts, nothing appears, and there is no
		message anywhere explaining why. One explicit warning turns an
		unexplainable "the script does nothing" into a diagnosable condition.
	]]
	if player == nil then
		warn("[MKUltraHUB] 本地玩家尚未就绪：界面与角色相关功能本次加载被跳过，请重新执行脚本")

		--[[
			Retry the boot once the player appears.

			A warning alone tells the user what happened but does not FIX it, and
			re-running the script by hand is exactly the burden this should remove.
			The retry is a timer rather than a wait, so the boot still returns
			immediately and anything that does not need the character (the frame
			loop, the config autosave) is already running.

			A newer local named `scheduleRetry` is deliberately NOT used: this runs
			before the runtime exists, so it uses `task.delay`, and the rebuilt
			boot re-registers everything through the same path as a manual reload.
		]]
		task.delay(2, function()
			if Players.LocalPlayer == nil or Main.session ~= nil then
				return
			end
			--[[
				`abort`, not `stop`. This boot never produced a session (that is
				why the retry exists), so `Main.stop()` is a no-op and the second
				`Main.start()` would stack a second runtime, heartbeat and task
				set on top of the first. `Main.abort` tears down the half-built
				boot, which is what makes the retry a restart rather than a
				duplicate.
			]]
			local ok, err = pcall(function()
				Main.abort()
				Main.start()
			end)
			if not ok then
				warn("[MKUltraHUB] 重试启动失败：" .. tostring(err))
			end
		end)
	end

	local character = nil
	local motion = nil
	local teleport = nil
	local boss = nil
	local size = nil
	local infoWindow = nil
	local combat = nil
	local machine = nil
	local pets = nil

	--[[
		"IS THE BOSS TASK FIGHTING", as opposed to "is auto-boss switched on" or
		even "is a boss on the map".

		Declared HERE, outside the `if character` block that installs Boss,
		because the training task below is installed unconditionally and asks the
		same question.

		The machine and the training task both step aside for a boss fight, and
		they were wired to `bossAlive` -- which is true the whole time a boss
		exists, including while the player is parked on a gym machine doing
		nothing about it. That is the deadlock behind the reported "明明启用了器
		械，就是不上". `Boss.stats().engaged` is published by Boss.approach, the
		task that owns the body during a fight, so this is the boss subsystem's own
		answer to "am I holding the character", with no second source of truth.
	]]
	local function bossEngaged()
		if boss == nil then
			return false
		end
		return Boss.stats(boss).engaged == true
	end
	local rebirth = nil
	local teleportRef = nil

	--[[
		THE ONE ANSWER TO "may I move the character?".

		The scheduler decides it per frame from the registered tasks' priorities
		(see core/Scheduler.claim); this closure is the shape the moving
		subsystems consume through `Motion`. Keeping it here rather than in
		Motion means the body slot stays one implementation, wired in one place,
		and a module that is not a scheduler task (a timer, a UI button) still
		moves freely because an unregistered id always gets the body.
	]]
	local function motionClaim(job: string): (boolean, string?)
		return runtime.scheduler:claim(job)
	end

	-- Sampling and rejoining do not need a character: the rejoin triggers and the
	-- info window both read the metrics, so they start first.
	local sessionStart = os.clock()
	local metrics = GameMetrics.install({ scheduler = runtime.scheduler })

	local perf = Perf.install({ store = store, scheduler = runtime.scheduler })

	-- Crystals is installed here (not inside the character block) because it needs
	-- nothing but the store and the scheduler: opening a crystal and pushing the
	-- auto-sell list are remote calls, not character work.
	local crystals = Crystals.install({
		store = store,
		scheduler = runtime.scheduler,
		timers = runtime.timers,
		-- The ping scales the give-up timeout: on a 1000 ms link a fixed 3 s
		-- guard expires on calls that are merely slow (see game/Crystals).
		metrics = metrics,
		notify = notify("crystal"),
	})

	-- The pause switch is a store key rather than a special-case call, so the
	-- settings toggle and any future keybind drive the same thing.
	runtime.scheduler:setPaused(store:get("runtime.paused") == true)
	store:subscribe("runtime.paused", function(_, value)
		runtime.scheduler:setPaused(value == true)
	end)

	local rejoin = Rejoin.install({
		store = store,
		scheduler = runtime.scheduler,
		timers = runtime.timers,
		metrics = metrics,
		notify = notify("rejoin"),
	})

	local antiAfk = AntiAfk.install({
		store = store,
		scheduler = runtime.scheduler,
		timers = runtime.timers,
		runtime = runtime,
		-- The kick detector drives the URGENT rejoin path, which is why Rejoin is
		-- installed first.
		rejoin = rejoin,
	})

	if player ~= nil then
		character = Character.new(player)
		-- Published for the same reason as the runtime: it owns event
		-- connections that must be dropped if the boot fails.
		Main._character = character
		motion = Motion.new({
			character = character,
			store = store,
			claim = motionClaim,
			onLost = function(attempt)
				warn(string.format("[MKUltraHUB][motion] pulled back, retry %d", attempt))
			end,
			onGiveUp = function(attempt)
				-- cfg.tpFallback: after the retries run out, go back to a position
				-- that is known to be safe rather than sitting somewhere the server
				-- keeps rejecting.
				local safe = motion:safePosition()
				if store:get("cfg.tpFallback") == true and safe ~= nil and teleportRef ~= nil then
					teleportRef:walk(safe, { mode = "tp", hold = false })
				else
					warn(string.format("[MKUltraHUB][motion] gave up after %d retries", attempt))
				end
			end,
		})
		teleport = Teleport.install({
			character = character,
			store = store,
			motion = motion,
			timers = runtime.timers,
			scheduler = runtime.scheduler,
			--[[
				BOSS OUTRANKS MOVEMENT, but the boss task is not asked about here
				any more: the live answer is the body slot (`bodyOwner` below),
				which is the activity that actually moved the character last
				frame. `isBossFight` -- "a boss model exists" -- kept the loop off
				for the whole session the moment one spawned.
			]]
			--[[
				THE MACHINE'S LIVE PHASE, and WHO ELSE HOLDS THE BODY.

				Both exist for one reason: "循环传送" (priority 80) writes the
				character's CFrame 40 times a second and used to do it while a
				chest (430), a boss approach (410) or a seat mount (90) was
				already driving the same character -- the last writer of the frame
				won, so the highest-priority task was the one that lost. The loop
				now asks these two questions and stands down; they are closures so
				that Teleport (installed before Machine and after the scheduler)
				reads them late.
			]]
			machinePhase = function()
				if machine == nil then
					return nil
				end
				return machine:stats().phase
			end,
			bodyOwner = function()
				return runtime.scheduler:bodyOwner()
			end,
		})
		teleportRef = teleport

		-- Record a safe position periodically. Only taken while nothing is being
		-- held: a position the server is rejecting is not somewhere to fall back to.
		runtime.timers:every(os.clock(), 3, function()
			motion:markSafe()
		end)

		--[[
			Model-drift watchdog.

			V1007 checked every second while no hold was active; the refactor only
			measured drift while HOLDING, so an idle or walking character whose
			model had come apart was never measured and never repaired. The
			notice is rate-limited inside Motion so a persistent separation cannot
			flood the log.
		]]
		runtime.timers:every(os.clock(), 1, function()
			motion:watchDrift(os.clock())
		end)

		--[[
			OUT-OF-MAP RESCUE.

			V1007 ran a watchdog that teleported the player back to the last
			recorded safe point whenever they fell out of the world (below a
			Y threshold), and it deliberately skipped while a teleport was in
			flight so it could not fight the teleport it was watching. The
			refactor kept `markSafe` and `safePosition` and dropped the watchdog,
			so a player who fell through the map stayed there.

			`Motion.markSafe` already refuses to record anything below Y = -50,
			which is what makes "below -50" a reliable definition of "out of the
			world": the saved point can never itself be out there.
		]]
		runtime.timers:every(os.clock(), 1, function()
			local root = character:requireRoot()
			if root == nil then
				return
			end
			local ok, position = pcall(function()
				return root.Position
			end)
			if not ok or typeof(position) ~= "Vector3" or position.Y >= -50 then
				return
			end

			--[[
				THE RESCUE MUST NOT BE STARVED, and it must work more than once.

				Two defects, both reported as "掉虚空自动拉回永远只能触发一次":

				  * it returned early whenever ANY walk was in flight. The chest
				    task and the boss pin both keep walks going, so in practice the
				    rescue usually found `isBusy()` true and never fired at all --
				    and after the one time it did fire, the walk it started made
				    `isBusy()` true again for as long as the character kept
				    falling. A character in the void outranks a pending walk, so
				    the walk is CANCELLED rather than waited for.
				  * when no safe point had been recorded yet (`markSafe` refuses
				    while a hold is active, and a boss fight holds almost
				    continuously) there was nothing to fall back to and the rescue
				    simply gave up. The Hallowed Gym / lobby coordinate is a
				    destination that always exists.

				The 1-second cadence and the explicit cancel also mean the rescue
				re-arms itself every second instead of depending on a state that
				the rescue's own walk happens to set.
			]]
			if teleport ~= nil then
				pcall(function()
					teleport:cancel()
				end)
			end
			local safe = motion:safePosition()
			if safe == nil then
				-- 万圣节健身房 as the last resort: it is where the seasonal bosses
				-- are, so a player pulled out of the void lands somewhere usable
				-- rather than at whatever stale coordinate was left over.
				safe = Vector3.new(5505.53, 96.32, 5893.50)
			end
			warn("[MKUltraHUB][motion] 掉出地图，已送回安全点")
			teleport:walk(safe + Vector3.new(0, 5, 0), { mode = "tp", hold = false })
		end)
		-- The position override must run pre-render, and it must be the Runtime
		-- that owns the connection.
		runtime:connectPreRender(function(now)
			motion:tick(now)
		end)

		--[[
			Pets is installed BEFORE Boss, Combat and Train.

			All three switch the pet preset as their task starts and stops, so all
			three need the service at construction. Installing Pets first is the
			cheapest way to keep that honest -- the alternative (a late setter, or
			a lazy lookup inside each task) reintroduces exactly the ordering
			dependency this ordering removes. Pets itself only needs the store,
			the net, the scheduler, the timers and the character, all of which
			already exist here.
		]]
		pets = Pets.install({
			store = store,
			net = net,
			scheduler = runtime.scheduler,
			timers = runtime.timers,
			character = character,
			notify = notify("pets"),
		})

		boss = Boss.install({
			store = store,
			scheduler = runtime.scheduler,
			character = character,
			motion = motion,
			teleport = teleport,
			timers = runtime.timers,
			pets = pets,
			--[[
				The post-event server hop needs two services that already exist
				here: Rejoin (installed far above, before the character) and the
				persistence module (pure, and stateless between calls). Both are
				captured BY VALUE -- unlike `size` below, neither is installed
				later, so there is no ordering trap to work around.
			]]
			rejoin = rejoin,
			persist = Persist,
			-- A late-bound getter: Size is installed AFTER Boss, so capturing the
			-- service here would capture nil. The closure reads the upvalue at
			-- call time, which is only ever during Boss.leave.
			size = function()
				return size
			end,
			--[[
				The machine, for the same late-binding reason: `Machine` is
				installed after Boss and Combat, and while the machine holds the
				seat (which only happens when the user let it win via
				machine.overridesCombat) the fight must not pin the body off it.
			]]
			machineSeated = function()
				return machine ~= nil and Machine.isSeated(machine)
			end,
			notify = notify("boss"),
		})

		-- Both Combat and Size need to know whether a boss is up. Injecting the
		-- predicate (instead of letting them reach for a global) is what keeps the
		-- three subsystems independent and the coupling visible.
		local function bossAlive()
			return Boss.isAlive(boss)
		end

		size = Size.install({
			store = store,
			scheduler = runtime.scheduler,
			isBossAlive = bossAlive,
		})

		combat = Combat.install({
			store = store,
			scheduler = runtime.scheduler,
			character = character,
			motion = motion,
			-- The 0.025 s pin for player targets (independent timer from the boss's).
			teleport = teleport,
			-- See Boss.install: the machine is installed after Combat, so this is
			-- a late-bound getter rather than a captured value.
			machineSeated = function()
				return machine ~= nil and Machine.isSeated(machine)
			end,
			net = net,
			arbiter = arbiter,
			pets = pets,
			isBossAlive = bossAlive,
			-- The damage hold and the boss punch both ask "are we FIGHTING the
			-- boss", not "does one exist": a boss idling across the map used to
			-- keep the machine blocked and the punch firing from anywhere.
			isBossEngaged = bossEngaged,
			-- Where the tracked rig is, so the punch can refuse to fire from a
			-- gym machine on the other side of the map (see Combat.bossInReach).
			bossPosition = function()
				return Boss.livePosition(boss)
			end,
			notify = notify("combat"),
		})

		machine = Machine.install({
			store = store,
			net = net,
			scheduler = runtime.scheduler,
			timers = runtime.timers,
			character = character,
			-- One-frame placement on the seat (`Teleport.snap`), so the machine
			-- mount does not have to hover its way over.
			teleport = teleport,
			isCombatBusy = function()
				return combat ~= nil and Combat.engaged(combat)
			end,
			--[[
				The depth question, answered by the module that decides whether
				anything needs to hit: while this is true the machine releases
				the seat, and when it goes false the mount resumes on its own.

				It also keeps the shared `damage` hold current. That is not a
				side effect for convenience: this predicate is asked every frame
				by the machine, which makes it the one place guaranteed to run
				while a fight is happening, and the hold must be up before the
				machine decides. The dedicated `damageHold` task in Combat covers
				the frames where the machine task itself is disabled.
			]]
			isDamageNeeded = function()
				return Combat.maintainDamageHold(combat)
			end,
			isBossAlive = bossEngaged,
			notify = notify("machine"),
		})

		rebirth = Rebirth.install({
			store = store,
			net = net,
			scheduler = runtime.scheduler,
			pets = pets,
			isBossAlive = bossAlive,
			notify = notify("rebirth"),
		})
	end

	local train = Train.install({
		store = store,
		net = net,
		scheduler = runtime.scheduler,
		runtime = runtime,
		character = character,
		-- The training preset ("train") is switched by the same auto-switch that
		-- the rebirth path already uses; without it this preset had no trigger.
		pets = pets,
		arbiter = arbiter,
		-- `engaged` rather than the raw switch: "开了杀戮" capped the training
		-- task for the whole session, which is the same phantom hold the machine
		-- was blocked by (see Combat.engaged).
		isCombatBusy = function()
			return combat ~= nil and Combat.engaged(combat)
		end,
		-- A boss is only worth standing down training for while the boss task is
		-- actually holding the body (see bossEngaged above).
		isBossAlive = bossEngaged,
		isMachineBusy = function()
			if machine == nil then
				return false
			end
			local phase = machine:stats().phase
			return phase == "mounting" or phase == "mounted"
		end,
		notify = notify("train"),
	})

	--[[
		THE AUTOSAVE IS A 1 Hz POLL, NOT A FIXED-RATE TIMER.

		The requirement is "every 10 seconds by default, and once immediately when
		the script is closed". A `timers:every(10, ...)` cannot honour a changed
		interval without being torn down and re-registered, and it also cannot
		express "10 s since the last ACTUAL write" -- which is what the user means,
		since the tracker skips writes when nothing persistable changed.

		A 1 Hz tick that compares `now - lastSave` against `cfg.saveSeconds` costs
		nothing measurable (one number comparison) and makes the setting take
		effect on the next second. The close-side save already lives in
		`session.stop`, which is the "immediately when closing" half.
	]]
	local saveTracker = Persist.tracker(store)
	local lastSave = os.clock()
	runtime.timers:every(os.clock(), Main.SAVE_POLL_SECONDS, function()
		local interval = tonumber(store:get("cfg.saveSeconds")) or 10
		if interval < 3 then
			interval = 3
		end
		local now = os.clock()
		if now - lastSave < interval then
			return
		end
		lastSave = now
		local ok, err = Persist.save(store, saveTracker)
		if not ok then
			warn("[MKUltraHUB][config] save failed: " .. tostring(err))
		end
	end)

	--[[
		Periodic garbage-collect hint.

		V1007 ran this in its always-on save task (every 120 s). A long session
		accumulates pricey short-lived objects (tween info, cframe/pivot temporaries,
		the per-frame tables in this script), and an explicit collectgarbage step on
		a slow timer is far cheaper than the alternative, which is the collector
		choosing a bad moment during a fight. Best-effort: `collectgarbage` is not
		available in every executor, and a missing one is not an error.
	]]
	if type(collectgarbage) == "function" then
		runtime.timers:every(os.clock(), Main.GC_SECONDS, function()
			pcall(collectgarbage)
		end)
	end

	-- Pet bonus figures change slowly (a pet gets equipped, an upgrade is
	-- bought), so this is a timer rather than a per-frame task. The scan itself
	-- is what walks the object tree; keeping it off the frame path matters.
	local petMetrics = PetMetrics.new()
	runtime.timers:every(os.clock(), Main.METRICS_SECONDS, function()
		PetMetrics.scan(petMetrics)
	end)

	-- --------------------------------------------------------------- interface --
	-- Built last, once every service a page might reach for exists. Pages are
	-- registered before build() so the shell can create their frames and nav
	-- buttons in one pass.
	local kit = nil
	local shell = nil
	if player ~= nil then
		kit = Kit.new({
			store = store,
			roles = Theme.roles(store:get("uiState.theme") or "light"),
			-- Delayed UI callbacks then go through the runtime's cancellable
			-- Timers instead of raw task.delay, so destroy() is a full teardown.
			timers = runtime.timers,
		})
		shell = Shell.new({
			store = store,
			kit = kit,
			version = Main.version,
			notify = notify("ui"),
			timers = runtime.timers,
			-- The status bar lists what the scheduler is actually running.
			scheduler = runtime.scheduler,
			services = {
				character = character,
				motion = motion,
				teleport = teleport,
				boss = boss,
				combat = combat,
				machine = machine,
				pets = pets,
				crystals = crystals,
				rebirth = rebirth,
				metrics = metrics,
				rejoin = rejoin,
				antiAfk = antiAfk,
				perf = perf,
				train = train,
				petMetrics = petMetrics,
				-- The settings page drives the numbered config slots through this.
				persist = Persist,
				uptime = function()
					return os.clock() - sessionStart
				end,
			},
			onClose = function()
				Main.stop()
			end,
		})
		--[[
			Registration order IS the nav-rail order.

			V1007's TABS ran 锻炼 / 传送 / 重生 / 杀戮 / 宠物 / Boss / 主题 / 设置, so
			宠物 came before Boss and 主题 before 设置. Registering in a different
			order put the same eight pages in a different sequence, which is the
			kind of difference a returning user reads as "the tab moved", not as
			"the order changed".
		]]
		Shell.registerPage(shell, TrainPage)
		Shell.registerPage(shell, TeleportPage)
		Shell.registerPage(shell, RebirthPage)
		Shell.registerPage(shell, KillPage)
		Shell.registerPage(shell, PetsPage)
		Shell.registerPage(shell, BossPage)
		Shell.registerPage(shell, ThemePage)
		Shell.registerPage(shell, SettingsPage)
		Shell.build(shell)

		-- The info window shares the shell's screen, so the shell has to be able
		-- to tell it when the main window changes shape. The panel is built
		-- further down (it needs the shell first), so the link is a callback that
		-- stays nil until then and is skipped harmlessly before that.
		shell.onVisualState = function(state)
			if infoWindow == nil then
				return
			end
			-- The panel gets the MODE, not a pre-computed "hide me": whether a
			-- collapsed main window hides it is a setting, and keeping the answer
			-- in one place is what lets that setting change while the window is
			-- already collapsed. Default is "do not hide" -- see
			-- InfoWindow.applyVisibility.
			InfoWindow.setShellMode(infoWindow, state.mode)
		end

		-- The reset button is the recovery path, so it has to repair the info
		-- panel too. It delegates to the PANEL, which is the only thing that knows
		-- the coordinate shape it stores (see InfoWindow.resetPlacement): the
		-- shell used to write a scale-based position here, and mixing the two
		-- shapes is exactly what made the panel "位置乱跳" on every reset.
		shell.onReset = function()
			if infoWindow == nil then
				return
			end
			InfoWindow.resetPlacement(infoWindow)
		end

		--[[
			The panel is placed relative to the main window's rect, so it has to be
			re-placed once that rect settles: a viewport change or a width/height
			edit moves the main window under a panel that was placed to avoid it.

			Wired here rather than inside the shell because the shell does not own
			the panel -- and the callback stays nil until the panel exists, which
			the shell already tolerates (it pcall-guards the field).
		]]
		shell.onGeometrySettled = function()
			if infoWindow == nil then
				return
			end
			InfoWindow.place(infoWindow)
		end

		--[[
			Click-through guard: the info panel floats over the main window, so the
			shell asks whether the press landed on the panel before it starts
			dragging the window. Without it a press that falls on one of the
			panel's non-Active children (a label, the read-out list) also drags the
			main window's title bar underneath.
		]]
		shell.isOverlayAt = function(x, y)
			if infoWindow == nil or InfoWindow.overRect == nil then
				return false
			end
			return InfoWindow.overRect(infoWindow, x, y)
		end

		--[[
			The rejoin cancel dialog.

			Wired here, after the shell exists, because Rejoin is installed well
			before the interface. Without it the toast still says "3 秒后自动重进
			（可取消）" but nothing can cancel -- which is exactly the missing popup
			the old version had.
		]]
		rejoin.onPending = function(reason, cancel, confirmNow)
			Shell.confirm(
				shell,
				"即将重进",
				string.format("原因：%s\n\n取消可留在当前服务器；确认则立即重进。", reason),
				function()
					confirmNow()
				end,
				-- Runs for 取消 AND for a backdrop click, which are both "do not
				-- rejoin" as far as the countdown is concerned.
				cancel
			)
		end

		-- The toast stack needs the screen, so it is created after the shell, and
		-- the shell routes page notifications into it.
		toastRef = Toast.new({
			screen = shell:screenGui(),
			kit = kit,
			store = store,
			timers = runtime.timers,
		})
		shell.onToast = function(text, kind, duration)
			Toast.show(toastRef, text, kind, duration)
		end
		-- The widget library reports its own actions (a toggle flipped, a slider
		-- released, a number committed) through the same stack. Installed after
		-- the stack exists, which is why Kit takes it as a callback.
		kit.onToast = function(text, kind, duration)
			Toast.show(toastRef, text, kind, duration)
		end

		-- Flush whatever the boot raised before there was anywhere to show it.
		if #pendingToasts > 0 then
			local buffered = pendingToasts
			pendingToasts = {}
			for index, entry in ipairs(buffered) do
				-- Staggered slightly so twenty boot messages are readable rather
				-- than a stack that retires itself before it can be read.
				runtime.timers:after(os.clock(), (index - 1) * 0.12, function()
					if toastRef ~= nil then
						Toast.show(toastRef, entry.text, entry.kind, entry.duration)
					end
				end)
			end
		end

		-- The info window shares the shell's screen, so both panels live in one
		-- coordinate space and can be compared directly when placing.
		infoWindow = InfoWindow.new({
			store = store,
			kit = kit,
			shell = shell,
			services = shell.services,
		})
		InfoWindow.build(infoWindow)

		-- Visibility is a store key, so the settings toggle and the window's own
		-- close button drive the same thing.
		store:subscribe("uiState.infoVisible", function(_, value)
			if value == true then
				InfoWindow.show(infoWindow)
			else
				InfoWindow.hide(infoWindow)
			end
		end)
		if store:get("uiState.infoVisible") == true then
			InfoWindow.show(infoWindow)
		end

		-- The shell was already built, so its current shape has to be applied to
		-- the panel once, now: the subscription that drives this fires on CHANGE,
		-- and "started minimised" is a state, not a change.
		local state = Shell.visualState(shell)
		InfoWindow.setShellMode(infoWindow, state.mode)

		--[[
			Reset per-character state when the character is REPLACED.

			`Character.onChanged` already fires `"spawned"` / `"removed"` and had
			zero consumers, which is why a death left the subsystems believing
			things about a model that no longer exists:

			  * `Combat.locked` kept a target the old body had been next to, and
			    `kingActive` kept claiming a king fight;
			  * the machine mount stayed in `mounted`/`mounting`, so `blocked()`
			    kept the tool task stood down and nothing ever re-seated;
			  * an active motion hold pinned a humanoid that had been destroyed.

			V1007 reset all of this from its respawn handler. Clearing the cached
			targets is the important part: every one of them is re-derived on the
			next tick, so this is a reset, not a teardown.
		]]
		character:onChanged(function(reason)
			if reason ~= "spawned" and reason ~= "removed" then
				return
			end
			if combat ~= nil then
				combat.locked = nil
				combat.lockTime = 0
				combat.validatedAt = 0
				combat.kingActive = false
				combat.punchMissingSince = 0
			end
			if machine ~= nil and reason == "removed" then
				-- `dismount` is the machine's own reset: it clears the target, the
				-- seat clock and the phase, and it is safe with no character.
				pcall(function()
					machine:dismount()
				end)
			end
			if motion ~= nil then
				pcall(function()
					motion:finish()
				end)
			end
		end)
	end

	local session = {
		store = store,
		net = net,
		runtime = runtime,
		character = character,
		motion = motion,
		teleport = teleport,
		boss = boss,
		size = size,
		combat = combat,
		machine = machine,
		pets = pets,
		rebirth = rebirth,
		-- Published like the rest: the crystal feature is reachable from the
		-- session handle (the smoke harness drives its sell selection through it).
		crystals = crystals,
		metrics = metrics,
		rejoin = rejoin,
		antiAfk = antiAfk,
		petMetrics = petMetrics,
		train = train,
		perf = perf,
		ui = { kit = kit, shell = shell, toast = toastRef, info = infoWindow },
		configReport = configReport,
	}

	function session.unfreeze()
		if teleport ~= nil then
			teleport:cancel()
		end
		if motion ~= nil then
			motion:unfreeze()
		end
	end

	function session.stop()
		Persist.save(store)
		session.unfreeze()
		-- Undo the client-side target resizing; it is not a hold, so nothing else
		-- would ever put those parts back.
		if combat ~= nil then
			combat:restoreAll()
		end
		-- Leave the player the size they started with.
		if size ~= nil then
			size:restore()
		end
		--[[
			Undo the anti-lag environment tweaks.

			`Perf.disableAntiLag` restores the lighting/property values it changed.
			Teardown ran the size restore and dropped the runtime but never called
			this, so unloading the script with 深度防卡顿 on left the game's
			lighting permanently altered -- a side effect that outlives the script
			that caused it, which is the worst kind.
		]]
		if perf ~= nil and perf.disable ~= nil then
			pcall(function()
				perf:disable()
			end)
		end
		-- Drop any active hold explicitly: runtime:destroy() stops the frame loop
		-- but the character may still be anchored by a hold that never finished.
		if motion ~= nil and motion.finish ~= nil then
			pcall(function()
				motion:finish()
			end)
		end
		runtime:destroy()
		if shell ~= nil then
			Shell.destroy(shell)
		end
		if character ~= nil then
			character:destroy()
		end
		Remotes.clear()
		Platforms.remove()
		-- Release the global handle, but only if it is still OURS: a newer load
		-- may already have published its own, and clearing that would leave the
		-- session that owns it unable to be replaced. Guarded because the
		-- environment table is not always writable -- see `environmentWrite`.
		local handle = environmentRead(Main.PLUGIN_ID)
		if type(handle) == "table" and handle.version == Main.version then
			environmentWrite(Main.PLUGIN_ID, nil)
		end
		-- The boot handles are cleared with the objects they point at, so a
		-- later Main.abort() cannot resurrect a torn-down runtime.
		Main._runtime = nil
		Main._character = nil
		Main.session = nil
	end

	Main.session = session

	-- Publish the handle so the NEXT load can unload this one cleanly, and so a
	-- user (or another script) can reach `MKUltraHUB.stop()`. Best-effort: a
	-- read-only environment is a legitimate configuration, not an error.
	environmentWrite(Main.PLUGIN_ID, {
		version = Main.version,
		cleanup = function()
			Main.stop()
		end,
		session = session,
	})

	return session
end

function Main.stop()
	local session = Main.session
	if session ~= nil then
		session.stop()
	end
end

--[[
	Roll back a FAILED boot.

	`Main.start` creates the runtime (a Heartbeat connection), registers tasks,
	starts timers and opens event connections long before it can return a
	session. If anything after that throws, `Main.session` is never assigned, so
	`Main.stop()` is a no-op: the frame loop keeps running forever with nothing
	referring to it. That is an invisible, unstoppable background loop.

	This tears down whatever the boot managed to create. It reads `Main._runtime`
	/ `Main._character` rather than a session, precisely because a failed boot
	never produced one.
]]
function Main.abort()
	local runtime = Main._runtime
	if runtime ~= nil then
		pcall(function()
			runtime:destroy()
		end)
	end
	local character = Main._character
	if character ~= nil then
		pcall(function()
			character:destroy()
		end)
	end
	pcall(function()
		Remotes.clear()
	end)
	pcall(function()
		Platforms.remove()
	end)
	Main._runtime = nil
	Main._character = nil
	Main.session = nil
end

-- Escape hatch for the "I cannot move" case, callable from a keybind or console.
function Main.unfreeze()
	local session = Main.session
	if session ~= nil then
		session.unfreeze()
	end
end

--[[
	Auto-start.

	Loading this script IS the instruction to run it -- asking the user to call
	Main.start() by hand was only ever a staging measure while the migration was
	in progress.

	The announcement is delayed rather than shown immediately so the window is on
	screen behind it.
]]
local booted, bootError = pcall(Main.start)
if not booted then
	warn("[MKUltraHUB] 启动失败：" .. tostring(bootError))
	-- Without this, the half-built runtime keeps ticking invisibly: Main.session
	-- was never set, so Main.stop() cannot reach it.
	Main.abort()
else
	local session = Main.session
	if session ~= nil and session.ui ~= nil and session.ui.kit ~= nil then
		task.delay(0.7, function()
			pcall(function()
				Announce.show(session.ui.kit, session.store)
			end)
		end)
	end
end

return Main
end

return __require("main")
