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

public protocol BleConnectionManagerDelegate: AnyObject {
    func onBleDeviceConnectionChange(deviceType: BleDeviceType, eventType: BleConnectionEventType)
}

public protocol RecorderStateDelegate: AnyObject {
    func isRecordering() -> Bool
}

public protocol PolarEcgDataDelegate: AnyObject {
    func onPolarEcgData(data: PolarEcgData)
}

public protocol PolarAccelDataDelegate: AnyObject {
    func onPolarAccelData(data: PolarAccData)
}

public protocol PolarHrDataDelegate: AnyObject {
    func onPolarHrData(data: PolarBleApiDeviceHrObserver.PolarHrData, timestamp: TimeInterval)
}

public protocol OpenBandPpg1DataDelegate: AnyObject {
    func onOpenBandPpg1Data(data: Data?)
}

public protocol OpenBandPpg2DataDelegate: AnyObject {
    func onOpenBandPpg2Data(data: Data?)
}

public protocol OpenBandAccelDataDelegate: AnyObject {
    func onOpenBandAccelData(data: Data?)
}

public protocol OpenBandErrorDelegate: AnyObject {
    func onOpenBandError(data: Data?)
}

/// MARK: - Open Band services and charcteristics Identifiers
public final class OpenBandConstants {
    public static let OpenBandName          = "Movui"
    public static let OpenBandName2         = "OHB"
    
    // UUID of service/chars of interest
    public static let errorCharacteristic     = CBUUID.init(string: "1201")
    public static let startStopCharacteristic = CBUUID.init(string: "1401")
    public static let accCharacteristic     = CBUUID.init(string: "1102")
    public static let gyroCharacteristic    = CBUUID.init(string: "1103")
    public static let magCharacteristic     = CBUUID.init(string: "1104")
    public static let ppgChar1acteristic    = CBUUID.init(string: "1309")
    public static let ppgChar2acteristic    = CBUUID.init(string: "1311")
    
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
    case polar, openBand, all
}

public enum RecordingSchedule: String, Codable {
    case always, oneMinuteEveryTen
}

public final class BleConnectionManager: NSObject, PolarBleApiObserver, PolarBleApiDeviceHrObserver, PolarBleApiDeviceInfoObserver, PolarBleApiDeviceFeaturesObserver, CBPeripheralDelegate, CBCentralManagerDelegate {

    public static let shared = BleConnectionManager()
    
    public weak var delegate: BleConnectionManagerDelegate?
    public weak var polarEcgDataDelegate: PolarEcgDataDelegate?
    public weak var polarAccelDataDelegate: PolarAccelDataDelegate?
    public weak var polarHrDataDelegate: PolarHrDataDelegate?
    public weak var openBandPpg1DataDelegate: OpenBandPpg1DataDelegate?
    public weak var openBandPpg2DataDelegate: OpenBandPpg2DataDelegate?
    public weak var openBandAccelDataDelegate: OpenBandAccelDataDelegate?
    public weak var openBandErrroDelegate: OpenBandErrorDelegate?
    public weak var recorderStateDelegate: RecorderStateDelegate?
    
    // The CoreBluetooth manager
    public var centralManager: CBCentralManager?
    
    // OpenBand BLE device vars
    public var openBandPeripheral: CBPeripheral?
    // OpenBand Characteristics
    private var ppgChar1: CBCharacteristic?
    private var ppgChar2: CBCharacteristic?
    private var accChar: CBCharacteristic?
    private var errorChar: CBCharacteristic?
    private var startStopChar: CBCharacteristic?
    // Connection state tracking
    private var shouldStartOpenBandScanning = false
    
    private let startSensorDataSignal = Data([1])
    private let stopSensorDataSignal = Data([2])
    
    // Controls when, how long, and what frequency the devices record
    public var recordingSchedule: RecordingSchedule = .always {
        didSet {
            // Update data streaming to pause if schedule is changed
            self.isStreamingDataPaused = false
        }
    }
    public var isStreamingDataPaused = false
    
    // Polar BLE device vars
    public var polarConnectedDeviceId: String?
    fileprivate var api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: Features.allFeatures.rawValue)
    fileprivate var autoConnect: Disposable?
    fileprivate var ecgDisposable: Disposable?
    fileprivate var accDisposable: Disposable?
    fileprivate var lastEcgTimestamp: TimeInterval = Date().timeIntervalSince1970
    
    /// Used as reference for timestamps on the data files
    public var startTimeInterval = Date().timeIntervalSince1970
    public var currentRelativeTimeInterval: TimeInterval {
        return Date().timeIntervalSince1970 - startTimeInterval
    }
    
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
        self.delegate?.onBleDeviceConnectionChange(deviceType: type, eventType: .disconnected)
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
        self.openBandPeripheral = nil
    }
    
    // Handles the result of the scan
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
                                
        print("Found peripheral \(peripheral)")
        if (peripheral.name?.starts(with: OpenBandConstants.OpenBandName) ?? false) ||
            (peripheral.name?.starts(with: OpenBandConstants.OpenBandName2) ?? false) ||
            (peripheral.name?.hasSuffix(OpenBandConstants.OpenBandName) ?? false) ||
            (peripheral.name?.hasSuffix(OpenBandConstants.OpenBandName2) ?? false) {
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
            
            // TODO: mdephillips 10/22/20 do we need to handle BLE permission on iOS 13?
        }
    
    // The handler if we do connect succesfully
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral.name == self.openBandPeripheral?.name {
            print("Connected to your Open Band")
            peripheral.discoverServices([])
            self.delegate?.onBleDeviceConnectionChange(deviceType: .openBand, eventType: .connected)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.name == self.openBandPeripheral?.name {
            print("Disconnected")
            
            self.openBandPeripheral = nil
            self.delegate?.onBleDeviceConnectionChange(deviceType: .openBand, eventType: .disconnected)
            
            // Try connecting again if the recorder is running
            if (recorderStateDelegate?.isRecordering() == true) {
                self._connectOpenBand()
            }
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
        
        //print("Did update value for char: \(characteristic.uuid)")
        
        if characteristic == ppgChar1 {
            self.openBandPpg1DataDelegate?.onOpenBandPpg1Data(data: characteristic.value)
        }
        if characteristic == ppgChar2 {
            self.openBandPpg2DataDelegate?.onOpenBandPpg2Data(data: characteristic.value)
        }
        if characteristic == accChar {
            self.openBandAccelDataDelegate?.onOpenBandAccelData(data: characteristic.value)
        }
        if characteristic == errorChar {
//            bufError[0] = errorIMU;
//            bufError[1] = errorPPG86;
//            bufError[2] = errorTemp;
//            bufError[3] = errorTens;
//            let values = [UInt8](characteristic.value!)
            //print("Error recieved from Open Band \(values[0]), \(values[1]), \(values[2]), \(values[3])")
            self.openBandErrroDelegate?.onOpenBandError(data: characteristic.value)
        }
    }
    
    // Handling discovery of characteristics for OpenBand
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                print("Did discover characteristic \(characteristic)")
                                                        
                if characteristic.uuid == OpenBandConstants.ppgChar1acteristic {
                    print("PPG characteristic found")

                    // Set the characteristic
                    self.ppgChar1 = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandConstants.ppgChar2acteristic {
                    print("PPG characteristic found")

                    // Set the characteristic
                    self.ppgChar2 = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandConstants.accCharacteristic {
                    print("Accelerometer characteristic found")

                    // Set the characteristic
                    self.accChar = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandConstants.errorCharacteristic {
                    print("Error characteristic found")

                    // Set the characteristic
                    self.errorChar = characteristic
                    self.openBandPeripheral?.setNotifyValue(true, for: characteristic)
                    
                } else if characteristic.uuid == OpenBandConstants.startStopCharacteristic {
                    print("Start/Stop sensors characteristic found")

                    // Set the characteristic
                    self.startStopChar = characteristic
                    if let charUnwrapped = self.startStopChar {
                        if (!self.isStreamingDataPaused) {
                            self.openBandPeripheral?.writeValue(startSensorDataSignal, for: charUnwrapped, type: .withResponse)
                        } else {
                            self.openBandPeripheral?.writeValue(stopSensorDataSignal, for: charUnwrapped, type: .withResponse)
                        }
                    }
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
        self.autoConnect = api.startAutoConnectToDevice(-55, service: nil, polarDeviceType: "H10").subscribe{ e in
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
        
        _stopPolarEcgAndAccStreaming()
                        
        guard let deviceId = self.polarConnectedDeviceId else { return }
        do{
            try self.api.disconnectFromDevice(deviceId)
        } catch let err {
            print("\(err)")
        }
        self.polarConnectedDeviceId = nil
    }
    
    fileprivate func _stopPolarEcgAndAccStreaming() {
        self.ecgDisposable?.dispose()
        self.ecgDisposable = nil
        self.accDisposable?.dispose()
        self.accDisposable = nil
    }
    
    // PolarBleApiObserver
    public func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTING: \(polarDeviceInfo)")
    }
    
    public func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("Polar device connected: \(polarDeviceInfo.name)")
        NSLog("DEVICE CONNECTED: \(polarDeviceInfo)")
        self.polarConnectedDeviceId = polarDeviceInfo.deviceId
        self.delegate?.onBleDeviceConnectionChange(deviceType: .polar, eventType: .connected)
        // Wait for ecg and accel features to be ready to start streaming them
    }
    
    fileprivate func _startStreamingPolarEcgData() {
        guard let deviceId = self.polarConnectedDeviceId else { return }
        self.ecgDisposable?.dispose()
        self.ecgDisposable = api.requestEcgSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarEcgData> in
            let maxSettings = settings.maxSettings()
            print("Attempting to start polar ecg streaming with max settings: \(maxSettings)")
            return self.api.startEcgStreaming(deviceId, settings: maxSettings)
        }).observe(on: MainScheduler.instance).subscribe{ e in
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
    
    fileprivate func _startStreamingPolarAccelData() {
        guard let deviceId = self.polarConnectedDeviceId else { return }        
        self.accDisposable?.dispose()
        self.accDisposable = api.requestAccSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarAccData> in
                    let maxSettings = settings.maxSettings()
                    print("Attempting to start polar accel streaming with max settings: \(maxSettings)")
                    return self.api.startAccStreaming(deviceId, settings: settings.maxSettings())
        }).observe(on: MainScheduler.instance).subscribe{ e in
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
    }
    
    public func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DISCONNECTED: \(polarDeviceInfo)")
        self.polarConnectedDeviceId = nil
        self.delegate?.onBleDeviceConnectionChange(deviceType: .polar, eventType: .disconnected)
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
        print("New HR value \(data.hr)")
        
        // Provide the latest ECG timestamp as a comparable timestamp across files
        self.polarHrDataDelegate?.onPolarHrData(data: data, timestamp: self.lastEcgTimestamp)
        
        // The periodic 1 second HR characteristic is the perfect place
        // to control the recording schedule as it will wake up our app every second
        // even when the app is running in the background with the screen off
        checkRecordingSchedule()
    }
    
    /// Check whether the recorders should be actively recording or in a paused state.
    private func checkRecordingSchedule() {
        // No need to alter streaming state if we should always be recording
        guard recordingSchedule != .always else {
            return
        }
        
        let shouldStream = shouldBeStreaming()
        
        if (!shouldStream && !self.isStreamingDataPaused) {
            pauseDataStreaming()
        } else if (shouldStream && self.isStreamingDataPaused) {
            resumeDataStreaming()
        }
    }
    
    private func shouldBeStreaming() -> Bool {
        guard recordingSchedule != .always else {
            return true
        }

        if (recordingSchedule == .oneMinuteEveryTen) {
            let components = Calendar.current.dateComponents(
                [.hour,.minute,.second], from: Date())

            guard let minuteOfHour = components.minute else {
                return true
            }

            return
                (minuteOfHour == 0) ||
                (minuteOfHour == 10) ||
                (minuteOfHour == 20) ||
                (minuteOfHour == 30) ||
                (minuteOfHour == 40) ||
                (minuteOfHour == 50)
        }

        return true
    }
    
    private func resumeDataStreaming() {
        debugPrint("Resuming data streaming")
        self.isStreamingDataPaused = false
        if let startChar = self.startStopChar {
            self.openBandPeripheral?.writeValue(startSensorDataSignal, for: startChar, type: .withResponse)
        }
        self._startStreamingPolarEcgData()
        self._startStreamingPolarAccelData()
        self.delegate?.onBleDeviceConnectionChange(deviceType: .all, eventType: .resumed)
    }
    
    private func pauseDataStreaming() {
        debugPrint("Pausing data streaming")
        self.isStreamingDataPaused = true
        if let stopChar = self.startStopChar {
            self.openBandPeripheral?.writeValue(stopSensorDataSignal, for: stopChar, type: .withResponse)
        }
        _stopPolarEcgAndAccStreaming()
        self.delegate?.onBleDeviceConnectionChange(deviceType: .all, eventType: .paused)
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
        if (!self.isStreamingDataPaused) {
            self._startStreamingPolarEcgData()
        }
    }
    
    // PolarBleApiDeviceAccelerometerObserver
    public func accFeatureReady(_ identifier: String) {
        print("Polar ACCEL data ready to stream \(identifier)")
        if (!self.isStreamingDataPaused) {
            self._startStreamingPolarAccelData()
        }
    }
}
