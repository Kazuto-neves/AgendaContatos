# Commandos a ser execultados

## Uso básico — roda clean + restore + build + test + lista transitivos
~~~shell
./packge.sh
~~~

## Uso básico — roda clean + restore + build + test + lista transitivos (Realease)
~~~shell
./packge.sh -c Release
~~~

## Executar também a API e cronometrar a subida (mata após 30s)
~~~shell
./packge.sh --run Api --timeout 30
~~~

## Modo Release (recomendado para benchmark) (mata após 30s)
~~~shell
./packge.sh -c Release --run Api --timeout 30
~~~

## Pular clean (build incremental, mais rápido)
~~~shell
./packge.sh --skip-clean
~~~

## Sem testes
~~~shell
./packge.sh --no-test
~~~

# Test

## Criar pedido (MediatR + FluentValidation + Mapster + repo in-memory)
~~~shell
curl -X POST http://localhost:5299/api/v1/orders \
  -H 'Content-Type: application/json' \
  -d '{
    "customerName": "Ada Lovelace",
    "customerEmail": "ada@example.com",
    "items": [
      { "productName": "Keyboard", "quantity": 1, "unitPrice": 199.90 },
      { "productName": "Mouse",    "quantity": 2, "unitPrice": 49.50  }
    ]
  }'
~~~

## Listar paginado
~~~shell
curl "http://localhost:5299/api/v1/orders?page=1&pageSize=10"
~~~


# Comparador

## Console

~~~shell
./compare.sh
~~~

## Markdown

~~~shell
./compare.sh --format markdown
~~~

## CSV 

~~~shell
./compare.sh --format csv
~~~

## HTML

~~~shell
./compare.sh --format html
~~~

## Tudo

~~~shell
./compare.sh --format all
~~~

## Pasta Customizada

~~~shell
./compare.sh --format markdown --out docs/benchmarks
~~~
