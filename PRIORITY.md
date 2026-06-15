# PRIORITY.md

Diese Datei beschreibt, woran im Projekt als Naechstes gearbeitet werden soll. Sie ist fuer Entwickler und AI-Agenten gedacht, damit nicht zufaellig an Nebenthemen gearbeitet wird.

## Regeln

- Vor jeder groesseren Aufgabe `CODEX.md`, `TODO.md`, `BRANCHES.md` und diese Datei lesen.
- `TODO.md` bleibt die vollstaendige Aufgabenliste.
- `PRIORITY.md` beschreibt nur die aktuelle Reihenfolge und den Arbeitsfokus.
- Nach jedem abgeschlossenen Priority-Punkt diese Datei aktualisieren.
- Abgeschlossene Punkte in den Bereich `DONE` verschieben oder dort kurz zusammenfassen.
- Keine neuen grossen Features starten, solange hoehere Prioritaeten sichtbar kaputt oder instabil sind.
- Kleine, fokussierte Commits bevorzugen.

## Aktueller Fokus

Branch: `feature/random-world-seed`

Ziel: Terrain und Placement so stabilisieren, dass Gebaeude, Waelder, Wasserbereiche und Dekorationen visuell sauber zusammenspielen. Erst danach Save/DataStore und UI weiter ausbauen.

## Prioritaeten

### P0 - Gebaeude sauber auf Terrain platzieren

Problem:

- Gebaeude koennen sichtbar ueber oder unter dem Terrain sitzen.
- Gras und Terrain koennen die Modell-Unterseite schneiden.
- Mehrere Gebaeude koennen optisch auf unterschiedlichen Hoehen stehen.
- Die erste Terrain-Plattform-Version kann zu grosse sichtbare Huegel/Plateaus um kleine Gebaeude erzeugen.

Naechste Schritte:

- Einheitliche Bauhoehe pro Placement-Footprint definieren. `[x] erste Version`
- Terrain im Footprint serverseitig zu einer flachen Plattform formen. `[x] erste Version`
- Gebaeude exakt auf die Modell-Unterseite bzw. Plattform setzen. `[x] erste Version`
- Plattform-Footprint und Tiefe reduzieren bzw. an die sichtbare Modell-Unterseite koppeln. `[x] erste Version`
- Plattform-Kanten weich auslaufen lassen, damit keine kuenstlichen Huegel entstehen. `[x] erste Version`
- Save/Restore beruecksichtigen, damit Plattformen nach Laden reproduzierbar sind.

Erfolgskriterium:

- Platzierte Gebaeude stehen sauber auf einer ebenen Flaeche, ohne Luecken, Einsinken oder Hoehenspruenge.

### P1 - Terrain-Artefakte an Wasser, Slate und Hoehlen vermeiden

Problem:

- Slate-/Steinbereiche koennen unnatuerliche Spitzen, schwebende Platten oder Bruecken ueber Wasser bilden.
- Hoehlen duerfen spaeter keine rausragenden Terrain-Reste an Waenden/Eingaengen erzeugen.
- Screenshots zeigen weiterhin herausragende Felsplatten, harte rechteckige Waende und unnatuerliche Bruecken ueber Wasser.

Naechste Schritte:

- Wasser-/Ufer-Carving pruefen und ueberlappende FillBlock-Paesse sauberer trennen. `[x] erste Version`
- Slate-Bank-Formen glatter und kontrollierter machen. `[x] erste Version`
- Debug-Seed-Logging verbessern, damit schlechte Seeds reproduzierbar sind. `[x] erste Version`
- Fels-/Slate-Waende nach dem Carving glaetten und Ueberhaenge/Bruecken gezielt entfernen.

Erfolgskriterium:

- Ufer und Hoehlen wirken absichtlich geformt, nicht wie zufaellige Terrain-Bruchstuecke.

### P2 - Vegetation natuerlicher verteilen

Problem:

- Waelder und Pond-Pflanzen koennen zu gleichmaessig oder gespammt wirken.
- Vegetation muss mit Placement-Blockern synchron bleiben.
- Baeume koennen trotz Surface-Raycasts noch auf Wasser, Slate/Fels oder Ufer-/Carving-Kanten landen.

Naechste Schritte:

- Pond-Pflanzen wie Waelder verteilen: dicht/gross nahe Wasser, kleiner/lockerer nach aussen.
- Wiesen- und Hill-Forests in Studio visuell pruefen.
- Baumplatzierung zusaetzlich nach Terrain-Material und Clearance pruefen.
- Baum- und Pflanzen-Blocker nach jeder Verteilungslogik aktuell halten.

Erfolgskriterium:

- Vegetation liest sich natuerlich: klare Zentren, lockere Raender, keine schwebenden Pflanzen/Baeume.

### P3 - Save-System terrain-sicher machen

Problem:

- DataStore ist vorbereitet, aber Terrain-Seed muss mitgespeichert werden.
- Ohne Seed-Restore koennen gespeicherte Gebaeude nach Reload in Fluss, Pond, Wald oder Huegel landen.

Naechste Schritte:

- Terrain-Seed in Save-Daten aufnehmen.
- TerrainService so erweitern, dass ein gespeicherter Seed beim Start genutzt werden kann.
- Restore-Reihenfolge pruefen: Terrain zuerst, dann Gebaeude.

Erfolgskriterium:

- Gespeicherte Gebaeude laden auf derselben Weltgeometrie wieder.

### P4 - Placement-UX und Delete-Workflow

Problem:

- Spieler bekommt noch wenig klares Feedback.
- Gebaeude koennen nicht provisorisch geloescht werden.

Naechste Schritte:

- Placement-Fehler sichtbar anzeigen.
- Provisorischen Delete-Button bauen.
- Occupied-Zellen fuer alle Spieler bzw. Preview synchronisieren.

Erfolgskriterium:

- Spieler versteht, warum Placement blockiert ist, und kann Fehler korrigieren oder Gebaeude entfernen.

## DONE

- Random Terrain Seed eingefuehrt.
- River, Streams, Pond, Meadow-Forest und Plateau-Hills generiert.
- Wasser-/Pond-/Tree-/Slope-Placement-Checks eingefuehrt.
- Pond-Pflanzen und Wiesen-Baeume als Placement-Blocker registriert.
- Grasbueschel im Gebaeude-Footprint werden beim Platzieren entfernt.
- Gebaeude-Footprints werden beim Platzieren zu einer flachen Terrain-Plattform geformt.
- Gebaeude-Plattformen nutzen eine kleinere modellbasierte Kernflaeche mit flacherem Rand.
- Reservierte Natur-Blocker werden nach erfolgreicher Platzierung im Footprint entfernt.
- Baeume werden auf echte Terrain-Oberflaeche gesetzt.
- Hill-Forests haben dichtere Zentren und kleinere/lockerere Raender.
- Slate-Ufer werden als flache Oberflaechenschicht statt als tiefe massive Bloecke erzeugt.
- River-X-Range, Stream-Starts und Pond-Position werden fuer Seed-Debugging geloggt.
