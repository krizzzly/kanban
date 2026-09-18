## Serena-first Arbeitsweise

> ⚙️ Projektwerte stehen in `.claude/project.json` im Repo-Root.

- **Symbolsuche, Referenzen und Datei-Struktur** immer zuerst über Serena-Tools lösen (find_symbol, get_symbols_overview, find_referencing_symbols, search_for_pattern, list_dir)
- **Shell/Bash** nur für Ausführung (Tests, PHPStan, Git-Commands, iwf-Commands)
- Wenn ausnahmsweise Shell statt Serena verwendet wird, kurz begründen warum
- Vor Code-Exploration ggf. zuerst das Serena-Projekt **aktivieren** (activate_project) — der Projektname ist `repoDir` aus `.claude/project.json`
