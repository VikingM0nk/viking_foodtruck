--[[
    viking_foodtruck — ox_inventory items
    Merge into: ox_inventory/data/items.lua
    Copy PNGs from ../images/ into: ox_inventory/web/images/

    consume + server.export make hunger/thirst/stress apply via viking_foodtruck
    even when ox_status is not installed.
]]

return {
    ['taco'] = {
        label = 'Street Taco',
        weight = 180,
        stack = true,
        close = true,
        consume = 1,
        description = 'A freshly made street taco from a food truck.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'taco.png',
            status = { hunger = 250000 },
            anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
            prop = { model = `prop_cs_burger_01`, pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
            usetime = 3500,
        },
    },
    ['burrito'] = {
        label = 'Beef Burrito',
        weight = 280,
        stack = true,
        close = true,
        consume = 1,
        description = 'A hearty beef burrito.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'burrito.png',
            status = { hunger = 400000 },
            anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
            usetime = 4500,
        },
    },
    ['burger'] = {
        label = 'Classic Burger',
        weight = 220,
        stack = true,
        close = true,
        consume = 1,
        description = 'A greasy classic burger.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'burger.png',
            status = { hunger = 350000 },
            anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
            prop = { model = `prop_cs_burger_01`, pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) },
            usetime = 4000,
        },
    },
    ['fries'] = {
        label = 'Fries',
        weight = 120,
        stack = true,
        close = true,
        consume = 1,
        description = 'Crispy fries.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'fries.png',
            status = { hunger = 150000 },
            anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
            usetime = 3000,
        },
    },
    ['hotdog'] = {
        label = 'Hotdog',
        weight = 160,
        stack = true,
        close = true,
        consume = 1,
        description = 'A classic hotdog.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'hotdog.png',
            status = { hunger = 200000 },
            anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' },
            usetime = 3000,
        },
    },
    ['water'] = {
        label = 'Water',
        weight = 200,
        stack = true,
        close = true,
        consume = 1,
        description = 'A bottle of water.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'water.png',
            status = { thirst = 300000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            prop = { model = `prop_ld_flow_bottle`, pos = vec3(0.01, 0.01, 0.06), rot = vec3(5.0, 5.0, -180.5) },
            usetime = 2500,
        },
    },
    ['cola'] = {
        label = 'Cola',
        weight = 200,
        stack = true,
        close = true,
        consume = 1,
        description = 'An ice-cold cola.',
        server = { export = 'viking_foodtruck.usedFoodItem' },
        client = {
            image = 'cola.png',
            status = { thirst = 250000 },
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            usetime = 2500,
        },
    },

    -- Ingredients / stock
    ['tortilla'] = {
        label = 'Tortilla',
        weight = 80,
        stack = true,
        close = true,
        description = 'Soft flour tortilla for cooking.',
        client = { image = 'tortilla.png' },
    },
    ['beef'] = {
        label = 'Beef',
        weight = 150,
        stack = true,
        close = true,
        description = 'Raw beef for cooking.',
        client = { image = 'beef.png' },
    },
    ['rice'] = {
        label = 'Rice',
        weight = 100,
        stack = true,
        close = true,
        description = 'Cooked rice portion.',
        client = { image = 'rice.png' },
    },
    ['bun'] = {
        label = 'Bun',
        weight = 70,
        stack = true,
        close = true,
        description = 'A soft bun for burgers or hotdogs.',
        client = { image = 'bun.png' },
    },
    ['potato'] = {
        label = 'Potato',
        weight = 120,
        stack = true,
        close = true,
        description = 'A potato for fries.',
        client = { image = 'potato.png' },
    },
    ['sausage'] = {
        label = 'Sausage',
        weight = 110,
        stack = true,
        close = true,
        description = 'A sausage for hotdogs.',
        client = { image = 'sausage.png' },
    },
}
