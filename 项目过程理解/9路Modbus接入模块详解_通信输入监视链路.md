# 板子到 RT-LAB 的 9 路 Modbus 接入模块详解

**结论：这套 9 路模块的作用是把"板子写进 Modbus 寄存器的值"变成 `sm_circuit` 里可用的 9 路 Simulink 信号，并进一步打包成一个向量送到 SC 界面显示。它本身还不是控制闭环，只是通信输入监视链路。**

完整链路是：

```text
板子 FC16 写 40001~40009
→ RT-LAB Modbus Slave 收到 9 个寄存器值
→ Configuration 把寄存器值连接到 sm_circuit 的 9 个 OpInput
→ sm_circuit 中出现 9 路 raw 信号
→ Mux 打包成 1 个向量
→ 通过 OpComm 送到 sc_display
→ SC 显示 101~109
```

---

## 1. 外面的 9 个 `Modbus_400x_raw` 是什么？

你第一张图左侧这些块：

```text
Modbus_4001_raw
Modbus_4002_raw
...
Modbus_4009_raw
```

它们是 **OpInput**。

它们的作用不是计算，而是：

```text
把 RT-LAB 外部 I/O 接口的数据送进 sm_circuit
```

也就是说，它们是 **外部数据进入实时模型的入口**。

对应关系是：

| Simulink 里的 OpInput | Modbus 寄存器 | 板子写入值 |
| ------------------- | -----------: | -------: |
| Modbus_4001_raw     | 40001 / offset 0 | 101 |
| Modbus_4002_raw     | 40002 / offset 1 | 102 |
| Modbus_4003_raw     | 40003 / offset 2 | 103 |
| ...                 | ... | ... |
| Modbus_4009_raw     | 40009 / offset 8 | 109 |

关键点：

```text
OpInput 本身不知道自己对应 40001 还是 40009。
这个对应关系是在 RT-LAB Configuration 里建立的。
```

所以你才必须在 Configuration 中把：

```text
Modbus Slave / Holding Register / Modbus_4001_raw
```

连接到：

```text
sm_circuit / Modbus_4001_raw
```

否则板子虽然写了寄存器，`sm_circuit` 里这个 OpInput 也收不到值。

---

## 2. 为什么名字里有 `_raw`？

`raw` 的意思是"原始值"。

现在板子写的是：

```text
101
102
...
109
```

这些只是未经换算的寄存器原始整数。

后续真实控制时，板子可能写：

```text
Ppv1_raw
Ppv2_raw
Pess1_raw
...
```

这些 raw 值不能直接接设备 Pref，必须经过：

```text
raw 原始值
→ 数据类型转换
→ 工程量换算
→ kW / pu 换算
→ 限幅
→ 通信有效判断
→ Switch
→ 设备 Pref
```

所以命名为 `_raw` 是合理的，表示"这是通信层收到的原始数据，还不是最终控制量"。

---

## 3. 中间的 `Modbus_Raw_Monitor` 子系统是什么？

你第一张图中间这个大子系统：

```text
Modbus_Raw_Monitor
```

它的作用主要是 **整理和监视 9 路 Modbus 原始输入**。

它不是必须的通信模块，而是为了让模型更清晰：

```text
把 9 路信号集中放进一个子系统
方便后续打包、显示、检查、扩展
```

如果不建这个子系统，也可以直接把 9 路 OpInput 接到 Mux。
但那样顶层会更乱，不利于后面继续加控制逻辑。

你可以把它理解成：

```text
9 路 Modbus 输入信号的监视器 / 汇总器
```

---

## 4. 子系统内部的 1~9 Inport 是什么？

第二张图左侧的：

```text
1
2
3
...
9
```

是子系统的 **Inport**。

它们没有计算作用，只是子系统的输入端口。

对应关系是：

```text
外部 Modbus_4001_raw → 子系统 Inport 1
外部 Modbus_4002_raw → 子系统 Inport 2
...
外部 Modbus_4009_raw → 子系统 Inport 9
```

通俗理解：

```text
外面有 9 根线要进子系统
所以子系统里面要有 9 个入口
```

---

## 5. 为什么每一路信号又分叉？

你图里很多线都有黑点和分叉。

在 Simulink 里，信号线分叉表示：

```text
同一个信号复制给多个模块使用
```

它不是电气线路里的"短接"，而是数据流复制。

例如 `Modbus_4001_raw` 可以同时送到：

```text
1. Modbus_Raw_Monitor 子系统
2. Mux 打包成向量
3. 后续控制逻辑
```

也就是说，分叉的意义是：

```text
同一个板子写入值，可以被多个地方同时使用
```

---

## 6. 右侧的 Mux 是什么？为什么要加？

第一张图右侧黑色竖条是：

```text
Mux
```

Mux 的作用是：

```text
把多路单独信号合成一个向量信号
```

也就是：

```text
Modbus_4001_raw = 101
Modbus_4002_raw = 102
...
Modbus_4009_raw = 109
```

经过 Mux 后变成：

```text
[101 102 103 104 105 106 107 108 109]
```

为什么要这样做？因为这样更方便送到 SC 显示或记录。

如果不 Mux，你需要 9 根线、9 个 OpComm、9 个 Display。
Mux 后只需要传一个 9 维向量。

所以 Mux 的作用是：

```text
把 9 路寄存器值打包成一个向量，方便传输和显示
```

---

## 7. `modbus_raw_vec_to_sc` 是什么？

第一张图最右侧的输出信号叫：

```text
modbus_raw_vec_to_sc
```

它的意思是：

```text
Modbus raw vector to SC
```

也就是：

```text
把 9 路 Modbus 原始值打包成向量后，送到 sc_display 显示
```

这一路一般后面会通过 `OpComm` 传给 `sc_display`。

原因是 RT-LAB 中：

```text
sm_circuit 是实时计算子系统
sc_display 是控制台显示子系统
```

两者之间不能随便用普通线连接，通常需要通过 RT-LAB 通信模块，例如 `OpComm`。你之前遇到的 Build 报错：

```text
Inport block of RT-LAB subsystems can only be connected to opcomm blocks
```

本质就是 SC 子系统信号交换规则不满足。

RT-LAB 手册也说明模型运行后可以在 SC 中观察下位机解算结果，因此 SC 更偏向监视和交互界面，不是实时主模型本体。

---

## 8. 为什么不能直接在 sm_circuit 里放 Display / Scope？

理论上 Simulink 离线仿真可以放 Display / Scope。

但在 RT-LAB 实时仿真里，`sm_circuit` 是要编译到 OP5700 上运行的实时子系统。里面直接放普通 Display / Scope 不合适，原因是：

```text
1. Display / Scope 是上位机显示用的，不适合放在实时目标机计算子系统里
2. Build 时可能不支持或导致结构不符合 RT-LAB 规则
3. 实时模型的数据应通过 OpComm / Probe / Recorder 等方式送出
```

所以正确做法是：

```text
sm_circuit 里负责计算和输出信号
sc_display 里负责显示
sm 和 sc 之间用 OpComm 通信
```

---

## 9. 为什么这样连接后 SC 能显示 101~109？

完整过程如下。

### 第一步：板子写寄存器

板子通过 Modbus TCP 写：

```text
40001 = 101
40002 = 102
...
40009 = 109
```

使用的是：

```text
FC16 写多个 Holding Registers
offset = 0
quantity = 9
```

---

### 第二步：RT-LAB Modbus Slave 接收

OP5700 上的 Modbus Slave 收到以后，寄存器表变成：

```text
Address 0 = 101
Address 1 = 102
...
Address 8 = 109
```

---

### 第三步：Configuration 把寄存器连接到 OpInput

Configuration 中已经配置：

```text
Address 0 → Modbus_4001_raw
Address 1 → Modbus_4002_raw
...
Address 8 → Modbus_4009_raw
```

所以 `sm_circuit` 里的 9 个 OpInput 输出值变成：

```text
Modbus_4001_raw = 101
Modbus_4002_raw = 102
...
Modbus_4009_raw = 109
```

---

### 第四步：Mux 打包成向量

Mux 输出：

```text
modbus_raw_vec_to_sc = [101 102 103 104 105 106 107 108 109]
```

---

### 第五步：送到 SC 显示

这个向量通过后续的 OpComm 送到 `sc_display`。

SC 里 Display 显示：

```text
101 102 103 104 105 106 107 108 109
```

所以你看到显示正确，说明：

```text
板子 → Modbus Slave → Configuration → OpInput → Mux → SC 显示
```

这条链路是通的。

---

## 10. 每个模块的作用总结

| 模块 / 信号 | 位置 | 作用 |
|------------|------|------|
| Modbus_4001_raw~Modbus_4009_raw | sm_circuit | 9 路 OpInput，把板子写入的寄存器值引入模型 |
| Modbus_Raw_Monitor | sm_circuit | 汇总和监视 9 路 Modbus 原始值 |
| Inport 1~9 | Modbus_Raw_Monitor 内部 | 子系统输入端口，对应 9 路 raw 信号 |
| 分叉线 | sm_circuit | 同一个 raw 信号同时送给多个用途 |
| Mux | sm_circuit | 把 9 路标量打包成 1 个向量 |
| modbus_raw_vec_to_sc | sm_circuit 输出 | 把 9 路 raw 值送去 SC 显示 |
| OpComm | sm/sc 之间 | 实时模型和控制台之间交换数据 |
| Display | sc_display | 显示板子写入的 9 路数值 |

---

## 11. 这套结构当前实现了什么？

它实现的是：

```text
板子写入 40001~40009
RT-LAB 能收到
RT-LAB 能在 SC 显示
```

也就是说，它验证的是：

```text
板子 → RT-LAB 的单向写入通信
```

它还没有实现：

```text
板子控制 PV / ESS / EV
板子运行 AGC
RT-LAB 闭环响应
```

目前它只是通信验证层。

---

## 12. 后续如果要变成真正控制链路，需要怎么改？

现在的链路是：

```text
Modbus_4001_raw~Modbus_4009_raw
→ Mux
→ SC 显示
```

后续要增加一条控制链：

```text
Modbus_4001_raw~Modbus_4009_raw
→ 数据类型转换
→ 工程量换算
→ pu 换算
→ 限幅
→ 通信有效判断
→ EXT_ENABLE Switch
→ PV / ESS / EV Pref
```

也就是说，当前这 9 路 raw 信号以后会有两个用途：

```text
用途 1：继续送 SC 显示，用于监视
用途 2：送控制逻辑，用于外部 AGC 接管设备
```

结构会变成：

```text
板子写 40001~40009
        ↓
Modbus_4001_raw~Modbus_4009_raw
        ├── Mux → SC 显示
        └── 换算/限幅/Switch → 设备 Pref
```

---

## 13. 最核心记忆

你可以记成一句话：

```text
OpInput 把板子写入值带进 sm_circuit；
Mux 把 9 路值打包；
OpComm 把打包后的值送到 sc_display；
Display 只是显示；
Configuration 决定寄存器和 OpInput 的对应关系。
```

当前这套 9 路结构的最终效果是：

```text
板子写 40001~40009 = 101~109，
RT-LAB 的 sm_circuit 收到 101~109，
sc_display 显示 101~109。
```

这证明的是通信入口已打通，不代表 AGC 闭环已经完成。
