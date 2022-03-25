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

public enum OpenBandDataType: String, Codable {
    case ppg1, ppg2, accelerometer
}

/// The configuration for the heart rate recorder.
public struct OpenBandBleRecorderConfiguration : RSDRecorderConfiguration, RSDAsyncActionVendor, Codable {

    /// A unique string used to identify the recorder.
    public let identifier: String
    
    /// The step used to mark when to start the recorder.
    public var startStepIdentifier: String?
    
    /// The step used to mark when to stop the recorder and also disconnect the BLE peripheral.
    public var stopStepIdentifier: String?
    
    /// The type of data to write to the logger file
    public var dataType: OpenBandDataType?
    
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
        return OpenBandBleRecorder(configuration: self, taskViewModel: taskViewModel, outputDirectory: taskViewModel.outputDirectory)
    }
}

public class OpenBandBleRecorder : RSDSampleRecorder, OpenBandPpg1DataDelegate, OpenBandPpg2DataDelegate, OpenBandAccelDataDelegate {
    
    var sampleStartTime: TimeInterval? = nil
    var sampleCount = 0
    
    var sampleStartTime2: TimeInterval? = nil
    var sampleCount2 = 0
    
    var sampleStartTimeAcc: TimeInterval? = nil
    var sampleCountAcc = 0
            
    public var openBandBleConfiguration : OpenBandBleRecorderConfiguration? {
        return self.configuration as? OpenBandBleRecorderConfiguration
    }
    
    var permissionCompletion: RSDAsyncActionCompletionHandler?

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
        if self.openBandBleConfiguration?.usesCSVEncoding == true {
            if openBandBleConfiguration?.dataType == OpenBandDataType.ppg1 || self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg2 {
                return CSVEncodingFormat<OpenBandPpgSample>()
            } else if openBandBleConfiguration?.dataType == OpenBandDataType.accelerometer {
                return CSVEncodingFormat<OpenBandAccelSample>()
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
        
        // Check that the OpenBand is connected
        guard bleManager.isConnected(type: .openBand) else {
            completion(.failed, nil)
            return
        }
        
        // Subscribe to OpenBand BLE data updates to write to the log file
        if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg1 {
            bleManager.openBandPpg1DataDelegate = self
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg2 {
            bleManager.openBandPpg2DataDelegate = self
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.accelerometer {
            bleManager.openBandAccelDataDelegate = self
        }
        
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        let bleManager = BleConnectionManager.shared
        if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg1 {
            bleManager.openBandPpg1DataDelegate = nil
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg2 {
            bleManager.openBandPpg2DataDelegate = nil
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.accelerometer {
            bleManager.openBandAccelDataDelegate = nil
        }
        super.stopRecorder(completion)
    }
    
    var i = 0
    public func onOpenBandPpg1Data(data: Data?) {
        guard let dataUnwrapped = data,
         (openBandBleConfiguration?.dataType == OpenBandDataType.ppg1) else {
             return
         }
        let values = [UInt8](dataUnwrapped)
        
        let relativeTimestamp = BleConnectionManager.shared.currentRelativeTimeInterval
        
        guard values.count >= 12 else {
            // TODO: mdephillips 10/22/20 log invalid sample ?
            return
        }
        let timestamp = ByteMathUtils.toOpenBandTimestamp(byte0: values[0], byte1: values[1], byte2: values[2], byte3: values[3])
        let g1 = ByteMathUtils.toOpenBandPpgValue(byte0: values[4], byte1: values[5], byte2: values[6], byte3: values[7])
        let g2 = ByteMathUtils.toOpenBandPpgValue(byte0: values[8], byte1: values[9], byte2: values[10], byte3: values[11])
        
        let sample = OpenBandPpgSample(timestamp: TimeInterval(timestamp), relativeTimestamp: relativeTimestamp, stepPath: self.currentStepPath, g1: g1, g2: g2)
        
        i += 1
        if (i % 30 == 0) {
            print("values: \(values)")
        }
        
        self.sampleCount += 1
        if let sampleTimeUnwrapped = self.sampleStartTime {
            let now = Date().timeIntervalSince1970
            let timeDiff = now - sampleTimeUnwrapped
            if (timeDiff > 1) {
                let samplesPerSecond = Double(self.sampleCount) / (timeDiff)
                print("PPG-1 Samples per second: \(samplesPerSecond)")
                self.sampleStartTime = Date().timeIntervalSince1970
                self.sampleCount = 1
            }
        } else {
            self.sampleStartTime = Date().timeIntervalSince1970
            self.sampleCount = 1
        }
        
        self.writeSample(sample)
    }
    
    public func onOpenBandPpg2Data(data: Data?) {
        guard let dataUnwrapped = data,
         (openBandBleConfiguration?.dataType == OpenBandDataType.ppg2) else {
             return
         }
        let values = [UInt8](dataUnwrapped)
        
        let relativeTimestamp = BleConnectionManager.shared.currentRelativeTimeInterval
    
        guard values.count >= 12 else {
            // TODO: mdephillips 10/22/20 log invalid sample ?
            return
        }
        
        let timestamp = ByteMathUtils.toOpenBandTimestamp(byte0: values[0], byte1: values[1], byte2: values[2], byte3: values[3])
        let g1 = ByteMathUtils.toOpenBandPpgValue(byte0: values[4], byte1: values[5], byte2: values[6], byte3: values[7])
        let g2 = ByteMathUtils.toOpenBandPpgValue(byte0: values[8], byte1: values[9], byte2: values[10], byte3: values[11])
        
        let sample = OpenBandPpgSample(timestamp: TimeInterval(timestamp), relativeTimestamp: relativeTimestamp, stepPath: self.currentStepPath, g1: g1, g2: g2)
        
        self.sampleCount2 += 1
        if let sampleTimeUnwrapped = self.sampleStartTime2 {
            let now = Date().timeIntervalSince1970
            let timeDiff = now - sampleTimeUnwrapped
            if (timeDiff > 1) {
                let samplesPerSecond = Double(self.sampleCount2) / (timeDiff)
                print("PPG-2 Samples per second: \(samplesPerSecond)")
                self.sampleStartTime2 = Date().timeIntervalSince1970
                self.sampleCount2 = 1
            }
        } else {
            self.sampleStartTime2 = Date().timeIntervalSince1970
            self.sampleCount2 = 1
        }
        
        self.writeSample(sample)
    }
    
    public func onOpenBandAccelData(data: Data?) {
        guard let dataUnwrapped = data else { return }
        let values = [UInt8](dataUnwrapped)
        
        let relativeTimestamp = BleConnectionManager.shared.currentRelativeTimeInterval

        guard values.count >= 11 else {
            // TODO: mdephillips 10/22/20 log invalid sample ?
            return
        }
        
        let timestamp = ByteMathUtils.toOpenBandTimestamp(byte0: values[0], byte1: values[1], byte2: values[2], byte3: values[3])
        // byte 4 is a constant for scale, that is not needed and assumed by this calculation
        let x = ByteMathUtils.toOpenBandAccelFloat(byte0: values[5], byte1: values[6])
        let y = ByteMathUtils.toOpenBandAccelFloat(byte0: values[7], byte1: values[8])
        let z = ByteMathUtils.toOpenBandAccelFloat(byte0: values[9], byte1: values[10])
        
        let sample = OpenBandAccelSample(timestamp: TimeInterval(timestamp), relativeTimestamp: relativeTimestamp, stepPath: self.currentStepPath, x: x, y: y, z: z)
        
        self.sampleCountAcc += 1
        if let sampleTimeUnwrapped = self.sampleStartTimeAcc {
            let now = Date().timeIntervalSince1970
            let timeDiff = now - sampleTimeUnwrapped
            if (timeDiff > 1) {
                let samplesPerSecond = Double(self.sampleCountAcc) / (timeDiff)
                print("Acc Samples per second: \(samplesPerSecond)")
                self.sampleStartTimeAcc = Date().timeIntervalSince1970
                self.sampleCountAcc = 1
            }
        } else {
            self.sampleStartTimeAcc = Date().timeIntervalSince1970
            self.sampleCountAcc = 1
        }
        
        self.writeSample(sample)
    }
}

public struct OpenBandPpgSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
        
    /// A  millisecond value representing the time that has passed since the OpenBand device has been running.
    /// See Arduino API millis() function
    public let timestamp: TimeInterval?
    
    /// A  millisecond value representing the time in seconds since the user landed on the BLE connection screen
    public let relativeTimestamp: TimeInterval?
    
    /// This is a unique string representing which screen the user is on while the data is being recorded
    public let stepPath: String
    
    /// The green sample 1 value of the PPG sensor
    public let g1: UInt32
    /// The green sample 2 value of the PPG sensor
    public let g2: UInt32
    
    // Unused, but required by RSDSampleRecord protocol
    public let timestampDate: Date? = nil
    public let uptime: TimeInterval = Date().timeIntervalSince1970
    
    public init(timestamp: TimeInterval, relativeTimestamp: TimeInterval, stepPath: String, g1: UInt32, g2: UInt32) {
        self.timestamp = timestamp
        self.relativeTimestamp = relativeTimestamp
        self.stepPath = stepPath
        self.g1 = g1
        self.g2 = g2
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        self.timestamp = try values.decode(TimeInterval.self, forKey: CodingKeys.timestamp)
        self.relativeTimestamp = try values.decode(TimeInterval.self, forKey: CodingKeys.relativeTimestamp)
        self.stepPath = try values.decode(String.self, forKey: CodingKeys.stepPath)
        self.g1 = try values.decode(UInt32.self, forKey: CodingKeys.g1)
        self.g2 = try values.decode(UInt32.self, forKey: CodingKeys.g2)
        
        // This class does not support timestampDate or uptime, ignore these values
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(g1, forKey: CodingKeys.g1)
        try container.encode(g2, forKey: CodingKeys.g2)
        try container.encode(timestamp, forKey: CodingKeys.timestamp)
        try container.encode(relativeTimestamp, forKey: CodingKeys.relativeTimestamp)
        try container.encode(stepPath, forKey: CodingKeys.stepPath)
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.timestamp, CodingKeys.relativeTimestamp, CodingKeys.g1, CodingKeys.g2, CodingKeys.stepPath]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case timestamp, relativeTimestamp, g1, g2, stepPath
    }
}

public struct OpenBandAccelSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    /// A  millisecond value representing the time that has passed since the OpenBand device has been running.
    /// See Arduino API millis() function
    public let timestamp: TimeInterval?
    
    /// A  millisecond value representing the time in seconds since the user landed on the BLE connection screen
    public let relativeTimestamp: TimeInterval?
    
    /// This is a unique string representing which screen the user is on while the data is being recorded
    public let stepPath: String
    
    /// The x-axis accelerometer value of the sensor on the Open Band
    public let x: Float
    /// The y-axis accelerometer value of the sensor on the Open Band
    public let y: Float
    /// The z-axis accelerometer value of the sensor on the Open Band
    public let z: Float
    
    // Unused, but required by RSDSampleRecord protocol
    public let timestampDate: Date? = nil
    public let uptime: TimeInterval = Date().timeIntervalSince1970
    
    public init(timestamp: TimeInterval, relativeTimestamp: TimeInterval, stepPath: String, x: Float, y: Float, z: Float) {
        self.timestamp = timestamp
        self.relativeTimestamp = relativeTimestamp
        self.stepPath = stepPath
        self.x = x
        self.y = y
        self.z = z
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        self.timestamp = try values.decode(TimeInterval.self, forKey: CodingKeys.timestamp)
        self.relativeTimestamp = try values.decode(TimeInterval.self, forKey: CodingKeys.relativeTimestamp)
        self.stepPath = try values.decode(String.self, forKey: CodingKeys.stepPath)
        self.x = try values.decode(Float.self, forKey: CodingKeys.x)
        self.y = try values.decode(Float.self, forKey: CodingKeys.y)
        self.z = try values.decode(Float.self, forKey: CodingKeys.z)
        
        // This class does not support timestampDate or uptime, ignore these values
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: CodingKeys.x)
        try container.encode(y, forKey: CodingKeys.y)
        try container.encode(z, forKey: CodingKeys.z)
        try container.encode(timestamp, forKey: CodingKeys.timestamp)
        try container.encode(relativeTimestamp, forKey: CodingKeys.relativeTimestamp)
        try container.encode(stepPath, forKey: CodingKeys.stepPath)
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.timestamp, CodingKeys.relativeTimestamp, CodingKeys.x, CodingKeys.y, CodingKeys.z, CodingKeys.stepPath]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case timestamp, relativeTimestamp, x, y, z, stepPath
    }
}
