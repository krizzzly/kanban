import Foundation

/// Liest ein **Compound File Binary Format** (CFBF, auch OLE2 oder „Structured Storage") — das
/// Container-Format, in dem eine Outlook-`.msg` steckt. Ein Dateisystem in einer Datei: Ordner
/// („storages"), Dateien („streams"), eine FAT für die Sektorketten.
///
/// Eigener Leser, weil macOS keinen mitbringt: Quick Look **hängt** an einer `.msg` (zwei Minuten
/// ohne Ergebnis gemessen), und ein `.msg` ohne Leser ist im Task-Ordner sonst nur die Zeile
/// „Binärdatei — im Finder öffnen".
///
/// Gelesen, nie geschrieben, und gegen **fremde Bytes** ausgelegt: jeder Zugriff ist
/// bereichsgeprüft, jede Sektorkette hat einen Zyklenschutz, der Verzeichnisbaum eine Tiefengrenze.
/// Ein kaputtes Feld gibt `nil`, nie einen Absturz.
public struct CompoundFile {
    /// Ein Verzeichniseintrag. Die Geschwister-Verweise sind ein Rot-Schwarz-Baum, kein Array —
    /// deshalb `children(of:)` statt eines fertigen Feldes.
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let isStorage: Bool
        let left: UInt32
        let right: UInt32
        let child: UInt32
        let start: UInt32
        let size: Int
    }

    /// `D0CF11E0A1B11AE1` — dieselbe Signatur wie bei `.doc`/`.xls` der alten Generation.
    static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    /// Ab diesem Wert ist eine Sektornummer keine Nummer mehr, sondern eine Marke
    /// (ENDOFCHAIN/FREESECT/FATSECT/DIFSECT).
    static let firstSpecialSector: UInt32 = 0xFFFF_FFFA
    /// Obergrenze jeder Kette. Zusammen mit dem Besucht-Set der Schutz gegen eine Datei, die sich
    /// im Kreis dreht oder auf ein Vielfaches ihrer Grösse zeigt.
    static let maxChain = 1 << 20
    /// Der Verzeichnisbaum einer `.msg` ist zwei Ebenen tief (Nachricht → Anhang/Empfänger).
    static let maxDepth = 16

    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private let fat: [UInt32]
    private let miniFAT: [UInt32]
    private let miniStream: [UInt8]
    public let entries: [Entry]

    // MARK: - Aufbau

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 512, Array(bytes.prefix(8)) == Self.signature else { return nil }
        self.bytes = bytes

        // Sektorgrösse steht als Zweierexponent da: 9 → 512 (Version 3), 12 → 4096 (Version 4).
        guard let sectorShift = Self.u16(bytes, 0x1E), (7...12).contains(sectorShift),
              let miniShift = Self.u16(bytes, 0x20), (2...12).contains(miniShift),
              let fatCount = Self.u32(bytes, 0x2C),
              let dirStart = Self.u32(bytes, 0x30),
              let cutoff = Self.u32(bytes, 0x38),
              let miniFATStart = Self.u32(bytes, 0x3C),
              let miniFATCount = Self.u32(bytes, 0x40),
              let difatStart = Self.u32(bytes, 0x44),
              let difatCount = Self.u32(bytes, 0x48) else { return nil }
        sectorSize = 1 << Int(sectorShift)
        miniSectorSize = 1 << Int(miniShift)
        miniCutoff = Int(cutoff)

        // --- DIFAT: die Liste der FAT-Sektoren. Die ersten 109 stehen im Kopf, der Rest in einer
        // eigenen Kette, deren letzter Eintrag je Sektor auf den nächsten zeigt.
        var difat: [UInt32] = []
        for i in 0..<109 {
            guard let value = Self.u32(bytes, 0x4C + i * 4) else { break }
            difat.append(value)
        }
        let perSector = sectorSize / 4
        var next = difatStart
        var guardCount = 0
        while next < Self.firstSpecialSector, guardCount < Int(difatCount) + 1, guardCount < Self.maxChain {
            guardCount += 1
            guard let sector = Self.sectorRange(next, sectorSize: sectorSize, count: bytes.count) else { break }
            for i in 0..<(perSector - 1) {
                guard let value = Self.u32(bytes, sector + i * 4) else { break }
                difat.append(value)
            }
            guard let following = Self.u32(bytes, sector + (perSector - 1) * 4) else { break }
            next = following
        }

        // --- FAT: die Sektorketten aller grossen Streams.
        var fat: [UInt32] = []
        for sectorNumber in difat.prefix(Int(fatCount)) where sectorNumber < Self.firstSpecialSector {
            guard let sector = Self.sectorRange(sectorNumber, sectorSize: sectorSize, count: bytes.count)
            else { continue }
            for i in 0..<perSector {
                guard let value = Self.u32(bytes, sector + i * 4) else { break }
                fat.append(value)
            }
        }
        guard !fat.isEmpty else { return nil }
        self.fat = fat

        // --- Verzeichnis: 128-Byte-Einträge.
        let directory = Self.concat(chain: Self.walk(from: dirStart, fat: fat),
                                    bytes: bytes, sectorSize: sectorSize)
        var entries: [Entry] = []
        for i in stride(from: 0, to: directory.count - 127, by: 128) {
            guard let entry = Self.parseEntry(directory, at: i) else { continue }
            entries.append(entry)
        }
        guard let root = entries.first else { return nil }
        self.entries = entries

        // --- Mini-FAT + Mini-Stream: alles unter `miniCutoff` (4096) liegt nicht in eigenen
        // Sektoren, sondern in einem einzigen Stream am Wurzeleintrag, gestückelt zu 64 Bytes.
        var miniFAT: [UInt32] = []
        for sectorNumber in Self.walk(from: miniFATStart, fat: fat).prefix(Int(miniFATCount)) {
            guard let sector = Self.sectorRange(sectorNumber, sectorSize: sectorSize, count: bytes.count)
            else { continue }
            for i in 0..<perSector {
                guard let value = Self.u32(bytes, sector + i * 4) else { break }
                miniFAT.append(value)
            }
        }
        self.miniFAT = miniFAT
        self.miniStream = Self.concat(chain: Self.walk(from: root.start, fat: fat),
                                      bytes: bytes, sectorSize: sectorSize)
    }

    /// Layout eines Verzeichniseintrags. Die Geschwister- und Kind-Verweise stehen bei **0x44/0x48/
    /// 0x4C** — vier Bytes weiter, als eine naheliegende Zählung vermuten lässt (davor liegt das
    /// Farb-Byte des Rot-Schwarz-Baums, danach die CLSID). Vier Bytes daneben, und der Baum führt
    /// ins Leere.
    static func parseEntry(_ bytes: [UInt8], at offset: Int) -> Entry? {
        guard let nameLength = u16(bytes, offset + 0x40), nameLength >= 2, nameLength <= 64,
              let type = bytes[safe: offset + 0x42],
              let left = u32(bytes, offset + 0x44),
              let right = u32(bytes, offset + 0x48),
              let child = u32(bytes, offset + 0x4C),
              let start = u32(bytes, offset + 0x74),
              let size = u64(bytes, offset + 0x78) else { return nil }
        guard type == 1 || type == 2 || type == 5 else { return nil }   // storage/stream/root
        // Der Name ist UTF-16LE **mit** abschliessender Null, die die Länge mitzählt.
        let nameBytes = Array(bytes[safe: offset..<(offset + Int(nameLength) - 2)] ?? [])
        let name = String(decoding: nameBytes.chunkedUTF16, as: UTF16.self)
        return Entry(name: name, isStorage: type != 2,
                     left: left, right: right, child: child,
                     start: start, size: Int(min(size, UInt64(Int.max))))
    }

    // MARK: - Lesen

    /// Die Einträge **direkt unter** einem Storage. Der Rot-Schwarz-Baum wird in Ordnung
    /// durchlaufen; ein Zyklus (kaputte Datei) endet am Besucht-Set, nicht in einer Endlosschleife.
    public func children(of index: Int) -> [(name: String, index: Int)] {
        guard let entry = entries[safe: index] else { return [] }
        var result: [(name: String, index: Int)] = []
        var visited = Set<UInt32>()
        collect(entry.child, into: &result, visited: &visited, depth: 0)
        return result
    }

    /// Die oberste Ebene: die Kinder des Wurzeleintrags.
    public var rootChildren: [(name: String, index: Int)] { children(of: 0) }

    private func collect(_ id: UInt32, into result: inout [(name: String, index: Int)],
                         visited: inout Set<UInt32>, depth: Int) {
        guard depth < Self.maxDepth, id < Self.firstSpecialSector,
              !visited.contains(id), let entry = entries[safe: Int(id)] else { return }
        visited.insert(id)
        collect(entry.left, into: &result, visited: &visited, depth: depth + 1)
        result.append((entry.name, Int(id)))
        collect(entry.right, into: &result, visited: &visited, depth: depth + 1)
    }

    /// Der Inhalt eines Streams. Kleine Streams liegen im Mini-Stream, grosse in eigenen Sektoren —
    /// die Grenze ist `miniCutoff`; der Wurzeleintrag selbst ist immer gross.
    public func data(at index: Int) -> [UInt8] {
        guard let entry = entries[safe: index], !entry.isStorage || index == 0 else { return [] }
        let raw: [UInt8]
        if entry.size < miniCutoff && index != 0 {
            raw = Self.concat(chain: Self.walk(from: entry.start, fat: miniFAT),
                              bytes: miniStream, sectorSize: miniSectorSize, offsetByOne: false)
        } else {
            raw = Self.concat(chain: Self.walk(from: entry.start, fat: fat),
                              bytes: bytes, sectorSize: sectorSize)
        }
        return Array(raw.prefix(entry.size))
    }

    // MARK: - Sektoren

    /// Folgt einer Sektorkette. Bricht bei einer Marke, einem Zyklus oder der Längengrenze ab.
    static func walk(from start: UInt32, fat: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        var visited = Set<UInt32>()
        var current = start
        while current < firstSpecialSector, !visited.contains(current), result.count < maxChain {
            // Erst nachschlagen, dann übernehmen: ein Sektor, den die FAT gar nicht beschreibt,
            // gehört zu keiner Kette. Ihn trotzdem mitzunehmen hiesse, einer kaputten Datei einen
            // Sektor zu glauben, den sie nur behauptet.
            guard let next = fat[safe: Int(current)] else { break }
            visited.insert(current)
            result.append(current)
            current = next
        }
        return result
    }

    /// Der Byte-Bereich eines Sektors. `offsetByOne`, weil im **Datei**-Bild der 512-Byte-Kopf vor
    /// Sektor 0 liegt — im Mini-Stream dagegen nicht.
    static func sectorRange(_ number: UInt32, sectorSize: Int, count: Int,
                            offsetByOne: Bool = true) -> Int? {
        let index = Int(number) + (offsetByOne ? 1 : 0)
        let (offset, overflow) = index.multipliedReportingOverflow(by: sectorSize)
        guard !overflow, offset >= 0, offset + sectorSize <= count else { return nil }
        return offset
    }

    static func concat(chain: [UInt32], bytes: [UInt8], sectorSize: Int,
                       offsetByOne: Bool = true) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(chain.count * sectorSize)
        for number in chain {
            guard let offset = sectorRange(number, sectorSize: sectorSize,
                                           count: bytes.count, offsetByOne: offsetByOne)
            else { continue }
            out.append(contentsOf: bytes[offset..<(offset + sectorSize)])
        }
        return out
    }

    // MARK: - Bereichsgeprüfte Zahlen

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16? {
        guard o >= 0, o + 2 <= b.count else { return nil }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | (UInt32(b[o + $1]) << (8 * UInt32($1))) }
    }

    static func u64(_ b: [UInt8], _ o: Int) -> UInt64? {
        guard o >= 0, o + 8 <= b.count else { return nil }
        return (0..<8).reduce(UInt64(0)) { $0 | (UInt64(b[o + $1]) << (8 * UInt64($1))) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    subscript(safe range: Range<Int>) -> ArraySlice<Element>? {
        guard range.lowerBound >= 0, range.upperBound <= count,
              range.lowerBound <= range.upperBound else { return nil }
        return self[range]
    }
}

extension Array where Element == UInt8 {
    /// Byte-Paare als UTF-16-Codeunits (little endian). Eine ungerade Restlänge fällt weg — ein
    /// halbes Zeichen gibt es nicht.
    var chunkedUTF16: [UInt16] {
        stride(from: 0, to: count - 1, by: 2).map { UInt16(self[$0]) | (UInt16(self[$0 + 1]) << 8) }
    }
}
