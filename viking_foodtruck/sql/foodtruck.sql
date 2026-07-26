CREATE TABLE IF NOT EXISTS `viking_foodtrucks` (
    `id` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `category` VARCHAR(32) NOT NULL DEFAULT 'custom',
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `price` INT NOT NULL DEFAULT 0,
    `data` LONGTEXT NOT NULL,
    `owner_id` VARCHAR(64) DEFAULT NULL,
    `created_by` VARCHAR(64) DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_owner` (`owner_id`),
    KEY `idx_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `viking_foodtruck_accounts` (
    `truck_id` VARCHAR(64) NOT NULL,
    `balance` INT NOT NULL DEFAULT 0,
    `employees` LONGTEXT NOT NULL,
    `stock` LONGTEXT NOT NULL,
    PRIMARY KEY (`truck_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `viking_foodtruck_wallets` (
    `owner_id` VARCHAR(64) NOT NULL,
    `cash` INT NOT NULL DEFAULT 0,
    `bank` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `viking_foodtruck_bills` (
    `id` VARCHAR(64) NOT NULL,
    `truck_id` VARCHAR(64) NOT NULL DEFAULT '',
    `from_id` VARCHAR(64) NOT NULL,
    `to_id` VARCHAR(64) NOT NULL,
    `from_src` INT DEFAULT NULL,
    `to_src` INT DEFAULT NULL,
    `amount` INT NOT NULL DEFAULT 0,
    `reason` VARCHAR(128) NOT NULL DEFAULT '',
    `status` VARCHAR(16) NOT NULL DEFAULT 'unpaid',
    `paid_from` VARCHAR(16) DEFAULT NULL,
    `meta` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `paid_at` TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_to_status` (`to_id`, `status`),
    KEY `idx_truck_status` (`truck_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
