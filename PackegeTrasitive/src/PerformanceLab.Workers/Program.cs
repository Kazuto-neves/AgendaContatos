using PerformanceLab.Core;
using PerformanceLab.Infrastructure;
using PerformanceLab.Workers.Jobs;
using PerformanceLab.Workers.Services;
using Quartz;
using Serilog;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSerilog(configuration =>
{
    configuration
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft", Serilog.Events.LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.Hosting.Lifetime", Serilog.Events.LogEventLevel.Information)
        .MinimumLevel.Override("Quartz", Serilog.Events.LogEventLevel.Warning)
        .MinimumLevel.Override("Hangfire", Serilog.Events.LogEventLevel.Information)
        .Enrich.FromLogContext()
        .Enrich.WithEnvironmentName()
        .Enrich.WithThreadId()
        .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] [{ThreadId}] {Message:lj}{NewLine}{Exception}")
        .WriteTo.File(
            path: "logs/workers-.log",
            rollingInterval: RollingInterval.Day,
            retainedFileCountLimit: 7,
            outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{ThreadId}] {SourceContext}: {Message:lj}{NewLine}{Exception}");
});

builder.Services.AddCore();
builder.Services.AddInfrastructure();

builder.Services.AddQuartz(q =>
{
    var jobKey = new JobKey(nameof(HeartbeatJob));
    q.AddJob<HeartbeatJob>(opts => opts.WithIdentity(jobKey));
    q.AddTrigger(opts => opts
        .ForJob(jobKey)
        .WithIdentity($"{nameof(HeartbeatJob)}-trigger")
        .WithSimpleSchedule(x => x.WithIntervalInSeconds(5).RepeatForever()));
});

builder.Services.AddQuartzHostedService(opt =>
{
    opt.WaitForJobsToComplete = true;
});

builder.Services.AddTransient<CleanupJob>();
builder.Services.AddHostedService<HangfireBackgroundService>();

var host = builder.Build();
host.Run();
