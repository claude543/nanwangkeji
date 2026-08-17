# K26_V5 / RT-LAB 在线调参设计与复用规范
## —— 从 LOCAL15 15策略闭环测试中总结出的 Tunable（运行时可调）参数设计方法

> **用途**：总结本次 LOCAL15（本地15策略闭环）实现过程中，哪些参数已经证明可以在 RT-LAB（实时仿真平台）中在线修改，以及以后如果希望一个新模块也支持“Build（编译）一次、Load（加载）后反复在线改参数”，模型结构应该怎样设计、参数应该放在哪里、怎样接线、怎样验证可调性、哪些修改不能靠在线调参完成。  
>
> **适用对象**：
>
> - K26_V5 / LOCAL15（本地15策略闭环）后续维护；
> - BOARD15（板端15策略）联调前模型侧参数设计；
> - CHIL（控制器硬件在环）测试；
> - 新增保护、控制、状态机、阈值和测试工况；
> - 以后任何希望通过 RT-LAB Variables Table（变量表）在线调节的 Simulink（仿真模型）参数。
>
> **本项目已经实际验证的核心工作流**：
>
> ```text
> Build（编译）一次
> ↓
> Load（加载）
> ↓
> Variables Table（变量表）
> ↓
> 在线修改 Tunable Parameter（运行时可调参数）
> ↓
> Target（目标机）立即采用新值
> ↓
> Execute（运行）过程中继续修改
> ↓
> 无需重新Build
> ```

---

# 1. 先给出结论：什么样的参数最适合做 RT-LAB 在线调参

本项目已经证明，最稳妥、最容易维护的在线调参方式不是把大量数值写死在算法代码里，而是建立：

```text
Parameter Panel（参数面板）
↓
Constant（常数块）
↓
Goto（信号发布）
↓
From（信号读取）
↓
控制Subsystem（子系统） / MATLAB Function（MATLAB函数块）
```

例如：

```text
CFG15_S15_SYNC_STABLE_S
（S15同步条件连续稳定时间）
```

不要只在 `AA15_S15_Recovery_Core（S15恢复核心）` 代码内部写：

```matlab
Tsync = 0.5;
```

而应当设计成：

```text
AA15_CFG15_PANEL
（15策略配置面板）
│
├─ Constant：
│  CFG15_S15_SYNC_STABLE_S
│
↓
global Goto：
CFG15_S15_SYNC_STABLE_S
│
↓
From
│
↓
AA15_S15_Recovery_Manager
（S15恢复管理器）
│
↓
Recovery Core input
（恢复核心输入）
```

于是：

```text
0.50 s
```

可以在 RT-LAB Load（加载）以后直接改成：

```text
999 s
```

而不需要重新Build（编译）。

这正是 S15 T1（同步方向验证、禁止重合闸）能够快速完成的基础。

---

# 2. 在线调参真正依赖什么

必须分清三件事。

---

## 2.1 第一层：模型级 Tunable（运行时可调）设置

Stage00（阶段00）锁定：

```text
DefaultParameterBehavior = Tunable
```

中文：

> 模型中的参数默认按照“可在生成代码后继续修改”的方式处理。

同时设置：

```text
ParameterTunabilityLossMsg = error
```

中文：

> 如果一个本来希望在线调节的参数在代码生成或优化以后失去可调性，不要静默继续，而是直接报错。

所以：

```text
DefaultParameterBehavior = Tunable
```

是在线调参的模型级基础。

---

## 2.2 第二层：参数必须真正成为实时代码里的可调参数

一个参数仅仅“在MATLAB工作区里有名字”并不等于：

```text
Target（目标机）一定可以在线改
```

本项目采用的可靠方法是：

```text
明确的 Constant（常数块）
↓
进入实时代码
↓
RT-LAB Variables Table（变量表）能够识别
```

然后实际进行：

```text
Load
↓
1 → 5
```

测试。

---

## 2.3 第三层：参数必须真正进入算法执行路径

即使一个参数在 Variables Table（变量表）里能改，也不代表：

```text
算法真的用了它
```

因此还必须有：

```text
Parameter
↓
Control Core（控制核心）
```

真实连接。

最好还增加：

```text
Parameter Echo（参数回显）
或
Diagnostic（诊断量）
```

写入 MAT（MATLAB数据文件）。

这样才能证明：

```text
PC端改了参数
↓
Target端收到
↓
算法真正读取
```

---

# 3. 本项目已经实际验证在线调参成功的结构

Stage01（阶段01）增加：

```text
SM_Master
└─ AA15_CFG15_PANEL
   （15策略统一配置面板）
```

它不是普通：

```text
输入
→ 算法
→ 输出
```

Subsystem（子系统）。

它的职责是：

> **集中发布所有 LOCAL15（本地15策略闭环）的运行配置。**

---

# 4. `AA15_CFG15_PANEL（15策略配置面板）` 内部怎样设计

每一个参数采用：

```text
Constant（常数块）
↓
global Goto（全局信号发布）
```

例如：

```text
CFG15_MASTER_ENABLE
（LOCAL15总使能）
Constant

↓
GOTO_CFG15_MASTER_ENABLE

↓
GotoTag：
CFG15_MASTER_ENABLE
```

其它子系统中：

```text
From：
CFG15_MASTER_ENABLE

↓
Mode Manager / Router / Core
（模式管理器 / 路由器 / 控制核心）
```

---

# 5. 为什么参数面板没有普通输入和输出

`AA15_CFG15_PANEL（15策略配置面板）`：

```text
Inport（传统输入端口） = 0
Outport（传统输出端口） = 0
```

因为它通过：

```text
global Goto（全局信号发布）
```

把参数送到整个 SM_Master（主任务模型）。

这样避免：

```text
42个参数
↓
42根长线
↓
从模型顶层拉到各个控制Subsystem
```

造成模型完全无法阅读。

所以参数发布架构是：

```text
Parameter Panel（参数面板）
     │
     ├─ CFG15_MASTER_ENABLE
     ├─ CFG15_EXEC_S01
     ├─ CFG15_EXEC_S02
     ├─ ...
     ├─ CFG15_MODE_ACTUATION_ENABLE
     ├─ CFG15_S15_SYNC_STABLE_S
     └─ ...
           ↓
       global Goto
           ↓
───────────────────────────────
其它Subsystem中的From按名称读取
───────────────────────────────
```

---

# 6. `Goto / From（标签连线）` 和在线调参是什么关系

必须明确：

> **Goto / From（标签连线）本身并不会让参数变成可调。**

真正让参数可调的是：

```text
模型参数被保留为 Tunable（运行时可调）
+
RT-LAB代码生成后能够访问它
```

Goto / From 的作用只是：

> **把已经可调的参数值干净地分发到模型不同位置。**

因此：

```text
Tunable（可调性）
=
参数/代码生成属性

Goto / From
=
模型内部信号组织方式
```

二者不能混为一件事。

---

# 7. Constant（常数块）为什么是当前最推荐的在线参数入口

本项目 Stage01（阶段01）实际采用的参数 Constant（常数块）：

```text
SampleTime（采样时间） = inf

Data type（数据类型） = double
```

其中：

```text
SampleTime = inf
```

不是说参数“永远不更新”。

它表示：

> 这个块不是一个按照100 μs周期不断变化的动态信号源，而是一个运行参数。

RT-LAB在线修改它以后：

```text
参数值会更新
```

但它并不需要像普通动态信号一样：

```text
每100 μs重新计算一个新值
```

---

# 8. 本项目已经做过的可调性实证

Stage01（阶段01）专门设计：

```text
CFG15_PARAM_PROBE
（参数可调性探针）
```

默认：

```text
1
```

Build（编译）以后：

```text
Load
↓
Variables Table
↓
CFG15_PARAM_PROBE
1 → 5
```

不重新Build。

然后 Target（目标机）正式记录：

```text
5
```

这证明：

```text
PC端参数修改
↓
RT-LAB Target端采用新值
```

这一链已经真实打通。

所以当前：

```text
Build一次
→ Load后在线改CFG15参数
```

不是理论设想，而是已经做过实机验证。

---

# 9. 为什么还增加 `AA15_CFG15_TUNABILITY_MONITOR（参数可调性监视器）`

只改：

```text
CFG15_PARAM_PROBE
```

可以证明一个参数能调。

但项目以后有几十个：

```text
CFG15_*
```

所以 Stage01（阶段01）又建立：

```text
AA15_CFG15_TUNABILITY_MONITOR
（15策略参数可调性监视器）
```

它读取：

```text
全部CFG15参数
```

计算：

```text
checksum（参数校验和）
```

并发布：

```text
AA15_CFG15_CHECKSUM
```

作用不是控制Plant（仿真对象）。

而是：

> 帮助确认这些配置参数确实已经进入实时代码和诊断链，而不是只存在于模型画面上。

以后新增重要在线参数，也可以继续采用：

```text
参数回显
或
checksum
```

的方式进行可调性验收。

---

# 10. 当前已验证的在线调参类型一：0/1 Enable（使能开关）

这是最适合在线调的参数。

例如：

```text
CFG15_MASTER_ENABLE
（LOCAL15总使能）

CFG15_EXEC_S01
（策略1执行许可）

CFG15_EXEC_S03
（策略3执行许可）

CFG15_EXEC_S14
（策略14执行许可）

CFG15_MODE_ACTUATION_ENABLE
（设备模式真实接管使能）

CFG15_PCC_BREAKER_ACTUATION_ENABLE
（PCC断路器真实接管使能）
```

典型用途：

```text
0
→ 模块存在但不真实执行

1
→ 允许真实执行
```

这种设计特别适合：

```text
透明回归
↓
真实接管
```

两阶段测试。

---

# 11. 当前已验证的在线调参类型二：Mode（模式选择）

例如：

```text
CFG15_CONTROL_SOURCE
（控制来源）
```

编码：

```text
0 = LEGACY_V5A
    （原V5-A控制）

1 = LOCAL15
    （本地15策略）

2 = BOARD15
    （未来板端15策略）
```

以及：

```text
CFG15_P_OBJECTIVE_MODE
（有功主目标模式）
```

编码：

```text
0 = S7联络线
1 = S9削峰填谷
2 = S10周期计划
3 = S12新能源消纳
4 = S13多目标协调
```

这类：

```text
整数编码参数
```

非常适合在线切换。

---

# 12. 当前已验证的在线调参类型三：Threshold（阈值）

例如：

```text
CFG_AA_demand_limit_kW
（最大允许进口需量）

CFG_AA_anti_reverse_limit_kW
（防逆流允许外送上限）

CFG_AA_export_limit_kW
（余电允许外送上限）

CFG_AA_uv_threshold_pu
（低压阈值）

CFG_AA_uf_threshold_Hz
（低频阈值）
```

这些参数可以直接用于制造测试工况。

例如 S8（策略8）：

```text
低压阈值：
0.88
→
1.10
```

无需重新Build。

于是正常：

```text
V ≈ 1.0 pu
```

在策略判断中变成：

```text
1.0 < 1.10
→ 低压判据成立
```

这类在线改阈值非常适合：

> **先测试策略逻辑，不先破坏真实电气对象。**

---

# 13. 当前已验证的在线调参类型四：Target（目标值）

例如：

```text
CFG_AA_tie_target_kW
（联络线有功目标）
```

可以：

```text
-100 kW
```

制造进口目标，也可以：

```text
+100 kW
```

制造外送目标。

这使 S1（需量）、S4（防逆流）、S11（余电外送）能够通过：

```text
主目标
vs
硬约束
```

故意冲突进行验收。

---

# 14. 当前已验证的在线调参类型五：Time（时间参数）

例如 S15（策略15）：

```text
CFG15_S15_SYNC_STABLE_S
（同步条件连续稳定时间）
```

正式：

```text
0.50 s
```

T1（测试1）在线改成：

```text
999 s
```

作用：

```text
同步控制可以真实运行
但试验期间绝对不允许自动重合闸
```

随后重新Load/恢复正式测试：

```text
0.50 s
```

完成 T2（完整恢复）。

时间参数特别适合：

```text
状态机驻留时间
确认时间
超时
保护延迟
恢复斜坡
```

在线调整。

---

# 15. 当前已验证的在线调参类型六：Gain（增益）

例如：

```text
CFG15_EXEC_FAULT_GAIN
（执行故障增益）
```

设计：

```text
u_applied
=
gain
×
u_commit
```

可以通过：

```text
1.0
→ 正常执行

0.8
→ 80%执行能力

0.5
→ 50%执行能力

0
→ 完全不响应新命令
```

制造执行能力退化。

类似地：

```text
CFG15_S15_FREF_KDF
（频率差到Fref修正增益）

CFG15_S15_FREF_KTHETA_HZ_PER_DEG
（相角差到Fref修正增益）
```

也属于适合在线调节的控制增益。

但高风险控制增益应：

```text
先Shadow（影子）
或
禁止危险动作
```

再调。

---

# 16. 当前已验证的在线调参类型七：Selector（设备选择）

例如：

```text
CFG15_EXEC_FAULT_DEVICE
（执行故障设备编号）
```

编码：

```text
1 = PV1（光伏1）
2 = PV2（光伏2）
3 = ESS1（储能1）
4 = ESS2（储能2）
5 = EV1（电动汽车1）
6 = EV2（电动汽车2）
```

以及：

```text
CFG15_BLACKSTART_MASTER
（黑启动构网主机）

CFG15_ISLAND_MASTER
（孤岛构网主机）
```

当前：

```text
1 = ESS1
2 = ESS2
```

这种：

```text
编号选择参数
```

也非常适合在线测试不同对象。

---

# 17. 当前已验证的在线调参类型八：Vector（向量参数）

本项目一个非常重要的实证：

```text
PV_profile_pu
（光伏可用功率曲线）
```

不是标量，而是：

```text
1×6 向量
```

在 RT-LAB Variable Viewer（变量查看器）中可以在线修改：

```text
PV_profile_pu(6)
```

例如：

```text
0.65
→
0.95
→
0.55
→
0.65
```

无需重新Build。

这证明：

> **在线调参不只适用于标量；已经被实测验证的向量参数也可以修改具体元素。**

但是不要直接推广成：

```text
“任何维度任何数组都一定可以在线修改”
```

准确说法是：

> 当前项目已经明确验证 `PV_profile_pu(6)` 这种1×6向量元素在线修改可用；其它复杂数组仍应单独验证代码生成后的可调性。

---

# 18. `CFG15_*` 和 `CFG_AA_*` 为什么要分两类

当前命名原则：

```text
CFG_AA_*
=
策略算法自己的物理参数、阈值和目标

CFG15_*
=
LOCAL15系统级执行、模式、仲裁和测试配置
```

例如：

```text
CFG_AA_uv_threshold_pu
（原策略低压阈值）
```

属于：

```text
S8策略本体
```

而：

```text
CFG15_EXEC_S08
（S8执行许可）
```

属于：

```text
LOCAL15执行框架
```

二者不能合并。

正确：

```text
“策略判断阈值”
和
“策略是否允许真实执行”
分开
```

错误：

```text
再造一个CFG15_UV_THRESHOLD
```

导致同一个低压阈值有两份。

---

# 19. 以后新模块想支持在线调参，推荐的标准结构

假设以后新增一个参数：

```text
CFG15_NEW_RECOVERY_TIMEOUT_S
（新恢复超时时间）
```

推荐设计：

```text
SM_Master
│
└─ AA15_CFG15_PANEL
   │
   └─ Constant：
      CFG15_NEW_RECOVERY_TIMEOUT_S
      默认 = 2.0
      SampleTime = inf
      DataType = double
      │
      ↓
      global Goto：
      CFG15_NEW_RECOVERY_TIMEOUT_S
```

使用模块：

```text
AA15_NEW_RECOVERY_MANAGER
（新恢复管理器）
│
└─ From：
   CFG15_NEW_RECOVERY_TIMEOUT_S
   │
   ↓
   MATLAB Function input
   （MATLAB函数输入）
```

而不是：

```matlab
function ...
timeout = 2.0;   % 写死
```

---

# 20. 为什么推荐把可调参数通过 Function Input（函数输入）送进去

如果阈值直接写在：

```matlab
if abs(df) < 0.2
```

代码内部：

```text
0.2
```

已经成为算法代码的一部分。

以后想改：

```text
0.20
→
0.10
```

通常需要：

```text
修改代码
↓
重新代码生成
↓
重新Build
```

如果改成：

```matlab
if abs(df) < df_max
```

其中：

```text
df_max
```

来自一个显式 Inport（输入端口）：

```text
From CFG15_NEW_DF_MAX
↓
MATLAB Function input
```

那么：

```text
算法结构不变
只改运行参数
```

更适合RT-LAB在线调试。

---

# 21. 最推荐的“参数发布 → 算法读取”模板

```text
┌─────────────────────────────┐
│ Parameter Panel（参数面板） │
│                             │
│ Constant                    │
│ CFG_xxx                     │
│                             │
│      ↓                      │
│ Global Goto CFG_xxx         │
└─────────────────────────────┘
             │
             │ 标签传输
             ▼
┌─────────────────────────────┐
│ Control Subsystem           │
│ （控制子系统）              │
│                             │
│ From CFG_xxx                │
│      ↓                      │
│ MATLAB Function Inport      │
│      ↓                      │
│ Core Algorithm              │
└─────────────────────────────┘
             │
             ▼
┌─────────────────────────────┐
│ Diagnostic（诊断）          │
│ Parameter Echo（参数回显）  │
│      ↓                      │
│ Group28 / OpWrite           │
└─────────────────────────────┘
```

三层分别回答：

```text
参数从哪里来？
↓
算法在哪里使用？
↓
Target是否真的采用了它？
```

---

# 22. 为什么重要参数最好增加 Parameter Echo（参数回显）

假设Variables Table中改：

```text
0.5
→
999
```

只看PC界面显示999并不够严谨。

更好的方式：

```text
CFG15_S15_SYNC_STABLE_S
↓
Recovery Manager
↓
同时支路输出
↓
Diagnostic
↓
MAT
```

那么MAT可以直接记录：

```text
实际Target使用的参数值
```

以后出现：

```text
“为什么这轮没有动作？”
```

可以先检查：

```text
参数到底有没有真正到Target
```

而不用猜。

---

# 23. 哪些参数适合放进统一 Parameter Panel（参数面板）

最适合集中放：

### 使能

```text
*_ENABLE
```

### 模式

```text
*_MODE
```

### 选择器

```text
*_SOURCE
*_MASTER
*_DEVICE
```

### 阈值

```text
*_MAX
*_MIN
*_THRESHOLD
```

### 时间

```text
*_S
*_TIME
*_HOLD
*_CONFIRM
```

### 增益

```text
*_GAIN
*_KDF
*_KTHETA
```

### 限幅

```text
*_LIMIT
*_TRIM_MAX
```

它们具有共同特点：

> **改变数值以后，算法拓扑和端口数量不需要改变。**

这种参数非常适合 RT-LAB 在线调节。

---

# 24. 参数名称最好直接写单位

推荐：

```text
CFG15_S15_SYNC_DF_MAX_HZ
```

而不是：

```text
CFG15_SYNC_DF
```

推荐：

```text
CFG_AA_demand_limit_kW
```

而不是：

```text
demand_limit
```

推荐：

```text
CFG15_S15_SYNC_DTHETA_MAX_DEG
```

单位直接写：

```text
HZ
KW
PU
DEG
S
```

可以避免在线调参时出现：

```text
这个0.2到底是Hz？
pu？
百分比？
```

---

# 25. 哪些东西不能依靠当前在线调参方法修改

以下变化应该默认视为：

```text
需要重新Build（编译）
```

除非以后单独证明其可在线修改。

---

## 25.1 模型结构

例如：

```text
新增/删除 Block（模块）

新增/删除 Line（连线）

修改 Mux Inputs（多路复用器输入数量）

修改 Demux Outputs（解复用器输出数量）

增加 MATLAB Function 输入/输出端口

改变 Subsystem 端口数量
```

这些都是：

```text
结构变化
```

必须重新代码生成。

---

## 25.2 MATLAB Function（MATLAB函数块）代码

例如：

```text
改变状态机逻辑

增加if分支

改AGC资源分配公式

增加persistent状态
```

属于：

```text
算法代码变化
```

需要重新Build。

---

## 25.3 GotoTag / From Tag（信号标签）

例如：

```text
V5A_FINAL_ESS1
→
AA15_FINAL_APPLIED_ESS1
```

这是：

```text
真实信号连接关系变化
```

不是普通参数调节。

修改以后需要重新Build。

---

## 25.4 Sample Time（采样时间）

例如：

```text
Unit Delay
100 μs
→
200 μs
```

当前项目没有把这类离散结构参数作为在线调参基线。

应当视为：

```text
结构/调度变化
→ 重新Build
```

---

## 25.5 实时模型基本步长

例如：

```text
100 μs
→
50 μs
```

一定不是普通 Variables Table 在线参数。

涉及：

```text
solver（求解器）
实时调度
代码生成
```

必须重新Build并重新做实时性验收。

---

## 25.6 SM / SS（主任务/子任务）任务分配

例如：

```text
把设备从SS_Slave2移到SS_Slave3
```

属于实时架构修改。

必须重新Build。

---

## 25.7 Stubline（实时电气解耦支路）拓扑

增加/删除：

```text
Stubline
Transformer
Breaker
Electrical Branch
```

属于电气结构修改。

不属于在线调参。

---

# 26. “理论上可能可调”和“本项目已经验证可调”要严格区分

Simulink / RT-LAB中某些：

```text
Gain
Threshold
Initial Condition
Lookup Table
```

参数在特定代码生成设置下也可能是Tunable（运行时可调）。

但本项目当前最可靠的结论应当写：

```text
已经实际验证：
1. CFG15参数面板中的Constant参数
2. 原CFG_AA策略参数
3. PV_profile_pu(6)向量元素
```

其它Block参数：

```text
是否能在线调
```

应当：

```text
先做Probe（探针）验证
```

再纳入正式工作流。

不要从软件理论能力直接推导：

```text
“所有Gain都一定可以在线改”
```

---

# 27. 新参数加入模型时的标准设计步骤

以后每新增一个在线参数，建议固定执行以下流程。

---

## Step 1（步骤1）：判断它到底是“参数”还是“结构”

如果修改它只会改变：

```text
数值
```

而不会改变：

```text
模块数量
连线
端口
状态维度
```

可以考虑做Tunable（在线可调）。

---

## Step 2（步骤2）：给参数统一命名

例如：

```text
CFG15_NEW_TIMEOUT_S
```

不要：

```text
a1
time2
testvalue
```

---

## Step 3（步骤3）：放入正确参数层

如果是策略本体物理阈值：

```text
CFG_AA_*
```

如果是LOCAL15系统执行框架：

```text
CFG15_*
```

不要重复定义同一物理量。

---

## Step 4（步骤4）：建立 Constant（常数块）

推荐：

```text
SampleTime = inf

DataType = double
```

设置明确默认值。

---

## Step 5（步骤5）：通过 Global Goto（全局发布）发送

例如：

```text
CFG15_NEW_TIMEOUT_S
```

标签和参数名尽量一致。

---

## Step 6（步骤6）：使用模块通过 From（读取标签）取值

不要从顶层拉几十根参数长线。

---

## Step 7（步骤7）：参数以显式输入进入控制核心

例如：

```text
From
↓
MATLAB Function input
```

不要把同一个值重新在核心代码里写死。

---

## Step 8（步骤8）：增加诊断回显

推荐：

```text
Parameter Echo
↓
Group28
```

或者加入：

```text
Tunability Monitor（可调性监视）
```

---

## Step 9（步骤9）：Rebuild All（全部重新编译）

因为：

```text
这一次是在“新增参数结构”
```

所以第一次必须Build。

---

## Step 10（步骤10）：做在线可调性Probe（探针测试）

```text
Load
↓
Variables Table
↓
默认值 A
→
测试值 B
↓
不Build
↓
观察MAT / Scope
```

如果Target真正变化：

```text
Tunable PASS（在线调参通过）
```

---

# 28. 新参数首次验收必须做的三个检查

不能只看 Variables Table（变量表）里数字变了。

必须：

### 检查1

```text
Variables Table值变化
```

### 检查2

```text
Target诊断/回显值变化
```

### 检查3

```text
算法输出按照参数意义发生对应变化
```

例如：

```text
SYNC_STABLE
0.5 → 999
```

不仅要看到参数=999。

还要看到：

```text
系统持续同步
但不重合闸
```

才算完整证明。

---

# 29. Variables Table（变量表）推荐工作方式

当前LOCAL15测试已经形成：

```text
AA15_CFG15_PANEL
```

整体加入 Variables Table（变量表）。

这样所有：

```text
CFG15_*
```

长期保留在工作区。

另外，不属于Panel的原策略参数，例如：

```text
CFG_AA_v_nom_V
```

可以单独拖入 Variables Table。

---

# 30. 建议建立 Working Set（参数工作集）

可以长期保存：

```text
LOCAL15_TEST_ALL
```

里面包含：

```text
全部CFG15_*

常用CFG_AA_*

PV_profile_pu
```

这样：

```text
Reset / Load
```

以后不需要重新找参数入口。

注意：

> Working Set（工作集）保存的是“我想显示和修改哪些参数”，不代表Target运行值不会因为重新Load而恢复模型默认。

---

# 31. Auto Apply（自动应用）为什么适合策略测试

Variables Table中：

```text
Auto Apply = ON
```

以后修改：

```text
0 → 1
```

Target直接使用。

这非常适合：

```text
t≈20 s
打开策略

t≈40 s
恢复参数
```

人工时序工况。

但是高风险参数，例如：

```text
Breaker真实使能
```

在操作以前必须先确认：

```text
当前工况
当前值
当前模式
```

避免误点击。

---

# 32. Reset / Load（复位/加载）以后为什么参数会恢复默认

当前调参逻辑是：

```text
运行时修改
```

并没有修改：

```text
SLX模型中保存的默认值
```

所以：

```text
Reset
重新Load
```

以后：

```text
Target重新加载模型默认参数
```

这其实是好事。

因为每轮测试可以从：

```text
已知初始状态
```

重新开始。

---

# 33. “测试参数”和“产品默认参数”必须分开

例如 S15 T1：

```text
SYNC_STABLE_S = 999 s
```

只是：

```text
安全测试参数
```

正式模型默认仍然：

```text
0.50 s
```

不要因为测试成功就把：

```text
999
```

保存成产品默认。

同理：

```text
UV threshold = 1.10
```

只是：

```text
S8测试判据注入
```

正式默认仍然：

```text
0.88
```

---

# 34. 在线调参的一个重要优势：可以实现“一次Execute多阶段工况”

例如 S6（策略6）：

```text
Execute开始

↓
PV_profile_pu(6)=0.65

↓
在线：
0.65 → 0.95

↓
再在线：
0.95 → 0.55

↓
再在线：
0.55 → 0.65

↓
Reset
```

一次Execute就完成：

```text
上升
下降
恢复
```

如果参数不能在线调：

```text
每一个阶段都需要单独Build/Run
```

测试效率会非常低。

---

# 35. 在线调参的第二个优势：可以建立“正向 + 负向”安全测试

例如：

```text
同一个冻结模型
```

先测试：

```text
电气异常
```

再Reset/Load。

然后测试：

```text
纯通信异常
```

只改不同参数。

模型结构完全不变。

因此可以明确：

```text
差异来自工况
不是来自两个不同模型版本
```

---

# 36. 在线调参的第三个优势：特别适合BOARD15以后做自动回归

未来可以把人工Variables Table逐步变成：

```text
Test Script（测试脚本）
```

自动执行：

```text
Load
↓
set parameter
↓
wait until Target Time
↓
set new parameter
↓
记录
↓
自动判PASS
```

因为当前参数已经被设计成：

```text
明确
集中
可在线修改
```

所以后续自动化的基础已经具备。

---

# 37. 一个推荐的新模块示例

假设以后要新增：

```text
通信异常恢复确认时间
```

参数：

```text
CFG15_COMM_RECOVERY_CONFIRM_S
（通信恢复确认时间）
```

推荐结构：

```text
AA15_CFG15_PANEL
│
├─ Constant
│  CFG15_COMM_RECOVERY_CONFIRM_S
│  Value = 0.5
│  SampleTime = inf
│
↓
Goto
CFG15_COMM_RECOVERY_CONFIRM_S
```

控制侧：

```text
Mode Manager
│
├─ From CFG15_COMM_RECOVERY_CONFIRM_S
│
↓
MATLAB Function input：
T_comm_recover
```

代码：

```matlab
if comm_good
    good_timer = good_timer + dt;
else
    good_timer = 0;
end

if good_timer >= T_comm_recover
    ...
end
```

这样以后：

```text
0.5
→
1.0
→
2.0
```

都可以在RT-LAB Load后直接对比。

---

# 38. 一个不推荐的设计示例

不推荐：

```matlab
function ...
...
if good_timer >= 0.5
    ...
end
```

然后测试需要：

```text
0.5
→
1.0
```

只能：

```text
打开MATLAB Function
↓
改代码
↓
保存
↓
Build
↓
Load
```

这种参数写法会极大拖慢：

```text
调试
参数敏感性
论文试验
CHIL复测
```

---

# 39. 一个更危险的不推荐设计：同一个参数定义两份

例如：

```text
CFG_AA_uv_threshold_pu = 0.88
```

原策略已经使用。

又新增：

```text
CFG15_UV_THRESHOLD = 0.90
```

执行器使用另一份。

那么可能发生：

```text
策略认为没低压
执行器认为低压
```

或相反。

因此：

> **一个物理判据只保留一个参数源。**

LOCAL15的 `CFG15_*` 主要管：

```text
“允不允许执行”
```

而不是复制所有 `CFG_AA_*` 物理阈值。

---

# 40. 在线参数和状态变量也不能混淆

例如：

```text
CFG15_S15_SYNC_STABLE_S
```

是：

```text
参数
```

可以在线调。

而：

```text
AA15_S15_SYNC_TIMER_S
```

是：

```text
运行状态
```

不能把它当成用户配置参数随意改。

同理：

```text
CFG15_ISLAND_MASTER
=
配置
```

而：

```text
AA15_MODE_SELECTED_MASTER
=
状态/结果
```

参数和状态必须命名、显示、记录分开。

---

# 41. 哪些模块在当前项目里特别适合利用在线调参

从本次15策略经验，可归纳为六类。

---

## A. Strategy Enable Layer（策略使能层）

例如：

```text
CFG15_EXEC_S01
...
CFG15_EXEC_S15
```

适合：

```text
在线开/关某个策略
```

---

## B. Objective / Constraint Layer（主目标/约束层）

例如：

```text
P_OBJECTIVE_MODE
tie_target
demand_limit
export_limit
anti_reverse_limit
```

适合：

```text
快速切换主目标
制造目标冲突
```

---

## C. Protection Threshold Layer（保护阈值层）

例如：

```text
UV threshold
UF threshold
Vn
```

适合：

```text
逻辑验证型工况注入
```

---

## D. Mode / Safety Layer（模式/安全层）

例如：

```text
MODE_ACTUATION_ENABLE
PCC_BREAKER_ACTUATION_ENABLE
BLACKSTART_MASTER
ISLAND_MASTER
```

适合：

```text
先透明
再接管
```

---

## E. Recovery State Machine Layer（恢复状态机参数层）

例如：

```text
sync stable time
reclose hold time
ΔV / Δf / Δθ threshold
Fref gains
```

非常适合：

```text
状态机参数调试
安全分步测试
敏感性实验
```

---

## F. Test Injection Layer（测试注入层）

例如：

```text
fault enable
fault device
fault gain
fault start/end

PV_profile_pu
```

适合：

```text
制造可重复测试工况
```

---

# 42. 最推荐的新模块设计规范

以后只要你说：

> “这个参数以后我想在RT-LAB运行中直接改。”

就优先按以下规则设计。

```text
① 参数有明确名称和单位

② 参数只定义一次

③ 参数不写死在核心算法

④ 参数从Parameter Panel统一发布

⑤ Constant使用明确默认值

⑥ global Goto分发

⑦ 使用模块通过From读取

⑧ 作为MATLAB Function显式输入

⑨ 重要参数增加回显/诊断

⑩ 初次增加结构以后Rebuild

⑪ Build后做一次在线Probe

⑫ Probe通过后再列入正式Variables Table工作集
```

---

# 43. 在线调参功能设计审查清单

新增模块前可以直接照此检查。

## 参数层

```text
□ 这个量真的是运行参数，不是结构参数？

□ 参数名有单位？

□ 默认值明确？

□ 是否已经有同义旧参数？

□ 应属于CFG_AA还是CFG15？
```

---

## 模型层

```text
□ Constant是否存在？

□ 是否从统一Panel发布？

□ SampleTime是否采用当前参数块规范？

□ DataType是否明确？

□ GotoTag是否唯一、命名一致？
```

---

## 算法层

```text
□ 使用模块是否通过From读取？

□ 参数是否通过显式Function Input进入核心？

□ 核心代码里是否还存在同一参数的硬编码副本？
```

---

## 验证层

```text
□ 是否增加Parameter Echo / Diagnostic？

□ 是否进入Group28或其它正式日志？

□ Build是否PASS？

□ Load以后不Build能否修改？

□ Target是否真的采用新值？

□ 算法输出是否按预期变化？
```

---

# 44. 最后总结：RT-LAB在线调参真正应该怎样理解

不是：

> “RT-LAB里看到一个数字，所以我都能随便改。”

而是：

```text
模型在设计阶段
把“以后需要频繁变化的量”
明确做成可调参数

↓
代码生成阶段
保留Tunability（可调性）

↓
模型内部
用Parameter Panel + Goto/From
把参数干净送到各控制模块

↓
控制核心
通过显式输入使用

↓
Target运行
Variables Table直接修改

↓
日志验证
Target真正采用新值
```

这才是一套完整的：

> **Real-Time Tunable Parameter Architecture（实时在线可调参数架构）。**

---

# 45. 本项目最值得长期保留的一句话设计原则

> **凡是“预计以后需要为了测试、整定、工况切换、模式选择或阈值敏感性而反复改变，但改变它又不应该改变模型拓扑”的量，都应优先设计成 RT-LAB Tunable Parameter（实时在线可调参数），通过统一 Parameter Panel（参数面板）发布，作为控制核心的显式输入，并通过诊断回显验证Target真正采用。**

而：

> **凡是会改变模块数量、连线、端口、状态维度、采样结构、求解器或实时任务拓扑的内容，都不应假装成普通在线参数，应重新Build并重新验收。**

这两句话基本就是以后设计RT-LAB新模块时判断：

```text
“这个东西到底应该在线调，
还是应该重新Build？”
```

的核心标准。
