namespace PerformanceLab.Benchmarks.Suites;

using BenchmarkDotNet.Attributes;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class LinqPagingBenchmarks
{
    private List<int> _numbers = null!;
    private int[] _numbersArray = null!;

    [GlobalSetup]
    public void Setup()
    {
        _numbers = Enumerable.Range(1, 10_000).ToList();
        _numbersArray = [.. _numbers];
    }

    [Benchmark(Baseline = true)]
    public List<int> LinqSkipTake()
    {
        return _numbers.Skip(500).Take(50).ToList();
    }

    [Benchmark]
    public List<int> ListGetRange()
    {
        return _numbers.GetRange(500, 50);
    }

    [Benchmark]
    public int[] ArraySpanSlice()
    {
        return _numbersArray.AsSpan(500, 50).ToArray();
    }
}
