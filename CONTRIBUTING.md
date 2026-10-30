# Convenções do time

Valem para todo o repositório. Itens marcados **(a confirmar no E1)** são propostas que serão fechadas por ADR durante a entrega 1.

## Princípios

1. **Cada bloco tem dono.** Não edite diretórios de outro bloco. Proponha a mudança por PR/comentário para o dono.
2. **O ICD é o contrato.** Portas, protocolos, mapa de memória e de registradores vivem em [02.Architecture/icd/](02.Architecture/icd/). Mudança de interface exige um ADR em [02.Architecture/decisions/](02.Architecture/decisions/) aprovado pelos donos afetados e pelo integrador.
3. **Simples primeiro.** Só entra complexidade que resolve um requisito do enunciado ou um problema medido.
4. **Evidência reproduzível.** Todo resultado relatado vem com o comando, a seed e o log.

## RTL (SystemVerilog sintetizável)

- Use `logic`, `always_ff` (só atribuição não bloqueante `<=`) e `always_comb` (só `=`, com valor default no início do bloco, para não gerar latch).
- Estados de FSM com `typedef enum logic [N-1:0]`. Use `unique case` quando os casos forem mutuamente exclusivos.
- Parâmetros e tipos compartilhados ficam em `package`. As portas dos módulos são planas: `interface`/`modport` só no testbench.
- Um módulo por arquivo, e o nome do arquivo é o nome do módulo.
- **Separação de responsabilidades:**
  - todo bloco que tem FSM separa controle e datapath em módulos: `<bloco>_ctrl` (FSM) e `<bloco>_dp` (registradores, muxes, aritmética). Blocos puramente de datapath (ex.: um MAC) não precisam do par;
  - toda FSM tem três blocos: registrador de estado, lógica de próximo estado e lógica de saída;
  - módulos pequenos e de responsabilidade única; o que puder ser encapsulado vira submódulo.
- Parâmetros em `MAIÚSCULAS`. Larguras derivadas com `$clog2`, sem número mágico.
- Nomes de sinais em `snake_case`. Sufixos: `_q`/`_d` para saída e próximo valor de flop, `_n` para ativo-baixo.
- Nomes de módulo com prefixo do bloco, para evitar colisão na compilação integrada **(a confirmar no E1)**.
- Clock único e convenção de reset **(a confirmar no E1)**.
- Nada de `initial` nem `$readmemh` no RTL sintetizável. A carga de memórias é feita pelo testbench.

## Comentários

- Poucos, e só onde o código não se explica: o **porquê** de uma decisão, nunca o que a linha faz.
- Em inglês.
- Sem cabeçalho obrigatório de arquivo e sem linhas divisórias (`// ----`, `// ====`).
- Comentário com mais de duas linhas usa `/* */`.

## Verificação

- **UVM:**
  - uma `package` por ambiente;
  - componentes criados pela factory (`type_id::create`);
  - interfaces virtuais via `uvm_config_db`, sem ponte estática;
  - IDs de mensagem curtos em maiúsculas (`DRV`, `MON`, `SCB`);
  - resumos com `UVM_NONE`;
  - `$fatal(1, "...")`, nunca `$fatal("...")`.
- **Critério de aprovação:** `UVM_ERROR : 0`, `UVM_FATAL : 0` e scoreboard sem divergências nem itens sobrando.
- **Testbench unitário simples** (quando UVM for exagero): SystemVerilog com tasks, cada checagem imprime `OK` ou `ERRO`, e a última linha é `RESUMO: <n> OK, <m> ERRO`.
- Assertions (SVA) em arquivos de `bind`, separados do RTL.
- Seeds sempre explícitas (`SEED=`). Evidências com TAG `<teste>_s<seed>` ou `NN_<descricao>_s<seed>`.

## Python (golden model e ferramentas)

- O núcleo em `03.Reference/golden/` usa só a biblioteca padrão e roda no Python 3.9 da WSL (sem numpy).
- Use type hints (`from __future__ import annotations`), funções pequenas e puras, sem estado global.
- Testes com `unittest` em `03.Reference/tests/` (o `pytest` também os executa). Comparações com numpy só em testes opcionais, que são pulados quando numpy não está disponível.
- CLIs com `argparse`. Toda aleatoriedade recebe seed.

## Firmware (C / assembly RISC-V)

- Freestanding, sem biblioteca padrão.
- Acesso a registradores mapeados em memória por ponteiros `volatile` definidos em header, nunca por endereço literal no código.
- O `.hex` gerado é versionado, para que a simulação rode sem toolchain RISC-V.

## Scripts (Make, Tcl, shell)

- Somente caminhos relativos à raiz do repositório: o caminho absoluto tem espaços.
- Todo alvo novo aparece em `make help`.
- Scripts retornam código de saída diferente de zero em caso de falha.

## Git

- `main` sempre verde. O trabalho acontece em branches `feat/<bloco>-<tema>`, `fix/<bloco>-<tema>` ou `docs/<tema>`.
- Mensagens no formato Conventional Commits (`feat(dma): ...`, `fix(soc): ...`, `docs: ...`).
- PR pequeno, com descrição do que mudou e de como foi verificado. Como as ferramentas só existem na WSL do curso (não há CI), a descrição do PR traz a saída de `make check`. Mudança de interface só com ADR.
- A `main` é protegida: só recebe merge por PR.
- Tags por entrega: `e1`, `e2`, `e3`, `e4`, `final`.

## Definition of Done

**Sprint:**
- código com testes;
- `make check` verde;
- revisão técnica sem pendências bloqueantes;
- documentação afetada atualizada (ICD, README);
- status no `roadmap.md`.

**Entrega (épico):**
- todos os itens do enunciado para a entrega com evidência;
- revisão de produto aprovada;
- tag criada.
