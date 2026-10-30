Cada um entrega o mesmo pacote para o seu bloco: RTL, UVM, síntese no Genus e os próprios slides. O que muda é o conteúdo:

1. CPU: RV32I e firmware. O UVM roda programas autoverificáveis contra uma memória-modelo, e o firmware é testado com um DMA comportamental. Síntese: área e fmax do core.
2. DMA: registradores, FSM de tiling e acesso à memória. O UVM tem um agente que faz o papel da CPU (é o BFM que a E3 pede), mais um acelerador e uma memória comportamentais. Síntese: área e fmax.
3. Acelerador: MAC, systolic array parametrizável e buffers. O UVM faz o papel do DMA e roda 2×2, 4×4 e 8×8. Síntese das 3 configurações e análise de trade-off.
4. Sistema: memória dual-port, barramento/decodificador, top-level e golden model. O UVM dele é o UVM integrado que o enunciado pede, e a síntese é a do sistema inteiro nas 3 configurações, com os ciclos do teste. Também fica com a demo de waveform e junta os slides.