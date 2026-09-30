# dp-pojazdy – systemy pojazdu dla FiveM

Standalone skrypt do aut: tryby jazdy (ECO / KOMFORT / SPORT / SPORT+ / DRIFT), przełączanie napędu
FWD / RWD / AWD, blokady dyferencjałów, reduktor 4L, kontrola trakcji, launch control, tempomat,
ogranicznik prędkości, zawieszenie pneumatyczne, kierunkowskazy z autokasowaniem, pasy z wypadaniem
przez szybę i silnik, który nie gaśnie po wyjściu. Do tego panel sterowania z telemetrią na żywo
i mały pasek statusu.

- **Bez frameworka i bez bazy danych.** Działa na ESX, QB, QBox i standalone.
- **Wszystko się synchronizuje.** Stan auta siedzi w state bagu pojazdu, więc po przesiadce
  kolejny kierowca dostaje te same ustawienia. Kierunkowskazy i wysokość zawieszenia widzą wszyscy.
- **Zero plików audio i obrazków.** Dźwięki (kierunkowskaz, gong pasów, blokady, pneumatyka)
  są syntezowane przez WebAudio.

---

## Instalacja
1. Wrzuć folder `dp-pojazdy` do `resources`.
2. Dopisz do `server.cfg`: `ensure dp-pojazdy`.
3. Przejrzyj `config.lua`. Jeśli masz już pasy w HUD-zie albo osobny skrypt do kierunkowskazów,
   wyłącz u nas `Config.Seatbelt.enabled` / `Config.Indicators.enabled`.

## Sterowanie (domyślne klawisze)
Każdy gracz może je zmienić w **Ustawienia → Przypisanie klawiszy → FiveM**.

| Klawisz | Funkcja |
|---|---|
| `F7` | panel sterowania (mysz, można jechać z otwartym panelem) |
| `Z` | następny tryb jazdy |
| `NUM9` | przełącz napęd |
| `NUM8` | blokada dyferencjału (kolejny poziom / wyłącz) |
| `NUM7` | reduktor 4H ↔ 4L |
| `NUM6` | kontrola trakcji: TC → TC SPORT → OFF |
| `NUM5` | uzbrój launch control |
| `NUM4` | zawieszenie pneumatyczne (kolejny poziom) |
| `NUM1` / `NUM2` | tempomat / ogranicznik (bierze aktualną prędkość) |
| `PGUP` / `PGDN` | ± krok tempomatu albo ogranicznika |
| `←` `→` `↑` | lewy / prawy kierunkowskaz / awaryjne |
| `B` | pasy |
| – | silnik on/off (bez domyślnego klawisza, przypisz sam) |

## Funkcje

### Tryby jazdy
Tryb zmienia handling auta **względem jego oryginału**: moc, szybkość wkręcania się silnika, czas
zmiany biegów, twardość zawieszenia i stabilizatorów, przyczepność, hamulce i kąt skrętu.
Każdy tryb ustawia też domyślny poziom TC.

| Tryb | Charakter | Skrzynia |
|---|---|---|
| ECO | mniej mocy, leniwy silnik, miękkie zawieszenie | wyższy bieg już od ~55% obrotów przy spokojnym gazie |
| KOMFORT | fabryczny handling | fabryczna |
| SPORT | +7% mocy, szybsze biegi, twardsze zawieszenie, TC SPORT | trzyma bieg do 90% obrotów, redukuje poniżej 55% |
| SPORT+ | +12% mocy, bardzo szybkie biegi, najtwardsze zawieszenie, TC OFF | trzyma bieg do 97%, redukuje poniżej 68%, z międzygazem |
| DRIFT | większy kąt skrętu, mniej przyczepności, wymusza RWD (jeśli auto je ma), TC OFF | jak SPORT+ |

Jakie tryby ma dane auto, ustalasz w profilu (klasa albo konkretny model).

### Skrzynia biegów w trybach sportowych
Fabryczna skrzynia GTA wrzuca wyższe biegi bardzo wcześnie. W SPORT, SPORT+ i DRIFT skrypt nadpisuje ją co klatkę:
- **Kickdown od razu po przełączeniu trybu.** Skrzynia redukuje kilka biegów jeden po drugim
  (z międzygazem), aż obroty dojdą do ~80% w SPORT albo ~88% w SPORT+. Wyraźnie słychać, jak silnik wchodzi na obroty.
- **Bieg zostaje do wysokich obrotów**, także przy lekkim gazie.
- **Wczesna redukcja.** Gdy obroty spadną (hamowanie przed zakrętem, spokojniejsza jazda), skrzynia
  zbija bieg, więc silnik cały czas „siedzi” wysoko. W SPORT+ obroty trzymają się między ~70% a ~95%.
- **Po puszczeniu gazu bieg zostaje.** Auto hamuje silnikiem i na wyjściu z zakrętu od razu ma moc.

Wszystkie progi ustawisz w `Config.Modes[...].gearbox`. `Config.Gearbox.enabled = false` przywraca fabryczną skrzynię.

### Napęd FWD / RWD / AWD
Działa tylko w autach, które mają to w profilu (`drive = { 'AWD', 'RWD' }` itp.). Przełączasz przy
małej prędkości (domyślnie do 15 km/h), a na czas zmiany moc jest przez chwilę odcinana. Skrypt ustawia
`fDriveBiasFront` i flagi napędzanych kół (`SetVehicleWheelIsPowered`).

> **Ograniczenie silnika gry:** koło dostaje moment tylko wtedy, gdy handling auta w ogóle przewiduje napęd na
> tę oś. Fabryczne AWD z GTA (Sultan, Kuruma, Elegy, terenówki) przełączają się bez zmian.
> Jeśli chcesz przełączać auto fabrycznie FWD na RWD (albo odwrotnie), ustaw mu w `handling.meta`
> `fDriveBiasFront` między `0.1` a `0.9`, np. `0.5`.

### Blokady dyferencjałów
Trzy poziomy: **TYŁ**, **TYŁ + CENTR.** i **WSZYSTKIE**. Każdy poziom zmniejsza buksowanie przy ruszaniu
i utratę przyczepności w terenie, ale auto gorzej skręca. Blokada centralna wymusza AWD z równym
rozkładem. Blokady da się załączyć do 25 km/h, a powyżej 40 km/h rozłączają się same. Jak w prawdziwych
terenówkach, blokada wyłącza TC.

### Reduktor (4L)
Załączasz go, stojąc. Skraca przełożenia (`fInitialDriveMaxFlatVel`), dodaje momentu i ogranicza
prędkość do 55 km/h. Jeśli auto może mieć AWD, reduktor je wymusza.

### Kontrola trakcji
Porównuje prędkość najszybszego napędzanego koła z prędkością auta. Gdy poślizg przekroczy próg,
płynnie odcina moc: szybko ją zabiera i łagodnie oddaje. **TC** łapie już małe poślizgi, **TC SPORT**
pozwala na sporo więcej, **OFF** wyłącza system. Na HUD-zie kontrolka TC miga, kiedy system ingeruje.

### Launch control
Uzbrój go (`NUM5` albo panel), zatrzymaj auto, wciśnij **hamulec + gaz**. Obroty stoją na ~70%.
Puść hamulec: przez ok. 2,5 s auto ma więcej momentu i agresywną kontrolę trakcji.

### Tempomat i ogranicznik
Tempomat trzyma prędkość, dozując gaz. Możesz dogazować, żeby wyprzedzić, a po puszczeniu gazu
tempomat wraca do zadanej prędkości. Hamulec albo ręczny wyłącza go. Ogranicznik nie pozwala
przekroczyć ustawionej prędkości. Obie wartości zmieniasz klawiszami `PGUP` / `PGDN` albo w panelu.

### Zawieszenie pneumatyczne
Poziomy **NISKO / NORMAL / WYSOKO / TEREN**. Zmieniają wysokość auta, którą widzą wszyscy gracze,
oraz sztywność zawieszenia. Nisko jest twardo, a w terenie miękko i z dużym prześwitem.
Przy większej prędkości zawieszenie samo zjeżdża do NORMAL (WYSOKO powyżej 90 km/h, TEREN powyżej 50 km/h).

### Kierunkowskazy, pasy, silnik
- Kierunkowskazy są widoczne dla wszystkich i gasną same po skręcie. W środku słychać tykanie.
- Pasy: zapięte blokują wysiadanie. Bez pasów przy zderzeniu powyżej 90 km/h wypadasz przez szybę.
  Powyżej 20 km/h bez pasów słychać gong.
- Silnik: wyjście z auta go nie gasi. Wyłączasz go osobnym klawiszem.

## Panel (F7)
Pokazuje prędkość, bieg, obroty, pasek mocy (widać na nim odcięcie TC i boost launcha) i schemat kół.
Koła napędzane świecą na bursztynowo, a buksujące na czerwono. Poniżej są przełączniki wszystkich
systemów dostępnych w aucie. Niedostępne sekcje są ukryte, a zablokowane opcje wyszarzone z opisem, dlaczego.

Panel można obejrzeć bez gry: otwórz `html/index.html` w przeglądarce (tryb demo).

## Konfiguracja profili
Profil auta składa się z trzech warstw: `Config.DefaultProfile` → `Config.ClassProfiles[klasa]` → `Config.Vehicles[model]`.

```lua
Config.Vehicles = {
    sandking = { drive = { 'RWD', 'AWD' }, diff = 3, lowRange = true, airSusp = true },
    sultanrs = { drive = { 'AWD', 'RWD', 'FWD' }, modes = { 'eco', 'comfort', 'sport', 'sportplus', 'drift' } },
    mojauto  = { modes = { 'comfort', 'sport' }, launch = true, awdBias = 0.35 },
}
```

| Pole | Znaczenie |
|---|---|
| `modes` | dostępne tryby jazdy (id z `Config.Modes`) |
| `drive` | napędy do przełączania; pierwszy jest domyślny. `nil` = napęd fabryczny |
| `awdBias` | własny `fDriveBiasFront` w trybie AWD |
| `diff` | maks. poziom blokady (0–3) |
| `lowRange` | reduktor |
| `airSusp` | zawieszenie pneumatyczne |
| `launch` | launch control |

Własny tryb dodajesz w `Config.Modes` i dopisujesz do `Config.ModeOrder` oraz do profili.

## Eksporty (klient)
```lua
exports['dp-pojazdy']:GetState()     -- { mode, drive, diff, low, tc, susp } albo nil
exports['dp-pojazdy']:GetProfile()
exports['dp-pojazdy']:IsBelted()     -- do HUD-a
exports['dp-pojazdy']:GetCruise()    -- prędkość tempomatu albo nil
exports['dp-pojazdy']:GetLimiter()
exports['dp-pojazdy']:SetMode('sport')
exports['dp-pojazdy']:SetDrive('AWD')
exports['dp-pojazdy']:ToggleBelt()
```
Powiadomienia możesz podpiąć pod ox_lib i inne systemy, podmieniając `Car.Notify` w `client/core.lua`.

## Wydajność
- Poza autem skrypt robi jedno sprawdzenie co 500 ms.
- Pasażer bez pasów przy małej prędkości: pętla co 100 ms.
- Kierowca: jedna pętla co klatkę z kilkoma tanimi natywkami (TC, tempomat, launch). Cięższe rzeczy
  (autowyłączanie blokad, zawieszenie, kierunkowskazy) działają co 100 ms.
- Handling jest przeliczany **tylko przy zmianie ustawienia**, nie co klatkę. Po wyjściu z auta
  wraca do oryginału.
- HUD dostaje dane tylko wtedy, gdy coś się zmieniło. Telemetria idzie (10 Hz) tylko przy otwartym panelu.
- Serwer tylko sprawdza poprawność state bagów i odrzuca śmieci od zmodyfikowanych klientów.

## Uwagi
- `ModifyVehicleTopSpeed(veh, 0.0)` jest wywoływane po każdej zmianie handlingu (bez tego gra nie
  przeładowuje skrzyni i napędu). Jeśli inny skrypt ustawia autu `ModifyVehicleTopSpeed`, trzeba go wywołać ponownie po zmianie trybu.
- Wartości w configu są dobrane pod auta z GTA. Auta addonowe mogą potrzebować innych mnożników.
  `Config.Debug = true` i komenda `/dpcar_debug` wypisują aktualny handling i stan auta.
