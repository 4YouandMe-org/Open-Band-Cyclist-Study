//
//  CompletedTestsDefaultsReport.swift
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

import BridgeApp

open class CompletedTestsDefaultsReport: UserDefaultsSingletonReport {
    
    lazy var dateFormatter: DateFormatter = {
      return NSDate.iso8601formatter()!
    }()

    var _current: CompletedTestList?
    var current: CompletedTestList? {
        if _current != nil { return _current }
        guard let jsonStr = self.defaults.data(forKey: "\(identifier)JsonValue") else { return nil }
        do {
            let previous = try TaskListScheduleManager.shared.jsonDecoder.decode(CompletedTestList.self, from: jsonStr)
            setCurrent(previous)
            return previous
        } catch {
            debugPrint("Error decoding reminders json \(error)")
        }
        return nil
    }
    func setCurrent(_ item: CompletedTestList) {
        let sortedList = item.completed.sorted { test1, test2 in
            guard let date1 = self.dateFormatter.date(from: test1.completedOn),
                  let date2 = self.dateFormatter.date(from: test2.completedOn) else {
                      return false
                  }
            return date1.timeIntervalSince1970 > date2.timeIntervalSince1970
        }
        let sortedItem = CompletedTestList(completed: sortedList)
        _current = sortedItem
        do {
            let jsonData = try TaskListScheduleManager.shared.jsonEncoder.encode(sortedItem)
            self.defaults.set(jsonData, forKey: "\(identifier)JsonValue")
        } catch {
            print("Error converting reminders to JSON \(error)")
        }
    }
    
    public override init(identifier: RSDIdentifier) {
        super.init(identifier: RSDIdentifier.completedTestsIdentifier)
    }
    
    public init() {
        super.init(identifier: RSDIdentifier.completedTestsIdentifier)
    }
    
    open func append(identifier: String) {
        let completedOn = NSDate.iso8601formatter()!.string(from: Date())
        let test = CompletedTest(identifier: identifier, completedOn: completedOn)
        self.append(completedTest: test)
    }
    
    open func append(completedTest: CompletedTest) {
        var newArray = self.current?.completed ?? []
        newArray.append(completedTest)
        self.setCurrent(CompletedTestList(completed: newArray))
        self.syncToBridge()
    }
    
    open override func loadFromBridge(completion: @escaping ((String?) -> Void)) {
        
        guard !self.isSyncingWithBridge else { return }
        self.isSyncingWithBridge = true
        TaskListScheduleManager.shared.getSingletonReport(reportId: self.identifier) { (report, error) in
            
            self.isSyncingWithBridge = false
            
            guard error == nil else {
                let errorStr = "Error getting most recent completed tests \(String(describing: error))"
                completion(errorStr)
                print(errorStr)
                return
            }
            
            var bridgeItem = CompletedTestList(completed: [])
            if let bridgeJsonData = (report?.clientData as? String)?.data(using: .utf8) {
                do {
                    bridgeItem = try TaskListScheduleManager.shared.jsonDecoder.decode(CompletedTestList.self, from: bridgeJsonData)
                } catch {
                    let errorStr = "Error parsing clientData for completed tests report \(error)"
                    completion(errorStr)
                    print(errorStr)
                }
            }

            if let cached = self.current {
                // Merge the cached list with the server list
                let bridgeItemsNotInCache = bridgeItem.completed.filter { (test1) -> Bool in
                    return !cached.completed.contains { (test2) -> Bool in
                        return test1.completedOn == test2.completedOn
                    }
                }
                var newArray = cached.completed
                newArray.append(contentsOf: bridgeItemsNotInCache)
                self.setCurrent(CompletedTestList(completed: newArray))
            } else {
                self.setCurrent(bridgeItem)
            }
            
            // Let's sync our cached version with bridge if our local was out of sync
            if !self.isSyncedWithBridge {
                self.writeToBridge()
            }
            
            completion(nil)
        }
    }
            
    override open func syncToBridge() {
        // Setting this to false will trigger a write to bridge after a successful read
        self.isSyncedWithBridge = false
        self.loadFromBridge { (error) in }
    }
    
    private func writeToBridge() {
        guard let item = self.current else { return }
        do {
            let jsonData = try TaskListScheduleManager.shared.jsonEncoder.encode(item)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            let report = SBAReport(reportKey: self.identifier, date: SBAReportSingletonDate, clientData: jsonString as NSString)
            TaskListScheduleManager.shared.saveReport(report)
        } catch {
            print(error)
        }
    }
}

public struct CompletedTestList: Codable {
    var completed: Array<CompletedTest>
}

public struct CompletedTest: Codable {
    /// identifier of the test
    var identifier: String
    /// completedOn is the ISO 8601 date/time when this test was completed
    var completedOn: String
}
