# dp-spawacz – praca spawacza dla FiveM

Praca spawacza z rozbudowaną, wieloetapową minigrą w NUI. Gracz nie „przeciąga myszką po linii”:
najpierw ustawia spawarkę według karty WPS, potem czyści detal, sczepia go albo nawierca otwory
zatrzymujące pęknięcie, spawa kilkoma ściegami (pilnuje przy tym łuku, prędkości, ciepła, drżenia
ręki i materiałów), czyści spoinę, a na końcu inspektor robi odbiór z radiogramem RTG.
**Im lepsza spoina, tym wyższa wypłata.**

- Frameworki: **ESX, QBCore, QBox** (wykrywane automatycznie) albo standalone
- Interakcja: **ox_target / qb-target** albo klasyczne `[E]`
- Zapis postępów: KVP zasobu, **bez bazy danych**
- Zero plików audio i obrazków: grafika jest rysowana na canvasie, dźwięk syntezowany przez WebAudio

---

## Rozgrywka

### Zlecenia i progresja
1. U brygadzisty w bazie otwierasz tablet i wybierasz jedno z 3 zleceń (miejsce, 2–4 spawy, szacowany zarobek).
2. Dostajesz auto służbowe za kaucją. Kaucja wraca proporcjonalnie do stanu auta.
3. Stanowiska pracy są na mapie, a na miejscu stoją rekwizyty (rury, blachy, zbiorniki).
4. Każdy spaw płaci od razu, zależnie od jakości. Po powrocie do bazy z kompletem dostajesz premię **+20%**.
5. Doświadczenie odblokowuje kolejne rzeczy:

| Poziom | Stopień | Odblokowuje |
|---|---|---|
| 1 | Praktykant | MMA, stal węglowa, pozycja PA, pęknięcia i spoiny pachwinowe |
| 2 | Spawacz | MIG/MAG, pozycja PF (pionowa), złącza doczołowe |
| 3 | Spawacz certyfikowany | TIG, stal nierdzewna, łaty na zbiornikach |
| 4 | Spawacz specjalista | aluminium, pozycja PE (pułapowa) |
| 5 | Mistrz spawalnictwa | najwyższy mnożnik stawek |

### Etapy minigry
| # | Etap | O co chodzi |
|---|---|---|
| 1 | **Karta WPS i spawarka** | Z karty (materiał, grubość, metoda, pozycja) i ściągawki wyliczasz natężenie prądu, biegunowość (DC+, DC−, AC) i parametr dodatkowy: średnicę elektrody, posuw drutu albo przepływ argonu. Masz 3 próbne zajarzenia na złomie. Pokazują, jak wygląda ścieg, i podpowiadają, co jest nie tak („łuk zimny”, „wolfram się topi”, „drut stuka”…). |
| 2 | **Przygotowanie** | Szlifierką (LPM) zdejmujesz rdzę i farbę, odtłuszczaczem (PPM) olej. Szlifowanie po oleju go rozmazuje, a trzymanie tarczy w jednym miejscu robi podcięcia. Brud zostawiony w strefie spawania daje później **pory**. |
| 3a | **Penetrant i otwory** (pęknięcia) | Czerwony penetrant pokazuje, że rysa jest dłuższa, niż widać. Za jej końcami wiercisz otwory. Wiertarka ucieka, SHIFT stabilizuje rękę, ale męczy. |
| 3b | **Sczepianie** (złącza, łaty) | Sczepy zakładasz w kolejności „na krzyż”, w rytm zwężającego się pierścienia. Złe sczepy odkształcają detal i poszerzają szczelinę do wypełnienia. |
| 4 | **Spawanie** (1–3 ściegi) | Opis niżej. |
| 4½ | **Żużel między ściegami** (MMA) | Kawałek żużla, którego nie odbijesz, staje się **wtrąceniem** w następnym ściegu. |
| 5 | **Czyszczenie** | Młotek na żużel, skrobak na odpryski (to efekt Twojego łuku), szczotka na naloty i przebarwienia. Za złe narzędzie tracisz czas i punkty. |
| 6 | **Odbiór** | Protokół z ocenami etapów i listą niezgodności, zdjęcie spoiny i **radiogram RTG** (TAB), pieczątka z oceną S/A/B/C/D/F i wypłata. |

### Spawanie – serce minigry
Podczas prowadzenia palnika pilnujesz naraz kilku rzeczy:
- **Długość łuku (kółko myszy).** Łuk sam dryfuje. W MMA elektroda się skraca, więc łuk się wydłuża i trzeba go dociskać. Za krótki: elektroda przywiera (MMA, stukaj SPACJĘ), wolfram wpada w jeziorko (TIG, ostrzysz go klawiszem R) albo drut stuka o materiał (MAG). Za długi: pory, odpryski, a w końcu łuk gaśnie.
- **Prędkość posuwu.** Za wolno: przegrzanie, **przepalenie** (dziura) albo spływające jeziorko w pozycjach PF/PE. Za szybko: brak przetopu.
- **Ciepło.** Lokalne ciepło jeziorka i temperatura całego detalu. Przed kolejnym ściegiem trzeba zejść do temperatury międzyściegowej (klawisz C dmucha sprężonym powietrzem).
- **Przyłbica samościemniająca.** Kiedy łuk się pali, widać tylko okolicę jeziorka, więc trasę warto zaplanować przed zajarzeniem.
- **Drżenie ręki.** Rośnie z trudnością, pozycją i zmęczeniem. SHIFT stabilizuje, ale ma ograniczoną wytrzymałość.
- **Materiały:** wymiana elektrody (MMA), czyszczenie zapchanej dyszy (MAG), rytmiczne dodawanie spoiwa SPACJĄ z oceną rytmu (TIG).
- **Ściegi wypełniające i licowe** prowadzi się **zakosami** od krawędzi do krawędzi rowka. Niepokryte brzegi to **podtopienia**.
- **Zdarzenia losowe:** podmuch wiatru szarpie łuk (w MAG i TIG zdmuchuje też osłonę gazową), gęsty dym ogranicza widoczność.

Wszystkie trzy metody grają się inaczej, a materiały różnią się przewodnością cieplną, odpornością na przepalenie i idealną prędkością.

### Ocena i wypłata
Wagi etapów: WPS 10%, przygotowanie 15%, otwory lub sczepy 10%, spawanie 55%, czyszczenie 10%. Każde przepalenie obniża maksymalną możliwą ocenę.

```
wypłata = baza × typ × materiał × pozycja × metoda × (1 + 18%·dodatkowe ściegi) × (1 + 10%·(trudność−1))
          × mnożnik poziomu × (0,3 + 0,9·(jakość/100)^1,5) × (1 + premia za ocenę: S +25%, A +10%)
```
Ocena **F** oznacza odrzucenie spoiny: brak wypłaty, ale można podejść jeszcze raz (`Config.Payment.maxAttempts`).

---

## Instalacja
1. Wrzuć folder `dp-spawacz` do `resources/`.
2. Dodaj do `server.cfg` **po** frameworku i targecie:
   ```
   ensure dp-spawacz
   ```
3. Opcjonalnie: ustaw `Config.Job.required = true` i dodaj pracę `welder` do frameworka.
4. **Sprawdź koordynaty** w `config.lua` (`Config.Depot`, `Config.Sites`) na swojej mapie. Wysokość Z jest automatycznie dociągana do gruntu, ale X i Y muszą wskazywać sensowne miejsca. Po włączeniu `Config.Debug = true` komenda `/spawacz_pos` wypisuje gotowy `vec4(...)` z Twojej pozycji.

### Podgląd minigry w przeglądarce (bez serwera)
Otwórz `html/index.html` w Chrome. W trybie demo minigra startuje od razu, a parametry możesz zmieniać w adresie:
```
index.html?proc=TIG&mat=stainless&type=patch&passes=1&diff=3
index.html?proc=MMA&type=crack&passes=2&pos=vertical
index.html?proc=MAG&type=butt&passes=3&th=10&diff=4
index.html?tablet=1          ← podgląd tabletu
```
`proc` = MMA | MAG | TIG, `mat` = steel | stainless | aluminium, `type` = crack | butt | fillet | patch,
`pos` = flat | vertical | overhead, `diff` = 1–5.

---

## Konfiguracja (najważniejsze)
| Klucz | Opis |
|---|---|
| `Config.Framework` | `auto` / `esx` / `qb` / `qbx` / `standalone` |
| `Config.UseTarget` | ox_target / qb-target, jeśli są uruchomione |
| `Config.Job` | wymagana praca (domyślnie każdy może pracować) |
| `Config.Vehicle` | model auta, kaucja, promień zwrotu |
| `Config.Levels`, `Config.XP` | progi XP, nazwy stopni, mnożniki stawek |
| `Config.Processes / Materials / Positions / Types` | odblokowania (`minLevel`) i mnożniki stawek |
| `Config.Payment` | stawka bazowa, premie, liczba podejść |
| `Config.Scoring` | wagi etapów i progi ocen (**muszą zgadzać się z `html/js/data.js`**) |
| `Config.Security` | limity czasu i odległości przy walidacji wyniku |
| `Config.Sites` | miejsca pracy: poziom, liczba zadań, stanowiska i dozwolone typy spawów |

Integracje z kluczykami, paliwem i powiadomieniami są w `client/hooks.lua`. Obsługiwane od razu: qb-vehiclekeys, qbx_vehiclekeys, wasabi_carlock, ox_fuel, LegacyFuel, cdn-fuel.

## Bezpieczeństwo
- Zadania, seedy detali i tokeny sesji generuje **serwer**. Każdy token jest jednorazowy.
- Serwer sam liczy jakość z wag, przycina wszystkie wartości i sprawdza minimalny i maksymalny czas minigry oraz odległość gracza od stanowiska na starcie i na końcu.
- Wypłaty, kaucje i XP są tylko po stronie serwera. Callbacki mają limit częstotliwości.
- Podejrzane wyniki są odrzucane i logowane w konsoli serwera.

## Wydajność
- Bez aktywnego zlecenia działa tylko jedna pętla bazy, która śpi 1,5 s, gdy jesteś daleko.
- Pętla zlecenia śpi 400–1000 ms i przechodzi w tryb klatka po klatce tylko w promieniu 30 m od stanowiska (marker). Z targetem nie ma nawet sprawdzania klawisza.
- Brygadzista i rekwizyty są spawnowane lokalnie i tylko w pobliżu, a potem usuwane.
- NUI renderuje tylko w trakcie minigry. Cząsteczki siedzą w typowanych tablicach (bez śmieci dla GC), a zdarzenia „łuk włączony/wyłączony” idą do Lua tylko przy zmianie stanu.

## Eksporty i zdarzenia (serwer)
```lua
exports['dp-spawacz']:GetWelderLevel(source)       -- poziom 1..5
exports['dp-spawacz']:AddWelderXP(source, amount)  -- dodaj/odejmij XP

AddEventHandler('dp-spawacz:taskFinished', function(src, data)
    -- data = { quality, grade, pay, type }
end)

-- standalone: podepnij własną ekonomię
AddEventHandler('dp-spawacz:standalone:addMoney', function(src, account, amount, reason) end)
```

## Sterowanie (skrót)
| Klawisz | Działanie |
|---|---|
| LPM | łuk / szlifierka / wiercenie / sczep / narzędzie |
| PPM | odtłuszczacz |
| Kółko | długość łuku, zmiana narzędzia |
| SHIFT | stabilizacja ręki |
| SPACJA | spoiwo TIG / odrywanie elektrody / start etapu |
| R | nowa elektroda / czyszczenie dyszy / ostrzenie wolframu |
| C | chłodzenie detalu sprężonym powietrzem |
| 1 2 3 | młotek / skrobak / szczotka |
| TAB | zdjęcie / radiogram w protokole |
| ENTER | zakończ etap |
| ESC | przerwij (z potwierdzeniem) |
| `/spawacz` | tablet (można przypisać klawisz w ustawieniach FiveM) |
