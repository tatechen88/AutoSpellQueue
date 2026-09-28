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

T.test("Latency: 收敛判定（够样本 + 平滑值不再移动）", function()
    local tracker = Latency.New()
    T.falsy(Latency.IsConverged(tracker), "没有样本不能算收敛")

    Latency.Push(tracker, 100, 0)
    Latency.Push(tracker, 100, 0)
    T.falsy(Latency.IsConverged(tracker), "样本不足不能算收敛")

    Latency.Push(tracker, 100, 0)
    T.truthy(Latency.IsConverged(tracker), "足够样本且值没动 → 收敛")

    -- 值又开始移动 → 立刻取消收敛
    Latency.Push(tracker, 400, 0)
    T.falsy(Latency.IsConverged(tracker), "读数大跳后必须重新学习")
end)

T.test("Latency: Seed 采用记住的值，但不污染样本窗口", function()
    local tracker = Latency.New()
    T.truthy(Latency.Seed(tracker, 300, 12))
    T.eq(Latency.Value(tracker), 300, "立刻就有可用的值")
    T.eq(Latency.Count(tracker), 0, "记忆值不算样本")
    T.eq(Latency.Jitter(tracker), 12, "同时记住抖动，余量一开始就合理")

    -- 拿到真实读数后，抖动改用实测
    Latency.Push(tracker, 100, 0)
    Latency.Push(tracker, 100, 0)
    T.eq(Latency.Jitter(tracker), 0, "有实测样本后不再用记忆的抖动")
    T.falsy(Latency.IsConverged(tracker), "刚播种还不算收敛（样本不足）")

    T.falsy(Latency.Seed(tracker, 0, 0), "0 不是有效的记忆值")
    Latency.Reset(tracker)
    T.eq(Latency.Value(tracker), 0, "Reset 清掉记忆值")
    T.eq(Latency.Jitter(tracker), 0)
end)

T.test("Latency: Snapshot 给出可持久化的值", function()
    local tracker = Latency.New()
    for _ = 1, 5 do Latency.Push(tracker, 120, 0) end
    local snapshot = Latency.Snapshot(tracker)
    T.eq(snapshot.value, 120)
    T.eq(snapshot.jitter, 0)
    T.eq(snapshot.samples, 5)
end)

T.test("Latency: 记忆值与实测差太远时立刻改用实测（不许慢慢滑几分钟）", function()
    local tracker = Latency.New()
    Latency.Seed(tracker, 300, 10) -- 上次会话学到 300
    Latency.Push(tracker, 100, 0)  -- 这次实际只有 100
    T.eq(Latency.Value(tracker), 100,
        "第一笔实测与记忆值差超过死区时必须直接采用实测值")

    Latency.Push(tracker, 100, 0)
    Latency.Push(tracker, 100, 0)
    T.truthy(Latency.IsConverged(tracker), "纠正后应很快收敛")

    -- 接近的读数则保持平滑（记忆值有用时不要跳）
    local smooth = Latency.New()
    Latency.Seed(smooth, 100, 0)
    Latency.Push(smooth, 110, 0) -- 差 10ms，在死区之内
    local value = Latency.Value(smooth)
    T.truthy(value > 100 and value < 110, "小差异应平滑过渡（实得 " .. value .. "）")
end)

T.test("Latency: Restart 保留估计值，但要求重新采样", function()
    local tracker = Latency.New()
    for _ = 1, 5 do Latency.Push(tracker, 120, 0) end
    T.truthy(Latency.IsConverged(tracker))

    Latency.Restart(tracker)
    T.eq(Latency.Value(tracker), 120, "重启学习期不得丢掉已有估计（否则数值会跳）")
    T.falsy(Latency.IsConverged(tracker), "重启后必须重新攒样本")
    T.eq(Latency.Count(tracker), 0)

    for _ = 1, 3 do Latency.Push(tracker, 120, 0) end
    T.truthy(Latency.IsConverged(tracker), "重新采样稳定后再次收敛")
end)

T.test("Latency: 延迟是否偏高（决定数字变红的判据）", function()
    -- 判据 = clamp(本机平时 + 60, 120, 250)：相对自己 + 有下限 + 有上限
    T.eq(Latency.HighThreshold(nil), Latency.HIGH_FLOOR, "还没学到基准时用下限")
    T.eq(Latency.HighThreshold(0), Latency.HIGH_FLOOR)
    T.eq(Latency.HighThreshold(30), 120, "基准 30 → 90 抬到下限 120")
    T.eq(Latency.HighThreshold(100), 160, "基准 100 → 160")
    T.eq(Latency.HighThreshold(200), 250, "基准 200 → 260 被上限压回 250")
    T.eq(Latency.HighThreshold(400), 250, "极慢的连接也用同一上限，不会永远红")

    -- 质量判定
    T.eq(Latency.Quality(30, 40), "good", "比平时低 → 正常")
    T.eq(Latency.Quality(30, 119), "good", "刚好在阈值下方 → 正常")
    T.eq(Latency.Quality(30, 120), "high", "达到阈值 → 偏高（边界含等于）")
    T.eq(Latency.Quality(30, 400), "high")
    T.eq(Latency.Quality(200, 210), "good", "平时就 200 的人，210 不该报警")
    T.eq(Latency.Quality(200, 300), "high", "但 300 要报")
    T.eq(Latency.Quality(nil, 130), "high", "没有基准时按下限 120 判")
    T.eq(Latency.Quality(30, 0), "unknown", "客户端还没报延迟 → 不猜")
    T.eq(Latency.Quality(30, nil), "unknown")
    T.eq(Latency.Quality(30, 0 / 0), "unknown", "NaN → 不猜")
end)

T.test("Latency: Describe 一次给出三个有限值", function()
    local tracker = Latency.New()
    Latency.Push(tracker, 80, 0)
    local value, margin, hysteresis = Latency.Describe(tracker)
    T.eq(value, 80)
    T.truthy(margin == margin and hysteresis == hysteresis, "不得是 NaN")
    T.truthy(type(margin) == "number" and type(hysteresis) == "number")
end)
