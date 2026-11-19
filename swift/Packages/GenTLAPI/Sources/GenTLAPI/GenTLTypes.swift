import Foundation

public struct GenTLPortReadRequest: Sendable, Equatable {
    public let address: UInt64
    public let size: Int

    public init(address: UInt64, size: Int) {
        self.address = address
        self.size = size
    }
}

public struct GenTLPortWriteRequest: Sendable, Equatable {
    public let address: UInt64
    public let data: Data

    public init(address: UInt64, data: Data) {
        self.address = address
        self.data = data
    }
}

public struct GenTLChunkData: Sendable, Equatable {
    public let chunkID: UInt64
    public let offset: Int64
    public let length: Int

    public init(chunkID: UInt64, offset: Int64, length: Int) {
        self.chunkID = chunkID
        self.offset = offset
        self.length = length
    }
}

public struct GenTLCompositeBufferSegment: @unchecked Sendable {
    public let memory: GenTLBufferMemory

    public init(memory: GenTLBufferMemory) {
        self.memory = memory
    }
}
