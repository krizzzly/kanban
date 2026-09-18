## Datenbankzugriff

> Gilt für Projekte **mit** Docker-Stack (`dockerStack: true` in `.claude/project.json`). Ohne Stack gibt es
> weder `iwf` noch eine Stack-Datenbank — dann steht in der `CLAUDE.md` des Projekts, ob und wie es eine gibt.

- immer wenn du Datenbankzugriff brauchst um ein Problem in der lokalen Datenbank zu untersuchen - nutze die Symfony Console Commands

Beispiel:

```
iwf run "bin/console dbal:run-sql 'SELECT * FROM app_user'"
```
