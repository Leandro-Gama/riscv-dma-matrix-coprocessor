# 06.Firmware

Firmware RISC-V que configura e dispara o sistema. Dono: CPU.

| Diretório | Conteúdo |
|---|---|
| `src/` | fonte (C ou assembly) |
| `include/` | headers, incluindo o mapa de registradores do sistema |
| `link/` | linker script e código de inicialização |

O `.hex` gerado é versionado, para que a simulação rode sem toolchain RISC-V.
