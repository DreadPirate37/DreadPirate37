-- ==========================================================================
--  dp-doorlock – panel administratora i wybieranie drzwi celownikiem
--  Pętla wyboru (co klatkę) istnieje wyłącznie w trybie wyboru.
-- ==========================================================================
Admin = {}
local picking = false

function Admin.Open(focusId)
    local res = DL.Callback('admin_open')
    if not res or not res.ok then return DL.Result(res) end
    DL.admin = true
    DL.busy = true
    DL.Focus(true)
    res.focus = focusId
    SendNUIMessage({ action = 'admin', data = res })
end

RegisterCommand('doorlock', function() CreateThread(function() Admin.Open(DL.focus) end) end, false)
TriggerEvent('chat:addSuggestion', '/doorlock', L('cmd_doorlock'))

RegisterNUICallback('adminTp', function(data, cb)
    cb(1)
    local c = data.coords
    if type(c) ~= 'table' then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0 - 0.9, false, false, false, false)
end)

-- --------------------------------------------------------------------------
--  Tryb wyboru: raycast z kamery, podświetlenie obrysu, E = dodaj skrzydło
-- --------------------------------------------------------------------------
local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function aimEntity()
    local cam = GetFinalRenderedCamCoord()
    local dir = rotToDir(GetFinalRenderedCamRot(2))
    local to = cam + dir * 25.0
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 16, PlayerPedId(), 4)
    local _, hit, _, _, ent = GetShapeTestResult(h)
    if hit == 1 and ent ~= 0 and GetEntityType(ent) == 3 then return ent end
    return 0
end

local function pick(existing)
    if picking then return end
    picking = true
    local leaves, chosen = {}, {}
    local lastEnt = 0
    SendNUIMessage({ action = 'pickHud', show = true, count = 0 })

    local function outline(ent, on)
        if ent ~= 0 and DoesEntityExist(ent) then
            SetEntityDrawOutline(ent, on)
            if on then SetEntityDrawOutlineColor(124, 92, 255, 255) end
        end
    end

    local result = nil
    while picking do
        Wait(0)
        DisableControlAction(0, 24, true)  -- atak
        DisableControlAction(0, 25, true)  -- celowanie
        DisableControlAction(0, 38, true)  -- E
        DisableControlAction(0, 47, true)  -- G
        DisableControlAction(0, 200, true) -- ESC/pauza
        DisableControlAction(0, 177, true) -- Backspace

        local ent = aimEntity()
        if ent ~= lastEnt then
            if not chosen[lastEnt] then outline(lastEnt, false) end
            if not chosen[ent] then outline(ent, true) end
            lastEnt = ent
        end

        if IsDisabledControlJustPressed(0, 38) and ent ~= 0 and not chosen[ent] and #leaves < 2 then
            local c = GetEntityCoords(ent)
            chosen[ent] = true
            SetEntityDrawOutlineColor(46, 230, 166, 255)
            SetEntityDrawOutline(ent, true)
            leaves[#leaves + 1] = { model = GetEntityModel(ent), coords = { x = c.x, y = c.y, z = c.z }, ent = ent }
            SendNUIMessage({ action = 'pickHud', show = true, count = #leaves })
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            if #leaves == 2 then result = leaves picking = false end
        elseif IsDisabledControlJustPressed(0, 47) then
            for e in pairs(chosen) do outline(e, false) end
            chosen, leaves = {}, {}
            SendNUIMessage({ action = 'pickHud', show = true, count = 0 })
        elseif IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then  -- Enter
            if #leaves > 0 then result = leaves end
            picking = false
        elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
            picking = false
        end
    end

    for e in pairs(chosen) do outline(e, false) end
    outline(lastEnt, false)
    SendNUIMessage({ action = 'pickHud', show = false })
    if result then
        for _, l in ipairs(result) do l.ent = nil end
    end
    return result
end

RegisterNUICallback('adminPick', function(_, cb)
    cb(1)
    DL.Focus(false)
    CreateThread(function()
        Wait(150)
        local leaves = pick()
        DL.Focus(true)
        SendNUIMessage({ action = 'adminPicked', leaves = leaves })
    end)
end)

RegisterNUICallback('adminClose', function(_, cb)
    cb(1)
    DL.Focus(false)
    DL.busy = false
end)
