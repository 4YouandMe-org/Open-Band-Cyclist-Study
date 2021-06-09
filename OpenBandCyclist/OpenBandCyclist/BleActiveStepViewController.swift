//
//  BleActiveStepViewController.swift
//  OpenBandCyclist
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

import Research
import ResearchUI

open class BleActiveUIStepObject : RSDActiveUIStepObject, RSDStepViewControllerVendor {
    
    public func instantiateViewController(with parent: RSDPathComponent?) -> (UIViewController & RSDStepController)? {
        return BleActiveStepViewController(step: self, parent: parent)
    }
}

open class BleActiveStepViewController: RSDActiveStepViewController, RecorderStateDelegate {
        
    public func isRecordering() -> Bool {
        return true
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        // Debug trick to end the task early, can be useful to end sleep task
        self.countdownLabel?.isEnabled = true
        self.countdownLabel?.isUserInteractionEnabled = true
        self.countdownLabel?.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.longHoldCountdownLabel)))
    }
    
    override open func start() {
        super.start()
        
        // This is necessary to disable the audio session cancelling our task
        // when it moves into the background
        stopInterruptionObserver()
        
        BleConnectionManager.shared.recorderStateDelegate = self
    }
    
    @objc func longHoldCountdownLabel() {
        self.goForward()
    }
}
