namespace PerformanceLab.Infrastructure.Time;

using PerformanceLab.Core.Abstractions;

public class SystemClock : IClock
{
    public DateTime UtcNow => DateTime.UtcNow;
}
