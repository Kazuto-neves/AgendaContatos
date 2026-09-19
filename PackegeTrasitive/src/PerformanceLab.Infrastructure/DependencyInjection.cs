namespace PerformanceLab.Infrastructure;

using MassTransit;
using Microsoft.Extensions.DependencyInjection;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Infrastructure.Messaging;
using PerformanceLab.Infrastructure.Persistence;
using PerformanceLab.Infrastructure.Time;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services)
    {
        services.AddMemoryCache();
        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<IOrderRepository, InMemoryOrderRepository>();
        services.AddScoped<IEventPublisher, MassTransitEventPublisher>();

        services.AddMassTransit(x =>
        {
            x.AddConsumer<OrderCreatedConsumer>();

            x.UsingInMemory((context, cfg) =>
            {
                cfg.ConfigureEndpoints(context);
            });
        });

        return services;
    }
}
