-- ==========================================================================
--  KAMERY, MIEJSCA MONTAŻU, PROPY, ANIMACJE
--  Pozycje podawane są w „połówkach wymiaru auta” względem środka jego bryły:
--    x: -1 = lewy bok, 1 = prawy bok   y: -1 = tył, 1 = przód   z: -1 = spód, 1 = dach
--  Dzięki temu kamery i poświaty pasują do każdego auta – od hatchbacka po autobus.
-- ==========================================================================

Config.CamPresets = {
    overview  = { pos = vec3(-1.9, 1.9, 0.95),  look = vec3(0.0, 0.0, -0.1), fov = 45.0 },
    front     = { pos = vec3(0.45, 2.55, 0.55), look = vec3(0.0, 0.8, -0.15), fov = 40.0 },
    rear      = { pos = vec3(-0.45, -2.55, 0.55), look = vec3(0.0, -0.8, -0.15), fov = 40.0 },
    rear_high = { pos = vec3(-0.55, -2.3, 1.9),  look = vec3(0.0, -0.75, 0.45), fov = 40.0 },
    side_l    = { pos = vec3(-3.0, 0.2, 0.45),  look = vec3(-0.6, 0.0, -0.2), fov = 42.0 },
    side_r    = { pos = vec3(3.0, 0.2, 0.45),   look = vec3(0.6, 0.0, -0.2), fov = 42.0 },
    wheel_fl  = { pos = vec3(-2.6, 1.25, -0.2), look = vec3(-0.9, 0.62, -0.55), fov = 38.0, bone = 'wheel_lf' },
    hood      = { pos = vec3(0.6, 2.2, 1.6),    look = vec3(0.0, 0.55, 0.15), fov = 42.0 },
    engine    = { pos = vec3(0.0, 1.75, 2.1),   look = vec3(0.0, 0.62, 0.15), fov = 45.0 },
    interior  = { pos = vec3(0.35, -0.05, 0.45), look = vec3(-0.25, 0.55, 0.05), fov = 55.0 },
    roof      = { pos = vec3(-1.3, -1.4, 3.2),  look = vec3(0.0, 0.0, 0.8), fov = 42.0 },
    trunk     = { pos = vec3(0.0, -2.2, 1.9),   look = vec3(0.0, -0.75, 0.2), fov = 45.0 },
    exhaust   = { pos = vec3(-0.9, -2.4, -0.1), look = vec3(0.35, -0.95, -0.55), fov = 38.0 },
    under     = { pos = vec3(1.1, 0.35, -2.4),  look = vec3(0.0, 0.1, -0.9), fov = 60.0, under = true, fallback = 'side_l' },
}

-- miejsca montażu: bones = kości GTA (pierwsza znaleziona), off = pozycja zapasowa
Config.Anchors = {
    spoiler       = { bones = { 'spoiler', 'boot' }, off = vec3(0.0, -0.85, 0.55), boneOff = vec3(0.0, -0.1, 0.25), size = 0.9 },
    bumper_f      = { bones = { 'bumper_f' },        off = vec3(0.0, 0.97, -0.35), size = 0.9 },
    bumper_r      = { bones = { 'bumper_r' },        off = vec3(0.0, -0.97, -0.35), size = 0.9 },
    grille        = { bones = { 'bumper_f' },        off = vec3(0.0, 0.95, -0.15), boneOff = vec3(0.0, 0.0, 0.15), size = 0.5 },
    hood          = { bones = { 'bonnet' },          off = vec3(0.0, 0.6, 0.25), size = 0.9 },
    engine        = { bones = { 'engine' },          off = vec3(0.0, 0.6, 0.05), boneOff = vec3(0.0, 0.0, 0.15), size = 0.6 },
    skirt         = { bones = {},                    off = vec3(-1.0, 0.0, -0.65), size = 0.8 },
    fender_l      = { bones = {},                    off = vec3(-0.98, 0.55, 0.0), size = 0.55 },
    fender_r      = { bones = {},                    off = vec3(0.98, 0.55, 0.0), size = 0.55 },
    roof          = { bones = {},                    off = vec3(0.0, -0.1, 0.95), size = 0.8 },
    door_l        = { bones = { 'door_dside_f' },    off = vec3(-0.98, 0.1, -0.05), size = 0.6 },
    interior      = { bones = { 'seat_dside_f' },    off = vec3(-0.25, 0.05, 0.0), boneOff = vec3(0.0, 0.2, 0.25), size = 0.45 },
    steering      = { bones = { 'steeringwheel' },   off = vec3(-0.35, 0.3, 0.25), size = 0.25 },
    trunk         = { bones = { 'boot' },            off = vec3(0.0, -0.8, 0.25), size = 0.7 },
    plate_r       = { bones = { 'platelight' },      off = vec3(0.0, -0.99, -0.2), size = 0.35 },
    exhaust       = { bones = { 'exhaust', 'exhaust_2' }, off = vec3(0.4, -1.0, -0.55), size = 0.35 },
    wheel         = { bones = { 'wheel_lf' },        off = vec3(-0.9, 0.62, -0.55), size = 0.55, wheel = true },
    front         = { bones = { 'bumper_f' },        off = vec3(0.0, 0.92, -0.25), size = 0.7 },
    under_engine  = { bones = { 'engine' },          off = vec3(0.0, 0.55, -0.9), boneOff = vec3(0.0, 0.0, -0.45), size = 0.5, under = true },
    under_gearbox = { bones = {},                    off = vec3(0.0, 0.15, -0.9), size = 0.5, under = true },
    under_exhaust = { bones = {},                    off = vec3(0.25, -0.45, -0.9), size = 0.5, under = true },
    under_front   = { bones = {},                    off = vec3(0.0, 0.62, -0.9), size = 0.5, under = true },
    under_rear    = { bones = {},                    off = vec3(0.0, -0.62, -0.9), size = 0.5, under = true },
}

-- co mechanik niesie – model + przyczepienie (brak modelu w grze = karton)
Config.CarryProps = {
    default     = { model = 'prop_cs_cardbox_01',  bone = 28422, pos = vec3(0.0, -0.03, -0.18), rot = vec3(5.0, 0.0, 0.0) },
    spoiler     = { model = 'prop_car_bonnet_02',  bone = 28422, pos = vec3(0.05, -0.2, -0.25), rot = vec3(-70.0, 0.0, 0.0), scaleHint = 'duża' },
    bumper      = { model = 'prop_car_bonnet_01',  bone = 28422, pos = vec3(0.0, -0.25, -0.3), rot = vec3(-75.0, 0.0, 0.0) },
    hood        = { model = 'prop_car_bonnet_01',  bone = 28422, pos = vec3(0.0, -0.25, -0.3), rot = vec3(-75.0, 0.0, 0.0) },
    panel       = { model = 'prop_car_door_01',    bone = 28422, pos = vec3(0.0, -0.1, -0.35), rot = vec3(0.0, 0.0, 90.0) },
    frame       = { model = 'prop_rub_carpart_02', bone = 28422, pos = vec3(0.0, -0.1, -0.2), rot = vec3(0.0, 0.0, 0.0) },
    exhaust     = { model = 'prop_car_exhaust_01', bone = 28422, pos = vec3(0.0, -0.05, -0.15), rot = vec3(0.0, 90.0, 0.0) },
    engine_part = { model = 'prop_car_engine_01',  bone = 28422, pos = vec3(0.0, -0.15, -0.25), rot = vec3(0.0, 0.0, 0.0) },
    turbo       = { model = 'prop_cs_cardbox_01',  bone = 28422, pos = vec3(0.0, -0.03, -0.18), rot = vec3(5.0, 0.0, 0.0) },
    brake       = { model = 'prop_rub_carpart_04', bone = 28422, pos = vec3(0.0, -0.05, -0.2), rot = vec3(0.0, 0.0, 0.0) },
    spring      = { model = 'prop_rub_carpart_03', bone = 28422, pos = vec3(0.0, -0.05, -0.2), rot = vec3(0.0, 0.0, 0.0) },
    seat        = { model = 'prop_car_seat',       bone = 28422, pos = vec3(0.0, -0.2, -0.35), rot = vec3(0.0, 0.0, 180.0) },
    steering    = { model = 'prop_cs_cardbox_01',  bone = 28422, pos = vec3(0.0, -0.03, -0.18), rot = vec3(5.0, 0.0, 0.0) },
    small       = { model = 'prop_tool_box_04',    bone = 28422, pos = vec3(0.0, -0.03, -0.15), rot = vec3(0.0, 0.0, 0.0) },
    box         = { model = 'prop_cs_cardbox_01',  bone = 28422, pos = vec3(0.0, -0.03, -0.18), rot = vec3(5.0, 0.0, 0.0) },
    roll        = { model = 'prop_cs_cardbox_01',  bone = 28422, pos = vec3(0.0, -0.03, -0.18), rot = vec3(5.0, 0.0, 0.0) },
    wheel       = { model = 'prop_wheel_01',       bone = 28422, pos = vec3(0.0, -0.1, -0.2), rot = vec3(0.0, 90.0, 0.0) },
    tire        = { model = 'prop_wheel_tyre',     bone = 28422, pos = vec3(0.0, -0.1, -0.2), rot = vec3(0.0, 90.0, 0.0) },
    battery     = { model = 'prop_car_battery_01', bone = 28422, pos = vec3(0.0, -0.05, -0.12), rot = vec3(0.0, 0.0, 0.0) },
    fluid       = { model = 'prop_oilcan_01a',     bone = 57005, pos = vec3(0.12, 0.0, -0.02), rot = vec3(-90.0, 0.0, 0.0), oneHand = true },
    nitro       = { model = 'prop_gascyl_01a',     bone = 28422, pos = vec3(0.0, -0.05, -0.2), rot = vec3(0.0, 90.0, 0.0) },
}

Config.CarryAnim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
Config.OneHandAnim = { dict = 'move_weapon@jerrycan@generic', clip = 'idle' }

Config.WorkAnims = {
    default = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    engine  = { dict = 'mini@repair', clip = 'fixing_a_player' },
    under   = { dict = 'amb@world_human_vehicle_mechanic@male@base', clip = 'base' },
    wheel   = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    interior= { dict = 'mini@repair', clip = 'fixing_a_ped' },
    paint   = { scenario = 'WORLD_HUMAN_MAID_CLEAN' },
}

-- stanowiska: model propa (nil = stanowisko tylko w MLO, rysowany marker)
Config.StationModels = {
    cabinet     = 'prop_toolchest_05',
    tireChanger = 'prop_tool_bench02',
    balancer    = 'prop_tool_bench02',
    liftPanel   = 'prop_elecbox_03a',
}

-- podnośniki – geometria rysowana (działa bez MLO); model = jeśli masz prop podnośnika
Config.Lifts = {
    speed = 0.22,          -- m/s
    ramp = { model = nil, length = 5.2, width = 2.6, railWidth = 0.62, thickness = 0.12, color = { 58, 64, 72 }, accent = { 255, 122, 26 } },
    arms = { model = nil, columnGap = 3.3, columnSize = 0.34, columnHeight = 3.3, armLength = 1.1, color = { 58, 64, 72 }, accent = { 255, 122, 26 } },
    driveOnRadius = 2.2,   -- jak blisko środka podnośnika musi stać auto
}

-- hamownia
Config.Dyno = {
    runTime = 9.0,         -- s trwania pomiaru
    rpmStart = 0.18,       -- ułamek obrotów maksymalnych na starcie
    gear = 4,
    noise = 0.012,         -- szum pomiaru (realizm)
}
