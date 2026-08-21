# BOARD15（板端15策略程序）工程师最终程序要求｜内容冻结规划 V0.1
## ——只规划工程师需要开发和实现的内容，不写验收要求，不写内部研究过程

> **日期**：2026-08-20  
> **当前阶段**：LOCAL15（模型侧15策略本地闭环）15/15 已冻结；C01～C10（C语言迁移与控制器适配层）已完成；开始汇总工程师最终 BOARD15（板端15策略程序）开发要求。  
> **本轮性质**：内部内容冻结规划。**本轮不是最终发给工程师的正式文档。**  
> **正式文档拟名**：`BOARD15最终板端控制程序设计与集成要求_V1.0.md`

---

# 1. 这份工程师文档的唯一目的

最终文件只回答一件事：

> **工程师需要在现有已验证板端程序基础上增加和修改哪些功能，最终形成什么样的 BOARD15（板端15策略程序）。**

正式文件只写：

```text
现有功能继续保留什么
↓
最终程序增加什么
↓
需要集成哪些 .c（C源文件）和 .h（C头文件）
↓
每100 ms主循环如何运行
↓
读取哪些寄存器
↓
如何形成 ControllerInput（控制器输入）
↓
如何调用 Controller Adapter（控制器适配层）
↓
如何形成完整 Command Frame（命令帧）
↓
如何通过 FC16（Modbus写多个寄存器功能码）发送
↓
什么时候 controller_commit（提交控制状态）
↓
通信异常、恢复、配置变化、Reset（复位）如何处理
```

正式文件不展开：

```text
C01～C10为什么逐轮产生
每轮测试跑了多少随机用例
LOCAL15怎么一步步改出来
内部研究目的
论文内容
验收用例
PASS判据
截图要求
报告取证要求
```

---

# 2. 当前工程师旧程序基线已经足够明确

当前上传的旧板端程序配套 `JSON（配置文件）` 已经能够作为最终升级的工程基线。

现有主要结构：

```text
Modbus TCP（Modbus传输控制协议）
↓
FC03（Modbus读保持寄存器功能码）
读取40101～40116

↓
DISCONNECTED（断开）
WAIT_VALID（等待数据有效）
ENABLED（已允许外部控制）
三状态安全框架

↓
基础 AGC（自动发电控制）算法

↓
FC16（Modbus写多个寄存器功能码）
写40001～40012
```

现有配置还包括：

```text
MODEL_STATUS（模型状态）
RTLAB_HEARTBEAT（RT-LAB心跳）
BOARD_HEARTBEAT（板端心跳）
CMD_SEQ（命令序号）
自动重连
连续3个有效周期投入
通信超时
测量范围检查
JSON（配置文件）
CSV（逗号分隔日志文件）
```

因此正式要求的原则确定为：

> **继续在现有程序上扩展，不重新设计第二套通信、安全状态机和网络框架。**

---

# 3. 当前最终 Simulink（仿真模型）审计得到的事实

上传的最终模型已经具备旧板端接口基础。

当前 `SM_Master（主实时子系统）` 内已经存在：

```text
12个 OpInput（RT-LAB输入接口块）
对应旧40001～40012

16个 OpOutput（RT-LAB输出接口块）
对应旧40101～40116
```

当前模型还已经完整具备：

```text
AA15_LOCAL_CONTROL_STACK（15策略本地控制栈）

P控制
Q控制
Mode（模式）控制
PCC Breaker（公共连接点断路器）控制
Black Start（黑启动）
S15 Resynchronization（策略15重同步恢复）
```

但是当前模型源码明确保留：

```text
CONTROL_SOURCE（控制源）=0
→ LEGACY（原控制源）

CONTROL_SOURCE（控制源）=1
→ LOCAL15（本地15策略）

CONTROL_SOURCE（控制源）=2
→ BOARD15（板端15策略）
```

其中 `CONTROL_SOURCE（控制源）=2` 在当前 P（有功）、Q（无功）等 Router（路由器）中仍是**预留未接入状态**。

这说明最终 C11（真实板端集成阶段）模型侧工作主要是：

```text
扩展 OpInput（RT-LAB输入接口）
扩展 OpOutput（RT-LAB输出接口）
↓
把 BOARD15（板端15策略）完整命令接入 source=2
↓
生成40122/40123最终执行反馈
↓
配置RT-LAB I/O Interfaces（输入输出接口）
↓
Configuration（配置）完成映射
```

这部分由我们处理，不作为工程师板端程序开发任务写进正式要求。

---

# 4. 正式工程师要求文档建议采用17个章节

以下章节已经基本冻结。

---

# 第一章｜最终程序目标与总体数据流

只写最终目标：

```text
RT-LAB
↓
FC03（读保持寄存器）
40101～40124
↓
Board（外部控制板）
↓
现有安全状态机
↓
Controller Adapter（控制器适配层）
↓
PROJECT15 Core（PROJECT15完整控制核心）
↓
40001～40064
↓
FC16（写多个寄存器）
↓
RT-LAB
```

正式基础周期：

```text
100 ms
```

这已经冻结。

不再设计：

```text
200 ms → 100 ms → 50 ms逐级试验
```

---

# 第二章｜必须继承的现有板端程序功能

工程师需要继续保留：

```text
Modbus TCP（Modbus传输控制协议）

FC03（读保持寄存器）
FC16（写多个寄存器）

DISCONNECTED（断开）
WAIT_VALID（等待数据有效）
ENABLED（已允许外部控制）

MODEL_STATUS（模型状态）
RTLAB_HEARTBEAT（RT-LAB心跳）
BOARD_HEARTBEAT（板端心跳）

测量有效性检查
连续有效周期投入
通信超时
自动重连

原寄存器：
类型
缩放
有符号/无符号转换
补码
舍入
范围处理

JSON（配置文件）
CSV（运行日志）
```

正式文档不要求工程师重新实现这些功能，而是要求：

> **在现有已验证框架内扩展 BOARD15（板端15策略程序）。**

---

# 第三章｜最终板端程序软件组成

工程师最终程序由三部分共同组成：

```text
A. 现有 Engineering Main Program（工程主程序）
   负责网络、Modbus、状态机、JSON、日志、调度

B. Controller Adapter（控制器适配层）
   负责候选状态、待提交状态、提交、复位、配置更新和执行确认

C. PROJECT15 Core（PROJECT15完整控制核心）
   负责15项高级应用控制算法
```

正式文档不要求工程师重新分解算法，只要求：

```text
将我们提供的正式C模块加入现有工程
↓
按规定接口调用
```

---

# 第四章｜需要集成的正式 C（C语言）模块

当前正式依赖版本冻结为：

```text
strategy15_core_BOARD15_C01_V0_1.h/.c
15策略判断核心

p_objective_BOARD15_C02_V0_1.h/.c
有功目标和约束

p_coord_baseline_BOARD15_C03_V0_2.h/.c
基础有功协调

p_execution_auxiliary_BOARD15_C04_V0_1.h/.c
有功执行映射与S6/S8辅助控制

q_control_BOARD15_C05_V0_1.h/.c
无功控制

mode_control_BOARD15_C06_V0_3.h/.c
系统模式控制

black_start_BOARD15_C07_V0_1.h/.c
黑启动阶段控制

resynchronization_BOARD15_C08_V0_1.h/.c
重同步恢复控制

project15_core_BOARD15_C09_V0_2.h/.c
完整PROJECT15控制核心

controller_adapter_BOARD15_C10_V0_1.h/.c
控制器适配层

controller_api_BOARD15_V0_1.h
控制器公共接口
```

正式要求中说明：

```text
这些文件作为完整算法模块加入最终工程
```

不写内部迁移历史。

---

# 第五章｜最终 Modbus（通信寄存器）范围

正式依据：

```text
BOARD15_Modbus点表_RuntimeConfig_CommandFrame_V0.4...
```

三块：

```text
40001～40064
Board → RT-LAB
完整 Command Frame（命令帧）

40101～40124
RT-LAB → Board
Measurement + Execution Feedback（测量与执行反馈）

40201～40280
Runtime Config（运行时配置）
```

正式文档只概述功能分组。

每个寄存器的：

```text
地址
名称
数据类型
缩放
单位
取值范围
```

以附件点表为正式定义，避免正文和Excel重复维护两套版本。

---

# 第六章｜功率方向和工程量转换

这一章必须单独写清楚。

BOARD15（板端15策略）算法内部统一：

```text
PCC P > 0
→ 微电网向上级电网送电

PCC P < 0
→ 微电网从上级电网购电
```

旧40101线端定义仍是：

```text
购电为正
送电为负
```

所以工程主程序需要：

```text
40101原始值
↓
解码
↓
执行一次PCC符号转换
↓
ControllerInput（控制器输入）
```

进入 C01～C10 后不再第二次翻转。

设备功率方向也在正式文档中统一列清：

```text
PV（光伏）
0～+1 pu

ESS（储能）
-1～+1 pu

EV（电动汽车）
-1～0 pu
```

---

# 第七章｜40101～40124读取与 ControllerInput（控制器输入）形成

每个正式100 ms周期：

```text
FC03一次完整读取
40101～40124
↓
全部解码
↓
状态/范围/有效性判断
↓
冻结为同一批 Measurement Snapshot（测量快照）
↓
形成 ControllerInput（控制器输入）
```

必须强调：

> **一次控制计算使用的数据必须来自同一次成功读取并解码后的完整快照。**

不能：

```text
PCC使用本周期
SOC使用上周期
相角使用另一个周期
```

---

# 第八章｜V3.2安全状态机与 Controller Adapter（控制器适配层）的关系

正式说明：

```text
现有V3.2三状态机
决定当前有没有资格进行真实外部控制

Controller Adapter（控制器适配层）
决定当前控制算法产生什么命令以及内部状态如何提交
```

因此：

```text
DISCONNECTED（断开）
WAIT_VALID（等待数据有效）
ENABLED（已允许外部控制）
```

仍由原工程主程序维护。

Adapter（适配层）不取代三状态机。

---

# 第九章｜Controller（控制器）启动、初始化和普通重连

程序启动顺序：

```text
controller_reset（控制器复位）
↓
建立Modbus连接
↓
得到第一批完整fresh/valid（新鲜且有效）测量
↓
获得完整配置
↓
controller_init（控制器初始化）
```

必须冻结：

```text
普通TCP reconnect（重新连接）
≠
controller_init（控制器重新初始化）
```

普通断线重连：

```text
恢复通信
↓
重新经过WAIT_VALID（等待数据有效）
↓
继续保留原算法历史状态
```

真正算法Reset（复位）由：

```text
CONTROLLER_RESET_SEQ（控制器复位序号）
```

触发。

---

# 第十章｜100 ms主循环固定顺序

正式要求中写成程序执行流程，而不是代码实现位置。

建议最终顺序：

```text
1. 维护主循环时间和BOARD_HEARTBEAT（板端心跳）

2. 确保Modbus连接状态

3. FC03读取40101～40124

4. 解码全部Measurement（测量量）

5. 执行现有状态、心跳和有效性判断

6. 检查CONFIG_SEQ（配置序号）
   如发生变化，按原子读取规则读取402xx配置

7. 形成同一批ControllerInput（控制器输入）

8. 调用controller_step（控制器单周期计算）

9. 根据返回状态选择本周期发送内容

10. 形成完整40001～40064命令帧

11. FC16一次写入完整命令帧

12. 对存在pending（待提交候选）的周期：
    FC16成功 → controller_commit（提交）
    FC16失败 → 不提交

13. 更新运行日志
```

这一章将是最终文档的核心。

---

# 第十一章｜controller_step（控制器单周期计算）返回状态处理

正式要求说明五种状态。

## `MONITOR_ONLY（仅监视）`

```text
策略可更新观测状态
不产生可投入的真实控制结果
```

## `HELD（保持）`

```text
继续保持当前正式控制内容
CMD_SEQ（命令序号）不增加
```

## `CANDIDATE（新候选）`

```text
存在新的pending（待提交候选）
↓
写入FC16
↓
成功后controller_commit（提交）
```

## `RETRY_PENDING（重试待提交候选）`

真正属于同一测量快照时：

```text
不重新计算
重复发送同一个pending
使用同一个candidate CMD_SEQ（候选命令序号）
```

## `ERROR（错误）`

```text
不提交新的控制状态
按现有安全框架处理本周期控制资格
```

---

# 第十二章｜FC16失败、pending（待提交候选）和新测量快照

正式冻结两种情况。

## 同一Measurement Snapshot（测量快照）

```text
FC16失败
↓
仍属于同一控制交易
↓
精确重试同一pending
```

## 新的fresh Measurement Snapshot（新测量快照）已经到达

```text
旧pending属于旧Plant（被控对象）状态
↓
废弃旧pending
↓
从official command state（正式命令状态）
使用最新测量重新计算
```

这是最终 BOARD15（板端15策略）安全语义。

---

# 第十三章｜CMD_SEQ（命令序号）、BOARD_HEARTBEAT（板端心跳）和外部控制使能

三者必须分开。

## BOARD_HEARTBEAT（板端心跳）

代表：

```text
板端程序持续运行
```

按照工程主循环正常更新。

## CMD_SEQ（命令序号）

代表：

```text
成功发布的新Plant控制内容版本
```

不是：

```text
100 ms周期计数器
```

也不是：

```text
每次FC16都+1
```

控制内容包括：

```text
6 Pref（有功指令）
6 Qref（无功指令）
6 GridOn（并网/构网模式）
6 Droop（下垂使能）
PCC Breaker（公共连接点断路器）
Fref trim（频率参考修正）
System Mode（系统模式）
Selected Master（选定构网主机）
```

只有新控制内容成功发布时更新 `CMD_SEQ（命令序号）`。

## 外部控制有效标志

继续由：

```text
现有V3.2安全资格
+
Adapter（适配层）已有成功正式控制结果
+
当前通信/测量/命令通道有效
```

共同决定。

---

# 第十四章｜FC03失败、测量异常和恢复处理

发生：

```text
FC03失败
测量无效
测量连续性中断
```

工程主程序调用：

```text
controller_notify_measurement_break
（通知控制器测量连续性中断）
```

处理要求：

```text
不推进新的命令状态
pending（待提交候选）清除
外部控制资格撤销
```

同时保留：

```text
已经确认的Island（孤岛）状态
Black Start（黑启动）状态
已有正式控制历史
```

普通通信恢复后：

```text
重新取得有效测量资格
↓
继续运行
```

不做：

```text
历史周期补算
```

---

# 第十五章｜Runtime Config（运行时配置）和 CONTROLLER_RESET_SEQ（控制器复位序号）

运行时配置通过：

```text
40124 CONFIG_SEQ（配置序号）
40201 CONFIG_SEQ_ECHO（配置序号回显）
40202～40280 参数
```

读取。

工程主程序负责原子读取：

```text
读取seq_before（读取前序号）
↓
读取整组402xx
↓
检查CONFIG_SEQ_ECHO（配置序号回显）
↓
再读seq_after（读取后序号）
↓
三者一致
↓
形成完整ControllerConfig（控制器配置）
↓
controller_reconfigure（控制器重新配置）
```

普通参数可以在配置边界更新。

结构型参数：

```text
P_UNIT_KW（功率基准）
PV_INIT_KW（光伏初始内部功率）
EV_INIT_KW（电动汽车初始内部充电功率）
```

需要和：

```text
CONTROLLER_RESET_SEQ（控制器复位序号）
```

一起改变。

---

# 第十六章｜40122 / 40123执行反馈处理

正式点表已经冻结：

```text
40122 EXEC_MODE_STATUS（执行模式状态位域）
40123 EXEC_SYSTEM_MODE（最终执行系统模式）
```

40122：

```text
bit0  PCC_BREAKER_CLOSED（PCC断路器已闭合）
bit1  ESS1_GRIDON（储能1 GridOn状态）
bit2  ESS2_GRIDON（储能2 GridOn状态）
bit3  ESS1_DROOP（储能1下垂状态）
bit4  ESS2_DROOP（储能2下垂状态）
bit5  SELECTED_MASTER_ESS1（构网主机为储能1）
bit6  SELECTED_MASTER_ESS2（构网主机为储能2）
bit7  MODE_OVERRIDE_ACTIVE（模式接管有效）
bit8  BREAKER_OVERRIDE_ACTIVE（断路器接管有效）
bit9  ISLAND_LATCH（孤岛锁存）
bit10 BLACKSTART_LATCH（黑启动锁存）
bit11 BOARD_ROUTE_ACTIVE（板端控制路由有效）
bit12 EXEC_ROUTE_VALID（最终执行路由有效）
bit13～15 reserved（保留）
```

40123：

```text
0 NORMAL（正常并网）
1 EMERGENCY（应急）
2 ISLANDING（正在离网）
3 ISLANDED（已孤岛）
4 BLACK_START（黑启动）
5 RESYNCHRONIZATION（重同步）
6 FAULT_SAFE（故障安全）
```

工程主程序：

```text
按UINT16（16位无符号整数）解码
↓
写入ControllerInput（控制器输入）
↓
Controller Adapter（控制器适配层）内部派生执行确认
```

工程师不需要自己再设计第二套确认算法。

---

# 第十七章｜最终 JSON（配置文件）和运行日志

最终 `JSON（配置文件）` 继续保存工程主程序需要的参数，例如：

```text
IP地址
端口
Unit ID（Modbus从站单元编号）

100 ms基础周期

连接超时
响应超时
心跳超时
重连周期

有效周期数量
连续失败阈值

日志路径
日志使能

外部控制请求

PCC符号转换系数

与最终模型固定接口有关的少量Board Integration Config
（板端集成配置）
```

15策略运行参数本身优先由：

```text
402xx Runtime Config（运行时配置）
```

提供，而不是再全部复制一份到JSON。

运行日志至少记录：

```text
时间
V3.2状态
FC03状态
FC16状态

40101～40124关键测量和执行反馈

controller_step（控制器单周期计算）结果

pending（待提交候选）状态
CMD_SEQ（命令序号）

6 Pref（有功指令）
6 Qref（无功指令）
6 GridOn（并网/构网模式）
6 Droop（下垂使能）

PCC Breaker（公共连接点断路器）
System Mode（系统模式）
Selected Master（选定构网主机）
Fref trim（频率参考修正）

CONFIG_SEQ（配置序号）
CONTROLLER_RESET_SEQ（控制器复位序号）

通信/算法错误状态
```

日志属于最终程序本身的运行功能，不作为“验收要求”表述。

---

# 5. 工程师正式文档的附件规划

正式要求建议只配少量必要附件。

## 附件A｜BOARD15（板端15策略）正式C源码包

包括：

```text
C01～C10正式 .c（C源文件）
C01～C10正式 .h（C头文件）
controller_api（控制器公共接口）
```

工程师直接加入现有程序工程。

---

## 附件B｜BOARD15（板端15策略）最终Modbus点表

当前：

```text
BOARD15_Modbus点表_RuntimeConfig_CommandFrame_V0.4_C10_EXEC_MODE_STATUS冻结.xlsx
```

作为地址、类型、缩放、单位的正式依据。

---

## 附件C｜最终 JSON（配置文件）参考模板

根据当前旧JSON升级。

工程师可继续沿用现有JSON读取机制。

---

# 6. 正式成文前还需要我们自己关闭的事项

这些事项是**我们内部需要确认的内容**，不是写给工程师去设计。

目前只剩很少几项。

## 6.1 模型侧 steady-state baseline（稳态基础模式值）

需要最终确认：

```text
baseline_grid_on（基础GridOn状态）
baseline_droop（基础下垂状态）
baseline_breaker_close（基础断路器状态）
```

当前模型已可从实际信号追踪。

最终值用于给工程师的 `Board Integration Config（板端集成配置）`。

---

## 6.2 40122 / 40123模型侧Publisher（发布信号）实现

点表语义已经冻结。

还需要我们在C11模型侧把：

```text
最终Breaker状态
最终ESS GridOn/Droop
最终Selected Master
最终Island/Black Start latch
最终Board route状态
最终System Mode
```

真正打包到40122/40123。

这不是板端工程师开发任务。

---

## 6.3 BOARD15 source=2模型路由

当前最终模型明确：

```text
source=2
```

仍是预留状态。

我们需要在C11模型侧把：

```text
Board完整命令
```

接入最终：

```text
Pref
Qref
GridOn
Droop
Breaker
Fref trim
Mode
Master
```

路由。

同样不是工程师板端程序任务。

---

# 7. 当前结论

经过C01～C10以后：

> **工程师最终要求已经不是“重新设计”，而是把已经冻结的BOARD15软件接口和运行规则整理成一份清楚的工程开发说明。**

当前17章内容已经基本成型。

下一轮可以做：

# `BOARD15最终板端控制程序设计与集成要求_V1.0.md`

正式成文时：

```text
只写最终要求
只写工程师需要实现的动作
不写验收
不写C01～C10历史
不写内部研究目的
不写无关解释
```

并且所有英文名称都会采用：

```text
English Name（中文含义）
```

的方式第一次出现即解释。
