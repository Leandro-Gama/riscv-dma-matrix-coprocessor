# DMA

Controlador que move os blocos de A e B da memória de dados para o acelerador, dispara o cálculo e grava C de volta, sem a CPU. A CPU só escreve os registradores e espera `DONE` (ou a interrupção).

Parâmetros: `ARRAY_SIZE` = 2, 4 ou 8, `DATA_WIDTH` = 8, 16 ou 32 e `ACCEL_BASE` (padrão `0x4000_0000`). Precisam ser os mesmos do acelerador.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `dma_pkg.sv` | offsets dos registradores, mapa do acelerador, tipos da FSM |
| `dma_top.sv` | liga os blocos abaixo; portas planas `s_axi_*`, `m_axi_*` e `irq_o` |
| `dma_regs.sv` | escravo AXI4-Lite com os registradores (ADDR_A … STATUS) e `irq_o` |
| `dma_ctrl.sv` | FSM principal |
| `dma_dp.sv` | contadores de bloco e de elemento, geração de endereços, montagem das palavras e soma de C |
| `dma_axil_master.sv` | mestre AXI4-Lite, uma transação por vez |

## Registradores

Base `0x2000_0000`, conforme a seção 5 da [especificação da E1](../../08.Docs/e1_especificacao.md).

| Offset | Nome | Acesso | Conteúdo |
|---|---|---|---|
| `0x00` | `ADDR_A` | RW | endereço inicial de A |
| `0x04` | `ADDR_B` | RW | endereço inicial de B |
| `0x08` | `ADDR_C` | RW | endereço inicial de C |
| `0x0C` | `DIM_M` | RW | linhas de A e de C |
| `0x10` | `DIM_K` | RW | colunas de A = linhas de B |
| `0x14` | `DIM_N` | RW | colunas de B e de C |
| `0x18` | `CONTROL` | RW | bit 0 `START` (lê 0), bit 1 `IRQ_EN` |
| `0x1C` | `STATUS` | RO | bit 0 `BUSY`, bit 1 `DONE`, bit 2 `ERROR` |

- `ADDR_*` e `DIM_*` respeitam `WSTRB`. Escrevê-los com `BUSY` em 1 dá SLVERR e o valor não muda.
- `START` com `BUSY` em 1 é ignorado (OKAY). `START` aceito limpa `DONE` e `ERROR`.
- Escrita em `STATUS`, offset sem registrador ou endereço desalinhado: SLVERR.
- `irq_o` = `DONE` e `IRQ_EN`. Cai com um novo `START` ou com `IRQ_EN` = 0.

## Como uma operação anda

As matrizes ficam linha por linha na memória, com `DATA_WIDTH / 8` bytes por elemento (A, B e C). Os blocos são percorridos com n por fora, k no meio e m por dentro: o bloco de B é carregado uma vez como pesos e os blocos de A passam por ele.

| Estado | O que faz |
|---|---|
| `INIT` | zera os contadores de bloco; dimensão 0 vai direto para `FAIL` |
| `CLEAR` | escreve `CTRL.CLR_ERROR` no acelerador, para não herdar erro de uma operação anterior |
| `SETUP_A/B/C` | escolhe a matriz, calcula o endereço do bloco e quantas linhas e colunas valem nele |
| `GATHER` | lê da memória um elemento por vez e monta a palavra de 32 bits de `DATA_IN` |
| `IN_WRITE` | grava a palavra montada em `DATA_IN` |
| `LOAD` / `START` | escreve `CTRL` = `0x2` (MODE=0, LOAD) ou `0x5` (MODE=1, START) |
| `POLL` | lê `STATUS` do acelerador até `DONE` com `STATE` = parado |
| `OUT_READ` | lê de `DATA_OUT` o elemento do bloco de C |
| `C_READ` | só a partir do segundo bloco de K: lê o valor parcial de C |
| `C_WRITE` | grava o elemento em C (soma com o parcial, se houver) com `WSTRB` só nos bytes dele |
| `NEXT_TILE` | avança m, depois k, depois n |
| `FINISH` / `FAIL` | liga `DONE` (e `ERROR` no `FAIL`) e volta a `IDLE` |

**Blocos da borda.** Quando M, K ou N não são múltiplos de `ARRAY_SIZE`, os elementos que ficam fora da matriz não são lidos: a posição fica em 0 no buffer. Na saída, só os elementos válidos são gravados em C.

**Somas parciais.** O acelerador não acumula entre um START e outro, então o DMA soma os blocos de K em C. A soma dá a volta em `DATA_WIDTH` bits, como a saída do acelerador e o golden (`systolic_array`). A decisão está no [ADR 0002](../../02.Architecture/decisions/0002-acumulacao-de-parciais-no-dma.md).

**Erros.** O DMA para com `DONE` e `ERROR` em 1 quando: alguma dimensão é 0; recebe SLVERR ou DECERR em qualquer acesso; ou o `STATUS` do acelerador mostra `ERROR`.

**Ordem garantida pelo DMA.** Cada acesso espera a resposta antes do próximo. Assim, o último BRESP de `DATA_IN` sempre chega antes do comando (ponto P4 do plano de verificação), e `DATA_OUT` só é lido depois de `DONE` (P3).

## Testbench da E3 (DMA + memória + acelerador, sem CPU)

`05.Verification/unit/dma/dma_subsys_tb.sv`. O testbench faz o papel da CPU com tarefas de escrita e leitura nos registradores do DMA (BFM), carrega A e B na memória por backdoor, dá START e espera a interrupção. Depois compara C com o golden e confere que nada foi escrito fora de C.

Montagem: `dma_top` → `soc_axil_decoder` → `soc_dmem` (memória), `soc_accel_csr` (CTRL/STATUS) e `accel_top` (buffers).

Roda as 9 combinações de `ARRAY_SIZE` × `DATA_WIDTH`, com 11 casos de matriz cada (99 no total): elemento único, bloco único, bordas, K > `ARRAY_SIZE`, C largo, A alto, 4 dimensões aleatórias e valores extremos. Também testa reset, leitura e escrita dos registradores, SLVERR, escrita com `BUSY`, `START` repetido, dimensão zero, DECERR em C e acelerador travado em erro. As regras de handshake do mestre ficam em `dma_sva.sv` (bind).

```bash
bash 05.Verification/common/scripts/run_dma.sh                 # Xcelium (WSL do curso)
SIM=verilator bash 05.Verification/common/scripts/run_dma.sh   # Verilator 5
```

Resultado esperado: `RESUMO: 15372 OK, 0 ERRO` e `SIM PASS`.

Ciclos de START até a interrupção, com `DATA_WIDTH` = 8 e S = `ARRAY_SIZE`:

| S | M = K = N = S | M = N = S, K = 3S | M = 2S+1, K = S, N = 2S+3 |
|---|---|---|---|
| 2 | 90 | 282 | 700 |
| 4 | 276 | 912 | 1636 |
| 8 | 1014 | 3414 | 5506 |

A maior parte do tempo vai no barramento: um elemento por transação e 3 a 4 ciclos por transação. Para melhorar depois: ler a palavra inteira de A e B quando os elementos estão alinhados, e reaproveitar a palavra de `DATA_OUT` lida para os elementos seguintes.

## Pendências

- **Memória, decodificador e CSR do acelerador** (`04.RTL/soc/`) foram feitos para fechar a E3 e são do bloco Sistema. Na E4 o decodificador vira a interconexão com dois mestres e árbitro.
- Formato de C (`DATA_WIDTH` bits) muda a seção 4 da especificação: precisa da aprovação do ADR 0002.
- Síntese no Genus (área e fmax) ainda não rodada.
