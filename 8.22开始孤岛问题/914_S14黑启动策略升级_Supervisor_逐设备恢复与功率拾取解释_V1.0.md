# 2026-09-14｜S14黑启动策略为什么必须升级、Supervisor与逐设备恢复状态机如何实现

> 基于：R7完整ESS2并回G27/G30分析 + 已有S14源码/计划孤岛结构 + 文献碰撞评价  
> 核心结论：**不是推翻已经通过的前半段，而是把原S14从“定时阶段 + Pref门控”升级成真正的闭环物理恢复策略。**

---

## 1. 原S14到底简单在哪里

原S14当前的核心逻辑实际上是：

```text
Stage1：
所有六台Pref = 0

Stage2：
恢复非master ESS的Pref

Stage3：
恢复PV的Pref

Stage4：
恢复EV的Pref
```

原设计自身也明确说明：

```text
“device restoration”主要是Pref分阶段释放
+ 已有GridOn/Droop模式控制
并不是物理断路器级逐设备恢复
```

而Stage2/3/4又基本按固定时间推进：

```text
约20 s
约40 s
约60 s
```

因此它适合作为：

```text
黑启动顺序框架
```

但不足以直接承担：

```text
真实断路器逐台合闸
同步资格判断
合闸后零功率稳定
功率安全拾取
失败回退
恢复完成确认
```

---

## 2. 这次是否要修改“策略本身”

### 逻辑上：需要

需要把S14从：

```text
时间到了
→ 放Pref
→ 下一阶段
```

升级为：

```text
当前阶段的物理目标完成
→ 收到健康确认
→ 才允许下一阶段
```

这属于真正的策略完善。

### 实现上：不必强行重写原Advanced_Strategy_Core

过去为了不破坏15策略公共核心，我们一直尽量保持：

```text
Original Strategy 14 algorithm = UNCHANGED
```

这个做法在前期是合理的。

现在更适合：

```text
S14原核心：
负责“进入黑启动模式/请求”

↓
S14黑启动执行监督器：
负责真实物理恢复过程
```

这样逻辑上仍然是Strategy 14，不是新策略，也不是无关的新顶层控制器。

---

## 3. 为什么原计划孤岛问题不能全部归咎于原S14

不能说：

```text
过去所有孤岛不稳定 = S14太简单
```

因为历史问题包括：

- ESS1 GFM交接；
- Current PI遗留状态；
- 参考切换；
- GFL dynamic terminal-Vdq feedforward；
- 五GFL弱网交互；
- 后续慢电压/无功层。

其中很多与S14无关。

但可以说：

> 早期整个系统的恢复框架普遍假设“模式/Stage切换 + 参考变化就足够”，缺少“每台设备真实物理可用状态、恢复ACK、健康门控、失败回退”。

这个架构简化同时影响了计划孤岛和黑启动。

---

## 4. 当前R7已经证明到哪里

### 已成功

```text
ESS1死母线建压
→ ESS2 GFL Stage1/2
→ breaker两侧同步
→ ESS2真实合闸
→ Current PI真实反馈
→ state4
→ state5
→ 长时间零功率稳定
```

### 失败发生在

```text
MANUAL_RELEASE
→ RestoreAlpha开始增加
→ ESS2真正开始承担功率
→ 母线电压持续下坠
```

所以当前最准确的表述是：

> **ESS2“接回孤岛”已经成功；ESS2“接回以后开始承担功率”失败。**

---

## 5. 全局Black-Start Supervisor是什么

不是突然增加一个无关控制器。

它就是：

> **S14策略的“执行状态机”。**

它负责回答：

```text
现在系统在黑启动哪一步？
哪台设备允许恢复？
这一台是否已经真正恢复完成？
下一台能不能开始？
```

推荐逻辑上：

```text
S14 request
↓
Black-Start Supervisor
↓
选择设备 / 发恢复许可
↓
等待本设备RESTORED_ACK
↓
再选下一设备
```

它可以物理实现为SM_Master中的一个普通Simulink/MATLAB Function子系统。

---

## 6. 每台GFL自己的局部恢复状态机怎么实现

最简单的实现不是重新设计五套控制器，而是：

> **把现在ESS2已经跑通的Restore Executor推广成通用模板。**

每台GFL都拥有自己的恢复状态。

### L0 ISOLATED（物理隔离）

```text
breaker open
功率释放=0
```

### L1 PREPARE（孤岛准备）

复用已有GFL孤岛支撑：

```text
退出强网dynamic VFF
进入弱孤岛适配状态
```

### L2 SYNC_READY（同期就绪）

检查真实断路器两侧：

```text
ΔV
Δf
Δθ
```

### L3 ZERO_CLOSE（零功率合闸）

```text
breaker close
Iref=0
Imeas=真实电流
Current PI主动把并入电流压小
```

### L4 CONNECTED_ZERO（零功率稳定）

要求持续：

```text
V/f健康
电流小
CurrentLimit=0
ModHeadroom正常
```

### L5 PICKUP_READY（允许开始承担功率）

确定本次恢复要先承担多少功率。

### L6 POWER_PICKUP（逐步承担功率）

不是当前固定2秒alpha斜坡，而是：

```text
系统健康：
→ 增加一点功率

略恶化：
→ 暂停增加

持续低压/接近限流：
→ 减少功率

严重异常：
→ 回到零功率
→ 必要时断开
```

### L7 RESTORED_VERIFY（恢复确认）

必须真正满足：

```text
功率目标达到
V/f健康
P/Q跟踪合理
CurrentLimit=0
ModHeadroom正常
持续健康一段时间
```

才输出：

```text
RESTORED_ACK = 1
```

---

## 7. “黑启动功率目标”到底是什么意思

不是新发明一个莫名其妙的控制器。

它只是：

> **设备刚刚接回来的最初几秒，不要立刻让它追正常孤岛调度给出的完整Pref。**

当前R7的问题是：

```text
正常孤岛Coordinator的Pref在变化
+
RestoreAlpha在变化
+
Power PI也在追
```

三件事同时动。

正确方式应该是：

```text
ESS2刚接好
↓
先给一个很小、暂时固定的功率目标
↓
保持一段时间
↓
系统健康
→ 再增加一点

系统恶化
→ 不增加 / 降低
```

例如：

```text
0
→ 小功率
→ 中等功率
→ 目标功率
```

每一级都重新确认母线是否健康。

这个“暂时固定的小目标”就是所谓：

```text
P_pickup_target
```

中文就是：

> **黑启动恢复阶段的临时功率目标。**

设备真正稳定以后，再把控制权交回原有正常孤岛Coordinator。

---

## 8. 为什么不能直接用正常孤岛长期调度

正常孤岛Coordinator假设的是：

```text
五台GFL都已经在线、可用
```

它会同时计算五台：

```text
PV1
PV2
ESS2
EV1
EV2
```

的调节余量。

但黑启动过程中可能实际只有：

```text
ESS2 connected
其它四台 disconnected
```

所以最终必须告诉Coordinator：

```text
谁已经真正RESTORED
谁还不能参与调度
```

只有RESTORED设备才进入正常功率分配。

---

## 9. 全局Stage为什么最终不够

计划孤岛时五台GFL都在线：

```text
一个global stage
```

合理。

黑启动时：

```text
ESS2已经恢复
PV1还没接
PV2还没接
EV还没接
```

如果为了ESS2进入Stage3而把全局Stage设为3：

```text
后面PV刚接入时
它直接看到Stage3
```

就跳过了：

```text
PREPARE
STABILIZE
```

因此最终需要：

```text
Global black-start stage
+
每台设备自己的local restore stage
```

---

## 10. 原S14应该怎么升级

### 保留

```text
ESS优先
→ PV
→ EV
```

这种大的恢复顺序可以继续作为默认策略。

### 修改

原：

```text
20s
→ ESS

40s
→ PV

60s
→ EV
```

升级成：

```text
ESS1母线形成成功
↓
恢复ESS2
↓
ESS2 RESTORED_ACK
↓
系统健康驻留
↓
再恢复PV
↓
PV RESTORED_ACK
↓
再恢复下一资源
```

时间只作为：

```text
minimum dwell / timeout
```

不能再作为“恢复成功”本身。

---

## 11. 当前最应该冻结与重构的部分

### 冻结

- ESS1 dead-bus formation；
- ESS2 breaker物理路径；
- breaker-inner同步测量；
- Current Adapter真实Imeas；
- state4零电流闭环；
- state5零功率稳定；
- Stage1/2 dynamic VFF抑制。

### 重构

- S14固定20/40/60 s推进；
- state6开环2 s RestoreAlpha斜坡；
- state7仅用alpha=1定义RESTORED；
- 黑启动首次功率目标；
- 低压时ESS充电功率退让；
- 每台资源availability / RESTORED_ACK；
- 全局Stage与逐设备local stage的关系。

---

## 12. 一句话理解当前项目状态

> **我们已经解决了“怎样把ESS2安全接回孤岛”，现在真正要解决的是“接回以后怎样在不拖垮ESS1构成的弱孤岛的情况下，让ESS2逐步承担功率”。**

这就是下一阶段黑启动策略完善的核心。
