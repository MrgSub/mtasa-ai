local DEMO_AI_CONFIG = {
    api_key = "",
    provider = "groq",
    model = "llama3-8b-8192",
    temperature = 0.4,
    max_tokens = 110
}

local DEMO_SIMULATION_CONFIG = {
    pedCount = 3,
    pedModel = 0,
    bounds = {
        minX = -40,
        maxX = 40,
        minY = -40,
        maxY = 40,
        z = 5
    },
    decisionIntervalMs = 3000,
    schedulerTickMs = 250,
    movementTickMs = 180,
    controlUpdateMs = 220,
    maxConcurrentRequests = 2,
    maxQueueSize = 300,
    nearbyRadius = 22,
    interactionRadius = 4,
    interactionCooldownMs = 7000,
    maxNearbyPedsInPrompt = 5,
    fallbackDecisionIntervalMs = 5500,
    useAnalogControls = true,
    debug = true
}

local function stringifyStats(stats)
    local parts = {}
    for key, value in pairs(stats) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function startDemoSimulation(config)
    local initSuccess, initError = pcall(AI.init, DEMO_AI_CONFIG)
    if not initSuccess then
        outputDebugString("[PedSimulationDemo] AI init failed: " .. tostring(initError))
        return false
    end
    local success, detail = PedSimulation.start(config or DEMO_SIMULATION_CONFIG)
    if success then
        outputDebugString("[PedSimulationDemo] started with peds: " .. tostring(detail))
    else
        outputDebugString("[PedSimulationDemo] start failed: " .. tostring(detail))
    end
    return success
end

addEventHandler("onResourceStart", resourceRoot, function()
    startDemoSimulation()
end)

addCommandHandler("pedsim_start", function(player)
    local success = startDemoSimulation()
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("Ped simulation start: " .. tostring(success), player, 210, 210, 255)
    end
end)

addCommandHandler("pedsim_stop", function(player)
    local success = PedSimulation.stop()
    outputDebugString("[PedSimulationDemo] stop: " .. tostring(success))
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("Ped simulation stopped", player, 255, 220, 200)
    end
end)

addCommandHandler("pedsim_spawn", function(player, _, amountText)
    local amount = math.max(1, math.floor(tonumber(amountText) or 1))
    local success, created = PedSimulation.spawn(amount)
    outputDebugString("[PedSimulationDemo] spawn success=" .. tostring(success) .. " created=" .. tostring(created))
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("Spawn result: " .. tostring(success) .. " created=" .. tostring(created), player, 200, 255, 200)
    end
end)

addCommandHandler("pedsim_stats", function(player)
    local stats = PedSimulation.getStats()
    local statsString = stringifyStats(stats)
    outputDebugString("[PedSimulationDemo] stats " .. statsString)
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox(statsString, player, 240, 255, 180)
    end
end)
