# 暑期南网科技项目｜SS 内单台逆变器 Control System 逐模块彻底理解版
## ——先吃透“一台逆变器完整闭环”，再彻底区分 GFL 与 GFM

> **阅读目标**：不是“知道这些模块叫什么”，而是看完以后能够自己顺着任意一根线回答：这个信号从哪里来、为什么经过这个块、块内部做了什么、输出送到哪里、怎样最终改变 IGBT、真实电流和功率又怎样测回来形成闭环。
>
> **当前模型依据**：`K12_V4yanshou.slx` + 你昨天上传的 Control System 总览和各子模块放大图。  
> 当前实时基本步长：`Ts = 100 μs`；当前开关频率：`Fsw = 4 kHz`。
>
> 本文用三种标记：
>
> - **【模型事实】**：当前 K12、截图或块参数可以直接确认；
> - **【原理解释】**：说明为什么电力电子控制一般要这样设计；
> - **【注意】**：命名遗留、参数异常或容易误解的地方。

---

# 0. 先把两个优先级的大图放进脑子

## 0.1 第一优先级：一台逆变器完整闭环

当前 GFL 主闭环可以先压缩成：

```text
Pref / Qref
↓
Power Control Loop
“目标P/Q → 目标dq电流”
↓
Id/Iq reference
↓
Current Regulator
“目标电流 → 目标dq电压”
↓
Vd/Vq command
↓
Vref Generation
“dq电压 → 三相调制参考”
↓
Vpwm
↓
PWM Generator (2-Level)
“连续参考 → 6路0/1门极脉冲”
↓
g1...g6
↓
Two-Level Converter
“真正切换IGBT”
↓
PWM交流电压
↓
L1 + C1
“滤除开关高频”
↓
Delta低压侧
↓
Differential Stubline
↓
SM中的三台单相变压器
↓
prim高压侧
↓
Feeder / PCC
↓
真实 prim Vabc / Iabc
↓
SM→SS 数字反馈
↓
Measurements
“真实V/I → dq、PLL、P/Q”
↓
Pmeas / Qmeas / IdIq_meas
↓
重新进入 Power Loop / Current Loop
```

真正的闭环不是“Pref进来，PWM出去”就结束，而是：

> **我给命令 → 真实功率级执行 → 我重新测真实结果 → 根据误差再修正。**

---

## 0.2 第二优先级：GFL 与 GFM 是“两套外层，共用一个执行底盘”

```text
                     Measurements
                   /              \
                  /                \
                 ▼                  ▼
          Grid-Following      Grid-Forming
          PLL + P/Q外环       Droop + 电压环
                 \                  /
                  \                /
                   ▼              ▼
                     signal switch
                          ↓
                  Current Regulator
                          ↓
                   Vref Generation
                          ↓
                    PWM Generator
                          ↓
                    Two-Level Converter
```

区别主要在：

```text
相角从哪里来？
电流参考怎样产生？
```

一旦两种模式都已经得到：

```text
IdIq_ref
IdIq_meas
VdVq_meas
wt/theta
```

后面共用同一套：

```text
电流内环 → 调制生成 → PWM → 变流器 → LC → 变压器
```

---

# 1. Control System 在当前 SM/SS 分核中的位置

## 1.1 数字控制信息怎样进 Control

SM为每台设备形成12维向量：

```text
[Vabc(3);
 Iabc(3);
 Fref;
 Vref;
 Droop_On;
 Pref;
 Qref;
 GridOn]
```

两台设备合成24维后：

```text
SM Mux24
→ Memory
→ SM Outport
→ SS Inport
→ OpComm
→ [12 12] Demux
→ [3 3 1 1 1 1 1 1] Demux
→ Control System 8个输入
```

所以当前 Control 的 `Vabc/Iabc` 是：

```text
SM中本设备 prim 高压侧测量
→ 数值信号
→ SM→SS普通通信
→ Control
```

不是从本地 Stubline 直接抽取的。

---

## 1.2 真实电气能量怎样跨 SM/SS

真实电路走另一条链：

```text
SS：
Converter
→ L1/C1
→ Delta
→ PMIO
↕
Differential Stubline
↕
SM：
单相变压器
→ prim
→ feeder
→ PCC
```

因此：

```text
OpComm = 数字信息
Stubline = 真实电气网络边界
```

这两个绝对不要混。

---

# 2. Control System 顶层 8 个输入

## 模块/端口1：`Vabc`

宽度：

```text
3 = [Va,Vb,Vc]
```

来源：

```text
SM中本设备 prim_* 高压侧三相电压
```

去向：

```text
→ Measurements
```

为什么存在：

> PLL、abc/dq、P/Q测量、电压前馈都必须知道设备真实并网侧电压。

---

## 模块/端口2：`Iabc`

宽度：

```text
3 = [Ia,Ib,Ic]
```

来源：

```text
prim_* 高压侧三相电流
```

去向：

```text
→ Measurements
```

为什么存在：

> 没有真实电流就无法计算设备实际P/Q，也无法形成电流闭环。

---

## 模块/端口3：`Fref`

单位：

```text
Hz
```

来源：

```text
SM Microgrid Supervisory Control
```

主要去向：

```text
→ Droop Control
```

GFM时作为公共频率基础参考；当前GFL下仍送入，但不是最终PWM相角的主来源。

---

## 模块/端口4：`Vref`

来源：

```text
Supervisor
```

主要去向：

```text
→ Droop Control
→ Power Control Loop中的诊断/遗留电压支路
```

GFM时用于形成电压幅值基础参考。

---

## 模块/端口5：`Droop_On`

当前：

```text
3 s：0 → 1
```

去向：

```text
→ Droop Control / Enable
```

作用：

```text
0：P/Q下垂反馈不参与
1：P-f、Q-V下垂真正参与
```

**它不是模式开关。**

---

## 模块/端口6：`Pref`

单位：

```text
pu
```

当前来源：

```text
本地 MATLAB AGC
```

未来V5：

```text
板端AGC → Modbus → SM安全门 → Pref
```

当前主去向：

```text
→ Power Control Loop
```

---

## 模块/端口7：`Qref`

单位：

```text
pu
```

去向：

```text
→ Power Control Loop
```

作为无功目标。

---

## 模块/端口8：`GRIDON`

顶层通过标签形成：

```text
ConnectMode
```

【模型事实】当前K12主Switch判据：

```text
u2 > 0.5
```

且连线确定：

```text
ConnectMode = 1
→ 选上支路
→ GFL

ConnectMode = 0
→ 选下支路
→ GFM
```

因此当前可以明确：

```text
GridOn = 1 → Grid-Following
GridOn = 0 → Grid-Forming
```

---

# 3. Control System 顶层 2 个输出

## 输出1：`Vpwm`

链：

```text
Vref Generation
→ 三相Vref
→ Unit Delay (1/z)
→ Vpwm
→ PWM Generator
```

它是三相连续调制参考，不是6路门极。

---

## 输出2：`meas`

14维本地运行状态总线。

主要用途：

```text
诊断
观察
向SM上送Pmeas
Target/Modbus数据源
```

它不是 Control 内部所有反馈必须绕行的总线。

---

# 4. 顶层辅助块：Goto / From / Unit Delay / Constant

## `Goto / From`

例如：

```text
[Pmeas]
[PmeasF]
[VdVq]
[VdVqF]
[IdIq]
[IdIqF]
[wt]
[thetaF]
```

只是内部信号路由。

```text
不改变值
不产生网络延时
不是OpComm
```

---

## `Unit Delay4 / Unit Delay5`

【模型事实】：

```text
Pmeas → Unit Delay4 → Droop
Qmeas → Unit Delay5 → Droop
```

作用：

> 打断 `Droop wt → Measurements P/Q → Droop wt` 的同拍代数环。

变成：

```text
当前步Droop
使用上一确定步的P/Q
```

适合100 μs离散实时执行。

---

## Vref Generation 后 `Unit Delay 1/z`

```text
Vref
→ 1/z
→ Vpwm
```

延迟一拍：

```text
100 μs
```

所以 Vref Generation 内部专门有：

```text
Ts*Fnom*2π
```

相角提前量，补偿这一拍。

---

## `Vreg_on`

【模型事实】顶层有一个常量：

```text
Vreg_on = 1
```

它使 GFM `Voltage Regulators` 的PI一直正常计算。

但当前 GridOn=1 时：

```text
GFM结果只是后台候选
```

最终没有被主 signal switch 选入 Current Regulator。

---

## `Vnom_dc`

【模型事实】顶层 Vref Generation 的 `Vdc_meas` 当前接的是：

```text
Constant Vnom_dc
```

因此当前调制归一化使用额定DC电压，不是实时DC母线测量。

---

# 5. Measurements：整个 Control System 的“眼睛 + 翻译器”

## 5.1 为什么必须有 Measurements

原始反馈是：

```text
Vabc、Iabc
```

它们是50 Hz旋转正弦，而且是实际物理量。

控制器真正想要：

```text
pu量
近似直流的dq量
P/Q
PLL频率和相角
```

所以 Measurements 完成：

```text
真实V/I
→ pu
→ dq
→ P/Q
→ 两套模式各自可用的反馈
```

它不是单纯“测一下”，而是：

> **把真实三相电气世界翻译成控制算法能直接使用的语言。**

---

# 6. Measurements 的 4 个输入、10 个输出

输入：

```text
1 Vabc_prim
2 Iabc_prim
3 Freq
4 wt
```

其中 `Freq/wt` 是 GFM/Droop 候选路径的自生参考。

输出：

```text
1  VdVq_meas
2  IdIq_meas
3  P_meas
4  Q_meas

5  VdVq_measPLL
6  IdIq_measPLL
7  P_meas_PLL
8  Q_meas_PLL
9  wt_PLL
10 Freq_PLL
```

可以分成：

```text
无PLL后缀
→ GFM/Droop参考系

PLL后缀
→ GFL/电网同步参考系
```

---

# 7. 为什么要 abc → dq

稳定三相电压仍然是：

```text
Va = Vm sin(ωt)
Vb = Vm sin(ωt-120°)
Vc = Vm sin(ωt+120°)
```

即使系统没有任何异常，三个数一直变化。

如果建立一个和基波一起旋转的坐标：

```text
abc → dq
```

那么在同步正确时：

```text
Vd,Vq
Id,Iq
```

会接近常数。

通俗比喻：

> 站在地面看旋转木马上的人，他一直转；你也坐上同速木马后，他在你眼里几乎不动。

这就是 PI 为什么喜欢 dq。

---

# 8. 为什么 Measurements 要同时算两套 dq

GFL：

```text
角度 = theta_PLL
```

意思：

> 跟着外部电网转。

GFM：

```text
角度 = Droop生成的 wt
```

意思：

> 自己定义旋转参考。

所以同一个 Vabc/Iabc 同时翻译两遍。

---

# 9. Measurements：GFM 电压支路逐块讲

完整链：

```text
Vabc_prim
→ V->pu
→ abc to dq0
→ Selector
→ Second-Order Filter
→ VdVq_meas
```

## 模块1：`V->pu`

类型：

```text
Gain
```

增益：

```text
1/(Vnom_prim*sqrt(2)/sqrt(3))
```

作用：

```text
实际三相高压瞬时电压
→ 以额定相电压峰值为基准的pu
```

为什么：

```text
额定附近变成1 pu量级
PI参数和数值尺度更统一
```

---

## 模块2：`abc to dq0`

输入：

```text
abc = pu Vabc
wt  = Droop相角
```

输出：

```text
[d,q,0]
```

这是 GFM 自生坐标系下的电压。

---

## 模块3：`Selector`

取：

```text
[d,q]
```

丢弃零序。

---

## 模块4：`Second-Order Filter`

输出：

```text
VdVq_meas
```

作用：

> 滤掉dq中的开关纹波、谐波和高频噪声，给外环/前馈更平滑的反馈。

---

# 10. Measurements：GFM 电流支路逐块讲

完整链：

```text
Iabc_prim
→ V->pu1
→ abc to dq1
→ Selector
→ Second-Order Filter
→ IdIq_meas
```

## 模块5：`V->pu1`

【注意】名字是模板遗留，实际接的是 `Iabc_prim`。

当前增益：

```text
Vnom_prim*sqrt(3)/Pnom/sqrt(2)
```

实际功能：

```text
A → pu
```

也就是电流标幺化。

---

## 模块6：`abc to dq1`

用：

```text
wt = GFM相角
```

把电流变成 GFM dq 电流。

---

## 模块7：`Selector`

取：

```text
Id,Iq
```

---

## 模块8：`Second-Order Filter`

输出正式：

```text
IdIq_meas
```

GFM时作为 Current Regulator 的实际电流反馈候选。

---

# 11. Measurements：GFM P/Q 支路逐块讲

链：

```text
Freq → Saturation ┐
wt ───────────────┤
Vabc ─────────────┤→ Power (PLL-Driven, Positive-Sequence)
Iabc ─────────────┘
                 ↓
                P,Q
                 ↓
          PQ->pu / PQ->pu1
                 ↓
        Second-Order Filter
                 ↓
          P_meas / Q_meas
```

## 模块9：`Saturation`

【模型事实】当前这条 GFM Freq→Power 支路可见范围是：

```text
55～65 Hz
```

【注意】这与当前项目额定50 Hz不一致，是一个遗留参数风险点。

当前真实主路径是GFL，因此它不影响当前基线主闭环；未来真正做GFM/孤岛前必须单独核查，不能直接沿用。

---

## 模块10：`Power (PLL-Driven, Positive-Sequence)`

输入：

```text
Freq
wt
Vabc
Iabc
```

输出：

```text
P
Q
```

平常可叫：

```text
同步正序P/Q测量模块
```

作用：

> 利用当前基波频率/相角，从真实三相V/I中提取基波正序有功、无功，而不是把PWM纹波、谐波、负序等全部交给Droop。

---

## 模块11：`PQ->pu`

Gain：

```text
1/Pnom
```

作用：

```text
P → pu
```

---

## 模块12：`PQ->pu1`

同理：

```text
Q → pu
```

---

## 模块13/14：两个 `Second-Order Filter`

正式输出：

```text
P_meas
Q_meas
```

这些值经顶层 Unit Delay 后进入 Droop。

---

# 12. Measurements：GFL PLL 支路

完整链：

```text
Vabc
→ V->pu2
→ PLL (3ph)
→ Freq_PLL
→ theta_PLL
```

## 模块15：`V->pu2`

再次把高压Vabc归一化，专供GFL/PLL支路。

---

## 模块16：`PLL (3ph)`

输入：

```text
归一化三相电压
```

输出：

```text
Freq_PLL
theta_PLL
```

它只回答：

```text
电网转得多快？
现在转到哪个角度？
```

它不直接控制P/Q。

为什么 GFL 必须有：

> 外部强电网已经存在，跟网逆变器必须先知道外部电网相位，才能在同一同步坐标系中注入/吸收电流。

---

# 13. Measurements：GFL 电压 dq 支路

```text
Vabc
→ V->pu2
→ abc to dq2(theta_PLL)
→ Selector
→ Second-Order Filter
→ VdVq_measPLL
```

## 模块17：`abc to dq2`

与GFM的数学作用相同，但旋转角改成：

```text
theta_PLL
```

因此是“电网同步坐标系”。

## 模块18：`Selector`

取 Vd/Vq。

## 模块19：`Second-Order Filter`

输出：

```text
VdVq_measPLL
```

顶层对应：

```text
[VdVqF]
```

当前GFL内环前馈真正使用它。

---

# 14. Measurements：GFL 电流 dq 支路

```text
Iabc
→ A->pu3
→ abc to dq3(theta_PLL)
→ Selector
→ Second-Order Filter
→ IdIq_measPLL
```

## 模块20：`A->pu3`

实际A → pu。

## 模块21：`abc to dq3`

用 `theta_PLL` 得到电网同步 dq 电流。

## 模块22：`Selector`

取 Id/Iq。

## 模块23：`Second-Order Filter`

输出：

```text
IdIq_measPLL
```

顶层：

```text
[IdIqF]
```

当前GFL下这是 Current Regulator 的真实电流反馈。

---

# 15. Measurements：GFL 正式 P/Q 支路

## 模块24：`Power (PLL-Driven, Positive-Sequence)1`

输入：

```text
Freq_PLL
theta_PLL
Vabc
Iabc
```

输出 P/Q。

随后：

```text
P/Q
→ Second-Order Filter
→ Gain 4/6
→ P_meas_PLL / Q_meas_PLL
```

【模型事实】存在 `4/6` 比例修正。

可以确定：

> 它承担当前模型功率测量输出尺度与正式反馈尺度之间的校准。

但仅靠当前模型无法严谨还原“为什么原作者恰好选4/6”的完整推导，所以保持现状，不编造来源。

---

## 模块25：第三个 `Power ...2`

还有一套PLL功率测量只送：

```text
Scope2
```

不进入正式P/Q输出。

它是诊断支路，不是主控制反馈。

---

# 16. Measurements 中的 Scope、Demux、Goto/From

`Scope`：

```text
只显示，不控制
```

`Demux`：

```text
把VdVq/IdIq等向量拆成标量给Scope观察
```

`Goto/From`：

```text
内部路由 Freq_PLL、theta_PLL、wt 等
```

它们不会产生控制作用本身。

---

# 17. Measurements 最终一句话

> **同一个真实 prim Vabc/Iabc，被 Measurements 同时翻译成两套“控制语言”：GFL用PLL角度得到 VdVqF/IdIqF/PmeasF/QmeasF；GFM用Droop自生wt得到 VdVq/IdIq/Pmeas/Qmeas。后面 signal switch 决定当前真正使用哪一套。**


---


# 17A. 五个核心控制模块先做一次“输入—作用—输出”总对照

在继续读细节前，先把最容易混的五个模块放在一张图里。

```text
                  GFL外层
Pref/Qref ─────→ Power Control Loop
PmeasF/QmeasF ─→        │
                         └→ IdIq_refF
                              │
                              │
                  GFM外层     │
Fref/Vref ─────→ Droop Control
Pmeas/Qmeas ───→       │
Droop_On ──────→       ├→ wt / Fout / Vout
                        │               │
                        │               ▼
                        │       Voltage Regulators
                        │       VdVq_meas + Vout
                        │               │
                        │               └→ IdIq_ref
                        │
                        └──────────────┐
                                       ▼
                                signal switch
                         GridOn决定GFL/GFM
                                       │
                     ┌─────────────────┼─────────────────┐
                     ▼                 ▼                 ▼
                IdIq_refs          IdIqs            VdVqs
                目标电流           实测电流         实测dq电压
                     └─────────────────┼─────────────────┘
                                       ▼
                               Current Regulator
                          PI纠错 + V/R/L前馈
                                       │
                                       └→ VdVq_conv
                                             │
                                             ▼
                                      Vref Generation
                                  wts + VdVq_conv + Vdc
                                             │
                                  ┌──────────┴──────────┐
                                  ▼                     ▼
                              三相Vref              ModIndex
                                  │
                                1/z
                                  │
                                Vpwm
                                  │
                           PWM Generator
```

下面逐个说清楚。

---

## 17A.1 `Droop Control`

### 输入是谁给的？

| 输入 | 来源 | 含义 |
|---|---|---|
| `Fref` | SM 的 Supervisor | 微网希望保持的公共频率基础参考 |
| `Vref` | SM 的 Supervisor | 微网希望保持的公共电压基础参考 |
| `Pmeas` | Measurements 的 GFM P 测量，经顶层一拍延迟 | 本设备真实有功 |
| `Qmeas` | Measurements 的 GFM Q 测量，经顶层一拍延迟 | 本设备真实无功 |
| `Enable` | `Droop_On` | 是否允许 P-f、Q-V 下垂反馈真正参与 |

### 它干什么？

它不是直接控制 IGBT。

它先回答：

```text
“如果我要作为一个构网电源，
根据当前P/Q负担，
我现在应该维持什么频率、相角和电压幅值？”
```

所以：

```text
Fref + P-f droop
→ Fout

Fout积分
→ theta_out / wt

Vref + Q-V droop
→ Vout
```

### 输出去哪？

```text
Fout
→ GFM Measurements中的正序功率测量参考

theta_out / wt
→ GFM abc/dq变换
→ signal switch的GFM角度候选

Vout
→ Voltage Regulators
→ 作为GFM电压目标
```

所以 Droop Control 的输出仍然是：

```text
“外层参考”
```

不是电流命令，更不是PWM。

---

## 17A.2 `Voltage Regulators`

### 输入是谁给的？

| 输入 | 来源 | 含义 |
|---|---|---|
| `VdVq` | Measurements 的 GFM dq 电压 | 设备当前真实dq电压 |
| `Vq_ref` | Droop 的 `Vout` | 当前GFM希望维持的主要电压幅值参考 |
| `Vd_ref` | Constant 0 | 另一轴参考 |
| `On` | 顶层 `Vreg_on=1` | 是否让电压PI正常工作 |

### 它干什么？

它回答：

```text
“Droop说我希望端电压是这个值，
但实际Vd/Vq不是这个值，
那我应该要求多少dq电流，
才能把端电压推向目标？”
```

所以：

```text
电压误差
→ 两个电压PI
→ IdIq_ref
```

### 输出去哪？

```text
IdIq_ref
→ signal switch的GFM电流参考候选
```

如果：

```text
GridOn=0
```

它才会真正进入 Current Regulator。

---

## 17A.3 `Power Control Loop`

### 输入是谁给的？

当前真正参与 GFL 主控制的是：

| 输入 | 来源 | 含义 |
|---|---|---|
| `Pref` | SM上层/AGC | 希望本设备有功达到多少 |
| `Qref` | SM上层 | 希望本设备无功达到多少 |
| `PmeasF` | Measurements 的 PLL/GFL 正序功率测量 | 当前设备真实有功 |
| `QmeasF` | Measurements 的 PLL/GFL 正序功率测量 | 当前设备真实无功 |

此外还接有：

```text
VdVq
Vref
```

但当前这条电压幅值支路最终接 Terminator，属于诊断/遗留计算，不进入正式 `IdIq_refF`。

### 它干什么？

它回答：

```text
“我想要的P/Q和现在真实P/Q差多少？
为了把P/Q纠正过来，
下一层应该要多少dq电流？”
```

所以：

```text
Pref - PmeasF
→ P PI

Q反馈误差
→ Q PI

→ IdIq_refF
```

### 输出去哪？

```text
IdIq_refF
→ signal switch的GFL电流参考候选
```

当前：

```text
GridOn=1
```

所以它就是实际被选中的电流参考来源。

---

## 17A.4 `Current Regulator`

### 三个输入到底是谁？

进入 signal switch 以后，当前模式的一整套信号统一改名为：

```text
IdIq_refs
IdIqs
VdVqs
```

这里末尾的：

```text
s
```

可以理解成：

```text
selected
已经选中的
```

### `IdIq_refs`

来源：

```text
GFL：
Power Control Loop → IdIq_refF

GFM：
Voltage Regulators → IdIq_ref

↓
signal switch
↓
IdIq_refs
```

所以你的理解是对的：

> **`IdIq_refs` 就是当前模式真正采用的 dq 电流参考。**

---

### `IdIqs`

来源：

```text
GFL：
Measurements → IdIqF

GFM：
Measurements → IdIq

↓
signal switch
↓
IdIqs
```

所以：

> **`IdIqs` 就是 Measurements 算出来的、当前模式真正采用的实测 dq 电流。**

Current Regulator 用：

```text
IdIq_refs - IdIqs
```

计算电流误差。

---

### `VdVqs`

来源：

```text
GFL：
Measurements → VdVqF

GFM：
Measurements → VdVq

↓
signal switch
↓
VdVqs
```

所以：

> **`VdVqs` 是当前模式下实际测得的 dq 电压。**

它为什么也必须进入 Current Regulator？

不是为了计算：

```text
电流误差
```

电流误差只需要：

```text
IdIq_refs
-
IdIqs
```

`VdVqs` 的作用是进入：

```text
Feedforward
前馈
```

因为逆变器要让电流流进一个已经存在电压的网络，首先必须知道：

```text
“外面现在已经有多少电压？”
```

例如外部网络已经约有：

```text
1 pu电压
```

要维持一个稳定电流，变流器输出电压本来就应该在这个外部电压附近，再额外补：

```text
电阻压降
电感耦合
电流误差修正
```

所以：

```text
VdVqs
= 前馈中的“基础外部电压项”
```

如果没有它，PI就得从接近0开始自己慢慢“猜”出整套网络电压，响应会慢很多，也更容易饱和。

---

### Current Regulator 输出什么？

```text
VdVq_conv
```

它代表：

> **为了让真实 dq 电流跟上目标 dq 电流，变流器下一步应该产生的 dq 电压命令。**

另一个输出：

```text
PIdq
```

主要用于诊断，表示 PI 自身补了多少电压。

---

## 17A.5 `Vref Generation`

### 输入是谁给的？

| 输入 | 来源 | 含义 |
|---|---|---|
| `wts` | signal switch | 当前模式真正采用的同步相角 |
| `VdVq_conv` | Current Regulator | 当前所需dq电压命令 |
| `Vdc_meas` | 当前顶层 `Vnom_dc` Constant | 调制归一化使用的DC母线电压尺度 |

其中：

```text
GFL：
wts = theta_PLL

GFM：
wts = Droop self wt
```

### 它干什么？

它回答：

```text
“我已经知道要产生哪个dq电压矢量，
现在怎样把它变成
A/B/C三相PWM能够理解的调制参考？”
```

它完成：

```text
VdVq_conv
→ 幅值 + 相对角

+
wts
+
三相0/±120°
+
D1变压器相移补偿
+
一拍数字延迟补偿

→ 三相正弦角度

× ModIndex
→ 三相Vref
```

### 输出去哪？

```text
三相Vref
→ Unit Delay 1/z
→ Vpwm
→ PWM Generator (2-Level)

ModIndex
→ meas
→ 诊断调制裕度
```

---

# 17B. 五个模块用一句话串起来

```text
Droop Control：
GFM先决定“我应该维持什么F/V/相角”

Voltage Regulators：
再把“电压目标”翻译成“电流目标”

Power Control Loop：
GFL直接把“P/Q目标”翻译成“电流目标”

Current Regulator：
把“电流目标”翻译成“电压目标”

Vref Generation：
把“dq电压目标”翻译成“三相PWM调制参考”
```

所以整个控制层级真正是：

```text
最上层目标
P/Q 或 V/F
        ↓
外环
        ↓
I*
“我需要多少电流”
        ↓
电流内环
        ↓
V*
“为了得到这个电流，我要产生多少电压”
        ↓
调制器
        ↓
PWM/g
“怎样开关IGBT”
        ↓
真实电路
```


---

# 18. Power Control Loop：当前 GFL 真正生效的功率外环

完整链：

```text
Pref / Qref
+
PmeasF / QmeasF
↓
功率误差
↓
两个带anti-windup的PI
↓
两维dq电流参考
↓
IdIq_refF
```

它解决的问题：

> **上层只会说“我要多少有功/无功”，但变流器最终必须控制电流，因此要把P/Q目标翻译成dq电流目标。**

---

# 19. 为什么 P/Q 外环的输出是电流参考

Two-Level Converter没有“100 kW”这个直接控制端口。

它真正能被控制的是：

```text
IGBT开关
→ 输出电压
→ 滤波电感电流
```

而在同步dq坐标中，当电压矢量被PLL固定到某一轴后：

```text
P/Q
与
两个dq电流分量
```

具有近似直接关系。

所以：

```text
目标P/Q
→ 目标dq电流
```

是最自然的级联控制结构。

【注意】不同Park定义会改变哪个轴对应P、哪个轴对应Q以及符号。当前模型的可靠事实是：

```text
P误差 → 第一dq电流通道
Q误差 → 第二dq电流通道
```

不要用别的教材强行改当前轴符号。

---

# 20. Power Control Loop 模块1：`Add`

输入符号：

```text
+ -
```

接线：

```text
Pref   → +
PmeasF → -
```

所以：

```text
eP = Pref - PmeasF
```

它回答：

> “目标有功和真实有功还差多少？”

例如：

```text
Pref = -0.60 pu
Pmeas = -0.50 pu
```

则：

```text
eP = -0.10 pu
```

表示当前还没有达到目标充电功率，PI需要继续调整电流参考。

---

# 21. 模块2：`PI regulator with anti-windup D`

输入：

```text
eP
```

参数来自 Control mask：

```text
Kp_Preg
Ki_Preg
Sample time = Ts
Output limits ≈ ±1.25
Initial value = 0
```

输出：

```text
第一dq电流参考分量
```

为什么用 PI：

```text
P项：
误差一出现立即响应

I项：
长期积累小误差，消除稳态静差
```

为什么输出要限幅：

> 设备有额定电流，不能因为功率误差大就要求无限大电流。

为什么有 anti-windup：

> 输出已经达到电流参考上限时，不能让积分器继续无限积累。

---

# 22. 模块3：`Add2`

当前接线：

```text
Qmeas → +
Qref  → -
```

所以：

```text
eQ = Qmeas - Qref
```

这个符号和很多教材常见写法不同。

**不要擅自改。**

原因：

> 当前模型的Park变换、q轴方向、Q正方向和PI输出方向是成套的；现有物理基线已验证。

---

# 23. 模块4：`PI regulator with anti-windup D1`

输入：

```text
eQ
```

参数：

```text
Kp_Preg
Ki_Preg
输出限幅约 ±1
Ts
```

输出：

```text
第二dq电流参考分量
```

---

# 24. 模块5：`Mux`

把两个标量：

```text
I1_ref
I2_ref
```

合成：

```text
IdIqrefF
```

顶层标签：

```text
[IdIq_refF]
```

这是当前 `GridOn=1` 时主 `signal switch` 真正选中的 GFL 电流参考。

---

# 25. Power Control Loop 里的 Vref/VdVq 支路：不要误认为它在控制

截图中还存在：

```text
VdVq
→ Demux
→ Cartesian to Polar

Vref
→ to-pu1

|VdVq| - Vref_pu
→ Terminator
```

以及：

```text
angle(VdVq)
→ Terminator
```

【模型事实】这条支路当前**没有回到 IdIqrefF**。

所以它属于：

```text
诊断 / 遗留 / 预留计算
```

不是当前GFL功率外环的有效闭环。

---

# 26. 模块6：`Demux`

把：

```text
VdVq
```

拆成：

```text
Vd
Vq
```

供下一模块使用。

---

# 27. 模块7：`Cartesian to Polar`

输入：

```text
Vd
Vq
```

输出：

```text
Magnitude = |V|
Angle = φ
```

本质：

```text
直角坐标 (d,q)
→ 极坐标 (幅值,角度)
```

为什么有价值：

> 同一个二维电压矢量，控制器有时更关心“有多大”和“朝哪”，而不是两个坐标分量。

在当前 Power Control Loop 中：

```text
Magnitude
→ 与Vref比较
→ 最后Terminator

Angle
→ Terminator
```

所以当前只保留了计算，不参与主控制。

---

# 28. 模块8：`to-pu1`

Gain：

```text
1/Vnom_prim
```

把：

```text
Vref
→ pu
```

目的是和已经是pu的 `|VdVq|` 在同一尺度比较。

---

# 29. 模块9：`Add1`

形成：

```text
|VdVq| - Vref_pu
```

输出送 Terminator，因此目前不影响 GFL。

---

# 30. 模块10/11：`Terminator`

明确终止当前不用的：

```text
电压幅值偏差
电压矢量角
```

它们的存在可以避免未连接端口警告，也明确原设计保留了这条观察/预留支路。

---

# 31. Power Control Loop 中的 `Scope`

`Scope1` 主要观察：

```text
Pref
Pmeas
```

另一个 Scope 用于观察 PI / Q 通道等内部量。

Scope只看，不改变闭环。

---

# 32. 带 Anti-Windup 的 PI：为什么必须深入理解

功率环、电压环、电流环都使用同类 PI。

如果只记：

```text
PI = Kp + Ki/s
```

还不够。

真实逆变器一定有：

```text
电流上限
电压上限
调制上限
```

一旦输出饱和，普通PI很容易发生积分器 windup。

---

# 33. PI内部模块1：`Inport Error`

输入就是当前控制误差：

```text
e
```

例如：

```text
Pref - Pmeas
```

或：

```text
Id_ref - Id
```

---

# 34. PI内部模块2：比例 Gain `Kp`

```text
e
→ Kp
→ Kp*e
```

作用：

> 当前误差越大，立刻给越大的修正。

特点：

```text
快
不记历史
```

---

# 35. PI内部模块3：积分 Gain `Ki`

```text
e
→ Ki
→ Ki*e
```

这不是最终积分结果，而是准备送进离散积分器的“积分速度”。

---

# 36. PI内部模块4：`Zero-Order Hold`

比例路径中使用离散保持。

作用：

> 明确按照当前100 μs控制节拍更新，保持离散控制信号在一个采样周期内不变。

---

# 37. PI内部模块5：`Discrete-Time Integrator`

正常时：

```text
I[k]
=
I[k-1] + Ki*e[k]*Ts
```

它记住历史误差。

为什么需要：

> 如果一个很小的偏差持续存在，比例项可能只给一个有限修正，系统停在有静差的位置；积分器会不断累积，直到把静差吃掉。

---

# 38. PI内部模块6：`Sum`

把：

```text
Kp*e
+
积分状态
```

合成：

```text
PI_raw
```

也就是未限幅的理论PI输出。

---

# 39. PI内部模块7：`Saturation`

将：

```text
PI_raw
```

限制在：

```text
UpperLimit
LowerLimit
```

例如 Current Regulator 常用：

```text
±1.25 pu
```

原因：

> 真实逆变器不可能产生无限大的电流/电压命令。

---

# 40. 为什么普通 PI 会 windup

假设：

```text
输出上限 = 1.25
```

理论PI因为误差太大想输出：

```text
2.0
```

Saturation只能给：

```text
1.25
```

如果积分器仍然继续：

```text
2.1
2.2
2.3...
```

内部会积下一大堆“做不到的历史命令”。

以后误差反向，输出仍会被巨大积分项顶住：

```text
恢复慢
超调
振荡
```

这就是：

```text
integrator windup
```

---

# 41. Anti-windup 的 `Compare To Zero`

当前PI内部有比较模块用于判断：

```text
误差是正还是负
```

因为：

> 输出已经在上限时，正误差会继续把输出往上推；负误差反而有利于退出上限。

---

# 42. Anti-windup 的 `Relational Operator`

它们比较：

```text
未限幅输出
与
UpperLimit / LowerLimit
```

判断是否：

```text
已经超过上限
或
已经低于下限
```

---

# 43. `Logical Operator` 与 `OR`

逻辑组合形成两种“禁止继续积分”的情况：

```text
上限已到
AND
误差还要求继续增大

OR

下限已到
AND
误差还要求继续减小
```

---

# 44. Anti-windup 的 `Switch`

正常：

```text
Ki*e
→ Integrator
```

如果继续积分只会让饱和更严重：

```text
0
→ Integrator
```

也就是：

> **把积分器临时踩住刹车。**

如果误差方向开始帮助系统退出饱和，则重新允许积分。

所以 anti-windup 不是“不积分”，而是：

> **只在积分会把饱和越推越严重时冻结。**

---

# 45. Voltage PI 中额外的 Reset 端口

Voltage Regulator / Supervisor 类 PI 还可能有外部 Reset。

作用：

```text
控制器未投入
→ 重置积分器/输出到初始工作点

控制器投入
→ 正常PI
```

它解决的是模式切换/使能管理，与 anti-windup 的饱和管理不是同一件事。

---

# 46. `signal switch`：GFL/GFM 真正的模式道岔

前面两套路径同时计算：

GFL：

```text
IdIq_refF
VdVqF
IdIqF
thetaF
```

GFM：

```text
IdIq_ref
VdVq
IdIq
wt
```

Current Regulator 必须收到同一坐标系中的一整套数据，因此不能只切一个电流参考。

---

# 47. signal switch 模块1：主 `Switch`——电流参考

输入：

```text
上端：IdIq_refF   = GFL
中间：ConnectMode
下端：IdIq_ref    = GFM
```

判据：

```text
u2 > 0.5
```

所以：

```text
ConnectMode=1 → GFL
ConnectMode=0 → GFM
```

输出：

```text
IdIq_refs
```

也就是当前真正进入电流内环的参考。

---

# 48. signal switch：Vd/Vq 两个分量的 Switch

GFL候选：

```text
VdVqF
```

GFM候选：

```text
VdVq
```

它们先通过 Selector/Demux 取出 Vd、Vq，再分别切换，最后重新 Mux：

```text
→ VdVqs
```

为什么要切：

> Current Regulator 前馈必须使用与当前电流参考相同坐标系的实际电压。

---

# 49. signal switch：Id/Iq 两个分量的 Switch

候选：

```text
GFL IdIqF
GFM IdIq
```

分别切换后重新组合：

```text
→ IdIqs
```

为什么：

> 不能拿 GFL坐标的电流参考减 GFM坐标的实际电流。

---

# 50. signal switch：角度 Switch

候选：

```text
GFL：thetaF = PLL相角
GFM：wt = Droop自生相角
```

输出：

```text
wts
```

送：

```text
Vref Generation
```

如果角度不切，最后三相调制参考会用错相位基准。

---

# 51. `Droop_On` 和 `GridOn` 的最终区别

```text
Droop_On
→ 只决定Droop是否按P/Q修正
→ 不决定实际模式

GridOn / ConnectMode
→ 成套选择GFL/GFM数据
→ 真正决定PWM最终听谁
```

当前：

```text
GridOn=1
→ GFL
```

这是当前 K12 可直接确认的。

---


# 51A. 为什么“外环输出电流参考，电流环输出电压命令”？

这是理解整个逆变器控制最关键的一层。

先不要看 dq，先看最简单的一相等效电路：

```text
变流器输出电压 v_conv
        │
        ▼
      R + L
        │
        ▼
外部网络/变压器侧电压 v_grid
```

滤波电感中的电流满足最核心的物理关系：

```text
L * di/dt
=
v_conv
-
v_grid
-
R*i
```

把它改成更直观的话：

> **电感电流变化得快还是慢，取决于“变流器这边的电压”和“外部网络那边的电压”之间有多大压差。**

---

## 51A.1 为什么“控制电流”最后要去改“电压”？

假设当前外部网络：

```text
v_grid = 1.0 pu
```

现在希望电流增加。

如果变流器也只产生：

```text
v_conv = 1.0 pu
```

忽略R时：

```text
v_conv - v_grid ≈ 0
```

于是：

```text
di/dt ≈ 0
```

电流不会明显增加。

如果希望电流向某个方向增大，就要让：

```text
v_conv - v_grid
```

出现合适的正/负压差。

例如概念上：

```text
v_conv稍微高于v_grid
→ 电感两端出现压差
→ 电流开始变化
```

所以：

> **逆变器并不能“直接命令电流跳到某个值”；它只能先改变自己输出的电压，再通过滤波电感的电压差让电流逐渐变化。**

因此 Current Regulator 的执行量自然是：

```text
dq电压命令
```

而不是另一个电流命令。

---

## 51A.2 “PI输出需要增加/减少多少dq电压”到底是什么意思？

当前：

```text
IdIq_refs - IdIqs
→ PI
→ PIdq
```

假设第一轴：

```text
I_ref = 0.60 pu
I_meas = 0.50 pu
```

说明：

```text
实际电流偏小0.10 pu
```

PI不会说：

```text
“那把电流直接改成0.60”
```

因为它没有这种物理执行端口。

它只能说：

```text
“为了把电流往0.60推，
我应该在当前基础上
把该轴电压命令再增加一点。”
```

这个：

```text
“再增加一点”
```

就是：

```text
PIdq
```

因此 PIdq 最准确的理解是：

> **电流误差对应的“附加dq电压纠偏量”。**

如果实际电流偏大，PI输出可能变负：

```text
减少该轴电压
→ 改变电感两端压差
→ 把电流往回拉
```

---

## 51A.3 为什么 GFL 的 Power Control Loop 输出电流参考？

GFL面对的是强电网：

```text
电网电压/频率已经存在
```

它真正想控制的是：

```text
“我向这个电网送/吸多少P/Q？”
```

三相功率本质上取决于：

```text
电压 × 电流
```

而在 PLL 同步 dq 坐标中，外部电压已经基本固定成一个稳定矢量。

此时要改变 P/Q，最直接、最快的中间变量就是：

```text
改变注入电网的dq电流
```

所以：

```text
Pref / Qref
↓
P/Q误差
↓
Power PI
↓
IdIq_refF
```

意思是：

> **“为了实现这个P/Q目标，我希望内层做出这些电流。”**

---

## 51A.4 为什么 GFM 的 Voltage Regulators 也输出电流参考？

GFM的外层目标变成：

```text
“我要把端口电压维持在目标值。”
```

但它同样不能直接让电压瞬间跳到目标。

端口电压会受到：

```text
负荷
滤波电容
输出电流
线路
变压器
```

影响。

要支撑/提高某个节点电压，本质上要让逆变器向该节点提供合适的电流。

所以：

```text
目标Vdq - 实际Vdq
↓
Voltage PI
↓
IdIq_ref
```

意思：

> **“为了把端口电压支撑到目标值，我下一层需要提供这些dq电流。”**

因此：

```text
GFL：
P/Q目标
→ I*

GFM：
V目标
→ I*
```

虽然外层目标不同，但最后都落到：

```text
“我要多少电流”
```

所以两种模式才能在 Current Regulator 汇合。

---

## 51A.5 为什么 Current Regulator 还需要 `VdVqs`？

现在看电感关系：

```text
L di/dt
=
v_conv
-
v_grid
-
R i
```

如果只知道：

```text
I_ref
I_meas
```

PI当然也能慢慢调。

但是它不知道：

```text
外面当前已经有一个多大的网络电压 v_grid
```

例如外部已经是：

```text
约1 pu
```

那为了维持正常电流，变流器输出电压本来就应该先在：

```text
约1 pu附近
```

而不是从0开始。

所以：

```text
VdVqs
```

就是给 Current Regulator 一个已知基础：

> **“当前外部/并网侧的dq电压已经是多少。”**

于是前馈可以直接构造：

```text
基础外部电压
+
R压降
±
L耦合
```

PI只补：

```text
实际误差造成的剩余部分
```

因此：

```text
IdIq_refs
= 我要多少电流

IdIqs
= 我现在真实有多少电流

VdVqs
= 外部网络/当前端口已经存在多少dq电压
```

三个输入职责完全不同。

---

## 51A.6 dq 下为什么还会多出“另一轴的L耦合项”？

在abc静止坐标里可以粗略看：

```text
L di/dt
=
v_conv - v_grid - Ri
```

但 dq 坐标本身在旋转。

旋转坐标变换后会额外出现：

```text
d轴方程里有q轴电流项
q轴方程里有d轴电流项
```

所以当前前馈才有：

```text
ff1 = V1 + Rff*I1_ref - Lff*I2_ref
ff2 = V2 + Rff*I2_ref + Lff*I1_ref
```

这就是：

```text
dq交叉耦合补偿
```

目的：

> 尽量让两个轴“各管各的”，减轻一个轴变化对另一个轴的干扰。

---

## 51A.7 滤波电感到底在哪里？

这句话里的“滤波电感”不是 Current Regulator 里面一个数学块。

它是 **Control System 外面的真实电气元件 `L1`**。

真实位置：

```text
Vref Generation
↓
Vpwm
↓
PWM Generator
↓
g1...g6
↓
Two-Level Converter
↓
inv测量点
↓
L1   ← 这里就是实际滤波电感/RL支路
↓
输出节点
├→ C1 并联电容
└→ Delta / Stubline / Transformer
```

所以：

```text
Current Regulator里的 Lff
```

不是物理电感本体。

它是：

> **控制器内部根据真实滤波器/等效网络建立的“电感模型前馈参数”。**

真实功率级：

```text
L1
```

真的储能、限制 di/dt、滤PWM。

控制算法中的：

```text
Lff
```

只是提前利用“我知道外面有这个电感”这一物理规律来算电压命令。

---

## 51A.8 C1 在哪里？它和电流环是什么关系？

当前真实滤波器：

```text
Two-Level Converter
↓
L1 串联
↓
节点
├→ C1 对地/中性点并联
└→ 变压器/电网
```

因此当前是：

```text
LC Filter
```

L1主要：

```text
限制高频电流
决定电流变化动态
```

C1主要：

```text
给高频纹波提供低阻抗旁路
平滑输出电压/高频分量
```

所以 Current Regulator 之所以和 `L` 特别密切，是因为：

```text
它直接控制的“电流动态”
主要被串联电感 L1 所塑造
```

---

## 51A.9 用“水流”类比把三层彻底串起来

可以把：

```text
电流
```

想成管道里的水流。

### 外环

GFL功率环：

```text
“我要送这么多功率”
→ “那我需要这么大的水流”
```

GFM电压环：

```text
“我要把水压撑到这个值”
→ “那我需要提供这么大的水流”
```

所以两个外环最终都给：

```text
目标流量 = I*
```

### 电流内环

它看到：

```text
目标流量
vs
实际流量
```

但真正能操纵的是：

```text
泵两端的压差
```

所以它输出：

```text
需要的电压 = 电气世界里的“压力差命令”
```

### 物理电感 L1

它像：

```text
有惯性的长水管
```

流量不可能瞬间跳变。

只有改变两端压力差：

```text
电流才逐渐变化
```

因此整个层级：

```text
P/Q 或 V
↓
决定需要多少 I
↓
Current Regulator
决定需要多少 V
↓
PWM/Converter
真正产生 V
↓
L1
把这个V差转换成电流变化
↓
真实I变化
↓
P/Q 或 V最终改变
```

这就是为什么当前控制器会自然形成：

```text
外环输出电流参考
内环输出电压命令
```

而不是随便设计出来的。

---

# 52. Current Regulator：真正最快的电流内环

进入它之前已经统一成：

```text
IdIq_refs
= 当前模式真正采用的dq电流参考

IdIqs
= Measurements输出并经过模式选择的实测dq电流

VdVqs
= Measurements输出并经过模式选择的实测dq电压
```

其中：

```text
IdIq_refs - IdIqs
→ 用来算电流误差

VdVqs
→ 不参与电流误差相减
→ 专门进入V/R/L前馈
→ 告诉控制器当前外部网络电压基础
```

它不关心上面到底是GFL还是GFM。

它只解决：

> **“我想要的dq电流和真实dq电流不一样，我该输出什么dq电压才能把电流尽快拉过去？”**

---

# 53. 为什么电流环必须比功率环快

功率变化最终依赖电流变化。

如果：

```text
功率外环已经连续改了三次电流目标
```

而：

```text
电流内环上一条目标还没做到
```

两个环会互相干扰。

所以级联原则：

```text
内环快
外环慢
```

【注意】当前它们都可以每100 μs执行一次，但：

```text
采样周期相同
≠
闭环动态速度相同
```

带宽由控制器增益和物理对象决定。

---

# 54. Current Regulator 模块1：`Sum`

形成：

```text
e_i
=
IdIq_ref - IdIq_meas
```

这是二维向量误差。

---

# 55. 模块2：`PI regulator with anti-windup D`

参数：

```text
Kp_Ireg
Ki_Ireg
Limits ≈ ±1.25
Ts=100 μs
```

输出：

```text
PIdq
```

物理意义：

> **根据当前电流误差，额外需要增加/减少多少dq电压。**

为什么输出是电压？

因为滤波电感中的电流变化由电感两端电压决定：

```text
v = L di/dt
```

所以要控制电流，最直接的执行量就是变流器输出电压。

---

# 56. 为什么 Current PI 之外还必须有 Feedforward

如果外部电网已经有一个电压，且滤波器有R/L，那么维持目标电流所需电压并不是0。

理论上已经知道：

```text
外部Vdq
电阻压降
dq电感耦合
```

这些没必要全等PI“发现误差以后再慢慢猜”。

所以：

```text
Feedforward
= 按已知物理模型提前算大部分正确电压

PI
= 用真实误差修正模型不准和扰动
```

---

# 57. Current Regulator：`Demux`

分别拆：

```text
VdVq_meas → V1,V2
IdIq_ref  → I1_ref,I2_ref
```

因为R/L前馈需要逐轴计算。

---

# 58. `Rtot_pu1 / Rtot_pu5`

两个 Gain：

```text
Rff
```

来源：

```text
Control mask 参数 RLff(1)
```

作用：

```text
I_ref
→ Rff*I_ref
```

提前补偿等效电阻压降：

```text
R·I
```

---

# 59. `Ltot_pu1 / Ltot_pu2`

两个 Gain：

```text
Lff
```

来源：

```text
RLff(2)
```

作用：

> 提前抵消dq旋转坐标中的电感交叉耦合。

当前 `Lff` 是模型定义好的pu前馈系数，不应在外面再随意额外乘一个ω。

---

# 60. 前馈上轴 `Add1`

符号：

```text
+ + -
```

形成：

```text
ff1
=
V1
+
Rff*I1_ref
-
Lff*I2_ref
```

含义：

```text
V1：
当前网络基础电压

Rff*I1：
本轴电阻压降

-Lff*I2：
另一轴电感交叉耦合补偿
```

---

# 61. 前馈下轴 `Add3`

符号：

```text
+ + +
```

形成：

```text
ff2
=
V2
+
Rff*I2_ref
+
Lff*I1_ref
```

两轴交叉项正负相反，是dq旋转方程本身造成的。

---

# 62. Feedforward 的 `Mux`

把：

```text
ff1
ff2
```

合成完整：

```text
Feedforward_dq
```

---

# 63. `Add2`：PI + Feedforward

最终：

```text
Vdq_raw
=
PIdq
+
Feedforward_dq
```

最通俗理解：

```text
前馈：
“根据电路方程，我猜大概需要这么多电压”

PI：
“真实执行后还差多少，我再补多少”
```

前馈提高响应速度和解耦性，PI保证鲁棒性和最终准确性。

---

# 64. Current Regulator 的 `Saturation`

把最终dq电压命令限制：

```text
约 ±1.25 pu
```

原因：

> 直流母线和调制器的电压能力有限，控制器不能要求物理上做不到的无限大交流电压。

输出：

```text
VdVq_conv
```

---

# 65. `PIdq` 为什么还单独作为输出

它进入最终 `meas` 总线。

用途：

> 观察“PI本身正在多努力纠偏”。

如果 PIdq 长期很大，可能提示：

```text
前馈模型不够准
设备接近能力边界
真实电流难以跟踪
```

它不是最终PWM命令本身。


---

# 66. Vref Generation：dq 电压命令怎样真正变成三相 PWM 参考

Current Regulator 输出的是：

```text
VdVq_conv
```

PWM Generator 需要的是：

```text
A相调制参考
B相调制参考
C相调制参考
```

所以 Vref Generation 的任务是：

```text
dq电压命令
+ 当前相角
+ DC母线电压能力
+ 三相120°关系
+ 变压器固定相移
+ 数字控制延迟补偿
↓
三相归一化调制波
```

可以把它理解成：

> **当前模型真正的“dq → abc 调制波合成器”。**

---

# 67. Vref Generation 输入1：`wt`

这里接的是顶层已经经过模式选择的：

```text
[wts]
```

当前：

```text
GFL → theta_PLL
GFM → Droop wt
```

Vref Generation本身不判断模式，它只使用最终选中的同步相角。

---

# 68. 输入2：`VdVq_conv`

来源：

```text
Current Regulator
```

含义：

```text
控制器最终希望变流器产生的dq电压命令
```

---

# 69. 输入3：`Vdc_meas`

【模型事实】当前顶层接的是：

```text
Constant Vnom_dc
```

不是动态DC测量。

所以当前更准确地说是：

```text
“按额定DC母线电压进行调制归一化”
```

---

# 70. 模块1：Gain `1/2`

```text
Vdc
→ Vdc/2
```

为什么？

理想两电平桥每个桥臂相对于直流中点的基础电压能力与：

```text
Vdc/2
```

直接相关。

所以先算：

```text
半直流母线可用电压
```

---

# 71. 模块2：Constant `Vnom_sec*sqrt(2)/sqrt(3)`

它表示：

```text
低压侧额定相电压峰值
```

因为：

```text
Vnom_sec
= 低压侧线电压RMS

Vnom_sec/√3
= 相电压RMS

×√2
= 相电压峰值
```

---

# 72. 模块3：第一个 `Product`

当前形成：

```text
(Vdc/2)
/
(Vnom_sec*sqrt(2)/sqrt(3))
```

作用：

> 计算当前直流母线可提供的电压能力，相对于额定交流相电压峰值有多大。

得到一个归一化可用电压尺度。

---

# 73. 模块4：第二个 `Product`

将：

```text
VdVq_conv
/
DC可用电压尺度
```

作用：

> 把控制器的dq电压命令换成适合PWM的归一化调制dq量。

---

# 74. 模块5：`Demux1`

把二维：

```text
[d,q]
```

拆成两个标量。

---

# 75. 模块6：`Real-Imag to Complex`

把：

```text
d
q
```

组合为：

```text
d + j q
```

它没有改变这个电压矢量的物理意义，只是换一种数学表示，方便下一步求幅值和角度。

---

# 76. 模块7：`Complex to Magnitude-Angle`

输出：

```text
|V|
φ
```

即：

```text
这个dq电压矢量有多大？
相对于同步坐标轴偏了多少角？
```

这就是 Cartesian-to-Polar 的思想。

---

# 77. 模块8：Magnitude `Saturation`

幅值限制：

```text
0 ～ 1
```

输出：

```text
ModIndex
```

`ModIndex` = 调制比。

通俗：

```text
0
→ 不使用交流调制能力

0.5
→ 使用一半量级

接近1
→ 接近正弦PWM线性调制能力上限
```

为什么不能超过1：

> 归一化调制波超过线性范围后会进入过调制，控制器要求的电压不能再按线性关系实现。

---

# 78. 模块9：Constant `[0, -2π/3, +2π/3]`

三相固定相位差：

```text
A = 0°
B = -120°
C = +120°
```

为什么存在：

> 同一个基波角必须生成三条相差120°的三相调制波。

---

# 79. 模块10：Constant `-π/6`

数值：

```text
-30°
```

截图注释：

```text
Correction for transformer D1 connection
```

这是非常关键的物理补偿。

当前反馈点：

```text
prim
= 变压器10 kV高压侧
```

而PWM执行点：

```text
Converter
= 变压器480 V低压侧
```

中间 D1 变压器带来固定30°相位位移。

所以：

> 控制器从高压侧测到的相角，不能不加换算就直接拿去生成低压侧PWM。

`-π/6` 就是在闭环中提前抵消这个固定相移。

---

# 80. 模块11：Constant `Ts*Fnom*(2*pi)`

这是：

```text
一拍数字延迟的相位提前补偿
```

顶层 Vref Generation 后还有：

```text
1/z
```

即 100 μs 延迟。

50 Hz 下这一拍相角：

```text
Δθ = 2π*50*100e-6
≈ 0.0314 rad
≈ 1.8°
```

所以在生成相角时提前加约1.8°，抵消后一拍才真正输出造成的相位滞后。

---

# 81. 模块12：`Add1`

把以下基础相角相加：

```text
当前同步角 wts
+
三相 [0,-120°, +120°]
+
D1变压器 -30°补偿
+
一拍数字延迟提前角
```

得到三相的基础角。

---

# 82. 模块13：`Add2`

再加入：

```text
dq电压矢量自身极角 φ
```

为什么还要加φ？

因为 `VdVq_conv` 并不一定正好沿着同步坐标的一条轴，它自身相对于同步坐标还有一个偏角。

所以最终相位：

```text
同步基准角
+
dq命令相对角
+
物理/数字补偿
```

---

# 83. 模块14：`Trigonometric Function` / `sin`

输入三相最终角：

```text
θa
θb
θc
```

输出：

```text
sin(θa)
sin(θb)
sin(θc)
```

也就是三相单位正弦。

---

# 84. 模块15：`Product2`

做：

```text
ModIndex
×
三相单位正弦
```

得到：

```text
Vref(3)
```

这就是三相连续调制参考。

---

# 85. 顶层 `Unit Delay (1/z)`

```text
Vref
→ 1/z
→ Vpwm
```

因此 `Vpwm` 是：

> 上一个离散拍已经确定的三相调制参考。

这与前面的 `Ts*Fnom*2π` 配套。

---

# 86. PWM Generator (2-Level)：为什么它和 Vref Generation 不是同一个东西

Vref Generation输出：

```text
连续值，例如 0.31、-0.72、0.40
```

IGBT真正需要：

```text
开 / 关
= 1 / 0
```

所以 PWM Generator 是：

> **把连续三相调制参考翻译成6路高速门极脉冲。**

---

# 87. PWM输入：`Vpwm`

三相向量：

```text
[ma, mb, mc]
```

设计范围：

```text
约[-1,1]
```

每个值表示当前这一相希望得到的归一化调制水平。

---

# 88. PWM载波与比较思想

当前：

```text
Fsw = 4 kHz
```

载波周期：

```text
250 μs
```

PWM的核心思想：

```text
低频正弦调制参考
和
高频载波
比较
```

通过每个载波周期内“开多久、关多久”改变桥臂平均输出，使低频基波跟随目标正弦。

---

# 89. PWM Generator 当前参数

【模型事实】当前配置包含：

```text
Three-phase bridge
→ 6 pulses

Modulator Mode
= Unsynchronized

Carrier frequency
= Fsw

Min/Max
= [-1,1]

Sampling
= Natural

Sample time
= Ts
```

这里不要把 `Ts=100 μs` 和 `Fsw=4 kHz` 混成一回事：

```text
Ts
= 实时离散控制更新步长

Fsw
= IGBT PWM载波开关频率
```

---

# 90. 为什么是6路门极 `g`

三相两电平桥：

```text
A相：上管 + 下管
B相：上管 + 下管
C相：上管 + 下管
```

共：

```text
6个功率开关
```

所以PWM输出：

```text
g1...g6
```

---

# 91. Two-Level Converter：整个链真正开始改变电能的地方

到PWM为止仍然是：

```text
数字控制信号
```

Two-Level Converter开始真正改变：

```text
电压
电流
功率流向
```

主要接口：

```text
DC：+ / -
AC：A / B / C
g：6路门极
BL：门极封锁
```

---

# 92. DC Voltage Source

当前每台逆变器功率级：

```text
DC Voltage Source = 1000 V
```

它提供真实直流侧电压/能量源。

Converter不创造能量，只是：

> 通过功率开关把直流侧能量组织成交流侧需要的波形，或在允许的双向条件下反向传能。

---

# 93. Converter `g` 端口

来源：

```text
PWM Generator
```

控制：

```text
哪只IGBT什么时候导通
```

因此 Control System 最终是通过：

```text
Vpwm
→ PWM
→ g
```

间接控制真实功率器件。

---

# 94. Converter `BL` 端口

当前：

```text
BL = 0
```

由 Constant 保持。

含义：

```text
不封锁门极
→ PWM脉冲正常生效
```

如果进入门极封锁状态，则即使PWM还在算，也不能正常驱动功率桥。

---

# 95. Two-Level Converter 内部物理意义

每个桥臂在不同开关状态下，把相端点连接到：

```text
+DC母线
或
-DC母线
```

于是生成两种主要电平。

通过4 kHz快速切换，占空比随50 Hz调制参考变化，低频平均效果形成需要的三相交流基波。

---

# 96. Converter 为什么输出不是漂亮正弦

功率管只有：

```text
开 / 关
```

所以桥臂原始输出包含：

```text
目标50 Hz基波
+
大量4 kHz及其倍频开关谐波
```

因此后面必须有滤波器。

---

# 97. Converter 参数中 Ron / Diode / Snubber 的意义

【模型事实】当前开关/二极管导通电阻量级约：

```text
1e-3 Ω
```

作用：

> 不把器件建成完全理想零电阻开关，保留基本导通损耗和数值合理性。

当前 snubber 参数设置使其基本不承担主要缓冲作用。

这里的参数属于功率器件模型，不是上层控制算法。

---

# 98. `inv`：Converter附近的 Three-Phase V-I Measurement

它位于功率级交流侧。

作用原本是：

```text
测低压侧局部V/I
```

但【模型事实】当前分核 K12 中：

```text
它的数值输出被Terminator终止
```

所以当前 Control 主反馈不使用这套低压本地数值测量。

**但它的电气穿越端口仍属于真实主回路。**

---

# 99. 当前滤波器到底是什么：LC，不是LCL

当前 K12：

```text
Converter
→ inv测量
→ L1串联
→ 输出节点
     ├→ C1并联支路
     └→ Delta / Transformer
```

所以是：

```text
LC Filter
```

不是 LCL。

---

# 100. L1：模块类型与作用

名称：

```text
L1
```

类型：

```text
Three-Phase Series RLC Branch
BranchType = RL
```

当前参数形式：

```text
R = 0.15*(Vnom_sec^2/Pnom)/100

L = 0.15*(Vnom_sec^2/Pnom/2/pi/60)
```

---

# 101. 为什么 L1 必须存在

电感规律：

```text
v = L di/dt
```

所以它阻止：

```text
IGBT一切换
→ 电流瞬间无限变化
```

开关频率越高，电感对高频分量阻抗越大。

因此：

```text
L1
→ 限制di/dt
→ 滤除高频电流谐波
→ 让注入电网的电流更接近正弦
```

通俗说：

> **L1是电流的“惯性轮”。**

---

# 102. 为什么 L1 还有 R

真实电感有：

```text
绕组电阻
铜耗
阻尼
```

所以模型保留R。

它还帮助：

```text
抑制LC过尖的谐振
```

---

# 103. C1：当前是什么连接

名称：

```text
C1
```

当前是：

```text
三相电容性支路
Y-grounded
```

连接在 L1 后输出节点的并联位置。

---

# 104. 为什么 C1 存在

电容阻抗：

```text
频率越高
→ 阻抗越低
```

所以高频PWM纹波更愿意：

```text
流入C支路
```

而不是继续去变压器和电网。

因此：

```text
L：
阻高频电流

C：
旁路高频纹波
```

一起形成：

```text
LC低通滤波
```

---

# 105. C1 中的小有功部分

当前 C1 模型还带很小的有功/损耗设置。

可理解为：

```text
等效损耗
阻尼
非理想性
```

避免完全无损的理想LC产生过于尖锐的共振。

---

# 106. LC之后的低压节点

经过 L1/C1：

```text
桥臂高频PWM波
```

被处理成更接近：

```text
50 Hz低频基波电压/电流
```

然后进入：

```text
低压Delta
```

---

# 107. SS低压侧 `Three-Phase V-I Measurement6`

该块位于 Delta / PMIO 与滤波节点之间。

当前：

```text
电气穿越端口继续使用
数值V/I输出不作为主Control反馈
```

所以：

> 数字输出不用，不代表可以删除电气块。

---

# 108. 为什么拆分后 Delta 必须在 SS 中显式恢复

旧模型的三相变压器块内部已经完成：

```text
高压Yg
低压Delta(D1)
```

拆分后把变压器低压绕组切开成6个端点：

```text
A_pos A_neg
B_pos B_neg
C_pos C_neg
```

SS中重新接：

```text
A节点 = A_pos + C_neg
B节点 = A_neg + B_pos
C节点 = B_neg + C_pos
```

恢复 D1 Delta。

---

# 109. Differential Stubline 的作用

每相低压绕组两个端点通过：

```text
2 with differential inputs
```

跨 SS/SM。

它不是控制通信。

它是：

> **把同一电气网络拆成多个实时任务后仍保持电压/电流边界关系的物理耦合接口。**

---

# 110. SM中的三台单相变压器

每台设备：

```text
A/B/C 三只单相变压器
```

每相参数大致：

```text
Sbase = 110000/3 VA
F = 50 Hz
V1 = 10000/sqrt(3) V
V2 = 480 V
```

高压侧组合：

```text
Yg
```

低压侧由SS重组：

```text
Delta D1
```

---

# 111. Transformer 为什么不仅是“升压”

它同时完成：

```text
1. 480 V量级 → 10 kV量级
2. 电气隔离/变比
3. Yg/D1连接关系
4. 固定30°相位位移
5. 漏抗/绕组阻抗动态
```

因此它本身也是闭环被控对象的一部分。

---

# 112. 为什么 Vref Generation 要有 `-π/6`

现在可以完整串起来：

```text
反馈：
prim在变压器高压侧

执行：
PWM在变压器低压侧

中间：
D1固定30°相移
```

所以必须提前做：

```text
-π/6
```

否则控制器使用的高压相角和低压PWM所需相角不一致。

---

# 113. `prim_*`：真正的高压侧反馈点

每台设备在 SM 有：

```text
prim_PV1
prim_PV2
prim_ESS1
...
```

当前方向：

```text
Transformer HV
→ prim ABC
→ prim abc
→ feeder
```

所以定义：

```text
设备 → 电网 = 正
```

这保证：

```text
PV发电为正
ESS放电为正
EV充电为负
```

---

# 114. 为什么 Control 主反馈用 prim，而不是 inv

当前真实链：

```text
SS Converter
→ LC
→ Delta
→ Stubline
→ SM Transformer
→ prim
```

然后：

```text
prim Vabc/Iabc
→ SM 12维向量
→ Memory / OpComm
→ SS Control
```

因此控制器看到的是：

> **设备经过逆变器、滤波、变压器以后，在10 kV并网侧真正呈现出来的结果。**

这也是论文以后 `Pmeas` 更有意义的原因。

---

# 115. Feeder / Line 为什么属于闭环

prim后还有：

```text
Line_EV2
PV2_Line
ESS2_Line
...
```

线路具有：

```text
R
L
```

因此设备输出变化会引起：

```text
线路压降
相角变化
损耗
节点之间的耦合
```

这些又会反过来改变：

```text
prim V/I
PCC V/I
```

所以线路不是“画一根线”。

它是物理系统的一部分。

---

# 116. 一台逆变器从 Pref 到 Pmeas：当前 GFL 完整走一遍

下面是第一优先级真正必须脱离图也能讲出来的过程。

### 第1步：AGC/上层改变 `Pref`

```text
Pref
→ SM 12维向量
→ SS Control
```

### 第2步：真实高压侧 `prim Vabc/Iabc` 同时进入 Control

它们代表上一轮真实电气执行结果。

### 第3步：Measurements 的 PLL 锁定电网

```text
Vabc
→ PLL
→ theta_PLL / Freq_PLL
```

### 第4步：Measurements 计算 GFL反馈

```text
V/I + theta_PLL
→ VdVqF / IdIqF

V/I + PLL基准
→ PmeasF / QmeasF
```

### 第5步：Power Control Loop 计算功率误差

```text
Pref - PmeasF
QmeasF - Qref
```

### 第6步：功率PI把P/Q误差变成 `IdIq_refF`

也就是：

```text
“为了达到目标P/Q，我需要这些dq电流。”
```

### 第7步：GridOn=1，signal switch选GFL全套

```text
IdIq_refF
IdIqF
VdVqF
theta_PLL
```

### 第8步：Current Regulator算电流误差

```text
IdIq_refF - IdIqF
→ PI
```

### 第9步：Current Regulator做R/L前馈

```text
VdVqF
+
Rff电阻压降
±
Lff交叉耦合
```

### 第10步：PI + Feedforward 得到 `VdVq_conv`

### 第11步：Vref Generation

```text
VdVq_conv
→ 幅值/角度
+ theta_PLL
+ 三相120°
- D1 30°
+ 一拍补偿
→ 三相Vref
```

### 第12步：Unit Delay

```text
Vref
→ Vpwm
```

### 第13步：PWM Generator

```text
Vpwm
→ 6路g
```

### 第14步：Two-Level Converter

```text
1000 V DC
+ g
→ 三相PWM交流
```

### 第15步：LC

```text
滤掉主要高频开关纹波
```

### 第16步：Delta / Stubline / Transformer

```text
低压交流
→ 10 kV高压
```

### 第17步：Feeder / PCC

设备真正向微网：

```text
送电或吸电
```

### 第18步：prim重新测 Vabc/Iabc

### 第19步：SM→SS重新送回 Measurements

得到新的：

```text
PmeasF
IdIqF
```

### 第20步：误差变小，控制器继续下一拍

这就是一个完整闭环。

---

# 117. 为什么 Pref 变化后 Pmeas 不会瞬间相等

中间真实存在：

```text
功率PI
电流PI
离散延迟
PWM
IGBT
L/C储能
变压器动态
线路
测量滤波
```

所以：

```text
Pref(t)
≠
Pmeas(t)瞬时相等
```

短时间差异完全可能是正常动态，而不是通信故障或设备异常。


---

# 118. Grid-Following：它到底在“跟”什么

GFL 的核心不是“功率控制”四个字。

更本质的是：

> **电压、频率、相角的基准由外部电网提供；逆变器只决定自己向这个已经存在的电网注入/吸收多少P/Q。**

链：

```text
外部电网
→ prim Vabc
→ PLL
→ theta_PLL
↓
所有GFL dq变换和最终PWM相角
都跟着theta_PLL
```

所以：

```text
PLL = 节拍器跟踪器
Power Loop = 任务分配器
Current Loop = 快速执行器
```

---

# 119. 为什么当前项目特别适合 GFL

当前基线一直连接：

```text
10 kV公共强电网
```

大电网已经提供：

```text
50 Hz
稳定电压
明确相角
```

所以当前最自然的实际主闭环就是：

```text
PLL同步
+
P/Q功率控制
```

这也是为什么15 s以后 AGC 改 Pref，可以直接通过 GFL Power Control Loop 改变设备有功。

---

# 120. GFL中三个环的职责必须分清

## PLL

回答：

```text
“外部电网现在转到哪？”
```

## Power Control Loop

回答：

```text
“为了目标P/Q，我应该要多少dq电流？”
```

## Current Regulator

回答：

```text
“为了把这个dq电流真的做出来，我应该输出多少dq电压？”
```

这三个不能混成一个“逆变器控制器”。

---

# 121. Grid-Forming：为什么需要另一套逻辑

如果进入孤岛或没有可靠强电网：

```text
外面没有一个稳定相角可以跟
```

这时还用PLL问：

```text
“电网现在是什么相位？”
```

就失去根本基准。

所以 GFM 必须自己产生：

```text
频率
相角
电压幅值
```

这就是：

```text
Droop Control
+
Voltage Regulators
```

的意义。

---

# 122. Droop Control：整体输入输出

输入：

```text
Fref
Vref
Pmeas
Qmeas
Enable = Droop_On
```

输出：

```text
Fout
theta_out
Vout
```

它的作用：

> **让逆变器具有类似电源的 P-f、Q-V 外特性，而不是只做一个听从P/Q命令的电流源。**

---

# 123. Droop P-f 模块1：`Product2`

输入：

```text
Droop_On
Pmeas
```

输出：

```text
Enable * Pmeas
```

作用：

```text
Droop_On=0
→ P下垂项归零

Droop_On=1
→ Pmeas真正参与
```

---

# 124. 模块2：Gain `-Freq_Droop`

当前等价：

```text
-Frequency_Droop/100
```

形成：

```text
-kf * Pmeas
```

物理含义：

```text
输出有功增加
→ 频率参考略下降
```

为什么要故意允许频率下降一点？

> 多台构网电源并联时，这种P-f斜率让它们根据各自功率自动形成负荷分担，而不必每100 μs由中央控制器精确分配。

---

# 125. 模块3：Gain `to-pu`

```text
Fref
→ 1/Fnom
→ Fref_pu
```

目的：

```text
统一在pu尺度做Droop运算
```

---

# 126. 模块4：Constant `Frequency_Droop/100/2`

加入：

```text
+kf/2
```

当前频率公式可以写成：

```text
f_pu
=
Fref/Fnom
-
kf*Pmeas
+
kf/2
```

因此当：

```text
Pmeas ≈ 0.5 pu
```

下垂修正的正负偏移大致居中。

也就是说当前模板把下垂工作中心放在约0.5 pu，而不是P=0。

---

# 127. 模块5：`Add2`

把：

```text
Fref_pu
-kfP
+kf/2
```

相加。

输出：

```text
GFM频率pu参考
```

---

# 128. 模块6：频率 pu → `Fout`

后面 Gain 乘：

```text
Fnom
```

得到：

```text
Fout [Hz]
```

这个量可以进入 Measurements 的 GFM 正序功率测量。

---

# 129. 模块7：Gain `2πFnom`

同一个频率pu还要转成：

```text
角速度 rad/s
```

因为：

```text
ω = 2πf
```

---

# 130. 模块8：`Discrete-Time Integrator1`

积分角速度：

```text
θ[k]
=
θ[k-1] + ω[k]*Ts
```

得到：

```text
自生相角
```

为什么：

> 频率只告诉“转多快”；PWM需要知道“当前已经转到哪一度”。

---

# 131. 模块9：Constant `2*pi` + `Math Function Mod`

角度不断积分会越来越大。

所以：

```text
theta mod 2π
```

让它回到：

```text
0～2π
```

输出：

```text
theta_out = wt
```

这就是GFM最终可以替代PLL的自生相角。

---

# 132. Droop Q-V 模块10：`Product1`

```text
Droop_On * Qmeas
```

Droop_On=0时关闭Q下垂反馈。

---

# 133. 模块11：Gain `Voltage_Droop`

当前：

```text
-Voltage_Droop/100
```

形成：

```text
-kv * Qmeas
```

物理含义：

```text
无功变化
→ 电压幅值参考发生轻微变化
```

即：

```text
Q-V droop
```

---

# 134. 模块12：`to-pu1`

```text
Vref
→ 1/Vnom_prim
→ Vref_pu
```

---

# 135. 模块13：`Add1`

形成：

```text
Vout
=
Vref_pu
+
Q droop项
```

`Vout` 是：

```text
GFM电压外环的目标电压幅值
```

还不是PWM。

---

# 136. 为什么 Droop 之后还需要 Voltage Regulators

Droop说：

```text
“我希望端电压是这个值。”
```

但真实端电压可能因：

```text
线路
负荷
LC
变压器
```

没有达到。

所以还要：

```text
目标电压 - 实际电压
→ PI
→ dq电流参考
```

即：

> **通过改变电流来真正把电压做出来。**

---

# 137. Voltage Regulators 的5个输入

当前截图/模型：

```text
1 Vq
2 Vq_ref+
3 On
4 Vd-
5 Vd_ref-
```

顶层实际：

```text
Vq_ref ← Droop Vout
Vd_ref ← Constant 0

Vd/Vq ← GFM Measurements
```

---

# 138. 为什么本模型是 `Vq_ref = Vout`、`Vd_ref = 0`

说明当前 Park 坐标约定把主要电压幅值放在：

```text
q轴
```

而不是很多教材常见的：

```text
d轴
```

两者只是坐标定义不同。

所以：

> **不要看到“Vq在控制电压”就认为模型错了。**

---

# 139. Voltage Regulator 模块1：`Sum`

形成：

```text
Vq_ref - Vq
```

---

# 140. 模块2：`Sum1`

当前形成：

```text
Vd - Vd_ref
```

符号与q支路不同，是当前模型坐标/反馈方向的一部分。

---

# 141. 模块3：On控制 `Switch`

Switch判据：

```text
u2 ~= 0
```

数据：

```text
Constant1 = 0
Constant2 = 1
```

因此：

```text
On=1
→ Reset=0
→ PI正常运行

On=0
→ Reset=1
→ PI复位
```

当前顶层：

```text
Vreg_on = 1
```

所以即使当前实际GFL，GFM两个电压PI仍在后台正常算。

---

# 142. 模块4/5：两个 `PI regulator with anti-windup`

输入：

```text
两个轴的电压误差
```

参数：

```text
Kp_Vreg
Ki_Vreg
limits ±1.25
Ts
```

输出：

```text
两个dq电流参考分量
```

---

# 143. 模块6：`Mux`

把两个PI输出合成：

```text
IdIq_ref
```

这是：

```text
GFM候选电流参考
```

---

# 144. Voltage Regulators 的 `Second-Order Filter / Scope`

当前两个PI输出还存在滤波观察支路。

【模型事实】滤波结果用于 Scope，不是正式 `IdIq_ref`。

正式输出：

```text
PI输出
→ Mux
```

---

# 145. GFM为什么最终也共用 Current Regulator

GFL外层：

```text
P/Q误差
→ IdIq_refF
```

GFM外层：

```text
电压误差
→ IdIq_ref
```

最后都变成：

```text
我要多少dq电流
```

所以后面完全可以共用：

```text
Current Regulator
Vref Generation
PWM
Converter
```

这正是当前模板设计得漂亮的地方。

---

# 146. 一台逆变器 GFM 完整闭环

```text
Supervisor给 Fref / Vref
↓
Droop
P-f / Q-V
→ Fout / Vout / self wt
↓
Measurements用self wt
→ GFM Vdq/Idq/P/Q
↓
Voltage Regulators
目标Vdq - 实际Vdq
→ IdIq_ref
↓
GridOn=0
→ signal switch选GFM全套
↓
Current Regulator
→ VdVq_conv
↓
Vref Generation使用self wt
↓
PWM
↓
Converter
↓
LC
↓
Transformer / Line
↓
prim
↓
Measurements
↓
新的V/P/Q
↓
重新进入Droop和Voltage Regulators
```

这就是真正构网闭环。

---

# 147. GFM“不要PLL”到底是什么意思

准确说法不是：

```text
GFM模型里完全没有PLL
```

当前 Measurements 的 PLL 仍然可以一直在后台算。

真正区别是：

```text
GridOn=0
→ signal switch不选theta_PLL
→ 选Droop self wt
```

所以：

> **GFM不依赖PLL作为最终控制相位基准。**

---

# 148. GFL / GFM 对照表

| 问题 | GFL | GFM |
|---|---|---|
| 相角基准 | 外部电网 | 自己生成 |
| 相角模块 | PLL | Droop积分器 |
| 频率由谁决定 | 电网/PLL | Fref + P-f Droop |
| 主要外环目标 | P/Q | V/F |
| 外环模块 | Power Control Loop | Droop + Voltage Regulators |
| 外环最终都输出 | dq电流参考 | dq电流参考 |
| Current Regulator | 共用 | 共用 |
| Vref Generation | 共用 | 共用 |
| PWM / Converter | 共用 | 共用 |
| 当前GridOn=1 | **被选中** | 后台 |
| Droop_On是否是模式选择 | 否 | 否 |
| 真正模式开关 | GridOn/ConnectMode | GridOn/ConnectMode |

---

# 149. 当前项目真实时序

```text
0～3 s：
GridOn=1
→ GFL实际执行

Droop_On=0
→ Droop P/Q下垂未投入


3 s：
Droop_On=1
→ GFM Droop开始后台计算

但GridOn仍=1
→ 实际仍GFL


5 s：
Supervisor开始根据PCC F/V动态修正 Fref/Vref

但GridOn仍=1
→ GFL仍实际执行


15 s：
AGC Enable
→ Pref开始变化

Power Control Loop真正使用Pref
→ IdIq_refF改变
→ Current Regulator
→ PWM
→ Pmeas/PCC改变
```

所以当前实际看到的：

```text
PCC -120 kW → -100 kW
```

主要体现：

```text
AGC + GFL Power Loop + Current Loop + PWM
```

---

# 150. 顶层最终 `meas` 14维：为什么存在

顶层 `Bus Creator` 把14个量组成：

```text
meas
```

它是：

> **本地Control的运行仪表盘和向上层报告接口。**

不是所有反馈必须经过的控制总线。

---

# 151. `meas` 1：`Id_ref`

来源：

```text
当前已选择 IdIq_refs
→ Selector第一分量
```

表示当前真正送入电流内环的第一dq电流参考。

---

# 152. `meas` 2：`Id`

当前已选择实际dq电流第一分量。

---

# 153. `meas` 3：`Iq_ref`

当前电流参考第二分量。

---

# 154. `meas` 4：`Iq`

当前实际电流第二分量。

---

# 155. `meas` 5：`ModIndex`

来自 Vref Generation。

表示：

```text
当前使用了多少调制能力
```

如果长期接近1：

> 说明电压指令接近调制极限。

---

# 156. `meas` 6/7：`PId / PIq`

来自 Current Regulator 的：

```text
PIdq
```

表示电流PI自身两个轴的修正输出。

---

# 157. `meas` 8：`Freq`

顶层经过模式相关 Switch 选择的当前频率状态。

---

# 158. `meas` 9：`Pmeas`

当前模式选择后的设备实际有功。

当前GFL主路径对应：

```text
PmeasF
```

这个字段最终会被 SS 中 Bus Selector 提取，上送SM形成六路Pmeas。

---

# 159. `meas` 10：`wt`

当前实际选择的相角：

```text
GFL → theta_PLL
GFM → self wt
```

---

# 160. `meas` 11：`Qmeas`

当前模式实际无功。

---

# 161. `meas` 12/13：`Vd / Vq`

当前模式对应的dq电压分量。

---

# 162. `meas` 14：`Vref`

上层/本地电压参考诊断量。

---

# 163. 最终 Bus Creator 前那些 `Selector`

黑色/小型选择块把二维向量拆出单个元素：

```text
IdIq_refs → Id_ref、Iq_ref
IdIqs     → Id、Iq
PIdq      → PId、PIq
VdVq      → Vd、Vq
```

为什么：

> Bus Creator最后需要按固定顺序打入14个标量。

---

# 164. 最终 Freq/P/Q/Vdq 的 Switch

因为 GFL/GFM 两套量一直并存，最终诊断总线也要回答：

```text
“当前实际模式对应的Freq/P/Q/Vdq是什么？”
```

所以这些量也经过 ConnectMode 相关 Switch 后再进入 `meas`。

---

# 165. `meas` 是不是快速控制反馈的必经路径

不是。

GFL Power Loop直接使用：

```text
Measurements → PmeasF/QmeasF
```

Current Regulator直接使用：

```text
signal switch → IdIqs/VdVqs
```

所以：

```text
Bus Creator meas
```

主要做：

```text
诊断
记录
上送
```

而不是“先打包再拆回控制器”。

---

# 166. 内部快速Pmeas反馈 vs 向SM上送Pmeas

必须分清。

## 内部快速反馈

```text
prim V/I
→ Measurements
→ PmeasF
→ Power Control Loop
```

这是本地功率闭环。

## 向上报告

```text
meas.Pmeas
→ SS Bus Selector
→ 两设备Pmeas Mux
→ Memory
→ SS Outport
→ SM
```

用途：

```text
Target
40109～40114
策略
未来论文执行状态
```

两者来源一致，但数据路径和用途不同。

---

# 167. 为什么这套 Control System 对论文极其重要

未来策略2要判断：

```text
设备有没有真正执行？
```

但 Control System 已经告诉我们：

```text
u_commit / Pref
↓
Power PI
↓
Current PI
↓
PWM
↓
Converter
↓
LC
↓
Transformer
↓
Line
↓
Pmeas
```

所以：

```text
Pref ≠ Pmeas
```

在短时间内可能完全正常。

不能简单：

```text
|Pref-Pmeas| > 0
→ 执行异常
```

---

# 168. 为什么后续要做 Pref→Pmeas 正常阶跃辨识

分别对：

```text
PV
ESS
EV
```

做小幅 Pref 阶跃，记录：

```text
命令变化时刻
Pmeas开始响应时刻
响应速度
超调
稳态误差
```

才能建立：

```text
正常执行应该长什么样
```

未来才能区分：

```text
正常动态滞后
vs
通信未执行
vs
设备执行不足
```

这正是未来 `Pexpected / tolerance band` 的物理基础。

---

# 169. 每个主要模块一页速查

| 模块 | 它回答的问题 | 输入 | 输出 | 当前GFL主闭环 |
|---|---|---|---|---|
| Measurements | 设备现在真实是什么状态？ | prim Vabc/Iabc、GFM Freq/wt | 两套dq/PQ/PLL | **生效** |
| PLL (3ph) | 电网频率/相角是多少？ | Vabc | Freq_PLL/theta_PLL | **生效** |
| abc→dq0 | 如何把旋转三相量变成近直流量？ | abc+angle | d/q/0 | **生效** |
| Power正序测量 | 当前基波P/Q是多少？ | V/I/Freq/angle | P/Q | **生效** |
| Power Control Loop | 为目标P/Q需要多少电流？ | Pref/Qref/P/Q | IdIq_refF | **生效** |
| Cartesian to Polar | dq矢量有多大、朝哪？ | d/q | magnitude/angle | 当前Power支路仅诊断 |
| PI anti-windup | 如何快速消误差又不积分饱和？ | error | 有限幅控制量 | **生效** |
| Droop Control | GFM应建立什么F/V/相角？ | Fref/Vref/P/Q | Fout/Vout/wt | 后台 |
| Voltage Regulators | 为目标电压需要多少电流？ | Vref/Vdq | IdIq_ref | 后台 |
| signal switch | 到底听GFL还是GFM？ | 两套信号+GridOn | 统一内环信号 | **生效** |
| Current Regulator | 怎样让实际电流跟目标？ | IdIq_ref/IdIq/Vdq | VdVq_conv | **生效** |
| R/L Feedforward | 理论上本来需要多少电压？ | Vdq/Iref/Rff/Lff | Vff | **生效** |
| Vref Generation | dq电压怎样变三相调制波？ | Vdq/wt/Vdc | Vref/ModIndex | **生效** |
| Unit Delay | 怎样明确一拍离散因果？ | Vref | Vpwm | **生效** |
| PWM Generator | 连续调制怎样变6路门极？ | Vpwm | g1…g6 | **生效** |
| Two-Level Converter | 门极怎样改变真实功率流？ | DC+g | 三相PWM电气量 | **生效** |
| L1 | 怎样限di/dt/滤高频电流？ | PWM电流 | 平滑电流 | **生效** |
| C1 | 怎样旁路高频纹波？ | 输出节点 | LC滤波节点 | **生效** |
| Delta/Stubline | 怎样跨任务保留低压绕组关系？ | 低压三相 | SM变压器边界 | **生效** |
| Transformer | 怎样升压并形成D1/Yg关系？ | 低压 | 10 kV | **生效** |
| prim | 并网高压侧真实V/I是多少？ | 电气主回路 | Vabc/Iabc数值 | **生效** |
| Feeder Line | 设备与PCC之间真实阻抗是什么？ | 电气状态 | PCC耦合 | **生效** |
| meas Bus Creator | 怎样统一报告本地状态？ | 14个量 | meas | 诊断/上送 |

---

# 170. 学完后的自检问题

1. 为什么 Pref 不能直接接 PWM？
2. 为什么 P/Q 外环最后要输出电流参考？
3. 为什么电流内环必须比功率外环快？
4. 为什么同一组 Vabc/Iabc 要算两套dq？
5. GFL相角从哪里来？
6. GFM相角从哪里来？
7. `Droop_On=1` 为什么仍可能是GFL？
8. 当前 `GridOn=1` 到底选择哪一路？
9. Current Regulator 中 PI 和 Feedforward 各解决什么？
10. `Rff/Lff` 为什么存在？
11. 为什么两个dq轴有交叉耦合？
12. Vref Generation 为什么要把dq改写成幅值/角度？
13. ModIndex是什么？
14. `-π/6` 补什么？
15. `Ts*Fnom*2π` 补什么？
16. PWM Generator和Two-Level Converter有什么本质区别？
17. 为什么Converter后必须有LC？
18. 当前到底是LC还是LCL？
19. 为什么Control主反馈使用prim高压侧V/I？
20. 为什么短时间 `Pref≠Pmeas` 不一定是故障？
21. 内部Pmeas快速反馈与向SM上报Pmeas有什么区别？
22. 为什么GFM可以保留PLL计算，但最终不用PLL相角？

能脱离截图回答这些问题，才算真正掌握。

---

# 171. 最终总图：当前一台设备 GFL 主闭环

```text
                        AGC / 上层
                           │
                      Pref / Qref
                           │
                           ▼
                  Power Control Loop
                   P/Q → IdIq_refF
                           │
                           │
prim Vabc/Iabc             │
     │                     │
     ▼                     │
┌───────────────┐          │
│ Measurements  │          │
│ PLL + dq + P/Q│          │
└───────┬───────┘          │
        │                  │
        ├→ PmeasF/QmeasF ──┘
        ├→ IdIqF
        ├→ VdVqF
        └→ theta_PLL
                  \        /
                   \      /
                    ▼    ▼
                  signal switch
                  GridOn = 1
                       │
                  选GFL全套
                       │
                       ▼
                Current Regulator
                  PI + R/L前馈
                       │
                   VdVq_conv
                       │
                       ▼
                Vref Generation
           幅值/角度 + 三相 + 补偿
                       │
                    Unit Delay
                       │
                     Vpwm
                       │
                       ▼
                 PWM Generator
                       │
                     g1~g6
                       │
                       ▼
               Two-Level Converter
                       │
                    PWM交流
                       │
                       ▼
                      L1
                       │
                 ┌─────┴─────┐
                 │           │
                C1        低频基波
                 │           │
                地         Delta
                             │
                         Stubline
                             │
                       Transformer
                             │
                           prim
                             │
                         Feeder Line
                             │
                            PCC

prim再次测Vabc/Iabc
        │
        └→ SM数字向量 → SS → Measurements
                           → 下一轮闭环
```

---

# 172. 最终总图：GFL/GFM 在哪分叉、在哪汇合

```text
                     真实 prim V/I
                          │
                    Measurements
                  /                 \
                 /                   \
                ▼                     ▼
      ┌─────────────────┐   ┌─────────────────┐
      │ GFL             │   │ GFM             │
      │ PLL             │   │ Droop           │
      │ ↓               │   │ ↓               │
      │ theta_PLL       │   │ self wt         │
      │                 │   │                 │
      │ P/Q Power Loop  │   │ Voltage Loop    │
      │ ↓               │   │ ↓               │
      │ IdIq_refF       │   │ IdIq_ref        │
      └────────┬────────┘   └────────┬────────┘
               │                     │
               └──────────┬──────────┘
                          ▼
                    signal switch
                GridOn / ConnectMode
                          │
                          ▼
                  Current Regulator
                          │
                  Vref Generation
                          │
                    PWM Generator
                          │
                    Converter + LC
                          │
                 Transformer / Line
                          │
                         PCC
```

> **分叉点：相位基准与外层控制目标。**  
> **汇合点：Current Regulator。**  
> **最终执行器：PWM + Two-Level Converter。**

---

# 173. 最后只记这一段

> **GFL模式下，PLL先从 prim 三相电压中找到外部电网相角，Measurements用这个相角把真实V/I转换成dq并算出P/Q；Power Control Loop把 `Pref/Qref` 与真实 `Pmeas/Qmeas` 比较，通过带 anti-windup 的PI生成dq电流参考；Current Regulator再比较目标电流和真实电流，并把电流PI修正与 `Vdq + Rff·I ± Lff·I` 前馈叠加，得到dq电压命令；Vref Generation根据dq电压的幅值和角度、当前同步相角、三相120°关系、D1变压器30°相移和一拍数字延迟补偿生成三相调制参考；PWM Generator把连续调制参考变成6路门极脉冲，驱动Two-Level Converter把1000 V直流侧能量变成三相PWM交流；L1/C1滤去高频，经过Delta、Stubline和单相变压器升到10 kV，经prim和馈线接到PCC；prim再把高压侧真实V/I测回来并通过SM→SS送回Measurements，于是形成真正闭环。GFM模式只是在前半段不用PLL+P/Q外环产生执行参考，而改用Droop自生频率/相角和Voltage Regulators生成电流参考；之后仍共用电流内环、调制、PWM、变流器和物理主回路。**
