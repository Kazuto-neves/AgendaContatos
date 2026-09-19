namespace PerformanceLab.Core.Models;

public record Order
{
    public Guid Id { get; init; }
    public string CustomerName { get; init; } = string.Empty;
    public string CustomerEmail { get; init; } = string.Empty;
    public decimal TotalAmount { get; init; }
    public OrderStatus Status { get; init; } = OrderStatus.Pending;
    public DateTime CreatedAtUtc { get; init; }
    public IReadOnlyList<OrderItem> Items { get; init; } = [];
}
