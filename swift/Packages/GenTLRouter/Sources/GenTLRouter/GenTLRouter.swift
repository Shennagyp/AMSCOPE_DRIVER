        for registration in current {
            let firstDeviceIndex = devices.count
            var api: (any GenTLAPI)?
            var didInitialize = false
            var context: GenTLProviderContext?

            do {
                let createdAPI = try registration.makeAPI()
                api = createdAPI
                try createdAPI.GCInitLib()
                didInitialize = true

                let system = try createdAPI.TLOpen()
                let providerContext = GenTLProviderContext(
                    backendID: registration.identifier,
                    api: createdAPI,
                    systemHandle: system
                )
                context = providerContext

                do {
                    try createdAPI.TLUpdateInterfaceList(system, timeout: timeout)
                    let interfaceCount = try createdAPI.TLGetNumInterfaces(system)

                    for interfaceIndex in 0..<interfaceCount {
                        let interfaceID = try createdAPI.TLGetInterfaceID(system, index: interfaceIndex)
                        let interfaceHandle = try createdAPI.TLOpenInterface(system, interfaceID: interfaceID)
                        providerContext.addInterface(id: interfaceID, handle: interfaceHandle)

                        try createdAPI.IFUpdateDeviceList(interfaceHandle, timeout: timeout)
                        let deviceCount = try createdAPI.IFGetNumDevices(interfaceHandle)

                        for deviceIndex in 0..<deviceCount {
                            let deviceID = try createdAPI.IFGetDeviceID(interfaceHandle, index: deviceIndex)
                            devices.append(try GenTLDeviceCandidate(
                                backendID: registration.identifier,
                                interfaceID: interfaceID,
                                deviceID: deviceID,
                                context: providerContext
                            ))
                        }
                    }

                    if devices.count == firstDeviceIndex {
                        providerContext.close()
                    }
                } catch {
                    devices.removeSubrange(firstDeviceIndex..<devices.count)
                    providerContext.close()
                    throw error
                }
            } catch {
                devices.removeSubrange(firstDeviceIndex..<devices.count)
                if let context {
                    context.close()
                } else if didInitialize, let api {
                    try? api.GCCloseLib()
                }
                failures.append(GenTLProviderFailure(
                    backendID: registration.identifier,
                    message: error.localizedDescription
                ))
            }
        }