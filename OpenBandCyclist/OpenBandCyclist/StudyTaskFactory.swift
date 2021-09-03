//
//  StudyTaskFactory.swift
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

import BridgeApp
import Research
import ResearchUI

extension RSDStepType {
    public static let bleConnection: RSDStepType = "bleConnection"
    
    // Onboarding and consent
    public static let consentReview: RSDStepType = "consentReview"
    public static let consentQuiz: RSDStepType = "consentQuiz"
    public static let onboardingInstruction: RSDStepType = "onboardingInstruction"
    public static let onboardingForm: RSDStepType = "onboardingForm"
}

extension RSDAsyncActionType {
    public static let polarBle: RSDAsyncActionType = "polarBle"
    public static let openBandBle: RSDAsyncActionType = "openBandBle"
    public static let bleConnections: RSDAsyncActionType = "bleConnections"
}

open class StudyTaskFactory: SBAFactory {
    
    /// Override the base factory to vend Open Band Cyclist specific step objects.
    override open func decodeStep(from decoder: Decoder, with type: RSDStepType) throws -> RSDStep? {
        switch type {
        case .bleConnection:
            return try BleConnectionStepObject(from: decoder)
        case .active:
            return try BleActiveUIStepObject(from: decoder)
        case .consentReview:
            return try ConsentReviewStepObject(from: decoder)
        case .consentQuiz:
            return try ConsentQuizStepObject(from: decoder)
        case .onboardingInstruction:
            return try OnboardingInstructionStepObject(from: decoder)
        case .onboardingForm:
            return try OnboardingFormStepObject(from: decoder)
        default:
            return try super.decodeStep(from: decoder, with: type)
        }
    }
    
    override open func decodeAsyncActionConfiguration(from decoder:Decoder, with typeName: String) throws -> RSDAsyncActionConfiguration? {
        
        // Look to see if there is a standard permission to map to this config.
        let type = RSDAsyncActionType(rawValue: typeName)
        switch type {
        case .polarBle:
            return try PolarBleRecorderConfiguration(from: decoder)
        case .openBandBle:
            return try OpenBandBleRecorderConfiguration(from: decoder)
        case .bleConnections:
            return try BleConnectionRecorderConfiguration(from: decoder)
        default:
            return try super.decodeAsyncActionConfiguration(from: decoder, with: typeName)
        }
    }
}
