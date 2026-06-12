import Foundation

@inline(__always)
func debugLog(_ message: String) {
#if DEBUG
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
#endif
}
