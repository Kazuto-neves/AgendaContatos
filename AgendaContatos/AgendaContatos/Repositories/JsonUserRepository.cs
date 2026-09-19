using System.Text.Json;
using AgendaContatos.Enums;
using AgendaContatos.Models;

namespace AgendaContatos.Repositories;

public class JsonUserRepository : IUserRepository
{
    private readonly string _filePath;
    private readonly List<User> _users = new();
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true
    };

    public JsonUserRepository(string? filePath = null)
    {
        _filePath = filePath ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "users.json");
        LoadData();
    }

    private void LoadData()
    {
        if (File.Exists(_filePath))
        {
            try
            {
                var json = File.ReadAllText(_filePath);
                if (!string.IsNullOrWhiteSpace(json))
                {
                    var loadedUsers = JsonSerializer.Deserialize<List<User>>(json, SerializerOptions);
                    if (loadedUsers != null && loadedUsers.Count > 0)
                    {
                        _users.AddRange(loadedUsers);
                    }
                }
            }
            catch
            {
                _users.Clear();
            }
        }

        // Regra de Bootstrap: Se a lista estiver vazia, cria usuário Super padrão
        if (_users.Count == 0)
        {
            var now = DateTime.Now;
            var defaultAdmin = new User
            {
                Id = 1,
                Name = "Administrador",
                Phone = "000000000",
                Type = UserType.Super,
                CreatedAt = now,
                UpdatedAt = now
            };
            _users.Add(defaultAdmin);
            SaveChanges();
        }
    }

    public List<User> GetAll()
    {
        return _users.ToList();
    }

    public User? GetById(int id)
    {
        return _users.FirstOrDefault(u => u.Id == id);
    }

    public void Add(User user)
    {
        user.Id = _users.Count > 0 ? _users.Max(u => u.Id) + 1 : 1;
        var now = DateTime.Now;
        user.CreatedAt = now;
        user.UpdatedAt = now;
        _users.Add(user);
    }

    public void Update(User user)
    {
        var existingIndex = _users.FindIndex(u => u.Id == user.Id);
        if (existingIndex >= 0)
        {
            _users[existingIndex] = user;
        }
    }

    public void Delete(int id)
    {
        var user = GetById(id);
        if (user != null)
        {
            _users.Remove(user);
        }
    }

    public void SaveChanges()
    {
        var json = JsonSerializer.Serialize(_users, SerializerOptions);
        File.WriteAllText(_filePath, json);
    }
}
