import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ein Foto oder Dokument, das der Nutzer ATLAS zur Analyse gibt.
struct Attachment: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case image, pdf }

    let id = UUID()
    let kind: Kind
    let name: String
    let data: Data
    let mediaType: String

    var contentPart: ContentPart {
        switch kind {
        case .image: return .image(data: data, mediaType: mediaType)
        case .pdf: return .pdf(data: data, name: name)
        }
    }

    var symbol: String { kind == .image ? "photo" : "doc.richtext" }

    /// Maximale PDF-Größe, die an Claude geschickt wird (API-Grenze 32 MB pro Anfrage).
    static let maxPDFBytes = 24 * 1024 * 1024

    /// Bild aus beliebigen Bilddaten (HEIC, PNG, JPEG …): verkleinert auf max. 1568 px
    /// (Claudes optimale Größe) und als JPEG neu kodiert – spart Zeit und Kosten.
    static func image(from data: Data, name: String = "Foto") -> Attachment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1568,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Attachment(kind: .image, name: name, data: output as Data, mediaType: "image/jpeg")
    }

    /// PDF aus einer vom Nutzer gewählten Datei.
    static func pdf(at url: URL) -> Attachment? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= maxPDFBytes else { return nil }
        return Attachment(kind: .pdf, name: url.deletingPathExtension().lastPathComponent, data: data,
                          mediaType: "application/pdf")
    }

    /// Bild aus einer vom Nutzer gewählten Datei.
    static func image(at url: URL) -> Attachment? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return image(from: data, name: url.deletingPathExtension().lastPathComponent)
    }
}
