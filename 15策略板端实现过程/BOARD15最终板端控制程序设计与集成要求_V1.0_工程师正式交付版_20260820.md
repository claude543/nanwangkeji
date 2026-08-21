# BOARD15（板端15策略程序）最终板端控制程序设计与集成要求 V1.0
## ——现有板端程序升级为最终100 ms BOARD15控制程序的开发要求

> **版本日期**：2026-08-20  
> **适用对象**：外部控制板程序开发与集成人员。  
> **实现基础**：在现有已验证 V3.2/V4/V5（历史板端程序版本）的 Modbus TCP（Modbus传输控制协议）、安全状态机、自动重连、JSON（配置文件）和运行日志框架上升级。  
> **正式基础周期**：100 ms。  
> **通信协议**：Modbus TCP（Modbus传输控制协议）。  
> **当前RT-LAB（实时仿真平台）地址**：`192.168.1.100:1502`。  
> **Unit ID（从站单元编号）**：1。  
> **正式寄存器依据**：`BOARD15_Modbus点表_V0.8_工程师最终终审版_20260820.xlsx`。正文描述程序逻辑；寄存器地址、数据类型、缩放、单位和编码以该点表为准。

---

# 一、最终程序目标

请在现有已验证板端程序基础上集成我方提供的 BOARD15（板端15策略程序）C语言控制模块，将现有基础 AGC（自动发电控制）程序升级为完整的15项微电网协调控制程序。

最终数据链路如下：

```text
RT-LAB（实时仿真平台）
        ↓
FC03（Modbus读保持寄存器功能码）
读取40101～40124
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

最终板端程序正常运行时，每100 ms完成一次完整通信和控制循环。

基础有功协调模块内部更新周期继续由：

```text
TS_AGC_MS（基础AGC更新周期）
```

独立控制。

当前项目基线：

```text
100 ms
=
完整Board（板端）通信和控制循环周期

1000 ms
=
基础AGC内部最小更新周期
```

两者分别管理，不互相替代。

---

# 二、现有程序基础功能继续保留

BOARD15（板端15策略程序）直接在现有程序上扩展，继续保留：

1. Modbus TCP（Modbus传输控制协议）客户端；
2. FC03（读保持寄存器）；
3. FC16（写多个寄存器）；
4. `DISCONNECTED（断开）`、`WAIT_VALID（等待有效）`、`ENABLED（已允许外部控制）` 三状态安全状态机；
5. `MODEL_STATUS（模型状态）` 判断；
6. `RTLAB_HEARTBEAT（RT-LAB心跳）` 监测；
7. `BOARD_HEARTBEAT（板端心跳）`；
8. 测量解码、范围检查和有效性判断；
9. 连续有效周期后进入 `ENABLED（已允许外部控制）`；
10. 通信失败检测和自动重连；
11. INT16/UINT16（16位有符号/无符号整数）转换、补码、缩放、舍入和限值；
12. JSON（配置文件）读取；
13. CSV（逗号分隔文件）或现有等效运行日志。

现有三状态安全框架继续作为真实外部控制资格的最外层判断。

继续支持：

```text
valid_cycles_before_enable（投入前连续有效周期数）
默认3

model_ready_mask（模型准备状态掩码）
当前7

model_fault_mask（模型故障状态掩码）
当前16

rtlab_heartbeat_timeout_ms（RT-LAB心跳超时）
JSON可配置

max_consecutive_failures（最大连续通信失败次数）
JSON可配置

reconnect_interval_ms（重连间隔）
JSON可配置
```

`MODEL_STATUS（模型状态）` 的基本判断继续采用：

```text
(status & model_ready_mask)
==
model_ready_mask
```

同时：

```text
(status & model_fault_mask)
==
0
```

---

# 三、最终工程需要加入的C语言控制模块

将随最终源码包提供的下列 `.c（C源文件）` 和 `.h（C头文件）` 加入现有工程共同编译。

## 3.1 公共接口

```text
controller_api_BOARD15_V0_1.h
（控制器公共接口定义）
```

用于定义：

```text
ControllerInput（控制器输入）
ControllerConfig（控制器配置）
ControllerOutput（控制器输出）
ControllerDiagnostics（控制器诊断）
SystemMode（系统模式）
SelectedMaster（构网主机）
设备顺序和状态码
```

## 3.2 PROJECT15（完整15策略）算法模块

```text
strategy15_core_BOARD15_C01_V0_1.h/.c
（15策略判断核心）

p_objective_BOARD15_C02_V0_1.h/.c
（有功主目标与有功约束）

p_coord_baseline_BOARD15_C03_V0_2.h/.c
（基础有功协调和六资源分配）

p_execution_auxiliary_BOARD15_C04_V0_1.h/.c
（有功执行映射、S6平滑和S8减载）

q_control_BOARD15_C05_V0_1.h/.c
（S3无功控制和六设备无功分配）

mode_control_BOARD15_C06_V0_3.h/.c
（系统模式、构网/跟网和PCC断路器基础控制）

black_start_BOARD15_C07_V0_1.h/.c
（S14黑启动分阶段有功控制）

resynchronization_BOARD15_C08_V0_1.h/.c
（S15重同步、重合闸和恢复控制）

project15_core_BOARD15_C09_V0_2.h/.c
（完整PROJECT15控制核心）
```

## 3.3 Controller Adapter（控制器适配层）

```text
controller_adapter_BOARD15_C10_V0_1.h/.c
（控制器适配层）
```

用于实现：

```text
ControllerContext（控制器上下文）
candidate（候选状态）
pending（待提交状态）
commit（提交）
abort（放弃待提交状态）
measurement break（测量连续性中断）
Runtime Config（运行时配置）
Reset（复位）
40122/40123执行反馈解析
CMD_SEQ（命令序号）管理接口
```

工程主程序通过 Controller Adapter（控制器适配层）调用完整 BOARD15（板端15策略程序）。

---

# 四、统一设备顺序

所有六设备数组统一采用：

```text
index 0 = PV1（光伏1）
index 1 = PV2（光伏2）
index 2 = ESS1（储能1）
index 3 = ESS2（储能2）
index 4 = EV1（电动汽车1）
index 5 = EV2（电动汽车2）
```

下列数组全部保持相同顺序：

```text
Pref（有功指令）
Qref（无功指令）
GridOn（跟网/构网状态）
Droop（下垂使能）
Pmeas（实际有功）
以及六设备相关诊断数组
```

---

# 五、最终Modbus（通信寄存器）区域

## 5.1 Board → RT-LAB（板端到实时仿真平台）

```text
40001～40064
```

每个正常100 ms周期使用一次完整 FC16（写多个寄存器）发送。

主要控制字段：

```text
40001～40006
六设备Pref（有功指令）

40007～40009
基础AGC状态、dP和remain

40010
EXT_CONTROL_ENABLE（板端整体控制有效）

40011
CMD_SEQ（命令序号）

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
配置、策略、控制域和通信状态

40031～40064
当前诊断和后续扩展预留
```

---

## 5.2 RT-LAB → Board（实时仿真平台到板端）

```text
40101～40124
```

每个正常100 ms周期使用一次完整 FC03（读保持寄存器）读取。

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
40121 PHASE_VALID（相角有效标志）

40122 EXEC_MODE_STATUS（最终执行状态位域）
40123 EXEC_SYSTEM_MODE（最终执行系统模式）

40124 CONFIG_SEQ（运行时配置序号）
```

---

## 5.3 Runtime Config（运行时配置）

```text
40201～40280
```

用于BOARD15运行参数和控制配置。

当前包括：

```text
Framework（控制框架参数）
Baseline AGC（基础有功协调参数）
Strategy（15策略参数）
S15 Resynchronization（重同步参数）
Future Reserved（未来预留参数）
Controller Reset（控制器复位参数）
```

具体地址、类型和缩放按附带点表实现。

---

# 六、PCC和六设备功率方向

BOARD15算法内部统一：

```text
PCC P > 0
=
微电网向上级电网送电

PCC P < 0
=
微电网从上级电网购电
```

40101继续沿用历史线端方向：

```text
40101 > 0
=
购电

40101 < 0
=
外送
```

因此主程序在40101完成寄存器解码后、写入：

```text
ControllerInput.pcc_p_kw
（控制器输入中的PCC有功）
```

以前，只执行一次：

```text
PCC_P_for_controller
=
pcc_sign_gain（PCC符号转换系数）
×
PCC_P_decoded（PCC解码值）
```

当前：

```text
pcc_sign_gain = -1.0
```

进入BOARD15 C语言模块以后不再第二次翻转。

六设备有功指令方向：

```text
PV（光伏）
0 ～ +1 pu（标幺值）

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

# 七、100 ms主循环调度规则

正式基础目标周期：

```text
100 ms
```

主循环采用板端 `monotonic clock（单调时钟）` 进行时间管理。

每个控制周期按顺序完成：

```text
FC03
解码
安全判断
配置处理
Controller计算
编码
FC16
日志
```

同一 `ControllerContext（控制器上下文）` 不允许同时被两个重叠控制周期并发修改。

如果某次通信超时或其它异常导致当前循环超过100 ms：

```text
记录CYCLE_OVERRUN（周期超时）
↓
等待当前周期处理完成
↓
进入后续正常循环
```

不启动重叠的第二个控制周期。

恢复后不快速补跑多个历史控制周期，也不把未执行的历史时间一次性补入算法。

---

# 八、每个FC03成功响应形成一份Measurement Snapshot（测量快照）

每个正常控制周期：

```text
FC03读取40101～40124
↓
检查响应功能码
↓
检查响应寄存器数量
↓
全部寄存器解码
↓
完成有效性判断
↓
形成Measurement Snapshot（测量快照）
```

`Measurement Snapshot（测量快照）` 是一次控制计算使用的数据边界。

一次 `ControllerInput（控制器输入）` 中的全部动态测量来自同一份Snapshot。

`snapshot_fresh（测量快照新鲜标志）=1` 表示：

> 本次成功取得并接受了一份新的完整40101～40124读取结果。

它和 `RTLAB_HEARTBEAT（RT-LAB心跳）` 是否在本次读取中发生数值变化不是同一个概念。

`RTLAB_HEARTBEAT（RT-LAB心跳）` 继续用于判断RT-LAB数据源是否持续活跃以及是否发生超时。

---

# 九、ControllerInput（控制器输入）填写

写入C语言算法模块的是解码后的工程量，不直接传Modbus原始寄存器整数。

主要字段：

```text
monotonic_time_s
本Snapshot对应的板端单调时间

pcc_p_kw
PCC有功；进入算法前已经完成方向转换

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
相角当前是否可用

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
当前是否为新Snapshot

snapshot_transport_valid
当前FC03传输和响应是否完整

signal_valid_mask
各输入字段读取/解码有效位域

measurement_channel_valid
当前测量通道是否有效

command_channel_valid
当前工程程序是否具备完整命令帧发布条件

controller_enabled
现有V3.2安全状态机当前是否已进入ENABLED

comm_ok_for_strategy
提供给策略判断层使用的通信状态

model_status_raw
40115原始MODEL_STATUS

rtlab_heartbeat
40116 RTLAB_HEARTBEAT
```

`monotonic_time_s（单调时间）` 在接受该Snapshot时记录。

真正的同一Snapshot重试必须复用原Snapshot中的这个时间值，不能重新生成新的Snapshot时间。

---

# 十、signal_valid_mask（信号有效位域）

位定义：

```text
bit0  PCC_P字段有效
bit1  PCC_Q字段有效
bit2  PCC_V字段有效
bit3  PCC_F字段有效
bit4  PV_MAX字段有效
bit5  ESS_SOC字段有效
bit6  P_MEAS字段有效
bit7  GRID_V字段有效
bit8  GRID_F字段有效
bit9  PCC_PHASE字段有效
bit10 GRID_PHASE字段有效
bit11 PHASE_VALID字段有效
bit12 EXEC_MODE_STATUS字段有效
bit13 EXEC_SYSTEM_MODE字段有效
bit14 MODEL_STATUS字段有效
bit15 RTLAB_HEARTBEAT字段有效
```

当前BASELINE（基础版本）控制要求：

```text
bit0～bit5
bit7～bit15
```

全部有效。

`bit6 P_MEAS字段有效` 当前不是BASELINE控制资格的强制条件，但40109～40114仍正常读取、解码和记录。

注意：

```text
signal_valid_mask中的“字段有效”
≠
该字段内部布尔值必须等于1
```

例如：

```text
40121 PHASE_VALID = 0
```

可以是一份合法的寄存器读取结果。

此时：

```text
bit11 PHASE_VALID字段有效 = 1
phase_valid = 0
```

表示“相角有效标志这个字段读取正确，但当前相角估计不可用于同步”。

同样，40122中的 `EXEC_ROUTE_VALID（执行路由有效）=0` 不等于40122寄存器读取失败。

---

# 十一、现有V3.2安全状态机与BOARD15控制器的关系

现有：

```text
DISCONNECTED（断开）
WAIT_VALID（等待有效）
ENABLED（已允许外部控制）
```

继续由工程主程序维护。

`controller_enabled（控制器允许状态）` 只有在现有状态机已经进入：

```text
ENABLED（已允许外部控制）
```

时置1。

JSON中的：

```text
external_enable_request（外部控制投入请求）
```

继续作为现有V3.2安全状态机允许进入ENABLED的必要条件。

40205：

```text
CONTROL_MASTER_ENABLE（板端控制总使能）
```

属于BOARD15 Runtime Config（运行时配置），决定PROJECT15是否允许真实执行。

因此真实控制受到：

```text
V3.2安全状态
+
external_enable_request
+
CONTROL_MASTER_ENABLE
+
Controller Adapter正式状态
```

共同约束。

---

# 十二、程序启动和首次控制器初始化

程序进程启动时：

```text
1.
controller_reset（控制器启动级复位）

2.
建立Modbus TCP连接

3.
进入WAIT_VALID（等待有效）

4.
读取40101～40124
建立有效Fast Measurement（快速测量）

5.
取得40124 CONFIG_SEQ（配置序号）

6.
按照第二十二章原子协议读取40201～40280
形成完整ControllerConfig（控制器配置）

7.
确认Measurement Snapshot（测量快照）和ControllerConfig均完整有效

8.
调用controller_init（控制器初始化）
```

在完整ControllerConfig尚未成功建立以前：

```text
通信
状态机
心跳
日志
```

可以继续运行，但：

```text
EXT_CONTROL_ENABLE（外部整体控制有效）=0
```

`controller_reset（控制器启动级复位）` 和 `controller_init（控制器初始化）` 只用于程序进程启动。

已经初始化以后，普通Modbus断线和自动重连过程中不再次调用这两个启动接口。

---

# 十三、100 ms主循环固定顺序

每个正常100 ms周期：

```text
1.
记录本周期monotonic time（单调时间）
更新本地调度状态

2.
更新本地BOARD_HEARTBEAT（板端心跳）计数

3.
确认TCP连接状态
必要时执行现有自动重连逻辑

4.
FC03读取40101～40124

5.
完成全部寄存器解码

6.
检查：
MODEL_STATUS
RTLAB_HEARTBEAT
测量范围
枚举值
数据完整性
并形成signal_valid_mask

7.
更新：
DISCONNECTED
WAIT_VALID
ENABLED

8.
检查40124 CONFIG_SEQ

如果发现新配置：
按照原子配置协议读取40201～40280；
新配置成功应用前继续使用上一份正式配置

9.
冻结本周期Measurement Snapshot
形成ControllerInput

10.
调用controller_step（控制器单周期计算）

11.
根据controller_step返回状态选择本周期控制内容

12.
生成40001～40064完整Command Frame（命令帧）

13.
执行所有编码、缩放、舍入、范围和有限数检查

14.
通过一次FC16发送40001～40064完整帧

15.
如果本周期对应一个pending（待提交候选）且该完整FC16成功：
调用controller_commit（提交）

16.
更新本周期FC16结果、通信状态和运行日志

17.
计算本周期实际耗时
超过100 ms时置CYCLE_OVERRUN（周期超时）
```

只有：

```text
40001～40064整个FC16写操作成功
```

才视为这一完整命令帧发布成功。

---

# 十四、controller_step（控制器单周期计算）返回状态处理

## 14.1 MONITOR_ONLY（仅监视）

表示当前可以根据fresh（新鲜）测量更新策略观测状态，但当前不形成新的真实控制接管结果。

如果命令通道仍可用，本周期继续发送完整工程帧：

```text
EXT_CONTROL_ENABLE = 0

CMD_SEQ
=
当前正式CMD_SEQ

BOARD_HEARTBEAT
=
当前工程心跳

控制量
=
最近一次成功committed（已提交）的正式控制结果
```

如果程序启动后还没有任何正式committed结果，则控制字段使用安全初始化值。

不调用 `controller_commit（提交）`。

---

## 14.2 HELD（保持）

表示本周期没有新的命令状态需要提交。

继续发送最近一次正式控制内容：

```text
CMD_SEQ不变
BOARD_HEARTBEAT正常更新
```

`EXT_CONTROL_ENABLE（外部整体控制有效）` 根据当前完整安全条件确定。

---

## 14.3 CANDIDATE（新候选）

表示 Controller Adapter（控制器适配层）已经保存新的：

```text
pending（待提交候选）
```

本周期使用返回的：

```text
ControllerOutput（控制器输出）
```

形成控制字段。

候选命令序号通过：

```text
controller_tx_cmd_seq（读取待发送命令序号）
```

取得。

FC16成功：

```text
controller_commit（提交）
```

FC16失败：

```text
不controller_commit
pending继续保留
```

FC16失败本身不立即调用 `controller_abort_pending（放弃待提交候选）`。

---

## 14.4 RETRY_PENDING（重试待提交候选）

表示当前调用仍然对应原来的同一Measurement Snapshot（测量快照）。

必须保持：

```text
同一pending ControllerOutput（待提交控制器输出）
同一candidate CMD_SEQ（候选命令序号）
同一候选Command State（命令状态）
```

不重新推进命令状态，也不重复更新Observation State（观测状态）。

工程主程序重新组成当前40001～40064帧时：

```text
控制候选字段保持不变
candidate CMD_SEQ保持不变
```

但工程运行字段可以按当前循环更新，例如：

```text
BOARD_HEARTBEAT
COMM_STATUS
```

因此“重试同一个pending”是指控制候选和候选命令版本不变，不要求完整64个寄存器逐字节完全冻结。

真正同一Snapshot重试时必须复用原来保存的：

```text
RTLAB_HEARTBEAT
monotonic_time_s
```

---

## 14.5 ERROR（错误）

本周期不提交新的控制器状态。

如果命令通道仍可用，发送：

```text
EXT_CONTROL_ENABLE = 0
CMD_SEQ保持
BOARD_HEARTBEAT正常更新
```

并记录具体错误。

如果错误发生在本地：

```text
控制结果编码
完整命令帧形成
本地范围处理
```

阶段，调用：

```text
controller_abort_pending（放弃待提交候选）
```

因为该候选在本地已经无法形成有效发送帧。

---

# 十五、同一Snapshot重试和新Snapshot到来的区别

## 15.1 尚未取得新的Measurement Snapshot

上一份FC16失败后，若没有接受新的40101～40124数据，可以继续针对原Snapshot进行真正的pending重试。

此时：

```text
不重新算控制器
不推进命令状态
不改变candidate CMD_SEQ
```

---

## 15.2 已经接受新的Measurement Snapshot

如果旧pending还未成功发布，但程序已经接受新的完整40101～40124数据：

```text
旧pending
=
旧Plant状态对应的控制候选
```

本周期正常调用：

```text
controller_step
```

Adapter自动废弃旧pending，并从：

```text
official command state（正式命令状态）
```

使用最新测量重新形成当前控制结果。

对于：

```text
PCC Breaker（公共连接点断路器）
System Mode（系统模式）
Black Start（黑启动）
Resynchronization（重同步）
```

等安全相关动作，不在接受新Plant状态以后无条件重发旧动作。

---

# 十六、FC03失败、测量无效和通信恢复

以下情况视为测量连续性中断：

```text
FC03失败
Modbus异常响应
返回寄存器数量错误
本周期核心测量无法形成有效Snapshot
```

调用：

```text
controller_notify_measurement_break
（通知控制器测量连续性中断）
```

本周期：

```text
不推进新的命令状态
清除未发布pending
EXT_CONTROL_ENABLE = 0
CMD_SEQ保持
```

如果TCP命令通道仍可用，可以继续发送一份完整安全状态帧：

```text
最近committed控制量
或尚无正式结果时的安全初始化值
+
EXT_CONTROL_ENABLE=0
+
当前BOARD_HEARTBEAT
+
当前工程状态字段
```

连接完全中断时进入：

```text
DISCONNECTED（断开）
```

通信恢复：

```text
重新连接
↓
WAIT_VALID
↓
重新满足连续有效周期
↓
ENABLED
```

普通通信恢复期间：

```text
不controller_reset
不controller_init
不补算历史周期
```

Controller Adapter会在首个新的有效Snapshot上重新对齐需要连续时间证据的内部状态。

---

# 十七、command_channel_valid（命令通道有效）的含义

`command_channel_valid（命令通道有效）` 表示：

> 在调用控制器时，工程主程序当前已具备形成并尝试发布一份完整40001～40064命令帧的工程条件。

它由工程主程序根据：

```text
TCP连接状态
本地编码能力
当前命令通道状态
已有通信故障状态
```

生成。

当前控制周期实际FC16是否最终成功，只能在FC16完成以后得到。

因此：

```text
command_channel_valid=1
```

不等于：

```text
本周期FC16必然成功
```

真正的状态提交仍然以当前完整FC16的实际返回结果为准。

---

# 十八、40010 EXT_CONTROL_ENABLE（外部整体控制有效）

40010沿用旧地址，但最终语义为：

```text
EXT_CONTROL_ENABLE
（板端整体控制有效）
```

不再只表示AGC。

本周期写1必须同时满足：

```text
1.
V3.2状态=ENABLED

2.
external_enable_request=true

3.
CONTROL_MASTER_ENABLE=1

4.
Controller Adapter已经初始化

5.
至少存在一份成功committed的完整控制结果

6.
当前Measurement Snapshot有效

7.
measurement_channel_valid=1

8.
command_channel_valid=1

9.
当前正式ControllerConfig合法

10.
当前没有导致控制输出无效的算法或本地编码错误
```

Adapter侧可使用：

```text
controller_external_control_ready
（控制器外部控制准备状态）
```

提供对应条件。

`AGC_ENABLE（基础AGC使能）` 只控制基础有功协调子模块，不作为整个40010有效的单独必要条件。

程序启动或运行时Reset后：

```text
has_committed_command（已有正式提交控制结果）=0
```

所以40010保持0。

第一份新candidate成功FC16并完成 `controller_commit（提交）` 后，从后续周期开始，在其它安全条件仍满足时才允许40010置1。

---

# 十九、BOARD_HEARTBEAT（板端心跳）

40012：

```text
BOARD_HEARTBEAT（板端心跳）
```

表示板端主程序持续运行。

每完成一个实际主循环更新一次。

正常运行时约每100 ms更新。

即使当前为：

```text
HELD（保持）
MONITOR_ONLY（仅监视）
ERROR（错误）
RETRY_PENDING（重试待提交候选）
```

只要板端主程序继续运行，BOARD_HEARTBEAT按工程循环继续更新。

通信阻塞导致某一周期超时后，不快速补加多个历史心跳。

计数采用UINT16（16位无符号整数），允许：

```text
65535 → 0
```

自然回绕。

---

# 二十、CMD_SEQ（命令序号）

40011：

```text
CMD_SEQ（命令序号）
```

表示：

> 成功发布的新Plant（被控对象）控制内容版本。

用于判断是否为“新控制内容”的字段包括：

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

以下工程/诊断字段的变化本身不构成新的Plant控制版本，例如：

```text
BOARD_HEARTBEAT
COMM_STATUS
STRATEGY_ACTIVE_MASK
DOMAIN_VALID_MASK
配置状态
其它诊断字段
```

只有新的Plant控制内容成功通过完整FC16发布并提交以后，正式CMD_SEQ更新。

以下情况不增加CMD_SEQ：

```text
HELD
MONITOR_ONLY
ERROR
FC16失败
同一pending重试
内部算法状态变化但编码后的Plant控制内容未变化
只有工程诊断字段变化
```

即使CMD_SEQ不增加，完整40001～40064仍按正常通信周期发送。

CMD_SEQ为UINT16，允许自然回绕：

```text
65535 → 0
```

程序不得使用“新值必须大于旧值”作为唯一合法性判断。

---

# 二十一、COMM_STATUS（通信与工程状态位域）

40030由工程主程序生成。

```text
bit0
TCP_CONNECTED（TCP连接存在）

bit1
LAST_FC03_OK（最近一次FC03成功）

bit2
MEASUREMENT_FRESH（本周期取得新的测量快照）

bit3
MEASUREMENT_VALID（本周期测量快照有效）

bit4
LAST_FC16_OK（最近一次已经完成的FC16成功）

bit5
COMMAND_CHANNEL_VALID（命令通道有效）

bit6
CONTROLLER_ENABLED（V3.2当前允许控制）

bit7
HAS_COMMITTED_COMMAND（已有正式提交控制结果）

bit8
STATE_WAIT_VALID（当前WAIT_VALID）

bit9
STATE_DISCONNECTED（当前DISCONNECTED）

bit10
CONFIG_VALID（当前正式控制器配置有效）

bit11
CONFIG_UPDATE_PENDING（新配置正在读取或应用）

bit12
CYCLE_OVERRUN（最近一个完整循环超过100 ms）
```

特别说明：

```text
LAST_FC16_OK
```

位于当前准备发送的40001～40064帧中，所以它表示：

> **形成当前帧以前，最近一次已经完成的FC16结果。**

当前FC16完成以后更新本地状态，供下一帧使用。

---

# 二十二、Runtime Config（运行时配置）首次读取和原子更新

40124：

```text
CONFIG_SEQ（配置序号）
```

表示当前整组运行配置版本。

程序启动时必须先建立一份完整运行配置。

运行过程中发现CONFIG_SEQ变化时，按以下原子协议：

```text
1.
读取40124
保存seq_before（读取前配置序号）

2.
使用FC03读取完整40201～40280

3.
读取40201 CONFIG_SEQ_ECHO（配置序号回显）

4.
再次读取40124
保存seq_after（读取后配置序号）

5.
只有：
seq_before
=
CONFIG_SEQ_ECHO
=
seq_after

才认为本次40201～40280属于同一个完整配置版本

6.
完成类型、缩放、范围、枚举和逻辑检查

7.
形成ControllerConfig（控制器配置）

8.
调用controller_reconfigure（控制器重新配置）

9.
成功后更新CONFIG_APPLIED_SEQ（已应用配置序号）
```

新配置完整成功应用前：

```text
继续使用上一份正式ControllerConfig
```

不使用一半新、一半旧的配置进行控制。

---

# 二十三、CONFIG_STATUS（配置状态）和CONFIG_APPLIED_SEQ（已应用配置序号）

40025：

```text
CONFIG_APPLIED_SEQ（已应用配置序号）
```

始终写当前正式生效的：

```text
ControllerConfig.config_seq
```

40026：

```text
CONFIG_STATUS（配置状态）
```

按本周期配置处理结果：

```text
0
本周期没有新的配置处理结果

1
本周期检测到新配置并成功应用

-1
本周期检测到新配置，但配置非法或被控制器拒绝
```

配置失败：

```text
保持上一份正式配置
CONFIG_APPLIED_SEQ保持原值
```

40030中的：

```text
CONFIG_UPDATE_PENDING
```

用于表示新的配置版本已经被发现，但完整读取、检查或应用尚未完成。

---

# 二十四、P_COORDINATION_MODE（有功协调方式）和METHOD_VARIANT（方法变体）

当前正式BOARD15 C语言程序支持：

```text
40202 P_COORDINATION_MODE
=
0 BASELINE（基础有功协调）
```

当前：

```text
1 EXECUTION_AWARE
（执行状态感知有功协调）
```

作为后续预留。

如果当前程序收到：

```text
P_COORDINATION_MODE = 1
```

则本次配置按不支持处理：

```text
controller_reconfigure返回配置错误
CONFIG_STATUS = -1
继续使用上一份正式配置
```

同样：

```text
40257 METHOD_VARIANT
```

当前只接受：

```text
0 BASELINE（基础方法）
```

其它值当前拒绝，不静默回退。

40027：

```text
P_COORDINATION_MODE_STATUS
（当前实际有功协调方式）
```

当前正式版本写0。

40061：

```text
METHOD_VARIANT_STATUS
（当前实际方法变体）
```

当前正式版本写0。

---

# 二十五、运行时Reset（复位）

40280：

```text
CONTROLLER_RESET_SEQ（控制器复位序号）
```

用于显式重建控制器算法状态。

运行时Reset通过：

```text
controller_reconfigure（控制器重新配置）
```

完成。

检测到RESET_SEQ变化以后，Adapter执行：

```text
清pending
重建Observation State（观测状态）
重建Command State（命令状态）
清除旧committed结果的有效资格
保留CMD_SEQ连续性
保持ControllerContext已初始化
```

之后第一份fresh有效Snapshot由Adapter重新对齐并重新形成新的候选控制结果。

运行时Reset不调用启动流程中的：

```text
controller_reset
controller_init
```

以下参数改变时必须同时改变CONTROLLER_RESET_SEQ：

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

时，如需改变当前构网主机配置，也通过显式Reset后应用。

普通TCP重新连接不改变CONTROLLER_RESET_SEQ。

RESET_SEQ为UINT16，允许自然回绕。

---

# 二十六、40122 EXEC_MODE_STATUS（最终执行状态位域）

40122按UINT16解析：

```text
bit0
PCC_BREAKER_CLOSED
（PCC断路器最终已闭合）

bit1
ESS1_GRIDON
（储能1最终GridOn状态）
1=GFL（跟网）
0=GFM（构网）

bit2
ESS2_GRIDON
（储能2最终GridOn状态）

bit3
ESS1_DROOP
（储能1最终下垂使能）

bit4
ESS2_DROOP
（储能2最终下垂使能）

bit5
SELECTED_MASTER_ESS1
（最终构网主机为ESS1）

bit6
SELECTED_MASTER_ESS2
（最终构网主机为ESS2）

bit7
MODE_OVERRIDE_ACTIVE
（最终模式接管有效）

bit8
BREAKER_OVERRIDE_ACTIVE
（最终PCC断路器接管有效）

bit9
ISLAND_LATCH
（最终孤岛锁存存在）

bit10
BLACKSTART_LATCH
（最终黑启动锁存存在）

bit11
BOARD_ROUTE_ACTIVE
（RT-LAB当前最终采用BOARD15控制路由）

bit12
EXEC_ROUTE_VALID
（最终BOARD15模式/断路器执行路由有效）

bit13～15
RESERVED（保留）
```

bits5和6不能同时作为两个有效主机。

40122原始值写入：

```text
ControllerInput.exec_mode_status_raw
```

Controller Adapter根据40122和40123自动派生：

```text
blackstart_execution_confirmed
（黑启动执行确认）

island_mode_confirmed
（孤岛模式执行确认）

breaker_closed_confirmed
（断路器闭合确认）

normal_mode_confirmed
（正常模式执行确认）
```

---

# 二十七、40123 EXEC_SYSTEM_MODE（最终执行系统模式）

40123按以下枚举解析：

```text
0 NORMAL（正常并网）

1 EMERGENCY（并网应急）

2 ISLANDING（正在离网）

3 ISLANDED（已孤岛）

4 BLACK_START（黑启动）

5 RESYNCHRONIZATION（重同步）

6 FAULT_SAFE（故障安全）
```

写入：

```text
ControllerInput.exec_system_mode
```

该值是RT-LAB最终实际执行模式，不是40023 `SYSTEM_MODE（板端请求系统模式）` 的简单回显。

---

# 二十八、ControllerOutput（控制器输出）到40001～40024

主要控制输出编码关系：

```text
pref_pu[6]
→
40001～40006

agc_status
→
40007

agc_dp_kw
→
40008

agc_remain_kw
→
40009

qref_pu[6]
→
40013～40018

grid_on[6]
→
40019 GRIDON_MASK

droop_enable[6]
→
40020 DROOP_MASK

pcc_breaker_request_close
→
40021

fref_trim_hz
→
40022

system_mode
→
40023

selected_master
→
40024
```

40019和40020位顺序：

```text
bit0 PV1
bit1 PV2
bit2 ESS1
bit3 ESS2
bit4 EV1
bit5 EV2
```

编码前执行：

```text
finite（有限数）检查
数据类型检查
缩放
舍入
寄存器范围检查
```

本地编码或帧形成失败时：

```text
不commit
EXT_CONTROL_ENABLE=0
controller_abort_pending
记录错误原因
```

---

# 二十九、40028 STRATEGY_ACTIVE_MASK（活动策略位域）

来自：

```text
ControllerDiagnostics.strategy_active_mask
（控制器诊断中的活动策略位域）
```

定义：

```text
bit0 = S1
bit1 = S2
...
bit14 = S15
```

---

# 三十、40029 DOMAIN_VALID_MASK（控制域有效位域）

按当前正式C语言实现：

```text
bit0
P_DOMAIN_VALID（有功域有效）

bit1
Q_DOMAIN_VALID（无功域有效）

bit2
MODE_DOMAIN_VALID（基础模式域有效）

bit3
BLACKSTART_DOMAIN_VALID（黑启动域有效）

bit4
RESYNC_DOMAIN_VALID（重同步恢复域有效）

bit5
FINAL_MODE_ROUTE_VALID（最终模式重路由有效）
```

其它bit当前写0。

---

# 三十一、40031～40064当前版本处理

40031～40059：

```text
后续执行状态感知算法诊断预留
当前BASELINE版本写0
```

40060：

```text
PCC_RX_KW
（Board本周期实际用于控制计算的PCC有功）
```

写当前 `ControllerInput.pcc_p_kw（控制器实际PCC有功输入）` 对应值。

方向：

```text
正=外送
负=购电
```

40061：

```text
METHOD_VARIANT_STATUS
当前写0
```

40062：

```text
RECON_EVENT_SEQ
当前写0
```

40063～40064：

```text
通用预留
当前写0
```

上述地址仍随每次完整40001～40064 FC16一起发送，以保持固定命令帧布局。

---

# 三十二、Runtime Config（运行时配置）和JSON（配置文件）的参数来源

15策略和控制算法运行参数以：

```text
40201～40280 Runtime Config
```

作为正式运行时来源。

包括：

```text
策略Enable（策略使能）
P_OBJECTIVE_MODE（有功目标模式）
CONTROL_MASTER_ENABLE（板端控制总使能）
AGC_ENABLE（基础AGC使能）
MODE_ACTUATION_ENABLE（模式真实执行使能）
PCC_BREAKER_ACTUATION_ENABLE（断路器真实执行使能）

P_UNIT
P_DEAD
SOC上下限
TS_AGC

15策略阈值和参数

S15重同步参数

RESET_SEQ
```

旧JSON中如果为了兼容原程序结构仍保留以下字段：

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

这些字段不再覆盖已经成功应用的402xx正式配置。

JSON继续保存工程程序本身的参数：

```text
ip（RT-LAB地址）
port（端口）
unit_id（从站单元编号）

send_interval_ms（基础发送周期）

connect_timeout_ms（连接超时）
response_timeout_ms（响应超时）
rtlab_heartbeat_timeout_ms（RT-LAB心跳超时）

valid_cycles_before_enable（投入前有效周期数）
max_consecutive_failures（最大连续失败次数）
reconnect_interval_ms（重连间隔）

model_ready_mask
model_fault_mask

external_enable_request（外部控制投入请求）

pcc_sign_gain（PCC符号转换系数）

日志开关和日志路径

Project15IntegrationConfig
（PROJECT15固定集成配置）
```

正式运行模式标识：

```text
algorithm_mode（算法模式）
=
"board15"
```

正式：

```text
send_interval_ms
=
100
```

---

# 三十三、Project15IntegrationConfig（PROJECT15固定集成配置）

根据当前最终RT-LAB模型正常稳态控制接口，最终集成配置设置为：

```text
baseline_grid_on
=
[1, 1, 1, 1, 1, 1]

baseline_droop
=
[1, 1, 1, 1, 1, 1]

baseline_breaker_close
=
1
```

六设备顺序：

```text
PV1
PV2
ESS1
ESS2
EV1
EV2
```

含义：

```text
正常模式下六设备均为GridOn=1
即GFL（跟网）

正常稳态下基础Droop=1

正常模式PCC断路器闭合
```

上述值放入最终JSON或等效固定集成配置，工程主程序在：

```text
controller_init（控制器初始化）
```

时传入 `Project15IntegrationConfig（PROJECT15固定集成配置）`。

---

# 三十四、Controller接口返回错误处理

以下接口均检查返回状态：

```text
controller_init
controller_reconfigure
controller_commit
controller_decode_execution_feedback
```

返回非成功状态时：

```text
不把本次结果当作新的正式控制状态
记录对应ControllerStatus（控制器状态码）
EXT_CONTROL_ENABLE按安全逻辑置0
保持上一份已经正式提交的控制历史
```

`controller_commit（提交）` 只在：

```text
当前确实存在pending
+
对应完整FC16已经成功
```

时调用。

没有pending时不调用controller_commit。

---

# 三十五、计数器和序号回绕

下列寄存器/状态均为UINT16：

```text
CMD_SEQ
CONFIG_SEQ
CONTROLLER_RESET_SEQ
RTLAB_HEARTBEAT
BOARD_HEARTBEAT
```

均允许：

```text
65535 → 0
```

自然回绕。

检测变化时不能使用：

```text
new > old
```

作为唯一条件。

---

# 三十六、最终JSON基础结构调整

现有JSON继续沿用原解析框架，主要工程字段调整为：

```json
{
  "ip": "192.168.1.100",
  "port": 1502,
  "unit_id": 1,

  "algorithm_mode": "board15",
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

  "baseline_grid_on": [1, 1, 1, 1, 1, 1],
  "baseline_droop": [1, 1, 1, 1, 1, 1],
  "baseline_breaker_close": 1.0
}
```

现有：

```text
read_points（读取点表）
```

扩展为40101～40124。

现有：

```text
write_points（写入点表）
```

扩展为40001～40064。

运行时40201～40280增加为独立连续配置块读取。

最终地址、数据类型、缩放和单位统一按随附点表。

---

# 三十七、运行日志

最终板端运行日志至少持续记录：

```text
monotonic_time（单调时间）

DISCONNECTED / WAIT_VALID / ENABLED状态

FC03结果
FC16结果
实际循环耗时
CYCLE_OVERRUN

RTLAB_HEARTBEAT
BOARD_HEARTBEAT

PCC P/Q/V/f/phase
Grid V/f/phase
phase_valid

PV1/PV2最大可用功率
ESS1/ESS2 SOC
六设备Pmeas

40122 EXEC_MODE_STATUS
40123 EXEC_SYSTEM_MODE

controller_step返回状态
ControllerStatus错误码

has_pending
has_committed_command

CMD_SEQ

CONFIG_SEQ
CONFIG_APPLIED_SEQ
CONFIG_STATUS
CONTROLLER_RESET_SEQ

六设备Pref
六设备Qref
GRIDON_MASK
DROOP_MASK

PCC Breaker
Fref trim
System Mode
Selected Master

STRATEGY_ACTIVE_MASK
DOMAIN_VALID_MASK
COMM_STATUS

通信错误
配置错误
控制器错误
编码错误
```

日志优先记录解码后的工程量，同时保留必要的原始状态字。

---

# 三十八、最终程序运行关系

最终程序固定关系：

```text
Engineering Main Program（工程主程序）
负责：
Modbus TCP通信
FC03 / FC16
V3.2三状态安全框架
心跳
寄存器解码/编码
Runtime Config原子读取
100 ms调度
JSON
运行日志
工程通信状态

        ↓

Controller Adapter（控制器适配层）
负责：
ControllerContext
candidate
pending
commit
measurement break
runtime reconfigure
reset
execution feedback confirmation

        ↓

PROJECT15 Core（完整15策略控制核心）
负责：
S1～S15策略判断
有功目标与约束
六资源基础有功协调
S6平滑
S8减载
S3无功
Mode控制
Black Start
Resynchronization

        ↓

ControllerOutput（控制器输出）

        ↓

工程主程序
编码40001～40064
        ↓

FC16
        ↓

RT-LAB（实时仿真平台）
```

最终板端程序以100 ms为基础周期，与RT-LAB形成完整双向实时控制闭环。
