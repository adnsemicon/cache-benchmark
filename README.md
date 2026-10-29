# Problem Statement: Parameterizable Set-Associative Read Cache (`simple_cache`)

## 1. Overview

Design and implement a parameterizable, read-only, **set-associative cache controller and memory array** (`simple_cache`) in SystemVerilog.

The cache sits between a requester (e.g., a CPU or DMA engine) that reads individual Cache data width `C_DW` and a backing main memory that transfers full cache lines of memory data width `M_DW`. Your implementation must support configurable address widths, data widths, number of cache lines, and set associativity, using any replacement policy as preferred.

---

## 2. Module Interface

### 2.1 Parameters

| Parameter | Type  | Default | Description                                                                                                |
| :-------- | :---- | :------ | :--------------------------------------------------------------------------------------------------------- |
| `AW`      | `int` | `16`    | **Address Width**: Width of byte addresses on both the cache and memory interfaces (in bits).              |
| `C_DW`    | `int` | `8`     | **Cache Data Width**: Width of data requested by the CPU/cache side (in bits).                             |
| `M_DW`    | `int` | `128`   | **Memory Data Width**: Width of a memory block or cache block/line transferred from main memory (in bits). |
| `CL`      | `int` | `256`   | **Cache Lines**: Total number of cache lines in the cache.                                                 |
| `NW`      | `int` | `4`     | **Number of Ways**: Set associativity (number of ways per set).                                            |

### 2.2 Input & Output Ports

| Port Name                         | Direction | Width  | Description                                                                   |
| :-------------------------------- | :-------- | :----- | :---------------------------------------------------------------------------- |
| **Clock & Reset**                 |           |        |                                                                               |
| `arst_ni`                         | `input`   | `1`    | Asynchronous active-low reset (`0`: reset active, `1`: normal operation).     |
| `clk_i`                           | `input`   | `1`    | Positive-edge-triggered system clock.                                         |
| **Cache (CPU-Side) Interface**    |           |        |                                                                               |
| `c_addr_i`                        | `input`   | `AW`   | Requested address from the cache requester.                                   |
| `c_req_i`                         | `input`   | `1`    | Cache read request strobe (`1`: valid read request).                          |
| `c_data_o`                        | `output`  | `C_DW` | Read data returned to the cache requester.                                    |
| `c_gnt_o`                         | `output`  | `1`    | Cache read grant/acknowledge (`1`: `c_data_o` is valid in the current cycle). |
| **Memory (Downstream) Interface** |           |        |                                                                               |
| `m_addr_o`                        | `output`  | `AW`   | Cache-line-aligned base address sent to main memory.                          |
| `m_req_o`                         | `output`  | `1`    | Memory read request (`1`: requesting a cache line refill).                    |
| `m_data_i`                        | `input`   | `M_DW` | Full cache line data returned from main memory.                               |
| `m_gnt_i`                         | `input`   | `1`    | Memory read grant (`1`: `m_data_i` is valid in the current cycle).            |

---

## 3. Interaction Protocol

1. The requester asserts `req` with the desired address on `addr`.
2. The responder responds with `gnt` once the requested data is available on `data`.
3. The requester must wait for `gnt` to be asserted before considering `data` valid.
4. The requester can not deassert `req` before `gnt` is received and the data has been captured.
