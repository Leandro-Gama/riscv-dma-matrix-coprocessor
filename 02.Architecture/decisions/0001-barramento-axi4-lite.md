# 0001 — Barramento AXI4-Lite com uma interconexão única

- **Status:** aceita
- **Data:** 01/11/2026; arbitragem revista em 13/11/2026
- **Blocos afetados:** Sistema, CPU, DMA, Acelerador
- **Aprovações:** Sistema (Leandro Gama), 13/11/2026. CPU, DMA e Acelerador em aberto

## Contexto

O acelerador foi especificado pelo dono como um bloco **no barramento**: registradores CTRL e STATUS e buffers DATA_IN e DATA_OUT a partir de `0x4000_0000`, com o DMA escrevendo os dados nos buffers. Isso define o que o sistema precisa ter:
- o DMA precisa chegar à memória de dados (ler A e B, gravar C) e ao acelerador;
- a CPU precisa chegar à memória de dados e aos registradores do DMA.

Faltava escolher o protocolo e a forma de ligar tudo.

## Alternativas

| Alternativa | Prós | Contras |
|---|---|---|
| **AXI4-Lite com uma interconexão única** (2 mestres, 3 escravos) | protocolo padrão, documentado e conhecido; o mesmo protocolo em todos os blocos; um só caminho do DMA para memória e acelerador | todo acesso leva pelo menos dois ciclos; a CPU precisa saber parar; CPU e DMA disputam o barramento |
| Protocolo próprio valid/ready mais simples | menos sinais por porta | regras de handshake, respostas de erro e escrita por byte teriam de ser escritas e revisadas do zero; AXI4-Lite já define tudo isso |
| Ligação direta DMA ↔ acelerador (proposta inicial do DMA: dados por valid/ready e um sinal de fim) e barramento só para a memória | o DMA não disputa o barramento para falar com o acelerador; atende ao pé da letra os "sinais de requisição, pronto/ocupado e conclusão" | o acelerador já foi especificado pelo dono como bloco no barramento, com buffers endereçados; mudar isso agora custa refazer a interface dele |
| Memória de dados com duas portas (uma só do DMA) + barramento para o resto | o DMA lê a memória sem disputar com a CPU | o DMA precisaria de duas portas mestre, uma para a memória e outra para o acelerador; mais coisa para especificar e verificar agora |

## Critérios e evidência

- **Uma interface comum para todos.** Com AXI4-Lite, CPU, DMA, memória e acelerador seguem a mesma regra de handshake, e a verificação usa um único checador de protocolo.
- **Prioridade para quem move os dados.** Enquanto a transferência corre, a CPU só lê o registrador de status em laço. Atrasar essa leitura não atrasa nada; atrasar o DMA atrasa a conta inteira. Por isso, quando os dois pedem o barramento no mesmo ciclo, quem passa é o DMA. A CPU não fica sem barramento para sempre: o DMA passa boa parte do tempo esperando o acelerador carregar os pesos e calcular, e nesses intervalos a CPU é atendida; além disso a operação termina.
- **Respeitar a interface que o acelerador já definiu.** Como ele está no barramento, uma porta mestre só no DMA atende memória e acelerador.
- **Simplicidade agora, desempenho depois.** Cada transação AXI4-Lite leva de 2 a 3 ciclos, e o DMA move um elemento por transação. A malha passa a maior parte do tempo esperando dados, e é esperado que seja assim nesta primeira versão. Dois cuidados:
  - um árbitro que alternasse os dois mestres poderia dar à CPU até metade das vezes no barramento enquanto ela só lê o status; é o que a prioridade do DMA evita;
  - uma memória com duas portas ou uma ligação direta com o acelerador continuam possíveis depois, por nova decisão, se a análise de desempenho pedir.

## Decisão

- O barramento de dados é **AXI4-Lite**, com endereço e dados de 32 bits.
- Uma **interconexão única** liga:
  - os mestres: porta de dados da CPU e DMA;
  - os escravos: memória de dados, registradores do DMA e acelerador.
- Quando os dois mestres pedem o barramento no mesmo ciclo, a **prioridade é do DMA**. A alternância entre eles continua disponível por parâmetro da interconexão, para render um número de comparação entre as duas formas de arbitrar.
- O barramento é concedido por **transação inteira**: os cinco canais ficam ligados a um mestre até a resposta chegar. Isso é possível porque cada mestre tem no máximo uma transação em voo, e dispensa rotear cada canal em separado e reordenar respostas.
- A **memória de instruções** fica fora do barramento, ligada só à porta de instrução da CPU.
- O **adaptador AXI4-Lite → casca do acelerador** é do Sistema. Ele guarda CTRL, gera os pulsos LOAD, START e CLR_ERROR e traduz os acessos aos buffers. Assim, o acelerador mantém a interface simples que o dono especificou.

## Consequências

- **CPU:** a porta de dados vira mestre AXI4-Lite. Cada load/store espera a resposta, então o core precisa parar até ela chegar. Isso é uma mudança em relação ao core do Lab20.
- **DMA:**
  - uma porta escrava AXI4-Lite para os registradores;
  - uma porta mestre AXI4-Lite para a memória e para o acelerador;
  - a saída de interrupção.
- **Acelerador:** a interface do readme continua. A especificação acrescenta o sufixo `_i` a `start` e `load` e propõe sinais de pedido e de escrita/leitura dos buffers (`data_req_i`, `data_we_i`), que precisam ser confirmados com o dono.
- **Sistema:** interconexão, árbitro, decodificador de endereços, memória de dados com escravo AXI4-Lite e adaptador do acelerador.
- **Verificação:** um checador das regras de handshake AXI4-Lite em todas as portas.
- **Mapa, registradores e sinais:** [08.Docs/e1_especificacao.md](../../08.Docs/e1_especificacao.md).
