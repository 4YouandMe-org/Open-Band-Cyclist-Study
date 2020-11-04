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

open class BleConnectionStepViewController: RSDStepViewController, BleConnectionRecorderDelegate {
    
    // These labels will be updated to reflect scanning and connection status
    @IBOutlet weak var polarStatusLabel: UILabel?
    @IBOutlet weak var openBandStatusLabel: UILabel?
    
    // Title labels for connection status'
    @IBOutlet weak var polarTitleLabel: UILabel?
    @IBOutlet weak var openBandTitleLabel: UILabel?
    
    var connectionRecorder: BleConnectionRecorder? {
        return self.taskController?.currentAsyncControllers.first(where: {$0 is BleConnectionRecorder}) as? BleConnectionRecorder
    }
    
    var includedTypes: [BleDeviceType] {
        self.connectionRecorder?.bleConnectionConfiguration?.deviceTypes ?? []
    }
    
    func includesDeviceType(type: BleDeviceType) -> Bool {
        return self.connectionRecorder?.bleConnectionConfiguration?.deviceTypes?.contains(type) ?? false
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.designSystem = AppDelegate.designSystem
        self.updateUiState()
        
        self.connectionRecorder?.connectionDelegate = self
        // TODO: mdephillips 10/22/20 recorder start function should trigger
        // ble connections, however need to sync with shannon why that isnt working
        // for now just start the ble connections in this class                
        BleConnectionManager.shared.delegate = self.connectionRecorder
        for type in self.includedTypes {
            BleConnectionManager.shared.connect(type: type)
        }
    }

    public func onBleDeviceConnectionChange(type: BleDeviceType, connected: Bool) {
        self.updateUiState()
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
        self.updateLabelVisibility()
    }
    
    public func updateLabelVisibility() {
        self.polarStatusLabel?.isHidden = !self.includesDeviceType(type: .polar)
        self.polarTitleLabel?.isHidden = !self.includesDeviceType(type: .polar)
        self.openBandStatusLabel?.isHidden = !self.includesDeviceType(type: .openBand)
        self.openBandTitleLabel?.isHidden = !self.includesDeviceType(type: .openBand)
    }
    
    public func updateNextButtonState() {
        var allConnected = true
        for type in self.includedTypes {
            if !(self.connectionRecorder?.isConnected(type: type) ?? false) {
                allConnected = false
            }
        }
        self.navigationFooter?.nextButton?.isEnabled = allConnected
    }
    
    public func updateOpenBandStatus() {
        if self.connectionRecorder?.isConnected(type: .openBand) ?? false {
            self.openBandStatusLabel?.text = "Connected"
        } else {
            self.openBandStatusLabel?.text = "Scanning..."
        }
    }
    
    public func updatePolarStatus() {
        if self.connectionRecorder?.isConnected(type: .polar) ?? false {
            self.polarStatusLabel?.text = "Connected"
        } else {
            self.polarStatusLabel?.text = "Scanning..."
        }
    }
}