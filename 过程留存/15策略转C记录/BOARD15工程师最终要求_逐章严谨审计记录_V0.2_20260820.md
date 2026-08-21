# BOARD15（板端15策略程序）工程师最终要求｜逐章严谨审计记录 V0.2
## ——面向正式工程师版本要求的内容、接口、状态与点表一致性审计

> **日期**：2026-08-20  
> **审计对象**：`BOARD15最终板端控制程序设计与集成要求_V0.1`、现有工程师 `JSON（配置文件）`、V3.2/V4/V5（历史板端程序版本）要求、C01～C10正式C语言模块、Modbus（通信寄存器）点表V0.4、当前最终Simulink（仿真模型）。  
> **本轮目标**：不是增加新功能，而是检查“工程师拿到要求后是否只有一种正确理解”，并消除点表、C接口和旧程序语义之间的不一致。

---

# 1. 总体结论

V0.1总体架构正确，但正式交付前发现并关闭了以下关键问题：

1. `DOMAIN_VALID_MASK（控制域有效位域）` 点表V0.4与C09 V0.2实际实现不一致；
2. `Reset Protocol（复位协议）` 点表V0.4仍保留早期“运行时调用controller_reset/controller_init”的旧表达，与C10 V0.1实际实现不一致；
3. 40010从旧版 `EXT_AGC_ENABLE（外部AGC使能）` 升级为 `EXT_CONTROL_ENABLE（外部整体控制有效）` 后，不能继续沿用“AGC_ENABLE必须为1”的旧语义；
4. V0.1没有把 `signal_valid_mask（信号有效位域）` 和当前BASELINE（基础版本）必需输入讲清；
5. V0.1没有把“同一Measurement Snapshot（测量快照）重试”与“新Snapshot到来后旧pending（待提交候选）失效”讲到工程师可以直接实现的程度；
6. V0.1没有明确 `BOARD_HEARTBEAT（板端心跳）`、`CMD_SEQ（命令序号）`、`pending（待提交候选）` 三者不是同一个时序概念；
7. V0.1没有把40025～40030的配置和通信状态字段逐项落实到工程主程序责任；
8. V0.1没有明确40031～40064以及40257～40279是稳定点位预留，而当前版本不要求开发执行状态感知算法；
9. V0.1没有明确最终JSON（配置文件）中哪些旧AGC参数应从“有效控制参数来源”退出，避免JSON和402xx同时成为两套参数源；
10. V0.1没有明确运行时Reset（复位）不清CMD_SEQ（命令序号），启动级Reset与运行时Reset是两种不同动作。

上述内容已在V0.2工程师要求中修正。

---

# 2. 点表V0.4发现的一处真实不一致：DOMAIN_VALID_MASK

C09 V0.2实际C代码中的控制域位定义为：

```text
bit0 = P（有功域）
bit1 = Q（无功域）
bit2 = MODE（基础模式域）
bit3 = BLACKSTART（黑启动域）
bit4 = RESYNC（重同步恢复域）
bit5 = FINAL_MODE_ROUTE（最终模式重路由域）
```

但点表V0.4写成：

```text
bit0=P
bit1=Q
bit2=MODE
bit3=SYNC
```

这会导致工程师按点表编码后与C09真实诊断结果不一致。

本轮已生成：

```text
BOARD15_Modbus点表_RuntimeConfig_CommandFrame_V0.5_工程师要求审计修正版.xlsx
```

正式改为bits0～5与C09 V0.2一致。

---

# 3. Reset Protocol（复位协议）发现的一处真实不一致

点表V0.4旧Reset流程仍写：

```text
RESET_SEQ变化
→ controller_reset（控制器启动级复位）
→ controller_init（控制器启动级初始化）
```

但C10 V0.1最终实现的运行时Reset语义是：

```text
controller_reconfigure（控制器重新配置）
检测CONTROLLER_RESET_SEQ变化
↓
清pending（待提交候选）
重建Observation State（观测状态）
重建Command State（命令状态）
清旧committed result（已提交结果）的有效资格
保留CMD_SEQ连续性
保持ControllerContext（控制器上下文）已初始化
↓
第一份fresh（新鲜）测量由Adapter（适配层）自动rebase（重新对齐）
↓
重新形成新候选
```

运行时Reset不能调用启动用 `controller_reset（控制器启动级复位）`，因为启动级Reset会把CMD_SEQ归零。

V0.5点表已修正。

---

# 4. 40010语义必须从“AGC使能”彻底升级成“整体控制有效”

旧程序40010叫：

```text
EXT_AGC_ENABLE（外部AGC使能）
```

当前最终点表保留地址40010，但名称和语义升级为：

```text
EXT_CONTROL_ENABLE（外部整体控制有效）
```

当前整体控制不仅有AGC（自动发电控制），还包括：

```text
Q（无功）
Mode（模式）
GridOn（并网/构网）
Droop（下垂）
Breaker（断路器）
Black Start（黑启动）
Resynchronization（重同步）
```

因此40010不能要求：

```text
AGC_ENABLE=1
```

才能有效。

最终40010的必要条件应来自：

```text
V3.2状态=ENABLED（已允许外部控制）
external_enable_request（外部控制请求）=true
CONTROL_MASTER_ENABLE（板端控制总使能）=1
已有至少一份成功committed（已提交）的完整控制结果
measurement_channel_valid（测量通道有效）=1
command_channel_valid（命令通道有效）=1
当前完整Snapshot（测量快照）有效
当前配置有效
当前无本周期控制器/编码错误
```

`AGC_ENABLE（自动发电控制使能）` 只控制基础有功协调子模块，不再是40010整体控制有效的必要条件。

---

# 5. 当前BASELINE（基础版本）真正需要哪些输入

C10 V0.1冻结的当前必需信号是：

```text
PCC_P（公共连接点有功）
PCC_Q（公共连接点无功）
PCC_V（公共连接点电压）
PCC_F（公共连接点频率）

PV_MAX（两路光伏最大可用功率）
ESS_SOC（两路储能荷电状态）

GRID_V（上级电网电压）
GRID_F（上级电网频率）

PCC_PHASE（公共连接点相角）
GRID_PHASE（上级电网相角）
PHASE_VALID（相角有效）

EXEC_MODE_STATUS（最终执行状态位域）
EXEC_SYSTEM_MODE（最终执行系统模式）

MODEL_STATUS（模型状态）
RTLAB_HEARTBEAT（RT-LAB心跳）
```

六路：

```text
P_MEAS（设备实际有功）
```

当前仍必须读取和记录，但BASELINE（基础有功协调）不把它作为当前控制资格的强制有效位。

这和后续执行状态感知算法预留要区分。

---

# 6. signal_valid_mask（信号有效位域）必须写进工程师要求

C语言公共接口已经冻结：

```text
bit0  PCC_P
bit1  PCC_Q
bit2  PCC_V
bit3  PCC_F
bit4  PV_MAX
bit5  ESS_SOC
bit6  P_MEAS
bit7  GRID_V
bit8  GRID_F
bit9  PCC_PHASE
bit10 GRID_PHASE
bit11 PHASE_FLAG
bit12 EXEC_MODE
bit13 EXEC_SYS
bit14 MODEL_STATUS
bit15 RT_HEARTBEAT
```

当前BASELINE版本要求：

```text
除bit6 P_MEAS外，其余上述当前控制必需位都有效
```

`P_MEAS`仍正常读取、解码和写日志。

---

# 7. Snapshot（测量快照）身份必须足够明确

C10 V0.1判断“是不是同一份待重试快照”使用：

```text
RTLAB_HEARTBEAT（RT-LAB心跳）
+
monotonic_time_s（该快照对应的板端单调时间）
```

因此真正重试旧pending时，工程主程序必须保留并复用**原先那一份ControllerInput（控制器输入）快照对象中的时间和心跳**。

不能：

```text
同一批寄存器数据
但重新写一个新的monotonic_time_s
```

否则控制器会认为这是新周期，而不是同一交易重试。

---

# 8. 新Snapshot到来后，旧pending不能继续当成普通FC16重试

对于只有Pref（有功指令）的旧AGC程序，FC16失败后“重复旧candidate（候选）”比较简单。

但最终BOARD15还包含：

```text
Breaker（断路器）
System Mode（系统模式）
Black Start（黑启动）
Resynchronization（重同步）
```

这些动作依赖当前Plant（被控对象）状态。

因此最终规则是：

```text
同一Snapshot
→ exact retry（精确重试）同一pending

新的fresh Snapshot已经被接受
→ 旧pending作废
→ 从official command state（正式命令状态）
  使用最新测量重新计算
```

这条必须写得足够明确。

---

# 9. FC16每100 ms发送与CMD_SEQ不是一回事

完整控制帧仍按100 ms发送，以持续提供：

```text
BOARD_HEARTBEAT（板端心跳）
EXT_CONTROL_ENABLE（外部控制有效）
COMM_STATUS（通信状态）
配置状态
当前控制内容
```

但：

```text
CMD_SEQ（命令序号）
```

只表示“成功发布的新Plant控制内容版本”。

所以：

```text
每100 ms发送FC16
≠
每100 ms CMD_SEQ + 1
```

这是正式要求必须反复避免歧义的地方。

---

# 10. HELD / MONITOR_ONLY / ERROR也要说明本周期写什么

正式工程要求中明确：

## HELD（保持）

```text
继续发送最近正式控制内容
EXT_CONTROL_ENABLE按当前安全资格决定
CMD_SEQ不变
BOARD_HEARTBEAT正常更新
```

## MONITOR_ONLY（仅监视）

```text
如命令通道可用：
继续发送完整工程帧
EXT_CONTROL_ENABLE=0
控制量使用最近committed结果；如果从未commit则使用初始化安全值
CMD_SEQ不变
BOARD_HEARTBEAT更新
```

## ERROR（错误）

```text
如命令通道仍可用：
发送完整安全状态帧
EXT_CONTROL_ENABLE=0
不得commit新的控制状态
CMD_SEQ不变
BOARD_HEARTBEAT更新
记录错误原因
```

这样工程师不会误以为“没有candidate就不再FC16”。

---

# 11. 40025～40030必须明确由谁生成

这些不全部来自 `ControllerOutput（控制器输出）`。

```text
40025 CONFIG_APPLIED_SEQ
→ 工程主程序/Adapter当前正式配置版本

40026 CONFIG_STATUS
→ 工程主程序配置读取/应用结果

40027 P_COORDINATION_MODE_STATUS
→ 当前active ControllerConfig（控制器正式配置）
  当前正式版本只能为0 BASELINE

40028 STRATEGY_ACTIVE_MASK
→ ControllerDiagnostics（控制器诊断）

40029 DOMAIN_VALID_MASK
→ ControllerDiagnostics（控制器诊断）

40030 COMM_STATUS
→ 工程主程序综合TCP/FC03/FC16/V3.2/配置/周期状态生成
```

V0.2要求中已明确。

---

# 12. COMM_STATUS（通信状态位域）必须逐bit冻结

当前正式点表：

```text
bit0  TCP_CONNECTED（TCP已连接）
bit1  LAST_FC03_OK（最近一次FC03成功）
bit2  MEASUREMENT_FRESH（测量快照新鲜）
bit3  MEASUREMENT_VALID（测量有效）
bit4  LAST_FC16_OK（最近一次FC16成功）
bit5  COMMAND_CHANNEL_VALID（命令通道有效）
bit6  CONTROLLER_ENABLED（V3.2当前允许控制）
bit7  HAS_COMMITTED_COMMAND（已有正式提交命令）
bit8  STATE_WAIT_VALID（当前WAIT_VALID）
bit9  STATE_DISCONNECTED（当前DISCONNECTED）
bit10 CONFIG_VALID（当前正式配置有效）
bit11 CONFIG_UPDATE_PENDING（新配置读取/应用中）
bit12 CYCLE_OVERRUN（最近一周期超过100 ms目标）
```

这一部分属于工程主程序状态，不由算法模块生成。

---

# 13. DOMAIN_VALID_MASK（控制域有效位域）已按C09修正

V0.5正式：

```text
bit0 P_DOMAIN_VALID（有功域有效）
bit1 Q_DOMAIN_VALID（无功域有效）
bit2 MODE_DOMAIN_VALID（基础模式域有效）
bit3 BLACKSTART_DOMAIN_VALID（黑启动域有效）
bit4 RESYNC_DOMAIN_VALID（重同步恢复域有效）
bit5 FINAL_MODE_ROUTE_VALID（最终模式重路由有效）
```

---

# 14. 当前版本如何处理未来预留点位

项目当前最终BOARD15只需要：

```text
P_COORDINATION_MODE=0 BASELINE（基础有功协调）
METHOD_VARIANT=0 BASELINE（基础方法）
```

当前C10对其它方式执行显式拒绝。

因此：

```text
40031～40062
```

保留为稳定的未来诊断地址。

当前程序：

```text
按ControllerDiagnostics（控制器诊断）已有字段编码；
尚未启用的执行状态感知字段保持0/默认值。
```

其中：

```text
40060 PCC_RX_KW
当前可写Board实际用于计算的PCC值

40061 METHOD_VARIANT_STATUS
当前固定0

40062 RECON_EVENT_SEQ
当前BASELINE固定0
```

```text
40063～40064
```

作为通用预留，当前写0。

运行时配置：

```text
40257 METHOD_VARIANT
```

当前只接受0。

```text
40258～40279
```

保持未来预留，不驱动当前BOARD15控制逻辑。

这就实现：

```text
点位预留
≠
要求工程师当前开发未来算法
```

---

# 15. Runtime Config（运行时配置）必须只有一个有效参数源

旧JSON中包含：

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

最终BOARD15已经把算法运行参数放到：

```text
40201～40280 Runtime Config（运行时配置）
```

因此最终要求中明确：

> **算法/策略运行参数以402xx当前正式配置为唯一运行时来源。**

旧JSON中的同名AGC参数如果为了兼容旧解析代码仍保留，不得覆盖402xx已经成功应用的正式配置。

JSON继续负责：

```text
IP
Port
Unit ID
100 ms工程周期
连接/响应/心跳超时
重连
V3.2安全参数
external_enable_request
pcc_sign_gain
日志
固定Project15IntegrationConfig（PROJECT15集成配置）
```

避免两套参数源互相覆盖。

---

# 16. CONTROL_MASTER_ENABLE和external_enable_request必须区分

```text
external_enable_request（外部控制请求）
```

属于工程主程序/V3.2安全状态机的人工或上层投入请求。

```text
CONTROL_MASTER_ENABLE（板端控制总使能）
```

属于402xx Runtime Config（运行时配置），决定PROJECT15是否真实产生控制接管。

最终真实外部控制需要二者与安全状态同时满足。

---

# 17. 启动Reset和运行时Reset必须区分

程序进程刚启动：

```text
controller_reset（控制器启动级复位）
→ controller_init（控制器初始化）
```

只执行一次完整启动流程。

运行过程中：

```text
CONTROLLER_RESET_SEQ变化
```

通过：

```text
controller_reconfigure（控制器重新配置）
```

完成算法状态重建。

普通TCP reconnect（重新连接）：

```text
不controller_reset
不controller_init
```

---

# 18. 第一份正式控制结果和40010的关系

程序启动/运行时Reset后：

```text
has_committed_command=0
```

因此即使当前V3.2已经满足ENABLED：

```text
40010 EXT_CONTROL_ENABLE仍保持0
```

第一份新candidate通过FC16成功发布后：

```text
controller_commit
↓
has_committed_command=1
```

从后续帧开始，在其它安全条件仍满足时，40010才可以置1。

这继承旧V4“先成功发布一份正式结果，再宣布外部控制有效”的安全语义。

---

# 19. baseline GridOn/Droop/Breaker不让工程师自行决定

C10需要：

```text
Project15IntegrationConfig（PROJECT15集成配置）
```

其中包括：

```text
baseline_grid_on[6]
baseline_droop[6]
baseline_breaker_close
```

正式工程师要求只规定：

```text
这些值从最终BOARD15 JSON/集成配置附件读取
不得在算法模块内部写死
```

实际数值由我们根据最终RT-LAB模型冻结后提供。

---

# 20. 当前文档成熟度

经过本轮审计：

```text
工程师要求主体
已经基本完整

点表逻辑
已修正到V0.5

C10生命周期
与正式要求已对齐
```

正式发给工程师前剩余内部事项主要是：

```text
1. 最终Project15IntegrationConfig三个baseline值填入参考JSON
2. 最终C源码包整理，清理旧“candidate/skeleton”注释，形成单一正式源码包
3. 将V0.2要求再做一次纯文字一致性检查后升为V1.0
```

这些都不是重新设计BOARD15算法。
