
# Estudo de Arquitetura — CPU RISC-V RV32I

## 1. Objetivo

Este estudo apresenta a análise e a definição da arquitetura da unidade de processamento baseada no conjunto de instruções RISC-V de 32 bits (RV32I).

O objetivo é estabelecer a organização interna da CPU, avaliar alternativas de microarquitetura e justificar a escolha da arquitetura que será utilizada no desenvolvimento do processador.

O planejamento considera uma organização modular, com separação entre caminho de dados, unidade de controle, armazenamento de registradores e subsistemas de memória.

## 2. Alternativas consideradas

Foram avaliadas duas alternativas de organização para a CPU: Single-Cycle e Pipeline.

### 2.1. Arquitetura Single-Cycle

Na arquitetura Single-Cycle, cada instrução é executada integralmente em um único ciclo de clock.

As operações de busca, decodificação, leitura dos operandos, execução, acesso à memória e escrita do resultado são realizadas dentro do mesmo ciclo.

**Características:**
- Um ciclo de clock por instrução.
- Caminho de dados compartilhado entre as etapas de execução.
- Unidade de controle combinacional.
- Atualização dos elementos sequenciais na borda ativa do clock.

**Vantagens:**
- Menor complexidade estrutural.
- Facilidade de implementação e depuração.
- Controle simplificado.
- Ausência de hazards decorrentes da sobreposição de instruções.

**Limitações:**
- O período de clock é determinado pelo caminho combinacional mais longo.
- Etapas mais simples não conseguem aproveitar integralmente o período disponível.
- Menor potencial de frequência em comparação com uma organização pipeline.

### 2.2. Arquitetura Pipeline

Na arquitetura Pipeline, o processamento das instruções é dividido em estágios que operam simultaneamente sobre instruções diferentes.

Uma organização clássica utiliza cinco estágios:

| Estágio | Descrição |
|---|---|
| IF | Busca da instrução |
| ID | Decodificação e leitura dos registradores |
| EX | Execução na ULA |
| MEM | Acesso à memória |
| WB | Escrita do resultado |

**Vantagens:**
- Maior potencial de throughput.
- Possibilidade de operação com frequências de clock mais elevadas.
- Melhor aproveitamento dos recursos computacionais.

**Limitações:**
- Necessidade de tratamento de hazards de dados e controle.
- Implementação de forwarding.
- Possibilidade de stalls e flushes.
- Maior complexidade da unidade de controle.
- Maior esforço de verificação e depuração.

## 3. Critérios de avaliação

A escolha da microarquitetura considera os seguintes critérios:

| Critério | Aspecto avaliado |
|---|---|
| Complexidade | Quantidade de componentes e mecanismos adicionais necessários |
| Funcionalidade | Suporte ao conjunto de instruções definido |
| Verificação | Facilidade de validação das operações e do caminho de dados |
| Temporização | Frequência potencial e caminho crítico |
| Organização | Separação modular e integração dos componentes |
| Evolução | Possibilidade de futuras modificações arquiteturais |

A análise considera também os requisitos estabelecidos para o projeto em `01.Specs/requirements.md`.

## 4. Evidências e análise

Como referência para a definição arquitetural, foi considerada uma implementação funcional de uma CPU RISC-V de 32 bits desenvolvida em Verilog.

A implementação de referência apresentou os seguintes resultados nas simulações:

| Verificação | Resultado |
|---|---:|
| Instruções executadas no teste de integração | 37 |
| Instruções distintas contempladas | 31 |
| Comparações complementares de branch | 16 |
| Tipos de branch avaliados | 6 |
| Erros reportados pelo testbench | 0 |

Os testes contemplaram operações aritméticas e lógicas, deslocamentos, comparações, acessos à memória, desvios condicionais e saltos.

A arquitetura Single-Cycle permitiu acompanhar diretamente o comportamento dos componentes, facilitando a verificação do contador de programa, dos resultados da ULA e das escritas no banco de registradores e na memória.

Em relação à alternativa Pipeline, a adoção de estágios adicionais exigiria a implementação e verificação de mecanismos de controle de dependências entre instruções.

**Impacto da escolha nos componentes:**

| Componente | Single-Cycle | Pipeline |
|---|---|---|
| PC e busca | Atualização direta a cada instrução | Integração com fluxo de estágios |
| Unidade de controle | Menor complexidade | Controle de hazards e estágios |
| Banco de registradores | Leitura e escrita por instrução | Dependências entre instruções |
| ULA | Operação no mesmo ciclo | Integrada ao estágio de execução |
| Memória | Acesso no mesmo ciclo | Estágio específico de memória |
| Verificação | Menor complexidade | Verificação adicional de sobreposição e dependências |

Não foram realizadas medições experimentais de frequência máxima, área ou comparação física de desempenho entre as duas alternativas. A decisão é fundamentada na complexidade arquitetural e nos resultados funcionais disponíveis.

## 5. Recomendação arquitetural

Recomenda-se a adoção da arquitetura RISC-V RV32I Single-Cycle.

A escolha é justificada pela menor complexidade de implementação, pela organização modular do caminho de dados e pela facilidade de verificação funcional do conjunto de instruções.

A implementação de referência demonstrou a execução do subconjunto de instruções previsto, constituindo uma base para a definição da microarquitetura.

A arquitetura Pipeline permanece como alternativa de evolução, caso futuras necessidades de desempenho justifiquem a introdução de mecanismos adicionais de processamento.

## 6. Escopo e considerações

O planejamento contempla exclusivamente a unidade de processamento RISC-V.

O escopo funcional considera o subconjunto de instruções definido para o projeto, com operações aritméticas, lógicas, de memória, desvios e saltos.

A escolha Single-Cycle define a organização inicial da CPU, permitindo que os componentes sejam especificados e integrados de maneira incremental.

A decisão arquitetural correspondente deverá ser registrada em um ADR separado, conforme as convenções do repositório.
