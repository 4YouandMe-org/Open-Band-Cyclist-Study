//
//  ExternalIDRegistrationViewController.swift
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

open class ExternalIDRegistrationStep : RSDUIStepObject, RSDStepViewControllerVendor, RSDNavigationSkipRule {
    
    open func shouldSkipStep(with result: RSDTaskResult?, isPeeking: Bool) -> Bool {
        return BridgeSDK.authManager.isAuthenticated()
    }    
    
    open func instantiateViewController(with parent: RSDPathComponent?) -> (UIViewController & RSDStepController)? {
        return ExternalIDRegistrationViewController(step: self, parent: parent)
    }
}

open class ExternalIDRegistrationViewController: RSDStepViewController, UITextFieldDelegate {
    
    /// Title label for external ID entry
    @IBOutlet public var titleLabel: UILabel!
    
    /// Text label for external ID entry
    @IBOutlet public var textLabel: UILabel!
    
    /// Textfield for external ID entry
    @IBOutlet public var textField: UITextField!
    
    /// The textfield underline
    @IBOutlet public var ruleView: UIView!
    
    /// The submit button
    @IBOutlet public var submitButton: RSDRoundedButton!
    
    /// The submit button
    @IBOutlet public var helpButton: RSDUnderlinedButton!
    
    /// The loading spinner
    @IBOutlet public var loadingSpinner: UIActivityIndicatorView!
    
    /// The number of digits for the external ID
    let externalIdDigitCount = 3
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // Looks for single taps to dismiss keyboard
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        self.designSystem = AppDelegate.designSystem
        let background = self.designSystem.colorRules.backgroundLight
        let primaryBackground = self.designSystem.colorRules.backgroundPrimary
        self.view.backgroundColor = background.color
        let upperContentView = self.view.subviews.first?.subviews.first
        upperContentView?.backgroundColor = primaryBackground.color
        
        self.textField.font = self.designSystem.fontRules.font(for: .smallNumber, compatibleWith: traitCollection)
        self.textField.textColor = self.designSystem.colorRules.textColor(on: background, for: .smallNumber)
        self.textField.delegate = self
        
        self.ruleView.backgroundColor = self.designSystem.colorRules.textColor(on: background, for: .largeBody)
        
        self.submitButton.setDesignSystem(self.designSystem, with: self.designSystem.colorRules.backgroundLight)
        self.submitButton.setTitle(Localization.localizedString("BUTTON_DONE"), for: .normal)
        self.submitButton.isEnabled = false
        
        self.helpButton.setDesignSystem(self.designSystem, with: self.designSystem.colorRules.backgroundLight)
        self.helpButton.setTitle(Localization.localizedString("EXTERNAL_ID_HELP_TITLE"), for: .normal)
        
        self.titleLabel.text = Localization.localizedString("EXTERNAL_ID_TITLE")
        self.titleLabel.font = self.designSystem.fontRules.font(for: .largeHeader)
        self.titleLabel.textColor = self.designSystem.colorRules.textColor(on: background, for: .largeHeader)
        
        self.textLabel.text = Localization.localizedString("EXTERNAL_ID_TEXT")
        self.textLabel.font = self.designSystem.fontRules.font(for: .bodyDetail)
        self.textLabel.textColor = RSDColor.white
    }
    
    /// Calls this function when the tap is recognized.
    @objc func dismissKeyboard() {
        //Causes the view (or one of its embedded text fields) to resign the first responder status.
        view.endEditing(true)
        self.view.frame.origin.y = 0
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        // un-comment if you need textfield to move up
//        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
//            self.view.frame.origin.y -= keyboardSize.height
//        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        // un-comment if you need textfield to reverse move
        //self.view.frame.origin.y = 0
    }
    
    func externalId() -> String? {
        return self.textField.text
    }
    
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let text = textField.text,
            let textRange = Range(range, in: text) {
            let updatedText = text.replacingCharacters(in: textRange, with: string)
            self.submitButton.isEnabled = updatedText.count >= externalIdDigitCount
            if updatedText.count == externalIdDigitCount {
                /// After the user types in the 3rd digit with keyboard, dismiss keyboard to show submit button after a quarter of a second
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
                   self.textField.resignFirstResponder()
                })
            }
            return updatedText.count <= externalIdDigitCount
        }
        return true
    }
    
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return self.textField.endEditing(false)
    }
    
    func signUpAndSignIn(completion: @escaping SBBNetworkManagerCompletionBlock) {
        guard let externalId = self.externalId(), !externalId.isEmpty else { return }
        
        let signUp: SBBSignUp = SBBSignUp()
        signUp.checkForConsent = true
        signUp.externalId = "Test\(externalId)"
        signUp.password = "\(externalId)foo#$H0"   // Add some additional characters match password requirements
        signUp.dataGroups = ["test_user"]
        signUp.sharingScope = "all_qualified_researchers"
        
        BridgeSDK.authManager.signUpStudyParticipant(signUp, completion: { (task, result, error) in
            
            guard error == nil else {
                completion(task, result, error)
                return
            }
            
            // we're signed up so sign in
            BridgeSDK.authManager.signIn(withExternalId: signUp.externalId!, password: signUp.password!, completion: { (task, result, error) in
                completion(task, result, error)
            })
        })
    }
    
    @IBAction func submitTapped() {
        DispatchQueue.main.async {
            self.submitButton.isEnabled = false
            self.loadingSpinner.isHidden = false
        }
       self.signUpAndSignIn { (task, result, error) in
            DispatchQueue.main.async {
                self.loadingSpinner.isHidden = true
                self.submitButton.isEnabled = true
                if error == nil {
                   self.goForward()
                } else {
                    self.presentAlertWithOk(title: "Error attempting sign in", message: error!.localizedDescription, actionHandler: nil)
                    // TODO: emm 2018-04-25 handle error from Bridge
                    // 400 is the response for an invalid external ID
                    debugPrint("Error attempting to sign up and sign in:\n\(String(describing: error))\n\nResult:\n\(String(describing: result))")
                }
            }
        }
    }
    
    @IBAction func helpButtonTapped() {
        let alert = UIAlertController(title: Localization.localizedString("EXTERNAL_ID_HELP_TITLE"), message: Localization.localizedString("EXTERNAL_ID_HELP_TEXT"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localization.localizedString("BUTTON_OK"), style: .default, handler: nil))
        self.present(alert, animated: true)
    }
}
