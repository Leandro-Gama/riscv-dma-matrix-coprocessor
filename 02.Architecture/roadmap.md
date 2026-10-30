# Roadmap

Documento vivo. Cada entrega parcial é um épico, dividido em sprints curtas. As decisões de arquitetura não são tomadas aqui: elas saem dos estudos do E1 e ficam registradas como ADRs em [decisions/](decisions/).

Depois do E1, a integração avança tratando CPU, DMA e acelerador como **interfaces**: modelos comportamentais com as portas do ICD, trocados pelo RTL real conforme cada bloco é entregue.

Status: `—` não iniciada · `em andamento` · `concluída` · `concluída c/ pendências`

## Sprint 0 — Ambiente (29–30/10)

| Sprint | Objetivo | Status |
|---|---|---|
| 0 | Estrutura do repositório, convenções, Makefile, `make check`, ambiente UVM de diagnóstico | concluída c/ pendências |

## E1 — Planejamento, microarquitetura e golden model (até 01/11)

O enunciado pede:
- repositório com estrutura e primeiro commit;
- especificação com diagrama de blocos, mapa de memória e sinais de interface entre CPU, DMA e acelerador;
- golden model com tiling.

| Sprint | Período | Objetivo | Saídas | Status |
|---|---|---|---|---|
| 1.0 | 30/10 | Repositório no GitHub, colegas convidados, primeiro commit; cada colega roda `make check` | repositório, `main` protegida | — |
| 1.1 | 30/10 | Requisitos e critérios | `requirements.md`, restrições, critérios de decisão, backlog de perguntas | — |
| 1.2 | 30/10 | Estudo de topologia e interconexão | estudo, ADR(s), diagrama top-level v1 | — |
| 1.3 | 31/10 | Estudo de interfaces e protocolos | ADRs, **ICD v1.0** (sinais, temporização, mapa de memória e de registradores) | — |
| 1.4 | 31/10 | Esqueleto da arquitetura de verificação (o estudo completo vai para a sprint 2.0) | esqueleto do plano de verificação, perguntas em aberto | — |
| 1.5 | 30–31/10 | Golden model (Python) | modelo com tiling, modelo de ciclos, geradores, testes | — |
| 1.6 | 01/11 | Fechamento do E1 | especificação única em `08.Docs/e1_especificacao.md` (diagrama, mapa de memória, sinais; aponta para o ICD), relatório consolidado da entrega em `08.Docs/e1_relatorio.md`, ICD v1.0, tag `e1` | — |

**O que cada bloco entrega no E1:**

| Quando | O quê |
|---|---|
| 30/10 | Cada dono descreve restrições e preferências para a interface do seu bloco (meia página). |
| 31/10 | Todos revisam o ICD v0.9. |
| 01/11 | ICD v1.0 aprovado. |

## E2 — Acelerador e infraestrutura de integração (02/11 → 14/11)

| Sprint | Período | Objetivo | Status |
|---|---|---|---|
| 2.0 | 02/11 | Estudo da arquitetura de verificação: estratégia por nível, UVM integrado, consumo do golden model, checagem, cobertura (ADR + plano de verificação v0) | — |
| 2.1 | 03–05/11 | Package comum e memória compartilhada (RTL, testbench, assertions, síntese de verificação) | — |
| 2.2 | 04–07/11 | Barramento/interconexão e blocos de sistema (RTL, checker de protocolo, testbench) | — |
| 2.3 | 07–11/11 | Modelos comportamentais dos blocos + VIP do barramento + top-level esqueleto; primeira multiplicação ponta a ponta sobre modelos | — |
| 2.4 | 11–14/11 | Acelerador real no top-level esqueleto; fechamento do E2 (tag `e2`) | — |

**Entregas entre blocos:**

| Data | De → para | O quê |
|---|---|---|
| 03/11 | Sistema → Acelerador | vetores de teste do golden model |
| 06–07/11 | Sistema → DMA | RTL da memória e modelo do acelerador |
| 07/11 | CPU, DMA, Acelerador → Sistema | *stubs* que compilam com as portas do ICD |
| 09/11 | Sistema → DMA | VIP do barramento (agente que faz o papel da CPU) |
| 09/11 | Sistema → CPU | modelo do DMA |
| 12–14/11 | Acelerador | RTL e testbench unitário (2×2 e 4×4, no mínimo) |

## E3 — DMA e memória compartilhada, sem CPU (15/11 → 22/11)

| Sprint | Período | Objetivo | Status |
|---|---|---|---|
| 3.1 | 15–18/11 | Ambiente de subsistema: o testbench faz o papel da CPU; memória e acelerador reais | — |
| 3.2 | 18–22/11 | DMA real integrado, regressão por seeds × tamanho da malha, waveform, tag `e3` | — |

**Entregas entre blocos:** DMA entrega o RTL por volta de 17–18/11. A CPU entrega o core com porta de dados externa (mesmo incompleto).

## E4 — Top-level, firmware e UVM integrado (23/11 → 13/12)

| Sprint | Período | Objetivo | Status |
|---|---|---|---|
| 4.1 | 23–29/11 | CPU real e firmware no top-level; resultado igual ao golden | — |
| 4.2 | 30/11–06/12 | UVM integrado completo, cobertura, regressão nas 3 configurações, plano de verificação | — |
| 4.3 | 07–13/12 | Robustez (injeção de falhas, casos de canto), ensaio da síntese do sistema, tag `e4` | — |

**Entregas entre blocos:**

| Data | Bloco | O quê |
|---|---|---|
| 24/11 | CPU | core |
| 25/11 | CPU | firmware |
| 29/11 | time | decisão sobre interrupção |
| 06/12 | todos | relatórios de síntese de cada bloco |

## Final — Síntese do sistema, análise, demo e relatório (14/12 → 19/12)

| Sprint | Período | Objetivo | Status |
|---|---|---|---|
| F.1 | 14–15/12 | Síntese do sistema nas 3 configurações, métricas e ciclos medidos | — |
| F.2 | 15–16/12 | Análise de trade-offs (área, fmax, ciclos, latência, utilização) e relatório | — |
| F.3 | 16–17/12 | Demo em waveform, slides consolidados, ensaio; tag `final` | — |

**Entregas entre blocos:** cada bloco entrega a sua seção do relatório e os seus slides até 15/12.
