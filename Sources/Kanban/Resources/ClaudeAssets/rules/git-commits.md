## Commit-Message Convention

> ⚙️ Projektwerte stehen in `.claude/project.json` im Repo-Root.

Alle Commits MÜSSEN diesem Schema folgen:

```
<TICKET-NUMMER> | <Beschreibung auf Englisch>
```

Die Ticket-Nummer ist `<prefix>-<NR>` (`prefix` aus `.claude/project.json`).

**Beispiele:**
- `<prefix>-3963 | Add correction request table component`
- `<prefix>-3963 | Implement accept/reject actions for requests`
- `<prefix>-3963 | Add status filter to correction requests`

**Regeln:**
- Beschreibung auf Englisch
- Ticket-Nummer am Anfang
- Pipe (`|`) als Trenner
- **KEIN** `Co-Authored-By` in Commit-Messages
- **KEINE** Erwähnung von AI/Claude in Commits
