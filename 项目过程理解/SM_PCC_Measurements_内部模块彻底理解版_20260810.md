# 暑期南网科技项目｜SM 中 PCC Measurements 模块彻底理解版

> 对象：当前 `SM_Master` 中的 `J2_PCC_Measurements / PCC Measurements`。  
> 输入：`Ipcc`、`Vpcc`，均为三相瞬时实际量。  
> 输出：  
> `Out1 = Freq_pcc`  
> `Out2 = Ppcc_kW`  
> `Out3 = Qpcc_kvar`  
> `Out4 = Vab_rms_pcc`  
>
> 本文按当前截图解释各模块的作用和串联关系。对于截图中看不到具体参数值的 Gain/限幅块，只解释其确定的功能，不凭图猜具体数值。

---

# 1. 这个 PCC Measurements 总体上是干什么的

PCC处原始测量块给出来的是：

```text
Vpcc = [Va, Vb, Vc]
Ipcc = [Ia, Ib, Ic]
```

它们是三相**瞬时波形**。

例如50 Hz电压本身一直在正弦变化：

```text
Va(t)
Vb(t)
Vc(t)
```

这些瞬时波形虽然最真实，但上层控制和AGC真正想要的是：

```text
现在频率是多少？
现在PCC有功是多少？
现在PCC无功是多少？
现在PCC线电压RMS是多少？
```

所以 `PCC Measurements` 本质上是一个：

> **“把三相瞬时电压、电流，加工成上层控制可以直接使用的四个稳定工程量”的测量处理器。**

总体链路：

```text
Vpcc / Ipcc
    │
    ├────────→ PLL ───────→ Freq_pcc
    │           │
    │           ├→ Freq
    │           └→ wt
    │                │
    │                ├──────────────┐
    │                │              │
    ▼                ▼              ▼
线电压Vab提取   正序功率计算      基波幅值提取
    │                │              │
    │             P / Q             │
    │                │              │
    ▼                ▼              ▼
Vab_rms_pcc      Ppcc_kW        Qpcc_kvar
```

更准确地说：

```text
PLL先告诉其它测量算法：
“当前电网基波到底以多快的速度、什么相角在旋转。”

然后功率和RMS测量都围绕同一套基波参考计算。
```

---

# 2. 两个输入：Vpcc 与 Ipcc

## 2.1 Vpcc

输入：

```text
Vpcc
宽度 = 3
```

就是：

```text
[Va, Vb, Vc]
```

三相PCC相电压瞬时值。

当前PCC三相V-I测量块已经配置为：

```text
Voltages in pu = off
```

所以这里进入的是**实际电压值**，不是pu。

它有三个主要用途：

```text
① PLL识别频率和相角
② 与Ipcc一起计算P、Q
③ 计算Vab线电压有效值
```

---

## 2.2 Ipcc

输入：

```text
Ipcc
宽度 = 3
```

就是：

```text
[Ia, Ib, Ic]
```

三相PCC瞬时电流。

当前：

```text
Currents in pu = off
```

所以同样是实际物理电流。

它主要进入：

```text
Power (PLL-Driven, Positive-Sequence)
```

和Vpcc共同计算PCC有功和无功。

---

# 3. 为什么不能直接由瞬时 V、I 给 AGC

假设：

```text
Va
Ia
```

都在50 Hz正弦变化。

即使系统功率已经完全稳定：

```text
Va(t)
Ia(t)
```

还是每20 ms变化一个完整周期。

如果把这种瞬时值直接给AGC：

```text
AGC会看到大量快速交流波动
```

而AGC关心的是慢很多的：

```text
PCC有功
频率
RMS电压
```

所以必须经过：

```text
基波同步
正序提取
功率计算
RMS/幅值处理
```

得到适合上层控制的量。

---

# 4. Vpcc → Gain → PLL：为什么先有一个 Gain

截图中：

```text
Vpcc
↓
Gain
↓
PLL
```

这里的 Gain 可以理解为：

> **给PLL使用的电压尺度预处理/归一化。**

PCC原始电压处于10 kV等级。

PLL真正关心的核心不是：

```text
“现在到底是10000 V还是10020 V”
```

而是：

```text
三相电压当前相位在哪里？
频率是多少？
```

因此通常会先把电压换成适合PLL数值计算的尺度。

这样有两个好处：

```text
1. 避免PLL直接处理上万伏数量级
2. PLL参数更容易按照统一标幺尺度设计
```

> 截图看不到这个 Gain 的具体数值，因此不要凭图猜它具体等于多少；它在这里确定承担的是PLL输入尺度变换。

---

# 5. PLL 是整个 PCC Measurements 的“时钟和角度基准”

PLL输入：

```text
三相Vpcc
```

输出：

```text
Freq
wt
```

可以把PLL理解成一个一直盯着PCC三相电压的“同步观察器”。

它不断回答两个问题。

---

## 5.1 Freq

```text
Freq
```

表示当前PCC基波频率。

正常并网附近应该约：

```text
50 Hz
```

如果系统发生频率偏移，它会跟踪这个变化。

---

## 5.2 wt

```text
wt
```

表示当前基波的电气相角。

简单理解：

```text
Freq
告诉你“转得有多快”

wt
告诉你“现在转到哪了”
```

例如频率一直是50 Hz，并不代表你知道现在A相：

```text
是在0°
90°
还是180°
```

所以功率正序算法不仅需要频率，还需要相角。

---

# 6. 为什么 PLL 输出的 Freq 后面还有一个处理块

图中PLL的 `Freq` 输出之后还有一个带折线图标的处理块，然后才送到：

```text
Freq_pcc
Power模块
基波幅值模块
```

从整体功能上，它属于：

> **对PLL频率结果做合理范围约束/后处理，使后续模块使用稳定的频率量。**

它的目的不是重新计算另一套频率，而是：

```text
PLL原始Freq
↓
合理化处理
↓
统一的Freq_pcc
```

然后这同一个频率被送给：

```text
P/Q测量
Vab基波/RMS测量
```

这样整个PCC Measurements采用同一个频率参考。

---

# 7. 第一输出 Freq_pcc 是怎样来的

链路：

```text
Vpcc
↓
电压尺度处理
↓
PLL
↓
Freq
↓
频率后处理
↓
Freq_pcc
```

所以：

```text
Freq_pcc
```

不是人为固定的50 Hz。

它是：

> **根据当前PCC三相电压实时估计出来的实际基波频率。**

这个量后面可以用于：

```text
SC在线观察
15项策略
Supervisory相关判断
系统频率状态分析
```

---

# 8. P/Q计算为什么用 `Power (PLL-Driven, Positive-Sequence)`

这是PCC Measurements中最核心的功率块。

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

---

# 9. 为什么这个模块既要 V/I，又要 Freq/wt

如果只是最简单的瞬时功率：

```text
p(t) = va·ia + vb·ib + vc·ic
```

理论上只需要V、I。

但这里使用的是：

```text
PLL-Driven
Positive-Sequence
```

它的目标不是简单输出含有所有交流波动、谐波和不平衡成分的瞬时功率。

它要得到更适合作为上层控制反馈的：

> **基波正序有功P和无功Q。**

PLL提供：

```text
Freq
wt
```

相当于告诉功率测量：

```text
“当前真正的基波参考就在这里。”
```

于是模块可以围绕当前基波进行同步计算。

---

# 10. 为什么强调 Positive-Sequence

真实三相系统可能出现：

```text
谐波
三相不平衡
暂态扰动
高频PWM影响
```

如果上层AGC直接使用含大量这些成分的瞬时功率：

```text
PCC反馈会很抖
```

正序功率测量更关注：

```text
三相系统的基波正序主体
```

所以它非常适合：

```text
PCC功率协调
AGC
Supervisory
运行状态评价
```

可以把它理解为：

> **“我不把所有高频细节都拿给AGC，而是把代表整个三相系统主工作状态的P/Q提取出来。”**

---

# 11. P输出后的 Gain：为什么还要再处理

Power模块输出：

```text
P
```

但最终接口明确叫：

```text
Ppcc_kW
```

所以后面的 Gain 负责：

> **把Power模块内部输出尺度转换成项目统一的kW工程量，并保持项目规定的功率方向。**

可能包含：

```text
W → kW
```

以及模型原有测量方向所需的符号适配。

当前项目最终统一的PCC约定是：

```text
Ppcc > 0
= 微电网向上级电网送电

Ppcc < 0
= 微电网从上级电网购电
```

例如正常两台EV充电基线：

```text
Ppcc ≈ -120 kW
```

表示：

```text
微电网从大电网购电约120 kW
```

---

# 12. Q输出后的 Gain

完全同理。

Power模块输出：

```text
Q
```

后面的Gain把它转换为项目需要的：

```text
Qpcc_kvar
```

因此：

```text
Power内部Q
↓
单位/尺度处理
↓
Qpcc_kvar
```

---

# 13. 第二、第三输出完整链路

因此P/Q完整链为：

```text
Vpcc
  │
  ├→ PLL → Freq / wt ──────────────┐
  │                                │
Ipcc ───────────────────────────┐   │
                               ▼   ▼
                 Power (PLL-Driven,
                 Positive-Sequence)
                         │
                    ┌────┴────┐
                    │         │
                    P         Q
                    │         │
                  Gain      Gain
                    │         │
                    ▼         ▼
              Ppcc_kW   Qpcc_kvar
```

---

# 14. Vab_rms 为什么不能直接取 Va

PCC额定电压通常讨论的是：

```text
三相线电压
```

例如系统说：

```text
10 kV
```

指的是：

```text
线电压RMS
```

不是单相对地的瞬时 `Va(t)`。

因此这里专门从三相Vpcc中取：

```text
Va
Vb
```

计算：

```text
Vab = Va - Vb
```

再去计算其基波有效值。

---

# 15. 左上黑色竖条模块在做什么

截图中：

```text
Vpcc（三维）
↓
黑色竖条
↓
两路标量
```

从接线功能看，它负责：

> **从三相电压向量中拆出计算Vab所需的相电压分量。**

也就是从：

```text
[Va, Vb, Vc]
```

中取出需要的两相。

第三个不用于Vab计算的分量被终止/不继续使用。

---

# 16. `+ / -` 求和块为什么存在

随后两个相电压进入：

```text
+
-
```

因此得到：

```text
Vab = Va - Vb
```

这一步非常关键。

因为：

```text
Va
```

是相对中性点/地的相电压。

而：

```text
Vab
```

才是A、B两相之间的线电压。

所以这里是在完成：

```text
三相相电压
→ 一路线电压 Vab
```

---

# 17. 为什么 Vab 还是不能直接作为 Vab_rms_pcc

因为：

```text
Vab(t)
```

仍然是一个50 Hz正弦瞬时波形。

例如稳定的10 kV RMS系统中，Vab瞬时值仍会：

```text
正
→ 0
→ 负
→ 0
→ 正
```

不停变化。

而我们真正需要的是：

```text
Vab_rms
≈ 一个稳定的正数
```

所以还必须做基波幅值/RMS提取。

---

# 18. `Freq / wt / In → |u| / ∠u` 模块是什么作用

截图中该模块输入：

```text
Freq
wt
In
```

输出：

```text
|u|
∠u
```

其中：

```text
In = Vab
```

它的功能可以理解成：

> **利用PLL给出的当前基波频率和相角，从Vab瞬时波形中提取其基波幅值和相位。**

所以：

```text
Freq / wt
= 当前基波参考

Vab
= 要分析的瞬时线电压

|u|
= 基波幅值

∠u
= 基波相角
```

当前系统这里只需要电压大小，所以：

```text
|u|
继续向后使用
```

而：

```text
∠u
```

没有作为最终PCC Measurements输出，因此被终止。

---

# 19. 为什么不能简单 `abs(Vab)`

如果直接：

```text
abs(Vab(t))
```

它仍然会随时间起伏。

并不是RMS。

例如一个标准正弦：

```text
v(t)=Vm sin(ωt)
```

其：

```text
|v(t)|
```

仍然在：

```text
0 ~ Vm
```

之间变化。

真正的RMS是：

```text
Vm / √2
```

所以必须做：

```text
基波幅值提取
+
适当的RMS尺度换算
```

---

# 20. `|u|` 后面的 Gain 为什么存在

该幅值模块输出的：

```text
|u|
```

要按照它自身的幅值定义转换成最终：

```text
Vab_rms_pcc
```

因此后面的 Gain 负责：

> **把基波幅值按模块定义转换/标定成实际线电压RMS工程量。**

通常这类转换会涉及：

```text
峰值 → RMS
和/或
内部尺度 → 实际电压尺度
```

但当前截图看不到Gain的具体参数，所以这里不凭图写死：

```text
K = 1/√2
```

或其它数值。

真正需要确认具体数值时，应打开该Gain的 Block Parameters。

---

# 21. 第四输出完整链路

完整的线电压RMS链：

```text
Vpcc = [Va,Vb,Vc]
        │
        ▼
   选择 Va、Vb
        │
        ▼
    Va - Vb
        │
        ▼
      Vab(t)
        │
        │      PLL
        │   Freq / wt
        │      │
        └──────┼─────────┐
               ▼         │
        基波幅值/相位提取
               │
             |u|
               │
             Gain
               │
               ▼
        Vab_rms_pcc
```

---

# 22. 为什么功率测量和电压RMS都共用PLL

这是整个结构设计得比较合理的一点。

如果：

```text
P/Q使用一套频率
Vab RMS使用另一套频率
```

那么当系统频率发生轻微偏移时，各测量量可能对“当前基波”理解不一致。

当前结构统一使用：

```text
同一个PLL
→ Freq
→ wt
```

再分给：

```text
Power
Vab基波幅值
```

所以：

> **Freq、P、Q、Vab_rms四个输出来自同一个基波同步参考。**

这样更适合后续：

```text
Supervisory
AGC
15项策略
SC显示
Target日志
```

做一致判断。

---

# 23. 四个输出分别回答什么问题

## Out1：Freq_pcc

回答：

> PCC现在实际基波频率是多少？

单位：

```text
Hz
```

---

## Out2：Ppcc_kW

回答：

> PCC现在真实交换多少有功？

单位：

```text
kW
```

项目模型方向：

```text
正 = 微电网向上级送电
负 = 微电网从上级购电
```

这是当前基础AGC最核心的反馈量。

---

## Out3：Qpcc_kvar

回答：

> PCC现在交换多少无功？

单位：

```text
kvar
```

它主要用于：

```text
电压/无功状态观察
高级策略
系统运行分析
```

当前基础有功AGC并不使用它作为核心动态输入。

---

## Out4：Vab_rms_pcc

回答：

> PCC当前A-B线电压的有效值是多少？

单位：

```text
V
```

在当前10 kV系统正常情况下应处于：

```text
约10 kV量级
```

---

# 24. 这四个量为什么不是全部送给同一个算法

虽然都来自PCC Measurements，但它们的用途不同。

```text
Ppcc_kW
→ 基础AGC核心反馈

Freq_pcc
→ 系统频率状态 / Supervisory / 高级策略

Qpcc_kvar
→ 无功运行状态 / 高级策略

Vab_rms_pcc
→ 电压状态观察 / SC / 高级策略
```

另外一定要记住：

> `Vab_rms_pcc` 是一个标量RMS量，不能替代原 `Vpcc=[Va,Vb,Vc]` 三相向量去接需要三相原始电压的 Supervisory 输入。

---

# 25. PCC Measurements 与外部三相 V-I Measurement 的区别

外部三相V-I块负责的是：

```text
“把电气网络中的真实V/I取出来”
```

即：

```text
物理电气网络
↓
Three-Phase V-I Measurement
↓
Vpcc / Ipcc
```

而当前这个 `PCC Measurements` 子系统负责的是：

```text
“把已经取出来的V/I加工成工程量”
```

所以两者职责是：

```text
Three-Phase V-I Measurement
= 传感器

PCC Measurements
= 测量信号处理器
```

不能把它们理解成重复测量。

---

# 26. 为什么 PCC Measurements 必须留在 SM

PCC本身位于：

```text
10 kV公共电网
+
六设备汇总
```

这一侧。

这些一次网络都在：

```text
SM_Master
```

所以：

```text
PCC V/I测量
PLL
PCC P/Q
PCC RMS
```

留在SM最自然。

它属于：

> **全微电网公共状态测量**

而不是某一台PV/ESS/EV的局部控制器。

---

# 27. 它与六台SS的关系

六台SS分别改变自己的功率：

```text
PV / ESS / EV
↓
Stubline
↓
单相变压器
↓
馈线
↓
公共母线
↓
PCC
```

这些设备共同作用后的总结果，被PCC Measurements重新测出来：

```text
六台设备共同执行
↓
PCC物理状态改变
↓
Vpcc / Ipcc改变
↓
PCC Measurements
↓
Ppcc / Qpcc / Freq / Vrms改变
```

然后Ppcc又回到AGC：

```text
Ppcc
↓
AGC
↓
新的六路Pref
↓
SS本地Control
↓
六台设备再次改变
```

因此它是整个大闭环中非常关键的“总反馈传感器”。

---

# 28. 与当前 AGC 的闭环关系

当前基础AGC主要看：

```text
Ptarget
-
Ppcc_kW
```

例如：

```text
Ptarget = -100 kW
Ppcc    = -120 kW
```

则：

```text
dP = +20 kW
```

AGC于是增加微电网净出力。

六台设备执行以后：

```text
Ppcc
从 -120
往 -100
靠近
```

PCC Measurements再次把新的PCC功率送回来。

所以：

```text
PCC Measurements
不是单纯为了显示Scope
```

而是：

> **基础AGC闭环的真实反馈源。**

---

# 29. 与 V4 Modbus 的关系

V4模型侧40101～40104真实源也来自这里：

```text
40101 ← Ppcc_kW
40102 ← Qpcc_kvar
40103 ← PCC电压
40104 ← Freq_pcc
```

然后再进入V4编码：

```text
工程量
↓
Gain / Round / INT16或UINT16
↓
401xx raw
↓
板端
```

所以：

> PCC Measurements先负责“测对真实工程量”，V4 Encoder再负责“把工程量变成Modbus raw”。

不要把这两层混在一起。

---

# 30. 一次完整计算过程，用最通俗的方式走一遍

假设某一时刻PCC真实状态大约：

```text
频率 = 50 Hz
线电压 ≈ 10 kV
微电网正在购电120 kW
```

第一步：

```text
PCC V-I块
```

测到：

```text
Va,Vb,Vc
Ia,Ib,Ic
```

第二步：

```text
Vpcc → PLL
```

PLL判断：

```text
Freq ≈ 50 Hz
wt = 当前电气角度
```

第三步：

```text
Freq + wt + Vpcc + Ipcc
→ Positive-Sequence Power
```

得到基波：

```text
P
Q
```

第四步：

```text
P/Q经过尺度换算
```

输出：

```text
Ppcc_kW ≈ -120 kW
Qpcc_kvar = 当前无功
```

第五步：

```text
Vpcc中取Va、Vb
↓
Va - Vb
```

得到：

```text
Vab瞬时线电压
```

第六步：

```text
Freq + wt + Vab
```

提取：

```text
Vab基波幅值
```

第七步：

```text
幅值换算
```

得到：

```text
Vab_rms_pcc ≈ 10 kV
```

最终四个输出：

```text
Freq_pcc
Ppcc_kW
Qpcc_kvar
Vab_rms_pcc
```

就同时准备好了。

---

# 31. 最终一张图记住整个模块

```text
                 Vpcc [Va,Vb,Vc]
                     │
        ┌────────────┼─────────────┐
        │            │             │
        ▼            ▼             ▼
    输入尺度       Va/Vb选择      Power输入
      Gain           │             │
        │          Va-Vb           │
        ▼            │             │
       PLL           Vab           │
   ┌────┴────┐        │             │
   │         │        │             │
 Freq       wt        │             │
   │         │        │             │
   └────┬────┴────────┼─────────────┘
        │             │
        │             ▼
        │      基波幅值/相角提取
        │             │
        │            |u|
        │             │
        │            Gain
        │             │
        │             ▼
        │       Vab_rms_pcc
        │
        ├─────────────────────────────┐
        │                             │
        ▼                             ▼
    Freq_pcc                 Positive-Sequence Power
                                  ▲
                                  │
                             Ipcc [Ia,Ib,Ic]
                                  │
                              ┌───┴───┐
                              │       │
                              P       Q
                              │       │
                            Gain    Gain
                              │       │
                              ▼       ▼
                         Ppcc_kW  Qpcc_kvar
```

---

# 32. 一句话总结

> **PCC Measurements先用PCC三相电压做PLL，建立统一的基波频率和相角参考；再利用这套参考和三相V/I提取正序P/Q，同时从三相电压中构造Vab并提取其基波RMS，最终把复杂的三相瞬时波形整理成 `Freq_pcc、Ppcc_kW、Qpcc_kvar、Vab_rms_pcc` 四个可以直接给上层控制使用的工程量。**
