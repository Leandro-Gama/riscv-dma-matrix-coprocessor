# RISC-V com coprocessador de multiplicação matricial e DMA

Sistema digital que calcula **C = A × B**. Uma CPU RISC-V RV32I configura e dispara a operação, um controlador de DMA move os dados de forma autônoma entre a memória compartilhada e o acelerador, e um *systolic array* parametrizável (`ARRAY_SIZE` = 2, 4, 8) faz a multiplicação, com particionamento em blocos (*tiling*) para matrizes maiores que a malha.

Projeto final da Fase 03 do CI Digital. O enunciado está em [01.Specs/](01.Specs/). O `task_division_schema.png` de lá só divide as tarefas entre os blocos. A arquitetura do sistema é definida nos estudos da entrega 1 e registrada em [02.Architecture/](02.Architecture/).

## Status

| Entrega | Data | Status |
|---|---|---|
| E1 · Planejamento, microarquitetura e golden model | 01/11/2026 | em andamento |
| E2 · RTL do acelerador e testes unitários | 14/11/2026 | — |
| E3 · RTL do DMA e memória compartilhada | 22/11/2026 | — |
| E4 · Integração top-level, firmware e UVM integrado | 13/12/2026 | — |
| Final · relatório e apresentação | 18–19/12/2026 | — |

O andamento detalhado por sprint está em [02.Architecture/roadmap.md](02.Architecture/roadmap.md).

## Time

| Bloco | Responsável | Diretórios |
|---|---|---|
| CPU (RV32I + firmware) | _a preencher_ | `04.RTL/cpu`, `06.Firmware` |
| DMA | _a preencher_ | `04.RTL/dma` |
| Acelerador (systolic array) | _a preencher_ | `04.RTL/accel` |
| Sistema (memória, barramento, top-level, golden model, UVM integrado) | Leandro Gama | `04.RTL/common`, `04.RTL/soc`, `03.Reference`, `05.Verification/{common,models,subsys,soc}` |

## Estrutura

| Diretório | Conteúdo |
|---|---|
| [01.Specs/](01.Specs/) | enunciado e divisão de tarefas (somente leitura) |
| [02.Architecture/](02.Architecture/) | roadmap, requisitos, estudos, decisões (ADRs), contrato de interfaces (ICD), relatórios de sprint |
| [03.Reference/](03.Reference/) | modelo de referência (golden model) em Python |
| [04.RTL/](04.RTL/) | RTL em SystemVerilog sintetizável, um subdiretório por bloco |
| [05.Verification/](05.Verification/) | testbenches unitários, VIP, modelos, ambientes de subsistema e sistema (UVM) |
| [06.Firmware/](06.Firmware/) | firmware RISC-V (fonte e `.hex`) |
| [07.Synthesis/](07.Synthesis/) | scripts, constraints e reports do Genus |
| [08.Docs/](08.Docs/) | relatório, slides e evidências de cada entrega |

## Como rodar

Pré-requisitos (ambiente padrão do curso, WSL `cademics-cepedi`):

| Ferramenta | Versão | Observação |
|---|---|---|
| Cadence Xcelium | 24.09 | com UVM |
| Cadence Genus | 25.13 | — |
| Python | ≥ 3.9 | só biblioteca padrão |
| Verible | qualquer recente | lint; caminho configurável com `make VERIBLE_DIR=...` |
| GNU make, bash | — | — |

A partir da raiz do repositório:

```bash
git clone <url-do-repositorio> && cd riscv-dma-matrix-coprocessor
make help        # lista os alvos
make check       # testes Python + lint + elaboração (não precisa de licença)
make sim-smoke   # simulação UVM de diagnóstico do ambiente (precisa de licença)
```

Antes de simular, `cadence-check` deve passar. Se falhar, rode `cadence-login`.

As convenções de código e de colaboração estão em [CONTRIBUTING.md](CONTRIBUTING.md).
