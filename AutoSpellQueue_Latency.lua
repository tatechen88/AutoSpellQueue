-------------------------------------------------------------------------------
--  AutoSpellQueue_Latency.lua
--
--  Pure latency tracker: the algorithm that used to be four player settings.
--
--  Why this file exists:
--    The addon used to expose Safety Margin, Hysteresis and Latency Source as
--    options. All three are things the addon can measure for itself, so they
--    are computed here instead: the player gets one switch, the client gets a
--    value that follows the connection.
--
--  What it does:
--    * Smooths the world latency with an asymmetric EMA - it reacts quickly
--      when latency gets worse (never under-buffer a spike) and lets go slowly
--      when it improves (no flapping).
--    * Measures jitter from the recent window and turns it into headroom:
--      margin = BASE_HEADROOM + JITTER_FACTOR * jitter, clamped.
--    * Derives the write threshold (hysteresis) from the same jitter, so a
--      noisy connection does not make the addon rewrite the CVar constantly.
--    * Falls back to home latency / zero safely, and never returns NaN.
--
--  No WoW API, no frames, no state outside the tracker table: the runtime feeds
--  samples in and reads numbers out (tests/spec_latency.lua).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Latency = {}
ns.Latency = Latency

-------------------------------------------------------------------------------
--  Tunables. These are the "settings" the player no longer sees: they are
--  documented here, covered by tests, and never exposed in the UI.
-------------------------------------------------------------------------------
Latency.WINDOW = 20            -- samples kept for the jitter estimate
Latency.SMOOTH_UP = 0.5        -- EMA weight when latency rises (react fast)
Latency.SMOOTH_DOWN = 0.15     -- EMA weight when latency falls (let go slowly)

Latency.BASE_HEADROOM = 40     -- ms always added on top of the measured latency
Latency.JITTER_FACTOR = 1.5    -- ms of headroom per ms of measured jitter
Latency.MARGIN_MIN = 30
Latency.MARGIN_MAX = 150

Latency.HYSTERESIS_MIN = 5
Latency.HYSTERESIS_MAX = 25
Latency.HYSTERESIS_PER_JITTER = 1.0

Latency.GOOD_ENOUGH_JITTER = 3 -- below this the connection counts as stable

--  Convergence: how the addon decides it has learned the connection and can
--  stop sampling. Latency does not move much within minutes, so once the
--  smoothed value stops moving there is nothing left to poll for.
Latency.MIN_SAMPLES = 3        -- never call it settled on one or two readings
Latency.STABLE_EPSILON = 3     -- ms the smoothed value may still move and count as settled
Latency.DRIFT_DEADBAND = 25    -- ms of movement that makes a drift check worth re-sampling

local function FiniteNumber(value, fallback)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-------------------------------------------------------------------------------
--  Tracker
-------------------------------------------------------------------------------

--- Creates a tracker. `maxSamples` exists for tests; production uses WINDOW.
function Latency.New(maxSamples)
    return {
        samples = {},
        maxSamples = maxSamples or Latency.WINDOW,
        count = 0,
        smoothed = nil,
        last = nil,
        stableFor = 0,
    }
end

--- Adopts a value remembered from an earlier session.
--  Deliberately does NOT add a sample: the remembered jitter is used for the
--  margin until real readings arrive, and the value can be corrected right away
--  instead of leaving the player with a wrong number until GetNetStats speaks.
function Latency.Seed(tracker, value, jitter)
    local seeded = FiniteNumber(value, 0)
    if seeded <= 0 then return false end
    tracker.smoothed = seeded
    tracker.seedJitter = FiniteNumber(jitter, 0)
    tracker.seeded = true
    return true
end

--- True once enough readings agree that more sampling would not change anything.
function Latency.IsConverged(tracker)
    if tracker.count < Latency.MIN_SAMPLES then return false end
    return (tracker.stableFor or 0) >= 1
end

--- What is worth remembering across sessions (persisted by the runtime).
function Latency.Snapshot(tracker)
    return {
        value = math.floor(Latency.Value(tracker) + 0.5),
        jitter = math.floor(Latency.Jitter(tracker) + 0.5),
        samples = tracker.count,
    }
end

--- Feeds one reading. `world` is the combat-path latency, `home` the fallback.
--  Either may be 0 (unknown) - those samples are ignored so a login-time zero
--  cannot drag the average down.
function Latency.Push(tracker, world, home)
    local value = FiniteNumber(world, 0)
    if value <= 0 then value = FiniteNumber(home, 0) end
    if value <= 0 then return false end

    tracker.count = tracker.count + 1
    tracker.last = value

    -- A remembered value is a guess. If the very first real reading disagrees
    -- with it, trust the reading instead of gliding towards it for minutes
    -- (SMOOTH_DOWN is deliberately slow, which would keep the window wrong).
    if tracker.seeded then
        tracker.seeded = nil
        tracker.seedJitter = nil
        if tracker.smoothed and math.abs(value - tracker.smoothed) > Latency.DRIFT_DEADBAND then
            tracker.smoothed = value
            tracker.stableFor = 0
            local samples = tracker.samples
            samples[#samples + 1] = value
            while #samples > tracker.maxSamples do table.remove(samples, 1) end
            return true
        end
    end

    local before = tracker.smoothed
    if before == nil then
        tracker.smoothed = value
    elseif value > before then
        tracker.smoothed = before + (value - before) * Latency.SMOOTH_UP
    else
        tracker.smoothed = before + (value - before) * Latency.SMOOTH_DOWN
    end

    -- How long the smoothed value has been standing still (used to stop sampling)
    local moved = before == nil and math.huge or (tracker.smoothed - before)
    if moved < 0 then moved = -moved end
    if before ~= nil and moved <= Latency.STABLE_EPSILON then
        tracker.stableFor = (tracker.stableFor or 0) + 1
    else
        tracker.stableFor = 0
    end

    local samples = tracker.samples
    samples[#samples + 1] = value
    while #samples > tracker.maxSamples do
        table.remove(samples, 1)
    end
    return true
end

function Latency.Reset(tracker)
    tracker.samples = {}
    tracker.count = 0
    tracker.smoothed = nil
    tracker.last = nil
    tracker.stableFor = 0
    tracker.seedJitter = nil
    tracker.seeded = nil
end

--- Starts a new learning phase without losing the current estimate.
--  Keeps the smoothed value (so the applied number does not jump while we
--  re-learn) and carries the last measured jitter over as the seed, but requires
--  fresh samples before IsConverged() can be true again. Without this, a zone
--  change re-used the previous convergence and the learning phase ended after a
--  single sample, which defeated the point of re-measuring.
function Latency.Restart(tracker)
    local jitter = Latency.Jitter(tracker)
    tracker.samples = {}
    tracker.count = 0
    tracker.stableFor = 0
    tracker.seedJitter = jitter
    tracker.seeded = tracker.smoothed ~= nil
end

function Latency.Count(tracker)
    return tracker.count
end

--- Smoothed latency in ms (0 when nothing was measured yet).
function Latency.Value(tracker)
    return FiniteNumber(tracker.smoothed, 0)
end

--- Spread of the recent window in ms: mean absolute deviation from the mean.
--  Cheap, stable, and it does not explode on a single outlier the way a
--  min-max range would (one 600 ms spike must not double the safety margin).
function Latency.Jitter(tracker)
    local samples = tracker.samples
    local n = #samples
    -- A remembered value carries a remembered jitter until fresh readings exist.
    if n < 2 then return FiniteNumber(tracker.seedJitter, 0) end

    local sum = 0
    for index = 1, n do sum = sum + samples[index] end
    local mean = sum / n

    local deviation = 0
    for index = 1, n do
        local diff = samples[index] - mean
        if diff < 0 then diff = -diff end
        deviation = deviation + diff
    end
    return deviation / n
end

--- Headroom to add on top of the measured latency: a fixed base plus a term
--- that grows with jitter.
function Latency.Margin(tracker)
    local jitter = Latency.Jitter(tracker)
    local margin = Latency.BASE_HEADROOM + Latency.JITTER_FACTOR * jitter
    return math.floor(Clamp(margin, Latency.MARGIN_MIN, Latency.MARGIN_MAX) + 0.5)
end

--- How far the target must move before it is worth writing the CVar.
--  Stable connection: a few ms (so small improvements still land).
--  Unstable connection: wider, so the addon does not chase every spike.
function Latency.Hysteresis(tracker)
    local jitter = Latency.Jitter(tracker)
    local hysteresis = Latency.HYSTERESIS_MIN + Latency.HYSTERESIS_PER_JITTER * jitter
    return math.floor(Clamp(hysteresis, Latency.HYSTERESIS_MIN, Latency.HYSTERESIS_MAX) + 0.5)
end

--- One call for the runtime: everything the decision needs.
--  Returns value, margin, hysteresis (all finite numbers).
function Latency.Describe(tracker)
    return Latency.Value(tracker), Latency.Margin(tracker), Latency.Hysteresis(tracker)
end

--- True when the connection looks stable (used for the status card wording).
function Latency.IsStable(tracker)
    return Latency.Count(tracker) >= 3 and Latency.Jitter(tracker) <= Latency.GOOD_ENOUGH_JITTER
end
