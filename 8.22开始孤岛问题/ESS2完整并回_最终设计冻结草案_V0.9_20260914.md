---
title: K26_K50｜ESS2 完整并回最终设计冻结草案
date: 2026-09-14
version: V0.9
project: 暑期南网科技项目 / yanshou_V7 / K26_K50_CLEAN_P1
status: 设计冻结阶段｜尚未生成正式 Patch
tags:
  - ESS2
  - 黑启动
  - 并回
  - GFL
  - RT-LAB
  - Simulink
  - OPAL-RT
---

# K26_K50｜ESS2 完整并回最终设计冻结草案 V0.9

> 本文件依据：
>
> - 当前 `K26_K50_CLEAN_P1`；
> - 已成功 Build 的 ESS2 Restore R3 + Return Fix R2 + Final Closure R2；
> - ESS1-only 黑启动数据；
> - ESS2 E2E R4 真实并回数据；
> - 2026-09-14 用户运行完成的 `AUDIT_K26_K50_ESS2_RECONNECT_FINAL_PREFLIGHT_R6` 70份输出；
> - 仓库中已冻结的 Simulink / RT-LAB 自动改模经验。
>
> **本文件只冻结设计，不生成 Patch。**

---

# 0. 先给结论

## 0.1 R6 自动状态虽然仍报 blocker，但本次改模所需事实已经足够

R6 自动摘要写的是：

```text
事实审计已一次性完成_仍有事实阻碍需用本ZIP分析
```

逐文件人工复核后，剩余自动 blocker 主要是递归 trace 算法继续向不属于本次修改范围的上游深挖，最终因 depth、Goto/From 非直接连接等原因自报 FAIL。

对于本次 ESS2 完整并回需要修改的范围，已经足够冻结设计。

因此：

```text
不再继续生成新的结构审计脚本
```

除非正式 Patch 的 preflight 发现当前模型已经发生新的语义漂移。

---

# 1. R6 自动 blocker 的人工关闭结果

|R6自动Blocker|人工结论|是否影响本次设计|
|---|---|---|
|实际电流反馈最终路径|已人工关闭|否|
|电流参考最终路径|已人工关闭|否|
|电压前馈最终路径|已人工关闭|否|
|Current Adapter状态反馈环|direct-check 不适配内部 Goto/From；现有 Adapter 已 Build/运行，本轮不改该状态环|否|
|hold退出首拍数学|数值已输出，可直接使用|否|
|Power Loop输出追溯|本次需要的接口已经明确，继续追到整个SM造成假 blocker|否|
|Executor输入来源|`23A_EXECUTOR_INTERFACE.csv` 5路全部 PASS|否|
|READY/COMMIT当前语义|`23C_READY_COMMIT_SEMANTICS.csv` 6项全部 PASS|否|
|MasterF相关证据|控制意义已经足够明确；本设计取消它的并回资格控制权|否|
|MasterF精确源|本轮不修 MasterF 生成链，因此不再把它作为改模 blocker|否|

---

# 2. 三条最关键控制路径已经审清

## 2.1 实际电流反馈

路径：

```text
Current Adapter IdIq_meas
↑
AA15_GFL_ISLAND_SUPPORT
↑
ESS2_Control/From28
tag = IdIqs
↑
Goto21
↑
Mux1
```

Mux1 的 d/q 两路来自：

```text
Switch2
Switch9
```

Switch2 / Switch9：

```text
Criteria = u2 > 0.5
u2 = ConnectMode = GRIDON
```

当前 ESS2 是 GFL：

```text
GRIDON = 1
```

因此选 `u1`。

最终：

```text
Measurements/IdIq_measPLL
→ IdIqF
→ Selector
→ Switch2 / Switch9
→ Mux1
→ IdIqs
→ From28
→ AA15_GFL_ISLAND_SUPPORT
→ Current Adapter
```

所以：

> **ESS2 当前真正的 Current Adapter 电流反馈，是 PLL frame 的 `IdIq_measPLL`。**

本次不要换这个反馈点。

---

# 3. 当前电流参考路径已经审清

```text
Current Adapter IdIq_ref
↑
AA15_GFL_ISLAND_SUPPORT
↑
ESS2_Control/From24
tag = IdIq_refs
↑
ESS2_Control/Switch
```

顶层 Switch：

```text
u1 = IdIq_refF
     = AA15_GFL_ISLAND_SUPPORT/FinalIref

u2 = ConnectMode / GRIDON

u3 = Voltage Regulators/IdIq_ref
```

ESS2 当前 GFL：

```text
ConnectMode = 1
```

因此选择：

```text
AA15_GFL_ISLAND_SUPPORT/FinalIref
```

---

# 4. 电压前馈路径已经审清

ESS2 GFL 的原始 Vdq 路径：

```text
Measurements/VdVq_measPLL
→ VdVqF
→ Selector8 / Selector12
→ Switch1 / Switch8
→ Mux
→ VdVqs
→ From26
→ GFL Support
→ Current Adapter Vdq_FF
```

当前 `ConnectMode=1` 时使用 PLL frame 分支。

因此本次也不改 Vdq 前馈选择逻辑。

---

# 5. 当前 ESS2 问题的准确表述

不是：

```text
原GFL电流控制器不会控
```

而是：

> **Restore 状态机在 breaker 已经闭合以后，仍继续使用“断开待并”的电流屏蔽模式，导致原有 GFL Current PI 被人为关掉。**

当前 state4/state5：

```text
breaker CLOSED
RestoreHold = 1
```

于是 Current Adapter：

```text
iref_used  = 0
imeas_used = 0
match      = 1
matchTarget= 0
```

所以真实支路电流已经出现时：

```text
Current PI error = 0
CurrentPI_d/q = 0
```

R4 数据已经直接证明。

---

# 6. 最终并回状态机

统一中文：

```text
状态1：断开待并
↓
状态2：并入资格累计
↓
状态3：并入前就绪
↓
状态4：断路器闭合 + 零电流主动调节
↓
状态5：零功率稳定接入
↓
状态6：功率平滑恢复
↓
状态7：正常恢复运行
```

代码内部可继续保留原 state 编号。

---

# 7. 每个状态应该输出什么

|状态|Breaker|Current Hold|IrefUsed|ImeasUsed|Power Loop|Release Alpha|
|---|---:|---:|---:|---:|---:|---:|
|1 断开待并|0|1|0|屏蔽|关闭|0|
|2 资格累计|0|1|0|屏蔽|关闭|0|
|3 并入前就绪|0|1|0|屏蔽|关闭|0|
|4 闭合后零电流调节|1|**0**|0|**真实Imeas**|关闭|0|
|5 零功率稳定接入|1|**0**|0|**真实Imeas**|关闭|0|
|6 功率平滑恢复|1|0|alpha × FinalIref|真实Imeas|开启|0→1|
|7 正常恢复运行|1|0|FinalIref|真实Imeas|开启|1|

---

# 8. 为什么 state4 的 `hold=0, alpha=0` 正好就是需要的模式

现有 Current Adapter 已经实现：

```matlab
if hold
    iref_used  = 0;
    imeas_used = 0;
else
    iref_used  = alpha * iref;
    imeas_used = imeas;
end
```

所以：

```text
hold=0
alpha=0
```

自然得到：

```text
iref_used = 0
imeas_used = actual imeas
```

电流误差：

```text
error = 0 - actual imeas
```

原 Current PI 立即恢复纠偏权。

因此：

> **不需要新增第二套 Current PI。**

---

# 9. hold 退出第一拍已经足够定量

R6 解析：

```text
Ts = 0.0001 s
Kp = 0.3
Ki = 20
Ttrack = 0.015 s
```

得到：

```text
HalfKiTs = 0.001
TrackAlpha/sample ≈ 0.00664449
```

hold 长期状态：

```text
error=0
match=1
target=0
```

所以 PI 状态接近零，且初始化已完成。

退出 hold：

```text
match=0
error=-Imeas
```

未限幅第一拍近似：

```text
rawPI ≈ 0.301*(-Imeas)
        + 0.00664449*residualPrev
```

因此不需要额外做一次“match oldPI”去拖延纠偏。

---

# 10. oldPI 已经审清

```text
Current Adapter/OldPI
←
AA15_GFL_ISLAND_SUPPORT/OldPI
←
ESS2_Control/Current Regulator/out2
= PIdq
```

本轮不改 oldPI 路径。

---

# 11. 修改1：Restore Executor 的 Hold 映射

位置：

```text
K26_K50_CLEAN_P1
/SS_Slave2
/AA15_ESS2_RESTORE_EXECUTOR
/CORE
```

当前：

```matlab
if state<=5 || state==9
    hold=1;
end
```

修改为：

```text
state1/2/3
→ hold=1

state4/5/6/7
→ hold=0
```

状态9单独处理。

---

# 12. 修改2：COMMIT 当拍重新检查 READY

当前 state3：

```text
只要历史上已经进入READY
+
manualCommit
→ state4
```

修改：

```text
request丢失
→ state1

ready丢失
→ state2
→ 清Ready dwell

只有：
ready==1
+
breakerAct==1
+
commit有效
→ state4
```

---

# 13. 修改3：READY 不再使用 legacy MasterF

当前：

```matlab
abs(pllHz-masterF) <= dfMax
```

但真实试验已证明：

```text
ESS2 PLL ≈ actual bus ≈ 50.233 Hz
legacy MasterF ≈ 49 Hz
```

所以新增：

```text
CFG_ESS2_RESTORE_FNOM_HZ
default = 50
```

READY 改为：

```text
abs(pllHz - fNom) <= dfMax
```

`MasterF` 保留诊断，不再拥有 breaker READY 否决权。

---

# 14. 必须补真实 breaker-inner Vabc

当前：

```text
EV1_inv
= L2之前

EV1_LV_Meas
= breaker外侧
```

真正 breaker 内侧：

```text
L2后 + C2 + breaker内侧
```

当前 C2：

```text
Measurements=None
```

所以新增：

```text
SS_Slave2/AA15_ESS2_BREAKER_INNER_MEAS
```

建议：

> **直接克隆当前 Build 成功的 `EV1_LV_Meas`，不要重新猜库路径。**

---

# 15. 修改4：breaker-inner 测量块的物理位置

当前：

```text
L2
↓
C2 node
↓
AA15_DIAG_AC_BREAKER_ESS2
```

修改：

```text
L2
↓
C2 node
↓
AA15_ESS2_BREAKER_INNER_MEAS
↓
AA15_DIAG_AC_BREAKER_ESS2
```

要求 postassert：

```text
L2
C2
new measurement input side
```

仍是同一电气节点。

measurement output side接 breaker。

---

# 16. 测量块参数

新 measurement 必须和：

```text
EV1_LV_Meas
```

使用同样：

```text
Vpu
Vbase
Pbase
phase-to-ground定义
measurement family
```

这样：

```text
vinner
vbus
```

才是同单位、同基准。

---

# 17. 修改5：Executor 的 Vinner 改成真实节点

当前：

```text
Executor/in4
← EV1_inv/out1
```

改：

```text
Executor/in4
← AA15_ESS2_BREAKER_INNER_MEAS/Vabc
```

`Vbus`：

```text
Executor/in5
← EV1_LV_Meas/Vabc
```

保持。

---

# 18. 现有 phaseCorr / voltageRatio 直接复用

现有：

```text
phaseCorr =
dot(vinner,vbus) /
(norm(vinner)*norm(vbus))

vRatio =
innerGain*norm(vinner)/norm(vbus)
```

同尺度平衡三相下：

```text
phaseCorr ≈ cos(phase difference)
```

因此不需要再加 PLL / FFT / phasor Function。

第一轮建议：

```text
PHASE_GATE_ENABLE = 1
PHASE_COS_MIN = 0.984807753012
```

对应约 ±10°。

连续 Ready dwell 0.5 s 若始终维持 ±10°，仅从相位漂移近似已经意味着频差需很小：

```text
约 0.0556 Hz 量级
```

Voltage Ratio：

```text
VMATCH_GATE_ENABLE = 1
VRATIO_MIN = 0.95
VRATIO_MAX = 1.05
```

需要时可在线放宽到：

```text
0.90 ~ 1.10
```

---

# 19. 修改6：state4 真正变成“闭合后零电流主动调节”

state3 → state4 同一控制步：

```text
breakerCmd = 1
hold = 0
alpha = 0
```

这一步就是本轮缺失的：

```text
plant-facing convergence
```

---

# 20. state4 的 PostOK

建议：

```text
postOK =
Vpu在post范围
AND
Imeas <= postImax
AND
CurrentLimit == 0
AND
ModHeadroom >= headroomMin
```

默认：

```text
postImax = 0.20 pu
postV = 0.80~1.20 pu
postDwell = 0.20 s
```

state4 只负责证明：

```text
最严重合闸瞬态已经被主动电流闭环压回
```

不是长期稳定证明。

---

# 21. 修改7：state5 增加真正的 Zero-Stable dwell

当前：

```text
state5一进入
→ releaseAllowed=1
```

太快。

新增：

```text
CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S
```

建议默认：

```text
2.0 s
```

state5 严格条件：

```text
Vpu在ready范围
Imeas <= IMEAS_MAX
CurrentLimit=0
ModHeadroom >= headroomMin
```

Python 同时检查：

```text
|Pmeas|
|Qmeas|
```

是否接近零。

---

# 22. 不扩状态向量：复用 z(2)

当前：

```text
z2 = readyCount
```

进入 state4 后它已经不再需要。

所以：

```text
state2：
z2 = Ready dwell count

state5：
z2 = ZeroStable dwell count
```

不增加 state vector 宽度。

---

# 23. 修改8：解决双 RestoreAlpha

当前：

```text
Power Loop:
P/Q error × alpha

Current Adapter:
FinalIref × alpha
```

这形成 double ramp。

最终建议：

> **只保留一个连续 ramp，放在 Current Adapter 最终电流执行入口。**

---

# 24. Power Loop 改成 binary enable

位置：

```text
SS_Slave2
/ESS2_Control
/Power Control Loop
```

新增标准块：

```text
AA15_RESTORE_POWER_LOOP_ENABLE
```

类型：

```text
Compare To Constant
```

逻辑：

```text
RestoreAlpha > 0
→ 1
否则
→ 0
```

原：

```text
P error × RestoreAlpha
Q error × RestoreAlpha
```

改为：

```text
P error × PowerLoopEnable
Q error × PowerLoopEnable
```

这样：

```text
state1~5
外环关闭

state6开始
外环正常工作

真正连续0→1 ramp
只发生在最终FinalIref进入Current PI之前
```

---

# 25. 为什么连续 ramp 必须保留在 Current Adapter

GFL Support 不只有 Power Loop，还可能有：

```text
本地电压支撑
Q secondary
UV relief
其它 FinalIref 修正
```

所以如果只在 Power Loop 做 ramp，这些附加电流可能绕过 ramp。

因此最终执行入口的：

```text
alpha × FinalIref
```

必须保留。

---

# 26. Current Adapter 算法本轮不改

位置：

```text
SS_Slave2
/ESS2_Control
/AA15_GFL_ISLAND_SUPPORT
/AA15_V49_CURRENT_EXECUTION_ADAPTER
/CORE
```

不改：

```text
Kp
Ki
Vff
限幅
oldPI
原helper
```

只通过正确的：

```text
Hold
Alpha
```

调用它已有能力。

---

# 27. 修改9：state9 fail 语义

当前：

```text
state9
hold=1
alpha=0
```

如果：

```text
abortOpen=0
breaker仍闭合
```

这又会关掉真实电流闭环。

修改：

## 自动断开

```text
abortOpen=1
breaker=0
hold=1
alpha=0
```

## 不自动断开 / evidence-first

```text
abortOpen=0
breaker=1
hold=0
alpha=0
```

原则：

> **breaker只要还闭合，就不能重新进入 open-standby current hold。**

---

# 28. state6 功率恢复期间

继续监视：

```text
Vpu
CurrentLimit
ModHeadroom
```

严重异常：

```text
abortOpen=1
→ state9 + breaker OPEN

abortOpen=0
→ state9 + breaker CLOSED + hold0 + alpha0
```

---

# 29. 是否应该继续叠 MATLAB Function？

## 结论：不应该

黑启动 / 孤岛并没有“每加一个阶段就叠一个 MATLAB Function”的标准做法。

更合理的分层：

```text
Plant
→ SPS / Simscape electrical blocks

PI / filter / limiter / switch
→ 标准 Simulink 控制块

状态顺序 / 模式逻辑
→ Stateflow 或一个清楚的 supervisor

复杂数值算法
→ MATLAB Function / C Function
```

---

# 30. Stateflow 更适合黑启动状态机吗？

从建模哲学：

```text
是
```

因为：

```text
Standby
Qualify
Ready
Close
ZeroCurrent
Release
Restored
Fail
```

本质是 finite-state supervisory control。

但当前不要把 Executor 改成 Stateflow。

原因：

```text
当前 Executor Function 已经：
Patch成功
Verifier成功
RT-LAB Build成功
Target运行成功
```

现在同时做：

```text
控制修复
+
技术栈迁移
```

会显著增加风险。

因此当前冻结：

> **保留一个现有 Executor Function；本次新增控制 Function = 0。**

未来产品化再单独做 Stateflow 等价迁移。

---

# 31. 本轮模块选择

|功能|实现方式|新 Function?|
|---|---|---:|
|breaker-inner Vabc|克隆现有三相测量块|否|
|Ready phase/ratio|现有 Executor 计算|否|
|状态机|修改现有 Executor CORE|不新增|
|Current PI|现有 Adapter/helper|否|
|Power Loop enable|Compare To Constant|否|
|IrefUsed 诊断镜像|Product + Switch|否|
|ImeasUsed 诊断镜像|Switch|否|
|诊断拼接|Mux|否|
|G27 packing|修改现有 Repack Function|不新增|
|G27 normalizer|Demux/Mux|否|

---

# 32. 修改10：新增内部控制诊断镜像

建议放：

```text
ESS2_Control
/AA15_GFL_ISLAND_SUPPORT
/AA15_ESS2_RESTORE_CURRENT_DIAG
```

内部全部用标准块。

## IrefUsedDiag

```text
IdIq_ref
× RestoreAlpha
↓
Switch:
hold=1 → zeros(2,1)
hold=0 → alpha*IdIq_ref
```

## ImeasUsedDiag

```text
Switch:
hold=1 → zeros(2,1)
hold=0 → IdIq_meas
```

## MatchActive

直接使用现有：

```text
AA15_V49_CURRENT_EXECUTION_ADAPTER/Diagnostic23
```

因为 helper 已经把：

```text
d(3)=matched
```

导出来。

---

# 33. G27 仍只有一个组，不加 G31

仍然：

```text
G26
G27
G28
G29
G30
```

ESS2 继续用：

```text
G27
Acq_Group=27
Decimation=4
```

---

# 34. G27 建议 56 → 62

保留原1~56全部证据。

新增：

|ch|含义|
|---:|---|
|57|IrefUsed_d|
|58|IrefUsed_q|
|59|ImeasUsed_d|
|60|ImeasUsed_q|
|61|MatchActive|
|62|PostOK|

MAT：

```text
Target Time + 62
= 63 rows
```

---

# 35. ch49~51 从 proxy 升级为真实 breaker-inner

当前：

```text
49~51 = EV1_inv proxy
```

修改：

```text
49~51 = AA15_ESS2_BREAKER_INNER_MEAS Vabc
```

52~54：

```text
bus-side Vabc
```

55：

```text
真实phaseCorr
```

56：

```text
真实voltageRatio
```

---

# 36. G27 Repack

路径：

```text
SS_Slave2/AA15_ESS2_RESTORE_G27_REPACK
```

当前输入：

```text
diag48
vinner
vbus
finalcmd
status12
```

增加：

```text
ctrlDiag5
=
[IrefUsed_d
 IrefUsed_q
 ImeasUsed_d
 ImeasUsed_q
 MatchActive]
```

输出：

```text
62×1
```

新增：

```text
57:61 = ctrlDiag5
62 = status12(PostOK)
```

---

# 37. G27 Normalizer

路径：

```text
SS_Slave2/AA15_ESS2_RESTORE_G27_VECTOR_NORMALIZER
```

56 → 62。

必须复用 Final Build Closure R2 成功模式：

```text
add Subsystem
↓
deleteContents
↓
assert empty
↓
In62
↓
Demux62
↓
62 scalar
↓
Mux62
↓
Out62
```

不重新发明 normalizer。

---

# 38. Restore Config 29 → 31

新增：

```text
30 CFG_ESS2_RESTORE_FNOM_HZ
31 CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S
```

默认：

```text
50
2.0
```

---

# 39. Python 一次性并回：在线参数分类

## 每轮动作参数

```text
MASTER_ENABLE
CONTROL_SOURCE
MANUAL_REQUEST
AUTO_SEQUENCE_ENABLE
BREAKER_ACTUATION_ENABLE
MANUAL_COMMIT
POWER_RELEASE_ENABLE
MANUAL_RELEASE
ABORT_OPEN_ENABLE
```

## 阈值 / 试验参数

```text
V_MIN / V_MAX
FNOM_HZ
DF_MAX
IREF_MAX
IMEAS_MAX
HEADROOM_MIN
READY_DWELL
POST_DWELL
ZERO_STABLE_DWELL
RELEASE_RAMP
PHASE_GATE
PHASE_COS_MIN
VMATCH_GATE
INNER_GAIN
VRATIO_MIN/MAX
POST_I_MAX
POST_V_MIN/MAX
```

---

# 40. 第一轮建议值

```text
MASTER_ENABLE = 1
CONTROL_SOURCE = 0
MANUAL_REQUEST = 1
AUTO_SEQUENCE_ENABLE = 0

BREAKER_ACTUATION_ENABLE = 1
MANUAL_COMMIT = 0

POWER_RELEASE_ENABLE = 1
MANUAL_RELEASE = 0

PHASE_GATE_ENABLE = 1
PHASE_COS_MIN = 0.984807753012

VMATCH_GATE_ENABLE = 1
VRATIO_MIN = 0.95
VRATIO_MAX = 1.05
VINNER_TO_BUS_GAIN = 1

FNOM = 50
DF_MAX = 0.5

READY_DWELL = 0.5 s
POST_DWELL = 0.2 s
ZERO_STABLE_DWELL = 2.0 s
RELEASE_RAMP = 2.0 s

ABORT_OPEN_ENABLE = 0
```

---

# 41. Build 后必须做 Target Probe

所有 Restore 参数：

```text
exact唯一路径
→ read
→ safe write
→ readback
→ restore
→ restore readback
```

特别是新增：

```text
FNOM_HZ
ZERO_STABLE_DWELL_S
```

不能只因为模型 Constant 存在就认为 Target 可调。

---

# 42. 一次性 Python Runner 流程

```text
人工：
Reset
→ Load
→ MODEL_PAUSED @ t=0

Python：
Preflight
↓
写黑启动baseline
↓
ESS1形成孤岛
↓
ESS2断开待并
↓
等待state3 READY
↓
Python独立cross-check
↓
pulse COMMIT
↓
state4
↓
闭合后零电流主动调节
↓
state5
↓
ZeroStable dwell
↓
releaseAllowed=1
↓
等待S14 Stage2有意义Pcmd
↓
pulse RELEASE
↓
state6 alpha ramp
↓
state7
↓
长观察
↓
Pause
↓
保留RAW
↓
DirectMAT
```

---

# 43. COMMIT 必须 pulse

```text
MANUAL_COMMIT:
0 → 1
```

确认：

```text
state4
breaker=1
```

立即：

```text
MANUAL_COMMIT = 0
```

避免未来重资格时因为 commit 长期为1自动再次闭合。

---

# 44. Gate A：合闸前

模型：

```text
state3
Ready=1
breaker=0
alpha=0
fail=0
```

Python 独立确认：

```text
PCC/bus V健康
PLL在50±0.5
phaseCorr >= phase threshold
vRatio在范围
FinalIref≈0
Imeas低
CurrentLimit=0
Headroom足
```

---

# 45. Gate B：state4

必须直接从新 G27 证明：

```text
hold=0
alpha=0
IrefUsed≈0
ImeasUsed=actual
MatchActive=0
```

并且：

```text
CurrentPI_d/q
不再永久为0
```

目标因果：

```text
电流出现
→ PI纠偏
→ Imeas衰减
```

---

# 46. Gate C：state5

要求：

```text
state5
breaker=1
hold=0
alpha=0
releaseAllowed=1
```

持续健康。

外部至少观察：

```text
2 s
```

检查：

```text
Imeas低
P/Q接近0
PCC V/f稳定
CurrentLimit=0
Headroom良好
PostOK=1
```

---

# 47. 等待 S14 Stage2

如果 Stage2 还没到：

```text
继续state5
```

即使：

```text
PrefCmd / PrefEff
```

开始变化，只要：

```text
PowerLoopEnable=0
alpha=0
```

设备仍不执行功率。

---

# 48. RELEASE 也必须 pulse

```text
MANUAL_RELEASE:
0 → 1
```

确认 state6 后：

```text
MANUAL_RELEASE = 0
```

---

# 49. state6 验收

必须直接验证：

```text
IrefUsed ≈ alpha × FinalIref
```

同时：

```text
PowerLoopEnable=1
Current PI正常
MatchActive=0
```

alpha：

```text
0→1
```

默认2s。

---

# 50. state7 验收

要求：

```text
state7
breaker=1
hold=0
alpha=1
fail=0
```

长观察至少：

```text
8~10 s
```

检查：

```text
P/Q tracking
Iref/Imeas
CurrentPI
Vconv
ModIndex
CurrentLimit
Headroom
PCC V/f
ESS1压力
```

---

# 51. OpWrite 总分工

## G27

ESS2 高速并回因果：

```text
63 rows
Target Time + 62
dt=0.4 ms
```

## G29

系统/PCC/S14。

## G30

ESS1 GFM响应。

不要把所有系统量重复塞入 G27。

---

# 52. 正式 Patch 精确修改位置

## A. 新增物理测量

```text
SS_Slave2/AA15_ESS2_BREAKER_INNER_MEAS
```

## B. Executor Vinner

```text
SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/in4
EV1_inv → new inner measurement
```

## C. Executor CORE

```text
SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR/CORE
```

修改：

```text
cfg29→31
MasterF gate→fNom gate
state3 recheck ready
state4 hold0
state5 hold0 + zero stable dwell
state6 health
state9 closed-fail hold0
```

## D. Config

```text
SS_Slave2/AA15_ESS2_RESTORE_CONFIG
```

新增2项。

## E. Power Loop

```text
SS_Slave2/ESS2_Control/Power Control Loop
```

新增：

```text
AA15_RESTORE_POWER_LOOP_ENABLE
```

## F. Current Adapter

```text
算法源码不改
```

## G. 诊断镜像

```text
ESS2_Control/AA15_GFL_ISLAND_SUPPORT/AA15_ESS2_RESTORE_CURRENT_DIAG
```

## H. G27 Repack

```text
SS_Slave2/AA15_ESS2_RESTORE_G27_REPACK
56→62
```

## I. G27 Normalizer

```text
SS_Slave2/AA15_ESS2_RESTORE_G27_VECTOR_NORMALIZER
56→62
```

---

# 53. 明确不修改

```text
ESS1 GFM
F21/F24/F25
PV1/PV2/EV1/EV2
Stubline
SSN
ARTEMiS
变压器参数
L2/C2参数
ESS2原Current Regulator PI
Current Adapter helper
ESS2 PLL
GFL dq选择
Power PI Kp/Ki
BOARD15主线
```

---

# 54. 正式 Patch 的工程流程

必须：

```text
pure helper selftest
↓
current semantic preflight
↓
physical topology preflight
↓
Executor candidate harness
↓
G27 62 normalizer production-equivalent harness
↓
byte-identical scratch
↓
scratch patch
↓
postassert
↓
save once
↓
reload
↓
persistent postassert
↓
formal backup
↓
formal re-preflight
↓
formal patch
↓
formal postassert
↓
save exactly once
↓
reload
↓
independent verifier
↓
RT-LAB Rebuild
```

---

# 55. Verifier 必须独立检查

```text
新物理节点
测量块family/settings
cfg31
state hold语义
state3 ready recheck
fNom频率条件
state5 zero dwell
state9 hold语义
PowerLoop binary enable
Current Adapter SHA不变
helper SHA不变
G27 62 schema
normalizer62
OpWrite仍5
return45不变
SM→SS2 25不变
S14 route不变
其它SPS节点不变
```

---

# 56. Function 模块的最终评价

当前模型 MATLAB Function 较多，是长期研究迭代造成的。

它们不是天然错误，因为很多已经 Build + Target 运行。

但：

> **后续不能遇到一个需求就叠一个新 Function。**

本轮正确策略：

```text
复杂状态逻辑
→ 保留现有 Executor Function

复杂 Current Adapter
→ 保留现有Function

简单门控/比较/诊断/拼接
→ 标准Simulink块

新增控制 Function
→ 0个
```

---

# 57. 未来产品化

当：

```text
ESS2 primitive
PV/EV primitive
完整六机恢复
```

全部通过后，再单独考虑：

```text
Restore Executor MATLAB Function
→ Stateflow
```

那一轮只做架构可读性迁移，不和故障修复混在一起。

---

# 58. 最终判断

## 审计

对于本次改模范围：

> **已经足够，无需继续审计。**

## 根因

首要确认控制缺陷：

> **breaker闭合后仍使用 open-standby hold，导致真实电流反馈和Current PI纠偏被关闭。**

第二个设计缺口：

> **当前没有真正 breaker-inner Vabc，因此并入前同步资格不完整。**

## 改模核心

不是加更多控制器，而是：

```text
补真实breaker-inner measurement
+
修状态机阶段语义
+
恢复已有Current PI控制权
+
double-ramp改成单一最终ramp
+
补zero-stable资格
+
补内部直接证据
```

---

# 59. 下一步

用户确认本设计后，一次性交付：

```text
1. 正式 Patch
2. Independent Verifier
3. 修改说明
4. Build 后 Target Probe
5. 一次性 Python Runner
6. DirectMAT Analyzer 更新
7. G27 62通道 schema
8. 执行顺序
```

目标：

> **一次设计、一次结构改模、一次 Build，把 ESS2 完整并回 primitive 做全。**
