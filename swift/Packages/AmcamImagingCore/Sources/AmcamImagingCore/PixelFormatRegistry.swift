import Foundation

/// Exact identity of a pixel format carried by a GenTL image buffer.
///
/// Namespace and numeric code are both required. The numeric value alone is
/// not globally unique and must never be treated as a PFNC identifier without
/// its namespace.
public struct PixelFormatIdentifier: Hashable, Sendable {
    public let namespace: UInt64
    public let code: UInt64

    public init(namespace: UInt64, code: UInt64) {
        self.namespace = namespace
        self.code = code
    }

    /// PFNC 32-bit namespace RGB8 packed identifier (0x02180014).
    public static let pfncRGB8 = PixelFormatIdentifier(
        namespace: 4,
        code: 0x02180014
    )
}

/// A decoder implemented by AmcamImagingCore for a registered pixel format.
public enum PixelFormatDecoder: String, Equatable, Sendable {
    case rgb8
}

/// Metadata for an exact pixel-format identity.
///
/// A nil decoder means the format is recognized by metadata but is not yet
/// supported by the image-decoding pipeline.
public struct PixelFormatDescriptor: Equatable, Sendable, Identifiable {
    public let identifier: PixelFormatIdentifier
    public let name: String
    public let decoder: PixelFormatDecoder?

    public var id: PixelFormatIdentifier { identifier }

    public init(
        identifier: PixelFormatIdentifier,
        name: String,
        decoder: PixelFormatDecoder?
    ) {
        self.identifier = identifier
        self.name = name
        self.decoder = decoder
    }
}

public enum PixelFormatRegistryError: Error, Equatable, Sendable {
    case emptyName
    case duplicateIdentifier(PixelFormatIdentifier)
}

/// Immutable lookup for formats whose namespace, identifier and decoder
/// contract have been explicitly registered.
public struct PixelFormatRegistry: Sendable {
    private let descriptorsByIdentifier: [PixelFormatIdentifier: PixelFormatDescriptor]

    public init(descriptors: [PixelFormatDescriptor]) throws {
        var indexed: [PixelFormatIdentifier: PixelFormatDescriptor] = [:]
        for descriptor in descriptors {
            guard !descriptor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PixelFormatRegistryError.emptyName
            }
            guard indexed[descriptor.identifier] == nil else {
                throw PixelFormatRegistryError.duplicateIdentifier(descriptor.identifier)
            }
            indexed[descriptor.identifier] = descriptor
        }
        descriptorsByIdentifier = indexed
    }

    public func descriptor(for identifier: PixelFormatIdentifier) -> PixelFormatDescriptor? {
        descriptorsByIdentifier[identifier]
    }

    /// Intersects camera-advertised PFNC identities with this registry's
    /// implemented decoders. Unknown, mismatched and duplicate identities are
    /// omitted; the camera's first-advertised order is preserved.
    public func decodableFormats(
        advertised identifiers: [PixelFormatIdentifier]
    ) -> [PixelFormatDescriptor] {
        var seen = Set<PixelFormatIdentifier>()
        return identifiers.compactMap { identifier in
            guard seen.insert(identifier).inserted,
                  let descriptor = descriptorsByIdentifier[identifier],
                  descriptor.decoder != nil else {
                return nil
            }
            return descriptor
        }
    }

    /// The initial, deliberately narrow PFNC output registry. New formats are
    /// added only alongside a decoder and independent layout/value tests.
    public static let pfnc: PixelFormatRegistry = {
        do {
            return try PixelFormatRegistry(descriptors: [
                PixelFormatDescriptor(
                    identifier: .pfncRGB8,
                    name: "RGB8",
                    decoder: .rgb8
                )
            ])
        } catch {
            preconditionFailure("The built-in PFNC registry is invalid: \\(error)")
        }
    }()
}
