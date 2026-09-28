-------------------------------------------------------------------------------
--  spec_latency.lua
--
--  The latency tracker replaced four player settings (Safety Margin, Hysteresis,
--  Latency Source and the adaptive toggle). Those cases are pinned here.
-------------------------------------------------------------------------------
local T, ns, Stub = ...
local Latency = ns.Latency

T.spec("spec_latency")

T.test("Latency: 没有样本时是安全的零值（不得返回 NaN/负数）", function()
    local tracker = Latency.New()
    T.eq(Latency.Value(tracker), 0)
    T.eq(Latency.Jitter(tracker), 0)
    T.truthy(Latency.Margin(tracker) >= Latency.MARGIN_MIN)
    T.truthy(Latency.Hysteresis(tracker) >= Latency.HYSTERESIS_MIN)
    T.falsy(Latency.IsStable(tracker), "没有样本不能算稳定")
end)

T.test("Latency: 未知延迟（0）不进窗口，也不会把均值拉低", function()
    local tracker = Latency.New()
    T.falsy(Latency.Push(tracker, 0, 0), "两个都是 0 时应忽略")
    T.falsy(Latency.Push(tracker, nil, nil))
    T.falsy(Latency.Push(tracker, 0 / 0, 0))
    T.eq(Latency.Count(tracker), 0)
    T.eq(Latency.Value(tracker), 0)

    T.truthy(Latency.Push(tracker, 0, 120), "world 为 0 时回退 home")
    T.eq(Latency.Value(tracker), 120)
end)

T.test("Latency: 上升快、下降慢（不对称平滑，宁可多留余量）", function()
    local tracker = Latency.New()
    Latency.Push(tracker, 100, 0)
    T.eq(Latency.Value(tracker), 100)

    -- 变差：一步就到 150（SMOOTH_UP = 0.5 → 100 + 25 = 125）
    Latency.Push(tracker, 150, 0)
    local afterRise = Latency.Value(tracker)
    T.truthy(afterRise > 100 and afterRise <= 150, "上升应立刻响应（实得 " .. afterRise .. "）")

    -- 变好：要好几步才降下来（SMOOTH_DOWN = 0.15）
    local before = Latency.Value(tracker)
    Latency.Push(tracker, 60, 0)
    local afterFall = Latency.Value(tracker)
    T.truthy(afterFall > 60, "下降必须比上升慢（实得 " .. afterFall .. "）")
    T.truthy(afterFall < before, "但仍然要往下降")
end)

T.test("Latency: 抖动越大，余量与迟滞越大（这就是原来的两个设置项）", function()
    local stable = Latency.New()
    for _ = 1, 10 do Latency.Push(stable, 100, 0) end
    T.eq(Latency.Jitter(stable), 0)
    T.eq(Latency.Margin(stable), Latency.BASE_HEADROOM, "稳定连接只用基础余量")
    T.eq(Latency.Hysteresis(stable), Latency.HYSTERESIS_MIN)
    T.truthy(Latency.IsStable(stable))

    local noisy = Latency.New()
    for index = 1, 10 do
        -- 100 / 140 交替 → 平均绝对偏差 20
        Latency.Push(noisy, index % 2 == 0 and 140 or 100, 0)
    end
    T.near(Latency.Jitter(noisy), 20, 0.01)
    T.truthy(Latency.Margin(noisy) > Latency.BASE_HEADROOM,
        "抖动大必须自动加余量（实得 " .. Latency.Margin(noisy) .. "）")
    T.truthy(Latency.Hysteresis(noisy) > Latency.HYSTERESIS_MIN,
        "抖动大必须自动放宽写入阈值（实得 " .. Latency.Hysteresis(noisy) .. "）")
end)

T.test("Latency: 单个尖刺不会把余量顶到天上（用平均绝对偏差，不是极差）", function()
    local tracker = Latency.New()
    for _ = 1, 19 do Latency.Push(tracker, 100, 0) end
    Latency.Push(tracker, 600, 0) -- 一次 600ms 尖刺

    local jitter = Latency.Jitter(tracker)
    T.truthy(jitter < 50, "一次尖刺不能让抖动失控（实得 " .. jitter .. "）")
    T.truthy(Latency.Margin(tracker) < Latency.MARGIN_MAX, "余量必须在钳制范围内")
end)

T.test("Latency: 余量与迟滞永远在钳制区间内", function()
    local tracker = Latency.New()
    for index = 1, 40 do Latency.Push(tracker, (index % 2 == 0) and 900 or 5, 0) end
    local margin = Latency.Margin(tracker)
    local hysteresis = Latency.Hysteresis(tracker)
    T.truthy(margin >= Latency.MARGIN_MIN and margin <= Latency.MARGIN_MAX,
        "margin 越界: " .. margin)
    T.truthy(hysteresis >= Latency.HYSTERESIS_MIN and hysteresis <= Latency.HYSTERESIS_MAX,
        "hysteresis 越界: " .. hysteresis)
end)

T.test("Latency: 窗口有上限，且 Reset 能清空", function()
    local tracker = Latency.New(5)
    for index = 1, 50 do Latency.Push(tracker, 100 + index, 0) end
    T.eq(#tracker.samples, 5, "只保留最近 5 个样本")
    T.eq(Latency.Count(tracker), 50, "累计计数不受窗口限制")

    Latency.Reset(tracker)
    T.eq(Latency.Count(tracker), 0)
    T.eq(Latency.Value(tracker), 0)
    T.eq(Latency.Jitter(tracker), 0)
end)

T.test("Latency: Describe 一次给出三个有限值", function()
    local tracker = Latency.New()
    Latency.Push(tracker, 80, 0)
    local value, margin, hysteresis = Latency.Describe(tracker)
    T.eq(value, 80)
    T.truthy(margin == margin and hysteresis == hysteresis, "不得是 NaN")
    T.truthy(type(margin) == "number" and type(hysteresis) == "number")
end)
