using AgendaContatos.Enums;
using AgendaContatos.Models;

namespace AgendaContatos.Services;

public interface IUserService
{
    List<User> SearchUsers(string term, User? currentUser);
    List<User> GetAllUsers(User? currentUser);
    void AddUser(User newUser, User? currentUser);
    void UpdateUser(int targetId, string newName, string newPhone, UserType? newType, User? currentUser);
    void DeleteUser(int targetId, User? currentUser);
}
