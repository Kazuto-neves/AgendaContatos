namespace PerformanceLab.Core.Abstractions;

using PerformanceLab.Core.Models;

public interface IOrderRepository
{
    Task<Order> CreateAsync(Order order, CancellationToken cancellationToken = default);
    Task<Order?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
    Task<(IReadOnlyList<Order> Items, int TotalCount)> GetPagedAsync(int page, int pageSize, CancellationToken cancellationToken = default);
}
