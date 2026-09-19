using AgendaContatos.Enums;
using AgendaContatos.Models;
using AgendaContatos.Repositories;
using FluentAssertions;
using Xunit;

namespace AgendaContatos.Tests.Repositories;

public class JsonUserRepositoryTests : IDisposable
{
    private readonly string _tempFilePath;

    public JsonUserRepositoryTests()
    {
        _tempFilePath = Path.Combine(Path.GetTempPath(), $"users_test_{Guid.NewGuid():N}.json");
    }

    public void Dispose()
    {
        if (File.Exists(_tempFilePath))
        {
            try
            {
                File.Delete(_tempFilePath);
            }
            catch
            {
                // Ignora falhas caso o arquivo já tenha sido removido
            }
        }
    }

    [Fact]
    public void Constructor_ShouldCreateBootstrapSuperUser_WhenFileIsEmpty()
    {
        // Act
        var repo = new JsonUserRepository(_tempFilePath);
        var users = repo.GetAll();

        // Assert
        users.Should().HaveCount(1);
        var admin = users.First();
        admin.Id.Should().Be(1);
        admin.Name.Should().Be("Administrador");
        admin.Phone.Should().Be("000000000");
        admin.Type.Should().Be(UserType.Super);
        admin.CreatedAt.Should().BeCloseTo(DateTime.Now, TimeSpan.FromSeconds(5));
        admin.UpdatedAt.Should().BeCloseTo(DateTime.Now, TimeSpan.FromSeconds(5));
        File.Exists(_tempFilePath).Should().BeTrue();
    }

    [Fact]
    public void Add_ShouldGenerateIdAndTimestamps()
    {
        // Arrange
        var repo = new JsonUserRepository(_tempFilePath); // Bootstrap cria o Admin (Id = 1)
        var newUser = new User { Name = "Lucas Santos", Phone = "998877665", Type = UserType.Common };

        // Act
        repo.Add(newUser);
        repo.SaveChanges();

        // Assert
        newUser.Id.Should().Be(2);
        newUser.CreatedAt.Should().BeCloseTo(DateTime.Now, TimeSpan.FromSeconds(5));
        newUser.UpdatedAt.Should().BeCloseTo(DateTime.Now, TimeSpan.FromSeconds(5));

        // Reabre repositório a partir do arquivo para garantir persistência no disco
        var repoReloaded = new JsonUserRepository(_tempFilePath);
        var persistedUser = repoReloaded.GetById(2);
        persistedUser.Should().NotBeNull();
        persistedUser!.Name.Should().Be("Lucas Santos");
        persistedUser.Phone.Should().Be("998877665");
    }

    [Fact]
    public void Update_ShouldPersistChanges()
    {
        // Arrange
        var repo = new JsonUserRepository(_tempFilePath);
        var newUser = new User { Name = "Lucas", Phone = "998877665", Type = UserType.Common };
        repo.Add(newUser);
        repo.SaveChanges();

        // Act
        var userToUpdate = repo.GetById(newUser.Id)!;
        userToUpdate.UpdatePersonalInfo("Lucas Modificado", "998877000");
        repo.Update(userToUpdate);
        repo.SaveChanges();

        // Assert
        var repoReloaded = new JsonUserRepository(_tempFilePath);
        var updatedUser = repoReloaded.GetById(newUser.Id);
        updatedUser.Should().NotBeNull();
        updatedUser!.Name.Should().Be("Lucas Modificado");
        updatedUser.Phone.Should().Be("998877000");
    }

    [Fact]
    public void Delete_ShouldRemoveUser()
    {
        // Arrange
        var repo = new JsonUserRepository(_tempFilePath);
        var newUser = new User { Name = "Para Deletar", Phone = "123456789", Type = UserType.Common };
        repo.Add(newUser);
        repo.SaveChanges();
        repo.GetAll().Should().HaveCount(2);

        // Act
        repo.Delete(newUser.Id);
        repo.SaveChanges();

        // Assert
        var repoReloaded = new JsonUserRepository(_tempFilePath);
        repoReloaded.GetAll().Should().HaveCount(1);
        repoReloaded.GetById(newUser.Id).Should().BeNull();
    }

    [Fact]
    public void GetAll_ShouldReturnAllUsers()
    {
        // Arrange
        var repo = new JsonUserRepository(_tempFilePath);
        var user1 = new User { Name = "User 1", Phone = "111", Type = UserType.Common };
        var user2 = new User { Name = "User 2", Phone = "222", Type = UserType.Common };
        repo.Add(user1);
        repo.Add(user2);
        repo.SaveChanges();

        // Act
        var users = repo.GetAll();

        // Assert (Admin inicial + user1 + user2 = 3)
        users.Should().HaveCount(3);
        users.Select(u => u.Name).Should().Contain(new[] { "Administrador", "User 1", "User 2" });
    }
}
