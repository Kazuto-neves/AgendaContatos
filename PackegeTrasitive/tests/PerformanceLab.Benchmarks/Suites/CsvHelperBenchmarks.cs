namespace PerformanceLab.Benchmarks.Suites;

using System.Globalization;
using BenchmarkDotNet.Attributes;
using CsvHelper;
using CsvHelper.Configuration;

public record BenchmarkCsvRecord(int Id, string Name, string Email, decimal Amount, DateTime CreatedAt);

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class CsvHelperBenchmarks
{
    private List<BenchmarkCsvRecord> _records = null!;
    private string _csvData = null!;

    [GlobalSetup]
    public void Setup()
    {
        _records = Enumerable.Range(1, 100).Select(i => new BenchmarkCsvRecord(
            Id: i,
            Name: $"User {i}",
            Email: $"user{i}@benchmark.com",
            Amount: i * 19.99m,
            CreatedAt: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(i)
        )).ToList();

        using var writer = new StringWriter();
        using var csv = new CsvWriter(writer, new CsvConfiguration(CultureInfo.InvariantCulture));
        csv.WriteRecords(_records);
        _csvData = writer.ToString();
    }

    [Benchmark(Baseline = true)]
    public string WriteCsv_100Rows()
    {
        using var writer = new StringWriter();
        using var csv = new CsvWriter(writer, new CsvConfiguration(CultureInfo.InvariantCulture));
        csv.WriteRecords(_records);
        return writer.ToString();
    }

    [Benchmark]
    public List<BenchmarkCsvRecord> ReadCsv_100Rows()
    {
        using var reader = new StringReader(_csvData);
        using var csv = new CsvReader(reader, new CsvConfiguration(CultureInfo.InvariantCulture));
        return csv.GetRecords<BenchmarkCsvRecord>().ToList();
    }
}
