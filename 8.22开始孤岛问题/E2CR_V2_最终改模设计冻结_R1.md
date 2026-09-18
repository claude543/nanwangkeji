# E2CR V2 最终改模设计冻结 R1

日期：2026-09-19  
正式基线：当前已 Build 成功的 `K26_K50_CLEAN_P1`  
本文件依据：V2 全模型只读审计结果 + FileID `745142806` 的 100 s 动态证据。  
状态：**架构、修改边界、接口、记录和验证流程冻结；控制增益仍属于首轮工程候选，必须在线暴露并由动态试验验证。**

---

# 0. 先给结论

## 0.1 静态审计是否已经“无死角”

本次正式审计完成：

- source SHA before/after 相同：`3b46324d12a7b2a98d4f9628e48357ade8e77f5967fca9ffe9de489aa5f9e1ca`
- Dirty：`off → off`
- SimulationStatus：`stopped`
- visible blocks：14992
- scoped blocks：14253
- direct edges：15155
- exported MATLAB/Stateflow functions：100
- parameters：404245
- native tags：3337
- critical input traces：952
- 35/35 个 V2 设计问题均有实际锚点，`MissingAnchors = 0`
- blocker：0
- review：10

因此不能把工具原始状态写成“0 review”。但 10 个 review 已在本轮人工闭合为**显式边界，不构成 V2 改模未知项**：

1. `SM_Master/From1`：`IabcPriSTUB`，属于显式 STUB 边界；
2. `SM_Master/From7`：`VabcPriSTUB`，属于显式 STUB 边界；
3. `ESS1_Control` input12 `F4_J1_CLOSED_APPLIED_RX`：来自 `OpComm_ESS_Group` out2，厂家/通信边界；
4. `ESS1_GFM_ISLAND_HANDOVER` input1 `pll_f`：来自 `Measurements/PLL (3ph)`，库/测量边界；
5. handover input22 `j1_closed`：同一 OpComm J1事实；
6. handover input23 `f23_j1_actual`：同一 OpComm J1事实；
7. handover input25 `j1_closed1`：同一 OpComm J1事实；
8. F24 manager input3 `pll_f`：同一 PLL 测量边界；
9. F24 manager input8 `j1_closed`：同一 OpComm J1事实；
10. ESS2 Power Control Loop input2 `VdVq`：来自现有 Measurements/Second-Order Filter7，已验证测量链。

这些路径均不属于本次修改对象；本次设计不进入库内部，不修改 PLL、OpComm 厂家内部或 ESS2 测量滤波器。

**所以：在“下一次改模需要知道的静态结构/控制权/端口/记录/通信”层面，当前设计输入已闭合，可以冻结。**

但“无死角”不等于：
- 新 Patch 必然一次 Build PASS；
- 新增控制增益一定最优；
- RT-LAB 动态一定稳定。

这些必须分别由 scratch Update/compile、RT-LAB Build、Target Verify 和动态 MAT 验证。

---

# 1. 100 s 真实数据已经冻结的根因

FileID `745142806` 故障前：

- Vpu = 0.802696
- PLL = 50.147878 Hz
- ESS2 Imeas = 0.285684 pu
- CurrentLimit = 0
- ModHeadroom = 1
- Pbase = -0.014506 pu
- Primary = -0.067375 pu
- old Frequency Secondary = -0.134635 pu
- Pcmd = -0.216507 pu
- Primary + Secondary 占最终有功请求绝对值约 93.3%
- Pbase 仅约 6.7%
- ESS1 Pdroop = +0.190281 pu
- ESS2 Pmeas = -0.174449 pu
- ESS1 + ESS2 ≈ +0.015832 pu，仅约 1.58 kW 净负荷+损耗
- 现有 Droop 预测 f = 50.154859 Hz，实测 = 50.147878 Hz

因此冻结：

> **V1不是 Pbase/Normal Responsibility 根本没有实现，而是旧 `Frequency Secondary → GFL P` 仍保留了长期积分控制权，把新的“ESS1负担 → ESS2 Pbase慢分担”压住了。**

电压侧同理：

> V4.8 中央 `Verror → qstate → GFL q-bias` 仍是第二套长期母线电压慢积分执行路径；黑启动只有 ESS2 available 时，几乎等价于 ESS2 独自承担这条慢电压恢复。

---

# 2. V2 的唯一架构原则

V2 把三个概念彻底分开：

## 2.1 Bus Reference Restoration（母线基准恢复）

唯一 GFM ESS1 负责：
- 长期频率目标：通过 ESS1 `Fref`
- 长期电压目标：通过 ESS1 `Vref`

## 2.2 Resource Dispatch（资源分担）

Normal Coordinator 负责：
- ESS2/PV/EV 等 GFL 的正常 P/Q 任务；
- ESS1 长期负担/备用恢复；
- 未来 EMS/SOC 任务；
- 有限、快速的 Primary。

## 2.3 Capability Envelope（能力包络）

它不是第二个协调器，只回答：
- 每台设备现在 P/Q 哪个方向能做多少；
- 设备自身 current/modulation/SOC/health 是否允许；
- 网络状态是否允许继续朝某个方向调节。

---

# 3. 已验证保护区：本次绝对不动

1. SPS/ARTEMiS/SSN 物理网络；
2. J1、ESS2 真实 breaker chain；
3. ESS1 GFM 内层 Voltage/Current 控制；
4. ESS1 Droop 主体公式与块内部；
5. F24 计划孤岛参考交接算法主体；
6. ESS2 Restore state0~7；
7. ESS2 P PI `Kp=0.06 / Ki=0.5`；
8. ESS2 Current Regulator；
9. Current Adapter；
10. ESS2同期/真实合闸/CONNECTED_ZERO；
11. S14-40 / S14-50 / 已验证 ownership blend；
12. S14-60 已验证小权限 Primary 起点；
13. GFL Stage0/1/2 已验证弱网结构；
14. planned-island 在 `S14 inactive` 时原行为。

---

# 4. 精确修改点一：ESS1 GFM Reference Secondary

## 4.1 审计锁定的真实参考链

当前真实链：

```text
F24_REFERENCE_HANDOVER_MANAGER out1 f_eff
→ AA15_F24_EFFECTIVE_FV_MUX / handover out1
→ P6_GOTO_0199
→ P6_FROM_0199_01
→ Droop Control input1

F24_REFERENCE_HANDOVER_MANAGER out2 v_eff
→ AA15_F24_EFFECTIVE_FV_MUX / handover out2
→ P6_GOTO_0200
→ P6_FROM_0200_01
→ Droop Control input2
```

因此 V2 **不进入 Droop Control 内部，也不修改 F24**。

### 冻结插入位置

在 `AA15_ESS1_GFM_ISLAND_HANDOVER` 内：

```text
F24 f_eff ───────────────┐
                         + → Fref_V2_final → 原 P6_GOTO_0199 → Droop input1
ΔFref_secondary ─────────┘

F24 v_eff ───────────────┐
                         + → Vref_V2_final → 原 P6_GOTO_0200 → Droop input2
ΔVref_secondary ─────────┘
```

这是本次唯一允许修改 ESS1 reference ownership 的位置。

## 4.2 为什么放这里

- F24 仍完整拥有计划孤岛/参考交接；
- S15 Master Fref Router 仍作为 upstream legacy/base reference；
- V2 只是在最终进入 Droop 前叠加黑启动慢 bias；
- `S14 inactive` 或 V2 disabled 时 bias=0，因此 planned-island 精确旁路；
- 不需要修改 ESS1 内层 GFM；
- 不需要扩 OpComm 传输 Fref/Vref bias。

## 4.3 本地已有输入，无需新增跨任务测量

SS_Slave2 当前已经有：
- `pll_f`：ESS1 Measurements/PLL；
- `Vq`：F2 voltage selected path；
- F24 `f_eff/v_eff`；
- S14 phase：现有 SM→SS 27维第26标量，即 `ESS_Group_Demux` out4。

所以新 manager 放在 SS_Slave2/ESS1 handover 内，不需要把 f/V 测量来回跨任务。

---

# 5. GFM Fref Secondary 的固定实现

优先使用普通 Simulink 块，不新增大型 MATLAB Function。

逻辑：

```text
f_target = F24 f_eff
e_f = f_target - pll_f
→ 一阶低通
→ deadband
→ Ki
→ derivative slew clamp
→ conditional integration
→ bias saturation
→ ΔFref
→ Fref_final = F24 f_eff + ΔFref
```

状态规则：

- phase < 70：bias reset=0；
- phase 70/75/80/88：积分允许；
- phase90：冻结最后 bias，不继续积分、不突然归零；
- S14/V2 inactive：bias=0，完全旁路；
- 模型 Reset：状态回0。

第一版在线可调候选：
- `CFG_E2V2_FSEC_KI = 0.10 1/s`
- `CFG_E2V2_FSEC_FILTER_TAU_S = 1.0 s`
- `CFG_E2V2_FSEC_DEADBAND_HZ = 0.01 Hz`
- `CFG_E2V2_FSEC_BIAS_MIN_HZ = -0.50 Hz`
- `CFG_E2V2_FSEC_BIAS_MAX_HZ = +0.50 Hz`
- `CFG_E2V2_FSEC_SLEW_HZ_S = 0.02 Hz/s`

这些是**首轮工程候选，不是最终稳定性定值**。

---

# 6. GFM Vref Secondary 的固定实现

同样放在 F24 v_eff 与 Droop input2 之间。

目标不硬编码成“当前测量”，而取：

```text
Vtarget_pu = F24_v_eff / Vnom
```

因此上游正式电压目标若变化，V2自动跟随。

```text
e_v = Vtarget_pu - Vq_meas
→ 一阶低通
→ deadband
→ Ki
→ slew clamp
→ conditional integration
→ bias saturation
→ ΔVref_pu
→ Vref_final = F24_v_eff + ΔVref_pu * Vnom
```

状态：

- phase <75：bias=0；
- phase75/80/88：允许慢积分；
- phase90：冻结；
- V2 inactive：旁路。

候选参数：
- `CFG_E2V2_VSEC_KI = 0.10 1/s`
- `CFG_E2V2_VSEC_FILTER_TAU_S = 1.0 s`
- `CFG_E2V2_VSEC_DEADBAND_PU = 0.005`
- `CFG_E2V2_VSEC_BIAS_MIN_PU = -0.10`
- `CFG_E2V2_VSEC_BIAS_MAX_PU = +0.10`
- `CFG_E2V2_VSEC_SLEW_PU_S = 0.01 pu/s`

---

# 7. 精确修改点二：旧 P Secondary 从黑启动 ESS2 最终P退出

现有 Coordinator 旧逻辑：

```text
filtered frequency error
├─ Primary
└─ psecz / Frequency Secondary integral

dpt = Primary + Secondary
→ available resource allocation
```

V1 `crCompleteStep` 又继续把：
- `pb3`
- `Primary`
- `x = Secondary`
组合成 ESS2 最终P。

这就是100 s运行中93.3%频率链的来源。

## V2冻结

### S14/V2 active

ESS2最终有功：

```text
P2_final = P2_base + bounded Primary
```

**不存在 `+ old Frequency Secondary integral`。**

处理：
- old `psecz/psecn` 在 V2黑启动阶段保持0；
- `dp_secondary=0`；
- `secondaryEnable` 不再代表 old GFL P-secondary；
- legacy planned-island (`S14 inactive`) 原 Secondary 行为完全保留。

---

# 8. Primary 的正确职责与限幅

Primary 不删除。

它代表：
- 快速辅助；
- 比较快的 P-f 比例作用；
- 不形成长期积分偏置。

V2 将“正常P调度能力”和“Primary authority”彻底分开。

阶段：
- S14-60/70/75：维持已验证 small Primary authority；
- S14-80/88：允许 Primary authority 在 release fraction 下从小权限逐渐到正常候选权限；
- Primary 永远不直接等于整台设备 P capability。

候选：
- 已验证起点 `0.001 pu`
- 正常候选 `CFG_E2V2_PRIMARY_AUTH_NORMAL = 0.005 pu`
- 该值在线暴露，可后续增大；首轮不直接给0.02/1.0。

---

# 9. 精确修改点三：Normal Responsibility 不再使用 Droop 50 Hz 平衡点

V1 `crCompleteStep` 当前使用：

```text
eq = (Fref + Fn*Df/200 - Fn) / (Fn*Df*DroopEnable/100)
```

在 Fref=50、Df=1 时把 ESS1 合理负担中心等价到约0.5 pu。

这正是V2必须删除的假设。

## V2新的 P1 burden center

进入 S14-80 时：

```text
P1_center = 当前低通后的 ESS1 P
```

仅捕获一次，不逐拍追踪。

```text
P1_low  = max(P1_center - band, ESS1_Pmin)
P1_high = min(P1_center + band, ESS1_Pmax)
```

行为：

```text
P1 > P1_high
→ ESS2 Pbase 增加供电 / 减少吸收

P1 < P1_low
→ ESS2 Pbase 减少供电 / 增加吸收

P1在band内
→ Pbase保持
```

保留 V1 已有：
- P1低通；
- deadband/hysteresis；
- Pbase rate limit；
- ESS1/ESS2 joint range；
- SOC；
- current/modulation capability。

删除：
- 以 Droop 的50Hz理论平衡点作为P1长期目标；
- 因该理论点驱动ESS2制造内部功率循环。

现有候选参数继续可复用：
- burden tau = 5 s
- band 初始候选 = 0.10 pu
- hysteresis = 0.01 pu
- burden gain = 0.02 /s
- Pbase slew = 0.005 pu/s

---

# 10. 精确修改点四：网络方向性 Capability Derating

Capability分两层：

## 10.1 Device capability

保留 V1：
- ESS1 Pmin/Pmax/valid；
- ESS2 Pmin/Pmax/valid；
- current circle；
- modulation；
- SOC；
- power residual。

## 10.2 Network directional capability

新增 `E2V2_NETWORK_DIRECTIONAL_DERATE`，放在 SM Normal Coordinator 的能力进入点，不是新协调器。

低压：

```text
只收紧“ESS2继续增加吸收”的下限方向
允许“减少吸收 / 增加供电”的恢复方向
```

数学：

若原 `[L,U]`，当前 `P2`，低压降额系数 `gL∈[0,1]`：

```text
L_eff = P2 + gL*(L-P2)
U_eff = U
```

高压反向：

```text
L_eff = L
U_eff = P2 + gH*(U-P2)
```

候选软阈值：
- low start = 0.95 pu
- low full = 0.90 pu
- high start = 1.05 pu
- high full = 1.10 pu

0.8/1.2 等原严重保护完全保留，软降额不替代保护。

Python Runner不以这些软阈值暂停。

---

# 11. 电压慢环：旧 q-bias 职责必须退出，但执行链保留

当前 V4.8：

```text
Verror
→ qstate慢积分
→ q1..q5 capability分配
→ q-bias Router
→ device Finalizer
```

V2黑启动中：

- 旧中央 `Verror → qstate` **不再承担母线Voltage Secondary**；
- `qstate` 在V2黑启动保持0；
- S14-75不再把 `crQStage` 改3去开启旧电压积分器；
- ESS2 q-bias Router / Decoder / Finalizer 保留；
- current-circle、modulation derating、CapPos/CapNeg、QsecClip全部保留；
- 这些以后作为 `Q-sharing actuator` 使用。

### 本轮第一版

为避免再次叠加慢环：
- V2首轮 `Q-sharing demand = 0`
- 先只验证 ESS1 Vref Secondary；
- ESS2维持现有qbase/旧Q PI退出语义；
- DampD/DampQ/SlowQ/LFQ仍关闭。

这不是删除Q能力，而是先消除双慢积分器。

后续Q burden sharing使用同一执行链，不再增加新的Voltage Secondary。

---

# 12. S14状态重新冻结

|S14状态|V2职责|
|---|---|
|40|原小功率资格，保持|
|50|原ownership handover，保持|
|60|已验证 small bounded Primary，保持|
|70|**ESS1 Fref Secondary ON；old GFL P Secondary OFF**|
|75|**ESS1 Vref Secondary ON；old q-bias voltage integrator OFF**|
|80|**ESS2 Normal P Responsibility Release；P1_center捕获；network derating ON**|
|88|Normal Restored：Fref/Vref Secondary + Pbase sharing + bounded Primary持续|
|90|严重故障上下文；新慢积分冻结，不突然清零；本地保护拥有trip权|

阶段推进仍遵循用户原则：
- 不用频率必须精确50 Hz作推进硬门；
- 不用电压必须精确1.0 pu作推进硬门；
- 普通波动不回退40/50/60；
- Python不因普通波动Pause/Reset；
- 只对结构无效、非有限关键数据和现有真实严重保护处理。

候选时序：
- state60 observe 3 s
- state70 observe 8 s
- state75 observe 8 s
- state80 release 20 s
- release后 observe 8 s
- 约90 s进入88，100 s留约10 s末段

---

# 13. planned-island兼容冻结

V2所有新逻辑必须满足：

```text
S14 inactive / V2 disabled
→ ΔFref=0
→ ΔVref=0
→ old planned-island P Secondary保持原逻辑
→ old q-bias保持原逻辑
→ F24/S15 reference ownership保持原逻辑
```

因此不修改：
- `AA15_S15_Master_Fref_Router_Core`
- F24 estimator/handover主体
- planned-island Stage3原 Secondary 本身

只在 `S14 active + V2 phase` 的黑启动分支改职责。

---

# 14. OpComm冻结：本轮不扩27/59

审计证明：

SM→SS 当前27维：
- 原25维保持；
- 第26标量已经是 S14/V2 phase；
- 第27是现有 support-mask 配置。

SS→SM 当前59维：
- 原45维保持；
- 后14维已经传 ESS1/ESS2 capability 摘要。

V2 GFM Reference Manager放在SS本地：
- Fref/Vref base、本地PLL/Vq、本地phase均已具备；
- 不需要把reference bias跨任务传输。

V2 P dispatch：
- ESS1 P、Pmin/Pmax、droop valid、mod raw、ESS2 Pmin/Pmax/mod/valid已有14维capability返回。

因此 **本次禁止为了“以后可能用”继续扩大OpComm**。

如果未来正式增加Q burden sharing，需要ESS1 Q等额外字段时，再单独append，不与本次架构修复混在一起。

---

# 15. 在线参数暴露冻结

## SS本地 GFM Reference Manager

新增显式Constant：
- `CFG_E2V2_FSEC_KI`
- `CFG_E2V2_FSEC_FILTER_TAU_S`
- `CFG_E2V2_FSEC_DEADBAND_HZ`
- `CFG_E2V2_FSEC_BIAS_MIN_HZ`
- `CFG_E2V2_FSEC_BIAS_MAX_HZ`
- `CFG_E2V2_FSEC_SLEW_HZ_S`
- `CFG_E2V2_VSEC_KI`
- `CFG_E2V2_VSEC_FILTER_TAU_S`
- `CFG_E2V2_VSEC_DEADBAND_PU`
- `CFG_E2V2_VSEC_BIAS_MIN_PU`
- `CFG_E2V2_VSEC_BIAS_MAX_PU`
- `CFG_E2V2_VSEC_SLEW_PU_S`

## SM正常协调/能力

保留并改义现有 E2CR config：
- ENABLE
- MAX_PHASE
- T60/T70/T75/NORMAL observe
- RELEASE_TIME
- BURDEN_TAU
- BURDEN_HALF_BAND
- BURDEN_HYST
- BURDEN_K
- BASE_SLEW
- CMD_SLEW
- MOD thresholds

新增：
- `CFG_E2V2_PRIMARY_AUTH_NORMAL`
- `CFG_E2V2_VDERATE_LOW_START`
- `CFG_E2V2_VDERATE_LOW_FULL`
- `CFG_E2V2_VDERATE_HIGH_START`
- `CFG_E2V2_VDERATE_HIGH_FULL`
- `CFG_E2V2_LAYOUT_VERSION = 1201`

所有参数：
Build后必须 `GetParametersDescription → unique discovery → write → readback → restore/prove`。

---

# 16. OpWrite记录冻结

旧行绝不重排。

## G27 ESS2
现有135 data channels保留，不新增为主；现有已经覆盖：
- Final Id/Iq
- Measured Id/Iq
- P/Q
- Pref applied
- CurrentLimit
- ModHeadroom
- RestoreState/FailCode
- local capability

## G29 中央
在现有126 data channels后append：
1. V2Mode/layout
2. OldPSecondaryRaw
3. OldPSecondaryUsed（V2应为0）
4. PrimaryAuthorityEffective
5. P1Center
6. P1BandLow
7. P1BandHigh
8. VDerateLowFactor
9. VDerateHighFactor
10. P2CapLowRaw
11. P2CapHighRaw
12. P2CapLowEffective
13. P2CapHighEffective

## G30 ESS1
在现有160 data channels后append：
1. GFMFSecondaryEnable
2. FrefBaseF24
3. FrequencyTarget
4. FrequencyErrorRaw
5. FrequencyErrorFiltered
6. FrefBias
7. FrefFinal
8. GFMVSecondaryEnable
9. VrefBaseF24
10. VoltageTargetPu
11. VoltageErrorRaw
12. VoltageErrorFiltered
13. VrefBiasPu
14. VrefFinal
15. FrefBiasAtLimit
16. VrefBiasAtLimit

新布局：
- G27仍136 rows含time
- G29变为140 rows含time
- G30变为177 rows含time
- layout version 1201

100 s、1 ms记录仍明显低于现有500 MB单文件上限。

---

# 17. Support冻结

第一轮V2：
- DampD = OFF
- DampQ = OFF
- SlowQ = OFF
- LFQ = OFF
- old q-bias Verror integrator = OFF

保留：
- terminal-V feedforward整形
- coordinate maintenance
- qbase
- current-circle
- modulation derating
- Current Adapter
-真实电流反馈

只有V2主架构稳定以后，某个support才允许单变量对照加入。

---

# 18. 后续设备复用接口冻结

PV1/PV2/EV1/EV2当前模型均已有与ESS2相同家族的：
- `AA15_GFL_ISLAND_SUPPORT`
- `AA15_V48_QBIAS_FINALIZER`
- `AA15_V49_CURRENT_EXECUTION_ADAPTER`

因此以后每台GFL统一流程：

```text
PREPARE
→ SYNC/CLOSE
→ CONNECTED_ZERO
→ SMALL_TASK_QUALIFY
→ OWNERSHIP_HANDOVER
→ CAPABILITY_VALID
→ JOIN_NORMAL_POOL
→ NORMAL_RESTORED
```

每台只需要提供统一资源字段：
- available
- Pmin/Pmax
- Qmin/Qmax（后续Q sharing阶段）
- SOC/energy
- current/modulation capability
- health

**不会再为每台GFL增加Frequency Secondary或Voltage Secondary。**

母线级 Secondary 永远只有 ESS1 GFM reference secondary。

---

# 19. 下一Patch必须遵守的事务

复用成功经验：

1. 当前模型语义preflight；
2. 数值Selftest；
3. ordinary-block Harness；
4. byte-identical scratch；
5. scratch应用修改；
6. **scratch Update Diagram + compile**；
7. 检查Function Coder；
8. 检查无代数环；
9. 检查OpComm/OpWrite必须为1-D `[1×N]`；
10. scratch save once；
11. close/reopen；
12. 再Update/compile；
13. 正式whole-file backup；
14. 正式重新preflight；
15. formal apply；
16. formal Update/compile；
17. save once；
18. close/reopen；
19. 独立只读Verifier；
20. RT-LAB Rebuild；
21. Target Verify；
22. fresh Reset/Load；
23. 最多100 s正式Runner；
24. DirectMAT。

禁止重复此前错误：
- 内部Inport数量代替PortHandles；
- 路径双拼；
- persistent污染自测；
- 生产Function塞进人工Harness；
- persistent未初始化读取；
- 同拍反馈代数环；
- OpComm Nx1；
- source parent多取一层。

---

# 20. 冻结后的唯一V2控制结构

```text
                           S14 Supervisor
                  恢复顺序 / enable / 监督 / hard context
                                 │
                  ┌──────────────┴──────────────┐
                  │                             │
          GFM Reference Secondary          Normal Coordinator
          ───────────────────────          ─────────────────
          f error → ΔFref                  Pbase / bounded Primary
          V error → ΔVref                  ESS1 burden / EMS
                  │                             │
                  ▼                             ▼
              ESS1 GFM              Device capability + network derating
          形成长期母线V/f                      │
                                                ▼
                                ESS2 / PV / EV GFL normal pool
```

这就是下一次改模唯一允许实现的架构。

---

# 21. 什么叫“本次改模成功”

结构通过：
- F24/S15/计划孤岛兼容；
- old GFL P Secondary在黑启动V2使用量=0；
- old q-bias Verror积分在黑启动V2使用量=0；
- ESS1 Fref/Vref bias真实进入Droop inputs1/2；
- P2 = Pbase + bounded Primary；
- P1 burden center来自state80入口实际工作点；
- low-V directional derating有效；
- 27/59通信不被破坏；
- 新OpWrite源线正确。

动态通过不能只看state88，必须同时看到：
- ESS1 Fref bias逐渐承担长期频差；
- ESS2 Primary不形成持续大偏置；
- 不再出现十几kW无意义内部P循环；
- Pbase只在ESS1长期偏离band时变化；
- 电压低时继续吸收方向被软收紧；
- F/V最终向目标收敛；
- CurrentLimit/Modulation无持续硬饱和；
- 100 s内无持续增长和hard fail。

---

# 22. 本设计明确未声称的内容

1. 首轮Ki、deadband、slew是工程候选，不是数学最优；
2. 本轮不同时上线Q burden sharing；
3. 本轮不恢复其它四台GFL；
4. 本轮不处理PCC重同步/上级电网合闸；
5. 本轮不删除V1诊断记录和旧support结构；
6. 本轮不修改已证明的ESS2 P PI、Current Adapter和物理恢复链。

这些不是遗漏，而是为了单变量和可验证性主动冻结的边界。
