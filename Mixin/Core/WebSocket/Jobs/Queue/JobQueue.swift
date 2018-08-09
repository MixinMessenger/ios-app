import Foundation
import UIKit

class JobQueue {

    internal let queue = OperationQueue()

    init(maxConcurrentOperationCount: Int) {
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    func cancelAllOperations() {
        queue.cancelAllOperations()
    }

    func suspend() {
        queue.isSuspended = true
    }

    func resume() {
        queue.isSuspended = false
    }

    @discardableResult
    func addJob(job: BaseJob) -> Bool {
        guard AccountAPI.shared.didLogin else {
            return false
        }
        let jobId = job.getJobId()
        guard !isExistJob(jodId: jobId) else {
            if jobId.hasPrefix("refresh-") || jobId.hasPrefix("file-") || jobId.hasPrefix("attachment-") {
                return false
            }
            var userInfo = UIApplication.getTrackUserInfo()
            userInfo["jobId"] = jobId
            userInfo["debugDescription"] = job.debugDescription
            UIApplication.trackError("JobQueue", action: "addJob failded", userInfo: userInfo)
            return false
        }
        queue.addOperation(job)
        if WebSocketService.shared.connected && queue.isSuspended {
            UIApplication.trackError("JobQueue", action: "job queue suspended", userInfo: ["operationCount" : queue.operationCount])
            resume()
        }
        return true
    }

    @discardableResult
    func cancelJob(jobId: String) -> Bool {
        guard let job = findJobById(jodId: jobId) else {
            return false
        }
        job.cancel()
        return true
    }

    func findJobById(jodId: String) -> BaseJob? {
        return queue.operations.first { (operation) -> Bool in
            return (operation as? BaseJob)?.getJobId() == jodId
        } as? BaseJob
    }

    func isExistJob(jodId: String) -> Bool {
        guard queue.operations.count > 0 else {
            return false
        }
        return queue.operations.contains(where: { (operation) -> Bool in
            (operation as? BaseJob)?.getJobId() == jodId && !operation.isCancelled
        })
    }
}

