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
    var genTLVersion: GenTLVersion { get }
}
