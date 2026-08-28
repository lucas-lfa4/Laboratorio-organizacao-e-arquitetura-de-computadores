lw x20, val_g
lw x21, val_h
lw x22, val_i
lw x23, val_j

bne x22, x23, senao

add x19, x20, x21
beq x0, x0, fim

senao:
sub x19, x20, x21

fim:
sw x19, val_f
halt

val_f: .word 0
val_g: .word 10
val_h: .word 5
val_i: .word 2
val_j: .word 2
