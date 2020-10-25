//
//  PolarBleRecorder.swift
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
import PolarBleSdk
import RxSwift

/// The configuration for the heart rate recorder.
public struct PolarBleRecorderConfiguration : RSDRecorderConfiguration, RSDAsyncActionVendor, Codable {

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
        return PolarBleRecorder(configuration: self, taskViewModel: taskViewModel, outputDirectory: taskViewModel.outputDirectory)
    }
}

public protocol PolarBleRecorderDelegate: class {
    func onConnectionChange(recorder: PolarBleRecorder)
}

public class PolarBleRecorder : RSDSampleRecorder, PolarBleApiObserver, PolarBleApiDeviceHrObserver, PolarBleApiDeviceInfoObserver, PolarBleApiDeviceFeaturesObserver, CBCentralManagerDelegate {

    public enum PolarBleRecorderError : Error {
        case permissionIssue(CBManagerState)
    }
    
    public var polarBleConfiguration : PolarBleRecorderConfiguration? {
        return self.configuration as? PolarBleRecorderConfiguration
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
    
    // The connected device ID
    var connectedDeviceId: String?
    public var isConnected: Bool {
        return connectedDeviceId != nil
    }
    weak var polarDelegate: PolarBleRecorderDelegate?
    
    var api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: Features.allFeatures.rawValue)
    var autoConnect: Disposable?
    var ecgDisposable: Disposable?
    var accDisposable: Disposable?
    
    // The central BT manager, used to manage permission requests
    var centralManager: CBCentralManager?
    var permissionCompletion: RSDAsyncActionCompletionHandler?
    
    // The BLE connection can be running without writing to the logger
    // When isRecording is true, samples from the BLE device will be logged
    var isRecording = false
    
    deinit {
        // TODO: mdephillips 10/23/20 do we need to de-allocate anything?
    }
    
//    This did not seem to work, becuase the recorder needs to be running to have this function called
//    /// Override to check if the step is the one where we should connect to the polar device
//    override public func moveTo(step: RSDStep, taskViewModel: RSDPathComponent) {
//
//        // Call super. This will update the step path and add a step change marker.
//        super.moveTo(step: step, taskViewModel: taskViewModel)
//
//        // Look to see if the configuration has a connection step and update state accordingly.
//        if let _ = self.polarBleConfiguration?.connectionStepIdentifier {
//            self.autoConnectBleDevice()
//        }
//    }
    
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
                completion(self, nil, PolarBleRecorderError.permissionIssue(CBManagerState.poweredOff))
            } else {
                completion(self, nil, nil)
            }
        case .denied, .restricted:
            completion(self, nil, PolarBleRecorderError.permissionIssue(.unauthorized))
        default: // Not determined
            // When the permission is not determined, the central manager creation
            // triggers the permission request, and will be shown at this point
            // Now we just need to wait for the delegate to communicate the change in permission
            self.permissionCompletion = completion
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard #available(iOS 13, *) else { return }
        
        switch self.centralManager?.authorization {
        case .allowedAlways:
            if self.centralManager?.state == CBManagerState.poweredOff {
                self.permissionCompletion?(self, nil, PolarBleRecorderError.permissionIssue(CBManagerState.poweredOff))
            } else {
                self.permissionCompletion?(self, nil, nil)
            }
        case .denied, .restricted:
            self.permissionCompletion?(self, nil, PolarBleRecorderError.permissionIssue(.unauthorized))
        default: // Not determined
            break
        }
    }
    
    public override func startRecorder(_ completion: @escaping ((RSDAsyncActionStatus, Error?) -> Void)) {
        guard let _ = self.connectedDeviceId else {
            completion(.failed, nil)
            return
        }
        self.isRecording = true
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        self.isRecording = false
        self.autoConnect?.dispose()
        self.autoConnect = nil
        self.ecgDisposable?.dispose()
        self.ecgDisposable = nil
        self.accDisposable?.dispose()
        self.accDisposable = nil
        self.disconnectFromDevice()
        super.stopRecorder(completion)
    }
    
    public func disconnectFromDevice() {
        guard let deviceId = self.connectedDeviceId else { return }
        do{
            try self.api.disconnectFromDevice(deviceId)
        } catch let err {
            print("\(err)")
        }
    }
    
    public func autoConnectBleDevice() {
        
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
    
    func startStreamingData() {
        guard let deviceId = self.connectedDeviceId else { return }
        
        self.accDisposable?.dispose()
        self.accDisposable = api.requestAccSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarAccData> in
                    NSLog("settings: \(settings.settings)")
                    return self.api.startAccStreaming(deviceId, settings: settings.maxSettings())
                }).observeOn(MainScheduler.instance).subscribe{ e in
                    switch e {
                    case .next(let data):
                        
                        if self.isRecording {
                            /// Polar acc data
                            ///     - Timestamp: Last sample timestamp in nanoseconds. Default epoch is 1.1.2000 for H10.
                            ///     - samples: Acceleration samples list x,y,z in millig signed value
                            let lastTimeStampSec = TimeInterval(Double(data.timeStamp) / 1000000000.0)
                            
                            //let recorderSamples =
                            let samples = data.samples.enumerated().map { (i, value) -> PolarBleSample in
                                // Calculate time interval since start time
                                let timestampSec = lastTimeStampSec - (TimeInterval(data.samples.count - i - 1) * self.timeBetweenSamples)
                                return PolarBleSample(uptime: timestampSec, timestamp: timestampSec, stepPath: self.currentStepPath, e: nil, hr: nil, rriMs: nil, x: value.x, y: value.y, z: value.z)
                            }
                            
                            // Write the samples to the logging queue
                            self.writeSamples(samples)
                        }
                        
                    case .error(let err):
                        NSLog("ACC error: \(err)")
                        self.accDisposable = nil
                    case .completed:
                        break
                    }
                }
                
                self.ecgDisposable?.dispose()
                self.ecgDisposable = api.requestEcgSettings(deviceId).asObservable().flatMap({ (settings) -> Observable<PolarEcgData> in
                    return self.api.startEcgStreaming(deviceId, settings: settings.maxSettings())
                }).observeOn(MainScheduler.instance).subscribe{ e in
                    switch e {
                    case .next(let data):
                        if self.isRecording {
                            /// Polar Ecg data
                            ///     - timestamp: Last sample timestamp in nanoseconds. Default epoch is 1.1.2000
                            ///     - samples: ecg sample in µVolts
                            let lastTimeStampSec = TimeInterval(Double(data.timeStamp) / 1000000000.0)
                            
                            //let recorderSamples =
                            let samples = data.samples.enumerated().map { (i, value) -> PolarBleSample in
                                // Calculate time interval since start time
                                let timestampSec = lastTimeStampSec - (TimeInterval(data.samples.count - i - 1) * self.timeBetweenSamples)
                                return PolarBleSample(uptime: timestampSec, timestamp: timestampSec, stepPath: self.currentStepPath, e: value, hr: nil, rriMs: nil, x: nil, y: nil, z: nil)
                            }
                            
                            // Write the samples to the logging queue
                            self.writeSamples(samples)
                        }
                        
                    case .error(let err):
                        // TODO: mdephillips 10/23/2020 show error to user
                        print("start ecg error: \(err)")
                        self.ecgDisposable = nil
                    case .completed:
                        break
                    }
                }
    }
    
    // PolarBleApiObserver
    public func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTING: \(polarDeviceInfo)")
    }
    
    public func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DEVICE CONNECTED: \(polarDeviceInfo)")
        self.connectedDeviceId = polarDeviceInfo.deviceId
        self.polarDelegate?.onConnectionChange(recorder: self)
        // Immediately begin streaming data
        // Data will not be recorded until recorder is officially started
        self.startStreamingData()
    }
    
    public func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo) {
        NSLog("DISCONNECTED: \(polarDeviceInfo)")
        self.connectedDeviceId = nil
        self.polarDelegate?.onConnectionChange(recorder: self)
    }
    
    // PolarBleApiDeviceInfoObserver
    public func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        NSLog("battery level updated: \(batteryLevel)")
    }
    
    public func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        NSLog("dis info: \(uuid.uuidString) value: \(value)")
    }
    
    // PolarBleApiDeviceHrObserver
    public func hrValueReceived(_ identifier: String, data: PolarBleApiDeviceHrObserver.PolarHrData) {
        /// Polar hr data
        ///     - hr in BPM
        ///     - rrs RR interval in 1/1024. R is a the top highest peak in the QRS complex of the ECG wave and RR is the interval between successive Rs.
        ///     - rrs RR interval in ms.
        ///     - contact status between the device and the users skin
        ///     - contactSupported if contact is supported
        print("(\(identifier)) HR notification: \(data.hr) rrs: \(data.rrs) rrsMs: \(data.rrsMs) c: \(data.contact) s: \(data.contactSupported)")
        
        let uptime = Date().timeIntervalSince(self.startDate)
        let timestamp = Date().timeIntervalSince1970
        let sample = PolarBleSample(uptime: uptime, timestamp: timestamp, stepPath: self.currentStepPath, e: nil, hr: data.hr, rriMs: data.rrsMs, x: nil, y: nil, z: nil)
        self.writeSample(sample)
    }
    
    public func ohrPPGFeatureReady(_ identifier: String) {
        // no op
    }
    
    public func ohrPPIFeatureReady(_ identifier: String) {
        // no op
    }
    
    public func ftpFeatureReady(_ identifier: String) {
        // no op
    }
    
    public func hrFeatureReady(_ identifier: String) {
        print("HR READY")
    }
    
    // PolarBleApiDeviceEcgObserver
    public func ecgFeatureReady(_ identifier: String) {
        print("ECG READY \(identifier)")
    }
    
    // PolarBleApiDeviceAccelerometerObserver
    public func accFeatureReady(_ identifier: String) {
        print("ACC READY")
    }
}

public struct PolarBleSample : RSDSampleRecord {
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let e: Int32?
    public let hr: UInt8?
    public let rriMs: [Int]?
    public let x: Int32?
    public let y: Int32?
    public let z: Int32?
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, e: Int32?, hr: UInt8?, rriMs: [Int]?, x: Int32?, y: Int32?, z: Int32?) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.hr = hr
        self.rriMs = rriMs
        self.e = e
        self.x = x
        self.y = y
        self.z = z
    }
}
