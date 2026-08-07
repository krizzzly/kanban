## Task-File aktuell halten

> ⚙️ Projektwerte stehen in `.claude/project.json` im Repo-Root.

- Wenn während der Umsetzung **Änderungen, Entscheidungen, Scope-Anpassungen oder Spec-Korrekturen** besprochen werden, **selbstständig** im aktuellen Task-File unter `<tasksPath>/<prefix>-<NR>_*.md` nachtragen — ohne dass der Benutzer extra `/update-task` aufrufen muss (`tasksPath` und `prefix` aus `.claude/project.json`)
- Aktuelles Task-File über den Branch-Namen ermitteln (`feature/<prefix>-<NR>_…` → `<tasksPath>/<prefix>-<NR>*.md`)
- Was gehört rein:
    - **Neue Entscheidungen** → als nächste Nummer unter `## Entscheidungen` anhängen, mit `✅` markiert
    - **Revidierte Entscheidungen** → bestehenden Punkt mit „(revidiert)" markieren, alte Begründung erhalten, neue ergänzen
    - **Gestrichene Anforderungen** → „(obsolet)" markieren statt löschen, kurz begründen warum
    - **Konkrete Implementierungsdetails** die nicht aus dem Code ablesbar sind (z.B. RFC-Fallbacks, Workarounds, Permission-Scopes, Migration-Notes)
- Was NICHT rein:
    - Reine Code-Mechanik (Klassennamen, Methodensignaturen) — die ergibt sich aus dem Code
    - Triviale Detail-Iterationen wie „Variable umbenannt" oder „Typ angepasst"
- Format: kurze Sätze, „Warum" statt „Was", auf Deutsch (Code-Identifier auf Englisch)
- Bei Status-Wechseln (`🔴 Offen` → `🟡 In Arbeit` → `🟢 Abgeschlossen`) den `### Status`-Block aktualisieren
- Wenn unklar ob etwas „besprochen genug" ist um es nachzutragen: lieber nachtragen — das Task-File ist die Single Source of Truth für die Spec-Historie
