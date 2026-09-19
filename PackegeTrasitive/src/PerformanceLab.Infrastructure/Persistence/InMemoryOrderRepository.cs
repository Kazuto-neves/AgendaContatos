namespace PerformanceLab.Infrastructure.Persistence;

using System.Collections.Concurrent;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Core.Models;

public class InMemoryOrderRepository : IOrderRepository
{
    private readonly ConcurrentDictionary<Guid, Order> _orders = new();

    public Task<Order> CreateAsync(Order order, CancellationToken cancellationToken = default)
    {
        _orders[order.Id] = order;
        return Task.FromResult(order);
    }

    public Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        _orders.TryGetValue(id, out var order);
        return Task.FromResult(order);
    }

    public Task<(IReadOnlyList<Order> Items, int TotalCount)> GetPagedAsync(int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var allOrders = _orders.Values;
        var totalCount = allOrders.Count;
        var items = allOrders
            .OrderByDescending(o => o.CreatedAtUtc)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToList();

        return Task.FromResult(((IReadOnlyList<Order>)items, totalCount));
    }
}
