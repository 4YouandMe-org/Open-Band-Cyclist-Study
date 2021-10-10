//
//  DataLogViewController.swift
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

open class DataLogViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    let cellReuseIdentifier = "DataLogTableViewCell"
    
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    lazy var dayTitleFormattor: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    lazy var timeTitleFormattor: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.updateDesignSystem()
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.refreshTableViewFromCache()
    }
    
    func updateDesignSystem() {
        let designSystem = AppDelegate.designSystem
        headerView?.backgroundColor = designSystem.colorRules.palette.accent.normal.color
    }
    
    func refreshTableViewFromCache() {
        self.tableView.reloadData()
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 88.0
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return TaskListScheduleManager.shared.completedTestList.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let designSystem = AppDelegate.designSystem
        
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath as IndexPath)
        guard let dataLogCell = cell as? DataLogTableViewCell else {
            return cell
        }
        
        let test = TaskListScheduleManager.shared.completedTestList[indexPath.row]
        dataLogCell.setDesignSystem(designSystem, with: RSDColorTile(RSDColor.white, usesLightStyle: false))
        
        let date = NSDate.iso8601formatter()!.date(from: test.completedOn) ?? Date()
        let dayTitle = dayTitleFormattor.string(from: date)
        let timeTitle = timeTitleFormattor.string(from: date)
        let image = TaskListScheduleManager.shared.image(for: test.identifier)
        dataLogCell.setItemIndex(itemIndex: indexPath.row, taskId: test.identifier, dayTitle: dayTitle, timeTitle: timeTitle, image: image)
        
        return dataLogCell
    }
}

open class DataLogTableViewCell: RSDDesignableTableViewCell {
    
    @IBOutlet public var dayLabel: UILabel?
    @IBOutlet public var timeLabel: UILabel?
    @IBOutlet public var iconView: UIImageView?
    @IBOutlet public var progressDial: RSDCountdownDial?
    
    var itemIndex: Int = -1

    func setItemIndex(itemIndex: Int, taskId: String, dayTitle: String?, timeTitle: String?, image: UIImage?) {
        self.itemIndex = itemIndex
        
        if self.timeLabel?.text != timeTitle {
            // Check for same title, to avoid UILabel flash update animation
            self.timeLabel?.text = timeTitle
        }
        
        if self.dayLabel?.text != dayTitle {
            // Check for same title, to avoid UILabel flash update animation
            self.dayLabel?.text = dayTitle
        }
        
        self.iconView?.image = image
        self.progressDial?.progress = CGFloat(1.0)
        
        // The colors of the cell are dynamic based on the task
        // let designSystem = self.designSystem ?? RSDDesignSystem()
        self.progressDial?.ringColor = UIColor(hexString: "#EDEDED") ?? UIColor.white
        switch taskId {
        case RSDIdentifier.cyclingTask.rawValue:
            self.progressDial?.innerColor = UIColor(hexString: "#7D8EAB") ?? UIColor.white
            self.progressDial?.progressColor = UIColor(hexString: "#4A5E81") ?? UIColor.white
        case RSDIdentifier.sleepingTask.rawValue:
            self.progressDial?.innerColor = UIColor(hexString: "#DAF5F6") ?? UIColor.white
            self.progressDial?.progressColor = UIColor(hexString: "#AFDDDF") ?? UIColor.white
        case RSDIdentifier.sittingTask.rawValue:
            self.progressDial?.innerColor = UIColor(hexString: "#F7CC7E") ?? UIColor.white
            self.progressDial?.progressColor = UIColor(hexString: "#F5B33C") ?? UIColor.white
        default: // .walkingTask
            self.progressDial?.innerColor = UIColor(hexString: "#F7CC7E") ?? UIColor.white
            self.progressDial?.progressColor = UIColor(hexString: "#F5B33C") ?? UIColor.white
        }
    }

    private func updateColorsAndFonts() {
        let designSystem = self.designSystem ?? RSDDesignSystem()
        let background = self.backgroundColorTile ?? RSDGrayScale().white
        let contentTile = designSystem.colorRules.tableCellBackground(on: background, isSelected: isSelected)

        contentView.backgroundColor = contentTile.color
        dayLabel?.textColor = designSystem.colorRules.textColor(on: contentTile, for: .body)
        dayLabel?.font = designSystem.fontRules.baseFont(for: .body)
        
        timeLabel?.textColor = designSystem.colorRules.textColor(on: contentTile, for: .body)
        timeLabel?.font = designSystem.fontRules.baseFont(for: .body)
    }

    override open func setDesignSystem(_ designSystem: RSDDesignSystem, with background: RSDColorTile) {
        super.setDesignSystem(designSystem, with: background)
        updateColorsAndFonts()
    }
}
