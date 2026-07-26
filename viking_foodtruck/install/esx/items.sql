-- viking_foodtruck — ESX items
-- Import into your database (oxmysql / HeidiSQL / phpMyAdmin)
-- Copy PNGs from ../images/ into your inventory images folder
--   (esx_inventoryhud/html/img/items/ OR ox_inventory/web/images/ if using ox)

INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('taco', 'Street Taco', 1, 0, 1),
    ('burrito', 'Beef Burrito', 1, 0, 1),
    ('burger', 'Classic Burger', 1, 0, 1),
    ('fries', 'Fries', 1, 0, 1),
    ('hotdog', 'Hotdog', 1, 0, 1),
    ('water', 'Water', 1, 0, 1),
    ('cola', 'Cola', 1, 0, 1),
    ('tortilla', 'Tortilla', 1, 0, 1),
    ('beef', 'Beef', 1, 0, 1),
    ('rice', 'Rice', 1, 0, 1),
    ('bun', 'Bun', 1, 0, 1),
    ('potato', 'Potato', 1, 0, 1),
    ('sausage', 'Sausage', 1, 0, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
