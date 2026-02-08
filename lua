-- Silent Aim для Forsaken (Dusekkar) - Версия 3.0
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Nearest" -- "Killer", "Survivor", "Nearest"
local AIM_FOV = 1000 -- Угол обзора
local SILENT_AIM_ENABLED = true
local PREDICTION_ENABLED = true -- Предсказание движения цели
local PREDICTION_STRENGTH = 0.3 -- Сила предсказания (0-1)

-- Получаем нужные модули
local success, Network = pcall(require, game:GetService("ReplicatedStorage").Modules.Network)
local success2, Device = pcall(require, game:GetService("ReplicatedStorage").Modules.Device)
local success3, Util = pcall(require, game:GetService("ReplicatedStorage").Modules.Util)

if not success then Network = nil end
if not success2 then Device = nil end
if not success3 then Util = nil end

-- Кэшированные данные
local lastTarget = nil
local lastTargetVelocity = Vector3.new(0, 0, 0)
local lastTargetTime = tick()
local dusekkarModule = nil

-- Функция для предсказания позиции
local function predictPosition(target, targetTime)
    if not target or not target.PrimaryPart or not PREDICTION_ENABLED then
        return target and target.PrimaryPart and target.PrimaryPart.Position
    end
    
    local deltaTime = tick() - targetTime
    if deltaTime > 1 then -- Сбрасываем если слишком старые данные
        return target.PrimaryPart.Position
    end
    
    -- Предсказываем позицию с учетом скорости
    local predictedPos = target.PrimaryPart.Position + (lastTargetVelocity * deltaTime * PREDICTION_STRENGTH)
    
    -- Ограничиваем предсказание максимальной дистанцией
    local maxPrediction = 10
    local actualDistance = (predictedPos - target.PrimaryPart.Position).Magnitude
    if actualDistance > maxPrediction then
        predictedPos = target.PrimaryPart.Position + (predictedPos - target.PrimaryPart.Position).Unit * maxPrediction
    end
    
    return predictedPos
end

-- Функция для получения ближайшей цели
local function getBestTarget()
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then 
        return nil, nil, nil
    end
    
    local camera = workspace.CurrentCamera
    local mousePos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local bestTarget = nil
    local bestDistance = math.huge
    local bestPosition = nil
    local bestVelocity = Vector3.new(0, 0, 0)
    
    -- Получаем всех игроков
    local allPlayers = {}
    
    -- Добавляем выживших
    local survivors = workspace.Players.Survivors:GetChildren()
    for _, survivor in ipairs(survivors) do
        if survivor:IsA("Model") and survivor ~= character then
            table.insert(allPlayers, {Model = survivor, Type = "Survivor"})
        end
    end
    
    -- Добавляем убийц
    local killers = workspace.Players.Killers:GetChildren()
    for _, killer in ipairs(killers) do
        if killer:IsA("Model") then
            table.insert(allPlayers, {Model = killer, Type = "Killer"})
        end
    end
    
    -- Фильтруем по режиму
    local filteredPlayers = {}
    for _, playerData in ipairs(allPlayers) do
        if AIM_MODE == "Nearest" then
            table.insert(filteredPlayers, playerData)
        elseif AIM_MODE == "Survivor" and playerData.Type == "Survivor" then
            table.insert(filteredPlayers, playerData)
        elseif AIM_MODE == "Killer" and playerData.Type == "Killer" then
            table.insert(filteredPlayers, playerData)
        end
    end
    
    for _, playerData in ipairs(filteredPlayers) do
        local target = playerData.Model
        if target and target.PrimaryPart then
            local screenPoint, onScreen = camera:WorldToViewportPoint(target.PrimaryPart.Position)
            
            if onScreen then
                local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
                local distance = (mousePos - screenPos).Magnitude
                
                if distance <= AIM_FOV then
                    -- Проверяем видимость через луч
                    local origin = camera.CFrame.Position
                    local direction = (target.PrimaryPart.Position - origin).Unit * 500
                    
                    local raycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
                    raycastParams.FilterDescendantsInstances = {character}
                    raycastParams.IgnoreWater = true
                    
                    local raycastResult = workspace:Raycast(origin, direction, raycastParams)
                    
                    local isVisible = false
                    if raycastResult then
                        local hitModel = raycastResult.Instance:FindFirstAncestorWhichIsA("Model")
                        if hitModel == target then
                            isVisible = true
                        end
                    else
                        -- Если луч не попал, но цель близко - все равно считаем видимой
                        local distanceToTarget = (target.PrimaryPart.Position - origin).Magnitude
                        if distanceToTarget < 50 then
                            isVisible = true
                        end
                    end
                    
                    if isVisible and distance < bestDistance then
                        bestDistance = distance
                        bestTarget = target
                        bestPosition = target.PrimaryPart.Position
                        bestVelocity = target.PrimaryPart.Velocity
                    end
                end
            else
                -- Если цель не на экране, но близко
                local distanceToChar = (target.PrimaryPart.Position - character.PrimaryPart.Position).Magnitude
                if distanceToChar < 100 and distanceToChar < bestDistance then
                    bestTarget = target
                    bestPosition = target.PrimaryPart.Position
                    bestVelocity = target.PrimaryPart.Velocity
                    bestDistance = distanceToChar
                end
            end
        end
    end
    
    -- Обновляем кэш скорости
    if bestTarget then
        lastTargetVelocity = bestVelocity
        lastTargetTime = tick()
    end
    
    lastTarget = bestTarget
    return bestTarget, bestPosition, bestVelocity
end

-- Функция для получения цели для Spawn Protection (учитывает радиус курсора)
local function getTargetForSpawnProtection()
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then return nil end
    
    local camera = workspace.CurrentCamera
    local mousePos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local bestTarget = nil
    local bestDistance = math.huge
    
    -- Только выжившие для Spawn Protection
    local survivors = workspace.Players.Survivors:GetChildren()
    
    for _, survivor in ipairs(survivors) do
        if survivor:IsA("Model") and survivor ~= character and survivor.PrimaryPart then
            local screenPoint, onScreen = camera:WorldToViewportPoint(survivor.PrimaryPart.Position)
            
            if onScreen then
                local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
                local distance = (mousePos - screenPos).Magnitude
                
                -- Важно: Spawn Protection требует курсор рядом с игроком
                -- Используем меньший FOV для этой способности
                if distance <= 300 then -- Меньший радиус для Spawn Protection
                    -- Проверяем атрибуты как в оригинальном коде
                    if not survivor:GetAttribute("DusekkarProtected") and 
                       not survivor:GetAttribute("Protecting") and
                       not survivor.PrimaryPart.Anchored then
                        
                        if distance < bestDistance then
                            bestDistance = distance
                            bestTarget = survivor
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end

-- Прямой перехват событий
local function hookEvents()
    -- Перехват удаленного вызова GetMousePosition
    local function hookRemoteFunction(rf)
        if rf.Name == "GetMousePosition" then
            local oldInvoke = rf.InvokeServer
            rf.InvokeServer = function(...)
                if SILENT_AIM_ENABLED then
                    local target, position, velocity = getBestTarget()
                    if target and position then
                        -- Предсказываем позицию
                        local predictedPos = predictPosition(target, lastTargetTime)
                        return predictedPos or position
                    end
                end
                return oldInvoke(...)
            end
        end
    end
    
    -- Перехват удаленного события DusekkarGet
    local function hookDusekkarRemoteFunction(rf)
        if string.find(rf.Name, "DusekkarGet") then
            local oldInvoke = rf.InvokeServer
            rf.InvokeServer = function(...)
                local target = getTargetForSpawnProtection()
                if target then
                    return target
                end
                return oldInvoke(...)
            end
        end
    end
    
    -- Ищем все RemoteFunction и перехватываем
    for _, descendant in pairs(game:GetDescendants()) do
        if descendant:IsA("RemoteFunction") then
            hookRemoteFunction(descendant)
            hookDusekkarRemoteFunction(descendant)
        end
    end
    
    -- Отслеживаем новые RemoteFunction
    game.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("RemoteFunction") then
            task.wait(0.1)
            hookRemoteFunction(descendant)
            hookDusekkarRemoteFunction(descendant)
        end
    end)
    
    print("[Silent Aim] События перехвачены")
end

-- Хук модуля Dusekkar
local function hookDusekkarModule()
    -- Ищем модуль Dusekkar
    local actorsFolder = game:GetService("ReplicatedStorage").Modules.Actors
    if not actorsFolder then return end
    
    for _, moduleScript in pairs(actorsFolder:GetChildren()) do
        if moduleScript.Name == "Dusekkar" then
            local success, module = pcall(require, moduleScript)
            if success and module and module.Abilities then
                dusekkarModule = module
                
                -- Сохраняем оригинальные коллбэки
                local originalPlasmaBeam = module.Abilities.PlasmaBeam.Callback
                local originalSpawnProtection = module.Abilities.SpawnProtection.Callback
                
                -- Заменяем PlasmaBeam
                module.Abilities.PlasmaBeam.Callback = function(self, arg)
                    if RunService:IsClient() and SILENT_AIM_ENABLED then
                        local target, position, velocity = getBestTarget()
                        if target and position then
                            local predictedPos = predictPosition(target, lastTargetTime)
                            return originalPlasmaBeam(self, predictedPos)
                        end
                    end
                    return originalPlasmaBeam(self, arg)
                end
                
                -- Заменяем SpawnProtection
                module.Abilities.SpawnProtection.Callback = function(self, arg)
                    if RunService:IsClient() then
                        -- Используем специальную функцию для Spawn Protection
                        local target = getTargetForSpawnProtection()
                        if target then
                            -- Подменяем аргумент
                            return originalSpawnProtection(self, {Target = target})
                        end
                    end
                    return originalSpawnProtection(self, arg)
                end
                
                print("[Silent Aim] Модуль Dusekkar перехвачен")
                break
            end
        end
    end
end

-- Создаем визуальный маркер
local function createVisuals()
    local marker = Instance.new("BillboardGui")
    marker.Name = "TargetMarker"
    marker.Size = UDim2.new(3, 0, 3, 0)
    marker.AlwaysOnTop = true
    marker.Adornee = nil
    marker.Enabled = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = marker
    
    marker.Parent = game.CoreGui
    
    -- Текст с информацией
    local infoGui = Instance.new("ScreenGui")
    infoGui.Name = "SilentAimInfo"
    infoGui.Parent = game.CoreGui
    
    local infoText = Instance.new("TextLabel")
    infoText.Size = UDim2.new(0, 300, 0, 100)
    infoText.Position = UDim2.new(1, -310, 0, 10)
    infoText.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    infoText.BackgroundTransparency = 0.7
    infoText.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoText.TextSize = 14
    infoText.Font = Enum.Font.Code
    infoText.TextXAlignment = Enum.TextXAlignment.Left
    infoText.TextYAlignment = Enum.TextYAlignment.Top
    infoText.Text = "Silent Aim: Загрузка..."
    infoText.Parent = infoGui
    
    -- Обновляем информацию
    RunService.RenderStepped:Connect(function()
        if SILENT_AIM_ENABLED and lastTarget and lastTarget.PrimaryPart then
            marker.Adornee = lastTarget.PrimaryPart
            marker.Enabled = true
            
            local distance = (LocalPlayer.Character and LocalPlayer.Character.PrimaryPart and 
                             (lastTarget.PrimaryPart.Position - LocalPlayer.Character.PrimaryPart.Position).Magnitude) or 0
            
            infoText.Text = string.format([[
Silent Aim: ВКЛ (F1)
Режим: %s (F2)
Предсказание: %s (F3)
Цель: %s
Дистанция: %.1f
Скорость: %.1f]], 
                AIM_MODE,
                PREDICTION_ENABLED and "ВКЛ" or "ВЫКЛ",
                lastTarget.Name,
                distance,
                lastTargetVelocity.Magnitude)
        else
            marker.Enabled = false
            infoText.Text = string.format([[
Silent Aim: %s (F1)
Режим: %s (F2)
Предсказание: %s (F3)
Цель: Нет]], 
                SILENT_AIM_ENABLED and "ВКЛ" or "ВЫКЛ",
                AIM_MODE,
                PREDICTION_ENABLED and "ВКЛ" or "ВЫКЛ")
        end
    end)
    
    return marker, infoText
end

-- Основная инициализация
local function initialize()
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    
    task.wait(2) -- Ждем загрузку
    
    -- Устанавливаем хуки
    hookEvents()
    hookDusekkarModule()
    
    -- Создаем визуализацию
    createVisuals()
    
    print("[Silent Aim] Инициализирован")
    print("[Silent Aim] Режим:", AIM_MODE)
    print("[Silent Aim] Предсказание:", PREDICTION_ENABLED and "ВКЛ" or "ВЫКЛ")
    
    -- Горячие клавиши
    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed then
            if input.KeyCode == Enum.KeyCode.F1 then
                SILENT_AIM_ENABLED = not SILENT_AIM_ENABLED
                print("[Silent Aim] " .. (SILENT_AIM_ENABLED and "Включен" or "Выключен"))
            elseif input.KeyCode == Enum.KeyCode.F2 then
                -- Меняем режим
                if AIM_MODE == "Killer" then
                    AIM_MODE = "Survivor"
                elseif AIM_MODE == "Survivor" then
                    AIM_MODE = "Nearest"
                else
                    AIM_MODE = "Killer"
                end
                print("[Silent Aim] Режим изменен на:", AIM_MODE)
            elseif input.KeyCode == Enum.KeyCode.F3 then
                PREDICTION_ENABLED = not PREDICTION_ENABLED
                print("[Silent Aim] Предсказание:", PREDICTION_ENABLED and "ВКЛ" or "ВЫКЛ")
            elseif input.KeyCode == Enum.KeyCode.F4 then
                -- Тестовый выстрел
                if SILENT_AIM_ENABLED then
                    local target, position, velocity = getBestTarget()
                    if target then
                        print("[Тест] Цель:", target.Name, "Позиция:", position, "Скорость:", velocity.Magnitude)
                    end
                end
            end
        end
    end)
end

-- Отслеживаем смену персонажа
local function onCharacterAdded(character)
    task.wait(1)
    if character.Name == "Dusekkar" then
        print("[Silent Aim] Обнаружен Dusekkar, инициализация...")
        initialize()
    end
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Если уже играем за Dusekkar
if LocalPlayer.Character and LocalPlayer.Character.Name == "Dusekkar" then
    task.spawn(function()
        task.wait(1)
        print("[Silent Aim] Обнаружен Dusekkar, инициализация...")
        initialize()
    end)
end

-- Функция для работы на телефоне
local function setupMobileSupport()
    if Device and Device:GetPlayerDevice() == "Mobile" then
        print("[Silent Aim] Обнаружено мобильное устройство")
        
        -- Создаем кнопки для мобильного управления
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "MobileSilentAimUI"
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        
        -- Кнопка включения/выключения
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(0, 100, 0, 50)
        toggleBtn.Position = UDim2.new(1, -110, 0, 10)
        toggleBtn.Text = "Aim: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggleBtn.Parent = screenGui
        
        toggleBtn.MouseButton1Click:Connect(function()
            SILENT_AIM_ENABLED = not SILENT_AIM_ENABLED
            toggleBtn.Text = "Aim: " .. (SILENT_AIM_ENABLED and "ON" or "OFF")
            toggleBtn.BackgroundColor3 = SILENT_AIM_ENABLED and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        end)
        
        -- Кнопка смены режима
        local modeBtn = Instance.new("TextButton")
        modeBtn.Size = UDim2.new(0, 100, 0, 50)
        modeBtn.Position = UDim2.new(1, -110, 0, 70)
        modeBtn.Text = "Mode: " .. AIM_MODE
        modeBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        modeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        modeBtn.Parent = screenGui
        
        modeBtn.MouseButton1Click:Connect(function()
            if AIM_MODE == "Killer" then
                AIM_MODE = "Survivor"
            elseif AIM_MODE == "Survivor" then
                AIM_MODE = "Nearest"
            else
                AIM_MODE = "Killer"
            end
            modeBtn.Text = "Mode: " .. AIM_MODE
        end)
    end
end

-- Инициализация для мобильных устройств
task.spawn(function()
    task.wait(3)
    if Device then
        setupMobileSupport()
    end
end)

print("[Silent Aim] Скрипт загружен. Ожидание Dusekkar...")
print("[Silent Aim] Горячие клавиши:")
print("  F1 - Вкл/Выкл Silent Aim")
print("  F2 - Сменить режим (Killer/Survivor/Nearest)")
print("  F3 - Вкл/Выкл предсказание движения")
print("  F4 - Тестовая информация о цели")
