# K26_K50｜ESS2并回新主力窗口接管与 V0.9 设计复核
**日期：2026-09-14**  
**对象：K26_K50_CLEAN_P1 / B窗口 / S14黑启动 / ESS2完整物理并回**  
**性质：接管基线 + R6证据复核 + V0.9设计审查；不修改模型，不执行RT-LAB**

---

## 0. 接管结论

本窗口可以正式接替 B 窗口继续推进。

当前断点不是“还不知道哪里错”，而是已经收敛到：

1. ESS1-only 黑启动建网已有较强动态证据支持；
2. ESS2 已完成断开待并、READY、真实 breaker close；
3. R4 已证明 ESS2 合闸以后长期停留 state4，RestoreAlpha=0、Final Iref=0，但真实电流显著存在；
4. 当前恢复逻辑在 breaker 已闭合的 state4/state5 仍输出 `RestoreHold=1`；
5. Current Adapter 在 hold 分支内执行：
   - `iref_used=0`
   - `imeas_used=0`
   - `match=1`
   - `matchTarget=0`
6. 因而真实支路电流出现后，已有 Current PI 被人为剥夺纠偏权；
7. R6 一次性审计已经把本轮正式设计需要的关键接口、物理节点、oldPI、Power PI、RestoreAlpha、breaker 链、G27 和 OpWrite 合同采集齐；
8. R6 自动 blocker 中若干是递归 trace 超出本次修改边界产生的保守 FAIL，V0.9 已结合全部证据人工关闭，当前不需要继续生成第7轮结构审计。

本窗口后续不回退到：
- “再等久一点”
- “放宽 Python Gate”
- “重跑同一个失败工况”
- “可能又是历史0.3–0.6 Hz”
- “再增加一个电流控制器”
- “重新Build当前未改模型”
等已经被证据否定或不属于当前层级的路径。

---

# 1. R6实际审计结果我已经逐项复核

## 1.1 自动明确关闭的事实

R6 closure matrix 已直接关闭：

- ESS2物理支路拓扑；
- ESS2父端口及跨任务接口；
- GFL wrapper 20输入合同；
- Current Adapter父接口7输入；
- Current Adapter Core 8输入语义；
- Power Loop 7输入合同；
- Restore Executor 5输入合同；
- oldPI来源；
- P/Q PI数值；
- double RestoreAlpha事实；
- C2/breaker-inner节点拓扑事实；
- breaker command chain；
- 5个OpWrite（G26~G30）边界；
- G27 group27 / decimation4 / 56ch 当前合同。

P/Q Power PI 当前参数已经解析：

```text
Kp = 0.06
Ki = 2
Init = 0

P PI limit = ±1.25
Q PI limit = ±1
```

Current Adapter 当前参数：

```text
Ts = 100 us
Kp = 0.3
Ki = 20
Ttrack = 15 ms
```

hold长期成立时，PI已初始化且状态趋近零；退出hold第一拍：

```text
hold = 0
alpha = 0
iref_used = 0
imeas_used = real imeas
match = 0
error = -imeas
```

第一拍未限幅近似：

```text
rawPI ≈ 0.301*(-Imeas) + 0.00664449*residualPrev
```

因此，**现有 Current Adapter 已经具有“闭合后零参考 + 真实反馈 + 正常Current PI纠偏”的能力。**

---

## 1.2 R6自动 blocker 为什么不能机械当成“还不能设计”

R6自动失败主要来自：

- recursive trace 一直追过本轮需要的语义锚点；
- 跨顶层 Goto/From 后继续进入 SM 大树导致 depth exceeded；
- 用 direct-connection 检查内部 Goto/From 状态环不适配该实现；
- Power Loop output trace 继续追到与本次局部修改无关的主任务；
- MasterF来源追踪比本轮设计需要的范围更深。

但关键人工事实已经明确：

### 实际 Current Adapter 电流反馈

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

ESS2当前为GFL，`GRIDON=1`，因此使用 PLL frame 的 `IdIq_measPLL`。

**本轮不换反馈点。**

### Current Adapter 电流参考

```text
AA15_GFL_ISLAND_SUPPORT/FinalIref
→ ESS2_Control顶层Switch
→ IdIq_refs
→ From24
→ Current Adapter
```

### Vdq前馈

```text
Measurements/VdVq_measPLL
→ VdVqF
→ Selector / Switch
→ VdVqs
→ From26
→ GFL Support
→ Current Adapter
```

**本轮不改Vdq前馈选择。**

---

# 2. 对“Function模块”的理解已经校正

用户的要求不是：

> 禁止 MATLAB Function。

而是：

> 根据控制任务的性质决定模块形式，不要因为写脚本方便就把所有逻辑都塞进 MATLAB Function，也不要为了“少用 Function”而强行把复杂算法拆成不适合的普通块。

本轮模块选择应冻结为：

| 功能 | 本轮建议实现 | 原因 |
|---|---|---|
| SPS电气测量 | 克隆当前已Build成功的 Three-Phase V-I Measurement | 这是物理对象，不应使用Function伪造 |
| 简单比较/使能 | Compare / Relational / Logic / Switch | 语义简单、可视、容易Verifier |
| 简单诊断镜像 | Product / Switch / Mux | 不需要新Function |
| Restore状态顺序 | **修改现有 Executor MATLAB Function** | 当前已Patch+Build+Target验证，迁移Stateflow会把“故障修复”和“技术栈迁移”混为一轮 |
| Current Adapter | **保留现有Function/helper，不重写** | 复杂PI/限幅/执行残差逻辑已验证，当前缺陷是调用阶段，不是helper本体 |
| G27 Repack | 修改现有Repack Function | 向量重排已有成熟实现；无需为了形式主义改成几十个块 |
| G27边界正规化 | Demux/Mux标准块 | 已有Build成功经验，解决Nx1 matrix→1-D vector边界问题 |
| 未来产品状态机 | 可单独评估Stateflow | 等ESS2/PV/EV完整恢复跑通后再做等价迁移 |

因此本轮“新增控制 MATLAB Function”仍应为 **0个**，但这不代表“Function不能用”。

---

# 3. V0.9初步改模方案逐项判断

## 3.1 可以直接保留的核心项

### A. state4/state5退出open-standby hold —— **保留，最高优先级**

```text
state1/2/3：hold=1
state4/5/6/7：hold=0
```

这是当前最强代码+动态证据共同支持的修复。

state4：

```text
breaker = CLOSED
hold = 0
alpha = 0
```

正好得到：

```text
IrefUsed = 0
ImeasUsed = actual
Current PI正常纠偏
Power尚未释放
```

### B. state3 COMMIT当拍重新检查当前READY —— **保留**

“曾经READY”不能替代“动作当拍仍READY”。

建议：

```text
request丢失 → state1
current ready丢失 → state2 + clear ready dwell
只有 current ready + breakerAct + commit → state4
```

### C. legacy MasterF退出breaker READY控制权 —— **保留**

R4已经证明：

```text
ESS2 PLL ≈ actual bus ≈ 50.233 Hz
legacy MasterF ≈ 49 Hz
```

因此当前 `abs(pllHz-masterF)` 不适合作物理同步许可。

V0.9新增：

```text
CFG_ESS2_RESTORE_FNOM_HZ = 50
abs(pllHz-fNom) <= dfMax
```

可以保留，但必须明确：

> `fNom`门只是“母线运行频率处于正常名义范围”的 sanity gate，不是两个breaker触点同步判据。

真正触点同步应由真实inner/bus电压的 phaseCorr / voltageRatio承担。

### D. 增加真实breaker-inner Vabc —— **保留**

R6已经确认：

```text
EV1_inv
= L2之前

C2/breaker-inner
= L2之后 + C2 + breaker RConn

EV1_LV_Meas
= breaker另一侧
```

当前两组proxy都不是打开breaker时两个真实触点。

建议继续采用：

```text
AA15_ESS2_BREAKER_INNER_MEAS
```

并优先克隆当前Build成功的 `EV1_LV_Meas` 同一测量family/settings，而不是重新猜SPS库。

物理Patch必须按 conserving `PortConnectivity`/节点集合做，不按普通Simulink line。

### E. phaseCorr / voltageRatio直接复用 —— **保留**

在三相基本平衡情况下，三相瞬时向量归一化点积可以直接反映相角相关性；同一基准下三相向量模长比可作为幅值比。

第一轮：

```text
phase gate = ON
cos threshold ≈ cos(10°)
vRatio = 0.95~1.05
```

可以作为**初始可调试验参数**，不是通用标准定值。

如果门不通过：

> 保留证据，先看真实inner/bus两侧为什么不匹配；不能为了让脚本继续跑就直接关门或无限放宽。

### F. state4 PostOK + state5独立Zero-Stable dwell —— **保留**

state4的0.2s只证明严重合闸暂态已经被压回，不是长期稳定证明。

state5再增加：

```text
CFG_ESS2_RESTORE_ZERO_STABLE_DWELL_S
初值 2.0 s
```

合理。

可以复用 `z(2)`：
- state2 = Ready counter
- state5 = ZeroStable counter

不需要扩状态向量。

### G. state9按breaker是否仍闭合决定hold —— **保留**

原则必须冻结：

```text
breaker OPEN
→ 可进入open-standby hold

breaker CLOSED
→ 不允许重新屏蔽真实电流反馈
```

因此：

```text
abortOpen=1：
breaker=0, hold=1, alpha=0

abortOpen=0：
breaker=1, hold=0, alpha=0
```

合理。

### H. G27继续复用、禁止G31 —— **保留**

仍维持5个OpWrite：

```text
G26~G30
```

ESS2继续G27。

增加：
- IrefUsed_d/q
- ImeasUsed_d/q
- MatchActive
- PostOK

并把49~51升级为真实breaker-inner Vabc，是合理的。

G27 56→62后继续使用：

```text
Function 62x1
→ Demux62
→ 62 scalars
→ Mux62
→ OpWrite
```

严格复用 Final Build Closure R2 成功范式。

---

# 4. V0.9中我建议修改的一项：Power Loop binary enable

V0.9提出：

```text
RestoreAlpha > 0
→ PowerLoopEnable=1
→ P/Q PI立即看到完整P/Q误差

Current Adapter仍：
IrefUsed = alpha * FinalIref
```

其目标是避免“double alpha”。

这个方向在形式上更接近单一ramp，但存在一个控制意义风险：

> **Power PI会在下游实际执行能力仍被alpha强烈限制时看到完整功率误差。**

当前 Power PI：

```text
Kp = 0.06
Ki = 2
```

其本地 anti-windup 只知道 Power PI **自身** 的 ±1.25/±1 输出限幅，不知道下游 Current Adapter 还在用 `alpha` 缩小实际电流执行。

因此在state6早期：

```text
P/Q PI：
“我看到完整大误差，应该快速积分”

Current Adapter：
“我只允许alpha比例的FinalIref真正进入Current PI”
```

这形成典型的“上层控制器不知道下游执行器仍被限幅”的状态不一致风险。

一个简单的抽象一阶对象 sanity calculation（不是本项目物理仿真）就会显示：
- binary外环 + downstream alpha 时，PI很容易先顶到自身限幅；
- alpha继续增加后，已经积累的PI状态可能造成明显超调；
- 现有PI自身anti-windup不能直接感知这个downstream alpha。

所以我**不建议在本轮正式Patch中直接采用 V0.9 的 binary PowerLoopEnable**。

---

# 5. 对Power Recovery更稳妥的V1.0建议

## 本轮先保留现有“双alpha”结构，并把它从“偶然重复”改成“明确的保守恢复律”

也就是：

```text
Power Loop：
(Pref-Pmeas) * alpha
(Qmeas-Qref) * alpha
→ 原Power PI

GFL Support：
形成 FinalIref

Current Adapter：
IrefUsed = alpha * FinalIref
```

这样做的优点：

1. state1~5 alpha=0：
   - Power PI误差输入=0；
   - Power PI状态不会提前追未来Pcmd；
   - Current Adapter执行电流参考=0。

2. state6 alpha 0→1：
   - Power PI逐步获得误差控制权；
   - 总FinalIref也逐步获得执行权；
   - 不需要新增Power PI tracking / external reset / downstream anti-windup。

3. state7 alpha=1：
   - 原Power Loop和Current Adapter全部回到正常完整控制。

缺点也要明确：

> 实际功率/电流恢复不会严格等于一个数学意义的2s线性ramp；早期响应可能近似比alpha更慢。

但本轮目标是：

> **安全、连续、可验证地恢复ESS2完整控制权。**

不是证明 `P(t)` 必须严格线性。

因此正式Runner应验收：

```text
alpha单调0→1
Raw/Final Iref有界
IrefUsed连续
Power PI不长期饱和
Current PI持续正常
P/Q平滑进入目标
state7后能够收敛
```

而不是要求：

```text
P/Ptarget = alpha
```

如果后续数据证明双alpha导致恢复过慢，再单独优化恢复律；不要在当前已经明确的zero-current接入缺陷修复中同时引入一个新的Power PI/downstream-actuator状态不一致。

**这会使本轮Patch更小、更符合“只改有证据的东西”。**

---

# 6. 因此我建议的V1.0正式改模范围

## 修改

1. 新增 `AA15_ESS2_BREAKER_INNER_MEAS`，使用当前Build成功测量family；
2. Executor in4 改接真实breaker-inner Vabc；
3. Restore Config 29→31：
   - FNOM_HZ
   - ZERO_STABLE_DWELL_S
4. Executor：
   - READY使用fNom sanity gate；
   - phase/vRatio用真实inner/bus；
   - state3 COMMIT当拍recheck ready；
   - state4/5 hold=0；
   - state5 ZeroStable dwell；
   - state6保持现有alpha ramp；
   - state9按breaker物理状态决定hold；
5. **Power Loop结构不再按V0.9新增binary enable，保留当前alpha误差门控；**
6. Current Adapter helper源码保持不变；
7. 新增标准块诊断镜像；
8. G27 56→62；
9. G27 ch49~51改真实inner Vabc；
10. G27 normalizer 56→62，复用成熟builder。

## 不修改

- ESS1 GFM；
- F21/F24/F25；
- PV1/PV2/EV1/EV2；
- Stubline/SSN/ARTEMiS；
- transformer / L2 / C2参数；
- ESS2原 Current Regulator PI；
- Current Adapter helper；
- ESS2 PLL；
- GFL dq selector；
- Power PI Kp/Ki；
- 25维SM→SS2接口（除现有结构保持）；
- 45维return chain；
- BOARD15产品主线。

---

# 7. 模块选择最终规则

不是“Function少就是好”。

本项目后续固定采用：

```text
复杂数值/复杂已有算法
→ Function可以使用

有限状态顺序
→ 新设计优先Stateflow/supervisor
→ 但已有Build/Target验证Function不在故障修复轮迁移

普通比较/门控/选择/限幅/拼接
→ 标准Simulink块

SPS物理观测/开关/网络
→ SPS现有物理块

跨task向量边界
→ 经典Demux/Mux正规化
```

判断标准是：
- 语义清楚；
- 实时平台兼容；
- 可独立Verifier；
- 最小修改；
- 不把复杂Function拆成不可维护的线网；
- 也不把简单逻辑藏进Function。

---

# 8. 后续脚本经验已经冻结为强制前置步骤

后续任何脚本，在开始写之前先做：

```text
1. 判定脚本类型
2. 搜本轮9/13总复盘
3. 搜仓库同类成熟helper / 成功脚本
4. 确认没有现成答案后才新增helper
5. 冻结允许改动/禁止改动/成功条件
6. 才开始生成
```

优先模板：

### Formal Patch
1. `PATCH_K26_K50_ESS2_FINAL_BUILD_CLOSURE_R2`
2. `PATCH_K26_K50_ESS2_RETURN_PATH_FIX_R2`

Physical Restore R3只作为主体结构来源，不机械复制其返回链和G27边界错误。

### Verifier
- Return Path Fix R2 verifier
- Final Build Closure R2 verifier

### OpWrite
- 仓库成熟 `localFindAllOpWrites`
- R6 `findAllOpWritesProven`

### Runner
- `RUN_K26_K50_LOCAL_S14_ESS2_PHYSICAL_RESTORE_E2E_R4.py`

### DirectMAT
- `ANALYZE_K26_K50_LOCAL_S14_ESS2_RESTORE_E2E_R4.m`

---

# 9. Formal Patch必须采用的事务流程

```text
pure helper selftest
↓
current semantic preflight
↓
SPS physical topology preflight
↓
Executor candidate source QA / harness
↓
G27 62 production-equivalent normalizer harness
↓
byte-identical scratch
↓
scratch apply
↓
postassert
↓
save exactly once
↓
close/reload
↓
persistence postassert
↓
formal whole-file backup
↓
formal re-preflight
↓
formal apply
↓
formal postassert
↓
save exactly once
↓
close/reload
↓
independent Verifier
↓
RT-LAB Rebuild
```

永久规则同时执行：

- raw SLX SHA只记录，不作语义硬门；
- SPS物理连线只按conserving PortConnectivity；
- From必须追Goto和最终selector/source；
- Subsystem模板先`deleteContents`；
- Nx1 Function输出跨task/OpWrite前做Demux/Mux正规化；
- 一个pattern错误出现，全文件扫描同类；
- Patch和Verifier分离；
- Verifier失败不重跑已成功Patch；
- Build后Target参数重新discover并read/write/readback/restore；
- Runner使用Target clock；
- 普通物理异常不自动Reset；
- MAT后处理失败不自动重跑物理试验；
- Missing/UNKNOWN绝不补0。

---

# 10. 下一步

**可以进入正式改模阶段。**

但不是原样把 V0.9 生成Patch，而是先把上述 Power Recovery 修订写入 **V1.0冻结合同**，然后一次性交付：

1. Formal Patch；
2. Independent Verifier；
3. 修改说明；
4. Build后Target Probe；
5. E2E Python Runner；
6. DirectMAT Analyzer更新；
7. G27 62通道 schema；
8. 用户执行顺序。

本轮目标仍然只有一个：

> **一次设计、一次结构改模、一次Build，把ESS2从“断开待并”完整推进到“零功率稳定接入→平滑功率恢复→正常恢复运行”，并用真实内部控制量直接证明每一阶段发生了什么。**

在ESS2 primitive通过前，不推进PV/EV，也不把本轮新RestoreHold缺陷倒推成历史完整孤岛的旧根因。
