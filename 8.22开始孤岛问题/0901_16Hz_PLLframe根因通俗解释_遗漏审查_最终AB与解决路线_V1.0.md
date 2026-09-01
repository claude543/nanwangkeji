# K26_V5｜16 Hz PLL/frame 根因通俗解释、遗漏审查、最终 A/B 与解决路线 V1.0

> 日期：2026-09-01  
> 当前阶段：**观测层根因已经高置信锁定；最终主动因果封板还差一次干净的 A/B。**  
> 当前不应再回头扫 F20/F21/F22/F24/F25、Current PI、Voltage PI、网络参数。  
> 下一步也**不是立即修改模型**，而是先把最终 A/B 所需的执行路径再做一次“精确到 Switch/Mux/Power Control Loop 端口”的只读微审计，然后再做一个可旁路的 A/B 平台。

---

# 0. 先用一句话把现在的问题讲明白

现在完整六机切岛失败的真正问题，不是：

```text
ESS1不会构网
不是F25太慢
不是Current PI先失控
不是PWM能力不够
不是某一条Stubline突然坏了
```

而是：

```text
J1闭合时：
上级强电网像一面“很硬的墙”
五台GFL的PLL即使有一点动态误差，
PCC相角/电压也不会被它们明显推着走。

J1打开以后：
这面“硬墙”消失
↓
ESS1成为唯一GFM
↓
母线不再是理想无限强电压源，
而是具有有限动态输出阻抗
↓
五台GFL仍然各自使用本地PLL追踪PCC相角
↓
PLL发生约16Hz增长的相角跟踪误差
↓
这个错误相角立即进入五台GFL的控制坐标系
并通过电压前馈/电流控制改变五台变流器输出
↓
五台GFL产生聚合动态电流
↓
这些电流又通过ESS1有限输出阻抗改变PCC相角
↓
PCC相角变化再次进入五台PLL
↓
形成正反馈 / 负阻尼闭环
```

最终表现就是：

```text
约16 Hz振荡越来越大
→ PCC先出现相角异常
→ 后续电压幅值大摆动
→ 最终完整六机孤岛失稳
```

---

# 1. 所以“到底是哪一个模块有问题”？

## 1.1 最核心的问题模块族

不是某一个单独 Gain 块坏掉。

当前 Primary initiating mechanism 是五台 GFL 共同拥有的：

```text
Measurements
└─ PLL (3ph) / SRF-PLL
   ├─ wt_PLL / thetaF
   ├─ Freq_PLL
   ├─ VdVq_measPLL
   └─ IdIq_measPLL
```

五台分别位于：

```text
PV1
K26_V5/SS_Slave3/PV1_Control/Measurements

PV2
K26_V5/SS_Slave3/PV2_Control/Measurements

ESS2
K26_V5/SS_Slave2/ESS2_Control/Measurements

EV1
K26_V5/SS_Slave/EV1_Control/Measurements

EV2
K26_V5/SS_Slave/Control System/Measurements
```

其中 EV2 的真实历史控制器名称仍是：

```text
Control System
```

不要写成不存在的 `EV2_Control`。

---

# 2. PLL 的错误动态到底怎样进入实际 PWM？

这是理解当前问题最重要的一部分。

---

## 2.1 第一条执行通道：PLL angle → PWM reference angle

当前已经确认：

```text
Measurements/wt_PLL
Port9
↓
Goto16
tag = thetaF
↓
From38
↓
Switch5 input1
```

Switch5 的三路结构历史和当前审计一致：

```text
input1 = thetaF
       = local PLL angle

input2 = ConnectMode

input3 = wt
       = Droop/GFM angle
```

因此：

```text
ConnectMode = GFL
→ Switch5选择 thetaF

ConnectMode = GFM
→ Switch5选择 Droop wt
```

Switch5 输出：

```text
Switch5/out1
↓
Goto23
tag = wts
```

然后：

```text
From39
tag = wts
↓
Vref Generation/in1
```

而 `Vref Generation` 最终负责把 dq 电压命令和角度变成三相电压参考：

```text
wts
+
VdVq_conv
+
Vdc
↓
Vref Generation
↓
Unit Delay
↓
Vpwm
↓
PWM Generator
```

所以在五台 GFL 中：

> **本地 PLL 的角度不是只用于“测量显示”，它直接决定最终三相 PWM 参考的相位坐标。**

---

# 3. 第二条执行通道：PLL-frame Vd/Vq → Current Regulator → Vconv

这条通道非常关键，也是为什么不能只改 `wt_selected`。

当前五台 GFL 都有：

```text
Measurements/out5
=
VdVq_measPLL
=
VdVqF
```

通过：

```text
Goto12
tag = VdVqF
```

进入顶层多个消费者。

当前审计确认其中包括：

```text
From22
→ Power Control Loop/in2

From25
→ Selector8/in1

From40
→ Switch6/in3

From43
→ Selector12/in1
```

而最终送进 Current Regulator 的不是原始名字 `VdVqF`，而是模式选择后的：

```text
VdVqs
```

真实路径已经确认：

```text
Goto20
tag = VdVqs
← Mux/out1

From26
tag = VdVqs
↓
Current Regulator/in1
```

所以：

> **PLL 不仅通过 angle 影响最终 PWM，相同 PLL frame 下测得的 Vd/Vq 还直接进入 Current Regulator 的电压前馈。**

---

# 4. Current Regulator 的真实控制律现在已经审计清楚

五台 Current Regulator 都是同构的。

输入：

```text
in1 = VdVq_meas
in2 = IdIq_meas
in3 = IdIq_ref
```

电流误差：

```text
IdIq_ref - IdIq_meas
↓
PI regulator with anti-windup
↓
PIdq
```

但是最终：

```text
VdVq_conv
```

不是只有 PI。

真实结构：

```text
PIdq
+
voltage/feedforward dq
↓
Add2
↓
Saturation
↓
VdVq_conv
```

其中 d 轴前馈结构：

```text
Vd_ff
=
Vd_meas
+
Rff * Id_ref
-
Lff * Iq_ref
```

q 轴前馈结构：

```text
Vq_ff
=
Vq_meas
+
Rff * Iq_ref
+
Lff * Id_ref
```

因此：

```text
Vd_conv
≈
PId
+ Vd_meas
+ Rff*Id_ref
- Lff*Iq_ref

Vq_conv
≈
PIq
+ Vq_meas
+ Rff*Iq_ref
+ Lff*Id_ref
```

最后再经过 Saturation。

这解释了 raw MAT 中为什么看到：

```text
Vconv_q
≈
1 × Vq_PLL
+
Current PI contribution
```

不是数据巧合。

这是模型结构本身决定的。

---

# 5. 为什么 Current PI 不是根因，却 Vconv 会和 PLL 几乎同时变化？

因为：

```text
PLL/frame Vq
↓
以近似1倍直接作为 voltage feedforward
↓
Vconv_q
```

中间不需要等待 Current PI 积分。

所以：

```text
PLL异常 +0.7 ms
Vconv也约+0.7~0.9 ms
```

并不代表：

```text
“Current PI比PLL先坏”
```

而是：

> **PLL/frame 的错误量通过前馈直接写进 Vconv。**

真正 Current PI 自身的共同动态晚约：

```text
1.4 ~ 1.6 ms
```

而且在早期 16 Hz 模态中 Current PI 贡献只占较小部分。

所以：

```text
Current PI = follower / execution amplifier
不是 Primary initiator
```

---

# 6. 当前 16 Hz 是怎么形成的？

## 6.1 强网下

可以把 PCC 想成：

```text
非常硬的电压/相角源
```

某一台 GFL PLL 有一点误差：

```text
PLL误差
→ GFL电流稍有变化
```

但：

```text
PCC相角几乎不动
```

所以这个反馈环增益很小。

六机强网可以稳定运行已经反复证明。

---

## 6.2 J1 打开后

J1 打开：

```text
上级电网退出
```

这时 PCC 的“硬度”只来自：

```text
ESS1 GFM
+
其闭环电压/电流控制
+
网络阻抗
```

ESS1 不是理想零阻抗电压源。

所以：

```text
五GFL动态电流变化
→ 会真正推动PCC电压/相角
```

于是形成：

```text
PCC angle
→ five local PLL
→ local frame error
→ Vdq/Iref/Vconv
→ five GFL current
→ ESS1 GFM finite output impedance
→ PCC angle
```

在当前工作点，这个环路约在：

```text
16 Hz
```

阻尼变成负值。

结果：

```text
每一圈不是把振荡削小
而是让它更大
```

这就是“负阻尼”。

---

# 7. 数据证据为什么已经足够把 Primary 压到 PLL/frame？

raw compact 独立分析不是靠一个 FFT。

它重新得到：

```text
真正早期线性增长模态：
约16.5 ±0.5 Hz

典型增长率：
+24 ~ +25 s^-1
```

六支路：

```text
median coherence ≈ 0.998
```

PV1/PV2：

```text
相位差≈0.01°
```

EV1/EV2：

```text
相位差≈0.02°
```

因此是六机公共模态，不是某一台设备坏。

五台 GFL：

```text
PLL/frame异常
≈ J1 +0.7 ms
```

Current PI：

```text
≈ PLL后1.4~1.6 ms
```

PCC可靠相角异常：

```text
≈ J1 +4.3 ms
```

ESS1 持续 Vconv 异常：

```text
≈ J1 +10.7 ms
```

ESS1 Current PI 持续异常：

```text
≈ J1 +30.1 ms
```

最强的一条证据：

```text
Vq_PLL
≈
-0.995 × (PLL angle - PCC physical angle error)

R² ≈ 0.994
```

这说明：

> 五台 PLL 的 16 Hz 量不是“大家同时看见PCC已经振了”，而是 local PLL 对弱 PCC 相角跟踪误差本身在增长。

---

# 8. 所以当前角色应该怎样分类？

## Primary initiator

```text
Five-GFL SRF-PLL / frame dynamics
```

即：

```text
local PLL angle / frequency
+
PLL-derived dq frame
```

---

## Necessary coupling / return path

```text
ESS1 GFM finite output impedance
```

注意：

这不等于：

```text
ESS1 GFM本身设计错误、自己先自激
```

而是：

```text
没有强网以后，
五台GFL动态电流能够通过ESS1 GFM的有限阻抗
反馈成PCC相角变化。
```

这是闭环能够形成的返回路径。

---

## Amplifier / follower

```text
GFL voltage feedforward
GFL Current PI
ESS1 Voltage PI后续动态
ESS1 Current PI
F25后期动态
limiters
```

---

## 当前不支持 Primary

```text
LC resonance
transformer leakage
Stubline
PWM/DC能力
单台设备故障
历史480/530Hz模态
F25 timeout
F25 0.6pu/slew
```

---

# 9. 这是不是“又出现了一个新的问题”？

需要分两层理解。

## 从调试阶段看

是：

> **这是第一层 handover 问题解决后暴露出来的第二层问题。**

第一层：

```text
单ESS1切岛
J1 event current-responsibility handover gap
```

已经被 F25 + R1 解决。

第二层：

```text
1 GFM + 5 GFL
弱网/孤岛多变流器动态稳定性
```

现在才真正暴露出来。

---

## 从模型历史看

不是：

> **它不是 RootDiag、R3、F25 或最近某个 Patch 新引入的。**

证据逻辑：

```text
强网六机
→ 稳定

五GFL隔离 + ESS1切岛 + F25
→ R1稳定

五GFL在线 + 完整六机切岛
→ V25A5/R2/R2-T1/R3持续失稳
```

而 full-six 失稳在 F25 FAST 以前就存在。

所以：

```text
这是原系统里早就存在的第二层弱网耦合问题，
只是以前被第一层handover故障遮住了。
```

---

# 10. 当前模型里你实际可以去哪里看？

以 PV1 为例。

---

## 10.1 PLL

```text
K26_V5
└─ SS_Slave3
   └─ PV1_Control
      └─ Measurements
         └─ PLL (3ph)
```

外部输出：

```text
Measurements/wt_PLL
Port9
```

---

## 10.2 PLL angle 进入实际执行 frame

```text
PV1_Control/Measurements/out9
↓
PV1_Control/Goto16
tag thetaF
↓
PV1_Control/From38
↓
PV1_Control/Switch5/in1
```

Switch5：

```text
GFL → thetaF
GFM → Droop wt
```

输出：

```text
Switch5
↓
Goto23
tag wts
↓
From39
↓
Vref Generation/in1
```

---

## 10.3 PLL-frame Vdq 进入 Current Regulator

```text
PV1_Control/Measurements/out5
↓
Goto12
tag VdVqF
↓
GFL/GFM Vdq selection
↓
Mux
↓
Goto20
tag VdVqs
↓
From26
↓
Current Regulator/in1
```

---

## 10.4 最终 Current Regulator

```text
PV1_Control/Current Regulator
```

关键块：

```text
VdVq_meas
IdIq_meas
IdIq_ref

Sum
PI regulator with anti-windup D

Rtot_pu1
Rtot_pu5
Ltot_pu1
Ltot_pu2

Add1
Add3
Mux
Add2
Saturation
```

---

## 10.5 最终 PWM

```text
Current Regulator/VdVq_conv
↓
Vref Generation
↓
Unit Delay
↓
Vpwm
↓
PWM
```

其它四台路径完全对应：

```text
PV2:
SS_Slave3/PV2_Control

ESS2:
SS_Slave2/ESS2_Control

EV1:
SS_Slave/EV1_Control

EV2:
SS_Slave/Control System
```

---

# 11. 我们有没有遗漏？

截至目前，大故障域已经覆盖得比较完整。

## 已经主动/高置信关闭

```text
1. 实时性：
   Overrun=0

2. 六机规模：
   强网正常

3. ESS1能否GFM：
   能

4. DC/PWM能力：
   不是首发

5. F21：
   已解决

6. F22：
   已解决

7. F24：
   已解决

8. P/Q COMMIT：
   已解决

9. AGC/S7：
   已冻结

10. single-ESS1 IOUT responsibility：
    F25 + R1已解决

11. F25 100ms timeout：
    R2-T1排除

12. F25 slew/magnitude：
    失稳明显早于limiter

13. passive network先发：
    当前raw 16Hz传播顺序不支持

14. Current PI先发：
    不支持

15. ESS1 Current PI先发：
    不支持

16. ESS1 Voltage PI独立自激：
    不支持

17. 单台GFL局部故障：
    六支路+twin symmetry不支持
```

所以不是只盯着一个方向猜。

---

# 12. 但现在还有两个“必须诚实保留”的边界

## 12.1 还没有定量拆开：

```text
负阻尼有多少来自 Y_GFL_PLL
有多少来自 Z_GFM
```

当前已经够判断：

```text
PLL/frame = Primary initiating mechanism
GFM output impedance = necessary return path
```

但没有足够端口辨识信号直接给出：

```text
完整2×2 dq impedance矩阵
精确Nyquist loop gain
```

因此现在不要写成：

```text
“|Z*Y|已经被直接测得严格等于1、相角严格180°”
```

那是机理解释，不是直接阻抗测量。

这不妨碍当前根因定位。

---

## 12.2 最终 A/B 的执行隔离路径还没有全部审计闭合

当前 PRE-A/B audit 已经确认：

```text
PLL angle path
Current Regulator equation
VdVqF进入多个执行消费者
五台控制器高度同构
```

但是当前 audit 有一个明显脚本局限：

```text
Section 4 TOP-LEVEL SELECTOR/SWITCH MAP
输出为空

Section 8 explicit alias consumer
输出为空

fingerprint还错误显示 topSwitch=0
```

而我们明明已经从 exact path 看到了：

```text
Switch5
Switch6
Goto/From
```

所以：

> **不能直接用这份V1 audit就开始Patch。**

不是根因方向不对。

而是：

> 最终 A/B 前必须把 Switch1/Switch6/Mux/Mux1/Power Control Loop 的所有 exact 输入再用“按名字直接定位”的只读审计打印清楚。

这是当前唯一真正需要补的模型结构证据。

---

# 13. 下一步是不是要修改模型？

**还差一步只读审计，然后才修改。**

正确顺序：

```text
现在
↓
PRE-A/B focused audit V2
只读
↓
确认完整PLL-derived actuation map
↓
设计可旁路A/B platform
↓
备份
↓
Patch
↓
一次Build
```

不能：

```text
现在马上手动改Switch5
```

---

# 14. 为什么不能只改 Switch5 的 PLL angle？

因为 Current Regulator 还有：

```text
VdVqs
```

而 GFL 下它来自 PLL-frame 的：

```text
VdVqF
```

另外：

```text
Power Control Loop/in2
```

也直接吃：

```text
VdVqF
```

因此如果只做：

```text
wt_selected
PLL → test angle
```

而仍然：

```text
VdVqF
=
local PLL frame
```

那么会产生：

```text
PWM angle使用test frame
但Current Regulator voltage feedforward仍用PLL frame
Power Control Loop也仍用PLL frame
```

这叫：

```text
frame inconsistency
```

会创造一个“人工新问题”。

这种 A/B 不干净。

---

# 15. 干净 A/B 真正应该隔离的是什么？

真正应该隔离的是：

> **local PLL 对 GFL 执行 frame 的动态反馈**

而不是“让 PLL 块停止存在”。

B 组中：

```text
PLL仍正常运行
PLL raw signals仍记录
```

但执行控制暂时不听 local PLL 的动态 angle。

需要形成一个一致的：

```text
TEST FRAME
```

然后至少让这些执行量全部使用同一个 TEST FRAME：

```text
1. PWM / Vref Generation angle

2. GFL Vd/Vq selected measurement

3. GFL Id/Iq selected measurement

4. Power Control Loop使用的Vd/Vq

5. Current Regulator使用的Vd/Vq和Id/Iq

6. 与这些量同坐标系的Id/Iq reference
```

不能只切一个角度。

---

# 16. TEST FRAME 应该是什么？

最安全的诊断方式不是：

```text
把角度冻结不动
```

那样 dq 坐标会停止旋转，肯定错误。

应是：

```text
J1前/AB启用瞬间
捕获每台GFL自己的：

theta_PLL_pre
freq_PLL_pre
↓
之后短时间：
theta_test
=
theta_pre + ∫ 2π f_hold dt
```

也就是：

> **保留当前相位，继续按接近50Hz平滑旋转，但不再让J1后的 local PLL angle error回写执行控制。**

优势：

```text
1. bumpless
   启用瞬间theta_test = theta_PLL

2. 不需要新增跨SS通信

3. 每台保留自己的pre-J1相位偏置

4. PLL本身继续运行、继续记录

5. 只切断“PLL动态反馈→执行frame”
```

---

# 17. 为什么不直接用 ESS1 GFM angle？

理论上很合理：

```text
五GFL全部临时跟随ESS1公共GFM角
```

但当前平台有：

```text
SS_Slave
SS_Slave2
SS_Slave3
```

ESS1 angle 在 SS_Slave2。

要实时送到：

```text
SS_Slave
SS_Slave3
```

可能需要：

```text
新增/扩展OpComm
```

这会：

```text
增加任务间通信
增加延时
引入新的实验变量
```

所以不适合作为第一因果 A/B。

后续正式 solution 可以再考虑 common-GFM reference。

第一轮 causal A/B 优先：

```text
local bumpless free-running test frame
```

---

# 18. A/B 到底要证明什么？

## A 组

```text
AB_ENABLE = 0
```

数学上完全走现在的原路径：

```text
local PLL
→ local GFL frame
```

它必须复现：

```text
约16 Hz growing mode
full-six failure
```

这证明新 Patch 在关闭状态没有污染 baseline。

---

## B 组

```text
AB_ENABLE = 1
```

在 J1 前几毫秒：

```text
每台本地capture theta_PLL/f_PLL
↓
切换到test frame
↓
确认强网下没有扰动
↓
J1 OPEN
```

J1 后：

```text
PLL继续运行、继续产生自然误差
但它不再驱动五台GFL执行frame
```

其它：

```text
Current PI不改
Power command不改
F25不改
ESS1不改
plant不改
J1不改
```

---

# 19. B 组如果怎样，才算根因真正封板？

最强判据：

```text
A：
16Hz sigma > 0
系统失稳

B：
16Hz sigma明显下降并≤0
或16Hz模态消失
系统不再沿原轨迹失稳
```

同时：

```text
PLL raw自身仍能看到PCC扰动
```

但：

```text
执行frame不再跟随它增长
```

那么可以正式写：

> **local GFL PLL/frame feedback 是 full-six planned-islanding 的主动根因执行环节。**

这是因果干预，而不只是相关性。

---

# 20. 我们现在有没有把握“能解决”？

有较高把握。

原因不是：

```text
“PLL问题一般都能调”
```

而是：

```text
强网六机稳定
+
单ESS1孤岛稳定
+
只有1GFM+5GFL弱网闭环失败
+
raw数据已经看到PLL/frame先发
+
Current PI/ESS1 PI/passive/F25均不先发
```

这说明系统不是：

```text
物理上根本无解
```

而是：

```text
控制阻尼/同步参考管理问题
```

解决空间明确存在。

---

# 21. 但是现在要不要“一次修改最终解决方案，Build一次就结束”？

不建议直接把“最终永久方案”写死。

原因：

如果现在同时：

```text
改PLL bandwidth
+
加hold
+
加common angle
+
改feedforward
+
加recovery
```

即使系统稳定：

```text
也不知道究竟哪一项真正解决了根因
```

以后论文/项目也无法形成干净因果链。

而如果失败：

```text
也不知道是根因判断错
还是新方案自己引入frame mismatch
```

---

# 22. 最合理的折中：一次 Build 做一个“三模式平台”

这是我当前更推荐的方向。

不是：

```text
Build一次只跑一个实验
```

也不是：

```text
现在直接把永久方案写死
```

而是一次 Patch 做成：

```text
MODE 0 = BASELINE
         原PLL路径
         必须数学透明

MODE 1 = CAUSAL ISOLATION
         local bumpless test frame
         用于最终A/B封板

MODE 2 = CANDIDATE RECOVERY
         在MODE1稳定后
         允许平滑重新引入local PLL
         或进入候选弱网PLL策略
```

然后只 Build 一次。

---

# 23. 同一次 Build 后的试验顺序

## Test A

```text
MODE0
```

目标：

```text
必须复现R3
```

否则：

```text
Patch污染baseline
整轮无效
```

---

## Test B

```text
MODE1
```

目标：

```text
切断local PLL dynamic frame feedback
```

若：

```text
16Hz消失/衰减
```

根因主动封板。

---

## Test C（只有B通过才做）

```text
MODE2
```

目标：

```text
验证“hold/isolation后如何正常长期运行和恢复PLL”
```

如果 MODE2 在同一 Build 已设计正确：

> 有机会一次 Build 就从因果验证推进到候选解决方案。

---

# 24. 为什么 MODE2 不能提前当最终方案？

因为最终工程方案还有这些约束：

```text
长期频率漂移
PLL重新接管是否bumpless
不同pre-island工作点
故障/电压骤变
五台设备相位一致性
F25 state4→5→6
J1重合闸/恢复
CHIL实时通信
```

所以 MODE2 即使第一次稳定：

```text
只是 candidate solution
```

最终还要：

```text
多工作点
重复性
Overrun=0
```

才正式冻结。

---

# 25. 修改模型可能引入哪些新问题？

必须提前防。

---

## 风险1：frame mismatch

最危险。

不能出现：

```text
angle = test frame
但Vdq/Idq = PLL frame
```

或者：

```text
Iref在frame A
Imeas在frame B
```

所以 A/B 必须成套切换。

---

## 风险2：启用瞬间 angle jump

不能：

```text
突然切50Hz固定角
```

必须：

```text
theta_test(t_enable)
=
theta_PLL(t_enable)
```

bumpless。

---

## 风险3：frequency mismatch造成短期phase drift

如果：

```text
f_hold
≠
actual island frequency
```

100ms后会累积相角误差。

所以 MODE1 是短时诊断。

不能直接把它当永久方案。

---

## 风险4：Power Control Loop frame不一致

Current Regulator之外：

```text
Power Control Loop/in2
```

也吃 `VdVqF`。

如果漏掉：

```text
PLL仍通过Iref路径影响执行
```

A/B不完整。

所以 focused audit V2 必须把这个路径完整打印。

---

## 风险5：Vref Generation固定phase补偿

历史模型存在：

```text
-pi/6
+
Ts*Fnom*2π
```

相位补偿。

不能在新 test frame 下重复补偿或漏补偿。

---

## 风险6：五台设备不完全同构

当前 fingerprint/历史结构都支持五台高度同构。

但最终 patch 前仍需要 exact path assert。

---

## 风险7：增加跨任务通信

第一轮 A/B 不应使用需要新增 OpComm 的 ESS1 common angle。

优先 local test frame。

---

## 风险8：诊断平台实时负担

RootDiag 已经 Overrun=0。

A/B 新增的 local angle manager + abc/dq transform 若太复杂仍需 Build 后重新证明：

```text
Overrun=0
```

---

## 风险9：Patch关闭时不透明

MODE0 必须做到：

```text
旧信号原线
→ exact bypass
```

不能让新滤波器即使“gain=1”仍产生额外delay。

---

# 26. 当前真正下一步

不是改模型。

是：

# **做一次 Focused PRE-A/B Audit V2。**

只读。

它只需要把以下 exact path 打印完整：

```text
Switch5
Switch1
Switch6
Switch7

Mux
Mux1

From22
From24
From25
From26
From27
From28
From38
From39
From40
From43
From47

Power Control Loop所有Inport

Vref Generation所有Inport

Measurements的：
VdVqF
IdIqF
wt_PLL
Freq_PLL

selected：
VdVqs
IdIqs
IdIq_refs
wts
```

并回答：

```text
1. GFL mode下每一个 selected signal到底从哪里来
2. PLL derived signal到底还有哪些actuation consumers
3. Power Control Loop的frame输入到底有哪些
4. clean TEST FRAME要替换哪些节点
5. 哪些诊断支路必须保持raw PLL不变
```

---

# 27. 为什么这个方向现在是正确方向，而不是“又一次试试看”？

因为路线已经从：

```text
现象
→ 系统层
→ 子机制
→ 真实模型执行路径
→ 因果干预
```

逐层压缩。

当前不是：

```text
试一下PLL
```

而是：

```text
raw数据：
PLL/frame首先增长
↓
模型结构：
PLL直接驱动angle + Vdq feedforward
↓
下一步：
只阻断这条已被数据指向的反馈通道
↓
观察16Hz增长率
```

这是一个明确可证伪的因果实验。

---

# 28. 最终路线图

```text
[已完成]
F21/F22/F24/F25第一层问题
↓
[已完成]
R1 single-ESS1稳定
↓
[已完成]
R2/R2-T1排除timeout/limiter
↓
[已完成]
R3五GFL高速RootDiag
↓
[已完成]
raw MAT重分析
锁16Hz + PLL/frame Primary
↓
[已完成大部分]
PRE-A/B V1结构审计
↓
[下一步]
Focused PRE-A/B V2
补齐所有frame consumers
↓
[之后]
F26/F27类 PLL-FRAME A/B PLATFORM
MODE0/1/2
↓
Build一次
↓
MODE0 baseline
↓
MODE1 causal isolation
↓
若16Hz消失：
Primary root正式封板
↓
MODE2 candidate recovery
↓
多工作点 + repeatability + Overrun=0
↓
最终solution冻结
```

---

# 29. 当前可以正式冻结的结论

> **当前 full-six planned-islanding 的第二层失稳不是新 Patch 引入的错误，而是原系统在强网移除后暴露出的多变流器弱网动态稳定问题。真正早期增长模态约为 16 Hz。五台 GFL 的本地 SRF-PLL 在 J1 后首先产生共同增长的相角/frame误差；该误差直接进入 `Switch5→wts→Vref Generation→PWM` 的角度执行路径，同时 PLL-frame `VdVqF` 经模式选择进入 `VdVqs→Current Regulator`，并作为单位增益电压前馈直接进入 `VdVq_conv`；`VdVqF` 还进入 Power Control Loop，从而进一步影响电流参考。五台 GFL 因此形成负阻尼聚合动态导纳；这些动态电流经 ESS1 有限 GFM 输出阻抗返回到 PCC 相角并再次进入五台 PLL，闭合约16 Hz正反馈。观测层 Primary initiating mechanism 已高置信锁为 five-GFL PLL/frame dynamics；ESS1 GFM output impedance 是必要耦合/返回路径；Current PI、ESS1 PI、F25、被动网络与限幅均不支持作为首发根因。最终还差一次干净、frame-consistent 的 PLL/frame isolation A/B 完成主动因果封板。**
