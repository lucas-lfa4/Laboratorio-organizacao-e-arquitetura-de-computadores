#!/usr/bin/env python3
"""
serial_dump.py
Lê 164 bytes da interface serial RS-232 do FPGA e exibe o estado do processador.

Protocolo esperado (164 bytes = 41 palavras de 32 bits):
  Bytes   0 –   3 :  Contador de ciclos de clock (uint32, little-endian)
  Bytes   4 –  35 :  Registradores x1 – x8        (8 × uint32, little-endian)
  Bytes  36 – 163 :  Memória 0x000 – 0x07C        (32 × uint32, little-endian)

Protocolo de transmissão (UART MMIO):
  O programa no FPGA executa uma instrução SW para o endereço UART (0x410)
  por valor a transmitir. O hardware do MMIO divide automaticamente a palavra
  de 32 bits em 4 bytes e os envia em sequência (little-endian):
    byte 0 = bits  7:0  (primeiro a chegar)
    byte 1 = bits 15:8
    byte 2 = bits 23:16
    byte 3 = bits 31:24  (último a chegar)

  Os 4 bytes de cada palavra chegam em rajada (back-to-back a 9600 baud,
  ~4 ms por palavra). Entre palavras há uma pausa de polling de software
  (~alguns µs a 10 MHz). O timeout deve ser calibrado para o número total
  de palavras × tempo por palavra + margem de polling.

  Tempo estimado de transmissão completa (41 palavras × ~4 ms): ≈ 164 ms.
"""

import argparse
import struct
import sys
import textwrap
import threading
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError:
    sys.exit("Erro: pyserial nao encontrado. Execute: pip install pyserial")

# ---------------------------------------------------------------------------
# Debug — altere para False para desativar
# ---------------------------------------------------------------------------
DEBUG_HEX = False   # imprime cada byte recebido em hex em tempo real

# ---------------------------------------------------------------------------
# Constantes do protocolo
# ---------------------------------------------------------------------------
CYCLE_WORDS   = 1            # 1 palavra  = 4 bytes
REG_COUNT     = 8            # x1 – x8
REG_WORDS     = REG_COUNT    # 8 palavras  = 32 bytes
MEM_WORDS     = 32           # 0x000 – 0x07C (word-addressed, passo 4)
                             # 32 palavras = 128 bytes

TOTAL_WORDS   = CYCLE_WORDS + REG_WORDS + MEM_WORDS  # 41
TOTAL_BYTES   = TOTAL_WORDS * 4                       # 164 bytes

# Offsets em bytes dentro do stream
CYCLE_OFFSET  = 0
REG_OFFSET    = CYCLE_WORDS  * 4          # 4
MEM_OFFSET    = REG_OFFSET   + REG_WORDS * 4  # 36

ABI_NAMES = [
    "zero",                          # x0 (não transmitido)
    "ra",  "sp",  "gp",  "tp",       # x1 – x4
    "t0",  "t1",  "t2",              # x5 – x7
    "s0",  "s1",                     # x8 – x9
    "a0",  "a1",  "a2",  "a3",       # x10 – x13
    "a4",  "a5",  "a6",  "a7",       # x14 – x17
    "s2",  "s3",  "s4",  "s5",       # x18 – x21
    "s6",  "s7",  "s8",  "s9",       # x22 – x25
    "s10", "s11",                    # x26 – x27
    "t3",  "t4",  "t5",  "t6",       # x28 – x31
]

# ---------------------------------------------------------------------------
# Recepção
# ---------------------------------------------------------------------------

class _SerialTimeout(Exception):
    """Sinaliza que a leitura serial esgotou o timeout antes do total esperado."""


def receive_dump(port: str, baud: int, timeout: float) -> bytes:
    """
    Recebe exatamente TOTAL_BYTES bytes da porta serial.

    Os bytes chegam em grupos de 4 (uma palavra por SW do FPGA).
    O loop de leitura acumula chunks até atingir o total esperado,
    reportando progresso por palavra completa recebida.

    A porta é fechada explicitamente no bloco finally antes de qualquer
    sys.exit() ser chamado em main(), garantindo a liberação do handle
    do sistema operacional em qualquer cenário de saída.
    """
    print(f"Aguardando dados em {port} @ {baud} baud ...")
    print(f"Esperando {TOTAL_WORDS} palavras ({TOTAL_BYTES} bytes)\n")

    ser = serial.Serial(port, baud, timeout=timeout)
    try:
        data = bytearray()
        last_reported_word = -1

        while len(data) < TOTAL_BYTES:
            chunk = ser.read(TOTAL_BYTES - len(data))
            if not chunk:
                words_received = len(data) // 4
                raise _SerialTimeout(
                    f"\nTimeout: recebidas {words_received}/{TOTAL_WORDS} palavras "
                    f"({len(data)}/{TOTAL_BYTES} bytes) sem mais dados.\n"
                    "Verifique a conexao e o programa no FPGA."
                )
            data.extend(chunk)

            words_now = len(data) // 4
            if words_now > last_reported_word:
                _print_progress(words_now, TOTAL_WORDS)
                last_reported_word = words_now

    finally:
        # Garante fechamento mesmo em timeout, KeyboardInterrupt ou exceção.
        ser.close()

    print()  # quebra de linha após a barra de progresso
    return bytes(data)


def debug_hex_monitor(port: str, baud: int) -> None:
    """
    Modo monitor: imprime em hex todos os bytes recebidos na serial.
    Pressione 'q' para encerrar.
    """
    stop = threading.Event()

    def _wait_q() -> None:
        try:
            import msvcrt  # Windows nativo
            while not stop.is_set():
                if msvcrt.kbhit() and msvcrt.getwch().lower() == 'q':
                    stop.set()
        except ImportError:
            import select as sel
            import termios
            import tty
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setraw(fd)
                while not stop.is_set():
                    if sel.select([sys.stdin], [], [], 0.1)[0]:
                        if sys.stdin.read(1).lower() == 'q':
                            stop.set()
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)

    threading.Thread(target=_wait_q, daemon=True).start()

    ser = serial.Serial(port, baud, timeout=0.5)
    try:
        while not stop.is_set():
            chunk = ser.read(64)
            if chunk:
                print(" ".join(f"0x{b:02X}" for b in chunk), end=" ", flush=True)
    finally:
        ser.close()
        stop.set()
    print()


def _print_progress(done: int, total: int) -> None:
    pct   = done / total
    bar   = int(pct * 30)
    label = _progress_label(done)
    print(
        f"\r  [{('#' * bar):<30}] {done:2d}/{total} palavras  {label:<28}",
        end="", flush=True,
    )


def _progress_label(word_idx: int) -> str:
    """Descreve qual campo está sendo recebido com base no índice da palavra."""
    if word_idx <= CYCLE_WORDS:
        return "ciclos"
    elif word_idx <= CYCLE_WORDS + REG_WORDS:
        reg = word_idx - CYCLE_WORDS
        abi = ABI_NAMES[reg] if reg < len(ABI_NAMES) else f"x{reg}"
        return f"x{reg} ({abi})"
    elif word_idx <= TOTAL_WORDS:
        mem_word = word_idx - CYCLE_WORDS - REG_WORDS - 1
        return f"mem[0x{mem_word * 4:03X}]"
    return ""


# ---------------------------------------------------------------------------
# Interpretação
# ---------------------------------------------------------------------------

def parse_dump(data: bytes) -> dict:
    """
    Interpreta o stream de 164 bytes como:
      - 1 palavra : contador de ciclos
      - 8 palavras: registradores x1–x8
      - 32 palavras: memória 0x000–0x07C
    Cada palavra foi transmitida pelo hardware UART como 4 bytes little-endian
    a partir de uma única instrução SW no FPGA.
    """
    cycle = struct.unpack_from("<I", data, CYCLE_OFFSET)[0]

    regs = {}
    for i in range(1, REG_COUNT + 1):
        offset = REG_OFFSET + (i - 1) * 4
        regs[i] = struct.unpack_from("<I", data, offset)[0]

    mem = []
    for w in range(MEM_WORDS):
        offset = MEM_OFFSET + w * 4
        mem.append(struct.unpack_from("<I", data, offset)[0])

    return {"cycle": cycle, "regs": regs, "mem": mem}


# ---------------------------------------------------------------------------
# Formatação
# ---------------------------------------------------------------------------

def format_report(parsed: dict, timestamp: str) -> str:
    cycle = parsed["cycle"]
    regs  = parsed["regs"]
    mem   = parsed["mem"]

    lines = []
    sep   = "=" * 62

    lines.append(sep)
    lines.append("  RV32I Pipeline Dump")
    lines.append(f"  {timestamp}")
    lines.append(sep)

    # --- Contador de ciclos ---
    lines.append("")
    lines.append("[ Contador de Ciclos ]")
    lines.append(f"  cycles = {cycle:10d}  (0x{cycle:08X})")

    # --- Registradores ---
    lines.append("")
    lines.append("[ Registradores x1 – x8 ]")
    lines.append(f"  {'Reg':<6} {'ABI':<6} {'Hex':>10}  {'Dec (uint)':>12}  {'Dec (int)':>12}")
    lines.append("  " + "-" * 54)
    for i in range(1, REG_COUNT + 1):
        val    = regs[i]
        signed = struct.unpack("<i", struct.pack("<I", val))[0]
        abi    = ABI_NAMES[i]
        lines.append(
            f"  x{i:<5d} {abi:<6} 0x{val:08X}  {val:>12d}  {signed:>12d}"
        )

    # --- Memória ---
    lines.append("")
    lines.append("[ Memória de Dados  0x000 – 0x07C ]")
    lines.append(f"  {'Endereço':<12} {'Hex':>10}  {'Dec (uint)':>12}  {'Dec (int)':>12}")
    lines.append("  " + "-" * 54)
    for w, val in enumerate(mem):
        addr   = w * 4
        signed = struct.unpack("<i", struct.pack("<I", val))[0]
        lines.append(
            f"  0x{addr:03X}        0x{val:08X}  {val:>12d}  {signed:>12d}"
        )

    lines.append("")
    lines.append(sep)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Entrada / saída
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Recebe dump de estado do RV32I via serial e formata a saida.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Exemplos:
              python serial_dump.py COM3
              python serial_dump.py /dev/ttyUSB0 --baud 115200
              python serial_dump.py COM3 --out meu_dump.txt

            Protocolo:
              O FPGA transmite 41 palavras de 32 bits (164 bytes) via UART MMIO.
              Cada SW para 0x410 dispara automaticamente o envio dos 4 bytes da
              palavra em ordem little-endian. O script aguarda os 164 bytes e
              os interpreta como: ciclos (1 palavra) + x1-x8 (8 palavras)
              + mem[0x000-0x07C] (32 palavras).
        """),
    )
    parser.add_argument("port",
                        help="Porta serial (ex: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud",    type=int,   default=9600,
                        help="Baud rate (padrao: 9600)")
    parser.add_argument("--timeout", type=float, default=10.0,
                        help="Timeout em segundos sem novos dados (padrao: 10). "
                             "Cada palavra leva ~4 ms a 9600 baud; "
                             "41 palavras = ~164 ms no total.")
    parser.add_argument("--out",                 default="dump.txt",
                        help="Arquivo de saida (padrao: dump.txt)")
    args = parser.parse_args()

    if DEBUG_HEX:
        try:
            debug_hex_monitor(args.port, args.baud)
        except KeyboardInterrupt:
            pass
        return

    try:
        raw = receive_dump(args.port, args.baud, args.timeout)
    except _SerialTimeout as e:
        # Porta já fechada pelo finally de receive_dump antes de chegar aqui.
        sys.exit(str(e))
    except KeyboardInterrupt:
        print("\nInterrompido pelo usuario.")
        sys.exit(1)

    parsed = parse_dump(raw)

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    report    = format_report(parsed, timestamp)

    print(report)

    out_path = Path(args.out)
    out_path.write_text(report, encoding="utf-8")
    print(f"\nDump salvo em: {out_path.resolve()}")


if __name__ == "__main__":
    main()
