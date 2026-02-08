local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Killer" -- "Killer", "Survivor", "Nearest"

-- Получаем нужные модули
local Network = require(game.ReplicatedStorage.Modules.Network)
local Device = require(game.ReplicatedStorage.Modules.Device)
local Util = require(game.ReplicatedStorage.Modules.Util)

-- Функция для получения ближайшей цели
local function getBestTarget()
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then return nil end
    
    local camera = workspace.CurrentCamera
    local bestTarget = nil
    local bestDistance = math.huge
    
    -- Ищем выживших
    local survivors = workspace.Players.Survivors:GetChildren()
    -- Ищем убийц
    local killers = workspace.Players.Killers:GetChildren()
    
    local targets = {}
    
    if AIM_MODE == "Killer" then
        targets = killers
    elseif AIM_MODE == "Survivor" then
        targets = survivors
    else -- Nearest
        for _, v in ipairs(survivors) do
            table.insert(targets, v)
        end
        for _, v in ipairs(killers) do
            table.insert(targets, v)
        end
    end
    
    -- Фильтруем себя
    for i = #targets, 1, -1 do
        if targets[i].Name == "Dusekkar" and character.Name == "Dusekkar" then
            table.remove(targets, i)
        end
    end
    
    for _, target in ipairs(targets) do
        if target and target.PrimaryPart then
            -- Проверяем, виден ли target на экране
            local screenPoint, onScreen = camera:WorldToViewportPoint(target.PrimaryPart.Position)
            
            if onScreen then
                local distanceFromCamera = (camera.CFrame.Position - target.PrimaryPart.Position).Magnitude
                
                local raycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
                raycastParams.FilterDescendantsInstances = {character}
                raycastParams.IgnoreWater = true
                
                local origin = camera.CFrame.Position
                local direction = (target.PrimaryPart.Position - origin).Unit * 500
                local raycastResult = workspace:Raycast(origin, direction, raycastParams)
                
                if raycastResult and raycastResult.Instance:IsDescendantOf(target) then
                    if distanceFromCamera < bestDistance then
                        bestDistance = distanceFromCamera
                        bestTarget = target
                    end
                end
            end
        end
    end
    
    return bestTarget
end

-- Перехват вызова GetMousePosition
local function hookGetMousePosition()
    if not Network or not Network.SetConnection then return end
    
    -- Устанавливаем свой обработчик для GetMousePosition
    Network:SetConnection("GetMousePosition", "REMOTE_FUNCTION", function()
        local target = getBestTarget()
        
        if target and target.PrimaryPart then
            -- Возвращаем позицию цели вместо позиции мыши
            return target.PrimaryPart.Position
        else
            -- Если цель не найдена, возвращаем реальную позицию мыши
            if Device:GetPlayerDevice() == "PC" then
                return LocalPlayer:GetMouse().Hit.Position
            else
                -- Для мобильных устройств возвращаем позицию по центру экрана
                local camera = workspace.CurrentCamera
                local ray = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
                return ray.Origin + ray.Direction * 500
            end
        end
    end)
end

-- Перехват вызова способности Plasma Beam
local function hookPlasmaBeam()
    -- Находим модуль Dusekkar
    local dusekkarModule = nil
    for _, module in pairs(game.ReplicatedStorage.Modules.Actors:GetChildren()) do
        if module.Name == "Dusekkar" then
            dusekkarModule = require(module)
            break
        end
    end
    
    if not dusekkarModule then return end
    
    -- Сохраняем оригинальный Callback
    local originalCallback = dusekkarModule.Abilities.PlasmaBeam.Callback
    
    -- Заменяем Callback
    dusekkarModule.Abilities.PlasmaBeam.Callback = function(arg1, arg2)
        if RunService:IsClient() then
            -- На клиенте проверяем, есть ли цель для атаки
            local target = getBestTarget()
            if target and target.PrimaryPart then
                -- Передаем фейковую позицию мыши для сервера
                local fakeMousePos = target.PrimaryPart.Position
                
                -- Вызываем оригинальный Callback с фейковой позицией
                return originalCallback(arg1, fakeMousePos)
            end
        end
        
        -- Если цель не найдена, используем оригинальную логику
        return originalCallback(arg1, arg2)
    end
end

-- Основная функция инициализации
local function initialize()
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    
    wait(3) -- Ждем загрузку игры
    
    -- Устанавливаем хуки
    hookGetMousePosition()
    --hookPlasmaBeam()
    
    print("[Silent Aim] Инициализирован для Dusekkar")
    print("[Silent Aim] Текущий режим:", AIM_MODE)
end

-- Запускаем при загрузке персонажа
LocalPlayer.CharacterAdded:Connect(function()
    if LocalPlayer.Character.Name == "Dusekkar" then
        initialize()
    end
end)

-- Если уже играем за Dusekkar
if LocalPlayer.Character and LocalPlayer.Character.Name == "Dusekkar" then
    initialize()
end
