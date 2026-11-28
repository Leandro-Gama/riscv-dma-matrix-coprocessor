# 0003 — Acelerador como um escravo só, com um decodificador local entre CTRL/STATUS e os buffers

- **Status:** proposta
- **Data:** 28/11/2026
- **Blocos afetados:** Sistema, Acelerador, DMA
- **Aprovações:** —

## Contexto

A especificação da E1 previa que o adaptador do Sistema (`accel_adapter`) conversasse com a casca do acelerador, que é a parte dele em volta da malha, por sinais simples de pedido: pedido, escrita ou leitura, endereço, dado, pronto e erro. Esses sinais estavam marcados como proposta, a confirmar com o dono do acelerador.

O acelerador entregue na E2 (`accel_top`) resolveu de outra forma. Os buffers `DATA_IN` e `DATA_OUT` ficam atrás de uma porta escrava AXI4-Lite do próprio acelerador, que decodifica os endereços `0x4000_1000` e `0x4000_2000`. Só os comandos (modo, carregar, calcular, limpar erro) e o status são fios. Com isso, o adaptador e o acelerador entregue não se encaixam, e sem resolver essa ligação não existe top-level.

O testbench da E3 já ligou os dois de um jeito que funciona: um decodificador de um mestre para vários escravos (`soc_axil_decoder`) separa os acessos em três destinos, e dois deles são o bloco de `CTRL` e `STATUS` e o próprio acelerador. Essa montagem passou em simulação com o DMA e o acelerador reais, mas fica fora da interconexão do Sistema, que é quem arbitra entre CPU e DMA.

## Alternativas

Em todas, "ciclos por acesso" conta do ciclo em que o endereço é aceito até o ciclo da resposta, na porta do acelerador vista pela interconexão.

| Alternativa | Prós | Contras |
|---|---|---|
| **Decodificador local atrás da porta do acelerador.** A interconexão continua vendo um escravo só. Logo depois dela, o `soc_axil_decoder` manda `0x4000_0000`–`0x4000_0FFF` para o adaptador (`CTRL` e `STATUS`) e o resto da região para a porta AXI4-Lite do `accel_top` | nenhum ciclo a mais: o decodificador só repassa os canais; a escrita por byte continua valendo; não muda a interconexão, o package comum (`soc_pkg`), o mapa, o adaptador nem o acelerador; a mesma fiação já simulou com o DMA e o acelerador reais | segundo nível de decodificação em série no caminho até o acelerador, com efeito no timing ainda não medido; o decodificador veio do trabalho do DMA e passa a ser mantido pelo Sistema; a metade do adaptador que trata buffers fica sem uso |
| Adaptador como ponte: ele fica com `CTRL` e `STATUS`, e os acessos a buffer saem dele para um mestre AXI4-Lite (`axil_master_port`) ligado à porta do `accel_top` | não muda a interconexão nem o mapa; todos os blocos são do Sistema e têm testbench; a fronteira com o acelerador fica registrada, o que isola o timing | 3 ciclos a mais em cada acesso a buffer (escrita de 3 para 6, leitura de 2 para 5); a escrita por byte se perde, porque o adaptador não repassa os bytes habilitados; cerca de 73 flip-flops a mais |
| Quarto escravo na interconexão: uma janela para `CTRL` e `STATUS`, outra para os buffers | nenhum ciclo a mais; escrita por byte preservada | muda o `soc_pkg`, o decodificador de endereços da interconexão e o testbench dela, já verificados; a metade de buffers do adaptador fica sem uso |
| Pedir ao dono do acelerador os sinais de pedido propostos na E1 | o adaptador fica como a especificação descreveu | muda RTL e testbench já entregues e verificados na E2; depende de outro bloco, sem prazo |

## Critérios e evidência

- **Ciclos são o que o relatório final compara.** O número de ciclos de uma multiplicação entra na comparação das três malhas. A ponte pelo adaptador custa 3 ciclos em cada acesso a buffer, pela leitura do RTL (falta medir em simulação). Para a mesma matriz 8 × 8 × 8 com elementos de 8 bits:

  | Malha | Acessos a buffer | Ciclos a mais com a ponte |
  |---|---|---|
  | 2 × 2 | 336 | 1008 |
  | 4 × 4 | 176 | 528 |
  | 8 × 8 | 96 (32 escritas e 64 leituras) | 288 |

  O acréscimo é maior nas malhas pequenas, então ele também achata a diferença entre as malhas, que é justamente o que o relatório quer mostrar. Com elementos de 32 bits o bloco 8 × 8 tem 192 acessos e o acréscimo dobra. O decodificador local e o quarto escravo não custam ciclo nenhum.
- **A base de comparação precisa ser dita.** Os 1014 ciclos que o README do DMA mede para um bloco 8 × 8 × 8 são da montagem do testbench da E3, com a memória de apoio daquele testbench. A memória do Sistema responde em mais ciclos, então o total no top-level será maior que 1014 por um motivo que não tem relação com esta decisão. O primeiro teste do subsistema mede os dois efeitos em separado.
- **Não mexer no que já foi verificado.** O decodificador local e a ponte não alteram nenhum bloco verificado. O quarto escravo altera três arquivos do Sistema e o testbench da interconexão.
- **Evidência de simulação.** A fiação do decodificador local é a do testbench da E3: decodificador, bloco de `CTRL` e `STATUS` e `accel_top`, com o DMA real, em 99 multiplicações por seed iguais ao golden model. A diferença é que aqui o bloco de `CTRL` e `STATUS` passa a ser o adaptador do Sistema, que tem testbench próprio. A ponte ainda não simulou com o acelerador real.
- **O que o DMA entregue faz hoje.** Pela leitura do RTL, ele escreve `DATA_IN` em palavras inteiras alinhadas e lê `DATA_OUT` em endereço de palavra, escolhendo o byte por conta própria. Qualquer uma das ligações serve a ele sem mudança.
- **Um risco de temporização foi conferido.** O DMA lê o `STATUS` do acelerador logo depois da resposta da escrita em `CTRL`. Se o `DONE` do comando anterior ainda estivesse em 1 nessa leitura, o DMA leria o resultado antes da conta. Pela leitura do RTL, o adaptador gera o pulso no ciclo da resposta, o acelerador baixa `DONE` no ciclo seguinte, e a leitura do DMA amostra 2 ciclos depois da resposta. Um mestre que emende a leitura na resposta tem 1 ciclo de folga. A verificação cobre isso com duas asserções.

## Decisão

- O acelerador continua sendo **um escravo só** para a interconexão, de 64 KiB em `0x4000_0000`. O mapa de memória, a interconexão e o `soc_pkg` não mudam.
- Depois da porta do acelerador na interconexão entra um **decodificador local** (`soc_axil_decoder`), com dois destinos:
  - `0x4000_0000` a `0x4000_0FFF`: o **adaptador do Sistema**, que guarda `CTRL`, gera os pulsos de carregar, calcular e limpar erro e espelha `STATUS`;
  - `0x4000_1000` a `0x4000_FFFF`: a **porta AXI4-Lite do `accel_top`**, que já responde erro de escravo para o que estiver fora dos buffers.
- Toda a região continua respondendo erro de escravo para acesso inválido, como a especificação diz.
- Os sinais de pedido que a E1 propôs para a casca do acelerador **deixam de existir**: nem o acelerador nem o Sistema precisam deles.
- A **ponte pelo adaptador** fica como reserva: entra se a síntese mostrar que a decodificação em série limita a frequência.

## Consequências

- **Acelerador:** nada muda no RTL. A interface entregue na E2 passa a ser a do contrato.
- **DMA:**
  - nada muda no RTL;
  - o decodificador que veio com o testbench da E3 passa a ser bloco do Sistema, como o próprio README do DMA já previa;
  - a memória e o bloco de `CTRL` e `STATUS` de apoio daquele testbench continuam valendo para ele até o testbench do DMA usar a interconexão do Sistema;
  - a tabela de ciclos do README do DMA vale para a montagem da E3; os ciclos do sistema saem do teste de subsistema.
- **Sistema**, até 02/12:
  - montar o subsistema com interconexão, memória, DMA, decodificador local, adaptador e acelerador;
  - no adaptador, o lado de pedido de buffer fica sem uso e é ligado de modo que um acesso perdido receba erro em vez de travar.
- **Contrato**, quando esta decisão for aceita:
  - a tabela de sinais entre adaptador e casca, na especificação, dá lugar às portas reais do `accel_top`;
  - saem da lista de pendências com o acelerador os sinais de pedido, a largura do buffer de saída e a escrita de vários elementos de uma vez;
  - a decisão 0001 dizia que o adaptador traduz os acessos aos buffers; esse trecho passa a apontar para cá;
  - a base do acelerador no arquivo antigo de registradores do contrato é corrigida para `0x4000_0000`;
  - as bases dos buffers passam a ter uma fonte só, o `soc_pkg`, de onde o topo tira os parâmetros do acelerador e do DMA.
- **Verificação:**
  - o checador AXI4-Lite cobre a porta do adaptador; a porta do acelerador e o decodificador local ganham as mesmas regras por `bind`;
  - duas asserções novas: um ciclo depois de um comando aceito, `STATUS` não mostra `DONE`; nenhuma leitura de `DATA_OUT` com o acelerador carregando ou calculando;
  - o primeiro teste de subsistema mede os ciclos por acesso a buffer e os ciclos da multiplicação 8 × 8 × 8.
- **Síntese**, até 06/12: medir o caminho mais longo do subsistema com o decodificador local, nas três malhas.

**Ainda falta definir:**
- se a decodificação em série custa frequência, o que só a síntese responde;
- a largura de C, que depende da decisão 0002, ainda em proposta.
