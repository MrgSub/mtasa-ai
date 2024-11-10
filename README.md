​
Use AI in your MTA:SA resources.

Powered by providers like OpenAI, Anthropic & Groq. You can now bake Artificial Intelligence into your resources, gamemodes and systems.

This resource exports the below functions:

```lua
init(config)
generateText(prompt,system)
generateObject(prompt, system)
getProviders()
getModels(provider)
getConfig()
```
Example usage:

The below code initializes the AI agent (add your API key from the provider) and creates a ped and a marker. when the player hits the marker, the ped says something funny.

```lua
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
```

Download: 

`https://community.multitheftauto.com/index.php?p=resources&s=details&id=18946`

Roadmap:

- Support conversation history

- Support streaming

- 
