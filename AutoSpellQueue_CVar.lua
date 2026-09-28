-------------------------------------------------------------------------------
--  AutoSpellQueue_CVar.lua
--
--  The only place that touches SpellQueueWindow.
--
--  Why this file exists as its own module:
--    * The old implementation treated a successful pcall() as a successful
--      CVar write. pcall() only says "no Lua error was raised"; the API itself
--      returns a boolean (and returns nil for some protected cases). Trusting
--      pcall() produced silent failures and a UI that claimed the value had
--      been applied.
--    * Everything here is expressed against an injectable environment so the
--      logic can be tested outside the game client (tests/spec_cvar.lua).
--
--  Contract of the environment (env) table:
--    env.getCVarInfo(name)  -> value, defaultValue, isStoredAccount,
--                              isStoredCharacter, isLocked, isSecure, isReadOnly
--    env.getCVar(name)      -> string | nil
--    env.setCVar(name, str) -> success(boolean|nil), ...
--    env.inCombat()         -> boolean
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local CVar = {}
ns.CVar = CVar

CVar.NAME = "SpellQueueWindow"

-- The client documents the usable range as 0..400 ms.
CVar.MIN = 0
CVar.MAX = 400

-- Failure reasons returned by Write(). Keep them as stable keys: the UI and
-- the chat diagnostics localise them.
CVar.ERR_INVALID_VALUE = "invalid-value"
CVar.ERR_READONLY = "readonly"
CVar.ERR_COMBAT = "combat"
CVar.ERR_NO_API = "no-api"
CVar.ERR_REJECTED = "rejected"
CVar.ERR_VERIFY = "verify-failed"
CVar.ERR_UNAVAILABLE = "unavailable"

-------------------------------------------------------------------------------
--  Real environment (game client)
-------------------------------------------------------------------------------
local function BuildRealEnv()
    return {
        inCombat = function()
            return (InCombatLockdown and InCombatLockdown()) and true or false
        end,
        getCVarInfo = function(name)
            if C_CVar and C_CVar.GetCVarInfo then
                return C_CVar.GetCVarInfo(name)
            end
            return nil
        end,
        getCVar = function(name)
            if C_CVar and C_CVar.GetCVar then
                return C_CVar.GetCVar(name)
            end
            if GetCVar then
                return GetCVar(name)
            end
            return nil
        end,
        setCVar = function(name, value)
            if C_CVar and C_CVar.SetCVar then
                return C_CVar.SetCVar(name, value)
            end
            if SetCVar then
                return SetCVar(name, value)
            end
            return false, "no-api"
        end,
    }
end

local realEnv

--- Returns the environment in use. Tests replace it through SetEnv().
function CVar.GetEnv()
    if not realEnv then realEnv = BuildRealEnv() end
    return realEnv
end

--- Test seam: swap in a fake environment. Not used by the addon itself.
function CVar.SetEnv(env)
    realEnv = env
end

-------------------------------------------------------------------------------
--  Reads
-------------------------------------------------------------------------------

--- Raw metadata for the CVar.
--  Returns a table (never nil) so callers do not have to nil-check twice:
--    { known = boolean, value = number|nil, defaultValue = number|nil,
--      isReadOnly = boolean, isSecure = boolean, isLocked = boolean,
--      isStoredAccount = boolean, isStoredCharacter = boolean }
function CVar:Info()
    local env = self:GetEnv()
    local info = {
        known = false,
        value = nil,
        defaultValue = nil,
        isReadOnly = false,
        isSecure = false,
        isLocked = false,
        isStoredAccount = false,
        isStoredCharacter = false,
    }

    if env.getCVarInfo then
        local ok, value, defaultValue, isStoredAccount, isStoredCharacter,
            isLocked, isSecure, isReadOnly =
            pcall(env.getCVarInfo, self.NAME)
        if ok and value ~= nil then
            info.known = true
            info.value = tonumber(value)
            info.defaultValue = tonumber(defaultValue)
            info.isStoredAccount = isStoredAccount and true or false
            info.isStoredCharacter = isStoredCharacter and true or false
            info.isLocked = isLocked and true or false
            info.isSecure = isSecure and true or false
            info.isReadOnly = isReadOnly and true or false
            return info
        end
    end

    -- Fallback for clients where GetCVarInfo is unavailable.
    local value = self:RawRead()
    if value ~= nil then
        local num = tonumber(value)
        -- Keep the number contract of Info().value even on this path.
        if num ~= nil then
            info.known = true
            info.value = num
        end
    end
    return info
end

--- Reads the raw string value. Returns string|nil.
function CVar:RawRead()
    local env = self:GetEnv()
    if not env.getCVar then return nil end
    local ok, value = pcall(env.getCVar, self.NAME)
    if not ok then return nil end
    if value == nil then return nil end
    -- Some clients return "" for unknown CVars.
    if type(value) == "string" and value == "" then return nil end
    return tostring(value)
end

--- Current numeric value.
--  Returns value(number) | nil, reason(string). A nil value must be surfaced
--  to the user as "unavailable" - never silently replaced by a default, which
--  is what made the old status bar show a believable but wrong 400 ms.
function CVar:Read()
    local info = self:Info()
    if info.value ~= nil then return info.value end

    local raw = self:RawRead()
    if raw == nil then return nil, self.ERR_UNAVAILABLE end
    local num = tonumber(raw)
    if num == nil then return nil, self.ERR_UNAVAILABLE end
    return num
end

--- True when the CVar can be read at all.
function CVar:IsAvailable()
    return self:Read() ~= nil
end

--- True when a write would be attempted at all (does not guarantee success).
function CVar:IsWritable()
    local info = self:Info()
    if not info.known then return false, self.ERR_UNAVAILABLE end
    if info.isReadOnly then return false, self.ERR_READONLY end
    local env = self:GetEnv()
    if env.inCombat and env.inCombat() then return false, self.ERR_COMBAT end
    return true
end

-------------------------------------------------------------------------------
--  Write
-------------------------------------------------------------------------------

local function SameValue(a, b)
    if a == nil or b == nil then return false end
    return math.floor(tonumber(a) + 0.5) == math.floor(tonumber(b) + 0.5)
end
CVar.SameValue = SameValue

--- Writes a value and verifies it actually took effect.
--  Returns: ok(boolean), reason(string|nil), applied(number|nil)
--
--  Success requires BOTH:
--    * the API did not reject the write (returns false/nil => rejected), and
--    * reading the CVar back yields the value we asked for.
--  When the client cannot be read back, a boolean true from the API is
--  accepted; anything less is a failure.
function CVar:Write(value)
    local num = tonumber(value)
    if num == nil or num ~= num or num == math.huge or num == -math.huge then
        return false, self.ERR_INVALID_VALUE, nil
    end
    num = math.max(self.MIN, math.min(self.MAX, math.floor(num + 0.5)))

    local env = self:GetEnv()
    if not env.setCVar then return false, self.ERR_NO_API, nil end

    local info = self:Info()
    if info.isReadOnly then return false, self.ERR_READONLY, nil end
    if env.inCombat and env.inCombat() then return false, self.ERR_COMBAT, nil end

    local text = ("%d"):format(num)
    local called, returned = pcall(env.setCVar, self.NAME, text)
    if not called then
        return false, self.ERR_NO_API, nil
    end

    -- The API documents a boolean return; nil means "unknown", which we treat
    -- as "not proven successful" and verify by reading the value back.
    if returned == false then
        return false, self.ERR_REJECTED, nil
    end

    local readBack = self:RawRead()
    if readBack ~= nil then
        local current = tonumber(readBack)
        if current == nil then return false, self.ERR_VERIFY, nil end
        if not SameValue(current, num) then
            return false, self.ERR_VERIFY, current
        end
        return true, nil, num
    end

    if returned == true then
        -- API said yes and the client cannot be read back on this version.
        return true, nil, num
    end

    return false, self.ERR_VERIFY, nil
end
