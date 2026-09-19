namespace PerformanceLab.Core.Features.Orders.GetOrders;

using MediatR;
using PerformanceLab.Core.DTOs;

public record GetOrdersQuery(int Page = 1, int PageSize = 10) : IRequest<PagedResult<OrderResponseDto>>;
