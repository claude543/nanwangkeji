# BOARD15 内部设计03A｜必要功能边界、板端可实现性与最终实现路径 V0.1
## —— 只做实现项目功能与后续研究试验所必需的设计

> 日期：2026-08-18
> 性质：内部设计文件，不直接发给工程开发方。
> 前置结论：用户已确认现有板端通信周期 **100 ms 已实际验证无问题**。
> 唯一原则：**只实现为了项目15策略、最终CHIL和后续控制算法试验所必须具备的功能；不增加没有明确用途的复杂机制。**

---

# 1. 100 ms 正式作为 BOARD15 首选基础周期

- 50 ms 不再作为必须达到的项目目标。
- 当前首选基础通信/控制周期冻结为：
  - `T_fast = 100 ms`
  - `T_AGC = 1.0 s`
- 50 ms 只保留为未来有明确必要性且实机证明可行时的可选优化。
- 不需要再做 200 → 100 → 50 ms 的阶梯确认。既然100 ms已经实际验证通过，只需最终BOARD15完成后再做一次 **100 ms最终回归验证**。

---

# 2. 为什么100 ms已经够用

BOARD15定位为监督/协调控制器，不承担PWM、电流内环、电压内环或保护继电器级功能。

高速部分继续留在OP5700：

```text
100 μs Plant
PWM / inner loop
电磁暂态
Grid/PCC相角估计
GFM/GFL底层控制
```

Board只负责：

```text
P/Q参考
15策略判断
PCC协调
黑启动阶段
并离网管理
重同步监督
```

S15当前：

```text
SYNC_STABLE_S = 0.50 s
RECLOSE_HOLD_S = 0.20 s
```

100 ms周期下分别约为5个周期和2个周期，只要C实现使用真实 `elapsed time` 而不是“调用次数=时间”，即可正确实现监督级状态机。

后续执行状态算法主要时间尺度在数百毫秒到数秒，基础AGC本身为1 s，因此100 ms每个AGC周期可获得约10次执行状态观测，已经足以支持失配检测、恢复管理和资源状态判断。

---

# 3. 最终程序只需要六类能力

## 3.1 保留V3.2/V4/V5通信安全外壳

继续使用现有：

```text
connect_modbus
FC03
decode
DISCONNECTED / WAIT_VALID / ENABLED
MODEL_STATUS
RTLAB_HEARTBEAT
数据有效性
FC16
CMD_SEQ
BOARD_HEARTBEAT
自动重连
CSV
```

不重写另一套网络框架。

## 3.2 嵌入我方 `project15_core.c/.h`

我方算法模块负责：

```text
15策略判断
Request Normalizer
P目标/硬约束
Arbitrated Baseline AGC
Q Allocator
S6/S8辅助执行
Mode Manager
Black Start
Resynchronization
```

工程主程序只负责形成输入快照、调用算法、发送输出。

## 3.3 一个100 ms单线程主循环

首选结构：

```text
每100 ms：

FC03
↓
解码/有效性
↓
Measurement Snapshot
↓
15策略与快速执行域
↓
若1 s AGC到期：
    执行一次Baseline AGC
↓
生成完整Command Frame
↓
FC16
↓
candidate/commit处理
↓
CSV
```

不要求多线程、实时线程、共享内存、IPC。

## 3.4 1 s基础AGC子周期

继续冻结：

```text
Ts_AGC = 1.0 s
```

由 `monotonic clock + deadline` 触发，不用简单 `counter==10`。

## 3.5 完整Command Frame

BOARD15需要真实输出：

```text
6 Pref
6 Qref
6 GridOn
6 Droop
PCC Breaker request
Fref trim / synchronization request
system mode
selected master
control valid/status
CMD_SEQ
BOARD_HEARTBEAT
```

## 3.6 必要的Runtime Config

只把运行中确实要变的参数放到RT-LAB运行时配置：

```text
strategy enable
P objective mode
目标值
关键阈值
black-start / island master
recovery request
S15同步阈值
必要控制enable
```

静态网络、日志路径等仍放JSON。

---

# 4. Board必须读取的动态输入——最小必要集

## PCC

```text
PCC_P
PCC_Q
PCC_V
PCC_F
PCC_PHASE
```

## Grid

```text
GRID_V
GRID_F
GRID_PHASE
```

不因为模型里存在就强行加入 `GRID_P / GRID_Q`，除非最终算法明确使用。

## DER

```text
PV1_P_MAX
PV2_P_MAX
ESS1_SOC
ESS2_SOC

PV1_P_MEAS
PV2_P_MEAS
ESS1_P_MEAS
ESS2_P_MEAS
EV1_P_MEAS
EV2_P_MEAS
```

## System

```text
MODEL_STATUS
RTLAB_HEARTBEAT
PHASE_VALID
```

如最终模式管理确实需要独立 `GRID_PRESENT`，再增加一个明确状态位，否则优先由已有量判断。

---

# 5. 不再强制新增MEAS_SEQ

前一版提出 `MEAS_SEQ` 是为了50 ms快测量新鲜度。

现在以100 ms为正式基础周期，可以优先直接把：

```text
RTLAB_HEARTBEAT
```

改成：

```text
每100 ms / 每个新的Fast Snapshot更新
```

这样同一个寄存器同时证明：

```text
RT-LAB程序在运行
+
测量快照持续刷新
```

只有后续实测证明heartbeat和measurement snapshot无法形成同一更新语义时，才增加 `MEAS_SEQ`。

---

# 6. Modbus结构必须尽量简单

## 6.1 Fast Measurement Block

每100 ms：

```text
一次FC03
```

读取一个连续动态测量块。

不要拆成多次FC03去读PCC、Grid、Pmeas和状态。

## 6.2 Runtime Config Block

Fast block中只带：

```text
CONFIG_SEQ
```

如果序号未变化：

```text
不读取配置块
```

只有变化时再额外执行一次FC03读取完整Runtime Config，并在下一个100 ms边界统一应用。

## 6.3 Command Block

每100 ms：

```text
一次FC16
```

发送一个连续完整Command Frame。

不要把Pref、Qref、Mode、Breaker拆成多次FC16，否则candidate/commit和状态一致性会显著复杂化。

---

# 7. 对后续算法升级只提前预留真正必要的东西

## 7.1 统一Controller接口

当前：

```text
algorithm_mode = PROJECT15
```

其它：

```text
RESERVED
```

主程序通过Controller Adapter调用算法。

以后新的C算法只需要接入统一接口，不重新设计通信。

## 7.2 当前输入已经覆盖后续算法需要的数据

后续算法需要：

```text
last committed command
six Pmeas
PVmax
SOC
PCC
measurement validity
command success
```

这些主程序本来就有，因此当前只需把它们纳入统一Controller Context，不需要额外新增一套专用Modbus量。

## 7.3 小规模扩展配置和扩展诊断

可以预留一小段：

```text
EXT_CONFIG[]
EXT_DIAG[]
```

用于以后增加阈值、状态、残差等，而不重做点表。

数量在点表设计时按实际需要决定，不预留几百个寄存器。

大量普通诊断仍放Board CSV，只有需要与RT-LAB MAT同步的关键量才进Modbus诊断区。

---

# 8. 明确不让Board做的事情

全部继续留在RT-LAB：

```text
100 μs Plant仿真
PWM / inner controller
Grid/PCC phase estimator
execution fault injector
physical disturbance
final board heartbeat safety gate
final u_applied routing
Plant MAT logging
```

Board不承担：

```text
三相瞬时波形高速采样
相角DSP
PWM
物理故障注入
```

---

# 9. 明确不要求工程开发方做的事情

没有直接服务于项目/CHIL/后续控制算法试验，就不要求：

```text
50 ms硬指标
多线程实时框架
复杂线程同步
动态插件加载
完整编译环境交付
逐设备ACK系统
大量实时诊断寄存器
自动测试脚本
15种Case脚本
图形界面
独立上位机软件
```

---

# 10. RT-LAB模型真正需要的最小改造

## M1. 扩展RT-LAB → Board测量寄存器

在现有40101～40116基础上，补充：

```text
Grid V
Grid f
Grid phase
PCC phase
phase_valid
必要运行状态
```

并将RTLAB_HEARTBEAT刷新周期调整到100 ms。

## M2. 新增Runtime Config寄存器块

由RT-LAB Tunable Parameters发布，配：

```text
CONFIG_SEQ
```

Python以后可：

```text
按仿真时间修改Tunable Parameter
↓
CONFIG_SEQ变化
↓
Board下一周期加载新配置
```

## M3. 扩展Board → RT-LAB控制块

覆盖：

```text
6 Pref
6 Qref
GridOn
Droop
Breaker
Fref trim
mode/master
status
CMD_SEQ
BOARD_HEARTBEAT
必要diagnostics
```

## M4. 真正实现BOARD15 Source Router

当前控制源结构中的BOARD15分支要从预留变成真实控制源，并覆盖P/Q/Mode/Breaker/Fref。

## M5. 保留RT-LAB最终安全层

```text
Board valid + heartbeat fresh
→ 接受新Board Frame

invalid
→ state-aware hold / safe behavior
```

## M6. 保留Execution Fault Injector

仍然：

```text
u_commit
↓
execution fault
↓
u_applied
```

Board不知道故障真值。

## M7. 扩展OpWrite/MAT关键诊断

只记录项目和后续分析真正需要的关键量，不重复Board所有CSV字段。

---

# 11. 是否需要RT-LAB回传“命令已接受”确认

当前不设计逐设备ACK。

最多只考虑一个轻量：

```text
BOARD_FRAME_ACCEPTED_SEQ
```

RT-LAB在Board Frame通过最终安全路由后回显最后接受的CMD_SEQ。

用途是让S14/S15区分：

```text
FC16传输成功
```

和：

```text
RT-LAB最终接受该控制帧
```

是否必须增加，留到最终点表冻结时按S14/S15是否能仅靠下一批Plant测量可靠确认来决定。

原则：

```text
能不用就不用；
如果模式/Breaker阶段确认确实缺一条必要证据，
只加一个全帧ACK，
不增加逐设备ACK。
```

---

# 12. 最终最简系统架构

```text
RT-LAB OP5700
100 μs Plant
测量/相角/配置
        │
        │ FC03 every 100 ms
        ▼
External Board
V3.2通信安全
100 ms主循环
Project15
1 s Baseline AGC
Command Frame
candidate / commit
        │
        │ FC16 every 100 ms
        ▼
RT-LAB OP5700
Board validity
Source Router
P/Q/Mode/Breaker/Fref
Execution Fault
u_applied
2PV + 2ESS + 2EV
```

---

# 13. 后续设计顺序

```text
设计01：接口与状态边界       ✓
设计02：安全机制             ✓
设计03：多速率原理           ✓
设计03A：必要功能/可实现性    ✓

下一步：
设计04：最终Modbus点表
- Fast Measurement Block
- Runtime Config Block
- Command Block
- minimal diagnostics

然后：
设计05：逐persistent状态更新/commit规则
设计06：project15_core接口冻结
LOCAL15 → C转换
PC离线等价验证
最终工程程序版本要求
工程集成
RT-LAB模型适配
15策略/CHIL复测
```

---

# 14. 最终冻结结论

```text
100 ms
= 当前BOARD15正式基础周期

50 ms
= 非必要优化，不作为要求

1 s
= Baseline AGC周期

一个主循环
= 首选实现

一次Fast FC03
+
必要时一次Config FC03
+
一次Command FC16
= 首选通信结构

RT-LAB
= 高速Plant + 相角 + 故障 + 最后安全

Board
= 监督/协调控制
```

这才是符合“只做为了达到最终效果所必须做的事情”的BOARD15设计。
