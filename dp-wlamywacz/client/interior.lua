-- ==========================================================================
--  Wnętrze: wejście przez fasadę do instancji (DOM-02, DOM-17), punkty interakcji (DOM-23),
--  propy łupu (LUP-05), światła (SKR-07), kryjówki (SKR-10), wyjścia
-- ==========================================================================
local props = {}                   -- [pointId] = entity (łup, sejf)
local shell
local hidden

local function S() return W.session end
local function tplOf(s) return Config.Interiors[s.interior] end
local function worldPos(s, p) return WLM.U.Rel(s.origin, p.pos) end

-- --------------------------------------------------------------------------
--  Akcja w środku: serwer daje token i grę, klient gra, serwer liczy wynik
-- --------------------------------------------------------------------------
function W.InsideAct(pointId, action)
    if W.busy then return end
    local r = W.Call('act:begin', pointId, action)
    if not r or not r.ok then return end
    local res = W.RunGame(r.game)
    if res.aborted and r.game.game == 'progress' then
        W.Callback('act:finish', r.token, { ok = false })
        return
    end
    local fin = W.Callback('act:finish', r.token, { ok = res.ok, broken = res.broken, combo = res.combo, code = res.code })
    if not fin or not fin.ok then W.Notify(fin and fin.msg or L('error'), 'bad') return end
    if fin.found then
        W.Notify(#fin.found > 0 and L('found', table.concat(fin.found, ', ')) or L('found_nothing'), #fin.found > 0 and 'good' or 'info')
        if fin.full then W.Notify(L('bag_full_left'), 'warn') end
    elseif fin.opened == false then
        W.Notify(fin.msg or L('entry_failed'), 'bad')
    elseif fin.msg then
        W.Notify(fin.msg, 'good')
    end
end

-- --------------------------------------------------------------------------
--  Punkty wnętrza
-- --------------------------------------------------------------------------
local function spawnLootProp(s, p)
    local key = s.slots[p.id]
    if not key or s.taken[p.id] then return end
    local def = Config.Loot[key]
    if not def or not def.prop then return end
    local hash = W.LoadModel(def.prop)
    if not hash then return end
    local c = worldPos(s, p)
    local obj = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(obj, p.pos.w or 0.0)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    props[p.id] = obj
end

local function removeProp(id)
    local e = props[id]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    props[id] = nil
end

local function pointOptions(s, p)
    local id = p.id
    if p.type == 'search' then
        local f = Config.Furniture[p.furniture]
        local opts = { {
            label = L('search', f.label), icon = 'fa-solid fa-magnifying-glass',
            canInteract = function() return not S().searched[id] and (not p.locked or S().unlocked[id]) end,
            action = function() W.InsideAct(id, 'search') end,
        } }
        if p.locked then
            opts[#opts + 1] = { label = L('m_unlock'), icon = 'fa-solid fa-key', canInteract = function() return not S().unlocked[id] end, action = function() W.InsideAct(id, 'unlock') end }
            opts[#opts + 1] = { label = L('m_force'), icon = 'fa-solid fa-hammer', canInteract = function() return not S().unlocked[id] end, action = function() W.InsideAct(id, 'force') end }
        end
        return opts
    elseif p.type == 'loot' then
        local key = s.slots[id]
        if not key then return nil end
        return { {
            label = L('take', Config.Loot[key].label), icon = 'fa-solid fa-hand',
            canInteract = function() return not S().taken[id] and not W.carry end,
            action = function() W.InsideAct(id, 'take') end,
        } }
    elseif p.type == 'safe' then
        return { { label = L('safe_open'), icon = 'fa-solid fa-vault', canInteract = function() return not S().searched[id] end, action = function() W.InsideAct(id, 'safe') end } }
    elseif p.type == 'light' then
        return { {
            label = L('light_toggle'), icon = 'fa-solid fa-lightbulb',
            action = function()
                local on = not S().lights[p.room]
                W.Call('house:light', p.room, on)
                SendNUIMessage({ action = 'sound', kind = 'click' })
            end,
        } }
    elseif p.type == 'hide' then
        return { { label = p.label or L('hide'), icon = 'fa-solid fa-user-secret', canInteract = function() return not hidden and not W.carry end, action = function() W.Hide(p) end } }
    elseif p.type == 'alarm' then
        if not s.hasAlarm then return nil end
        return { { label = L('alarm_panel'), icon = 'fa-solid fa-shield-halved', canInteract = function() return S().alarm.stage ~= 'disarmed' end, action = function() W.InsideAct(id, 'keypad') end } }
    elseif p.type == 'dvr' then
        if #s.cameras == 0 then return nil end
        return {
            { label = L('dvr_take'), icon = 'fa-solid fa-hard-drive', canInteract = function() return S().dvr == 'ok' end, action = function() W.InsideAct(id, 'dvr_take') end },
            { label = L('dvr_smash'), icon = 'fa-solid fa-hammer', canInteract = function() return S().dvr == 'ok' end, action = function() W.InsideAct(id, 'dvr_smash') end },
        }
    elseif p.type == 'exit' then
        return { { label = L('exit_' .. p.spawn), icon = 'fa-solid fa-person-running', canInteract = function() return not hidden end, action = function() W.ExitHouse(id) end } }
    end
    return nil
end

local function setupPoints(s)
    for _, p in ipairs(tplOf(s).points) do
        local opts = pointOptions(s, p)
        if opts then W.AddPoint('i:' .. p.id, worldPos(s, p), p.type == 'exit' and 1.4 or 1.0, opts) end
        if p.type == 'loot' then spawnLootProp(s, p) end
    end
end

-- --------------------------------------------------------------------------
--  Kryjówki (SKR-10): chowasz się, a AI domowników cię nie widzi; blisko domownika
--  trzeba wstrzymać oddech (SPACJA), bo inaczej oddech jest słyszalny
-- --------------------------------------------------------------------------
function W.Hide(p)
    if hidden or W.busy then return end
    local r = W.Call('house:hide', p.id, true)
    if not r or not r.ok then return end
    local ped = PlayerPedId()
    local c = worldPos(S(), p)
    hidden = p.id
    W.hidden = true
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, p.pos.w or 0.0)
    FreezeEntityPosition(ped, true)
    if W.LoadDict('amb@world_human_bum_standing@depressed@idle_a') then
        TaskPlayAnim(ped, 'amb@world_human_bum_standing@depressed@idle_a', 'idle_a', 3.0, 3.0, -1, 1, 0, false, false, false)
    end
    W.Hud({ hidden = true })
    CreateThread(function()
        local breath, nextBreath = 8.0, 0
        while hidden do
            local close = W.ResidentNear and W.ResidentNear(3.0)
            if close then
                W.Help(L('hold_breath'))
                if IsControlPressed(0, 22) and breath > 0 then
                    breath = breath - 0.016
                elseif GetGameTimer() > nextBreath then
                    nextBreath = GetGameTimer() + 2000
                    W.EmitNoise(Config.Noise.actions.hidden * 3)
                end
            else
                breath = math.min(8.0, breath + 0.02)
                W.Help(L('hidden_exit'))
            end
            W.Hud({ breath = math.floor(breath / 8.0 * 100) })
            if IsControlJustReleased(0, 38) then break end
            Wait(0)
        end
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
        hidden = nil
        W.hidden = false
        W.Hud({ hidden = false, breath = false })
        W.Callback('house:hide', p.id, false)
    end)
end

-- --------------------------------------------------------------------------
--  Wejście i wyjście
-- --------------------------------------------------------------------------
local function cleanup()
    W.RemovePoints('i:')
    for id in pairs(props) do removeProp(id) end
    if shell and DoesEntityExist(shell) then DeleteEntity(shell) end
    shell = nil
    hidden = nil
    W.hidden = false
    if W.StopAI then W.StopAI() end
    if W.StopSecurity then W.StopSecurity() end
    if W.StopStealth then W.StopStealth() end
    SetArtificialLightsState(false)
    W.session = nil
    W.Hud({ inside = false, alarm = false, room = false, calling = false, police = false })
    if not next(W.near) then W.HudShow(false) end
end
W.CleanupInside = cleanup

function W.EnterHouse(houseId, entryId)
    if W.busy or W.session then return end
    if W.carry then W.Notify(L('hands_full'), 'bad') return end
    local r = W.Call('house:enter', houseId, entryId, W.Clock())
    if not r or not r.ok then return end
    local s = r.session
    local tpl = tplOf(s)
    s.tpl = tpl
    W.session = s
    W.FadeTo(function()
        if tpl.ipl then RequestIpl(tpl.ipl) end
        if tpl.type == 'shell' and tpl.model then
            local hash = W.LoadModel(tpl.model)
            if hash then
                shell = CreateObject(hash, s.origin.x, s.origin.y, s.origin.z, false, false, false)
                FreezeEntityPosition(shell, true)
                SetModelAsNoLongerNeeded(hash)
            end
        end
        local sp = tpl.spawns[s.spawn] or tpl.spawns.front
        local ped = PlayerPedId()
        local x, y, z = s.origin.x + sp.x, s.origin.y + sp.y, s.origin.z + sp.z
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoords(ped, x, y, z, false, false, false, false)
        SetEntityHeading(ped, sp.w)
        local t = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(20) end
        setupPoints(s)
    end)
    W.HudShow(true)
    W.Hud({ inside = true, house = WLM.HouseById[houseId].label, alarm = s.alarm.stage ~= 'idle' and s.alarm or false })
    if W.StartStealth then W.StartStealth(s) end
    if W.StartSecurity then W.StartSecurity(s) end
    if s.host and W.StartAI then W.StartAI(s) end
    local v = W.VehicleDesc()
    if v then CreateThread(function() W.Callback('witness:vehicle', v) end) end
end

function W.ExitHouse(pointId)
    if W.busy then return end
    local r = W.Call('house:exit', pointId)
    if not r or not r.ok then return end
    W.FadeTo(function()
        local ped = PlayerPedId()
        SetEntityCoords(ped, r.coords.x, r.coords.y, r.coords.z, false, false, false, false)
        SetEntityHeading(ped, (r.coords.w or 0.0) + 180.0)
        cleanup()
    end)
end

RegisterNetEvent('dp-wlamywacz:client:forceExit', function(c)
    if not W.session then return end
    W.FadeTo(function()
        SetEntityCoords(PlayerPedId(), c.x, c.y, c.z, false, false, false, false)
        cleanup()
    end)
end)

-- --------------------------------------------------------------------------
--  Zmiany stanu od serwera
-- --------------------------------------------------------------------------
RegisterNetEvent('dp-wlamywacz:client:pointState', function(id, st)
    local s = S()
    if not s then return end
    if st.searched then s.searched[id] = true end
    if st.unlocked then s.unlocked[id] = true end
    if st.taken ~= nil then
        s.taken[id] = st.taken or nil
        if st.taken then removeProp(id)
        else
            local p = WLM.U.FindPoint(tplOf(s), id)
            if p then spawnLootProp(s, p) end
        end
    end
    if st.dvr then s.dvr = st.dvr end
end)

RegisterNetEvent('dp-wlamywacz:client:lights', function(lights)
    local s = S()
    if s then s.lights = lights or {} if W.ApplyLighting then W.ApplyLighting() end end
end)

RegisterNetEvent('dp-wlamywacz:client:alarm', function(a)
    local s = S()
    if s then s.alarm = { stage = a.stage, left = a.left } end
    W.Hud({ alarm = a })
    if a.stage == 'siren' then SendNUIMessage({ action = 'siren', on = true, volume = 1.0 }) end
    if a.stage == 'disarmed' then SendNUIMessage({ action = 'siren', on = false }) end
end)

RegisterNetEvent('dp-wlamywacz:client:hud', function(d)
    W.Hud(d)
end)

AddEventHandler('dp-wlamywacz:client:houseStateChanged', function(id, st)
    local s = S()
    if s and s.house == id and st then
        s.power = st.power
        if W.ApplyLighting then W.ApplyLighting() end
        if not st.siren then SendNUIMessage({ action = 'siren', on = false }) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(props) do removeProp(id) end
    if shell and DoesEntityExist(shell) then DeleteEntity(shell) end
    SetArtificialLightsState(false)
    if hidden then FreezeEntityPosition(PlayerPedId(), false) end
end)
