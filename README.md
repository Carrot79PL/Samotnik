# Samotnik

Spokojna gra logiczna Samotnik (peg solitaire) na macOS, z białymi i czarnymi kulkami na trójwymiarowej planszy. Gra jest napisana w Swift i SceneKit, bez silnika i bez zewnętrznych zależności. Wszystkie tekstury i muzyka powstają w kodzie.

**Wersja:** 1.0  ·  **Autor:** Tomasz Marchewka

## Zasady

Kulka przeskakuje sąsiednią kulkę w poziomie lub w pionie i ląduje na wolnym polu za nią. Przeskoczona kulka znika z planszy. Celem jest zostawić jak najmniej kulek, najlepiej jedną.

## Co jest w grze

- **60 plansz**, po 20 na każdy poziom trudności. Są wśród nich klasyczne krzyże, gwiazdy i plansze asymetryczne. Solver sprawdził, że każda da się rozwiązać.
- **Generator losowych plansz.** Tworzy spójny kształt i szuka pola startowego, z którego solver potrafi dojść do jednej kulki.
- **Trzy poziomy trudności:**

  | Poziom | Cel | Pomoc | Punkty |
  |---|---|---|---|
  | Łatwy | najwyżej 4 kulki | podświetlone ruchy, podpowiedź z solvera (klawisz H), cofanie bez limitu | ×1 |
  | Normalny | najwyżej 2 kulki | cele po wybraniu kulki, 3 cofnięcia | ×1,5 |
  | Trudny | 1 kulka | bez podpowiedzi i cofania, limit 6 s na kulkę | ×2 |

- **Samouczek:** gra sama rozgrywa planszę i objaśnia ruchy.
- **Gracze i tabela rekordów** dla każdej planszy. Imię wpisuje się w samej grze.
- **Motyw ciemny i jasny** z płynnym przenikaniem między nimi.

## Grafika i dźwięk

- Fizyczne materiały (PBR) i studyjne oświetlenie HDR. Bloom, SSAO, delikatna głębia ostrości, winieta i antyaliasing MSAA 8×. Obraz jest ostry na ekranach 4K i Retina.
- Plansza lekko przechyla się w stronę kursora. Miękkie cienie podążają za światłem.
- Każda kulka jest trochę inna: ma własny obrót, odcień i drobne zabrudzenia.
- Plansza nosi ślady używania: odciski palców, mikrorysy, kurz, przetarcia lakieru wokół pól i płytkie odpryski na krawędziach. Rozkład śladów jest losowy w każdej grze.
- Ambientowa muzyka (akordy padów i dzwonki) generowana na żywo syntezatorem w AVAudioEngine.

## Sterowanie

| Gdzie | Klawisze i mysz |
|---|---|
| Gra | klik na kulkę, potem na pole docelowe · **Z** / **U** / Backspace: cofnij · **R** / **N**: nowa gra · **H**: podpowiedź (tylko na Łatwym) · **Esc**: menu |
| Menu | **↑ ↓**: wybór · **← →**: zmiana opcji · **Enter** / spacja: zatwierdź |
| Rekordy | **← →**: zmiana planszy · **Esc**: powrót |

Kliknięcie małego logo w czasie gry pokazuje informacje o grze.

## Uruchomienie

Wymagania: macOS 14 lub nowszy, Mac z procesorem Apple Silicon i narzędzia Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

```bash
open Samotnik.app
```

Skrypt kompiluje źródła przez `swiftc`, generuje ikonę i podpisuje aplikację lokalnie (ad hoc). Żeby gra była widoczna w Launchpadzie, skopiuj ją do Aplikacji:

```bash
cp -R Samotnik.app /Applications/
```

Zapis graczy i rekordów leży w `~/Library/Application Support/Samotnik/zapis.json`.

## Struktura kodu

| Plik | Zawartość |
|---|---|
| `main.swift` | scena 3D, motywy, interfejs (menu, rekordy, samouczek), logika gry |
| `Data.swift` | plansze, poziomy trudności, zestawy kulek, gracze i zapis |
| `Solver.swift` | solver (DFS na maskach bitowych z pamięcią przegranych pozycji) i generator losowych plansz |
| `Texture.swift` | proceduralne tekstury kulek (szum, fbm, Worley) i mapa środowiska HDR |
| `BoardWear.swift` | ślady zużycia planszy i odpryski krawędzi |
| `Core.swift` | pomocnicze funkcje kolorów i syntezator muzyki |
| `Icon.swift` | generator ikony aplikacji |
| `build.sh` | budowanie pakietu `.app` |
