import XCTest
@testable import KanbanCore

final class CompoundFileTests: XCTestCase {
    // MARK: - Ein echtes, von Hand gebautes CFBF

    /// Baut die kleinste gültige Datei: Kopf, eine FAT, ein Verzeichnis, ein grosser Stream.
    /// Bewusst **über** dem Mini-Cutoff (4096), damit dieser Test die normale Sektorkette prüft;
    /// der Mini-Stream hat seinen eigenen Test unten.
    private func makeFile(streamBytes: [UInt8]) -> Data {
        let sectorSize = 512
        var header = [UInt8](repeating: 0, count: sectorSize)
        header.replaceSubrange(0..<8, with: CompoundFile.signature)
        func put16(_ v: UInt16, _ o: Int, _ b: inout [UInt8]) {
            b[o] = UInt8(v & 0xFF); b[o + 1] = UInt8(v >> 8)
        }
        func put32(_ v: UInt32, _ o: Int, _ b: inout [UInt8]) {
            for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) }
        }
        put16(9, 0x1E, &header)          // Sektorgrösse 2^9 = 512
        put16(6, 0x20, &header)          // Mini-Sektor 2^6 = 64
        put32(1, 0x2C, &header)          // eine FAT-Sektor
        put32(1, 0x30, &header)          // Verzeichnis beginnt in Sektor 1
        put32(4096, 0x38, &header)       // Mini-Cutoff
        put32(0xFFFFFFFE, 0x3C, &header) // keine Mini-FAT
        put32(0, 0x40, &header)
        put32(0xFFFFFFFE, 0x44, &header) // keine weitere DIFAT
        put32(0, 0x48, &header)
        put32(0, 0x4C, &header)          // DIFAT[0] = Sektor 0 ist die FAT

        let dataSectors = (streamBytes.count + sectorSize - 1) / sectorSize
        var fat = [UInt8](repeating: 0xFF, count: sectorSize)   // alles frei
        put32(0xFFFFFFFD, 0, &fat)                              // Sektor 0: die FAT selbst
        put32(0xFFFFFFFE, 4, &fat)                              // Sektor 1: Verzeichnis, Kettenende
        for i in 0..<dataSectors {
            let sector = 2 + i
            put32(i == dataSectors - 1 ? 0xFFFFFFFE : UInt32(sector + 1), sector * 4, &fat)
        }

        var directory = [UInt8](repeating: 0, count: sectorSize)
        func writeEntry(_ index: Int, name: String, type: UInt8, child: UInt32,
                        start: UInt32, size: UInt64) {
            let base = index * 128
            let utf16 = Array(name.utf16)
            for (i, unit) in utf16.enumerated() {
                directory[base + i * 2] = UInt8(unit & 0xFF)
                directory[base + i * 2 + 1] = UInt8(unit >> 8)
            }
            put16(UInt16((utf16.count + 1) * 2), base + 0x40, &directory)   // Länge inkl. Null
            directory[base + 0x42] = type
            put32(0xFFFFFFFF, base + 0x44, &directory)   // links
            put32(0xFFFFFFFF, base + 0x48, &directory)   // rechts
            put32(child, base + 0x4C, &directory)
            put32(start, base + 0x74, &directory)
            for i in 0..<8 { directory[base + 0x78 + i] = UInt8((size >> (8 * UInt64(i))) & 0xFF) }
        }
        writeEntry(0, name: "Root Entry", type: 5, child: 1, start: 0xFFFFFFFE, size: 0)
        writeEntry(1, name: "BigStream", type: 2, child: 0xFFFFFFFF,
                   start: 2, size: UInt64(streamBytes.count))

        var padded = streamBytes
        padded += [UInt8](repeating: 0, count: dataSectors * sectorSize - streamBytes.count)
        return Data(header + fat + directory + padded)
    }

    func testReadsAStreamOutOfAHandBuiltFile() throws {
        let payload = (0..<5000).map { UInt8($0 % 251) }
        let file = try XCTUnwrap(CompoundFile(data: makeFile(streamBytes: payload)))
        let children = file.rootChildren
        XCTAssertEqual(children.map(\.name), ["BigStream"])
        XCTAssertEqual(file.data(at: children[0].index), payload)
    }

    /// Die Streamlänge schneidet die Sektor-Auffüllung ab — sonst hinge an jedem Text ein Schwanz
    /// aus Nullen.
    func testStreamIsTruncatedToItsRecordedLength() throws {
        let payload = (0..<4097).map { _ in UInt8(7) }
        let file = try XCTUnwrap(CompoundFile(data: makeFile(streamBytes: payload)))
        XCTAssertEqual(file.data(at: file.rootChildren[0].index).count, 4097)
    }

    func testRejectsAnythingThatIsNotACompoundFile() {
        XCTAssertNil(CompoundFile(data: Data()))
        XCTAssertNil(CompoundFile(data: Data(repeating: 0, count: 4096)))
        XCTAssertNil(CompoundFile(data: Data("# ein Markdown-Task-File".utf8)))
        // Richtige Signatur, sonst nur Nullen: Sektorgrösse 2^0 ist ungültig.
        var broken = [UInt8](repeating: 0, count: 1024)
        broken.replaceSubrange(0..<8, with: CompoundFile.signature)
        XCTAssertNil(CompoundFile(data: Data(broken)))
    }

    // MARK: - Verzeichniseintrag

    /// Die Verweise liegen bei **0x44/0x48/0x4C**. Vier Bytes daneben gelesen (davor steht das
    /// Farb-Byte des Rot-Schwarz-Baums), und der Baum zeigt ins Leere: die erste Fassung dieses
    /// Lesers fand so **keinen einzigen** Eintrag in einer gültigen Datei.
    func testDirectoryEntryOffsets() throws {
        var bytes = [UInt8](repeating: 0, count: 128)
        for (i, unit) in Array("Hi".utf16).enumerated() {
            bytes[i * 2] = UInt8(unit & 0xFF); bytes[i * 2 + 1] = UInt8(unit >> 8)
        }
        bytes[0x40] = 6            // 2 Zeichen + Null, mal zwei
        bytes[0x42] = 2            // stream
        bytes[0x44] = 0x11         // links
        bytes[0x48] = 0x22         // rechts
        bytes[0x4C] = 0x33         // Kind
        bytes[0x74] = 0x44         // Startsektor
        bytes[0x78] = 0x55         // Grösse
        let entry = try XCTUnwrap(CompoundFile.parseEntry(bytes, at: 0))
        XCTAssertEqual(entry.name, "Hi")
        XCTAssertFalse(entry.isStorage)
        XCTAssertEqual(entry.left, 0x11)
        XCTAssertEqual(entry.right, 0x22)
        XCTAssertEqual(entry.child, 0x33)
        XCTAssertEqual(entry.start, 0x44)
        XCTAssertEqual(entry.size, 0x55)
    }

    func testUnusedDirectorySlotsAreSkipped() {
        // Typ 0 heisst „unbelegt" — davon stehen in jeder Datei Dutzende hinter den echten.
        XCTAssertNil(CompoundFile.parseEntry([UInt8](repeating: 0, count: 128), at: 0))
    }

    // MARK: - Sektorketten

    func testChainStopsAtTheEndMarker() {
        XCTAssertEqual(CompoundFile.walk(from: 0, fat: [1, 2, 0xFFFFFFFE]), [0, 1, 2])
    }

    /// Eine Kette, die im Kreis zeigt, ist eine kaputte (oder bösartige) Datei — sie darf die
    /// Vorschau nicht aufhängen.
    func testCyclicChainTerminates() {
        XCTAssertEqual(CompoundFile.walk(from: 0, fat: [1, 2, 0]), [0, 1, 2])
    }

    func testChainStopsAtTheEndOfTheTable() {
        XCTAssertEqual(CompoundFile.walk(from: 0, fat: [5]), [0])
    }

    // MARK: - Bereichsprüfung

    func testNumbersOutsideTheBufferYieldNil() {
        let bytes: [UInt8] = [1, 2, 3, 4]
        XCTAssertEqual(CompoundFile.u32(bytes, 0), 0x04030201)
        XCTAssertNil(CompoundFile.u32(bytes, 1))
        XCTAssertNil(CompoundFile.u16(bytes, -1))
        XCTAssertNil(CompoundFile.u64(bytes, 0))
    }
}
