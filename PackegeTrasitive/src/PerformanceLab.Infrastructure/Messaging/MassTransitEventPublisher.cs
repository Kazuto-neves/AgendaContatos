namespace PerformanceLab.Infrastructure.Messaging;

using MassTransit;
using PerformanceLab.Core.Abstractions;

public class MassTransitEventPublisher(IPublishEndpoint publishEndpoint) : IEventPublisher
{
    public Task PublishAsync<T>(T message, CancellationToken cancellationToken = default) where T : class
    {
        return publishEndpoint.Publish(message, cancellationToken);
    }
}
