-- ==========================================================================
--  Baza: brygadzista (NPC), blip, tablet zleceń
-- ==========================================================================
local S = Spawacz
local D = Config.Depot
local depotPed, tabletProp

local function spawnDepotPed()
    local hash = S.LoadModel(D.ped.model)
    if not hash then return end
    local c = D.ped.coords
    local z = S.GroundZ(c.xyz)
    depotPed = CreatePed(4, hash, c.x, c.y, z, c.w, false, true)
    SetEntityInvincible(depotPed, true)
    SetBlockingOfNonTemporaryEvents(depotPed, true)
    FreezeEntityPosition(depotPed, true)
    TaskStartScenarioInPlace(depotPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(hash)
    if S.usingTarget == 'ox' then
        exports.ox_target:addLocalEntity(depotPed, { {
            name = 'dp_spawacz_depot', icon = 'fa-solid fa-helmet-safety', label = L('target_depot'), distance = 2.5,
            onSelect = function() S.OpenTablet() end,
        } })
    elseif S.usingTarget == 'qb' then
        exports['qb-target']:AddTargetEntity(depotPed, {
            options = { { icon = 'fas fa-hard-hat', label = L('target_depot'), action = function() S.OpenTablet() end } },
            distance = 2.5,
        })
    end
end

local function deleteDepotPed()
    if depotPed and DoesEntityExist(depotPed) then DeleteEntity(depotPed) end
    depotPed = nil
end

CreateThread(function()
    local b = AddBlipForCoord(D.ped.coords.x, D.ped.coords.y, D.ped.coords.z)
    SetBlipSprite(b, D.blip.sprite)
    SetBlipColour(b, D.blip.color)
    SetBlipScale(b, D.blip.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(D.label)
    EndTextCommandSetBlipName(b)

    Wait(1500)
    local pos = D.ped.coords.xyz
    while true do
        local sleep = 1500
        local dist = #(GetEntityCoords(PlayerPedId()) - pos)
        if dist < 70.0 then
            if not depotPed then spawnDepotPed() end
            sleep = 500
            if not S.usingTarget and dist < 2.2 and not S.busy then
                sleep = 0
                S.Help(L('help_depot'))
                if IsControlJustReleased(0, 38) then S.OpenTablet() end
            end
        elseif depotPed then
            deleteDepotPed()
        end
        Wait(sleep)
    end
end)

-- --------------------------------------------------------------------------
--  Tablet
-- --------------------------------------------------------------------------
local function tabletAnim(on)
    local ped = PlayerPedId()
    if on then
        local a = Config.Anim.tablet
        if S.LoadDict(a.dict) then TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 49, 0, false, false, false) end
        local hash = S.LoadModel(a.prop)
        if hash then
            tabletProp = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
            AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(hash)
        end
    else
        StopAnimTask(ped, Config.Anim.tablet.dict, Config.Anim.tablet.clip, 2.0)
        if tabletProp and DoesEntityExist(tabletProp) then DeleteEntity(tabletProp) end
        tabletProp = nil
    end
end

function S.OpenTablet()
    if S.busy then return end
    local res = S.Callback('overview')
    if not res or not res.ok then
        S.Notify(res and res.msg or L('error'), 'bad')
        return
    end
    S.busy = true
    tabletAnim(true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openTablet', data = res.data })
end

local function closeTablet()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeTablet' })
    tabletAnim(false)
    S.busy = false
end

RegisterNUICallback('tablet', function(data, cb)
    local action = data and data.action
    if action == 'close' then
        closeTablet()
        return cb({ ok = true })
    end
    CreateThread(function()
        if action == 'accept' then
            local sp = Config.Depot.vehicleSpawn
            if Config.Vehicle.enabled and IsAnyVehicleNearPoint(sp.x, sp.y, sp.z, 3.0) then
                return cb({ ok = false, msg = L('spawn_blocked') })
            end
            local r = S.Callback('accept', data.id)
            if r and r.ok then
                closeTablet()
                S.StartContract(r.contract)
                return cb({ ok = true, msg = r.msg, close = true })
            end
            return cb({ ok = false, msg = r and r.msg or L('error') })
        elseif action == 'cancel' or action == 'finish' then
            local r = S.Callback(action == 'cancel' and 'cancelContract' or 'finishContract')
            if r and r.ok then
                closeTablet()
                S.EndContract()
            end
            return cb(r or { ok = false, msg = L('error') })
        elseif action == 'waypoint' then
            S.WaypointNext()
            return cb({ ok = true, msg = 'Zaznaczono najbliższe stanowisko na GPS.' })
        end
        cb({ ok = false })
    end)
end)

-- tablet dostępny także zdalnie (podgląd / anulowanie) – bez domyślnego klawisza
RegisterCommand('spawacz', function() S.OpenTablet() end, false)
RegisterKeyMapping('spawacz', 'Spawacz: tablet zleceń', 'keyboard', '')

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    deleteDepotPed()
    if tabletProp and DoesEntityExist(tabletProp) then DeleteEntity(tabletProp) end
    if S.busy then SetNuiFocus(false, false) end
end)
