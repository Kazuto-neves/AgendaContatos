using AgendaContatos.Enums;
using AgendaContatos.Exceptions;
using AgendaContatos.Models;
using AgendaContatos.Repositories;

namespace AgendaContatos.Services;

public class UserService : IUserService
{
    private readonly IUserRepository _userRepository;

    public UserService(IUserRepository userRepository)
    {
        _userRepository = userRepository;
    }

    public List<User> SearchUsers(string term, User? currentUser)
    {
        if (currentUser == null)
        {
            throw new BusinessRuleException("Você precisa estar logado.");
        }

        var searchTerm = term?.Trim() ?? string.Empty;
        var allUsers = _userRepository.GetAll();

        bool isNumeric = int.TryParse(searchTerm, out int searchId);

        var query = allUsers.Where(u =>
            (isNumeric && u.Id == searchId) ||
            u.Name.Contains(searchTerm, StringComparison.OrdinalIgnoreCase) ||
            u.Phone.Contains(searchTerm, StringComparison.OrdinalIgnoreCase)
        );

        if (currentUser.Type == UserType.Common)
        {
            return query.Where(u => u.Id == currentUser.Id).ToList();
        }

        return query.ToList();
    }

    public List<User> GetAllUsers(User? currentUser)
    {
        if (currentUser == null)
        {
            throw new BusinessRuleException("Você precisa estar logado.");
        }

        if (currentUser.Type != UserType.Super)
        {
            throw new BusinessRuleException("Apenas SUPER pode ver a lista completa.");
        }

        return _userRepository.GetAll();
    }

    public void AddUser(User newUser, User? currentUser)
    {
        if (currentUser == null)
        {
            throw new BusinessRuleException("Você precisa estar logado.");
        }

        if (currentUser.Type != UserType.Super)
        {
            throw new BusinessRuleException("Apenas SUPER pode adicionar contatos.");
        }

        if (newUser == null || string.IsNullOrWhiteSpace(newUser.Name) || newUser.Name.Trim().Length < 3)
        {
            throw new BusinessRuleException("O nome é obrigatório e deve conter no mínimo 3 caracteres.");
        }

        if (string.IsNullOrWhiteSpace(newUser.Phone))
        {
            throw new BusinessRuleException("O telefone é obrigatório.");
        }

        string trimmedPhone = newUser.Phone.Trim();
        if (_userRepository.GetAll().Any(u => u.Phone.Trim().Equals(trimmedPhone, StringComparison.OrdinalIgnoreCase)))
        {
            throw new BusinessRuleException("Já existe um usuário cadastrado com este telefone.");
        }

        newUser.Name = newUser.Name.Trim();
        newUser.Phone = trimmedPhone;

        _userRepository.Add(newUser);
        _userRepository.SaveChanges();
    }

    public void UpdateUser(int targetId, string newName, string newPhone, UserType? newType, User? currentUser)
    {
        if (currentUser == null)
        {
            throw new BusinessRuleException("Você precisa estar logado.");
        }

        var target = _userRepository.GetById(targetId);
        if (target == null)
        {
            throw new BusinessRuleException("Usuário não encontrado.");
        }

        if (currentUser.Type == UserType.Common && targetId != currentUser.Id)
        {
            throw new BusinessRuleException("Comuns só atualizam a si mesmos.");
        }

        if (string.IsNullOrWhiteSpace(newName) || newName.Trim().Length < 3)
        {
            throw new BusinessRuleException("O nome é obrigatório e deve conter no mínimo 3 caracteres.");
        }

        if (string.IsNullOrWhiteSpace(newPhone))
        {
            throw new BusinessRuleException("O telefone é obrigatório.");
        }

        string trimmedPhone = newPhone.Trim();
        if (_userRepository.GetAll().Any(u => u.Id != targetId && u.Phone.Trim().Equals(trimmedPhone, StringComparison.OrdinalIgnoreCase)))
        {
            throw new BusinessRuleException("Já existe outro usuário cadastrado com este telefone.");
        }

        target.UpdatePersonalInfo(newName.Trim(), trimmedPhone);

        if (currentUser.Type == UserType.Super && newType.HasValue)
        {
            target.UpdateType(newType.Value);
        }

        _userRepository.Update(target);
        _userRepository.SaveChanges();
    }

    public void DeleteUser(int targetId, User? currentUser)
    {
        if (currentUser == null)
        {
            throw new BusinessRuleException("Você precisa estar logado.");
        }

        if (currentUser.Type != UserType.Super)
        {
            throw new BusinessRuleException("Apenas SUPER pode excluir contatos.");
        }

        if (targetId == currentUser.Id)
        {
            throw new BusinessRuleException("Não é possível excluir a si mesmo.");
        }

        var target = _userRepository.GetById(targetId);
        if (target == null)
        {
            throw new BusinessRuleException("Usuário não encontrado.");
        }

        _userRepository.Delete(targetId);
        _userRepository.SaveChanges();
    }
}
