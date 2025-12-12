local MAX_STAMINA = 100
local RUN_DRAIN = 10
local REGEN_RATE = 20
local UPDATE_RATE = 0.1
local REGEN_DELAY = 0.5 -- реген через 0.5 секунды после остановки бега

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local SurvivorsFolder = Workspace.Players.Survivors
local SkinsRoot = ReplicatedStorage.Assets.Skins.Survivors

local DEFAULT_CHARACTER_ANIMS = {
    Shedletsky = {
        Run = "rbxassetid://136252471123500"
    }
}

local SkinConfigCache = {}

local function loadSkinConfig(characterName, skinName)
    if not skinName or skinName == "" then return nil end
    SkinConfigCache[characterName] = SkinConfigCache[characterName] or {}
    if SkinConfigCache[characterName][skinName] then
        return SkinConfigCache[characterName][skinName]
    end
    local folder = SkinsRoot:FindFirstChild(characterName)
    if not folder then return nil end
    local skinFolder = folder:FindFirstChild(skinName)
    if not skinFolder then return nil end
    local configModule = skinFolder:FindFirstChild("Config")
    if not configModule then return nil end
    local cfg = require(configModule)
    SkinConfigCache[characterName][skinName] = cfg
    return cfg
end

local function isRunning(characterModel, animationId)
    if not animationId then return false end
    local characterName = characterModel.Name
    local skinName = characterModel:GetAttribute("SkinNameDisplay")
    local cfg = loadSkinConfig(characterName, skinName)
    if cfg and cfg.Animations and cfg.Animations.Run == animationId then
        return true
    end
    local defaults = DEFAULT_CHARACTER_ANIMS[characterName]
    if defaults and defaults.Run == animationId then
        return true
    end
    return false
end

local function getLagCompensation()
    local pingStat = stats().Network.ServerStatsItem["Data Ping"]
    if not pingStat then return 0.15 end
    local pingSec = pingStat:GetValue() / 1000
    return math.clamp(pingSec * 0.5, 0.05, 0.40)
end

-- создаём Drawing UI для стамины
local function createStaminaUI()
    local background = Drawing.new("Square")
    background.Filled = true
    background.Color = Color3.fromRGB(40, 40, 40) -- Темно-серый фон
    background.Thickness = 0
    background.Transparency = 0.7

    local fill = Drawing.new("Square")
    fill.Filled = true
    fill.Thickness = 0

    local border = Drawing.new("Square")
    border.Filled = false
    border.Color = Color3.fromRGB(200, 200, 200)
    border.Thickness = 1
    border.Transparency = 0.8

    local text = Drawing.new("Text")
    text.Color = Color3.fromRGB(255, 255, 255)
    text.Size = 12
    text.Center = false
    text.Outline = true
    text.OutlineColor = Color3.fromRGB(0, 0, 0)

    return {
        Background = background,
        Fill = fill,
        Border = border,
        Text = text
    }
end

local function updateStaminaUI(ui, position, stamina)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    
    if onScreen then
        -- Рассчитываем масштаб в зависимости от расстояния
        local distance = (Camera.CFrame.Position - position).Magnitude
        local distanceScale = math.clamp(50 / distance, 0.3, 1.5) -- Не слишком маленький и не слишком большой
        
        -- Размеры полоски
        local width = 60 * distanceScale
        local height = 8 * distanceScale
        
        -- Позиция справа от игрока
        local offsetX = 40 * distanceScale
        local offsetY = 0
        
        local x = screenPos.X + offsetX
        local y = screenPos.Y + offsetY
        
        -- Фон
        ui.Background.Position = Vector2.new(x - width/2, y - height/2)
        ui.Background.Size = Vector2.new(width, height)
        ui.Background.Visible = true
        
        -- Заполненная часть (цвет от зеленого к красному)
        local fillWidth = (stamina/100) * (width - 2) -- -2 для отступов от краев
        local r = math.floor(255 * (1 - stamina/100))
        local g = math.floor(255 * (stamina/100))
        local b = 0
        
        ui.Fill.Color = Color3.fromRGB(r, g, b)
        ui.Fill.Position = Vector2.new(x - width/2 + 1, y - height/2 + 1)
        ui.Fill.Size = Vector2.new(fillWidth, height - 2)
        ui.Fill.Visible = true
        
        -- Граница
        ui.Border.Position = Vector2.new(x - width/2, y - height/2)
        ui.Border.Size = Vector2.new(width, height)
        ui.Border.Visible = true
        
        -- Текст со стаминой
        ui.Text.Position = Vector2.new(x - width/2 + 2, y + height/2 + 2)
        ui.Text.Text = math.floor(stamina) .. "%"
        ui.Text.Visible = true
    else
        ui.Background.Visible = false
        ui.Fill.Visible = false
        ui.Border.Visible = false
        ui.Text.Visible = false
    end
end

local function trackSurvivor(char)
    local humanoid = char:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")
    local rootPart = char:WaitForChild("HumanoidRootPart")

    local stamina = MAX_STAMINA
    local running = false
    local animationId = ""
    local regenBlockedUntil = 0

    local ui = createStaminaUI()

    animator.AnimationPlayed:Connect(function(track)
        local id = track.Animation.AnimationId
        if id ~= animationId then
            animationId = id
            local nowRunning = isRunning(char, id)
            
            if nowRunning and not running then
                local lag = getLagCompensation()
                stamina = math.clamp(stamina - RUN_DRAIN * lag, 0, MAX_STAMINA)
            end

            if running and not nowRunning then
                regenBlockedUntil = tick() + REGEN_DELAY
            end

            running = nowRunning
        end
    end)

    task.spawn(function()
        while char.Parent == SurvivorsFolder do
            task.wait(UPDATE_RATE)

            if running then
                stamina = stamina - RUN_DRAIN * UPDATE_RATE
                if stamina <= 0 then
                    stamina = 0
                    regenBlockedUntil = tick() + 3
                end
            else
                if tick() >= regenBlockedUntil then
                    stamina = stamina + REGEN_RATE * UPDATE_RATE
                end
            end

            stamina = math.clamp(stamina, 0, MAX_STAMINA)

            -- смещение справа от игрока в мировых координатах
            local offset = Vector3.new(2, 1.5, 0)
            updateStaminaUI(ui, rootPart.Position + offset, stamina)
        end

        ui.Background:Remove()
        ui.Fill:Remove()
        ui.Border:Remove()
        ui.Text:Remove()
    end)
end

for _, char in ipairs(SurvivorsFolder:GetChildren()) do
    task.spawn(function() trackSurvivor(char) end)
end

SurvivorsFolder.ChildAdded:Connect(function(char)
    task.wait(0.1)
    trackSurvivor(char)
end)
