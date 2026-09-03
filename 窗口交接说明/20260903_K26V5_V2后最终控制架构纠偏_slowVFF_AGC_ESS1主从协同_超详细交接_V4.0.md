# K26_V5｜V2 实测后最终控制架构纠偏、slow-VFF / AGC / 主从协同统一设计与下一阶段超详细交接 V4.0

> 日期：2026-09-03  
> 对象：K26_V5，2PV + 2ESS + 2EV 六逆变器光储充微电网  
> 计划离岛角色：ESS1 = 唯一 GFM；PV1/PV2/ESS2/EV1/EV2 = 五台 current-controlled GFL / grid-supporting slave units  
> 本文性质：**从上一份《最终五GFL工程改造超详细窗口交接 V3.1》和 V2 正式实测结果继续，不重新开历史根因树。**  
> 本文重点：纠正“把极端因果隔离状态当成最终工程控制器”的规划错误，回答 slow-VFF 参数、P/Q/AGC、ESS1 参考、五设备岛态角色、文献依据和下一次真正完整验收应该怎样设计。  
> 最高原则：**不再做 Kslow=0/0.5/1 这种物理单变量盲试；所有最终参数必须从完整闭环、输出导纳/特征值和设备角色共同设计。**

---

# 0. 与上一份交接文档的衔接：我们到底走到哪了

上一份交接冻结的核心事实仍然成立：

```text
J1 CLOSED：
上级强网提供主要电压/频率刚度

J1 OPEN：
ESS1 成为唯一 GFM
其余 PV1/PV2/ESS2/EV1/EV2 继续保持 GFL
```

原系统第一层快速失稳已经强锁定：

```text
五 GFL Current Regulator
terminal Vdq 近单位直接前馈
+
ESS1 GFM finite output impedance
+
network / digital delay
↓
约 10~17 Hz 正增长 GFM-GFL 交互
```

历史关键证据：

```text
B1：
native PLL active frame 不是原 fast root

C1 full DQ HOLD：
动态 terminal-Vdq 前馈被切断后，原 fast mode 消失

C2：
P/Q dynamic Iref 不是原 fast mode 必要条件

C1-Q / Mode6：
D/Q dynamic terminal-Vdq 都能独立维持不同失稳机制

Mode7：
Vff = Vslow + Kfast(Vraw-Vslow)
Kfast island = 0
fc ≈ 1 Hz
→ 原高可信 10~17 Hz 模态转负 / 消失
```

这些不重开。

上一阶段又完成了最终工程 V1、V2 两轮模型重构。

## V1 的失败属于“确定性的工程设计错误”

V1 曾经出现：

```text
raw Vref ≈ 9600 V
直接被当成
VrefPu ≈ 9600 pu
```

导致五台 voltage support 第一拍全部打满；

并且：

```text
SupportClipActive
和
CurrentCapabilityActive
```

被错误混为一个 flag，造成 PQ recovery 永久锁死。

这些属于**明确设计缺陷**。

## V2 已经修掉 V1 的明确实现缺陷

V2 正式运行后的 MATLAB 证据：

```text
NumericalExecutionContractValid = 1

PV1  = 1
PV2  = 1
ESS2 = 1
EV1  = 1
EV2  = 1
```

五台都逐点满足：

```text
Stage0 VFF bypass = exact
Stage0 Iref bypass = exact

Stage1 VFF equation = exact
Stage2 VFF equation = exact

Pref/Qref equation = machine precision
Stage2 Iref equation = exact

Kslow = 0
Kfast = 0
PQGate = 0

VsupportRef frozen span = 0
CurrentCapabilityActive = 0
LambdaPQ = 1
```

所以 V2 这次**不是模型没执行、不是单位错、不是接线错、不是状态机写错**。

但 V2 Stage2 仍发生严重慢失稳：

```text
Stage3Authorized = 0

Stage2-only：
Vmin ≈ 0.0235 pu
Vmax ≈ 1.4273 pu
```

因此需要重新审判的是：

> **V2 Stage2 作为“最终工程工作状态”的控制哲学是否正确。**

最新结论：

> **不正确。V2 Stage2 是一个很干净的因果隔离状态，但被我们错误地赋予了“它应该长期成为最终岛态”的含义。**

这是本文第一条纠偏。

---

# 1. 本轮必须先纠正的规划错误

用户指出的三个问题全部成立。

---

## 1.1 “不让 P/Q 外环恢复、不让 AGC、不让 dynamic VFF，底层怎么一定能稳定？”

正确答案：

```text
不能假定一定稳定。
```

关闭这些路径的意义只在于：

```text
隔离因果
```

而不是：

```text
构成最终岛态控制器
```

尤其：

### AGC

原并网 PCC-tracking AGC 在 J1 OPEN 后不能继续以原目标运行，这一点仍然正确。

但是：

```text
“原 PCC AGC 不继续”
≠
“岛态永远没有上层功率协调”
```

后面必须有 island dispatch / secondary coordination。

### P/Q 外环

```text
PQGate = 0
```

可以用于切岛初期暂时卸掉恒功率负反馈压力；

但不能把：

```text
五台 GFL 的 P/Q 任务永久冻结
```

作为最终运行状态。

### slow VFF

不能把：

```text
Kslow = 0
```

理解成“最终正确控制”。

这样会让 Current PI 承担全部慢端口电压补偿。

---

## 1.2 V2 Stage2 实际上重新把 C1 hard HOLD 长期化了

V2 Stage2：

```text
Kslow = 0
Kfast = 0
```

所以：

\[
V_{ff}=V_{anchor}
\]

这意味着：

```text
terminal voltage变了
VFF不再跟
```

这正是 C1 因果诊断“硬 HOLD”的核心效果。

而历史 C1 后我们早就记录过：

```text
fast mode被打断
但出现slow frequency/angle slip
Current PI不断补偿
```

所以：

> C1 是强诊断刀，不是最终工程控制器。

V2 又把它做成长期 Stage2，这是规划上的过度修正。

---

## 1.3 “下一轮 Kslow=1”也是重复旧实验，不能再这样做

Mode7 本身就是：

```text
Kslow = 1
Kfast = 0
fc ≈ 1 Hz
```

即：

```text
Vff ≈ Vslow
```

结果：

```text
fast mode消失
但慢电压严重塌陷
```

历史 Layer2 又已经测试：

```text
Mode7 : Kslow=1,   P/Q dynamic=1
Mode1 : Kslow=0.5, P/Q dynamic=1
Mode2 : Kslow=1,   P/Q dynamic=0.5
Mode3 : Kslow=0.5, P/Q dynamic=0.5
V2    : Kslow=0,   PQGate=0
```

所以：

```text
0
0.5
1
```

都已经给过信息。

下一步绝不能继续：

```text
0.4
0.6
0.7
```

在 RT-LAB 里一个个试。

---

# 2. V2 最新数据到底说明了什么

这一部分是新窗口必须先继承的“当前事实”，以后不要重新让用户上传旧 MAT。

---

## 2.1 Stage3 没有动作，这恰好排除了 P/Q recovery

V2 Stage timeline：

```text
五台 Stage1 ≈ 7.427 s
Kslow target settle ≈ 7.437 s
Kfast target settle ≈ 7.437 s
PQGate zero ≈ 7.437 s

J1 / Stage2 ≈ 8.409 s

Stage3 = NaN
```

所以全程：

```text
Stage3没有参与
P/Q recovery没有参与
```

这说明 V2 失稳不能再推给：

```text
Stage3
P/Q恢复过快
恢复dwell
恢复slew
```

---

## 2.2 五台真正的 CurrentCapability 没有介入

五台：

```text
CurrentCapabilityActive = 0
LambdaPQ = 1
```

整个 Stage2 都成立。

说明：

```text
final vector limiter
不是首发失稳机制
```

EV1/EV2 后段 SupportClip 会出现，但：

```text
first support clip ≈ J1+6.598 s
```

而失稳早得多。

所以：

```text
SupportClip
也不是初始根因
```

---

## 2.3 FrameHold 也是后果

五台 FrameHold 第一次动作：

```text
≈ J1 + 1.171 s
```

此时母线早已进入明显异常。

因此：

```text
PLL/frame fallback
不是首发
```

仍是低压后的鲁棒性保护。

---

## 2.4 ESS1 不是第一拍先触顶

V2：

```text
ESS1 ModIndex > 0.98
≈ J1 + 1.733 s
```

而系统明显电压失稳早于此。

F25：

```text
无 slew
无 magnitude limit
无 timeout
无 state7
```

所以：

```text
ESS1/F25依旧不是首发解释
```

---

## 2.5 VFF 的 fast 动态确实被切掉

V2 fast modal 文件中：

```text
Vff_d = 常值
Vff_q = 常值
```

历史 17 Hz / 10.6 Hz 在 VFF 上的拟合幅值已经接近机器零。

这说明：

> **原 dynamic terminal-VFF 这条快速必要路径，在 V2 Stage2 确实已经从当前闭环里切掉。**

不能再说：

```text
可能Kfast没关成功
```

---

## 2.6 新数据真正突出的是五台 Current PI 的同步慢补偿

V2 Stage2：

```text
PQGate = 0
VFF = fixed anchor
Raw Iref基本冻结
```

但五台 CurrentPI_d 都持续大幅变化。

从 compact 10 ms 时间序列重新检查：

```text
PV1/PV2/ESS2/EV1/EV2
五台 d 轴 Current PI
约 J1+3.07 s
全部到达约 -1.24~-1.25
```

五台 d 轴 PI 在 J1 后 0~3.1 s 的相关系数接近：

```text
0.999~1.000
```

每台：

```text
CurrentPI_d
与
(RawVd - fixed VFF_d)
```

的相关系数也约：

```text
0.998
```

这不是单独某一台设备随机漂移。

它显示的是：

```text
公共母线 / 公共控制结构导致的同步补偿负担
```

注意：

> 高相关性本身不是“数学上的最终根因证明”，但它非常强地支持“hard slow-VFF freeze 将慢端口补偿整体转移到五台 Current PI”这一机制。

---

# 3. 用户问题一：两频带 VFF 到底怎么设置？公式是否合理？

最终讨论公式：

\[
V_{ff}
=
V_{anchor}
+
K_{slow}(V_{slow}-V_{anchor})
+
K_{fast}(V_{raw}-V_{slow})
\]

其中：

\[
V_{slow}
=
\frac{\omega_c}{s+\omega_c}V_{raw}
\]

对 terminal-voltage 小扰动而言，等效 VFF 频率响应为：

\[
H_{vff}(s)
=
K_{fast}
+
(K_{slow}-K_{fast})
\frac{\omega_c}{s+\omega_c}
\]

整理：

\[
\boxed{
H_{vff}(s)
=
\frac{K_{fast}s+K_{slow}\omega_c}{s+\omega_c}
}
\]

这非常重要。

因为：

```text
s -> 0：
H_vff -> Kslow

s -> ∞：
H_vff -> Kfast
```

所以这三个参数不是三个“经验旋钮”，而分别控制：

```text
Kslow：
低频 / DC terminal-voltage feedforward比例

Kfast：
高频 terminal-voltage feedforward比例

fc：
低频行为和高频行为之间的分界速度
```

---

## 3.1 Kfast 怎么定

这个参数是目前最有证据的一项。

C1 / Mode6 / Mode7 已经证明：

```text
8~25 Hz dynamic terminal-VFF
是原 fast instability 的主要必要路径
```

因此第一正式原则：

```text
Kfast = 0
```

或至少：

```text
非常接近0
```

目前没有理由重新把它开回 0.25。

这不是猜值。

这是因果证据直接支持的。

---

## 3.2 fc 怎么定

Mode7：

```text
fc ≈ 1 Hz
Kfast = 0
```

已经真实证明：

```text
10~17 Hz fast mode被显著抑制
```

因此：

```text
fc = 1 Hz
```

作为第一版频带分界是有物理依据的，不是随机数字。

用简单数量级看：

若：

```text
Kfast=0
fc=1Hz
```

则高于 fc 后，低通分量快速衰减。

对于 8 Hz：

\[
|LPF|\approx \frac{1}{\sqrt{1+8^2}}\approx0.124
\]

10.6 Hz：

```text
≈ 0.094
```

17 Hz：

```text
≈ 0.059
```

所以即使：

```text
Kslow=1
```

fast band 也已经只有约 6%~12% 的 terminal-V 动态能走这条低通路径。

这和 Mode7 fast mode消失相互一致。

### 因此当前不需要先改 fc

第一版可以继续：

```text
fc_vff = 1 Hz
```

除非后续输出导纳分析明确指出：

```text
分界频率需要移动
```

---

## 3.3 Kslow 不能从旧实验直接指定为某个数

这是最重要的纠偏。

历史：

```text
Kslow=1
失稳

Kslow=0.5
也失稳

Kslow=0
也失稳
```

但三次对应的其他闭环都不一样：

```text
Mode7：
P/Q保持强恒功率追踪
没有最终resource-specific island support

Mode1：
P/Q仍全部参与
没有最终resource-specific island support

V2：
P/Q完全冻结
VFF也完全冻结
```

所以不能得出：

```text
Kslow应该等于0.6
```

这种结论。

真正应该做的是：

> **先把最终岛态 P/f、Q/V、current limit、ESS1 reference 使用方式确定，再在这个完整闭环下用输出导纳/特征值选 Kslow。**

---

# 4. 两频带 VFF 到底合不合理？

## 4.1 “频带分开”这一思想是合理的

原因：

```text
fast path已实验证明危险
slow path完全冻结又把负担推给Current PI
```

所以：

```text
fast强抑制
+
slow有限保留
```

是目前最符合全部证据的方向。

---

## 4.2 但“两个常数 + 一个一阶LPF”不保证一定是最终最佳形式

2026 年相关 GFL 文献已经明确指出：

```text
voltage feedforward
会在不同频带重塑输出导纳

改善高频passivity
可能同时恶化低频positive admittance
```

所以真正最终设计必须检查：

```text
dq output admittance
MIMO coupling
passivity / dissipativity
generalized Nyquist
```

如果：

```text
Kslow + Kfast + 一阶LPF
```

无法同时得到：

```text
fast稳定裕度
+
slow稳定裕度
```

下一步应该升级 transfer function：

```text
二阶LPF
lead-lag
modified active damping
```

而不是继续：

```text
Kslow=0.4/0.6/0.8
```

在实机盲试。

---

# 5. 为什么模型改了两次，效果还是看起来“差不多”？

因为前两轮“改模”并没有真正把**最终 island control architecture**一次实现完。

这是需要明确承认的地方。

---

## V1 做了什么

V1 想同时解决：

```text
fast VFF
slow voltage support
P/Q gate
current limit
PLL guard
```

但存在：

```text
Vref单位错误
limit flag语义错误
PQ recovery被错误锁死
```

所以 V1 不是有效工程验证。

---

## V2 做了什么

V2 修掉了 V1 的这些明确错误，并做了：

```text
两频带VFF结构
local voltage support
current capability
Stage2/Stage3
```

但 V2 Stage2 默认设成：

```text
Kslow=0
Kfast=0
PQGate=0
```

本质上是：

```text
极端隔离状态
```

而不是完整 island GFL controller。

更重要的是，V2 还没有真正实现：

```text
PV / ESS2 / EV 差异化的 island P/f 行为

真正的 island secondary AGC

ESS1公共angle/frequency作为五GFL计划离岛frame reference

最终 vector-current saturation 对外层PI的 anti-windup回灌
```

所以：

> **V2 是一个执行正确、诊断价值高、但控制职责仍不完整的中间工程架构。**

不是“完全正确的最终控制器”。

---

# 6. 用户问题二：slow VFF 缺失 → Current PI 漂移，不是一直在排除吗？

正确理解要分三层。

---

## 6.1 C1 已经证明 hard HOLD 会产生 slow artifact / slow slip

这一点早就知道。

所以不能把：

```text
Kslow=0
```

当最终工程答案。

---

## 6.2 Mode7 / Layer2 又证明 Kslow=1 也不够

这说明：

```text
只恢复slow VFF
```

也不能建立稳定孤岛。

---

## 6.3 因此现在不是又“回到 slow VFF 是唯一根因”

当前真正冻结的结论应该是：

> **slow VFF 是低频端口行为的一部分，但不是独立唯一根因。**

完整慢层是：

```text
slow VFF
+
P/Q / constant-power behavior
+
Current PI
+
resource power balance
+
ESS1 finite GFM Zout
+
PLL/frame robustness
+
current capability
```

的整体相互作用。

所以我们不能再写：

```text
根因 = slow VFF缺失
```

更准确：

> **V2 hard freeze 将 slow compensation 过度转移给 Current PI；而原 Mode7/Mode1 又证明只靠恢复 slow VFF 仍不能解决 constant-power / power-sharing 架构失配。**

这两句话并不矛盾。

它们共同说明：

```text
最终控制必须同时解决：
频带塑形
+
岛态功率平衡
```

---

# 7. 用户问题三：AGC 到底应该怎样？

用户之前提出的思想：

```text
岛态不要让AGC调ESS1
```

本质上是合理的。

但需要重新把“AGC”分成两类。

---

## 7.1 并网 PCC AGC

并网：

```text
目标：
PCC / tie-line功率跟踪
```

J1 OPEN 后：

```text
PCC物理断开
```

所以：

```text
PCC-tracking error
```

不再是正常岛态调度目标。

因此：

```text
原 PCC AGC
在 J1 OPEN 后应该退出
```

这一点不变。

---

## 7.2 岛态 secondary AGC / dispatch

岛态仍然应该有上层协调。

而且完全可以：

```text
继续使用“改进AGC”的资源分配思想
```

但控制目标必须换掉。

推荐：

```text
ESS1：
唯一GFM / slack-like master
不直接接受secondary P command快速追踪

五GFL：
PV1/PV2/ESS2/EV1/EV2
接受 island secondary dispatch
```

secondary error 可以来自：

```text
ESS1持续承担的有功偏置
frequency restoration error
资源SOC/可调裕度
```

例如：

\[
\Delta P_{bal}
=
P_{ESS1}-P_{ESS1,bias}
\]

或：

\[
\Delta P_f
=
K_f(f_{nom}-f_{GFM})
\]

secondary coordinator 再把它分给：

```text
PV headroom
ESS2 charge/discharge margin
EV flexible charging margin
```

这样：

```text
ESS1只负责快速平衡和形成V/f
↓
secondary慢慢把长期功率负担转移给五GFL
↓
ESS1回到合理reserve附近
```

这和“AGC不调ESS1”是统一的。

---

# 8. 最终控制层级应该怎样划分

以后不要再把：

```text
Stage2
Stage3
```

理解成简单“关/开某个增益”。

最终应该按**控制时间尺度与职责**设计。

---

## Layer A：电磁/电流层

100 µs / ms 级：

```text
Current PI
PWM
Rff/Lff
vector current limiter
```

目标：

```text
安全、快速、稳定执行电流
```

---

## Layer B：GFL本地 primary grid-supporting 层

几十 ms ~ 数百 ms：

```text
two-band VFF
frequency-responsive active power
local voltage support
current capability priority
anti-windup
```

目标：

```text
J1一开就马上参与稳定
```

这些必须在 J1 OPEN 第一拍就处于最终正确状态。

---

## Layer C：ESS1 GFM primary layer

ESS1：

```text
形成：
theta
frequency
voltage

通过：
P-f droop / frequency dynamics
Q-V droop / voltage loop
承担瞬时residual power mismatch
```

---

## Layer D：island secondary coordination

约 0.5~数秒以后：

```text
恢复frequency toward nominal
把ESS1长期P/Q负担重新分给五GFL
SOC / headroom协调
PV curtailment
EV charging adjustment
ESS2 dispatch
```

这才是岛态 AGC。

---

# 9. 用户问题四：是否需要检索文献？

答案：

```text
需要，而且已经做了定向检索。
```

因为现在剩下的不是 K26 某个 Simulink bug，而是：

```text
一主五从的 island microgrid control architecture
```

必须和已有 master-slave / GFM-GFL / PV-ESS / EV island coordination 对齐。

---

# 10. 定向文献检索结论

以下不是用文献替代 K26 证据，而是用文献约束最终工程结构。

---

## 10.1 Carnielutti et al. — IEEE TPEL, 2025

**A Master-Slave Model Predictive Control Approach for Microgrids**  
IEEE Transactions on Power Electronics, 40(1), 540–550  
DOI: `10.1109/TPEL.2024.3464105`

其系统明确：

```text
grid connected：
master + slaves 都GFL

island：
master BESS -> GFM
PV slaves -> remain GFL
```

并做了 HIL 验证。

这直接支持我们的基本架构：

```text
ESS1唯一GFM
其余设备仍然current-controlled GFL
```

所以：

```text
不是一定要把ESS2也改GFM
```

---

## 10.2 “Coordinated control between a GFM and GFLs in standalone microgrid”, 2022

DOI：

`10.1016/j.gloei.2022.06.002`

核心：

```text
单一GFM master决定frequency / voltage
其他GFL subordinate sources执行P/Q
EMS负责整体协调
```

这和我们的目标非常接近。

但关键是：

> subordinate GFL 的 P/Q 不是“永久冻结”，而是在 EMS / island control 下协调。

---

## 10.3 PV-ESS coordinated island control literature

“Coordinated control for PV-ESS islanded microgrid without communication”

核心行为：

```text
ESS：
droop / grid-supporting

PV：
正常时MPPT
必要时根据frequency切入droop / curtailment

当ESS吸收能力不足：
PV不再强行维持最大功率
```

而且该文明确：

```text
建立不同operation modes的小信号模型
用small-signal stability设计control coefficients
```

这和我们现在应该停止盲扫、转向闭环参数设计高度一致。

---

## 10.4 NREL communication-less microgrid

NREL 的典型思想：

```text
battery / dispatchable source形成frequency

PV / wind等资源：
观察frequency
根据frequency改变power
```

即：

> frequency 可以作为 GFM 和 GFL 之间天然的“公共语言”。

这对 K26 很重要：

```text
ESS1的f
不应该只是一个logger信号
```

它应该真正进入五GFL island active-power behavior。

---

## 10.5 NREL GFM roadmap

Roadmap指出：

```text
GFL依赖well-defined terminal voltage/frequency
GFM能够形成voltage/frequency
```

并明确提到：

```text
GFL在island中只能在特定条件下正常工作
```

因此“一主五从”不是：

```text
ESS1形成V/f
五台仍完全照搬strong-grid constant-PQ
```

而必须做 grid-support / dispatch compatibility。

---

## 10.6 Zhang et al., IJEPES 2026

**Quantitative stability analysis of Grid-Following inverter with Grid-Supporting control and stability enhancement method based on Multi-Voltage feedforward**

结论之一：

```text
给GFL加grid-supporting control
本身会新增dq coupling
并可能降低弱网稳定性
```

所以：

> 我们不能只说“加support一定有利”。

必须看完整 dq admittance。

---

## 10.7 Ma et al., IEEE TIE 2026

**Wideband Stability Improvement of Grid-Following Inverter Through a Modified Active Damping Scheme**  
DOI：`10.1109/TIE.2026.3684189`

结论与 K26 特别相关：

```text
lowpass voltage feedforward
可能改善high-frequency passivity

但同时可能降低
current-controller-related low-frequency positive admittance
```

所以：

```text
Kslow / fc
不能靠时域波形拍脑袋
```

必须做频域设计。

---

## 10.8 E-GFL, IEEE TPEL 2024

**Enhanced Grid-Following Inverter: A Unified Control Framework for Stiff and Weak Grids**  
DOI：`10.1109/TPEL.2024.3350528`

它强调：

```text
dq耦合
line dynamics
synchronization
current tracking
performance tradeoff
```

应该整体设计。

这再次说明：

```text
不要把slowVFF当成唯一变量
```

---

# 11. 用户问题五：五台设备在并离网切换后到底应该是什么状态？

以下是最终推荐的**设备角色冻结**。

---

# 12. ESS1：唯一 GFM master

J1 OPEN 后 ESS1 应：

```text
形成 voltage magnitude
形成 frequency
形成 angle

承担最初瞬时有功/无功 mismatch
```

不是：

```text
secondary AGC的普通受控P/Q设备
```

ESS1 可以有：

```text
P-f droop
Q-V droop
F24/F25 bumpless handover
```

长期目标不是让它永久承担全部功率失配。

secondary island coordinator 应逐步把长期负担卸给其他设备。

---

# 13. ESS2：最强的 supporting GFL

ESS2仍保持：

```text
current-controlled GFL
```

但岛态不应仅：

```text
追一个固定 P/Q
```

建议 primary：

```text
frequency ↓
→ ESS2增加放电 / 减少充电

frequency ↑
→ ESS2减少放电 / 增加充电
```

并：

```text
local voltage低
→ 提供合适Iq / reactive support
```

受：

```text
SOC
Pmax
Qmax
Imax
```

限制。

ESS2 是五台中最适合承担双向有功 primary support 的资源。

---

# 14. PV1 / PV2：GFL renewable slaves

并网：

```text
正常P/Q / MPPT逻辑
```

岛态：

### 有功

如果 PV 已经在最大可用功率：

```text
under-frequency时没有额外向上headroom
```

所以不能虚构：

```text
PV一定可以增加P
```

但：

```text
over-frequency / power surplus
→ PV可以curtail
```

如果未来特意保留 headroom：

```text
under-frequency
→ 才能增加PV P
```

### 无功/电压

PV inverter仍可在 current capability 允许时：

```text
提供 Q / Iq voltage support
```

但 current priority 必须明确。

---

# 15. EV1 / EV2：优先把它们视为 flexible charging load

如果当前运行状态是充电：

```text
under-frequency
undervoltage
```

第一正确响应应该是：

```text
减少充电功率
```

而不是：

```text
继续维持恒功率充电
```

这本身就是非常有效的 island load relief。

若模型和未来实际接口明确支持 V2G，则：

```text
可以进一步从0充电跨到discharge
```

但不能在没有实际 V2G/SOC合同情况下默认这一点。

over-frequency / surplus：

```text
EV可以增加允许范围内的charging
```

所以 EV 是极有价值的可调负荷。

---

# 16. 五 GFL 共同必须有的状态

J1 OPEN 后：

```text
仍然都是 current-controlled
仍然不是新的voltage source
仍然不抢ESS1的GFM角色
```

但应该：

```text
跟随ESS1形成的theta/f

有自己的resource-specific active-power response

有local voltage support

有最终current vector limit

有outer-loop anti-windup

有secondary dispatch接口
```

这才是：

```text
grid-supporting GFL
```

而不是：

```text
strong-grid GFL原样搬到孤岛
```

---

# 17. 用户问题八：现在到底有没有利用 ESS1 的电压、相角、频率？

## 当前 V2

当前五台主要还是：

```text
使用自己的local Measurements / PLL execution frame
```

只有低压后：

```text
FrameHoldReq
```

去做本地 frame fallback。

因此：

> **当前 V2 没有把 ESS1 的 θ/f 显式作为五台 GFL 的统一 island execution reference。**

五台只是通过公共电网物理电压“间接看到”ESS1。

---

# 18. 最终推荐：planned island 使用 ESS1 common angle/frequency reference

因为我们是：

```text
planned island
```

不是突然无通信 black-start。

如果现有跨任务信号路径允许低成本实现，推荐：

## GRID CONNECTED

```text
五GFL：
local PLL frame
```

## ISLAND PREPARE

在 J1 OPEN 前：

```text
ESS1 GFM self-generated theta/f
已经和grid对齐

五GFL：
local PLL frame
→ bumpless blend
→ ESS1 common theta/f
```

## ISLANDED

五台执行 dq 变换优先：

```text
theta = theta_ESS1_GFM
f = f_ESS1_GFM
```

local PLL：

```text
保留监视 / recovery / backup
```

这样做的意义：

```text
把“同步谁”
从五个独立弱网PLL问题
变成
一个ESS1 master reference
```

这与 master-slave 微电网非常一致。

---

# 19. 电压幅值不能简单全部强跟 ESS1 local V

角度/频率可以作为全局参考。

电压幅值不同。

因为：

```text
各设备之间存在line/filter voltage drop
```

所以不能简单：

```text
PV1 Vref = ESS1 terminal V
PV2 Vref = ESS1 terminal V
...
```

否则五台可能为了“强制同电压”互相打架。

推荐：

```text
ESS1提供全局 Vmaster / Vout reference
+
每个GFL保留自己计划离岛前local voltage offset
```

例如：

\[
V_{ref,i}^{isl}
=
V_{GFM,ref}
+
\Delta V_{i,pre}
\]

其中：

\[
\Delta V_{i,pre}
=
V_{i,pre}
-
V_{ESS1,pre}
\]

这样：

```text
ESS1全局电压目标变化
→ 五台一起知道

但
每台本地正常line-drop offset
→ 保留
```

这是比 V2 单纯固定 `VsupportRef` 更完整的主从电压关系。

---

# 20. 最终 island active-power 控制应该怎样

不建议继续：

```text
PQGate=0
然后某天PQGate直接恢复原Pref
```

应该直接构造 island P reference。

对第 i 台 GFL：

\[
P_{i,ref}^{isl}
=
P_{i,0}
+
\Delta P_{f,i}
+
\Delta P_{sec,i}
\]

其中：

```text
P_i0：
切岛前bumpless capture的基准

ΔP_f,i：
本地primary frequency response

ΔP_sec,i：
更慢的island secondary coordinator输出
```

---

# 21. primary frequency response

推荐统一用：

```text
ESS1 GFM frequency
```

而不是五个独立PLL频率作为控制真值。

形式：

\[
\Delta P_{f,i}
=
K_{f,i}(f_{nom}-f_{GFM})
\]

但不同设备有不同 saturation / direction。

### ESS2

```text
双向最大能力
```

### PV

```text
受available PV/headroom约束
```

### EV

```text
优先通过减少/增加charging实现
```

这样五台不是“等同设备”。

---

# 22. reactive / voltage primary support

这里不能把：

```text
原Q PI
+
新的fast Q-V droop
+
新的Iq support
```

全部同带宽叠加，否则容易形成新的耦合。

推荐第一正式架构：

```text
Q outer reference:
保持较慢 / captured baseline

+
一条明确的 local voltage-support current：
ΔIq_v = Yv(s)*(Vref_local - Vlocal)
```

即：

\[
I_{q,ref}^{final}
=
I_{q,PQ}
+
\Delta I_{q,v}
\]

而不是让多个独立快速Q控制器互相抢。

---

# 23. 用户问题六：是不是设置合理 slow VFF，再把全部功能打开跑一次？

结论：

## “最终一定要有一次全部功能完整验收”——对

但：

## “现在先随便给 Kslow 一个合理数字，再把 V2 全开”——不对

原因：

当前 V2 Stage3 恢复的是：

```text
原冻结P/Q命令
```

并不是：

```text
resource-specific island P/f reference
```

当前 V2 也没有：

```text
ESS1 common theta/f
island secondary AGC
final outer-loop saturation anti-windup
```

因此把：

```text
Kslow=.6
然后 Stage3全开
```

跑一次，仍然不是完整正确 island controller。

失败以后还是会混淆。

---

# 24. 正确的“一次全面验收”应该是什么

先完成理论设计和最终控制结构。

然后只有一个正式 physical run。

J1 OPEN 第一拍：

```text
ESS1：
GFM master

五GFL：
ESS1 common theta/f
two-band VFF
resource-specific P/f primary response
local voltage support
current capability
anti-windup
```

全部 primary 功能都应该已经处于正确状态。

不是一个一个开。

然后：

```text
系统先靠primary形成稳定
```

若达到健康窗口：

```text
island secondary AGC / dispatch逐步进入
```

这属于正常 hierarchical control，不是“单变量试验”。

---

# 25. 这一个全面验收为什么仍然能定位问题

因为所有关键贡献都被独立记录：

```text
VFF slow contribution
VFF fast contribution

P/f primary contribution
voltage support contribution

PQ base component
secondary AGC component

current limiter
lambda

ESS1 P/Q/f/V/theta

五设备P/Q/I/V
```

所以如果失败：

### fast 10~17 Hz

看：

```text
VFF fast contribution
Current PI
Vconv
```

### slow voltage drift

看：

```text
slow VFF contribution
P/f support
ESS1 P residual
Current PI
```

### secondary进入后才坏

看：

```text
secondary dispatch contribution
```

因此：

> **完整控制不等于不可诊断。**

真正的问题是以前 diagnostics 没有和 control contribution 一一对应。

---

# 26. slow VFF 怎样“彻底关闭”？是不是只有设置参数？

从数学上：

```text
Kslow = 0
```

就已经严格得到：

\[
K_{slow}(V_{slow}-V_{anchor})=0
\]

这是“贡献为零”。

不需要把 Vslow tracker 本身冻结。

事实上：

> **让 Vslow state继续跟踪，反而更好。**

因为以后 re-enable 时：

```text
不会从陈旧state突然跳
```

所以正确诊断结构：

```text
Vslow tracker继续运行

Kslow=0
→ slow contribution精确为0
```

而不是：

```text
把Vslow状态也冻结
```

---

# 27. 如果想要更强的“硬证明”

diag 应该直接记录：

\[
\Delta V_{ff,slow}
=
K_{slow}(V_{slow}-V_{anchor})
\]

以及：

\[
\Delta V_{ff,fast}
=
K_{fast}(V_{raw}-V_{slow})
\]

当前 V2 已经记录：

```text
Vslow
Vanchor
Kslow
Kfast
```

所以 MATLAB 可以逐点重构。

不需要为了“有一个enable开关”再 Rebuild。

---

# 28. 用户问题七：不能总陷入单变量——最终确实必须整体看

从现在开始，正式对象不是：

```text
Kslow
```

而是完整闭环：

\[
\boxed{
Z_{GFM+network}(s)
\;\times\;
Y_{5GFL}(s)
}
\]

其中五 GFL 的 admittance 同时依赖：

```text
Current PI
Rff/Lff
PWM / delay
two-band VFF
P/f behavior
Q/V support
PLL / common frame
current limiter
outer-loop anti-windup
```

所以最终参数必须在完整系统中求。

---

# 29. Kslow 以后究竟怎么选：不是实机扫，而是离线稳定域设计

这一步必须写清楚。

---

## 29.1 建立单台 GFL dq 输出导纳

目标：

\[
Y_{GFL,i}(s)
=
\frac{\Delta i_{dq}}{\Delta v_{dq}}
\]

完整包括：

```text
Current PI
Rff/Lff
PWM/数字延迟
two-band VFF
island P/f controller
voltage support
frame/synchronization
```

---

## 29.2 聚合五台

\[
Y_{\Sigma}(s)
=
\sum_i Y_{GFL,i}(s)
\]

必要时保留每台网络支路变换。

---

## 29.3 得到 ESS1 + network 等效输出阻抗

\[
Z_{GFM,eq}(s)
\]

包含：

```text
ESS1 voltage loop
current loop
droop
filter
line/network
```

---

## 29.4 看 MIMO return ratio

\[
L(s)
=
Z_{GFM,eq}(s)
Y_{\Sigma}(s)
\]

用：

```text
generalized Nyquist
eigenvalue loci
passivity / dissipativity
```

确定稳定裕度。

---

## 29.5 在离线模型里搜索参数稳定域

不是 RT-LAB run。

离线参数可以搜索：

```text
Kslow
fc_vff
Kmag / Yv
Kf_ESS2
Kf_EV
PV curtail droop
```

每组都计算：

```text
RHP pole?
critical mode damping?
8~25Hz admittance?
0.1~5Hz low-frequency margin?
```

得到：

```text
稳定区域
```

最后取：

```text
区域中间、离边界最远的robust point
```

不是：

```text
波形最好看的一个数字
```

---

# 30. Kslow 当前可以冻结哪些结论

可以冻结：

```text
Kfast island：
第一版 = 0

fc：
第一版保持约1Hz
```

Kslow：

```text
暂不写死0/0.5/1
```

必须由完整岛态闭环的输出导纳/特征值选。

如果理论分析最后发现：

```text
0.55~0.72
```

有鲁棒稳定域，

才选择：

```text
例如稳定域中部值
```

进入一次正式验收。

这和以前：

```text
先试0.5
再试1
```

完全不同。

---

# 31. final current limiter 与 anti-windup

现有 V2：

```text
vector current limiter
```

结构本身是有价值的。

但最终完整控制还必须保证：

```text
final limiter active
```

时：

```text
P/Q outer PI
island P/f controller
voltage support controller
```

不会继续积累不可实现指令。

所以最终设计要明确：

```text
lambda < 1
↓
outer-loop back calculation / freeze / reference tracking
```

否则未来真正触发 Imax 后会再制造新的慢恢复问题。

---

# 32. 当前正确的一主五从总交互

最终目标可以画成：

```text
                     ┌─────────────────────────┐
                     │        ESS1 GFM         │
                     │ theta_GFM / f_GFM / V   │
                     │ residual P/Q balancing  │
                     └────────────┬────────────┘
                                  │
                      common θ/f  │
                                  ▼
 ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
 │     PV1      │     PV2      │     ESS2     │     EV1      │     EV2      │
 │ current-GFL  │ current-GFL  │ current-GFL  │ current-GFL  │ current-GFL  │
 │              │              │              │              │              │
 │ P/f curtail  │ P/f curtail  │ bidir P/f    │ flexible P   │ flexible P   │
 │ local V sup  │ local V sup  │ local V sup  │ local V sup  │ local V sup  │
 └──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┘
        │              │              │              │              │
        └──────────────┴──────────────┴──────────────┴──────────────┘
                                  │
                         current capability
                                  │
                                  ▼
                            AC microgrid bus

secondary island coordinator:
ESS1 residual P / f / SOC / headroom
→ 只重新分配 PV1/PV2/ESS2/EV1/EV2
→ ESS1不作为普通AGC受控资源
```

这才是最终一致架构。

---

# 33. ESS1 的频率到底怎样被五台用

推荐两个层次。

## primary

```text
f_GFM
→ 五台 P/f local response
```

不依赖通信延迟很大的中央 AGC。

如果 ESS1 f 可以通过现有模型本地/跨任务低延迟共享：

```text
直接使用
```

## secondary

```text
f error
+
ESS1 residual P
+
resource margins
```

进入板端 coordinator / island AGC。

---

# 34. ESS1 的 angle 怎样被五台用

planned island 优先：

```text
ESS1 theta_GFM
→ 五GFL dq execution frame
```

但必须：

```text
bumpless blend
```

不能 J1 边沿硬换坐标。

如果现有 OpComm/跨任务资源让公共 angle 代价过大：

第二选择才是：

```text
local PLL
+
coherent hold/free-run
+
bumpless reacquire
```

这一点在最终改模前必须做一次只读结构审计，不能靠猜。

---

# 35. ESS1 的 voltage 怎样被五台用

不要把 ESS1 terminal V 原样当五台绝对 Vref。

应该用：

```text
ESS1全局V target
+
每台local pre-island offset
```

形成各自 local reference。

五台 voltage support 仍使用：

```text
自己的local V measurement
```

这样不会因为线路压降而互相打架。

---

# 36. 最终 AGC / secondary coordinator资源逻辑

## PV

优先：

```text
保持可用功率
```

但：

```text
over-frequency
→ curtail

under-frequency
→ 只有存在headroom才加P
```

## ESS2

```text
最主要双向调节资源
```

## EV

作为充电负荷：

```text
under-frequency
→ 减充电

over-frequency
→ 增充电
```

V2G：

```text
只有实际模型/接口允许时才进入
```

---

# 37. 为什么这样不会和 ESS1 GFM “抢控制权”

因为五台仍然输出：

```text
current
```

ESS1 输出：

```text
voltage waveform / frequency / angle
```

五台的：

```text
P/f
Q/V
```

只是决定：

```text
应该注入/吸收多少current
```

并没有自己建立母线角度。

所以仍然是：

```text
1 GFM + 5 supporting GFL
```

---

# 38. 下一次正式模型修改前，不允许再跑 RT-LAB 的理由

当前 V2 已经告诉我们：

```text
hard Stage2 isolation不稳定
```

历史又告诉我们：

```text
Kslow=1不稳定
Kslow=.5不稳定
```

因此新跑：

```text
Kslow=.6
```

信息价值非常低。

下一步最高信息量动作是：

```text
完整闭环理论 / linearization / admittance设计
```

而不是再跑波形。

---

# 39. 下一次“最终控制 Patch”必须一次包含什么

如果理论设计确认以后确实要再改模型，必须一次性包含：

1. 两频带 VFF：
   - Kfast island
   - Kslow
   - fc
   - 贡献量 diag

2. ESS1 common theta/f island reference path：
   - 如果结构审计证明可行

3. resource-specific P/f controller：
   - PV1/PV2
   - ESS2
   - EV1/EV2

4. local voltage support / virtual admittance

5. current vector limit

6. outer-loop anti-windup back-calculation

7. island secondary dispatch interface

8. exact diagnostics：
   - base P/Q
   - primary P/f contribution
   - voltage support contribution
   - secondary contribution
   - final Iref
   - lambda
   - ESS1 reference

不能再分三次 Rebuild 加功能。

---

# 40. 下一次全面验收 run 应该怎样

## J1前

```text
并网 AGC工作
ESS1完成GFL→GFM
F24/F25准备
五GFL无扰切到 island-ready 控制参数
公共frame准备
```

## J1第一拍

同时：

```text
ESS1 GFM master

五GFL：
final two-band VFF
P/f primary response
local voltage support
current capability
```

不是把它们一个一个开。

## J1后 0~1s

只看：

```text
primary system
```

secondary island AGC 还不抢动作。

## primary健康以后

再：

```text
secondary island AGC ramp in
```

不是恢复 PCC AGC。

## 后续 8~10s

检查：

```text
f restoration
ESS1 residual P是否下降
PV/ESS2/EV是否按资源角色分担
V稳定
Current PI不漂移
current capability有界
```

---

# 41. 一次完整验收如何定义成功

不是单看：

```text
V没掉
```

而是同时：

```text
fast 10~17Hz没有正增长

slow V/f形成稳定

Current PI没有长期单向漂到limit

ESS1没有长期独自承担大residual P

五GFL primary response方向正确

secondary进入后没有重新引发振荡

PV/ESS2/EV行为符合资源约束

Iref <= Imax
outer loops无windup

frame没有因低压长期fallback
```

---

# 42. 如果完整验收仍失败，怎么定位

此时才是有价值的失败。

## A. primary阶段就fast失稳

查：

```text
VFF / current-loop / output-admittance
```

## B. primary不fast，但slow漂

查：

```text
Kslow / P-f droop / Yv / ESS1 Zout
```

## C. primary稳定，secondary一进就坏

直接锁：

```text
island AGC / power recovery
```

## D. 电流limit后才坏

锁：

```text
current priority + anti-windup
```

这个因果树比现在清楚得多。

---

# 43. 当前根因应该怎样表述，避免再反复改口

## 原始快速根因——冻结

> 五台 GFL 面向强网设计的 dynamic terminal-Vdq direct feedforward 使其输出导纳过度电流源化，与 ESS1 GFM 有限输出阻抗形成 10~17 Hz 不稳定交互。

## 慢层根因——冻结为“架构族”，不是某个K

> 在孤岛低频尺度，五台 GFL 必须同时解决 terminal-voltage compensation、功率平衡、frequency/voltage support 和 current capability。仅恢复 slow VFF 会保留近恒功率问题；仅削弱/冻结 P/Q 会让 ESS1 与 Current PI承担过多慢补偿；仅加局部 voltage support 也不能替代有功功率平衡。因此慢层根因是“五 GFL 的强网型功率跟踪/端口行为与单 GFM 孤岛功率平衡要求不匹配”，slow VFF只是其中一个关键路径。

## V2新证据

> V2 证明：在 Kslow=Kfast=0、PQGate=0、AGC退出、Stage3不参与、CurrentCapability未动作的条件下，系统仍发生慢失稳，并伴随五台 Current PI 同步补偿漂移。说明“hard freeze everything”也不是工程解。

这三句话以后不要互相替代。

---

# 44. 当前明确排除 / 降级的分支

继续关闭：

```text
F21
F22 first handover
F24 reference jump
F25首发
predictor
F9 dq map
F12 PWM alias
B1 PLL primary fast root
V1 Vref unit bug
V1 combined limit flag
Stage3 / PQ recovery 作为V2本轮根因
PCC AGC 作为V2本轮根因
CurrentCapability limit作为V2本轮首发
SupportClip作为V2本轮首发
FrameHold作为V2本轮首发
ESS1 ModIndex作为V2本轮首发
```

---

# 45. 当前不能排除但不应单变量盲试的项

```text
slow VFF low-frequency gain / shape
static Rff/Lff + Current PI low-frequency port behavior
ESS1 GFM output impedance
resource-specific island P/f law
local voltage-support admittance
common ESS1 frame vs local PLL
outer-loop saturation anti-windup
```

这些应该进完整模型一起分析。

---

# 46. 文献与 K26 证据如何合并

以后新窗口必须用：

```text
K26实测
决定：
什么路径真的在我们的模型里发生

文献
决定：
合理控制结构有哪些
参数应该用什么理论约束
```

禁止：

```text
看到一篇droop论文
→ 直接照抄
```

也禁止：

```text
K26波形看起来好一点
→ 不做稳定模型
```

---

# 47. 下一窗口唯一正确开始方式

新窗口先继承以下七项：

```text
1. 原fast root已经锁定，不重跑C1/C2/Mode6/Mode7

2. Layer2已经做过 Kslow=1 / .5 和 Kpq=1 / .5
   禁止再物理扫0.4/0.6/0.8

3. V2实现合同全部PASS
   当前失稳不是V1那类代码/单位/连线错误

4. V2 Stage2是过度隔离诊断状态
   不能再当最终岛态控制器

5. 最终必须是：
   ESS1 GFM master
   + 5 grid-supporting current-controlled GFL

6. 原PCC AGC岛态退出
   但要设计新的island secondary dispatch，且不直接调ESS1

7. 下一步不跑RT-LAB
   先完成：
   output-admittance / eigenvalue
   + resource-specific P/f
   + ESS1 theta/f reference
   + VFF parameter design
```

---

# 48. 下一步工作卡

## Step N1：只读结构审计

必须拿齐：

```text
ESS1 theta_GFM / f_GFM / Vout
现在在哪个task
五GFL当前frame consumer准确位置
是否已有跨任务可复用信号
不新增OpComm能否复用
```

目的是决定：

```text
common ESS1 frame是否可低风险实现
```

---

## Step N2：建立五GFL最终 island control block diagram

不是代码。

必须先冻结：

```text
PV1/PV2 P/f law
ESS2 P/f law
EV1/EV2 flexible-load law
voltage support law
current priority
anti-windup
secondary interface
```

---

## Step N3：建立 output-admittance / linearized model

输出：

```text
Y_PV
Y_ESS2
Y_EV
Yaggregate
Z_ESS1_GFM
critical eigenvalues
```

---

## Step N4：离线选择 VFF / support / P-f 参数

冻结：

```text
Kfast
fc
Kslow
Yv / Kmag
Kf values
```

以稳定裕度决定。

---

## Step N5：最后一次完整控制 Patch

一次加入全部最终功能与diagnostics。

---

## Step N6：Rebuild后只跑一次完整 hierarchical acceptance

不是单变量 sweep。

---

# 49. 最终对用户八个问题的压缩回答

## Q1：两频带 VFF 合理吗，参数怎么设？

```text
频带分离合理。
Kfast=0有强实验证据。
fc≈1Hz有Mode7实验证据作为第一分界。
Kslow不能再凭0/.5/1选，必须在完整岛态闭环中用admittance/eigenvalue定。
```

## Q2：slow VFF / Current PI为什么一直回来？

因为：

```text
它不是唯一根因
但它是低频端口行为的一部分。

Kslow=1：
constant-power问题仍在

Kslow=0：
Current PI补偿负担过大

所以最终需要整体控制，不是二选一。
```

## Q3：AGC离网后该不该有？

```text
原PCC AGC：退出

新的island secondary AGC：
需要
但目标改成f/ESS1 residual P/resource margins
且主要调五GFL，不把ESS1当普通受控资源
```

## Q4：是不是已经锁slow VFF？

```text
锁定它是慢层关键参与路径之一。
没有锁定它是唯一根因。
```

## Q5：文献是否需要？

```text
需要，已经定向检索。
主从一GFM+多GFL、PV/ESS island droop、EV flexible load、GFL admittance文献都支持整体架构设计。
```

## Q6：五台离岛应该什么状态？

```text
都保持current-controlled GFL
统一跟随ESS1 theta/f
每类资源有不同P/f响应
都有local voltage support
都有current capability/anti-windup
接受island secondary dispatch
```

## Q7：先设一个slow值全开跑一次？

```text
现在不应该。
当前V2还没有完整resource-specific island controller。
先理论设计；完整控制冻结后再一次全功能验收。
```

## Q8：不能只看单变量，对吗？

```text
对。
最终对象是：
Z_GFM+network × Y_5GFL
而不是一个Kslow。
```

---

# 50. 本交接之后禁止出现的建议

没有新理论/模型证据前，不要再建议：

```text
再试Kslow=1
再试Kslow=.5
试Kslow=.6
Kmag先关了看
Stage3强行打开
把原AGC直接重新打开
先调PLL
先调F25
把ESS2直接改GFM
```

下一步是完整控制设计，不是再做参数骰子。

---

# 51. 外部文献清单（本轮定向检索）

1. Carnielutti, F. et al.  
   **A Master-Slave Model Predictive Control Approach for Microgrids**  
   IEEE Transactions on Power Electronics, 40(1), 540–550, 2025.  
   DOI: `10.1109/TPEL.2024.3464105`

2. **Coordinated control between a grid forming inverter and grid following inverters suppling power in a standalone microgrid**  
   Global Energy Interconnection, 2022.  
   DOI: `10.1016/j.gloei.2022.06.002`

3. **Coordinated control for PV-ESS islanded microgrid without communication**  
   International Journal of Electrical Power & Energy Systems.  
   关键：PV MPPT/frequency droop、PV curtailment、ESS droop、small-signal coefficient design。

4. NREL  
   **Research Roadmap on Grid-Forming Inverters**  
   关键：GFL依赖外部V/f；GFM形成V/f；island GFL需要特定运行条件。

5. NREL  
   **Microgrids For Anyone / communication-less microgrid control**  
   关键：battery forms grid frequency；PV/wind use frequency as common language to adjust power。

6. Wang, J. et al., NREL / IEEE PESGM 2024  
   **Dispatching Grid-Forming Inverters in Grid-Connected and Islanded Mode**  
   关键：grid-connected / island dispatch rule应区分。

7. Tian et al.  
   **Transient Synchronization Stability of an Islanded AC Microgrid Considering Interactions Between Grid-Forming and Grid-Following Converters**  
   IEEE JESTPE, 2023.  
   关键：GFM-GFL island synchronization interaction。

8. Askarian, A., Park, J., Salapaka, S.  
   **Enhanced Grid-Following Inverter: A Unified Control Framework for Stiff and Weak Grids**  
   IEEE TPEL, 2024.  
   DOI: `10.1109/TPEL.2024.3350528`

9. Zhang et al.  
   **Quantitative stability analysis of Grid-Following inverter with Grid-Supporting control and stability enhancement method based on Multi-Voltage feedforward**  
   IJEPES, 2026.  
   关键：grid-supporting control会新增dq coupling，必须从admittance设计。

10. Ma, G. et al.  
    **Wideband Stability Improvement of Grid-Following Inverter Through a Modified Active Damping Scheme**  
    IEEE Transactions on Industrial Electronics, 2026.  
    DOI: `10.1109/TIE.2026.3684189`  
    关键：lowpass voltage feedforward可能改善高频却恶化低频positive admittance。

11. Oh, H.-B. et al.  
    **Passivity-Based Stabilization of LCL-Filtered Grid-Following Inverters for Offshore Wind Farms: A Step-by-Step Design With PCC Voltage Feedforward**  
    IEEE Access, 2026.  
    DOI: `10.1109/ACCESS.2026.3707968`  
    关键：PCC voltage feedforward必须通过passivity/admittance procedure设计，而非单一经验系数。

---

# 52. 最终一句话交接

> **K26_V5 现在已经不是“还不知道哪里坏”，也不是“继续调 slow-VFF 一个参数”。原快速根因已经锁定；V2 又证明极端关闭 dynamic VFF、P/Q recovery、AGC 并不能自动形成正确岛态。当前真正任务是把 ESS1 作为唯一 voltage/frequency/angle master，把 PV1/PV2/ESS2/EV1/EV2 设计成有资源差异化 P/f 响应、local V support、current capability 和 secondary dispatch 的五台 supporting GFL，并在这个完整闭环下用 output-admittance/eigenvalue 反推 two-band VFF 的 Kslow/fc，而不是继续在 RT-LAB 里试 0、0.5、1。理论设计冻结以后，只做一次完整 hierarchical physical acceptance。**
