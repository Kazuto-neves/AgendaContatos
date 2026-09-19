namespace PerformanceLab.Benchmarks.Suites;

using BenchmarkDotNet.Attributes;
using Humanizer;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class HumanizerBenchmarks
{
    private const string Word = "benchmark_metric_analysis";
    private const int LargeNumber = 987654;

    [Benchmark(Baseline = true)]
    public string StandardStringManipulation()
    {
        return Word.Replace('_', ' ').ToUpperInvariant();
    }

    [Benchmark]
    public string HumanizerTitleize()
    {
        return Word.Titleize();
    }

    [Benchmark]
    public string HumanizerPluralize()
    {
        return "order".Pluralize();
    }

    [Benchmark]
    public string HumanizerToWords()
    {
        return LargeNumber.ToWords();
    }
}
