local MAX_STAMINA = 100
local RUN_DRAIN = 10
local REGEN_RATE = 20
local UPDATE_RATE = 0.1
local REGEN_DELAY = 0.5 -- заменили с 1 на 0.5

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

local function createStaminaUI()
    local background = Drawing.new("Square")
    background.Size = Vector2.new(6, 50)
    background.Color = Color3.new(0.1,0.1,0.1)
    background.Filled = true
    background.Thickness = 1

    local fill = Drawing.new("Square")
    fill.Size = Vector2.new(6,50)
    fill.Color = Color3.new(0,1,0)
    fill.Filled = true
    fill.Thickness = 1

    local text = Drawing.new("Text")
    text.Color = Color3.new(1,1,1)
    text.Size = 14
    text.Center = true
    text.Outline = true
    text.OutlineColor = Color3.new(0,0,0)

    return {Background = background, Fill = fill, Text = text}
end

local function updateStaminaUI(ui, position, stamina)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    if onScreen then
        ui.Background.Visible = true
        ui.Fill.Visible = true
        ui.Text.Visible = true

        ui.Background.Position = Vector2.new(screenPos.X + 20, screenPos.Y - 25)
        ui.Fill.Position = Vector2.new(screenPos.X + 20, screenPos.Y - 25 + (50 - (stamina/100)*50))
        ui.Fill.Size = Vector2.new(6, (stamina/100)*50)
        ui.Text.Position = Vector2.new(screenPos.X + 20, screenPos.Y + 30)
        ui.Text.Text = string.format("%d/%d", math.floor(stamina), MAX_STAMINA)
    else
        ui.Background.Visible = false
        ui.Fill.Visible = false
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
            local lag = getLagCompensation()
            if nowRunning and not running then
                stamina -= RUN_DRAIN * lag
                if stamina < 0 then stamina = 0 end
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
                stamina -= RUN_DRAIN * UPDATE_RATE
                if stamina <= 0 then
                    stamina = 0
                    regenBlockedUntil = tick() + 3
                end
            else
                if tick() >= regenBlockedUntil then
                    stamina += REGEN_RATE * UPDATE_RATE
                end
            end

            stamina = math.clamp(stamina, 0, MAX_STAMINA)
            updateStaminaUI(ui, rootPart.Position + Vector3.new(2,3,0), stamina)
        end

        -- чистим UI при удалении персонажа
        ui.Background:Remove()
        ui.Fill:Remove()
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
