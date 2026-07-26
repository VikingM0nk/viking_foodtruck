FoodTruckTemplates = {}

local function truck(id, label, category, opts)
    return {
        id = id,
        label = label,
        category = category,
        enabled = true,
        price = opts.price or 50000,
        description = opts.description or '',
        data = {
            vehicle = opts.vehicle or Config.DefaultVehicle or 'taco',
            platePrefix = opts.platePrefix or 'FOOD',
            livery = opts.livery,
            extras = opts.extras or {},
            blip = opts.blip or {
                enabled = true,
                sprite = Config.DefaultBlip.sprite,
                color = Config.DefaultBlip.color,
                scale = Config.DefaultBlip.scale,
            },
            shopRadius = opts.shopRadius or 3.0,
            windowOffset = opts.windowOffset or { x = 0.0, y = -2.0, z = 0.0 },
            menu = opts.menu or {},
            maxStock = opts.maxStock or Config.MaxStockPerItem,
            startingStock = opts.startingStock or {},
            retrieve = opts.retrieve,
        },
    }
end

FoodTruckTemplates.taco_truck = truck('taco_truck', 'El Camino Tacos', 'mexican', {
    price = 75000,
    description = 'Street tacos and cold drinks from a classic taco truck.',
    vehicle = 'taco',
    platePrefix = 'TACO',
    menu = {
        {
            item = 'taco',
            label = 'Street Taco',
            price = 12,
            cookMs = 6000,
            category = 'food',
            hunger = 25,
            thirst = 0,
            stress = 2,
            ingredients = {
                { item = 'tortilla', count = 1 },
                { item = 'beef', count = 1 },
            },
        },
        {
            item = 'burrito',
            label = 'Beef Burrito',
            price = 18,
            cookMs = 8000,
            category = 'food',
            hunger = 40,
            thirst = 5,
            stress = 3,
            ingredients = {
                { item = 'tortilla', count = 1 },
                { item = 'beef', count = 2 },
                { item = 'rice', count = 1 },
            },
        },
        {
            item = 'water',
            label = 'Bottled Water',
            price = 4,
            cookMs = 1500,
            category = 'drink',
            hunger = 0,
            thirst = 30,
            stress = 1,
            ingredients = {
                { item = 'water', count = 1 },
            },
        },
    },
    startingStock = {
        tortilla = 40,
        beef = 40,
        rice = 20,
        water = 30,
        taco = 0,
        burrito = 0,
    },
})

FoodTruckTemplates.burger_truck = truck('burger_truck', 'Highway Burgers', 'american', {
    price = 85000,
    description = 'Greasy burgers and fries for the late-night crowd.',
    vehicle = 'taco',
    platePrefix = 'BRGR',
    menu = {
        {
            item = 'burger',
            label = 'Classic Burger',
            price = 15,
            cookMs = 7000,
            category = 'food',
            hunger = 35,
            thirst = 0,
            stress = 2,
            ingredients = {
                { item = 'bun', count = 1 },
                { item = 'beef', count = 1 },
            },
        },
        {
            item = 'fries',
            label = 'Fries',
            price = 7,
            cookMs = 5000,
            category = 'food',
            hunger = 15,
            thirst = 0,
            stress = 1,
            ingredients = {
                { item = 'potato', count = 1 },
            },
        },
        {
            item = 'cola',
            label = 'Cola',
            price = 5,
            cookMs = 1500,
            category = 'drink',
            hunger = 0,
            thirst = 25,
            stress = 1,
            ingredients = {
                { item = 'cola', count = 1 },
            },
        },
    },
    startingStock = {
        bun = 40,
        beef = 40,
        potato = 40,
        cola = 30,
        burger = 0,
        fries = 0,
    },
})

FoodTruckTemplates.hotdog_truck = truck('hotdog_truck', 'Corner Dogs', 'american', {
    price = 45000,
    description = 'Quick hotdogs and snacks from a compact van.',
    vehicle = 'pony',
    platePrefix = 'DOGS',
    menu = {
        {
            item = 'hotdog',
            label = 'Hotdog',
            price = 8,
            cookMs = 4000,
            category = 'food',
            hunger = 20,
            thirst = 0,
            stress = 1,
            ingredients = {
                { item = 'bun', count = 1 },
                { item = 'sausage', count = 1 },
            },
        },
        {
            item = 'water',
            label = 'Water',
            price = 3,
            cookMs = 1000,
            category = 'drink',
            hunger = 0,
            thirst = 30,
            stress = 1,
            ingredients = {
                { item = 'water', count = 1 },
            },
        },
    },
    startingStock = {
        bun = 50,
        sausage = 50,
        water = 40,
        hotdog = 0,
    },
})

function FoodTruckTemplates.List()
    local list = {}
    for id, def in pairs(FoodTruckTemplates) do
        if type(def) == 'table' and def.id then
            list[#list + 1] = {
                id = def.id,
                label = def.label,
                category = def.category,
                price = def.price,
                description = def.description,
            }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function FoodTruckTemplates.Get(id)
    for key, def in pairs(FoodTruckTemplates) do
        if type(def) == 'table' and def.id == id then
            return def
        end
    end
    return nil
end

function FoodTruckTemplates.GetAll()
    local all = {}
    for _, def in pairs(FoodTruckTemplates) do
        if type(def) == 'table' and def.id then
            all[#all + 1] = def
        end
    end
    return all
end
