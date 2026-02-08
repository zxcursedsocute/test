local gui = loadstring(game:HttpGet("https://raw.githubusercontent.com/zxcursedsocute/.1/refs/heads/main/test%20ne%20lib"))()

local windows = gui.CreateWindow("Forsaken script", "By zxc76945",'590','v 1.0')

local SurvivorCombatSection = windows:AddTab('Visual','Visual')
if not ForsakenSettings then
    getgenv().ForsakenSettings = {
        SilentAimEnabled = false,
        SilentAimTargetMode = "Survivors", -- "Survivors", "Killers", "All"
        SilentAimFOV = 500, -- Радиус действия (опционально)
    }
end

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- UI Elements (Добавьте это в секцию SurvivorCombatSection)
SurvivorCombatSection:AddSection('Dusekkar Silent Aim')

SurvivorCombatSection:AddToggle({
    Name = 'Enable Silent Aim (Plasma Beam)',
    Description = 'Automatically aims the Plasma Beam at the target.',
    Callback = function(state)
        ForsakenSettings.SilentAimEnabled = state
    end
})

SurvivorCombatSection:AddDropdown({
    Name = "Target Selection",
    Description = 'Choose who to aim at.',
    Options = {"Survivors", "Killers", "Closest"},
    Default = "Survivors",
    Callback = function(value)
        ForsakenSettings.SilentAimTargetMode = value
    end
})
local function GetBestTarget()
    local ClosestDist = math.huge
    local Target = nil
    
    local PotentialTargets = {}
    
    -- Выбираем папки игроков в зависимости от настройки
    if ForsakenSettings.SilentAimTargetMode == "Survivors" then
        if workspace.Players:FindFirstChild("Survivors") then
            for _, v in pairs(workspace.Players.Survivors:GetChildren()) do table.insert(PotentialTargets, v) end
        end
    elseif ForsakenSettings.SilentAimTargetMode == "Killers" then
        if workspace.Players:FindFirstChild("Killers") then
            for _, v in pairs(workspace.Players.Killers:GetChildren()) do table.insert(PotentialTargets, v) end
        end
    else -- Closest / All
        if workspace.Players:FindFirstChild("Survivors") then
            for _, v in pairs(workspace.Players.Survivors:GetChildren()) do table.insert(PotentialTargets, v) end
        end
        if workspace.Players:FindFirstChild("Killers") then
            for _, v in pairs(workspace.Players.Killers:GetChildren()) do table.insert(PotentialTargets, v) end
        end
    end

    local MousePos = game:GetService("UserInputService"):GetMouseLocation()
    
    for _, char in pairs(PotentialTargets) do
        -- Проверки: это не мы, персонаж жив, есть HumanoidRootPart
        if char ~= LocalPlayer.Character and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
            local RootPart = char.HumanoidRootPart
            local ScreenPos, OnScreen = workspace.CurrentCamera:WorldToViewportPoint(RootPart.Position)
            
            -- Если нужна проверка на видимость (FOV) или просто дистанцию
            local Dist = (LocalPlayer.Character.HumanoidRootPart.Position - RootPart.Position).Magnitude
            
            if Dist < ClosestDist then
                ClosestDist = Dist
                Target = RootPart
            end
        end
    end
    
    return Target
end
local NetworkModule = ReplicatedStorage:WaitForChild("Modules"):FindFirstChild("Network")
local RemoteFunc = NetworkModule and NetworkModule:FindFirstChild("RemoteFunction")

if RemoteFunc then
    -- Сохраняем оригинальную функцию (если она была)
    local OldOnClientInvoke = RemoteFunc.OnClientInvoke
    
    RemoteFunc.OnClientInvoke = function(...)
        local args = {...}
        local key = args[1] -- Обычно первый аргумент - это название запроса (например "GetMousePosition")
        
        -- Проверяем, включен ли чит и запрашивает ли сервер позицию мыши
        if ForsakenSettings.SilentAimEnabled and key == "GetMousePosition" then
            local TargetPart = GetBestTarget()
            
            if TargetPart then
                -- Возвращаем позицию врага вместо позиции мыши
                -- Можно добавить Random Spread (разброс), если нужно, но для Plasma Beam лучше точность
                return TargetPart.Position
            end
        end
        
        -- Если это не наш запрос или цель не найдена, возвращаем оригинал или позицию мыши
        if OldOnClientInvoke then
            return OldOnClientInvoke(...)
        end
        
        -- Фоллбэк (стандартное поведение), если оригинальной функции не было
        if key == "GetMousePosition" then
            local mouse = LocalPlayer:GetMouse()
            return mouse.Hit.Position
        end
        
        return nil
    end
    
    print("Silent Aim Hooked successfully!")
else
    warn("Could not find RemoteFunction in Modules.Network")
end
