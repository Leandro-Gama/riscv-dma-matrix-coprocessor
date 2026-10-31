# Acelerador com array sistólico Weight-Stationary

Especificação de um acelerador de multiplicação matricial Weight-Stationary, parametrizável em `N = 2, 4 ou 8` e `DATA_WIDTH = 8, 16 ou 32` bits por elemento. Cada matriz contém `N²` elementos.

## Integração e mapa de memória

O módulo externo de CSR decodifica os endereços de controle, status e dados. A casca do acelerador contém os buffers de entrada e saída, cada um com `N²` elementos; o `systolic_array` recebe os comandos e acessa esses buffers.

Os endereços abaixo são tratados pelo CSR externo, com base em `0x4000_0000`:

| Endereço/base | Registrador/buffer | Acesso | Função |
|---|---|---|---|
| `0x4000_0000` | CTRL | RW | MODE, LOAD, START e CLR_ERROR |
| `0x4000_0004` | STATUS | RO | STATE, DONE e ERROR |
| `0x4000_1000` | DATA_IN | WO | Base do buffer de entrada |
| `0x4000_2000` | DATA_OUT | RO | Base do buffer de saída |

O DMA transfere `N²` elementos, com tamanho de transferência e incremento de endereço de `DATA_WIDTH / 8` bytes por elemento. Cada buffer ocupa `N² × (DATA_WIDTH / 8)` bytes, e a posição acessada é `(endereço − base) / (DATA_WIDTH / 8)`.

Para `N = 8`, cada buffer ocupa 64, 128 ou 256 bytes, conforme `DATA_WIDTH` seja 8, 16 ou 32 bits. A casca seleciona a posição pelo endereço recebido; os registradores CTRL/STATUS e os sinais de dados do barramento têm 32 bits.

### CTRL — offset `0x0000`

| Bits | Campo | Função |
|---|---|---|
| 0 | MODE | `0`: CONFIG (pesos); `1`: EXECUTION (entradas) |
| 1 | LOAD | Escrita de 1 inicia o carregamento dos pesos |
| 2 | START | Escrita de 1 inicia o processamento |
| 3 | CLR_ERROR | Escrita de 1 limpa ERROR |
| 31:4 | Reservado | Leitura retorna zero |

MODE mantém o valor escrito e alimenta `mode_i`. Cada escrita aceita em CTRL com LOAD, START ou CLR_ERROR em 1 gera um pulso de um ciclo no sinal correspondente.

### STATUS — offset `0x0004`

| Bits | Campo | Função |
|---|---|---|
| 1:0 | STATE | `00`: IDLE; `01`: LOADING; `10`: PROCESSING |
| 2 | DONE | Última operação concluída |
| 3 | ERROR | Comando ou acesso inválido detectado pelo acelerador |
| 31:4 | Reservado | Zero |

## Funcionamento

O buffer de entrada é compartilhado pelos fluxos de CONFIG e EXECUTION. Os pesos ficam nos registradores dos elementos de processamento e são reutilizados até um novo carregamento.

### Configuração dos pesos

1. Selecionar MODE=0 e usar o DMA para escrever `N²` elementos a partir da base DATA_IN.
2. Após a conclusão bem-sucedida do DMA, emitir LOAD. No estado LOAD, contadores internos percorrem o buffer e controlam o carregamento dos pesos no array.
3. Quando todos os pesos estiverem carregados, retornar a IDLE e indicar DONE. O host aguarda essa conclusão antes da próxima etapa.

### Processamento

1. Selecionar MODE=1 e usar o DMA para escrever `N²` elementos a partir da base DATA_IN.
2. Após a conclusão bem-sucedida do DMA, emitir START. No estado PROCESSING, o array lê diretamente o buffer de entrada, executa a multiplicação e preenche o buffer de saída.
3. Contadores internos sequenciam as entradas, o processamento e o armazenamento dos resultados. Quando todos os resultados estiverem disponíveis no buffer de saída, retornar a IDLE e indicar DONE.

### Leitura

1. O host aguarda DONE do processamento e programa o DMA para ler `N²` elementos a partir da base DATA_OUT.
2. O DMA incrementa o endereço em `DATA_WIDTH / 8` bytes por elemento, e o host aguarda sua conclusão.

O host coordena as transferências e as operações do array; leituras de DATA_OUT antes de DONE podem retornar resultados incompletos.

### Indicadores e regras

- Reset estabelece IDLE e limpa DONE e ERROR. O acelerador mantém esses indicadores e os apresenta em `status_o`.
- LOAD e START são aceitos somente em IDLE. LOAD em EXECUTION e START em CONFIG geram ERROR.
- LOAD ou START aceito limpa DONE; a conclusão da operação ativa DONE. DONE não impede novos comandos.
- ERROR registra erros detectados pelo acelerador e permanece ativo até `clr_error_i` ou reset. O CSR trata os erros de endereço externamente.

## Interface do acelerador

### Controle do array

| Sinal | Direção | Largura | Descrição |
|---|---|---|---|
| `clk_i` | Entrada | 1 bit | Clock |
| `rst_ni` | Entrada | 1 bit | Reset ativo baixo |
| `mode_i` | Entrada | 1 bit | CTRL.MODE: `0` CONFIG; `1` EXECUTION |
| `start` | Entrada | 1 bit | Pulso de processamento, originado de CTRL.START |
| `load` | Entrada | 1 bit | Pulso de carregamento dos pesos em CONFIG, originado de CTRL.LOAD |
| `clr_error_i` | Entrada | 1 bit | Pulso de limpeza de ERROR, originado de CTRL.CLR_ERROR |
| `status_o` | Saída | 32 bits | Espelha STATUS: STATE em `[1:0]`, DONE em `[2]`, ERROR em `[3]` e zeros em `[31:4]` |

### Acesso aos buffers na casca

| Sinal | Direção | Largura | Descrição |
|---|---|---|---|
| `wdata_i` | Entrada | 32 bits | Dados de escrita do barramento |
| `rdata_o` | Saída | 32 bits | Dados de leitura do barramento |
| `ready_o` | Saída | 1 bit | Transação concluída |
| `error_o` | Saída | 1 bit | Erro na transação |

