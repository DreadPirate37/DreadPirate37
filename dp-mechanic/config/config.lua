Config = {}

-- ==========================================================================
--  OGÓLNE
-- ==========================================================================
Config.Debug = false                 -- /dpm_pos, /dpm_veh, dodatkowe logi
Config.Framework = 'auto'            -- 'auto' | 'esx' | 'qb' | 'qbx' | 'standalone'
Config.UseTarget = true              -- ox_target / qb-target jeśli uruchomione, inaczej [E]
Config.Currency = '$'
Config.AdminAce = 'dpmechanic.admin' -- ace do komend administracyjnych (/dpm_setboss)
Config.RequireDuty = true            -- praca przy autach (zlecenia, szafki, podnośniki) tylko na służbie
Config.ProjectForEveryone = true     -- stanowisko projektowe dostępne też dla mechaników

-- Tablet
Config.Tablet = {
    command = 'mechtablet',
    key = 'F6',                      -- domyślny klawisz (gracz może zmienić w ustawieniach GTA)
    item = nil,                      -- np. 'mechanic_tablet' – wtedy tablet otwiera też przedmiot
    anim = true,                     -- animacja trzymania tabletu + prop
    autoHide = true,                 -- chowanie tabletu po wyjechaniu myszką poza niego
    hideDelay = 350,                 -- ms zanim tablet zacznie się chować
}

-- ==========================================================================
--  TRYBY ROZGRYWKI  (wszystko co „ciężkie” da się wyłączyć)
-- ==========================================================================
Config.Assembly = {
    enabled = true,     -- true  = każda część montowana osobno: szafka → nosisz część → poświata → śruby i grzechotka
                        -- false = prostsza alternatywa: pasek postępu + animacja przy aucie
    requireStock = true,-- części muszą być na stanie magazynu warsztatu (szafki)
    requireLifts = true,-- części podwoziowe wymagają auta na podnośniku (rampa / ramiona)
    boltsMin = 2, boltsMax = 8,
    strokeGain = 0.14,  -- ile postępu daje jeden pełny „ruch” grzechotką (mniej = więcej ruchów)
    simpleTime = 6500,  -- ms paska postępu w trybie prostym (bazowo, skalowane robocizną)
}

Config.Tires = {
    minigames = true,   -- true = realistyczna montażownica + wyważarka; false = paski postępu
    allWheels = true,   -- pełna procedura dla każdego koła; false = pełna tylko dla 1., reszta szybka
    requireLift = 'arms', -- wymagany typ podnośnika do zdejmowania kół (nil = bez podnośnika)
    lugNuts = 5,
    lugTorque = 120,    -- Nm – moment dokręcania kół (wyświetlany na kluczu)
    targetPressure = 2.3, -- bar – ciśnienie docelowe
    pressureTolerance = 0.1,
    maxResidual = 5,    -- g – tyle niewyważenia wyważarka uznaje za „0”
    randomImbalance = { 15, 70 }, -- g – losowe niewyważenie nowej opony (na płaszczyznę)
}

-- ==========================================================================
--  FAKTURY / PŁATNOŚCI
-- ==========================================================================
Config.Invoice = {
    vat = 0.23,                -- podatek doliczany do faktury (0 = brak)
    laborRate = 150,           -- stawka za roboczogodzinę
    mechanicCut = 0.12,        -- % dla mechanika wystawiającego (reszta na konto warsztatu)
    maxCustomLines = 10,
    maxCustomAmount = 250000,
    targetRadius = 8.0,        -- zasięg wyboru klienta (strzałki nad graczami)
    pinAbove = 500,            -- powyżej tej kwoty karta wymaga PIN-u
    terminalTimeout = 120,     -- s na opłacenie
    allowSelf = false,         -- czy można wystawić fakturę samemu sobie (testy)
}

-- ==========================================================================
--  WYPŁATY / ZMIANY
-- ==========================================================================
Config.Salary = {
    enabled = true,
    interval = 15,             -- min – co ile wypłata dla pracowników na służbie
    fromBusiness = true,       -- wypłaty z konta warsztatu (false = „z powietrza”)
    account = 'bank',
}

-- ==========================================================================
--  ZAOPATRZENIE (magazyn)
-- ==========================================================================
Config.Supplier = {
    deliveryTime = 60,         -- s – dostawa zamówienia z hurtowni
    wholesale = 0.55,          -- cena hurtowa = cena detaliczna * mnożnik
    startStock = 3,            -- ile sztuk każdej pozycji na start nowego warsztatu
}

-- ==========================================================================
--  RANGI (domyślne dla nowego warsztatu – potem edytowalne w tablecie)
-- ==========================================================================
Config.Permissions = {
    { id = 'orders',     label = 'Zlecenia – obsługa' },
    { id = 'orders_all', label = 'Zlecenia – zarządzanie (anulowanie, przypisywanie)' },
    { id = 'invoice',    label = 'Wystawianie faktur' },
    { id = 'projects',   label = 'Projekty klientów' },
    { id = 'stock',      label = 'Magazyn – pobieranie części' },
    { id = 'stock_buy',  label = 'Magazyn – zamawianie w hurtowni' },
    { id = 'dyno',       label = 'Hamownia' },
    { id = 'employees',  label = 'Pracownicy – zatrudnianie / zwalnianie' },
    { id = 'ranks',      label = 'Edycja rang' },
    { id = 'bank',       label = 'Konto warsztatu – podgląd' },
    { id = 'bank_manage',label = 'Konto warsztatu – wpłaty / wypłaty' },
    { id = 'settings',   label = 'Ustawienia warsztatu' },
}

Config.DefaultRanks = {
    { level = 0, label = 'Praktykant',   salary = 150, perms = { 'orders', 'stock' } },
    { level = 1, label = 'Mechanik',     salary = 250, perms = { 'orders', 'stock', 'invoice', 'projects', 'dyno' } },
    { level = 2, label = 'Starszy mechanik', salary = 350, perms = { 'orders', 'orders_all', 'stock', 'stock_buy', 'invoice', 'projects', 'dyno', 'bank' } },
    { level = 3, label = 'Kierownik',    salary = 450, perms = { 'orders', 'orders_all', 'stock', 'stock_buy', 'invoice', 'projects', 'dyno', 'bank', 'bank_manage', 'employees' } },
    { level = 4, label = 'Właściciel',   salary = 0,   perms = { '*' } },
}

-- ==========================================================================
--  WARSZTATY
--  Każdy warsztat ma własne konto, pracowników, rangi, magazyn i stanowiska.
--  Współrzędne poniżej to przykład (okolice Benny's) – dopasuj do swojego MLO.
--  Z Config.Debug = true komenda /dpm_pos kopiuje pozycję do konsoli F8.
-- ==========================================================================
Config.Workshops = {
    dp = {
        label = 'DP Garage',
        job = 'mechanic',                 -- praca frameworka (auto-import pracowników z tą pracą)
        syncJob = true,                   -- zatrudnianie/awans ustawia też pracę we frameworku
        blip = { coords = vec3(-205.6, -1310.4, 31.3), sprite = 446, color = 47, scale = 0.85 },
        zone = { center = vec3(-205.6, -1318.0, 31.0), radius = 45.0 },

        duty = vec3(-197.1, -1319.1, 31.1),

        -- szafki z częściami – kategorie: body, engine, perf, wheels, wear, nitro, swap, paint, all
        cabinets = {
            { label = 'Szafka – nadwozie',   coords = vec4(-199.0, -1330.9, 31.1, 90.0),  categories = { 'body' } },
            { label = 'Szafka – silnik i osiągi', coords = vec4(-199.0, -1327.0, 31.1, 90.0), categories = { 'engine', 'perf', 'swap', 'nitro' } },
            { label = 'Regał – eksploatacja', coords = vec4(-199.0, -1323.0, 31.1, 90.0), categories = { 'wear', 'paint' } },
            { label = 'Regał opon i felg',   coords = vec4(-213.8, -1335.0, 31.1, 180.0), categories = { 'wheels' } },
        },

        -- podnośniki: 'ramp' (najazdowy, auto stoi na kołach – praca od spodu)
        --             'arms' (dwukolumnowy na ramionach, auto na progach – koła wiszą)
        lifts = {
            { type = 'ramp', coords = vec4(-222.6, -1324.4, 30.9, 270.0), maxHeight = 1.85, panel = vec3(-222.8, -1320.6, 31.0) },
            { type = 'arms', coords = vec4(-222.6, -1332.6, 30.9, 270.0), maxHeight = 1.60, panel = vec3(-222.8, -1328.8, 31.0) },
        },

        tireChanger = vec4(-213.9, -1330.9, 30.9, 180.0),
        balancer    = vec4(-210.9, -1330.9, 30.9, 180.0),

        dyno = { coords = vec4(-210.5, -1316.0, 30.9, 180.0), radius = 3.0 },

        -- stanowisko projektowe (dla klientów bez pracy mechanika)
        projectStation = { coords = vec4(-194.5, -1300.8, 31.3, 270.0), radius = 3.5 },

        -- stanowisko swapów (silnik, napęd, hamulce, skrzynia, nitro)
        swapStation = { coords = vec4(-215.0, -1316.0, 30.9, 180.0), radius = 3.5 },

        -- kabina lakiernicza (lakier tylko tutaj; nil = wszędzie w strefie)
        paintBooth = nil,

        -- dostawa z hurtowni – gdzie pojawia się paleta (tylko efekt)
        delivery = vec4(-190.2, -1296.9, 31.3, 0.0),
    },
}

-- ==========================================================================
--  KLAWISZE (RegisterKeyMapping – gracz może zmienić w ustawieniach)
-- ==========================================================================
Config.Keys = {
    nitroArm   = 'N',        -- uzbrojenie systemu N2O
    nitroFire  = 'LSHIFT',   -- podanie N2O (trzymaj)
    nitroPurge = 'B',        -- przedmuch (purge)
    nitroShot  = 'PAGEUP',   -- zmiana dyszy (shot)
    liftUp     = 'UP',
    liftDown   = 'DOWN',
}
