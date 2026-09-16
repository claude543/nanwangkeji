---
title: "2026-09-16｜ESS2下一步试验定案：直接d轴电流注入、P-only确认与在线可调点 V1.0"
date: 2026-09-16
project: "暑期南网科技项目 / yanshou_V7 / K26_K50_CLEAN_P1"
status: "下一轮改模与试验设计冻结前说明"
tags:
  - ESS2
  - GFM
  - GFL
  - Power-Loop
  - Current-Loop
  - Direct-Id-Injection
  - Orthogonal-Test
  - RT-LAB
---

# ESS2下一步试验定案：直接d轴电流注入、P-only确认与在线可调点 V1.0

# 0. 结论先行

当前已经做过：

```text
Current Adapter（电流参考执行适配器） = ON
Power Loop（功率外环） = ON
P目标先为0，随后才到 -0.005 pu
```

并且已经出现约 `0.8~0.9 Hz` 的慢振荡。

因此下一步不再重复“两者都开”。

推荐只做两个高信息量试验：

```text
A0：
电流执行链 ON
P/Q功率外环 OFF
Id_ref = 0
Iq_ref = 0

A1：
电流执行链 ON
P/Q功率外环 OFF
直接给极小、缓慢的 d轴电流参考
Iq_ref = 0
```

如果 A0 和 A1 都稳定，再做：

```text
B-P0：
电流执行链 ON
P有功外环 ON
Q无功外环 OFF
Pref = 0
```

这一步不是为了查无功，而是为了把 **P有功外环** 单独重新加入，得到直接因果证据。

当前没有必要做独立的 Q-only（仅无功外环）试验；无功链可以后置。

---

# 1. “绕过功率外环，直接给一个很小的d轴电流参考”能不能设计得合理？

可以，而且这是下一步非常有价值的一轮。

但前提是设计成一个**受控诊断试验**，而不是随便在某条线上硬塞一个数。

正常GFL链条是：

```text
Pref / Qref
↓
Power Loop（功率外环）
↓
Id_ref / Iq_ref
↓
Current Adapter（电流参考执行适配器）
↓
Current Regulator（电流控制器）
↓
变流器
↓
真实电流
↓
真实P/Q
```

A1的做法是：

```text
把 Power Loop 暂时拿掉
↓
人工提供一个很小的 Id_ref
↓
但后面的：
Current Adapter
Current Regulator
最终限流
PWM
物理滤波器
ESS1 GFM
真实母线
全部保留
```

所以它问的是一个非常纯粹的问题：

> **不依赖P功率误差闭环，ESS2的真实功率硬件/电流控制链本身能不能稳定地产生一点有功交换？**

---

# 2. 为什么这个A1试验能帮助锁定原因？

因为它把“承担有功”拆成两件事：

## 事情1：物理上产生有功

```text
给一个d轴电流参考
↓
电流内环执行
↓
ESS2产生实际有功
```

## 事情2：自动闭环决定应该给多少d轴电流

```text
Pref - Pmeas
↓
Power PI（有功功率比例-积分控制器）
↓
自动不断修改Id_ref
```

当前正式试验里两件事绑在一起。

A1只保留事情1。

如果A1表现为：

```text
直接给小Id
↓
Pmeas确实产生小的有功变化
↓
母线仍然稳定
```

那么可以明确得到：

> **ESS2并不是“只要交换一点有功就必然失稳”。**

而是更接近：

> **让P有功外环根据P误差不断自动修改Id_ref以后才失稳。**

这会非常明显地把问题推向P有功外环。

反过来，如果A1在没有P有功外环的情况下仍然出现同样的慢振荡：

> 就不能再把问题主要归给Power PI，应该继续往电流执行链、PLL、dq坐标、VFF和弱网物理耦合下沉。

所以A1信息量很高。

---

# 3. A1怎么设计才不会自己制造假问题？

必须满足以下条件。

## 3.1 不猜d轴正负方向

不能凭理论公式直接猜：

```text
+Id = 充电
还是
-Id = 充电
```

正式值应该从本轮已有G27数据中的：

```text
IrefUsedD
FinalIdRef
```

提取。

用“上一轮实际 -0.005 pu 平台对应的有符号 d轴电流”作为方向依据。

不需要重跑RT-LAB；直接从现有MAT取即可。

---

## 3.2 第一次不要直接打到上一轮完整电流幅值

推荐：

```text
先取上一轮 -0.005 pu 平台对应有符号Id的约10%~20%
```

只作为第一轮诊断量级。

如果稳定，再逐步增大。

目的不是一次到目标功率，而是确认：

> “只要给一点真实d轴电流，系统是否仍然稳定。”

---

## 3.3 不能用Python瞬间阶跃硬打

模型内部增加：

**Rate Limiter（变化率限制器）**

让：

```text
Id_direct：
0 → 小目标
```

缓慢变化。

Python只写：

```text
DIRECT_ID_REF_PU = 某固定值
```

真正的斜坡由模型内部完成。

这样不会把“突然的电流阶跃冲击”误判成“结构性不稳定”。

---

## 3.4 Iq_ref保持0

A1只测试有功方向。

不要同时给无功电流。

---

## 3.5 直接Id仍然必须经过现有最终限制链

不能把直接Id注入到最末端绕开保护。

正确结构：

```text
Power Loop产生的基础Id/Iq
            ↘
             BASETEST selector
            ↗
Direct Id/Iq
        ↓
现有 Manager / Final Limit Core
        ↓
Current Adapter
        ↓
Current Regulator
```

所以：

- 现有current circle；
- Final GFL limit；
- Current Adapter；
- 电流PI；
- modulation；

都继续真实参与。

A1只绕开“功率外环生成基础电流参考”这一层。

---

# 4. B试验到底有没有必要？

这里必须区分两种“B”。

## 不需要现在做的

```text
Q-only：
P外环关
Q外环开
```

当前没有必要。

现有证据没有明显指向Q无功外环：

```text
QIntegral = 0
```

所以无功链可以后置。

---

## 建议保留的B-P0

```text
P有功外环 ON
Q无功外环 OFF
Pref = 0
```

这个仍然有价值，而且不是重复当前正式试验。

为什么？

当前正式试验是：

```text
P/Q Power Loop结构整体存在
+
Current Adapter打开
```

虽然Q积分量为0，但仅凭：

```text
QIntegral = 0
```

不能100%证明Q比例支路、P/Q耦合、Q测量链完全没有动态参与。

所以如果：

```text
A0稳定
A1稳定
```

再做一次：

```text
只P外环 ON
Q外环明确 OFF
Pref = 0
```

成本很低，但得到的是：

> **P有功外环单独加入前后的直接A/B因果证据。**

因此：

- 独立Q试验：现在不做；
- P-only B-P0：建议做一次。

---

# 5. 如果确认功率外环是问题，是不是肯定Kp/Ki有问题？

不是。

这是必须避免的新误区。

“P有功外环导致不稳定”只说明：

> **不稳定因素位于P有功外环及其与弱网对象/PLL的闭环交互中。**

它可能来自很多位置。

---

## 5.1 可能性A：Kp/Ki和当前弱网对象不匹配

**Kp（Proportional Gain，比例增益）**

**Ki（Integral Gain，积分增益）**

原参数：

```text
Kp = 0.06
Ki = 2
```

在强网下可能完全没问题。

但弱孤岛对象变了：

```text
母线不再刚性
PLL会跟着动
ESS1 GFM也在参与
```

同样参数可能使功率环带宽过高或相位裕度不足。

这是当前很值得怀疑的一类原因。

---

## 5.2 可能性B：功率测量本身的延迟/滤波

Power PI看到的不是“瞬时真实系统状态”，而是经过测量链的Pmeas。

如果测量链产生明显相位延迟：

```text
系统已经转向
↓
控制器还在按照旧误差动作
```

即使Kp/Ki数值本身看起来不大，也可能产生负阻尼。

---

## 5.3 可能性C：PLL与P外环相互作用

**PLL（Phase-Locked Loop，锁相环）**

ESS2要通过PLL判断母线相角。

弱网中：

```text
ESS2电流
→ 改变母线相角/电压
→ PLL变化
→ dq坐标和Pmeas变化
→ P外环再改电流
```

所以可能是：

```text
Power Loop + PLL + 弱网
```

组合问题，而不是单独某一个K值。

---

## 5.4 可能性D：P → Id的转换/符号/尺度/限幅

也必须核查：

- P误差符号；
- d轴方向；
- 电压归一化；
- P到Id的换算；
- 输出限幅；
- Alpha切换；
- 积分状态管理。

不过“完全粗暴的符号写反”目前不是最高嫌疑：

因为本轮长期平均：

```text
Pref ≈ -0.005 pu
Pmeas平均也接近 -0.005 pu
```

如果整个P控制方向完全反了，更可能看到快速单向跑偏，而不是现在这种平均值接近、同时出现0.8~0.9 Hz大幅周期振荡。

所以更像：

> **动态相位/带宽/耦合问题**

而不是简单正负号写反。

---

# 6. 那为什么还建议现在把Kp/Ki做成在线可调？

不是因为已经认定：

```text
Kp/Ki = 根因
```

而是因为：

1. 如果B-P0确认P外环是决定性因素，下一步最自然的诊断就是比例/积分分解；
2. Kp/Ki只是两个参数，提前暴露成本非常低；
3. 默认倍率=1，不改变当前行为；
4. 可以避免以后每改一次比例/积分就重新Build。

所以建议暴露的不是直接替换正式参数，而是：

```text
P_KP_SCALE
P_KI_SCALE
```

正常：

```text
P_KP_SCALE = 1
P_KI_SCALE = 1
```

比例-only：

```text
P_KP_SCALE = 1
P_KI_SCALE = 0
```

降低比例：

```text
P_KP_SCALE = 0.5
P_KI_SCALE = 0
```

这样所有试验都有清晰基准。

---

# 7. 下一版模型到底改哪里？必须让用户能在Simulink里定位

正式Patch必须输出“修改地图”，至少包含：

```text
完整路径
新增块名称
原连接
新连接
修改原因
默认值
BASETEST=0时是否完全恢复旧行为
```

当前建议的改动位置如下。

---

## 修改位置1：ESS2功率外环

路径：

```text
K26_K50_CLEAN_P1
└─ SS_Slave2
   └─ ESS2_Control
      └─ Power Control Loop
```

这里现有 `RestoreAlpha` 已经会乘到P/Q功率误差进入PI之前。

下一版只在BASETEST下把它拆成：

```text
P_ALPHA
Q_ALPHA
```

并新增明确诊断开关：

```text
P_LOOP_ENABLE
Q_LOOP_ENABLE
```

目的：

- A0/A1：P=OFF，Q=OFF；
- B-P0：P=ON，Q=OFF；
- 正常模式：继续完全使用原RestoreAlpha语义。

功率环的正式位置已经在历史审计中固定为 `SS_Slave2/ESS2_Control/Power Control Loop`。

---

## 修改位置2：基础Id/Iq来源选择器

建议新增：

```text
K26_K50_CLEAN_P1
└─ SS_Slave2
   └─ ESS2_Control
      └─ AA15_BASETEST_DIRECT_IREF_SELECT
```

位置必须在：

```text
Power Control Loop基础电流输出
↓
进入AA15_GFL_ISLAND_SUPPORT的IdIq_ref入口
```

之间。

这里做：

```text
正常模式：
Power Loop Id/Iq

BASETEST direct模式：
[DirectId ; DirectIq]
```

重要：

> 不把DirectId直接送到Current Regulator末端。

它仍然必须走：

```text
AA15_GFL_ISLAND_SUPPORT
↓
AA15_ISLAND_GFL_SUPPORT_MANAGER
↓
Final GFL Limit Core
↓
AA15_V49_CURRENT_EXECUTION_ADAPTER
↓
Current Regulator
```

这样A1仍然是真实完整电流执行链。

历史审计已经确认 `AA15_GFL_ISLAND_SUPPORT` 的 `IdIq_ref` 是基础电流参考入口，而Current Adapter位于：

```text
ESS2_Control
└─ AA15_GFL_ISLAND_SUPPORT
   └─ AA15_V49_CURRENT_EXECUTION_ADAPTER
```

---

## 修改位置3：BASETEST在线诊断配置

建议新增独立子系统：

```text
K26_K50_CLEAN_P1
└─ SS_Slave2
   └─ AA15_ESS2_BASETEST_DIAG_CONFIG
```

只放本轮诊断用参数：

```text
CFG_E2_BASETEST_P_LOOP_ENABLE
CFG_E2_BASETEST_Q_LOOP_ENABLE

CFG_E2_BASETEST_DIRECT_IREF_ENABLE
CFG_E2_BASETEST_DIRECT_ID_REF_PU
CFG_E2_BASETEST_DIRECT_IQ_REF_PU

CFG_E2_BASETEST_P_KP_SCALE
CFG_E2_BASETEST_P_KI_SCALE
```

默认值必须使正常行为不变。

其中当前真正使用：

```text
P_LOOP_ENABLE
Q_LOOP_ENABLE
DIRECT_IREF_ENABLE
DIRECT_ID_REF
```

Kp/Ki scale先只预留，不在第一轮改动后立即调。

---

## 修改位置4：P有功比例/积分倍率

仍位于：

```text
SS_Slave2/ESS2_Control/Power Control Loop
```

但正式Patch之前必须先读取当前真实Power Loop内部结构，确认：

- P比例Gain是哪一块；
- P积分Gain和Integrator的实际排列；
- Kp/Ki分别在哪个节点生效。

不能凭名字猜插入位置。

目标数学关系应是：

```text
Kp_eff = Kp_original × P_KP_SCALE
Ki_eff = Ki_original × P_KI_SCALE
```

并保持：

```text
scale = 1
```

时与当前正式模型数学等价。

---

# 8. 当前建议最小在线参数集合

当前不要暴露一大堆东西。

第一版只需要：

```text
1. P_LOOP_ENABLE
2. Q_LOOP_ENABLE
3. DIRECT_IREF_ENABLE
4. DIRECT_ID_REF_PU
5. DIRECT_IQ_REF_PU
6. P_KP_SCALE
7. P_KI_SCALE
```

共7个。

甚至第一轮A0/A1只使用前5个。

---

# 9. Python怎么用这些在线参数？

每一轮只在t=0、模型暂停时写一次。

例如：

## A0

```text
P_LOOP_ENABLE = 0
Q_LOOP_ENABLE = 0
DIRECT_IREF_ENABLE = 1
DIRECT_ID_REF = 0
DIRECT_IQ_REF = 0
```

## A1

```text
P_LOOP_ENABLE = 0
Q_LOOP_ENABLE = 0
DIRECT_IREF_ENABLE = 1
DIRECT_ID_REF = 小的有符号值
DIRECT_IQ_REF = 0
```

## B-P0

```text
P_LOOP_ENABLE = 1
Q_LOOP_ENABLE = 0
DIRECT_IREF_ENABLE = 0
Pref = 0
```

每轮：

```text
Reset
→ Load once
→ PAUSED @ t≈0
→ Python写固定配置并回读
→ Execute
→ 模型自己跑固定时序
→ Pause
→ DirectMAT
```

不做同一轮边跑边调。

---

# 10. 最终建议

当前不建议做Q-only试验。

下一步改模应该为一次Build服务于：

```text
A0：纯电流执行零参考
A1：纯电流执行 + 小d轴直接电流
B-P0：只开启P有功外环，Pref=0
```

并提前暴露：

```text
P_KP_SCALE
P_KI_SCALE
```

但在B-P0确认P外环为决定性因素之前，不使用它们调参。

如果B-P0确认P外环问题，再进入：

```text
C1：Ki=0，只留比例
C2：降低Kp
C3：固定稳定Kp，逐级恢复Ki
C4：最后再给实际小Pref
```

因此：

> **A1是合理且必要的信息增益试验；Q-only现在没有必要；Kp/Ki值得在线可调，但它们只是后续诊断旋钮，不是已经被证明的根因。正式改模时必须把每个新增块和完整Simulink路径列出来，确保用户可以逐块定位。**
