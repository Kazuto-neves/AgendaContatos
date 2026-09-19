namespace PerformanceLab.Infrastructure.Messaging;

using MassTransit;
using Microsoft.Extensions.Logging;
using PerformanceLab.Core.Events;

public class OrderCreatedConsumer(ILogger<OrderCreatedConsumer> logger) : IConsumer<OrderCreatedEvent>
{
    public Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var message = context.Message;
        logger.LogInformation(
            "OrderCreatedConsumer handled Order {OrderId} for {CustomerName} ({CustomerEmail}) with total {TotalAmount:C}",
            message.OrderId,
            message.CustomerName,
            message.CustomerEmail,
            message.TotalAmount);

        return Task.CompletedTask;
    }
}
