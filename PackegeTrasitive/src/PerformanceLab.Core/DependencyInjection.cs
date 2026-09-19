namespace PerformanceLab.Core;

using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using PerformanceLab.Core.Mapping;

public static class DependencyInjection
{
    public static IServiceCollection AddCore(this IServiceCollection services)
    {
        var assembly = typeof(DependencyInjection).Assembly;

        services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));
        services.AddValidatorsFromAssembly(assembly);

        MapsterConfig.RegisterMappings();

        return services;
    }
}
