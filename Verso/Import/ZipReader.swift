import Foundation

/// A small reader for zip files (EPUBs are zip files). Supports stored and
/// deflated entries, which covers every EPUB in practice. No third-party code.
struct ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedMethod(UInt16)
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file is not a zip archive."
            case .unsupportedMethod(let m): return "Unsupported zip compression method \(m)."
            case .corrupt: return "The archive is damaged."
            }
        }
    }

    let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name } ?? entries.first { $0.name.lowercased() == name.lowercased() }
    }

    func contents(of name: String) throws -> Data {
        guard let entry = entry(named: name) else { throw ZipError.corrupt }
        return try contents(of: entry)
    }

    func contents(of entry: Entry) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, u32(at: base) == 0x04034b50 else { throw ZipError.corrupt }
        let nameLength = Int(u16(at: base + 26))
        let extraLength = Int(u16(at: base + 28))
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corrupt }
        let raw = data.subdata(in: start..<end)
        switch entry.method {
        case 0:
            return raw
        case 8:
            let inflated = try (raw as NSData).decompressed(using: .zlib) as Data
            return inflated
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    // MARK: Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipError.notAZip }
        // Find the End of Central Directory record, scanning back over a possible comment.
        var eocd = -1
        let minIndex = max(0, data.count - 22 - 65_535)
        var i = data.count - 22
        while i >= minIndex {
            if data.u32(at: i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(data.u16(at: eocd + 10))
        let cdOffset = Int(data.u32(at: eocd + 16))
        var entries: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(at: p) == 0x02014b50 else { throw ZipError.corrupt }
            let method = data.u16(at: p + 10)
            let compressed = Int(data.u32(at: p + 20))
            let uncompressed = Int(data.u32(at: p + 24))
            let nameLength = Int(data.u16(at: p + 28))
            let extraLength = Int(data.u16(at: p + 30))
            let commentLength = Int(data.u16(at: p + 32))
            let localOffset = Int(data.u32(at: p + 42))
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private func u16(at offset: Int) -> UInt16 { data.u16(at: offset) }
    private func u32(at offset: Int) -> UInt32 { data.u32(at: offset) }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    func u32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | (UInt32(self[i + 1]) << 8) | (UInt32(self[i + 2]) << 16) | (UInt32(self[i + 3]) << 24)
    }
}
