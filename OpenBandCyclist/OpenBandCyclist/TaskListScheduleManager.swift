//
//  TaskListScheduleManager.swift
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

import Foundation
import BridgeApp
import Research
import MotorControl

public extension RSDIdentifier {
    // Measuring tasks
    static let cyclingTask: RSDIdentifier  = "Cycling"
    static let sleepingTask: RSDIdentifier = "Sleeping"
    static let sittingTask: RSDIdentifier  = "Sitting"
    static let walkingTask: RSDIdentifier  = "Walking"
}

/// Subclass the schedule manager to set up a predicate to filter the schedules.
public class TaskListScheduleManager : SBAScheduleManager {
    
    // The number of completed tasks we want each user to complete for each type of task
    public let COMPLETED_COUNT_GOAL = 6
    
    public let tasks: [RSDIdentifier] = [.cyclingTask, .sleepingTask, .sittingTask, .walkingTask]
        
    ///
    /// - returns: the total table row count including activities
    ///         and the supplemental rows that go after them
    ///
    public var tableRowCount: Int {
        return self.tasks.count
    }
    
    public var tableSectionCount: Int {
        return 1
    }
    
    open func completedCount(for taskIdentifier: String) -> Int {
        // TODO: mdephillips get completed count from singleton report
        return Int.random(in: 0...6)
    }
    
    ///
    /// - parameter indexPath: from the table view
    ///
    /// - returns: the task info object for the task list row
    ///
    open func taskInfo(for itemIndex: Int) -> RSDTaskInfo {
        return RSDTaskInfoObject(with: self.tasks[itemIndex].rawValue)
    }
    
    open func taskId(for itemIndex: Int) -> RSDIdentifier {
        return self.tasks[itemIndex]
    }
    
    open func completedProgress(for itemIndex: Int) -> Float {
        let taskId = tasks[itemIndex]
        let completed = self.completedCount(for: taskId.rawValue)
        return Float(completed) / Float(COMPLETED_COUNT_GOAL)
    }
    
    ///
    /// - parameter itemIndex: pointing to an item in the list of sorted schedule items
    ///
    /// - returns: the image associated with the scheduled activity for the measure tab screen
    ///
    open func image(for itemIndex: Int) -> UIImage? {
        let taskId = tasks[itemIndex]
        switch taskId {
        case .cyclingTask:
            return UIImage(named: "ActivityCycling")
        case .sleepingTask:
            return UIImage(named: "ActivitySleeping")
        case .sittingTask:
            return UIImage(named: "ActivitySitting")
        case .walkingTask:
            return UIImage(named: "ActivityWalking")
        default:
            return UIImage(named: taskId.rawValue)
        }
    }
    
    ///
    /// - parameter itemIndex: from the collection view
    ///
    /// - returns: the title for the task list row
    ///
    open func title(for itemIndex: Int) -> String? {
        let taskId = tasks[itemIndex]
        let completed = self.completedCount(for: taskId.rawValue)
        if (completed >= COMPLETED_COUNT_GOAL) {
            return Localization.localizedString("ACTIVITY_COMPLETED")
        }
        let format = Localization.localizedString("ACTIVITY_%@_%@_COMPLETED")
        return String(format: format, String(completed), String(COMPLETED_COUNT_GOAL))
    }
    
    ///
    /// - parameter itemIndex: from the collection view
    ///
    /// - returns: the text for the task list row
    ///
    open func text(for itemIndex: Int) -> String? {
        let taskId = tasks[itemIndex]
        switch taskId {
        case .cyclingTask:
            return Localization.localizedString("ACTIVITY_CYCLING")
        case .sleepingTask:
            return Localization.localizedString("ACTIVITY_SLEEPING")
        case .sittingTask:
            return Localization.localizedString("ACTIVITY_SITTING")
        case .walkingTask:
            return Localization.localizedString("ACTIVITY_WALKING")
        default:
            return taskId.rawValue
        }
    }
}
