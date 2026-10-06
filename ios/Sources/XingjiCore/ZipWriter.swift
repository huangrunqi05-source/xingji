import Foundation
/// Small, streaming, uncompressed ZIP writer. Each attachment is released after writing.
public final class ZipWriter {
    private struct Entry { var name: Data; var crc: UInt32; var size: UInt32; var offset: UInt32 }
    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private var closed = false
    public init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
    }
    deinit { try? handle.close() }
    public func add(name: String, data: Data) throws {
        let filename = Data(name.utf8)
        guard !closed, !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), filename.count <= 65_535,
              data.count < Int(UInt32.max), offset + UInt64(data.count) + UInt64(filename.count) + 30 < UInt64(UInt32.max), entries.count < 65_535 else { throw CocoaError(.fileWriteInvalidFileName) }
        let crc = Self.crc32(data), size = UInt32(data.count)
        var header = Data(); header.le(UInt32(0x04034b50)); header.le(UInt16(20)); header.le(UInt16(0x800)); header.le(UInt16(0))
        header.le(UInt16(0)); header.le(UInt16(0x21)); header.le(crc); header.le(size); header.le(size); header.le(UInt16(filename.count)); header.le(UInt16(0)); header.append(filename)
        entries.append(Entry(name: filename, crc: crc, size: size, offset: UInt32(offset)))
        try write(header); try write(data)
    }
    public func finish() throws {
        guard !closed else { return }
        let centralOffset = offset
        for entry in entries {
            var h = Data(); h.le(UInt32(0x02014b50)); h.le(UInt16(20)); h.le(UInt16(20)); h.le(UInt16(0x800)); h.le(UInt16(0))
            h.le(UInt16(0)); h.le(UInt16(0x21)); h.le(entry.crc); h.le(entry.size); h.le(entry.size)
            h.le(UInt16(entry.name.count)); h.le(UInt16(0)); h.le(UInt16(0)); h.le(UInt16(0)); h.le(UInt16(0)); h.le(UInt32(0)); h.le(entry.offset); h.append(entry.name)
            try write(h)
        }
        guard offset < UInt64(UInt32.max) else { throw CocoaError(.fileWriteOutOfSpace) }
        var end = Data(); end.le(UInt32(0x06054b50)); end.le(UInt16(0)); end.le(UInt16(0)); end.le(UInt16(entries.count)); end.le(UInt16(entries.count)); end.le(UInt32(offset-centralOffset)); end.le(UInt32(centralOffset)); end.le(UInt16(0))
        try write(end); try handle.close(); closed = true
    }
    private func write(_ data: Data) throws { try handle.write(contentsOf: data); offset += UInt64(data.count) }
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ number: T) { var value = number.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } }
}
