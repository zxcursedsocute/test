-- Silent Aim для Plasma Beam (Dusekkar) + Fix Spawn Protection
-- [v2.0] Added Prediction & Anti-Cancel Hook

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- === НАСТРОЙКИ ===
local CONFIG = {
    AIM_MODE = "Nearest", -- "Killer", "Survivor", "Nearest"
    AIM_FOV = 1200,       -- Угол обзора
    PREDICTION = 0.145,   -- Коэффициент упреждения (0.13 - 0.16 обычно идеально для стрейфов)
    DEBUG = false         -- Показ отладочной информации в консоли
}

-- Модули игры
local Network = require(game.ReplicatedStorage.Modules.Network)
local Device = require(game.ReplicatedStorage.Modules.Device)
local Util = require(game.ReplicatedStorage.Modules.Util)

-- Переменные состояния
local currentTarget = nil

-- Функция для получения ближайшей цели
local function getBestTarget()
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then return nil end
    
    local camera = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local bestTarget = nil
    local bestDistance = math.huge
    
    local targets = {}
    
    -- Сбор целей в зависимости от режима
    if CONFIG.AIM_MODE == "Killer" then
        targets = workspace.Players.Killers:GetChildren()
    elseif CONFIG.AIM_MODE == "Survivor" then
        targets = workspace.Players.Survivors:GetChildren()
    else
        for _, v in ipairs(workspace.Players.Survivors:GetChildren()) do table.insert(targets, v) end
        for _, v in ipairs(workspace.Players.Killers:GetChildren()) do table.insert(targets, v) end
    end
    
    -- Фильтр: не целиться в себя
    for i = #targets, 1, -1 do
        if targets[i] == character then
            table.remove(targets, i)
        end
    end
    
    for _, target in ipairs(targets) do
        if target and target.PrimaryPart then
            local screenPoint, onScreen = camera:WorldToViewportPoint(target.PrimaryPart.Position)
            
            if onScreen then
                local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
                local distance = (mousePos - screenPos).Magnitude
                
                if distance <= CONFIG.AIM_FOV then
                    -- Проверка на препятствия (Raycast)
                    local rayParams = RaycastParams.new()
                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                    rayParams.FilterDescendantsInstances = {character}
                    
                    local origin = camera.CFrame.Position
                    local direction = (target.PrimaryPart.Position - origin).Unit * 500
                    local result = workspace:Raycast(origin, direction, rayParams)
                    
                    if result and result.Instance:IsDescendantOf(target) then
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

-- Хук для блокировки отмены Spawn Protection
-- Это решает проблему прерывания способности через 1 секунду
local function hookRemoteEvents()
    local mt = getrawmetatable(game)
    local oldNameCall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        -- Проверяем, пытается ли игра отправить сигнал отмены
        if method == "FireServer" and tostring(self):find("DusekkarCancel") then
            -- Если у нас есть цель, которую мы защищаем/атакуем, БЛОКИРУЕМ отмену
            local target = getBestTarget()
            if target then
                if CONFIG.DEBUG then warn("[Silent Aim] Blocked DusekkarCancel packet!") end
                return nil -- Ничего не возвращаем, пакет не уходит на сервер
            end
        end

        return oldNameCall(self, ...)
    end)
    
    setreadonly(mt, true)
end

-- Перехват сетевых функций (Network Module)
local function hookGameNetwork()
    -- 1. Перехват позиции для атаки (Plasma Beam)
    Network:SetConnection("GetMousePosition", "REMOTE_FUNCTION", function()
        local target = getBestTarget()
        
        if target and target.PrimaryPart then
            -- === ДОБАВЛЕНА ПРЕДИКЦИЯ ===
            local velocity = target.PrimaryPart.AssemblyLinearVelocity
            local position = target.PrimaryPart.Position
            
            -- Расчет упреждения: Позиция + (Скорость * Коэффициент)
            local predictedPos = position + (velocity * CONFIG.PREDICTION)
            
            if CONFIG.DEBUG then 
                print(string.format("[Silent Aim] Aiming at: %s | Pred: %s", target.Name, tostring(velocity.Magnitude > 0))) 
            end
            
            return predictedPos
        else
            -- Стандартное поведение (реальная мышь)
            if Device:GetPlayerDevice() == "PC" then
                return LocalPlayer:GetMouse().Hit.Position
            else
                local cam = workspace.CurrentCamera
                local ray = cam:ScreenPointToRay(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                return ray.Origin + ray.Direction * 100
            end
        end
    end)
    
    -- 2. Перехват выбора цели для защиты (Spawn Protection)
    Network:SetConnection(tostring(LocalPlayer).."DusekkarGet", "REMOTE_FUNCTION", function()
        local target = getBestTarget()
        
        -- Сначала пробуем взять цель из Silent Aim
        if target and target:FindFirstChild("PrimaryPart") then
            -- Проверки валидности для защиты
            local canProtect = not target:GetAttribute("DusekkarProtected") 
                           and not target:GetAttribute("Protecting")
                           and not target.PrimaryPart.Anchored
            
            if canProtect then
                return target
            end
        end
        
        -- Если Silent Aim не нашел цель, используем стандартную логику игры (чтобы не сломать механику)
        local closest = Util:GetClosestPlayerFromPosition(
            LocalPlayer.Character.PrimaryPart.Position,
            {ReturnTable=true, MaxDistance=60, PlayerSelection="Survivors", OverrideUndetectable=true}
        )
        
        for _, data in pairs(closest) do
            if data.Player ~= LocalPlayer.Character then
                return data.Player
            end
        end
        return nil
    end)
end

-- GUI
local function createUI()
    if game.CoreGui:FindFirstChild("DusekkarAimUI") then game.CoreGui.DusekkarAimUI:Destroy() end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "DusekkarAimUI"
    ScreenGui.Parent = game.CoreGui -- Используем CoreGui для безопасности
    
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 150, 0, 130)
    Frame.Position = UDim2.new(0.01, 0, 0.5, -65)
    Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    Frame.BorderSizePixel = 0
    Frame.Parent = ScreenGui
    
    local Title = Instance.new("TextLabel")
    Title.Text = "Dusekkar Fix v2"
    Title.Size = UDim2.new(1, 0, 0, 25)
    Title.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
    Title.TextColor3 = Color3.white
    Title.Parent = Frame
    
    local function createBtn(text, order, callback)
        local btn = Instance.new("TextButton")
        btn.Text = text
        btn.Size = UDim2.new(0.9, 0, 0, 25)
        btn.Position = UDim2.new(0.05, 0, 0, 30 + (order * 30))
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        btn.TextColor3 = Color3.white
        btn.Parent = Frame
        btn.MouseButton1Click:Connect(function()
            callback(btn)
        end)
        return btn
    end
    
    createBtn("Target: " .. CONFIG.AIM_MODE, 0, function(self)
        if CONFIG.AIM_MODE == "Nearest" then CONFIG.AIM_MODE = "Killer"
        elseif CONFIG.AIM_MODE == "Killer" then CONFIG.AIM_MODE = "Survivor"
        else CONFIG.AIM_MODE = "Nearest" end
        self.Text = "Target: " .. CONFIG.AIM_MODE
    end)
    
    local predBtn = createBtn("Pred: " .. CONFIG.PREDICTION, 1, function(self)
        CONFIG.PREDICTION = CONFIG.PREDICTION + 0.05
        if CONFIG.PREDICTION > 0.3 then CONFIG.PREDICTION = 0.0 end
        self.Text = "Pred: " .. string.sub(tostring(CONFIG.PREDICTION), 1, 4)
    end)
    
    createBtn("Re-Init Hooks", 2, function()
        hookGameNetwork()
        hookRemoteEvents()
    end)
end

-- Инициализация
local function init()
    if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
    
    task.wait(1)
    hookGameNetwork()
    hookRemoteEvents()
    createUI()
    
    print("--> Dusekkar Script Loaded: Anti-Cancel & Prediction Active <--")
end

LocalPlayer.CharacterAdded:Connect(function(char)
    if char.Name == "Dusekkar" then
        task.wait(2)
        init()
    end
end)

if LocalPlayer.Character and LocalPlayer.Character.Name == "Dusekkar" then
    init()
end
