PedSimulation = {
    _version = "1.0.0"
}

local APPLY_INTENT_EVENT = "llmPedSimulation:applyIntent"
local CLEAR_INTENT_EVENT = "llmPedSimulation:clearIntent"
local PED_FLAG_KEY = "llmPedSimulation:isManaged"

local DEFAULT_CONFIG = {
    pedCount = 3,
    pedModel = 0,
    bounds = {
        minX = -50,
        maxX = 50,
        minY = -50,
        maxY = 50,
        z = 5
    },
    decisionIntervalMs = 3500,
    schedulerTickMs = 300,
    movementTickMs = 200,
    controlUpdateMs = 250,
    maxConcurrentRequests = 3,
    maxQueueSize = 300,
    nearbyRadius = 20,
    interactionRadius = 4,
    interactionCooldownMs = 6000,
    maxNearbyPedsInPrompt = 5,
    fallbackDecisionIntervalMs = 6500,
    useAnalogControls = true,
    debug = false
}

local DIRECTION_HEADINGS = {
    N = 0,
    NE = 45,
    E = 90,
    SE = 135,
    S = 180,
    SW = 225,
    W = 270,
    NW = 315,
    STAY = false
}

local DIRECTION_KEYS = {"N", "NE", "E", "SE", "S", "SW", "W", "NW", "STAY"}

local runtime = {
    active = false,
    config = nil,
    pedsById = {},
    pedStateByElement = {},
    queue = {},
    queuedById = {},
    inFlightCount = 0,
    nextId = 1,
    timers = {
        scheduler = nil,
        movement = nil
    },
    stats = {
        spawned = 0,
        despawned = 0,
        decisionsRequested = 0,
        decisionsSucceeded = 0,
        decisionsFailed = 0,
        fallbacksUsed = 0,
        boundaryCorrections = 0,
        queueDepthPeak = 0,
        queueDrops = 0,
        interactions = 0
    }
}

local function shallowCopy(source)
    local copied = {}
    for key, value in pairs(source) do
        copied[key] = value
    end
    return copied
end

local function clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

local function normalizeConfig(config)
    local merged = shallowCopy(DEFAULT_CONFIG)
    local provided = config or {}
    for key, value in pairs(provided) do
        if key ~= "bounds" then
            merged[key] = value
        end
    end
    local bounds = shallowCopy(DEFAULT_CONFIG.bounds)
    if type(provided.bounds) == "table" then
        for key, value in pairs(provided.bounds) do
            bounds[key] = value
        end
    end
    if bounds.minX > bounds.maxX then
        local temporary = bounds.minX
        bounds.minX = bounds.maxX
        bounds.maxX = temporary
    end
    if bounds.minY > bounds.maxY then
        local temporary = bounds.minY
        bounds.minY = bounds.maxY
        bounds.maxY = temporary
    end
    merged.bounds = bounds
    merged.pedCount = math.max(0, math.floor(tonumber(merged.pedCount) or DEFAULT_CONFIG.pedCount))
    merged.pedModel = math.max(0, math.floor(tonumber(merged.pedModel) or DEFAULT_CONFIG.pedModel))
    merged.decisionIntervalMs = math.max(500, math.floor(tonumber(merged.decisionIntervalMs) or DEFAULT_CONFIG.decisionIntervalMs))
    merged.schedulerTickMs = math.max(100, math.floor(tonumber(merged.schedulerTickMs) or DEFAULT_CONFIG.schedulerTickMs))
    merged.movementTickMs = math.max(100, math.floor(tonumber(merged.movementTickMs) or DEFAULT_CONFIG.movementTickMs))
    merged.controlUpdateMs = math.max(100, math.floor(tonumber(merged.controlUpdateMs) or DEFAULT_CONFIG.controlUpdateMs))
    merged.maxConcurrentRequests = math.max(1, math.floor(tonumber(merged.maxConcurrentRequests) or DEFAULT_CONFIG.maxConcurrentRequests))
    merged.maxQueueSize = math.max(1, math.floor(tonumber(merged.maxQueueSize) or DEFAULT_CONFIG.maxQueueSize))
    merged.nearbyRadius = math.max(2, tonumber(merged.nearbyRadius) or DEFAULT_CONFIG.nearbyRadius)
    merged.interactionRadius = math.max(1, tonumber(merged.interactionRadius) or DEFAULT_CONFIG.interactionRadius)
    merged.interactionCooldownMs = math.max(1000, math.floor(tonumber(merged.interactionCooldownMs) or DEFAULT_CONFIG.interactionCooldownMs))
    merged.maxNearbyPedsInPrompt = math.max(1, math.floor(tonumber(merged.maxNearbyPedsInPrompt) or DEFAULT_CONFIG.maxNearbyPedsInPrompt))
    merged.fallbackDecisionIntervalMs = math.max(1000, math.floor(tonumber(merged.fallbackDecisionIntervalMs) or DEFAULT_CONFIG.fallbackDecisionIntervalMs))
    merged.useAnalogControls = not not merged.useAnalogControls
    merged.debug = not not merged.debug
    return merged
end

local function countManagedPeds()
    local count = 0
    for _, state in pairs(runtime.pedsById) do
        if state and isElement(state.element) then
            count = count + 1
        end
    end
    return count
end

local function debugLog(message)
    if runtime.config and runtime.config.debug then
        outputDebugString("[PedSimulation] " .. message)
    end
end

local function removeQueuedPed(pedId)
    if not runtime.queuedById[pedId] then
        return
    end
    runtime.queuedById[pedId] = nil
    for index = #runtime.queue, 1, -1 do
        if runtime.queue[index] == pedId then
            table.remove(runtime.queue, index)
        end
    end
end

local function computeDirectionFromVector(dx, dy)
    local horizontal = ""
    local vertical = ""
    if dx > 1 then
        horizontal = "E"
    elseif dx < -1 then
        horizontal = "W"
    end
    if dy > 1 then
        vertical = "N"
    elseif dy < -1 then
        vertical = "S"
    end
    local direction = vertical .. horizontal
    if direction == "" then
        direction = "STAY"
    end
    if not DIRECTION_HEADINGS[direction] and direction ~= "STAY" then
        direction = "STAY"
    end
    return direction
end

local function clearPedControls(ped)
    if isElement(ped) then
        triggerClientEvent(root, CLEAR_INTENT_EVENT, resourceRoot, ped)
    end
end

local function applyIntentToClients(state, force)
    if not state.intent or not isElement(state.element) then
        return
    end
    local now = getTickCount()
    local remainingMs = state.intent.expiresAt - now
    if remainingMs <= 0 then
        return
    end
    if not force and now - state.intent.lastBroadcastAt < runtime.config.controlUpdateMs then
        return
    end
    state.intent.lastBroadcastAt = now
    triggerClientEvent(root, APPLY_INTENT_EVENT, resourceRoot, state.element, {
        controls = state.intent.controls,
        analog = state.intent.analog,
        durationMs = remainingMs,
        useAnalogControls = runtime.config.useAnalogControls
    })
end

local function sanitizeInteraction(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:gsub("[%c\r\n\t]", " ")
    trimmed = trimmed:gsub("%s+", " ")
    trimmed = trimmed:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end
    if #trimmed > 120 then
        trimmed = trimmed:sub(1, 120)
    end
    return trimmed
end

local function applyDecisionIntent(state, decision, source)
    if not isElement(state.element) then
        return
    end
    local heading = DIRECTION_HEADINGS[decision.direction]
    if heading then
        setElementRotation(state.element, 0, 0, heading)
    end
    if type(decision.walkStyle) == "number" then
        setPedWalkingStyle(state.element, math.floor(decision.walkStyle))
    end
    local durationMs = math.floor(clamp(decision.steps, 1, 5) * 700)
    local controlPayload = {
        controls = {},
        analog = {},
        expiresAt = getTickCount() + durationMs,
        lastBroadcastAt = 0
    }
    if decision.direction ~= "STAY" then
        controlPayload.controls.forwards = true
        controlPayload.analog.forwards = clamp(decision.speed, 0.1, 1.0)
    end
    state.intent = controlPayload
    state.lastDecisionSource = source
    applyIntentToClients(state, true)
    local interaction = sanitizeInteraction(decision.interaction)
    if interaction then
        local now = getTickCount()
        if now - state.lastInteractionAt >= runtime.config.interactionCooldownMs then
            runtime.stats.interactions = runtime.stats.interactions + 1
            state.lastInteractionAt = now
            outputDebugString(string.format("[Ped %s] %s", state.name, interaction))
        end
    end
end

local function normalizeDecision(raw)
    if type(raw) ~= "table" then
        return nil, "decision_not_table"
    end
    local direction = raw.direction
    if type(direction) ~= "string" then
        return nil, "direction_missing"
    end
    direction = direction:upper()
    if not DIRECTION_HEADINGS[direction] and direction ~= "STAY" then
        return nil, "direction_invalid"
    end
    local steps = clamp(tonumber(raw.steps) or 2, 1, 5)
    local speed = clamp(tonumber(raw.speed) or 0.5, 0.1, 1.0)
    local walkStyle = raw.walkStyle
    if walkStyle ~= nil then
        walkStyle = tonumber(walkStyle)
    end
    return {
        direction = direction,
        steps = steps,
        speed = speed,
        interaction = raw.interaction,
        walkStyle = walkStyle
    }, nil
end

local function randomFallbackDecision()
    local direction = DIRECTION_KEYS[math.random(1, #DIRECTION_KEYS)]
    return {
        direction = direction,
        steps = math.random(1, 3),
        speed = 0.45,
        interaction = nil,
        walkStyle = nil
    }
end

local function scheduleNextDecision(state, intervalMs)
    local jitter = math.random(100, 700)
    state.nextDecisionAt = getTickCount() + intervalMs + jitter
end

local function handleDecisionFailure(state, reason)
    runtime.stats.decisionsFailed = runtime.stats.decisionsFailed + 1
    runtime.stats.fallbacksUsed = runtime.stats.fallbacksUsed + 1
    state.failureCount = state.failureCount + 1
    applyDecisionIntent(state, randomFallbackDecision(), "fallback:" .. tostring(reason))
    local penalty = runtime.config.fallbackDecisionIntervalMs + (state.failureCount - 1) * 500
    scheduleNextDecision(state, penalty)
end

local function buildNearbySummary(state)
    local sourcePed = state.element
    local x, y = getElementPosition(sourcePed)
    local nearby = {}
    local radius = runtime.config.nearbyRadius
    local maxNearby = runtime.config.maxNearbyPedsInPrompt
    for pedId, otherState in pairs(runtime.pedsById) do
        if pedId ~= state.id and isElement(otherState.element) then
            local ox, oy = getElementPosition(otherState.element)
            local dx = ox - x
            local dy = oy - y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance <= radius then
                nearby[#nearby + 1] = {
                    id = otherState.id,
                    name = otherState.name,
                    distance = tonumber(string.format("%.1f", distance)),
                    dx = tonumber(string.format("%.1f", dx)),
                    dy = tonumber(string.format("%.1f", dy))
                }
            end
        end
    end
    table.sort(nearby, function(a, b)
        return a.distance < b.distance
    end)
    while #nearby > maxNearby do
        table.remove(nearby)
    end
    local nearbyCount = #nearby
    local density = "sparse"
    if nearbyCount >= 5 then
        density = "crowded"
    elseif nearbyCount >= 2 then
        density = "medium"
    end
    local bounds = runtime.config.bounds
    local margin = 8
    local boundary = "center"
    if x - bounds.minX <= margin then
        boundary = "west_edge"
    elseif bounds.maxX - x <= margin then
        boundary = "east_edge"
    elseif y - bounds.minY <= margin then
        boundary = "south_edge"
    elseif bounds.maxY - y <= margin then
        boundary = "north_edge"
    end
    return {
        x = tonumber(string.format("%.1f", x)),
        y = tonumber(string.format("%.1f", y)),
        nearby = nearby,
        nearbyCount = nearbyCount,
        density = density,
        boundary = boundary
    }
end

local function buildPrompt(state, snapshot)
    local nearbyParts = {}
    for _, nearbyPed in ipairs(snapshot.nearby) do
        nearbyParts[#nearbyParts + 1] = string.format("%s(%sm,dx=%s,dy=%s)", nearbyPed.name, nearbyPed.distance, nearbyPed.dx, nearbyPed.dy)
    end
    local nearbyString = table.concat(nearbyParts, "; ")
    if nearbyString == "" then
        nearbyString = "none"
    end
    local system = "You are the decision model for one simulated city pedestrian. Respond with JSON only."
    local prompt = string.format(
        "Ped name:%s\nPosition:(%s,%s)\nBoundary:%s\nDensity:%s\nNearby:%s\nLastMemory:%s\nReturn valid JSON object with keys direction,steps,speed,interaction,walkStyle. direction must be one of N,NE,E,SE,S,SW,W,NW,STAY. steps is integer 1-5. speed is number 0.1-1.0. interaction is optional short text.",
        state.name,
        snapshot.x,
        snapshot.y,
        snapshot.boundary,
        snapshot.density,
        nearbyString,
        state.memorySummary
    )
    return prompt, system
end

local function dispatchDecisionRequest(state)
    if not isElement(state.element) then
        return
    end
    state.pendingRequest = true
    state.lastDecisionAt = getTickCount()
    runtime.inFlightCount = runtime.inFlightCount + 1
    runtime.stats.decisionsRequested = runtime.stats.decisionsRequested + 1
    local snapshot = buildNearbySummary(state)
    local prompt, system = buildPrompt(state, snapshot)
    local call = AI.generateObject(prompt, system)
    if type(call) ~= "function" then
        state.pendingRequest = false
        runtime.inFlightCount = math.max(0, runtime.inFlightCount - 1)
        handleDecisionFailure(state, "request_function_missing")
        return
    end
    call(function(result, requestError)
        runtime.inFlightCount = math.max(0, runtime.inFlightCount - 1)
        state.pendingRequest = false
        if not runtime.pedsById[state.id] or not isElement(state.element) then
            return
        end
        if requestError then
            debugLog("Decision failed for " .. state.name .. ": " .. tostring(requestError))
            handleDecisionFailure(state, requestError)
            return
        end
        local decision, parseError = normalizeDecision(result)
        if not decision then
            debugLog("Decision invalid for " .. state.name .. ": " .. tostring(parseError))
            handleDecisionFailure(state, parseError)
            return
        end
        runtime.stats.decisionsSucceeded = runtime.stats.decisionsSucceeded + 1
        state.failureCount = 0
        state.memorySummary = string.format("dir=%s density=%s nearby=%d", decision.direction, snapshot.density, snapshot.nearbyCount)
        applyDecisionIntent(state, decision, "llm")
        scheduleNextDecision(state, runtime.config.decisionIntervalMs)
    end)
end

local function queuePedForDecision(state)
    if state.pendingRequest or runtime.queuedById[state.id] then
        return
    end
    if #runtime.queue >= runtime.config.maxQueueSize then
        runtime.stats.queueDrops = runtime.stats.queueDrops + 1
        handleDecisionFailure(state, "queue_full")
        return
    end
    runtime.queuedById[state.id] = true
    runtime.queue[#runtime.queue + 1] = state.id
    if #runtime.queue > runtime.stats.queueDepthPeak then
        runtime.stats.queueDepthPeak = #runtime.queue
    end
end

local function drainDecisionQueue()
    while runtime.inFlightCount < runtime.config.maxConcurrentRequests and #runtime.queue > 0 do
        local pedId = table.remove(runtime.queue, 1)
        runtime.queuedById[pedId] = nil
        local state = runtime.pedsById[pedId]
        if state and isElement(state.element) and not state.pendingRequest then
            dispatchDecisionRequest(state)
        end
    end
end

local function applyBoundaryCorrection(state)
    local bounds = runtime.config.bounds
    local x, y = getElementPosition(state.element)
    local outOfBounds = x < bounds.minX or x > bounds.maxX or y < bounds.minY or y > bounds.maxY
    if not outOfBounds then
        return
    end
    local now = getTickCount()
    if now < state.boundaryCooldownUntil then
        return
    end
    runtime.stats.boundaryCorrections = runtime.stats.boundaryCorrections + 1
    local centerX = (bounds.minX + bounds.maxX) * 0.5
    local centerY = (bounds.minY + bounds.maxY) * 0.5
    local direction = computeDirectionFromVector(centerX - x, centerY - y)
    applyDecisionIntent(state, {
        direction = direction,
        steps = 2,
        speed = 1,
        interaction = nil,
        walkStyle = nil
    }, "boundary")
    state.boundaryCooldownUntil = now + 1200
    scheduleNextDecision(state, runtime.config.fallbackDecisionIntervalMs)
end

local function processSchedulerTick()
    if not runtime.active then
        return
    end
    local now = getTickCount()
    for pedId, state in pairs(runtime.pedsById) do
        if not isElement(state.element) then
            runtime.pedsById[pedId] = nil
            runtime.pedStateByElement[state.element] = nil
            removeQueuedPed(pedId)
        elseif now >= state.nextDecisionAt and not state.pendingRequest and not runtime.queuedById[pedId] then
            queuePedForDecision(state)
        end
    end
    drainDecisionQueue()
end

local function processMovementTick()
    if not runtime.active then
        return
    end
    local now = getTickCount()
    for pedId, state in pairs(runtime.pedsById) do
        if not isElement(state.element) then
            runtime.pedsById[pedId] = nil
            runtime.pedStateByElement[state.element] = nil
            removeQueuedPed(pedId)
        else
            applyBoundaryCorrection(state)
            if state.intent then
                if now >= state.intent.expiresAt then
                    state.intent = nil
                    clearPedControls(state.element)
                else
                    applyIntentToClients(state, false)
                end
            end
        end
    end
end

local function randomNameForPed(id)
    return string.format("ped_%03d", id)
end

local function randomSpawnPoint()
    local bounds = runtime.config.bounds
    local x = bounds.minX + math.random() * (bounds.maxX - bounds.minX)
    local y = bounds.minY + math.random() * (bounds.maxY - bounds.minY)
    return x, y, bounds.z
end

local function createPedState(model, x, y, z)
    local ped = createPed(model, x, y, z, math.random(0, 359), true)
    if not ped then
        return nil
    end
    setElementData(ped, PED_FLAG_KEY, true)
    local id = runtime.nextId
    runtime.nextId = runtime.nextId + 1
    local state = {
        id = id,
        name = randomNameForPed(id),
        element = ped,
        pendingRequest = false,
        nextDecisionAt = getTickCount() + math.random(300, runtime.config.decisionIntervalMs),
        lastDecisionAt = 0,
        lastInteractionAt = 0,
        boundaryCooldownUntil = 0,
        failureCount = 0,
        memorySummary = "none",
        intent = nil,
        lastDecisionSource = "none"
    }
    runtime.pedsById[id] = state
    runtime.pedStateByElement[ped] = state
    runtime.stats.spawned = runtime.stats.spawned + 1
    return state
end

function PedSimulation.spawn(count, spawnOptions)
    if not runtime.active then
        return false, "simulation_not_started"
    end
    local amount = math.max(0, math.floor(tonumber(count) or 0))
    local options = spawnOptions or {}
    local model = math.max(0, math.floor(tonumber(options.pedModel) or runtime.config.pedModel))
    local created = 0
    for index = 1, amount do
        local x
        local y
        local z
        if type(options.spawnPoints) == "table" and #options.spawnPoints > 0 then
            local point = options.spawnPoints[((index - 1) % #options.spawnPoints) + 1]
            if type(point) == "table" then
                x = tonumber(point.x)
                y = tonumber(point.y)
                z = tonumber(point.z)
            end
        end
        if not x or not y or not z then
            x, y, z = randomSpawnPoint()
        end
        local state = createPedState(model, x, y, z)
        if state then
            created = created + 1
        end
    end
    return true, created
end

function PedSimulation.despawnAll()
    for pedId, state in pairs(runtime.pedsById) do
        removeQueuedPed(pedId)
        if state.intent and isElement(state.element) then
            clearPedControls(state.element)
        end
        if isElement(state.element) then
            destroyElement(state.element)
            runtime.stats.despawned = runtime.stats.despawned + 1
        end
    end
    runtime.pedsById = {}
    runtime.pedStateByElement = {}
    runtime.queue = {}
    runtime.queuedById = {}
    runtime.inFlightCount = 0
    return true
end

local function stopTimers()
    if isTimer(runtime.timers.scheduler) then
        killTimer(runtime.timers.scheduler)
    end
    if isTimer(runtime.timers.movement) then
        killTimer(runtime.timers.movement)
    end
    runtime.timers.scheduler = nil
    runtime.timers.movement = nil
end

function PedSimulation.start(config)
    if not AI or type(AI.generateObject) ~= "function" then
        return false, "ai_engine_unavailable"
    end
    if runtime.active then
        PedSimulation.stop()
    end
    runtime.config = normalizeConfig(config or {})
    runtime.active = true
    runtime.pedsById = {}
    runtime.pedStateByElement = {}
    runtime.queue = {}
    runtime.queuedById = {}
    runtime.inFlightCount = 0
    runtime.nextId = 1
    runtime.stats = {
        spawned = 0,
        despawned = 0,
        decisionsRequested = 0,
        decisionsSucceeded = 0,
        decisionsFailed = 0,
        fallbacksUsed = 0,
        boundaryCorrections = 0,
        queueDepthPeak = 0,
        queueDrops = 0,
        interactions = 0
    }
    runtime.timers.scheduler = setTimer(processSchedulerTick, runtime.config.schedulerTickMs, 0)
    runtime.timers.movement = setTimer(processMovementTick, runtime.config.movementTickMs, 0)
    local ok, created = PedSimulation.spawn(runtime.config.pedCount)
    if not ok then
        return false, "spawn_failed"
    end
    debugLog("Started with ped count " .. tostring(created))
    return true, created
end

function PedSimulation.stop()
    runtime.active = false
    stopTimers()
    PedSimulation.despawnAll()
    return true
end

function PedSimulation.getStats()
    local stats = shallowCopy(runtime.stats)
    stats.activePeds = countManagedPeds()
    stats.inFlightRequests = runtime.inFlightCount
    stats.queueDepth = #runtime.queue
    stats.running = runtime.active
    return stats
end

function PedSimulation.getConfig()
    if not runtime.config then
        return nil
    end
    local config = shallowCopy(runtime.config)
    config.bounds = shallowCopy(runtime.config.bounds)
    return config
end

function startPedSimulation(config)
    return PedSimulation.start(config)
end

function stopPedSimulation()
    return PedSimulation.stop()
end

function spawnPedSimulation(count, spawnOptions)
    return PedSimulation.spawn(count, spawnOptions)
end

function despawnPedSimulation()
    return PedSimulation.despawnAll()
end

function getPedSimulationStats()
    return PedSimulation.getStats()
end

function getPedSimulationConfig()
    return PedSimulation.getConfig()
end

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "ped" then
        return
    end
    local state = runtime.pedStateByElement[source]
    if not state then
        return
    end
    runtime.pedsById[state.id] = nil
    runtime.pedStateByElement[source] = nil
    removeQueuedPed(state.id)
    runtime.stats.despawned = runtime.stats.despawned + 1
end)

addEventHandler("onResourceStop", resourceRoot, function()
    PedSimulation.stop()
end)

return PedSimulation
