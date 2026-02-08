local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Killer" -- "Killer", "Survivor", "Nearest"
local AIM_TECHNIQUE = "PC and Mobile" -- "PC", "PC and Mobile"

-- ID анимаций Plasma Beam для отслеживания
local PLASMA_BEAM_ANIM_IDS = {
    "77894750279891",
    "118933622288262"
}

-- Таблица состояния скрипта
local state = {
    enabled = false,
    characterAddedConnection = nil,
    renderSteppedConnection = nil,
    plasmaBeamAnimConnection = nil,
    isUsingPlasmaBeam = false,
    currentAnimationTrack = nil
}

-- Переменная для определения устройства
local isMobile = false

-- Функция для получения ближайшей цели
local function getBestTarget()
    if not state.enabled then return nil end
    
    local character = Player.Character
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
    
    local character = Player.Character
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

-- Основной цикл слежения за цель
local function aimLoop()
    if not state.enabled then return end
    if AIM_TECHNIQUE ~= "PC and Mobile" then return end
    if not state.isUsingPlasmaBeam then return end
    
    local character = Player.Character
    if not character or character.Name ~= "Dusekkar" then return end
    
    local target = getBestTarget()
    if target then
        aimAtTarget(target)
    end
end

-- Функция отслеживания анимаций Plasma Beam
local function setupPlasmaBeamTracking(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end
    
    -- Отключаем старый connection если есть
    if state.plasmaBeamAnimConnection then
        state.plasmaBeamAnimConnection:Disconnect()
        state.plasmaBeamAnimConnection = nil
    end
    
    -- Находим аниматор
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    
    -- Отслеживаем воспроизведение анимаций
    state.plasmaBeamAnimConnection = animator.AnimationPlayed:Connect(function(track)
        -- Получаем ID анимации
        local animationId = track.Animation.AnimationId
        local animIdString = tostring(animationId)
        
        -- Ищем ID в нашем списке
        for _, id in ipairs(PLASMA_BEAM_ANIM_IDS) do
            if animIdString:find(id) then
                -- Начинаем цель, если включен режим PC and Mobile
                if AIM_TECHNIQUE == "PC and Mobile" and state.enabled then
                    state.isUsingPlasmaBeam = true
                    state.currentAnimationTrack = track
                    
                    -- Отслеживаем завершение анимации
                    track.Stopped:Once(function()
                        state.isUsingPlasmaBeam = false
                        state.currentAnimationTrack = nil
                    end)
                    
                    -- Также отслеживаем, если анимация была прервана
                    track.Ended:Once(function()
                        state.isUsingPlasmaBeam = false
                        state.currentAnimationTrack = nil
                    end)
                end
                break
            end
        end
    end)
end

-- Запуск цикла слежения
local function startAimLoop()
    if state.renderSteppedConnection then
        state.renderSteppedConnection:Disconnect()
        state.renderSteppedConnection = nil
    end
    
    state.renderSteppedConnection = RunService.RenderStepped:Connect(aimLoop)
end

-- Остановка цикла слежения
local function stopAimLoop()
    state.isUsingPlasmaBeam = false
    state.currentAnimationTrack = nil
    
    if state.renderSteppedConnection then
        state.renderSteppedConnection:Disconnect()
        state.renderSteppedConnection = nil
    end
end

-- Перехват вызова GetMousePosition (только для PC)
local function hookGetMousePosition()
    local Network = require(game.ReplicatedStorage.Modules.Network)
    local Device = require(game.ReplicatedStorage.Modules.Device)

    if not Network or not Network.SetConnection then return end
    
    -- Определяем тип устройства
    local deviceType = Device:GetPlayerDevice()
    isMobile = deviceType ~= "PC"
    
    -- Если мы на мобильном устройстве, не хукаем позицию мыши
    if isMobile then
        print("[Silent Aim] На мобильном устройстве - отключен хук позиции мыши")
        return
    end
    
    -- Устанавливаем свой обработчик для GetMousePosition (только на PC)
    Network:SetConnection("GetMousePosition", "REMOTE_FUNCTION", function()
        -- Для режима PC - всегда хук мыши
        if AIM_TECHNIQUE == "PC" then
            local target = getBestTarget()
            
            if target and target.PrimaryPart then
                return target.PrimaryPart.Position
            else
                return Player:GetMouse().Hit.Position
            end
        end
        
        -- Для режима PC and Mobile на PC
        if AIM_TECHNIQUE == "PC and Mobile" then
            local target = getBestTarget()
            
            if target and target.PrimaryPart then
                return target.PrimaryPart.Position
            else
                return Player:GetMouse().Hit.Position
            end
        end
        
        -- Если режим не определен, возвращаем реальную позицию мыши
        return Player:GetMouse().Hit.Position
    end)
end

-- Инициализация при загрузке персонажа Dusekkar
local function initializeForCharacter(character)
    if character.Name == "Dusekkar" then
        wait(1) -- Ждем загрузку
        
        -- Только на PC хукаем позицию мыши
        if not isMobile then
            hookGetMousePosition()
        end
        
        -- Настраиваем отслеживание анимаций для режима PC and Mobile
        if AIM_TECHNIQUE == "PC and Mobile" then
            setupPlasmaBeamTracking(character)
            startAimLoop()
        end
        
        print("[Silent Aim] Инициализирован для Dusekkar")
        print("[Silent Aim] Текущий режим:", AIM_MODE)
        print("[Silent Aim] Техника:", AIM_TECHNIQUE)
        print("[Silent Aim] Устройство:", isMobile and "Mobile" or "PC")
        print("[Silent Aim] Хук мыши:", isMobile and "Отключен" or "Включен")
    else
        -- Если сменили персонажа, останавливаем цикл
        stopAimLoop()
    end
end

-- Функция включения/выключения Silent Aim
local function toggleSilentAim(enable)
    state.enabled = enable
    
    if enable then
        print("[Silent Aim] Включен")
        
        -- Устанавливаем соединение при изменении персонажа
        if not state.characterAddedConnection then
            state.characterAddedConnection = Player.CharacterAdded:Connect(initializeForCharacter)
        end
        
        -- Если персонаж уже есть, инициализируем
        if Player.Character then
            initializeForCharacter(Player.Character)
        end
    else
        print("[Silent Aim] Выключен")
        
        -- Останавливаем все процессы
        stopAimLoop()
        
        -- Отключаем соединение
        if state.characterAddedConnection then
            state.characterAddedConnection:Disconnect()
            state.characterAddedConnection = nil
        end
        
        -- Отключаем отслеживание анимаций
        if state.plasmaBeamAnimConnection then
            state.plasmaBeamAnimConnection:Disconnect()
            state.plasmaBeamAnimConnection = nil
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
    
    -- Останавливаем старый цикл
    stopAimLoop()
    
    -- Переинициализируем если скрипт включен
    if state.enabled and Player.Character and Player.Character.Name == "Dusekkar" then
        initializeForCharacter(Player.Character)
    end
end

-- Включаем по умолчанию
toggleSilentAim(true)
