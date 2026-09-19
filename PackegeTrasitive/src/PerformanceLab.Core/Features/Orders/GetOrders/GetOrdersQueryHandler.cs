namespace PerformanceLab.Core.Features.Orders.GetOrders;

using Mapster;
using MediatR;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Core.DTOs;

public class GetOrdersQueryHandler(IOrderRepository orderRepository) : IRequestHandler<GetOrdersQuery, PagedResult<OrderResponseDto>>
{
    public async Task<PagedResult<OrderResponseDto>> Handle(GetOrdersQuery request, CancellationToken cancellationToken)
    {
        var page = request.Page < 1 ? 1 : request.Page;
        var pageSize = request.PageSize < 1 ? 10 : (request.PageSize > 100 ? 100 : request.PageSize);

        var (items, totalCount) = await orderRepository.GetPagedAsync(page, pageSize, cancellationToken);
        var mappedItems = items.Adapt<List<OrderResponseDto>>();
        var totalPages = totalCount == 0 ? 0 : (int)Math.Ceiling(totalCount / (double)pageSize);

        return new PagedResult<OrderResponseDto>(
            Items: mappedItems,
            Page: page,
            PageSize: pageSize,
            TotalCount: totalCount,
            TotalPages: totalPages
        );
    }
}
