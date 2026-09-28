-------------------------------------------------------------------------------
--  AutoSpellQueue_Formula.lua
--
--  Pure calculation module.
--
--  This file must stay free of WoW API calls: no frames, no events, no CVar
--  access, no C_* namespaces. Every input comes in as an argument so the whole
--  decision of "what value should SpellQueueWindow have" can be unit tested
--  outside the game client (see tests/spec_formula.lua).
--  The runtime (AutoSpellQueue.lua) is responsible for reading the game state
--  and passing it in.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Formula = {}
ns.Formula = Formula

--  Enum.UIMapFlag.IsCityMap, documented since 11.0.0.
Formula.CITY_MAP_FLAG = 0x100000

Formula.ROLE_MELEE = "melee"
Formula.ROLE_RANGED = "ranged"

-------------------------------------------------------------------------------
--  Spec classification
-------------------------------------------------------------------------------
local MELEE_SPECS = {
    -- Death Knight
    [250] = true, -- Blood
    [251] = true, -- Frost
    [252] = true, -- Unholy
    -- Demon Hunter
    [577] = true, -- Havoc
    [581] = true, -- Vengeance
    [1480] = true, -- Devourer
    -- Druid
    [103] = true, -- Feral
    [104] = true, -- Guardian
    -- Hunter
    [255] = true, -- Survival
    -- Monk
    [268] = true, -- Brewmaster
    [269] = true, -- Windwalker
    [270] = true, -- Mistweaver (melee healer)
    -- Paladin
    [66] = true, -- Protection
    [70] = true, -- Retribution
    -- Rogue
    [259] = true, -- Assassination
    [260] = true, -- Outlaw
    [261] = true, -- Subtlety
    -- Shaman
    [263] = true, -- Enhancement
    -- Warrior
    [71] = true, -- Arms
    [72] = true, -- Fury
    [73] = true, -- Protection
}

local RANGED_SPECS = {
    -- Druid
    [102] = true, -- Balance
    [105] = true, -- Restoration
    -- Evoker
    [1467] = true, -- Devastation
    [1468] = true, -- Preservation
    [1473] = true, -- Augmentation
    -- Hunter
    [253] = true, -- Beast Mastery
    [254] = true, -- Marksmanship
    -- Mage
    [62] = true, -- Arcane
    [63] = true, -- Fire
    [64] = true, -- Frost
    -- Paladin
    [65] = true, -- Holy
    -- Priest
    [256] = true, -- Discipline
    [257] = true, -- Holy
    [258] = true, -- Shadow
    -- Shaman
    [262] = true, -- Elemental
    [264] = true, -- Restoration
    -- Warlock
    [265] = true, -- Affliction
    [266] = true, -- Demonology
    [267] = true, -- Destruction
}

local MELEE_CLASSES = {
    DEATHKNIGHT = true,
    DEMONHUNTER = true,
    MONK = true,
    ROGUE = true,
    WARRIOR = true,
}

-------------------------------------------------------------------------------
--  Base values (ms).
--
--  These are tuning defaults, not measurements. They exist so the addon works
--  out of the box; every one of them can be overridden in the options panel by
--  switching "Base value mode" to manual. When a new spec ships, it falls back
--  to the class value and then to FALLBACK - never to nil.
-------------------------------------------------------------------------------
local CLASS_BASE = {
    DEATHKNIGHT = { melee = 150 },
    DEMONHUNTER = { melee = 145 },
    DRUID       = { melee = 145, ranged = 225 },
    EVOKER      = { ranged = 230 },
    HUNTER      = { melee = 160, ranged = 200 },
    MAGE        = { ranged = 240 },
    MONK        = { melee = 140 },
    PALADIN     = { melee = 150, ranged = 230 },
    PRIEST      = { ranged = 225 },
    ROGUE       = { melee = 140 },
    SHAMAN      = { melee = 150, ranged = 220 },
    WARLOCK     = { ranged = 240 },
    WARRIOR     = { melee = 150 },
}

local SPEC_BASE = {
    -- Death Knight (tank slightly higher so defensive cooldowns queue cleanly)
    [250] = 160, [251] = 150, [252] = 150,
    -- Demon Hunter
    [577] = 145, [581] = 160, [1480] = 145,
    -- Druid
    [102] = 230, [103] = 145, [104] = 150, [105] = 220,
    -- Evoker
    [1467] = 230, [1468] = 220, [1473] = 235,
    -- Hunter (BM instant -> low, MM casted -> higher, SV melee)
    [253] = 190, [254] = 210, [255] = 160,
    -- Mage
    [62] = 235, [63] = 245, [64] = 240,
    -- Monk
    [268] = 150, [269] = 140, [270] = 180,
    -- Paladin
    [65] = 230, [66] = 150, [70] = 150,
    -- Priest
    [256] = 220, [257] = 220, [258] = 225,
    -- Rogue (energy/combo -> low, avoid wrong finishers)
    [259] = 140, [260] = 145, [261] = 140,
    -- Shaman
    [262] = 220, [263] = 150, [264] = 220,
    -- Warlock
    [265] = 240, [266] = 240, [267] = 245,
    -- Warrior (protection slightly higher)
    [71] = 150, [72] = 150, [73] = 160,
}

local FALLBACK = { melee = 150, ranged = 220 }

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------

--- Clamps v into [lo, hi]. Swapped bounds are tolerated, NaN never escapes.
function Formula.Clamp(v, lo, hi)
    local nv, nlo, nhi = tonumber(v), tonumber(lo), tonumber(hi)
    if nlo == nil or nlo ~= nlo then nlo = 0 end
    if nhi == nil or nhi ~= nhi then nhi = nlo end
    if nlo > nhi then nlo, nhi = nhi, nlo end
    if nv == nil or nv ~= nv then return nlo end
    if nv < nlo then return nlo end
    if nv > nhi then return nhi end
    return nv
end

--- Rounds to the nearest integer millisecond. Never raises on NaN/inf.
function Formula.Round(v)
    local n = tonumber(v)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then n = 0 end
    return math.floor(n + 0.5)
end

local function SafeNumber(v)
    local n = tonumber(v)
    if n == nil then return 0 end
    -- NaN and +/-inf are not usable as a millisecond value.
    if n ~= n or n == math.huge or n == -math.huge then return 0 end
    return n
end
Formula.SafeNumber = SafeNumber

-------------------------------------------------------------------------------
--  API
-------------------------------------------------------------------------------

--- Returns "melee" or "ranged" for a spec, falling back to the class.
function Formula.Classify(specID, classFile)
    if MELEE_SPECS[specID] then return Formula.ROLE_MELEE end
    if RANGED_SPECS[specID] then return Formula.ROLE_RANGED end
    -- Unknown spec (low level, brand new spec, missing data): class fallback.
    if classFile and MELEE_CLASSES[classFile] then return Formula.ROLE_MELEE end
    return Formula.ROLE_RANGED
end

--- True when the spec id is known to the tables (used for diagnostics/UI).
function Formula.IsKnownSpec(specID)
    return (MELEE_SPECS[specID] or RANGED_SPECS[specID]) ~= nil
end

--- Base value (ms) before any latency adaptation.
function Formula.GetBase(cfg, specID, classFile)
    cfg = cfg or {}
    if cfg.baseMode == "manual" then
        local manual = SafeNumber(cfg.manualBase)
        if manual > 0 then return manual end
        return FALLBACK.ranged
    end
    if specID and SPEC_BASE[specID] then
        return SPEC_BASE[specID]
    end
    local role = Formula.Classify(specID, classFile)
    local classEntry = classFile and CLASS_BASE[classFile]
    if classEntry and classEntry[role] then
        return classEntry[role]
    end
    return FALLBACK[role]
end

--- Maps the raw game state onto a gameplay context.
--  isInInstance: boolean from IsInInstance()
--  mapFlags:     number|nil, UIMapFlag bitfield of the innermost map (or of a
--                parent map when the runtime walked up the hierarchy)
--  Returns "instance" | "city" | "world".
function Formula.ClassifyContext(isInInstance, mapFlags)
    if isInInstance then return "instance" end
    if Formula.HasFlag(mapFlags, Formula.CITY_MAP_FLAG) then return "city" end
    return "world"
end

--- Bit test that does not require the client's bit library.
--  Exact for the flag magnitudes used by UIMapFlag (far below 2^53).
function Formula.HasFlag(value, flag)
    local v, f = tonumber(value), tonumber(flag)
    if not v or not f or f <= 0 or v <= 0 then return false end
    return (math.floor(math.floor(v) / f) % 2) == 1
end

--- Picks one latency number according to the configured source.
--  home/world come from GetNetStats(); either may be 0 when unknown.
function Formula.PickLatency(source, home, world)
    home = SafeNumber(home)
    world = SafeNumber(world)
    if source == "home" then
        return home
    elseif source == "avg" then
        return (home + world) / 2
    elseif source == "max" then
        return math.max(home, world)
    end
    -- "world" (default): the combat path is the world server.
    if world > 0 then return world end
    if home > 0 then return home end
    return 0
end

--- Final SpellQueueWindow target.
--  Returns: target, role, base, latency
function Formula.ComputeTarget(cfg, specID, classFile, home, world, context)
    cfg = cfg or {}
    local role = Formula.Classify(specID, classFile)
    local base = Formula.GetBase(cfg, specID, classFile)
    local latency = Formula.PickLatency(cfg.latencySource, home, world)

    local target
    if context == "city" then
        -- Safe area: no combat pacing pressure, keep the clean base value.
        target = base
    elseif cfg.adaptive ~= false then
        target = math.max(base, latency + SafeNumber(cfg.margin))
    else
        target = base
    end

    target = Formula.Clamp(Formula.Round(target),
        SafeNumber(cfg.minWindow), SafeNumber(cfg.maxWindow))
    return target, role, base, latency
end

--- Builds the human readable formula parts for the UI/diagnostics.
--  Returns: kind ("city"|"adaptive"|"base"), base, latency, margin
function Formula.Describe(cfg, specID, classFile, home, world, context)
    cfg = cfg or {}
    local base = Formula.GetBase(cfg, specID, classFile)
    local latency = Formula.PickLatency(cfg.latencySource, home, world)
    if context == "city" then
        return "city", base, latency, SafeNumber(cfg.margin)
    elseif cfg.adaptive ~= false then
        return "adaptive", base, latency, SafeNumber(cfg.margin)
    end
    return "base", base, latency, SafeNumber(cfg.margin)
end
