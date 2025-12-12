local MAX_STAMINA = 100
local RUN_DRAIN = 10
local REGEN_RATE = 20
local UPDATE_RATE = 0.1

local RUN_SPEED_THRESHOLD = 20 -- выше этой скорости считается бег

local Workspace = game:GetService("Workspace")
local SurvivorsFolder = Workspace.Players.Survivors

local function trackSurvivor(char)
    local humanoid = char:WaitForChild("Humanoid")

    local stamina = MAX_STAMINA
    local running = false
    local regenBlockedUntil = 0

    while char.Parent == SurvivorsFolder do
        task.wait(UPDATE_RATE)

        -- определяем бег по скорости
        local nowRunning = humanoid.WalkSpeed >= RUN_SPEED_THRESHOLD

        -- если стамина была 0, ставим задержку 3 сек
        if stamina <= 0 then
            nowRunning = false
            regenBlockedUntil = tick() + 3
        end

        -- если только что перестал бегать — ставим задержку 1 сек
        if running and not nowRunning then
            regenBlockedUntil = tick() + 1
        end

        running = nowRunning

        if running then
            stamina -= RUN_DRAIN * UPDATE_RATE
        else
            if tick() >= regenBlockedUntil then
                stamina += REGEN_RATE * UPDATE_RATE
            end
        end

        stamina = math.clamp(stamina, 0, MAX_STAMINA)

        -- выводим в консоль, когда бежит
        if running then
            print(
                tostring(char:GetAttribute("Username") or "Unknown"),
                "|", char.Name,
                "| WalkSpeed:", humanoid.WalkSpeed,
                "| Stamina:", math.floor(stamina)
            )
        end
    end
end

-- запуск для всех существующих Survivors
for _, char in ipairs(SurvivorsFolder:GetChildren()) do
    task.spawn(function() trackSurvivor(char) end)
end

-- новые персонажи
SurvivorsFolder.ChildAdded:Connect(function(char)
    task.wait(0.1)
    trackSurvivor(char)
end)
