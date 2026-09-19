namespace PerformanceLab.Benchmarks.Suites;

using System.Text.Json;
using BenchmarkDotNet.Attributes;
using Newtonsoft.Json;
using PerformanceLab.Core.Models;

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 5)]
public class SerializationBenchmarks
{
    private Order _sampleOrder = null!;
    private string _systemTextJsonString = null!;
    private string _newtonsoftJsonString = null!;

    [GlobalSetup]
    public void Setup()
    {
        _sampleOrder = new Order
        {
            Id = Guid.NewGuid(),
            CustomerName = "Alan Turing",
            CustomerEmail = "alan@turing.org",
            TotalAmount = 1450.75m,
            Status = OrderStatus.Processing,
            CreatedAtUtc = DateTime.UtcNow,
            Items =
            [
                new OrderItem(Guid.NewGuid(), "Universal Machine Part A", 2, 250m),
                new OrderItem(Guid.NewGuid(), "Universal Machine Part B", 1, 500m),
                new OrderItem(Guid.NewGuid(), "Logic Circuit Set", 5, 80.15m),
                new OrderItem(Guid.NewGuid(), "Copper Tape Roll", 10, 5m)
            ]
        };

        _systemTextJsonString = System.Text.Json.JsonSerializer.Serialize(_sampleOrder);
        _newtonsoftJsonString = JsonConvert.SerializeObject(_sampleOrder);
    }

    [Benchmark(Baseline = true)]
    public string SystemTextJson_Serialize()
    {
        return System.Text.Json.JsonSerializer.Serialize(_sampleOrder);
    }

    [Benchmark]
    public string NewtonsoftJson_Serialize()
    {
        return JsonConvert.SerializeObject(_sampleOrder);
    }

    [Benchmark]
    public Order? SystemTextJson_Deserialize()
    {
        return System.Text.Json.JsonSerializer.Deserialize<Order>(_systemTextJsonString);
    }

    [Benchmark]
    public Order? NewtonsoftJson_Deserialize()
    {
        return JsonConvert.DeserializeObject<Order>(_newtonsoftJsonString);
    }
}
