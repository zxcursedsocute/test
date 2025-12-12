-- Конфигурация стамины
local MAX_STAMINA = 100
local RUN_DRAIN = 10        -- расход в секунду
local REGEN_RATE = 20       -- реген в секунду
local UPDATE_RATE = 0.1     -- частота обновления стамины

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivorsFolder = Workspace:WaitForChild("Players"):WaitForChild("Survivors")
local SkinsRoot = ReplicatedStorage.Assets.Skins.Survivors

-- Анимации по умолчанию для каждого персонажа
-- Здесь ты добавляешь всех своих персонажей
local DEFAULT_CHARACTER_ANIMS = {
    Shedletsky = {
        Run = "rbxassetid://136252471123500"
        -- Idle / Walk / Hurt добавляются по мере необходимости
    }
}

-- Кэш конфигов скинов
local SkinConfigCache = {}

local function loadSkinConfig(characterName, skinName)
    if not skinName or skinName == "" then
        return nil
    end

    SkinConfigCache[characterName] = SkinConfigCache[characterName] or {}
    if SkinConfigCache[characterName][skinName] then
        return SkinConfigCache[characterName][skinName]
    end

    local charFolder = SkinsRoot:FindFirstChild(characterName)
    if not charFolder then return nil end

    local skinFolder = charFolder:FindFirstChild(skinName)
    if not skinFolder then return nil end

    local configModule = skinFolder:FindFirstChild("Config")
    if not configModule then return nil end

    local config = require(configModule)
    SkinConfigCache[characterName][skinName] = config
    return config
end

-- Определение: является ли текущая анимация бегом
local function isRunning(characterModel, animationId)
    if not animationId then return false end

    local characterName = characterModel.Name
    local skinName = characterModel:GetAttribute("SkinNameDisplay")

    local skinConfig = loadSkinConfig(characterName, skinName)

    -- Проверяем анимацию скина
    if skinConfig and skinConfig.Animations and skinConfig.Animations.Run then
        if animationId == skinConfig.Animations.Run then
            return true
        end
    end

    -- Проверяем дефолтную анимацию персонажа
    local defaults = DEFAULT_CHARACTER_ANIMS[characterName]
    if defaults and defaults.Run == animationId then
        return true
    end

    return false
end


-- Система стамины для одного персонажа
local function trackSurvivor(characterModel)
    local humanoid = characterModel:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    -- Стамина персонажа
    local stamina = MAX_STAMINA

    -- Текущая анимация
    local currentAnimationId = ""

    animator.AnimationPlayed:Connect(function(track)
        local anim = track.Animation
        currentAnimationId = anim.AnimationId
    end)

    -- Основной цикл стамины
    task.spawn(function()
        while characterModel.Parent == SurvivorsFolder do
            task.wait(UPDATE_RATE)

            local running = isRunning(characterModel, currentAnimationId)

            if running then
                stamina -= RUN_DRAIN * UPDATE_RATE
            else
                stamina += REGEN_RATE * UPDATE_RATE
            end

            -- Клампим
            if stamina < 0 then stamina = 0 end
            if stamina > MAX_STAMINA then stamina = MAX_STAMINA end

            -- Если персонаж бежит — выводим в консоль
            if running then
                print(
                    tostring(characterModel:GetAttribute("Username") or "UnknownUser"),
                    "|", characterModel.Name,
                    "|", currentAnimationId,
                    "| Stamina:", math.floor(stamina)
                )
            end
        end
    end)
end


-- Отслеживаем всех существующих
for _, character in ipairs(SurvivorsFolder:GetChildren()) do
    task.spawn(function()
        trackSurvivor(character)
    end)
end

-- Новые персонажи
SurvivorsFolder.ChildAdded:Connect(function(character)
    task.wait(0.1)
    trackSurvivor(character)
end)
