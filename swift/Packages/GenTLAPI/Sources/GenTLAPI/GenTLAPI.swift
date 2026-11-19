/// Swift-facing GenTL 1.6 API surface.
///
/// Method names and module boundaries follow the GenTL C API. Implementations
/// are interchangeable: one forwards to a real GenTL Producer through its C
/// interface; another can translate the same operations to a proprietary SDK.
public protocol GenTLAPI:
    GenTLLibraryFunctions,
    GenTLSystemFunctions,
    GenTLInterfaceFunctions,
    GenTLDeviceFunctions,
    GenTLDataStreamFunctions,
    GenTLPortFunctions,
    GenTLSignalingFunctions
{
    var genTLVersion: GenTLVersion { get }
}
