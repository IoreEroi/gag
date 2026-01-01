-- 🧠 BRAINROT FINDER v8.1 - WORKING DETECTION + FIXED SERVER HOPPER + BRAINROT TRACKER
-- FIXED SERVER HOPPING - Uses Roblox API as primary source with backend fallback
-- Based on ACTUAL game structure: AnimalOverhead (SurfaceGui) → Generation (TextLabel)
-- Skips $1/s templates in Debris folder, finds REAL brainrots
-- Carica lo status da GitHub

-- CONFIG
local KEYS_URL = "https://raw.githubusercontent.com/IoreEroi/gag/main/keys.txt"

-- hash della key che TU hai generato per questo cliente
local CLIENT_HASH = "3e33252c5ebd41242f306323ea377743f86dbcd3399aa873032cc299498ac524"

-- scarica lista hash
local success, data = pcall(function()
    return game:HttpGet(KEYS_URL)
end)

if not success then
    warn("Errore nel controllo chiavi")
    return
end

-- controlla se l'hash esiste
if not data:find(CLIENT_HASH, 1, true) then
    warn("Key not valid or revoked")
    return
end

-- =========================
-- SCRIPT VERO PARTE QUI
-- =========================
print(" ✅")

-- SERVICES
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait() until Players.LocalPlayer
local LocalPlayer = Players.LocalPlayer

-- ============ COMPLETE CONFIGURATION ============
local DEFAULT_CONFIG = {
    -- Brainrot Game ID
    PLACE_ID = 109983668079237,
    
    -- ACTUAL BRAINROT STRUCTURE (CONFIRMED WORKING)
    BRAINROT_STRUCTURE = {
        SURFACE_GUI_NAME = "AnimalOverhead",           -- SurfaceGui, not BillboardGui
        GENERATION_LABEL = "Generation",               -- Shows income like '90/s'
        DISPLAY_NAME_LABEL = "DisplayName",            -- Shows brainrot name
        MUTATION_LABEL = "Mutation",                   -- Shows type like 'Gold'
        RARITY_LABEL = "Rarity",                       -- Shows rarity
        PRICE_LABEL = "Price",                         -- Shows price
        STOLEN_LABEL = "Stolen"                        -- Shows stolen status
    },
    
    -- BACKEND API SETTINGS
    USE_BACKEND_API = true,
    BACKEND_API_URL = "https://api.allports.exposed",
    API_TIMEOUT = 10,
    USE_PROXIES = true,
    MAX_PROXY_RETRIES = 3,
    
    -- ROXBLOX API SETTINGS (NEW - PRIMARY METHOD)
    USE_ROBLOX_API = true,  -- Enable the reliable Roblox API method
    
    -- WEBHOOK SETTINGS
    ENABLE_WEBHOOK = true,
    WEBHOOK_URL = "",
    WEBHOOK_COOLDOWN = 5,
    
    -- THRESHOLDS - ADJUSTED FOR REAL BRAINROTS
    MIN_INCOME = 100,          -- Minimum income to track ($100/s to skip $1/s templates)
    HIGH_THRESHOLD = 1000000,  -- $1M - Changed from 5000 to 1000000
    ULTRA_THRESHOLD = 5000000, -- $5M
    MILLION_THRESHOLD = 1000000, -- $1M threshold for Discord notifications
    
    -- TIMING SETTINGS
    SCAN_WAIT_TIME = 15,       -- Increased from 10 to 15
    SERVER_HOP_DELAY = 1,
    MAX_ATTEMPTS = 999,
    MIN_PLAYERS = 2,
    MAX_PLAYERS = 7,
    MAX_SERVER_SIZE = 8,
    
    -- AUTO REJOIN SETTINGS
    AUTO_REJOIN_ENABLED = true,
    AUTO_REJOIN_DELAY = 5,
    
    -- AUTO START
    AUTO_START = true,
    AUTO_START_DELAY = 3,
    
    -- FAST HOP SETTINGS
    FAST_HOP_AFTER = 1,
    FAST_HOP_INTERVAL = 0.3,
    MAX_FAST_HOPS = 50,
    
    -- RETRY SETTINGS
    RETRY_DELAY = 0.5,
    MAX_SERVER_RETRIES = 3,
    MAX_SERVERS_TO_TRY = 10,
    
    -- GUI SETTINGS
    GUI_ENABLED = true,
    GUI_POSITION = {X = 0.5, Y = 0.5},
    GUI_WIDTH = 500,  -- Increased width for webhook input
    GUI_HEIGHT = 550, -- Increased height
    
    -- DEBUG SETTINGS
    DEBUG_MODE = true,
    LOG_TO_CONSOLE = true,
    
    -- NOTIFICATION SETTINGS
    NOTIFY_ON_FIND = true,
    NOTIFY_ON_ERROR = true,
    NOTIFY_1M_PLUS = true,  -- Send Discord for 1M+ brainrots
    
    -- BRAINROT TRACKER SETTINGS
    MAX_SAVED_BRAINROTS = 10,
    TRACKER_REFRESH_INTERVAL = 5,
    
    -- STUCK DETECTION
    MAX_RESCANS = 10,
    STUCK_TIMEOUT = 30,
    FORCE_HOP_AFTER = 5
}

-- STATE
local sentThisServer = false
local visitedServers = {}
local attemptCount = 0
local blacklistedServers = {}
local isRunning = false
local currentStatus = "Ready"
local foundCount = 0
local fastHopMode = false
local fastHopCount = 0
local lastHopTime = 0
local lastWebhookTime = 0
local lastScanTime = 0
local last1MWebhookTime = 0
local consecutiveNoBrainrot = 0
local millionPlusCount = 0
local lastFoundBrainrots = {} -- Track all found brainrots per scan

-- BRAINROT TRACKER
local savedBrainrots = {}
local brainrotTrackerPanel
local brainrotTrackerContainer

-- GUI ELEMENTS
local ScreenGui, MainFrame, StatusText, Stat1Value, Stat2Value, Stat3Value, Stat4Value, ConsoleScrolling, ConsoleLayout
local StartButton, StopButton, DebugScanButton, ForceHopButton, MillionCounter, WebhookInput, SaveWebhookButton
local SettingsFrame, SettingsButton, SettingsOpen = false

-- ============ UTILITY FUNCTIONS ============
local function safeWait(seconds)
    local start = tick()
    while tick() - start < seconds and isRunning do
        task.wait(0.1)
    end
end

-- ============ LOGGING SYSTEM ============
local function logToConsole(message, color)
    if DEFAULT_CONFIG.LOG_TO_CONSOLE then
        local timestamp = os.date("%H:%M:%S")
        print("[" .. timestamp .. "] " .. tostring(message))
    end
    
    if ConsoleScrolling and ConsoleLayout and typeof(ConsoleScrolling) == "Instance" and ConsoleScrolling:IsA("ScrollingFrame") then
        local success, result = pcall(function()
            local logEntry = Instance.new("TextLabel")
            logEntry.Name = "LogEntry_" .. tick()
            logEntry.Size = UDim2.new(1, -10, 0, 20)
            logEntry.BackgroundTransparency = 1
            logEntry.Text = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(message)
            logEntry.TextColor3 = color or Color3.fromRGB(200, 200, 200)
            logEntry.TextSize = 12
            logEntry.Font = Enum.Font.Gotham
            logEntry.TextXAlignment = Enum.TextXAlignment.Left
            logEntry.TextWrapped = true
            logEntry.Parent = ConsoleScrolling
            
            task.wait(0.01)
            if ConsoleLayout.AbsoluteContentSize then
                ConsoleScrolling.CanvasSize = UDim2.new(0, 0, 0, ConsoleLayout.AbsoluteContentSize.Y)
                ConsoleScrolling.CanvasPosition = Vector2.new(0, ConsoleLayout.AbsoluteContentSize.Y)
            end
            
            if #ConsoleScrolling:GetChildren() > 50 then
                for i = 1, 10 do
                    local child = ConsoleScrolling:FindFirstChildOfClass("TextLabel")
                    if child then
                        child:Destroy()
                    end
                end
            end
        end)
        
        if not success and DEFAULT_CONFIG.DEBUG_MODE then
            print("GUI Error: " .. tostring(result))
        end
    end
end

-- ============ CONFIG SYSTEM ============
local function loadConfig()
    local success, savedConfig = pcall(function()
        if readfile and isfile and isfile("brainrot_config.json") then
            local content = readfile("brainrot_config.json")
            if content and #content > 0 then
                return HttpService:JSONDecode(content)
            end
        end
        return nil
    end)
    
    if success and savedConfig and type(savedConfig) == "table" then
        for key, value in pairs(savedConfig) do
            if DEFAULT_CONFIG[key] ~= nil then
                DEFAULT_CONFIG[key] = value
            end
        end
        logToConsole("✓ Configuration loaded", Color3.fromRGB(0, 200, 255))
        return true
    else
        logToConsole("⚠ Using default configuration", Color3.fromRGB(255, 150, 0))
        return false
    end
end

local function saveConfig()
    local success, errorMsg = pcall(function()
        if writefile then
            writefile("brainrot_config.json", HttpService:JSONEncode(DEFAULT_CONFIG))
            return true
        end
        return false
    end)
    
    if success then
        logToConsole("✓ Configuration saved", Color3.fromRGB(0, 200, 255))
        return true
    else
        logToConsole("✗ Save error: " .. tostring(errorMsg), Color3.fromRGB(255, 100, 100))
        return false
    end
end

-- ============ WORKING BRAINROT DETECTION FUNCTIONS ============
-- SMART INCOME PARSING (SKIPS $1/s TEMPLATES)
local function parseBrainrotIncome(text)
    if not text or type(text) ~= "string" then return 0 end
    
    -- Clean text
    local cleanText = text:gsub(",", ""):gsub(" ", ""):gsub("%$", "")
    
    -- MUST contain income pattern
    if not cleanText:find("/s") then return 0 end
    
    -- Extract number and suffix
    local patterns = {
        "([%d%.]+)([KMkmB]?)/s",      -- 90/s, 1.5K/s, 2.3M/s
        "([%d%.]+)/s"                  -- 90/s
    }
    
    for _, pattern in ipairs(patterns) do
        local number, suffix = cleanText:match(pattern)
        if number then
            local value = tonumber(number)
            if value and value > 1 then  -- Skip $1/s (template)
                suffix = (suffix or ""):upper()
                if suffix == "K" then
                    value = value * 1000
                elseif suffix == "M" then
                    value = value * 1000000
                elseif suffix == "B" then
                    value = value * 1000000000
                end
                return math.floor(value), text
            end
        end
    end
    
    return 0
end

-- GET BRAINROT DETAILS FROM STRUCTURE
local function getBrainrotDetails(generationLabel)
    if not generationLabel or not generationLabel:IsA("TextLabel") then
        return "Unknown", "Unknown", "Unknown", "Unknown"
    end
    
    local surfaceGui = generationLabel.Parent
    local animalOverhead = surfaceGui and surfaceGui.Parent
    local part = animalOverhead and animalOverhead.Parent
    local model = part and part.Parent
    
    -- Get brainrot name from DisplayName label
    local brainrotName = "Unknown"
    local plotName = "Unknown"
    local mutation = "Unknown"
    local rarity = "Unknown"
    
    if surfaceGui then
        -- Look for all labels in SurfaceGui
        for _, child in pairs(surfaceGui:GetChildren()) do
            if child:IsA("TextLabel") then
                if child.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.DISPLAY_NAME_LABEL then
                    brainrotName = child.Text or "Unknown"
                elseif child.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.MUTATION_LABEL then
                    mutation = child.Text or "Unknown"
                elseif child.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.RARITY_LABEL then
                    rarity = child.Text or "Unknown"
                elseif child.Name:find("Plot") or child.Name:find("Name") then
                    plotName = child.Text or "Unknown"
                end
            end
        end
    end
    
    -- If plot name not found, use model name
    if plotName == "Unknown" and model and model:IsA("Model") then
        plotName = model.Name
    end
    
    return brainrotName, plotName, mutation, rarity
end

-- FIND REAL BRAINROTS (SKIPS TEMPLATES IN DEBRIS FOLDER) - FIXED VERSION
local function findBrainrotsInWorkspace()
    if DEFAULT_CONFIG.DEBUG_MODE then
        logToConsole("🔍 Searching for REAL brainrots (not templates)...", Color3.fromRGB(100, 200, 255))
    end
    
    local foundBrainrots = {}
    
    -- Look for ALL Generation TextLabels in SurfaceGuis
    for _, descendant in pairs(Workspace:GetDescendants()) do
        if not isRunning then break end
        
        if descendant:IsA("TextLabel") and descendant.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.GENERATION_LABEL then
            -- Get the parent structure
            local surfaceGui = descendant.Parent
            if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
                continue -- Skip if not in SurfaceGui
            end
            
            local animalOverhead = surfaceGui.Parent
            local part = animalOverhead and animalOverhead.Parent
            local parent = part and part.Parent
            
            -- Skip if in Debris folder (templates)
            if parent and parent:IsA("Folder") and parent.Name == "Debris" then
                -- This is the $1/s template, skip it
                continue -- Use continue instead of goto
            end
            
            -- Check the income value
            local income, originalText = parseBrainrotIncome(descendant.Text)
            
            if income >= DEFAULT_CONFIG.MIN_INCOME then
                -- Get brainrot details
                local brainrotName, plotName, mutation, rarity = getBrainrotDetails(descendant)
                
                -- Get owner if available
                local owner = "Unknown"
                local model = parent
                while model and model ~= Workspace do
                    if model:IsA("Model") then
                        for _, child in pairs(model:GetChildren()) do
                            if child:IsA("StringValue") and (child.Name == "Owner" or child.Name:find("Player")) then
                                owner = child.Value or "Unknown"
                                break
                            end
                        end
                        break
                    end
                    model = model.Parent
                end
                
                -- Look for price and stolen status
                local price = "Unknown"
                local stolen = "No"
                if surfaceGui then
                    for _, child in pairs(surfaceGui:GetChildren()) do
                        if child:IsA("TextLabel") then
                            if child.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.PRICE_LABEL then
                                price = child.Text or "Unknown"
                            elseif child.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.STOLEN_LABEL then
                                stolen = child.Text or "No"
                            end
                        end
                    end
                end
                
                if DEFAULT_CONFIG.DEBUG_MODE then
                    logToConsole("  ✅ FOUND: " .. brainrotName .. " at " .. plotName, Color3.fromRGB(180, 220, 180))
                    logToConsole("     Income: " .. originalText .. " ($" .. income .. "/s)", Color3.fromRGB(180, 220, 180))
                end
                
                table.insert(foundBrainrots, {
                    name = brainrotName,
                    plotName = plotName,
                    income = income,
                    incomeText = originalText,
                    mutation = mutation,
                    rarity = rarity,
                    price = price,
                    stolen = stolen,
                    owner = owner,
                    model = model,
                    surfaceGui = surfaceGui,
                    animalOverhead = animalOverhead,
                    generationLabel = descendant,
                    
                    -- For compatibility with existing code
                    billboard = surfaceGui,  -- Alias for surfaceGui
                    displayNameLabel = surfaceGui and surfaceGui:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.DISPLAY_NAME_LABEL),
                    mutationLabel = surfaceGui and surfaceGui:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.MUTATION_LABEL),
                    rarityLabel = surfaceGui and surfaceGui:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.RARITY_LABEL),
                    priceLabel = surfaceGui and surfaceGui:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.PRICE_LABEL),
                    stolenLabel = surfaceGui and surfaceGui:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.STOLEN_LABEL)
                })
            end
        end
    end
    
    -- Alternative search: Look for AnimalOverhead SurfaceGuis directly
    if #foundBrainrots == 0 then
        if DEFAULT_CONFIG.DEBUG_MODE then
            logToConsole("🔍 Alternative search: Looking for AnimalOverhead SurfaceGuis...", Color3.fromRGB(100, 200, 255))
        end
        
        for _, descendant in pairs(Workspace:GetDescendants()) do
            if not isRunning then break end
            
            if descendant:IsA("SurfaceGui") and descendant.Name == DEFAULT_CONFIG.BRAINROT_STRUCTURE.SURFACE_GUI_NAME then
                -- Skip Debris folder
                local part = descendant.Parent
                local parent = part and part.Parent
                
                if parent and parent:IsA("Folder") and parent.Name == "Debris" then
                    continue -- Use continue instead of goto
                end
                
                -- Check for Generation label
                local generationLabel = descendant:FindFirstChild(DEFAULT_CONFIG.BRAINROT_STRUCTURE.GENERATION_LABEL)
                if generationLabel and generationLabel:IsA("TextLabel") then
                    local income, originalText = parseBrainrotIncome(generationLabel.Text)
                    
                    if income >= DEFAULT_CONFIG.MIN_INCOME then
                        local brainrotName, plotName, mutation, rarity = getBrainrotDetails(generationLabel)
                        
                        if DEFAULT_CONFIG.DEBUG_MODE then
                            logToConsole("  ✅ FOUND via SurfaceGui: " .. brainrotName .. " at " .. plotName, Color3.fromRGB(180, 220, 180))
                        end
                        
                        table.insert(foundBrainrots, {
                            name = brainrotName,
                            plotName = plotName,
                            income = income,
                            incomeText = originalText,
                            mutation = mutation,
                            rarity = rarity,
                            surfaceGui = descendant,
                            generationLabel = generationLabel
                        })
                    end
                end
            end
        end
    end
    
    if DEFAULT_CONFIG.DEBUG_MODE then
        logToConsole("📊 Found " .. #foundBrainrots .. " real brainrots (excluding templates)", Color3.fromRGB(200, 200, 255))
    end
    return foundBrainrots
end

-- ============ GUI FUNCTIONS ============
local function updateStatus(status, color)
    currentStatus = status
    if StatusText then
        StatusText.Text = "Status: " .. status
        StatusText.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    end
    if DEFAULT_CONFIG.LOG_TO_CONSOLE then
        logToConsole("[STATUS] " .. status)
    end
end

local function updateStat(stat, value, color)
    if not Stat1Value or not Stat2Value or not Stat3Value or not Stat4Value then
        return
    end
    
    if stat == "attempts" then
        Stat1Value.Text = tostring(value)
    elseif stat == "found" then
        Stat2Value.Text = tostring(value)
        Stat2Value.TextColor3 = color or Color3.fromRGB(0, 255, 127)
    elseif stat == "players" then
        Stat3Value.Text = tostring(value)
    elseif stat == "serverid" then
        if value and value ~= "" then
            Stat4Value.Text = tostring(value):sub(1, 8) .. "..."
        else
            Stat4Value.Text = "N/A"
        end
    end
end

-- ============ WEBHOOK MANAGEMENT ============
local function updateWebhookURL()
    if WebhookInput then
        local newURL = WebhookInput.Text
        if newURL and newURL ~= "" then
            DEFAULT_CONFIG.WEBHOOK_URL = newURL
            saveConfig()
            logToConsole("✓ Webhook URL updated", Color3.fromRGB(0, 255, 0))
            return true
        else
            logToConsole("⚠ Webhook URL cannot be empty", Color3.fromRGB(255, 150, 0))
            return false
        end
    end
    return false
end

-- ============ 1M+ WEBHOOK FUNCTION ============
local function send1MPlusWebhook(brainrotInfo, serverId)
    if not DEFAULT_CONFIG.ENABLE_WEBHOOK or not DEFAULT_CONFIG.NOTIFY_1M_PLUS then
        return false
    end
    
    -- Check if webhook URL is set
    if not DEFAULT_CONFIG.WEBHOOK_URL or DEFAULT_CONFIG.WEBHOOK_URL == "" then
        logToConsole("⚠ Webhook URL not set! Use the input field in GUI", Color3.fromRGB(255, 150, 0))
        return false
    end
    
    -- Only send for 1M+ brainrots
    if brainrotInfo.income < DEFAULT_CONFIG.MILLION_THRESHOLD then
        return false
    end
    
    local currentTime = tick()
    if currentTime - last1MWebhookTime < DEFAULT_CONFIG.WEBHOOK_COOLDOWN then
        return false
    end
    
    last1MWebhookTime = currentTime
    millionPlusCount = millionPlusCount + 1
    
    -- Format income
    local incomeFormatted
    local incomeValue = brainrotInfo.income
    if incomeValue >= 1000000000 then
        incomeFormatted = string.format("%.2fB", incomeValue / 1000000000)
    else
        incomeFormatted = string.format("%.2fM", incomeValue / 1000000)
    end
    
    -- Use brainrot name if available, otherwise use plot name
    local displayName = brainrotInfo.name ~= "Unknown" and brainrotInfo.name or brainrotInfo.plotName
    
    local content = string.format(
        "🚨 **💎 1M+ BRAINROT FOUND! 💎**\n\n" ..
        "**🧠 Name:** %s\n" ..
        "**📍 Plot:** %s\n" ..
        "**💰 Income:** $%s/s ($%s)\n" ..
        "**✨ Mutation:** %s\n" ..
        "**🌟 Rarity:** %s\n" ..
        "**🏷️ Price:** %s\n" ..
        "**👤 Owner:** %s\n" ..
        "**🆔 Job ID:** %s\n" ..
        "**📅 Found:** %s\n\n" ..
        "**Total 1M+ Found:** %d",
        displayName,
        brainrotInfo.plotName,
        incomeFormatted,
        tostring(incomeValue),
        brainrotInfo.mutation,
        brainrotInfo.rarity,
        brainrotInfo.price,
        brainrotInfo.owner,
        serverId or "Unknown",
        os.date("%H:%M:%S %Y-%m-%d"),
        millionPlusCount
    )
    
    local webhookData = {
        content = content,
        username = "🧠 Lore's Hub (LOGS)",
        avatar_url = "https://cdn.discordapp.com/attachments/1102432517862989935/1229650128142401556/brainrot.png"
    }
    
    local success, result = pcall(function()
        local jsonData = HttpService:JSONEncode(webhookData)
        
        local httpRequest
        if syn and syn.request then
            httpRequest = syn.request
        elseif request then
            httpRequest = request
        elseif http_request then
            httpRequest = http_request
        else
            return false
        end
        
        if not httpRequest then
            return false
        end
        
        local response = httpRequest({
            Url = DEFAULT_CONFIG.WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonData,
            Timeout = 10
        })
        
        return response and (response.Success or response.StatusCode == 200 or response.StatusCode == 204)
    end)
    
    if success and result then
        logToConsole("✅ 1M+ Webhook sent! (" .. incomeFormatted .. "/s)", Color3.fromRGB(0, 255, 255))
        return true
    else
        logToConsole("❌ 1M+ Webhook failed: " .. tostring(result), Color3.fromRGB(255, 100, 100))
        return false
    end
end

-- ============ REGULAR WEBHOOK FUNCTION ============
local function sendBrainrotWebhook(brainrotInfo, serverId)
    if not DEFAULT_CONFIG.ENABLE_WEBHOOK then
        return false
    end
    
    -- Check if webhook URL is set
    if not DEFAULT_CONFIG.WEBHOOK_URL or DEFAULT_CONFIG.WEBHOOK_URL == "" then
        return false
    end
    
    local currentTime = tick()
    if currentTime - lastWebhookTime < DEFAULT_CONFIG.WEBHOOK_COOLDOWN then
        return false
    end
    
    lastWebhookTime = currentTime
    
    -- Send 1M+ webhook separately
    if brainrotInfo.income >= DEFAULT_CONFIG.MILLION_THRESHOLD then
        return send1MPlusWebhook(brainrotInfo, serverId)
    end
    
    -- Regular webhook for non-1M brainrots
    local incomeDisplay
    if brainrotInfo.income >= 1000000 then
        incomeDisplay = string.format("%.2fM", brainrotInfo.income / 1000000)
    elseif brainrotInfo.income >= 1000 then
        incomeDisplay = string.format("%.2fK", brainrotInfo.income / 1000)
    else
        incomeDisplay = tostring(brainrotInfo.income)
    end
    
    local displayName = brainrotInfo.name ~= "Unknown" and brainrotInfo.name or brainrotInfo.plotName
    
    local content = string.format(
        "🧠 **BRAINROT FOUND!**\n" ..
        "**Name:** %s\n" ..
        "**Plot:** %s\n" ..
        "**Income:** $%s/s\n" ..
        "**Mutation:** %s\n" ..
        "**Rarity:** %s\n" ..
        "**Owner:** %s\n" ..
        "**Time:** %s",
        displayName,
        brainrotInfo.plotName,
        incomeDisplay,
        brainrotInfo.mutation,
        brainrotInfo.rarity,
        brainrotInfo.owner,
        os.date("%H:%M:%S")
    )
    
    local webhookData = {
        content = content,
        username = "Lore's Hub",
        avatar_url = "https://cdn.discordapp.com/attachments/1102432517862989935/1229650128142401556/brainrot.png"
    }
    
    local success, result = pcall(function()
        local jsonData = HttpService:JSONEncode(webhookData)
        
        local httpRequest
        if syn and syn.request then
            httpRequest = syn.request
        elseif request then
            httpRequest = request
        elseif http_request then
            httpRequest = http_request
        else
            return false
        end
        
        if not httpRequest then
            return false
        end
        
        local response = httpRequest({
            Url = DEFAULT_CONFIG.WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonData
        })
        
        return response and (response.Success or response.StatusCode == 200 or response.StatusCode == 204)
    end)
    
    if success and result then
        logToConsole("✅ Webhook sent!", Color3.fromRGB(0, 255, 0))
        return true
    else
        logToConsole("❌ Webhook failed: " .. tostring(result), Color3.fromRGB(255, 100, 100))
        return false
    end
end

-- ============ SEND ALL 1M+ BRAINROTS ============
local function sendAll1MPlusBrainrots(brainrots, serverId)
    if not DEFAULT_CONFIG.ENABLE_WEBHOOK or not DEFAULT_CONFIG.NOTIFY_1M_PLUS then
        return
    end
    
    if not brainrots or #brainrots == 0 then
        return
    end
    
    -- Sort by income (highest first)
    table.sort(brainrots, function(a, b) return a.income > b.income end)
    
    local sentCount = 0
    for _, brainrot in ipairs(brainrots) do
        if brainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD then
            -- Send webhook for each 1M+ brainrot
            local success = send1MPlusWebhook(brainrot, serverId)
            if success then
                sentCount = sentCount + 1
                -- Small delay between webhooks to avoid rate limiting
                task.wait(0.5)
            end
        end
    end
    
    if sentCount > 0 then
        logToConsole("✅ Sent " .. sentCount .. " 1M+ brainrots to Discord", Color3.fromRGB(0, 255, 255))
    end
end

-- ============ TEST WEBHOOK FUNCTION ============
local function testWebhook()
    logToConsole("Testing webhook...", Color3.fromRGB(255, 200, 0))
    
    if not DEFAULT_CONFIG.WEBHOOK_URL or DEFAULT_CONFIG.WEBHOOK_URL == "" then
        logToConsole("❌ Webhook URL not set! Use the input field", Color3.fromRGB(255, 100, 100))
        return false
    end
    
    local testData = {
        name = "TEST BRAINROT",
        plotName = "Test Plot",
        income = 1500000,
        incomeText = "1.5M/s",
        mutation = "Gold",
        rarity = "Legendary",
        price = "$1,500,000",
        stolen = "No",
        owner = "TestPlayer"
    }
    
    local success = send1MPlusWebhook(testData, "TEST1234")
    if success then
        logToConsole("✅ Test webhook sent!", Color3.fromRGB(0, 255, 0))
    else
        logToConsole("❌ Test webhook failed", Color3.fromRGB(255, 100, 100))
    end
    return success
end

-- ============ BRAINROT TRACKER SYSTEM ============
local function updateBrainrotTracker()
    if not brainrotTrackerContainer then return end
    
    for _, child in ipairs(brainrotTrackerContainer:GetChildren()) do
        if child:IsA("Frame") and child.Name:find("BrainrotEntry_") then
            child:Destroy()
        end
    end
    
    if #savedBrainrots == 0 then
        local noDataLabel = Instance.new("TextLabel")
        noDataLabel.Size = UDim2.new(1, 0, 0, 50)
        noDataLabel.Position = UDim2.new(0, 0, 0, 0)
        noDataLabel.BackgroundTransparency = 1
        noDataLabel.Text = "No brainrots saved yet\nFind some to see them here!"
        noDataLabel.TextColor3 = Color3.fromRGB(150, 150, 180)
        noDataLabel.TextSize = 12
        noDataLabel.Font = Enum.Font.Gotham
        noDataLabel.TextWrapped = true
        noDataLabel.Parent = brainrotTrackerContainer
        return
    end
    
    local yPosition = 0
    for i = #savedBrainrots, 1, -1 do
        local brainrotData = savedBrainrots[i]
        
        local entryFrame = Instance.new("Frame")
        entryFrame.Name = "BrainrotEntry_" .. i
        entryFrame.Size = UDim2.new(1, 0, 0, 90)
        entryFrame.BackgroundColor3 = brainrotData.isMillionPlus and Color3.fromRGB(40, 10, 20) or 
                                     (brainrotData.isUltra and Color3.fromRGB(40, 20, 20) or Color3.fromRGB(30, 30, 40))
        entryFrame.BorderSizePixel = 0
        entryFrame.Position = UDim2.new(0, 0, 0, yPosition)
        entryFrame.Parent = brainrotTrackerContainer
        
        local entryCorner = Instance.new("UICorner")
        entryCorner.CornerRadius = UDim.new(0, 6)
        entryCorner.Parent = entryFrame
        
        local displayName = brainrotData.brainrotName ~= "Unknown" and brainrotData.brainrotName or brainrotData.plotName
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.6, -5, 0, 18)
        nameLabel.Position = UDim2.new(0, 5, 0, 5)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = brainrotData.isMillionPlus and "💎 " .. displayName or 
                         (brainrotData.isUltra and "⚡ " .. displayName or "🧠 " .. displayName)
        nameLabel.TextColor3 = brainrotData.isMillionPlus and Color3.fromRGB(255, 50, 150) or 
                              (brainrotData.isUltra and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(200, 200, 255))
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = entryFrame
        
        local incomeLabel = Instance.new("TextLabel")
        incomeLabel.Size = UDim2.new(0.6, -5, 0, 18)
        incomeLabel.Position = UDim2.new(0, 5, 0, 25)
        incomeLabel.BackgroundTransparency = 1
        incomeLabel.Text = brainrotData.incomeFormatted .. "/s"
        incomeLabel.TextColor3 = brainrotData.isMillionPlus and Color3.fromRGB(255, 100, 200) or 
                                (brainrotData.isUltra and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(100, 255, 100))
        incomeLabel.TextSize = 14
        incomeLabel.Font = Enum.Font.GothamBold
        incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
        incomeLabel.Parent = entryFrame
        
        local mutationLabel = Instance.new("TextLabel")
        mutationLabel.Size = UDim2.new(0.6, -5, 0, 16)
        mutationLabel.Position = UDim2.new(0, 5, 0, 45)
        mutationLabel.BackgroundTransparency = 1
        mutationLabel.Text = "✨ " .. brainrotData.mutation
        mutationLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        mutationLabel.TextSize = 11
        mutationLabel.Font = Enum.Font.Gotham
        mutationLabel.TextXAlignment = Enum.TextXAlignment.Left
        mutationLabel.TextTruncate = Enum.TextTruncate.AtEnd
        mutationLabel.Parent = entryFrame
        
        local ownerLabel = Instance.new("TextLabel")
        ownerLabel.Size = UDim2.new(0.6, -5, 0, 16)
        ownerLabel.Position = UDim2.new(0, 5, 0, 65)
        ownerLabel.BackgroundTransparency = 1
        ownerLabel.Text = "👤 " .. brainrotData.owner
        ownerLabel.TextColor3 = Color3.fromRGB(180, 180, 220)
        ownerLabel.TextSize = 11
        ownerLabel.Font = Enum.Font.Gotham
        ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
        ownerLabel.TextTruncate = Enum.TextTruncate.AtEnd
        ownerLabel.Parent = entryFrame
        
        local timeLabel = Instance.new("TextLabel")
        timeLabel.Size = UDim2.new(0.4, -5, 0, 15)
        timeLabel.Position = UDim2.new(0.6, 5, 0, 5)
        timeLabel.BackgroundTransparency = 1
        timeLabel.Text = brainrotData.timeFound
        timeLabel.TextColor3 = Color3.fromRGB(150, 150, 180)
        timeLabel.TextSize = 10
        timeLabel.Font = Enum.Font.Gotham
        timeLabel.TextXAlignment = Enum.TextXAlignment.Right
        timeLabel.Parent = entryFrame
        
        local rarityLabel = Instance.new("TextLabel")
        rarityLabel.Size = UDim2.new(0.4, -5, 0, 15)
        rarityLabel.Position = UDim2.new(0.6, 5, 0, 25)
        rarityLabel.BackgroundTransparency = 1
        rarityLabel.Text = brainrotData.rarity
        rarityLabel.TextColor3 = Color3.fromRGB(200, 150, 255)
        rarityLabel.TextSize = 10
        rarityLabel.Font = Enum.Font.Gotham
        rarityLabel.TextXAlignment = Enum.TextXAlignment.Right
        rarityLabel.Parent = entryFrame
        
        local joinButton = Instance.new("TextButton")
        joinButton.Name = "JoinButton"
        joinButton.Size = UDim2.new(0.4, -10, 0, 30)
        joinButton.Position = UDim2.new(0.6, 5, 0, 55)
        joinButton.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
        joinButton.Text = brainrotData.isMillionPlus and "💎 JOIN" or "JOIN"
        joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        joinButton.TextSize = 12
        joinButton.Font = Enum.Font.GothamBold
        joinButton.Parent = entryFrame
        
        local joinCorner = Instance.new("UICorner")
        joinCorner.CornerRadius = UDim.new(0, 4)
        joinCorner.Parent = joinButton
        
        joinButton.MouseButton1Click:Connect(function()
            local success, errorMsg = pcall(function()
                TeleportService:TeleportToPlaceInstance(DEFAULT_CONFIG.PLACE_ID, brainrotData.serverId, LocalPlayer)
            end)
            
            if success then
                logToConsole("✓ Joining brainrot server...", Color3.fromRGB(0, 255, 0))
            else
                logToConsole("✗ Join failed: " .. tostring(errorMsg), Color3.fromRGB(255, 100, 100))
            end
        end)
        
        yPosition = yPosition + 95
    end
    
    brainrotTrackerContainer.CanvasSize = UDim2.new(0, 0, 0, yPosition)
end

local function saveBrainrot(brainrotInfo, serverId)
    if #savedBrainrots >= DEFAULT_CONFIG.MAX_SAVED_BRAINROTS then
        table.remove(savedBrainrots, 1)
    end
    
    -- Format income display
    local incomeFormatted
    local incomeValue = brainrotInfo.income
    if incomeValue >= 1000000 then
        incomeFormatted = string.format("$%.2fM", incomeValue / 1000000)
    elseif incomeValue >= 1000 then
        incomeFormatted = string.format("$%.2fK", incomeValue / 1000)
    else
        incomeFormatted = string.format("$%.0f", incomeValue)
    end
    
    local brainrotData = {
        brainrotName = brainrotInfo.name,
        plotName = brainrotInfo.plotName,
        income = incomeValue,
        incomeFormatted = incomeFormatted,
        mutation = brainrotInfo.mutation,
        rarity = brainrotInfo.rarity,
        price = brainrotInfo.price,
        stolen = brainrotInfo.stolen,
        owner = brainrotInfo.owner,
        serverId = serverId,
        timeFound = os.date("%H:%M:%S"),
        dateFound = os.date("%Y-%m-%d"),
        isUltra = incomeValue >= DEFAULT_CONFIG.ULTRA_THRESHOLD,
        isMillionPlus = incomeValue >= DEFAULT_CONFIG.MILLION_THRESHOLD
    }
    
    table.insert(savedBrainrots, brainrotData)
    
    local displayName = brainrotInfo.name ~= "Unknown" and brainrotInfo.name or brainrotInfo.plotName
    logToConsole("💾 Saved: " .. displayName .. " (" .. incomeFormatted .. "/s)", 
                brainrotData.isMillionPlus and Color3.fromRGB(255, 50, 150) or 
                (brainrotData.isUltra and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(0, 200, 255)))
    
    -- Send 1M+ webhook immediately
    if brainrotData.isMillionPlus and DEFAULT_CONFIG.ENABLE_WEBHOOK and DEFAULT_CONFIG.NOTIFY_1M_PLUS then
        task.spawn(function()
            send1MPlusWebhook(brainrotInfo, serverId)
        end)
    end
    
    if brainrotTrackerContainer then
        task.spawn(function()
            updateBrainrotTracker()
        end)
    end
    
    return brainrotData
end

-- ============ DEBUG SCAN ============
local function debugScanWorkspace()
    logToConsole("🧪 DEBUG SCAN - Looking for REAL brainrots", Color3.fromRGB(255, 200, 0))
    
    local brainrots = findBrainrotsInWorkspace()
    
    logToConsole("Found " .. #brainrots .. " brainrot structures", Color3.fromRGB(200, 200, 255))
    
    -- Sort by income (highest first)
    table.sort(brainrots, function(a, b) return a.income > b.income end)
    
    -- Track all 1M+ brainrots found
    local millionPlusFound = {}
    
    -- Show found brainrots
    for i = 1, math.min(20, #brainrots) do
        local brainrot = brainrots[i]
        
        local color = brainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD and Color3.fromRGB(255, 50, 150) or
                     brainrot.income >= DEFAULT_CONFIG.HIGH_THRESHOLD and Color3.fromRGB(255, 50, 50) or 
                     brainrot.income > 0 and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(200, 200, 200)
        
        logToConsole("  " .. i .. ". " .. brainrot.name .. " at " .. brainrot.plotName, color)
        logToConsole("     Generation: " .. brainrot.incomeText .. " (Value: $" .. brainrot.income .. "/s)", 
                   brainrot.income > 0 and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(150, 150, 150))
        logToConsole("     Mutation: " .. brainrot.mutation, Color3.fromRGB(255, 215, 0))
        logToConsole("     Rarity: " .. brainrot.rarity, Color3.fromRGB(200, 150, 255))
        logToConsole("     Price: " .. brainrot.price, Color3.fromRGB(100, 255, 100))
        logToConsole("     Stolen: " .. brainrot.stolen, Color3.fromRGB(255, 100, 100))
        logToConsole("     Owner: " .. brainrot.owner, Color3.fromRGB(150, 200, 255))
        
        if brainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD then
            logToConsole("     💎 1M+ BRAINROT DETECTED! 💎", Color3.fromRGB(255, 0, 255))
            table.insert(millionPlusFound, brainrot)
        elseif brainrot.income >= DEFAULT_CONFIG.ULTRA_THRESHOLD then
            logToConsole("     ⚡ ULTRA BRAINROT DETECTED! ⚡", Color3.fromRGB(255, 0, 0))
        elseif brainrot.income >= DEFAULT_CONFIG.HIGH_THRESHOLD then
            logToConsole("     🧠 HIGH VALUE BRAINROT! 🧠", Color3.fromRGB(255, 100, 100))
        end
    end
    
    if #millionPlusFound > 0 then
        logToConsole("💎 Found " .. #millionPlusFound .. " 1M+ brainrots!", Color3.fromRGB(255, 50, 150))
        
        -- Ask if user wants to send webhooks for all 1M+ brainrots
        logToConsole("💡 Use 'Send All 1M+' button to send these to Discord", Color3.fromRGB(200, 150, 255))
    end
    
    if #brainrots == 0 then
        logToConsole("❌ No brainrots found with current settings", Color3.fromRGB(255, 150, 0))
        logToConsole("💡 Try lowering MIN_INCOME in config (current: $" .. DEFAULT_CONFIG.MIN_INCOME .. "/s)", Color3.fromRGB(255, 200, 0))
    end
    
    logToConsole("🧪 DEBUG SCAN COMPLETE", Color3.fromRGB(255, 200, 0))
    return brainrots, millionPlusFound
end

-- ============ SCAN FOR BRAINROT FUNCTION ============
local function scanForBrainrot()
    if sentThisServer or not isRunning then 
        return false 
    end
    
    logToConsole("🔍 Scanning for REAL brainrots...", Color3.fromRGB(100, 200, 255))
    
    local brainrots = findBrainrotsInWorkspace()
    lastFoundBrainrots = brainrots -- Store all found brainrots
    
    if #brainrots > 0 then
        -- Sort by income (highest first)
        table.sort(brainrots, function(a, b) return a.income > b.income end)
        
        local bestBrainrot = brainrots[1]
        
        if bestBrainrot.income >= DEFAULT_CONFIG.MIN_INCOME then
            consecutiveNoBrainrot = 0
        else
            consecutiveNoBrainrot = consecutiveNoBrainrot + 1
        end
        
        logToConsole("📊 Scan: " .. #brainrots .. " brainrot structures found, best: $" .. bestBrainrot.income .. "/s", 
                   Color3.fromRGB(200, 200, 255))
        
        -- Check for 1M+ brainrots and send webhooks for ALL of them
        local millionPlusFound = {}
        for _, brainrot in ipairs(brainrots) do
            if brainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD then
                table.insert(millionPlusFound, brainrot)
            end
        end
        
        if #millionPlusFound > 0 then
            logToConsole("💎 Found " .. #millionPlusFound .. " 1M+ brainrots!", Color3.fromRGB(255, 50, 150))
            
            -- Send webhooks for all 1M+ brainrots
            if DEFAULT_CONFIG.ENABLE_WEBHOOK and DEFAULT_CONFIG.NOTIFY_1M_PLUS then
                task.spawn(function()
                    sendAll1MPlusBrainrots(millionPlusFound, game.JobId)
                end)
            end
        end
        
        if bestBrainrot.income >= DEFAULT_CONFIG.HIGH_THRESHOLD then
            foundCount = foundCount + 1
            
            if Stat2Value then
                Stat2Value.Text = tostring(foundCount)
                Stat2Value.TextColor3 = bestBrainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD and Color3.fromRGB(255, 50, 150) or
                                      (bestBrainrot.income >= DEFAULT_CONFIG.ULTRA_THRESHOLD and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 255, 127))
            end
            
            lastScanTime = tick()
            
            local brainrotType = bestBrainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD and "💎 1M+" or
                               (bestBrainrot.income >= DEFAULT_CONFIG.ULTRA_THRESHOLD and "⚡ ULTRA" or "🧠 HIGH")
            local displayName = bestBrainrot.name ~= "Unknown" and bestBrainrot.name or bestBrainrot.plotName
            local logMessage = brainrotType .. " brainrot: " .. displayName .. " (" .. bestBrainrot.incomeText .. ")"
            
            logToConsole(logMessage, bestBrainrot.income >= DEFAULT_CONFIG.MILLION_THRESHOLD and Color3.fromRGB(255, 50, 150) or
                       (bestBrainrot.income >= DEFAULT_CONFIG.ULTRA_THRESHOLD and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 255, 0)))
            logToConsole("  Mutation: " .. bestBrainrot.mutation, Color3.fromRGB(255, 215, 0))
            logToConsole("  Rarity: " .. bestBrainrot.rarity, Color3.fromRGB(200, 150, 255))
            logToConsole("  Price: " .. bestBrainrot.price, Color3.fromRGB(100, 255, 100))
            logToConsole("  Stolen: " .. bestBrainrot.stolen, Color3.fromRGB(255, 100, 100))
            logToConsole("  Owner: " .. bestBrainrot.owner, Color3.fromRGB(150, 200, 255))
            
            saveBrainrot(bestBrainrot, game.JobId)
            
            if DEFAULT_CONFIG.ENABLE_WEBHOOK and DEFAULT_CONFIG.NOTIFY_ON_FIND then
                task.spawn(function()
                    local success = sendBrainrotWebhook(bestBrainrot, game.JobId)
                    if not success then
                        logToConsole("⚠ Webhook failed to send", Color3.fromRGB(255, 150, 0))
                    end
                end)
            end
            
            return true
        else
            if bestBrainrot.income > 0 then
                logToConsole("❌ Brainrot income below HIGH threshold: $" .. bestBrainrot.income .. "/s (needs $" .. 
                           DEFAULT_CONFIG.HIGH_THRESHOLD .. ")", Color3.fromRGB(255, 150, 0))
            else
                logToConsole("❌ No valid brainrot structures found", Color3.fromRGB(255, 150, 0))
            end
        end
    else
        logToConsole("❌ No brainrot structures found", Color3.fromRGB(255, 150, 0))
        consecutiveNoBrainrot = consecutiveNoBrainrot + 1
    end
    
    if consecutiveNoBrainrot >= DEFAULT_CONFIG.FORCE_HOP_AFTER then
        logToConsole("⚠ Too many failed scans (" .. consecutiveNoBrainrot .. "), forcing server hop", 
                   Color3.fromRGB(255, 100, 100))
        return "force_hop"
    end
    
    return false
end

-- ============ BACKEND API FUNCTIONS ============
local function fetchServersFromBackend()
    if not DEFAULT_CONFIG.USE_BACKEND_API or not DEFAULT_CONFIG.BACKEND_API_URL then
        logToConsole("⚠ Backend API disabled", Color3.fromRGB(255, 150, 0))
        return nil
    end
    
    local apiUrl = DEFAULT_CONFIG.BACKEND_API_URL .. "/servers"
    local requestData = {
        placeId = DEFAULT_CONFIG.PLACE_ID,
        minPlayers = DEFAULT_CONFIG.MIN_PLAYERS,
        maxPlayers = DEFAULT_CONFIG.MAX_PLAYERS,
        exclude = visitedServers,
        useProxies = DEFAULT_CONFIG.USE_PROXIES
    }
    
    for attempt = 1, DEFAULT_CONFIG.MAX_PROXY_RETRIES do
        local success, response = pcall(function()
            local httpRequest
            if syn and syn.request then
                httpRequest = syn.request
            elseif request then
                httpRequest = request
            elseif http_request then
                httpRequest = http_request
            else
                return nil
            end
            
            if not httpRequest then
                return nil
            end
            
            local req = httpRequest({
                Url = apiUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"] = "BrainrotFinder/8.1"
                },
                Body = HttpService:JSONEncode(requestData),
                Timeout = DEFAULT_CONFIG.API_TIMEOUT
            })
            
            if req and req.Success and req.Body then
                local data = HttpService:JSONDecode(req.Body)
                if data and data.success and data.servers then
                    return data.servers
                end
            end
            return nil
        end)
        
        if success and response then
            logToConsole("✓ Backend API: Fetched " .. #response .. " fresh servers", Color3.fromRGB(0, 200, 255))
            return response
        elseif attempt < DEFAULT_CONFIG.MAX_PROXY_RETRIES then
            logToConsole("⚠ Backend API attempt " .. attempt .. " failed, retrying...", Color3.fromRGB(255, 150, 0))
            task.wait(1)
        end
    end
    
    logToConsole("✗ Backend API: All attempts failed", Color3.fromRGB(255, 100, 100))
    return nil
end

-- ============ IMPROVED SERVER LIST FUNCTION ============
local function getServerList()
    local allServers = {}
    
    -- 1. PRIMARY METHOD: Use the Official Roblox API
    if DEFAULT_CONFIG.USE_ROBLOX_API then
        local robloxApiUrl = "https://games.roblox.com/v1/games/" .. DEFAULT_CONFIG.PLACE_ID .. "/servers/Public?sortOrder=Asc&limit=100"
        
        local success, robloxResponse = pcall(function()
            local httpRequest = syn and syn.request or request or http_request
            if not httpRequest then return nil end
            
            local req = httpRequest({
                Url = robloxApiUrl,
                Method = "GET",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Timeout = DEFAULT_CONFIG.API_TIMEOUT
            })
            
            if req and req.Success and req.Body then
                return HttpService:JSONDecode(req.Body)
            end
            return nil
        end)
        
        if success and robloxResponse and robloxResponse.data then
            for _, server in ipairs(robloxResponse.data) do
                if server.id and server.playing and server.maxPlayers then
                    table.insert(allServers, {
                        id = tostring(server.id),
                        playing = server.playing,
                        maxPlayers = server.maxPlayers
                    })
                end
            end
            logToConsole("✓ Roblox API: Fetched " .. #allServers .. " servers", Color3.fromRGB(0, 200, 255))
        else
            logToConsole("⚠ Roblox API failed, trying backend...", Color3.fromRGB(255, 150, 0))
        end
    end
    
    -- 2. FALLBACK: Use the old backend API (keep your existing code)
    if #allServers < 5 and DEFAULT_CONFIG.USE_BACKEND_API then
        local backendServers = fetchServersFromBackend()
        if backendServers and #backendServers > 0 then
            for _, server in ipairs(backendServers) do
                if server.id then
                    table.insert(allServers, {
                        id = tostring(server.id),
                        playing = server.playing or 0,
                        maxPlayers = server.maxPlayers or DEFAULT_CONFIG.MAX_SERVER_SIZE
                    })
                end
            end
            logToConsole("✓ Backend added " .. #backendServers .. " servers", Color3.fromRGB(0, 200, 255))
        end
    end
    
    -- If still no servers, return at least the current one for fallback logic
    if #allServers == 0 then
        logToConsole("⚠ Warning: No servers found from any source.", Color3.fromRGB(255, 150, 0))
        -- Optionally add current server to trigger the random teleport fallback
        table.insert(allServers, {
            id = game.JobId,
            playing = #Players:GetPlayers(),
            maxPlayers = DEFAULT_CONFIG.MAX_SERVER_SIZE
        })
    end
    
    return allServers
end

-- ============ SERVER HOP FUNCTIONS ============
local function isCurrentServerPrivate()
    local playerCount = #Players:GetPlayers()
    if playerCount <= 1 then return true end
    
    local serverId = tostring(game.JobId):lower()
    if serverId:find("^0000") or serverId:find("^ffff") or serverId:find("^aaaa") then
        return true
    end
    
    if visitedServers[serverId] then return true end
    return false
end

local function isServerPrivate(server)
    if not server or not server.id then return true end
    
    local serverId = tostring(server.id)
    local playerCount = server.playing or 0

    if blacklistedServers[serverId] or visitedServers[serverId] or serverId == game.JobId then
        return true
    end

    if playerCount < DEFAULT_CONFIG.MIN_PLAYERS or playerCount > DEFAULT_CONFIG.MAX_PLAYERS then
        return true
    end

    local idLower = serverId:lower()
    if idLower:find("^0000") or idLower:find("^ffff") or idLower:find("^aaaa") then
        blacklistedServers[serverId] = true
        return true
    end

    return false
end

local function tryJoinServer(server, retryCount)
    retryCount = retryCount or 0
    
    if not server or not server.id then 
        logToConsole("Invalid server data", Color3.fromRGB(255, 100, 100))
        return false 
    end
    
    local serverId = tostring(server.id)
    local playerCount = server.playing or 0
    
    local message = "→ Trying: " .. serverId:sub(1, 8) .. " (" .. playerCount .. "/" .. DEFAULT_CONFIG.MAX_SERVER_SIZE .. ")"
    if retryCount > 0 then
        message = message .. " [" .. retryCount .. "]"
    end
    
    logToConsole(message, Color3.fromRGB(200, 200, 255))
    
    local success, errorMsg = pcall(function()
        TeleportService:TeleportToPlaceInstance(DEFAULT_CONFIG.PLACE_ID, serverId, LocalPlayer)
    end)
    
    if success then
        logToConsole("✓ Teleport started!", Color3.fromRGB(0, 255, 0))
        lastHopTime = tick()
        visitedServers[serverId] = true
        updateStatus("Joining...", Color3.fromRGB(0, 255, 0))
        return true
    else
        errorMsg = tostring(errorMsg)
        
        if errorMsg:find("full") or errorMsg:find("GameFull") then
            if retryCount < DEFAULT_CONFIG.MAX_SERVER_RETRIES then
                logToConsole("⚠ Server full, retrying in 0.5s...", Color3.fromRGB(255, 150, 0))
                safeWait(0.5)
                return tryJoinServer(server, retryCount + 1)
            else
                logToConsole("✗ Server full after " .. DEFAULT_CONFIG.MAX_SERVER_RETRIES .. " attempts", Color3.fromRGB(255, 100, 100))
                visitedServers[serverId] = true
                return false
            end
        elseif errorMsg:find("private") or errorMsg:find("Unauthorized") then
            logToConsole("✗ Private server", Color3.fromRGB(255, 100, 100))
            blacklistedServers[serverId] = true
            visitedServers[serverId] = true
            return false
        elseif errorMsg:find("not found") or errorMsg:find("404") then
            logToConsole("✗ Server not found", Color3.fromRGB(255, 100, 100))
            blacklistedServers[serverId] = true
            visitedServers[serverId] = true
            return false
        else
            logToConsole("✗ Teleport failed: " .. errorMsg:sub(1, 80), Color3.fromRGB(255, 100, 100))
            visitedServers[serverId] = true
            return false
        end
    end
end

local function filterServers(servers)
    if not servers then return {} end
    
    local filtered = {}
    for _, server in ipairs(servers) do
        if not isRunning then break end
        
        if server and server.id and server.playing then
            local serverId = tostring(server.id)
            local playerCount = server.playing or 0
            
            if not isServerPrivate(server) and 
               playerCount >= DEFAULT_CONFIG.MIN_PLAYERS and 
               playerCount <= DEFAULT_CONFIG.MAX_PLAYERS and
               not visitedServers[serverId] and
               not blacklistedServers[serverId] and
               serverId ~= game.JobId then
                table.insert(filtered, server)
            end
        end
    end
    
    table.sort(filtered, function(a, b)
        local aPlayers = a.playing or 0
        local bPlayers = b.playing or 0
        
        local aSlots = DEFAULT_CONFIG.MAX_SERVER_SIZE - aPlayers
        local bSlots = DEFAULT_CONFIG.MAX_SERVER_SIZE - bPlayers
        
        if aSlots ~= bSlots then
            return aSlots > bSlots
        end
        
        return aPlayers > bPlayers
    end)
    
    return filtered
end

local function serverHop()
    if sentThisServer or not isRunning then 
        logToConsole("Server hop canceled", Color3.fromRGB(255, 150, 0))
        return 
    end
    
    attemptCount = attemptCount + 1
    visitedServers[tostring(game.JobId)] = true
    
    updateStat("attempts", attemptCount .. "/" .. DEFAULT_CONFIG.MAX_ATTEMPTS)
    updateStatus("Hop #" .. attemptCount, Color3.fromRGB(255, 255, 0))
    
    if attemptCount > DEFAULT_CONFIG.MAX_ATTEMPTS then
        logToConsole("✗ Max attempts reached", Color3.fromRGB(255, 100, 100))
        updateStatus("Max attempts", Color3.fromRGB(255, 100, 100))
        isRunning = false
        return
    end
    
    logToConsole("=== Server Hop Attempt " .. tostring(attemptCount) .. " ===", Color3.fromRGB(255, 255, 100))
    logToConsole("Fetching server list...", Color3.fromRGB(200, 200, 255))
    
    local servers = {}
    local fetchSuccess, fetchError = pcall(getServerList)
    
    if fetchSuccess then
        servers = fetchError or {}
    else
        logToConsole("✗ Server fetch error: " .. tostring(fetchError), Color3.fromRGB(255, 100, 100))
    end
    
    if not servers or #servers == 0 then
        logToConsole("⚠ No servers available", Color3.fromRGB(255, 150, 0))
        
        if attemptCount % 5 == 0 then
            logToConsole("🔄 Trying random teleport...", Color3.fromRGB(255, 200, 0))
            local randomSuccess = pcall(function()
                TeleportService:Teleport(DEFAULT_CONFIG.PLACE_ID, LocalPlayer)
            end)
            
            if randomSuccess then
                logToConsole("✓ Random teleport initiated", Color3.fromRGB(0, 255, 0))
                return
            end
        end
        
        logToConsole("⚠ Retrying in " .. DEFAULT_CONFIG.RETRY_DELAY .. "s...", Color3.fromRGB(255, 150, 0))
        safeWait(DEFAULT_CONFIG.RETRY_DELAY)
        task.spawn(serverHop)
        return
    end
    
    logToConsole("✓ Found " .. #servers .. " servers", Color3.fromRGB(200, 200, 255))
    
    local publicServers = filterServers(servers)
    
    if #publicServers == 0 then
        logToConsole("⚠ No suitable servers found", Color3.fromRGB(255, 150, 0))
        
        if attemptCount >= DEFAULT_CONFIG.FAST_HOP_AFTER then
            logToConsole("⚡ Activating fast hop mode", Color3.fromRGB(255, 200, 0))
            fastHopMode = true
            fastHopCount = 0
            safeWait(DEFAULT_CONFIG.FAST_HOP_INTERVAL)
            task.spawn(serverHop)
        else
            safeWait(DEFAULT_CONFIG.RETRY_DELAY)
            task.spawn(serverHop)
        end
        return
    end
    
    local serversToTry = math.min(DEFAULT_CONFIG.MAX_SERVERS_TO_TRY, #publicServers)
    logToConsole("Trying " .. serversToTry .. " servers...", Color3.fromRGB(200, 200, 255))
    
    for i = 1, serversToTry do
        if not isRunning then break end
        
        local server = publicServers[i]
        updateStatus("Trying server " .. i .. "/" .. serversToTry, Color3.fromRGB(255, 255, 0))
        
        if tryJoinServer(server) then
            logToConsole("✓ Successfully joining server!", Color3.fromRGB(0, 255, 0))
            return
        end
        
        if i < serversToTry then
            safeWait(0.2)
        end
    end
    
    logToConsole("⚠ All " .. serversToTry .. " servers failed", Color3.fromRGB(255, 150, 0))
    
    if fastHopMode and fastHopCount < DEFAULT_CONFIG.MAX_FAST_HOPS then
        fastHopCount = fastHopCount + 1
        logToConsole("⚡ Fast hop " .. fastHopCount .. "/" .. DEFAULT_CONFIG.MAX_FAST_HOPS, Color3.fromRGB(255, 200, 0))
        safeWait(DEFAULT_CONFIG.FAST_HOP_INTERVAL)
        task.spawn(serverHop)
    else
        logToConsole("⚠ Retrying in " .. DEFAULT_CONFIG.RETRY_DELAY .. "s...", Color3.fromRGB(255, 150, 0))
        safeWait(DEFAULT_CONFIG.RETRY_DELAY)
        task.spawn(serverHop)
    end
end

-- ============ MAIN FUNCTION ============
local function main()
    if not isRunning then 
        logToConsole("Script is not running", Color3.fromRGB(255, 100, 100))
        return 
    end
    
    logToConsole("🧠 Lore's Hub v8.1 (FIXED SERVER HOP)", Color3.fromRGB(0, 200, 255))
    logToConsole("🎯 Target: AnimalOverhead SurfaceGui → Generation TextLabel", Color3.fromRGB(200, 200, 200))
    logToConsole("💰 Skips $1/s templates in Debris folder", Color3.fromRGB(200, 200, 200))
    logToConsole("🔍 Looking for REAL brainrots only", Color3.fromRGB(200, 200, 255))
    logToConsole("💎 ALL 1M+ brainrots will be sent to Discord", Color3.fromRGB(255, 50, 150))
    logToConsole("📊 Thresholds: HIGH=$1M, ULTRA=$5M", Color3.fromRGB(200, 200, 255))
    logToConsole("🔄 Server Hop: Fixed with Roblox API + Backend fallback", Color3.fromRGB(0, 200, 255))
    
    updateStatus("Starting...", Color3.fromRGB(100, 200, 255))
    
    local lastActivityTime = tick()
    
    while isRunning do
        if tick() - lastActivityTime > DEFAULT_CONFIG.STUCK_TIMEOUT then
            logToConsole("⚠ Stuck detection triggered", Color3.fromRGB(255, 100, 100))
            logToConsole("🔄 Force restarting...", Color3.fromRGB(255, 200, 0))
            
            updateStatus("Stuck! Restarting...", Color3.fromRGB(255, 200, 0))
            
            lastActivityTime = tick()
            consecutiveNoBrainrot = 0
            task.spawn(serverHop)
            break
        end
        
        if isCurrentServerPrivate() then
            logToConsole("Private server detected", Color3.fromRGB(255, 150, 0))
            logToConsole("Waiting " .. DEFAULT_CONFIG.SERVER_HOP_DELAY .. "s...", Color3.fromRGB(255, 255, 0))
            
            safeWait(DEFAULT_CONFIG.SERVER_HOP_DELAY)
            logToConsole("Starting server hop...", Color3.fromRGB(255, 255, 0))
            
            task.spawn(serverHop)
            break
        else
            logToConsole("Scanning for brainrot structures...", Color3.fromRGB(200, 200, 255))
            updateStatus("Scanning...", Color3.fromRGB(100, 200, 255))
            
            lastActivityTime = tick()
            local scanResult = scanForBrainrot()
            
            if scanResult == true then
                logToConsole("✅ Brainrot found!", Color3.fromRGB(0, 255, 0))
                logToConsole("Waiting " .. DEFAULT_CONFIG.SCAN_WAIT_TIME .. "s...", Color3.fromRGB(200, 200, 200))
                
                updateStatus("Found! Waiting...", Color3.fromRGB(0, 255, 0))
                safeWait(DEFAULT_CONFIG.SCAN_WAIT_TIME)
                
                local maxRescans = DEFAULT_CONFIG.MAX_RESCANS
                local rescanCount = 0
                local brainrotStillPresent = true
                
                while isRunning and brainrotStillPresent and rescanCount < maxRescans do
                    lastActivityTime = tick()
                    if scanForBrainrot() then
                        logToConsole("✅ Still present, waiting... (" .. (rescanCount + 1) .. "/" .. maxRescans .. ")", Color3.fromRGB(0, 255, 0))
                        safeWait(DEFAULT_CONFIG.SCAN_WAIT_TIME)
                        rescanCount = rescanCount + 1
                    else
                        logToConsole("❌ Brainrot no longer found", Color3.fromRGB(255, 150, 0))
                        brainrotStillPresent = false
                    end
                end
                
                if rescanCount >= maxRescans then
                    logToConsole("⚠ Max rescans reached, moving to next server", Color3.fromRGB(255, 150, 0))
                end
                
                if isRunning then
                    logToConsole("Starting server hop...", Color3.fromRGB(255, 255, 0))
                    task.spawn(serverHop)
                    break
                end
            elseif scanResult == "force_hop" then
                logToConsole("🔄 Force hopping due to too many failed scans", Color3.fromRGB(255, 200, 0))
                consecutiveNoBrainrot = 0
                task.spawn(serverHop)
                break
            else
                logToConsole("No brainrot found above threshold", Color3.fromRGB(255, 150, 0))
                logToConsole("Waiting " .. DEFAULT_CONFIG.SERVER_HOP_DELAY .. "s...", Color3.fromRGB(255, 255, 0))
                
                safeWait(DEFAULT_CONFIG.SERVER_HOP_DELAY)
                logToConsole("Starting server hop...", Color3.fromRGB(255, 255, 0))
                task.spawn(serverHop)
                break
            end
        end
        
        task.wait(0.1)
    end
end

-- ============ FORCE RESET FUNCTION ============
local function forceReset()
    logToConsole("🔄 Force reset triggered", Color3.fromRGB(255, 200, 0))
    
    sentThisServer = false
    fastHopMode = false
    fastHopCount = 0
    consecutiveNoBrainrot = 0
    updateStatus("Force Reset", Color3.fromRGB(255, 200, 0))
    
    task.wait(1)
    if isRunning then
        serverHop()
    end
end

-- ============ GUI (FIXED) ============
local function createGUI()
    if not DEFAULT_CONFIG.GUI_ENABLED then return end
    
    -- Create ScreenGui
    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BrainrotFinderGUI"
    ScreenGui.Parent = CoreGui
    
    -- Main Frame
    MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, DEFAULT_CONFIG.GUI_WIDTH, 0, DEFAULT_CONFIG.GUI_HEIGHT)
    MainFrame.Position = UDim2.new(
        DEFAULT_CONFIG.GUI_POSITION.X, -DEFAULT_CONFIG.GUI_WIDTH/2,
        DEFAULT_CONFIG.GUI_POSITION.Y, -DEFAULT_CONFIG.GUI_HEIGHT/2
    )
    MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = MainFrame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    title.Text = "🧠 Lore's Hub v8.1"
    title.TextColor3 = Color3.fromRGB(0, 200, 255)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.Parent = MainFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8, 0, 0)
    titleCorner.Parent = title
    
    -- Status
    StatusText = Instance.new("TextLabel")
    StatusText.Size = UDim2.new(1, -20, 0, 20)
    StatusText.Position = UDim2.new(0, 10, 0, 45)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "Status: Ready"
    StatusText.TextColor3 = Color3.fromRGB(200, 200, 200)
    StatusText.TextSize = 14
    StatusText.Font = Enum.Font.Gotham
    StatusText.TextXAlignment = Enum.TextXAlignment.Left
    StatusText.Parent = MainFrame
    
    -- Stats Grid
    local statsGrid = Instance.new("Frame")
    statsGrid.Size = UDim2.new(1, -20, 0, 80)
    statsGrid.Position = UDim2.new(0, 10, 0, 70)
    statsGrid.BackgroundTransparency = 1
    statsGrid.Parent = MainFrame
    
    -- Row 1: Labels
    local stat1Label = Instance.new("TextLabel")
    stat1Label.Size = UDim2.new(0.5, -5, 0, 20)
    stat1Label.Position = UDim2.new(0, 0, 0, 0)
    stat1Label.BackgroundTransparency = 1
    stat1Label.Text = "Attempts:"
    stat1Label.TextColor3 = Color3.fromRGB(150, 150, 180)
    stat1Label.TextSize = 12
    stat1Label.Font = Enum.Font.Gotham
    stat1Label.TextXAlignment = Enum.TextXAlignment.Left
    stat1Label.Parent = statsGrid
    
    local stat2Label = Instance.new("TextLabel")
    stat2Label.Size = UDim2.new(0.5, -5, 0, 20)
    stat2Label.Position = UDim2.new(0.5, 5, 0, 0)
    stat2Label.BackgroundTransparency = 1
    stat2Label.Text = "Found:"
    stat2Label.TextColor3 = Color3.fromRGB(150, 150, 180)
    stat2Label.TextSize = 12
    stat2Label.Font = Enum.Font.Gotham
    stat2Label.TextXAlignment = Enum.TextXAlignment.Left
    stat2Label.Parent = statsGrid
    
    -- Row 2: Values
    Stat1Value = Instance.new("TextLabel")
    Stat1Value.Size = UDim2.new(0.5, -5, 0, 25)
    Stat1Value.Position = UDim2.new(0, 0, 0, 20)
    Stat1Value.BackgroundTransparency = 1
    Stat1Value.Text = "0"
    Stat1Value.TextColor3 = Color3.fromRGB(255, 255, 255)
    Stat1Value.TextSize = 18
    Stat1Value.Font = Enum.Font.GothamBold
    Stat1Value.TextXAlignment = Enum.TextXAlignment.Left
    Stat1Value.Parent = statsGrid
    
    Stat2Value = Instance.new("TextLabel")
    Stat2Value.Size = UDim2.new(0.5, -5, 0, 25)
    Stat2Value.Position = UDim2.new(0.5, 5, 0, 20)
    Stat2Value.BackgroundTransparency = 1
    Stat2Value.Text = "0"
    Stat2Value.TextColor3 = Color3.fromRGB(0, 255, 127)
    Stat2Value.TextSize = 18
    Stat2Value.Font = Enum.Font.GothamBold
    Stat2Value.TextXAlignment = Enum.TextXAlignment.Left
    Stat2Value.Parent = statsGrid
    
    -- Row 3: Labels
    local stat3Label = Instance.new("TextLabel")
    stat3Label.Size = UDim2.new(0.5, -5, 0, 20)
    stat3Label.Position = UDim2.new(0, 0, 0, 50)
    stat3Label.BackgroundTransparency = 1
    stat3Label.Text = "Players:"
    stat3Label.TextColor3 = Color3.fromRGB(150, 150, 180)
    stat3Label.TextSize = 12
    stat3Label.Font = Enum.Font.Gotham
    stat3Label.TextXAlignment = Enum.TextXAlignment.Left
    stat3Label.Parent = statsGrid
    
    local stat4Label = Instance.new("TextLabel")
    stat4Label.Size = UDim2.new(0.5, -5, 0, 20)
    stat4Label.Position = UDim2.new(0.5, 5, 0, 50)
    stat4Label.BackgroundTransparency = 1
    stat4Label.Text = "Server ID:"
    stat4Label.TextColor3 = Color3.fromRGB(150, 150, 180)
    stat4Label.TextSize = 12
    stat4Label.Font = Enum.Font.Gotham
    stat4Label.TextXAlignment = Enum.TextXAlignment.Left
    stat4Label.Parent = statsGrid
    
    -- Row 4: Values
    Stat3Value = Instance.new("TextLabel")
    Stat3Value.Size = UDim2.new(0.5, -5, 0, 25)
    Stat3Value.Position = UDim2.new(0, 0, 0, 70)
    Stat3Value.BackgroundTransparency = 1
    Stat3Value.Text = "0"
    Stat3Value.TextColor3 = Color3.fromRGB(255, 255, 255)
    Stat3Value.TextSize = 18
    Stat3Value.Font = Enum.Font.GothamBold
    Stat3Value.TextXAlignment = Enum.TextXAlignment.Left
    Stat3Value.Parent = statsGrid
    
    Stat4Value = Instance.new("TextLabel")
    Stat4Value.Size = UDim2.new(0.5, -5, 0, 25)
    Stat4Value.Position = UDim2.new(0.5, 5, 0, 70)
    Stat4Value.BackgroundTransparency = 1
    Stat4Value.Text = "N/A"
    Stat4Value.TextColor3 = Color3.fromRGB(255, 255, 255)
    Stat4Value.TextSize = 14
    Stat4Value.Font = Enum.Font.GothamBold
    Stat4Value.TextXAlignment = Enum.TextXAlignment.Left
    Stat4Value.Parent = statsGrid
    
    -- Webhook Input Frame
    local webhookFrame = Instance.new("Frame")
    webhookFrame.Size = UDim2.new(1, -20, 0, 35)
    webhookFrame.Position = UDim2.new(0, 10, 0, 160)
    webhookFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    webhookFrame.BorderSizePixel = 0
    webhookFrame.Parent = MainFrame
    
    local webhookCorner = Instance.new("UICorner")
    webhookCorner.CornerRadius = UDim.new(0, 6)
    webhookCorner.Parent = webhookFrame
    
    local webhookLabel = Instance.new("TextLabel")
    webhookLabel.Size = UDim2.new(0, 80, 1, 0)
    webhookLabel.Position = UDim2.new(0, 5, 0, 0)
    webhookLabel.BackgroundTransparency = 1
    webhookLabel.Text = "Webhook:"
    webhookLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
    webhookLabel.TextSize = 12
    webhookLabel.Font = Enum.Font.GothamSemibold
    webhookLabel.TextXAlignment = Enum.TextXAlignment.Left
    webhookLabel.Parent = webhookFrame
    
    WebhookInput = Instance.new("TextBox")
    WebhookInput.Size = UDim2.new(0.65, -90, 1, -10)
    WebhookInput.Position = UDim2.new(0, 85, 0, 5)
    WebhookInput.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    WebhookInput.TextColor3 = Color3.fromRGB(200, 200, 255)
    WebhookInput.Text = DEFAULT_CONFIG.WEBHOOK_URL or ""
    WebhookInput.PlaceholderText = "Enter Discord webhook URL"
    WebhookInput.TextSize = 11
    WebhookInput.Font = Enum.Font.Gotham
    WebhookInput.TextXAlignment = Enum.TextXAlignment.Left
    WebhookInput.ClearTextOnFocus = false
    WebhookInput.Parent = webhookFrame
    
    SaveWebhookButton = Instance.new("TextButton")
    SaveWebhookButton.Size = UDim2.new(0.25, -5, 1, -10)
    SaveWebhookButton.Position = UDim2.new(0.75, 5, 0, 5)
    SaveWebhookButton.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
    SaveWebhookButton.Text = "SAVE"
    SaveWebhookButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    SaveWebhookButton.TextSize = 12
    SaveWebhookButton.Font = Enum.Font.GothamBold
    SaveWebhookButton.Parent = webhookFrame
    
    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 4)
    saveCorner.Parent = SaveWebhookButton
    
    -- Million Counter
    local millionFrame = Instance.new("Frame")
    millionFrame.Size = UDim2.new(1, -20, 0, 25)
    millionFrame.Position = UDim2.new(0, 10, 0, 200)
    millionFrame.BackgroundColor3 = Color3.fromRGB(40, 10, 20)
    millionFrame.BorderSizePixel = 0
    millionFrame.Parent = MainFrame
    
    local millionCorner = Instance.new("UICorner")
    millionCorner.CornerRadius = UDim.new(0, 6)
    millionCorner.Parent = millionFrame
    
    local millionLabel = Instance.new("TextLabel")
    millionLabel.Size = UDim2.new(0.6, -5, 1, 0)
    millionLabel.Position = UDim2.new(0, 5, 0, 0)
    millionLabel.BackgroundTransparency = 1
    millionLabel.Text = "💎 1M+ Found:"
    millionLabel.TextColor3 = Color3.fromRGB(255, 150, 200)
    millionLabel.TextSize = 12
    millionLabel.Font = Enum.Font.GothamSemibold
    millionLabel.TextXAlignment = Enum.TextXAlignment.Left
    millionLabel.Parent = millionFrame
    
    MillionCounter = Instance.new("TextLabel")
    MillionCounter.Size = UDim2.new(0.4, -5, 1, 0)
    MillionCounter.Position = UDim2.new(0.6, 5, 0, 0)
    MillionCounter.BackgroundTransparency = 1
    MillionCounter.Text = "0"
    MillionCounter.TextColor3 = Color3.fromRGB(255, 50, 150)
    MillionCounter.TextSize = 16
    MillionCounter.Font = Enum.Font.GothamBold
    MillionCounter.TextXAlignment = Enum.TextXAlignment.Right
    MillionCounter.Parent = millionFrame
    
    -- Console Frame
    local consoleFrame = Instance.new("Frame")
    consoleFrame.Size = UDim2.new(1, -20, 0, 100)
    consoleFrame.Position = UDim2.new(0, 10, 0, 230)
    consoleFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
    consoleFrame.BorderSizePixel = 0
    consoleFrame.Parent = MainFrame
    
    local consoleCorner = Instance.new("UICorner")
    consoleCorner.CornerRadius = UDim.new(0, 6)
    consoleCorner.Parent = consoleFrame
    
    ConsoleScrolling = Instance.new("ScrollingFrame")
    ConsoleScrolling.Size = UDim2.new(1, -10, 1, -10)
    ConsoleScrolling.Position = UDim2.new(0, 5, 0, 5)
    ConsoleScrolling.BackgroundTransparency = 1
    ConsoleScrolling.BorderSizePixel = 0
    ConsoleScrolling.ScrollBarThickness = 6
    ConsoleScrolling.Parent = consoleFrame
    
    ConsoleLayout = Instance.new("UIListLayout")
    ConsoleLayout.Padding = UDim.new(0, 2)
    ConsoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ConsoleLayout.Parent = ConsoleScrolling
    
    -- Brainrot Tracker Frame
    local trackerFrame = Instance.new("Frame")
    trackerFrame.Size = UDim2.new(1, -20, 0, 120)
    trackerFrame.Position = UDim2.new(0, 10, 0, 335)
    trackerFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    trackerFrame.BorderSizePixel = 0
    trackerFrame.Parent = MainFrame
    
    local trackerCorner = Instance.new("UICorner")
    trackerCorner.CornerRadius = UDim.new(0, 6)
    trackerCorner.Parent = trackerFrame
    
    local trackerTitle = Instance.new("TextLabel")
    trackerTitle.Size = UDim2.new(1, 0, 0, 25)
    trackerTitle.Position = UDim2.new(0, 0, 0, 0)
    trackerTitle.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    trackerTitle.Text = "📋 Recent Brainrots"
    trackerTitle.TextColor3 = Color3.fromRGB(200, 200, 255)
    trackerTitle.TextSize = 12
    trackerTitle.Font = Enum.Font.GothamBold
    trackerTitle.Parent = trackerFrame
    
    local titleTrackerCorner = Instance.new("UICorner")
    titleTrackerCorner.CornerRadius = UDim.new(0, 6, 0, 0)
    titleTrackerCorner.Parent = trackerTitle
    
    brainrotTrackerContainer = Instance.new("ScrollingFrame")
    brainrotTrackerContainer.Size = UDim2.new(1, -10, 1, -35)
    brainrotTrackerContainer.Position = UDim2.new(0, 5, 0, 30)
    brainrotTrackerContainer.BackgroundTransparency = 1
    brainrotTrackerContainer.BorderSizePixel = 0
    brainrotTrackerContainer.ScrollBarThickness = 6
    brainrotTrackerContainer.Parent = trackerFrame
    
    -- Buttons Row
    local buttonsFrame = Instance.new("Frame")
    buttonsFrame.Size = UDim2.new(1, -20, 0, 35)
    buttonsFrame.Position = UDim2.new(0, 10, 1, -95)
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.Parent = MainFrame
    
    StartButton = Instance.new("TextButton")
    StartButton.Size = UDim2.new(0.3, -5, 1, 0)
    StartButton.Position = UDim2.new(0, 0, 0, 0)
    StartButton.BackgroundColor3 = Color3.fromRGB(0, 150, 50)
    StartButton.Text = "START"
    StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    StartButton.TextSize = 14
    StartButton.Font = Enum.Font.GothamBold
    StartButton.Parent = buttonsFrame
    
    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 6)
    startCorner.Parent = StartButton
    
    StopButton = Instance.new("TextButton")
    StopButton.Size = UDim2.new(0.3, -5, 1, 0)
    StopButton.Position = UDim2.new(0.33, 5, 0, 0)
    StopButton.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
    StopButton.Text = "STOP"
    StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    StopButton.TextSize = 14
    StopButton.Font = Enum.Font.GothamBold
    StopButton.Parent = buttonsFrame
    
    local stopCorner = Instance.new("UICorner")
    stopCorner.CornerRadius = UDim.new(0, 6)
    stopCorner.Parent = StopButton
    
    DebugScanButton = Instance.new("TextButton")
    DebugScanButton.Size = UDim2.new(0.3, -5, 1, 0)
    DebugScanButton.Position = UDim2.new(0.66, 5, 0, 0)
    DebugScanButton.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
    DebugScanButton.Text = "DEBUG"
    DebugScanButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    DebugScanButton.TextSize = 14
    DebugScanButton.Font = Enum.Font.GothamBold
    DebugScanButton.Parent = buttonsFrame
    
    local debugCorner = Instance.new("UICorner")
    debugCorner.CornerRadius = UDim.new(0, 6)
    debugCorner.Parent = DebugScanButton
    
    -- Additional Buttons Row
    local buttonsFrame2 = Instance.new("Frame")
    buttonsFrame2.Size = UDim2.new(1, -20, 0, 35)
    buttonsFrame2.Position = UDim2.new(0, 10, 1, -55)
    buttonsFrame2.BackgroundTransparency = 1
    buttonsFrame2.Parent = MainFrame
    
    ForceHopButton = Instance.new("TextButton")
    ForceHopButton.Size = UDim2.new(0.45, -5, 1, 0)
    ForceHopButton.Position = UDim2.new(0, 0, 0, 0)
    ForceHopButton.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
    ForceHopButton.Text = "FORCE HOP"
    ForceHopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ForceHopButton.TextSize = 14
    ForceHopButton.Font = Enum.Font.GothamBold
    ForceHopButton.Parent = buttonsFrame2
    
    local forceCorner = Instance.new("UICorner")
    forceCorner.CornerRadius = UDim.new(0, 6)
    forceCorner.Parent = ForceHopButton
    
    local testWebhookButton = Instance.new("TextButton")
    testWebhookButton.Size = UDim2.new(0.45, -5, 1, 0)
    testWebhookButton.Position = UDim2.new(0.55, 5, 0, 0)
    testWebhookButton.BackgroundColor3 = Color3.fromRGB(150, 0, 150)
    testWebhookButton.Text = "TEST"
    testWebhookButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    testWebhookButton.TextSize = 14
    testWebhookButton.Font = Enum.Font.GothamBold
    testWebhookButton.Parent = buttonsFrame2
    
    local testCorner = Instance.new("UICorner")
    testCorner.CornerRadius = UDim.new(0, 6)
    testCorner.Parent = testWebhookButton
    
    -- Button Events
    StartButton.MouseButton1Click:Connect(function()
        if not isRunning then
            isRunning = true
            logToConsole("⚡ Script started", Color3.fromRGB(0, 255, 0))
            updateStatus("Starting...", Color3.fromRGB(0, 255, 0))
            task.spawn(main)
        end
    end)
    
    StopButton.MouseButton1Click:Connect(function()
        if isRunning then
            isRunning = false
            logToConsole("🛑 Script stopped", Color3.fromRGB(255, 100, 100))
            updateStatus("Stopped", Color3.fromRGB(255, 100, 100))
        end
    end)
    
    DebugScanButton.MouseButton1Click:Connect(function()
        logToConsole("🧪 Manual debug scan triggered", Color3.fromRGB(255, 200, 0))
        task.spawn(debugScanWorkspace)
    end)
    
    ForceHopButton.MouseButton1Click:Connect(function()
        logToConsole("🔄 Manual force hop triggered", Color3.fromRGB(255, 200, 0))
        forceReset()
    end)
    
    testWebhookButton.MouseButton1Click:Connect(function()
        logToConsole("🔗 Testing webhook...", Color3.fromRGB(200, 100, 255))
        task.spawn(testWebhook)
    end)
    
    SaveWebhookButton.MouseButton1Click:Connect(function()
        updateWebhookURL()
    end)
    
    WebhookInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            updateWebhookURL()
        end
    end)
    
    -- Update stats periodically
    task.spawn(function()
        while ScreenGui and ScreenGui.Parent do
            if Stat3Value then
                Stat3Value.Text = tostring(#Players:GetPlayers())
            end
            if Stat4Value then
                Stat4Value.Text = game.JobId:sub(1, 8) .. "..."
            end
            if MillionCounter then
                MillionCounter.Text = tostring(millionPlusCount)
            end
            task.wait(2)
        end
    end)
    
    -- Make draggable
    local dragging = false
    local dragInput, dragStart, startPos
    
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                         startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    logToConsole("GUI initialized successfully", Color3.fromRGB(0, 200, 255))
    logToConsole("💡 Enter your Discord webhook URL in the input field", Color3.fromRGB(150, 200, 255))
end

-- ============ INITIALIZATION ============
task.spawn(function()
    print("\n" .. string.rep("=", 60))
    print("🧠 Lore's Hub v8.1 - FIXED SERVER HOP")
    print("🎯 Target: AnimalOverhead SurfaceGui → Generation TextLabel")
    print("💰 Skips $1/s templates in Debris folder")
    print("🔍 Only detects REAL brainrots")
    print("💎 ALL 1M+ brainrots → Discord Webhook")
    print("📊 Thresholds: HIGH=$1M, ULTRA=$5M")
    print("🔄 FIXED: Server hopping with Roblox API + Backend fallback")
    print(string.rep("=", 60) .. "\n")
    
    loadConfig()
    
    -- Hotkeys
    UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.F5 then
            forceReset()
        elseif input.KeyCode == Enum.KeyCode.F6 then
            task.spawn(debugScanWorkspace)
        elseif input.KeyCode == Enum.KeyCode.F7 then
            testWebhook()
        end
    end)
    
    if DEFAULT_CONFIG.GUI_ENABLED then
        createGUI()
    else
        print("[CONSOLE] 📟 Console mode active")
        
        task.wait(1)
        local debugSuccess, debugErr = pcall(debugScanWorkspace)
        if not debugSuccess then
            print("⚠ Debug scan failed: " .. tostring(debugErr))
        end
    end
    
    -- Test scan first
    task.wait(2)
    logToConsole("🧪 Running initial debug scan...", Color3.fromRGB(255, 200, 0))
    task.wait(1)
    local debugSuccess, debugErr = pcall(debugScanWorkspace)
    if not debugSuccess then
        logToConsole("⚠ Debug scan failed: " .. tostring(debugErr), Color3.fromRGB(255, 150, 0))
    end
    
    -- Auto-start
    if DEFAULT_CONFIG.AUTO_START and not isRunning then
        task.wait(DEFAULT_CONFIG.AUTO_START_DELAY)
        logToConsole("⚡ Auto-start activated...", Color3.fromRGB(0, 255, 0))
        isRunning = true
        task.spawn(main)
    end
end)

-- Keep script alive
while task.wait(5) do
    if not isRunning then
        break
    end
end
