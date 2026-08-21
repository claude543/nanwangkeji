# BOARD15（板端15策略程序）最终板端控制程序设计与集成要求 V0.2
## ——现有板端程序升级为最终100 ms BOARD15控制程序的开发要求

> **版本日期**：2026-08-20  
> **适用对象**：现有外部控制板程序的开发与集成人员。  
> **实现基础**：在现有已验证的 V3.2/V4/V5（历史板端程序版本）通信、安全状态机、自动重连、JSON（配置文件）和运行日志框架上升级。  
> **正式基础周期**：100 ms。  
> **通信协议**：Modbus TCP（Modbus传输控制协议）。  
> **RT-LAB（实时仿真平台）地址**：沿用现有工程配置，当前为 `192.168.1.100:1502`，`Unit ID（从站单元编号）=1`。  
> **寄存器正式依据**：随附 `BOARD15_Modbus点表_RuntimeConfig_CommandFrame_V0.5_工程师要求审计修正版.xlsx`。正文描述控制逻辑；寄存器地址、数据类型、缩放、单位和编码以该点表为准。

---

# 一、最终版本目标

请在现有已验证板端程序基础上集成我方提供的 BOARD15（板端15策略程序）C语言控制模块，将现有“基础AGC（自动发电控制）板端程序”升级为完整的15项微电网协调控制程序。

最终数据链路为：

```text
RT-LAB（实时仿真平台）
        ↓
FC03（Modbus读保持寄存器功能码）
40101～40124
        ↓
板端完成寄存器解码
        ↓
执行现有通信、模型状态、心跳和数据有效性判断
        ↓
形成同一周期ControllerInput（控制器输入）
        ↓
Controller Adapter（控制器适配层）
        ↓
PROJECT15 Core（PROJECT15完整控制核心）
        ↓
形成ControllerOutput（控制器输出）
        ↓
编码为40001～40064完整Command Frame（命令帧）
        ↓
FC16（Modbus写多个寄存器功能码）
        ↓
RT-LAB（实时仿真平台）
```

最终程序基础通信和控制循环周期统一为：

```text
100 ms
```

基础有功协调模块本身的更新周期继续由：

```text
TS_AGC_MS（基础AGC更新周期）
```

独立控制，当前项目基线为：

```text
1000 ms
```

因此：

```text
100 ms = 板端完整通信/控制循环周期
1000 ms = 基础AGC内部最小更新周期
```

二者不是同一个参数。

---

# 二、现有程序功能继续保留

BOARD15（板端15策略程序）直接在现有程序上扩展，继续保留以下功能：

1. Modbus TCP（Modbus传输控制协议）客户端连接；
2. FC03（读保持寄存器）；
3. FC16（写多个寄存器）；
4. `DISCONNECTED（断开）`、`WAIT_VALID（等待有效）`、`ENABLED（已允许外部控制）` 三状态安全状态机；
5. `MODEL_STATUS（模型状态）` 判断；
6. `RTLAB_HEARTBEAT（RT-LAB心跳）` 监测；
7. `BOARD_HEARTBEAT（板端心跳）`；
8. 测量解码、范围检查和有效性检查；
9. 连续有效周期后进入 `ENABLED（已允许外部控制）`；
10. 通信失败检测和自动重连；
11. 原寄存器的INT16/UINT16（16位有符号/无符号整数）处理、补码、缩放、舍入和限值；
12. JSON（配置文件）读取；
13. CSV（逗号分隔运行日志）或现有等效运行日志。

现有三状态机继续作为真实外部控制资格的最外层安全框架。

当前安全配置继续支持：

```text
valid_cycles_before_enable（投入前连续有效周期数）
默认3

model_ready_mask（模型准备掩码）
当前7

model_fault_mask（模型故障掩码）
当前16

rtlab_heartbeat_timeout_ms（RT-LAB心跳超时）
保留为JSON可配置

max_consecutive_failures（最大连续通信失败次数）
保留为JSON可配置

reconnect_interval_ms（重连间隔）
保留为JSON可配置
```

`MODEL_STATUS（模型状态）` 的基本判断继续采用：

```text
(status & model_ready_mask) == model_ready_mask
```

同时要求：

```text
(status & model_fault_mask) == 0
```

---

# 三、需要加入最终工程的BOARD15 C语言文件

将我方随最终源码包提供的下列模块加入现有C语言工程并共同编译。

## 3.1 公共接口

```text
controller_api_BOARD15_V0_1.h
```

作用：

```text
定义ControllerInput（控制器输入）
ControllerConfig（控制器配置）
ControllerOutput（控制器输出）
ControllerDiagnostics（控制器诊断）
SystemMode（系统模式）
SelectedMaster（构网主机）
以及统一设备顺序等公共接口
```

## 3.2 15策略算法模块

```text
strategy15_core_BOARD15_C01_V0_1.h/.c
15策略判断核心

p_objective_BOARD15_C02_V0_1.h/.c
有功主目标和有功约束

p_coord_baseline_BOARD15_C03_V0_2.h/.c
基础有功协调和六资源分配

p_execution_auxiliary_BOARD15_C04_V0_1.h/.c
有功执行映射、S6平滑和S8减载

q_control_BOARD15_C05_V0_1.h/.c
S3无功控制和六设备无功分配

mode_control_BOARD15_C06_V0_3.h/.c
系统运行模式、构网/跟网和PCC断路器基础控制

black_start_BOARD15_C07_V0_1.h/.c
S14黑启动分阶段有功指令控制

resynchronization_BOARD15_C08_V0_1.h/.c
S15重同步、重合闸和恢复控制

project15_core_BOARD15_C09_V0_2.h/.c
完整PROJECT15控制核心
```

## 3.3 控制器适配层

```text
controller_adapter_BOARD15_C10_V0_1.h/.c
```

作用：

```text
ControllerContext（控制器上下文）
candidate（候选状态）
pending（待提交状态）
commit（成功发布后的状态提交）
measurement break（测量连续性中断）
Runtime Config（运行时配置）
Reset（复位）
40122/40123执行反馈解析
CMD_SEQ（命令序号）管理接口
```

最终工程主程序通过 `Controller Adapter（控制器适配层）` 调用 BOARD15（板端15策略程序）。

---

# 四、六设备顺序统一

所有六设备数组统一使用以下顺序：

```text
index 0 = PV1（光伏1）
index 1 = PV2（光伏2）
index 2 = ESS1（储能1）
index 3 = ESS2（储能2）
index 4 = EV1（电动汽车1）
index 5 = EV2（电动汽车2）
```

以下所有六元素数组均保持相同顺序：

```text
Pref（有功指令）
Qref（无功指令）
GridOn（跟网/构网状态）
Droop（下垂使能）
Pmeas（实际有功）
以及相关诊断数组
```

---

# 五、最终Modbus寄存器范围

最终程序支持三个连续寄存器区域。

## 5.1 Board → RT-LAB（板端到实时仿真平台）

```text
40001～40064
```

作为一份完整 `Command Frame（命令帧）`。

主要包括：

```text
40001～40006
六设备Pref（有功指令）

40007～40009
基础AGC状态、dP和remain

40010
EXT_CONTROL_ENABLE（板端整体控制有效）

40011
CMD_SEQ（成功发布的新控制内容版本）

40012
BOARD_HEARTBEAT（板端心跳）

40013～40018
六设备Qref（无功指令）

40019
GRIDON_MASK（六设备GridOn位域）

40020
DROOP_MASK（六设备Droop位域）

40021
PCC_BREAKER_REQUEST_CLOSE（PCC断路器闭合请求）

40022
FREF_TRIM_HZ（频率参考修正）

40023
SYSTEM_MODE（板端请求系统模式）

40024
SELECTED_MASTER（选定构网主机）

40025～40030
配置状态、策略状态、控制域状态和通信状态
```

40031～40064保留在同一个固定命令帧中，用于当前诊断及后续扩展。

当前BOARD15基础版本不要求实现新的执行状态感知有功协调算法；当前未启用的未来诊断字段按照本文件第二十四章处理。

---

## 5.2 RT-LAB → Board（实时仿真平台到板端）

```text
40101～40124
```

包括：

```text
40101 PCC_P（公共连接点有功）
40102 PCC_Q（公共连接点无功）
40103 PCC_V（公共连接点电压）
40104 PCC_F（公共连接点频率）

40105 PV1_P_MAX（光伏1最大可用功率）
40106 PV2_P_MAX（光伏2最大可用功率）

40107 ESS1_SOC（储能1荷电状态）
40108 ESS2_SOC（储能2荷电状态）

40109～40114
六设备P_MEAS（实际有功）

40115 MODEL_STATUS（模型状态）
40116 RTLAB_HEARTBEAT（RT-LAB心跳）

40117 PCC_PHASE（PCC相角）
40118 GRID_V（上级电网电压）
40119 GRID_F（上级电网频率）
40120 GRID_PHASE（上级电网相角）
40121 PHASE_VALID（相角有效）

40122 EXEC_MODE_STATUS（最终执行状态位域）
40123 EXEC_SYSTEM_MODE（最终执行系统模式）

40124 CONFIG_SEQ（运行时配置序号）
```

---

## 5.3 Runtime Config（运行时配置）

```text
40201～40280
```

用于BOARD15控制器的运行参数和配置。

参数组包括：

```text
Framework（控制框架参数）
Baseline AGC（基础有功协调参数）
Strategy（15策略参数）
S15 Resynchronization（重同步参数）
Future Reserved（未来算法预留）
Controller Reset（控制器复位）
```

具体寄存器地址、类型和缩放以随附点表为准。

---

# 六、PCC和设备功率方向

BOARD15（板端15策略程序）算法内部统一采用：

```text
PCC P > 0
= 微电网向上级电网送电

PCC P < 0
= 微电网从上级电网购电
```

现有40101线端方向继续沿用历史定义：

```text
40101 > 0
= 购电

40101 < 0
= 外送
```

主程序在40101解码后、写入 `ControllerInput.pcc_p_kw（控制器输入PCC有功）` 前执行一次：

```text
PCC_P_for_controller
=
pcc_sign_gain（PCC符号转换系数）
×
PCC_P_decoded
```

当前：

```text
pcc_sign_gain = -1.0
```

进入BOARD15控制模块以后不再第二次翻转。

设备有功指令统一：

```text
PV（光伏）
0 ～ +1 pu（标幺）

ESS（储能）
-1 ～ +1 pu
正值=放电
负值=充电

EV（电动汽车）
-1 ～ 0 pu
负值=充电
0=不充电
```

---

# 七、每100 ms形成一份完整Measurement Snapshot（测量快照）

每个基础循环进行一次：

```text
FC03
读取40101～40124
```

完成：

```text
响应功能码和长度检查
↓
全部寄存器解码
↓
MODEL_STATUS（模型状态）检查
↓
RTLAB_HEARTBEAT（RT-LAB心跳）检查
↓
信号合法性和范围检查
↓
形成同一批Measurement Snapshot（测量快照）
```

一次BOARD15控制计算中的全部动态输入使用同一份测量快照。

禁止在一次 `ControllerInput（控制器输入）` 中混合不同控制周期的数据。

---

# 八、ControllerInput（控制器输入）填写要求

`ControllerInput（控制器输入）` 使用解码后的工程量，不传入Modbus原始整数。

主要字段如下：

```text
monotonic_time_s
本测量快照对应的板端单调时间

pcc_p_kw
PCC有功，进入算法前已完成方向转换

pcc_q_kvar
PCC无功

pcc_v_rms_v
PCC电压

pcc_freq_hz
PCC频率

pcc_phase_deg
PCC相角

grid_v_rms_v
上级电网电压

grid_freq_hz
上级电网频率

grid_phase_deg
上级电网相角

phase_valid
相角有效标志

pv_max_kw[2]
两路光伏最大可用功率

ess_soc[2]
两路储能SOC（荷电状态）

p_meas_kw[6]
六设备实际有功

exec_mode_status_raw
40122原始执行状态位域

exec_system_mode
40123最终系统模式

snapshot_fresh
当前是否为新的有效测量快照

snapshot_transport_valid
当前FC03传输是否完整有效

signal_valid_mask
各输入信号有效位域

measurement_channel_valid
当前测量通道是否有效

command_channel_valid
当前完整命令帧是否具备发布条件

controller_enabled
现有V3.2安全状态是否已允许真实控制

comm_ok_for_strategy
当前策略使用的通信状态

model_status_raw
40115原始MODEL_STATUS

rtlab_heartbeat
40116 RTLAB_HEARTBEAT
```

控制算法时间统一使用：

```text
monotonic clock（单调时钟）
```

不使用系统日期时间。

---

# 九、signal_valid_mask（信号有效位域）

位定义按照公共接口：

```text
bit0  PCC_P有效
bit1  PCC_Q有效
bit2  PCC_V有效
bit3  PCC_F有效
bit4  PV_MAX有效
bit5  ESS_SOC有效
bit6  P_MEAS有效
bit7  GRID_V有效
bit8  GRID_F有效
bit9  PCC_PHASE有效
bit10 GRID_PHASE有效
bit11 PHASE_VALID信号有效
bit12 EXEC_MODE_STATUS有效
bit13 EXEC_SYSTEM_MODE有效
bit14 MODEL_STATUS有效
bit15 RTLAB_HEARTBEAT有效
```

当前BOARD15 BASELINE（基础版本）控制所需的必需有效位为：

```text
bit0～bit5
bit7～bit15
```

即：

```text
bit6 P_MEAS
```

当前不是BASELINE控制资格的强制条件。

40109～40114六设备P_MEAS仍需正常读取、解码并写入运行日志。

---

# 十、V3.2安全状态机和Controller Adapter（控制器适配层）的关系

现有：

```text
DISCONNECTED（断开）
WAIT_VALID（等待有效）
ENABLED（已允许外部控制）
```

继续由工程主程序维护。

`controller_enabled（控制器允许状态）` 只有在现有安全状态机已经进入 `ENABLED（已允许外部控制）` 时置1。

`external_enable_request（外部控制投入请求）` 继续保留在JSON（配置文件）中，作为现有状态机进入 `ENABLED（已允许外部控制）` 的必要条件。

40205：

```text
CONTROL_MASTER_ENABLE（板端控制总使能）
```

属于BOARD15运行时配置，控制PROJECT15是否允许真实执行。

因此最终真实控制资格同时受到：

```text
V3.2外部安全状态
+
external_enable_request（外部控制请求）
+
CONTROL_MASTER_ENABLE（板端控制总使能）
+
Controller Adapter（控制器适配层）正式状态
```

约束。

---

# 十一、程序启动流程

程序进程启动后：

```text
1.
controller_reset（控制器启动级复位）

2.
建立Modbus TCP（通信）连接

3.
进入WAIT_VALID（等待有效）

4.
读取并解码完整40101～40124

5.
建立RTLAB_HEARTBEAT（RT-LAB心跳）有效性

6.
取得一份完整fresh/valid（新鲜且有效）的Measurement Snapshot（测量快照）

7.
取得一份完整且合法的ControllerConfig（控制器配置）

8.
调用controller_init（控制器初始化）
```

`controller_reset（控制器启动级复位）` 和 `controller_init（控制器初始化）` 属于进程启动流程。

已经完成初始化后，普通Modbus断线和自动重连过程中不再次调用这两个启动接口。

---

# 十二、100 ms主循环固定顺序

每个100 ms基础周期按照以下顺序执行。

```text
1.
更新时间和BOARD_HEARTBEAT（板端心跳）

2.
确认TCP连接状态；
必要时执行现有重连逻辑

3.
FC03读取40101～40124

4.
完成全部寄存器解码

5.
检查：
MODEL_STATUS
RTLAB_HEARTBEAT
测量范围
枚举
相角有效
执行反馈有效
以及本周期数据完整性

6.
更新现有：
DISCONNECTED
WAIT_VALID
ENABLED
状态

7.
检查40124 CONFIG_SEQ（配置序号）

如发现新配置：
按照第十八章的原子协议读取40201～40280；
在新配置完整应用前继续保留原正式配置

8.
冻结本周期Measurement Snapshot（测量快照）
并形成ControllerInput（控制器输入）

9.
调用controller_step（控制器单周期计算）

10.
根据返回状态选择本周期控制内容

11.
编码40001～40064完整Command Frame（命令帧）

12.
通过一次FC16发送40001～40064

13.
如果本周期存在pending（待提交候选）并且对应完整FC16成功：
调用controller_commit（提交）

14.
更新运行日志
```

完整FC16对应的是：

```text
40001～40064整帧成功
```

只有整帧成功才允许提交与该帧对应的pending状态。

---

# 十三、controller_step（控制器单周期计算）五种返回状态

## 13.1 MONITOR_ONLY（仅监视）

表示当前允许使用新测量更新策略观测状态，但不形成可投入的新真实控制状态。

如果命令通道仍可用，本周期继续发送完整工程帧：

```text
EXT_CONTROL_ENABLE = 0
CMD_SEQ保持当前正式值
BOARD_HEARTBEAT正常更新
```

控制量优先保留最近一次成功committed（已提交）的正式控制结果；程序启动后从未形成正式结果时使用初始化安全值。

不调用 `controller_commit（提交）`。

---

## 13.2 HELD（保持）

表示当前控制器没有新的命令状态需要提交。

本周期继续发送当前正式控制内容：

```text
CMD_SEQ不变
BOARD_HEARTBEAT继续更新
```

`EXT_CONTROL_ENABLE（外部控制有效）` 根据当前完整安全资格决定。

---

## 13.3 CANDIDATE（新候选）

表示Adapter（适配层）已经保存一份新的：

```text
pending（待提交候选）
```

使用返回的 `ControllerOutput（控制器输出）` 形成当前40001～40064。

候选CMD_SEQ通过：

```text
controller_tx_cmd_seq（取得当前待发送命令序号）
```

获取。

FC16成功后：

```text
controller_commit（提交）
```

FC16失败：

```text
不controller_commit
```

---

## 13.4 RETRY_PENDING（重试待提交候选）

表示本次调用仍属于原先同一Measurement Snapshot（测量快照）对应的未完成发送交易。

本周期：

```text
使用完全相同的pending ControllerOutput
使用相同candidate CMD_SEQ
不重新推进命令状态
不重复更新Observation（观测状态）
```

工程主程序在真正进行“同一Snapshot重试”时，必须复用原先保存的那一份 `ControllerInput（控制器输入）`，包括：

```text
原RTLAB_HEARTBEAT
原monotonic_time_s
```

不能重新生成新的快照时间。

---

## 13.5 ERROR（错误）

本周期不提交新的控制器状态。

如果命令通道仍可写，本周期发送：

```text
EXT_CONTROL_ENABLE = 0
CMD_SEQ保持
BOARD_HEARTBEAT更新
```

并记录对应错误状态。

如果错误发生在本地编码或完整帧形成阶段，放弃该未发布候选：

```text
controller_abort_pending（放弃待提交候选）
```

---

# 十四、同一Snapshot重试与新Snapshot到来的处理

需要严格区分下面两种情况。

## 14.1 同一Measurement Snapshot（测量快照）

FC16失败后，如果尚未接受新的40101～40124测量快照，可继续针对原Snapshot执行真正的发送重试。

此时：

```text
不重新计算
不推进控制器命令状态
不改变candidate CMD_SEQ
```

---

## 14.2 已接受新的fresh Measurement Snapshot（新测量快照）

如果上一份pending尚未成功发布，但已经取得并接受了新的完整Measurement Snapshot，则上一份pending属于旧Plant（被控对象）状态。

本周期仍正常调用：

```text
controller_step
```

Adapter（适配层）会废弃旧pending，并从：

```text
official command state（正式命令状态）
```

出发，使用最新测量重新形成控制结果。

特别对于：

```text
PCC Breaker（断路器）
System Mode（系统模式）
Black Start（黑启动）
Resynchronization（重同步）
```

不得在已经接受新Plant状态以后继续无条件重发旧动作。

---

# 十五、FC03失败、测量无效和通信恢复

发生：

```text
FC03失败
响应数量/格式错误
测量无效
Measurement Snapshot连续性中断
```

时，调用：

```text
controller_notify_measurement_break
（通知控制器测量连续性中断）
```

并执行：

```text
本周期不推进新的命令状态
清除未发布pending
EXT_CONTROL_ENABLE退出
CMD_SEQ保持
```

如果TCP命令通道仍然可用，可以继续发送完整安全状态帧：

```text
最近committed控制量或初始化安全值
+
EXT_CONTROL_ENABLE=0
+
当前BOARD_HEARTBEAT
+
当前工程状态字段
```

连接完全断开时进入现有 `DISCONNECTED（断开）` 流程。

普通通信恢复：

```text
重新连接
↓
WAIT_VALID
↓
重新连续验证数据
↓
恢复ENABLED
```

期间：

```text
不controller_reset
不controller_init
不补算断线期间控制周期
```

Controller Adapter（控制器适配层）会在首个fresh有效快照对需要连续时间证据的内部状态执行重新对齐。

---

# 十六、40010 EXT_CONTROL_ENABLE（外部整体控制有效）

40010继续沿用旧地址，但最终名称和语义为：

```text
EXT_CONTROL_ENABLE（外部整体控制有效）
```

它不再只代表AGC。

只有同时满足以下条件时，本周期才允许写1：

```text
1. V3.2状态=ENABLED
2. external_enable_request=true
3. CONTROL_MASTER_ENABLE=1
4. Controller Adapter已初始化
5. 已存在至少一份成功committed的完整控制结果
6. 当前Measurement Snapshot有效
7. measurement_channel_valid=1
8. command_channel_valid=1
9. 当前正式ControllerConfig合法
10. 当前无导致控制输出无效的算法/编码错误
```

可直接使用：

```text
controller_external_control_ready
（控制器外部控制准备状态）
```

提供Adapter侧条件，并与现有V3.2安全状态共同形成40010。

`AGC_ENABLE（自动发电控制使能）` 只控制基础有功协调子模块，不作为40010整体控制有效的单独必要条件。

程序启动或运行时Reset后，在第一份新的完整控制结果成功发布以前：

```text
40010 = 0
```

第一份candidate成功FC16并 `controller_commit（提交）` 后，从后续周期开始，在其它条件仍满足时40010才可以置1。

---

# 十七、CMD_SEQ（命令序号）与BOARD_HEARTBEAT（板端心跳）

## 17.1 BOARD_HEARTBEAT（板端心跳）

表示板端程序主循环持续运行。

按照现有程序方式连续更新，最终周期为100 ms。

即使：

```text
HELD
MONITOR_ONLY
ERROR
或同一pending重试
```

只要主程序仍正常运行，BOARD_HEARTBEAT继续按工程逻辑更新。

---

## 17.2 CMD_SEQ（命令序号）

表示：

```text
成功发布的新Plant控制内容版本
```

Plant控制内容包括：

```text
6 Pref
6 Qref
6 GridOn
6 Droop
PCC Breaker
Fref trim
System Mode
Selected Master
```

只有新的Plant控制内容成功通过完整FC16发布并提交以后，正式CMD_SEQ更新。

以下情况CMD_SEQ不增加：

```text
HELD
MONITOR_ONLY
ERROR
FC16失败
同一pending重试
内部算法状态变化但编码后的Plant控制内容不变
```

即使CMD_SEQ不增加，完整40001～40064仍按正常100 ms通信周期发送。

---

# 十八、Runtime Config（运行时配置）原子读取

40124：

```text
CONFIG_SEQ（配置序号）
```

表示当前完整运行配置版本。

当检测到新的CONFIG_SEQ时：

```text
1.
读取40124
保存seq_before

2.
读取40201～40280完整配置块

3.
读取40201 CONFIG_SEQ_ECHO（配置序号回显）

4.
再次读取40124
保存seq_after

5.
只有：
seq_before
=
CONFIG_SEQ_ECHO
=
seq_after
时，
本次配置块才作为一份完整候选配置

6.
完成数据类型、范围、枚举和逻辑合法性检查

7.
调用controller_reconfigure（控制器重新配置）

8.
成功应用以后更新40025 CONFIG_APPLIED_SEQ
```

在新的完整配置正式成功应用以前：

```text
继续使用上一份正式ControllerConfig
```

不允许使用一半新、一半旧的参数进行控制。

---

# 十九、配置状态寄存器

## 19.1 40025 CONFIG_APPLIED_SEQ（已应用配置序号）

写入当前已经正式应用的：

```text
config_seq
```

## 19.2 40026 CONFIG_STATUS（配置状态）

```text
0
当前无新的配置应用结果

1
新配置已成功应用

-1
本次配置非法或被控制器拒绝
```

配置非法时：

```text
保持上一份正式配置继续生效
```

## 19.3 40027 P_COORDINATION_MODE_STATUS（有功协调方式状态）

写入当前控制器实际运行的有功协调方式。

当前正式版本：

```text
0 = BASELINE（基础有功协调）
```

当前C语言程序尚未集成：

```text
1 = EXECUTION_AWARE（执行状态感知有功协调）
```

如果40202设置为当前未支持的模式，本次配置按非法配置处理，不静默回退。

---

# 二十、CONTROLLER_RESET_SEQ（控制器复位序号）

40280：

```text
CONTROLLER_RESET_SEQ（控制器复位序号）
```

用于显式重建算法状态。

运行时Reset流程通过：

```text
controller_reconfigure（控制器重新配置）
```

完成。

检测到RESET_SEQ变化后，Adapter（适配层）执行：

```text
清除pending
重建Observation State（观测状态）
重建Command State（命令状态）
清除旧committed控制结果的有效资格
保留CMD_SEQ连续性
保持ControllerContext（控制器上下文）已初始化
```

随后首个fresh有效Measurement Snapshot由Adapter自动完成重新对齐并重新形成新的候选控制结果。

运行时Reset不调用启动级：

```text
controller_reset
controller_init
```

下列结构型参数发生变化时，要求同时变化CONTROLLER_RESET_SEQ：

```text
P_UNIT_KW（功率基准）
PV_INIT_KW（光伏内部初值）
EV_INIT_KW（电动汽车内部充电初值）
```

系统已经处于：

```text
ISLANDED（已孤岛）
RESYNCHRONIZATION（重同步）
BLACK_START（黑启动）
```

时，如需改变当前构网主机配置，也通过显式Reset后应用新配置。

普通TCP重新连接不改变CONTROLLER_RESET_SEQ。

---

# 二十一、40122 EXEC_MODE_STATUS（最终执行状态位域）

40122按 `UINT16（16位无符号整数）` 解码：

```text
bit0
PCC_BREAKER_CLOSED
PCC断路器最终已闭合

bit1
ESS1_GRIDON
储能1最终GridOn状态
1=GFL（跟网）
0=GFM（构网）

bit2
ESS2_GRIDON
储能2最终GridOn状态

bit3
ESS1_DROOP
储能1最终下垂使能

bit4
ESS2_DROOP
储能2最终下垂使能

bit5
SELECTED_MASTER_ESS1
最终构网主机为ESS1

bit6
SELECTED_MASTER_ESS2
最终构网主机为ESS2

bit7
MODE_OVERRIDE_ACTIVE
最终模式接管有效

bit8
BREAKER_OVERRIDE_ACTIVE
最终PCC断路器接管有效

bit9
ISLAND_LATCH
最终孤岛锁存存在

bit10
BLACKSTART_LATCH
最终黑启动锁存存在

bit11
BOARD_ROUTE_ACTIVE
RT-LAB当前最终采用BOARD15控制路由

bit12
EXEC_ROUTE_VALID
最终BOARD15模式/断路器执行路由有效

bit13～15
RESERVED
保留
```

bits5和6不能同时作为两个有效主机使用。

原始40122写入：

```text
ControllerInput.exec_mode_status_raw
```

`Controller Adapter（控制器适配层）` 根据40122和40123自动派生：

```text
blackstart_execution_confirmed
island_mode_confirmed
breaker_closed_confirmed
normal_mode_confirmed
```

---

# 二十二、40123 EXEC_SYSTEM_MODE（最终执行系统模式）

40123按以下枚举写入：

```text
0
NORMAL（正常并网）

1
EMERGENCY（并网应急）

2
ISLANDING（正在离网）

3
ISLANDED（已孤岛）

4
BLACK_START（黑启动）

5
RESYNCHRONIZATION（重同步）

6
FAULT_SAFE（故障安全）
```

写入：

```text
ControllerInput.exec_system_mode
```

该值表示RT-LAB最终实际执行模式，不是板端40023请求值的简单回显。

---

# 二十三、ControllerOutput（控制器输出）到40001～40024

`controller_step（控制器单周期计算）` 的主要控制输出按照点表编码：

```text
pref_pu[6]
→ 40001～40006

agc_status
→ 40007

agc_dp_kw
→ 40008

agc_remain_kw
→ 40009

qref_pu[6]
→ 40013～40018

grid_on[6]
→ 40019 GRIDON_MASK

droop_enable[6]
→ 40020 DROOP_MASK

pcc_breaker_request_close
→ 40021

fref_trim_hz
→ 40022

system_mode
→ 40023

selected_master
→ 40024
```

40019和40020中六设备bit顺序统一：

```text
bit0 PV1
bit1 PV2
bit2 ESS1
bit3 ESS2
bit4 EV1
bit5 EV2
```

输出编码前继续进行：

```text
finite（有限数）检查
数据类型检查
缩放
舍入
寄存器范围检查
```

编码失败时：

```text
不commit
EXT_CONTROL_ENABLE=0
controller_abort_pending
记录错误
```

---

# 二十四、40028～40064诊断与预留字段

## 24.1 40028 STRATEGY_ACTIVE_MASK（活动策略位域）

来自：

```text
ControllerDiagnostics.strategy_active_mask
```

bit0～bit14对应S1～S15。

---

## 24.2 40029 DOMAIN_VALID_MASK（控制域有效位域）

按照C09 V0.2正式定义：

```text
bit0 P_DOMAIN_VALID（有功域有效）
bit1 Q_DOMAIN_VALID（无功域有效）
bit2 MODE_DOMAIN_VALID（基础模式域有效）
bit3 BLACKSTART_DOMAIN_VALID（黑启动域有效）
bit4 RESYNC_DOMAIN_VALID（重同步恢复域有效）
bit5 FINAL_MODE_ROUTE_VALID（最终模式重路由有效）
```

---

## 24.3 40030 COMM_STATUS（通信与工程状态位域）

由工程主程序生成：

```text
bit0 TCP_CONNECTED（TCP连接存在）
bit1 LAST_FC03_OK（最近一次FC03成功）
bit2 MEASUREMENT_FRESH（测量快照新鲜）
bit3 MEASUREMENT_VALID（测量有效）
bit4 LAST_FC16_OK（最近一次FC16成功）
bit5 COMMAND_CHANNEL_VALID（命令通道有效）
bit6 CONTROLLER_ENABLED（V3.2当前允许控制）
bit7 HAS_COMMITTED_COMMAND（已有正式提交控制结果）
bit8 STATE_WAIT_VALID（当前WAIT_VALID）
bit9 STATE_DISCONNECTED（当前DISCONNECTED）
bit10 CONFIG_VALID（当前正式配置有效）
bit11 CONFIG_UPDATE_PENDING（新配置正在读取/应用）
bit12 CYCLE_OVERRUN（最近一个完整循环超过100 ms）
```

---

## 24.4 40031～40062

这些地址保持在固定命令帧中，以保证后续算法扩展不需要重新修改Modbus框架。

当前BASELINE（基础版本）：

```text
按ControllerDiagnostics已有对应字段编码
```

当前未启用的执行状态感知诊断字段保持0或控制器返回的默认值。

其中：

```text
40060 PCC_RX_KW
写当前Board实际用于控制计算的PCC有功

40061 METHOD_VARIANT_STATUS
当前正式版本写0 BASELINE

40062 RECON_EVENT_SEQ
当前BASELINE版本写0
```

---

## 24.5 40063～40064

当前作为通用预留诊断字段：

```text
写0
```

---

# 二十五、当前Runtime Config（运行时配置）支持边界

当前正式C语言程序支持：

```text
40202 P_COORDINATION_MODE
只能为0 BASELINE
```

以及：

```text
40257 METHOD_VARIANT
只能为0 BASELINE
```

当前如果配置为未支持的其它值：

```text
controller_reconfigure返回配置错误
40026 CONFIG_STATUS = -1
保持上一份正式配置继续运行
```

40258～40279为后续算法预留配置字段。

当前版本读取完整40201～40280配置块时保留这些位置，但它们不驱动当前15策略BASELINE控制逻辑。

---

# 二十六、Runtime Config和JSON的参数来源划分

最终程序只保留一个算法运行参数来源：

```text
40201～40280 Runtime Config
```

包括：

```text
P目标和AGC参数
SOC上下限
15策略阈值
AVC无功参数
防逆流参数
削峰填谷参数
S15同步参数
黑启动/孤岛主机
策略Enable
控制总Enable
Reset Seq
```

旧JSON中下列AGC参数如果为了兼容旧程序结构继续保留，不再作为BOARD15正式运行参数覆盖402xx：

```text
p_target_kw
p_unit_kw
p_dead_kw
soc_min
soc_max
ts_agc_s
pv_init_kw
ev_init_kw
```

JSON继续作为工程配置来源，保存：

```text
ip
port
unit_id

send_interval_ms

connect_timeout_ms
response_timeout_ms
rtlab_heartbeat_timeout_ms

valid_cycles_before_enable
max_consecutive_failures
reconnect_interval_ms

model_ready_mask
model_fault_mask

external_enable_request

pcc_sign_gain

日志开关和日志路径

以及Project15IntegrationConfig
（PROJECT15固定集成配置）
```

最终建议运行模式标识设为：

```text
algorithm_mode = "board15"
```

最终：

```text
send_interval_ms = 100
```

---

# 二十七、Project15IntegrationConfig（PROJECT15固定集成配置）

Controller Adapter需要一份固定集成配置：

```text
baseline_grid_on[6]
六设备正常模式基础GridOn

baseline_droop[6]
六设备正常模式基础Droop

baseline_breaker_close
正常模式基础PCC断路器状态
```

这些参数由随最终程序包提供的JSON或固定集成配置附件提供。

工程主程序读取后传给：

```text
controller_init
```

对应的 `Project15IntegrationConfig（PROJECT15集成配置）`。

运行过程中不在算法模块内部自行改变这些基础值。

---

# 二十八、配置状态和控制状态的日志

最终运行日志至少记录：

```text
monotonic_time（单调时间）

DISCONNECTED / WAIT_VALID / ENABLED状态

FC03结果
FC16结果

RTLAB_HEARTBEAT
BOARD_HEARTBEAT

PCC P/Q/V/f/phase
Grid V/f/phase
phase_valid

PVmax
ESS SOC
六设备Pmeas

40122 EXEC_MODE_STATUS
40123 EXEC_SYSTEM_MODE

controller_step返回状态

has_pending
has_committed_command

CMD_SEQ
CONFIG_SEQ
CONFIG_APPLIED_SEQ
CONFIG_STATUS
CONTROLLER_RESET_SEQ

6 Pref
6 Qref
GRIDON_MASK
DROOP_MASK
PCC Breaker
Fref trim
System Mode
Selected Master

STRATEGY_ACTIVE_MASK
DOMAIN_VALID_MASK
COMM_STATUS

当前通信错误
配置错误
控制器错误
编码错误
```

日志使用解码后的工程量，并保留必要的原始状态字用于问题定位。

---

# 二十九、最终工程基础JSON调整

当前旧配置中的基础网络参数继续沿用，例如：

```json
{
  "ip": "192.168.1.100",
  "port": 1502,
  "unit_id": 1,
  "send_interval_ms": 100,
  "connect_timeout_ms": 1000,
  "response_timeout_ms": 800,
  "rtlab_heartbeat_timeout_ms": 3500,
  "external_enable_request": true,
  "valid_cycles_before_enable": 3,
  "max_consecutive_failures": 3,
  "reconnect_interval_ms": 1000,
  "model_ready_mask": 7,
  "model_fault_mask": 16,
  "pcc_sign_gain": -1.0,
  "algorithm_mode": "board15"
}
```

最终JSON中：

```text
read_points（读取点表）
扩展为40101～40124

write_points（写入点表）
扩展为40001～40064
```

运行时40201～40280配置读取可以按照现有JSON驱动点表方式增加独立配置点组，或按照现有程序结构实现连续配置块读取。

无论采用哪种程序组织方式，最终线端地址、类型、缩放和单位均以随附Modbus点表为准。

---

# 三十、最终程序运行关系

最终程序运行时的控制关系固定为：

```text
现有Engineering Main Program（工程主程序）
负责：
Modbus通信
三状态安全框架
心跳
数据解码/编码
JSON
Runtime Config原子读取
100 ms调度
日志

        ↓

Controller Adapter（控制器适配层）
负责：
控制状态生命周期
candidate / pending / commit
measurement break
Reset
执行反馈解析

        ↓

PROJECT15 Core（完整15策略控制核心）
负责：
15策略判断
有功目标/约束
六资源有功协调
S6/S8
S3无功
Mode
Black Start
Resynchronization

        ↓

ControllerOutput（控制器输出）

        ↓

工程主程序编码为40001～40064
        ↓
FC16
        ↓
RT-LAB
```

最终板端程序与RT-LAB通过100 ms双向通信形成完整实时闭环。
