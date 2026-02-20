local APPLY_INTENT_EVENT = "llmPedSimulation:applyIntent"
local CLEAR_INTENT_EVENT = "llmPedSimulation:clearIntent"

local activeControlsByPed = {}
local releaseTimer = nil

local function releasePedControls(ped)
    local controlState = activeControlsByPed[ped]
    if not controlState then
        return
    end
    for controlName, isPressed in pairs(controlState.controls) do
        if isPressed then
            setPedControlState(ped, controlName, false)
        end
    end
    for controlName, _ in pairs(controlState.analog) do
        setPedAnalogControlState(ped, controlName, 0)
    end
    activeControlsByPed[ped] = nil
end

local function clearMissingControls(ped, previousState, nextState)
    for controlName, isPressed in pairs(previousState.controls) do
        if isPressed and not nextState.controls[controlName] then
            setPedControlState(ped, controlName, false)
        end
    end
    for controlName, _ in pairs(previousState.analog) do
        if not nextState.analog[controlName] then
            setPedAnalogControlState(ped, controlName, 0)
        end
    end
end

local function applyControlsToPed(ped, payload)
    if not isElement(ped) or getElementType(ped) ~= "ped" then
        return
    end
    local now = getTickCount()
    local previousState = activeControlsByPed[ped] or {
        controls = {},
        analog = {},
        expiresAt = 0
    }
    local nextState = {
        controls = {},
        analog = {},
        expiresAt = now + math.max(0, math.floor(tonumber(payload.durationMs) or 0))
    }
    if type(payload.controls) == "table" then
        for controlName, isPressed in pairs(payload.controls) do
            if type(controlName) == "string" and isPressed then
                nextState.controls[controlName] = true
            end
        end
    end
    if payload.useAnalogControls and type(payload.analog) == "table" then
        for controlName, analogValue in pairs(payload.analog) do
            if type(controlName) == "string" then
                local value = tonumber(analogValue) or 0
                if value > 0 then
                    nextState.analog[controlName] = math.max(0, math.min(1, value))
                end
            end
        end
    end
    clearMissingControls(ped, previousState, nextState)
    for controlName, isPressed in pairs(nextState.controls) do
        setPedControlState(ped, controlName, isPressed)
    end
    for controlName, analogValue in pairs(nextState.analog) do
        setPedAnalogControlState(ped, controlName, analogValue)
    end
    activeControlsByPed[ped] = nextState
end

local function processReleaseTick()
    local now = getTickCount()
    for ped, controlState in pairs(activeControlsByPed) do
        if not isElement(ped) or now >= controlState.expiresAt then
            releasePedControls(ped)
        end
    end
end

local function clearAllControls()
    for ped, _ in pairs(activeControlsByPed) do
        releasePedControls(ped)
    end
end

addEvent(APPLY_INTENT_EVENT, true)
addEventHandler(APPLY_INTENT_EVENT, root, function(ped, payload)
    if source ~= resourceRoot then
        return
    end
    if type(payload) ~= "table" then
        return
    end
    applyControlsToPed(ped, payload)
end)

addEvent(CLEAR_INTENT_EVENT, true)
addEventHandler(CLEAR_INTENT_EVENT, root, function(ped)
    if source ~= resourceRoot then
        return
    end
    if not ped then
        return
    end
    releasePedControls(ped)
end)

addEventHandler("onClientElementDestroy", root, function()
    if activeControlsByPed[source] then
        releasePedControls(source)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    releaseTimer = setTimer(processReleaseTick, 120, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(releaseTimer) then
        killTimer(releaseTimer)
    end
    releaseTimer = nil
    clearAllControls()
end)
