local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Killer" -- "Killer", "Survivor", "Nearest"
local silentAimEnabled = false
local characterAddedConnection = nil

-- Функция для получения ближайшей цели
local function getBestTarget()
    if not silentAimEnabled then return nil end
    
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
    local Network = require(game.ReplicatedStorage.Modules.Network)
    local Device = require(game.ReplicatedStorage.Modules.Device)

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

-- Инициализация при загрузке персонажа Dusekkar
local function initializeForCharacter(character)
    if character.Name == "Dusekkar" then
        wait(1) -- Ждем загрузку
        hookGetMousePosition()
        print("[Silent Aim] Инициализирован для Dusekkar")
        print("[Silent Aim] Текущий режим:", AIM_MODE)
    end
end

-- Функция включения/выключения Silent Aim
local function toggleSilentAim(enable)
    silentAimEnabled = enable
    
    if enable then
        print("[Silent Aim] Включен")
        
        -- Устанавливаем соединение при изменении персонажа
        if not characterAddedConnection then
            characterAddedConnection = LocalPlayer.CharacterAdded:Connect(initializeForCharacter)
        end
        
        -- Если персонаж уже есть, инициализируем
        if LocalPlayer.Character then
            initializeForCharacter(LocalPlayer.Character)
        end
    else
        print("[Silent Aim] Выключен")
        
        -- Отключаем соединение
        if characterAddedConnection then
            characterAddedConnection:Disconnect()
            characterAddedConnection = nil
        end
    end
end
toggleSilentAim(true)
