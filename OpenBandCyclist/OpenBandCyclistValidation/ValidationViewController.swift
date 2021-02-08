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
import BridgeApp
import Research
import ResearchUI
import BridgeSDK
import CoreBluetooth
import PolarBleSdk
import RxSwift

open class ValidationViewController : UIViewController, RSDTaskViewControllerDelegate {
    
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
    
    // Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    
    // Characteristics
    private var ppgChar: CBCharacteristic?
    private var accChar: CBCharacteristic?
    private var gyroChar: CBCharacteristic?
    private var magChar: CBCharacteristic?
    
    // Benchmarking helper class
    var benchmark = ValidationBenchmarkingHelper()
    
    // Polar vars
    var autoConnect: Disposable?
    var ecgToggle: Disposable?
    var accToggle: Disposable?
    
    // API reference for polar
    var api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: Features.allFeatures.rawValue)
    
    var deviceId = "" // replace this with your device id
    
    let scheduleManager = SBAScheduleManager()
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        guard BridgeSDK.authManager.isAuthenticated() else { return }
    }

    @IBAction func validationButtonTapped(_ sender: Any) {
        let resource = RSDResourceTransformerObject(resourceName: "Validation.json", bundle: Bundle.main)
        do {
            let task = try RSDFactory.shared.decodeTask(with: resource)
            let vc = RSDTaskViewController(task: task)
            vc.modalPresentationStyle = .fullScreen
            vc.delegate = self
            self.present(vc, animated: true, completion: nil)
        } catch let error {
            print("Error creating validation task from JSON \(error)")
        }
    }
    
    public func taskController(_ taskController: RSDTaskController, didFinishWith reason: RSDTaskFinishReason, error: Error?) {
        self.scheduleManager.taskController(taskController, didFinishWith: reason, error: error)
        self.dismiss(animated: true, completion: nil)
    }
    
    public func taskController(_ taskController: RSDTaskController, readyToSave taskViewModel: RSDTaskViewModel) {
        self.scheduleManager.taskController(taskController, readyToSave: taskViewModel)
    }
}

class ValidationBenchmarkingHelper {
    // Benchmarking vars
    var ppgByteReadCount: Int = 0
    var ppgReadStartTime: TimeInterval?
    var accByteReadCount: Int = 0
    var accReadStartTime: TimeInterval?
    var polarEcgByteReadCount: Int = 0
    var polarEcgReadStartTime: TimeInterval?
    var polarAccByteReadCount: Int = 0
    var polarAccReadStartTime: TimeInterval?
    
    func updateOBPpg(with values: [UInt8]) {
        if self.ppgReadStartTime == nil {
            self.ppgReadStartTime = Date().timeIntervalSince1970
        }
        ppgByteReadCount += values.count
        // Log the trasmission rate about every 1 second, assuming 4kB/s
        if (self.ppgByteReadCount % (values.count * 250) == 0) {
            let elapsedTime = Date().timeIntervalSince1970 - self.ppgReadStartTime!
            let kBperS = (Double(self.ppgByteReadCount) / 1000.0) / elapsedTime
            print("PPG trasmission rate = \(kBperS)kB/s")
            print("Example PPG values = \(values)")
            
            // Refresh the stats
            self.ppgReadStartTime = Date().timeIntervalSince1970
            self.ppgByteReadCount = 0
        }
    }
    
    func updateOBAccel(with values: [UInt8]) {
        if self.accReadStartTime == nil {
            self.accReadStartTime = Date().timeIntervalSince1970
        }
        accByteReadCount += values.count
        
        // Log the trasmission rate about every 1 second, assuming 4kB/s
        if (self.accByteReadCount % (values.count * 250) == 0) {
            let elapsedTime = Date().timeIntervalSince1970 - self.accReadStartTime!
            let kBperS = (Double(self.accByteReadCount) / 1000.0) / elapsedTime
            print("Accelerometer trasmission rate = \(kBperS)kB/s")
            print("Example Accelerometer values = \(values)")
            
            // Refresh the stats
            self.accReadStartTime = Date().timeIntervalSince1970
            self.accByteReadCount = 0
        }
    }
    
    func updatePolarEcg(for data: PolarBleSdk.PolarEcgData) {
        if self.polarEcgReadStartTime == nil {
            self.polarEcgReadStartTime = Date().timeIntervalSince1970
        }
        let previousModCount = self.polarEcgByteReadCount % 1000
        self.polarEcgByteReadCount += data.samples.count
        
        // Log the trasmission rate about every 1000 samples
        if (self.polarEcgByteReadCount % 1000) != previousModCount {
            let elapsedTime = Date().timeIntervalSince1970 - self.polarEcgReadStartTime!
            let kBperS = Double(self.polarEcgByteReadCount) / elapsedTime
            print("Polar ECG trasmission rate = \(kBperS)samples/s")
            print("µV: \(data.samples)")
            
            // Refresh the stats
            self.polarEcgReadStartTime = Date().timeIntervalSince1970
            self.polarEcgByteReadCount = 0
        }
    }
    
    func updatePolarAccel(for data: PolarBleSdk.PolarAccData) {
        if self.polarAccReadStartTime == nil {
            self.polarAccReadStartTime = Date().timeIntervalSince1970
        }
        let previousModCount = self.polarAccByteReadCount % 1000
        self.polarAccByteReadCount += data.samples.count
        
        // Log the trasmission rate about every 4000 samples
        if (self.polarAccByteReadCount % 1000) != previousModCount {
            let accSample = data.samples.first
            print("polar acc x: \(String(describing: accSample?.x)) y: \(String(describing: accSample?.y)) z: \(String(describing: accSample?.z))")
            let elapsedTime = Date().timeIntervalSince1970 - self.polarAccReadStartTime!
            let kBperS = Double(self.polarAccByteReadCount) / elapsedTime
            print("Polar ACC trasmission rate = \(kBperS)samples/s")
            
            
            // Refresh the stats
            self.polarAccReadStartTime = Date().timeIntervalSince1970
            self.polarAccByteReadCount = 0
        }
    }
}
