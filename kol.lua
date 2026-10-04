-- ============================================================
-- AUTO COLLECT + SELL FISH — TANPA JEDA
-- Pond sendiri | Scan sekali | Collect + Sell instant
-- Remotes:
--   - bait.collectAllFish(uid)
--   - sellFish.sellAllFish()
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ====== DEPENDENCY ======
local getPlayerDataById = require(ReplicatedStorage.TS.state["player-data"]).getPlayerDataById

-- ====== REMOTES ======
local remoContainer = ReplicatedStorage
    :WaitForChild("rbxts_include")
    :WaitForChild("node_modules")
    :WaitForChild("@rbxts")
    :WaitForChild("remo")
    :WaitForChild("src")
    :WaitForChild("container")

local collectFishRemote = remoContainer:WaitForChild("bait.collectAllFish")
local sellAllFishRemote = remoContainer:WaitForChild("sellFish.sellAllFish")

-- ====== CONFIG ======
local DEFAULT_CYCLE_INTERVAL = 0.5   -- jeda antar SIKLUS (bukan antar remote)

-- ====== STATE ======
local autoRunEnabled = false
local cycleInterval = DEFAULT_CYCLE_INTERVAL
local mainThread = nil
local currentUIDs = {}
local collectSent = 0
local sellSent = 0
local failedCount = 0
local cyclesDone = 0
local autoSellEnabled = true

-- ============================================================
-- HELPERS
-- ============================================================
local function resolveBaitName(bait)
    if type(bait) == "string" then return bait end
    if type(bait) ~= "table" then return "?" end
    for _, key in ipairs({ "baitType", "type", "baitId", "id", "name" }) do
        local v = bait[key]
        if type(v) == "string" then return v end
    end
    return "unknown"
end

local function scanOwnPond()
    local uids = {}
    local ok, data = pcall(function()
        return getPlayerDataById(tostring(LocalPlayer.UserId))
    end)
    if not ok or not data or not data.ponds then return uids end
    local pond = data.ponds[data.currentPond]
    if not pond or not pond.baits then return uids end
    for uid, bait in pairs(pond.baits) do
        table.insert(uids, {
            uid = tostring(uid),
            baitType = resolveBaitName(bait),
            mutation = (type(bait) == "table" and bait.mutation) or nil,
            amount = (type(bait) == "table" and (bait.amount or bait.count)) or 1,
            pond = tostring(data.currentPond),
        })
    end
    table.sort(uids, function(a, b) return a.uid < b.uid end)
    return uids
end

local function countFishInInventory()
    local ok, data = pcall(function()
        return getPlayerDataById(tostring(LocalPlayer.UserId))
    end)
    if not ok or not data or not data.inventory or not data.inventory.fishes then
        return 0
    end
    local n = 0
    for _ in pairs(data.inventory.fishes) do n = n + 1 end
    return n
end

-- ============================================================
-- GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoCollectSellGUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = game:GetService("CoreGui")

local COLORS = {
    bg = Color3.fromRGB(22, 24, 30),
    panel = Color3.fromRGB(34, 37, 45),
    panelAlt = Color3.fromRGB(44, 48, 58),
    accent = Color3.fromRGB(88, 166, 255),
    text = Color3.fromRGB(230, 232, 238),
    textDim = Color3.fromRGB(150, 155, 165),
    success = Color3.fromRGB(80, 200, 120),
    danger = Color3.fromRGB(240, 90, 90),
    warning = Color3.fromRGB(240, 180, 80),
    sell = Color3.fromRGB(255, 180, 80),
}

-- MAIN
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 520, 0, 560)
main.Position = UDim2.new(0.5, -260, 0.5, -280)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = COLORS.accent
stroke.Thickness = 1
stroke.Transparency = 0.5

-- TITLE
local titleBar = Instance.new("Frame", main)
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = COLORS.panel
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)
local titleCover = Instance.new("Frame", titleBar)
titleCover.Size = UDim2.new(1, 0, 0, 10)
titleCover.Position = UDim2.new(0, 0, 1, -10)
titleCover.BackgroundColor3 = COLORS.panel
titleCover.BorderSizePixel = 0

local title = Instance.new("TextLabel", titleBar)
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡  Auto Collect + Sell (No Delay)"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = COLORS.danger
closeBtn.Text = "✕"
closeBtn.TextColor3 = COLORS.text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- ====== CONTROL PANEL ======
local ctrl = Instance.new("Frame", main)
ctrl.Size = UDim2.new(1, -20, 0, 110)
ctrl.Position = UDim2.new(0, 10, 0, 46)
ctrl.BackgroundColor3 = COLORS.panel
ctrl.BorderSizePixel = 0
Instance.new("UICorner", ctrl).CornerRadius = UDim.new(0, 8)

-- Toggle
local toggleBtn = Instance.new("TextButton", ctrl)
toggleBtn.Size = UDim2.new(0, 160, 0, 40)
toggleBtn.Position = UDim2.new(0, 12, 0, 12)
toggleBtn.BackgroundColor3 = COLORS.danger
toggleBtn.Text = "▶  Start Auto"
toggleBtn.TextColor3 = COLORS.text
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- Manual collect
local manualCollectBtn = Instance.new("TextButton", ctrl)
manualCollectBtn.Size = UDim2.new(0, 150, 0, 40)
manualCollectBtn.Position = UDim2.new(0, 180, 0, 12)
manualCollectBtn.BackgroundColor3 = COLORS.accent
manualCollectBtn.Text = "📤  Collect"
manualCollectBtn.TextColor3 = COLORS.text
manualCollectBtn.Font = Enum.Font.GothamBold
manualCollectBtn.TextSize = 13
Instance.new("UICorner", manualCollectBtn).CornerRadius = UDim.new(0, 6)

-- Manual sell
local manualSellBtn = Instance.new("TextButton", ctrl)
manualSellBtn.Size = UDim2.new(0, 160, 0, 40)
manualSellBtn.Position = UDim2.new(0, 338, 0, 12)
manualSellBtn.BackgroundColor3 = COLORS.sell
manualSellBtn.Text = "💰  Sell All"
manualSellBtn.TextColor3 = COLORS.text
manualSellBtn.Font = Enum.Font.GothamBold
manualSellBtn.TextSize = 13
Instance.new("UICorner", manualSellBtn).CornerRadius = UDim.new(0, 6)

-- Cycle interval input
local cycleIntervalLbl = Instance.new("TextLabel", ctrl)
cycleIntervalLbl.Size = UDim2.new(0, 100, 0, 20)
cycleIntervalLbl.Position = UDim2.new(0, 12, 0, 60)
cycleIntervalLbl.BackgroundTransparency = 1
cycleIntervalLbl.Text = "Cycle jeda (s):"
cycleIntervalLbl.TextColor3 = COLORS.textDim
cycleIntervalLbl.Font = Enum.Font.Gotham
cycleIntervalLbl.TextSize = 11
cycleIntervalLbl.TextXAlignment = Enum.TextXAlignment.Left

local cycleIntervalBox = Instance.new("TextBox", ctrl)
cycleIntervalBox.Size = UDim2.new(0, 80, 0, 24)
cycleIntervalBox.Position = UDim2.new(0, 115, 0, 58)
cycleIntervalBox.BackgroundColor3 = COLORS.panelAlt
cycleIntervalBox.BorderSizePixel = 0
cycleIntervalBox.Text = tostring(DEFAULT_CYCLE_INTERVAL)
cycleIntervalBox.TextColor3 = COLORS.text
cycleIntervalBox.Font = Enum.Font.Code
cycleIntervalBox.TextSize = 12
cycleIntervalBox.ClearTextOnFocus = false
Instance.new("UICorner", cycleIntervalBox).CornerRadius = UDim.new(0, 4)

cycleIntervalBox.FocusLost:Connect(function()
    local n = tonumber(cycleIntervalBox.Text)
    if n and n >= 0 then
        cycleInterval = n
        statusBar.Text = "Cycle interval: " .. tostring(n) .. "s"
    else
        cycleIntervalBox.Text = tostring(cycleInterval)
    end
end)

-- Info label untuk jeda
local delayInfoLbl = Instance.new("TextLabel", ctrl)
delayInfoLbl.Size = UDim2.new(0, 200, 0, 24)
delayInfoLbl.Position = UDim2.new(0, 200, 0, 58)
delayInfoLbl.BackgroundTransparency = 1
delayInfoLbl.Text = "⚡ Collect & Sell: instant (no delay)"
delayInfoLbl.TextColor3 = COLORS.success
delayInfoLbl.Font = Enum.Font.GothamBold
delayInfoLbl.TextSize = 11
delayInfoLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Toggles row
local autoSellToggle = Instance.new("TextButton", ctrl)
autoSellToggle.Size = UDim2.new(0, 160, 0, 30)
autoSellToggle.Position = UDim2.new(0, 12, 0, 88)
autoSellToggle.BackgroundColor3 = COLORS.sell
autoSellToggle.Text = "💰  Auto Sell: ON"
autoSellToggle.TextColor3 = COLORS.text
autoSellToggle.Font = Enum.Font.GothamBold
autoSellToggle.TextSize = 12
Instance.new("UICorner", autoSellToggle).CornerRadius = UDim.new(0, 6)

local refreshBtn = Instance.new("TextButton", ctrl)
refreshBtn.Size = UDim2.new(0, 150, 0, 30)
refreshBtn.Position = UDim2.new(0, 180, 0, 88)
refreshBtn.BackgroundColor3 = COLORS.accent
refreshBtn.Text = "🔄  Rescan Pond"
refreshBtn.TextColor3 = COLORS.text
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 12
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)

local clearLogBtn = Instance.new("TextButton", ctrl)
clearLogBtn.Size = UDim2.new(0, 160, 0, 30)
clearLogBtn.Position = UDim2.new(0, 338, 0, 88)
clearLogBtn.BackgroundColor3 = COLORS.panelAlt
clearLogBtn.Text = "🧹  Reset Counter"
clearLogBtn.TextColor3 = COLORS.text
clearLogBtn.Font = Enum.Font.GothamBold
clearLogBtn.TextSize = 11
Instance.new("UICorner", clearLogBtn).CornerRadius = UDim.new(0, 6)

-- ====== INFO BAR ======
local infoBar = Instance.new("Frame", main)
infoBar.Size = UDim2.new(1, -20, 0, 54)
infoBar.Position = UDim2.new(0, 10, 0, 162)
infoBar.BackgroundColor3 = COLORS.panelAlt
infoBar.BorderSizePixel = 0
Instance.new("UICorner", infoBar).CornerRadius = UDim.new(0, 6)

local infoLbl1 = Instance.new("TextLabel", infoBar)
infoLbl1.Size = UDim2.new(1, -20, 0, 26)
infoLbl1.Position = UDim2.new(0, 10, 0, 0)
infoLbl1.BackgroundTransparency = 1
infoLbl1.Text = "Pond: - | Bait (snapshot): 0 | Fish in Inv: 0"
infoLbl1.TextColor3 = COLORS.text
infoLbl1.Font = Enum.Font.GothamBold
infoLbl1.TextSize = 12
infoLbl1.TextXAlignment = Enum.TextXAlignment.Left

local infoLbl2 = Instance.new("TextLabel", infoBar)
infoLbl2.Size = UDim2.new(1, -20, 0, 24)
infoLbl2.Position = UDim2.new(0, 10, 0, 26)
infoLbl2.BackgroundTransparency = 1
infoLbl2.Text = "Collect: 0 | Sell: 0 | Cycles: 0 | Failed: 0"
infoLbl2.TextColor3 = COLORS.textDim
infoLbl2.Font = Enum.Font.Gotham
infoLbl2.TextSize = 11
infoLbl2.TextXAlignment = Enum.TextXAlignment.Left

-- ====== LIST HEADER ======
local listHeader = Instance.new("Frame", main)
listHeader.Size = UDim2.new(1, -20, 0, 24)
listHeader.Position = UDim2.new(0, 10, 0, 224)
listHeader.BackgroundTransparency = 1

local h1 = Instance.new("TextLabel", listHeader)
h1.Size = UDim2.new(0, 70, 1, 0)
h1.Position = UDim2.new(0, 10, 0, 0)
h1.BackgroundTransparency = 1
h1.Text = "Type"
h1.TextColor3 = COLORS.textDim
h1.Font = Enum.Font.GothamBold
h1.TextSize = 11
h1.TextXAlignment = Enum.TextXAlignment.Left

local h2 = Instance.new("TextLabel", listHeader)
h2.Size = UDim2.new(0, 80, 1, 0)
h2.Position = UDim2.new(0, 90, 0, 0)
h2.BackgroundTransparency = 1
h2.Text = "Mutation"
h2.TextColor3 = COLORS.textDim
h2.Font = Enum.Font.GothamBold
h2.TextSize = 11
h2.TextXAlignment = Enum.TextXAlignment.Left

local h3 = Instance.new("TextLabel", listHeader)
h3.Size = UDim2.new(1, -180, 1, 0)
h3.Position = UDim2.new(0, 180, 0, 0)
h3.BackgroundTransparency = 1
h3.Text = "UID"
h3.TextColor3 = COLORS.textDim
h3.Font = Enum.Font.GothamBold
h3.TextSize = 11
h3.TextXAlignment = Enum.TextXAlignment.Left

-- ====== SCROLL LIST ======
local scroll = Instance.new("ScrollingFrame", main)
scroll.Size = UDim2.new(1, -20, 1, -280)
scroll.Position = UDim2.new(0, 10, 0, 252)
scroll.BackgroundColor3 = COLORS.panel
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = COLORS.accent
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)

local listPad = Instance.new("UIPadding", scroll)
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 6)
listPad.PaddingLeft = UDim.new(0, 6)
listPad.PaddingRight = UDim.new(0, 6)

-- ====== STATUS ======
local statusBar = Instance.new("TextLabel", main)
statusBar.Size = UDim2.new(1, -20, 0, 30)
statusBar.Position = UDim2.new(0, 10, 1, -38)
statusBar.BackgroundTransparency = 1
statusBar.Text = "Ready."
statusBar.TextColor3 = COLORS.textDim
statusBar.Font = Enum.Font.Gotham
statusBar.TextSize = 11
statusBar.TextXAlignment = Enum.TextXAlignment.Left
statusBar.TextWrapped = true

-- ============================================================
-- RENDER
-- ============================================================
local function createRow(bait, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = COLORS.panelAlt
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    local typeLbl = Instance.new("TextLabel", row)
    typeLbl.Size = UDim2.new(0, 80, 1, 0)
    typeLbl.Position = UDim2.new(0, 10, 0, 0)
    typeLbl.BackgroundTransparency = 1
    typeLbl.Text = "🎣 " .. tostring(bait.baitType)
    typeLbl.TextColor3 = COLORS.text
    typeLbl.Font = Enum.Font.GothamMedium
    typeLbl.TextSize = 12
    typeLbl.TextXAlignment = Enum.TextXAlignment.Left

    local mutLbl = Instance.new("TextLabel", row)
    mutLbl.Size = UDim2.new(0, 80, 1, 0)
    mutLbl.Position = UDim2.new(0, 90, 0, 0)
    mutLbl.BackgroundTransparency = 1
    mutLbl.Text = tostring(bait.mutation or "-")
    mutLbl.TextColor3 = COLORS.textDim
    mutLbl.Font = Enum.Font.Gotham
    mutLbl.TextSize = 11
    mutLbl.TextXAlignment = Enum.TextXAlignment.Left

    local uidLbl = Instance.new("TextLabel", row)
    uidLbl.Size = UDim2.new(1, -180, 1, 0)
    uidLbl.Position = UDim2.new(0, 180, 0, 0)
    uidLbl.BackgroundTransparency = 1
    uidLbl.Text = bait.uid
    uidLbl.TextColor3 = COLORS.text
    uidLbl.Font = Enum.Font.Code
    uidLbl.TextSize = 11
    uidLbl.TextXAlignment = Enum.TextXAlignment.Left
    uidLbl.TextTruncate = Enum.TextTruncate.AtEnd

    return row
end

local function updateInfo()
    local pondName = currentUIDs[1] and currentUIDs[1].pond or "-"
    infoLbl1.Text = string.format("Pond: %s | Bait (snapshot): %d | Fish in Inv: %d",
        pondName, #currentUIDs, countFishInInventory())
    infoLbl2.Text = string.format("Collect: %d | Sell: %d | Cycles: %d | Failed: %d",
        collectSent, sellSent, cyclesDone, failedCount)
end

local function render()
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for i, bait in ipairs(currentUIDs) do
        createRow(bait, i)
    end
    updateInfo()
end

-- ============================================================
-- CORE — TANPA JEDA
-- ============================================================
local function sendCollect(uid)
    local ok, err = pcall(function()
        collectFishRemote:FireServer(uid)
    end)
    if ok then
        collectSent = collectSent + 1
        return true
    else
        failedCount = failedCount + 1
        warn("[Collect] Error:", err)
        return false
    end
end

local function sendSellAll()
    local ok, err = pcall(function()
        sellAllFishRemote:FireServer()
    end)
    if ok then
        sellSent = sellSent + 1
        return true
    else
        failedCount = failedCount + 1
        warn("[Sell] Error:", err)
        return false
    end
end

-- Collect semua UID dalam snapshot — TANPA task.wait
local function collectAllNow()
    if #currentUIDs == 0 then
        statusBar.Text = "⚠ Snapshot kosong. Klik Rescan Pond dulu."
        return 0
    end
    local n = 0
    for _, bait in ipairs(currentUIDs) do
        if sendCollect(bait.uid) then n = n + 1 end
        -- ❌ tidak ada task.wait di sini
    end
    updateInfo()
    statusBar.Text = string.format("⚡ Collect instant %d/%d bait (no delay).", n, #currentUIDs)
    return n
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function runCycle()
    if #currentUIDs == 0 then
        statusBar.Text = "⏳ Snapshot kosong. Klik Rescan Pond."
        return
    end

    -- 1. Collect semua UID — INSTANT
    local okCount = 0
    for _, bait in ipairs(currentUIDs) do
        if not autoRunEnabled then return end
        if sendCollect(bait.uid) then okCount = okCount + 1 end
        -- ❌ tidak ada jeda antar UID
    end
    statusBar.Text = string.format("⚡ Collect instant: %d/%d", okCount, #currentUIDs)
    updateInfo()

    -- 2. Auto Sell — INSTANT (langsung setelah collect, tidak ada jeda)
    if autoSellEnabled and autoRunEnabled then
        if sendSellAll() then
            statusBar.Text = "⚡ Collect + Sell instant selesai."
        else
            statusBar.Text = "✕ Sell All gagal."
        end
        updateInfo()
    end

    cyclesDone = cyclesDone + 1
    updateInfo()
end

local function startMainLoop()
    if mainThread then return end
    mainThread = task.spawn(function()
        while autoRunEnabled and screenGui.Parent do
            runCycle()
            task.wait(cycleInterval)  -- jeda HANYA antar siklus
        end
        mainThread = nil
    end)
end

local function stopMainLoop()
    autoRunEnabled = false
    if mainThread then
        pcall(task.cancel, mainThread)
        mainThread = nil
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
toggleBtn.MouseButton1Click:Connect(function()
    autoRunEnabled = not autoRunEnabled
    if autoRunEnabled then
        toggleBtn.BackgroundColor3 = COLORS.success
        toggleBtn.Text = "⏸  Stop Auto"
        statusBar.Text = "⚡ Auto instant AKTIF (collect+sell tanpa jeda)."
        startMainLoop()
    else
        toggleBtn.BackgroundColor3 = COLORS.danger
        toggleBtn.Text = "▶  Start Auto"
        statusBar.Text = "Auto nonaktif."
        stopMainLoop()
    end
end)

autoSellToggle.MouseButton1Click:Connect(function()
    autoSellEnabled = not autoSellEnabled
    if autoSellEnabled then
        autoSellToggle.BackgroundColor3 = COLORS.sell
        autoSellToggle.Text = "💰  Auto Sell: ON"
    else
        autoSellToggle.BackgroundColor3 = COLORS.panelAlt
        autoSellToggle.Text = "💰  Auto Sell: OFF"
    end
end)

manualCollectBtn.MouseButton1Click:Connect(function()
    collectAllNow()
end)

manualSellBtn.MouseButton1Click:Connect(function()
    if sendSellAll() then
        statusBar.Text = "⚡ Sell All instant terkirim."
    else
        statusBar.Text = "✕ Sell All gagal."
    end
    updateInfo()
end)

refreshBtn.MouseButton1Click:Connect(function()
    currentUIDs = scanOwnPond()
    render()
    statusBar.Text = "Rescan selesai: " .. #currentUIDs .. " bait."
end)

clearLogBtn.MouseButton1Click:Connect(function()
    collectSent = 0
    sellSent = 0
    failedCount = 0
    cyclesDone = 0
    updateInfo()
    statusBar.Text = "Counter di-reset."
end)

closeBtn.MouseButton1Click:Connect(function()
    stopMainLoop()
    screenGui:Destroy()
end)

-- ============================================================
-- INIT — SCAN SEKALI
-- ============================================================
currentUIDs = scanOwnPond()
render()
statusBar.Text = "Ready. Snapshot: " .. #currentUIDs .. " bait. Klik Start Auto untuk mulai."
print("[AutoCollect+Sell] No-Delay mode. Snapshot bait:", #currentUIDs)
