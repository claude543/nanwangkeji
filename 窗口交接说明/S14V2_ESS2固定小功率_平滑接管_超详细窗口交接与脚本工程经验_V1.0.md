---
title: 2026-09-15｜K26_K50 S14 V2 + ESS2固定小功率承担 + 平滑接管｜超详细窗口交接与脚本工程经验
date: 2026-09-15
version: V1.0
project: 暑期南网科技项目 / yanshou_V7 / K26_K50_CLEAN_P1
status: 正式Patch已生成并完成容器侧静态审查；尚未在MATLAB/RT-LAB执行
tags:
  - OPAL-RT
  - RT-LAB
  - Simulink
  - MATLAB
  - S14黑启动
  - ESS2并回
  - GFM构网
  - GFL跟网
  - 防返工
  - 窗口交接
---

# K26_K50｜S14 V2 + ESS2固定小功率承担 + 平滑接管
# 超详细窗口交接、数据结论、正式改模设计与脚本工程经验 V1.0

> **正式工作模型：** `K26_K50_CLEAN_P1`  
> **当前用户上传模型 SHA256（文件内容校验值）：** `9c6f881c68411d023732a30b70554d118fa557b197f9b419f686214b1d5edea3`  
> **平台：** OPAL-RT OP5700（实时数字仿真器）  
> **RT-LAB（实时仿真软件）：** v2024.1.1.38  
> **MATLAB/Simulink（数学计算与模型仿真软件）：** R2023b  
> **ARTEMiS（实时电力系统求解器）：** 7.8.0.17  
> **固定步长：** `Ts = 100 μs`  
> **系统：** 2PV（两台光伏）+ 2ESS（两台储能）+ 2EV（两台电动汽车）六逆变器微电网  
> **当前角色：** ESS1（储能1）= 唯一 GFM（Grid-Forming，构网型）；PV1/PV2/ESS2/EV1/EV2 = GFL（Grid-Following，跟网型）  
> **PCC（Point of Common Coupling，公共连接点）有功方向：** 正值 = 微电网向上级电网送电  
> **本文目的：** 新窗口接手以后不重新猜、不重新做已完成实验、不重新踩脚本坑，直接从当前断点继续。

---

# 0. 新窗口只看这一节，也必须知道的结论

当前已经不是“ESS2（储能2）能不能接进ESS1（储能1）构成的孤岛”的问题。

真实试验已经证明下面这条链能够走通：

```text
ESS1（储能1）从死母线自主建压
→ ESS2（储能2）退出强网GFL（跟网型）Stage0（阶段0）
→ GFL Stage1（孤岛准备阶段）
→ GFL Stage2（孤岛稳定阶段）
→ 断路器两侧同期资格满足
→ ESS2 READY（并入前就绪）
→ ESS2真实交流断路器闭合
→ Restore state4（恢复状态4：闭合后零电流主动调节）
→ Restore state5（恢复状态5：零功率稳定接入）
→ ESS2真实挂网、P≈0、Q≈0
→ 可以长期保持稳定
```

所以当前真正的问题已经推进到下一层：

> **ESS2已经能够“安全接回来”，但旧设计在“开始承担非零功率”时把系统推向持续低压。**

R7（第7轮正式完整并回试验）已经把失败分界压到：

```text
24.5 s以前：
ESS2已经真实接入
RestoreAlpha（恢复系数）= 0
P≈0、Q≈0
系统稳定

24.5 s：
旧MANUAL_RELEASE（人工功率释放）
→ RestoreAlpha开始0→1
→ 正常孤岛Coordinator（协调器）目标仍在移动
→ Power PI（功率比例积分调节器）同时积分
→ 母线电压持续下降
→ 之后才出现CurrentLimit（电流限幅）
```

因此当前工作重心已经冻结为：

> **直接改造S14（策略14黑启动）本体，把“ESS1建网 → ESS2本地正确阶段 → 零功率真实接入 → 固定小功率验证 → 平滑交给正常孤岛Coordinator（协调器） → Primary-only（仅一次协调）观察”做成一个有明确物理确认、有明确控制权、没有目标漂移的闭环。**

本轮不再回头重做：

- ESS1（储能1）死母线建网；
- ESS2（储能2）真实同步；
- ESS2真实交流断路器；
- state0~5（状态0~5）已验证物理算法；
- Current Adapter（电流执行适配器）；
- 已经消掉的约26 Hz（赫兹）快速模态；
- breaker-inner（断路器内侧）真实Vabc（三相电压）测量。

---

# 1. 当前正式交付物与状态

## 1.1 Patch（改模脚本）

文件：

```text
PATCH_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m
```

SHA256（文件内容校验值）：

```text
bfb0ee63df58c709e371ae1028c3e8300d4a46874717f9d8146d45de645b318c
```

行数：

```text
2678
```

职责：

- 修改 `K26_K50_CLEAN_P1.slx`；
- 自带当前语义预检查；
- 自带5组 production-equivalent Harness（生产等价隔离测试）；
- 先在 byte-identical scratch（字节一致临时副本）演练；
- scratch（临时副本）通过以后才碰正式模型；
- 正式模型保存一次；
- 保存后失败则 whole-file backup（整文件备份）字节级回滚。

**截至本交接文件生成时：**

> 该Patch（改模脚本）已经生成并完成本环境静态检查，**尚未由用户在MATLAB R2023b中运行**。

---

## 1.2 Verifier（独立验证脚本）

文件：

```text
VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m
```

SHA256：

```text
9ed90cfdbc6bd6395f11a000589338826d7785ee4cb5a9a5a8a96b79cc01b266
```

行数：

```text
482
```

职责：

- 完全只读；
- 不调用Patch内部helper（辅助函数）；
- 不 `set_param`（写参数）；
- 不 `add_block`（新增模块）；
- 不 `delete_block`（删除模块）；
- 不 `add_line`（新增连线）；
- 不 `delete_line`（删除连线）；
- 不 `save_system`（保存模型）；
- 不 `update/compile`（更新/编译模型）；
- 独立重新打开已保存模型，验证源码、接口、连线、G29（第29记录组）、OpWrite（目标端文件记录模块）与跨任务维度。

PASS（通过）状态设计为：

```text
PASS_READY_FOR_RTLAB_REBUILD
```

含义严格是：

> **模型保存结构符合R1设计，可以进入RT-LAB Rebuild All（全部重新构建）。**

不等于：

- RT-LAB（实时仿真软件）已经构建通过；
- 目标机已经运行通过；
- 电气性能已经通过。

---

## 1.3 Static Review（静态审查报告）

文件：

```text
PATCH_VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1_STATIC_REVIEW.txt
```

SHA256：

```text
2759a69eaeb5b9fe75422a3ba5c7828e3958c5e347ebd2663c5c95c924f12523
```

当前静态结论：

```text
PASS
```

但必须看清边界：

> 当前容器没有MATLAB R2023b/Simulink（模型仿真软件）运行时，因此“PASS”指容器侧静态规则检查通过，不冒充MATLAB解析、Simulink更新或RT-LAB构建通过。

Patch本身已经把第一道MATLAB侧门设计成：

```text
candidate source QA（候选源码质量检查）
→ 5个production-equivalent Harness（生产等价隔离测试）
→ scratch（临时副本）
→ formal（正式模型）
```

所以如果候选MATLAB Function（MATLAB函数模块）源码、Rate Limiter（斜率限制模块）参数名或端口接口不被R2023b接受，会在**正式模型保存之前**停止。

---

## 1.4 关于用户上传的“中断思考过程”文件

用户本次上传了窗口突然停止时保存的分析过程。

该文件中已经形成了：

- S14 V2（策略14黑启动第二版）的详细状态设计；
- state25（状态25：Stage2预合闸稳定）的关键补充；
- 三类Stage（阶段）拆分；
- Qref/q-bias（无功参考/无功偏置）语义对齐；
- G29（第29记录组）46→68的通道设计；
- Patch（改模脚本）与Verifier（独立验证脚本）的目标名称。

本次续接时，先用这个文件恢复断点，再重新对照：

- 当前正式SLX（Simulink模型）；
- 一次通过的架构审计ZIP；
- V8成功Patch；
- planned-island V3.4（计划孤岛第3.4版）成功Patch；
- Physical Restore R3（物理恢复第3版）Verifier；
- 工程脚本编写总复盘。

**注意：**

中断文件里曾出现过一组尚未落盘的旧脚本SHA/行数。新窗口不要把那组数字当正式交付物。本文第1节列出的SHA和行数来自当前实际生成文件，是唯一有效版本。

---

# 2. 当前正确执行顺序：禁止越级

下一步只按：

```text
1. 用户运行正式Patch（改模脚本）
↓
2. Patch自身：
   preflight（预检查）
   → Harness（隔离测试）
   → scratch（临时副本）
   → formal（正式模型）
   全部PASS
↓
3. 用户运行独立Verifier（独立验证脚本）
↓
4. Verifier = PASS_READY_FOR_RTLAB_REBUILD
↓
5. RT-LAB Rebuild All（全部重新构建）
↓
6. Rebuild真正成功
↓
7. 才编写下一轮Python Runner（Python动态试验脚本）
↓
8. 单轮完整试验：
   ESS1建网
   → ESS2零功率并回
   → 固定小功率
   → 固定小功率达到规定稳定时间
   → 同一轮自动平滑接管
   → Primary-only（仅一次协调）
   → 停止并保存MAT
↓
9. DirectMAT（原始MAT直接分析）
↓
10. 决定下一步
```

禁止：

```text
Patch还没跑
→ 先写正式Runner
```

原因：

RT-LAB Rebuild（重新构建）以后：

- 参数暴露可能变化；
- Signal ID（信号编号）会变化；
- Parameter ID（参数编号）会变化；
- 新增信号是否真正可读，必须以当前Build（构建）为准。

先写Runner很容易再次出现：

> “模型按一套接口改，Python按另一套想象接口写，然后Build后重新返工。”

---

# 3. 本窗口承接的总体背景：A/B两个窗口分别做了什么

## 3.1 A窗口：非孤岛策略联调验收

A窗口负责：

- 除孤岛/黑启动/重同步以外的大部分策略；
- 板端通信接口；
- 策略执行链；
- 最终已经完成。

这条线不要在本窗口重复。

A窗口的价值：

> BOARD15（板端15策略）主线已经是未来产品主事实库之一。

---

## 3.2 B窗口：模型全面审计 + 孤岛/黑启动物理能力

B窗口负责：

- 全模型结构梳理；
- 物理/普通信号连线整理；
- ESS1（储能1）GFM（构网型）；
- J1（公共连接点断路器）真实开断；
- 孤岛持续稳定；
- 黑启动；
- ESS2（储能2）真实物理并回。

当前主窗口正式接替的就是B线。

---

# 4. 为什么从“完整六机孤岛”转向“黑启动逐台恢复”

此前完整六机孤岛存在：

```text
前期波动
→ 中间一段相对安静
→ 25~30 s附近又出现明显波动
```

继续在：

```text
1台GFM + 5台GFL
```

全部同时在线的状态里盲调，很难知道：

- ESS1（储能1）本体是不是问题；
- 某台GFL（跟网型）是不是问题；
- 多台GFL聚合才出问题；
- 功率慢恢复把工作点推坏；
- 切换状态记忆导致；
- EV（电动汽车）负荷动态导致；
- 二次控制导致。

所以转黑启动不是换题，而是因果分解：

```text
先证明ESS1自己能建网
↓
再加ESS2但零功率
↓
再让ESS2承担一点功率
↓
再恢复更多资源
```

第一处失败就是最有价值的因果边界。

---

# 5. 文献检索带来的真正结论

高质量文献没有证明：

```text
1台GFM最多只能带2台GFL
```

台数比不是稳定判据。

真正相关的是：

- GFM（构网型）容量；
- GFM当前P/Q（有功/无功）余量；
- 短时电流能力；
- 调制度余量；
- 网络阻抗；
- GFL功率工作点；
- PLL（锁相环）；
- 功率环；
- GFM输出阻抗；
- 多GFL聚合动态。

所以：

> **1 GFM + 5 GFL不是理论错误，但确实属于需要定量验证构网强度与运行点稳定边界的高难度架构。**

黑启动文献共同支持的恢复骨架：

```text
隔离
→ GFM建立V/f（电压/频率）
→ 待接设备同步
→ 低/零功率合闸
→ 稳定确认
→ 逐步增加功率
→ 下一资源
```

这正是我们目前已经走通的前半段。

---

# 6. ESS2为什么选作第一台恢复设备

ESS1和ESS2都位于：

```text
K26_K50_CLEAN_P1/SS_Slave2
```

优点：

- 同一实时任务；
- 本地breaker（断路器）；
- 本地控制；
- 本地高速诊断；
- 减少第一次恢复样机的跨任务复杂度。

ESS2跑通以后，再推广PV/EV。

本轮禁止：

> ESS2还没完成功率承担和平滑接管，就复制五套到PV/EV。

---

# 7. ESS2并回早期最大的设计缺陷：闭合以后还在“断开待并模式”

历史错误逻辑：

```text
breaker OPEN（断路器打开）
时：
iref_used = 0
imeas_used = 0
match = 1
```

这在断开待并时合理：

- 支路不可控；
- 不让Current PI（电流比例积分调节器）追一个物理上不能控制的外部量。

但旧状态4/5仍然：

```text
breaker已经CLOSED（闭合）
RestoreHold = 1
```

导致：

```text
真实电流已经流动
但Current PI仍看：
error = 0 - 0 = 0
```

而且持续 `match=1` 会让积分项抵消比例项，使PI总输出保持0。

所以状态4一直等待电流自己变健康，却没有让已有电流调节器真正纠偏。

这才是当时的直接控制缺陷。

---

# 8. 这个缺陷怎么被正确修掉

最终正确阶段：

| Restore状态（恢复状态） | 断路器 | RestoreHold（恢复保持） | RestoreAlpha（恢复系数） | 电流反馈 |
|---|---:|---:|---:|---|
| state1~3（断开待并/资格/READY） | 0 | 1 | 0 | 待并处理 |
| state4（闭合后零电流主动调节） | 1 | 0 | 0 | 真实Imeas（实测电流） |
| state5（零功率稳定接入） | 1 | 0 | 0 | 真实Imeas |
| state6（当前将改为固定小功率验证） | 1 | 0 | 1 | 真实Imeas |
| state7（当前将改为本机恢复完成） | 1 | 0 | 1 | 真实Imeas |

核心：

```text
hold = 0
alpha = 0
```

意味着：

```text
iref_used = 0
imeas_used = real imeas
```

所以已有Current PI自动形成：

```text
0 - actual current
```

的纠偏。

不用新造第二套Current PI。

---

# 9. 真实breaker-inner Vabc为什么必须补

ESS2历史物理顺序：

```text
ESS2_Converter（储能2变流器）
→ EV1_inv（历史误名，实际是ESS2变流器端测量）
→ L2（滤波电感）
→ C2所在节点
→ ESS2交流断路器
→ EV1_LV_Meas（历史误名，实际是ESS2母线侧测量）
→ 岛网
```

旧G27（第27记录组）：

```text
49~51 = EV1_inv
52~54 = EV1_LV_Meas
```

第一组在L2之前，不是breaker-inner真实节点。

后来用户手动加入：

```text
SS_Slave2/AA15_ESS2_BREAKER_INNER_MEAS
```

这个动作之所以改为手动，而不是继续让自动脚本修改SPS（专用电力系统）物理线，是因为此前Patch连续遇到：

- 三相Connection根线解析不唯一；
- 分支残余线无法可靠识别；
- conserving port（守恒端口）和普通Simulink signal（普通信号）语义完全不同。

最终规则：

> **SPS物理网络如果自动脚本不能百分百确定节点与分支，就不要强行自动改。用户手动完成，Patch只做只读拓扑核对。**

这是非常重要的防返工原则。

---

# 10. 之前几轮Patch为什么反复失败，分别教会了什么

## 10.1 V2：同名模型shadow（路径遮蔽）

错误：

```text
The file containing block diagram ... is shadowed by a file of the same name
```

本质：

- MATLAB path（路径）里有另一个同名SLX；
- `load_system`可能加载的不是用户当前工作文件。

正确经验：

```text
canonical path（规范绝对路径）
+
get_param(model,'FileName')
+
当前模型文件精确一致
```

不是只看模型名。

---

## 10.2 V3：把SPS三相分支按普通信号根线解析

错误：

```text
第1相L2/C2/breaker原节点没有解析到唯一Connection根线
```

本质：

- 物理节点可有多个守恒连接端；
- 没有普通信号唯一Src/Dst（源/目标）语义；
- “唯一根线”是假设错了。

经验：

> 普通信号用Src/Dst；SPS物理连接看LConn/RConn与节点成员集合。

---

## 10.3 V4：自动生成MATLAB源码出现非法`end`

错误：

```text
非法使用保留关键字 end
```

经验：

生成`.m`以后必须全文件扫描：

- 函数定义；
- `end`结构；
- `fprintf/error/sprintf`字符串；
- bare `&& / ||`；
- 括号；
- 函数名与文件名；
- 重复local function（局部函数）。

不能只等MATLAB报第一处以后再修。

---

## 10.4 V5：物理旧inner-node删除后仍有残余连接

本质：

脚本对复杂三相物理分支的重接不够可靠。

最终决策：

> 这一块交给用户手动修改，不再追求“所有事情必须自动化”。

用户明确允许：

> 自动不擅长就说，手动来连。

这是后续永久规则。

---

## 10.5 V6/V7：普通信号已有连接，但来源解析规则过于理想化

出现：

```text
目标端口已有信号线连接
```

以及：

```text
无法解析到唯一普通信号来源
```

经验：

- 不能因为目标已连就直接报错；
- 先判断是否已经是期望连接；
- Goto/From（标签发送/读取）不能只停在From；
- 分支/包装块必须追到真实最终源；
- helper（辅助函数）必须复用仓库成熟版本。

---

## 10.6 V8：真正稳定的改模模板

V8最终形成了现在继续复用的正式事务模板：

```text
pure helper selftest（纯辅助函数自测）
→ candidate source QA（候选源码质量检查）
→ production-equivalent Harness（生产等价隔离测试）
→ byte-identical scratch（字节一致临时副本）
→ scratch preflight（临时副本预检查）
→ scratch apply
→ scratch postassert
→ scratch save once
→ scratch reload
→ persistence postassert（持久化断言）
→ whole-file formal backup（正式整文件备份）
→ formal re-preflight
→ formal apply
→ formal postassert
→ formal save exactly once
→ formal close/reload
→ persistence postassert
```

如果正式保存前失败：

```text
磁盘正式模型没被Patch保存
→ 不需要rollback（回滚）
```

正式保存后失败：

```text
whole-file backup
→ 字节级覆盖回正式模型
→ SHA确认
```

---

# 11. Python Runner（Python动态试验脚本）踩过的关键坑

## 11.1 `(MODEL_PAUSED, SOFT_SIM_MODE)`不是“模型没暂停”

历史Runner错误把：

```text
(MODEL_PAUSED, SOFT_SIM_MODE)
```

当成：

```text
不是MODEL_PAUSED
```

导致用户Reset→Load以后仍被脚本拒绝。

经验：

> RT-LAB状态API返回的是状态组合/tuple（元组），不能拿整个对象与一个枚举直接等号比较。

---

## 11.2 `max(empty sequence)`不是物理问题，是Runner结构bug

某轮脚本：

```text
max(RELEASE_CANDIDATE_TIMES)
```

但候选数组为空。

这是Python脚本本身没有覆盖“本轮禁用release候选”的模式。

经验：

所有：

```text
max/min/first/last
```

之前必须明确：

```text
list非空
```

而不是假设每个工况一定有事件。

---

## 11.3 为什么最后决定做“一轮完整试验”

中间曾考虑：

```text
跑到某个状态
→ 停
→ 分析
```

用户指出：

> 如果最终还是要看完整并网过程，为什么不一次跑完整，再拿完整MAT分析？

这个纠正是对的。

以后在：

- 已知安全边界；
- 关键事件可以按状态门控；
- 中途不需要人工判定；

的情况下，Runner应尽量：

```text
单次Execute
→ 按Target clock（目标机时钟）推进
→ 各阶段自动动作
→ 最后Pause
→ 保存完整RAW/MAT
```

避免人为分成很多碎片，破坏状态连续性。

---

## 11.4 Evidence-first（证据优先）原则

普通：

- V低；
- f偏；
- 电流升；
- PostOK（接入后健康条件）失败；

不等于：

```text
立即Reset
```

正确：

```text
Pause
→ 保存RAW
→ 保存MAT
→ DirectMAT分析
```

只有：

- NaN/Inf（非数/无穷）；
- 数值灾难；
- 拓扑合同失效；
- breaker执行错误；
- 不可逆错误动作；

才硬停。

---

# 12. R6.1：GFL工程Stage正确桥接后，第一次零功率真正稳定

R6.1只改变一个核心变量：

```text
AA15_FINAL_SYSTEM_STAGE（最终系统阶段）
0 → 1 → 2
```

不释放功率。

成功时序：

```text
0~5.5 s
ESS1死母线建网

5.5 s
Stage0 → Stage1
= ISLAND_PREPARE（孤岛准备）

5.5~8.0 s
Stage1保持2.5 s

8.0 s
Stage1 → Stage2
= ISLAND_STABILIZE（孤岛稳定）

8.0~12.0 s
Stage2预合闸保持约4 s

12.0 s
READY + COMMIT

12.0002 s左右
breaker close（断路器闭合）

12.2 s左右
state5

后续：
P≈0
Q≈0
稳定
```

这组成功时序非常重要。

本轮新S14不能“看起来更智能”以后偷偷删掉：

```text
2.5 s Stage1准备
+
4.0 s Stage2预合闸稳定
```

所以最终专门新增：

```text
state25 = ESS2_STAGE2_STABILIZE
```

就是为了复用成功时间结构。

---

# 13. R6.1最重要的频域正证据：旧约26 Hz快速模态几乎被消掉

错误Stage0与正确Stage2对比，20~32 Hz频带关键量下降约：

- ESS2 Vpu：99.937%；
- ESS2 Id：99.768%；
- ESS2 Iq：99.940%；
- Raw Vd/Vq：99.97%以上；
- Final VFF d/q：99.999%左右；
- Current PI：99.8%以上；
- Vconv：99.99%左右。

因果闭环：

```text
错误GFL Stage0
→ 强网dynamic terminal-Vdq（动态端电压dq前馈）100%保留
→ 弱网中形成约26 Hz共享快速模态

正确Stage1/2
→ dynamic VFF（动态电压前馈）按弱网逻辑整形
→ 约26 Hz模态几乎消失
```

新窗口禁止：

> 一出现新的慢失稳，又重新说“可能还是旧26 Hz VFF问题”。

除非新数据反证。

---

# 14. R7证明了什么

## 14.1 零功率接入真的成功

关键时刻：

```text
12.0002 s：
state3 → state4
breaker 0→1
RestoreHold 1→0
MatchActive 1→0

12.2002 s：
state4 → state5

15.8335 s：
ReleaseAllowed 0→1
```

20~24 s：

```text
Vpu均值约1.020
范围约0.987~1.067
PLL约50.239 Hz
P≈0
Q≈0
CurrentLimit=0
```

所以：

> `ESS1 GFM + ESS2 GFL @ zero power` 已经真实稳定。

---

## 14.2 Stage3本身不是直接触发

R7：

```text
24.0 s：
GFL Stage2 → Stage3
但RestoreAlpha仍=0

24.0~24.5 s：
稳定
```

所以：

> 进入功率恢复控制结构本身不是第一触发。

真正分界：

```text
24.5 s MANUAL_RELEASE
```

---

## 14.3 功率释放后的电压下降先于限流

典型：

| 时刻 | RestoreAlpha（恢复系数） | Vpu（电压标幺） | PrefEff（有效有功参考） | Pmeas（实测有功） |
|---:|---:|---:|---:|---:|
|24.50|≈0|≈0.994|≈-0.068|≈0|
|25.00|0.25|≈0.993|≈-0.097|≈+0.001|
|25.18|0.338|≈0.95|≈-0.104|≈-0.001|
|25.40|0.451|≈0.90|≈-0.109|≈-0.005|
|25.65|0.577|≈0.80|≈-0.109|≈-0.012|
|26.00|0.750|≈0.54|≈-0.123|≈-0.016|
|26.21|0.855|≈0.20|≈-0.130|≈-0.003|

CurrentLimit（电流限幅）大约到26.36 s才明显动作。

因此：

```text
功率承担开始
→ 电压先持续恶化
→ 后面才进入限流
```

CurrentLimit不是第一触发。

---

## 14.4 ESS1自己的Fref/Vref不是先发疯

G30（第30记录组）表明：

```text
ESS1 Fout ≈ 50.241 Hz
std ≈ 0.006 Hz

Vq_ref ≈ 1.004 pu
```

目标很平静。

但实际电压已经明显失真/下跌。

所以：

> 不是ESS1先把参考命令发坏，而是物理闭环已经无法维持目标。

---

# 15. R7暴露的最核心上层缺陷：目标在后台提前积累

在RestoreAlpha仍为0、ESS2实际P≈0时：

```text
23.9 s  ESS2 PrefCmd ≈ -0.043 pu
24.2 s             ≈ -0.055 pu
24.4 s             ≈ -0.068 pu
24.5 s             ≈ -0.0745 pu
```

所以24.5 s不是：

```text
从0开始承担一个小功率
```

而是：

```text
打开一个已经积累到约-0.0745 pu
而且还在继续移动的正常孤岛目标
```

同时：

```text
Coordinator目标在动
+
RestoreAlpha在动
+
Power PI在积
```

三个慢变量一起动。

因此R7不能回答：

```text
ESS2固定-0.005 pu到底稳不稳定？
```

因为它从未做过固定非零平台。

---

# 16. 为什么第一轮固定功率选择 -0.005 pu

正式默认：

```text
AA15_S14V2_CFG_PICKUP_TARGET_PU
= -0.005 pu
```

硬限：

```text
[-0.02,+0.02] pu
```

这不是说：

```text
ESS2最大只能0.005 pu
```

而是：

> R7已经在极小实际功率时出现电压恶化，因此第一轮必须用非常小的诊断工作点先回答“有没有稳定非零平衡点”。

若-0.005 pu稳定：

```text
下一轮才谈扩大
```

若-0.005 pu都不稳定：

```text
顶层目标漂移已排除
Alpha双动态已排除
Coordinator错误资源分配已排除
↓
转底层：
Power PI
Current Loop（电流环）
GFM/GFL阻抗耦合
符号/坐标
执行tracking（执行跟踪）
```

---

# 17. 用户明确冻结的最高算法原则

原始15策略不是不可修改的祖传代码。

最高原则：

> **策略本身如果不能实现策略功能，就直接改策略本体。**

因此：

```text
S14黑启动太基础
→ 改S14

S15重同步太基础
→ 以后改S15

S5计划孤岛需要完善
→ 改S5
```

禁止：

```text
为了“保护原算法”
→ 外围无限叠Function（函数模块）
→ 再叠状态机
→ 再叠补丁
```

---

# 18. 为什么本轮没有把S14迁到Stateflow（状态流程图）

Stateflow（状态流程图）很适合：

- 状态机；
- Supervisor（监督器）；
- 超时；
- 故障；
- 事件。

但当前15策略统一结构：

```text
SM_Master
/Advanced_Microgrid_15_Strategies
/Advanced_Strategy_Core
```

已经统一承载：

```text
40输入
→ 15策略
→ status/alarm/metric/cmd四组15维输出
```

若只把S14搬出去：

```text
原Core
+
单独Stateflow
+
重新拼4组15维输出
+
两套状态来源
```

本轮风险反而更大。

所以当前正确决策：

> **直接重写现有Advanced_Strategy_Core中的S14段，不增加新状态机。**

连续量处理：

- Rate Limiter（斜率限制）；
- Switch（开关选择）；
- Product（乘法）；
- Sum（求和）；
- Saturation（限幅）；
- Unit Delay（一拍延时）；

优先用标准Simulink模块。

---

# 19. 一次通过的S14架构审计为什么成功

正式审计：

```text
AUDIT_K26_K50_S14_V2_ESS2_POWER_PICKUP_ARCH_R1.m
```

用户本地一次通过。

成功的关键不是“运气”，而是执行了之前反复总结却曾经忘记执行的规则：

1. whole-SLX raw SHA（整个SLX原始哈希）只记录；
2. 当前SLX实际结构优先；
3. Dirty（未保存标志）开始/结束必须一致；
4. 只读审计不Update、不Compile、不Save；
5. Goto/From必须继续追真实源；
6. 普通信号Connectivity first（连接优先），Name second（名字其次）；
7. SPS物理线不用普通信号Src/Dst规则；
8. UNKNOWN（未知）不补0；
9. 一次扫描全部问题，不遇到第一个就return；
10. 一次性输出事实矩阵、问题矩阵、修改矩阵；
11. OpWrite识别直接复用成熟helper；
12. 脚本生成完做全文件静态QA。

这一轮应作为以后复杂只读审计标准模板。

---

# 20. 架构审计最终锁定的四个上层缺陷

## 20.1 S14仍是20/40/60 s时间推进

旧：

```text
black_state=1

t>20 → 2
t>40 → 3
t>60 → 4
```

它不知道：

- ESS2 RestoreState（恢复状态）；
- breaker（断路器）；
- restored ack（恢复完成确认）；
- availability（物理可用资格）。

这不是一个真正物理闭环黑启动Supervisor（监督器）。

---

## 20.2 Black Start Pref Gate按Stage直接放旧Pref

旧：

```text
Stage1 → 全零
Stage2 → 非master ESS旧Pref
Stage3 → PV旧Pref
Stage4 → EV旧Pref
```

错误：

> Stage编号不等于设备已经真实恢复。

---

## 20.3 Normal Island Coordinator默认五台GFL都在线

旧：

```text
upT=up1+up2+up3+up4+up5
dnT=dn1+dn2+dn3+dn4+dn5
```

黑启动真实状态却可能：

```text
PV1 断开
PV2 断开
ESS2 已恢复
EV1 断开
EV2 断开
```

所以原能力池与物理世界不一致。

---

## 20.4 availability与authority必须分开

`ESS2Available=1`只表示：

```text
ESS2有资格参与
```

不表示：

```text
ESS2可以直接用±1 pu额定能力承担全部系统调频
```

ESS1仍是唯一GFM。

因此必须再有：

```text
ESS2 coordination authority（ESS2协调权限）
```

本轮默认：

```text
0.01 pu
```

Coordinator内部硬上限：

```text
0.02 pu
```

这是第一轮诊断边界，不是最终容量结论。

---

# 21. 当前正式Patch总览：一次修改哪些问题

当前Patch一次性完成：

```text
S14时间推进
→ 物理反馈状态推进

粗Stage直接恢复旧Pref
→ S14物理黑启动旧Pref全零

一个Stage控制三层
→ Coordinator Stage / ESS2 GFL Stage / Restore Stage分开

Coordinator默认五GFL在线
→ S14时只允许真实恢复资源参与

设备额定能力=协调能力
→ 单独增加小authority

Alpha连续时间斜坡
→ Alpha只做0/1权限，真正功率斜坡移动到Pref

S14→Coordinator硬切
→ beta平滑混合

beta完成后一次协调立即全开
→ Correction Gain再单独0→1

Secondary提前积分
→ R1明确关闭Secondary

G29看不到上层因果
→ 46→68补完整系统状态
```

---

# 22. 修改位置1：Advanced Strategy Core（高级策略核心）

路径：

```text
K26_K50_CLEAN_P1
/SM_Master
/Advanced_Microgrid_15_Strategies
/Advanced_Strategy_Core
```

修改前：

```text
外层子系统：40 input / 4 output
Core：40 input / 4 output
```

修改后：

```text
外层子系统仍：40 input / 4 output
Core内部：44 input / 5 output
```

为什么外层不扩：

> 避免改变原15策略对整套模型的公共接口。

新增Core输入：

| Core端口 | 信号 | 中文作用 |
|---:|---|---|
|41|ESS2 RestoreStatus12（储能2恢复12维状态）|读取真实恢复状态|
|42|HandoverBeta_Z1（接管比例一拍值）|判断平滑接管是否完成|
|43|S14 Arm_Z1（策略14执行预备一拍值）|确认模式执行链真正进入黑启动|
|44|CFG15_BLACKSTART_MASTER（黑启动主机构网设备）|强制本轮只允许ESS1为主GFM|

新增Core输出5：

```text
S14Exec13（策略14执行13维控制向量）
```

---

# 23. 为什么Beta和Arm必须一拍延时

若同拍：

```text
S14状态
→ OwnerRequest
→ Beta
→ S14判断Beta
```

可能形成代数环。

所以新增：

```text
Advanced_Microgrid_15_Strategies
/AA15_S14V2_BETA_Z1
```

以及：

```text
Advanced_Microgrid_15_Strategies
/AA15_S14V2_ARM_Z1
```

参数：

```text
SampleTime = 0.0001 s
InitialCondition = 0
```

对秒级黑启动：

```text
100 μs延迟几乎不可见
```

但对Simulink因果：

```text
非常重要
```

---

# 24. S14Exec13精确通道

Core output5先经过：

```text
AA15_S14V2_EXEC13_NORMALIZER（策略14执行向量正规化器）
```

内部：

```text
13×1 MATLAB Function输出
→ Demux13（13路拆分）
→ 13个scalar（标量）
→ Mux13（13路拼接）
→ 经典1-D Simulink vector（一维Simulink向量）
```

然后：

```text
AA15_S14V2_EXEC13_DEMUX
```

再次拆成13个标量，发布13个global Goto（全局标签发送）。

字段：

|序号|信号|
|---:|---|
|1|S14Substate（策略14详细子状态）|
|2|CoordinatorStage（中央协调阶段）|
|3|ESS2GFLStage（储能2本地跟网阶段）|
|4|ESS2RestoreStage（储能2恢复阶段）|
|5|PickupEnable（固定小功率使能）|
|6|ESS2Available（储能2可参与协调）|
|7|OwnerRequest（协调器接管请求）|
|8|SecondaryEnable（二次协调使能）|
|9|CorrectionEnable（一次协调修正使能）|
|10|S14Active（策略14物理黑启动有效）|
|11|CoarseStage（粗阶段）|
|12|StateElapsed_s（当前状态已运行秒数）|
|13|GoodDwell_s（健康连续驻留秒数）|

对应global tags（全局标签）：

```text
AA15_S14V2_SUBSTATE
AA15_S14V2_COORD_STAGE
AA15_S14V2_ESS2_GFL_STAGE
AA15_S14V2_ESS2_RESTORE_STAGE
AA15_S14V2_PICKUP_ENABLE
AA15_S14V2_ESS2_AVAILABLE
AA15_S14V2_OWNER_REQUEST
AA15_S14V2_SECONDARY_ENABLE
AA15_S14V2_CORRECTION_ENABLE
AA15_S14V2_ACTIVE
AA15_S14V2_COARSE_STAGE
AA15_S14V2_STATE_ELAPSED_S
AA15_S14V2_GOOD_DWELL_S
```

---

# 25. S14 V2正式子状态

```text
0   IDLE（空闲）
10  ESS1_FORMATION（储能1建网）
20  ESS2_GFL_PREPARE（储能2跟网准备）
25  ESS2_STAGE2_STABILIZE（储能2阶段2预合闸稳定）
30  ESS2_ZERO_RECONNECT（储能2零功率并回）
40  ESS2_POWER_PICKUP（储能2固定小功率承担）
50  ESS2_HANDOVER（储能2控制权平滑接管）
60  ESS2_COORD_PRIMARY（储能2正常孤岛一次协调）
90  FAIL（失败安全保持）
```

R1没有：

```text
70 SECONDARY（正常二次协调）
```

这是故意的。

---

# 26. state10：ESS1_FORMATION（储能1建网）

进入前资格：

```text
blackstart_enable（黑启动使能）有效
CFG15_BLACKSTART_MASTER（黑启动主机）= 1
SOC1 >= 0.25
beta反馈有效
```

进入后：

```text
StateElapsed每拍按真实模型dt累加
```

不是host sleep（主机休眠）。

形成条件：

```text
|Vpu-1| <= max(原island_v_dev_pu, 0.10)
|Freq-50| <= max(原island_freq_dev_Hz, 0.50)
S14 Arm_Z1 = 1
```

连续：

```text
1.0 s
```

才通过。

超时：

```text
15 s
```

进入FAIL。

旧逻辑：

```text
t>20s
```

完全删除。

---

# 27. state20：ESS2_GFL_PREPARE（储能2跟网准备）

输出：

```text
CoordinatorStage = 1
ESS2GFLStage = 1
ESS2RestoreStage = 1
```

保持：

```text
2.5 s
```

来源：

> 直接复用R6.1成功的5.5→8.0 s Stage1准备窗口。

---

# 28. state25：ESS2_STAGE2_STABILIZE（储能2阶段2预合闸稳定）

这是本轮写脚本时最关键的防返工发现之一。

初稿容易写成：

```text
Stage1结束
→ 直接Stage2
→ Restore也Stage2
→ 立即可能COMMIT
```

但R6.1真正成功时序是：

```text
8.0 s：
GFL Stage2

8.0~12.0 s：
先稳定约4 s

12.0 s：
才COMMIT
```

所以state25输出：

```text
CoordinatorStage = 2
ESS2GFLStage = 2
ESS2RestoreStage = 1
```

保持：

```text
4.0 s
```

效果：

```text
GFL底层已经进入弱网稳定模式
但Restore Executor只允许READY
不能COMMIT
```

4 s结束才：

```text
ESS2RestoreStage = 2
```

允许真实合闸。

---

# 29. 为什么现在必须有三套Stage语义

正式区分：

## 29.1 CoordinatorStage（中央协调阶段）

控制：

- 中央有功Coordinator；
- 中央Q-bias（无功偏置协调）。

## 29.2 ESS2GFLStage（储能2跟网阶段）

控制ESS2本地：

- dynamic VFF（动态电压前馈）；
- 本地孤岛支撑；
- frame（坐标框架）逻辑；
- Qref/q-bias decoder（无功参考/无功偏置解码）。

## 29.3 ESS2RestoreStage（储能2恢复阶段）

只控制：

- READY资格；
- COMMIT；
- power release（功率释放）权限。

旧设计：

```text
一个global Stage
→ 同时干三件事
```

导致无法实现：

```text
GFL已经Stage2稳定
但breaker还不能合
```

这种必要顺序。

---

# 30. state30：ESS2_ZERO_RECONNECT（储能2零功率并回）

输出：

```text
CoordinatorStage = 2
ESS2GFLStage = 2
ESS2RestoreStage = 2
```

等待现有Restore Executor：

```text
state1
→ state2
→ state3 READY
→ state4真实合闸后零电流主动调节
→ state5零功率稳定
```

通过条件：

```text
RestoreState == 5
AND ReleaseAllowed == 1
AND FailCode == 0
```

超时：

```text
20 s
```

进入FAIL。

---

# 31. state40：ESS2_POWER_PICKUP（储能2固定小功率承担）

输出：

```text
CoordinatorStage = 2
ESS2GFLStage = 3
ESS2RestoreStage = 3

PickupEnable = 1
ESS2Available = 0
OwnerRequest = 0
SecondaryEnable = 0
CorrectionEnable = 0
```

解释：

- ESS2本地GFL需要进入真正功率恢复结构；
- 中央Coordinator还停Stage2；
- ESS2暂不进入正常协调器能力池；
- 固定小P由S14独占；
- 二次频率/电压恢复完全关闭；
- 正常一次调频修正也关闭。

---

# 32. 修改位置2：Black Start Pref Gate（黑启动有功参考门）

路径：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_LOCAL_CONTROL_STACK
/AA15_Black_Start_Pref_Gate
/AA15_Black_Start_Pref_Gate_Core
```

修改前：

```text
Stage2 → nonmaster ESS旧Pref
Stage3 → PV旧Pref
Stage4 → EV旧Pref
```

修改后：

只要：

```text
S14被选中
且真实BLACK_START执行链armed
且blackstart master = ESS1
```

则：

```text
PV1 old Pref = 0
PV2 old Pref = 0
ESS1 old Pref = 0
ESS2 old Pref = 0
EV1 old Pref = 0
EV2 old Pref = 0
```

ESS2第一个非零功率：

```text
不再来自旧Pref Gate
```

而来自：

```text
S14固定pickup target（拾取目标）
```

非S14：

```text
exact passthrough（精确旁路）
```

---

# 33. 修改位置3：两个新可调参数

新增：

```text
SM_Master/AA15_S14V2_CFG_PICKUP_TARGET_PU
```

默认：

```text
-0.005
```

新增：

```text
SM_Master/AA15_S14V2_CFG_ESS2_COORD_AUTH_PU
```

默认：

```text
0.01
```

这些以后可以在Runner t=0写。

但它们只调：

```text
目标/权限
```

不负责：

```text
人工切控制权
```

---

# 34. 修改位置4：ESS2唯一有功所有权子系统

新增：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_S14V2_ESS2_P_OWNERSHIP_BLEND
```

这是普通Simulink子系统，不是状态机。

输入：

```text
1 PCoord（正常孤岛Coordinator原始ESS2 Pref）
2 PickupTarget（S14固定小功率目标）
3 PickupEnable（固定小功率使能）
4 OwnerRequest（协调器接管请求）
5 S14Active（S14物理黑启动有效）
```

输出：

```text
1 PFinal（最终给ESS2的有功参考）
2 PS14Ramped（S14斜坡后固定小P）
3 HandoverBeta（平滑接管比例）
```

---

# 35. ESS2 Pref连线精确修改

修改前：

```text
SM_Master/P3_FROM_002_01
→ SM_Master/ESS2_IO_Mux12 input6
```

其中：

```text
P3_FROM_002_01
= normal island Coordinator PrefESS2
```

修改后：

```text
P3_FROM_002_01
→ AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/PCoord

AA15_S14V2_ESS2_P_OWNERSHIP_BLEND/PFinal
→ ESS2_IO_Mux12 input6
```

这就是唯一最终P所有权点。

---

# 36. 固定小功率斜坡

路径：

```text
PickupTarget
→ Saturation（限幅）
→ × PickupEnable
→ PickupRateLimiter（固定小功率斜率限制）
→ PS14Ramped
```

限幅：

```text
[-0.02,+0.02] pu
```

斜率：

```text
FallingSlewLimit = -0.0025 pu/s
RisingSlewLimit  = +0.01 pu/s
InitialCondition = 0
```

默认：

```text
0 → -0.005 pu
```

约：

```text
2 s
```

达到。

退回0更快。

---

# 37. Beta（接管比例）平滑切换

内部：

```text
OwnerRequest × S14Active
→ BetaRateLimiter（接管比例斜率限制）
```

参数：

```text
Rising = +0.5 /s
Falling = -2.0 /s
IC = 0
```

所以：

```text
0 → 1
约2 s
```

回退：

```text
1 → 0
约0.5 s
```

最终：

```math
P_{final}
=
(1-β)P_{S14}
+
βP_{Coord}
```

非S14：

```text
PFinal = PCoord
```

使用独立Switch（选择开关）保证exact bypass。

---

# 38. state50：ESS2_HANDOVER（平滑接管）

进入前提：

```text
RestoreState == 7
```

而新的state7已经不再表示“Alpha计时结束”，而表示：

```text
固定小功率真实稳定
```

state50输出：

```text
ESS2Available = 1
OwnerRequest = 1
CorrectionEnable = 0
SecondaryEnable = 0
PickupEnable = 1
```

所以：

- Coordinator知道ESS2已经可参与；
- 但还不能增加额外调频责任；
- S14的-0.005路径仍保持；
- beta才开始0→1。

---

# 39. Coordinator baseline（协调基线）怎么无扰接住-0.005

在state40：

```text
ESS2Available=0
CorrectionGain=0
```

Coordinator内部：

```text
pbase_ESS2
每拍跟踪实际Pmeas_ESS2
```

所以固定小功率稳定时：

```text
Pmeas ≈ -0.005
pbase_ESS2 ≈ -0.005
```

进入state50：

```text
Available变1
Correction仍0
```

Coordinator输出仍应在当前工作点附近。

于是beta：

```text
S14 -0.005
→ Coordinator约-0.005
```

不是：

```text
-0.005 → -0.2
```

---

# 40. 修改位置5：Normal Island Coordinator（正常孤岛协调器）

路径：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_ISLAND_SUPERVISORY_COORDINATION
/AA15_FINAL_ISLAND_COORDINATOR
/AA15_FINAL_COORD_CORE
```

外层保持：

```text
30 input
31 output
```

Core内部：

```text
59 input
→ 64 input
```

输出仍：

```text
48
```

新增内部输入：

|Core端口|信号|
|---:|---|
|60|S14Active（S14有效）|
|61|ESS2Available（ESS2可参与）|
|62|CorrectionGainActual（实际一次协调增益）|
|63|SecondaryEnable（二次协调使能）|
|64|ESS2CoordAuthority（ESS2协调权限）|

非S14：

```text
全部新限制自动exact bypass
```

保持原计划孤岛行为。

---

# 41. Coordinator availability（协调可用资格）

S14 active时：

```text
PV1 = unavailable
PV2 = unavailable
ESS2 = S14决定
EV1 = unavailable
EV2 = unavailable
```

unavailable设备：

```text
pmin = pbase
pmax = pbase
```

得到：

```text
Up = 0
Down = 0
```

不会再进入能力池。

PV/EV数值输出还进一步置0，避免物理未恢复设备收到虚假正常功率命令。

ESS2即使available=0时，Coordinator raw Pref仍保留其跟踪baseline，用于后续无扰接管。

---

# 42. Coordinator authority（协调权限）

ESS2设备模型原始范围仍可能：

```text
[-1,+1] pu
```

但S14 active时额外限制：

```text
[pbase-auth, pbase+auth]
```

默认：

```text
auth = 0.01 pu
```

Core内部硬限：

```text
auth <= 0.02 pu
```

所以不会发生：

```text
其它4台unavailable
→ 所有调频责任全部压给唯一ESS2
```

---

# 43. 为什么R1不现在硬造ESS1动态余量公式

架构上已经明确：

> 最终正常黑启动协调必须考虑ESS1 GFM的P/Q、电流、调制和电压余量。

但现在没有实验认证的：

```text
ESS1 margin threshold（ESS1余量阈值）
```

如果现在直接写：

```text
某个I/Mod/P/Q公式
→ 动态算authority
```

就是新的一层未经证明算法。

R1目标只回答：

```text
固定-0.005能否稳定
+
能否平滑交给Coordinator
```

所以用：

```text
极小static authority（静态协调权限）
+
hard cap（硬上限）
```

更合理。

这叫：

```text
有意延期
```

不是遗漏。

---

# 44. Correction Gain（一次协调修正增益）

新增：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_ISLAND_SUPERVISORY_COORDINATION
/AA15_S14V2_CORRECTION_GAIN_RATE_LIMITER
```

输入目标：

```text
S14 CorrectionEnable × S14Active
```

参数：

```text
Rising = +0.25 /s
Falling = -2.0 /s
IC = 0
```

非S14：

```text
Switch强制actual gain = 1
```

state50：

```text
CorrectionEnable=0
```

beta完成以后state60：

```text
CorrectionEnable=1
```

实际一次协调从：

```text
0 → 1
约4 s
```

不会在beta刚到1时突然全强度出现。

---

# 45. state60：ESS2_COORD_PRIMARY（正常孤岛一次协调）

此时：

```text
beta = 1
ESS2Available = 1
OwnerRequest = 1
PickupEnable = 1（作为热备用，便于回退）
CorrectionEnable = 1
SecondaryEnable = 0
CoordinatorStage = 2
ESS2GFLStage = 3
ESS2RestoreStage = 3
```

为什么PickupEnable还保持1：

> beta=1时S14固定P对最终输出没有权重，但让其Rate Limiter保持在-0.005附近。若后面本地资格丢失，beta需要快速退回0时，S14路径已经“热着”，不用再次从0慢慢爬到-0.005。

这是本次续接时在原中断草案基础上进一步补强的回退连续性设计。

---

# 46. R1为什么不自动打开Secondary（二次协调）

R7失败时已经同时存在：

```text
Stage3
+
secondary integrator（二次积分）
+
moving normal target（移动正常目标）
+
Alpha ramp（Alpha斜坡）
```

本轮如果又一次：

```text
fixed P
→ beta
→ primary
→ secondary
```

全部塞同一轮，就会再次丢失因果分层。

所以R1只做到：

```text
固定小P
+
平滑接管
+
Primary-only
```

Runner在state60观察后停止。

Secondary下一轮单独验证。

---

# 47. 中央Stage连线精确改法

路径：

```text
SM_Master/AA15_ISLAND_SUPERVISORY_COORDINATION
```

修改前：

```text
AA15_FINAL_SYSTEM_STAGE
→ AA15_FINAL_ISLAND_COORDINATOR input1

AA15_FINAL_SYSTEM_STAGE
→ AA15_V48_ISLAND_QBIAS_COORDINATOR input1
```

新增：

```text
AA15_S14V2_COORD_STAGE_SWITCH
```

输入：

```text
u1 = S14 CoordinatorStage
u2 = S14Active
u3 = 原AA15_FINAL_SYSTEM_STAGE
```

输出：

```text
→ AA15_FINAL_ISLAND_COORDINATOR input1
→ AA15_V48_ISLAND_QBIAS_COORDINATOR input1
```

非S14：

```text
exact fallback原global stage
```

---

# 48. ESS2本地GFL Stage连线精确改法

修改前：

```text
SM_Master/P3_FROM_006_03
→ ESS2_IO_Mux12 input5
```

新增：

```text
SM_Master/AA15_S14V2_ESS2_GFL_STAGE_SWITCH
```

输入：

```text
u1 = S14 ESS2GFLStage
u2 = S14Active
u3 = 原P3_FROM_006_03
```

输出：

```text
→ ESS2_IO_Mux12 input5
```

同时发布：

```text
AA15_S14V2_ESS2_GFL_STAGE_EFFECTIVE
```

---

# 49. Restore Stage连线精确改法

已有：

```text
SM_Master/AA15_ESS2_RESTORE_STAGE_FROM_S14
```

修改前Tag：

```text
AA15_BS_STAGE_ECHO
```

修改后Tag：

```text
AA15_S14V2_ESS2_RESTORE_STAGE
```

不扩SM→SS2 25维通信。

只把已有的“第25个Stage scalar（阶段标量）”改为新的Restore Stage语义。

---

# 50. Qref/q-bias语义坑：本轮脚本后审查发现的关键问题

这是一个如果遗漏，很可能Build能过、电气却错的典型坑。

当前Q通道在不同Stage有不同语义：

```text
Stage3/4：
Q通信槽 = qsec_req（无功二次偏置）

其它Stage：
Q通信槽 = legacy Qref（原无功参考）
```

ESS2源端router：

```text
AA15_V48_QREF_QBIAS_ROUTER_ESS2
```

设备端decoder也根据：

```text
local GFL Stage
```

判断这个标量到底是什么。

如果：

```text
ESS2 local Stage = 3
中央 Stage = 2
```

而源端router仍看中央Stage2：

```text
源端：把数值当Qref
接收端：因为local Stage3，把同一个数值当q-bias
```

这属于：

> **物理量语义错位。**

不是一个简单数值误差。

---

# 51. Q通道正式修法

中央Q-bias：

```text
AA15_S14V2_COORD_STAGE_SWITCH
→ AA15_V48_ISLAND_QBIAS_COORDINATOR input1
```

所以当前中央Stage2：

```text
central q-bias保持reset/off
```

ESS2 Q source router：

修改前：

```text
AA15_FINAL_SYSTEM_STAGE
→ AA15_V48_QREF_QBIAS_ROUTER_ESS2 input1
```

修改后：

```text
From AA15_S14V2_ESS2_GFL_STAGE_EFFECTIVE
→ AA15_V48_QREF_QBIAS_ROUTER_ESS2 input1
```

于是：

```text
source router
与
ESS2 device decoder
```

永远看到同一个local Stage。

---

# 52. Restore Config（恢复配置）31→34

路径：

```text
K26_K50_CLEAN_P1
/SS_Slave2
/AA15_ESS2_RESTORE_CONFIG
```

原31项保留。

新增：

```text
32 CFG_ESS2_RESTORE_PICKUP_PREF_MIN_PU = 0.0045
33 CFG_ESS2_RESTORE_PICKUP_PERR_MAX_PU = 0.002
34 CFG_ESS2_RESTORE_PICKUP_STABLE_DWELL_S = 3.0
```

同时：

```text
CFG_ESS2_RESTORE_STAGE_TRIGGER_MIN
2 → 1
```

---

# 53. 为什么Stage Trigger改1，却不会提前合闸

Stage1：

```text
允许Executor：
state1 → state2 → READY → state3
```

但新互锁：

```text
state3 COMMIT
必须 source=S14
AND stage >= 2
```

所以：

```text
Stage1只准备
Stage2才合闸
```

正好复用R6.1成功结构。

---

# 54. “state0~5冻结”到底是什么意思

不是：

```text
一个字符都不能改
```

而是：

> **不重新设计已经验证成功的物理资格、真实电流闭环、PostOK、zero-stable逻辑。**

本轮只增加两个上层阶段互锁：

```text
state3：
S14 source时
stage >= 2
才COMMIT

state5：
S14 source时
stage >= 3
才允许release
```

这属于：

```text
把已验证primitive（基础执行单元）接进正确Supervisor（监督器）
```

不是重做state0~5。

---

# 55. state6正式新定义：固定小功率真实验证

旧state6：

```text
releaseAlpha += Ts/releaseRamp
→ alpha到1
→ state7
```

删除。

新state6：

```text
breaker=1
hold=0
releaseAlpha=1
```

真正连续斜坡已经移动到：

```text
S14固定Pref Rate Limiter
```

所以不会再：

```text
P目标在变
+
Alpha也在变
```

---

# 56. state6通过条件

从现有diag48读取：

- Final Iref（最终电流参考）；
- Imeas（实测电流）；
- Pmeas（实测有功）；
- PLL（锁相频率）；
- Vpu（电压标幺）；
- PrefEff（有效有功参考）；
- CurrentLimit（限流）；
- ModHeadroom（调制余量）。

要求：

```text
abs(PrefEff) >= 0.0045
abs(Pmeas-PrefEff) <= 0.002

Vpu在原ready范围
|PLL-fNom| <= dfMax
IrefMag <= postImax
ImeasMag <= postImax
CurrentLimit = 0
ModHeadroom >= headroomMin
```

连续：

```text
3 s
```

才：

```text
state6 → state7
```

这3 s不是“状态计时器自动成功”。

它必须建立在：

```text
真实固定非零P
+
真实跟踪误差
+
真实V/f
+
真实电流
+
真实限流
+
真实调制余量
```

全部满足上。

---

# 57. 为什么state6 severe（严重异常）同时看Iref与Imeas

旧阶段主要看Imeas。

但功率承担时可能：

```text
Power PI已经把Iref要求推很大
实际电流还没来得及跟上
```

只看Imeas会晚。

所以新增：

```text
IrefMag > postImax
```

并保留：

```text
ImeasMag > postImax
Vpu超post范围
CurrentLimit动作
```

severe时：

若：

```text
abortOpen=1
```

进入state9并断开。

当前默认：

```text
abortOpen=0
```

则：

```text
回state5
Alpha=0
breaker保持闭合
hold=0
真实电流闭环保持
FailCode置位
```

随后S14进入FAIL安全保持。

---

# 58. state7正式新定义

旧：

```text
state7
= alpha走到1
```

R7已经证明这个语义是错的：

```text
state7时Vpu甚至可以已经≈0.2
```

新：

```text
state7 = ESS2_LOCAL_RESTORED（储能2本地恢复完成）
```

含义：

> ESS2在本次固定小功率工作点上，真实满足功率跟踪和电气健康连续3 s，可以交给正常孤岛Coordinator接管。

---

# 59. state50/60如果本地恢复资格丢失

S14不会盲目继续。

state50：

```text
RestoreState != 7
→ 回state40
```

state60：

```text
RestoreState != 7
→ 回state40
```

同时：

```text
CorrectionEnable归0
OwnerRequest归0
beta以更快斜率退回
```

并且本轮续接加强为：

```text
state60仍保持PickupEnable=1
```

让S14固定小功率路径保持热备用。

---

# 60. FAIL状态语义

如果：

- blackstart master（黑启动主机）错误；
- SOC1不足；
- Restore FailCode非0；
- formation超时；
- zero reconnect超时；
- pickup超时；
- handover超时；

进入：

```text
S14 substate90
```

关键：

> 物理黑启动已经开始以后，FAIL不能静默掉回GRID_NORMAL（强网正常阶段）。

否则可能：

- J1控制权丢失；
- GFL弱网整形突然恢复强网模式；
- 旧Pref穿透。

所以state90仍保持S14物理黑启动authority（权限），输出：

```text
中央Stage2
ESS2 GFL Stage2
Restore Stage2
Pickup=0
Owner=0
Correction=0
Secondary=0
```

让系统尽可能回到已验证的弱网/零功率语义。

---

# 61. G29为什么必须扩

现有：

```text
G27 = ESS2本地高速因果
G30 = ESS1 GFM详细因果
```

但过去缺：

- S14到底哪个substate；
- central Stage；
- local GFL Stage；
- Restore Stage；
- 当前最终P到底由谁拥有；
- beta；
- correction gain；
- availability；
- authority。

若不记录这些：

```text
电气波形坏
→ 又只能猜上层当时到底是什么状态
```

所以G29必须补系统级因果。

---

# 62. OpWrite（目标端记录）最终合同

仍然只有5组：

| Group（组） | Decimation（抽取倍率） | 主要作用 |
|---|---:|---|
|G26|4|EV1/EV2高速诊断|
|G27|4|ESS2高速本地诊断|
|G28|4|PV1/PV2高速诊断|
|G29|4|系统/S14/协调因果|
|G30|10|ESS1 GFM内部详细诊断|

禁止G31。

---

# 63. G27保持62通道，不再扩

G27继续看：

- RawIdRef/RawIqRef（原始电流参考）；
- FinalIdRef/FinalIqRef（最终电流参考）；
- Id/Iq Meas（实测dq电流）；
- RawVdq（原始dq电压）；
- FinalVFF（最终电压前馈）；
- Current PI（电流比例积分输出）；
- Vconv（变流器电压命令）；
- ModIndex（调制度）；
- P/Q；
- GammaP/GammaQ（有功/无功权重）；
- PLL；
- Vpu；
- PrefCmd/PrefAfterUV/PrefEff；
- RestoreHold；
- RestoreAlpha；
- breaker command；
- CurrentLimit；
- ModHeadroom；
- breaker-inner Vabc；
- bus Vabc；
- phaseCorr；
- voltageRatio；
- IrefUsed；
- ImeasUsed；
- MatchActive；
- PostOK。

它已经足够回答ESS2本地因果。

---

# 64. G30保持128通道，不改

G30继续负责ESS1 GFM：

- Fref；
- Fout；
- theta；
- PLL；
- Vabc；
- P/Q；
- Voltage PI（电压比例积分）；
- Current reference（电流参考）；
- Id/Iq；
- Vconv；
- Vd/Vq测量与参考；
- 历史F20/F22/F23/F24/F25内部诊断。

本轮不碰。

---

# 65. G29 46→68

原1~46：

> 一个source block/source port都不能变。

Patch在保存前后用真实endpoint（端点）逐项比较。

新增：

| G29通道 | 含义 |
|---:|---|
|47|S14Substate（策略14子状态）|
|48|S14CoarseStage（策略14粗阶段）|
|49|S14StateElapsed_s（当前状态持续秒数）|
|50|ESS2RestoreStageCmd（ESS2恢复阶段命令）|
|51|CoordinatorStageCmd（中央协调阶段命令）|
|52|ESS2GFLStageCmd（ESS2本地GFL阶段命令）|
|53|PickupEnable（固定小功率使能）|
|54|OwnerRequest（接管请求）|
|55|PickupTargetRaw_pu（固定小P原始目标）|
|56|PS14Ramped_pu（S14斜坡后P）|
|57|PCoordRaw_pu（Coordinator原始P）|
|58|PFinalApplied_pu（最终给ESS2的P）|
|59|HandoverBeta（接管比例）|
|60|ESS2Available（ESS2可参与）|
|61|CorrectionGainActual（实际一次协调增益）|
|62|SecondaryEnable（二次协调使能）|
|63|ESS2CoordAuthority_pu（ESS2协调权限）|
|64|S14Active（S14有效）|
|65|RestoreState（恢复状态）|
|66|RestoreAlpha（恢复系数）|
|67|RestoreFailCode（恢复失败码）|
|68|RestoreReleaseAllowed（允许释放）|

MAT：

```text
row1 = Target Time
row2 = ch1
...
row69 = ch68
```

所以新G29 MAT应为：

```text
69行
```

---

# 66. 为什么ch50记录RestoreStage，而不是GoodDwell

最早设计曾想记录：

```text
S14 GoodDwell（健康驻留时间）
```

但最终发现对防返工更关键的是：

```text
state25期间：
ESS2 GFL Stage = 2
Restore Stage = 1
```

这是证明：

```text
GFL已经完成Stage2弱网稳定
但Restore还没获得COMMIT资格
```

的直接证据。

所以ch50最终给：

```text
ESS2RestoreStageCmd
```

而不是GoodDwell。

GoodDwell仍存在于S14Exec13字段13，需要时可通过在线信号或后续重新规划，但本轮G29优先记录阶段分离证据。

---

# 67. Patch如何保护G29旧1~46不被悄悄改掉

Patch preflight先读取：

```text
AA15_FINAL_G29_MUX38
input1~46
```

每一路：

```text
真实source block
+
source port
```

存成endpoint矩阵。

scratch修改后比较一次。

正式修改前再次比较。

正式修改后再比较。

close/reload以后再比较。

任何一个旧通道：

```text
块变了
或
端口变了
```

Patch报错。

这样避免：

> “为了加新通道，旧诊断被无意重排，下一轮MAT解释全部错位。”

---

# 68. Patch如何避免改坏原15策略其它14项

正式硬门：

```text
Advanced_Strategy_Core当前源码SHA
= 7caa43572ef5c3486b122bf74abd0f184000b02ab34814a9f2694fb6cb828d5b
```

只有完全匹配本次一次通过审计的当前源码，才允许写。

候选Strategy源码不是重新手写1~15。

而是：

> 以当前真实Strategy源码为基线，只替换S14部分并扩展内部输入/输出。

Patch写完后：

```text
原Core input1~40 endpoint
```

逐项与修改前比较。

所以：

- S1~S13；
- S15；
- 原40输入来源；

不允许因为S14改造被悄悄换线。

---

# 69. Patch如何避免改坏原Coordinator

修改前：

```text
Coordinator outer = 30 in / 31 out
Core = 59 in / 48 out
```

修改后：

```text
outer仍30 / 31
Core = 64 / 48
```

Patch保存前后比较：

```text
原Core input1~59 endpoint
```

全部必须不变。

只允许新增：

```text
60~64
```

所以原：

- legacy Pref；
- Pmeas；
- PVmax；
- SOC；
- Vref/Fref；
- state delay；
- 原参数；

不重新接线。

---

# 70. Patch如何保护Current Adapter和Power PI

Current Adapter核心源码SHA硬门：

```text
1414737b8b1672f6bbadf27a6112fe95efc129dab9a13a1db921926519035223
```

preflight先检查。

postassert再检查。

本轮不写它。

Power PI：

- 不改Kp；
- 不改Ki；
- 不加新reset；
- 不重写Power Loop。

原因：

> 先把上层移动目标/控制权缺陷排除。若-0.005固定平台仍失败，再定向判断Power PI下游tracking是否是根因。

---

# 71. Patch的5个Harness分别防什么

## 71.1 Strategy Harness（策略隔离测试）

验证：

```text
44 input / 5 output
```

且：

```text
output5 13×1
→ production-equivalent vector normalizer
```

能够普通Simulink update（更新）。

防：

- MATLAB Function语法错误；
- 44口推导错误；
- 13维列向量维度传播错误。

---

## 71.2 Gate Harness（有功门隔离测试）

验证：

```text
14 input / 11 output
```

候选源码解析。

---

## 71.3 Coordinator Harness（协调器隔离测试）

验证：

```text
64 input / 48 output
```

新availability/authority/correction/secondary源码解析。

---

## 71.4 Executor Harness（恢复执行器隔离测试）

使用34维真实配置形状：

```text
cfg34
stage
diag48
vinner3
vbus3
z5
```

验证候选state机源码解析。

---

## 71.5 Ownership Blend Harness（所有权混合隔离测试）

直接调用与正式Patch相同的builder（构造函数）。

验证：

- Saturation；
- Product；
- Rate Limiter；
- beta；
- Switch；
- 3输出接口。

这条专门吸收过去：

> Harness和正式builder不一致，Harness PASS但正式Patch仍失败。

的经验。

---

# 72. 为什么Harness不是RT-LAB Build的替代

Harness只能证明：

- 候选MATLAB Function能被普通Simulink解析；
- 新建普通块的参数名合法；
- 接口宽度可以传播；
- builder实际构造可update。

不能证明：

- ARTEMiS完整实时编译；
- OpComm跨任务最终宽度；
- RT-LAB masked library；
- Target信号暴露；
- 实时overrun。

最终裁判仍然：

```text
RT-LAB Rebuild All
```

---

# 73. Verifier为什么必须独立

Patch负责写模型。

Verifier负责：

```text
重新打开已保存模型
→ 只读检查
```

禁止Verifier调用Patch内部helper。

原因：

> 写错模型的代码不能用同一套错误假设证明自己正确。

Verifier独立检查：

- 候选核心源码SHA；
- 端口数；
- S14 13个global tags；
- 唯一P所有权连线；
- local Stage；
- Restore Stage tag；
- central Stage；
- Q source semantic alignment；
- config34；
- state6/7语义；
- G29 68；
- G29 old1~46；
- new47~68；
- OpWrite仍G26~G30；
- 25/45跨任务维度；
- G27/G30组号。

---

# 74. 当前Patch/Verifier静态审查到底检查了什么

本环境已经检查：

- 当前上传模型SHA=审计模型SHA；
- 所需关键路径全部在上传SLX中存在；
- Patch入口函数名=文件名；
- Verifier入口函数名=文件名；
- local function（局部函数）无重名；
- 没有裸 `&&` / `||` 物理行；
- Verifier里：
  - `set_param` = 0；
  - `add_block` = 0；
  - `delete_block` = 0；
  - `add_line` = 0；
  - `delete_line` = 0；
  - `save_system` = 0；
- Patch存在：
  - byte-identical scratch；
  - formal whole-file backup；
  - save exactly once；
  - semantic source hash preflight；
  - 5 Harness；
  - G29旧通道endpoint保护；
- Patch没有SPS `LConn/RConn/PortConnectivity`物理编辑逻辑；
- 没有创建G31。

静态结论：

```text
PASS
```

但不冒充MATLAB运行。

---

# 75. 下一轮Python Runner应该怎样设计

用户已经明确：

> 固定小功率和后续平滑接管可以在同一轮，只要固定小功率按规定时间证明稳定，就自动继续。

所以Rebuild成功后Runner正式目标：

```text
t=0：
只启S14
ESS1 black-start master
五台非主设备物理隔离
Restore Control Source = S14
手工COMMIT/RELEASE = 0

模型内部自动：
state10 ESS1建网
→ state20 Stage1 2.5 s
→ state25 Stage2预合闸 4 s
→ state30真实零功率并回
→ state40 0→-0.005 pu
→ state6真实健康连续3 s
→ state7
→ state50 beta 0→1
→ state60 correction gain 0→1
→ Primary-only保持若干秒
→ Runner Pause
→ 保存完整MAT
```

Runner不再负责：

```text
某时刻手工写Stage1
某时刻手工写Stage2
某时刻手工COMMIT
某时刻手工RELEASE
某时刻手工写beta
```

这些都已经移入模型策略。

Runner只负责：

- 初始参数合同；
- Target clock；
- 状态观察；
- hard safety；
- 证据保存。

---

# 76. 下一轮Runner必须记录/在线观察的关键量

从G29：

- S14Substate；
- CoarseStage；
- elapsed；
- RestoreStage；
- CoordinatorStage；
- ESS2GFLStage；
- PickupEnable；
- OwnerRequest；
- target raw；
- PS14；
- PCoord；
- PFinal；
- beta；
- Available；
- CorrectionGain；
- Secondary；
- authority；
- RestoreState；
- Alpha；
- FailCode；
- ReleaseAllowed。

从G27：

- Pmeas；
- PrefEff；
- Perror（可离线计算）；
- IrefUsed；
- ImeasUsed；
- Vpu；
- PLL；
- ModHeadroom；
- CurrentLimit；
- Current PI；
- VFF；
- Vconv。

从G30：

- ESS1 Fout；
- ESS1 Vref/Vmeas；
- ESS1 P/Q；
- ESS1 current；
- modulation相关量；
- 内部Voltage/Current PI。

---

# 77. 下一轮Runner的硬停和普通质量判据必须分开

Hard Safety（硬安全）：

- NaN/Inf；
- breaker未按命令；
- S14/GFL/Restore阶段合同自相矛盾；
- Alpha提前；
- FailCode；
- 不可逆错误。

普通Electrical Quality（电气质量）：

- Vpu暂低；
- f偏；
- Perror大；
- I变化；
- PostOK暂时false。

普通质量差：

```text
优先Pause/记录
```

不是：

```text
自动Reset
```

---

# 78. DirectMAT分析下一轮必须回答的问题

## 78.1 Test A：固定-0.005 pu

是否出现：

```text
PFinal稳定到-0.005
PrefEff稳定
Pmeas跟随
Vpu不持续下降
Iref不持续累积
CurrentLimit=0
ModHeadroom健康
ESS1 V/f仍健康
```

如果失败：

> 立即进入底层GFL/GFM功率环稳定性，不继续谈handover。

---

## 78.2 Test B：beta平滑接管

检查：

```text
PS14 ≈ PCoord
beta 0→1
PFinal是否连续
Pmeas是否连续
V/f是否连续
```

不能只看beta。

---

## 78.3 Test C：Primary correction慢开启

检查：

```text
CorrectionGain 0→1
PCoord逐步变化
PFinal=PCoord
ESS2实际P
ESS1 Fout
Vpu
```

如果CorrectionGain增加到某一点才出现问题：

> 可以直接得到一次协调稳定边界线索。

---

# 79. 当前还不知道的东西：不要写成已证明

以下仍是未知：

- ESS2固定-0.005 pu是否稳定；
- ESS2稳定功率上限；
- ESS2协调authority最终应该多大；
- ESS1 GFM真实安全余量阈值；
- Power PI是否必须加下游执行tracking；
- 二次频率恢复何时安全开启；
- 恢复PV/EV以后六机是否长期稳定；
- 完整六机黑启动与计划孤岛是否会收敛到相同长期稳定性。

这些必须后续试验回答。

---

# 80. 已经证明的东西：不要重复审

除非有新数据反证，不要重新怀疑：

- 当前模型路径/主模型身份；
- ESS1能够死母线建网；
- J1真实开断链；
- ESS2真实交流breaker链；
- ESS2 breaker-inner真实Vabc测量；
- state4 hold=0；
- state5 zero-power；
- real Imeas进入Current Adapter；
- G27 62通道；
- SM→SS2 25维；
- SS2→SM 45维；
- Stage0错误dynamic VFF约26 Hz机制；
- Stage1/2能把该快速模态压低约99.9%；
- ESS2零功率接入可稳定；
- R7失败发生在功率承担，而不是零功率合闸。

---

# 81. 默认问答规则

新窗口必须默认执行：

1. 结论先行。
2. 任何英文名称、参数、概念第一次出现必须附中文含义。
3. 用户是电气工程及其自动化研究生，不是程序员；代码可以专业，但解释必须能对应模型物理意义。
4. 不赞美、不客套、不说“好问题”。
5. 发现用户前提错，直接纠正。
6. 事实、已冻结决定、待验证假设、助手建议严格分开。
7. 不因为“以前习惯这样”就沿用；先问这一步真正要解决什么。
8. 已经有成熟标准方法/模块时，优先查实际文档和项目成功实现，不自造新框架。
9. 模型修改涉及英文块名时，必须同时说明中文作用。
10. 数据分析后要形成Markdown归档。
11. 用户要求“可以手动改”时，不为自动化而自动化。
12. 不确定SPS物理连接时停止自动修改，给出精确手动位置。
13. 不把单次脚本异常自动升级成物理模型缺陷。
14. 不把物理波形差自动升级成脚本失败。
15. 不把脚本PASS自动升级成电气PASS。

---

# 82. 默认推理原则

## 82.1 从第一触发事件出发

例如R7：

```text
Power release
→ V下降
→ 后CurrentLimit
```

所以不能倒因果说：

```text
CurrentLimit导致第一波下降
```

---

## 82.2 一次只隔离一个因果变量

R6.1就是正确示范：

```text
只改GFL engineering Stage
不放功率
```

从而证明约26 Hz问题来自stage/VFF链。

---

## 82.3 先分“接入”和“承担功率”

```text
breaker close transient（合闸暂态）
```

与：

```text
power-sharing transient（功率分担暂态）
```

必须分开。

---

## 82.4 先建立固定工作点，再谈动态调度

若目标一直动，就无法判断：

```text
系统是工作点不稳定
还是调度轨迹不稳定
```

所以当前先-0.005固定平台。

---

## 82.5 模型内部慢状态必须可见

以后不能只看：

```text
V/F/P/Q
```

还必须记录：

- stage；
- owner；
- beta；
- authority；
- correction gain；
- local restore state。

---

# 83. 脚本分类：每一类脚本只能做自己的事

| 类别 | 典型语言 | 正确职责 |
|---|---|---|
|A 只读审计|MATLAB|回答当前模型真实是什么|
|B Patch（改模）|MATLAB|真正改SLX|
|C Verifier（验证）|MATLAB|改完后独立只读验证|
|D Harness（隔离测试）|MATLAB|验证builder/源码/维度|
|E Target Probe（目标端探针）|Python|验证Build后的参数/信号可读写|
|F Runner（动态运行）|Python|按Target时间轴执行正式工况|
|G Archive-only（只归档）|Python|已有MAT归档，不重跑|
|H DirectMAT（直接MAT分析）|MATLAB/Python|原始MAT定量分析|
|I Plot/Report（绘图报告）|MATLAB/Python|数据冻结后出图|
|J Manifest（清单/版本）|Python/MATLAB|SHA、版本、正确/废止索引|

禁止：

```text
Verifier语法错
→ 重跑Patch

Analyzer报错
→ 重跑物理试验

Build失败
→ 自动判控制理论错
```

必须先判断脚本所属层。

---

# 84. 只读审计脚本固定经验

## 84.1 raw SHA只作provenance（来源记录）

SLX是ZIP容器。

布局/保存/metadata可能改变raw SHA。

硬门应该是：

- 关键块；
- 当前源码；
- 当前端口；
- 当前参数；
- 当前连接。

---

## 84.2 Connectivity first（连接优先）

普通信号：

```text
source block/outport
→ destination block/inport
```

物理SPS：

```text
conserving port节点成员
```

名字只是解释。

---

## 84.3 Goto/From不能停在From

必须：

```text
From
→ tag
→ unique Goto
→ Goto input source
→ Switch/Mux/Measurement
```

不唯一：

```text
UNKNOWN/AMBIGUOUS
```

不能取第一个。

---

## 84.4 父子系统接口按port（端口）硬审

不要：

```text
find Name='Vabc'
```

做唯一硬合同。

应该：

```text
parent input1实际来源
parent input2实际来源
...
```

---

## 84.5 OpWrite识别复用成熟helper

不要再：

```text
BlockType='Reference'
```

猜。

正确：

```text
遍历block
→ ReferenceBlock/SourceBlock/MaskType
→ contains('opwritefile')
→ 读Acq_Group
```

---

## 84.6 UNKNOWN不能补0

读不到：

```text
UNKNOWN
```

不是：

```text
0
```

否则自动脚本可能对未知结构做破坏性决定。

---

## 84.7 一轮审计一次收齐所有问题

不要：

```text
A缺失
→ error
→ 修A
→ 下一轮才发现B
```

要：

```text
扫全合同
→ 输出missing/duplicate/ambiguous矩阵
→ 最后统一判定
```

本次S14架构审计一次通过就是正确示范。

---

# 85. Patch脚本固定经验

## 85.1 事务模板

固定：

```text
1 pure selftest
2 semantic preflight
3 candidate source QA
4 production-equivalent Harness
5 byte-identical scratch
6 scratch apply
7 scratch postassert
8 scratch save once
9 scratch close/reload
10 persistence postassert
11 formal whole-file backup
12 formal re-preflight
13 formal apply
14 formal postassert
15 formal save exactly once
16 formal close/reload
17 persistence postassert
18 result/manifest
```

---

## 85.2 Harness必须调用正式同一个builder

过去错误：

```text
Harness手工搭一个类似结构
正式Patch用另一套builder
```

结果Harness没覆盖真实错误。

永久原则：

> production-equivalent Harness必须调用production builder（正式构造函数）。

本轮Ownership Blend就按此执行。

---

## 85.3 新Subsystem必须删除默认In1/Out1

若从库新增Subsystem：

```text
add_block(...)
```

库会自带：

```text
In1
Out1
```

正式builder固定：

```matlab
Simulink.SubSystem.deleteContents(sub)
```

再建立自己的接口。

---

## 85.4 Nx1不是普通1-D vector

MATLAB Function：

```matlab
y=zeros(13,1)
```

跨关键边界不能只看：

```text
width=13
```

而要考虑：

```text
orientation/dimensionality
```

稳妥：

```text
Nx1
→ Demux N scalar
→ Mux N
→ 经典1-D vector
```

---

## 85.5 修改向量必须追真正最后拼接层

曾经返回链失败：

```text
改了前级Mux
```

但真正final append在后面。

以后：

```text
从最终Memory/OpWrite反向追
```

不按名字猜“这个Mux大概是最后一个”。

---

## 85.6 自动生成MATLAB源码必须全文件QA

重点扫：

- `fprintf('`跨行；
- `error('`跨行；
- `sprintf('`跨行；
- bare `&&/||`；
- 函数名；
- 括号；
- 重复helper；
- placeholder；
- 表项数量。

发现一种错误：

```text
扫描全文件同类
```

不能只修第一行。

---

# 86. Verifier固定经验

1. 必须和Patch分离。
2. 完全只读。
3. 不调用Patch helper。
4. 独立硬编码/重建期望合同。
5. Patch成功但Verifier语法错：
   ```text
   修Verifier
   ```
   不是：
   ```text
   重跑Patch
   ```
6. Verifier PASS只是结构PASS，不是Build PASS。

---

# 87. Python Target Probe固定经验

每次新Build：

```text
重新GetParametersDescription
重新GetSignalsDescription
```

旧ID一律不能继承。

参数：

```text
exact hit == 1
→ 才允许写

0或>1
→ 只报告
```

写参数：

```text
before
→ write
→ readback
→ compare
```

可逆probe必须finally恢复并readback。

---

# 88. Python Runner固定经验

## 88.1 起点

```text
人工Reset
→ Load once
→ MODEL_PAUSED @ t=0
→ 不人工Execute
→ Runner接管
```

Runner不要偷偷Reset/Load。

---

## 88.2 时间轴

物理时间：

```text
Target clock
```

Runner动作：

```text
SetPauseTime
Execute
等待Target pause
读Target clock
```

host sleep只用于轮询等待。

---

## 88.3 不自动Reset普通坏波形

普通V/f/I异常就是证据。

优先：

```text
Pause
→ 保存
```

---

## 88.4 Python负责动作，不负责最终电气判决

Runner最终状态最好：

```text
CAPTURE_COMPLETE_NO_ELECTRICAL_VERDICT
```

最终PASS：

```text
DirectMAT
```

---

# 89. DirectMAT数据分析固定经验

1. 永远先读原MAT形状和时间轴。
2. 第一行通常是Target Time，但每组必须实际确认。
3. 不补零。
4. 不把不同采样率强行拼成等间隔。
5. 时间缺口不是0。
6. 事件时序与滤波延迟分开。
7. 峰值只能说“记录采样点峰值”，不能冒充开关瞬时真实峰值。
8. 先根据模型当前schema（通道表）解码，再算指标。
9. 每轮数据分析后生成Markdown记录。
10. 稳定必须看：
   - 均值；
   - 标准差；
   - 极值；
   - 趋势；
   - 频谱；
   - 控制内部状态；
   - 事件先后；
   而不是只看截图“好像平”。

---

# 90. 关于“长期稳定”的默认判断

不要再把：

```text
1~5 s暂态恢复
```

写成：

```text
长期稳定
```

本项目已经真实出现：

```text
15 s看着不错
30 s重新摆动
```

所以：

- 短时暂态；
- 数十秒持续孤岛；
- 分钟/小时级运行；

必须分级。

---

# 91. 关于GFM/GFL数量比的默认判断

禁止：

```text
别人3 GFM + 6 GFL
→ 所以必须1:2
```

数量不是充分指标。

真正应检查：

```text
ESS1构网容量
短时电流能力
调制度
P/Q余量
网络阻抗
GFL总功率
GFL PLL/功率环
运行点
```

---

# 92. 当前不应该做的事情

- 不把ESS2改成第二GFM作为默认修复；
- 不直接复制ESS2恢复到PV/EV；
- 不直接把GammaP全局改0；
- 不盲调Power PI Kp/Ki；
- 不重新启F21/F22/F24旧切换机制；
- 不再加G31；
- 不新造第二套长期孤岛Coordinator；
- 不把Stateflow迁移和控制修复绑同一轮；
- 不提前开Secondary；
- 不提前写正式Runner；
- 不再做一轮同类型S14架构审计。

---

# 93. 当前可以做的下一步只有一个

用户本地MATLAB运行：

```matlab
result = PATCH_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1;
```

如果Patch完整PASS，再运行：

```matlab
result = VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1;
```

如果Verifier返回：

```text
PASS_READY_FOR_RTLAB_REBUILD
```

再：

```text
RT-LAB Rebuild All
```

然后把：

- Patch日志/RESULT；
- Verifier结果；
- RT-LAB Build输出；

发回新窗口。

**只有这三项都完成，才进入下一轮Python Runner。**

---

# 94. 如果Patch报错，新窗口怎样处理

先看发生在哪一层：

## 94.1 preflight阶段

含义：

```text
当前模型与本次审计基线发生语义漂移
```

不要强行改Patch绕过。

需要看：

- 哪个核心SHA变了；
- 哪条线变了；
- 用户是否手动改过。

---

## 94.2 Harness阶段

正式模型还没改。

问题属于：

- 候选MATLAB Function语法；
- 新Simulink标准块参数名；
- 端口推导；
- builder。

修脚本即可。

不需要回滚。

---

## 94.3 scratch阶段

正式模型仍没改。

修Patch。

不需要正式rollback。

---

## 94.4 formal save之前

正式磁盘文件还没被本Patch保存。

日志会明确：

```text
NO ROLLBACK NEEDED
```

不要人工拿旧模型覆盖。

---

## 94.5 formal save以后

Patch自己会：

```text
whole-file backup
→ byte-for-byte rollback
```

检查SHA。

新窗口先看日志，不要再额外乱恢复。

---

# 95. 如果自动脚本再次遇到不擅长的连接

永久原则：

> 不为了“脚本全自动”而冒险。

以下情况：

- SPS物理节点；
- 多分支守恒端口；
- 模糊库块；
- 不能唯一识别的线；
- 目标端口连接图复杂且无法证明删除只影响一个branch；

直接：

```text
停止
→ 告诉用户具体位置
→ 说明要手动断哪条、接哪条
→ 用户截图确认
→ 后续脚本只读核对
```

之前breaker-inner measurement已经证明这种分工更可靠。

---

# 96. 文件版本纪律

每次只认：

```text
模型名
+
路径
+
当前关键源码
+
关键连接
+
Build记录
+
运行manifest
+
MAT
```

不要只认：

```text
文件名
```

也不要只认：

```text
raw SHA
```

raw SHA只是provenance。

---

# 97. 术语与历史误名提醒

`EV1_inv`：

> 在SS_Slave2中其实属于ESS2变流器端测量，不是EV1。

`EV1_LV_Meas`：

> 这里其实属于ESS2母线侧测量，不是EV1。

以后任何解释都要说真实物理身份，不能被历史名称带偏。

---

# 98. 新窗口接手时禁止出现的典型错误回答

不要：

```text
可能再等久一点state4就会进state5
```

这个早已被旧数据否定，而且后面state5已经真实跑通。

不要：

```text
可能ESS1自己不会建网
```

已有正证据。

不要：

```text
可能就是旧26Hz
```

已被Stage桥接实验压掉99.9%。

不要：

```text
1 GFM + 5 GFL肯定不行
```

无理论依据。

不要：

```text
把ESS2改GFM就好了
```

没有证据。

不要：

```text
直接把所有健康门、回退、二次协调、五设备恢复一起加
```

这样又失去因果可解释性。

---

# 99. 新窗口应该怎样回答用户“现在到底是什么问题”

标准简洁表述：

> **ESS2零功率真实并回已经解决。当前问题是旧S14与正常孤岛Coordinator在首次功率承担阶段控制权和时间尺度混在一起：正常目标提前累积、Alpha再开放、Power PI同时追移动目标。当前R1 Patch把这些拆开，先验证固定-0.005 pu真实工作点，再在同一轮里平滑交给正常Coordinator的一次协调。**

---

# 100. 新窗口应该怎样理解“当前Patch是否最终完美黑启动”

不是。

当前R1完成的是：

```text
ESS1
+
ESS2第一台恢复样机
+
固定小功率
+
平滑正常协调接管
```

后续还需要：

- Secondary（二次频率/电压恢复）；
- ESS1真实动态余量；
- PV1；
- PV2；
- EV1；
- EV2；
- 每台Local Restore（本地恢复）；
- 全局资源选择；
- 最终六机长期稳定；
- 重同步到上级电网。

但当前R1必须先通过，否则没有资格向后复制。

---

# 101. 最终冻结状态

## 已证明

```text
ESS1 dead-bus formation PASS
ESS2 GFL Stage0→1→2 bridge PASS
ESS2 breaker synchronization PASS
ESS2 real breaker close PASS
state4 real-current loop PASS
state5 connected-zero PASS
zero-power long hold PASS
old ~26Hz mode caused by wrong Stage/VFF chain CLOSED
R7 failure boundary = power pickup
```

## 当前脚本已完成但未运行

```text
PATCH_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m
VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m
STATIC REVIEW = PASS
```

## 下一道硬门

```text
用户本地Patch
→ Verifier
→ RT-LAB Rebuild All
```

## 下一项物理问题

```text
固定 -0.005 pu
到底能不能稳定？
```

若能：

```text
同一轮继续beta平滑接管
→ primary correction慢开启
```

若不能：

```text
转底层Power PI / Current Loop / GFM-GFL稳定性
```

---

# 102. 当前正式文件索引

| 文件 | 性质 | SHA256 |
|---|---|---|
|`PATCH_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m`|正式改模Patch（改模脚本）|`bfb0ee63df58c709e371ae1028c3e8300d4a46874717f9d8146d45de645b318c`|
|`VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1.m`|独立Verifier（独立验证脚本）|`9ed90cfdbc6bd6395f11a000589338826d7785ee4cb5a9a5a8a96b79cc01b266`|
|`PATCH_VERIFY_K26_K50_S14_V2_ESS2_PICKUP_HANDOVER_R1_STATIC_REVIEW.txt`|容器侧静态审查|`2759a69eaeb5b9fe75422a3ba5c7828e3958c5e347ebd2663c5c95c924f12523`|
|`K26_K50_CLEAN_P1`|当前正式模型|当前用户上传文件SHA=`9c6f881c...edea3`|

---

# 103. 一句话交接

> **不要再重新做“ESS2能不能接回来”的工作。当前已经把问题推进到“接回来以后怎样安全承担非零功率并无扰进入正常孤岛协调”。先运行本轮Patch（改模脚本）和Verifier（独立验证脚本），Rebuild（重新构建）通过后，下一轮只写一个完整Runner（动态试验脚本）：自动零功率并回 → 固定-0.005 pu验证 → 满足稳定时间就自动beta平滑接管 → Primary-only观察。**
