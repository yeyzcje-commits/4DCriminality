-- 4Money | Criminality | Lumen UI | built for many executors (features are detected, see README)
local env = (getgenv and getgenv()) or _G

-- Re-run support: tear down the previous instance instead of refusing to start
if env.Money4Window then
    pcall(function() env.Money4Window:Destroy() end)
    env.Money4Window = nil
end
if env.Money4Cleanup then
    pcall(env.Money4Cleanup)
    env.Money4Cleanup = nil
end

-- Menu library: try the normal download, then other HTTP functions of the executor, a CDN mirror and
-- finally a local copy (workspace/4D$.lua). Executors differ a lot in what they offer here.
local Lumen
do
    local URL = "https://raw.githubusercontent.com/yeyzcje-commits/4D-/main/4D%24.lua"
    local MIRROR = "https://cdn.jsdelivr.net/gh/yeyzcje-commits/4D-@main/4D%24.lua"

    local function fetch(url)
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and type(res) == "string" and #res > 100 then return res end
        ok, res = pcall(function() return game:HttpGet(url, true) end)
        if ok and type(res) == "string" and #res > 100 then return res end
        local fns = {}
        if request then fns[#fns + 1] = request end
        if http_request then fns[#fns + 1] = http_request end
        if syn and syn.request then fns[#fns + 1] = syn.request end
        if http and http.request then fns[#fns + 1] = http.request end
        if fluxus and fluxus.request then fns[#fns + 1] = fluxus.request end
        for _, fn in ipairs(fns) do
            local ok2, r = pcall(fn, { Url = url, Method = "GET" })
            if ok2 and type(r) == "table" and type(r.Body) == "string" and #r.Body > 100
                and (r.StatusCode == nil or r.StatusCode == 200) then
                return r.Body
            end
        end
        return nil
    end

    local src = fetch(URL) or fetch(MIRROR)
    if not src and isfile and readfile then
        local okF, has = pcall(isfile, "4D$.lua")
        if okF and has then
            local okR, body = pcall(readfile, "4D$.lua")
            if okR and type(body) == "string" then src = body end
        end
    end
    if src then
        local okL, lib = pcall(function() return loadstring(src)() end)
        if okL and lib then Lumen = lib end
    end
end
if not Lumen then
    warn("[4Money] Could not load the menu library (4D$). Check the internet connection / that your executor allows HTTP requests, "
        .. "or put 4D$.lua into the executor's workspace folder.")
    return
end

-- build stamp: if this line does not show up in the console, an OLD copy of the script is being run
print("[4Money] build 2026-11-22 r14 starting")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui -- not reachable on every executor: fall back to PlayerGui later
do
    local okCG, svc = pcall(game.GetService, game, "CoreGui")
    if okCG then CoreGui = svc end
end
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local okVim, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager")
if not okVim then VirtualInputManager = nil end

-- What this executor can do. Every feature that needs something missing here just stays inactive.
local Cap = { name = "unknown" }
do
    local okN, n = pcall(function()
        if identifyexecutor then return (identifyexecutor()) end
        if getexecutorname then return getexecutorname() end
        return nil
    end)
    if okN and n then Cap.name = tostring(n) end
    Cap.hook = (hookmetamethod ~= nil or (getrawmetatable ~= nil and (setreadonly ~= nil or make_writeable ~= nil)))
        and getnamecallmethod ~= nil
    Cap.getgc = getgc ~= nil
    Cap.upvals = ((debug and debug.getupvalues) ~= nil) or getupvalues ~= nil
    Cap.mouseRel = mousemoverel ~= nil
    Cap.click = mouse1click ~= nil
    Cap.vim = VirtualInputManager ~= nil
    Cap.conns = getconnections ~= nil
    Cap.files = writefile ~= nil and readfile ~= nil and isfolder ~= nil and makefolder ~= nil
    Cap.mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    Cap.summary = string.format("hook=%s getgc=%s upvalues=%s mousemoverel=%s mouse1click=%s virtualinput=%s files=%s mobile=%s",
        tostring(Cap.hook), tostring(Cap.getgc), tostring(Cap.upvals), tostring(Cap.mouseRel), tostring(Cap.click),
        tostring(Cap.vim), tostring(Cap.files), tostring(Cap.mobile))
    print("[4Money] executor: " .. Cap.name .. " | " .. Cap.summary)
end

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local State = {
    -- Combat
    NoRecoil = false,
    RecoilSuppression = 1.0, -- 1 = cancel the whole kick
    RecoilRecovery = true,
    RecoilSmooth = 0,        -- 0 = cancel instantly (smoothing lets part of the kick through)
    NoSpread = false,
    TransparentAimWeapon = false,
    AimWeaponTransparency = 0.75,

    -- Aim lock
    AimLock = false,
    AimTrigger = "Hold RMB",
    AimPart = "Head",
    AimFov = 150,
    ShowFov = true,
    AimFovColor = Color3.fromRGB(255, 255, 255),
    AimMethod = "Camera", -- exact: our own smoothed rotation is written to the camera each frame. "Mouse move" is experimental
    AimMouseGain = 1.0, -- raise if the aim is too slow to arrive, lower if it overshoots / shakes
    AimSmooth = 0.25,
    AimMaxStep = 6,
    AimMaxDistance = 500,
    AimWallCheck = true,

    -- Camera
    FovEnabled = false,
    FovValue = 90,
    ZoomEnabled = true,
    ZoomKey = "C",
    ZoomMode = "Hold",
    ZoomFov = 30,
    ZoomSpeed = 0.3,
    ZoomSensScale = true,    -- slow the mouse down while zoomed (otherwise zoom feels far too sharp)
    ZoomSensStrength = 1.0,  -- 1 = proportional to the FOV (zoom 30 of 70 = 43% sensitivity)

    -- Crosshair
    Crosshair = false,
    CrosshairColor = Color3.fromRGB(0, 255, 140),
    CrosshairSize = 8,
    CrosshairThickness = 2,
    CrosshairGap = 4,
    CenterDot = true,

    -- Player ESP
    PlayerBoxESP = false,
    PlayerFillESP = false,
    PlayerESPColor = Color3.fromRGB(255, 65, 65),
    PlayerFillTransparency = 0.65,
    PlayerMaxDistance = 450,
    PlayerShowHealth = true, -- HP bar + number next to the box
    PlayerShowTool = true,   -- item the player holds, under the box
    PlayerTracers = false,   -- line from the bottom of the screen to each box

    -- Hitmarker + arrows
    Hitmarker = true,
    HitSound = true,
    HitDamageText = true, -- "-23 HP  -15 ARMOR" under the crosshair
    OffscreenArrows = false,
    ArrowMaxDistance = 120,
    ArrowRadius = 190,

    -- Silent aim (turns the bullet rays toward the target; the camera does not move)
    SilentAim = false,
    SilentPart = "Head",
    SilentFov = 200,          -- px around the crosshair
    SilentMaxDistance = 500,
    SilentHitChance = 100,    -- % of shots that get turned
    SilentWallCheck = true,

    -- Triggerbot
    Triggerbot = false,
    TriggerDelay = 80,       -- ms the crosshair must stay on an enemy before the shot
    TriggerDistance = 400,

    -- Utility
    AntiAFK = true,
    DangerAlert = false,
    DangerRadius = 40,
    SmartPause = false,      -- pause auto cash / crowbar / allowance / bank at low health or while dead
    PauseHealth = 35,

    -- World ESP
    WorldOutline = true,
    WorldOutlineFill = 0.85,
    LootESP = false,
    OnlyAvailableLoot = false,
    LootESPColor = Color3.fromRGB(255, 200, 40),
    LootMaxDistance = 350,
    DoorESP = false,
    DoorESPColor = Color3.fromRGB(80, 190, 255),
    DoorMaxDistance = 250,
    VendorESP = false,
    VendorESPColor = Color3.fromRGB(130, 255, 120),
    VendorMaxDistance = 350,

    -- Lockpick
    AutoLockpick = false,
    LockpickDelay = 0.25,
    LockpickTolerance = 0.09,
    LockpickLatencyOffset = 0, -- ms added on top of one frame of click latency (can be negative)
    LockpickMaxFails = 4,
    LockpickStartDelay = 0.7, -- no press during the first moments of a minigame (the first click was getting wasted)
    LockpickKeyName = "Auto",
    LockpickMethod = "Auto",

    -- Money
    AutoCash = false,
    CashRadius = 8,
    AutoCrowbar = false,
    CrowbarRange = 12,
    AutoAllowance = false,
    AllowanceInterval = 5,
    AutoBank = false,
    BankInterval = 10,

    -- Character
    InfStamina = false,
    NoFall = false,
    AntiFlash = false,
    Fullbright = false,

    -- Misc
    OptimizerEnabled = false,
    Debug = false,
}

-- touch-only devices (Delta, Codex, Arceus ... on a phone) have no right mouse button
if Cap.mobile then State.AimTrigger = "Always" end

local isRunning = true
local conns = {}
local function track(c)
    conns[#conns + 1] = c
    return c
end

local function firstOf(v)
    if type(v) == "table" then return v[1] end
    return v
end

local function dbg(...)
    if State.Debug then print("[4Money]", ...) end
end

local function notify(title, content)
    pcall(function()
        Lumen:Notify({ Title = title, Content = content, Duration = 5, Type = "info" })
    end)
end

local function prettify(name)
    return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

---------------------------------------------------------------------
-- 1. GUI parent + overlay
---------------------------------------------------------------------
local function getGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok = pcall(function() return CoreGui:GetChildren() end)
    if ok then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end
local GuiParent = getGuiParent()

for _, name in ipairs({ "Money4Overlay", "Money4Highlights" }) do
    local old = GuiParent:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
end

local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "Money4Overlay"
OverlayGui.ResetOnSpawn = false
OverlayGui.IgnoreGuiInset = true
OverlayGui.DisplayOrder = 999
OverlayGui.Parent = GuiParent

local CenterRoot = Instance.new("Frame")
CenterRoot.Name = "CrosshairCenter"
CenterRoot.Size = UDim2.new(0, 0, 0, 0)
CenterRoot.Position = UDim2.new(0.5, 0, 0.5, 0)
CenterRoot.BackgroundTransparency = 1
CenterRoot.Visible = false
CenterRoot.Parent = OverlayGui

local BoxFolder = Instance.new("Folder")
BoxFolder.Name = "PlayerBoxes"
BoxFolder.Parent = OverlayGui

local WorldEspFolder = Instance.new("Folder")
WorldEspFolder.Name = "WorldEspLabels"
WorldEspFolder.Parent = OverlayGui

local HighlightFolder = Instance.new("Folder")
HighlightFolder.Name = "Money4Highlights"
HighlightFolder.Parent = GuiParent

local lines = {}
local function makeLine(name)
    local f = Instance.new("Frame")
    f.Name = name
    f.BackgroundColor3 = State.CrosshairColor
    f.BorderSizePixel = 0
    f.Parent = CenterRoot

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = f

    table.insert(lines, f)
    return f
end

local topLine = makeLine("Top")
local bottomLine = makeLine("Bottom")
local leftLine = makeLine("Left")
local rightLine = makeLine("Right")
local dotLine = makeLine("Dot")

local function updateCrosshairLayout()
    CenterRoot.Visible = State.Crosshair

    local sz = State.CrosshairSize
    local th = State.CrosshairThickness
    local gp = State.CrosshairGap
    local halfTh = th / 2

    topLine.Size = UDim2.new(0, th, 0, sz)
    topLine.Position = UDim2.new(0, -halfTh, 0, -(gp + sz))

    bottomLine.Size = UDim2.new(0, th, 0, sz)
    bottomLine.Position = UDim2.new(0, -halfTh, 0, gp)

    leftLine.Size = UDim2.new(0, sz, 0, th)
    leftLine.Position = UDim2.new(0, -(gp + sz), 0, -halfTh)

    rightLine.Size = UDim2.new(0, sz, 0, th)
    rightLine.Position = UDim2.new(0, gp, 0, -halfTh)

    dotLine.Visible = State.CenterDot
    dotLine.Size = UDim2.new(0, th, 0, th)
    dotLine.Position = UDim2.new(0, -halfTh, 0, -halfTh)

    for _, line in ipairs(lines) do
        line.BackgroundColor3 = State.CrosshairColor
    end
end

updateCrosshairLayout()

---------------------------------------------------------------------
-- 2. Time-sliced helpers + optimizer
---------------------------------------------------------------------
local function walkAsync(root, visit, isCancelled)
    task.spawn(function()
        local stack, n = { root }, 1
        local t0 = os.clock()
        while n > 0 do
            if isCancelled() then return end
            local inst = stack[n]
            stack[n] = nil
            n -= 1
            for _, kid in ipairs(inst:GetChildren()) do
                visit(kid)
                n += 1
                stack[n] = kid
            end
            if os.clock() - t0 > 0.002 then
                task.wait()
                t0 = os.clock()
            end
        end
    end)
end

local function eachChunked(list, fn, isCancelled)
    task.spawn(function()
        local t0 = os.clock()
        for i = 1, #list do
            if isCancelled and isCancelled() then return end
            pcall(fn, list[i])
            if os.clock() - t0 > 0.002 then
                task.wait()
                t0 = os.clock()
            end
        end
    end)
end

-- Same as walkAsync, but calls onDone() once the whole tree has been visited
local function walkAsyncDone(root, visit, isCancelled, onDone)
    task.spawn(function()
        local stack, n = { root }, 1
        local t0 = os.clock()
        while n > 0 do
            if isCancelled() then return end
            local inst = stack[n]
            stack[n] = nil
            n -= 1
            for _, kid in ipairs(inst:GetChildren()) do
                visit(kid)
                n += 1
                stack[n] = kid
            end
            if os.clock() - t0 > 0.002 then
                task.wait()
                t0 = os.clock()
            end
        end
        if onDone then onDone() end
    end)
end

local savedLightingShadows = nil
local savedEffects = {}
local savedShadowParts = {}
local savedEmitters = {}
local optimizerToken = 0
local optimizerConn = nil

local function isPostEffect(eff)
    return eff:IsA("BlurEffect") or eff:IsA("SunRaysEffect") or eff:IsA("BloomEffect") or eff:IsA("DepthOfFieldEffect")
end

local function applyOptimizer(enable)
    optimizerToken += 1
    local token = optimizerToken
    local function cancelled() return token ~= optimizerToken or not isRunning end

    if optimizerConn then
        optimizerConn:Disconnect()
        optimizerConn = nil
    end

    if enable then
        pcall(function()
            if savedLightingShadows == nil then savedLightingShadows = Lighting.GlobalShadows end
            Lighting.GlobalShadows = false
            for _, eff in ipairs(Lighting:GetChildren()) do
                if isPostEffect(eff) then
                    if savedEffects[eff] == nil then savedEffects[eff] = eff.Enabled end
                    eff.Enabled = false
                end
            end
        end)

        local function handle(obj)
            if obj:IsA("BasePart") then
                if obj.CastShadow then
                    savedShadowParts[obj] = true
                    obj.CastShadow = false
                end
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                if savedEmitters[obj] == nil then savedEmitters[obj] = obj.Enabled end
                obj.Enabled = false
            end
        end

        optimizerConn = workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                pcall(handle, obj)
            end
        end)
        walkAsync(workspace, function(obj) pcall(handle, obj) end, cancelled)
    else
        pcall(function()
            if savedLightingShadows ~= nil then
                Lighting.GlobalShadows = savedLightingShadows
                savedLightingShadows = nil
            end
            for eff, was in pairs(savedEffects) do
                if eff.Parent then eff.Enabled = was end
            end
            savedEffects = {}
        end)

        local parts, emitters = {}, {}
        for p in pairs(savedShadowParts) do parts[#parts + 1] = p end
        for e, was in pairs(savedEmitters) do emitters[#emitters + 1] = { e, was } end
        savedShadowParts = {}
        savedEmitters = {}

        eachChunked(parts, function(p)
            if p.Parent then p.CastShadow = true end
        end, function() return not isRunning end)
        eachChunked(emitters, function(pair)
            if pair[1].Parent then pair[1].Enabled = pair[2] end
        end, function() return not isRunning end)
    end
end

---------------------------------------------------------------------
-- 3. Player ESP
---------------------------------------------------------------------
local playerBoxPool = {}
local playerHighlights = {}

local function getOrCreateBox(player)
    if playerBoxPool[player] then
        return playerBoxPool[player]
    end

    local frame = Instance.new("Frame")
    frame.Name = player.Name .. "_Box"
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = BoxFolder

    local stroke = Instance.new("UIStroke")
    stroke.Color = State.PlayerESPColor
    stroke.Thickness = 1.6
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "Tag"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 60, 0, 16)
    label.Position = UDim2.new(0, -30, 0, -18)
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.2
    label.Parent = frame

    -- held item, under the box
    local toolLabel = Instance.new("TextLabel")
    toolLabel.Name = "Tool"
    toolLabel.BackgroundTransparency = 1
    toolLabel.Size = UDim2.new(1, 60, 0, 14)
    toolLabel.Position = UDim2.new(0, -30, 1, 2)
    toolLabel.Font = Enum.Font.Code
    toolLabel.TextSize = 11
    toolLabel.TextColor3 = Color3.fromRGB(255, 235, 140)
    toolLabel.TextStrokeTransparency = 0.2
    toolLabel.Parent = frame

    -- health bar, left of the box
    local bar = Instance.new("Frame")
    bar.Name = "HpBar"
    bar.BackgroundColor3 = Color3.new(0, 0, 0)
    bar.BackgroundTransparency = 0.45
    bar.BorderSizePixel = 0
    bar.Size = UDim2.new(0, 3, 1, 0)
    bar.Position = UDim2.new(0, -6, 0, 0)
    bar.Parent = frame
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BorderSizePixel = 0
    fill.BackgroundColor3 = Color3.fromRGB(60, 255, 90)
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Parent = bar

    -- tracer line (drawn as a rotated thin frame)
    local line = Instance.new("Frame")
    line.Name = player.Name .. "_Tracer"
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BorderSizePixel = 0
    line.BackgroundTransparency = 0.3
    line.BackgroundColor3 = State.PlayerESPColor
    line.Visible = false
    line.Parent = BoxFolder

    playerBoxPool[player] = {
        Frame = frame, Stroke = stroke, Label = label, LastDist = -1,
        ToolLabel = toolLabel, Bar = bar, Fill = fill, Line = line, LastText = "", LastTool = "",
    }
    return playerBoxPool[player]
end

local function removePlayerVisuals(player)
    local box = playerBoxPool[player]
    if box then
        if box.Line then box.Line:Destroy() end
        if box.Frame then box.Frame:Destroy() end
        playerBoxPool[player] = nil
    end
    local hl = playerHighlights[player]
    if hl then
        hl:Destroy()
        playerHighlights[player] = nil
    end
end

track(Players.PlayerRemoving:Connect(removePlayerVisuals))

local function getFullCharacterBox(character, hum, rootPos)
    local head = character:FindFirstChild("Head")
    local hipHeight = (hum and hum.RigType == Enum.HumanoidRigType.R15) and math.max(hum.HipHeight, 2.0) or 2.0

    local topY = head and (head.Position.Y + head.Size.Y * 0.65 + 0.25) or (rootPos.Y + hipHeight + 1.35)
    local bottomY = rootPos.Y - (hipHeight + 1.15)

    local topScreen, topVis = Camera:WorldToViewportPoint(Vector3.new(rootPos.X, topY, rootPos.Z))
    local botScreen, botVis = Camera:WorldToViewportPoint(Vector3.new(rootPos.X, bottomY, rootPos.Z))

    if topScreen.Z <= 0 or botScreen.Z <= 0 then return nil end
    if not topVis and not botVis then return nil end

    local height = math.abs(botScreen.Y - topScreen.Y)
    if height < 8 then return nil end

    local width = height * 0.56
    local midX = (topScreen.X + botScreen.X) * 0.5
    local minY = math.min(topScreen.Y, botScreen.Y)

    return midX - width * 0.5, minY, width, height
end

local playersWereVisible = false

local function updatePlayersESP()
    if not State.PlayerBoxESP and not State.PlayerFillESP then
        if playersWereVisible then
            playersWereVisible = false
            for _, box in pairs(playerBoxPool) do
                box.Frame.Visible = false
                box.Line.Visible = false
            end
            for _, hl in pairs(playerHighlights) do hl.Enabled = false end
        end
        return
    end
    playersWereVisible = true

    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local myPos = myRoot and myRoot.Position or Camera.CFrame.Position

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local alive = char and root and hum and hum.Health > 0

            local dist = alive and (root.Position - myPos).Magnitude or math.huge
            local inRange = alive and (dist <= State.PlayerMaxDistance)

            if State.PlayerFillESP and inRange then
                local hl = playerHighlights[plr]
                if not hl then
                    hl = Instance.new("Highlight")
                    hl.Name = plr.Name .. "_Fill"
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.OutlineTransparency = 1
                    hl.Parent = HighlightFolder
                    playerHighlights[plr] = hl
                end
                if hl.Adornee ~= char then hl.Adornee = char end
                if hl.FillColor ~= State.PlayerESPColor then hl.FillColor = State.PlayerESPColor end
                if hl.FillTransparency ~= State.PlayerFillTransparency then hl.FillTransparency = State.PlayerFillTransparency end
                if not hl.Enabled then hl.Enabled = true end
            elseif playerHighlights[plr] and playerHighlights[plr].Enabled then
                playerHighlights[plr].Enabled = false
            end

            local box = playerBoxPool[plr]
            if State.PlayerBoxESP and inRange then
                box = box or getOrCreateBox(plr)
                local x, y, w, h = getFullCharacterBox(char, hum, root.Position)
                if x then
                    box.Frame.Position = UDim2.fromOffset(x, y)
                    box.Frame.Size = UDim2.fromOffset(w, h)
                    if box.Stroke.Color ~= State.PlayerESPColor then box.Stroke.Color = State.PlayerESPColor end
                    local d = math.floor(dist)
                    local showHp = State.PlayerShowHealth
                    local txt = plr.DisplayName .. " [" .. d .. "m]"
                    if showHp then txt = txt .. " " .. math.ceil(hum.Health) .. "hp" end
                    if txt ~= box.LastText then
                        box.LastText = txt
                        box.Label.Text = txt
                    end

                    if box.Bar.Visible ~= showHp then box.Bar.Visible = showHp end
                    if showHp then
                        local f = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        box.Fill.Size = UDim2.new(1, 0, f, 0)
                        box.Fill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), f)
                    end

                    local tool = State.PlayerShowTool and char:FindFirstChildOfClass("Tool")
                    local tn = tool and tool.Name or ""
                    if tn ~= box.LastTool then
                        box.LastTool = tn
                        box.ToolLabel.Text = tn
                    end

                    if State.PlayerTracers then
                        local vp = Camera.ViewportSize
                        local ax, ay = vp.X * 0.5, vp.Y
                        local bx, by = x + w * 0.5, y + h
                        local ddx, ddy = bx - ax, by - ay
                        local line = box.Line
                        line.Size = UDim2.fromOffset(math.sqrt(ddx * ddx + ddy * ddy), 1.5)
                        line.Position = UDim2.fromOffset((ax + bx) * 0.5, (ay + by) * 0.5)
                        line.Rotation = math.deg(math.atan2(ddy, ddx))
                        line.BackgroundColor3 = State.PlayerESPColor
                        line.Visible = true
                    else
                        box.Line.Visible = false
                    end
                    box.Frame.Visible = true
                else
                    box.Frame.Visible = false
                    box.Line.Visible = false
                end
            elseif box and box.Frame.Visible then
                box.Frame.Visible = false
                box.Line.Visible = false
            end
        end
    end
end

---------------------------------------------------------------------
-- 4. World ESP (safes / registers / crates, doors, shops)
--    Uses the game's own folders (no map-wide scanning):
--      Map.BredMakurz  - lootables, each has Values.Broken (true = already opened)
--      Map.Doors       - doors
--      Map.Shopz       - shops / dealers
---------------------------------------------------------------------
local trackedWorld = {}

local function getGameFolder(name)
    local map = workspace:FindFirstChild("Map")
    local f = map and map:FindFirstChild(name)
    if f then return f end
    local filter = workspace:FindFirstChild("Filter")
    return filter and filter:FindFirstChild(name) or nil
end

local function anchorOf(obj)
    if obj:IsA("BasePart") then return obj end
    local main = obj:FindFirstChild("MainPart")
    if main and main:IsA("BasePart") then return main end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function findBroken(obj)
    local values = obj:FindFirstChild("Values")
    local b = values and values:FindFirstChild("Broken")
    if b and b:IsA("BoolValue") then return b end
    return nil
end

local function addEntry(obj, kind, title)
    if trackedWorld[obj] then return end
    local a = anchorOf(obj)
    if not a then return end
    trackedWorld[obj] = { Obj = obj, Kind = kind, Anchor = a, Title = title, Broken = findBroken(obj) }
end

local function syncWorld()
    if State.LootESP then
        local f = getGameFolder("BredMakurz")
        if f then
            for _, o in ipairs(f:GetChildren()) do
                if o:IsA("Model") or o:IsA("BasePart") then
                    addEntry(o, "Loot", prettify(o.Name))
                end
            end
        end
    end
    if State.DoorESP then
        local f = getGameFolder("Doors")
        if f then
            for _, o in ipairs(f:GetChildren()) do
                if o:IsA("Folder") then
                    for _, c in ipairs(o:GetChildren()) do addEntry(c, "Door", "Door") end
                elseif o:IsA("Model") or o:IsA("BasePart") then
                    addEntry(o, "Door", "Door")
                end
            end
        end
    end
    if State.VendorESP then
        local f = getGameFolder("Shopz")
        if f then
            for _, o in ipairs(f:GetChildren()) do
                if o:IsA("Model") or o:IsA("BasePart") then
                    addEntry(o, "Vendor", "Shop: " .. prettify(o.Name))
                end
            end
        end
    end
end

local function makeWorldLabel()
    local lbl = Instance.new("TextLabel")
    lbl.Name = "WorldTag"
    lbl.BackgroundTransparency = 0.35
    lbl.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
    lbl.Size = UDim2.fromOffset(170, 18)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.TextStrokeTransparency = 0.25
    lbl.Visible = false
    lbl.Parent = WorldEspFolder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = lbl

    return lbl
end

local activeWorld = {}
local activeN = 0
local WORLD_HIGHLIGHT_CAP = 22 -- player fill highlights share the same engine limit

-- Runs 4x per second: validates entries, distance, opened-state; builds the draw list
local function refreshWorldActive()
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local myPos = myRoot and myRoot.Position or Camera.CFrame.Position

    for i = 1, activeN do
        local e = activeWorld[i]
        if e.Label then e.Label.Visible = false end
        if e.Highlight then e.Highlight.Enabled = false end
        activeWorld[i] = nil
    end
    activeN = 0
    if not (State.LootESP or State.DoorESP or State.VendorESP) then return end

    for obj, entry in pairs(trackedWorld) do
        if not obj.Parent then
            if entry.Label then entry.Label:Destroy() end
            if entry.Highlight then entry.Highlight:Destroy() end
            trackedWorld[obj] = nil
        else
            if not entry.Anchor.Parent then
                local a = anchorOf(obj)
                if a then entry.Anchor = a end
            end
            local kind = entry.Kind
            local enabled, maxDist, col = false, 250, nil
            if kind == "Loot" then
                enabled, maxDist, col = State.LootESP, State.LootMaxDistance, State.LootESPColor
            elseif kind == "Door" then
                enabled, maxDist, col = State.DoorESP, State.DoorMaxDistance, State.DoorESPColor
            elseif kind == "Vendor" then
                enabled, maxDist, col = State.VendorESP, State.VendorMaxDistance, State.VendorESPColor
            end

            if enabled and entry.Anchor.Parent then
                local dist = (entry.Anchor.Position - myPos).Magnitude
                if dist <= maxDist then
                    local suffix = ""
                    if kind == "Loot" then
                        if not entry.Broken then entry.Broken = findBroken(obj) end
                        if entry.Broken and entry.Broken.Value then
                            if State.OnlyAvailableLoot then
                                enabled = false
                            else
                                suffix = " (opened)"
                            end
                        end
                    end
                    if enabled then
                        local lbl = entry.Label
                        if not lbl then
                            lbl = makeWorldLabel()
                            entry.Label = lbl
                        end
                        local shownColor = (suffix ~= "") and Color3.fromRGB(140, 140, 140) or col
                        lbl.TextColor3 = shownColor
                        lbl.Text = entry.Title .. suffix .. " [" .. math.floor(dist) .. "m]"
                        entry.Dist = dist
                        entry.Color = shownColor
                        activeN += 1
                        activeWorld[activeN] = entry
                    end
                end
            end
        end
    end

    -- Outlines: Roblox renders at most ~31 Highlights at once, so only the nearest ones get one
    if activeN > 1 then
        table.sort(activeWorld, function(a, b) return a.Dist < b.Dist end)
    end
    for i = 1, activeN do
        local e = activeWorld[i]
        if State.WorldOutline and i <= WORLD_HIGHLIGHT_CAP then
            local hl = e.Highlight
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "WorldOutline"
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = HighlightFolder
                e.Highlight = hl
            end
            if hl.Adornee ~= e.Obj then hl.Adornee = e.Obj end
            hl.OutlineColor = e.Color
            hl.FillColor = e.Color
            hl.OutlineTransparency = 0
            hl.FillTransparency = State.WorldOutlineFill
            hl.Enabled = true
        elseif e.Highlight then
            e.Highlight.Enabled = false
        end
    end
end

local function drawWorldESP()
    for i = 1, activeN do
        local e = activeWorld[i]
        local lbl = e.Label
        local sp, onScreen = Camera:WorldToViewportPoint(e.Anchor.Position + Vector3.new(0, 1.3, 0))
        if onScreen and sp.Z > 0 then
            lbl.Position = UDim2.fromOffset(sp.X - 85, sp.Y - 9)
            if not lbl.Visible then lbl.Visible = true end
        elseif lbl.Visible then
            lbl.Visible = false
        end
    end
end

---------------------------------------------------------------------
-- 5. Input, anti-recoil, weapon transparency
---------------------------------------------------------------------
local isShooting = false
local isAiming = false

-- Life state: while the player is dead (and for a moment after respawn) the game rebuilds the camera,
-- FOV and movement scripts. We must not write to any of them then, and our own state is reset.
local Life = { start = os.clock() }
function Life.alive()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end
function Life.settled(delay)
    return Life.alive() and os.clock() - Life.start > (delay or 1.5)
end

-- Our own raycasts. Called as a plain function (not workspace:Raycast) so they never pass through the
-- __namecall hook (silent aim) - this works even where checkcaller() does not exist.
function Life.ray(origin, dir, params)
    local ok, res = pcall(workspace.Raycast, workspace, origin, dir, params)
    if ok then return res end
    return nil
end

-- mouse sensitivity scaling for zoom (Roblox does not slow the camera down when the FOV shrinks)
function Life.setSens(f)
    Life.sensF = f >= 0.999 and 1 or f
    if f >= 0.999 then
        if Life.sensOrig then
            UserInputService.MouseDeltaSensitivity = Life.sensOrig
            Life.sensOrig = nil
        end
    else
        if not Life.sensOrig then Life.sensOrig = UserInputService.MouseDeltaSensitivity end
        UserInputService.MouseDeltaSensitivity = Life.sensOrig * f
    end
end

function Life.zoomSens(fov, ref)
    if not State.ZoomSensScale or ref <= 0 then
        Life.setSens(1)
        return
    end
    Life.setSens(1 - State.ZoomSensStrength * (1 - math.min(1, fov / ref)))
end
track(LocalPlayer.CharacterAdded:Connect(function()
    Life.start = os.clock()
    isShooting = false
    isAiming = false
end))

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isShooting = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = true
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isShooting = false
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = false
    end
end))

local function hasWeaponEquipped()
    local char = LocalPlayer.Character
    return char ~= nil and char:FindFirstChildOfClass("Tool") ~= nil
end

local function isFirstPerson()
    local char = LocalPlayer.Character
    local head = char and char:FindFirstChild("Head")
    if not head or not Camera then return false end
    return (Camera.CFrame.Position - head.Position).Magnitude < 1.6
end

local originalTransparencies = setmetatable({}, { __mode = "k" })

local function applyWeaponTransparency(container, targetVal)
    if not container then return end
    for _, inst in ipairs(container:GetDescendants()) do
        if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
            if originalTransparencies[inst] == nil then
                originalTransparencies[inst] = inst.Transparency
            end
            local orig = originalTransparencies[inst]
            if orig < 1 then
                local want = math.max(orig, targetVal)
                if inst.Transparency ~= want then inst.Transparency = want end
            end
        end
    end
end

local function restoreWeaponTransparency()
    for inst, orig in pairs(originalTransparencies) do
        if inst and inst.Parent then
            pcall(function() inst.Transparency = orig end)
        end
        originalTransparencies[inst] = nil
    end
end

local weaponFaded = false
local lastWeaponUpdate = 0

local function updateFirstPersonAimWeapon()
    local shouldFade = State.TransparentAimWeapon and isAiming and isFirstPerson()
    if shouldFade then
        local now = os.clock()
        if now - lastWeaponUpdate < 0.15 then return end
        lastWeaponUpdate = now
        weaponFaded = true

        local val = State.AimWeaponTransparency
        local char = LocalPlayer.Character
        applyWeaponTransparency(char and char:FindFirstChildOfClass("Tool"), val)
        for _, child in ipairs(Camera:GetChildren()) do
            if child:IsA("Model") or child:IsA("Tool") then
                applyWeaponTransparency(child, val)
            end
        end
    elseif weaponFaded then
        weaponFaded = false
        restoreWeaponTransparency()
    end
end

-- Anti-recoil: cancels camera kick on both axes. Whatever we remove ("owed") is only
-- given back during the game's own recovery, so the aim never drifts.
local lastPitch, lastYaw = 0, 0
local aimEngaged = false -- set by the aim lock; anti-recoil stays out of the way while true
local hasPrevAngles = false
local pitchOwed, yawOwed = 0, 0
local lastShotTime = 0
local baseOffsetY = nil

local function wrapAngle(a)
    return math.atan2(math.sin(a), math.cos(a))
end

-- Smoothing: corrections are not applied in one frame. They go into a buffer (pendP / pendY)
-- that is drained with an exponential filter, so the camera never "snaps".
-- RecoilSmooth: 0 = instant (old behaviour), higher = softer and slightly later.
local pendP, pendY = 0, 0

local function stepAntiRecoil(dt)
    if not isRunning then return end
    Camera = workspace.CurrentCamera
    if not Camera then return end
    dt = dt or (1 / 60)

    if not Life.settled() then
        -- dead / just respawned: drop every bit of recoil state and leave the camera alone
        if not Life.alive() then
            isShooting = false
            isAiming = false
        end
        hasPrevAngles = false
        pitchOwed, yawOwed = 0, 0
        pendP, pendY = 0, 0
        baseOffsetY = nil
        lastShotTime = 0
        return
    end

    local now = os.clock()
    local active = State.NoRecoil and isShooting and hasWeaponEquipped()
    if active then lastShotTime = now end

    local smooth = math.clamp(State.RecoilSmooth, 0, 0.95)
    local alpha = (smooth <= 0) and 1 or (1 - smooth ^ (dt * 60))

    -- Humanoid.CameraOffset kick (eased toward the remembered baseline, never below it)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local off = hum.CameraOffset
        if active then
            if baseOffsetY and off.Y > baseOffsetY + 0.01 then
                local target = baseOffsetY + (off.Y - baseOffsetY) * (1 - State.RecoilSuppression)
                hum.CameraOffset = Vector3.new(off.X, off.Y + (target - off.Y) * alpha, off.Z)
            end
        elseif now - lastShotTime > 1 then
            baseOffsetY = off.Y
        end
    end

    local cf = Camera.CFrame
    local pitch, yaw, roll = cf:ToEulerAnglesYXZ()

    if not hasPrevAngles then
        lastPitch, lastYaw = pitch, yaw
        hasPrevAngles = true
        return
    end

    if aimEngaged then
        lastPitch, lastYaw = pitch, yaw
        pitchOwed, yawOwed = 0, 0
        pendP, pendY = 0, 0
        return
    end

    if State.NoRecoil then
        local md = UserInputService:GetMouseDelta()
        local recent = active or now - lastShotTime < 0.8

        -- Radians the camera turns per mouse pixel, learned while you are NOT shooting. While shooting it is
        -- used to take YOUR mouse movement out of the camera delta, so only the weapon's kick is cancelled
        -- (before, any mouse movement at all switched the correction off - that is why recoil came back).
        if not active and math.abs(md.Y) >= 3 then
            local k = -(pitch - lastPitch) / md.Y
            if k > 0 then Life.k = math.clamp((Life.k or 0.004) + (k - (Life.k or 0.004)) * 0.1, 0.0002, 0.012) end
        end
        local kEst = Life.k or 0.004

        -- vertical: what to remove goes into the buffer (md.Y > 0 = mouse down = pitch goes down)
        local d = pitch - lastPitch + md.Y * kEst
        if active and d > 0.0002 then
            local sub = d * State.RecoilSuppression
            pitchOwed = math.min(pitchOwed + sub, 0.12)
            pendP -= sub
        elseif State.RecoilRecovery and pitchOwed > 0 and d < -0.0002 and recent then
            local add = math.min(-d * State.RecoilSuppression, pitchOwed)
            pitchOwed -= add
            pendP += add
        end

        -- horizontal
        local dy = wrapAngle(yaw - lastYaw) + md.X * kEst -- md.X > 0 = mouse right = yaw goes down
        if active and math.abs(dy) > 0.0002 then
            local sub = dy * State.RecoilSuppression
            yawOwed = math.clamp(yawOwed + sub, -0.15, 0.15)
            pendY -= sub
        elseif State.RecoilRecovery and yawOwed ~= 0 and dy * yawOwed < 0 and math.abs(dy) > 0.0002 and recent then
            local amount = math.min(math.abs(dy) * State.RecoilSuppression, math.abs(yawOwed))
            local sgn = yawOwed > 0 and 1 or -1
            yawOwed -= sgn * amount
            pendY += sgn * amount
        end

        if not recent then
            pitchOwed = 0
            yawOwed = 0
        end
    else
        pitchOwed, yawOwed = 0, 0
        pendP, pendY = 0, 0
    end

    -- drain the buffer with the smoothing filter
    local ap = (math.abs(pendP) < 1e-5) and pendP or pendP * alpha
    local ay = (math.abs(pendY) < 1e-5) and pendY or pendY * alpha
    if ap ~= 0 or ay ~= 0 then
        pendP -= ap
        pendY -= ay
        pitch = math.clamp(pitch + ap, -1.5, 1.5)
        yaw = yaw + ay
        Camera.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
    end

    lastPitch, lastYaw = pitch, yaw
end

pcall(function()
    RunService:UnbindFromRenderStep("Money4_LateRecoil")
end)
RunService:BindToRenderStep("Money4_LateRecoil", Enum.RenderPriority.Camera.Value + 5, stepAntiRecoil)

---------------------------------------------------------------------
-- 5b. Aim lock (FOV circle around the screen center)
--     Picks the player closest to the crosshair inside the FOV, optional wall check,
--     smooth camera turn (Smoothness 1.0 = instant snap).
---------------------------------------------------------------------
local FovCircle = Instance.new("Frame")
FovCircle.Name = "AimFov"
FovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
FovCircle.BackgroundTransparency = 1
FovCircle.BorderSizePixel = 0
FovCircle.Visible = false
FovCircle.Parent = OverlayGui

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = FovCircle

local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 1.5
fovStroke.Color = State.AimFovColor
fovStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fovStroke.Parent = FovCircle

local function updateFovCircle()
    FovCircle.Visible = (State.AimLock or State.SilentAim) and State.ShowFov
    local r = State.AimLock and State.AimFov or State.SilentFov
    FovCircle.Size = UDim2.fromOffset(r * 2, r * 2)
    fovStroke.Color = State.AimFovColor
end
updateFovCircle()

local aimRayParams = RaycastParams.new()
aimRayParams.FilterType = Enum.RaycastFilterType.Exclude
local aimTarget = nil
-- mouse-move aim method: sub-pixel remainder, learned radians-per-pixel (kx / ky), last command
local AIMM = {
    rx = 0, ry = 0, kx = 0.004, ky = 0.004,
    pendY = 0, pendP = 0,        -- commanded rotation (rad) the camera has not shown yet
    accSx = 0, accSy = 0, accOy = 0, accOp = 0, wt = 0, -- learning window
    pcy = nil, pcp = 0, sf = nil,
    camCF = nil,                 -- own smoothed rotation for the Camera method
}

local function getAimPart(char)
    if State.AimPart == "Head" then
        return char:FindFirstChild("Head")
    end
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
end

local function hasLineOfSight(part, char)
    local filter = { char, Camera }
    if LocalPlayer.Character then filter[#filter + 1] = LocalPlayer.Character end
    aimRayParams.FilterDescendantsInstances = filter
    local origin = Camera.CFrame.Position
    return Life.ray(origin, part.Position - origin, aimRayParams) == nil
end

local function aimCandidateOk(char, part, myPos, center, fovLimit)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or not part.Parent then return nil end
    if (part.Position - myPos).Magnitude > State.AimMaxDistance then return nil end
    local sp, on = Camera:WorldToViewportPoint(part.Position)
    if not on or sp.Z <= 0 then return nil end
    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
    if d > fovLimit then return nil end
    return d
end

local function acquireAimTarget(myPos, center)
    local candidates = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local char = plr.Character
            local part = getAimPart(char)
            if part then
                local d = aimCandidateOk(char, part, myPos, center, State.AimFov)
                if d then candidates[#candidates + 1] = { char = char, part = part, d = d } end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#candidates, 4) do
        local c = candidates[i]
        if not State.AimWallCheck or hasLineOfSight(c.part, c.char) then
            return c
        end
    end
    return nil
end

local function aimKeyActive()
    local m = State.AimTrigger
    if m == "Always" then return true end
    if m == "Hold LMB" then return isShooting end
    return isAiming
end

local function stepAimLock(dt)
    local wasEngaged = aimEngaged
    aimEngaged = false
    if not wasEngaged then
        -- starting a new lock: forget everything that belonged to the previous one
        AIMM.pcy = nil
        AIMM.pendY, AIMM.pendP = 0, 0
        AIMM.accSx, AIMM.accSy, AIMM.accOy, AIMM.accOp, AIMM.wt = 0, 0, 0, 0, os.clock()
        AIMM.rx, AIMM.ry = 0, 0
        AIMM.camCF = nil
    end
    if not isRunning or not State.AimLock then
        aimTarget = nil
        return
    end
    Camera = workspace.CurrentCamera
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not Camera or not hum or hum.Health <= 0 or not Life.settled() or not aimKeyActive() then
        aimTarget = nil
        return
    end

    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local root = char:FindFirstChild("HumanoidRootPart")
    local myPos = root and root.Position or Camera.CFrame.Position

    -- keep the current target while it stays valid (slightly larger FOV so it does not flicker)
    if aimTarget then
        local t = aimTarget
        local ok = t.char.Parent and aimCandidateOk(t.char, t.part, myPos, center, State.AimFov * 1.25)
        if not ok or (State.AimWallCheck and not hasLineOfSight(t.part, t.char)) then
            aimTarget = nil
        end
    end
    if not aimTarget then
        aimTarget = acquireAimTarget(myPos, center)
    end
    if not aimTarget then return end

    -- Mouse-move method: push the real mouse toward the target; the game's own camera turns, so there is
    -- no per-frame fight with its camera script. Remainders are carried so slow moves are not lost.
    if State.AimMethod == "Mouse move" and mousemoverel then
        local free = UserInputService.MouseBehavior == Enum.MouseBehavior.Default and not isAiming
        if not free and not UserInputService:GetFocusedTextBox() then
            -- Work in ANGLES, not pixels: how many radians one mouse pixel turns the camera depends on the
            -- game's sensitivity and on the zoom, so it is measured. The game applies mouse input with a delay
            -- (its own smoothing), so commands that are still "in flight" are remembered and subtracted from
            -- the error; without that the aim overshoots and swings away.
            local cf = Camera.CFrame
            local cp, cy = cf:ToEulerAnglesYXZ() -- pitch, yaw
            local nowT = os.clock()

            -- the zoom changes the mouse sensitivity: rescale the learned radians-per-pixel at once
            local sf = Life.sensF or 1
            if AIMM.sf and AIMM.sf ~= sf then
                local r = sf / AIMM.sf
                AIMM.kx = math.clamp(AIMM.kx * r, 0.0002, 0.012)
                AIMM.ky = math.clamp(AIMM.ky * r, 0.0002, 0.012)
            end
            AIMM.sf = sf

            -- what the camera did since the last frame: reduces what is still in flight
            if AIMM.pcy then
                local oy, op = wrapAngle(cy - AIMM.pcy), cp - AIMM.pcp
                AIMM.accOy += oy
                AIMM.accOp += op
                local leak = 0.5 ^ (dt / 0.15)
                local ny, np = AIMM.pendY - oy, AIMM.pendP - op
                if AIMM.pendY > 0 then ny = math.max(ny, 0) elseif AIMM.pendY < 0 then ny = math.min(ny, 0) end
                if AIMM.pendP > 0 then np = math.max(np, 0) elseif AIMM.pendP < 0 then np = math.min(np, 0) end
                AIMM.pendY, AIMM.pendP = ny * leak, np * leak
            end
            AIMM.pcy, AIMM.pcp = cy, cp

            -- learn radians-per-pixel over a 0.3 s window (robust against the input delay)
            if nowT - AIMM.wt >= 0.3 then
                if math.abs(AIMM.accSx) >= 15 then
                    local k = -AIMM.accOy / AIMM.accSx
                    if k > 0 then AIMM.kx = math.clamp(AIMM.kx + (k - AIMM.kx) * 0.5, 0.0002, 0.012) end
                end
                if math.abs(AIMM.accSy) >= 15 then
                    local k = -AIMM.accOp / AIMM.accSy
                    if k > 0 then AIMM.ky = math.clamp(AIMM.ky + (k - AIMM.ky) * 0.5, 0.0002, 0.012) end
                end
                AIMM.accSx, AIMM.accSy, AIMM.accOy, AIMM.accOp, AIMM.wt = 0, 0, 0, 0, nowT
            end

            local dir = aimTarget.part.Position - cf.Position
            if dir.Magnitude > 0.01 then
                dir = dir.Unit
                local ey = wrapAngle(math.atan2(-dir.X, -dir.Z) - cy)     -- yaw error
                local ep = math.asin(math.clamp(dir.Y, -1, 1)) - cp        -- pitch error
                -- error that is NOT already covered by commands in flight (never flips sign)
                local effY = (ey >= 0) and math.max(ey - math.max(AIMM.pendY, 0), 0) or math.min(ey - math.min(AIMM.pendY, 0), 0)
                local effP = (ep >= 0) and math.max(ep - math.max(AIMM.pendP, 0), 0) or math.min(ep - math.min(AIMM.pendP, 0), 0)
                local s = math.clamp(State.AimSmooth, 0.02, 1)
                local alpha = (s >= 1) and 1 or (1 - (1 - s) ^ (dt * 60))
                local cmdY, cmdP = effY * alpha * State.AimMouseGain, effP * alpha * State.AimMouseGain
                if State.AimMaxStep > 0 then
                    local maxA = math.rad(State.AimMaxStep) * dt * 60
                    local mag = math.sqrt(cmdY * cmdY + cmdP * cmdP)
                    if mag > maxA then
                        cmdY, cmdP = cmdY * maxA / mag, cmdP * maxA / mag
                    end
                end
                if State.Debug and nowT - (AIMM.dbgT or 0) > 0.5 then
                    AIMM.dbgT = nowT
                    dbg(string.format("aim(mouse): err yaw=%.2fdeg pitch=%.2fdeg | k=%.3f/%.3f deg per px | pending %.2f/%.2fdeg",
                        math.deg(ey), math.deg(ep), math.deg(AIMM.kx), math.deg(AIMM.ky), math.deg(AIMM.pendY), math.deg(AIMM.pendP)))
                end
                -- positive mouse X turns right (yaw decreases), positive mouse Y looks down (pitch decreases)
                AIMM.rx += -cmdY / AIMM.kx
                AIMM.ry += -cmdP / AIMM.ky
                local ix = AIMM.rx >= 0 and math.floor(AIMM.rx) or math.ceil(AIMM.rx)
                local iy = AIMM.ry >= 0 and math.floor(AIMM.ry) or math.ceil(AIMM.ry)
                ix, iy = math.clamp(ix, -300, 300), math.clamp(iy, -300, 300)
                AIMM.rx -= ix
                AIMM.ry -= iy
                if ix ~= 0 or iy ~= 0 then
                    pcall(mousemoverel, ix, iy)
                    AIMM.accSx += ix
                    AIMM.accSy += iy
                    AIMM.pendY += -ix * AIMM.kx
                    AIMM.pendP += -iy * AIMM.ky
                end
            end
        end
        local p0, y0 = Camera.CFrame:ToEulerAnglesYXZ()
        lastPitch, lastYaw = p0, y0
        aimEngaged = true
        return
    end

    -- Camera method: the game rewrites the camera every frame from its own angles, so smoothing from the
    -- game's CFrame never arrives. Keep our OWN rotation, move it toward the target and write it each frame.
    local pos = Camera.CFrame.Position
    local cur = (wasEngaged and AIMM.camCF) and (CFrame.new(pos) * AIMM.camCF.Rotation) or Camera.CFrame
    local want = CFrame.lookAt(cur.Position, aimTarget.part.Position)
    local s = math.clamp(State.AimSmooth, 0.02, 1)
    local alpha = (s >= 1) and 1 or (1 - (1 - s) ^ (dt * 60))
    -- optional speed cap so a far target never makes the camera whip around
    if State.AimMaxStep > 0 then
        local angle = math.acos(math.clamp(cur.LookVector:Dot(want.LookVector), -1, 1))
        local maxRad = math.rad(State.AimMaxStep) * dt * 60
        if angle > 1e-4 and angle * alpha > maxRad then
            alpha = maxRad / angle
        end
    end
    Camera.CFrame = cur:Lerp(want, alpha)
    AIMM.camCF = Camera.CFrame

    -- tell anti-recoil where the camera is now so it never treats our turn as recoil
    local p, y = Camera.CFrame:ToEulerAnglesYXZ()
    lastPitch, lastYaw = p, y
    aimEngaged = true
end

pcall(function()
    RunService:UnbindFromRenderStep("Money4_Aim")
end)
RunService:BindToRenderStep("Money4_Aim", Enum.RenderPriority.Camera.Value + 10, stepAimLock)

---------------------------------------------------------------------
-- 5c. Field of view + key-bound camera zoom
--     Custom FOV slider, and a key that zooms the camera in (hold or toggle),
--     eased with an exponential filter. The game's own FOV is restored when everything is off.
---------------------------------------------------------------------
local zoomKeybind = nil -- the Lumen keybind control (assigned in the UI section)
local zoomActive = false
local fovOverriding = false
local baseFov = 70
local fovNow = 70

local function currentZoomKey()
    if zoomKeybind and type(zoomKeybind) == "table" and zoomKeybind.CurrentKeybind then
        return zoomKeybind.CurrentKeybind
    end
    return State.ZoomKey
end

track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not State.ZoomEnabled then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode.Name ~= currentZoomKey() then return end
    if State.ZoomMode == "Toggle" then
        zoomActive = not zoomActive
    else
        zoomActive = true
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if State.ZoomMode ~= "Toggle" and input.KeyCode.Name == currentZoomKey() then
        zoomActive = false
    end
end))

local function stepFov(dt)
    if not isRunning then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    Camera = cam
    dt = dt or (1 / 60)

    if not Life.alive() then
        -- dead: hand the FOV back to the game once and stop touching it
        zoomActive = false
        Life.setSens(1)
        if fovOverriding then
            fovOverriding = false
            cam.FieldOfView = baseFov
        end
        return
    end

    if not State.ZoomEnabled then zoomActive = false end

    local wantZoom = State.ZoomEnabled and zoomActive
    local target = nil
    if wantZoom then
        target = State.ZoomFov
    elseif State.FovEnabled then
        target = State.FovValue
    end

    if target == nil then
        -- nothing to override: ease back to the game's FOV, then let go of the camera
        if not fovOverriding then return end
        target = baseFov
        local s = math.clamp(State.ZoomSpeed, 0.05, 1)
        local alpha = (s >= 1) and 1 or (1 - (1 - s) ^ (dt * 60))
        fovNow = fovNow + (target - fovNow) * alpha
        cam.FieldOfView = fovNow
        Life.zoomSens(fovNow, baseFov)
        if math.abs(fovNow - baseFov) < 0.05 then
            cam.FieldOfView = baseFov
            fovOverriding = false
            Life.setSens(1)
        end
        return
    end

    if not fovOverriding then
        fovOverriding = true
        baseFov = cam.FieldOfView
        fovNow = baseFov
    end

    local s = math.clamp(State.ZoomSpeed, 0.05, 1)
    local alpha = (s >= 1) and 1 or (1 - (1 - s) ^ (dt * 60))
    fovNow = fovNow + (target - fovNow) * alpha
    cam.FieldOfView = fovNow
    -- slower mouse while zoomed in (relative to the normal / custom FOV)
    Life.zoomSens(fovNow, State.FovEnabled and State.FovValue or baseFov)
end

pcall(function()
    RunService:UnbindFromRenderStep("Money4_Fov")
end)
RunService:BindToRenderStep("Money4_Fov", Enum.RenderPriority.Camera.Value + 12, stepFov)

---------------------------------------------------------------------
-- 6. Auto lockpick
--    PlayerGui.LockpickGUI.MF.LP_Frame.Line          - static horizontal line
--    PlayerGui.LockpickGUI.MF.LP_Frame.Frames.B1..B3 - holders; each has a moving "Bar"
--    PlayerGui.LockpickGUI.MF.Base.Instructions      - hint text
--    The input method self-calibrates: after each press we check that the bar stopped.
---------------------------------------------------------------------
local function keyCodeFor(name)
    if name == "Space" then return Enum.KeyCode.Space end
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    if ok and kc then return kc end
    return Enum.KeyCode.E
end

local function vkFor(name)
    if name == "Space" then return 0x20 end
    if #name == 1 then return string.byte(string.upper(name)) end
    return 0x45
end

local function sendViaVIM(keyName)
    if not VirtualInputManager then return false end
    local ok = pcall(function()
        if keyName == "Mouse1" then
            local vp = Camera.ViewportSize
            VirtualInputManager:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0)
        else
            local kc = keyCodeFor(keyName)
            VirtualInputManager:SendKeyEvent(true, kc, false, game)
            task.wait(0.02)
            VirtualInputManager:SendKeyEvent(false, kc, false, game)
        end
    end)
    return ok
end

local function sendNative(keyName)
    if keyName == "Mouse1" then
        if mouse1click then return pcall(mouse1click) end
        return false
    end
    if keypress and keyrelease then
        return pcall(function()
            keypress(vkFor(keyName))
            task.wait(0.02)
            keyrelease(vkFor(keyName))
        end)
    end
    return false
end

-- The GUI has a MobileButton (hidden on PC). Call its handler directly.
local function pressMobileButton(gui)
    local btn = gui and gui:FindFirstChild("MobileButton", true)
    if not btn then return false end
    if getconnections then
        for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated, btn.MouseButton1Down }) do
            local ok, cs = pcall(getconnections, sig)
            if ok and cs and #cs > 0 then
                for _, c in ipairs(cs) do pcall(function() c:Fire() end) end
                return true
            end
        end
    end
    if firesignal then
        return pcall(firesignal, btn.MouseButton1Click)
    end
    return false
end

-- Real mouse click on a GUI element (moves the virtual cursor onto it, presses, releases).
-- A hidden element (e.g. MobileButton on PC) is made visible for the duration of the click.
local function guiTarget(gui, targetName)
    local el = gui and gui:FindFirstChild(targetName, true)
    if el and el:IsA("GuiObject") then return el end
    return nil
end

local function guiPoint(el)
    return el.AbsolutePosition + el.AbsoluteSize * 0.5 + GuiService:GetGuiInset()
end

-- Hover the virtual cursor over the target BEFORE the timing window, so the real click
-- needs no extra mouse move (that move + waits is what made presses land late).
local function placeCursor(gui, targetName)
    if not VirtualInputManager then return end
    local el = guiTarget(gui, targetName)
    if not el then return end
    local pos = guiPoint(el)
    pcall(function() VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, game) end)
end

-- The button goes down immediately (no waiting before the press); only the release waits.
local function guiClick(gui, targetName)
    if not VirtualInputManager then return false end
    local el = guiTarget(gui, targetName)
    if not el then return false end

    local wasHidden = not el.Visible
    if wasHidden then el.Visible = true end

    local pos = guiPoint(el)
    -- a click that lands outside the screen goes nowhere: let the caller use another way
    local vp = Camera.ViewportSize
    if pos.X < 0 or pos.Y < 0 or pos.X > vp.X or pos.Y > vp.Y then
        if wasHidden and el.Parent then el.Visible = false end
        return false
    end
    -- move onto the button right before pressing so the very first click has a proper hover
    pcall(function() VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, game) end)
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
    end)
    task.wait(0.02)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
    end)

    if wasHidden and el.Parent then el.Visible = false end
    return ok
end

-- "Auto": read the hint text inside the minigame, fall back to E
local function resolveLockpickKey(instructionText)
    local chosen = State.LockpickKeyName
    if chosen ~= "Auto" then return chosen end
    local t = string.upper(instructionText or "")
    if string.find(t, "SPACE", 1, true) then return "Space" end
    if string.find(t, "CLICK", 1, true) or string.find(t, "MOUSE", 1, true) then return "Mouse1" end
    local letter = string.match(t, "PRESS%s+%[?(%a)%]?%f[%A]") or string.match(t, "%[(%a)%]")
    if letter then return letter end
    return "E"
end

local cal = { sig = "", methods = {}, idx = 1, fails = 0, rotations = 0, good = false }

local function buildMethods(resolvedKey)
    local list, seen = {}, {}
    local function add(kind, key)
        local id = kind .. ":" .. key
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = { kind = kind, key = key }
        end
    end
    local userKey, userMethod = State.LockpickKeyName, State.LockpickMethod
    if userMethod == "GUI click" then
        add("gui", "MobileButton")
        add("gui", "LP_Frame")
    elseif userMethod == "VirtualInput" then
        add("vim", resolvedKey)
    elseif userMethod == "keypress/mouse1click" then
        add("native", resolvedKey)
    elseif userMethod == "MobileButton" then
        add("button", "-")
    else
        -- Auto: real GUI click first, then signal / key fallbacks
        add("gui", "MobileButton")
        add("button", "-")
        add("gui", "LP_Frame")
        add("vim", resolvedKey)
        if userKey == "Auto" then
            add("vim", "E")
            add("vim", "Space")
            add("vim", "F")
            add("vim", "Mouse1")
        end
        add("native", resolvedKey)
        if userKey == "Auto" then add("native", "Mouse1") end
    end
    return list
end

local function describeMethod(m)
    return m.kind .. ":" .. m.key
end

local lastActionTime = 0

local function ensureCal(resolvedKey)
    local sig = State.LockpickKeyName .. "|" .. State.LockpickMethod .. "|" .. resolvedKey
    if cal.sig ~= sig then
        cal.sig = sig
        cal.methods = buildMethods(resolvedKey)
        cal.idx = 1
        cal.fails = 0
        cal.rotations = 0
        cal.good = false
    end
    return cal.methods[cal.idx] or cal.methods[1]
end

local function triggerLockpickAction(gui, resolvedKey)
    local now = os.clock()
    if now - lastActionTime < State.LockpickDelay then
        return nil
    end
    lastActionTime = now

    local m = ensureCal(resolvedKey)
    if not m then return nil end

    task.spawn(function()
        if m.kind == "gui" then
            if not guiClick(gui, m.key) then pressMobileButton(gui) end
        elseif m.kind == "vim" then
            sendViaVIM(m.key)
        elseif m.kind == "native" then
            sendNative(m.key)
        else
            pressMobileButton(gui)
        end
    end)
    return m
end

local function onLockResult(p, ok)
    if p.m ~= cal.methods[cal.idx] then return end -- result of an outdated method
    if ok then
        if not cal.good then
            cal.good = true
            print("[4Money] Lockpick input confirmed: " .. describeMethod(p.m))
        end
        cal.fails = 0
    else
        -- A late or early press says nothing about the input method: only presses whose
        -- timing was good count against it. Once a method is confirmed it is never swapped,
        -- and the auto-search goes through each method at most once (swapping burns picks).
        if not p.timingOk or cal.good then return end
        cal.fails += 1
        if cal.fails >= 3 and #cal.methods > 1 and cal.rotations < #cal.methods - 1 then
            cal.idx = cal.idx % #cal.methods + 1
            cal.rotations += 1
            cal.fails = 0
            print("[4Money] Lockpick press had no effect, trying: " .. describeMethod(cal.methods[cal.idx]))
        end
    end
end

local function dumpGui(root)
    local out = { "=== LOCKPICK GUI DUMP: " .. root:GetFullName() .. " ===" }
    local count = 0
    local function add(o, depth)
        if count >= 300 then return end
        count += 1
        local line = string.rep("  ", depth) .. o.ClassName .. " '" .. o.Name .. "'"
        if o:IsA("GuiObject") then
            line = line .. string.format(" vis=%s pos=(%d,%d) size=(%d,%d)",
                tostring(o.Visible), o.AbsolutePosition.X, o.AbsolutePosition.Y,
                o.AbsoluteSize.X, o.AbsoluteSize.Y)
            if o:IsA("TextLabel") or o:IsA("TextButton") then line = line .. " text='" .. o.Text .. "'" end
        end
        out[#out + 1] = line
        for _, c in ipairs(o:GetChildren()) do add(c, depth + 1) end
    end
    add(root, 0)
    local text = table.concat(out, "\n")
    print(text)
    if setclipboard then pcall(setclipboard, text) end
end

local lp = {
    gui = nil,
    instr = nil,
    seenAt = 0,
    fails = 0,          -- presses in this minigame that did not lock a bar
    halted = false,     -- true once the fail budget is used up (stops wasting picks)
    cursorPlaced = false,
    cursor2 = false,
    lastPressAt = 0,
    lastDiag = 0,
    seedFor = 0.7,     -- seconds after the GUI shows up (or after a miss) during which nothing is pressed
    hit = setmetatable({}, { __mode = "k" }),
    armed = setmetatable({}, { __mode = "k" }), -- bars that were seen away from the line and may fire
    prev = setmetatable({}, { __mode = "k" }),
    pend = setmetatable({}, { __mode = "k" }),
    lastScan = 0,
    attN = nil,        -- number of used-attempt marks seen in the GUI
    lastPress = nil,   -- info about the latest press (for hit/miss logging)
}

local function resetLockpick()
    lp.attN = nil
    lp.lastPress = nil
    lp.lastScan = 0
    table.clear(lp.armed)
    lp.gui = nil
    lp.instr = nil
    lp.fails = 0
    lp.halted = false
    lp.cursorPlaced = false
    lp.cursor2 = false
    table.clear(lp.hit)
    table.clear(lp.prev)
    table.clear(lp.pend)
end

local function barCenterY(bar)
    return bar.AbsolutePosition.Y + bar.AbsoluteSize.Y * 0.5
end

local function countVisibleHolders(framesF)
    local n = 0
    for _, h in ipairs(framesF:GetChildren()) do
        if h:IsA("GuiObject") and h.Visible then n += 1 end
    end
    return n
end

local function scanLockpickMinigame()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = playerGui and playerGui:FindFirstChild("LockpickGUI")
    if not gui or not gui:IsA("ScreenGui") or not gui.Enabled then
        if lp.gui then resetLockpick() end
        return
    end

    local now = os.clock()
    local mf = gui:FindFirstChild("MF")
    if gui ~= lp.gui then
        resetLockpick()
        lp.gui = gui
        lp.seenAt = now
        lp.seedFor = math.max(0.15, State.LockpickStartDelay)
        lp.instr = mf and mf:FindFirstChild("Instructions", true)
        if State.Debug then
            task.spawn(function()
                task.wait(0.3)
                if gui.Parent then dumpGui(gui) end
            end)
        end
    end

    local lpf = mf and mf:FindFirstChild("LP_Frame")
    local line = lpf and lpf:FindFirstChild("Line")
    local framesF = lpf and lpf:FindFirstChild("Frames")
    if not (line and framesF) then return end

    local resolved = resolveLockpickKey(lp.instr and lp.instr.Text or nil)

    -- park the virtual cursor on the click target while the minigame starts
    if not lp.cursorPlaced then
        lp.cursorPlaced = true
        local m0 = ensureCal(resolved)
        if m0 and m0.kind == "gui" then placeCursor(gui, m0.key) end
    end

    local visCount = countVisibleHolders(framesF)

    -- frame time (the game evaluates a click about one frame after we send it)
    local dtFrame = math.clamp(now - (lp.lastScan > 0 and lp.lastScan or now - 1 / 60), 0.003, 0.05)
    lp.lastScan = now

    -- Attempts counter: a new visible mark = the last press was a MISS (the game resets all bars)
    local attF = mf and mf:FindFirstChild("Attempts")
    local attN = 0
    if attF then
        for _, c in ipairs(attF:GetChildren()) do
            if c:IsA("GuiObject") and c.Visible then attN += 1 end
        end
    end
    if lp.attN == nil then lp.attN = attN end
    if attN ~= lp.attN then
        local missed = attN > lp.attN
        dbg("lockpick attempt marks:", lp.attN, "->", attN)
        lp.attN = attN
        if missed then
            local lpress = lp.lastPress
            if lpress and now - lpress.t < 1 then
                dbg(string.format("lockpick MISS (attempt used): %s was %.1fpx from the line (v=%.0fpx/s, landing e=%.1fpx, frame=%.1fms)",
                    lpress.name, lpress.raw, lpress.v, lpress.e, lpress.dt * 1000))
            else
                dbg("lockpick: attempt used")
            end
            lp.fails += 1
            local cap = State.LockpickMaxFails
            if cap > 0 and lp.fails >= cap and not lp.halted then
                lp.halted = true
                print("[4Money] Auto lockpick paused: " .. lp.fails .. " misses. Enable Debug (Misc) and send me the 'lockpick press/MISS' lines.")
                notify("4Money", "Auto lockpick paused to save your picks (see console).")
            end
        end
        -- bars restart from the far end: forget velocities and wait a moment
        table.clear(lp.prev)
        table.clear(lp.armed)
        table.clear(lp.pend)
        lp.seenAt = now
        lp.seedFor = 0.15
    end

    -- verify earlier presses: success if the bar stopped, vanished, or the next bar appeared
    for bar, p in pairs(lp.pend) do
        local holder = bar.Parent
        local alive = holder and bar.Visible and (not holder:IsA("GuiObject") or holder.Visible)
        if not alive or visCount > p.vis then
            lp.pend[bar] = nil
            onLockResult(p, true)
        else
            local cy = barCenterY(bar)
            local el = now - p.t
            if el >= 0.12 then
                p.min = math.min(p.min or cy, cy)
                p.max = math.max(p.max or cy, cy)
            end
            if el >= 0.45 then
                lp.pend[bar] = nil
                if p.min then
                    local locked = (p.max - p.min) < 3
                    onLockResult(p, locked)
                    -- only informational: a press that "did not lock" may just have been ignored by the game
                    -- (no attempt used), so it must not stop the script. Real misses (attempt marks) still do.
                    dbg(string.format("lockpick result: %s %s (travel %.1fpx in 0.45s)", p.name or "?",
                        locked and "LOCKED" or "NOT locked", p.max - p.min))
                end
            end
        end
    end

    if lp.halted then return end

    local lineY = line.AbsolutePosition.Y + line.AbsoluteSize.Y * 0.5
    local tol = 12 -- a bar must have been this far x2.5 from the line before it may fire
    -- The click is evaluated ~1 frame after it is sent. (The old 40 ms guess made every press ~25px early.)
    local latency = math.max(0, dtFrame + State.LockpickLatencyOffset / 1000)
    local seeding = now - lp.seenAt < lp.seedFor

    -- the GUI may still be sliding in when the cursor was parked: park it once more
    if not lp.cursor2 and now - lp.seenAt > 0.35 then
        lp.cursor2 = true
        local m1 = ensureCal(resolved)
        if m1 and m1.kind == "gui" then placeCursor(gui, m1.key) end
    end

    -- Collect the bars in lock order (B1, B2, B3). On big safes all bars run at the same time and the
    -- game locks them ONE BY ONE, so only the first bar that is not locked yet may be clicked.
    local entries = {}
    for _, holder in ipairs(framesF:GetChildren()) do
        if holder:IsA("GuiObject") then
            local bar = holder:FindFirstChild("Bar")
            if bar and bar:IsA("GuiObject") then
                if holder.Visible and bar.Visible then
                    entries[#entries + 1] = { holder = holder, bar = bar, cy = barCenterY(bar) }
                else
                    -- hidden bar: forget it, so it has to arm again when it shows up
                    lp.prev[bar] = nil
                    lp.armed[bar] = nil
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.holder.LayoutOrder ~= b.holder.LayoutOrder then return a.holder.LayoutOrder < b.holder.LayoutOrder end
        return a.holder.Name < b.holder.Name
    end)

    -- update motion state of every bar; a bar that moved before and now stands still is locked
    local target
    for _, en in ipairs(entries) do
        local bar, cy = en.bar, en.cy
        local st = lp.prev[bar]
        local v = 0
        if st then
            local d = now - st.t
            if d > 0 then v = (cy - st.y) / d end
            if math.abs(cy - st.y) > 0.4 then
                st.lastMove = now
                st.moved = true
            end
        else
            st = { y = cy, t = now, e = 0, lastMove = now, moved = false, first = now }
            lp.prev[bar] = st
        end
        en.v = v
        en.st = st
        -- locked = standing still. A bar that has not budged since we first saw it counts too (state is
        -- cleared after a miss / when the script starts mid-minigame, and a locked bar must never stay "target")
        en.locked = (now - st.lastMove) > 0.15 and (st.moved or (now - st.first) > 0.3)
        if not target and not en.locked then target = en end
    end

    for _, en in ipairs(entries) do
        local bar, cy, v, st = en.bar, en.cy, en.v, en.st
        local predicted = cy + math.clamp(v * latency, -40, 40)
        local e = predicted - lineY -- signed distance of the landing point from the line
        local pe = st.e
        st.y, st.t, st.e = cy, now, e

        -- A bar may only fire after it has been seen AWAY from the line. Bars that appear on
        -- the line (or sit locked on it) are never "armed", so they cannot burn an attempt.
        if math.abs(cy - lineY) > tol * 2.5 then
            lp.armed[bar] = true
        end

        if en == target and lp.armed[bar] and not seeding and math.abs(v) > 20 then
            -- Fire on the frame whose landing point is closest to the line: within half of one
            -- frame's travel (+ a small user slack), or when it jumped over the line.
            local win = math.abs(v) * dtFrame * 0.5 + State.LockpickTolerance * 20 + 0.5
            local crossed = pe and (pe * e < 0) and math.abs(e - pe) < 80
            if math.abs(e) <= win or crossed then
                local m = triggerLockpickAction(gui, resolved)
                if m then
                    lp.armed[bar] = false
                    lp.pend[bar] = { t = now, m = m, vis = visCount, timingOk = math.abs(e) <= win * 2, name = en.holder.Name }
                    lp.lastPress = { t = now, name = en.holder.Name, raw = cy - lineY, v = v, e = e, dt = dtFrame }
                    lp.lastPressAt = now
                    if State.Debug then
                        local all = {}
                        for _, o in ipairs(entries) do
                            all[#all + 1] = string.format("%s=%.0f%s%s", o.holder.Name, o.cy - lineY,
                                o.locked and "(locked)" or "", o == en and "(target)" or "")
                        end
                        dbg(string.format("lockpick press %s via %s: bar %.1fpx from line, landing e=%.1fpx, v=%.0fpx/s, window=%.1fpx, latency=%.1fms | bars: %s",
                            en.holder.Name, describeMethod(m), cy - lineY, e, v, win, latency * 1000, table.concat(all, " ")))
                    end
                end
            end
        end
    end

    -- Debug: say why nothing is being pressed (once a second, only while a target exists)
    if State.Debug and target and now - lp.lastPressAt > 1.5 and now - lp.lastDiag > 1 then
        lp.lastDiag = now
        local st = target.st
        dbg(string.format("lockpick idle: target=%s offset=%.0fpx v=%.0fpx/s armed=%s seeding=%s halted=%s attemptsUsed=%d",
            target.holder.Name, target.cy - lineY, target.v, tostring(lp.armed[target.bar] == true),
            tostring(seeding), tostring(lp.halted), lp.attN or -1))
    end
end

---------------------------------------------------------------------
-- 7. Character / weapon extras
---------------------------------------------------------------------

-- ===== No spread: zero Spread/Inaccuracy/Bloom numbers on the equipped weapon and its config modules =====
-- Every write is logged and put back when you die, switch it off or unload, so game scripts that
-- start on respawn (camera, sprint, controls) never see changed values.
local SPREAD_KEYS = { "spread", "inaccura", "bloom", "scatter", "deviation", "dispersion" }
local SPREAD_SKIP = { "smooth", "recover", "damp", "speed", "decay", "rate", "lerp", "ease", "sens",
    "camera", "time", "step", "delta", "factor", "mult", "sway" }
local NS = {
    log = {}, done = setmetatable({}, { __mode = "k" }), equipT = setmetatable({}, { __mode = "k" }),
    -- No Recoil also zeroes the weapon's own recoil / kick numbers (camera kick, viewmodel kick)
    recoilKeys = { "recoil", "kick" },
    recoilSkip = { "smooth", "recover", "damp", "speed", "decay", "rate", "lerp", "ease", "sens", "time", "step", "delta", "factor", "mult" },
}

local function isSpreadName(n)
    local l = string.lower(tostring(n))
    local function any(list)
        for _, k in ipairs(list) do
            if string.find(l, k, 1, true) then return true end
        end
        return false
    end
    if State.NoSpread and any(SPREAD_KEYS) and not any(SPREAD_SKIP) then return true end
    if State.NoRecoil and any(NS.recoilKeys) and not any(NS.recoilSkip) then return true end
    return false
end

local function zeroValue(v)
    if type(v) == "number" then return 0 end
    if typeof(v) == "Vector2" then return Vector2.zero end
    if typeof(v) == "Vector3" then return Vector3.zero end
    return v
end

function NS.setField(t, k, nv)
    local old = t[k]
    if old == nv then return false end
    NS.log[#NS.log + 1] = { t = t, k = k, v = old }
    t[k] = nv
    return true
end

function NS.zeroTable(t, depth, seen, force)
    if depth > 3 or seen[t] then return 0 end
    seen[t] = true
    local n = 0
    for k, v in pairs(t) do
        if force or (type(k) == "string" and isSpreadName(k)) then
            if type(v) == "table" then
                n += NS.zeroTable(v, depth + 1, seen, true)
            else
                local nv = zeroValue(v)
                if nv ~= v and NS.setField(t, k, nv) then n += 1 end
            end
        elseif type(v) == "table" then
            n += NS.zeroTable(v, depth + 1, seen, false)
        end
    end
    return n
end

function NS.zeroInstance(inst)
    local n = 0
    for name, v in pairs(inst:GetAttributes()) do
        if type(v) == "number" and v ~= 0 and isSpreadName(name) then
            NS.log[#NS.log + 1] = { inst = inst, attr = name, v = v }
            inst:SetAttribute(name, 0)
            n += 1
        end
    end
    return n
end

function NS.zeroValueObject(d)
    NS.log[#NS.log + 1] = { inst = d, v = d.Value }
    d.Value = 0
end

-- put every changed value back (newest first)
function NS.restore()
    local log = NS.log
    NS.log = {}
    table.clear(NS.done)
    for i = #log, 1, -1 do
        local e = log[i]
        pcall(function()
            if e.t then
                e.t[e.k] = e.v
            elseif e.attr then
                e.inst:SetAttribute(e.attr, e.v)
            else
                e.inst.Value = e.v
            end
        end)
    end
end

local rsToolCache = {}

local function applyNoSpread(tool, allowRequire)
    local changed = NS.zeroInstance(tool)
    local modules = {}

    for _, d in ipairs(tool:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and isSpreadName(d.Name) then
            if d.Value ~= 0 then
                NS.zeroValueObject(d)
                changed += 1
            end
        elseif d:IsA("ModuleScript") then
            modules[#modules + 1] = d
        end
    end

    -- weapon configs often live in ReplicatedStorage under the same name
    local rsObj = rsToolCache[tool.Name]
    if rsObj == nil then
        rsObj = ReplicatedStorage:FindFirstChild(tool.Name, true) or false
        rsToolCache[tool.Name] = rsObj
    end
    if rsObj then
        changed += NS.zeroInstance(rsObj)
        if rsObj:IsA("ModuleScript") then modules[#modules + 1] = rsObj end
        for _, d in ipairs(rsObj:GetDescendants()) do
            if d:IsA("ModuleScript") then
                modules[#modules + 1] = d
            elseif (d:IsA("NumberValue") or d:IsA("IntValue")) and isSpreadName(d.Name) and d.Value ~= 0 then
                NS.zeroValueObject(d)
                changed += 1
            end
        end
    end

    -- NEVER require a module the game has not loaded yet: if it errors while we load it, Roblox caches the
    -- error and the game itself then fails with "Requested module experienced an error while loading"
    -- (weapons stop equipping / reloading). Modules are only touched for a weapon that has been in the
    -- player's hands for a while, i.e. after the game's own equip code has run.
    if allowRequire then
        for _, m in ipairs(modules) do
            local ok, res = pcall(require, m)
            if ok and type(res) == "table" then
                local ok2, n = pcall(NS.zeroTable, res, 0, {}, false)
                if ok2 then changed += n end
            end
        end
    end
    return changed, #modules
end

local lastSpreadApply = 0
local spreadReported = setmetatable({}, { __mode = "k" })

local function stepNoSpread(now)
    if now - lastSpreadApply < 0.4 then return end
    lastSpreadApply = now
    -- a toggle changed: weapons that were already processed must be processed again with the new key set
    local mode = (State.NoSpread and 1 or 0) + (State.NoRecoil and 2 or 0)
    if NS.mode ~= mode then
        NS.mode = mode
        table.clear(NS.done)
    end
    local char = LocalPlayer.Character
    -- The equipped weapon is re-applied every pass (the game may put values back). Its ModuleScripts are only
    -- touched after it has been in your hands for 2.5 s (the game has loaded them by then). Weapons in the
    -- backpack get a one-time pass over plain values / attributes only - no module is ever loaded by us.
    local list = {}
    local equipped = char and char:FindFirstChildOfClass("Tool")
    if equipped then
        NS.equipT[equipped] = NS.equipT[equipped] or now
        list[1] = { equipped, now - NS.equipT[equipped] >= 2.5 }
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and not NS.done[t] then
                NS.done[t] = true
                list[#list + 1] = { t, false }
            end
        end
    end
    for _, item in ipairs(list) do
        local tool = item[1]
        local ok, n, mods = pcall(applyNoSpread, tool, item[2])
        if State.Debug and not spreadReported[tool] then
            spreadReported[tool] = true
            print("[4Money] NoSpread:", tool.Name, ok and ("fields changed: " .. tostring(n) .. ", modules: " .. tostring(mods)) or tostring(n))
        end
    end
end

-- ===== Infinite stamina =====
-- Three strategies, all pumped back to the highest value ever seen:
--  1) NumberValue / IntValue / numeric attributes named Stamina/Energy on the character or player
--  2) fields named Stamina in already-loaded ModuleScripts (getloadedmodules)
--  3) tables with a Stamina field anywhere in memory (getgc, one time-sliced scan)
local STAM_KEYS = { "Stamina", "stamina", "STAMINA", "CurrentStamina", "StaminaValue", "Energy", "energy" }
local MAX_KEYS = { "MaxStamina", "maxStamina", "MaxEnergy", "StaminaMax" }
local STAM_BAD = { "max", "regen", "rate", "drain", "cost", "delay", "cooldown", "speed", "recover", "time", "mult" }

local stamMax = setmetatable({}, { __mode = "k" })
local stamAttrMax = setmetatable({}, { __mode = "k" })
local stamReported = setmetatable({}, { __mode = "k" })
local stamTables = {}
local stamSeen = setmetatable({}, { __mode = "k" })
local stamScanToken = 0

local function isStaminaName(n)
    local l = string.lower(tostring(n))
    if not (string.find(l, "stamina", 1, true) or string.find(l, "energy", 1, true)) then return false end
    for _, bad in ipairs(STAM_BAD) do
        if string.find(l, bad, 1, true) then return false end
    end
    return true
end

local function pumpInst(inst)
    if (inst:IsA("NumberValue") or inst:IsA("IntValue")) and isStaminaName(inst.Name) then
        local v = inst.Value
        local mx = math.max(stamMax[inst] or 0, v)
        stamMax[inst] = mx
        if v < mx then inst.Value = mx end
        if State.Debug and not stamReported[inst] then
            stamReported[inst] = true
            print("[4Money] Stamina value:", inst:GetFullName(), "max=", mx)
        end
    end
end

local function pumpAttrs(inst)
    for name, v in pairs(inst:GetAttributes()) do
        if type(v) == "number" and isStaminaName(name) then
            local t = stamAttrMax[inst]
            if not t then
                t = {}
                stamAttrMax[inst] = t
            end
            local explicitMax = inst:GetAttribute("Max" .. name)
            local mx = math.max(t[name] or 0, v, type(explicitMax) == "number" and explicitMax or 0)
            t[name] = mx
            if v < mx then inst:SetAttribute(name, mx) end
            if State.Debug and not stamReported[inst] then
                stamReported[inst] = true
                print("[4Money] Stamina attribute:", inst:GetFullName(), name, "max=", mx)
            end
        end
    end
end

local function tryRegisterStaminaTable(t)
    if stamSeen[t] then return false end
    for _, k in ipairs(STAM_KEYS) do
        local ok, v = pcall(rawget, t, k)
        if ok and type(v) == "number" then
            local mx = v
            for _, mk in ipairs(MAX_KEYS) do
                local okm, mv = pcall(rawget, t, mk)
                if okm and type(mv) == "number" and mv > mx then mx = mv end
            end
            stamSeen[t] = true
            stamTables[#stamTables + 1] = { t = t, key = k, max = mx }
            if State.Debug then print("[4Money] Stamina table found: key=" .. k .. " value=" .. tostring(v) .. " max=" .. tostring(mx)) end
            return true
        end
    end
    return false
end

local function scanStaminaSources()
    stamScanToken += 1
    local token = stamScanToken
    stamTables = {}
    stamSeen = setmetatable({}, { __mode = "k" })

    -- Loading modules from here is disabled on purpose: some executors return EVERY ModuleScript from
    -- getloadedmodules, and requiring one that is not loaded yet can poison it for the game itself.
    -- (The memory scan below and the stamina learner do not need it.)
    if false and getloadedmodules then
        local ok, mods = pcall(getloadedmodules)
        if ok and type(mods) == "table" then
            for _, m in ipairs(mods) do
                local okr, res = pcall(require, m)
                if okr and type(res) == "table" then
                    pcall(tryRegisterStaminaTable, res)
                    local okp = pcall(function()
                        for _, v in pairs(res) do
                            if type(v) == "table" then tryRegisterStaminaTable(v) end
                        end
                    end)
                    if not okp then dbg("module scan error in", m.Name) end
                end
            end
        end
    end

    if getgc then
        task.spawn(function()
            local ok, all = pcall(getgc, true)
            if not ok or type(all) ~= "table" then return end
            local t0 = os.clock()
            for i = 1, #all do
                if token ~= stamScanToken or not isRunning then return end
                local v = all[i]
                if type(v) == "table" and #stamTables < 24 then
                    pcall(tryRegisterStaminaTable, v)
                end
                if os.clock() - t0 > 0.003 then
                    task.wait()
                    t0 = os.clock()
                end
            end
            dbg("stamina memory scan finished, tables:", #stamTables)
        end)
    end

    if State.Debug then
        -- list every numeric value so the real stamina source can be identified
        local function listNumbers(root, label)
            local n = 0
            for _, d in ipairs(root:GetDescendants()) do
                if (d:IsA("NumberValue") or d:IsA("IntValue")) and n < 60 then
                    n += 1
                    print("[4Money] " .. label .. " value:", d:GetFullName(), d.Value)
                end
            end
            for name, v in pairs(root:GetAttributes()) do
                if type(v) == "number" then print("[4Money] " .. label .. " attribute:", name, v) end
            end
        end
        if LocalPlayer.Character then listNumbers(LocalPlayer.Character, "Character") end
        for _, c in ipairs(LocalPlayer:GetChildren()) do
            if c.Name ~= "PlayerGui" then listNumbers(c, "Player." .. c.Name) end
        end
        print("[4Money] getgc:", tostring(getgc ~= nil), "getloadedmodules:", tostring(getloadedmodules ~= nil))
    end
end

-- ===== Stamina learner (name independent) =====
-- The game shows stamina as a percentage (CoreGUI...StaminaNum). While you sprint that number changes,
-- so we look through memory for numbers that FOLLOW it (tables with a numeric field, function upvalues),
-- keep the ones that keep matching, and pin them to full. Sprint for a few seconds after enabling it.
local SL = {
    cands = nil, pinned = {}, p0 = nil, t0 = 0, rounds = 0,
    token = 0, scanning = false, lastP = nil, cooldown = 0, lowSince = nil, lbl = nil,
    getUp = (debug and debug.getupvalues) or getupvalues,
    setUp = (debug and debug.setupvalue) or setupvalue,
}

function SL.percent()
    local lbl = SL.lbl
    if not (lbl and lbl.Parent) then
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local core = pg and pg:FindFirstChild("CoreGUI")
        lbl = core and core:FindFirstChild("StaminaNum", true)
        SL.lbl = lbl
        if not lbl then return nil end
    end
    return tonumber(string.match(lbl.Text, "[%d%.]+"))
end

-- 100 = value is on the 0..100 scale, 1 = value is on the 0..1 scale
function SL.scale(v, P, tol)
    if type(v) ~= "number" then return nil end
    if math.abs(v - P) < tol then return 100 end
    if math.abs(v * 100 - P) < tol then return 1 end
    return nil
end

function SL.read(c)
    if c.t then
        local ok, v = pcall(rawget, c.t, c.k)
        if ok then return v end
        return nil
    end
    if SL.getUp then
        local ok, ups = pcall(SL.getUp, c.f)
        if ok and type(ups) == "table" then return ups[c.i] end
    end
    return nil
end

function SL.scan(P)
    SL.token += 1
    local token = SL.token
    SL.scanning = true
    task.spawn(function()
        local out = {}
        local ok, all = pcall(getgc, true)
        if ok and type(all) == "table" then
            local t0 = os.clock()
            for i = 1, #all do
                if token ~= SL.token or not isRunning then
                    SL.scanning = false
                    return
                end
                local o = all[i]
                local ty = type(o)
                if #out < 4000 then
                    if ty == "table" then
                        pcall(function()
                            local c = 0
                            for k, v in next, o do
                                c += 1
                                if c > 80 then break end
                                if type(k) == "string" and type(v) == "number" then
                                    local sc = SL.scale(v, P, 6) -- wide: the bar keeps moving while we scan
                                    if sc then out[#out + 1] = { t = o, k = k, scale = sc } end
                                end
                            end
                        end)
                    elseif ty == "function" and SL.getUp and (not islclosure or islclosure(o)) then
                        pcall(function()
                            local ups = SL.getUp(o)
                            if type(ups) == "table" then
                                for idx, v in pairs(ups) do
                                    local sc = SL.scale(v, P, 6)
                                    if sc then out[#out + 1] = { f = o, i = idx, scale = sc } end
                                end
                            end
                        end)
                    end
                end
                if os.clock() - t0 > 0.003 then
                    task.wait()
                    t0 = os.clock()
                end
            end
        end
        if token == SL.token then
            SL.cands = out
            SL.p0 = SL.percent() or P
            SL.t0 = os.clock()
            SL.rounds = 0
            dbg("stamina learner: scan done, candidates:", #out)
        end
        SL.scanning = false
    end)
end

function SL.reset()
    SL.token += 1
    SL.scanning = false
    SL.cands = nil
    SL.pinned = {}
    SL.lastP = nil
    SL.lowSince = nil
    SL.lbl = nil
end

function SL.step(now)
    local P = SL.percent()
    if not P then return end

    if #SL.pinned > 0 then
        for _, c in ipairs(SL.pinned) do
            local val = (c.scale == 100) and 100 or 1
            if c.t then
                pcall(rawset, c.t, c.k, val)
            elseif SL.setUp then
                pcall(SL.setUp, c.f, c.i, val)
            end
        end
        if P < 95 then
            SL.lowSince = SL.lowSince or now
            if now - SL.lowSince > 2.5 then
                print("[4Money] Stamina: pinned values did not keep the bar full, learning again (sprint a few seconds)")
                SL.pinned = {}
                SL.lowSince = nil
                SL.cooldown = now + 2
            end
        else
            SL.lowSince = nil
        end
        return
    end

    if SL.scanning or now < SL.cooldown then
        SL.lastP = P
        return
    end

    if not SL.cands then
        if SL.lastP and math.abs(P - SL.lastP) >= 1 and P > 3 and P < 97 then SL.scan(P) end
        SL.lastP = P
        return
    end

    -- candidates exist: once the bar has moved on, keep only those that followed it
    if now - SL.t0 > 0.6 and math.abs(P - SL.p0) >= 3 then
        local keep = {}
        for _, c in ipairs(SL.cands) do
            if SL.scale(SL.read(c), P, 1.5) == c.scale then keep[#keep + 1] = c end
        end
        SL.cands = keep
        SL.p0, SL.t0 = P, now
        SL.rounds += 1
        dbg("stamina learner: round", SL.rounds, "candidates left:", #keep)
        if #keep == 0 then
            SL.cands = nil
            SL.cooldown = now + 1
        elseif SL.rounds >= 2 and #keep <= 12 then
            SL.pinned = keep
            SL.cands = nil
            print("[4Money] Stamina learned: pinning " .. #keep .. " value(s)")
        elseif SL.rounds >= 4 then
            SL.cands = nil
            SL.cooldown = now + 3
        end
    elseif now - SL.t0 > 25 then
        SL.cands = nil
    end
end

local lastStamina = 0

local function stepStamina()
    if not Life.alive() then
        -- dead: forget tables of the old life (they are rescanned after respawn) and write nothing
        if #stamTables > 0 then
            stamTables = {}
            stamScanToken += 1
        end
        return
    end
    if os.clock() - Life.start < 2 then return end
    local char = LocalPlayer.Character
    if char then
        pumpAttrs(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then pumpAttrs(hum) end
        for _, d in ipairs(char:GetDescendants()) do pumpInst(d) end
    end
    pumpAttrs(LocalPlayer)
    for _, c in ipairs(LocalPlayer:GetChildren()) do
        if c.Name ~= "PlayerGui" and c.Name ~= "Backpack" then
            pumpInst(c)
            if c:IsA("Folder") or c:IsA("Configuration") then
                for _, d in ipairs(c:GetDescendants()) do pumpInst(d) end
            end
        end
    end
    for i = #stamTables, 1, -1 do
        local e = stamTables[i]
        local v = rawget(e.t, e.key)
        if type(v) ~= "number" then
            table.remove(stamTables, i)
        else
            if v > e.max then e.max = v end
            if v < e.max then rawset(e.t, e.key, e.max) end
        end
    end
    pcall(SL.step, os.clock())
end

-- rescan after every respawn (character scripts get recreated)
track(LocalPlayer.CharacterAdded:Connect(function()
    SL.reset() -- the old life's script state is gone: learn again
    if State.InfStamina then
        task.delay(3, function()
            if isRunning and State.InfStamina then pcall(scanStaminaSources) end
        end)
    end
end))

-- ===== Fullbright =====
-- Forces bright, shadowless, fog-free lighting. The game's own values are saved and put back when it is
-- switched off or the script unloads; the game's day/night changes are overridden every 0.3 s.
local FB = { orig = nil, last = 0, atm = setmetatable({}, { __mode = "k" }) }
FB.props = {
    Brightness = 2,
    ClockTime = 14,
    FogEnd = 100000,
    FogStart = 100000,
    GlobalShadows = false,
    Ambient = Color3.fromRGB(190, 190, 190),
    OutdoorAmbient = Color3.fromRGB(190, 190, 190),
}

function FB.apply()
    local L = game:GetService("Lighting")
    if not FB.orig then
        FB.orig = {}
        for k in pairs(FB.props) do FB.orig[k] = L[k] end
    end
    for k, v in pairs(FB.props) do
        if L[k] ~= v then L[k] = v end
    end
    for _, a in ipairs(L:GetChildren()) do
        if a:IsA("Atmosphere") then
            if FB.atm[a] == nil then FB.atm[a] = { a.Density, a.Haze } end
            if a.Density ~= 0 then a.Density = 0 end
            if a.Haze ~= 0 then a.Haze = 0 end
        end
    end
end

function FB.restore()
    local L = game:GetService("Lighting")
    if FB.orig then
        for k, v in pairs(FB.orig) do pcall(function() L[k] = v end) end
        FB.orig = nil
    end
    for a, o in pairs(FB.atm) do
        if a.Parent then pcall(function() a.Density = o[1]; a.Haze = o[2] end) end
        FB.atm[a] = nil
    end
end

function FB.step(now)
    if now - FB.last < 0.3 then return end
    FB.last = now
    FB.apply()
end

-- ===== Anti flashbang =====
-- Hides (a) ScreenGuis / big GUI frames named flash*/blind*, (b) full-screen WHITE frames that sit directly
-- under a ScreenGui, (c) Lighting / Camera post effects named flash*/blind* and ColorCorrection flashes.
-- Turn on Debug to see what gets hidden (names differ between games / updates).
local AF = { watched = setmetatable({}, { __mode = "k" }), last = 0 }

function AF.nameHit(n)
    local l = string.lower(tostring(n))
    if string.find(l, "light", 1, true) then return false end -- Flashlight is not a flashbang
    return string.find(l, "flash", 1, true) ~= nil or string.find(l, "blind", 1, true) ~= nil
end

function AF.big(g)
    local s = g.Size
    return s.X.Scale >= 0.9 and s.Y.Scale >= 0.9
end

function AF.hide(inst)
    local prop
    if inst:IsA("ScreenGui") or inst:IsA("PostEffect") then
        prop = "Enabled"
    elseif inst:IsA("GuiObject") then
        prop = "Visible"
    else
        return
    end
    if inst[prop] then
        inst[prop] = false
        dbg("anti-flash hid:", inst.ClassName, inst:GetFullName())
    end
    if not AF.watched[inst] then
        AF.watched[inst] = true
        track(inst:GetPropertyChangedSignal(prop):Connect(function()
            if State.AntiFlash and isRunning and inst[prop] then inst[prop] = false end
        end))
    end
end

function AF.candidate(d)
    if not State.AntiFlash or not d.Parent then return end
    if d:IsA("ScreenGui") then
        AF.hide(d)
    elseif d:IsA("GuiObject") and AF.big(d) then
        AF.hide(d)
    end
end

function AF.overlay(g)
    if not g.Visible or g.BackgroundTransparency > 0.85 or not AF.big(g) then return false end
    local c = g.BackgroundColor3
    return c.R > 0.9 and c.G > 0.9 and c.B > 0.9
end

function AF.step(now)
    if now - AF.last < 0.1 then return end
    AF.last = now
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled then
                if AF.nameHit(sg.Name) then
                    AF.hide(sg)
                else
                    for _, c in ipairs(sg:GetChildren()) do
                        if c:IsA("Frame") and AF.overlay(c) then AF.hide(c) end
                    end
                end
            end
        end
    end
    local cam = workspace.CurrentCamera
    for _, root in ipairs({ game:GetService("Lighting"), cam }) do
        if root then
            for _, e in ipairs(root:GetChildren()) do
                if e:IsA("PostEffect") then
                    if AF.nameHit(e.Name) then
                        AF.hide(e)
                    elseif e:IsA("ColorCorrectionEffect") and e.Enabled and e.Brightness > 0.45 then
                        e.Brightness = 0
                        dbg("anti-flash reset brightness:", e:GetFullName())
                    end
                end
            end
        end
    end
end

do
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        track(pg.DescendantAdded:Connect(function(d)
            if State.AntiFlash and AF.nameHit(d.Name) then task.defer(AF.candidate, d) end
        end))
    end
end

-- ===== No fall damage =====
-- 1) cap the fall speed (damage grows with speed) and kill the speed right before touching the ground
-- 2) block remotes with "fall" in the name
-- 3) LEARN the damage remote (names are obfuscated): if you still lose health after a fast fall, the remotes
--    that were fired around the landing are blocked from then on (needs hookmetamethod)
local fallParams = RaycastParams.new()
fallParams.FilterType = Enum.RaycastFilterType.Exclude
local NF = { recent = {}, blocked = setmetatable({}, { __mode = "k" }), hp0 = nil, fallT = 0 }

function NF.learn(landT)
    local counts = {}
    for _, r in ipairs(NF.recent) do counts[r.remote] = (counts[r.remote] or 0) + 1 end
    local seen = false
    for _, r in ipairs(NF.recent) do
        if r.t >= landT - 0.25 and r.t <= landT + 0.5 then
            seen = true
            if counts[r.remote] <= 3 and not NF.blocked[r.remote] then
                NF.blocked[r.remote] = true
                print("[4Money] No fall: learned damage remote " .. r.remote:GetFullName() .. " (blocked from now on)")
            end
        end
    end
    if not seen then
        print("[4Money] No fall: damage was taken but NO remote was fired around the landing"
            .. (NF.hooked and "." or " (the remote hook is not active in this executor, so remotes cannot be seen)")
            .. " The damage is probably computed by the server from your height/position.")
    end
end

-- the game may react to the Humanoid "Landed" state; keep that state off while falling fast
function NF.release()
    NF.stateOff = false
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
    end
end

local function stepNoFall()
    if NF.install and not NF.tried then
        NF.tried = true
        NF.install()
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) or hum.Health <= 0 then
        NF.hp0 = nil
        NF.stateOff = false
        return
    end
    local now = os.clock()
    local vel = hrp.AssemblyLinearVelocity

    if vel.Y < -20 and not NF.stateOff then
        NF.stateOff = true
        NF.offT = now
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end)
    elseif NF.stateOff and vel.Y > -8 and now - (NF.offT or 0) > 0.6 then
        NF.release()
    end

    if vel.Y < -26 and not NF.hp0 then
        NF.hp0 = hum.Health
        NF.fallT = now
    end

    if vel.Y < -30 then
        fallParams.FilterDescendantsInstances = { char }
        local dist = math.clamp(-vel.Y * 0.12, 7, 25)
        local hit = Life.ray(hrp.Position, Vector3.new(0, -dist, 0), fallParams)
        hrp.AssemblyLinearVelocity = Vector3.new(vel.X, hit and -4 or -30, vel.Z)
    elseif NF.hp0 and vel.Y > -8 and now - NF.fallT > 0.15 then
        -- landed: did it still hurt?
        local hp0, landT = NF.hp0, now
        NF.hp0 = nil
        task.delay(0.5, function()
            local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and h.Health < hp0 - 0.5 and State.NoFall then
                dbg("fall damage still taken:", hp0 - h.Health)
                NF.learn(landT)
            end
        end)
    end
end

-- ===== Silent aim =====
-- While you shoot, the rays the game casts to find what the bullet hits (workspace:Raycast /
-- FindPartOnRay*) are turned toward the head of the enemy closest to the crosshair. The camera does not
-- move. Only rays that look like a shot are touched: they start near the camera / your character, are long
-- and point roughly where you look; ground checks, our own raycasts (checkcaller) and everything else are
-- left alone. Needs hookmetamethod.
local SA = {
    cache = nil, cacheT = 0, busy = false, count = 0, lastShot = 0,
    params = RaycastParams.new(),
    methods = { Raycast = true, FindPartOnRay = true, FindPartOnRayWithIgnoreList = true, FindPartOnRayWithWhitelist = true },
}
SA.params.FilterType = Enum.RaycastFilterType.Exclude
NF.SA = SA

function SA.visible(part, c, origin, myChar)
    SA.busy = true
    SA.params.FilterDescendantsInstances = { c, myChar, workspace.CurrentCamera }
    local hit = Life.ray(origin, part.Position - origin, SA.params)
    SA.busy = false
    return hit == nil
end

-- the enemy part closest to the crosshair (screen distance), inside the silent-aim FOV circle
function SA.pick()
    local now = os.clock()
    if now - SA.cacheT < 0.03 then return SA.cache end
    SA.cacheT = now
    SA.cache = nil
    local cam = workspace.CurrentCamera
    local myChar = LocalPlayer.Character
    if not cam or not myChar then return nil end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local myPos = cam.CFrame.Position
    local best, bestD
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = plr ~= LocalPlayer and plr.Character
        if c then
            local part
            if State.SilentPart == "Head" then
                part = c:FindFirstChild("Head")
            else
                part = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or c:FindFirstChild("HumanoidRootPart")
            end
            local hum = c:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 and (part.Position - myPos).Magnitude <= State.SilentMaxDistance then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d <= State.SilentFov and (not bestD or d < bestD)
                        and (not State.SilentWallCheck or SA.visible(part, c, myPos, myChar)) then
                        best, bestD = { part = part, char = c, plr = plr }, d
                    end
                end
            end
        end
    end
    SA.cache = best
    return best
end

-- returns the new direction for a shot-like ray, or nil to leave it alone
function SA.redirect(origin, dir)
    if SA.busy or not State.SilentAim then return nil end
    local cam = workspace.CurrentCamera
    if not cam or not Life.alive() or not hasWeaponEquipped() then return nil end
    local shooting = isShooting or os.clock() - SA.lastShot < 0.25
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    if not shooting then return nil end
    if dir.Magnitude < 50 then return nil end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local near = (origin - cam.CFrame.Position).Magnitude <= 15 or (hrp and (origin - hrp.Position).Magnitude <= 12)
    if not near then return nil end
    if dir.Unit:Dot(cam.CFrame.LookVector) < 0.9 then return nil end
    local pick = SA.pick()
    if not pick then return nil end
    if State.SilentHitChance < 100 and math.random() * 100 > State.SilentHitChance then return nil end
    SA.count += 1
    if State.Debug and (SA.count <= 8 or SA.count % 25 == 0) then
        dbg("silent aim: ray turned to", pick.plr.Name, pick.part.Name, "(#" .. SA.count .. ")")
    end
    return (pick.part.Position - origin).Unit * dir.Magnitude
end

function SA.apply(m, a)
    if m == "Raycast" then
        local o, d = a[1], a[2]
        if typeof(o) == "Vector3" and typeof(d) == "Vector3" then
            local nd = SA.redirect(o, d)
            if nd then
                a[2] = nd
                return true
            end
        end
    else
        local ray = a[1]
        if typeof(ray) == "Ray" then
            local nd = SA.redirect(ray.Origin, ray.Direction)
            if nd then
                a[1] = Ray.new(ray.Origin, nd)
                return true
            end
        end
    end
    return false
end

-- One shared __namecall hook: (a) blocks "fall" remotes while No Fall is on,
-- (b) records remote calls while the macro recorder is active (used by Allowance / Bank),
-- (c) silent aim: turns shot rays toward the target.
local recorder = { active = false, name = nil, log = {} }
local hookInstalled = false
local hookWorks = false

local function installNamecallHook()
    if hookInstalled then return hookWorks end
    hookInstalled = true
    -- hookmetamethod, or (older executors) the same thing done by hand on the raw metatable
    local hookFn = hookmetamethod
    if not hookFn and getrawmetatable and (setreadonly or make_writeable) then
        hookFn = function(obj, method, fn)
            local mt = getrawmetatable(obj)
            local prev = rawget(mt, method)
            if setreadonly then setreadonly(mt, false) else make_writeable(mt) end
            rawset(mt, method, fn)
            if setreadonly then setreadonly(mt, true) end
            return prev
        end
    end
    if not (hookFn and getnamecallmethod) then
        dbg("no way to hook __namecall in this executor")
        return false
    end
    local old
    local function hook(self, ...)
        local m = getnamecallmethod()
        if (m == "FireServer" or m == "InvokeServer") and isRunning and typeof(self) == "Instance" then
            if recorder.active then
                local log = recorder.log
                log[#log + 1] = { remote = self, method = m, args = table.pack(...), tick = tick() }
                if #log > 400 then table.remove(log, 1) end
            end
            if State.NoFall then
                local recent = NF.recent
                recent[#recent + 1] = { remote = self, t = os.clock() }
                if #recent > 60 then table.remove(recent, 1) end
                if NF.blocked[self] or string.find(string.lower(self.Name), "fall", 1, true) then
                    dbg("blocked remote:", self.Name)
                    return nil
                end
            end
        end
        if State.SilentAim and isRunning and SA.methods[m] and self == workspace
            and not SA.busy and not (checkcaller and checkcaller()) then
            local a = table.pack(...)
            local okA, changed = pcall(SA.apply, m, a)
            if okA and changed then
                return old(self, table.unpack(a, 1, a.n))
            end
        end
        return old(self, ...)
    end
    local ok, err = pcall(function()
        old = hookFn(game, "__namecall", newcclosure and newcclosure(hook) or hook)
    end)
    if not ok then
        dbg("failed to install hook:", err)
        return false
    end
    hookWorks = true
    NF.hooked = true
    return true
end
NF.install = installNamecallHook

---------------------------------------------------------------------
-- 8. Money helpers (from the AutoFarm reference script)
--    Filter.SpawnedBread          - dropped cash
--    Events.CZDPZUS               - pickup remote
--    Events["XMHH.2"/"XMHH2.2"]   - crowbar hit remotes (Register/Safe)
---------------------------------------------------------------------
local cashLock = false
local lastCash = 0

local function stepAutoCash(now)
    if cashLock or now - lastCash < 0.15 then return end
    lastCash = now
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local filter = workspace:FindFirstChild("Filter")
    local folder = filter and filter:FindFirstChild("SpawnedBread")
    local events = ReplicatedStorage:FindFirstChild("Events")
    local remote = events and events:FindFirstChild("CZDPZUS")
    if not (hrp and folder and remote) then return end

    for _, part in ipairs(folder:GetChildren()) do
        if part:IsA("BasePart") and (hrp.Position - part.Position).Magnitude <= State.CashRadius then
            cashLock = true
            task.spawn(function()
                pcall(function() remote:FireServer(part) end)
                task.wait(1.1)
                cashLock = false
            end)
            break
        end
    end
end

local BREAD = "\u{1F35E}"
local lastCrowbar = 0
local crowbarBusy = false
local crowbarHits = 0

local function findNearestSafe(origin, maxDist)
    local folder = getGameFolder("BredMakurz")
    if not folder then return nil end
    local best, bestDist, bestPart = nil, maxDist, nil
    for _, o in ipairs(folder:GetChildren()) do
        local lname = string.lower(o.Name)
        if string.find(lname, "safe", 1, true) or string.find(lname, "register", 1, true) then
            local broken = findBroken(o)
            if broken and not broken.Value then
                local a = anchorOf(o)
                if a then
                    local d = (a.Position - origin).Magnitude
                    if d <= bestDist then
                        best, bestDist, bestPart = o, d, a
                    end
                end
            end
        end
    end
    return best, bestPart
end

local function stepAutoCrowbar(now)
    if crowbarBusy or now < lastCrowbar then return end
    lastCrowbar = now + 0.4

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum and hum.Health > 0) then return end

    local crowbar = char:FindFirstChild("Crowbar")
    if not crowbar then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        local tool = bp and bp:FindFirstChild("Crowbar")
        if tool then pcall(function() hum:EquipTool(tool) end) end
        return
    end

    local target, mainPart = findNearestSafe(hrp.Position, State.CrowbarRange)
    if not target then return end

    local events = ReplicatedStorage:FindFirstChild("Events")
    local r1 = events and events:FindFirstChild("XMHH.2")
    local r2 = events and events:FindFirstChild("XMHH2.2")
    local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
    if not (r1 and r2 and arm) then return end

    crowbarBusy = true
    task.spawn(function()
        local ok, res = pcall(function()
            return r1:InvokeServer(BREAD, tick(), crowbar, "DZDRRRKI", target, "Register")
        end)
        if ok and res then
            pcall(function()
                r2:FireServer(BREAD, tick(), crowbar, "2389ZFX34", res, false, arm, mainPart, target, mainPart.Position, mainPart.Position)
            end)
            crowbarHits += 1
            if crowbarHits % 4 == 0 then lastCrowbar = os.clock() + 0.8 end
            dbg("crowbar hit", crowbarHits, target.Name)
        end
        crowbarBusy = false
    end)
end

---------------------------------------------------------------------
-- 8b. Allowance collector + Bank -> Cash, both usable from afar
--   Allowance: finds the allowance ProximityPrompt(s) and fires them remotely
--              (fireproximityprompt does not care about distance). If no prompt is found,
--              it replays a learned remote call instead.
--   Bank -> Cash: "learn" the real remote calls once (do a withdrawal at an ATM while
--              recording), then replay them from anywhere, manually or on a timer.
---------------------------------------------------------------------
local Macros = { Allowance = { seq = {} }, Bank = { seq = {} } }

local function summarizeArgs(args)
    local out = {}
    for i = 1, args.n do
        local a = args[i]
        local t = typeof(a)
        if t == "Instance" then
            out[#out + 1] = a.ClassName .. ":" .. a.Name
        elseif t == "string" or t == "number" or t == "boolean" then
            out[#out + 1] = tostring(a)
        else
            out[#out + 1] = t
        end
    end
    return table.concat(out, ", ")
end

local function startLearning(name)
    if not installNamecallHook() then
        notify("4Money", "This executor has no remote hooks, cannot record '" .. name .. "'.")
        return
    end
    recorder.active = true
    recorder.name = name
    recorder.log = {}
    notify("4Money", "Recording '" .. name .. "'. Do it once in-game, then press 'Stop & save'.")
end

local function stopLearning()
    if not recorder.active then
        notify("4Money", "Nothing is being recorded.")
        return
    end
    recorder.active = false

    -- remotes called many times while recording are movement/shooting noise: drop them
    local counts = {}
    for _, c in ipairs(recorder.log) do counts[c.remote] = (counts[c.remote] or 0) + 1 end
    local seq = {}
    for _, c in ipairs(recorder.log) do
        if counts[c.remote] <= 3 then seq[#seq + 1] = c end
    end
    while #seq > 6 do table.remove(seq, 1) end

    Macros[recorder.name].seq = seq
    print("[4Money] Learned '" .. recorder.name .. "': " .. #seq .. " call(s)")
    for i, c in ipairs(seq) do
        print(string.format("  %d. %s:%s(%s)", i, c.remote:GetFullName(), c.method, summarizeArgs(c.args)))
    end
    notify("4Money", "Saved " .. #seq .. " call(s) for '" .. recorder.name .. "'.")
end

local function replayMacro(name)
    local seq = Macros[name].seq
    if #seq == 0 then return false end
    task.spawn(function()
        for _, c in ipairs(seq) do
            if not isRunning then return end
            local remote = c.remote
            if remote and remote.Parent then
                local args = table.pack(table.unpack(c.args, 1, c.args.n))
                -- timestamps recorded with tick() are refreshed so the server does not see stale ones
                for i = 1, args.n do
                    local a = args[i]
                    if type(a) == "number" and math.abs(a - c.tick) < 30 then
                        args[i] = tick() + (a - c.tick)
                    end
                end
                pcall(function()
                    if c.method == "FireServer" then
                        remote:FireServer(table.unpack(args, 1, args.n))
                    else
                        remote:InvokeServer(table.unpack(args, 1, args.n))
                    end
                end)
            end
            task.wait(0.12)
        end
    end)
    return true
end

-- Allowance prompts
local allowance = { prompts = {}, scanning = false, lastScan = -100, last = 0 }

local function promptText(p)
    local parts = { p.ObjectText, p.ActionText, p.Name }
    local par = p.Parent
    for _ = 1, 3 do
        if par and par ~= workspace then
            parts[#parts + 1] = par.Name
            par = par.Parent
        end
    end
    return string.lower(table.concat(parts, " "))
end

local function scanAllowancePrompts()
    if allowance.scanning then return end
    allowance.scanning = true
    allowance.lastScan = os.clock()
    local found = {}
    walkAsyncDone(workspace, function(inst)
        if inst:IsA("ProximityPrompt") and string.find(promptText(inst), "allowance", 1, true) then
            found[#found + 1] = inst
            dbg("allowance prompt:", inst:GetFullName(), "action=", inst.ActionText, "object=", inst.ObjectText)
        end
    end, function() return not isRunning end, function()
        allowance.prompts = found
        allowance.scanning = false
        dbg("allowance scan done, prompts:", #found)
    end)
end

local function stepAllowance(now)
    if now - allowance.last < State.AllowanceInterval then return end
    allowance.last = now

    local fired = false
    for _, p in ipairs(allowance.prompts) do
        if p.Parent and p.Enabled and fireproximityprompt then
            fired = true
            task.spawn(function() pcall(fireproximityprompt, p) end)
        end
    end

    if #allowance.prompts == 0 then
        if not allowance.scanning and now - allowance.lastScan > 20 then
            scanAllowancePrompts()
        end
        if #Macros.Allowance.seq > 0 then replayMacro("Allowance") end
    elseif not fired and #Macros.Allowance.seq > 0 then
        replayMacro("Allowance")
    end
end

local lastBank = 0
local function stepAutoBank(now)
    if now - lastBank < State.BankInterval then return end
    lastBank = now
    replayMacro("Bank")
end

-- Debug helper: print every prompt within a radius (to identify allowance / ATM objects)
local function listNearbyPrompts(radius)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local lines = {}
    walkAsyncDone(workspace, function(inst)
        if inst:IsA("ProximityPrompt") then
            local part = inst.Parent
            if part and part:IsA("Attachment") then part = part.Parent end
            if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= radius then
                lines[#lines + 1] = string.format("%s | action='%s' object='%s' enabled=%s",
                    inst:GetFullName(), inst.ActionText, inst.ObjectText, tostring(inst.Enabled))
            end
        end
    end, function() return not isRunning end, function()
        local text = "[4Money] Prompts within " .. radius .. " studs (" .. #lines .. "):\n" .. table.concat(lines, "\n")
        print(text)
        if setclipboard then pcall(setclipboard, text) end
        notify("4Money", #lines .. " prompt(s) printed to console (and copied).")
    end)
end

---------------------------------------------------------------------
-- 9. Main loops
---------------------------------------------------------------------
---------------------------------------------------------------------
-- Hitmarker + off-screen arrows
--  Hitmarker: when another player's health drops shortly after you fired and that player is near the
--  crosshair, a small X flashes at the center (red = that hit killed) and a sound plays.
--  Arrows: chevrons around the screen center that point to nearby players who are outside the view.
---------------------------------------------------------------------
local Vis = {
    hp = setmetatable({}, { __mode = "k" }),
    lastShot = 0, hitT = -1, kill = false,
    arrows = {},
}

Vis.root = Instance.new("Frame")
Vis.root.Name = "Hitmarker"
Vis.root.AnchorPoint = Vector2.new(0.5, 0.5)
Vis.root.Position = UDim2.new(0.5, 0, 0.5, 0)
Vis.root.Size = UDim2.new(0, 40, 0, 40)
Vis.root.BackgroundTransparency = 1
Vis.root.Visible = false
Vis.root.Parent = OverlayGui

Vis.lines = {}
for i, c in ipairs({ { -1, -1, 45 }, { 1, -1, -45 }, { -1, 1, -45 }, { 1, 1, 45 } }) do
    local l = Instance.new("Frame")
    l.AnchorPoint = Vector2.new(0.5, 0.5)
    l.Size = UDim2.new(0, 10, 0, 2)
    l.Position = UDim2.new(0.5, c[1] * 9, 0.5, c[2] * 9)
    l.Rotation = c[3]
    l.BorderSizePixel = 0
    l.BackgroundColor3 = Color3.new(1, 1, 1)
    l.Parent = Vis.root
    Vis.lines[i] = l
end

pcall(function()
    local s = Instance.new("Sound")
    s.Name = "Money4Hit"
    s.SoundId = "rbxassetid://160432334"
    s.Volume = 0.6
    s.Parent = game:GetService("SoundService")
    Vis.snd = s
end)

-- damage text under the crosshair: HP and armor you took off (hits within 0.7 s are added together)
Vis.dmg = { hp = 0, armor = 0 }
Vis.dmgLabel = Instance.new("TextLabel")
Vis.dmgLabel.Name = "HitDamage"
Vis.dmgLabel.AnchorPoint = Vector2.new(0.5, 0.5)
Vis.dmgLabel.Position = UDim2.new(0.5, 0, 0.5, 50)
Vis.dmgLabel.Size = UDim2.new(0, 280, 0, 22)
Vis.dmgLabel.BackgroundTransparency = 1
Vis.dmgLabel.Font = Enum.Font.GothamBold
Vis.dmgLabel.TextSize = 16
Vis.dmgLabel.RichText = true
Vis.dmgLabel.TextColor3 = Color3.new(1, 1, 1)
Vis.dmgLabel.TextStrokeTransparency = 0.35
Vis.dmgLabel.Visible = false
Vis.dmgLabel.Parent = OverlayGui

-- armor lives in an unknown place: look for a number named armor / armour / shield (not "max")
-- on the character, humanoid and player (attributes, NumberValue, IntValue)
Vis.armorState = setmetatable({}, { __mode = "k" })

function Vis.armorName(n)
    local l = string.lower(tostring(n))
    if string.find(l, "max", 1, true) then return false end
    return string.find(l, "armor", 1, true) ~= nil or string.find(l, "armour", 1, true) ~= nil
        or string.find(l, "shield", 1, true) ~= nil
end

function Vis.findArmor(plr, char, hum)
    for _, holder in ipairs({ char, hum, plr }) do
        for name, v in pairs(holder:GetAttributes()) do
            if type(v) == "number" and Vis.armorName(name) then return { inst = holder, attr = name } end
        end
    end
    for _, d in ipairs(char:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and Vis.armorName(d.Name) then return { inst = d } end
    end
    for _, c in ipairs(plr:GetChildren()) do
        if c.Name ~= "PlayerGui" and c.Name ~= "Backpack" then
            if (c:IsA("NumberValue") or c:IsA("IntValue")) and Vis.armorName(c.Name) then return { inst = c } end
            if c:IsA("Folder") or c:IsA("Configuration") then
                for _, d in ipairs(c:GetDescendants()) do
                    if (d:IsA("NumberValue") or d:IsA("IntValue")) and Vis.armorName(d.Name) then return { inst = d } end
                end
            end
        end
    end
    return nil
end

function Vis.readArmor(plr, char, hum, now)
    local st = Vis.armorState[plr]
    if not st then
        st = { nextScan = 0 }
        Vis.armorState[plr] = st
    end
    if st.src and not st.src.inst.Parent then
        st.src = nil
        st.last = nil
    end
    if not st.src and now >= st.nextScan then
        st.nextScan = now + 5
        st.src = Vis.findArmor(plr, char, hum)
        if st.src then dbg("armor source:", plr.Name, st.src.inst:GetFullName(), st.src.attr or "") end
    end
    local v
    if st.src then
        if st.src.attr then
            v = st.src.inst:GetAttribute(st.src.attr)
        else
            v = st.src.inst.Value
        end
        if type(v) ~= "number" then v = nil end
    end
    local drop = (st.last and v and st.last > v) and (st.last - v) or 0
    st.last = v
    return drop
end

function Vis.hit(killed, hpDrop, armorDrop)
    local now0 = os.clock()
    if now0 - Vis.hitT > 0.7 then
        Vis.dmg.hp, Vis.dmg.armor = 0, 0
    end
    Vis.dmg.hp += hpDrop or 0
    Vis.dmg.armor += armorDrop or 0
    local parts = {}
    if Vis.dmg.hp > 0.05 then
        parts[#parts + 1] = string.format('<font color="#ff5a5a">-%d HP</font>', math.floor(Vis.dmg.hp + 0.5))
    end
    if Vis.dmg.armor > 0.05 then
        parts[#parts + 1] = string.format('<font color="#5aa8ff">-%d ARMOR</font>', math.floor(Vis.dmg.armor + 0.5))
    end
    if killed then parts[#parts + 1] = '<font color="#ffd24a">KILL</font>' end
    Vis.dmgLabel.Text = table.concat(parts, "  ")
    Vis.hitT = now0
    Vis.kill = killed
    if State.HitSound and Vis.snd then
        pcall(function()
            Vis.snd.TimePosition = 0
            Vis.snd:Play()
        end)
    end
end

function Vis.getArrow(plr)
    local a = Vis.arrows[plr]
    if a then return a end
    local f = Instance.new("Frame")
    f.Name = plr.Name .. "_Arrow"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.new(0, 26, 0, 26)
    f.BackgroundTransparency = 1
    f.Visible = false
    f.Parent = OverlayGui
    local bars = {}
    for i, ang in ipairs({ -38, 38 }) do
        local b = Instance.new("Frame")
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Size = UDim2.new(0, 14, 0, 3)
        b.Position = UDim2.new(0.5, i == 1 and -5 or 5, 0.5, 2)
        b.Rotation = ang
        b.BorderSizePixel = 0
        b.Parent = f
        bars[i] = b
    end
    a = { Frame = f, Bars = bars }
    Vis.arrows[plr] = a
    return a
end

track(Players.PlayerRemoving:Connect(function(plr)
    local a = Vis.arrows[plr]
    if a then
        a.Frame:Destroy()
        Vis.arrows[plr] = nil
    end
end))

function Vis.step(now)
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local shotRecently = isShooting or now - Vis.lastShot < 0.45
    if isShooting then Vis.lastShot = now end
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            -- hitmarker: health went down, we shot a moment ago, the target is near the crosshair
            if hum then
                local last = Vis.hp[hum]
                Vis.hp[hum] = hum.Health
                local hpDrop = last and math.max(last - hum.Health, 0) or 0
                local armorDrop = 0
                if State.Hitmarker and char then armorDrop = Vis.readArmor(plr, char, hum, now) end
                if State.Hitmarker and root and (hpDrop > 0.01 or armorDrop > 0.01) and shotRecently then
                    local sp, on = Camera:WorldToViewportPoint(root.Position)
                    if on and sp.Z > 0 and (Vector2.new(sp.X, sp.Y) - center).Magnitude < vp.Y * 0.4 then
                        Vis.hit(hum.Health <= 0, hpDrop, armorDrop)
                    end
                end
            end

            -- off-screen arrow
            local a = Vis.arrows[plr]
            local show = false
            if State.OffscreenArrows and root and hum and hum.Health > 0 and myRoot then
                local dist = (root.Position - myRoot.Position).Magnitude
                if dist <= State.ArrowMaxDistance then
                    local sp, on = Camera:WorldToViewportPoint(root.Position)
                    local inside = on and sp.Z > 0 and sp.X > 0 and sp.Y > 0 and sp.X < vp.X and sp.Y < vp.Y
                    if not inside then
                        local rel = Camera.CFrame:PointToObjectSpace(root.Position)
                        local mag = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
                        if mag > 1e-3 then
                            local sx, sy = rel.X / mag, rel.Z / mag -- screen right / screen down (behind = down)
                            a = a or Vis.getArrow(plr)
                            local r = State.ArrowRadius
                            a.Frame.Position = UDim2.fromOffset(center.X + sx * r, center.Y + sy * r)
                            a.Frame.Rotation = math.deg(math.atan2(sx, -sy))
                            local near = 1 - math.clamp(dist / State.ArrowMaxDistance, 0, 1)
                            local size = 20 + near * 14
                            a.Frame.Size = UDim2.fromOffset(size, size)
                            for _, b in ipairs(a.Bars) do
                                b.BackgroundColor3 = State.PlayerESPColor
                                b.BackgroundTransparency = 0.5 - near * 0.4
                            end
                            show = true
                        end
                    end
                end
            end
            if a and a.Frame.Visible ~= show then a.Frame.Visible = show end
        end
    end

    -- hitmarker fade
    local age = now - Vis.hitT
    if age >= 0 and age < 0.25 then
        local col = Vis.kill and Color3.fromRGB(255, 60, 60) or Color3.new(1, 1, 1)
        for _, l in ipairs(Vis.lines) do
            l.BackgroundColor3 = col
            l.BackgroundTransparency = age / 0.25
        end
        Vis.root.Visible = true
    elseif Vis.root.Visible then
        Vis.root.Visible = false
    end

    -- damage text: floats up and fades
    if State.HitDamageText and age >= 0 and age < 1.0 then
        Vis.dmgLabel.Position = UDim2.new(0.5, 0, 0.5, 50 - age * 22)
        Vis.dmgLabel.TextTransparency = math.clamp((age - 0.55) / 0.45, 0, 1)
        Vis.dmgLabel.TextStrokeTransparency = 0.35 + 0.65 * Vis.dmgLabel.TextTransparency
        Vis.dmgLabel.Visible = true
    elseif Vis.dmgLabel.Visible then
        Vis.dmgLabel.Visible = false
    end
end

function Vis.hideAll()
    Vis.dmgLabel.Visible = false
    Vis.root.Visible = false
    for _, a in pairs(Vis.arrows) do a.Frame.Visible = false end
end

local worldRefreshAcc = 0

track(RunService.RenderStepped:Connect(function(dt)
    if not isRunning then return end
    Camera = workspace.CurrentCamera
    if not Camera then return end

    updatePlayersESP()

    if State.Hitmarker or State.OffscreenArrows then
        pcall(Vis.step, os.clock())
        Vis.active = true
    elseif Vis.active then
        Vis.active = false
        Vis.hideAll()
    end

    worldRefreshAcc += dt
    if worldRefreshAcc >= 0.25 then
        worldRefreshAcc = 0
        refreshWorldActive()
    end
    drawWorldESP()

    updateFirstPersonAimWeapon()

    if State.AutoLockpick then
        pcall(scanLockpickMinigame)
    elseif lp.gui then
        resetLockpick()
    end
end))

---------------------------------------------------------------------
-- Extras: smart pause, nearby-player alert, triggerbot, anti-AFK
---------------------------------------------------------------------
local Ext = {
    lastCheck = 0, tbSince = nil, tbLast = 0,
    alerted = setmetatable({}, { __mode = "k" }),
    tbParams = RaycastParams.new(),
}
Ext.tbParams.FilterType = Enum.RaycastFilterType.Exclude

-- auto actions stand still at low health / while dead
function Ext.paused()
    if not State.SmartPause then return false end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or hum.MaxHealth <= 0 then return true end
    return hum.Health / hum.MaxHealth * 100 < State.PauseHealth
end

-- one notification per player when they come within the radius (re-armed after 10 s)
function Ext.danger(now)
    if now - Ext.lastCheck < 0.5 then return end
    Ext.lastCheck = now
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local d = (root.Position - myRoot.Position).Magnitude
                if d <= State.DangerRadius and now - (Ext.alerted[plr] or -99) > 10 then
                    Ext.alerted[plr] = now
                    notify("4Money - danger", plr.DisplayName .. " is " .. math.floor(d) .. " studs away")
                end
            end
        end
    end
end

-- shoots when the crosshair ray hits an enemy: the first thing hit must be the enemy (so walls block it)
-- and it must stay there for TriggerDelay ms
function Ext.trigger(now)
    local char = LocalPlayer.Character
    if isShooting or not (char and Life.settled(0.5) and hasWeaponEquipped()) then
        Ext.tbSince = nil
        return
    end
    Camera = workspace.CurrentCamera
    if not Camera then return end
    local vp = Camera.ViewportSize
    local ray = Camera:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
    Ext.tbParams.FilterDescendantsInstances = { char }
    local hit = Life.ray(ray.Origin, ray.Direction * State.TriggerDistance, Ext.tbParams)
    local onEnemy = false
    if hit then
        local model = hit.Instance:FindFirstAncestorOfClass("Model")
        local plr = model and Players:GetPlayerFromCharacter(model)
        local hum = model and model:FindFirstChildOfClass("Humanoid")
        onEnemy = plr ~= nil and plr ~= LocalPlayer and hum ~= nil and hum.Health > 0
    end
    if not onEnemy then
        Ext.tbSince = nil
        return
    end
    Ext.tbSince = Ext.tbSince or now
    if now - Ext.tbSince >= State.TriggerDelay / 1000 and now - Ext.tbLast > 0.1 then
        Ext.tbLast = now
        Vis.lastShot = now
        NF.SA.lastShot = now
        task.spawn(function()
            if mouse1click then
                pcall(mouse1click)
            else
                sendViaVIM("Mouse1")
            end
        end)
    end
end

track(LocalPlayer.Idled:Connect(function()
    if not (State.AntiAFK and isRunning) then return end
    local ok, vu = pcall(game.GetService, game, "VirtualUser")
    if ok and vu then
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new(0, 0))
        end)
    end
end))

track(RunService.Heartbeat:Connect(function()
    if not isRunning then return end
    local now = os.clock()
    if State.NoFall then
        pcall(stepNoFall)
    elseif NF.stateOff then
        pcall(NF.release)
    end
    if State.AntiFlash then pcall(AF.step, now) end
    if State.Fullbright then
        pcall(FB.step, now)
    elseif FB.orig then
        pcall(FB.restore)
    end
    if State.InfStamina and now - lastStamina > 0.1 then
        lastStamina = now
        pcall(stepStamina)
    end
    if (State.NoSpread or State.NoRecoil) and Life.alive() then
        pcall(stepNoSpread, now)
    elseif #NS.log > 0 then
        -- switched off or dead: give every changed value back before the game rebuilds its scripts
        pcall(NS.restore)
    end
    if State.SilentAim then
        if isShooting then NF.SA.lastShot = now end
        if not NF.SA.installed then
            NF.SA.installed = true
            if not NF.install() then
                notify("4Money", "Silent aim needs hookmetamethod, which this executor does not provide.")
            end
        end
    end
    local paused = Ext.paused()
    if State.AutoCash and not paused then pcall(stepAutoCash, now) end
    if State.AutoCrowbar and not paused then pcall(stepAutoCrowbar, now) end
    if State.AutoAllowance and not paused then pcall(stepAllowance, now) end
    if State.AutoBank and not paused then pcall(stepAutoBank, now) end
    if State.DangerAlert then pcall(Ext.danger, now) end
    if State.Triggerbot then pcall(Ext.trigger, now) else Ext.tbSince = nil end
end))

-- World ESP source sync (cheap: only reads three small game folders once per second)
task.spawn(function()
    while isRunning do
        pcall(syncWorld)
        task.wait(1)
    end
end)

---------------------------------------------------------------------
-- 10. Cleanup + UI
---------------------------------------------------------------------
local function cleanup()
    if not isRunning then return end
    isRunning = false

    if State.OptimizerEnabled then
        State.OptimizerEnabled = false
        pcall(applyOptimizer, false)
    end
    pcall(restoreWeaponTransparency)
    pcall(NS.restore)
    pcall(FB.restore)
    pcall(NF.release)
    pcall(Life.setSens, 1)
    pcall(function() RunService:UnbindFromRenderStep("Money4_LateRecoil") end)
    pcall(function() RunService:UnbindFromRenderStep("Money4_Aim") end)
    pcall(function() RunService:UnbindFromRenderStep("Money4_Fov") end)
    if fovOverriding then
        pcall(function() workspace.CurrentCamera.FieldOfView = baseFov end)
    end

    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    if optimizerConn then pcall(function() optimizerConn:Disconnect() end) end

    pcall(function() OverlayGui:Destroy() end)
    pcall(function() HighlightFolder:Destroy() end)
end
env.Money4Cleanup = cleanup

-- The whole menu is built inside one function: it gets its own budget of 200 local variables,
-- so the main chunk (already close to the limit) never overflows ("Out of local registers").
local function buildMenu()
local okWin, Window = pcall(function()
    return Lumen:CreateWindow({
        Name = "4Money",
        ScriptName = "4Money",
        Subtitle = "Criminality",
        IntroText = "4Money",
        DefaultBinds = true, -- every toggle and button gets a key chip
        ConfigurationSaving = {
            Enabled = Cap.files, -- needs writefile / readfile / folder functions (missing on some executors)
            FolderName = "4Money",
            FileName = "config",
        },
    })
end)
if not okWin or not Window then
    warn("[4Money] Failed to create window: " .. tostring(Window))
    cleanup()
    return
end
env.Money4Window = Window

pcall(function()
    Window:OnDestroy(cleanup)
end)

---------------------------------------------------------------------
-- Menu (4D$ UI library: tabs, folders, selector, side panel, drawer, key-bind chips)
---------------------------------------------------------------------

-- Small builders kept in one table so they do not use up local variable slots
local UI = {}

function UI.toggle(parent, name, flag, key, after)
    return parent:CreateToggle({
        Name = name,
        CurrentValue = State[key],
        Flag = flag,
        Callback = function(v)
            State[key] = v
            if after then after(v) end
        end,
    })
end

function UI.slider(parent, name, flag, key, min, max, inc, after)
    return parent:CreateSlider({
        Name = name,
        Range = { min, max },
        Increment = inc,
        CurrentValue = State[key],
        Flag = flag,
        Callback = function(v)
            State[key] = v
            if after then after(v) end
        end,
    })
end

function UI.color(parent, name, flag, key, after)
    return parent:CreateColorPicker({
        Name = name,
        Color = State[key],
        Flag = flag,
        Callback = function(c)
            State[key] = c
            if after then after(c) end
        end,
    })
end

function UI.dropdown(parent, name, flag, key, options, after)
    return parent:CreateDropdown({
        Name = name,
        Options = options,
        CurrentOption = { State[key] },
        MultipleOptions = false,
        Flag = flag,
        Callback = function(v)
            State[key] = firstOf(v) or State[key]
            if after then after(State[key]) end
        end,
    })
end

function UI.button(parent, name, fn)
    return parent:CreateButton({ Name = name, Callback = fn })
end

function UI.collectAllowanceNow()
    allowance.last = -1e9
    stepAllowance(os.clock())
end

---------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------
do -- Combat tab (own scope keeps the local-variable count low)
local CombatTab = Window:CreateTab("Combat", "sword")

local recoilFolder = CombatTab:CreateFolder({ Name = "Recoil and spread", Icon = "target", Open = true })
UI.toggle(recoilFolder, "No Recoil", "m4_no_recoil", "NoRecoil")
-- "_v2" flags: the new defaults (full cancel, no smoothing) must not be overridden by values saved earlier
UI.slider(recoilFolder, "Recoil suppression (1.0 = cancel all)", "m4_recoil_suppression_v2", "RecoilSuppression", 0.1, 1.0, 0.02)
UI.slider(recoilFolder, "Recoil smoothing (0 = instant, higher = softer)", "m4_recoil_smooth_v2", "RecoilSmooth", 0, 0.9, 0.05)
UI.toggle(recoilFolder, "Cancel camera recovery (turn off if aim creeps UP after shooting)", "m4_recoil_recovery", "RecoilRecovery")
UI.toggle(recoilFolder, "No Spread", "m4_no_spread", "NoSpread")

local aimFolder = CombatTab:CreateFolder({ Name = "Aim lock", Icon = "target" })
UI.toggle(aimFolder, "Aim lock", "m4_aim_lock", "AimLock", function() updateFovCircle() end)
UI.dropdown(aimFolder, "Aim when", "m4_aim_trigger", "AimTrigger", { "Hold RMB", "Hold LMB", "Always" })
UI.dropdown(aimFolder, "Aim at", "m4_aim_part", "AimPart", { "Head", "Torso" }, function() aimTarget = nil end)
UI.slider(aimFolder, "FOV radius (px)", "m4_aim_fov", "AimFov", 30, 700, 5, function() updateFovCircle() end)
UI.toggle(aimFolder, "Show FOV circle", "m4_show_fov", "ShowFov", function() updateFovCircle() end)
UI.color(aimFolder, "FOV circle color", "m4_aim_fov_color", "AimFovColor", function() updateFovCircle() end)
-- "_v2": an old saved "Mouse move" must not override the new default
UI.dropdown(aimFolder, "Aim method (Camera = exact, Mouse move = experimental)", "m4_aim_method_v2", "AimMethod", { "Camera", "Mouse move" }, function(v)
    if v == "Mouse move" and not Cap.mouseRel then
        notify("4Money", "This executor has no mousemoverel: 'Mouse move' will do nothing, use 'Camera'.")
    end
end)
UI.slider(aimFolder, "Mouse gain (Mouse move method)", "m4_aim_gain", "AimMouseGain", 0.2, 3.0, 0.05)
UI.slider(aimFolder, "Smoothness (1.0 = instant)", "m4_aim_smooth", "AimSmooth", 0.02, 1.0, 0.01)
UI.slider(aimFolder, "Max turn speed (deg/frame, 0 = no limit)", "m4_aim_max_step", "AimMaxStep", 0, 30, 1)
UI.slider(aimFolder, "Max target distance", "m4_aim_distance", "AimMaxDistance", 50, 1500, 25)
UI.toggle(aimFolder, "Wall check (visible targets only)", "m4_aim_wallcheck", "AimWallCheck", function() aimTarget = nil end)

local silentFolder = CombatTab:CreateFolder({ Name = "Silent aim", Icon = "target" })
UI.toggle(silentFolder, "Silent aim (bullets go to the target while the camera stays put)", "m4_silent_aim", "SilentAim", function(v)
    updateFovCircle()
    if v then installNamecallHook() end
end)
UI.dropdown(silentFolder, "Hit part", "m4_silent_part", "SilentPart", { "Head", "Torso" }, function() NF.SA.cache = nil end)
UI.slider(silentFolder, "FOV radius (px, shown as the circle)", "m4_silent_fov", "SilentFov", 30, 700, 5, function() updateFovCircle() end)
UI.slider(silentFolder, "Max distance", "m4_silent_dist", "SilentMaxDistance", 50, 1500, 25)
UI.slider(silentFolder, "Hit chance (%)", "m4_silent_chance", "SilentHitChance", 5, 100, 5)
UI.toggle(silentFolder, "Wall check (only visible targets)", "m4_silent_wall", "SilentWallCheck", function() NF.SA.cache = nil end)

local hitFolder = CombatTab:CreateFolder({ Name = "Hitmarker", Icon = "crosshair" })
UI.toggle(hitFolder, "Hitmarker (X at the crosshair when you hit someone)", "m4_hitmarker", "Hitmarker")
UI.toggle(hitFolder, "Hit sound", "m4_hit_sound", "HitSound")
UI.toggle(hitFolder, "Damage text (HP and armor you took off)", "m4_hit_damage", "HitDamageText")

local triggerFolder = CombatTab:CreateFolder({ Name = "Triggerbot", Icon = "target" })
UI.toggle(triggerFolder, "Triggerbot (shoots when the crosshair is on an enemy)", "m4_triggerbot", "Triggerbot")
UI.slider(triggerFolder, "Reaction delay (ms)", "m4_trigger_delay", "TriggerDelay", 0, 400, 5)
UI.slider(triggerFolder, "Max distance", "m4_trigger_dist", "TriggerDistance", 50, 1000, 25)

local weaponFolder = CombatTab:CreateFolder({ Name = "Weapon view", Icon = "sword" })
UI.toggle(weaponFolder, "Transparent weapon while aiming (1st person)", "m4_transparent_aim_weapon", "TransparentAimWeapon", function(v)
    if not v then
        weaponFaded = false
        restoreWeaponTransparency()
    end
end)
UI.slider(weaponFolder, "Weapon transparency (1.0 = hidden)", "m4_aim_weapon_transp", "AimWeaponTransparency", 0.2, 1.0, 0.05)
end -- Combat tab

---------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------
do -- Visuals tab
local VisualsTab = Window:CreateTab("Visuals", "eye")

-- One selector instead of five separate ESP blocks: pick a category, see only its settings
do -- ESP selector pages (inner scope frees its locals afterwards)
local esp = VisualsTab:CreateSelector({
    Name = "ESP",
    Icon = "eye",
    Options = { "Players", "Loot", "Doors", "Shops", "Outlines" },
    Flag = "m4_esp_category",
})

local pPlayers = esp:Page("Players")
UI.toggle(pPlayers, "Players: Box", "m4_player_box_esp", "PlayerBoxESP")
UI.toggle(pPlayers, "Players: Fill", "m4_player_fill_esp", "PlayerFillESP")
UI.toggle(pPlayers, "Health bar + number (needs Box)", "m4_player_health", "PlayerShowHealth")
UI.toggle(pPlayers, "Held item under the box (needs Box)", "m4_player_tool", "PlayerShowTool")
UI.toggle(pPlayers, "Tracers (needs Box)", "m4_player_tracers", "PlayerTracers")
UI.toggle(pPlayers, "Off-screen arrows (players outside your view)", "m4_offscreen_arrows", "OffscreenArrows")
UI.slider(pPlayers, "Arrow max distance", "m4_arrow_dist", "ArrowMaxDistance", 20, 500, 10)
UI.slider(pPlayers, "Arrow circle radius (px)", "m4_arrow_radius", "ArrowRadius", 80, 450, 10)
UI.slider(pPlayers, "Distance", "m4_player_dist", "PlayerMaxDistance", 50, 1000, 25)
UI.slider(pPlayers, "Fill transparency", "m4_player_fill_transp", "PlayerFillTransparency", 0.1, 0.95, 0.05)
UI.color(pPlayers, "Color", "m4_player_esp_color", "PlayerESPColor")

local pLoot = esp:Page("Loot")
UI.toggle(pLoot, "Loot ESP (safes, registers, crates)", "m4_loot_esp", "LootESP")
UI.toggle(pLoot, "Only show not-yet-opened", "m4_loot_only_available", "OnlyAvailableLoot")
UI.slider(pLoot, "Distance", "m4_loot_dist", "LootMaxDistance", 50, 1000, 25)
UI.color(pLoot, "Color", "m4_loot_esp_color", "LootESPColor")

local pDoors = esp:Page("Doors")
UI.toggle(pDoors, "Door ESP", "m4_door_esp", "DoorESP")
UI.slider(pDoors, "Distance", "m4_door_dist", "DoorMaxDistance", 50, 800, 25)
UI.color(pDoors, "Color", "m4_door_esp_color", "DoorESPColor")

local pShops = esp:Page("Shops")
UI.toggle(pShops, "Shop ESP", "m4_vendor_esp", "VendorESP")
UI.slider(pShops, "Distance", "m4_vendor_dist", "VendorMaxDistance", 50, 1000, 25)
UI.color(pShops, "Color", "m4_vendor_esp_color", "VendorESPColor")

local pOutlines = esp:Page("Outlines")
UI.toggle(pOutlines, "Outline objects (Highlight)", "m4_world_outline", "WorldOutline")
UI.slider(pOutlines, "Fill transparency (1.0 = outline only)", "m4_world_outline_fill", "WorldOutlineFill", 0.3, 1.0, 0.05)
end -- ESP selector pages

local camFolder = VisualsTab:CreateFolder({ Name = "Camera (FOV and zoom)", Icon = "eye" })
UI.toggle(camFolder, "Custom field of view", "m4_fov_enabled", "FovEnabled")
UI.slider(camFolder, "Field of view", "m4_fov_value", "FovValue", 40, 120, 1)
UI.toggle(camFolder, "Zoom on key", "m4_zoom_enabled", "ZoomEnabled", function(v)
    if not v then zoomActive = false end
end)
zoomKeybind = camFolder:CreateKeybind({
    Name = "Zoom key",
    CurrentKeybind = State.ZoomKey,
    HoldToInteract = false,
    Flag = "m4_zoom_key",
    Callback = function() end,
    OnChange = function(name)
        State.ZoomKey = name
    end,
})
UI.dropdown(camFolder, "Zoom mode", "m4_zoom_mode", "ZoomMode", { "Hold", "Toggle" }, function() zoomActive = false end)
UI.toggle(camFolder, "Slow mouse while zoomed (fixes sharp zoom)", "m4_zoom_sens", "ZoomSensScale")
UI.slider(camFolder, "Zoom sensitivity strength", "m4_zoom_sens_strength", "ZoomSensStrength", 0, 1.5, 0.05)
UI.slider(camFolder, "Zoom field of view (lower = closer)", "m4_zoom_fov", "ZoomFov", 10, 70, 1)
UI.slider(camFolder, "Zoom speed (1.0 = instant)", "m4_zoom_speed", "ZoomSpeed", 0.05, 1.0, 0.05)

local crossFolder = VisualsTab:CreateFolder({ Name = "Custom crosshair", Icon = "target" })
UI.toggle(crossFolder, "Enable crosshair", "m4_crosshair_enabled", "Crosshair", function() updateCrosshairLayout() end)
UI.toggle(crossFolder, "Center dot", "m4_crosshair_dot", "CenterDot", function() updateCrosshairLayout() end)
UI.slider(crossFolder, "Line length", "m4_crosshair_size", "CrosshairSize", 2, 24, 1, function() updateCrosshairLayout() end)
UI.slider(crossFolder, "Thickness", "m4_crosshair_thickness", "CrosshairThickness", 1, 6, 1, function() updateCrosshairLayout() end)
UI.slider(crossFolder, "Gap from center", "m4_crosshair_gap", "CrosshairGap", 0, 20, 1, function() updateCrosshairLayout() end)
UI.color(crossFolder, "Crosshair color", "m4_crosshair_color", "CrosshairColor", function() updateCrosshairLayout() end)
end -- Visuals tab

---------------------------------------------------------------------
-- Money
---------------------------------------------------------------------
do -- Money tab
local MoneyTab = Window:CreateTab("Money", "bolt")

local lockFolder = MoneyTab:CreateFolder({ Name = "Lockpick minigame", Icon = "target", Open = true })
UI.toggle(lockFolder, "Auto lockpick", "m4_auto_lockpick", "AutoLockpick")
UI.dropdown(lockFolder, "Key to press", "m4_lockpick_key", "LockpickKeyName", { "Auto", "E", "Space", "F", "R", "Q", "Mouse1" })
UI.dropdown(lockFolder, "Input method", "m4_lockpick_method", "LockpickMethod", { "Auto", "GUI click", "VirtualInput", "keypress/mouse1click", "MobileButton" })
UI.slider(lockFolder, "Timing offset (ms) - 0 is auto (1 frame). Negative = press later, positive = earlier", "m4_lockpick_latency_off", "LockpickLatencyOffset", -40, 40, 1)
UI.slider(lockFolder, "Stop after N failed presses per minigame (0 = never, saves picks)", "m4_lockpick_maxfails", "LockpickMaxFails", 0, 12, 1)
UI.slider(lockFolder, "Extra hit slack (x20 px)", "m4_lockpick_tolerance", "LockpickTolerance", 0.01, 0.25, 0.01)
UI.slider(lockFolder, "Delay between presses (sec)", "m4_lockpick_delay", "LockpickDelay", 0.01, 0.3, 0.01)
UI.slider(lockFolder, "Start delay (sec) - no press right after the minigame opens", "m4_lockpick_start", "LockpickStartDelay", 0, 2, 0.05)

local cashFolder = MoneyTab:CreateFolder({ Name = "Cash and safes", Icon = "bolt" })
UI.toggle(cashFolder, "Auto pickup dropped cash", "m4_auto_cash", "AutoCash")
UI.slider(cashFolder, "Cash pickup radius", "m4_cash_radius", "CashRadius", 4, 15, 1)
UI.toggle(cashFolder, "Auto crowbar (breaks nearest safe/register, needs a Crowbar)", "m4_auto_crowbar", "AutoCrowbar")
UI.slider(cashFolder, "Crowbar range", "m4_crowbar_range", "CrowbarRange", 5, 25, 1)

local allowFolder = MoneyTab:CreateFolder({ Name = "Allowance (from afar)", Icon = "bolt" })
UI.toggle(allowFolder, "Auto collect allowance", "m4_auto_allowance", "AutoAllowance", function(v)
    if v then
        allowance.last = 0
        scanAllowancePrompts()
    end
end)
UI.slider(allowFolder, "Check interval (sec)", "m4_allowance_interval", "AllowanceInterval", 1, 60, 1)
UI.button(allowFolder, "Fallback: start recording (collect it once by hand)", function() startLearning("Allowance") end)
UI.button(allowFolder, "Fallback: stop & save recording", function() stopLearning() end)

local bankFolder = MoneyTab:CreateFolder({ Name = "Bank to Cash (from afar)", Icon = "bolt" })
UI.button(bankFolder, "1) Start recording (then withdraw bank -> cash once at an ATM)", function() startLearning("Bank") end)
UI.button(bankFolder, "2) Stop & save recording", function() stopLearning() end)
UI.button(bankFolder, "3) Convert now (from anywhere)", function()
    if not replayMacro("Bank") then
        notify("4Money", "Nothing recorded yet. Use buttons 1 and 2 first.")
    end
end)
UI.toggle(bankFolder, "Auto convert bank -> cash", "m4_auto_bank", "AutoBank")
UI.slider(bankFolder, "Auto convert interval (sec)", "m4_bank_interval", "BankInterval", 3, 120, 1)
end -- Money tab

---------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------
do -- Misc tab
local MiscTab = Window:CreateTab("Misc", "sliders")

local charFolder = MiscTab:CreateFolder({ Name = "Character", Icon = "user", Open = true })
UI.toggle(charFolder, "Infinite stamina", "m4_inf_stamina", "InfStamina", function(v)
    if v and not Cap.getgc then
        notify("4Money", "This executor has no getgc: infinite stamina can only use the simple method.")
    end
    if v then pcall(scanStaminaSources) end
end)
UI.toggle(charFolder, "No fall damage", "m4_no_fall", "NoFall", function(v)
    if v then installNamecallHook() end
end)
UI.toggle(charFolder, "Fullbright (bright, no shadows, no fog)", "m4_fullbright", "Fullbright")
UI.toggle(charFolder, "Anti-AFK (no kick while idle)", "m4_anti_afk", "AntiAFK")
UI.toggle(charFolder, "Nearby player alert", "m4_danger_alert", "DangerAlert")
UI.slider(charFolder, "Alert radius (studs)", "m4_danger_radius", "DangerRadius", 10, 150, 5)
UI.toggle(charFolder, "Smart pause (stop auto actions at low health)", "m4_smart_pause", "SmartPause")
UI.slider(charFolder, "Pause below health (%)", "m4_pause_health", "PauseHealth", 5, 90, 5)
UI.toggle(charFolder, "Anti flashbang (no flash / blind effect)", "m4_anti_flash", "AntiFlash", function(v)
    if v then
        -- one-time sweep of GUIs that already exist
        pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then
                for _, d in ipairs(pg:GetDescendants()) do
                    if AF.nameHit(d.Name) then AF.candidate(d) end
                end
            end
        end)
    end
end)

local perfFolder = MiscTab:CreateFolder({ Name = "Performance", Icon = "settings" })
UI.toggle(perfFolder, "Optimizer (shadows / particles / post effects)", "m4_optimizer_enabled", "OptimizerEnabled", function(v)
    applyOptimizer(v)
end)

local debugFolder = MiscTab:CreateFolder({ Name = "Debug", Icon = "info" })
UI.toggle(debugFolder, "Debug output (console: lockpick, stamina, spread)", "m4_debug", "Debug")
end -- Misc tab

---------------------------------------------------------------------
-- Side panel with one-click money actions (slides out from the right edge)
---------------------------------------------------------------------
pcall(function()
    local panel = Window:CreatePanel({ Id = "money_tools", Title = "Money tools", Side = "Right", Width = 270, Height = 190 })
    UI.button(panel, "Convert bank -> cash now", function()
        if not replayMacro("Bank") then
            notify("4Money", "Nothing recorded yet (Money tab > Bank to Cash).")
        end
    end)
    UI.button(panel, "Collect allowance now", function() UI.collectAllowanceNow() end)
    UI.button(panel, "List prompts within 60 studs (debug)", function() listNearbyPrompts(60) end)
end)

-- Help drawer hanging on the left side of the window
pcall(function()
    local help = Window:CreateDrawer({ Id = "money_help", Title = "Help", Side = "Left", Icon = "info", Width = 270 })
    help:CreateParagraph({
        Title = "Key binds",
        Content = "Every toggle and button has a small key chip. Click it and press a key to bind. Esc or right-click on the chip clears it.",
    })
    help:CreateParagraph({
        Title = "Bank to Cash",
        Content = "Money tab > Bank to Cash: press 1, withdraw once at an ATM, press 2. After that 3 (or the side panel) converts from anywhere.",
    })
    help:CreateParagraph({
        Title = "Your executor: " .. Cap.name,
        Content = Cap.summary .. (Cap.mobile and "\nTouch device: Aim lock is set to 'Always'; there is no right mouse button." or "")
            .. "\nFeatures that need a missing function stay inactive; everything else works.",
    })
    help:CreateParagraph({
        Title = "Aim feels sharp?",
        Content = "Raise Recoil smoothing and lower Aim smoothness / Max turn speed in Combat.",
    })
end)

pcall(function()
    Lumen:Notify({
        Title = "4Money",
        Content = "Loaded.",
        Duration = 4,
        Type = "success",
    })
end)
end
buildMenu()
