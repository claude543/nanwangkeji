# BOARD15 内部设计04 V0.2｜四项问题修正与最终点表冻结候选
## ——策略总使能、配置原子性、通信状态字、未来算法扩展容量

> **日期**：2026-08-18  
> **性质**：内部冻结候选，不直接作为工程开发方最终版本要求。  
> **本轮目的**：修正 V0.1 点表审计发现的四个问题，同时把后续已明确的算法发展路线提前纳入接口容量规划。  
> **原则**：不增加没有明确用途的功能；但对已经确定会做的后续算法和对比试验，必须提前留够接口，避免 BOARD15 完成后再次大改 Modbus 框架。

---

# 1. 修正一：`CFG_AA_enable` 与 `MASTER_ENABLE` 不合并成一个语义

## 1.1 最终决定

**不建议直接合并。**

原因是两者原本代表两个不同层次：

```text
CFG_AA_enable
= 15策略判断层是否运行

CFG15_MASTER_ENABLE
= LOCAL15/BOARD15的策略执行层是否允许真实控制Plant
```

如果简单合并，会失去一个很有价值的状态：

```text
策略可以继续计算、监视、记录
但暂时不允许真实接管设备
```

这在以下阶段都很有用：

```text
BOARD15首次联调
Shadow验证
通信恢复后的WAIT_VALID
单项策略诊断
算法对比试验
```

---

## 1.2 但也不增加一个新的运行时寄存器

我们没有必要再增加：

```text
STRATEGY_EVAL_ENABLE
```

作为用户可调参数。

BOARD15内部直接派生：

```text
strategy_eval_enable
=
measurement_fresh
AND measurements_valid
AND algorithm_mode有效
```

也就是说：

> 只要当前Board拿到了可信的新测量，就允许15策略判断层继续计算和产生状态/告警/指标。

而真正能否把结果送给Plant，由：

```text
CONTROL_MASTER_ENABLE
+
通信状态ENABLED
+
对应执行域有效
+
具体策略执行许可
```

共同决定。

---

## 1.3 40205正式改名

V0.1：

```text
40205 MASTER_ENABLE
```

V0.2：

```text
40205 CONTROL_MASTER_ENABLE
```

标准中文：

> **Board真实控制总使能**

含义：

```text
0
= 15策略仍可监视/计算，但不允许BOARD15形成新的真实控制接管

1
= 在通信、安全、策略许可均满足时，BOARD15可以真实执行
```

因此：

```text
原Advanced_Strategy_Core的en
```

在C版本中不再直接由40205传入，而是由内部：

```text
strategy_eval_enable
```

驱动。

这既保留原策略算法的“enable”语义，又避免多增加一个没有必要让用户修改的参数。

---

# 2. 修正二：Runtime Config增加真正可靠的原子读取规则

## 2.1 为什么V0.1还差一步

V0.1已经规定：

```text
先修改所有参数
最后修改CONFIG_SEQ
```

这是正确方向。

但Board读取配置块时仍需要确认：

> 读取过程中CONFIG_SEQ没有再次变化。

---

## 2.2 V0.2最终协议

RT-LAB / Python侧更新：

```text
Step A
修改所有402xx具体参数

Step B
全部参数已经完成后

Step C
最后修改40124 CONFIG_SEQ
```

Board：

```text
1. 100 ms Fast FC03读取40101～40124
   得到 seq_before

2. 如果 seq_before == last_applied_config_seq
   → 不读取配置块

3. 如果 seq_before != last_applied_config_seq
   → FC03读取40201～40280

4. 检查：
   40201 CONFIG_SEQ_ECHO == seq_before

5. 再单独FC03读取一次40124
   得到 seq_after

6. 只有：
   seq_before
   ==
   CONFIG_SEQ_ECHO
   ==
   seq_after

   才认为这一整块配置属于同一版本

7. 参数合法性检查

8. 在下一个100 ms控制周期边界统一apply

9. 40025 CONFIG_APPLIED_SEQ更新为该版本
```

如果任何序号不一致：

```text
本轮不应用
继续使用上一份正式配置
下一周期重新读取
```

---

## 2.3 自动化更新的附加规则

以后RT-LAB Python自动化修改配置时：

```text
所有参数先修改
CONFIG_SEQ最后修改
```

并且不应该在上一份配置还没来得及被Board读取时立刻再覆盖下一份配置。

我们的试验本来就是秒级改变工况，因此不存在必须在100 ms内连续写多套配置的需求。

所以不需要：

```text
复杂双缓冲
CRC
奇偶序号协议
```

现在的：

```text
SEQ前后双检
```

已经足够，而且工程实现很简单。

---

# 3. 修正三：新增明确的 `COMM_STATUS`

V0.1已经有：

```text
DOMAIN_VALID_MASK
```

表示：

```text
P/Q/MODE/SYNC
```

四个控制域是否可用。

但它不能替代：

```text
通信输入侧
通信输出侧
Controller是否真的enabled
```

这些基础状态。

---

## 3.1 新地址

```text
40030 COMM_STATUS
```

类型：

```text
UINT16 bitfield
```

---

## 3.2 位定义

| Bit | 名称 | 中文含义 |
|---:|---|---|
| 0 | `TCP_CONNECTED` | TCP连接存在 |
| 1 | `LAST_FC03_OK` | 最近一次FC03读取成功 |
| 2 | `MEASUREMENT_FRESH` | 当前测量是新鲜快照 |
| 3 | `MEASUREMENT_VALID` | 当前测量通过合法性检查 |
| 4 | `LAST_FC16_OK` | 最近一次FC16写入成功 |
| 5 | `COMMAND_CHANNEL_VALID` | 当前命令发送通道可用 |
| 6 | `CONTROLLER_ENABLED` | 当前状态机处于允许控制状态 |
| 7 | `HAS_COMMITTED_COMMAND` | 已存在至少一帧正式成功提交命令 |
| 8 | `STATE_WAIT_VALID` | 当前处于WAIT_VALID |
| 9 | `STATE_DISCONNECTED` | 当前处于DISCONNECTED |
| 10 | `CONFIG_VALID` | 当前正式配置合法 |
| 11 | `CONFIG_UPDATE_PENDING` | 检测到新配置但尚未正式应用 |
| 12 | `CYCLE_OVERRUN` | 最近一周期超过100 ms目标周期 |
| 13～15 | Reserved | 预留 |

这样以后可以明确区分：

```text
FC03失败
和
FC16失败
```

并且不需要靠CSV猜测Board当时处于什么通信状态。

---

# 4. 修正四：重新规划未来算法，不再只保留8个Config和11个Diag

## 4.1 我们真正已经确定的算法路线只有两大类

不是无限制预留“未知算法”。

当前能够明确规划的是：

### A. `PROJECT15`

也就是现在的项目最终算法：

```text
15策略
+
Normalizer
+
Mode Manager
+
Arbiter
+
仲裁型基础AGC
+
Q分配
+
S6/S8
+
黑启动
+
S15重同步
```

这是最终项目交付主模式。

---

### B. `EXECUTION_AWARE_COORDINATION`

后续已经明确要继续完成的执行状态感知协调算法族：

```text
Strategy 2
PCC Tracking + Execution-State Assessment
执行状态评估

↓

Strategy 7
NORMAL / HOLD / RECONSTRUCTION / RECOVERY
协调恢复管理

↓

Improved AGC
依据真实有效调节能力重新分配
```

它需要显式使用：

```text
u_commit
Pexpected
Pmeas
execution residual
execution state
effective capability
resource qualification
recovery state
reallocation
```

这不是一个完全无关的新项目，而是当前2PV+2ESS+2EV平台后续确定的高级控制算法。

---

## 4.2 对比/消融不再设计成很多独立程序

后续试验需要比较：

```text
传统Baseline

只做Execution-State Assessment

增加Recovery Management

完整Execution-Aware + Effective-Capability Reallocation
```

这些不需要工程开发方维护四套程序。

统一设计：

```text
ALGORITHM_MODE
选择算法族

METHOD_VARIANT
选择同一算法族内部的对比/消融方式
```

推荐内部规划：

```text
ALGORITHM_MODE = 0
PROJECT15

ALGORITHM_MODE = 1
EXECUTION_AWARE_COORDINATION

其它
RESERVED
```

对于：

```text
EXECUTION_AWARE_COORDINATION
```

内部：

```text
METHOD_VARIANT = 0
传统Baseline

METHOD_VARIANT = 1
Execution Assessment Only

METHOD_VARIANT = 2
Assessment + Recovery Management

METHOD_VARIANT = 3
Full Method
Assessment + Recovery + Effective-Capability Reallocation
```

所以以后不会为了每个对比试验重新设计Modbus通信程序。

---

# 5. Runtime Config扩展到40201～40280

V0.1：

```text
40201～40264
64 registers
其中只有8个EXT_CONFIG
```

V0.2：

```text
40201～40280
80 registers
```

正常100 ms主循环不读取这80个寄存器。

只有：

```text
CONFIG_SEQ变化
```

才额外读一次。

因此增加16个配置寄存器：

```text
不会增加正常运行时每100 ms通信负担
```

---

# 6. 40257～40280正式规划给后续Execution-Aware算法

当前PROJECT15：

```text
这些寄存器全部可以保持默认值
```

以后不需要重新改点表。

| 地址 | 名称 | 用途 |
|---:|---|---|
| 40257 | `METHOD_VARIANT` | Baseline / Assessment / Recovery / Full方法选择 |
| 40258 | `EXEC_ERR_ENTER_PU` | 执行失配进入阈值 |
| 40259 | `EXEC_ERR_CLEAR_PU` | 执行失配清除阈值，形成滞环 |
| 40260 | `EXEC_CONFIRM_MS` | 执行异常持续确认时间 |
| 40261 | `RECOVERY_STABLE_MS` | 恢复连续稳定确认时间 |
| 40262 | `RESPONSE_TIMEOUT_MS` | 设备响应超时判断 |
| 40263 | `PV1_EXPECT_DELAY_MS` | PV1预期响应延迟 |
| 40264 | `PV2_EXPECT_DELAY_MS` | PV2预期响应延迟 |
| 40265 | `ESS1_EXPECT_DELAY_MS` | ESS1预期响应延迟 |
| 40266 | `ESS2_EXPECT_DELAY_MS` | ESS2预期响应延迟 |
| 40267 | `EV1_EXPECT_DELAY_MS` | EV1预期响应延迟 |
| 40268 | `EV2_EXPECT_DELAY_MS` | EV2预期响应延迟 |
| 40269 | `PV1_EXPECT_TAU_MS` | PV1预期响应时间常数/等效动态参数 |
| 40270 | `PV2_EXPECT_TAU_MS` | PV2预期响应时间常数/等效动态参数 |
| 40271 | `ESS1_EXPECT_TAU_MS` | ESS1预期响应动态参数 |
| 40272 | `ESS2_EXPECT_TAU_MS` | ESS2预期响应动态参数 |
| 40273 | `EV1_EXPECT_TAU_MS` | EV1预期响应动态参数 |
| 40274 | `EV2_EXPECT_TAU_MS` | EV2预期响应动态参数 |
| 40275 | `CAPABILITY_MIN_PU` | 最小有效能力下限 |
| 40276 | `CAPABILITY_RESERVE_PU` | 有效能力安全余量 |
| 40277 | `TRUST_ALPHA` | 执行可信度/能力估计平滑系数 |
| 40278 | `RECON_BLEND_GAIN` | 状态重构/对齐融合增益 |
| 40279 | `SOC_WEIGHT_GAIN` | SOC辅助权重增益 |
| 40280 | `FUTURE_CONFIG_01` | 最后保留1个通用配置槽 |

为什么把六台设备动态参数分开，而不是只留PV/ESS/EV三类：

> 后续真实辨识结果可能证明同类型两台设备也存在不同响应，因此提前用六设备独立参数更稳妥，且只在配置变更时读取，不增加正常通信负担。

---

# 7. Command Frame扩展到40001～40064

V0.1：

```text
40001～40040
```

其中：

```text
40030～40040
只有11个泛化EXT_DIAG
```

这对于当前PROJECT15够，但对于后续Execution-Aware算法同步记录不够。

V0.2：

```text
40001～40064
```

每100 ms仍然只：

```text
一次FC16
```

只是一个更完整的连续控制/关键诊断帧。

---

# 8. 40001～40029保持V0.1控制语义

保持：

```text
6 Pref
6 Qref
GridOn mask
Droop mask
Breaker
Fref trim
System Mode
Selected Master
Config status
Strategy active
Domain validity
```

不变。

40030新增：

```text
COMM_STATUS
```

---

# 9. 40031～40064提前规划后续关键诊断

这些量的目的不是普通调试，而是：

> **把以后需要与RT-LAB真实Plant波形严格同步比较的关键算法内部状态直接写入RT-LAB。**

大量普通日志仍然留Board CSV。

---

## 9.1 六路设备预期功率 `Pexpected`

```text
40031 PV1_P_EXPECTED_KW
40032 PV2_P_EXPECTED_KW
40033 ESS1_P_EXPECTED_KW
40034 ESS2_P_EXPECTED_KW
40035 EV1_P_EXPECTED_KW
40036 EV2_P_EXPECTED_KW
```

作用：

```text
u_commit
↓
设备预期动态模型
↓
Pexpected
```

然后与六路：

```text
Pmeas
```

比较。

---

## 9.2 六路执行残差

```text
40037 PV1_EXEC_RESIDUAL_KW
40038 PV2_EXEC_RESIDUAL_KW
40039 ESS1_EXEC_RESIDUAL_KW
40040 ESS2_EXEC_RESIDUAL_KW
40041 EV1_EXEC_RESIDUAL_KW
40042 EV2_EXEC_RESIDUAL_KW
```

典型语义：

```text
residual = Pmeas - Pexpected
```

最终符号在算法冻结时统一。

---

## 9.3 执行状态与资源资格

```text
40043 EXEC_STATE_PACKED
```

每台设备使用2 bit：

```text
00 NORMAL
01 SUSPECT
10 DEGRADED/UNAVAILABLE
11 RECOVERING
```

六设备只占12 bit。

```text
40044 RESOURCE_QUALIFIED_MASK
```

bit0～5分别表示六设备当前是否仍允许参与有功重分配。

---

## 9.4 六路真实有效调节能力

```text
40045 PV1_EFFECTIVE_CAP_KW
40046 PV2_EFFECTIVE_CAP_KW
40047 ESS1_EFFECTIVE_CAP_KW
40048 ESS2_EFFECTIVE_CAP_KW
40049 EV1_EFFECTIVE_CAP_KW
40050 EV2_EFFECTIVE_CAP_KW
```

这是后续改进AGC真正用来分配任务的能力，而不仅是铭牌上限。

---

## 9.5 六路执行可信度/能力权重

```text
40051 PV1_TRUST_PU
40052 PV2_TRUST_PU
40053 ESS1_TRUST_PU
40054 ESS2_TRUST_PU
40055 EV1_TRUST_PU
40056 EV2_TRUST_PU
```

如果最终算法不采用连续trust，也可将其解释为：

```text
execution confidence / capability weight
```

不改变地址结构。

---

## 9.6 协调恢复和重分配关键状态

```text
40057 COORD_RECOVERY_STATE
```

内部状态：

```text
NORMAL
HOLD
RECONSTRUCTION
RECOVERY
```

具体enum以后由算法正式冻结。

```text
40058 REALLOC_ACTIVE_MASK
```

表示哪些设备当前正在承担故障后的剩余任务重分配。

```text
40059 REALLOC_REMAIN_KW
```

表示当前仍未被可用资源消化的剩余调节量。

---

## 9.7 通信/状态失配实验关键证据

```text
40060 PCC_RX_KW
```

表示：

> **Board本周期真正用于控制计算的PCC有功值。**

RT-LAB本身已经有：

```text
PCC真实值
```

于是最终能够同时保存：

```text
Ppcc_real
Ppcc_rx
```

这对通信异常条件下确认“Plant真实状态”和“Board认知状态”是否失步非常重要。

---

## 9.8 方法版本与状态重构事件

```text
40061 CONTROL_VARIANT_STATUS
```

记录：

```text
当前究竟运行Baseline
还是Assessment
还是Recovery
还是Full
```

方便同一套CHIL平台做自动对比。

```text
40062 RECON_EVENT_SEQ
```

每发生一次正式状态重构/对齐事件递增，便于RT-LAB MAT精确定位恢复事件。

---

## 9.9 最后保留两个真正通用槽

```text
40063 FUTURE_DIAG_01
40064 FUTURE_DIAG_02
```

只保留2个未定义槽。

因为我们已经把目前可预见的后续算法关键证据具体规划出来，不需要再盲目留几十个“EXT”。

---

# 10. 为什么64个FC16寄存器仍然是合理方案

从工程结构上：

```text
以前：
40001～40012

BOARD15 V0.2：
40001～40064
```

看起来增加很多，但本质仍然：

```text
每100 ms
一次连续FC16
```

工程开发方只需要扩充：

```text
write buffer
encode table
CSV/diag mapping
```

不增加：

```text
第二个命令socket
第二套协议
多次FC16事务
```

这些扩展诊断值即使PROJECT15当前不用：

```text
置0即可
```

真正的板端可实现性仍要在完整BOARD15程序完成后做一次100 ms回归验证。

因此：

> 这是“为确定的后续算法一次性预留足够证据接口”，而不是为了架构复杂化。

---

# 11. V0.2三个最终地址块

```text
A. Command Frame
40001～40064
Board → RT-LAB
每100 ms一次FC16

B. Fast Measurement
40101～40124
RT-LAB → Board
每100 ms一次FC03

C. Runtime Config
40201～40280
RT-LAB → Board
仅CONFIG_SEQ变化时读取
+
读后再次核对CONFIG_SEQ
```

---

# 12. 当前PROJECT15真正使用哪些未来扩展点

PROJECT15正式运行时：

```text
40257～40280
除METHOD_VARIANT默认值外
可以全部保持默认

40031～40064
Execution-Aware相关诊断
可以全部置0
```

因此：

> 当前项目交付逻辑不会因为未来算法预留而变复杂。

主程序只是在数组中多保留了一些位置。

---

# 13. 对工程开发方的实现影响

工程开发方仍然只需要：

```text
100 ms主循环

FC03 40101～40124

若CONFIG_SEQ变化：
    读取40201～40280
    再核对一次40124

调用统一Controller Adapter

FC16 40001～40064

candidate / commit

CSV
```

没有新增多线程、ACK网络、实时DSP等复杂要求。

---

# 14. 对RT-LAB模型改造的影响

模型侧需要：

```text
1. Fast Measurement pack扩到40124

2. Runtime Config pack扩到40280

3. Board Command / Diagnostic decode扩到40064

4. 增加COMM_STATUS记录

5. PROJECT15阶段40031～40064未来算法量可先接常数0/Board回传

6. 后续Execution-Aware算法接入时
   只需要把这些预留诊断量真正使用起来
   不再改变Modbus整体结构
```

---

# 15. 四项问题修正后的最终结论

## 问题1：`CFG_AA_enable` vs `MASTER_ENABLE`

```text
不合并语义
但不新增外部寄存器

策略判断enable：
Board内部根据fresh/valid测量派生

40205 CONTROL_MASTER_ENABLE：
只负责“是否允许真实控制Plant”
```

---

## 问题2：Runtime Config原子性

```text
参数先写
CONFIG_SEQ最后写

Board：
seq_before
→ read config
→ config echo
→ 再读seq_after

三者一致才应用
```

---

## 问题3：通信状态缺口

新增：

```text
40030 COMM_STATUS
```

明确保存：

```text
TCP
FC03
measurement fresh/valid
FC16
command channel
controller enabled
```

---

## 问题4：未来算法扩展不足

现在不再泛泛预留8/11个槽。

而是明确规划：

```text
PROJECT15
+
Execution-Aware Coordination算法族
+
内部Baseline/Assessment/Recovery/Full对比
```

并将地址扩展到：

```text
40201～40280
40001～40064
```

足以覆盖目前已经明确的后续路线。

---

# 16. 下一步

V0.2完成以后，再进入：

# BOARD15 内部设计05
# Project15 persistent状态逐变量更新 / commit规则审计

下一步不再改外围点表，而是逐个核定：

```text
demand_avg
peak_power
pv_prev
energy accumulators
black_state
switch/recovery state
AGC Ppv/Pess/Pev
S6 smooth_ref
S15 sync_timer
...
```

在：

```text
正常
FC03失败
FC16失败
WAIT_VALID
重连
Reset
```

时到底如何更新。

这一步完成后即可冻结`Project15State`并开始正式C代码转换。
