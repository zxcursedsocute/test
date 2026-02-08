local gui = loadstring(game:HttpGet("https://raw.githubusercontent.com/zxcursedsocute/.1/refs/heads/main/test%20ne%20lib"))()

local windows = gui.CreateWindow("Forsaken script", "By zxc76945",'590','v 1.0')

local SurvivorCombatSection = windows:AddTab('Visual','Visual')
-- === НАСТРОЙКИ ===
if not ForsakenSettings then
    getgenv().ForsakenSettings = {
        SilentAimEnabled = false,
        SilentAimTargetMode = "Survivors", -- "Survivors", "Killers", "All"
        SilentAimFOV = 2000, 
    }
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- === ПОИСК ЦЕЛИ (AIM LOGIC) ===
local function GetBestTarget()
    local ClosestDist = math.huge
    local Target = nil
    local PotentialTargets = {}
    
    local function addTargets(folderName)
        local folder = workspace.Players:FindFirstChild(folderName)
        if folder then
            for _, v in pairs(folder:GetChildren()) do table.insert(PotentialTargets, v) end
        end
    end

    if ForsakenSettings.SilentAimTargetMode == "Survivors" then
        addTargets("Survivors")
    elseif ForsakenSettings.SilentAimTargetMode == "Killers" then
        addTargets("Killers")
    else
        addTargets("Survivors")
        addTargets("Killers")
    end

    local MousePos = game:GetService("UserInputService"):GetMouseLocation()
    
    for _, char in pairs(PotentialTargets) do
        if char ~= LocalPlayer.Character and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
            local RootPart = char.HumanoidRootPart
            local Dist = (LocalPlayer.Character.HumanoidRootPart.Position - RootPart.Position).Magnitude
            
            if Dist < ForsakenSettings.SilentAimFOV and Dist < ClosestDist then
                ClosestDist = Dist
                Target = RootPart
            end
        end
    end
    return Target
end

-- === ВЗЛОМ СЕТИ (HOOKING) ===

local function HookNetwork()
    local NetworkModule = ReplicatedStorage:WaitForChild("Modules"):FindFirstChild("Network")
    local RemoteFunc = NetworkModule and NetworkModule:FindFirstChild("RemoteFunction")
    
    if not RemoteFunc then return warn("Silent Aim: RemoteFunction not found!") end

    -- МЕТОД 1: Ищем таблицу обработчиков внутри модуля Network (Самый надежный)
    -- Мы пытаемся найти таблицу, где хранятся функции типа "GetMousePosition"
    local NetworkLib = require(NetworkModule)
    local HandlersTable = nil
    
    -- Сканируем функции модуля, чтобы найти спрятанную таблицу (upvalues)
    for k, v in pairs(NetworkLib) do
        if type(v) == "function" then
            local ups = debug.getupvalues(v)
            for _, up in pairs(ups) do
                if type(up) == "table" then
                    -- Проверяем, похожа ли таблица на список ивентов
                    -- "GetMousePosition" используется сервером [cite: 1, 20]
                    if up["GetMousePosition"] or up[tostring(LocalPlayer).."DusekkarGet"] then
                        HandlersTable = up
                        break
                    end
                end
            end
        end
        if HandlersTable then break end
    end

    if HandlersTable and HandlersTable["GetMousePosition"] then
        -- Мы нашли внутреннюю функцию! Подменяем её.
        local OldHandler = HandlersTable["GetMousePosition"]
        
        HandlersTable["GetMousePosition"] = function(...)
            if ForsakenSettings.SilentAimEnabled then
                local Target = GetBestTarget()
                if Target then
                    -- Возвращаем позицию врага вместо мышки
                    return Target.Position
                end
            end
            return OldHandler(...)
        end
        
        print("Silent Aim: Hooked via Network Module Table!")
        return -- Успех, выходим
    end

    -- МЕТОД 2: Используем getcallbackvalue (Если поддерживает чит)
    -- Это сработает, если первый метод не нашел таблицу
    if getcallbackvalue then
        local OldCallback = getcallbackvalue(RemoteFunc)
        if OldCallback then
            RemoteFunc.OnClientInvoke = function(...)
                local args = {...}
                if args[1] == "GetMousePosition" and ForsakenSettings.SilentAimEnabled then
                    local Target = GetBestTarget()
                    if Target then return Target.Position end
                end
                return OldCallback(...)
            end
            print("Silent Aim: Hooked via getcallbackvalue!")
            return
        end
    end

    warn("Silent Aim: Failed to hook. Your executor might be too weak.")
end

-- Запускаем хук
HookNetwork()

-- === UI ЭЛЕМЕНТЫ ===
SurvivorCombatSection:AddToggle({
    Name = 'Plasma Beam Silent Aim',
    Description = 'Redirects beam to nearest target',
    Callback = function(state)
        ForsakenSettings.SilentAimEnabled = state
        -- Повторная попытка хука при включении, если вдруг слетел
        if state then HookNetwork() end 
    end
})

SurvivorCombatSection:AddDropdown({
    Name = "Target Selection",
    Description = '',
    Options = {"Survivors", "Killers"},
    Default = "Survivors",
    Callback = function(value)
        ForsakenSettings.SilentAimTargetMode = value
    end
})
