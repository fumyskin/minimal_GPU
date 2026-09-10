# TERMINI E CONCETTI

1) **fixed-width instruction** = a computer architecture design where every machine language instruction processed by the CPU is the exact same size (length in bits), regardless of its complexity or function.

For example, in a 32-bit fixed-width architecture, a simple command like "add two registers" takes exactly 32 bits of memory, and a more complex command like "load a value from memory into a register" also takes exactly 32 bits.

This design is a hallmark of RISC (Reduced Instruction Set Computer) architectures.

2) **Q-format** : The Q format is usually written as Qm.n:  
    m: The number of bits dedicated to the integer (whole number) part.  
    n: The number of bits dedicated to the fractional part.  
    (Implicit): One extra bit is usually reserved at the front for the sign (positive/negative).