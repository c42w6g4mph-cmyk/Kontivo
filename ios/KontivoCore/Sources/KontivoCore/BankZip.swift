import Foundation

// MARK: - Kontoauszug als ZIP: Excel (.xlsx), OpenDocument (.ods), gezippte camt/MT940/CSV
// 1:1 nach Web zipOpen, xlsxTexts, odsTexts, bankZip (v261, v272, df2851e). Entpacken auf dem Gerät (eigenes Inflate, plattformunabhängig).

/// ZIP-Datei lesen (Web `zipOpen`): Inhaltsverzeichnis am Ende, Einträge gespeichert (0) oder komprimiert (8, Deflate).
struct ZipArchive {
    struct Entry {
        var method: Int
        var size: Int
        var offset: Int
    }

    enum Failure: Error {
        case notZip
        case inflate
    }

    let bytes: [UInt8]
    /// Namen in der Reihenfolge des Inhaltsverzeichnisses (Web `Object.keys(F)`)
    private(set) var names: [String] = []
    private var entries: [String: Entry] = [:]
    private var lower: [String: String] = [:]

    private func u16(_ i: Int) -> Int { i + 1 < bytes.count ? Int(bytes[i]) | Int(bytes[i + 1]) << 8 : 0 }
    private func u32(_ i: Int) -> Int { i + 3 < bytes.count ? u16(i) | u16(i + 2) << 16 : 0 }

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        var e = -1
        var i = bytes.count - 22
        let stop = Swift.max(0, bytes.count - 70000)
        while i >= stop {
            if u32(i) == 0x06054b50 {
                e = i
                break
            }
            i -= 1
        }
        if e < 0 { throw Failure.notZip }
        let n = u16(e + 10)
        var p = u32(e + 16)
        for _ in 0..<n {
            guard p + 46 <= bytes.count else { break }
            let m = u16(p + 10), cs = u32(p + 20), nl = u16(p + 28), xl = u16(p + 30), cl = u16(p + 32), lo = u32(p + 42)
            let nb = Array(bytes[(p + 46)..<Swift.min(bytes.count, p + 46 + nl)])
            var name = String(decoding: nb, as: UTF8.self).replacingOccurrences(of: "\\", with: "/")
            while name.hasPrefix("/") { name.removeFirst() }
            if entries[name] == nil { names.append(name) }
            entries[name] = Entry(method: m, size: cs, offset: lo)
            lower[name.lowercased()] = name
            p += 46 + nl + xl + cl
        }
    }

    /// Rohbytes eines Eintrags (Gross/Klein egal, führende «/» egal); fehlt er: leer (Web `getBytes`)
    func data(_ name: String) throws -> Data {
        var key = name
        while key.hasPrefix("/") { key.removeFirst() }
        guard let f = entries[name] ?? lower[key.lowercased()].flatMap({ entries[$0] }) else { return Data() }
        let o = f.offset + 30 + u16(f.offset + 26) + u16(f.offset + 28)
        guard o <= bytes.count else { return Data() }
        let d = Array(bytes[o..<Swift.min(bytes.count, o + f.size)])
        if f.method == 0 { return Data(d) }
        if f.method != 8 { throw Failure.inflate }
        guard let out = Inflate.raw(d) else { throw Failure.inflate }
        return Data(out)
    }

    /// Eintrag als UTF-8-Text (XML)
    func text(_ name: String) throws -> String { String(decoding: try data(name), as: UTF8.self) }
}

/// Deflate entpacken (RFC 1951, ohne zlib-Kopf), nach dem Referenz-Decoder «puff».
enum Inflate {
    private struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        init(_ lengths: [Int]) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for l in lengths { count[l] += 1 }
            var offs = [Int](repeating: 0, count: 16)
            for i in 1..<15 { offs[i + 1] = offs[i] + count[i] }
            for (s, l) in lengths.enumerated() where l != 0 {
                symbol[offs[l]] = s
                offs[l] += 1
            }
        }
    }

    private struct Reader {
        let src: [UInt8]
        var pos = 0
        var bitBuf = 0
        var bitCnt = 0
        var failed = false

        init(_ s: [UInt8]) { src = s }

        mutating func bits(_ need: Int) -> Int {
            var val = bitBuf
            while bitCnt < need {
                if pos >= src.count {
                    failed = true
                    return 0
                }
                val |= Int(src[pos]) << bitCnt
                pos += 1
                bitCnt += 8
            }
            bitBuf = val >> need
            bitCnt -= need
            return val & ((1 << need) - 1)
        }

        mutating func decode(_ h: Huffman) -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= bits(1)
                if failed { return -1 }
                let count = h.count[len]
                if code - count < first { return h.symbol[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            return -1
        }
    }

    private static let lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                4097, 6145, 8193, 12289, 16385, 24577]
    private static let dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static let fixed: (Huffman, Huffman) = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        return (Huffman(l), Huffman([Int](repeating: 5, count: 30)))
    }()

    /// Entpackt; nil bei beschädigten Daten. Höchstens 200 MB Ausgabe (Schutz vor «ZIP-Bomben»).
    static func raw(_ src: [UInt8]) -> [UInt8]? {
        var r = Reader(src)
        var out: [UInt8] = []
        out.reserveCapacity(src.count * 4)
        let maxOut = 200_000_000
        var last = 0
        repeat {
            last = r.bits(1)
            let type = r.bits(2)
            if r.failed { return nil }
            switch type {
            case 0:
                // gespeichert: auf Byte-Grenze, Länge + Einerkomplement
                r.bitBuf = 0
                r.bitCnt = 0
                guard r.pos + 4 <= src.count else { return nil }
                let len = Int(src[r.pos]) | Int(src[r.pos + 1]) << 8
                let nlen = Int(src[r.pos + 2]) | Int(src[r.pos + 3]) << 8
                if len != (~nlen & 0xFFFF) { return nil }
                r.pos += 4
                guard r.pos + len <= src.count else { return nil }
                out.append(contentsOf: src[r.pos..<(r.pos + len)])
                r.pos += len
            case 1:
                if !codes(&r, &out, fixed.0, fixed.1, maxOut) { return nil }
            case 2:
                let nlen = r.bits(5) + 257, ndist = r.bits(5) + 1, ncode = r.bits(4) + 4
                if r.failed || nlen > 286 || ndist > 30 { return nil }
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var lengths = [Int](repeating: 0, count: 19)
                for i in 0..<ncode { lengths[order[i]] = r.bits(3) }
                let lencode = Huffman(lengths)
                var ll = [Int](repeating: 0, count: nlen + ndist)
                var idx = 0
                while idx < nlen + ndist {
                    let sym = r.decode(lencode)
                    if sym < 0 { return nil }
                    if sym < 16 {
                        ll[idx] = sym
                        idx += 1
                    } else {
                        var len = 0, rep = 0
                        if sym == 16 {
                            if idx == 0 { return nil }
                            len = ll[idx - 1]
                            rep = 3 + r.bits(2)
                        } else if sym == 17 {
                            rep = 3 + r.bits(3)
                        } else {
                            rep = 11 + r.bits(7)
                        }
                        if idx + rep > nlen + ndist { return nil }
                        for _ in 0..<rep {
                            ll[idx] = len
                            idx += 1
                        }
                    }
                }
                if ll[256] == 0 { return nil }
                if !codes(&r, &out, Huffman(Array(ll[0..<nlen])), Huffman(Array(ll[nlen...])), maxOut) { return nil }
            default:
                return nil
            }
            if out.count > maxOut { return nil }
        } while last == 0
        return out
    }

    private static func codes(_ r: inout Reader, _ out: inout [UInt8], _ lencode: Huffman, _ distcode: Huffman, _ maxOut: Int) -> Bool {
        while true {
            var sym = r.decode(lencode)
            if sym < 0 { return false }
            if sym < 256 {
                out.append(UInt8(sym))
            } else if sym == 256 {
                return true
            } else {
                sym -= 257
                if sym >= 29 { return false }
                let len = lbase[sym] + r.bits(lext[sym])
                let ds = r.decode(distcode)
                if ds < 0 || ds >= 30 { return false }
                let dist = dbase[ds] + r.bits(dext[ds])
                if r.failed || dist > out.count { return false }
                let start = out.count - dist
                for k in 0..<len { out.append(out[start + k]) }
                if out.count > maxOut { return false }
            }
        }
    }
}

// MARK: - Tabellen (xlsx, ods) → CSV-Text für den Leser

enum BankSheets {
    static let rxPrefix = BRX("<(/?)[A-Za-z][\\w.-]*:(?=[A-Za-z])")
    static let rxNumEntity = BRX("&#(\\d+);")

    /// XML-Entitäten (Web `x`)
    static func unescape(_ t: String) -> String {
        var s = t.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        s = rxNumEntity.replaceAll(s) { m in
            guard let c = Int(m.s(1)), let u = UnicodeScalar(UInt32(c & 0xFFFF)) else { return "" }
            return String(Character(u))
        }
        return s.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Zelle für CSV mit «;» (Web: Anführungszeichen bei ; " Zeilenumbruch)
    static let rxNeedsQuote = BRX("[;\"\\n]")
    static func csvCell(_ v: String) -> String {
        rxNeedsQuote.test(v) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    static let rxRow = BRX("<row[^>]*>[\\s\\S]*?</row>|<row[^>]*/>")
    static let rxCell = BRX("<c [^>]*?(/>|>[\\s\\S]*?</c>)")
    static let rxCellRef = BRX(" r=\"([A-Z]+\\d+)\"")
    static let rxCellType = BRX(" t=\"(\\w+)\"")
    static let rxCellV = BRX("<v>([\\s\\S]*?)</v>")
    static let rxCellT = BRX("<t[^>]*>([\\s\\S]*?)</t>")
    static let rxSI = BRX("<si>[\\s\\S]*?</si>")
    static let rxSIT = BRX("<t[^>]*>[\\s\\S]*?</t>")
    static let rxTag = BRX("<[^>]+>")
    static let rxTarget = BRX("Target=\"([^\"]+)\"")
    static let rxSheetName = BRX("^xl/worksheets/[^/]+\\.xml$", i: true)
    static let rxNonDigit = BRX("\\D")
    static let rxHeadGuess = BRX("buchung|datum|valuta|date", i: true)
    static let rxDateHead = BRX("datum|tag|valuta|wert$|^wert|date", i: true)
    static let rxSerial = BRX("^\\d{5}(\\.\\d+)?$")
    static let rxDigits = BRX("\\d")

    /// Spaltennummer aus «AB12» (Web `col`)
    static func column(_ ref: String) -> Int {
        var v = 0
        for u in rxDigits.replaceAll(ref, "").unicodeScalars { v = v * 26 + Int(u.value) - 64 }
        return v - 1
    }

    /// Excel-Seriennummer → TT.MM.JJJJ (Tage seit 30.12.1899)
    static func serialDate(_ v: String) -> String {
        let d = Day(1899, 12, 30).addingDays(Int((Double(v) ?? 0).rounded(.down)))
        return String(format: "%02d.%02d.%d", d.day, d.month, d.year)
    }

    /// Zeilen (Lücken = nil) → CSV-Text mit Datumsumwandlung in Datumsspalten (Web, Ende von `xlsxTexts`)
    static func csvText(_ rows: [[String?]]) -> String {
        var hi = rows.firstIndex { r in r.count >= 3 && BankReader.head(r.map { $0 ?? "" }).ok } ?? -1
        if hi < 0 { hi = rows.firstIndex { r in r.contains { v in v.map { rxHeadGuess.test($0) } ?? false } } ?? -1 }
        var dc = Set<Int>()
        if hi >= 0 {
            for (i, v) in rows[hi].enumerated() where v != nil && rxDateHead.test(v ?? "") { dc.insert(i) }
        }
        return rows.enumerated().map { ri, r in
            r.indices.map { i -> String in
                var v = r[i] ?? ""
                if ri > hi && dc.contains(i) && rxSerial.test(v) { v = serialDate(v) }
                return csvCell(v)
            }.joined(separator: ";")
        }.joined(separator: "\n")
    }

    /// xlsx → je Tabellenblatt ein CSV-Text (Reihenfolge wie in der Mappe), Web `xlsxTexts`
    static func xlsx(_ z: ZipArchive) throws -> [String] {
        // .NET/OpenXML-SDK schreiben Präfixe (<x:row>, <x:c>) → entfernen
        func get(_ n: String) throws -> String { rxPrefix.replaceAll(try z.text(n), "<$1") }
        let rels = try get("xl/_rels/workbook.xml.rels")
        func tg(_ type: String) -> [String] {
            BRX("<Relationship[^>]*Type=\"[^\"]*" + type + "\"[^>]*>").matches(rels).map { m in
                let t = rxTarget.match(m.s(0))?.s(1) ?? ""
                if t.hasPrefix("/") { return String(t.dropFirst()) }
                return "xl/" + (t.hasPrefix("./") ? String(t.dropFirst(2)) : t)
            }
        }
        let ssN = tg("sharedStrings").first ?? "xl/sharedStrings.xml"
        let sx = try get(ssN)
        let ss: [String] = rxSI.matches(sx).map { si in
            unescape(rxSIT.matches(si.s(0)).map { rxTag.replaceAll($0.s(0), "") }.joined())
        }
        var shs = tg("worksheet")
        if shs.isEmpty {
            shs = BU.sorted(z.names.filter { rxSheetName.test($0) }) { a, b in
                Double((Int(rxNonDigit.replaceAll(a, "")) ?? 0) - (Int(rxNonDigit.replaceAll(b, "")) ?? 0))
            }
        }
        if shs.isEmpty { throw ZipArchive.Failure.notZip }
        var out: [String] = []
        for sh in shs {
            let xml = try get(sh)
            var rows: [[String?]] = []
            for rw in rxRow.matches(xml) {
                var row: [String?] = []
                for cm in rxCell.matches(rw.s(0)) {
                    let c = cm.s(0)
                    let ref = rxCellRef.match(c)?.s(1)
                    let t = rxCellType.match(c)?.s(1) ?? "n"
                    let v = rxCellV.match(c)?.s(1)
                    let val: String
                    if t == "s" {
                        let i = Int(v ?? "") ?? -1
                        val = i >= 0 && i < ss.count ? ss[i] : ""
                    } else if t == "inlineStr" {
                        val = unescape(rxCellT.match(c)?.s(1) ?? "")
                    } else {
                        val = unescape(v ?? "")
                    }
                    if let r = ref {
                        let ci = column(r)
                        if ci >= 0 && ci < 16384 {
                            while row.count <= ci { row.append(nil) }
                            row[ci] = val
                        }
                    } else {
                        row.append(val)
                    }
                }
                rows.append(row)
            }
            out.append(csvText(rows))
        }
        return out
    }

    static let rxTable = BRX("<table [\\s\\S]*?</table>")
    static let rxTableRow = BRX("<table-row[^>]*?(/>|>[\\s\\S]*?</table-row>)")
    static let rxTableCell = BRX("<(table-cell|covered-table-cell)[^>]*?(/>|>[\\s\\S]*?</\\1>)")
    static let rxColRep = BRX("number-columns-repeated=\"(\\d+)\"")
    static let rxRowRep = BRX("number-rows-repeated=\"(\\d+)\"")
    static let rxDateValue = BRX(" date-value=\"([^\"]+)\"")
    static let rxValue = BRX(" value=\"([^\"]+)\"")
    static let rxValueType = BRX("value-type=\"(float|currency|percentage)\"")
    static let rxP = BRX("<p[^>]*>[\\s\\S]*?</p>|<p[^>]*/>")
    static let rxTextS = BRX("<text:s[^>]*/>")

    /// OpenDocument-Tabelle → je Blatt ein CSV-Text; wiederholte Zellen/Zeilen begrenzt (Web `odsTexts`)
    static func ods(_ z: ZipArchive) throws -> [String] {
        let xml = rxPrefix.replaceAll(try z.text("content.xml"), "<$1")
        func x(_ t: String) -> String {
            let s = rxTag.replaceAll(rxTextS.replaceAll(t, " "), "")
            return s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
        }
        var out: [String] = []
        for tb in rxTable.matches(xml) {
            var rows: [[String]] = []
            for rwm in rxTableRow.matches(tb.s(0)) {
                let rw = rwm.s(0)
                var row: [String] = []
                for cm in rxTableCell.matches(rw) {
                    let c = cm.s(0)
                    let rep = Swift.min(Int(rxColRep.match(c)?.s(1) ?? "1") ?? 1, 50)
                    let dv = rxDateValue.match(c)?.s(1)
                    let nv = rxValue.match(c)?.s(1)
                    let tv = rxP.matches(c).map { x($0.s(0)) }.joined(separator: " ")
                    let v: String
                    if let d = dv {
                        v = BU.slice(d, 0, 10)
                    } else if let n = nv, rxValueType.test(c) {
                        v = n
                    } else {
                        v = tv
                    }
                    for _ in 0..<Swift.max(rep, 0) { row.append(v) }
                }
                while let l = row.last, l.isEmpty { row.removeLast() }
                let rr = Swift.min(Int(rxRowRep.match(rw)?.s(1) ?? "1") ?? 1, row.isEmpty ? 1 : 5)
                for _ in 0..<Swift.max(rr, 0) { rows.append(row) }
            }
            out.append(rows.map { r in r.map { csvCell($0) }.joined(separator: ";") }.joined(separator: "\n"))
        }
        return out
    }
}

extension BankReader {
    static let rxXlsxName = BRX("^xl/(workbook\\.xml|worksheets/)", i: true)
    static let rxNumbersName = BRX("^index/|\\.iwa$", i: true)
    static let rxOds = BRX("opendocument\\.spreadsheet")
    static let rxZipStatement = BRX("\\.(xml|txt|sta|940|csv|tsv|mt940|camt)$", i: true)
    static let rxZipJunk = BRX("__macosx|/\\._|^\\._", i: true)

    /// Ein Blatt/Text lesen; Grund bei leerem Ergebnis
    private static func tryRead(_ txt: String) -> (BankFile?, BankReadDiag) {
        do {
            return (try read(text: txt), .none)
        } catch BankReadError.notRecognized(let d) {
            return (nil, d)
        } catch {
            return (nil, .none)
        }
    }

    /// ZIP-Datei: Excel (alle Blätter), camt-Sammlung oder Apple Numbers → Ergebnis oder Grund (Web `bankZip`)
    static func zip(_ data: Data) throws -> BankFile {
        let z: ZipArchive
        do { z = try ZipArchive(data) } catch { throw BankReadError.notRecognized(.zip) }
        if z.names.contains(where: { rxXlsxName.test($0) }) {
            let ts: [String]
            do { ts = try BankSheets.xlsx(z) } catch { throw BankReadError.notRecognized(.xlsxError) }
            var d0 = BankReadDiag.none
            for t in ts {
                let (f, d) = tryRead(t)
                if let f = f { return f }
                if d0 == .none || d == .dateFormat { d0 = d }
            }
            throw BankReadError.notRecognized(d0 == .none ? .noHeader : d0)
        }
        if z.names.contains(where: { rxNumbersName.test($0) }) { throw BankReadError.notRecognized(.numbers) }
        if z.names.contains("content.xml"), rxOds.test((try? z.text("mimetype")) ?? "") {
            let to = (try? BankSheets.ods(z)) ?? []
            var d1 = BankReadDiag.none
            for t in to {
                let (f, d) = tryRead(t)
                if let f = f { return f }
                if d1 == .none || d == .dateFormat { d1 = d }
            }
            throw BankReadError.notRecognized(d1 == .none ? .noHeader : d1)
        }
        // gezippte Exporte: camt/MT940 (XML, STA) oder CSV/TXT
        let xs = z.names.filter { rxZipStatement.test($0) && !rxZipJunk.test($0) }
        var rs: [BankFile] = []
        for n in xs.prefix(200) {
            guard let d = try? z.data(n), let f = try? read(text: decode(d)) else { continue }
            rs.append(f)
        }
        if rs.isEmpty { throw BankReadError.notRecognized(.zip) }
        return rs.count == 1 ? rs[0] : merge(rs)
    }
}
