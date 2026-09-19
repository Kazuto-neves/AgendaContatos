using AgendaContatos.Enums;
using AgendaContatos.Exceptions;
using AgendaContatos.Models;
using AgendaContatos.Repositories;
using AgendaContatos.Services;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using Moq;
using Xunit;

namespace AgendaContatos.Tests.Services;

public class UserServiceTests
{
    private readonly Mock<IUserRepository> _mockUserRepository;
    private readonly UserService _userService;
    private readonly User _superUser;
    private readonly User _commonUser;

    public UserServiceTests()
    {
        _mockUserRepository = new Mock<IUserRepository>();
        _userService = new UserService(_mockUserRepository.Object);

        _superUser = new User
        {
            Id = 1,
            Name = "Administrador",
            Phone = "000000000",
            Type = UserType.Super,
            CreatedAt = DateTime.Now.AddDays(-10),
            UpdatedAt = DateTime.Now.AddDays(-10)
        };

        _commonUser = new User
        {
            Id = 2,
            Name = "Carlos Silva",
            Phone = "111111111",
            Type = UserType.Common,
            CreatedAt = DateTime.Now.AddDays(-5),
            UpdatedAt = DateTime.Now.AddDays(-5)
        };
    }

    #region Search Tests

    [Fact]
    public void SearchUsers_Unauthenticated_ShouldThrowBusinessRuleException()
    {
        // Act
        var act = () => _userService.SearchUsers("Carlos", null);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*logado*");
    }

    [Fact]
    public void SearchUsers_CommonUser_ShouldReturnOnlyItself()
    {
        // Arrange
        var otherUser = new User { Id = 3, Name = "Carlos Eduardo", Phone = "222222222", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _commonUser, otherUser });

        // Act
        var results = _userService.SearchUsers("Carlos", _commonUser);

        // Assert
        results.Should().HaveCount(1);
        results.First().Id.Should().Be(_commonUser.Id);
        results.First().Name.Should().Be("Carlos Silva");
    }

    [Fact]
    public void SearchUsers_SuperUser_ShouldReturnAllMatching()
    {
        // Arrange
        var user2 = new User { Id = 2, Name = "Carlos Silva", Phone = "111111111", Type = UserType.Common };
        var user3 = new User { Id = 3, Name = "Carlos Eduardo", Phone = "222222222", Type = UserType.Common };
        var user4 = new User { Id = 4, Name = "Beatriz", Phone = "333333333", Type = UserType.Common };

        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, user2, user3, user4 });

        // Act
        var results = _userService.SearchUsers("Carlos", _superUser);

        // Assert
        results.Should().HaveCount(2);
        results.Select(u => u.Name).Should().Contain(new[] { "Carlos Silva", "Carlos Eduardo" });
    }

    [Fact]
    public void SearchUsers_ById_ShouldReturnCorrectUser()
    {
        // Arrange
        var user2 = new User { Id = 2, Name = "Carlos Silva", Phone = "777777777", Type = UserType.Common };
        var user3 = new User { Id = 3, Name = "Beatriz", Phone = "888888888", Type = UserType.Common };

        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, user2, user3 });

        // Act
        var results = _userService.SearchUsers("2", _superUser);

        // Assert
        results.Should().HaveCount(1);
        results.First().Id.Should().Be(2);
        results.First().Name.Should().Be("Carlos Silva");
    }

    [Fact]
    public void SearchUsers_ByPhone_ShouldReturnCorrectUser()
    {
        // Arrange
        var user2 = new User { Id = 2, Name = "Carlos Silva", Phone = "999888777", Type = UserType.Common };
        var user3 = new User { Id = 3, Name = "Beatriz", Phone = "111222333", Type = UserType.Common };

        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, user2, user3 });

        // Act
        var results = _userService.SearchUsers("888", _superUser);

        // Assert
        results.Should().HaveCount(1);
        results.First().Phone.Should().Be("999888777");
    }

    [Fact]
    public void SearchUsers_NoMatches_ShouldReturnEmptyList()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser });

        // Act
        var results = _userService.SearchUsers("Inexistente", _superUser);

        // Assert
        results.Should().BeEmpty();
    }

    #endregion

    #region GetAllUsers Tests

    [Fact]
    public void GetAllUsers_SuperUser_ShouldReturnAll()
    {
        // Arrange
        var userList = new List<User> { _superUser, _commonUser };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(userList);

        // Act
        var results = _userService.GetAllUsers(_superUser);

        // Assert
        results.Should().HaveCount(2);
        results.Should().BeEquivalentTo(userList);
    }

    [Fact]
    public void GetAllUsers_CommonUser_ShouldThrow()
    {
        // Act
        var act = () => _userService.GetAllUsers(_commonUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*SUPER*");
    }

    [Fact]
    public void GetAllUsers_Unauthenticated_ShouldThrow()
    {
        // Act
        var act = () => _userService.GetAllUsers(null);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*logado*");
    }

    #endregion

    #region AddUser Tests

    [Fact]
    public void AddUser_SuperUser_ShouldSucceed()
    {
        // Arrange
        var newUser = new User { Name = "Mariana Costa", Phone = "987654321", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser });

        // Act
        _userService.AddUser(newUser, _superUser);

        // Assert
        _mockUserRepository.Verify(r => r.Add(newUser), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    [Fact]
    public void AddUser_CommonUser_ShouldThrow()
    {
        // Arrange
        var newUser = new User { Name = "Mariana Costa", Phone = "987654321", Type = UserType.Common };

        // Act
        var act = () => _userService.AddUser(newUser, _commonUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*SUPER*");
        _mockUserRepository.Verify(r => r.Add(It.IsAny<User>()), Times.Never);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Never);
    }

    [Fact]
    public void AddUser_DuplicatePhone_ShouldThrow()
    {
        // Arrange
        var newUser = new User { Name = "Mariana", Phone = "111111111" };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _commonUser }); // _commonUser tem Phone="111111111"

        // Act
        var act = () => _userService.AddUser(newUser, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*telefone*");
        _mockUserRepository.Verify(r => r.Add(It.IsAny<User>()), Times.Never);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Never);
    }

    [Fact]
    public void AddUser_EmptyName_ShouldThrow()
    {
        // Arrange
        var newUser = new User { Name = "   ", Phone = "999999999" };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User>());

        // Act
        var act = () => _userService.AddUser(newUser, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*nome*");
        _mockUserRepository.Verify(r => r.Add(It.IsAny<User>()), Times.Never);
    }

    [Fact]
    public void AddUser_ShortName_ShouldThrow()
    {
        // Arrange
        var newUser = new User { Name = "Ab", Phone = "999999999" };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User>());

        // Act
        var act = () => _userService.AddUser(newUser, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*3 caracteres*");
        _mockUserRepository.Verify(r => r.Add(It.IsAny<User>()), Times.Never);
    }

    [Fact]
    public void AddUser_EmptyPhone_ShouldThrow()
    {
        // Arrange
        var newUser = new User { Name = "Marcos", Phone = "   " };
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User>());

        // Act
        var act = () => _userService.AddUser(newUser, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*telefone*");
        _mockUserRepository.Verify(r => r.Add(It.IsAny<User>()), Times.Never);
    }

    #endregion

    #region UpdateUser Tests

    // TODO: TimeProvider - Atualização própria com controle simulado via FakeTimeProvider
    [Fact]
    [Trait("Category", "TimeProvider")]
    public void UpdateUser_CommonUserUpdatingSelf_WithTimeProvider_ShouldSucceed()
    {
        // Arrange
        var fakeTime = new FakeTimeProvider(DateTimeOffset.Now.AddDays(-3));
        _commonUser.UpdatedAt = fakeTime.GetLocalNow().DateTime;
        var previousUpdatedAt = _commonUser.UpdatedAt;

        fakeTime.Advance(TimeSpan.FromHours(3));

        _mockUserRepository.Setup(r => r.GetById(_commonUser.Id)).Returns(_commonUser);
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser });

        // Act
        _userService.UpdateUser(_commonUser.Id, "Carlos Silva Junior", "111111222", null, _commonUser);

        // Assert
        _commonUser.Name.Should().Be("Carlos Silva Junior");
        _commonUser.Phone.Should().Be("111111222");
        _commonUser.UpdatedAt.Should().BeAfter(previousUpdatedAt);
        _mockUserRepository.Verify(r => r.Update(_commonUser), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    // TODO: Sem TimeProvider - Atualização própria com validação tradicional do UpdatedAt via DateTime.Now
    [Fact]
    [Trait("Category", "WithoutTimeProvider")]
    public void UpdateUser_CommonUserUpdatingSelf_WithoutTimeProvider_ShouldSucceed()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetById(_commonUser.Id)).Returns(_commonUser);
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser });

        // Act
        _userService.UpdateUser(_commonUser.Id, "Carlos Silva Junior", "111111222", null, _commonUser);

        // Assert
        _commonUser.Name.Should().Be("Carlos Silva Junior");
        _commonUser.Phone.Should().Be("111111222");
        Assert.True(_commonUser.UpdatedAt <= DateTime.Now);
        _mockUserRepository.Verify(r => r.Update(_commonUser), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    [Fact]
    public void UpdateUser_CommonUserUpdatingOther_ShouldThrow()
    {
        // Arrange
        var targetUser = new User { Id = 3, Name = "Outro", Phone = "333333333", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetById(3)).Returns(targetUser);

        // Act
        var act = () => _userService.UpdateUser(3, "Novo Nome", "333333333", null, _commonUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*Comuns só atualizam a si mesmos*");
        _mockUserRepository.Verify(r => r.Update(It.IsAny<User>()), Times.Never);
    }

    // TODO: TimeProvider - Atualização de terceiro + Tipo com controle simulado via FakeTimeProvider
    [Fact]
    [Trait("Category", "TimeProvider")]
    public void UpdateUser_SuperUserUpdatingOtherAndType_WithTimeProvider_ShouldSucceed()
    {
        // Arrange
        var fakeTime = new FakeTimeProvider(DateTimeOffset.Now.AddDays(-2));
        var targetUser = new User
        {
            Id = 3,
            Name = "Roberto",
            Phone = "333333333",
            Type = UserType.Common,
            CreatedAt = fakeTime.GetLocalNow().DateTime,
            UpdatedAt = fakeTime.GetLocalNow().DateTime
        };
        var previousUpdatedAt = targetUser.UpdatedAt;

        fakeTime.Advance(TimeSpan.FromDays(1));

        _mockUserRepository.Setup(r => r.GetById(3)).Returns(targetUser);
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser, targetUser });

        // Act
        _userService.UpdateUser(3, "Roberto Carlos", "333333444", UserType.Super, _superUser);

        // Assert
        targetUser.Name.Should().Be("Roberto Carlos");
        targetUser.Phone.Should().Be("333333444");
        targetUser.Type.Should().Be(UserType.Super);
        targetUser.UpdatedAt.Should().BeAfter(previousUpdatedAt);
        _mockUserRepository.Verify(r => r.Update(targetUser), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    // TODO: Sem TimeProvider - Atualização de terceiro + Tipo com validação tradicional do UpdatedAt via DateTime.Now
    [Fact]
    [Trait("Category", "WithoutTimeProvider")]
    public void UpdateUser_SuperUserUpdatingOtherAndType_WithoutTimeProvider_ShouldSucceed()
    {
        // Arrange
        var targetUser = new User
        {
            Id = 3,
            Name = "Roberto",
            Phone = "333333333",
            Type = UserType.Common,
            CreatedAt = DateTime.Now.AddDays(-2),
            UpdatedAt = DateTime.Now.AddDays(-2)
        };

        _mockUserRepository.Setup(r => r.GetById(3)).Returns(targetUser);
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser, targetUser });

        // Act
        _userService.UpdateUser(3, "Roberto Carlos", "333333444", UserType.Super, _superUser);

        // Assert
        targetUser.Name.Should().Be("Roberto Carlos");
        targetUser.Phone.Should().Be("333333444");
        targetUser.Type.Should().Be(UserType.Super);
        Assert.True(targetUser.UpdatedAt <= DateTime.Now);
        _mockUserRepository.Verify(r => r.Update(targetUser), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    [Fact]
    public void UpdateUser_TargetNotFound_ShouldThrow()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetById(99)).Returns((User?)null);

        // Act
        var act = () => _userService.UpdateUser(99, "Novo Nome", "999999999", null, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*não encontrado*");
        _mockUserRepository.Verify(r => r.Update(It.IsAny<User>()), Times.Never);
    }

    [Fact]
    public void UpdateUser_DuplicatePhone_ShouldThrow()
    {
        // Arrange
        var targetUser = new User { Id = 3, Name = "Roberto", Phone = "333333333", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetById(3)).Returns(targetUser);
        _mockUserRepository.Setup(r => r.GetAll()).Returns(new List<User> { _superUser, _commonUser, targetUser });

        // Act (Tenta mudar o telefone do usuário 3 para o telefone do usuário 2 "111111111")
        var act = () => _userService.UpdateUser(3, "Roberto", "111111111", null, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*telefone*");
        _mockUserRepository.Verify(r => r.Update(It.IsAny<User>()), Times.Never);
    }

    [Fact]
    public void UpdateUser_InvalidName_ShouldThrow()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetById(_commonUser.Id)).Returns(_commonUser);

        // Act
        var act = () => _userService.UpdateUser(_commonUser.Id, "Oi", "111111111", null, _commonUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*3 caracteres*");
        _mockUserRepository.Verify(r => r.Update(It.IsAny<User>()), Times.Never);
    }

    #endregion

    #region DeleteUser Tests

    [Fact]
    public void DeleteUser_SuperUserDeletingOther_ShouldSucceed()
    {
        // Arrange
        var targetUser = new User { Id = 3, Name = "Para Deletar", Phone = "777777777", Type = UserType.Common };
        _mockUserRepository.Setup(r => r.GetById(3)).Returns(targetUser);

        // Act
        _userService.DeleteUser(3, _superUser);

        // Assert
        _mockUserRepository.Verify(r => r.Delete(3), Times.Once);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Once);
    }

    [Fact]
    public void DeleteUser_SuperUserDeletingSelf_ShouldThrow()
    {
        // Act
        var act = () => _userService.DeleteUser(_superUser.Id, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*a si mesmo*");
        _mockUserRepository.Verify(r => r.Delete(It.IsAny<int>()), Times.Never);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Never);
    }

    [Fact]
    public void DeleteUser_CommonUser_ShouldThrow()
    {
        // Act
        var act = () => _userService.DeleteUser(3, _commonUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*SUPER*");
        _mockUserRepository.Verify(r => r.Delete(It.IsAny<int>()), Times.Never);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Never);
    }

    [Fact]
    public void DeleteUser_TargetNotFound_ShouldThrow()
    {
        // Arrange
        _mockUserRepository.Setup(r => r.GetById(99)).Returns((User?)null);

        // Act
        var act = () => _userService.DeleteUser(99, _superUser);

        // Assert
        act.Should().Throw<BusinessRuleException>().WithMessage("*não encontrado*");
        _mockUserRepository.Verify(r => r.Delete(It.IsAny<int>()), Times.Never);
        _mockUserRepository.Verify(r => r.SaveChanges(), Times.Never);
    }

    #endregion
}
