-- ==========================================================================
--  dp-mechanic – baza danych (oxmysql)
--  Tworzy brakujące tabele przy starcie zasobu. Pozostałe moduły czekają na
--  gotowość przez DB.Await() (w wątku).
--  Uwaga: kolumny nie mogą nazywać się `rank`, `lines`, `count` (słowa zastrzeżone).
-- ==========================================================================
DB = { ready = false, failed = false }

local OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'

local TABLES = {
    { name = 'dpm_workshops', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_workshops` (
    `id` VARCHAR(32) NOT NULL,
    `balance` BIGINT NOT NULL DEFAULT 0,
    `settings` LONGTEXT NULL,
    PRIMARY KEY (`id`)
) ]] .. OPTS },

    { name = 'dpm_transactions', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_transactions` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(32) NOT NULL,
    `amount` BIGINT NOT NULL DEFAULT 0,
    `balance` BIGINT NOT NULL DEFAULT 0,
    `type` VARCHAR(24) NOT NULL DEFAULT '',
    `label` VARCHAR(128) NOT NULL DEFAULT '',
    `actor` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `idx_workshop` (`workshop`)
) ]] .. OPTS },

    { name = 'dpm_ranks', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_ranks` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(32) NOT NULL,
    `level` INT NOT NULL DEFAULT 0,
    `label` VARCHAR(48) NOT NULL DEFAULT '',
    `salary` INT NOT NULL DEFAULT 0,
    `perms` LONGTEXT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_workshop` (`workshop`)
) ]] .. OPTS },

    { name = 'dpm_employees', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_employees` (
    `workshop` VARCHAR(32) NOT NULL,
    `identifier` VARCHAR(64) NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `rank_id` INT NOT NULL DEFAULT 0,
    `hired_at` INT NOT NULL DEFAULT 0,
    `minutes` INT NOT NULL DEFAULT 0,
    `earned` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`workshop`, `identifier`),
    INDEX `idx_identifier` (`identifier`)
) ]] .. OPTS },

    { name = 'dpm_stock', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_stock` (
    `workshop` VARCHAR(32) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `qty` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`workshop`, `item`)
) ]] .. OPTS },

    { name = 'dpm_vehicles', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_vehicles` (
    `plate` VARCHAR(16) NOT NULL,
    `model` VARCHAR(64) NULL DEFAULT NULL,
    `data` LONGTEXT NULL,
    `updated_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`plate`)
) ]] .. OPTS },

    { name = 'dpm_orders', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_orders` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(32) NOT NULL,
    `plate` VARCHAR(16) NOT NULL DEFAULT '',
    `model` VARCHAR(64) NULL DEFAULT NULL,
    `vlabel` VARCHAR(64) NULL DEFAULT NULL,
    `customer` VARCHAR(64) NULL DEFAULT NULL,
    `customer_name` VARCHAR(64) NULL DEFAULT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'open',
    `source` VARCHAR(16) NOT NULL DEFAULT 'mechanic',
    `items` LONGTEXT NULL,
    `notes` TEXT NULL,
    `assigned` VARCHAR(64) NULL DEFAULT NULL,
    `assigned_name` VARCHAR(64) NULL DEFAULT NULL,
    `created_by` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` INT NOT NULL DEFAULT 0,
    `updated_at` INT NOT NULL DEFAULT 0,
    `project_id` INT NULL DEFAULT NULL,
    `invoice_id` INT NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_workshop` (`workshop`),
    INDEX `idx_plate` (`plate`),
    INDEX `idx_ws_status` (`workshop`, `status`),
    INDEX `idx_ws_created` (`workshop`, `created_at`)
) ]] .. OPTS },

    { name = 'dpm_projects', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_projects` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `workshop` VARCHAR(32) NOT NULL,
    `owner` VARCHAR(64) NOT NULL DEFAULT '',
    `owner_name` VARCHAR(64) NULL DEFAULT NULL,
    `plate` VARCHAR(16) NOT NULL DEFAULT '',
    `model` VARCHAR(64) NULL DEFAULT NULL,
    `vlabel` VARCHAR(64) NULL DEFAULT NULL,
    `label` VARCHAR(64) NULL DEFAULT NULL,
    `items` LONGTEXT NULL,
    `total` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'new',
    `created_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `idx_workshop` (`workshop`),
    INDEX `idx_owner` (`owner`)
) ]] .. OPTS },

    { name = 'dpm_invoices', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_invoices` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `number` VARCHAR(32) NOT NULL DEFAULT '',
    `workshop` VARCHAR(32) NOT NULL,
    `order_id` INT NULL DEFAULT NULL,
    `plate` VARCHAR(16) NULL DEFAULT NULL,
    `vlabel` VARCHAR(64) NULL DEFAULT NULL,
    `customer` VARCHAR(64) NULL DEFAULT NULL,
    `customer_name` VARCHAR(64) NULL DEFAULT NULL,
    `issuer` VARCHAR(64) NULL DEFAULT NULL,
    `issuer_name` VARCHAR(64) NULL DEFAULT NULL,
    `lines_json` LONGTEXT NULL,
    `subtotal` INT NOT NULL DEFAULT 0,
    `discount` INT NOT NULL DEFAULT 0,
    `tax` INT NOT NULL DEFAULT 0,
    `total` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'unpaid',
    `method` VARCHAR(8) NULL DEFAULT NULL,
    `created_at` INT NOT NULL DEFAULT 0,
    `paid_at` INT NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_workshop` (`workshop`),
    INDEX `idx_ws_paid` (`workshop`, `status`, `paid_at`)
) ]] .. OPTS },

    { name = 'dpm_history', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_history` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `workshop` VARCHAR(32) NULL DEFAULT NULL,
    `kind` VARCHAR(16) NOT NULL DEFAULT '',
    `label` VARCHAR(160) NOT NULL DEFAULT '',
    `km` INT NOT NULL DEFAULT 0,
    `mechanic` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `idx_plate` (`plate`)
) ]] .. OPTS },

    { name = 'dpm_dyno', sql = [[
CREATE TABLE IF NOT EXISTS `dpm_dyno` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `workshop` VARCHAR(32) NULL DEFAULT NULL,
    `model` VARCHAR(64) NULL DEFAULT NULL,
    `vlabel` VARCHAR(64) NULL DEFAULT NULL,
    `result` LONGTEXT NULL,
    `mechanic` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `idx_plate` (`plate`)
) ]] .. OPTS },
}

-- --------------------------------------------------------------------------
--  Inicjalizacja
-- --------------------------------------------------------------------------
local initializing = false

function DB.Init()
    if DB.ready then return true end
    if initializing then return DB.Await() end
    initializing = true
    DB.failed = false

    -- czekamy na uruchomienie oxmysql
    local limit = GetGameTimer() + 60000
    while GetResourceState('oxmysql') ~= 'started' do
        if GetGameTimer() > limit then
            DPM.Error('oxmysql nie jest uruchomiony – dodaj „ensure oxmysql” przed dp-mechanic w server.cfg')
            DB.failed, initializing = true, false
            return false
        end
        Wait(250)
    end

    -- test połączenia (oxmysql łączy się asynchronicznie)
    local connected, lastErr = false, nil
    for _ = 1, 20 do
        local ok, err = pcall(MySQL.scalar.await, 'SELECT 1')
        if ok then connected = true break end
        lastErr = err
        Wait(1500)
    end
    if not connected then
        DPM.Error('brak połączenia z bazą danych: ' .. tostring(lastErr))
        DB.failed, initializing = true, false
        return false
    end

    local okAll = true
    for _, t in ipairs(TABLES) do
        local ok, err = pcall(MySQL.query.await, t.sql)
        if not ok then
            okAll = false
            DPM.Error(('nie udało się utworzyć tabeli %s: %s'):format(t.name, tostring(err)))
        end
    end

    initializing = false
    if not okAll then
        DB.failed = true
        DPM.Error('schemat bazy danych niekompletny – sprawdź uprawnienia użytkownika MySQL (CREATE, INDEX)')
        return false
    end
    DB.ready = true
    DPM.Debug(('baza danych gotowa (%d tabel)'):format(#TABLES))
    TriggerEvent('dp-mechanic:dbReady')
    return true
end

-- czeka (w wątku), aż baza będzie gotowa; zwraca true/false (błąd lub przekroczony czas)
function DB.Await(timeout)
    local limit = timeout and (GetGameTimer() + timeout) or nil
    while not DB.ready and not DB.failed do
        if limit and GetGameTimer() > limit then break end
        Wait(100)
    end
    return DB.ready
end

-- --------------------------------------------------------------------------
--  Pomocnicze
-- --------------------------------------------------------------------------
function DB.Json(v)
    local ok, s = pcall(json.encode, v)
    return ok and s or 'null'
end

function DB.Decode(s, default)
    if type(s) ~= 'string' or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return default
end

-- zapytanie z pcall: wynik lub nil (+ false przy błędzie SQL)
function DB.Safe(kind, query, params)
    local fn = MySQL[kind]
    if not fn then return nil, false end
    local ok, res = pcall(fn.await, query, params)
    if not ok then
        DPM.Error(('SQL: %s | %s'):format(tostring(res), query:gsub('%s+', ' '):sub(1, 120)))
        return nil, false
    end
    return res, true
end

CreateThread(function()
    DB.Init()
end)
