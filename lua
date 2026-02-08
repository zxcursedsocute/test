local gui = loadstring(game:HttpGet("https://raw.githubusercontent.com/zxcursedsocute/.1/refs/heads/main/test%20ne%20lib"))()

local windows = gui.CreateWindow("Forsaken script", "By zxc76945",'590','v 1.0')

local SurvivorCombatSection = windows:AddTab('Visual','Visual')
-- === НАСТРОЙКИ ===
getgenv().ForsakenSettings = getgenv().ForsakenSettings or {
    SilentAimEnabled = true,
    SilentAimTargetMode = "Killers", -- "Survivors" или "Killers"
    SilentAimFOV = 1000
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- === ПОИСК ЦЕЛИ ===
local function GetBestTarget()
    local ClosestDist = ForsakenSettings.SilentAimFOV
    local TargetPos = nil
    
    local targetFolder = workspace.Players:FindFirstChild(ForsakenSettings.SilentAimTargetMode)
    if not targetFolder then return nil end

    for _, char in pairs(targetFolder:GetChildren()) do
        if char ~= LocalPlayer.Character and char:FindFirstChild("HumanoidRootPart") then
            local root = char.HumanoidRootPart
            local dist = (LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Magnitude
            
            if dist < ClosestDist then
                ClosestDist = dist
                TargetPos = root.Position
            end
        end
    end
    return TargetPos
end

-- === БЕЗОПАСНЫЙ ХУК (FIX) ===
-- Мы используем метаметод __newindex, чтобы поймать момент, 
-- когда игра ПЫТАЕТСЯ установить OnClientInvoke.
local NetworkModule = game:GetService("ReplicatedStorage").Modules.Network
local RF = NetworkModule:FindFirstChildOfClass("RemoteFunction")

if RF then
    local oldHook
    oldHook = hookmetamethod(game, "__newindex", function(self, index, value)
        -- Если игра пытается назначить OnClientInvoke для нашей RemoteFunction
        if self == RF and index == "OnClientInvoke" and type(value) == "function" then
            local originalCallback = value
            
            -- Мы подменяем функцию на свою "обертку"
            value = function(name, ...)
                -- Если сервер спрашивает позицию мышки для Plasma Beam
                if name == "GetMousePosition" and ForsakenSettings.SilentAimEnabled then
                    local target = GetBestTarget()
                    if target then
                        return target -- Возвращаем Vector3 цели вместо мышки
                    end
                end
                -- В остальных случаях возвращаем то, что хотела игра
                return originalCallback(name, ...)
            end
        end
        return oldHook(self, index, value)
    end)
    print("Silent Aim: Hook applied successfully!")
else
    warn("Silent Aim: RemoteFunction not found in Network module.")
end

-- === UI (Вставь в свой Combat Section) ===
SurvivorCombatSection:AddToggle({
    Name = 'Plasma Beam Silent Aim',
    Callback = function(state)
        ForsakenSettings.SilentAimEnabled = state
    end
})
