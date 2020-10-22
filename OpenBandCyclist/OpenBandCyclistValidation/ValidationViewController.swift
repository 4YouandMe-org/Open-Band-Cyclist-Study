//
//  ValidationViewController.swift
//  OpenBandCyclistValidation
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

import Foundation
import UIKit
import ResearchUI
import BridgeSDK
import CoreBluetooth

open class ValidationViewController : UIViewController, CBPeripheralDelegate, CBCentralManagerDelegate {
    
    /// Label for displaying polar state info
    @IBOutlet public var polarLabel: UILabel!
    
    /// The button for transitioning to different polar states
    @IBOutlet public var polarButton: RSDRoundedButton!
    
    /// Label for displaying open band state info
    @IBOutlet public var openBandLabel: UILabel!
    
    /// The button for transitioning to different open band states
    @IBOutlet public var openBandButton: RSDRoundedButton!
    
    /// Label for displaying open recording state info
    @IBOutlet public var recordingLabel: UILabel!
    
    /// The button for transitioning to different recording states
    @IBOutlet public var recordingButton: RSDRoundedButton!
    
    // Benchmarking vars
    var ppgByteReadCount: Int = 0
    var ppgReadStartTime: TimeInterval?
    var accByteReadCount: Int = 0
    var accReadStartTime: TimeInterval?
    
    // Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    
    // Characteristics
    private var ppgChar: CBCharacteristic?
    private var accChar: CBCharacteristic?
    private var gyroChar: CBCharacteristic?
    private var magChar: CBCharacteristic?
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        guard BridgeSDK.authManager.isAuthenticated() else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // If we're powered on, start scanning
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central state update")
        if central.state != .poweredOn {
            print("Central is not powered on")
        } else {
            print("Central scanning for \(OpenBandPeripheral.timestampService) and \(OpenBandPeripheral.imuService)");
            centralManager.scanForPeripherals(withServices: [],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }

    // Handles the result of the scan
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
                                
        print("Found peripheral \(peripheral)")
        if peripheral.name == "Open Health Band" {
            // We've found it so stop scan
            self.centralManager.stopScan()
            
            // Copy the peripheral instance
            self.peripheral = peripheral
            
            self.peripheral.delegate = self
            self.centralManager.connect(self.peripheral, options: nil)
        }
    }
    
    // The handler if we do connect succesfully
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == self.peripheral {
            print("Connected to your Open Band")
            peripheral.discoverServices([]);
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == self.peripheral {
            print("Disconnected")
            
            self.peripheral = nil
            
            // Start scanning again
            print("Central scanning for \(OpenBandPeripheral.timestampService) and \(OpenBandPeripheral.imuService)");
            centralManager.scanForPeripherals(withServices: [OpenBandPeripheral.timestampService, OpenBandPeripheral.imuService],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
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
        
        if let data = characteristic.value {
            let values = [UInt8](data)
            
            if characteristic == ppgChar {
                if self.ppgReadStartTime == nil {
                    self.ppgReadStartTime = Date().timeIntervalSince1970
                }
                ppgByteReadCount += values.count
                
                // Log the trasmission rate about every 1 second, assuming 4kB/s
                if (self.ppgByteReadCount % (values.count * 250) == 0) {
                    let elapsedTime = Date().timeIntervalSince1970 - self.ppgReadStartTime!
                    let kBperS = (Double(self.ppgByteReadCount) / 1000.0) / elapsedTime
                    print("PPG trasmission rate = \(kBperS)kB/s")
                }
            }
            
            if characteristic == accChar {
                if self.accReadStartTime == nil {
                    self.accReadStartTime = Date().timeIntervalSince1970
                }
                accByteReadCount += values.count
                
                // Log the trasmission rate about every 1 second, assuming 4kB/s
                if (self.accByteReadCount % (values.count * 250) == 0) {
                    let elapsedTime = Date().timeIntervalSince1970 - self.accReadStartTime!
                    let kBperS = (Double(self.accByteReadCount) / 1000.0) / elapsedTime
                    print("Accelerometer trasmission rate = \(kBperS)kB/s")
                }
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
                    
                    self.peripheral.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandPeripheral.accCharacteristic {
                    print("Accelerometer characteristic found")

                    // Set the characteristic
                    accChar = characteristic
                    
                    self.peripheral.setNotifyValue(true, for: characteristic)
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
        
//        self.peripheral?.enableNotify(for: characteristic, handler: { (error) in
//            if error != nil {
//                print("Error reading characteristic")
//            }
//            if self.startTime == nil {
//                let startTimeUnwrapped = Date().timeIntervalSince1970
//                self.startTime = startTimeUnwrapped
//                print("Reading characteristic started after \(startTimeUnwrapped - self.dataReadStartTime)")
//            }
//            if let data = characteristic.value {
//               let values = [UInt8](data)
//               print("\n\(identifier) New values \(values)")
//           } else {
//               print("Error reading values")
//           }
//
//            //print("data read ")
//            self.dataReadCount = self.dataReadCount + 1
//            let timePassed = Date().timeIntervalSince1970 - self.dataReadStartTime
//            let hz = Double(self.dataReadCount) / timePassed
//            print("\nNotify count \(self.dataReadCount) over \(timePassed) seconds\nSpeed is \(hz) Hz or \(hz*16) bytes/sec with each notify at 16 bytes")
//
//
//        })

//    private func writeLEDValueToChar( withCharacteristic characteristic: CBCharacteristic, withValue value: Data) {
//
//        // Check if it has the write property
//        if characteristic.properties.contains(.writeWithoutResponse) && peripheral != nil {
//
//            peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
//        }
//    }
//
//    @IBAction func redChanged(_ sender: Any) {
//        print("red:",redSlider.value);
//        let slider:UInt8 = UInt8(redSlider.value)
//        writeLEDValueToChar( withCharacteristic: redChar!, withValue: Data([slider]))
//
//    }
//
//    @IBAction func greenChanged(_ sender: Any) {
//        print("green:",greenSlider.value);
//        let slider:UInt8 = UInt8(greenSlider.value)
//        writeLEDValueToChar( withCharacteristic: greenChar!, withValue: Data([slider]))
//    }
//
//    @IBAction func blueChanged(_ sender: Any) {
//        print("blue:",blueSlider.value);
//        let slider:UInt8 = UInt8(blueSlider.value)
//        writeLEDValueToChar( withCharacteristic: blueChar!, withValue: Data([slider]))
//
//    }
}
