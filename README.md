# Cel-City

Cel-City ist ein Roblox City Builder Projekt mit plain Luau, Rojo, GitHub und VS Code.

## Branching

Dieses Repo nutzt einen vereinfachten Git-Flow. Die Regeln stehen in `BRANCHES.md`.

## Projektstruktur

- `src/ReplicatedStorage/Shared` enthaelt Code, den Client und Server lesen duerfen.
- `src/ReplicatedStorage/Remotes` enthaelt RemoteEvents fuer Client-Server-Kommunikation.
- `src/ServerScriptService` enthaelt serverseitige Scripts und Services. Der Server bleibt authoritative.
- `src/StarterPlayer/StarterPlayerScripts` enthaelt clientseitige Scripts und Controller.
- `src/Workspace/Map` ist der Platz fuer spaetere Map-Objekte.
- `src/Workspace/PlacedBuildings` enthaelt zur Laufzeit platzierte Gebaeude.

## Arbeiten mit VS Code + Rojo

1. Repo in VS Code oeffnen.
2. Rojo Server starten, zum Beispiel mit `rojo serve default.project.json`.
3. Roblox Studio oeffnen.
4. Im Rojo Plugin mit dem laufenden Rojo Server verbinden.
5. Aenderungen in VS Code schreiben und in Studio testen.

## Aktueller Flow

Im aktuellen Prototyp sieht der Spieler eine lokale Ghost Preview fuer ein `House`. Die Preview folgt der Maus, snappt auf das Grid und zeigt einfache Bounds-Gueltigkeit:

- `B` schaltet den Build Mode ein oder aus.
- `R` rotiert die Preview um 90 Grad.
- Linksklick fragt beim Server an, das aktuell angezeigte `House` zu platzieren.

Der Client sendet nur `buildingId`, Position und Rotation. Der Server snappt/validiert erneut, prueft Bounds, Wasser/Gravel, belegte Zellen und Kosten. Bei erfolgreicher Platzierung zieht der Server Geld ab und erstellt ein einfaches Placeholder-Gebaeude in `Workspace/PlacedBuildings`, falls noch kein echtes Model existiert.

Es gibt noch keine finale UI, keine echten Gebaeude-Modelle und keinen DataStore. Diese Struktur ist bewusst klein gehalten, damit die naechsten Systeme sauber darauf aufbauen koennen.

## Economy

`EconomyService` verwaltet aktuell nur Session-Geld. Jeder Spieler startet mit `1000` Money. Der Geldstand ist ueber Roblox `leaderstats` sichtbar.

Beim Platzieren prueft der Server `Buildings[buildingId].Cost`. Geld wird nur abgezogen, wenn alle Placement-Checks bestanden sind und das Gebaeude wirklich platziert wird. Wenn der Spieler nicht genug Geld hat, antwortet der Server mit `PlacementResult.Reason = "NotEnoughMoney"` und der Client faerbt die Preview rot.

Der Client zeigt oben rechts eine kleine Money-Anzeige. Wenn Geld ausgegeben wird, erscheint kurz ein rotes Minus-Popup unter der Anzeige.

Noch nicht enthalten:

- Kein DataStore.
- Kein Einkommen pro Gebaeude.
- Keine finale Economy-UI.
- Kein Balancing.

## Grid-System

Das Grid liegt in `ReplicatedStorage/Shared/Util/Grid.lua`, damit Client und Server dieselben Koordinatenregeln lesen koennen. Die finale Entscheidung bleibt trotzdem immer auf dem Server.

Aktuelle Grid-Config:

- `TileSize = 4`
- `MinX = -50`
- `MaxX = 50`
- `MinY = -50`
- `MaxY = 50`

`worldToGrid` wandelt eine Roblox-World-Position in eine Grid-Zelle um. `gridToWorld` wandelt eine Grid-Zelle wieder in eine World-Position. `getOccupiedCells` berechnet alle Zellen, die ein Gebaeude mit einer bestimmten Groesse belegt. Rotation ist fuer `0`, `90`, `180` und `270` Grad vorbereitet; bei `90` und `270` wird die Footprint-Groesse logisch gedreht.

Bounds bedeuten: Der Server akzeptiert Platzierungen nur innerhalb `MinX..MaxX` und `MinY..MaxY`. Zellen ausserhalb dieses Bereichs werden abgelehnt.

Optionales Debug-Grid:

1. `src/ServerScriptService/Services/PlacementService.lua` oeffnen.
2. `local DEBUG_GRID = false` auf `true` setzen.
3. Rojo synchronisieren lassen und Studio neu starten oder Play neu starten.
4. Die Debug-Linien erscheinen in `Workspace/GridDebug`.

Der naechste sinnvolle Schritt nach diesem Branch ist `feature/save-system`: platzierte Gebaeude, Rotation und Geldstand speichern und beim Join wiederherstellen.

## Terrain Style

`TerrainService` setzt eine einfache stilisierte Material-Palette fuer Roblox Terrain. Zusaetzlich werden erste prozedurale Platzhalter-Details erzeugt:

- einfache Grasbueschel auf trockenem Huegelboden
- importierte Baum-Modelle fuer Waelder

Diese Details sind bewusst temporaer. Spaeter koennen echte Low-Poly-Felsen, bessere Gras-Assets und Ufer-Meshes in `ServerStorage` importiert und von `TerrainService` statt der Platzhalter genutzt werden. Die prozeduralen Ufer-Pebbles sind deaktiviert, weil sie auf dem Wasser nicht gut lesbar waren.

Beim Serverstart loggt `TerrainService` jeden Generierungsschritt im Output. `Workspace/GeneratedMap` wird vor jeder Neugenerierung geleert, damit alte Wald- oder Deko-Objekte nicht mehrfach liegen bleiben.

## Save System

`SaveService` definiert bereits die Datenform fuer spaetere Speicherung:

- `Money`
- platzierte Gebaeude mit `BuildingId`, Grid-Origin und Rotation

DataStore-Laden und -Speichern sind implementiert, aber aktuell bewusst deaktiviert (`DATASTORE_ENABLED = false` in `SaveService.lua`). Der Service sammelt die Daten in der Session und kann diese Struktur bereits auf `EconomyService` und `PlacementService` anwenden. Sobald API Services in Studio/Experience aktiv sind, kann der Schalter fuer echte Persistenz eingeschaltet werden.
