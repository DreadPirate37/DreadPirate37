Locales = {
    -- ogólne
    error            = 'Wystąpił błąd – spróbuj ponownie.',
    slow_down        = 'Zwolnij trochę.',
    no_door          = 'Te drzwi już nie istnieją.',
    too_far          = 'Jesteś za daleko od drzwi.',
    no_access        = 'Brak dostępu.',
    cant_do          = 'Tego nie da się zrobić przy tych drzwiach.',
    need_item        = 'Brak potrzebnego przedmiotu',
    difficulty       = 'Trudność %d/5',
    alarm_warn       = 'Uruchomi alarm',
    session_invalid  = 'Sesja wygasła.',
    suspicious       = 'Wynik odrzucony – coś tu nie gra.',
    cancelled        = 'Przerwano.',
    no_player        = 'Nie ma takiego gracza.',

    -- stany
    door_broken      = 'Zamek jest wyłamany – wymaga naprawy.',
    lockdown_active  = 'Budynek jest zablokowany.',
    already_open     = 'Te drzwi są otwarte.',
    not_broken       = 'Zamek jest sprawny.',

    -- klawiatura
    wrong_pin        = 'Błędny kod.',
    keypad_locked    = 'Klawiatura zablokowana na %ds.',
    pin_len          = 'PIN musi mieć %d–%d cyfr.',
    pin_changed      = 'Kod został zmieniony.',

    -- menu
    m_unlock         = 'Otwórz',
    m_lock           = 'Zamknij',
    m_keypad         = 'Klawiatura',
    m_card           = 'Przyłóż kartę',
    m_bio            = 'Skaner linii papilarnych',
    m_knock          = 'Zapukaj',
    m_bell           = 'Zadzwoń',
    m_lockpick       = 'Wytrych',
    m_lockpick_diy   = 'Spinka i śrubokręt',
    m_lockpick_round = 'Wytrych okrągły',
    skill_low        = 'Wymaga umiejętności Włamywanie LVL %d',
    skill_up         = 'Włamywanie: poziom %d!',
    xp_gain          = 'Włamywanie +%d XP',
    m_hack           = 'Włam do czytnika',
    m_thermite       = 'Ładunek termitowy',
    m_ram            = 'Wyważ taranem',
    m_repair         = 'Napraw zamek',
    m_lockdown       = 'Zablokuj budynek',
    m_lockdown_off   = 'Zdejmij blokadę',
    m_keys           = 'Klucze',
    m_keys_desc      = 'Zarządzaj dostępem',
    m_pin            = 'Zmień PIN',
    m_edit           = 'Edytuj drzwi',

    -- akcje
    bell_ring        = 'Ktoś dzwoni do drzwi: %s',
    bell_sent        = 'Zadzwoniłeś.',
    picked           = 'Zamek ustąpił.',
    pick_failed      = 'Nie udało się. Wytrych przetrwał.',
    pick_broke       = 'Wytrych pękł!',
    hacked           = 'Czytnik zhakowany – drzwi odblokowane.',
    hack_failed      = 'Hakowanie nieudane – czytnik się zablokował.',
    hack_locked      = 'Czytnik jest zablokowany jeszcze %ds.',
    breached         = 'Zamek przepalony!',
    rammed           = 'Drzwi wyważone.',
    repaired         = 'Zamek naprawiony.',
    p_thermite       = 'Termit się pali…',
    p_ram            = 'Wyważanie…',
    p_repair         = 'Naprawa zamka…',
    lockdown_on      = 'Blokada budynku %s: zamknięto %d drzwi.',
    lockdown_off     = 'Zdjęto blokadę budynku %s.',
    lockdown_usage   = 'Użycie: /lockdown <grupa> [off]',

    -- klucze
    key_given        = 'Klucz przekazany.',
    key_taken        = 'Klucz odebrany.',
    key_received     = 'Otrzymałeś klucz do: %s',
    keys_full        = 'Osiągnięto limit kluczy.',

    -- alarmy
    alarm_blip       = 'Alarm: %s',
    alarm_toast      = 'ALARM – %s (%s)',

    -- admin
    door_created     = 'Drzwi dodane.',
    door_saved       = 'Zmiany zapisane.',
    door_deleted     = 'Drzwi usunięte.',
    bad_door         = 'Nieprawidłowe dane drzwi (%s).',
    cmd_doorlock     = 'Panel zamków drzwi (admin)',

    -- klawisze
    key_use          = 'Drzwi: otwórz / zamknij',
    key_menu         = 'Drzwi: menu akcji',
}

function L(key, ...)
    local s = Locales[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end
