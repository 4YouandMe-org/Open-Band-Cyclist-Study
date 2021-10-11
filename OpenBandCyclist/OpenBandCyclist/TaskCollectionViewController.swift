//
//  TaskCollectionViewController.swift
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

class TaskCollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, TaskCollectionViewCellDelegate, RSDTaskViewControllerDelegate {
    
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var signUpButton: UIButton?
    @IBOutlet weak var collectionView: UICollectionView!
    
    let gridLayout = RSDVerticalGridCollectionViewFlowLayout()
    let collectionViewReusableCell = "TaskCollectionViewCell"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.updateDesignSystem()
        self.setupCollectionView()
        
        // Register the 30 second walking task with the motor control framework
        SBABridgeConfiguration.shared.addMapping(with: MCTTaskInfo(.walk30Seconds).task)
        
        // Reload the completed tests from bridge
        let taskCount = TaskListScheduleManager.shared.completedTestList.count
        TaskListScheduleManager.shared.completedTests.loadFromBridge { [weak self] (error) in
            if (error == nil) {
                DispatchQueue.main.async {
                    if (taskCount != TaskListScheduleManager.shared.completedTestList.count) {
                        self?.collectionView.reloadData()
                    }
                }
            }
        }
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Set the collection view width for the layout,
        // so it knows how to calculate the cell size.
        self.gridLayout.collectionViewWidth = self.collectionView.bounds.width
        // Refresh collection view sizes
        self.setupCollectionViewSizes()
        
        self.gridLayout.itemCount = TaskListScheduleManager.shared.tableRowCount
        self.collectionView.reloadData()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Disconnect if they are connected to protect state
        BleConnectionManager.shared.disconnect(type: .openBand)
        BleConnectionManager.shared.disconnect(type: .polar)
    }
    
    func updateDesignSystem() {
        let designSystem = AppDelegate.designSystem
        
        self.view.backgroundColor = designSystem.colorRules.backgroundPrimary.color
        headerView?.backgroundColor = AppDelegate.designSystem.colorRules.palette.accent.normal.color
    }
    
    // MARK: UICollectionView setup and delegates

    fileprivate func setupCollectionView() {
        self.setupCollectionViewSizes()
        
        self.collectionView.collectionViewLayout = self.gridLayout
    }
    
    fileprivate func setupCollectionViewSizes() {
        self.gridLayout.columnCount = 2
        self.gridLayout.horizontalCellSpacing = 16
        self.gridLayout.cellHeightAbsolute = 180
        // This matches the collection view's top inset
        self.gridLayout.verticalCellSpacing = 16
    }
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.gridLayout.sectionCount
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.gridLayout.itemCountInGridRow(gridRow: section)
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return self.gridLayout.cellSize(for: indexPath)
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
       
      var sectionInsets = self.gridLayout.secionInset(for: section)
      // Default behavior of grid layout is to have no top vertical spacing
      // but we want that for this UI, so add it back in
      if section == 0 {
        sectionInsets.top = self.gridLayout.verticalCellSpacing
      }
      return sectionInsets
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = self.collectionView.dequeueReusableCell(withReuseIdentifier: self.collectionViewReusableCell, for: indexPath)
        
        // The grid layout stores items as (section, row),
        // so make sure we use the grid layout to get the correct item index.
        let itemIndex = self.gridLayout.itemIndex(for: indexPath)
        let taskId = TaskListScheduleManager.shared.taskId(for: itemIndex)
        let translatedIndexPath = IndexPath(item: itemIndex, section: 0)

        if let taskCell = cell as? TaskCollectionViewCell {
            taskCell.setDesignSystem(AppDelegate.designSystem, with: RSDColorTile(RSDColor.white, usesLightStyle: true))
            
            taskCell.delegate = self
            
            let title = TaskListScheduleManager.shared.title(for: itemIndex)
            let text = TaskListScheduleManager.shared.text(for: itemIndex)
            let image = TaskListScheduleManager.shared.image(for: itemIndex)
            let progress = TaskListScheduleManager.shared.completedProgress(for: itemIndex)

            taskCell.setItemIndex(itemIndex: translatedIndexPath.item, taskId: taskId, title: title, text: text, image: image, completionProgress: progress)
        }

        return cell
    }
    
    // MARK: MeasureTabCollectionViewCell delegate
    
    func didTapItem(for itemIndex: Int) {
        self.runTask(at: itemIndex)
    }
    
    func runTask(at itemIndex: Int) {
        let taskInfo = TaskListScheduleManager.shared.taskInfo(for: itemIndex)
        let taskViewModel = RSDTaskViewModel(taskInfo: taskInfo)
        let taskVc = RSDTaskViewController(taskViewModel: taskViewModel)
        taskVc.modalPresentationStyle = .fullScreen
        taskVc.delegate = self
        self.present(taskVc, animated: true, completion: nil)
    }        

    func taskController(_ taskController: RSDTaskController, didFinishWith reason: RSDTaskFinishReason, error: Error?) {

        // dismiss the view controller
        (taskController as? UIViewController)?.dismiss(animated: true, completion: nil)
    }
        
    func taskController(_ taskController: RSDTaskController, readyToSave taskViewModel: RSDTaskViewModel) {
        // Do not save or upload the data for the screening app
        TaskListScheduleManager.shared.uploadTask(taskViewModel: taskViewModel)
        // Update the UI
        self.collectionView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 112.0
    }
    
    /// Here we can customize which VCs show for a step within a survey
    func taskViewController(_ taskViewController: UIViewController, viewControllerForStep stepModel: RSDStepViewModel) -> UIViewController? {
        return nil
    }
}

open class TaskTableHeaderView: UIView {
}

/// `TaskCollectionViewCell` shows a vertically stacked image icon, title button, and title label.
@IBDesignable open class TaskCollectionViewCell: RSDDesignableCollectionViewCell {

    weak var delegate: TaskCollectionViewCellDelegate?
    
    let kCollectionCellVerticalItemSpacing = CGFloat(6)
    
    @IBOutlet public var titleLabel: UILabel?
    @IBOutlet public var textLabel: UILabel?
    @IBOutlet public var imageView: UIImageView?
    @IBOutlet public var progressDial: RSDCountdownDial?
    
    var itemIndex: Int = -1

    func setItemIndex(itemIndex: Int, taskId: RSDIdentifier, title: String?, text: String?, image: UIImage?, completionProgress: Float) {
        self.itemIndex = itemIndex
        
        if self.titleLabel?.text != title {
            // Check for same title, to avoid UILabel flash update animation
            self.titleLabel?.text = title
        }
        
        if self.textLabel?.text != text {
            // Check for same title, to avoid UILabel flash update animation
            self.textLabel?.text = text
        }
        
        self.imageView?.image = image
        self.progressDial?.progress = CGFloat(completionProgress)
        
        // The colors of the cell are dynamic based on the task
        // let designSystem = self.designSystem ?? RSDDesignSystem()
        self.progressDial?.ringColor = UIColor(hexString: "#EDEDED") ?? UIColor.white
        self.progressDial?.innerColor = UIColor(hexString: "#DAF5F6") ?? UIColor.white
        self.progressDial?.progressColor = UIColor(hexString: "#AFDDDF") ?? UIColor.white
    }

    private func updateColorsAndFonts() {
        let designSystem = self.designSystem ?? RSDDesignSystem()
        let background = self.backgroundColorTile ?? RSDGrayScale().white
        let contentTile = designSystem.colorRules.tableCellBackground(on: background, isSelected: isSelected)

        contentView.backgroundColor = contentTile.color
        titleLabel?.textColor = designSystem.colorRules.textColor(on: contentTile, for: .microDetail)
        titleLabel?.font = designSystem.fontRules.baseFont(for: .microDetail)
    
        textLabel?.textColor = designSystem.colorRules.textColor(on: contentTile, for: .microDetail)
        textLabel?.font = designSystem.fontRules.baseFont(for: .microDetail)
    }

    override open func setDesignSystem(_ designSystem: RSDDesignSystem, with background: RSDColorTile) {
        super.setDesignSystem(designSystem, with: background)
        updateColorsAndFonts()
    }
    
    @IBAction func touchDown() {
        self.progressDial?.alpha = 0.5
        self.progressDial?.hasShadow = false
    }
    
    @IBAction func touchUp() {
        self.progressDial?.alpha = 1.0
        self.progressDial?.hasShadow = true
    }
    
    @IBAction func cellSelected() {
        self.delegate?.didTapItem(for: self.itemIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: { [weak self] in
            self?.touchUp()
        })
    }
}

protocol TaskCollectionViewCellDelegate: AnyObject {
    func didTapItem(for itemIndex: Int)
}
