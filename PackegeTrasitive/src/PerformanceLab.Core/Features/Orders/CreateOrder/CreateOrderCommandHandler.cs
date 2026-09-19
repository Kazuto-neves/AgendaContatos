namespace PerformanceLab.Core.Features.Orders.CreateOrder;

using FluentValidation;
using Mapster;
using MediatR;
using Microsoft.Extensions.Logging;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Core.DTOs;
using PerformanceLab.Core.Events;
using PerformanceLab.Core.Models;

public class CreateOrderCommandHandler(
    IOrderRepository orderRepository,
    IClock clock,
    IEventPublisher eventPublisher,
    IValidator<CreateOrderCommand> validator,
    ILogger<CreateOrderCommandHandler> logger) : IRequestHandler<CreateOrderCommand, OrderResponseDto>
{
    public async Task<OrderResponseDto> Handle(CreateOrderCommand request, CancellationToken cancellationToken)
    {
        var validationResult = await validator.ValidateAsync(request, cancellationToken);
        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        var orderItems = request.Items.Select(item => new OrderItem(
            Id: Guid.NewGuid(),
            ProductName: item.ProductName,
            Quantity: item.Quantity,
            UnitPrice: item.UnitPrice
        )).ToList();

        var totalAmount = orderItems.Sum(x => x.TotalPrice);

        var order = new Order
        {
            Id = Guid.NewGuid(),
            CustomerName = request.CustomerName,
            CustomerEmail = request.CustomerEmail,
            TotalAmount = totalAmount,
            Status = OrderStatus.Pending,
            CreatedAtUtc = clock.UtcNow,
            Items = orderItems
        };

        var created = await orderRepository.CreateAsync(order, cancellationToken);
        logger.LogInformation("Order {OrderId} created successfully with total {TotalAmount:C}", created.Id, created.TotalAmount);

        var orderCreatedEvent = new OrderCreatedEvent(
            created.Id,
            created.CustomerName,
            created.CustomerEmail,
            created.TotalAmount,
            created.CreatedAtUtc
        );

        await eventPublisher.PublishAsync(orderCreatedEvent, cancellationToken);

        return created.Adapt<OrderResponseDto>();
    }
}
