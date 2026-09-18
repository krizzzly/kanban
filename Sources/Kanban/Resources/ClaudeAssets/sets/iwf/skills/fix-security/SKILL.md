---
name: fix-security
description: Holt den Trivy-Security-Scan aus Jenkins und fixt gefundene Vulnerabilities in einem SEC-Worktree
argument-hint: "[--build <NR>] [--all-severities] [--dry-run]"
disable-model-invocation: true
---

# FIX SECURITY - Trivy-Scan aus Jenkins holen und Vulnerabilities fixen

> ⚙️ **Projektwerte** (`prefix`, `tasksPath`, `repoDir`, `worktreePrefix`, `dockerStack`, `stackDomain`,
> `gitlabProjectPath`): stehen in `.claude/project.json` im Repo-Root. Lies die Datei, bevor du einen
> Projektwert brauchst — nie raten. `dockerStack: false` heisst: kein Docker-Stack — dann gibt es weder
> `stackDomain` noch `iwf`, und Befehle laufen direkt im Worktree.

Du holst den **Trivy-Security-Scan** des Jenkins-Jobs `<repo-ordnername> - DEV - Security`, parst die gefundenen
Vulnerabilities und fixt — falls es **blockierende** (HIGH/CRITICAL) Findings gibt — die Dependency-Bumps in
einem dedizierten **`sec<Datum>`-Worktree**.

> **Zuschnitt:** Dieser Skill ist auf Projekte **mit** Docker-Stack und Jenkins-Security-Job gemünzt — dort
> hat der `sec<Datum>`-Worktree einen eigenen iwf-Stack, in dem Lockfiles regeneriert und Tests gefahren
> werden. Bei **`dockerStack: false`** gibt es weder `iwf` noch Container: dann ist der SEC-Worktree ein
> reiner Git-Worktree (Phase 3B) und das Tooling läuft direkt darin (Phase 4/5). Existiert für das Projekt
> gar kein Jenkins-Security-Job, sag das und brich ab, statt einen Scan zu erfinden.

Platzhalter in spitzen Klammern (`<PREFIX>`, `<repoDir>`, `<worktreePrefix>`, `<stackDomain>`) stehen im
Folgenden für die Werte aus `.claude/project.json`. **`<repo-ordnername>`** ist der letzte Pfadbestandteil
von `repoDir` — er ist zugleich der **Hermes-Projektname** (für die Jenkins-Tools) und der Container-Prefix
des Haupt-Stacks (`<repo-ordnername>-fpm`).

> Befehls-/Routing-Referenz zu Worktrees: `.claude/rules/worktree.md`.
> Worktree-Routing (cwd bleibt Haupt-Repo): wie in `solve-task` Phase 0a.

## Input

$ARGUMENTS

Optionale Flags:

- `--build <NR>` — einen **bestimmten** Jenkins-Build parsen statt des letzten (Default: `lastBuild`).
- `--all-severities` — auch LOW/MEDIUM fixen (Default: nur **HIGH + CRITICAL**, exakt das, worauf der Job selbst
  „failed" markiert).
- `--dry-run` — nur Scan holen + Findings + geplante Fixes ausgeben, **keinen** Worktree anlegen, **nichts** ändern.

---

## Festgelegtes Verhalten (aus der Spec, NICHT erneut erfragen)

1. **Severity-Schwelle:** Default **HIGH + CRITICAL** (= worauf der Jenkins-Job blockt). `--all-severities` erweitert.
2. **Worktree-ID:** **`sec<YYYYMMDD>`** (z.B. `sec20260616`) — **lowercase**, datumsbasiert, kollisionsfrei pro Tag.
   Mehrfach-Lauf am selben Tag → bestehenden Worktree wiederverwenden. (iwf erlaubt nur lowercase-alnum-Slugs.)
3. **Fix-Autonomie:** Fixes **anwenden + verifizieren**, aber **NICHT committen** — Änderungen bleiben unstaged
   (wie `solve-task`). Der Benutzer committet selbst.
4. **Commit-Schema (nur als Vorschlag ausgeben, nicht ausführen):** `SEC | <englische Beschreibung>` —
   z.B. `SEC | Bump form-data to 3.0.5 and ws to 7.5.11 (CVE-2026-12143, CVE-2026-48779)`. KEINE Ticket-Nummer,
   KEIN Co-Authored-By, KEINE AI-Erwähnung.

---

## Jenkins-Quelle (fix)

| | Wert |
|---|---|
| Hermes-Projekt | `<repo-ordnername>` |
| Job | `DEV - Security` (eindeutiges Suffix genügt — matcht `<repo-ordnername> - DEV - Security`) |
| Schwelle des Jobs | failed bei HIGH/CRITICAL in **FS-Scan ODER Image-Scan** |

> Die hermes-Jenkins-Tools sind **deferred** — vor dem ersten Aufruf per
> `ToolSearch query:"select:mcp__hermes__get-jenkins-job,mcp__hermes__get-jenkins-console,mcp__hermes__get-jenkins-build-log"`
> laden. Falls `get-jenkins-project <repo-ordnername>` „nicht in Config" meldet, hat der Daemon die
> `~/.hermes/config.json` noch nicht geladen → `mcp__hermes__restart-hermes-daemon`, dann erneut. Meldet er es
> auch danach, fehlt das Projekt unter `modules.jenkins.projects` — dann ehrlich stoppen, nicht raten.

---

## Workflow

### Phase 1: Scan-Ergebnis aus Jenkins holen

**Schritt 1 — Build + Status ermitteln**

`mcp__hermes__get-jenkins-job` mit `project=<repo-ordnername>`, `job=DEV - Security`
(bzw. `get-jenkins-build` mit `--build`).

- **Status SUCCESS** → keine blockierenden Vulnerabilities. **STOPP** mit:
  ```
  ✅ KEINE BLOCKIERENDEN VULNERABILITIES
  Job: <repo-ordnername> - DEV - Security #<NR>  (SUCCESS, <Datum>)
  → Nichts zu tun. (Hinweis: --all-severities würde auch LOW/MEDIUM zeigen.)
  ```
- **Status FAILURE** → weiter mit Schritt 2.

**Schritt 2 — Console-Output holen + parsen**

`mcp__hermes__get-jenkins-console` mit `project=<repo-ordnername>`, `job=DEV - Security`, `tail=0`.

> ⚠️ Der Console-Output ist oft **groß** (>100 KB, Token-Limit) und wird dann **als Datei** gespeichert (der Tool-Fehler
> nennt den Pfad). In dem Fall **NICHT** das ganze File lesen — mit `grep`/`sed` nur die Vuln-Tabellen + Verdikt-Marker
> extrahieren (Beispiel-Greps siehe unten). Alternativ einen Subagenten die Datei chunked lesen lassen.

**Struktur des Trivy-Outputs (zwei Pässe):**

1. **FS-Scan** — Quelltext-Bäume (`yarn.lock (yarn)`, `composer.lock (composer)`):
   - Beginn: `================== Trivy FS results from build`
   - Verdikt: `HIGH/CRITICAL vulnerabilities in FS scan from build: <N>` / `... -> marking job as failed`
2. **Image-Scan** — gebautes Docker-Image:
   - Beginn: `====================== Trivy IMAGE results`
   - Zuerst eine `Report Summary`-Tabelle (nur Zählwerte, **überspringen**), dann pro Target Detail-Blöcke
     (`Node.js (node-pkg)`, `app/vendor/composer/installed.json (composer-vendor)`, `<…> (debian)`).
   - Verdikt: `Image scan detected blocking vulnerabilities -> marking job as failed`

**Jeder Detail-Block** hat einen Quell-Header (`<source> (<typ>)`), eine Zeile `Total: N (... HIGH: x, CRITICAL: y)`
und eine Tabelle mit den Spalten:
`Library │ Vulnerability │ Severity │ Status │ Installed Version │ Fixed Version │ Title`.
Trivy lässt bei Folgezeilen gleiche Severity/Status leer — die Severity gilt bis zur nächsten gesetzten Zeile.

**Beispiel-Greps (wenn Console als Datei vorliegt):**

```bash
F="<gespeicherter-pfad>"
# Sektions-/Verdikt-Marker + Totals:
grep -nE "Trivy (FS|IMAGE) results|Total:|HIGH/CRITICAL|marking job as failed|Security job (FAILED|passed)|\(yarn\)|\(composer\)|\(node-pkg\)|\(composer-vendor\)|\(debian\)" "$F"
# Tabellenzeilen mit CVE (eine Zeile pro Library):
grep -nE "CVE-[0-9]{4}-[0-9]+" "$F"
```

**Schritt 3 — Findings normalisieren + filtern**

Baue eine deduplizierte Liste von Findings:
`{ scan: FS|IMAGE, sourceType: yarn|composer|node-pkg|composer-vendor|debian|secret, library, cve, severity, installed, fixedVersions[], title }`.

- **Dedup:** dieselbe `library`+`cve` taucht oft in FS **und** Image auf (z.B. `ws`/`form-data` in `yarn.lock` **und**
  `node-pkg`) → **ein** Fix.
- **Severity-Filter:** Default nur `HIGH`/`CRITICAL`. Mit `--all-severities` auch `LOW`/`MEDIUM`.
- Findet sich **kein** Finding über der Schwelle (obwohl Job FAILURE) → das Verdikt nochmal lesen; ggf. liegt die
  Ursache woanders (z.B. Secret-Fund) → ehrlich berichten, nicht „erfinden".

---

### Phase 2: Triage — Fixbarkeit pro Finding

Klassifiziere **jedes** Finding und bestimme die **Ziel-Version**:

| sourceType | Fix-Weg | Ziel-Version wählen |
|---|---|---|
| `yarn` / `node-pkg` | JS-Dependency bumpen (s. Phase 4) | **Niedrigste** `Fixed Version`, die **im selben Major** wie `installed` liegt (z.B. `ws 7.5.10→7.5.11`, `form-data 3.0.4→3.0.5`, `vite 7.3.3→7.3.5`). KEIN Major-Sprung, wenn ein Same-Major-Fix existiert. |
| `composer` / `composer-vendor` | `composer update <pkg> --with-dependencies` | Niedrigste `Fixed Version` **innerhalb der `composer.json`-Constraint** (z.B. Symfony `6.4.x → 6.4.40`). |
| `debian` (OS-Pakete) | **NICHT** im Repo fixbar → Base-Image-Bump nötig | Nur **berichten** (manuelle Aktion / Dockerfile-Basis). |
| `secret` | **NIE** automatisch | Nur **berichten**. |

Gib nach der Triage eine **Findings-Tabelle** aus (Library, CVE, Severity, Installed → Ziel, Fixweg, fixbar?), und
**bei `--dry-run` STOPP hier** (kein Worktree, keine Änderung).

---

### Phase 3A: SEC-Worktree anlegen mit Stack (via iwf, `dockerStack: true`)

> iwf akzeptiert seit Kurzem **lowercase-alphanumerische** Worktree-IDs (Regex `[a-z0-9](?:[a-z0-9-]*[a-z0-9])?`),
> nicht mehr nur Zahlen. Uppercase ist verboten (die ID wird Docker-Compose-Projektname + DNS-Label unter
> `<stackDomain>`). Darum **`sec<Datum>`** in Kleinbuchstaben.

```bash
MAIN="<repoDir>"                     # aus .claude/project.json
SEC_ID="sec$(date +%Y%m%d)"          # z.B. sec20260616  (lowercase!)

# Existiert der Worktree von heute schon? Dann wiederverwenden + Stack hochfahren.
if git -C "$MAIN" worktree list | grep -q "/$SEC_ID\b\|-$SEC_ID\b"; then
  iwf worktree start "$SEC_ID"
else
  iwf worktree create "$SEC_ID" security_fixes --start
fi
```

`iwf worktree create <SEC_ID> security_fixes --start` legt Worktree **und** eigenen Stack an (Image-Build, TLS-Cert,
DB-Seed, `postStart`-Hooks aus `.iwf.yml` — welche das sind, definiert das Projekt dort). `--start` hier bewusst,
weil Phase 4/5 die **worktree-eigenen Container** zum Lockfile-Regen + Testen brauchen.

**Übernimm Worktree-Pfad / Branch / Stack-Name / URL aus dem `create`-Output.** Konvention (falls nicht ausgegeben):
- Stack/Container-Prefix: `<repo-ordnername>-<SEC_ID>` → Container `<repo-ordnername>-<SEC_ID>-fpm`
- URL: `https://<repo-ordnername>-<SEC_ID>.<stackDomain>`
- Branch: `feature/<PREFIX>-<SEC_ID>_security_fixes` (z.B. `feature/<PREFIX>-sec20260616_security_fixes`)
- Worktree-Pfad: unter `<worktreePrefix>/…` (exakten Pfad aus dem Output nehmen)

Ab hier gilt **Worktree-Routing** (wie `solve-task` Phase 0a-3): Code-Edits/Greps/Git mit absolutem Worktree-Pfad
bzw. `git -C "$WT" …`; Lesen von Doku/`.claude/`/Task-Files aus dem Haupt-Repo.

### Phase 3B: SEC-Worktree anlegen ohne Stack (`dockerStack: false`)

Kein `iwf`, kein Stack, keine URL — nur Worktree und Branch. Die ID bleibt `sec<YYYYMMDD>` (die
Lowercase-Regel von iwf gilt hier zwar nicht, aber ein einheitlicher Name über beide Wege ist mehr wert als
eine Ausnahme):

```bash
MAIN="<repoDir>"
SEC_ID="sec$(date +%Y%m%d)"
WT="<worktreePrefix>/$SEC_ID"

if [ -d "$WT" ]; then
  echo "Worktree von heute existiert schon — wird wiederverwendet: $WT"
else
  BASE=$(git -C "$MAIN" symbolic-ref --quiet --short refs/remotes/origin/HEAD)
  if [ -z "$BASE" ]; then
    for kandidat in origin/develop origin/main develop main; do
      git -C "$MAIN" rev-parse --verify --quiet "$kandidat" >/dev/null && { BASE="$kandidat"; break; }
    done
  fi
  [ -z "$BASE" ] && BASE=HEAD
  git -C "$MAIN" worktree add "$WT" -b "feature/<PREFIX>-${SEC_ID}_security_fixes" --no-track "$BASE"
fi
```

Danach gilt dasselbe Worktree-Routing wie oben.

---

### Phase 4: Fixes anwenden

**Mit Stack (`dockerStack: true`):** Der `sec<Datum>`-Worktree hat **eigene** Container, die seinen Code sehen —
also Tooling **dort** ausführen (`docker exec <repo-ordnername>-<SEC_ID>-fpm …` bzw. `cd "$WT" && iwf …`;
`iwf` liest `PROJECT_NAME` aus der Worktree-`.env.local`, funktioniert also nur mit cwd im Worktree).
**Niemals** die Haupt-Repo-Container (`<repo-ordnername>-fpm`) nehmen.

**Ohne Stack (`dockerStack: false`):** kein Container dazwischen — die Paketmanager-Befehle laufen direkt im
Worktree (`cd "$WT" && yarn install`, `cd "$WT" && composer update …`, bzw. was das Projekt sonst benutzt:
`swift package update`, `npm install`, `go get -u …`). Überall unten, wo `iwf <x>` steht, ist das dann
schlicht `<x>`.

**A) yarn-Findings (`yarn`/`node-pkg`):**

1. **Direkte Dependency** (in `<WT>/package.json` unter `dependencies`/`devDependencies`): Version auf die Ziel-Version
   anheben.
2. **Transitive Dependency** (nur im Lockfile, z.B. `form-data`, `ws` als Sub-Dep): in `<WT>/package.json` einen
   **`resolutions`**-Eintrag auf die Ziel-Version setzen — bestehende `resolutions` ergänzen, nicht ersetzen.
3. **Lockfile regenerieren** (iwf wählt den passenden Container selbst — z.B. den fe-dev-Container, falls das
   Projekt einen hat):
   ```bash
   cd "$WT" && iwf yarn install
   ```

**B) composer-Findings (`composer`/`composer-vendor`), falls vorhanden:**

```bash
cd "$WT" && iwf composer update <pkg> [weitere…] --with-dependencies
```

**C) `debian`/`secret`-Findings:** nicht anfassen — in der Zusammenfassung als „manuell" markieren.

---

### Phase 5: Verifikation

1. **Statisch (immer):** prüfen, dass die verwundbare Version aus dem Lockfile verschwunden und die Ziel-Version drin ist:
   ```bash
   grep -nE "form-data@|\bws@|vite@|<library>@" "$WT/yarn.lock" | head
   ```
   Für composer analog in `$WT/composer.lock` (`grep "<pkg>" -A2`).
2. **Funktional** (mit Stack im worktree-eigenen Stack, ohne Stack direkt im Worktree — dann jeweils ohne
   das `iwf`-Präfix bzw. mit dem projektüblichen Befehl aus der `CLAUDE.md`):
   - Frontend-Build: `cd "$WT" && iwf yarn build` (bzw. `iwf yarn tsc --noEmit` für den reinen Typecheck).
   - Tests/PHPStan **nur bei composer-Änderungen** nötig: bei Metadata-Änderungen vorher Cache leeren
     `docker exec <repo-ordnername>-<SEC_ID>-fpm sh -lc 'rm -rf var/cache/*'`, dann
     `docker exec <repo-ordnername>-<SEC_ID>-fpm ./vendor/bin/paratest tests/…` (bzw. `./vendor/bin/phpunit`,
     falls das Projekt kein paratest hat) und `cd "$WT" && iwf run phpstan` (bzw.
     `iwf run "vendor/bin/phpstan analyse src"`, falls der Kurzbefehl nicht definiert ist).
3. **Definitive Gegenprobe (empfehlen, nicht selbst auslösen):** Branch pushen →
   `<repo-ordnername> - DEV - Security` läuft neu → muss **SUCCESS** sein. Push/Trigger macht der Benutzer.

---

### Phase 6: Zusammenfassung (KEIN Commit)

**NICHT committen.** Änderungen bleiben unstaged im Worktree. Gib aus:

```
🔐 SECURITY-FIX VORBEREITET

Quelle:   <repo-ordnername> - DEV - Security #<NR> (FAILURE, <Datum>)
Worktree: <WT-Pfad>
Branch:   feature/<PREFIX>-sec<Datum>_security_fixes
Stack:    https://<repo-ordnername>-sec<Datum>.<stackDomain>   [entfällt bei dockerStack: false]

## Gefixte Vulnerabilities (HIGH/CRITICAL)
| Library | CVE | Installed → Ziel | Scan | Fixweg |
|---|---|---|---|---|
| ws | CVE-2026-48779 | 7.5.10 → 7.5.11 | FS+Image | yarn resolutions |
| form-data | CVE-2026-12143 | 3.0.4 → 3.0.5 | FS+Image | yarn resolutions |
| vite | CVE-2026-53571 | 7.3.3 → 7.3.5 | Image | package.json bump |

## Verifikation
- Lockfile: <verwundbare Version weg? Ziel-Version drin?>  ✅/⚠️
- Build/Tests: <was lief>  | Definitiv: Jenkins-Re-Run empfohlen

## NICHT automatisch fixbar (manuelle Aktion)
- <debian/OS-Pakete → Base-Image-Bump>  | <Secret-Funde>   (oder: „keine")

## Vorgeschlagene Commit-Message(s)  (du committest selbst)
```
SEC | Bump form-data to 3.0.5 and ws to 7.5.11 (CVE-2026-12143, CVE-2026-48779)
SEC | Bump vite to 7.3.5 (CVE-2026-53571)
```

## Nächste Schritte
- [ ] Änderungen prüfen: git -C <WT> diff
- [ ] Committen (Schema: SEC | <desc>), pushen
- [ ] Jenkins `<repo-ordnername> - DEV - Security` neu laufen lassen → muss SUCCESS sein
```

---

## Wichtige Regeln

1. **Quelle ist fix:** hermes-Projekt `<repo-ordnername>`, Job `DEV - Security`. Bei „nicht in Config" →
   Daemon-Restart, dann erneut; fehlt das Projekt wirklich in der Config → stoppen, nicht raten.
2. **Nur HIGH/CRITICAL** (Default) — exakt die Schwelle des Jobs; `--all-severities` erweitert bewusst.
3. **Dedup FS↔Image:** gleiche Library+CVE = ein Fix.
4. **Same-Major-Fix bevorzugen:** niedrigste Fixed Version im selben Major; kein unnötiger Major-Sprung.
5. **Worktree-ID lowercase:** `sec<YYYYMMDD>` (iwf-Regex `[a-z0-9-]`, Uppercase verboten). Mit Stack eigener
   Stack via `--start`; ohne Stack (`dockerStack: false`) reiner `git worktree add` vom ermittelten
   Basis-Branch.
6. **Worktree-eigene Container nutzen** (`<repo-ordnername>-<SEC_ID>-fpm`), NIE die Haupt-Repo-Container
   (`<repo-ordnername>-fpm`).
7. **NIEMALS committen** — Änderungen unstaged lassen, Commit-Message nur vorschlagen (`SEC | …`, keine AI-Erwähnung).
8. **Nicht-fixbares ehrlich melden** (OS-Pakete, Secrets) statt zu „faken".

---

## Fehlerbehandlung

| Fehler | Reaktion |
|---|---|
| `get-jenkins-project <repo-ordnername>` → „nicht in Config" | `restart-hermes-daemon`, erneut versuchen; sonst `~/.hermes/config.json` prüfen (gültiges JSON? Projekt unter `modules.jenkins.projects`?) |
| Console > Token-Limit (als Datei gespeichert) | Datei mit grep/sed gezielt parsen, nicht komplett lesen |
| Job ist SUCCESS | STOPP — nichts zu tun (Phase 1) |
| Nur `debian`/`secret`-Findings (nichts im-Repo-fixbar) | Worktree überflüssig → kein Worktree, nur Report + manuelle Schritte |
| `iwf worktree create` lehnt ID ab (`number_invalid`) | ID war nicht lowercase-alnum → `sec<YYYYMMDD>` (kleingeschrieben) verwenden |
| Worktree von heute existiert schon | wiederverwenden: `iwf worktree start sec<YYYYMMDD>` |
| `iwf yarn`/`iwf run` greift Haupt-Repo statt Worktree | cwd ist nicht der Worktree → erst `cd "$WT"` (iwf liest `PROJECT_NAME` aus Worktree-`.env.local`) |

---

Beginne jetzt mit Phase 1: Build + Status aus Jenkins holen (Projekt `<repo-ordnername>`, Job `DEV - Security`).
