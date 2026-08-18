# BOARD15 内部设计06｜`project15_core.c/.h` 正式接口、模块边界与工程集成冻结 V0.1
## ——在开始 LOCAL15 → C 转换以前，最后冻结“谁负责什么、数据怎么进、状态怎么保存、命令怎么出、未来P协调算法怎么无侵入切换”

> **日期**：2026-08-18  
> **性质**：内部冻结设计；本轮之后才进入真正的C代码迁移。  
> **依据**：当前冻结的 LOCAL15 15/15 PASS（全部通过）结构、V3.2/V4/V5板端安全基线、BOARD15 Design01～Design05、Modbus点表 V0.3，以及已经存在的执行状态评估 / 协调恢复 / 有效能力重分配算法原型。  
> **核心原则**：
>
> 1. **板端始终只有一套S1～S15高级应用策略。**
> 2. `P_COORDINATION_MODE（有功协调方式）` 只切换P协调子模块，不复制整套15策略。
> 3. 工程主程序只负责通信、安全、调度、配置、编码/解码和“FC16成功以后才commit（提交）”。
> 4. 我方C算法不包含Modbus、socket、JSON、CSV、线程、硬件驱动。
> 5. `project15_core`迁移的是完整LOCAL15控制语义，不只是原始`Advanced_Strategy_Core`。
> 6. 所有可持续状态必须显式放在结构体中；禁止隐藏的可变全局变量。
> 7. 所有算法时间使用板端monotonic clock（单调时钟）推导的控制时间，不直接读取系统日期时间。
> 8. 正常100 ms主循环、1 s基础AGC、多域安全、Runtime Config和candidate/commit语义不能被未来算法破坏。
> 9. 未来已经明确的执行状态感知P协调算法必须能在同一二进制程序中通过运行时参数切换；切换试验不需要工程开发方重新改代码。

---

# 1. 本轮为什么必须在写C以前做

到Design05为止，我们已经解决：

```text
Design01
算法/主程序/Plant接口边界

Design02
FC03 / FC16 / 多控制域安全

Design03 / 03A
100 ms主循环 + 1 s基础AGC
以及板端可实现性

Design04 V0.2
Modbus点表和未来算法预留

Design05
persistent状态分类
candidate / commit
Reset / reconnect规则
```

现在剩下的最大风险不是算法数学本身，而是：

```text
“C代码到底拆成哪些模块？”
“主程序到底调用哪个函数？”
“哪些变量属于input？”
“哪些状态是算法正式状态？”
“future P协调方式怎么插入？”
“FC16失败后谁负责不commit？”
“运行中切换P协调方法时怎么不重新启动Board？”
```

如果这些没有冻结就开始转C，最容易出现：

```text
算法能跑
但是主程序不知道怎么集成

或：

同一个状态在两个文件各保存一份

或：

future算法加入后必须重写main

或：

工程开发方为了接算法自行改变控制语义
```

所以Design06是正式转C以前最后一道结构关。

---

# 2. 先冻结最终软件分层

最终BOARD15程序只分三大层：

```text
============================================================
Layer A：Engineering Main Program
工程主程序层
============================================================

Modbus TCP
FC03 / FC16
V3.2三状态机
heartbeat
数据raw decode / encode
100 ms scheduler
Runtime Config
candidate发布结果
CMD_SEQ
BOARD_HEARTBEAT
CSV
reconnect

                    ↓ 统一结构体

============================================================
Layer B：Controller Adapter
控制算法适配层
============================================================

controller_reset
controller_init
controller_reconfigure
controller_step
controller_commit
controller_abort_pending

P_COORDINATION_MODE运行时切换
pending candidate管理
一套15策略状态生命周期

                    ↓

============================================================
Layer C：Project15 Algorithm
项目15策略算法层
============================================================

一套S1～S15
Request Normalizer
Mode Manager
Arbiter
P Objective / Constraints
P Coordination
S6 / S8
S3 Q
Black Start
S15 Resynchronization
Execution Mapper

============================================================
```

RT-LAB不属于这三层，它仍是：

```text
Plant
测量
相角估计
最终Board有效性
Source Router
Execution Fault Injector
u_applied
MAT
```

---

# 3. 工程主程序与算法模块之间只允许结构体交互

正式禁止这种写法：

```c
project15_core(
    reg40101,
    reg40102,
    ...
    register_array,
    modbus_socket,
    json_object);
```

正确：

```text
Modbus raw registers
↓
工程主程序 decode / I/O Adapter
↓
ControllerInput
ControllerConfig
↓
Controller Adapter / Project15
↓
ControllerOutput
ControllerDiagnostics
↓
工程主程序 encode
↓
40001～40064
```

也就是说：

> **算法永远不知道40101是多少，也不知道40001是多少。**

这样以后点表变动、缩放变化、补码处理都不会污染算法。

---

# 4. 六设备顺序正式冻结

所有数组统一：

```text
index 0 = PV1
index 1 = PV2
index 2 = ESS1
index 3 = ESS2
index 4 = EV1
index 5 = EV2
```

C中统一：

```c
typedef enum
{
    DEV_PV1 = 0,
    DEV_PV2 = 1,
    DEV_ESS1 = 2,
    DEV_ESS2 = 3,
    DEV_EV1 = 4,
    DEV_EV2 = 5
} DeviceIndex;
```

以后：

```text
Pref
Qref
Pmeas
Pexpected
residual
trust
effective capability
execution state
```

全部使用同一顺序。

禁止不同模块自己发明设备排序。

---

# 5. System Mode（系统模式）编码正式继承LOCAL15

继续使用：

```text
0 = GRID_CONNECTED_NORMAL
    正常并网

1 = GRID_CONNECTED_EMERGENCY
    并网紧急状态

2 = ISLANDING
    正在离网切换

3 = ISLANDED
    已孤岛

4 = BLACK_START
    黑启动

5 = RESYNCHRONIZATION
    重同步

6 = FAULT_SAFE
    故障安全状态
```

C：

```c
typedef enum
{
    SYS_GRID_CONNECTED_NORMAL = 0,
    SYS_GRID_CONNECTED_EMERGENCY = 1,
    SYS_ISLANDING = 2,
    SYS_ISLANDED = 3,
    SYS_BLACK_START = 4,
    SYS_RESYNCHRONIZATION = 5,
    SYS_FAULT_SAFE = 6
} SystemMode;
```

这和40123 `EXEC_SYSTEM_MODE（实际系统模式）`、40023 `SYSTEM_MODE（Board请求模式）`采用同一语义。

---

# 6. Master（构网主机）编码正式冻结

```text
0 = NONE
1 = ESS1
2 = ESS2
```

不使用设备数组index直接代替。

原因：

```text
设备index：
ESS1 = 2
ESS2 = 3

master编码：
ESS1 = 1
ESS2 = 2
```

两者语义不同。

---

# 7. GridOn / Droop语义正式冻结

当前LOCAL15已经冻结：

```text
GridOn = 1
→ GFL（Grid-Following，跟网型）

GridOn = 0
→ GFM（Grid-Forming，构网型）
```

`Droop=1`：

```text
下垂控制使能
```

因此：

```c
uint8_t grid_on[6];
uint8_t droop_enable[6];
```

进入Modbus前再压缩为：

```text
GRIDON_MASK
DROOP_MASK
```

算法内部不要直接操作bit mask。

---

# 8. ControllerInput正式冻结

Design01第一版曾考虑把Grid P/Q也带入算法输入。

Design06基于“最小必要”原则做最终收口：

> **不把GRID_P、GRID_Q放进BOARD15 ControllerInput。**

原因：

1. 当前15项BOARD15闭环没有实际使用Grid P/Q；
2. S15只需要Grid V/f/phase；
3. 后续Execution-Aware P协调使用PCC、u_commit和六路Pmeas；
4. Modbus V0.3没有给Grid P/Q增加动态寄存器；
5. 为“也许以后有用”而增加输入不符合当前原则。

同理：

```text
六路Qmeas
```

当前也不进入Board算法接口。

需要做Q执行效果验证时：

```text
RT-LAB MAT
```

已经能够记录Plant Qmeas。

---

# 9. `ControllerInput`最终字段

推荐正式结构：

```c
typedef struct
{
    /* --------------------------------------------------------
     * Time
     * -------------------------------------------------------- */
    double monotonic_time_s;

    /* --------------------------------------------------------
     * PCC measurements
     * Internal sign is ALWAYS:
     *   + export to upstream grid
     *   - import from upstream grid
     * -------------------------------------------------------- */
    double pcc_p_kw;
    double pcc_q_kvar;
    double pcc_v_rms_v;
    double pcc_freq_hz;
    double pcc_phase_deg;

    /* --------------------------------------------------------
     * Grid-side synchronization measurements
     * -------------------------------------------------------- */
    double grid_v_rms_v;
    double grid_freq_hz;
    double grid_phase_deg;
    uint8_t phase_valid;

    /* --------------------------------------------------------
     * DER capability / state
     * -------------------------------------------------------- */
    double pv_max_kw[2];
    double ess_soc[2];
    double p_meas_kw[6];

    /* --------------------------------------------------------
     * RT-LAB final execution feedback
     * -------------------------------------------------------- */
    uint16_t exec_mode_status_raw;
    uint8_t  exec_system_mode;

    /* --------------------------------------------------------
     * Snapshot / signal validity
     * -------------------------------------------------------- */
    uint8_t snapshot_fresh;
    uint8_t snapshot_transport_valid;
    uint32_t signal_valid_mask;

    /* --------------------------------------------------------
     * Communication / controller context
     * -------------------------------------------------------- */
    uint8_t measurement_channel_valid;
    uint8_t command_channel_valid;
    uint8_t controller_enabled;
    uint8_t comm_ok_for_strategy;

    uint16_t model_status_raw;
    uint16_t rtlab_heartbeat;

} ControllerInput;
```

---

# 10. 为什么不再把`last_committed_pref`放进ControllerInput

Design01曾考虑：

```text
last_committed_cmd_seq
has_committed_command
last_committed_pref
```

作为Input。

Design06最终改为：

> **这些不是Plant输入，而是Controller自身的正式历史。**

因此移入：

```text
ControllerContext
```

由Controller Adapter在：

```text
FC16成功
→ controller_commit()
```

以后维护。

未来Execution-Aware P协调需要：

```text
u_commit
```

时，直接读取ControllerContext中的：

```text
last_committed_output.pref_pu[6]
```

不需要工程主程序把Board自己的输出再“作为输入传回来”。

这样职责更干净。

---

# 11. `signal_valid_mask`为什么必须存在

不能只保留：

```text
measurements_valid = 0 / 1
```

因为：

```text
phase invalid
```

应该：

```text
禁止S15重同步
```

但不应必然让：

```text
S7普通有功控制
```

全部退出。

因此算法输入增加32位内部有效性mask。

建议第一版bit：

```text
bit 0  PCC_P valid
bit 1  PCC_Q valid
bit 2  PCC_V valid
bit 3  PCC_F valid
bit 4  PV_MAX pair valid
bit 5  ESS_SOC pair valid
bit 6  six P_MEAS valid
bit 7  GRID_V valid
bit 8  GRID_F valid
bit 9  PCC_PHASE valid
bit 10 GRID_PHASE valid
bit 11 PHASE_VALID flag valid
bit 12 EXEC_MODE_STATUS valid
bit 13 EXEC_SYSTEM_MODE valid
bit 14 MODEL_STATUS valid
bit 15 RTLAB_HEARTBEAT valid/fresh
bit 16～31 reserved
```

这只是Board程序内部结构。

不新增Modbus寄存器。

---

# 12. Domain Validity（控制域有效性）由算法层统一派生

例如：

```text
P_DOMAIN_VALID
需要：
PCC_P
PV_MAX
ESS_SOC
以及当前P策略所需输入

Q_DOMAIN_VALID
需要：
PCC_Q
PCC_V
当前Pref

MODE_DOMAIN_VALID
需要：
PCC_V
PCC_F
executed mode feedback

SYNC_DOMAIN_VALID
需要：
PCC_V / PCC_F / PCC_PHASE
GRID_V / GRID_F / GRID_PHASE
PHASE_VALID
executed mode feedback
```

具体逻辑统一写在：

```text
project15_core / validity helper
```

工程主程序只做：

```text
“这一原始信号是否合法”
```

不要在main里复制策略域判断。

---

# 13. `comm_ok_for_strategy`正式定义

它不是：

```text
“这一个FC16一定成功”
```

也不是：

```text
“只要TCP socket存在”
```

它表示：

> **原15策略S5中的通信健康语义。**

BOARD15建议：

```text
comm_ok_for_strategy = 1
```

仅当：

```text
当前measurement channel可用
+
当前command channel没有被主程序判定为失效
+
V3.2状态不是DISCONNECTED
```

单次、尚未达到失效判据的FC16偶发失败：

```text
可以让LAST_FC16_OK=0
```

但不必立刻把整个S5 raw communication判定长期失效。

最终精确去抖/连续失败阈值继续由V3.2主程序安全逻辑决定。

更重要的是：

> 即使 `comm_ok_for_strategy=0` 使原S5 raw alarm出现，S11已经冻结的“communication-only不能触发真实PCC解列”规则必须继续保留。

---

# 14. 时间语义正式收口

不增加：

```text
RT-LAB Target Time
```

实时控制寄存器。

算法只接：

```text
monotonic_time_s
```

ControllerContext在每次显式：

```text
controller_init()
```

时保存：

```text
control_epoch_s
```

内部统一：

```text
control_time_s
=
monotonic_time_s - control_epoch_s
```

所以：

```text
新实验controller reset/init
→ control_time重新从0开始
```

这样满足：

```text
S10周期计划
原15策略时间
S6 dt
```

等控制需要。

S14 Board版已经在Design05正规化为：

```text
stage-relative time
```

不再直接依赖：

```text
Board进程启动了多久
```

---

# 15. ControllerConfig正式分层

不要把40201～40280原样变成一个80元素数组。

正式C结构分：

```text
ControllerConfig
│
├─ FrameworkConfig
│
├─ StrategyConfig
│
├─ BaselineAgcConfig
│
├─ BlackStartConfig
│
├─ ResyncConfig
│
└─ ExecutionAwareConfig
```

---

# 16. `FrameworkConfig`

包括：

```c
typedef struct
{
    uint8_t  p_coordination_mode;
    uint16_t strategy_enable_mask;
    uint8_t  p_objective_mode;

    uint8_t  control_master_enable;
    uint8_t  agc_enable;

    uint8_t  mode_actuation_enable;
    uint8_t  pcc_breaker_actuation_enable;

    int8_t   q_sign_gain;

    uint8_t  blackstart_pref_sequence_enable;
    uint8_t  blackstart_master;
    uint8_t  island_master;

    uint8_t  recovery_request;

} FrameworkConfig;
```

注意：

```text
CONTROLLER_RESET_SEQ
```

不是Project15算法参数。

它属于：

```text
Controller lifecycle
```

由Controller Adapter处理。

---

# 17. `StrategyConfig`

只保留当前原15策略真正存在的参数：

```text
P_unit
demand window / demand limit
AGC error band
Vnom
AVC deadband / Qlimit
anti-reverse limit / deadband
island f/v thresholds
smooth rate / PV fluct trigger
tie target
UV / UF
load shed step
peak / valley
plan interval
export limit
renewable target
blackstart enable
switch enable
5个multi-objective权重
```

原：

```text
CFG_AA_enable
```

不作为外部Config字段。

按Design04 V0.2已经冻结：

```text
strategy_eval_enable
```

由Board内部根据：

```text
fresh / valid snapshot
```

自动派生。

---

# 18. `BaselineAgcConfig`

```c
typedef struct
{
    double p_unit_kw;
    double p_dead_kw;
    double soc_min;
    double soc_max;
    double ts_agc_s;
    double pv_init_kw;
    double ev_init_kw;
} BaselineAgcConfig;
```

---

# 19. `ResyncConfig`

```c
typedef struct
{
    double sync_dv_max_pu;
    double sync_df_max_hz;
    double sync_dtheta_max_deg;

    double sync_stable_s;
    double reclose_hold_s;

    double fref_ktheta_hz_per_deg;
    double fref_kdf;
    double fref_trim_max_hz;
} ResyncConfig;
```

`recovery_request`不放这里，因为它是运行时动作请求，已经位于FrameworkConfig。

---

# 20. `ExecutionAwareConfig`

这部分现在只是为了**稳定接口**。

当前Execution-Aware MATLAB原型中的部分时间参数仍明确是候选值，不能因为Design06就宣称数学参数已经最终冻结。

C接口先准备：

```text
METHOD_VARIANT
执行失配进入/清除阈值
异常确认时间
恢复稳定时间
response timeout
六设备expect delay
六设备expect tau
capability min/reserve
trust alpha
reconstruction blend
SOC辅助权重
```

未来正式C算法只填充这部分。

当前：

```text
P_COORDINATION_MODE = BASELINE
```

时：

> 这些参数不会改变PROJECT15结果。

---

# 21. ControllerOutput只放“算法控制内容”

正式：

```c
typedef struct
{
    double pref_pu[6];
    double qref_pu[6];

    uint8_t grid_on[6];
    uint8_t droop_enable[6];

    uint8_t pcc_breaker_request_close;

    double  fref_trim_hz;

    uint8_t system_mode;
    uint8_t selected_master;

    int8_t  agc_status;
    double  agc_dp_kw;
    double  agc_remain_kw;

    uint8_t output_valid;

} ControllerOutput;
```

范围：

```text
PV Pref   [0, +1]
ESS Pref  [-1, +1]
EV Pref   [-1, 0]

Qref      [-1, +1]并受Q能力分配进一步限制

grid_on / droop / breaker
只能为0或1

selected_master
只能为0/1/2

system_mode
只能为0～6

fref_trim
受ResyncConfig限幅
```

---

# 22. 哪些400xx量绝对不放进ControllerOutput

以下属于工程主程序：

```text
40010 EXT_CONTROL_ENABLE
40011 CMD_SEQ
40012 BOARD_HEARTBEAT

40025 CONFIG_APPLIED_SEQ
40026 CONFIG_STATUS

40030 COMM_STATUS
```

原因：

它们描述的是：

```text
通信
配置
发布
应用程序状态
```

而不是控制算法想让Plant做什么。

---

# 23. ControllerDiagnostics与ControllerOutput彻底分开

Design01第一版曾把：

```text
strategy_status[15]
...
```

放在ControllerOutput中。

Design06最终拆开。

原因：

```text
strategy_status
objective_dP
residual
trust
```

不是Plant控制命令。

正式：

```c
typedef struct
{
    /* original 15 strategies */
    double strategy_status[15];
    double strategy_alarm[15];
    double strategy_metric[15];
    double strategy_cmd[15];

    uint16_t strategy_active_mask;
    uint16_t domain_valid_mask;

    /* P objective / constraint */
    uint8_t  p_objective_source;
    uint16_t p_constraint_mask;
    double   objective_dp_kw;
    double   effective_dp_kw;

    /* Q */
    double q_request_kvar;
    double q_applied_kvar;
    double q_unserved_kvar;

    /* S6 / S8 */
    double s6_request_kw;
    double s6_applied_kw;
    double s6_unserved_kw;

    double s8_request_kw;
    double s8_applied_kw;
    double s8_unserved_kw;

    /* mode */
    uint8_t raw_system_mode;
    uint8_t final_system_mode;
    uint8_t mode_reason;

    uint8_t selected_master;
    uint8_t breaker_request_close;

    /* S15 electrical synchronization */
    double delta_v_pu;
    double delta_f_hz;
    double delta_theta_deg;
    double sync_timer_s;
    double reclose_timer_s;
    double fref_trim_hz;

    /* future execution-aware P coordination */
    double p_expected_kw[6];
    double execution_residual_kw[6];
    uint16_t execution_state_packed;
    uint16_t resource_qualified_mask;

    double effective_cap_kw[6];
    double trust[6];

    uint8_t  coord_recovery_state;
    uint16_t realloc_active_mask;
    double   realloc_remain_kw;

    double   pcc_rx_kw;
    uint8_t  method_variant_status;
    uint16_t reconstruction_event_seq;

} ControllerDiagnostics;
```

当前Baseline模式：

```text
future execution-aware字段
= 0 / default
```

这样Board CSV和40031～40064共享同一个诊断源，不重复计算。

---

# 24. Project15State继续使用Design05的分类

正式核心：

```c
typedef struct
{
    StrategyObservationState observation;

    StrategyQualificationState qualification;

    AgcCommandState baseline_agc;

    S6CommandState s6;

    ModeExecutionState mode_execution;

    BlackStartExecutionState black_start;

    RecoveryState resync;

} Project15State;
```

其中：

```text
Observation / qualification的部分状态
按照fresh测量更新

Command-generating state
必须candidate/commit

confirmed mode
从40122/40123反馈对齐
```

具体规则完全继承Design05，不在Design06重新发明第二套。

---

# 25. ControllerContext是最终真正的控制器运行实例

建议：

```c
typedef struct
{
    uint8_t initialized;

    double control_epoch_s;

    uint16_t active_config_seq;
    uint16_t last_reset_seq;

    uint8_t active_p_coordination_mode;
    uint8_t active_method_variant;

    Project15State project15;

    PCoordinationState pcoord;

    ControllerOutput last_committed_output;

    uint8_t has_committed_output;

    ControllerPending pending;

} ControllerContext;
```

---

# 26. `ControllerPending`为什么必须放Adapter内部

推荐：

```c
typedef struct
{
    uint8_t valid;

    uint8_t control_content_changed;
    uint8_t command_state_changed;

    Project15CommandCandidate project_candidate;
    PCoordinationCandidate pcoord_candidate;

    ControllerOutput output;

} ControllerPending;
```

工程主程序不需要理解：

```text
AGC哪几个字段要commit
S6哪几个字段要commit
sync_timer是不是candidate
```

它只需要知道：

```text
FC16成功
→ controller_commit()

FC16失败
→ 不commit
```

这会明显降低工程开发方误接状态的风险。

---

# 27. 公开给工程主程序的函数最终建议6个

```c
void controller_reset(
    ControllerContext *ctx);

ControllerStatus controller_init(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *config);

ControllerStatus controller_reconfigure(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *old_config,
    const ControllerConfig *new_config);

ControllerStepResult controller_step(
    ControllerContext *ctx,
    const ControllerInput *input,
    const ControllerConfig *config,
    ControllerOutput *output,
    ControllerDiagnostics *diag);

ControllerStatus controller_commit(
    ControllerContext *ctx);

void controller_abort_pending(
    ControllerContext *ctx);
```

工程主程序不直接调用内部：

```text
strategy15_step
baseline_agc_step
resync_step
```

---

# 28. `controller_reset()`职责

只在：

```text
程序首次启动
或
CONTROLLER_RESET_SEQ变化
```

调用。

负责：

```text
清Project15State
清pending
清Controller内部初始化标志
清控制epoch

不碰CMD_SEQ
不碰BOARD_HEARTBEAT
不碰Modbus状态机
```

后3项仍属于工程主程序。

---

# 29. `controller_init()`职责

前提：

```text
已有一批fresh、合法、可用于初始化的Measurement Snapshot
```

负责：

```text
control_epoch_s = current monotonic time

observation:
使用当前PCC/PV等建立初始历史

pv_prev:
= current PV

S6 smooth_ref:
= current PV

Mode:
根据40122/40123对齐真实Plant状态

Baseline AGC:
按照当前项目初始化规则建立Ppv/Pess/Pev

Recovery:
初始IDLE/根据confirmed Plant模式建立安全状态

last committed output:
不在init中伪造为“已经成功发布”
```

初始化本身：

```text
不增加CMD_SEQ
```

也不声称：

```text
Plant已经接受任何新命令
```

---

# 30. `controller_reconfigure()`职责

只有Runtime Config成功原子读取并通过合法性检查以后调用。

普通：

```text
target
threshold
weight
strategy enable
```

变化：

```text
保留历史状态
只更新配置
```

如果：

```text
CONTROLLER_RESET_SEQ变化
```

主程序不调用reconfigure，而是：

```text
controller_reset
↓
等待fresh input
↓
controller_init
```

---

# 31. `P_COORDINATION_MODE`切换时的处理

这一点直接关系以后我们自己做试验是否需要工程开发方。

例如：

```text
BASELINE
→
EXECUTION_AWARE
```

不能：

```text
把新的P协调模块从全0状态硬切入
```

正确：

```text
读取：
last_committed_output.pref_pu[6]

+
当前Pmeas/PVmax/SOC

↓

p_coordination_initialize_from_committed()

↓

新P协调模块从当前正式u_commit附近接管
```

反向：

```text
EXECUTION_AWARE
→
BASELINE
```

也同样对齐到：

```text
last committed six Pref
```

因此：

> **运行时方法切换只重新初始化P协调子模块，不重置S1～S15、Q、模式、黑启动和S15。**

---

# 32. 如果future P协调C模块尚未编译进当前Board怎么办

严格禁止：

```text
P_COORDINATION_MODE = 1
↓
程序悄悄退回BASELINE
```

正确：

```text
Runtime Config validation failed
↓
CONFIG_STATUS = -1
↓
保持上一份正式配置
↓
日志明确UNSUPPORTED_P_COORDINATION_MODE
```

等未来模块正式完成并编译进最终Board二进制以后：

```text
P_COORDINATION_MODE=1
```

才允许使用。

这样不会出现“以为在跑新方法，其实还在跑基线”的试验事故。

---

# 33. `controller_step()`是整个算法唯一正常周期入口

每100 ms调用一次。

内部固定顺序建议：

```text
A. Validate input context
↓
B. Update observation-side state
↓
C. Evaluate single S1～S15 strategy set
↓
D. Normalize strategy requests
↓
E. Prepare mode / black-start / resync candidate
↓
F. Build P objective + constraints
↓
G. Call selected P-coordination submodule
↓
H. Execution Mapper
↓
I. S6 smoothing + S8 load-shed auxiliary
↓
J. Black-start Pref gate
↓
K. S3 AVC + Q allocator
↓
L. Apply mode permissions and assemble:
   Pref
   Qref
   GridOn
   Droop
   Breaker request
   Fref trim
   Mode
   Master
↓
M. Finite / range / internal consistency check
↓
N. Store candidate in ctx->pending
↓
O. Return candidate ControllerOutput
```

这条调用顺序是C版本正式骨架。

---

# 34. 为什么Mode模块要在P/Q完成前先给“权限/候选状态”

因为：

```text
BLACK_START
ISLANDING
FAULT_SAFE
```

会决定：

```text
普通AGC能不能更新
S6能不能参与
AVC普通Q是否允许
黑启动Pref Gate是否应该覆盖普通P
```

所以不能等P/Q全部算完以后才判断当前模式。

Mode首先产生：

```text
allow_normal_p
allow_normal_q
allow_s6
blackstart_stage
final mode candidate
selected master
```

后续P/Q执行层再服从这些权限。

---

# 35. `controller_step()`遇到已有pending candidate时怎么办

V4要求：

> FC16重试不能重新计算一次算法。

所以如果：

```text
上一周期FC16失败
+
pending仍有效
+
没有进入WAIT_VALID/DISCONNECTED
```

本周期：

```text
可以更新ObservationState和诊断

但不能重新推进command-generating state

直接返回同一份pending控制内容
用于FC16重试
```

标记：

```text
retrying_pending = 1
```

---

# 36. 哪些情况下pending必须立即丢弃

如果发生：

```text
FC03失败并导致控制资格退出
measurement snapshot失效
进入WAIT_VALID
进入DISCONNECTED
MODEL_STATUS失效
RT-LAB heartbeat失效
CONTROLLER_RESET_SEQ变化
P协调方式切换
```

则：

```text
controller_abort_pending()
```

恢复后：

```text
从最后正式committed state
+
新的fresh snapshot
```

重新计算。

禁止长时间以后继续发送一份过时candidate。

---

# 37. `controller_commit()`职责

工程主程序只在：

```text
candidate/output内部合法
+
encode成功
+
FC16完整写成功
```

后调用。

负责：

```text
把pending里的command-related state
提交为official state

更新：
last_committed_output

has_committed_output = 1

清pending
```

它不负责：

```text
CMD_SEQ++
```

CMD_SEQ仍然由工程主程序维护。

---

# 38. `CMD_SEQ`与内部State Commit再次区分

出现一种合法情况：

```text
sync_timer candidate
从0.1 → 0.2 s

但是本周期：
Pref/Q/Breaker/Fref等真正控制内容完全没变
```

FC16成功以后：

```text
内部sync_timer可以commit
```

但：

```text
CMD_SEQ不必增加
```

因此`controller_step`必须提供两个标志：

```text
command_state_changed
control_content_changed
```

主程序：

```text
FC16 success
→ controller_commit()

如果 control_content_changed
→ candidate CMD_SEQ正式提交

否则
→ CMD_SEQ保持
```

这是Design05状态规则在API层真正落地。

---

# 39. 推荐`ControllerStepResult`

```c
typedef enum
{
    CTRL_STEP_ERROR = -1,
    CTRL_STEP_MONITOR_ONLY = 0,
    CTRL_STEP_HELD = 1,
    CTRL_STEP_CANDIDATE = 2,
    CTRL_STEP_RETRY_PENDING = 3
} ControllerStepCode;

typedef struct
{
    ControllerStepCode code;

    uint8_t output_valid;

    uint8_t pending_valid;

    uint8_t command_state_changed;
    uint8_t control_content_changed;

    uint8_t agc_updated;
    uint8_t retrying_pending;

} ControllerStepResult;
```

---

# 40. ControllerStatus错误码必须明确

不能所有错误都返回：

```text
-1
```

建议至少：

```text
CTRL_OK

CTRL_ERR_NULL
CTRL_ERR_NOT_INITIALIZED
CTRL_ERR_INPUT_INVALID
CTRL_ERR_CONFIG_INVALID
CTRL_ERR_UNSUPPORTED_P_MODE
CTRL_ERR_NUMERIC
CTRL_ERR_STATE
```

工程主程序可以：

```text
记录CSV/event
+
将EXT_CONTROL_ENABLE置0
```

而不是猜错误原因。

---

# 41. P Coordination（有功协调）必须单独定义稳定内部接口

因为未来真正变化的只应该是：

```text
“总P请求如何根据执行状态在六资源之间协调”
```

而不是整套15策略。

因此增加内部稳定层：

```text
P Coordination Adapter
有功协调适配器
```

---

# 42. P协调公共输入

```c
typedef struct
{
    double control_time_s;

    double dp_request_kw;

    double pcc_p_kw;

    double pv_max_kw[2];
    double ess_soc[2];

    double p_meas_kw[6];

    double committed_pref_pu[6];

    uint8_t update_allowed;
    uint8_t p_domain_valid;

} PCoordinationInput;
```

当前Baseline：

```text
主要使用：
dp_request
PVmax
SOC
```

后续Execution-Aware：

```text
还使用：
Pmeas
committed Pref
execution state
```

因此不需要以后改接口。

---

# 43. P协调公共输出

```c
typedef struct
{
    double pref_pu[6];

    int8_t status;
    double dp_kw;
    double remain_kw;

    uint8_t reconstruction_done;

} PCoordinationOutput;
```

未来的：

```text
Pexpected
residual
trust
effective capacity
```

进入：

```text
PCoordinationDiagnostics
```

而不是污染正常Plant命令接口。

---

# 44. 当前Baseline P协调怎么实现

不建议把未来Project15重新绑定到Modbus目标值。

Project15上游已经形成：

```text
effective_dp_kw
```

因此当前Baseline正式接口应直接：

```text
consume dp_request_kw
```

而不是重新在AGC内部决定：

```text
Ptarget - Ppcc
```

具体C实现建议：

```text
p_coord_baseline.c
```

采用现有基础AGC相同的：

```text
资源优先顺序
SOC约束
PVmax约束
P deadband
Ppv/Pess/Pev状态
1 s更新
```

只是输入改成：

```text
dp_request_kw
```

这和LOCAL15 Stage02已经做过的“external-dP baseline”保持一致。

---

# 45. 为什么不直接用`virtual Ptarget = Pcc + dP_request`欺骗旧AGC

数学上可行，但Design06不推荐作为正式实现。

原因：

1. 会重新把“目标生成”和“资源分配”语义混在一起；
2. 边界处存在不必要的浮点加减；
3. 日后阅读代码不清楚为什么构造虚拟Ptarget；
4. LOCAL15已经验证过external-dP接口，没必要再绕回旧接口。

因此：

> **正式Board Project15 P协调模块直接接受dP_request。**

现有V4 C AGC继续作为：

```text
回归参照
```

而不是强行成为新架构的API约束。

---

# 46. Future Execution-Aware P协调不是第二套15策略

未来文件建议：

```text
p_coord_execution_aware.c/.h
    │
    ├─ p_exec_assessment
    ├─ p_coord_recovery
    └─ p_effective_reallocation
```

它只替换：

```text
P协调子模块
```

整个外部仍然：

```text
同一套15策略
同一个Normalizer
同一个Mode系统
同一个Q系统
同一个S14
同一个S15电气重同步
```

---

# 47. 为什么future P协调接口已经够用

当前已存在的执行状态评估原型使用：

```text
六路command
六路Pmeas
cmd_valid
meas_valid
```

并内部建立：

```text
Pexpected
filtered Pmeas
residual
6设备 execution state
mismatch latch
```

当前协调恢复原型使用：

```text
6设备execution state
cmd/meas validity
```

形成：

```text
NORMAL
HOLD
RECONSTRUCTION
RECOVERY
trust
isolation
dP_request
```

当前有效能力重分配原型使用：

```text
Pexec
trust
PVmax
SOC
dP_request
```

重新计算六资源有效余量。

因此我们冻结的公共P协调输入：

```text
committed Pref
Pmeas
PVmax
SOC
dP_request
validity
```

已经覆盖当前已明确的后续路线。

不需要为了论文算法再次改变主程序接口。

---

# 48. 未来P协调内部persistent不能现在按原型直接照搬

当前原型里的：

```text
T_CLEAR_CONFIRM
T_ISOLATE_CONFIRM
T_RECOVERY_RAMP
...
```

自身文档已经标注部分为：

```text
候选参数
```

并且当前V0.3还注明：

```text
隔离资源本次运行不重新加入
```

因此Design06只冻结：

```text
接口
数据结构能力
运行时切换方式
诊断槽
```

**不在这一轮宣称future算法数学细节已经最终冻结。**

这样既不会阻塞PROJECT15转C，又不会把研究原型过早写死进工程协议。

---

# 49. 最终C文件结构建议

我方算法包：

```text
board15_controller/
│
├─ controller_api.h
│   公共枚举、Input/Config/Output/Diagnostics
│
├─ controller_adapter.h
├─ controller_adapter.c
│   生命周期、pending、commit、P协调方式切换
│
├─ controller_context.h
│   ControllerContext和内部状态组合
│
├─ project15_core.h
├─ project15_core.c
│   单一15策略总编排
│
├─ strategy15_core.h
├─ strategy15_core.c
│   原S1～S15判断 + observation state
│
├─ p_objective.h
├─ p_objective.c
│   Normalizer / 主P目标 / S1/S4/S11约束
│
├─ p_coord_baseline.h
├─ p_coord_baseline.c
│   当前external-dP基础资源分配
│
├─ p_auxiliary.h
├─ p_auxiliary.c
│   S6平滑 + S8 EV减载
│
├─ q_control.h
├─ q_control.c
│   S3 AVC normalize + Q capability allocation
│
├─ mode_control.h
├─ mode_control.c
│   S5资格、Mode Manager、GridOn/Droop/Breaker基础模式
│
├─ black_start.h
├─ black_start.c
│   S14 Pref阶段序列
│
├─ resynchronization.h
├─ resynchronization.c
│   S15 ΔV/Δf/Δθ、Fref trim、重合闸恢复
│
├─ controller_math.h
└─ controller_math.c
    clamp / finite / angle wrap等无状态工具
```

未来正式加入：

```text
p_coord_execution_aware.h/.c
p_exec_assessment.h/.c
p_coord_recovery.h/.c
p_effective_reallocation.h/.c
```

工程main不需要修改调用方式。

---

# 50. 为什么不把所有算法塞进一个`project15_core.c`

一个文件也能运行，但不建议。

原因：

```text
15策略
AGC
S6
Q
模式
黑启动
同步
```

如果全部放在一个几千行文件：

```text
难单测
难做等价比较
难定位状态
future P协调很容易复制整段代码
```

拆成上述模块后：

```text
每个模块都可以对照LOCAL15单独离线验证
```

这会明显降低迁移风险。

---

# 51. 为什么也不拆得更碎

不为每个S1～S15单独建立15个C文件。

因为很多策略本质只是：

```text
统一strategy judgment的一部分
```

如果拆15个文件：

```text
工程文件数量过多
公共状态更难管理
反而增加集成错误
```

所以：

```text
strategy15_core.c
```

保留一套原15策略判断，

后面按：

```text
P / Q / Mode / auxiliary
```

执行域拆分。

这是当前最合适的粒度。

---

# 52. C代码硬性实现规范

所有我方算法文件：

### 必须

```text
C99兼容
固定宽度整数
double浮点
无动态内存
无malloc/free
无线程
无socket
无Modbus
无JSON
无CSV
无文件I/O
无sleep
无系统日期时间
无随机数
```

### 状态

```text
全部显式放struct
```

禁止：

```c
static double hidden_state;
```

形式的跨周期隐藏可变状态。

文件内部只允许：

```text
const常量
纯函数static helper
```

---

# 53. 为什么使用double而不是float

当前：

```text
MATLAB / Simulink
V4 C AGC
```

都以double语义为主要参考。

转C第一阶段目标是：

```text
等价验证
```

而不是极限优化内存。

当前AArch64板端也没有证据表明：

```text
double计算负担会成为100 ms周期瓶颈
```

因此先使用：

```c
double
```

避免引入额外数值差异。

最终完整BOARD15实测100 ms仍是最终性能确认。

---

# 54. 所有时间必须显式dt，不允许“每调用一次=100 ms”

内部：

```text
dt
=
current valid time
-
last valid time
```

需要连续可信数据的：

```text
sync timer
execution assessment timer
```

输入失效时按照其物理规则：

```text
reset / freeze
```

不能因为主循环100 ms就简单：

```c
timer += 0.1;
```

这样以后周期微调也不会改算法语义。

---

# 55. 数值安全规范

每个公共step输出前必须：

```text
finite check
range check
enum check
mask check
```

算法内部出现NaN/Inf：

```text
返回CTRL_ERR_NUMERIC
pending无效
output_valid=0
```

不允许：

```text
NaN
↓
encode cast
↓
写入Modbus
```

---

# 56. Config合法性检查必须在调用算法以前完成

主程序/Adapter应验证：

```text
SOC_min <= SOC_max
P_unit > 0
Ts_AGC > 0
q_sign_gain ∈ {-1,+1}
strategy mask <= 15 bits
P objective mode ∈ [0,4]
master ∈ {0,1,2}并符合对应字段
sync thresholds非负
sync stable / reclose hold > 0
P_COORDINATION_MODE已编译支持
METHOD_VARIANT合法
```

非法配置：

```text
不替换上一份正式Config
CONFIG_STATUS=-1
```

---

# 57. `controller_step()`必须是确定性的

在相同：

```text
ControllerContext official state
ControllerInput
ControllerConfig
```

下：

```text
ControllerOutput
candidate state
diagnostics
```

必须确定。

算法中不允许：

```text
随机数
系统时间抖动源
socket状态直接读取
文件配置临时读取
```

---

# 58. LOCAL15 → C验证顺序冻结

不直接写完整C然后一次上板。

分模块验证：

```text
C01
strategy15_core
对比15×status/alarm/metric/cmd

C02
P Normalizer / objective / constraints

C03
Baseline external-dP P coordination

C04
Execution Mapper + S6 + S8

C05
S3 AVC + Q allocator

C06
Mode Manager + GridOn/Droop/Breaker

C07
S14 black-start Pref stages

C08
S15 resync / reclose / Fref

C09
full project15_core offline

C10
candidate / commit communication fault unit tests

C11
BOARD15 100 ms real board regression
```

任何一层不通过：

```text
不进入下一层
```

---

# 59. 等价验证判据

对于可以直接数学等价的量：

```text
double误差
必须远小于Modbus量化分辨率
```

建议：

```text
先使用abs error <= 1e-9
```

如果由于运算顺序存在合理浮点差异：

```text
必须解释来源
```

而不是放宽到影响寄存器的范围。

最强最终判据：

> **经过最终scale / round / INT16/UINT16编码后，所有应该等价的Modbus控制寄存器必须逐周期完全一致。**

这是比“曲线看起来一样”更严格的标准。

---

# 60. 15策略的Golden Reference不允许被future算法污染

当前PROJECT15 C转换时：

```text
P_COORDINATION_MODE = BASELINE
```

所有future Execution-Aware代码：

```text
不得改变
S1～S15原始status/alarm/metric/cmd
Q
Mode
S14
S15
```

future只在：

```text
P协调子模块
```

被选择时生效。

这是后续实验能够做到：

```text
只比较P协调方法差异
```

的重要基础。

---

# 61. 工程开发方最终需要做什么

工程开发方不需要理解每一个策略公式。

只需：

```text
1. 扩展现有40101～40124 decode

2. 形成ControllerInput

3. 402xx变化时形成ControllerConfig

4. 按CONTROLLER_RESET_SEQ调用reset/init

5. 每100 ms：
   controller_step()

6. 把ControllerOutput编码进40001～40024等控制位置

7. 把ControllerDiagnostics的指定关键量编码进诊断位置

8. FC16成功：
   controller_commit()

9. FC16失败：
   不commit
   按V3.2失败规则处理

10. 安全状态退出：
    controller_abort_pending()

11. 保持现有三状态、heartbeat、reconnect、CSV
```

工程开发方不重新写：

```text
S1～S15
AGC
S6
Q
Mode
Black Start
S15
```

---

# 62. 我方最终要交给工程开发方什么

算法包至少：

```text
controller_api.h
controller_adapter.h/.c
controller_context.h

project15_core.h/.c

strategy15_core.h/.c
p_objective.h/.c
p_coord_baseline.h/.c
p_auxiliary.h/.c
q_control.h/.c
mode_control.h/.c
black_start.h/.c
resynchronization.h/.c
controller_math.h/.c
```

另外提供：

```text
接口说明
enum说明
单位/符号说明
输入输出范围
默认Config表
离线单元测试结果
LOCAL15 vs C等价报告
```

future Execution-Aware最终冻结后，再把对应P协调模块一并编译进最终BOARD15二进制。

---

# 63. 一个必须提前说清的现实边界

如果工程开发方在：

```text
future Execution-Aware C模块还没有完成
```

以前就已经编译并交付了最终不可修改二进制，

那么以后：

```text
P_COORDINATION_MODE=1
```

当然不可能凭空出现新算法。

所以我们的目标应是：

> **最终正式BOARD15程序定版前，把需要用于后续试验的Execution-Aware P协调模块一起集成进同一二进制。**

集成完成以后：

```text
Baseline
Assessment
Recovery
Full
```

之间的切换都由我们自己通过Runtime Config完成，

**不再需要工程开发方帮忙切程序。**

如果future算法当时还没冻结，则只需要工程开发方再做**一次模块集成/重新编译**，不需要重新设计通信、安全、点表或main。

---

# 64. 本轮对Modbus V0.3是否产生新地址需求

结论：

> **没有。**

Design06使用的所有输入/输出/配置/未来诊断，都已经被V0.3覆盖。

地址仍：

```text
40001～40064
40101～40124
40201～40280
```

不继续扩张。

---

# 65. Design06完成后的冻结结论

当前已经可以正式冻结：

### 一套15策略

```text
永远只有一份
```

### 一个可切换P协调接口

```text
BASELINE
EXECUTION_AWARE
```

### 一个统一Board控制API

```text
reset
init
reconfigure
step
commit
abort_pending
```

### 一个统一输入

```text
ControllerInput
```

### 一个统一配置

```text
ControllerConfig
```

### 一个统一Plant控制输出

```text
ControllerOutput
```

### 一个统一诊断

```text
ControllerDiagnostics
```

### 一个显式状态实例

```text
ControllerContext
```

---

# 66. 下一步

Design06之后，不再继续增加外围架构。

下一步正式进入：

# BOARD15 C迁移阶段 C01
# `strategy15_core.c/.h`

只做第一件事：

> 把当前 `Advanced_Strategy_Core1.m` 的S1～S15判断层，按照Design05的状态规则转换成显式C状态结构，并用同一批离线输入逐周期比较15×4输出。

先证明：

```text
status[15]
alarm[15]
metric[15]
cmd[15]
```

C版与Golden Reference一致。

C01通过后，才进入P Normalizer / Arbiter。
