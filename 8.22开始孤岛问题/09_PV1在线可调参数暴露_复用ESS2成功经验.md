# PV1 R1.4｜在线可调参数暴露合同
## ——严格复用ESS2已经成功的Kp/Ki在线暴露方法

# 1. 为什么R1.3的Kp预检会失败

当前PV1 P有功PI内部的原始Gain（增益）不是字面：

```text
0.06
2.0
```

而是模型表达式：

```text
Kp4.Gain = Kp
Kp5.Gain = Ki
```

因此旧R1.3：

```matlab
str2double(get_param(...,'Gain'))
```

会把`Kp`解析成NaN（非数），从而误报`PV1 P Kp baseline drift`。

这不是模型漂移，是预检写法错误。

ESS2已经成功的正式Patch从来不是这样判断。它使用：

```text
get_param取得原始表达式
↓
slResolve（Simulink上下文求值）
↓
确认实际数学值是0.06 / 2.0
```

R1.4已经完全改回这一成功范式。

---

# 2. PV1 P Kp/Ki怎样真正在线暴露

原PV1：

```text
Error
→ Kp4(Gain=Kp，实际0.06)
→ 原比例后级

Error
→ Kp5(Gain=Ki，实际2.0)
→ 原anti-windup Switch（抗积分饱和选择器）
```

R1.4改成：

```text
Error
→ 原Kp4(Gain改为1)
→ AA15_PV1_P_KP_APPLY（乘法）
   × CFG_PV1_DIAG_P_KP_RT(Constant，默认0.06)
→ 原比例后级
```

积分支路：

```text
Error
→ 原Kp5(Gain改为1)
→ AA15_PV1_P_KI_APPLY（乘法）
   × CFG_PV1_DIAG_P_KI_RT(Constant，默认2.0)
→ 原anti-windup Switch
```

这和ESS2已经Build并Target实测成功的结构相同。

### Patch默认为什么仍然是Ki=2.0？

因为Patch只改变“参数从哪里进入”，不偷偷同时改变控制数学基线。

所以改模后的默认模型仍与旧PV1一致：

```text
Kp有效值 = 1 × 0.06 = 0.06
Ki有效值 = 1 × 2.0 = 2.0
```

等唯一一次RT-LAB Build成功并完成Target Verify（目标机接口验证）后，正式Run A在第一次Execute前再写：

```text
Kp = 0.06
Ki = 0.5
```

并立即readback（回读）。

这样“结构改模”和“动态参数试验”是两个独立证据层。

---

# 3. R1.4还保护了什么

R1.4在改模前同时验证：

```text
PV1 P PI Kp resolved = 0.06
PV1 P PI Ki resolved = 2.0
PV1 Q PI Kp resolved = 0.06
PV1 Q PI Ki resolved = 2.0
```

Q环不做Kp/Ki在线暴露改造，本轮保持原结构和原参数。

还验证：

```text
P Error → Kp4 → Zero-Order Hold
P Error → Kp5 → anti-windup Switch input3
原Discrete-Time Integrator仍存在
```

只有这些都闭合，才允许改P Kp/Ki路径。

---

# 4. 哪些PV1参数这次提前做成在线接口

## A. 正式Run前必须能在线写/回读

- `CFG_PV1_FULL_RESTORE_MASTER_ENABLE`：PV1完整恢复总使能；
- `CFG_PV1_PICKUP_TARGET_PU`：首个小正有功目标；
- `CFG_PV1_DIAG_MASTER_ENABLE`：诊断/运行时控制接口总使能；
- `CFG_PV1_DIAG_P_LOOP_ENABLE`：P环使能；
- `CFG_PV1_DIAG_Q_LOOP_ENABLE`：旧Q环使能；
- `CFG_PV1_DIAG_DIRECT_IREF_ENABLE`：直接d/q电流因果诊断；
- `CFG_PV1_DIAG_DIRECT_ID_TARGET_PU`；
- `CFG_PV1_DIAG_DIRECT_IQ_TARGET_PU`；
- `CFG_PV1_DIAG_P_KP_RT`；
- `CFG_PV1_DIAG_P_KI_RT`。

正式Run A第一版候选：

```text
P loop = 1
Q loop = 0
Direct Iref = 0
Kp = 0.06
Ki = 0.5
Pickup target = +0.005 pu
```

## B. 结构上也做成显式Constant，Target Verify检查是否可见

包括：

```text
V_MIN / V_MAX
DF_MAX
PHASE_COS_MIN
VRATIO_MIN / MAX
READY_DWELL
ZERO_STABLE_DWELL
PICKUP_PERR_MAX
PICKUP_STABLE_DWELL
BREAKER_ACTUATION_ENABLE
POWER_RELEASE_ENABLE
ABORT_OPEN_ENABLE
```

首轮正式Run正常情况下不扫描这些参数，只读取/确认冻结值。若未来需要定向调试，可以优先复用在线接口，不重Build。

---

# 5. Build以后才真正证明“在线可调”

SLX里有Constant不等于Target一定暴露。

唯一一次RT-LAB Rebuild以后必须：

```text
GetParametersDescription
↓
按当前Build动态发现路径
↓
每个关键参数精确唯一匹配
↓
可逆write
↓
readback
↓
restore原值
↓
再次readback
```

尤其必须验证：

```text
CFG_PV1_DIAG_P_KP_RT / Value
CFG_PV1_DIAG_P_KI_RT / Value
```

只有Target Verify通过，才能说PV1 Kp/Ki“真正在线可调”。

Runner不能复用旧Parameter ID（参数编号）。

---

# 6. Python Runner永久纪律

完全复用ESS2成功经验：

```text
fresh Reset
→ Load
→ PAUSED @ t≈0
→ GetParametersDescription
→ GetSignalsDescription
→ exact unique binding
→ write
→ readback
→ FileID
→ enable最后写
→ first Execute
```

第一次Execute以后：

```text
禁止Host继续写控制参数
```

普通V/f/P/I偏差仍然只记录，不由Host提前判停。

---

# 7. 本轮不需要用户手工改Kp/Ki块

不需要手工：

```text
把Kp改0.06
把Ki改2
新增Constant
新增Product
改线
```

这些属于普通Simulink信号结构，R1.4正式Patch可以按ESS2已验证范式自动完成，而且有scratch、原生compile、save/reopen、postassert和rollback保护。

用户只需要继续保持当前模型保存、停止状态即可。
