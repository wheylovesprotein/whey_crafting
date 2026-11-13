-- Every SQL statement this resource runs lives in this file.
-- The tables are created automatically the first time the resource starts, so there is nothing to import by hand.
-- All values are passed as parameters (?), never joined into the query text.

local db = {}

-- Table layout. Each statement only runs when its table is missing.
-- Columns added in later versions are listed in db.columns below, so older installs get them too.
db.schema = {
    -- One row per crafting bench placed in the world.
    -- `type` is the bench type key, `gangs` is a JSON list of gang names allowed to use it (empty = anyone).
    -- `model` is the prop the bench uses, NULL means the first one in config/stations.lua.
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
            `model` VARCHAR(64) DEFAULT NULL,
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
    -- `xp` is the crafting XP still to be paid out when the order is collected.
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
            `xp` INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `table_id` (`table_id`),
            CONSTRAINT `whey_crafting_queue_table` FOREIGN KEY (`table_id`)
                REFERENCES `whey_crafting_tables` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],

    -- Total crafting XP per character. The level is worked out from the XP with the numbers in config/general.lua.
    [[
        CREATE TABLE IF NOT EXISTS `whey_crafting_levels` (
            `citizenid` VARCHAR(50) NOT NULL,
            `xp` INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}

-- Columns added after the first release. Each one is added only when the table does not have it yet.
db.columns = {
    {
        table = 'whey_crafting_queue',
        column = 'xp',
        add = 'ALTER TABLE `whey_crafting_queue` ADD COLUMN `xp` INT UNSIGNED NOT NULL DEFAULT 0',
    },
    {
        table = 'whey_crafting_tables',
        column = 'model',
        add = 'ALTER TABLE `whey_crafting_tables` ADD COLUMN `model` VARCHAR(64) DEFAULT NULL',
    },
}

db.queries = {
    -- Asked before anything is moved, to make sure the database is answering.
    ping = 'SELECT 1',

    -- Used on start to see whether a column from db.columns still has to be added.
    hasColumn = [[
        SELECT COUNT(*) FROM `information_schema`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = ? AND `COLUMN_NAME` = ?
    ]],

    -- Benches
    loadTables = [[
        SELECT `id`, `x`, `y`, `z`, `heading`, `type`, `gangs`, `model` FROM `whey_crafting_tables` ORDER BY `id`
    ]],
    insertTable = [[
        INSERT INTO `whey_crafting_tables` (`x`, `y`, `z`, `heading`, `type`, `gangs`, `placed_by`, `model`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    updateTable = 'UPDATE `whey_crafting_tables` SET `type` = ?, `gangs` = ?, `model` = ? WHERE `id` = ?',
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
            `cooldown_start`, `xp`
        FROM `whey_crafting_queue`
        ORDER BY `id`
        LIMIT ?
    ]],
    insertOrder = [[
        INSERT INTO `whey_crafting_queue`
            (`citizenid`, `table_id`, `item`, `count`, `amount`, `duration`, `ready_at`, `ingredients`,
            `cooldown_start`, `xp`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    -- Used when a player could only carry part of a finished order. The XP for the part they took is paid out.
    setOrderCount = 'UPDATE `whey_crafting_queue` SET `count` = ?, `xp` = ? WHERE `id` = ?',
    deleteOrder = 'DELETE FROM `whey_crafting_queue` WHERE `id` = ?',
    -- After a cancel, the orders behind it finish that much sooner.
    shiftOrders = [[
        UPDATE `whey_crafting_queue` SET `ready_at` = `ready_at` - ?
        WHERE `citizenid` = ? AND `table_id` = ? AND `id` > ?
    ]],

    -- Levels
    loadXp = 'SELECT `xp` FROM `whey_crafting_levels` WHERE `citizenid` = ?',
    saveXp = [[
        INSERT INTO `whey_crafting_levels` (`citizenid`, `xp`) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `xp` = VALUES(`xp`)
    ]],

    -- Character search for the Levels page of the tablet.
    -- `players` and `users` are qbx_core's tables. They are only read here, never changed.
    findCharacter = 'SELECT `citizenid`, `charinfo` FROM `players` WHERE `citizenid` = ?',
    -- By exact citizen ID, or by part of the character's first and last name.
    searchCharacters = [[
        SELECT `citizenid`, `charinfo` FROM `players`
        WHERE `citizenid` = ?
            OR LOWER(CONCAT(
                JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.firstname')), ' ',
                JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.lastname'))
            )) LIKE ?
        ORDER BY `citizenid`
        LIMIT ?
    ]],
    -- Every character of the account with that Discord ID, stored with or without the "discord:" prefix.
    searchDiscord = [[
        SELECT p.`citizenid`, p.`charinfo` FROM `players` p
        JOIN `users` u ON u.`userId` = p.`userId`
        WHERE u.`discord` IN (?, ?)
        ORDER BY p.`citizenid`
        LIMIT ?
    ]],
}

function db.install()
    for i = 1, #db.schema do
        MySQL.query.await(db.schema[i])
    end

    for i = 1, #db.columns do
        local column = db.columns[i]

        if MySQL.scalar.await(db.queries.hasColumn, { column.table, column.column }) == 0 then
            MySQL.query.await(column.add)
        end
    end
end

return db
