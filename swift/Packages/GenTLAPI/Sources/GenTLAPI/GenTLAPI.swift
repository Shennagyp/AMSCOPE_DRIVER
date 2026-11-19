/// Swift interface following the GenTL 1.6 function groups.
///
/// Both implementations expose this same interface:
/// - GenTLNative forwards operations to manufacturer CTI Producers.
/// - AmcamGenTL maps supported operations to the Amcam SDK.
public protocol GenTLAPI:
    GenTLLibraryFunctions,
    GenTLSystemFunctions,
    GenTLInterfaceFunctions,
    GenTLDeviceFunctions,
    GenTLDataStreamFunctions,
    GenTLAdvancedDataFunctions,
    GenTLPortFunctions,
    GenTLSignalingFunctions
{
    /// GenTL revision represented by this Swift API contract. For GenTLNative,
    /// this is not a promise that every loaded .cti Producer implements that revision;
    /// query GCGetInfo/TL_INFO_GENTL_VER_MAJOR and MINOR for the Producer's own version.
    var genTLVersion: GenTLVersion { get }
}
