# 暑期南网科技项目｜Two-Level Converter + LC Filter + 控制闭环彻底理解版
## ——从 `Pref` 到电流目标、从电流目标到电压、从PWM到真实Pmeas，再回到PCC闭环

> 对象：当前 2PV + 2ESS + 2EV 六逆变器 RT-LAB 模型中的单台逆变器功率级。  
> 主要依据：当前截图中的 `Two-Level Converter → inv → L1 → C1`，以及项目中已经确认的 Control System、PWM、Transformer、Stubline、prim/PCC 测量链。
>
> 当前项目典型参数：
>
> ```text
> 实时步长 Ts = 100 μs
> PWM开关频率 Fsw = 4 kHz
> 直流侧电压约 1000 V
> ```
>
> 本文最重要的目标不是记模块名，而是彻底理解：
>
> ```text
> 功率目标
> ↓
> 电流目标
> ↓
> 电压目标
> ↓
> PWM
> ↓
> IGBT开关
> ↓
> LC滤波
> ↓
> 真实电流与功率
> ↓
> Pmeas / PCC反馈
> ```


---

# 1. 先把截图一句话看懂

截图从左到右是：

```text
直流电源
↓
Two-Level Converter
输入：g、BL
输出：A/B/C三相PWM电压
↓
inv
逆变器侧三相测量
↓
L1
三相串联滤波电感
↓
滤波输出节点
├─ 向后接变压器 / Stubline / PCC
└─ C1三相并联到地/公共参考
```

这一块的本质是：

> **把直流能量通过高速开关变成可控三相交流，再用LC滤掉高频开关纹波，使输出能够进入变压器和交流电网。**

---

# 2. Two-Level Converter到底是什么

可以把它理解成：

> **一个由6个功率开关器件组成的高速电子换向器。**

它不直接接受“30 kW”这种功率命令，而是接受：

```text
直流电压
+
六路门极脉冲g
```

然后通过6个IGBT不断开关，在A/B/C端生成高速PWM三相电压。

所以它真正完成：

```text
DC
↓
可控三相PWM AC
```

---

# 3. 为什么叫“两电平”

每一相桥臂由：

```text
上管
+
下管
```

组成。

以A相为例，桥臂中点会在直流母线的两个主要电平之间切换，因此叫：

> **Two-Level，两电平。**

三相各两只功率开关：

```text
A相：2只
B相：2只
C相：2只
```

合计6只。

---

# 4. 当前块的外部端口

## 4.1 左侧 `+ / -`

是直流母线输入。

当前模型中直流侧约为：

```text
1000 V DC
```

它是能量来源。

## 4.2 顶部 `g`

`g` 是 Gate，门极脉冲。

最终通常对应：

```text
g1 ... g6
```

六路0/1信号。

它们来自：

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
```

所以：

> 真正决定IGBT什么时候开、什么时候关的是 `g`，不是Pref。

## 4.3 `BL`

当前截图中：

```text
BL = 0
```

可以把它理解成变流器的阻断/封锁类输入。

当前条件下没有触发阻断，六个功率器件由 `g` 正常控制。

## 4.4 A/B/C

这是三相真实电气端口，不是普通Simulink数值线。

它们承载真实：

```text
电压
电流
瞬时功率
```

---

# 5. Two-Level Converter内部实际上在做什么

假设A相想产生一个正方向的平均交流电压。

PWM会控制A相上下管在一个开关周期内的导通比例。

可以简单理解：

```text
上管导通时间更长
→ A相平均电压更正

上管导通时间更短
→ A相平均电压降低
```

因此控制器真正调的是：

> **占空比，也就是每个开关周期中各开关状态持续多长时间。**

这就是为什么 `Modulation Index`（调制度）和相角最终能决定三相基波电压。

---

# 6. 为什么Converter输出不是天然正弦

IGBT本质只有：

```text
开
关
```

所以桥臂直接输出的是高频PWM脉冲电压，不是漂亮正弦。

但是这些脉冲的：

```text
平均值 / 基波分量
```

按照控制器希望的正弦规律变化。

因此：

> **PWM用高速0/1切换，在平均意义上合成需要的三相交流基波。**

---

# 7. 为什么后面一定要LC Filter

如果把桥臂PWM电压直接送进变压器和电网，会带来：

- 高频电流纹波；
- 开关谐波；
- 电磁干扰；
- 对变压器、线路和电网不友好的高频能量。

所以必须增加滤波器。

当前截图：

```text
Converter
↓
L1 串联
↓
输出节点
├─ 后续交流网络
└─ C1 并联
```

---

# 8. L1到底干什么

电感最重要的物理特性：

> **电流不能瞬间突变。**

对一相，可以用下面这条关系理解：

```text
L * di/dt
≈
v_converter - v_grid - R*i
```

翻译成人话：

> **电流变化得多快，取决于电感两端有多少电压差。**

这是理解电流内环最关键的物理基础。

L1还有第二个作用：

```text
阻碍高频电流快速变化
```

所以PWM高频电压虽然很尖锐，但通过L1后，高频电流纹波会明显减小。

---

# 9. C1到底干什么

电容对高频分量更容易形成旁路。

因此：

```text
L1
→ 阻挡高频电流继续向电网传播

C1
→ 为高频分量提供旁路
→ 平滑输出节点电压
```

两者组合形成LC低通滤波。

---

# 10. L1 + C1结合起来做什么

整体可以理解为：

```text
Converter产生高频PWM电压
↓
L1限制高频电流
↓
C1旁路高频电压分量
↓
保留以50 Hz基波为主的交流量
↓
进入Transformer / Grid
```

所以：

> **Converter负责制造可控交流，LC负责把高速开关交流整理成电网能接受的交流。**

---

# 11. `inv`是什么

截图中：

```text
Two-Level Converter
↓
inv
↓
L1
```

`inv` 是逆变器侧三相V/I测量位置。

它主要观察：

```text
Converter输出侧电压
Converter输出侧电流
```

它不会主动调节功率。

真实电气功率继续沿A/B/C端口向后传递。

---

# 12. 为什么“功率外环 → 电流参考”

这是整个控制结构最重要的一层。

AGC或上层给出：

```text
Pref = 40 kW
```

它表达的是：

> 我希望这台设备最终输出40 kW有功。

但IGBT并不能直接执行“40 kW”。

功率是由：

```text
电压
×
电流
```

共同形成的。

三相系统在dq坐标中通常可写成类似：

```text
P ∝ vd*id + vq*iq

Q ∝ vq*id - vd*iq
```

具体正负号和d/q主轴取决于当前模型自己的坐标约定。

但核心不变：

> **要改变P/Q，最终必须改变注入交流网络的电流。**

---

# 13. 为什么跟网时电流尤其适合作为外环输出

当前GFL运行时，外部强电网已经提供：

```text
电压幅值
频率
相角
```

所以设备不需要从零建立整个电网电压。

这时候要改变自己和电网交换多少有功、无功，最直接的办法就是：

```text
改变注入电流的大小和相位
```

所以自然形成：

```text
P/Q目标
↓
Power Control Loop
↓
Id/Iq_ref
```

---

# 14. 一个直观例子

假设电网电压基本不变。

PV希望：

```text
20 kW → 40 kW
```

那么控制器需要增加对应有功方向的交流电流分量。

于是：

```text
Pref ↑
↓
功率误差增加
↓
P/Q外环
↓
I_ref增加
```

所以：

> **功率外环做的是把“我要多少功率”翻译成“我需要多少交流电流”。**

---

# 15. 为什么不让功率外环直接输出PWM

因为功率是宏观目标，而PWM是微秒/毫秒级器件动作。

中间还缺：

```text
电流状态
电网电压
滤波电感
dq相角
调制关系
```

所以必须逐层翻译：

```text
功率
↓
电流
↓
电压
↓
调制
↓
门极开关
```

---

# 16. 为什么“电流内环 → 电压命令”

假设功率外环已经给出：

```text
Id_ref / Iq_ref
```

但真实电流还没到。

比如：

```text
目标 = 100 A
实际 = 70 A
```

控制器不能直接把物理电流改成100 A。

因为L1电流不能瞬间跳变。

真正能操纵的是：

```text
Converter输出电压
```

再次看：

```text
L * di/dt
≈
v_converter - v_grid - R*i
```

如果变流器输出电压相对外部电压提高到合适程度：

```text
di/dt > 0
```

电流就会增加。

如果降低：

```text
di/dt < 0
```

电流就会下降。

所以：

> **电流内环输出电压命令，本质是在决定给L1施加多大的电压差，从而控制电流变化速度。**

---

# 17. 这条因果关系必须记住

不是：

```text
电流误差
↓
直接改电流
```

而是：

```text
电流误差
↓
计算需要多少电压
↓
Converter输出电压改变
↓
L1两端压差改变
↓
di/dt改变
↓
真实电流向目标靠近
```

---

# 18. Current Regulator为什么还需要VdVqs

当前Current Regulator的三个核心输入可以理解为：

```text
IdIq_refs
= 目标dq电流

IdIqs
= 实测dq电流

VdVqs
= 实测dq电压
```

电流误差：

```text
IdIq_refs - IdIqs
↓
PI
↓
PIdq
```

`PIdq` 可以理解为：

> 为了纠正当前电流误差，还需要额外补多少dq电压。

但外部网络本身已经存在交流电压。

所以还需要：

```text
VdVqs
```

作为基础前馈。

可以理解为：

```text
外面本来已经有多少电压
+
R/L物理模型补偿
+
PI残差修正
↓
最终VdVq_conv
```

---

# 19. 前馈与PI怎么分工

可以把电流内环理解成：

```text
VdVqs
= 外部网络当前基础电压

+

Rff/Lff补偿
= 根据模型提前估算需要的额外压差

+

PI
= 把模型没算准的剩余误差修掉

↓

VdVq_conv
```

所以：

> **前馈负责提前按物理规律猜得接近，PI负责把剩余误差修正掉。**

---

# 20. L1和Lff不是同一个东西

```text
L1
= 真实电气网络中的物理滤波电感

Lff
= 控制器内部前馈计算使用的等效电感参数
```

所以：

```text
L1 = 现实
Lff = 控制器脑子里的模型
```

---

# 21. 从Pref开始完整串一次

假设：

```text
PCC目标 = -100 kW
当前PCC = -120 kW
```

AGC认为微网净输出还需增加。

于是给PV1更高的Pref。

## 第一步：Power Control Loop

比较：

```text
Pref
vs
Pmeas
```

若：

```text
Pref > Pmeas
```

则提高相应dq电流参考：

```text
IdIq_ref
```

## 第二步：Current Regulator

比较：

```text
IdIq_ref
vs
IdIq_meas
```

然后计算：

```text
VdVq_conv
```

即：

> 为了让真实电流向目标靠近，Converter应该产生什么dq电压。

## 第三步：Vref Generation

将：

```text
VdVq_conv
+
当前角度wts
+
DC母线电压
```

变成三相连续调制参考：

```text
Va_ref
Vb_ref
Vc_ref
```

当前模型再经过 `1/z`，形成：

```text
Vpwm
```

## 第四步：PWM Generator

把连续Vpwm与4 kHz载波比较，生成：

```text
g1...g6
```

## 第五步：Two-Level Converter

6路门极信号控制IGBT高速开关：

```text
1000 V DC
↓
三相PWM交流电压
```

## 第六步：L1

Converter电压与外部网络电压形成压差：

```text
ΔV
```

作用在L1上，于是：

```text
di/dt
```

改变，真实三相电流开始向目标靠近。

## 第七步：C1

旁路高频分量，平滑交流节点电压。

## 第八步：后续真实电气网络

滤波后：

```text
Delta
↓
Differential Stubline
↓
SM中的Transformer
↓
prim
↓
Feeder
↓
PCC
```

## 第九步：重新测量

prim真实Vabc/Iabc测得后：

```text
SM → SS
↓
Measurements
↓
Pmeas / Qmeas / IdIq / VdVq
```

再次进入下一控制周期。

---

# 22. 真正的单设备闭环

```text
Pref/Qref
↓
Power Loop
↓
Iref
↓
Current Loop
↓
V*
↓
Vref Generation
↓
PWM
↓
Converter
↓
LC
↓
Transformer / Grid
↓
真实I/P/Q
↓
Measurements
└──────────────→ 再反馈到Power Loop / Current Loop
```

所以真正的闭环不是“Pref进去，PWM出来”就结束。

而是：

> **命令 → 真实功率级执行 → 测量真实结果 → 再修正。**

---

# 23. 为什么外环慢、内环快

功率外环关心：

```text
我要多少P/Q
```

属于较慢的系统目标。

电流内环关心：

```text
当前电流与目标电流差多少
```

是更接近功率器件的快速状态。

PWM更快。

所以典型层级：

```text
功率外环
慢
↓
电流内环
快
↓
PWM / Converter
更快
```

---

# 24. 为什么AGC绝不能直接控制PWM

AGC知道的是：

```text
PCC还差多少kW
```

但它不知道每个实时小步中：

```text
dq相角
真实电流
外部电压
滤波电感状态
IGBT具体开关时刻
```

所以AGC只应该决定：

```text
Pref
```

后面由本地快速控制器逐层翻译。

可以类比：

```text
AGC
= 总经理：这个部门多承担20 kW

Power Loop
= 部门经理：那需要这样的目标电流

Current Loop
= 现场主管：那需要这样的目标电压

PWM
= 班组长：六个IGBT这样开关

Converter
= 真正执行开关动作
```

---

# 25. 放回六设备项目

六台：

```text
PV1
PV2
ESS1
ESS2
EV1
EV2
```

每台都有自己的：

```text
Control System
↓
PWM
↓
Two-Level Converter
↓
LC
↓
Transformer
↓
Pmeas
```

AGC只在更上层产生六路Pref。

于是整体是：

```text
PCC目标
↓
AGC
↓
6路Pref
├─ PV1本地快速闭环
├─ PV2本地快速闭环
├─ ESS1本地快速闭环
├─ ESS2本地快速闭环
├─ EV1本地快速闭环
└─ EV2本地快速闭环
↓
六台真实功率共同形成PCC
↓
PCC重新反馈AGC
```

---

# 26. 三个时间尺度必须一起理解

## 电力电子实时层

```text
100 μs
```

包括：

```text
Current Regulator
PWM / Converter
电气网络
```

## 设备功率动态层

当前专门辨识表明，三类设备主要90%响应大约：

```text
0.9～1.5 s
```

## AGC协调层

```text
1 s更新
```

所以会出现：

> **下一轮AGC已经到来，但上一轮Pref造成的真实功率可能还没完全到位。**

因此：

```text
Pref ≠ Pmeas
```

短时间内完全可能是正常动态，不是故障。

---

# 27. 这和论文策略2有什么关系

基础AGC可能：

```text
1 s前给新Pref
↓
1 s后PCC仍有误差
↓
马上继续追加或反向调节
```

但真实设备可能：

```text
上一条命令
↓
Power Loop
↓
Current Loop
↓
Converter
↓
LC
↓
Transformer
↓
Pmeas
仍处于正常响应中
```

如果控制器不能区分：

```text
正常响应中
vs
真正执行异常
```

就可能过早追加或反向修正。

这就是策略2未来需要重点处理的执行状态评估问题之一。

---

# 28. 最推荐记住的三句话

### 第一句

> **功率是最终目标。**

### 第二句

> **电流是实现功率交换的直接中间变量。**

### 第三句

> **电压是推动滤波电感电流变化的直接执行量。**

因此：

```text
功率目标
↓
电流目标
↓
电压目标
↓
PWM
↓
IGBT
↓
真实电流
↓
真实功率
```

---

# 29. 看到当前截图时应该马上想到什么

```text
DC source
→ Two-Level Converter
→ inv
→ L1
→ C1
```

应立即解释为：

### Two-Level Converter

```text
直流 + 六路g
↓
三相PWM交流电压
```

### inv

```text
逆变器侧V/I测量
```

### L1

```text
串联电感
限制di/dt
抑制高频电流
也是电流控制真正作用的物理对象
```

### C1

```text
并联电容
旁路高频分量
平滑节点电压
```

### LC整体

```text
把高速PWM输出
整理成适合Transformer / Grid的交流量
```

---

# 30. 闭眼自测

1. Two-Level Converter为什么需要直流侧？
2. “两电平”是什么意思？
3. g是什么？为什么有六路？
4. BL在当前模型里属于什么类型的输入？
5. A/B/C是普通信号还是电气端口？
6. Converter为什么产生PWM而不是天然正弦？
7. L1为什么串联？
8. C1为什么并联？
9. LC怎样滤掉高频开关分量？
10. inv为什么不会主动改变功率？
11. Pref为什么不能直接送给PWM？
12. 功率外环为什么输出电流参考？
13. 电流内环为什么输出电压命令？
14. 为什么改变Converter电压就能改变真实电流？
15. L1和Lff有什么区别？
16. VdVqs为什么进入前馈？
17. PI和前馈分别干什么？
18. VdVq_conv怎样变成Vpwm？
19. PWM Generator和Converter分别干什么？
20. Converter + LC怎样继续连到Transformer / Stubline？
21. Pmeas从哪里重新测回来？
22. 为什么要把Pmeas反馈给功率外环？
23. 为什么六台设备都要自己的快速本地闭环？
24. 为什么AGC只管Pref，而不直接管IGBT？
25. 为什么1 s AGC到来时上一条Pref可能仍在正常响应？
26. 这件事为什么会影响策略2和论文方向？

---

# 31. 最后一条主线

```text
AGC：
“这台设备应该出多少功率？”
↓
Pref
↓
Power Loop：
“为了这个功率，我需要什么dq电流？”
↓
IdIq_ref
↓
Current Regulator：
“为了让真实电流达到目标，
Converter应该产生什么dq电压？”
↓
VdVq_conv
↓
Vref Generation：
“这个dq电压对应什么三相连续调制参考？”
↓
Vpwm
↓
PWM Generator：
“六个IGBT每一刻怎么开关？”
↓
g1...g6
↓
Two-Level Converter：
“把直流切成三相PWM交流电压”
↓
L1：
“利用压差控制真实电流变化，并抑制高频电流”
↓
C1：
“旁路高频分量、平滑节点电压”
↓
Transformer / Stubline / Feeder
↓
真实交流功率进入PCC
↓
prim / Measurements重新测量
↓
Pmeas
↓
功率外环再次比较Pref
↓
AGC再根据PCC重新协调
```

一句话压缩：

> **功率外环把“功率要求”翻译成“电流要求”；电流内环再把“电流要求”翻译成“电压要求”；PWM和Two-Level Converter把“电压要求”变成真实开关电压；L1/C1把高速PWM整理成可用交流；真实电流和功率形成以后再测回来，闭环才真正完成。**
