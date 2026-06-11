# Cel-City

Cel-City ist ein Roblox City Builder Projekt mit plain Luau, Rojo, GitHub und VS Code.

## Branching

Dieses Repo nutzt einen vereinfachten Git-Flow. Die Regeln stehen in `BRANCHES.md`.

## Projektstruktur

- `src/ReplicatedStorage/Shared` enthält Code, den Client und Server lesen dürfen.
- `src/ReplicatedStorage/Remotes` enthält RemoteEvents für Client-Server-Kommunikation.
- `src/ServerScriptService` enthält serverseitige Scripts und Services. Der Server bleibt authoritative.
- `src/StarterPlayer/StarterPlayerScripts` enthält clientseitige Scripts und Controller.
- `src/Workspace/Map` ist der Platz für spätere Map-Objekte.

## Arbeiten mit VS Code + Rojo

1. Repo in VS Code öffnen.
2. Rojo Server starten, zum Beispiel mit `rojo serve default.project.json`.
3. Roblox Studio öffnen.
4. Im Rojo Plugin mit dem laufenden Rojo Server verbinden.
5. Änderungen in VS Code schreiben und in Studio testen.

## Aktueller Flow

Der Client hat bereits einen `PlacementController`, der später eine Platzierungsanfrage an den Server senden kann. Der Server nimmt diese Anfrage in `PlacementService` entgegen und prüft dort zentral Gebäude-Konfiguration, Grid-Position und Economy-Regeln.

Es gibt noch keine UI, keine echten Gebäude-Modelle und keinen DataStore. Diese Struktur ist bewusst klein gehalten, damit die nächsten Systeme sauber darauf aufbauen können.
