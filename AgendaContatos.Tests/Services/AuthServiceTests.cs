using AgendaContatos.Enums;
using AgendaContatos.Models;
using AgendaContatos.Repositories;
using AgendaContatos.Services;
using FluentAssertions;
using Moq;
using Xunit;

namespace AgendaContatos.Tests.Services;

public class AuthServiceTests
{
    private readonly Mock<IUserRepository> _mockUserRepository;
    private readonly AuthService _authService;

    public AuthServiceTests()
    {
        _mockUserRepository = new Mock<IUserRepository>();
        _authService = new AuthService(_mockUserRepository.Object);
    }

    [Fact]
    public void Login_ExistingUser_ShouldReturnTrueAndSetCurrentUser()
    {
        // Arrange
        var existingUser = new User
        {
            Id = 1,
            Name = "Administrador",
            Phone = "000000000",
            Type = UserType.Super,
            CreatedAt = DateTime.Now,
            UpdatedAt = DateTime.Now
        };
        _mockUserRepository.Setup(r => r.GetById(1)).Returns(existingUser);

        // Act
        var result = _authService.Login(1);

        // Assert
        result.Should().BeTrue();
        _authService.CurrentUser.Should().NotBeNull();
        _authService.CurrentUser!.Id.Should().Be(1);
        _authService.CurrentUser.Name.Should().Be("Administrador");
        _mockUserRepository.Verify(r => r.GetById(1), Times.Once);
    }

    [Fact]
    public void Login_NonExistingUser_ShouldReturnFalseAndKeepCurrentUserNull()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetById(99)).Returns((User?)null);

        // Act
        var result = _authService.Login(99);

        // Assert
        result.Should().BeFalse();
        _authService.CurrentUser.Should().BeNull();
        _mockUserRepository.Verify(r => r.GetById(99), Times.Once);
    }

    [Fact]
    public void Logout_ShouldClearCurrentUser()
    {
        // Arrange
        var user = new User { Id = 2, Name = "Carlos", Phone = "111111111", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetById(2)).Returns(user);
        _authService.Login(2);
        _authService.CurrentUser.Should().NotBeNull();

        // Act
        _authService.Logout();

        // Assert
        _authService.CurrentUser.Should().BeNull();
    }
}
