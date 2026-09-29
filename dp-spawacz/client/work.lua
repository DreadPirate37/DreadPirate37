-- ==========================================================================
--  Stanowisko pracy: start minigry, animacje, kamera, światło łuku, wynik
-- ==========================================================================
local S = Spawacz
local scene

local function fwd(h)
    local r = math.rad(h)
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

local function makeCam(t)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local f = fwd(t.heading)
    local right = vector3(f.y, -f.x, 0.0)
    local camPos = p - f * 1.3 + right * 1.2 + vector3(0.0, 0.0, 0.75)
    local look = p + f * 0.9 + vector3(0.0, 0.0, -0.1)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 50.0, false, 0)
    PointCamAtCoord(cam, look.x, look.y, look.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 800, true, true)
    return cam
end

local function setStage(name)
    if not scene or scene.stage == name then return end
    scene.stage = name
    local ped = PlayerPedId()
    if name == 'weld' or name == 'tack' then
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, Config.Anim.weldScenario, 0, true)
    elseif name == 'prep' or name == 'drill' or name == 'finish' then
        local a = Config.Anim.kneel
        if S.LoadDict(a.dict) then
            ClearPedTasks(ped)
            TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
        end
    else
        ClearPedTasks(ped)
    end
end

local function arcLight()
    if scene.lightThread then return end
    scene.lightThread = true
    CreateThread(function()
        local p = scene.workPos
        while scene and scene.arc do
            local f = math.random(65, 100) / 100
            DrawLightWithRange(p.x, p.y, p.z + 0.4, 150, 190, 255, 4.5 * f, 7.0 * f)
            Wait(0)
        end
        if scene then scene.lightThread = false end
    end)
end

local function endScene()
    if not scene then return end
    local ped = PlayerPedId()
    scene.arc = false
    SetNuiFocus(false, false)
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    if scene.cam then
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(scene.cam, false)
    end
    local res = scene.result
    scene = nil
    S.busy = false
    SetTimeout(1500, function()
        if not scene and IsPedUsingAnyScenario(PlayerPedId()) then ClearPedTasksImmediately(PlayerPedId()) end
    end)
    -- podsumowanie po zamknięciu
    if res and res.ok then
        if res.failed then
            S.Notify(res.attemptsLeft > 0 and L('task_failed', res.attemptsLeft) or L('task_lost'), 'bad')
        elseif res.left and res.left > 0 then
            S.Notify(L('task_done', res.grade, res.left), 'good')
        end
        if res.left == 0 then S.Notify(L('all_done'), 'good', 8000) end
    end
end

function S.BeginTask(t)
    if S.busy then return S.Notify(L('busy'), 'warn') end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
    S.busy = true
    local r = S.Callback('startTask', t.id)
    if not r or not r.ok then
        S.busy = false
        S.Notify(r and r.msg or L('error'), 'bad')
        return
    end
    scene = { task = t, workPos = t.pos + fwd(t.heading) * 0.9 }
    SetEntityHeading(ped, t.heading)
    FreezeEntityPosition(ped, true)
    if Config.Camera then scene.cam = makeCam(t) end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openGame', task = r.task })

    -- strażnik: śmierć / teleport w trakcie minigry
    CreateThread(function()
        while scene do
            local p = PlayerPedId()
            if IsEntityDead(p) or #(GetEntityCoords(p) - t.pos) > Config.Security.maxDistance then
                SendNUIMessage({ action = 'forceClose' })
                S.Callback('abortTask')
                endScene()
                break
            end
            Wait(500)
        end
    end)
end

-- --------------------------------------------------------------------------
--  NUI
-- --------------------------------------------------------------------------
RegisterNUICallback('stage', function(data, cb)
    setStage(data and data.name)
    cb({ ok = true })
end)

RegisterNUICallback('arc', function(data, cb)
    if scene then
        scene.arc = data and data.on == true
        if scene.arc then arcLight() end
    end
    cb({ ok = true })
end)

RegisterNUICallback('finish', function(data, cb)
    CreateThread(function()
        local r = S.Callback('finishTask', data)
        if r and r.ok then
            if r.contract then r.left = S.UpdateContract(r.contract) end
            r.contract = nil
            if scene then scene.result = r end
        end
        cb(r or { ok = false, msg = L('error') })
    end)
end)

RegisterNUICallback('closeGame', function(_, cb)
    endScene()
    cb({ ok = true })
end)

RegisterNUICallback('abort', function(_, cb)
    CreateThread(function()
        S.Callback('abortTask')
    end)
    endScene()
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and scene then endScene() end
end)
