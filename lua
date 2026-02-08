-- Silent Aim для Plasma Beam (Dusekkar)
-- Автоматически цепляет по ближайшей цели в зависимости от настроек

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Настройки
local AIM_MODE = "Killer" -- "Killer", "Survivor", "Nearest"
local AIM_FOV = 100 -- Угол обзора для поиска целей

-- Получаем нужные модули
local Network = require(game.ReplicatedStorage.Modules.Network)
local Device = require(game.ReplicatedStorage.Modules.Device)
local Util = require(game.ReplicatedStorage.Modules.Util)

-- Кэшированные данные
local cachedConnections = {}
local originalFireServer = nil

-- Функция для получения ближайшей цели
local function getBestTarget()
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then return nil end
    
    local camera = workspace.CurrentCamera
    local mousePos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
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
                local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
                local distance = (mousePos - screenPos).Magnitude
                
                -- Проверяем попадание в FOV
                if distance <= AIM_FOV then
                    local raycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
                    raycastParams.FilterDescendantsInstances = {character}
                    raycastParams.IgnoreWater = true
                    
                    local origin = camera.CFrame.Position
                    local direction = (target.PrimaryPart.Position - origin).Unit * 500
                    local raycastResult = workspace:Raycast(origin, direction, raycastParams)
                    
                    if raycastResult and raycastResult.Instance:IsDescendantOf(target) then
                        if distance < bestDistance then
                            bestDistance = distance
                            bestTarget = target
                        end
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
    
    -- Также перехватываем вызов DusekkarGet для Spawn Protection
    Network:SetConnection(`{tostring(LocalPlayer)}DusekkarGet`, "REMOTE_FUNCTION", function()
        local target = getBestTarget()
        
        if target and target:FindFirstChild("PrimaryPart") then
            -- Проверяем, можно ли защитить этого игрока
            if not target:GetAttribute("DusekkarProtected") and 
               not target:GetAttribute("Protecting") and
               not target.PrimaryPart.Anchored then
                return target
            end
        end
        
        -- Если цель не найдена или не подходит, используем оригинальную логику
        local closestPlayers = Util:GetClosestPlayerFromPosition(
            LocalPlayer.Character.PrimaryPart.Position,
            {
                ReturnTable = true,
                MaxDistance = 50,
                PlayerSelection = "Survivors",
                OverrideUndetectable = true
            }
        )
        
        for _, playerData in pairs(closestPlayers) do
            local playerChar = playerData.Player
            if playerChar and playerChar ~= LocalPlayer.Character then
                return playerChar
            end
        end
        
        return nil
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

-- Функция для переключения режимов
local function setAimMode(mode)
    AIM_MODE = mode
    print("[Silent Aim] Режим изменен на:", mode)
end

-- Создаем интерфейс для управления
local function createUI()
    if not RunService:IsClient() then return end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SilentAimUI"
    ScreenGui.Parent = LocalPlayer.PlayerGui
    
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 200, 0, 150)
    Frame.Position = UDim2.new(0, 10, 0, 10)
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Frame.BackgroundTransparency = 0.5
    Frame.Parent = ScreenGui
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.Text = "Silent Aim - Dusekkar"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    Title.Parent = Frame
    
    -- Кнопки выбора режима
    local modes = {"Killer", "Survivor", "Nearest"}
    local buttons = {}
    
    for i, mode in ipairs(modes) do
        local Button = Instance.new("TextButton")
        Button.Size = UDim2.new(0.9, 0, 0, 30)
        Button.Position = UDim2.new(0.05, 0, 0, 35 + (i-1)*35)
        Button.Text = mode
        Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        Button.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        Button.Parent = Frame
        
        Button.MouseButton1Click:Connect(function()
            setAimMode(mode)
            for _, btn in pairs(buttons) do
                btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
            end
            Button.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        end)
        
        table.insert(buttons, Button)
        
        if mode == AIM_MODE then
            Button.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        end
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
    hookPlasmaBeam()
    
    -- Создаем интерфейс
    pcall(createUI)
    
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
