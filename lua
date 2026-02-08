local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Killer" -- "Killer", "Survivor", "Nearest"
local AIM_TECHNIQUE = "PC" -- "PC", "PC and Mobile"
local silentAimEnabled = false
local characterAddedConnection = nil

-- ID анимаций Plasma Beam для отслеживания
local PLASMA_BEAM_ANIM_IDS = {
    "77894750279891",
    "118933622288262"
}

-- Переменные для отслеживания анимации
local plasmaBeamAnimConnection = nil
local isUsingPlasmaBeam = false

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

-- Функция для поворота камеры и персонажа на цель
local function aimAtTarget(target)
    if not target or not target.PrimaryPart then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local camera = workspace.CurrentCamera
    
    -- Поворачиваем камеру на цель
    camera.CFrame = CFrame.new(camera.CFrame.Position, target.PrimaryPart.Position)
    
    -- Поворачиваем HumanoidRootPart на цель (для мобильных устройств)
    hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(
        target.PrimaryPart.Position.X,
        hrp.Position.Y,
        target.PrimaryPart.Position.Z
    ))
end

-- Функция отслеживания анимаций Plasma Beam
local function setupPlasmaBeamTracking(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end
    
    -- Отключаем старый connection если есть
    if plasmaBeamAnimConnection then
        plasmaBeamAnimConnection:Disconnect()
        plasmaBeamAnimConnection = nil
    end
    
    -- Находим аниматор
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    
    -- Отслеживаем воспроизведение анимаций
    plasmaBeamAnimConnection = animator.AnimationPlayed:Connect(function(track)
        -- Получаем ID анимации
        local animationId = track.Animation.AnimationId
        local animIdString = tostring(animationId)
        
        -- Ищем ID в нашем списке
        for _, id in ipairs(PLASMA_BEAM_ANIM_IDS) do
            if animIdString:find(id) then
                -- Начинаем цель, если включен режим PC and Mobile
                if AIM_TECHNIQUE == "PC and Mobile" and silentAimEnabled then
                    isUsingPlasmaBeam = true
                    
                    -- Целимся в ближайшую цель
                    local target = getBestTarget()
                    if target then
                        aimAtTarget(target)
                    end
                    
                    -- Отслеживаем завершение анимации
                    track.Stopped:Once(function()
                        isUsingPlasmaBeam = false
                    end)
                end
                break
            end
        end
    end)
end

-- Перехват вызова GetMousePosition
local function hookGetMousePosition()
    local Network = require(game.ReplicatedStorage.Modules.Network)
    local Device = require(game.ReplicatedStorage.Modules.Device)

    if not Network or not Network.SetConnection then return end
    
    -- Устанавливаем свой обработчик для GetMousePosition
    Network:SetConnection("GetMousePosition", "REMOTE_FUNCTION", function()
        -- Если включен режим PC and Mobile и используется Plasma Beam, 
        -- то возвращаем позицию мыши (камеры уже направлена на цель)
        if AIM_TECHNIQUE == "PC and Mobile" and isUsingPlasmaBeam then
            local camera = workspace.CurrentCamera
            local ray = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
            return ray.Origin + ray.Direction * 500
        end
        
        -- Для режима PC или когда не используется Plasma Beam - стандартная логика
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
        
        -- Настраиваем отслеживание анимаций для режима PC and Mobile
        if AIM_TECHNIQUE == "PC and Mobile" then
            setupPlasmaBeamTracking(character)
        end
        
        print("[Silent Aim] Инициализирован для Dusekkar")
        print("[Silent Aim] Текущий режим:", AIM_MODE)
        print("[Silent Aim] Техника:", AIM_TECHNIQUE)
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
        isUsingPlasmaBeam = false
        
        -- Отключаем соединение
        if characterAddedConnection then
            characterAddedConnection:Disconnect()
            characterAddedConnection = nil
        end
        
        -- Отключаем отслеживание анимаций
        if plasmaBeamAnimConnection then
            plasmaBeamAnimConnection:Disconnect()
            plasmaBeamAnimConnection = nil
        end
    end
end

-- Функция для изменения режима техники
local function setAimTechnique(technique)
    if technique ~= "PC" and technique ~= "PC and Mobile" then
        print("[Silent Aim] Неверная техника. Используйте 'PC' или 'PC and Mobile'")
        return
    end
    
    AIM_TECHNIQUE = technique
    print("[Silent Aim] Техника изменена на:", technique)
    
    -- Переинициализируем если скрипт включен
    if silentAimEnabled and LocalPlayer.Character and LocalPlayer.Character.Name == "Dusekkar" then
        initializeForCharacter(LocalPlayer.Character)
    end
end

-- Включаем по умолчанию
toggleSilentAim(true)
