-- ==========================================================================
--  Wygląd rozbieranego auta: zdjęte drzwi, koła, szyby, tuning, tablice.
--  Stan przychodzi przez statebag 'dpChop'; stosujemy go idempotentnie
--  (również gdy auto dopiero wjedzie w zasięg streamingu).
-- ==========================================================================
local D = Dz
local applied = {}   -- [veh] = { [partId] = true }
local built = {}     -- [veh] = wersja stanu składaka

local function applyPart(veh, def)
    local v = def.vis
    if not v then return end
    if v.door then
        SetVehicleDoorBroken(veh, v.door, true)
    elseif v.wheel then
        if v.wheel < GetVehicleNumberOfWheels(veh) then
            BreakOffVehicleWheel(veh, v.wheel, false, true, true, false)
        end
    elseif v.window then
        RemoveVehicleWindow(veh, v.window)
    elseif v.mod then
        SetVehicleModKit(veh, 0)
        SetVehicleMod(veh, v.mod, -1, false)
    elseif v.toggle then
        ToggleVehicleMod(veh, v.toggle, false)
    elseif v.plate then
        SetVehicleNumberPlateText(veh, ' ')
    elseif v.undriveable then
        SetVehicleEngineHealth(veh, 0.0)
    end
end

function D.ApplyVisuals(veh, st)
    if not st or not st.parts or not DoesEntityExist(veh) then return end
    -- składak: naprawiamy całe auto i „zdejmujemy” to, czego jeszcze nie zamontowano
    if st.mode == 'build' then
        if built[veh] ~= st.ver then
            built[veh] = st.ver
            SetVehicleFixed(veh)
            SetVehicleDeformationFixed(veh)
            for id, p in pairs(st.parts) do
                local def = Parts.ById[id]
                if def and p.s ~= 'done' then applyPart(veh, def) end
            end
        end
        SetVehicleUndriveable(veh, true)
        return
    end
    local done = applied[veh] or {}
    applied[veh] = done
    SetVehicleUndriveable(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    for id, p in pairs(st.parts) do
        if p.s == 'done' and not done[id] then
            local def = Parts.ById[id]
            if def then
                done[id] = true
                applyPart(veh, def)
            end
        end
    end
end

function D.ForgetVisuals(veh)
    applied[veh] = nil
    built[veh] = nil
    D.ClearAnchorCache(veh)
end

AddStateBagChangeHandler('dpChop', nil, function(bagName, _, value)
    local veh = GetEntityFromStateBagName(bagName)
    if veh == 0 then return end
    if not value then
        D.ForgetVisuals(veh)
        SetVehicleUndriveable(veh, false)
        return
    end
    -- handler odpala się przed zapisem stanu – aplikujemy w następnej klatce
    SetTimeout(0, function() D.ApplyVisuals(veh, value) end)
end)

-- sprzątanie cache dla aut, które zniknęły
CreateThread(function()
    while true do
        Wait(30000)
        for veh in pairs(applied) do
            if not DoesEntityExist(veh) then applied[veh] = nil end
        end
    end
end)
