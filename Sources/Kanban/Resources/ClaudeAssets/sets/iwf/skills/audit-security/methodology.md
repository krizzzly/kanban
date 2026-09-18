# Security-Audit — Methodik für Business-Web-Applikationen

Mehrschichtige, evidenzbasierte Befundung für Symfony/PHP + React/JS und vergleichbare Business-Web-Systeme.

**Coverage-Rahmen (versioniert):**

- OWASP Top 10 **2025**
- OWASP API Security Top 10 **2023**
- OWASP ASVS **5.0.0**, Zielniveau **L2**
- CVSS **4.0** für technische Severity bei MEDIUM+

> **Leitsatz:** Ein bestätigtes Finding existiert erst, wenn die behauptete Sicherheitswirkung nachvollziehbar
> verifiziert ist. Ein widerlegter Verdacht und eine nicht ausgeführte Prüfung sind ebenfalls Ergebnisse.

---

# 1. Normalisierter Input-Contract

Argumentauflösung, Git-Source, Worktree, Stack-Safety, Tool-Preflight und Resume/Fingerprint werden in
`SKILL.md` erledigt.

Diese Methodik erhält:

```yaml
security_audit_context:
  audit_id: ...
  ticket: ...
  repository_path: ...
  audit_worktree: ...
  target_ref: ...
  audit_source_sha: ...
  source_fingerprint: ...
  requested_phases: all|[...]
  resume: true|false
  dast_enabled: true|false
  dry_run: true|false
  report_path: ...
  findings_path: ...
  task_file: ...
  tool_manifest: ...
```

Die Methodik ändert den Audit-Source nicht und rät keine Umgebung.

---

# 2. Audit-Ziel und Abgrenzung

Dieses Audit prüft **die gesamte definierte Applikation** am festgenagelten Source-Fingerprint.

Es ist nicht:

- Feature-Impact-Analyse,
- allgemeine Design-Quality-Analyse,
- bloßer Branch-Diff-Security-Review,
- Dependency-Bump-Workflow,
- automatische Remediation.

Die vorhandenen Ergebnisse aus diesen Wegen dürfen als Evidenz/Baseline konsumiert werden, aber nicht als Ersatz
für die Security-Coverage dieses Audits.

---

# 3. Security-Model zuerst: System verstehen, bevor Tools laufen

Vor SCA/SAST/DAST ein kompaktes Security-Modell erstellen.

## 3.1 Identitäten und Trust Boundaries

Dokumentiere:

| Dimension | Fragen |
|---|---|
| Identity Provider | Keycloak/OIDC/SAML/lokal? |
| Rollen | globale Rollen, Mandantenrollen, Objektrollen? |
| Tenant | wie wird Tenant-Kontext bestimmt und technisch erzwungen? |
| Session/Token | Cookie/JWT, Lebensdauer, Refresh, Logout, Audience/Issuer? |
| Browser/API | gleiche AuthN/AuthZ oder unterschiedliche Trust Boundaries? |
| Async | welche Messages laufen ohne aktuellen User-Kontext? |
| E-Mail | welche Aktionen/Links verlassen die Anwendung? |
| Externe APIs | welche Provider werden vertraut/konsumiert? |
| Dateien/PDF | welche User-/DB-Inhalte erreichen Parser/Renderer? |

## 3.2 Geschäftsprozesse mit Security-Relevanz

Für Business-Systeme mit Rollen, Pendenzen und Statusmodellen mindestens inventarisieren:

- Freigeben / Ablehnen / Einreichen / Zurückziehen,
- Zuweisen / Umweisen / Pendenz erledigen,
- Rollen-/Mandantenwechsel,
- Export / Download / Report,
- Massenaktionen,
- E-Mail-/Notification-Trigger,
- administrative Sonderaktionen,
- zeit-/statusabhängige Aktionen.

Diese Prozesse sind nicht nur „Business Logic“; sie sind potenzielle **Sensitive Business Flows**.

## 3.3 Datenklassen

Markiere mindestens:

- personenbezogene Daten,
- vertrauliche Geschäfts-/Mandantendaten,
- Auth-/Session-/Token-Daten,
- Auditdaten,
- Dokumente/Uploads,
- E-Mail-Inhalte/Empfänger,
- Secrets/Keys,
- öffentlich sichtbare Daten.

---

# 4. Stack-/Projekt-Profil

Aus Code und effektiver Konfiguration detektieren, nicht blind aus README übernehmen.

| ID | Achse | Beispiele für Detektion |
|---|---|---|
| S1 | AuthN | `security.yaml`, OIDC/Keycloak config, authenticators |
| S2 | AuthZ | `#[IsGranted]`, Voter, Permission-Config, imperative Checks |
| S3 | Tenant-Scoping | Doctrine Filter, Restrict-Services, QueryBuilder-Constraints |
| S4 | Workflow/Pendenzen | Status-Enums, Transition Services, Pending/Task Entities |
| S5 | Async/Eventing | Messenger routing, handlers, retry/dead-letter |
| S6 | E-Mail | Mailer calls, templates, recipient resolution, links/tokens |
| S7 | HTML/Sanitizer | Editors, `|raw`, `dangerouslySetInnerHTML`, sanitizers |
| S8 | File/PDF | uploads/downloads, Gotenberg/wkhtmltopdf/browser rendering |
| S9 | External HTTP | HttpClient/Guzzle/fetch/provider clients |
| S10 | Secrets | Symfony secrets, env, Vault patterns |
| S11 | FE Build | Vite/Webpack env exposure, source maps |
| S12 | Container/Proxy | Docker, nginx/Traefik, headers/TLS |
| S13 | Public Surface | `PUBLIC_ACCESS`, anonymous routes, webhook endpoints |
| S14 | API Inventory | routes, versions, deprecated/debug endpoints |

Das Profil kommt in den Report-Kopf.

---

# 5. Phase 0 — Scope, Snapshot und Coverage Plan

## 5.1 Audit Snapshot

Dokumentiere:

```markdown
- Audit-ID
- Target Ref
- Audit Source SHA
- Source Fingerprint
- Datum/Zeit
- Worktree
- Stack/Container
- Framework-/Runtime-Versionen
- Standards-Versionen
- Tool-Versionen/Digests
```

## 5.2 Coverage-Matrix anlegen

Vor dem ersten Finding eine Matrix erzeugen:

| Surface | Planned | Executed | Evidence | Gaps |
|---|---:|---:|---|---|
| AuthN | ✅ |  |  |  |
| AuthZ/Object-Level | ✅ |  |  |  |
| Tenant Isolation | ✅ |  |  |  |
| Business Flows | ✅ |  |  |  |
| Async/Events | ✅ |  |  |  |
| Email/Notifications | ✅ |  |  |  |
| Input/Injection | ✅ |  |  |  |
| XSS/Rendering | ✅ |  |  |  |
| Files/PDF | ✅ |  |  |  |
| External HTTP/SSRF | ✅ |  |  |  |
| Secrets | ✅ |  |  |  |
| Supply Chain | ✅ |  |  |  |
| Logging/Exceptions | ✅ |  |  |  |
| Config/Infra | ✅ |  |  |  |
| DAST | ✅ |  |  |  |

ASVS-Anforderungen, die explizit geprüft werden, nach Möglichkeit versioniert referenzieren:
`v5.0.0-<chapter>.<section>.<requirement>`.

---

# 6. Phase 1 — Empirische Angriffsflächen-Vermessung

Ziel: aus „ganze App auditieren“ endliche, zählbare Prüflisten machen.

Beispiele:

```bash
# Routes / Controller
rg -n '#\[Route' src/Controller
rg -L 'IsGranted|denyAccessUnlessGranted|->isGranted\(' src/Controller -g '*.php'

# Object-/Tenant-Security
rg -n 'IsGranted|denyAccessUnlessGranted|->isGranted\(|Voter|Permission' src/
rg -n 'tenant|Tenant|Restrict|SQLFilter|addFilterConstraint|ownership|owner' src/

# Dynamic queries
rg -n 'createNativeQuery|executeQuery|executeStatement|andWhere|orWhere|orderBy' src/

# HTML / rendering
rg -n 'dangerouslySetInnerHTML|\|raw|Markup|sanitize|DOMPurify|tiptap|ckeditor|quill' assets templates src/

# File / PDF
rg -n 'UploadedFile|BinaryFileResponse|download\(|Gotenberg|wkhtml|generateFromHtml|pdf\(' src config/

# Async / event / email
rg -n 'dispatch\(|AsMessageHandler|MailerInterface|TemplatedEmail|send\(' src/
rg -n 'Pending|Pendenz|Task|Notification|Email|Mail' src/

# External HTTP / URL consumption
rg -n 'HttpClientInterface|Guzzle|request\(|file_get_contents\(|curl_|fetch\(' src assets/

# Public / debug
rg -n 'PUBLIC_ACCESS|_profiler|_wdt|api/doc|openapi' config src/
```

**Nicht nur zählen.** Für jede Kategorie eine konkrete Review-Liste erzeugen.

## 6.1 Authorization-Matrix

Gerade bei vielen Rollen nicht bei „Route hat `IsGranted`“ stehenbleiben.

Erzeuge stichproben- oder vollständig, je nach Größe:

| Aktion/Endpoint | Objekt | Rolle | Tenant-Bezug | Function AuthZ | Object AuthZ | Property AuthZ |
|---|---|---|---|---|---|---|

Drei Ebenen unterscheiden:

1. **Function Level** — darf Rolle X die Aktion grundsätzlich?
2. **Object Level** — darf sie dieses konkrete Objekt?
3. **Property Level** — darf sie dieses Feld sehen/ändern?

---

# 7. Phase 2 — Supply Chain / SCA

## 7.1 Paketmanager detektieren

Nicht blind `yarn audit` annehmen.

Detektiere:

- `composer.lock`,
- `package-lock.json`,
- `yarn.lock`,
- `pnpm-lock.yaml`,
- `packageManager` in `package.json`.

## 7.2 Scans

Mindestens vorhandene native Audit-Funktion und – falls verfügbar – zweite Advisory-Quelle.

Beispiele:

```bash
composer audit --format=json
osv-scanner --lockfile composer.lock
```

JS passend zum Package Manager.

## 7.3 Triage

Für jedes Advisory:

- direct/transitive,
- runtime vs dev/build,
- tatsächlich ausgelieferter/erreichbarer Codepfad,
- vorhandene Mitigation,
- bereits durch CI/Trivy bekannt?,
- konkrete Upgrade-/Mitigation-Richtung.

Tool-Fund ≠ Finding.

## 7.4 Supply-chain controls

Zusätzlich:

- Lockfiles vorhanden und konsistent?
- private Registries?
- install scripts?
- abandoned/unmaintained dependencies?
- mutable Container-Tags?
- Integrity/Signature-Möglichkeiten?
- CI lädt ausführbaren Code aus unpinned refs?

---

# 8. Phase 3 — Secrets und Credentials über Historie

Mindestens:

```bash
gitleaks detect --source . --redact
# optional zusätzlich, wenn vorhanden:
trufflehog git file://$(pwd) --only-verified
```

Manueller Pass:

```bash
git ls-files | grep -Ei '\.env|secret|credential|realm|\.pem|\.key|token'
git log --all --diff-filter=A --name-only --pretty=format: \
  | sort -u | grep -Ei '\.env|secret|credential|\.pem|\.key'
```

## 8.1 Strikte Redaction-Regel

Niemals Secret-Werte in Report/Register kopieren.

Dokumentieren:

- Typ,
- Pfad,
- Commit,
- Fingerprint/Hash oder stark redigierter Prefix,
- Gültigkeit verifiziert?,
- Scope/Blast Radius,
- Rotation erforderlich?

Wenn ein reales Secret gefunden wird, Beweis sichern ohne es erneut zu verbreiten.

---

# 9. Phase 4 — SAST / Taint / Static Signals

Rollen der Tools trennen:

- Semgrep: Pattern-/Custom-Regeln, mehrere Sprachen,
- Psalm: PHP-Taint, falls sinnvoll konfigurierbar,
- CodeQL: JS/TS Deep Dataflow; **nicht PHP**,
- Exakat: optionaler PHP-Breitenpass,
- vorhandene PHPStan/ESLint-Regeln als Kontext, nicht als Security-Ersatz.

Beispiele:

```bash
semgrep scan --config p/php --config p/javascript --config p/owasp-top-ten --config p/secrets src/ assets/
```

Psalm:

```bash
./vendor/bin/psalm --taint-analysis --no-cache
```

CodeQL nur für unterstützte Sprachen des Repos.

## 9.1 Triage-Pflicht

Jeder Treffer bekommt:

```text
Source → Transformation → Security Control → Sink → Exploitability
```

Fehlt diese Kette, bleibt es ein Signal.

## 9.2 Cross-Language Blind Spot

Explizit suchen nach Flüssen wie:

```text
API Input
→ PHP
→ Persistenz
→ Read Model
→ JSON
→ React
→ HTML/URL/DOM Sink
```

oder:

```text
DB-Inhalt
→ Twig/PDF Renderer
→ Netzwerk/File-System
```

Toolgrenzen dürfen nicht mit Trust Boundaries verwechselt werden.

---

# 10. Phase 5 — Manuelle Security-Tiefenprüfung

Diese Phase ist Pflicht; ein „clean“ SAST ersetzt sie nicht.

## 10.1 Authentifizierung und Session

Prüfen:

- OIDC/JWT Issuer/Audience/Signature,
- Redirect-/Callback-Allowlist,
- Session Fixation,
- Logout/Revocation soweit relevant,
- Cookie `Secure`, `HttpOnly`, `SameSite`,
- Token-/Recovery-Link TTL und Single Use,
- Default-/Fallback-Authentisierung,
- Test-/Debug-Bypass,
- Account/Identity Mapping zwischen IdP und App.

## 10.2 Autorisierung, BOLA/BFLA/BOPLA und Tenant Isolation

Für sensible Endpoints und Queries:

- Function-Level,
- Object-Level,
- Property-Level,
- Tenant-Read,
- Tenant-Write,
- indirekte Objektbezüge,
- Exporte/Downloads,
- Bulk-Endpunkte,
- Such-/Filter-Endpunkte.

Cross-Tenant immer mit **mindestens zwei wirklich getrennten Identitäten** testen.

Ein All-Roles-Account ist kein Tenant-Isolation-Test.

## 10.3 Business-Flow-Abuse

Für Freigaben, Pendenzen, Status und andere sensible Flows:

- Schritt überspringbar?
- Reihenfolge erzwingbar?
- alte Aktion replaybar?
- derselbe Schritt mehrfach ausführbar?
- Race/Doppelclick?
- Benutzer kann eigene Berechtigung durch Zustandsänderung erzeugen?
- IDs/Status/Owner manipulierbar?
- Massenaktionen rate-/umfangsbegrenzt?
- fachliche Limits serverseitig?
- „versteckter Button“ ohne Backend-Schutz?

Besonders prüfen:

```text
Role/Permission
→ konkrete Entity
→ Transition
→ Pendenz
→ Event
→ Mail
→ nächster Actor
```

Jede Kante kann eine Security Boundary sein.

## 10.4 Pendenzen / Aufgaben

Prüfen:

- darf der falsche Tenant Pendenz sehen?
- darf er sie erledigen/umweisen?
- wird Owner/Assignee clientseitig kontrollierbar?
- entstehen doppelte Pendenzen bei Retry?
- bleibt eine erledigte Pendenz nach Status-Race aktiv?
- verrät die Liste Existenz fremder Objekte?
- erzeugt eine Pendenz Folgeaktionen ohne erneute Autorisierung?

## 10.5 Events / Async / Messenger

Prüfen:

- Wer darf das auslösende Event erzeugen?
- Wird Berechtigung nur beim Producer geprüft oder muss Consumer erneut fachliche Gültigkeit prüfen?
- Replay/Duplikate?
- Out-of-order?
- Retry-sicher?
- Poison Message?
- Datenminimierung im Payload?
- sensitive Daten in Queue/Dead Letter?
- Tenant-ID explizit und vertrauenswürdig?
- Event kann auf inzwischen geänderten/entzogenen Rechten weiterwirken?
- DB-Commit und Message-Publish konsistent (Outbox o.ä. falls erforderlich)?

**TOCTOU-Frage:** Ist eine Berechtigung zwischen Command und späterem Async-Consumer inzwischen ungültig geworden?

## 10.6 E-Mail / Notifications

Prüfen:

- Empfänger serverseitig aus autoritativen Daten abgeleitet?
- kann Request eine fremde Adresse einschleusen?
- Tenant-/Rollen-Scope des Empfängers korrekt?
- PII/Business-Secrets im Subject/Body/Attachment?
- HTML-/Template-Injection?
- Header Injection?
- Links enthalten Tokens: TTL, Scope, Single Use, Entropie?
- Retry/Duplicate → Spam oder mehrfach ausführbare Aktion?
- E-Mail verrät Existenz eines Accounts/Objekts?
- Unsubscribe/Preference darf Security-Mail nicht ungewollt unterdrücken?

## 10.7 Injection

Nicht nur Werte:

- SQL/DQL values,
- dynamische Operatoren,
- Sortierung,
- Feldnamen,
- Alias,
- Expression-/Specification-Bausteine,
- Shell/Process,
- Template,
- LDAP/Regex falls vorhanden.

Allowlist für Struktur; Parameter-Binding für Werte.

## 10.8 XSS / Rich Text / Rendering

End-to-end:

```text
Writer
→ Validation
→ Sanitization
→ Persistence
→ Serialization
→ Browser/PDF/Email Sink
```

Client-Validierung ist nie alleinige Security-Kontrolle.

Attribute/Protocols genauso prüfen wie Nodes/Tags.

## 10.9 File Upload/Download

- MIME/Content, nicht nur Extension,
- Größe/Resource Exhaustion,
- path traversal,
- zip bombs/archives falls vorhanden,
- storage außerhalb Webroot,
- filename/content-disposition injection,
- malware scanning falls Anforderung,
- Object-Level Authorization beim Download,
- Cross-Tenant Zugriff,
- signed/temp URLs.

## 10.10 SSRF / External Resource Fetching / PDF

Alle user-/DB-kontrollierten URLs bis zum Netzwerk- oder Renderer-Sink verfolgen.

Prüfen:

- scheme allowlist,
- host allowlist,
- DNS rebinding soweit relevant,
- loopback/link-local/private ranges,
- redirects,
- file://,
- cloud metadata endpoints,
- Renderer local file access,
- Netzwerkzugriff des Renderer-Containers.

## 10.11 Unsafe Consumption externer APIs

Providerdaten sind **untrusted input**:

- Schema/Type validation,
- Größenlimits,
- Timeout,
- Redirects,
- TLS,
- Fehler-Mapping,
- Rate/Resource consumption,
- Provider-HTML/URLs nicht ungeprüft rendern/fetchen,
- kompromittierter Provider als Threat Model.

## 10.12 Logging / Audit / Exceptional Conditions

Prüfen:

- Exceptions fail closed?
- Security-Check in `catch` umgangen?
- 500 verrät Interna?
- Secrets/PII in Logs?
- Audit Event vollständig genug: actor, action, object, tenant, outcome, time?
- Security-relevante Aktionen ohne Audit?
- Logs/Events manipulierbar?
- Retry-/Partial Failure sichtbar?
- Rate-Limit-/Auth-Fails observierbar?

---

# 11. Phase 6 — DAST

Nur gegen den im Skill verifizierten nicht-produktiven Stack.

## 11.1 Preconditions

- Authentifizierte Session,
- Rollen-/Tenant-Testkonten,
- Seed-Daten,
- Target-Host verifiziert,
- Source-Parität zum Audit-Fingerprint.

## 11.2 Coverage

Mindestens:

- Header/Cookies,
- passive scan,
- authentifiziertes Spidering,
- aktive Scans soweit sicher,
- role/tenant-negative Requests,
- Rate-/Resource-Limits für sensible Business Flows,
- Upload/Download,
- API error handling.

Automatisierter Scanner ersetzt keine fachlichen IDOR-/Workflow-Tests.

## 11.3 Destruktive Wirkung

DAST kann Daten verändern.

- nur dafür vorgesehene Daten,
- keine Prod-/QA-Ziele,
- Testdaten nach Bedarf resetten,
- Scan-Accounts kennzeichnen,
- ausgelöste E-Mails/Jobs berücksichtigen.

---

# 12. Phase 7 — Konfiguration & Infrastruktur

Prüfen:

- Symfony Firewall / `access_control`,
- `PUBLIC_ACCESS`,
- Prod-Debug/Profiler/API-Docs,
- CORS,
- CSRF-Modell,
- Cookie Flags,
- Security Headers / CSP,
- Reverse Proxy Trust,
- Keycloak Realm/Client config,
- Token-Lifetimes,
- secrets/env exposure,
- Vite env exposure / source maps,
- Docker non-root / capabilities / secrets,
- mutable base image tags,
- exposed ports,
- container network boundaries,
- TLS termination,
- CI credentials and unpinned actions/scripts,
- backup/export access,
- dead-letter/queue access.

---

# 13. Phase 8 — Verifikation und Adversarialer Gegencheck

## 13.1 Finding States

```text
SIGNAL
  ↓
HYPOTHESIS
  ↓
VERIFIED_FINDING
```

oder:

```text
HYPOTHESIS
  ↓
DISPROVED
```

oder:

```text
HYPOTHESIS
  ↓
UNVERIFIED
```

Kein Sprung von Tool-Output direkt zu `VERIFIED_FINDING`.

## 13.2 Verifikation

Mögliche Nachweise:

- fokussierter Controller-/Integrationstest,
- Security-Repro-Test,
- reproduzierbarer curl/API-Request,
- generiertes SQL/Query AST,
- Browser-Repro,
- DAST-Evidenz,
- Config-/Runtime-Nachweis.

## 13.3 Adversarial Recheck

Vor `HIGH/CRITICAL`:

1. Mitigation suchen, die die Hypothese widerlegt.
2. Alternative Rolle/Tenant/Status prüfen.
3. Framework-Verhalten verifizieren statt annehmen.
4. Tatsächlichen Sink/Side Effect beweisen.
5. Blast Radius konkret bestimmen.
6. Bei Cross-Tenant separat nachweisen, dass die Tenant-Grenze wirklich überschritten wird.

---

# 14. Severity und Priorisierung

## 14.1 CVSS

Für MEDIUM+:

- CVSS **4.0**
- Score **und Vector** dokumentieren.

CVSS beschreibt technische Severity, nicht automatisch interne Fix-Priorität.

## 14.2 Business-Priority Overlay

Zusätzlich separat dokumentieren:

- cross-tenant?,
- personenbezogene/vertrauliche Daten?,
- breite Rollenreichweite?,
- sensible Business-Flow-Manipulation?,
- automatable?,
- dauerhaft gespeicherter Effekt?,
- Audit-/Nachweisbarkeit?,
- öffentliche/pre-auth Erreichbarkeit?

**Cross-Tenant Confidentiality/Integrity** wird in eurer Remediation-Roadmap unabhängig vom reinen CVSS nach oben priorisiert.

Technische Severity und interne Priorität nicht vermischen.

---

# 15. Findings-Register

IDs:

```text
SEC-001
SEC-002
...
```

Positive/verifizierte Kontrollen:

```text
POS-001
...
```

Pflichtformat:

```markdown
## SEC-001 — <Titel>

- **Status:** VERIFIED / UNVERIFIED
- **Severity:** MEDIUM / HIGH / CRITICAL
- **CVSS 4.0:** <score> — `<vector>`
- **OWASP:** <Top10/API category>
- **ASVS:** <v5.0.0-x.y.z, falls passend>
- **Surface:** AuthZ / Tenant / Workflow / Async / Email / ...
- **Source:** <datei:zeile / endpoint>
- **Kette:** Source → Controls → Sink/Effect
- **Actor:** ...
- **Victim/Scope:** ...
- **Tenant-Reach:** same-tenant / cross-tenant / global
- **FACT:** ...
- **Exploitability:** ...
- **Business Impact:** ...
- **Verification:** <Test/Kommando>
- **Evidence:** ...
- **Remediation Direction:** ...
- **Repro-Lifecycle:** Audit-Repro muss im Fix-Ticket in schützenden Regressionstest überführt werden.
```

Keine Secrets im Klartext.

---

# 16. Positive Controls und widerlegte Hypothesen

Pflichtsektion:

```markdown
## Verifizierte Positiva

| ID | Hypothese/Kontrolle | Nachweis | Ergebnis |
|---|---|---|---|
| POS-001 | ... | ... | wirksam |
```

Widerlegte Hypothesen reduzieren Wiederholungsarbeit in künftigen Audits.

---

# 17. Tool-/Coverage-Status

Pflicht:

```markdown
| Prüfung/Tool | Status | Version | Ergebnis | Grund/Gaps |
|---|---|---|---|---|
| Semgrep | ✅ | ... | ... | |
| Psalm Taint | ❌ | ... | NOT RUN | Setup inkompatibel |
| Authenticated DAST | ⚠️ | ... | PARTIAL | zweiter Tenant-Account fehlt |
```

Status:

- `DONE`
- `PARTIAL`
- `NOT RUN`
- `STALE`

„Tool nicht vorhanden“ darf nie als „clean“ erscheinen.

---

# 18. Report

Pflichtreihenfolge:

1. Audit Snapshot
2. Executive Summary
3. Coverage Statement + Gaps
4. Attack Surface / Security Model
5. Severity Overview
6. Verified Findings
7. Cross-Tenant / Sensitive Business Flow Summary
8. Verified Positive Controls / Disproved Hypotheses
9. Tool Status
10. Remediation Roadmap
11. Repro-Test Lifecycle
12. Appendix / raw evidence references

Der Report muss ohne Chat verständlich sein.

---

# 19. Remediation Roadmap

Audit selbst fixt nicht.

Für jedes bestätigte Finding:

```markdown
| Prio | SEC-ID | Folgeticket | Ziel | Regressionstest |
|---|---|---|---|---|
```

Priorisierung:

1. Cross-Tenant / AuthN/AuthZ / kritische Integrität
2. andere HIGH/CRITICAL
3. MEDIUM
4. LOW/Hardening
5. Tool-/Coverage-Lücken

Dependency-only Fixes an den vorhandenen `/fix-security`-Weg delegieren.

---

# 20. Completion Gate

Audit ist erst abgeschlossen, wenn:

- [ ] Source-Fingerprint dokumentiert
- [ ] Security Model erstellt
- [ ] Coverage Matrix vorhanden
- [ ] angeforderte Phasen DONE/PARTIAL/NOT RUN markiert
- [ ] Tool-Versionen/Digests erfasst
- [ ] keine Roh-Scanner-Treffer ungeprüft als Finding übernommen
- [ ] jedes VERIFIED Finding reproduzierbar
- [ ] HIGH/CRITICAL adversarial gegengeprüft
- [ ] Tenant-Reach je relevantem Finding bestimmt
- [ ] Business-Flow/Async/Email geprüft, falls vorhanden
- [ ] Secrets im Report redigiert
- [ ] Positiva/widerlegte Hypothesen dokumentiert
- [ ] Coverage-Gaps offen benannt
- [ ] Remediation-Roadmap vorhanden
- [ ] Repro-Test-Lifecycle dokumentiert
- [ ] Report ist allein lesbar

---

# Merksatz

> **Security-Audit = belegte Angriffskette + belegte Tragweite + belegte Coverage.**
> Scanner liefern Signale; die Befundung beginnt erst danach.
