---
permalink: /learn/01-hardware-basics/09-axi-peripherals/
lang: en
---
# 09. AXI4-Lite Bus

## 1. Why a Bus Is Needed

The CPU needs to access UART and GPIO as ordinary memory addresses (MMIO), but these two peripherals use the standard
AXI4-Lite slave interface (this project's peripheral code comes from open-source AXI-Lite IP). The CPU side uses a simplified
"request/data/ready" interface, so a **master bridge** `axil_master.v` is needed to do the protocol conversion.

Bus topology: **1 master, 3 slaves**. In `src/core_perips.v`:

- `is_uart = (adr[31:16] == 16'h1000)`
- `is_gpio = (adr[31:16] == 16'h2000)`

MEM (0x8000_0000) and CLINT (0x0200_0000) **do not go through AXI**; they are fixed-latency direct connections (see Chapter 03),
so the AXI bus actually only serves UART and GPIO.

## 2. The Five AXI4-Lite Channels

An AXI4-Lite write transaction uses 3 channels, and a read transaction uses 2 channels:

| Channel | Direction | Signals | Description |
|---------|-----------|---------|-------------|
| AW (write address) | M→S | awaddr/awvalid/awready | write address |
| W (write data) | M→S | wdata/wstrb/wvalid/wready | write data + byte enables |
| B (write response) | S→M | bresp/bvalid/bready | write completion acknowledgment |
| AR (read address) | M→S | araddr/arvalid/arready | read address |
| R (read data) | S→M | rdata/rresp/rvalid/rready | read data |

Each channel uses a **VALID/READY handshake**: the master asserts VALID, the slave asserts READY, and when both are active
the data/address is latched on the edge. `core_perips.v:106-122` instantiates these interconnect nets.

## 3. axil_master State Machine (src/axil_master.v)

The master bridge converts the CPU's simple interface (`mem_req` pulse + `mem_addr/mem_wdata/mem_wen/mem_wstrb`)
into the AXI five-channel handshake. State machine:

```
IDLE → (mem_req)
   write: → WRITE_ADDR (AW/W each handshake) → WRITE_RESP (wait for BVALID) → IDLE
   read:  → READ_ADDR (AR handshake) → READ_DATA (wait for RVALID) → READ_DONE → IDLE
```

Key fragment (`src/axil_master.v:143-190`):

```verilog
STATE_READ_ADDR: begin
    if (m_axil_arvalid && m_axil_arready) begin
        m_axil_arvalid <= 1'b0;
        m_axil_rready  <= 1'b1;
        state <= STATE_READ_DATA;
    end
end
STATE_READ_DATA: begin
    if (m_axil_rvalid && m_axil_rready) begin
        mem_rdata <= m_axil_rdata;
        ...
        state <= STATE_READ_DONE;
    end
end
STATE_READ_DONE: begin
    mem_ready <= 1'b1;      // single-beat pulse, notifies the CPU that the read is complete
    state <= STATE_IDLE;
end
```

On the write side, AW and W are **independent channels**, consumed separately in `STATE_WRITE_ADDR` (`axil_master.v:167-181`).

`mem_ready` is a single-beat pulse (`axil_master.v:115` defaults to clearing to 0), and `mem_busy = (state != IDLE)`
(`axil_master.v:86`) lets the CPU determine busy status.

## 4. CPU-Side Timing

`src/core_perips.v:127-176` converts PERIPS's `req` into an AXI request:

```verilog
wire axil_mem_req = req && (is_uart || is_gpio);
wire axil_mem_wen = (wen != 2'b00);
wire [3:0] axil_wstrb = (wen==2'b01) ? 4'b0001 :
                        (wen==2'b10) ? 4'b0011 :
                        (wen==2'b11) ? 4'b1111 : 4'b0000;
```

In `core_ctl`'s PERIPS beat: issue `perips_req` → wait for `perips_done` (=`axil_ready`)
→ capture data, advance the token (`src/core_ctl.v:406-427`).

## 5. Slave Return Mux

`src/core_perips.v:277-290` selects the two slaves' handshake signals back to the Master based on `is_uart/is_gpio`:

```verilog
assign s_axil_awready = is_uart ? uart_awready : is_gpio ? gpio_awready : 1'b0;
assign s_axil_rdata   = is_uart ? uart_rdata_s : is_gpio ? gpio_rdata_s : 32'b0;
...
```

The final `odata` selection (`src/core_perips.v:295-298`): MEM → CLINT → AXI.

## 6. Testing and Debugging

- The simplest verification: use the Shell's `info`/`gpio`/`uart` commands to read/write the UART/GPIO registers.
- Look at the `axil_*valid/ready` handshakes in the ModelSim waveform (`tb/mycpu_sim.v:61-71` has already brought the AXI signals out).
- Common problems: `req` pulse too short, `mem_ready` not consumed, and the AW/W two channels not each handshaking.

## 7. Pitfalls

- **mem_ready single beat**: if the CPU does not capture `perips_data_w` on that beat, the data is lost —
  `core_ctl` must latch on the `perips_done` (=axil_ready) beat.
- **wstrb**: SB only writes the low byte (`wstrb=0001`), SH/SW extend accordingly; `axil_master.v` does not do byte selection.
- **AW/W independence**: AXI allows AW and W to be out of order; the master bridge waits for both channels to be ready in the WRITE_ADDR state.
