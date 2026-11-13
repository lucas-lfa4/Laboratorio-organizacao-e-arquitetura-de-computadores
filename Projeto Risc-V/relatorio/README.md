# Relatório do Projeto Final: Processador RISC-V RV32I com Pipeline

CIN0012, Laboratório de Organização e Arquitetura de Computadores
Centro de Informática (CIn), Universidade Federal de Pernambuco (UFPE)
Professores: Victor Medeiros e Edna Barros
Novembro de 2026

| Nome | Usuário |
|------|:-------:|
| Alberto Marques dos Santos | ams18 |
| Carolina Santiago de Medeiros | csm6 |
| Ianne Vitória Cruz Fernandes | ivsf |
| Lucas Ferreira Alves | lfa4 |

---

## 1. Introdução

A arquitetura RISC-V é uma ISA aberta e livre, baseada no conceito RISC. O subconjunto RV32I utiliza registradores e endereçamento de 32 bits e define 37 instruções inteiras de uso geral.

O objetivo deste projeto é estender um processador RISC-V com pipeline de cinco estágios (IF, ID, EX, MEM, WB), descrito em SystemVerilog, até cobrir o RV32I completo, e executá-lo na FPGA DE2-115 (Cyclone IV E, EP4CE115F29C7).

O ponto de partida é o repositório base fornecido pelos professores (https://gitlab.com/jualabs-teaching/oac/rv32i_pipelined_base_project). Essa implementação cobre apenas ADD, SUB, OR, AND, SLT, BEQ, LW e SW.

O desenvolvimento foi organizado em três etapas:

- Etapa 01 - R-type: XOR, SLL, SRL, SRA, SLTU |
- Etapa 02 - I-type: ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI; U-type: LUI, AUIPC |
- Etapa 03 - Loads: LB, LH, LBU, LHU; Stores: SB, SH; Branches: BNE, BLT, BGE, BLTU, BGEU; Jumps: JAL, JALR |

## 2. Arquitetura do projeto base

O processador base segue a organização clássica de pipeline de 5 estágios do livro de Patterson e Hennessy. Os registradores de pipeline (IF/ID, ID/EX, EX/MEM, MEM/WB) são definidos como structs no pacote `pl_pipe_pkg.sv`.

O controle principal (`pl_control.sv`) decodifica o opcode no estágio ID e gera sinais como RegWrite, MemRead, MemWrite, ALUSrc, ALUOp, Branch, entre outros. Esses sinais são propagados junto com os dados pelos registradores de pipeline.

O tratamento de hazards é feito por dois módulos:
- `pl_forward.sv`: resolve hazards RAW por adiantamento de dados. Os caminhos são EX/MEM para EX (prioridade maior) e MEM/WB para EX. O registrador x0 nunca é adiantado.
- `pl_hazard.sv`: detecta o hazard load-use (instrução de load seguida imediatamente por instrução que lê o registrador destino) e insere uma bolha de 1 ciclo, travando PC e IF/ID e zerando ID/EX.

Branches são resolvidos no estágio EX, o que implica um flush de 2 instruções (IF/ID e ID/EX são zerados) quando o desvio é tomado.

A memória de dados e de instruções são memórias de 256 palavras de 32 bits com leitura assíncrona. O endereçamento de periféricos é feito pelo bit 10 do resultado da ALU: endereços de 0x000 a 0x3FF acessam a dmem e endereços de 0x400 a 0x7FF acessam o módulo MMIO (`pl_mmio.sv`), que conecta chaves (SW), botões (KEY), LEDs vermelhos (LEDR), LEDs verdes (LEDG), UART e um contador de ciclos.

O clock do processador é gerado por uma PLL que divide o clock de 50 MHz da placa para 10 MHz.

## 3. Implementação

### 3.1 Etapa 01: R-type (XOR, SLL, SRL, SRA, SLTU)

As cinco novas instruções R-type compartilham o opcode 0110011 com as já existentes (ADD, SUB, AND, OR, SLT) e são diferenciadas pela combinação de funct3 e funct7.

As alterações concentraram-se em dois módulos:

Em `pl_alu_ctrl.sv`, o bloco para ALUOp = 2'b10 (R-type) já existia e decodificava funct3 = 0 (ADD/SUB), 2 (SLT), 6 (OR) e 7 (AND). Os novos casos adicionados no mesmo case foram:

| funct3 | funct7[5] | Instrução | Operation |
|:------:|:---------:|-----------|:---------:|
| 001 | 0 | SLL | 7 |
| 011 | 0 | SLTU | 12 |
| 100 | 0 | XOR | 6 |
| 101 | 0 | SRL | 8 |
| 101 | 1 | SRA | 9 |

Em `pl_alu.sv`, as novas operações foram adicionadas ao case de Operation:

```systemverilog
4'd06: ALUResult = SrcA ^ SrcB;                   // XOR
4'd07: ALUResult = SrcA << SrcB[4:0];             // SLL
4'd08: ALUResult = SrcA >> SrcB[4:0];             // SRL
4'd09: ALUResult = $signed(SrcA) >>> SrcB[4:0];   // SRA
4'd12: ALUResult = 32'(SrcA < SrcB);              // SLTU
```

Os deslocamentos usam apenas os 5 bits menos significativos de SrcB (shamt), conforme a especificação RV32I. O deslocamento aritmético à direita (SRA) utiliza o operador `>>>` do SystemVerilog aplicado sobre o operando interpretado como signed, o que preserva o bit de sinal.

Nenhuma alteração foi necessária em `pl_control.sv`, pois o opcode é o mesmo das instruções R-type já existentes. Os sinais de controle (RegWrite=1, ALUSrc=0, ALUOp=10, etc.) são idênticos. O pipeline, o forwarding e a detecção de hazards também não precisaram de modificações, pois as novas instruções seguem o mesmo fluxo de dados das anteriores.

### 3.2 Etapa 02: I-type aritmético (ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI)

As instruções I-type aritméticas usam o opcode 0010011. A principal diferença em relação ao R-type é que o segundo operando vem de um imediato de 12 bits com extensão de sinal, e não do registrador rs2.

Em `pl_control.sv`, foi adicionado o caso para o opcode OP_IMM (0010011):

```systemverilog
OP_IMM: begin
    ALUSrc   = 1'b1;   // B = imediato
    RegWrite = 1'b1;
    ALUOp    = 2'b11;  // decodificar funct3
end
```

O sinal ALUSrc = 1 faz o mux no estágio EX selecionar o imediato estendido em vez de rs2. O ALUOp = 2'b11 é um novo código que indica ao controlador da ALU que a decodificação deve usar funct3 para I-type.

Em `pl_alu_ctrl.sv`, foi adicionado o bloco para ALUOp = 2'b11:

| funct3 | Instrução | Operation |
|:------:|-----------|:---------:|
| 000 | ADDI | 1 (ADD) |
| 001 | SLLI | 7 (SLL) |
| 010 | SLTI | 11 (SLT) |
| 011 | SLTIU | 12 (SLTU) |
| 100 | XORI | 6 (XOR) |
| 101 | SRLI / SRAI | 8 (SRL) ou 9 (SRA) |
| 110 | ORI | 4 (OR) |
| 111 | ANDI | 5 (AND) |

Um ponto sutil: no formato I-type, os bits inst[31:25] fazem parte do imediato, não são um campo funct7 independente. Apenas para SRLI/SRAI (funct3 = 101) o bit 30 (equivalente a funct7[5]) distingue o deslocamento lógico do aritmético. Por isso, ADDI com imediato negativo nunca é confundido com uma subtração.

Em `pl_sign_ext.sv`, o opcode OP_IMM foi adicionado junto ao caso de LOAD, pois ambos usam o mesmo formato de imediato I-type: `ImmExt = {{20{Instr[31]}}, Instr[31:20]}`.

Nenhuma alteração foi necessária na ALU, pois as operações já haviam sido implementadas na Etapa 01.

### 3.3 Etapa 02: U-type (LUI, AUIPC)

LUI e AUIPC usam opcodes distintos (0110111 e 0010111) e o formato U-type, cujo imediato de 20 bits ocupa os bits [31:12] da instrução. O valor estendido é `{Instr[31:12], 12'b0}`, ou seja, o imediato deslocado 12 bits à esquerda.

A semântica é:
- LUI: rd = imm << 12 (carrega um imediato nos 20 bits superiores do registrador)
- AUIPC: rd = PC + (imm << 12) (endereçamento relativo ao PC)

Para implementar isso sem duplicar a ALU, foi introduzido um novo sinal de controle `ALUSrcA[1:0]`, que seleciona a entrada A da ALU:

| ALUSrcA | Fonte de A | Uso |
|:-------:|------------|-----|
| 00 | rs1 (com forwarding) | R-type, I-type, loads, stores, branches |
| 01 | PC | AUIPC |
| 10 | zero (32'b0) | LUI |

Em ambos os casos, ALUSrc = 1 (entrada B = imediato) e ALUOp = 00 (ADD), de modo que a ALU calcula A + imediato. Para LUI, A = 0, logo o resultado é o próprio imediato. Para AUIPC, A = PC, logo o resultado é PC + imediato.

Em `pl_control.sv`:

```systemverilog
LUI: begin
    ALUSrc   = 1'b1;
    ALUSrcA  = 2'b10;   // A = zero
    RegWrite = 1'b1;
    ALUOp    = 2'b00;   // ADD
end
AUIPC: begin
    ALUSrc   = 1'b1;
    ALUSrcA  = 2'b01;   // A = PC
    RegWrite = 1'b1;
    ALUOp    = 2'b00;   // ADD
end
```

Em `pl_sign_ext.sv`, os opcodes LUI e AUIPC compartilham o mesmo caso: `ImmExt = {Instr[31:12], 12'b0}`.

No datapath, o mux de ALUSrcA foi posicionado depois do forwarding. Isso é correto porque em LUI e AUIPC os bits inst[19:15] (que normalmente indicam rs1) fazem parte do imediato e não representam um registrador fonte. O valor que o forwarding encaminhar para SrcA é simplesmente descartado pelo mux quando ALUSrcA != 00.

```systemverilog
always_comb begin
    case (id_ex.alu_src_a)
        2'b01:   alu_srca = id_ex.pc;     // AUIPC
        2'b10:   alu_srca = 32'b0;        // LUI
        default: alu_srca = fwd_srca;     // demais
    endcase
end
```

O sinal ALUSrcA precisou ser propagado pelo registrador ID/EX (campo `alu_src_a` na struct `id_ex_t` do pacote `pl_pipe_pkg.sv`).

### 3.4 Etapa 03: Loads (LB, LH, LBU, LHU)

(a ser preenchido)

### 3.5 Etapa 03: Stores (SB, SH)

(a ser preenchido)

### 3.6 Etapa 03: Branches (BNE, BLT, BGE, BLTU, BGEU)

(a ser preenchido)

### 3.7 Etapa 03: Jumps (JAL, JALR)

(a ser preenchido)

## 4. Verificação e testes

(a ser preenchido)

## 5. Conclusão

(a ser preenchido)
