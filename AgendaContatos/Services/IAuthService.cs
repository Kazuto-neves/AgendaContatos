using AgendaContatos.Models;

namespace AgendaContatos.Services;

public interface IAuthService
{
    User? CurrentUser { get; }
    bool Login(int id);
    void Logout();
}
