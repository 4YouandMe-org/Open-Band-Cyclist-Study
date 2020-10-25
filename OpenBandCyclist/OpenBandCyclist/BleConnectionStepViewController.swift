//
//  BleConnectionStepViewController.swift
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

import UIKit
import ResearchUI
import Research
import BridgeSDK
import BridgeApp

class BleConnectionStepObject : RSDUIStepObject, RSDStepViewControllerVendor {
    
    /// Default type is `.digitalJarOpenInstruction`.
    open override class func defaultType() -> RSDStepType {
        return .bleConnection
    }
    
    open func instantiateViewController(with parent: RSDPathComponent?) -> (UIViewController & RSDStepController)? {
        return BleConnectionStepViewController(step: self, parent: parent)
    }
}

open class BleConnectionStepViewController: RSDStepViewController, PolarBleRecorderDelegate, OpenBandBleRecorderDelegate {
    
    // These labels will be updated to reflect scanning and connection status
    @IBOutlet weak var polarStatusLabel: UILabel?
    @IBOutlet weak var openBandStatusLabel: UILabel?
    
    var polarRecorder: PolarBleRecorder? {
        return self.taskController?.currentAsyncControllers.first(where: {$0 is PolarBleRecorder}) as? PolarBleRecorder
    }
    
    var openBandRecorder: OpenBandBleRecorder? {
        return self.taskController?.currentAsyncControllers.first(where: {$0 is OpenBandBleRecorder}) as? OpenBandBleRecorder
    }
    
//    /// Override the default background for all the placements
//    open override func defaultBackgroundColorTile(for placement: RSDColorPlacement) -> RSDColorTile {
//        if placement == .header || placement == .footer {
//            return RSDColorTile(RSDColor.clear, usesLightStyle: false)
//        } else {
//            return self.designSystem.colorRules.palette?.grayScale.veryLightGray ?? RSDColorTile(RSDColor.white, usesLightStyle: false)
//        }
//    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.designSystem = AppDelegate.designSystem
        
        self.openBandRecorder?.openBandDelegate = self
        if !(self.openBandRecorder?.isConnected ?? false) {
            self.openBandRecorder?.autoConnectBleDevice()
        }
        
        self.polarRecorder?.polarDelegate = self
        if !(self.polarRecorder?.isConnected ?? false) {
            // Initiate connection and wait for response
            self.polarRecorder?.autoConnectBleDevice()
        }
    }
    
    public func onConnectionChange(recorder: PolarBleRecorder) {
        self.updateUiState()
    }
    
    public func onConnectionChange(recorder: OpenBandBleRecorder) {
        self.updateUiState()
    }
    
    override open func setupFooter(_ footer: RSDNavigationFooterView) {
        super.setupFooter(footer)
        self.updateUiState()
    }
    
    public func updateUiState() {
        self.updatePolarStatus()
        self.updateOpenBandStatus()
        self.updateNextButtonState()
    }
    
    public func updateNextButtonState() {
        if (self.openBandRecorder?.isConnected ?? false) &&
            (self.polarRecorder?.isConnected ?? false) {
            self.navigationFooter?.nextButton?.isEnabled = true
        } else {
            self.navigationFooter?.nextButton?.isEnabled = false
        }
    }
    
    public func updateOpenBandStatus() {
        if self.openBandRecorder?.isConnected ?? false {
            self.openBandStatusLabel?.text = "Connected"
        } else {
            self.openBandStatusLabel?.text = "Scanning..."
        }
    }
    
    public func updatePolarStatus() {
        if self.polarRecorder?.isConnected ?? false {
            self.polarStatusLabel?.text = "Connected"
        } else {
            self.polarStatusLabel?.text = "Scanning..."
        }
    }
}
