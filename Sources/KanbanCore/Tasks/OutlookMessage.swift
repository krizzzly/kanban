import Foundation

/// Eine Outlook-`.msg`, so weit gelesen, wie eine Vorschau sie braucht: Kopf, Körper, Anhangnamen.
///
/// Im Task-Ordner liegen solche Dateien, weil jemand den Mailverkehr zum Ticket mitgespeichert hat —
/// oft die Anforderung selbst. Sie sind damit Inhalt, nicht Beiwerk.
public struct OutlookMessage: Sendable, Equatable {
    public struct Attachment: Sendable, Equatable, Hashable {
        public let name: String
        public let byteCount: Int
        /// Ein Bild aus der Signatur oder dem Fliesstext (`cid:`) — kein eigener Anhang, den man
        /// öffnen will. Sie werden in den Körper eingebettet und in der Liste nicht genannt.
        public let isInline: Bool
    }

    public let subject: String?
    public let fromName: String?
    public let fromAddress: String?
    public let to: String?
    public let cc: String?
    public let date: Date?
    /// Der HTML-Körper — auf den Body reduziert, `cid:`-Bilder eingebettet.
    public let html: String?
    /// Der Text-Körper. Immer vorhanden (in allen neun geprüften Dateien), dient als Rückfall.
    public let text: String?
    public let attachments: [Attachment]

    /// Anhänge, die man wirklich als Anhang liest — ohne die eingebetteten Signaturbilder.
    public var realAttachments: [Attachment] { attachments.filter { !$0.isInline } }

    /// Die Nachricht für die Vorschau: Kopfzeilen als Markdown, darunter der Körper.
    ///
    /// Bewusst Markdown mit rohem HTML darin statt einer eigenen Seite — dann rendert es derselbe
    /// Weg wie Task-Files und Kommentare (`MarkdownWebView`), erbt dessen Stylesheet und damit
    /// Hell/Dunkel, und der Mail-Körper braucht keine eigenen Farben.
    public var markdown: String {
        var head: [String] = []
        if let fromName, let fromAddress {
            head.append("**Von:** \(Self.escape(fromName)) &lt;\(Self.escape(fromAddress))&gt;")
        } else if let sender = fromName ?? fromAddress {
            head.append("**Von:** \(Self.escape(sender))")
        }
        if let to { head.append("**An:** \(Self.escape(to))") }
        if let cc { head.append("**Cc:** \(Self.escape(cc))") }
        if let date { head.append("**Datum:** \(Self.dateFormatter.string(from: date))") }
        let files = realAttachments
        if !files.isEmpty {
            let list = files.map { "\(Self.escape($0.name)) (\(Self.size($0.byteCount)))" }
            head.append("**Anhänge:** \(list.joined(separator: ", "))")
        }

        var out: [String] = []
        // Kein `#`: die Vorschau steht schon unter der Kopfzeile mit dem Dateinamen, und eine
        // Überschrift in Seitenbreite darüber wäre der zweite Titel derselben Sache.
        if let subject { out.append("### \(Self.escape(subject))") }
        if !head.isEmpty { out.append(head.joined(separator: "<br>")) }
        out.append("---")
        out.append(body)
        return out.joined(separator: "\n\n")
    }

    /// Der Körper: HTML, wenn die Mail welches mitbringt, sonst der Text.
    ///
    /// Der Text kommt mit **harten Zeilenumbrüchen** — als Markdown gelesen würde er zu einem
    /// einzigen Absatz zusammenlaufen und jede Aufzählung, jede Signatur und jede zitierte Antwort
    /// wäre eine Zeile. Deshalb `pre-wrap` statt eines Absatzes, und `<pre>` wäre auch falsch: das
    /// bräche lange Zeilen nicht um.
    var body: String {
        if let html, !html.isEmpty { return html }
        guard let text, !text.isEmpty else { return "_(kein Inhalt)_" }
        return "<div style=\"white-space: pre-wrap\">\(Self.escape(text))</div>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Wie `CommentThread.absolute` — dieselbe Schreibweise für Zeitpunkte in derselben Ansicht.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter
    }()
}

/// Liest `.msg` (MAPI in einem `CompoundFile`).
///
/// Die Eigenschaften stehen als Streams `__substg1.0_<ID><TYP>` da: `001F` ist UTF-16-Text, `0102`
/// sind rohe Bytes. Die Zahlen und Zeitstempel liegen dagegen zusammen in
/// `__properties_version1.0`. Alle Tags unten sind an den echten Dateien dieser Maschine
/// nachgesehen, nicht der Spezifikation entnommen.
public enum OutlookMessageReader {
    /// Grenze fürs Einlesen. Die grösste Datei hier ist 282 KB; 64 MB ist der Notausgang gegen eine
    /// Datei, die den Speicher aufbraucht, bevor irgendeine Prüfung greift.
    public static let maxBytes = 64 * 1024 * 1024
    /// So gross darf ein eingebettetes Bild werden (wie `TaskFileLoader.maxInlineImageBytes`) —
    /// darüber bleibt der Platzhalter stehen, statt die Seite unbrauchbar aufzublähen.
    static let maxInlineImageBytes = 6 * 1024 * 1024

    public static func isMessageFile(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == "msg"
    }

    public static func read(_ url: URL) -> OutlookMessage? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= maxBytes, let data = try? Data(contentsOf: url) else { return nil }
        return read(data: data)
    }

    public static func read(data: Data) -> OutlookMessage? {
        guard let file = CompoundFile(data: data) else { return nil }
        let top = Dictionary(file.rootChildren.map { ($0.name, $0.index) }, uniquingKeysWith: { a, _ in a })

        func string(_ tag: String) -> String? {
            guard let index = top["__substg1.0_\(tag)001F"] else { return nil }
            let value = utf16String(file.data(at: index))
            return value.isEmpty ? nil : value
        }

        let properties = top["__properties_version1.0"].map { file.data(at: $0) } ?? []
        let codepage = fixedProperty(properties, id: 0x3FDE, type: 0x0003)
            ?? fixedProperty(properties, id: 0x3FFD, type: 0x0003)

        let parts = attachmentParts(file: file, top: top)
        let embedded = top["__substg1.0_10130102"]
            .map { decodeHTML(file.data(at: $0), codepage: codepage.map { Int($0) }) }
            .map { inlineImages(in: bodyFragment(of: $0), parts: parts) }
        let html = embedded?.html
        let shown = embedded?.usedContentIDs ?? []

        return OutlookMessage(
            subject: string("0037") ?? string("0E1D"),
            fromName: string("0C1A"),
            // Die SMTP-Adresse zuerst; der X.500-Pfad fällt ganz weg, siehe `mailAddress`.
            fromAddress: mailAddress(string("5D01") ?? string("0C1F")),
            to: string("0E04"),
            cc: string("0E03"),
            // Reihenfolge nach Aussagekraft: abgeschickt, zugestellt, zuletzt angelegt. Die dritte
            // Stufe ist nicht theoretisch — zwei der neun Dateien haben nur sie.
            date: [0x0039, 0x0E06, 0x3007]
                .lazy
                .compactMap { fixedProperty(properties, id: $0, type: 0x0040) }
                .compactMap(fileTime)
                .first,
            html: html,
            text: top["__substg1.0_1000001F"].map { utf16String(file.data(at: $0)) }
                .flatMap { $0.isEmpty ? nil : $0 },
            attachments: parts.map {
                // „Inline" heisst: **im Körper zu sehen**, nicht bloss „hat eine Content-Id". Vier
                // der neun Dateien tragen Bilder mit Content-Id, haben aber gar keinen HTML-Körper
                // (nur Text) — deren Bilder zeigt niemand, also sind es Anhänge. Nach der
                // Id allein zu gehen hiesse: „keine Anhänge" über sechs Bildern.
                OutlookMessage.Attachment(name: $0.name, byteCount: $0.bytes.count,
                                          isInline: $0.contentID.map(shown.contains) ?? false)
            })
    }

    // MARK: - Anhänge

    struct Part {
        let name: String
        let bytes: [UInt8]
        let contentID: String?
        let mime: String?
    }

    /// Nur die Anhänge der **obersten** Ebene. Eine angehängte Mail bringt ihre eigenen mit; die
    /// gehören zu ihr, nicht in die Liste dieser Nachricht.
    static func attachmentParts(file: CompoundFile, top: [String: Int]) -> [Part] {
        top.filter { $0.key.hasPrefix("__attach_version1.0") }
            .sorted { $0.key < $1.key }
            .map { entry in
                let fields = Dictionary(file.children(of: entry.value).map { ($0.name, $0.index) },
                                        uniquingKeysWith: { a, _ in a })
                func string(_ tag: String) -> String? {
                    guard let index = fields["__substg1.0_\(tag)001F"] else { return nil }
                    let value = utf16String(file.data(at: index))
                    return value.isEmpty ? nil : value
                }
                return Part(name: string("3707") ?? string("3704") ?? "(ohne Namen)",
                            bytes: fields["__substg1.0_37010102"].map { file.data(at: $0) } ?? [],
                            contentID: string("3712"),
                            mime: string("370E"))
            }
    }

    // MARK: - Körper

    /// Reduziert ein HTML-Dokument auf seinen Body und wirft weg, was in einer Vorschau nur stört
    /// oder schadet: `<head>` (samt `<meta charset>`, das nach der Umkodierung falsch wäre),
    /// `<style>` und `<script>`.
    ///
    /// Die Stilblöcke **müssen** raus, nicht nur unschädlich gemacht werden: der Markdown-Renderer
    /// entschärft `<style>` durch Escapen (`tagfilter`), und dann stünde Outlooks seitenlanges
    /// Word-CSS als sichtbarer Text über der Mail.
    static func bodyFragment(of html: String) -> String {
        var result = html
        for tag in ["style", "script", "head", "title"] {
            result = removingElements(named: tag, in: result)
        }
        if let body = innerHTML(ofFirst: "body", in: result) { result = body }
        // Ein `<html>`-Rahmen ohne Body-Tag bleibt sonst als leerer Wrapper stehen.
        for tag in ["html", "body"] {
            result = result.replacingOccurrences(
                of: "</?\(tag)\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removingElements(named tag: String, in html: String) -> String {
        html.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", with: "",
                                  options: [.regularExpression, .caseInsensitive])
            // Ein `<head>` ohne Abschluss (kommt vor) darf nicht den Rest verschlucken.
            .replacingOccurrences(of: "<\(tag)\\b[^>]*/>", with: "",
                                  options: [.regularExpression, .caseInsensitive])
    }

    static func innerHTML(ofFirst tag: String, in html: String) -> String? {
        guard let open = html.range(of: "<\(tag)\\b[^>]*>",
                                    options: [.regularExpression, .caseInsensitive]) else { return nil }
        let rest = html[open.upperBound...]
        guard let close = rest.range(of: "</\(tag)\\s*>",
                                     options: [.regularExpression, .caseInsensitive]) else {
            return String(rest)
        }
        return String(rest[..<close.lowerBound])
    }

    /// Ersetzt `cid:`-Verweise durch die Bilddaten als `data:`-URI. WKWebViews `loadHTMLString` hat
    /// keinen Dateizugriff — und die Bilder liegen ohnehin nicht als Datei vor, sondern in der
    /// `.msg`. Ohne das zeigt jede Signatur drei kaputte Bildsymbole.
    static func inlineImages(in html: String, parts: [Part]) -> (html: String, usedContentIDs: Set<String>) {
        var result = html
        var used: Set<String> = []
        for part in parts {
            guard let cid = part.contentID, !part.bytes.isEmpty,
                  part.bytes.count <= maxInlineImageBytes else { continue }
            let reference = "cid:" + cid
            guard result.range(of: reference, options: .caseInsensitive) != nil else { continue }
            let mime = part.mime ?? mimeType(forName: part.name)
            let uri = "data:\(mime);base64,\(Data(part.bytes).base64EncodedString())"
            result = result.replacingOccurrences(
                of: "cid:" + NSRegularExpression.escapedPattern(for: cid),
                with: uri, options: [.regularExpression, .caseInsensitive])
            used.insert(cid)
        }
        return (result, used)
    }

    /// Eine Absenderadresse — oder nichts. Bei internen Absendern steht in `0C1F` kein Postfach,
    /// sondern der Exchange-Pfad (`/o=intraOrg/ou=Exchange Administrative Group…`). Den als Adresse
    /// hinzuschreiben sähe aus wie eine Adresse und wäre keine; der Name daneben steht ohnehin da.
    static func mailAddress(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("/") else { return nil }
        return raw
    }

    static func mimeType(forName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "bmp": "image/bmp"
        case "webp": "image/webp"
        default: "application/octet-stream"
        }
    }

    // MARK: - Kodierung

    /// Der HTML-Körper liegt **nicht** in UTF-8 vor, sondern in der Codepage der Nachricht
    /// (`PR_INTERNET_CPID`) — hier durchweg 28591/1252. Als UTF-8 gelesen käme aus „Rückerstattung"
    /// Zeichensalat oder gar nichts.
    static func decodeHTML(_ bytes: [UInt8], codepage: Int?) -> String {
        let data = Data(bytes)
        let decoded: String
        if let encoding = codepage.flatMap(encoding(forCodepage:)),
           let text = String(data: data, encoding: encoding) {
            decoded = text
        } else if let text = String(data: data, encoding: .utf8) {
            decoded = text
        } else {
            decoded = String(data: data, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
        }
        // Auch hier kann eine abschliessende Null stehen — mit derselben Folge, siehe `utf16String`.
        return String(String.UnicodeScalarView(decoded.unicodeScalars.filter { $0.value != 0 }))
    }

    /// Windows-1252 auch für **28591** (ISO-8859-1): Outlook meldet Latin-1 und schreibt trotzdem
    /// gern die typografischen Anführungszeichen aus 0x80–0x9F, wo Latin-1 nur Steuerzeichen kennt.
    /// CP1252 liest beides richtig. (In den neun Dateien hier ist dieser Bereich leer — die Wahl
    /// kann also nur helfen, nie schaden.)
    static func encoding(forCodepage codepage: Int) -> String.Encoding? {
        switch codepage {
        case 65001: .utf8
        case 1252, 28591: .windowsCP1252
        case 1250, 28592: .windowsCP1250
        case 1251, 28595: .windowsCP1251
        case 1253, 28597: .windowsCP1253
        case 1254, 28599: .windowsCP1254
        case 20127: .ascii
        case 1200: .utf16LittleEndian
        default: nil
        }
    }

    /// Ein Text-Property, ohne die abschliessende Null.
    ///
    /// Die Streams sind **uneinheitlich**: `0E04` (An) zählt die Null mit (36 Bytes für 17 Zeichen),
    /// `0037` (Betreff) nicht (52 Bytes für 26 Zeichen). Bleibt sie stehen, endet das Markdown
    /// mitten im Kopf — cmark liest bis zur ersten Null. Genau so gemessen: 208 statt 2000 Zeichen
    /// gerendert, Körper weg. `trimmingCharacters(in: .whitespacesAndNewlines)` fängt das nicht,
    /// eine Null ist ein Steuerzeichen und kein Leerraum.
    static func utf16String(_ bytes: [UInt8]) -> String {
        String(String.UnicodeScalarView(
            String(decoding: bytes.chunkedUTF16, as: UTF16.self).unicodeScalars.filter { $0.value != 0 }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Feste Eigenschaften (`__properties_version1.0`)

    /// Der Kopf einer Nachricht ist **32 Bytes** lang, danach folgen 16-Byte-Einträge: 2 Bytes Typ,
    /// 2 Bytes Id, 4 Bytes Flags, 8 Bytes Wert. An vier Dateien gegengerechnet — der Rest geht
    /// jedes Mal genau auf.
    static let propertyHeaderSize = 32

    static func fixedProperty(_ bytes: [UInt8], id: UInt16, type: UInt16) -> UInt64? {
        var offset = propertyHeaderSize
        while offset + 16 <= bytes.count {
            defer { offset += 16 }
            guard let entryType = CompoundFile.u16(bytes, offset),
                  let entryID = CompoundFile.u16(bytes, offset + 2),
                  entryID == id, entryType == type else { continue }
            return CompoundFile.u64(bytes, offset + 8)
        }
        return nil
    }

    /// FILETIME: 100-Nanosekunden-Schritte seit 1601. Offensichtlich Unsinniges (0, oder jenseits
    /// des Jahres 3000) gilt als „kein Datum" — ein falsch geratener Zeitpunkt wäre schlechter als
    /// gar keiner.
    static func fileTime(_ raw: UInt64) -> Date? {
        guard raw > 0 else { return nil }
        let seconds = Double(raw) / 10_000_000 - 11_644_473_600
        guard seconds > 0, seconds < 32_503_680_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
