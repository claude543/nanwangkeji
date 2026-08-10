# 暑期南网科技项目｜SS内逆变器 Control System 彻底理解版

> 目标：把当前六台逆变器共用的 `Control System` 从整体闭环到每一个内部子模块彻底串起来。  
> 依据：当前用户上传的 Control System 总览及 8 张内部放大图，并结合当前 `1SM+3SS` 分核模型已经确认的接口和信号关系。  
> 当前实时基本步长：`Ts = 100 μs`。  
> 当前六台本地 Control System 的算法主体没有因分核而重写；主要接口变化是把旧模型中隐藏的 `GridOn` 改成了显式第 8 个输入 `GRIDON`。

---

# 0. 阅读这份文档前，先记住一句话

一台逆变器的 Control System 干的事情，本质上只有一句话：

> **上层告诉我“你应该发/吸多少功率、参考频率和参考电压是多少”，我不断测量设备当前真实电压电流，把这些目标逐层转换成“应该输出什么电流 → 应该产生什么交流电压 → PWM 应该怎样开关”，再由真实变流器执行；执行结果又被重新测量回来，形成闭环。**

所以整个本地闭环可以先压缩成：

```text
上层参考
Fref / Vref / Pref / Qref
        ↓
Control System
        ↓
电流参考 Id/Iq_ref
        ↓
电流内环
        ↓
dq电压指令 Vd/Vq_conv
        ↓
三相调制波 Vpwm
        ↓
PWM Generator
        ↓
IGBT六路门极 g
        ↓
Two-Level Converter
        ↓
真实交流电压、电流、功率改变
        ↓
Vabc / Iabc 再测回来
        ↓
Control System重新计算
```

这不是一次性计算，而是在当前实时模型中**每 100 μs 重复一次**。

---

# 1. Control System 位于整个项目的什么位置

当前每台设备的快速控制和功率级都放在对应 SS 中。

整体结构：

```text
SM_Master
  │
  │  每台设备12维：
  │  [Vabc(3), Iabc(3), Fref, Vref,
  │   Droop_On, Pref, Qref, GridOn]
  │
  ↓
Memory
  ↓
SS Inport
  ↓
OpComm
  ↓
Group Demux
  ↓
Device Demux
  ↓
┌─────────────────────────────┐
│       Control System        │
└─────────────────────────────┘
  ↓ Vpwm
PWM Generator
  ↓ g1~g6
Two-Level Converter
  ↓
滤波器 / 低压网络 / Delta
  ↓
Stubline
  ↓
SM中的变压器、高压馈线、PCC
```

所以要特别区分两种东西：

```text
普通控制信息：
SM ↔ SS
走 OpComm / Memory

真实电气能量：
SM ↔ SS
走 Stubline
```

Control System 属于**SS 中的本地快速控制器**，它并不直接通过 Modbus 与板子通信。

以后 V5 即使板端 AGC 真正接管，也只是：

```text
板端
→ 给出六路 Pref
→ SM安全门
→ 现有12维通信
→ SS Control System
```

Control System 本身仍然负责把 Pref 真正执行成逆变器功率。

---

# 2. Control System 的 8 个输入和 2 个输出

当前新模型中，每台 Control System 有 8 个显式输入：

```text
1  Vabc
2  Iabc
3  Fref
4  Vref
5  Droop_On
6  Pref
7  Qref
8  GRIDON
```

两个主要输出：

```text
1  Vpwm
2  meas（14维内部测量/状态向量）
```

## 2.1 Vabc / Iabc

来自 SM 中本设备的 `prim_*` 高压侧测量。

当前 `prim_*` 的方向已经统一为：

```text
设备 → prim → 馈线/母线
= 正方向
```

所以本地功率符号与项目统一：

```text
PV发电            Pmeas > 0
ESS放电           Pmeas > 0
ESS充电           Pmeas < 0
EV充电            Pmeas < 0
```

这一点非常重要，因为：

```text
Vabc / Iabc
→ Measurements
→ Pmeas
→ Power Control Loop / Droop
```

也就是说，`prim` 不是为了画 Scope 才测，它直接参与闭环。

---

## 2.2 Fref / Vref

来自 SM 中的 `Microgrid Supervisory Control`。

可以把它们理解为：

```text
Fref：
“系统希望本地频率参考是多少”

Vref：
“系统希望本地电压参考是多少”
```

它们首先进入 Droop/构网路径，在那里再做标幺化。

当前 SC 中曾经直接把：

```text
Fref 与 PCC频率
Vref 与 PCC电压
```

放在一起观察，因此这两个量是上层物理参考，而不是 PWM 门极信号。

---

## 2.3 Pref / Qref

这是设备最直接的功率任务。

当前：

```text
Pref
= 有功功率参考，pu

Qref
= 无功功率参考，pu
```

例如：

```text
EV Pref = -0.6 pu
```

表示单台 100 kW 设备希望吸收约：

```text
-60 kW
```

Control System 的任务就是不断调节，使本地：

```text
Pmeas → Pref
```

---

## 2.4 Droop_On 和 GRIDON —— 两个最容易混淆的输入

这两个信号绝对不要混成一个“模式开关”。

### Droop_On

直接进入 `Droop Control` 的 `Enable`。

它控制的是：

> **P/Q 下垂反馈是否参与构网参考的生成。**

也就是是否让：

```text
Pmeas影响频率
Qmeas影响电压
```

---

### GRIDON

第 8 个输入进入：

```text
ConnectMode
```

而 `ConnectMode` 控制大批 Switch。

它负责：

> **当前公共内环到底采用 Grid-Following 那套信号，还是 Grid-Forming 那套信号。**

所以：

```text
Droop_On
= 控制“下垂特性是否启用”

GRIDON / ConnectMode
= 控制“哪套控制参考系最终接入公共内环”
```

两者职责完全不同。

> 注意：仅凭目前截图可以确定 `ConnectMode` 在两套路径之间切换，但不能严谨地仅凭图标断言“0一定是哪一路、1一定是哪一路”。精确 0/1 语义最终以这些 Switch 的 Criteria/Threshold 参数为准。本文不人为猜测这个参数。

---

# 3. 第一张总览图到底怎样看

第一张总览图不要按“左上 → 右下”机械阅读。

应该把它看成：

```text
                   ┌───────────────┐
                   │ Measurements  │
                   │ 两套测量同时算 │
                   └──────┬────────┘
                          │
             ┌────────────┴────────────┐
             │                         │
             ▼                         ▼
       Grid-Forming               Grid-Following
       构网控制链                  跟网控制链
             │                         │
   Droop Control                Power Control Loop
             │                         │
   Voltage Regulators                │
             │                         │
             └──────────┬──────────────┘
                        ▼
                  signal switch
                        │
             只选当前需要的一套
                        ▼
                 Current Regulator
                        │
                  VdVq_conv
                        ▼
                  Vref Generation
                        │
                      1/z
                        ▼
                      Vpwm
                        │
                  PWM Generator
```

所以它不是“两套完整逆变器控制器”。

更准确地说：

> **前半段有两套外层控制思想，但后半段共用同一套电流内环和 PWM 调制生成。**

这是理解整个 Control System 最重要的一点。

---

# 4. 为什么要同时存在 Grid-Following 和 Grid-Forming

## 4.1 Grid-Following：跟着电网走

有大电网存在时，大电网已经提供了：

```text
频率基准
相位基准
电压基准
```

逆变器主要需要回答：

> “我应该向这个已经存在的电网注入/吸收多少 P、Q？”

所以 GFL 最典型的链是：

```text
PLL锁住电网相位
↓
把abc量转换到PLL同步dq坐标
↓
Pref - Pmeas
Q反馈误差
↓
功率PI
↓
Id/Iq参考
↓
电流内环
↓
PWM
```

它像一个：

> **“跟着大部队节拍走，只负责控制自己出多少力”的成员。**

---

## 4.2 Grid-Forming：自己提供参考

没有可靠大电网参考时，不能再依赖 PLL 说：

```text
“别人现在角度是多少，我跟着它。”
```

这时逆变器要自己产生：

```text
频率
相角
电压幅值
```

所以 GFM 链是：

```text
Fref / Vref
+
P/Q下垂
↓
自己得到 Fout / theta / Vout
↓
电压调节器
↓
Id/Iq参考
↓
电流内环
↓
PWM
```

它像：

> **“自己拿节拍器，同时根据自己承担的负荷自动略微调频、调压”的电源。**

---

# 5. Measurements：整个 Control System 的“眼睛和翻译器”

这是图2。

它的任务不是单纯“测量一下”。

它实际上完成三件事：

```text
① 把Vabc/Iabc转换成控制器能理解的pu量
② 把abc正弦量变成dq近似直流量
③ 同时生成GFM和GFL两套坐标系下的测量值
```

---

# 6. 为什么不能直接拿 Vabc/Iabc 做 PI 控制

三相 abc 电压例如：

```text
Va = 正弦
Vb = 相差120°
Vc = 再相差120°
```

即使系统已经完全稳定，它们仍然每秒变化50次。

如果直接拿正弦量做普通 PI：

```text
参考值
-
不断旋转的正弦测量
```

控制器会非常难设计。

所以使用 Park 变换：

```text
abc
→ dq
```

如果 dq 坐标系正好跟着电压矢量一起旋转，那么原来不停旋转的三相量，在 dq 坐标系里会近似变成：

```text
Vd ≈ 常数
Vq ≈ 常数

Id ≈ 常数
Iq ≈ 常数
```

这样 PI 就很好调。

通俗类比：

> 你站在地面看旋转木马上的人，他一直在转；  
> 你自己也站上旋转木马，用同样速度跟着转，那个人在你眼里就几乎不动了。

---

# 7. Measurements 左半边：Droop-based Grid Forming 测量

左侧路径使用：

```text
[wt]
```

作为 abc→dq 的旋转角。

这里的 `wt` 不是 PLL 给的。

它来自：

```text
Droop Control
→ theta_out
→ [wt]
```

所以这套坐标系本质是：

> **逆变器自己建立的旋转坐标系。**

---

## 7.1 Vabc → VdVq_meas

路径：

```text
Vabc_prim
↓
V->pu
↓
abc to dq0（角度 = wt）
↓
取d/q两个分量
↓
低通滤波
↓
VdVq_meas
```

### V->pu 为什么存在

SM 送来的 `Vabc` 是实际物理电压。

本地控制器更适合在 pu 下设计。

已有模型使用类似：

```text
1 / (Vnom_prim × √2 / √3)
```

的比例，把三相高压侧瞬时峰值统一到标幺尺度。

所以后面的控制器看到的是：

```text
额定附近 ≈ 1 pu
```

而不是：

```text
几千伏、上万伏
```

---

## 7.2 Iabc → IdIq_meas

路径：

```text
Iabc_prim
↓
A->pu
↓
abc to dq0（角度 = wt）
↓
取d/q
↓
滤波
↓
IdIq_meas
```

电流基值由：

```text
Vnom_prim
Pnom
```

共同决定。

目的仍然是：

> 不让 PI 参数直接依赖“多少安培”。

---

## 7.3 P/Q 测量

左下的 `Power (PLL-Driven, Positive-Sequence)` 虽然块名中写着 PLL-Driven，但在这一支实际给它的是：PLL同步的正序P/Q测量模块

```text
Freq
wt
Vabc
Iabc
```

其中 `Freq`、`wt` 来自本地构网参考。

所以这里真正应该理解为：

> **利用提供给它的频率/相角参考，计算正序 P/Q。**

然后：

```text
P/Q
↓
PQ->pu
↓
滤波
↓
P_meas / Q_meas
```

这两个无后缀量属于 GFM / Droop 坐标体系。

## 7.4 Power 模块到底在做什么（记成"提取 P/Q"）

先记住这个块的整体作用：

> **从三相 `Vabc + Iabc` 中提取基波正序有功 P 和无功 Q。**

它还需要 `Freq` 和 `wt`，因为要知道当前基波频率和相角，才能围绕正确的同步参考计算。

> 注意：块名叫 `PLL-Driven` 只是模板命名习惯；在当前模型里，实际输入是当前控制模式有效的那套 `Freq` / `wt`（GFM 支来自本地构网参考，见上文；GFL 支来自 PLL，见下一节）。

它通常位于 `Measurements` 或 `PCC Measurements` 中，输出 `Pmeas/Qmeas` 或 `Ppcc/Qpcc`，再送给本地功率环、Droop、AGC 或上层策略。

通俗说：

> **把杂乱的三相瞬时波形整理成"现在真正有多少有功、无功"。**

整个控制链里，它的位置可以记成**"提取 P/Q"**。

---

# 8. Measurements 右半边：Grid Following / PLL 测量

右边先做最关键的一步：

```text
Vabc
↓
PLL
↓
Freq_PLL
theta_PLL
```

PLL就是：

> **实时判断外部电网现在转到哪个角度、实际频率是多少。**

---

## 8.1 为什么 PLL 只看电压

电网电压是同步参考。

PLL通过三相电压判断：

```text
当前相位角 theta_PLL
当前频率 Freq_PLL
```

然后其它量全部采用这个角度进行 dq 变换。

---

## 8.2 GFL电压 dq 测量

```text
Vabc
↓
V->pu2
↓
abc to dq2
角度 = theta_PLL
↓
滤波
↓
VdVq_measPLL
```

对应总览中的：

```text
[VdVqF]
```

---

## 8.3 GFL电流 dq 测量

```text
Iabc
↓
A->pu3
↓
abc to dq3
角度 = theta_PLL
↓
滤波
↓
IdIq_measPLL
```

对应：

```text
[IdIqF]
```

---

## 8.4 GFL P/Q

另一套功率测量使用：

```text
Freq_PLL
theta_PLL
Vabc
Iabc
```

得到：

```text
P_meas_PLL
Q_meas_PLL
```

也就是后续：

```text
[PmeasF]
[QmeasF]
```

截图中 PLL 功率支路滤波后还能看到一个：

```text
4/6
```

比例块。

可以确定它是当前模型已有的功率归一化/比例修正的一部分。

但仅凭这张截图不能严谨证明“为什么恰好是4/6”的设计来源，因此：

> **把它理解为原模板已经验证的测量比例修正即可，不要擅自改动。若以后要追公式来源，需要再打开该功率测量块及相关Mask参数核对。**

---

# 9. Measurements 为什么一定要两套都同时算

因为模式切换时不能临时说：

```text
“现在开始从头算PLL”
```

或者：

```text
“现在开始从头建立Droop角度”
```

更稳的方式是：

```text
GFM测量持续算
+
GFL测量持续算
↓
真正使用哪套
由 ConnectMode 的 Switch 决定
```

就像飞机有两套仪表一直工作，需要时切显示源，而不是切换时才启动第二套仪表。

---

# 10. Power Control Loop：Grid-Following 的功率外环

这是图5。

它主要做：

> **把 Pref / Qref 转换成 Id/Iq 电流参考。**

因为真正的变流器不是直接“接受100 kW”。

它最终能直接控制的是：

```text
开关
→ 电压
→ 电流
```

所以功率目标必须逐层下翻：

```text
功率目标
→ 电流目标
→ 电压目标
→ PWM
```

---

# 11. 有功通道：Pref - Pmeas

当前图中很明确：

```text
Pref
  +
  │
 [Σ] → PI → 第一电流参考分量
  │
Pmeas
  -
```

因此：

```text
eP = Pref - Pmeas
```

例如 EV：

```text
Pref  = -0.60 pu
Pmeas = -0.50 pu
```

则：

```text
eP = -0.10
```

表示：

> 当前充电还不够，需要继续把功率往负方向推。

PI根据这个误差改变电流参考。

---

# 12. 为什么功率 PI 不直接输出 PWM

因为：

```text
功率动态
```

比：

```text
电流动态
```

慢。

如果功率环直接控制PWM，会让一个慢变量直接操作最快的开关层，调试和稳定性都很差。

所以采用经典级联：

```text
功率PI
只负责告诉下一层：
“我需要多少电流”

电流PI
负责：
“我怎样快速把这个电流做出来”
```

---

# 13. Q 通道：为什么图里是 Qmeas - Qref

图中下方求和块明确表现为：

```text
Qmeas
  +
 [Σ]
Qref
  -
```

即：

```text
eQ = Qmeas - Qref
```

随后进入第二个功率 PI。

这和很多教材里常写的：

```text
Qref - Qmeas
```

表面相反。

这里不要擅自“纠正”。

原因是：

> dq 轴定义、电流正方向以及本模型 Q 的符号约定共同决定了该环的反馈符号。

当前六套 Control 已经通过真实物理基线验证，所以：

```text
P环、Q环的求和符号
属于已验证控制器的一部分
```

不能因为和某本教材写法不同就自行翻转。

---

# 14. Power Control Loop 中间那条 Vref / VdVq 支路为什么存在

图中：

```text
Vref
→ to-pu1

VdVq
→ 取一个电压分量

二者求差
```

但是当前截图显示这个差值最终进入：

```text
Terminator
```

并没有进入最终 `IdIqrefF`。

因此当前实际闭环中：

> **这条电压偏差支路不是 GFL Power Control Loop 的有效输出路径。**

它更像是：

```text
原模板遗留接口
调试量
或曾经为另一种控制结构预留的支路
```

当前不要把它算进实际功率闭环。

真正有效的是：

```text
Pref/Pmeas → PI
Qmeas/Qref → PI
→ IdIqrefF
```

---

# 15. Droop Control：Grid-Forming 的“频率和电压发生器”

这是图4。

输入：

```text
Fref
Vref
Pmeas
Qmeas
Enable（Droop_On）
```

输出：

```text
Vout
theta_out
Fout
```

这是 GFM 路线的核心。

---

# 16. P-f 下垂到底在做什么

最直观思想：

```text
输出有功越多
→ 自己的频率参考略微降低
```

即类似：

```text
P ↑
→ f ↓
```

为什么这样能帮助多台逆变器分功率？

假设两台构网逆变器并联。

负荷突然增加时，谁先多承担一点功率，谁的频率参考就略微往下掉。

这样功率会自然重新分配，最后达到新的平衡。

它不是靠中央控制器逐微秒告诉每台：

```text
“你现在加0.01 kW”
```

而是靠每台自己的外特性协调。

---

# 17. 图中 P-f 支路逐块看

首先：

```text
Fref
→ to-pu
```

把上层频率参考转换到当前内部标幺尺度。

同时：

```text
Enable × Pmeas
→ -Freq_Droop
```

所以 Droop_On 的作用非常直观：

```text
Enable = 0
→ Pmeas下垂反馈项归零

Enable = 1
→ Pmeas真正参与频率修正
```

然后频率求和块还加入：

```text
Frequency_Droop/100/2
```

这个常量是一个**偏置/工作点校正项**。

所以不要把当前块过度简化成只有：

```text
f = Fref - Kp·P
```

当前实现更准确地说是：

```text
频率标幺参考
+
有功下垂项
+
固定偏置项
→ 内部频率标幺值
```

这个偏置项使下垂曲线围绕设计工作点布置，而不是机械地以 `P=0` 为唯一中心。

---

# 18. Fout 和 theta_out 为什么都需要

频率求和结果分成两条。

### 第一条

```text
内部频率pu
→ Fnom
→ Fout
```

得到实际频率量。

它被 Measurements 的 GFM 功率测量使用。

---

### 第二条

```text
频率
→ 角速度/每步相角增量换算
→ 离散积分器 K·Ts/(z-1)
→ mod(2π)
→ theta_out
```

为什么频率还要积分？

因为：

```text
频率 = 相角变化速度
```

也就是：

```text
θ = ∫ 2πf dt
```

PWM最终必须知道：

> “A相现在到底应该走到正弦波哪个角度了？”

所以只知道50 Hz不够，还要积出：

```text
wt / theta
```

`mod(2π)` 是为了把角度不断限制回：

```text
0 ~ 2π
```

避免角度无限增长成非常大的数。

---

# 19. Q-V 下垂

下半部分：

```text
Enable × Qmeas
→ Voltage_Droop

Vref
→ to-pu1

两者相加
→ Vout
```

本质是：

```text
Q变化
→ 电压幅值参考发生轻微变化
```

也就是典型：

```text
Q-V droop
```

与 P-f 类似：

> 多台构网电源不用高频互相通信，也能通过公共电网电压/频率行为实现一定程度的负荷共享。

---

# 20. Voltage Regulators：把“我要什么电压”变成“我要什么电流”

这是图3。

它只属于 GFM 路径。

Droop Control 给它：

```text
Vout
```

而 Measurements 给它：

```text
VdVq
```

Voltage Regulators 再产生：

```text
IdIq_ref
```

所以逻辑就是：

```text
电压参考
-
实际电压
↓
PI
↓
需要多少电流来纠正电压
```

---

# 21. 当前模型的 dq 轴定义不要套错教材

图中上支路明确是：

```text
Vq_ref - Vq
```

其中：

```text
Vq_ref
来自 Vout
```

下支路：

```text
Vd - Vd_ref
```

而：

```text
Vd_ref = 0
```

这说明当前模型采用的坐标约定是：

> **主要电压幅值参考落在 q 轴，而 d 轴参考约为 0。**

很多教材习惯写：

```text
Vd ≈ 1
Vq ≈ 0
```

但本模型显然采用了旋转90°后的另一套等价定义。

所以以后看本模型：

```text
不要机械说“d轴一定管电压幅值”
```

要以当前变换定义为准。

---

# 22. Voltage Regulators 的 On

`On` 经一个 0/1 Switch 后同时进入两个 PI 的辅助端口。

从当前结构可以理解为：

```text
On = 1
→ PI处于正常投入状态

On = 0
→ PI进入复位/冻结/旁路管理状态
```

作用是：

> 不使用这套电压控制时，不让 PI 积分器在后台继续乱积累。

否则过一段时间再切回来，可能因为积分器已经积了很大的旧误差而产生突跳。

---

# 23. Anti-windup PI 为什么在这里反复出现

功率环、电压环、电流环都用了：

```text
PI regulator with anti-windup
```

普通 PI 最大的问题之一是：

```text
设备已经达到输出极限
但误差还存在
→ 积分器继续累加
→ windup
```

等系统终于能恢复时，积分器里面已经存了一大堆“历史债务”，容易导致：

```text
超调
恢复慢
甚至振荡
```

Anti-windup 的目标就是：

> **输出已经被物理限幅时，不允许积分器继续无意义地越积越大。**

当前截图没有展开这些 PI Mask 的内部实现，因此本文只确认它们的功能，不虚构内部比较器和具体复位逻辑。

## 23.1 先记住 PI 本身在干什么（记成"稳稳地追踪目标"）

作用是把"参考值 − 实际值"的持续误差转换成控制修正量：

```text
功率环：Pref - Pmeas → PI → Id/Iq_ref
电流环：IdIq_ref - IdIq_meas → PI → VdVq 修正量
```

`anti-windup` 是为了防止输出已经达到限幅后，积分器还继续越积越大，否则恢复时容易严重超调。

通俗说：

> **PI 负责追目标，anti-windup 负责防止控制器在做不到的时候越憋越多。**

整个控制链里，它的位置可以记成**"稳稳地追踪目标"**。

---

# 24. signal switch：整个双模控制器的“换轨器”

这是图8。

前面两套路径都已经算好了：

```text
Grid Following：
IdIq_refF
VdVqF
IdIqF
thetaF

Grid Forming：
IdIq_ref
VdVq
IdIq
wt
```

但公共 Current Regulator 只能同时采用一套。

所以 signal switch 输出统一的：

```text
IdIq_refs
VdVqs
IdIqs
wts
```

可以直接理解为：

```text
IdIq_refs：
当前模式真正采用的电流参考

VdVqs：
当前模式真正采用的dq电压测量

IdIqs：
当前模式真正采用的dq电流测量

wts：
当前模式真正采用的相角
```

---

# 25. 为什么不能只切 IdIq_ref

假如只切电流参考：

```text
参考用GFL坐标
```

但：

```text
实测电流却还是GFM坐标
```

那就是拿两个不同坐标系的数字做减法。

例如：

```text
同一个三相电流
在PLL坐标下 = [0.8, 0.1]
在Droop坐标下 = [0.3, 0.75]
```

它们不是同一坐标中的数。

所以模式切换必须成套切：

```text
参考电流
实测电流
实测电压
相角
```

这正是 signal switch 存在的原因。

---

# 26. ConnectMode 的本质

第8输入：

```text
GRIDON
→ ConnectMode
→ 多个Switch
```

它相当于告诉整个 Control System：

> **“现在公共内环应该相信哪套参考系。”**

但再次强调：

```text
ConnectMode = 0
到底选哪一路
ConnectMode = 1
到底选哪一路
```

仅凭当前静态截图不足以严谨冻结。

如果以后需要把这个语义写进正式模型文档，只需要打开任意一个 Switch，看：

```text
Criteria
Threshold
```

即可100%确定。

这并不影响现在理解它的功能。

---

# 27. Current Regulator：真正最快的“执行控制器”

这是图6。

到这里，前面所有复杂事情都已经被压缩成：

```text
我希望电流 = IdIq_ref
我实际电流 = IdIq_meas
```

Current Regulator只做一件事：

> **让实际电流尽快跟上参考电流。**

---

# 28. 电流误差

图中求和明确为：

```text
IdIq_ref
-
IdIq_meas
↓
PI
```

写成向量：

```text
e_i = IdIq_ref - IdIq_meas
```

然后：

```text
PI(e_i)
→ PIdq
```

`PIdq` 是电流 PI 自己给出的修正电压分量。

---

# 29. 为什么只有 PI 还不够

逆变器通过滤波电感接到交流网络。

即使：

```text
Id_ref = Id
```

为了维持这个电流，变流器本身仍然必须克服：

```text
外部交流电压
线路/滤波电阻压降
dq旋转坐标中的电感交叉耦合
```

如果全部让 PI 慢慢试出来：

```text
“我先多给一点电压看看”
```

响应会变慢，而且 d/q 两轴会互相影响。

所以这里加了：

```text
Feedforward
```

---

# 30. Feedforward 前馈逐块理解

从图中可以看出，两轴前馈大致按以下结构形成：

第一轴：

```text
测量电压分量
+
Rff × 对应电流参考
-
Lff × 另一轴电流参考
```

第二轴：

```text
测量电压分量
+
Rff × 对应电流参考
+
Lff × 另一轴电流参考
```

也就是：

```text
Vff,d ≈ Vd + Rff·Id_ref - Lff·Iq_ref
Vff,q ≈ Vq + Rff·Iq_ref + Lff·Id_ref
```

当前实现中的 `Rff`、`Lff` 是从模型工作区复制并保留的控制器参数。

这里不要再额外凭教材给 `Lff` 硬乘一个 `ω`，因为当前模型的参数定义已经封装了自身的标幺/前馈意义。

---

# 31. 为什么 d/q 会交叉耦合

因为坐标系本身在旋转。

在旋转 dq 坐标中，电感不仅有：

```text
L·dI/dt
```

还会出现：

```text
另一轴电流对本轴的耦合项
```

所以：

```text
d轴改变
会影响q轴

q轴改变
也会影响d轴
```

Feedforward 就是在 PI 还没来得及慢慢修正之前，提前把这些已知影响补进去。

通俗理解：

> 你知道汽车马上会上坡，就提前踩油门，而不是等车速已经掉下来后再靠速度PI补救。

---

# 32. PI + Feedforward

最终：

```text
PIdq
+
Feedforward
↓
Saturation
↓
VdVq_conv
```

因此：

```text
PI
= 负责消灭剩余误差

Feedforward
= 负责提前补偿已知物理规律
```

这是一种非常典型的高性能逆变器电流控制结构。

## 32.1 前馈的详细拆解：每一项在补什么

> 把前馈理解成：**根据滤波器和电网的已知物理规律，直接预先算出"为了产生目标电流，逆变器大约应该输出多少 dq 电压"。**

当前结构：

```text
                 电流误差
IdIq_ref - IdIq_meas
        ↓
       PI
        ↓
     ΔV_PI
        │
        │
        ├──────────────┐
        │              │
        │         Feedforward
        │              │
        └────── + ─────┘
                ↓
            VdVq_conv
```

也就是说：

> **前馈先给一个理论上比较正确的电压，PI 只负责修剩余误差。**

### ① 为什么控制电流需要先算一个电压

逆变器不是直接"命令电流"。

它真正能够控制的是：

```text
PWM
→ 逆变器交流侧电压
→ 滤波电感两端产生压差
→ 电流发生变化
```

所以如果希望：

```text
Id → Id_ref
Iq → Iq_ref
```

本质上必须先知道：

> "为了让这个电流存在，逆变器应该产生什么电压？"

而这个电压至少要克服三部分：

```text
① 外部网络当前本来就有的电压
② 滤波电阻上的压降
③ 滤波电感以及 dq 旋转产生的交叉耦合
```

于是才有图里的三组前馈量。

### ② 第一项：VdVq_meas —— 电网电压前馈

`VdVq_meas` 直接进入两个前馈求和块，它代表：

> **逆变器交流端现在已经存在的外部电压。**

假设电网当前已经有：

```text
Vd = 某个值
Vq = 某个值
```

你要让电流稳定流进去，逆变器输出电压首先就要"站在这个基础电压附近"。

否则，假设外面已经有 1 pu 电压，而控制器从 0 开始慢慢让 PI 猜：

```text
0 → 0.1 → 0.2 → ... → 1.0
```

显然非常慢。

所以直接：

```text
测得外部电压
→ 提前加到逆变器电压指令里
```

这就是最基本的**电网电压前馈**。

### ③ 第二项：Rff × 电流参考 —— 电阻压降补偿

因为滤波电阻满足：

```text
V_R = R × I
```

如果希望流过某个目标电流 `I_ref`，那么就已经能提前知道大约存在 `R × I_ref` 的电压损失。

所以：

```text
I_ref
→ Rff
→ 提前补偿电阻压降
```

通俗说：

> 已经知道线路上会损失 0.02 pu 电压，就别等 PI 发现"怎么电流还没到"，直接提前多给这 0.02 pu。

### ④ 第三项：Lff × 另一轴电流 —— dq 交叉耦合补偿

这是最重要、也最难直观看懂的一部分。

在普通 abc 静止坐标里，电感主要体现：

```text
L di/dt
```

但我们控制器工作在**旋转的 dq 坐标系**里。由于坐标系本身在旋转，会产生：

```text
d轴电流影响q轴电压
q轴电流影响d轴电压
```

也就是 **dq 交叉耦合**。

因此图里不是简单：

```text
d轴只看 Id
q轴只看 Iq
```

而是出现另一轴电流经过 `Lff` 加入本轴电压前馈。图里可以明确看到两个轴的符号不同：

```text
上面前馈求和：
+ 测量电压
+ Rff 项
- Lff 交叉项

下面前馈求和：
+ 测量电压
+ Rff 项
+ Lff 交叉项
```

这正是在做 **dq 解耦补偿**。

至于哪个对应 d 轴、哪个对应 q 轴，以及为什么一个 `+` 一个 `-`，取决于当前模型的 Park 变换和 dq 方向定义；我们应保持模型现有符号，不按其他教材强行翻转。

### ⑤ 所以前馈实际上在算什么

概念上可以理解为：

```text
某一轴所需电压
≈
当前网络电压
+
本轴电阻压降
±
另一轴电感耦合补偿
```

即近似：

```text
Vff,d ≈ Vd + Rff·Id_ref ± Lff·Iq_ref
Vff,q ≈ Vq + Rff·Iq_ref ± Lff·Id_ref
```

这里故意不把两个 `±` 写死，因为**具体正负必须服从当前模型的 dq 定义**；图里的两个求和块已经把正确符号固定好了。

### ⑥ 那已经有这么完整的前馈，为什么还需要 PI

因为前馈依赖的是"理论模型"。

实际系统永远可能存在：

```text
R参数不完全准确
L参数不完全准确
电压测量误差
采样延迟
PWM延迟
线路变化
设备扰动
模型未考虑的动态
```

所以前馈可能算出"理论应该给 0.80 pu"，但真实系统可能需要 0.83 pu，剩下 0.03 pu 就交给 PI 纠正。

所以最终：

```text
VdVq_conv = Feedforward + PI correction
```

这是这张图最核心的思想。

### ⑦ 最通俗的比喻：开车保持 100 km/h

**前馈**是：

> "我看到前面是 10° 上坡，根据车辆模型，提前多踩 20% 油门。"

**PI** 是：

> "提前加了油以后，实际只有 98 km/h，那我再补一点，直到 100。"

如果没有前馈：

```text
上坡 → 车速先下降 → PI 发现误差 → 再慢慢加油
```

如果有前馈：

```text
看到上坡 → 提前加油 → 车速基本不掉 → PI 只修最后一点误差
```

因此在逆变器里：

> **`VdVq_meas + Rff + Lff` 前馈负责根据电路物理规律提前算出大部分正确电压；PI 负责根据 `IdIq_ref - IdIq_meas` 把模型误差和扰动造成的剩余偏差修掉。**

### ⑧ 最后再串到模型

```text
VdVq_meas + IdIq_ref
        ↓
   R/L Feedforward
        ↓
     基础电压
        +
IdIq_ref - IdIq_meas
        ↓
       PI
        ↓
     修正电压
        │
        └──── 相加
              ↓
          Saturation
              ↓
          VdVq_conv
              ↓
       Vref Generation
              ↓
             PWM
              ↓
          真实逆变器
              ↓
          实际电流改变
```

一句话：

> **前馈"按物理模型提前算"，PI"按实际误差事后修"，二者叠加后既快又准。**

---

# 33. Saturation 为什么是必需的

控制器数学上可能算出：

```text
“我想要1.4 pu电压”
```

但变流器能产生的交流电压受：

```text
DC母线电压
调制方式
```

限制。

所以必须限幅。

否则后续会进入严重过调制，控制器要求的电压物理上根本做不出来。

---

# 34. Vref Generation：把 dq 电压指令重新变成三相 PWM 调制波

这是图7。

Current Regulator 输出：

```text
VdVq_conv
```

但 PWM Generator 需要的是：

```text
A相调制波
B相调制波
C相调制波
```

所以最后必须完成：

```text
dq电压
→ 幅值 + 相角
→ 三相正弦波
```

---

# 35. 为什么先处理 DC 电压

左侧：

```text
Vdc_meas
→ 1/2
```

然后与：

```text
Vnom_sec × √2 / √3
```

比较/归一化。

这是在问：

> **当前直流母线能提供的交流电压能力，相对于额定交流相电压峰值是多少？**

随后：

```text
VdVq_conv
÷
这个DC电压可用比例
```

得到适合 PWM 使用的调制 dq 量。

总览图中当前给这个端口的是：

```text
Vnom_dc
```

因此当前实现更接近：

> 使用额定/给定 DC 母线电压进行调制归一化。

---

# 36. dq 复数化的意义

二维量：

```text
Vd
Vq
```

可以看成一个复数：

```text
Vd + jVq
```

于是：

```text
Real-Imag to Complex
↓
Complex to Magnitude-Angle
```

就直接得到：

```text
幅值 |V|
角度 φ
```

这一步把”两个坐标分量”重新解释成：

```text
我要多大幅值
我要偏多少相角
```

## 36.1 Cartesian to Polar：把 dq 直角坐标变成幅值 + 相角（记成”把 dq 向量变成幅值和角度”）

作用是把二维直角坐标量从 `d/q` 表达转换成**幅值 + 相角**。

例如 `VdVq_conv` 原来表示两个 dq 分量，经过 Cartesian to Polar 后得到：

```text
|V|     → 用于 ModIndex / 调制幅值
angle   → 与 wt、三相±120°、变压器相移补偿等组合
```

然后生成三相正弦调制参考送 PWM。

通俗说：

> **前面控制器算的是”横向多少、纵向多少”，PWM 最终需要知道的是”这个电压向量有多大、朝哪个方向”。**

整个控制链里，它的位置可以记成**”把 dq 向量变成幅值和角度”**。

## 36.2 这三个模块在整条链里的位置

上面三个模块（Power、anti-windup PI、Cartesian to Polar）在整条链里的位置，可以记成：

```text
Vabc/Iabc
→ Power模块
→ P/Q反馈

参考 - 反馈
→ anti-windup PI
→ 控制量

dq控制量
→ Cartesian to Polar
→ 幅值 + 相角
→ 三相PWM
```

一句话：

> **Power 负责”看现在是多少”，PI 负责”把它调到目标”，Cartesian to Polar 负责”把调节结果变成 PWM 能使用的幅值和角度”。**

---

# 37. ModIndex：调制比

幅值路径：

```text
|V|
↓
Saturation
↓
ModIndex
```

`ModIndex` 可以理解成：

> **为了产生目标交流电压，我现在需要把直流母线利用到什么程度。**

大致：

```text
0
→ 不输出

接近1
→ 接近线性调制能力上限
```

它既参与最终三相波幅值，也被放进 `meas` 作为诊断量。

---

# 38. 相角路径：为什么有这么多加法

最终每相角度不是只有：

```text
wt
```

还包括：

```text
dq电压自身角度 φ
+
三相120°偏移
+
变压器D1补偿
+
一个Ts的数字延迟补偿
+
公共旋转角 wt
```

---

# 39. 三相 120° 偏移

常量：

```text
[0, -2π/3, +2π/3]
```

就是：

```text
A相：0°
B相：-120°
C相：+120°
```

没有它就不是三相系统。

---

# 40. `-π/6`：为什么补偿30°

图中明确注释：

```text
Correction for transformer D1 connection
```

而：

```text
-π/6 = -30°
```

原控制器对应 D1 Delta 变压器连接。

变压器组别会引入固定相移。

如果控制器完全不补偿这个相移，那么：

```text
控制器认为的dq角度
```

和：

```text
高压侧实际电气角度
```

会存在固定30°误差。

这会导致：

```text
P/Q串扰
dq控制不准
甚至稳定性恶化
```

因此它提前把变压器相移抵消。

当前任务拆分以后虽然 Delta 被放到 SS 内重新显式组成，并通过 Stubline 跨任务，但控制器原来的 D1 相位补偿仍被保留。

---

# 41. `Ts*Fnom*2π`：为什么补偿一个控制周期

图中明确写：

```text
Correction for delay of Ts
```

Control System 顶层在 Vref Generation 后还有：

```text
1/z
```

也就是一个离散步延迟。

一个周期内，相角会继续前进：

```text
Δθ = 2π f Ts
```

当前：

```text
Ts = 100 μs
f  = 50 Hz
```

因此：

```text
Δθ
= 2π × 50 × 100e-6
≈ 0.031416 rad
≈ 1.8°
```

所以控制器提前补约：

```text
1.8°
```

抵消一个 Ts 引入的相位滞后。

注意：

> 旧说明里曾举过50 μs的例子，但当前实时模型已经冻结为100 μs，因此当前应使用约1.8°。

---

# 42. 最终三相 Vpwm

相角经过：

```text
sin()
```

得到三相单位正弦波。

再乘：

```text
ModIndex
```

得到最终：

```text
三相调制参考 Vref
```

在 Control System 顶层再经过：

```text
1/z
```

输出为：

```text
Vpwm
```

之后才进入 Control System 外面的：

```text
PWM Generator (2-Level)
```

所以：

```text
Vref Generation
≠ 直接开IGBT

Vref Generation
→ 产生调制参考

PWM Generator
→ 把调制参考变成6路门极脉冲
```

---

# 43. PWM Generator 后发生什么

```text
Vpwm
↓
PWM Generator
↓
g1~g6
↓
Two-Level Converter
```

六路门极控制三相桥的上下开关。

于是：

```text
直流侧能量
↔
三相交流侧能量
```

转换方向取决于：

```text
Pref
当前电网状态
本地控制结果
```

所以 ESS 能双向充放电，EV 在当前控制范围内主要表现为负功率充电，PV主要表现为正功率发电。

---

# 44. 最右侧 `meas` 14维到底是什么

图9非常重要。

这个输出名字叫：

```text
meas
```

但它并不是14个纯“物理测量”。

它其实是：

> **本地控制器的运行仪表盘。**

当前打包顺序可以读成：

```text
1   Id_ref
2   Id
3   Iq_ref
4   Iq
5   ModIndex
6   PId
7   PIq
8   Freq
9   Pmeas
10  wt
11  Qmeas
12  Vd
13  Vq
14  Vref
```

---

# 45. 这14个量各自告诉你什么

## 1~4 电流参考和实际电流

```text
Id_ref vs Id
Iq_ref vs Iq
```

这是判断本地内环有没有跟上的最直接证据。

如果：

```text
Id_ref改变
但Id长期不动
```

那不是 AGC 的问题，而是设备本地电流执行层出现异常。

---

## 5 ModIndex

看：

```text
控制器离过调制极限还有多远
```

如果长期顶到上限，说明控制器要求的交流电压已经接近硬件能力边界。

---

## 6~7 PId / PIq

这是 Current Regulator 中：

```text
PI本身输出的dq修正量
```

不包括全部前馈。

它可以帮助判断：

> 当前 PI 到底在多努力地纠错。

---

## 8 Freq

这是 ConnectMode 选出的当前模式有效频率。

不是固定死的“PLL频率”或者“Droop频率”。

---

## 9 Pmeas

这是当前设备最终用于控制和上层反馈的有功测量。

当前六路返回 SM 的 Pmeas 就来源于 SS 中这些本地控制/测量结果。

它也是未来论文中最重要的真实设备执行状态之一。

---

## 10 wt

当前模式真正使用的相角。

它就是 Vref Generation 最终生成三相调制波时的旋转基准。

---

## 11 Qmeas

当前模式有效无功功率。

---

## 12~13 Vd / Vq

当前模式有效 dq 电压。

---

## 14 Vref

上层给本地控制器的电压参考，用于观察参考与实际状态关系。

---

# 46. 为什么最右边还要再次用 ConnectMode 选择 Freq/P/Q/Vdq

因为内部两套测量一直同时存在：

```text
GFM：
Freq / Pmeas / Qmeas / VdVq

GFL：
FreqF / PmeasF / QmeasF / VdVqF
```

如果最后的 `meas` 不选模式，那么上层会搞不清：

```text
“这个Pmeas到底属于哪套坐标/算法？”
```

所以最终输出也通过 ConnectMode 选择当前模式对应的：

```text
Freq
Pmeas
Qmeas
Vd/Vq
```

这样 `meas` 才代表：

> **当前控制器真正采用的那套运行状态。**

---

# 47. Goto / From 标签究竟是什么

你在图里会看到很多：

```text
[Pmeas]
[VdVq]
[IdIq]
[wt]
[PmeasF]
[IdIq_refF]
...
```

这些不是无线通信，也不是 RT-LAB OpComm。

它们只是：

> **同一个 Control System 内部为了少画长线使用的 Simulink 信号标签。**

例如：

```text
Measurements
→ Goto [Pmeas]

Droop Control
→ From [Pmeas]
```

逻辑上等价于一根普通 Simulink 线。

它们不会自动产生网络延时。

---

# 48. 一次 Grid-Following 闭环完整走一遍

假设 AGC 给某台 PV：

```text
Pref = +0.30 pu
Qref = 0
```

第1步：

```text
SM prim测得 Vabc / Iabc
↓
送进SS Control
```

第2步：

```text
PLL读取Vabc
↓
得到 theta_PLL / Freq_PLL
```

第3步：

```text
Vabc/Iabc
用 theta_PLL 做abc→dq
↓
得到 VdVqF / IdIqF
```

第4步：

```text
计算 PmeasF / QmeasF
```

第5步：

```text
Pref - PmeasF
↓
功率PI
↓
得到有功对应电流参考
```

第6步：

```text
Q反馈误差
↓
Q PI
↓
得到无功对应电流参考
```

第7步：

```text
signal switch
↓
把GFL的：
IdIq_refF
VdVqF
IdIqF
thetaF
送入公共内环
```

第8步：

```text
IdIq_ref - IdIq_meas
↓
Current Regulator PI
+
R/L前馈解耦
↓
VdVq_conv
```

第9步：

```text
Vref Generation
↓
ModIndex + 三相角度
↓
Vpwm
```

第10步：

```text
PWM
↓
IGBT
↓
实际电流改变
↓
实际P改变
```

第11步：

```text
新的 Vabc / Iabc
再回到 Measurements
```

于是：

```text
PmeasF
逐渐逼近 Pref
```

这就是一台设备的 GFL 有功闭环。

---

# 49. 一次 Grid-Forming 闭环完整走一遍

现在换成需要本机建立频率/电压参考。

第1步：

```text
Fref / Vref
↓
Droop Control
```

第2步：

```text
Pmeas
→ P-f droop
→ Fout

Qmeas
→ Q-V droop
→ Vout
```

第3步：

```text
Fout积分
↓
theta_out = wt
```

此时逆变器已经有自己的：

```text
频率
相角
电压幅值目标
```

第4步：

```text
wt
进入Measurements
↓
用本机角度做abc→dq
↓
VdVq / IdIq / Pmeas / Qmeas
```

第5步：

```text
Vout
-
实际Vdq
↓
Voltage Regulators
↓
IdIq_ref
```

第6步：

```text
signal switch
↓
把GFM的：
IdIq_ref
VdVq
IdIq
wt
送给公共Current Regulator
```

第7步以后：

```text
Current Regulator
→ Vref Generation
→ PWM
→ Converter
→ 真实V/I改变
→ Measurements
```

闭环再次成立。

---

# 50. GFL和GFM真正共享了什么

最终共享：

```text
Current Regulator
Vref Generation
1/z
PWM Generator
Converter
真实电路
```

不同的只是：

```text
“我要什么电流参考”
和
“我用哪个角度解释测量”
```

从哪里来。

因此可以压缩成：

```text
GFL：
PLL + P/Q功率外环
         ↓
      电流参考

GFM：
Droop + 电压环
         ↓
      电流参考

         ↓
   同一个电流内环
         ↓
   同一个PWM执行层
```

---

# 51. Control System 与 AGC 的关系

这一点对我们的论文尤其重要。

AGC不负责：

```text
PLL
dq变换
电流PI
PWM
IGBT
```

AGC只负责：

```text
“这台设备下一阶段应该给多少Pref？”
```

本地 Control System负责：

```text
“我怎样把这个Pref真正实现出来？”
```

所以两层分别是：

```text
AGC：
任务分配者

Control System：
设备执行者
```

---

# 52. 为什么我们的论文以后必须尊重本地 Control System 动态

假设 AGC 在某一秒把：

```text
Pref:
0.20 → 0.40 pu
```

并不意味着同一个瞬间：

```text
Pmeas:
0.20 → 0.40 pu
```

因为中间还必须经历：

```text
功率外环PI
↓
Id/Iq_ref
↓
电流内环
↓
Vd/Vq
↓
PWM
↓
Converter
↓
滤波器
↓
真实电磁动态
↓
Pmeas
```

所以：

```text
Pref ≠ Pmeas
```

在短时间内完全可能是**正常设备动态**。

这正是论文以后不能简单使用：

```text
|Pref - Pmeas| > 0
→ 执行失败
```

的原因。

必须先认识清楚：

> 本地 Control System 自己就有真实动态响应时间。

---

# 53. 当前分核以后，一个100 μs步内怎样工作

假设当前是第 `k` 个实时步。

SM和SS不是简单顺序：

```text
SM全部算完
再算SS
```

而是通过 Memory / Stubline 状态边界并行运行。

概念上：

```text
SM：
使用已有边界状态
算高压电网/PCC/prim
并准备新的12/24维控制量

SS：
使用上一确定通信状态
执行：
Control
→ PWM
→ Converter
→ 低压电路
```

SS Control 在本步产生：

```text
新的Vpwm
新的门极
新的设备电气响应
新的Pmeas
```

到步末：

```text
Memory
Stubline
PI积分器
PLL
Droop角度
PWM状态
```

全部更新。

第 `k+1` 步再继续。

所以当前100 μs是：

> **真实本地设备控制、开关和跨任务状态推进的基本时间节拍。**

---

# 54. 三层嵌套闭环如何套在一起

当前至少有三个最重要的时间尺度。

### 第一层：电流快速闭环

```text
IdIq_ref
↓
Current Regulator
↓
PWM / Converter
↓
IdIq_meas
↑______________
```

目的：

```text
把目标电流做出来
```

---

### 第二层：本地功率/电压闭环

GFL：

```text
Pref
↓
Power Control
↓
IdIq_ref
↓
电流环
↓
Pmeas
↑____________
```

GFM：

```text
V/F参考 + Droop
↓
Voltage Regulator
↓
IdIq_ref
↓
电流环
↓
V/P/Q
↑____________
```

目的：

```text
让单台设备真正完成自己的局部任务
```

---

### 第三层：微网AGC慢闭环

当前约每1 s：

```text
Ptarget
↓
PCC误差
↓
AGC
↓
六路Pref
↓
六套本地Control
↓
六台真实功率
↓
PCC
↑____________
```

目的：

```text
让整个微网PCC跟踪目标
```

---

# 55. 为什么控制器必须这样“套娃”

因为不同对象快慢完全不一样。

如果 AGC 每100 μs直接改：

```text
IGBT门极
```

它根本不应该承担这个任务。

反过来，如果电流环1 s才更新一次：

```text
开关级逆变器早就失稳了
```

所以正确分工是：

```text
最内层：
快、局部、物理

最外层：
慢、全局、协调
```

这也是当前项目：

```text
SM放上层
SS放快速本地控制和功率级
```

的根本工程逻辑。

---

# 56. 你以后看Control System，建议按这6个问题判断每个模块

看到任何块，不要先问：

```text
“它叫什么？”
```

而先问：

```text
1. 它收到的是参考还是测量？
2. 这个量目前是abc还是dq？
3. 是物理单位还是pu？
4. 它属于GFL还是GFM？
5. 它输出的是功率、电流、电压还是相角？
6. 它下一步送给谁？
```

只要这6个问题能答出来，这个模块就不会再“看起来像一团线”。

---

# 57. 最终总图——一张图记住全部Control

```text
                    SM上层
────────────────────────────────────
PCC → AGC → Pref
Supervisor → Fref / Vref
prim → Vabc / Iabc
Droop_On
GRIDON
                    │
                    │ 12维/设备
                    ▼
────────────────────────────────────
                 SS Control
────────────────────────────────────

                Measurements
          Vabc / Iabc实际物理量
                    │
         ┌──────────┴──────────┐
         │                     │
         ▼                     ▼
      GFM测量                GFL测量
      用 wt                  用 PLL
         │                     │
 P,Q,Vdq,Idq             P,Q,Vdq,Idq
         │                     │
         ▼                     ▼
   Droop Control        Power Control
   P→f, Q→V            Pref/Qref→IdIq
         │                     │
    F,V,theta                 │
         │                     │
 Voltage Regulators            │
    V误差→IdIq                 │
         └──────────┬──────────┘
                    ▼
              signal switch
           ConnectMode统一选路
                    │
      IdIq_ref / IdIq / VdVq / wt
                    ▼
             Current Regulator
         电流PI + R/L前馈解耦
                    │
                 VdVq_conv
                    ▼
              Vref Generation
     DC归一化 + ModIndex + 相角补偿
                    │
                   1/z
                    │
                  Vpwm
                    ▼
              PWM Generator
                    ▼
                  g1~g6
                    ▼
            Two-Level Converter
                    ▼
             L/C + Delta + Stub
                    ▼
           真实电压/电流/功率
                    │
                    └────────→ 下一次Measurements
```

---

# 58. 最后用一句最通俗的话总结

> **Measurements 负责“看清设备现在怎么样”；GFL Power Loop 或 GFM Droop+Voltage Loop 负责“决定我现在应该要多少电流”；signal switch 负责“决定当前听哪套控制”；Current Regulator 负责“把这股电流真正做出来”；Vref Generation + PWM 负责“把数学上的电压命令变成IGBT实际开关”；真实电路执行以后又产生新的 V/I/P/Q 回来，于是整个闭环不断重复。**

如果这句话能在脑中对应到第一张总览图，那么整个 Control System 的大框架就已经真正看懂了。

---

# 59. 当前有两件事不要自行“修正”

第一：

```text
Power Control Loop 中 Qmeas - Qref 的符号
```

虽然和部分教材写法不同，但它属于当前控制器既有 dq/功率符号体系，而且当前物理基线已验证，不应凭直觉翻号。

第二：

```text
ConnectMode 的0/1→GFL/GFM精确对应
```

当前截图只能确定它负责成套切换两套信号。正式写“0=某模式，1=某模式”之前，应以 Switch 的 Criteria/Threshold 参数再确认一次。

---

# 60. 与当前论文最直接的联系

理解这个 Control System 后，论文里一个关键问题就非常清楚：

```text
AGC给出 u_commit / Pref
        ↓
本地Control不是瞬时理想执行器
        ↓
Power PI
Current PI
PWM
Converter
电气网络
        ↓
Pmeas
```

因此：

```text
u_commit 与 Pmeas 不同
```

可能来自：

```text
正常控制动态
```

也可能来自：

```text
通信未执行
设备受限
执行异常
```

未来策略2真正困难的地方，就是要区分这几种情况，而不是简单把 `Pref-Pmeas` 当成异常。

这也是为什么后续 V5 基础闭环稳定后，要对 PV / ESS / EV 分别做：

```text
Pref阶跃 → Pmeas
```

的正常响应辨识。
