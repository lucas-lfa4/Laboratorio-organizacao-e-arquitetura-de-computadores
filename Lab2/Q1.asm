lw x10, a
lw x11, b
lw x12, m

addi x12, x10, 0

main:
	slt x1, x11, x12
	beq x1, x0, fim
	add x12, x10, x11
	sw x12, m
	halt

fim:
	sw x12, m
	halt

a: .word 0xE
b: .word 0x7
m: .word 0x0000

