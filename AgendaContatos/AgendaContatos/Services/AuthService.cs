using AgendaContatos.Models;
using AgendaContatos.Repositories;

namespace AgendaContatos.Services;

public class AuthService : IAuthService
{
    private readonly IUserRepository _userRepository;

    public User? CurrentUser { get; private set; }

    public AuthService(IUserRepository userRepository)
    {
        _userRepository = userRepository;
    }

    public bool Login(int id)
    {
        var user = _userRepository.GetById(id);
        if (user == null)
        {
            CurrentUser = null;
            return false;
        }

        CurrentUser = user;
        return true;
    }

    public void Logout()
    {
        CurrentUser = null;
    }
}
