# RT-LAB I/O Interfaces 详细理解

## 先建立整体认识：I/O Interfaces 到底负责什么

`I/O Interfaces` 不是 Simulink 算法模块，也不负责计算功率。它相当于 RT-LAB 对外通信的"端口和寄存器管理器"，主要定义四件事：

```text
OP5700通过哪块网卡、哪个IP和端口对外通信
→ 对外提供哪些Modbus寄存器
→ 每个寄存器由板子还是Simulink模型控制
→ 这些寄存器怎样与sm_circuit中的OpInput/OpOutput连接
```

当前完整链路是：

```text
板子
  │ Modbus TCP
  ▼
I/O Interfaces中的Modbus Slave
  │ 寄存器映射
  ▼
Configuration
  │
  ▼
sm_circuit中的OpInput / OpOutput
```

其中：

- **I/O Interfaces**：定义网络服务和寄存器表；
- **Configuration**：把寄存器连接到模型信号；
- **Simulink 模型**：生成或使用实际数值；
- **板子程序**：通过 FC03、FC16 访问寄存器。

顶部的：

```text
Associated subsystem:
xingdaoru__slx__sier_rt/sm_circuit
```

表示这套 Modbus 接口归属于实时计算子系统 `sm_circuit`。后续在 Configuration 中，相关连接点也会映射到这个子系统。

---

## 一、General 中的三个选项是什么意思

你当前界面中有：

```text
Use an RT core for asynchronous computation
Enable verbose mode
Enable virtual mode
```

目前只勾选了 `Enable verbose mode`，这个配置对当前项目是合理的。

---

### 1. Use an RT core for asynchronous computation

中文可理解为：**是否单独占用一个实时 CPU 核心，专门运行 Modbus 通信驱动。**

#### 不勾选时

Modbus 通信任务运行在默认的 CPU 核心上，通常是运行操作系统的 core 0。

#### 勾选时

RT-LAB 会预留一个实时 CPU 核心专门处理通信。这样可以承载更多从站、更大量的数据或更高的通信负荷（[Opal-RT][1]）。

#### 为什么我们没有勾选

当前只有：

```text
1个Modbus Slave
28个Holding Register
1块外部板子
1～3秒级通信周期
```

通信量很小，没有必要额外占用一个实时核心。勾选它并不会让 28 个寄存器的简单通信明显变快，反而会占用 OP5700 的实时计算资源。

后续只有在以下情况下才需要考虑：

```text
寄存器数量大幅增加
多个Modbus主站同时连接
通信周期缩短到很高频率
现有通信出现明显处理瓶颈
```

所以当前保持**不勾选**。

---

### 2. Enable verbose mode

中文是**启用详细日志模式**。

勾选后，RT-LAB 在模型 Load、初始化 I/O 接口时，会输出更多 Modbus 配置和驱动信息。它主要帮助排查：

```text
网卡名称是否正确
IP和端口是否绑定成功
寄存器配置是否加载
驱动是否正常初始化
```

官方说明中，这个选项主要增加模型加载阶段的日志信息（[Opal-RT][1]）。

#### 为什么我们勾选

当前仍处在开发和联调阶段，出现问题时需要看到：

- Modbus Slave 有没有启动；
- 1502 端口有没有绑定；
- 寄存器表有没有加载；
- Configuration 有没有连接错误。

因此目前勾选是合理的。

等最终稳定运行后，可以取消，减少日志信息。

注意：

> `Verbose mode` 主要是 RT-LAB 驱动加载日志，不等于板子程序中的 `print_hex`。两者是两套不同日志。

---

### 3. Enable virtual mode

中文是**启用虚拟模式**。

虚拟模式下，即使当前计算机或目标机没有兼容的通信硬件，模型仍可以完成初始化和运行，但这个 I/O 接口实际上不会进行真实通信。官方文档明确说明，虚拟模式中的接口连接可以建立，但接口本身不会执行通信（[Opal-RT][1]）。

#### 为什么我们不能勾选

我们需要真实执行：

```text
板子192.168.1.10
↔ OP5700的192.168.1.100:1502
```

如果勾选虚拟模式，模型可能仍显示 Execute，但板子无法真正通过 1502 访问寄存器。

所以当前必须保持**不勾选**。

---

### General 三个选项的简单总结

| 选项               | 作用                  | 当前设置 | 原因         |
| ------------------ | --------------------- | -------- | ------------ |
| Use an RT core     | 单独占用实时核心处理通信  | 不勾选   | 当前通信量小 |
| Verbose mode       | 输出更多驱动加载日志    | 勾选     | 处于开发联调阶段 |
| Virtual mode       | 不执行真实 I/O，仅让模型模拟运行 | 不勾选   | 必须和真实板子通信 |

---

## 二、Slave_1 中的参数分别是什么意思

`Slave_1` 表示当前 OP5700 上配置的一台 Modbus 从站服务器。

板子是 Master，OP5700 是 Slave，因此由板子主动连接 OP5700。

当前配置为：

```text
Mode：TCP
NIC name：eth1
IP address：192.168.1.100
TCP port：1502
Cycle output rate：2000 ms
Byte ordering：ABCD
Permit address gaps：勾选
```

---

### 1. Mode = TCP

Modbus 有两种常见承载方式：

```text
Modbus TCP：通过以太网和TCP/IP通信
Modbus RTU：通过RS485等串行链路通信
```

当前板子与 OP5700 使用网线直接连接，因此选择 `Mode = TCP`。

如果选择 RTU，就会要求配置串口、波特率、停止位、校验位等，和当前项目完全不一致。

---

### 2. NIC name = eth1

NIC 是 **Network Interface Card**（网络接口）。

`eth1` 代表 OP5700 的第二块以太网接口。

当前 OP5700 有两条不同网络：

```text
eth0：192.168.10.87
用于上位机管理、RT-LAB Load和SSH

eth1：192.168.1.100
用于与控制器板子通信
```

所以 Modbus Slave 必须绑定 `eth1`。

官方文档要求根据目标机 Linux 中实际存在的接口名称选择 NIC，例如通过 `ifconfig` 或 `ip addr` 确认（[Opal-RT][1]）。

#### 如果错误填成 eth0 会怎样

Modbus 服务可能绑定在 `192.168.10.87`，但板子位于 `192.168.1.10`。板子通过直连网络访问的是 `192.168.1.100`，因此可能连接不上。

可以把它理解为：

> OP5700 有两扇门，Modbus 服务必须开在面向板子的 eth1 这扇门上。

---

### 3. IP address = 192.168.1.100

这是 OP5700 作为 Modbus Slave 对板子提供服务的 IP 地址，**不是**板子的 IP。

对应关系：

```text
OP5700 Modbus Slave：192.168.1.100
板子Modbus Master：192.168.1.10
```

板子 JSON 中配置 `"ip": "192.168.1.100"`，就是让板子连接这里。

`NIC name = eth1` 与 `IP address = 192.168.1.100` 必须属于同一网卡。也就是 eth1 上配置的地址必须是 192.168.1.100。

---

### 4. TCP port = 1502

这是 Modbus Slave 监听连接的 TCP 端口。

整个连接目标是 `192.168.1.100:1502`。模型 Execute 后，OP5700 会在该端口等待板子连接。官方说明中，TCP port 就是从站等待主站连接的端口（[Opal-RT][2]）。

#### 为什么不是标准端口 502

502 是标准 Modbus TCP 端口，但使用 502 通常涉及系统权限或与其他服务冲突。项目选择 1502，只要双方一致即可：

```text
RT-LAB：1502
板子JSON：1502
```

端口号本身不影响 Modbus 协议内容。

---

### 5. Cycle output rate = 2000 ms

这个参数很容易和板子 JSON 中的 `send_interval_ms` 混淆。它们**不是同一件事**。

#### 板子的 send_interval_ms

表示板子多久主动执行一次：`FC03读取 → 处理 → FC16写入`。

#### RT-LAB 的 Cycle output rate

表示 Simulink 模型控制的值，多久从模型刷新到 Modbus Slave 的输出寄存器中。官方文档将其定义为模型数据写入从站输出，即 Coils 和 Holding Registers 的更新周期（[Opal-RT][2]）。

当前配置 `Cycle output rate = 2000 ms`，表示由 `Control from = Model` 控制的寄存器，最多每 2 秒从 Simulink 刷新一次。

例如 `40101 PCC_P`、`40105 PV1_P_MAX`、`40116 RTLAB_HEARTBEAT` 如果由 Model 控制，模型中的值会按这个周期更新到 Modbus 寄存器。

#### 它不代表从站每 2 秒才响应一次

Modbus Slave 仍会持续响应板子的请求。官方说明，从站会尽可能快速地响应主站请求（[Opal-RT][1]），只是模型控制的数据可能每 2 秒刷新一次。

#### 对 V3.2 的重要影响

V3.2 计划 `RTLAB_HEARTBEAT` 每 1000 ms 变化一次，板子每 1000 ms 读取一次。但当前 `Cycle output rate = 2000 ms`，意味着即使 Simulink 内部心跳每 1 秒加 1，Modbus 寄存器可能仍每 2 秒才更新一次。

板子可能读取到：

```text
第1秒：10
第2秒：10
第3秒：12
第4秒：12
```

而不是每秒变化。

因此进入 V3.2 时，需要统一周期。较合理的是 `Cycle output rate = 1000 ms` 或更小，但要大于模型时间步长。这项修改要与心跳超时参数一起考虑，不能孤立设置。

---

### 6. Byte ordering = ABCD

字节序用于说明 32 位数据怎样放进两个 16 位寄存器。例如 FLOAT32 或 UINT32 有 4 个字节 `A B C D`，可能排列为：

```text
ABCD
BADC
CDAB
DCBA
```

官方文档说明，ABCD 表示标准网络字节顺序（[Opal-RT][2]）。

#### 为什么当前影响不大

目前 40001～40116 全部采用 UINT16 或 INT16，每个量只占一个 16 位寄存器，不涉及两个寄存器之间的排列，因此 ABCD 当前基本不产生实际影响。

后续如果改用 FLOAT32、INT32、UINT32，板子和 RT-LAB 就必须使用相同字节序，否则数值会完全错误。

所以现在保持 `ABCD` 即可。

---

### 7. Permit read/write requests with address gaps

中文可理解为：**允许寄存器地址中间存在未定义空洞**。

当前地址分成两段：

```text
0～11    对应40001～40012
100～115 对应40101～40116
```

中间的 `12～99` 没有人工定义寄存器。

勾选后，驱动会在最低地址和最高地址之间，对未定义地址自动建立值为 0 的占位寄存器（[Opal-RT][2]）。

#### 为什么我们需要勾选

因为我们故意把地址分成低地址段（板子写 RT-LAB）和高地址段（RT-LAB 发给板子），中间留出较大空间，方便后续扩展，也避免读写点混在一起。

勾选后，这种非连续地址布局能够被驱动正常管理。

当前板子实际请求是：

```text
FC16：offset 0，数量12
FC03：offset 100，数量16
```

都没有跨越中间空洞，但保持勾选可以让整个地址空间的非连续布局更明确、稳定。

---

## 三、Slave_1 下面四类数据区是什么意思

Modbus 标准将数据分为四类：

| 数据区             | 数据宽度   | 主站权限   | 常见功能码            |
| ------------------ | ---------- | ---------- | --------------------- |
| Coils              | 1 bit      | 可读、可写 | FC01、FC05、FC15      |
| Discrete Inputs    | 1 bit      | 只读       | FC02                  |
| Holding Registers  | 16 bit     | 可读、可写 | FC03、FC06、FC16      |
| Input Registers    | 16 bit     | 只读       | FC04                  |

---

### 1. Coils

Coil 是单个二进制量（0 或 1），适合：

- 开关命令；
- 启停命令；
- 断路器合闸/分闸；
- 布尔使能信号。

例如：启动 AGC = 1，停止 AGC = 0。

主站可以读，也可以写。

我们没有使用 Coils，是因为目前主要传输功率、电压、频率、SOC、状态码、心跳计数、命令序号等，都不是简单的 1 位数据。

即使 `EXT_AGC_ENABLE` 只有 0 和 1，我们仍将它放在 Holding Register 中，是为了让所有数据统一通过一条 FC16 批量写入 `40001～40012`，这样板子无需额外发送 FC05 或 FC15。

---

### 2. Discrete Inputs

Discrete Input 也是单个 0/1 信号，但对 Modbus 主站**只读**。

适合模型向外报告某保护是否动作、断路器是否闭合、某设备是否故障等数字量告警。

板子只能读取，不能写。

我们当前没有单独使用它，因为：

- 当前没有必须通过独立 bit 区传输的数字量；
- `MODEL_STATUS` 已经把多个状态压缩到一个 UINT16 状态字；
- 保持一套 Holding Register 协议更简单。

---

### 3. Holding Registers

Holding Register 是 16 位寄存器，并且支持主站读写。**这是当前项目唯一使用的数据区**。

它可以承载 UINT16、INT16，以及驱动扩展支持的 UINT32、INT32、FLOAT32。

官方文档说明，Holding Register 支持主站控制、模型控制或双方控制，并可映射成模型输入或输出（[Opal-RT][2]）。

我们使用：

```text
FC03：读取Holding Registers
FC16：写多个Holding Registers
```

正好满足板子读取 RT-LAB 测量量、板子写入 RT-LAB 控制量。

---

### 4. Input Registers

Input Register 也是 16 位数值，但对主站通常只读。

适合 RT-LAB 生成测量量、板子只负责读取的场景。

理论上，我们完全可以把 40101～40116 放入 Input Registers，然后板子使用 FC04 读取。但我们没有这样做，是为了简化板子程序和点表。

当前全部放入 Holding Registers 后，板子只需要 FC03 读取 16 路 + FC16 写 12 路，不用同时维护 FC03、FC04、FC16，使程序、日志、地址映射和调试更统一。

---

## 四、为什么我们只使用 Holding Registers

主要有四个原因。

### 原因 1：数据都是 16 位数值，不是单 bit

当前数据包括功率、电压、频率、SOC、状态码、心跳、序号，都适合 16 位寄存器。Coils 和 Discrete Inputs 只有 1 bit，不适合。

### 原因 2：同时需要板子读和板子写

Holding Registers 支持 FC03 读取和 FC16 写入，同一类寄存器即可完成双向通信。

### 原因 3：程序更简单

板子只需维护两个主要请求：FC03 读 40101～40116 和 FC16 写 40001～40012。不需要额外增加 FC01、FC02 或 FC04。

### 原因 4：可以通过 Control from 区分数据方向

虽然全部属于 Holding Register，但可以给每个点指定"谁拥有写权限"：

```text
40001～40012：Control from = Master
40101～40116：Control from = Model
```

这样同一类寄存器也不会发生方向混乱。

---

## 五、Holding Registers 表格每一列是什么意思

截图中的列包括：

```text
Name
Address
Initial value
Control from
Register type
```

---

### 1. Name

只是 RT-LAB 内部用于识别和 Configuration 映射的名称，例如 `Modbus_4001_raw`、`EXT_AGC_ENABLE_raw`、`Op40101`。

名称不会通过 Modbus 报文发送给板子。板子只看到地址和数值。

名称需要统一，是为了避免 Configuration 中接错点。

---

### 2. Address

这是 Modbus 的零基地址 offset。

```text
Address 0   → 逻辑地址40001
Address 1   → 逻辑地址40002
Address 9   → 逻辑地址40010
Address 100 → 逻辑地址40101
```

所以板子日志中 `FC16 offset=0`、`FC03 offset=100` 与这里完全对应。

---

### 3. Initial value

寄存器在模型刚启动、尚未收到板子数据或模型数据前的初始值。

当前设置为 `0.0`，表示启动时先为 0。

对于 `Control from = Master` 的点，在板子第一次写入之前，模型看到的是初始值。

---

### 4. Control from

这是整个表中最关键的一列。

#### Master

表示该寄存器由外部 Modbus 主站（即板子）控制。官方说明中，Master 控制的点作为模型输入，主站写入后传给 Simulink，应连接到模型的 OpInput（[Opal-RT][2]）。

当前 `40001～40012 = Master`，数据方向为：板子 → FC16 → Holding Register → OpInput → Simulink。

#### Model

表示该寄存器由 Simulink 模型控制，板子只能读取。官方说明中，Model 控制的点由模型输出，主站可以读取；即使主站尝试写入，也会被模型重新覆盖。应连接模型的 OpOutput（[Opal-RT][2]）。

当前 `40101～40116 = Model`，数据方向为：Simulink → OpOutput → Holding Register → FC03 → 板子。

#### Both

表示板子和模型都可能控制同一寄存器。模型会按 `Cycle output rate` 周期覆盖该寄存器。

当前项目没有使用 Both，因为会出现所有权竞争：板子刚写一个值，模型随后又将它覆盖，这会使调试复杂。

所以我们采用明确分工：

```text
低地址段完全归板子
高地址段完全归模型
```

---

### 5. Register type

表示 RT-LAB 怎样解释这个寄存器：UINT16、INT16、UINT32、INT32、FLOAT32。

当前截图中 I/O Interfaces 全部显示 `UINT16`，这意味着驱动层主要保留原始 16 位位模式。例如 `0xF060` 会输出为 `61536`。

然后我们在 Simulink 中用 Data Type Conversion 重新解释为 `-4000`。

这种方式的好处是：

> I/O Interfaces 统一保留原始寄存器位模式，具体 INT16/UINT16 语义由点表和 Simulink/板子程序处理。

这也是为什么 V3.1 中需要增加 int16 转换模块。

---

## 六、用当前 28 个 Holding Register 理解完整结构

当前一共是 12 个板子控制点 + 16 个模型控制点 = **28 个 Holding Registers**。

### 前 12 个

```text
Address 0～11
逻辑地址40001～40012
Control from = Master
```

数据方向：**板子写入 → RT-LAB 模型接收**。

### 后 16 个

```text
Address 100～115
逻辑地址40101～40116
Control from = Model
```

数据方向：**RT-LAB 模型生成 → 板子读取**。

这就是当前 Holding Registers (28) 的来源。

---

## 七、最完整的串联理解

### 板子写 RT-LAB

```text
板子生成控制数据
→ FC16写offset 0～11
→ I/O Interfaces中的Master控制寄存器
→ Configuration连接到sm_circuit的OpInput
→ Simulink接收raw
→ int16解释和Gain缩放
→ SC显示
→ 后续接设备Pref
```

### RT-LAB 发给板子

```text
Simulink生成测量量、状态和心跳
→ OpOutput
→ Configuration
→ I/O Interfaces中的Model控制寄存器
→ Cycle output rate刷新寄存器
→ 板子FC03读取offset 100～115
→ 板子解码成工程量
```

---

## 最终记忆方式

可以把 I/O Interfaces 中的各部分理解为：

```text
General：
通信驱动整体怎样运行

Slave_1：
OP5700从哪块网卡、哪个IP、哪个端口提供Modbus服务

Coils / Discrete Inputs / Holding Registers / Input Registers：
Modbus提供哪一种类型的数据区

Holding Registers表：
具体有哪些寄存器、地址是什么、由谁控制、采用什么类型
```

我们只使用 Holding Registers，是因为：

> 当前全部信号都是 16 位数值，并且既有板子写入也有板子读取；使用 Holding Registers 后，只需 FC03 和 FC16 两类请求，再通过 `Control from = Master / Model` 区分数据方向，结构最简单、最统一。

[1]: https://opal-rt.atlassian.net/wiki/spaces/PDOCHS/pages/150341654/Modbus%2BMaster%2BConfiguration?utm_source=chatgpt.com "Modbus Master | Configuration - HYPERSIM Documentation - OPAL-RT"
[2]: https://opal-rt.atlassian.net/wiki/spaces/PDOCHS/pages/150079584/Modbus%2BSlave%2B%7C%2BConfiguration?utm_source=chatgpt.com "Modbus Slave | Configuration - HYPERSIM Documentation - OPAL-RT"
