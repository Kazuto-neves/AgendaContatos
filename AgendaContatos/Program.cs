using AgendaContatos.Repositories;
using AgendaContatos.Services;
using AgendaContatos.UI;
using Microsoft.Extensions.DependencyInjection;

namespace AgendaContatos;

public class Program
{
    public static void Main(string[] args)
    {
        var services = new ServiceCollection();

        // 1. Repositório configurado como Singleton
        services.AddSingleton<IUserRepository, JsonUserRepository>();

        // 2. Serviços e UI configurados como Transient
        services.AddTransient<IAuthService, AuthService>();
        services.AddTransient<IUserService, UserService>();
        services.AddTransient<ConsoleUI>();

        // 3. Construção do Container de DI
        var serviceProvider = services.BuildServiceProvider();

        // 4. Resolução da UI e execução do ciclo de vida
        var app = serviceProvider.GetRequiredService<ConsoleUI>();
        app.Run();
    }
}
