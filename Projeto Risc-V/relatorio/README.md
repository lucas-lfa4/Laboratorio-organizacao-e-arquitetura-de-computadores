# Relatório do Projeto Final: Processador RISC-V RV32I com Pipeline

CIN0012, Laboratório de Organização e Arquitetura de Computadores
Centro de Informática (CIn), Universidade Federal de Pernambuco (UFPE)
Professores: Victor Medeiros e Edna Barros
Novembro de 2026

| Nome | Usuário |
|------|:-------:|
| Alberto Marques dos Santos | ams18 |
| Carolina Santiago de Medeiros | csm6 |
| Ianne Vitória Cruz Fernandes | ivcf |
| Lucas Ferreira Alves | lfa4 |

Repositório: https://github.com/lucas-lfa4/Laboratorio-organizacao-e-arquitetura-de-computadores

---

## 1. Introdução

O RISC-V é uma arquitetura de conjunto de instruções aberta e livre, construída sobre os princípios RISC. O subconjunto RV32I trabalha com registradores e endereços de 32 bits e define o núcleo de instruções inteiras sobre o qual todas as extensões da arquitetura são construídas. Por ser pequeno, regular e bem documentado, ele se presta muito bem a um projeto didático de processador.

O objetivo deste trabalho foi estender um processador RISC-V com pipeline de cinco estágios (IF, ID, EX, MEM e WB), descrito em SystemVerilog, até que ele executasse o conjunto de instruções pedido na especificação da disciplina, e em seguida validá-lo em simulação e na placa FPGA DE2-115 (Cyclone IV E, EP4CE115F29C7). O ponto de partida foi o projeto base fornecido pelos professores (https://gitlab.com/jualabs-teaching/oac/rv32i_pipelined_base_project), que implementa apenas oito instruções: ADD, SUB, OR, AND, SLT, BEQ, LW e SW.

O desenvolvimento acompanhou as três etapas definidas no cronograma. A primeira completou as operações lógicas, aritméticas e de deslocamento entre registradores (XOR, SLL, SRL, SRA e SLTU). A segunda acrescentou as mesmas operações com imediato (ADDI, ANDI, ORI, XORI, SLTI, SLLI, SRLI e SRAI) e as duas instruções de imediato superior (LUI e AUIPC). A terceira, a maior delas, tratou dos acessos parciais à memória (LB, LH, LBU, LHU, SB e SH), dos desvios condicionais restantes (BNE, BLT, BGE, BLTU e BGEU) e dos saltos incondicionais (JAL e JALR). Ao final, o processador passou de 8 para 36 instruções, isto é, 28 instruções novas. A XORI não constava da lista da Etapa 2, mas foi incluída porque reaproveita integralmente a operação XOR criada na Etapa 1.

O código modificado está em `rv32i_pipelined_complete_project/`, enquanto `rv32i_pipelined_base_project/` guarda o código original para comparação. As seções seguintes descrevem o projeto base, as decisões de arquitetura que orientaram as mudanças, a implementação de cada grupo de instruções, os problemas encontrados no caminho e, por fim, a verificação em simulação e em hardware.

## 2. O projeto base

O processador base segue a organização clássica de pipeline de cinco estágios apresentada nas seções 4.6 a 4.10 do livro de Patterson e Hennessy. Os registradores de pipeline (IF/ID, ID/EX, EX/MEM e MEM/WB) são declarados como structs no pacote `pl_pipe_pkg.sv`, o que deixa claro quais sinais de controle e quais dados cada estágio entrega ao seguinte. A unidade de controle (`pl_control.sv`) decodifica o opcode no estágio ID e gera os sinais RegWrite, MemRead, MemWrite, MemtoReg, ALUSrc, Branch e ALUOp, que acompanham a instrução pelo pipeline. No estágio EX, o módulo `pl_alu_ctrl.sv` combina ALUOp com os campos funct3 e funct7 para escolher a operação executada pela ALU.

Os conflitos de dados são resolvidos por dois módulos. A unidade de forwarding (`pl_forward.sv`) adianta resultados dos registradores EX/MEM e MEM/WB para as entradas da ALU, dando prioridade ao mais recente e nunca adiantando o registrador x0. A unidade de detecção de hazard (`pl_hazard.sv`) identifica o caso load-use, em que uma instrução usa o registrador que acabou de ser carregado por um LW, e insere uma bolha de um ciclo: o PC e o IF/ID são congelados e o ID/EX é zerado. O banco de registradores escreve na borda de descida do clock, de modo que um valor gravado pelo WB já está disponível para a leitura no ID dentro do mesmo ciclo, sem necessidade de um caminho de forwarding adicional.

Os desvios são resolvidos no estágio EX. No projeto base, o BEQ usava a ALU para calcular rs1 − rs2 e desviava quando a saída Zero era verdadeira (`pc_src = branch && zero`). Quando o desvio é tomado, as duas instruções que entraram no pipeline depois dele (em IF/ID e ID/EX) são descartadas, o que custa dois ciclos por desvio tomado.

As memórias de instruções e de dados têm 256 palavras de 32 bits, com leitura assíncrona e escrita síncrona. O bit 10 do endereço calculado pela ALU seleciona o destino do acesso: endereços de 0x000 a 0x3FF vão para a memória de dados, e endereços a partir de 0x400 vão para o controlador de entrada e saída mapeada em memória (`pl_mmio.sv`), que expõe as chaves, os botões, os LEDs vermelhos e verdes, uma UART RS-232 e um contador de ciclos. O processador roda a 10 MHz, gerados por uma PLL a partir do oscilador de 50 MHz da placa.

O que faltava, portanto, estava espalhado por quase todos os blocos: a ALU conhecia apenas cinco operações, o controle reconhecia apenas quatro opcodes, o gerador de imediatos só montava os formatos I, S e B, o desvio só sabia testar igualdade e a memória de dados só era lida e escrita em palavras inteiras.

> **[FIGURA 1: diagrama do datapath com pipeline do projeto base, por exemplo o slide 3 da especificação do projeto ou uma figura equivalente do Patterson e Hennessy]**

## 3. Estratégia e decisões de arquitetura

A regra geral foi estender os blocos que já existiam, sem reorganizar o pipeline. A ALU continua fazendo todas as contas, inclusive as que não são operações aritméticas em sentido estrito, como o cálculo do alvo do JALR ou do resultado do LUI. Cada instrução nova entra como mais um caso nos blocos de controle, e os mecanismos de forwarding, stall e flush do projeto base foram reaproveitados sem modificação. Como consequência, apenas 8 dos 18 arquivos da pasta `src` foram alterados (`pl_alu`, `pl_alu_ctrl`, `pl_control`, `pl_sign_ext`, `pl_pipe_pkg`, `pl_cpu`, `pl_datapath` e `pl_mmio`), e no último a alteração não tem relação com o conjunto de instruções. Os módulos `pl_forward`, `pl_hazard`, `pl_regfile`, `pl_imem`, `pl_dmem`, `pl_uart`, `pl_top`, `pll_10mhz` e o testbench permaneceram como vieram.

A decisão mais visível foi manter a resolução de desvios no estágio EX, herdada do projeto base, em vez de antecipá-la para o ID como no diagrama do livro. No EX os dois operandos já chegam com forwarding aplicado, então o comparador de desvio pode usá-los diretamente. Mover a comparação para o ID reduziria a penalidade de dois para um ciclo, mas exigiria um caminho de forwarding até o ID e stalls adicionais sempre que o desvio dependesse da instrução imediatamente anterior. Consideramos que o ganho não compensava o risco de introduzir erros em uma parte do pipeline que já funcionava. Com isso, a nossa implementação difere do diagrama da especificação em dois pontos: o desvio é resolvido no EX e não há tratamento de exceções (registradores SCAUSE e SEPC e o desvio para o endereço 0x1C090000), que a especificação não pede.

As demais decisões aparecem em detalhe na seção 4, mas seguem a mesma lógica. Criamos um novo modo de ALUOp para as instruções com imediato, para que os bits do imediato nunca sejam confundidos com o campo funct7. LUI e AUIPC foram implementados com um multiplexador na entrada A da ALU, e não com um somador separado. O JALR calcula seu alvo na própria ALU, e o endereço de retorno de JAL e JALR substitui o resultado da ALU no registrador EX/MEM, de modo que segue o caminho normal até o banco de registradores e é coberto pelo forwarding existente. A seleção do byte ou da meia palavra nos loads acontece no estágio MEM, para que o valor adiantado de MEM/WB já esteja correto. Os stores parciais usam leitura, modificação e escrita da palavra no mesmo ciclo, o que dispensou alterar o módulo de memória.

## 4. Implementação

### 4.1 Etapa 1: R-type (XOR, SLL, SRL, SRA, SLTU)

As cinco novas instruções R-type usam o mesmo opcode (0110011) das que já existiam e se distinguem apenas pelos campos funct3 e funct7. Como o caminho "lê rs1 e rs2, opera na ALU, escreve em rd" já estava pronto, e como a unidade de controle já gerava os sinais corretos para esse opcode (RegWrite = 1, ALUSrc = 0, ALUOp = 10), o trabalho da Etapa 1 se limitou à ALU e ao seu controle. Também não foi preciso tocar no forwarding nem na detecção de hazard, que tratam qualquer instrução que escreve em rd da mesma maneira.

Em `pl_alu.sv` foram acrescentadas cinco operações, usando códigos que estavam livres e preservando os códigos originais (1, 2, 4, 5 e 11):

```systemverilog
4'd06: ALUResult = SrcA ^ SrcB;                  // XOR
4'd07: ALUResult = SrcA << SrcB[4:0];            // SLL
4'd08: ALUResult = SrcA >> SrcB[4:0];            // SRL
4'd09: ALUResult = $signed(SrcA) >>> SrcB[4:0];  // SRA
4'd12: ALUResult = 32'(SrcA < SrcB);             // SLTU
```

Os deslocamentos usam apenas os cinco bits menos significativos do segundo operando, como determina a especificação: deslocar uma palavra de 32 bits por mais de 31 posições não tem significado, e o RV32I manda ignorar os bits superiores. A diferença entre SRL e SRA está no que entra pela esquerda. No SRL entram zeros; no SRA entram cópias do bit de sinal, o que em SystemVerilog exige aplicar o operador `>>>` a um operando marcado como `$signed` (sem essa marcação, o `>>>` se comporta como um deslocamento lógico). Deslocando −16 duas posições para a direita, por exemplo, o SRL produz 0x3FFFFFFC e o SRA produz −4. A mesma distinção entre comparação com e sem sinal separa o SLT, que já existia, do SLTU: −1 é menor que 1 no SLT, mas 0xFFFFFFFF é maior que 1 no SLTU.

Em `pl_alu_ctrl.sv`, o bloco correspondente a ALUOp = 10 passou a cobrir os oito valores possíveis de funct3. Em dois deles o funct3 é compartilhado por um par de instruções, e o bit 30 da instrução (o bit 5 de funct7) faz a separação: ADD e SUB no funct3 = 000, SRL e SRA no funct3 = 101. A Tabela 1 resume a decodificação, incluindo a do I-type que será descrita na próxima seção.

**Tabela 1.** Decodificação em `pl_alu_ctrl.sv` para R-type (ALUOp = 10) e I-type aritmético (ALUOp = 11).

| funct3 | R-type | I-type | Operation |
|:------:|--------|--------|:---------:|
| 000 | ADD / SUB (bit 30) | ADDI | 1 ou 2 (R); sempre 1 (I) |
| 001 | SLL | SLLI | 7 |
| 010 | SLT | SLTI | 11 |
| 011 | SLTU | (SLTIU, não implementada) | 12 (R) |
| 100 | XOR | XORI | 6 |
| 101 | SRL / SRA (bit 30) | SRLI / SRAI (bit 30) | 8 ou 9 |
| 110 | OR | ORI | 4 |
| 111 | AND | ANDI | 5 |

### 4.2 Etapa 2: I-type aritmético (ADDI, ANDI, ORI, XORI, SLTI, SLLI, SRLI, SRAI)

As instruções aritméticas com imediato têm opcode próprio (0010011, chamado OP_IMM no código) e realizam as mesmas operações do R-type, com a diferença de que o segundo operando é um imediato de 12 bits com extensão de sinal, e não o conteúdo de rs2. Em `pl_control.sv`, o novo opcode ativa ALUSrc, para que o multiplexador da entrada B da ALU escolha o imediato, e RegWrite. O ponto central é o valor de ALUOp:

```systemverilog
OP_IMM: begin
    ALUSrc   = 1'b1;   // B = imediato
    RegWrite = 1'b1;
    ALUOp    = 2'b11;  // modo novo: decodificar apenas funct3
end
```

Seria tentador reaproveitar o ALUOp = 10 do R-type, já que os valores de funct3 coincidem, mas isso produziria um erro sutil. No formato I, os bits 31 a 25 da instrução não formam um campo funct7: eles são a parte alta do imediato. Uma instrução como `addi x1, x1, -1024` tem imediato 0xC00, cujo bit 30 vale 1, e com ALUOp = 10 ela seria executada como uma subtração. O modo ALUOp = 11 resolve o problema ignorando funct7 em todos os casos, exceto no funct3 = 101, que é o único em que o bit 30 de fato distingue duas instruções (SRLI e SRAI). Nas instruções de deslocamento, a ALU usa apenas os cinco bits inferiores do imediato (o campo shamt), então o bit 30 ligado em uma SRAI não interfere no valor do deslocamento.

O gerador de imediatos (`pl_sign_ext.sv`) não precisou de um formato novo para essas instruções: o opcode OP_IMM foi apenas acrescentado ao mesmo caso do LOAD, que já montava o imediato I como `{{20{Instr[31]}}, Instr[31:20]}`. A ALU também não mudou nesta etapa, porque todas as operações necessárias já haviam sido criadas na Etapa 1.

Vale registrar que a SLTIU (funct3 = 011) não faz parte da lista pedida e não foi implementada. Nesse caso o controle da ALU cai no ramo padrão e executa uma soma, de modo que um programa que use SLTIU produzirá um resultado incorreto.

### 4.3 Etapa 2: U-type (LUI e AUIPC)

LUI (opcode 0110111) e AUIPC (opcode 0010111) usam o formato U, em que os bits 31 a 12 da instrução formam um imediato de 20 bits destinado à parte alta do registrador. O LUI escreve esse valor em rd com os 12 bits inferiores zerados, e o AUIPC soma esse mesmo valor ao PC da instrução, o que permite montar endereços relativos ao programa.

A observação que guiou a implementação é que as duas instruções são somas. O LUI equivale a 0 + imediato e o AUIPC a PC + imediato. Como a ALU já sabe somar e o multiplexador da entrada B já é capaz de entregar o imediato, faltava apenas poder escolher o que entra na entrada A. Criamos para isso o sinal de controle de dois bits ALUSrcA, que seleciona entre rs1 (código 00, usado por todas as outras instruções), o PC (01, para o AUIPC) e a constante zero (10, para o LUI). Na unidade de controle, ambas as instruções ativam ALUSrc e RegWrite, usam ALUOp = 00 (soma) e diferem apenas no valor de ALUSrcA. O gerador de imediatos ganhou o caso `{Instr[31:12], 12'b0}`, que já entrega o imediato deslocado de 12 posições, e assim a ALU só precisa somar.

O multiplexador foi colocado no estágio EX, depois do forwarding:

```systemverilog
always_comb begin
    case (id_ex.alu_src_a)
        2'b01:   alu_srca = id_ex.pc;   // AUIPC: PC + imm
        2'b10:   alu_srca = 32'b0;      // LUI:   0  + imm
        default: alu_srca = fwd_srca;   // demais: rs1, já com forwarding
    endcase
end
```

A posição importa. Em LUI e AUIPC, os bits 19 a 15, que nas outras instruções indicam rs1, fazem parte do imediato. Se por coincidência eles forem iguais ao rd de uma instrução anterior ainda no pipeline, a unidade de forwarding vai adiantar um valor para a entrada A. Como o multiplexador vem depois, esse valor é simplesmente descartado. Como ALUSrcA é gerado no ID e usado no EX, ele precisou ser transportado pelo registrador ID/EX, o que motivou o novo campo `alu_src_a` na struct `id_ex_t` em `pl_pipe_pkg.sv` e a nova ligação entre controle e datapath em `pl_cpu.sv`.

Dois exemplos ilustram o resultado esperado: `lui x1, 0x12345` escreve 0x12345000 em x1, e `auipc x2, 1` no endereço 0x40 escreve 0x40 + 0x1000 = 0x1040 em x2.

### 4.4 Etapa 3: loads (LB, LH, LBU, LHU)

A Etapa 3 tem uma característica que a diferencia das anteriores: loads, stores e desvios condicionais não trouxeram opcodes novos. LB, LH, LBU e LHU compartilham o opcode do LW, SB e SH o do SW, e os cinco novos desvios o do BEQ. O que separa essas instruções é o funct3, e por isso o trabalho se concentrou no datapath, que passou a consultar o funct3 para decidir a largura do acesso ou a condição do desvio. O funct3 já era transportado até o estágio MEM no projeto base, então nenhum campo novo foi necessário nos registradores de pipeline para loads e stores.

O cálculo do endereço (rs1 + imediato) continua sendo feito pela ALU, exatamente como no LW. A memória de dados, porém, sempre devolve a palavra inteira de 32 bits que contém o endereço. Cabe ao load escolher o pedaço certo e completar os 32 bits. Os dois bits menos significativos do endereço indicam onde está o dado dentro da palavra (um dos quatro bytes, ou uma das duas metades), e o funct3 indica como completar: com cópias do bit de sinal no LB e no LH, com zeros no LBU e no LHU. Esse bloco foi colocado no estágio MEM, em `pl_datapath.sv`:

```systemverilog
case (ex_mem.funct3)
    3'b000:  load_data = {{24{ld_byte[7]}},  ld_byte};  // LB
    3'b001:  load_data = {{16{ld_half[15]}}, ld_half};  // LH
    3'b100:  load_data = {24'b0, ld_byte};              // LBU
    3'b101:  load_data = {16'b0, ld_half};              // LHU
    default: load_data = mem_read_data;                 // LW
endcase
```

onde `ld_byte` e `ld_half` são escolhidos por `ex_mem.alu_result[1:0]` e `ex_mem.alu_result[1]`, respectivamente. O valor gravado em MEM/WB passou a ser `load_data`, e não mais a palavra crua lida da memória. Fazer a seleção no MEM, e não no WB, garante que o caminho de forwarding de MEM/WB para EX já entregue o valor final a uma instrução que precise dele logo em seguida. Com a palavra 0x8765F0A1 armazenada no endereço 0x100, por exemplo, `lb` em 0x100 produz 0xFFFFFFA1, `lbu` em 0x100 produz 0x000000A1, `lh` em 0x102 produz 0xFFFF8765 e `lhu` em 0x102 produz 0x00008765.

### 4.5 Etapa 3: stores (SB, SH)

O problema dos stores parciais é o inverso do dos loads. A memória de dados grava palavras inteiras, então um SB que simplesmente escrevesse 32 bits apagaria os outros três bytes da palavra. A solução foi fazer uma leitura, modificação e escrita no mesmo ciclo. Primeiro, um vetor de habilitação `byte_en` marca quais bytes da palavra serão alterados: um byte no SB, escolhido pelos dois bits inferiores do endereço; dois bytes no SH, escolhidos pelo bit 1; e os quatro no SW. Em paralelo, o dado de rs2 é replicado em todas as posições possíveis (quatro cópias do byte no SB, duas da meia palavra no SH). Por fim, a palavra efetivamente gravada é montada byte a byte, tomando de rs2 os bytes habilitados e da palavra atual os demais:

```systemverilog
assign dmem_wdata = { byte_en[3] ? store_data[31:24] : dmem_rd[31:24],
                      byte_en[2] ? store_data[23:16] : dmem_rd[23:16],
                      byte_en[1] ? store_data[15:8]  : dmem_rd[15:8],
                      byte_en[0] ? store_data[7:0]   : dmem_rd[7:0] };
```

Isso só funciona porque a leitura de `pl_dmem` é assíncrona: a palavra atual (`dmem_rd`) está disponível no mesmo ciclo em que a escrita acontece, sem custo de ciclos extras. A alternativa seria substituir a memória por uma com habilitação de escrita por byte, o que mudaria um módulo que até então estava intocado. Com a palavra 0x11223344 na memória, um `sb` do valor 0xAB no byte de deslocamento 2 resulta em 0x11AB3344. A saída de observação usada pelo testbench (`mem_wr_data`) também passou a ser a palavra completa montada, para que o registro de escritas na memória mostre o conteúdo real após um SB ou SH.

### 4.6 Etapa 3: desvios condicionais (BNE, BLT, BGE, BLTU, BGEU)

O BEQ do projeto base dependia da saída Zero da ALU, que só responde à pergunta "os operandos são iguais?". Os novos desvios precisam também de comparações de ordem, com e sem sinal, e por isso substituímos o uso de Zero por um comparador dedicado no estágio EX, cuja condição é escolhida pelo funct3:

```systemverilog
case (id_ex.funct3)
    3'b000:  branch_taken = (fwd_srca == fwd_srcb);                    // BEQ
    3'b001:  branch_taken = (fwd_srca != fwd_srcb);                    // BNE
    3'b100:  branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb));  // BLT
    3'b101:  branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb));  // BGE
    3'b110:  branch_taken = (fwd_srca <  fwd_srcb);                    // BLTU
    3'b111:  branch_taken = (fwd_srca >= fwd_srcb);                    // BGEU
    default: branch_taken = 1'b0;
endcase
```

O comparador recebe `fwd_srca` e `fwd_srcb`, isto é, os valores de rs1 e rs2 já corrigidos pela unidade de forwarding. Esse é justamente o motivo para manter o desvio no EX: um BNE que dependa do resultado da instrução imediatamente anterior funciona sem nenhum stall adicional. O alvo do desvio continua sendo PC + imediato, calculado pelo mesmo somador que o BEQ já usava, e o mecanismo de flush das duas instruções seguintes também foi mantido. A diferença entre as versões com e sem sinal aparece com operandos negativos: com rs1 = −1 e rs2 = 1, o BLT desvia, porque −1 < 1, enquanto o BLTU não desvia, porque 0xFFFFFFFF > 1 quando interpretado sem sinal.

### 4.7 Etapa 3: saltos (JAL e JALR)

JAL e JALR são os únicos opcodes novos da Etapa 3. Ambos desviam sempre e gravam em rd o endereço de retorno PC + 4, que é o mecanismo usado para chamar uma função e voltar dela. A diferença está no alvo. O JAL (formato J) salta para PC + imediato, usando um imediato de 21 bits cujos campos aparecem embaralhados na instrução; o JALR (formato I) salta para rs1 + imediato, com o bit menos significativo forçado a zero, como exige a especificação.

Na unidade de controle, cada um ganhou um sinal próprio (Jal e Jalr), transportado pelo ID/EX em dois novos campos da struct. O JALR também ativa ALUSrc com ALUOp = 00, para que a ALU calcule rs1 + imediato. No gerador de imediatos, o JALR reaproveita o caso do formato I, e o JAL ganhou a montagem do formato J:

```systemverilog
JAL: ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
                Instr[20], Instr[30:21], 1'b0};
```

No datapath, três atribuições concentram a lógica dos saltos:

```systemverilog
assign pc_target = id_ex.jalr ? {alu_result[31:1], 1'b0} : branch_target;
assign pc_src    = (id_ex.branch && branch_taken) || id_ex.jal || id_ex.jalr;
assign ex_result = (id_ex.jal || id_ex.jalr) ? (id_ex.pc + 32'd4) : alu_result;
```

A primeira escolhe o alvo: o somador PC + imediato, já existente, serve aos desvios condicionais e ao JAL, enquanto o JALR usa o resultado da ALU com o bit 0 zerado. Como rs1 chega à ALU já com forwarding, um JALR que dependa de um registrador recém-calculado também funciona sem stall extra. A segunda ativa o desvio, e com ele o mesmo flush de duas instruções usado pelos desvios condicionais. A terceira coloca PC + 4 no lugar do resultado da ALU antes do registrador EX/MEM. Dessa forma, o endereço de retorno segue o caminho normal até o banco de registradores e pode ser adiantado pelo forwarding para instruções seguintes, sem nenhum caminho de dados novo até o WB. Em um uso típico, `jal x1, func` chama a função e guarda o endereço de volta em x1, e `jalr x0, 0(x1)` retorna dela.

## 5. Problemas encontrados

Alguns problemas surgiram fora das etapas propriamente ditas. Nenhum deles alterou o comportamento das instruções, mas dois exigiram mudanças em `pl_mmio.sv`.

O primeiro apareceu logo na compilação: o sinal `tx_byte` era usado na instância da UART antes de ser declarado, e o ModelSim recusava o arquivo (erro vlog-2388). A declaração foi movida para antes da instância, uma mudança apenas de ordem, sem efeito no circuito.

O segundo só se manifestou na placa. A UART estava parametrizada com `CLK_HZ = 50_000_000`, mas o processador e o MMIO rodam no clock de 10 MHz gerado pela PLL. O divisor de baud era calculado para um clock cinco vezes mais rápido, e a serial saía a 9600 / 5 = 1920 baud. Corrigimos o parâmetro para `10_000_000`, o clock real, e a comunicação voltou a 9600 baud, de modo que o `serial_dump.py` funciona sem precisar ajustar a taxa.

O terceiro envolveu o testbench. Quando o WB escreve em um registrador e o MEM escreve na memória no mesmo ciclo, o ModelSim imprime a linha do WB primeiro, mas outro simulador pode inverter essa ordem, e o teste acusa falha por causa de duas linhas trocadas, embora os valores estejam corretos. Optamos por não alterar o testbench e gerar o `golden.txt` na ordem produzida pelo ModelSim, que é o simulador usado na disciplina.

O quarto está no montador fornecido. O `assembler.py` codifica incorretamente o campo de deslocamento das instruções SLLI, SRLI e SRAI quando o deslocamento está entre 16 e 31: o campo sai com seis bits e invade o funct7. O hardware trata essas instruções corretamente, e o problema não foi corrigido no repositório; os programas de teste simplesmente evitam esse caso. A correção seria trocar a linha 533 do montador por `shamt = bin(int(shamt))[2:].zfill(5)`.

## 6. Verificação

### 6.1 Metodologia

A verificação foi feita em quatro frentes: os programas de teste enviados pelos professores, um teste completo escrito pela equipe, uma bateria de programas aleatórios e uma aplicação interativa na placa. Em simulação, o testbench do projeto base registra cada escrita em registrador e em memória e compara a sequência com um arquivo `golden.txt`. Em hardware, os programas são montados com a opção `--dump` do montador, que acrescenta ao final do código uma rotina que envia pela serial o contador de ciclos, os registradores x1 a x8 e as 32 primeiras palavras da memória de dados (41 palavras ao todo), capturadas no computador pelo script `serial_dump.py`.

Um cuidado importante foi a origem dos valores esperados. Eles não foram tirados do próprio processador, o que tornaria o teste circular, mas de um simulador de referência escrito à parte, em Python, que executa uma instrução por vez seguindo a especificação do RISC-V. Se o processador errasse, os dois discordariam. Tivemos uma demonstração prática disso durante o desenvolvimento: quando uma versão antiga do `pl_alu.sv` foi restaurada por engano, o teste da Etapa 2 passou a falhar imediatamente.

### 6.2 Testes dos professores

Os dois programas fornecidos foram executados em simulação e na placa. O `hello_e1.asm` exercita as instruções R-type e I-type aritméticas e grava doze resultados na memória, que conferem com a planilha de resultados esperados enviada com o teste. O `hello_e2.asm` cobre loads e stores parciais, LUI, AUIPC, todos os desvios condicionais, JAL e JALR. Na placa, o número de ciclos é maior porque o contador é lido dentro da rotina de dump, depois de algumas instruções adicionais. Para rodar um teste na placa, a última linha (`beq x0, x0, 0`, usada como halt na simulação) é retirada antes da montagem com `--dump`.

**Tabela 2.** Resultados dos testes fornecidos pelos professores.

| Teste | Cobertura | ModelSim | DE2-115 |
|-------|-----------|----------|---------|
| `hello_e1.asm` | R-type e I-type aritmético | PASS, 39 ciclos | 12 resultados corretos, 50 ciclos |
| `hello_e2.asm` | Loads, stores, LUI, AUIPC, desvios, JAL, JALR | PASS, 65 ciclos | todos os valores corretos, 76 ciclos |

No dump do `hello_e2` capturado na placa (`dump/dump.txt`), é possível conferir diretamente várias das extensões descritas na seção 4. O valor −107 (0xFFFFFF95) gravado com `sb` e `sh` é lido de volta como 0xFFFFFF95 pelo `lb` e pelo `lh`, como 0x00000095 pelo `lbu` e como 0x0000FF95 pelo `lhu`. O `lui x7, 3` produz 0x00003000, o `auipc x8, 0`, que ocupa o endereço 0x24, produz 0x24, e todas as flags de desvio e salto gravadas a partir do endereço 0x018 valem 1.

### 6.3 Teste completo

Para cobrir as 36 instruções em um único programa, escrevemos o `completo.asm`, com 108 instruções, que parte de dois operandos com padrões de bits pouco simétricos, A = 0x87654321 e B = 0x00000F0C, e exercita cada instrução com eles. Em simulação, o programa termina com PASS, atingindo o halt em PC = 0x1B4 depois de 132 ciclos. Gravado na DE2-115, ele produziu um dump idêntico ao esperado nas 41 palavras transmitidas, em 143 ciclos, e acende todos os LEDs verdes ao terminar. O trecho abaixo, extraído de `dump/dump_completo.txt`, mostra parte do resultado:

```
cycles = 143
x1 = 0x87654321   x2 = 0x00000F0C   x3 = 0xFFFFFF87   x4 = 0x00000087
x5 = 0xFFFF8765   x6 = 0x00008765   x7 = 0x87654321   x8 = 0x0000000C
```

Os registradores x3 a x6 guardam os resultados de LB, LBU, LH e LHU aplicados à palavra A, e permitem verificar de relance a diferença entre a extensão de sinal e a extensão com zeros.

> **[FIGURA 6: foto da DE2-115 ao final do teste completo, com os LEDs verdes acesos]**

### 6.4 Programas aleatórios

Os testes escritos à mão tendem a exercitar os casos que o próprio autor imaginou. Para reduzir esse viés, geramos 1000 programas por sorteio, somando 50.372 instruções, e executamos cada um no processador e no simulador de referência. Não houve nenhuma diferença. Como o gerador sorteia também dependências entre instruções vizinhas, esses programas não testam apenas as operações, mas a interação delas com o forwarding, com o stall de load-use e com o flush dos desvios e saltos, que são as partes do pipeline mais propensas a erros sutis.

### 6.5 Demonstração interativa na placa

Por fim, escrevemos um pequeno programa de calculadora para a demonstração: as chaves da placa escolhem a operação e os operandos, e o resultado aparece nos LEDs vermelhos. O programa foi conferido em simulação e na placa.

> **[FIGURA 7: foto da placa executando a calculadora, com a configuração das chaves e o resultado nos LEDs]**

## 7. Limitações e possíveis melhorias

O processador cobre as 36 instruções pedidas, mas há pontos que ficaram de fora ou que poderiam ser aprimorados. A SLTIU não foi implementada e, como explicado na seção 4.2, é executada como uma soma; acrescentá-la exigiria apenas mais uma linha no bloco ALUOp = 11 do `pl_alu_ctrl.sv`. As instruções FENCE, ECALL e EBREAK e o tratamento de exceções presentes no diagrama da especificação também não fazem parte da implementação, assim como a detecção de acessos desalinhados: um LH ou LW em endereço não alinhado simplesmente lê a parte da palavra indicada pelos bits de endereço, sem sinalizar erro. Os stores parciais, além disso, valem apenas para a memória de dados, já que o MMIO continua recebendo a palavra inteira.

Do ponto de vista de desempenho, todo desvio tomado e todo salto custam dois ciclos. Antecipar a resolução para o estágio ID reduziria a penalidade para um ciclo, ao preço do forwarding adicional discutido na seção 3, e um preditor de desvios simples poderia reduzi-la ainda mais em laços. A unidade de detecção de hazard herdada também é conservadora: ela compara os campos rs1 e rs2 de qualquer instrução com o rd de um load em EX, inclusive em instruções nas quais esses bits fazem parte do imediato (como LUI, JAL ou as do formato I no campo rs2). Isso nunca produz resultado errado, mas pode inserir uma bolha desnecessária de vez em quando. Por fim, o defeito do montador descrito na seção 5 deveria ser corrigido para permitir deslocamentos imediatos entre 16 e 31.

## 8. Conclusão

O projeto estendeu o processador base de 8 para 36 instruções do RV32I sem alterar a estrutura do pipeline. A maior parte do trabalho consistiu em acrescentar casos aos blocos de controle e reaproveitar o hardware já existente: a ALU passou a calcular também o resultado de LUI e AUIPC e o alvo do JALR, o endereço de retorno dos saltos viaja pelo mesmo caminho do resultado da ALU, e o forwarding, o stall de load-use e o flush do projeto base atenderam às instruções novas sem modificação. As poucas estruturas realmente novas (o multiplexador da entrada A da ALU, o comparador de desvio e os blocos de seleção de bytes para loads e stores) foram posicionadas de modo a continuar aproveitando esses mecanismos.

O processo também deixou claro o valor de uma verificação independente da implementação. Os valores esperados vieram de um simulador de referência, e não do próprio processador, e os programas aleatórios exercitaram combinações de dependências que dificilmente apareceriam em testes escritos à mão. O resultado foi um processador que passa nos testes dos professores e no teste completo, tanto no ModelSim quanto na DE2-115.

## Referências

PATTERSON, D. A.; HENNESSY, J. L. *Computer Organization and Design RISC-V Edition: The Hardware/Software Interface*. 2. ed. Morgan Kaufmann, 2020.

WATERMAN, A.; ASANOVIĆ, K. (ed.). *The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA*. RISC-V International. Cópia disponível em `Projeto Risc-V/riscv-unprivileged.pdf`.

MEDEIROS, V.; BARROS, E. *Especificação do Projeto RISC-V (RV32I)*. CIN0012, Centro de Informática, UFPE, 2026.

Projeto base: https://gitlab.com/jualabs-teaching/oac/rv32i_pipelined_base_project
