addEventHandler("onResourceStart", resourceRoot,
    function()
        AI.init({
            api_key = "",
            provider = "groq",
            model = "llama3-8b-8192",
            temperature = 0.7,
            max_tokens = 150
        })
        createPed(0, 0, 0, 5)
        local marker = createMarker(0, 0, 2, "cylinder", 5, 10, 244, 23, 10, root)
        local function handleMarkerHit(hitElement)
            local elementType = getElementType(hitElement)
            if elementType ~= "player" then return end
        	local playerName = getPlayerName(hitElement)
            outputDebugString("Player "..playerName.." hit marker")
            AI.generateText(playerName.." got close to you, say something funny, and out of pocket. Limit is 255 characters. Your name is Pedro. Don't use quotes.", "You are a random pedestrian living in San Andreas, grand theft auto.")(
                function(result, error)
                    if error then
                        outputDebugString("Error: " .. error)
                        return
                    end
                    if (result:len() >= 254) then
                        result = result:sub(1, 254) .. "..."
                        return
                    end
                    outputChatBox("[Pedro]: "..result, hitElement, 255, 255, 255)
                end
            )
        end
        addEventHandler("onMarkerHit", marker, handleMarkerHit)
    end
)

-- Basic init code
--AI.init({
--    api_key = "",
--    provider = "groq",
--    model = "llama3-8b-8192",
--    temperature = 0.7,
--    max_tokens = 150
--})
--AI.init({
--    api_key = "",
--    provider = "anthropic",
--    model = "claude-2.1",
--    temperature = 0.7,
--    max_tokens = 150
--})
--AI.init({
--    api_key = "",
--    provider = "openai",
--    model = "gpt-3.5-turbo",
--    temperature = 0.7,
--    max_tokens = 150,
--})

--Basic text generation
--AI.generateText("Hi who are you?", "You are a random pedestrian living in San Andreas, California. You have 3 kids.")(
--    function(result, error)
--        if error then
--            outputDebugString("Error: " .. error)
--            return
--        end
--        outputDebugString("test"..result)
--    end
--)
--
---- Streaming text generation
--AI.generateTextStream("Tell me a story")(
--    function(chunk)
--        -- Handle each chunk
--        outputChatBox(chunk)
--    end,
--    function(fullText)
--        -- Handle completion
--        outputDebugString("Story complete!")
--    end,
--    function(error)
--        -- Handle error
--        outputDebugString("Error: " .. error)
--    end
--)
--
---- Generate JSON object (untested)
--AI.generateObject("Create a player configuration with name, level, and inventory")(
--    function(result, error)
--        if error then
--            outputDebugString("Error: " .. error)
--            return
--        end
--        -- Result is a Lua table
--        outputDebugString(inspect(result))
--    end
--)

---- Get available providers
--local providers = AI.getProviders()
--outputDebugString("Available providers: " .. table.concat(providers, ", "))
--
---- Get available models for a provider
--local models = AI.getModels("groq")
--outputDebugString("Available Groq models: " .. table.concat(models, ", "))
