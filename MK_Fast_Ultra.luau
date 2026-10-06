--!nonstrict
-- 肌肉之王自动化 v39
local PLUGIN_ID = "__MK_AUTO_V39__"
local VERSION = 3900
local CONFIG_FILE = "mk_auto_v39.json"
-- ★ 旧版本清理 + 配置继承
local OLD_PLUGIN_IDS = {"__MK_AUTO_V38__", "__MK_AUTO_V37__", "__MK_AUTO_V36__", "__MK_AUTO_V35__"}
local OLD_CONFIGS    = {"mk_auto_v38.json", "mk_auto_v37.json", "mk_auto_v36.json", "mk_auto_v35.json"}
for _, oldId in ipairs(OLD_PLUGIN_IDS) do
    local old = _G[oldId]
    if old then
        if type(old.cleanup) == "function" then pcall(old.cleanup) end
        _G[oldId] = nil
    end
end
if _G[PLUGIN_ID] then
    if _G[PLUGIN_ID].version and _G[PLUGIN_ID].version >= VERSION then return end
    if type(_G[PLUGIN_ID].cleanup) == "function" then pcall(_G[PLUGIN_ID].cleanup) end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")

do
    local t = 0
    while not game:IsLoaded() and t < 60 do t = t + 1; task.wait(0.5) end
    if not Players.LocalPlayer then Players.PlayerAdded:Wait() end
end
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui", 60)

local UD2 = UDim2.new
local UDO = UDim2.fromOffset
local C3 = Color3.fromRGB
local V2 = Vector2.new
local V3 = Vector3.new
local CN = CFrame.new
local ENUM = Enum
local HB = RunService.Heartbeat
local RS = RunService.RenderStepped
local UIS_IC = UserInputService.InputChanged
local UIS_IB = UserInputService.InputBegan
local UIS_IE = UserInputService.InputEnded
local GetPlayers = Players.GetPlayers

local S = {
    version = VERSION, destroyed = false,
    threads = {}, conns = {}, ui = {},
    Info = { rows = {}, frames = {} },
    UIState = { pillPos = nil, confirmOpen = false },
    pingHistory = {}, activeNotifies = {},
    friendWL = { ids = {}, loaded = false, refreshing = false, lastRefresh = 0, lastAttempt = 0 },
    repCache = { pet = 0, ult = 0, x2 = false, speedMul = 1, lastRefresh = 0, lastPassCheck = 0 },
    cache = { char = nil, hum = nil, hrp = nil },
    antiLag = { enabled = false, rescanAt = 0, particles = {}, shadows = {}, sounds = {}, lighting = nil, postEffects = {}, atmospheres = {}, decals = {}, textures = {}, materials = {} },
    renderCull = { hidden = {}, rescanAt = 0 },
    petHider = { own = {}, all = {}, machines = {}, rescanAt = 0 },
    texRem = { enabled = false, rescanAt = 0, saved = {}, seen = {} },
    hiddenUIs = {}, taskChain = {},
    gravityLock = { active = false },
    machineState = { enabled = false, mode = "dumbbell", targetSeat = nil, targetName = "", lastTry = 0, using = false, failCount = 0, triedAt = 0, gymFilter = "", machineFilter = "", indexFilter = 0 },
    petPreset = { train = {}, rebirth = {}, kill = {}, boss = {}, autoSwitch = false, activeType = nil },
    rebirthTarget = 0, teleportLoopEnabled = false, teleportLoopIndex = 1, teleportLoopLastAt = 0,
    scriptPaused = false, pausedSnapshot = nil, emergencyRejoin = false,
    rejoinPending = false, rejoinPendingAt = 0,
    machineTeleport = { enabled = false, lastAt = 0 },
    antiAfkInterval = 900, lastAntiAfk = 0,
    autoTrain = false, fastTrain = false, fastRate = 20,
    toolDumbbell = false, toolPushups = false, toolHandstands = false, toolSitups = false,
    lastToolCheck = 0, toolCooldown = false, _missingSince = 0, _lastSuicide = 0, _suicideCount = 0,
    autoTeleport = false, lastTeleportAt = 0, lastCameraFix = 0,
    autoRebirth = false, rebirthRate = 2, lastRebirthAt = 0,
    rebirthPausedReasons = {}, rebirthSavedBySystem = false,
    killEnabled = false, killThreshold = 5, killGoodOnly = false, killBadOnly = false,
    killScanAt = 0, killTarget = nil, killLastAttack = 0, killSavedState = nil, toolOwnedByKill = false,
    friendWhitelist = false, autoKingKill = false,
    kingKillTarget = nil, kingKillLastAttack = 0, kingKillActive = false, lastKingCheck = 0,
    dualEnabled = true, dualLastSwitch = 0, dualCurrentMode = "punch",
    adaptiveEnabled = false, adaptiveThreshold = 30, adaptiveStep = 100, adaptiveStableCount = 0, lastAdaptiveAt = 0,
    adaptiveMaxRate = 5000,
    antiLagEnabled = false, renderCullEnabled = false, renderCullDist = 500,
    hideOwnPets = false, hideAllPets = false, hideMachines = false,
    textureRemoverEnabled = false, hideUIEnabled = false,
    infoWindowEnabled = false, infoLastRefresh = 0, formatEnabled = true,
    uiBgOpacity = 1.0, uiPageOpacity = 1.0, infoBgOpacity = 1.0, infoScale = 100,
    autoPetBuy = false, selectedPet = "", autoWheel = false,
    autoBoss = false, bossHeight = 40, bossHeightMode = "auto",
    autoPackRebirth = false,
    autoEatEgg = false, eatEggBatch = 10, giftAmount = 0, selectedEggTarget = "",
    autoChest = true, chestDelay = 3, chestHoldTime = 2,
    bossWasAlive = false, bossKilledAt = 0, bossDeathPos = nil, chestTaskActive = false,
    autoRejoinEnabled = false, rejoinCondition = "any",
    rejoinEnableMem = true, rejoinEnableFps = true, rejoinEnablePing = true,
    rejoinServerMode = "same", rejoinPrivateServerId = "",
    rejoinMemThreshold = 4000, rejoinFpsThreshold = 5, rejoinPingThreshold = 800,
    rejoinCheckAt = 0, _rejoinTriggered = false,
    savedMainPos = nil, savedInfoPos = nil, savedInfoSize = nil,
    uiWidthPct = 40, uiHeightPct = 46, originalGravity = Workspace.Gravity,
    muscleEventRef = nil, rebirthEventRef = nil, lastRebirthScan = 0,
    trainAccum = 0, time = 0, fpsWinTime = 0, fpsWinFrames = 0, avgFps = 60,
    lastDegradeAt = 0, degradeLevel = 0, lastAFKClick = 0, lastSaveAt = 0, lastSweepAt = 0,
    sessionStartStrength = nil, strengthCheckAt = 0, lastStrengthSnapshot = 0, strengthPerSec = 0,
    ping = 0, lastPingCheck = 0, friendCount = 0, memMb = 0, _lastBossAlive = false,
    startAt = tick(), lastGcAt = 0, lastMemCheckAt = 0,
    memBaseline = 0, memWarnCount = 0, sessionUptime = 0, peakMem = 0, _didDeepClean = false,
    portalCache = nil, portalCacheAt = 0, bossHoverConn = nil, bossCurrent = "Boss1",
    bossAliveCache = false, bossAliveCacheAt = 0, fontScale = 1.0, currentPrivateServerId = "",
    _rebirthEventWarned = false, _muscleEventWarned = false,
    _jumpCdUntil = 0, _machineOccupantTarget = nil, _machineOccupantSince = nil,
    _bossActive = false, _bossSavedDual = nil, _bossSavedMachine = nil,
    _lastRebCheck = 0, _lastRebVal = 0, rebirthPerSec = 0,
    _cfPriority = 0, _cfTarget = nil, _cfSetAt = 0,
    -- ★ 新增
    _origWalkSpeed = 16, _origJumpPower = 50, _origJumpHeight = 7.2,
    _enlargedTargets = {},
    _lastKillEnlarge = 0,
    theme = {
        Bg=C3(16,18,24), Bg2=C3(22,25,33), Surface=C3(30,34,44), SurfaceAlt=C3(40,46,58),
        Border=C3(68,76,94), Accent=C3(100,170,255), Accent2=C3(60,120,220),
        Success=C3(80,220,140), Warning=C3(255,190,80), Danger=C3(255,90,90),
        Text=C3(245,248,255), TextDim=C3(185,192,210), TextMuted=C3(135,142,160), OnAccent=C3(255,255,255),
    },
}

S.MACHINE_TRANSLATE = {
    ["Squat Rack"]="深蹲架", ["Bench Press"]="卧推台", ["Deadlift"]="硬拉台",
    ["Pullups"]="引体向上", ["Boulder Throw"]="巨石投掷",
    ["Frost Squat"]="冰霜深蹲", ["Frost Press"]="冰霜卧推", ["Frost Lift"]="冰霜硬拉",
    ["Frost Treadmill"]="冰霜跑步机",
    ["Mythical Pullup"]="神话引体", ["Mythical Press"]="神话卧推",
    ["Mythical Throw"]="神话投掷", ["Mythical Treadmill"]="神话跑步机",
    ["Legends Press"]="传奇卧推", ["Legends Squat"]="传奇深蹲",
    ["Legends Pullup"]="传奇引体", ["Legends Throw"]="传奇投掷", ["Legends Lift"]="传奇硬拉",
    ["Eternal Press"]="永恒卧推", ["Eternal Treadmill"]="永恒跑步机",
    ["Jungle Squat"]="丛林深蹲", ["Jungle Bench"]="丛林卧推",
    ["Jungle Bar Lift"]="丛林硬拉", ["Jungle Boulder"]="丛林投掷", ["Jungle Treadmill"]="丛林跑步机",
    ["Industrial Bench"]="工业卧推", ["Industrial Squat"]="工业深蹲",
    ["Industrial Bar Lift"]="工业硬拉", ["Industrial Boulder"]="工业投掷", ["Industrial Treadmill"]="工业跑步机",
    ["Overcharged Bench"]="超载卧推", ["Overcharged Squat"]="超载深蹲",
    ["Overcharged Bar Lift"]="超载硬拉", ["Overcharged Boulder"]="超载投掷", ["Overcharged Treadmill"]="超载跑步机",
    ["Muscle King Lift"]="王·硬拉", ["Muscle King Squat"]="王·深蹲",
    ["Muscle King Bench"]="王·卧推", ["King Boulder"]="王·巨石",
    ["Punching Rock"]="拳击石", ["Tiny Rock"]="微岩石", ["Frozen Rock"]="冰冻岩",
    ["Rock Of Legends"]="传奇岩", ["Inferno Rock"]="炼狱岩",
    ["Industrial Rock"]="工业岩", ["Overcharged Rock"]="超载岩",
    ["Ancient Jungle Rock"]="远古丛林岩", ["Muscle King Mountain"]="王·巨山",
}
S.GYM_TRANSLATE = {
    ["冰霜健身房"]="冰霜", ["神话健身房"]="神话", ["永恒健身房"]="永恒",
    ["传奇健身房"]="传奇", ["肌肉之王健身房"]="王·健身房", ["丛林健身房"]="丛林",
    ["工业健身房"]="工业", ["超载健身房"]="超载", ["海滩"]="海滩", ["未知"]="未知",
}
S.PET_TRANSLATE = {
    ["Omega Overlord"]="终极霸主", ["Swift Samurai"]="迅捷武士",
    ["Powercore Hound"]="能量核心猎犬", ["Titanium Hydra"]="钛合金九头蛇",
    ["Tribal Overlord"]="部落霸主", ["Inferno Unicorn"]="炼狱独角兽",
    ["Common Boss Pet"]="普通Boss宠", ["Rare Boss Pet"]="稀有Boss宠",
    ["Epic Boss Pet"]="史诗Boss宠", ["Rainbow Boss Pet"]="彩虹Boss宠",
    ["Legendary Boss Pet"]="传奇Boss宠", ["Mythic Boss Pet"]="神话Boss宠",
    ["Inferno Drake"]="炼狱龙", ["Core Pup"]="核心幼犬", ["Volt Talon"]="伏特利爪",
    ["Reactor Beast"]="反应堆兽", ["Apex Overlord"]="顶级霸主", ["Moonlight"]="月光兽",
    ["Titan Reactor"]="泰坦反应堆", ["Shard Dragon"]="碎片龙",
    ["Plasma Ravager"]="等离子掠夺者", ["Neon Guardian"]="霓虹守护者",
    ["Nova Phoenix"]="新星凤凰", ["Surge Tiger"]="涌动虎", ["Volt Wolf"]="伏特狼",
    ["Prismcore Hound"]="棱镜核心犬", ["Blazestone"]="炽热之石",
    ["Inferno"]="炼狱", ["Astral Electro"]="星界电光", ["Dark Electro"]="暗黑电光",
    ["Lightning"]="闪电", ["Supernova"]="超新星", ["Grand Supernova"]="大超新星",
    ["Power Lightning"]="能量闪电", ["Ultra Inferno"]="终极炼狱",
    ["Enchanted Mirage"]="魔法幻影", ["Unstable Mirage"]="不稳定幻影",
    ["Azure Tundra"]="蔚蓝苔原", ["Purple Falcon"]="紫色猎鹰", ["Red Dragon"]="红龙",
    ["Blue Firecaster"]="蓝释火者", ["Golden Pheonix"]="金凤凰",
    ["Dark Storm"]="暗黑风暴", ["Dark Lightning"]="暗黑闪电",
    ["Muscle King"]="肌肉之王", ["Eternal Megastrike"]="永恒巨型攻击",
    ["Entropic Blast"]="熵爆炸", ["Red Firecaster"]="红释火者",
    ["Infernal Dragon"]="炼狱龙", ["White Pegasus"]="白色飞马",
    ["Ultra Birdie"]="终极小鸟", ["Magic Butterfly"]="魔法蝴蝶",
    ["Green Firecaster"]="绿释火者", ["White Pheonix"]="白凤凰",
    ["Frostwave Legends Penguin"]="冰波传奇企鹅", ["Phantom Genesis Dragon"]="幻影创世龙",
    ["Dark Legends Manticore"]="暗黑传奇蝎尾怪", ["Ultimate Supernova Pegasus"]="终极超新星飞马",
    ["Aether Spirit Bunny"]="以太仙灵小兔", ["Cybernetic Showdown Dragon"]="赛博对峙龙",
    ["Eternal Strike Leviathan"]="永恒打击利维坦", ["Lightning Strike Phantom"]="闪电打击幻影",
    ["Darkstar Hunter"]="暗星猎人", ["Alien Girl"]="外星女孩",
    ["Green-Fly"]="绿蝇", ["Ice Ice"]="冰冰", ["Slitherman"]="蛇人", ["Hank"]="汉克",
    ["Gold Warrior"]="黄金勇士", ["Mask Of Gold"]="黄金面具", ["Mr. Serious"]="严肃先生",
    ["Smiley"]="笑脸", ["A. Gnatomy"]="昆虫学家", ["Sir Flame"]="火焰爵士",
    ["Sky Hawk"]="天鹰", ["Chops"]="排骨侠", ["Boy Wonder"]="神奇小子",
    ["Masked Marksman"]="面具射手", ["Cool Guy Larry"]="酷盖拉里",
    ["Screaming Bones"]="尖叫骨", ["Muscle Sensei"]="肌肉老师",
    ["Golden Viking"]="黄金维京", ["Red Kitty"]="红猫", ["Dark Vampy"]="暗黑吸血",
    ["Blue Bunny"]="蓝兔", ["Silver Dog"]="银狗", ["Purple Nova"]="紫新星",
    ["Electro"]="电光", ["Dark Golem"]="暗黑魔像", ["Green Butterfly"]="绿蝴蝶",
    ["Crimson Falcon"]="深红猎鹰", ["Yellow Butterfly"]="黄蝴蝶",
    ["Purple Dragon"]="紫龙", ["Blue Pheonix"]="蓝凤凰",
    ["Ultra Mirage"]="终极幻影", ["Orange Pegasus"]="橙飞马",
    ["Wind-Up Buddy"]="发条伙伴", ["Patchwork Teddy"]="拼布泰迪",
    ["Arcade Overlord"]="街机霸主", ["Toy Trooper"]="玩具士兵",
    ["Jack-in-the-Box"]="弹簧盒", ["Biohazard Ape"]="生化猿",
    ["Radio Rat"]="辐射鼠", ["Nuclear Hydra"]="核能九头蛇",
    ["Sludge Croc"]="污泥鳄", ["Toxic Hound"]="剧毒猎犬",
    ["Planet Bull"]="行星公牛", ["Orbital Hawk"]="轨道鹰",
    ["Eclipse Overlord"]="日蚀霸主", ["Nebula Lion"]="星云狮",
    ["Solar Cub"]="太阳幼兽", ["Solar Dragon"]="太阳龙",
    ["Voidling"]="虚空幼体", ["UFO Drone"]="UFO无人机",
    ["Cosmic Overlord"]="宇宙霸主", ["Ethereal Emperor"]="以太皇帝",
    ["Alien Buddy"]="外星伙伴", ["Galactic Guardian"]="银河守护者",
    ["Meteor Beast"]="陨石兽", ["Griffin"]="狮鹫",
}
S.translateMachine = function(n) return S.MACHINE_TRANSLATE[n] or n end
S.translateGym = function(n) return S.GYM_TRANSLATE[n] or n end
S.translatePet = function(n) return S.PET_TRANSLATE[n] or n end
S.bilingualPet = function(n)
    local cn = S.PET_TRANSLATE[n]; if cn then return cn.." ("..n..")" end; return n
end

S.TELEPORTS = {
    {name="大厅",pos=V3(-0.75,93.61,242.78)},{name="小岛",pos=V3(-32.14,11.51,1904.41)},
    {name="冰霜健身房",pos=V3(-2623.41,9.99,-409.34)},{name="神话健身房",pos=V3(2250.39,9.99,1072.77)},
    {name="永恒健身房",pos=V3(-6758.39,9.99,-1284.45)},{name="传奇健身房",pos=V3(4603.40,993.99,-3897.44)},
    {name="肌肉之王健身房",pos=V3(-8625.40,19.99,-5730.41)},{name="丛林健身房",pos=V3(-8685.01,8.99,2392.06)},
    {name="工业健身房",pos=V3(-5496.68,62.04,4927.74)},{name="超载健身房",pos=V3(-3045.30,168.41,4990.69)},
    {name="无转盘岛",pos=V3(1952.09,4,6179.98)},{name="熔岩争斗",pos=V3(4472.53,121.90,-8848.54)},
    {name="沙漠争斗",pos=V3(973.62,18.92,-7277.01)},{name="海滩争斗",pos=V3(-1880.89,18.87,-6137.75)},
}
S.TOOL_KW = {
    dumbbell={"barbell","dumbbell","weight","哑铃","杠铃"},
    pushups={"pushup","push up","push-up","俯卧撑"},
    handstands={"handstand","hand stand","hand-stand","倒立"},
    situps={"situp","sit up","sit-up","仰卧起坐"},
    punch={"punch","拳","fist","空手","拳头"},
}
S.BOSS_NAMES = {"Boss1","Boss2","Boss3","Boss4","Boss5","BossRainbow"}
S.CHEST_POS = V3(-12.6, 403, -1246.9)
S.CHEST_RADIUS = 30
S.OVERCHARGED_POS = V3(-3045.30, 165.41, 4990.69)
S.GYM_POSITIONS = {
    {name="冰霜健身房",pos=V3(-2623.41,6.99,-409.34)},{name="神话健身房",pos=V3(2250.39,6.99,1072.77)},
    {name="永恒健身房",pos=V3(-6758.39,6.99,-1284.45)},{name="传奇健身房",pos=V3(4603.40,990.99,-3897.44)},
    {name="肌肉之王健身房",pos=V3(-8625.40,16.99,-5730.41)},{name="丛林健身房",pos=V3(-8685.01,5.99,2392.06)},
    {name="工业健身房",pos=V3(-5496.68,59.04,4927.74)},{name="超载健身房",pos=V3(-3045.30,165.41,4990.69)},
    {name="海滩",pos=V3(-32.14,8.51,1904.41)},
}

S.create = function(cls, props, parent)
    local i = Instance.new(cls)
    if props then for k, v in pairs(props) do if k ~= "Parent" then i[k] = v end end end
    if parent then i.Parent = parent end
    return i
end
S.corner = function(p, r) return S.create("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p) end
S.stroke = function(p, c, t, tr)
    return S.create("UIStroke", { Color = c or S.theme.Border, Thickness = t or 1,
        Transparency = tr or 0, ApplyStrokeMode = ENUM.ApplyStrokeMode.Border }, p)
end
S.padding = function(p, t, b, l, r)
    return S.create("UIPadding", { PaddingTop = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0), PaddingLeft = UDim.new(0, l or 0),
        PaddingRight = UDim.new(0, r or 0) }, p)
end
S.listLayout = function(p, spacing, h)
    return S.create("UIListLayout", {
        Padding = UDim.new(0, spacing or 6),
        FillDirection = h and ENUM.FillDirection.Horizontal or ENUM.FillDirection.Vertical,
        SortOrder = ENUM.SortOrder.LayoutOrder }, p)
end
S.track = function(c) if c then table.insert(S.conns, c) end return c end

S.notify = function(text, duration)
    duration = duration or 3
    if S.destroyed or not S.ui.screen then return end
    local AN = S.activeNotifies
    for i = #AN, 1, -1 do if not AN[i] or not AN[i].Parent then table.remove(AN, i) end end
    if #AN >= 5 then local o = table.remove(AN, 1); if o then pcall(function() o:Destroy() end) end end
    local label = S.create("TextLabel", {
        AnchorPoint = V2(0.5, 0), Position = UD2(0.5, 0, 0.04, 0),
        Size = UDO(480, 46), BackgroundColor3 = S.theme.Surface, BorderSizePixel = 0,
        Font = ENUM.Font.GothamMedium, Text = text, TextColor3 = S.theme.Text,
        TextSize = 15, TextWrapped = true, ZIndex = 500,
    }, S.ui.screen)
    S.corner(label, 10); S.stroke(label, S.theme.Accent, 1.5, 0.3)
    table.insert(AN, label)
    task.delay(duration, function() pcall(function() label:Destroy() end) end)
end

S.serializePos = function(pos) if not pos then return nil end return {xs=pos.X.Scale,xo=pos.X.Offset,ys=pos.Y.Scale,yo=pos.Y.Offset} end
S.deserializePos = function(t, fb) if type(t)~="table" then return fb end return UD2(t.xs or 0,t.xo or 0,t.ys or 0,t.yo or 0) end
S.serializeSize = function(sz) if not sz then return nil end return {xo=sz.X.Offset,yo=sz.Y.Offset,xs=sz.X.Scale,ys=sz.Y.Scale} end
S.deserializeSize = function(t, fb) if type(t)~="table" then return fb end return UD2(t.xs or 0,t.xo or 0,t.ys or 0,t.yo or 0) end

S.formatNumber = function(n)
    local SUF = {"","K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc","Ud","Dd","Td","Qad","Qid","Sxd","Spd","Ocd","Nod","Vg"}
    n = tonumber(n) or 0
    if not S.formatEnabled then return tostring(math.floor(n)) end
    local neg = n < 0; n = math.abs(n)
    if n < 1000 then return (neg and "-" or "") .. string.format("%.0f", n) end
    local i = 1
    while n >= 1000 and i < #SUF do n = n/1000; i = i+1 end
    return (neg and "-" or "") .. string.format("%.3f%s", n, SUF[i])
end

S.stat = function(plr, name)
    if not plr then return 0 end
    local v = plr:FindFirstChild(name)
    if v and v:IsA("ValueBase") then return tonumber(v.Value) or 0 end
    local ls = plr:FindFirstChild("leaderstats")
    if ls then local s = ls:FindFirstChild(name); if s and s:IsA("ValueBase") then return tonumber(s.Value) or 0 end end
    return 0
end
S.myStrength = function() return S.stat(LP, "Strength") end
S.myDurability = function() return S.stat(LP, "Durability") end

S.refreshCache = function()
    local c = LP.Character
    local C = S.cache
    if c ~= C.char then
        C.char = c; C.hum = nil; C.hrp = nil
        S.releaseGravityLock()
        -- ★ 记录原始移动参数
        if c then
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum then
                S._origWalkSpeed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
            end
        end
    end
    if c then
        if not C.hum or not C.hum.Parent then C.hum = c:FindFirstChildOfClass("Humanoid") end
        if not C.hrp or not C.hrp.Parent then C.hrp = c:FindFirstChild("HumanoidRootPart") end
    end
end

S.getMuscleEvent = function()
    local c = S.muscleEventRef
    if c and c.Parent == LP then return c end
    local ev = LP:FindFirstChild("muscleEvent")
    if not ev then
        for _, v in ipairs(LP:GetChildren()) do
            if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name:lower():find("muscle") then ev = v; break end
        end
    end
    S.muscleEventRef = ev
    return ev
end

S.getRebirthEvent = function()
    local c = S.rebirthEventRef
    if c and c.Parent then return c end
    if tick() - S.lastRebirthScan < 3 then return nil end
    S.lastRebirthScan = tick()
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    if r then
        for _, ev in ipairs(r:GetChildren()) do
            if (ev:IsA("RemoteEvent") or ev:IsA("RemoteFunction")) and ev.Name:lower():find("rebirth") then
                S.rebirthEventRef = ev; return ev
            end
        end
    end
    for _, ev in ipairs(ReplicatedStorage:GetDescendants()) do
        if (ev:IsA("RemoteEvent") or ev:IsA("RemoteFunction")) and ev.Name:lower():find("rebirth") then
            S.rebirthEventRef = ev; return ev
        end
    end
    return nil
end

S.fireRebirth = function()
    if S.rebirthTarget > 0 then
        local cur = S.stat(LP, "Rebirths")
        if cur >= S.rebirthTarget then
            if S.autoRebirth then
                S.autoRebirth = false
                S.notify("已达目标重生 " .. S.rebirthTarget .. "，已关闭自动重生", 6)
                if S.ui.rebirthToggle then S.ui.rebirthToggle.set(false) end
            end
            return
        end
    end
    local ev = S.getRebirthEvent()
    if not ev then return end
    task.spawn(function()
        pcall(function()
            if ev:IsA("RemoteFunction") then ev:InvokeServer("rebirthRequest")
            else ev:FireServer("rebirthRequest") end
        end)
    end)
end

S.matchKw = function(n, list)
    n = n:lower()
    for i = 1, #list do if n:find(list[i]) then return true end end
    return false
end
S.isEquipped = function(list)
    local c = S.cache.char; if not c then return false end
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") and S.matchKw(t.Name, list) then return true end
    end
    return false
end
S.findTool = function(list)
    local c = S.cache.char
    if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and S.matchKw(t.Name, list) then return t end end end
    local bp = LP:FindFirstChild("Backpack")
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and S.matchKw(t.Name, list) then return t end end end
    return nil
end
S.tryEquip = function(list)
    if S.isEquipped(list) then return true end
    local hum = S.cache.hum; if not hum then return false end
    local bp = LP:FindFirstChild("Backpack"); if not bp then return false end
    for _, c in ipairs(bp:GetChildren()) do
        if c:IsA("Tool") and S.matchKw(c.Name, list) then
            pcall(function() hum:EquipTool(c) end); return true
        end
    end
    return false
end
S.toolExists = function(list) return S.isEquipped(list) or S.findTool(list) ~= nil end
S.suicide = function()
    local hum = S.cache.hum
    if hum and hum.Health > 0 then hum.Health = 0
    elseif S.cache.char then pcall(function() S.cache.char:BreakJoints() end) end
end

S.spawnThread = function(key, fn)
    if S.threads[key] then pcall(function() task.cancel(S.threads[key]) end) end
    S.threads[key] = task.spawn(fn)
    return S.threads[key]
end
S.cancelThread = function(key) if S.threads[key] then pcall(function() task.cancel(S.threads[key]) end); S.threads[key] = nil end end
S.cancelAllThreads = function() for k in pairs(S.threads) do S.cancelThread(k) end end

S.setCFrame = function(pos, priority)
    if (S._cfPriority or 0) > priority then return end
    S._cfPriority = priority
    S._cfTarget = pos
    S._cfSetAt = tick()
end

-- 反重力
S.setupGravityLock = function()
    local hrp = S.cache.hrp; if not hrp then return end
    S.releaseGravityLock()
    local bf = Instance.new("BodyForce"); bf.Name="_MK_AntiGrav"; bf.Force=V3(0, hrp.AssemblyMass * Workspace.Gravity, 0); bf.Parent=hrp
    local ao = Instance.new("AlignOrientation"); ao.Name="_MK_AlignOr"
    ao.Mode=ENUM.OrientationAlignmentMode.OneAttachment; ao.RigidityEnabled=true
    local at1 = Instance.new("Attachment", hrp); at1.Name="_MK_AlignAt1"; ao.Attachment0=at1; ao.Parent=hrp
    local ap = Instance.new("AlignPosition"); ap.Name="_MK_AlignPos"
    ap.Mode=ENUM.PositionAlignmentMode.OneAttachment; ap.RigidityEnabled=true
    ap.MaxForce=1e9; ap.Responsiveness=200
    local at2 = Instance.new("Attachment", hrp); at2.Name="_MK_AlignAt2"; ap.Attachment0=at2
    ap.Position=hrp.Position; ap.Parent=hrp
    S.gravityLock = {active=true, force=bf, align=ao, alignPos=ap, anchor=at2}
end

S.updateGravityLock = function(pos)
    if not S.gravityLock.active then return end
    local hrp = S.cache.hrp
    if not hrp or not hrp.Parent then S.releaseGravityLock(); return end
    if S.gravityLock.force and not S.gravityLock.force.Parent then S.gravityLock.force = nil end
    if S.gravityLock.alignPos and not S.gravityLock.alignPos.Parent then S.gravityLock.alignPos = nil end
    pcall(function()
        if S.gravityLock.force then
            S.gravityLock.force.Force = V3(0, hrp.AssemblyMass * math.max(Workspace.Gravity, 196.2), 0)
        end
        if S.gravityLock.alignPos and pos then S.gravityLock.alignPos.Position = pos end
        hrp.AssemblyLinearVelocity = V3(0, 0, 0)
        hrp.AssemblyAngularVelocity = V3(0, 0, 0)
    end)
end

S.releaseGravityLock = function()
    if S.gravityLock.force then pcall(function() S.gravityLock.force:Destroy() end) end
    if S.gravityLock.align then pcall(function() S.gravityLock.align:Destroy() end) end
    if S.gravityLock.alignPos then pcall(function() S.gravityLock.alignPos:Destroy() end) end
    if S.gravityLock.anchor then pcall(function() S.gravityLock.anchor:Destroy() end) end
    S.gravityLock = {active=false}
end

S.forceReleaseGravity = function()
    S.releaseGravityLock()
    pcall(function() Workspace.Gravity = S.originalGravity end)
    local hrp = S.cache.hrp
    if hrp then
        pcall(function()
            hrp.AssemblyLinearVelocity = V3(0,0,0)
            hrp.AssemblyAngularVelocity = V3(0,0,0)
        end)
    end
end

-- 战斗判定
S.isTargetSafe = function(plr)
    local myStr = S.myStrength(); local myDur = S.myDurability()
    local myHp = 0; pcall(function() myHp = S.cache.hum and S.cache.hum.MaxHealth or 0 end)
    local theirStr = S.stat(plr, "Strength"); local theirDur = S.stat(plr, "Durability")
    if myStr <= 0 then return false end
    local myEHP = myDur + myHp; local theirEHP = theirDur
    if theirEHP <= 0 and theirStr <= 0 then return false end
    return (theirEHP / math.max(myStr, 1)) < (myEHP / math.max(theirStr, 1)) * 0.8
end

-- ★ 放大敌人
S.enlargeTarget = function(plr)
    if not plr or not plr.Character then return end
    if S._enlargedTargets[plr.UserId] then return end
    local record = {}
    for _, part in ipairs(plr.Character:GetDescendants()) do
        if part:IsA("BasePart") then
            record[part] = part.Size
            pcall(function()
                part.Size = part.Size * V3(2.5, 2.5, 2.5)
                part.CanCollide = false
            end)
        end
    end
    S._enlargedTargets[plr.UserId] = record
end

S.restoreEnlarged = function(plr)
    if not plr then return end
    local record = S._enlargedTargets[plr.UserId]
    if not record then return end
    for part, size in pairs(record) do
        if part and part.Parent then
            pcall(function() part.Size = size end)
        end
    end
    S._enlargedTargets[plr.UserId] = nil
end

S.restoreAllEnlarged = function()
    for userId in pairs(S._enlargedTargets) do
        local plr = Players:GetPlayerByUserId(userId)
        if plr then S.restoreEnlarged(plr) end
    end
    table.clear(S._enlargedTargets)
end

-- 宝箱
S.findNearbyChest = function()
    local best, bestDist = nil, math.huge
    local roots = {Workspace, Workspace:FindFirstChild("Events")}
    local hrpPos = (S.cache.hrp and S.cache.hrp.Position) or S.CHEST_POS
    for _, radius in ipairs({S.CHEST_RADIUS, S.CHEST_RADIUS * 2}) do
        for _, root in ipairs(roots) do
            if root then
                for _, obj in ipairs(root:GetDescendants()) do
                    if obj:IsA("BasePart") and (obj.Name:find("Chest") or (obj.Parent and obj.Parent.Name:find("Chest"))) then
                        local d = (obj.Position - S.CHEST_POS).Magnitude
                        if d <= radius and obj.Transparency < 0.95 and obj.CanCollide then
                            local dist = (obj.Position - hrpPos).Magnitude
                            if dist < bestDist then best, bestDist = obj, dist end
                        end
                    end
                end
            end
        end
        if best then return best end
    end
    return nil
end

-- 换宠
S.getEquippedPetNames = function()
    local out = {}
    local own = Workspace:FindFirstChild(LP.Name); if not own then return out end
    for _, c in ipairs(own:GetChildren()) do
        if c:IsA("Model") then
            local slot = c:FindFirstChild("equippedSlot")
            if slot and slot:IsA("StringValue") and slot.Value ~= "" then
                table.insert(out, {name=c.Name, slot=slot.Value, model=c})
            end
        end
    end
    return out
end
S.getOwnedPetInstancesByName = function(name)
    local pf = LP:FindFirstChild("petsFolder"); if not pf then return {} end
    local out = {}
    for _, folder in ipairs(pf:GetChildren()) do
        if folder:IsA("Folder") then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet.Name == name then table.insert(out, pet) end
            end
        end
    end
    return out
end
S.unequipAllPets = function()
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    local ev = r and r:FindFirstChild("equipPetEvent"); if not ev then return end
    local pf = LP:FindFirstChild("petsFolder"); if not pf then return end
    for _, folder in ipairs(pf:GetChildren()) do
        if folder:IsA("Folder") then
            for _, pet in ipairs(folder:GetChildren()) do
                pcall(function() ev:FireServer("unequipPet", pet) end)
            end
        end
    end
end
-- ★ 加速版（无 wait）
S.applyPetPreset = function(presetType)
    local preset = S.petPreset[presetType]; if not preset or #preset == 0 then return end
    if S.petPreset.activeType == presetType then return end
    S.petPreset.activeType = presetType
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    local ev = r and r:FindFirstChild("equipPetEvent"); if not ev then return end
    local pf = LP:FindFirstChild("petsFolder")
    if pf then
        for _, folder in ipairs(pf:GetChildren()) do
            if folder:IsA("Folder") then
                for _, pet in ipairs(folder:GetChildren()) do
                    pcall(function() ev:FireServer("unequipPet", pet) end)
                end
            end
        end
    end
    for _, entry in ipairs(preset) do
        local instances = S.getOwnedPetInstancesByName(entry.name)
        for i = 1, math.min(entry.count or 1, #instances) do
            pcall(function() ev:FireServer("equipPet", instances[i]) end)
        end
    end
end

-- 暂停
S.essentialTasks = { info = true, emergency = true, save = true, sweep = true, rejoin = true, afk = true }
S.pauseScript = function()
    if S.scriptPaused then return end
    S.scriptPaused = true
    S.pausedSnapshot = {
        autoTrain=S.autoTrain, fastTrain=S.fastTrain, autoTeleport=S.autoTeleport,
        autoRebirth=S.autoRebirth, killEnabled=S.killEnabled, autoKingKill=S.autoKingKill,
        autoBoss=S.autoBoss, autoChest=S.autoChest, autoPackRebirth=S.autoPackRebirth,
        autoEatEgg=S.autoEatEgg, autoPetBuy=S.autoPetBuy, autoWheel=S.autoWheel,
        machineEnabled=S.machineState.enabled, machineTeleport=S.machineTeleport.enabled,
        teleportLoopEnabled=S.teleportLoopEnabled,
    }
    S.autoTrain=false; S.fastTrain=false; S.autoTeleport=false; S.autoRebirth=false
    S.killEnabled=false; S.autoKingKill=false; S.autoBoss=false; S.autoChest=false
    S.autoPackRebirth=false; S.autoEatEgg=false; S.autoPetBuy=false; S.autoWheel=false
    S.machineState.enabled=false; S.machineTeleport.enabled=false; S.teleportLoopEnabled=false
    S.restoreAllEnlarged()
    S.releaseGravityLock()
    pcall(function() Workspace.Gravity = S.originalGravity end)
    pcall(function()
        local hum = S.cache.hum
        if hum then hum:Move(V3(0,0,0), false); hum.WalkSpeed=0 end
    end)
    S.notify("脚本已暂停（保留信息+紧急重进）", 4)
end
S.resumeScript = function()
    if not S.scriptPaused then return end
    local snap = S.pausedSnapshot
    if snap then
        S.autoTrain=snap.autoTrain; S.fastTrain=snap.fastTrain; S.autoTeleport=snap.autoTeleport
        S.autoRebirth=snap.autoRebirth; S.killEnabled=snap.killEnabled; S.autoKingKill=snap.autoKingKill
        S.autoBoss=snap.autoBoss; S.autoChest=snap.autoChest; S.autoPackRebirth=snap.autoPackRebirth
        S.autoEatEgg=snap.autoEatEgg; S.autoPetBuy=snap.autoPetBuy; S.autoWheel=snap.autoWheel
        S.machineState.enabled=snap.machineEnabled; S.machineTeleport.enabled=snap.machineTeleport
        S.teleportLoopEnabled=snap.teleportLoopEnabled
    end
    pcall(function()
        local hum = S.cache.hum
        if hum then hum.WalkSpeed = S._origWalkSpeed end
    end)
    S.scriptPaused = false; S.pausedSnapshot = nil
    S.notify("脚本已恢复", 3)
end

-- 重进
S.getMemoryMb = function()
    local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
    if ok and type(v) == "number" then return math.floor(v) end
    return 0
end
S.readRawPing = function()
    local ok, v = pcall(function() return LP:GetNetworkPing() end)
    if ok and type(v) == "number" and v > 0 then return v * 1000 end
    local ok2, v2 = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok2 and type(v2) == "number" and v2 > 0 then return v2 end
    return 0
end
S.updatePingSmooth = function()
    local raw = S.readRawPing(); if raw <= 0 then return S.ping end
    table.insert(S.pingHistory, raw)
    if #S.pingHistory > 5 then table.remove(S.pingHistory, 1) end
    local sum, n = 0, #S.pingHistory
    for i = 1, n do sum = sum + S.pingHistory[i] end
    return n == 0 and S.ping or math.floor(sum / n)
end

S.getHttpFn = function()
    if syn and syn.request then return syn.request end
    if http and http.request then return http.request end
    if request then return request end
    if http_request then return http_request end
    if fluxus and fluxus.request then return fluxus.request end
    return nil
end
S.fetchServers = function(sortOrder)
    local httpFn = S.getHttpFn(); if not httpFn then return nil end
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100", game.PlaceId, sortOrder)
    local ok, resp = pcall(httpFn, {Url=url, Method="GET"})
    if not ok or not resp then return nil end
    local body = resp.Body or resp.body; if not body then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok2 or type(data) ~= "table" or not data.data then return nil end
    local result = {}
    for _, srv in ipairs(data.data) do
        if srv.id and srv.id ~= game.JobId then
            local playing = tonumber(srv.playing) or 0
            local maxP = tonumber(srv.maxPlayers) or 0
            if playing < maxP then table.insert(result, {id=srv.id, playing=playing}) end
        end
    end
    return result
end
S.parsePrivateServerCode = function(input)
    if not input or input == "" then return nil end
    local code = input:match("privateServerLinkCode=([%w%-_]+)")
    if code then return code end
    if input:match("^[%w%-_]+$") then return input end
    local code2 = input:match("[%?&]code=([%w%-_]+)")
    if code2 then return code2 end
    local numId = input:match("(%d+)")
    if numId and #numId > 5 then return numId end
    return nil
end

S.rejoinGame = function(reason, urgent)
    if S._rejoinTriggered then return end
    if not urgent then
        S.rejoinPending = true; S.rejoinPendingAt = tick()
        S.notify("【重进】" .. (reason or "") .. "，3秒内可点击取消", 3)
        task.delay(3, function()
            if S.rejoinPending and tick() - S.rejoinPendingAt >= 3 then
                S.rejoinPending = false
                S._rejoinTriggered = true
                S.doRejoin(reason)
            end
        end)
    else
        S._rejoinTriggered = true
        S.doRejoin(reason)
    end
end

S.doRejoin = function(reason)
    S.notify("正在重进...", 4)
    task.wait(1)
    local mode = S.rejoinServerMode or "same"
    local ok = false
    if mode == "private" then
        local code = S.parsePrivateServerCode(S.rejoinPrivateServerId)
        if code then ok = pcall(function() TeleportService:TeleportToPrivateServer(game.PlaceId, code, {LP}) end) end
        if not ok then ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end) end
        if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, LP) end) end
    elseif mode == "crowded" then
        local servers = S.fetchServers("Desc")
        if servers and #servers > 0 then ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LP) end) end
        if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, LP) end) end
    elseif mode == "sparse" then
        local servers = S.fetchServers("Asc")
        if servers and #servers > 0 then ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LP) end) end
        if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, LP) end) end
    else
        ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
        if not ok then
            S.notify("原服务器不可用，加入新服务器", 4)
            pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
        end
    end
    task.wait(3)
    pcall(function() LP:Kick("AutoRejoin") end)
end

S.checkRejoin = function()
    if not S.autoRejoinEnabled or S._rejoinTriggered then return end
    if tick() - S.rejoinCheckAt < 3 then return end
    S.rejoinCheckAt = tick()
    S.memMb = S.getMemoryMb()
    local enabledCount, triggeredCount = 0, 0; local triggers = {}
    if S.rejoinEnableFps then
        enabledCount = enabledCount + 1
        if S.avgFps > 0 and S.avgFps < S.rejoinFpsThreshold then
            triggeredCount = triggeredCount + 1; table.insert(triggers, string.format("帧率%.0f<%d", S.avgFps, S.rejoinFpsThreshold))
        end
    end
    if S.rejoinEnablePing then
        enabledCount = enabledCount + 1
        if S.ping > 0 and S.ping > S.rejoinPingThreshold then
            triggeredCount = triggeredCount + 1; table.insert(triggers, string.format("延迟%d>%d", S.ping, S.rejoinPingThreshold))
        end
    end
    if S.rejoinEnableMem then
        enabledCount = enabledCount + 1
        if S.memMb > 0 and S.memMb > S.rejoinMemThreshold then
            triggeredCount = triggeredCount + 1; table.insert(triggers, string.format("内存%d>%d", S.memMb, S.rejoinMemThreshold))
        end
    end
    if enabledCount == 0 then return end
    local should = (S.rejoinCondition == "all") and (triggeredCount == enabledCount) or (triggeredCount > 0)
    if should then S.rejoinGame(table.concat(triggers, ","), false) end
end

S.emergencyRejoinCheck = function()
    if not S.emergencyRejoin or S._rejoinTriggered then return end
    local found = nil
    local ok1, cg = pcall(function() return CoreGui end)
    if ok1 and cg then
        local prompt = cg:FindFirstChild("RobloxPromptGui")
        if prompt then
            local overlay = prompt:FindFirstChild("promptOverlay")
            if overlay and overlay.Enabled then
                local et = overlay:FindFirstChild("ErrorTitle"); local em = overlay:FindFirstChild("ErrorMsg")
                local t = (et and et.Text or "") .. " " .. (em and em.Text or "")
                if #t > 3 then found = t end
            end
        end
    end
    if not found then
        for _, gui in ipairs(PG:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled then
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        local txt = d.Text or ""; local lt = txt:lower()
                        if lt:find("disconnect") or lt:find("kick") or lt:find("connection lost")
                            or lt:find("网络错误") or lt:find("尝试重新连接") then found = txt; break end
                    end
                end
                if found then break end
            end
        end
    end
    if found then
        S.notify("【紧急重进】" .. found:sub(1, 40), 3)
        S.rejoinGame("紧急：" .. found:sub(1, 30), true)
    end
end

-- 器械
S.fireOverchargedTravel = function()
    local ev = ReplicatedStorage:FindFirstChild("rEvents")
    ev = ev and ev:FindFirstChild("areaTravelRemote"); if not ev then return false end
    local circle = Workspace:FindFirstChild("areaCircles")
    circle = circle and circle:FindFirstChild("overchargedGymCircle"); if not circle then return false end
    pcall(function() ev:InvokeServer("travelToArea", circle) end); return true
end
S.getMachineGym = function(seatPos)
    local closest, minDist = nil, math.huge
    for _, gym in ipairs(S.GYM_POSITIONS) do
        local d = (seatPos - gym.pos).Magnitude
        if d < minDist then minDist = d; closest = gym.name end
    end
    return closest or "未知", minDist
end
S.getMachineSeats = function()
    local folder = Workspace:FindFirstChild("machinesFolder"); if not folder then return {} end
    local seats = {}
    for i, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") then
            local seat = m:FindFirstChild("interactSeat")
            if not (seat and seat:IsA("BasePart")) then
                for _, child in ipairs(m:GetChildren()) do
                    if child:IsA("Seat") or child:IsA("VehicleSeat") then seat = child; break end
                end
            end
            if not (seat and seat:IsA("BasePart")) then
                for _, child in ipairs(m:GetDescendants()) do
                    if child:IsA("Seat") or child:IsA("VehicleSeat") then seat = child; break end
                end
            end
            if seat and seat:IsA("BasePart") then
                local gym, dist = S.getMachineGym(seat.Position)
                table.insert(seats, {model=m, seat=seat, name=m.Name, gym=gym, gymDist=dist, modelIndex=i})
            end
        end
    end
    return seats
end
S.getMachineSeatsByGym = function()
    local all = S.getMachineSeats()
    local grouped = {}
    for _, s in ipairs(all) do
        if not grouped[s.gym] then grouped[s.gym] = {} end
        table.insert(grouped[s.gym], s)
    end
    return grouped
end
S.getFilteredMachines = function()
    local all = S.getMachineSeats()
    local gym = S.machineState.gymFilter or ""
    local out = {}
    for _, s in ipairs(all) do
        if gym == "" or s.gym == gym then table.insert(out, s) end
    end
    return out
end
S.getMachineNameList = function()
    local names, seen = {}, {}
    for _, s in ipairs(S.getFilteredMachines()) do
        if not seen[s.name] then seen[s.name] = true; table.insert(names, s.name) end
    end
    table.sort(names)
    return names
end
S.getMachineCountByName = function(name)
    local n = 0
    for _, s in ipairs(S.getFilteredMachines()) do
        if name == "" or s.name == name then n = n + 1 end
    end
    return n
end
S.resolveTargetSeat = function()
    local mname = S.machineState.machineFilter or ""
    local idx = S.machineState.indexFilter or 0
    local candidates = {}
    for _, s in ipairs(S.getFilteredMachines()) do
        if mname == "" or s.name == mname then table.insert(candidates, s) end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a,b)
        if a.name == b.name then return a.modelIndex < b.modelIndex end
        return a.name < b.name
    end)
    if idx > 0 and idx <= #candidates then return candidates[idx].seat end
    return nil
end

S.teleportToMachine = function()
    if not S.machineState.enabled then return end
    if tick() < (S._jumpCdUntil or 0) then return end
    local now = tick()
    if now - S.machineState.lastTry < 0.5 then return end
    S.machineState.lastTry = now
    local resolved = S.resolveTargetSeat()
    if resolved and resolved.Parent then S.machineState.targetSeat = resolved end
    local seats = S.getMachineSeats()
    if #seats == 0 then return end
    if S.machineState.targetSeat then
        local ok = false
        for _, s in ipairs(seats) do if s.seat == S.machineState.targetSeat then ok = true; break end end
        if not ok then S.machineState.targetSeat = nil end
    end
    if not S.machineState.targetSeat then
        local candidates = S.getFilteredMachines()
        if #candidates == 0 then candidates = seats end
        local avail = {}
        for _, s in ipairs(candidates) do if not s.seat.Occupant then table.insert(avail, s) end end
        if #avail == 0 then avail = candidates end
        if #avail > 0 then S.machineState.targetSeat = avail[math.random(1, #avail)].seat end
    end
    local seat = S.machineState.targetSeat
    if not seat or not seat.Parent then S.machineState.targetSeat = nil; return end
    local occ = seat.Occupant
    if occ then
        local occPlr = Players:GetPlayerFromCharacter(occ.Parent)
        if occPlr and occPlr ~= LP then
            if not S._machineOccupantTarget then
                S._machineOccupantTarget = occPlr; S._machineOccupantSince = tick()
                S.notify("器械被 " .. occPlr.Name .. " 占用，尝试击杀", 4)
            end
            local elapsed = tick() - (S._machineOccupantSince or tick())
            if elapsed > 15 then
                S.notify("器械被占用超过15秒，关闭器械模式", 6)
                S.machineState.enabled = false; S._machineOccupantTarget = nil
                if S.ui and S.ui.machineToggle then S.ui.machineToggle.set(false) end
                return
            end
            if S.isTargetSafe(occPlr) then
                local hrp = S.cache.hrp; local theirHRP = S.getCharHRP(occPlr)
                if hrp and theirHRP then
                    S.applyKillMove(theirHRP)
                    if tick() - (S.killLastAttack or 0) >= 0.05 then
                        S.killLastAttack = tick()
                        if not S.isEquipped(S.TOOL_KW.punch) then S.tryEquip(S.TOOL_KW.punch) end
                        S.punch()
                    end
                end
            else
                S.notify("器械占用者太强，关闭器械模式", 5)
                S.machineState.enabled = false; S._machineOccupantTarget = nil
                if S.ui and S.ui.machineToggle then S.ui.machineToggle.set(false) end
            end
            return
        end
    else
        if S._machineOccupantTarget then
            S._machineOccupantTarget = nil; S._machineOccupantSince = nil
        end
    end
    local hrp = S.cache.hrp; if not hrp then return end
    if (seat.Position - S.OVERCHARGED_POS).Magnitude < 200 then
        S.fireOverchargedTravel()
        task.wait(0.2)
    end
    pcall(function()
        hrp.CFrame = CN(seat.Position + V3(0, 3, 0))
        hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0)
    end)
    local ev = ReplicatedStorage:FindFirstChild("rEvents")
    ev = ev and ev:FindFirstChild("machineInteractRemote")
    if ev then
        local ok = pcall(function() ev:InvokeServer("useMachine", seat) end)
        if ok then S.machineState.using = true; S.machineState.failCount = 0
        else
            S.machineState.failCount = S.machineState.failCount + 1
            local parent = seat.Parent
            if parent then
                for _, alt in ipairs(parent:GetDescendants()) do
                    if (alt:IsA("Seat") or alt:IsA("VehicleSeat")) and alt ~= seat then
                        pcall(function() ev:InvokeServer("useMachine", alt) end)
                        break
                    end
                end
            end
        end
    end
end

S.tryCancelMachine = function()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, ENUM.KeyCode.Space, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, ENUM.KeyCode.Space, false, game)
    end)
end

-- 战斗
S.getPlayerAlignment = function(plr)
    if not plr then return nil end
    for _, a in ipairs({"Alignment","Karma","Faction","Side","Team"}) do
        local v = plr:GetAttribute(a)
        if type(v) == "string" then
            local k = v:lower()
            if k:find("good") or k:find("hero") or k:find("正义") or k:find("好人") then return "good" end
            if k:find("bad") or k:find("villain") or k:find("evil") or k:find("邪恶") or k:find("坏人") then return "bad" end
        elseif type(v) == "number" then if v > 0 then return "good" elseif v < 0 then return "bad" end end
    end
    return nil
end
S.passAlignmentFilter = function(plr)
    if S.killGoodOnly == S.killBadOnly then return true end
    local a = S.getPlayerAlignment(plr); if not a then return true end
    if S.killGoodOnly then return a == "good" end
    if S.killBadOnly then return a == "bad" end
    return true
end
S.getCharHRP = function(plr)
    local c = plr and plr.Character; if not c then return nil end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h or h.Health <= 0 then return nil end
    return hrp
end
S.applyKillMove = function(targetHRP)
    local hrp = S.cache.hrp; if not hrp then return end
    local d = targetHRP.Position - hrp.Position
    local dsq = d.X*d.X + d.Y*d.Y + d.Z*d.Z
    if dsq > 9 then
        local dist = math.sqrt(dsq)
        local np = targetHRP.Position - d/dist*2.5
        pcall(function() hrp.CFrame = CN(np, targetHRP.Position)
            hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0) end)
    end
end
S.punch = function()
    local c = S.cache.char; if not c then return end
    local tool = c:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
end

S.refreshFriendList = function()
    local FW = S.friendWL
    if FW.refreshing or tick() - FW.lastAttempt < 60 then return end
    FW.lastAttempt = tick(); FW.refreshing = true
    S.spawnThread("friendRefresh", function()
        local ids = {}
        pcall(function()
            local pages = LP:GetFriendsAsync()
            while pages do
                for _, item in ipairs(pages:GetCurrentPage()) do if item.Id then ids[item.Id] = true end end
                if pages.IsFinished then break end
                pcall(function() pages:AdvanceToNextPageAsync() end)
            end
        end)
        pcall(function()
            for _, f in ipairs(LP:GetFriendsOnline(200)) do if f.VisitorId then ids[f.VisitorId] = true end end
        end)
        FW.ids = ids; FW.loaded = true
        local n = 0; for _ in pairs(ids) do n = n + 1 end
        S.friendCount = n; FW.lastRefresh = tick(); FW.refreshing = false
    end)
end
S.isFriend = function(plr) if not plr or not plr.UserId then return false end return S.friendWL.ids[plr.UserId] == true end

S.refreshRepSpeed = function()
    local RC = S.repCache
    local sumPct = 0
    local own = Workspace:FindFirstChild(LP.Name)
    if own then
        local seen = {}
        for _, pet in ipairs(own:GetChildren()) do
            if pet:IsA("Model") then
                local slot
                local s = pet:FindFirstChild("equippedSlot")
                if s and s:IsA("StringValue") and s.Value ~= "" then slot = s.Value end
                local key = slot or ("obj:" .. tostring(pet))
                if not seen[key] then
                    seen[key] = true
                    local perks = pet:FindFirstChild("perksFolder")
                    if perks then
                        for _, p in ipairs(perks:GetChildren()) do
                            if p:IsA("ValueBase") and p.Name:lower():find("rep") then
                                local v = tonumber(p.Value) or 0
                                if v > 0 then sumPct = sumPct + v end
                            end
                        end
                    end
                end
            end
        end
    end
    local ultPct = 0
    local a = LP:GetAttribute("UltimateRepSpeed")
    if type(a) == "number" then ultPct = a * 5 end
    local now = tick()
    if now - (RC.lastPassCheck or 0) > 60 then
        RC.lastPassCheck = now
        local ok, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(LP.UserId, 6998482)
        end)
        RC.x2 = (ok and owns == true) and true or false
    end
    local petMul = math.max(0.001, 1 - sumPct / 100)
    local ultMul = math.max(0.001, 1 - ultPct / 100)
    local passMul = RC.x2 and 0.5 or 1
    local totalMul = petMul * ultMul * passMul
    RC.pet = sumPct; RC.ult = ultPct
    RC.speedMul = 1 / math.max(0.0001, totalMul)
end

S.updateRebirthRate = function()
    local now = tick()
    local cur = S.stat(LP, "Rebirths")
    if now - (S._lastRebCheck or 0) >= 30 then
        if S._lastRebCheck > 0 then
            local delta = cur - (S._lastRebVal or cur)
            local dt = now - S._lastRebCheck
            if dt > 0 then S.rebirthPerSec = delta / dt end
        end
        S._lastRebCheck = now
        S._lastRebVal = cur
    end
end

S.getBossHoverHeight = function()
    if S.bossHeightMode == "manual" then return S.bossHeight end
    if S.bossCurrent == "Boss1" then return 40 end
    return 55
end

S.findBossModel = function(name)
    local events = Workspace:FindFirstChild("Events")
    local arena = events and events:FindFirstChild("BossArena")
    local holder = arena and arena:FindFirstChild(name or S.bossCurrent)
    return holder and holder:FindFirstChild("Boss")
end
S.isBossAlive = function(name)
    local b = S.findBossModel(name); if not b then return false end
    if b:IsA("Model") then local h = b:FindFirstChildOfClass("Humanoid"); return h ~= nil and h.Health > 0 end
    return b:IsA("BasePart") and b.Transparency < 1
end
S.isAnyBossAlive = function()
    if tick() - S.bossAliveCacheAt < 0.5 then return S.bossAliveCache end
    S.bossAliveCacheAt = tick()
    for _, n in ipairs(S.BOSS_NAMES) do if S.isBossAlive(n) then S.bossAliveCache = true; return true end end
    S.bossAliveCache = false; return false
end
S.getBossPos = function()
    local b = S.findBossModel(); if not b then return nil end
    if b:IsA("Model") then return b:GetPivot().Position end
    return b.Position
end

S.startBossHover = function()
    if S.bossHoverConn then pcall(function() S.bossHoverConn:Disconnect() end) end
    S.bossHoverConn = RS:Connect(function()
        if not S.autoBoss then return end
        if S.isAnyBossAlive() then
            local hrp = S.cache.hrp; if not hrp then return end
            local bp = S.getBossPos(); if not bp then return end
            local height = S.getBossHoverHeight()
            local hoverPos = bp + V3(0, height, 0)
            local flat = V3(bp.X - hoverPos.X, 0, bp.Z - hoverPos.Z)
            if flat.Magnitude < 0.1 then flat = V3(0,0,-1) end
            hrp.CFrame = CFrame.lookAt(hoverPos, hoverPos + (flat.Unit + V3(0,-1,0)).Unit)
            S.updateGravityLock(hoverPos)
        elseif S.bossKilledAt > 0 and (tick() - S.bossKilledAt) < 30 then
            local hrp = S.cache.hrp; if not hrp then return end
            S.updateGravityLock(S.bossDeathPos or hrp.Position)
        end
    end)
end

S.bossPunchLoop = function()
    local useLeft, trackL, trackR = true, nil, nil
    local counter = 0
    while S.autoBoss and not S.destroyed do
        if S.isAnyBossAlive() and S.getBossPos() then
            counter = counter + 1
            if counter % 4 == 0 then
                pcall(function()
                    local bp = LP:FindFirstChild("Backpack")
                    local pt = bp and bp:FindFirstChild("Punch")
                    local cd = pt and pt:FindFirstChildOfClass("NumberValue")
                    if cd then cd.Value = 0.01 end
                end)
            end
            pcall(function()
                local char = S.cache.char
                local hum = char and char:FindFirstChildOfClass("Humanoid"); if not hum then return end
                local bp = LP:FindFirstChild("Backpack")
                local pt = (char and char:FindFirstChild("Punch")) or (bp and bp:FindFirstChild("Punch"))
                if pt and pt.Parent ~= char then hum:EquipTool(pt) end
                local ev = S.getMuscleEvent()
                if ev then ev:FireServer("punch", useLeft and "leftHand" or "rightHand") end
                local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
                local track = useLeft and trackL or trackR
                if not track then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = useLeft and "rbxassetid://3638729053" or "rbxassetid://3638767427"
                    track = animator:LoadAnimation(anim)
                    if useLeft then trackL = track else trackR = track end
                end
                if track then track:Stop(0); track:Play(0.1) end
                useLeft = not useLeft
            end)
        else task.wait(0.5) end
        task.wait(0.05)
    end
end

S.bossScanLoop = function()
    while S.autoBoss and not S.destroyed do
        task.wait(2)
        if S.autoBoss and not S.destroyed then
            for _, n in ipairs(S.BOSS_NAMES) do
                if S.isBossAlive(n) then if n ~= S.bossCurrent then S.bossCurrent = n end break end
            end
        end
    end
end

S.selectKillTarget = function()
    for _, plr in ipairs(GetPlayers(Players)) do
        if plr ~= LP and not (S.friendWhitelist and S.isFriend(plr)) then
            local hrp = S.getCharHRP(plr)
            if hrp and S.passAlignmentFilter(plr) and S.isTargetSafe(plr) then return plr end
        end
    end
    return nil
end

S.runKillTick = function()
    if tick() - S.killScanAt >= 0.5 then
        S.killScanAt = tick()
        if S.killTarget and S.friendWhitelist and S.isFriend(S.killTarget) then S.killTarget = nil end
        if S.killTarget and not S.passAlignmentFilter(S.killTarget) then S.killTarget = nil end
        local valid = S.killTarget and S.getCharHRP(S.killTarget)
        if not valid then S.killTarget = S.selectKillTarget()
        elseif not S.isTargetSafe(S.killTarget) then S.killTarget = S.selectKillTarget() end
        S.toolOwnedByKill = S.killTarget ~= nil
        -- ★ 放大当前目标
        if S.killTarget then
            if tick() - (S._lastKillEnlarge or 0) > 2 then
                S._lastKillEnlarge = tick()
                S.enlargeTarget(S.killTarget)
            end
        end
    end
    local t = S.killTarget; if not t then return end
    local hrp = S.getCharHRP(t); if not hrp then S.killTarget = nil; return end
    S.applyKillMove(hrp)
    if not (S.dualEnabled and (S.autoTrain or S.fastTrain)) then
        if tick() - S.killLastAttack >= 0.05 then
            S.killLastAttack = tick()
            if not S.isEquipped(S.TOOL_KW.punch) then S.tryEquip(S.TOOL_KW.punch) end
            S.punch()
        end
    end
end

S.runKingKillTick = function()
    if tick() - S.lastKingCheck >= 0.5 then
        S.lastKingCheck = tick()
        local shared = ReplicatedStorage:FindFirstChild("shared")
        local state = shared and shared:FindFirstChild("state")
        local world = state and state:FindFirstChild("World")
        local mk = world and world:FindFirstChild("muscleKing")
        local king = nil
        if mk then
            if mk:IsA("ObjectValue") then king = mk.Value
            elseif mk:IsA("StringValue") and mk.Value ~= "" then king = Players:FindFirstChild(mk.Value) end
        end
        if not king or king == LP or (S.friendWhitelist and S.isFriend(king)) then
            S.kingKillTarget = nil; S.kingKillActive = false; return
        end
        if not S.getCharHRP(king) or not S.isTargetSafe(king) then
            S.kingKillTarget = nil; S.kingKillActive = false; return
        end
        S.kingKillTarget = king
    end
    local t = S.kingKillTarget; if not t then S.kingKillActive = false; return end
    if S.friendWhitelist and S.isFriend(t) then S.kingKillTarget = nil; S.kingKillActive = false; return end
    local hrp = S.getCharHRP(t)
    if not hrp then S.kingKillTarget = nil; S.kingKillActive = false; return end
    S.kingKillActive = true
    S.enlargeTarget(t)
    S.applyKillMove(hrp)
    if tick() - S.kingKillLastAttack >= 0.05 then
        S.kingKillLastAttack = tick()
        if not S.isEquipped(S.TOOL_KW.punch) then S.tryEquip(S.TOOL_KW.punch) end
        S.punch()
    end
end

S.findPreferredTool = function()
    local TK = S.TOOL_KW
    if S.toolPushups then local t = S.findTool(TK.pushups); if t then return t end end
    if S.toolHandstands then local t = S.findTool(TK.handstands); if t then return t end end
    if S.toolSitups then local t = S.findTool(TK.situps); if t then return t end end
    if S.toolDumbbell then local t = S.findTool(TK.dumbbell); if t then return t end end
    return nil
end
S.updateDualTool = function()
    if not S.dualEnabled or not S.killEnabled or not S.killTarget then return end
    if not (S.autoTrain or S.fastTrain) then return end
    local hum = S.cache.hum; if not hum then return end
    if S._bossActive then return end
    if tick() - S.dualLastSwitch < 0.06 then return end
    S.dualLastSwitch = tick()
    if S.dualCurrentMode == "punch" then
        local t = S.findPreferredTool()
        if t then
            pcall(function() hum:EquipTool(t) end); S.dualCurrentMode = "train"
            task.defer(function() if not S.destroyed then pcall(function() t:Activate() end) end end)
        else S.dualCurrentMode = "punch" end
    else
        local t = S.findTool(S.TOOL_KW.punch)
        if t then
            pcall(function() hum:EquipTool(t) end); S.dualCurrentMode = "punch"
            task.defer(function() if not S.destroyed then pcall(function() t:Activate() end) end end)
        else S.dualCurrentMode = "train" end
    end
end

-- PETS / getOwnedPets / eatEgg / giftEggs / petShop / antiLag / tex / cull / hide 同 v38
S.PETS_DATA = {
    ["Omega Overlord"]={repSpeed=20},["Swift Samurai"]={repSpeed=15},
    ["Powercore Hound"]={strength=25,durability=15},["Titanium Hydra"]={rebirth=2},
    ["Tribal Overlord"]={rebirth=2},["Inferno Unicorn"]={strength=25,durability=25},
    ["Common Boss Pet"]={repSpeed=5},["Rare Boss Pet"]={repSpeed=7},
    ["Epic Boss Pet"]={repSpeed=10},["Rainbow Boss Pet"]={repSpeed=10,strength=7},
    ["Legendary Boss Pet"]={repSpeed=10,strength=10},["Mythic Boss Pet"]={repSpeed=10,strength=20},
    ["Inferno Drake"]={repSpeed=40},
}
S.getOwnedPets = function()
    local out = {}
    local pf = LP:FindFirstChild("petsFolder"); if not pf then return out end
    local previews = ReplicatedStorage:FindFirstChild("shared")
    previews = previews and previews:FindFirstChild("runtime")
    previews = previews and previews:FindFirstChild("petPreviews")
    for _, folder in ipairs(pf:GetChildren()) do
        if folder:IsA("Folder") then
            for _, pet in ipairs(folder:GetChildren()) do
                local cfg = S.PETS_DATA[pet.Name]
                local entry = {instance=pet, name=pet.Name, repSpeed=0, strength=0, durability=0, rebirth=0}
                if cfg then
                    entry.repSpeed=cfg.repSpeed or 0; entry.strength=cfg.strength or 0
                    entry.durability=cfg.durability or 0; entry.rebirth=cfg.rebirth or 0
                else
                    local pv = previews and previews:FindFirstChild(pet.Name)
                    if pv then
                        local perks = pv:FindFirstChild("perksFolder")
                        if perks then
                            local rep = perks:FindFirstChild("repTimeBoostPercent")
                            local str = perks:FindFirstChild("strength")
                            local dur = perks:FindFirstChild("durability")
                            entry.repSpeed = rep and tonumber(rep.Value) or 0
                            entry.strength = str and tonumber(str.Value) or 0
                            entry.durability = dur and tonumber(dur.Value) or 0
                        end
                    end
                end
                table.insert(out, entry)
            end
        end
    end
    return out
end
S.equipOnePet = function(pet)
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    local ev = r and r:FindFirstChild("equipPetEvent")
    if ev then pcall(function() ev:FireServer("equipPet", pet) end) end
end
S.equipFarmingPets = function()
    S.unequipAllPets()
    local pets = S.getOwnedPets(); table.sort(pets, function(a,b) return a.repSpeed > b.repSpeed end)
    local equipped, count, rep = {}, 0, 0
    for _, p in ipairs(pets) do
        if count >= 12 or rep >= 100 then break end
        if p.repSpeed > 0 then S.equipOnePet(p.instance); equipped[p.instance]=true; count=count+1; rep=rep+p.repSpeed end
    end
    local rest = {}
    for _, p in ipairs(pets) do if not equipped[p.instance] then table.insert(rest, p) end end
    table.sort(rest, function(a,b) return (a.strength+a.durability) > (b.strength+b.durability) end)
    for _, p in ipairs(rest) do
        if count >= 12 then break end
        if p.strength > 0 or p.durability > 0 then S.equipOnePet(p.instance); count = count + 1 end
    end
end
S.equipRebirthPets = function()
    S.unequipAllPets()
    local pets = S.getOwnedPets(); table.sort(pets, function(a,b) return a.rebirth > b.rebirth end)
    local count = 0
    for _, p in ipairs(pets) do
        if count >= 12 then break end
        if p.rebirth > 0 then S.equipOnePet(p.instance); count = count + 1 end
    end
end
S.performPackRebirth = function()
    local ev = S.getMuscleEvent(); if not ev then return end
    local ls = LP:FindFirstChild("leaderstats")
    local strStat = ls and ls:FindFirstChild("Strength"); local rebStat = ls and ls:FindFirstChild("Rebirths")
    if not (strStat and rebStat) then return end
    local target = 5000 + rebStat.Value * 2550
    while strStat.Value < target and S.autoPackRebirth and not S.destroyed do
        pcall(function()
            local burst = math.clamp(math.floor(S.fastRate/10), 5, 50)
            for _ = 1, burst do ev:FireServer("rep") end
        end)
        task.wait(0.01)
    end
    S.equipRebirthPets(); task.wait(0.25)
    local before = rebStat.Value; local tries = 0
    repeat S.fireRebirth(); task.wait(0.05); tries = tries + 1
    until rebStat.Value > before or tries > 20
end
S.packRebirthLoop = function()
    while S.autoPackRebirth and not S.destroyed do
        S.equipFarmingPets(); S.performPackRebirth(); task.wait(0.5)
    end
end

S.findProteinEgg = function()
    local c = S.cache.char; local bp = LP:FindFirstChild("Backpack")
    return (c and c:FindFirstChild("Protein Egg")) or (bp and bp:FindFirstChild("Protein Egg"))
end
S.eatEggLoop = function()
    local ev = S.getMuscleEvent()
    while S.autoEatEgg and not S.destroyed do
        pcall(function()
            local egg = S.findProteinEgg()
            local batch = S.eatEggBatch or 10
            if egg and ev then for _ = 1, batch do ev:FireServer("proteinEgg", egg) end end
        end)
        task.wait(0.5)
    end
end

S.giftEggsTo = function(target, amount)
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    local giftRemote = r and r:FindFirstChild("giftRemote")
    local folder = LP:FindFirstChild("consumablesFolder")
    if not (giftRemote and folder and target) then return 0 end
    local sent = 0; amount = amount or 9999
    for _ = 1, amount do
        local egg = folder:FindFirstChild("Protein Egg")
        if not egg or not egg.Parent then break end
        local ok = pcall(function()
            if egg.Parent and target.Parent then giftRemote:InvokeServer("giftRequest", target, egg) end
        end)
        if ok then sent = sent + 1 end
        task.wait(0.1)
    end
    return sent
end

S.getPetShopFolder = function()
    local s = ReplicatedStorage:FindFirstChild("shared")
    local rt = s and s:FindFirstChild("runtime")
    return rt and rt:FindFirstChild("cPetShopFolder")
end
S.getPetShopRemote = function()
    local r = ReplicatedStorage:FindFirstChild("rEvents")
    return r and r:FindFirstChild("cPetShopRemote")
end
S.getPetShopList = function()
    local names = {}
    pcall(function()
        local f = S.getPetShopFolder()
        if f then for _, item in ipairs(f:GetChildren()) do table.insert(names, item.Name) end end
    end)
    table.sort(names); return names
end
S.buyPet = function(name)
    local remote = S.getPetShopRemote(); local folder = S.getPetShopFolder()
    if not (remote and folder) then return false end
    if not name or name == "" then return false end
    local pet = folder:FindFirstChild(name); if not pet then return false end
    pcall(function()
        if remote:IsA("RemoteFunction") then remote:InvokeServer(pet) else remote:FireServer(pet) end
    end)
    return true
end

S.hidePart = function(m)
    if not m or not m.Parent then return end
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p.LocalTransparencyModifier = 1; p.Transparency = 1 end) end
    end
end
S.showPart = function(m)
    if not m or not m.Parent then return end
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p.LocalTransparencyModifier = 0; p.Transparency = 0 end) end
    end
end
S.scanHidePets = function()
    local PH = S.petHider
    if S.hideOwnPets then
        local own = Workspace:FindFirstChild(LP.Name)
        if own then for _, pet in ipairs(own:GetChildren()) do
            if pet:IsA("Model") or pet:IsA("Folder") then table.insert(PH.own, pet); S.hidePart(pet) end
        end end
    end
    if S.hideAllPets then
        for _, plr in ipairs(GetPlayers(Players)) do
            if plr ~= LP then
                local f = Workspace:FindFirstChild(plr.Name)
                if f then for _, pet in ipairs(f:GetChildren()) do
                    if pet:IsA("Model") or pet:IsA("Folder") then table.insert(PH.all, pet); S.hidePart(pet) end
                end end
            end
        end
    end
    PH.rescanAt = tick() + 2
end
S.restoreHiddenPets = function()
    local PH = S.petHider
    for _, m in ipairs(PH.own) do S.showPart(m) end; table.clear(PH.own)
    for _, m in ipairs(PH.all) do S.showPart(m) end; table.clear(PH.all)
end
S.scanHideMachines = function()
    if not S.hideMachines then return end
    local PH = S.petHider; local mf = Workspace:FindFirstChild("machinesFolder")
    if mf then for _, m in ipairs(mf:GetChildren()) do
        if m:IsA("Model") then table.insert(PH.machines, m); S.hidePart(m) end
    end end
    PH.rescanAt = tick() + 2
end
S.restoreHiddenMachines = function()
    for _, m in ipairs(S.petHider.machines) do S.showPart(m) end; table.clear(S.petHider.machines)
end

S.scanTextures = function()
    local TR = S.texRem
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local cls = obj.ClassName
        if cls == "Decal" or cls == "Texture" then
            if not TR.seen[obj] and obj.Texture ~= "" then
                TR.seen[obj]=true
                table.insert(TR.saved,{obj=obj,prop="Texture",value=obj.Texture}); obj.Texture=""
            end
        elseif cls == "MeshPart" or cls == "SpecialMesh" then
            local p = (cls == "MeshPart") and "TextureID" or "TextureId"
            if not TR.seen[obj] and obj[p] and obj[p] ~= "" then
                TR.seen[obj]=true
                table.insert(TR.saved,{obj=obj,prop=p,value=obj[p]}); obj[p]=""
            end
        elseif cls == "SurfaceAppearance" then
            if not TR.seen[obj] and obj.ColorMap ~= "" then
                TR.seen[obj]=true
                table.insert(TR.saved,{obj=obj,prop="ColorMap",value=obj.ColorMap}); obj.ColorMap=""
            end
        elseif cls == "BasePart" then
            if not TR.seen[obj] and obj.Material ~= ENUM.Material.Plastic then
                TR.seen[obj]=true
                table.insert(TR.saved,{obj=obj,prop="Material",value=obj.Material})
                obj.Material = ENUM.Material.Plastic; obj.Reflectance = 0
            end
        end
    end
end
S.enableTex = function()
    if S.texRem.enabled then return end
    S.texRem.enabled = true; table.clear(S.texRem.saved); table.clear(S.texRem.seen)
    S.scanTextures(); S.texRem.rescanAt = tick() + 4
end
S.rescanTex = function()
    if not S.texRem.enabled then return end
    S.scanTextures(); S.texRem.rescanAt = tick() + 4
end
S.disableTex = function()
    S.texRem.enabled = false
    for _, it in ipairs(S.texRem.saved) do pcall(function() it.obj[it.prop] = it.value end) end
    table.clear(S.texRem.saved); table.clear(S.texRem.seen)
end

S.scanAntiLag = function()
    local AL = S.antiLag
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local cls = obj.ClassName
        if cls == "ParticleEmitter" or cls == "Trail" or cls == "Beam" or cls == "Fire" or cls == "Smoke" or cls == "Sparkles" then
            if obj.Enabled then obj.Enabled = false; table.insert(AL.particles, obj) end
        elseif cls == "BasePart" and obj.CastShadow then
            table.insert(AL.shadows, {part=obj, value=true}); obj.CastShadow = false
        elseif cls == "Decal" and obj.Transparency < 1 then
            table.insert(AL.decals, {obj=obj, value=obj.Transparency}); obj.Transparency = 1
        elseif cls == "Texture" and obj.Transparency < 1 then
            table.insert(AL.textures, {obj=obj, value=obj.Transparency}); obj.Transparency = 1
        elseif cls == "BasePart" and obj.Material ~= ENUM.Material.Plastic then
            table.insert(AL.materials, {obj=obj, value=obj.Material})
            obj.Material = ENUM.Material.Plastic; obj.Reflectance = 0
        end
    end
    local POST = {BloomEffect=1, BlurEffect=1, SunRaysEffect=1, ColorCorrectionEffect=1, DepthOfFieldEffect=1}
    for _, obj in ipairs(Lighting:GetChildren()) do
        if POST[obj.ClassName] then
            if obj.Enabled then obj.Enabled = false; table.insert(AL.postEffects, obj) end
        elseif obj.ClassName == "Atmosphere" then
            table.insert(AL.atmospheres, {obj=obj, Density=obj.Density, Haze=obj.Haze, Glare=obj.Glare})
            obj.Density=0; obj.Haze=0; obj.Glare=0
        end
    end
    for _, obj in ipairs(SoundService:GetDescendants()) do
        if obj:IsA("Sound") and obj.Playing and obj.Volume > 0 then
            table.insert(AL.sounds, {sound=obj, volume=obj.Volume}); obj.Volume = 0
        end
    end
end
S.enableAntiLag = function()
    if S.antiLag.enabled then return end
    S.antiLag.enabled = true
    S.antiLag.lighting = {GlobalShadows=Lighting.GlobalShadows, ShadowSoftness=Lighting.ShadowSoftness,
        EnvironmentDiffuseScale=Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale=Lighting.EnvironmentSpecularScale, FogEnd=Lighting.FogEnd}
    pcall(function()
        Lighting.GlobalShadows=false; Lighting.ShadowSoftness=0
        Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0; Lighting.FogEnd=1e10
    end)
    S.scanAntiLag(); S.antiLag.rescanAt = tick() + 4
end
S.rescanAntiLag = function()
    if not S.antiLag.enabled then return end
    pcall(function() Lighting.GlobalShadows=false; Lighting.ShadowSoftness=0 end)
    S.scanAntiLag(); S.antiLag.rescanAt = tick() + 4
end
S.disableAntiLag = function()
    local AL = S.antiLag; AL.enabled = false
    for _, p in ipairs(AL.particles) do pcall(function() p.Enabled = true end) end; table.clear(AL.particles)
    for _, it in ipairs(AL.shadows) do pcall(function() it.part.CastShadow = it.value end) end; table.clear(AL.shadows)
    for _, it in ipairs(AL.decals) do pcall(function() it.obj.Transparency = it.value end) end; table.clear(AL.decals)
    for _, it in ipairs(AL.textures) do pcall(function() it.obj.Transparency = it.value end) end; table.clear(AL.textures)
    for _, it in ipairs(AL.materials) do pcall(function() it.obj.Material = it.value end) end; table.clear(AL.materials)
    for _, it in ipairs(AL.sounds) do pcall(function() it.sound.Volume = it.volume end) end; table.clear(AL.sounds)
    for _, fx in ipairs(AL.postEffects) do pcall(function() fx.Enabled = true end) end; table.clear(AL.postEffects)
    for _, it in ipairs(AL.atmospheres) do pcall(function() it.obj.Density=it.Density; it.obj.Haze=it.Haze; it.obj.Glare=it.Glare end) end
    table.clear(AL.atmospheres)
    if AL.lighting then
        pcall(function()
            Lighting.GlobalShadows=AL.lighting.GlobalShadows; Lighting.ShadowSoftness=AL.lighting.ShadowSoftness
            Lighting.EnvironmentDiffuseScale=AL.lighting.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale=AL.lighting.EnvironmentSpecularScale; Lighting.FogEnd=AL.lighting.FogEnd
        end)
        AL.lighting = nil
    end
end

S.cullModel = function(m)
    local s = {}
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then
            s[p] = {ltm=p.LocalTransparencyModifier, tr=p.Transparency}
            pcall(function() p.LocalTransparencyModifier=1; p.Transparency=1 end)
        end
    end
    S.renderCull.hidden[m] = s
end
S.uncullModel = function(m)
    local s = S.renderCull.hidden[m]; if not s then return end
    for p, v in pairs(s) do if p.Parent then pcall(function() p.LocalTransparencyModifier=v.ltm; p.Transparency=v.tr end) end end
    S.renderCull.hidden[m] = nil
end
S.scanRenderCull = function()
    local RC = S.renderCull; local hrp = S.cache.hrp; if not hrp then return end
    local pos = hrp.Position; local tSq = (S.renderCullDist or 500)^2
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= S.cache.char and not Players:GetPlayerFromCharacter(obj) then
            local prim = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if prim then
                local d = prim.Position - pos; local dsq = d.X*d.X + d.Y*d.Y + d.Z*d.Z
                if dsq > tSq then if not RC.hidden[obj] then S.cullModel(obj) end
                else if RC.hidden[obj] then S.uncullModel(obj) end end
            end
        end
    end
    for m in pairs(RC.hidden) do if not m.Parent then RC.hidden[m] = nil end end
    RC.rescanAt = tick() + 2
end
S.disableRenderCull = function()
    for m in pairs(S.renderCull.hidden) do S.uncullModel(m) end
    table.clear(S.renderCull.hidden)
end

S.hideAllOtherUI = function()
    local HU = S.hiddenUIs; table.clear(HU)
    for _, gui in ipairs(PG:GetChildren()) do
        if gui:IsA("ScreenGui") and gui ~= S.ui.screen and gui ~= S.ui.infoGui then
            if gui.Enabled then gui.Enabled = false; table.insert(HU, gui) end
        end
    end
end
S.restoreHiddenUI = function()
    for _, gui in ipairs(S.hiddenUIs) do pcall(function() gui.Enabled = true end) end
    table.clear(S.hiddenUIs)
end

S.sweepOverflow = function()
    local AL, RC, TR, PH, HU = S.antiLag, S.renderCull, S.texRem, S.petHider, S.hiddenUIs
    for i = #AL.particles,1,-1 do local p = AL.particles[i]; if not p or not p.Parent then table.remove(AL.particles, i) end end
    for i = #AL.shadows,1,-1 do local it = AL.shadows[i]; if not it.part or not it.part.Parent then table.remove(AL.shadows, i) end end
    for i = #AL.decals,1,-1 do local it = AL.decals[i]; if not it.obj or not it.obj.Parent then table.remove(AL.decals, i) end end
    for i = #AL.textures,1,-1 do local it = AL.textures[i]; if not it.obj or not it.obj.Parent then table.remove(AL.textures, i) end end
    for i = #AL.materials,1,-1 do local it = AL.materials[i]; if not it.obj or not it.obj.Parent then table.remove(AL.materials, i) end end
    for i = #AL.sounds,1,-1 do local it = AL.sounds[i]; if not it.sound or not it.sound.Parent then table.remove(AL.sounds, i) end end
    for i = #AL.postEffects,1,-1 do local fx = AL.postEffects[i]; if not fx or not fx.Parent then table.remove(AL.postEffects, i) end end
    for i = #AL.atmospheres,1,-1 do local it = AL.atmospheres[i]; if not it.obj or not it.obj.Parent then table.remove(AL.atmospheres, i) end end
    for m in pairs(RC.hidden) do if not m.Parent then RC.hidden[m] = nil end end
    for i = #TR.saved,1,-1 do local it = TR.saved[i]; if not it.obj or not it.obj.Parent then table.remove(TR.saved, i) end end
    for o in pairs(TR.seen) do if not o.Parent then TR.seen[o] = nil end end
    for i = #PH.own,1,-1 do if not PH.own[i].Parent then table.remove(PH.own, i) end end
    for i = #PH.all,1,-1 do if not PH.all[i].Parent then table.remove(PH.all, i) end end
    for i = #PH.machines,1,-1 do if not PH.machines[i].Parent then table.remove(PH.machines, i) end end
    for i = #HU,1,-1 do if not HU[i].Parent then table.remove(HU, i) end end
    for i = #S.activeNotifies,1,-1 do if not S.activeNotifies[i] or not S.activeNotifies[i].Parent then table.remove(S.activeNotifies, i) end end
    while #S.pingHistory > 10 do table.remove(S.pingHistory, 1) end
end

S.runPeriodicGc = function()
    if tick() - S.lastGcAt < 60 then return end
    S.lastGcAt = tick(); pcall(function() collectgarbage("collect") end)
end
S.runMemoryWatchdog = function()
    if tick() - S.lastMemCheckAt < 30 then return end
    S.lastMemCheckAt = tick()
    local mem = S.getMemoryMb(); if mem <= 0 then return end
    S.memMb = mem; if mem > S.peakMem then S.peakMem = mem end
    if S.memBaseline == 0 then S.memBaseline = mem end
    if mem - S.memBaseline > 400 then
        S.memWarnCount = S.memWarnCount + 1
        pcall(function() collectgarbage("collect") end); pcall(S.sweepOverflow)
    end
end
S.longRunProtection = function()
    local uptime = tick() - S.startAt; S.sessionUptime = uptime
    if uptime > 5 * 3600 and not S._didDeepClean then
        S._didDeepClean = true; pcall(S.sweepOverflow)
        pcall(function() collectgarbage("collect") end); S.startAt = tick()
    end
end

S.runAdaptive = function()
    if not S.adaptiveEnabled then return end
    if not (S.fastTrain or S.autoTrain) then return end
    if tick() - S.lastAdaptiveAt < 1 then return end
    S.lastAdaptiveAt = tick()
    local fps = S.avgFps; local th = S.adaptiveThreshold or 30
    local cap = S.adaptiveMaxRate or 5000
    local newRate
    if fps < th then
        local r = fps / th
        local factor = r < 0.4 and 0.4 or (r < 0.7 and 0.7 or 0.9)
        newRate = math.max(10, math.floor(S.fastRate * factor))
    else
        if fps > th * 1.15 then
            S.adaptiveStableCount = S.adaptiveStableCount + 1
            if S.adaptiveStableCount >= 2 then
                newRate = math.min(cap, S.fastRate + S.adaptiveStep)
                S.adaptiveStep = math.min(2000, S.adaptiveStep * 2)
                S.adaptiveStableCount = 0
            end
        else S.adaptiveStableCount = 0 end
    end
    if newRate and newRate ~= S.fastRate then
        S.fastRate = newRate
        if S.ui.rateBox then S.ui.rateBox.Text = tostring(newRate) end
    end
end

-- ============================================================
-- 任务注册
-- ============================================================
S.registerTask = function(t)
    t._failCount = 0; t._disabledUntil = 0
    table.insert(S.taskChain, t)
    table.sort(S.taskChain, function(a, b) return a.priority > b.priority end)
end

S.registerTask({ id="afk", priority=200,
    enabled=function() return not S.scriptPaused end,
    tick=function()
        if tick() - S.lastAFKClick >= S.antiAfkInterval then
            S.lastAFKClick = tick()
            local cam = Workspace.CurrentCamera
            pcall(function()
                VirtualUser:Button2Down(V2(0,0), cam.CFrame)
                task.wait(0.05)
                VirtualUser:Button2Up(V2(0,0), cam.CFrame)
            end)
        end
    end,
})

S.registerTask({ id="chest", priority=195,
    enabled=function() return S.autoChest and not S.scriptPaused end,
    tick=function()
        if S.isAnyBossAlive() then
            S.bossWasAlive = true; S.bossKilledAt = 0; S.chestTaskActive = false; return
        end
        if S.bossWasAlive and S.bossKilledAt == 0 then
            S.bossKilledAt = tick(); S.bossWasAlive = false
            local hrp = S.cache.hrp; if hrp then S.bossDeathPos = hrp.Position end
        end
        if S.bossKilledAt == 0 then return end
        local sinceDeath = tick() - S.bossKilledAt
        if sinceDeath < S.chestDelay then
            local hrp = S.cache.hrp
            if hrp then
                pcall(function() hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0) end)
                S.updateGravityLock(S.bossDeathPos or hrp.Position)
            end
            return
        end
        local chest = S.findNearbyChest()
        if not chest then
            if sinceDeath > 30 then S.bossKilledAt = 0; S.releaseGravityLock() end
            return
        end
        local hrp = S.cache.hrp; if not hrp then return end
        local targetPos = chest.Position + V3(0, 4, 0)
        pcall(function()
            hrp.CFrame = CN(targetPos)
            hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0)
        end)
        S.updateGravityLock(targetPos)
        if not S.chestTaskActive then
            S.chestTaskActive = true
            task.spawn(function()
                pcall(function() VirtualInputManager:SendKeyEvent(true, ENUM.KeyCode.E, false, game) end)
                task.wait(1)
                local endAt = tick() + 1
                while tick() < endAt do
                    pcall(function()
                        VirtualInputManager:SendKeyEvent(true, ENUM.KeyCode.E, false, game)
                        task.wait(0.05)
                        VirtualInputManager:SendKeyEvent(false, ENUM.KeyCode.E, false, game)
                    end)
                    task.wait(0.05)
                end
                pcall(function() VirtualInputManager:SendKeyEvent(false, ENUM.KeyCode.E, false, game) end)
                pcall(function()
                    for _, obj in ipairs(chest:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") and obj.Enabled then fireproximityprompt(obj) end
                    end
                end)
                task.wait(3)
                S.chestTaskActive = false
            end)
        end
    end,
})

S.registerTask({ id="boss", priority=190,
    enabled=function() return S.autoBoss and not S.scriptPaused end,
    onEnable=function()
        if not S.threads.bossPunch then
            S.spawnThread("bossPunch", S.bossPunchLoop)
            S.spawnThread("bossScan", S.bossScanLoop)
            S.startBossHover()
        end
    end,
    onDisable=function()
        if S.bossHoverConn then pcall(function() S.bossHoverConn:Disconnect() end); S.bossHoverConn = nil end
        S.cancelThread("bossPunch"); S.cancelThread("bossScan")
        if S._bossSavedDual ~= nil then S.dualEnabled = S._bossSavedDual; S._bossSavedDual = nil end
        if S._bossSavedMachine ~= nil then S.machineState.enabled = S._bossSavedMachine; S._bossSavedMachine = nil end
        S._bossActive = false
    end,
    tick=function()
        if S.isAnyBossAlive() and S.killEnabled then
            S.killEnabled = false
            if S.ui.killToggle then S.ui.killToggle.set(false) end
            S.notify("检测到 Boss，自动杀戮已暂停", 4)
        end
        local bossAlive = S.isAnyBossAlive()
        if bossAlive and not S._bossActive then
            S._bossActive = true
            if S.machineState.enabled then
                S._bossSavedMachine = true
                S.machineState.enabled = false
                S.notify("Boss 出现，器械暂停", 3)
            end
            if S.dualEnabled then
                S._bossSavedDual = true
                S.dualEnabled = false
            end
        elseif (not bossAlive) and S._bossActive then
            S._bossActive = false
            if S._bossSavedMachine ~= nil then S.machineState.enabled = S._bossSavedMachine; S._bossSavedMachine = nil end
            if S._bossSavedDual ~= nil then S.dualEnabled = S._bossSavedDual; S._bossSavedDual = nil end
        end
        if bossAlive ~= S._lastBossAlive then
            S._lastBossAlive = bossAlive
            S.setRebirthPause("boss", bossAlive)
            if bossAlive then S.applyPetPreset("boss") else S.applyPetPreset("train") end
        end
    end,
})

S.registerTask({ id="kingKill", priority=180,
    enabled=function() return S.autoKingKill and not S.scriptPaused and not (S.autoBoss and S.isAnyBossAlive()) end,
    onDisable=function() S.kingKillTarget = nil; S.kingKillActive = false; S.restoreAllEnlarged() end,
    tick=function() S.runKingKillTick() end,
})

S.registerTask({ id="kill", priority=150,
    enabled=function()
        return S.killEnabled and not S.scriptPaused and not S.kingKillActive
            and not (S.autoBoss and S.isAnyBossAlive())
    end,
    onEnable=function()
        S.killSavedState = {autoTeleport=S.autoTeleport}
        S.autoTeleport = false
        if S.ui.teleToggle then S.ui.teleToggle.set(false) end
        S.killTarget = nil; S.killScanAt = 0; S.dualCurrentMode = "punch"
        S.setRebirthPause("kill", true)
        S.applyPetPreset("kill")
    end,
    onDisable=function()
        if S.killSavedState then
            S.autoTeleport = S.killSavedState.autoTeleport
            if S.ui.teleToggle then S.ui.teleToggle.set(S.autoTeleport) end
            S.killSavedState = nil
        end
        S.killTarget = nil; S.toolOwnedByKill = false; S.dualCurrentMode = "punch"
        S.setRebirthPause("kill", false)
        S.restoreAllEnlarged()
        S.applyPetPreset("train")
    end,
    tick=function() S.runKillTick() end,
})

S.registerTask({ id="dual", priority=140,
    enabled=function()
        return S.dualEnabled and S.killEnabled and S.killTarget ~= nil
            and (S.autoTrain or S.fastTrain) and not S.kingKillActive
            and not (S.autoBoss and S.isAnyBossAlive())
    end,
    onDisable=function() S.dualCurrentMode = "punch" end,
    tick=function() S.updateDualTool() end,
})

S.registerTask({ id="rebirth", priority=120,
    enabled=function() return S.autoRebirth and not S.scriptPaused end,
    tick=function()
        if S.rebirthTarget > 0 and S.stat(LP, "Rebirths") >= S.rebirthTarget then
            S.autoRebirth = false
            S.notify("已达目标重生 " .. S.rebirthTarget .. "，自动重生已关闭", 6)
            if S.ui.rebirthToggle then S.ui.rebirthToggle.set(false) end
            return
        end
        local interval = 1 / math.max(1, S.rebirthRate)
        if tick() - S.lastRebirthAt >= interval then
            S.lastRebirthAt = tick()
            S.fireRebirth()
        end
    end,
})

S.registerTask({ id="wheel", priority=110,
    enabled=function() return S.autoWheel and not S.scriptPaused end,
    onEnable=function()
        S.spawnThread("wheel", function()
            while S.autoWheel and not S.destroyed do
                pcall(function()
                    local r = ReplicatedStorage:FindFirstChild("rEvents")
                    local remote = r and r:FindFirstChild("openFortuneWheelRemote")
                    local s = ReplicatedStorage:FindFirstChild("shared")
                    local cat = s and s:FindFirstChild("catalogs")
                    local wc = cat and cat:FindFirstChild("fortuneWheelChances")
                    local wheel = wc and wc:FindFirstChild("Fortune Wheel")
                    if remote and wheel then
                        if remote:IsA("RemoteFunction") then remote:InvokeServer("openFortuneWheel", wheel)
                        else remote:FireServer("openFortuneWheel", wheel) end
                    end
                end)
                task.wait(1)
            end
        end)
    end,
    onDisable=function() S.cancelThread("wheel") end,
    tick=function() end,
})

S.registerTask({ id="machine", priority=101,
    enabled=function()
        return S.machineState.enabled and not S.scriptPaused
            and not S.killEnabled and not S.kingKillActive
            and not (S.autoBoss and S.isAnyBossAlive())
            and not S._bossActive
    end,
    onDisable=function() S.forceReleaseGravity() end,
    tick=function()
        S.teleportToMachine()
        if S.machineState.using and tick() - S.machineState.triedAt > 5 then
            S.machineState.using = false
            S.machineState.triedAt = tick()
            S.tryCancelMachine()
        end
    end,
})

S.registerTask({ id="teleport", priority=100,
    enabled=function()
        return S.autoTeleport and not S.scriptPaused and not S.killEnabled
            and not S.kingKillActive and not (S.autoBoss and S.isAnyBossAlive())
            and not S.machineState.enabled and not S._bossActive
    end,
    onDisable=function()
        task.wait(0.1)
        if not S.autoTeleport and not S.killEnabled and not S.kingKillActive
           and not S.autoBoss and not S.teleportLoopEnabled and not S.machineState.enabled
           and not S.fastTrain and not S.autoTrain then
            S.forceReleaseGravity()
        end
    end,
    tick=function()
        if tick() - S.lastTeleportAt >= 0.05 then
            S.lastTeleportAt = tick()
            local hrp = S.cache.hrp
            if hrp then
                local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
                local cf = portal and CN(portal.Position + V3(0, 6, 0)) or CN(V3(-8727.1, 409.7, -5796.4))
                pcall(function()
                    hrp.CFrame = cf
                    hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0)
                end)
                S.updateGravityLock(cf.Position)
            end
        end
    end,
})

-- ★ 单点传送（不是循环）
S.registerTask({ id="teleportLoop", priority=95,
    enabled=function()
        return S.teleportLoopEnabled and not S.scriptPaused and not S.autoTeleport
            and not S.killEnabled and not S.kingKillActive
            and not (S.autoBoss and S.isAnyBossAlive())
            and not S.machineState.enabled and not S._bossActive
    end,
    onDisable=function()
        task.wait(0.1)
        if not S.autoTeleport and not S.killEnabled and not S.kingKillActive
           and not S.autoBoss and not S.machineState.enabled then
            S.forceReleaseGravity()
        end
    end,
    tick=function()
        -- ★ 只在每个点停 0.8 秒，然后传下一个；但这版是"单点传送"，不循环
        -- 用户意思是：单点反复传送（循环到同一个点），而不是顺序多个点
        if tick() - S.teleportLoopLastAt >= 0.8 then
            S.teleportLoopLastAt = tick()
            local tp = S.TELEPORTS[S.teleportLoopIndex]  -- 用户指定的单点
            if tp then
                local hrp = S.cache.hrp
                if hrp then
                    hrp.CFrame = CN(tp.pos)
                    hrp.AssemblyLinearVelocity = V3(0,0,0)
                    hrp.AssemblyAngularVelocity = V3(0,0,0)
                end
                S.updateGravityLock(tp.pos)
            end
        end
    end,
})

S.registerTask({ id="camera", priority=90,
    enabled=function()
        return S.killEnabled or S.autoTeleport or S.kingKillActive or S.autoBoss
            or S.teleportLoopEnabled or S.autoTrain or S.fastTrain or S.machineState.enabled
    end,
    tick=function()
        if tick() - S.lastCameraFix >= 0.5 then
            S.lastCameraFix = tick()
            local cam = Workspace.CurrentCamera; local hum = S.cache.hum
            if cam and hum and hum.Parent then
                pcall(function()
                    if cam.CameraSubject ~= hum then cam.CameraSubject = hum end
                    if cam.CameraType ~= ENUM.CameraType.Custom then cam.CameraType = ENUM.CameraType.Custom end
                end)
            end
        end
    end,
})

S.registerTask({ id="info", priority=85,
    enabled=function() return S.infoWindowEnabled end,
    tick=function()
        if tick() - S.strengthCheckAt >= 1 then
            S.strengthCheckAt = tick()
            local s = S.myStrength()
            if S.sessionStartStrength == nil then
                S.sessionStartStrength = s; S.lastStrengthSnapshot = s
            else
                local d = s - S.lastStrengthSnapshot
                if d >= 0 then S.strengthPerSec = S.strengthPerSec * 0.7 + d * 0.3 end
                S.lastStrengthSnapshot = s
            end
        end
        if tick() - S.repCache.lastRefresh >= 1 then
            S.repCache.lastRefresh = tick(); S.refreshRepSpeed()
        end
        if tick() - S.lastPingCheck >= 1 then
            S.lastPingCheck = tick(); S.ping = S.updatePingSmooth()
        end
        S.updateRebirthRate()
        if tick() - S.infoLastRefresh >= 0.2 then
            S.infoLastRefresh = tick(); S.refreshInfoWindow()
        end
    end,
})

S.registerTask({ id="petbuy", priority=82,
    enabled=function() return S.autoPetBuy and not S.scriptPaused and S.selectedPet ~= "" end,
    tick=function()
        if tick() - (S._petBuyLast or 0) >= 0.5 then
            S._petBuyLast = tick(); S.buyPet(S.selectedPet)
        end
    end,
})

S.registerTask({ id="tool", priority=79,
    enabled=function()
        if S._bossActive or (S.autoBoss and S.isAnyBossAlive()) then return false end
        return (S.autoTrain or S.fastTrain)
            and not S.toolCooldown and not S.toolOwnedByKill and not S.kingKillActive
            and not S.scriptPaused and S.machineState.mode ~= "machine"
    end,
    tick=function()
        if tick() - S.lastToolCheck < 0.1 then return end
        S.lastToolCheck = tick()
        local sel = {}
        if S.toolPushups then table.insert(sel, S.TOOL_KW.pushups) end
        if S.toolHandstands then table.insert(sel, S.TOOL_KW.handstands) end
        if S.toolSitups then table.insert(sel, S.TOOL_KW.situps) end
        if S.toolDumbbell then table.insert(sel, S.TOOL_KW.dumbbell) end
        if #sel == 0 then S._missingSince = 0; return end
        local equipped = false
        for _, kw in ipairs(sel) do if S.tryEquip(kw) then equipped = true; break end end
        if equipped then S._missingSince = 0; return end
        local anyExist = false
        for _, kw in ipairs(sel) do if S.toolExists(kw) then anyExist = true; break end end
        if anyExist then S._missingSince = 0; return end
        if S._missingSince == 0 then S._missingSince = tick() end
        if tick() - S._missingSince < 1.0 then return end
        if tick() - S._lastSuicide < 60 then return end
        S._lastSuicide = tick()
        S._suicideCount = (S._suicideCount or 0) + 1
        if S._suicideCount <= 3 then
            S.toolCooldown = true
            S.notify(string.format("未找到训练工具，第 %d 次重生", S._suicideCount), 4)
            S.suicide()
            task.delay(15, function() if not S.destroyed then S.toolCooldown = false end end)
        else
            S.notify("连续找不到工具，已停止自动切换", 6)
        end
    end,
})

S.registerTask({ id="train", priority=60,
    enabled=function()
        return (S.autoTrain or S.fastTrain) and not S.kingKillActive
            and not S.autoPackRebirth and not S.scriptPaused
    end,
    tick=function(dt)
        local rate = S.fastTrain and S.fastRate or (S.autoTrain and 10 or 0)
        if rate <= 0 then return end
        S.trainAccum = S.trainAccum + rate * dt
        local count = math.floor(S.trainAccum)
        if count <= 0 then return end
        S.trainAccum = S.trainAccum - count
        if count > 400 then S.trainAccum = S.trainAccum + (count - 400); count = 400 end
        local ev = S.getMuscleEvent()
        if not ev then S.muscleEventRef = nil; ev = S.getMuscleEvent() end
        if not ev then return end
        if ev.Parent ~= LP then S.muscleEventRef = nil; ev = S.getMuscleEvent() end
        if not ev then return end
        task.spawn(function()
            pcall(function()
                for i = 1, count do
                    ev:FireServer("rep")
                    if i % 100 == 0 then task.wait() end
                end
            end)
        end)
    end,
})

S.registerTask({ id="packrebirth", priority=56,
    enabled=function() return S.autoPackRebirth and not S.scriptPaused end,
    onEnable=function() S.spawnThread("packRebirth", S.packRebirthLoop) end,
    onDisable=function() S.cancelThread("packRebirth") end,
    tick=function() end,
})

S.registerTask({ id="egg", priority=58,
    enabled=function() return S.autoEatEgg and not S.scriptPaused end,
    onEnable=function() S.spawnThread("egg", S.eatEggLoop) end,
    onDisable=function() S.cancelThread("egg") end,
    tick=function() end,
})

S.registerTask({ id="rejoin", priority=50,
    enabled=function() return S.autoRejoinEnabled and not S.rejoinPending end,
    tick=function() S.checkRejoin() end,
})

S.registerTask({ id="emergency", priority=49,
    enabled=function() return S.emergencyRejoin end,
    tick=function() S.emergencyRejoinCheck() end,
})

S.registerTask({ id="antilag", priority=40,
    enabled=function() return S.antiLagEnabled end,
    onEnable=function() pcall(S.enableAntiLag) end,
    onDisable=function() pcall(S.disableAntiLag) end,
    tick=function() if S.antiLag.enabled and tick() >= S.antiLag.rescanAt then S.rescanAntiLag() end end,
})

S.registerTask({ id="cull", priority=35,
    enabled=function() return S.renderCullEnabled end,
    onEnable=function() S.renderCull.rescanAt = 0 end,
    onDisable=function() pcall(S.disableRenderCull) end,
    tick=function() if tick() >= S.renderCull.rescanAt then S.scanRenderCull() end end,
})

S.registerTask({ id="hider", priority=30,
    enabled=function() return S.hideOwnPets or S.hideAllPets or S.hideMachines end,
    onEnable=function() S.petHider.rescanAt = 0 end,
    onDisable=function() pcall(S.restoreHiddenPets); pcall(S.restoreHiddenMachines) end,
    tick=function()
        if tick() >= S.petHider.rescanAt then
            pcall(S.restoreHiddenPets); pcall(S.restoreHiddenMachines)
            S.scanHidePets(); S.scanHideMachines()
        end
    end,
})

S.registerTask({ id="tex", priority=25,
    enabled=function() return S.textureRemoverEnabled end,
    onEnable=function() pcall(S.enableTex) end,
    onDisable=function() pcall(S.disableTex) end,
    tick=function() if S.texRem.enabled and tick() >= S.texRem.rescanAt then S.rescanTex() end end,
})

S.registerTask({ id="friend", priority=22,
    enabled=function() return S.friendWhitelist end,
    onEnable=function() if not S.friendWL.loaded then S.refreshFriendList() end end,
    tick=function()
        if S.friendWL.refreshing then return end
        if not S.friendWL.loaded then S.refreshFriendList()
        elseif tick() - S.friendWL.lastRefresh >= 300 then S.refreshFriendList() end
    end,
})

S.registerTask({ id="sweep", priority=20,
    enabled=function() return true end,
    tick=function()
        if tick() - S.lastSweepAt >= 15 then S.lastSweepAt = tick(); pcall(S.sweepOverflow) end
    end,
})

S.registerTask({ id="save", priority=10,
    enabled=function() return true end,
    tick=function()
        if tick() - S.lastSaveAt >= 2 then S.lastSaveAt = tick(); task.spawn(S.saveConfig) end
        pcall(S.runPeriodicGc); pcall(S.runMemoryWatchdog); pcall(S.longRunProtection)
    end,
})

S.setRebirthPause = function(reason, on)
    local reasons = S.rebirthPausedReasons
    if on then
        if reasons[reason] then return end
        reasons[reason] = true
        if not S.rebirthSavedBySystem and S.autoRebirth then
            S.rebirthSavedBySystem = true; S.autoRebirth = false
            if S.ui.rebirthToggle then S.ui.rebirthToggle.set(false) end
        end
    else
        if not reasons[reason] then return end
        reasons[reason] = nil
        if not next(reasons) and S.rebirthSavedBySystem then
            S.rebirthSavedBySystem = false; S.autoRebirth = true
            if S.ui.rebirthToggle then S.ui.rebirthToggle.set(true) end
        end
    end
end

-- ============================================================
-- 心跳
-- ============================================================
S.updateGlobal = function(dt)
    local wantZero = S.killEnabled or S.autoTeleport or S.kingKillActive
        or S.teleportLoopEnabled or S.machineState.enabled
        or (S.autoBoss and S.autoChest and S.bossKilledAt > 0 and (tick() - S.bossKilledAt) < 30)
        or ((S.autoTrain or S.fastTrain) and not S.scriptPaused)
    if wantZero then
        if Workspace.Gravity ~= 0 then pcall(function() Workspace.Gravity = 0 end) end
    else
        if Workspace.Gravity ~= S.originalGravity then
            pcall(function() Workspace.Gravity = S.originalGravity end)
        end
    end
    S.fpsWinTime = S.fpsWinTime + dt; S.fpsWinFrames = S.fpsWinFrames + 1
    if S.fpsWinTime >= 0.5 then
        S.avgFps = S.fpsWinFrames / S.fpsWinTime
        S.fpsWinTime = 0; S.fpsWinFrames = 0
    end
    if S.sessionStartStrength == nil then
        S.sessionStartStrength = S.myStrength(); S.lastStrengthSnapshot = S.sessionStartStrength
    end
    if S.adaptiveEnabled and (S.fastTrain or S.autoTrain) then
        pcall(S.runAdaptive)
    end
    if tick() - (S._cfSetAt or 0) > 0.15 then S._cfPriority = 0 end
    -- ★ 关键修复：只在真正需要时禁用移动；一旦没有任何阻止移动的任务，恢复 WalkSpeed
    local blockMove = S.killEnabled or S.autoTeleport or S.kingKillActive
        or S.teleportLoopEnabled or S.machineState.enabled or S._bossActive
    local hum = S.cache.hum
    if hum then
        if blockMove then
            if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
        else
            -- 恢复 WalkSpeed（防止关闭后无法移动）
            if hum.WalkSpeed == 0 then
                hum.WalkSpeed = S._origWalkSpeed or 16
            end
        end
    end
end

S.onHeartbeat = function(dt)
    if S.destroyed then return end
    S.time = tick()
    S.refreshCache()
    S.updateGlobal(dt)
    if S.gravityLock.active then
        local hrp = S.cache.hrp
        if hrp then
            local pos = (S.gravityLock.alignPos and S.gravityLock.alignPos.Position) or hrp.Position
            S.updateGravityLock(pos)
        end
    end
    if S.scriptPaused then
        local hum = S.cache.hum
        if hum then
            hum:Move(V3(0,0,0), false)
            if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
        end
    end
    local now = tick()
    local TC = S.taskChain
    for i = 1, #TC do
        local task_ = TC[i]
        if S.scriptPaused and not S.essentialTasks[task_.id] then
            -- skip
        elseif task_._disabledUntil > 0 and now < task_._disabledUntil then
            -- skip
        else
            if task_._disabledUntil > 0 and now >= task_._disabledUntil then
                task_._disabledUntil = 0; task_._failCount = 0
            end
            local ok, en = pcall(task_.enabled)
            if not ok then en = false end
            if not en then
                if task_._wasActive then
                    task_._wasActive = false
                    if task_.onDisable then pcall(task_.onDisable) end
                end
            else
                if not task_._wasActive then
                    task_._wasActive = true
                    if task_.onEnable then pcall(task_.onEnable) end
                end
                local ok2, err = pcall(task_.tick, dt)
                if not ok2 then
                    task_._failCount = (task_._failCount or 0) + 1
                    if task_._failCount >= 10 then
                        task_._disabledUntil = tick() + 30; task_._failCount = 0
                        if task_._wasActive and task_.onDisable then
                            pcall(task_.onDisable); task_._wasActive = false
                        end
                    end
                else
                    if task_._failCount and task_._failCount > 0 then task_._failCount = 0 end
                end
            end
        end
    end
end

-- ============================================================
-- 配置（带继承）
-- ============================================================
S.saveConfig = function()
    if S.destroyed or type(writefile) ~= "function" then return end
    pcall(function()
        if S.ui.main then S.savedMainPos = S.serializePos(S.ui.main.Position) end
        local inf = S.Info
        if inf.frames and inf.frames.frame then
            S.savedInfoPos = S.serializePos(inf.frames.frame.Position)
            S.savedInfoSize = S.serializeSize(inf.frames.frame.Size)
        end
        if S.ui.pillFrame then S.UIState.pillPos = S.serializePos(S.ui.pillFrame.Position) end
    end)
    local data = {
        autoTrain=S.autoTrain, fastTrain=S.fastTrain, fastRate=S.fastRate,
        toolDumbbell=S.toolDumbbell, toolPushups=S.toolPushups,
        toolHandstands=S.toolHandstands, toolSitups=S.toolSitups,
        adaptiveEnabled=S.adaptiveEnabled, adaptiveThreshold=S.adaptiveThreshold,
        adaptiveMaxRate=S.adaptiveMaxRate,
        autoRebirth=S.autoRebirth, rebirthRate=S.rebirthRate, rebirthTarget=S.rebirthTarget,
        autoPackRebirth=S.autoPackRebirth, autoEatEgg=S.autoEatEgg,
        eatEggBatch=S.eatEggBatch, giftAmount=S.giftAmount, selectedEggTarget=S.selectedEggTarget,
        autoTeleport=S.autoTeleport, autoChest=S.autoChest,
        chestDelay=S.chestDelay, chestHoldTime=S.chestHoldTime,
        killEnabled=S.killEnabled, killThreshold=S.killThreshold, dualEnabled=S.dualEnabled,
        killGoodOnly=S.killGoodOnly, killBadOnly=S.killBadOnly, friendWhitelist=S.friendWhitelist,
        autoKingKill=S.autoKingKill, antiLagEnabled=S.antiLagEnabled,
        renderCullEnabled=S.renderCullEnabled, renderCullDist=S.renderCullDist,
        hideOwnPets=S.hideOwnPets, hideAllPets=S.hideAllPets, hideMachines=S.hideMachines,
        textureRemoverEnabled=S.textureRemoverEnabled, hideUIEnabled=S.hideUIEnabled,
        infoWindowEnabled=S.infoWindowEnabled, formatEnabled=S.formatEnabled,
        uiBgOpacity=S.uiBgOpacity, uiPageOpacity=S.uiPageOpacity,
        infoBgOpacity=S.infoBgOpacity, infoScale=S.infoScale,
        uiWidthPct=S.uiWidthPct, uiHeightPct=S.uiHeightPct,
        savedMainPos=S.savedMainPos, savedInfoPos=S.savedInfoPos, savedInfoSize=S.savedInfoSize,
        autoBoss=S.autoBoss, bossHeight=S.bossHeight, bossHeightMode=S.bossHeightMode,
        autoRejoinEnabled=S.autoRejoinEnabled, rejoinCondition=S.rejoinCondition,
        rejoinEnableMem=S.rejoinEnableMem, rejoinEnableFps=S.rejoinEnableFps, rejoinEnablePing=S.rejoinEnablePing,
        rejoinServerMode=S.rejoinServerMode, rejoinPrivateServerId=S.rejoinPrivateServerId,
        rejoinMemThreshold=S.rejoinMemThreshold, rejoinFpsThreshold=S.rejoinFpsThreshold,
        rejoinPingThreshold=S.rejoinPingThreshold,
        machineEnabled=S.machineState.enabled, machineMode=S.machineState.mode,
        machineTargetName=S.machineState.targetName,
        machineGymFilter=S.machineState.gymFilter,
        machineMachineFilter=S.machineState.machineFilter,
        machineIndexFilter=S.machineState.indexFilter,
        teleportLoopEnabled=S.teleportLoopEnabled, teleportLoopIndex=S.teleportLoopIndex,
        emergencyRejoin=S.emergencyRejoin, fontScale=S.fontScale,
        UIState_pillPos=S.UIState.pillPos,
        petPresetAutoSwitch=S.petPreset.autoSwitch,
        petPresetTrain=S.petPreset.train, petPresetRebirth=S.petPreset.rebirth,
        petPresetKill=S.petPreset.kill, petPresetBoss=S.petPreset.boss,
        antiAfkInterval=S.antiAfkInterval,
        configVersion=VERSION,
    }
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, data)
    if ok and enc then pcall(writefile, CONFIG_FILE, enc) end
end

S.applyConfigData = function(data)
    local function b(k, f) if type(data[k]) == "boolean" then return data[k] end return f end
    local function n(k, f, lo, hi)
        local v = tonumber(data[k]); if not v then return f end
        v = math.floor(v); if lo then v = math.max(lo, v) end; if hi then v = math.min(hi, v) end
        return v
    end
    local function fl(k, f, lo, hi)
        local v = tonumber(data[k]); if not v then return f end
        if lo then v = math.max(lo, v) end; if hi then v = math.min(hi, v) end
        return v
    end
    local function s_(k, f) if type(data[k]) == "string" then return data[k] end return f end
    S.autoTrain=b("autoTrain",S.autoTrain); S.fastTrain=b("fastTrain",S.fastTrain)
    S.fastRate=n("fastRate",S.fastRate,1,50000)
    S.toolDumbbell=b("toolDumbbell",S.toolDumbbell); S.toolPushups=b("toolPushups",S.toolPushups)
    S.toolHandstands=b("toolHandstands",S.toolHandstands); S.toolSitups=b("toolSitups",S.toolSitups)
    S.adaptiveEnabled=b("adaptiveEnabled",S.adaptiveEnabled)
    S.adaptiveThreshold=n("adaptiveThreshold",S.adaptiveThreshold,10,120)
    S.adaptiveMaxRate=n("adaptiveMaxRate",S.adaptiveMaxRate,100,50000)
    S.autoRebirth=b("autoRebirth",S.autoRebirth); S.rebirthRate=n("rebirthRate",S.rebirthRate,1,100)
    S.rebirthTarget=n("rebirthTarget",S.rebirthTarget,0,1000000)
    S.autoPackRebirth=b("autoPackRebirth",S.autoPackRebirth)
    S.autoEatEgg=b("autoEatEgg",S.autoEatEgg)
    S.eatEggBatch=n("eatEggBatch",S.eatEggBatch,1,100)
    S.giftAmount=n("giftAmount",S.giftAmount,0,9999)
    S.selectedEggTarget=s_("selectedEggTarget",S.selectedEggTarget)
    S.autoTeleport=b("autoTeleport",S.autoTeleport); S.autoChest=b("autoChest",S.autoChest)
    S.chestDelay=n("chestDelay",S.chestDelay,0,30); S.chestHoldTime=n("chestHoldTime",S.chestHoldTime,1,10)
    S.killEnabled=b("killEnabled",S.killEnabled); S.killThreshold=n("killThreshold",S.killThreshold,1,100)
    S.dualEnabled=b("dualEnabled",S.dualEnabled)
    S.killGoodOnly=b("killGoodOnly",S.killGoodOnly); S.killBadOnly=b("killBadOnly",S.killBadOnly)
    S.friendWhitelist=b("friendWhitelist",S.friendWhitelist); S.autoKingKill=b("autoKingKill",S.autoKingKill)
    S.antiLagEnabled=b("antiLagEnabled",S.antiLagEnabled)
    S.renderCullEnabled=b("renderCullEnabled",S.renderCullEnabled)
    S.renderCullDist=n("renderCullDist",S.renderCullDist,100,5000)
    S.hideOwnPets=b("hideOwnPets",S.hideOwnPets); S.hideAllPets=b("hideAllPets",S.hideAllPets)
    S.hideMachines=b("hideMachines",S.hideMachines)
    S.textureRemoverEnabled=b("textureRemoverEnabled",S.textureRemoverEnabled)
    S.hideUIEnabled=b("hideUIEnabled",S.hideUIEnabled)
    S.infoWindowEnabled=b("infoWindowEnabled",S.infoWindowEnabled)
    S.formatEnabled=b("formatEnabled",S.formatEnabled)
    S.uiBgOpacity=fl("uiBgOpacity",S.uiBgOpacity,0.3,1.0)
    S.uiPageOpacity=fl("uiPageOpacity",S.uiPageOpacity,0.3,1.0)
    S.infoBgOpacity=fl("infoBgOpacity",S.infoBgOpacity,0.3,1.0)
    S.infoScale=n("infoScale",S.infoScale,60,200)
    S.uiWidthPct=n("uiWidthPct",S.uiWidthPct,30,90); S.uiHeightPct=n("uiHeightPct",S.uiHeightPct,30,90)
    if type(data.savedMainPos)=="table" then S.savedMainPos=data.savedMainPos end
    if type(data.savedInfoPos)=="table" then S.savedInfoPos=data.savedInfoPos end
    if type(data.savedInfoSize)=="table" then S.savedInfoSize=data.savedInfoSize end
    S.autoBoss=b("autoBoss",S.autoBoss); S.bossHeight=n("bossHeight",S.bossHeight,0,200)
    S.bossHeightMode=s_("bossHeightMode",S.bossHeightMode)
    S.autoRejoinEnabled=b("autoRejoinEnabled",S.autoRejoinEnabled)
    S.rejoinCondition=s_("rejoinCondition",S.rejoinCondition)
    S.rejoinEnableMem=b("rejoinEnableMem",S.rejoinEnableMem)
    S.rejoinEnableFps=b("rejoinEnableFps",S.rejoinEnableFps)
    S.rejoinEnablePing=b("rejoinEnablePing",S.rejoinEnablePing)
    S.rejoinServerMode=s_("rejoinServerMode",S.rejoinServerMode)
    S.rejoinPrivateServerId=s_("rejoinPrivateServerId",S.rejoinPrivateServerId)
    S.rejoinMemThreshold=n("rejoinMemThreshold",S.rejoinMemThreshold,500,100000)
    S.rejoinFpsThreshold=n("rejoinFpsThreshold",S.rejoinFpsThreshold,1,60)
    S.rejoinPingThreshold=n("rejoinPingThreshold",S.rejoinPingThreshold,100,5000)
    S.machineState.enabled=b("machineEnabled",S.machineState.enabled)
    S.machineState.mode=s_("machineMode",S.machineState.mode)
    S.machineState.targetName=s_("machineTargetName",S.machineState.targetName)
    S.machineState.gymFilter=s_("machineGymFilter",S.machineState.gymFilter)
    S.machineState.machineFilter=s_("machineMachineFilter",S.machineState.machineFilter)
    S.machineState.indexFilter=n("machineIndexFilter",S.machineState.indexFilter,0,100)
    S.teleportLoopEnabled=b("teleportLoopEnabled",S.teleportLoopEnabled)
    S.teleportLoopIndex=n("teleportLoopIndex",S.teleportLoopIndex,1,#S.TELEPORTS)
    S.emergencyRejoin=b("emergencyRejoin",S.emergencyRejoin)
    S.fontScale=fl("fontScale",S.fontScale,0.8,1.6)
    if type(data.UIState_pillPos)=="table" then S.UIState.pillPos=data.UIState_pillPos end
    S.petPreset.autoSwitch=b("petPresetAutoSwitch",S.petPreset.autoSwitch)
    if type(data.petPresetTrain)=="table" then S.petPreset.train=data.petPresetTrain end
    if type(data.petPresetRebirth)=="table" then S.petPreset.rebirth=data.petPresetRebirth end
    if type(data.petPresetKill)=="table" then S.petPreset.kill=data.petPresetKill end
    if type(data.petPresetBoss)=="table" then S.petPreset.boss=data.petPresetBoss end
    S.antiAfkInterval=n("antiAfkInterval",S.antiAfkInterval,60,1140)
end

S.loadConfig = function()
    -- ★ 优先读自己；没有就读老版本
    local function tryLoad(file)
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
        local exists = false
        pcall(function() exists = isfile(file) end)
        if not exists then return nil end
        local ok, content = pcall(readfile, file)
        if not ok or type(content) ~= "string" then return nil end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, content)
        if not ok2 or type(data) ~= "table" then return nil end
        return data
    end
    local data = tryLoad(CONFIG_FILE)
    if not data then
        for _, oldFile in ipairs(OLD_CONFIGS) do
            data = tryLoad(oldFile)
            if data then
                print("[MK v39] 从旧版本继承配置：" .. oldFile)
                break
            end
        end
    end
    if data then S.applyConfigData(data) end
end

-- ============================================================
-- UI 构建
-- ============================================================
S.buildUI = function()
    local TH = S.theme
    local screen = S.create("ScreenGui", {
        Name="MK_AUTO_UI", ResetOnSpawn=false,
        ZIndexBehavior=ENUM.ZIndexBehavior.Sibling, DisplayOrder=99999,
    }, PG)
    S.ui.screen = screen

    -- ★ 确认弹窗（关闭脚本 / 删除配置）
    S.showConfirm = function(title, desc, onYes, onNo)
        if S.UIState.confirmOpen then return end
        S.UIState.confirmOpen = true
        local overlay = S.create("Frame", {
            Name="ConfirmOverlay", Size=UD2(1,0,1,0),
            BackgroundColor3=C3(0,0,0), BackgroundTransparency=0.5,
            BorderSizePixel=0, ZIndex=2000, Active=true,
        }, screen)
        local box = S.create("Frame", {
            AnchorPoint=V2(0.5, 0.5), Position=UD2(0.5, 0, 0.5, 0),
            Size=UDO(400, 200), BackgroundColor3=TH.Surface,
            BorderSizePixel=0, ZIndex=2001,
        }, overlay)
        S.corner(box, 12); S.stroke(box, TH.Accent, 2, 0.1)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(0,20), Size=UD2(1,0,0,32),
            Font=ENUM.Font.GothamBold, Text=title or "确认",
            TextColor3=TH.Text, TextSize=20, TextXAlignment=ENUM.TextXAlignment.Center,
        }, box)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(20,60), Size=UD2(1,-40,0,60),
            Font=ENUM.Font.GothamMedium, Text=desc or "",
            TextColor3=TH.TextDim, TextSize=14, TextWrapped=true,
            TextXAlignment=ENUM.TextXAlignment.Center,
        }, box)
        local yesBtn = S.create("TextButton", {
            Size=UDO(160,44), Position=UDO(30, 140),
            BackgroundColor3=TH.Danger, BorderSizePixel=0,
            Font=ENUM.Font.GothamBold, Text="确认", TextColor3=TH.OnAccent, TextSize=16,
        }, box)
        S.corner(yesBtn, 8)
        local noBtn = S.create("TextButton", {
            Size=UDO(160,44), Position=UDO(210, 140),
            BackgroundColor3=TH.SurfaceAlt, BorderSizePixel=0,
            Font=ENUM.Font.GothamBold, Text="取消", TextColor3=TH.Text, TextSize=16,
        }, box)
        S.corner(noBtn, 8)
        S.track(yesBtn.MouseButton1Click:Connect(function()
            pcall(function() overlay:Destroy() end)
            S.UIState.confirmOpen = false
            if onYes then onYes() end
        end))
        S.track(noBtn.MouseButton1Click:Connect(function()
            pcall(function() overlay:Destroy() end)
            S.UIState.confirmOpen = false
            if onNo then onNo() end
        end))
    end

    local main = S.create("Frame", {
        Name="Main", AnchorPoint=V2(0,0),
        Position=S.deserializePos(S.savedMainPos, UD2(0.5,-280,0.5,-220)),
        Size=UDO(600, 460), BackgroundColor3=TH.Bg, BorderSizePixel=0,
        ClipsDescendants=true, Active=true,
    }, screen)
    S.ui.main = main
    S.corner(main, 12); S.stroke(main, TH.Border, 1)

    local titleBar = S.create("Frame", {
        Name="TitleBar", Size=UD2(1,0,0,46), BackgroundColor3=TH.Surface,
        BorderSizePixel=0, Active=true,
    }, main)
    S.corner(titleBar, 12)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(18,0), Size=UD2(1,-160,1,0),
        Font=ENUM.Font.GothamBold, Text="肌肉之王自动化 v39",
        TextColor3=TH.Text, TextSize=18, TextXAlignment=ENUM.TextXAlignment.Left,
    }, titleBar)
    local minBtn = S.create("TextButton", {
        Size=UDO(32,28), Position=UD2(1,-118,0,9), BackgroundColor3=TH.SurfaceAlt,
        BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text="—", TextColor3=TH.Text, TextSize=16,
    }, titleBar); S.corner(minBtn, 6)
    local pillBtn = S.create("TextButton", {
        Size=UDO(32,28), Position=UD2(1,-82,0,9), BackgroundColor3=TH.SurfaceAlt,
        BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text="◯", TextColor3=TH.Text, TextSize=16,
    }, titleBar); S.corner(pillBtn, 6)
    local closeBtn = S.create("TextButton", {
        Size=UDO(32,28), Position=UD2(1,-46,0,9), BackgroundColor3=TH.Danger,
        BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text="✕", TextColor3=TH.OnAccent, TextSize=16,
    }, titleBar); S.corner(closeBtn, 6)

    local tabBar = S.create("Frame", {
        Name="TabBar", Size=UD2(1,0,0,38), Position=UDO(0,46),
        BackgroundColor3=TH.SurfaceAlt, BorderSizePixel=0,
    }, main)
    local contentArea = S.create("Frame", {
        Name="Content", Size=UD2(1,0,1,-84), Position=UDO(0,84),
        BackgroundTransparency=1,
    }, main)
    S.ui.contentArea = contentArea

    local TABS = {
        {id="train",label="锻炼"},{id="tele",label="传送"},{id="reb",label="重生"},
        {id="kill",label="杀戮"},{id="pet",label="宠物"},{id="boss",label="Boss"},{id="set",label="设置"},
    }
    local tabButtons = {}
    for i, tab in ipairs(TABS) do
        local btn = S.create("TextButton", {
            Name="Tab_"..tab.id, Size=UD2(1/#TABS,0,1,0), Position=UD2((i-1)/#TABS,0,0,0),
            BackgroundTransparency=1, BorderSizePixel=0,
            Font=ENUM.Font.GothamBold, Text=tab.label, TextColor3=TH.TextDim, TextSize=16,
            AutoButtonColor=false,
        }, tabBar)
        tabButtons[i] = btn
    end

    local function newPage(name)
        local page = S.create("ScrollingFrame", {
            Name=name, Size=UD2(1,0,1,0), BackgroundTransparency=1, BorderSizePixel=0,
            ScrollBarThickness=6, ScrollBarImageColor3=TH.Accent,
            CanvasSize=UD2(0,0,0,0), AutomaticCanvasSize=ENUM.AutomaticSize.Y,
            ScrollingDirection=ENUM.ScrollingDirection.Y, Visible=false, ClipsDescendants=true,
        }, contentArea)
        S.padding(page, 14, 14, 14, 14); S.listLayout(page, 8)
        return page
    end
    local function sectionLabel(parent, text)
        return S.create("TextLabel", {
            Size=UD2(1,0,0,22), BackgroundTransparency=1,
            Font=ENUM.Font.GothamBold, Text=text, TextColor3=TH.TextMuted,
            TextSize=14, TextXAlignment=ENUM.TextXAlignment.Left,
        }, parent)
    end
    local function divider(parent)
        return S.create("Frame", {Size=UD2(1,0,0,1), BackgroundColor3=TH.Border, BorderSizePixel=0}, parent)
    end
    local function addToggle(parent, label, default, onChange, hint)
        local row = S.create("Frame", {
            Size=UD2(1,0,0, hint and 52 or 40),
            BackgroundColor3=TH.Surface, BorderSizePixel=0,
        }, parent)
        S.corner(row, 8); S.stroke(row, TH.Border, 1, 0.5)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(14, hint and 6 or 0),
            Size=UD2(1,-90,0, hint and 22 or 40),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.Text,
            TextSize=15, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        if hint then
            S.create("TextLabel", {
                BackgroundTransparency=1, Position=UDO(14,26), Size=UD2(1,-90,0,20),
                Font=ENUM.Font.Gotham, Text=hint, TextColor3=TH.TextDim,
                TextSize=12, TextXAlignment=ENUM.TextXAlignment.Left,
                TextTruncate=ENUM.TextTruncate.AtEnd,
            }, row)
        end
        local tb = S.create("Frame", {
            AnchorPoint=V2(1,0.5), Position=UD2(1,-14,0.5,0), Size=UDO(46,24),
            BackgroundColor3=TH.SurfaceAlt, BorderSizePixel=0,
        }, row)
        S.corner(tb, 12)
        local knob = S.create("Frame", {
            AnchorPoint=V2(0,0.5), Position=UD2(0,3,0.5,0), Size=UDO(18,18),
            BackgroundColor3=TH.TextMuted, BorderSizePixel=0, ZIndex=2,
        }, tb)
        S.corner(knob, 9)
        local function render(on)
            if on then
                tb.BackgroundColor3=TH.Accent
                knob.Position=UD2(1,-21,0.5,0)
                knob.BackgroundColor3=TH.OnAccent
            else
                tb.BackgroundColor3=TH.SurfaceAlt
                knob.Position=UD2(0,3,0.5,0)
                knob.BackgroundColor3=TH.TextMuted
            end
        end
        render(default)
        local ca = S.create("TextButton", {Size=UD2(1,0,1,0), BackgroundTransparency=1, Text=""}, row)
        local value = default
        S.track(ca.MouseButton1Click:Connect(function()
            value = not value; render(value)
            if onChange then onChange(value) end
        end))
        return {set=function(v) value=v; render(v) end, get=function() return value end}
    end
    local function addInput(parent, label, default, minV, maxV, onChange, hint)
        local row = S.create("Frame", {
            Size=UD2(1,0,0, hint and 52 or 40),
            BackgroundColor3=TH.Surface, BorderSizePixel=0,
        }, parent)
        S.corner(row, 8); S.stroke(row, TH.Border, 1, 0.5)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(14, hint and 6 or 0),
            Size=UD2(1,-130,0, hint and 22 or 40),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.Text,
            TextSize=15, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        if hint then
            S.create("TextLabel", {
                BackgroundTransparency=1, Position=UDO(14,26), Size=UD2(1,-130,0,20),
                Font=ENUM.Font.Gotham, Text=hint, TextColor3=TH.TextDim,
                TextSize=12, TextXAlignment=ENUM.TextXAlignment.Left,
                TextTruncate=ENUM.TextTruncate.AtEnd,
            }, row)
        end
        local box = S.create("TextBox", {
            AnchorPoint=V2(1,0.5), Position=UD2(1,-14,0.5,0), Size=UDO(100,30),
            BackgroundColor3=TH.Bg2, BorderSizePixel=0, Font=ENUM.Font.GothamBold,
            Text=tostring(default), TextColor3=TH.Text, TextSize=15,
            PlaceholderText=string.format("%d-%d", minV, maxV), PlaceholderColor3=TH.TextMuted,
            ClearTextOnFocus=false,
        }, row)
        S.corner(box, 6); S.stroke(box, TH.Border, 1)
        S.track(box.FocusLost:Connect(function()
            local n = tonumber(box.Text)
            if not n then box.Text = tostring(default); return end
            n = math.floor(n); n = math.clamp(n, minV, maxV)
            box.Text = tostring(n)
            if onChange then onChange(n) end
        end))
        return box
    end
    local function addTextInput(parent, label, default, onChange, hint)
        local row = S.create("Frame", {
            Size=UD2(1,0,0, hint and 52 or 40),
            BackgroundColor3=TH.Surface, BorderSizePixel=0,
        }, parent)
        S.corner(row, 8); S.stroke(row, TH.Border, 1, 0.5)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(14, hint and 6 or 0),
            Size=UD2(1,-210,0, hint and 22 or 40),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.Text,
            TextSize=15, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        if hint then
            S.create("TextLabel", {
                BackgroundTransparency=1, Position=UDO(14,26), Size=UD2(1,-210,0,20),
                Font=ENUM.Font.Gotham, Text=hint, TextColor3=TH.TextDim,
                TextSize=12, TextXAlignment=ENUM.TextXAlignment.Left,
            }, row)
        end
        local box = S.create("TextBox", {
            AnchorPoint=V2(1,0.5), Position=UD2(1,-14,0.5,0), Size=UDO(190,30),
            BackgroundColor3=TH.Bg2, BorderSizePixel=0, Font=ENUM.Font.GothamMedium,
            Text=tostring(default or ""), TextColor3=TH.Text, TextSize=13,
            PlaceholderText="链接或 code", PlaceholderColor3=TH.TextMuted,
            ClearTextOnFocus=false, TextTruncate=ENUM.TextTruncate.AtEnd,
        }, row)
        S.corner(box, 6); S.stroke(box, TH.Border, 1)
        S.track(box.FocusLost:Connect(function() if onChange then onChange(box.Text) end end))
        return box
    end
    local function addButton(parent, label, onClick, color)
        local btn = S.create("TextButton", {
            Size=UD2(1,0,0,36), BackgroundColor3=color or TH.SurfaceAlt,
            BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text=label,
            TextColor3=TH.Text, TextSize=15, AutoButtonColor=true,
        }, parent)
        S.corner(btn, 8); S.stroke(btn, TH.Border, 1, 0.5)
        S.track(btn.MouseButton1Click:Connect(onClick))
        return btn
    end
    local function addSlider(parent, label, minV, maxV, default, onChange)
        local row = S.create("Frame", {
            Size=UD2(1,0,0,46), BackgroundColor3=TH.Surface, BorderSizePixel=0,
        }, parent)
        S.corner(row, 8); S.stroke(row, TH.Border, 1, 0.5)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(14,4), Size=UD2(1,-110,0,20),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.Text,
            TextSize=14, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        local vl = S.create("TextLabel", {
            BackgroundTransparency=1, AnchorPoint=V2(1,0), Position=UD2(1,-14,0,4),
            Size=UDO(80,20), Font=ENUM.Font.GothamBold, Text=tostring(default),
            TextColor3=TH.Accent, TextSize=14, TextXAlignment=ENUM.TextXAlignment.Right,
        }, row)
        local trackBar = S.create("Frame", {
            Position=UDO(14,28), Size=UD2(1,-28,0,7),
            BackgroundColor3=TH.SurfaceAlt, BorderSizePixel=0,
        }, row)
        S.corner(trackBar, 4)
        local fill = S.create("Frame", {
            Size=UD2((default-minV)/math.max(1,maxV-minV),0,1,0),
            BackgroundColor3=TH.Accent, BorderSizePixel=0,
        }, trackBar)
        S.corner(fill, 4)
        local sb = S.create("TextButton", {
            Size=UD2(1,0,1,22), Position=UDO(0,-7), BackgroundTransparency=1, Text="",
        }, trackBar)
        local active = false
        local function upd(mx)
            local ap = trackBar.AbsolutePosition; local as = trackBar.AbsoluteSize
            local r = math.clamp((mx - ap.X)/math.max(1,as.X), 0, 1)
            local v = math.floor(minV + (maxV-minV)*r + 0.5)
            vl.Text = tostring(v)
            fill.Size = UD2((v-minV)/math.max(1,maxV-minV),0,1,0)
            if onChange then onChange(v) end
        end
        S.track(sb.InputBegan:Connect(function(i)
            if i.UserInputType == ENUM.UserInputType.MouseButton1 or i.UserInputType == ENUM.UserInputType.Touch then active = true; upd(i.Position.X) end
        end))
        S.track(sb.InputEnded:Connect(function(i)
            if i.UserInputType == ENUM.UserInputType.MouseButton1 or i.UserInputType == ENUM.UserInputType.Touch then active = false end
        end))
        S.track(UIS_IC:Connect(function(i)
            if not active then return end
            if i.UserInputType == ENUM.UserInputType.MouseMovement or i.UserInputType == ENUM.UserInputType.Touch then upd(i.Position.X) end
        end))
        return {set=function(v) vl.Text=tostring(v); fill.Size=UD2((v-minV)/math.max(1,maxV-minV),0,1,0) end}
    end
    local function addDropdown(parent, label, values, default, onChange)
        local row = S.create("Frame", {
            Size=UD2(1,0,0,42), BackgroundColor3=TH.Surface, BorderSizePixel=0,
        }, parent)
        S.corner(row, 8); S.stroke(row, TH.Border, 1, 0.5)
        S.create("TextLabel", {
            BackgroundTransparency=1, Position=UDO(14,0), Size=UD2(0.35,0,1,0),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.Text,
            TextSize=15, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        local dropBtn = S.create("TextButton", {
            AnchorPoint=V2(1,0.5), Position=UD2(1,-14,0.5,0), Size=UDO(220,32),
            BackgroundColor3=TH.Bg2, BorderSizePixel=0, Font=ENUM.Font.GothamBold,
            Text=(default and tostring(default) or "—").." ▾", TextColor3=TH.Text,
            TextSize=14, TextTruncate=ENUM.TextTruncate.AtEnd,
        }, row)
        S.corner(dropBtn, 6); S.stroke(dropBtn, TH.Border, 1)
        local modal = S.create("Frame", {
            Size=UDO(220, 260), BackgroundColor3=TH.Surface, BorderSizePixel=0,
            Visible=false, ZIndex=300,
        }, main)
        S.corner(modal, 8); S.stroke(modal, TH.Accent, 1.5, 0.2)
        local list = S.create("ScrollingFrame", {
            Size=UD2(1,0,1,0), BackgroundTransparency=1, BorderSizePixel=0,
            ScrollBarThickness=5, ScrollBarImageColor3=TH.Accent,
            CanvasSize=UD2(0,0,0,0), AutomaticCanvasSize=ENUM.AutomaticSize.Y,
            ScrollingDirection=ENUM.ScrollingDirection.Y,
        }, modal)
        S.padding(list, 5, 5, 5, 5); S.listLayout(list, 3)
        local function draw()
            for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for i, v in ipairs(values) do
                local opt = S.create("TextButton", {
                    Size=UD2(1,0,0,28), BackgroundColor3=TH.SurfaceAlt,
                    BorderSizePixel=0, Font=ENUM.Font.GothamMedium, Text=tostring(v),
                    TextColor3=TH.Text, TextSize=14, LayoutOrder=i,
                    TextXAlignment=ENUM.TextXAlignment.Left, TextTruncate=ENUM.TextTruncate.AtEnd,
                }, list)
                S.corner(opt, 5); S.padding(opt, 0, 0, 8, 8)
                S.track(opt.MouseButton1Click:Connect(function()
                    dropBtn.Text = tostring(v).." ▾"; modal.Visible = false
                    if onChange then onChange(v) end
                end))
            end
        end
        draw()
        S.track(dropBtn.MouseButton1Click:Connect(function()
            if modal.Visible then modal.Visible = false; return end
            local bp = dropBtn.AbsolutePosition; local bs = dropBtn.AbsoluteSize
            local mp = main.AbsolutePosition; local ms = main.AbsoluteSize
            local mw, mh = 220, 260
            local mx = (bp.X - mp.X) + bs.X - mw
            local my = (bp.Y - mp.Y) + bs.Y + 6
            if mx < 4 then mx = 4 end
            if mx + mw > ms.X - 4 then mx = ms.X - mw - 4 end
            if my + mh > ms.Y - 4 then
                my = (bp.Y - mp.Y) - mh - 6
                if my < 4 then my = 4 end
            end
            modal.Position = UDO(mx, my)
            modal.Visible = true
        end))
        S.track(UIS_IB:Connect(function(i)
            if not modal.Visible then return end
            if i.UserInputType ~= ENUM.UserInputType.MouseButton1 and i.UserInputType ~= ENUM.UserInputType.Touch then return end
            local ap = modal.AbsolutePosition; local as = modal.AbsoluteSize
            local ip = i.Position
            local inM = ip.X >= ap.X and ip.X <= ap.X+as.X and ip.Y >= ap.Y and ip.Y <= ap.Y+as.Y
            local bp = dropBtn.AbsolutePosition; local bs = dropBtn.AbsoluteSize
            local inB = ip.X >= bp.X and ip.X <= bp.X+bs.X and ip.Y >= bp.Y and ip.Y <= bp.Y+bs.Y
            if not inM and not inB then modal.Visible = false end
        end))
        return {
            refresh = function(nv, newDefault)
                values = nv
                if newDefault then dropBtn.Text = tostring(newDefault).." ▾" end
                draw()
            end
        }
    end
    local function addActionRow(parent, actions)
        local row = S.create("Frame", {Size=UD2(1,0,0,36), BackgroundTransparency=1}, parent)
        S.listLayout(row, 6, true)
        for _, a in ipairs(actions) do
            local btn = S.create("TextButton", {
                Size=UD2(1/#actions, -4, 1, 0), BackgroundColor3=a.color or TH.SurfaceAlt,
                BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text=a.label,
                TextColor3=TH.Text, TextSize=14,
            }, row)
            S.corner(btn, 8); S.stroke(btn, TH.Border, 1, 0.5)
            S.track(btn.MouseButton1Click:Connect(a.onClick))
        end
        return row
    end

    local pages = {}
    for _, tab in ipairs(TABS) do pages[tab.id] = newPage("Page_"..tab.id) end

    -- 锻炼页
    do
        local p = pages.train
        sectionLabel(p, "基本锻炼")
        local trainToggle, fastToggle
        trainToggle = addToggle(p, "自动锻炼", S.autoTrain, function(v)
            S.autoTrain = v
            if v and S.fastTrain then S.fastTrain = false; fastToggle.set(false) end
        end, "固定 10 次/秒")
        fastToggle = addToggle(p, "快速锻炼", S.fastTrain, function(v)
            S.fastTrain = v
            if v and S.autoTrain then S.autoTrain = false; trainToggle.set(false) end
        end, "自定义频率（最低 10/s）")
        S.ui.rateBox = addInput(p, "频率（次/秒）", S.fastRate, 1, 50000, function(n)
            if S.adaptiveEnabled then
                if S.ui.rateBox then S.ui.rateBox.Text = tostring(S.fastRate) end
                return
            end
            S.fastRate = n; S.degradeLevel = 0
        end)
        divider(p)
        sectionLabel(p, "卡顿自调节")
        addToggle(p, "根据帧率自动调节频率", S.adaptiveEnabled, function(v)
            S.adaptiveEnabled = v
            if S.ui.rateBox then
                S.ui.rateBox.TextEditable = not v
                S.ui.rateBox.TextColor3 = v and TH.TextDim or TH.Text
            end
        end, "自适应实时刷新，输入框锁定")
        addSlider(p, "目标帧率阈值", 10, 120, S.adaptiveThreshold, function(v) S.adaptiveThreshold = v end)
        addInput(p, "自适应上限（次/秒）", S.adaptiveMaxRate, 100, 50000, function(n)
            S.adaptiveMaxRate = n
        end, "自适应最高不超过这个值")
        divider(p)
        sectionLabel(p, "工具自动切换")
        local tP, tH, tS
        addToggle(p, "自动切换哑铃", S.toolDumbbell, function(v) S.toolDumbbell = v end)
        tP = addToggle(p, "自动切换俯卧撑", S.toolPushups, function(v)
            S.toolPushups = v
            if v then S.toolHandstands = false; S.toolSitups = false
                if tH then tH.set(false) end; if tS then tS.set(false) end end
        end)
        tH = addToggle(p, "自动切换倒立", S.toolHandstands, function(v)
            S.toolHandstands = v
            if v then S.toolPushups = false; S.toolSitups = false
                if tP then tP.set(false) end; if tS then tS.set(false) end end
        end)
        tS = addToggle(p, "自动切换仰卧起坐", S.toolSitups, function(v)
            S.toolSitups = v
            if v then S.toolPushups = false; S.toolHandstands = false
                if tP then tP.set(false) end; if tH then tH.set(false) end end
        end)
        divider(p)
        sectionLabel(p, "★ 器械模式")
        S.ui.machineToggle = addToggle(p, "启用器械使用", S.machineState.enabled,
            function(v) S.machineState.enabled = v end,
            "优先器械（Boss 时暂停）")

        local gymNames = {"全部"}
        for name, _ in pairs(S.getMachineSeatsByGym()) do
            table.insert(gymNames, S.translateGym(name))
        end
        table.sort(gymNames, function(a,b)
            if a == "全部" then return true end
            if b == "全部" then return false end
            return a < b
        end)

        local machineDrop, indexDrop

        addDropdown(p, "① 健身房", gymNames,
            S.machineState.gymFilter == "" and "全部" or S.translateGym(S.machineState.gymFilter),
            function(v)
                local gymEn = ""
                if v ~= "全部" then
                    for en, cn in pairs(S.GYM_TRANSLATE) do
                        if cn == v then gymEn = en; break end
                    end
                end
                S.machineState.gymFilter = gymEn
                local names = {"全部"}
                for _, n in ipairs(S.getMachineNameList()) do
                    table.insert(names, S.translateMachine(n))
                end
                if machineDrop and machineDrop.refresh then
                    machineDrop.refresh(names, "全部")
                end
                S.machineState.indexFilter = 0
                S.machineState.machineFilter = ""
                S.machineState.targetSeat = nil
                if indexDrop and indexDrop.refresh then
                    indexDrop.refresh({"随机"}, "随机")
                end
            end)

        local initNames = {"全部"}
        for _, n in ipairs(S.getMachineNameList()) do
            table.insert(initNames, S.translateMachine(n))
        end

        local function refreshIndexOptions()
            local mname = S.machineState.machineFilter or ""
            local count = S.getMachineCountByName(mname)
            local opts = {"随机"}
            for i = 1, math.max(1, count) do table.insert(opts, "第"..i.."台") end
            if indexDrop and indexDrop.refresh then
                indexDrop.refresh(opts, "随机")
            end
        end

        machineDrop = addDropdown(p, "② 器械名", initNames,
            S.machineState.machineFilter == "" and "全部" or S.translateMachine(S.machineState.machineFilter),
            function(v)
                if v == "全部" then
                    S.machineState.machineFilter = ""
                else
                    local found = false
                    for en, cn in pairs(S.MACHINE_TRANSLATE) do
                        if cn == v then S.machineState.machineFilter = en; found = true; break end
                    end
                    if not found then S.machineState.machineFilter = v end
                end
                S.machineState.indexFilter = 0
                S.machineState.targetSeat = nil
                refreshIndexOptions()
            end)

        indexDrop = addDropdown(p, "③ 编号", {"随机"}, "随机",
            function(v)
                if v == "随机" then S.machineState.indexFilter = 0
                else S.machineState.indexFilter = tonumber(v:match("%d+")) or 0 end
                S.machineState.targetSeat = nil
            end)

        addToggle(p, "启用器械传送", S.machineTeleport.enabled,
            function(v) S.machineTeleport.enabled = v end,
            "自动处理超载健身房前置")
    end

    -- 传送页
    do
        local p = pages.tele
        sectionLabel(p, "自动传送")
        S.ui.teleToggle = addToggle(p, "循环前往肌肉之王", S.autoTeleport, function(v)
            S.autoTeleport = v
            if v then
                S.teleportLoopEnabled = false
                if S.ui.loopToggle then S.ui.loopToggle.set(false) end
            end
        end, "Boss 存在时自动暂停")
        addButton(p, "强制传送肌肉之王", function()
            local hrp = S.cache.hrp; if not hrp then return end
            local portal = Workspace:FindFirstChild("beachToMuscleKing", true)
            local cf = portal and CN(portal.Position + V3(0,6,0)) or CN(V3(-8727.1, 409.7, -5796.4))
            hrp.CFrame = cf; S.notify("已传送", 2)
        end)
        divider(p)
        sectionLabel(p, "★ 单点传送（持续锁定同一坐标）")
        S.ui.loopToggle = addToggle(p, "启用单点传送", S.teleportLoopEnabled, function(v)
            S.teleportLoopEnabled = v
            if v then
                S.autoTeleport = false
                if S.ui.teleToggle then S.ui.teleToggle.set(false) end
            end
        end, "持续锁定到选择的单个坐标")
        local tpNames = {}
        for _, t in ipairs(S.TELEPORTS) do table.insert(tpNames, t.name) end
        addDropdown(p, "目标坐标", tpNames, S.TELEPORTS[S.teleportLoopIndex] and S.TELEPORTS[S.teleportLoopIndex].name or tpNames[1],
            function(v)
                for i, t in ipairs(S.TELEPORTS) do
                    if t.name == v then S.teleportLoopIndex = i; break end
                end
            end)
        divider(p)
        sectionLabel(p, "地图传送点")
        local grid = S.create("Frame", {
            Size=UD2(1,0,0,0), BackgroundTransparency=1,
            AutomaticSize=ENUM.AutomaticSize.Y,
        }, p)
        S.create("UIGridLayout", {
            CellSize=UD2(0.5,-5,0,36), CellPadding=UD2(0,8,0,6),
            SortOrder=ENUM.SortOrder.LayoutOrder,
        }, grid)
        for i, tp in ipairs(S.TELEPORTS) do
            local btn = S.create("TextButton", {
                LayoutOrder=i, BackgroundColor3=TH.SurfaceAlt, BorderSizePixel=0,
                Font=ENUM.Font.GothamBold, Text=tp.name, TextColor3=TH.Text,
                TextSize=14, TextTruncate=ENUM.TextTruncate.AtEnd,
            }, grid)
            S.corner(btn, 6); S.stroke(btn, TH.Border, 1, 0.4); S.padding(btn, 0, 0, 8, 8)
            S.track(btn.MouseButton1Click:Connect(function()
                local hrp = S.cache.hrp
                if hrp then
                    hrp.CFrame = CN(tp.pos)
                    hrp.AssemblyLinearVelocity = V3(0,0,0); hrp.AssemblyAngularVelocity = V3(0,0,0)
                end
                S.notify("已传送："..tp.name, 2)
            end))
        end
    end

    -- 重生页
    do
        local p = pages.reb
        sectionLabel(p, "自动重生")
        S.ui.rebirthToggle = addToggle(p, "自动重生", S.autoRebirth, function(v)
            S.autoRebirth = v; S.rebirthSavedBySystem = false
        end, "Boss/杀戮时自动暂停，结束后恢复")
        addInput(p, "频率（次/秒）", S.rebirthRate, 1, 100, function(n) S.rebirthRate = n end)
        addInput(p, "★ 目标重生数（0=无限）", S.rebirthTarget, 0, 1000000, function(n)
            S.rebirthTarget = n
        end, "达到后自动关闭自动重生")
        divider(p)
        sectionLabel(p, "换包重生")
        addToggle(p, "换包重生", S.autoPackRebirth, function(v) S.autoPackRebirth = v end, "自动换宠并自动重生")
    end

    -- 杀戮页
    do
        local p = pages.kill
        sectionLabel(p, "全图杀戮")
        S.ui.killToggle = addToggle(p, "开启全图杀戮", S.killEnabled, function(v) S.killEnabled = v end,
            "Boss 存在时自动暂停；开启时放大敌人方便打中")
        divider(p)
        sectionLabel(p, "善恶过滤")
        addToggle(p, "只杀好人", S.killGoodOnly, function(v) S.killGoodOnly = v end)
        addToggle(p, "只杀坏人", S.killBadOnly, function(v) S.killBadOnly = v end)
        divider(p)
        sectionLabel(p, "好友白名单")
        addToggle(p, "不打好友", S.friendWhitelist, function(v)
            S.friendWhitelist = v
            if v and not S.friendWL.loaded then S.refreshFriendList() end
        end)
        addButton(p, "刷新好友列表", function() S.refreshFriendList() end)
        divider(p)
        sectionLabel(p, "双工具 / 肌肉之王")
        addToggle(p, "杀戮时切换训练工具", S.dualEnabled, function(v) S.dualEnabled = v end)
        addToggle(p, "自动击杀其他肌肉之王", S.autoKingKill, function(v)
            S.autoKingKill = v
            if not v then S.kingKillTarget = nil; S.kingKillActive = false; S.restoreAllEnlarged() end
        end, "只看打不打得过")
    end

    -- 宠物页
    do
        local p = pages.pet
        sectionLabel(p, "宠物商店")
        local rawList = S.getPetShopList()
        local list = {}
        for _, n in ipairs(rawList) do table.insert(list, S.bilingualPet(n)) end
        local dd = addDropdown(p, "选择宠物", list,
            S.selectedPet == "" and "—" or S.bilingualPet(S.selectedPet),
            function(v)
                for _, rn in ipairs(rawList) do
                    if S.bilingualPet(rn) == v then S.selectedPet = rn; break end
                end
            end)
        addActionRow(p, {
            {label="刷新", onClick=function()
                local l2 = {}
                for _, n in ipairs(S.getPetShopList()) do table.insert(l2, S.bilingualPet(n)) end
                dd.refresh(l2)
            end},
            {label="购买", color=TH.Accent2, onClick=function() S.buyPet(S.selectedPet) end},
        })
        addToggle(p, "自动购买", S.autoPetBuy, function(v) S.autoPetBuy = v end)
        divider(p)
        sectionLabel(p, "自动轮盘（不持久化）")
        addToggle(p, "自动轮盘", S.autoWheel, function(v) S.autoWheel = v end)
        divider(p)
        sectionLabel(p, "自动吃蛋")
        addToggle(p, "自动吃蛋", S.autoEatEgg, function(v) S.autoEatEgg = v end)
        addInput(p, "吃蛋数量（每0.5秒）", S.eatEggBatch, 1, 100, function(n) S.eatEggBatch = n end)
        divider(p)
        sectionLabel(p, "★ 送蛋功能（仅 Protein Egg）")
        local giftTargets = {}
        local function makeName(plr)
            local d = plr.DisplayName or plr.Name
            if d ~= plr.Name then return d.." (@"..plr.Name..")" end
            return plr.Name
        end
        for _, plr in ipairs(GetPlayers(Players)) do
            if plr ~= LP then table.insert(giftTargets, makeName(plr)) end
        end
        local targetDrop = addDropdown(p, "送蛋目标", giftTargets, "—",
            function(v)
                for _, plr in ipairs(GetPlayers(Players)) do
                    if plr ~= LP and makeName(plr) == v then
                        S.selectedEggTarget = plr.Name; break
                    end
                end
            end)
        addInput(p, "送蛋数量（0=全部）", S.giftAmount or 0, 0, 9999,
            function(n) S.giftAmount = n end)
        addActionRow(p, {
            {label="赠送蛋白蛋", color=TH.Success, onClick=function()
                local target = Players:FindFirstChild(S.selectedEggTarget)
                if not target then S.notify("请先选择玩家", 3); return end
                local amt = S.giftAmount or 0
                task.spawn(function()
                    local sent = S.giftEggsTo(target, amt > 0 and amt or 9999)
                    S.notify(string.format("已送 %d 个蛋白蛋 → %s", sent, target.Name), 4)
                end)
            end},
            {label="刷新玩家", onClick=function()
                local l = {}
                for _, plr in ipairs(GetPlayers(Players)) do
                    if plr ~= LP then table.insert(l, makeName(plr)) end
                end
                targetDrop.refresh(l)
                S.notify("已刷新", 2)
            end},
        })
        divider(p)
        sectionLabel(p, "★ 自动换宠（4 预设，快速切换）")
        addToggle(p, "启用自动换宠", S.petPreset.autoSwitch, function(v) S.petPreset.autoSwitch = v end,
            "执行不同任务时切换宠物（快速，无延迟）")

        -- ★ 显示当前配置详情
        local presetViewer = S.create("Frame", {
            Size=UD2(1,0,0,180), BackgroundColor3=TH.Surface,
            BorderSizePixel=0,
        }, p)
        S.corner(presetViewer, 8); S.stroke(presetViewer, TH.Border, 1, 0.5)
        S.padding(presetViewer, 10, 10, 12, 12)
        local pvLayout = S.create("UIListLayout", {
            Padding = UDim.new(0, 4),
            SortOrder=ENUM.SortOrder.LayoutOrder,
        }, presetViewer)

        local function refreshPresetViewer()
            for _, c in ipairs(presetViewer:GetChildren()) do
                if c:IsA("TextLabel") then c:Destroy() end
            end
            local order = 0
            local function makeLine(text, color)
                order = order + 1
                local lbl = S.create("TextLabel", {
                    Size=UD2(1,0,0,18), BackgroundTransparency=1, LayoutOrder=order,
                    Font=ENUM.Font.GothamMedium, Text=text, TextColor3=color or TH.Text,
                    TextSize=13, TextXAlignment=ENUM.TextXAlignment.Left,
                    TextTruncate=ENUM.TextTruncate.AtEnd,
                }, presetViewer)
                return lbl
            end
            makeLine("【当前配置详情】", TH.Accent)
            local function describe(key, label)
                local p_ = S.petPreset[key]
                if not p_ or #p_ == 0 then
                    makeLine(label.."：空", TH.TextMuted)
                else
                    local parts = {}
                    for _, e in ipairs(p_) do
                        table.insert(parts, string.format("%s×%d", S.translatePet(e.name) or e.name, e.count or 1))
                    end
                    makeLine(label.."："..table.concat(parts, ", "), TH.Text)
                end
            end
            describe("train", "锻炼")
            describe("rebirth", "重生")
            describe("kill", "杀戮")
            describe("boss", "Boss")
        end
        refreshPresetViewer()
        S.ui.refreshPresetViewer = refreshPresetViewer

        local function savePreset(key, label)
            local names = {}
            for _, p_ in ipairs(S.getEquippedPetNames()) do
                local found = false
                for _, e in ipairs(names) do
                    if e.name == p_.name then e.count = e.count + 1; found = true; break end
                end
                if not found then table.insert(names, {name=p_.name, count=1}) end
            end
            S.petPreset[key] = names
            S.petPreset.activeType = nil
            refreshPresetViewer()
            local txt = {}
            for _, e in ipairs(names) do
                table.insert(txt, string.format("%s×%d", S.translatePet(e.name) or e.name, e.count))
            end
            S.notify(label.."已保存："..table.concat(txt, ", "), 5)
        end
        local function applyPreset(key, label)
            if not S.petPreset[key] or #S.petPreset[key] == 0 then
                S.notify(label.."为空，请先保存", 3); return
            end
            S.petPreset.activeType = nil
            S.applyPetPreset(key)
            S.notify("已应用"..label, 3)
        end
        local function deletePreset(key, label)
            if not S.petPreset[key] or #S.petPreset[key] == 0 then
                S.notify(label.."为空", 3); return
            end
            S.showConfirm("删除配置", "确定删除 "..label.." 配置？此操作不可撤销。", function()
                S.petPreset[key] = {}
                S.petPreset.activeType = nil
                refreshPresetViewer()
                S.notify(label.."已删除", 3)
            end)
        end

        addActionRow(p, {
            {label="保存→锻炼", onClick=function() savePreset("train", "锻炼") end},
            {label="应用→锻炼", color=TH.Accent2, onClick=function() applyPreset("train", "锻炼") end},
        })
        addActionRow(p, {
            {label="保存→重生", onClick=function() savePreset("rebirth", "重生") end},
            {label="应用→重生", color=TH.Accent2, onClick=function() applyPreset("rebirth", "重生") end},
        })
        addActionRow(p, {
            {label="保存→杀戮", onClick=function() savePreset("kill", "杀戮") end},
            {label="应用→杀戮", color=TH.Accent2, onClick=function() applyPreset("kill", "杀戮") end},
        })
        addActionRow(p, {
            {label="保存→Boss", onClick=function() savePreset("boss", "Boss") end},
            {label="应用→Boss", color=TH.Accent2, onClick=function() applyPreset("boss", "Boss") end},
        })
        addActionRow(p, {
            {label="删除→锻炼", color=TH.Warning, onClick=function() deletePreset("train", "锻炼") end},
            {label="删除→重生", color=TH.Warning, onClick=function() deletePreset("rebirth", "重生") end},
        })
        addActionRow(p, {
            {label="删除→杀戮", color=TH.Warning, onClick=function() deletePreset("kill", "杀戮") end},
            {label="删除→Boss", color=TH.Warning, onClick=function() deletePreset("boss", "Boss") end},
        })
        addButton(p, "刷新配置查看", function() refreshPresetViewer(); S.notify("已刷新", 2) end)
    end

    -- Boss 页
    do
        local p = pages.boss
        sectionLabel(p, "自动打 Boss")
        addToggle(p, "自动打 Boss", S.autoBoss, function(v)
            S.autoBoss = v
            if not v and S.bossHoverConn then
                pcall(function() S.bossHoverConn:Disconnect() end); S.bossHoverConn = nil
            end
            if not v then S._lastBossAlive = false; S.setRebirthPause("boss", false) end
        end, "Boss 存活时打；暂停器械/双工具")
        addDropdown(p, "悬停高度模式", {"自动", "手动"},
            S.bossHeightMode == "manual" and "手动" or "自动",
            function(v)
                S.bossHeightMode = (v == "手动") and "manual" or "auto"
                S.notify(S.bossHeightMode == "auto" and "自动：普通40/其他55" or "手动模式", 3)
            end)
        addSlider(p, "手动高度", 0, 200, S.bossHeight, function(v) S.bossHeight = v end)
        divider(p)
        sectionLabel(p, "自动开宝箱（Boss 死后）")
        addToggle(p, "自动开宝箱", S.autoChest, function(v) S.autoChest = v end,
            "限定坐标±30")
        addSlider(p, "宝箱延迟（秒）", 0, 30, S.chestDelay, function(v) S.chestDelay = v end)
    end

    -- 设置页
    do
        local p = pages.set
        sectionLabel(p, "★ 全局控制")
        addToggle(p, "暂停脚本所有功能", S.scriptPaused, function(v)
            if v then S.pauseScript() else S.resumeScript() end
        end, "暂停后保留信息+紧急重进")
        divider(p)
        sectionLabel(p, "窗口外观")
        addSlider(p, "字体大小(%)", 80, 160, math.floor(S.fontScale*100), function(v)
            S.fontScale = v/100; S.applyFontScale()
        end)
        addSlider(p, "窗口宽度比例(%)", 30, 90, S.uiWidthPct, function(v) S.uiWidthPct = v; S.applyUISize() end)
        addSlider(p, "窗口高度比例(%)", 30, 90, S.uiHeightPct, function(v) S.uiHeightPct = v; S.applyUISize() end)
        addSlider(p, "主窗口不透明度(%)", 30, 100, math.floor(S.uiBgOpacity*100), function(v)
            S.uiBgOpacity = v/100; S.applyUIOpacity()
        end)
        addSlider(p, "内容页不透明度(%)", 30, 100, math.floor(S.uiPageOpacity*100), function(v)
            S.uiPageOpacity = v/100; S.applyUIOpacity()
        end)
        addActionRow(p, {
            {label="重置窗口位置", onClick=function()
                if S.ui.main then S.ui.main.Position = UD2(0.5,-280,0.5,-220) end
                S.savedMainPos = nil; S.applyUISize(); S.notify("已重置", 2)
            end},
        })
        divider(p)
        sectionLabel(p, "信息悬浮窗")
        S.ui.infoToggle = addToggle(p, "显示实时信息", S.infoWindowEnabled, function(v)
            S.infoWindowEnabled = v
            if S.ui.infoGui then
                if v then
                    if S.reopenInfoWindow then S.reopenInfoWindow() end
                    S.ui.infoGui.Enabled = true
                else
                    S.ui.infoGui.Enabled = false
                end
            end
        end)
        addSlider(p, "信息窗大小(%)", 60, 200, S.infoScale, function(v) S.infoScale = v; S.applyUISize() end)
        addSlider(p, "信息窗不透明度(%)", 30, 100, math.floor(S.infoBgOpacity*100), function(v)
            S.infoBgOpacity = v/100; S.applyUIOpacity()
        end)
        addToggle(p, "数字格式化显示", S.formatEnabled, function(v) S.formatEnabled = v end)
        divider(p)
        sectionLabel(p, "★ 自动重进")
        addToggle(p, "启用自动重进", S.autoRejoinEnabled, function(v)
            S.autoRejoinEnabled = v; S._rejoinTriggered = false
        end)
        addToggle(p, "★ 紧急重进（弹窗检测）", S.emergencyRejoin, function(v) S.emergencyRejoin = v end,
            "检测到退游弹窗/被踢立即重进")
        addDropdown(p, "触发条件", {"任意一个满足", "全部满足"},
            S.rejoinCondition == "all" and "全部满足" or "任意一个满足",
            function(v) S.rejoinCondition = (v == "全部满足") and "all" or "any" end)
        addToggle(p, "内存触发器", S.rejoinEnableMem, function(v) S.rejoinEnableMem = v end)
        addInput(p, "内存阈值（MB）", S.rejoinMemThreshold, 500, 100000, function(n) S.rejoinMemThreshold = n end)
        addToggle(p, "帧率触发器", S.rejoinEnableFps, function(v) S.rejoinEnableFps = v end)
        addInput(p, "帧率下限（FPS）", S.rejoinFpsThreshold, 1, 60, function(n) S.rejoinFpsThreshold = n end)
        addToggle(p, "延迟触发器", S.rejoinEnablePing, function(v) S.rejoinEnablePing = v end)
        addInput(p, "延迟上限（ms）", S.rejoinPingThreshold, 100, 5000, function(n) S.rejoinPingThreshold = n end)
        local serverModeMap = {["回原服务器"]="same", ["人多的服务器"]="crowded", ["私服"]="private", ["人少的服务器"]="sparse"}
        local serverModeRev = {same="回原服务器", crowded="人多的服务器", private="私服", sparse="人少的服务器"}
        addDropdown(p, "重进目标", {"回原服务器", "人多的服务器", "私服", "人少的服务器"},
            serverModeRev[S.rejoinServerMode] or "回原服务器",
            function(v) S.rejoinServerMode = serverModeMap[v] or "same" end)
        S.ui.privateServerBox = addTextInput(p, "私服链接/code", S.rejoinPrivateServerId, function(s)
            S.rejoinPrivateServerId = s
        end, "仅私服模式")
        addActionRow(p, {
            {label="复制当前私服 ID", color=TH.Accent2, onClick=function()
                local id = game.JobId or ""
                S.currentPrivateServerId = id
                if setclipboard then pcall(setclipboard, id) end
                S.notify("已复制："..id:sub(1, 30), 4)
                if S.ui.privateServerBox then S.ui.privateServerBox.Text = id end
                S.rejoinPrivateServerId = id
            end},
            {label="手动重进", color=TH.Warning, onClick=function()
                S._rejoinTriggered = false
                S.rejoinGame("手动", false)
            end},
        })
        divider(p)
        sectionLabel(p, "性能优化")
        addToggle(p, "深度防卡顿", S.antiLagEnabled, function(v) S.antiLagEnabled = v end)
        addToggle(p, "渲染剔除", S.renderCullEnabled, function(v) S.renderCullEnabled = v end)
        addSlider(p, "剔除距离", 100, 5000, S.renderCullDist, function(v) S.renderCullDist = v end)
        addToggle(p, "移除纹理", S.textureRemoverEnabled, function(v) S.textureRemoverEnabled = v end)
        divider(p)
        sectionLabel(p, "隐藏")
        addToggle(p, "隐藏自己的宠物", S.hideOwnPets, function(v) S.hideOwnPets = v end)
        addToggle(p, "隐藏所有宠物", S.hideAllPets, function(v) S.hideAllPets = v end)
        addToggle(p, "隐藏器械", S.hideMachines, function(v) S.hideMachines = v end)
        addToggle(p, "隐藏其他 UI", S.hideUIEnabled, function(v)
            S.hideUIEnabled = v
            if v then S.hideAllOtherUI() else S.restoreHiddenUI() end
        end)
        divider(p)
        sectionLabel(p, "反挂机（最多19分钟）")
        addSlider(p, "反AFK触发间隔(秒)", 60, 1140, S.antiAfkInterval, function(v)
            S.antiAfkInterval = math.min(v, 1140)
        end)
    end

    local function switchTab(id)
        for tid, p_ in pairs(pages) do p_.Visible = (tid == id) end
        for i, tab in ipairs(TABS) do
            tabButtons[i].TextColor3 = (tab.id == id) and TH.Accent or TH.TextDim
        end
    end
    for i, btn in ipairs(tabButtons) do
        S.track(btn.MouseButton1Click:Connect(function() switchTab(TABS[i].id) end))
    end
    switchTab("train")

    -- 拖动
    local dragging, dragStart, dragStartPos = false, nil, nil
    local function posIn(btn, pos)
        local ap = btn.AbsolutePosition; local as = btn.AbsoluteSize
        return pos.X >= ap.X and pos.X <= ap.X+as.X and pos.Y >= ap.Y and pos.Y <= ap.Y+as.Y
    end
    S.track(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType ~= ENUM.UserInputType.MouseButton1 and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        if posIn(minBtn, input.Position) or posIn(pillBtn, input.Position) or posIn(closeBtn, input.Position) then return end
        dragging = true; dragStart = input.Position; dragStartPos = main.Position
    end))
    S.track(UIS_IC:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= ENUM.UserInputType.MouseMovement and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        local d = input.Position - dragStart
        main.Position = UD2(dragStartPos.X.Scale, dragStartPos.X.Offset+d.X, dragStartPos.Y.Scale, dragStartPos.Y.Offset+d.Y)
    end))
    S.track(UIS_IE:Connect(function(input)
        if input.UserInputType == ENUM.UserInputType.MouseButton1 or input.UserInputType == ENUM.UserInputType.Touch then
            if dragging then S.savedMainPos = S.serializePos(main.Position); dragging = false end
        end
    end))

    local minimized = false
    S.track(minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            tabBar.Visible = false; contentArea.Visible = false
            main.Size = UDO(main.Size.X.Offset, 46); minBtn.Text = "+"
        else
            tabBar.Visible = true; contentArea.Visible = true
            S.applyUISize(); minBtn.Text = "—"
        end
    end))

    -- 药丸
    local pillFrame = S.create("Frame", {
        Name="Pill", AnchorPoint=V2(0.5, 0.5),
        Position=S.deserializePos(S.UIState.pillPos, UD2(0.5, 0, 0.18, 0)),
        Size=UDO(180, 42), BackgroundColor3=TH.Surface, BorderSizePixel=0,
        Visible=false, ZIndex=1000, Active=true,
    }, screen)
    S.ui.pillFrame = pillFrame
    S.corner(pillFrame, 21); S.stroke(pillFrame, TH.Accent, 1.5, 0.2)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(0,0), Size=UDO(48,42),
        Font=ENUM.Font.GothamBold, Text="≡", TextColor3=TH.Text, TextSize=22,
    }, pillFrame)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(48,0), Size=UD2(1,-48,1,0),
        Font=ENUM.Font.GothamBold, Text="肌肉之王 v39",
        TextColor3=TH.Text, TextSize=15,
    }, pillFrame)

    local pillDrag, pillDS, pillDSP, pillStart = false, nil, nil, 0
    S.track(pillFrame.InputBegan:Connect(function(input)
        if input.UserInputType ~= ENUM.UserInputType.MouseButton1 and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        pillDrag = true
        pillDS = input.Position
        pillDSP = pillFrame.Position
        pillStart = tick()
    end))
    S.track(UIS_IC:Connect(function(input)
        if not pillDrag then return end
        if input.UserInputType ~= ENUM.UserInputType.MouseMovement and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        local d = input.Position - pillDS
        pillFrame.Position = UD2(pillDSP.X.Scale, pillDSP.X.Offset+d.X,
                                 pillDSP.Y.Scale, pillDSP.Y.Offset+d.Y)
    end))
    S.track(UIS_IE:Connect(function(input)
        if input.UserInputType ~= ENUM.UserInputType.MouseButton1 and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        if pillDrag then
            local elapsed = tick() - pillStart
            local moved = (input.Position - (pillDS or input.Position)).Magnitude
            if moved < 5 and elapsed < 0.35 then
                pillFrame.Visible = false
                main.Visible = true
            else
                S.UIState.pillPos = S.serializePos(pillFrame.Position)
            end
            pillDrag = false
        end
    end))

    S.track(pillBtn.MouseButton1Click:Connect(function()
        main.Visible = false; pillFrame.Visible = true
    end))
    -- ★ 关闭脚本二次确认
    S.track(closeBtn.MouseButton1Click:Connect(function()
        S.showConfirm("关闭脚本", "确定要完全关闭脚本吗？所有功能会停止。", function()
            S.destroy()
        end)
    end))
    if S.UIState.pillPos then
        pillFrame.Position = S.deserializePos(S.UIState.pillPos, UD2(0.5, 0, 0.18, 0))
    end
end

S.applyFontScale = function()
    if not S.ui.screen then return end
    local scale = S.fontScale
    for _, d in ipairs(S.ui.screen:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            if not d:GetAttribute("_MK_OrigSize") then
                d:SetAttribute("_MK_OrigSize", d.TextSize)
            end
            local orig = d:GetAttribute("_MK_OrigSize") or d.TextSize
            d.TextSize = math.floor(orig * scale)
        end
    end
end

S.applyUISize = function()
    if not S.ui.main then return end
    local cam = Workspace.CurrentCamera; if not cam then return end
    local vp = cam.ViewportSize
    local w = math.max(420, vp.X * S.uiWidthPct / 100)
    local h = math.max(320, vp.Y * S.uiHeightPct / 100)
    S.ui.main.Size = UDO(w, h)
    if S.ui.contentArea then S.ui.contentArea.Size = UD2(1, 0, 1, -(46+38)) end
    if S.ui.infoScale then
        local s = math.clamp(vp.Y/900, 0.7, 1.6) * (S.infoScale/100)
        S.ui.infoScale.Scale = s
    end
end
S.applyUIOpacity = function()
    if S.ui.main then S.ui.main.BackgroundTransparency = 1 - S.uiBgOpacity end
    if S.ui.contentArea then S.ui.contentArea.BackgroundTransparency = 1 - S.uiPageOpacity end
    if S.Info.frames.frame then S.Info.frames.frame.BackgroundTransparency = 1 - S.infoBgOpacity end
end

-- 信息窗
S.buildInfoWindow = function()
    local TH = S.theme
    local Info = S.Info
    local screen = S.create("ScreenGui", {
        Name="MK_AUTO_INFO", ResetOnSpawn=false,
        ZIndexBehavior=ENUM.ZIndexBehavior.Sibling, DisplayOrder=99998,
    }, PG)
    S.ui.infoGui = screen
    screen.Enabled = false
    S.ui.infoScale = S.create("UIScale", {Scale=1}, screen)
    local frame = S.create("Frame", {
        Name="InfoFrame", AnchorPoint=V2(0,0),
        Position=S.deserializePos(S.savedInfoPos, UD2(1,-340,1,-500)),
        Size=S.deserializeSize(S.savedInfoSize, UDO(340, 500)),
        BackgroundColor3=TH.Bg, BorderSizePixel=0, ClipsDescendants=true, Active=true,
    }, screen)
    Info.frames.frame = frame
    S.corner(frame, 12); S.stroke(frame, TH.Border, 1)
    local tb = S.create("Frame", {
        Size=UD2(1,0,0,42), BackgroundColor3=TH.Surface, BorderSizePixel=0, Active=true,
    }, frame)
    S.corner(tb, 12)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(14,0), Size=UD2(1,-100,1,0),
        Font=ENUM.Font.GothamBold, Text="实时信息", TextColor3=TH.Text,
        TextSize=17, TextXAlignment=ENUM.TextXAlignment.Left,
    }, tb)
    local minBtn = S.create("TextButton", {
        Size=UDO(26,26), Position=UD2(1,-60,0,8), BackgroundColor3=TH.SurfaceAlt,
        BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text="—", TextColor3=TH.Text, TextSize=14,
    }, tb); S.corner(minBtn, 6)
    local closeBtn = S.create("TextButton", {
        Size=UDO(26,26), Position=UD2(1,-32,0,8), BackgroundColor3=TH.Danger,
        BorderSizePixel=0, Font=ENUM.Font.GothamBold, Text="✕", TextColor3=TH.OnAccent, TextSize=14,
    }, tb); S.corner(closeBtn, 6)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(14,44), Size=UD2(1,-28,0,18),
        Font=ENUM.Font.Gotham, Text="服务器："..(game.JobId or ""):sub(1,24),
        TextColor3=TH.TextDim, TextSize=11, TextXAlignment=ENUM.TextXAlignment.Left,
    }, frame)
    S.create("TextLabel", {
        BackgroundTransparency=1, Position=UDO(14,62), Size=UD2(1,-28,0,18),
        Font=ENUM.Font.Gotham, Text="游戏 ID："..tostring(game.PlaceId),
        TextColor3=TH.TextDim, TextSize=11, TextXAlignment=ENUM.TextXAlignment.Left,
    }, frame)
    local playerBtn = S.create("TextButton", {
        Position=UDO(12,84), Size=UD2(1,-24,0,32),
        BackgroundColor3=TH.Surface, BorderSizePixel=0, Font=ENUM.Font.GothamBold,
        Text="查看：自己", TextColor3=TH.Text, TextSize=15,
    }, frame)
    S.corner(playerBtn, 8); S.stroke(playerBtn, TH.Border, 1, 0.5)
    Info.frames.playerBtn = playerBtn
    local listFrame = S.create("ScrollingFrame", {
        Position=UDO(12,122), Size=UD2(1,-24,0,220),
        BackgroundColor3=TH.Surface, BorderSizePixel=0,
        ScrollBarThickness=5, ScrollBarImageColor3=TH.Accent,
        CanvasSize=UD2(0,0,0,0), AutomaticCanvasSize=ENUM.AutomaticSize.Y,
        ScrollingDirection=ENUM.ScrollingDirection.Y, Visible=false, ZIndex=5,
    }, frame)
    S.corner(listFrame, 8); S.stroke(listFrame, TH.Border, 1)
    S.listLayout(listFrame, 4); S.padding(listFrame, 5, 5, 5, 5)
    Info.frames.listFrame = listFrame
    local dataFrame = S.create("ScrollingFrame", {
        Position=UDO(0,124), Size=UD2(1,0,1,-124), BackgroundTransparency=1,
        BorderSizePixel=0, ScrollBarThickness=5, ScrollBarImageColor3=TH.Accent,
        CanvasSize=UD2(0,0,0,0), AutomaticCanvasSize=ENUM.AutomaticSize.Y,
        ScrollingDirection=ENUM.ScrollingDirection.Y, ClipsDescendants=true,
    }, frame)
    S.padding(dataFrame, 8, 8, 12, 12); S.listLayout(dataFrame, 5)
    Info.frames.dataFrame = dataFrame
    local function mkRow(label, order)
        local row = S.create("Frame", {
            Size=UD2(1,0,0,24), BackgroundTransparency=1, LayoutOrder=order,
        }, dataFrame)
        S.create("TextLabel", {
            BackgroundTransparency=1, Size=UD2(0.55,0,1,0),
            Font=ENUM.Font.GothamBold, Text=label, TextColor3=TH.TextDim,
            TextSize=14, TextXAlignment=ENUM.TextXAlignment.Left,
        }, row)
        local val = S.create("TextLabel", {
            BackgroundTransparency=1, Position=UD2(0.55,0,0,0), Size=UD2(0.45,0,1,0),
            Font=ENUM.Font.GothamBold, Text="-", TextColor3=TH.Text,
            TextSize=14, TextXAlignment=ENUM.TextXAlignment.Right,
        }, row)
        return val
    end
    Info.rows.strength=mkRow("力量",1); Info.rows.strengthDelta=mkRow("力量增量",2)
    Info.rows.gems=mkRow("宝石",3); Info.rows.durability=mkRow("耐力",4)
    Info.rows.rebirths=mkRow("重生",5); Info.rows.rebirthRate=mkRow("重生速度(个/时)",6)
    Info.rows.petRep=mkRow("宠物反复%",7); Info.rows.ultRep=mkRow("终极反复%",8)
    Info.rows.passRep=mkRow("通行证",9)
    Info.rows.speedMul=mkRow("综合速度",10); Info.rows.perHour=mkRow("每小时预计",11)
    Info.rows.pingRow=mkRow("网络延迟",12); Info.rows.memRow=mkRow("内存占用",13)
    Info.rows.uptimeRow=mkRow("运行时长",14)
    Info.rows.rebPredict=mkRow("重生预测",15)

    local dragging, dragStart, startPos = false, nil, nil
    S.track(tb.InputBegan:Connect(function(input)
        if input.UserInputType ~= ENUM.UserInputType.MouseButton1 and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        dragging = true; dragStart = input.Position; startPos = frame.Position
    end))
    S.track(UIS_IC:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= ENUM.UserInputType.MouseMovement and input.UserInputType ~= ENUM.UserInputType.Touch then return end
        local d = input.Position - dragStart
        frame.Position = UD2(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end))
    S.track(UIS_IE:Connect(function(input)
        if input.UserInputType == ENUM.UserInputType.MouseButton1 or input.UserInputType == ENUM.UserInputType.Touch then
            if dragging then S.savedInfoPos = S.serializePos(frame.Position); dragging = false end
        end
    end))
    S.track(minBtn.MouseButton1Click:Connect(function()
        Info.minimized = not Info.minimized
        if Info.minimized then
            playerBtn.Visible = false; listFrame.Visible = false; dataFrame.Visible = false
            frame.Size = UDO(frame.Size.X.Offset, 42); minBtn.Text = "+"
        else
            playerBtn.Visible = true; dataFrame.Visible = true
            frame.Size = S.deserializeSize(S.savedInfoSize, UDO(340, 500)); minBtn.Text = "—"
        end
    end))
    S.track(closeBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        S.infoWindowEnabled = false
        if S.ui.infoToggle then S.ui.infoToggle.set(false) end
        Info.minimized = false; Info.listOpen = false
    end))

    S.track(playerBtn.MouseButton1Click:Connect(function()
        Info.listOpen = not Info.listOpen
        listFrame.Visible = Info.listOpen
        if Info.listOpen then
            for _, c in ipairs(listFrame:GetChildren()) do
                if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
            end
            local ord = 0
            local function addRow(plr)
                ord = ord + 1
                local display = plr.DisplayName or plr.Name
                local head
                if display ~= plr.Name then head = display.." (@"..plr.Name..")"
                else head = plr.Name end
                if plr == LP then head = head.." ⭐" end
                if S.friendWhitelist and plr ~= LP and S.isFriend(plr) then head = head.." [友]" end

                local str = S.stat(plr, "Strength")
                local reb = S.stat(plr, "Rebirths")
                local dur = S.stat(plr, "Durability")
                local rate = (plr == LP) and S.rebirthPerSec or 0
                local p1, p7, p30
                if rate > 0 then
                    p1 = rate * 3600 * 24
                    p7 = p1 * 7
                    p30 = p1 * 30
                else p1, p7, p30 = 0, 0, 0 end

                local row = S.create("Frame", {
                    Size=UD2(1,0,0,72), BackgroundColor3=TH.SurfaceAlt,
                    BorderSizePixel=0, LayoutOrder=ord,
                }, listFrame)
                S.corner(row, 6)

                local titleBtn = S.create("TextButton", {
                    Size=UD2(1,0,0,24), Position=UDO(0,2),
                    BackgroundTransparency=1, Text=head,
                    Font=ENUM.Font.GothamBold, TextColor3=TH.Text,
                    TextSize=14, TextXAlignment=ENUM.TextXAlignment.Left,
                }, row)
                S.padding(titleBtn, 0, 0, 8, 8)

                S.create("TextLabel", {
                    Size=UD2(1,0,0,18), Position=UDO(8,26),
                    BackgroundTransparency=1,
                    Text=string.format("重生:%s  力量:%s  耐力:%s",
                        S.formatNumber(reb), S.formatNumber(str), S.formatNumber(dur)),
                    Font=ENUM.Font.Gotham, TextColor3=TH.TextDim,
                    TextSize=12, TextXAlignment=ENUM.TextXAlignment.Left,
                }, row)
                S.create("TextLabel", {
                    Size=UD2(1,0,0,18), Position=UDO(8,44),
                    BackgroundTransparency=1,
                    Text=string.format("预测+%s / %s / %s (1/7/30天)",
                        S.formatNumber(p1), S.formatNumber(p7), S.formatNumber(p30)),
                    Font=ENUM.Font.Gotham, TextColor3=TH.Accent,
                    TextSize=12, TextXAlignment=ENUM.TextXAlignment.Left,
                }, row)

                S.track(titleBtn.MouseButton1Click:Connect(function()
                    Info.viewingPlayer = plr
                    if plr == LP then playerBtn.Text = "查看：自己"
                    else playerBtn.Text = "查看："..plr.Name end
                    Info.listOpen = false; listFrame.Visible = false
                end))
            end
            addRow(LP)
            for _, plr in ipairs(GetPlayers(Players)) do if plr ~= LP then addRow(plr) end end
        end
    end))
    Info.viewingPlayer = LP
    S.reopenInfoWindow = function()
        Info.minimized = false; Info.listOpen = false
        frame.Visible = true
        playerBtn.Visible = true; dataFrame.Visible = true
        minBtn.Text = "—"
        frame.Size = S.deserializeSize(S.savedInfoSize, UDO(340, 500))
        screen.Enabled = true
        S.infoWindowEnabled = true
        if S.ui.infoToggle then S.ui.infoToggle.set(true) end
    end
end

S.refreshInfoWindow = function()
    local Info = S.Info
    if not Info.frames.frame or not S.ui.infoGui then return end
    if not S.ui.infoGui.Enabled or Info.minimized then return end
    local plr = Info.viewingPlayer
    if not plr or not plr.Parent then Info.viewingPlayer = LP; plr = LP end
    local isSelf = (plr == LP)
    Info.rows.strength.Text = S.formatNumber(S.stat(plr, "Strength"))
    Info.rows.gems.Text = S.formatNumber(S.stat(plr, "Gems"))
    Info.rows.durability.Text = S.formatNumber(S.stat(plr, "Durability"))
    Info.rows.rebirths.Text = S.formatNumber(S.stat(plr, "Rebirths"))
    if isSelf then
        if S.sessionStartStrength then
            local d = S.stat(plr, "Strength") - S.sessionStartStrength
            Info.rows.strengthDelta.Text = (d>=0 and "+" or "")..S.formatNumber(d)
            Info.rows.strengthDelta.TextColor3 = d>=0 and S.theme.Success or S.theme.Danger
        end
        if S.rebirthPerSec > 0 then
            Info.rows.rebirthRate.Text = string.format("%.0f", S.rebirthPerSec * 3600)
            Info.rows.rebirthRate.TextColor3 = S.theme.Success
        else
            Info.rows.rebirthRate.Text = "0"
            Info.rows.rebirthRate.TextColor3 = S.theme.TextDim
        end
        local RC = S.repCache
        Info.rows.petRep.Text = string.format("%d%%", RC.pet)
        Info.rows.ultRep.Text = string.format("%d%%", RC.ult)
        Info.rows.passRep.Text = RC.x2 and "x2 已拥有" or "无"
        Info.rows.passRep.TextColor3 = RC.x2 and S.theme.Success or S.theme.TextDim
        Info.rows.speedMul.Text = string.format("%.2fx", RC.speedMul)
        Info.rows.perHour.Text = S.formatNumber(S.strengthPerSec * 3600)
        local p = S.ping
        Info.rows.pingRow.Text = p > 0 and (math.floor(p).." ms") or "-"
        if p > 0 then
            Info.rows.pingRow.TextColor3 = p<80 and S.theme.Success or (p<200 and S.theme.Warning or S.theme.Danger)
        end
        Info.rows.memRow.Text = string.format("%d MB", S.memMb or 0)
        local up = math.floor(S.sessionUptime or 0)
        local uh = math.floor(up/3600); local um = math.floor((up%3600)/60)
        Info.rows.uptimeRow.Text = string.format("%dh %dm", uh, um)
        if S.rebirthPerSec > 0 then
            local p1 = S.rebirthPerSec * 3600 * 24
            local p7 = p1 * 7
            local p30 = p1 * 30
            Info.rows.rebPredict.Text = string.format("+%s / %s / %s",
                S.formatNumber(p1), S.formatNumber(p7), S.formatNumber(p30))
            Info.rows.rebPredict.TextColor3 = S.theme.Accent
        else
            Info.rows.rebPredict.Text = "-"
            Info.rows.rebPredict.TextColor3 = S.theme.TextDim
        end
    else
        for _, k in ipairs({"strengthDelta","rebirthRate","petRep","ultRep","passRep","speedMul","perHour","pingRow","memRow","uptimeRow","rebPredict"}) do
            Info.rows[k].Text = "-"
            Info.rows[k].TextColor3 = S.theme.TextMuted
        end
    end
end

S.destroy = function()
    if S.destroyed then return end
    pcall(S.saveConfig)
    S.destroyed = true
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    table.clear(S.conns)
    S.cancelAllThreads()
    S.restoreAllEnlarged()
    pcall(S.releaseGravityLock)
    pcall(function() Workspace.Gravity = S.originalGravity end)
    -- ★ 恢复玩家移动
    pcall(function()
        local hum = S.cache.hum
        if hum then hum.WalkSpeed = S._origWalkSpeed or 16 end
    end)
    pcall(S.disableAntiLag); pcall(S.disableRenderCull)
    pcall(S.restoreHiddenPets); pcall(S.restoreHiddenMachines)
    pcall(S.disableTex); pcall(S.restoreHiddenUI)
    if S.bossHoverConn then pcall(function() S.bossHoverConn:Disconnect() end) end
    if S.ui.screen then pcall(function() S.ui.screen:Destroy() end); S.ui.screen = nil end
    if S.ui.infoGui then pcall(function() S.ui.infoGui:Destroy() end); S.ui.infoGui = nil end
    pcall(function() collectgarbage("collect") end)
    if _G[PLUGIN_ID] and _G[PLUGIN_ID].version == VERSION then _G[PLUGIN_ID] = nil end
end

-- ============================================================
-- 启动
-- ============================================================
S.loadConfig()
S.buildUI()
S.buildInfoWindow()
S.applyUISize()
S.applyUIOpacity()
S.applyFontScale()

if S.antiLagEnabled then pcall(S.enableAntiLag) end
if S.textureRemoverEnabled then pcall(S.enableTex) end
if S.hideUIEnabled then pcall(S.hideAllOtherUI) end
if S.infoWindowEnabled and S.ui.infoGui then
    if S.reopenInfoWindow then S.reopenInfoWindow() end
    S.ui.infoGui.Enabled = true
end
if S.friendWhitelist then task.delay(2, function() S.refreshFriendList() end) end

local cam = Workspace.CurrentCamera
if cam then S.track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(S.applyUISize)) end

S.track(UserInputService.JumpRequest:Connect(function()
    S._jumpCdUntil = tick() + 3
    S.machineState.using = false
end))

S.track(LP.CharacterAdded:Connect(function()
    S.cache.char = nil; S.cache.hum = nil; S.cache.hrp = nil
    S.killTarget = nil; S.kingKillTarget = nil; S.kingKillActive = false
    S.toolCooldown = false; S.toolOwnedByKill = false
    S.dualCurrentMode = "punch"
    S.muscleEventRef = nil
    S.rebirthEventRef = nil; S.lastRebirthScan = 0
    S.portalCache = nil; S.portalCacheAt = 0
    S._missingSince = 0; S._lastSuicide = 0; S._suicideCount = 0
    S.bossKilledAt = 0; S.bossWasAlive = false; S.chestTaskActive = false
    S.bossDeathPos = nil
    S.petPreset.activeType = nil
    S.trainAccum = 0
    table.clear(S._enlargedTargets)
    table.clear(S.renderCull.hidden)
    table.clear(S.petHider.own); table.clear(S.petHider.all); table.clear(S.petHider.machines)
    task.wait(0.5)
    pcall(S.setupGravityLock)
    if S.hideUIEnabled then pcall(S.hideAllOtherUI) end
    -- ★ 恢复新角色移动速度（关键！防止重生后被锁死）
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = S._origWalkSpeed or 16
        end
    end)
end))

S.track(LP.AncestryChanged:Connect(function()
    if S.emergencyRejoin and not S._rejoinTriggered then
        S.notify("检测到离开游戏", 3)
        task.wait(0.5)
        S.rejoinGame("被踢出", true)
    end
end))

task.spawn(function()
    task.wait(1)
    pcall(S.setupGravityLock)
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then S._origWalkSpeed = hum.WalkSpeed end
    end)
end)

S.track(HB:Connect(S.onHeartbeat))
_G[PLUGIN_ID] = {version=VERSION, cleanup=S.destroy}
S.notify("肌肉之王自动化 v39 已加载（继承 v38 配置）", 4)
