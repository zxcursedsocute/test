local gui = loadstring(game:HttpGet("https://raw.githubusercontent.com/zxcursedsocute/.1/refs/heads/main/test%20ne%20lib"))()

local windows = gui.CreateWindow("Forsaken script", "By zxc76945",'590','v 1.0')

local SurvivorCombatSection = windows:AddTab('Visual','Visual')
-- === НАСТРОЙКИ (Добавь в начало или используй существующие) ===
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

-- === ЛОГИКА ПОИСКА ЦЕЛИ ===
local function GetBestTarget()
    local ClosestDist = math.huge
    local Target = nil
    
    local PotentialTargets = {}
    
    -- Сбор целей
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
            -- Дистанция от персонажа до цели
            local Dist = (LocalPlayer.Character.HumanoidRootPart.Position - RootPart.Position).Magnitude
            
            -- Можно добавить проверку на экран, если нужно, но для Plasma Beam важнее дистанция в мире
            if Dist < ForsakenSettings.SilentAimFOV and Dist < ClosestDist then
                ClosestDist = Dist
                Target = RootPart
            end
        end
    end
    
    return Target
end

-- === ПЕРЕХВАТ (HOOK) ===
-- Ищем RemoteFunction в папке Network. Обычно он называется "RemoteFunction" или "RF".
local NetworkModule = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network")
local TargetRemoteFunc = NetworkModule:FindFirstChildOfClass("RemoteFunction")

if TargetRemoteFunc then
    -- Сохраняем оригинальную функцию (если она была)
    local OldOnClientInvoke = TargetRemoteFunc.OnClientInvoke
    
    -- Переопределяем функцию ответа
    TargetRemoteFunc.OnClientInvoke = function(...)
        local args = {...}
        
        -- Выводим в консоль (F9), чтобы проверить, работает ли хук вообще
        -- Если в консоли появится этот принт при выстреле, значит хук работает!
        -- print("[SilentAim Debug] Server asked for:", args[1])

        -- Проверка запроса от сервера (строка 441 в серверном скрипте)
        if args[1] == "GetMousePosition" and ForsakenSettings.SilentAimEnabled then
            local TargetPart = GetBestTarget()
            if TargetPart then
                -- Возвращаем позицию врага вместо курсора
                return TargetPart.Position
            end
        end
        
        -- Если это другой запрос или цель не найдена
        if OldOnClientInvoke then
            return OldOnClientInvoke(...)
        end
        
        -- Стандартное поведение (если оригинала не было)
        if args[1] == "GetMousePosition" then
            local mouse = LocalPlayer:GetMouse()
            return mouse.Hit.Position
        end
        
        return nil
    end
    
    -- Уведомление для тебя
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Silent Aim";
        Text = "Hooked successfully!";
        Duration = 5;
    })
else
    warn("НЕ НАЙДЕН RemoteFunction в Modules.Network! Silent Aim не будет работать.")
end

-- === UI (Добавь в свою таблицу) ===
local SilentAimToggle = SurvivorCombatSection:AddToggle({
    Name = 'Dusekkar Silent Aim',
    Description = 'Redirects Plasma Beam to nearest target',
    Callback = function(state)
        ForsakenSettings.SilentAimEnabled = state
    end
})

local TargetDropdown = SurvivorCombatSection:AddDropdown({
    Name = "Silent Aim Target",
    Description = '',
    Options = {"Survivors", "Killers"},
    Default = "Survivors",
    Callback = function(value)
        ForsakenSettings.SilentAimTargetMode = value
    end
})
