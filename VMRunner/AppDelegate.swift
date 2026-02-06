/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app delegate that sets up and starts the virtual machine.
*/

import Cocoa
import Foundation
import Virtualization

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!

    @IBOutlet weak var virtualMachineView: VZVirtualMachineView!

    private var virtualMachineResponder: MacOSVirtualMachineDelegate?

    private var virtualMachine: VZVirtualMachine!
    
    private var selectedVMBundleURL: URL?

    // MARK: Create the Mac platform configuration.

    private func createMacPlaform() -> VZMacPlatformConfiguration {
        guard let vmBundleURL = selectedVMBundleURL else {
            fatalError("VM bundle URL not set.")
        }
        
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorageURL = vmBundleURL.appendingPathComponent("AuxiliaryStorage")
        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

        if !FileManager.default.fileExists(atPath: vmBundleURL.path) {
            fatalError("Missing Virtual Machine Bundle at \(vmBundleURL.path). Run InstallationTool first to create it.")
        }

        // Retrieve the hardware model and save this value to disk
        // during installation.
        let hardwareModelURL = vmBundleURL.appendingPathComponent("HardwareModel")
        guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
            fatalError("Failed to retrieve hardware model data.")
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            fatalError("Failed to create hardware model.")
        }

        if !hardwareModel.isSupported {
            fatalError("The hardware model isn't supported on the current host")
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier and save this value to disk
        // during installation.
        let machineIdentifierURL = vmBundleURL.appendingPathComponent("MachineIdentifier")
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            fatalError("Failed to retrieve machine identifier data.")
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            fatalError("Failed to create machine identifier.")
        }
        macPlatform.machineIdentifier = machineIdentifier

        return macPlatform
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    private func createVirtualMachine() {
        guard let vmBundleURL = selectedVMBundleURL else {
            fatalError("VM bundle URL not set.")
        }
        
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()
        
        virtualMachineConfiguration.platform = createMacPlaform()
        virtualMachineConfiguration.bootLoader = MacOSVirtualMachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.cpuCount = MacOSVirtualMachineConfigurationHelper.computeCPUCount()
        virtualMachineConfiguration.memorySize = MacOSVirtualMachineConfigurationHelper.computeMemorySize()

        virtualMachineConfiguration.audioDevices = [MacOSVirtualMachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MacOSVirtualMachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MacOSVirtualMachineConfigurationHelper.createNetworkDeviceConfiguration()]
        
        let diskImageURL = vmBundleURL.appendingPathComponent("Disk.img")
        virtualMachineConfiguration.storageDevices = [MacOSVirtualMachineConfigurationHelper.createBlockDeviceConfiguration(diskImageURL: diskImageURL)]

//        virtualMachineConfiguration.pointingDevices = [MacOSVirtualMachineConfigurationHelper.createPointingDeviceConfiguration()]
//        virtualMachineConfiguration.keyboards = [MacOSVirtualMachineConfigurationHelper.createKeyboardConfiguration()]
        // ✅ Force input devices that Monterey reliably recognizes
            virtualMachineConfiguration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
            virtualMachineConfiguration.keyboards = [VZUSBKeyboardConfiguration()]
        
//        let sharedFolderURL = FileManager.default.homeDirectoryForCurrentUser
//            .appendingPathComponent("VMShare", isDirectory: true)
//
//        // Make sure it exists
//        try? FileManager.default.createDirectory(at: sharedFolderURL, withIntermediateDirectories: true)
//
//         // Attach to VM
//        virtualMachineConfiguration.directorySharingDevices = [
//            createDirectorySharingDevice(hostFolderURL: sharedFolderURL)
//        ]
        
        try! virtualMachineConfiguration.validate()
        try! virtualMachineConfiguration.validateSaveRestoreSupport()

        virtualMachine = VZVirtualMachine(configuration: virtualMachineConfiguration)
    }

    private func createDirectorySharingDevice(hostFolderURL: URL) -> VZVirtioFileSystemDeviceConfiguration {
        let sharedDirectory = VZSharedDirectory(url: hostFolderURL, readOnly: false)
        let share = VZSingleDirectoryShare(directory: sharedDirectory)

        let fs = VZVirtioFileSystemDeviceConfiguration(tag: "share")
        fs.share = share
        return fs
    }
    
    // MARK: Start or restore the virtual machine.

    func startVirtualMachine() {
        virtualMachine.start(completionHandler: { (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to start with \(error)")
            }
        })
    }

    func resumeVirtualMachine() {
        virtualMachine.resume(completionHandler: { (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to resume with \(error)")
            }
        })
    }

    func restoreVirtualMachine() {
        guard let vmBundleURL = selectedVMBundleURL else {
            fatalError("VM bundle URL not set.")
        }
        let saveFileURL = vmBundleURL.appendingPathComponent("SaveFile.vzvmsave")
        
        virtualMachine.restoreMachineStateFrom(url: saveFileURL, completionHandler: { [self] (error) in
            // Remove the saved file. Whether success or failure, the state no longer matches the VM's disk.
            let fileManager = FileManager.default
            try! fileManager.removeItem(at: saveFileURL)

            if error == nil {
                self.resumeVirtualMachine()
            } else {
                self.startVirtualMachine()
            }
        })
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Show open panel to select VM bundle
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Virtual Machine Bundle"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.canCreateDirectories = false
        openPanel.message = "Please select the Virtual Machine bundle folder (VM.bundle)"
        
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let selectedURL = openPanel.url {
                self.selectedVMBundleURL = selectedURL
                self.setupAndStartVirtualMachine()
            } else {
                // User cancelled, terminate the app
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func setupAndStartVirtualMachine() {
        DispatchQueue.main.async { [self] in
            createVirtualMachine()
            virtualMachineResponder = MacOSVirtualMachineDelegate()
            virtualMachine.delegate = virtualMachineResponder
            virtualMachineView.virtualMachine = virtualMachine
            virtualMachineView.capturesSystemKeys = true
            
            // ✅ Ensure the window + VM view are ready to receive input
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(virtualMachineView)
            // Configure the app to automatically respond to changes in the display size.
            virtualMachineView.automaticallyReconfiguresDisplay = true

            guard let vmBundleURL = selectedVMBundleURL else {
                fatalError("VM bundle URL not set.")
            }
            let saveFileURL = vmBundleURL.appendingPathComponent("SaveFile.vzvmsave")
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: saveFileURL.path) {
                restoreVirtualMachine()
            } else {
                startVirtualMachine()
            }
        }
    }

    // MARK: Save the virtual machine when the app exits.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func saveVirtualMachine(completionHandler: @escaping () -> Void) {
        guard let vmBundleURL = selectedVMBundleURL else {
            fatalError("VM bundle URL not set.")
        }
        let saveFileURL = vmBundleURL.appendingPathComponent("SaveFile.vzvmsave")
        
        virtualMachine.saveMachineStateTo(url: saveFileURL, completionHandler: { (error) in
            guard error == nil else {
                fatalError("Virtual machine failed to save with \(error!)")
            }

            completionHandler()
        })
    }

    func pauseAndSaveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.pause(completionHandler: { (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to pause with \(error)")
            }

            self.saveVirtualMachine(completionHandler: completionHandler)
        })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if virtualMachine.state == .running {
            pauseAndSaveVirtualMachine(completionHandler: {
                sender.reply(toApplicationShouldTerminate: true)
            })
            return .terminateLater
        }
        return .terminateNow
    }
}
