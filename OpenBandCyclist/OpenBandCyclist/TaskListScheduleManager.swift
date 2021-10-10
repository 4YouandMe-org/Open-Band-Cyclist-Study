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

import UIKit
import CoreData
import BridgeApp
import BridgeAppUI
import BridgeSDK
import Research
import ResearchUI

public extension RSDIdentifier {
    // Measuring tasks
    static let cyclingTask: RSDIdentifier  = "Cycling"
    static let sleepingTask: RSDIdentifier = "Sleeping"
    static let sittingTask: RSDIdentifier  = "Sitting"
    static let walkingTask: RSDIdentifier  = "Walking"
    static let completedTestsIdentifier: RSDIdentifier  = "CompletedTests"
}

/// Subclass the schedule manager to set up a predicate to filter the schedules.
public class TaskListScheduleManager {
    
    public static let shared = TaskListScheduleManager()
    
    private let kDataGroups                       = "dataGroups"
    private let kSchemaRevisionKey                = "schemaRevision"
    private let kSurveyCreatedOnKey               = "surveyCreatedOn"
    private let kSurveyGuidKey                    = "surveyGuid"
    private let kExternalIdKey                    = "externalId"

    private let kMetadataFilename                 = "metadata.json"
    
    let kReportDateKey = "reportDate"
    let kReportTimeZoneIdentifierKey = "timeZoneIdentifier"
    let kReportClientDataKey = "clientData"
    
    open var appType: String {
        return "HASD"
    }
    
    /// For encoding report client data
    lazy var jsonEncoder: JSONEncoder = {
        return JSONEncoder()
    }()
    
    /// For decoding report client data
    lazy var jsonDecoder: JSONDecoder = {
        return JSONDecoder()
    }()
    
    var defaults: UserDefaults {
        return UserDefaults.standard
    }
    
    /// Pointer to the shared participant manager.
    public var participantManager: SBBParticipantManagerProtocol {
        return BridgeSDK.participantManager
    }
    
    /// Pointer to the default factory to use for serialization.
    open var factory: RSDFactory {
        return SBAFactory.shared
    }
    
    public let completedTests = CompletedTestsDefaultsReport()
    public var completedTestList: Array<CompletedTest> {
        return self.completedTests.current?.completed ?? []
    }
    
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
        return self.completedTestList.filter({ $0.identifier == taskIdentifier }).count
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
        return self.image(for: taskId.rawValue)
    }
    
    ///
    /// - parameter taskId: that you are looking for the image to represent
    ///
    /// - returns: the image associated with the task identifier
    ///
    open func image(for taskIdentifier: String) -> UIImage? {
        switch taskIdentifier {
        case RSDIdentifier.cyclingTask.rawValue:
            return UIImage(named: "ActivityCycling")
        case RSDIdentifier.sleepingTask.rawValue:
            return UIImage(named: "ActivitySleeping")
        case RSDIdentifier.sittingTask.rawValue:
            return UIImage(named: "ActivitySitting")
        case RSDIdentifier.walkingTask.rawValue:
            return UIImage(named: "ActivityWalking")
        default:
            return UIImage(named: taskIdentifier)
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
    
    /// This should only be called by the sign-in controller or when the app loads
    public func forceReloadCompletedTestData(completion: @escaping ((String?) -> Void)) {
        self.completedTests.loadFromBridge(completion: completion)
    }
    
    open func loadHistoryFromBridge(completed: @escaping ((String?) -> Void)) {
        let identifier = RSDIdentifier.completedTestsIdentifier
        self.getSingletonReport(reportId: identifier) { (report, error) in
            if (error != nil) {
                completed(error)
            }
            completed(nil)
        }
    }
    
    func getSingletonReport(reportId: RSDIdentifier, completion: @escaping (_ report: SBAReport?, _ error: String?) -> Void) {
        // Make sure we cover the ReportSingletonDate no matter what time zone or BridgeApp version it was created in
        // and no matter what time zone it's being retrieved in:
        let fromDateComponents = Date(timeIntervalSince1970: -48 * 60 * 60).dateOnly()
        let toDateComponents = Date(timeIntervalSinceReferenceDate: 48 * 60 * 60).dateOnly()
        
        self.participantManager.getReport(reportId.rawValue, fromDate: fromDateComponents, toDate: toDateComponents) { (obj, error) in
            
            if error != nil {
                DispatchQueue.main.async {
                    completion(nil, error?.localizedDescription)
                }
                return
            }
            
            if let sbbReport = (obj as? [SBBReportData])?.last,
               let report = self.transformReportData(sbbReport, reportKey: reportId, category: SBAReportCategory.singleton) {
                DispatchQueue.main.async {
                    completion(report, nil)
                }
                return
            }
                                    
            DispatchQueue.main.async {
                completion(nil, nil)
            }
        }
    }
    
    public func uploadTask(taskViewModel: RSDTaskViewModel) {        
        var filesToUpload = [URL]()
        
        // Let's get all the files that were saved during the test
        taskViewModel.taskResult.stepHistory.forEach { (result) in
            if let fileResult = result as? RSDFileResultObject,
                let url = fileResult.url {
                filesToUpload.append(url)
            }
        }
        
        let identifier = taskViewModel.task!.identifier
        // Upload to Bridge as an ecrypted archive
        self.uploadData(identifier: identifier, data: filesToUpload)
        // Upload to Bridge as a report
        self.completedTests.append(identifier: identifier)
    }
    
    private func removeFile(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Successfully deleted file: \(url.absoluteURL)")
        } catch let error as NSError {
            print("Error deleting file: \(error.domain)")
        }
    }
    
    private func uploadData(identifier: String, data: [URL]?, dataName: String = "data.json", answersMap: [String: Any] = [:]) {

        let archive = SBBDataArchive(reference: identifier, jsonValidationMapping: nil)
        
        do {
            // Write all files to the archive
            data?.forEach({ (url) in
                archive.insertURL(intoArchive: url, fileName: url.lastPathComponent)
            })
            
            var metadata = [String: Any]()
            
            // Add answers dictionary data
            var mutableMap = [String: Any]()
            if let externalId = SBAParticipantManager.shared.studyParticipant?.externalId {
                metadata[kExternalIdKey] = externalId
            }
            
            answersMap.forEach({
                mutableMap[$0.key] = $0.value
            })
            archive.insertAnswersDictionary(mutableMap)
            
            // Add the current data groups and the user's arc id
            if let dataGroups = SBAParticipantManager.shared.studyParticipant?.dataGroups {
                metadata[kDataGroups] = dataGroups.joined(separator: ",")
            }
            // Insert the metadata dictionary
            archive.insertDictionary(intoArchive: metadata, filename: kMetadataFilename, createdOn: Date())
            
            // Set the correct schema revision version, this is required
            // for bridge to know that this archive has a schema
            let schemaRevisionInfo = SBABridgeConfiguration.shared.schemaInfo(for: identifier) ?? RSDSchemaInfoObject(identifier: identifier, revision: 1)
            archive.setArchiveInfoObject(schemaRevisionInfo.schemaVersion, forKey: kSchemaRevisionKey)
            
            try archive.complete()
            archive.encryptAndUploadArchive()
        } catch let error as NSError {
          print("Error while converting test to upload format \(error)")
        }
    }
    
    public func saveReport(_ report: SBAReport, completion: SBBParticipantManagerCompletionBlock?) {
        
        let reportIdentifier = report.reportKey.stringValue
        let bridgeReport = SBBReportData()

        // For a singleton, always set the date to a dateString that is the singleton date
        // in UTC timezone. This way it will always write to the report using that date.
        bridgeReport.data = report.clientData
        let formatter = NSDate.iso8601DateOnlyformatter()!
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let reportDate = SBAReportSingletonDate
        
        bridgeReport.localDate = formatter.string(from: reportDate)
        
        // Before we save the newest report, set it to need synced if its the completed tests
        if (reportIdentifier == RSDIdentifier.completedTestsIdentifier) {
            self.completedTests.isSyncedWithBridge = false
        }
        
        self.participantManager.save(bridgeReport, forReport: reportIdentifier) { [weak self] (_, error) in
            DispatchQueue.main.async {
                guard error == nil else {
                    print("Failed to save report: \(String(describing: error?.localizedDescription))")
                    self?.failedToSaveReport(report)
                    completion?(nil, error)
                    return
                }
                self?.successfullySavedReport(report)
                completion?(nil, nil)
            }
        }
    }
    
    /// Save an individual report to Bridge.
    ///
    /// - parameter report: The report object to save to Bridge.
    public func saveReport(_ report: SBAReport) {
        self.saveReport(report, completion: nil)
    }
    
    open func failedToSaveReport(_ report: SBAReport) {
        if (report.reportKey == RSDIdentifier.completedTestsIdentifier) {
            self.completedTests.isSyncedWithBridge = false
        }
    }
    
    open func successfullySavedReport(_ report: SBAReport) {
        if (report.reportKey == RSDIdentifier.completedTestsIdentifier) {
            self.completedTests.isSyncedWithBridge = true
        }
    }
    
    open func newReport(reportIdentifier: String, date: Date, clientData: SBBJSONValue) -> SBAReport {
        let reportDate = SBAReportSingletonDate
        let timeZone = TimeZone(secondsFromGMT: 0)!
        
        return SBAReport(reportKey: RSDIdentifier(rawValue: reportIdentifier),
            date: reportDate,
            clientData: clientData,
            timeZone: timeZone)
    }
    
    open func transformReportData(_ report: SBBReportData, reportKey: RSDIdentifier, category: SBAReportCategory) -> SBAReport? {
        guard let reportData = report.data, let date = report.date else { return nil }
        
        if let json = reportData as? [String : Any],
            let clientData = json[kReportClientDataKey] as? SBBJSONValue,
            let dateString = json[kReportDateKey] as? String,
            let timeZoneIdentifier = json[kReportTimeZoneIdentifierKey] as? String {
            let reportDate = self.factory.decodeDate(from: dateString) ?? date
            let timeZone = TimeZone(identifier: timeZoneIdentifier) ??
                TimeZone(iso8601: dateString) ??
                TimeZone.current
            return SBAReport(reportKey: reportKey, date: reportDate, clientData: clientData, timeZone: timeZone)
        }
        else {
            switch category {
            case .timestamp, .groupByDay:
                return SBAReport(reportKey: reportKey, date: date, clientData: reportData, timeZone: TimeZone.current)
                
            case .singleton:
                let timeZone = TimeZone(secondsFromGMT: 0)!
                let reportDate: Date = {
                    if let localDate = report.localDate {
                        let dateFormatter = NSDate.iso8601DateOnlyformatter()!
                        dateFormatter.timeZone = timeZone
                        return dateFormatter.date(from: localDate) ?? date
                    }
                    else {
                        return date
                    }
                }()
                return SBAReport(reportKey: reportKey, date: reportDate, clientData: reportData, timeZone: timeZone)
            }
        }
    }
}

open class UserDefaultsSingletonReport {
    var defaults: UserDefaults {
        return TaskListScheduleManager.shared.defaults
    }
    
    var isSyncingWithBridge = false
    var identifier: RSDIdentifier
    
    var isSyncedWithBridge: Bool {
        get {
            let key = "\(identifier.rawValue)SyncedToBridge"
            if self.defaults.object(forKey: key) == nil {
                return true // defaults to synced with bridge
            }
            return self.defaults.bool(forKey: "\(identifier.rawValue)SyncedToBridge")
        }
        set {
            self.defaults.set(newValue, forKey: "\(identifier.rawValue)SyncedToBridge")
        }
    }
    
    public init(identifier: RSDIdentifier) {
        self.identifier = identifier
    }
    
    // String? is the error message
    open func loadFromBridge(completion: @escaping ((String?) -> Void)) {
        // to be implemented by sub-class
    }
    
    open func syncToBridge() {
        // to be implemented by sub-class
    }
}
