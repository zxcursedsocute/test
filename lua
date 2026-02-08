-- === НАСТРОЙКИ ===
getgenv().ForsakenSettings = {
    SilentAimEnabled = true,
    SilentAimTargetMode = "Killers", -- "Survivors" или "Killers"
    SilentAimFOV = 1000, 
}

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

-- === ФУНКЦИЯ ПОИСКА ЦЕЛИ ===
local function GetBestTarget()
    local ClosestDist = ForsakenSettings.SilentAimFOV
    local Target = nil
    local folder = workspace.Players:FindFirstChild(ForsakenSettings.SilentAimTargetMode)
    
    if folder then
        for _, char in pairs(folder:GetChildren()) do
            if char ~= LocalPlayer.Character and char:FindFirstChild("HumanoidRootPart") then
                local root = char.HumanoidRootPart
                local hum = char:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 then
                    -- Проверяем, видит ли камера цель (опционально, но лучше оставить)
                    local _, onScreen = Camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local dist = (LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Magnitude
                        if dist < ClosestDist then
                            ClosestDist = dist
                            Target = root
                        end
                    end
                end
            end
        end
    end
    return Target
end

-- === ГЛАВНЫЙ ХУК ДВИЖКА ===
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, index)
    if ForsakenSettings.SilentAimEnabled and not checkcaller() then
        local target = GetBestTarget()
        if target then
            -- 1. Подменяем UnitRay (Направление луча из камеры)
            -- Это самое важное для Plasma Beam!
            if self == Mouse and index == "UnitRay" then
                return Ray.new(Camera.CFrame.Position, (target.Position - Camera.CFrame.Position).Unit)
            end
            
            -- 2. Подменяем Hit (3D позиция)
            if self == Mouse and index == "Hit" then
                return target.CFrame
            end
            
            -- 3. Подменяем Target (Объект под мышкой)
            if self == Mouse and index == "Target" then
                return target
            end
        end
    end
    return oldIndex(self, index)
end)

-- === ХУК ЭКРАННЫХ КООРДИНАТ (Vector2) ===
local oldGetMouseLocation
oldGetMouseLocation = hookfunction(UIS.GetMouseLocation, function(self)
    if ForsakenSettings.SilentAimEnabled and not checkcaller() then
        local target = GetBestTarget()
        if target then
            local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
            if onScreen then
                return Vector2.new(screenPos.X, screenPos.Y)
            end
        end
    end
    return oldGetMouseLocation(self)
end)

-- === ФИНАЛЬНЫЙ ПЕРЕХВАТ ДЛЯ NETWORK ===
-- Перезаписываем OnClientInvoke, чтобы он возвращал Vector2 цели
task.spawn(function()
    local NetworkModule = game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Network")
    local RF = NetworkModule:FindFirstChildOfClass("RemoteFunction")
    
    if RF then
        RF.OnClientInvoke = function(name, ...)
            if name == "GetMousePosition" and ForsakenSettings.SilentAimEnabled then
                local target = GetBestTarget()
                if target then
                    local screenPos = Camera:WorldToViewportPoint(target.Position)
                    return Vector2.new(screenPos.X, screenPos.Y)
                end
            end
            return UIS:GetMouseLocation()
        end
    end
end)

print("!!! ULTRA SILENT AIM LOADED !!!")
