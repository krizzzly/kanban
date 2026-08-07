## Datenbankzugriff

- immer wenn du Datenbankzugriff brauchst um ein Problem in der lokalen Datenbank zu untersuchen - nutze die Symfony Console Commands

Beispiel:

```
iwf run "bin/console dbal:run-sql 'SELECT * FROM app_user'"
```
