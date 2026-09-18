# ESS2后续正式恢复路线：Q外环、Support取舍、无扰接管、协调权限与ESS1余量监督

> 日期：2026-09-17  
> 工程：`yanshou_V7 / K26_K50_CLEAN_P1`  
> 当前事实基线：A0 / P0 / C1 / Ki=0小功率 / Ki=0.5小功率已完成；P有功外环当前候选 `Kp=0.06, Ki=0.5`。  
> 目的：冻结“Q外环 → Support决策 → 局部清理 → 正式本地恢复 → S14接管 → Primary/Secondary → 正常权限扩大 → 多资源恢复”的工程路线。

---

# 0. 结论先行

1. 当前四路 Support（附加孤岛支撑）不是“黑启动必须模块”。它们属于 GFL（Grid-Following，跟网型）在孤岛中的附加阻尼/电压无功支撑功能，而不是 ESS1 GFM 建网、ESS2 同期、真实断路器合闸、真实电流闭环和基础 P/Q 闭环这些恢复原语。
2. 也不能只根据 `P=-0.005 pu` 一个稳态点就宣布 Support 永远不需要。是否保留，应该看最终所需工作域：P/Q、本地恢复、handover（控制权交接）、Primary（一次协调）、Secondary（二次恢复）、适度扰动、更大功率和更多 GFL。
3. 下一轮只做 Q 外环恢复。保持 P `.06/.5`、`P=-0.005 pu`、Qref=0、Support OFF、handover/Primary/Secondary OFF，只把 Q Loop 从 OFF 改成 ON。
4. Q 通过后做“部分清理”，不是全清理。A0/P0/C1 专用诊断控制可以删；Support Gate、P在线Kp/Ki、G27/G29/G30记录暂时保留。
5. 对本项目更推荐：S14 只负责把 ESS2 恢复到一个安全资格点，然后尽早交给正常 Coordinator（正常孤岛协调器）；后续正常功率范围由 Coordinator 在能力约束下逐步扩大。不要把 S14 扩展成第二套完整 EMS/AGC。
6. ESS1 动态构网余量监督现在不用加。它在 handover、Primary/Secondary 小权限验收阶段不是硬前置条件；但在扩大 ESS2 正常协调权限或恢复 PV/EV 下一台资源之前必须存在。


# 1. Support到底是不是“孤岛必须、黑启动不必须”

更准确的表述是：

- 黑启动/逐设备恢复必须的是功能：ESS1 构网、ESS2 弱网兼容、真实同步、真实合闸、真实电流闭环、基础 P/Q 控制和保护/执行余量。
- 当前 BASETEST 隔离的 `DampD / DampQ / SlowQ / LFQ` 是附加孤岛支撑请求，不是黑启动顺序的标准必需模块。
- “孤岛运行一定必须有这四路 Support”也不成立。若基础弱网结构在目标工作域已经稳定，它们就是增强功能，而不是必需控制。
- 若以后更大功率、更多 GFL 或特定扰动出现某类不稳定，而某组 Support 经过严格 A/B 后稳定改善，那么它才应被定义为正式弱网稳定控制的一部分。

因此最终判断标准不是名字，而是：

> **没有它，系统在要求的工作域内是否仍然满足稳定、V/f质量、P/Q跟踪和执行余量。**


# 2. 什么情况下可以正式判定某个 Support 不需要

至少应覆盖：

1. P-only 本地小功率；
2. P+Q 本地小功率；
3. Restore-state6 → Restore-state7 正式本地恢复资格；
4. S14-50 handover；
5. S14-60 Primary @ small authority；
6. S14-70 Secondary @ small authority；
7. 一个小且可重复的外部功率扰动。

如果 Support OFF 时仍满足：

- 无持续振荡增长；
- V/f质量满足项目要求；
- CurrentLimit不持续参与；
- ModHeadroom（调制度余量）健康；
- P/Q跟踪正常；
- ESS1不过度接近执行边界；

那么没有必要为了“形式完整”把四路 Support 全部恢复。


# 3. Support现在怎么处理

## 3.1 下一轮先不恢复

Q试验仍保持：

`Support actual = 0`

## 3.2 Q通过后先做 Support Audit（支撑审计）

直接看稳定数据中的后台请求：

- `Unselected_DampD`
- `Unselected_DampQ`
- `Unselected_SlowQ`
- `Unselected_LFQ`

先回答：

- 哪一路长期接近0；
- 哪一路在稳态持续有明显请求；
- 哪一路主要只在扰动出现；
- 哪一路与特定低频/中频动态相关。

如果某一路 `raw request≈0`，当前工况没有必要为了它单独跑一轮。

## 3.3 真要A/B时按功能族，而不是组合穷举

建议分组：

- S1：DampD + DampQ（阻尼类）
- S2：SlowQ（慢电压/无功类）
- S3：LFQ（低频无功类）

只对“有真实活动且物理目的明确”的组做最少量A/B。


# 4. Q外环下一步

唯一变化：

`Q Loop OFF → ON`

保持：

- `P target=-0.005 pu`
- P Loop ON
- P Kp/Ki = 0.06/0.5
- Qref = 0
- Q Kp/Ki = 0.06/2
- Support OFF
- handover=0
- Primary=0
- Secondary=0
- Direct diagnostic branch=OFF

重点记录：

- Qmeas
- QrefEff
- Qerror
- RawPowerCurrent_Q
- QIntegral
- FinalIref_q
- ImeasUsed_q
- Vpu
- Pmeas
- PLL
- CurrentLimit
- ModHeadroom

Qref=0 时不要用相对百分比作为主判据。应和已经通过的 P-only 基线做对照，关注均值、标准差、峰峰值、增长/衰减趋势和新主导频率。

如果 Q 一打开出现问题：

> **先建立 `Qerror → QIntegral / RawQ → Iq执行 → V/P/PLL变化` 的因果链，不直接调 Q Kp/Ki。**


# 5. Q通过后：建议部分清理

## 5.1 清理

A0/P0/C1 专用诊断控制：

- P/Q诊断开关
- Direct Iref诊断支路
- BT35 / BT40 / BT45 专用诊断状态
- 只为正交试验存在的 direct-rate / mux / select

## 5.2 暂时保留

- Support Enable / selector
- P在线Kp/Ki接口
- G27/G29/G30扩展记录

Support selector 仍是很有价值的 commissioning interface（调试验收接口），不应在 Support 最终角色确定前删除。

P在线Kp/Ki功能应保留。P+Q通过后，正式默认参数应收口为：

`Kp_P=0.06, Ki_P=0.5`

不要让正式运行永远依赖 Python 在 t=0 把 Ki 从2写成0.5。

Recorder 至少等 handover、Primary、Secondary 都验完以后再决定精简。


# 6. Cleanup以后第一步不是立刻handover

BASETEST为了看完整波形，绕开了部分 Restore-state6 → Restore-state7 的正式资格语义。

Cleanup 后先重新验证：

- P/Q tracking
- V/f
- Iref/Imeas
- CurrentLimit
- ModHeadroom
- dwell
- rollback

并重新形成：

`Restore-state7 = ESS2_LOCAL_RESTORED（ESS2本地恢复完成）`

建议把“本地恢复完成”和“允许接管”拆开：

`DeviceRestoredACK → HANDOVER_ENABLE → S14-50`

这样调试时可以先验证正式本地恢复而不让 handover 同拍发生。


# 7. DeviceRestoredACK建议含义

概念上：

`DeviceRestoredACK = BreakerClosed && PLLHealthy && PTrackingOK && QTrackingOK && IslandVoltageOK && IslandFrequencyOK && !CurrentLimit && ModHeadroomOK && NoAlarm && StableDwellDone`

具体阈值不在当前凭空指定，应使用 Ki=.5 和 P+Q 的真实数据校准。

其中：

- `DeviceRestoredACK` 表示设备有资格被正常协调层接管；
- 不代表设备已经恢复完整正常功率范围。


# 8. S14-50 handover到底怎么做

handover（控制权交接）只解决：

> **最终有功命令的所有者从 S14 换成正常 Coordinator。**

不同时做：

- 功率扩大；
- Primary；
- Secondary；
- 下一资源恢复。

现有：

`Pfinal = (1-beta)*P_S14 + beta*P_Coord`

结构合理，应保留。

建议 S14-50 内部分四步：

### H50-A Coordinator Pre-arm（协调器预接管准备）
- beta=0
- CorrectionEnable=0
- SecondaryEnable=0
- authority=0或极小
- Coordinator内部 `Pbase_ESS2` 跟踪/捕获当前 Pmeas/Pfinal

### H50-B Match Check（目标匹配检查）
在beta变化前确认：
- `P_Coord_pre ≈ P_S14`
- V/f健康
- CurrentLimit=0
- ModHeadroom健康
- P/Q没有异常

不匹配则beta保持0。

### H50-C beta平滑交接
`beta: 0 → 1`

此时仍：
- CorrectionEnable=0
- SecondaryEnable=0

只换所有权，不应显著改变功率工作点。

### H50-D Post-handover Hold（接管后保持）
beta=1后保持观察，确认：
- Pfinal连续
- Pmeas不出现新增长
- V/f不恶化
- CurrentLimit=0
- ModHeadroom健康

然后才进入S14-60。


# 9. handover失败怎么退

breaker已经闭合后，不能通过“把Imeas变0”来退出。

软异常：
- 冻结beta；
- 或让beta平滑回0；
- 恢复 `S14 owns P`；
- 保持真实Current loop继续工作。

硬故障：
- 严重欠压；
- 严重过流；
- 数据无效；
- 明显失控；

才进入正式失败/必要breaker OPEN路径。


# 10. S14-60 Primary怎么验

handover通过后：

- beta=1
- Coordinator owns ESS2
- CorrectionEnable从0打开
- CorrectionGain 0→1
- Secondary仍OFF
- authority保持当前小范围（约0.01 pu，hard cap约0.02 pu）

建议两轮：

### Primary-P0
只打开Primary，不额外加扰动。先证明一次协调本身投入不会激发新振荡。

### Primary-P1
Primary稳定后，再加一个小且可重复的负荷/功率扰动。

观察：
- ESS1 P
- ESS2 P
- master frequency
- dp_primary
- authority
- V/f
- CurrentLimit
- ModHeadroom

回答 ESS2 是否按正确方向帮助 ESS1 承担功率失配。


# 11. S14-70 Secondary怎么实现

当前正式模型没有S14-70。

Primary稳定后再新增：

`S14-70 ESS2_COORD_SECONDARY`

但必须先审计：

> 当前 `SecondaryEnable` 是否同时打开“二次频率恢复”和“慢电压恢复”。

若一个开关同时打开两个慢控制族，不符合当前单变量因果纪律。

更干净的 commissioning（验收）方式：

- 70A：secondary frequency restoration ON，slow voltage restoration OFF
- 70B：secondary frequency restoration ON，slow voltage restoration ON

或者提供：
- `SecondaryFreqEnable`
- `SecondaryVoltageEnable`

最终正常模式可同时使能，但第一次验收不要两个慢环一起开。


# 12. 完全正常恢复：推荐哪种架构

有两个方案。

## 方案A：S14先把ESS2拉到较大恢复功率，再handover
缺点是S14会越来越像第二套EMS/AGC，与正常Coordinator职责重复。

## 方案B：S14只负责恢复到安全资格点，然后handover，后续正常功率由Coordinator逐步扩大

推荐方案B：

`0-power connect → P/Q qualification → P_qualification≈-0.005 → DeviceRestoredACK → S14-50 handover → Primary small authority → Secondary small authority → ESS1 reserve supervision → authority expansion → normal schedule`

理由：
1. S14职责保持单一；
2. 正常功率调度只有一个Coordinator；
3. 避免两套长期功率管理；
4. 现有ownership blend结构正好适配；
5. 当前0.01/0.02小authority提供安全过渡层。

因此 `-0.005 pu` 应定义为 `P_qualification（首个功能资格工作点）`，不是“完整正常功率”。


# 13. 建议增加三个资格层

### LocalRestored
真实并回 + P/Q资格通过。

### CoordinationReady
handover完成 + Primary/Secondary小权限通过。

### NormalAuthorityReady
ESS1 reserve监督有效 + ESS2自身能力有效 + 系统稳定边界允许。

只有第三层以后，才逐渐扩大到正常schedule（正常调度目标）。


# 14. ESS1余量监督什么时候加

现在不用加。

当前还在：
- P+Q
- Support决策
- formal local restored
- handover
- Primary/Secondary small authority

这些阶段只有很小权限，若现在加入复杂动态reserve会多一个未经验证的新机制。

必须加的时间点：

> **authority准备从当前±0.01/0.02 pu继续扩大之前，并且一定在恢复PV1/PV2/EV1/EV2之前。**


# 15. ESS1余量监督最终不应只是一个对称标量

至少应区分：

- `ESS1_P_Up_Reserve`
- `ESS1_P_Down_Reserve`

当前约定下，ESS2更负表示吸收更多功率，因此ESS1必须增加供电，所以：

- ESS2向负方向的允许变化受ESS1向上有功余量限制；
- ESS2向正方向/少充电/多发电时，主要受ESS1向下调节余量限制。

因此最终不应只有一个完全对称的 `authority=±X`。


# 16. ESS1余量监督最小版看什么

第一版至少看：

- ESS1当前P
- ESS1当前Q
- ESS1电流幅值
- CurrentLimit
- ModHeadroom
- V/f健康

得到：

- P_up_margin
- P_down_margin

更完整版本以后再考虑：
- Vdc
- SOC/能量
- 温度/持续时间
- 当前GFL总量
- 稳定边界经验系数

不要第一版全部加入。

概念结构：

`ESS1 electrical margin → P_up/down reserve → 安全系数 → 与ESS2自身up/down capability取min → AuthorityUp / AuthorityDown → Coordinator`

它是 supervisory capability calculation（监督层能力计算），不是新的快速控制环，不直接生成PWM、电流或电压。


# 17. Support与ESS1 reserve是两件不同的事

- Support：改变GFL本地动态特性、阻尼、电压无功响应。
- ESS1 reserve supervision：决定系统现在允许恢复/调节多少功率。

所以：
- Support不能替代GFM余量管理；
- GFM余量管理也不能替代Support；
- 如果最终Support没有证据证明必要，可以不启用；
- 但正常功率扩大仍必须受ESS1能力约束。


# 18. 推荐完整执行顺序

1. **P+Q small-power**
   - P=-0.005
   - Qref=0
   - P=.06/.5
   - Q原参数
   - Support OFF

2. **Support Audit**
   - 先看后台raw request

3. **只对有活动、有物理目的的Support做最少量A/B**
   - 若无必要，可继续OFF

4. **Partial Control Cleanup**
   - 删除A0/P0/C1 direct诊断控制
   - 保留Support Gate
   - 保留P Kp/Ki online
   - 保留Recorder
   - P Ki默认改为0.5

5. **Audit + Verifier + Rebuild**

6. **formal local restored**
   - P+Q正式路径
   - Support最终默认集合
   - Restore-state6→7
   - DeviceRestoredACK
   - HANDOVER_ENABLE先保持0

7. **S14-50 handover**
   - Pre-arm
   - Match
   - beta 0→1
   - Post-hold

8. **S14-60 Primary**
   - small authority
   - 先无扰投入
   - 再小扰动验证

9. **S14-70 Secondary**
   - small authority
   - 尽量分开频率二次与慢电压恢复

10. **ESS1 dynamic reserve supervision**
    - AuthorityUp / AuthorityDown

11. **扩大ESS2 normal authority**
    - 逐级向正常schedule开放

12. **PV1 / PV2 / EV1 / EV2逐台恢复**
    - reconnect → qualification → handover → coordination


# 19. 当前冻结结论

- Support不是因为“孤岛”三个字就必须全部打开。
- 如果没有证据证明某组Support对最终工作域有必要，就不应把它重新引入控制链。
- Q通过后可以清理，但只清理已经完成使命的A/B诊断控制；Support Gate、P在线Kp/Ki和Recorder暂时保留。
- handover只换命令所有权，不扩大功率。
- Primary、Secondary与authority expansion必须分开验证。
- 本项目更适合让S14在小资格点完成恢复并尽快交给正常Coordinator，而不是把S14扩展成第二套完整EMS。
- 动态ESS1余量监督在small-authority Primary/Secondary前不是硬前置条件，但在扩大ESS2权限或恢复下一台GFL前必须存在。

当前下一轮实际只做：

> **在已验证的P `.06/.5` 小功率基础上，只打开Q外环，验证P+Q本地基础闭环。**
