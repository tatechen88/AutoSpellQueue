-------------------------------------------------------------------------------
--  AutoSpellQueue.lua
--
--  Runtime core: config, ownership, decision and application.
--
--  Design rules (these are the fixes for the issues found in the review):
--
--  1. A CVar write is only reported as applied when the write was verified
--     (see AutoSpellQueue_CVar.lua). A failure keeps the diagnostic state and
--     is retried on the next refresh instead of being silently dropped.
--  2. Ownership of the user's value is explicit and persisted. While the addon
--     manages the CVar it remembers the value the player had before, so
--     disabling the addon - or logging out - can put it back. Ownership is
--     only released, never overwritten, when somebody else changed the value.
--  3. There is no "pendingTarget" snapshot to replay. After combat the addon
--     re-reads the live state and decides again, so a combat-time enable or
--     disable cannot apply a stale value.
--  4. The addon does NOT poll on a fixed short timer. It samples only while it
--     is learning the connection (login, zone change, entering an instance or
--     raid, spec change, external edits, or a drift check that found movement)
--     and then settles, remembering the learned latency for the next session.
--     See the sampling policy comment below Core.WINDOW_MIN.
--  5. Saved settings are validated on load. Unknown/future schema versions are
--     never silently downgraded.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Formula = ns.Formula
local CVar = ns.CVar
local Latency = ns.Latency

local Core = {}
ns.Core = Core

-- Exposed for /dump and troubleshooting; the addon name is unique.
_G.AutoSpellQueue = Core

Core.NAME = ADDON_NAME
Core.SV = "AutoSpellQueueDB"
Core.LEGACY_SV = "Tate_ASQDB"
Core.SCHEMA_VERSION = 2

-- Sampling policy.
--
-- The addon used to re-read the client every 15 seconds forever, which is
-- pointless work: latency does not move much within minutes, and the events
-- that actually change the answer (login, zone change, entering an instance or
-- a raid, a spec change, another addon touching the CVar) are all delivered to
-- us anyway. So it samples only while it is *learning* the connection and then
-- settles:
--
--   settling  -> sample every SETTLE_INTERVAL until the smoothed value stops
--                moving, then remember it and go quiet
--   pending   -> a write or a restore still has to reach the client: keep
--                retrying (short-lived; combat ends, writes succeed)
--   settled   -> one cheap drift check every HEARTBEAT_SECONDS; a check only
--                re-samples when the reading moved past DRIFT_DEADBAND
Core.SETTLE_INTERVAL = 15
Core.PENDING_INTERVAL = 15
Core.RETRY_INTERVAL = 60        -- a write that failed: retry, but not every 15 s
Core.RETRY_ATTEMPTS = 3         -- after this many failures, back off to the heartbeat
Core.HEARTBEAT_SECONDS = 300
Core.MAX_SETTLE_SAMPLES = 8

-- Retry schedule used while the client has no latency reading yet.
Core.WARMUP_DELAYS = { 2, 5, 10, 20, 40 }

-- Safety rails for the value we write, in ms. They are deliberately not
-- settings: below 50 the queue is effectively off, and the client caps it at
-- 400 anyway.
Core.WINDOW_MIN = 50
Core.WINDOW_MAX = 400

Core.STATE = {
    IDLE = "idle",
    DISABLED = "disabled",
    APPLIED = "applied",
    PENDING = "pending",
    ERROR = "error",
    UNAVAILABLE = "unavailable",
}

-------------------------------------------------------------------------------
--  Localisation hook (AutoSpellQueue_Locale.lua sets ns.L when present)
--  Resolved at call time so load order can never leave the core without it.
-------------------------------------------------------------------------------
function Core.L(key)
    local translate = ns.L
    if translate then return translate(key) end
    return key
end

-------------------------------------------------------------------------------
--  Configuration schema
--
--  v2 keeps only what a player can reasonably have an opinion about:
--    enabled     - the master switch
--    showStatus  - draw the floating readout
--    baseOverride- command-only escape hatch (/asq base 180), not in the panel
--  Everything else (safety margin, hysteresis, latency source, per-context
--  behaviour, window rails) is computed by AutoSpellQueue_Latency.lua or fixed
--  here, because the addon can measure those things better than a player can
--  guess them.
-------------------------------------------------------------------------------
Core.DEFAULTS = {
    schemaVersion = 2,
    enabled = true,
    showStatus = true,
    statusBarPos = nil,
    baseOverride = nil,         -- number (50..400) | nil = follow the spec table
    ownership = nil,
    stats = nil,
    -- Bookkeeping, not a setting: the latency learned last time, so login can
    -- apply the right value immediately instead of waiting for GetNetStats().
    latencyCache = nil,
}

-- Keys that may be written through SetConfig even though their default is nil.
local OPTIONAL_KEYS = {
    statusBarPos = true,
    baseOverride = true,
    ownership = true,
    latencyCache = true,
}

local LIMITS = {
    baseOverride = { 50, 400 },
}

local BOOLEAN_KEYS = {
    "enabled", "showStatus",
}

-- Maps a CVar failure reason to a locale key (shared with the options panel).
Core.REASON_KEY = {
    [CVar.ERR_READONLY] = "ERR_READONLY",
    [CVar.ERR_COMBAT] = "ERR_COMBAT",
    [CVar.ERR_UNAVAILABLE] = "ERR_UNAVAILABLE",
    [CVar.ERR_REJECTED] = "ERR_REJECTED",
    [CVar.ERR_VERIFY] = "ERR_VERIFY_FAILED",
    [CVar.ERR_NO_API] = "ERR_NO_API",
    [CVar.ERR_INVALID_VALUE] = "ERR_INVALID_VALUE",
}

local function Now()
    if type(time) == "function" then return time() end
    if os and os.time then return os.time() end
    return 0
end
Core.Now = Now

local function IsFiniteNumber(v)
    local n = tonumber(v)
    if n == nil then return nil end
    if n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-------------------------------------------------------------------------------
--  Validation
-------------------------------------------------------------------------------

--- Normalises a settings table in place.
--  Returns: db, repairCount
function Core.Sanitize(db)
    local repairs = 0
    if type(db) ~= "table" then
        db = {}
        repairs = repairs + 1
    end

    -- Fill missing keys from the defaults (tables are copied, never shared).
    for key, default in pairs(Core.DEFAULTS) do
        if db[key] == nil and default ~= nil then
            if type(default) == "table" then
                local copy = {}
                for k, v in pairs(default) do copy[k] = v end
                db[key] = copy
            else
                db[key] = default
            end
        end
    end

    for _, key in ipairs(BOOLEAN_KEYS) do
        local v = db[key]
        if type(v) ~= "boolean" then
            if v == nil then
                db[key] = Core.DEFAULTS[key]
            else
                db[key] = not not v
                repairs = repairs + 1
            end
        end
    end

    for key, range in pairs(LIMITS) do
        local raw = db[key]
        if raw == nil then
            db[key] = Core.DEFAULTS[key] -- stays nil for the optional keys
        else
            local n = IsFiniteNumber(raw)
            if n == nil then
                db[key] = Core.DEFAULTS[key]
                repairs = repairs + 1
            else
                local clamped = Formula.Clamp(math.floor(n + 0.5), range[1], range[2])
                if clamped ~= n then repairs = repairs + 1 end
                db[key] = clamped
            end
        end
    end

    -- Keys retired in schema v2 (they used to be player settings) must not
    -- linger in the save file: they would come back as unknown data forever.
    for _, key in ipairs({ "baseMode", "manualBase", "adaptive", "latencySource",
        "margin", "minWindow", "maxWindow", "hysteresis",
        "statusFont", "statusFontSize", "chatFeedback", "showAdvanced" }) do
        if db[key] ~= nil then
            db[key] = nil
            repairs = repairs + 1
        end
    end

    local pos = db.statusBarPos
    if pos ~= nil then
        if type(pos) ~= "table" or IsFiniteNumber(pos.x) == nil or IsFiniteNumber(pos.y) == nil then
            db.statusBarPos = nil
            repairs = repairs + 1
        end
    end

    -- Remembered latency: only a plausible round-trip time is kept, so a
    -- corrupted save cannot pin the window to nonsense.
    local cache = db.latencyCache
    if cache ~= nil then
        local value = type(cache) == "table" and IsFiniteNumber(cache.value) or nil
        local jitter = type(cache) == "table" and IsFiniteNumber(cache.jitter) or 0
        if value == nil or value < 1 or value > 999 then
            db.latencyCache = nil
            repairs = repairs + 1
        else
            db.latencyCache = {
                value = math.floor(value + 0.5),
                jitter = math.max(0, math.floor((jitter or 0) + 0.5)),
                samples = math.max(0, math.floor(IsFiniteNumber(cache.samples) or 0)),
                at = IsFiniteNumber(cache.at),
            }
        end
    end

    local own = db.ownership
    if own ~= nil then
        local baseline = type(own) == "table" and IsFiniteNumber(own.baseline) or nil
        if type(own) ~= "table" or own.active ~= true or baseline == nil or
            baseline < 0 or baseline > CVar.MAX then
            db.ownership = nil
            repairs = repairs + 1
        else
            local lastApplied = IsFiniteNumber(own.lastApplied)
            db.ownership = {
                active = true,
                schema = Core.SCHEMA_VERSION,
                baseline = math.floor(baseline + 0.5),
                lastApplied = lastApplied and math.floor(lastApplied + 0.5) or nil,
                startedAt = IsFiniteNumber(own.startedAt),
            }
        end
    end

    local stats = db.stats
    if type(stats) ~= "table" then
        stats = {}
    end
    stats.applied = math.max(0, math.floor(IsFiniteNumber(stats.applied) or 0))
    stats.repairs = math.max(0, math.floor(IsFiniteNumber(stats.repairs) or 0)) + repairs
    stats.lastError = type(stats.lastError) == "string" and stats.lastError or nil
    stats.lastNotifiedError = type(stats.lastNotifiedError) == "string" and stats.lastNotifiedError or nil
    stats.lastErrorAt = IsFiniteNumber(stats.lastErrorAt)
    stats.lastMessageAt = IsFiniteNumber(stats.lastMessageAt)
    stats.externalChangeAt = IsFiniteNumber(stats.externalChangeAt)
    db.stats = stats

    return db, repairs
end

-------------------------------------------------------------------------------
--  Migration
-------------------------------------------------------------------------------

-- Ordered schema migrations: MIGRATIONS[n] upgrades schema (n-1) -> n.
local MIGRATIONS = {
    -- v1 -> v2: the addon stopped asking the player to configure the algorithm.
    -- A manual base value is the one thing a player may have deliberately set,
    -- so it is carried over as the (command-only) override instead of being
    -- thrown away; every other retired key is dropped by Sanitize.
    [2] = function(db)
        if db.baseMode == "manual" and IsFiniteNumber(db.manualBase) then
            local manual = IsFiniteNumber(db.manualBase)
            if manual >= 50 and manual <= 400 then
                db.baseOverride = math.floor(manual + 0.5)
            end
        end
    end,
}

--- Brings a loaded table up to Core.SCHEMA_VERSION.
--  A table written by a newer addon version is left untouched and flagged.
function Core.Migrate(db)
    local version = IsFiniteNumber(db.schemaVersion) or 0
    if version > Core.SCHEMA_VERSION then
        -- Never downgrade a future schema: keep every field as-is.
        db.schemaFuture = true
        return db
    end
    for step = version + 1, Core.SCHEMA_VERSION do
        local fn = MIGRATIONS[step]
        if fn then fn(db) end
    end
    db.schemaVersion = Core.SCHEMA_VERSION
    db.schemaFuture = nil
    return db
end

--- Imports settings from the pre-rename SavedVariables (Tate_ASQDB).
--  The legacy variable is cleared afterwards so the client stops writing it.
--
--  IMPORTANT precondition: the client only loads WTF\...\SavedVariables\
--  <AddOnFolderName>.lua. The old settings live in Tate_ASQ.lua, so deleting
--  the old addon folder means nothing reads that file any more and this import
--  simply finds nothing. For the import to run, the player has to copy that
--  file to AutoSpellQueue.lua once (see README "upgrading"). Declaring
--  Tate_ASQDB in the .toc is what makes the renamed file reach this function.
--  Without the copy the addon starts from the defaults - that is expected, not
--  a failure, so nothing is reported to the player here.
function Core.ImportLegacy()
    local old = _G[Core.LEGACY_SV]
    if type(old) ~= "table" then return nil end
    local imported = {}
    local keys = {
        "enabled", "baseMode", "manualBase", "showStatus", "statusBarPos",
    }
    for _, key in ipairs(keys) do
        if old[key] ~= nil then imported[key] = old[key] end
    end
    imported.importedFrom = "Tate_ASQ"
    imported.importedAt = Now()
    _G[Core.LEGACY_SV] = nil
    return imported
end

-------------------------------------------------------------------------------
--  Config access
-------------------------------------------------------------------------------
Core.db = nil

local function LoadConfig()
    local db = _G[Core.SV]
    if type(db) ~= "table" then
        db = Core.ImportLegacy() or {}
        _G[Core.SV] = db
    end
    db = Core.Migrate(db)
    db = Core.Sanitize(db)
    Core.db = db
    return db
end

function Core.GetConfig()
    if not Core.db then return LoadConfig() end
    return Core.db
end

--- Writes a validated setting. Unknown keys are rejected.
--  opts.noRefresh suppresses the immediate re-evaluation.
function Core.SetConfig(key, value, opts)
    local cfg = Core.GetConfig()
    if Core.DEFAULTS[key] == nil and not OPTIONAL_KEYS[key] then
        return false, "unknown-key"
    end
    cfg[key] = value
    Core.Sanitize(cfg)
    if not (opts and opts.noRefresh) then
        Core.Refresh("config:" .. tostring(key))
    end
    return true
end

--- Restores every setting to its default. Ownership of the CVar is kept, so
--- "reset" cannot strand a value the addon set.
function Core.ResetSettings()
    local cfg = Core.GetConfig()
    local ownership = cfg.ownership
    local stats = cfg.stats
    for key, default in pairs(Core.DEFAULTS) do
        if type(default) == "table" then
            local copy = {}
            for k, v in pairs(default) do copy[k] = v end
            cfg[key] = copy
        else
            cfg[key] = default
        end
    end
    -- pairs() skips keys whose default is nil, so clear those explicitly.
    cfg.statusBarPos = nil
    cfg.baseOverride = nil
    cfg.ownership = ownership
    cfg.stats = stats
    cfg.schemaVersion = Core.SCHEMA_VERSION
    Core.Sanitize(cfg)
    Core.Refresh("reset")
    return true
end

-------------------------------------------------------------------------------
--  The algorithm's view of the settings
--
--  The decision functions take one flat table. The player only controls two
--  booleans; everything else is produced here (latency tracker) or fixed.
-------------------------------------------------------------------------------
Core.latency = Latency.New()

--- Builds the table Formula/Decide consume for the current refresh.
function Core.EffectiveOptions()
    local cfg = Core.GetConfig()
    local smoothed, margin, hysteresis = Latency.Describe(Core.latency)
    return {
        -- player settings
        enabled = cfg.enabled,
        ownership = cfg.ownership,
        baseOverride = cfg.baseOverride,
        -- measured
        margin = margin,
        hysteresis = hysteresis,
        latency = smoothed,
        -- fixed policy
        baseMode = cfg.baseOverride and "manual" or "auto",
        manualBase = cfg.baseOverride or 0,
        adaptive = true,
        latencySource = "world",
        minWindow = Core.WINDOW_MIN,
        maxWindow = Core.WINDOW_MAX,
    }
end

--- Feeds the latency tracker from a snapshot. Called once per refresh.
function Core.TrackLatency(snap)
    if not snap then return end
    Latency.Push(Core.latency, snap.world, snap.home)
end

--- Applies the /asq base escape hatch. nil (or "auto") restores the spec table.
function Core.SetBaseOverride(value)
    local cfg = Core.GetConfig()
    if value == nil or value == "auto" then
        cfg.baseOverride = nil
        Core.Refresh("base:auto")
        return true
    end
    local n = tonumber(value)
    if n == nil or n ~= n then return false, "invalid-value" end
    return Core.SetConfig("baseOverride", n)
end

-------------------------------------------------------------------------------
--  Game state
-------------------------------------------------------------------------------

--- Reads spec/class. Returns specID, classFile, specName
local function GetPlayerInfo()
    local specID, specName = 0, nil
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and
        C_SpecializationInfo.GetSpecializationInfo then
        local ok, index = pcall(C_SpecializationInfo.GetSpecialization)
        if ok and index then
            local ok2, id, name = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
            if ok2 and type(id) == "number" and id > 0 then
                specID = id
                specName = name
            end
        end
    elseif GetSpecialization and GetSpecializationInfo then
        local ok, index = pcall(GetSpecialization)
        if ok and index then
            local ok2, id, name = pcall(GetSpecializationInfo, index)
            if ok2 and type(id) == "number" and id > 0 then
                specID = id
                specName = name
            end
        end
    end
    local classFile = "UNKNOWN"
    if UnitClass then
        local ok, _, cls = pcall(UnitClass, "player")
        if ok and cls then classFile = cls end
    end
    return specID, classFile, specName
end

--- Resolves the gameplay context, walking up the map hierarchy so a city
--- sub-map without its own flag is still recognised as a city.
--  Returns context, mapFlags
local function GetContext()
    if IsInInstance then
        local ok, inInstance = pcall(IsInInstance)
        if ok and inInstance then return Formula.ClassifyContext(true, nil), nil end
    end

    local flags = nil
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and mapID then
            local depth = 0
            while mapID and depth < 4 do
                local ok2, info = pcall(C_Map.GetMapInfo, mapID)
                if not ok2 or type(info) ~= "table" then break end
                if info.flags then
                    flags = info.flags
                    if Formula.HasFlag(info.flags, Formula.CITY_MAP_FLAG) then
                        return Formula.ClassifyContext(false, info.flags), info.flags
                    end
                end
                mapID = info.parentMapID
                depth = depth + 1
            end
        end
    end
    return Formula.ClassifyContext(false, flags), flags
end

--- Everything the decision needs, read once per refresh.
function Core.Snapshot()
    local specID, classFile, specName = GetPlayerInfo()
    local home, world = 0, 0
    if GetNetStats then
        local ok, _, _, h, w = pcall(GetNetStats)
        if ok then
            home, world = Formula.SafeNumber(h), Formula.SafeNumber(w)
        end
    end
    local context, mapFlags = GetContext()
    local current, readErr = CVar:Read()
    local cvarInfo = CVar:Info()
    local inCombat = false
    if InCombatLockdown then
        local ok, value = pcall(InCombatLockdown)
        inCombat = ok and value and true or false
    end
    return {
        specID = specID,
        classFile = classFile,
        specName = specName,
        home = home,
        world = world,
        context = context,
        mapFlags = mapFlags,
        current = current,
        readErr = readErr,
        cvarInfo = cvarInfo,
        inCombat = inCombat,
        at = Now(),
    }
end

-------------------------------------------------------------------------------
--  Decision (pure: no side effects, no game API - unit tested)
-------------------------------------------------------------------------------

--- Decides what to do for a snapshot.
--  Returns an action table:
--    kind = "none" | "apply" | "restore" | "wait" | "release" | "unavailable"
--    state, target, value, reason, externalChange, base, role, latency, context
function Core.Decide(cfg, snap)
    local own = cfg.ownership
    -- The client reports 0 until it has talked to the world server. A fresh
    -- login must not apply a too-low window while that happens, so fall back to
    -- the latency this addon already learned (seeded from the last session).
    local home, world = snap.home, snap.world
    if (not world or world <= 0) and (not home or home <= 0) then
        local known = cfg.latency or 0
        if known > 0 then world = known end
    end
    local target, role, base, latency = Formula.ComputeTarget(
        cfg, snap.specID, snap.classFile, home, world, snap.context)

    local action = {
        kind = "none",
        target = target,
        role = role,
        base = base,
        latency = latency,
        context = snap.context,
    }

    if snap.current == nil then
        action.kind = "unavailable"
        action.reason = snap.readErr or CVar.ERR_UNAVAILABLE
        return action
    end

    if not cfg.enabled then
        if own and own.active then
            if own.lastApplied ~= nil and CVar.SameValue(snap.current, own.lastApplied) then
                if snap.inCombat then
                    -- Same rule as applying: never write during combat. The
                    -- restore is decided again from live state when it ends.
                    action.kind = "wait"
                    action.state = Core.STATE.PENDING
                    return action
                end
                action.kind = "restore"
                action.value = own.baseline
                action.state = Core.STATE.DISABLED
            else
                -- Somebody else changed it while we were off/managing: do not
                -- fight over the value, just stop claiming ownership.
                action.kind = "release"
                action.reason = "external-change"
                action.state = Core.STATE.DISABLED
            end
        else
            action.state = Core.STATE.DISABLED
        end
        return action
    end

    action.state = Core.STATE.APPLIED

    if own and own.active and own.lastApplied ~= nil and
        not CVar.SameValue(snap.current, own.lastApplied) then
        -- Informational only: the baseline is not rebased, the promise stays
        -- "put back what the player had before the addon took over".
        action.externalChange = true
    end

    if CVar.SameValue(snap.current, target) then
        return action
    end

    if own and own.active and own.lastApplied ~= nil and
        math.abs(target - snap.current) < (cfg.hysteresis or 0) then
        return action
    end

    if snap.inCombat then
        action.kind = "wait"
        action.state = Core.STATE.PENDING
        return action
    end

    action.kind = "apply"
    return action
end

-------------------------------------------------------------------------------
--  Diagnostics / notifications
-------------------------------------------------------------------------------
Core.state = Core.STATE.IDLE
Core.stateReason = nil
Core.externalChange = false
Core.lastTarget = nil
Core.lastSnapshot = nil

local function SetError(reason)
    local cfg = Core.GetConfig()
    Core.state = Core.STATE.ERROR
    Core.stateReason = reason
    cfg.stats.lastError = reason
    cfg.stats.lastErrorAt = Now()
    -- Consecutive failures drive the retry backoff (see Core.DesiredInterval).
    Core.failures = (Core.failures or 0) + 1
    Core.NotifyError(reason)
end
Core.SetError = SetError

local function Output(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29fAutoSpellQueue|r: " .. message)
    elseif type(print) == "function" then
        print("AutoSpellQueue: " .. message)
    end
end
Core.Output = Output

--- Errors are always surfaced (throttled), even with chat feedback disabled:
--- a silently failing addon is worse than a chat line.
function Core.NotifyError(reason)
    local cfg = Core.db
    if not cfg then return end
    local key = Core.REASON_KEY[reason] or reason
    local text = Core.L("CHAT_ERROR"):format(Core.L(key))
    local now = Now()
    local last = cfg.stats.lastMessageAt
    if cfg.stats.lastNotifiedError ~= reason or last == nil or (now - last) > 120 then
        cfg.stats.lastNotifiedError = reason
        cfg.stats.lastMessageAt = now
        Output(text)
    end
end

--- Change notifications are intentionally gone: the addon should be invisible
--- while it works. `/asq status` still reports how often it applied a value.
--- Errors (see NotifyError) are the only thing that ever speaks up.

-------------------------------------------------------------------------------
--  Execution
-------------------------------------------------------------------------------

--- Applies an action produced by Decide().
function Core.Execute(action, snap)
    local cfg = Core.GetConfig()
    snap = snap or Core.lastSnapshot
    if snap then
        -- Keep the derived values on the snapshot: the status card reads them
        -- from here and they only exist on the action otherwise.
        snap.role = action.role
        snap.base = action.base
        snap.latency = action.latency
        snap.context = action.context
        snap.inCombat = snap.inCombat and true or false
    end
    Core.lastSnapshot = snap
    if action.target then Core.lastTarget = action.target end
    Core.externalChange = action.externalChange and true or false
    if action.externalChange then
        cfg.stats.externalChangeAt = Now()
    end

    if action.kind == "none" then
        Core.state = action.state or Core.STATE.APPLIED
        Core.stateReason = nil
        return true
    end

    if action.kind == "unavailable" then
        Core.state = Core.STATE.UNAVAILABLE
        Core.stateReason = action.reason
        return false
    end

    if action.kind == "release" then
        cfg.ownership = nil
        Core.state = Core.STATE.DISABLED
        Core.stateReason = nil
        return true
    end

    if action.kind == "wait" then
        -- Nothing is written in combat. There is deliberately no cached target
        -- to replay: PLAYER_REGEN_ENABLED re-reads the world and decides again.
        Core.state = Core.STATE.PENDING
        Core.stateReason = nil
        return true
    end

    if action.kind == "apply" then
        local current = Core.lastSnapshot and Core.lastSnapshot.current
        if not (cfg.ownership and cfg.ownership.active) then
            cfg.ownership = {
                active = true,
                schema = Core.SCHEMA_VERSION,
                baseline = current,
                lastApplied = nil,
                startedAt = Now(),
            }
        end
        local ok, err, applied = CVar:Write(action.target)
        if ok then
            cfg.ownership.lastApplied = applied or action.target
            cfg.stats.applied = (cfg.stats.applied or 0) + 1
            cfg.stats.lastError = nil
            Core.state = Core.STATE.APPLIED
            Core.stateReason = nil
            Core.failures = 0
        else
            -- Ownership is kept so the value can still be restored later.
            SetError(err)
        end
        return ok
    end

    if action.kind == "restore" then
        local ok, err = CVar:Write(action.value)
        if ok then
            cfg.ownership = nil
            Core.state = Core.STATE.DISABLED
            Core.stateReason = nil
            Core.failures = 0
        else
            -- Keep ownership: the next refresh (or logout) retries.
            SetError(err)
        end
        return ok
    end

    return true
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------

--- Ends the learning phase once the value has stopped moving (or after a cap of
--- samples, so a genuinely noisy connection cannot keep the sampler running).
local function UpdateCadence()
    if not Core.settling then return end
    Core.settleSamples = (Core.settleSamples or 0) + 1
    if Latency.IsConverged(Core.latency) or Core.settleSamples >= Core.MAX_SETTLE_SAMPLES then
        Core.settling = false
        Core.settleReason = nil
        Core.RememberLatency()
    end
end

--- Re-reads the game state and applies whatever the current settings require.
function Core.Refresh(reason)
    if not Core.db then return end
    Core.lastReason = reason
    if not Core.inWorld then
        Core.state = Core.STATE.IDLE
        return
    end
    local snap = Core.Snapshot()

    -- A settled addon only wakes up for a drift check, and that check does NOT
    -- feed the tracker: one reading every few minutes must not drag the smoothed
    -- value (the EMA would jump half way on a single sample) and cause writes.
    -- It only decides whether re-learning is worth it.
    if reason == "ticker" and not Core.settling then
        local reading = (snap.world > 0) and snap.world or snap.home
        local known = Latency.Value(Core.latency)
        if not reading or reading <= 0 or known <= 0 then
            Core.BeginSettle("first-reading")
        elseif math.abs(reading - known) > Latency.DRIFT_DEADBAND then
            Core.BeginSettle("drift")
        else
            -- Steady: stay settled and go back to sleep.
            Core.heartbeatSteady = true
            Core.SyncTicker()
            return
        end
        Core.heartbeatSteady = false
    end

    -- Feed the tracker first: this refresh's margin and hysteresis come from
    -- the connection as measured so far, not from a number a player typed.
    Core.TrackLatency(snap)
    local options = Core.EffectiveOptions()
    local action = Core.Decide(options, snap)
    local result = Core.Execute(action, snap)

    UpdateCadence()
    -- A deferred or failed restore must keep retrying even after the addon is
    -- switched off, so the timer follows the work, not just the switch.
    Core.SyncTicker()
    return result
end

--- Puts the player's original value back if the addon still owns it.
--  Returns ok(boolean), reason(string|nil)
function Core.RestoreOwnership(reason)
    local cfg = Core.GetConfig()
    local own = cfg.ownership
    if not (own and own.active) then return true, "not-owned" end

    local current, readErr = CVar:Read()
    if current == nil then
        SetError(readErr or CVar.ERR_UNAVAILABLE)
        return false, readErr or CVar.ERR_UNAVAILABLE
    end
    if own.lastApplied == nil or not CVar.SameValue(current, own.lastApplied) then
        -- Somebody else owns the value now; drop our claim without writing.
        cfg.ownership = nil
        return true, "external-change"
    end
    local ok, err = CVar:Write(own.baseline)
    if ok then
        cfg.ownership = nil
        return true
    end
    SetError(err)
    return false, err
end

function Core.SetEnabled(value)
    local cfg = Core.GetConfig()
    cfg.enabled = value and true or false
    Core.Refresh(cfg.enabled and "enable" or "disable")
    Core.SyncTicker()
    return cfg.enabled
end

function Core.IsEnabled()
    return Core.GetConfig().enabled and true or false
end

-------------------------------------------------------------------------------
--  Status for the UI
-------------------------------------------------------------------------------
--- Live value straight from the client (never a cached snapshot).
--  The status card uses this for "current", while "target" comes from the last
--  computation - the UI must not present the two as if they were sampled
--  at the same moment.
function Core.GetLiveValue()
    local value, err = CVar:Read()
    return value, err
end

function Core.GetStatus()
    local cfg = Core.GetConfig()
    local snap = Core.lastSnapshot or {}
    local own = cfg.ownership
    return {
        enabled = cfg.enabled and true or false,
        state = Core.state,
        stateReason = Core.stateReason,
        stateReasonKey = Core.stateReason and (Core.REASON_KEY[Core.stateReason] or Core.stateReason) or nil,
        current = snap.current,
        live = Core.GetLiveValue(),
        target = Core.lastTarget,
        snapshotAt = snap.at,
        baseline = own and own.baseline or nil,
        lastApplied = own and own.lastApplied or nil,
        owned = (own and own.active) and true or false,
        inCombat = snap.inCombat and true or false,
        inWorld = Core.inWorld and true or false,
        context = snap.context,
        role = snap.role,
        base = snap.base,
        latency = snap.latency,
        home = snap.home,
        world = snap.world,
        specID = snap.specID,
        specName = snap.specName,
        classFile = snap.classFile,
        cvarInfo = snap.cvarInfo,
        lastError = cfg.stats.lastError,
        lastErrorAt = cfg.stats.lastErrorAt,
        applyCount = cfg.stats.applied,
        repairs = cfg.stats.repairs,
        externalChange = Core.externalChange and true or false,
        schemaFuture = cfg.schemaFuture and true or false,
        importedFrom = cfg.importedFrom,
        reason = Core.lastReason,
        -- What the algorithm decided for itself (no longer player settings).
        baseOverride = cfg.baseOverride,
        margin = select(2, Latency.Describe(Core.latency)),
        hysteresis = select(3, Latency.Describe(Core.latency)),
        jitter = Latency.Jitter(Core.latency),
        smoothed = Latency.Value(Core.latency),
        samples = Latency.Count(Core.latency),
        stable = Latency.IsStable(Core.latency),
        -- Sampling policy: what the addon is doing right now and how often it
        -- intends to wake up (nil = it has stopped waking up at all).
        cadence = Core.settling and "settling"
            or (Core.state == Core.STATE.PENDING and "pending" or "fixed"),
        settleReason = Core.settleReason,
        settleSamples = Core.settleSamples,
        intervalSeconds = Core.DesiredInterval(),
        heartbeatSeconds = Core.HEARTBEAT_SECONDS,
        converged = Latency.IsConverged(Core.latency),
        cachedLatency = type(cfg.latencyCache) == "table" and cfg.latencyCache.value or nil,
        cachedLatencyAt = type(cfg.latencyCache) == "table" and cfg.latencyCache.at or nil,
        -- Is the connection good enough? Drives the colour of the number on
        -- screen: normal = white, clearly worse than this connection's usual (or
        -- genuinely awful) = red. Rule lives in Latency.Quality.
        latencyNormal = type(cfg.latencyCache) == "table" and cfg.latencyCache.value or nil,
        latencyHighAt = Latency.HighThreshold(
            type(cfg.latencyCache) == "table" and cfg.latencyCache.value or nil),
        latencyQuality = Latency.Quality(
            type(cfg.latencyCache) == "table" and cfg.latencyCache.value or nil,
            snap.latency or Latency.Value(Core.latency)),
    }
end

-------------------------------------------------------------------------------
--  Timers
-------------------------------------------------------------------------------
Core.ticker = nil

local function NewTimer(seconds, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, callback)
        return true
    end
    return false
end
Core.After = NewTimer

function Core.StartTicker(seconds)
    seconds = seconds or Core.SETTLE_INTERVAL
    -- One ticker with the cadence the current state needs; changing cadence means
    -- replacing it (C_Timer.NewTicker has a fixed interval).
    if Core.ticker and Core.tickerInterval == seconds then return end
    Core.StopTicker()
    if not (C_Timer and C_Timer.NewTicker) then return end
    Core.tickerInterval = seconds
    Core.ticker = C_Timer.NewTicker(seconds, function()
        Core.Refresh("ticker")
    end)
end

function Core.StopTicker()
    if Core.ticker then
        if Core.ticker.Cancel then Core.ticker:Cancel() end
        Core.ticker = nil
    end
    Core.tickerInterval = nil
end

--- The cadence this state needs, or nil when the addon should not wake up at all.
--  Exposed for tests and for /asq status: "how often does this thing run?"
function Core.DesiredInterval()
    local cfg = Core.db
    if not cfg then return nil end
    local owning = cfg.ownership and cfg.ownership.active
    if not (cfg.enabled or owning) then return nil end        -- nothing left to do
    if Core.settling then return Core.SETTLE_INTERVAL end     -- still learning
    if Core.state == Core.STATE.PENDING then return Core.PENDING_INTERVAL end
    if Core.state == Core.STATE.ERROR then
        -- A failed write/restore must keep being retried (the player's value is
        -- still owed), but with backoff: hammering a read-only CVar every 15 s
        -- forever is exactly the pointless polling this policy removes.
        if (Core.failures or 0) <= Core.RETRY_ATTEMPTS then return Core.RETRY_INTERVAL end
        return Core.HEARTBEAT_SECONDS
    end
    -- Settled: a slow drift check only.
    return Core.HEARTBEAT_SECONDS
end

--- Keeps the refresh timer in step with the state: learning, owing the player a
--- value, or settled. Without this, "leave no trace" would stall until the next
--- zone change; with it, a settled addon wakes up 20x less often than it used to.
function Core.SyncTicker()
    local wanted = Core.DesiredInterval()
    if wanted == nil then
        Core.StopTicker()
        return
    end
    Core.StartTicker(wanted)
end

--- Starts a learning phase. Called on the events that can change the answer:
--- login/zoning, entering an instance or raid, and spec changes.
function Core.BeginSettle(reason)
    Core.settling = true
    Core.settleReason = reason
    Core.settleSamples = 0
    -- Require fresh samples: reusing the previous convergence would end the
    -- learning phase after a single reading, defeating the point of re-measuring.
    Latency.Restart(Core.latency)
end

--- Ends the learning phase and remembers what was learned, so the next session
--- can apply the right value before GetNetStats() reports anything.
function Core.RememberLatency()
    local cfg = Core.db
    if not cfg then return end
    local snapshot = Latency.Snapshot(Core.latency)
    if snapshot.value <= 0 then return end
    local previous = cfg.latencyCache
    if type(previous) == "table" and previous.value == snapshot.value
        and previous.jitter == snapshot.jitter then
        return
    end
    snapshot.at = Now()
    cfg.latencyCache = snapshot
end

--- Adopts the remembered latency (if any) so the first decision is already right.
function Core.SeedLatency()
    local cache = Core.GetConfig().latencyCache
    if type(cache) ~= "table" then return false end
    return Latency.Seed(Core.latency, cache.value, cache.jitter)
end

--- Re-checks a few times after login, because GetNetStats() reports 0 until
--- the client has talked to the world server.
function Core.ScheduleWarmup()
    local index = 0
    local function step()
        index = index + 1
        Core.Refresh("warmup")
        local snap = Core.lastSnapshot
        local unknown = (not snap) or (snap.world == 0 and snap.home == 0)
        if unknown and index < #Core.WARMUP_DELAYS then
            NewTimer(Core.WARMUP_DELAYS[index + 1] - Core.WARMUP_DELAYS[index], step)
        end
    end
    if #Core.WARMUP_DELAYS > 0 then
        NewTimer(Core.WARMUP_DELAYS[1], step)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
Core.inWorld = false
Core.lastReason = nil

local eventFrame

local HANDLERS = {
    ADDON_LOADED = function(name)
        if name ~= Core.NAME then return end
        Core.GetConfig()
        Core.initialized = true
    end,
    PLAYER_LOGIN = function()
        if not Core.initialized then Core.GetConfig() end
        -- Covers the case where a previous session could not give the value
        -- back: ownership is still recorded, so the timer must keep running.
        Core.SyncTicker()
    end,
    PLAYER_ENTERING_WORLD = function()
        if not Core.initialized then Core.GetConfig() end
        Core.inWorld = true
        -- A new session, a new zone or an instance/raid entry is a new connection
        -- context: drop the old samples, adopt the remembered latency so the very
        -- first decision is already sensible, and learn again from there.
        Latency.Reset(Core.latency)
        Core.SeedLatency()
        Core.BeginSettle("enter-world")
        Core.Refresh("enter-world")
        if Core.GetConfig().enabled then
            Core.ScheduleWarmup()
        end
        Core.SyncTicker()
    end,
    PLAYER_SPECIALIZATION_CHANGED = function(unit)
        -- Fires for party/raid members too; only the player matters here.
        if unit ~= nil and unit ~= "player" then return end
        -- The base value changed, the connection did not: no re-learning needed.
        Core.Refresh("spec")
    end,
    ZONE_CHANGED_NEW_AREA = function()
        -- Walking into a dungeon/raid fires this (plus PLAYER_ENTERING_WORLD).
        Core.BeginSettle("zone")
        Core.Refresh("zone")
    end,
    ZONE_CHANGED = function() Core.Refresh("zone-changed") end,
    PLAYER_REGEN_ENABLED = function()
        -- Re-decide from the live state instead of replaying a stale target.
        Core.Refresh("combat-end")
    end,
    CVAR_UPDATE = function(name)
        if name ~= nil and name ~= CVar.NAME then return end
        -- Debounced: an external change is picked up on the next refresh.
        NewTimer(0.5, function() Core.Refresh("cvar-update") end)
    end,
    PLAYER_LOGOUT = function()
        -- Leave no trace: the CVar is written back to the player's own value
        -- before the client persists its settings. If this write fails the
        -- persisted ownership record lets the next session restore it.
        Core.StopTicker()
        Core.RestoreOwnership("logout")
    end,
}

local function OnEvent(_, event, arg1)
    local handler = HANDLERS[event]
    if handler then
        local ok, err = pcall(handler, arg1)
        if not ok then
            Core.state = Core.STATE.ERROR
            Core.stateReason = "handler-error"
            if type(print) == "function" then
                print("AutoSpellQueue: error in " .. tostring(event) .. ": " .. tostring(err))
            end
        end
    end
end

--- Creates the event frame. Safe to call more than once.
function Core.Init()
    if eventFrame or not CreateFrame then return end
    eventFrame = CreateFrame("Frame")
    for event in pairs(HANDLERS) do
        -- One bad event name must not stop the others from being registered,
        -- and must not abort the rest of this file.
        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok and type(print) == "function" then
            print("AutoSpellQueue: cannot register event " .. tostring(event) .. ": " .. tostring(err))
        end
    end
    eventFrame:SetScript("OnEvent", OnEvent)
    Core.eventFrame = eventFrame
end

Core.Init()
