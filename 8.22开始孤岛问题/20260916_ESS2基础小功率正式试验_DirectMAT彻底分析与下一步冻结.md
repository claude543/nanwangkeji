# 2026-09-16｜ESS2 基础小功率正式试验：DirectMAT 深度分析与根因分层冻结

> 模型：`K26_K50_CLEAN_P1`  
> 本轮：ESS2 BASETEST（基础小功率诊断）  
> 数据：G27 / G29 / G30 DirectMAT 压缩计算结果  
> 试验目标：附加支撑完全隔离后，验证 ESS2 从零功率恢复到固定 `-0.005 pu` 时的真实动态  
> 结论性质：**当前数据已经足以封板“问题发生在哪一层”；若要进一步唯一分离 Power PI 与 current-execution 两个同时放行的子环节，还需一轮很小的正交 A/B 试验。**

---

# 0. 结论先行

本轮已经把问题压缩得非常清楚：

```text
不是：
旧 26 Hz dynamic-VFF 问题
不是：
四路附加支撑重新混入
不是：
Coordinator / Primary / Secondary 接管
不是：
-0.005 pu 这个非零目标本身才开始触发
不是：
CurrentLimit 先触发
不是：
Power PI 积分器持续 windup 发散

而是：

ESS2 已零功率真实并回
↓
14.6574 s：RestoreAlpha 0 → 1
↓
此时 Pref 仍为 0
↓
BASE active-power/current-reference path 真正取得执行权
↓
原本约 0.8~1 Hz 的弱孤岛慢振荡阻尼明显恶化
↓
振幅在 P=0 阶段已经持续增大
↓
19.6775 s 才开始 0 → -0.005 pu 斜坡
↓
随后调制裕度开始周期性触底 / component clipping 参与
↓
系统进入约 0.86 Hz 的大幅、持续、近似有界极限环
```

因此当前核心问题已经从此前的：

> “额外 support 被 Alpha 一起放出来”

进一步压缩为：

> **ESS2 基础有功闭环 / 电流执行路径在有限强度 ESS1-GFM 孤岛中的低频交互稳定性问题。**

更精确地说，`RestoreAlpha` 在当前结构中同时做两件事：

1. 打开 Power Loop 的 P/Q error；
2. 打开 Current Adapter 的最终 current-reference authority。

因此本轮 `14.6574 s` 的一次事件同时改变了两个子环节。现有数据足以证明**问题由这个 BASE path 放行事件触发**，但还不能仅凭这一轮唯一断言：

- 是 Power PI 外环本身给出负阻尼；
- 还是 current-reference execution / inner current control 在弱网下本身存在问题；
- 或两者共同构成。

下一轮最有价值的试验应只拆开这两个同时变化的量，而不是再碰 Stage、support、Coordinator 或继续盲调 PI。

---

# 1. 数据完整性足够支撑当前结论

## G27

```text
0.3999 ~ 55.1587 s
137000 samples
median dt = 0.0004 s
无倒序
无大缺口
```

适合做 ESS2 本地高速因果分析。

## G29

```text
0.4014 ~ 55.1602 s
137000 samples
median dt = 0.0004 s
无大缺口
```

足够确认 S14 / Stage / ownership / command chronology。

## G30

```text
1.0000 ~ 55.4253 s
54000 samples
median dt = 0.001 s
53 个较大间隔
最大间隔约 0.014 s
```

不适合据此做亚毫秒瞬态判断，但对当前约 `0.86 Hz` 的慢振荡、ESS1 GFM 平台状态和 30 s 级趋势分析完全够用。

---

# 2. 正式试验时序确实按设计走完

G29 证明本轮没有被隐藏的上层控制污染。

## S14 substate

```text
0.4014 s   → state10
5.9571 s   → state20
8.4574 s   → state25
12.4572 s  → state30
14.6573 s  → state35
19.6574 s  → state40
52.1575 s  → state45
```

## Restore

```text
12.4573 s：真实 breaker 闭合 / state4
12.6573 s：state5
14.6574 s：state6
14.6574 s：Alpha = 1
```

## 功率命令

```text
14.6574 ~ 19.6775 s：
Alpha = 1
Pref ≈ 0

19.6775 s：
Pref 开始下降

21.6176 s：
到达约 -0.005 pu

21.6176 s 之后：
固定 -0.005 pu 平台
```

这正是本轮最关键的因果分离：

> **我们有约 5 s 的 “Alpha=1 + Pref=0” 独立窗口。**

因此可以判断问题究竟是在“基础路径放行”还是“非零功率目标”后才出现。

---

# 3. 四路附加 support 已经被彻底排除

这是本轮最重要的成功证据之一。

在固定平台：

```text
AllowedSupportMaxAbs = 0
TotalSupportMag      = 0
SupportEnvelope      = 0
```

而后台 raw / unselected support 实际并不小：

```text
RawSupportMaxAbs 平均 ≈ 0.0518 pu
最大 ≈ 0.0871 pu
```

所以：

```text
后台支撑算法仍在算
↓
但 BASETEST selector 的确把它们挡在 common allocation 之前
↓
最终执行 current reference 中没有这些额外支撑
```

这意味着上一轮的“support 跟 Alpha 一起放出”机制已经被正确消除。

因此：

> **当前约 0.86 Hz 问题不能再归因于四路额外 support。**

---

# 4. 非零 -0.005 pu 不是首次触发点

真正的关键事件是：

```text
14.6574 s：Alpha = 1
```

而不是：

```text
19.6775 s：Pref 开始离开 0
```

## Alpha 开放后的第一个 2 s

```text
14.6574 ~ 16.6574 s
Pref mean = 0
Vpu p2p ≈ 0.173
Pmeas p2p ≈ 0.024
```

## 第二个 2 s

```text
16.6574 ~ 18.6574 s
Pref mean = 0
Vpu p2p ≈ 0.262
Pmeas p2p ≈ 0.046
```

## 到 Pref 斜坡刚开始附近

```text
18.6574 ~ 20.6574 s
只有后半段才开始有小负 Pref
Vpu p2p ≈ 0.500
Pmeas p2p ≈ 0.091
```

所以在 `Pref=0` 的前 5 s 中，振荡幅值已经明显增长。

这直接排除：

> “因为 -0.005 pu 这个目标太大，所以才开始振荡”

这种解释。

更准确的结论是：

> **BASE current/power-control authority 被放开以后，慢模态已经开始失去阻尼；-0.005 pu 斜坡只是进一步把已经增长的振荡推入非线性/饱和区。**

---

# 5. 现在不是旧 26 Hz 问题，而是新的约 0.8~0.9 Hz 慢模态

FFT 结果：

## Alpha=1、P≈0 阶段

```text
Vpu dominant ≈ 0.796 Hz
Pmeas dominant ≈ 0.796 Hz
PIntegral dominant ≈ 0.796 Hz
```

20~32 Hz 能量已经几乎可以忽略。

## 固定 -0.005 pu 平台

```text
Vpu dominant ≈ 0.864 Hz
Pmeas dominant ≈ 0.864 Hz
PIntegral dominant ≈ 0.864 Hz
```

而：

```text
20~32 Hz energy fraction
≈ 10^-6 量级
```

所以无需再回头怀疑此前已经解决的：

```text
Stage0
→ dynamic VFF
→ 约26 Hz
```

本轮暴露的是完全不同的慢动态层。

---

# 6. -0.005 pu 平台不是“稳定小功率跟踪”，而是大幅持续极限环

固定平台统计：

```text
Pref mean ≈ -0.00499994 pu
Pmeas mean ≈ -0.005151 pu
```

如果只看平均值，会误以为“跟得很好”。

但瞬时数据完全不是这样：

```text
Pmeas min ≈ -0.06056 pu
Pmeas max ≈ +0.05066 pu
Pmeas p2p ≈ 0.11122 pu

P tracking RMS error ≈ 0.03679 pu
```

目标本身只有：

```text
0.005 pu
```

因此跟踪误差 RMS 约是目标幅值的：

```text
0.03679 / 0.005 ≈ 7.36 倍
```

所以不能把“均值接近目标”当作功率跟踪成功。

---

# 7. 电压也不是收敛，而是持续大幅振荡

固定平台：

```text
Vpu mean ≈ 1.028
min ≈ 0.662
max ≈ 1.292
p2p ≈ 0.630 pu
std ≈ 0.204 pu
```

2 s 窗口显示，在进入平台后：

```text
Vpu p2p 长期约 0.55~0.60 pu
Pmeas p2p 长期约 0.103~0.110 pu
PLL p2p 长期约 0.52~0.58 Hz
```

这些值后面没有继续持续放大，而是维持在相近数量级。

因此动态性质更像：

> **前期振幅增长 → 后期进入大幅、近似有界的非线性极限环**

而不是：

> 无限单调发散。

但这种“有界”绝不等于工程可接受稳定，因为振幅已经非常大，而且进入了调制边界。

---

# 8. Power PI 没有持续 windup，但它明确参与了 0.86 Hz 回路

固定平台：

```text
PIntegral mean ≈ -0.00536
min ≈ -0.02727
max ≈ +0.01496
p2p ≈ 0.04223
long-term slope ≈ 4.9e-7 / s
```

长期 slope 基本为 0。

所以：

> **当前不是“积分器一路越积越大”的 windup 发散。**

但是 PIntegral 与 Vpu / Pmeas 同频：

```text
~0.86 Hz
```

而且从 Alpha 开放的 P=0 阶段开始就同步增长。

这说明：

> **Power PI 是当前慢振荡闭环中的重要动态参与者。**

它是在周期性地产生反向调节，而不是单向累积。

---

# 9. 电流执行出现明显问题，但不是 CurrentLimit 先导致的

固定平台：

```text
|Iref used| mean ≈ 0.0128 pu
|Imeas used| mean ≈ 0.0530 pu

CurrentErrorNorm mean ≈ 0.0548 pu
```

也就是说：

> 实际 dq 电流动态远大于基础 current reference 本身，当前环路并没有表现成“给一个很小的电流参考，实际电流紧紧贴着它”。

但同时：

```text
CurrentLimit = 0 全程
RadiusClip   = 0
PIStateClip  = 0
```

所以不能解释成：

> “先触发 current limit，才导致振荡。”

事实上：

```text
first ModHeadroom loss ≈ 19.9155 s
first ComponentClip   ≈ 19.9355 s
```

都发生在：

```text
14.6574 s Alpha 已开放
19.6775 s Pref 才开始斜坡
```

之后。

因此因果顺序是：

```text
Alpha打开
↓
慢振荡先增长
↓
之后才碰到 modulation/component clipping
↓
clipping 将振荡限制成大幅周期性极限环
```

不是：

```text
clipping
↓
产生振荡
```

---

# 10. 调制饱和是后期“限幅机制”，不是初始触发机制

固定平台：

```text
ModHeadroom = 0 的时间占比约 26.5%
ComponentClip = 1 的时间占比约 14.5%
CurrentLimit = 1 的时间占比 = 0
```

因此后期确实存在明显的电压/调制侧执行边界。

这很好地解释了为什么：

```text
振荡前期越来越大
↓
后期没有无限长大
↓
形成持续大幅极限环
```

也就是说：

> **系统后期的“有界”很可能不是因为线性闭环已经稳定，而是因为非线性执行约束把幅值卡住了。**

---

# 11. 上层 Coordinator / Secondary / handover 已经彻底排除

G29 全程：

```text
OwnerRequest   = 0
HandoverBeta   = 0
ESS2Available  = 0
CorrectionGain = 0
SecondaryEnable= 0
```

并且：

```text
CoordStage = 2
GFLStage   = 2
RestoreStage = 3
```

所以本轮没有：

- Coordinator ownership；
- Primary correction；
- Secondary；
- beta handover；
- 其他上层调节。

因此问题就在 ESS2 本地 BASE path 与 ESS1 GFM 的物理闭环里。

---

# 12. ESS1 GFM 证据：它在“被迫响应”，不是上层参考自己在大幅摆动

根据冻结的 G30 schema：

```text
ch1  = FrefInput_Hz
ch2  = Fout_Hz
ch4  = PLL_Hz
ch8  = P_DroopFeedback_pu
ch9  = Q_DroopFeedback_pu

ch118/119 = Iref_PreSaturation_d/q
ch120/121 = Iref_Final_d/q
ch122/123 = Id/Iq_Meas
ch124/125 = Vconv_d/q
ch126     = Vq_Meas_pu
ch127     = Vq_Ref_pu
ch128     = Vd_Meas_pu
```

固定平台：

## 频率参考侧

```text
FrefInput = 50 Hz，完全固定
Fout p2p ≈ 0.053 Hz
PLL p2p ≈ 0.611 Hz
```

说明 ESS1 的构网频率命令本身没有跟着母线一样大幅摆动。

## 电压参考侧

```text
VqRef p2p ≈ 0.0029 pu
VqMeas p2p ≈ 0.624 pu
VdMeas p2p ≈ 0.649 pu
```

也就是说：

> 构网电压参考几乎不动，但真实母线 dq 电压在大幅摆。

## ESS1 电流闭环

```text
IrefFinal_d mean ≈ -0.2054
IdMeas      mean ≈ -0.2054

IrefFinal_q mean ≈ +0.0394
IqMeas      mean ≈ +0.0397
```

ESS1 自己的 current reference 与 measured current 平均值和动态幅值相对接近。

所以目前没有证据支持：

> “ESS1 自己的电流环先失控，才把 ESS2 带坏。”

反而更符合：

> ESS2 BASE loop 放行后激发岛内慢模态，ESS1 GFM 被迫承担这个振荡功率并努力维持电压。

ESS1 `P_DroopFeedback` 平台 p2p 约：

```text
0.107 pu
```

说明它确实承受了明显的周期性有功摆动。

---

# 13. 目前可以正式排除的原因

本轮后，下面这些不要再反复怀疑：

## 已排除 1：旧 26 Hz dynamic VFF

20~32 Hz 能量几乎消失，本轮主导频率约 0.86 Hz。

## 已排除 2：四路附加 support

Allowed support = 0，而 raw support 明显非零。

## 已排除 3：Coordinator / Primary / Secondary

全程没有接管。

## 已排除 4：-0.005 pu 才是首次触发点

Alpha=1、Pref=0 的 5 s 内振幅已明显增长。

## 已排除 5：CurrentLimit 触发导致振荡

CurrentLimit 全程为 0。

## 已排除 6：Power PI 单向 windup

PIntegral 无长期漂移，表现为同频周期振荡。

## 已排除 7：ESS1 reference 自己大幅振荡

Fref / VqRef 基本固定，ESS1主要是在响应母线异常。

---

# 14. 当前最合理的根因层

当前控制链可简化成：

```text
ESS2 PLL / P measurement
        ↓
Power PI
        ↓
BASE current reference
        ↓
Current Adapter / Current Regulator
        ↓
ESS2 converter
        ↓
弱孤岛母线
        ↓
ESS1 GFM
        ↓
母线电压/频率/功率
        └──────── 回到 ESS2 PLL / P measurement
```

在强网中：

```text
ESS2改变一点电流
→ 母线 V/f 基本不动
```

所以 Power Loop 看起来像在控制一个近似刚性的对象。

在当前只有 ESS1 GFM 的孤岛中：

```text
ESS2改变电流
→ 母线 V/angle/f 会明显变化
→ PLL/Pmeas随之变化
→ Power PI再改电流
→ 反过来继续改变母线
```

于是形成一个新的慢闭环。

当前实验证明：

> **这个慢闭环在 Alpha 放行后阻尼不足，约 0.8~0.9 Hz 模态被持续激发。**

---

# 15. 但还不能仅凭本轮唯一分开 Power PI 与 current-execution

这是当前唯一还需要严谨保留的边界。

因为同一个：

```text
RestoreAlpha 0 → 1
```

同时：

```text
A. 打开 Power Loop 的 error
B. 打开 Current Adapter 的 reference authority
```

所以本轮是：

```text
A + B 同时变化
```

即使当前数据已经非常指向 BASE active-power loop，我们仍不应该直接说：

> “一定就是 Ki=2 太大”

然后开始调 PI。

这会重复以前“没有正交隔离就直接调参”的返工。

---

# 16. 下一轮唯一值得做的正交试验

建议下一轮只做：

## Test A：current authority 开，Power Loop error 仍关

```text
Current Adapter Alpha = 1
Power Loop RestoreAlpha = 0

Pref = 0
附加 support = 0
Coordinator = 0
Secondary = 0
```

含义：

> 让 ESS2 的真实 current controller 接管，但 Power PI 不参与。

如果这时仍出现同样约 0.8~0.9 Hz 增长：

```text
→ 问题进一步落到 current execution / PLL / inner GFL base path
```

如果这时稳定：

```text
→ 再把 Power Loop Alpha 从0→1，Pref仍保持0
```

只要同一慢模态重新增长：

```text
→ Power PI / P-loop weak-grid interaction 得到非常强的 A/B 因果闭环
```

这比现在直接调 Kp/Ki 更干净，也只需要改一个 BASETEST-only alpha selector。

---

# 17. 本轮最终冻结结论

一句话：

> **本轮已经证明四路额外支撑不是当前根因，-0.005 pu 目标也不是首次触发源；ESS2 在真实零功率并回后，只要 RestoreAlpha 打开 BASE active-power/current-reference path，即使 Pref 仍为0，约0.8~0.9 Hz 的弱孤岛慢模态就开始增长，随后功率斜坡把系统推入周期性调制/分量裁剪，最终形成大幅但近似有界的极限环。当前剩下的唯一关键分界，是同一 Alpha 同时打开的“Power PI 外环”和“current-reference execution”两部分，需要用一次最小正交 A/B 试验拆开。**

这轮以后，不再回头重做：

- Stage0/1/2；
- old dynamic VFF；
- 四路 support；
- Coordinator ownership；
- Secondary；
- 保护阈值；
- MAT 记录架构。

下一轮只拆 Alpha 的两个职责。
