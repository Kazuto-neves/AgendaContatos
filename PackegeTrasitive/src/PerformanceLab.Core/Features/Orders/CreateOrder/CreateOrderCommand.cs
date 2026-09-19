namespace PerformanceLab.Core.Features.Orders.CreateOrder;

using MediatR;
using PerformanceLab.Core.DTOs;

public record CreateOrderCommand(
    string CustomerName,
    string CustomerEmail,
    List<CreateOrderItemDto> Items) : IRequest<OrderResponseDto>;
