namespace PerformanceLab.Tests;

using FluentAssertions;
using FluentValidation;
using Microsoft.Extensions.Logging;
using NSubstitute;
using PerformanceLab.Core.Abstractions;
using PerformanceLab.Core.DTOs;
using PerformanceLab.Core.Events;
using PerformanceLab.Core.Features.Orders.CreateOrder;
using PerformanceLab.Core.Mapping;
using PerformanceLab.Core.Models;
using Xunit;

public class CreateOrderCommandHandlerTests
{
    private readonly IOrderRepository _orderRepository = Substitute.For<IOrderRepository>();
    private readonly IClock _clock = Substitute.For<IClock>();
    private readonly IEventPublisher _eventPublisher = Substitute.For<IEventPublisher>();
    private readonly ILogger<CreateOrderCommandHandler> _logger = Substitute.For<ILogger<CreateOrderCommandHandler>>();
    private readonly CreateOrderValidator _validator = new();

    public CreateOrderCommandHandlerTests()
    {
        MapsterConfig.RegisterMappings();
    }

    [Fact]
    public async Task Handle_ValidCommand_ShouldCreateOrderAndPublishEvent()
    {
        // Arrange
        var fakeUtcNow = new DateTime(2026, 1, 15, 12, 0, 0, DateTimeKind.Utc);
        _clock.UtcNow.Returns(fakeUtcNow);

        _orderRepository.CreateAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>())
            .Returns(callInfo => callInfo.Arg<Order>());

        var handler = new CreateOrderCommandHandler(_orderRepository, _clock, _eventPublisher, _validator, _logger);
        var command = new CreateOrderCommand(
            CustomerName: "Margaret Hamilton",
            CustomerEmail: "margaret@apollo.nasa.gov",
            Items:
            [
                new CreateOrderItemDto("Apollo Guidance Software", 1, 1000m),
                new CreateOrderItemDto("Patch Cables", 3, 25m)
            ]
        );

        // Act
        var result = await handler.Handle(command, CancellationToken.None);

        // Assert
        result.Should().NotBeNull();
        result.CustomerName.Should().Be("Margaret Hamilton");
        result.TotalAmount.Should().Be(1075m);
        result.CreatedAtUtc.Should().Be(fakeUtcNow);
        result.Items.Should().HaveCount(2);

        await _orderRepository.Received(1).CreateAsync(Arg.Is<Order>(o =>
            o.CustomerName == "Margaret Hamilton" &&
            o.TotalAmount == 1075m &&
            o.CreatedAtUtc == fakeUtcNow), Arg.Any<CancellationToken>());

        await _eventPublisher.Received(1).PublishAsync(Arg.Is<OrderCreatedEvent>(e =>
            e.CustomerName == "Margaret Hamilton" &&
            e.TotalAmount == 1075m), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_InvalidCommand_ShouldThrowValidationException()
    {
        // Arrange
        var handler = new CreateOrderCommandHandler(_orderRepository, _clock, _eventPublisher, _validator, _logger);
        var command = new CreateOrderCommand("", "", []);

        // Act
        var act = () => handler.Handle(command, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<ValidationException>();
        await _orderRepository.DidNotReceive().CreateAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>());
        await _eventPublisher.DidNotReceive().PublishAsync(Arg.Any<OrderCreatedEvent>(), Arg.Any<CancellationToken>());
    }
}
