namespace PerformanceLab.Core.Abstractions;

public interface IClock
{
    DateTime UtcNow { get; }
}
