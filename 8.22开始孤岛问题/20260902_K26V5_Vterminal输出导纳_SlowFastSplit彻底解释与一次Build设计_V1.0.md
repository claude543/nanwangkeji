# K26_V5｜Vterminal、输出导纳、slow/fast split 与下一次改模的彻底解释 + 审计设计冻结 V1.0

> 日期：2026-09-02  
> 目的：把当前根因从“名词”变成可以在 Simulink 图里逐线定位、可以用物理直觉理解、可以据此设计下一次一次性 Build 的工程方案。  
> 结论边界：**根因作用点已经有很强的主动因果证据；slow/fast split 是当前最小、最直接、证据最匹配的第一工程修复结构，但 `fc=1 Hz` 等具体参数还不是“最终理论最优值”，必须通过工程验证与后续阻抗/导纳裕度确定。**

---

# 1. `Vterminal` 到底是什么？

## 1.1 它不是模型里一个叫 Vterminal 的模块

`Vterminal` 是我为了讲控制原理使用的通用符号：

```text
Vterminal = converter terminal voltage
          = 变流器交流端口处“它自己看到的电压”
```

在我们的模型中，对五台 GFL，它具体落实为：

```text
本机交流电压测量
↓
Measurements
↓
dq变换
↓
VdVq_meas
↓
[VdVqs]
↓
Current Regulator / in1
```

所以以后看到我写：

```text
Vterminal
```

你应该在脑中立即替换成：

```text
本台GFL自己测到的交流端口电压
→ 变成Vd、Vq
→ 送入Current Regulator
```

它**不是**：

```text
PCC电压的别名
ESS1 Vref
上级电网电压源
```

每台 GFL 都有自己的 local terminal measurement（本地端口电压测量）。

具体物理测点到底位于该设备滤波器/变压器的哪一侧，下一轮只读审计会沿 `Vabc → Measurements → VdVqs` 把真实源节点打印出来；在没有读取当前 post-Mode6 模型前，不靠截图擅自把它命名成某个特定一次/二次侧节点。

---

# 2. `+Vterminal` 到底什么时候“主动加入”？

答案：

> **一直都在加。每一个控制采样周期都加。不是 J1 打开以后才加。**

你的第三张图已经直接画出来了。

Current Regulator 输入：

```text
in1 = VdVq_meas
in2 = IdIq_meas
in3 = IdIq_ref
```

`VdVq_meas` 经 Demux 拆成：

```text
Vd_meas
Vq_meas
```

---

## 2.1 d轴

第三张图上方 Feedforward：

```text
                         ┌── + Vd_meas
                         │
Id_ref ── Rff ───────────┼── + Rff·Id_ref
                         │
Iq_ref ── Lff ───────────┴── - Lff·Iq_ref
                         ↓
                  Feedforward_d
```

因此：

```text
FF_d
=
Vd_meas
+
Rff·Id_ref
-
Lff·Iq_ref
```

根因试验真正切断过的是：

```text
+ Vd_meas
```

---

## 2.2 q轴

下方 Feedforward：

```text
                         ┌── + Vq_meas
                         │
Iq_ref ── Rff ───────────┼── + Rff·Iq_ref
                         │
Id_ref ── Lff ───────────┴── + Lff·Id_ref
                         ↓
                  Feedforward_q
```

因此：

```text
FF_q
=
Vq_meas
+
Rff·Iq_ref
+
Lff·Id_ref
```

根因试验真正切断过的是：

```text
+ Vq_meas
```

最后：

```text
Current PI
+
Feedforward
↓
Saturation
↓
VdVq_conv
↓
PWM
↓
变流器
```

所以“Current Regulator 主动加入 +Vterminal”的准确含义就是：

> **每个控制周期，把当前测到的 `Vd_meas/Vq_meas` 直接以正号加进最终的变流器电压指令。**

不是一个隐藏功能；就是你第三张图那两根“不经过 Rff/Lff Gain、直接进入 Feedforward 求和器 `+` 端”的线。

---

# 3. 为什么正常的电流控制会故意加 `+Vterminal`？

先只看一相/一个dq轴的物理。

变流器和交流母线之间有电感。

电感电流变化粗略满足：

```text
L di/dt
=
Vconv - Vterminal - R i
```

通俗理解：

```text
Vconv      = 变流器“推”的电压
Vterminal  = 外部母线“顶回来”的电压
差值        = 真正压在电感上的推动力
```

像两个人隔着一个弹簧/阻尼器推一辆车：

```text
变流器向右推
母线向左顶
两边差多少
决定电流怎么变
```

---

## 3.1 如果不做电压前馈

假设你希望电流保持 1 pu。

突然外部母线电压升高：

```text
Vterminal ↑
```

物理式里：

```text
Vconv - Vterminal
```

变小。

所以即使你的电流指令没变：

```text
电流也会被母线电压扰动一下
```

PI 必须看到电流误差后再纠正。

---

## 3.2 加 `+Vterminal` 的初衷

控制器提前知道母线电压升了多少，于是：

```text
Vterminal ↑ 0.1
→ Vconv指令也提前 ↑ 0.1
```

物理对象中：

```text
+0.1 Vconv
-
0.1 Vterminal
≈ 0
```

外部电压扰动对电流的影响就被抵消了。

所以并网电流控制里：

```text
+Vterminal feedforward
```

本身并不是“错误设计”。

它的目的非常合理：

> **让电流更少受电网电压扰动影响，更忠实地跟着 Iref。**

---

# 4. “五台 GFL 被过度理想电流源化”到底是什么意思？

先理解“理想电流源”。

一个完全理想的电流源会说：

```text
你外面的电压是多少，我不管。
我答应输出10A，就永远给10A。
```

即：

```text
terminal voltage变化
↓
current几乎不变化
```

这在**强网**里非常舒服。

因为强网自己负责：

```text
电压
频率
相角
```

GFL只负责：

```text
我要送多少P/Q
→ 对应送多少电流
```

---

# 5. 为什么孤岛以后“太像理想电流源”反而不好？

想象六个人站在一个漂浮平台上。

## 并网时

平台被一根巨大钢柱固定在地面：

```text
强网 = 巨大钢柱
```

五台 GFL 可以闭着眼睛只负责：

```text
按照自己的电流命令推
```

因为平台位置和角度主要由钢柱固定。

---

## J1打开后

钢柱突然撤掉。

现在平台只剩：

```text
ESS1 GFM
```

作为主支撑。

另外五台 GFL 仍然说：

```text
“平台怎么晃我不管，
我只保证自己的推力/电流。”
```

这就危险了。

因为现在平台电压和角度不是外界给定，而是六台设备共同作用的结果。

---

# 6. output admittance（输出导纳）怎么用通俗方式理解？

先不管数学。

输出导纳可以理解成：

> **“当我端口电压变化一点时，我的输出电流会自然改变多少、以什么方向改变。”**

形式上：

```text
Δi
≈
Yout · Δv
```

如果一个设备像完美理想电流源：

```text
Δv很大
Δi仍≈0
```

那么：

```text
Yout ≈ 0
```

---

# 7. 为什么需要“适当的输出导纳/被动阻尼”？

想象汽车悬架。

## 没有减震器

车身向下一沉：

```text
悬架不根据运动产生反作用
```

就很容易继续摆。

## 有被动阻尼

车身向下运动：

```text
减震器立即产生反方向作用
```

把能量耗掉。

电气系统也类似。

当孤岛母线电压/相角有扰动：

```text
bus voltage/angle perturbation
```

如果 GFL 的电流能以恰当方向发生一些变化：

```text
Δv
→ Δi
```

这部分电流响应就可以帮助：

```text
支撑母线
耗散振荡能量
增加阻尼
```

这就是“输出导纳/被动性”在这里的直观意义。

---

# 8. `+Vterminal` 为什么会把这种自然响应削弱？

再次看：

```text
L di/dt
=
Vconv - Vterminal - Ri
```

如果母线电压突然下降：

```text
Vterminal ↓
```

在物理对象里，`-Vterminal` 会改变电感两端电压。

所以电流本来自然会响应。

但是控制器同步做：

```text
Vterminal ↓
→ Vconv也因为 +Vterminal feedforward 同样 ↓
```

于是：

```text
Vconv下降
-
Vterminal下降
```

两者互相抵消。

结果：

> **母线电压虽然变化了，但 GFL 电流对这次变化变得非常不敏感。**

这就是：

```text
GFL更像理想电流源
Yout变小/被重塑
```

---

# 9. 为什么不仅仅是“没有阻尼”，还可能变成负阻尼？

现实数字控制不是理想瞬时数学运算。

路径里还有：

```text
Measurement filter
100 us采样
Current PI
计算延迟
PWM
converter/filter
network
```

所以理论上的：

```text
+Vterminal
```

和物理对象中的：

```text
-Vterminal
```

不可能在所有频率上“瞬时、完美、零相位”抵消。

不同频率下会有：

```text
幅值差
相位差
```

当相位组合不合适时，本来应该：

```text
反着振荡去吸能
```

的电流，可能变成：

```text
顺着振荡继续推
```

就像减震器装反：

```text
车身向下
它反而继续向下推
```

这就是 negative damping（负阻尼）的直观含义。

五台 GFL 同类控制并联：

```text
一个有问题的动态导纳
× 5
```

再去面对一个：

```text
ESS1 GFM finite output impedance
```

问题就会被聚合放大。

---

# 10. ESS1 GFM 的 finite output impedance（有限输出阻抗）又是什么意思？

GFM 不是一台真正无限容量、零阻抗的理想电压源。

它内部有：

```text
Voltage loop
Current loop
PWM
filter
transformer/network
current/voltage limits
digital delay
```

所以即使 ESS1 命令：

```text
“我要1 pu、50 Hz”
```

它也不能像无限大的国家电网一样：

```text
无论另外五台怎么折腾，我都把母线绝对钉死。
```

它表现为一个有动态的：

```text
Zout_gfm
```

即：

```text
电流变化
→ 它的端口电压会有一定变化
```

因此孤岛稳定不是只看 ESS1：

```text
ESS1 Zout
×
五台GFL聚合 Yout
×
network
```

三者共同决定。

---

# 11. 为什么我们现在能说这不是“想象出来的理论”？

因为 D/Q 四角因果试验已经闭合：

```text
D ON / Q ON
→ ~17 Hz positive growth

D ON / Q OFF
→ 原17Hz基本消失
→ d轴幅值塌陷

D OFF / Q ON
→ 新~10.62Hz
→ sigma约+69/s q轴正增长

D OFF / Q OFF
→ C1快速失稳被打断
```

而且单轴保留时：

```text
D-only：
Vd → Vconv_d
近乎1:1

Q-only：
Vq → Vconv_q
共同模态贡献约89~97%
```

所以理论解释是在解释已经观察到的主动因果事实，不是反过来凭理论猜结果。

---

# 12. slow/fast split（慢快分离）究竟是什么？

不要先把它想成“又加一个滤波器”。

先想成把同一个 Vterminal 拆成两部分：

```text
Vraw
=
慢变化
+
快变化
```

例如母线电压：

```text
从1.000 pu
经过0.5秒慢慢变成0.995 pu
```

这是：

```text
slow
```

而：

```text
10.6 Hz振荡
17 Hz振荡
突然快速摆动
```

属于：

```text
fast
```

我们真正想做的是：

```text
慢变化：
仍然允许进入原来的 +Vterminal feedforward

快速危险变化：
不再100%直接进入
```

---

# 13. 数学结构

令：

```text
Vslow = SlowTracker(Vraw)
Vfast = Vraw - Vslow
```

然后：

```text
Vff
=
Vslow
+
Kfast · Vfast
```

等价：

```text
Vff
=
Vslow
+
Kfast · (Vraw - Vslow)
```

---

# 14. Kfast 是干什么的？

`Kfast` 就是：

> **“快速部分还允许保留多少直接前馈？”**

## Kfast = 1

```text
Vff
=
Vslow + (Vraw-Vslow)
=
Vraw
```

这就是现在原始控制。

100% fast feedforward。

---

## Kfast = 0

```text
Vff
=
Vslow
```

快速部分完全不直接前馈。

但注意：

```text
Vslow仍在动
```

所以不是 HOLD。

---

## Kfast = 0.2

```text
慢部分100%保留
快部分只保留20%
```

---

# 15. fc 是干什么的？

`fc` 决定：

> **多慢算“慢”，多快开始算“快”。**

SlowTracker 第一版可用一阶低通：

```text
Hslow(s)
=
1 / (1 + s/(2πfc))
```

如果：

```text
fc = 1 Hz
```

则非常慢的：

```text
0 Hz/DC
0.1 Hz
0.5 Hz
```

基本会被认为是 slow。

而：

```text
10.6 Hz
17 Hz
```

会主要被认为是 fast。

当 Kfast=0 时，约：

```text
10.6 Hz剩余幅值 ≈ 9.4%
17 Hz剩余幅值   ≈ 5.9%
```

所以 `fc=1 Hz` 不是拍脑袋来的。

它来自我们已经测到的最低危险快速模态：

```text
10.6 Hz
```

若第一轮希望把 10.6 Hz direct feedforward 压到约10%以下：

```text
fc ≲ 1 Hz
```

正好是一个有依据的保守起点。

---

# 16. slew 是干什么的？

注意：

```text
fc
```

控制的是**电压信号的慢快分离**。

而：

```text
slew
```

控制的是 **Kfast 从1变到0时，不要瞬间跳变**。

假设：

```text
8.1894 s
```

开始准备切岛。

如果一个采样周期内：

```text
Kfast: 1 → 0
```

虽然理论上可以，但这个控制结构本身发生了突然变化。

为了不制造新的 step disturbance（阶跃扰动），让：

```text
Kfast_eff
```

例如在：

```text
约10 ms
```

内：

```text
1 → 0
```

平滑变化。

我们已有约：

```text
19.9 ms
```

J1前干预窗口。

所以10ms并非随机：

```text
前10ms：
完成shaper接管

后约10ms：
强网下观察是否无扰稳定

然后J1打开
```

---

# 17. 为什么还需要“尝试不同数字”？这是不是又在调参碰运气？

要区分两个阶段。

## 阶段A：根因验证

已经完成。

我们不再用参数扫描寻找根因。

根因作用点已经由 B1/C1/C2/C1-Q/Mode6 主动因果试验锁定。

---

## 阶段B：工程控制器设计

任何真正的控制器都必须有参数：

```text
PI有Kp/Ki
滤波器有fc
虚拟阻抗有R/L
droop有斜率
```

工程问题不是：

```text
“能不能完全不要参数”
```

而是：

```text
参数能否根据物理目标和稳定裕度设计
而不是盲扫
```

我们这里：

### fc初值

由：

```text
最低危险模态≈10.6Hz
+
希望direct fast feedforward首轮压到<10%
```

推出：

```text
fc≈1Hz
```

### Kfast初值

第一轮不是为了性能最优，而是为了验证：

> **“只恢复慢跟踪、去掉危险快速直接前馈，能否同时解决三类快速失稳且消除C1 HOLD副作用？”**

所以取最干净的：

```text
Kfast=0
```

### slew初值

由：

```text
19.9ms pre-J1 window
```

推一个：

```text
约10ms完成
```

的保守无扰切换。

这不是随机三个数字。

---

# 18. 后续为什么可能还要改 fc / Kfast？

如果第一轮：

```text
稳定
+
没有slow-slip
```

根因→修复已经闭环。

此时再提高：

```text
fc
或 Kfast
```

不是继续找根因，而是：

> **在稳定已经保证的前提下，尽量恢复原来并网电流解耦性能。**

这叫 performance tuning（性能整定）。

最终数值应该由：

```text
稳定裕度
+
动态性能
+
阻抗/导纳分析
```

共同决定，而不是“哪个波形看起来顺眼”。

---

# 19. slow/fast split 是不是我全面考虑后认为的“最佳方案”？

更准确的结论：

> **它是当前证据下最优先、最小侵入、可逆、最容易形成因果闭环的第一工程修复方案。**

我不会在还没做工程验证前声称它已经是“数学上的全球最优控制器”。

我们比较过几类方向。

---

## A. 永久删掉/永久HOLD Vd/Vq

不选。

原因：

```text
C1已证明会产生slow mismatch/slow-slip风险
```

---

## B. 只修d或只修q

不选。

原因：

```text
C1-Q
Mode6
```

已经双双否决。

---

## C. 固定10～17Hz notch

不作为第一方案。

原因：

```text
模式会迁移：
17Hz → 10.6Hz
```

追固定频率不等于修架构。

---

## D. 直接调Current PI

不作为第一方案。

没有“PI是必要根因”的主动因果证据。

---

## E. 先改Rff/Lff

不作为第一方案。

C2已经说明动态Iref路径不是必要根因；R/L reference feedforward 不是当前最直接根路径。

---

## F. virtual impedance / active damping

是合理的第二层方案，而且理论上更一般。

但它：

```text
修改量更大
参数更多
影响电流控制更多
```

而我们已经知道最直接问题就是 terminal-Vdq direct path。

因此第一工程动作应先修根路径。

如果 slow/fast split 稳定但鲁棒性不足，再进入：

```text
virtual impedance
active damping
explicit output-admittance shaping
```

---

# 20. slow/fast split 有没有一个很重要的理论优点？

有。

写成传递函数：

```text
Fvff(s)
=
Kfast
+
(1-Kfast) Hslow(s)
```

因为：

```text
Hslow(0)=1
```

所以无论 Kfast 多少：

```text
Fvff(0)=1
```

即：

> **DC/稳态前馈永远不丢。**

高频时：

```text
Hslow ≈ 0
```

所以：

```text
Fvff(high frequency) ≈ Kfast
```

也就是说：

```text
DC gain
和
fast gain
```

被干净分开。

这正好针对我们现在的问题：

```text
C1告诉我们：
fast dynamic direct FF必须削弱

C1 slow-slip告诉我们：
DC/slow tracking不能永久丢
```

所以 slow/fast split 不是凭惯性想到的，而是两个实验事实交集出来的结构。

---

# 21. `AA15_VFF_DQ_SHAPER` 到底是干什么？

它只是我们准备新增模块的名字。

展开：

```text
AA15
= 当前项目诊断/增强模块统一前缀

VFF
= Voltage FeedForward
= 电压前馈

DQ
= d/q两轴一起处理

SHAPER
= 不删除信号，而是塑造它的频率动态
```

所以：

```text
AA15_VFF_DQ_SHAPER
```

就是：

> **“d/q端口电压直接前馈动态整形器”。**

---

# 22. 它在模型中放哪里？

控制意义上的根因在第三张图：

```text
Vd_meas → Feedforward_d 的 + 输入
Vq_meas → Feedforward_q 的 + 输入
```

但实际工程改模建议不进去剪这两根内部线。

因为当前 Causal Harness 已经提供了安全外部插入点。

目标链路：

```text
Measurements
↓
raw VdVq
↓
old C1 vector wrapper
↓
C1 axis wrapper
↓
【NEW AA15_VFF_DQ_SHAPER】
↓
Current Regulator/in1
```

因此 Current Regulator 内部仍会认为它收到的是：

```text
VdVq_meas
```

但在 Mode7 island shaping 时，实际收到的是：

```text
Vff_dq = shaped terminal Vdq
```

它只影响第三张图那两根 direct `+Vd/+Vq` 线。

**前提是只读审计再次证明 Current Regulator/in1 在内部没有被别的关键环节复用。**

这正是本轮审计的重点之一。

---

# 23. 为什么不直接改 Current Regulator 内部？

不是因为不能。

而是为了工程风险最小。

外部 wrapper 的优势：

```text
不碰PI
不碰Rff/Lff
不碰Saturation
不改Current Regulator内部库结构
五台Patch完全一致
Mode0~6可以exact bypass
容易回滚
容易审计
```

只要审计证明：

```text
Current Regulator/in1
```

只服务于 direct terminal Vdq feedforward，这个外部插入就是数学等价的。

如果审计发现 in1 还被内部其它控制支路使用：

```text
就不能外部整形整个in1
```

那时必须回到第三张图内部，只处理两条 direct branch。

所以**我们现在先审计，而不是凭截图直接Patch。**

---

# 24. OpWrite 到底保留什么？

当前每台 diag26：

```text
01 raw Id_ref
02 raw Iq_ref
03 applied Id_ref
04 applied Iq_ref

05 Id_meas
06 Iq_meas

07 raw Vd
08 raw Vq
09 final applied Vd
10 final applied Vq

11 Current PI_d
12 Current PI_q

13 Vconv_d
14 Vconv_q

15 ModIndex
16 Pmeas
17 Qmeas

18 selected/execution angle
19 selected/execution frequency

20 native PLL theta
21 native PLL frequency

22 CAUSAL_MODE
23 old C1_TRACK
24 C2_TRACK
25 D_AXIS_TRACK
26 Q_AXIS_TRACK
```

对于下一轮工程修复，我建议：

> **一个都先不删。**

不是“越多越好”，而是每一组仍然对应一个需要排除的失败模式：

```text
01~04：
证明P/Q Iref没有偷偷变化

05~06：
看GFL真实电流响应/输出导纳

07~10：
根因输入、shaper输出

11~12：
检查是否重演C1的PI长期代偿漂移

13~14：
看root path最终Vconv传播

15：
排除modulation saturation

16~17：
看逐设备功率

18~21：
检查slow-slip、执行坐标与PLL

22~26：
证明试验模式与旧因果Harness透明
```

在“最终解决方案还没闭环”之前删它们，会节省很少的数据，却可能让我们缺一块关键证据。

---

# 25. 新方案真正只需要再加4个 scalar

不记录 `Vfast`，因为：

```text
Vfast = Vraw - Vslow
```

离线可以精确计算。

建议新增：

```text
27 Vslow_d
28 Vslow_q
29 Kfast_eff
30 Kfast_target
```

因此：

```text
per GFL = 30 scalar

G26 = 60
G27 = 30
G28 = 60
```

仍然只用原来的5个 OpWrite。

---

# 26. G29/G30 这次必须重点审计

此前：

```text
G29
```

能覆盖 J1 并记录 PCC/ESS1 关键物理量。

但是：

```text
G30
```

历史上只记录到约 8.102 s，没覆盖 8.209 s J1。

而下一轮修复不能只看180ms：

```text
至少要看J1后0.5s
```

以检查 C1 曾暴露的 slow-slip。

所以本次只读审计必须明确：

```text
G29/G30当前Decimation
capture length
输入宽度
文件/segment机制
G30里到底有哪些theta/frequency信号
```

再决定：

```text
是否调整Decimation
是否依赖第二segment
是否把少数slow-slip关键信号并入G29
```

**不能现在凭感觉改 OpWrite。**

---

# 27. 下一次一次 Build 的目标

如果审计通过，下一次 Build 应一次准备：

```text
Mode0~6 保留
Mode7 = dq VFF shaper

runtime tunable:
alpha / fc等价参数
Kfast_island
Kfast_slew

diag30

足够覆盖J1后0.5s的ESS1/PCC slow diagnostics
```

这样：

```text
改fc
改Kfast
改slew
```

都只改 runtime 参数，不重新 Build。

---

# 28. 一次 Build 后的第一轮不是“参数扫”

第一正式修复试验建议：

```text
fc = 1 Hz
Kfast_island = 0
Kfast 1→0 ≈10ms
```

原因分别是：

```text
1Hz：
由最低危险模态10.6Hz和<10%快速前馈目标推导

Kfast=0：
先做最强但仍保留DC/slow tracking的机制验证

10ms：
由19.9ms pre-J1 window推导
```

目的只有一个：

> **验证“恢复慢跟踪、消除快速unity direct FF”是否同时干掉三种快速失稳，并避免C1 hard HOLD的慢滑移。**

若成功：

```text
根因→修复闭环完成
```

后续调大 fc/Kfast 是性能优化，不是重新寻找根因。

---

# 29. 当前信心边界

## 可以高度确信

```text
terminal Vdq dynamic direct feedforward
```

是正确根因作用点。

因为 D/Q 四角主动因果已经闭合。

## 可以高度确信

最终不能：

```text
只修d
只修q
永久HOLD
只追17Hz
```

## 有强依据但仍需工程验证

```text
dq对称 slow/fast split
```

是第一优先修复结构。

## 现在还不能声称

```text
fc=1Hz
Kfast=0
10ms slew
```

就是最终量产/论文意义下的最优参数。

最终参数要由：

```text
工程闭环实验
+
输出阻抗/导纳稳定裕度
+
动态性能
```

确定。

这不是遗漏，而是把：

```text
根因确定
结构选择
参数整定
```

三个层次严格分开。

---

# 30. 下一步：只读审计

本次审计只读，不修改模型。

它必须回答：

1. 当前 post-Mode6 `K26_V5.slx` 的真实 SHA256；
2. 五台控制器路径是否一致；
3. Mode0~6 / diag26 是否完整；
4. 当前真实链路是否为：
   ```text
   old C1 → axis wrapper → Current Regulator/in1
   ```
5. Current Regulator/in1 内部是否**只**服务于 direct Vd/Vq Feedforward；
6. d/q direct branch 的真实 Sum/Gain/符号结构；
7. Rff/Lff/Current PI 是否完全独立于未来 shaper 作用点；
8. logger input5 是否确实为“final applied Vdq”；
9. 新 Mode7 / shaper 名称是否无碰撞；
10. G26~G30 五个 OpWrite 的真实参数、宽度、Decimation、capture配置；
11. G30 中 ESS1 theta/Fout/frequency 真实信号来源；
12. 下一轮0.5s post-J1数据是否需要调整 G29/G30；
13. `Ts` 是否可用于纯基础块离散 SlowTracker；
14. compile 状态下所有相关 width 是否与设计相容；
15. 审计结束后模型 `Dirty` 必须仍保持 off。

只有这些全部确认后再写 Patch。
