-- ============================================================
-- AUTO COLLECT + SELL FISH — 1 Tombol
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = game:GetService("Players").LocalPlayer

local getPlayerDataById = require(ReplicatedStorage.TS.state["player-data"]).getPlayerDataById

local remo = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container
local collectRemote = remo:WaitForChild("bait.collectAllFish")
local sellRemote    = remo:WaitForChild("sellFish.sellAllFish")

-- ====== STATE ======
local running = false
local cycleInterval = 0.5
local mainThread, currentUIDs = nil, {}
local collectSent, sellSent, failed, cycles = 0, 0, 0, 0
local isMin = false

-- ====== HELPERS ======
local function baitName(b)
    if type(b) == "string" then return b end
    if type(b) ~= "table" then return "?" end
    for _, k in ipairs({"baitType","type","baitId","id","name"}) do
        if type(b[k]) == "string" then return b[k] end
    end
    return "unknown"
end

local function scanPond()
    local out = {}
    local ok, data = pcall(getPlayerDataById, tostring(LocalPlayer.UserId))
    if not ok or not data or not data.ponds then return out end
    local pond = data.ponds[data.currentPond]
    if not pond or not pond.baits then return out end
    for uid, b in pairs(pond.baits) do
        table.insert(out, {uid = tostring(uid), baitType = baitName(b)})
    end
    table.sort(out, function(a,b) return a.uid < b.uid end)
    return out
end

-- ====== GUI ======
local C = {
    bg=Color3.fromRGB(22,24,30), panel=Color3.fromRGB(32,35,42),
    alt=Color3.fromRGB(44,48,58), accent=Color3.fromRGB(88,166,255),
    text=Color3.fromRGB(230,232,238), dim=Color3.fromRGB(150,155,165),
    ok=Color3.fromRGB(80,200,120), bad=Color3.fromRGB(240,90,90),
    min=Color3.fromRGB(240,180,80),
}

local FULL, MIN = UDim2.new(0,300,0,300), UDim2.new(0,160,0,28)

local sg = Instance.new("ScreenGui")
sg.Name, sg.ResetOnSpawn, sg.Parent = "AutoCS", false, game:GetService("CoreGui")

local main = Instance.new("Frame", sg)
main.Size, main.Position = FULL, UDim2.new(0.5,-150,0.5,-150)
main.BackgroundColor3, main.BorderSizePixel = C.bg, 0
main.Active, main.Draggable, main.ClipsDescendants = true, true, true
Instance.new("UICorner", main).CornerRadius = UDim.new(0,8)
local stroke = Instance.new("UIStroke", main)
stroke.Color, stroke.Thickness, stroke.Transparency = C.accent, 1, 0.5

-- Title bar
local bar = Instance.new("Frame", main)
bar.Size, bar.BackgroundColor3, bar.BorderSizePixel = UDim2.new(1,0,0,28), C.panel, 0
Instance.new("UICorner", bar).CornerRadius = UDim.new(0,8)

local title = Instance.new("TextLabel", bar)
title.Size, title.Position = UDim2.new(1,-80,1,0), UDim2.new(0,10,0,0)
title.BackgroundTransparency = 1
title.Text, title.TextColor3 = "⚡ Auto Collect + Sell", C.text
title.Font, title.TextSize = Enum.Font.GothamBold, 12
title.TextXAlignment = Enum.TextXAlignment.Left

local function makeBtn(parent, size, pos, color, text, tsize)
    local b = Instance.new("TextButton", parent)
    b.Size, b.Position, b.BackgroundColor3 = size, pos, color
    b.Text, b.TextColor3 = text, C.text
    b.Font, b.TextSize = Enum.Font.GothamBold, tsize or 12
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    return b
end

local minBtn   = makeBtn(bar, UDim2.new(0,22,0,22), UDim2.new(1,-52,0,3), C.min, "—", 14)
local closeBtn = makeBtn(bar, UDim2.new(0,22,0,22), UDim2.new(1,-26,0,3), C.bad, "✕", 12)

-- Body
local body = Instance.new("Frame", main)
body.Size, body.Position, body.BackgroundTransparency = UDim2.new(1,0,1,-28), UDim2.new(0,0,0,28), 1

-- ====== TOMBOL UTAMA (1 tombol) ======
local mainBtn = makeBtn(body, UDim2.new(1,-16,0,44), UDim2.new(0,8,0,8), C.bad, "▶ Start Auto", 15)

-- Info bar
local info = Instance.new("TextLabel", body)
info.Size, info.Position, info.BackgroundColor3 = UDim2.new(1,-16,0,32), UDim2.new(0,8,0,60), C.alt
info.BorderSizePixel = 0
info.Text, info.TextColor3 = "Bait: 0 | C:0 | S:0 | Cy:0 | F:0", C.text
info.Font, info.TextSize = Enum.Font.Gotham, 11
Instance.new("UICorner", info).CornerRadius = UDim.new(0,5)

-- Scroll list
local scroll = Instance.new("ScrollingFrame", body)
scroll.Size, scroll.Position = UDim2.new(1,-16,1,-124), UDim2.new(0,8,0,100)
scroll.BackgroundColor3, scroll.BorderSizePixel = C.panel, 0
scroll.ScrollBarThickness, scroll.ScrollBarImageColor3 = 4, C.accent
scroll.CanvasSize, scroll.AutomaticCanvasSize = UDim2.new(0,0,0,0), Enum.AutomaticSize.Y
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0,5)
local ll = Instance.new("UIListLayout", scroll)
ll.SortOrder, ll.Padding = Enum.SortOrder.LayoutOrder, UDim.new(0,2)
local lp = Instance.new("UIPadding", scroll)
lp.PaddingTop, lp.PaddingBottom = UDim.new(0,4), UDim.new(0,4)
lp.PaddingLeft, lp.PaddingRight = UDim.new(0,4), UDim.new(0,4)

local status = Instance.new("TextLabel", body)
status.Size, status.Position = UDim2.new(1,-16,0,16), UDim2.new(0,8,1,-20)
status.BackgroundTransparency = 1
status.Text, status.TextColor3 = "Ready.", C.dim
status.Font, status.TextSize = Enum.Font.Gotham, 10
status.TextXAlignment, status.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd

-- ====== MINIMIZE ======
local savedPos = main.Position
local function setMin(state)
    isMin = state
    if state then
        savedPos = main.Position
        body.Visible, closeBtn.Visible = false, false
        minBtn.Text, minBtn.Position = "+", UDim2.new(1,-26,0,3)
        main.Size, title.Text = MIN, "⚡ ACS"
    else
        body.Visible, closeBtn.Visible = true, true
        minBtn.Text, minBtn.Position = "—", UDim2.new(1,-52,0,3)
        main.Size, main.Position = FULL, savedPos
        title.Text = "⚡ Auto Collect + Sell"
    end
end
minBtn.MouseButton1Click:Connect(function() setMin(not isMin) end)
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 and isMin then setMin(false) end
end)

-- ====== RENDER ======
local function updateInfo()
    info.Text = string.format("Bait: %d | C:%d | S:%d | Cy:%d | F:%d",
        #currentUIDs, collectSent, sellSent, cycles, failed)
end

local function render()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, bait in ipairs(currentUIDs) do
        local r = Instance.new("Frame", scroll)
        r.Size, r.BorderSizePixel = UDim2.new(1,0,0,22), 0
        r.BackgroundColor3 = i % 2 == 0 and C.alt or C.panel
        r.LayoutOrder = i
        Instance.new("UICorner", r).CornerRadius = UDim.new(0,3)

        local t = Instance.new("TextLabel", r)
        t.Size, t.Position, t.BackgroundTransparency = UDim2.new(0,80,1,0), UDim2.new(0,6,0,0), 1
        t.Text, t.TextColor3 = tostring(bait.baitType), C.text
        t.Font, t.TextSize = Enum.Font.GothamMedium, 10
        t.TextXAlignment, t.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd

        local u = Instance.new("TextLabel", r)
        u.Size, u.Position, u.BackgroundTransparency = UDim2.new(1,-90,1,0), UDim2.new(0,90,0,0), 1
        u.Text, u.TextColor3 = bait.uid, C.dim
        u.Font, u.TextSize = Enum.Font.Code, 10
        u.TextXAlignment, u.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
    end
    updateInfo()
end

-- ====== CORE ======
local function collect(uid)
    local ok = pcall(collectRemote.FireServer, collectRemote, uid)
    if ok then collectSent = collectSent + 1 else failed = failed + 1 end
end

local function sell()
    local ok = pcall(sellRemote.FireServer, sellRemote)
    if ok then sellSent = sellSent + 1 else failed = failed + 1 end
end

local function runCycle()
    -- scan ulang tiap siklus supaya UID fresh
    currentUIDs = scanPond()
    render()

    if #currentUIDs == 0 then
        status.Text = "⏳ Pond kosong, tunggu..."
        return
    end

    -- 1) Collect semua UID (instant)
    for _, b in ipairs(currentUIDs) do
        if not running then return end
        collect(b.uid)
    end
    -- 2) Sell all (instant)
    sell()

    cycles = cycles + 1
    updateInfo()
    status.Text = string.format("⚡ Cycle #%d: %d collect + sell", cycles, #currentUIDs)
end

local function startLoop()
    if mainThread then return end
    mainThread = task.spawn(function()
        while running and sg.Parent do
            runCycle()
            task.wait(cycleInterval)
        end
        mainThread = nil
    end)
end

local function stopLoop()
    running = false
    if mainThread then pcall(task.cancel, mainThread); mainThread = nil end
end

-- ====== SATU TOMBOL ======
mainBtn.MouseButton1Click:Connect(function()
    running = not running
    if running then
        mainBtn.BackgroundColor3 = C.ok
        mainBtn.Text = "⏸ Stop Auto"
        status.Text = "Auto collect + sell AKTIF."
        startLoop()
    else
        mainBtn.BackgroundColor3 = C.bad
        mainBtn.Text = "▶ Start Auto"
        status.Text = "Auto nonaktif."
        stopLoop()
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    stopLoop()
    sg:Destroy()
end)

-- ====== INIT ======
currentUIDs = scanPond()
render()
status.Text = "Ready. Snapshot: " .. #currentUIDs .. " bait."
