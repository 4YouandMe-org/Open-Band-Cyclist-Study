//
//  OpenBandBleRecorder.swift
//  OpenBandCylist
//
//  Copyright © 2020 4YouandMe. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import UIKit
import Research
import ResearchUI
import ResearchMotion
import CoreBluetooth
import RxSwift

/// The configuration for the heart rate recorder.
public struct OpenBandBleRecorderConfiguration : RSDRecorderConfiguration, RSDAsyncActionVendor, Codable {

    /// A unique string used to identify the recorder.
    public let identifier: String
    
    /// The step used to mark when we should connect the user to the BLE peripheral.
    public var connectionStepIdentifier: String?
    
    /// The step used to mark when to start the recorder.
    public var startStepIdentifier: String?
    
    /// The step used to mark when to stop the recorder and also disconnect the BLE peripheral.
    public var stopStepIdentifier: String?
    
    /// Default initializer.
    /// - parameter identifier: A unique string used to identify the recorder.
    public init(identifier: String) {
        self.identifier = identifier
    }
    
    // TODO: mdephillips 10/22/20 add BT permission for iOS 13
    /// This recorder requires permission to use the camera.
    public var permissionTypes: [RSDPermissionType] {
        return []//[RSDStandardPermissionType.bluetooth]
    }
    
    /// This recorder does not require background audio
    public var requiresBackgroundAudio: Bool {
        return false
    }
    
    /// No validation required.
    public func validate() throws {
        // TODO: syoung 11/16/2017 Decide if we want validation to include checking the plist for required privacy alerts.
        // The value of these keys change from time to time so they can't be relied upon to be the same but it's confusing
        // for "researchers who write code" to have to manage that stuff when setting up a project.
    }
    
    /// Instantiate a `RSDDistanceRecorder` (iOS only).
    /// - parameter taskViewModel: The current task path to use to initialize the controller.
    /// - returns: A new instance of `RSDDistanceRecorder` or `nil` if the platform does not
    ///            support distance recording.
    public func instantiateController(with taskViewModel: RSDPathComponent) -> RSDAsyncAction? {
        return OpenBandBleRecorder(configuration: self, taskViewModel: taskViewModel, outputDirectory: taskViewModel.outputDirectory)
    }
}

public protocol OpenBandBleRecorderDelegate: class {
    func onConnectionChange(recorder: OpenBandBleRecorder)
}

public class OpenBandBleRecorder : RSDSampleRecorder, CBPeripheralDelegate, CBCentralManagerDelegate {

    public enum OpenBandBleRecorderError : Error {
        case permissionIssue(CBManagerState)
    }
    
    public var openBandBleConfiguration : OpenBandBleRecorderConfiguration? {
        return self.configuration as? OpenBandBleRecorderConfiguration
    }
    
    // ECG Sensor info
    // Input impedance = 2 MΩ (with moistened ProStrap)
    // Bandwidth = 0.7 - 40 Hz (with moistened ProStrap)
    // Dynamic input range = +- 20 000 µV
    // Sample rate = 130 Hz ± 2 % (Tamb = +20 … +40 °C)
    // 130 Hz ± 5 % (Tamb = -20 … +70 °C)
    // Accurate timestamps of samples available
    // Assuming 130 Hz, we can accurately calculate the timestamp of each sample in the array
    let timeBetweenSamples = TimeInterval(1.0 / 130.0)
    
    public var isConnected: Bool {
        guard let peripheralUnwrapped = self.peripheral else {
            return false
        }
        return peripheralUnwrapped.state == CBPeripheralState.connected
    }
    weak var openBandDelegate: OpenBandBleRecorderDelegate?
    
    // The central BT manager, used to manage permission requests
    // Properties
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    
    // Characteristics
    private var ppgChar: CBCharacteristic?
    private var accChar: CBCharacteristic?
    private var gyroChar: CBCharacteristic?
    private var magChar: CBCharacteristic?
    
    var permissionCompletion: RSDAsyncActionCompletionHandler?
    
    // The BLE connection can be running without writing to the logger
    // When isRecording is true, samples from the BLE device will be logged
    var isRecording = false
    
    // The CB manager cannot scan for peripherals right after it is instantiated
    // so we must set this to true to signal a scan after it is ready
    var shouldStartScanning = false
    
    deinit {
        // TODO: mdephillips 10/23/20 do we need to de-allocate anything?
    }
    
    public override func requestPermissions(on viewController: UIViewController, _ completion: @escaping RSDAsyncActionCompletionHandler) {
        
        // We only need to request bluetooth permission on iOS 13 or later
        guard #available(iOS 13, *) else {
            completion(self, nil, nil)
            return
        }
        
        // Creating the bluetooth manager will trigger requesting the permission
        if self.centralManager == nil {
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        self.centralManager?.delegate = self
        
        switch self.centralManager?.authorization {
        case .allowedAlways:
            if self.centralManager?.state == CBManagerState.poweredOff {
                completion(self, nil, OpenBandBleRecorderError.permissionIssue(CBManagerState.poweredOff))
            } else {
                completion(self, nil, nil)
            }
        case .denied, .restricted:
            completion(self, nil, OpenBandBleRecorderError.permissionIssue(.unauthorized))
        default: // Not determined
            // When the permission is not determined, the central manager creation
            // triggers the permission request, and will be shown at this point
            // Now we just need to wait for the delegate to communicate the change in permission
            self.permissionCompletion = completion
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Central is not powered on")
        } else {
            print("Central scanning for Open Band Devices");
            if self.shouldStartScanning {
                self.centralManager?.scanForPeripherals(withServices: [],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
            }
        }
        self.shouldStartScanning = false
        
        // TODO: mdephillips 10/22/20 handle permission on iOS 13
//        switch self.centralManager?.authorization {
//        case .allowedAlways:
//            if self.centralManager?.state == CBManagerState.poweredOff {
//                self.permissionCompletion?(self, nil, OpenBandBleRecorderError.permissionIssue(CBManagerState.poweredOff))
//            } else {
//                self.permissionCompletion?(self, nil, nil)
//            }
//        case .denied, .restricted:
//            self.permissionCompletion?(self, nil, OpenBandBleRecorderError.permissionIssue(.unauthorized))
//        default: // Not determined
//            break
//        }
    }
    
    public override func startRecorder(_ completion: @escaping ((RSDAsyncActionStatus, Error?) -> Void)) {
        guard peripheral != nil else {
            completion(.failed, nil)
            return
        }
        
        self.isRecording = true
        
        // TODO: mdephillips 10/22/20 handle error states on starting up acc and ecg
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        self.isRecording = false
        self.disconnectFromDevice()
        super.stopRecorder(completion)
    }
    
    public func disconnectFromDevice() {
        guard let peripheralUnwrapped = peripheral else { return }
        self.centralManager?.cancelPeripheralConnection(peripheralUnwrapped)
    }
    
    public func autoConnectBleDevice() {
        self.shouldStartScanning = true
        if self.centralManager == nil {
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        self.centralManager?.delegate = self
        self.centralManager?.scanForPeripherals(withServices: [],
                                                     options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    }
    
    // Handles the result of the scan
        public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
                                    
            print("Found peripheral \(peripheral)")
            if peripheral.name == "Open Health Band" {
                // We've found it so stop scan
                self.centralManager?.stopScan()
                
                // Copy the peripheral instance
                self.peripheral = peripheral
                
                self.peripheral?.delegate = self
                self.centralManager?.connect(peripheral, options: nil)
            }
        }
        
        // The handler if we do connect succesfully
        public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            if peripheral == self.peripheral {
                print("Connected to your Open Band")
                peripheral.discoverServices([])
                self.openBandDelegate?.onConnectionChange(recorder: self)
            }
        }
        
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            if peripheral == self.peripheral {
                print("Disconnected")
                
                self.peripheral = nil
                self.openBandDelegate?.onConnectionChange(recorder: self)
                
                // Start scanning again
//                print("Central scanning for \(OpenBandPeripheral.timestampService) and \(OpenBandPeripheral.imuService)");
//                self.centralManager?.scanForPeripherals(withServices: [OpenBandPeripheral.timestampService, OpenBandPeripheral.imuService],
//                                                  options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
            }
        }
        
        // Handles discovery event
        public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            if let services = peripheral.services {
                for service in services {
                    print("Did discover service \(service)")
                    peripheral.discoverCharacteristics([], for: service)
    //                if service.uuid == OpenBandPeripheral.timestampService {
    //                    print("LED service found")
    //                    //Now kick off discovery of characteristics
    //                    peripheral.discoverCharacteristics([OpenBandPeripheral.ppgCharacteristic], for: service)
    //                }
    //                if( service.uuid == OpenBandPeripheral.imuService) {
    //                    print("Battery service found")
    //                    peripheral.discoverCharacteristics([OpenBandPeripheral.accCharacteristic, OpenBandPeripheral.gyroCharacteristic, OpenBandPeripheral.magCharacteristic], for: service)
    //                }
                }
            }
        }
        
        public func peripheral(_ peripheral: CBPeripheral,
                         didUpdateNotificationStateFor characteristic: CBCharacteristic,
                         error: Error?) {
            print("Enabling notify ", characteristic.uuid)
            
            if error != nil {
                print("Enable notify error")
            }
        }

        public func peripheral(_ peripheral: CBPeripheral,
                         didUpdateValueFor characteristic: CBCharacteristic,
                         error: Error?) {
            
            // Only write samples when we are recording
            guard self.isRecording else { return }
            
            if let data = characteristic.value {
                let values = [UInt8](data)
                
                // TODO: mdephillips 10/22/20 figure out a more efficient way to convert these values
                if characteristic == ppgChar {
                    // Values come through in little endian format
                    // timestamp = [0-3]
                    // redPPG = [4-7]
                    // irPPG = [8-11]
                    // greenPPG = [12-15]
                    
                    // timestamp is the number of milliseconds passed since the Arduino board began running the current program. This number will overflow (go back to zero), after approximately 50 days.
                    let timestamp = Int32(bigEndian: values[0..<4].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0 })
                    }.pointee)
                    let redPPG = Int32(bigEndian: values[4..<8].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0 })
                    }.pointee)
                    let irPPG = Int32(bigEndian: values[8..<12].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0 })
                    }.pointee)
                    let greenPPG = Int32(bigEndian: values[12..<16].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0 })
                    }.pointee)
                    let sample = OpenBandBleSample(uptime: TimeInterval(timestamp), timestamp: TimeInterval(timestamp), stepPath: self.currentStepPath, r: redPPG, g: greenPPG, i: irPPG, x: nil, y: nil, z: nil)
                    self.writeSample(sample)
                }
                
                if characteristic == accChar {
                    // Values come through in little endian format
                    // timestamp = [0-3]
                    // acc_x = [4-5]
                    // acc_y = [6-7]
                    // acc_z = [8-9]
                    
                    // timestamp is the number of milliseconds passed since the Arduino board began running the current program. This number will overflow (go back to zero), after approximately 50 days.
                    let timestamp = Int32(bigEndian: values[0..<4].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0 })
                    }.pointee)
                    let accX = Int16(bigEndian: values[4..<6].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int16.self, capacity: 1) { $0 })
                    }.pointee)
                    let accY = Int16(bigEndian: values[6..<8].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int16.self, capacity: 1) { $0 })
                    }.pointee)
                    let accZ = Int16(bigEndian: values[8..<10].reversed().withUnsafeBufferPointer {
                             ($0.baseAddress!.withMemoryRebound(to: Int16.self, capacity: 1) { $0 })
                    }.pointee)
                    let sample = OpenBandBleSample(uptime: TimeInterval(timestamp), timestamp: TimeInterval(timestamp), stepPath: self.currentStepPath, r: nil, g: nil, i: nil, x: accX, y: accY, z: accZ)
                    self.writeSample(sample)
                }
            } else {
                print("Error reading values")
            }
        }
        
        // Handling discovery of characteristics
        public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            if let characteristics = service.characteristics {
                for characteristic in characteristics {
                    print("Did discover characteristic \(characteristic)")
                                                            
                    if characteristic.uuid == OpenBandPeripheral.ppgCharacteristic {
                        print("PPG characteristic found")

                        // Set the characteristic
                        ppgChar = characteristic
                        self.peripheral?.setNotifyValue(true, for: characteristic)
                        
                    } else if characteristic.uuid == OpenBandPeripheral.accCharacteristic {
                        print("Accelerometer characteristic found")

                        // Set the characteristic
                        accChar = characteristic
                        self.peripheral?.setNotifyValue(true, for: characteristic)
                    }
    //                } else if characteristic.uuid == OpenBandPeripheral.gyroCharacteristic {
    //                    print("Gyroscope characteristic found")
    //
    //                    // Set the characteristic
    //                    gyroChar = characteristic
    //                } else if characteristic.uuid == OpenBandPeripheral.magCharacteristic {
    //                    print("Magnetometer characteristic found")
    //
    //                    // Set the characteristic
    //                    magChar = characteristic
    //                }
                }
            }
        }
}

public struct OpenBandBleSample : RSDSampleRecord {
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let r: Int32?
    public let g: Int32?
    public let i: Int32?
    public let x: Int16?
    public let y: Int16?
    public let z: Int16?
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, r: Int32?, g: Int32?, i: Int32?, x: Int16?, y: Int16?, z: Int16?) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.r = r
        self.g = g
        self.i = i
        self.x = x
        self.y = y
        self.z = z
    }
}
