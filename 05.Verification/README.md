# 05.Verification

| Diretório | Conteúdo | Dono |
|---|---|---|
| `common/` | VIP compartilhado, assertions de protocolo, scripts de veredito | Sistema |
| `models/` | modelos comportamentais dos blocos, conformes ao ICD | Sistema |
| `unit/` | testbenches unitários, um subdiretório por bloco | dono de cada bloco |
| `subsys/` | ambiente DMA + memória + acelerador, sem CPU (E3) | Sistema |
| `soc/` | UVM integrado do sistema completo (E4) | Sistema |
| `env_smoke/` | teste UVM mínimo que valida o ambiente (Xcelium + UVM + licença) | Sistema |

Diagnóstico do ambiente, na WSL e a partir da raiz do repositório:

```bash
make elab-smoke   # sem licença
make sim-smoke    # com licença; espera "SIM PASS"
```
