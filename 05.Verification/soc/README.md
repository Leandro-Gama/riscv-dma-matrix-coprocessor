# Ambiente UVM do sistema

Este é o ambiente de verificação do sistema inteiro, que calcula C = A × B. Ele roda em UVM 1.2 no Xcelium, sem precisar de nenhum outro programa. Uma pessoa de fora do grupo consegue rodar a regressão seguindo só este arquivo.

## O DUT

O DUT (o circuito sob teste) é o `soc_top`. Dentro dele:

- a CPU RISC-V de 32 bits roda um firmware que escreve nos registradores do DMA os endereços de A, B e C e as dimensões M, K e N, e escreve START;
- o DMA lê A e B da memória de dados, entrega os blocos ao acelerador e escreve C de volta;
- o acelerador é uma malha sistólica de ARRAY_SIZE × ARRAY_SIZE elementos, com ARRAY_SIZE de 2, 4 ou 8;
- quando a matriz é maior que a malha, o DMA divide a conta em blocos (tiling) e soma os resultados parciais em C;
- no fim, o DMA liga DONE e, se a interrupção estiver habilitada, o pino `irq_o`.

Por fora, o `soc_top` só tem clock, reset e `irq_o`. Por isso o ambiente põe A, B e a descrição da operação direto na memória de dados (por backdoor, sem passar pelo barramento) e lê C da mesma forma. Quem programa o DMA é sempre o firmware, pela CPU: o ambiente não escreve em registrador nenhum e não usa `force`.

Enquanto o core da CPU não é entregue, quem faz o papel dela é um modelo comportamental RV32I com as mesmas portas do contrato de interfaces (`05.Verification/models/cpu_model.sv`). Quando o core chegar, ele entra no lugar do modelo trocando uma linha da filelist `sim/soc.f`, e os testes continuam os mesmos.

O mesmo ambiente roda também sem CPU (harness `subsys`). Nesse caso um driver de barramento faz, pelo barramento, o mesmo que o firmware faz. Serve para depurar o DMA e o acelerador sem depender da CPU.

## Como rodar

Tudo roda na WSL `cademics-cepedi`, a partir da raiz do repositório, com a licença Cadence ativa (`cadence-check` mostra se ela está acessível).

| Para | Comando |
|---|---|
| Ver todos os alvos | `make help` |
| Checar sem licença (testes Python, lint, firmware, elaborações) | `make check` |
| Compilar do zero | `make clean && make uvm-elab TB=soc` |
| Rodar um teste | `make uvm TEST=mm_smoke_test` |
| Escolher a malha, a largura e a seed | `make uvm TEST=mm_rand_test ARRAY_SIZE=8 DATA_WIDTH=16 SEED=1234` |
| Ligar a cobertura | `make uvm TEST=mm_rand_test COV=1` |
| Gravar e abrir as ondas | `make uvm TEST=mm_smoke_test WAVES=1` e depois `make uvm-gui` |
| Rodar sem a CPU | `make uvm TB=subsys TEST=mm_smoke_test` |
| Injetar uma falha | `make uvm TEST=mm_fault_test FAULT=fw_dim_k EXPECT=fail` |
| Rodar com um RTL mutante | `make uvm TEST=mm_smoke_test BUG=mem_strobe EXPECT=fail` |
| Rodar a regressão | `make regress` (tabela em `build/regress/regress.md`) |
| Somar a cobertura da regressão | `make cov-merge` (tabela em `build/regress/coverage.md`) |

O padrão é `TB=soc`, `ARRAY_SIZE=4`, `DATA_WIDTH=8` e `SEED=1`. Cada combinação de harness, malha e largura compila em `build/uvm/<harness>_s<malha>_w<largura>/`, e o log do teste fica lá com o nome `<teste>_s<seed>.log`.

**Como ler o resultado.** A última linha do log é `TEST PASS` ou `TEST FAIL`, com a contagem de erros e o número de operações comparadas. Um teste só passa se não houve erro, se chegou ao fim e se comparou pelo menos uma operação. O veredito que vale é o do `make uvm`. Ele lê essa linha e também reprova quando o simulador acusou erro ou quando uma asserção do checador de protocolo falhou, o que não aparece na linha.

Com `EXPECT=fail`, o comando passa só se o teste falhou pela própria checagem, isto é, chegou ao fim sem erro fatal. Assim, um nome de teste errado, o tempo máximo global ou uma queda do simulador não contam como a falha que se queria provocar. É assim que se prova que uma falha injetada é detectada.

**Opções do teste** (pela linha de comando, `EXTRA=+OPCAO=valor` ou pelas variáveis do make):

| Opção | Efeito |
|---|---|
| `NUM_OPS=<n>` | número de operações dos testes aleatórios |
| `+MAX_DIM=<n>` | maior dimensão de uma operação aleatória (padrão 2 × ARRAY_SIZE + 3) |
| `+OP_TIMEOUT=<ciclos>` | tempo máximo de uma operação antes de o driver desistir (padrão 200 000) |
| `+C_WIDTH=<bits>` | largura de cada elemento de C (padrão DATA_WIDTH): o modelo de referência, o scoreboard, o monitor e o driver usam esse tamanho para endereçar e conferir C |
| `FAULT=fw_dim_k` | o firmware programa K − 1: C mantém o formato, mas os valores mudam |
| `FAULT=c_flip` | um bit de C é invertido na memória depois do fim da operação |
| `FAULT=hang` | o firmware nunca avisa o fim: a operação estoura o tempo |
| `BUG=<mutante>` | compila uma cópia modificada de um arquivo de RTL (lista abaixo) |
| `+CPU_TRACE=1` | o modelo de CPU imprime cada instrução executada |
| `+VECTORS=<arquivo>` | outro arquivo de vetores do golden model (padrão: o da malha e da largura, gerado pelo `make uvm`) |
| `+MM_FW=<arquivo>` | outra imagem de firmware (o `make uvm` já passa a de `firmware/mm_fw.hex`) |

## Como o ambiente funciona

**Uma transação é uma multiplicação inteira.** A transação (`mm_item`) leva as dimensões, os endereços, A, B e se a interrupção fica habilitada. A resposta é o que o monitor encontra na memória no fim: C, o status do DMA, os ciclos e as escritas fora de lugar. O protocolo do barramento fica num agente separado, só de observação.

**O firmware é genérico.** Ele não sabe de antemão qual conta vai fazer. No começo da memória de dados existe um bloco de parâmetros, uma área de 10 palavras que o ambiente e o firmware usam para conversar:

| Palavra | Campo | Quem escreve |
|---|---|---|
| 0 | `CMD`: 1 quando há uma operação esperando | ambiente; o firmware zera |
| 1 a 3 | endereços de A, B e C | ambiente |
| 4 a 6 | M, K e N | ambiente |
| 7 | `FLAGS`: bit 0 habilita a interrupção; os bits 8 e 9 injetam falhas | ambiente |
| 8 | `STATUS` do DMA no fim | firmware |
| 9 | `DONE_COUNT`: operações concluídas | firmware |

O firmware espera `CMD`, lê o bloco, programa o DMA, escreve START e lê o STATUS em laço até DONE. No fim grava o STATUS, zera `CMD` e só então soma 1 em `DONE_COUNT`. O ambiente escreve `CMD` por último e espera `DONE_COUNT` mudar. Assim várias operações rodam numa mesma simulação sem remontar o firmware.

**O monitor só olha o DUT.** Ele vê a operação começar quando `CMD` liga e terminar quando `DONE_COUNT` muda, lendo da memória do DUT. Nunca pega nada do driver nem da sequence. No início ele guarda uma cópia de toda a memória de dados. No fim, qualquer byte alterado fora de C conta como escrita fora de lugar. A exceção são as três palavras em que o firmware responde: `CMD`, `STATUS` e `DONE_COUNT`. O monitor também confere que o firmware terminou como combinado, com `CMD` zerado e `DONE_COUNT` com exatamente uma operação a mais.

**A checagem tem quatro camadas:**
1. O modelo de referência recebe a operação observada e calcula o C esperado, com sinal e com a volta (wrap) para a largura de C. Também prevê o STATUS: erro quando uma dimensão é 0 ou quando A, B ou C saem da memória.
2. O scoreboard compara STATUS, cada elemento de C e as escritas fora de lugar. Cada elemento errado gera um erro com operação, linha, coluna, valor esperado e valor obtido. No fim do teste, ele acusa operações iniciadas e nunca comparadas.
3. O verificador de autonomia olha a porta de dados da CPU e a porta do DMA. Durante uma operação, a CPU não pode ler nem escrever A, B, C ou o acelerador, e o que ela escreveu nos registradores do DMA tem de bater com o bloco de parâmetros.
4. As asserções de sistema (`sva/soc_sva.sv`) conferem regras que nenhum bloco checa sozinho. Um comando só chega ao acelerador parado. O DONE antigo some no ciclo seguinte a um comando. O resultado só é lido com o acelerador parado. A interrupção só sobe com o DMA quieto. A CPU nunca acessa o acelerador. O checador de protocolo AXI4-Lite do Sistema vale em todas as portas do subsistema: os dois mestres (CPU e DMA, onde também confere uma transação por vez), a memória de dados, os registradores do DMA, a porta do acelerador, o adaptador, o lado dos buffers no decodificador local e o escravo de erro da interconexão.

Nos testes de vetores, o modelo de referência primeiro confere a própria conta contra os arquivos gerados pelo golden model em Python (`03.Reference/tools/generate_dma_vectors.py`). Só depois os mesmos casos passam pelo DUT.

**Cobertura funcional** (ligada com `COV=1`). A cobertura amostra só o que o monitor publicou. O log mostra o percentual de cada grupo, o total e a lista das combinações não atingidas.

| Grupo | O que mede |
|---|---|
| `cg_tiling` | cada dimensão contra a malha (menor, igual, múltiplo, maior com sobra) e o cruzamento M × K × N, com 64 combinações: é onde o DMA pode errar (bordas, preenchimento com zero, soma das parciais) |
| `cg_data` | A e B com o mínimo, o máximo, ou só zeros; se algum elemento de C precisou dar a volta; cruzamento da volta com a classe de K |
| `cg_ctrl` | interrupção ligada ou desligada; operação logo depois do reset ou emendada; endereços padrão ou realocados; fim certo, erro por dimensão zero ou erro por endereço; cruzamento interrupção × emendada |
| `cg_bus` | caminhos do barramento (CPU no bloco de parâmetros e nos registradores; DMA na memória, no controle, nos buffers) e respostas, à parte do total |

Como não há IMC na máquina de simulação, cada operação também gera uma linha `MM_COV` com os bins atingidos. O `make cov-merge` soma essas linhas de todas as execuções que passaram, por malha. Antes de somar, ele refaz a conta de cada log e confere que ela bate com o percentual que o simulador imprimiu.

## Os testes

| Teste | O que exercita | Resultado esperado |
|---|---|---|
| `mm_smoke_test` | uma operação do tamanho da malha, com valores conhecidos | PASS |
| `mm_vectors_test` | os casos do golden model em Python: um elemento, um bloco, bordas, soma em K, C larga, A alta, aleatórios, valores extremos | PASS |
| `mm_tiling_test` | as 64 combinações das classes de M, K e N | PASS |
| `mm_limits_test` | mínimo, máximo, zero, menos um, identidade, valores pequenos | PASS |
| `mm_b2b_test` | operações emendadas sem reset, com tamanhos, endereços e interrupção diferentes | PASS |
| `mm_irq_poll_test` | fim com interrupção habilitada e fim só por leitura do STATUS | PASS |
| `mm_error_test` | dimensão zero, C depois do fim da memória, C e A em endereço sem dono; cada uma seguida de uma operação que tem de funcionar | PASS |
| `mm_reset_midop_test` | reset durante a programação e no meio da conta; o sistema volta limpo | PASS |
| `mm_rand_test` | `NUM_OPS` operações aleatórias (20 por padrão), um terço com endereços realocados | PASS |
| `mm_latency_test` | os tamanhos da tabela de ciclos do DMA, mais 8 × 8 × 8; o log traz a latência de cada um | PASS |
| `mm_fault_test` | operações aleatórias com a falha de `FAULT=` | FAIL |
| `mm_timeout_test` | o firmware nunca avisa o fim; o driver desiste, acusa e reseta | FAIL, sem travar |

**Mutantes de RTL** (`BUG=`). Cada um é uma cópia de um arquivo de RTL com uma única mudança, gerada em `build/` por `03.Reference/tools/make_mutant.py`. O RTL original não é tocado.

| Mutante | O que muda | Quem pega |
|---|---|---|
| `accel_mac_sign` | cada elemento da malha subtrai o produto em vez de somar | scoreboard |
| `mem_strobe` | a memória ignora os bytes habilitados e escreve a palavra inteira | scoreboard |
| `adapter_level` | o adaptador segura os bits de comando em vez de dar um pulso | asserções de sistema |
| `dma_row_step` | o DMA anda uma palavra a mais no fim de cada linha de um bloco | scoreboard |
| `dma_k_sum` | o DMA troca a soma parcial de C em vez de somar (precisa de K maior que a malha) | scoreboard, no `mm_limits_test` |

A regressão (`sim/tests.list`) roda cada teste nas três malhas, com as seeds da lista. Também roda smoke, vetores e aleatório com 16 e 32 bits na malha 4, as três falhas e os cinco mutantes.

## Os arquivos

| Arquivo | Função |
|---|---|
| `agents/mm_agent/sys_if.sv` | pinos do sistema (clock, reset, interrupção) e backdoor das memórias; é o único lugar que conhece os caminhos dentro do DUT |
| `agents/mm_agent/mm_item.svh` | a transação: uma multiplicação, com restrições de tamanho, endereço e dados |
| `agents/mm_agent/mm_agent_cfg.svh` | configuração do agente: interfaces, malha, largura, limites, falha injetada |
| `agents/mm_agent/mm_sequencer.svh` | sequencer, com a configuração para as sequences |
| `agents/mm_agent/mm_driver_base.svh` | o que os dois drivers fazem: reset, carga da memória, espera do fim com tempo máximo |
| `agents/mm_agent/mm_driver_fw.svh` | driver do topo: carrega o firmware e põe cada operação na memória |
| `agents/mm_agent/mm_driver_bfm.svh` | driver sem CPU: faz pelo barramento o que o firmware faz |
| `agents/mm_agent/mm_monitor.svh` | monitor passivo: início, fim, latência e escritas fora de lugar |
| `agents/mm_agent/mm_agent.svh` | o agente |
| `agents/mm_agent/mm_vector_file.svh` | leitura dos arquivos do golden model |
| `agents/mm_agent/mm_seq_lib.svh` | as sequences |
| `agents/mm_agent/mm_agent_pkg.sv` | pacote do agente, com o bloco de parâmetros |
| `env/mm_ref_model.svh` | modelo de referência por TLM e conferência com o golden model |
| `env/mm_scoreboard.svh` | scoreboard |
| `env/mm_coverage.svh` | cobertura das operações |
| `env/mm_autonomy_checker.svh` | verificador de autonomia do DMA |
| `env/mm_bus_coverage.svh` | cobertura do barramento |
| `env/mm_env.svh`, `env/mm_env_cfg.svh`, `env/mm_env_pkg.sv` | o ambiente, a configuração dele, o pacote e o veredito |
| `tests/mm_base_test.svh` | teste base: configuração, troca do driver pela factory, topologia, tempo máximo |
| `tests/mm_tests.svh`, `tests/mm_test_pkg.sv` | o catálogo de testes e o pacote |
| `top/tb_soc.sv` | harness do topo: clock, DUT, interfaces, `run_test()` e veredito |
| `sva/soc_sva.sv`, `sva/soc_sva_bind.sv` | asserções de sistema, ligadas ao subsistema por `bind` |
| `firmware/mm_fw.S`, `firmware/mm_fw.hex` | firmware de teste e imagem; `make fw` remonta e `make fw-check` confere que estão em dia |
| `sim/soc.f` | filelist do topo |
| `sim/tests.list` | lista da regressão |
| `sim/waves.tcl`, `sim/sv_view.tcl` | gravação das ondas e janela do SimVision |

Fora desta pasta:

| Arquivo | Função |
|---|---|
| `04.RTL/soc/soc_top.sv`, `04.RTL/soc/soc_subsys.sv` | o topo do sistema e o subsistema sem CPU |
| `05.Verification/models/cpu_model.sv` | modelo comportamental da CPU, conferido contra o modelo de referência RV32I em Python (`make sim-unit UNIT_TOP=tb_cpu_model`) |
| `05.Verification/subsys/tb_subsys.sv`, `subsys.f` | harness e filelist sem CPU |
| `05.Verification/common/vip/axil_agent/` | interfaces do barramento (mestre ativo e observação) e agente passivo AXI4-Lite |
| `05.Verification/common/scripts/test_verdict.sh`, `regress.sh` | veredito de um teste e regressão |
| `03.Reference/tools/rv32i_asm.py` | montador RV32I em Python, só com a biblioteca padrão; os testes dele rodam o firmware no modelo de referência |
| `03.Reference/tools/cov_merge.py`, `make_mutant.py` | soma da cobertura e geração dos mutantes |

## Demonstração

O roteiro segue os seis passos pedidos, na malha 4:

1. **Compilação limpa:** `make clean && make uvm-elab TB=soc`.
2. **Teste dirigido:** `make uvm TEST=mm_smoke_test`. O log mostra a topologia impressa pelo UVM, as mensagens do scoreboard e o veredito.
3. **Teste aleatório com a seed do professor:** `make uvm TEST=mm_rand_test SEED=<seed>`.
4. **Cobertura:** `make uvm TEST=mm_tiling_test COV=1`, e depois o `make cov-merge` da regressão. Os bins descobertos aparecem listados.
5. **Uma operação no SimVision:** `make uvm TEST=mm_smoke_test WAVES=1` e `make uvm-gui`. A janela mostra:
   - a CPU escrevendo os registradores do DMA e o START;
   - o DMA lendo A e B e escrevendo nos buffers;
   - os comandos de carga e de cálculo do acelerador;
   - a escrita de C;
   - a subida de `irq`.
6. **O ambiente achando um erro:** `make uvm TEST=mm_fault_test FAULT=fw_dim_k EXPECT=fail`. O scoreboard aponta cada elemento divergente e o teste termina em `TEST FAIL`.

## Limitações conhecidas

- **CPU:** a CPU ainda é o modelo comportamental. O firmware usa só oito instruções (`lui`, `addi`, `andi`, `lw`, `sw`, `beq`, `bne`, `jal`) com acesso de palavra, para que o core real o rode sem mudança.
- **Largura de C:** o ambiente segue o RTL, com C da largura dos elementos e volta, como a decisão 0002 propõe. A especificação ainda diz que C tem 32 bits; isso se resolve quando a decisão 0002 for aceita. Se ela mudar a largura, o ambiente acompanha com `+C_WIDTH`, mas o DMA também precisa mudar.
- **Ligação do acelerador:** a ligação ao barramento segue a proposta da decisão 0003, com o decodificador local atrás da porta do acelerador.
- **Endereços:** o ambiente só gera endereços de A, B e C múltiplos do tamanho do elemento.
- **Cobertura de código:** não há medida, porque a máquina de simulação não tem IMC.
