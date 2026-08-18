# BOARD15 内部设计02｜安全机制继承与全控制域升级原则 V0.1
## —— 从 V3.2 通信安全 + V4 candidate/commit + V5-A 最终保持，升级到完整15策略、P/Q/模式/断路器/重同步

> **日期**：2026-08-17  
> **性质**：内部设计文件，暂不作为工程开发方版本要求。  
> **前置文件**：`BOARD15_内部设计01_LOCAL15到BOARD15_C接口冻结审计_V0.1.md`  
> **目的**：先冻结 BOARD15（板端15策略）安全架构的总原则，再进入执行周期、多速率调度、Modbus点表和最终工程程序要求设计。
>
> 本文件不推翻 V3.2 / V4 / V5-A，而是回答：
>
> 1. 哪些旧安全机制必须保留；
> 2. 为什么完整15策略以后旧机制“不够覆盖”；
> 3. FC03失败和FC16失败分别代表什么；
> 4. 不同内部状态在通信异常时如何处理；
> 5. P、Q、模式、Breaker（断路器）、Fref（频率参考）如何共享统一安全框架；
> 6. 哪些安全责任在Board（控制板），哪些必须留在RT-LAB；
> 7. 为后续算法模块升级应该提前保留哪些通用状态接口。

---

# 0. 一句话结论

BOARD15 的安全机制不是：

```text
重新做一套
```

而是：

```text
V3.2：
通信 / 数据安全
        ↓
V4：
candidate / commit
（候选状态 / 成功提交）
        ↓
V5-A：
板端真实接管
+ RT-LAB最后HOLD
        ↓
BOARD15：
把以上机制扩展到
P + Q + GridOn + Droop + Breaker + Fref
+ 15策略状态机
+ 黑启动
+ 并离网
+ 重同步
```

所以最终原则是：

> **继承旧机制，扩大保护范围，细化状态更新规则，不推翻已经验证成功的安全基线。**

---

# 1. BOARD15 相比 V4 / V5-A 到底新增了什么

## 1.1 V4主要控制对象

V4主要围绕基础AGC：

```text
PCC / PVmax / SOC
↓
C版基础AGC
↓
6 × Pref
```

而且V4仍是Shadow（影子）阶段。

## 1.2 V5-A真实控制对象

V5-A第一次真正让板端：

```text
6 × Pref
```

进入六台设备。

已经形成：

```text
BOARD_CMD
↓
EXTERNAL_COMMAND_VALID
↓
TAKEOVER
↓
FINAL_APPLIED
↓
Plant
```

## 1.3 BOARD15控制对象

完整15策略以后，板端将不只产生6路有功命令。

至少涉及：

```text
6 × Pref
6 × Qref

6 × GridOn
6 × Droop

PCC Breaker request

ESS synchronization / Fref trim

system mode
master selection

black-start stage
resynchronization stage
```

所以：

> **安全机制必须从“保护6路Pref”升级成“保护一个完整控制帧及其状态机”。**

---

# 2. 三层安全架构正式冻结

以后所有周期、点表和程序主循环设计，都服从下面三层。

---

## Layer 1：Communication & Data Safety
## 通信与数据安全层

来源：

```text
V3.2
```

负责回答：

> **现在板端得到的RT-LAB信息是否可信，板端是否还有资格形成新的闭环控制决策？**

包含：

```text
TCP connection
FC03 result
MODEL_STATUS
RTLAB_HEARTBEAT
measurement freshness
range check
continuous-valid cycles

DISCONNECTED
WAIT_VALID
ENABLED
```

这一层不负责：

```text
S7到底怎么算
S15是否应该重合闸
```

它只负责：

```text
数据能不能信
```

---

## Layer 2：Controller Logic & State Safety
## 控制算法与状态安全层

来源：

```text
LOCAL15
+
V4 candidate/commit思想
```

负责回答：

> **数据可信时，当前策略应该做什么；算法内部哪些状态可以推进；哪些状态必须等命令成功发布以后才能确认？**

包含：

```text
Request Normalizer
P Objective / Constraint Manager
Arbitrated Baseline AGC
Q allocator
Mode Manager
Black Start
Resynchronization
```

以及：

```text
measurement-driven state
command-driven state
mode/recovery state
```

的不同更新规则。

---

## Layer 3：Plant-Side Final Execution Safety
## RT-LAB最终执行安全层

来源：

```text
V5-A
```

负责回答：

> **即使板端程序死机、网线断开或新命令不可用，Plant最后到底采用什么？**

核心：

```text
BOARD_HEARTBEAT fresh
+
Board command valid
↓
accept new committed frame

invalid
↓
HOLD / safe route
```

这一层必须留在RT-LAB。

原因：

```text
如果Board已经死机
Board自己无法再告诉RT-LAB：
“我失效了，请安全处理”
```

所以Plant侧必须具有最后独立判断权。

---

# 3. BOARD15中的四个关键状态必须严格区分

完整程序以后不能只使用一个模糊的：

```text
command
```

至少区分：

---

## 3.1 Measurement Snapshot
## 测量快照

定义：

```text
某一次成功FC03
+
完整解码
+
有效性检查通过
```

得到的：

```text
ControllerInput snapshot
```

它表示：

> **板端这一次真正知道了什么。**

---

## 3.2 u_calc
## 候选计算命令

定义：

```text
基于最新可信Measurement Snapshot
调用project15_core
得到的candidate output
```

它只是：

> **算法想发什么。**

还没有证明RT-LAB收到。

---

## 3.3 u_commit
## 成功提交命令

定义：

```text
完整candidate command frame
↓
合法性检查
↓
编码
↓
FC16成功
```

以后才成为：

```text
u_commit
```

它表示：

> **最近一次已经成功发布给RT-LAB的板端命令状态。**

---

## 3.4 u_applied
## Plant实际采用状态

定义：

```text
u_commit
↓
RT-LAB板端有效性判断
↓
最终安全路由
↓
可能的执行故障注入
↓
Plant
```

即：

```text
u_applied
```

它表示：

> **Plant最后真正采用什么。**

BOARD15算法不能把：

```text
u_commit
```

自动当作：

```text
u_applied
```

两者语义不同。

---

# 4. FC03失败与FC16失败必须拆开

这是BOARD15安全机制的核心。

---

# 4.1 FC03失败的含义

```text
FC03 failed
```

表示：

> **板端失去新的可信Plant状态。**

即：

```text
不知道当前PCC
不知道当前DER响应
不知道当前Grid/PCC同步量是否仍满足
```

所以：

```text
FC03 failed
≠
只是“少了一包数据”
```

而是：

```text
本周期没有fresh measurement
```

---

# 4.2 FC16失败的含义

```text
FC16 failed
```

表示：

> **板端知道系统当前状态，也已经算出了新的candidate，但这份candidate没有成功发布。**

因此：

```text
FC03 failure
= input side failure

FC16 failure
= output side failure
```

两个故障位置完全不同。

---

# 5. 四种FC03 / FC16组合的统一处理原则

| FC03 | FC16 | 实际含义 | 核心处理 |
|---|---|---|---|
| 成功 | 成功 | 输入可信，新命令成功发布 | 正常推进 |
| 成功 | 失败 | 知道当前状态，但候选命令没有成功发布 | 不commit命令类状态 |
| 失败 | 可写/成功发送安全帧 | 不知道当前状态，但通信链尚能写 | 不计算新闭环命令，撤销控制有效资格 |
| 失败 | 失败 | 完整通信异常 | 进入DISCONNECTED，由RT-LAB心跳安全层接管 |

这一张表后续必须进入最终主循环设计。

---

# 6. FC03失败时：哪些事情必须立即停止

只要当前需要的新Measurement Snapshot不存在：

```text
FC03 failed
OR
required data invalid
OR
measurement stale
```

则：

```text
不得基于旧PCC继续产生新的闭环P命令
不得基于旧Q/V继续产生新的AVC命令
不得基于旧V/f/phase继续推进S15同步判据
不得把“上一批测量”伪装成“当前测量”
```

---

# 7. FC03失败时：不同状态怎么处理

这部分不能“一刀切”。

---

## 7.1 Measurement / Statistics State
## 测量/统计状态

例如：

```text
demand_avg
peak_power
energy accumulation
historical measurement statistics
```

规则：

```text
有新的有效测量：
更新

FC03失败：
保持已有值
本周期不更新

不回滚
不虚构
```

例如：

```text
peak_power已经真实记录600 kW
↓
FC03失败
↓
仍然保持600 kW
```

不能退回旧峰值。

---

## 7.2 Command Allocation State
## 命令/资源分配状态

例如：

```text
AGC Ppv
AGC Pess
AGC Pev
```

规则：

```text
FC03失败
↓
不调用新的正常AGC step
↓
不生成新的allocation candidate
↓
正式allocation state保持
```

因为没有新的可信PCC/PVmax/SOC，不应继续闭环分配。

---

## 7.3 Continuous-Validity Timer
## 连续有效条件计时器

例如：

```text
S15 sync_timer
WAIT_VALID valid_count
```

它们的含义是：

```text
连续满足
```

所以：

```text
FC03失败
required sync data invalid
phase invalid
```

以后：

```text
连续性已经断裂
```

规则：

```text
reset to zero
```

而不是：

```text
继续计时
```

也不是默认：

```text
暂停后从旧0.42 s继续
```

例如：

```text
sync_timer = 0.42 s
↓
FC03失效
↓
sync_timer = 0
```

恢复后重新证明完整：

```text
SYNC_STABLE_S
```

---

## 7.4 Confirmed Mode State
## 已确认运行模式

例如系统已经处于：

```text
ISLANDED
```

FC03失败不能：

```text
自动变回GRID_CONNECTED
```

规则：

```text
已确认模式：
保持

依赖新测量的后续状态转移：
禁止
```

所以：

```text
ISLANDED
+
FC03 failed
↓
still ISLANDED
但是不能继续推进RESYNCHRONIZATION / RECLOSE
```

---

# 8. FC16失败时：状态处理原则

FC16失败时：

```text
最新Measurement Snapshot
可能完全正常
```

所以测量历史可以正常记录。

但：

```text
candidate command
```

没有成功发布。

因此：

---

## 8.1 Command State

规则：

```text
candidate command
candidate allocation state

↓ FC16 failed

discard / do not commit

official u_commit stays unchanged
CMD_SEQ stays unchanged
```

继承V4。

---

## 8.2 Measurement State

不能因为FC16失败：

```text
回滚peak_power
回滚测量统计
```

因为真实测量已经发生。

---

## 8.3 Mode Request

如果本轮算法计算：

```text
PCC_OPEN_REQUEST
```

但FC16失败：

```text
requested state
可以在诊断中记录

executed/committed mode
不能宣称已经完成
```

所以：

```text
request
≠
commit
≠
execution
```

---

# 9. FC03失败但FC16仍可写时怎么处理

这是必须提前定义的边界工况。

推荐行为：

```text
FC03 failed
↓
no new controller step
↓
keep last committed control state internally
↓
controller valid request = 0
↓
if TCP write path still works:
send a safety/status frame
```

这个frame的意义：

```text
BOARD程序仍活着
但是Board当前输入不可信
不要接受新的闭环控制更新
```

注意：

```text
BOARD_HEARTBEAT
仍可以继续增加
```

因为：

```text
“板端程序活着”
```

和：

```text
“控制数据有效”
```

不是一回事。

---

# 10. 完整断线时为什么还需要RT-LAB最后安全层

如果：

```text
FC03失败
+
FC16也失败
+
TCP断开
```

Board已经没有办法写：

```text
enable = 0
```

所以RT-LAB必须独立使用：

```text
BOARD_HEARTBEAT timeout
```

把：

```text
EXTERNAL_COMMAND_VALID
```

撤销。

然后：

```text
Plant HOLD LAST_APPLIED
或进入定义好的safe route
```

这个功能不能移到Board。

---

# 11. 通信恢复后不能立刻恢复控制

继续继承V3.2：

```text
DISCONNECTED
↓
TCP reconnect
↓
WAIT_VALID
↓
连续N批有效测量
↓
ENABLED
```

当前历史基线：

```text
valid_cycles_before_enable = 3
```

恢复后的第一包不能：

```text
立即取得完整控制权
```

而且：

```text
故障期间不补算历史AGC周期
```

恢复后以：

```text
新的fresh snapshot
```

继续。

---

# 12. 单一 `measurements_valid` 已不足以覆盖BOARD15

V3.2时，安全判断主要服务：

```text
基础AGC
```

因此可以把核心量归成：

```text
AGC required measurement valid
```

但BOARD15以后：

```text
S3需要Q / V
S5需要电气V/f
S8需要V/f
S15需要Grid/PCC V/f/phase
P控制需要PCC/PVmax/SOC
```

所以：

> **某一个测量坏了，不应机械地把所有控制域全部判死，也不能让与它相关的控制域继续运行。**

---

# 13. 推荐采用Control-Domain Validity
# 控制域有效性

第一版建议至少有：

```text
P_DOMAIN_VALID
Q_DOMAIN_VALID
MODE_DOMAIN_VALID
SYNC_DOMAIN_VALID
```

---

## 13.1 P_DOMAIN_VALID

用于：

```text
S1/S2/S4/S6/S7/S9/S10/S11/S12/S13
+
Baseline AGC
```

依赖至少包括：

```text
PCC P
PVmax
SOC
以及具体策略需要的P相关状态
```

---

## 13.2 Q_DOMAIN_VALID

用于：

```text
S3 AVC
```

依赖：

```text
PCC Q
PCC V
必要的P命令/视在容量信息
```

---

## 13.3 MODE_DOMAIN_VALID

用于：

```text
S5
S8
S14
S15模式判断
```

依赖：

```text
PCC V
PCC f
Grid presence / relevant model state
```

具体映射在点表设计阶段冻结。

---

## 13.4 SYNC_DOMAIN_VALID

用于：

```text
S15 RESYNCHRONIZATION
RECLOSE
```

要求最严格：

```text
Grid V valid
PCC V valid

Grid f valid
PCC f valid

Grid phase valid
PCC phase valid
phase_valid = 1

freshness满足
```

只有：

```text
SYNC_DOMAIN_VALID = 1
```

才允许：

```text
sync_timer累计
```

---

# 14. 全局Board控制有效与域有效不是同一件事

需要区分：

```text
BOARD_COMMUNICATION_AVAILABLE
```

和：

```text
P_DOMAIN_VALID
Q_DOMAIN_VALID
MODE_DOMAIN_VALID
SYNC_DOMAIN_VALID
```

以及：

```text
BOARD_OUTPUT_FRAME_VALID
```

例如：

```text
PCC_Q测量异常
```

可能：

```text
P_DOMAIN_VALID = 1
Q_DOMAIN_VALID = 0
SYNC_DOMAIN_VALID按其它量判断
```

而不是简单：

```text
全系统立即全部掉线
```

但：

```text
TCP断线
```

则可以导致：

```text
全部domain不能取得fresh input
```

---

# 15. 一个完整Board command frame应该怎么理解

BOARD15以后下行不能把每一个控制量看成互相独立的小命令。

推荐理解为一份：

```text
Command Frame
```

包括：

```text
6 Pref
6 Qref
6 GridOn
6 Droop
PCC Breaker
Fref trim / sync command
mode
master
status / valid
CMD_SEQ
BOARD_HEARTBEAT
```

原则：

> **一批控制决策尽量作为一个逻辑快照进行编码、写入、成功判断和commit。**

这样避免：

```text
Pref是新一拍
Qref还是旧一拍
Breaker又是另一拍
```

造成跨周期混合。

最终是否必须单个FC16覆盖全部寄存器，要结合地址数量和Modbus限制在点表阶段决定，但**逻辑上必须保持一个统一Command Frame版本号/序号语义。**

---

# 16. BOARD15的candidate / commit应该作用到哪里

不是：

```text
整个Project15State
一刀切复制 / 回滚
```

而是：

---

## 16.1 必须commit后确认的状态

主要是：

```text
command allocation state
command-generating state
committed mode request
committed breaker request
committed Fref action
```

这些状态代表：

> **板端认为已经成功发布了什么。**

---

## 16.2 不依赖commit的状态

主要是：

```text
measurement history
statistics
diagnostic observation
```

这些代表：

> **板端已经真实观察到什么。**

---

## 16.3 条件式推进的状态

主要是：

```text
black-start stage
resynchronization state
sync timer
reclose timer
mode transition
```

这些既依赖：

```text
fresh measurements
```

也依赖：

```text
相关控制动作是否已经成功发布
```

因此需要独立阶段规则。

---

# 17. S14 / S15必须采用Requested → Committed → Stage Progress思想

例如离网：

```text
Strategy:
request OPEN PCC

↓
candidate frame

↓
FC16 success

↓
OPEN request committed

↓
RT-LAB command route valid

↓
后续阶段才能继续
```

不能：

```text
算法刚刚算出OPEN
↓
内部立刻进入“已离网完成”
```

同理重合闸：

```text
sync condition continuously valid
↓
CLOSE candidate
↓
successful commit
↓
才能进入reclose hold / next stage
```

---

# 18. 是否需要Plant执行反馈确认

这是当前**保留待决策**的一项。

理想执行链：

```text
request
↓
successful FC16
↓
RT-LAB accepts frame
↓
physical command route applied
↓
RT-LAB returns execution status
```

如果最终新点表能够提供：

```text
FINAL_BREAKER_STATE
FINAL_MODE_STATE
FINAL_APPLIED_SEQ
```

那么：

```text
requested
committed
executed
```

可以真正完整闭环。

如果不增加：

```text
Plant execution acknowledgement
```

则至少：

```text
successful FC16
+
Board output validity
```

只能定义：

```text
committed
```

不能严格声称：

```text
physical action definitely completed
```

这一点留给Modbus点表设计阶段决定。

---

# 19. RT-LAB最终安全层必须覆盖哪些输出域

BOARD15以后不能只保护：

```text
Pref
```

至少需要覆盖：

```text
P command
Q command
mode command
breaker command
Fref / synchronization command
```

但失效时各域未必使用完全同一个Fallback（回退）：

---

## 19.1 P / Q

可能：

```text
HOLD LAST_APPLIED
```

作为主原则。

---

## 19.2 Breaker

不能因为Board失效：

```text
自动反转Breaker命令
```

例如已经离网时Board掉线：

```text
不能因为失效就自动闭合PCC
```

更合理的是：

```text
保持已确认安全状态
```

---

## 19.3 GFM / GFL

同样不能：

```text
Board失效
→ 盲目恢复GFL
```

如果系统已经孤岛：

```text
必须保持至少一个ESS GFM
```

所以模式域失效处理需要：

```text
state-aware fallback
```

而不是普通Pref的简单HOLD复制。

---

## 19.4 S15重同步

Board / sync data失效：

```text
禁止新重合闸动作
sync qualification失效
```

原则：

```text
fail-safe = no new reclose
```

---

# 20. Board内部算法和RT-LAB最后安全层的职责分界

Board负责：

```text
我现在想做什么
我的数据是否可信
我的控制状态如何推进
这一帧是否成功发布
```

RT-LAB负责：

```text
这一帧是否仍然fresh
Board是否还活着
最后是否接受新帧
Plant真正采用哪一个命令
失效时Plant最后安全行为
```

两边都要有安全机制，不重复也不冲突。

---

# 21. 推荐预留的公共通信状态接口

即使当前PROJECT15不全部使用，建议主程序将以下状态做成统一内部Context（上下文）：

```c
bool fc03_success;
bool fc16_success;

bool measurement_fresh;
bool measurement_channel_valid;
bool command_channel_valid;

bool p_domain_valid;
bool q_domain_valid;
bool mode_domain_valid;
bool sync_domain_valid;

bool controller_enabled;

uint16_t last_committed_cmd_seq;
bool has_committed_command;
```

这些是通用软件基础，不绑定某一种未来算法。

---

# 22. Board Heartbeat与Control Valid必须继续分开

重要：

```text
BOARD_HEARTBEAT
```

表示：

> **程序还在运行。**

而：

```text
CONTROL_VALID
```

表示：

> **当前控制输入、算法状态和输出条件允许RT-LAB采用Board命令。**

所以可能出现：

```text
BOARD_HEARTBEAT正常
CONTROL_VALID=0
```

例如：

```text
FC03测量无效
```

这完全正常。

不能把：

```text
程序活着
```

等同：

```text
控制有效
```

---

# 23. CMD_SEQ继续代表什么

继续继承V4核心语义：

> **CMD_SEQ只代表成功发布的新控制命令版本。**

不代表：

```text
主循环运行次数
heartbeat次数
FC03次数
```

推荐：

```text
candidate output generated
↓
valid
↓
encoded
↓
successful full command publication
↓
CMD_SEQ increment
```

如果：

```text
FC16 failed
HELD
no new control output
```

则：

```text
CMD_SEQ不变
```

---

# 24. 恢复以后“继续”还是“重置”不能一刀切

通信恢复：

```text
WAIT_VALID
↓
continuous valid
↓
ENABLED
```

以后：

---

## Measurement statistics

继续已有累计状态，不因为普通通信恢复清零。

---

## Command allocation state

从最后正式：

```text
u_commit / committed allocation state
```

继续。

---

## sync_timer

已经因连续可信条件中断清零：

```text
从0重新累计
```

---

## confirmed mode

保留当前已确认模式，不因TCP reconnect自动恢复并网。

---

## scheduler

不得补算断线期间所有历史周期。

---

# 25. BOARD15安全架构第一版状态图

```text
                 TCP unavailable
              ┌──────────────────┐
              ▼                  │
        DISCONNECTED             │
              │                  │
        TCP connected            │
              ▼                  │
          WAIT_VALID             │
              │                  │
      N fresh valid snapshots    │
              ▼                  │
           ENABLED               │
              │                  │
     ┌────────┼──────────┐       │
     │        │          │       │
 FC03 bad  data bad   heartbeat   │
     │        │          │       │
     └────────┴──────► WAIT_VALID │
                                  │
                    connection lost
                                  │
                                  └──► DISCONNECTED
```

在ENABLED内部：

```text
fresh snapshot
↓
domain validity
↓
strategy / controller
↓
candidate output
↓
check / encode
↓
publish command frame
↓
success?
   ├─ yes → commit + CMD_SEQ++
   └─ no  → no commit
```

---

# 26. BOARD15安全原则冻结清单

本轮建议正式冻结以下原则：

1. **V3.2三状态通信安全机继续保留，不重新设计另一套TCP安全框架。**

2. **V4 candidate/commit继续保留，但只用于“与成功发布命令绑定”的内部状态，不覆盖所有统计/观测状态。**

3. **V5-A RT-LAB最后Board有效性判断继续保留，并从Pref扩展到完整控制域。**

4. **FC03失败和FC16失败必须区分：前者代表没有fresh input，后者代表candidate没有成功发布。**

5. **FC03失败时不得使用旧测量继续形成新的正常闭环控制决策。**

6. **测量统计状态FC03失败时保持，不回滚、不虚构更新。**

7. **要求连续可信的计时器（尤其S15 sync_timer）在关键输入失效时清零。**

8. **FC16失败时命令类candidate不得commit，CMD_SEQ不得增加。**

9. **运行模式必须区分requested / committed / executed语义。**

10. **S14/S15不能依赖未成功发布的命令继续推进后续阶段。**

11. **Board heartbeat和Control valid必须分开。**

12. **恢复后先WAIT_VALID重新证明连续有效，不立即取得控制权。**

13. **恢复后不补算通信异常期间的历史控制周期。**

14. **BOARD15采用P/Q/MODE/SYNC域有效性，而不是依赖一个笼统measurements_valid覆盖全部控制。**

15. **RT-LAB必须保留Board完全失效时的最后独立安全层。**

16. **Breaker和GFM/GFL失效处理必须state-aware（根据当前状态），不能简单等同于Pref HOLD。**

17. **所有板端控制输出逻辑上构成统一Command Frame，并具有一致的CMD_SEQ版本语义。**

18. **是否增加Plant执行反馈确认，在BOARD15 Modbus点表设计时正式决定。**

---

# 27. 这一步解决了什么

完成本文件以后，我们已经不再模糊地说：

```text
“通信异常就HOLD”
```

而是知道：

```text
哪里坏了
↓
哪类状态受影响
↓
哪些状态保持
↓
哪些状态不commit
↓
哪些连续计时器清零
↓
哪些模式不能继续转移
↓
RT-LAB最后如何兜底
```

这样下一步设计周期和点表时才不会自相矛盾。

---

# 28. 下一设计节点

下一步正式进入：

# BOARD15 内部设计03
# Sample-Time / Multi-Rate Audit
# 执行周期与多速率调度审计

需要逐一回答：

```text
FC03基本刷新周期应该多快？

FC16 command frame多快？

V3.2心跳多久更新？

S1～S15分别需要什么时间尺度？

Baseline AGC继续1 s是否合理？

S3 AVC需要多快？

S6平滑需要多快？

S5/S8电气保护判断需要多快？

S14黑启动状态机需要多快？

S15重同步为什么不能跟1 s AGC共用周期？

Runtime Config多久读取/应用？

CSV日志多久记录？
```

最终目标是得到：

```text
Communication Task
Fast Supervisory Task
Strategy Task
AGC Task
Logging Task
```

各自明确的执行周期和调用关系。

只有这一步完成以后，才能真正冻结：

```text
BOARD15主循环
+
Modbus寄存器刷新架构
+
最终给工程开发方的调度要求
```
