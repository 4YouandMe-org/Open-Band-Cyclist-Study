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
    case ppg, accelerometer
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

public class OpenBandBleRecorder : RSDSampleRecorder, OpenBandPpgDataDelegate, OpenBandAccelDataDelegate {
        
    public var openBandBleConfiguration : OpenBandBleRecorderConfiguration? {
        return self.configuration as? OpenBandBleRecorderConfiguration
    }
    
    var permissionCompletion: RSDAsyncActionCompletionHandler?

    deinit {
        // TODO: mdephillips 10/23/20 do we need to de-allocate anything?
    }
    
    /// Returns the string encoding format to use for this file. Default is `nil`. If this is `nil`
    /// then the file will be formatted using JSON encoding.
    override public func stringEncodingFormat() -> RSDStringSeparatedEncodingFormat? {
        if self.openBandBleConfiguration?.usesCSVEncoding == true {
            if openBandBleConfiguration?.dataType == OpenBandDataType.ppg {
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
        if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg {
            bleManager.openBandPpgDataDelegate = self
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.accelerometer {
            bleManager.openBandAccelDataDelegate = self
        }
        
        completion(.running, nil)
    }
    
    public override func stopRecorder(_ completion: @escaping ((RSDAsyncActionStatus) -> Void)) {
        let bleManager = BleConnectionManager.shared
        if self.openBandBleConfiguration?.dataType == OpenBandDataType.ppg {
            bleManager.openBandPpgDataDelegate = nil
        } else if self.openBandBleConfiguration?.dataType == OpenBandDataType.accelerometer {
            bleManager.openBandAccelDataDelegate = nil
        }
        super.stopRecorder(completion)
    }
    
    public func onOpenBandPpgData(data: Data?) {
        guard let dataUnwrapped = data else { return }
        let values = [UInt8](dataUnwrapped)

        guard values.count >= 16 else {
            // TODO: mdephillips 10/22/20 log invalid sample ?
            return
        }
        let timestamp = ByteMathUtils.toOpenBandTimestamp(byte0: values[0], byte1: values[1], byte2: values[2], byte3: values[3])
        let red = ByteMathUtils.toOpenBandPpgValue(byte0: values[4], byte1: values[5], byte2: values[6], byte3: values[7])
        let ir = ByteMathUtils.toOpenBandPpgValue(byte0: values[8], byte1: values[9], byte2: values[10], byte3: values[11])
        let green = ByteMathUtils.toOpenBandPpgValue(byte0: values[12], byte1: values[13], byte2: values[14], byte3: values[15])
        
        let sample = OpenBandPpgSample(uptime: TimeInterval(timestamp), timestamp: nil, stepPath: self.currentStepPath, r: red, g: green, i: ir)
        
        self.writeSample(sample)
    }
    
    public func onOpenBandAccelData(data: Data?) {
        guard let dataUnwrapped = data else { return }
        let values = [UInt8](dataUnwrapped)

        guard values.count >= 10 else {
            // TODO: mdephillips 10/22/20 log invalid sample ?
            return
        }
        
        let timestamp = ByteMathUtils.toOpenBandTimestamp(byte0: values[0], byte1: values[1], byte2: values[2], byte3: values[3])
        let x = ByteMathUtils.toOpenBandAccelFloat(byte0: values[4], byte1: values[5])
        let y = ByteMathUtils.toOpenBandAccelFloat(byte0: values[6], byte1: values[7])
        let z = ByteMathUtils.toOpenBandAccelFloat(byte0: values[8], byte1: values[9])
        
        let sample = OpenBandAccelSample(uptime: TimeInterval(timestamp), timestamp: nil, stepPath: self.currentStepPath, x: x, y: y, z: z)
        
        self.writeSample(sample)
    }
}

public struct OpenBandPpgSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let r: UInt32
    public let g: UInt32
    public let i: UInt32
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, r: UInt32, g: UInt32, i: UInt32) {
        self.uptime = uptime
        self.timestamp = timestamp
        self.stepPath = stepPath
        self.r = r
        self.g = g
        self.i = i
    }
    
    public static func codingKeys() -> [CodingKey] {
        return [CodingKeys.uptime, CodingKeys.timestamp, CodingKeys.timestampDate, CodingKeys.stepPath, CodingKeys.r, CodingKeys.g, CodingKeys.i]
    }
    
    private enum CodingKeys : String, CodingKey, CaseIterable {
        case uptime, timestamp, timestampDate, stepPath, r, g, i
    }
}

public struct OpenBandAccelSample : RSDSampleRecord, RSDDelimiterSeparatedEncodable {
    
    public let uptime: TimeInterval
    public let timestamp: TimeInterval?
    public var timestampDate: Date?
    public let stepPath: String
    public let x: Float
    public let y: Float
    public let z: Float
    
    public init(uptime: TimeInterval, timestamp: TimeInterval?, stepPath: String, x: Float, y: Float, z: Float) {
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
