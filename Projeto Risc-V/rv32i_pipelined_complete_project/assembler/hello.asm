lw x1,0(x0)
lw x2,4(x0)
xor x3,x1,x2
lw x4,8(x0)
sw x3,8(x4)
beq x0,x0,0