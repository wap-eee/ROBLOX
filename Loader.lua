--!nonstrict
-- ===========================================================================
--  MKUltraHUB -- GENERATED BUNDLE. DO NOT EDIT.
--  Source of truth: src\**\*.luau   Builder: tools\bundle.ps1
--  Modules: 68   Entry: main
--  Generated: 2026-10-10 18:32:40
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

	Extracted from Core.fmt / Core.fmtDur in V1007, with the boundary bug the
	review flagged fixed: the old code picked its tier from the RAW value and
	then rounded, so 999.5 printed as "1000" instead of "1.000K", and
	999999.9 printed as "1000.000M" instead of "1.000M".

	The fix is to choose the tier from the value *as it will be displayed*:
	round to the tier's precision first, and if that reaches 1000, step up a
	tier. Both boundaries therefore resolve consistently.
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

--[[
	Format a number for display.

	    Format.number(999.4)        --> "999"
	    Format.number(999.5)        --> "1.000K"
	    Format.number(999999.9)     --> "1.000M"
	    Format.number(nil)          --> "0"
	    Format.number(0/0)          --> "0"
	    Format.number(1e15, false)  --> "1000000000000000"

	`abbreviated == false` prints the rounded value with no suffix and, unlike
	the original, never falls back to scientific notation.
]]
function Format.number(value: number?, abbreviated: boolean?): string
	local n = value or 0
	if n ~= n or n == math.huge or n == -math.huge or n == NAN then
		return "0"
	end

	local negative = n < 0
	n = math.abs(n)

	if abbreviated == false then
		return sign(negative) .. string.format("%.0f", roundTo(n, 0))
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
	return sign(negative) .. string.format("%." .. tostring(decimals) .. "f", shown) .. SUFFIXES[tier]
end

--[[
	Format a duration in seconds: "45s", "1m 30s", "2h 5m".
]]
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

--[[
	Format a signed delta with an explicit sign, e.g. "+1.234K" / "-12".
]]
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

	Why: V1007 kept two copies of the same state (the `Core.<feature>` tables and
	each UI.toggle's internal `val`) and reconciled them with a 1 Hz polling loop
	(Core.syncUI). Polling cannot express "this changed", so drift is normal and a
	missed poll means a control that silently stops working.

	With a Signal, state lives in ONE place (see core/Store) and every view
	subscribes to it. Updates are pushed, so there is nothing to reconcile and
	nothing to miss.

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

	Why: V1007 removed all send throttling on purpose --

	    function Core.allow(key, rate, burst) return true end

	-- arguing that "fast training is implemented by firing as fast as possible".
	That is a safety valve wired open. The moment the server starts throttling,
	the client has no idea, no fallback, and the player gets kicked.

	This module restores the limiter as something *measurable* rather than a
	boolean switch:

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

	Why: V1007 kept every setting in a handful of mutable global tables
	(Core.train, Core.kill, Core.boss, ...) AND a second copy inside each UI
	widget (UI.toggle's local `val`), then reconciled the two with a 1 Hz polling
	loop (Core.syncUI). Polling cannot express "this changed", so the copies drift
	apart and a missed pass means a control that silently stops working.

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

--[[
	Flatten a nested table into path -> value.

	`isLeaf` lets the caller stop the recursion at paths whose values are records
	rather than subtrees. Without it a position record like
	{ xs = 0, xo = 640, ... } would be flattened into savedMain.xs, savedMain.xo,
	... and could never be validated as a unit. Config passes exactly that.
]]
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

--[[
	Rebuild the nested shape from a flat map, for serialisation.

	If both "a" and "a.b" are present the deeper key wins and the scalar is
	lost -- setting a value and one of its own descendants is a modelling bug,
	not a supported state.
]]
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

function Store.new(initial: { [string]: any }?): Store
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

--[[
	Write a value. Returns true when something actually changed, and only then
	are subscribers notified -- writing an unchanged value is not an event, which
	is precisely what makes polling unnecessary.
]]
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

local Config = {}

Config.VERSION = 1008

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
local REJOIN_MODES = { "same", "crowded", "private", "sparse" }
local RARITIES = { "Common", "Rare", "Epic", "Legendary", "Rainbow", "Mythic" }

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
	bool("train.adaptive", false),
	num("train.adaptiveThresh", 30, 10, 120),
	num("train.adaptiveMax", 5000, 100, 50000),
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
	num("kill.range", 400, 20, 2000),
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
	bool("boss.autoChest", false),
	num("boss.chestDelay", 3, 0, 30),

	-- own character ----------------------------------------------------------
	bool("size.selfEnabled", false),
	num("size.selfMul", 3, 1, 20),

	-- performance ------------------------------------------------------------
	bool("perf.antiLag", false),
	bool("perf.disabled", false),

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
		Metadata that travels INSIDE a config file rather than describing a
		setting: the display label of a numbered config slot.

		It is declared here so that loading a named save does not warn "unknown
		key dropped" -- the slot label is written by game/Persist after the
		projection, so validation has to know about it. It defaults to empty and
		is never set by a control.
	]]
	str("meta.slotLabel", ""),

	-- machines ---------------------------------------------------------------
	bool("machine.enabled", false),	str("machine.gymFilter", ""),
	str("machine.nameFilter", ""),
	num("machine.indexFilter", 0, 0, 500),

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

	-- ui state ---------------------------------------------------------------
	num("uiState.widthPct", 45, 30, 100),	num("uiState.heightPct", 52, 30, 100),
	num("uiState.uiScale", 100, 50, 125),
	num("uiState.infoScale", 100, 50, 250),
	num("uiState.fontScale", 1, 0.8, 1.5),
	bool("uiState.formatNum", true),
	bool("uiState.infoVisible", false),
	enm("uiState.theme", "light", THEMES),
	bool("uiState.minimized", false),
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

-- Kinds whose value is a record, not a subtree: flattening must stop here or a
-- position like { xs = 0, xo = 640 } would become un-validatable leaf paths.
local LEAF_KINDS: { [string]: boolean } = { position = true, preset = true }

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
		if path ~= "version" and not known[path] then
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

	Extracted from Core.tpPathTo in V1007. The reasoning behind the algorithm is
	unchanged and worth restating, because it is the whole anti-pullback strategy:

	  * Teleporting hundreds of studs in a single frame trips a server-side
	    distance check, which then snaps the player back. Walking the distance in
	    small steps mostly stays under that check.
	  * The trip must still feel instant, so the step size is derived from a TIME
	    BUDGET: hops = budget / interval, and each step carries total/hops studs.
	    Close targets get many small steps, far targets get fewer larger ones.
	  * An optional vertical arc keeps the path off the ground.

	This module only computes the waypoints. It never touches the engine, so the
	arithmetic is unit-testable -- which is exactly what was impossible in V1007,
	where the maths was interleaved with CFrame writes and task.wait calls.
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

--[[
	Plan a stepped path from `from` to `to`.

	The returned point list always ends EXACTLY on `to` (no accumulated floating
	point drift), and never contains more than maxTime/interval points.
]]
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

	Why: V1007 scattered 30+ raw `task.delay(...)` calls through the codebase.
	None of them could be cancelled, so on unload every pending callback still ran
	and had to defend itself with `if d.Parent then ... end` guards. Guards are a
	symptom; the fix is that a timer is an object you can cancel, and that all of
	them die together when the script unloads.

	There is no scheduler thread here on purpose. The host calls `step(now)` once
	per frame and this registry decides what is due. That means:
	  * no coroutine per timer,
	  * no wake-ups on frames where nothing is due,
	  * deterministic ordering, and
	  * the whole thing is unit-testable with a virtual clock.

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

--[[
	Repeating. Without `immediate` the first run happens one interval from now.

	The next run is scheduled from the CURRENT time, not from the previous
	deadline, so a slow frame cannot make a repeating timer fire several times in
	a row to "catch up".
]]
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

--[[
	Fire everything that is due at `now`.

	Returns (fired, failed). A callback that throws never stops the others: the
	error is counted and handed to the optional onError handler.
]]
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

	V1007 ran three overlapping concurrency APIs at once:

	    Core.spawn(key, fn) / Core.threads / Core.cancel      -- ad-hoc coroutines
	    Core.startWorker(name, step, interval) / Core.workers -- interval loops
	    Core.registerTask(t) / Core.tasks / Core.cancelTask   -- the real scheduler

	...plus 20-odd task coroutines that each woke every single frame
	(`while ... do task.wait(); pcall(t.enabled); pcall(t.tick) end`), so a frame
	cost 20+ coroutine switches and 40+ pcalls even when nothing was enabled.
	Their cancellation also relied on `coroutine.status` before `task.cancel`, a
	check-then-act race that only `pcall` was hiding.

	This scheduler removes the coroutines entirely. Tasks are plain records with
	an `enabled()` predicate and a `tick(dt, now)` callback; the host calls
	`step(dt, now)` once per frame. Consequences:

	  * cost is proportional to tasks that actually run, not to tasks that exist;
	  * there is no `coroutine.status` check and no TOCTOU race;
	  * enable/disable transitions are explicit, so `onEnable`/`onDisable` fire
	    exactly once per transition instead of being inferred;
	  * repeated failures disable a task for a backoff window and report why --
	    V1007 counted failures but had no way to surface them.

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
	-- os.clock() of the last tick that ran, for the liveness watchdog.
	lastRun: number,
	-- os.clock() the entry became active, so a task that has never ticked can be
	-- told apart from one that stopped.
	activeSince: number,
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
			Re-registering replaces the definition and DEACTIVATES the entry, so
			the next step re-evaluates enablement and fires the NEW definition's
			onEnable.

			The old definition's onDisable is fired first, because the new task is
			not a continuation of the old one: leaving the entry `active` would
			carry the previous task's setup into its replacement and the new
			onEnable would never run -- the hooks would silently disagree with
			which definition is installed.

			Failure accounting is reset for the same reason: a re-registered task
			is a fresh task, and inheriting a backoff window from the definition it
			replaced would delay it for no reason.
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

--[[
	Run one frame.

	Returns how many tasks ticked. Tasks whose `enabled()` is false (or that are
	skipped because the scheduler is paused and they are not essential) have
	`onDisable` invoked exactly once on the transition out of active state.
]]
function Scheduler.step(self: Scheduler, dt: number, now: number): number
	sortEntries(self)
	local ran = 0

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
				-- A task with no `tick` runs nothing on purpose. `stalled` excludes
				-- these outright; stamping the clock here is only so the entry has
				-- a coherent timeline for any other reader.
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

	return ran
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

	The scheduler already handles a task that THROWS (failures, then a backoff
	window). It cannot see a task that simply stops doing anything: an `enabled()`
	that started returning false for the wrong reason, a guard that latched, or a
	`tick` that returns early because a clock it reads has gone backwards. From
	the outside those are identical to a task that is working.

	Deliberately a REPORT, not an action. Restarting a task that stopped on
	purpose would undo whatever the guard was protecting against -- the host
	decides, and the read-out tells the user which task has gone quiet. The
	threshold is generous (the slowest real cadence in this script is the 60 s
	metrics sample, and those are timers rather than tasks; every registered task
	is expected to tick within a second or two).
]]
function Scheduler.stalled(self: Scheduler, now: number, staleSeconds: number?): { string }
	local limit = staleSeconds or DEFAULT_STALE_SECONDS
	local out: { string } = {}
	for _, entry in ipairs(self._entries) do
		-- A task with no `tick` is a pure enable/disable hook: it is not supposed
		-- to run anything, so "has not run" is its normal state. Stamping its
		-- clock would not help either -- the stamp never advances, so it would be
		-- reported again as soon as the window elapsed.
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

	Why: V1007 fired remotes with no throttle at all, on purpose --

	    function Core.allow(key, rate, burst) return true end

	-- arguing that "fast training is implemented by firing as fast as possible".
	The safety valve was wired open. There was no queue, no drop accounting, no
	backpressure and nothing observable, so the first symptom of trouble was the
	player being kicked for sending too many requests.

	This module keeps the throughput -- a channel declared with no rate really is
	unlimited, which is what fast training wants -- but turns it into a decision
	with visible consequences:

	  * every channel owns a token bucket (core/RateLimiter);
	  * a send the limiter refuses is either queued (bounded) or dropped, and
	    drops are counted per channel;
	  * a transport error feeds multiplicative backoff, so a server that starts
	    rejecting makes us slow down on our own before it escalates;
	  * stats() reports sent / dropped / queued / penalty, so the UI can show it
	    instead of the user guessing.

	The RemoteEvent call itself lives in src/game, which is why everything above
	is unit-tested without Roblox.
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
	unlimited: boolean,
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
	-- `burst` belongs here: it is the training path's entry point (attempt N
	-- sends, stop at the first refusal) and is part of the public surface. Its
	-- absence from this type was an oversight, not a decision.
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

--[[
	Dispatch one payload.

	Returns (sent, denied):
	  sent   -- the transport accepted it
	  denied -- the limiter refused, so retrying later is meaningful
	A transport failure is (false, false): the payload is bad or the remote is
	gone, and re-queueing it would just fail again.
]]
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

--[[
	Declare a channel.

	`rate` nil or <= 0 means UNLIMITED: sends go straight out, no limiter, no
	queueing. That is the deliberate "fast training" mode -- but now it is a
	per-channel choice the user can see, not a global valve welded open.
]]
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
		unlimited = limiter == nil,
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

--[[
	Send the same payload up to `count` times, stopping at the first refusal.

	This is the training path: the caller has already worked out how many packets
	this frame is worth, and the limiter decides how many of those actually leave.
	A refused burst is NOT counted as drops -- nothing was lost, the remainder is
	simply not due yet.
]]
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

	This is the arithmetic behind Core.trainTick in V1007, lifted out so it can be
	tested. The original pacing was sound and its shape is preserved:

	  * "fast" fires at the configured rate (capped), "auto" at a fixed trickle;
	  * fractional progress accumulates across frames, so a low frame rate does
	    not silently halve the throughput;
	  * the accumulator is capped, so a long stall cannot bank a huge burst;
	  * only a limited number go out per frame and the remainder is KEPT, so the
	    average rate is unchanged while a single frame cannot dump everything;
	  * whatever the network layer refuses is handed back instead of being lost.

	What changed: V1007 had this logic mixed into a tick that also reached for the
	remote and fired it, so none of it could be tested. Whether the result is
	throttled on the wire is now the network layer's decision, not this module's.
]]

local TrainRate = {}

export type Settings = {
	auto: boolean,
	fast: boolean,
	rate: number,
	adaptive: boolean,
	adaptiveThresh: number,
	-- Optional throughput ceiling. Present because V1007 had the setting
	-- (`train.adaptiveMax`) and the UI still writes it while NOTHING read it --
	-- see compute().
	adaptiveMax: number?,
}

export type State = {
	tokens: number,
}

TrainRate.AUTO_RATE = 10
TrainRate.FAST_CAP = 2000
TrainRate.MAX_RATE = 5000
TrainRate.CEILING = 400
TrainRate.PER_FRAME = 40

function TrainRate.newState(): State
	return { tokens = 0 }
end

--[[
	The target rate in packets per second, or 0 when training is off.

	Adaptive mode scales the rate by how far the frame rate has fallen below the
	target: at half the target frame rate you get half the rate. It exists so a
	weak machine degrades smoothly instead of stuttering.

	`adaptiveMax` is applied LAST, as a hard ceiling on whatever the above
	produced. It is not the same thing as `rate`: V1007's UI offered
	"自适应上限" (100-50000) and wrote `Core.train.adaptiveMax`, but `trainTick`
	never read it -- so the slider moved and the throughput ceiling it promised
	did not exist. Reading it here makes the control mean what its label says,
	and it is a ceiling rather than a replacement so it cannot RAISE the rate
	above the configured one.
]]
function TrainRate.compute(settings: Settings, fps: number): number
	local base = 0
	if settings.fast then
		base = math.min(settings.rate, TrainRate.FAST_CAP)
	elseif settings.auto then
		base = TrainRate.AUTO_RATE
	end
	if base <= 0 then
		return 0
	end
	if settings.adaptive and settings.adaptiveThresh > 0 and fps > 0 and fps < settings.adaptiveThresh then
		base = base * (fps / settings.adaptiveThresh)
	end
	local ceiling = settings.adaptiveMax
	if ceiling ~= nil and ceiling > 0 and base > ceiling then
		base = ceiling
	end
	return math.max(0, math.min(base, TrainRate.MAX_RATE))
end

--[[
	Advance the accumulator and return how many packets to ATTEMPT this frame.

	The caller must report back what was not actually delivered via `refund`.
]]
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
	Hold -- the "keep the character where I put it" state machine. Pure.

	This is the decision half of the anti-pullback kernel in V1007's
	Core.motion.update(); the other half is writing CFrames, which stays in
	src/game. Splitting them means the part that decides when to stop holding the
	player can actually be tested -- and that is the part that used to trap them:

	  * a hold is either PERSISTENT (combat/boss: kept as long as the feature is
	    on) or VERIFIED (a teleport or chest: released the moment the arrival
	    window ends). Releasing is what gives control back; an earlier revision
	    held forever and the symptom was "after teleporting I cannot move at all".
	  * while verifying, the distance to the target is sampled at a fixed rate and
	    must exceed the threshold for several CONSECUTIVE samples before it counts
	    as a pullback. A single odd frame, or a target that is itself moving, must
	    not start a retry storm.
	  * pullbacks are retried up to a limit, after which the caller is told to
	    give up (V1007 fell back to a recorded safe position there).

	Two deliberate changes from V1007:

	  1. `start` always resets the counters. V1007 only reset them when no hold
	     was active, so a teleport issued while a hold was live inherited the
	     previous attempt's retry count and gave up early. Carrying state across
	     targets is exactly the bug class the original spent comments fighting.
	  2. `giveup` fires once. V1007 kept sampling after giving up and called the
	     give-up callback again every ten samples, forever.
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

-- Modes that keep holding for as long as the feature is switched on. Everything
-- else is a one-shot "put me here" that must release control after verification.
--
-- NOTE: the annotation has to live on a local. `Hold.X: T = {...}` is not valid
-- Luau -- a type annotation is only allowed on a local declaration.
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
	-- compared against os.clock(), which is machine uptime and never near zero;
	-- anchoring it to `now` makes the behaviour explicit and testable.
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

--[[
	Feed one distance measurement in.

	  "ok"      -- within tolerance, the streak is cleared
	  "lost"    -- over tolerance, but not yet enough consecutive samples
	  "retry"   -- the caller should re-apply the position
	  "giveup"  -- the caller should fall back; fires at most once per hold
	  "skipped" -- not due, already exhausted, or past the verification window
]]
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
	Keyword -- the name matching used to find game objects by fuzzy name. Pure.

	V1007 matched tools and machines by lowercasing a name and searching for a
	substring, inline, at every call site -- which meant the rules (case folding,
	plain-text search, empty keywords) were re-derived each time and never tested.
	There is one implementation now, and it is covered.

	Two details that matter and are easy to get wrong:
	  * the search is PLAIN (`string.find(..., true)`), so a keyword containing a
	    Lua pattern character like "-" or "." matches literally. "push-up" and
	    "hand-stand" are real keywords in this project.
	  * both sides are lowercased, so a caller may pass "Punch" and still match a
	    tool named "PunchTool".
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

	This is where V1007's "single target kill does nothing" chain lived, and the
	whole chain came from one shared number: the free-scan range was also applied
	to a hand-picked target. Pick someone slightly too far away and the selection
	silently returned nothing, every frame, forever.

	So the rules are explicit here, and the two modes are genuinely different:

	    LOCKED   the user named a target. Distance is irrelevant -- they asked for
	             that one. Only self / dead / (optionally) friend can veto it.
	    FREE     nobody named. The nearest eligible candidate inside `range` wins.

	Rather than returning nil on failure, select() returns a REASON. "Why did
	nothing happen" was previously unanswerable without reading the source, and
	the reasons are exactly the distinctions a user needs (out of range? all of
	them are friends? the target left?).
]]

local Targeting = {}

export type Vec3 = { x: number, y: number, z: number }

export type Candidate = {
	id: string,
	position: Vec3,
	alive: boolean,
	friend: boolean,
	self: boolean,
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
		-- Deliberately no range check: the user named this target.
		return { id = candidate.id, reason = "locked" }
	end

	local total = #candidates
	if total == 0 then
		return { id = nil, reason = "no-candidates" }
	end

	local otherThanSelf = 0
	local aliveOthers = 0
	local eligible = 0
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
	return { id = nil, reason = "all-out-of-range" }
end

return Targeting
end

__modules["core/BossInfo"] = function()
	local require = __require
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	BossInfo -- identifying a boss and deciding whether it is wanted. Pure.

	Two rules live here because both were subtly wrong in V1007.

	1. RARITY FROM A NAME. The original looked the keyword up with

	       for kw, r in pairs(RARITY_FIND) do ... break end

	   `pairs` over a hash table has no defined order, so a name matching two
	   keywords resolved differently between runs. The list is ordered here
	   (most specific first) and that ordering is the specification.

	2. AN UNIDENTIFIED BOSS IS ATTACKED, NOT IGNORED. "?" is treated as selected.
	   Refusing to act on a boss you failed to classify would make the feature
	   silently do nothing whenever the game renames something.
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
}

-- The arena's fixed slots, in the order V1007 probed them.
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

function BossInfo.empty(): Info
	return {
		alive = false,
		id = "?",
		rarity = BossInfo.UNKNOWN,
		hp = 0,
		maxHp = 0,
		position = nil,
	}
end

-- The label text. Kept identical to V1007's, since it is user-facing.
function BossInfo.describe(info: Info?): string
	if info == nil or info.alive ~= true then
		return "等待 Boss 刷新..."
	end
	return string.format("存活  %s (%s)\nHP  %s / %s",
		info.id, info.rarity, Format.number(info.hp), Format.number(info.maxHp))
end

return BossInfo
end

__modules["core/ChestTimer"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	ChestTimer -- "the boss just died, go and open the chest" timing. Pure.

	Ported from the state V1007 kept in Core.boss (wasAlive / killedAt) and
	threaded through its chest task. The rules were right but were spread over
	five early-return branches inside a tick that also did teleporting and input
	injection, so nobody could check them:

	    a live boss keeps resetting the timer (a new spawn must not inherit the
	    previous death);
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
ChestTimer.DEFAULT_WINDOW = 30

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

	V1007 decided this inside its orchestrator, on every frame:

	    wantSize = nil
	    if bossAlive and boss.sizeEnabled then wantSize = boss.sizeMul
	    elseif size.selfEnabled then wantSize = self.sizeMul end
	    if wantSize and _lastWantSize ~= wantSize then changeSelfSize(wantSize) end
	    if not wantSize and _lastWantSize and _lastWantSize ~= 1 then changeSelfSize(1) end

	The logic is small but it has three states (boss size / own size / back to
	normal) and it drives a REMOTE, so it must not fire every frame. Splitting it
	into "what size is wanted" and "is that a change worth sending" makes both
	halves checkable -- and the second half is the one that used to spam the
	server or, worse, forget to restore the player's own size.
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
--
-- NOTE: a live boss that is not resized still suppresses the user's own size
-- setting (this is an elseif in V1007 and is preserved): during a boss fight the
-- boss size wins, otherwise the user's own multiplier applies.
function SizePolicy.wanted(inputs: Inputs): number?
	if inputs.bossAlive and inputs.bossSizeEnabled then
		return inputs.bossSizeMul
	end
	if inputs.selfSizeEnabled then
		return inputs.selfSizeMul
	end
	return nil
end

--[[
	Turn "what is wanted" into "what to send", or nil when nothing should be sent.

	`last` is the last value this function returned. Falling back to 1 is explicit
	rather than implicit, because forgetting it leaves the player permanently
	enlarged.
]]
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

	Ported from scanPetMetrics in V1007. The mechanism is not a multiplier bonus:
	the equipped pets' repTimeBoostPercent values are summed and SUBTRACTED FROM
	THE COOLDOWN directly, which is why 100% total means zero cooldown and an
	effectively unbounded speed. Everything here follows from that:

	    total = sum(pet perks) + 5% per ultimate level
	    total >= 100  ->  no meaningful multiplier at all
	    otherwise     ->  1 / (1 - total/100), doubled by the x2 gamepass

	The original computed this inline while walking the object tree, so the one
	line that actually matters (the reciprocal, and the >= 100 cutoff) was never
	checkable. It also carried three unrelated flags around with it.
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

-- The label shown in the info window. V1007 printed "无上限" here.
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

	V1007's applyPreset did this inline, with a task.wait(0.1) between each remote
	call, inside a task.spawn'd coroutine. Two consequences: the whole thing was
	uncancellable, and the interesting part -- what happens when the preset names
	pets you do not own -- was invisible.

	    local instances = Core.findOwnedPets(entry.name)
	    for i = 1, math.min(entry.count or 1, #instances) do ... end

	Note what that does when `instances` is empty: nothing. And since
	unequipAllPets() had already run by then, switching to a preset you own none
	of left you with NO pets at all -- your training silently stopped. The plan
	here reports that case as `unusable` so the caller can refuse to strip the
	player's pets for nothing.
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

--[[
	Build the plan for a preset.

	`availability` maps a pet name to how many copies the player owns. A preset
	entry that asks for more copies than are owned is clamped rather than
	dropped, which is what the original did.
]]
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

--[[
	Flatten a plan into the steps to execute, one per tick.

	The unequip is a step like any other, so the caller has exactly one code path
	and the pacing between remote calls is uniform.
]]
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

	V1007 expressed this with a phase string, three timestamps sprinkled across
	the function, and four early returns. The shape was:

	    idle --(0.8s of hovering)--> approaching --> mounting --(seated)--> mounted
	                                       ^                       |
	                                       +---- 3s timeout -------+

	Everything is gated by a 0.35s retry interval, which means the whole sequence
	takes a bit over a second, not the 0.8s the constant suggests. That is
	preserved -- it is the actual observed pacing -- but it is now testable
	instead of emergent.

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

--[[
	Tolerance for the interval comparisons.

	Without it the pacing misses beats: 0.9 - 0.8 evaluates to
	0.09999999999999998 in IEEE754, so `>= 0.1` reports "too soon" and the action
	is skipped for a tick. The same applies to the hover, where a start time that
	is not exactly representable makes 0.8 measure short.
]]
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
	Disengage: the feature was switched off, or combat took over.

	A "release" is only needed if we were actually attached or attaching; the
	caller unanchors in the other cases anyway, so this keeps it honest.
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

	Ported from Core.rebirthTick in V1007. The shape is:

	    idle ----(interval elapsed)----> request sent, pending
	    pending --(strength collapsed)--> succeeded, short cooldown, failures reset
	    pending --(no reaction in 5s)----> failed, backoff grows with the failures

	The failure path is the point. A rebirth request the server ignores is
	indistinguishable from one that never arrived, so the only safe response is to
	slow down rather than hammer: V1007 grew the cooldown by one second per
	consecutive failure up to ten, and warned once at three. Preserved, and now
	tested.

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

	Ported from Core.performPackRebirth, which was a loop, then a call, then a
	repeat-until, all with task.wait() inside:

	    while strength < target and elapsed < 60 do  fire 20 reps; wait 0.05  end
	    equipFarmingPets()
	    wait 0.25
	    repeat  fire rebirth; wait 0.15  until rebirths grew or 20 tries

	Sequential code that blocks a coroutine cannot be cancelled, cannot report
	progress, and hides its own timeouts. The same sequence as an explicit phase
	machine can do all three:

	    training --> equipping --> requesting --> done

	Two details worth preserving: the training phase gives up on its own after a
	time limit and proceeds anyway (because a rebirth that is slow is better than
	one that never happens), and the requesting phase stops as soon as the rebirth
	counter moves, rather than after a fixed number of attempts.
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

	Ported from the rejoin task in V1007, where three thresholds were evaluated in
	one tick with a shared 10-second sustain. Two rules were buried in that shape
	and are worth making explicit:

	  * the FPS and ping triggers require the condition to hold for 10 seconds,
	    because a single stuttering frame or one lag spike is not a reason to
	    abandon a session;
	  * the MEMORY trigger does not. It fires as soon as the threshold is crossed,
	    because memory only grows -- waiting would just delay an inevitable rejoin,
	    and the sample is taken once every 15 seconds anyway.

	Both are now per-trigger settings rather than an accident of how the tick was
	written.

	A reading of zero or less means "no sample yet" and never trips anything.
	V1007 checked `mem > 0`, `fps > 0`, `ping > 0` for exactly that reason.
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

	local pingOver = thresholds.pingEnabled and reading.ping > 0 and reading.ping > thresholds.pingThreshold
	if sustained(self, "ping", pingOver, now, self.sustain) then
		table.insert(reasons, string.format("延迟 %d", reading.ping))
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

ServerPick.MODES = { "same", "crowded", "sparse", "private" }

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

return ServerPick
end

__modules["core/Metrics"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Metrics -- the rolling frame/memory/ping figures. Pure.

	Ported from onHeartbeat in V1007. Three accumulators with boundaries that are
	easy to get subtly wrong and impossible to notice in a game:

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

export type Metrics = {
	_window: number,
	_maxPing: number,
	_frames: number,
	_elapsed: number,
	_fps: number,
	_ping: { number },
	_pingValue: number,
	_memory: number,
	frame: (Metrics, number) -> number,
	fps: (Metrics) -> number,
	pushPing: (Metrics, number) -> number,
	ping: (Metrics) -> number,
	setMemory: (Metrics, number) -> (),
	memory: (Metrics) -> number,
	reset: (Metrics) -> (),
}

Metrics.DEFAULT_FPS_WINDOW = 0.5
Metrics.DEFAULT_PING_SAMPLES = 5
Metrics.DEFAULT_START_FPS = 60

function Metrics.new(options: Options?): Metrics
	local opts: Options = options or {}
	local self = setmetatable({
		_window = opts.fpsWindow or Metrics.DEFAULT_FPS_WINDOW,
		_maxPing = math.max(1, math.floor(opts.pingSamples or Metrics.DEFAULT_PING_SAMPLES)),
		_frames = 0,
		_elapsed = 0,
		_fps = opts.startFps or Metrics.DEFAULT_START_FPS,
		_ping = {},
		_pingValue = 0,
		_memory = 0,
	}, Metrics)
	return (self :: any) :: Metrics
end

function Metrics.reset(self: Metrics)
	self._frames = 0
	self._elapsed = 0
	self._fps = Metrics.DEFAULT_START_FPS
	table.clear(self._ping)
	self._pingValue = 0
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
function Metrics.pushPing(self: Metrics, millis: number): number
	if millis <= 0 then
		return self._pingValue
	end
	table.insert(self._ping, millis)
	while #self._ping > self._maxPing do
		table.remove(self._ping, 1)
	end
	local total = 0
	for _, value in ipairs(self._ping) do
		total += value
	end
	self._pingValue = math.floor(total / #self._ping)
	return self._pingValue
end

function Metrics.ping(self: Metrics): number
	return self._pingValue
end

function Metrics.setMemory(self: Metrics, megabytes: number)
	if megabytes > 0 then
		self._memory = math.floor(megabytes)
	end
end

function Metrics.memory(self: Metrics): number
	return self._memory
end

function Metrics.reading(self: Metrics)
	return {
		memory = self._memory,
		fps = self._fps,
		ping = self._pingValue,
	}
end

return Metrics
end

__modules["core/Palette"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	Palette -- mapping colour roles from one theme to another. Pure, over plain
	{r, g, b} integers.

	Why this exists at all: V1007's theme switch tried to relate old colours to new
	ones by using Color3 values AS TABLE KEYS.

	    local roles = {}
	    for k, v in pairs(CLR) do
	        if typeof(v) == "Color3" then roles[v] = k end
	    end
	    -- ... later: local role = roles[someWidget.BackgroundColor3]

	Color3 is userdata, and table lookup on userdata compares by REFERENCE. A
	colour read back from a property is a different object from the one that went
	into the table, so almost every lookup missed and the switch "only changed a
	little bit". A second pass was bolted on to paper over it.

	Doing the arithmetic on integer triples removes the problem by construction --
	equal components are equal, full stop -- and makes the whole thing testable
	without a Roblox runtime.
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

--[[
	Build the old -> new mapping for the roles both palettes define.

	A role whose colour did not change produces no entry: there is nothing to
	animate, and including it would waste a tween per widget per role.
]]
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

--[[
	Nearest entry within `tolerance` per channel, or nil.

	Exact first, then a tolerance sweep. The tolerance matters because a widget
	caught mid-tween, or hovered, is not sitting on a palette value -- and those
	are exactly the widgets that used to keep their old theme's colour and make
	the switch look patchy.

	Distance is the largest per-channel difference (Chebyshev), matching the
	per-channel closeness test the original used.
]]
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

	V1007 had no such thing. Each subsystem opened its own connection or its own
	`while true do task.wait() end` coroutine, so frame work was spread over
	"whatever happened to be connected" and there was no single place to look at
	what runs when, and no single place to shut everything down.

	Here there is exactly one Heartbeat connection for the whole script. It does
	three things, in this order, every frame:

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

--[[
	Register a pre-render callback.

	Position overriding has to happen on RenderStepped -- after physics has
	settled and before the frame is drawn. On Heartbeat the correction lands a
	frame late and the snap-back is visible. The "one place connects to the
	engine" invariant still holds: the Runtime owns this connection too, so
	destroy() remains a complete teardown.
]]
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

--[[
	Adopt an engine connection opened by a subsystem.

	The invariant is that every connection in the script is owned by the Runtime,
	so destroy() is a complete teardown. Subsystems that need one (an Idled
	handler, a property-changed signal) hand it over here instead of keeping it.
]]
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

	V1007 called Cache.refresh() on EVERY Heartbeat, and that function re-checked
	`LP.Character`, re-looked-up the Humanoid and the HumanoidRootPart through
	FindFirstChild, and pcall-wrapped a Position read -- every frame, forever,
	even while standing still. It also sampled the position into `lastPos`, which
	two other places then used to "rescue" the player, which is how the script
	ended up dragging the player back to an old coordinate.

	Here the cache is driven by events instead:

	    Player.CharacterAdded      -> adopt the new model
	    ChildAdded on the model    -> pick up a Humanoid / root that streams in late
	    Humanoid.Died              -> mark dead
	    CharacterRemoving / model.AncestryChanged -> clear

	The result is that `runtime.frames` costs nothing when nothing happens, and
	`isAlive()` is a field read rather than a tree walk.
]]

local Signal = require("core/Signal")

local Character = {}
Character.__index = Character

--[[
	The cached HUMANOID and ROOT live in fields named `_humanoid` / `_root`, not
	`humanoid` / `root`.

	They cannot be called `humanoid` / `root`: those are the names of this class's
	METHODS, and the two share one namespace. A nil-valued field is an ABSENT key,
	so `self.humanoid` fell through `__index` to `Character.humanoid` -- the
	function itself -- and `self.humanoid.Parent` then raised

	    attempt to index function with 'Parent'

	on the very first character resolution, which is a boot failure. Initialising
	the field is not enough either: `_clearModel` sets it back to nil, which
	deletes the key and re-exposes the method.
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
	tagged with a field.

	The previous version wrote `connection._mkOwner = owner`. That cannot work:
	an RBXScriptConnection is engine userdata and rejects unknown members with

	    _mkOwner is not a valid member of RBXScriptConnection

	which fired on every spawn and every clear. Attributes are not an option
	either -- they exist on Instances, and a connection is not one -- so the
	association is kept beside the connection, on our side of the boundary.
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

-- Model-scoped connections record their owner so _clearModel can drop exactly
-- those, without writing a field onto the engine's connection object.
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

-- Resolve the root lazily for callers that need a position now: the common case
-- is a cache hit, and the miss costs one FindFirstChild, not one per frame.
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

	V1007 looked remotes up inline at every call site (and in one case re-scanned
	ReplicatedStorage every 3 seconds forever). Two rules here:

	  * a cached remote is only trusted while it is still parented where it was
	    found, so a re-created remote is picked up automatically;
	  * the expensive scan (walking ReplicatedStorage) is throttled, but a failed
	    scan is not cached as a permanent "not found".

	Note that `LocalPlayer` is read lazily: this module can be required before the
	player exists, and capturing it at require time would freeze a nil.
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

-- A remote directly under the player, matched by exact name then by keyword.
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

-- A remote inside ReplicatedStorage.rEvents, by keyword. The scan is throttled;
-- a miss is deliberately not cached, so a later spawn is still discoverable.
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

-- Look for an exact name first, then fall back to a keyword scan. The exact
-- lookup matters because a keyword like "size" or "machine" can pick up an
-- unrelated remote whose name merely contains it.
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
	GameNet -- the Roblox side of the network layer.

	This is deliberately the thinnest possible adapter: everything with a policy
	in it (token buckets, queues, drop accounting, backoff) lives in core/Net,
	which is unit-tested. All that is left here is "call FireServer and report
	what happened".

	Two things this file exists to get right:

	  1. The remote is resolved at SEND time, not captured when the channel is
	     created. A remote that is re-created (respawn, rejoin) would otherwise
	     leave every channel holding a dead instance.

	  2. The payload is packed BEFORE the pcall closure. Writing
	         pcall(function() remote:FireServer(...) end)
	     does not compile -- the anonymous function is not a vararg function, so
	     `...` inside it is "Cannot use '...' outside of a vararg function". That
	     exact mistake made an earlier revision of this script fail to load at
	     all, so it is spelled out here rather than left as folklore.
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

--[[
	The muscle remote is shared by three subsystems: training, egg dropping and
	the pack-rebirth training burst. Whichever one installs first creates the
	channel and the others reuse it, so a channel that is declared with no rate
	limit (training's default) is not silently replaced by a throttled one.

	Returns true when it had to create the channel.
]]
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

	Ported from Core.platforms in V1007. It exists because a client-side hold
	does not stop the server from resolving gravity: if the server wins a frame,
	the character starts to fall, and the next frame snaps it back -- visible as a
	shudder. A hidden collider underneath removes the fall entirely.

	Why it is OFF by default: in "strict" anti-pull mode the root is anchored, so
	there is nothing to fall and the platforms are pure overhead. They matter for
	the non-anchored modes.

	The parts are kept in one list and destroyed together, so nothing outlives the
	hold that created it -- V1007's remove() was correct and is preserved.
]]

-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).

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
	Motion -- the client half of the anti-pullback kernel.

	The decision half (when to hold, when to release, when to retry, when to give
	up) is core/Hold and is unit-tested. This file is only the part that has to
	touch the engine:

	    freeze the humanoid state machine   (PlatformStand + Physics state)
	    anchor the root                     (only in "strict" mode)
	    zero the velocities and write CFrame every frame
	    PivotTo the WHOLE model, not just the root

	The last point is not a detail. Writing only HumanoidRootPart leaves the
	server free to snap the other parts back to its authoritative position, which
	is the "my real position is here but the rendered model is on the floor, and
	my pets are still in the air" symptom.

	Anti-pull mode comes from the config and is re-read on every begin():
	  off     -- never freeze, never anchor; plain teleporting
	  normal  -- clear velocities and write position, but leave the player mobile
	  strict  -- additionally anchor the root and freeze the state machine
]]

local Hold = require("core/Hold")
local Attributes = require("core/Attributes")
local Platforms = require("game/Platforms")

--[[
	How long a held position must stay stable before it counts as accepted.

	Long enough that a server pull-back (which moves the character immediately,
	within a frame or two) can never qualify, short enough that a normal walk
	crossing 1.5 seconds produces a fallback point.
]]
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
}

function Motion.new(options: Options?)
	local opts: Options = options or {}
	local self = setmetatable({
		character = opts.character,
		store = opts.store,
		onLost = opts.onLost,
		onGiveUp = opts.onGiveUp,
		hold = Hold.new(),
		pos = nil,
		get = nil,
		look = nil,
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

function Motion.mode(self): string
	return self.mode
end

-- The position currently being held, or nil. Callers use it to decide whether a
-- new destination is worth issuing (re-targeting every frame is what made the
-- chest task thrash in V1007).
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

function Motion.setLook(self, look)
	self.look = look
end

--[[
	Start (or re-aim) a hold.

	`get` is ALWAYS overwritten, even with nil. Leaving a previous dynamic target
	in place is how a teleport ends up being dragged back to wherever the last
	combat target was.
]]
function Motion.begin(self, options): boolean
	local opts = options or {}
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	if humanoid == nil or root == nil then
		return false
	end

	local antiPull = self.store:get("cfg.antiPull") or "normal"
	local mode = opts.mode or "hover"

	self.pos = opts.pos
	self.get = opts.get
	self.look = opts.look
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
		--[[
			Snapshot the two properties release() restores.

			There is deliberately NO gravity here. An earlier revision read and
			wrote `humanoid.Gravity`, which DOES NOT EXIST -- gravity lives on
			`Workspace`. That raised "Gravity is not a valid member of Humanoid" on
			every hold (the user's log showed it flooding from both `task:boss` and
			`timer`, 60+ folded copies every 30 seconds) and it also meant the
			restore never happened, because the whole shared `pcall` aborted before
			the walk/jump writes.

			Nothing in this module changes gravity, so there is nothing to restore:
			the strict anti-pull mode pins the character by anchoring the root and
			zeroing its velocity, not by fiddling with gravity.
		]]
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
		cf = CFrame.lookAt(target, self.look)
	else
		cf = CFrame.new(target)
	end

	if self.anchored and not root.Anchored then
		pcall(function()
			root.Anchored = true
		end)
	end

	--[[
		Each write is guarded SEPARATELY.

		These three used to share one pcall. A failure on the first (these
		velocity properties do not exist on every root type) then skipped the
		third -- which is the CFrame write, the only one that actually holds the
		player in place. An unrelated property error silently disabled the entire
		anti-pullback correction for that frame, and the symptom would be a
		pullback that "sometimes cannot be corrected".

		The CFrame is also written last on purpose: it is the authoritative one.
	]]
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
	Drift watchdog -- called from a periodic timer, NOT from the frame loop.

	V1007 checked every second while NO hold was active, resynced once the model
	had separated by more than 8 studs, and notified at most three times, twelve
	seconds apart. The refactor only measured drift inside `Motion.apply` (i.e.
	while holding) and at teleport arrival, so an idle or normally-walking
	character whose model had come apart was never measured and never repaired --
	the symptom being an invisible or duplicated body with nothing in the log.

	Rate-limited notifications for the same reason V1007 had them: once the model
	is separated, the watchdog fires every second until it is fixed, and an
	unthrottled warn would be a per-second log flood.
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
		Record the held position ONCE THE SERVER HAS ACCEPTED IT.

		`Motion.markSafe` refuses to record while a hold is active -- correctly, so
		that a position the server is rejecting never becomes the fallback. But
		that left a gap: a session that is holding almost continuously (a long
		boss fight, a teleport loop) never records anything, so when a hold is
		finally given up on there is no fallback point at all and the player is
		left wherever the server dumped them.

		The signal used here is "we have been enforcing this position for
		GOOD_AFTER seconds and the measured error stayed small". A rejected
		position cannot satisfy that: the pull-back that rejects it moves the
		character immediately, so the sample above returns `retry` and the timer
		below never reaches its threshold. Steady time is what makes the position
		provably acceptable.
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
	self.look = nil
	Platforms.remove()

	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false
	-- The validated-position clock belongs to ONE hold: a new hold must earn its
	-- own acceptance rather than inheriting the previous one's timer.
	self.goodSince = 0
end

-- [[ Restore the humanoid and unanchor, without requiring an active hold. ]]
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
	Platforms.remove()
	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false
end

--[[
	Remember a position that is known to be safe (on the ground, inside the map).

	Only recorded while no hold is active: a position the server is actively
	rejecting is not somewhere to fall back to. This is what cfg.tpFallback
	returns to when a teleport is refused repeatedly.
]]
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
	Where to send the player when a hold is given up on.

	`safe` (recorded by the 3-second timer while nothing is held) is preferred,
	because it is a position the player reached by actually standing there.
	`goodPos` is the fallback for the case that used to have NO answer at all: a
	session holding almost continuously never runs the `markSafe` timer, so a
	give-up had nothing to offer and the player was left wherever the server had
	put them. `goodPos` is a held position that stayed stable long enough to be
	accepted -- see Motion.tick.
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

	These coordinates were probed in game and are the whole point of the feature,
	so they live in one place with a lookup, rather than being pasted into a UI
	list and a task separately (which is how V1007 kept them: a table for the tab
	and an index into the same table for the loop task, with nothing checking that
	the index was still valid).

	Coordinates are plain numbers here; the adapter converts to Vector3.
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

	V1007 did this in a coroutine with task.wait(0.015) between hops. That worked,
	but the walk could not be cancelled, was invisible to the task scheduler, and
	its arithmetic was entangled with the CFrame writes. Here:

	    core/Path    decides the waypoints   (pure, tested)
	    core/Timers  paces the hops          (cancellable, counted)
	    this file    writes the CFrames      (the only engine part)

	Why stepping at all: teleporting hundreds of studs in one frame trips the
	server's distance validation, which then snaps the player back. Walking the
	distance in small hops mostly stays under it, while a time budget keeps the
	trip feeling instant regardless of distance.

	On arrival the movement kernel is armed for a verification window, so the
	first few frames of any residual snap-back are corrected -- and then released,
	so the player can walk again.
]]

-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).

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
		arrivals = 0,
		lastArrival = 0,
		retargets = 0,
	}, Teleport)
	return self
end

function Teleport.isBusy(self): boolean
	return self.busy
end

function Teleport.cancel(self)
	if self.handle ~= nil then
		self.handle:cancel()
		self.handle = nil
	end
	self.busy = false
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
		onLost = options.onLost,
		onGiveUp = options.onGiveUp,
	})
end

--[[
	Walk to `target`.

	Returns false if there is no character to move. The walk itself is
	asynchronous but cancellable: starting a second one cancels the first.
]]
function Teleport.walk(self, target, options): boolean
	local opts: Options = options or {}
	if typeof(target) ~= "Vector3" then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end

	Teleport.cancel(self)
	self.retargets += 1

	local from = root.Position
	--[[
		`cfg.tpPath` -- the old "分跳传送" switch, restored.

		V1007 read it in `Core.tpPathTo`'s caller: when it was on AND the distance
		exceeded 40 studs it took the staged path, otherwise it moved in one hop.
		The refactor always staged (`Path.plan` + a hop timer) and left the key in
		the schema with no reader and no control, so the option silently ceased to
		exist.

		Off means "one hop, then arrive": the plan is cut to its final point. That
		is the same endpoint either way, so turning it off can make the move
		rubber-band more, not less -- which is exactly what the setting is for.

		`opts.path` still overrides the store, because the teleport page's own
		callers pass it explicitly.
	]]
	local staged = opts.path
	if staged == nil then
		staged = self.store:get("cfg.tpPath") ~= false
	end
	local distance = (target - from).Magnitude

	--[[
		`cfg.tpStage` -- "分段传送：长距离先抬高再落点".

		Also a restored reader: the toggle existed and nothing consumed it. V1007
		gated an initial lift on it (`Core.cfg.tpStage and dist > 60`, its line
		773); the equivalent here is the path's arc, which lifts the midpoint of
		the hop chain. An explicit `opts.arc` still wins, so the callers that pass
		their own arc are unaffected.
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
	})
end

--[[
	The muscle-king shortcut.

	The portal sits above the beach, and arriving straight at it drops the player
	through the map, so the trip is done in two hops: high above the arena first,
	then down onto the portal. V1007 did the same two calls.
]]
function Teleport.goToMuscleKing(self)
	Teleport.walk(self, Vector3.new(-8727.1, 100, -5796.4), { mode = "tp", hold = false })
	local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
	local destination = if portal ~= nil
		then portal.Position + Vector3.new(0, -14, 0)
		else Vector3.new(-8727.1, 389.7, -5796.4)
	-- Scheduled rather than slept: the original blocked its coroutine for 0.1s
	-- between the two hops.
	self.timers:after(os.clock(), 0.1, function()
		Teleport.walk(self, destination, { mode = "tp", arc = 200 })
	end)
	return true
end

local function farFromCurrent(self, target, tolerance)
	local current = self.motion:targetPosition()
	if current == nil or typeof(current) ~= "Vector3" then
		return true
	end
	return (current - target).Magnitude > (tolerance or 12)
end

function Teleport.install(context)
	local self = Teleport.new(context)
	local store = context.store
	local scheduler = context.scheduler

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
			return true
		end,
		onDisable = function()
			Teleport.cancel(self)
		end,
		tick = function(_dt, now)
			if now - (self.lastLoop or 0) < 0.5 then
				return
			end
			self.lastLoop = now
			if Teleport.isBusy(self) then
				return
			end
			local entry = Teleports.byIndex(store:get("tp.loopIdx"))
			if entry == nil then
				return
			end
			local target = Vector3.new(entry.x, entry.y, entry.z)
			if farFromCurrent(self, target) then
				Teleport.walk(self, target, { mode = "tp", arc = 220 })
			end
		end,
	})

	scheduler:register({
		id = "teleport",
		priority = 80,
		enabled = function()
			return store:get("tp.autoMK") == true
		end,
		onDisable = function()
			Teleport.cancel(self)
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
			if farFromCurrent(self, target) then
				Teleport.walk(self, target, { mode = "tp", arc = 200 })
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

	V1007 had this logic in three places (getToolInChar, findTool, equipTool) plus a
	keyword table, with the matching rules inline. The rules now live in
	core/Keyword (tested); this file only knows how to walk a character and a
	backpack.

	The keyword sets are deliberately loose and bilingual -- tool names in this
	game are localised, and V1007's sets (matching Chinese and English at once)
	were the result of real names observed in game. They are preserved as-is.
]]

local Keyword = require("core/Keyword")

local Tools = {}

Tools.PUNCH = { "punch", "拳", "fist", "空手", "拳头" }
Tools.DUMBBELL = { "barbell", "dumbbell", "weight", "哑铃", "杠铃" }
Tools.PUSHUP = { "pushup", "push up", "push-up", "俯卧撑" }
Tools.HANDSTAND = { "handstand", "hand stand", "hand-stand", "倒立" }
Tools.SITUP = { "situp", "sit up", "sit-up", "仰卧起坐" }

-- Already equipped (a child of the character).
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

-- Present but in the backpack.
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

function Tools.find(character, player, keywords)
	return Tools.equipped(character, keywords) or Tools.inBackpack(player, keywords)
end

--[[
	Equip a matching tool. Returns true when the tool is (now) held.

	The humanoid is the only thing that can equip, and it may be gone by the time
	this runs, so every step is guarded.
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
	local ok = pcall(function()
		humanoid:EquipTool(tool)
	end)
	return ok
end

-- The first matching group wins, so callers can express a preference order.
function Tools.equipFirst(character, humanoid, player, groups): boolean
	for _, keywords in ipairs(groups) do
		if Tools.equip(character, humanoid, player, keywords) then
			return true
		end
	end
	return false
end

return Tools
end

__modules["game/Pets"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Pets -- presets, the shop, eggs and the fortune wheel.

	The interesting part is preset application. V1007 ran it inside a task.spawn'd
	coroutine with task.wait(0.1) between every remote call: uncancellable, and
	invisible to the scheduler. Here the plan is computed purely
	(core/PetPlan), flattened into steps, and executed one step per tick by a
	timer -- so it can be cancelled, it shows up in the scheduler's accounting,
	and the "preset names pets you do not own" case can be refused instead of
	stripping every pet the player has.

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

--[[
	Apply a saved preset, one remote call per tick.

	Returns false when there is nothing sensible to do, which includes the case
	that used to hurt: a preset whose pets the player does not own.
]]
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
		Distinguish "this preset is empty" from "this preset has nothing usable".

		Both used to return `false` silently, and they mean different things to the
		user: an empty preset is "you never saved this", while a preset whose pets
		are all unowned is "the game moved on". V1007 reported the empty case.
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
	from what is already active.

	Two things report rather than staying silent, because both look identical to
	"the feature is broken" from the outside:

	  * an empty preset: the request is dropped, and the previously applied preset
	    stays on. Silently ignoring it means the user turns on auto-switch, never
	    sees a swap, and has nothing to go on.
	  * a re-request inside the delay window: `pendingAt` is re-armed on every call
	    (that is what the delay is FOR -- the caller is saying "switch once things
	    settle"), but if the key changes the earlier request is genuinely replaced,
	    so saying so is the difference between "it retargeted" and "it did nothing".
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

__modules["game/Combat"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Combat -- global killing, single-target killing, and the muscle king.

	The three modes are one concept with three ways of naming a target, and V1007
	suffered for treating them as three features. "Single target kill does
	nothing" was not one bug but a chain, all rooted in the question "is combat
	happening right now?" being answered differently in four places:

	    the scheduler decided no combat was happening, so it released the motion
	    hold and the player never closed the distance;
	    the punch guard decided no punch tool was needed, so a swapped-out glove
	    was never re-equipped;
	    the tool task decided training could take the glove away;
	    and the selection insisted on the free-scan range even for a hand-picked
	    target.

	So there is one answer now -- Combat.isBusy() -- and the selection rules live
	in core/Targeting where the locked/free distinction is explicit and tested.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Targeting = require("core/Targeting")
local Arbiter = require("core/Arbiter")
local Tools = require("game/Tools")
local Remotes = require("game/Remotes")
local GameNet = require("game/Net")
local Pets = require("game/Pets")
local Attributes = require("core/Attributes")

local Combat = {}
Combat.__index = Combat

local PUNCH_LEFT = "rbxassetid://3638729053"
local PUNCH_RIGHT = "rbxassetid://3638767427"

local LOCK_MAX_AGE = 15
local SCAN_INTERVAL = 0.3
local VALIDATE_INTERVAL = 0.1
local KING_INTERVAL = 0.5
local PUNCH_MISSING_GRACE = 1.5

--[[
	The boss punch cadence.

	V1007 ran `Core.startBossPunch`: a loop that called `Core.doPunch`, flipped
	the hand and waited 0.05s while the boss was alive. Same interval here, so
	the wire traffic matches the version the game accepted -- the difference is
	that it is a scheduler task now, so it shows up in the accounting, obeys the
	punch channel's limiter, and dies with the runtime.
]]
local BOSS_PUNCH_INTERVAL = 0.05

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
	Friend check.

	An external friend-list script may install a predicate at MK_HUB_IS_FRIEND, or
	publish a whitelist at MK_HUB_FRIEND_WL. When a whitelist exists but has not
	finished loading, every player counts as a friend: refusing to attack is the
	safe direction to fail in, and V1007 behaved the same way.
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
			FAIL SAFE WHEN THERE IS NO LIST AT ALL.

			The old code left `friendWL.loaded = false` and `ids = {}` when no
			external script was present, so `isFriend` answered `true`: "I do not
			know who my friends are, so I will not attack anyone". This revision
			answered `false` here, which INVERTED the promise the kill page makes
			("名单状态：未加载（不会攻击任何人）") -- with 不打好友 on and no list
			installed, it attacked everyone. Attacking a friend is not
			recoverable; declining to attack a stranger is.
		]]
		return true
	end
	if whitelist.loaded ~= true then
		return true
	end
	return (whitelist.ids or {})[player.UserId] == true
end

--[[
	Ask the external friend script to refresh, and read what it published.

	V1007 had this as `Core.refreshFriends`, wired to a "刷新好友列表" button and
	to a 10-second retry while the whitelist was on. The refactor kept the READ
	side of the contract (the two environment keys) and dropped the request side
	and the button, so a user whose whitelist was not ready at load had no way to
	make it ready -- "不打好友" simply did nothing, silently, forever.

	Both halves of the contract are optional and probed: an executor with neither
	key is not an error, it just means no friend list is available.
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
			The arbitration handle. When present, this subsystem announces the
			one thing the rest of the script needs to know about it: "something
			must be able to deal damage right now". While that hold is up, any
			task above the BODY rung (i.e. the gym machine) is capped, and the
			machine steps off the seat for exactly as long as the hold lasts.

			Missing it is not an error: the subsystem runs, it just cannot ask
			anyone to make way.
		]]
		arbiter = context.arbiter or nil,
		damageHeld = false,
		--[[
			Pet presets follow the task, exactly like the rebirth path already did.

			`petPreset.kill` and `petPreset.boss` were configurable in the UI and
			never applied, because Pets.scheduleSwap had a single call site (the
			rebirth one). The swap is what "自动换宠" means to the user.
		]]
		pets = context.pets or nil,
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
		lastReason = "idle",
		-- Boss attack state, mirroring V1007's startBossPunch loop.
		bossPunchAt = 0,
		bossHandLeft = false,
		bossPunches = 0,
	}, Combat)
	return self
end

-- The user-named target, resolved from the store on demand so it is always
-- fresh. V1007 cached a Player instance and needed a 2-second sync task to
-- repair it after a rejoin.
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
	Is combat happening right now?

	This single predicate is what the motion hold, the punch guard and the tool
	task all consult. Splitting it into "enabled" and "single" is exactly what
	broke single-target mode in V1007.
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

function Combat.candidates(self)
	local list = {}
	local me = localPlayer()
	for _, player in ipairs(Players:GetPlayers()) do
		local root, humanoid = rootOf(player)
		if root ~= nil and humanoid ~= nil then
			local ok, position = pcall(function()
				return root.Position
			end)
			if ok and typeof(position) == "Vector3" then
				table.insert(list, {
					id = player.Name,
					position = { x = position.X, y = position.Y, z = position.Z },
					alive = humanoid.Health > 0,
					friend = isFriend(player),
					self = (player == me),
				})
			end
		end
	end
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
	if self.store:get("kill.single") == true then
		lockedId = tostring(self.store:get("kill.singleName") or "")
	end

	local decision = Targeting.select(Combat.candidates(self), { x = position.X, y = position.Y, z = position.Z }, {
		range = tonumber(self.store:get("kill.range")) or 400,
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

	No mouse simulation. An earlier revision injected a mouse click every 0.05s
	here, which consumed the player's real clicks -- "opening auto-boss makes the
	whole screen unclickable". Punches are the remote plus an animation only.

	They also go through the network layer now, so the punch rate is bounded and
	counted instead of being an invisible flood.
]]
function Combat.punch(self, left, now)
	if self.character:isAlive() ~= true then
		return
	end
	local character = self.character:current()
	local humanoid = self.character:humanoid()
	if character == nil or humanoid == nil then
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
	Combat.playAnimation(self, humanoid, left)
end

--[[
	Is something in this script currently required to be able to deal damage?

	Two things can be: the boss attack (its own task, in game/Boss) and this
	module's kill / single-target / muscle-king loops. Both raise the SAME
	`damage` requirement, because the consequence for everything else is
	identical -- the gym machine has to get out of the way.
]]
function Combat.wantsDamage(self): boolean
	if self.store:get("boss.auto") == true and self.isBossAlive() then
		return true
	end
	return Combat.isBusy(self)
end

--[[
	Hold the damage requirement for exactly as long as it is true.

	Held on the instance rather than the arbiter so the hold is tied to this
	subsystem's lifetime: when the task is disabled (or the script unloads) the
	release happens on the way out, and a leftover hold from a dead subsystem can
	never keep the machine locked out.
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
	One boss punch cycle.

	Alternates hands like V1007's `startBossPunch` did, and paces itself with the
	same 0.05s interval. No proximity test and no approach: the old version
	fired the remote from wherever the player was hovering, and adding a range
	gate here would silently change behaviour the game already accepted.
]]
function Combat.bossPunchTick(self, now)
	if self.store:get("boss.auto") ~= true or not self.isBossAlive() then
		self.bossPunchAt = 0
		return
	end
	if now - self.bossPunchAt < BOSS_PUNCH_INTERVAL then
		return
	end
	self.bossPunchAt = now
	self.bossHandLeft = not self.bossHandLeft
	Combat.punch(self, self.bossHandLeft, now)
	self.bossPunches += 1
end

--[[
	Which pet preset the current activity wants, or nil for "none".

	Order matters: a boss fight outranks a kill loop, so the boss preset wins
	while a boss is up even if `kill.enabled` is also on.
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
	Follow the preset when the desired key CHANGES.

	Debounced by the caller through the key compare: `scheduleSwap` would be a
	no-op anyway once the preset is active, but re-requesting every frame would
	also keep re-arming its 0.4s delay, so the preset would never actually be
	applied while the task stayed busy.
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

-- Close the distance through the motion kernel (so a pullback is corrected) and
-- strike.
function Combat.attack(self, target)
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
		local direction = myPosition - targetPosition
		if direction.Magnitude < 0.1 then
			direction = Vector3.new(0, 0, -1)
		end
		local destination = targetPosition + direction.Unit * 1.5
		self.motion:setTarget(destination)
		if not self.motion:isActive() then
			self.motion:begin({ pos = destination, mode = "combat" })
		end
		self.motion:setLook(targetPosition)
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
	if self.locked ~= nil then
		-- The staleness test is arithmetic and stays per-frame; the liveness test
		-- walks the target's character (a root + humanoid lookup), so it is
		-- throttled. Checking it 60x/second per locked target bought nothing --
		-- a corpse can be punched harmlessly for a tenth of a second.
		local stale = now - self.lockTime > LOCK_MAX_AGE
		local valid = true
		if now - self.validatedAt >= VALIDATE_INTERVAL then
			self.validatedAt = now
			valid = aliveRoot(self.locked) ~= nil
		end
		if not valid or stale then
			self.locked = nil
			self.lockTime = 0
			self.validatedAt = 0
		end
	end

	if self.locked == nil and now - self.scanAt >= SCAN_INTERVAL then
		self.scanAt = now
		local target = Combat.select(self)
		if target ~= nil then
			self.locked = target
			self.lockTime = now
			self.validatedAt = now
			self.resized = nil
		end
	end

	if self.locked ~= nil then
		Combat.attack(self, self.locked)
	end
end

-- The muscle king is published by the game as an ObjectValue or StringValue.
function Combat.findKing()
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local state = shared and shared:FindFirstChild("state")
	local world = state and state:FindFirstChild("World")
	local value = world and world:FindFirstChild("muscleKing")
	if value == nil then
		return nil
	end
	if value:IsA("ObjectValue") then
		return value.Value
	end
	if value:IsA("StringValue") and value.Value ~= "" then
		return Players:FindFirstChild(value.Value)
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
	Keep a punch tool in hand while combat is running.

	V1007 only checked kill.enabled here, so in single-target mode the glove was
	never restored after anything replaced it -- and the attacks silently did
	nothing.
]]
function Combat.guardPunch(self, now)
	if self.store:get("cfg.keepPunch") ~= true or not Combat.wantsDamage(self) then
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
	Client-side resize of another player's model. Purely cosmetic locally, which
	V1007 documented and this keeps -- the server model is untouched.

	The pet check walks the ancestor chain, so its result is cached on the part:
	doing it per call meant a string search per part per second.

	The cache is assumed to outlive the part. That holds because a pet is
	identified by its ancestor chain (the "pet" folder part), which is fixed for
	the lifetime of the part, and because a renamed part is re-created rather
	than mutated -- so the attribute cannot go stale while the instance lives.
	If that assumption ever changes, the fix is to clear `_MK_Pet` on the
	character's ChildAdded/ChildRemoved, not to drop the cache.
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
	return {
		punches = self.punches,
		locked = if self.locked ~= nil then self.locked.Name else nil,
		kingActive = self.kingActive,
		lastReason = self.lastReason,
	}
end

function Combat.install(context)
	local self = Combat.new(context)

	-- Punches are event-driven rather than bursty, but they were previously an
	-- invisible flood: two sends per frame, unlimited. 60/s is still far beyond
	-- any real attack rate and it is now counted.
	self.net:addChannel("punch", GameNet.senderFor(Remotes.muscle), {
		rate = 60,
		burst = 20,
		queue = 0,
	})

	local store = self.store

	--[[
		The damage requirement lives on its own instance, not on the kill task.

		Two different tasks can want it (the boss attack and the kill loop) and
		the hold has to be up whenever EITHER does -- so it is owned by the
		subsystem and driven from one place, rather than duplicated inside each
		task where the two would release each other's hold.
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
			self.motion:finish()
			--[[
				Hand the pet preset back to training.

				V1007's kill task onDisable did this (`schedulePetSwap("train",
				0.5)`) and the refactor ported the size restore and the motion
				release but not the preset revert -- so after a kill session the
				player kept wearing the "kill" pets while training, permanently.
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
		THE BOSS ATTACK.

		Priority 385 puts it above the kill loop (370) and the tool task (60) and
		just under kingKill (380) -- which is inert while a boss is alive anyway.
		It has to run while `boss.auto` is on and a boss exists, and it is
		deliberately NOT gated on `kill.enabled`: the old version attacked the
		boss whenever auto-boss was on, regardless of the kill switch.

		This task is the whole reason the damage requirement exists: while it
		runs, training comes off the machine.
	]]
	self.scheduler:register({
		id = "bossPunch",
		priority = 385,
		enabled = function()
			return store:get("boss.auto") == true and self.isBossAlive()
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
		needs it: the kill loop raises it too, and this task is what drops it
		again the moment neither source wants damage. Without it, a boss dying
		mid-kill would leave the hold up and the machine would never re-mount.
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
		Keep the friend whitelist loaded while "不打好友" is on.

		V1007 retried every 10 seconds (`Core.friendWL.lastTry`) because the
		external friend script may not be ready at load, and a whitelist that
		never loads makes `isFriend` answer `true` for everyone -- so combat would
		refuse every target with no explanation. The periodic retry is what makes
		that self-healing, and the button on the kill page is the manual override.
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

	The decision rules live in core (core/BossInfo for identification and rarity,
	core/ChestTimer for the post-kill countdown); this file is the traversal and
	the engine calls.

	Detection is cached for half a second. V1007 did the same, and it matters:
	the alive-check is consulted by several subsystems every frame, and each miss
	walks Workspace.Events.BossArena looking for a model.

	The structure is probed in two passes, preserved from V1007:
	  1. the arena's fixed slots (Boss1..Boss5, BossRainbow), which carry no
	     readable rarity in their names;
	  2. a fallback scan of every child, reading the rarity out of the name --
	     so a renamed or newly added arena still works.
]]

-- `Workspace` is used directly: it is a real Roblox global, and declaring a
-- local for it only creates a shadow that the bundle-level check flags.
local VirtualInputManager = game:GetService("VirtualInputManager")

local BossInfo = require("core/BossInfo")
local ChestTimer = require("core/ChestTimer")
local Pets = require("game/Pets")

local Boss = {}
Boss.__index = Boss

local DETECT_CACHE = 0.5
local INTERACT_INTERVAL = 0.4
local TOUCH_TAIL = 0.05

local function selectionOf(store)
	local selection = {}
	for _, rarity in ipairs(BossInfo.RARITIES) do
		selection[rarity] = store:get("boss.select." .. rarity) ~= false
	end
	return selection
end

local function fill(info, holder, model, id, rarity)
	info.alive = true
	info.id = id
	info.rarity = rarity
	info.hp = tonumber(holder:GetAttribute("Health")) or 0
	info.maxHp = tonumber(holder:GetAttribute("MaxHealth")) or 0
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		info.position = pivot.Position
	end
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
		-- "train" when it ends -- the same revert V1007's boss task onDisable did.
		pets = context.pets or nil,
		-- Used on exit to restore the body size. A FUNCTION, not the service:
		-- main.luau installs Size AFTER Boss, so a captured value would be nil --
		-- the same ordering trap the pet service above avoids by being installed
		-- first.
		sizeRef = context.size or nil,
		-- Where to put the player back when the boss task turns off.
		lastPosition = nil,
		cacheAt = 0,
		cacheInfo = BossInfo.empty(),
		chest = ChestTimer.new(),
		lastInteract = 0,
		loots = 0,
	}, Boss)
	return self
end

local function chestPosition(chest)
	if chest == nil then
		return nil
	end
	if chest:IsA("Model") then
		local primary = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
		if primary ~= nil then
			return primary.Position
		end
		return nil
	end
	if chest:IsA("BasePart") then
		return chest.Position
	end
	return nil
end

--[[
	Scan for a boss. Cached for DETECT_CACHE seconds.
]]
function Boss.detect(self)
	local now = os.clock()
	if now - self.cacheAt < DETECT_CACHE then
		return self.cacheInfo
	end
	self.cacheAt = now

	local info = BossInfo.empty()
	local selection = selectionOf(self.store)

	local events = Workspace:FindFirstChild("Events")
	local arena = events ~= nil and events:FindFirstChild("BossArena") or nil

	if arena ~= nil then
		for _, entry in ipairs(BossInfo.fixed()) do
			if BossInfo.selected(entry.rarity, selection) then
				local holder = arena:FindFirstChild(entry.id)
				local model = holder ~= nil and holder:FindFirstChild("Boss") or nil
				if model ~= nil then
					self.cacheInfo = fill(info, holder, model, entry.id, entry.rarity)
					return self.cacheInfo
				end
			end
		end

		for _, holder in ipairs(arena:GetChildren()) do
			local model = holder:FindFirstChild("Boss")
			if model ~= nil then
				local rarity = BossInfo.rarityFromName(holder.Name)
				if BossInfo.selected(rarity, selection) then
					self.cacheInfo = fill(info, holder, model, holder.Name, rarity)
					return self.cacheInfo
				end
			end
		end
	end

	-- Last resort: a flat attribute set on Workspace, with no position at all.
	if Workspace:GetAttribute("BossActive") then
		info.alive = true
		info.hp = tonumber(Workspace:GetAttribute("BossHealth")) or 0
		info.maxHp = tonumber(Workspace:GetAttribute("BossMaxHealth")) or 0
		info.rarity = tostring(Workspace:GetAttribute("BossRarityName") or "?")
		info.id = tostring(Workspace:GetAttribute("BossDisplayName") or "?")
	end

	self.cacheInfo = info
	return self.cacheInfo
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
	Get onto the boss, properly.

	The old shape of this was ONLY a motion hold: `motion:setTarget(pos)` plus
	`motion:begin`, and then `Motion.apply` rewrites the character's CFrame every
	frame to keep it there. Two things made that not work in practice:

	  * the hold re-writes the SAME position every frame, so the character is
	    pinned where it started rather than carried to the boss -- with the boss
	    spawning far away, "it only tries to attack and never gets there" is the
	    exact symptom;
	  * if a hold was already active for another reason (a teleport, a combat
	    approach), `motion:begin` was never called at all, so the boss task did
	    nothing but observe.

	This drives the teleport directly and keeps the hold only as the anti-pull
	correction once we are actually near. The re-approach is rate limited: a boss
	that is alive but unreachable must not be re-teleported to every frame.
]]
local APPROACH_INTERVAL = 0.5
local ARRIVE_DISTANCE = 12
-- Hover height above the boss: close enough for the punches to land, high enough
-- that the boss's own attacks mostly miss. V1007 hard-coded 70.
local BOSS_HOVER_HEIGHT = 70

function Boss.approach(self, now)
	local info = self.detect(self)
	if not info.alive or typeof(info.position) ~= "Vector3" then
		self.approachAt = 0
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

	-- Hover height: close enough for the punches to land, high enough that the
	-- boss's own attacks mostly miss.
	local destination = info.position + Vector3.new(0, BOSS_HOVER_HEIGHT, 0)
	local distance = (position - destination).Magnitude

	if distance > ARRIVE_DISTANCE and self.teleport ~= nil then
		if now - (self.approachAt or 0) >= APPROACH_INTERVAL then
			self.approachAt = now
			-- hold = false while travelling: the walk owns the character for the
			-- duration, and the hold begins on arrival (see Teleport._arrive).
			self.teleport:walk(destination, { mode = "boss", hold = false, arc = 120 })
		end
		return
	end

	-- In range: keep the position with the motion hold so a server pull-back is
	-- corrected rather than leaving the player on the ground.
	self.motion:setTarget(destination)
	if not self.motion:isActive() then
		self.motion:begin({ pos = destination, mode = "boss" })
	end
end

--[[
	Leave the boss area when the boss task turns off.

	V1007's boss-task onDisable did three things: stop punching, put the player
	back (last position + 5 studs, or release the freeze), and hand the pet preset
	back to "train". Only the punch stop had been ported, so turning auto-boss off
	left the character frozen 70 studs above an empty arena -- which reads as "the
	script broke" rather than "the feature is off".
]]
function Boss.leave(self)
	if self.pets ~= nil then
		Pets.scheduleSwap(self.pets, "train", 0.5)
	end

	--[[
		Put the body back.

		V1007's boss-task `onDisable` ended with:

		    if not Core.size.selfEnabled then
		        Core._lastWantSize = 1
		        Core.changeSelfSize(1)
		    end

		i.e. it restored the size EXPLICITLY rather than waiting for the size task
		to notice. That matters because `SizePolicy.wanted` gates the boss branch on
		`bossAlive AND boss.sizeEnabled`, so turning auto-boss OFF while the boss is
		still alive does not change what the policy wants -- the player stays
		enlarged for as long as the boss lives, which is what the user saw as "关闭
		打 Boss 后不会切换回原来的体型".

		Only when the user has no size setting of their own: if they do, `Size.tick`
		owns the value and the policy already wants THEIR size, so forcing 1 here
		would fight it.
	]]
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

	self.motion:finish()
	if destination ~= nil and self.teleport ~= nil then
		-- hold = false: arrive and hand control straight back. Without a recorded
		-- position there is nothing better to do than release, which finish()
		-- already did.
		self.teleport:walk(destination, { mode = "tp", hold = false })
	end
	self.lastPosition = nil
end

--[[
	Open whatever the chest responds to.

	Three mechanisms, because chests in this game are inconsistent: a
	ProximityPrompt, a ClickDetector, or plain touch interest. The E key is a
	fourth fallback for prompts that only react to real input.

	The two "release" steps (touch end, key up) are scheduled on a timer rather
	than with task.wait: the original blocked a coroutine for 0.05s, and a blocked
	task cannot be cancelled when the script unloads.
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
	self.loots += 1
end

function Boss.chestTick(self, now)
	self.chest:configure({
		delay = tonumber(self.store:get("boss.chestDelay")) or nil,
	})

	local status = self.chest:observe(Boss.isAlive(self), now)
	if status ~= "ready" then
		return
	end

	local chest = Workspace:FindFirstChild("BossChest")
	local position = chestPosition(chest)
	if position == nil or position.Y < -100 then
		return
	end

	local current = self.motion:targetPosition()
	local nearby = self.motion:isActive()
		and typeof(current) == "Vector3"
		and (current - position).Magnitude <= 5
	if not nearby then
		self.teleport:walk(position + Vector3.new(0, 5, 0), { mode = "chest", arc = 120 })
	end

	-- Once every 0.4s. Interaction is not rate limited on the wire, but clicking
	-- E every frame is pointless and noisy.
	if now - self.lastInteract < INTERACT_INTERVAL then
		return
	end
	self.lastInteract = now
	Boss.interact(self, chest)
end

function Boss.stats(self)
	local info = Boss.detect(self)
	return {
		alive = info.alive,
		id = info.id,
		rarity = info.rarity,
		hp = info.hp,
		loots = self.loots,
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
			Boss.leave(self)
		end,
		tick = function(_dt, now)
			Boss.approach(self, now)
		end,
	})

	self.scheduler:register({
		id = "chest",
		priority = 400,
		enabled = function()
			return store:get("boss.autoChest") == true
		end,
		tick = function(_dt, now)
			Boss.chestTick(self, now)
		end,
	})

	return self
end

return Boss
end

__modules["game/Size"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Size -- applying the self-resize decided by core/SizePolicy.

	One remote call, guarded, driven by a change detector. V1007 decided this
	inline every frame and called the remote whenever the value differed -- with
	the "last value" bookkeeping spread over two `if` statements in a different
	file. Splitting the policy out (core/SizePolicy) leaves this file with nothing
	to get wrong except the call itself.
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

__modules["game/PetMetrics"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	PetMetrics -- reading the player's rep-speed bonuses off the object tree.

	This is the adapter half of what used to be one function in V1007
	(scanPetMetrics): the arithmetic moved to core/RepBonus where it is tested,
	and what remains is the traversal and the field names.

	The field names are not guesses -- they were confirmed against the game and
	are documented here because getting one wrong silently reports zero:

	    equipped pets : Players.<me>.equippedPets.pet1..petN   (ValueBase = name)
	    pet bonus     : <pet>.perksFolder.repTimeBoostPercent  (Boss pets 5/7/10,
	                                                           Inferno Drake 40)
	    ultimate      : catalogs.gameUltimatesFolder["+5% Rep Speed"], 5% per level
	    gamepass      : Players.<me>.ownedGamepasses["x2 Rep Time"]

	The scan is throttled: it walks several containers, so it is not something to
	do every frame.
]]

local Players = game:GetService("Players")
-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).
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
	The bonus for one equipped pet.

	The live model is preferred, because an individual pet may have been upgraded;
	the static preview catalogue is the fallback for a pet whose model has not
	streamed in yet.
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
	The container name has changed between game versions, so several are tried.

	Order matters: the PLAYER containers are checked first because they hold the
	player's own levels, and only then the shared catalogue. The catalogue path
	(`ReplicatedStorage.shared.catalogs.gameUltimatesFolder`) is the one the
	module's own header documents as the source of truth, and it was missing from
	this list -- so on the game revision this script targets, the lookup could
	fail entirely and "终极反复 %" would sit at zero with the documented container
	sitting right there.
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

	The two decisions live in core and are tested there:
	    core/MachinePlan  which machine to use
	    core/MountState   when to hover, when to sit, when to give up

	What is left here is the object traversal and the engine calls: reading the
	machines folder, resolving a seat, and performing the "aim" / "sit" /
	"release" actions the state machine asks for.

	One robustness fix over V1007: the seat is read through occupantOf, which only
	touches `Occupant` on an actual Seat or VehicleSeat. The original read
	`seat.Occupant` on any BasePart, and `interactSeat` is frequently a plain
	Part -- where that raises "Occupant is not a valid member", inside a code path
	that had no pcall around it.
]]

-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).
local VirtualInputManager = game:GetService("VirtualInputManager")

local MachinePlan = require("core/MachinePlan")
local MountState = require("core/MountState")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")

local Machine = {}
Machine.__index = Machine

local SCAN_CACHE = 2
local HOVER_HEIGHT = 3
local SIT_HEIGHT = 1.2
local KEY_TAIL = 0.05

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
		isCombatBusy = context.isCombatBusy or function()
			return false
		end,
		isBossAlive = context.isBossAlive or function()
			return false
		end,
		--[[
			The arbitration handle.

			`isDamageNeeded` is the ONE question this subsystem needs answered:
			"would sitting here cost us a punch?" A machine blocks damage, so
			while the answer is yes the seat is released -- and because the
			question is re-asked every frame, the mount resumes by itself the
			moment the answer turns no. That automatic re-mount is the "raise the
			depth back afterwards" half of the protocol; nothing has to remember
			to undo the step-down.
		]]
		isDamageNeeded = context.isDamageNeeded or function()
			return false
		end,
		notify = context.notify or function() end,
		mount = MountState.new(),
		cache = {},
		cacheAt = 0,
		target = nil,
		attempts = 0,
		lastPhase = "idle",
	}, Machine)
	return self
end

--[[
	Every seat in the world, cached for two seconds.

	The scan walks machinesFolder, so it is not something to do every frame --
	but the cache must not be trusted forever either, since machines are streamed
	in and out as the player moves.
]]
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
				local seat = model:FindFirstChild("interactSeat")
				if seat == nil or not seat:IsA("BasePart") then
					seat = nil
					for _, child in ipairs(model:GetChildren()) do
						if child:IsA("Seat") or child:IsA("VehicleSeat") then
							seat = child
							break
						end
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
	Should the seat be given up right now?

	Three independent reasons, and the third is the one the refactor was missing:
	the machine was blocked by combat and by a live boss, but NOT by "something
	is required to be able to deal damage" consulted as a depth decision. The
	practical difference is that `isDamageNeeded` can be true for reasons neither
	of the other two covers (a boss being attacked by the boss-punch task while
	`kill.enabled` is off), which is exactly the combination that used to leave
	the player parked on a machine while auto-boss punched nothing.
]]
function Machine.blocked(self): boolean
	if self.isDamageNeeded() then
		return true
	end
	return self.isCombatBusy() or self.isBossAlive()
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
	self.mount:reset()
	self.target = nil
	self.lastPhase = "idle"
end

local function aim(self, root, seat)
	local ok, position = pcall(function()
		return seat.Position
	end)
	if not ok then
		return
	end
	pcall(function()
		root.Anchored = true
		root.CFrame = CFrame.new(position + Vector3.new(0, HOVER_HEIGHT, 0))
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)
end

local function sit(self, root, humanoid, seat)
	local ok, position = pcall(function()
		return seat.Position
	end)
	if ok then
		pcall(function()
			root.CFrame = CFrame.new(position + Vector3.new(0, SIT_HEIGHT, 0))
		end)
	end

	self.net:send("machine", os.clock(), "useMachine", seat)
	pcall(function()
		seat:Sit(humanoid)
	end)
	pcall(function()
		humanoid.Sit = true
	end)

	-- The touch pulse is what actually registers with some machines. The release
	-- is scheduled rather than slept through: the original blocked a coroutine for
	-- 0.05s here, and a blocked task cannot be cancelled on unload.
	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, seat, root, 0)
		self.timers:after(os.clock(), KEY_TAIL, function()
			pcall(firetouchinterest, seat, root, 1)
		end)
	end
	self.attempts += 1
end

function Machine.tick(self, now)
	local store = self.store
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	local hasCharacter = humanoid ~= nil and root ~= nil

	if self.target ~= nil and self.target.Parent == nil then
		self.target = nil
	end
	if hasCharacter and self.target == nil then
		self.target = Machine.resolve(self)
	end

	local seat = self.target
	local occupant = occupantOf(seat)
	local seated = hasCharacter and seat ~= nil and (humanoid.Sit == true or occupant == humanoid)
	local targetValid = seat ~= nil and seat.Parent ~= nil and (occupant == nil or occupant == humanoid)

	local result = self.mount:step({
		enabled = store:get("machine.enabled") == true,
		blocked = Machine.blocked(self),
		training = store:get("train.auto") == true or store:get("train.fast") == true,
		hasCharacter = hasCharacter,
		targetValid = targetValid,
		seated = seated,
	}, now)

	if result.timedOut then
		-- The seat is not cooperating; try a different one next time.
		self.target = nil
	end

	if result.action == "release" then
		Machine.dismount(self)
		return result
	end

	if hasCharacter then
		if result.action == "aim" and seat ~= nil then
			aim(self, root, seat)
		elseif result.action == "sit" and seat ~= nil then
			sit(self, root, humanoid, seat)
		elseif result.phase == "mounted" and root.Anchored then
			-- Attached: give the seat control of the body.
			pcall(function()
				root.Anchored = false
			end)
		end
	end

	self.lastPhase = result.phase
	return result
end

function Machine.stats(self)
	return {
		phase = self.mount.phase,
		attempts = self.attempts,
		target = if self.target ~= nil then self.target.Name else nil,
		seats = #Machine.seats(self),
	}
end

function Machine.install(context)
	local self = Machine.new(context)
	local store = self.store

	-- Sitting is a chained operation (hover, then interact, then touch), so the
	-- channel queues rather than dropping.
	self.net:addChannel("machine", GameNet.senderFor(function()
		return Remotes.machine()
	end), { rate = 4, burst = 2, queue = 8 })

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

__modules["game/PlayerStats"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	PlayerStats -- reading the leaderboard values.

	V1007's Core.stat looked in two places: a direct child, then leaderstats. The
	direct-child lookup is nearly always a miss (the game keeps these under
	leaderstats), but it is kept because it costs one failed lookup and some
	versions expose them flat.
]]

local PlayerStats = {}

function PlayerStats.value(player, name): number
	if player == nil or name == nil then
		return 0
	end
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

__modules["game/Rebirth"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Rebirth -- automatic rebirth, and the "pack rebirth" sequence.

	rebirthTick in V1007 carried six pieces of mutable state (pending, fails,
	cooldown, lastAt, reqAt, beforeStrength) that were only meaningful together,
	and the rules connecting them lived in the same function as the remote call
	and the pet-preset swap. It is now core/RebirthState, which is a pure
	function of (strength, rebirths, target, rate, now).

	Pack rebirth was a loop, a call and a repeat-until with task.wait() inside:
	uncancellable, unable to report progress, and its own two timeouts invisible.
	It is now core/PackState, an explicit training -> equipping -> requesting
	sequence, and this file just performs the actions it asks for.
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

	-- While waiting for a rebirth, move to the rebirth pet preset. scheduleSwap
	-- is a no-op when auto-switch is off, when the preset is empty, or when it is
	-- already active.
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
	Metrics -- the engine side of the frame/memory/ping figures.

	The accumulators (and their windows) are core/Metrics, which is tested. What
	is left here is three engine calls and their throttles:

	    frame rate   -- every frame, but the measurement only lands when the
	                    window closes
	    memory       -- once every 15 seconds: Stats:GetTotalMemoryUsageMb is a
	                    known hitch source, which is why V1007 backed it off too
	    ping         -- once a second, averaged by the core over the last five

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

--[[
	Rolling-window sizes for the two rate read-outs.

	Time-bounded (seconds) plus a hard sample cap, so the window means the same
	thing at any sampling cadence and cannot grow without bound if the caller is
	driven faster than expected.
]]
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
			local ok, seconds = pcall(function()
				return user:GetNetworkPing()
			end)
			if ok and seconds ~= nil and seconds > 0 then
				self.metrics:pushPing(seconds * 1000)
			end
		end
	end

	GameMetrics.trackStrength(self, now)
	GameMetrics.trackRebirths(self, now)
end

--[[
	Session strength, and the rate it is climbing at.

	The rate is measured between samples rather than averaged over the session, so
	a run that started slowly does not flatter the current figure. Kept here with
	the other read-outs because the info window and the rejoin logic both want it.
]]
--[[
	Push one sample into a bounded rolling window and return the window's rate.

	V1007 kept fixed-size sample windows for both the strength rate (它的
	`m.strength.sessionDelta` / per-second figure) and the rebirth rate (30
	samples). This revision measured between exactly TWO samples, which has two
	consequences the window avoids:

	  * one 40 ms frame that happens to gain strength reports an absurd per-second
	    figure, and the display then sits on it until the next gain;
	  * a rate that stops changing (no new gain) FREEZES at its last value instead
	    of decaying toward zero, so "每秒增长" keeps claiming a rate that is no
	    longer happening.

	The window is time-bounded rather than count-bounded so it behaves the same
	whatever cadence the caller samples at, and it is anchored at the first sample
	still inside the window -- so the elapsed time used for the rate is the age of
	that sample, not of the newest one.
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

--[[
	Rebirths, and how fast they are arriving.

	V1007 tracked this and the info window showed "重生/小时" (with a 1/7/30 day
	prediction) from it. The refactor kept the two ROW LABELS and dropped the
	tracking, so both rows sat on "-" forever -- they looked implemented and were
	not.

	The rate is measured between consecutive changes in the rebirth count, not
	over the whole session: a session that rebirths slowly at first should not
	flatter the current figure. Kept separate from the strength tracker because
	the two change at completely different rates.
]]
function GameMetrics.trackRebirths(self, now)
	local user = Players.LocalPlayer
	if user == nil then
		return
	end
	local value = PlayerStats.value(user, "Rebirths")

	if self.rebirthValue == nil then
		self.rebirthValue = value
		self.rebirthAt = now
		self.rebirthWindow = { { value = value, at = now } }
		return
	end
	--[[
		Sampled every call, not only when the count changes.

		The old behaviour only pushed a sample on a CHANGE, which is exactly why
		the figure froze: with no change there was no sample, so no window
		advanced and "重生/小时" kept reporting the last burst forever.
	]]
	self.rebirthWindow = self.rebirthWindow or {}
	local first = self.rebirthWindow[1]
	if first == nil or value ~= first.value then
		pushSample(self.rebirthWindow, value, now, REBIRTH_WINDOW_SECONDS, REBIRTH_WINDOW_CAP)
	end

	if value == self.rebirthValue then
		-- No change: keep the WINDOW advancing so the rate decays on its own,
		-- but do not resample the same value.
		return
	end

	local elapsed = now - (self.rebirthAt or now)
	local gained = value - self.rebirthValue
	self.rebirthValue = value
	self.rebirthAt = now
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
-- does not expose it. V1007 read this for its "重生倍率" row.
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

-- The current frame rate, for callers that want just that number (the adaptive
-- training rate). Kept as an accessor so the core accumulator stays the only
-- thing that knows how it is measured.
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
	Rejoin -- leaving and coming back: on a timer, on a bad-client trigger, or on
	an error prompt.

	The decision rules are pure and tested (core/RejoinTriggers for "is the client
	in a bad enough state", core/ServerPick for "where do we go"). This file is
	the HTTP call, the teleport call, and the three tasks that drive them.

	One deliberate exception to "no ad-hoc coroutines": performing a rejoin makes
	a BLOCKING http request, and blocking the frame for the duration of a network
	round trip would freeze the game. It runs in a task.spawn for that reason
	alone, and it ends in a teleport -- the session is over either way. This is
	the only such spawn in the refactor.
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
		attempts = 0,
	}, Rejoin)
	return self
end

local function httpGet(url)
	local executor = (type(syn) == "table" and syn.request)
		or (type(http) == "table" and http.request)
		or (type(fluxus) == "table" and fluxus.request)
		or request
		or http_request
	if type(executor) == "function" then
		local ok, response = pcall(executor, { Url = url, Method = "GET" })
		if ok and type(response) == "table" then
			return response.Body or response.body
		end
		return nil
	end
	if type(game.HttpGet) == "function" then
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok then
			return body
		end
	end
	return nil
end

--[[
	Fetch the public server list.

	A failure starts a five-minute cooldown: the endpoint is rate limited and a
	rejoin is not urgent enough to hammer it. V1007 did the same, inline.
]]
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

-- Actually leave. Runs off the frame path (see the module comment).
function Rejoin.perform(self, reason)
	self.notify("正在重进...", "warn")

	local mode = self.store:get("rejoin.mode") or "same"
	local servers = {}
	if mode ~= "private" then
		local order = if mode == "sparse" then "Asc" else "Desc"
		servers = Rejoin.fetchServers(self, order) or {}
	end

	local plan = ServerPick.plan(mode, servers, game.JobId, self.store:get("rejoin.privId"))
	local user = Players.LocalPlayer
	if user == nil then
		return false
	end

	if plan.code ~= nil then
		local ok = pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, plan.code, { user })
		end)
		if ok then
			self.attempts += 1
			return true
		end
	end

	for _, id in ipairs(plan.ids) do
		local ok = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, id, user)
		end)
		if ok then
			self.attempts += 1
			return true
		end
	end

	self.notify("服务器尝试失败，返回原服", "warn")
	pcall(function()
		TeleportService:Teleport(game.PlaceId, user)
	end)
	return false
end

-- Off-frame wrapper. The only task.spawn in the refactor, and documented above.
function Rejoin.spawnPerform(self, reason)
	task.spawn(function()
		pcall(function()
			Rejoin.perform(self, reason)
		end)
	end)
end

--[[
	Ask to rejoin.

	Urgent requests go immediately; everything else gets a three-second,
	cancellable countdown. V1007 showed a modal here -- without a UI the countdown
	is a timer and `cancelPending` is what the modal's Cancel button will call.
]]
function Rejoin.request(self, reason, urgent)
	if os.clock() - self.startedAt < STARTUP_GRACE then
		self.notify("游戏正在加载，15 秒内禁止重进", "warn")
		return false
	end
	if self._triggered or self._state ~= "idle" then
		return false
	end

	if urgent then
		self._state = "running"
		self._triggered = true
		Rejoin.spawnPerform(self, reason)
		return true
	end

	self._state = "pending"
	self.notify(string.format("原因：%s\n3 秒后自动重进（可取消）", tostring(reason or "")), "warn")

	--[[
		The cancel dialog.

		V1007 showed a modal here and the refactor left only the timer: the toast
		promised "可取消" while `cancelPending` had no caller anywhere in src/, so
		the countdown could not actually be stopped. The UI is injected rather
		than constructed here because this module must stay ui-free (it is in
		game/, and the module is exercised without a shell in tests).

		`onPending` receives the two actions; it returns nothing and may be nil
		(no UI, or a headless run), in which case the countdown simply proceeds.
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
			self._state = "running"
			self._triggered = true
			Rejoin.spawnPerform(self, reason)
			return true
		end)
	end

	self.pendingHandle = self.timers:after(os.clock(), CONFIRM_DELAY, function()
		if self._state ~= "pending" then
			return
		end
		self.pendingHandle = nil
		self._state = "running"
		self._triggered = true
		Rejoin.spawnPerform(self, reason)
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
	Put the state machine back to idle, dropping any pending countdown.

	This exists so a caller (the manual-rejoin button, a keybind) never has to
	assign `_state` / `_triggered` itself. Those are the machine's own
	bookkeeping: writing them from outside couples the UI to the implementation
	and breaks silently the moment the states are renamed or become an enum.
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
-- cancellable countdown, not the urgent path).
function Rejoin.requestNow(self, reason)
	Rejoin.reset(self)
	return Rejoin.request(self, reason, false)
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
		`promptOverlay` is a Frame, and a Frame has no `Enabled` property.

		The original check read `overlay.Enabled ~= true`, which raised
		"Enabled is not a valid member of Frame" on EVERY tick -- the rejoin
		emergency task runs constantly, so this flooded the log (the user saw
		"另有 59 条同类错误被折叠" every 30 seconds) and meant the emergency path
		never actually detected a disconnect.

		`Visible` is the property a Frame has, and it is also the one that means
		"the prompt is on screen". The read is guarded so a future Roblox change
		to this container cannot flood the log again.
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

	return self
end

return Rejoin
end

__modules["game/AntiAfk"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	AntiAfk -- staying connected while idle.

	Two mechanisms, because one is not enough:

	    Player.Idled       -- the reliable signal; Roblox raises it when it is
	                          about to treat the player as away. Capturing the
	                          controller and clicking is the documented response.
	    a periodic click   -- a fallback for anything that does not raise Idled,
	                          on a user-configurable interval (default 300s, and
	                          the game's own idle timeout is 20 minutes).

	The interval is capped at 1140 seconds by the config schema, so it always
	fires at least once before Roblox's 20-minute limit.

	The periodic task is registered as `essential`, which is what makes "pausing
	the script" mean "stop the automation", not "stop the thing that keeps me
	connected". A paused scheduler skips every non-essential task, so without the
	flag the settings hint was simply false and pausing for a long time could get
	the player kicked.

	The Idled connection is handed to the Runtime rather than kept here, so the
	"every connection is owned by the Runtime" invariant holds.
]]

local Players = game:GetService("Players")
-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).
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
		-- Set by bindKick when the client is disconnected; also stops the timer
		-- from fighting the teardown.
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
	KICK DETECTION.

	`LocalPlayer.AncestryChanged` fires with `Parent == nil` when the client is
	disconnected (kicked, dropped, or shut down). V1007 watched this through its
	rejoin path and treated it as an urgent rejoin trigger; the refactor kept the
	rejoin machinery and dropped the signal, so a kick was only noticed if the
	Roblox error prompt happened to appear -- and if the prompt was dismissed, the
	session sat there doing nothing with every task still "running".

	The request is made URGENT (`Rejoin.request(reason, true)`), which skips the
	3-second countdown: by the time this fires, the countdown's window has
	already passed, and waiting would only delay the requeue.
]]
function AntiAfk.bindKick(self, rejoin)
	local user = Players.LocalPlayer
	if user == nil or rejoin == nil then
		return
	end
	--[[
		Probe the signal rather than assuming it.

		`AncestryChanged` exists on Instance in the real engine, but it is not
		universally present on a Player proxy in every executor or test harness --
		and the smoke harness is exactly such a case: the first version of this
		crashed the whole boot with "attempt to index nil with 'Connect'". A
		missing signal means "no kick detection available", not "fail to start".
	]]
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
		-- A short delay so a genuine shutdown is not fought with a teleport or a
		-- remote call during teardown.
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
	Perf -- the anti-lag pass: hide particles, kill shadows, flatten the lighting.

	Ported from Core.Perf in V1007. One behaviour change, and it matters on a big
	map: the original walked Workspace:GetDescendants() once inside a coroutine,
	giving up after eight seconds and holding whatever it had managed to disable.
	On a large place that meant a partially applied optimisation whose extent
	depended on how busy the machine was.

	This version snapshots the list, then walks it with a fixed per-frame budget,
	so it always finishes and never stalls a frame doing it. The snapshot is taken
	on the first tick rather than inside enable(), because GetDescendants() on a
	large place is itself the expensive part.

	A pass is followed by a LONG pause (RESCAN_SECONDS) before the next one. That
	pause is the fix for a real defect: the first revision cleared the snapshot
	when the walk finished, so the very next tick re-walked the whole of Workspace
	and the anti-lag pass became the stutter it was meant to remove. Re-sweeping
	slowly (rather than never) keeps objects that stream in later covered.

	Everything disabled is remembered and put back, so switching the option off
	restores the world.
]]

-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).
local Lighting = game:GetService("Lighting")

local Perf = {}
Perf.__index = Perf

local BUDGET_PER_TICK = 500
local RESCAN_SECONDS = 45

function Perf.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		lighting = nil,
		particles = {},
		shadows = {},
		snapshot = nil,
		cursor = 0,
		disabled = 0,
		nextScanAt = nil,
	}, Perf)
	return self
end

function Perf.enable(self)
	if self.lighting ~= nil then
		return
	end
	self.lighting = {
		GlobalShadows = Lighting.GlobalShadows,
		ShadowSoftness = Lighting.ShadowSoftness,
	}
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.ShadowSoftness = 0
	end)
	self.particles = {}
	self.shadows = {}
	self.snapshot = nil
	self.cursor = 0
	self.disabled = 0
	-- Due immediately: the first sweep starts on the next tick.
	self.nextScanAt = 0
end

function Perf.tick(self, now)
	if self.lighting == nil then
		return
	end

	local list = self.snapshot
	if list == nil then
		-- Between sweeps. Without this gate the snapshot was cleared on
		-- completion and the next tick immediately re-walked every descendant,
		-- turning the anti-lag pass into a recurring frame spike.
		if now < (self.nextScanAt or 0) then
			return
		end
		local ok, descendants = pcall(function()
			return Workspace:GetDescendants()
		end)
		if not ok then
			-- A failed walk must not be retried every frame either.
			self.nextScanAt = now + RESCAN_SECONDS
			return
		end
		self.snapshot = descendants
		self.cursor = 0
		return
	end

	local last = math.min(#list, self.cursor + BUDGET_PER_TICK)
	for index = self.cursor + 1, last do
		local object = list[index]
		if object.Parent ~= nil then
			local class = object.ClassName
			if class == "ParticleEmitter" or class == "Trail" or class == "Beam" then
				if object.Enabled then
					object.Enabled = false
					table.insert(self.particles, object)
					self.disabled += 1
				end
			elseif class == "BasePart" and object.CastShadow then
				object.CastShadow = false
				table.insert(self.shadows, object)
				self.disabled += 1
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

	for _, object in ipairs(self.particles) do
		if object.Parent ~= nil then
			pcall(function()
				object.Enabled = true
			end)
		end
	end
	table.clear(self.particles)

	for _, object in ipairs(self.shadows) do
		if object.Parent ~= nil then
			pcall(function()
				object.CastShadow = true
			end)
		end
	end
	table.clear(self.shadows)

	local saved = self.lighting
	if saved ~= nil then
		self.lighting = nil
		pcall(function()
			Lighting.GlobalShadows = saved.GlobalShadows
			Lighting.ShadowSoftness = saved.ShadowSoftness
		end)
	end
end

function Perf.stats(self)
	return {
		active = self.lighting ~= nil,
		disabled = self.disabled,
		scanning = self.snapshot ~= nil,
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

	return self
end

return Perf
end

__modules["game/Train"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Train -- the automatic training subsystem.

	The whole subsystem is now three lines of policy plus one call:

	    read the settings from the store
	    ask TrainRate how many packets this frame is worth   (pure, tested)
	    ask Net to burst that many                         (pure, tested)

	Everything that used to make this untestable -- reaching for the remote,
	firing in a loop, deciding the rate from three different flags in one
	function -- has moved either into core (tested) or into the channel's sender
	(one line in src/game/Net).

	Wire throttling follows cfg.trainThrottle: OFF means the "muscle" channel is
	unlimited, which is what fast training is for and what V1007 hard-coded.
	ON puts it behind a real token bucket. Either way the pacing arithmetic is
	the same, and the channel keeps its own sent/dropped/penalty counters.
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
	Consecutive-send-failure latch.

	V1007 counted consecutive rep-send errors and gave up after 15
	(`Core.failCounters_train`, its lines 1818 and 1828-1829). The refactor kept
	the counting that `Net` does per channel but dropped the LATCH, and `Net.burst`
	only breaks the burst it is in -- so a muscle remote that exists but rejects
	every call gets retried at full rate on every single frame. That is both a
	waste and a plausible kick trigger.

	This is the same shape as the scheduler's own task backoff: fail N times, sit
	out a window, then try again. The window matters more than the count, because
	a transient failure must not disable training for the session.
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
				adaptive = store:get("train.adaptive") == true,
				adaptiveThresh = tonumber(store:get("train.adaptiveThresh")) or 30,
				-- Was written by the UI and read by nobody (in V1007 either).
				adaptiveMax = tonumber(store:get("train.adaptiveMax")) or 5000,
			}
			-- Adaptive rate needs the measured frame rate. `context.metrics` is
			-- the game metrics service; reading it is cheap (a field), and a
			-- missing/silent sample leaves the default in place rather than
			-- disabling the feature.
			local fps = 60
			local metrics = context.metrics
			if metrics ~= nil then
				local ok, sample = pcall(function()
					return metrics:fps()
				end)
				if ok and type(sample) == "number" and sample > 0 then
					fps = sample
				end
			end

			local rate = TrainRate.compute(settings, fps)
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
					Nothing at all got through: treat that as one failure step.

					`refused` counts REFUSED payloads, which includes the ordinary
					case of a rate limiter doing its job, so a latch keyed on it
					would fire during normal throttling. The latch is keyed on
					`sent == 0` instead, and only after a burst was actually
					attempted -- one frame of backpressure is not a failure.
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
		快速锻炼 / 自动锻炼 are mutually exclusive, and the UI says so
		("与自动锻炼互斥") -- but nothing enforced it, so both keys could be on at
		once and `TrainRate.compute` silently let `fast` win. A store subscription
		rather than an onChange so that a loaded config or a config slot is covered
		too, not just a click.
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
		ANNONCE THE DEPTH, and switch the training pet preset.

		A low-priority reporter task (priority 5, so it runs after everything that
		could change the answer) that publishes the resolved depth to the store
		for the UI to read, and asks for the "train" pet preset while training is
		actually happening.

		The preset request is what makes `petPreset.train` reachable at all: only
		the rebirth path ever called Pets.scheduleSwap, so the train/kill/boss
		presets were configurable in the UI and never applied in game.
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
		Keep a training tool in hand.

		The preference order is the one V1007 used, and it is expressed as a list of
		keyword groups so that "which tool would we rather hold" is data rather than
		four nested ifs.

		Two guards matter: the task stands down while a machine is holding the
		player (sitting is itself the exercise), and while dual-tool combat has
		taken over the glove.
	]]
	local missingSince = 0
	local lastAttempt = 0
	local lastRespawn = 0
	local respawns = 0
	local cooldown = false

	--[[
		Clear the give-up latch when the user asks for a tool.

		The latch stops the task from killing the player over and over when no
		training tool exists, and it also zeroes the four "which tool" toggles.
		Without a way back, that was a ONE-WAY DOOR for the whole session: the UI
		still showed the toggles, turning one back on did nothing, and the only
		fix was reloading the script.

		Only `value == true` clears it. The give-up path itself writes these keys
		(as false), and reacting to that would immediately un-latch the task and
		recreate the loop the latch exists to prevent.
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
			THE "同时锻炼 / 同时重生" POLICY.

			`train.duringBoss` and `train.duringKill` used to be toggles with no
			reader at all: turning them on changed nothing, and the real gating
			was `boss.auto and isBossAlive` plus `isCombatBusy`, unconditionally.

			What the user asked for is not "ignore the conflict" but "step down
			and carry on": while the main task runs, training lowers its depth
			out of the way (the machine releases the seat -- see Machine.blocked
			and the `damage` requirement) and then keeps going on the lower rungs.
			So the flags now decide whether this task stands down or steps down:

			    duringBoss off -> stand down while a boss fight is running
			    duringBoss on  -> keep training, at whatever depth survives
			    duringKill off -> stand down while the kill loop is running
			    duringKill on  -> keep training alongside it
		]]
		enabled = function()
			if not (store:get("train.auto") == true or store:get("train.fast") == true) then
				return false
			end
			if cooldown then
				return false
			end
			if store:get("boss.auto") == true and isBossAlive() then
				if store:get("train.duringBoss") ~= true then
					return false
				end
			end
			-- The machine holding the player IS the exercise, so there is nothing
			-- for the tool task to do. This is not the boss/combat conflict: it is
			-- the case where training is already happening at a HIGHER depth.
			if isMachineBusy() then
				return false
			end
			if isCombatBusy() then
				if store:get("train.duringKill") ~= true then
					return false
				end
				-- Dual-tool combat keeps the glove; the `dual` task swaps the
				-- training tool in on its own schedule. Handing the tool task the
				-- glove as well would make the two fight over it every frame.
				if store:get("kill.dualEnabled") == true then
					return false
				end
			end
			return true
		end,
		tick = function(_dt, now)
			if now - lastAttempt < 0.12 then
				return
			end
			lastAttempt = now

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
			if #groups == 0 then
				missingSince = 0
				return
			end

			local humanoid = character:humanoid()
			local tool = character:current()
			if Tools.equipFirst(tool, humanoid, Players.LocalPlayer, groups) then
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
		end,
	})

	--[[
		Alternate the glove and a training tool while fighting.

		V1007 flipped a mode string every 0.05s. Same idea, but the two halves are
		explicit and it stands down whenever the glove is not the right thing to
		hold.
	]]
	local dualMode = "punch"
	local lastDual = 0

	scheduler:register({
		id = "dual",
		priority = 62,
		enabled = function()
			if store:get("kill.dualEnabled") ~= true then
				return false
			end
			if not (store:get("train.auto") == true or store:get("train.fast") == true) then
				return false
			end
			if not isCombatBusy() then
				return false
			end
			return true
		end,
		tick = function(_dt, now)
			if now - lastDual < 0.05 then
				return
			end
			lastDual = now

			local humanoid = character:humanoid()
			local current = character:current()
			if humanoid == nil or current == nil then
				return
			end

			if dualMode == "punch" then
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
				if #groups > 0 and Tools.equipFirst(current, humanoid, Players.LocalPlayer, groups) then
					dualMode = "train"
				end
			else
				Tools.equip(current, humanoid, Players.LocalPlayer, Tools.PUNCH)
				dualMode = "punch"
			end
		end,
	})

	return {
		task = definition,
		state = state,
		stats = function()
			return { delivered = delivered, refused = refused }
		end,
	}
end

return Train
end

__modules["ui/Theme"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Theme -- the colour roles, and repainting a live UI when the theme changes.

	The mapping decision is core/Palette (pure, tested). This file holds the role
	tables, converts to Color3, and walks a GUI tree applying the remap.

	V1007's switch rebuilt the entire interface, which is why the colours "hard
	cut" and why the window jumped: a rebuild restores the position from the last
	save, which can be up to eight seconds stale. Repainting in place means the
	colours tween across and nothing moves.
]]

local TweenService = game:GetService("TweenService")

local Palette = require("core/Palette")
local Attributes = require("core/Attributes")

local Theme = {}

--[[
	The palette types are declared locally rather than referenced as
	Palette.RGB / Palette.Roles / Palette.Remap.

	A cross-module type annotation does not survive bundling: the bundler replaces
	`require` with a module loader, so `Palette` is no longer a type namespace in
	the shipped file and the analyzer reports "Unknown type 'Palette.RGB'". The
	src gate cannot see this -- it only appears in the dist gate.
]]
type RGB = { r: number, g: number, b: number }
type Roles = { [string]: RGB }
type RemapEntry = { from: RGB, to: RGB }
type Remap = { exact: { [string]: RGB }, entries: { RemapEntry } }

Theme.NAMES = { "light", "dark", "ocean", "sakura", "forest", "flame" }
Theme.FALLBACK = "light"
-- Per-channel tolerance for "is this widget wearing the old theme's colour?".
-- 6/255 is deliberately narrow: it is enough to catch a widget caught mid-tween
-- or sitting on a hover shade (the cases that used to keep the old colour and
-- make a switch look patchy) while staying well inside the ~15-unit gaps
-- between distinct palette roles, so a colour is never remapped to a neighbour.
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

-- A membership set, because `Theme.palette` cannot be used to test validity: it
-- FALLS BACK to the default rather than returning nil, so `Theme.palette(name)
-- == nil` is dead code that is false for every input -- including a typo'd
-- theme name, which would sail through and be written to the store.
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

function Theme.toRGB(color: Color3): RGB
	return {
		r = math.floor(color.R * 255 + 0.5),
		g = math.floor(color.G * 255 + 0.5),
		b = math.floor(color.B * 255 + 0.5),
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

--[[
	Repaint a GUI tree in place.

	Returns how many properties were changed, which the caller can log -- a
	silent zero is exactly the failure mode the original had.

	A tolerance is used so that widgets caught mid-tween or in a hover state are
	still recognised as "the old theme's border colour" rather than being left
	behind.
]]
function Theme.apply(root: Instance?, remap: Remap, duration: number?): number
	if root == nil then
		return 0
	end
	local time = duration or Theme.RECOLOR_TIME
	local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local changed = 0

	for _, object in ipairs(root:GetDescendants()) do
		for _, property in ipairs(COLOR_PROPERTIES) do
			local ok, current = pcall(function()
				return object[property]
			end)
			if ok and typeof(current) == "Color3" then
				local mapped = Palette.nearest(remap, Theme.toRGB(current), Theme.RECOLOR_TOLERANCE)
				if mapped ~= nil then
					pcall(function()
						TweenService:Create(object, tweenInfo, { [property] = Theme.toColor3(mapped) }):Play()
					end)
					changed += 1
				end
			end
		end

		local stroke = object:FindFirstChildOfClass("UIStroke")
		if stroke ~= nil then
			local mapped = Palette.nearest(remap, Theme.toRGB(stroke.Color), Theme.RECOLOR_TOLERANCE)
			if mapped ~= nil then
				TweenService:Create(stroke, tweenInfo, { Color = Theme.toColor3(mapped) }):Play()
				changed += 1
			end
		end

		local gradient = object:FindFirstChildOfClass("UIGradient")
		if gradient ~= nil then
			local keypoints = {}
			local touched = false
			for _, keypoint in ipairs(gradient.Color.Keypoints) do
				local mapped = Palette.nearest(remap, Theme.toRGB(keypoint.Value), Theme.RECOLOR_TOLERANCE)
				if mapped ~= nil then
					touched = true
					table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, Theme.toColor3(mapped)))
				else
					table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, keypoint.Value))
				end
			end
			if touched then
				pcall(function()
					TweenService:Create(gradient, tweenInfo, { Color = ColorSequence.new(keypoints) }):Play()
				end)
				changed += 1
			end
		end

		-- Buttons remember their resting colour in an attribute so that a hover
		-- leaving cannot write the previous theme's colour back.
		local base = object:GetAttribute(Attributes.BASE_COLOR)
		if typeof(base) == "Color3" then
			local mapped = Palette.nearest(remap, Theme.toRGB(base), Theme.RECOLOR_TOLERANCE)
			if mapped ~= nil then
				object:SetAttribute(Attributes.BASE_COLOR, Theme.toColor3(mapped))
				changed += 1
			end
		end
	end

	return changed
end

return Theme
end

__modules["ui/Kit"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	Kit -- the interface component library.

	The one architectural change that matters: a bound component READS and WRITES
	the Store, and re-renders from a Store subscription. It does not keep its own
	copy of the value.

	V1007's UI.toggle held a local `val` while Core.train.auto held the real one,
	and the two were reconciled by a one-hertz polling loop (Core.syncUI). Nothing
	could express "this changed", so the copies drifted, a missed pass left a
	control permanently out of step, and a control that silently stopped working
	was the normal failure mode.

	Here there is exactly one place the value lives. The click handler writes to
	it; the subscription is what repaints. `spec.path` is that place, named.

	Components without a path (buttons, notes) keep no state at all.
]]

local TweenService = game:GetService("TweenService")

local Attributes = require("core/Attributes")

local Kit = {}
Kit.__index = Kit

local ROW_HEIGHT = 40
local ROW_HEIGHT_WITH_HINT = 52
local DROPDOWN_MAX_HEIGHT = 300
local DROPDOWN_OPTION_HEIGHT = 26

function Kit.new(context)
	--[[
		Guard against the collision that silently broke the entire interface.

		The widget factory is `Kit.instance(class, props, parent)`. Calling the
		CONSTRUCTOR as if it were that factory does not raise, in either form:

		    self:new("Frame", props, parent)   -> Kit.new(self, "Frame", ...)
		    Kit.new("Frame", props, parent)    -> context is a string

		A string indexes to nil rather than erroring, and in the colon form the
		Kit itself arrives as `context` and brings a perfectly good `.store` and
		`.roles` with it. Either way the call succeeded and returned a Kit where
		an Instance was expected -- so every widget in the UI became a Kit, and
		the damage only showed up later, on the first `uiCorner.Parent = <kit>`,
		as an empty page.

		Both forms are rejected here: a plain context table is the only valid
		input, and a Kit is never one.
	]]
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

--------------------------------------------------------------------- plumbing --

--[[
	Resolve a role to a colour.

	Three levels, because the return value is assigned straight to Roblox colour
	properties: a miss on both the role and its fallback used to return nil, and
	`BackgroundColor3 = nil` is a hard error. A mistyped role should look wrong,
	not crash the window. The last resort is opaque white, which every theme has
	as a surface colour.
]]
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

-- Ordering is a counter per parent, not `#parent:GetChildren() * 10`.
-- The original recomputed that for every widget, which is quadratic over a page
-- with fifty controls in it.
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

--[[
	Schedule a delayed UI callback.

	Through the runtime's Timers when one was injected, so that
	`Runtime.destroy()` cancels it along with everything else; a raw `task.delay`
	cannot be cancelled, so on unload every pending one still fires and each has
	to defend itself with a `self.destroyed` / `parent ~= nil` guard. Those guards
	are a symptom -- the fix is that the timer dies with the runtime.

	`task.delay` remains the fallback for a Kit built without a runtime (e.g. a
	unit test), so this never turns a missing dependency into a crash.
]]
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

--[[
	Bind a widget to a store path.

	`apply` renders a value. It runs once immediately with the current value (or
	`default` when the store has none) and again on every subsequent change --
	including changes made by another subsystem, which is what makes the widget
	and the state structurally incapable of disagreeing.

	The second argument tells `apply` whether this is the initial paint. An
	animating widget must snap on it: the widget is constructed with the fallback
	and then corrected to the stored value in the same frame, and tweening that
	correction made every control on a freshly opened page visibly flip itself.
]]
function Kit.bind(self, path, default, apply)
	local current = self.store:get(path)
	apply(if current == nil then default else current, true)
	self:track(self.store:subscribe(path, function(_, value)
		if value ~= nil then
			apply(value, false)
		end
	end))
end

------------------------------------------------------------------------- layout --

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
	self:instance("TextLabel", {
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
	if hint ~= nil then
		self:instance("TextLabel", {
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
		if self.theming then
			return
		end
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

------------------------------------------------------------------------- widgets --

--[[
	spec = { label, path?, default?, onChange?, hint? }

	When `path` is set the toggle is a view onto that store key: clicking writes
	it, and the subscription repaints. When it is not, the toggle keeps its own
	value and calls `onChange` -- for the rare control that has no state.
]]
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
		-- rebirth" is really `rebirth.rate > 0`. Reading and writing go through
		-- the caller, and it re-renders whenever the watched key moves.
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
				render(value)
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

	local hit = self:instance("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		ZIndex = 4,
	}, trackBar)

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

	--[[
		The drag rectangle is captured on press and held for the whole gesture.

		The original re-read AbsolutePosition and AbsoluteSize on every mouse
		event. Changing a slider that resizes the window moves the track, so the
		next event computed a completely unrelated fraction -- 45 would jump to 15
		and then to 40.
	]]
	local rect = nil
	local function applyFromX(x)
		if rect == nil or rect.width <= 0 then
			return
		end
		local f = math.clamp((x - rect.x) / rect.width, 0, 1)
		local next = math.clamp(math.floor(minimum + (maximum - minimum) * f + 0.5), minimum, maximum)
		if next ~= current then
			render(next)
			if spec.path ~= nil then
				self.store:set(spec.path, toStore(next))
			end
			if not spec.commitOnly and spec.onChange ~= nil then
				task.spawn(spec.onChange, next)
			end
		end
	end

	self:track(hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local position = trackBar.AbsolutePosition
		local size = trackBar.AbsoluteSize
		rect = { x = position.X, width = size.X }
		self:tween(knob, 0.1, { Size = UDim2.fromOffset(26, 26) })
		applyFromX(input.Position.X)
	end))

	self:track(hit.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if rect == nil then
			return
		end
		rect = nil
		self:tween(knob, 0.16, { Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Quint)
		if spec.commitOnly and spec.onChange ~= nil then
			task.spawn(spec.onChange, current)
		end
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

	-- A full-screen invisible button eats every click outside the panel. Relying
	-- on an InputBegan check alone let clicks fall through to whatever was under
	-- the open panel.
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
		--[[
			The hide is deferred until the close tween has run, and it must only
			apply to the close it belongs to. Reopening during those 0.17s used to
			leave the old hide pending, so the freshly opened panel was hidden
			again the moment it appeared -- the dropdown "did not open" if you
			clicked it twice quickly.

			Re-checking `open` is what ties the callback to its own close.
		]]
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

	local function draw()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for index, option in ipairs(values) do
			local entry = self:instance("TextButton", {
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
			self:track(entry.MouseButton1Click:Connect(function()
				currentDisplay = tostring(option)
				button.Text = currentDisplay .. "  ▾"
				if spec.path ~= nil then
					local stored = option
					if mapping ~= nil and mapping.toStore ~= nil then
						stored = mapping.toStore(option)
					end
					self.store:set(spec.path, stored)
				end
				if spec.onSelect ~= nil then
					task.spawn(spec.onSelect, option)
				end
				closePanel()
			end))
		end
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

	--[[
		Scroll or touch-drag dismisses the list.

		V1007 closed on either, and it matters more here than it looks: the panel
		is parented to the ScreenGui to escape the page's clipping, so scrolling
		the page underneath while the list is open used to leave a floating panel
		pinned over content that had scrolled away from its trigger.
	]]
	self:track(listFrame.InputChanged:Connect(function(input)
		if not open then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel
			or input.UserInputType == Enum.UserInputType.Touch then
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
			values = nextValues
			if nextDefault ~= nil then
				currentDisplay = tostring(nextDefault)
				button.Text = currentDisplay .. "  ▾"
			end
			draw()
		end,
		--[[
			Show a value without re-declaring the option list.

			`refresh` needs both arguments and rebuilding the list on every call is
			wasteful when only the trigger text changes. More importantly, calling
			`refresh(values, nil)` deliberately PRESERVES the selection, whereas
			`set` is the explicit "make the button say this" call -- the two are
			different intents and conflating them is how a refresh silently
			reset a user's choice.
		]]
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

	Why this exists: the main window has three shapes (normal, minimised title
	bar, floating pill) and each shape decides four things (size, corner radius,
	which layers are visible, and whether the pill overlay is up). That decision
	was spread across `applySize`, `setMinimized` and `setPill`, and the three
	disagreed:

	  * `setMinimized` had NO restore branch -- it unconditionally morphed to
	    MINIMIZED_HEIGHT and hid the panels, so `setMinimized(false)` collapsed an
	    already-collapsed window. The minimise button flipped the store flag, the
	    window never came back, and the store said "not minimised" while the
	    screen said otherwise.
	  * the collapsed bar was sized `UDim2.new(1, 0, 0, MINIMIZED_HEIGHT)` -- FULL
	    SCREEN width -- instead of the width of the window it collapsed from, so
	    it did not line up with anything.
	  * `applySize` computed the same three cases a third time, with its own copy
	    of the same constants.

	Computing the state in ONE pure function over (pill, minimized, width,
	height) means every combination is enumerable and testable without Roblox --
	which is the only way this class of bug stops being found by the user.

	Per-shape visibility, and why:

	    topBar     the drag handle and the window buttons; up in normal and
	               minimised, down in pill (the pill IS the handle)
	    nav        the page list; only meaningful when there is a content area
	    content    the page area; down whenever the window is a bar or a pill
	    topFill    a strip that squares off the bottom of the top bar so it does
	               not show a rounded seam against the content. Only there IS
	               content below it in normal mode.
	    status     the status line; kept while minimised (it is the only
	               feedback left), hidden in pill because the pill has its own
	               live line
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
--[[
	Shell -- the window: top bar, navigation, pages, dragging, pill mode, theme.

	Everything the shell owns is driven by the Store:

	    uiState.theme       which palette is active
	    uiState.minimized   the collapsed bar
	    uiState.widthPct    window width as a share of the screen
	    uiState.heightPct   ditto for height
	    uiState.uiScale     internal scale
	    uiState.savedMain   where the user dragged it

	So a change made anywhere -- a settings slider, a future keybind, the config
	file -- moves the window. There is no second copy of "is it minimised" to fall
	out of step, which is why the original's minimise button and its saved state
	could disagree.

	Two defects from V1007 are fixed here by construction:

	  * uiPctRange ignored the resolution factor, so on a 4K screen (factor 1.6) a
	    100% window actually covered 160% of the screen. The range is computed from
	    the real coverage now.
	  * dragging divided the mouse delta by a scale PROBED by moving the window
	    eight pixels and reading it back -- which made the window twitch on every
	    drag. The scale is not a mystery: the shell sets it, so the shell uses it.
]]

local UserInputService = game:GetService("UserInputService")
-- `Workspace` is a real Roblox global; no local alias (see game/Boss for why).

local Theme = require("ui/Theme")
local ShellState = require("core/ShellState")
local Format = require("core/Format")
local Attributes = require("core/Attributes")

local Shell = {}
Shell.__index = Shell

--[[
	Human-readable names for the scheduler's task ids, used by the status bar and
	the pill. V1007 had this table; without it the status line can only show
	"空闲中" because a raw id like "kingKill" is not something to put in front of
	a user.
]]
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
	--[[
		The five that were missing.

		`Shell.bindStatus` walks the scheduler's ACTIVE list, so any running task
		without an entry here was silently dropped from the status bar and the
		pill: the bar said "空闲中" while five tasks were in fact running. These
		are exactly the ids the scheduler registers.
	]]
	["bossPunch"] = "打Boss出拳",
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
local MORPH_COVER_TIME = 0.14

-- The three shapes' sizes and layers live in core/ShellState, so the pure state
-- table is the single source of truth for them. Re-declaring the numbers here is
-- how applySize / setMinimized / setPill came to disagree in the first place.
local PILL_WIDTH = ShellState.PILL_WIDTH
local PILL_HEIGHT = ShellState.PILL_HEIGHT

Shell.PILL_SIZE = Vector2.new(PILL_WIDTH, PILL_HEIGHT)

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
		-- The subsystems a hotkey may need to reach (motion, teleport). Kept so
		-- the shell does not have to grow a getter per action.
		services = context.services or {},
		-- Read for the status bar's "what is running" list.
		scheduler = context.scheduler,
		uiTicks = {},
		pages = {},
		built = false,
		activeTab = nil,
		themeName = context.store:get("uiState.theme") or "light",
		connections = {},
		-- Incremented by every morph. A morph's delayed steps abort as soon as a
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

--[[
	Register a slow refresh for read-outs that are not bound to a store key --
	a retry counter, a scan result.

	These run on a timer rather than per frame, and they exist so a page never has
	to open its own loop: the original had each read-out on whatever connection it
	could grab.
]]
function Shell.addUiTick(self, fn)
	table.insert(self.uiTicks, fn)
	return fn
end

-- Pages report through the shell, so they never need a reference to the toast
-- stack (and keep working before it exists). `duration` is optional; see
-- Toast.show.
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

--------------------------------------------------------------------- geometry --

--[[
	The legal range for widthPct / heightPct.

	Coverage = pct/100 * uiScale * resolutionFactor, and it must not exceed 90%.
	V1007 computed this from uiScale alone, which silently under-counted on any
	display above 1080p.
]]
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

--[[
	The current visual state: the window size from the store/viewport, then the
	pure decision from core/ShellState.
]]
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

	--[[
		Tell the separately-owned panels that the main window changed shape.

		The InfoWindow lives on the SAME ScreenGui but is not a child of the main
		frame, so collapsing the window hid the nav and the content and left the
		info panel sitting on screen -- the reported "minimised and it is still
		showing". Nothing in this file even mentioned InfoWindow before, so no
		amount of reading the minimise code could have revealed it; it is a
		consequence of sharing the screen.

		Wired as a callback rather than a direct reference because the Shell is
		built before the panel exists, and because the Shell must not acquire a
		dependency on a panel it does not own.
	]]
	if self.onVisualState ~= nil then
		pcall(self.onVisualState, state)
	end
end

function Shell.applySize(self)
	-- Uses the same state function as the shape changes, so a width/scale edit
	-- while minimised or in the pill keeps that shape's own layout instead of
	-- falling back to the window size.
	Shell.applyVisualState(self, Shell.visualState(self))
	self.mainScale.Scale = ((self.store:get("uiState.uiScale") or 100) / 100) * Shell.resFactor()

	if self.syncSliders ~= nil then
		self.syncSliders()
	end

	--[[
		A width/height change can push the window past the screen edge, so the
		position is re-clamped here too -- deferred until the new size has been
		laid out, because `AbsolutePosition`/`AbsoluteSize` are only meaningful
		after the property writes above have propagated.

		Deliberately does NOT save afterwards: the stored position may be exactly
		what the user chose, and silently rewriting it because they resized the
		window would lose their placement. Only a DRAG persists (see bindDrag).
	]]
	self:delay(0.05, function()
		if self.destroyed then
			return
		end
		Shell.clampOnScreen(self)
	end)
end

--[[
	Apply `uiState.fontScale` to every text object on the screen.

	The stored value is a MULTIPLIER (0.8 - 1.5). Each text object's original
	TextSize is remembered in an attribute the first time it is touched, so the
	result is always `base * scale` -- scaling the CURRENT size instead would
	compound every time the slider moved (1.5 then 1.5 again -> 2.25x).

	Accessed through pcall because most GUI objects have no TextSize at all.
]]
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

--[[
	Keep the window on screen after a drag, a resize, or a display change.

	Returns true when it actually moved the window (i.e. a tween is in flight),
	so a caller that persists the position can wait for the move to land instead
	of saving an intermediate coordinate.
]]
function Shell.clampOnScreen(self)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local viewport = camera.ViewportSize
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

-------------------------------------------------------------------------- build --

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

	-- Squares off the bottom edge of the bar so the rounded corners do not show
	-- a seam. Hidden while minimised, otherwise it covers the window's own corner.
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

	-- A cover used during shape changes. Without it, resizing the window and
	-- toggling which layer is visible happen in the same tick and read as a hard
	-- cut; with it, every switch happens while the window is hidden.
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

	--[[
		The pill's status dot.

		V1007 had a 7x7 rounded dot next to the live text: green while tasks run,
		amber while paused. The refactor kept the text and dropped the dot, which
		matters because the pill exists to be read at a glance -- colour is what
		makes that possible, and the dot is the only colour in the collapsed form.
		Driven from the same `bindStatus` tick that writes the text.
	]]
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

	Shell.buildNavigation(self)
	Shell.buildPages(self)
	Shell.bindDrag(self, topBar)
	Shell.bindInput(self)
	Shell.bindStore(self)
	Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	Shell.bindHotkeys(self)
	Shell.buildResetButton(self, screen)
	Shell.bindStatus(self)

	Shell.applySize(self)
	if #self.pages > 0 then
		-- Select the first page unconditionally. The minimised state hides the
		-- layers; it does not change which tab is selected. (The original wrote
		-- `minimized == true and nil or pages[1].id`, which always evaluates to
		-- the second alternative -- the guard never did anything.)
		Shell.switchTab(self, self.pages[1].id)
	end

	if self.store:get("uiState.minimized") == true then
		Shell.setMinimized(self, true, true)
	end

	if self.timers ~= nil and #self.uiTicks > 0 then
		self.timers:every(os.clock(), 0.5, function()
			for _, tick in ipairs(self.uiTicks) do
				pcall(tick)
			end
		end)
	end

	return screen
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

--[[
	Stagger the cards of one page in with a short scale pop.

	Extracted because TWO paths need it: switching to a tab, and coming back from
	the pill. V1007 popped the active page's cards on both (`fromPillAnim`'s
	"10-card staggered pop"), and the refactor only wired the tab-switch side --
	so leaving the pill restored the window with a flat, static page.

	A UIScale is used rather than Size so the layout pass is untouched: animating
	AutomaticSize frames' sizes is how cards get permanently misaligned.
]]
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

--------------------------------------------------------------------- behaviour --

--[[
	Drag the window by its top bar.

	The mouse delta is divided by the window's scale, which the shell knows
	because the shell set it.
]]
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
		if input.Position.X >= position.X + size.X - TOP_BUTTON_ZONE then
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

		--[[
			Put the window back on screen BEFORE saving where it is.

			The saved position is what the next session restores, so persisting an
			off-screen one makes the problem permanent: the window returns where it
			cannot be reached, and the controls that would move it are precisely
			the ones that are out of reach. `Shell.clampOnScreen` existed for this
			and had ZERO call sites.

			The save is deferred by the clamp tween's duration because reading
			`main.Position` while it animates would record an intermediate value.
		]]
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

--[[
	Change shape behind a cover.

	`onCovered` runs while the window is invisible, so nothing is ever caught
	half-swapped.

	Every morph takes a new sequence number and each delayed step bails out when a
	newer morph has started. Without that, clicking minimise/restore quickly left
	two overlapping delay chains; whichever finished last decided the final size,
	corner and visibility, and the window visibly flickered through both shapes.
]]
function Shell.morph(self, options)
	self.morphSeq += 1
	local seq = self.morphSeq
	-- Stamped so the watchdog below can tell "a morph is in flight" from
	-- "a morph died and left the cover up".
	self.morphAt = os.clock()

	local cover = self.cover
	if cover ~= nil then
		cover.BackgroundColor3 = self.kit:color("White")
		cover.BackgroundTransparency = 1
		cover.Visible = true
		self.kit:tween(cover, MORPH_COVER_TIME, { BackgroundTransparency = 0 })
	end
	self:delay(MORPH_COVER_TIME, function()
		if self.destroyed or self.morphSeq ~= seq then
			return
		end
		if options.onCovered ~= nil then
			pcall(options.onCovered)
		end
		if options.corner ~= nil then
			self.kit:tween(self.mainCorner, options.move, { CornerRadius = UDim.new(0, options.corner) }, Enum.EasingStyle.Quint)
		end
		local props = {}
		if options.size ~= nil then
			props.Size = options.size
		end
		if options.position ~= nil then
			props.Position = options.position
		end
		self.kit:tween(self.main, options.move, props, Enum.EasingStyle.Quint)
		self:delay(options.move, function()
			if self.destroyed or self.morphSeq ~= seq then
				return
			end
			self.kit:tween(cover, options.fadeOut, { BackgroundTransparency = 1 })
			self:delay(options.fadeOut + 0.03, function()
				-- The cover is only hidden by the morph that still owns it; a
				-- superseded chain must not uncover an in-flight newer one.
				if self.morphSeq ~= seq then
					return
				end
				pcall(function()
					cover.Visible = false
					cover.BackgroundTransparency = 1
				end)
				self.morphAt = 0
				-- The window is fully visible again, so anything that only makes
				-- sense once it is revealed happens here.
				if options.onRevealed ~= nil then
					pcall(options.onRevealed)
				end
			end)
		end)
	end)
end

--[[
	Collapse to the title bar, or restore the window.

	`instant` applies the end state with no morph (used at build, when there is
	nothing to animate from).

	Both directions go through Shell.visualState, which is what makes the restore
	work at all: the previous version had no restore branch -- it always morphed
	to MINIMIZED_HEIGHT and hid the panels, so un-minimising collapsed the window
	again and the minimise button could only ever go one way.
]]
function Shell.setMinimized(self, minimized, instant)
	self.minimized = minimized
	local state = Shell.visualState(self)

	-- Show what the button will DO, like V1007 did. Without this the button read
	-- "—" in both states, so a collapsed window looked like a dead end: nothing
	-- on screen said that pressing it again would bring the window back.
	if self.minimizeButton ~= nil then
		self.minimizeButton.Text = if minimized then "+" else "—"
	end

	if instant then
		Shell.applyVisualState(self, state)
		return
	end

	Shell.morph(self, {
		move = 0.22,
		fadeOut = 0.16,
		size = UDim2.fromOffset(state.layout.width, state.layout.height),
		corner = state.layout.corner,
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
	-- rather than a second copy: a config load or any other writer moves the
	-- window through the same path.
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
		fadeOut = if enabled then 0.14 else 0.18,
		size = UDim2.fromOffset(state.layout.width, state.layout.height),
		corner = state.layout.corner,
		position = position,
		onCovered = function()
			Shell.applyVisualState(self, state)
		end,
		-- Coming back from the pill re-pops the active page, like V1007 did;
		-- going INTO the pill has nothing to pop.
		onRevealed = function()
			if not enabled then
				Shell.replayCards(self, self.activeTab)
			end
		end,
	})
end

function Shell.setTheme(self, name)
	-- `Theme.has`, not a nil check on `Theme.palette`: the palette accessor
	-- falls back instead of returning nil, so the old guard was dead and any
	-- unknown name was accepted.
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
	--[[
		Persist the theme immediately.

		The autosave fires every 8 seconds and would get there eventually, but a
		theme is a visible choice the user just made: if the session ends (crash,
		kick, rejoin) inside that window, the choice is lost. V1007 saved from the
		theme handler for the same reason.
	]]
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

	--[[
		`uiState.savedMain` needs a subscriber, or the settings button that writes
		it ("reset window position") does nothing at all: the store changes, the
		window stays where it is, and the control looks broken.

		Dragging also writes this key, which is why the move is skipped when the
		window is already at the target.
	]]
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

	-- `uiState.fontScale` was written by a settings slider that NOTHING read, so
	-- the slider moved and the interface never changed. Applying it here gives
	-- the control the effect it promises.
	self.kit:track(store:subscribe("uiState.fontScale", function()
		Shell.applyFontScale(self)
	end))

	--[[
		Re-layout when the viewport changes.

		`Shell.windowSize` derives the window size from `Camera.ViewportSize` and
		the width/height percentages, and V1007 re-ran its size application from
		the same place. Nothing here listened for a change, so resizing the Roblox
		window (or going fullscreen) left the panel at the old resolution's
		proportions with stale clamps -- and because the size is stored in
		percentages, the CORRECT size is computable at any moment; only the
		notification was missing.

		Debounced through the runtime's Timers rather than run inline: a window
		drag emits this signal continuously and each pass re-tweens the shell.
	]]
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
				Shell.applySize(self)
				-- A shrink can push the window off the new viewport; a resolution
				-- change that leaves the panel unreachable is the same class of
				-- problem as dragging it there.
				Shell.clampOnScreen(self)
			end)
		end))
	end
end

function Shell.buttons(self)
	return self.minimizeButton, self.pillButton, self.closeButton
end

function Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	local kit = self.kit
	local store = self.store

	-- Kept on the instance: setMinimized flips the button's glyph, and
	-- Shell.buttons used to read fields that were never assigned.
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
			if self.onClose ~= nil then
				task.spawn(self.onClose)
			end
		end)
	end))
end

--[[
	Keyboard shortcuts.

	V1007 had these and the settings page still advertises them, but the refactor
	shipped only the hint string -- pressing RightShift/RightCtrl/RightAlt did
	nothing at all.

	    RightShift  show / hide the window (pill)
	    RightCtrl   pause / resume
	    RightAlt    unfreeze (the "I cannot move" escape hatch)
	    Space       step off a gym machine

	`gameProcessedEvent` is honoured so typing in a TextBox is never treated as a
	shortcut. The whole binding is gated on `cfg.hotkeys`, which is the switch the
	settings page already exposes.
]]
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
			--[[
				Step off the gym machine.

				V1007 bound Space alongside the other three (the machine itself is
				escaped with a Space key event, so pressing it by hand is the
				natural manual override), and the "解除冻结" note on the teleport
				page advertises RightAlt only -- so this was simply absent here.
				Only acts while a machine is actually engaged, or it would swallow
				the jump key.
			]]
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

--[[
	Long-press reset.

	A floating button that restores every UI state value to its default after a
	3-second hold, with the fill as visible progress. V1007 had it and it is the
	only recovery path when the window has been dragged off screen or scaled to
	something unusable -- which is exactly the situation a user cannot fix by
	clicking, because the controls are the thing that is broken.
]]
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

	--[[
		A rotating red->yellow gradient, spun by the hold loop as a progress ring.

		V1007 did exactly this (`resetGrad.Rotation = (Rotation + 8) % 360`) and it
		is the only feedback the button gives while held besides the percentage:
		the fill bar is 4px tall, and the whole point of this control is that it
		must work when the rest of the UI does not.
	]]
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

--[[
	Put every layout value back to its default and re-apply it.

	The recovery path, so it has to be complete: this button exists for the case
	where the window is off-screen or scaled into uselessness, and the INFO panel
	has its own size, scale and saved position -- all of them store keys that a
	partial reset would leave broken. V1007's 3-second hold reset the info window
	too (and called saveConfig immediately, rather than leaving the repaired state
	to the next autosave).

	`onReset` is the hook main.luau uses to re-apply those panel values, because
	the Shell does not own the InfoWindow.
]]
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

	local center = UDim2.new(0.5, 0, 0.5, 0)
	self.main.Position = center
	store:set("uiState.savedMain", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
	self.pillPosition = UDim2.new(0.5, 0, 0.18, 0)

	Shell.applySize(self)
	Shell.applyFontScale(self)
	if self.onReset ~= nil then
		pcall(self.onReset)
	end
	Shell.toast(self, "界面已复位", "success")
end

--[[
	Live read-outs that are not bound to a store key.

	V1007 showed "运行中: 打Boss + 全图杀戮" along the bottom and "力量/秒 ·
	当前任务" on the pill. Both widgets exist in this shell but nothing ever wrote
	to them, so the status line sat on "空闲中" forever and the pill's second line
	was permanently blank -- two features that looked implemented and were not.
]]
function Shell.bindStatus(self)
	local scheduler = self.scheduler
	local metrics = self.services.metrics

	Shell.addUiTick(self, function()
		--[[
			Stuck-cover watchdog.

			The cover is a full-window opaque frame. If a morph chain is
			superseded at the wrong moment, or its delayed step is dropped (a timer
			cancelled by teardown, a `pcall` that swallowed a failure), the cover
			stays up and the entire interface is a white rectangle -- with the
			click-through controls still working underneath, which makes it look
			like a rendering bug rather than a state bug.

			V1007 guarded this from its heartbeat (`:4708-4714`). The check is
			deliberately generous: a legitimate morph finishes in well under a
			second (cover 0.16 + move 0.28 + fade 0.18), so anything still covered
			after 2 s is not a morph.
		]]
		if self.cover ~= nil and self.cover.Visible == true then
			local since = if self.morphAt ~= nil and self.morphAt > 0 then os.clock() - self.morphAt else 999
			if since > 2 then
				self.cover.Visible = false
				self.cover.BackgroundTransparency = 1
				self.morphAt = 0
				warn("[MKUltraHUB][ui] 形态切换遮罩卡住，已强制清除")
			end
		end

		--[[
			Per-task liveness watchdog.

			The scheduler notices a task that THROWS and backs it off. It cannot
			notice one that has silently stopped doing anything -- a latched guard,
			an `enabled()` that started answering false for the wrong reason, a
			`tick` that returns early. From the outside those look exactly like a
			task that is working.

			REPORTED, never restarted: a task that stopped on purpose must not be
			revived behind the guard that stopped it. Naming the task is the whole
			value -- it turns "锻炼没反应" into "任务 train 超过 8 秒没运行".
		]]
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
				-- The first label is the highest-priority running task, matching
				-- the order the scheduler runs them in.
				--
				-- The rate respects "数字格式化显示" just like the info panel does:
				-- the pill is the most-read read-out in the script, so a toggle
				-- that changed only the panel would look broken here.
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

--[[
	A small confirm dialog.

	The holder is the thing that gets destroyed -- it is the full-screen click
	absorber. V1007 returned the inner card from its modal helper and destroyed
	only that, leaving a black overlay permanently covering the screen and eating
	every click.

	`onCancel` is optional and runs for EVERY dismissal that is not `确认` --
	the 取消 button, a click on the backdrop, and the close tween. A caller whose
	action keeps running in the background after the dialog closes (the rejoin
	countdown) must be told, or the dialog is decorative: cancelling it would
	still fire three seconds later.
]]
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
		-- `gameProcessedEvent`, so while a dialog is up it swallows every drag and
		-- click meant for the window underneath. The dialog's own buttons and the
		-- card handle dismissal; this layer is only the dim.
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

--[[
	A dismissible detail card.

	V1007's `Core.showPreview`: a small card anchored to the control that opened
	it, listing whatever the caller wants, closed by clicking anywhere or after a
	timeout. The refactor replaced its one call site (the pet preset "?") with a
	6-second toast, which is a poor substitute for exactly the reason the card
	existed: the content is a LIST ("每只名字 × 数量"), and a list that vanishes
	on a timer cannot be read carefully or copied from.

	Only one card at a time -- opening a second replaces the first, which is what
	`Core._currentPreview` did.
]]
function Shell.preview(self, title, lines, lifetime, anchor)
	local kit = self.kit

	-- Only one at a time.
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
		--[[
			The full-screen dismiss layer must NOT be a live button.

			It was one, and that is why "点了问号之后整个窗口拖不动" happened: a
			Button reports `gameProcessedEvent = true`, so while the preview was up
			every drag of the main window was swallowed by this transparent layer
			instead of reaching the title bar underneath. The window looked frozen
			for as long as the card was shown.

			With `Active = false` it is pure decoration: the card itself still
			closes on click, and the rest of the interface keeps working.
		]]
		Active = false,
	}, self.screen)

	--[[
		Anchored to the control that opened it when one is given, like V1007's
		`Core.showPreview` (which offset the card to the left of and just below
		its trigger). Centring is the fallback, because a card whose anchor has
		scrolled out of view would be better off centred than off-screen.
	]]
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
--[[
	Toast -- the notification stack.

	Every subsystem already calls a `notify(text, kind)` callback; this turns those
	into cards in the corner. It is the only place that decides how a message
	looks, so a subsystem never has to know whether there is a UI at all.

	Two things V1007 got wrong here:

	  * the card animated its height only, so the accent bar and the text appeared
	    instantly while the box grew around them;
	  * the stack could fill the whole screen. There is a cap now, and the oldest
	    card is retired when the stack gets too tall.
]]

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

-- There was a `Toast.setVisible(visible)` here that wrote `uiState.toast`. It was
-- never called, and the key is not in the config schema -- so it was a phantom
-- store entry that could not be validated or persisted. Visibility is already a
-- real key: the settings toggle writes `cfg.toast` and `Toast.show` reads it.

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

--[[
	Show a card.

	`duration` is optional: V1007's `Core.notify(text, dur, kind)` let a caller
	keep an important message up longer, and the refactor's fixed 3-second
	lifetime silently took that away (the callers still pass a duration).
]]
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
		Text = tostring(text),
		TextColor3 = kit:color("TextPrimary"),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTransparency = 1,
		ZIndex = 902,
	}, card)

	-- The card grows, the text fades in with it, and the accent bar drains as a
	-- countdown. Animating all three together is what stops the "box appeared
	-- around some already-visible text" look.
	kit:tween(card, 0.22, { Size = UDim2.new(1, 0, 0, CARD_HEIGHT) }, Enum.EasingStyle.Quint)
	kit:tween(label, 0.24, { TextTransparency = 0 })
	kit:tween(accent, lifetime, { Size = UDim2.new(0, 4, 0, 0) }, Enum.EasingStyle.Linear)

	table.insert(self.live, card)

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
			pcall(function()
				card:Destroy()
			end)
		end)
	end

	self:delay(lifetime, retire)

	-- Cap the stack: over five cards, or taller than 80% of the screen, retire the
	-- oldest rather than letting toasts cover the game.
	while #self.live > MAX_VISIBLE do
		local oldest = table.remove(self.live, 1)
		if oldest ~= nil and oldest.Parent ~= nil then
			pcall(function()
				oldest:Destroy()
			end)
		end
	end

	local camera = workspace.CurrentCamera
	local viewportHeight = if camera ~= nil then camera.ViewportSize.Y else 720
	local stackHeight = #self.live * (CARD_HEIGHT + 5)
	if stackHeight > viewportHeight * MAX_SCREEN_FRACTION then
		local oldest = table.remove(self.live, 1)
		if oldest ~= nil and oldest.Parent ~= nil then
			pcall(function()
				oldest:Destroy()
			end)
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
end

return Toast
end

__modules["core/PanelPlacement"] = function()
-- (module directive --!strict; the bundle is --!nonstrict)
--[[
	PanelPlacement -- where to put a second panel so it does not cover the first.

	Extracted from the info window's placement code in V1007, which computed this
	inline with four candidate positions, a scoring expression and two levels of
	fallback. It is pure geometry, so it is testable -- and it needed to be, because
	the original had a real defect: it decided "does the panel overlap the main
	window" from the SAVED position rather than the live one, and both windows
	carried IgnoreGuiInset = true specifically so their coordinate systems matched.

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
	-- an optional inside the loop is what the type checker objects to, and the
	-- first candidate always wins anyway.
	--
	-- The score keeps the DOCUMENTED preference order rather than "whichever side
	-- is nearest the old position": right and left both avoid the main window, so
	-- without a preference term the panel would flip sides depending on where it
	-- happened to be. The index supplies that order.
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
--[[
	InfoWindow -- the live read-out panel.

	It lives on the SAME ScreenGui as the main window. V1007 gave it its own
	ScreenGui and then had to set IgnoreGuiInset on both so their coordinate
	systems would line up; sharing one screen removes that whole class of
	off-by-inset bugs, and it lets core/PanelPlacement compare the two rectangles
	directly.

	The rows are read-outs, not bound controls: they refresh on a timer, because
	what they show (frame rate, memory, per-second strength) is computed rather
	than stored.
]]

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
local REFRESH_SECONDS = 0.2

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

--[[
	The read-out number formatter.

	`uiState.formatNum` USED TO HAVE NO READER AT ALL: the settings page offered
	"数字格式化显示（1.000K）", flipping it changed the checkbox and nothing else.
	V1007 read the same flag in its `Core.fmt` (see its line 346: `if not
	Core.uiState.formatNum then return tostring(math.floor(n)) end`), so the
	behaviour here is the old one: off means the plain rounded integer, on means
	the abbreviated suffix form.

	Read through the store rather than captured at build, because the toggle is on
	a different page and the panel refreshes on a timer anyway -- so a flip is
	reflected on the next refresh with no subscription to maintain.
]]
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
		-- True while the main window is collapsed or in pill mode. Independent of
		-- `visible`, which is the user's intent (see applyVisibility).
		shellHidden = false,
		lastRefresh = 0,
	}, InfoWindow)
	return self
end

--[[
	The panel's BASE size, in unscaled units; `uiState.infoScale` is applied on
	top of it by the UIScale. A saved size is honoured here, which is what makes
	the drag-to-resize grip below persist across sessions -- V1007 stored this and
	the refactor kept the schema key (`uiState.savedInfoSize`) but never wrote or
	read it, so a resized panel always came back at the default size.
]]
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
		--[[
			Required, or minimising does nothing visible.

			Collapsing tweens the frame's HEIGHT to `MINIMIZED_HEIGHT` (36). Every
			child below that line -- the 服务器 line at y=40, Place ID at y=56, the
			查看：自己 button at y=78, the scrolling read-out -- is still a child of
			this frame and still rendered, because a Frame does NOT clip its
			descendants by default. That is why the user saw "最小化之后服务器信息、
			Place ID、查看自己还在": the window got shorter and everything below it
			just hung outside the new bounds.

			V1007 set this on the equivalent frame.
		]]
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

	--[[
		The player picker list.

		The button used to only CYCLE through the server's players, which V1007 did
		not do -- it opened a list showing every player with their strength and
		rebirths, DisplayName included, and let you pick one. Cycling means you
		cannot see who is available and you must click N times to reach someone.
	]]
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

	-- Drag by the title bar.
	local dragging = false
	local startInput = nil
	local startPosition = nil
	kit:track(bar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.Position.X >= bar.AbsolutePosition.X + bar.AbsoluteSize.X - 80 then
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
		local delta = input.Position - startInput
		frame.Position = UDim2.fromOffset(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y)
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
		local position = frame.Position
		self.store:set("uiState.savedInfo", { xs = 0, xo = position.X.Offset, ys = 0, yo = position.Y.Offset })
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

	--[[
		Drag-to-resize grip (bottom-right corner).

		V1007 had this and the refactor dropped it, leaving "infoScale" as the only
		way to change the panel's size and no control for it at all. The grip
		adjusts the BASE size by the mouse delta divided by the scale, so the panel
		keeps up with the cursor at any `uiState.infoScale`.
	]]
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

	--[[
		Honour a visibility request that arrived BEFORE the frame existed.

		main.luau subscribes to `uiState.infoVisible` and calls `show()` as soon as
		it constructs the panel -- which is before `build()` runs. Every method
		here guards on `self.frame == nil`, so that early `show()` set the flags
		and changed nothing, and the frame was then created with `Visible = false`
		and left that way: the panel only appeared if the user toggled the switch
		a second time.

		Re-applying here makes the build order irrelevant instead of relying on
		main.luau calling things in the right sequence.
	]]
	if self.visible then
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
		InfoWindow.applyVisibility(self)
		InfoWindow.animateIn(self)
	end
	return frame
end

--[[
	Put the panel somewhere that does not cover the main window.

	The decision is core/PanelPlacement; this only gathers the rectangles.
]]
function InfoWindow.place(self)
	local screen = screenSize()
	local main = self.shell.main
	local mainRect = nil
	if main ~= nil and main.Visible and not self.shell.pill then
		local position = main.AbsolutePosition
		local size = main.AbsoluteSize
		mainRect = { x = position.X, y = position.Y, w = size.X, h = size.Y }
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
	return result
end

--[[
	The panel's own visibility, as the user set it.

	Kept separate from `frame.Visible` because the two are different questions
	and conflating them is a bug: `visible` is "the user wants this open", while
	the frame is only visible when the user wants it AND the main window is not
	collapsed. Writing the user's intent over the top of a collapse would reopen
	the panel on top of a minimised window.
]]
function InfoWindow.applyVisibility(self)
	if self.frame == nil then
		return
	end
	local open = self.visible and self.shellHidden ~= true
	self.frame.Visible = open
	if open and self.timers ~= nil then
		InfoWindow.refresh(self)
	end
end

--[[
	Called by the Shell whenever the main window changes shape (minimise, pill).

	Collapsed and pill modes hide the panel; the window mode restores it only if
	the user had it open -- minimise then restore must not conjure a panel the
	user had closed, and must not lose one they had open.
]]
function InfoWindow.setShellHidden(self, hidden)
	hidden = hidden == true
	if self.shellHidden == hidden then
		return
	end
	self.shellHidden = hidden
	InfoWindow.applyVisibility(self)
end

function InfoWindow.show(self)
	self.visible = true
	InfoWindow.applyVisibility(self)
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

--[[
	Entrance / exit motion for the panel.

	Both were instant, sitting next to a main window that morphs over 0.22s and
	page cards that stagger in -- which is why the panel read as pasted on. The
	transform is the panel's UIScale, NOT its Size: Size carries the user's saved
	size and `place()` owns the scale factor, so growing Size here would fight
	both (the same trap that once made the panel come back at factor squared).

	A tween on a property of a hidden object still runs, so the exit animates the
	SAME scale down and only then flips Visible -- and the delayed hide re-checks
	`visible`, so a rapid off/on does not get hidden by an exit that is no longer
	current.
]]
--[[
	Where the panel collapses INTO: the main window's centre.

	The panel shares the ScreenGui with the main window, so "fuse back into the
	main panel" is a real motion here rather than a fade. V1007 did exactly this
	(its close handler animated the frame into the main window); the refactor
	reduced it to an instant visibility flip, which is why the user saw the close
	as "只是缩小了一点" with no merge.
]]
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

--[[
	Entrance / exit motion for the panel.

	Show: grows OUT of the main window's centre with a Back (overshoot) ease.
	Hide: shrinks back INTO that same point, so closing reads as fusing back in.

	The transform is `Size` + `Position` (with the UIScale left alone, because
	`place()` owns its factor). The geometry is handed back to `place()` when the
	motion finishes, so this is purely an effect and the panel always ends up
	exactly where the normal layout code puts it.
]]
function InfoWindow.animateIn(self)
	if self.frame == nil or self.scale == nil then
		return
	end
	local merge = InfoWindow.mergeTarget(self)
	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight

	if merge == nil then
		-- Nothing to grow out of: a plain pop, no geometry games.
		self.scale.Scale = 0.94
		self.kit:tween(self.scale, 0.26, { Scale = 1 }, Enum.EasingStyle.Back)
		return
	end

	local centreX = merge.X
	local centreY = merge.Y
	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.frame.Position = UDim2.fromOffset(centreX, centreY)
	self.frame.Size = UDim2.fromOffset(self.baseWidth * 0.2, height * 0.2)
	self.frame.BackgroundTransparency = 1

	self.kit:tween(self.frame, 0.3, {
		Position = UDim2.fromOffset(centreX - self.baseWidth / 2, centreY - height / 2),
		Size = UDim2.fromOffset(self.baseWidth, height),
		BackgroundTransparency = 0,
	}, Enum.EasingStyle.Back)
	self.kit:delay(0.32, function()
		if self.frame == nil then
			return
		end
		-- Hand geometry back to the layout owner.
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
	local merge = InfoWindow.mergeTarget(self)
	if merge == nil then
		InfoWindow.applyVisibility(self)
		return
	end

	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	-- Anchor at the centre so the shrink converges on the merge point instead of
	-- collapsing toward its own top-left corner.
	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local fromX = self.frame.AbsolutePosition.X + self.frame.AbsoluteSize.X / 2
	local fromY = self.frame.AbsolutePosition.Y + self.frame.AbsoluteSize.Y / 2
	self.frame.Position = UDim2.fromOffset(fromX, fromY)

	self.kit:tween(self.frame, 0.22, {
		Position = UDim2.fromOffset(merge.X, merge.Y),
		Size = UDim2.fromOffset(self.baseWidth * 0.2, height * 0.2),
		BackgroundTransparency = 1,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	self.kit:delay(0.24, function()
		if self.frame == nil then
			return
		end
		self.frame.AnchorPoint = Vector2.new(0, 0)
		InfoWindow.applyVisibility(self)
		-- Restore the real geometry for the next show, which animates from
		-- scratch -- leaving the 20%-size here would make the reopen jump.
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
	end)
end

function InfoWindow.toggle(self)
	if self.visible then
		InfoWindow.hide(self)
	else
		InfoWindow.show(self)
	end
end

--[[
	Collapse / expand the panel.

	`Size` is kept in UNSCALED units and `scale` (a UIScale) is the only thing
	that applies `uiState.infoScale`.

	The previous version pre-multiplied the size here AND reset the scale to 1,
	while `place()` set the scale to `factor` on every show. Minimise once, reopen,
	and both applied: the panel came back at factor squared (250% at a 160%
	setting) and grew a little on every toggle.
]]
function InfoWindow.toggleMinimized(self)
	if self.frame == nil then
		return
	end
	self.minimized = not self.minimized
	local target = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight
	-- Animate the collapse rather than snapping it: the main window morphs over
	-- 0.22s, so an instant jump on the panel beside it looked like a glitch.
	-- `Size` stays in UNSCALED units and `self.scale` is deliberately untouched
	-- (place() owns it), which is what keeps this from compounding on reopen.
	self.kit:tween(self.frame, 0.18, { Size = UDim2.fromOffset(self.baseWidth, target) },
		Enum.EasingStyle.Quint)
end

--[[
	Open / close the player picker and fill it with everyone in the server.

	Replaces a single cycling button. Cycling cannot show who is available, and
	reaching the Nth player takes N clicks -- V1007 shipped the list, and this
	brings it back with the same information (DisplayName, strength, rebirths).
]]
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

--[[
	One read-out row, with the colour chosen from the value.

	Every `setRow` used to carry its condition inline (`if x > 0 then
	kit:color("Green") else ...`). That is fine in isolation, but this function
	became the point where the BUNDLED artifact exceeded Luau's type-inference
	budget: the bundle reported "Code is too complex to typecheck!" here, then
	35 downstream findings, while `gate src` on the same code reported 0 errors.
	Naming the intermediate values gives the checker concrete types to resolve
	instead of nested conditional expressions over `any`-typed service handles,
	which is what the budget was being spent on. The behaviour is identical.
]]
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

	--[[
		Explicitly typed service handles.

		`self.services` is a plain table built in main.luau, so every field is
		`any` and each `metrics:reading()` becomes an unresolved call whose
		result type the checker must guess. Annotating the handles (and the
		values derived from them, below) is what keeps the inference budget from
		being spent here -- see the note on `row` above.
	]]
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
		local ping: number = reading.ping
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
			pingText = tostring(ping) .. " ms"
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

	--[[
		Rebirth rate, its projection, and the multiplier.

		These three rows existed with labels and a "-" placeholder, but nothing
		ever wrote to them -- the tracking behind them was dropped in the refactor.
		V1007 filled all three.
	]]
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
		--[[
			"N 只" is the number of pets actually WORN, not the number whose rep
			bonus could be read.

			`petCount` counts only the equipped pets with a readable boost, so a pet
			whose perks are not published made this row under-report what the player
			is wearing -- e.g. "12%（10 只）" with sixteen pets out. `equippedCount`
			is the honest denominator and the one the label promises.
		]]
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
--[[
	Announce -- the one-off notice shown on load.

	Kept separate from the shell because it is not part of the interface: it is a
	single card that must be dismissed with the button (clicking the backdrop does
	NOT close it, which is deliberate -- the point is that it gets read).

	It can be switched off with cfg.announce, in which case nothing is built.
]]

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
		-- Through the Kit's Timers (which is the runtime's), so this pending
		-- teardown is cancelled by destroy() instead of running against a GUI
		-- that no longer exists.
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
--[[
	The training page.

	Every control that has state declares a `path` into the Store. Nothing here
	keeps a value, mirrors a value, or refreshes a value: the toggle writes
	`train.auto`, the subscription repaints it, and a change made from anywhere
	else (a saved config, another page, a keybind) shows up here on its own.

	V1007's equivalent held a local copy per widget and reconciled the two with a
	one-hertz polling loop.
]]

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
	kit:toggle(basics, { label = "根据帧率自适应", path = "train.adaptive" })
	kit:slider(basics, {
		label = "目标帧率",
		path = "train.adaptiveThresh",
		min = 10,
		max = 120,
		default = 30,
		commitOnly = true,
	})
	kit:input(basics, { label = "自适应上限", path = "train.adaptiveMax", min = 100, max = 50000, default = 5000 })

	kit:section(page, "训练工具")
	local tools = kit:card(page)
	kit:toggle(tools, { label = "自动切换哑铃", path = "train.toolDumbbell" })
	kit:toggle(tools, { label = "自动切换俯卧撑", path = "train.toolPush" })
	kit:toggle(tools, { label = "自动切换倒立", path = "train.toolHand" })
	kit:toggle(tools, { label = "自动切换仰卧起坐", path = "train.toolSit" })
	kit:note(tools, "同时开启多个时按 俯卧撑 → 倒立 → 仰卧起坐 → 哑铃 的顺序尝试")

	kit:section(page, "器械")
	local machines = kit:card(page)

	kit:toggle(machines, {
		label = "启用器械",
		path = "machine.enabled",
		hint = "需要先开启自动或快速锻炼",
	})

	--[[
		"启用器械" refuses to turn on unless training is already on.

		V1007 did this with a notify ("请先开启自动锻炼") and flipped the toggle
		back. Without it, turning the machine on first does nothing visible: the
		mount state machine is gated on training as well (`Machine.tick` passes
		`train.auto or train.fast` into MountState), so the user gets an enabled
		switch, no movement, and nothing explaining why.

		Written as a store subscription rather than an onChange so that EVERY
		writer is covered -- the toggle, a loaded config, a config slot, or a
		future keybind. The subscribe callback runs after the value is stored, so
		the write-back below is what actually keeps the state consistent.
	]]
	kit:track(kit.store:subscribe("machine.enabled", function(_, value)
		if value ~= true then
			return
		end
		if kit.store:get("train.auto") == true or kit.store:get("train.fast") == true then
			return
		end
		shell:toast("请先开启自动锻炼或快速锻炼", "warn")
		kit.store:set("machine.enabled", false)
	end))

	local function gymOptions()
		local seen = { ["全部"] = true }
		local out = { "全部" }
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
	})

	local nameDropdown
	local indexDropdown

	--[[
		Rebuild the machine-name and index lists from a live scan.

		`default` is what the dropdown SHOWS when the store has nothing (or has
		something the scan no longer finds); it is nil unless we are actually
		resetting the selection. Passing a label unconditionally is what made the
		old version look like it worked: it "refreshed" by overwriting whatever
		the user had picked with 全部.
	]]
	local function refreshMachines(resetSelection)
		if nameDropdown == nil or indexDropdown == nil or machineService == nil then
			return
		end

		local known = machineService:names()
		local names = { "全部" }
		for _, name in ipairs(known) do
			table.insert(names, MachinePlan.machineLabel(name))
		end
		local resetName = if resetSelection then "全部" else nil
		nameDropdown.refresh(names, resetName)

		local stored = kit.store:get("machine.nameFilter")
		local count = machineService:count(stored)
		local indexes = { "随机" }
		for position = 1, math.max(1, count) do
			table.insert(indexes, "第" .. position .. "台")
		end
		local resetIndex = if resetSelection then "随机" else nil
		indexDropdown.refresh(indexes, resetIndex)
	end

	local function nameOptions()
		local out = { "全部" }
		if machineService ~= nil then
			for _, name in ipairs(machineService:names()) do
				table.insert(out, MachinePlan.machineLabel(name))
			end
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
				local known = if machineService ~= nil then machineService:names() else {}
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
			-- index list follows the name.
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

	-- Keep the name list current. The seats are streamed in as the player moves,
	-- so a list built once at page build is empty for anyone not standing in a
	-- gym at that moment -- which is why "器械名" had nothing to choose from.
	-- This is what the page note has always claimed ("列表每 2 秒重新扫描一次").
	local timers = shell.timers
	if timers ~= nil then
		timers:every(os.clock(), 2, function()
			refreshMachines(false)
		end)
	else
		kit:delay(2, function()
			refreshMachines(false)
		end)
	end

	kit:note(machines, "多人同器械时会自动换一台空闲的；列表每 2 秒重新扫描一次")
	refreshMachines(true)

	kit:section(page, "锻炼时机")
	local timing = kit:card(page)
	kit:toggle(timing, { label = "杀戮时同时锻炼", path = "train.duringKill" })
	kit:toggle(timing, { label = "打 Boss 时同时锻炼", path = "train.duringBoss" })
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
--[[
	The teleport page.

	The destination list comes from core/Teleports, and the dropdown writes the
	INDEX into the store. The grid at the bottom writes the same key, so the
	dropdown and the grid can never disagree about what is selected -- the earlier
	version kept the current choice in a label AND in a variable AND in the loop
	task's index, and only the label was refreshed.
]]

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

	-- "当前选择：<name>" -- V1007 printed the resolved destination next to the
	-- dropdown, which is what tells you the grid click and the dropdown agree.
	-- It is a read-out, so it follows the store rather than being written by the
	-- two controls that set the same key.
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
			--[[
				Refuse while the auto-MK loop owns the character.

				V1007 warned here ("请先关闭「循环前往肌肉之王」再重试") and returned.
				Without the guard the manual teleport lands, then the auto-MK task
				walks the player back within half a second -- which reads as "the
				button does not work" rather than "two features are fighting".
			]]
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
		hint = "反复把角色送到所选传送点；与自动前往肌肉之王互斥",
	})

	--[[
		Keep the two "keep me somewhere" features mutually exclusive AT THE SWITCH.

		They already exclude each other inside the scheduler (each task's enabled()
		checks the other key), but that makes the losing switch stay ARMED: turning
		auto-MK off later silently starts the loop the user had forgotten about.
		V1007 handled this in the UI -- enabling one cleared the other and warned --
		and that is what these two subscriptions restore.
	]]
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
			-- Selecting and travelling are separate: this only selects, so the
			-- grid cannot teleport the player by accident.
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

	-- Turning 悬停平台 off must also tear down the parts it already spawned.
	-- `Platforms.ensure` only ever ADDS (Motion.apply calls it while the flag is
	-- on) and nothing removes them on the flag going false, so the nine invisible
	-- parts stayed in Workspace until a hold ended. V1007 called
	-- `Core.platforms.remove()` from the toggle's own handler.
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

	--[[
		The two escape hatches V1007 put beside 记录安全点.

		`清空统计` zeroes the pulled/retries/failures counters. `解除冻结` is the
		one that matters: the anti-pull kernel anchors the character, so when
		something goes wrong the player literally cannot move, and this (or the
		RightAlt hotkey, which calls the same thing) is the only way out.
	]]
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
--[[
	The rebirth page.

	"Automatic rebirth" is not a boolean in the store -- it is `rebirth.rate > 0`,
	because the rate is what actually drives it. The switch therefore reads and
	writes through a derived pair instead of owning a second flag that could
	disagree with the rate. V1007 had exactly that duplication, and the target
	counter reaching its goal would silently switch rebirth off while the toggle
	stayed lit.
]]

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

	--[[
		The lock zeroes the frequency, as its hint says.

		V1007 did this from the toggle's own handler. Without it the 自动重生 switch
		(the "rate > 0" view) stays lit while the lock is on, and rebirth silently
		resumes the moment the lock is lifted -- so the control reads "on" while
		nothing happens, and then does something the user did not ask for.

		Written as a store subscription so a loaded config or a config slot takes
		the same path as a click.
	]]
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
--[[
	The combat page.

	The single-target dropdown is the one place a page reads the game directly:
	the candidate list is whoever is in the server right now, which is not state
	the store should hold. The page refreshes it on its own slow tick rather than
	opening a loop.
]]

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
	kit:input(area, {
		label = "搜索范围（格）",
		path = "kill.range",
		min = 20,
		max = 2000,
		default = 400,
		hint = "只影响全图杀戮挑最近的敌人；手选目标不受它限制",
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

	kit:section(page, "单独击杀")
	local single = kit:card(page)
	kit:toggle(single, { label = "启用单独击杀", path = "kill.single" })

	--[[
		The option list, always including the stored selection.

		`refresh(values, current)` PRESERVES the selection by keeping the display
		string -- but only if that string is still one of the values. A saved
		target that has left the server would otherwise be silently dropped from
		the list, the dropdown would fall back to its first entry, and the store
		would still hold the old name: the panel and the state would disagree, and
		the kill task would keep hunting a player who is not there.

		Keeping the name in the list (marked as gone) is what makes the state and
		the display tell the same story.
	]]
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
		--[[
			Selection feedback, which V1007 gave ("单独击杀目标：X" /
			"找不到玩家 X（可能已离开）").

			Without it a name typed into a saved config that no longer resolves
			fails SILENTLY: the kill task looks up the name, finds nobody, and
			reports nothing, so single-target mode appears to be on and idle.
		]]
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

	--[[
		The list refreshes itself, which is what the module header and the page
		note have always claimed ("列表每 2 秒自动刷新").

		V1007 rebuilt this dropdown from a 2-second orchestrator block, so a player
		who joined after the page was built could simply be picked. The refactor
		kept the note and the button but dropped the timer, so the only way to
		reach a late joiner was to know to press 刷新玩家列表.

		The stored selection is passed as `default` so a refresh never moves the
		user's choice.
	]]
	shell:addUiTick(function()
		if targetDropdown == nil then
			return
		end
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

	--[[
		V1007 had this button and the refactor dropped it.

		The whitelist is filled by an EXTERNAL script through two environment
		keys, so when that script is not ready the list stays empty and "不打好友"
		refuses every target. Without a manual refresh (and the 10-second retry in
		Combat) there was no way to recover short of reloading.
	]]
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
			friendLabel.Text = "名单状态：未加载（不会攻击任何人）"
		end
	end)

	kit:note(friends, "需要外部好友列表脚本提供名单；名单未加载时不会攻击任何人")

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

	shell:addUiTick(function()
		if combat == nil then
			return
		end
		local stats = combat:stats()
		-- The reason string is what makes "nothing is happening" answerable.
		label.Text = string.format("目标 %s · 出拳 %d · 选敌结果 %s",
			tostring(stats.locked or "无"), stats.punches, tostring(stats.lastReason))
	end)
end

return Page
end

__modules["ui/Pages/Boss"] = function()
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	The boss page.

	The rarity switches are one bound control each against `boss.select.<Rarity>`,
	and the status line refreshes on the shell's slow tick. Detection is cached for
	half a second inside the service, so reading it here is cheap.
]]

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

Page.build = function(kit, page, shell)
	local services = shell.services or {}
	local boss = services.boss

	kit:section(page, "自动打 Boss")
	local auto = kit:card(page)
	kit:toggle(auto, {
		label = "自动打 Boss",
		path = "boss.auto",
		hint = "优先于全图杀戮；打开时会悬停在 Boss 上方",
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

	shell:addUiTick(function()
		if boss == nil then
			return
		end
		-- The formatting lives in core/BossInfo, so the label and the service
		-- cannot disagree about what "waiting" looks like.
		statusLabel.Text = boss:status()
		statusLabel.TextColor3 = if boss:isAlive() then kit:color("Red") else kit:color("TextMuted")
	end)

	kit:section(page, "要打的品级")
	local rarityCard = kit:card(page)
	for _, rarity in ipairs(RARITIES) do
		kit:toggle(rarityCard, {
			label = rarity.label,
			path = "boss.select." .. rarity.key,
		})
	end
	kit:note(rarityCard, "识别不出品级的 Boss 一律算作要打，避免游戏改名后功能静默失效")

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
--[[
	The pet page.

	The four preset rows all do the same three things -- snapshot what is worn,
	apply a saved preset, clear it -- so they are built from one helper rather
	than copied four times, which is how the original ended up with four nearly
	identical blocks that had drifted apart.
]]

local Shell = require("ui/Shell")

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

			--[[
				The overwrite confirmation.

				V1007 opened a modal here ("预设 [<label>] 已有配置，是否覆盖？",
				320x140) before replacing a non-empty preset. The refactor wrote
				straight over it, so a misclick destroyed a saved preset with no
				warning and no undo -- the preset is pure user data with no other
				copy.

				An empty preset saves immediately: there is nothing to lose, and a
				confirmation for the common first-time case is just friction.
			]]
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

		--[[
			"?" used to report only the number of saved pets, so there was no way
			to see WHAT is in a preset without applying it. V1007 showed the full
			contents in a dismissible card; this uses the restored `Shell.preview`
			rather than a toast, because a list of names is content to read, not a
			notification to glance at.
		]]
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
			-- Anchored to the "?" that opened it, like V1007's preview card.
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

	--[[
		The shop list, keeping the stored choice present.

		Same trap as the single-target dropdown: `refresh(values, current)` keeps
		the selection only while the display string is still in `values`. A saved
		pet that has scrolled out of the shop would vanish from the list while
		`pet.selected` still named it -- so 购买 would look armed and fail.
	]]
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
	kit:toggle(control, { label = "深度防卡顿（隐藏粒子 / 阴影）", path = "perf.antiLag" })
	kit:toggle(control, { label = "显示通知气泡", path = "cfg.toast" })

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
	kit:textInput(rejoin, {
		label = "私服 code",
		path = "rejoin.privId",
		default = "",
		placeholder = "链接或 code",
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

	kit:section(page, "配置存档")
	local slots = kit:card(page)

	if Persist == nil then
		kit:note(slots, "存档功能不可用：当前执行器没有文件读写接口")
	else
		local names = {}
		-- Forward-declared because the refresher is defined before the widget it
		-- drives exists, and it is only ever CALLED after that assignment.
		local slotDropdown

		local function refreshSlots()
			--[[
				Rebuild the labels from disk.

				There is no filesystem watcher, so the read-out would otherwise keep
				showing whatever each slot held when the page was built. The dropdown
				is re-seeded with its CURRENT text (not a reset label) so refreshing
				does not silently move the selection back to slot 1.
			]]
			local selected = slotDropdown.get()
			names = {}
			for index = 1, Persist.SLOT_COUNT do
				local label = Persist.slotLabel(index)
				table.insert(names, string.format("%d. %s", index, label or "（空）"))
			end
			for _, entry in ipairs(names) do
				if entry == selected then
					slotDropdown.refresh(names, selected)
					return
				end
			end
			slotDropdown.refresh(names)
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

		local labelBox = kit:textInput(slots, {
			label = "存档名",
			placeholder = "例如：锻炼配置",
			default = "",
		})

		local function currentSlot()
			local display = slotDropdown.get() or "1."
			return tonumber(string.match(display, "^%d+")) or 1
		end

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

		kit:dualButtons(
			slots,
			{ label = "保存到该存档位", role = "Green", onClick = saveCurrent },
			{ label = "读取该存档位", onClick = loadCurrent }
		)

		kit:note(slots, "共 8 个存档位，可随时切换；读取后当前设置会被覆盖")
		refreshSlots()
	end
end

return Page
end

__modules["ui/Pages/Theme"] = function()
	local require = __require
-- (module directive --!nonstrict; the bundle is --!nonstrict)
--[[
	The theme page.

	Clicking a theme writes `uiState.theme` and nothing else. The shell subscribes
	to that key, so the repaint happens there -- which is also why the selected
	marker here is driven by a binding rather than by the click handler.
]]

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
			-- One line: the shell reacts to the store, not to this click.
			kit.store:set("uiState.theme", choice.key)
		end))
	end

	--[[
		The selected marker follows the store, so it is correct on load and after
		a change made anywhere else. The initial paint snaps: animating it would
		make the page visibly "select" its theme as it opens.

		EVERY button is re-rendered on every change, from one function. The
		previous version drove the same state from the binding AND left
		`Kit.animate`'s hover tween free to overwrite `BackgroundColor3`; a button
		the pointer had already visited kept whatever colour the hover path last
		wrote, so the page showed several "selected" buttons at once until
		something forced a full repaint. Re-asserting the resting colour here (and
		refreshing the attribute `Kit.animate` reads on mouse-leave) is what makes
		the marker exactly one button, always.
	]]
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
	kit:bind("uiState.theme", "light", function(name, initial)
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
	end)
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
	version = "V1008-dev",
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

Main.AUTOSAVE_SECONDS = 8
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
			if toastRef ~= nil then
				local ok, err = pcall(Toast.show, toastRef, text, kind, duration)
				if not ok then
					warn("[MKUltraHUB][ui] toast failed: " .. tostring(err))
				end
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
			local ok, err = pcall(function()
				Main.stop()
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
	local rebirth = nil
	local teleportRef = nil

	-- Sampling and rejoining do not need a character: the rejoin triggers and the
	-- info window both read the metrics, so they start first.
	local sessionStart = os.clock()
	local metrics = GameMetrics.install({ scheduler = runtime.scheduler })

	local perf = Perf.install({ store = store, scheduler = runtime.scheduler })

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
		runtime.timers:every(os.clock(), 2, function()
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
			-- Never fight an in-flight teleport: `Teleport:walk` cancels its own
			-- predecessor, so a rescue dispatched here would silently replace the
			-- walk the user (or a subsystem) just started.
			if teleport:isBusy() then
				return
			end
			local safe = motion:safePosition()
			if safe == nil then
				return
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
			-- A late-bound getter: Size is installed AFTER Boss, so capturing the
			-- service here would capture nil. The closure reads the upvalue at
			-- call time, which is only ever during Boss.leave.
			size = function()
				return size
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
			net = net,
			arbiter = arbiter,
			pets = pets,
			isBossAlive = bossAlive,
			notify = notify("combat"),
		})

		machine = Machine.install({
			store = store,
			net = net,
			scheduler = runtime.scheduler,
			timers = runtime.timers,
			character = character,
			isCombatBusy = function()
				return Combat.isBusy(combat)
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
			isBossAlive = bossAlive,
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
		-- Required by train.adaptive: without it the tick fell back to a
		-- hard-coded 60 and every adaptive setting was inert.
		metrics = metrics,
		isCombatBusy = function()
			return combat ~= nil and Combat.isBusy(combat)
		end,
		isBossAlive = function()
			return boss ~= nil and Boss.isAlive(boss)
		end,
		isMachineBusy = function()
			if machine == nil then
				return false
			end
			local phase = machine:stats().phase
			return phase == "mounting" or phase == "mounted"
		end,
		notify = notify("train"),
	})

	-- The autosave is a timer, not a task: cancellable, counted, and it dies with
	-- the runtime instead of outliving the script. The tracker makes it skip the
	-- encode and the disk write when nothing persistable has changed, so an idle
	-- session is not rewriting an identical file every 8 seconds.
	local saveTracker = Persist.tracker(store)
	runtime.timers:every(os.clock(), Main.AUTOSAVE_SECONDS, function()
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
		-- to tell it when the main window collapses. The panel is built further
		-- down (it needs the shell first), so the link is a callback that stays
		-- nil until then and is skipped harmlessly before that.
		shell.onVisualState = function(state)
			if infoWindow == nil then
				return
			end
			-- Collapsed and pill both mean "the main window is not a window right
			-- now", and the panel must not float over a bar that is 36px tall.
			local hidden = state.mode == "minimized" or state.mode == "pill"
			InfoWindow.setShellHidden(infoWindow, hidden)
		end

		-- The reset button is the recovery path, so it has to repair the info
		-- panel too: its scale, its saved position and its saved size are store
		-- keys the Shell writes but does not own.
		shell.onReset = function()
			if infoWindow == nil then
				return
			end
			InfoWindow.loadBaseSize(infoWindow)
			InfoWindow.applyBaseSize(infoWindow)
			InfoWindow.place(infoWindow)
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
		InfoWindow.setShellHidden(infoWindow, state.mode == "minimized" or state.mode == "pill")

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
				pcall(function()
					machine.mount:reset()
				end)
				machine.target = nil
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
