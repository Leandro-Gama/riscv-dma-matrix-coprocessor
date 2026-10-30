# 03.Reference — golden model

Modelo de referência em Python da multiplicação matricial por blocos (tiling), base da verificação automática. Dono: integração (Sistema).

| Diretório | Conteúdo |
|---|---|
| `golden/` | núcleo do modelo; só biblioteca padrão, compatível com Python 3.9 |
| `tools/` | geradores de casos de teste e comparadores |
| `tests/` | testes `unittest` (também rodam com `pytest`) |

Executar os testes, a partir da raiz do repositório:

```bash
make test                     # WSL, python3 do curso
python -m pytest 03.Reference # Windows
```
