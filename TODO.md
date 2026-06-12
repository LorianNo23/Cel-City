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

## Naechster Branch: `feature/save-system`

- [ ] Datenmodell fuer platzierte Gebaeude definieren.
- [ ] Pro Gebaeude speichern: `BuildingId`, Grid-Origin, Rotation.
- [ ] Geldstand speichern.
- [ ] Beim Join gespeicherte Gebaeude serverseitig wiederherstellen.
- [ ] DataStore-Fehler sauber behandeln.
- [ ] Autosave oder Save-on-leave vorbereiten.
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
- [ ] Echte Gebaeude-Models aus `ServerStorage/BuildingModels` nutzen.
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
- [x] Erste prozedurale Ufer-Kies-Details erzeugen.
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
