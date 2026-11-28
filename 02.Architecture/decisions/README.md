# Decisões (ADRs)

Um arquivo por decisão: `NNNN-titulo-curto.md`, a partir de [0000-template.md](0000-template.md).

Status possíveis:
- **proposta**: em discussão;
- **aceita**: aprovada pelos donos afetados;
- **substituída por NNNN**;
- **rejeitada**.

| Nº | Título | Status | Blocos afetados |
|---|---|---|---|
| [0001](0001-barramento-axi4-lite.md) | Barramento AXI4-Lite com uma interconexão única | aceita | Sistema, CPU, DMA, Acelerador |
| [0002](0002-acumulacao-de-parciais-no-dma.md) | Somas parciais de K acumuladas pelo DMA, com C em DATA_WIDTH bits | proposta | DMA, Acelerador, Sistema |
| [0003](0003-ligacao-do-acelerador-ao-barramento.md) | Acelerador como um escravo só, com um decodificador local entre CTRL/STATUS e os buffers | proposta | Sistema, Acelerador, DMA |
