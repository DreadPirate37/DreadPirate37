Locales = {
    help_depot        = '~INPUT_CONTEXT~ Tablet zleceń spawalniczych',
    help_task         = '~INPUT_CONTEXT~ Rozpocznij spawanie: ~y~%s',
    target_depot      = 'Zlecenia spawalnicze',
    target_task       = 'Spawaj: %s',
    no_job            = 'Nie pracujesz jako spawacz.',
    busy              = 'Jesteś teraz zajęty.',
    too_far           = 'Podejdź bliżej stanowiska.',
    no_contract       = 'Nie masz aktywnego zlecenia.',
    has_contract      = 'Masz już aktywne zlecenie.',
    offer_gone        = 'To zlecenie jest już nieaktualne.',
    level_low         = 'Masz za niski poziom na to zlecenie.',
    no_money_deposit  = 'Nie stać cię na kaucję za pojazd (%s$).',
    spawn_blocked     = 'Miejsce parkingowe jest zajęte – przestaw pojazd.',
    accepted          = 'Zlecenie przyjęte: %s. Punkty pracy zaznaczono na mapie.',
    task_done         = 'Zadanie wykonane (%s). Pozostało: %d.',
    task_failed       = 'Spoina odrzucona. Pozostałe podejścia: %d.',
    task_lost         = 'Zadanie przepadło – zbyt wiele nieudanych podejść.',
    all_done          = 'Wszystkie spawy gotowe! Wróć do bazy po rozliczenie i premię.',
    not_at_depot      = 'Rozliczenie jest możliwe tylko w bazie.',
    finished          = 'Zlecenie rozliczone. Premia: %s$. Zwrot kaucji: %s$.',
    cancelled         = 'Zlecenie anulowane.',
    deposit_lost      = 'Pojazd nie wrócił do bazy – kaucja przepadła.',
    task_active       = 'Już pracujesz przy tym stanowisku.',
    suspicious        = 'Wynik odrzucony – coś tu nie gra.',
    session_invalid   = 'Sesja spawania wygasła.',
    level_up          = 'Awans! Twój nowy stopień: %s',
    error             = 'Wystąpił błąd – spróbuj ponownie.',
}

function L(key, ...)
    local s = Locales[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end
