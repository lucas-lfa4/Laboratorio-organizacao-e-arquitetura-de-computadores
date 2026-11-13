# RV32I Pipelined Base Project

Processador RISC-V de 32 bits com pipeline de 5 estágios implementado em SystemVerilog, baseado nas seções 4.6 a 4.10 de *Computer Organization and Design: RISC-V Edition* (Patterson & Hennessy). O projeto tem como plataforma alvo a placa **DE2-115** (Intel Cyclone IV E) e é estruturado para servir de base para extensões do conjunto de instruções pelos alunos.

---

## Instruções suportadas

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `ADD`     | R    | 0110011 | ✅ |
| 2 | `SUB`     | R    | 0110011 | ✅ |
| 3 | `OR`      | R    | 0110011 | ✅ |
| 4 | `AND`     | R    | 0110011 | ✅ |
| 5 | `SLT`     | R    | 0110011 | ✅ |
| 6 | `LW`      | I    | 0000011 | ✅ |
| 7 | `SW`      | S    | 0100011 | ✅ |
| 8 | `BEQ`     | B    | 1100011 | ✅ |

### Resumo de cobertura do ISA RV32I

| Categoria          | Total ISA | Implementadas | Faltando |
|--------------------|:---------:|:-------------:|:--------:|
| R-type             | 10        | 5             | 5        |
| I-type aritmético  | 9         | 7             | 2        |
| I-type load        | 5         | 1 (LW)        | 4        |
| S-type             | 3         | 1 (SW)        | 2        |
| B-type             | 6         | 1 (BEQ)       | 5        |
| U-type             | 2         | 2             | 0        |
| J-type             | 2         | 0             | 2        |
| **Total**          | **37**    | **8**         | **29**   |

### Instruções a implementar — Etapa 01

#### Aritmética, lógica e deslocamentos (R-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `XOR`     | R    | 0110011 | ❌ |
| 2 | `SLL`     | R    | 0110011 | ❌ |
| 3 | `SRL`     | R    | 0110011 | ❌ |
| 4 | `SRA`     | R    | 0110011 | ❌ |
| 5 | `SLTU`    | R    | 0110011 | ❌ |

#### Aritmética, lógica e deslocamentos com imediatos (I-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `ADDI`    | I    | 0010011 | ✅ |
| 2 | `ANDI`    | I    | 0010011 | ✅ |
| 3 | `ORI`     | I    | 0010011 | ✅ |
| 4 | `SLTI`    | I    | 0010011 | ✅ |
| 5 | `SLLI`    | I    | 0010011 | ✅ |
| 6 | `SRLI`    | I    | 0010011 | ✅ |
| 7 | `SRAI`    | I    | 0010011 | ✅ |

### Instruções a implementar — Etapa 02

#### Acesso à memória — loads (I-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `LB`      | I    | 0000011 | ❌ |
| 2 | `LH`      | I    | 0000011 | ❌ |
| 3 | `LBU`     | I    | 0000011 | ❌ |
| 4 | `LHU`     | I    | 0000011 | ❌ |

#### Acesso à memória — stores (S-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `SB`      | S    | 0100011 | ❌ |
| 2 | `SH`      | S    | 0100011 | ❌ |

#### Desvios condicionais (B-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `BNE`     | B    | 1100011 | ❌ |
| 2 | `BLT`     | B    | 1100011 | ❌ |
| 3 | `BGE`     | B    | 1100011 | ❌ |
| 4 | `BLTU`    | B    | 1100011 | ❌ |
| 5 | `BGEU`    | B    | 1100011 | ❌ |

#### Jumps (J-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `JAL`     | J    | 1101111 | ❌ |
| 2 | `JALR`    | I    | 1100111 | ❌ |

#### Imediato superior (U-type)

| # | Instrução | Tipo | Opcode  | Status |
|---|-----------|------|---------|:------:|
| 1 | `LUI`     | U    | 0110111 | ✅ |
| 2 | `AUIPC`   | U    | 0010111 | ✅ |

### Etapa 02 — I-type aritmético e U-type (implementado)

| Arquivo | Mudança |
|---------|---------|
| `pl_control.sv` | Novos opcodes `0010011` (I-type aritmético), `0110111` (LUI) e `0010111` (AUIPC); novo sinal `ALUSrcA[1:0]`; `ALUOp = 2'b11` para I-type |
| `pl_alu_ctrl.sv` | Caso `ALUOp = 2'b11`: decodifica pelo `funct3`. `inst[31:25]` é parte do imediato, então só é usado em SRLI/SRAI (bit 30) — ADDI com imediato negativo não vira SUB |
| `pl_sign_ext.sv` | I-type aritmético: `{{20{inst[31]}}, inst[31:20]}`; U-type: `{inst[31:12], 12'b0}` |
| `pl_pipe_pkg.sv` | Campo `alu_src_a` no registrador ID/EX |
| `pl_datapath.sv` | Mux `ALUSrcA` na entrada A da ALU (rs1 / PC / zero), posicionado **depois** do forwarding: em LUI/AUIPC os bits [19:15] são imediato e o valor encaminhado é descartado |
| `pl_cpu.sv` | Ligação do sinal `ALUSrcA` entre controle e datapath |

| Instrução | ALUSrcA (A) | ALUSrc (B) | Operação |
|-----------|-------------|------------|----------|
| I-type aritmético | rs1 | imediato | conforme `funct3` |
| `LUI`   | zero | `imm << 12` | ADD |
| `AUIPC` | PC   | `imm << 12` | ADD |

Programa de teste: `assembler/etapa2.asm` (gera `modelsim/program.hex` e `golden.txt`). Cobre as 9 instruções, forwarding entre I-type, LUI cujo campo "rs1" coincide com um registrador recém-escrito, e load-use seguido de ADDI.

Estado final esperado: `x1=5  x2=-3  x3=4  x4=13  x5=1  x6=0  x7=40  x8=15  x9=-2  x10=0x12345678  x11=0x2C  x12=0x1030  x13=0x12345679  dmem[2]=0x12345678`

---

## Arquitetura

### Pipeline de 5 estágios

```
+------+     +------+     +------+     +------+     +------+
|  IF  | --> |  ID  | --> |  EX  | --> | MEM  | --> |  WB  |
+------+     +------+     +------+     +------+     +------+
  Busca      Decode       Execução     Memória     Write-back
  instrução  Regs         ALU          dmem/MMIO   Regfile
             Sign-ext     Branch
```

**Registradores de pipeline:** `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` (definidos em `pl_pipe_pkg.sv`).

### Tratamento de hazards

| Hazard | Mecanismo | Detalhe |
|--------|-----------|---------|
| RAW (dado) | Forwarding | EX/MEM → EX e MEM/WB → EX (`pl_forward.sv`) |
| Load-use | Stall | 1 bolha inserida em ID/EX (`pl_hazard.sv`) |
| Branch taken | Flush | 2 NOPs (IF e ID) na resolução em EX (`pl_datapath.sv`) |

**Resolução de branch no estágio EX:** quando `BEQ` é tomado, o PC retorna ao alvo e os dois estágios anteriores são esvaziados. O custo é de 2 ciclos de penalidade por branch tomado.

**Banco de registradores com escrita em negedge:** a escrita ocorre na borda de descida do clock, garantindo que o estágio ID leia o valor atualizado no próximo posedge sem necessidade de forwarding WB→ID explícito.

### Mapa de memória

| Endereço (byte) | Tamanho | Acesso | Descrição |
|-----------------|---------|--------|-----------|
| `0x000 – 0x3FC` | 256 × 32 b | R/W | Memória de dados (`pl_dmem`) |
| `0x400` | 32 b | R | SW\[17:0\] — chaves deslizantes |
| `0x404` | 32 b | R | KEY\[3:0\] — botões push |
| `0x408` | 32 b | W | LEDR\[17:0\] — LEDs vermelhos |
| `0x40C` | 32 b | W | LEDG\[8:0\] — LEDs verdes |
| `0x410` | 32 b | R/W | UART RS-232 (8N1, 9600 baud) |
| `0x414` | 32 b | R | Contador de ciclos de clock (32 bits, reset em 0) |

Seleção: `alu_result[10] = 1` redireciona o acesso ao controlador MMIO (`pl_mmio`).

**Leitura da UART (`lw` em 0x410):** `{22'b0, tx_busy[9], rx_ready[8], rx_data[7:0]}`

**Escrita na UART (`sw` em 0x410):** o hardware (`pl_mmio`) divide automaticamente a palavra de 32 bits em 4 bytes e os envia em sequência little-endian (byte 0 primeiro). `tx_busy` permanece alto até o último byte ser aceito pelo shift register. O software deve aguardar `tx_busy = 0` antes de escrever nova palavra.

### ALU — codificação de operação

| Operation | Instrução |
|-----------|-----------|
| `4'd01` ADD | LW, SW, ADD, ADDI, LUI, AUIPC |
| `4'd02` SUB | BEQ (comparação) |
| `4'd04` OR  | OR, ORI |
| `4'd05` AND | AND, ANDI |
| `4'd06` XOR | XOR, XORI |
| `4'd07` SLL | SLL, SLLI |
| `4'd08` SRL | SRL, SRLI |
| `4'd09` SRA | SRA, SRAI |
| `4'd11` SLT | SLT, SLTI |
| `4'd12` SLTU | SLTU, SLTIU |

---

## Estrutura do repositório

```
rv32i_pipelined_base_project/
│
├── src/                        Código-fonte SystemVerilog
│   ├── pl_pipe_pkg.sv          Structs dos registradores de pipeline
│   ├── pl_top.sv               Top-level (PLL 50→10 MHz + CPU)
│   ├── pl_cpu.sv               Wrapper: Control + ALU_Ctrl + Datapath
│   ├── pl_control.sv           Unidade de controle (estágio ID)
│   ├── pl_alu_ctrl.sv          Controle da ALU (estágio EX)
│   ├── pl_alu.sv               ALU 32 bits
│   ├── pl_regfile.sv           Banco de registradores 32×32 b
│   ├── pl_sign_ext.sv          Extensão de sinal I/S/B
│   ├── pl_imem.sv              Memória de instruções 256×32 b (MIF)
│   ├── pl_dmem.sv              Memória de dados 256×32 b (MIF)
│   ├── pl_mmio.sv              Controlador MMIO (SW/KEY/LED/UART)
│   ├── pl_uart.sv              UART RS-232 8N1 (9600 baud, 50 MHz)
│   ├── pl_hazard.sv            Detecção de hazard load-use
│   ├── pl_forward.sv           Unidade de forwarding
│   ├── pl_datapath.sv          Datapath 5 estágios
│   ├── pl_cpu_tb.sv            Testbench de verificação
│   └── pll_10mhz.v             PLL Altera (50 MHz → 10 MHz)
│
├── mifs/                       Arquivos de inicialização de memória
│   ├── instruction.mif         Programa de teste padrão
│   ├── data.mif                Dados iniciais do programa de teste
│   ├── mmio_test_program.mif   Programa de teste MMIO + UART
│   └── mmio_test_data.mif      Dados para o teste MMIO
│
├── assembler/
│   ├── assembler.py            Montador Python: assembly → .mif / dump
│   ├── hello.asm               Programa de entrada padrão
│   ├── instruction.mif         MIF gerado (saída do assembler)
│   ├── data.mif                MIF de dados gerado (modo --dump)
│   └── program.hex             Hex gerado (modo normal)
│
├── dump/
│   └── serial_dump.py          Captura e decodifica dump serial do FPGA
│
├── modelsim/                   Projeto ModelSim para simulação
│   ├── *.mpf                   Arquivo de projeto ModelSim
│   ├── program.hex             Imagem da instrução (.hex para $readmemh)
│   ├── data.hex                Imagem dos dados (.hex para $readmemh)
│   ├── golden.txt              Saída esperada pelo testbench
│   └── output.txt              Saída gerada na última simulação
│
└── quartus/                    Projeto Quartus Prime para síntese
    ├── *.qpf / *.qsf           Arquivos de projeto Quartus
    ├── instruction.mif         MIF da instrução (cópia de trabalho)
    └── data.mif                MIF dos dados (cópia de trabalho)
```

---

## Como simular (ModelSim)

1. Abra o ModelSim e carregue o projeto `modelsim/rv32i_pipelined_base_project.mpf`.
2. Compile todos os arquivos em `src/` — compilar `pl_pipe_pkg.sv` primeiro.
3. Inicie a simulação com o top `pl_cpu_tb`.
4. Execute `run -all`.

O testbench detecta o halt automaticamente (repetição periódica do PC causada pelo `beq x0, x0, 0`), imprime o estado final dos registradores e da memória, e compara a saída com `modelsim/golden.txt`.

**Programa de teste padrão (`mifs/instruction.mif`):**

```
000: lw  x1,  0(x0)   x1 = 10
001: lw  x2,  4(x0)   x2 = 20
002: add x3, x1, x2   x3 = 30   -- forwarding MEM/WB→EX
003: and x4, x3, x1   x4 = 10   -- forwarding EX/MEM→EX
004: lw  x5,  0(x0)   x5 = 10   -- causa load-use stall
005: add x6, x5, x2   x6 = 30   -- executado após 1 ciclo de stall
006: sw  x3,  8(x0)   dmem[2] = 30
007: beq x1, x2, +8   NÃO tomado (10 ≠ 20)
008: add x7, x1, x2   x7 = 30
009: beq x1, x5, +8   TOMADO (10 = 10) → flush de 00A
00A: add x8, x0, x0   DESCARTADO
00B: add x8, x1, x4   x8 = 20
00C: beq x0, x0,  0   halt
```

Estado final esperado: `x1=10  x2=20  x3=30  x4=10  x5=10  x6=30  x7=30  x8=20  dmem[2]=30`

---

## Como sintetizar (Quartus)

1. Abra o Quartus Prime e carregue `quartus/rv32i_pipelined_base_project.qpf`.
2. Verifique que os arquivos `instruction.mif` e `data.mif` estão na pasta `quartus/`.
3. Execute **Processing → Start Compilation**.
4. Grave o bitstream na DE2-115 via JTAG.

**Dispositivo alvo:** Intel Cyclone IV E — EP4CE115F29C7  
**Clock:** 50 MHz (entrada) → 10 MHz (saída da PLL, usado pelo CPU)  
**Reset:** KEY\[0\] ativo-baixo; liberado após a PLL travar.

---

## Assembler

O script `assembler/assembler.py` converte assembly textual para o formato `.mif`.

### Uso

```bash
cd assembler

# modo normal — gera instruction.mif + program.hex
python3 assembler.py programa.asm

# sem argumento — usa instructions.txt como padrão
python3 assembler.py

# modo dump — gera instruction.mif + data.mif com dump serial embutido
python3 assembler.py --dump programa.asm
```

Todos os arquivos de saída são gerados na pasta `assembler/`.

### Modo normal

| Arquivo | Formato | Uso |
|---------|---------|-----|
| `instruction.mif` | Quartus MIF | Síntese (Quartus) e simulação (ModelSim via `ram_init_file`) |
| `program.hex` | Um word hex por linha | Simulação via `$readmemh` |

### Modo `--dump`

Anexa automaticamente o código de dump serial ao programa do usuário, sem que o usuário precise escrever nenhuma instrução extra.

| Arquivo | Conteúdo |
|---------|----------|
| `instruction.mif` | Código do usuário + `beq` de desvio + dump serial a partir de `0x080` |
| `data.mif` | Zeros + constantes de infraestrutura do dump em `0x080–0x086` |

**Layout da memória de instruções com `--dump`:**

```
0x000..N-1  Código do usuário (máx. 127 instruções)
0xN         beq x0,x0,→0x80   (desvio incondicional para o dump)
0xN+1..07F  NOP (addi x0,x0,0)
0x080..0x0AD  Dump serial — Parts 2–8 (46 instruções)
```

**Layout da memória de dados com `--dump`:**

```
0x000..0x01F  Área do usuário  (byte 0x000–0x07C) — transmitida no dump
0x078..0x07F  Saves de x1–x8  (byte 0x1E0–0x1FC) — escritos em runtime
0x080..0x086  Constantes de infraestrutura         — inicializadas no MIF
```

**O que o dump transmite via UART (164 bytes = 41 palavras):**

```
bytes  0–  3   Contador de ciclos (MMIO 0x414)
bytes  4– 35   Registradores x1–x8
bytes 36–163   dmem[0x000–0x07C] (32 palavras do usuário)
```

O programa do usuário pode ter no máximo **127 instruções**; o assembler valida e reporta erro se excedido.

### Formato de entrada aceito

```
add  x3,x1,x2
lw   x1,0(x0)
sw   x3,8(x0)
beq  x1,x2,-4
```

Uma instrução por linha, sem rótulos, sem comentários. O argumento de arquivo é opcional — o padrão é `instructions.txt`.

---

## Detalhes de implementação

### Banco de registradores — escrita em negedge

A escrita no banco de registradores ocorre na **borda de descida** do clock (`negedge clk`). Isso resolve o conflito de leitura/escrita simultânea que ocorre quando, após um load-use stall, o estágio WB escreve um registrador no mesmo ciclo em que o estágio ID o lê para captura no registrador ID/EX. Com a escrita em negedge, o valor é garantidamente visível antes do próximo posedge. Esta é a solução descrita na Fig. 4.63 do P&H.

### Detecção de halt no testbench

O halt é implementado como `beq x0, x0, 0`. Com resolução de branch no estágio EX, o PC oscila com período 3 (H, H+4, H+8, H, …). O testbench detecta halt quando `PC_atual == PC_de_3_ciclos_atrás` por 9 ciclos consecutivos (3 períodos completos).

### UART (9600 8N1 a 50 MHz)

Implementada em `pl_uart.sv` (parâmetros `CLK_HZ=50_000_000`, `BAUD=9600`). Taxa de erro: < 0,1% (5208 clocks/bit, baud efetivo 9601). O sequenciador de 4 bytes em `pl_mmio.sv` divide automaticamente cada `sw` em 0x410 em 4 transmissões consecutivas, liberando o software de enviar byte a byte.

### Dump serial

O script `dump/serial_dump.py` captura e decodifica o dump transmitido pelo FPGA. Pré-requisito: `pip install pyserial`.

```bash
python3 dump/serial_dump.py COM3            # Windows
python3 dump/serial_dump.py /dev/ttyUSB0   # Linux
python3 dump/serial_dump.py COM3 --out resultado.txt
```

Aguarda **164 bytes** (41 palavras × ~4 ms a 9600 baud) e exibe ciclos, x1–x8 e dmem[0x000–0x07C]. Para usar, compile com `python3 assembler.py --dump` e grave o bitstream no FPGA.

**Fluxo completo:**

```bash
cd assembler
python3 assembler.py --dump meu_programa.asm  # gera instruction.mif + data.mif
cp instruction.mif data.mif ../quartus/        # copia para o projeto Quartus
# compilar e gravar na FPGA via Quartus...
cd ../dump
python3 serial_dump.py COM3                    # captura o resultado
```

---

## Recursos

- [Manual RISC-V ISA v2.2](https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf)
- [RISC-V ISA Reference (msyksphinz)](https://msyksphinz-self.github.io/riscv-isadoc/html/rvi.html)
- [RISC-V Interpreter — Cornell University](https://www.cs.cornell.edu/courses/cs3410/2019sp/riscv/interpreter/)
- Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*, seções 4.6 – 4.10
