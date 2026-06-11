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

Im aktuellen Prototyp kann der Spieler in Studio die Taste `B` druecken. Der Client fragt dann beim Server an, ein `House` vor dem Spieler zu platzieren. Der Server snappt die Position auf das Grid, prueft grob belegte Zellen und erstellt ein einfaches Placeholder-Gebaeude in `Workspace/PlacedBuildings`, falls noch kein echtes Model existiert.

Es gibt noch keine finale UI, keine echten Gebaeude-Modelle, keinen Economy-Check und keinen DataStore. Diese Struktur ist bewusst klein gehalten, damit die naechsten Systeme sauber darauf aufbauen koennen.
