# dp-wlamywacz – katalog pomysłów

Skrypt na włamania do domów dla FiveM, oparty na mechanikach z **Thief Simulatora**. Ten plik to **bank pomysłów do wyboru**, a nie specyfikacja: **437 pomysłów w 18 kategoriach** (150 `MVP`, 205 `v1`, 65 `v2`, 17 `extra`, 61 wprost z Thief Simulatora). Każdy pomysł ma swoje ID, więc wybieranie jest proste. Odpisz np.:

> `MVP całe + WYT-02, WYT-10, ZAB-21, NPC-22, POL-07` albo `REK-01…REK-12, bez REK-09`

`dp-wlamywacz` to nazwa robocza. Konwencje są takie jak w `dp-spawacz`: bridge ESX / QBCore / QBox / standalone, ox_target / qb-target albo `[E]`, minigry NUI na canvasie z dźwiękiem syntezowanym przez WebAudio (zero plików audio i grafik), serwer jako jedyne źródło prawdy, tokeny jednorazowe.

### Oznaczenia
| Znak | Znaczenie |
|---|---|
| 🎮 | mechanika z Thief Simulatora albo wprost w jej duchu |
| `MVP` | rdzeń: bez tego nie ma grywalnej pierwszej wersji |
| `v1` | premiera wersji „najlepszy skrypt na rynku” |
| `v2` | pierwsza duża aktualizacja |
| `extra` | opcja niszowa, eksperymentalna albo zależna od serwera (przełącznik w configu) |
| ⚡ | uwaga wydajnościowa: pomysł kosztuje więcej niż „nic”, obok jest opisane, jak zrobić go tanio. Pomysły bez ⚡ są praktycznie darmowe (zdarzeniowe, bez pętli). |

---

## 0. Zasady optymalizacji (obowiązują każdy pomysł)

1. **Maszyna stanów klienta zamiast stałych pętli.** Każdy stan ma własny budżet w resmonie:

   | Stan | Co działa | Cel resmon |
   |---|---|---|
   | `IDLE` (daleko od celów) | tylko strefy ox_lib (onEnter/onExit), **zero** wątków | 0.00 ms |
   | `NEAR` (ulica z celem, < 80 m) | 1 wątek co 500 ms (najbliższe punkty, props lokalne) | ≤ 0.01 ms |
   | `RECON` (lornetka/dron) | wątek co 100–200 ms tylko gdy narzędzie w użyciu | ≤ 0.03 ms |
   | `INSIDE` (w domu) | koordynator domu co 100–250 ms + pętla klatkowa **tylko** do klawiszy aktywnego narzędzia | ≤ 0.08–0.10 ms |
   | `MINIGAME` | cała logika w NUI (wątek przeglądarki), Lua śpi i czeka na wynik | ≤ 0.02 ms (Lua) |
2. **Serwer działa zdarzeniowo.** Stan istnieje wyłącznie dla *aktywnych* włamań. Nie ma pętli per gracz. Wartości, które maleją w czasie (heat, ceny, cooldowny), liczymy *leniwie przy odczycie* ze wzoru `v·e^(−Δt/τ)`, bez żadnego timera.
3. **Percepcja „najtańsze najpierw”.** Najpierw dystans², potem kąt stożka (iloczyn skalarny), dopiero na końcu **asynchroniczny** raycast `StartShapeTestLosProbe`. Ticki NPC są rozłożone w czasie (NPC 1 w ms 0, NPC 2 w ms 80…), więc nigdy nie liczą się wszystkie naraz.
4. **Hałas to zdarzenie, a nie ciągły pomiar.** Graf pokoi jest policzony z góry przy wczytaniu domu, a BFS rusza tylko wtedy, gdy coś zahałasuje. Zdarzenia są łączone w paczki (max 4/s).
5. **Encje lokalne i krótkotrwałe.** Propy łupu, pedy i kamery pojawiają się tylko w instancji (routing bucket), biorą się z puli, a przy wyjściu, rozłączeniu gracza i `onResourceStop` są sprzątane. `SetModelAsNoLongerNeeded` zawsze po spawnie.
6. **Synchronizacja oszczędna.** Stan drzwi, alarmu i domu idzie przez statebagi encji albo eventy *tylko do członków ekipy*. `GlobalState` służy wyłącznie do małych liczników, nigdy do tabel domów.
7. **NUI.** Jeden iframe, moduły minigier ładowane leniwie, `requestAnimationFrame` zatrzymany, gdy UI jest ukryte, HUD dostaje wiadomość tylko przy zmianie wartości, a w gorących ścieżkach nie ma śmieci dla GC (typowane tablice).
8. **Żadnego `DrawText3D` co klatkę dla wielu punktów.** Target albo jeden podpowiadacz dla najbliższego punktu.
9. **Cel serwera:** poniżej 0,1 ms przy 10 równoczesnych włamaniach. Do mierzenia służy komenda testu obciążenia (TEC-12).

---

## Na szybko: funkcje flagowe (tym wygrywa się z konkurencją)

| # | Funkcja flagowa | Z czego się składa |
|---|---|---|
| 1 | **Żywy dom.** Domownicy mają plan dnia, fazy snu i nocne rutyny, a do tego zauważają zmiany: otwarte szuflady, zapalone światło, brak telewizora. | NPC-01…09, NPC-28, SKR-12 |
| 2 | **Notatnik złodzieja.** Oś czasu obecności domowników, plan domu odkrywany jak mgła wojny, oznaczone łupy i zabezpieczenia. | REK-01…04, REK-11, UIX-04, UIX-05 |
| 3 | **Prawdziwe zamki.** Klasy A/B/C, piny zabezpieczające, SPP, grabie, bump key, pick gun, sejf na stetoskop, keypad z UV. | ZAM-01…11, WYT-01…13 |
| 4 | **Zabezpieczenia jak z filmu o skoku.** Rejestrator z pętlą obrazu, bezpieczniki z UPS, kontaktron + magnes, podmiana ciężaru na gablocie, kamery IR widoczne tylko w noktowizorze. | ZAB-03, ZAB-08, ZAB-12, ZAB-17, ZAB-18, ZAB-21 |
| 5 | **Dowody i śledztwo dla policji.** Odciski, krew, ślady łomu i butów, nagrania, rejestr skradzionych przedmiotów. Policja dostaje własną rozgrywkę. | POL-03…11 |
| 6 | **Ekonomia gorącego towaru.** Numery seryjne, stygnięcie, czyszczenie, aukcje, ceny zależne od podaży na serwerze. | LUP-10, PAS-03…07 |
| 7 | **Ekipa z rolami.** Czujka z lornetką, wspólne minigry, noszenie sejfu we dwóch, podawanie łupu przez okno. | EKI-01…07 |
| 8 | **Edytor domów w grze.** Admin sam dodaje domy, pokoje, kamery i łupy, bez edytowania plików. | DOM-07, DOM-08, DOM-19 |
| 9 | **Presety Casual / Realistic / Hardcore.** Jeden przełącznik zmienia kilkadziesiąt parametrów. | TEC-20 |
| 10 | **0.00 ms poza akcją.** Twarde budżety resmonu opisane i dowiedzione testem obciążenia. | sekcja 0, TEC-01, TEC-12 |

Proponowany zestaw startowy (MVP) jest na samym końcu pliku.

---

## 1. REK – Rekonesans i wybór celu

- **REK-01 · Lornetka i obserwacja** `MVP` 🎮. Celujesz lornetką w domownika albo okno (kółko myszy to zoom, ręce lekko drżą). Po ~3 s obserwacji do notatnika wpada wpis, np. „Pan Nowak wychodzi do pracy ok. 7:40”. ⚡ _raycast co 200 ms, i tylko gdy lornetka jest w rękach_
- **REK-02 · Notatnik złodzieja** `MVP` 🎮. Automatyczny dziennik każdego domu: domownicy, harmonogram, kamery, psy, wejścia, łupy. Nieodkryte rzeczy mają status „???”. Dane trzyma serwer, osobno dla każdej postaci.
- **REK-03 · Oznaczanie łupów przez okno** `v1` 🎮. Lornetką oznaczasz przedmioty widoczne przez szybę. W środku mają obrys i pewne miejsce, a dom dostaje wyższą ocenę wartości.
- **REK-04 · Harmonogram z pewnością** `MVP` 🎮. Domownicy żyją według planu, np. „dom pusty 9:00–16:00 (pewność 70%)”. Pewność rośnie z każdą obserwacją o innej porze. Plan jest deterministyczny z seeda domu i daty, więc obserwacja ma sens.
- **REK-05 · Sygnały z otoczenia** `v1`. Auto na podjeździe znaczy, że ktoś jest w domu. Sterta gazet i listów to wyjazd. Do tego zapalone światła, opuszczone rolety, wystawione śmieci, włączony zraszacz. Każdy sygnał daje podpowiedź w notatniku. ⚡ _stan liczony raz przy wejściu w strefę ulicy, propy lokalne_
- **REK-06 · Naklejki firm ochroniarskich** `MVP`. Logo na oknie albo tabliczka w ogrodzie mówi, jaki jest system: brak / standard / premium z patrolem. Około 20% naklejek to blef, który da się sprawdzić skanerem.
- **REK-07 · Podszycie się pod kuriera lub akwizytora** `v1`. W przebraniu pukasz do drzwi i domownik otwiera. W krótkiej rozmowie z wyborami podglądasz przedpokój: panel alarmu, psa, układ korytarza. Minus: zapamiętuje twarz (NPC-22).
- **REK-08 · Informator w barze** `v1`. Kupujesz cynk, np. „dom na wakacjach” albo „kod do alarmu”. Informator z niską reputacją czasem sprzedaje fałszywkę.
- **REK-09 · Hakowanie Wi-Fi z auta** `v2`. Laptop w zasięgu 30 m i minigra sieciowa. Nagroda: lista urządzeń (kamery IP, smart lock, TV) i dostęp do smart home (ZAB-20).
- **REK-10 · Social media ofiar** `v1`. Aplikacja „Facegram” na laptopie. Zdjęcie nowego zegarka to pewny łup, check-in na lotnisku znaczy pusty dom, zdjęcie psa ostrzega. Posty generuje seed domu.
- **REK-11 · Ocena ryzyka i wartości domu** `MVP`. Po rekonesansie dom dostaje gwiazdki: zabezpieczenia, szacowany łup, obecność ludzi, odległość posterunku. Rośnie ich dokładność.
- **REK-12 · Tablica planowania w kryjówce** `v1`. Korkowa tablica ze zdjęciami, notatkami, planem domu i narysowaną trasą. Cała ekipa widzi to samo.
- **REK-13 · Zdjęcie zamka telefonem** `v1`. Zdjęcie drzwi z bliska rozpoznaje markę i klasę wkładki („bębenek klasy B, piny grzybkowe”), więc wytrych dobierasz przed akcją.
- **REK-14 · Obchód okolicy** `MVP`. Powolny spacer wzdłuż domu odkrywa uchylone okno, drabinę w ogrodzie, psią budę. Zbyt długie stanie w miejscu zwiększa podejrzliwość ulicy.
- **REK-15 · Pora dnia i pogoda** `MVP`. Deszcz tłumi hałas o ~30%, grzmot maskuje zbicie szyby, mgła skraca wzrok NPC. W nocy domownicy śpią, w dzień domy są puste, ale na ulicy jest więcej świadków. ⚡ _pogodę sprawdzamy raz na minutę_
- **REK-16 · Mapa okazji w telefonie** `v1`. Generowane, wygasające okazje, np. „Mirror Park, dom pusty do 18:00”. Ich liczba na serwer jest ograniczona, więc na jedną ulicę nie zjeżdża 10 ekip.
- **REK-17 · Przeszukanie śmietnika** `v1`. Paragon za nowy telewizor to łup, karton po kamerze to zabezpieczenie, list z banku to sejf, a rzadko trafia się kartka z PIN-em.
- **REK-18 · Obserwacja z auta** `v1`. Siedzenie w zaparkowanym aucie przyspiesza zbieranie informacji, ale długie stanie ściąga uwagę wścibskiej sąsiadki (NPC-17), która zapisuje tablice.
- **REK-19 · Dzień otwarty „na sprzedaż”** `v2`. Legalnie wchodzisz z agentem nieruchomości. Możesz uchylić okno w łazience, zanotować sejf i sfotografować panel alarmu.
- **REK-20 · Dron zwiadowczy** `v2`. Podgląd podwórka, dachu i okien na piętrze, bateria na 90 s. Psy słyszą drona. ⚡ _kamera skryptowa tylko w trakcie lotu_
- **REK-21 · Test obecności: dzwonek** `MVP`. Dzwonisz i czekasz albo uciekasz. Jeśli ktoś podejdzie, dom nie jest pusty. Otwierający widzi twoją twarz.
- **REK-22 · Endoskop pod drzwiami** `v1`. Kamera o małym polu widzenia pokazuje pokój za zamkniętymi drzwiami: śpiącego domownika, psa, kamerę.
- **REK-23 · Cynki od legalnych prac** `extra`. Gracze pracujący jako dostawcy czy sprzątacze mogą sprzedawać informacje o domach NPC w aplikacji. Legalne prace łączą się ze światem przestępczym.
- **REK-24 · Rejestr dzielnic** `v1`. Lista domów w dzielnicy ze statusem (nieznany / zbadany / okradziony, z cooldownem) i szacunkiem łupu.
- **REK-25 · Automatyczna sekretarka przez okno lub drzwi** `extra`. Przy uchylonym oknie słychać nagrywaną wiadomość („wrócimy w niedzielę”), która trafia do notatnika.

## 2. WEJ – Drzwi, okna i punkty wejścia

- **WEJ-01 · Wiele wejść na dom** `MVP` 🎮. Drzwi frontowe, tylne, taras, garaż, piwnica, okna. Każde wejście ma własny zamek, czujnik, widoczność z ulicy i hałas. Wybór wejścia to wybór ryzyka.
- **WEJ-02 · Typy drzwi** `MVP`. Drewniane da się wyważyć. Stalowe antywłamaniowe tylko wytrych albo wiertarka. Szklane przesuwne: łom po cichu albo zbicie głośno. Garażowe, piwniczne na kłódkę, wewnętrzne.
- **WEJ-03 · Stany okien** `MVP` 🎮. Zamknięte, uchylone (ciche podważenie), otwarte na oścież (latem częściej), z kratami (szlifierka), na piętrze (drabina, rynna, balkon).
- **WEJ-04 · Zbicie szyby łomem** `MVP` 🎮. Najszybsze i bardzo głośne (hałas 90). Zostaje szkło, a bez rękawic i kurtki możesz się skaleczyć, czyli zostawić krew z DNA (POL-04).
- **WEJ-05 · Wycięcie szyby** `MVP` 🎮. Minigra: rysujesz myszą okrąg nożem do szkła, potem przyssawka. Trwa 10–15 s, prawie cicho, a przez otwór sięgasz do klamki.
- **WEJ-06 · Podważanie łomem** `MVP`. Drzwi i okna tarasowe. Minigra siły: przytrzymujesz i „pompujesz” w rytm, za mocno znaczy głośny trzask. Zostaje ślad narzędzia (POL-05).
- **WEJ-07 · Wyważanie kopniakiem** `v1`. Tylko drewniane drzwi: 2–4 kopnięcia, bardzo głośno, szybko. Wyłamane drzwi widać z ulicy.
- **WEJ-08 · Ukryte klucze** `MVP` 🎮. Pod wycieraczką, w doniczce, sztuczny kamień, nad framugą, w skrzynce na listy. Szansa zależy od profilu (emeryt chowa klucz częściej). Szukanie trwa i jest widoczne z ulicy.
- **WEJ-09 · Łańcuch włamań** `v2`. U sąsiada znajdujesz zapasowy klucz z breloczkiem „Kowalscy”, który daje ciche wejście do kolejnego domu.
- **WEJ-10 · Łańcuch i zasuwa od środka** `v1`. Gdy ktoś jest w domu, drzwi mają łańcuch: otwarty zamek nie wystarczy, potrzebne są nożyce albo inne wejście. Sam łańcuch jest znakiem, że domownik jest w środku.
- **WEJ-11 · Brama garażowa** `v1`. Skopiowanie pilota (minigra dopasowania fali) albo awaryjne odblokowanie drutem przez szczelinę u góry. Drzwi z garażu do domu są słabiej zabezpieczone.
- **WEJ-12 · Dach i świetlik** `v2`. Wspinaczka po rynnie z paskiem wytrzymałości, świetlik z zamkiem od środka, zejście po linie.
- **WEJ-13 · Drabina** `v1`. Własna drabina (duży przedmiot w aucie) albo ogrodowa przestawiona pod balkon. Zostawiona drabina to sygnał dla sąsiadów i patrolu.
- **WEJ-14 · Drut przez uchylone okno** `v1`. Precyzyjna minigra: prowadzisz drut przez szparę do klamki. Cicho.
- **WEJ-15 · Zamknij za sobą** `v1`. Zamknięcie drzwi lub okna po wejściu idzie szybciej niż otwarcie. Mniej podejrzeń u przechodniów i powracających domowników.
- **WEJ-16 · Trwałe ślady włamania** `MVP`. Wyłamane drzwi, odłamki szkła, otwarte okno zostają do resetu domu. Widzą je gracze i NPC, a świadkowie dzwonią. ⚡ _jeden prop odłamków na wejście, stan w statebagu drzwi_
- **WEJ-17 · Zamknięte pokoje w środku** `v1`. Gabinet, sypialnia z sejfem, pokój nastolatka z napisem „NIE WCHODZIĆ”. Zamki wewnętrzne są łatwiejsze, a klucz czasem leży w szufladzie.
- **WEJ-18 · Ucieczka przez okno** `v1`. Skok przez niskie okno. Z piętra grozi upadkiem z ragdollem, a ciężki plecak zwiększa obrażenia.
- **WEJ-19 · Furtka i płot** `MVP`. Furtka zamknięta na kłódkę albo na klamkę od środka (sięgasz ręką). Przeskoczenie płotu jest głośne i widoczne. Czasem jest dziura w żywopłocie.
- **WEJ-20 · Klapa dla psa i chwytak** `v2`. Przez klapę sięgasz chwytakiem do klucza zostawionego w zamku albo do zasuwy. Cicho, ale pies musi być nieobecny.
- **WEJ-21 · Okienko piwniczne** `v1`. Ciasne: przechodzisz bez plecaka, a plecak podajesz osobno. Piwnica jest słabo zabezpieczona, ale drzwi z piwnicy na górę skrzypią.
- **WEJ-22 · Łamanie wkładki** `v1`. Brutalna, szybka i głośna metoda na tanie wkładki klasy A. Niszczy zamek, a policja od razu widzi, że było to włamanie siłowe.
- **WEJ-23 · Wyjęcie drzwi przesuwnych z prowadnicy** `v2`. Słaby punkt tanich drzwi tarasowych: łom i siła, we dwóch dwa razy szybciej.
- **WEJ-24 · Wspólny model wejścia** `MVP`. Każde wejście to obiekt `{ zamek, czujnik, materiał, widoczność, hałas, metody }`. Jeden interfejs obsługuje wszystkie metody otwierania i wszystko da się ustawić w edytorze (DOM-08).
- **WEJ-25 · Drzwi skrzypią i trzaskają** `v1`. Otwieranie z przytrzymaniem klawisza jest ciche, szybkie daje skrzypienie. Każde drzwi mają swój próg i dźwięk, który trafia do systemu hałasu (SKR-04).

## 3. ZAM – Zamki, sejfy i ich typy

- **ZAM-01 · Zamki bębenkowe klasy A/B/C** `MVP` 🎮. Mają 3, 5 albo 7 pinów, różną tolerancję i tempo opadania pinów. Klasę widać dopiero z bliska albo po zdjęciu (REK-13).
- **ZAM-02 · Piny zabezpieczające (grzybkowe, szpulkowe)** `v1`. Fałszywe ustawienie: bęben lekko się obraca jak przy otwarciu, ale pin blokuje. Trzeba poluzować napinacz, czyli uczysz się prawdziwej techniki.
- **ZAM-03 · Zamek dźwigniowy (stare drzwi, szafy)** `v1`. Osobna minigra: każdą dźwignię podnosisz suwakiem na właściwą wysokość, wytrych dwubrodowy.
- **ZAM-04 · Kłódki: tania, średnia, dyskowa** `MVP`. Tanią otwiera shim albo wytrych, a nożyce ją tną (głośno). Dyskowej nie da się ani shimem, ani nożycami, zostaje szlifierka.
- **ZAM-05 · Kłódki i zamki szyfrowe** `v1`. Minigra wyczuwania: przy lekkim napięciu kółko cicho „klika” na właściwej cyfrze.
- **ZAM-06 · Keypad (kod 4–6 cyfr)** `MVP`. Metody: UV na starte klawisze, kod z notatki w domu, dekoder, zwarcie przewodów (ryzyko alarmu). 3 błędy blokują zamek.
- **ZAM-07 · Smart lock** `v2`. Hakujesz go laptopem przez Wi-Fi (REK-09) albo snifferem BT, gdy domownik otwiera drzwi telefonem. Musisz wtedy stać blisko.
- **ZAM-08 · Brelok RFID (apartamenty, wille)** `v2`. Klonujesz go od domownika na ulicy (1 m przez 5 s) albo z kurtki w przedpokoju.
- **ZAM-09 · Drzwi wielopunktowe klasy 4+** `v1`. Dwa zamki plus rygle, czyli wiertarka i 60–90 s głośnej pracy. Najlepsze domy.
- **ZAM-10 · Sejf z tarczą mechaniczną** `MVP` 🎮. Stetoskop, obracanie tarczy i słuchanie kliknięć na 3 liczbach. Trudność rośnie z szumem otoczenia (pralka, TV).
- **ZAM-11 · Sejf elektroniczny** `v1`. Keypad z blokadą po 3 błędach (15 min albo cichy alarm). Kod zdobywasz z notatki, przez UV, reset serwisowy albo dekoder.
- **ZAM-12 · Tani sejf meblowy** `MVP`. 5–10% właścicieli nie zmieniło kodu fabrycznego „0000”. Otwierasz go też magnesem serwisowym. Szybki łup dla początkujących.
- **ZAM-13 · Sejf do wyniesienia** `v1`. Mały sejf (40 kg) odkręcasz i wynosisz we dwóch albo na wózku, a spokojnie otwierasz w kryjówce szlifierką (3 min).
- **ZAM-14 · Duży sejf wolnostojący** `v2`. Wiercenie w punkcie z minigrą przegrzewania i wymianą wierteł, 2–4 min, głośno. Alternatywa to ładunek: bardzo głośno i część papierów spłonie.
- **ZAM-15 · Gabloty, witryny, szafy na broń** `v1`. Zamki meblowe są łatwe, ale gablota może mieć czujnik wagi (ZAB-17).
- **ZAM-16 · Zamknięta szuflada biurka** `MVP`. Wytrych zajmuje ~10 s. Łom jest głośny i niszczy mebel, co podnosi podejrzliwość (SKR-12).
- **ZAM-17 · Zamki samochodowe w garażu** `v1` 🎮. Stare auto otwiera slim jim, nowe wymaga dekodera lub programatora kluczyka (LOG-04).
- **ZAM-18 · Stan zamka** `v1`. Zardzewiały jest trudniejszy (pomaga smar), nowy gładki, a zamek uszkodzony po nieudanej próbie łatwiej wyważyć, ale trudniej otworzyć wytrychem.
- **ZAM-19 · Wkładka z czujnikiem** `extra`. Złamany wytrych w zamku wysyła powiadomienie do właściciela albo firmy ochroniarskiej.
- **ZAM-20 · Klucz w zamku od środka** `v1`. Blokuje wytrych. Klasyczny trik: kartka pod drzwi i drut wypychający klucz. 20 s, cicho, a klucz jest twój.
- **ZAM-21 · Parametry zamka z seeda serwera** `MVP`. Punkt, kolejność pinów i tolerancja są deterministyczne dla domu i resetu. Wrócisz tego samego dnia i pamiętasz zamek, ale na stałe się go nie nauczysz.
- **ZAM-22 · Klucz dozorcy w apartamentowcu** `v2`. Otwiera piwnice i komórki lokatorskie. Cel sam w sobie.

## 4. WYT – Wytrychy i minigry otwierania

- **WYT-01 · Minigra „punkt” jak w TS** `MVP` 🎮. Obracasz wytrych myszą po półokręgu, a napinacz (PPM) próbuje obrócić bęben. Im bliżej właściwego kąta, tym dalej bęben idzie. Daleko od punktu wytrych drży i traci wytrzymałość. Klasy B i C mają 2–3 kolejne punkty.
- **WYT-02 · SPP, czyli pin po pinie (tryb realistyczny)** `v1`. Podnosisz piny w kolejności wiązania (z seeda). Ustawiony pin daje delikatne kliknięcie i drgnięcie, za wysoko znaczy reset pinu. Serwer wybiera tryb albo zależy on od klasy zamku.
- **WYT-03 · Grabie** `MVP`. Szybkie szarpanie w rytmie. Na klasie A działa w 3–8 s, na B rzadko, na C nigdy. Głośniejsze niż hak.
- **WYT-04 · Bump key** `v1`. Jedno uderzenie młotkiem w idealnym momencie (QTE). Szybkie na A i B bez pinów zabezpieczających. Stuknięcie słychać (hałas 40), a na wkładce zostają ślady.
- **WYT-05 · Wytrzymałość i jakość wytrychów** `MVP` 🎮. Drut, stal, tytan, zestaw profesjonalny. Złamany wytrych może utknąć w zamku: wyciągasz go pęsetą albo zamek jest zablokowany.
- **WYT-06 · Dwa typy napinacza (dolny i górny)** `v1`. Górny daje szerszy punkt w minigrze, dolny jest szybszy. Wybór ma realny wpływ na grę.
- **WYT-07 · Pick gun** `v1`. Trzymasz spust i trafiasz w rytm wibracji. Szybki, ale głośny (35) i zużywa baterię.
- **WYT-08 · Elektroniczny wytrych** `v1` 🎮. Sam otwiera zamki do klasy B w ~20 s, jeśli się nie ruszasz i nikt ci nie przerwie. Drogi, a baterię ładujesz w kryjówce. W ekipie czujka pilnuje, a wytrych pracuje.
- **WYT-09 · Shim do kłódek** `MVP`. Wsuwasz blaszkę w szczelinę z właściwym naciskiem. Działa tylko na tanie kłódki.
- **WYT-10 · Sejf na stetoskop** `v1`. Kręcisz tarczą i słyszysz kliknięcia w słuchawkach (panoramowanie WebAudio), a wskazówka drga. Znalezione liczby zapisują się w notatniku.
- **WYT-11 · Keypad: UV i dedukcja** `v1`. Lampa UV pokazuje 4 starte klawisze, a kolejność musisz ustalić. Podpowiedzi są w domu: data urodzin dziecka na ramce zdjęcia, rocznica w kalendarzu. Masz 3 próby.
- **WYT-12 · Dekoder keypadów** `v1`. Odkręcasz obudowę, podłączasz przewody w dobrej kolejności kolorów (minigra), a dekoder zgaduje kod cyfra po cyfrze przez 15–40 s.
- **WYT-13 · Wiercenie wkładki** `v1`. Trzymasz wiertarkę w punkcie przy wibracjach i przegrzewaniu (trzeba chłodzić). Głośno. Działa na wszystko oprócz wkładek z ochroną przed rozwierceniem.
- **WYT-14 · Stres i warunki** `v1`. Drżenie rąk rośnie, gdy domownik jest blisko, w deszczu i zimie, po sprincie. Grube rękawiczki ogrzewają, ale obniżają precyzję. Umiejętności zmniejszają drżenie.
- **WYT-15 · Hałas minigier** `MVP`. Każda metoda ma swój hałas (grabie 25, bump 40, pick gun 35, wiertarka 80). Wynik wysyłany z NUI zgłasza zdarzenie do systemu hałasu, bez żadnego sprawdzania co klatkę.
- **WYT-16 · Przerwanie minigry** `MVP`. Gdy domownik się zbliża, ekran lekko ciemnieje i słychać kroki. Możesz przerwać, a w SPP ustawione piny trzymają się jeszcze 5–10 s.
- **WYT-17 · Ochrona przed makrami** `MVP`. Każda minigra ma seed z serwera i jednorazowy token, a serwer sprawdza czas (min/max) i dystans, dokładnie jak w `dp-spawacz`.
- **WYT-18 · Dostępność minigier** `v1`. Sterowanie klawiaturą i padem, opcja wolniejszego tempa (serwer decyduje, czy kosztem nagrody).
- **WYT-19 · Wytrych dwubrodowy** `v1`. Minigra z suwakami do zamków dźwigniowych (ZAM-03).
- **WYT-20 · Dorabianie bump keya** `v2`. W kryjówce wybierasz profil klucza pod markę wkładki (z REK-13). Bump działa tylko na dopasowanej marce.
- **WYT-21 · Odcisk klucza w plastelinie** `v2`. Przy chwilowym dostępie do klucza (kurtka w przedpokoju, kieszeń domownika) robisz odcisk, a ślusarz-paser dorabia klucz. Wejście w 100% ciche.
- **WYT-22 · Pęseta i złamany wytrych** `v1`. Minigra precyzji. Wytrych zostawiony w zamku to dowód dla policji.
- **WYT-23 · Smar do zamków** `v1`. Obniża trudność zardzewiałych i zimowych zamków oraz ich hałas o 30%.
- **WYT-24 · Wyczucie zamiast zielonego paska** `v1`. Mikrodrgania, dźwięk sprężyn i zmiana tonu przy zbliżaniu się do punktu. Tryb „assist” z podpowiedziami dla serwerów casual.
- **WYT-25 · Zmęczenie ręki przy napięciu** `v1`. Trzymanie napinacza męczy. Po udanym etapie możesz odpocząć, ale piny wtedy opadają.
- **WYT-26 · Pamięć zamka** `v1`. Zamek otwarty już w tym resecie domu przy kolejnej próbie otwiera się szybciej. Opłaca się planować wejście i wyjście.

## 5. NAR – Narzędzia, sprzęt i gadżety

- **NAR-01 · Łom** `MVP` 🎮. Podważanie, zbijanie szyb, otwieranie skrzyń. W configu można włączyć użycie jako broni.
- **NAR-02 · Nóż do szkła z przyssawką** `MVP` 🎮. Do WEJ-05. Ostrze się zużywa.
- **NAR-03 · Zestawy wytrychów (4 poziomy)** `MVP` 🎮. Od drutu do zestawu profesjonalnego (WYT-05).
- **NAR-04 · Latarki** `MVP`. Biała jest widoczna z ulicy i dla NPC. Z czerwonym filtrem ma mniejszy zasięg i słabiej zdradza. Czołówka zostawia wolne ręce do dużych łupów.
- **NAR-05 · Noktowizor** `v1` 🎮. Widzisz w ciemności bez światła, a do tego diody kamer IR (ZAB-03). Zapalona lampa cię oślepia. Działa na baterię. ⚡ _`SetNightvision` tylko przełączany, bez pętli_
- **NAR-06 · Lornetka** `MVP` 🎮. Do REK-01 i REK-03.
- **NAR-07 · Jammer** `v1` 🎮. Wyłącza kamery bezprzewodowe i Wi-Fi w promieniu 15 m na 45 s, potem cooldown. Nie działa na kamery przewodowe. Zagłusza też radio ekipy i twój telefon, co daje ciekawy kompromis.
- **NAR-08 · Nożyce do drutu** `MVP`. Kłódki, łańcuchy, przewody kamer i syren.
- **NAR-09 · Śrubokręt** `MVP` 🎮. Obudowy keypadów i paneli, demontaż elektroniki (LUP-13), odkręcanie tablic i kamer.
- **NAR-10 · Wiertarka i wiertła** `v1`. Wiertła się zużywają, a wiertło diamentowe dostajesz z craftingu.
- **NAR-11 · Szlifierka kątowa** `v1`. Kłódki dyskowe, kraty, sejf w kryjówce. Bardzo głośna, a iskry dają światło.
- **NAR-12 · Stetoskop** `v1`. Do WYT-10.
- **NAR-13 · Lampa UV** `v1`. Starte klawisze, ślady krwi, które sam zostawiłeś (do sprzątania), znaki na banknotach-pułapkach.
- **NAR-14 · Rękawiczki: lateksowe, skórzane, taktyczne** `MVP`. Lateksowe się rwą. Skórzane są trwałe, ale dają −10% precyzji w minigrach. Taktyczne są najlepsze. Wykrywanie rękawic z ubrania przez listę drawable w configu.
- **NAR-15 · Maska lub kominiarka** `MVP`. Chroni twarz przed kamerami i świadkami, ale maska na ulicy od razu robi z ciebie podejrzanego (przechodnie, policja).
- **NAR-16 · Ochraniacze na buty** `v1`. Bez odcisków butów i ciszej na kafelkach. Zakładanie trwa 3 s.
- **NAR-17 · Plecaki i torby** `MVP` 🎮. Mały (15 kg), turystyczny (25 kg), sportowa torba (35 kg, spowalnia), worek na śmieci (tani, a ostre przedmioty mogą go rozerwać).
- **NAR-18 · Wózek transportowy** `v1`. Telewizory, sejf, duże AGD. Idziesz wolno, a kółka głośno stukają na panelach.
- **NAR-19 · Drabina składana** `v1`. Duży przedmiot wożony w aucie (WEJ-13).
- **NAR-20 · Endoskop** `v1`. Do REK-22.
- **NAR-21 · Narzędzie pod drzwi** `v1`. Otwiera klamkę od środka, jeśli drzwi są tylko zatrzaśnięte, a nie zamknięte na klucz.
- **NAR-22 · Drut lub wieszak** `MVP`. Uchylone okno (WEJ-14), zatrzask bramy garażowej (WEJ-11).
- **NAR-23 · Przysmaki dla psa** `v1`. Zwykły uspokaja psa na 60 s, z tabletką nasenną usypia go po 30 s. Gwizdek ultradźwiękowy odciąga psa w inne miejsce.
- **NAR-24 · Przebrania** `v1`. Kurier, hydraulik, elektryk, technik alarmów, z torbą narzędzi. Za dnia przechodnie w nich nie podejrzewają, ale policjant-gracz może sprawdzić „legitymację” (RP).
- **NAR-25 · Taśma klejąca** `v1`. Zaklejasz kamerę wideodomofonu albo szybę przed zbiciem (ciszej i bez odłamków, to prawdziwy trik).
- **NAR-26 · Skaner RF i detektor kamer** `v1`. Pokazuje kierunek kamer i czujników bezprzewodowych w promieniu 20 m. Piszczy co 2 s, coraz szybciej. ⚡ _ping liczony co 2 s z listy zabezpieczeń domu, bez raycastów_
- **NAR-27 · Laptop złodzieja** `MVP` 🎮. Aplikacje z UIX-02. Laptop terenowy przydaje się do hakowania.
- **NAR-28 · Klonowacz RFID i sniffer BT** `v2`. Do ZAM-07 i ZAM-08.
- **NAR-29 · Magnes neodymowy** `v1`. Przyłożony do kontaktronu pozwala otworzyć okno bez alarmu (ZAB-12). Działa też na tanie sejfy.
- **NAR-30 · Kawa lub energetyk** `extra`. Przez 5 minut drżenie rąk jest mniejsze, ale za dużo kofeiny je zwiększa.
- **NAR-31 · Zestaw do sprzątania śladów** `v1`. Wybielacz i szmatka usuwają odcisk lub krew z punktu w 5–10 s (POL-20).
- **NAR-32 · Pas na narzędzia** `v1`. Więcej slotów szybkiego dostępu (1–6) w czasie włamania.
- **NAR-33 · Pasek narzędzi w akcji** `MVP`. Klawisze 1–6 i kółko myszy zmieniają narzędzie bez otwierania ekwipunku.
- **NAR-34 · Pakowanie torby przed akcją** `v1`. Narzędzia też ważą i liczą się do udźwigu, więc trzeba planować.
- **NAR-35 · Zużycie i naprawa narzędzi** `v1`. Wytrzymałość w metadanych, naprawa w warsztacie kryjówki (LOG-07).
- **NAR-36 · Crafting z części** `v2` 🎮. Z elektroniki rozebranej na części (PAS-05) składasz jammer, dekoder, tytanowy wytrych.
- **NAR-37 · Sklep czarnego rynku z dostawą** `MVP` 🎮. Zamawiasz w laptopie, a towar czeka w skrytce (dead drop), a nie pojawia się z powietrza. Podaż jest ograniczona.
- **NAR-38 · Gaz pieprzowy lub paralizator** `extra`. Domyślnie wyłączone. Obezwładnienie domownika zamienia włamanie w rozbój, a heat rośnie ×2.
- **NAR-39 · Ręcznik lub koc** `v1`. Owinięte łupy nie brzęczą (SKR-06). Kocem zasłaniasz też okno przy zapalonej latarce.
- **NAR-40 · Walkie-talkie** `v1`. Kanał ekipy, który działa niezależnie od telefonu (EKI-07). Jammer go zagłusza.

## 6. ZAB – Kamery, alarmy, czujniki i panele

- **ZAB-01 · Kamery ze stożkiem widzenia** `MVP` 🎮. Kąt 60–90°, zasięg 12–20 m. W polu widzenia narasta wskaźnik nagrywania, a bez maski kamera nagrywa twarz (dowód). ⚡ _sprawdzamy tylko kamery w pokoju gracza: kąt, potem async LOS co 250 ms_
- **ZAB-02 · Kamery obrotowe** `MVP`. Obrót 90–180° z pauzami, więc uczysz się rytmu. ⚡ _kąt liczony wzorem z `GetGameTimer()` (wszyscy liczą to samo bez synchronizacji), a sam prop obraca się tylko gdy gracz jest bliżej niż 25 m_
- **ZAB-03 · Dioda kamery** `MVP` 🎮. Czerwona dioda miga co 2 s i widać ją w ciemności. Kamery IR mają diodę niewidoczną gołym okiem, ale widoczną w noktowizorze i przez aparat telefonu (prawdziwy trik).
- **ZAB-04 · Noc a kamery** `v1`. Zwykła kamera w ciemności nagrywa tylko sylwetkę. Kamera IR nagrywa twarz także w nocy.
- **ZAB-05 · Atrapy kamer** `v1`. Zła dioda albo brak kabla, widoczne przez lornetkę z bliska. Skaner RF je rozpoznaje.
- **ZAB-06 · Ukryte kamery** `v2`. W zegarze, czujniku dymu, pluszaku. Tylko w bogatych domach. Wykrywa je skaner RF albo odblask obiektywu w świetle latarki.
- **ZAB-07 · Wideodomofon** `v1`. Nagrywa ruch przy drzwiach i powiadamia właściciela. Gdy ktoś jest w domu, zaczyna się niepokoić, a gdy nikogo nie ma, jest szansa na zgłoszenie. Kontra: taśma, śrubokręt, jammer.
- **ZAB-08 · Rejestrator DVR/NVR** `MVP`. Nagrania są zapisane na rejestratorze w szafie albo garażu. Zniszczenie lub zabranie go oznacza, że policja nie ma nagrania. W systemie chmurowym nagranie wychodzi od razu, chyba że najpierw odetniesz internet (ZAB-19).
- **ZAB-09 · Przecięcie przewodu kamery** `v1`. Kamera gaśnie, ale w systemie premium po 60–120 s przychodzi komunikat o utracie sygnału i ochrona przyjeżdża sprawdzić.
- **ZAB-10 · Jammer a typy kamer** `v1`. Bezprzewodowe się wyłączają, przewodowe są odporne. Premium wykrywa zagłuszanie i zgłasza sabotaż.
- **ZAB-11 · Panel alarmu z opóźnieniem** `MVP` 🎮. Po otwarciu drzwi masz 20–45 s na kod (pikanie). Kod zdobywasz z rekonesansu, przez UV, dekoderem albo odcinasz zasilanie przed wejściem. Nowoczesne panele są odporne na wyrwanie ze ściany.
- **ZAB-12 · Kontaktrony na drzwiach i oknach** `MVP`. Przy framudze widać biały czujnik, jeśli się przyjrzysz. Otwarcie wyzwala alarm, a magnes (NAR-29) go neutralizuje.
- **ZAB-13 · Czujki ruchu PIR** `v1`. Stożek z rogu pokoju, a dioda miga przy wykryciu. Bardzo wolny ruch w kucki obniża szansę wykrycia. Czujkę da się zasłonić, podchodząc od tyłu.
- **ZAB-14 · Czujnik zbicia szyby** `v1`. Zbicie szyby łomem od razu włącza alarm, wycięcie nożem do szkła nie.
- **ZAB-15 · Lasery** `v2`. Wille i gabloty. Widać je tylko w dymie, sprayu albo przez noktowizor. Przechodzisz pod nimi i nad nimi.
- **ZAB-16 · Maty naciskowe pod dywanem** `v2`. Wyczuwasz je, unosząc brzeg dywanu („sprawdź”), i omijasz po meblach.
- **ZAB-17 · Czujnik wagi na gablocie** `v1`. Zabranie przedmiotu włącza alarm, chyba że podmienisz go na coś o podobnej wadze (worek z piaskiem jako item). Moment jak z Indiany Jonesa.
- **ZAB-18 · Skrzynka z bezpiecznikami** `MVP` 🎮. Minigra: wyłączasz właściwe bezpieczniki, a etykiety bywają błędne. Bez prądu gasną światła, kamery przewodowe i alarm, ale lepsze systemy mają akumulator na X minut. Domownik o lekkim śnie może się obudzić i pójść sprawdzić bezpieczniki: pułapka albo okazja.
- **ZAB-19 · Router i linia telefoniczna** `v1`. Odcięcie internetu blokuje kamery chmurowe i monitoring alarmu. Premium ma zapasowy nadajnik GSM, na który potrzebny jest jammer GSM.
- **ZAB-20 · Hub smart home** `v2`. Hakując go laptopem, możesz wyłączyć kamery, otworzyć smart lock albo włączyć TV na drugim końcu domu, żeby odwrócić uwagę.
- **ZAB-21 · Pętla obrazu z kamery** `v1`. W panelu rejestratora nagrywasz 10 s pustego korytarza i puszczasz je w pętli przez N minut. Moment jak z filmu o skoku.
- **ZAB-22 · Abonament ochrony** `MVP`. Brak / monitoring (dzwonią do właściciela) / reakcja (patrol NPC w 2–4 min) / premium (patrol i od razu policja).
- **ZAB-23 · Patrol ochrony NPC** `v1`. Przyjeżdża autem, obchodzi dom z latarką po punktach i sprawdza drzwi oraz okna. Jeśli znajdzie ślady, wzywa policję i obstawia dom. Możesz przeczekać go w kryjówce. ⚡ _1 ped + 1 auto na sekwencji tasków, spawn tylko gdy ktoś jest w pobliżu_
- **ZAB-24 · Cichy alarm** `v1`. Nie ma syreny, więc nie wiesz, ile masz czasu. Zdradzają go dioda na panelu, która zmienia kolor, i telefon domowy, bo firma dzwoni sprawdzić.
- **ZAB-25 · Syrena i stroboskop** `MVP`. Budzi sąsiadów w promieniu 60 m, przechodnie nagrywają telefonami (świadkowie). Wyłączasz ją kodem albo przecinając kabel syreny na zewnątrz (drabina).
- **ZAB-26 · Wytwornica mgły** `v2`. Premium: po alarmie dom w 10 s wypełnia się mgłą z widocznością na 1 m. Zostaje tylko ucieczka. ⚡ _efekt cząsteczkowy + timecycle tylko w instancji_
- **ZAB-27 · Panic room** `v2`. Domownik zamyka się w pokoju i dzwoni na policję, a ty masz twardą decyzję: uciekać od razu czy ryzykować.
- **ZAB-28 · Tryb analizy zabezpieczeń** `v1`. Skaner RF, UV i czujnik ruchu razem. Znalezione zabezpieczenia trafiają do notatnika i na plan domu.
- **ZAB-29 · Dysk z nagraniem jako przedmiot** `v1`. Możesz go zniszczyć albo sprzedać. Jeśli policja znajdzie go przy tobie, odtworzy nagranie jako dowód.
- **ZAB-30 · Kamery sąsiadów** `v1`. Kamera na domu obok łapie twoje auto razem z tablicami, więc liczy się, gdzie parkujesz.
- **ZAB-31 · Instalator zabezpieczeń (praca dla graczy)** `extra`. Gracze-ochroniarze montują systemy w domach graczy, jeśli okradanie ich domów jest włączone (DOM-15).
- **ZAB-32 · Profil zabezpieczeń domu** `MVP`. Generowany z poziomu domu i profilu właściciela: paranoik ma wszystko, emeryt prawie nic, ale za to psa.
- **ZAB-33 · Telefon z firmy ochroniarskiej** `v1`. Po alarmie dzwoni telefon domowy. Jeśli podniesiesz słuchawkę i podasz hasło z notatek, alarm zostaje odwołany.
- **ZAB-34 · Czujnik otwarcia sejfu** `v2`. Sejf w domu premium wysyła powiadomienie przy otwarciu bez kodu (wiercenie, ładunek). Ogranicza czas na ucieczkę.

## 7. NPC – Mieszkańcy, sąsiedzi, zwierzęta i ochrona (AI)

- **NPC-01 · Plan dnia domowników** `MVP` 🎮. Praca, zakupy, sen (np. 23:00–6:30), deterministycznie z seeda domu i czasu gry. Spawnowani są tylko ci, którzy według planu są teraz w domu, i tylko w instancji włamania.
- **NPC-02 · Fazy snu** `MVP`. Głęboki sen ma wysoki próg słuchu, lekki niski, a co 10–20 min domownik się przewraca: siada, rozgląda się i zasypia. Chrapanie (dźwięk 3D) zdradza głęboki sen.
- **NPC-03 · Stany czujności** `MVP` 🎮. Nieświadomy → Zaniepokojony „?” → Sprawdza (idzie do źródła, zapala światło) → Zaalarmowany „!” → reakcja zależna od archetypu. Zapamiętuje, skąd dobiegł hałas.
- **NPC-04 · Słuch** `MVP`. Dostaje zdarzenia hałasu z SKR-04, stłumione przez ściany i drzwi zgodnie z grafem pokoi. Sen podnosi próg.
- **NPC-05 · Wzrok** `MVP`. Stożek 110°. W ciemnym pokoju widzi na 4 m, w zapalonym na 15 m, a latarka gracza potraja twoją widoczność. ⚡ _dystans², kąt, na końcu async LOS, co 250 ms, NPC rozłożeni w czasie_
- **NPC-06 · Archetypy domowników** `v1`. Emeryt (głęboki sen, niedosłyszy, ale wstaje w nocy do toalety), rodzina z dziećmi, imprezowicz (wraca pijany o 3:00, mało zauważa), paranoik (sam sprawdza dom, może mieć broń, jeśli config pozwala), nocny gracz (do 4:00 w słuchawkach, słabo słyszy, ale nie śpi), pielęgniarka na nocki (odwrócony plan dnia), student (dom pełen gości), policjant po służbie (radio, szybsza reakcja policji).
- **NPC-07 · Nocne rutyny** `v1`. Wyjście do toalety albo kuchni po wodę po stałej trasie. Jeśli obserwowałeś dom, notatnik podpowiada „wstaje ok. 3:00”, więc możesz się schować albo przeczekać.
- **NPC-08 · Zauważanie zmian w domu** `v1`. Otwarte szuflady, zapalone światło, uchylone drzwi, pusta szafka po telewizorze. Domownik przechodzący przez pokój robi się Zaniepokojony (SKR-12).
- **NPC-09 · Telefon na policję, który da się przerwać** `MVP`. Domownik wyciąga telefon (5–8 s animacji). Jeśli go spłoszysz albo wcześniej zabierzesz telefon z szafki nocnej, zgłoszenia nie będzie. Stacjonarny telefon stoi w kuchni. Dużo napięcia.
- **NPC-10 · Konfrontacja** `v1`. Domownik z kijem albo patelnią. Możesz uciekać, odepchnąć go albo zastraszyć, ale zastraszenie bronią zmienia włamanie w rozbój (heat ×2). Poziom przemocy ustawia config.
- **NPC-11 · Ucieczka z krzykiem** `v1`. Domownik wybiega na ulicę i krzyczy, a sąsiedzi w promieniu 40 m się budzą (NPC-16).
- **NPC-12 · Chowanie się i szept do telefonu** `v1`. Domownik zamyka się w łazience i dzwoni. Policja dostaje dokładniejszy opis: liczbę sprawców i ubrania.
- **NPC-13 · Psy** `MVP`. Czują cię na 8 m, nawet przez zamknięte drzwi. Szczekają i budzą domowników. Pies w ogrodzie gryzie albo trzyma. Mały pies tylko hałasuje, duży jest groźny. Kontra: przysmak, usypiacz, gwizdek (NAR-23). ⚡ _ped psa tylko gdy gracz jest bliżej niż 60 m, `TaskWanderInArea`_
- **NPC-14 · Kot** `extra`. Strąca przedmioty, co losowo robi hałas. Spłoszony ucieka z miauczeniem, a domownik obwinia kota albo idzie sprawdzić.
- **NPC-15 · Papuga** `extra`. Krzyczy „Złodziej! Złodziej!”, kiedy cię zobaczy, i budzi dom. Easter egg.
- **NPC-16 · Sąsiedzi w oknach** `v1`. Przy hałasie powyżej 60 na zewnątrz zapala się światło u sąsiada i widać sylwetkę. Jeśli cię zobaczy, zostaje świadkiem i opisze ubranie oraz auto. ⚡ _sąsiad jest „wirtualny”: światło w oknie plus logika, bez spawnowania peda_
- **NPC-17 · Wścibska sąsiadka** `v1`. Jedna na ulicę. Wieczorem wychodzi z psem, zapisuje tablice aut, które długo stoją, i dzwoni, gdy coś się nie zgadza. Da się ją obserwować i ominąć.
- **NPC-18 · Przechodnie** `MVP`. Zwykłe pedy GTA reagują na zbitą szybę i syrenę natywnym scenariuszem telefonu, a zgłoszenie ma szansę pójść do dispatchu. ⚡ _`GetGamePool('CPed')` raz, tylko przy głośnym zdarzeniu, filtr dystansu_
- **NPC-19 · Wcześniejszy powrót** `v1`. Podjeżdża auto, reflektory przesuwają się po ścianie, trzaskają drzwi. Masz 20–40 s, a potem słychać klucze w zamku.
- **NPC-20 · Ochroniarz w willi** `v2`. Patroluje po punktach z latarką i radiem. Warta zmienia się co X min. Można go ogłuszyć (umiejętność albo config), ale jeśli przez 3 min nie odezwie się przez radio, włącza się alarm.
- **NPC-21 · Świadek pamięta** `MVP`. Kolor ubrania, maska albo jej brak, płeć, auto, część tablicy („LS 8??”). Wszystko to trafia do dispatchu i raportu dla policji.
- **NPC-22 · Rozpoznanie po czasie** `v2`. Domownik, który widział twoją twarz bez maski, rozpozna cię przez kilka dni przy swoim domu albo w sklepie na rogu i zadzwoni. Świetne dla RP.
- **NPC-23 · Dzieci** `v1`. Budzą się łatwo, ale nie dzwonią: biegną do rodziców, co daje ci 10–15 s. Serwer może je wyłączyć w configu.
- **NPC-24 · Impreza w domu** `v2`. Dużo ludzi i głośno, więc hałas jest zamaskowany, ale oczu jest wiele. W przebraniu gościa możesz się wmieszać.
- **NPC-25 · Przeszukiwanie** `v1`. Po hałasie domownik obchodzi źródło i sąsiednie pokoje. Pod łóżko i do szafy zagląda tylko Zaalarmowany. Jeśli nic nie znajdzie przez 60 s, wraca do łóżka i przez jakiś czas śpi płycej.
- **NPC-26 · Jeden koordynator AI domu** `MVP`. Jeden „mózg” na dom, co 250–500 ms. Pedy dostają natywne taski (`TaskGoToCoordAnyMeans`, `TaskStartScenarioAtPosition`, `TaskLookAtEntity`, sekwencje) i nie ma pętli dla każdego peda w każdej klatce.
- **NPC-27 · AI liczone przez hosta ekipy** `MVP`. Percepcję liczy tylko właściciel encji (lider ekipy). Kluczowe decyzje, jak telefon na policję czy alarm, zatwierdza serwer. Przy zmianie hosta stan się przenosi.
- **NPC-28 · Dom uczy się po włamaniu** `v1`. Po resecie okradziony dom ma nowy zamek, kamerę albo psa. Świat reaguje, a te same domy nie dają się farmić w kółko.
- **NPC-29 · Ewakuacja przy syrenie** `v1`. Domownicy wybiegają na podwórko i czekają. Dom jest pusty, ale ulica pełna ludzi.
- **NPC-30 · Wizyty w dzień** `v2`. Listonosz, kurier, ogrodnik, sprzątaczka o stałych porach. Możesz wejść za nimi albo podszyć się pod nich, ale są też dodatkowymi świadkami.
- **NPC-31 · Zmęczenie czujności** `v1`. Po kilku fałszywych alarmach (hałas, który nic nie wykazał) domownik przestaje wstawać. Nagradza cierpliwe „oswajanie” domu, np. kot albo rzucony przedmiot.

## 8. SKR – Skradanie, hałas, światło i wykrycie

- **SKR-01 · Wskaźnik hałasu** `MVP` 🎮. HUD pokazuje falę ostatniego hałasu i jej zasięg. Kucanie, chód i bieg dają różne wartości. ⚡ _`GetPlayerCurrentStealthNoise` jako baza, próbkowane co 200 ms tylko w domu_
- **SKR-02 · Wskaźnik widoczności** `MVP` 🎮. Oko pokazuje, jak dobrze cię widać: światło w pokoju, latarka, ruch, stanie albo kucanie. Wyliczane ze stanu pokoju, bez pomiaru światła. ⚡ _zero kosztownych natywek, sama tabela stanów_
- **SKR-03 · Materiał podłogi** `MVP`. Dywan ×0,5, panele ×1, kafle ×1,3, żwir ×1,8, a skrzypiące deski skrzypią zawsze w tych samych miejscach, które warto zapamiętać. ⚡ _materiał przypisany do pokoju plus małe strefy skrzypiących desek zamiast raycastów po materiałach_
- **SKR-04 · Hałas przez pokoje (graf)** `MVP`. Pokoje są węzłami, drzwi krawędziami. Zamknięte drzwi tłumią o 40%, ściana o 60%, osobno liczone jest wyjście na zewnątrz do sąsiadów. BFS rusza tylko przy zdarzeniu.
- **SKR-05 · Tempo** `MVP`. Kucanie (tryb stealth GTA), bardzo wolne skradanie z ALT (50% prędkości), bieg. Ciężki plecak robi więcej hałasu.
- **SKR-06 · Brzęczący plecak** `v1`. Szkło i metal w plecaku dzwonią przy biegu. Pomaga owinięcie ręcznikiem (NAR-39).
- **SKR-07 · Włączniki światła** `MVP`. Każdy pokój ma światło. Zapalone widać z ulicy, a zgaszenie światła, które było zapalone, domownik zauważy. ⚡ _w shellach ciemność daje modyfikator timecycle ustawiany raz przy wejściu do pokoju, a jest tylko 1–2 najbliższe lampy przez `DrawLightWithRange` w wątku INSIDE_
- **SKR-08 · Latarka zdradza** `MVP`. Jej światło widać przez okna z ulicy i na ścianach dla domowników. Czerwony filtr zdradza mniej.
- **SKR-09 · Zasłony i rolety** `v1`. Zasunięte zmniejszają ryzyko z ulicy, ale rano domownik to zauważy. Rolety elektryczne hałasują.
- **SKR-10 · Kryjówki** `MVP` 🎮. Szafa, pod łóżkiem, za zasłoną, za drzwiami, za kotarą w wannie, za autem w garażu. Wejście trwa 1–2 s, a przez szparę widać pokój. Gdy domownik jest blisko, trzymasz klawisz, żeby wstrzymać oddech (pasek).
- **SKR-11 · Odwracanie uwagi** `v1`. Rzucasz monetę albo butelkę, a hałas powstaje tam, gdzie upadła. Możesz też nastawić minutnik w kuchni (dzwoni za 30 s), włączyć radio albo zadzwonić z komórki na telefon domowy.
- **SKR-12 · Licznik bałaganu** `v1`. Otwarte szuflady, przesunięte rzeczy i brakujące przedmioty podnoszą bałagan w pokoju, a razem z nim szansę, że domownik go zauważy. Zamknięcie szuflady za sobą kosztuje +2 s i oznacza profesjonalizm.
- **SKR-13 · Stopnie wykrycia** `MVP`. Pasek od „?” do „!”, a nie natychmiastowa porażka. Da się przeczekać i się wycofać.
- **SKR-14 · Oczy przyzwyczajają się do ciemności** `v1`. Po zgaszeniu światła domownik przez 5 s widzi gorzej, a ty bez noktowizora też.
- **SKR-15 · Bicie serca** `v1`. Im bliżej jest domownik patrzący w twoją stronę, tym głośniejsze bicie serca (WebAudio). Immersja zamiast pasków, co przydaje się w trybie hardcore.
- **SKR-16 · Ślady błota i śniegu** `v2`. W deszczu i śniegu zostawiasz ślady butów, które zauważy domownik i zbada policja. Ochraniacze na buty (NAR-16) je usuwają. ⚡ _max 20 decali na dom, usuwane przy resecie_
- **SKR-17 · Powolne otwieranie drzwi** `v1`. Z przytrzymaniem klawisza jest cicho, szybko skrzypi (WEJ-25).
- **SKR-18 · Szum tła** `v1`. Burza, pociąg, samolot, impreza u sąsiada, kosiarka, wirowanie pralki, włączony TV to okna czasowe, w których głośne akcje są bezpieczniejsze. HUD pokazuje wskaźnik szumu tła.
- **SKR-19 · Obezwładnienie od tyłu** `extra`. Domyślnie wyłączone. Wymaga umiejętności i daje bardzo dużo heatu.
- **SKR-20 · Tryb hardcore bez HUD** `v1`. Bez wskaźników i znaczników nad NPC, za to z mnożnikiem XP.
- **SKR-21 · Okna widoczne z ulicy** `v1`. Pokoje z oknami na ulicę mają strefę widoczności z zewnątrz. Przejście z latarką przed takim oknem to ryzyko. Plan domu w notatniku pokazuje te okna.
- **SKR-22 · Przedmioty-pułapki** `v1`. Wazon na krawędzi stołu, puszki przy drzwiach tarasu. Potrącenie oznacza upadek i duży hałas. Są to pojedyncze, zaprojektowane pułapki, a nie fizyka całego domu.
- **SKR-23 · Ocena akcji S–F** `MVP`. Po wyjściu raport: czas, hałas, wykrycia, zostawione ślady, łup. Ocena mnoży XP i reputację (jak pieczątka w `dp-spawacz`).
- **SKR-24 · Głos w domu to hałas** `v1`. Mówienie na proximity voice (`NetworkIsPlayerTalking`) w domu emituje hałas dla domowników. Ekipa musi szeptać (tryb szeptu pma-voice) albo używać gestów. ⚡ _sprawdzane co 500 ms tylko w stanie INSIDE_

## 9. LUP – Łup i kradzież

- **LUP-01 · Kategorie łupu** `MVP` 🎮. Elektronika, biżuteria, gotówka, alkohol, sztuka, kolekcje (karty, figurki, monety), dokumenty, elektronarzędzia, klucze do aut. Broń i leki tylko przy włączonej opcji w configu.
- **LUP-02 · Waga i objętość** `MVP` 🎮. Każdy przedmiot ma kg i rozmiar, a plecak ma limit. Integracja z wagą w ox_inventory albo osobny „plecak misji”.
- **LUP-03 · Duże przedmioty w rękach** `MVP` 🎮. Telewizor, komputer, konsola w pudełku, mikrofalówka. Prop w rękach, wolniejszy chód, bez sprintu, jedna rzecz naraz. Niesiesz ją do bagażnika.
- **LUP-04 · Przeszukiwanie mebli** `MVP` 🎮. Szuflady, szafki, lodówka, apteczka, materac, kieszenie kurtek w przedpokoju. 2–6 s, dźwięk, animacja, wynik z tabeli dla danego mebla.
- **LUP-05 · Łup widoczny i ukryty** `MVP`. Najważniejsze rzeczy (TV, laptop) stoją jako propy 3D, a drobnica z mebli jest losowana. ⚡ _propy lokalnie w instancji, zabranie ustawia statebag `taken` i usuwa prop_
- **LUP-06 · Skrytki domowe** `v1`. Sejf za obrazem, luźna deska (skrzypi inaczej niż reszta), podwójne dno szuflady, gotówka w folii w zamrażarce, książka-sejf. Podpowiedzi są w notatkach domowników.
- **LUP-07 · Łup według profilu** `MVP`. U gracza konsole i PC, u emeryta biżuteria i słoik z gotówką, u lekarza zegarek i leki, u kolekcjonera rzadkie figurki. U dilera narkotyki i broń, ale jego ekipa może wrócić.
- **LUP-08 · Kruche przedmioty** `v1`. Porcelana, obrazy za szkłem, telewizory. Uderzenie przy biegu obniża stan (100% → 60%), a z nim cenę.
- **LUP-09 · Stan przedmiotu (0–100%)** `v1`. Wpływa na cenę. Część rzeczy da się naprawić w warsztacie kryjówki.
- **LUP-10 · Numery seryjne** `v1`. Elektronika ma numer w metadanych. U pasera ma to znaczenie (gorący / czysty), a policja sprawdza numer przy zatrzymaniu (POL-10).
- **LUP-11 · Przedmioty z historią** `v1`. Np. „złoty zegarek dziadka Kowalskiego”. Duża wartość, ale bardzo gorący: paser weźmie go dopiero po 48 h, kolekcjoner od razu. Do tego zlecenia na odzyskanie.
- **LUP-12 · Pułapki w łupie** `v2`. Kasetka z farbą (plamy na ubraniu są dowodem, a gotówka jest zniszczona). Lokalizator w drogiej elektronice: policja widzi pozycję przez 5 min, chyba że wcześniej go wykręcisz śrubokrętem.
- **LUP-13 · Demontaż na miejscu** `v1` 🎮. Odkręcenie TV ze ściany (8 s), wyjęcie dysku i RAM z komputera. Do wyboru całość (ciężka, droższa) albo części (lekkie, tańsze).
- **LUP-14 · Rozproszona gotówka** `MVP`. Portfel w kurtce, słoik w kuchni, koperta w książce, sejf. Zachęca do eksploracji.
- **LUP-15 · Klucze do auta** `v1` 🎮. Znalezione w domu pozwalają ukraść auto z garażu albo podjazdu (LOG-04).
- **LUP-16 · Laptop z danymi** `v2`. Po złamaniu hasła w kryjówce dostajesz hasło do sejfu innego domu, zlecenie szantażu albo dane karty (hook do systemów przestępstw finansowych na serwerze).
- **LUP-17 · Oko złodzieja** `v1` 🎮. Klawisz na krótko podświetla wartościowe przedmioty w pokoju (cooldown 10 s). Zasięg i dokładność rosną z umiejętnością. ⚡ _obrys tylko encji-łupów z listy domu, `SetEntityDrawOutline` przez 3 s_
- **LUP-18 · Wycena na oko** `v1`. Celując w przedmiot, widzisz przedział wartości. Amator widzi „???$”, ekspert kwotę prawie dokładną.
- **LUP-19 · Łupy sezonowe** `v2`. Prezenty pod choinką w grudniu, słodycze i dekoracje na Halloween, sprzęt plażowy latem.
- **LUP-20 · Broń w domu** `extra`. Paranoik trzyma broń w szafce nocnej. Kradzież broni daje duży heat, a serwer może ją wyłączyć.
- **LUP-21 · Stos przy wyjściu** `v1`. Łup odkładasz przy drzwiach wyjściowych i wynosisz za jednym razem, albo ekipa podaje go przez okno (EKI-06).
- **LUP-22 · Chciwość kontra czas** `MVP`. Im dłużej jesteś w domu, tym większa szansa na zdarzenia losowe (ZLE-08). Klasyczne „jeszcze jedna szuflada”.
- **LUP-23 · Kolekcjonerski alkohol w piwnicy** `v2`. Ciężki, kruchy, drogi, a kupuje go tylko konkretny paser.
- **LUP-24 · Łupy na kółkach** `v1`. Rower, hulajnoga elektryczna, kosiarka, quad z garażu. Wyprowadzasz albo wyjeżdżasz nimi.
- **LUP-25 · Anti-dupe łupu** `MVP`. Każdy łup to rekord na serwerze z UUID. Przy zabraniu serwer sprawdza dystans i flagę `taken`, i dopiero wtedy wydaje item z metadanymi (dom, czas, numer seryjny).
- **LUP-26 · Wybór przy przeszukaniu** `v1`. Szuflada nie oddaje wszystkiego automatycznie. Mini-lista zawartości pozwala wybrać, co bierzesz, żeby nie tracić udźwigu na śmieci.
- **LUP-27 · Pamiątki bez wartości** `extra`. Albumy, listy, medale, bezwartościowe u pasera. Oddanie ich przez skrzynkę pocztową albo policję daje karmę i reputację u części kontaktów. Czysto fabularne.

## 10. PAS – Paser, sprzedaż i ekonomia

- **PAS-01 · Paserzy z preferencjami** `MVP` 🎮. Jeden bierze elektronikę, drugi biżuterię, trzeci sztukę. Ich lokalizacje zmieniają się co restart, a informacje o nich dają kontakty.
- **PAS-02 · Lombard** `MVP` 🎮. Legalny: płaci mało, kupuje tylko czysty towar. Gorący odrzuca albo zgłasza policji (szansa zależy od reputacji).
- **PAS-03 · Gorący towar i stygnięcie** `v1`. Przez pierwsze 24 h (albo X restartów) paser płaci 40–60%, potem 100%. Towar przechowujesz w kryjówce. ⚡ _liczone leniwie z czasu kradzieży zapisanego w metadanych_
- **PAS-04 · Czyszczenie numerów seryjnych** `v1` 🎮. Minigra szlifowania tabliczki albo podmiany płytki w warsztacie. Jest szansa uszkodzenia przedmiotu.
- **PAS-05 · Rozbieranie elektroniki na części** `v1` 🎮. Części sprzedajesz osobno albo używasz do craftingu (NAR-36).
- **PAS-06 · Aukcje online w laptopie** `v1` 🎮. Wystawiasz przedmiot, a oferty NPC przychodzą z czasem. Cena jest wyższa niż u pasera, ale czekasz. Policja może przeglądać ogłoszenia (POL-11).
- **PAS-07 · Ceny zależne od podaży na serwerze** `v1`. Im więcej konsol sprzedano w ostatnich 24 h, tym niższa cena (do 50%), która potem powoli wraca. Chroni przed farmieniem. ⚡ _licznik per kategoria z zanikaniem liczonym przy zapytaniu, bez pętli_
- **PAS-08 · Zamówienia pasera** `v1`. „Potrzebuję 2 zegarków i obrazu do piątku”, z premią 150%. Rekonesans staje się konieczny.
- **PAS-09 · Reputacja u pasera** `MVP`. Lepsze ceny, rzadkie zlecenia, dostęp do narzędzi. Sprzedaż przedmiotu z lokalizatorem albo przyprowadzenie ogona obniża reputację.
- **PAS-10 · Wsypa przy sprzedaży** `v1`. Losowy nalot w miejscu wymiany, jeśli towar ma lokalizator albo policja ustawiła zasadzkę u pasera. Paser z niskim zaufaniem sam może być informatorem.
- **PAS-11 · Targowanie** `v1` 🎮. Minigra: paser proponuje cenę, ty podbijasz, a jego cierpliwość spada. Za mocno i odchodzi. Umiejętność „Handel” poszerza pole manewru.
- **PAS-12 · Brudna gotówka** `MVP`. Wypłata w `black_money` (ESX), `markedbills` (QB) albo item. Config pozwala wypłacać czystą gotówkę.
- **PAS-13 · Limity dzienne** `MVP`. Maksymalna sprzedaż na postać i na serwer, ustawiana w configu.
- **PAS-14 · Sprzedaż graczom** `v1`. Przedmioty z metadanymi da się sprzedać innym graczom, np. sklepom RP ze „sprzętem używanym”. Jeśli policja sprawdzi numer, jest problem.
- **PAS-15 · Paser w vanie** `v2`. Pojawia się na 20 min w losowym miejscu i kupuje wszystko po dobrej cenie. Informacja przychodzi SMS-em, więc czasem czeka tam zasadzka.
- **PAS-16 · Dead drop** `v1`. Zostawiasz towar w skrytce, pieniądze przychodzą po 30 min bez kontaktu z NPC. Bezpieczniej, ale taniej.
- **PAS-17 · Podróbki i ekspertyza** `v2`. Część „drogich” rzeczy to fałszywki. W kryjówce sprawdzasz je lupą (umiejętność), zanim ośmieszysz się u pasera.
- **PAS-18 · Eksport hurtowy** `v2`. Raz w tygodniu statek w porcie kupuje duże ilości po wyższej cenie. Event dla ekip.
- **PAS-19 · Sklep narzędzi zależny od reputacji** `v1` 🎮. Najlepsze narzędzia są dostępne dopiero od pewnego poziomu reputacji.
- **PAS-20 · Ubezpieczenie ofiar** `extra`. Przy okradaniu domów graczy (DOM-15) ofiara dostaje część zwrotu, co pomaga zbalansować ekonomię.
- **PAS-21 · Prowizja pasera** `MVP`. Stały procent jako money sink, ustawiany w configu.
- **PAS-22 · Panel cen dla admina** `v1`. Wykresy sprzedaży i cen, ręczne korekty, logi transakcji na Discordzie.
- **PAS-23 · Kolekcjoner** `v2`. NPC kupuje całe zestawy (np. 5 figurek z serii) z premią za komplet. Zachęca do celowanych włamań.

## 11. POL – Policja, dowody i konsekwencje

- **POL-01 · Integracja z dispatchem** `MVP`. ps-dispatch, cd_dispatch, core_dispatch, qs-dispatch, rcore_dispatch, lb-tablet, własny hook. Alert zawiera typ (alarm / świadek / ochrona), adres i opis sprawcy z NPC-21.
- **POL-02 · Czas reakcji** `MVP`. Zależy od dzielnicy, pory i liczby policjantów na służbie. W Vinewood Hills jest szybciej, w Sandy Shores wolniej.
- **POL-03 · Odciski palców** `MVP`. Bez rękawiczek każda interakcja (klamka, szuflada, zamek) zostawia odcisk z ID postaci. Integracja z systemami dowodów (qb-policejob evidence, r14-evidence) albo wbudowany prosty system.
- **POL-04 · DNA i krew** `v1`. Skaleczenie przy zbijaniu szyby, niedopałek, jeśli palisz w domu.
- **POL-05 · Ślady butów i narzędzi** `v1`. Ślad łomu na framudze („narzędzie 22 mm”) i odcisk buta (model z drawable butów postaci) da się porównać z tym, co ma podejrzany.
- **POL-06 · Nagrania z kamer** `v1`. Jeśli rejestrator nie został zniszczony, policja ogląda nagranie w NUI: sylwetkę, ubranie, twarz bez maski, godzinę. Świetny materiał do RP.
- **POL-07 · Minigra śledcza** `v1`. Na miejscu włamania policja szuka śladów lampą UV i proszkiem, pakuje je do woreczków i pisze raport. Policja dostaje własną rozgrywkę.
- **POL-08 · Heat gracza i dzielnicy** `MVP`. Głośne i zauważone włamania podnoszą heat, który opada z czasem. Przy wysokim heacie w dzielnicy jest więcej patroli, dłuższe cooldowny i więcej domów z alarmami. ⚡ _zanik liczony leniwie przy odczycie_
- **POL-09 · Zgłoszenie z opóźnieniem** `v1`. Niezauważone włamanie zgłasza się dopiero, gdy domownik wróci albo rano: „włamanie z nocy”. Policja jedzie zbadać ślady, więc zamiast pościgu jest śledztwo.
- **POL-10 · Łup jako dowód** `MVP`. Przy przeszukaniu policja sprawdza przedmioty w bazie skradzionych rzeczy (target lub komenda) i widzi, z którego domu pochodzą.
- **POL-11 · Rejestr skradzionych w MDT** `v2`. ps-mdt, lb-tablet, redutzu-mdt: automatyczne wpisy, alerty z aukcji internetowych (PAS-06).
- **POL-12 · Seria włamań** `v2`. Ten sam styl, pora albo wizytówka (PRO-15) łączy sprawy. Przy wielu świadkach powstaje list gończy z opisem.
- **POL-13 · Dom-pułapka** `v2`. Policjant z odpowiednią rangą oznacza dom jako przynętę, a cichy alarm trafia tylko do niego.
- **POL-14 · Mapa heatu dla policji** `v1`. W MDT widać, gdzie było dużo włamań. Kieruje patrolami graczy.
- **POL-15 · Hook dla K9** `extra`. Ślad zapachowy z miejsca włamania dla skryptów psa policyjnego.
- **POL-16 · Minimum policji i cooldowny** `MVP`. Minimalna liczba policjantów na służbie, cooldown globalny, dla gracza i dla domu, limit równoczesnych włamań.
- **POL-17 · Tryb bez policji-graczy** `v1`. Policja NPC: natywny wanted level albo symulowany pościg, dla małych serwerów.
- **POL-18 · Ochrona przed nadużyciami** `MVP`. Blokada okradania przez X min po zejściu ze służby policji lub EMS, a podejrzane zachowania trafiają do logów.
- **POL-19 · Konsekwencje zatrzymania** `v1`. Konfiskata łupu i narzędzi (z metadanymi jako dowód), wpis do kartoteki, integracja z więzieniem.
- **POL-20 · Zacieranie śladów po akcji** `v1`. Wybielacz, spalenie ubrania w beczce, prysznic w kryjówce usuwają dowody z postaci (farbę, krew, odłamki szkła).
- **POL-21 · Gracz jako świadek** `v1`. Gracz, który widzi włamanie, ma opcję „Zgłoś” na podejrzanym. Dispatch dostaje opis.
- **POL-22 · Premia za odzyskany łup** `v1`. Ubezpieczyciel NPC płaci policji za odzyskane przedmioty. Policja ma motywację, a ekonomia sink.
- **POL-23 · Odłamki szkła na ubraniu** `v2`. Przez 30 min po zbiciu szyby policja wykrywa je na ubraniu przy przeszukaniu.
- **POL-24 · Nagranie przechodnia** `v2`. Świadek przy syrenie nagrywa telefonem, a policja może je „pobrać” (tekstowy opis plus zdjęcie z miejsca).

## 12. DOM – Domy, wnętrza, profile i instancje

- **DOM-01 · Hybrydowe źródła wnętrz** `MVP`. Shelle (K4MB1 i inne, z darmowym zestawem jako fallback), IPL z GTA, MLO serwera. Wybór w configu osobno dla każdego domu.
- **DOM-02 · Routing bucket na włamanie** `MVP`. Ekipa dzieli jeden bucket. Wnętrza nie widzi reszta serwera i nie ma synchronizacji z innymi, a przy wyjściu gracz wraca do bucketu 0. ⚡ _`SetPlayerRoutingBucket`, `SetRoutingBucketPopulationEnabled(false)`_
- **DOM-03 · Tryb wspólnego świata dla MLO** `v1`. Bez instancji: inni gracze, w tym policja, mogą wejść do środka. Ustawiane per dom.
- **DOM-04 · Poziomy domów** `MVP` 🎮. T1 przyczepa lub mieszkanie, T2 szeregowiec, T3 dom jednorodzinny, T4 willa. Rosną zabezpieczenia i łup, a poziomy odblokowuje progresja.
- **DOM-05 · Generator profilu właściciela** `MVP`. Archetyp (NPC-06), zabezpieczenia (ZAB-32), łupy (LUP-07), zwierzęta, plan dnia. Deterministycznie z seeda (dom + dzień), więc rekonesans ma sens.
- **DOM-06 · Proceduralne wyposażenie** `v1`. Shell ma sloty, do których losowane są meble i łupy z tabel profilu. 3–5 wariantów na shell, więc dom wygląda jak jego właściciel (plakaty gracza, książki emeryta).
- **DOM-07 · Pokoje jako strefy** `MVP`. Każdy dom ma zdefiniowane pokoje (box zones) z materiałem podłogi, światłem, kamerami, czujkami i węzłem grafu hałasu. To serce wszystkich systemów.
- **DOM-08 · Edytor domów w grze** `v1`. Tryb admina z laserem: stawiasz wejścia, pokoje, meble z łupem, kamery, czujniki i kryjówki. Podgląd na żywo, zapis do JSON albo bazy. Kluczowe przy sprzedaży skryptu.
- **DOM-09 · Stan i cooldown domu** `MVP`. Po włamaniu cooldown 2–6 h, ślady (WEJ-16) i ulepszone zabezpieczenia (NPC-28). Stan w pamięci serwera plus KVP albo baza.
- **DOM-10 · Piętra i piwnica** `v1`. Shell wielopiętrowy albo kilka shelli połączonych schodami z krótkim wyciemnieniem.
- **DOM-11 · Garaż i szopa** `MVP`. Mikro-włamania dla początkujących: szopa na kłódkę z elektronarzędziami, garaż z rowerem i autem.
- **DOM-12 · Apartamentowce** `v2`. Klatka schodowa, domofon (wchodzisz za mieszkańcem), kilka mieszkań w jednym budynku, dozorca, komórki lokatorskie.
- **DOM-13 · Żywe domy** `v1`. Włączony TV (maskuje hałas zza ściany), radio, pralka, ciepły czajnik. Podpowiedzi, że ktoś tu niedawno był.
- **DOM-14 · Sezonowość** `v2`. Choinka i prezenty w grudniu, Halloween, lato z otwartymi oknami i basenem.
- **DOM-15 · Domy graczy** `extra`. Integracja z ps-housing, qb-houses, qs-housing, loaf_housing. Właściciel kupuje zabezpieczenia (alarm, kamery, psa). Twarde limity: tylko przy właścicielu online albo offline (do wyboru), najwyżej raz na X dni, tylko ze „schowka na wartościowe rzeczy”, a nie z całego ekwipunku.
- **DOM-16 · Pula i rotacja celów** `MVP`. Z ~200 domów w configu aktywnych celów jest tylko N naraz, z rotacją co kilka godzin. Mniej danych dla klientów i brak tłoku.
- **DOM-17 · Wejście z prawdziwej fasady** `MVP`. Interakcja na drzwiach domu w świecie GTA, wyciemnienie i shell. Tylne drzwi shella prowadzą na tył domu na mapie (spójne punkty wejść i wyjść).
- **DOM-18 · Okna w shellach** `v1`. Zasłony albo widok ulicy w oknach, żeby logika sąsiadów i widoczności z ulicy była spójna z tym, co widać.
- **DOM-19 · Import i eksport domów** `v1`. Paczki domów w JSON do udostępniania między serwerami, przykładowe domy w zestawie.
- **DOM-20 · Stany specjalne domu** `v2`. Dom na sprzedaż (mało łupu, kamera agencji), w remoncie (rusztowanie, łatwe wejście, narzędzia robotników), tuż po przeprowadzce (łup spakowany w kartony).
- **DOM-21 · Willa jako mini-skok** `v2`. Brama, ogrodzenie, ochrona, psy, kamery, sejf, kolekcja. Plan w kryjówce i ekipa 3–4 osób. Wieloetapowe.
- **DOM-22 · Płynne wejście** `v1`. Model shella wczytuje się już przy zbliżeniu do drzwi (< 10 m), drzwi się uchylają, wyciemnienie trwa 300 ms. Bez czarnego ekranu.
- **DOM-23 · Interakcje przez strefy targetu** `MVP`. Szuflady, szafki i panele to strefy ox_target, a nie encje, wszędzie gdzie się da. Zero pętli i zero dodatkowych encji.
- **DOM-24 · Jeden dom, jedna ekipa** `MVP`. Blokada na serwerze: w danym domu może być tylko jedno aktywne włamanie naraz.

## 13. LOG – Pojazdy, transport i kryjówka

- **LOG-01 · Łup do bagażnika** `MVP` 🎮. Duże rzeczy wkładasz do bagażnika z animacją. Pojemność zależy od klasy auta (sedan 3 duże, van 10). Łup trzymany w metadanych pojazdu albo w bagażniku ox_inventory.
- **LOG-02 · Łup widoczny w vanie** `v2`. Skradziony telewizor widać przez szyby, co może zauważyć policja. ⚡ _propy przyczepione lokalnie, tylko w zasięgu 30 m, max 6_
- **LOG-03 · Van złodzieja** `v1`. Więcej miejsca, półki na narzędzia, napis fałszywej firmy („Hydraulika Staszek”), przez co za dnia budzisz mniej podejrzeń.
- **LOG-04 · Kradzież auta z garażu** `v1` 🎮. Kluczyki z domu (LUP-15) albo dekoder i programator (minigra dopasowania sygnału). Integracja z qb-vehiclekeys, qbx_vehiclekeys, wasabi_carlock i innymi.
- **LOG-05 · Dziupla** `v2` 🎮. Rozkręcanie kół, drzwi i maski (minigry klucza i śrubokręta). Części idą na sprzedaż, a auto znika (sink).
- **LOG-06 · Fałszywe tablice** `v1`. Zakładasz je na akcję, więc świadek zapisze fałszywe numery.
- **LOG-07 · Kryjówka** `v1` 🎮. Magazyn łupu, warsztat (czyszczenie, naprawa, crafting), laptop, tablica planowania, prysznic (POL-20). Rozbudowujesz ją za pieniądze.
- **LOG-08 · Nalot na kryjówkę** `v2`. Gdy policja zdobędzie trop (lokalizator, śledzenie), może przeszukać kryjówkę na nakaz (event RP). Ukryta skrytka chroni część łupu.
- **LOG-09 · Wynajmowane garaże i magazyny** `v2`. Rozproszenie ryzyka: nie trzymasz wszystkiego w jednym miejscu.
- **LOG-10 · Gubienie ogona** `v1`. Zmiana auta w przygotowanym wcześniej garażu, przebranie się w aucie. Opis świadka przestaje pasować.
- **LOG-11 · Spalenie auta** `v1`. Kanister i zapalniczka usuwają ślady z auta, ale dym przyciąga uwagę (dispatch: „płonący pojazd”).
- **LOG-12 · Kurier łupu** `v2`. Za prowizję NPC odbiera łup z punktu i po 30 min dostarcza go do kryjówki. Bywa przechwycony.
- **LOG-13 · Pieszo albo rowerem** `v1`. Ciche podejście i mały łup. Bez auta świadkowie nie mają tablic.
- **LOG-14 · Parkowanie a świadkowie** `MVP`. Auto stojące pod domem dłużej niż X min zapisuje sąsiadka (NPC-17) albo łapie kamera sąsiada (ZAB-30).
- **LOG-15 · Tetris w bagażniku** `v2`. Łup układasz na siatce w NUI, a dobre ułożenie mieści więcej.

## 14. PRO – Umiejętności, poziomy i reputacja

- **PRO-01 · XP i poziomy** `MVP`. XP za włamania (według poziomu domu, cichości i łupu), rekonesans i sprzedaż. Poziomy odblokowują domy i narzędzia.
- **PRO-02 · Drzewko umiejętności** `v1` 🎮. Zamki (szerszy punkt, mniejsze zużycie wytrychów), Skradanie (cichsze kroki, lepsze chowanie się), Siła (+kg udźwigu, szybsze noszenie), Zręczność (szybsze przeszukiwanie), Elektronika (dłuższy jammer, łatwiejsze hakowanie), Handel (ceny, targowanie), Oko (wycena, podświetlanie łupu).
- **PRO-03 · Punkty i reset** `v1`. Punkt umiejętności za każdy poziom, reset drzewka za opłatą.
- **PRO-04 · Nauka przez praktykę** `v1`. Tryb alternatywny: im więcej otwierasz zamków, tym lepiej ci idzie. Config pozwala wybrać drzewko, praktykę albo oba.
- **PRO-05 · Reputacja u kontaktów** `MVP`. Osobne paski u pasera, zleceniodawcy i informatora. Otwierają zlecenia i ceny.
- **PRO-06 · Mnożnik za ocenę S–F** `MVP`. „Czysty skok” (0 wykryć, 0 śladów) daje premię (SKR-23).
- **PRO-07 · Style gry** `v1`. „Duch” (bez wykrycia), „Błyskawica” (poniżej X min), „Odkurzacz” (cały dom). Odznaki i mnożniki.
- **PRO-08 · Osiągnięcia** `v1` 🎮. Nagrody kosmetyczne: wzór na wytrychu, motyw laptopa, ramka notatnika.
- **PRO-09 · Wyzwania dzienne i tygodniowe** `v1`. „Ukradnij 3 konsole bez wykrycia”, „Otwórz sejf stetoskopem”.
- **PRO-10 · Ranking** `v2`. Tygodniowy ranking na pseudonimach złodziei, z nagrodami.
- **PRO-11 · Kara za wpadkę** `MVP`. Przy zatrzymaniu przepada część XP albo reputacji (config) i narzędzia.
- **PRO-12 · Specjalizacje** `v2`. Od pewnego poziomu wybierasz kasiarza, hakera, włamywacza albo tragarza. Specjalizacja wzmacnia rolę w ekipie (EKI-02).
- **PRO-13 · Mentoring** `v1`. Doświadczony złodziej, który zabiera nowicjusza, dostaje premię XP. Ułatwia wejście nowym graczom.
- **PRO-14 · Legenda** `v2`. Przy wysokiej reputacji dispatch pisze np. „styl działania przypomina «Cienia»”. Klimat dla RP.
- **PRO-15 · Wizytówka złodzieja** `v2`. Możesz zostawić podpis, np. figurkę kruka. Daje reputację, ale policja łączy sprawy w serię (POL-12).
- **PRO-16 · Samouczek fabularny** `MVP` 🎮. Pierwsze zlecenia z mentorem uczą mechanik krok po kroku, jak Vinny w TS.
- **PRO-17 · Odblokowania przez zlecenia** `v1`. Stetoskop dopiero po misji „Kasiarz”, elektroniczny wytrych po misji „Technik” itd.
- **PRO-18 · Integracja z zewnętrznymi systemami XP** `v1`. Hook do popularnych systemów reputacji i umiejętności na serwerze.

## 15. ZLE – Zlecenia, fabuła i zdarzenia losowe

- **ZLE-01 · Zleceniodawca w stylu Vinny'ego** `MVP` 🎮. Mentor kontaktuje się przez telefon albo laptop i daje zlecenia z fabularnym tekstem.
- **ZLE-02 · Kampania w 5 rozdziałach** `v1`. Od drobnych kradzieży do willi z tajemnicą, np. kompromitujących dokumentów. Dialogi i lekkie przerywniki (kamera i napisy).
- **ZLE-03 · Zlecenie na konkretny przedmiot** `MVP`. „Obraz z salonu” ze zdjęciem jako podpowiedzią. Premia, a rekonesans konieczny.
- **ZLE-04 · Tylko dokumenty** `v1`. Sejf w gabinecie. Premia za „czystą robotę”, żeby właściciel długo się nie zorientował.
- **ZLE-05 · Podrzucenie przedmiotu** `v2`. Odwrotny skok: podrzucasz coś do domu bez śladów.
- **ZLE-06 · Zdjęcia zamiast kradzieży** `v1`. Fotografujesz plany w gabinecie telefonem i niczego nie ruszasz.
- **ZLE-07 · Auto z garażu na zamówienie** `v1` 🎮. Konkretny model w dobrym stanie, dostarczony na czas.
- **ZLE-08 · Zdarzenia losowe w trakcie** `MVP`. Domownik wraca wcześniej, kurier dzwoni do drzwi, dzwoni telefon, budzik o 3:00, awaria prądu w dzielnicy (kamery gasną!), burza, pies sąsiada się zrywa, przejeżdża patrol.
- **ZLE-09 · Inny złodziej w środku** `v1`. W domu jest już NPC-rywal. Możesz go przegonić, przeczekać albo przejąć jego torbę.
- **ZLE-10 · Automatyczna sekretarka** `v1`. Odsłuchanie wiadomości w domu daje informacje, np. kod do garażu od męża albo „wracamy w piątek”.
- **ZLE-11 · Gang z konkurencji** `v2`. NPC-owy gang „rezerwuje” dzielnicę. Wejście na jego teren to konfrontacja albo haracz, a do tego misje sabotażu.
- **ZLE-12 · Tygodniowy wielki skok** `v2`. Raz w tygodniu willa z wyjątkowym łupem dla jednej ekipy. Wyścig o zdobycie planów.
- **ZLE-13 · Eventy sezonowe** `v2`. Święta (tryb Grincha), Halloween (przebrania mniej podejrzane), wakacje (dużo pustych domów, ale lepsze alarmy).
- **ZLE-14 · Moralne wybory** `extra`. Dom okazuje się biedny albo mieszka w nim chory człowiek. Odejście daje karmę i reputację u części kontaktów.
- **ZLE-15 · Tablica zleceń w darknecie** `v1`. Zlecenia z terminem i kaucją, która przepada, jeśli zawalisz.
- **ZLE-16 · Łańcuchy zleceń** `v1`. W sejfie jest mapa albo klucz do kolejnego miejsca. Proceduralne mini-fabuły.
- **ZLE-17 · Zlecenia od graczy** `v2`. Gracz zleca kradzież konkretnej rzeczy i płaci depozyt przez system.
- **ZLE-18 · Przekręt ubezpieczeniowy** `v2`. Właściciel zleca „włamanie” do własnego domu. Łatwe, ale śledczy może to wykryć. Świetne RP dla policji.
- **ZLE-19 · Poczta w laptopie** `MVP` 🎮. Zlecenia, plotki, podpowiedzi, wiadomości od paserów.
- **ZLE-20 · Wezwanie od zleceniodawcy w trakcie** `v1`. „Zmiana planów, w gabinecie jest coś ważniejszego”. Cel zmienia się w czasie akcji.

## 16. EKI – Współpraca, ekipy i multiplayer

- **EKI-01 · System ekipy** `MVP`. Do 4 osób. Wspólny bucket, wspólny notatnik, podział łupu: równo, według ról albo decyzją lidera.
- **EKI-02 · Role z bonusami** `v1`. Czujka (większy zasięg ostrzeżeń), haker, zamki, tragarz (+udźwig). Bonusy działają tylko w ekipie.
- **EKI-03 · Czujka na zewnątrz** `MVP`. Oznaczenia z lornetki („auto podjeżdża!”) widzi ekipa w środku, razem ze wskaźnikiem zagrożenia.
- **EKI-04 · Wspólne minigry** `v1`. Jeden świeci latarką albo trzyma napinacz, drugi pracuje wytrychem. Przy sejfie jeden słucha stetoskopem, drugi kręci tarczą.
- **EKI-05 · Ciężkie rzeczy we dwóch** `v1`. Sejf, lodówka, fortepian elektryczny, z synchronizowanymi animacjami.
- **EKI-06 · Podawanie przez okno** `v1`. Łańcuch podawania łupu przyspiesza opróżnianie domu.
- **EKI-07 · Cicha komunikacja** `MVP`. Radio (pma-voice), szybkie koło gestów („stój”, „cisza”, „uciekamy”, „tutaj”). Głos w domu jest słyszalny (SKR-24).
- **EKI-08 · Wspólna tablica** `v1`. REK-12 synchronizowana dla ekipy.
- **EKI-09 · Zdrada** `extra`. Członek ekipy może uciec z łupem z auta. Serwer decyduje, czy podział jest automatyczny, czy „na słowo” (RP).
- **EKI-10 · Kapowanie** `extra`. Zatrzymany może „sypnąć”, a policja dostaje pseudonimy ekipy.
- **EKI-11 · Rywalne ekipy** `v2`. Ta sama okazja dla dwóch ekip. Wygrywa pierwsza, a sabotaż to np. anonimowy telefon na policję.
- **EKI-12 · Ochrona osiedla dla graczy** `v2`. Praca dla graczy: patrol i odbiór alarmów w aplikacji. Naturalna kontra dla złodziei.
- **EKI-13 · Aplikacja w telefonie** `v1`. lb-phone, qs-smartphone, npwd, yseries: zlecenia, ekipa, notatnik, sklep.
- **EKI-14 · Kierowca w aucie** `v1`. Czeka ukryty ze zgaszonymi światłami i szybko podjeżdża na ping.
- **EKI-15 · Premia za zgranie** `v1`. Udane podanie przez okno albo wspólna minigra daje XP.
- **EKI-16 · Zaproszenia i rekrutacja** `v2`. Ogłoszenia „szukam czujki” w aplikacji, z oceną graczy po wspólnych akcjach.

## 17. UIX – UI/UX, HUD, aplikacje i minigry NUI

- **UIX-01 · Minimalistyczny HUD włamania** `MVP`. Hałas, widoczność, stan alarmu, czas, udźwig. Pokazywany tylko w domu i aktualizowany tylko przy zmianie wartości.
- **UIX-02 · Laptop złodzieja** `MVP` 🎮. Aplikacje: Sklep, Aukcje, Poczta i zlecenia, Umiejętności, Notatnik, Mapa okazji, Podgląd drona.
- **UIX-03 · Telefon w terenie** `v1`. Uproszczona wersja laptopa: notatnik, mapa okazji, ekipa.
- **UIX-04 · Notatnik w stylu odręcznym** `MVP`. Rysowany na canvasie. Oś czasu 24 h z paskami obecności domowników, lista zabezpieczeń, znalezione kody.
- **UIX-05 · Plan domu jak mgła wojny** `v1`. Rysowany z definicji pokoi i odkrywany w miarę zwiedzania. Zaznacza kamery, czujki, łupy i okna widoczne z ulicy.
- **UIX-06 · Plecak na siatce** `v2`. Opcjonalny tryb układania łupu jak w tetrisie.
- **UIX-07 · Karta przedmiotu** `MVP`. Nazwa, szacunkowa wartość, waga, kruchość, czy jest gorący.
- **UIX-08 · Spójny katalog minigier** `MVP`. Wytrych TS, SPP, grabie, bump, kłódka i shim, sejf z tarczą, keypad z UV, przewody, bezpieczniki, wycinanie szkła, wiertło, dekoder pilota, hakowanie Wi-Fi, targowanie, czyszczenie numerów. Jeden styl i jeden silnik.
- **UIX-09 · Podgląd minigier w przeglądarce** `MVP`. Tak jak w `dp-spawacz`: `index.html?demo=lockpick&tier=C` bez serwera.
- **UIX-10 · Dostępność** `v1`. Tryb dla daltonistów, skalowanie UI, napisy do dźwięków („[skrzypienie]”), tryb bez migania.
- **UIX-11 · Tłumaczenia** `MVP`. PL i EN na start, pliki `locales/`.
- **UIX-12 · Znaczniki nad NPC** `v1`. „?” i „!”, wyłączane w hardcore.
- **UIX-13 · Podpowiedzi bez DrawText co klatkę** `MVP`. Target albo jeden helper dla najbliższego punktu.
- **UIX-14 · Raport po włamaniu** `MVP`. Czas, łup, hałas, wykrycia, ślady, ocena S–F z pieczątką.
- **UIX-15 · Widok przez szparę i endoskop** `v1`. Efekty postprocessu z timecycle, przyciemniona winieta.
- **UIX-16 · Styl graficzny „noir”** `MVP`. Papierowe notatki, taśma, pinezki i neonowe ekrany gadżetów.
- **UIX-17 · Dźwięki syntezowane** `MVP`. Piny, sprężyny, stetoskop, bicie serca, szum. Bez plików audio.
- **UIX-18 · Klawisze do zmiany** `MVP`. Przez `RegisterKeyMapping` w ustawieniach FiveM.
- **UIX-19 · Podpowiedzi przy pierwszym użyciu** `v1`. Kontekstowy samouczek każdego narzędzia, pokazywany raz.

## 18. TEC – Architektura, optymalizacja, anty-exploit i integracje

- **TEC-01 · Maszyna stanów klienta z budżetami** `MVP`. Stany IDLE, NEAR, RECON, INSIDE, MINIGAME i ESCAPE z sekcji 0. Każda pętla ma właściciela, budżet i warunek wyjścia.
- **TEC-02 · Strefy zamiast pętli dystansu** `MVP`. `lib.zones` / `lib.points` z ox_lib, z własnym fallbackiem (siatka przestrzenna 100 m). Nie ma iteracji po wszystkich domach.
- **TEC-03 · Oszczędna synchronizacja** `MVP`. Statebagi encji dla drzwi i alarmu, eventy tylko do ekipy, flaga `inBurglary` w statebagu gracza, a `GlobalState` tylko dla małych liczników.
- **TEC-04 · Serwer autorytatywny** `MVP`. Seedy, tokeny jednorazowe, rekordy łupu, sprawdzanie dystansu (`GetEntityCoords(GetPlayerPed(src))`), czasów minigier i limitów wywołań.
- **TEC-05 · Anti-dupe i anti-exploit** `MVP`. UUID łupu, blokady po stronie serwera, idempotentne zabranie, logi podejrzanych wyników.
- **TEC-06 · Zapis danych** `MVP`. Domyślnie KVP (bez bazy), opcjonalnie oxmysql. Zapisy zbierane w paczki co X min i przy wyjściu gracza.
- **TEC-07 · Bridge i integracje** `MVP`. Frameworki: ESX, QBCore, QBox, ox_core, ND, standalone. Inwentarze: ox, qb, qs, codem, tgiann, core, ps. Target: ox_target, qb-target. Do tego dispatch, dowody, telefony, housing, kluczyki i rękawiczki z ubrania.
- **TEC-08 · API dla deweloperów** `v1`. Eksporty i eventy: `onBurglaryStart/End`, `onLootTaken`, `onAlarm`, `onEvidence` i kontrola z zewnątrz, np. `ForceHouseCooldown`.
- **TEC-09 · Otwarta konfiguracja** `MVP`. Config, locales, bridge, hooki i domy w JSON są otwarte, a logika może być w escrow przy sprzedaży na Tebexie.
- **TEC-10 · Logi** `v1`. Discord webhook albo ox_lib logger (Fivemanage, Datadog, Loki): włamania, sprzedaż, odrzucone wyniki.
- **TEC-11 · Nakładka debug** `v1`. Rysuje pokoje, stożki kamer i NPC oraz graf hałasu, pokazuje liczniki czasu wątków. Tylko przy `Config.Debug`.
- **TEC-12 · Test obciążenia** `v1`. Komenda symuluje N włamań po stronie serwera i mierzy czas. Dowód dla klientów, że skrypt jest wydajny.
- **TEC-13 · Streaming modeli** `MVP`. Wczytywanie z limitem czasu, wcześniejsze ładowanie przy zbliżeniu do drzwi, zawsze `SetModelAsNoLongerNeeded`.
- **TEC-14 · Pula encji i sprzątanie** `MVP`. Pula propów łupu. Sprzątanie przy wyjściu, `playerDropped` i `onResourceStop`, bez osieroconych encji.
- **TEC-15 · Percepcja „najtańsze najpierw”** `MVP`. Opisana w sekcji 0.3: wspólna biblioteka dla NPC, kamer i PIR.
- **TEC-16 · Paczki zdarzeń hałasu** `MVP`. Max 4 na sekundę do hosta i serwera, łączone w oknie 250 ms.
- **TEC-17 · Wydajne NUI** `MVP`. Leniwe moduły minigier, zatrzymany `requestAnimationFrame` w tle, typowane tablice, wiadomości tylko przy zmianie.
- **TEC-18 · Sprawdzanie wersji** `v1`. Informacja o nowej wersji z GitHuba w konsoli, changelog.
- **TEC-19 · Panel admina** `v1`. Aktywne włamania, reset domu, teleport, podgląd logów, ceny, heat dzielnic.
- **TEC-20 · Presety serwera** `v1`. Casual, Realistic, Hardcore. Jeden przełącznik zmienia kilkadziesiąt parametrów, a każdy da się nadpisać.
- **TEC-21 · Minimalne zależności** `MVP`. ox_lib zalecane, ale nie wymagane. Działa na OneSync Infinity i Legacy.
- **TEC-22 · Dokumentacja i przykładowe domy** `v1`. README jak w `dp-spawacz` plus paczka 20–30 gotowych domów.
- **TEC-23 · Testy jednostkowe logiki** `v2`. Czysta logika (graf hałasu, generator profilu, ceny, tabele łupu) w osobnych modułach Lua, testowana poza grą (busted).
- **TEC-24 · Odporność na restart zasobu** `v1`. Po `restart dp-wlamywacz` aktywne włamania bezpiecznie się kończą: łup wraca albo zostaje przyznany, gracze wychodzą z bucketów.

---

## Proponowany zestaw startowy (MVP)

Najmniejsza całość, która już jest grywalna od początku do końca: rekonesans → wejście → dom z domownikami i zabezpieczeniami → łup → ucieczka → paser → progresja.

- **Rekonesans:** REK-01, 02, 04, 06, 11, 14, 15, 21
- **Wejścia:** WEJ-01, 02, 03, 04, 05, 06, 08, 16, 19, 24
- **Zamki i wytrychy:** ZAM-01, 04, 06, 10, 12, 16, 21 · WYT-01, 03, 05, 09, 15, 16, 17
- **Narzędzia:** NAR-01, 02, 03, 04, 06, 08, 09, 14, 15, 17, 22, 27, 33, 37
- **Zabezpieczenia:** ZAB-01, 02, 03, 08, 11, 12, 18, 22, 25, 32
- **AI:** NPC-01, 02, 03, 04, 05, 09, 13, 18, 21, 26, 27
- **Skradanie:** SKR-01, 02, 03, 04, 05, 07, 08, 10, 13, 23
- **Łup:** LUP-01, 02, 03, 04, 05, 07, 14, 22, 25
- **Paser:** PAS-01, 02, 09, 12, 13, 21
- **Policja:** POL-01, 02, 03, 08, 10, 16, 18
- **Domy:** DOM-01, 02, 04, 05, 07, 09, 11, 16, 17, 23, 24
- **Logistyka i progresja:** LOG-01, 14 · PRO-01, 05, 06, 11, 16
- **Zlecenia, ekipa, UI:** ZLE-01, 03, 08, 19 · EKI-01, 03, 07 · UIX-01, 02, 04, 07, 08, 09, 11, 13, 14, 16, 17, 18
- **Technika:** TEC-01…07, 09, 13…17, 21

Najlepsze kandydatury do `v1` (to one robią „najlepszy skrypt na rynku”): WYT-02, WYT-10, WYT-11, ZAB-17, ZAB-21, NPC-06, NPC-08, NPC-28, SKR-12, SKR-18, SKR-24, LUP-10, PAS-03, PAS-07, POL-06, POL-07, DOM-08, EKI-04, TEC-20.

## Decyzje do podjęcia przed pisaniem kodu

1. **Wnętrza:** same shelle w instancjach, shelle z opcjonalnymi MLO (DOM-01, DOM-03) czy własne MLO?
2. **Framework docelowy:** wszystkie przez bridge (jak w `dp-spawacz`) czy jeden główny (np. QBox + ox_inventory) i reszta później?
3. **Poziom realizmu domyślnie:** Casual czy Realistic (TEC-20)? Od tego zależy, czy minigra SPP (WYT-02) jest domyślna.
4. **Przemoc:** czy domownicy mogą mieć broń, a złodziej obezwładniać (NPC-10, NAR-38, SKR-19)? Domyślnie proponuję „wyłączone”.
5. **Domy graczy (DOM-15):** w ogóle, tylko jako opcja, czy wcale?
6. **Dane:** KVP bez bazy (jak `dp-spawacz`) czy oxmysql od razu (przyda się przy rejestrze skradzionych przedmiotów i MDT)?
7. **Sprzedaż:** Tebex z escrow (TEC-09) czy wydanie otwarte?
