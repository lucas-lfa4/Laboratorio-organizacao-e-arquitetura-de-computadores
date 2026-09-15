# RISC-V Single-Cycle Processor

Implementação em SystemVerilog de um processador RISC-V de ciclo único, baseada no Capítulo 4 de *Patterson & Hennessy — Computer Organization and Design (RISC-V Edition)*. Alvo: placa **DE2-115** (Intel Cyclone IV E, EP4CE115F29C7, 50 MHz).

---

## Instruções suportadas

| Tipo   | Instrução | Opcode    | Funct3 | Funct7   |
|--------|-----------|-----------|--------|----------|
| R-type | `add`     | `0110011` | `000`  | `0000000`|
| R-type | `sub`     | `0110011` | `000`  | `0100000`|
| R-type | `and`     | `0110011` | `111`  | `0000000`|
| R-type | `or`      | `0110011` | `110`  | `0000000`|
| R-type | `slt`     | `0110011` | `010`  | `0000000`|
| I-type | `lw`      | `0000011` | `010`  | —        |
| S-type | `sw`      | `0100011` | `010`  | —        |
| B-type | `beq`     | `1100011` | `000`  | —        |

---

## Arquitetura

```
sc_top
└── sc_cpu
    ├── sc_control      — Unidade de controle principal (decodifica opcode)
    └── sc_datapath
        ├── sc_imem     — Memória de instruções (256 × 32 bits, program.hex)
        ├── sc_regfile  — Banco de registradores (32 × 32 bits)
        ├── sc_sign_ext — Extensor de sinal (formatos I, S, B)
        ├── sc_alu_ctrl — Controle da ALU (ALUOp + Funct3/Funct7 → Operation)
        ├── sc_alu      — ALU de 32 bits (add, sub, or, and, slt)
        └── sc_dmem     — Memória de dados (256 × 32 bits, data.hex)
```

### Memórias — leitura assíncrona

`sc_imem` e `sc_dmem` são implementadas como arrays SystemVerilog (`logic [31:0] mem [0:255]`) com leitura puramente combinacional:

```systemverilog
assign instr    = rom[addr];   // sc_imem: async, sem clock
assign ReadData = ram[addr];   // sc_dmem: async, sem clock
```

Escritas em `sc_dmem` (instrução `sw`) são síncronas na borda de subida:

```systemverilog
always @(posedge clk)
    if (MemWrite) ram[addr] <= WriteData;
```

O Quartus infere **MLAB** (LUT-RAM) automaticamente para arrays com leitura combinacional, que suportam leitura assíncrona nativamente no Cyclone IV.

<!-- ### Diagrama de temporização

Com leitura assíncrona, o caminho combinacional completo dispõe do período inteiro de **20 ns**:

```
posedge
  │  PC atualiza (FF)
  │  regfile escreve (FF)
  │
  ├─── addr = pc[9:2] estável (combinacional)
  │       │
  │    instr disponível (sc_imem async)
  │       │
  │    decode → regfile read → ALU → addr estável
  │                                      │
  │                                  ReadData disponível (sc_dmem async)
  │                                      │
  │                                  mux → write_back estável
  │                                      │
posedge ──────────────────── setup ──────┘
```

--- -->

## Sinais de controle

| Sinal    | R-type | `lw` | `sw` | `beq` |
|----------|:------:|:----:|:----:|:-----:|
| ALUSrc   | 0      | 1    | 1    | 0     |
| MemtoReg | 0      | 1    | —    | —     |
| RegWrite | 1      | 1    | 0    | 0     |
| MemRead  | 0      | 1    | 0    | 0     |
| MemWrite | 0      | 0    | 1    | 0     |
| Branch   | 0      | 0    | 0    | 1     |
| ALUOp    | `10`   | `00` | `00` | `01`  |

---

## Arquivos

| Arquivo            | Descrição |
|--------------------|-----------|
| `sc_top.sv`        | Módulo top-level |
| `sc_cpu.sv`        | CPU: conecta controle e datapath |
| `sc_control.sv`    | **Unidade de controle** (precisa ser implementado) |
| `sc_datapath.sv`   | Datapath completo |
| `sc_imem.sv`       | Memória de instruções — array SV, leitura async |
| `sc_dmem.sv`       | Memória de dados — array SV, leitura async, escrita sync |
| `sc_regfile.sv`    | Banco de registradores |
| `sc_alu.sv`        | ALU de 32 bits |
| `sc_alu_ctrl.sv`   | Controle da ALU |
| `sc_sign_ext.sv`   | Extensor de sinal |
| `sc_cpu_tb.sv`     | Testbench com verificação por golden file |
| `program.hex`      | Programa de teste (formato `$readmemh`) |
| `data.hex`         | Memória de dados inicial (formato `$readmemh`) |
| `program.mif`      | Programa de teste (formato Altera — referência) |
| `data.mif`         | Memória de dados inicial (formato Altera — referência) |
| `sc_top.sdc`       | Restrições de timing (TimeQuest, 50 MHz) |
| `quartus/`         | Projeto Quartus Prime (`.qpf`, `.qsf`) |
| `modelsim/`        | Ambiente de simulação ModelSim |

---

## Programa de teste (`program.hex`)

O programa cobre todas as instruções suportadas e produz resultados determinísticos verificáveis:

```asm
lw  x1,  0(x0)      # x1 = 5  (A)
lw  x2,  4(x0)      # x2 = 3  (B)
add x3,  x1, x2     # x3 = 8
sub x4,  x1, x2     # x4 = 2
and x5,  x1, x2     # x5 = 1
or  x6,  x1, x2     # x6 = 7
slt x7,  x2, x1     # x7 = 1  (3 < 5, true)
slt x8,  x1, x2     # x8 = 0  (5 < 3, false)
sw  x3,  8(x0)      # mem[8]  = 8
sw  x4, 12(x0)      # mem[12] = 2
sw  x5, 16(x0)      # mem[16] = 1
sw  x6, 20(x0)      # mem[20] = 7
sw  x7, 24(x0)      # mem[24] = 1
sw  x8, 28(x0)      # mem[28] = 0
beq x1,  x2, +8     # NÃO tomado (x1 ≠ x2)
lw  x9,  8(x0)      # x9 = 8  (verifica roundtrip sw/lw)
beq x3,  x9, +8     # TOMADO (x3 = x9 = 8), pula próxima instrução
add x10, x3, x3     # PULADO — x10 = 0; se executado erroneamente, x10 = 16
beq x0,  x0, 0      # halt
```

---

## Simulação (ModelSim)

### 1. Compilar os arquivos

No terminal do ModelSim (diretório `modelsim/`):

```tcl
vlib work
vmap work work
vlog -sv ../sc_alu.sv ../sc_alu_ctrl.sv ../sc_control.sv \
         ../sc_sign_ext.sv ../sc_regfile.sv               \
         ../sc_imem.sv ../sc_dmem.sv                      \
         ../sc_datapath.sv ../sc_cpu.sv ../sc_cpu_tb.sv
```

> Os arquivos `program.hex` e `data.hex` devem estar no diretório de trabalho da simulação. Copie-os para `modelsim/`.

### 2. Verificar a implementação

O arquivo `golden.txt` deve estar presente no diretório de trabalho (fornecido pelo professor).

```tcl
vsim work.sc_cpu_tb
run -all
```

Durante a simulação, cada escrita em registrador ou memória é impressa no console:

```
[cycle   1] REG  x1  <= 00000005
[cycle   2] REG  x2  <= 00000003
[cycle   3] REG  x3  <= 00000008
...
[cycle   9] MEM  [word 02] <= 00000008
[cycle  10] MEM  [word 03] <= 00000002
```

Ao final, gera `output.txt` e compara linha a linha com `golden.txt`:

```
=== PASS: all 42 lines match ===
```
ou
```
=== FAIL: 3 mismatch(es) in 42 lines ===
  line  15 MISMATCH
    expected: CYCLE  15  PC=0000003c
    got:      CYCLE  15  PC=00000040
```

### Conteúdo do golden file

```
CYCLE   1  PC=00000000
CYCLE   2  PC=00000004
...
CYCLE  18  PC=00000048
---
x0  = 00000000
x1  = 00000005
x2  = 00000003
x3  = 00000008
x4  = 00000002
x5  = 00000001
x6  = 00000007
x7  = 00000001
x8  = 00000000
x9  = 00000008
x10 = 00000000
---
MEM[00] = 00000005
MEM[01] = 00000003
MEM[02] = 00000008
MEM[03] = 00000002
MEM[04] = 00000001
MEM[05] = 00000007
MEM[06] = 00000001
MEM[07] = 00000000
```

---

## Exercício: implementar `sc_control.sv`

O arquivo `sc_control.sv` contém a unidade de controle principal. A interface é:

```systemverilog
module sc_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic [1:0] ALUOp
);
```

Implemente o `case` sobre `Opcode` para os quatro tipos de instrução conforme a tabela de sinais de controle acima. Após implementar, use o testbench para validar:

```tcl
vsim work.sc_cpu_tb
run -all
```

---

## Referências

- Patterson, D. A.; Hennessy, J. L. *Computer Organization and Design: RISC-V Edition*. 2ª ed. Morgan Kaufmann, 2020. Capítulos 4.1–4.4.
- [RISC-V Instruction Set Manual, Volume I: Unprivileged ISA](https://riscv.org/specifications/)