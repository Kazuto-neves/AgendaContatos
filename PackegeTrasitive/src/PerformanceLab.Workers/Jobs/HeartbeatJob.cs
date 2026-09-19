namespace PerformanceLab.Workers.Jobs;

using Bogus;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Core.Events;
using Quartz;

[DisallowConcurrentExecution]
public class HeartbeatJob(
    IServiceScopeFactory scopeFactory,
    ILogger<HeartbeatJob> logger) : IJob
{
    private static readonly Faker Faker = new();

    public async Task Execute(IJobExecutionContext context)
    {
        using var scope = scopeFactory.CreateScope();
        var eventPublisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();

        var customerName = Faker.Name.FullName();
        var customerEmail = Faker.Internet.Email(customerName);
        var totalAmount = Math.Round(Faker.Random.Decimal(10m, 500m), 2);
        var orderId = Guid.NewGuid();

        logger.LogInformation(
            "[Quartz Heartbeat] Emitting synthetic OrderCreatedEvent {OrderId} for {Customer} ({Email}) | Total: {Total:C}",
            orderId, customerName, customerEmail, totalAmount);

        var @event = new OrderCreatedEvent(
            orderId,
            customerName,
            customerEmail,
            totalAmount,
            DateTime.UtcNow);

        await eventPublisher.PublishAsync(@event, context.CancellationToken);
    }
}
