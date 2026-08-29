using AgendaContatos.Enums;

namespace AgendaContatos.Models;

public class User
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public UserType Type { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User()
    {
    }

    public User(int id, string name, string phone, UserType type, DateTime createdAt, DateTime updatedAt)
    {
        Id = id;
        Name = name;
        Phone = phone;
        Type = type;
        CreatedAt = createdAt;
        UpdatedAt = updatedAt;
    }

    public void UpdatePersonalInfo(string newName, string newPhone)
    {
        Name = newName;
        Phone = newPhone;
        //TODO: Mudar para testar com o Edu
        UpdatedAt = DateTime.Now;
    }

    public void UpdateType(UserType newType)
    {
        Type = newType;
        //TODO: Mudar para testar com o Edu
        UpdatedAt = DateTime.Now;
    }
}
