# dp-wlamywacz – włamania do domów dla FiveM

Włamania inspirowane **Thief Simulatorem**: rekonesans lornetką i notatnik, zamki różnych klas i wytrychy, domownicy z planem dnia i snem, kamery, alarmy z opóźnieniem wejścia, bezpieczniki, łup noszony w torbie i w rękach, paserzy, policja z dowodami i ekipy do 4 osób.

To jest **zestaw startowy (MVP)** z katalogu `POMYSLY.md`: wszystkie 150 pomysłów oznaczonych `MVP`. Grywalny prototyp minigier zamków jest w `prototyp/zamki.html`.

- Frameworki: **ESX, QBCore, QBox** (wykrywane automatycznie) albo standalone
- Ekwipunki: **ox_inventory, qb-inventory, qs-inventory, ESX** (łup trzyma własna torba skryptu, więc działa z każdym)
- Interakcja: **ox_target / qb-target** albo wbudowane `[E]`
- Dispatch: **ps-dispatch, cd_dispatch, core_dispatch, qs-dispatch, rcore_dispatch** albo wbudowany
- Zapis: KVP zasobu, **bez bazy danych**
- Zero plików audio i grafik: minigry rysuje canvas, dźwięk syntezuje WebAudio

---

## Jak wygląda skok

1. **Wiktor** (blip na mapie) wprowadza cię w robotę: daje drut i shim, wysyła maile z kolejnymi krokami samouczka i płaci za zlecenia na konkretne przedmioty.
2. **Rekonesans.** Lornetka (klawisz `1` przy celu) po 3 s obserwacji zapisuje w notatniku, kto jest w domu i kiedy wychodzi albo śpi. Obchód domu zapisuje wejścia, klasę zamków, uchylone okna i kontaktrony. Możesz też zadzwonić do drzwi i obejrzeć naklejkę ochrony (bywa blefem).
3. **Wejście.** Każdy dom ma kilka wejść. Do wyboru: wytrych (minigra „punkt”), grabie, łom, zbicie albo wycięcie szyby, drut przez uchylone okno, ukryty klucz pod wycieraczką. Furtka blokuje wejścia od ogrodu. Bezpieczniki odcinają prąd.
4. **W środku** (osobna instancja dla ekipy):
   - Domownicy śpią albo nie. Słyszą hałas przez ściany i drzwi, widzą cię w zależności od światła i latarki, idą sprawdzić, co się dzieje, i mogą zadzwonić na policję. Telefon da się im wytrącić.
   - Psy szczekają.
   - Kamery patrzą i się obracają, rejestrator można zabrać. Panel alarmu odlicza czas na kod: starte klawisze widać w świetle latarki, a kod bywa zapisany na kartce w biurku.
5. **Łup.** Przeszukujesz meble, bierzesz przedmioty z półek, a telewizor czy komputer niesiesz w rękach do bagażnika. Zamknięte szuflady otwierasz wytrychem albo łomem. Jest też sejf na stetoskop.
6. **Ucieczka i ocena S–F.** Liczą się czas, hałas, wykrycia, odciski palców, nagrania, alarm i policja. Ocena mnoży XP.
7. **Paser** (co dzień w innym miejscu) kupuje łup z torby i z bagażnika za brudną gotówkę. Reputacja podnosi ceny. Lombard płaci czysto, ale gorącego towaru nie weźmie i może zadzwonić na policję.
8. **Policja** dostaje dispatch z opisem sprawcy od świadków. Na miejscu zabezpiecza ślady: odciski, krew, ślady łomu, nagrania, auto zaparkowane pod domem. Może sprawdzić łup przy zatrzymanym i go skonfiskować.

## Instalacja

1. Wrzuć folder `dp-wlamywacz` do `resources/` i dodaj `ensure dp-wlamywacz` w `server.cfg` **po** frameworku, ekwipunku i targecie.
2. Dodaj przedmioty narzędzi do swojego ekwipunku (lista niżej). Na serwerze testowym możesz ustawić `Config.RequireItems = false`.
3. **Sprawdź koordynaty** (patrz „Domy i wnętrza”). Przykładowe domy w `config/houses.lua` i punkty wnętrza w `config/interiors.lua` wpisałem z pamięci mapy: trzeba je potwierdzić na serwerze.
4. Opcjonalnie: ustaw `Config.Police.minOnline`, cooldowny, liczbę celów w rotacji i paserów w `config.lua`.

### Przedmioty (nazwy w `Config.Items`)

`wlm_wytrych_drut`, `wlm_wytrych_stal`, `wlm_wytrych_tytan`, `wlm_wytrych_pro`, `wlm_grabie`, `wlm_shim`, `wlm_lom`, `wlm_noz_szklo`, `wlm_nozyce`, `wlm_srubokret`, `wlm_drut`, `wlm_latarka`, `wlm_lornetka`, `wlm_laptop`, `wlm_rekawiczki_lateks`, `wlm_rekawiczki_skora`, `wlm_rekawiczki_takt`, `wlm_maska`, `wlm_worek`, `wlm_plecak`, `wlm_torba`

**ox_inventory** (`data/items.lua`) – przedmioty używalne z ekwipunku wołają eksport skryptu:
```lua
['wlm_laptop']    = { label = 'Laptop', weight = 1500, stack = false, client = { export = 'dp-wlamywacz.useItem' } },
['wlm_lornetka']  = { label = 'Lornetka', weight = 600, client = { export = 'dp-wlamywacz.useItem' } },
['wlm_latarka']   = { label = 'Latarka', weight = 300, client = { export = 'dp-wlamywacz.useItem' } },
['wlm_rekawiczki_lateks'] = { label = 'Rękawiczki lateksowe', weight = 20, client = { export = 'dp-wlamywacz.useItem' } },
['wlm_wytrych_stal'] = { label = 'Wytrych stalowy', weight = 30 },
['wlm_lom']       = { label = 'Łom', weight = 1500 },
-- … pozostałe analogicznie
```
**ESX / QBCore:** dodaj przedmioty jak zwykle. Laptop, lornetka, latarka i rękawiczki rejestrują się jako używalne automatycznie.

Łup (**telewizor, laptop, biżuteria…**) nie jest przedmiotem ekwipunku. Trzyma go torba skryptu: każdy przedmiot ma unikalne ID, dom pochodzenia i czas kradzieży. Dzięki temu nie da się go zdupować, a policja może go sprawdzić.

## Domy i wnętrza

- `config/houses.lua` – domy (wejścia na fasadzie, ukryte klucze, bezpieczniki, dzielnica, poziom) i szopy do samouczka. **Szopy działają od razu**, bo skrzynię spawnuje skrypt.
- `config/interiors.lua` – szablony wnętrz. Domyślny `studio` to wnętrze GTA „low-end apartment” pod mapą, które w routing buckecie może obsłużyć wiele włamań naraz. Obsługiwane są też shelle (`type = 'shell'`, np. K4MB1).
- Każdy szablon ma **pokoje** (materiał podłogi, okno na ulicę, graf przejść dla hałasu) i **punkty**: meble do przeszukania, sloty łupu, sejf, włączniki, kryjówki, łóżka, panel alarmu, rejestrator, kamery, wyjścia.

**Poprawianie punktów.** Ustaw `Config.Debug = true`. W domu skrypt rysuje pokoje i punkty, a:
- `/wlm_punkt search wardrobe` wypisuje gotową linijkę z pozycją **względną** do wnętrza (typy: `search`, `loot`, `light`, `hide`, `bed`, `sit`, `camera`, `exit`…),
- `/wlm_dom moj_dom` poza domem wypisuje szablon nowego domu z twoją pozycją jako drzwiami.

## Sterowanie

| Klawisz / komenda | Działanie |
|---|---|
| `1` `2` `3` `4` (przy celu lub w domu) | lornetka, latarka, rękawiczki, laptop |
| `H` | latarka · `/wlm_filtr` – czerwony filtr |
| `Z` | koło sygnałów ekipy |
| `/wlm_laptop` | laptop: profil, notatnik, czarny rynek, poczta, torba, ekipa |
| `/wlm_ekipa zapros <id>` · `akceptuj` · `opusc` | ekipa |
| `G` (niosąc przedmiot) | odłóż · `E` przy bagażniku – włóż do bagażnika |
| `SPACJA` (w kryjówce) | wstrzymaj oddech, gdy ktoś jest blisko |
| `/wlm_slady` · `/wlm_sprawdz [id]` · `/wlm_zabierz [id]` | policja: ślady w domu, sprawdzenie łupu, konfiskata |

Wszystkie klawisze możesz zmienić w ustawieniach FiveM (`RegisterKeyMapping`).

## Wydajność

| Stan | Co działa |
|---|---|
| Daleko od celów | jedna pętla co 1,5 s licząca dystans do ~10 aktywnych domów |
| Przy domu | pętla co 0,5 s (obchód, syrena), strefy targetu bez pętli |
| W domu | koordynator co 250 ms; pętla klatkowa tylko gdy: niesiesz przedmiot, latarka świeci, jesteś w kryjówce albo w pobliżu kamery |
| Minigra | cała logika i rysowanie w NUI; Lua czeka na wynik |

- **AI domowników** liczy tylko host ekipy, jeden koordynator na dom co 250 ms. Percepcja: najpierw dystans², potem stożek widzenia, a na końcu asynchroniczny raycast. Pedy dostają natywne taski.
- **Hałas** propaguje BFS po grafie pokoi tylko przy zdarzeniu i trafia do serwera w paczkach (max 4 na sekundę).
- **Obrót kamer** liczony jest z czasu sieciowego, więc nie wymaga synchronizacji.
- **Serwer** działa zdarzeniowo. Heat i ceny zanikają leniwie ze wzoru, a zapis KVP idzie paczką co minutę.
- **NUI** zmienia HUD tylko przy zmianie wartości, a `requestAnimationFrame` działa wyłącznie w trakcie minigry.

## Bezpieczeństwo

- Każda minigra i akcja z czasem trwania ma **jednorazowy token** z minimalnym i maksymalnym czasem. Serwer sprawdza też dystans gracza (pozycja z OneSync).
- **Kody** alarmu i sejfu porównuje wyłącznie serwer. NUI dostaje tylko starte cyfry, bez kolejności.
- **Łup, gotówkę, XP i ceny** liczy serwer. Limity dzienne obowiązują na postać i na serwer, a callbacki mają limit częstotliwości.
- Podejrzane wyniki trafiają do logów (`dp-wlamywacz:suspicious`).

## Eksporty i zdarzenia (serwer)

```lua
exports['dp-wlamywacz']:GetBurglarLevel(source)
exports['dp-wlamywacz']:AddBurglarXP(source, amount)
exports['dp-wlamywacz']:ArrestPlayer(source)        -- konfiskata łupu i narzędzi + kara w progresji
exports['dp-wlamywacz']:GetHouseEvidence(houseId)   -- ślady do własnego MDT

AddEventHandler('dp-wlamywacz:dispatch', function(data) end)   -- każde zgłoszenie
AddEventHandler('dp-wlamywacz:log', function(kind, msg) end)
AddEventHandler('dp-wlamywacz:standalone:addMoney', function(src, account, amount, reason) end)
```
Pora dnia: serwer bierze zegar gracza (synchronizowany przez skrypty pogody). Własne źródło podasz jako funkcję `Config.GameTime = function() return h, m end`.

## Podgląd NUI w przeglądarce

Otwórz `html/index.html`. Panel po lewej uruchamia każdą minigrę, HUD, laptop, paser, dialog, raport i lornetkę. Minigrę można też otworzyć od razu z adresu:
```
index.html?game=lockpick&cls=C   index.html?game=safe&cls=B   index.html?game=keypad   index.html?win=laptop
```

## Uproszczenia względem opisów w katalogu

- **WEJ-16:** ślady włamania (wyłamane drzwi, zbita szyba) są stanem domu. Widzą je świadkowie, domownik wracający do domu i policja, ale skrypt nie spawnuje propów odłamków.
- **REK-15:** deszcz tłumi hałas, a w nocy domownicy śpią. Grzmot maskujący zbicie szyby i mgła skracająca wzrok jeszcze nie działają.
- **UIX-04:** notatnik to lista wpisów z oceną domu, bez graficznej osi czasu 24 h.
- **SKR-08:** latarkę widzi ekipa w domu, ale przechodnie na ulicy jeszcze nie.
- **Wnętrza:** wszystkie przykładowe domy korzystają z jednego szablonu `studio`. Kolejne szablony, także shelle, dodaje się samymi danymi w `config/interiors.lua`.

## Co jest sprawdzone, a co nie

- **Sprawdzone.** Cały Lua przechodzi `luac` i ładuje się w kolejności z manifestu. Czysta logika (generator profili domów, harmonogramy, graf hałasu, RNG) ma testy. Pełny przebieg serwera na atrapach natywek FiveM też został przetestowany: wytrych, wejście, przeszukanie, łup, sejf, alarm z kodem, bezpieczniki, wyjście, raport, cooldown, ślady i paser. NUI przeszło test w przeglądarce, bez błędów JS.
- **Niesprawdzone.** Skrypt nie był jeszcze uruchomiony na serwerze FiveM. Do potwierdzenia w grze:
  - koordynaty domów i punktów wnętrza,
  - nazwy animacji i propów,
  - zachowanie pedów domowników w instancji,
  - integracje z dispatchami i ekwipunkami, które piszę według ich dokumentacji.
