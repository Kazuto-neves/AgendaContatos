using AgendaContatos.Enums;
using AgendaContatos.Models;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AgendaContatos.Tests.Models;

public class UserTests
{
    #region Testes COM TimeProvider (FakeTimeProvider)

    // TODO: TimeProvider - Atualização de dados pessoais simulando controle de tempo com FakeTimeProvider
    [Fact]
    [Trait("Category", "TimeProvider")]
    public void UpdatePersonalInfo_WithTimeProvider_ShouldUpdateTimestamp()
    {
        // Arrange
        var fakeTime = new FakeTimeProvider(DateTimeOffset.Now.AddDays(-2));
        var user = new User
        {
            Id = 1,
            Name = "Carlos",
            Phone = "111111111",
            Type = UserType.Common,
            CreatedAt = fakeTime.GetLocalNow().DateTime,
            UpdatedAt = fakeTime.GetLocalNow().DateTime
        };

        var previousUpdatedAt = user.UpdatedAt;
        fakeTime.Advance(TimeSpan.FromHours(2));

        // Act
        user.UpdatePersonalInfo("Carlos Silva", "222222222");

        // Assert
        user.Name.Should().Be("Carlos Silva");
        user.Phone.Should().Be("222222222");
        user.UpdatedAt.Should().BeAfter(previousUpdatedAt);
    }

    // TODO: TimeProvider - Atualização de tipo simulando controle de tempo com FakeTimeProvider
    [Fact]
    [Trait("Category", "TimeProvider")]
    public void UpdateType_WithTimeProvider_ShouldUpdateTimestamp()
    {
        // Arrange
        var fakeTime = new FakeTimeProvider(DateTimeOffset.Now.AddDays(-5));
        var user = new User
        {
            Id = 2,
            Name = "Beatriz",
            Phone = "333333333",
            Type = UserType.Common,
            CreatedAt = fakeTime.GetLocalNow().DateTime,
            UpdatedAt = fakeTime.GetLocalNow().DateTime
        };

        var previousUpdatedAt = user.UpdatedAt;
        fakeTime.Advance(TimeSpan.FromDays(1));

        // Act
        user.UpdateType(UserType.Super);

        // Assert
        user.Type.Should().Be(UserType.Super);
        user.UpdatedAt.Should().BeAfter(previousUpdatedAt);
    }

    #endregion

    #region Testes SEM TimeProvider (Validação Tradicional)

    // TODO: Sem TimeProvider - Atualização de dados pessoais com validação tradicional do UpdatedAt via DateTime.Now
    [Fact]
    [Trait("Category", "WithoutTimeProvider")]
    public void UpdatePersonalInfo_WithoutTimeProvider_ShouldUpdateTimestamp()
    {
        // Arrange
        var user = new User
        {
            Id = 1,
            Name = "Carlos",
            Phone = "111111111",
            Type = UserType.Common,
            CreatedAt = DateTime.Now.AddDays(-1),
            UpdatedAt = DateTime.Now.AddDays(-1)
        };

        // Act
        user.UpdatePersonalInfo("Carlos Silva", "222222222");

        // Assert
        user.Name.Should().Be("Carlos Silva");
        user.Phone.Should().Be("222222222");
        Assert.True(user.UpdatedAt <= DateTime.Now);
    }

    // TODO: Sem TimeProvider - Atualização de tipo com validação tradicional do UpdatedAt via DateTime.Now
    [Fact]
    [Trait("Category", "WithoutTimeProvider")]
    public void UpdateType_WithoutTimeProvider_ShouldUpdateTimestamp()
    {
        // Arrange
        var user = new User
        {
            Id = 2,
            Name = "Beatriz",
            Phone = "333333333",
            Type = UserType.Common,
            CreatedAt = DateTime.Now.AddDays(-1),
            UpdatedAt = DateTime.Now.AddDays(-1)
        };

        // Act
        user.UpdateType(UserType.Super);

        // Assert
        user.Type.Should().Be(UserType.Super);
        Assert.True(user.UpdatedAt <= DateTime.Now);
    }

    #endregion
}
