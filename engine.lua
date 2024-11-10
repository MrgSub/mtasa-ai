AI = {
    _version = "1.0.0",
}

local PROVIDERS = {
    openai = {
        api_url = "https://api.openai.com/v1/chat/completions",
        models = {
            ["gpt-3.5-turbo"] = true,
            ["gpt-4"] = true
        }
    },
    anthropic = {
        api_url = "https://api.anthropic.com/v1/complete",
        models = {
            ["claude-2.1"] = true,
            ["claude-instant-1"] = true
        }
    },
    groq = {
        api_url = "https://api.groq.com/openai/v1/chat/completions",
        models = {
            ["llama3-8b-8192"] = true,
            ["mixtral-8x7b-32768"] = true,
            ["gemma-7b-it"] = true
        }
    }
}

-- Private utility functions
local function validateConfig(config)
    if not config then error("Config is required") end

    AI._config = {}
    if type(config.temperature) == "number" then
        AI._config.temperature = math.max(0, math.min(1, config.temperature))
    end

    if type(config.max_tokens) == "number" then
        AI._config.max_tokens = math.max(1, config.max_tokens)
    end

    if type(config.model) == "string" then
        local provider = config.provider or AI._config.provider
        if PROVIDERS[provider].models[config.model] then
            AI._config.model = config.model
        else
            error("Invalid model for provider " .. provider)
        end
    end

    if type(config.provider) == "string" then
        if PROVIDERS[config.provider] then
            AI._config.provider = config.provider
        else
            error("Invalid provider. Supported providers: openai, anthropic, groq")
        end
    end

    if config.api_key then
        AI._config.api_key = config.api_key
    end
end

local function makeHttpRequest(endpoint, data, headers, callback)
    fetchRemote(
        endpoint,
        {
            queuePriority = "high",
            connectionAttempts = 3,
            connectTimeout = 5000,
            method = "POST",
            headers = headers,
            postData = string.sub(toJSON(data), 2, -2)
        },
        callback
    )
end

local function prepareRequestData(prompt, system, config)
    local provider = config.provider or AI._config.provider
    local data = {}
    local headers = {
        ["Content-Type"] = "application/json"
    }

    if provider == "openai" then
        headers["Authorization"] = "Bearer " .. AI._config.api_key
        data = {
            model = config.model,
            messages = {
                [1] = {role = "system", content = system or ""},
                [2] = {
                    role = "user",
                    content = prompt
                }
            },
            temperature = config.temperature,
            max_tokens = config.max_tokens,
        }
    elseif provider == "anthropic" then
        local _prompt = "\n\nHuman: " .. prompt .. "\n\nAssistant:"
        if system then
            _prompt = "\n\nSystem: " .. system .. "\n\nHuman: " .. prompt .. "\n\nAssistant:"
        end
        headers["x-api-key"] = AI._config.api_key
        headers["anthropic-version"] = AI._config.anthropic_version
        data = {
            model = config.model,
            prompt = _prompt,
            temperature = config.temperature,
            max_tokens_to_sample = config.max_tokens,
        }
    elseif provider == "groq" then
        headers["Authorization"] = "Bearer " .. AI._config.api_key
        data = {
            model = config.model,
            messages = {
                [1] = {role = "system", content = system or ""},
                [2] = {
                    role = "user",
                    content = prompt
                }
            },
            temperature = config.temperature,
            max_tokens = config.max_tokens,
        }
    end

    if data.messages then
        local cleanMessages = {}
        for _, msg in pairs(data.messages) do
            if msg then
                table.insert(cleanMessages, msg)
            end
        end
        data.messages = cleanMessages
    end

    return data, headers
end

local function parseResponse(responseData, provider)
    local response = fromJSON(responseData)
    if provider == "openai" then
        return response.choices[1].message.content
    elseif provider == "anthropic" then
        return response.completion
    elseif provider == "groq" then
        return response.choices[1].message.content or response.choices[1].text
    end

    return nil
end

-- Public functions
function AI.init(config)
    validateConfig(config)

    local provider = config.provider or AI._config.provider
    if provider == "openai" and not AI._config.api_key then
        error("OpenAI API key required when using OpenAI provider")
    elseif provider == "anthropic" and not AI._config.api_key then
        error("Anthropic API key required when using Anthropic provider")
    elseif provider == "groq" and not AI._config.api_key then
        error("Groq API key required when using Groq provider")
    end

    return AI
end

function AI.generateText(prompt, system)
    if type(prompt) ~= "string" then
        error("Prompt must be a string")
    end

    local localConfig = AI._config
    validateConfig(localConfig)

    return function(callback)
        local requestData, headers = prepareRequestData(prompt, system, localConfig)
        local provider = localConfig.provider

        makeHttpRequest(PROVIDERS[provider].api_url, requestData, headers, function(responseData, responseInfo)
            if responseInfo.success then
                local content = parseResponse(responseData, provider)

                if content then
                    callback(content, nil)
                else
                    callback(nil, "Invalid response format")
                end
            else
                callback(nil, "Request failed: " .. tostring(responseInfo.statusCode))
            end
        end)
    end
end

-- Beta, not fully tested
function AI.generateObject(prompt, system)
    if type(prompt) ~= "string" then
        error("Prompt must be a string")
    end

    local localConfig = AI._config
    validateConfig(localConfig)

    return function(callback)
        local requestData, headers = prepareRequestData(prompt, system, localConfig)
        local provider = localConfig.provider

        makeHttpRequest(PROVIDERS[provider].api_url, requestData, headers, function(responseData, responseInfo)
            if responseInfo.success then
                local jsonStr = parseResponse(responseData, provider)

                if jsonStr then
                    local success, result = pcall(fromJSON, jsonStr)
                    if success then
                        callback(result, nil)
                    else
                        callback(nil, "Failed to parse JSON response")
                    end
                else
                    callback(nil, "Invalid response format")
                end
            else
                callback(nil, "Request failed: " .. tostring(responseInfo.statusCode))
            end
        end)
    end
end

-- Utility functions
function AI.getProviders()
    local providers = {}
    for provider, _ in pairs(PROVIDERS) do
        table.insert(providers, provider)
    end
    return providers
end

function AI.getModels(provider)
    provider = provider or AI._config.provider
    if not PROVIDERS[provider] then
        error("Invalid provider")
    end

    local models = {}
    for model, _ in pairs(PROVIDERS[provider].models) do
        table.insert(models, model)
    end
    return models
end

function AI.getConfig()
    return table.copy(AI._config)
end

return AI
