-- LoHub Executor / StarterPlayerScripts (LocalScript)
-- "Lọ Hub" - VN theme - Rayfield UI if available, fallback otherwise
-- FEATURES: Platform on jump (thin/wide), Speed x1.5, Jump x2, Teleport +/-1000, Fake Skin (local), ESP name + red dot, VN Sky overlay
-- SAFE: client-side visual & local modifications only; does NOT bypass server anti-cheat.

-- ========== CONFIG ==========
local RAYFIELD_URL = "https://raw.githubusercontent.com/shlexware/Rayfield/main/source" -- Rayfield loader attempt
local VN_PRIMARY = Color3.fromRGB(192, 11, 11)
local VN_ACCENT = Color3.fromRGB(255, 204, 0)
local VN_TEXT = Color3.fromRGB(255,255,255)

local DEFAULT_PLATFORM_DELAY = 0.25
local DEFAULT_PLATFORM_WIDTH = 8
local DEFAULT_PLATFORM_THICKNESS = 0.25
local DEFAULT_PLATFORM_LIFETIME = 3

-- If your game has ReplicatedStorage.LoHubEvents with RemoteEvents, script will use them (optional)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EVENTS = ReplicatedStorage:FindFirstChild("LoHubEvents")
local SetBoost = EVENTS and EVENTS:FindFirstChild("SetBoost")
local TeleportReq = EVENTS and EVENTS:FindFirstChild("TeleportReq")
local ApplyFakeSkin = EVENTS and EVENTS:FindFirstChild("ApplyFakeSkin")
local PlatformRequest = EVENTS and EVENTS:FindFirstChild("PlatformRequest")

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer

-- ========== TRY LOAD RAYFIELD ==========
local Rayfield = nil
pcall(function()
    local loader = game:HttpGet(RAYFIELD_URL)
    if loader and type(loader) == "string" then
        local ok, rf = pcall(loadstring(loader))
        if ok and rf then Rayfield = rf end
    end
end)

local function notify(title, content, dur)
    dur = dur or 3
    if Rayfield and Rayfield.Notify then
        pcall(function() Rayfield:Notify({Title = title, Content = content, Duration = dur}) end)
    else
        -- fallback small hint on screen
        print("[LoHub] "..tostring(title)..": "..tostring(content))
    end
end

-- ========== STATE ==========
local state = {
    platformEnabled = false,
    platformDelay = DEFAULT_PLATFORM_DELAY,
    platformWidth = DEFAULT_PLATFORM_WIDTH,
    platformThickness = DEFAULT_PLATFORM_THICKNESS,
    platformLifetime = DEFAULT_PLATFORM_LIFETIME,
    speedEnabled = false,
    jumpEnabled = false,
    espEnabled = false,
    vnSkyEnabled = false
}

-- ========== UI BUILD HELPERS ==========
local Window, TabMovement, TabBoosts, TabVisual, TabTeleport

if Rayfield then
    Window = Rayfield:CreateWindow({
        Name = "Lọ Hub",
        LoadingTitle = "Lọ Hub",
        LoadingSubtitle = "Steal a Lọ - VN",
        ConfigurationSaving = { Enabled = false }
    })
    TabMovement = Window:CreateTab("Movement", 4483362458)
    TabBoosts = Window:CreateTab("Boosts", 4483362458)
    TabVisual = Window:CreateTab("Visual", 4483362458)
    TabTeleport = Window:CreateTab("Teleport", 4483362458)
else
    -- fallback simple ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LoHub_Fallback"
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

    local function mkFrame(title, y)
        local f = Instance.new("Frame", screenGui)
        f.Size = UDim2.new(0, 320, 0, 110)
        f.Position = UDim2.new(0, 10, 0, 10 + (y-1)*120)
        f.BackgroundColor3 = VN_PRIMARY
        f.BorderSizePixel = 0
        local t = Instance.new("TextLabel", f)
        t.Size = UDim2.new(1,0,0,26)
        t.Position = UDim2.new(0,0,0,0)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = VN_TEXT
        t.TextScaled = true
        return f
    end

    TabMovement = mkFrame("Movement", 1)
    TabBoosts = mkFrame("Boosts", 2)
    TabVisual = mkFrame("Visual", 3)
    TabTeleport = mkFrame("Teleport", 4)
end

local function createToggle(tab, name, initial, cb)
    if Rayfield and tab.CreateToggle then
        tab:CreateToggle({ Name = name, CurrentValue = initial, Callback = cb })
        return
    end
    -- fallback: create small button
    local b = Instance.new("TextButton", tab)
    b.Size = UDim2.new(1, -12, 0, 28)
    b.Position = UDim2.new(0,6,0,30 + (#tab:GetChildren())*32)
    b.Text = name.." : "..(initial and "ON" or "OFF")
    b.TextColor3 = VN_TEXT
    b.BackgroundColor3 = VN_PRIMARY
    local stateVal = initial
    b.MouseButton1Click:Connect(function()
        stateVal = not stateVal
        b.Text = name.." : "..(stateVal and "ON" or "OFF")
        pcall(cb, stateVal)
    end)
end

local function createButton(tab, name, cb)
    if Rayfield and tab.CreateButton then
        tab:CreateButton({ Name = name, Callback = cb })
        return
    end
    local b = Instance.new("TextButton", tab)
    b.Size = UDim2.new(1, -12, 0, 28)
    b.Position = UDim2.new(0,6,0,30 + (#tab:GetChildren())*32)
    b.Text = name
    b.TextColor3 = VN_TEXT
    b.BackgroundColor3 = VN_ACCENT
    b.MouseButton1Click:Connect(function() pcall(cb) end)
end

local function createSlider(tab, name, min, max, inc, default, cb)
    if Rayfield and tab.CreateSlider then
        tab:CreateSlider({ Name = name, Range = {min, max}, Increment = inc, CurrentValue = default, Callback = cb })
        return
    end
    -- fallback: two small buttons + label
    local frame = Instance.new("Frame", tab)
    frame.Size = UDim2.new(1, -12, 0, 28)
    frame.Position = UDim2.new(0,6,0,30 + (#tab:GetChildren())*32)
    frame.BackgroundTransparency = 1
    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.6,0,1,0); label.BackgroundTransparency = 1; label.Text = name..": "..tostring(default); label.TextColor3 = VN_TEXT
    local dec = Instance.new("TextButton", frame); dec.Size = UDim2.new(0.2,0,1,0); dec.Position = UDim2.new(0.6,0,0,0); dec.Text = "-"; dec.BackgroundColor3 = VN_PRIMARY
    local incb = Instance.new("TextButton", frame); incb.Size = UDim2.new(0.2,0,1,0); incb.Position = UDim2.new(0.8,0,0,0); incb.Text = "+"; incb.BackgroundColor3 = VN_PRIMARY
    local val = default
    dec.MouseButton1Click:Connect(function() val = math.max(min, val - inc); label.Text = name..": "..tostring(val); pcall(cb, val) end)
    incb.MouseButton1Click:Connect(function() val = math.min(max, val + inc); label.Text = name..": "..tostring(val); pcall(cb, val) end)
end

-- ========== UI ELEMENTS ==========
-- Movement tab: Platform toggles + sliders
createToggle(TabMovement, "Platform On Jump (thin & wide)", false, function(v) state.platformEnabled = v; notify("Platform", v and "Bật platform on jump" or "Tắt platform", 2) end)
createSlider(TabMovement, "Platform Delay (s)", 0.05, 2, 0.05, state.platformDelay, function(v) state.platformDelay = v; notify("Platform", "Delay = "..v.."s",1) end)
createSlider(TabMovement, "Platform Width (stud)", 2, 50, 1, state.platformWidth, function(v) state.platformWidth = v; notify("Platform", "Width = "..v,1) end)
createSlider(TabMovement, "Platform Thickness", 0.1, 1, 0.05, state.platformThickness, function(v) state.platformThickness = v; notify("Platform", "Thickness = "..v,1) end)
createSlider(TabMovement, "Platform Lifetime (s)", 1, 10, 0.5, state.platformLifetime, function(v) state.platformLifetime = v; notify("Platform", "Lifetime = "..v.."s",1) end)

-- Boosts tab: speed + jump toggles
createToggle(TabBoosts, "Speed Boot (x1.5)", false, function(v)
    state.speedEnabled = v
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = v and 16*1.5 or 16 end
    if SetBoost and SetBoost:IsA("RemoteEvent") then pcall(function() SetBoost:FireServer({walk = v and 16*1.5 or 16, duration = v and 999 or 0}) end) end
    notify("Speed", v and "Speed x1.5 bật" or "Speed tắt", 2)
end)

createToggle(TabBoosts, "Jump Boot (x2)", false, function(v)
    state.jumpEnabled = v
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.JumpPower = v and 50*2 or 50 end
    if SetBoost and SetBoost:IsA("RemoteEvent") then pcall(function() SetBoost:FireServer({jump = v and 50*2 or 50, duration = v and 999 or 0}) end) end
    notify("Jump", v and "Jump x2 bật" or "Jump tắt", 2)
end)

-- Teleport tab
createButton(TabTeleport, "Teleport Up +1000", function()
    if TeleportReq and TeleportReq:IsA("RemoteEvent") then
        pcall(function() TeleportReq:FireServer("up") end)
    else
        local c = localPlayer.Character
        if c and c:FindFirstChild("HumanoidRootPart") then c.HumanoidRootPart.CFrame = c.HumanoidRootPart.CFrame + Vector3.new(0,1000,0) end
    end
    notify("Teleport", "Đã teleport lên +1000", 2)
end)
createButton(TabTeleport, "Teleport Down -1000", function()
    if TeleportReq and TeleportReq:IsA("RemoteEvent") then
        pcall(function() TeleportReq:FireServer("down") end)
    else
        local c = localPlayer.Character
        if c and c:FindFirstChild("HumanoidRootPart") then c.HumanoidRootPart.CFrame = c.HumanoidRootPart.CFrame - Vector3.new(0,1000,0) end
    end
    notify("Teleport", "Đã teleport xuống -1000", 2)
end)

-- Visual tab: ESP, Fake skin, VN Sky
createToggle(TabVisual, "ESP Name + Dot", false, function(v)
    state.espEnabled = v
    if not v then
        -- remove esp
        for _,pl in pairs(Players:GetPlayers()) do
            if pl.Character and pl.Character:FindFirstChild("Head") then
                local g = pl.Character.Head:FindFirstChild("LoHubESP"); if g then g:Destroy() end
            end
            if pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local d = pl.Character.HumanoidRootPart:FindFirstChild("LoHubDot"); if d then d:Destroy() end
            end
        end
    else
        for _,pl in pairs(Players:GetPlayers()) do
            if pl ~= localPlayer and pl.Character then
                if pl.Character:FindFirstChild("Head") and not pl.Character.Head:FindFirstChild("LoHubESP") then
                    local bill = Instance.new("BillboardGui", pl.Character.Head)
                    bill.Name = "LoHubESP"; bill.Adornee = pl.Character.Head; bill.Size = UDim2.new(0,140,0,36); bill.AlwaysOnTop = true
                    local label = Instance.new("TextLabel", bill); label.Size = UDim2.new(1,0,1,0); label.BackgroundTransparency = 1
                    label.Text = pl.Name; label.TextScaled = true; label.TextColor3 = VN_TEXT
                end
                if pl.Character:FindFirstChild("HumanoidRootPart") and not pl.Character.HumanoidRootPart:FindFirstChild("LoHubDot") then
                    local dot = Instance.new("BillboardGui", pl.Character.HumanoidRootPart)
                    dot.Name = "LoHubDot"; dot.Adornee = pl.Character.HumanoidRootPart; dot.Size = UDim2.new(0,12,0,12); dot.AlwaysOnTop = true
                    local f = Instance.new("Frame", dot); f.Size = UDim2.new(1,0,1,0); f.BackgroundColor3 = Color3.fromRGB(255,0,0); f.BorderSizePixel = 0
                end
            end
        end
    end
end)

-- Fake skin input
if Rayfield and TabVisual.CreateTextBox then
    TabVisual:CreateTextBox({ Name = "Fake skin (player name)", Text = "", Placeholder = "Nhập tên người chơi", Callback = function(val)
        if type(val) == "string" and #val > 0 then
            -- prefer server
            if ApplyFakeSkin and ApplyFakeSkin:IsA("RemoteEvent") then
                pcall(function() ApplyFakeSkin:FireServer(val) end)
                notify("Fake Skin", "Gửi yêu cầu server copy skin: "..val, 2)
            else
                local target = Players:FindFirstChild(val)
                local myHum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
                if target and target.Character and myHum then
                    pcall(function()
                        local srcHum = target.Character:FindFirstChildOfClass("Humanoid")
                        if srcHum then myHum:ApplyDescription(srcHum:GetAppliedDescription()); notify("Fake Skin", "Áp skin local của "..val,2) end
                    end)
                else
                    notify("Fake Skin", "Không tìm thấy target hoặc humanoid", 2)
                end
            end
        end
    end})
else
    -- fallback: make a small UI area
    local frame = Instance.new("Frame", TabVisual)
    frame.Size = UDim2.new(1, -12, 0, 36); frame.Position = UDim2.new(0,6,0,60)
    local box = Instance.new("TextBox", frame); box.Size = UDim2.new(0.75,0,1,0); box.PlaceholderText = "Fake skin: player name"
    local btn = Instance.new("TextButton", frame); btn.Size = UDim2.new(0.25,0,1,0); btn.Position = UDim2.new(0.75,0,0,0); btn.Text = "Apply"
    btn.BackgroundColor3 = VN_ACCENT
    btn.MouseButton1Click:Connect(function()
        local val = box.Text
        if type(val) == "string" and #val > 0 then
            if ApplyFakeSkin and ApplyFakeSkin:IsA("RemoteEvent") then pcall(function() ApplyFakeSkin:FireServer(val) end); notify("Fake Skin","Gửi yêu cầu server",2) else
                local target = Players:FindFirstChild(val); local myHum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
                if target and target.Character and myHum then pcall(function() local srcHum = target.Character:FindFirstChildOfClass("Humanoid"); if srcHum then myHum:ApplyDescription(srcHum:GetAppliedDescription()); notify("Fake Skin","Áp skin local",2) end end) end
            end
        end
    end)
end

createToggle(TabVisual, "VN Sky (visual overlay)", false, function(v)
    state.vnSkyEnabled = v
    if v then
        -- create overlay
        if not game.Players.LocalPlayer:FindFirstChild("PlayerGui") then return end
        if game.Players.LocalPlayer.PlayerGui:FindFirstChild("LoHub_VN") then return end
        local g = Instance.new("ScreenGui", game.Players.LocalPlayer.PlayerGui)
        g.Name = "LoHub_VN"
        g.ResetOnSpawn = false
        local f = Instance.new("Frame", g)
        f.Size = UDim2.new(1,0,1,0); f.Position = UDim2.new(0,0,0,0); f.BackgroundColor3 = VN_PRIMARY; f.BackgroundTransparency = 0.03
        local star = Instance.new("TextLabel", f)
        star.Size = UDim2.new(0.14,0,0.14,0); star.Position = UDim2.new(0.43,0,0.43,0)
        star.Text = "★"; star.TextScaled = true; star.BackgroundTransparency = 1; star.TextColor3 = VN_ACCENT
        notify("VN Sky", "VN Sky bật (client-only)", 2)
    else
        local g = game.Players.LocalPlayer.PlayerGui:FindFirstChild("LoHub_VN")
        if g then g:Destroy() end
        notify("VN Sky", "VN Sky tắt", 1)
    end
end)

-- ========== PLATFORM SPAWN LOGIC ==========
local lastPlatformTime = 0
local function spawnLocalPlatform(cframe)
    local p = Instance.new("Part")
    p.Size = Vector3.new(state.platformWidth, state.platformThickness, state.platformWidth)
    p.Anchored = true
    p.CanCollide = true
    p.Material = Enum.Material.SmoothPlastic
    p.Color = VN_PRIMARY:lerp(Color3.new(0,1,0), 0.12)
    p.CFrame = cframe
    p.Parent = workspace
    Debris:AddItem(p, state.platformLifetime)
end

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    hum.Jumping:Connect(function(active)
        if state.platformEnabled and active then
            if tick() - lastPlatformTime < state.platformDelay then return end
            lastPlatformTime = tick()
            -- notify server if available
            if PlatformRequest and PlatformRequest:IsA("RemoteEvent") then
                pcall(function() PlatformRequest:FireServer() end)
            end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local cf = hrp.CFrame * CFrame.new(0, -3, 0)
                spawnLocalPlatform(cf)
            end
        end
    end)
end

if localPlayer.Character then onCharacterAdded(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- keep ESP for new players
Players.PlayerAdded:Connect(function(pl)
    pl.CharacterAdded:Connect(function()
        wait(0.2)
        if state.espEnabled and pl ~= localPlayer then
            -- create ESP for new player
            if pl.Character:FindFirstChild("Head") and not pl.Character.Head:FindFirstChild("LoHubESP") then
                local bill = Instance.new("BillboardGui", pl.Character.Head)
                bill.Name = "LoHubESP"; bill.Adornee = pl.Character.Head; bill.Size = UDim2.new(0,140,0,36); bill.AlwaysOnTop = true
                local lbl = Instance.new("TextLabel", bill); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = pl.Name; lbl.TextScaled = true; lbl.TextColor3 = VN_TEXT
            end
            if pl.Character:FindFirstChild("HumanoidRootPart") and not pl.Character.HumanoidRootPart:FindFirstChild("LoHubDot") then
                local dot = Instance.new("BillboardGui", pl.Character.HumanoidRootPart)
                dot.Name = "LoHubDot"; dot.Adornee = pl.Character.HumanoidRootPart; dot.Size = UDim2.new(0,12,0,12); dot.AlwaysOnTop = true
                local f = Instance.new("Frame", dot); f.Size = UDim2.new(1,0,1,0); f.BackgroundColor3 = Color3.fromRGB(255,0,0); f.BorderSizePixel = 0
            end
        end
    end)
end)

-- ========== INITIAL NOTIFY ==========
notify("Lọ Hub", "Đã load (VN theme). Dán vào StarterPlayerScripts hoặc chạy bằng executor.", 3)

-- EOF
