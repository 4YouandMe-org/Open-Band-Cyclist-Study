//
//  BleConnectionManager.swift
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

import Foundation
import PolarBleSdk
import CoreBluetooth
import RxSwift

public protocol BleConnectionManagerDelegate: class {
    func onBleDeviceConnectionChange(type: BleDeviceType, connected: Bool)
}

public protocol PolarEcgDataDelegate: class {
    func onPolarEcgData(data: PolarEcgData)
}

public protocol PolarAccelDataDelegate: class {
    func onPolarAccelData(data: PolarAccData)
}

public protocol PolarHrDataDelegate: class {
    func onPolarHrData(data: PolarBleApiDeviceHrObserver.PolarHrData, timestamp: TimeInterval)
}

public protocol OpenBandPpgDataDelegate: class {
    func onOpenBandPpgData(data: Data?)
}

public protocol OpenBandAccelDataDelegate: class {
    func onOpenBandAccelData(data: Data?)
}

/// MARK: - Open Band services and charcteristics Identifiers
public final class OpenBandConstants {
    public static let OpenBandName          = "Open Health Band"
    
    // UUID of service/chars of interest
    public static let timestampService      = CBUUID.init(string: "1165")
    public static let imuService            = CBUUID.init(string: "1101")
    public static let ppgCharacteristic     = CBUUID.init(string: "1166")
    public static let accCharacteristic     = CBUUID.init(string: "1102")
    public static let gyroCharacteristic    = CBUUID.init(string: "1103")
    public static let magCharacteristic     = CBUUID.init(string: "1104")
    
    /// The scaling factor to convert to floating point accel values
    /// See Arduino code MPU9250_asukiaaa.cpp for more details.
    /// The byte values are the storage buffers for the hardware accel sensor.
    /// From MPU9250_asukiaaa.cpp in the firmware project the calculation is:
    /// float MPU9250_asukiaaa::accelGet(uint8_t highIndex, uint8_t lowIndex) {
    /// int16_t v = ((int16_t) accelBuf[highIndex]) << 8 | accelBuf[lowIndex];
    ///   return ((float) -v) * accelRange / (float) 0x8000; // (float) 0x8000 == 32768.0
    /// }
    /// where the firmware code sets "accelRange" = 16.0
    public static let accelScalingFactor: Float = 16.0 / 32768.0
}

/// MARK: - Open Band services and charcteristics Identifiers
public final class PolarConstants {
    // ECG Sensor info
    // Input impedance = 2 MΩ (with moistened ProStrap)
    // Bandwidth = 0.7 - 40 Hz (with moistened ProStrap)
    // Dynamic input range = +- 20 000 µV
    // Sample rate = 130 Hz ± 2 % (Tamb = +20 … +40 °C)
    // 130 Hz ± 5 % (Tamb = -20 … +70 °C)
    // Accurate timestamps of samples available
    // Assuming 130 Hz, we can accurately calculate the timestamp of each sample in the array
    public static let timeBetweenSamples = TimeInterval(1.0 / 130.0)
}

public enum BleDeviceType: String, Codable {
    case polar, openBand
}

public final class BleConnectionManager: NSObject, PolarBleApiObserver, PolarBleApiDeviceHrObserver, PolarBleApiDeviceInfoObserver, PolarBleApiDeviceFeaturesObserver, CBPeripheralDelegate, CBCentralManagerDelegate {

    public static let shared = BleConnectionManager()
    
    public weak var delegate: BleConnectionManagerDelegate?
    public weak var polarEcgDataDelegate: PolarEcgDataDelegate?
    public weak var polarAccelDataDelegate: PolarAccelDataDelegate?
    public weak var polarHrDataDelegate: PolarHrDataDelegate?
    public weak var openBandPpgDataDelegate: OpenBandPpgDataDelegate?
    public weak var openBandAccelDataDelegate: OpenBandAccelDataDelegate?
    
    // The CoreBluetooth manager
    public var centralManager: CBCentralManager?
    
    // OpenBand BLE device vars
    public var openBandPeripheral: CBPeripheral?
    // OpenBand Characteristics
    private var ppgChar: CBCharacteristic?
    private var accChar: CBCharacteristic?
    // Connection state tracking
    private var shouldStartOpenBandScanning = false
    
    // Polar BLE device vars
    public var polarConnectedDeviceId: String?
    fileprivate var api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: Features.allFeatures.rawValue)
    fileprivate var autoConnect: Disposable?
    fileprivate var ecgDisposable: Disposable?
    fileprivate var accDisposable: Disposable?
    fileprivate var lastEcgTimestamp: TimeInterval = Date().timeIntervalSince1970
    
    public func isConnected(type: BleDeviceType) -> Bool {
        if type == .polar {
            return self._isPolarDeviceConnected()
        } else if type == .openBand {
            return self._isOpenBandConnected()
        }
        return false
    }
    
    public func connect(type: BleDeviceType) {
        if type == .polar && !self.isConnected(type: .polar) {
            self._connectPolar()
        } else if type == .openBand && !self.isConnected(type: .openBand) {
            self._connectOpenBand()
        }
    }
    
    public func disconnect(type: BleDeviceType) {
        if type == .polar {
            self._disconnectPolar()
        } else if type == .openBand {
            self._disconnectOpenBand()
        }
        self.delegate?.onBleDeviceConnectionChange(type: type, connected: false)
    }
    
    fileprivate func _isOpenBandConnected() -> Bool {
        guard let peripheralUnwrapped = self.openBandPeripheral else {
            return false
        }
        return peripheralUnwrapped.state == CBPeripheralState.connected
    }
    
    fileprivate func _connectOpenBand() {
        self.shouldStartOpenBandScanning = true
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.centralManager?.delegate = self
        self.centralManager?.scanForPeripherals(withServices: [],
                                                     options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    }
    
    fileprivate func _disconnectOpenBand() {
        guard let peripheralUnwrapped = self.openBandPeripheral else { return }
        self.centralManager?.cancelPeripheralConnection(peripheralUnwrapped)
    }
    
    // Handles the result of the scan
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
                                
        print("Found peripheral \(peripheral)")
        if peripheral.name == OpenBandConstants.OpenBandName {
            // We've found it so stop scan
            self.centralManager?.stopScan()
            
            // Copy the peripheral instance
            self.openBandPeripheral = peripheral
            
            self.openBandPeripheral?.delegate = self
            self.centralManager?.connect(peripheral, options: nil)
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
            if central.state != .poweredOn {
                print("Central is not powered on")
            } else {
                print("Central scanning for Open Band Devices");
                if self.shouldStartOpenBandScanning {
                    self.centralManager?.scanForPeripherals(withServices: [],
                                                  options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
                }
            }
            self.shouldStartOpenBandScanning = false
            
            // TODO: mdephillips 10/22/20 handle permission on iOS 13
        }
    
    // The handler if we do connect succesfully
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral.name == self.openBandPeripheral?.name {
            print("Connected to your Open Band")
            peripheral.discoverServices([])
            self.delegate?.onBleDeviceConnectionChange(type: .openBand, connected: true)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.name == self.openBandPeripheral?.name {
            print("Disconnected")
            
            self.openBandPeripheral = nil
            self.delegate?.onBleDeviceConnectionChange(type: .openBand, connected: false)
            
            // TODO: mdephillips 10/22/20 re-connect logic?
            // Start scanning again
//                print("Central scanning for \(OpenBandPeripheral.timestampService) and \(OpenBandPeripheral.imuService)");
//                self.centralManager?.scanForPeripherals(withServices: [OpenBandPeripheral.timestampService, OpenBandPeripheral.imuService],
//                                                  options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        }
    }
    
    // Handles discovery event for Open Band
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                print("Did discover service \(service)")
                peripheral.discoverCharacteristics([], for: service)
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
        if characteristic == ppgChar {
            self.openBandPpgDataDelegate?.onOpenBandPpgData(data: characteristic.value)
        }
        if characteristic == accChar {
            self.openBandAccelDataDelegate?.onOpenBandAccelData(data: characteristic.value)
        }
    }
    
    // Handling discovery of characteristics for OpenBand
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                print("Did discover characteristic \(characteristic)")
                                                        
                if characteristic.uuid == OpenBandConstants.ppgCharacteristic {
                    print("PPG characteristic found")

                    // Set the characteristic
                    self.ppgChar = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandConstants.accCharacteristic {
                    print("Accelerometer characteristic found")

                    // Set the characteristic
                    self.accChar = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    fileprivate func _isPolarDeviceConnected() -> Bool {
        return self.polarConnectedDeviceId != nil
    }
    
    fileprivate func _connectPolar() {
        // Polar manager setup
        self.api.observer = self
        self.api.deviceHrObserver = self
        self.api.deviceInfoObserver = self
        self.api.deviceFeaturesObserver = self
        self.api.polarFilter(false)
        print("\(PolarBleApiDefaultImpl.versionInfo())")
        
        self.autoConnect?.dispose()
        self.autoConnect = api.startAutoConnectToDevice(-55, service: nil, polarDeviceType: nil).subscribe{ e in
            switch e {
            case .completed:
                print("auto connect search complete")
            case .error(let err):
                print("auto connect failed: \(err)")
            @unknown default:
                print("auto connect unknown case")
            }
        }
    }

    fileprivate func _disconnectPolar() {
        self.autoConnect?.dispose()
        self.autoConnect = nil
        self.ecgDisposable?.dispose()
        self.ecgDisposable = nil
        self.accDisposable?.dispose()
        self.accDisposable = nil
        
        guard let deviceId = self.polarConnectedDeviceId else { return }
        do{
            try self.api.disconnectFromDevice(deviceId)
        } catch let err {
            print("\(err)")
        }
        self.polarConnectedDeviceId = nil
    }
    
    // PolarBleApiObserver
    public func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTING: \(polarDeviceInfo)")
    }
    
    public func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTED: \(polarDeviceInfo)")
        self.polarConnectedDeviceId = polarDeviceInfo.deviceId
        self.delegate?.onBleDeviceConnectionChange(type: .polar, connected: true)
        // Immediately begin streaming data
        // Data will not be recorded until recorder is officially started
        self.startStreamingPolarData()
    }
    
    fileprivate func startStreamingPolarData() {
        guard let deviceId = self.polarConnectedDeviceId else { return }
        
        self.accDisposable?.dispose()
        self.accDisposable = api.requestAccSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarAccData> in
                    NSLog("settings: \(settings.settings)")
                    return self.api.startAccStreaming(deviceId, settings: settings.maxSettings())
                }).observeOn(MainScheduler.instance).subscribe{ e in
                    switch e {
                    case .next(let data):
                        self.polarAccelDataDelegate?.onPolarAccelData(data: data)
                    case .error(let err):
                        // TODO: mdephillips 10/23/2020 show error to user?
                        NSLog("ACC error: \(err)")
                        self.accDisposable = nil
                    default: // case .completed:
                        break
                    }
                }
                
                self.ecgDisposable?.dispose()
                self.ecgDisposable = api.requestEcgSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarEcgData> in
                    return self.api.startEcgStreaming(deviceId, settings: settings.maxSettings())
                }).observeOn(MainScheduler.instance).subscribe{ e in
                    switch e {
                    case .next(let data):
                        /// Polar acc data
                        ///     - Timestamp: Last sample timestamp in nanoseconds. Default epoch is 1.1.2000 for H10.
                        ///     - samples: Acceleration samples list x,y,z in millig signed value
                        self.lastEcgTimestamp = TimeInterval(Double(data.timeStamp) / 1000000000.0)
                        self.polarEcgDataDelegate?.onPolarEcgData(data: data)
                    case .error(let err):
                        // TODO: mdephillips 10/23/2020 show error to user?
                        print("start ecg error: \(err)")
                        self.ecgDisposable = nil
                    default: // case .completed:
                        break
                    }
                }
    }
    
    public func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DISCONNECTED: \(polarDeviceInfo)")
        self.polarConnectedDeviceId = nil
        self.delegate?.onBleDeviceConnectionChange(type: .polar, connected: false)
    }
    
    // PolarBleApiDeviceInfoObserver
    public func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        NSLog("polar battery level updated: \(batteryLevel)")
    }
    
    public func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        NSLog("polar dis info: \(uuid.uuidString) value: \(value)")
    }
    
    // PolarBleApiDeviceHrObserver
    public func hrValueReceived(_ identifier: String, data: PolarBleApiDeviceHrObserver.PolarHrData) {
        // Provide the latest ECG timestamp as a comparable timestamp across files
        self.polarHrDataDelegate?.onPolarHrData(data: data, timestamp: self.lastEcgTimestamp)
    }
    
    public func ohrPPGFeatureReady(_ identifier: String) {
        // no op, h10 does not have this
    }
    
    public func ohrPPIFeatureReady(_ identifier: String) {
        // no op, h10 does not have this
    }
    
    public func ftpFeatureReady(_ identifier: String) {
        // no op, h10 does not have this
    }
    
    public func hrFeatureReady(_ identifier: String) {
        print("Polar HR data ready to stream \(identifier)")
    }
    
    // PolarBleApiDeviceEcgObserver
    public func ecgFeatureReady(_ identifier: String) {
        print("Polar ECG data ready to stream \(identifier)")
    }
    
    // PolarBleApiDeviceAccelerometerObserver
    public func accFeatureReady(_ identifier: String) {
        print("Polar ACCEL data ready to stream \(identifier)")
    }
}
