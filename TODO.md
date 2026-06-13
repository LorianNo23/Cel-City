# TODO

Diese Liste beschreibt sinnvolle naechste Schritte fuer Cel-City. Sie ist bewusst klein und umsetzbar gehalten.

## Aktueller Stand

- Rojo-Projektstruktur existiert.
- Grid-System existiert mit Bounds, Rotation-Footprint und belegten Zellen.
- Building Placement existiert als Prototyp.
- Client zeigt eine graue Ghost Preview.
- Preview wird rot, wenn lokal bekannte belegte Zellen getroffen werden.
- Server validiert Placement authoritative.
- Server erstellt aktuell Placeholder-Gebaeude.
- Economy-Basis existiert mit Session-Geld, `leaderstats/Money` und serverseitigem Kostencheck.
- Geld wird nur bei erfolgreicher Platzierung abgezogen.
- `NotEnoughMoney` wird ueber `PlacementResult` an den Client gemeldet.

## Abgeschlossen in `feature/economy`

- [x] `EconomyService` an `PlacementService` anbinden.
- [x] Startgeld pro Spieler setzen, z.B. `1000`.
- [x] `Buildings[buildingId].Cost` serverseitig pruefen.
- [x] Geld nur bei erfolgreicher Platzierung abziehen.
- [x] `PlacementResult` um `NotEnoughMoney` erweitern.
- [x] Preview rot faerben, wenn Server wegen fehlendem Geld ablehnt.
- [x] Minimalen Geldstand sichtbar machen, z.B. ueber `leaderstats`.
- [x] Keine finale UI bauen.
- [x] Kein DataStore einbauen.

## Abgeschlossen in `feature/sprint-and-lighting`

- [x] Wald-Schatten heller machen (`Ambient`/`OutdoorAmbient` in `CelShadingService` erhoeht).
- [x] Sprinten mit gedrueckter Shift-Taste bei 2x Geschwindigkeit (`SprintController`).

## Abgeschlossen in `feature/random-world-seed`

- [x] Terrain-Seed pro Serverstart zufaellig machen, damit Huegel, Fluss und Baeche jedes Mal anders liegen (gleiche Regeln via `CONFIG`).
- [x] `FIXED_SEED`-Option behalten, um eine bestimmte Welt reproduzieren zu koennen (Seed steht im Log).
- [x] 1-2 sanfte Erhebungen in der Plateau-Wiese generieren, mit Abstand zu Fluss und Baechen.
- [x] Erhebungen wellig/unregelmaessig formen statt als perfekte Kuppel (Noise auf der Oberflaeche).
- [x] Erhebungen breiter, flacher und langgezogen machen (rotierte Ellipsen ueber die ganze Wiese, Hoehe laeuft Richtung Wasser sanft aus).
- [x] Genau eine Erhebung pro Gewaesser-Abteilung, die sich ueber die ganze Abteilung ausbreitet (max. ~5 Studs, problemlos bebaubar).
- [x] Erhebungen natuerlich wellig machen statt als flaches Plateau (Noise-Erhoehungen und -Senken, laeuft an Ufern weiter auf null aus).
- [x] Grasbueschel 15x kleiner machen (erst 5x, dann nochmal 3x).
- [x] Kleinen Teich in der groessten Abteilung generieren, etwas ausserhalb der Mitte (Erd-Ufer statt Gras/Kies, halb so breit wie das Bach-Kiesufer, mit Rohrkolben-Pflanzen).
- [x] Teichpflanzen massiv aufstocken (120-200 statt 6-10) und 3-4x groesser, jede Pflanze mit eigener Zufallsgroesse.
- [x] Teichpflanzen unregelmaessig weit ausbreiten (Noise pro Richtung statt perfekter Kreis), mit Distanz kleiner werdend, und unter jeder Pflanze ein unregelmaessiger Erd-Fleck.
- [x] Teichpflanzen 4x dichter (480-800), Erd-Fleck von ~1 m auf ~30 cm, Mindestgroesse 30 cm pro Pflanze (kleinere spawnen nicht).
- [x] Maximale Ausbreitung der Teichpflanzen auf ~3 m (10.7 Studs) ueber das Ufer begrenzen.
- [x] Eine kleinere Abteilung komplett mit lockerem Wald bedecken.
- [x] Wiesen-Wald auf ~1/3 der Baeume ausduennen (`MeadowForestTreeChance` 0.45 -> 0.15).
- [x] Gebaeudeplatzierung mit Baeumen auf der Wiese abstimmen (Haeuser koennen aktuell in Wiesen-Wald-Baeume hineingebaut werden).
- [x] Harte Regel im Code: Gewaesser darf die Erhebung nie beruehren (jede Terrain-Saeule wird gegen `IsWaterArea` geprueft).

## Terrain erweitern

- [x] Flussverlauf natuerlicher machen: maximal ca. 5 Meter gerade Strecke, danach wieder eine Kurvung einbauen.
- [ ] Hoehlen hinzufuegen, die direkt am Fuss einer Erhebung starten.
- [ ] Gebaeudeplatzierung auf den Plateau-Erhebungen pruefen (Steigung), damit nichts schief oder schwebend steht.

## Naechster Branch: `feature/save-system`

- [x] Datenmodell fuer platzierte Gebaeude definieren.
- [x] Pro Gebaeude in Session-Daten erfassen: `BuildingId`, Grid-Origin, Rotation.
- [x] Geldstand in Session-Daten erfassen.
- [x] Restore-Pipeline fuer Money und platzierte Gebaeude vorbereiten.
- [x] DataStore-Laden beim Join vorbereiten.
- [x] Beim Join gespeicherte Gebaeude aus geladenen Daten serverseitig wiederherstellen.
- [x] DataStore-Fehler sauber behandeln.
- [x] Save-on-leave vorbereiten.
- [ ] `DATASTORE_ENABLED` aktivieren, sobald Studio API Services/Publish-Setup bereit sind.
- [ ] Terrain-Seed mit den Spielstandsdaten speichern und beim Restore wiederverwenden, damit gespeicherte Gebaeude nicht im neu generierten Fluss landen.
- [ ] Autosave waehrend der Session vorbereiten.
- [ ] Keine komplexe Versionierung bauen, solange das Datenmodell klein ist.

## Danach: `feature/ui`

- [x] Kleine Money-Anzeige bauen.
- [x] Rotes Minus-Popup anzeigen, wenn Geld ausgegeben wird.
- [ ] Einfache Building-Auswahl bauen.
- [ ] Ausgewaehltes Gebaeude im `PlacementController` wechseln.
- [ ] Platzierungsfehler kurz anzeigen, z.B. `Occupied`, `OutOfBounds`, `NotEnoughMoney`.
- [ ] UI schlicht halten, keine finale Shop-Oberflaeche.

## Placement verbessern

- [ ] Client-Preview soll auch Server-Fehler kurzfristig anzeigen.
- [ ] Belegte Zellen fuer alle Spieler synchronisieren, nicht nur lokal nach eigener Platzierung.
- [x] Echte Gebaeude-Models aus `ServerStorage/BuildingModels` nutzen.
- [x] Shop-Footprint an quadratischen Modellboden anpassen, damit Preview und 3D-Modell sauber alignen.
- [ ] Placeholder-Farbe/Material spaeter entfernen.
- [ ] Rotation visuell an echten Models pruefen.
- [ ] Map-Bounds besser sichtbar machen.
- [ ] Abbruch-Taste fuer Placement-Modus vorbereiten.

## Grid verbessern

- [ ] Debug-Grid in eigenes Modul auslagern.
- [ ] Bounds-Konfiguration eventuell in eigenes Config-Modul verschieben.
- [ ] Terrain-Steigung pruefen, damit Gebaeude nicht auf zu schraegen Flaechen stehen.
- [ ] Wasser, Strassen und reservierte Flaechen blockieren.
- [ ] Grid-Zellen optional als Debug-Overlay einfaerben.

## Content

- [ ] Einfaches House-Model bauen.
- [ ] Einfaches Shop-Model bauen.
- [ ] Building Config um Kategorie, Beschreibung und IconName erweitern.
- [ ] Erste Balancing-Werte fuer Kosten und Groessen festlegen.
- [ ] Content-Pack Branches erst starten, wenn Economy und Save-System stabil sind.

## Roads

- [ ] Road-Placement als eigenes System planen.
- [ ] Strassen-Zellen separat von Building-Zellen speichern.
- [ ] Gebaeudeplatzierung auf Strassen blockieren.
- [ ] Spaeter Verbindung/Adjacency fuer Stadtlogik nutzen.

## Cel-Shading / Visual Polish

- [x] Erste Terrain-Materialpalette definieren.
- [x] Schlechte prozedurale Ufer-Pebbles wieder deaktivieren.
- [x] Erste prozedurale Grasbueschel erzeugen.
- [x] Terrain-Generation mit Schritt-Logs stabilisieren.
- [x] `Workspace/GeneratedMap` vor Neugenerierung leeren.
- [ ] Einheitlichen visuellen Stil final definieren.
- [ ] Lighting-Preset testen.
- [ ] Materials fuer Placeholder und echte Models vereinheitlichen.
- [ ] Echte Low-Poly-Felsen importieren und statt Platzhalter-Steinen nutzen.
- [ ] Echte Gras-/Busch-Assets importieren und statt Platzhalter-Gras nutzen.
- [ ] Erst nach Core-Gameplay polieren.

## Technische Qualitaet

- [x] `CLAUDE.md` erstellen, damit Claude Code Projektregeln vor jeder Arbeit kennt.
- [x] `CLAUDE.md` um vollstaendiges Projektwissen erweitern (Architektur-Details, Workflow-Regeln, Toolchain).
- [ ] Gemeinsame Result/Reason-Konstanten definieren.
- [ ] Server-Warnungen konsistent halten.
- [ ] README aktualisieren, wenn Architektur oder Testflow sich aendert.
- [ ] Branch-Regeln aus `BRANCHES.md` einhalten.
- [ ] Kleine Branches und fokussierte Commits beibehalten.

## Nicht jetzt bauen

- [ ] Keine finale Shop-UI.
- [ ] Keine Monetarisierung.
- [ ] Keine komplexen Frameworks.
- [ ] Kein roblox-ts.
- [ ] Keine grossen Content-Packs vor Save/Economy/UI.
