# 0002 — Somas parciais de K acumuladas pelo DMA, com C em DATA_WIDTH bits

- **Status:** proposta
- **Data:** 22/11/2026
- **Blocos afetados:** DMA, Acelerador, Sistema
- **Aprovações:** —

## Contexto

Ficou em aberto na especificação da E1 (seção 8, "Somas parciais e ordem dos blocos") e no plano de verificação (P1 e P2). O RTL do acelerador entregue na E2:
- zera as somas parciais a cada START, ou seja, não acumula entre um bloco e outro de K;
- guarda em `DATA_OUT` só os `DATA_WIDTH` bits baixos de cada resultado.

Quando K > `ARRAY_SIZE`, alguém precisa somar os blocos parciais de C. O DMA precisava dessa resposta para fechar a FSM.

## Alternativas

| Alternativa | Prós | Contras |
|---|---|---|
| **DMA soma: lê C, soma o bloco novo e grava de volta** | não muda o acelerador; funciona com qualquer ordem de blocos | mais tráfego de C no barramento (uma leitura a mais por elemento a partir do segundo bloco de K) |
| Acelerador ganha modo de acumulação entre STARTs | menos tráfego; o DMA só grava C no último bloco de K | muda o RTL e o testbench da E2; obriga a percorrer todos os K de um bloco de C antes de passar ao próximo, recarregando os pesos com mais frequência |
| `DATA_OUT` com o acumulador inteiro e C em 32 bits | resultado sem estouro para os casos pequenos | muda o tamanho do buffer de saída, o acelerador e o golden; não resolve a soma entre blocos sozinho |

## Critérios e evidência

- **Não mexer no que já foi entregue e verificado na E2.** A primeira alternativa usa o acelerador como está.
- **Fechar com o golden.** `golden/systolic_array.py` já soma bloco a bloco e devolve o resultado com *wrap* em `DATA_WIDTH` bits. Somando no DMA módulo 2^`DATA_WIDTH`, o resultado é o mesmo, sem precisar mudar o golden.
- **Custo medido.** No testbench da E3, com `ARRAY_SIZE` = 8 e `DATA_WIDTH` = 8, um bloco só (8 × 8 × 8) leva 1014 ciclos e K = 24 (três blocos de K) leva 3414 ciclos. A leitura extra de C pesa, mas cabe na decisão do ADR 0001 de deixar o desempenho para depois.

## Decisão

- O DMA soma as parciais: no primeiro bloco de K grava C direto; nos seguintes, lê C, soma e grava.
- C fica com `DATA_WIDTH` bits por elemento, no mesmo formato de A e B, e a soma dá a volta módulo 2^`DATA_WIDTH`.
- Ordem dos blocos: n por fora, k no meio, m por dentro. O bloco de B (pesos) é carregado uma vez e os blocos de A passam por ele, como no weight-stationary.

## Consequências

- **ICD:** a seção 4 da especificação dizia "C com 4 bytes (32 bits) por elemento" (provisório). Passa a ser `DATA_WIDTH / 8` bytes, igual a A e B.
- **DMA:** já implementado assim na E3 (`04.RTL/dma`).
- **Acelerador:** nada muda.
- **Verificação:** o golden de referência para C é `systolic_array()`; o testbench da E3 já usa.
- **Revisitar na análise final:** se o tráfego de C pesar nos ciclos, o modo de acumulação no acelerador volta a ser opção, por novo ADR.
