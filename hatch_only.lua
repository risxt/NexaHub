--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║           NEXA HATCHER — Standalone Hatch + Enchant Script                 ║
    ╠═══════════════════════════════════════════════════════════════════════════╣
    ║  Features:                                                                ║
    ║    • Auto Hatch (x1/x3/x8) with Dynamic Egg Discovery                   ║
    ║    • Auto Enchant with Target Detection + Auto Stop                      ║
    ║    • Quick Action: Teleport to Lucky Event                               ║
    ║    • Anti-AFK + Auto Rejoin                                              ║
    ║    • Black Screen AFK Mode (End key toggle)                              ║
    ║    • Mobile Toggle Button                                                ║
    ║    • SaveManager Config Persistence                                      ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════════════
-- [SEC-CORE] SERVICES & CORE VARIABLES
-- ═══════════════════════════════════════════════════════════════════════════
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local Player = Players.LocalPlayer

-- UI Libraries (Load Once)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

print("[SEC-CORE] Services loaded successfully")

-- ═══════════════════════════════════════════════════════════════════════════
-- [SEC-CONFIG] SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════
_G.HatchSettings = {
    AutoHatch = false,
    TargetEgg = nil,
    HatchDelay = 0.1,
    HatchAmount = 1,
}

_G.EnchantSettings = _G.EnchantSettings or {
    TargetPet = "",
    TargetPetUUID = nil,
    TargetEnchant = "Secret Hunter",
    Speed = 0.001,
    AutoStop = true,
    AutoEnchant = false,
}

print("[SEC-CONFIG] Settings initialized")

-- ═══════════════════════════════════════════════════════════════════════════
-- [SEC-ANTIAFK] SUPER ANTI-AFK V2 & AUTO REJOIN
-- ═══════════════════════════════════════════════════════════════════════════
task.spawn(function()
    print("[SEC-ANTIAFK] Loading Aggressive Anti-AFK...")
    
    -- 1. Deteksi Idle (Saat Roblox mendeteksi diam 20 menit)
    Player.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(), workspace.CurrentCamera.CFrame)
        print("[SEC-ANTIAFK] Idled Triggered - Resetting Timer")
    end)
    
    -- 2. Pulse Loop (Memaksa input setiap 60 detik sebagai cadangan)
    task.spawn(function()
        while true do
            task.wait(60)
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end)
    
    -- 3. Auto Rejoin (Jika terkena Kick/Disconnect)
    task.spawn(function()
        CoreGui.ChildAdded:Connect(function(child)
            if child.Name == "RobloxPromptGui" then
                warn("[SEC-ANTIAFK] Disconnected! Rejoining in 5s...")
                task.wait(5)
                TeleportService:Teleport(game.PlaceId, Player)
            end
        end)
    end)
end)

print("[SEC-ANTIAFK] Anti-AFK armed")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-NET] NETWORK WRAPPER (SAFE MODE)
-- ═══════════════════════════════════════════════════════════════════════════
local NetworkMod = {}
do
    local _RS = game:GetService("ReplicatedStorage")

    function NetworkMod:GetRemote(name)
        local target = _RS:FindFirstChild("Functions") and _RS.Functions:FindFirstChild(name)
        if not target then
            for _, v in pairs(_RS:GetDescendants()) do
                if v.Name == name and (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) then
                    return v
                end
            end
        end
        return target
    end

    function NetworkMod:FireServer(remoteName, ...)
        local args = {...}
        local remote = self:GetRemote(remoteName)
        if remote and remote:IsA("RemoteEvent") then
            pcall(function() remote:FireServer(unpack(args)) end)
        end
    end

    function NetworkMod:InvokeServer(remoteName, ...)
        local args = {...}
        local remote = self:GetRemote(remoteName)
        if remote then
            if remote:IsA("RemoteFunction") then
                local success, res = pcall(function() return remote:InvokeServer(unpack(args)) end)
                if success then return res else warn("[NET-FAIL] Invoke Error: " .. remoteName) end
            elseif remote:IsA("RemoteEvent") then
                remote:FireServer(unpack(args))
                return true
            end
        end
        return nil
    end
end

print("[MOD-NET] Network modules loaded")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-TASKMANAGER] CENTRAL LOOP CONTROLLER
-- ═══════════════════════════════════════════════════════════════════════════
local TaskManager = {}
do
    local _registry = {}

    function TaskManager.Start(id, func)
        if _registry[id] then 
            task.cancel(_registry[id])
            _registry[id] = nil
        end
        _registry[id] = task.spawn(function()
            local success, err = pcall(func)
            if not success then
                warn("[TASK-CRASH] Task '" .. id .. "' failed: " .. tostring(err))
            end
        end)
    end

    function TaskManager.Stop(id)
        if _registry[id] then
            task.cancel(_registry[id])
            _registry[id] = nil
        end
    end
end

print("[MOD-TASKMANAGER] Ready")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-TELEPORT] ISLAND TELEPORT (LUCKY EVENT)
-- ═══════════════════════════════════════════════════════════════════════════
local Islands = {}
do
    Islands.Locations = {
        ["Forest"]      = CFrame.new(-235, 1225, 269), 
        ["Winter"]      = CFrame.new(-258, 2546, 354),
        ["Desert"]      = CFrame.new(-95, 3510, 336), 
        ["Jungle"]      = CFrame.new(-304, 4421, 420),
        ["Heaven"]      = CFrame.new(-397, 5847, 266), 
        ["Dojo"]        = CFrame.new(-402, 7626, 385),
        ["Volcano"]     = CFrame.new(-281, 9192, 146), 
        ["Candy"]       = CFrame.new(-202, 10969, 399),
        ["Atlantis"]    = CFrame.new(-432, 12950, 266), 
        ["Space"]       = CFrame.new(-278, 15334, 440),
        ["World 2"]     = CFrame.new(1279, 651, -13267), 
        ["Kryo"]        = CFrame.new(1387, 1741, -13233),
        ["Magma"]       = CFrame.new(1430, 3120, -12970), 
        ["Celestial"]   = CFrame.new(1260, 4164, -12939),
        ["Holographic"] = CFrame.new(1427, 5354, -12718), 
        ["Lunar"]       = CFrame.new(1472, 6855, -12914),
        ["Cyberpunk"]   = CFrame.new(1348.8, 8915.0, -13397.7),
        ["Lucky Event"] = CFrame.new(-177.407, 214.149, 234.651)
    }

    function Islands.teleportTo(name)
        local Plr = Players.LocalPlayer
        if not Plr.Character or not Plr.Character:FindFirstChild("HumanoidRootPart") then return end
        local Root = Plr.Character.HumanoidRootPart

        -- METHOD 1: PHYSICAL BYPASS (PRIORITY FOR LUCKY EVENT)
        if name == "Lucky Event" and Islands.Locations["Lucky Event"] then
            print("[ISLANDS] Force Teleporting to Lucky Event...")
            Root.CFrame = Islands.Locations["Lucky Event"] + Vector3.new(0, 5, 0)
            return 
        end

        -- METHOD 2: REMOTE TELEPORT
        local success = pcall(function() NetworkMod:InvokeServer("TeleportZone", name) end)
        
        -- METHOD 3: FALLBACK PHYSICAL
        if not success then
            local zonePoint = workspace.Zones:FindFirstChild(name .. "TpPoint") or workspace.Zones:FindFirstChild(name)
            if zonePoint then
                local targetCF = zonePoint:IsA("BasePart") and zonePoint.CFrame or zonePoint:GetPivot()
                Root.CFrame = targetCF + Vector3.new(0, 5, 0)
            else
                local cf = Islands.Locations[name]
                if cf then Root.CFrame = cf + Vector3.new(0, 5, 0) end
            end
        end
    end
end

print("[MOD-TELEPORT] Island teleport ready")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-EGGS] AUTO HATCH (NON-BLOCKING / SPAM MODE)
-- ═══════════════════════════════════════════════════════════════════════════
local Eggs = {}
do
    -- DYNAMIC EGG DISCOVERY (reads directly from game's Eggs module)
    -- Filters out: Expired events, Robux eggs, Exclusive eggs
    function Eggs.discover()
        local list = {}
        local ok, EggsModule = pcall(function()
            return require(game:GetService("ReplicatedStorage").Game.Eggs)
        end)
        
        if ok and EggsModule then
            local indexed = {}
            for name, data in pairs(EggsModule) do
                if type(data) == "table" and data.Pets 
                   and not data.Expired 
                   and not data.RobuxEgg 
                   and not data.Exclusive then
                    table.insert(indexed, {name = name, index = data.Index or 999})
                end
            end
            table.sort(indexed, function(a, b) return a.index < b.index end)
            for _, entry in ipairs(indexed) do
                table.insert(list, entry.name)
            end
            print("[EGGS] Dynamic discovery: found " .. #list .. " active eggs")
        else
            list = {"Basic", "Forest", "Lucky Event"}
            warn("[EGGS] Failed to load Eggs module, using fallback list")
        end
        
        return list
    end
    
    function Eggs.toggle(state)
        _G.HatchSettings.AutoHatch = state
        
        if state then
            TaskManager.Start("AutoHatch", function()
                while _G.HatchSettings.AutoHatch do
                    local eggName = _G.HatchSettings.TargetEgg
                    local amount = _G.HatchSettings.HatchAmount or 1
                    
                    if eggName then
                        task.spawn(function()
                            NetworkMod:InvokeServer("OpenEgg", eggName, amount)
                        end)
                    end
                    
                    task.wait(_G.HatchSettings.HatchDelay or 0.1)
                end
            end)
        else
            TaskManager.Stop("AutoHatch")
        end
    end
end

print("[MOD-EGGS] Auto Hatch ready")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-BLACKSCREEN] AFK BLACK SCREEN MODE (END KEY TOGGLE)
-- ═══════════════════════════════════════════════════════════════════════════
local BlackScreen = {}
do
    local _active = false

    -- Create Black Screen GUI
    local BlackGui = Instance.new("ScreenGui", CoreGui)
    BlackGui.Name = "NexaHatcherBlackScreen"
    BlackGui.IgnoreGuiInset = true
    BlackGui.Enabled = false

    local BlackFrame = Instance.new("Frame", BlackGui)
    BlackFrame.Size = UDim2.new(1, 0, 1, 0)
    BlackFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    BlackFrame.ZIndex = 9999

    local StatusText = Instance.new("TextLabel", BlackFrame)
    StatusText.Size = UDim2.new(1, 0, 1, 0)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "AFK MODE ACTIVE\n(3D Rendering Off - FPS Capped to 25)\n\nPress [End] to exit"
    StatusText.TextColor3 = Color3.fromRGB(150, 150, 150)
    StatusText.TextSize = 20
    StatusText.Font = Enum.Font.GothamBold

    -- Potato Graphics (strip all visual effects)
    local function setPotatoGraphics()
        pcall(function()
            local L = game:GetService("Lighting")
            L.GlobalShadows = false
            L.FogEnd = 9e9
            for _, v in pairs(L:GetChildren()) do 
                if v:IsA("PostEffect") or v:IsA("Sky") or v:IsA("Atmosphere") then v:Destroy() end 
            end
            for _, v in pairs(workspace:GetDescendants()) do
                if v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then 
                    v.Material = Enum.Material.SmoothPlastic 
                    v.CastShadow = false
                elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("ParticleEmitter") then 
                    v:Destroy() 
                end
            end
        end)
    end

    local _uiToggleRef = nil -- Will be set after UI is created

    function BlackScreen.setToggleRef(ref)
        _uiToggleRef = ref
    end

    function BlackScreen.toggle(state)
        _active = state
        BlackGui.Enabled = state
        pcall(function() RunService:Set3dRenderingEnabled(not state) end)
        if state then
            setPotatoGraphics()
            pcall(function() setfpscap(25) end)
            print("[BLACKSCREEN] AFK Mode ON — FPS capped to 25")
        else
            pcall(function() setfpscap(60) end)
            print("[BLACKSCREEN] AFK Mode OFF — FPS restored to 60")
        end
    end

    function BlackScreen.isActive()
        return _active
    end

    -- KEYBOARD HOTKEY: End key
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.End then
            local newState = not _active
            BlackScreen.toggle(newState)
            -- Sync UI toggle if exists
            if _uiToggleRef then
                pcall(function() _uiToggleRef:SetValue(newState) end)
            end
        end
    end)
end

print("[MOD-BLACKSCREEN] AFK Mode ready (Press End to toggle)")

-- ═══════════════════════════════════════════════════════════════════════════
-- [MOD-ENCHANT] AUTO ENCHANT (DUAL-SYNC + HIDDEN PETS EQUIP DETECTION)
-- ═══════════════════════════════════════════════════════════════════════════
local Enchant = {}
do
    local _petDisplayMap = {}
    
    -- [METHOD 1] Local Data — FAST, for UI init (never blocks)
    local function getLocalPets()
        local ok, Rep = pcall(function() return require(game:GetService("ReplicatedStorage").Game.Replication) end)
        if ok and Rep and Rep.Data and Rep.Data.Pets then
            return Rep.Data.Pets
        end
        return {}
    end
    
    -- [METHOD 2] Server Data — FRESH, for Refresh button
    local function getServerPets()
        local success, result = pcall(function()
            return NetworkMod:InvokeServer("GetPetList")
        end)
        
        if success and result and type(result) == "table" then
            print("[ENCHANT] Server sync success (GetPetList)!")
            return result
        else
            warn("[ENCHANT] GetPetList failed, falling back to local...")
            return getLocalPets()
        end
    end

    function Enchant.getAllPets(fromServer)
        local list = {}
        _petDisplayMap = {}
        
        -- Load Calculator Module
        local okStats, PetStats = pcall(function() return require(game:GetService("ReplicatedStorage").Game.PetStats) end)
        
        -- Pick data source: Server (Refresh) or Local (Init)
        local petsData
        if fromServer then
            petsData = getServerPets()
        else
            petsData = getLocalPets()
        end
        
        -- Number Abbreviation Helper
        local function abbr(n)
            if n >= 1e15 then return string.format("%.2fQd", n / 1e15)
            elseif n >= 1e12 then return string.format("%.2fT", n / 1e12)
            elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
            elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
            elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
            else return string.format("%.0f", n) end
        end
        
        if petsData and type(petsData) == "table" then
            local allPets = {}
            local eqCount = 0
            
            for id, data in pairs(petsData) do
                if type(data) == "table" then
                    local name = (data.Nickname or data.Name or "Unknown"):gsub("<[^>]+>", "")
                    local tier = data.Tier or "Normal"
                    local enchant = data.Enchant
                    
                    -- [FIX] Trust server data directly, not Hidden Pets folder
                    local isEquipped = data.Equipped or false
                    if isEquipped then eqCount = eqCount + 1 end
                    
                    -- Calculate Multiplier
                    local finalMulti = 1
                    if okStats and PetStats then
                        pcall(function()
                            local base1 = data.Multi1
                            if not base1 or base1 == 0 then
                                base1 = PetStats:GetMultiplier(data.Name, 1) or 1
                            end
                            finalMulti = PetStats:GetMulti(base1, tier, data.Level or 0, data)
                        end)
                    end
                    
                    table.insert(allPets, {
                        id = id, 
                        name = name, 
                        tier = tier,
                        enchant = enchant, 
                        multi = finalMulti,
                        equipped = isEquipped
                    })
                end
            end
            
            -- Sort: Equipped pets first, then by multiplier desc
            table.sort(allPets, function(a, b) 
                if a.equipped and not b.equipped then return true end
                if not a.equipped and b.equipped then return false end
                return a.multi > b.multi 
            end)
            
            -- Build Display List
            for i, pet in ipairs(allPets) do
                local multiStr = "x" .. abbr(pet.multi)
                local enchantStr = (pet.enchant and pet.enchant ~= "") and ("; " .. pet.enchant) or ""
                local eqTag = pet.equipped and "[EQ] " or ""
                
                local display = string.format("%s%s (%s)%s", eqTag, pet.name, multiStr, enchantStr)
                
                _petDisplayMap[display] = pet.id
                table.insert(list, display)
            end
            local src = fromServer and "Server" or "Local"
            print("[ENCHANT] " .. src .. " sync done. Equipped: " .. eqCount .. ", Total: " .. #allPets)
        end
        
        if #list == 0 then table.insert(list, "No Pets Found") end
        return list
    end

    function Enchant.setTarget(val) 
        _G.EnchantSettings.TargetPetUUID = _petDisplayMap[val] 
    end
    function Enchant.setEnchant(val) _G.EnchantSettings.TargetEnchant = val end

    function Enchant.toggle(state)
        _G.EnchantSettings.AutoEnchant = state
        if state then
            if not _G.EnchantSettings.TargetPetUUID then
                warn("[ENCHANT] Select a pet first!")
                pcall(function() Fluent:Notify({Title = "Enchant", Content = "Select a pet first!", Duration = 3}) end)
                return
            end

            TaskManager.Start("AutoEnchant", function()
                local Network = require(game:GetService("ReplicatedStorage").Modules.Network)
                local Rep = require(game:GetService("ReplicatedStorage").Game.Replication)
                local Signal = require(game:GetService("ReplicatedStorage").Modules.Signal)
                local targetUUID = _G.EnchantSettings.TargetPetUUID
                local targetEnchant = _G.EnchantSettings.TargetEnchant
                
                print("[ENCHANT] Starting Max Speed Mode (Latency Limit)...")

                while _G.EnchantSettings.AutoEnchant do
                    local success, resultEnchant = pcall(function()
                        return Network:InvokeServer("EnchantPet", targetUUID)
                    end)
                    
                    if success then
                        if resultEnchant == targetEnchant then
                            print("[ENCHANT] JACKPOT! Server confirmed: " .. tostring(resultEnchant))
                            
                            -- [VISUAL FIX] Force-update local client data to match server
                            pcall(function()
                                -- Update local Replication data
                                if Rep.Data.Pets[targetUUID] then
                                    Rep.Data.Pets[targetUUID].Enchant = resultEnchant
                                end
                                
                                -- Fire game's internal signal to refresh inventory UI
                                -- This tricks the game into thinking the server just sent an update
                                Signal.Fire("UpdatePetData", Rep.Data.Pets[targetUUID])
                            end)
                            
                            pcall(function()
                                Fluent:Notify({
                                    Title = "Enchant Done!", 
                                    Content = "GOT " .. tostring(resultEnchant) .. "! 🎉", 
                                    Duration = 5
                                })
                            end)
                            
                            _G.EnchantSettings.AutoEnchant = false
                            break
                        end
                    else
                        warn("[ENCHANT] Timeout. Retrying...")
                        task.wait(0.5)
                    end
                    
                    -- [SPEED] No artificial delay — InvokeServer already rate-limits by ping
                    task.wait()
                end
                
                task.defer(function() _G.EnchantSettings.AutoEnchant = false end)
            end)
        else
            TaskManager.Stop("AutoEnchant")
        end
    end
end

print("[MOD-ENCHANT] Auto Enchant ready")

-- ═══════════════════════════════════════════════════════════════════════════
-- [UI-MAIN] FLUENT UI SETUP
-- ═══════════════════════════════════════════════════════════════════════════
local Window = Fluent:CreateWindow({
    Title = "Nexa",
    SubTitle = "  · Hatcher",
    TabWidth = 160,
    Size = UDim2.fromOffset(480, 360),
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Hatcher", Icon = "egg" }),
    Enchant = Window:AddTab({ Title = "Enchant", Icon = "star" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- ═══ TAB: HATCHER ═══
Tabs.Main:AddParagraph({Title = "Quick Actions", Content = ""})

Tabs.Main:AddButton({
    Title = "Teleport to Lucky Event", 
    Callback = function()
        Islands.teleportTo("Lucky Event")
    end
})

Tabs.Main:AddParagraph({Title = "Egg Hatching", Content = ""})

local eggList = Eggs.discover()
local EggDropdownRef = Tabs.Main:AddDropdown("EggSelect", {
    Title = "Target Egg", 
    Values = eggList, 
    Default = nil
})
EggDropdownRef:OnChanged(function(v) _G.HatchSettings.TargetEgg = v end)
task.defer(function() EggDropdownRef:SetValue(nil) end)

Tabs.Main:AddButton({
    Title = "Refresh Egg List", 
    Callback = function()
        local newList = Eggs.discover()
        EggDropdownRef:SetValues(newList)
        Fluent:Notify({Title = "Eggs", Content = "Refreshed! Found " .. #newList .. " eggs.", Duration = 3})
    end
})

Tabs.Main:AddDropdown("HatchMode", {
    Title = "Hatch Mode",
    Values = {"x1 (Single)", "x3 (Triple)", "x8 (Octuple)"},
    Default = "x1 (Single)",
}):OnChanged(function(Value)
    if Value == "x1 (Single)" then
        _G.HatchSettings.HatchAmount = 1
    elseif Value == "x3 (Triple)" then
        _G.HatchSettings.HatchAmount = 3
    elseif Value == "x8 (Octuple)" then
        _G.HatchSettings.HatchAmount = 8
    end
    print("[EGGS] Hatch Mode: x" .. _G.HatchSettings.HatchAmount)
end)

Tabs.Main:AddSlider("HatchDelay", {
    Title = "Hatch Delay (seconds)",
    Description = "Lower = faster hatching, higher = less lag",
    Min = 0,
    Max = 2,
    Default = 0.1,
    Rounding = 2,
}):OnChanged(function(v)
    _G.HatchSettings.HatchDelay = v
end)

Tabs.Main:AddToggle("AutoHatch", {
    Title = "Auto Hatch", 
    Default = false
}):OnChanged(function(v) Eggs.toggle(v) end)

Tabs.Main:AddParagraph({Title = "AFK Mode", Content = ""})

local BlackScreenToggle = Tabs.Main:AddToggle("BlackScreenMode", {
    Title = "Black Screen (AFK)", 
    Description = "Covers screen, disables 3D, caps FPS to 25. Hotkey: End",
    Default = false
})
BlackScreenToggle:OnChanged(function(v) BlackScreen.toggle(v) end)
BlackScreen.setToggleRef(BlackScreenToggle)

-- ═══ TAB: ENCHANT ═══
Tabs.Enchant:AddParagraph({Title = "Auto Enchant", Content = ""})

local petList = Enchant.getAllPets()
local PetDrop = Tabs.Enchant:AddDropdown("PetSelect", {
    Title = "Select Pet", 
    Description = "Shows all pets with [EQ] tag for equipped ones", 
    Values = petList, 
    Default = nil
})
PetDrop:OnChanged(function(v) Enchant.setTarget(v) end)

Tabs.Enchant:AddButton({
    Title = "🔄 Refresh Pets (Server Sync)", 
    Callback = function()
        local newList = Enchant.getAllPets(true)
        PetDrop:SetValues(newList)
        Fluent:Notify({Title = "Enchant", Content = "Server Sync: " .. #newList .. " pets loaded", Duration = 2})
    end
})

-- Dynamic enchant list from game data
local enchantValues = {}
do
    local ok, EnchantData = pcall(function()
        return require(game:GetService("ReplicatedStorage").Game.EnchantData)
    end)
    if ok and EnchantData and EnchantData.Contents then
        for name, _ in pairs(EnchantData.Contents) do
            table.insert(enchantValues, name)
        end
        table.sort(enchantValues)
        print("[ENCHANT] Dynamic discovery: found " .. #enchantValues .. " enchants")
    else
        enchantValues = {"Secret Hunter", "Rainbow Hunter", "Golden Hunter", "Luck III"}
        warn("[ENCHANT] Failed to load EnchantData, using fallback list")
    end
end

Tabs.Enchant:AddDropdown("TargetEnchant", {
    Title = "Target Enchant", 
    Description = "Will stop when this enchant is rolled", 
    Values = enchantValues, 
    Default = "Secret Hunter"
}):OnChanged(function(v) Enchant.setEnchant(v) end)

Tabs.Enchant:AddToggle("StartEnchant", {
    Title = "Start Auto Enchant", 
    Default = false
}):OnChanged(function(v) Enchant.toggle(v) end)

-- ═══ TAB: SETTINGS ═══
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("NexaHatcher")
SaveManager:SetFolder("NexaHatcher/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

if not SaveManager:LoadAutoloadConfig() then
    Fluent:SetTheme("Darker")
end

Window:SelectTab(1)
Fluent:Notify({Title = "Ready", Content = "Nexa Hatcher Loaded!", Duration = 3})

print("═══════════════════════════════════════")
print("  NEXA HATCHER — Standalone")
print("  Features: Hatch + Enchant + TP + Anti-AFK + BlackScreen")
print("  Hotkey: End = Toggle Black Screen")
print("═══════════════════════════════════════")

-- ═══════════════════════════════════════════════════════════════════════════
-- [UI-MOBILE] MOBILE TOGGLE BUTTON
-- ═══════════════════════════════════════════════════════════════════════════
do
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NexaHatcherToggle"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    local existing = Player.PlayerGui:FindFirstChild("NexaHatcherToggle")
    if existing then existing:Destroy() end
    
    ScreenGui.Parent = Player.PlayerGui

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Name = "MobileToggle"
    ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
    ToggleBtn.Position = UDim2.new(0, 10, 0.5, -25)
    ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    ToggleBtn.BackgroundTransparency = 0.3
    ToggleBtn.Text = "🥚"
    ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    ToggleBtn.TextSize = 24
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.Parent = ScreenGui
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 12)
    Corner.Parent = ToggleBtn

    local dragging, dragStart, startPos = false, nil, nil
    local dragThreshold = 5

    ToggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragStart = input.Position
            startPos = ToggleBtn.Position
        end
    end)

    ToggleBtn.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            if dragStart then
                local delta = input.Position - dragStart
                if delta.Magnitude > dragThreshold then
                    dragging = true
                    ToggleBtn.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y
                    )
                end
            end
        end
    end)

    ToggleBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if not dragging then
                Window:Minimize()
            end
            dragStart = nil
            dragging = false
        end
    end)
    
    print("[UI-MOBILE] Mobile toggle button ready")
end
