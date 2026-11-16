"""
Author: Nathalia Barbosa (@nathaliafab)
Date: 2023-06-16

This script translates instructions from a given file into a format readable by the instruction memory.
(It basically functions as an assembler.)

> The instructions to be translated are stored in a file named "instructions.txt"
> The translated instructions will be written to a file named "instruction.mif"

The instructions MUST follow the following formats, with one instruction per line:

<instruction> <register>,<register>,<register>
<instruction> <register>,<register>,<immediate>
<instruction> <register>,<offset>(<register>)
<instruction> <register>,<immediate>

~ Otherwise, it won't work. ;)

Example of a valid instruction file (content delimited by ```):
```
sub x6,x6,x1
addi x1,x0,8
lw x9,0(x0)
auipc x6,3
```
"""

import argparse
import os

# ---------------------------------------------------------------------------
# --dump mode constants
# ---------------------------------------------------------------------------
# Instruction memory: dump code always starts at word address DUMP_START.
DUMP_START = 0x80

# Data memory layout (word addresses):
#   0x000..0x01F : user data area (byte 0x000..0x07C) — sent in mem dump
#   0x072..0x079 : saves x1-x8  (byte 0x1C8..0x1E4)  — written at runtime
#   0x080..0x086 : infrastructure constants            — initialised in data.mif
SAVES_WBASE = 0x78               # first word address of saves area
SAVES_BBASE = SAVES_WBASE * 4    # = 0x1C8 = 456  (byte offset for sw from x0)
SAVES_BEND  = (SAVES_WBASE + 8) * 4  # = 0x1E8 = 488  (exclusive end for loop)

INFRA_WBASE = 0x80
INFRA_BBASE = INFRA_WBASE * 4   # = 0x200 = 512  (fits in 12-bit signed imm)

NOP_WORD = "00000013"  # addi x0, x0, 0

# Register allocation in dump code:
#   x13=status tmp, x14=ptr, x15=UART addr, x16=ptr end,
#   x17=tx_busy mask, x18=step, x19=word to send,
#   x20=MMIO base, x21=LEDG, x22=CYCLE addr, x23=saves start, x24=saves end
INFRA_DATA = [
    (INFRA_WBASE + 0, 0x00000410, "UART TX/status addr      -> x15"),
    (INFRA_WBASE + 1, 0x00000200, "tx_busy mask (bit 9)     -> x17"),
    (INFRA_WBASE + 2, 0x00000004, "step = 4                 -> x18"),
    (INFRA_WBASE + 3, 0x00000400, "MMIO base 0x400          -> x20"),
    (INFRA_WBASE + 4, 0x000001FF, "LEDG all-on 0x1FF        -> x21"),
    (INFRA_WBASE + 5, SAVES_BBASE, f"saves start byte 0x{SAVES_BBASE:03X} -> x23"),
    (INFRA_WBASE + 6, SAVES_BEND,  f"saves end   byte 0x{SAVES_BEND:03X} -> x24"),
]

INSTRUCTION = {
 "lui": {
  "format": "U",
  "opcode": "0110111",
  "funct3": "",
  "funct7": ""
 },
 "auipc": {
  "format": "U",
  "opcode": "0010111",
  "funct3": "",
  "funct7": ""
 },
 "jal": {
  "format": "J",
  "opcode": "1101111",
  "funct3": "",
  "funct7": ""
 },
 "jalr": {
  "format": "I",
  "opcode": "1100111",
  "funct3": "000",
  "funct7": ""
 },
 "beq": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "000",
  "funct7": ""
 },
 "bne": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "001",
  "funct7": ""
 },
 "blt": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "100",
  "funct7": ""
 },
 "bge": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "101",
  "funct7": ""
 },
 "bltu": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "110",
  "funct7": ""
 },
 "bgeu": {
  "format": "B",
  "opcode": "1100011",
  "funct3": "111",
  "funct7": ""
 },
 "lb": {
  "format": "I",
  "opcode": "0000011",
  "funct3": "000",
  "funct7": ""
 },
 "lh": {
  "format": "I",
  "opcode": "0000011",
  "funct3": "001",
  "funct7": ""
 },
 "lw": {
  "format": "I",
  "opcode": "0000011",
  "funct3": "010",
  "funct7": ""
 },
 "lbu": {
  "format": "I",
  "opcode": "0000011",
  "funct3": "100",
  "funct7": ""
 },
 "lhu": {
  "format": "I",
  "opcode": "0000011",
  "funct3": "101",
  "funct7": ""
 },
 "sb": {
  "format": "S",
  "opcode": "0100011",
  "funct3": "000",
  "funct7": ""
 },
 "sh": {
  "format": "S",
  "opcode": "0100011",
  "funct3": "001",
  "funct7": ""
 },
 "sw": {
  "format": "S",
  "opcode": "0100011",
  "funct3": "010",
  "funct7": ""
 },
 "addi": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "000",
  "funct7": ""
 },
 "slti": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "010",
  "funct7": ""
 },
 "sltiu": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "011",
  "funct7": ""
 },
 "xori": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "100",
  "funct7": ""
 },
 "ori": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "110",
  "funct7": ""
 },
 "andi": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "111",
  "funct7": ""
 },
 "slli": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "001",
  "funct7": "0000000"
 },
 "srli": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "101",
  "funct7": "0000000"
 },
 "srai": {
  "format": "I",
  "opcode": "0010011",
  "funct3": "101",
  "funct7": "0100000"
 },
 "add": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "000",
  "funct7": "0000000"
 },
 "sub": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "000",
  "funct7": "0100000"
 },
 "sll": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "001",
  "funct7": "0000000"
 },
 "slt": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "010",
  "funct7": "0000000"
 },
 "sltu": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "011",
  "funct7": "0000000"
 },
 "xor": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "100",
  "funct7": "0000000"
 },
 "srl": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "101",
  "funct7": "0000000"
 },
 "sra": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "101",
  "funct7": "0100000"
 },
 "or": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "110",
  "funct7": "0000000"
 },
 "and": {
  "format": "R",
  "opcode": "0110011",
  "funct3": "111",
  "funct7": "0000000"
 },
}


# creates the file and writes the header
def create_file(file_name):
	header = ("DEPTH = 256;            -- The size of memory in words\n"
	          "WIDTH = 32;             -- The size of data in bits\n"
	          "ADDRESS_RADIX = HEX;    -- The radix for address values\n"
	          "DATA_RADIX = HEX;       -- The radix for data values\n"
	          "CONTENT                 -- Start of (address: data pairs)\n"
	          "BEGIN\n\n")

	with open(file_name, "w") as file:
		file.write(header)


# reads the instruction file and returns a list containing the instructions (its lines)
def read_file(file_name):
	try:
		with open(file_name, "r") as file:
			instructions = file.readlines()
		if not instructions:
			raise Exception("Empty file or no instructions found.")
	except Exception as e:
		print(f"Error reading instructions from '{file_name}': {e}")
		exit(1)

	return instructions


# writes one 32-bit word to the file ({index} : {hex_word};  -- {instruction})
def write_instruction(file_name, index, hex_word, instr):
	with open(file_name, "a") as file:
		file.write(f"{index} : {hex_word};  -- {instr.rstrip()}\n")


# appends a final "END;" string to the file
def end_file(file_name):
	with open(file_name, "a") as file:
		file.write("END;")

def negative_to_twos_complement(negative_binary):
	abs_binary = negative_binary
	ones_complement = ''.join('1' if bit == '0' else '0' for bit in abs_binary)

	twos_complement = ''
	carry = 1

	for bit in reversed(ones_complement):
		if carry == 1:
			if bit == '0':
				twos_complement = '1' + twos_complement
				carry = 0
			else:
				twos_complement = '0' + twos_complement
				carry = 1
		else:
			twos_complement = bit + twos_complement

	return twos_complement

# converts a decimal value to a signed binary value (sign bit is the first bit)
def sbin(value):
	binary = bin(int(value))

	if (binary[0] == '-'):
		return '1' + negative_to_twos_complement(binary[3:])

	else:
		return '0' + binary[2:]


# pads a binary value with 0s or 1s to a certain length (same as zfill() but extends the sign bit)
def sfill(value, length):
	if (len(value) < length):
		if (value[0] == '1'):
			return (length - len(value)) * '1' + value
		else:
			return (length - len(value)) * '0' + value
	else:
		return value


def check_register(register):
	if (register[0] != "x" or int(register[1:]) < 0 or int(register[1:]) > 31):
		raise Exception("Invalid register.")


def check_instruction(instruction):
	if (instruction not in INSTRUCTION):
		raise Exception("Instruction not found.")


def check_immediate(immediate, length):
	if (int(immediate) > 2**(length - 1) - 1 or int(immediate) < -2**(length - 1) + 1):
		raise Exception("Immediate value out of range.")


# translates an instruction to binary (assembly to machine code)
def translate_instruction(instruction):
	try:
		instr = instruction.split(" ")[0]

		check_instruction(instr)

		opcode = INSTRUCTION[instr]["opcode"]
		funct3 = INSTRUCTION[instr]["funct3"]
		funct7 = INSTRUCTION[instr]["funct7"]

		if (INSTRUCTION[instr]["format"] not in ["S", "B"]):
			rd = instruction.split(" ")[1].split(",")[0]

			check_register(rd)

			rd = bin(int(rd[1:]))[2:].zfill(5)

		if (INSTRUCTION[instr]["format"] == "U"):
			imm = instruction.split(" ")[1].split(",")[1]

			check_immediate(imm, 20)

			imm = sfill(sbin(imm)[0:20], 20)

			binary = imm + rd + opcode

		elif (INSTRUCTION[instr]["format"] == "J"):
			imm = instruction.split(" ")[1].split(",")[1]

			check_immediate(imm, 20)

			imm = sfill(sbin(imm)[0:20], 21)
			imm = imm[::-1]

			bit20 = imm[20]
			bit10to1 = (imm[1:11])[::-1]
			bit11 = imm[11]
			bit19to12 = (imm[12:20])[::-1]

			imm = sfill((bit20 + bit10to1 + bit11 + bit19to12), 20)

			binary = imm + rd + opcode

		elif (
		  INSTRUCTION[instr]["format"] == "I"
		  and instr not in ["lw", "lb", "lh", "lbu", "lhu", "slli", "srli", "srai"]):
			rs1 = instruction.split(" ")[1].split(",")[1]

			check_register(rs1)

			rs1 = bin(int(rs1[1:]))[2:].zfill(5)

			imm = instruction.split(" ")[1].split(",")[2]

			check_immediate(imm, 12)

			imm = sfill(sbin(imm)[0:12], 12)

			binary = imm + rs1 + funct3 + rd + opcode

		elif (INSTRUCTION[instr]["format"] == "B"):
			rs1 = instruction.split(" ")[1].split(",")[0]
			rs2 = instruction.split(" ")[1].split(",")[1]

			check_register(rs1)
			check_register(rs2)

			rs1 = bin(int(rs1[1:]))[2:].zfill(5)
			rs2 = bin(int(rs2[1:]))[2:].zfill(5)

			imm = instruction.split(" ")[1].split(",")[2]

			check_immediate(imm, 12)

			imm = sfill(sbin(imm)[0:12], 13)
			imm = imm[::-1]

			bit12 = imm[12]
			bit10to5 = (imm[5:11])[::-1]
			bit4to1 = (imm[1:5])[::-1]
			bit11 = imm[11]

			binary = sfill((bit12 + bit10to5), 7) + rs2 + rs1 + funct3 + sfill(
			 (bit4to1 + bit11), 5) + opcode

		elif (instr in ["lb", "lh", "lw", "lbu", "lhu"]):
			rs1 = instruction.split(" ")[1].split(",")[1]
			rs1 = rs1.split("(")[1].split(")")[0]

			check_register(rs1)

			rs1 = bin(int(rs1[1:]))[2:].zfill(5)

			imm = instruction.split(" ")[1].split(",")[1]
			imm = imm.split("(")[0]

			check_immediate(imm, 12)

			imm = sfill(sbin(imm)[0:12], 12)

			binary = imm + rs1 + funct3 + rd + opcode

		elif (INSTRUCTION[instr]["format"] == "S"):
			rs2 = instruction.split(" ")[1].split(",")[0]
			rs1 = instruction.split(" ")[1].split(",")[1]
			rs1 = rs1.split("(")[1].split(")")[0]

			check_register(rs1)
			check_register(rs2)

			rs2 = bin(int(rs2[1:]))[2:].zfill(5)
			rs1 = bin(int(rs1[1:]))[2:].zfill(5)

			imm = instruction.split(" ")[1].split(",")[1]
			imm = imm.split("(")[0]

			check_immediate(imm, 12)

			imm = sfill(sbin(imm)[0:12], 12)
			imm = imm[::-1]

			bit11to5 = (imm[5:12])[::-1]
			bit4to0 = (imm[0:5])[::-1]

			binary = sfill(bit11to5, 7) + rs2 + rs1 + funct3 + sfill(bit4to0, 5) + opcode

		elif (INSTRUCTION[instr]["format"] == "R"):
			rs1 = instruction.split(" ")[1].split(",")[1]
			rs2 = instruction.split(" ")[1].split(",")[2]

			check_register(rs1)
			check_register(rs2)

			rs1 = bin(int(rs1[1:]))[2:].zfill(5)
			rs2 = bin(int(rs2[1:]))[2:].zfill(5)

			binary = funct7 + rs2 + rs1 + funct3 + rd + opcode

		elif (instr in ["slli", "srli", "srai"]):
			rs1 = instruction.split(" ")[1].split(",")[1]

			check_register(rs1)

			rs1 = bin(int(rs1[1:]))[2:].zfill(5)

			shamt = instruction.split(" ")[1].split(",")[2]
			shamt = sfill(sbin(shamt)[0:6], 5)

			binary = funct7 + shamt + rs1 + funct3 + rd + opcode

	except Exception as e:
		print(f"Error translating instruction '{instruction.rstrip()}': {e}")
		return None

	return binary


def build_dump_code():
	"""Returns the dump code (Parts 2-8) as a list of (assembly, comment).

	Designed to be placed at DUMP_START (word address 0x80).
	All internal branch offsets are PC-relative and position-independent:
	  POLL back  : beq x0,x0,-12
	  POLL fwd   : beq x13,x0,8
	  Loop back  : beq x0,x0,-32
	  Loop done  : beq x14,x16,8  (or beq x14,x0,8 for cycle poll-only)
	"""
	b = INFRA_BBASE  # byte base for infrastructure lw offsets (0x200)
	code = []

	# Part 2: save x1-x8 to dmem word addr 0x72-0x79 (byte 0x1C8-0x1E4)
	for i in range(1, 9):
		code.append((f"sw x{i},{SAVES_BBASE + (i-1)*4}(x0)",
		             f"x{i} -> dmem[0x{SAVES_WBASE + i - 1:02X}]"))

	# Part 3: load infrastructure constants
	code.append((f"lw x15,{b+0}(x0)",  "x15 = 0x410  UART TX/status"))
	code.append((f"lw x17,{b+4}(x0)",  "x17 = 0x200  tx_busy mask"))
	code.append((f"lw x18,{b+8}(x0)",  "x18 = 4      step"))
	code.append((f"lw x20,{b+12}(x0)", "x20 = 0x400  MMIO base"))
	code.append((f"lw x21,{b+16}(x0)", "x21 = 0x1FF  LEDG all-on"))
	code.append((f"lw x23,{b+20}(x0)", "x23 = 0x80   saves start"))
	code.append((f"lw x24,{b+24}(x0)", "x24 = 0xFC   saves end"))

	# Part 4: send cycle count (MMIO 0x414)
	code.append(("add x22,x15,x18",  "x22 = 0x414  CYCLE MMIO"))
	code.append(("lw x19,0(x22)",    "x19 = cycle count"))
	code.append(("lw x13,0(x15)",    "POLL: read UART status"))
	code.append(("and x13,x13,x17",  "      isolate tx_busy"))
	code.append(("beq x13,x0,8",     "      free? -> SEND"))
	code.append(("beq x0,x0,-12",    "      busy? -> POLL"))
	code.append(("sw x19,0(x15)",    "SEND  cycles (4 bytes hw)"))

	# Part 5: loop — send x1-x31 from dmem[0x80..0xF8]
	code.append(("add x14,x23,x0",  "x14 = 0x80  saves start ptr"))
	code.append(("add x16,x24,x0",  "x16 = 0xFC  saves end ptr"))
	# REG_LOOP:
	code.append(("lw x19,0(x14)",   "REG_LOOP: load saved reg"))
	code.append(("lw x13,0(x15)",   "POLL"))
	code.append(("and x13,x13,x17", "      isolate tx_busy"))
	code.append(("beq x13,x0,8",    "      free? -> SEND"))
	code.append(("beq x0,x0,-12",   "      busy? -> POLL"))
	code.append(("sw x19,0(x15)",   "SEND  reg (4 bytes hw)"))
	code.append(("add x14,x14,x18", "      ptr += 4"))
	code.append(("beq x14,x16,8",   "      done? skip loop-back"))
	code.append(("beq x0,x0,-32",   "      -> REG_LOOP"))

	# Part 6: loop — send dmem[0x000..0x07C]
	code.append(("add x14,x0,x0",   "x14 = 0     mem start ptr"))
	code.append(("add x16,x23,x0",  "x16 = 0x80  mem end ptr"))
	# MEM_LOOP:
	code.append(("lw x19,0(x14)",   "MEM_LOOP: load mem word"))
	code.append(("lw x13,0(x15)",   "POLL"))
	code.append(("and x13,x13,x17", "      isolate tx_busy"))
	code.append(("beq x13,x0,8",    "      free? -> SEND"))
	code.append(("beq x0,x0,-12",   "      busy? -> POLL"))
	code.append(("sw x19,0(x15)",   "SEND  mem word (4 bytes hw)"))
	code.append(("add x14,x14,x18", "      ptr += 4"))
	code.append(("beq x14,x16,8",   "      done? skip loop-back"))
	code.append(("beq x0,x0,-32",   "      -> MEM_LOOP"))

	# Part 7: light all green LEDs
	code.append(("sw x21,12(x20)", "LEDG[8:0] = 0x1FF  (addr 0x40C)"))

	# Part 8: halt
	code.append(("beq x0,x0,0", "halt: infinite loop"))

	return code


def main_normal(src):
	"""Original behavior: <src> -> instruction.mif + program.hex."""
	instructions = read_file(src)
	create_file("instruction.mif")

	hex_words = []

	for i, instruction in enumerate(instructions):
		binary = translate_instruction(instruction)
		if binary:
			hex_word = f"{int(binary, 2):08X}"
			index = f"{i:03X}"
			write_instruction("instruction.mif", index, hex_word, instruction)
			hex_words.append(hex_word)
		else:
			line = i + 1
			print(f"Translation failed on line {line}.\n")
			os.remove("instruction.mif")
			exit(2)

	end_file("instruction.mif")

	with open("program.hex", "w") as hex_file:
		for word in hex_words:
			hex_file.write(f"{word}\n")

	print("Assembly to machine code translation complete.\n")
	print(f"  instruction.mif : {len(hex_words)} instruction(s)")
	print(f"  program.hex     : {len(hex_words)} instruction(s)")


def main_dump(src):
	"""--dump mode: user code + jump + dump at 0x80 -> quartus/instruction.mif + quartus/data.mif."""
	script_dir = os.path.dirname(os.path.abspath(__file__))
	instr_path = os.path.join(script_dir, "instruction.mif")
	data_path  = os.path.join(script_dir, "data.mif")

	# ---- Assemble user instructions ----------------------------------------
	raw_lines = read_file(src)
	user_encoded = []
	for lineno, line in enumerate(raw_lines, 1):
		instr = line.strip()
		if not instr:
			continue
		binary = translate_instruction(instr)
		if binary is None:
			print(f"Translation failed on line {lineno}: '{instr}'")
			exit(2)
		user_encoded.append((f"{int(binary, 2):08X}", instr))

	n_user = len(user_encoded)
	if n_user >= DUMP_START:
		print(f"Erro: {n_user} instrucoes do usuario excedem o limite de "
		      f"{DUMP_START - 1} (dump reside a partir de 0x{DUMP_START:02X}).")
		exit(3)

	# ---- Build beq user_end -> DUMP_START ----------------------------------
	beq_word_addr  = n_user
	beq_byte_offset = (DUMP_START - beq_word_addr) * 4
	beq_instr = f"beq x0,x0,{beq_byte_offset}"
	beq_bin   = translate_instruction(beq_instr)
	if beq_bin is None:
		print(f"Erro interno: nao foi possivel codificar '{beq_instr}'")
		exit(4)
	beq_hex = f"{int(beq_bin, 2):08X}"

	# ---- Encode dump code --------------------------------------------------
	dump_raw = build_dump_code()
	dump_encoded = []
	for asm, comment in dump_raw:
		binary = translate_instruction(asm)
		if binary is None:
			print(f"Erro interno no dump: nao foi possivel codificar '{asm}'")
			exit(4)
		dump_encoded.append((f"{int(binary, 2):08X}", asm, comment))

	nop_start  = beq_word_addr + 1
	nop_end    = DUMP_START - 1
	has_nop    = nop_start <= nop_end
	dump_end   = DUMP_START + len(dump_encoded) - 1

	# ---- Write instruction.mif ---------------------------------------------
	with open(instr_path, "w") as f:
		f.write("-- ============================================================\n")
		f.write("-- instruction.mif — gerado por: python assembler.py --dump\n")
		f.write("--\n")
		f.write(f"-- 0x000..0x{n_user-1:03X} : codigo do usuario ({n_user} instrucao(oes))\n")
		f.write(f"-- 0x{beq_word_addr:03X}       : beq x0,x0 -> 0x{DUMP_START:02X}  (desvio para dump)\n")
		if has_nop:
			f.write(f"-- 0x{nop_start:03X}..0x{nop_end:03X} : NOP (addi x0,x0,0)\n")
		f.write(f"-- 0x{DUMP_START:03X}..0x{dump_end:03X} : dump serial (Parts 2-8)\n")
		f.write("-- ============================================================\n")
		f.write("DEPTH = 256;\n")
		f.write("WIDTH = 32;\n")
		f.write("ADDRESS_RADIX = HEX;\n")
		f.write("DATA_RADIX = HEX;\n")
		f.write("CONTENT\nBEGIN\n\n")

		for i, (hex_word, instr) in enumerate(user_encoded):
			f.write(f"{i:03X} : {hex_word};  -- {instr}\n")

		f.write(f"{beq_word_addr:03X} : {beq_hex};  -- {beq_instr}  [-> dump @ 0x{DUMP_START:02X}]\n")

		if has_nop:
			f.write(f"[{nop_start:03X}..{nop_end:03X}] : {NOP_WORD};  -- nop\n")

		f.write("\n")
		for i, (hex_word, asm, comment) in enumerate(dump_encoded):
			f.write(f"{DUMP_START + i:03X} : {hex_word};  -- {asm:<24}  {comment}\n")

		if dump_end < 0xFF:
			f.write(f"[{dump_end+1:03X}..0FF] : {NOP_WORD};  -- nop\n")

		f.write("\nEND;\n")

	# ---- Write data.mif ----------------------------------------------------
	with open(data_path, "w") as f:
		f.write("-- ============================================================\n")
		f.write("-- data.mif — gerado por: python assembler.py --dump\n")
		f.write("--\n")
		f.write("-- 0x000..0x01F : area do usuario  (byte 0x000..0x07C)\n")
		f.write(f"-- 0x{SAVES_WBASE:03X}..0x{SAVES_WBASE+7:03X} : saves x1-x8   (byte 0x{SAVES_BBASE:03X}..0x{SAVES_BBASE+28:03X}, escritos em runtime)\n")
		f.write(f"-- 0x{INFRA_WBASE:03X}..0x{INFRA_WBASE + len(INFRA_DATA) - 1:03X} : constantes de infraestrutura (byte 0x{INFRA_BBASE:03X}..)\n")
		f.write("-- ============================================================\n")
		f.write("DEPTH = 256;\n")
		f.write("WIDTH = 32;\n")
		f.write("ADDRESS_RADIX = HEX;\n")
		f.write("DATA_RADIX = HEX;\n")
		f.write("CONTENT\nBEGIN\n\n")
		f.write("[000..0FF] : 00000000;  -- zeros por padrao\n\n")
		for word_addr, value, desc in INFRA_DATA:
			f.write(f"{word_addr:03X} : {value:08X};  -- {desc}\n")
		f.write("\nEND;\n")

	# ---- Summary -----------------------------------------------------------
	print("Geracao com --dump concluida.\n")
	print(f"  {instr_path}")
	print(f"    {n_user} instrucao(oes) do usuario  (0x000..0x{n_user-1:03X})")
	print(f"    beq -> dump em 0x{beq_word_addr:03X}  (offset {beq_byte_offset} bytes)")
	if has_nop:
		print(f"    NOP fill  (0x{nop_start:03X}..0x{nop_end:03X})")
	print(f"    dump code (0x{DUMP_START:03X}..0x{dump_end:03X},"
	      f" {len(dump_encoded)} instrucoes)")
	print(f"\n  {data_path}")
	print(f"    zeros + constantes em"
	      f" 0x{INFRA_WBASE:03X}..0x{INFRA_WBASE + len(INFRA_DATA) - 1:03X}")


def main():
	parser = argparse.ArgumentParser(
		description="Assembler RV32I: converte um arquivo .asm em instruction.mif.",
	)
	parser.add_argument(
		"file",
		nargs="?",
		default="instructions.txt",
		help="Arquivo de entrada com as instrucoes (padrao: instructions.txt).",
	)
	parser.add_argument(
		"--dump",
		action="store_true",
		help=(
			"Anexa o codigo de dump serial (Parts 2-8) a partir do endereco 0x80 "
			"da memoria de instrucoes, precedido por um beq incondicional ao fim do "
			"codigo do usuario. Gera quartus/instruction.mif e quartus/data.mif."
		),
	)
	args = parser.parse_args()

	if args.dump:
		main_dump(args.file)
	else:
		main_normal(args.file)


if __name__ == "__main__":
	main()
