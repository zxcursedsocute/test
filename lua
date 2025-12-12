local MAX_STAMINA = 100
local RUN_DRAIN = 10
local REGEN_RATE = 20
local UPDATE_RATE = 0.05
local EPSILON = 0.001 -- Для сравнения с нулём с учётом погрешности

-----------------------------------------------------
-- Автоматическая компенсация задержки (по пингу)
-----------------------------------------------------
local function getLagCompensation()
    local pingStat = stats().Network.ServerStatsItem["Data Ping"]
    if not pingStat then
        return 0.15 -- fallback
    end

    local pingMs = pingStat:GetValue()
    local pingSec = pingMs / 1000

    -- половина round-trip — реальная задержка репликации
    return math.clamp(pingSec * 0.5, 0.05, 0.40)
end

-----------------------------------------------------
-- Сервисы и пути
-----------------------------------------------------
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivorsFolder = Workspace.Players.Survivors
local SkinsRoot = ReplicatedStorage.Assets.Skins.Survivors

-----------------------------------------------------
-- Дефолтные анимации персонажей (можно расширять)
-----------------------------------------------------
local DEFAULT_CHARACTER_ANIMS = {
    Shedletsky = {
        Run = "rbxassetid://136252471123500"
    }
}

-----------------------------------------------------
-- Кэш конфигов скинов
-----------------------------------------------------
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

    local success, cfg = pcall(require, configModule)
    if not success then return nil end
    
    SkinConfigCache[characterName][skinName] = cfg

    return cfg
end

-----------------------------------------------------
-- Проверка, является ли анимация бегом
-----------------------------------------------------
local function isRunning(characterModel, animationId)
    if not animationId then return false end

    local characterName = characterModel.Name
    local skinName = characterModel:GetAttribute("SkinNameDisplay") or ""

    -- проверяем анимации скина
    local cfg = loadSkinConfig(characterName, skinName)
    if cfg and cfg.Animations and cfg.Animations.Run == animationId then
        return true
    end

    -- проверяем дефолтные анимации
    local defaults = DEFAULT_CHARACTER_ANIMS[characterName]
    if defaults and defaults.Run == animationId then
        return true
    end

    return false
end

-----------------------------------------------------
-- Основной трекинг конкретного Survivor
-----------------------------------------------------
local function trackSurvivor(char)
    local humanoid = char:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    local stamina = MAX_STAMINA
    local running = false
    local animationId = ""
    local lastStaminaCheck = tick()

    -- время, до которого реген заблокирован
    local regenBlockedUntil = 0

    animator.AnimationPlayed:Connect(function(track)
        local id = track.Animation.AnimationId

        if id ~= animationId then
            animationId = id
            local nowRunning = isRunning(char, id)
            local lag = getLagCompensation()

            -- компенсируем задержку при переходе в бег
            if nowRunning and not running then
                stamina = math.clamp(stamina - RUN_DRAIN * lag, 0, MAX_STAMINA)
            end

            -- задержка перед началом регена (1 сек после остановки)
            if running and not nowRunning then
                regenBlockedUntil = tick() + 1
            end

            running = nowRunning
        end
    end)

    -------------------------------------------------
    -- Цикл обновления стамины
    -------------------------------------------------
    while char.Parent == SurvivorsFolder do
        local now = tick()
        local deltaTime = math.min(now - lastStaminaCheck, UPDATE_RATE * 2) -- Защита от больших дельт
        lastStaminaCheck = now
        
        task.wait(UPDATE_RATE)

        if running then
            stamina = stamina - RUN_DRAIN * deltaTime
            
            -- Используем EPSILON для сравнения с нулём
            if stamina <= EPSILON then
                stamina = 0
                regenBlockedUntil = tick() + 3
                -- Принудительно останавливаем бег при нулевой стамине
                running = false
            end
        else
            -- реген только если время вышло
            if tick() >= regenBlockedUntil then
                stamina = stamina + REGEN_RATE * deltaTime
            end
        end

        stamina = math.clamp(stamina, 0, MAX_STAMINA)

        -- выводим только во время бега и если стамина менялась
        if running then
            -- Округляем до целого для красивого вывода
            local displayStamina = math.floor(stamina + 0.5)
            print(
                tostring(char:GetAttribute("Username") or "Unknown"),
                "|", char.Name,
                "|", string.sub(animationId, 1, 30) .. (string.len(animationId) > 30 and "..." or ""),
                "| Stamina:", displayStamina
            )
        end
    end
end

-----------------------------------------------------
-- Запуск для уже существующих Survivors
-----------------------------------------------------
for _, char in ipairs(SurvivorsFolder:GetChildren()) do
    if char:IsA("Model") then
        task.spawn(function()
            trackSurvivor(char)
        end)
    end
end

-----------------------------------------------------
-- Новые Survivors
-----------------------------------------------------
SurvivorsFolder.ChildAdded:Connect(function(char)
    task.wait(0.1)
    if char:IsA("Model") then
        trackSurvivor(char)
    end
end)
