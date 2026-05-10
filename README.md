# UART-Transceiver
EEE 333 Lab 3

A UART transmitter and receiver in SystemVerilog. Sends a byte out serially
with start/stop bits, then receives it back and shows the result on two
hex displays.

## What's in it

- **UART_tx** — three-state FSM (RS / LD / TX). Loads the byte into a
  10-bit buffer (start, 8 data, stop) and shifts it out one bit per
  baud tick.
- **UART_rx** — three-state FSM (RST / DET / REC). Waits for a start bit,
  samples 10 bits per baud tick, then pulses `rx_ready` when a full byte
  is received.
- **BAUD_rate_gen** — parameterized counter that produces a one-cycle
  `baud_tick` at the configured rate.
- **Hex7Seg** — 4-bit hex to 7-segment decoder for the FPGA hex displays.
- **UART_pv** — top-level wrapper for the prototype board, loops TX into
  RX and displays the received byte.

## Files

- `Lab3.sv` — all modules + testbench (`UART_TB`)

## How to simulate

Open in ModelSim/Questa, compile `Lab3.sv`, run `UART_TB`. Testbench sends
two bytes (0x20 and 0x45), loops TX into RX, and prints the received bytes.

## Waveform

[insert screenshot of testbench waveform here — showing tx_start, tx,
baud_tick, rx_ready, and rx_data]
