-- Every SQL statement this resource runs lives in this file.
-- The tables are created automatically the first time the resource starts, so there is nothing to import by hand.
-- All values are passed as parameters (?), never joined into the query text.

local db = {}

-- Table layout. Each statement only runs when its table is missing.
db.schema = {
    -- One row per crafting bench placed in the world.
    -- `type` is the bench type key, `gangs` is a JSON list of gang names allowed to use it (empty = anyone).
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_tables` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `heading` DOUBLE NOT NULL,
            `type` VARCHAR(50) NOT NULL DEFAULT '',
            `gangs` LONGTEXT NULL,
            `placed_by` VARCHAR(50) DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],

    -- One row per bench type. `categories` is JSON holding the categories and every recipe inside them.
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_types` (
            `name` VARCHAR(50) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `categories` LONGTEXT NOT NULL,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],

    -- Craft cooldowns per character and item. Times are unix seconds. `ends_at` = 0 means no cooldown is running yet.
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_cooldowns` (
            `citizenid` VARCHAR(50) NOT NULL,
            `item` VARCHAR(100) NOT NULL,
            `crafted` INT UNSIGNED NOT NULL,
            `started_at` INT UNSIGNED NOT NULL,
            `ends_at` INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`, `item`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],

    -- Queued crafts. `ingredients` is JSON of what was taken, so a cancel can give it back.
    -- Removing a bench removes its queue rows with it.
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_queue` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `table_id` INT UNSIGNED NOT NULL,
            `item` VARCHAR(100) NOT NULL,
            `count` INT UNSIGNED NOT NULL,
            `amount` INT UNSIGNED NOT NULL,
            `duration` INT UNSIGNED NOT NULL,
            `ready_at` INT UNSIGNED NOT NULL,
            `ingredients` LONGTEXT NOT NULL,
            `cooldown_start` INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `table_id` (`table_id`),
            CONSTRAINT `whey_crafting_queue_table` FOREIGN KEY (`table_id`)
                REFERENCES `whey_crafting_tables` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],

    -- Decorative props placed from the tablet.
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_props` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `model` VARCHAR(64) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `heading` DOUBLE NOT NULL,
            `placed_by` VARCHAR(50) DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}

db.queries = {
    -- Asked before anything is moved, to make sure the database is answering.
    ping = 'SELECT 1',

    -- Benches
    loadTables = 'SELECT `id`, `x`, `y`, `z`, `heading`, `type`, `gangs` FROM `whey_crafting_tables` ORDER BY `id`',
    insertTable = [[
        INSERT INTO `whey_crafting_tables` (`x`, `y`, `z`, `heading`, `type`, `gangs`, `placed_by`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]],
    updateTable = 'UPDATE `whey_crafting_tables` SET `type` = ?, `gangs` = ? WHERE `id` = ?',
    deleteTable = 'DELETE FROM `whey_crafting_tables` WHERE `id` = ?',
    deleteTablesOfType = 'DELETE FROM `whey_crafting_tables` WHERE `type` = ?',

    -- Bench types and their recipes
    loadTypes = 'SELECT `name`, `label`, `categories` FROM `whey_crafting_types` ORDER BY `name`',
    saveType = [[
        INSERT INTO `whey_crafting_types` (`name`, `label`, `categories`) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `categories` = VALUES(`categories`)
    ]],
    deleteType = 'DELETE FROM `whey_crafting_types` WHERE `name` = ?',

    -- Cooldowns
    -- Clears finished cooldowns and counts that can no longer matter when the resource starts.
    pruneCooldowns = [[
        DELETE FROM `whey_crafting_cooldowns`
        WHERE (`ends_at` > 0 AND `ends_at` <= ?) OR (`ends_at` = 0 AND `started_at` <= ?)
    ]],
    loadCooldowns = [[
        SELECT `citizenid`, `item`, `crafted`, `started_at`, `ends_at`
        FROM `whey_crafting_cooldowns`
        ORDER BY `citizenid`, `item`
        LIMIT ?
    ]],
    saveCooldown = [[
        INSERT INTO `whey_crafting_cooldowns` (`citizenid`, `item`, `crafted`, `started_at`, `ends_at`)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `crafted` = VALUES(`crafted`),
            `started_at` = VALUES(`started_at`),
            `ends_at` = VALUES(`ends_at`)
    ]],

    -- Queue
    loadQueue = [[
        SELECT `id`, `citizenid`, `table_id`, `item`, `count`, `amount`, `duration`, `ready_at`, `ingredients`,
            `cooldown_start`
        FROM `whey_crafting_queue`
        ORDER BY `id`
        LIMIT ?
    ]],
    insertOrder = [[
        INSERT INTO `whey_crafting_queue`
            (`citizenid`, `table_id`, `item`, `count`, `amount`, `duration`, `ready_at`, `ingredients`, `cooldown_start`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    -- Used when a player could only carry part of a finished order.
    setOrderCount = 'UPDATE `whey_crafting_queue` SET `count` = ? WHERE `id` = ?',
    deleteOrder = 'DELETE FROM `whey_crafting_queue` WHERE `id` = ?',
    -- After a cancel, the orders behind it finish that much sooner.
    shiftOrders = [[
        UPDATE `whey_crafting_queue` SET `ready_at` = `ready_at` - ?
        WHERE `citizenid` = ? AND `table_id` = ? AND `id` > ?
    ]],

    -- Props
    loadProps = 'SELECT `id`, `model`, `x`, `y`, `z`, `heading` FROM `whey_crafting_props` ORDER BY `id` LIMIT ?',
    insertProp = [[
        INSERT INTO `whey_crafting_props` (`model`, `x`, `y`, `z`, `heading`, `placed_by`)
        VALUES (?, ?, ?, ?, ?, ?)
    ]],
    deleteProp = 'DELETE FROM `whey_crafting_props` WHERE `id` = ?',
}

function db.install()
    for i = 1, #db.schema do
        MySQL.query.await(db.schema[i])
    end
end

return db
