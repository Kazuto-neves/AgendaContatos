namespace PerformanceLab.Core.Mapping;

using Mapster;
using PerformanceLab.Core.DTOs;
using PerformanceLab.Core.Models;

public static class MapsterConfig
{
    private static bool _configured;
    private static readonly object SyncLock = new();

    public static void RegisterMappings()
    {
        if (_configured) return;

        lock (SyncLock)
        {
            if (_configured) return;

            TypeAdapterConfig<Order, OrderResponseDto>
                .NewConfig()
                .Map(dest => dest.Status, src => src.Status.ToString())
                .Map(dest => dest.Items, src => src.Items.Adapt<List<OrderItemDto>>());

            TypeAdapterConfig<OrderItem, OrderItemDto>
                .NewConfig()
                .Map(dest => dest.TotalPrice, src => src.TotalPrice);

            TypeAdapterConfig.GlobalSettings.Compile();
            _configured = true;
        }
    }
}
