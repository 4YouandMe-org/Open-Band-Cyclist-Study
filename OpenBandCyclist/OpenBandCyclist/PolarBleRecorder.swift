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

public enum PolarDataType: String, Codable {
    case ecg, hr, accelerometer
}

/// The configuration for the heart rate recorder.
public struct PolarBleRecorderConfiguration : RSDRecorderConfiguration, RSDAsyncActionVendor, Codable {

    /// A unique string used to identify the recorder.
    public let identifier: String
    
    /// The step used to mark when to start the recorder.
    public var startStepIdentifier: String?
    
    /// The step used to mark when to stop the recorder and also disconnect the BLE peripheral.
    public var stopStepIdentifier: String?
    
    /// The type of data to write to the logger file
    public var dataType: PolarDataType?
    
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
        return PolarBleRecorder(configuration: self, taskViewModel: taskViewModel, outputDirectory: taskViewModel.outputDirectory)
    }
}

public class PolarBleRecorder : RSDSampleRecorder, PolarEcgDataDelegate, PolarAccelDataDelegate, PolarHrDataDelegate {
        
    public var polarBleConfiguration : PolarBleRecorderConfiguration? {
        return self.configuration as? PolarBleRecorderConfiguration
    }
    
    deinit {
        // TODO: mdephillips 10/23/20 do we need to de-allocate anything?
    }    
    
    /// Returns the string encoding format to use for this file. Default is `nil`. If this is `nil`
    /// then the file will be formatted using JSON encoding.
    override public func stringEncodingFormat() -> RSDStringSeparatedEncodingFormat? {
        if self.polarBleConfiguration?.usesCSVEncoding == true {
            if self.polarBleConfiguration?.dataType == PolarDataType.ecg {
                return CSVEncodingFormat<PolarEcgSample>()
            } else if self.polarBleConfiguration?.dataType == PolarDataType.hr {
                return CSVEncodingFormat<PolarHrSample>()
            } else if self.polarBleConfiguration?.dataType == PolarDataType.accelerometer {
                return CSVEncodingFormat<PolarAccelSample>()
            }
        }
        return nil
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
        
        // Check that the Polar H10 is connected
        guard bleManager.isConnected(type: .polar) else {
            completion(.failed, nil)
            return
        }
        
        // Subscribe to Polar BLE data updates to write to the log file
        if self.polarBleConfiguration?.dataType == PolarDataType.ecg {
            bleManager.polarEcgDataDelegate = self
        } else if self.polarBleConfiguration?.dataType == PolarDataType.hr {
            bleManager.polarHrDataDelegate = self
        } else if self.polarBleConfiguration?.dataType == PolarDataType.accelerometer {
            bleManager.polarAccelDataDelegate = self
        }
        
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        let bleManager = BleConnectionManager.shared
        if self.polarBleConfiguration?.dataType == PolarDataType.ecg {
            bleManager.polarEcgDataDelegate = nil
        } else if self.polarBleConfiguration?.dataType == PolarDataType.hr {
            bleManager.polarHrDataDelegate = nil
        } else if self.polarBleConfiguration?.dataType == PolarDataType.accelerometer {
            bleManager.polarAccelDataDelegate = nil
        }
        super.stopRecorder(completion)
    }
    
    public func onPolarEcgData(data: PolarEcgData) {
        /// Polar Ecg data
        ///     - timestamp: Last sample timestamp in nanoseconds. Default epoch is 1.1.2000
        ///     - samples: ecg sample in µVolts
        let lastTimeStampSec = TimeInterval(Double(data.timeStamp) / 1000000000.0)
        
        //let recorderSamples =
        let samples = data.samples.enumerated().map { (i, value) -> PolarEcgSample in
            // Calculate time interval since start time
            let timestampSec = lastTimeStampSec - (TimeInterval(data.samples.count - i - 1) * PolarConstants.timeBetweenSamples)
            
            return PolarEcgSample(uptime: timestampSec, timestamp: nil, stepPath: self.currentStepPath, ecg: value)
        }
        
        // Write the samples to the logging queue
        self.writeSamples(samples)
    }
    
    public func onPolarAccelData(data: PolarAccData) {
        /// Polar acc data
        ///     - Timestamp: Last sample timestamp in nanoseconds. Default epoch is 1.1.2000 for H10.
        ///     - samples: Acceleration samples list x,y,z in millig signed value
        let lastTimeStampSec = TimeInterval(Double(data.timeStamp) / 1000000000.0)
        
        //let recorderSamples =
        let samples = data.samples.enumerated().map { (i, value) -> PolarAccelSample in
            // Calculate time interval since start time
            let timestampSec = lastTimeStampSec - (TimeInterval(data.samples.count - i - 1) * PolarConstants.timeBetweenSamples)
            return PolarAccelSample(uptime: timestampSec, timestamp: nil, stepPath: self.currentStepPath, x: value.x, y: value.y, z: value.z)
        }
        
        // Write the samples to the logging queue
        self.writeSamples(samples)
    }
    
    public func onPolarHrData(data: PolarBleApiDeviceHrObserver.PolarHrData, timestamp: TimeInterval) {
        /// Polar hr data
        ///     - hr in BPM
        ///     - rrs RR interval in 1/1024. R is a the top highest peak in the QRS complex of the ECG wave and RR is the interval between successive Rs.
        ///     - rrs RR interval in ms.
        ///     - contact status between the device and the users skin
        ///     - contactSupported if contact is supported
        let sample = PolarHrSample(uptime: timestamp, timestamp: nil, stepPath: self.currentStepPath, hr: data.hr, rriMs: data.rrsMs)
        
        self.writeSample(sample)
    }
}

public struct PolarEcgSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let ecg: Int32
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, ecg: Int32) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.ecg = ecg
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.uptime, CodingKeys.timestamp, CodingKeys.timestampDate, CodingKeys.stepPath, CodingKeys.ecg]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case uptime, timestamp, timestampDate, stepPath, ecg
    }
}

public struct PolarHrSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let hr: UInt8
    public let rriMs: [Int]
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, hr: UInt8, rriMs: [Int]) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.hr = hr
        self.rriMs = rriMs
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.uptime, CodingKeys.timestamp, CodingKeys.timestampDate, CodingKeys.stepPath, CodingKeys.hr, CodingKeys.rriMs]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case uptime, timestamp, timestampDate, stepPath, hr, rriMs
    }
}

public struct PolarAccelSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let x: Int32
    public let y: Int32
    public let z: Int32
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, x: Int32, y: Int32, z: Int32) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.x = x
        self.y = y
        self.z = z
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.uptime, CodingKeys.timestamp, CodingKeys.timestampDate, CodingKeys.stepPath, CodingKeys.x, CodingKeys.y, CodingKeys.z]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case uptime, timestamp, timestampDate, stepPath, x, y, z
    }
}
