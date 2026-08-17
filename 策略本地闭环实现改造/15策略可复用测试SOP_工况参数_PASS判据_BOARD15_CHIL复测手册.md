# K26_V5 LOCAL15（本地15策略闭环）｜15策略可复用测试SOP（标准操作流程）与工况设计方法手册

> **用途**：把本轮 S1～S15（策略1～策略15）闭环实现过程中已经验证有效的测试操作、参数修改方法、工况设计原则、日志保存方式和PASS（通过）判据整理成可长期复用的操作手册。  
> **适用阶段**：
>
> - LOCAL15（本地15策略闭环）回归测试；
> - BOARD15（板端15策略）C代码移植后的离线一致性测试；
> - Modbus TCP（工业以太网通信）真实闭环；
> - CHIL（控制器硬件在环）正式验收；
> - 后续模型版本升级后的回归测试；
> - 论文附加实验和复现实验。
>
> **核心思想**：以后不要“想起一个策略就临时设计一套测试”。应固定成：
>
> ```text
> 标准操作流程
> +
> 标准参数卡
> +
> 标准工况模板
> +
> 标准观测信号
> +
> 标准PASS判据
> ```
>
> 这样 LOCAL15（本地15策略）、BOARD15（板端15策略）和CHIL（控制器硬件在环）就可以使用同一套测试语言。

---

# 1. 为什么这套内容值得单独保存

本轮15策略测试过程中，真正有长期价值的并不只是：

```text
“最后15/15通过”
```

更重要的是我们已经形成了一套经过实际踩坑验证的测试方法。

这些经验后续会反复用到：

```text
如何只改参数、不重复Build（编译）

如何设计一个只验证单一因果链的工况

如何区分“策略在计算”
和
“策略真正获得执行权”

如何验证Router（路由器）关闭时完全透明

如何验证危险动作前先做禁止动作安全轮

如何利用Variables Table（变量表）在线改参数

如何保存MAT（MATLAB数据文件）

如何用Group28（第28采集组）追完整因果链

如何判断文件名写PASS但证据其实不足

如何把同一套工况复制到BOARD15（板端15策略）
```

所以：

> **这套15策略测试方法本身就是一个项目级可复用资产。**

---

# 2. 建议长期保存的五类内容

以后正式归档时建议固定为五个文件/目录。

```text
01_LOCAL15_15策略测试SOP.md
02_LOCAL15_15策略参数卡.md
03_LOCAL15_15策略PASS判据.md
04_MAT/
05_Waveforms/
```

其中：

## 2.1 测试SOP（标准操作流程）

保存：

```text
Build（编译）
Load（加载）
Variables Table（变量表）
Execute（运行）
Reset（复位）
MAT（MATLAB数据文件）
```

完整操作顺序。

---

## 2.2 参数卡

每个策略只写：

```text
本轮真正需要修改的参数
```

不要每轮重新写一大堆默认参数。

这样最不容易误操作。

---

## 2.3 PASS（通过）判据

每个策略明确：

```text
看哪些信号
哪些必须相等
哪些必须非零
哪些必须保持0
哪些方向必须正确
```

---

## 2.4 MAT（MATLAB数据文件）

MAT是原始事实证据。

PNG（波形图）只是MAT的可视化。

所以必须：

```text
MAT + PNG
```

一起保存。

---

## 2.5 波形图

建议每个策略至少一张主验收图。

复杂策略可额外保存补充图：

```text
S5（策略5）：
正向 + communication-only（纯通信异常）负向

S14（策略14）：
主体 + Stage3（阶段3）专项

S15（策略15）：
T0（测试0） + T1（测试1） + T2（测试2）
```

---

# 3. LOCAL15（本地15策略）统一测试工作流

以后任何策略回归都优先按照下面流程。

---

## 3.1 第一步：确认模型是正确冻结版本

当前推荐冻结基线：

```text
K26_V5_LOCAL15_FINAL_FROZEN_20260817
```

不要直接在唯一正式冻结模型上随意改结构。

推荐：

```text
冻结模型
↓
另存测试副本
↓
在副本上操作
```

---

## 3.2 第二步：结构不变时，不重新Build（编译）

如果只是修改：

```text
CFG15_*（LOCAL15配置参数）
CFG_AA_*（原策略参数）
PV_profile_pu（光伏可用功率曲线）
```

这些 Tunable（运行时可调）参数：

```text
不需要重新Build
```

正确：

```text
Build一次
↓
Load
↓
Variables Table
↓
在线改参数
```

错误：

```text
每改一次阈值
→ Rebuild All（全部重新编译）
```

---

## 3.3 第三步：Load（加载）后再设置测试参数

Reset（复位）或重新Load以后：

```text
参数会回到模型默认值
```

所以每轮测试：

```text
Load
↓
确认默认值
↓
只修改本轮真正需要改的参数
```

---

## 3.4 第四步：Variables Table（变量表）开启 Auto Apply（自动应用）

正式测试建议：

```text
Auto Apply（自动应用） = ON
```

这样运行过程中修改参数后：

```text
参数立即发送到Target（目标机）
```

无需额外Apply。

---

## 3.5 第五步：Execute（运行）后按工况时间点修改参数

测试操作要区分两类参数。

### A. Execute前设置

例如：

```text
CFG15_MASTER_ENABLE（LOCAL15总使能）
CFG15_CONTROL_SOURCE（控制来源）
CFG15_EXEC_Sxx（策略执行许可）
CFG15_P_OBJECTIVE_MODE（有功主目标模式）
```

这些决定整轮测试架构。

---

### B. Execute过程中修改

用于制造工况。

例如：

```text
PV_profile_pu(6)
0.65 → 0.95

CFG_AA_uv_threshold_pu
0.88 → 1.10

CFG_AA_v_nom_V
10000 → 20000
```

这些用于产生明确触发事件。

---

## 3.6 第六步：实际时间以MAT记录为准

人工在：

```text
“约10 s”
```

点击参数，不一定会刚好发生在10.000 s。

所以最终验收必须写：

```text
MAT实际记录：
13.923 s发生
```

而不是强行说：

```text
“10 s一定发生”
```

原则：

> **设计时间是操作计划，MAT时间才是正式证据。**

---

## 3.7 第七步：Reset（复位）后保存MAT

正式测试结束：

```text
Reset
```

让：

```text
OpWrite（目标机数据写出）
```

完整落盘。

再保存：

```text
MAT
```

不要在仍Execute时直接判断文件已经完整。

---

# 4. 测试文件统一命名建议

建议统一：

```text
SXX_策略名称_工况说明_PASS.mat
```

例如：

```text
S06_PV功率平滑_ESS充放电补偿_PASS.mat
```

PNG（波形图）：

```text
S06_PV功率平滑.png
```

如果是安全负向：

```text
S05_防孤岛_通信异常不误跳PCC负向边界_PASS.mat
```

如果是补测：

```text
S14_黑启动Stage3_PV恢复专项补测_PASS.mat
```

---

# 5. 所有策略通用的六层PASS（通过）证据链

以后判断一个策略是否真正闭环，统一看六层。

```text
第1层：
Trigger（触发条件）

第2层：
Raw Strategy Output（原策略输出）

第3层：
Execution Qualification / Arbitration
（执行资格 / 仲裁）

第4层：
Effective Command
（最终有效控制请求）

第5层：
Final Actuator Command
（最终设备执行命令）

第6层：
Plant / PCC Response
（仿真对象 / PCC响应）
```

例如S4（策略4）：

```text
PCC外送过大
↓
S4 relief（S4纠偏量）
↓
S4 active（S4真实约束激活）
↓
effective dP（最终有效有功调节量）
↓
Final Pref（最终有功参考）
↓
PCC外送受抑制
```

只有这条链成立，才叫闭环PASS。

---

# 6. 不允许采用的“假PASS”判断方式

以后禁止：

```text
文件名带PASS
→ 直接判通过
```

也禁止：

```text
raw cmd（原始命令）非零
→ 判通过
```

也禁止：

```text
selected source（请求来源）正确
但请求=0
→ 判完整通过
```

本轮已经实际遇到：

```text
S12（策略12）
source=12
但dP=0
```

所以最后必须补非零工况。

---

# 7. 可复用测试方法一：透明回归

适合：

```text
Router（路由）
Gate（门控）
Takeover（接管）
Breaker（断路器）
Mode（模式）
Fref Router（频率参考路由）
```

测试方法：

```text
新模块已经插入真实控制链
但新执行使能 = 0
```

要求：

```text
Final（最终值）
=
Legacy（原值）
```

典型：

```text
S13（阶段13）Breaker Router（断路器路由）

S14（策略14）Black Start Pref Gate
（黑启动有功参考门控）

S15（策略15）Fref Router
（频率参考路由）
```

用途：

> 证明“增加新结构本身没有破坏旧系统”。

---

# 8. 可复用测试方法二：主目标与硬约束故意冲突

适合：

```text
S1（需量）
S4（防逆流）
S11（有限外送）
```

通用设计：

```text
先用S7建立明确PCC主目标
↓
再打开硬约束
↓
制造一个数值明确的冲突
```

例如：

```text
主目标 -100 kW
约束 -50 kW
```

冲突：

```text
50 kW
```

这样可以直接检查：

```text
effective dP
-
objective dP
```

是否等于预期修正量。

---

# 9. 可复用测试方法三：正向 + 负向安全边界

适合：

```text
保护
模式切换
故障检测
```

典型S5：

```text
正向：
electrical_bad（电气异常） = 1
→ 必须跳PCC

负向：
comm_bad（通信异常） = 1
electrical_bad = 0
→ 不得跳PCC
```

只有：

```text
“该动作时会动作”
+
“不该动作时不动作”
```

同时通过，安全策略才算完整验收。

---

# 10. 可复用测试方法四：双方向测试

适合：

```text
有正负方向的控制量
```

典型S6：

```text
PV升高
→ ESS充电

PV降低
→ ESS放电
```

如果只测试一个方向：

```text
无法发现符号写反
```

所以任何双向控制优先：

```text
正向
+
反向
+
恢复
```

三段式测试。

---

# 11. 可复用测试方法五：分阶段状态机测试

适合：

```text
黑启动
恢复
分级减载
```

典型：

```text
S8：
0 → 1 → 2 → 1 → 0

S14：
Stage1 → Stage2 → Stage3 → Stage4

S15：
NORMAL
→ ISLANDED
→ RESYNC
→ NORMAL
```

要求：

> 不只看状态编号，还必须检查每个阶段对应的真实输出是否真的改变。

---

# 12. 可复用测试方法六：危险动作前先禁止危险动作

典型S15。

```text
正式同步稳定时间：
0.50 s
```

第一轮先改：

```text
999 s
```

允许：

```text
同步控制真实运行
```

但禁止：

```text
PCC自动重合
```

先证明：

```text
Fref（频率参考）调节方向正确
```

再恢复：

```text
0.50 s
```

做正式重合。

原则：

> **危险动作前先把“控制计算正确”和“执行动作正确”拆开验证。**

---

# 13. S1（策略1）需量控制｜标准复测卡

## 作用

限制：

```text
微电网最大进口功率
```

---

## Execute（运行）前关键设置

```text
CFG15_MASTER_ENABLE（LOCAL15总使能） = 1

CFG15_CONTROL_SOURCE（控制来源） = 1
→ LOCAL15

CFG15_P_OBJECTIVE_MODE（有功主目标模式） = 0

CFG15_EXEC_S07（S7执行许可） = 1

CFG_AA_tie_target_kW（联络线目标） = -100 kW
```

---

## 工况触发

打开：

```text
CFG15_EXEC_S01（S1执行许可） = 1
```

并把：

```text
CFG_AA_demand_limit_kW
（最大允许进口需量）

250
→
50 kW
```

---

## 为什么

```text
S7想进口100
S1最多允许进口50
```

制造：

```text
50 kW明确冲突
```

---

## 必看信号

```text
S1 relief（S1进口纠偏量）

S1 active（S1硬约束激活）

objective dP（主目标有功调节量）

effective dP（最终有效有功调节量）

6× Final Pref（六设备最终有功参考）
```

---

## PASS（通过）

```text
S1 active = 1

effective dP
-
objective dP
≈ +50 kW

Final Pref真实改变
```

---

# 14. S2（策略2）PCC跟踪｜标准复测卡

需要两轮。

---

## A. 单策略

```text
CFG15_EXEC_S02（S2执行许可） = 1
CFG15_EXEC_S07（S7执行许可） = 0
```

要求：

```text
selected source（请求来源） = 2

Arbiter dP（仲裁有功请求）
=
S2 dP
```

---

## B. S2 + S7联合

```text
CFG15_EXEC_S02 = 1
CFG15_EXEC_S07 = 1
```

要求：

```text
selected source = 7

duplicate guard（重复保护） = 1

S2 monitor-only（S2仅监测） = 1

Arbiter dP
=
S7 dP
```

---

# 15. S3（策略3）AVC（自动电压/无功控制）｜标准复测卡

## 作用

```text
电压偏差
→ 无功需求
→ 六台设备Qref（无功参考）
```

---

## 设置

```text
CFG15_MASTER_ENABLE = 1

CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S03（S3执行许可） = 1

CFG15_Q_SIGN_GAIN
（无功方向系数）
= +1
```

---

## 工况

建议：

```text
P主链保持稳定
```

然后制造一个明确电压偏差。

当前历史正式MAT没有保存唯一人工电压扰动值，因此未来BOARD15标准化测试可以固定：

```text
例如0.97 pu
```

但应按最终板端量纲正式冻结。

---

## PASS

```text
selected source（无功来源） = 3

Q request（无功请求）
=
Q applied（实际无功执行）

allocator valid（无功分配有效） = 1

Q saturated（无功饱和） = 0

六设备Final Qref真实非零
```

---

# 16. S4（策略4）防逆流｜标准复测卡

## 作用

限制：

```text
PCC向主网外送
```

---

## 基础

```text
S7目标：
+100 kW外送
```

---

## 触发

```text
CFG15_EXEC_S04（S4执行许可） = 1

CFG_AA_anti_reverse_limit_kW
（允许外送上限）
= 0

CFG_AA_anti_reverse_deadband_kW
（防逆流死区）
= 2
```

---

## 为什么

理论纠偏：

```text
100 - 0 - 2
≈ 98 kW
```

---

## PASS

```text
S4 active（S4约束激活） = 1

effective dP
-
objective dP
≈ -98 kW

Final Pref真实变化
```

---

# 17. S5（策略5）防孤岛｜标准复测卡

必须两轮。

---

## A. 电气异常正向

Execute前：

```text
CFG15_EXEC_S05 = 1
CFG15_EXEC_S15 = 1

CFG15_MODE_ACTUATION_ENABLE
（设备模式真实接管）
= 1

CFG15_PCC_BREAKER_ACTUATION_ENABLE
（PCC断路器真实接管）
= 1

CFG15_ISLAND_MASTER
（孤岛构网主机）
= 1
→ ESS1
```

运行中：

```text
CFG_AA_v_nom_V
（策略额定电压基准）

10000
→
20000
```

这是：

```text
判据注入
```

不是实际低电压。

PASS：

```text
electrical_bad = 1

S5_execute = 1

S15_transition = 1

island_latch = 1

PCC OPEN

ESS1 GridOn = 0
→ GFM
```

---

## B. communication-only（纯通信异常）负向

要求：

```text
V/f正常
electrical_bad = 0

comm < 0.5
→ comm_bad = 1

模式/Breaker执行权限仍开
```

PASS：

```text
S5_execute = 0

S15_transition = 0

island_latch = 0

PCC保持闭合
```

---

# 18. S6（策略6）光伏平滑｜标准复测卡

## 工况入口

真正修改：

```text
PV_profile_pu(6)
（光伏可用功率曲线第6点）
```

不要改：

```text
PCC target
```

因为S6真正读的是：

```text
Ppv_max
```

---

## 三段

```text
0.65 → 0.95
```

预期：

```text
ESS充电
```

然后：

```text
0.95 → 0.55
```

预期：

```text
ESS放电
```

最后：

```text
0.55 → 0.65
```

恢复。

---

## PASS

```text
PV升：
compensation（补偿量） < 0

PV降：
compensation > 0

request = applied

unserved = 0
```

---

# 19. S7（策略7）联络线控制｜标准复测卡

设置：

```text
CFG15_EXEC_S07 = 1

CFG15_P_OBJECTIVE_MODE = 0
```

推荐同时：

```text
CFG15_EXEC_S02 = 1
```

用于去重复验证。

PASS：

```text
selected source = 7

duplicate guard = 1

S2 monitor-only = 1

Arbiter dP = S7 dP
```

---

# 20. S8（策略8）低压/低频分级减载｜标准复测卡

正常：

```text
UV threshold（低压阈值） = 0.88
UF threshold（低频阈值） = 49 Hz
```

---

## Stage1（一级）

改：

```text
UV threshold
0.88 → 1.10
```

预期：

```text
Stage = 1

shed request（减载请求）
= 50 kW
```

---

## Stage2（二级）

继续：

```text
UF threshold
49 → 51 Hz
```

预期：

```text
Stage = 2

shed request
= 100 kW
```

---

## 恢复

```text
UF 51 → 49
→ Stage2 →1

UV 1.10 →0.88
→ Stage1 →0
```

---

## PASS

```text
Stage：
0 →1 →2 →1 →0

request：
0 →50 →100 →50 →0

applied = request

unserved = 0

EV2优先向0移动
```

---

# 21. S9（策略9）削峰填谷｜标准复测卡

设置：

```text
CFG15_EXEC_S09 = 1

CFG15_P_OBJECTIVE_MODE = 1
```

关闭：

```text
S1
S4
S11
```

硬约束，避免混淆。

PASS：

```text
selected source = 9

S9 dP非零

objective dP
=
S9 dP

Final Pref真实响应
```

注意：

> 如果和S12/S13在同一个MAT中测试，只能在 `selected source = 9` 的时间段验收S9。

---

# 22. S10（策略10）周期计划｜标准复测卡

设置：

```text
CFG15_EXEC_S10 = 1

CFG15_P_OBJECTIVE_MODE = 2
```

PASS：

```text
selected source = 10

S10 target（周期计划目标）
真实进入：

target - Pcc
→ AGC
→ Final Pref
```

当前边界：

```text
现阶段是模型已有合成周期计划
```

后续如果BOARD15要求：

```text
96点计划
```

应换输入接口，不应重写后级执行链。

---

# 23. S11（策略11）自发自用/余电上网｜标准复测卡

基础：

```text
S7目标 = +100 kW
```

触发：

```text
CFG15_EXEC_S11 = 1

CFG_AA_export_limit_kW
（允许余电外送上限）
= 50
```

PASS：

```text
S11 active = 1

effective dP
-
objective dP
≈ -50 kW
```

---

# 24. S12（策略12）新能源消纳｜标准复测卡

设置：

```text
CFG15_EXEC_S12 = 1

CFG15_P_OBJECTIVE_MODE = 3
```

必须制造：

```text
非零新能源吸纳需求
```

不能只：

```text
selected source = 12
```

但：

```text
dP = 0
```

PASS：

```text
S12 dP非零

selected source = 12

objective dP = S12 dP

Final Pref向增加充电/吸收方向变化
```

当前历史正式非零结果：

```text
最低约 -105 kW
```

---

# 25. S13（策略13）多目标协调｜标准复测卡

设置：

```text
CFG15_EXEC_S13 = 1

CFG15_P_OBJECTIVE_MODE = 4
```

PASS：

```text
selected source = 13

S13 dP非零

objective dP = S13 dP

Final Pref真实响应
```

边界：

```text
证明多目标请求真实执行
```

不是：

```text
证明全局数学最优
```

---

# 26. S14（策略14）黑启动｜标准复测卡

必须三轮。

---

## A. Gate（门控）透明回归

```text
CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE
（黑启动有功参考分阶段门控）
= 0
```

要求：

```text
gated Pref（门控后的有功参考）
=
aux Pref（门控前辅助有功参考）
```

---

## B. 四阶段主体

设置：

```text
CFG15_MASTER_ENABLE = 1

CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S14 = 1

CFG_AA_blackstart_enable
（原黑启动使能）
= 1

CFG15_MODE_ACTUATION_ENABLE = 1

CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1

CFG15_BLACKSTART_PREF_SEQUENCE_ENABLE = 1

CFG15_BLACKSTART_MASTER
（黑启动构网主机）
= 1
→ ESS1
```

要求：

```text
executed mode（真实执行模式）
= 4

PCC OPEN

ESS1 GridOn = 0
→ GFM

Stage：
1 →2 →3 →4
```

---

## C. Stage3（阶段3）专项

必须证明：

```text
Stage3：
PV恢复
EV仍为0

Stage4：
EV才恢复
```

当前正式证据：

```text
Stage3：
PV1/PV2 ≈ 0.65 pu
EV1/EV2 = 0
```

---

# 27. S15（策略15）受控并离网与重同步｜标准复测卡

必须三轮。

---

## T0（测试0）：透明回归

设置：

```text
CFG15_MODE_ACTUATION_ENABLE = 0

CFG15_PCC_BREAKER_ACTUATION_ENABLE = 0

CFG15_S15_RECOVERY_REQUEST
（恢复请求）
= 0
```

PASS：

```text
mode = 0

PCC闭合

Recovery state（恢复状态） = 0

Fref trim（频率参考微调） = 0

ESS Final Fref
=
Legacy Fref
```

---

## T1（测试1）：同步方向，禁止合闸

设置：

```text
CFG15_MASTER_ENABLE = 1

CFG15_CONTROL_SOURCE = 1

CFG15_EXEC_S05 = 1

CFG15_EXEC_S15 = 1

CFG15_MODE_ACTUATION_ENABLE = 1

CFG15_PCC_BREAKER_ACTUATION_ENABLE = 1

CFG15_ISLAND_MASTER = 1
→ ESS1

CFG15_S15_SYNC_STABLE_S
（同步稳定时间）
= 999 s
```

触发孤岛：

```text
CFG_AA_v_nom_V
10000 → 20000
```

恢复判据：

```text
20000 →10000
```

再：

```text
CFG15_S15_RECOVERY_REQUEST
0 →1
```

PASS：

```text
mode：
0 →3 →5

PCC始终OPEN

ESS1：
Final Fref = Legacy + trim

ESS2：
Final Fref = Legacy

无自动重合
```

---

## T2（测试2）：完整恢复

和T1相同，但：

```text
CFG15_S15_SYNC_STABLE_S = 0.50 s

CFG15_S15_RECLOSE_HOLD_S = 0.20 s
```

同步阈值：

```text
CFG15_S15_SYNC_DV_MAX_PU
（最大电压差）
= 0.10

CFG15_S15_SYNC_DF_MAX_HZ
（最大频差）
= 0.20

CFG15_S15_SYNC_DTHETA_MAX_DEG
（最大相角差）
= 10°
```

PASS：

```text
NORMAL
→ ISLANDED
→ RESYNCHRONIZATION
→ NORMAL

PCC：
CLOSE → OPEN → CLOSE

同步：
连续满足约0.50 s

重合：
保持约0.20 s

island latch：
1 →0

ESS1：
GFM → GFL
```

---

# 28. S5 / S8 / S15测试中的“判据注入”必须保留备注

以后复用时必须明确：

```text
改变 Vn（额定电压基准）
改变UV/UF阈值
```

属于：

```text
criterion injection
（判据注入）
```

目的：

```text
验证策略逻辑与执行链
```

不是：

```text
真实10 kV低电压故障
```

所以：

```text
LOCAL15逻辑验收
≠
物理故障型式试验
```

真正CHIL以后若要验证物理鲁棒性，应另外做：

```text
真实电压跌落
真实频率扰动
真实PCC切换
```

---

# 29. BOARD15（板端15策略）如何直接复用这套流程

BOARD15阶段不要重新发明测试。

正确：

```text
同样的参数
同样的事件顺序
同样的PASS判据
```

先比较：

```text
LOCAL15
vs
BOARD15
```

---

## 第一层：离线Golden Vector（黄金输入输出向量）

同一输入：

```text
LOCAL15 MATLAB/Simulink
vs
BOARD15 C
```

比较：

```text
策略状态
主目标
硬约束
6 Pref
6 Qref
模式请求
Breaker请求
```

---

## 第二层：Modbus真实闭环

```text
RT-LAB
→ 测量
→ BOARD15
→ 命令
→ RT-LAB
```

再跑同一15策略测试卡。

---

## 第三层：CHIL（控制器硬件在环）

继续复用同一工况。

这样最终形成：

```text
LOCAL15
→ BOARD15离线
→ BOARD15 Modbus闭环
→ CHIL
```

同一套验收语言。

---

# 30. 推荐建立“测试Case卡片”制度

后续每个策略都可以固定一张Case卡。

模板：

```text
Case ID（用例编号）：

策略：

测试目标：

起始条件：

Execute前修改参数：

Execute中修改参数：

修改时间：

为什么这样设置：

预期因果链：

必看信号：

PASS判据：

FAIL判据：

对应MAT：

对应PNG：

边界说明：
```

这样以后任何人都能照卡复测。

---

# 31. 建议每次测试保存“计划时间”和“实际时间”

例如：

```text
计划：
15 s改参数

实际MAT：
18.546 s发生
```

两者都保存。

原因：

```text
人工操作有延迟
```

而正式论文/报告应使用：

```text
MAT实际发生时间
```

---

# 32. 建议未来增加一个自动Test Harness（测试框架），但不是当前必须项

目前人工Variables Table已经完成LOCAL15验收。

BOARD15以后为了重复性，可以进一步写自动测试脚本：

```text
加载模型
↓
初始化参数
↓
按Target Time自动修改参数
↓
运行
↓
自动保存MAT
↓
自动判PASS
↓
自动生成PNG
```

但是：

> **不要现在为了“自动化”重新改动已经冻结的LOCAL15模型。**

应该在：

```text
独立测试脚本
```

中做。

---

# 33. 测试脚本必须遵守的模型命名规则

如果脚本需要访问当前Simulink模型：

```matlab
mdl = bdroot(gcs);
```

不要：

```matlab
mdl = 'K26_V5';
```

避免：

```text
模型另存以后脚本失效
```

---

# 34. 结构脚本的额外检查规则

本轮实际踩过：

```text
Function有27个输入
但第27输入没有接线
```

所以结构脚本完成后必须检查：

```text
Block存在

端口数正确

每一个输入都Driven（有真实驱动）

GotoTag（信号标签）正确

没有断开共享Branch（共享支路）

目标Mux端口正确

Update Diagram（模型更新）通过

RT-LAB Build（实时编译）通过
```

---

# 35. Group28（第28采集组）为什么必须继续保留

当前Group28最终有：

```text
292个诊断标量
```

覆盖：

```text
请求
仲裁
Candidate
u_commit
u_applied
Final Pref
Qref
Mode
Breaker
Black Start
Recovery
```

因此BOARD15以后建议：

> 不要删除Group28。

反而可以继续增加：

```text
BOARD15输入回显
BOARD15输出回显
LOCAL15-BOARD15差值
```

作为一致性比较层。

---

# 36. 当前最值得长期保存的测试设计经验

最终可以压缩成十条。

```text
1.
参数能在线改
就不要重新Build

2.
一次只验证一条因果链

3.
先透明
再真实接管

4.
危险动作
先禁止执行验证方向

5.
保护策略
正向 + 负向都要测

6.
双向控制
两个方向都要测

7.
硬约束
用明确冲突测试

8.
状态机
不能只看state数字
还要看对应真实输出

9.
文件名PASS
不能代替MAT证据

10.
LOCAL15工况
应直接复用到BOARD15和CHIL
```

---

# 37. 当前最推荐保存的“15策略测试资产包”

最终建议归档：

```text
LOCAL15_15_STRATEGY_TEST_BASELINE/
│
├─ 00_README.md
│
├─ 01_15策略测试SOP.md
│
├─ 02_15策略参数卡.md
│
├─ 03_15策略PASS判据.md
│
├─ 04_Group28信号映射.md
│
├─ 05_波形逐图讲解.md
│
│
├─ MAT/
│  ├─ S01_...
│  ├─ S02_...
│  └─ ...
│
├─ Waveforms/
│  ├─ S01_...
│  ├─ S02_...
│  └─ ...
│
└─ Scripts/
   ├─ PLOT_LOCAL15_15_STRATEGIES_ALL.m
   └─ 后续自动测试脚本
```

这套包以后就是：

> **LOCAL15 Golden Test Baseline（本地15策略黄金测试基线）。**

---

# 38. 最终建议

值得保存，而且建议把它当成项目正式资产，而不是个人笔记。

因为后续：

```text
BOARD15
C代码移植
Modbus联调
CHIL
模型版本升级
问题回归
```

都会反复问同一个问题：

> **“这个策略原来到底怎么测才算对？”**

如果现在不整理，以后只能重新翻几十份MAT和聊天记录。

如果现在冻结这套SOP：

```text
以后任何新版本
只需要：
同工况 → 同信号 → 同判据
```

就能快速判断：

```text
有没有回归
板端有没有移植错
新模型有没有破坏旧功能
```

因此，这套15策略测试SOP应当和：

```text
最终冻结SLX
正式PASS MAT
15张PNG
```

处于同一级别长期保存。
