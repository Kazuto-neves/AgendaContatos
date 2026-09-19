namespace PerformanceLab.Benchmarks.Suites;

using BenchmarkDotNet.Attributes;
using Bogus;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class BogusBenchmarks
{
    private Faker _faker = null!;

    [GlobalSetup]
    public void Setup()
    {
        _faker = new Faker();
    }

    [Benchmark(Baseline = true)]
    public string GenerateSingleCustomerName()
    {
        return _faker.Name.FullName();
    }

    [Benchmark]
    public List<string> GenerateTenCustomerNames()
    {
        var names = new List<string>(10);
        for (int i = 0; i < 10; i++)
        {
            names.Add(_faker.Name.FullName());
        }
        return names;
    }

    [Benchmark]
    public List<string> GenerateFiftyCustomerNames()
    {
        var names = new List<string>(50);
        for (int i = 0; i < 50; i++)
        {
            names.Add(_faker.Name.FullName());
        }
        return names;
    }
}
