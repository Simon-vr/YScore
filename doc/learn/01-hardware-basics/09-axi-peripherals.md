# 09. AXI4-Lite 总线

## 1. 为什么需要总线

CPU 要把 UART、GPIO 当作普通内存地址访问（MMIO），但这两个外设的接口是标准
AXI4-Lite 从机（本项目外设代码来自开源 AXI-Lite IP）。CPU 侧用的是简化的
"request/data/ready"接口，所以需要一个**主桥** `axil_master.v` 做协议转换。

总线拓扑：**1 主 3 从**。`src/core_perips.v` 里：

- `is_uart = (adr[31:16] == 16'h1000)`
- `is_gpio = (adr[31:16] == 16'h2000)`

MEM（0x8000_0000）与 CLINT（0x0200_0000）**不走 AXI**，是固定延迟直连（见 03 章），
所以 AXI 总线实际上只服务 UART 和 GPIO。

## 2. AXI4-Lite 五通道

AXI4-Lite 写事务用 3 个通道，读事务用 2 个通道：

| 通道 | 方向 | 信号 | 说明 |
|------|------|------|------|
| AW（写地址） | M→S | awaddr/awvalid/awready | 写地址 |
| W（写数据） | M→S | wdata/wstrb/wvalid/wready | 写数据 + 字节使能 |
| B（写响应） | S→M | bresp/bvalid/bready | 写完成确认 |
| AR（读地址） | M→S | araddr/arvalid/arready | 读地址 |
| R（读数据） | S→M | rdata/rresp/rvalid/rready | 读数据 |

每个通道都是 **VALID/READY 握手**：主拉 VALID，从拉 READY，两者同时有效时
数据/地址在沿上被锁存。`core_perips.v:106-122` 例化了这些互联线网。

## 3. axil_master 状态机（src/axil_master.v）

主桥把 CPU 的简单接口（`mem_req` 脉冲 + `mem_addr/mem_wdata/mem_wen/mem_wstrb`）
转成 AXI 五通道握手。状态机：

```
IDLE → (mem_req) 
  写: → WRITE_ADDR (AW/W 各自握手) → WRITE_RESP (等 BVALID) → IDLE
  读: → READ_ADDR (AR 握手) → READ_DATA (等 RVALID) → READ_DONE → IDLE
```

关键片段（`src/axil_master.v:143-190`）：

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
    mem_ready <= 1'b1;      // 单拍脉冲，通知 CPU 读完成
    state <= STATE_IDLE;
end
```

写侧 AW 和 W 是**独立通道**，`STATE_WRITE_ADDR` 里分别消费（`axil_master.v:167-181`）。

`mem_ready` 是单拍脉冲（`axil_master.v:115` 默认清 0），`mem_busy = (state != IDLE)`
（`axil_master.v:86`）供 CPU 判断忙。

## 4. CPU 侧时序

`src/core_perips.v:127-176` 把 PERIPS 的 `req` 转成 AXI 请求：

```verilog
wire axil_mem_req = req && (is_uart || is_gpio);
wire axil_mem_wen = (wen != 2'b00);
wire [3:0] axil_wstrb = (wen==2'b01) ? 4'b0001 :
                        (wen==2'b10) ? 4'b0011 :
                        (wen==2'b11) ? 4'b1111 : 4'b0000;
```

`core_ctl` 的 PERIPS 拍里：发 `perips_req` → 等 `perips_done`（=`axil_ready`）
→ 捕获数据、推进 token（`src/core_ctl.v:406-427`）。

## 5. 从机返回的多路选择

`src/core_perips.v:277-290` 把两个从机的握手信号按 `is_uart/is_gpio` 选回给 Master：

```verilog
assign s_axil_awready = is_uart ? uart_awready : is_gpio ? gpio_awready : 1'b0;
assign s_axil_rdata   = is_uart ? uart_rdata_s : is_gpio ? gpio_rdata_s : 32'b0;
...
```

`odata` 最终选择（`src/core_perips.v:295-298`）：MEM → CLINT → AXI。

## 6. 测试与调试

- 最简单的验证：Shell 的 `info`/`gpio`/`uart` 命令读写 UART/GPIO 寄存器。
- ModelSim 波形里看 `axil_*valid/ready` 握手（`tb/mycpu_sim.v:61-71` 已把 AXI 信号引出）。
- 常见问题：`req` 脉冲太短、`mem_ready` 没被消费、AW/W 两个通道未分别握手。

## 7. 易错点

- **mem_ready 单拍**：若 CPU 没在那一拍捕获 `perips_data_w`，数据就丢了——
  `core_ctl` 必须在 `perips_done`（=axil_ready）那一拍锁存。
- **wstrb**：SB 只写低字节（`wstrb=0001`），SH/SW 依次扩展，`axil_master.v` 不做字节选择。
- **AW/W 独立性**：AXI 允许 AW 和 W 乱序，主桥在 WRITE_ADDR 状态同时等两个通道就绪。