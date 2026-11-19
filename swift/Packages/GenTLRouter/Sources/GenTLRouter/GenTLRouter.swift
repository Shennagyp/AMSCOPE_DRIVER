            } catch GenTLRouterError.duplicateBackendID(_) {
                // Another concurrent discovery call registered this producer
                // after the initial backendIDs snapshot.
                alreadyRegistered.append(backendID)
            } catch {