import BackgroundTasks

/// Manages `BGAppRefreshTask` registration and scheduling so the backup engine
/// can process its queue even when the app is not in the foreground.
///
/// The system decides the actual launch time; `earliestBeginDate` is only a hint.
/// Each refresh handler re-schedules itself before doing work, so the chain never breaks.
enum BackgroundTaskService {
    static let refreshIdentifier = "com.yogesh.AzureGallery.backgroundRefresh"

    /// Register the background refresh handler with `BGTaskScheduler`.
    /// Must be called before the app finishes launching (i.e. inside the `.task` modifier
    /// of `AzureGalleryApp`, after DB setup).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    /// Submit a request for the next background refresh, ~15 minutes from now.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh() // schedule next before processing

        let workTask = Task {
            await BackupEngine.shared.processQueue()
        }

        task.expirationHandler = { workTask.cancel() }

        Task {
            await workTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
