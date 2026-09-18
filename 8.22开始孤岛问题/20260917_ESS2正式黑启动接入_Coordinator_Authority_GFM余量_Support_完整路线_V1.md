---
title: "2026-09-17｜ESS2正式黑启动接入：Coordinator、Ownership、Authority、GFM余量、Support与完整恢复路线"
date: 2026-09-17
project: "yanshou_V7 / K26_K50_CLEAN_P1 / S14 V2"
status: "设计澄清与文献碰撞版 V1.0"
basis:
  - "当前模型/仓库结构"
  - "A0/P0/C1/Ki=0/Ki=0.5真实RT-LAB证据"
  - "孤岛与黑启动22篇论文精读"
  - "黑启动第二轮增量深度研究"
  - "2026-09-17定向公开文献核查"
---

# 0. 结论先行

当前最重要的结论不是“继续加模块”，而是把**恢复层、正常协调层、设备本地控制层**彻底分清。

对 ESS2 的最终正确路线，建议冻结成：

```text
ESS1 GFM建立孤岛
↓
ESS2 GFL准备
↓
ESS2真实同步与零功率物理合闸
↓
CONNECTED_ZERO（已连接零功率）
↓
P/Q本地闭环资格验证
↓
小功率qualification（资格平台）
↓
必要时分阶段提高到安全的restoration target（恢复目标）
↓
DeviceRestoredACK（设备恢复完成确认）
↓
S14 → 正常Coordinator无扰交接
↓
Primary（一次功率-频率协调）
↓
Secondary（二次频率/电压慢恢复）
↓
在ESS1实时能力允许下扩大正常协调权限
↓
再恢复下一台PV/EV
↓
最终完整正常孤岛调度
```

当前模型已经做到的不是整条链，而是一个**ESS2-only原型**：

```text
S14-10 → 20 → 25 → 30 → 40 → 50 → 60 → 90
```

其中：

- `S14-40` 已有固定小功率 pickup（功率拾取）；
- `S14-50` 已有 ownership handover（功率命令所有权平滑交接）；
- `S14-60` 已有 Primary-only（仅一次功率-频率协调）；
- `S14-70 Secondary` 尚未实现；
- 当前 `ESS2CoordAuthority=0.01 pu / hard cap 0.02 pu` 只适合作为**调试/验收阶段的小权限**，不能代表“正常功率已经恢复完整”；
- 当前没有真正的动态 ESS1 GFM reserve（构网型实时余量）监督；
- BASETEST 中隔离的四路 support（支撑）并不是“黑启动标准规定必须有的四个模块”，必须先审计其最终角色，再决定是否恢复。

---

# 1. 术语先统一：以后所有英文名都必须带中文物理意义

## 1.1 Coordinator（正常孤岛协调器）

**Coordinator（正常孤岛协调器）**不是 ESS2 本地控制器，也不是 S14 黑启动状态机。

它是：

> 在微电网已经进入孤岛运行后，负责根据系统频率、电压、资源可用性和资源调节能力，对各 GFL 设备生成正常长期功率协调目标的中央控制模块。

当前模型准确路径：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_ISLAND_SUPERVISORY_COORDINATION
/AA15_FINAL_ISLAND_COORDINATOR
/AA15_FINAL_COORD_CORE
```

物理层级：

```text
S14
= 恢复监督层
负责“设备怎么安全恢复回来”

Coordinator
= 正常孤岛协调层
负责“设备恢复以后，怎么长期共同承担功率”
```

Coordinator内部已有：

```text
Primary P-f correction
（一次有功-频率修正）

Secondary frequency restoration
（二次频率恢复积分）

slow voltage restoration
（慢速电压恢复）

resource availability / up-down capability
（资源可用性 / 上下调能力）

dispatch allocation
（调节量分配）
```

所以：

> S14 不应该永久替代 Coordinator；Coordinator 也不应该在 ESS2 尚未安全恢复时抢先给 ESS2 正常大功率命令。

---

## 1.2 Ownership（命令所有权）

**ownership（命令所有权）**回答的是：

> “现在 ESS2 的最终有功参考值，究竟听谁的？”

当前有两个潜在命令源：

```text
P_S14
= S14恢复阶段给ESS2的功率目标

P_Coord
= 正常Coordinator给ESS2的功率目标
```

---

## 1.3 Ownership Blend（功率命令所有权平滑混合）

当前模型准确路径：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND
```

这是普通 Simulink 子系统，不是状态机。

它的核心数学：

```text
P_final
=
(1-beta) * P_S14
+
beta * P_Coord
```

含义：

```text
beta = 0
→ 完全由S14控制

0 < beta < 1
→ S14与Coordinator平滑混合

beta = 1
→ 完全由Coordinator控制
```

---

## 1.4 Pfinal（最终施加给ESS2的有功参考）

**Pfinal（最终有功命令）**就是：

> 在所有权选择/混合以后，真正送往 ESS2 IO 路径、最终进入 ESS2 本地有功功率控制环的那个有功参考值。

旧路径：

```text
Coordinator PrefESS2
→ ESS2 IO
```

S14 V2后：

```text
P_S14 --------\
               → Ownership Blend → Pfinal → ESS2 IO
P_Coord -------/
```

所以：

> `Pfinal` 才是 ESS2 真正执行的最终上层有功目标。

---

## 1.5 “Coordinator owns ESS2”

**Coordinator owns ESS2（Coordinator拥有ESS2有功命令控制权）**不是说：

```text
Coordinator拥有ESS2所有控制器
```

也不是：

```text
Coordinator可以让ESS2随便输出任意功率
```

它只表示：

```text
beta = 1
→ Pfinal = P_Coord
```

即：

> ESS2 最终有功参考值的命令来源已经从 S14 切换到了正常孤岛 Coordinator。

ESS2 本地：

```text
P/Q Power Loop
Current Regulator
PLL
Current Adapter
保护/限幅
```

仍然全部是 ESS2 自己的本地控制。

---

## 1.6 Primary Correction（一次功率-频率修正）

**Primary correction（一次功率-频率修正）**是：

> Coordinator拿到ESS2以后，根据孤岛频率偏差快速改变ESS2有功功率，帮助唯一GFM ESS1承担瞬时功率不平衡。

当前概念关系：

```text
frequency error
= 50 Hz - master_f

↓ filter（滤波）
↓ deadband（死区）

dp_primary
=
CorrectionGain
× Kpf
× frequency_error_filtered
```

它类似：

```text
一次调频 / P-f快速响应
```

特点：

```text
快
按当前频差动作
不是长期积分器
```

---

## 1.7 “Coordinator owns ESS2 with primary correction only”

完整中文应该写成：

> **Coordinator 已经取得 ESS2 有功命令控制权，但当前只允许启用一次有功-频率快速修正，二次频率/电压慢恢复仍关闭。**

它对应当前 `S14-60`：

```text
beta = 1
ESS2Available = 1

CorrectionEnable = 1
CorrectionGain: 0 → 1

Primary P-f = ON

Secondary = OFF
```

这不是“完整正常调度已恢复”。

它只是：

> ESS2已经从“恢复中的设备”变成“正常孤岛协调器可以有限调用的设备”。

---

## 1.8 Secondary（第二层慢速恢复 / 二次协调）

**Secondary（第二层慢速恢复，也可类比二次频率/电压恢复）**负责：

> Primary 快速把频率偏差压小以后，再通过慢积分逐步把长期剩余频差、电压偏差恢复到目标附近。

概念：

```text
Primary：
频率一偏，马上按比例帮忙

Secondary：
长期还有偏差，慢慢积分消掉
```

当前模型 Coordinator 内部已有 Secondary 算法，但：

```text
当前S14 R1
没有正式 S14-70
```

所以目前还没有自动把它放进黑启动恢复状态链。

---

## 1.9 Authority（协调权限 / 允许调节幅度）

**authority（协调权限）**回答的是：

> Coordinator拿到控制权以后，允许它把ESS2从当前稳定基线推多远？

它和 beta 完全不同：

```text
beta
= 谁控制

authority
= 新控制者最多允许改多少
```

---

# 2. Coordinator到底在模型哪里，实际做什么

当前 Coordinator 准确模块：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_ISLAND_SUPERVISORY_COORDINATION
/AA15_FINAL_ISLAND_COORDINATOR
/AA15_FINAL_COORD_CORE
```

可把它理解为：

```text
              ┌─────────────────────────┐
              │ Normal Island Coordinator│
              │ 正常孤岛协调器           │
              └─────────────────────────┘
                       ▲
                       │
     ┌─────────────────┼─────────────────┐
     │                 │                 │
 ESS1/母线频率     各资源Pmeas       各资源能力/状态
 master_f         PV/ESS/EV          available/headroom
     │                 │                 │
     └─────────────────┼─────────────────┘
                       ↓
            Primary / Secondary
                       ↓
              资源调节量分配
                       ↓
             P_Coord_ESS2 等
```

S14黑启动期间，又额外给它加了：

```text
S14Active
ESS2Available
CorrectionGain
SecondaryEnable
ESS2CoordAuthority
```

目的是让同一个正常 Coordinator：

> 能够知道“现在只有哪些设备真正恢复了”，而不是把断开的 PV/EV 仍然当作在线资源分功率。

这点非常重要。

---

# 3. 当前 Coordinator 的三层责任

## 3.1 Baseline（基线）

ESS2还没有 `Available` 时：

```text
Pbase_ESS2
```

跟踪当前：

```text
Pmeas_ESS2
```

目的：

> 避免 Coordinator 内部还记着黑启动前/强网时期的旧功率目标。

所以如果 S14 让 ESS2 稳定在：

```text
-0.005 pu
```

Coordinator的内部基线也应接近：

```text
-0.005 pu
```

---

## 3.2 Primary（一次修正）

在正常孤岛中：

```text
频率低
→ 说明发电不足/负荷偏大

频率高
→ 说明发电过多/负荷偏小
```

Coordinator按频率偏差产生：

```text
dp_primary
```

然后按设备可调能力分配。

---

## 3.3 Secondary（慢速二次恢复）

Primary之后如果：

```text
f ≠ 50 Hz
```

Secondary才进一步积分，恢复：

```text
frequency
voltage
long-term sharing
```

---

# 4. “动态ESS1 GFM余量监督”到底是不是必须的

## 4.1 结论

必须把两句话分开：

### 不是必须有一个名字叫：

```text
Dynamic ESS1 GFM Reserve Supervisor
（动态ESS1构网余量监督器）
```

的固定标准模块。

文献没有规定所有黑启动系统都必须拥有一个同名模块。

### 但是物理上必须保证：

> **新增/恢复的GFL功率和调节责任，不能超过当前黑启动GFM能够实际承受的瞬时功率、电流、调制度和稳定能力。**

这个物理约束是无法绕过的。

所以：

```text
“动态余量模块”
不是行业统一必备模块名

但
“恢复动作必须受GFM当前能力约束”
是必不可少的物理要求
```

---

# 5. 为什么ESS1余量不能只看额定功率

ESS1即使铭牌：

```text
100 kW / 某kVA
```

也不代表此刻就能再承担全部剩余负荷。

实时有效构网能力受：

```text
当前P
当前Q
当前电流
CurrentLimit
ModIndex / ModHeadroom
Vdc
电压环/电流环执行能力
网络阻抗
变压器励磁
母线电压
GFL聚合动态
PLL交互
```

共同决定。

一个最简单的例子：

```text
ESS1额定100 kW

但此刻：
已经承担80 kW
+
Q很大
+
电流接近上限
+
ModHeadroom很低
```

这时再恢复一个大功率GFL，虽然：

```text
100 kW额定容量
```

表面看还够，但动态上很可能已经没有足够电流/电压形成裕量。

---

# 6. 文献是不是也这样做

不是所有研究都叫“GFM reserve”，但大量研究都在做同一件物理事情。

## 6.1 Arai 2022

单GFM + 多GFL。

负荷变化后：

```text
GFM先承担
↓
频率变化
↓
GFL随后增加/减少功率
↓
EMS再调整GFL长期Pref
↓
让GFM不长期顶在不健康工作点
```

这就是：

> **让GFM短时托底，但长期把功率责任重新分出去。**

它不是显式“headroom supervisor”，但目的与我们要做的GFM余量管理高度一致。

---

## 6.2 Zhang 2021 IEEE TSG

顺序恢复不是：

```text
想恢复多少就恢复多少
```

而是：

```text
恢复动作
↓
暂态频率动态验证
↓
可行才进入下一恢复步骤
```

这相当于把：

```text
系统动态可承受能力
```

作为恢复约束。

---

## 6.3 CIGRE 2026

这篇是目前与我们：

```text
GFM BESS黑启动源
+
多个non-black-start GFL
+
逐步系统恢复
```

最接近的新来源之一。

它明确讨论：

```text
GFM black-starter import/export limits
GFL恢复比例
PLL
PPC
current limiting
network impedance
```

并指出 DER 变化只要保持在 black-starter 的输入/输出功率能力范围内，可以保持稳定。

它还得到某些：

```text
1:10
80%
```

等特定模型结果。

**这些数字绝不能抄到我们模型。**

我们真正要借鉴的是：

> **“恢复多少GFL”和“GFM此刻还有多少能力”必须绑定。**

---

# 7. 因此动态ESS1余量什么时候真正必须实现

当前阶段：

```text
只有ESS2
小功率
authority=.01/.02
```

还可以先用硬限幅代替复杂动态余量。

但进入：

```text
ESS2更大正常功率
PV1/PV2恢复
EV1/EV2恢复
多个GFL同时参与Primary/Secondary
```

以后：

> 动态ESS1余量监督必须成为正式设计的一部分，或者至少存在功能等价的实时能力约束。

---

# 8. 当前0.01 / 0.02 pu保守权限究竟够不够

## 8.1 数值先换成物理量

ESS2：

```text
Pnom = 100 kW
```

所以：

```text
0.01 pu = 1 kW
0.02 pu = 2 kW
```

当前小功率基线：

```text
Pbase ≈ -0.005 pu
      ≈ -0.5 kW
```

默认：

```text
authority = ±0.01 pu
```

只允许 Coordinator 在当前基线附近移动约：

```text
±1 kW
```

Core硬上限：

```text
±2 kW
```

---

# 9. 它够做什么

足够做：

```text
S14-50 handover
（控制权平滑交接）

+

S14-60 Primary commissioning
（小幅一次协调验收）
```

也就是回答：

1. Coordinator拿到命令源以后会不会跳变；
2. 小幅频率修正能不能稳定工作；
3. ESS1与ESS2之间的两机协调能不能建立。

---

# 10. 它不够做什么

它不够证明：

```text
ESS2已经恢复到正常功率范围
```

也不够证明：

```text
ESS2可以承担完整AGC/EMS调度
```

如果 ESS2 最终正常可能承担：

```text
几十kW
```

那么：

```text
1~2 kW authority
```

显然只是调试边界。

所以当前准确表述：

> **0.01/0.02 pu足够做“小权限正常协调接管”的第一轮工程验收，但不足以代表正常功率承担能力已经恢复。**

---

# 11. 这里暴露出当前S14 R1一个重要“原型 vs 最终方案”差异

当前R1：

```text
S14-40：
先到 -0.005

↓
Restore-state7

↓
S14-50：
立刻handover

↓
S14-60：
Primary with tiny authority
```

这是一个非常适合因果验证的原型。

但是最终工程恢复还缺：

> **ESS2如何从“-0.005资格平台”继续安全走到一个真正有意义的正常功率工作区。**

当前 R1 没有完整解决这件事。

---

# 12. 文献更支持的最终结构

第二轮文献研究得到的更完整组织是：

```text
zero-power connected
↓
restoration supervisor拥有P/Q命令
↓
小目标
↓
hold
↓
更高目标
↓
hold
↓
...
↓
达到安全restoration target
↓
稳定确认
↓
DeviceRestoredACK
↓
再无扰handover给正常EMS/Coordinator
```

这意味着：

> `-0.005 pu` 更适合定义成“资格工作点/第一阶段工作点”，而不是“已经完整恢复完成”。

---

# 13. 最终方案应如何处理“正常功率”

建议区分三个概念：

```text
P_qualification
= 首个资格小功率
例如当前 -0.005

P_restoration_target
= 黑启动恢复阶段允许ESS2达到的安全恢复目标

P_normal_schedule
= 全系统正常孤岛调度最终希望ESS2承担的目标
```

其中：

```text
P_restoration_target
=
clip(
    P_normal_schedule,
    ESS2自身能力,
    ESS1 GFM余量,
    current margin,
    modulation margin,
    stability boundary
)
```

即：

> 正常计划值是“想要多少”，恢复目标是“当前安全允许做到多少”。

---

# 14. 这意味着未来S14-40可能需要升级

当前：

```text
S14-40
= 0 → -0.005
```

最终可以设计成：

```text
S14-40 POWER_PICKUP
│
├─ Phase A：qualification
│   0 → -0.005
│   hold
│
├─ Phase B：staged pickup
│   -0.005 → P2
│   hold
│   → P3
│   hold
│   → safe restoration target
│
└─ Stable ACK
    → S14-50
```

是否拆成新的S14Substate编号：

```text
暂不决定
```

应该等：

```text
PQ
support分类
cleanup audit
文献最终碰撞
```

完成后再冻结。

不要现在为了形式提前加一个新state编号。

---

# 15. 别人的研究怎么“恢复正常功率”

没有一个统一模板。

但跨论文共同逻辑非常一致：

```text
GFM先托底
↓
非黑启动资源接入
↓
功率不是一步恢复
↓
逐步加入/调节GFL功率
↓
监视系统V/f/电流/能力
↓
慢速EMS/Secondary再重新分配长期责任
```

不同论文只是实现方式不同：

- Arai：GFM先承担，GFL频压调节，EMS慢改GFL Pref；
- Seo：GFL先 zero-power standby 合闸，之后才给非零 P*；
- Yin/Hu：恢复阶段与正常 Energy Management / Power Management 分层，状态机决定哪些功能使能；
- Zhang：按资源恢复状态和频率动态约束逐步恢复；
- CIGRE 2026：恢复规模受GFM能力、GFL控制设置、PPC/PLL/网络等稳定边界约束。

因此：

> 我们不需要寻找一个“别人用0.01还是0.02”的标准值。

应该借鉴的是：

```text
分层
分阶段
能力约束
稳定确认
再继续
```

---

# 16. 是否还需要再做“深度检索”

## 16.1 不需要再做宽泛综述

目前：

```text
22篇完整精读
+
22篇实现级深榨
+
第二轮增量深度研究
+
本轮定向公开核查
```

已经足够支撑：

- PQ下一步；
- support角色分类；
- cleanup边界；
- ownership handover；
- Primary/Secondary分层；
- GFM能力必须约束恢复规模；
- staged pickup（分阶段功率拾取）。

继续重新搜：

```text
“black start microgrid GFM GFL”
```

意义已经很低。

---

# 17. 后续只需要两个窄检索问题

## 窄问题A：GFM headroom → restoration authority

重点问：

> 在1台BESS GFM黑启动源 + 多GFL恢复中，如何实时把GFM当前P/Q、电流、调制度和稳定裕量转换成“允许恢复多少GFL功率”？

优先：

```text
CIGRE 2026
Grid-Forming Inverter Capabilities for System Restoration in 100% IBR Power Systems
```

这篇当前 eCIGRE 需要付费。

如果用户有权限：

> 这是最值得下载给下一轮精读的全文。

---

## 窄问题B：restoration supervisor → normal EMS handover

重点问：

> 非黑启动资源恢复到什么条件以后，正常微电网功率管理才重新取得该设备的P/Q命令权？

优先：

```text
Yin 2019
Hierarchical control system for a flexible microgrid with dynamic boundary

Hu 2020
Real-time power management technique for microgrid with flexible boundaries

Zhang 2021
A Two-Level Simulation-Assisted Sequential Distribution System Restoration Model With Frequency Dynamics Constraints
```

Yin与Hu当前网页可直接访问正文/关键结构，Zhang可从IEEE/作者公开版本补全文。

---

# 18. Support到底是什么，是否黑启动必不可少

必须先纠正：

> **我们当前四路额外support并不是“任何黑启动系统都必不可少”的标准模块。**

当前 BASETEST 隔离的是：

```text
DampD
DampQ
SlowQ
LFQ
```

它们属于：

```text
AA15_GFL_ISLAND_SUPPORT
```

框架下的附加孤岛支撑请求。

---

# 19. 当前BASETEST到底关闭了什么

没有关闭：

```text
ESS1 GFM
Stage0→1→2弱网工程架构
真实breaker同步
Current Adapter
Current Regulator
基础Power Loop
GFL弱网模式基本结构
```

只在最终共同电流分配前把四路：

```text
DampD
DampQ
SlowQ
LFQ
```

请求置零。

所以：

> 当前稳定的Ki=.5小功率不是“没有任何弱网控制”的结果，而是“保留基础弱网架构、隔离四路附加support”的结果。

---

# 20. Support有没有可能是最终正常运行必需的

有两种合法架构。

## 架构A：support是增强项

```text
基础P/Q控制
本身稳定

support
= 提高阻尼/改善电压/频率性能
```

这种情况下：

```text
support不是黑启动必须条件
```

---

## 架构B：support是弱网模式正式组成

```text
进入弱孤岛
↓
必须建立support
↓
再释放P/Q功率
```

这种情况下：

```text
support就是正式孤岛控制的一部分
```

两种都可以。

关键不是名字，而是：

> 最终正常模型到底定义哪一种。

---

# 21. 文献怎么说Support

Arai类研究：

```text
GFL根据frequency / voltage偏差调整P/Q
```

Singhal类研究：

```text
GFL参与frequency/voltage restoration
```

所以：

> “GFL在孤岛里参与支撑”完全合理。

但新的 Grid-Supporting GFL（跟网型电网支撑）稳定研究又明确提醒：

```text
support
会改变GFL的dq动态导纳
会增加交叉耦合
```

因此：

> **support更多 ≠ 一定更稳定。**

所以我们绝不能因为这些support是“好功能”，就四路全部恢复并默认是必须的。

---

# 22. 因此“PQ后先验证support再cleanup”应如何改进

用户提出：

```text
Q
↓
support
↓
cleanup
↓
正式改模/接管
```

总体思路正确。

但 support 这一步应改成：

```text
Q闭环验证
↓
Support Audit（支撑功能审计）
↓
只对确定要保留的support做A/B
↓
决定最终support集合
↓
cleanup
```

不是：

```text
Q通过
↓
四路support全部打开
↓
只跑一轮
```

---

# 23. 为什么support应该在cleanup前审计/验收

因为现在 BASETEST selector（选择器）还在。

这反而给我们一个非常方便的 A/B 工具：

```text
同一模型
同一P/Q
同一Kp/Ki
只打开某一support family
```

一旦cleanup后删掉这些selector，再想做这种正交比较反而麻烦。

所以：

> **诊断结构不要在它完成最后一项诊断任务之前删掉。**

---

# 24. Support建议怎么分组，而不是四个全扫

先审计当前Ki=.5 MAT里的：

```text
Unselected_DampD
Unselected_DampQ
Unselected_SlowQ
Unselected_LFQ
```

看哪个请求在当前平台实际有显著活动。

然后按功能族，而不是穷举所有组合：

```text
Group S1：
DampD + DampQ
（阻尼类）

Group S2：
SlowQ
（慢电压/无功支撑）

Group S3：
LFQ
（低频无功支撑）
```

如果某支路：

```text
raw request≈0
```

在当前工况根本不参与，就没有必要为了“形式完整”先跑它。

---

# 25. 当前正确的短期试验顺序

```text
已经完成：
P-only
Kp=.06 Ki=.5
P=-.005
稳定
```

下一步：

```text
Test PQ
P=-.005
Qref=0
P loop ON
Q loop ON
support OFF
handover OFF
Primary OFF
Secondary OFF
```

如果PASS：

```text
Support Audit
↓
确定最终要保留哪些support
↓
对这些support做最少量A/B
```

然后：

```text
Control Cleanup
```

---

# 26. Cleanup以后不能立刻handover

Cleanup后必须重新跑一轮：

> **正式本地恢复路径验收。**

因为 BASETEST 当前绕开了：

```text
Restore-state6 → Restore-state7
```

的正式资格门。

正式 S14-40 想进入 S14-50，需要：

```text
Restore-state7
```

即：

```text
ESS2_LOCAL_RESTORED
（ESS2本地恢复完成）
```

所以 cleanup 后应重新校准：

```text
P/Q tracking
V/f
Iref/Imeas
CurrentLimit
ModHeadroom
dwell
rollback
```

再证明：

```text
Restore-state7
```

真的能成立。

---

# 27. ESS2完整正式黑启动接入——建议最终版

下面区分：

```text
【当前已实现】
【需要验证】
【建议新增设计】
【未来扩展】
```

---

# 28. Phase 1｜S14-10：ESS1_FORMATION

【当前已实现 / 已大量验证】

```text
ESS1唯一GFM
↓
死母线软建压
↓
建立10 kV / 50 Hz附近V/f
```

目的：

> 先形成唯一可靠电压/频率参考。

准入下一阶段至少看：

```text
V
f
CurrentLimit
ModHeadroom
ESS1健康
```

---

# 29. Phase 2｜S14-20：ESS2_GFL_PREPARE

【当前已实现】

ESS2仍：

```text
breaker OPEN
```

但控制器进入：

```text
ESS2-GFL-Stage1 PREPARE
```

目的：

> 让跟网型控制器先进入适合弱孤岛的准备状态，而不是突然合闸。

---

# 30. Phase 3｜S14-25：ESS2_ISLAND_STABILIZE

【当前已实现】

进入：

```text
ESS2-GFL-Stage2
```

并保持预合闸稳定窗口。

目的：

> 先让本地弱网控制结构settle（稳定下来），再允许真正breaker动作。

---

# 31. Phase 4｜S14-30：ESS2_ZERO_RECONNECT

【当前已实现 / 零功率物理并回已证明】

Restore Executor完成：

```text
QUALIFY
↓
READY
↓
真实breaker close
↓
CONNECTED_ZERO
```

物理含义：

```text
P*≈0
Q*≈0
但真实Current loop必须闭环
```

不是：

```text
Imeas=0
```

---

# 32. Phase 5｜本地P/Q基础闭环资格

【当前正在补齐】

现在已经：

```text
P-only Ki=.5 PASS
```

下一步：

```text
P+Q
P=-.005
Qref=0
```

回答：

> 本地基础P/Q控制在弱孤岛中能否稳定承担小功率。

---

# 33. Phase 6｜Support最终角色资格

【当前尚未完成】

不是机械“全部打开”。

先：

```text
audit
↓
分类
↓
只恢复最终正式架构需要的support
↓
A/B验证
```

最终得到：

```text
Final Support Set
（最终支撑集合）
```

---

# 34. Phase 7｜正式S14-40：POWER_PICKUP

【当前原型已实现，但最终语义建议升级】

当前：

```text
0 → -0.005
```

建议最终定义：

```text
Step A：
0 → P_qualification
例如 -0.005
hold
```

然后根据最终设计：

```text
Step B：
分阶段向 P_restoration_target 移动
```

每一级检查：

```text
P/Q tracking
V/f
ESS1 P/Q
ESS1 CurrentLimit
ESS1 ModHeadroom
ESS2 CurrentLimit
ESS2 ModHeadroom
PLL
dominant oscillation envelope
```

软异常：

```text
HOLD
→ 降额
→ 回到上一安全平台
```

硬故障：

```text
rollback
→ 必要时breaker OPEN
```

---

# 35. Phase 8｜DeviceRestoredACK

【建议正式明确化】

不要再把：

```text
“到时间了”
```

作为恢复完成。

建议：

```text
DeviceRestoredACK
=
BreakerClosed
&& PLLHealthy
&& PTrackingOK
&& QTrackingOK
&& IslandVoltageOK
&& IslandFrequencyOK
&& !CurrentLimit
&& ModHeadroomOK
&& NoAlarm
&& StableDwellDone
```

其中：

```text
ModHeadroomOK
```

是我们项目自己的工程扩展，不是论文标准字段。

---

# 36. Phase 9｜S14-50：ESS2_HANDOVER

【当前已设计 / 新P参数下未正式实测】

完整名称：

> **S14→Coordinator有功命令控制权无扰交接**

动作：

```text
ESS2Available = 1
OwnerRequest = 1

CorrectionEnable = 0
SecondaryEnable = 0

beta 0 → 1
```

这一步：

```text
不应该显著增加功率
```

只验证：

```text
S14 target
→
Coordinator baseline
```

能否无扰换手。

---

# 37. Phase 10｜S14-60：ESS2_COORD_PRIMARY

【当前已设计 / 未正式实测】

完整名称：

> **Coordinator取得ESS2命令权后，逐渐开放一次有功-频率快速协调。**

动作：

```text
beta=1

CorrectionEnable=1
CorrectionGain 0→1

Primary P-f ON
Secondary OFF
```

当前：

```text
authority default=.01
hard cap=.02
```

只作为：

```text
small-authority commissioning
（小权限一次协调验收）
```

---

# 38. Phase 11｜S14-70：ESS2_COORD_SECONDARY

【规划，当前未实现】

完整名称：

> **一次协调稳定以后，才开放二次频率/电压慢恢复。**

预计：

```text
CoordinatorStage=3
SecondaryEnable=1
```

这一步必须单独验证。

---

# 39. Phase 12｜正常权限扩大 / 正常功率承担

【当前R1缺口，未来必须设计】

这里才真正解决：

> ESS2怎样从1~2 kW的保守协调权限，走向真正正常运行需要的更大功率范围。

不能直接：

```text
authority .02
→ 1.0
```

建议：

```text
根据：
ESS1 GFM动态余量
ESS2自身能力
系统稳定裕量
其它已恢复设备

逐步扩大authority
```

或：

```text
在S14-40就把ESS2逐级拉到安全restoration target
再handover
```

最终采用哪一种，需要在 PQ + support + cleanup audit 后冻结。

---

# 40. Phase 13｜恢复PV/EV

【未来】

每台都不能简单：

```text
available=1
```

而应重复最基本逻辑：

```text
physical reconnect
↓
zero-power connected
↓
qualification
↓
staged pickup
↓
restored ACK
↓
normal coordination
```

设备细节可不同：

```text
PV
ESS
EV
```

不能复制一套阈值。

---

# 41. 当前推荐路线——最后冻结

```text
现在
│
├─ 1. P+Q小功率
│      P=-.005
│      Qref=0
│      P .06/.5
│      support OFF
│
├─ 2. Support Audit
│      不自动全恢复
│
├─ 3. 对最终需要的support做最少量A/B
│
├─ 4. Control Cleanup
│      保留Kp/Ki online
│      P Ki默认改.5
│      Recorder先保留
│
├─ 5. Audit + Verifier + Rebuild
│
├─ 6. 正式本地恢复复验
│      P+Q正式路径
│      final support set
│      Restore-state7 qualification
│
├─ 7. 正式S14-40最终pickup设计
│      qualification
│      staged restoration target
│
├─ 8. DeviceRestoredACK
│
├─ 9. S14-50 beta handover
│
├─ 10. S14-60 Primary
│       small authority
│
├─ 11. S14-70 Secondary
│       需要实现
│
├─ 12. dynamic ESS1 GFM reserve
│       + authority expansion
│
└─ 13. PV/EV逐台恢复
       → 完整正常孤岛
```

---

# 42. 一个需要进一步讨论的顺序细节：动态ESS1余量应放在Secondary前还是后

这里不要机械。

对于：

```text
small authority = .01/.02
```

下验证 Secondary：

可以暂时依靠硬限幅，不一定要先实现复杂动态reserve。

所以工程上更干净的因果顺序可以是：

```text
handover
↓
Primary @ small authority
↓
Secondary @ small authority
↓
再开发dynamic reserve
↓
扩大authority
↓
多资源恢复
```

但是：

> 一旦准备让ESS2承担明显更大的正常功率，或开始恢复PV/EV，动态GFM余量/功能等价能力约束就不能继续缺席。

---

# 43. 当前真正需要下载什么论文

不需要重新收集几十篇。

如果下一轮要把：

```text
动态ESS1 headroom
+
最终恢复目标
+
normal Coordinator handover
```

设计成正式版本，优先全文：

## 第一优先

**Grogan et al., CIGRE 2026**  
*Grid-Forming Inverter Capabilities for System Restoration in 100% IBR Power Systems*

重点找：

- 多GFL恢复时序；
- GFM BESS import/export limit；
- GFM/GFL容量/功率边界；
- PPC/PLL限制；
- current limiting；
- EMT波形；
- restoration recommendation。

当前 eCIGRE 是付费下载。

---

## 第二优先

**Yin et al., IET Smart Grid 2019**  
*Hierarchical control system for a flexible microgrid with dynamic boundary: design, implementation and testing*

重点：

- FSM功能使能矩阵；
- 恢复阶段哪些功能开/关；
- MGCC / LC分工；
- normal Energy Management何时恢复。

---

## 第三优先

**Hu et al., IET GTD 2020**  
*Real-time power management technique for microgrid with flexible boundaries*

重点：

- BESS建网后非黑启动PV如何接入；
- Power Management何时接管；
- OPAL-RT + CompactRIO HIL波形。

---

## 第四优先

**Zhang et al., IEEE TSG 2021**  
*A Two-Level Simulation-Assisted Sequential Distribution System Restoration Model With Frequency Dynamics Constraints*

重点：

- non-black-start资源何时进入active set；
- 恢复动作如何受频率动态可行性限制。

---

## 第五优先

**Rahimi et al., IET 2023**

用于：

- ESS2/EV作为充电型受控负荷时；
- 负增量阻抗；
- 功率水平/直流环带宽与稳定边界。

---

# 44. 当前不需要再搜的内容

无需再泛搜：

```text
GFM是什么
GFL是什么
black start一般流程
zero-power reconnect是否合理
GFM先建网是否合理
GFL是否能参与孤岛支撑
```

这些已有充分证据。

---

# 45. 最后的设计原则

## 原则1

```text
恢复设备
≠
立刻给正常大功率
```

---

## 原则2

```text
handover
= 换命令所有者
≠
立即扩大功率
```

---

## 原则3

```text
authority
= 可调范围
≠
固定功率目标
```

---

## 原则4

```text
Primary
= 快速频率功率修正
Secondary
= 慢速频率/电压恢复
```

---

## 原则5

```text
GFM reserve
不一定叫一个标准模块
但GFL恢复必须受GFM实时能力约束
```

---

## 原则6

```text
support不是越多越好
```

最终support集合必须由：

```text
模型目的
+
A/B证据
+
弱网稳定性
```

决定。

---

## 原则7

每次正式实验只增加一层控制责任：

```text
P
→ Q
→ final support set
→ formal local restored
→ ownership
→ Primary
→ Secondary
→ larger authority
→ next resource
```

不要一次全开。

---

# 46. 本文来源与证据边界

## 用户已有22篇精读基线

- 《孤岛与黑启动——22篇论文完整精读、控制逻辑、波形证据与现有模型启示》
- 《孤岛与黑启动——22篇论文实现级深榨》
- 《黑启动第二轮深度研究》

这些资料已经明确区分：

```text
论文明确
框图还原
跨论文归纳
对本项目启示
论文未说明
```

本文沿用这一证据纪律。

---

## 本轮再次核查的公开来源

1. Arai & Taguchi, 2022  
   *Coordinated control between a grid forming inverter and grid following inverters supplying power in a standalone microgrid*  
   DOI: 10.1016/j.gloei.2022.06.002

2. Grogan et al., CIGRE 2026  
   *Grid-Forming Inverter Capabilities for System Restoration in 100% IBR Power Systems*  
   Ref: C4_10396_2026

3. Yin et al., 2019  
   *Hierarchical control system for a flexible microgrid with dynamic boundary: design, implementation and testing*  
   DOI: 10.1049/iet-stg.2019.0115

4. Hu et al., 2020  
   *Real-time power management technique for microgrid with flexible boundaries*  
   DOI: 10.1049/iet-gtd.2019.1576

5. Zhang et al., 2021  
   *A Two-Level Simulation-Assisted Sequential Distribution System Restoration Model With Frequency Dynamics Constraints*  
   DOI: 10.1109/TSG.2021.3088006

6. Singhal et al., 2022  
   *Consensus Control for Coordinating Grid-Forming and Grid-Following Inverters in Microgrids*  
   DOI: 10.1109/TSG.2022.3158254

7. Tian et al., 2023  
   *Transient Synchronization Stability of an Islanded AC Microgrid Considering Interactions Between Grid-Forming and Grid-Following Converters*  
   DOI: 10.1109/JESTPE.2023.3271418

8. Seo et al., 2025  
   *Microgrid Black Start Challenges: The Role of Grid-Forming Inverters*  
   DOI: 10.1109/ACCESS.2025.3634530

---

# 47. 当前一句话

> **下一步先完成P+Q小功率验收；然后利用仍存在的BASETEST选择器做一次support角色审计和最少量A/B，不把四路support自动视为黑启动必需模块；之后再做Control Cleanup和正式模型审计。最终ESS2恢复不能停在“-0.005→beta→0.01 pu小authority”，而要补齐“安全功率逐级恢复→Restored ACK→无扰交接→Primary→Secondary→基于ESS1实时能力扩大正常协调权限”这一完整链。**
