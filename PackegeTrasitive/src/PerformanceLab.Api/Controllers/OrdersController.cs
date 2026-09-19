namespace PerformanceLab.Api.Controllers;

using Asp.Versioning;
using MediatR;
using Microsoft.AspNetCore.Mvc;
using PerformanceLab.Core.DTOs;
using PerformanceLab.Core.Features.Orders.CreateOrder;
using PerformanceLab.Core.Features.Orders.GetOrders;

[ApiController]
[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/[controller]")]
public class OrdersController(IMediator mediator) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType(typeof(OrderResponseDto), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Create([FromBody] CreateOrderCommand command, CancellationToken cancellationToken)
    {
        var result = await mediator.Send(command, cancellationToken);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<OrderResponseDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetPaged([FromQuery] int page = 1, [FromQuery] int pageSize = 10, CancellationToken cancellationToken = default)
    {
        var result = await mediator.Send(new GetOrdersQuery(page, pageSize), cancellationToken);
        return Ok(result);
    }
}
