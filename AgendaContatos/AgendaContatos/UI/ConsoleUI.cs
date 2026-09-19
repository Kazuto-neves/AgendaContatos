using AgendaContatos.Enums;
using AgendaContatos.Exceptions;
using AgendaContatos.Models;
using AgendaContatos.Services;

namespace AgendaContatos.UI;

public class ConsoleUI
{
    private readonly IAuthService _authService;
    private readonly IUserService _userService;

    public ConsoleUI(IAuthService authService, IUserService userService)
    {
        _authService = authService;
        _userService = userService;
    }

    public void Run()
    {
        bool isRunning = true;

        while (isRunning)
        {
            if (_authService.CurrentUser == null)
            {
                isRunning = ShowLoginScreen();
            }
            else
            {
                ShowMainMenu();
            }
        }

        Console.Clear();
        Console.WriteLine("Aplicação encerrada. Até logo!");
    }

    private bool ShowLoginScreen()
    {
        Console.Clear();
        Console.WriteLine("==================================================");
        Console.WriteLine("          AGENDA DE CONTATOS - LOGIN              ");
        Console.WriteLine("==================================================");
        Console.WriteLine("Dica: O usuário inicial padrão é o Administrador (ID: 1).");
        Console.WriteLine();
        Console.Write("Digite seu ID de usuário (ou 'sair' para fechar): ");

        var input = Console.ReadLine()?.Trim();

        if (string.Equals(input, "sair", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!int.TryParse(input, out int id))
        {
            ShowError("ID inválido! Por favor, digite um número inteiro.");
            Pause();
            return true;
        }

        if (!_authService.Login(id))
        {
            ShowError($"Usuário com ID '{id}' não foi encontrado.");
            Pause();
            return true;
        }

        ShowSuccess($"Login realizado com sucesso! Bem-vindo(a), {_authService.CurrentUser!.Name}.");
        Pause();
        return true;
    }

    private void ShowMainMenu()
    {
        var user = _authService.CurrentUser!;
        Console.Clear();
        Console.WriteLine("==================================================");
        Console.WriteLine($" Usuário: {user.Name} (ID: {user.Id}) | Perfil: {user.Type}");
        Console.WriteLine("==================================================");
        Console.WriteLine("Menu Principal:");
        Console.WriteLine("1. Buscar contato (ID/Nome/Telefone)");
        Console.WriteLine("2. Atualizar dados");

        if (user.Type == UserType.Super)
        {
            Console.WriteLine("3. Adicionar novo contato");
            Console.WriteLine("4. Listar todos os contatos");
            Console.WriteLine("5. Excluir contato");
        }

        Console.WriteLine("0. Sair (Logout)");
        Console.WriteLine("==================================================");
        Console.Write("Escolha uma opção: ");

        var option = Console.ReadLine()?.Trim();
        Console.WriteLine();

        try
        {
            switch (option)
            {
                case "1":
                    SearchContacts();
                    break;
                case "2":
                    UpdateContact(user);
                    break;
                case "3" when user.Type == UserType.Super:
                    AddContact();
                    break;
                case "4" when user.Type == UserType.Super:
                    ListAllContacts();
                    break;
                case "5" when user.Type == UserType.Super:
                    DeleteContact();
                    break;
                case "0":
                    _authService.Logout();
                    ShowSuccess("Logout realizado com sucesso!");
                    Pause();
                    break;
                default:
                    ShowError("Opção inválida! Tente novamente.");
                    Pause();
                    break;
            }
        }
        catch (BusinessRuleException ex)
        {
            ShowError($"[Regra de Negócio] {ex.Message}");
            Pause();
        }
        catch (Exception ex)
        {
            ShowError($"[Erro Inesperado] {ex.Message}");
            Pause();
        }
    }

    private void SearchContacts()
    {
        Console.WriteLine("--- BUSCAR CONTATO ---");
        Console.Write("Digite o termo de busca (ID, Nome ou Telefone): ");
        var term = Console.ReadLine() ?? string.Empty;

        var results = _userService.SearchUsers(term, _authService.CurrentUser);
        DisplayUsersTable(results);
        Pause();
    }

    private void ListAllContacts()
    {
        Console.WriteLine("--- LISTA COMPLETA DE CONTATOS ---");
        var results = _userService.GetAllUsers(_authService.CurrentUser);
        DisplayUsersTable(results);
        Pause();
    }

    private void AddContact()
    {
        Console.WriteLine("--- ADICIONAR NOVO CONTATO ---");
        Console.Write("Nome (mínimo 3 caracteres): ");
        var name = Console.ReadLine() ?? string.Empty;

        Console.Write("Telefone: ");
        var phone = Console.ReadLine() ?? string.Empty;

        Console.Write("Tipo (1 - Comum, 2 - Super) [Padrão: 1]: ");
        var typeInput = Console.ReadLine()?.Trim();
        UserType type = typeInput == "2" ? UserType.Super : UserType.Common;

        var newUser = new User
        {
            Name = name,
            Phone = phone,
            Type = type
        };

        _userService.AddUser(newUser, _authService.CurrentUser);
        ShowSuccess("Contato cadastrado com sucesso!");
        Pause();
    }

    private void UpdateContact(User currentUser)
    {
        Console.WriteLine("--- ATUALIZAR DADOS ---");
        int targetId;

        if (currentUser.Type == UserType.Common)
        {
            targetId = currentUser.Id;
            Console.WriteLine($"Atualizando seus próprios dados (ID: {targetId}).");
        }
        else
        {
            Console.Write("Digite o ID do contato que deseja atualizar: ");
            if (!int.TryParse(Console.ReadLine(), out targetId))
            {
                ShowError("ID inválido.");
                Pause();
                return;
            }
        }

        Console.Write("Novo Nome: ");
        var newName = Console.ReadLine() ?? string.Empty;

        Console.Write("Novo Telefone: ");
        var newPhone = Console.ReadLine() ?? string.Empty;

        UserType? newType = null;
        if (currentUser.Type == UserType.Super)
        {
            Console.Write("Alterar Tipo? (1 - Comum, 2 - Super, deixe vazio para manter atual): ");
            var typeInput = Console.ReadLine()?.Trim();
            if (typeInput == "1")
            {
                newType = UserType.Common;
            }
            else if (typeInput == "2")
            {
                newType = UserType.Super;
            }
        }

        _userService.UpdateUser(targetId, newName, newPhone, newType, currentUser);
        ShowSuccess("Contato atualizado com sucesso!");
        Pause();
    }

    private void DeleteContact()
    {
        Console.WriteLine("--- EXCLUIR CONTATO ---");
        Console.Write("Digite o ID do contato que deseja excluir: ");
        if (!int.TryParse(Console.ReadLine(), out int targetId))
        {
            ShowError("ID inválido.");
            Pause();
            return;
        }

        Console.Write($"Tem certeza de que deseja excluir o contato ID {targetId}? (s/n): ");
        var confirmation = Console.ReadLine()?.Trim();

        if (string.Equals(confirmation, "s", StringComparison.OrdinalIgnoreCase))
        {
            _userService.DeleteUser(targetId, _authService.CurrentUser);
            ShowSuccess($"Contato ID {targetId} excluído com sucesso!");
        }
        else
        {
            Console.WriteLine("Exclusão cancelada pelo usuário.");
        }

        Pause();
    }

    private void DisplayUsersTable(List<User> users)
    {
        Console.WriteLine();
        if (users == null || users.Count == 0)
        {
            Console.WriteLine("Nenhum contato encontrado.");
            Console.WriteLine();
            return;
        }

        Console.WriteLine(new string('-', 105));
        Console.WriteLine(string.Format("{0,-6} | {1,-30} | {2,-16} | {3,-8} | {4,-19} | {5,-19}",
            "ID", "Nome", "Telefone", "Tipo", "Criado em", "Atualizado em"));
        Console.WriteLine(new string('-', 105));

        foreach (var user in users)
        {
            Console.WriteLine(string.Format("{0,-6} | {1,-30} | {2,-16} | {3,-8} | {4,-19:dd/MM/yyyy HH:mm:ss} | {5,-19:dd/MM/yyyy HH:mm:ss}",
                user.Id,
                Truncate(user.Name, 30),
                Truncate(user.Phone, 16),
                user.Type,
                user.CreatedAt,
                user.UpdatedAt));
        }

        Console.WriteLine(new string('-', 105));
        Console.WriteLine($"Total: {users.Count} contato(s) exibido(s).");
        Console.WriteLine();
    }

    private static string Truncate(string value, int maxLength)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;
        return value.Length <= maxLength ? value : value.Substring(0, maxLength - 3) + "...";
    }

    private static void ShowError(string message)
    {
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine($"\n[ERRO] {message}");
        Console.ResetColor();
    }

    private static void ShowSuccess(string message)
    {
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"\n[SUCESSO] {message}");
        Console.ResetColor();
    }

    private static void Pause()
    {
        Console.WriteLine("\nPressione qualquer tecla para continuar...");
        Console.ReadKey(intercept: true);
    }
}
