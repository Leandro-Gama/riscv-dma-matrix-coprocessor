# ICD — contrato de interfaces

Fonte da verdade para portas, protocolos, temporização, mapa de memória e mapa de registradores entre CPU, DMA, acelerador e sistema. É versionado, e cada mudança cita a decisão de arquitetura (ADR, em [../decisions/](../decisions/)) que a justificou.

Nenhum bloco muda uma porta descrita aqui sem ADR aprovado pelos donos afetados.

**Versão 1.0:** está na [especificação da Entrega 1](../../08.Docs/e1_especificacao.md): barramento AXI4-Lite, mapa de memória, registradores do DMA e do acelerador e sinais de cada bloco.
