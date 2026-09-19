namespace PerformanceLab.Workers.Jobs;

using Microsoft.Extensions.Logging;

public class CleanupJob(ILogger<CleanupJob> logger)
{
    public Task ExecuteAsync()
    {
        var memoryBefore = GC.GetTotalMemory(false);
        GC.Collect(1, GCCollectionMode.Optimized);
        var memoryAfter = GC.GetTotalMemory(false);

        logger.LogInformation(
            "[Hangfire Cleanup] Periodic GC cleanup executed at {Timestamp:O}. Memory: {Before} KB -> {After} KB",
            DateTime.UtcNow,
            memoryBefore / 1024,
            memoryAfter / 1024);

        return Task.CompletedTask;
    }
}
