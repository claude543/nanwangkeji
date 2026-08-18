# BOARD15 C迁移 C01｜`strategy15_core.c/.h` 原始15策略判断层转换与验证设计 V0.1

> **日期**：2026-08-18  
> **C01定位**：完整BOARD15 C迁移的第一块单元，不是最终板端版本。  
> **唯一源基准**：GitHub `算法代码/Advanced_Strategy_Core1.m` 当前main版本，函数为 `Advanced_Strategy_Core`。  
> **目标**：先证明原始S1～S15判断层从MATLAB翻译为C以后，`status[15] / alarm[15] / metric[15] / cmd[15]` 的数学行为没有被改坏，再进入后续Normalizer、P目标/约束、AGC、S6/S8、Q、Mode、S14、S15的C迁移。

---

# 1. C01这一步具体转换什么

只转换：

```text
Advanced_Strategy_Core
```

也就是原15策略共同判断Function。

输入仍代表：

```text
t
PCC P/Q/V/f
ESS1/ESS2 SOC
PV1/PV2当前策略输入
通信健康语义
原策略enable
以及原CFG_AA参数
```

输出：

```text
status[15]
alarm[15]
metric[15]
cmd[15]
```

---

# 2. C01明确不做什么

本轮不转换：

```text
Request Normalizer
P Objective / Constraint
Arbitrated Baseline AGC
Execution Mapper
S6/S8真实执行器
S3 Q Allocator
Mode Manager
GridOn/Droop/Breaker执行
S14 Black Start Pref Gate
S15重同步/重合闸/Fref
Command Source Router
Execution Fault Injector
```

原因：

> C01只验证“15个策略自己判断是否正确”，后面的闭环执行链属于C02～C08。

---

# 3. 为什么C01必须保持“源代码等价”

C01的第一目标不是优化原策略，也不是修正算法，而是：

```text
MATLAB源算法
↓
逐行语义翻译
↓
C
```

这样以后如果完整BOARD15出现差异，可以明确：

```text
不是S1～S15判断层翻译错了
```

---

# 4. 当前源算法实际保存的状态

原Function persistent：

```text
last_t
demand_avg
peak_power
pv_prev
self_use_energy
export_energy
pv_energy
curtailed_energy
black_state
switch_timer
```

C01全部显式放进：

```c
Strategy15State
```

不使用隐藏`static`可变状态。

这样后续Design05的reset/reconnect/状态管理能够由上层明确控制。

---

# 5. C01的重要边界：SOURCE-EQUIVALENT和BOARD-RUNTIME-SAFE不是同一件事

C01首先复制原始数学语义。

例如原代码：

```text
en <= 0.5
→ last_t = t
→ 输出全0
```

C01保留这一行为。

原S14：

```text
t > 20 / 40 / 60
```

推动raw `black_state`。

C01也保留。

但是BOARD15最终真实黑启动执行不会直接依赖这个绝对时间状态推进，而是由后续：

```text
black_start.c
```

根据Design05冻结的“成功发布 + 执行确认 + stage-relative time”规则实现。

同理：

```text
原S15 switch_timer
```

只是原策略判断层的raw状态；

真正电气重同步的：

```text
recovery_state
sync_timer
reclose_timer
```

属于后续`resynchronization.c`。

因此：

> C01必须保留原S14/S15输出用于15策略兼容和诊断，但BOARD15的真实S14/S15执行状态由后续模块独立管理。

---

# 6. C01字段语义

`Strategy15Input`：

```text
time_s
pcc_p_kw
pcc_q_kvar
pcc_v_rms_v
pcc_freq_hz
ess1_soc
ess2_soc
pv1_available_kw
pv2_available_kw
comm_ok
evaluate_enable
```

PCC符号：

```text
+ = 微电网向上级电网外送
- = 微电网从上级电网进口
```

PV1/PV2：

当前K26_V5策略层实际接入的是：

```text
Ppv_max1_kW
Ppv_max2_kW
```

因此C01名称使用：

```text
pv1_available_kw
pv2_available_kw
```

避免误解成PV Pmeas。

---

# 7. `Strategy15Config`为什么单独存在

为了让C01可以完全独立于：

```text
Modbus
Controller Adapter
Runtime Config地址
```

做数学单元测试。

后续`project15_core`只需要把：

```text
ControllerConfig
```

映射给：

```text
Strategy15Config
```

即可。

---

# 8. C01 PASS必须验证哪些东西

## 8.1 初始化

第一拍：

```text
persistent第一次建立
dt = 0
PV_prev = 当前PV1+PV2
所有能量=0
black_state=0
switch_timer=0
```

---

## 8.2 时间正常前进

测试：

```text
0
0.1
0.2
...
```

确保所有积分、滑动历史和timer一致。

---

## 8.3 时间回绕

原代码：

```text
t < last_t
```

会重新初始化persistent。

必须验证C一致。

---

## 8.4 `enable=0`

必须验证：

```text
输出四组15维全部为0
last_t仍更新
```

与源代码一致。

---

## 8.5 S1～S15逐项触发

至少覆盖：

```text
S1 进口需量越限 / 不越限
S2 PCC误差带内 / 带外
S3 高压 / 低压 / 正常
S4 外送越限 / 正常
S5 电压异常 / 频率异常 / comm异常 / 正常
S6 PV上升 / PV下降 / 无变化
S7 PCC目标偏差
S8 UV一级 / UF一级 / UV+UF二级
S9 削峰 / 填谷 / 中间
S10 不同计划时间点
S11 外送限制触发
S12 弃光风险非零
S13 不同权重组合
S14 stage 0/1/2/3/4及SOC不足失败
S15 进入切换 / 连续5 s告警 / 条件清除
```

---

# 9. 数值PASS标准

第一层：

```text
C double结果
vs
MATLAB double结果
```

建议：

```text
abs error <= 1e-9
```

对于0/1、整数状态：

```text
必须完全一致
```

第二层、也是最终更强的标准：

> 后续经过BOARD15真实scale/round/寄存器编码后，所有对应量必须完全一致，不能出现不同整数寄存器值。

---

# 10. C01输出文件

本轮生成：

```text
strategy15_core_BOARD15_C01_V0_1.h
strategy15_core_BOARD15_C01_V0_1.c
```

两者是第一版源等价实现。

---

# 11. 本轮不会马上宣称C01 FINAL PASS

原因：

当前环境没有直接运行用户的MATLAB R2023b原函数。

本轮可以完成：

```text
源代码逐行审计
C99编译
独立数值镜像测试
```

但正式C01最终冻结前，仍应在用户MATLAB环境使用：

```text
同一输入CSV
→ 原Advanced_Strategy_Core
→ Golden output

同一输入CSV
→ C runner
→ C output

逐项compare
```

得到真实MATLAB/C交叉验证。

所以当前状态应写：

```text
C01 IMPLEMENTATION CANDIDATE
实现候选
```

而不是提前写：

```text
C01 FINAL PASS
```

---

# 12. C01通过以后才进入C02

C02只做：

```text
Request Normalizer
P Objective Selection
S1/S4/S11 Constraint Manager
```

并利用已经确认正确的C01输出作为输入。

这样问题定位边界始终清楚。
