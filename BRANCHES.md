# Branches

## Purpose

This repository uses a simplified Git Flow workflow.

All contributors and AI coding agents (Codex, ChatGPT, Cursor, Claude, etc.) must follow these rules.

## Branches

### main

Production-ready branch.

Rules:

- Never commit directly to main.
- Never create experimental code on main.
- Only merge tested code from develop.
- main should always be deployable.

### develop

Main development branch.

Rules:

- All completed features are merged into develop.
- develop may contain unfinished project features.
- develop should remain stable whenever possible.

### feature branches

Naming:

```txt
feature/<feature-name>
```

Examples:

```txt
feature/grid-system
feature/building-placement
feature/economy
feature/ui
feature/datastore
feature/roads
feature/cel-shading
```

Rules:

- One branch = one feature.
- Keep feature branches small.
- Merge into develop when finished.
- Keep feature branches after merging (do not delete them).

## Commit Convention

Format:

```txt
type: short description
```

Examples:

```txt
feat: add grid system
feat: implement building placement
fix: resolve placement collision bug
refactor: simplify placement service
docs: update README
```

## Development Workflow

1. `main` contains stable code.

2. Create feature branch:

```bash
git checkout develop
git pull

git checkout -b feature/grid-system
```

3. Work on feature.

4. Commit changes:

```bash
git add .
git commit -m "feat: add grid coordinate conversion"
```

5. Merge into develop:

```bash
git checkout develop
git merge feature/grid-system
```

6. Keep the feature branch (do not delete it).

7. When multiple features are tested:

```bash
git checkout main
git merge develop
```

## AI Agent Rules

When generating code:

- Never commit directly to main.
- Never create new branches without reason.
- Suggest a feature branch when work affects a major system.
- Keep commits focused on a single feature.
- Prefer multiple small commits over one huge commit.
- Update README when architecture changes.
- Update this document when branching strategy changes.

## Current Project Roadmap

Planned feature branches:

```txt
feature/project-setup
feature/grid-system
feature/building-placement
feature/economy
feature/save-system
feature/ui
feature/cel-shading
feature/roads
feature/buildings-pack-01
feature/buildings-pack-02
feature/city-expansion
```

Always complete systems in this order:

1. project setup
2. grid system
3. building placement
4. economy
5. save system
6. UI
7. cel shading polish
8. content expansion
