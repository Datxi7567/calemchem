local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local STOP = false

-- ===== CONNECTION MANAGER =====
local Connections = {}

local function addConn(conn)
    table.insert(Connections, conn)
end

local function stopAll()
    for _, v in pairs(Connections) do
        pcall(function()
            v:Disconnect()
        end)
    end
    table.clear(Connections)
    warn("ALL SCRIPT STOPPED")
end

-- ===== CHECK LEVEL =====
local triggered = false

task.spawn(function()
    local levelValue = player:WaitForChild("Data"):WaitForChild("Level")

    while true do
        if levelValue.Value >= 8000 and not triggered then
            triggered = true
            STOP = true

            -- dừng toàn bộ
            stopAll()

            -- reset nhân vật
            player.Character:BreakJoints()

            -- đợi respawn
            player.CharacterAdded:Wait()
            task.wait(1)

            -- abandon quest 1 lần
            local abandonRemote = game:GetService("ReplicatedStorage")
                :WaitForChild("RemoteEvents")
                :WaitForChild("QuestAbandon")

            abandonRemote:FireServer("repeatable")

            warn("Quest Abandoned")

            break
        end

        task.wait(0.5)
    end
end)

-- ===== MAIN =====
local function startScript(char)
    if STOP then return end

    local humanoid = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")

    -- ===== NOCLIP (FIXED) =====
    addConn(RunService.Heartbeat:Connect(function()
        if STOP then return end

        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide == true then
                part.CanCollide = false
            end
        end
    end))

    -- ===== ATTACK =====
    local remote = game:GetService("ReplicatedStorage")
        :WaitForChild("CombatSystem")
        :WaitForChild("Remotes")
        :WaitForChild("RequestHit")

    addConn(RunService.Heartbeat:Connect(function()
        if STOP then return end
        remote:FireServer()
    end))

    -- ===== EQUIP =====
    local tool = player.Backpack:WaitForChild("Gryphon")
    humanoid:EquipTool(tool)

    -- ===== NẰM =====
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.AutoRotate = false

    addConn(RunService.RenderStepped:Connect(function()
        if STOP then return end
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(-90), 0, 0)
    end))

    -- ===== QUEST =====
    local questRemote = game:GetService("ReplicatedStorage")
        :WaitForChild("RemoteEvents")
        :WaitForChild("QuestAccept")

    local QUEST_NAME = "QuestNPC13"
    local REQUIRED_KILLS = 5

    local killCount = 0
    local currentTarget = nil
    local lastQuestTime = 0

    local function acceptQuest()
        if STOP then return end
        if tick() - lastQuestTime > 5 then
            lastQuestTime = tick()
            questRemote:FireServer(QUEST_NAME)
        end
    end

    task.delay(1, acceptQuest)

    -- ===== FIND NPC =====
    local function getNearestNPC()
        local nearest = nil
        local minDist = 1000

        for _, npc in pairs(workspace:WaitForChild("NPCs"):GetChildren()) do
            -- Chỉ tìm Curse1-5
            if (npc.Name == "Curse1" or npc.Name == "Curse2" or npc.Name == "Curse3" or npc.Name == "Curse4" or npc.Name == "Curse5") and npc:FindFirstChild("HumanoidRootPart") then
                if npc.Humanoid.Health > 0 then
                    local dist = (npc.HumanoidRootPart.Position - root.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        nearest = npc
                    end
                end
            end
        end

        return nearest
    end

    -- ===== TRACK KILL =====
    local tracked = {}

    local function trackKill(npc)
        if npc and npc:FindFirstChild("Humanoid") and not tracked[npc] then
            tracked[npc] = true

            npc.Humanoid.Died:Connect(function()
                if STOP then return end

                killCount += 1

                if killCount >= REQUIRED_KILLS then
                    killCount = 0
                    task.wait(1)
                    acceptQuest()
                end
            end)
        end
    end

    -- ===== FOLLOW =====
    local lastNPCPosition = nil
    
    task.spawn(function()
        while not STOP do
            local npc = getNearestNPC()

            if npc then
                if npc ~= currentTarget then
                    currentTarget = npc
                    trackKill(npc)
                end

                while npc and npc.Parent and npc:FindFirstChild("Humanoid") and npc.Humanoid.Health > 0 and not STOP do
                    local head = npc:FindFirstChild("Head") or npc:FindFirstChild("HumanoidRootPart")

                    if head then
                        lastNPCPosition = head.Position + Vector3.new(0, 8.3, 0)
                        local direction = (lastNPCPosition - root.Position)

                        root.Velocity = direction * 3
                    end

                    RunService.Heartbeat:Wait()
                end
            else
                -- Nếu không tìm thấy NPC, neo tại vị trí NPC cuối cùng
                if lastNPCPosition then
                    local direction = (lastNPCPosition - root.Position)
                    root.Velocity = direction * 3
                    root.CFrame = CFrame.new(lastNPCPosition)
                else
                    task.wait(0.3)
                end

                RunService.Heartbeat:Wait()
            end
        end
    end)

    -- ===== AUTO STAT =====
    local statRemote = game:GetService("ReplicatedStorage")
        :WaitForChild("RemoteEvents")
        :WaitForChild("AllocateStat")

    local defenseSpent = 0
    local maxDefense = 3

    task.spawn(function()
        while not STOP do
            local level = player.Data.Level.Value
            local stat = player.Data.StatPoints.Value

            if level >= 1 and level <= 8000 and stat > 0 then
                if defenseSpent < maxDefense then
                    -- Allocate to Defense first (up to 200)
                    statRemote:FireServer("Defense", stat)
                    defenseSpent += stat
                else
                    -- After 200 Defense, allocate remaining to Melee
                    statRemote:FireServer("Sword", stat)
                end
            end

            task.wait(1)
        end
    end)
    
    -- ===== REQUEST ABILITY EVERY 7 SECONDS =====
    local abilityRemote = game:GetService("ReplicatedStorage")
        :WaitForChild("AbilitySystem")
        :WaitForChild("Remotes")
        :WaitForChild("RequestAbility")
    
    task.spawn(function()
        while not STOP do
            abilityRemote:FireServer(1)
            task.wait(1)
        end
    end)
end

-- ===== START =====
local char = player.Character or player.CharacterAdded:Wait()
startScript(char)

-- ===== RESPAWN =====
player.CharacterAdded:Connect(function(newChar)
    task.wait(1)
    if not STOP then
        startScript(newChar)
    end
end)