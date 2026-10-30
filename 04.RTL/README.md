# 04.RTL

RTL em SystemVerilog sintetizável, um diretório por bloco. Convenções em [../CONTRIBUTING.md](../CONTRIBUTING.md); interfaces em [../02.Architecture/icd/](../02.Architecture/icd/).

| Diretório | Bloco | Dono |
|---|---|---|
| `common/` | packages e primitivas compartilhadas | Sistema |
| `soc/` | memória compartilhada, barramento/decodificador, top-level | Sistema |
| `cpu/` | RISC-V RV32I | CPU |
| `dma/` | controlador de DMA | DMA |
| `accel/` | MAC e systolic array parametrizável | Acelerador |
