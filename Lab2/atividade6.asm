main:
    addi x11, x0, 1
    sb   x11, 1029(x0)

loop:
    addi x12, x0, 128
    beq  x11, x12, fim

espera_pressionar:
    lb   x10, 1026(x0)
    andi x10, x10, 0x1
    beq  x10, x0, espera_pressionar

espera_soltar:
    lb   x10, 1026(x0)
    andi x10, x10, 0x1
    bne  x10, x0, espera_soltar

    add  x11, x11, x11
    sb   x11, 1029(x0)

    jal  x0, loop

fim:
    halt
