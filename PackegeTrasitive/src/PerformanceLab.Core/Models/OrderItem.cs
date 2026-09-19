namespace PerformanceLab.Core.Models;

public record OrderItem(
    Guid Id,
    string ProductName,
    int Quantity,
    decimal UnitPrice)
{
    public decimal TotalPrice => Quantity * UnitPrice;
}
