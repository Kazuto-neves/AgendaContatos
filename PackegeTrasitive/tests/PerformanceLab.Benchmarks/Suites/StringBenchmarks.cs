namespace PerformanceLab.Benchmarks.Suites;

using System.Text;
using BenchmarkDotNet.Attributes;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class StringBenchmarks
{
    private string[] _words = null!;

    [GlobalSetup]
    public void Setup()
    {
        _words = ["Performance", "Lab", "Baseline", "DotNet8", "DotNet10", "BenchmarkDotNet", "Runtime", "Optimization"];
    }

    [Benchmark(Baseline = true)]
    public string PlusOperatorConcat()
    {
        var result = "";
        for (int i = 0; i < _words.Length; i++)
        {
            result += _words[i] + "-";
        }
        return result;
    }

    [Benchmark]
    public string StringBuilderConcat()
    {
        var sb = new StringBuilder(128);
        for (int i = 0; i < _words.Length; i++)
        {
            sb.Append(_words[i]).Append('-');
        }
        return sb.ToString();
    }

    [Benchmark]
    public string StringJoinConcat()
    {
        return string.Join('-', _words) + "-";
    }

    [Benchmark]
    public string StringInterpolation()
    {
        return $"{_words[0]}-{_words[1]}-{_words[2]}-{_words[3]}-{_words[4]}-{_words[5]}-{_words[6]}-{_words[7]}-";
    }
}
