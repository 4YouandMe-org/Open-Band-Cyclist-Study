//
//  BleConnectionRecorder.swift
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

/// The configuration for connection to the ble devices.
public struct BleConnectionRecorderConfiguration : RSDRecorderConfiguration, RSDAsyncActionVendor, Codable {

    /// A unique string used to identify the recorder.
    public let identifier: String
    
    /// The step used to mark when to start the recorder.
    public var startStepIdentifier: String?
    
    /// The step used to mark when to stop the recorder and also disconnect the BLE peripheral.
    public var stopStepIdentifier: String?
    
    /// The device to connect to
    public var deviceTypes: [BleDeviceType]?
    
    /// Set the flag to `true` to encode the samples as a CSV file.
    public var usesCSVEncoding : Bool?
    
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
        return BleConnectionRecorder(configuration: self, taskViewModel: taskViewModel, outputDirectory: taskViewModel.outputDirectory)
    }
}

public protocol BleConnectionRecorderDelegate: class {
    func onBleDeviceConnectionChange(deviceType: BleDeviceType, eventType: BleConnectionEventType)
}

public class BleConnectionRecorder : RSDSampleRecorder, BleConnectionManagerDelegate {
        
    public var bleConnectionConfiguration : BleConnectionRecorderConfiguration? {
        return self.configuration as? BleConnectionRecorderConfiguration
    }
    
    public weak var connectionDelegate: BleConnectionRecorderDelegate?
    
    public func isConnected(type: BleDeviceType) -> Bool {
        return BleConnectionManager.shared.isConnected(type: type)
    }

    deinit {
        // TODO: mdephillips 10/23/20 do we need to de-allocate anything?
    }
    
    /// Don't include markers as they will cause a gap in the timestamps
//    override open var shouldIncludeMarkers: Bool {
//        false
//    }
    
    /// Returns the string encoding format to use for this file. Default is `nil`. If this is `nil`
    /// then the file will be formatted using JSON encoding.
    override public func stringEncodingFormat() -> RSDStringSeparatedEncodingFormat? {
        if self.bleConnectionConfiguration?.usesCSVEncoding == true {
            return CSVEncodingFormat<BleConnectionSample>()
        } else {
            return nil
        }
    }
    
    public override func requestPermissions(on viewController: UIViewController, _ completion: @escaping RSDAsyncActionCompletionHandler) {
        
        // We only need to request bluetooth permission on iOS 13 or later
        guard #available(iOS 13, *) else {
            completion(self, nil, nil)
            return
        }
        
        // TODO: mdephillips 10/22/20 deal with permission on iOS 13
        completion(self, nil, nil)
    }
    
    public override func startRecorder(_ completion: @escaping ((RSDAsyncActionStatus, Error?) -> Void)) {
        let bleManager = BleConnectionManager.shared
        
        // Check that the OpenBand is connected
        guard bleManager.centralManager?.state == CBManagerState.poweredOn else {
            completion(.failed, nil)
            return
        }
        
        // Connect to all relevant ble devices
        for type in self.bleConnectionConfiguration?.deviceTypes ?? [] {
            bleManager.connect(type: type)
        }
        
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        let bleManager = BleConnectionManager.shared
        // Disconnect to all relevant ble devices
        for type in self.bleConnectionConfiguration?.deviceTypes ?? [] {
            bleManager.disconnect(type: type)
        }
        super.stopRecorder(completion)
    }
    
    public func onBleDeviceConnectionChange(deviceType: BleDeviceType, eventType: BleConnectionEventType) {
        
        // Log connection event time sample
        let sample = BleConnectionSample(uptime: RSDClock.uptime(), timestamp: nil, stepPath: self.currentStepPath, device: deviceType, event: eventType)
        self.writeSample(sample)
        
        self.connectionDelegate?.onBleDeviceConnectionChange(deviceType: deviceType, eventType: eventType)
    }
}


public enum BleConnectionEventType: String, Codable {
    case connected, disconnected, paused, resumed
}

public struct BleConnectionSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let device: BleDeviceType
    public let event: BleConnectionEventType
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, device: BleDeviceType, event: BleConnectionEventType) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.device = device
        self.event = event
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.uptime, CodingKeys.timestamp, CodingKeys.timestampDate, CodingKeys.stepPath, CodingKeys.device, CodingKeys.event]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case uptime, timestamp, timestampDate, stepPath, device, event
    }
}
