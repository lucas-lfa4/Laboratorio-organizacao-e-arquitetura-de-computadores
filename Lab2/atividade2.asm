lw x10, val_a
lw x11, val_b
lw x12, val_m

bge x11, x12, senao

add x12, x10, x11
beq x0, x0, fim

senao:
sub x12, x10, x11

fim:
sw x12, val_m
halt

val_a: .word 6
val_b: .word 15
val_m: .word 16
