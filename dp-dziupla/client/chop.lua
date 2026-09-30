-- ==========================================================================
--  Stanowisko rozbiórki: wykrywanie aut na stanowiskach, znaczniki części
--  (jak w Thief Simulator – patrzysz na część i widzisz, co da się zdjąć),
--  oględziny, podnośnik, przerwanie, HUD stanowiska, lakiernia po przebitce.
-- ==========================================================================
local D = Dz
local jobVehs = {}
local snaps = {}          -- [jobId] = zdjęcie auta (dla wymagań zależnych od wyposażenia)
local inspect = false
local cancelAsk = 0
local hudShown = false

-- wymagania zależne od wyposażenia liczymy z drzwi zapisanych przez serwer przy starcie
local function snapFor(veh, st)
    local s = snaps[veh]
    if not s or s.id ~= st.id then
        s = { id = st.id, doors = st.doors or {} }
        snaps[veh] = s
    end
    return s
end

-- auta ze statebagiem w pobliżu (tylko gdy jesteśmy w dziupli)
CreateThread(function()
    while true do
        local found = {}
        local pc = GetEntityCoords(PlayerPedId())
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(veh) - pc) < 30.0 then
                local st = Entity(veh).state.dpChop
                if st then
                    found[#found + 1] = veh
                    D.ApplyVisuals(veh, st)
                end
            end
        end
        jobVehs = found
        Wait(1000)
    end
end)

local function nearestJob(pc, maxD)
    local best, bd
    for _, veh in ipairs(jobVehs) do
        if DoesEntityExist(veh) then
            local d = #(GetEntityCoords(veh) - pc)
            if d < maxD and (not bd or d < bd) then best, bd = veh, d end
        end
    end
    return best, bd
end

local function counts(st)
    local done, total = 0, 0
    for id, p in pairs(st.parts) do
        local def = Parts.ById[id]
        if def and not def.op then
            total = total + 1
            if p.s == 'done' then done = done + 1 end
        end
    end
    return done, total
end

-- --------------------------------------------------------------------------
--  Lakiernia i papiery (koniec przebitki)
-- --------------------------------------------------------------------------
local paintVeh, paintSt

local function openPaint(veh, st)
    D.busy = true
    paintVeh, paintSt = veh, st
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'paintOpen', colors = Config.Revin.colors, paint = Config.Revin.paintPrice, papers = Config.Revin.papersPrice })
end

RegisterNUICallback('paint', function(data, cb)
    if not paintVeh then return cb({ ok = false }) end
    if data.cancel then
        SetNuiFocus(false, false)
        D.busy = false
        paintVeh = nil
        return cb({ ok = true })
    end
    CreateThread(function()
        local r = D.Callback('revinPaint', paintSt.id, tonumber(data.color), data.papers == true)
        if r and r.ok then
            local veh = paintVeh
            if D.Control(veh) then
                SetVehicleColours(veh, r.color, r.color)
                SetVehicleNumberPlateText(veh, r.plate)
                SetVehicleDirtLevel(veh, 0.0)
            end
            Hooks.GiveKeys(veh, r.plate)
            SetNuiFocus(false, false)
            D.busy = false
            paintVeh = nil
            if D.SetCleanCar then D.SetCleanCar(r.net) end
            D.Notify(r.msg, 'good', 8000)
        else
            D.Notify(r and r.msg or L('error'), 'bad')
        end
        cb(r or { ok = false })
    end)
end)

-- --------------------------------------------------------------------------
--  Pętla znaczników i wyboru części
-- --------------------------------------------------------------------------
local M = Config.Marker

local function marker(w, col)
    DrawMarker(28, w.x, w.y, w.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, M.size, M.size, M.size, col[1], col[2], col[3], col[4], false, false, 2, false, nil, nil, false)
end

CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local pc = GetEntityCoords(ped)
        local veh = (#jobVehs > 0 and not D.busy and not D.carrying and not IsPedInAnyVehicle(ped, false)) and nearestJob(pc, 7.5) or nil
        local st = veh and Entity(veh).state.dpChop
        if st and st.parts then
            sleep = 0
            local snap = snapFor(veh, st)
            local best, bestD, bestDef, bestBlock
            for id, p in pairs(st.parts) do
                local def = Parts.ById[id]
                if def and p.s ~= 'done' then
                    local loc = D.AnchorLocal(veh, def)
                    local w = GetOffsetFromEntityInWorldCoords(veh, loc.x, loc.y, loc.z)
                    local dist = #(w - pc)
                    if dist < 4.2 then
                        local block = Logic.Blockers(def, st, snap)
                        local col = p.s == 'busy' and M.busy or (#block > 0 and M.blocked or M.available)
                        marker(w, col)
                        if inspect then
                            local txt = (#block > 0 and '~c~' or '~y~') .. def.label
                            if st.mode == 'build' then txt = txt .. ' ~o~brak'
                            elseif not def.op then txt = txt .. ' ~s~' .. p.c .. '%' end
                            D.Text3D(w + vector3(0.0, 0.0, 0.07), txt, 0.26)
                        end
                        if dist < 2.8 then
                            local on, sx, sy = GetScreenCoordFromWorldCoord(w.x, w.y, w.z)
                            if on then
                                local d = math.sqrt((sx - 0.5) ^ 2 + (sy - 0.5) ^ 2)
                                if d < 0.085 and (not bestD or d < bestD) then
                                    best, bestD, bestDef, bestBlock = id, d, def, block
                                    best = { id = id, w = w, p = p }
                                end
                            end
                        end
                    end
                end
            end

            -- rozebrane do gołej karoserii: można zostawić na składaka
            if st.mode == 'chop' and Config.Build.enabled then
                local bare = true
                for _, id in ipairs(Config.Build.parts) do
                    local pp = st.parts[id]
                    if pp and pp.s ~= 'done' then bare = false break end
                end
                if bare then
                    D.Text3D(GetEntityCoords(veh) + vector3(0.0, 0.0, 1.2), L('build_convert'), 0.32)
                    if IsControlJustReleased(0, 29) then
                        CreateThread(function()
                            local r = D.Callback('buildConvert', st.id)
                            if r and r.msg then D.Notify(r.msg, r.ok and 'good' or 'bad') end
                        end)
                    end
                end
            end

            if (st.mode == 'revin' or st.mode == 'build') and st.ready then
                D.Help(L('help_revin_done'))
                if IsControlJustReleased(0, 38) then openPaint(veh, st) end
            elseif best then
                local p = best.p
                local line
                if p.s == 'busy' then
                    line = '~r~' .. L('part_locked')
                elseif #bestBlock > 0 then
                    line = '~r~' .. L('part_blocked', table.concat(bestBlock, ', '))
                else
                    if st.mode == 'build' then
                        line = '~o~Brak – [E] zamontuj z magazynu'
                    else
                        line = bestDef.op and '~g~Gotowe do pracy' or ('Stan: ~b~' .. p.c .. '%~s~ (' .. Logic.GradeLabel(p.c) .. ')')
                    end
                end
                D.Text3D(best.w + vector3(0.0, 0.0, 0.16), '~y~' .. bestDef.label, 0.38)
                D.Text3D(best.w + vector3(0.0, 0.0, 0.11), line, 0.3)
                D.Help(L('help_part'))
                if IsControlJustReleased(0, 38) and p.s == 'on' and #bestBlock == 0 then
                    local id = best.id
                    CreateThread(function() D.StartPart(veh, st, id) end)
                end
            else
                D.Help(L('help_part'))
            end

            -- G: oględziny
            if IsControlJustReleased(0, 47) then inspect = not inspect end
            -- H: podnośnik (0 -> 1 -> 2 -> 0)
            if IsControlJustReleased(0, 74) and st.mode == 'chop' and not st.moving then
                local lvl = ((st.lift or 0) + 1) % #Config.Bay.lift
                CreateThread(function()
                    local r = D.Callback('lift', st.id, lvl)
                    if r and r.msg then D.Notify(r.msg, r.ok and 'info' or 'bad') end
                end)
            end
            -- X dwa razy: przerwij rozbiórkę
            if IsControlJustReleased(0, 73) then
                if GetGameTimer() - cancelAsk < 4000 then
                    cancelAsk = 0
                    CreateThread(function()
                        local r = D.Callback('chopCancel', st.id)
                        if r and r.msg then D.Notify(r.msg, r.ok and 'warn' or 'bad') end
                    end)
                else
                    cancelAsk = GetGameTimer()
                    D.Notify('Wciśnij X jeszcze raz, żeby przerwać rozbiórkę i zwolnić stanowisko.', 'warn', 4000)
                end
            end
        end
        Wait(sleep)
    end
end)

-- --------------------------------------------------------------------------
--  HUD stanowiska (postęp, podnośnik, hałas, brama)
-- --------------------------------------------------------------------------
CreateThread(function()
    local noise, gate, lastNoise = 0, false, 0
    while true do
        local sleep = 1500
        if D.shop and not D.busy then
            local pc = GetEntityCoords(PlayerPedId())
            local veh = nearestJob(pc, 9.0)
            local st = veh and Entity(veh).state.dpChop
            if st and st.parts then
                sleep = 700
                if GetGameTimer() - lastNoise > 3000 then
                    lastNoise = GetGameTimer()
                    local r = D.Callback('noise', D.shop.key)
                    if r then noise, gate = r.v or 0, r.closed == true end
                end
                local done, total = counts(st)
                SendNUIMessage({ action = 'bayHud', show = true, data = {
                    label = st.label, done = done, total = total, lift = st.lift or 0, moving = st.moving,
                    noise = noise, gate = gate, mode = st.mode, flags = st.flags,
                } })
                hudShown = true
            elseif hudShown then
                SendNUIMessage({ action = 'bayHud', show = false })
                hudShown = false
            end
        elseif hudShown then
            SendNUIMessage({ action = 'bayHud', show = false })
            hudShown = false
        end
        Wait(sleep)
    end
end)
