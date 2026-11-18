# 03.Reference — golden model

Modelo de referência em Python da multiplicação de matrizes por blocos (tiling). Ele calcula o resultado que o hardware deve produzir, e o ambiente de verificação compara C com ele. Dono: integração (Sistema).

Usa só a biblioteca padrão e roda no Python 3.9 da WSL do curso.

| Diretório | Conteúdo |
|---|---|
| `golden/` | o modelo |
| `tools/` | geradores de casos de teste e comparadores (próximas entregas) |
| `tests/` | testes `unittest`, que também rodam com `pytest` |

## O que o modelo supõe sobre os outros blocos

Algumas escolhas são do acelerador ou do DMA. No modelo, cada uma é um parâmetro, e o valor padrão vale até o dono confirmar.

| Escolha | Parâmetro | Padrão | Dono |
|---|---|---|---|
| Formato dos números | `NumericFormat(data_bits, acc_bits, signed)` | operandos de 8 bits com sinal; acumulador e C de 32 bits. O estouro dá a volta: em complemento de 2 com sinal, módulo 2^n sem sinal. `signed` vale para operandos e acumulador juntos | Acelerador |
| Tamanho dos blocos | `TileConfig(tile_m, tile_n, tile_k)` ou `TileConfig.square(N)` | N × N, o tamanho da malha | Acelerador, DMA |
| Ordem dos blocos | `TileConfig(..., order)`, laços de fora para dentro | `nkm`: um bloco de B fica fixo enquanto os blocos de A passam. É o jeito de trabalhar do acelerador do time, *weight-stationary*: os "pesos" (B) ficam parados dentro da malha | DMA |

## Uso

Com `03.Reference/` no `PYTHONPATH`:

```python
import random
from golden import NumericFormat, TileConfig, generate, matmul_reference, matmul_tiled

fmt = NumericFormat(data_bits=8, acc_bits=32, signed=True)
rng = random.Random(1)
a = generate(17, 13, fmt, rng)            # A: 17 x 13
b = generate(13, 11, fmt, rng)            # B: 13 x 11
c = matmul_tiled(a, b, fmt, TileConfig.square(4))
assert c == matmul_reference(a, b, fmt)
```

| Função | O que faz |
|---|---|
| `generate(rows, cols, fmt, rng, pattern)` | matriz de teste: `random`, `zeros`, `max`, `min` ou `identity` |
| `matmul_reference(a, b, fmt)` | C = A × B direto |
| `matmul_tiled(a, b, fmt, cfg)` | C = A × B bloco a bloco, somando cada bloco parcial em C como o hardware faz |
| `tile_schedule(m, n, k, cfg)` | a sequência de blocos, com os blocos de borda recortados |

## Testes

A partir da raiz do repositório:

```bash
make test                       # WSL, Python 3.9 (a comparação com numpy é pulada)
python -m pytest 03.Reference   # Windows
```

Os testes cobrem:
- cada produto A[i][x]·B[x][j] aparece em exatamente um bloco, para N = 2, 4 e 8, as 6 ordens de laços e blocos não quadrados;
- a sequência de blocos de cada ordem é igual à de um cálculo independente;
- o resultado por blocos é igual ao direto em matrizes múltiplas de N, não múltiplas e menores que a malha;
- operandos de 8, 16 e 32 bits, com e sem sinal;
- valores extremos e estouro do acumulador;
- mesma seed, mesmas matrizes;
- rejeição de entradas inválidas;
- comparação com numpy, quando ele está instalado.
