namespace PerformanceLab.Core.DTOs;

public record OrderItemDto(
    Guid Id,
    string ProductName,
    int Quantity,
    decimal UnitPrice,
    decimal TotalPrice);

public record CreateOrderItemDto(
    string ProductName,
    int Quantity,
    decimal UnitPrice);

public record OrderResponseDto(
    Guid Id,
    string CustomerName,
    string CustomerEmail,
    decimal TotalAmount,
    string Status,
    DateTime CreatedAtUtc,
    IReadOnlyList<OrderItemDto> Items);

public record PagedResult<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages)
{
    public bool HasPreviousPage => Page > 1;
    public bool HasNextPage => Page < TotalPages;
}
