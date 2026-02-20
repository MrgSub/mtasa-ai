Use AI in your MTA:SA resources and run multi-agent pedestrian simulations.

The resource supports OpenAI, Anthropic, and Groq models for text and JSON generation. It now includes a scalable LLM pedestrian simulation loop that can run from a few peds to large crowds with bounded request concurrency and fallback movement.

## AI exports

```lua
init(config)
generateText(prompt, system)
generateObject(prompt, system)
getProviders()
getModels(provider)
getConfig()
```

## Ped simulation exports

```lua
startPedSimulation(config)
stopPedSimulation()
spawnPedSimulation(count, spawnOptions)
despawnPedSimulation()
getPedSimulationStats()
getPedSimulationConfig()
```

## Simulation architecture

- Server manages ped lifecycle, LLM decision scheduling, queueing, and stats.
- Client applies ped controls with MTA ped control APIs for streamed peds:
  - `setPedControlState`
  - `setPedAnalogControlState`
- Server uses ped setup APIs for entities and movement style:
  - `createPed`
  - `setPedWalkingStyle`

This keeps each ped independently LLM-driven while respecting MTA control sync behavior.

## Minimal start config (2-3 peds)

```lua
AI.init({
    api_key = "your_api_key",
    provider = "groq",
    model = "llama3-8b-8192",
    temperature = 0.4,
    max_tokens = 110
})

PedSimulation.start({
    pedCount = 3,
    bounds = { minX = -40, maxX = 40, minY = -40, maxY = 40, z = 5 },
    decisionIntervalMs = 3000,
    maxConcurrentRequests = 2,
    maxQueueSize = 300,
    nearbyRadius = 22,
    interactionRadius = 4,
    useAnalogControls = true,
    debug = true
})
```

## Scale config (100+ peds)

```lua
PedSimulation.start({
    pedCount = 120,
    bounds = { minX = -180, maxX = 180, minY = -180, maxY = 180, z = 5 },
    decisionIntervalMs = 6500,
    schedulerTickMs = 400,
    movementTickMs = 220,
    controlUpdateMs = 260,
    maxConcurrentRequests = 4,
    maxQueueSize = 1000,
    nearbyRadius = 20,
    maxNearbyPedsInPrompt = 4,
    fallbackDecisionIntervalMs = 9000,
    useAnalogControls = true,
    debug = false
})
```

## Runtime notes

- Each ped has isolated state: intent, cooldowns, failure backoff, and memory summary.
- LLM decision failures automatically trigger fallback movement.
- Queue depth and in-flight request limits prevent overload spikes.
- Use `getPedSimulationStats()` to observe throughput and fallbacks while tuning.

## Demo commands

The included demo script starts the simulation on resource start and provides:

- `/pedsim_start`
- `/pedsim_stop`
- `/pedsim_spawn <count>`
- `/pedsim_stats`
