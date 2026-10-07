-- ============================================================
-- GABUNGAN: Auto Collect + Sell Fish & Auto Place Feeders
-- Satu GUI, fungsi tetap sama
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- BAGIAN 1: AUTO COLLECT + SELL FISH
-- ============================================================
local getPlayerDataById = require(ReplicatedStorage.TS.state["player-data"]).getPlayerDataById

local remo = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container
local collectRemote = remo:WaitForChild("bait.collectAllFish")
local sellRemote    = remo:WaitForChild("sellFish.sellAllFish")

-- ====== STATE (Fish) ======
local fishRunning = false
local cycleInterval = 0.25
local fishThread, currentUIDs = nil, {}
local collectSent, sellSent, failed, cycles = 0, 0, 0, 0

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

-- ============================================================
-- BAGIAN 2: AUTO PLACE FEEDERS
-- ============================================================
local placeRemote = remo:WaitForChild("ponds.placeBuilding")
local SwitchPetLoadout = remo:WaitForChild("pets.switchPetLoadout")

local Position = vector.create(24.862998962402344, -0.012000083923339844, -23)
local PLACE_COUNT = 5
local INTERVAL = 606
local FEEDER_DELAY = 0.05
local SWITCH_DELAY = 0.1

local Feeders = {
    "GodlyAutoFeeder",
    "ExtremeAutoFeeder",
    "SupremeAutoFeeder",
    "AdvancedAutoFeeder",
    "BasicAutoFeeder",
}

local feederRunning = false
local feederThread = nil

-- ============================================================
-- COLOR PALETTE
-- ============================================================
local C = {
    bg=Color3.fromRGB(22,24,30), panel=Color3.fromRGB(32,35,42),
    alt=Color3.fromRGB(44,48,58), accent=Color3.fromRGB(88,166,255),
    text=Color3.fromRGB(230,232,238), dim=Color3.fromRGB(150,155,165),
    ok=Color3.fromRGB(80,200,120), bad=Color3.fromRGB(240,90,90),
    min=Color3.fromRGB(240,180,80),
}

-- ============================================================
-- SATU SCREENGUI
-- ============================================================
local sg = Instance.new("ScreenGui")
sg.Name, sg.ResetOnSpawn, sg.Parent = "AutoFarmGUI", false, game:GetService("CoreGui")

local FULL = UDim2.new(0,300,0,500)

local main = Instance.new("Frame", sg)
main.Size, main.Position = FULL, UDim2.new(0.5,-150,0.5,-250)
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
title.Text, title.TextColor3 = "⚡ Auto Farm", C.text
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

-- ============================================================
-- SECTION HEADER (Fish)
-- ============================================================
local function makeSection(parent, yPos, text)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size, lbl.Position, lbl.BackgroundTransparency = UDim2.new(1,-16,0,18), UDim2.new(0,8,0,yPos), 1
    lbl.Text, lbl.TextColor3 = text, C.accent
    lbl.Font, lbl.TextSize = Enum.Font.GothamBold, 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    return lbl
end

makeSection(body, 4, "🐟 COLLECT + SELL")

-- Tombol Fish
local fishBtn = makeBtn(body, UDim2.new(1,-16,0,36), UDim2.new(0,8,0,24), C.bad, "▶ Start Auto", 14)

-- Info bar Fish
local info = Instance.new("TextLabel", body)
info.Size, info.Position, info.BackgroundColor3 = UDim2.new(1,-16,0,26), UDim2.new(0,8,0,64), C.alt
info.BorderSizePixel = 0
info.Text, info.TextColor3 = "Bait: 0 | C:0 | S:0 | Cy:0 | F:0", C.text
info.Font, info.TextSize = Enum.Font.Gotham, 10
Instance.new("UICorner", info).CornerRadius = UDim.new(0,5)

-- Scroll list Fish
local scroll = Instance.new("ScrollingFrame", body)
scroll.Size, scroll.Position = UDim2.new(1,-16,0,90), UDim2.new(0,8,0,94)
scroll.BackgroundColor3, scroll.BorderSizePixel = C.panel, 0
scroll.ScrollBarThickness, scroll.ScrollBarImageColor3 = 4, C.accent
scroll.CanvasSize, scroll.AutomaticCanvasSize = UDim2.new(0,0,0,0), Enum.AutomaticSize.Y
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0,5)
local ll = Instance.new("UIListLayout", scroll)
ll.SortOrder, ll.Padding = Enum.SortOrder.LayoutOrder, UDim.new(0,2)
local lp = Instance.new("UIPadding", scroll)
lp.PaddingTop, lp.PaddingBottom = UDim.new(0,4), UDim.new(0,4)
lp.PaddingLeft, lp.PaddingRight = UDim.new(0,4), UDim.new(0,4)

local fishStatus = Instance.new("TextLabel", body)
fishStatus.Size, fishStatus.Position = UDim2.new(1,-16,0,14), UDim2.new(0,8,0,186)
fishStatus.BackgroundTransparency = 1
fishStatus.Text, fishStatus.TextColor3 = "Ready.", C.dim
fishStatus.Font, fishStatus.TextSize = Enum.Font.Gotham, 10
fishStatus.TextXAlignment, fishStatus.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd

-- ============================================================
-- SECTION HEADER (Feeder)
-- ============================================================
makeSection(body, 206, "🌾 AUTO FEEDER")

-- Input rows Feeder
local function makeInputRow(yPos, labelText, defaultText)
    local Label = Instance.new("TextLabel", body)
    Label.Size, Label.Position, Label.BackgroundTransparency = UDim2.new(0.5,-10,0,22), UDim2.new(0,8,0,yPos), 1
    Label.Text, Label.TextColor3 = labelText, C.text
    Label.Font, Label.TextSize = Enum.Font.Gotham, 11
    Label.TextXAlignment = Enum.TextXAlignment.Left

    local Box = Instance.new("TextBox", body)
    Box.Size, Box.Position, Box.BackgroundColor3 = UDim2.new(0.5,-10,0,22), UDim2.new(0.5,2,0,yPos), C.alt
    Box.BorderSizePixel = 0
    Box.Text, Box.TextColor3 = defaultText, C.text
    Box.Font, Box.TextSize = Enum.Font.Gotham, 11
    Box.ClearTextOnFocus = false
    Instance.new("UICorner", Box).CornerRadius = UDim.new(0,5)

    return Box
end

local IntervalBox = makeInputRow(226, "Interval (detik)", tostring(INTERVAL))
local PlaceCountBox = makeInputRow(252, "Place per jenis", tostring(PLACE_COUNT))
local FeederDelayBox = makeInputRow(278, "Delay feeder (s)", tostring(FEEDER_DELAY))

-- Tombol Feeder
local feederBtn = makeBtn(body, UDim2.new(1,-16,0,36), UDim2.new(0,8,0,304), C.ok, "▶ Start Feeder", 14)

-- Log Feeder
local logFrame = Instance.new("ScrollingFrame", body)
logFrame.Size, logFrame.Position = UDim2.new(1,-16,0,80), UDim2.new(0,8,0,346)
logFrame.BackgroundColor3, logFrame.BorderSizePixel = C.panel, 0
logFrame.ScrollBarThickness = 4
logFrame.CanvasSize, logFrame.AutomaticCanvasSize = UDim2.new(0,0,0,0), Enum.AutomaticSize.Y
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0,5)
local logLayout = Instance.new("UIListLayout", logFrame)
logLayout.Padding, logLayout.SortOrder = UDim.new(0,2), Enum.SortOrder.LayoutOrder
local logPad = Instance.new("UIPadding", logFrame)
logPad.PaddingTop, logPad.PaddingLeft, logPad.PaddingRight = UDim.new(0,4), UDim.new(0,6), UDim.new(0,6)

-- ============================================================
-- MINIMIZE
-- ============================================================
local MIN = UDim2.new(0,160,0,28)
local isMin = false
local savedPos = main.Position
local function setMin(state)
    isMin = state
    if state then
        savedPos = main.Position
        body.Visible, closeBtn.Visible = false, false
        minBtn.Text, minBtn.Position = "+", UDim2.new(1,-26,0,3)
        main.Size, title.Text = MIN, "⚡ AF"
    else
        body.Visible, closeBtn.Visible = true, true
        minBtn.Text, minBtn.Position = "—", UDim2.new(1,-52,0,3)
        main.Size, main.Position = FULL, savedPos
        title.Text = "⚡ Auto Farm"
    end
end
minBtn.MouseButton1Click:Connect(function() setMin(not isMin) end)
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 and isMin then setMin(false) end
end)

-- ============================================================
-- RENDER FISH
-- ============================================================
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

-- ============================================================
-- CORE FISH
-- ============================================================
local function collect(uid)
    local ok = pcall(collectRemote.FireServer, collectRemote, uid)
    if ok then collectSent = collectSent + 1 else failed = failed + 1 end
end

local function sell()
    local ok = pcall(sellRemote.FireServer, sellRemote)
    if ok then sellSent = sellSent + 1 else failed = failed + 1 end
end

local function runCycle()
    currentUIDs = scanPond()
    render()

    if #currentUIDs == 0 then
        fishStatus.Text = "⏳ Pond kosong, tunggu..."
        return
    end

    for _, b in ipairs(currentUIDs) do
        if not fishRunning then return end
        collect(b.uid)
    end
    sell()

    cycles = cycles + 1
    updateInfo()
    fishStatus.Text = string.format("⚡ Cycle #%d: %d collect + sell", cycles, #currentUIDs)
end

local function startFishLoop()
    if fishThread then return end
    fishThread = task.spawn(function()
        while fishRunning and sg.Parent do
            runCycle()
            task.wait(cycleInterval)
        end
        fishThread = nil
    end)
end

local function stopFishLoop()
    fishRunning = false
    if fishThread then pcall(task.cancel, fishThread); fishThread = nil end
end

fishBtn.MouseButton1Click:Connect(function()
    fishRunning = not fishRunning
    if fishRunning then
        fishBtn.BackgroundColor3 = C.ok
        fishBtn.Text = "⏸ Stop Auto"
        fishStatus.Text = "Auto collect + sell AKTIF."
        startFishLoop()
    else
        fishBtn.BackgroundColor3 = C.bad
        fishBtn.Text = "▶ Start Auto"
        fishStatus.Text = "Auto nonaktif."
        stopFishLoop()
    end
end)

-- ============================================================
-- CORE FEEDER
-- ============================================================
local function log(msg)
    local entry = Instance.new("TextLabel", logFrame)
    entry.Size, entry.BackgroundTransparency = UDim2.new(1,0,0,14), 1
    entry.Text, entry.TextColor3 = "• " .. msg, Color3.fromRGB(200,220,200)
    entry.Font, entry.TextSize = Enum.Font.Code, 10
    entry.TextXAlignment = Enum.TextXAlignment.Left

    if #logFrame:GetChildren() > 55 then
        for _, child in ipairs(logFrame:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy(); break end
        end
    end
end

local function SwitchSlot(slot)
    SwitchPetLoadout:InvokeServer(slot)
    task.wait(SWITCH_DELAY)
end

local function PlaceFeeders(list)
    log("Switch ke slot 1")
    SwitchSlot(1)

    for _, feeder in ipairs(list) do
        if not feederRunning then return end
        log("Place " .. feeder .. " x" .. PLACE_COUNT)
        for i = 1, PLACE_COUNT do
            if not feederRunning then return end
            placeRemote:InvokeServer("booster", feeder, Position)
            task.wait(FEEDER_DELAY)
        end
    end

    log("Switch ke slot 0")
    SwitchSlot(0)
    log("Selesai. Menunggu " .. INTERVAL .. "s")
end

local function RunFeederLoop()
    while feederRunning do
        PlaceFeeders(Feeders)
        local waited = 0
        while waited < INTERVAL and feederRunning do
            task.wait(1)
            waited = waited + 1
        end
    end
    log("Loop dihentikan")
end

feederBtn.MouseButton1Click:Connect(function()
    if feederRunning then
        feederRunning = false
        feederBtn.Text = "▶ Start Feeder"
        feederBtn.BackgroundColor3 = C.ok
    else
        local ok1, v1 = pcall(function() return tonumber(IntervalBox.Text) end)
        local ok2, v2 = pcall(function() return tonumber(PlaceCountBox.Text) end)
        local ok3, v3 = pcall(function() return tonumber(FeederDelayBox.Text) end)

        if ok1 and v1 and v1 > 0 then INTERVAL = v1 end
        if ok2 and v2 and v2 > 0 then PLACE_COUNT = math.floor(v2) end
        if ok3 and v3 and v3 >= 0 then FEEDER_DELAY = v3 end

        feederRunning = true
        feederBtn.Text = "■ Stop Feeder"
        feederBtn.BackgroundColor3 = C.bad
        log("Start | interval=" .. INTERVAL .. "s, count=" .. PLACE_COUNT .. ", delay=" .. FEEDER_DELAY)

        feederThread = task.spawn(RunFeederLoop)
    end
end)

-- ============================================================
-- CLOSE
-- ============================================================
closeBtn.MouseButton1Click:Connect(function()
    stopFishLoop()
    feederRunning = false
    sg:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
currentUIDs = scanPond()
render()
fishStatus.Text = "Ready. Snapshot: " .. #currentUIDs .. " bait."
