# BOARD15 内部设计05｜Project15State逐变量更新、冻结、candidate/commit与恢复规则 V0.1
## ——从LOCAL15 persistent / Unit Delay语义迁移到板端C状态机

> **日期**：2026-08-18  
> **性质**：内部设计文件，不直接作为工程开发方最终版本要求。  
> **前置基线**：
> - LOCAL15 已完成15/15闭环验收，是BOARD15算法迁移的Golden Reference（黄金参考）。
> - BOARD15主循环：100 ms。
> - 仲裁型基础AGC周期：1 s。
> - V3.2通信状态机：`DISCONNECTED / WAIT_VALID / ENABLED`。
> - V4核心原则：命令相关状态使用 `candidate → FC16成功 → commit`。
> - V0.2点表已经区分Fast Measurement、Runtime Config和Command Frame。
>
> **本轮目标**：
>
> > 不再笼统地说“所有persistent都保存”或者“所有state都candidate/commit”，而是把PROJECT15中每一类真正的历史状态按物理语义分类，明确在正常、FC03失败、FC16失败、通信恢复、运行时配置变化和新实验Reset时到底怎么处理。

---

# 1. 先给最终结论

BOARD15中的状态不能只有一个：

```c
Project15State state;
```

然后每个周期全部：

```text
candidate = state
↓
计算
↓
FC16成功
↓
state = candidate
```

这样做是错误的。

因为有些状态代表：

```text
“我已经真实观察到了什么”
```

例如：

```text
需量平均值
峰值功率
累计PV能量
```

它们和FC16写命令是否成功没有关系。

而有些状态代表：

```text
“我认为已经成功发布了什么控制动作”
```

例如：

```text
AGC六资源分配记忆
S6平滑控制参考
模式切换状态
重合闸恢复阶段
```

这些就必须和命令成功发布绑定。

所以最终Project15状态拆成：

```text
Project15State
├─ ObservationState
│  测量/统计历史状态
│
├─ QualificationState
│  连续条件判断/资格计时状态
│
├─ AgcCommandState
│  仲裁型基础AGC命令记忆
│
├─ S6CommandState
│  PV平滑命令参考状态
│
├─ ModeExecutionState
│  孤岛/黑启动/模式执行状态
│
└─ RecoveryState
   S15重同步/重合闸恢复状态
```

同时：

```text
Pending Command Frame
CMD_SEQ
BOARD_HEARTBEAT
DISCONNECTED/WAIT_VALID/ENABLED
CONFIG_SEQ
```

不属于`Project15State`，继续由工程主程序管理。

---

# 2. 当前真实代码中到底有哪些历史状态

## 2.1 原15策略核心已有persistent

当前`Advanced_Strategy_Core1.m`实际保存：

```text
last_t
demand_avg
peak_power
pv_prev
self_use_energy
export_energy
pv_energy
curtailed_energy
black_state
switch_timer
```

其中并不是同一种状态。

---

## 2.2 基础AGC已有persistent

当前`AGC_Controller.m`实际保存：

```text
Ppv[2]
Pess[2]
Pev[2]

last_t
status
last_dP
last_remain
```

这些量共同描述：

> 最近一次正式AGC分配以后，六类资源目前被认为处于什么有功命令状态。

---

## 2.3 S6真实执行器已有persistent

当前S10的S6辅助执行核心实际保存：

```text
initialized
last_t
smooth_ref
```

其中：

```text
smooth_ref
```

不是普通测量统计量。

它代表：

> 平滑控制器当前内部使用的“受爬坡率限制的PV目标轨迹”。

它会直接决定ESS补偿命令。

---

## 2.4 S13模式执行状态

LOCAL15 Stage13已经明确把以下状态从MATLAB Function persistent改成显式Unit Delay：

```text
island_latch
black_latch
```

这说明它们本质上属于：

> **系统模式执行记忆**

而不是普通策略计算中间量。

---

## 2.5 S15恢复状态

LOCAL15 Stage15使用显式Unit Delay保存：

```text
recovery_state
sync_timer
reclose_timer
```

当前模式：

```text
0 IDLE
1 RESYNCHRONIZATION
2 RECLOSE_HOLD
3 CLEAR_ISLAND_LATCH_WAIT
```

它们属于：

> **受控恢复状态机**

---

# 3. 第一类：ObservationState
# 测量/统计历史状态

建议最终：

```c
typedef struct {
    bool initialized;
    double last_valid_time_s;

    double demand_avg_kw;
    double peak_import_kw;

    double pv_prev_kw;

    double self_use_energy_kwh;
    double export_energy_kwh;
    double pv_energy_kwh;
    double curtailed_energy_kwh;
} StrategyObservationState;
```

---

# 4. `demand_avg`怎么更新

含义：

> 当前需量窗口/需量估计的历史状态。

规则：

### 正常fresh FC03

```text
测量有效
↓
按照真实dt更新demand_avg
```

### FC16失败

```text
照常更新
```

原因：

> 今天真实发生的进口功率不会因为Board写命令失败而“没有发生”。

### FC03失败 / measurement invalid

```text
冻结
不更新
```

### 恢复

不能：

```text
把通信异常期间整段时间用最后一个旧PCC值补积分
```

所以恢复第一份fresh snapshot：

```text
last_valid_time_s = now
本拍不对断线时段做追补
```

下一拍再正常更新。

---

# 5. `peak_power`怎么更新

含义：

> 当前运行周期内已经真实观察到的最大进口功率。

规则：

```text
fresh有效测量
→ peak = max(peak, current_import)

FC03失败
→ 保持

FC16失败
→ 仍可更新

普通通信重连
→ 不清零
```

因为已经真实发生过的峰值不能因为通信失败被回滚。

只有：

```text
显式Controller Reset
```

才清零。

---

# 6. 能量累计量怎么更新

包括：

```text
self_use_energy
export_energy
pv_energy
curtailed_energy
```

统一规则：

```text
fresh + valid测量
→ 按dt积分

FC03失败/测量非法
→ 不积分

通信恢复
→ 不补算缺失时间

FC16失败
→ 正常积分

普通reconnect
→ 保持历史累计
```

因此：

> **能量历史属于Plant已经真实发生的事实，不能由命令发布成功与否决定。**

---

# 7. `pv_prev`怎么处理

原策略S6判断PV变化率时需要上一批PV可用出力。

它属于：

```text
measurement history
```

但有一个特殊规则。

### 连续fresh测量

```text
pv_prev = 上一批fresh PV
```

### FC03失败

```text
保持旧值
```

### 恢复第一拍

不要立刻：

```text
旧pv_prev
和
中断很久后的新PV
```

直接当成一个100 ms变化。

恢复第一拍：

```text
pv_prev = current_pv
last_valid_time = now
```

重新建立测量基线。

这样不会制造虚假的巨大PV ramp（爬坡率）。

---

# 8. 第二类：QualificationState
# 连续条件/资格判断状态

包括至少：

```text
raw_s15_switch_timer
```

以及通信主程序自己的：

```text
valid_count
```

其中`valid_count`不放Project15State。

建议：

```c
typedef struct {
    double s15_switch_timer_s;
} StrategyQualificationState;
```

---

# 9. 原S15 `switch_timer`规则

这个量只是原15策略判断层用来描述：

> 孤岛/切换条件持续了多久。

它不是“已经执行到哪个物理模式”。

因此：

### fresh有效测量 + 原S15条件成立

```text
switch_timer += dt
```

### 条件消失

```text
switch_timer = 0
```

### FC03失败 / 测量非法

```text
switch_timer = 0
```

原因：

> 它表达“连续满足”，数据中断以后连续性已经不能证明。

### FC16失败

```text
可以继续按fresh测量更新
```

因为它只是策略判断指标，不代表命令已经执行。

---

# 10. 第三类：AgcCommandState
# 仲裁型基础AGC命令状态

建议：

```c
typedef struct {
    double pv_kw[2];
    double ess_kw[2];
    double ev_charge_kw[2];

    double last_update_time_s;

    int status;
    double last_dp_kw;
    double last_remain_kw;

    bool initialized;
} AgcCommandState;
```

---

# 11. 为什么AGC状态必须candidate/commit

当前AGC内部：

```text
Ppv
Pess
Pev
```

并不是“真实测量”。

它们代表：

> AGC上一次认为已经分配给六资源的命令状态。

如果：

```text
AGC candidate算出了新Ppv/Pess/Pev
↓
FC16失败
```

但内部仍然更新了：

```text
Ppv/Pess/Pev
```

下一次算法就会认为：

```text
“上一次新命令已经发出”
```

实际上Plant仍执行旧命令。

这就是控制器内部状态和真实发布命令发生失步。

因此必须：

```text
official AgcCommandState
↓ copy
candidate AgcCommandState
↓
AGC step
↓
candidate Pref
↓
FC16
```

### FC16成功

```text
official = candidate
```

### FC16失败

```text
official保持不变
```

---

# 12. AGC `last_t`也必须随commit

不能出现：

```text
AGC在10.0 s计算新命令
FC16失败

但last_t已经变成10.0
```

因为这样算法会认为：

```text
10.0 s已经完成了一轮正式AGC更新
```

所以：

```text
last_update_time_s
```

也属于candidate AgcCommandState。

只有成功发布新AGC命令后才正式推进。

---

# 13. 单次FC16失败后的AGC处理

继续继承V4思想：

```text
candidate已经计算
FC16失败
↓
candidate暂时保留
official不变
```

如果下一100 ms周期：

```text
TCP仍连接
输入通道仍正常
没有进入WAIT_VALID/DISCONNECTED
```

可以优先：

```text
重试同一份控制candidate
```

不重新把AGC往前算一轮。

但管理字段可以刷新：

```text
BOARD_HEARTBEAT
COMM_STATUS
```

控制内容和candidate AGC state不变。

---

# 14. 什么时候丢弃pending candidate

如果发生：

```text
FC03随后失败
测量变成invalid
进入WAIT_VALID
进入DISCONNECTED
RT-LAB模型重启
显式CONTROLLER_RESET
```

则：

```text
pending candidate丢弃
```

恢复以后从：

```text
最后正式committed AgcCommandState
```

和新的fresh snapshot重新计算。

不会在长时间中断后发送一份过时的旧candidate。

---

# 15. AGC通信恢复以后不补算历史周期

例如：

```text
最后一次AGC成功：
10 s

通信恢复：
16 s
```

不能：

```text
补算11、12、13、14、15、16六轮
```

正确：

```text
WAIT_VALID
↓
恢复控制资格
↓
使用当前fresh snapshot
↓
最多运行一次当前AGC step
```

这是“没有历史catch-up（追补）”原则。

---

# 16. 第四类：S6CommandState
# S6平滑控制状态

建议：

```c
typedef struct {
    bool initialized;
    double smooth_ref_kw;
    double last_update_time_s;
} S6CommandState;
```

---

# 17. 为什么`smooth_ref`不能作为普通测量历史

S6当前实际命令：

```text
Pess_smooth
=
smooth_ref
-
PV_actual
```

所以：

```text
smooth_ref
```

直接参与产生ESS命令。

如果：

```text
smooth_ref已经向前推进
但FC16失败
```

下一拍就会假定上一拍平滑命令已经执行。

因此：

> **S6 active（正在执行平滑控制）时，smooth_ref属于命令状态，必须candidate/commit。**

---

# 18. S6不活动时如何处理

如果：

```text
S6未使能
或当前Mode不允许S6
```

则S6没有在实际产生控制动作。

此时每次fresh有效PV测量可以：

```text
smooth_ref = current_PV
last_update_time = now
```

作为“重新对齐当前PV”的基线。

这样下一次S6重新投入不会突然使用很久以前的平滑参考。

---

# 19. S6通信恢复规则

发生：

```text
FC03失效
WAIT_VALID
DISCONNECTED
```

以后：

```text
不继续累积历史平滑轨迹
```

恢复第一批有效测量：

```text
smooth_ref = current_PV
last_update_time = now
```

然后重新开始平滑。

这比：

```text
拿断线前smooth_ref
+
很长的dt
```

重新追赶更安全，也符合“不补算历史”的原则。

---

# 20. 第五类：ModeExecutionState
# 模式执行状态

LOCAL15 Stage13已经证明需要状态记忆：

```text
island_latch
black_latch
```

建议BOARD15：

```c
typedef struct {
    bool island_latch;
    bool black_latch;

    bool initialized;
} ModeExecutionState;
```

但BOARD15比LOCAL15多了一条重要真实证据：

```text
40122 EXEC_MODE_STATUS
40123 EXEC_SYSTEM_MODE
```

所以Board不再只相信自己内部“想切到什么模式”。

---

# 21. 模式状态必须区分三个概念

```text
requested
= 算法希望执行什么

committed
= 相关Command Frame已经FC16成功

confirmed
= RT-LAB下一批测量反馈：
  最终模式/Breaker确实进入相应状态
```

例如：

```text
Board请求PCC OPEN
```

不等于：

```text
PCC已经物理/模型侧处于OPEN
```

---

# 22. island_latch什么时候建立

候选逻辑仍沿用LOCAL15：

```text
S5 qualified electrical abnormality
+
S15 transition request
↓
island candidate
```

但BOARD15正式执行：

```text
candidate frame：
PCC open
selected ESS GFM
system mode ISLANDING/ISLANDED
```

只有：

```text
FC16成功
```

以后才允许把“已成功发布解列请求”记入command state。

而真正后续进入稳定ISLANDED后的阶段推进，应等待：

```text
EXEC_MODE_STATUS
EXEC_SYSTEM_MODE
```

确认。

---

# 23. black_latch什么时候建立

同样：

```text
S14黑启动请求
↓
candidate mode/breaker/GFM command
```

FC16成功：

```text
记录已发布
```

下一批RT-LAB确认：

```text
PCC open
master GFM
mode BLACK_START
```

以后才允许继续黑启动后续阶段。

---

# 24. 通信失败不能自动清除已经确认的孤岛/黑启动状态

如果系统已经：

```text
ISLANDED
```

此时FC03失败：

```text
不能：
island_latch = 0
```

也不能：

```text
自动返回GRID_CONNECTED
```

正确：

```text
保持最后已确认模式
禁止基于未知Plant状态继续推进新的阶段
```

---

# 25. 原LOCAL15 S13“execution未armed则清latch”的逻辑如何迁移

LOCAL15中关闭真实执行开关时：

```text
island_next = 0
black_next = 0
```

这是模型侧透明回归设计。

BOARD15 C中建议区分：

### `CONTROL_MASTER_ENABLE=0`且系统本来正常并网

```text
清除未完成的模式请求
保持监视
```

### Plant已经确认处于ISLANDED/BLACK_START

不能因为：

```text
CONTROL_MASTER_ENABLE暂时变0
```

就自动要求回并网。

应优先服从：

```text
RT-LAB confirmed execution state
```

保证失效安全。

---

# 26. S14黑启动状态如何处理

原15策略核心的：

```text
black_state
```

既是策略状态，又直接被S14 Pref Gate用于阶段执行。

这在Board通信失败场景下存在潜在问题：

```text
stage内部时间继续推进
但阶段命令可能没有成功发送
```

因此BOARD15建议把S14正式视为：

> **执行序列状态**

而不是普通观察状态。

---

# 27. S14 Board版建议状态

```c
typedef struct {
    int stage;          // 0~4，失败状态另定义
    double stage_entry_time_s;
    bool waiting_execution_confirm;
} BlackStartExecutionState;
```

阶段含义继续保持当前项目语义：

```text
Stage 1
六Pref=0，主ESS GFM建压

Stage 2
非主ESS逐步恢复

Stage 3
PV恢复

Stage 4
EV负荷恢复
```

---

# 28. 为什么建议用“stage entry time”而不是绝对Board时间

原始MATLAB策略使用：

```text
t > 20
t > 40
t > 60
```

这是原模型测试环境下的实现形式。

Board正式执行时更安全的等价工程语义是：

```text
从本次黑启动真正进入Stage 1开始计时
```

然后：

```text
Stage 1稳定20 s
→ Stage 2

Stage 2再稳定20 s
→ Stage 3

Stage 3再稳定20 s
→ Stage 4
```

如果黑启动从仿真0 s开始，两者正常测试行为一致。

这种实现避免：

```text
系统已经运行100 s
此时才触发黑启动
→ 原绝对t逻辑瞬间跳Stage 4
```

这是板端C迁移时应做的工程语义正规化。

---

# 29. S14阶段什么时候正式推进

满足：

```text
当前stage规定的时间/条件
+
fresh有效测量
+
相关执行路径可用
```

只形成：

```text
next_stage candidate
```

如果该阶段会改变：

```text
Pref
GridOn
Droop
Breaker
Mode
```

则：

```text
FC16成功
+
必要的RT-LAB EXEC_MODE_STATUS/EXEC_SYSTEM_MODE确认
```

以后才正式进入下一stage。

因此不会出现：

```text
Board内部已经Stage 4
Plant其实Stage 1命令都没收到
```

---

# 30. 第六类：RecoveryState
# S15重同步与重合闸恢复状态

建议：

```c
typedef struct {
    int state;

    double sync_timer_s;
    double reclose_timer_s;

    bool initialized;
} RecoveryState;
```

当前状态仍保持：

```text
0 IDLE
1 RESYNCHRONIZATION
2 RECLOSE_HOLD
3 CLEAR_ISLAND_LATCH_WAIT
```

---

# 31. `sync_timer`怎么更新

它不是普通计时器，而是在证明：

> **Grid和PCC连续满足重同步条件。**

只有同时满足：

```text
fresh measurement

PHASE_VALID

|ΔV| <= threshold
|Δf| <= threshold
|Δθ| <= threshold

当前处于确认的ISLANDED/RESYNCHRONIZATION

Board控制路径仍可用
```

才允许：

```text
sync_timer += dt
```

---

# 32. `sync_timer`什么时候必须清零

任何一个发生：

```text
FC03失败
measurement invalid
phase invalid
ΔV越限
Δf越限
Δθ越限
离开允许的恢复模式
进入DISCONNECTED/WAIT_VALID
```

则：

```text
sync_timer = 0
```

这保持“连续满足”的物理含义。

---

# 33. FC16失败时`sync_timer`怎么处理

如果只是：

```text
单次FC16失败
TCP仍连接
fresh测量正常
```

则本轮新的Recovery candidate不commit。

因此official：

```text
sync_timer
```

自然保持上一次值。

也就是：

```text
freeze
```

而不是继续前进。

如果FC16失败导致：

```text
command channel失效
WAIT_VALID/DISCONNECTED
```

则：

```text
sync_timer = 0
```

恢复后重新证明完整同步窗口。

---

# 34. `recovery_state`什么时候推进

### IDLE → RESYNCHRONIZATION

必须：

```text
RT-LAB确认当前ISLANDED
+
RECOVERY_REQUEST=1
+
SYNC/MODE输入有效
```

形成candidate。

成功发布恢复模式/Fref命令后：

```text
state = RESYNCHRONIZATION
```

---

### RESYNCHRONIZATION → RECLOSE_HOLD

必须：

```text
sync_timer达到阈值
↓
形成PCC_CLOSE candidate
↓
FC16成功
```

然后等待RT-LAB反馈：

```text
PCC_BREAKER_CLOSED=1
```

确认以后才真正开始：

```text
reclose_timer
```

---

### RECLOSE_HOLD → CLEAR_ISLAND_LATCH_WAIT

```text
PCC已确认闭合
+
reclose_timer达到设定保持时间
```

再形成：

```text
返回正常模式
清除island latch
selected ESS GFM→GFL
```

candidate。

---

### CLEAR_ISLAND_LATCH_WAIT → IDLE

必须看到：

```text
EXEC_SYSTEM_MODE = GRID_CONNECTED_NORMAL
PCC_BREAKER_CLOSED = 1
selected ESS已回GFL
```

以后：

```text
RecoveryState回IDLE
```

---

# 35. `reclose_timer`不能从“算出close请求”那一刻开始

应该从：

```text
RT-LAB确认PCC最终已闭合
```

开始。

原因：

> FC16发送成功只说明报文写入成功，不等于最终安全路由一定已经让Breaker闭合。

这也是我们设计：

```text
EXEC_MODE_STATUS
EXEC_SYSTEM_MODE
```

反馈的实际价值之一。

---

# 36. 哪些模块完全不需要persistent

以下模块应尽量保持pure/combinational（纯组合）：

```text
Request Normalizer
P Objective Arbiter
P Objective Constraint Manager
Execution Mapper
S3 AVC Normalizer
Q Allocator
S8 Load Shed allocation
Mode Manager的当前优先级判断
Device Mode mapping
Black Start Pref Gate
Fref Router
```

它们都应满足：

```text
相同输入
+
相同Config
+
相同正式State
=
相同输出
```

不要无意义地在里面继续增加历史变量。

---

# 37. 主程序还需要一个独立的CommandCommitState

这不属于Project15State。

工程主程序维护：

```c
typedef struct {
    bool has_committed_command;

    uint16_t cmd_seq;

    ControllerOutput last_committed_output;

    bool pending_valid;
    ControllerOutput pending_output;

    Project15CommandState pending_command_state;
} CommandCommitState;
```

其中：

```text
last_committed_output
```

就是Board内部正式的：

```text
u_commit
```

---

# 38. 为什么未来研究算法可以直接使用`u_commit`

以后执行状态感知算法需要：

```text
u_commit
↓
Pexpected
↓
Pmeas
```

因此没有必要通过Modbus把Board刚刚自己发出去的命令再读回来。

主程序本来就保存：

```text
last_committed_output
```

以后统一Controller Adapter把它提供给P协调子模块即可。

---

# 39. 新增一个必要的显式Controller Reset机制

设计05审计发现：

> 仅靠普通Modbus reconnect不能满足“每轮实验独立初始化”。

我们当前实验流程要求：

```text
Reset
↓
下一轮从干净算法状态开始
```

而V4又明确：

```text
普通通信重连
不能自动reset AGC
```

所以必须有显式：

```text
CONTROLLER_RESET_SEQ
```

---

# 40. 使用V0.2最后一个配置槽，不增加地址

V0.2：

```text
40280 FUTURE_CONFIG_01
```

现在正式定义为：

```text
40280 CONTROLLER_RESET_SEQ
```

类型：

```text
UINT16 count
```

因此不用再次扩展Runtime Config地址范围。

---

# 41. `CONTROLLER_RESET_SEQ`怎么用

每一次希望算法重新初始化：

```text
RT-LAB / Python
↓
将CONTROL_MASTER_ENABLE先设为0
↓
CONTROLLER_RESET_SEQ + 1
↓
最后CONFIG_SEQ + 1
```

Board完成原子配置读取后：

```text
发现reset_seq变化
↓
停止产生新真实控制
↓
清除pending candidate
↓
controller_reset()
↓
等待fresh有效Measurement Snapshot
↓
controller_init()
↓
WAIT_VALID
```

之后再通过新的Runtime Config：

```text
CONTROL_MASTER_ENABLE = 1
```

开始本轮测试。

---

# 42. Reset时哪些状态清零

显式controller reset：

### Observation

```text
demand_avg = 0
peak_power = 0
energy accumulators = 0
initialized = false
```

第一批fresh measurement重新建立：

```text
pv_prev
last_valid_time
```

---

### AGC

```text
initialized = false
Ppv/Pess/Pev重新按当前config + 当前fresh snapshot初始化
status = 0
last_dP = 0
last_remain = 0
```

---

### S6

```text
initialized = false
下一批fresh PV：
smooth_ref = current PV
```

---

### Mode

```text
内部未确认请求清除
```

但如果RT-LAB真实Plant已经处于：

```text
ISLANDED
BLACK_START
```

初始化以后必须读取：

```text
EXEC_MODE_STATUS
EXEC_SYSTEM_MODE
```

重新对齐当前真实执行模式。

不能盲目假定GRID_CONNECTED。

---

### Recovery

```text
state = IDLE
sync_timer = 0
reclose_timer = 0
```

如果Plant仍然处于ISLANDED：

```text
后续由当前exec feedback重新进入正确受控状态
```

---

# 43. `CMD_SEQ`是否随Controller Reset清零

建议：

> **不清零。**

理由：

```text
CMD_SEQ
= Board进程生命周期内成功发布命令的版本序号
```

而：

```text
CONTROLLER_RESET_SEQ
= 算法实验/初始化代次
```

两者语义不同。

因此：

```text
算法reset
↓
CMD_SEQ继续递增
BOARD_HEARTBEAT继续递增
```

这样不会让RT-LAB因为序号突然从500变0而产生额外歧义。

---

# 44. 普通Modbus reconnect和显式Controller Reset严格区分

## 普通reconnect

```text
不清AGC
不清能量统计
不清已确认模式
不清last committed command
```

只：

```text
进入WAIT_VALID
qualification timer清零
等待连续有效数据
```

---

## CONTROLLER_RESET_SEQ变化

才：

```text
真正重新初始化Project15State
```

这解决了：

```text
工程运行连续性
```

和：

```text
独立实验可重复性
```

之间的冲突。

---

# 45. FC03失败总规则

发生：

```text
FC03 failed
or
measurement invalid
```

统一：

### ObservationState

```text
freeze
```

### 原S15连续判断timer

```text
reset
```

### AGC

```text
不step
official保持
```

### S6

```text
不step
进入WAIT_VALID以后恢复时rebase
```

### Mode

```text
保持最后confirmed状态
禁止新阶段推进
```

### Recovery

```text
sync timer清零
禁止reclose
```

### Command

如果FC16仍可写：

```text
EXT_CONTROL_ENABLE=0
CMD_SEQ不变
BOARD_HEARTBEAT继续
```

---

# 46. FC16失败总规则

### ObservationState

```text
可以按本轮fresh测量正常更新
```

### AGC/S6/Mode/Recovery命令状态

```text
candidate不commit
official保持
```

### CMD_SEQ

```text
不增加
```

### pending candidate

如果通信仍正常：

```text
保留短期pending，下一周期优先重试
```

如果进入：

```text
WAIT_VALID / DISCONNECTED / measurement invalid
```

则：

```text
丢弃pending
```

---

# 47. Runtime Config变化时哪些状态不能乱清

普通参数变化：

```text
P目标
阈值
权重
策略enable
```

不应该：

```text
整个Project15State全部reset
```

否则调个目标就把：

```text
需量历史
能量统计
AGC状态
```

全删了。

---

# 48. Config变化的三类处理

## A. 普通阈值/目标变化

例如：

```text
TIE_TARGET
UV_THRESHOLD
Q_LIMIT
```

规则：

```text
新配置原子应用
状态保留
```

---

## B. 策略Enable变化

如果某个连续状态型策略被关闭：

```text
对应资格timer清零
```

例如：

```text
S15关闭
→ raw switch timer = 0
→ recovery不得继续推进
```

但：

```text
历史能量/需量统计
```

不需要全部清零。

---

## C. `CONTROLLER_RESET_SEQ`变化

才执行：

```text
完整Project15State reset
```

---

# 49. 一套15策略 + 一个可切换P协调模块

上一轮已经明确：

> Board里绝不是两套15策略。

因此V0.2点表中的：

```text
ALGORITHM_MODE
```

命名需要正式修正。

---

# 50. 点表命名修正

## 40202

V0.2：

```text
ALGORITHM_MODE
```

V0.3：

```text
P_COORDINATION_MODE
```

含义：

```text
0 = BASELINE
当前项目仲裁型基础AGC

1 = EXECUTION_AWARE
后续执行状态感知P协调
```

15策略、Q、Mode、S14、S15仍然只有一套。

---

## 40027

改为：

```text
P_COORDINATION_MODE_STATUS
```

表示Board当前实际运行的是哪一种P协调方式。

---

## 40061

改为：

```text
METHOD_VARIANT_STATUS
```

表示Execution-Aware内部：

```text
0 Baseline
1 Assessment
2 Assessment + Recovery
3 Full
```

当前PROJECT15/BASELINE阶段可以为0。

---

# 51. `P_COORDINATION_MODE`运行时切换的状态处理

以后我们自己做试验时：

```text
不找工程开发方改程序
```

而是Runtime Config改变：

```text
P_COORDINATION_MODE
METHOD_VARIANT
```

但切换时不能让P命令突然失步。

统一Controller Adapter以后必须做：

```text
旧P协调模块
↓
last committed 6 Pref
↓
新P协调模块initialize_from_committed_output()
↓
下一周期接管
```

也就是说：

> **方法切换只重新初始化P协调子模块，不重新初始化整套15策略。**

这是以后Design06/Execution-Aware模块要继续冻结的接口要求。

---

# 52. 最终状态更新矩阵

| 状态类别 | fresh FC03 | FC16成功 | FC16失败 | FC03失败 | reconnect | Controller Reset |
|---|---|---|---|---|---|---|
| `demand_avg` | 更新 | 无关 | 保留更新 | 冻结 | 继续 | 清零 |
| `peak_power` | 更新 | 无关 | 保留更新 | 冻结 | 继续 | 清零 |
| energy累计 | 更新 | 无关 | 保留更新 | 冻结 | 不补历史 | 清零 |
| `pv_prev` | 更新 | 无关 | 更新 | 冻结 | 首拍rebase | 重建 |
| raw `switch_timer` | 条件成立更新 | 无关 | 可更新 | 清零 | 重算 | 清零 |
| AGC `Ppv/Pess/Pev` | 生成candidate | commit | 不commit | 不step | 从last commit继续 | 重建 |
| AGC `last_t/status/dP/remain` | candidate | commit | 不commit | 保持 | 不补算 | 重建 |
| S6 `smooth_ref` active | candidate | commit | 不commit | 保持 | fresh首拍rebase | 重建 |
| `island_latch` | 形成请求 | 发布后可推进 | 不推进 | 保持confirmed | 对齐反馈 | 重新对齐反馈 |
| `black_latch/stage` | 条件候选 | 发布/确认后推进 | 不推进 | 保持 | 对齐反馈 | 重新初始化/对齐 |
| `sync_timer` | 满足同步条件candidate更新 | commit | freeze | 清零 | 清零后重证 | 清零 |
| `reclose_timer` | breaker确认后更新 | commit | freeze | 停止 | 重新确认 | 清零 |
| `recovery_state` | candidate | commit/反馈推进 | 不推进 | 保持安全状态 | 由exec feedback恢复 | IDLE后重新对齐 |
| last `u_commit` | 不直接变 | 更新 | 保持 | 保持 | 保持 | 主程序仍保留，控制禁用后新初始化 |

---

# 53. 建议的C结构

```c
typedef struct
{
    StrategyObservationState observation;

    StrategyQualificationState qualification;

    AgcCommandState agc;

    S6CommandState s6;

    ModeExecutionState mode;

    BlackStartExecutionState black_start;

    RecoveryState recovery;

} Project15State;
```

但主程序另外持有：

```c
CommunicationState comm;

RuntimeConfigState runtime_config;

CommandCommitState command_commit;
```

不要把通信和命令发布管理塞回`project15_core.c`。

---

# 54. 最终每100 ms控制周期的状态顺序

```text
1. FC03
↓
2. decode + measurement validity
↓
3. 若CONFIG_SEQ变化：
   原子读取配置
   必要时处理CONTROLLER_RESET_SEQ
↓
4. fresh有效：
   先更新ObservationState
↓
5. 从official command-related state复制candidate
↓
6. 运行：
   15策略
   Normalizer
   Arbiter
   P/Q/Mode/S14/S15
↓
7. 形成ControllerOutput candidate
↓
8. encode
↓
9. FC16
↓
10a. success：
     commit command-related candidate state
     更新last_committed_output
     必要时CMD_SEQ+1

10b. failure：
     official command state不推进
↓
11. 下一周期
```

---

# 55. 本轮新发现对点表的唯一必要修正

不需要推翻V0.2三块地址结构。

只修改四处：

```text
40202
ALGORITHM_MODE
→ P_COORDINATION_MODE

40027
ALGORITHM_MODE_STATUS
→ P_COORDINATION_MODE_STATUS

40061
CONTROL_VARIANT_STATUS
→ METHOD_VARIANT_STATUS

40280
FUTURE_CONFIG_01
→ CONTROLLER_RESET_SEQ
```

地址范围仍然：

```text
40001～40064
40101～40124
40201～40280
```

不扩展。

---

# 56. 本轮完成后，下一步是什么

现在已经冻结：

```text
接口边界
通信/安全原则
100 ms调度
Modbus点表
Project15状态更新规则
```

下一步应该进入：

# BOARD15 内部设计06
# `project15_core.c/.h`正式接口和模块文件结构冻结

具体确定：

```text
ControllerInput
ControllerConfig
Project15State
ControllerOutput

controller_reset()
controller_init()
controller_step()

Project15内部：
strategy_core
request_normalizer
p_objective
baseline_agc
s6_s8
q_allocator
mode_manager
black_start
s15_recovery
```

以及：

```text
哪些C文件由我们交付
工程开发方主程序怎样只通过Adapter调用
```

完成Design06后，才正式开始LOCAL15 → C代码转换。
