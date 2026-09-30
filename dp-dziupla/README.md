# dp-dziupla – dziupla (chop shop) dla FiveM

Rozbiórka aut **śruba po śrubie**, jak w *Car Mechanic Simulator* i *Thief Simulator*. Kamera najeżdża na
prawdziwe auto w grze, a na nim pojawiają się śruby, nakrętki, klipsy, wtyczki, węże, korki spustowe
i linie cięcia (NUI rzutuje je z 3D na ekran). Każdy element ma własną mechanikę i wpływa na stan
zdjętej części, a stan przekłada się na cenę.

Rozbiórka to tylko część zabawy. Dochodzą: kradzież na zlecenie (wytrych, alarm, nadajniki GPS),
magazyn i dynamiczny rynek części, zamówienia klientów z dostawą, eksport całych aut w kontenerze,
przebitka VIN z lakiernią i handlarzem, zgniatarka, regeneracja części na stole, rozbieranie kół
na montażownicy, hałas i brama (jak w Thief Simulator), progresja i drzewko umiejętności.

- Frameworki: **ESX, QBCore, QBox** (wykrywane automatycznie) albo standalone
- Interakcja: własny celownik na części + `[E]`; NPC przez **ox_target / qb-target**, jeśli są
- Zapis: KVP zasobu, **bez bazy danych** (oxmysql jest opcjonalny, tylko do sprawdzania aut graczy)
- Zero plików audio i obrazków: grafika na canvasie, dźwięki syntezowane przez WebAudio

---

## Rozbiórka krok po kroku

1. Wjedź autem na stanowisko w dziupli (pomarańczowe koło) i wciśnij **E**. Postać wysiada, auto staje na podnośniku.
2. Podejdź do auta. Na częściach widać znaczniki: **pomarańczowy** = można zdjąć, **szary** = coś blokuje, **czerwony** = ktoś przy tym pracuje.
3. Spójrz na część. Pokaże się nazwa, stan i czego brakuje („Najpierw: Zderzak przedni”, „Podnośnik na poziom 2”).
   - **E** – demontaż, **G** – oględziny (etykiety wszystkich części), **H** – podnośnik 0 → 1 → 2, **X ×2** – przerwij rozbiórkę.
4. Demontaż: kamera najeżdża na część, postać znika z kadru, a na aucie pojawiają się elementy złączne.
5. Gdy wszystko jest odpięte, przytrzymaj **SPACJĘ**. Część ląduje w rękach. Zanieś ją na **regał** (ciężkie, czyli silnik, skrzynia i złom, jadą wózkiem od razu do magazynu).

### Zależności jak w CMS
Części mają kolejność. Przykłady:
- **Reflektory** i **chłodnica** wymagają zdjętego zderzaka przedniego.
- **Hamulec** wymaga zdjętego koła, a **amortyzator** zdjętego hamulca.
- **Silnik** wymaga zdjętej maski, akumulatora, chłodnicy i turbo oraz spuszczonego oleju. Olej spuszcza się pod autem na podnośniku 2, a sam silnik wyjmuje się żurawiem na poziomie 0.
- **Skrzynia** wymaga wyjętego silnika i spuszczonego oleju przekładniowego.
- **Wydech** zdejmiesz dopiero po katalizatorze, a **zbiornik paliwa** po spuszczeniu paliwa.
- **Kierownica** wymaga zdjętej poduszki, a śruby **radia** są schowane pod klipsami ramki (warstwy).
- **Karoseria** (pocięcie na złom) jest dostępna dopiero po zdjęciu drzwi, maski, klapy, kół, silnika, skrzyni i zbiornika.
- **Podnośnik:** koła i hamulce na poziomie 1–2, podwozie (katalizator, wydech, zbiornik, spusty) na 2, wnętrze i silnik na 0.

### Lista części (≈35 na auto, zależnie od modelu i tuningu)
Tablica, 4 koła, 2 hamulce, 2 amortyzatory, do 4 drzwi, maska, klapa, spojler (jeśli jest), 2 zderzaki,
2 reflektory, 2 lampy tylne, akumulator, sterownik ECU, chłodnica, turbo (jeśli jest), silnik, skrzynia,
katalizator, wydech, zbiornik paliwa, 2 fotele, kanapa, radio, poduszka kierowcy, kierownica,
szyba czołowa, szyba tylna, a na koniec pocięcie karoserii. Do tego czynności: spuszczanie oleju i paliwa.

Tuning podnosi wartość: sportowe felgi, lepsze hamulce, zawieszenie, skrzynia, silnik (poziom), turbo,
ksenony, sportowy wydech, zderzaki i maska z tuningu. Zdjęcie tuningu jest widać na aucie.

Na aucie widać zdjęte drzwi, maskę, klapę, koła, szyby, turbo, spojler, tuningowane zderzaki i wydech oraz tablicę.

### Mechaniki elementów złącznych

| Element | Narzędzie | Na co uważać |
|---|---|---|
| **Śruba / nakrętka** | Grzechotka (1) lub udarowy (2), **dobór nasadki** kółkiem albo Q/E | Za duża nasadka ślizga się i **zaokrągla łeb**, za mała nie wejdzie. PPM = zmierz rozmiar. |
| **Zapieczona (rdza)** | Grzechotka impulsami | Wskaźnik momentu: trzymaj w **zielonym polu**, puść przed czerwonym. Za długo w czerwonym = **ukręcona śruba**. **Penetrant** (9) + 2,5 s = dwa razy łatwiej. Udarowy rozbija rdzę sam, ale jest głośny. |
| **Ukręcona / zaokrąglona** | Wiertarka (0) + wykrętak | Zużywa wykrętak, obniża stan części. |
| **Klema akumulatora** | Grzechotka | **Najpierw minus.** Plus przy podłączonym minusie = iskra (kara do stanu). |
| **Korek spustowy** | Grzechotka + **miska (B)** | Bez miski płyn leje się na posadzkę. Potem trzeba poczekać, aż spłynie. |
| **Wkręt** | Wkrętak (3), **dobór bitu** PH/Torx | Ruszanie myszą przy wkręcaniu = wyrobione gniazdo. |
| **Klips tapicerki** | Łyżka (4) | Podważ i pociągnij w kierunku strzałki. **Za szybko = pęka.** |
| **Wieszak wydechu** | Łyżka (4) | Dłuższe przeciągnięcie. |
| **Wtyczka** | Ręka (6) | Przytrzymaj (zatrzask), potem wyciągnij. Szarpnięcie bez zatrzasku = urwana wtyczka. **Żółta = poduszka powietrzna**: przy podłączonym akumulatorze **wystrzeli** (część zniszczona, postać leży). **Niebieska = elektronika**: zwarcie psuje ECU. |
| **Wąż z opaską** | Szczypce (5) albo ręka (wolniej, może się rozerwać) | Niespuszczony płyn (chłodniczy, paliwo, olej) **wyleje się**. |
| **Linia cięcia** | Szlifierka (7) / struna (8) do szyb | Prowadź po linii. Obok linii niszczysz część. Szlifierka zużywa tarcze i **iskry przy niespuszczonym paliwie mogą wywołać pożar**. |
| **Śruba do przecięcia** | Szlifierka | Szybciej niż odkręcanie zapieczonej śruby, ale część traci trochę stanu. Typowe dla katalizatora. |
| **Żuraw** | Klik + SPACJA/LPM w zielonym polu | Za duże kołysanie = silnik obija karoserię. |
| **Znak VIN** | Puncerzy (T) | Trzymaj LPM i puść, gdy pierścienie się zrównają. Od tego zależy jakość przebitki. |

Odkręcone elementy **zostają odkręcone**, jeśli odejdziesz od części (ESC). Klema minus i spuszczone płyny też są zapamiętane.

### Hałas i brama (Thief Simulator)
Szlifierka, klucz udarowy i młotek robią hałas. Przy otwartej bramie hałas niesie się po okolicy i po
przekroczeniu progu sąsiedzi mogą zadzwonić po policję. Zamknięta brama tłumi hałas do 30%.
Stan bramy i hałasu widać w HUD-zie stanowiska.

---

## Pozostałe zajęcia

### Laptop ChopNet
Stoi w dziupli (albo porozmawiaj z paserem). Zakładki:
- **Pulpit:** statystyki, zadania w toku, wydarzenie rynkowe, instrukcja.
- **Zlecenia:** lista życzeń (konkretne modele z premią) i eksport w kontenerze.
- **Magazyn:** filtry, sortowanie, zaznaczanie, sprzedaż paserowi i oddanie na złom według wagi.
- **Zamówienia:** klienci chcą konkretnych części w konkretnym stanie i płacą więcej.
- **Rynek:** popyt na kategorie z wykresem.
- **Sklep:** narzędzia, materiały, regały.
- **Umiejętności.**

### Kradzież na zlecenie
1. Bierzesz zlecenie (model, obszar na mapie, premia, ryzyko alarmu i nadajnika).
2. Gdy podjedziesz, auto pojawia się na parkingu w zaznaczonym obszarze (zamknięte).
3. Przy drzwiach kierowcy: **E** = **wytrych**, czyli minigra z zamkiem bębenkowym. Szukasz bolca, który stawia opór, podnosisz go do linii ścinania i puszczasz. Za wysoko = bolce spadają i wytrych się zużywa. **G** = wybicie szyby: szybko, ale zawsze włącza alarm.
4. Droższe auta mają **nadajnik GPS**: dopóki jedziesz, policja co 45 s dostaje namiar. Skanerem (**E** przy aucie albo `/skaner`) szukasz go na sylwetce auta po sygnale, sprawdzasz kryjówki i przecinasz przewód w kolorze diody.
5. Wstawienie auta na stanowisko wypłaca premię za zlecenie, a potem rozbierasz je normalnie.

Można też przyprowadzić **dowolne auto z ulicy**. Auta z garaży graczy są blokowane (sprawdzanie przez oxmysql w `server/hooks.lua`).

### Zamówienia klientów
Klient chce np. „4× Koło min. 60% + Fotel min. 45%”. Po przyjęciu części są rezerwowane w magazynie,
a ty wieziesz paczkę do punktu odbioru. Płacą 1,5–1,9× tyle co paser. Przy odbiorze może kręcić się policja.

### Eksport
Dostarczasz **całe auto** danej klasy w dobrym stanie do kontenera w porcie. Nic nie rozbierasz, liczy się szybkość i stan auta.

### Przebitka VIN, lakiernia i handlarz (poziom 6, puncerzy)
Na stanowisku przebitki: zeszlifuj stary numer, wybij nowy puncerem (8 znaków, jakość = precyzja uderzeń),
wymień tablice, wybierz kolor i dokup fałszywe papiery. Potem jedź do handlarza. Przy słabej przebitce
albo bez papierów handlarz może zadzwonić po policję. Opcjonalnie (`Config.Revin.allowKeep`) auto można zatrzymać.

### Zgniatarka
Wjedź na prasę i wciśnij **E**. Auto się zgniata, a ty dostajesz pieniądze za złom według klasy. To szybki
sposób na pozbycie się auta (albo gołej karoserii po przerwaniu rozbiórki).

### Stół warsztatowy i montażownica
- **Klepanie** (karoseria): przytrzymaj LPM, żeby wybrać siłę, i puść na wgnieceniu. Siła ma pasować do głębokości, za mocno = wybrzuszenie.
- **Czyszczenie** (mechanika, oświetlenie, wnętrze): szczotka na brud i wymiana zużytych uszczelek.
- **Montażownica:** wentyl, zbicie stopki w rytm, łyżka dookoła felgi. **Koło → felga + opona**, osobno warte więcej.

Każdą część można zregenerować raz, maksymalnie o +20 pkt stanu (umiejętność *Złota rączka* dodaje więcej).

### Rynek
Każda kategoria (karoseria, oświetlenie, koła, silnik, elektronika, wnętrze, wydech, szyby) ma popyt
0,55–1,5. Sprzedaż zbija popyt, a z czasem wraca on do normy. Co godzinę może wypaść **wydarzenie**,
np. „Boom na katalizatory +45%”. Popyt jest wspólny dla całego serwera i zapisywany w KVP.

---

## Progresja

10 poziomów (Złomiarz → Legenda półświatka) i 1 punkt umiejętności na poziom:

| Umiejętność | Efekt |
|---|---|
| Szybkie ręce (3) | +12% szybkości odkręcania na rangę |
| Pewna ręka (2) | -30% ryzyka zaokrąglenia, ukręcenia, pęknięcia klipsa |
| Cichociemny (2) | -25% hałasu |
| Negocjator (3) | +5% do cen |
| Oko fachowca (1) | Rozmiary śrub widoczne od razu, wycena części przy demontażu, +4% stanu |
| Złota rączka (2) | +10 pkt maksymalnej regeneracji |
| Włamywacz (2) | Szersza linia ścinania w zamkach, -35% szansy na alarm |
| Elektronik (1) | Szybszy skaner, o połowę mniejsze szkody od zwarć |
| Tragarz (1) | Bieganie z częściami |
| Kontakty (2) | +1 zlecenie w ofercie, +10% premii |

Narzędzia odblokowują się poziomami: szczypce, wiertarka, szlifierka, struna, klucz udarowy, żuraw,
skaner GPS, montażownica, puncerzy.

---

## Instalacja
1. Wrzuć folder `dp-dziupla` do `resources/`.
2. W `server.cfg` **po** frameworku (i oxmysql / targecie, jeśli ich używasz):
   ```
   ensure dp-dziupla
   ```
3. **Sprawdź koordynaty** w `config.lua` (`Config.Shops`, `Config.Contracts.spots`, `Config.Orders.drops`,
   `Config.Export.points`, `Config.Revin.dealer`). Z jest dociągane do gruntu, ale X/Y muszą pasować do
   Twojej mapy (MLO!). Z `Config.Debug = true` komenda `/dziupla_pos` wypisuje gotowy `vec4(...)`.
4. Opcjonalnie: `Config.Job.required = true`, żeby dziupla była tylko dla gangu/pracy z listy.

### Podgląd NUI w przeglądarce (bez serwera)
Otwórz `html/index.html` w Chrome z parametrem:
```
index.html?part=wheel      (także: radio, radiator, battery, airbag, engine, windscreen, catalyst, vin; &eye = perk)
index.html?laptop          (laptop=warehouse | contracts | orders | market | shop | skills)
index.html?lockpick&pins=6
index.html?scanner
index.html?bench=dents     (dents | clean | split)
index.html?paint   index.html?hud
```

---

## Konfiguracja (najważniejsze)
| Plik / klucz | Opis |
|---|---|
| `config.lua` → `Config.Shops` | dziuple: laptop, paser, regał, stół, montażownica, zgniatarka, brama, stanowiska, przebitka |
| `Config.Bay` | promień stanowiska, wysokości podnośnika |
| `Config.Levels`, `Config.Perks` | progresja i umiejętności |
| `Config.Tools`, `Config.Consumables`, `Config.Upgrades` | sklep |
| `Config.Economy`, `Config.ClassMult`, `Config.ModelMult` | ceny, mnożniki klas i modeli |
| `Config.Market` | popyt, odbudowa, wydarzenia |
| `Config.Noise` | hałas i brama |
| `Config.Contracts`, `Config.Tracker` | zlecenia kradzieży, poziomy, alarmy, nadajniki, miejsca aut |
| `Config.Orders`, `Config.Export`, `Config.Revin`, `Config.Crusher` | pozostałe zajęcia |
| `Config.Police` | wymagana liczba policji |
| `config_parts.lua` | **wszystkie części**: typy, wartości, kotwice (kości), mocowania, zależności, kamera, poziom podnośnika. Łatwo dodać własną część. |

### Dodanie własnej części
W `config_parts.lua` dopisz `add({...})` z kotwicą (`bone` albo `fb` = ułamek wymiarów auta),
listą `F` (typ, rozmiar, pozycja względem kotwicy), kamerą `cam` i ewentualnymi `requires`/`lift`.
Pozycje są w metrach w układzie auta: x = w bok (dla części bocznych „na zewnątrz”), y = do przodu, z = w górę.

## Integracje (`client/hooks.lua`, `server/hooks.lua`)
- **Kluczyki:** qb/qbx-vehiclekeys, wasabi_carlock, MrNewbVehicleKeys
- **Dispatch:** ps-dispatch, cd_dispatch, qs-dispatch, core_dispatch (inaczej podepnij własny)
- **Właściwości auta** (zatrzymanie po przebitce): ox_lib / QBCore / ESX
- **Auta graczy:** `ServerHooks.IsVehicleOwned` (owned_vehicles / player_vehicles przez oxmysql), `ServerHooks.GiveVehicle`
- Standalone: `AddEventHandler('dp-dziupla:standalone:addMoney', function(src, account, amount, reason) end)`

### Eksporty i zdarzenia (serwer)
```lua
exports['dp-dziupla']:GetLevel(source)
exports['dp-dziupla']:AddXP(source, amount)
exports['dp-dziupla']:AddPart(source, 'engine', 80, 1.2)   -- typ, stan, mnożnik wartości
exports['dp-dziupla']:GetWarehouse(source)

AddEventHandler('dp-dziupla:partRemoved', function(src, data) end)  -- { part, cond, vehicle }
AddEventHandler('dp-dziupla:earned', function(src, amount, reason) end)
```

## Bezpieczeństwo
- Serwer generuje zlecenia, rdzę śrub, VIN i tokeny sesji. Każdy token jest jednorazowy, a jeden gracz ma jedną sesję naraz.
- „Zdjęcie” auta z klienta jest przycinane i porównywane z modelem, który widzi serwer. Stan części liczy serwer; kary z minigry są ograniczone do sensownych zakresów.
- Minimalny czas demontażu zależy od liczby elementów. Sprawdzana jest odległość gracza od auta, stanowiska, regału i punktów.
- Materiały (penetrant, tarcze, wykrętaki, wytrychy) są odejmowane po stronie serwera, a pieniądze, XP, magazyn i rynek są tylko na serwerze.
- Blokada aut graczy, czarna lista modeli (radiowozy itp.), zablokowane klasy (motocykle, łodzie, samoloty...).

## Wydajność
- Poza dziuplą działa tylko pętla wykrywania lokacji (1 s) i pętla zleceń (1,5 s).
- Znaczniki części i celownik działają klatka po klatce tylko w promieniu ~7 m od rozbieranego auta.
- Rzutowanie śrub na ekran idzie co 40 ms podczas najazdu kamery, potem co 350 ms.
- NUI renderuje tylko w czasie minigry. HUD stanowiska aktualizuje się co 0,7 s, a hałas jest odpytywany co 3 s.
