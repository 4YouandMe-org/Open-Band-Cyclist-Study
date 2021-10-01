//
//  HelpViewController.swift
//  OpenBandCyclist
//
//  Copyright © 2021 Sage Bionetworks. All rights reserved.
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
import BridgeApp
import BridgeSDK
import MotorControl

open class HelpViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var data: [HelpSection] = [
        HelpSection(title: "Additional Links:", links: [
            HelpLink(title: "Privacy Policy", url: "PrivacyPolicy.html"),
            HelpLink(title: "Licenses", url: "Licenses.html")
        ]),
        HelpSection(title: "Contact Us:", links: [
            HelpLink(title: "info@4youandme.org", url: "mailto:info@4youandme.org")
        ])
    ]
    
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    let cellReuseIdentifier = "HelpCell"
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        self.updateDesignSystem()
    }
    
    func updateDesignSystem() {
        let designSystem = AppDelegate.designSystem
        
        headerView?.backgroundColor = designSystem.colorRules.palette.accent.normal.color
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.data.count
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.data[section].title
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 64.0
    }
    
    public func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        let designSystem = AppDelegate.designSystem
        let header: UITableViewHeaderFooterView = view as! UITableViewHeaderFooterView
        header.tintColor = UIColor.white
        header.textLabel?.font = designSystem.fontRules.font(for: .xLargeHeader)
        header.textLabel?.textAlignment = NSTextAlignment.center
        header.textLabel?.backgroundColor = UIColor.white
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.data[section].links.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let designSystem = AppDelegate.designSystem
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath as IndexPath)
        let link = self.data[indexPath.section].links[indexPath.row]
        let underlineAttribute: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
            NSAttributedString.Key.foregroundColor: designSystem.colorRules.backgroundPrimary.color,
            NSAttributedString.Key.font: designSystem.fontRules.font(for: .largeHeader)
        ]
        let underlineAttributedString = NSAttributedString(string: link.title, attributes: underlineAttribute)
        cell.textLabel?.attributedText = underlineAttributedString
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let link = self.data[indexPath.section].links[indexPath.row]
        if (link.url.contains(".html")) {
            let webAction = RSDWebViewUIActionObject(url: link.url, buttonTitle: "Done")
            let (_, navVC) = RSDWebViewController.instantiateController(using: AppDelegate.designSystem, action: webAction)
            navVC.modalPresentationStyle = .popover
            self.show(navVC, sender: self)
        } else if (link.url.contains("mailto:")) {
            let mailToUrl = URL(string: link.url)!
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(mailToUrl)
            } else {
                UIApplication.shared.openURL(mailToUrl)
            }
        }
    }
}

struct HelpSection {
    var title: String
    var links: [HelpLink]
}

struct HelpLink {
    var title: String
    var url: String
}
