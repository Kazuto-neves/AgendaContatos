namespace PerformanceLab.Tests;

using FluentAssertions;
using PerformanceLab.Core.Models;
using PerformanceLab.Infrastructure.Persistence;
using Xunit;

public class InMemoryOrderRepositoryTests
{
    private readonly InMemoryOrderRepository _repository = new();

    [Fact]
    public async Task CreateAsync_And_GetByIdAsync_ShouldPersistAndRetrieveOrder()
    {
        // Arrange
        var order = new Order
        {
            Id = Guid.NewGuid(),
            CustomerName = "Alan Turing",
            CustomerEmail = "alan@bletchleypark.org",
            TotalAmount = 250m,
            CreatedAtUtc = DateTime.UtcNow,
            Items = [new OrderItem(Guid.NewGuid(), "Enigma Decryptor", 1, 250m)]
        };

        // Act
        await _repository.CreateAsync(order);
        var retrieved = await _repository.GetByIdAsync(order.Id);

        // Assert
        retrieved.Should().NotBeNull();
        retrieved!.Id.Should().Be(order.Id);
        retrieved.CustomerName.Should().Be("Alan Turing");
        retrieved.TotalAmount.Should().Be(250m);
    }

    [Fact]
    public async Task GetPagedAsync_ShouldReturnCorrectPageAndTotalCount()
    {
        // Arrange
        for (int i = 1; i <= 25; i++)
        {
            await _repository.CreateAsync(new Order
            {
                Id = Guid.NewGuid(),
                CustomerName = $"Customer {i:D2}",
                CustomerEmail = $"customer{i}@example.com",
                TotalAmount = i * 10m,
                CreatedAtUtc = DateTime.UtcNow.AddMinutes(i)
            });
        }

        // Act
        var (page1Items, totalCount) = await _repository.GetPagedAsync(page: 1, pageSize: 10);
        var (page3Items, _) = await _repository.GetPagedAsync(page: 3, pageSize: 10);

        // Assert
        totalCount.Should().Be(25);
        page1Items.Should().HaveCount(10);
        page3Items.Should().HaveCount(5);

        // Descending order verification
        page1Items.First().CreatedAtUtc.Should().BeAfter(page1Items.Last().CreatedAtUtc);
    }
}
