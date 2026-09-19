namespace PerformanceLab.Core.Events;

public record OrderCreatedEvent(
    Guid OrderId,
    string CustomerName,
    string CustomerEmail,
    decimal TotalAmount,
    DateTime CreatedAtUtc);
