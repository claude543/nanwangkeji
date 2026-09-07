# K26_V5｜V4.8 FINAL DESIGN FREEZE V1.0
## 岛内稳态 q-bias 恢复 + 调制裕度感知｜正式改模冻结版

> 日期：2026-09-04  
> 正式基线：V4.7 Full 运行模型  
> 基线 SHA256：`6e7710750bc9ef5e4a8747ac541c53be639317c83a50e736e06b51c4bd1ca34f`  
> 结构证据：R2 = 11/11 PASS，R3 = 7/7 PASS，均为 `UNKNOWN/FAILED COUNT=0`。  
> 数值证据：V4.8 Numeric Design R2 = 9/9 PASS。  
> 本文件是 V4.8 Patch 的唯一设计源；此前 V0.x 规划若与本文件冲突，以本文件为准。

---

# 0. 冻结结论

V4.8 可以进入正式 Patch。

这里的“可以冻结”含义是：

1. **当前 V4.7 模型中，V4.8 要修改或复用的所有现有结构边界均已被 R2/R3 精确审计；没有已知 UNKNOWN。**
2. **V4.8 要解决的两个剩余问题均有正式 V4.7 数据支撑：**
   - Primary 历史增长模态已经被 V4.7 压成衰减，但离网后缺少新的稳态 q 工作点恢复；
   - Full 中旧 Voltage Secondary 权限耗尽，且部分设备持续进入调制饱和。
3. **V4.8 不再重构 Primary；只新增 Secondary 稳态恢复与 Secondary 执行能力约束。**
4. **不能承诺 Patch 后物理结果“数学上百分之百必然 PASS”——任何新闭环都必须经过 compile、Rebuild 和正式孤岛试验才能证明。**  
   但截至本冻结版，已知历史失败机制、切换边界、限幅、抗积分饱和、通信、回并网和诊断均已有明确处理，没有已知结构遗漏。

---

# 1. 设计目标

最终目标不是要求：

```text
V = 1.000000 pu
F = 50.000000 Hz
完全无纹波
```

V4.8 第一阶段工程目标是：

```text
J1真实断开，孤岛持续 ≥ 15 s
系统不发散
0.05~2 Hz 后期不增长
5~30 Hz 后期不增长

Late Vmean ∈ [0.90, 1.10] pu
优选 [0.95, 1.05] pu

Late Fmean ∈ [49.5, 50.5] Hz
且无持续 49~51 Hz 越界

CurrentLimit 不持续
raw modulation demand / ModIndex 不长期贴极限
Secondary 不 windup
```

小幅有界振荡允许存在。

---

# 2. V4.7 Primary 完整冻结

V4.8 第一版禁止修改：

```text
ESS1 GFM
F21 / F24 / F25
Frame / MasterF

五台 Power Control P PI
五台旧 Q PI 参数
V4.7 q-base track/hold
V4.7 Qref selector
V4.7 Q-authority recovery blend
Stage2/3/4 Qerror=0

Kslow = 0.5
Kfast = 0
slow-q Kmag = 0.25
slow-q fc = 1 Hz
5~20 Hz active damping
V4.6 LFQ 0.18~0.35 Hz
P/f Primary
现有 Manager LimitCore
现有 current-circle / role protection

Current PI Kp=0.3 Ki=20
Rff / Lff
```

硬约束：

```text
Stage0 / Stage1 / Stage2：
V4.8 q-bias 必须为0

因此 Stage2 FinalIref(V4.8)
必须等于 Stage2 FinalIref(V4.7)
```

---

# 3. 旧 Voltage Secondary 退出物理控制

当前旧路径：

```text
PCC voltage error
→ AA15_STATE_VSEC
→ dVSecondary
→ 五台 VsupportRef
→ slow-q
```

正式数据已经证明：

```text
Late dVSecondary = -0.05 pu
Desired-direction limit fraction = 1
Late Vmean ≈ 1.164 pu
```

说明旧 Secondary 不是没动作，而是执行方式/权限不足。

V4.8 冻结：

```text
AA15_P_KI_V_SECONDARY = 0
AA15_P_VSEC_LIMIT_PU  = 0
```

双重关闭旧 Voltage Secondary 的物理作用。

保留：

```text
AA15_STATE_VSEC
Coordinator Core
Frequency Secondary
P/f Primary
P capability allocation
dVSecondary 诊断
```

预期 V4.8：

```text
dVSecondary ≈ 0
```

它成为“旧 Voltage Secondary 已退出”的诊断证据。

---

# 4. 新中央 q-bias Secondary

新增：

```text
K26_V5/SM_Master/AA15_V48_ISLAND_QBIAS_COORDINATOR
```

职责唯一：

> 根据 PCC 电压的慢误差，建立一个新的、可保持非零的岛内稳态 q 轴电流偏置总量 `QbiasTotal`。

它不是：

```text
0.25Hz阻尼器
Q固定值跟踪器
Current控制器
P/f控制器
```

---

# 5. 电压目标不是人工设置 q-bias

用户设定/控制器冻结的是：

```text
电压目标
```

不是：

```text
Qbias = 某个固定数
```

Vtarget：

```text
Stage0/1:
Vpcc_pre = PCC_Vab_RMS / 10000

Vtarget =
clamp(Vpcc_pre, 0.99, 1.01)

如果捕获无效：
Vtarget = 1.0
```

Stage2~5：

```text
Vtarget hold
```

正式 Full 的捕获值为：

```text
1.001922315 pu
```

因此当前工况下实际目标约：

```text
1.001922315 pu
```

---

# 6. 新 Secondary 电压误差

冻结：

```text
eV_raw = Vtarget - Vpcc
```

高电压：

```text
Vpcc > Vtarget
→ eV < 0
→ 需要 positive q-axis correction
```

因此：

```text
dQbias/dt = -Ki_qbias * eV_filtered
```

---

# 7. 新增显式慢误差低通，防止重新碰 0.25 Hz Primary 模态

数值设计 R2 给出的 6 s acquisition time-scale 已通过 0.25 Hz 时间尺度门。

最终冻结再增加一层明确带宽隔离：

```text
V48_QBIAS_VERR_FC_HZ = 0.10 Hz
```

离散一阶低通：

```text
alpha = 1-exp(-2*pi*fc*Ts)
eVf[k+1] = eVf[k] + alpha*(eV_raw-eVf[k])
```

意义：

- 新 q-bias 只看非常慢的稳态电压偏差；
- 不专门处理 0.25 Hz；
- 不重新承担 V4.6 LFQ 或 5~20 Hz damping 的职责。

---

# 8. 中央 q-bias 最终参数

Numeric Design R2 证据：

```text
Observed steady q-support sizing scale
= 0.293714280 puIqSum

Observed peak support scale
= 0.403656129 puIqSum

Aggregate nominal support residual
= 0.706285720 puIqSum
```

冻结参数：

```text
Ts                          = 0.0001 s
Vnom                        = 10000 V

Vtarget clamp               = [0.99, 1.01] pu
Verror LPF fc               = 0.10 Hz
Verror deadband             = 0.01 pu

Secondary entry delay       = 0.50 s
Ki_qbias                    = 0.30 puIqSum/(puV*s)
QbiasTotal limit            = ±0.45 puIqSum
normal acquisition slew     = 0.05 puIqSum/s
sign-reversal release slew  = 0.15 puIqSum/s
anti-windup tracking slew   = 0.10 puIqSum/s
request/applied mismatch tol= 0.02 puIqSum
capability epsilon          = 1e-4 puIq
```

`0.293714` 只是量级证据，不是固定设定点。

真正最终 `QbiasTotal`：

```text
由闭环自动寻找。
```

---

# 9. 中央只有一个 active voltage-restoration integrator

新增唯一积分状态：

```text
AA15_STATE_QBIAS_TOTAL
```

同时有：

```text
AA15_STATE_VTARGET
AA15_STATE_VERR_FILT
AA15_STATE_QBIAS_PREV_STAGE
AA15_STATE_QBIAS_TIMER
```

全部显式 UnitDelay，Ts=100 us。

禁止：

```text
persistent
第二个并行 voltage integrator
旧 VSEC 与新 q-bias 同时积分
```

---

# 10. 中央 Stage 行为

## Stage0 / Stage1

```text
QbiasTotal = 0
qsec requests = 0
捕获 Vtarget
```

## Stage2

```text
QbiasTotal = 0
qsec requests = 0
Primary exact V4.7
```

## Stage3 / Stage4

连续 Secondary-active 区域。

首次进入 Stage3/4：

```text
timer = 0
```

Stage3→Stage4 不重新清 timer。

达到：

```text
0.50 s
```

以后才允许 q-bias acquisition。

## Stage5

中央：

```text
QbiasTotal = 0
qsec request = 0
```

Stage5 的 bumpless release 由五台本地 finalizer 负责。

---

# 11. deadband 的正确行为

当：

```text
|eV_filtered| <= 0.01 pu
```

不是：

```text
QbiasTotal -> 0
```

而是：

```text
QbiasTotal HOLD
```

原因：

> 电压回到目标以后，孤岛仍可能需要非零稳态 q-bias。

---

# 12. sign reversal 的正确行为

如果：

```text
当前 QbiasState
```

与当前电压误差要求的新修正方向相反：

```text
先以 0.15 puIqSum/s
单调释放到0

不能同一拍穿过0

到0之后
才允许反方向 acquisition
```

这是直接吸收 V4.6 VSEC stale-state 的成功经验。

---

# 13. 中央 capability-aware allocation

每台返回：

```text
CapPos_i
CapNeg_i
IqSecApplied_i
```

中央：

```text
CapPosTotal = Σ CapPos_i
CapNegTotal = Σ CapNeg_i
QbiasApplied = Σ IqSecApplied_i
```

如果：

```text
QbiasState >= 0
```

则：

```text
Qalloc =
min(QbiasState, CapPosTotal)

request_i =
Qalloc * CapPos_i / CapPosTotal
```

负方向同理使用 CapNeg。

因此中央不会故意发送一个已知超过返回能力的分配。

---

# 14. anti-windup 采用 actual-applied，而不是 request

如果：

```text
QbiasState 与 QbiasApplied
差值 > 0.02
```

且电压误差仍要求继续向不可实现方向增加：

```text
停止 error integration

QbiasState
以 0.10 puIqSum/s
向 QbiasApplied 有界跟踪
```

如果当前方向总 capability：

```text
<= 1e-4
```

则：

```text
AuthorityExhausted = 1
禁止继续同方向积分
```

宁可留下电压偏差，不允许为追1pu破坏稳定。

---

# 15. q-bias 复用现有 Qref scalar transport

R2 已证明每台现有 Qref scalar 在设备根层只有：

```text
Manager input6
diag row27
```

两个消费者。

Master 设备包 input7 继续复用。

但为避免语义污染，V4.8 新增**两级显式编码/解码**。

---

# 16. Master Qref/Qbias Router

每台 Master 新增：

```text
AA15_V48_QREF_QBIAS_ROUTER_<device>
```

输入：

```text
Stage
LegacyQref
QsecRequest
```

输出到原 device IO Mux input7：

```text
Stage0/1/2 = LegacyQref
Stage3/4   = QsecRequest
Stage5     = LegacyQref
```

---

# 17. Slave Qref Slot Decoder

每台控制器根层新增：

```text
AA15_V48_QREF_SLOT_DECODER
```

显式 UnitDelay：

```text
AA15_STATE_LEGACY_QREF
```

行为：

```text
Stage0/1/2/5:
Manager legacy Qref = slot
qsec request = 0
legacy state tracks slot

Stage3/4:
Manager legacy Qref = held legacy state
qsec request = slot
legacy state hold
```

因此：

- Manager input6 始终保持“Legacy Qref”的真实语义；
- diag row27 始终保持“Legacy QrefCmd”的真实语义；
- qsec request 有独立新诊断；
- Stage5 恢复旧 Q PI 时不会把 qsec 当 Qref。

---

# 18. 为什么不会重新激活旧 Q PI

V4.7 Qref selector 保持原 hash。

Stage2/3/4：

```text
QrefEff = Qmeas
Qerror = 0
```

所以即使 transport slot 在 Stage3/4 传 qsec：

```text
旧 Q PI 仍没有孤岛物理控制权。
```

---

# 19. Local q-bias finalizer 位置最终冻结

每台：

```text
AA15_ISLAND_GFL_SUPPORT_MANAGER out2
    Primary FinalIref
        ↓
NEW AA15_V48_QBIAS_FINALIZER
        ↓
Goto18 / IdIq_refF
        ↓
原 Switch / Goto19 / From24
        ↓
Current Regulator input3
```

这比修改 Manager 内 LimitCore 更安全。

V4.7 Manager 继续作为冻结黑箱。

---

# 20. Local finalizer 输入

每台 finalizer 输入：

```text
1 Primary FinalIref [d q]
2 Primary actual Support [d q]
3 Qsec transport request
4 Stage
5 Raw modulation demand
```

内部参数：

```text
Imax = 1.20

IsupMax:
PV1 0.20
PV2 0.20
ESS2 0.30
EV1 0.15
EV2 0.15
```

---

# 21. local current-circle hard residual

设 Primary 输出：

```text
Id0, Iq0
```

若：

```text
|Id0| > Imax
```

则：

```text
Secondary q capability = 0
```

否则：

```text
qI = sqrt(Imax²-Id0²)

current_lo = -qI-Iq0
current_hi = +qI-Iq0
```

---

# 22. local support-budget hard residual

设 Primary actual support：

```text
SupD, SupQ
```

若：

```text
|SupD| > IsupMax
```

则：

```text
Secondary q capability = 0
```

否则：

```text
qS = sqrt(IsupMax²-SupD²)

support_lo = -qS-SupQ
support_hi = +qS-SupQ
```

最终 hard interval：

```text
hard_lo=max(current_lo,support_lo)
hard_hi=min(current_hi,support_hi)
```

若：

```text
hard_lo > hard_hi
```

Secondary capability=0。

---

# 23. raw modulation demand

R2 已精确锁定：

```text
Vref Generation/
Complex to
Magnitude-Angle
output1
```

在：

```text
Saturation [0,1]
```

之前。

冻结：

```text
Mraw = 该 output1
```

---

# 24. modulation 必须显式延迟

每台 finalizer：

```text
Mraw
↓
AA15_STATE_MRAW_Z1
↓
10 Hz 一阶 filter
↓
3-state modulation supervisor
```

禁止 same-sample：

```text
Mraw -> Iref
```

因此不会新增：

```text
Iref -> Current PI -> Vconv -> Mraw -> Iref
```

代数/高速反馈环。

---

# 25. modulation thresholds

Numeric Design R2 冻结：

```text
filter fc        = 10 Hz
persistence      = 0.05 s

soft enter       = 0.95
soft exit        = 0.92

hard enter       = 0.98
hard exit        = 0.95
```

状态：

```text
HEALTHY
DERATING
HARD
```

---

# 26. ModHeadroom

```text
HEALTHY:
hM = 1

DERATING:
hM 在 0.95~0.98 之间
连续线性 1 -> 0

HARD:
hM = 0
```

调制约束只限制 Secondary。

不直接修改：

```text
Primary damping
slow-q
base current
Current PI
```

---

# 27. local directional capability

先由 hard interval 得到：

```text
baseCapPos=max(hard_hi,0)
baseCapNeg=max(-hard_lo,0)
```

再：

```text
CapPos = baseCapPos * ModHeadroom
CapNeg = baseCapNeg * ModHeadroom
```

这是发给中央的真实 Secondary supervisory capability。

---

# 28. qsec 本地状态

新增：

```text
AA15_STATE_QSEC
```

正常 acquisition：

```text
0.05 puIq/s/device
```

capability loss / command reduction：

```text
0.10 puIq/s/device
```

即：

```text
release > acquisition
```

调制压力出现后，Secondary 退出比进入更快，但仍连续。

---

# 29. 本拍硬安全和下一拍 soft control 分开

采样 k：

```text
qsec_used(k)
=
clamp(qsec_z(k), hard interval(k))
```

因此本拍严格保证：

```text
current circle
support budget
```

然后根据：

```text
QsecRequest
ModHeadroom
```

得到下一拍：

```text
qsec_next
```

所以：

- hard safety 可以立即生效；
- modulation derating 不产生一拍 q 电流跳变；
- 无代数环。

---

# 30. Stage0/1/2 local exact bypass

```text
qsec_used = 0
qsec_state = 0
```

输出：

```text
Actual FinalIref
=
Primary FinalIref
```

这就是 V4.8 Stage2 exact V4.7 的结构保证。

---

# 31. Stage5 bumpless release

每台新增：

```text
AA15_STATE_QSEC_HOLD
AA15_STATE_QSEC_REC_BLEND
```

Stage5 首拍捕获最后 island qsec。

然后：

```text
beta_sec += 0.0002 / sample
```

Ts=100 us：

```text
约0.5 s
```

输出：

```text
IqSecUsed =
(1-beta_sec)*IqSecHeld
```

同步于 V4.7 原：

```text
Q PI authority 0 -> 1
```

实现：

```text
qsec 淡出
旧 Q PI 淡入
```

---

# 32. total Support 诊断语义继续保持

V4.7 row29/30：

```text
actual total support
```

V4.8：

```text
TotalSupportD = PrimarySupportD
TotalSupportQ = PrimarySupportQ + IqSecApplied
```

所以 row29/30 的语义保持不变，只是增加了 Secondary 真正执行量。

---

# 33. Device diag48

现有 1~41 行保留原语义。

其中重新接线：

```text
03-04 = finalizer 后真正 FinalIref
29-30 = 包含 qsec 的 actual total support
27     = legacy QrefCmd，保持原语义
```

追加：

```text
42 RawModDemand
43 ModHeadroom
44 IqSecTransportRequest
45 IqSecApplied
46 QsecCapPos
47 QsecCapNeg
48 QsecClip
```

---

# 34. Device OpWrite 宽度

冻结：

```text
G26 EV1+EV2 : 82 -> 96
G27 ESS2    : 41 -> 48
G28 PV1+PV2 : 82 -> 96
G30 ESS1    : 128 unchanged
```

---

# 35. Capability return

每台只回：

```text
[CapPos, CapNeg, IqSecApplied]
```

三标量。

使用 unique global Goto/From 只在**同一 Slave 分区内部**从嵌套 controller 送到该 Slave 顶层返回 Mux。

不跨 RT-LAB 分区使用 Goto/From。

---

# 36. Slave return payload

R3 已锁定旧 unpack。

Patch 后：

## PV

Slave return Mux：

```text
old input1 PV1 Pmeas
old input2 PV2 Pmeas
new input3 PV1 cap3
new input4 PV2 cap3
```

宽度：

```text
2 -> 8
```

Master `Demux2`：

```text
2
->
[1 1 3 3]
```

原 output1/2 消费者完全保留。

## ESS

Slave return Mux：

```text
5 inputs -> 6 inputs
new input6 = ESS2 cap3
```

宽度：

```text
30 -> 33
```

Master `Demux1`：

```text
[1 1 1 1 26]
->
[1 1 1 1 26 3]
```

原 output1~5 消费者完全保留。

## EV

```text
2 -> 8
Demux:
2 -> [1 1 3 3]
```

原 output1/2 消费者完全保留。

---

# 37. OpComm3

端口数量保持：

```text
3 inputs
3 outputs
```

只改变编译宽度：

```text
[2 30 2]
->
[8 33 8]
```

---

# 38. 中央 capability unpack

SM 新增五个：

```text
AA15_V48_PV1_CAP_DEMUX3
AA15_V48_PV2_CAP_DEMUX3
AA15_V48_ESS2_CAP_DEMUX3
AA15_V48_EV1_CAP_DEMUX3
AA15_V48_EV2_CAP_DEMUX3
```

每个输出：

```text
1 CapPos
2 CapNeg
3 Applied
```

进入中央 q-bias coordinator。

---

# 39. Master Qref/Qbias transport routers

五台现有 device IO Mux：

```text
input7
```

从：

```text
legacy Qref
```

改为：

```text
AA15_V48_QREF_QBIAS_ROUTER
```

其他 device IO Mux input1~6/8 全部冻结。

设备包宽度仍：

```text
12
```

---

# 40. Central G29 diagnostics

现有 38 行全部保留。

新增：

```text
39 Vtarget_pu
40 FilteredVoltageError_pu
41 QbiasTotalState
42 QbiasAppliedTotal
43 CapPosTotal
44 CapNegTotal
45 QbiasIntegrating
46 AuthorityExhausted
```

G29：

```text
38 -> 46
```

MAT 含时间：

```text
47 columns
```

---

# 41. 最终 OpWrite 宽度冻结

```text
G26 = 96
G27 = 48
G28 = 96
G29 = 46
G30 = 128
```

恰好五个 OpWrite，数量不变。

---

# 42. Patch 修改范围

V4.8 只允许：

1. 把旧 Voltage Secondary 两个参数置0；
2. SM 新增中央 q-bias coordinator；
3. SM 新增五台 Qref/Qbias routers；
4. SM 扩展能力反馈 unpack；
5. 五台 controller 新增 Qref slot decoder；
6. 五台 controller 新增 root-level q-bias finalizer；
7. 五台增加 cap3 分区内返回；
8. 三个 Slave return payload 扩宽；
9. 三个 Master return Demux 扩展；
10. diag41→diag48；
11. G29 38→46。

明确禁止其他改动。

---

# 43. Patch 事务要求

正式 Patch 必须：

```text
SimulationStatus = stopped
Dirty = off
exact baseline SHA

R2/R3 已审计结构硬断言
V4.7 frozen hashes硬断言
scratch compile 新模块
full SLX backup

edit
strict compile AlgebraicLoopMsg=error
compiled width audit
unconnected-port audit
old-consumer preservation audit

save_system exactly once

close/reload
persistence audit
strict compile again

任一 post-save FAIL
→ whole-file rollback
```

---

# 44. Patch 后不能立即 Rebuild

必须先跑独立 Verifier。

Verifier 必须证明：

```text
旧 V4.7 Primary hashes不变
old VSEC Ki/limit = 0

new core hashes exact
Stage0/1/2 bypass结构
Qref decode/router结构
finalizer current/support hard limits结构
Mraw UnitDelay
capability return widths
OpComm3 [8 33 8]
diag48
G29=46
OpWrite [96 48 96 46 128]

AlgebraicLoopMsg=error strict compile
```

只有 Verifier PASS 才允许 RT-LAB Rebuild All。

---

# 45. 最终验收顺序

Patch + Verifier + Rebuild 后：

## Test A：Primary-only

仍然先做 Stage2-only。

目的不是重新找根因，而是确认：

```text
V4.8 Stage2 exact transparency
历史 sub-Hz / 5~30Hz 衰减没有被破坏
```

## Test B：Full

Stage3 q-bias 工作。

目标：

```text
Late Vmean 0.90~1.10
频率合格
Qbias收敛
旧dVSecondary≈0
无持续CurrentLimit
无持续modulation saturation
0.05~2Hz不增长
5~30Hz不增长
```

---

# 46. 冻结结论

> **V4.8 正式冻结为：完整保留 V4.7 Primary；关闭旧 Voltage Secondary 的物理积分作用；新增唯一中央 0.10 Hz 慢误差驱动的 q-bias Secondary；复用 Qref 标量通道但通过 Stage-aware Router/Decoder 保持 legacy Qref 语义；在五台 Manager 之后增加 root-level q-bias finalizer；Secondary 只能使用 current-circle 与 support-budget 的剩余 q 能力，并由一拍延迟、10 Hz 滤波、带 persistence/hysteresis 的 raw modulation demand 进一步降额；中央根据 CapPos/CapNeg 比例分配，并使用真实 IqSecApplied 做 anti-windup；Stage5 用0.5 s与 V4.7 Q PI 同步完成 qsec 淡出和旧Q控制权恢复。结构审计 R2/R3 与数值设计 R2 均已通过，因此允许进入事务式 Patch。**


---

# 47. V4.8 新 MATLAB Function 正文身份

正式 Patch / Verifier 使用以下内容 SHA256：

```text
AA15_V48_QBIAS_COORD_CORE
bb471e1f737dbae0807170770a969778ce9d9bb79d84e3bf5f22be0ca5c361f0

AA15_V48_ROUTER_CORE
34627ffb5205cf1d7107ecdf7bc3fa36916f25084df87512963d6cebae37cea2

AA15_V48_QREF_DECODER_CORE
3017f933023900140313fe862d71048ddc30371196dbd882579707b6701ceb85

AA15_V48_FINALIZER_CORE
711acba35f46da411e0a78baed6ecb1c4c01dc0f59e0349de3ffaf8b28882866
```

这些哈希是 V4.8 新控制逻辑的正文身份；Patch 后必须由独立 Verifier 精确复核。
