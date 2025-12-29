-- ═══════════════════════════════════════════════════════════════
--  TDS AUTO STRATEGY LIBRARY WITH GUI v2.0
--  Upload file ini ke GitHub sebagai raw file
-- ═══════════════════════════════════════════════════════════════

if not game:IsLoaded() then game.Loaded:Wait() end

-- ═══════════════════════════════════════════════════════════════
--  DETECT GAME STATE
-- ═══════════════════════════════════════════════════════════════

local function identify_game_state()
    local players = game:GetService("Players")
    local temp_player = players.LocalPlayer or players.PlayerAdded:Wait()
    local temp_gui = temp_player:WaitForChild("PlayerGui")
    
    while true do
        if temp_gui:FindFirstChild("LobbyGui") then
            return "LOBBY"
        elseif temp_gui:FindFirstChild("GameGui") then
            return "GAME"
        end
        task.wait(1)
    end
end

local game_state = identify_game_state()

-- ═══════════════════════════════════════════════════════════════
--  SERVICES & REFERENCES
-- ═══════════════════════════════════════════════════════════════

local send_request = request or http_request or httprequest or (GetDevice and GetDevice().request)

if not send_request then 
    warn("[TDS] Warning: No HTTP function available for webhooks") 
end

local replicated_storage = game:GetService("ReplicatedStorage")
local remote_func = replicated_storage:WaitForChild("RemoteFunction")
local remote_event = replicated_storage:WaitForChild("RemoteEvent")
local players_service = game:GetService("Players")
local local_player = players_service.LocalPlayer or players_service.PlayerAdded:Wait()
local player_gui = local_player:WaitForChild("PlayerGui")
local run_service = game:GetService("RunService")

-- ═══════════════════════════════════════════════════════════════
--  CORE VARIABLES
-- ═══════════════════════════════════════════════════════════════

local TDS = {
    placed_towers = {},
    active_strat = true,
    version = "2.0"
}

local upgrade_history = {}
local back_to_lobby_running = false
local auto_pickups_running = false
local auto_skip_running = false
local anti_lag_running = false

-- Currency tracking
local start_coins, current_total_coins, start_gems, current_total_gems = 0, 0, 0, 0
if game_state == "GAME" then
    pcall(function()
        repeat task.wait(1) until local_player:FindFirstChild("Coins")
        start_coins = local_player.Coins.Value
        current_total_coins = start_coins
        start_gems = local_player.Gems.Value
        current_total_gems = start_gems
    end)
end

-- Item names for rewards
local ItemNames = {
    ["17447507910"] = "Timescale Ticket(s)",
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
}

-- ═══════════════════════════════════════════════════════════════
--  UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function check_res_ok(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end

    local success, is_model = pcall(function()
        return data and data:IsA("Model")
    end)
    
    if success and is_model then return true end
    if type(data) == "userdata" then return true end

    return false
end

local function get_current_wave()
    local success, wave = pcall(function()
        local label = player_gui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
        local wave_num = label.Text:match("^(%d+)")
        return tonumber(wave_num) or 0
    end)
    return success and wave or 0
end

local function is_void_charm(obj)
    return math.abs(obj.Position.Y) > 999999
end

local function get_root()
    local char = local_player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- ═══════════════════════════════════════════════════════════════
--  WEBHOOK SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function get_all_rewards()
    local results = {
        Coins = 0, 
        Gems = 0, 
        XP = 0, 
        Time = "00:00",
        Status = "UNKNOWN",
        Others = {} 
    }
    
    local ui_root = player_gui:FindFirstChild("ReactGameNewRewards")
    local main_frame = ui_root and ui_root:FindFirstChild("Frame")
    local game_over = main_frame and main_frame:FindFirstChild("gameOver")
    local rewards_screen = game_over and game_over:FindFirstChild("RewardsScreen")
    
    local game_stats = rewards_screen and rewards_screen:FindFirstChild("gameStats")
    local stats_list = game_stats and game_stats:FindFirstChild("stats")
    
    if stats_list then
        for _, frame in ipairs(stats_list:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            if l1 and l2 and l1.Text:find("Time Completed:") then
                results.Time = l2.Text
                break
            end
        end
    end

    local top_banner = rewards_screen and rewards_screen:FindFirstChild("RewardBanner")
    if top_banner and top_banner:FindFirstChild("textLabel") then
        local txt = top_banner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    local section_rewards = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    if section_rewards then
        for _, item in ipairs(section_rewards:GetChildren()) do
            if tonumber(item.Name) then 
                local icon_id = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then icon_id = img.Image:match("%d+") or "0" end

                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0
                        
                        if text:find("Coins") then
                            results.Coins = amt
                        elseif text:find("Gems") then
                            results.Gems = amt
                        elseif text:find("XP") then
                            results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[icon_id] or "Unknown Item (" .. icon_id .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end
    
    return results
end

local function log_match_start()
    if not _G.SendWebhook or not send_request then return end

    local start_payload = {
        username = "TDS AutoStrat",
        embeds = {{
            title = "🚀 **Match Started Successfully**",
            description = "The AutoStrat has successfully loaded into a new game session and is beginning execution.",
            color = 3447003,
            
            fields = {
                { 
                    name = "🪙 Starting Coins", 
                    value = "```" .. tostring(start_coins) .. " Coins```", 
                    inline = true 
                },
                { 
                    name = "💎 Starting Gems", 
                    value = "```" .. tostring(start_gems) .. " Gems```", 
                    inline = true 
                },
                { 
                    name = "Status", 
                    value = "🟢 Running Script", 
                    inline = false 
                }
            },
            
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        send_request({
            Url = _G.Webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(start_payload)
        })
    end)
end

local function send_to_lobby()
    task.wait(1)
    local lobby_remote = replicated_storage.Network.Teleport["RE:backToLobby"]
    lobby_remote:FireServer()
end

local function handle_post_match()
    local ui_root
    repeat
        task.wait(1)

        local root = player_gui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local rewards_screen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        ui_root = rewards_screen and rewards_screen:FindFirstChild("RewardsSection")
    until ui_root

    if not ui_root then return send_to_lobby() end

    if not _G.SendWebhook or not send_request then
        send_to_lobby()
        return
    end

    local match = get_all_rewards()

    current_total_coins += match.Coins
    current_total_gems += match.Gems

    local bonus_string = ""
    if #match.Others > 0 then
        for _, res in ipairs(match.Others) do
            bonus_string = bonus_string .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n"
        end
    else
        bonus_string = "_No bonus rewards found._"
    end

    local post_data = {
        username = "TDS AutoStrat",
        embeds = {{
            title = (match.Status == "WIN" and "🏆 TRIUMPH" or "💀 DEFEAT"),
            color = (match.Status == "WIN" and 0x2ecc71 or 0xe74c3c),
            description = "### 📋 Match Overview\n" ..
                          "> **Status:** `" .. match.Status .. "`\n" ..
                          "> **Time:** `" .. match.Time .. "`",
            fields = {
                {
                    name = "✨ Rewards",
                    value = "```ansi\n" ..
                            "[2;33mCoins:[0m +" .. match.Coins .. "\n" ..
                            "[2;34mGems: [0m +" .. match.Gems .. "\n" ..
                            "[2;32mXP:   [0m +" .. match.XP .. "```",
                    inline = false
                },
                {
                    name = "🎁 Bonus Items",
                    value = bonus_string,
                    inline = true
                },
                {
                    name = "📊 Session Totals",
                    value = "```py\n# Total Amount\nCoins: " .. current_total_coins .. "\nGems:  " .. current_total_gems .. "```",
                    inline = true
                }
            },
            footer = { text = "Logged for " .. local_player.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        send_request({
            Url = _G.Webhook,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(post_data)
        })
    end)

    send_to_lobby()
end

-- ═══════════════════════════════════════════════════════════════
--  LOBBY & GAME FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function run_vote_skip()
    while true do
        local success = pcall(function()
            remote_func:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.2)
    end
end

local function match_ready_up()
    local ui_overrides = player_gui:WaitForChild("ReactOverridesVote", 30)
    local main_frame = ui_overrides and ui_overrides:WaitForChild("Frame", 30)
    
    if not main_frame then return end

    local vote_ready = nil

    while not vote_ready do
        local vote_node = main_frame:FindFirstChild("votes")
        
        if vote_node then
            local container = vote_node:FindFirstChild("container")
            if container then
                local ready = container:FindFirstChild("ready")
                if ready then
                    vote_ready = ready
                end
            end
        end
        
        if not vote_ready then
            task.wait(0.5) 
        end
    end

    repeat task.wait(0.1) until vote_ready.Visible == true

    run_vote_skip()
    log_match_start()
end

local function lobby_ready_up()
    pcall(function()
        remote_event:FireServer("LobbyVoting", "Ready")
    end)
end

local function do_place_tower(t_name, t_pos)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = t_pos
            }, t_name)
        end)

        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_upgrade_tower(t_obj, path_id)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = t_obj,
                Path = path_id
            })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

local function do_sell_tower(t_obj)
    while true do
        local ok, res = pcall(function()
            return remote_func:InvokeServer("Troops", "Sell", { Troop = t_obj })
        end)
        if ok and check_res_ok(res) then return true end
        task.wait(0.25)
    end
end

-- ═══════════════════════════════════════════════════════════════
--  AUTO FEATURES
-- ═══════════════════════════════════════════════════════════════

local function start_auto_pickups()
    if auto_pickups_running or not _G.AutoPickups then return end
    auto_pickups_running = true

    task.spawn(function()
        while _G.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = get_root()

            if folder and hrp then
                for _, item in ipairs(folder:GetChildren()) do
                    if not _G.AutoPickups then break end

                    if item:IsA("MeshPart") and (item.Name == "SnowCharm" or item.Name == "Lorebook") then
                        if not is_void_charm(item) then
                            local old_pos = hrp.CFrame
                            hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                            task.wait(0.2)
                            hrp.CFrame = old_pos
                            task.wait(0.3)
                        end
                    end
                end
            end

            task.wait(1)
        end

        auto_pickups_running = false
    end)
end

local function start_auto_skip()
    if auto_skip_running or not _G.AutoSkip then return end
    auto_skip_running = true

    task.spawn(function()
        while _G.AutoSkip do
            local skip_visible =
                player_gui:FindFirstChild("ReactOverridesVote")
                and player_gui.ReactOverridesVote:FindFirstChild("Frame")
                and player_gui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and player_gui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if skip_visible and skip_visible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                run_vote_skip()
            end

            task.wait(1)
        end

        auto_skip_running = false
    end)
end

local function start_back_to_lobby()
    if back_to_lobby_running then return end
    back_to_lobby_running = true

    task.spawn(function()
        while true do
            pcall(function()
                handle_post_match()
            end)
            task.wait(5)
        end
    end)
end

local function start_anti_lag()
    if anti_lag_running or not _G.AntiLag then return end
    anti_lag_running = true

    task.spawn(function()
        while _G.AntiLag do
            local towers_folder = workspace:FindFirstChild("Towers")
            local client_units = workspace:FindFirstChild("ClientUnits")
            local enemies = workspace:FindFirstChild("NPCs")

            if towers_folder then
                for _, tower in ipairs(towers_folder:GetChildren()) do
                    pcall(function()
                        local anims = tower:FindFirstChild("Animations")
                        local weapon = tower:FindFirstChild("Weapon")
                        local projectiles = tower:FindFirstChild("Projectiles")
                        
                        if anims then anims:Destroy() end
                        if projectiles then projectiles:Destroy() end
                        if weapon then weapon:Destroy() end
                    end)
                end
            end
            if client_units then
                for _, unit in ipairs(client_units:GetChildren()) do
                    pcall(function() unit:Destroy() end)
                end
            end
            if enemies then
                for _, npc in ipairs(enemies:GetChildren()) do
                    pcall(function() npc:Destroy() end)
                end
            end
            task.wait(0.5)
        end
        anti_lag_running = false
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  TDS PUBLIC API
-- ═══════════════════════════════════════════════════════════════

function TDS:Mode(difficulty)
    if game_state ~= "LOBBY" then 
        return false 
    end

    local lobby_hud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = lobby_hud and lobby_hud:WaitForChild("Frame", 30)
    local match_making = frame and frame:WaitForChild("matchmaking", 30)

    if match_making then
        local remote = replicated_storage:WaitForChild("RemoteFunction")
        local success = false
        
        repeat
            local ok, result = pcall(function()
                if difficulty == "Hardcore" then
                    return remote:InvokeServer("Multiplayer", "v2:start", {
                        mode = "hardcore",
                        count = 1
                    })
                elseif difficulty == "Pizza Party" then
                    return remote:InvokeServer("Multiplayer", "v2:start", {
                        mode = "halloween",
                        count = 1
                    })
                else
                    return remote:InvokeServer("Multiplayer", "v2:start", {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    })
                end
            end)

            if ok and check_res_ok(result) then
                success = true
            else
                task.wait(0.5) 
            end
        until success
    end

    return true
end

function TDS:Loadout(...)
    if game_state ~= "LOBBY" then 
        return false 
    end

    local lobby_hud = player_gui:WaitForChild("ReactLobbyHud", 30)
    local frame = lobby_hud and lobby_hud:WaitForChild("Frame", 30)
    local match_making = frame and frame:WaitForChild("matchmaking", 30)

    if match_making then
        local towers = {...}
        local remote = replicated_storage:WaitForChild("RemoteFunction")
        for _, tower_name in ipairs(towers) do
            if tower_name and tower_name ~= "" then
                pcall(function()
                    remote:InvokeServer("Inventory", "Equip", "tower", tower_name)
                end)
                task.wait(0.5)
            end
        end
    end
    
    return true
end

function TDS:Ready()
    match_ready_up()
end

function TDS:VoteSkip(req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end
    run_vote_skip()
end

function TDS:GetWave()
    return get_current_wave()
end

function TDS:Place(t_name, px, py, pz)
    if game_state ~= "GAME" then
        return false 
    end
    
    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        existing[child] = true
    end

    do_place_tower(t_name, Vector3.new(px, py, pz))

    local new_t
    repeat
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            if not existing[child] then
                new_t = child
                break
            end
        end
        task.wait(0.05)
    until new_t

    table.insert(self.placed_towers, new_t)
    return #self.placed_towers
end

function TDS:Upgrade(idx, p_id)
    local t = self.placed_towers[idx]
    if t then
        do_upgrade_tower(t, p_id or 1)
        upgrade_history[idx] = (upgrade_history[idx] or 0) + 1
    end
end

function TDS:SetTarget(idx, target_type, req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end

    local t = self.placed_towers[idx]
    if not t then return end

    pcall(function()
        remote_func:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = target_type
        })
    end)
end

function TDS:Sell(idx, req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end
    local t = self.placed_towers[idx]
    if t and do_sell_tower(t) then
        table.remove(self.placed_towers, idx)
        return true
    end
    return false
end

function TDS:SellAll(req_wave)
    if req_wave then
        repeat task.wait(0.5) until get_current_wave() >= req_wave
    end

    local towers_copy = {unpack(self.placed_towers)}
    for idx, t in ipairs(towers_copy) do
        if do_sell_tower(t) then
            for i, orig_t in ipairs(self.placed_towers) do
                if orig_t == t then
                    table.remove(self.placed_towers, i)
                    break
                end
            end
        end
    end

    return true
end

-- ═══════════════════════════════════════════════════════════════
--  GUI SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function CreateGUI()
    -- Remove old GUI
    if player_gui:FindFirstChild("TDSAutoStratGUI") then
        player_gui.TDSAutoStratGUI:Destroy()
    end
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TDSAutoStratGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = player_gui
    
    -- Main Frame
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 350, 0, 400)
    MainFrame.Position = UDim2.new(1, -360, 0, 10)
    MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 12)
    Corner.Parent = MainFrame
    
    -- Title Bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 50)
    TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame
    
    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 12)
    TitleCorner.Parent = TitleBar
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 15, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "🎮 TDS Auto Strat"
    Title.TextColor3 = Color3.fromRGB(100, 200, 255)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 16
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TitleBar
    
    -- Close Button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Size = UDim2.new(0, 40, 0, 40)
    CloseButton.Position = UDim2.new(1, -45, 0, 5)
    CloseButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    CloseButton.Text = "✕"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.TextSize = 18
    CloseButton.BorderSizePixel = 0
    CloseButton.Parent = TitleBar
    
    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 8)
    CloseCorner.Parent = CloseButton
    
    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
    end)
    
    -- Content Frame
    local Content = Instance.new("Frame")
    Content.Size = UDim2.new(1, -20, 1, -70)
    Content.Position = UDim2.new(0, 10, 0, 60)
    Content.BackgroundTransparency = 1
    Content.Parent = MainFrame
    
    -- Status Label
    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "StatusLabel"
    StatusLabel.Size = UDim2.new(1, 0, 0, 25)
    StatusLabel.Position = UDim2.new(0, 0, 0, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "Status: " .. game_state
    StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.TextSize = 14
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = Content
    
    -- Stats Frame
    local StatsFrame = Instance.new("Frame")
    StatsFrame.Size = UDim2.new(1, 0, 0, 120)
    StatsFrame.Position = UDim2.new(0, 0, 0, 35)
    StatsFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    StatsFrame.BorderSizePixel = 0
    StatsFrame.Parent = Content
    
    local StatsCorner = Instance.new("UICorner")
    StatsCorner.CornerRadius = UDim.new(0, 10)
    StatsCorner.Parent = StatsFrame
    
    local StatsLabel = Instance.new("TextLabel")
    StatsLabel.Name = "StatsLabel"
    StatsLabel.Size = UDim2.new(1, -20, 1, -20)
    StatsLabel.Position = UDim2.new(0, 10, 0, 10)
    StatsLabel.BackgroundTransparency = 1
    StatsLabel.Text = "📊 Stats Loading..."
    StatsLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
    StatsLabel.Font = Enum.Font.Gotham
    StatsLabel.TextSize = 13
    StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatsLabel.TextYAlignment = Enum.TextYAlignment.Top
    StatsLabel.Parent = StatsFrame
    
    -- Settings Frame
    local SettingsFrame = Instance.new("Frame")
    SettingsFrame.Size = UDim2.new(1, 0, 0, 150)
    SettingsFrame.Position = UDim2.new(0, 0, 0, 165)
    SettingsFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    SettingsFrame.BorderSizePixel = 0
    SettingsFrame.Parent = Content
    
    local SettingsCorner = Instance.new("UICorner")
    SettingsCorner.CornerRadius = UDim.new(0, 10)
    SettingsCorner.Parent = SettingsFrame
    
    local SettingsTitle = Instance.new("TextLabel")
    SettingsTitle.Size = UDim2.new(1, -20, 0, 25)
    SettingsTitle.Position = UDim2.new(0, 10, 0, 5)
    SettingsTitle.BackgroundTransparency = 1
    SettingsTitle.Text = "⚙️ Settings"
    SettingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    SettingsTitle.Font = Enum.Font.GothamBold
    SettingsTitle.TextSize = 14
    SettingsTitle.TextXAlignment = Enum.TextXAlignment.Left
    SettingsTitle.Parent = SettingsFrame
    
    -- Function to create toggle
    local function CreateToggle(name, yPos, globalVar)
        local ToggleFrame = Instance.new("Frame")
        ToggleFrame.Size = UDim2.new(1, -20, 0, 30)
        ToggleFrame.Position = UDim2.new(0, 10, 0, yPos)
        ToggleFrame.BackgroundTransparency = 1
        ToggleFrame.Parent = SettingsFrame
        
        local ToggleLabel = Instance.new("TextLabel")
        ToggleLabel.Size = UDim2.new(0.7, 0, 1, 0)
        ToggleLabel.BackgroundTransparency = 1
        ToggleLabel.Text = name
        ToggleLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
        ToggleLabel.Font = Enum.Font.Gotham
        ToggleLabel.TextSize = 12
        ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
        ToggleLabel.Parent = ToggleFrame
        
        local ToggleButton = Instance.new("TextButton")
        ToggleButton.Size = UDim2.new(0, 60, 0, 25)
        ToggleButton.Position = UDim2.new(1, -60, 0.5, -12.5)
        ToggleButton.BackgroundColor3 = _G[globalVar] and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
        ToggleButton.Text = _G[globalVar] and "ON" or "OFF"
        ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        ToggleButton.Font = Enum.Font.GothamBold
        ToggleButton.TextSize = 12
        ToggleButton.BorderSizePixel = 0
        ToggleButton.Parent = ToggleFrame
        
        local ToggleBtnCorner = Instance.new("UICorner")
        ToggleBtnCorner.CornerRadius = UDim.new(0, 6)
        ToggleBtnCorner.Parent = ToggleButton
        
        ToggleButton.MouseButton1Click:Connect(function()
            _G[globalVar] = not _G[globalVar]
            ToggleButton.Text = _G[globalVar] and "ON" or "OFF"
            ToggleButton.BackgroundColor3 = _G[globalVar] and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
            
            -- Actually trigger the functions
            if globalVar == "AutoSkip" then
                if _G[globalVar] then
                    start_auto_skip()
                    print("[TDS] Auto Skip enabled")
                else
                    auto_skip_running = false
                    print("[TDS] Auto Skip disabled")
                end
            elseif globalVar == "AutoPickups" then
                if _G[globalVar] then
                    start_auto_pickups()
                    print("[TDS] Auto Pickups enabled")
                else
                    auto_pickups_running = false
                    print("[TDS] Auto Pickups disabled")
                end
            elseif globalVar == "AntiLag" then
                if _G[globalVar] then
                    start_anti_lag()
                    print("[TDS] Anti Lag enabled")
                else
                    anti_lag_running = false
                    print("[TDS] Anti Lag disabled")
                end
            end
        end)
    end
    
    CreateToggle("Auto Skip Waves", 35, "AutoSkip")
    CreateToggle("Auto Pickup Items", 70, "AutoPickups")
    CreateToggle("Anti Lag", 105, "AntiLag")
    
    -- Update stats
    local matchStartTime = tick()
    task.spawn(function()
        while ScreenGui.Parent do
            local wave = get_current_wave()
            local coins = 0
            local gems = 0
            local duration = tick() - matchStartTime
            
            pcall(function()
                coins = local_player.Coins.Value
                gems = local_player.Gems.Value
            end)
            
            -- Format duration as MM:SS
            local minutes = math.floor(duration / 60)
            local seconds = math.floor(duration % 60)
            local timeString = string.format("%02d:%02d", minutes, seconds)
            
            StatsLabel.Text = string.format(
                "📊 Statistics\n\n" ..
                "Wave: %d\n" ..
                "Towers: %d\n" ..
                "Coins: %d (+%d)\n" ..
                "Gems: %d (+%d)\n" ..
                "Time: %s",
                wave,
                #TDS.placed_towers,
                coins, coins - start_coins,
                gems, gems - start_gems,
                timeString
            )
            
            task.wait(1)
        end
    end)
    
    print("[TDS] GUI Created!")
end

-- ═══════════════════════════════════════════════════════════════
--  ENHANCED AUTO FEATURES MANAGEMENT
-- ═══════════════════════════════════════════════════════════════

function TDS:StartAutoFeatures()
    print("[TDS] Starting auto features...")
    
    -- Always start back to lobby
    start_back_to_lobby()
    
    -- Start auto skip if enabled
    if _G.AutoSkip then
        start_auto_skip()
        print("[TDS] ✅ Auto Skip enabled")
    end
    
    -- Start auto pickups if enabled
    if _G.AutoPickups then
        start_auto_pickups()
        print("[TDS] ✅ Auto Pickups enabled")
    end
    
    -- Start anti lag if enabled
    if _G.AntiLag then
        start_anti_lag()
        print("[TDS] ✅ Anti Lag enabled")
    end
end

-- ═══════════════════════════════════════════════════════════════
--  STRATEGY EXECUTION WRAPPER
-- ═══════════════════════════════════════════════════════════════

function TDS:ExecuteStrategy(strategyFunction)
    print("[TDS] Executing strategy...")
    
    -- Wait for game to be ready
    if game_state == "LOBBY" then
        -- Wait for join game
        print("[TDS] Waiting for game to start...")
        repeat 
            task.wait(1) 
        until player_gui:FindFirstChild("GameGui") or player_gui:FindFirstChild("ReactGameIntermission")
        
        task.wait(2) -- Additional wait for game initialization
    end
    
    -- Execute the strategy
    task.spawn(function()
        local success, err = pcall(strategyFunction)
        if not success then
            warn("[TDS] Strategy error: " .. tostring(err))
        else
            print("[TDS] ✅ Strategy completed!")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  AUTO-START FEATURES & GUI
-- ═══════════════════════════════════════════════════════════════

-- Start auto features immediately
TDS:StartAutoFeatures()

-- Create GUI if AutoStrat is enabled
if _G.AutoStrat then
    task.spawn(function()
        task.wait(1) -- Small delay for initialization
        CreateGUI()
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  EXPORT
-- ═══════════════════════════════════════════════════════════════

print("═══════════════════════════════════════")
print("🎮 TDS Auto Strategy Library v" .. TDS.version)
print("State: " .. game_state)
print("Auto Skip: " .. tostring(_G.AutoSkip))
print("Auto Pickups: " .. tostring(_G.AutoPickups))
print("Anti Lag: " .. tostring(_G.AntiLag))
print("═══════════════════════════════════════")

-- Share globally
getgenv().TDS = TDS
shared.TDS = TDS

return TDS
