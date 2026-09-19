namespace PerformanceLab.Tests;

using FluentAssertions;
using PerformanceLab.Core.DTOs;
using PerformanceLab.Core.Features.Orders.CreateOrder;
using Xunit;

public class CreateOrderValidatorTests
{
    private readonly CreateOrderValidator _validator = new();

    [Fact]
    public void Validate_ValidCommand_ShouldPassValidation()
    {
        // Arrange
        var command = new CreateOrderCommand(
            CustomerName: "Ada Lovelace",
            CustomerEmail: "ada@example.com",
            Items:
            [
                new CreateOrderItemDto("Analytical Engine Core", 2, 499.99m),
                new CreateOrderItemDto("Punch Cards Box", 10, 19.50m)
            ]
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeTrue();
        result.Errors.Should().BeEmpty();
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void Validate_EmptyCustomerName_ShouldFail(string? invalidName)
    {
        // Arrange
        var command = new CreateOrderCommand(
            CustomerName: invalidName!,
            CustomerEmail: "valid@example.com",
            Items: [new CreateOrderItemDto("Item A", 1, 10m)]
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == nameof(CreateOrderCommand.CustomerName));
    }

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("plainaddress")]
    [InlineData("@nodomain.com")]
    public void Validate_InvalidEmail_ShouldFail(string invalidEmail)
    {
        // Arrange
        var command = new CreateOrderCommand(
            CustomerName: "John Doe",
            CustomerEmail: invalidEmail,
            Items: [new CreateOrderItemDto("Item A", 1, 10m)]
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == nameof(CreateOrderCommand.CustomerEmail));
    }

    [Fact]
    public void Validate_EmptyItemsList_ShouldFail()
    {
        // Arrange
        var command = new CreateOrderCommand(
            CustomerName: "John Doe",
            CustomerEmail: "john@example.com",
            Items: []
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == nameof(CreateOrderCommand.Items));
    }

    [Fact]
    public void Validate_ItemWithZeroQuantityOrNegativePrice_ShouldFail()
    {
        // Arrange
        var command = new CreateOrderCommand(
            CustomerName: "John Doe",
            CustomerEmail: "john@example.com",
            Items:
            [
                new CreateOrderItemDto("Invalid Item", 0, -5m)
            ]
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().HaveCountGreaterThanOrEqualTo(2);
    }
}
