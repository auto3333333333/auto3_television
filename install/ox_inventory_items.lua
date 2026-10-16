-- Add this item to ox_inventory's data/items.lua
-- (the item name must match Config.Boombox.Item in config.lua)

['boombox'] = {
    label = 'Boombox',
    weight = 3000,
    stack = false,
    close = true,
    consume = 0,        -- rensyu_television handles consuming it (1 item is used when placed, returned when picked up)
    description = 'Place it on the ground and play music',
    client = {
        event = 'rensyu_television:useBoombox',
    },
},

-- Put an image at ox_inventory/web/images/boombox.png to give the item an icon.
