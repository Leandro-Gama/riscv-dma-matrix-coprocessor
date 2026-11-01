# Acelerador com array sistólico Weight-Stationary

Acelerador de multiplicação matricial com `N = 2, 4 ou 8` e `DATA_WIDTH = 8, 16 ou 32` bits por elemento. Os pesos permanecem nos elementos de processamento e são reutilizados até um novo carregamento.

## Casca e integração

A casca contém um slave AXI4-Lite, os buffers de entrada e saída e o controle/datapath do array.

Host e DMA acessam os buffers pelo barramento compartilhado, com encaminhamento pela interconexão. O [CSR externo](../../02.Architecture/icd/csr_readme.md) fornece MODE e os pulsos LOAD, START e CLR_ERROR, e recebe `status_o`.


## Buffers endereçáveis

Cada buffer contém `N²` elementos compactados e ocupa `N² × (DATA_WIDTH / 8)` bytes. A casca seleciona as posições pelo endereço recebido.

| Base | Buffer | Acesso externo |
|---|---|---|
| `0x4000_1000` | DATA_IN | Escrita |
| `0x4000_2000` | DATA_OUT | Leitura |

Os acessos AXI são alinhados em 4 bytes. Cada palavra de 32 bits contém os elementos em ordem little-endian: o elemento de menor endereço ocupa os bits menos significativos. Na escrita, `WSTRB[n]` habilita o byte `WDATA[8*n +: 8]`.

| DATA_WIDTH | Elementos por palavra AXI | Bytes por buffer para N=8 |
|---|---|---|
| 8 bits | 4 | 64 |
| 16 bits | 2 | 128 |
| 32 bits | 1 | 256 |

Com palavras completas, o DMA transfere `N² × DATA_WIDTH / 32` palavras por matriz, incrementando o endereço em 4 bytes. A posição de um elemento é `(endereço_do_elemento − base) / (DATA_WIDTH / 8)`.

## Interface AXI4-Lite

O slave usa dados e endereços de 32 bits. `clk_i` e `rst_ni` correspondem a ACLK e ARESETn; AXI, CSR e array compartilham o mesmo clock e reset ativo baixo. As direções abaixo são relativas ao acelerador; sinais sem largura indicada têm 1 bit.

| Canal | Entradas | Saídas |
|---|---|---|
| AW | `s_axi_awaddr[31:0]`, `s_axi_awprot[2:0]`, `s_axi_awvalid` | `s_axi_awready` |
| W | `s_axi_wdata[31:0]`, `s_axi_wstrb[3:0]`, `s_axi_wvalid` | `s_axi_wready` |
| B | `s_axi_bready` | `s_axi_bresp[1:0]`, `s_axi_bvalid` |
| AR | `s_axi_araddr[31:0]`, `s_axi_arprot[2:0]`, `s_axi_arvalid` | `s_axi_arready` |
| R | `s_axi_rready` | `s_axi_rdata[31:0]`, `s_axi_rresp[1:0]`, `s_axi_rvalid` |

- Cada canal transfere quando VALID e READY estão ativos na borda de subida. AW e W são capturados independentemente; a escrita é executada uma única vez, após receber ambos.
- A casca admite uma escrita e uma leitura pendentes. BRESP/BVALID e RDATA/RRESP/RVALID permanecem estáveis enquanto aguardam a aceitação das respostas.
- A resposta de escrita é produzida após efetivar ou rejeitar o acesso ao buffer. A resposta AXI confirma o acesso; DONE informa a conclusão da operação do array.
- Acessos válidos retornam `OKAY` (`00`). Endereços locais inválidos, desalinhamentos, leitura de DATA_IN e escrita em DATA_OUT retornam `SLVERR` (`10`).
- Escritas em DATA_IN durante LOADING ou PROCESSING retornam `SLVERR` e preservam o buffer. Erros AXI são informados por BRESP/RRESP.

Referência: [AMBA AXI and ACE Protocol Specification — AXI4-Lite](https://documentation-service.arm.com/static/602a9df190ee6824a1e02b98).

## Operação

O buffer de entrada é compartilhado pelos fluxos de configuração e execução. O host coordena as transferências e os comandos conforme o [contrato dos CSR](../../02.Architecture/icd/csr_readme.md).

### Carregamento dos pesos

1. Selecionar CONFIG e usar o DMA para preencher DATA_IN.
2. Aguardar a conclusão bem-sucedida do DMA e emitir LOAD.
3. Em LOADING, contadores internos percorrem o buffer e controlam a carga dos pesos. Após carregar todos os pesos, retornar a IDLE e indicar DONE.

### Processamento e leitura

1. Após concluir a carga dos pesos, selecionar EXECUTION e usar o DMA para preencher DATA_IN com as entradas.
2. Aguardar a conclusão bem-sucedida do DMA e emitir START. O array lê diretamente o buffer de entrada e preenche DATA_OUT.
3. Em PROCESSING, contadores internos sequenciam as entradas, o processamento e o armazenamento dos resultados. Quando todos os resultados estiverem disponíveis, retornar a IDLE e indicar DONE.
4. O host aguarda DONE, programa o DMA para ler DATA_OUT e aguarda a conclusão da transferência.

Leituras de DATA_OUT antes de DONE podem retornar resultados incompletos. A latência de LOAD e PROCESSING depende do sequenciamento interno do array.
