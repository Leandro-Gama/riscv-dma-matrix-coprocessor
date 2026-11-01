# CSR

Módulo que o host (RISC-V) usa para configurar e ler os status dos IPs presente no barramento. Acessivel na faxia de endereço: 0x0000_0000 a 0x4000_0000

## CSR do DMA
To be defined

## CSR do acelerador

Os endereços entre 0x1000_0000 e 0x2000_0000 são destinados a configuração do [acelerador Weight-Stationary](../../04.RTL/accel/readme.md). Os registradores têm 32 bits e base `0x1000_0000`.

| Offset | Endereço | Registrador | Acesso |
|---|---|---|---|
| `0x0000` | `0x1000_0000` | CTRL | RW |
| `0x0004` | `0x1000_0004` | STATUS | RO |

### CTRL

| Bits | Campo | Escrita | Leitura |
|---|---|---|---|
| 0 | MODE | `0`: CONFIG (pesos); `1`: EXECUTION (entradas) | Valor armazenado |
| 1 | LOAD | Escrita de 1 solicita carregamento dos pesos | Zero |
| 2 | START | Escrita de 1 solicita processamento | Zero |
| 3 | CLR_ERROR | Escrita de 1 limpa ERROR | Zero |
| 31:4 | Reservado | Ignorada | Zero |

MODE mantém o valor escrito e alimenta `mode_i`. Cada escrita aceita em CTRL com LOAD, START ou CLR_ERROR em 1 gera um pulso de um ciclo no sinal correspondente, uma única vez por transação. Escrita de 0 nesses campos de comando não gera pulso.

### STATUS

STATUS reflete `status_o[31:0]`, produzido pelo acelerador.

| Bits | Campo | Significado |
|---|---|---|
| 1:0 | STATE | `00`: IDLE; `01`: LOADING; `10`: PROCESSING |
| 2 | DONE | Última operação concluída |
| 3 | ERROR | Comando inválido detectado pelo acelerador |
| 31:4 | Reservado | Zero |

## Reset e regras de comando

- Reset estabelece MODE=CONFIG, STATE=IDLE, DONE=0 e ERROR=0.
- LOAD é aceito em IDLE com MODE=CONFIG; START é aceito em IDLE com MODE=EXECUTION. Comandos LOAD/START fora dessas condições ativam ERROR.
- LOAD ou START aceito limpa DONE. A conclusão da carga dos pesos ou do armazenamento de todos os resultados ativa DONE e retorna a IDLE. DONE não impede novos comandos.
- O acelerador mantém ERROR até `clr_error_i` ou reset. Erros de acesso aos buffers são reportados nas respostas AXI4-Lite BRESP/RRESP.
