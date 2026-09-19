namespace PerformanceLab.Workers.Services;

using Hangfire;
using Hangfire.InMemory;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using PerformanceLab.Workers.Jobs;

public class HangfireBackgroundService(
    IServiceProvider serviceProvider,
    ILogger<HangfireBackgroundService> logger) : BackgroundService
{
    private BackgroundJobServer? _server;

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        GlobalConfiguration.Configuration
            .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
            .UseSimpleAssemblyNameTypeSerializer()
            .UseRecommendedSerializerSettings()
            .UseStorage(new InMemoryStorage())
            .UseActivator(new ServiceProviderJobActivator(serviceProvider));

        _server = new BackgroundJobServer();
        logger.LogInformation("[Hangfire] In-Memory Background Job Server started.");

        RecurringJob.AddOrUpdate<CleanupJob>(
            "in-memory-cleanup",
            job => job.ExecuteAsync(),
            Cron.Minutely);

        logger.LogInformation("[Hangfire] Recurring CleanupJob registered (Cron.Minutely).");

        return Task.CompletedTask;
    }

    public override void Dispose()
    {
        _server?.SendStop();
        _server?.Dispose();
        base.Dispose();
        GC.SuppressFinalize(this);
    }
}

public class ServiceProviderJobActivator(IServiceProvider serviceProvider) : JobActivator
{
    public override object ActivateJob(Type jobType) => serviceProvider.GetService(jobType)
        ?? Activator.CreateInstance(jobType)!;
}
