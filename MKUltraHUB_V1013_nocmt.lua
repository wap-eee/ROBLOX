
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

local Format = {}

local SUFFIXES: { string } = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

local NAN = 0 / 0

local function sign(negative: boolean): string
	return if negative then "-" else ""
end

local function roundTo(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

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

	if shown == 0 then
		negative = false
	end
	return sign(negative) .. string.format("%." .. tostring(decimals) .. "f", shown) .. SUFFIXES[tier]
end

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

local function isArray(value: any): boolean
	return type(value) == "table" and rawget(value, 1) ~= nil
end

function Store.flatten(nested: { [string]: any }, isLeaf: LeafPredicate?): { [string]: any }
	local out: { [string]: any } = {}

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

local function covers(subPath: string, changedPath: string): boolean
	if subPath == "" then
		return true
	end
	if subPath == changedPath then
		return true
	end
	return string.sub(changedPath, 1, #subPath + 1) == subPath .. "."
end

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

local Format = require("core/Format")

local BossInfo = {}

export type Info = {
	alive: boolean,
	id: string,
	rarity: string,
	hp: number,
	maxHp: number,
	position: any?,

	group: string?,

	eventKey: string?,
}

local FIXED: { { id: string, rarity: string } } = {
	{ id = "Boss1", rarity = "Common" },
	{ id = "Boss2", rarity = "Rare" },
	{ id = "Boss3", rarity = "Epic" },
	{ id = "Boss4", rarity = "Legendary" },
	{ id = "Boss5", rarity = "Mythic" },
	{ id = "BossRainbow", rarity = "Rainbow" },
}

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

BossInfo.NORMAL_GROUP = "normal"
BossInfo.EVENT_GROUP = "event"

export type EventBoss = {
	key: string,
	label: string,

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

BossInfo.EVENT_ID = "BossId"

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

function BossInfo.selected(rarity: string?, selection: { [string]: boolean }?): boolean
	if rarity == nil or rarity == BossInfo.UNKNOWN then
		return true
	end
	if selection == nil then
		return true
	end
	return selection[rarity] ~= false
end

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

local Store = require("core/Store")

local BossInfo = require("core/BossInfo")

local Config = {}

Config.VERSION = 1013

export type Spec = {
	path: string,
	kind: string,
	default: any,
	min: number?,
	max: number?,
	values: { string }?,

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

local BOSS_PRIORITY = { "event", "normal" }

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

local function map(path: string): Spec
	return { path = path, kind = "map", default = {} }
end

local function live(path: string, default: boolean): Spec
	return { path = path, kind = "boolean", default = default, persist = false }
end

local function liveNum(path: string, default: number): Spec
	return { path = path, kind = "number", default = default, persist = false }
end

local function liveStr(path: string, default: string): Spec
	return { path = path, kind = "string", default = default, persist = false }
end

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

	bool("train.auto", false),
	bool("train.fast", false),
	num("train.rate", 20, 1, 2000),
	bool("train.duringKill", true),
	bool("train.duringBoss", true),
	bool("train.toolDumbbell", false),
	bool("train.toolPush", false),
	bool("train.toolHand", false),
	bool("train.toolSit", false),

	liveNum("train.effRate", 0),
	liveStr("train.rateSource", ""),

	liveStr("train.dualTool", "punch"),

	liveNum("train.depth", 0),
	liveStr("train.depthLabel", ""),
	liveStr("train.depthReason", ""),

	num("rebirth.target", 0, 0, 1000000),
	num("rebirth.rate", 0, 0, 300),
	bool("rebirth.lock", false),
	bool("rebirth.duringBoss", true),
	bool("rebirth.duringKill", true),

	bool("pet.autoBuy", false),
	str("pet.selected", ""),
	bool("pet.autoWheel", false),
	bool("pet.autoEgg", false),
	num("pet.eggBatch", 10, 1, 500),
	bool("pet.autoPack", false),

	bool("crystal.auto", false),
	str("crystal.selected", ""),
	num("crystal.rate", 2, 1, 20),
	bool("crystal.autoSell", false),

	map("crystal.sellByCrystal"),

	preset("crystal.sellPets"),

	bool("tp.autoMK", false),
	bool("tp.loop", false),
	num("tp.loopIdx", 1, 1, 100),

	bool("kill.enabled", false),
	bool("kill.friendWL", false),

	str("kill.friendNames", ""),
	bool("kill.autoKing", false),
	bool("kill.dualEnabled", true),
	bool("kill.single", false),
	str("kill.singleName", ""),
	bool("kill.approach", true),

	liveNum("kill.range", 400),

	bool("kill.powerCheck", true),
	num("kill.powerMaxHits", 30, 0, 500),

	num("kill.targetTimeout", 10, 2, 120),
	num("kill.targetSkip", 60, 0, 3600),

	bool("kill.skipSafeZones", true),

	num("kill.dualInterval", 0.15, 0.1, 3),

	num("kill.hoverHeight", 12, 1, 200),

	bool("kill.directPin", true),
	bool("kill.lookDown", true),
	bool("kill.targetSizeEnabled", false),
	num("kill.targetSizeMul", 5, 1, 20),

	bool("boss.auto", false),
	bool("boss.sizeEnabled", false),
	num("boss.sizeMul", 5, 1, 20),

	liveNum("boss.hoverHeight", BossInfo.NORMAL_HOVER),

	bool("boss.autoChest", true),
	num("boss.chestDelay", 3, 0, 30),

	enm("boss.priority", "event", BOSS_PRIORITY),

	bool("boss.directPin", true),
	bool("boss.event.enabled", true),

	liveNum("boss.eventHoverHeight", BossInfo.EVENT_HOVER),

	enm("boss.event.hopMode", "sparse", HOP_MODES),
	num("boss.event.hopDelay", 5, 0, 120),

	bool("size.selfEnabled", false),
	num("size.selfMul", 3, 1, 20),

	bool("perf.antiLag", false),
	bool("perf.disabled", false),
	bool("perf.removeEffects", true),
	bool("perf.removeTextures", true),
	bool("perf.cull", true),

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

	str("rejoin.targetPlayer", ""),

	str("meta.slotLabel", ""),

	bool("machine.enabled", false),
	str("machine.gymFilter", ""),
	str("machine.nameFilter", ""),
	num("machine.indexFilter", 0, 0, 500),

	bool("machine.overridesCombat", false),

	num("antiAfk.interval", 300, 60, 1140),

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

	bool("cfg.trainThrottle", false),

	num("cfg.saveSeconds", 10, 3, 300),

	bool("cfg.saveEnabled", true),

	num("uiState.widthPct", 45, 30, 100),
	num("uiState.heightPct", 52, 30, 100),
	num("uiState.uiScale", 100, 50, 125),
	num("uiState.infoScale", 100, 50, 250),
	num("uiState.fontScale", 1, 0.8, 1.5),
	bool("uiState.formatNum", true),
	bool("uiState.infoVisible", false),

	bool("uiState.infoHideWithShell", false),
	enm("uiState.theme", "light", THEMES),
	bool("uiState.minimized", false),

	liveNum("uiState.themeEpoch", 0),

	live("uiState.pill", false),
	pos("uiState.savedMain"),
	pos("uiState.savedPill"),
	pos("uiState.savedInfo"),
	pos("uiState.savedInfoSize"),

	bool("petPreset.autoSwitch", false),
	preset("petPreset.train"),
	preset("petPreset.rebirth"),
	preset("petPreset.kill"),
	preset("petPreset.boss"),

	live("runtime.paused", false),
}

for _, rarity in ipairs(RARITIES) do
	table.insert(SCHEMA, bool("boss.select." .. rarity, true))
end

for _, entry in ipairs(BossInfo.events()) do
	table.insert(SCHEMA, bool("boss.event." .. entry.key, true))
end

Config.SCHEMA = SCHEMA

local PERSISTABLE: { [string]: boolean } = {}
for _, spec in ipairs(SCHEMA) do
	if spec.persist ~= false then
		PERSISTABLE[spec.path] = true
	end
end

function Config.isPersisted(path: string): boolean
	return PERSISTABLE[path] == true
end

function Config.canSave(values: { [string]: any }?): boolean
	if type(values) ~= "table" then
		return true
	end
	return values["cfg.saveEnabled"] ~= false
end

local LEAF_KINDS: { [string]: boolean } = { position = true, preset = true, map = true }

local MIGRATIONS: Steps = {

	[1007] = function(_data: { [string]: any }) end,

	[1008] = function(data: { [string]: any })
		local old = data["crystal.sellPets"]
		if type(old) ~= "table" then
			return
		end
		local crystal = data["crystal.selected"]
		if type(crystal) ~= "string" or crystal == "" then

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

	[1012] = function(data: { [string]: any })
		if data["boss.auto"] == true then
			data["boss.autoChest"] = true
		end
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

function Config.defaults(): { [string]: any }
	local out: { [string]: any } = {}
	for _, spec in ipairs(SCHEMA) do
		out[spec.path] = defaultFor(spec)
	end
	return out
end

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

function Timers.step(self: Timers, now: number): (number, number)
	local due: { Entry } = {}
	for _, entry in ipairs(self._entries) do
		if entry.alive and entry.due <= now then
			table.insert(due, entry)
		end
	end

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

	lastRun: number,

	activeSince: number,

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

function Scheduler.step(self: Scheduler, dt: number, now: number): number
	sortEntries(self)
	local ran = 0

	self._frames += 1

	local entries = table.clone(self._entries)
	for _, entry in ipairs(entries) do
		if entry.removed then
			continue
		end

		local current = entry.task

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

function Scheduler.stalled(self: Scheduler, now: number, staleSeconds: number?): { string }
	local limit = staleSeconds or DEFAULT_STALE_SECONDS
	local out: { string } = {}
	for _, entry in ipairs(self._entries) do

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

function Net.enqueue(self: Dispatcher, name: string, ...: any): boolean
	local channel = self._channels[name]
	if channel == nil then
		report(self, name, "unknown channel")
		return false
	end
	return queueOrDrop(self, channel, table.pack(...))
end

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

function TrainRate.refund(state: State, count: number, ceiling: number?): ()
	if count <= 0 then
		return
	end
	state.tokens = math.min(ceiling or TrainRate.CEILING, state.tokens + count)
end

return TrainRate
end

__modules["core/Hold"] = function()

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

function Hold.shouldHold(self: Hold, now: number): boolean
	if not self._active then
		return false
	end
	if self._persistent then
		return true
	end
	return now <= self._verifyUntil
end

Hold.SAMPLE_EPSILON = 1e-9

function Hold.sampleDue(self: Hold, now: number): boolean
	if not self._active or self._exhausted then
		return false
	end
	if now > self._verifyUntil then
		return false
	end
	return now - self._lastSample >= self._sampleInterval - Hold.SAMPLE_EPSILON
end

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

local Targeting = {}

export type Vec3 = { x: number, y: number, z: number }

export type Candidate = {
	id: string,
	position: Vec3,
	alive: boolean,
	friend: boolean,
	self: boolean,

	protected: boolean?,

	winnable: boolean?,

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

function ChestTimer.configure(self: ChestTimer, options: Options)
	local opts: Options = options or {}
	self._delay = opts.delay or self._delay
	self._window = opts.window or self._window
end

function ChestTimer.killedAt(self: ChestTimer): number?
	return self._killedAt
end

function ChestTimer.observe(self: ChestTimer, alive: boolean, now: number): Status
	if alive then
		self._wasAlive = true
		self._killedAt = nil
		return "blocked"
	end

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

local SizePolicy = {}

export type Inputs = {
	bossAlive: boolean,
	bossSizeEnabled: boolean,
	bossSizeMul: number,
	selfSizeEnabled: boolean,
	selfSizeMul: number,
}

function SizePolicy.wanted(inputs: Inputs): number?
	if inputs.bossAlive and inputs.bossSizeEnabled then
		return inputs.bossSizeMul
	end
	if inputs.selfSizeEnabled then
		return inputs.selfSizeMul
	end
	return nil
end

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

		unequipFirst = entries > 0,
		actions = actions,
		missing = missing,
		total = #actions,

		unusable = entries > 0 and #actions == 0,
	}
end

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

local GYMS: { { name: string, x: number, y: number, z: number } } = {
	{ name = "冰霜健身房", x = -2623.41, y = 6.99, z = -409.34 },
	{ name = "神话健身房", x = 2250.39, y = 6.99, z = 1072.77 },
	{ name = "永恒健身房", x = -6758.39, y = 6.99, z = -1284.45 },
	{ name = "传奇健身房", x = 4603.40, y = 990.99, z = -3897.44 },
	{ name = "肌肉之王健身房", x = -8625.40, y = 16.99, z = -5730.41 },
	{ name = "丛林健身房", x = -8685.01, y = 5.99, z = 2392.06 },
	{ name = "工业健身房", x = -5496.68, y = 59.04, z = 4927.74 },
	{ name = "超载健身房", x = -3045.30, y = 165.41, z = 4990.69 },

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

local MACHINE_LABELS: { [string]: string } = {
	["Squat Rack"] = "深蹲架",
	["Bench Press"] = "卧推台",
	["Deadlift"] = "硬拉台",
	["Pullups"] = "引体向上",
	["Boulder Throw"] = "巨石投掷",
	["Treadmill"] = "跑步机",

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

	{ en = "Hallowed", cn = "万圣节" },
}

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

function MachinePlan.machineLabel(name: string?): string
	if name == nil or name == "" then
		return ""
	end
	local exact = MACHINE_LABELS[name]
	if exact ~= nil then
		return exact
	end

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

	if not input.training or not input.hasCharacter then
		return { phase = self.phase, action = "none", timedOut = false }
	end

	if input.seated and input.targetValid then
		self.phase = MountState.MOUNTED
		self.mountStart = 0
		return { phase = MountState.MOUNTED, action = "none", timedOut = false }
	end

	if self.phase == MountState.MOUNTED then
		self.phase = MountState.IDLE
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = false }
	end

	if self.phase == MountState.MOUNTING and now - self.mountStart > self._timeout then
		self.phase = MountState.IDLE
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = true }
	end

	if not input.targetValid then
		self.phase = MountState.IDLE
		self.holdStart = 0
		self.mountStart = 0
		return { phase = MountState.IDLE, action = "none", timedOut = false }
	end

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

RebirthState.EPSILON = 1e-9

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

function RebirthState.cooldown(self: RebirthState): number
	return self._cooldown
end

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

			self.phase = PackState.PHASE_EQUIPPING
			self.equipAt = now
			return step(self, PackState.PHASE_EQUIPPING, "equip", false, false, expired)
		end
		return step(self, PackState.PHASE_TRAINING, "train", false, false, false)
	end

	if self.phase == PackState.PHASE_EQUIPPING then
		local waited = now - self.equipAt >= self._equipDelay - PackState.EPSILON

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

local function sustained(self: Evaluator, key: string, breached: boolean, now: number, sustain: number): boolean
	if not breached then
		self._since[key] = nil
		return false
	end

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

			return a.id < b.id
		end
		if descending then
			return a.playing > b.playing
		end
		return a.playing < b.playing
	end)
	return sorted
end

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

		append(currentJobId)
		for _, server in ipairs(sortByPlayers(servers, true)) do
			append(server.id)
		end
	end

	return { mode = resolved, code = nil, ids = ordered }
end

export type Attempt = {
	kind: string,
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

		if code == nil or code == "" then
			return
		end
		table.insert(attempts, { kind = "private", id = nil, code = code, label = label })
	end

	if resolved == "player" then

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

	self._fps = self._startFps
	table.clear(self._ping)
	table.clear(self._worst)
	self._pingValue = 0
	self._pingWorst = 0

	self._pingEstimated = false
end

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

function Metrics.setPingEstimated(self: Metrics, estimated: boolean)
	self._pingEstimated = estimated == true
end

function Metrics.ping(self: Metrics): number
	return self._pingValue
end

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

function Palette.key(rgb: RGB): string
	return string.format("%d_%d_%d", clampByte(rgb.r), clampByte(rgb.g), clampByte(rgb.b))
end

function Palette.same(a: RGB, b: RGB): boolean
	return Palette.key(a) == Palette.key(b)
end

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

function Palette.exact(remap: Remap, rgb: RGB): RGB?
	return remap.exact[Palette.key(rgb)]
end

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

local Arbiter = {}

Arbiter.Depth = {
	IDLE = 0,
	BODY = 1,
	FREE_WEIGHT = 2,
	MACHINE = 3,
}

Arbiter.LABELS = {
	[0] = "空闲",
	[1] = "徒手",
	[2] = "哑铃",
	[3] = "器械",
}

Arbiter.REQUIREMENTS = { "damage", "standing", "seat" }

Arbiter.MATRIX = {
	damage = { blocks = Arbiter.Depth.BODY, reason = "需要造成伤害：器械会阻断出拳" },
	standing = { blocks = Arbiter.Depth.MACHINE, reason = "需要保持站姿" },
	seat = { blocks = Arbiter.Depth.MACHINE, reason = "需要占用座位" },
}

local REQUIREMENT_ORDER = { "damage", "seat", "standing" }

local function countsOf(active: { [string]: number }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for flag in pairs(active) do
		out[flag] = true
	end
	return out
end

function Arbiter.blockersOf(active: { [string]: boolean }): { string }
	local out: { string } = {}
	for _, name in ipairs(REQUIREMENT_ORDER) do
		if Arbiter.MATRIX[name] ~= nil and active[name] == true then
			table.insert(out, name)
		end
	end
	return out
end

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

function InstanceMT.preempt(self: Instance, depth: number)
	local limit = Arbiter.capOf(countsOf(self.owner.active))
	local clamped = if depth > limit then limit else depth
	self.pinned = clamped
end

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

function Arbiter.state(self: Arbiter): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for flag in pairs(self.active) do
		out[flag] = true
	end
	return out
end

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

local Signal = require("core/Signal")

local Character = {}
Character.__index = Character

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

function Character._track(self, connection, owner)
	table.insert(self._connections, { connection = connection, owner = owner })
	return connection
end

function Character._clearModel(self)
	local character = self.character
	if character ~= nil then
		for i = #self._connections, 1, -1 do
			local record = self._connections[i]

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

function Character.requireRoot(self): any?
	local root = self._root
	if root ~= nil and root.Parent ~= nil then
		return root
	end
	self:_resolve(self)
	return self._root
end

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

function Remotes.crystal()
	return exactOrKeyword("openCrystalRemote", "opencrystalremote", 5)
end

function Remotes.areaTravel()
	return exactOrKeyword("areaTravelRemote", "areatravelremote", 5)
end

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

local HttpService = game:GetService("HttpService")

local Config = require("core/Config")
local Store = require("core/Store")

local Persist = {}

Persist.FILE = "mk_v1008.json"
Persist.FALLBACKS = { "mk_v1007.json", "mk_v1006.json" }

Persist.SLOT_COUNT = 8
Persist.SLOT_PREFIX = "mk_v1008.slot."
Persist.SLOT_SUFFIX = ".json"

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

function Persist.tracker(store)
	local tracker = { dirty = true }
	tracker.connection = store:subscribeAll(function(path)
		if Config.isPersisted(path) then
			tracker.dirty = true
		end
	end)
	return tracker
end

function Persist.save(store, tracker)
	if not Persist.canWrite(store) then

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

	if tracker ~= nil then
		tracker.dirty = false
	end
	return true
end

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

export type Names = {

	BASE_COLOR: string,

	ORDER: string,

	CARD: string,

	PET: string,

	ORIGINAL_SIZE: string,

	OFFSET: string,

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

local Hold = require("core/Hold")
local Attributes = require("core/Attributes")
local Platforms = require("game/Platforms")

local GOOD_AFTER = 1.5

local GOOD_TOLERANCE = 2

local DRIFT_LIMIT = 8
local DRIFT_NOTICE_INTERVAL = 12

local ROTATE_INTERVAL = 0.1

local Motion = {}
Motion.__index = Motion

export type Options = {
	character: any,
	store: any,
	onLost: ((attempt: number) -> ())?,
	onGiveUp: ((attempt: number) -> ())?,

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

		owner = nil,
		refusedBy = nil,
		refusals = 0,
		hold = Hold.new(),
		pos = nil,
		get = nil,
		look = nil,

		lookBias = nil,
		mode = "hover",

		heading = nil,
		headingAt = 0,
		anchored = false,
		frozen = false,
		saved = nil,

		baselineWalk = nil,
		baselineJump = nil,
		safe = nil,

		goodPos = nil,
		goodSince = 0,

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

function Motion.learnSpeed(self)
	if self.hold:isActive() or self.frozen then
		return
	end
	local humanoid = self.character:humanoid()
	if humanoid == nil then
		return
	end
	local okWalk, walk = pcall(function()
		return humanoid.WalkSpeed
	end)

	if okWalk and typeof(walk) == "number" and walk > 0 then
		self.baselineWalk = walk
	end
	local okJump, jump = pcall(function()
		return humanoid.JumpPower
	end)
	if okJump and typeof(jump) == "number" and jump > 0 then
		self.baselineJump = jump
	end
end

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

function Motion.ownerOf(self): string?
	return self.owner
end

function Motion.refused(self): string?
	return self.refusedBy
end

function Motion.mode(self): string
	return self.mode
end

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

function Motion.setLook(self, look, bias)
	self.look = look
	if bias ~= nil then
		self.lookBias = if typeof(bias) == "Vector3" then bias else nil
	end
end

function Motion.begin(self, options): boolean
	local opts = options or {}
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	if humanoid == nil or root == nil then
		return false
	end

	local job = if type(opts.job) == "string" then opts.job else (opts.mode or "hover")
	local allowed = Motion.claim(self, job)
	if not allowed then
		return false
	end

	self.job = job

	local antiPull = self.store:get("cfg.antiPull") or "normal"
	local mode = opts.mode or "hover"

	self.pos = opts.pos
	self.get = opts.get
	self.look = opts.look
	self.lookBias = opts.lookBias

	self.heading = nil
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

		local walk = humanoid.WalkSpeed
		local jump = humanoid.JumpPower
		self.saved = {
			walk = if typeof(walk) == "number" and walk > 0 then walk else self.baselineWalk,
			jump = if typeof(jump) == "number" and jump > 0 then jump else self.baselineJump,
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

		pcall(function()
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			if humanoid.WalkSpeed == 0 and self.baselineWalk ~= nil then
				humanoid.WalkSpeed = self.baselineWalk
			end
			if humanoid.JumpPower == 0 and self.baselineJump ~= nil then
				humanoid.JumpPower = self.baselineJump
			end
		end)
	end

	if self.store:get("cfg.platform") == true then
		Platforms.ensure(self.pos)
	end

	Motion.apply(self, os.clock())
	return true
end

function Motion.apply(self, now: number): boolean
	if not self.hold:isActive() then
		return false
	end

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

	if self.heading == nil or now - (self.headingAt or 0) >= ROTATE_INTERVAL then
		self.heading = cf - cf.Position
		self.headingAt = now
	end
	if self.heading ~= nil then
		cf = CFrame.new(target) * self.heading
	end

	if self.anchored and not root.Anchored then
		pcall(function()
			root.Anchored = true
		end)
	end

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

		local okInside, inside = pcall(function()
			return root:IsDescendantOf(entry)
		end)
		if not okInside or not inside then
			pcall(function()
				entry:PivotTo(cf)
			end)
		end
	elseif Motion.drift(self) > 4 then
		Motion.resync(self)
	end

	self.lastApply = now
	self.applies += 1
	return true
end

function Motion.watchDrift(self, now: number): boolean
	if self.hold:isActive() then

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

function Motion.tick(self, now: number)
	if not self.hold:isActive() then

		Motion.learnSpeed(self)
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

	local offset = (position - self.pos).Magnitude
	if offset <= GOOD_TOLERANCE then
		if self.goodSince == 0 then
			self.goodSince = now
		elseif self.goodPos == nil and now - self.goodSince >= GOOD_AFTER then
			self.goodPos = self.pos
		end
	else

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

function Motion.finish(self)
	if not self.hold:isActive() then
		return
	end
	self.hold:finish()
	self.get = nil

	self.owner = nil
	self.refusedBy = nil

	self.pos = nil
	self.job = nil
	self.look = nil
	self.lookBias = nil
	self.heading = nil
	Platforms.remove()

	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false

	self.goodSince = 0
end

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

			local walk = if saved ~= nil then saved.walk else self.baselineWalk
			local jump = if saved ~= nil then saved.jump else self.baselineJump
			if typeof(walk) ~= "number" or walk <= 0 then
				walk = self.baselineWalk
			end
			if typeof(jump) ~= "number" or jump <= 0 then
				jump = self.baselineJump
			end
			humanoid.PlatformStand = false
			humanoid.Sit = false
			humanoid.AutoRotate = true

			if typeof(walk) == "number" and walk > 0 then
				humanoid.WalkSpeed = walk
			elseif self.frozen then
				humanoid.WalkSpeed = 16
			end
			if typeof(jump) == "number" and jump > 0 then
				humanoid.JumpPower = jump
			elseif self.frozen then
				humanoid.JumpPower = 50
			end

			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

function Motion.unfreeze(self)
	self.hold:finish()
	self.get = nil
	self.look = nil
	self.lookBias = nil

	self.pos = nil
	self.job = nil
	self.owner = nil
	self.refusedBy = nil
	self.heading = nil
	self.goodSince = 0
	Platforms.remove()
	Motion.release(self)
	self.saved = nil
	self.frozen = false
	self.anchored = false
end

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

function Teleports.indexOf(name: string?): number
	for index, entry in ipairs(LIST) do
		if entry.name == name then
			return index
		end
	end
	return 1
end

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

	path: boolean?,
	get: (() -> any)?,
	hold: boolean?,

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

	local okCurrent, current = pcall(function()
		return root.CFrame
	end)
	local rotation = if okCurrent and typeof(current) == "CFrame" then current - current.Position else CFrame.new()
	local cf = CFrame.new(point.x, point.y, point.z) * rotation

	local inside = false
	if entry ~= nil then
		local okInside, value = pcall(function()
			return root:IsDescendantOf(entry)
		end)
		inside = okInside and value == true
	end
	if entry ~= nil and entry.PrimaryPart ~= nil and not inside then
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

function Teleport.walk(self, target, options): boolean
	local opts: Options = options or {}
	if typeof(target) ~= "Vector3" then
		return false
	end
	local root = self.character:requireRoot()
	if root == nil then
		return false
	end

	local job = if type(opts.job) == "string" and opts.job ~= "" then opts.job else nil
	if job ~= nil and self.motion ~= nil and not self.motion:claim(job) then
		return false
	end

	Teleport.cancel(self)
	self.walkJob = job
	self.retargets += 1

	local from = root.Position

	local staged = opts.path
	if staged == nil then
		staged = self.store:get("cfg.tpPath") ~= false
	end
	local distance = (target - from).Magnitude

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

	if staged ~= true and distance > 0 then
		plan.points = { plan.points[#plan.points] }
	end

	local interval = tonumber(opts.interval) or 0.015
	local index = 0
	self.busy = true

	local function step()

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

	step()
	if self.busy then
		self.handle = self.timers:every(os.clock(), interval, step, false)
	end
	return true
end

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

	if self.motion ~= nil then
		pcall(function()
			self.motion:finish()
		end)
	end

	local entry = self.character:current()

	local okCurrent, current = pcall(function()
		return root.CFrame
	end)
	local rotation = if okCurrent and typeof(current) == "CFrame" then current - current.Position else CFrame.new()
	local snapped = CFrame.new(target) * rotation
	if entry ~= nil and entry.PrimaryPart ~= nil then
		pcall(function()
			entry:PivotTo(snapped)
		end)
	else
		pcall(function()
			root.CFrame = snapped
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
		local wanted
		if typeof(bias) == "Vector3" then
			local flat = look - target
			flat = Vector3.new(flat.X, 0, flat.Z)
			local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			wanted = CFrame.lookAt(target, target + (direction + bias).Unit)
		else
			wanted = CFrame.lookAt(target, look)
		end

		local now = os.clock()
		if self.pinHeading == nil or now - (self.pinHeadingAt or 0) >= 0.1 then
			self.pinHeading = wanted - wanted.Position
			self.pinHeadingAt = now
		end
		cf = CFrame.new(target) * (self.pinHeading or CFrame.new())
	else
		cf = CFrame.new(target)
	end

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

function Teleport.goToMuscleKing(self)
	Teleport.walk(self, Vector3.new(-8727.1, 100, -5796.4), { mode = "tp", hold = false, job = "teleport" })
	local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
	local destination = if portal ~= nil
		then portal.Position + Vector3.new(0, -14, 0)
		else Vector3.new(-8727.1, 389.7, -5796.4)

	self.timers:after(os.clock(), 0.1, function()
		Teleport.walk(self, destination, { mode = "tp", arc = 200, job = "teleport" })
	end)
	return true
end

function Teleport.install(context)
	local self = Teleport.new(context)
	local store = context.store
	local scheduler = context.scheduler

	local machinePhase = context.machinePhase or function()
		return nil
	end

	local isBossEngaged = context.isBossEngaged or context.isBossAlive or function()
		return false
	end

	local isBossBlocked = context.isBossBlocked or function()
		return store:get("boss.auto") == true and isBossEngaged()
	end

	local bodyOwner = context.bodyOwner or function()
		return nil
	end

	local function foreignOwner(): string?
		local owner = bodyOwner()
		if type(owner) ~= "string" or owner == "" then
			return nil
		end
		return owner
	end

	scheduler:register({
		id = "teleportLoop",

		priority = 300,
		enabled = function()
			if store:get("tp.loop") ~= true then
				return false
			end

			if store:get("tp.autoMK") == true then
				return false
			end
			if store:get("kill.enabled") == true then
				return false
			end

			if isBossBlocked() then
				return false
			end

			if store:get("machine.enabled") == true then
				local phase = machinePhase()
				if phase == "mounting" or phase == "mounted" then
					return false
				end
			end

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

		priority = 310,
		enabled = function()
			if store:get("tp.autoMK") ~= true then
				return false
			end

			if isBossBlocked() then
				return false
			end

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

local Duel = {}

export type Side = {
	strength: number?,
	durability: number?,
}

export type Options = {
	maxHits: number?,

	margin: number?,
}

export type Verdict = {
	winnable: boolean,
	reason: string?,

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

	if maxHits <= 0 then
		maxHits = math.huge
	end

	local myStrength = positive(mine.strength)
	local theirDurability = positive(theirs.durability)
	local theirStrength = positive(theirs.strength)

	if myStrength == nil or theirDurability == nil then
		return { winnable = true, reason = nil, ourHits = nil, theirHits = nil }
	end

	local ourHits = theirDurability / myStrength

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

local SafeZones = {}

export type Vec3 = { x: number, y: number, z: number }

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

local TargetLock = {}
TargetLock.__index = TargetLock

export type Options = {

	timeout: number?,

	skipSeconds: number?,
}

export type Verdict = {

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

function TargetLock.skip(self: TargetLock, id: string?, now: number)
	if id == nil or id == "" or self._skipSeconds <= 0 then
		return
	end
	self._skips[id] = now + self._skipSeconds
end

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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetPlan = require("core/PetPlan")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")

local Pets = {}
Pets.__index = Pets

Pets.PRESET_KEYS = { "train", "rebirth", "kill", "boss" }

local STEP_INTERVAL = 0.25

local VERIFY_GRACE = 0.9
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
	if folder ~= nil then
		for _, group in ipairs(folder:GetChildren()) do
			if group:IsA("Folder") then
				for _, pet in ipairs(group:GetChildren()) do
					counts[pet.Name] = (counts[pet.Name] or 0) + 1
				end
			end
		end
	end

	for _, name in ipairs(Pets.equippedModels(self)) do
		counts[name] = (counts[name] or 0) + 1
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

	local user = player()
	local own = if user ~= nil then Workspace:FindFirstChild(user.Name) else nil
	if own ~= nil and sent < UNEQUIP_CAP then
		for _, child in ipairs(own:GetChildren()) do
			if sent >= UNEQUIP_CAP then
				break
			end
			if child:IsA("Model") then
				local slot = child:FindFirstChild("equippedSlot")
				if slot ~= nil and slot:IsA("StringValue") and slot.Value ~= "" then
					self.net:send("petop", now, "unequipPet", child)
					sent += 1
				end
			end
		end
	end
	return sent
end

function Pets.equip(self, name, index, asName)
	local folder = Pets.petsFolder(self)
	if folder == nil or Remotes.equipPet() == nil then
		return false
	end
	local found = {}
	for _, group in ipairs(folder:GetChildren()) do
		if group:IsA("Folder") then
			for _, pet in ipairs(group:GetChildren()) do
				if pet.Name == name then
					table.insert(found, pet)
				end
			end
		end
	end

	local want = math.max(1, math.floor(index or 1))
	local pick = found[want]
	if pick == nil then

		local already = 0
		for _, equippedName in ipairs(Pets.equippedModels(self)) do
			if equippedName == name then
				already += 1
			end
		end
		return already >= want
	end
	return self.net:send("petop", os.clock(), "equipPet", if asName == true then pick.Name else pick)
end

function Pets.cancelSequence(self)
	if self.sequenceHandle ~= nil then
		self.sequenceHandle:cancel()
		self.sequenceHandle = nil
	end

	local sequence = self.sequence
	if sequence ~= nil and sequence.done ~= true then
		self.activeType = nil
	end
	self.sequence = nil
end

function Pets.stepSequence(self, key, now)
	local sequence = self.sequence
	if sequence == nil then
		Pets.cancelSequence(self)
		return
	end
	now = now or os.clock()

	local pending = sequence.pending
	sequence.pending = nil

	if pending ~= nil and sequence.verify == true then
		local count = #Pets.equippedModels(self)
		if count <= pending.count then

			if pending.at == nil or now - pending.at < VERIFY_GRACE then
				sequence.pending = pending
				return
			end
			if pending.retried ~= true then
				Pets.equip(self, pending.name, pending.index, true)
				sequence.pending = {
					name = pending.name,
					index = pending.index,
					count = count,
					retried = true,
					at = now,
				}
				return
			end
			self.notify(string.format("预设 [%s] 的 %s 装备没有生效（服务器未接受）", key, pending.name), "warn")
		end
	end

	sequence.index += 1
	local step = sequence.steps[sequence.index]
	if step == nil then
		self.equipped = #Pets.equippedModels(self)
		sequence.done = true
		Pets.cancelSequence(self)
		self.notify(string.format("预设 [%s] 装备 %d 只", key, self.equipped), "info")
		return
	end

	if step.kind == "unequip" then
		Pets.unequipAll(self)
	elseif step.kind == "equip" then
		local before = #Pets.equippedModels(self)
		if Pets.equip(self, step.name, step.index) then
			sequence.pending = { name = step.name, index = step.index, count = before, at = now }
		end
	end
	self.equipped = #Pets.equippedModels(self)
end

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

	self.sequence = { steps = PetPlan.steps(plan), index = 0, verify = #Pets.equippedModels(self) > 0 }

	self.sequenceHandle = self.timers:every(os.clock(), STEP_INTERVAL, function()
		Pets.stepSequence(self, key, os.clock())
	end, true)
	return true
end

function Pets.scheduleSwap(self, key, delay)
	if self.store:get("petPreset.autoSwitch") ~= true then
		return
	end
	if self.activeType == key then
		return
	end
	local preset = self.store:get("petPreset." .. key)
	if type(preset) ~= "table" or #preset == 0 then

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

function Pets.isBusy(self): boolean
	return self.sequenceHandle ~= nil
end

function Pets.equipFarming(self, max): boolean
	local plan = PetPlan.farming(Pets.ownedNames(self), max)
	if plan.unusable then
		return false
	end
	Pets.cancelSequence(self)
	self.equipped = 0
	self.sequence = { steps = PetPlan.steps(plan), index = 0 }
	self.sequenceHandle = self.timers:every(os.clock(), STEP_INTERVAL, function()
		Pets.stepSequence(self, "farming", os.clock())
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
	if #out > 0 then
		return out
	end

	local list = user:FindFirstChild("equippedPets")
	if list ~= nil then
		for index = 1, 24 do
			local slot = list:FindFirstChild("pet" .. index)
			if slot ~= nil and slot:IsA("ValueBase") then
				local name = tostring(slot.Value or "")
				if name ~= "" then
					table.insert(out, name)
				end
			end
		end
	end
	return out
end

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

__modules["game/Combat"] = function()
	local require = __require

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

local BOSS_PUNCH_INTERVAL = 0.025

local BOSS_REACH = 30

local PIN_INTERVAL = 0.025

local function localPlayer()
	return Players.LocalPlayer
end

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

local function environment()
	return (type(getgenv) == "function" and getgenv()) or _G
end

local function parseFriendNames(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for name in string.gmatch(text, "[^,%s]+") do
		out[string.lower(name)] = true
	end
	return out
end

local function isFriend(self, player)
	local env = environment()

	local predicate = env["MK_HUB_IS_FRIEND"]
	if type(predicate) == "function" then
		local ok, result = pcall(predicate, player)
		if ok then
			return result == true
		end
	end

	local names = self ~= nil and self.friendNames or nil
	if names ~= nil and player ~= nil and names[string.lower(player.Name)] == true then
		return true
	end

	local whitelist = env["MK_HUB_FRIEND_WL"]
	if type(whitelist) ~= "table" then

		return false
	end
	if whitelist.loaded ~= true then
		return true
	end
	return (whitelist.ids or {})[player.UserId] == true
end

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

	self.friendNames = parseFriendNames(self.store:get("kill.friendNames"))

	local count = 0
	for _ in pairs(self.friendIds) do
		count += 1
	end
	for _ in pairs(self.friendNames) do
		count += 1
	end
	if count > 0 then
		self.friendsLoaded = true
	end
	self.friendCount = count
	return count
end

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

		isBossEngaged = context.isBossEngaged or context.isBossAlive or function()
			return false
		end,

		bossPosition = context.bossPosition or nil,

		arbiter = context.arbiter or nil,
		damageHeld = false,

		pets = context.pets or nil,

		teleport = context.teleport or nil,

		machineSeated = context.machineSeated or nil,
		pinAt = 0,
		lastPresetKey = nil,

		friendIds = {},
		friendNames = {},
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

		killPunches = 0,

		punchAtLock = 0,
		lastReason = "idle",

		lock = TargetLock.new(),

		skipStats = { protected = 0, unwinnable = 0, skipped = 0, total = 0 },

		arenaAreas = nil,
		arenaAt = 0,

		bossPunchAt = 0,
		bossHandLeft = false,
		bossPunches = 0,
	}, Combat)
	return self
end

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
					friend = isFriend(self, player),
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

	if self.store:get("kill.single") == true and self.store:get("kill.enabled") ~= true then
		lockedId = tostring(self.store:get("kill.singleName") or "")
	end

	local decision = Targeting.select(Combat.candidates(self), { x = position.X, y = position.Y, z = position.Z }, {

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

function Combat.punch(self, left, now)
	if self.character:isAlive() ~= true then
		return
	end
	local character = self.character:current()
	local humanoid = self.character:humanoid()
	if character == nil or humanoid == nil then
		return
	end

	if self.store:get("train.dualTool") == "train" then
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
	self.killPunches += 1
	Combat.playAnimation(self, humanoid, left)
end

function Combat.wantsDamage(self): boolean
	if self.store:get("boss.auto") == true and self.isBossEngaged() then
		return true
	end
	return Combat.engaged(self)
end

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
	Combat.punch(self, self.bossHandLeft, now)
	self.bossPunches += 1
end

function Combat.presetFor(self): string?
	if self.store:get("boss.auto") == true and self.isBossEngaged() then
		return "boss"
	end
	if Combat.isBusy(self) then
		return "kill"
	end
	return nil
end

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

function Combat.machineHeld(self): boolean
	local check = self.machineSeated
	if type(check) ~= "function" then
		return false
	end
	local ok, seated = pcall(check)
	return ok and seated == true
end

function Combat.attack(self, target)

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

		local height = tonumber(self.store:get("kill.hoverHeight")) or 12
		local destination = targetPosition + Vector3.new(0, math.max(1, height), 0)
		local bias = if self.store:get("kill.lookDown") == false then nil else Vector3.new(0, -1, 0)

		if self.teleport ~= nil and self.store:get("kill.directPin") ~= false then
			local stamp = os.clock()
			if stamp - (self.pinAt or 0) >= PIN_INTERVAL then
				self.pinAt = stamp

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

	self.lock:configure({
		timeout = tonumber(self.store:get("kill.targetTimeout")),
		skipSeconds = tonumber(self.store:get("kill.targetSkip")),
	})

	if self.locked ~= nil then

		local valid = true
		if now - self.validatedAt >= VALIDATE_INTERVAL then
			self.validatedAt = now

			valid = (self.locked.Parent ~= nil) and (aliveRoot(self.locked) ~= nil)
		end

		local verdict = self.lock:step(now, valid)
		if verdict.action ~= "keep" then
			if verdict.action == "timeout" then

				if self.killPunches == self.punchAtLock then
					self.lock:unskip(verdict.id)
				else
					self.lastReason = string.format("超时跳过 %s（%d 秒没打死）",
						tostring(verdict.id), math.floor(self.lock._timeout))

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

			self.lock:lock(target.Name, now)

			self.punchAtLock = self.killPunches
		end
	end

	if self.locked ~= nil then
		self.attack(self, self.locked)
	end
end

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
	if self.store:get("kill.friendWL") == true and isFriend(self, king) then
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

function Combat.guardPunch(self, now)
	if self.store:get("cfg.keepPunch") ~= true or not Combat.wantsDamage(self) then
		self.punchMissingSince = 0
		return
	end

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

		held = self.lock:held(now),
		timeouts = self.lock._timeouts,
		skippedCount = self.lock:skipCount(now),
		skippedIds = self.lock:skippedIds(now),
		skipStats = self.skipStats,
	}
end

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

	self.net:addChannel("punch", GameNet.senderFor(Remotes.muscle), {
		rate = 400,
		burst = 60,
		queue = 0,
	})

	local store = self.store

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

			Combat.maintainDamageHold(self)
			Combat.bossPunchTick(self, now)
		end,
	})

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

	self.scheduler:register({
		id = "friendRefresh",
		priority = 45,
		enabled = function()
			return store:get("kill.friendWL") == true
		end,
		onEnable = function()

			self.lastFriendTry = 0
		end,
		tick = function(_dt, now)
			if now - self.lastFriendTry < 10 then
				return
			end
			self.lastFriendTry = now
			Combat.refreshFriends(self)

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

local VirtualInputManager = game:GetService("VirtualInputManager")

local BossInfo = require("core/BossInfo")
local ChestTimer = require("core/ChestTimer")
local Pets = require("game/Pets")
local Remotes = require("game/Remotes")

local Teleport = require("game/Teleport")

local Players = game:GetService("Players")

local Boss = {}
Boss.__index = Boss

local DETECT_CACHE = 0.5
local INTERACT_INTERVAL = 0.4
local TOUCH_TAIL = 0.05

local CHEST_STAND_HEIGHT = 15

local CHEST_HOLD = 4

local CHEST_WALK_INTERVAL = 0.7
local CHEST_WALK_TRIES = 6

local FIGHT_LIMIT = 150
local FIGHT_SKIP = 90

local function selectionOf(store)
	local selection = {}
	for _, rarity in ipairs(BossInfo.RARITIES) do
		selection[rarity] = store:get("boss.select." .. rarity) ~= false
	end
	return selection
end

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

		health, maxHp = healthFromDescendants(model)
		if health == nil and model ~= holder then
			health, maxHp = healthFromDescendants(holder)
		end
	end
	return health, maxHp
end

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

	return total == 0
end

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

		pets = context.pets or nil,

		sizeRef = context.size or nil,

		rejoin = context.rejoin or nil,

		persist = context.persist or nil,

		machineSeated = context.machineSeated or nil,

		lastPosition = nil,
		cacheAt = 0,
		cacheInfo = BossInfo.empty(),

		trackedHolder = nil,
		trackedModel = nil,
		chest = ChestTimer.new(),
		lastInteract = 0,
		loots = 0,

		chestClaim = false,
		chestStatus = "idle",

		engaged = false,

		chestLootedAt = nil,

		eventHolderCache = nil,
		eventHolderCacheAt = 0,

		travelAt = 0,
		travelFirstAt = 0,
		travelTries = 0,
		travelGaveUp = false,
		travelWarned = false,

		pinAt = 0,
	}, Boss)
	return self
end

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

function Boss.detectEvent(self)
	local selection = eventSelection(self.store)
	local holders = Boss.eventHolders(self)

	self.eventRig = nil
	self.eventModel = nil
	for _, entry in ipairs(BossInfo.events()) do
		if eventWanted(selection, entry.key) then
			local holder = holders[entry.key]
			if holder ~= nil and holder.Parent ~= nil then
				local model = holder:FindFirstChild("Boss") or holder

				if not bossDown(holder, model) then

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

				if not bossDown(holder, model) then
					alive += 1
				end
			end
		end
	end
	return alive > 0, present > 0, alive, wanted
end

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

local function slotRarity(name: string): string
	local fixed = BossInfo.fixed()
	local lowered = string.lower(name)
	for _, entry in ipairs(fixed) do
		if string.lower(entry.id) == lowered then
			return entry.rarity
		end
	end

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

local function isFixedSlotName(name: string): boolean
	for _, entry in ipairs(BossInfo.fixed()) do
		if entry.id == name then
			return true
		end
	end
	return false
end

local function normalHolder(selection)
	local events = Workspace:FindFirstChild("Events")
	local arena = events ~= nil and events:FindFirstChild("BossArena") or nil
	if arena == nil then
		return nil
	end

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

	local narrowed = BossInfo.narrowed(selection)
	for _, holder in ipairs(arena:GetChildren()) do
		local model = holder:FindFirstChild("Boss")
		if model ~= nil and not isEventRig(holder) and not bossDown(holder, model) then

			if not isFixedSlotName(holder.Name) then
				local rarity = slotRarity(holder.Name)
				if rarity == BossInfo.UNKNOWN then

					rarity = slotRarity(model.Name)
				end
				local wanted = if rarity == BossInfo.UNKNOWN
					then not narrowed
					else BossInfo.selected(rarity, selection)
				if wanted then

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

	self.normalRig = holder
	self.normalModel = model
	if info ~= nil then
		return info
	end

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

			return flat
		end
	end

	return nil
end

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

	if chosen ~= nil and chosen.alive == true then
		if chosen.group == BossInfo.EVENT_GROUP then
			self.trackedHolder = self.eventRig
			self.trackedModel = self.eventModel
		else
			self.trackedHolder = self.normalRig
			self.trackedModel = self.normalModel
		end
	else

		self.trackedHolder = nil
		self.trackedModel = nil
	end
	return self.cacheInfo
end

function Boss.invalidate(self)
	self.cacheAt = 0
end

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

function Boss.livePosition(self)
	local model = self.trackedModel
	if model == nil or model.Parent == nil then
		return nil
	end
	return objectPosition(model)
end

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

local TRAVEL_RETRY = 0.5

local STAGING_RESNAP = 0.1

local TRAVEL_ATTEMPT_LIMIT = 8

local TRAVEL_DEADLINE = 6

local HALLOWED_STAGING = Vector3.new(283, 19, 372)
local STAGING_REACH = 25

local TRAVEL_BEAT = 0.12

function Boss.requestTravel(self): boolean

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

	local function fire()
		pcall(function()
			if remote:IsA("RemoteFunction") then
				remote:InvokeServer("travelToArea", circle)
			else
				remote:FireServer("travelToArea", circle)
			end
		end)
	end

	if self.timers ~= nil then
		self.timers:after(os.clock(), TRAVEL_BEAT, function()
			task.spawn(fire)
		end)
	else
		task.spawn(fire)
	end
	return true
end

function Boss.ensureArena(self, now, info): boolean
	if inHallowedGym() then
		self.travelAt = 0
		self.travelTries = 0
		self.travelFirstAt = 0
		self.travelGaveUp = false
		self.travelWarned = false
		return true
	end

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

local function lookBias(store)
	if store:get("kill.lookDown") == false then
		return nil
	end
	return Vector3.new(0, -1, 0)
end

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

function Boss.chestPending(self): boolean
	return self.chestClaim == true
end

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

	local skip = self.fightSkip
	local name = info.name or info.eventKey
	if skip ~= nil and name ~= nil and name == skip.name and now < (skip.expires or 0) then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end
	if self.fightTarget ~= name then
		self.fightTarget = name
		self.fightAt = nil
	end

	if Boss.chestPending(self) then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	if Boss.machineHeld(self) then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

	if not info.alive or typeof(info.position) ~= "Vector3" then
		Boss.releaseHold(self)
		self.approachAt = 0
		self.engaged = false
		return
	end

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

	self.lastPosition = position

	if info.group == BossInfo.EVENT_GROUP and not Boss.ensureArena(self, now, info) then
		Boss.releaseHold(self)
		self.engaged = false
		return
	end

	local target = Boss.livePosition(self) or info.position

	local destination = target + Vector3.new(0, hoverHeight(self.store, info), 0)

	self.approachAt = now
	if self.teleport ~= nil and Teleport.isBusy(self.teleport) then

		Teleport.cancel(self.teleport)
	end

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

	self.motion:setLook(target, lookBias(self.store))

	self.engaged = self.motion:isActive() or pinned == true
	if self.engaged then
		if self.fightAt == nil then
			self.fightAt = now
		elseif now - self.fightAt > FIGHT_LIMIT then
			self.fightAt = nil
			self.fightSkip = { name = name, expires = now + FIGHT_SKIP }
			self.notify(
				string.format("打了 %d 秒还没打死 %s，先换目标（%d 秒内不再打它）", FIGHT_LIMIT, tostring(name), FIGHT_SKIP),
				"warn"
			)
			Boss.releaseHold(self)
			Boss.invalidate(self)
			self.engaged = false
		end
	else
		self.fightAt = nil
	end
end

function Boss.leave(self)
	if self.pets ~= nil then
		Pets.scheduleSwap(self.pets, "train", 0.5)
	end

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

	Boss.releaseHold(self)
	if destination ~= nil and self.teleport ~= nil then

		self.teleport:walk(destination, { mode = "tp", hold = false, job = "boss" })
	end
	self.lastPosition = nil
end

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

	local status = self.chest:observe(Boss.isNormalAlive(self), now)
	self.chestStatus = status
	if status ~= "ready" then
		self.chestClaim = false

		self.chestLootedAt = nil
		self.chestMisses = 0
		self.chestGaveUp = false
		return
	end

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

	self.chestClaim = true

	local fell = origin ~= nil and (origin.Y < stand.Y - 40 or origin.Y < -50)

	local current = self.motion:targetPosition()

	local reached = origin ~= nil and (origin - stand).Magnitude <= 12 and not fell
	local nearby = reached
		or (
			self.motion:isActive()
			and typeof(current) == "Vector3"
			and (current - stand).Magnitude <= 5
			and not fell
		)
	if not nearby then

		self.chestMisses = (self.chestMisses or 0) + 1
		if self.chestMisses > CHEST_WALK_TRIES then
			self.chestClaim = false
			if self.chestGaveUp ~= true then
				self.chestGaveUp = true
				self.notify("多次走不到宝箱（可能被地形挡住），本次放弃，下个宝箱再试", "warn")
			end
			return
		end
		if now - (self.chestWalkAt or 0) < CHEST_WALK_INTERVAL then
			return
		end
		self.chestWalkAt = now

		self.teleport:walk(stand, { mode = "chest", arc = 120, job = "chest" })

		return
	end
	self.chestMisses = 0

	if now - self.lastInteract < INTERACT_INTERVAL then
		return
	end
	self.lastInteract = now
	Boss.interact(self, chest)

	if self.chestLootedAt == nil then
		self.loots += 1
		self.chestLootedAt = now
	end
end

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

			self.engaged = false
			Boss.leave(self)
		end,
		tick = function(_dt, now)
			Boss.approach(self, now)
		end,
	})

	self.scheduler:register({
		id = "chest",
		priority = 430,
		enabled = function()

			return store:get("boss.auto") == true and store:get("boss.autoChest") ~= false
		end,
		onDisable = function()
			self.chestClaim = false
			self.chestStatus = "idle"
		end,
		tick = function(_dt, now)
			Boss.chestTick(self, now)
		end,
	})

	store:subscribe("boss.priority", function()
		Boss.invalidate(self)
	end)

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

local CrystalList = {}

export type Entry = {
	name: string,
	price: number?,
	priceType: string?,
	label: string,
}

function CrystalList.parse(chances: { [string]: any }?, prices: { [string]: any }?): { Entry }
	local out: { Entry } = {}
	if chances == nil then
		return out
	end

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

		local label: string = name
		if price ~= nil and price > 0 then
			local kind: string = "价格"
			if priceType ~= nil then
				kind = priceType
			end
			local amount: string = tostring(math.floor(price))

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

		if type(name) == "string" and name ~= "" and wanted == true then
			out[name] = true
		end
	end
	return out
end

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

function CrystalList.pool(pools: { [string]: { [string]: any } }?, name: string?): { string }
	local out: { string } = {}
	if pools == nil or name == nil then
		return out
	end
	local pool = pools[name]
	if pool == nil then
		return out
	end

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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrystalList = require("core/CrystalList")
local Remotes = require("game/Remotes")

local Crystals = {}
Crystals.__index = Crystals

local OPEN_TIMEOUT = 3
local OPEN_TIMEOUT_RTT = 3

local MAX_IN_FLIGHT = 48

local WARN_INTERVAL = 5

local SAVE_DEBOUNCE = 0.6

local function sharedFolder()
	return ReplicatedStorage:FindFirstChild("shared")
end

local function catalogsFolder()
	local shared = sharedFolder()
	return shared and shared:FindFirstChild("catalogs") or nil
end

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

		metrics = context.metrics,
		notify = context.notify or function() end,
		entries = {},
		pools = {},
		catalogueAt = 0,
		lastOpen = 0,
		inFlight = 0,

		tickets = {},
		opened = 0,
		applied = 0,
		saveAt = nil,
		lastResult = "-",
	}, Crystals)
	return self
end

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

function Crystals.labelFor(self, name: string?): string
	local entries = Crystals.catalogue(self)
	local label = CrystalList.labelFor(entries, name)
	if label == nil or label == "" then
		return "—"
	end
	return label
end

function Crystals.nameForLabel(self, label: string?): string
	return CrystalList.nameForLabel(Crystals.catalogue(self), label)
end

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

function Crystals.selectedPool(self): { string }
	local name = self.store:get("crystal.selected")
	Crystals.catalogue(self)
	return CrystalList.pool(self.pools, if type(name) == "string" then name else nil)
end

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

			self.lastResult = if reply == nil then "服务器未返回结果" else "服务器拒绝"
		end
	end)
	return true
end

function Crystals.applyAutoSell(self): boolean
	local remote = Remotes.crystal()
	local name = Crystals.selectedName(self)
	if remote == nil or name == nil then
		return false
	end

	local sell = CrystalList.sellNames(self.store:get("crystal.sellByCrystal"), name)
	local payload = CrystalList.sellPayload(sell, self.store:get("crystal.autoSell") == true)

	task.spawn(function()
		local ok = pcall(function()
			remote:InvokeServer("saveAutoSell", name, payload)
		end)

		if ok then
			self.applied += 1
		end
	end)
	return true
end

function Crystals.sellSelection(self)
	return CrystalList.sellNames(
		self.store:get("crystal.sellByCrystal"),
		Crystals.selectedName(self)
	)
end

function Crystals.setSell(self, pet: string?, marked: boolean)
	local name = Crystals.selectedName(self)
	if name == nil then
		self.notify("先选一个水晶", "warn")
		return
	end
	self.store:set("crystal.sellByCrystal",
		CrystalList.withMark(self.store:get("crystal.sellByCrystal"), name, pet, marked))
end

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

			Crystals.applyAutoSell(self)
		end,
		tick = function(_dt, now)

			local timeout = OPEN_TIMEOUT
			local metrics = self.metrics
			local rtt = 0
			if metrics ~= nil then

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

local VirtualInputManager = game:GetService("VirtualInputManager")

local MachinePlan = require("core/MachinePlan")
local Remotes = require("game/Remotes")

local Machine = {}
Machine.__index = Machine

local SCAN_CACHE = 2

local SIT_HEIGHT = 1.2
local KEY_TAIL = 0.05

local SIT_INTERVAL = 0.06
local SEND_INTERVAL = 0.12
local SEAT_TIMEOUT = 4

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

		teleport = context.teleport or nil,
		isCombatBusy = context.isCombatBusy or function()
			return false
		end,
		isBossAlive = context.isBossAlive or function()
			return false
		end,

		isBossBlocked = context.isBossBlocked or function()
			return false
		end,

		isDamageNeeded = context.isDamageNeeded or function()
			return false
		end,
		notify = context.notify or function() end,
		cache = {},
		cacheAt = 0,
		target = nil,
		attempts = 0,
		lastPhase = "idle",

		blockReason = nil,
		placeAt = nil,
		sendAt = nil,
		seatSince = nil,
	}, Machine)
	return self
end

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

function Machine.blocked(self): boolean
	local blocked = Machine.blockedState(self)
	return blocked
end

function Machine.blockedState(self): (boolean, string?)

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

function Machine.use(self, seat): boolean
	local remote = Remotes.machine()
	if remote == nil then
		return false
	end

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

local function mountSeat(self, root, humanoid, seat, now)
	local ok, position = pcall(function()
		return seat.Position
	end)

	if self.teleport ~= nil and ok and typeof(position) == "Vector3" then

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

	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, seat, root, 0)
		self.timers:after(now, KEY_TAIL, function()
			pcall(firetouchinterest, seat, root, 1)
		end)
	end
end

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

	local seat = if self.target ~= nil then self.target.seat else nil
	return occupantOf(seat) == humanoid
end

function Machine.tick(self, now)
	local humanoid = self.character:humanoid()
	local root = self.character:requireRoot()
	local hasCharacter = humanoid ~= nil and root ~= nil

	local blocked, reason = Machine.blockedState(self)
	self.blockReason = reason
	if blocked then
		if self.lastPhase ~= "blocked" then

			if self.lastPhase == "mounted" or self.lastPhase == "mounting" then
				Machine.dismount(self)
			end
			self.lastPhase = "blocked"
			self.target = nil
		end
		return
	end

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

	if occupant ~= nil and occupant ~= humanoid then
		self.target = nil
		self.seatSince = nil
		return
	end

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

			if self.isBossBlocked() then
				return false
			end
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

		if self.pets ~= nil then
			Pets.clearActiveType(self.pets)
		end
		return
	end

	if result.action == "send" then
		self.requests += 1
		if not self.net:send("rebirth", now, "rebirthRequest") then

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

local Players = game:GetService("Players")
local StatsService = game:GetService("Stats")

local Metrics = require("core/Metrics")
local PlayerStats = require("game/PlayerStats")

local GameMetrics = {}
GameMetrics.__index = GameMetrics

local MEMORY_INTERVAL = 15
local PING_INTERVAL = 1
local STATS_INTERVAL = 0.25

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

					estimated = true
				end
			end
			if millis ~= nil then
				self.metrics:setPingEstimated(estimated)
				self.metrics:pushPing(millis)
			end
		end
	end

	if now - (self.statsAt or 0) >= STATS_INTERVAL then
		self.statsAt = now
		GameMetrics.trackStrength(self, now)
		GameMetrics.trackRebirths(self, now)
	end
end

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

local HOP_TIMEOUT = 20

local PLAYER_CACHE = 60
local PLAYER_MISS_TTL = 5

function Rejoin.new(context)
	local self = setmetatable({
		store = context.store,
		scheduler = context.scheduler,
		timers = context.timers,
		metrics = context.metrics,
		notify = context.notify or function() end,

		onPending = context.onPending or nil,
		triggers = RejoinTriggers.new(),
		startedAt = os.clock(),
		timedLast = os.clock(),
		checkAt = 0,
		httpFailedAt = 0,

		_state = "idle",
		_triggered = false,
		pendingHandle = nil,

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

local function httpRequest(url, method, body, contentType)
	local verb = method or "GET"
	local headers = if body ~= nil
		then { ["Content-Type"] = contentType or "application/json" }
		else nil

	for _, executor in ipairs(httpExecutors()) do

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

function Rejoin.playerJobId(self, name, force)
	if name == nil or name == "" then
		return nil, "no-name"
	end
	local cached = self.playerCache
	if force ~= true and cached ~= nil and cached.name == name then

		local ttl = if cached.jobId ~= nil and cached.jobId ~= "" then PLAYER_CACHE else PLAYER_MISS_TTL
		if os.clock() - cached.at < ttl then
			return cached.jobId, cached.status
		end
	end

	local jobId, status = lookupPlayerJob(name)
	self.playerCache = { name = name, jobId = jobId, at = os.clock(), status = status }
	return jobId, status
end

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

function Rejoin.perform(self, reason, modeOverride, exactJobId)
	self.notify("正在重进...", "warn")

	local mode = modeOverride or self.store:get("rejoin.mode") or "same"
	local servers = {}
	local order = if mode == "sparse" or mode == "player" or mode == "private" then "Asc" else "Desc"
	servers = if mode == "private" then {} else (Rejoin.fetchServers(self, order) or {})

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

			self.notify("换服失败：所有目标都没进去（可能都满了）", "error")
			Rejoin.reset(self)
			self.plan = nil
			return false
		end

		if attempt.kind == "job" and (attempt.id == nil or attempt.id == "" or attempt.id == game.JobId) then
			if attempt.id == game.JobId and self.planIndex < #attempts then
				continue
			end
			if attempt.id == nil or attempt.id == "" then
				continue
			end

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

		self.notify(string.format("%s 无法传送，试下一个目标", attempt.label), "warn")
	end
end

function Rejoin.hopWatch(self, now)
	if self.hopAt == nil or self.hopAt == 0 then
		return
	end
	if now - self.hopAt < HOP_TIMEOUT then
		return
	end

	if game.JobId ~= self.hopJobId then

		self.hopAt = 0
		return
	end

	self.hopAt = 0
	self.notify(string.format("%s 超时未生效（多半已满），自动降级", tostring(self.hopLabel or "目标服务器")), "warn")
	if Rejoin.attemptNext(self, "hop-timeout") == false then

		self.hopAt = 0
	end
end

function Rejoin.spawnPerform(self, reason, modeOverride, exactJobId)
	task.spawn(function()
		pcall(function()
			Rejoin.perform(self, reason, modeOverride, exactJobId)
		end)
	end)
end

function Rejoin.beginUrgent(self, reason, modeOverride, exactJobId)
	self._state = "running"
	self._triggered = true
	Rejoin.spawnPerform(self, reason, modeOverride, exactJobId)
	return true
end

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

	if self.onPending ~= nil then
		pcall(self.onPending, tostring(reason or ""), function()
			return Rejoin.cancelPending(self)
		end, function()

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

function Rejoin.reset(self)
	self._state = "idle"
	self._triggered = false
	if self.pendingHandle ~= nil then
		self.pendingHandle:cancel()
		self.pendingHandle = nil
	end
end

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

function AntiAfk.bindKick(self, rejoin)
	local user = Players.LocalPlayer
	if user == nil or rejoin == nil then
		return
	end

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

local Lighting = game:GetService("Lighting")

local Perf = {}
Perf.__index = Perf

local BUDGET_PER_TICK = 250
local RESCAN_SECONDS = 90

local EFFECT_OFF = {
	ParticleEmitter = "Enabled",
	Trail = "Enabled",
	Beam = "Enabled",
	Fire = "Enabled",
	Smoke = "Enabled",
	Sparkles = "Enabled",

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

		restores = {},
		groups = { effects = 0, textures = 0, culled = 0 },
	}, Perf)
	return self
end

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

	table.remove(self.restores)
	return false
end

function Perf.enable(self)
	if self.lighting ~= nil then
		return
	end

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

		if now < (self.nextScanAt or 0) then
			return
		end
		local ok, descendants = pcall(function()

			local out = Workspace:GetDescendants()
			local effects = Lighting:GetDescendants()
			for _, object in ipairs(effects) do
				table.insert(out, object)
			end
			return out
		end)
		if not ok then

			self.nextScanAt = now + RESCAN_SECONDS
			return
		end
		self.snapshot = descendants
		self.cursor = 0

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

	self.disabled = 0
	self.groups = { effects = 0, textures = 0, culled = 0 }

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

local TrainRate = require("core/TrainRate")
local Arbiter = require("core/Arbiter")
local GameNet = require("game/Net")
local Remotes = require("game/Remotes")
local Tools = require("game/Tools")
local Pets = require("game/Pets")

local Players = game:GetService("Players")

local Train = {}

Train.CHANNEL = "muscle"

Train.THROTTLE_RATE = 2000
Train.THROTTLE_BURST = 64

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

	local isBossBlocked = context.isBossBlocked or function()
		return store:get("boss.auto") == true and isBossAlive()
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

			store:set("train.effRate", math.floor(rate + 0.5))
			store:set("train.rateSource", source)
			local perFrame = math.max(1, math.floor(tonumber(store:get("cfg.netBurst")) or 40))
			local budget = TrainRate.step(state, rate, dt, perFrame)
			if budget <= 0 then
				return
			end

			if Remotes.muscle() == nil then
				TrainRate.refund(state, budget)
				return
			end

			local sent = net:burst(Train.CHANNEL, now, budget, "rep")
			delivered += sent
			if sent < budget then
				refused += (budget - sent)
				TrainRate.refund(state, budget - sent)

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

	local missingSince = 0
	local lastAttempt = 0
	local lastRespawn = 0
	local respawns = 0
	local cooldown = false

	local machineToolAt = 0

	for _, path in ipairs({ "train.toolDumbbell", "train.toolPush", "train.toolHand", "train.toolSit" }) do
		store:subscribe(path, function(_, value)
			if value == true then
				cooldown = false
				missingSince = 0

				respawns = 0
			end
		end)
	end

	scheduler:register({
		id = "tool",
		priority = 60,

		enabled = function()
			if not (store:get("train.auto") == true or store:get("train.fast") == true) then
				return false
			end
			if cooldown then
				return false
			end

			if isBossBlocked() and store:get("train.duringBoss") ~= true then
				return false
			end

			if arbitrationActive() then
				return false
			end

			return true
		end,
		tick = function(_dt, now)

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

			setDualMode("punch", os.clock())
		end,
		tick = function(_dt, now)

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

				if holdTrainingTool(humanoid, player, model) then
					if now - dualSince >= dwell then
						setDualMode("punch", now)
					end
					return
				end

				setDualMode("punch", now)
				return
			end

			Tools.equip(model, humanoid, player, Tools.PUNCH)
			if now - dualSince >= dwell then

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

local TweenService = game:GetService("TweenService")

local Palette = require("core/Palette")
local Attributes = require("core/Attributes")

local Theme = {}

type RGB = { r: number, g: number, b: number }
type Roles = { [string]: RGB }
type RemapEntry = { from: RGB, to: RGB }
type Remap = { exact: { [string]: RGB }, entries: { RemapEntry } }

Theme.NAMES = { "light", "dark", "ocean", "sakura", "forest", "flame" }
Theme.FALLBACK = "light"

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

function Theme.apply(root: Instance?, remap: Remap, duration: number?): number
	if root == nil then
		return 0
	end
	local time = duration or Theme.RECOLOR_TIME
	local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local changed = 0

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

local TweenService = game:GetService("TweenService")

local UserInputService = game:GetService("UserInputService")

local Attributes = require("core/Attributes")

local Kit = {}
Kit.__index = Kit

local ROW_HEIGHT = 40
local ROW_HEIGHT_WITH_HINT = 52
local DROPDOWN_MAX_HEIGHT = 300
local DROPDOWN_OPTION_HEIGHT = 26

local TOUCH_ARM = 8

function Kit.new(context)

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

		timers = context.timers,
		connections = {},
		destroyed = false,
	}, Kit)
	return self
end

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

function Kit.toast(self, text, kind, duration)
	if self.onToast == nil then
		return
	end
	pcall(self.onToast, text, kind, duration)
end

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

function Kit.bind(self, path, default, apply)
	local current = self.store:get(path)
	apply(if current == nil then default else current, true)
	self:track(self.store:subscribe(path, function(_, value)
		if value ~= nil then
			apply(value, false)
		end
	end))
end

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

function Kit.slider(self, parent, spec)
	local minimum = spec.min or 0
	local maximum = spec.max or 100
	local fallback = spec.default or minimum
	local mapping = spec.map

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
		Position = UDim2.fromOffset(0, -13),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Text = "",
		Active = true,
		ZIndex = 4,
	}, trackBar)

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

			dragging = true
			lockScroll(true)
			self:tween(knob, 0.1, { Size = UDim2.fromOffset(26, 26) })
			applyFromX(input.Position.X)
		end
	end))

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

			if math.abs(dx) < TOUCH_ARM or math.abs(dx) < math.abs(dy) then
				return
			end
			dragging = true
			lockScroll(true)
			self:tween(knob, 0.1, { Size = UDim2.fromOffset(26, 26) })
		end
		trackRect()

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

			if spec.path ~= nil then
				self.store:set(spec.path, toStore(current))
			end
			if spec.onChange ~= nil then
				task.spawn(spec.onChange, current)
			end
		end

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

			if changed and drawn then
				draw()
			end
		end,

		set = function(display)
			currentDisplay = tostring(display)
			button.Text = currentDisplay .. "  ▾"
		end,
	}
end

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

local UserInputService = game:GetService("UserInputService")

local Theme = require("ui/Theme")
local ShellState = require("core/ShellState")
local Format = require("core/Format")
local Attributes = require("core/Attributes")

local Shell = {}
Shell.__index = Shell

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

		services = context.services or {},

		scheduler = context.scheduler,
		uiTicks = {},
		pages = {},
		built = false,
		activeTab = nil,
		themeName = context.store:get("uiState.theme") or "light",
		connections = {},

		morphSeq = 0,

		morphAt = 0,
	}, Shell)
	return self
end

function Shell.registerPage(self, spec)
	table.insert(self.pages, spec)
	return spec
end

function Shell.addUiTick(self, fn)
	table.insert(self.uiTicks, fn)
	return fn
end

function Shell.toast(self, text, kind, duration)
	if self.onToast ~= nil then
		pcall(self.onToast, text, kind, duration)
	end
end

function Shell.screenGui(self)
	return self.screen
end

function Shell.delay(self, seconds, fn)
	local timers = self.timers
	if timers ~= nil then
		return timers:after(os.clock(), seconds, fn)
	end

	task.delay(seconds, fn)
	return nil
end

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

function Shell.applyVisualState(self, state)
	self.main.Size = UDim2.fromOffset(state.layout.width, state.layout.height)
	self.mainCorner.CornerRadius = UDim.new(0, state.layout.corner)
	applyLayers(self, state.layers)

	if self.onVisualState ~= nil then
		pcall(self.onVisualState, state)
	end
end

function Shell.applySize(self, instant)

	local state = Shell.visualState(self)
	local targetScale = ((self.store:get("uiState.uiScale") or 100) / 100) * Shell.resFactor()
	if instant then
		Shell.applyVisualState(self, state)
		self.mainScale.Scale = targetScale
	else

		self.morphSeq += 1
		self.kit:tween(self.main, 0.2, {
			Size = UDim2.fromOffset(state.layout.width, state.layout.height),
		}, Enum.EasingStyle.Quint)
		self.kit:tween(self.mainCorner, 0.2, { CornerRadius = UDim.new(0, state.layout.corner) },
			Enum.EasingStyle.Quint)

		self.kit:tween(self.mainScale, 0.2, { Scale = targetScale }, Enum.EasingStyle.Quint)

		applyLayers(self, state.layers)
		if self.onVisualState ~= nil then
			pcall(self.onVisualState, state)
		end
	end

	if self.syncSliders ~= nil then
		self.syncSliders()
	end

	self:delay(if instant then 0.35 else 0.26, function()
		if self.destroyed then
			return
		end
		Shell.reapplyPosition(self, false)

		if self.onGeometrySettled ~= nil then
			pcall(self.onGeometrySettled)
		end
	end)
end

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

function Shell.positionFromStore(self): UDim2
	local saved = self.store:get("uiState.savedMain")
	if type(saved) ~= "table" then
		return UDim2.new(0.5, 0, 0.5, 0)
	end
	return UDim2.new(saved.xs or 0.5, saved.xo or 0, saved.ys or 0.5, saved.yo or 0)
end

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

function Shell.reapplyPosition(self, animate)
	if self.main == nil or self.destroyed then
		return false
	end

	if self.pill == true then
		return Shell.clampOnScreen(self)
	end

	local target = Shell.positionFromStore(self)
	local viewport = Shell.viewport(self)
	if viewport == nil then

		Shell.setPosition(self, target, false)
		return false
	end

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

	local pillDot = kit:instance("Frame", {
		Name = "PillDot",
		Position = UDim2.fromOffset(48, 17),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = kit:color("Green"),
		BorderSizePixel = 0,
	}, pill)
	kit:corner(pillDot, 4)
	self.pillDot = pillDot

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

	Shell.bindStore(self)
	Shell.buildNavigation(self)
	Shell.buildPages(self)
	Shell.bindDrag(self, topBar)
	Shell.bindInput(self)
	Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	Shell.bindHotkeys(self)
	Shell.buildResetButton(self, screen)
	Shell.bindStatus(self)

	Shell.applySize(self, true)
	if #self.pages > 0 then

		Shell.switchTab(self, self.pages[1].id)
	end

	if self.store:get("uiState.minimized") == true then
		Shell.setMinimized(self, true, true)
	end

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

		if Shell.overlayTakes(self, input.Position) then
			return
		end

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

function Shell.setMinimized(self, minimized, instant)
	self.minimized = minimized
	local state = Shell.visualState(self)

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

	self.store:set("uiState.pill", enabled)

	local state = Shell.visualState(self)

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

				self.pillLayer.Visible = true
				Shell.setPillContent(self, 1, 0.02)
				Shell.setPillContent(self, 0, 0.24)
			else

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

		onRevealed = function()
			if not enabled then
				Shell.replayCards(self, self.activeTab)
			end
		end,
	})
end

function Shell.setTheme(self, name)

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

	self.kit:track(store:subscribe("uiState.savedPill", function(_, value)
		if type(value) == "table" and self.pill then
			self.pillPosition = UDim2.new(value.xs or 0.5, value.xo or 0, value.ys or 0.5, value.yo or 0)
		end
	end))

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

	self.kit:track(store:subscribe("uiState.fontScale", function()
		Shell.applyFontScale(self)
	end))

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
			end)
		end))
	end
end

function Shell.bindButtons(self, minimizeButton, pillButton, closeButton)
	local kit = self.kit
	local store = self.store

	self.minimizeButton = minimizeButton
	self.pillButton = pillButton
	self.closeButton = closeButton

	kit:track(minimizeButton.MouseButton1Click:Connect(function()

		store:set("uiState.minimized", store:get("uiState.minimized") ~= true)
	end))

	kit:track(pillButton.MouseButton1Click:Connect(function()
		self.pillPosition = self.main.Position
		Shell.setPill(self, not self.pill)
	end))

	kit:track(closeButton.MouseButton1Click:Connect(function()
		Shell.confirm(self, "关闭确认", "确定要关闭脚本吗？", function()

			Shell.closeAnimated(self)
		end)
	end))
end

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

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, kit:color("Red")),
		ColorSequenceKeypoint.new(1, kit:color("Yellow")),
	})
	gradient.Transparency = NumberSequence.new(0.3)
	gradient.Rotation = 0
	gradient.Parent = button

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

function Shell.resetLayout(self)
	local store = self.store
	store:set("uiState.widthPct", 45)
	store:set("uiState.heightPct", 52)
	store:set("uiState.uiScale", 100)
	store:set("uiState.fontScale", 1)
	store:set("uiState.minimized", false)
	store:set("uiState.pill", false)

	store:set("uiState.infoScale", 100)
	store:set("uiState.savedInfo", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
	store:set("uiState.savedInfoSize", { xs = 0, xo = 320, ys = 0, yo = 470 })

	store:set("uiState.savedMain", { xs = 0.5, xo = 0, ys = 0.5, yo = 0 })
	self.pillPosition = UDim2.new(0.5, 0, 0.18, 0)

	Shell.applySize(self)
	Shell.applyFontScale(self)
	if self.onReset ~= nil then
		pcall(self.onReset)
	end
	Shell.toast(self, "界面已复位", "success")
end

function Shell.bindStatus(self)
	local scheduler = self.scheduler
	local metrics = self.services.metrics

	Shell.addUiTick(self, function()

		if self.cover ~= nil and self.cover.Visible == true then
			local since = if self.morphAt ~= nil and self.morphAt > 0 then os.clock() - self.morphAt else 999
			if since > 2 then
				self.cover.Visible = false
				self.cover.BackgroundTransparency = 1
				self.morphAt = 0
				warn("[MKUltraHUB][ui] 形态切换遮罩卡住，已强制清除")
			end
		end

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

	kit:track(holder.MouseButton1Click:Connect(close))

	return { destroy = close }
end

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

		Active = false,
	}, self.screen)

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

		timers = context.timers,
		holder = nil,
		layout = nil,
		sequence = 0,
		live = {},

		byKey = {},
	}, Toast)
	return self
end

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

	local candidates = {
		{ x = main.x + main.w + gap, y = main.y },
		{ x = main.x - gap - panelWidth, y = main.y },
		{ x = main.x, y = main.y + main.h + gap },
		{ x = main.x, y = main.y - gap - panelHeight },
	}

	local bestX, bestY, bestScore = 0, 0, math.huge
	for index, candidate in ipairs(candidates) do
		local x = clampX(candidate.x)
		local y = clampY(candidate.y)
		local overlap = PanelPlacement.overlap(rectAt(x, y), main)
		local pushed = math.abs(x - candidate.x) + math.abs(y - candidate.y)

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

local Format = require("core/Format")
local PanelPlacement = require("core/PanelPlacement")
local PlayerStats = require("game/PlayerStats")

local InfoWindow = {}
InfoWindow.__index = InfoWindow

local WIDTH = 320
local HEIGHT = 470
local MINIMIZED_HEIGHT = 36

local MIN_WIDTH = 240
local MAX_WIDTH = 1200
local MIN_HEIGHT = 160
local MAX_HEIGHT = 1200

local REFRESH_SECONDS = 0.3

local DRAG_OVER = 48

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

		shellMode = "window",
		lastRefresh = 0,

		animSeq = 0,
	}, InfoWindow)
	return self
end

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

function InfoWindow.applyScale(self)
	if self.frame == nil or self.scale == nil then
		return
	end
	local factor = (tonumber(self.store:get("uiState.infoScale")) or 100) / 100
	self.scale.Scale = factor
	InfoWindow.clampOnScreen(self, false)
end

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

	local dragging = false
	local startInput = nil
	local startPosition = nil

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

	local timers = self.shell.timers
	if timers ~= nil then
		timers:every(os.clock(), REFRESH_SECONDS, function()
			if self.visible then
				InfoWindow.refresh(self)
			end
		end)
	end

	self.timers = timers

	kit:track(self.store:subscribe("uiState.infoHideWithShell", function()
		InfoWindow.applyVisibility(self)
	end))

	kit:track(self.store:subscribe("uiState.infoScale", function()
		InfoWindow.applyScale(self)
	end))
	kit:track(self.store:subscribe("uiState.savedInfoSize", function()
		InfoWindow.loadBaseSize(self)
		InfoWindow.applyBaseSize(self)
		InfoWindow.clampOnScreen(self, false)
	end))

	if self.visible then
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
		InfoWindow.applyVisibility(self)
		InfoWindow.animateIn(self)
	end
	return frame
end

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

function InfoWindow.overRect(self, x, y): boolean
	local frame = self.frame
	if frame == nil or frame.Visible ~= true then
		return false
	end

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

function InfoWindow.place(self)
	local screen = usableScreen(self)
	if screen == nil then

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

		panel = { w = self.baseWidth * factor, h = unscaledHeight * factor },
		main = mainRect,
		preferred = preferred,
	})

	self.frame.Position = UDim2.fromOffset(result.x, result.y)
	self.scale.Scale = factor

	self.placed = {
		x = result.x,
		y = result.y,
		w = self.baseWidth * factor,
		h = unscaledHeight * factor,
	}
	return result
end

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

		InfoWindow.refresh(self)
		return
	end

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

	return Vector2.new(position.X + size.X / 2, position.Y + size.Y / 2)
end

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

	if self.anim == "in" then
		return
	end
	self.anim = "in"
	self.animSeq = (self.animSeq or 0) + 1
	local seq = self.animSeq
	local merge = InfoWindow.mergeTarget(self)
	local height = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight

	if merge == nil then

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

		self.frame.AnchorPoint = Vector2.new(0, 0)
		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)
	end)
end

function InfoWindow.animateOut(self)
	if self.frame == nil or self.scale == nil or self.frame.Visible ~= true then

		InfoWindow.applyVisibility(self)
		return
	end

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

	local absolute = self.frame.AbsolutePosition
	local rendered = self.frame.AbsoluteSize
	self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.frame.Position = UDim2.fromOffset(absolute.X + rendered.X / 2, absolute.Y + rendered.Y / 2)

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

		InfoWindow.applyBaseSize(self)
		InfoWindow.place(self)

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

function InfoWindow.toggleMinimized(self)
	if self.frame == nil then
		return
	end
	self.minimized = not self.minimized
	local target = if self.minimized then MINIMIZED_HEIGHT else self.baseHeight

	if self.minimizeButton ~= nil then
		self.minimizeButton.Text = if self.minimized then "+" else "—"
	end

	local factor = (tonumber(self.store:get("uiState.infoScale")) or 100) / 100

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

	self.kit:tween(self.frame, 0.18, { Size = UDim2.fromOffset(self.baseWidth, target) },
		Enum.EasingStyle.Quint)
end

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

	if metrics ~= nil and metrics.rebirthStats ~= nil then

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

	local refreshMachines

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

			kit.store:set("machine.nameFilter", "")
			kit.store:set("machine.indexFilter", 0)
			refreshMachines(true)
		end,
	})

	local nameDropdown
	local indexDropdown

	local function refreshMachinesImpl(resetSelection)
		if nameDropdown == nil or indexDropdown == nil or machineService == nil then
			return
		end

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

	kit:toggle(machines, {
		label = "器械优先（战斗中也不让位）",
		path = "machine.overridesCombat",
		hint = "默认关闭：打 Boss / 杀戮时会自动让位；打开后器械不再被抢占",
	})

	refreshMachines(false)

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

			if kit.store:get("tp.loop") == true or kit.store:get("tp.autoMK") == true then
				kit.store:set("tp.loop", false)
				kit.store:set("tp.autoMK", false)
				shell:toast("已关闭循环传送", "warn")
			end
			local entry = Teleports.byIndex(kit.store:get("tp.loopIdx"))
			if entry == nil then
				shell:toast("还没有选传送点", "warn")
				return
			end
			if teleport ~= nil then
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

			kit.store:set("tp.loopIdx", index)
			kit.store:set("tp.loop", false)
			kit.store:set("tp.autoMK", false)
			if teleport ~= nil then
				teleport:goTo(entry.name)
			end
		end))
	end

	kit:note(grid, "点一下就传送过去（会自动关掉循环传送）")

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

	kit:slider(extras, {
		label = "双工具切换间隔（秒）",
		path = "kill.dualInterval",
		min = 0.1,
		max = 3,
		default = 0.15,
		commitOnly = true,
		hint = "每个半程持握工具的时长；两半相同，越小切换越快",
	})

	kit:note(extras, "优先级：打 Boss > 全图杀戮 > 单独击杀 / 肌肉之王 > 器械；高优先级运行时会自动让位")

	kit:section(page, "贴身方式")
	local approach = kit:card(page)

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

	kit:toggle(approach, {
		label = "贴脸直写 0.025 秒（位置+朝向）",
		path = "kill.directPin",
		hint = "关闭后只用每帧的保持修正；打不到人时可以先关掉试试",
	})

	kit:section(page, "单独击杀")
	local single = kit:card(page)
	kit:toggle(single, { label = "启用单独击杀", path = "kill.single" })

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

	kit:textInput(friends, {
		label = "好友名字",
		path = "kill.friendNames",
		default = "",
		placeholder = "用逗号或空格分隔，例如：小明,Tom",
		hint = "「不打好友」打开后，这些玩家不会被攻击",
		onChange = function()
			if combat ~= nil then
				combat:refreshFriends()
			end
		end,
	})

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

	shell:addUiTick(function()
		if combat == nil then
			return
		end
		local status = combat:friendStatus()
		if status.loaded then
			friendLabel.Text = string.format("名单状态：已加载 %d 个好友", status.count)
		else

			friendLabel.Text = "名单状态：未加载（「不打好友」暂不生效，会攻击所有人）"
		end
	end)

	kit:note(friends, "名字列表由本脚本直接读取；外部好友脚本（MK_HUB_FRIEND_WL）提供的名单会合并进来")

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

	for index, entry in ipairs(BossInfo.events()) do
		kit:toggle(eventCard, {
			label = string.format("%d. %s", index, entry.label),
			path = "boss.event." .. entry.key,
		})
	end
	kit:note(eventCard, "按顺序击杀：打完一个自动飞下一个；关掉的会被跳过")

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

		local questionButton
		questionButton = slotButton("?", "White", function()
			local entries = kit.store:get("petPreset." .. preset.key)
			local lines = {}
			if type(entries) ~= "table" or #entries == 0 then

				lines = { if entries == nil then "尚未保存过这个预设" else "这个预设已被清除" }
			else
				for _, entry in ipairs(entries) do
					table.insert(lines, string.format("%s × %d", entry.name, entry.count or 1))
				end
			end

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

				toStore = function(display)
					if display == "—" then
						return ""
					end
					local name = crystals:nameForLabel(tostring(display))
					if name ~= "" and name ~= tostring(display) then
						return name
					end

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

	kit:note(crystalCard, "下面勾选的是「要卖掉」的宠物；没勾的都会保留（按水晶分别记住）")

	local sellList = kit:instance("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = kit:nextOrder(crystalCard),
	}, crystalCard)
	kit:list(sellList, 2)

	local rows: { [string]: { frame: any, box: any, mark: any, name: string } } = {}
	local rowOrder = 0
	local builtFor = nil

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

local Page = {}

Page.id = "set"
Page.label = "设置"

local REJOIN_MODES = {
	{ display = "回原服务器", value = "same" },
	{ display = "人多的服务器", value = "crowded" },
	{ display = "私服", value = "private" },
	{ display = "人少的服务器", value = "sparse" },

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

	kit:toggle(control, {
		label = "启用功能存档",
		path = "cfg.saveEnabled",
		hint = "关闭后本次运行不再写入任何配置文件；已保存的配置仍然照常读取",
	})

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

	shell.syncSliders = function()
		local low, high = shell:pctRange()
		widthSlider.setRange(low, high)
		heightSlider.setRange(low, high)
		widthSlider.set(kit.store:get("uiState.widthPct"))
		heightSlider.set(kit.store:get("uiState.heightPct"))
	end

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

	kit:note(rejoin, "「目标玩家所在服务器」对手动 / 定时重进生效")
	kit:textInput(rejoin, {
		label = "私服 code",
		path = "rejoin.privId",
		default = "",
		placeholder = "链接或 code",
	})

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

	local Persist = services.persist

	local section = kit:section(page, "配置存档")
	local slots = kit:card(page)

	local slotRow
	local slotNote
	local slotButtons

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

					slotNote.Text = "功能存档已禁用：本次会话不写入任何配置（读取照常）"
					slotNote.Visible = true
				end
			end
			return
		end

		if slotNote ~= nil then
			slotNote.Text = "存档功能不可用：当前执行器没有文件读写接口"
			slotNote.Visible = true
		end
	end

	if Persist == nil then

		slotNote = kit:note(slots, "存档功能不可用：当前执行器没有文件读写接口")
	else
		local names = {}

		local slotDropdown

		local function currentSlot()
			local display = slotDropdown.get() or "1."
			local index = tonumber(string.match(display, "^%d+")) or 1
			return math.clamp(index, 1, Persist.SLOT_COUNT)
		end

		local function refreshSlots()

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

	kit:track(kit.store:subscribe("cfg.saveEnabled", function()
		applySaveGate()
	end))
	applySaveGate()
end

return Page
end

__modules["ui/Pages/Theme"] = function()
	local require = __require

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

	local function render(active, initial)
		for _, choice in ipairs(CHOICES) do
			local button = buttons[choice.key]
			if button ~= nil then
				local selected = choice.key == active
				local base = if selected then kit:color("Green") else kit:color("White")
				local textColor = if selected then kit:color("White") else kit:color("TextPrimary")

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
	version = "V1013",
}

Main.PLUGIN_ID = "__MKUltraHUB_V1007__"
Main.STALE_GUI_NAMES = { "MK_V1000", "MK_V1000_INFO", "MK_V1007", "MK_V1007_INFO", "MKUltraHUB" }

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

Main.SAVE_POLL_SECONDS = 1
Main.METRICS_SECONDS = 5

Main.GC_SECONDS = 120

Main.LOG_THROTTLE_SECONDS = 5
Main.session = nil

Main._runtime = nil
Main._character = nil

function Main.start()
	if Main.session ~= nil then
		return Main.session
	end

	Main.cleanupPrevious()

	local toastRef = nil

	local pendingToasts = {}

	local function notify(source)
		return function(message, kind, duration)
			local text = string.format("[%s] %s", source, tostring(message))
			if kind == "warn" or kind == "error" then
				warn("[MKUltraHUB] " .. text)
			else
				print("[MKUltraHUB] " .. text)
			end

			if toastRef == nil then

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

	local arbiter = Arbiter.new()
	local lastArbiterReason = nil
	arbiter.onChange = function(flag, up, by)
		if not up then
			return
		end

		local _, reason = Arbiter.capOf(arbiter:state())
		if reason ~= lastArbiterReason then
			lastArbiterReason = reason
			warn(string.format("[MKUltraHUB][arbiter] %s 已接管（%s），锻炼降深至%s",
				by or flag, reason or flag, Arbiter.LABELS[Arbiter.Depth.BODY]))
		end
	end

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

	Main._runtime = runtime

	local player = Players.LocalPlayer

	if player == nil then
		warn("[MKUltraHUB] 本地玩家尚未就绪：界面与角色相关功能本次加载被跳过，请重新执行脚本")

		task.delay(2, function()
			if Players.LocalPlayer == nil or Main.session ~= nil then
				return
			end

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

	local function bossEngaged()
		if boss == nil then
			return false
		end
		return Boss.stats(boss).engaged == true
	end

	local function bossBlocked()
		if boss == nil or store:get("boss.auto") ~= true then
			return false
		end
		return bossEngaged() or Boss.chestPending(boss)
	end
	local rebirth = nil
	local teleportRef = nil

	local function motionClaim(job: string): (boolean, string?)
		return runtime.scheduler:claim(job)
	end

	local sessionStart = os.clock()
	local metrics = GameMetrics.install({ scheduler = runtime.scheduler })

	local perf = Perf.install({ store = store, scheduler = runtime.scheduler })

	local crystals = Crystals.install({
		store = store,
		scheduler = runtime.scheduler,
		timers = runtime.timers,

		metrics = metrics,
		notify = notify("crystal"),
	})

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

		rejoin = rejoin,
	})

	if player ~= nil then
		character = Character.new(player)

		Main._character = character
		motion = Motion.new({
			character = character,
			store = store,
			claim = motionClaim,
			onLost = function(attempt)
				warn(string.format("[MKUltraHUB][motion] pulled back, retry %d", attempt))
			end,
			onGiveUp = function(attempt)

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

			machinePhase = function()
				if machine == nil then
					return nil
				end
				return machine:stats().phase
			end,
			bodyOwner = function()
				return runtime.scheduler:bodyOwner()
			end,
			isBossEngaged = function()
				return bossEngaged()
			end,
			isBossBlocked = function()
				return bossBlocked()
			end,
		})
		teleportRef = teleport

		runtime.timers:every(os.clock(), 3, function()
			motion:markSafe()
		end)

		runtime.timers:every(os.clock(), 1, function()
			motion:watchDrift(os.clock())
		end)

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

			if teleport ~= nil then
				pcall(function()
					teleport:cancel()
				end)
			end
			local safe = motion:safePosition()
			if safe == nil then

				safe = Vector3.new(5505.53, 96.32, 5893.50)
			end
			warn("[MKUltraHUB][motion] 掉出地图，已送回安全点")
			teleport:walk(safe + Vector3.new(0, 5, 0), { mode = "tp", hold = false })
		end)

		runtime:connectPreRender(function(now)
			motion:tick(now)
		end)

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

			rejoin = rejoin,
			persist = Persist,

			size = function()
				return size
			end,

			machineSeated = function()
				return machine ~= nil and Machine.isSeated(machine)
			end,
			notify = notify("boss"),
		})

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

			teleport = teleport,

			machineSeated = function()
				return machine ~= nil and Machine.isSeated(machine)
			end,
			net = net,
			arbiter = arbiter,
			pets = pets,
			isBossAlive = bossAlive,

			isBossEngaged = bossEngaged,

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

			teleport = teleport,
			isCombatBusy = function()
				return combat ~= nil and Combat.engaged(combat)
			end,

			isDamageNeeded = function()
				return Combat.maintainDamageHold(combat)
			end,
			isBossAlive = bossEngaged,

			isBossBlocked = bossBlocked,
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

		pets = pets,
		arbiter = arbiter,

		isCombatBusy = function()
			return combat ~= nil and Combat.engaged(combat)
		end,

		isBossAlive = bossEngaged,

		isBossBlocked = bossBlocked,
		isMachineBusy = function()
			if machine == nil then
				return false
			end
			local phase = machine:stats().phase
			return phase == "mounting" or phase == "mounted"
		end,
		notify = notify("train"),
	})

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

	if type(collectgarbage) == "function" then
		runtime.timers:every(os.clock(), Main.GC_SECONDS, function()
			pcall(collectgarbage)
		end)
	end

	local petMetrics = PetMetrics.new()
	runtime.timers:every(os.clock(), Main.METRICS_SECONDS, function()
		PetMetrics.scan(petMetrics)
	end)

	local kit = nil
	local shell = nil
	if player ~= nil then
		kit = Kit.new({
			store = store,
			roles = Theme.roles(store:get("uiState.theme") or "light"),

			timers = runtime.timers,
		})
		shell = Shell.new({
			store = store,
			kit = kit,
			version = Main.version,
			notify = notify("ui"),
			timers = runtime.timers,

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

				persist = Persist,
				uptime = function()
					return os.clock() - sessionStart
				end,
			},
			onClose = function()
				Main.stop()
			end,
		})

		Shell.registerPage(shell, TrainPage)
		Shell.registerPage(shell, TeleportPage)
		Shell.registerPage(shell, RebirthPage)
		Shell.registerPage(shell, KillPage)
		Shell.registerPage(shell, PetsPage)
		Shell.registerPage(shell, BossPage)
		Shell.registerPage(shell, ThemePage)
		Shell.registerPage(shell, SettingsPage)
		Shell.build(shell)

		shell.onVisualState = function(state)
			if infoWindow == nil then
				return
			end

			InfoWindow.setShellMode(infoWindow, state.mode)
		end

		shell.onReset = function()
			if infoWindow == nil then
				return
			end
			InfoWindow.resetPlacement(infoWindow)
		end

		shell.onGeometrySettled = function()
			if infoWindow == nil then
				return
			end
			InfoWindow.place(infoWindow)
		end

		shell.isOverlayAt = function(x, y)
			if infoWindow == nil or InfoWindow.overRect == nil then
				return false
			end
			return InfoWindow.overRect(infoWindow, x, y)
		end

		rejoin.onPending = function(reason, cancel, confirmNow)
			Shell.confirm(
				shell,
				"即将重进",
				string.format("原因：%s\n\n取消可留在当前服务器；确认则立即重进。", reason),
				function()
					confirmNow()
				end,

				cancel
			)
		end

		toastRef = Toast.new({
			screen = shell:screenGui(),
			kit = kit,
			store = store,
			timers = runtime.timers,
		})
		shell.onToast = function(text, kind, duration)
			Toast.show(toastRef, text, kind, duration)
		end

		kit.onToast = function(text, kind, duration)
			Toast.show(toastRef, text, kind, duration)
		end

		if #pendingToasts > 0 then
			local buffered = pendingToasts
			pendingToasts = {}
			for index, entry in ipairs(buffered) do

				runtime.timers:after(os.clock(), (index - 1) * 0.12, function()
					if toastRef ~= nil then
						Toast.show(toastRef, entry.text, entry.kind, entry.duration)
					end
				end)
			end
		end

		infoWindow = InfoWindow.new({
			store = store,
			kit = kit,
			shell = shell,
			services = shell.services,
		})
		InfoWindow.build(infoWindow)

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

		local state = Shell.visualState(shell)
		InfoWindow.setShellMode(infoWindow, state.mode)

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

		if combat ~= nil then
			combat:restoreAll()
		end

		if size ~= nil then
			size:restore()
		end

		if perf ~= nil and perf.disable ~= nil then
			pcall(function()
				perf:disable()
			end)
		end

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

		local handle = environmentRead(Main.PLUGIN_ID)
		if type(handle) == "table" and handle.version == Main.version then
			environmentWrite(Main.PLUGIN_ID, nil)
		end

		Main._runtime = nil
		Main._character = nil
		Main.session = nil
	end

	Main.session = session

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

function Main.unfreeze()
	local session = Main.session
	if session ~= nil then
		session.unfreeze()
	end
end

local booted, bootError = pcall(Main.start)
if not booted then
	warn("[MKUltraHUB] 启动失败：" .. tostring(bootError))

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
