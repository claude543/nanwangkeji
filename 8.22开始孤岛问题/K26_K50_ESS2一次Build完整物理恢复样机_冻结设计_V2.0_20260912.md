# K26_K50 物理黑启动｜ESS2 一次 Build 完整恢复样机冻结设计 V2.0

日期：2026-09-12  
模型：`K26_K50_CLEAN_P1`  
范围：**ESS2 从黑启动待并到最终接回和功率恢复所需结构，一次性补齐**  
状态：**设计冻结，进入 Patch R2**

---

## 1. 为什么 V1 方案需要扩大

上一版只准备补：

- ESS2 功率环待并；
- ESS2 电流执行待并；
- G27诊断。

这个方案能做“待并验证”，但还不满足：

> **既然改模后必须重新 Build，就应在这次 Build 前把 ESS2 后续真正接回所需结构一次性补齐。**

否则待并 PASS 后还要为了：

- S14阶段传入；
- 本地接回状态机；
- breaker 自动/手动仲裁；
- 零功率接入后的确认；
- 平滑功率释放；
- 状态回送 SM；

再次改模和 Rebuild。

因此 V2 的目标改为：

```text
一次 Build
↓
以后 ESS2 各阶段只靠在线参数推进
↓
待并
↓
零功率接回
↓
小功率释放
↓
S14自动源
```

不再因为缺结构重复 Build。

---

# 2. 这次到底修改哪些位置

## 2.1 SM_Master：只做“传阶段”和“收状态”

**不是新增中央快速控制器。**

### 修改 A：ESS 组发送向量 24 → 25

现有：

```text
ESS1_IO12
+
ESS2_IO12
↓
ESS_Group_Mux24
↓
ESS_IO_Memory24
↓
SS_Slave2
```

改为：

```text
ESS1_IO12
+
ESS2_IO12
+
LOCAL15 S14 stage_echo 1维
↓
25维
```

具体：

```text
SM_Master/ESS_Group_Mux24
Inputs: 2 → 3

SM_Master/ESS_IO_Memory24
IC: zeros(24,1) → zeros(25,1)

新增：
SM_Master/AA15_ESS2_RESTORE_STAGE_FROM_S14
GotoTag = AA15_BS_STAGE_ECHO
```

SS_Slave2：

```text
ESS_Group_Demux
[12 12] → [12 12 1]
```

因此以后只需在线设置：

```text
CFG_ESS2_RESTORE_CONTROL_SOURCE
0 = 手动测试源
1 = S14 stage源
```

不需要再 Build 才接 S14。

---

## 2.2 SS_Slave2：增加 ESS2 本地物理恢复执行器

新增：

```text
AA15_ESS2_RESTORE_CONFIG
AA15_ESS2_RESTORE_EXECUTOR
AA15_ESS2_RESTORE_EXECUTOR_DEMUX
```

执行器状态：

```text
0 旁路/原模型
1 断开待并
2 准备资格累计
3 READY
4 已发合闸命令，零功率后确认
5 已接入、仍零功率
6 功率平滑释放
7 恢复完成
9 失败
```

执行器没有 persistent，状态显式放在 Unit Delay。

---

# 3. ESS2 功率环怎么改

路径：

```text
SS_Slave2/ESS2_Control/Power Control Loop
```

现有：

```text
Pref - Pmeas → P PI
Qmeas - Qref → Q PI
```

V2 不再只做简单开关，而是增加：

```text
RestoreAlpha
```

变为：

```text
(Pref - Pmeas) × RestoreAlpha → P PI
(Qmeas - Qref) × RestoreAlpha → Q PI
```

其中：

```text
正常/旁路：
alpha = 1

待并/零功率接入：
alpha = 0

功率恢复：
alpha 从0平滑爬到1
```

这样第一次恢复功率不会突然把完整误差一步送回功率 PI。

---

# 4. 为什么还要直接处理功率 PI 的积分状态

这是 V1 还不够完整的地方。

如果设备曾经运行过，再进入待并：

```text
即使 error × alpha = 0
```

旧 PI 积分状态仍可能留着。

因此这次一次性给两只原功率 PI 内部的：

```text
Discrete-Time Integrator
```

启用：

```text
ExternalReset = level
```

并新增 `RestoreHold`。

待并时：

```text
RestoreHold = 1
↓
P PI积分状态持续复位到原Init=0
Q PI积分状态持续复位到原Init=0
```

释放功率时：

```text
RestoreHold = 0
↓
从干净的0状态开始
+
alpha 0→1平滑增加
```

**Kp/Ki/限幅完全不改。**

---

# 5. ESS2 电流执行层怎么改

路径：

```text
SS_Slave2/ESS2_Control
/AA15_GFL_ISLAND_SUPPORT
/AA15_V49_CURRENT_EXECUTION_ADAPTER
/CORE
```

新增：

```text
RestoreHold
```

待并时：

```text
iref_used = 0
imeas_used = 0
PI总输出匹配目标 = 0
```

因此：

```text
不再追一个物理断开后不可控的母线侧电流
```

但保留：

```text
Vff（母线电压前馈）
```

所以 ESS2 不是完全关PWM，而是：

> **保持跟随岛网电压，但不主动请求电流。**

原底层 V4.9 helper 函数主体完全不改，只改最外层调用。

---

# 6. 本地 breaker 怎么处理

现有：

```text
CFG_DIAG_AC_CONNECT_ESS2
↓
AA15_DIAG_AC_BREAKER_ESS2
```

改为：

```text
                       ┌ 原CFG命令
                       │
                   Switch
                       │
                       └ executor breaker command
                       ↓
              AA15_DIAG_AC_BREAKER_ESS2
```

规则：

```text
MASTER = 0
→ 完整旧路径
→ CFG_DIAG_AC_CONNECT_ESS2 直接生效

MASTER = 1
→ executor接管
```

执行器内部另有：

```text
BREAKER_ACTUATION_ENABLE
```

默认 0。

因此即使误开启 MASTER：

```text
breaker也不会自动闭合
```

除非明确打开执行门。

---

# 7. 为什么这次就把手动、半自动、自动三种模式都留好

后续不应再为测试方式改模。

### 手动开发阶段

```text
CONTROL_SOURCE = 0
MANUAL_REQUEST = 1
AUTO_SEQUENCE = 0
```

待并完成后：

```text
MANUAL_COMMIT = 1
```

这是唯一物理接回事件。

零功率接入确认后：

```text
MANUAL_RELEASE = 1
```

开始平滑恢复。

### S14自动阶段

以后不改模型，只在线设：

```text
CONTROL_SOURCE = 1
AUTO_SEQUENCE = 1
BREAKER_ACTUATION_ENABLE = 1
POWER_RELEASE_ENABLE = 1
```

此时：

```text
S14 stage >= 2
↓
ESS2自动进入恢复序列
```

---

# 8. 接回准备判据已经预留，但高风险判据默认关闭

基础 READY 条件使用：

```text
PCC/设备 Vpu 范围
ESS2 PLL 与 MasterF 频差
Final Iref 大小
实际 Imeas 大小
CurrentLimit
ModHeadroom
```

并要求持续 `READY_DWELL_S`。

另外还预留：

```text
PHASE_GATE_ENABLE
VMATCH_GATE_ENABLE
```

利用已有：

```text
EV1_inv      → 变流器端电压
EV1_LV_Meas  → breaker母线侧电压
```

计算：

```text
phase correlation
voltage magnitude ratio
```

但默认：

```text
PHASE_GATE_ENABLE = 0
VMATCH_GATE_ENABLE = 0
```

原因：

- C2 节点没有直接测量；
- 两个测量块量纲/比例还需要第一轮 standby 数据标定；
- 不能在没有实际数据时把这些条件伪装成已经验证过的硬门。

结构已经一次性留好；标定后**在线改参数启用即可，不需要再 Build**。

---

# 9. 功率释放为什么有独立斜坡

接回成功以后，不能直接：

```text
alpha 0 → 1
```

所以执行器有：

```text
RELEASE_RAMP_S
```

默认内部参考：

```text
2 s
```

释放时：

```text
RestoreHold
1 → 0

RestoreAlpha
0 → 1 线性爬升
```

功率 PI 从零积分状态开始重新工作。

这个结构也解决了原始 S14：

```text
Stage2 一到就立即恢复ESS Pref
```

过于粗糙的问题。

即使 S14 已经释放 Pref：

```text
本地 RestoreAlpha=0
```

时 ESS2 仍然不会执行功率。

只有接回确认后才平滑放开。

---

# 10. SS_Slave2 恢复状态也一次性送回 SM

当前 ESS 返回向量是 33 维。

这次：

```text
33 → 45
```

只在末尾追加执行器 12维状态。

SM 原 `Demux1`：

```text
[1 1 1 1 26 3]
```

改：

```text
[1 1 1 1 26 3 12]
```

前6段完全不动。

新增第7段通过：

```text
AA15_ESS2_RESTORE_STATUS_GOTO
GotoTag = AA15_ESS2_RESTORE_STATUS_VEC
```

保留在 SM。

现在不增加中央控制器消费者，但**反馈基础已经建好**。

以后做 PV/EV 和真正全 S14 顺序闭环时，SM 可以直接使用这个状态，不需要再为了 ESS2 改通信。

---

# 11. OpWrite仍然只有5个

保持：

```text
G26 EV1/EV2
G27 ESS2
G28 PV1/PV2
G29 系统
G30 ESS1
```

不增加第6个。

G27 改为新 56维 ESS2 设备数据。

原48维中替换：

| 原槽位 | 新含义 |
|---|---|
| Stage | RestoreState |
| Kslow | RestoreHold |
| Kfast | ReconnectReady |
| gP | RestoreAlpha |
| gQ | 最终 breaker command |
| MasterF | PowerReleaseAllowed |
| VrefCmd | RestoreFailCode |

追加：

```text
49~51  变流器端 Va/Vb/Vc
52~54  breaker母线侧 Va/Vb/Vc
55     phase correlation
56     voltage ratio
```

所以：

> **不新增 OpWrite，且核心电流、P/Q、PLL、调制度、支撑量仍全部保留。**

---

# 12. 保存后默认不会改变正常模型

这是整个设计的总安全门。

默认：

```text
CFG_ESS2_RESTORE_MASTER_ENABLE = 0
```

于是：

```text
RestoreHold = 0
RestoreAlpha = 1
breaker router = legacy CFG path
```

即：

> **模型保存/Build以后，如果不主动打开恢复 MASTER，ESS2仍按原模型工作。**

因此这次结构可以一次性加全，但逐级测试。

---

# 13. Build后怎么试，不再改模型

## 第1轮：参数可调性 Probe

验证全部新 `CFG_ESS2_RESTORE_*`：

```text
read
write
readback
restore
```

## 第2轮：待并，不合闸

pre-Execute：

```text
MASTER=1
CONTROL_SOURCE=MANUAL
MANUAL_REQUEST=1
AUTO_SEQUENCE=0
BREAKER_ACTUATION=0
POWER_RELEASE=0
```

验证：

```text
ESS1仍能建网
ESS2 breaker保持OPEN
ESS2 P/Q PI状态被清零
FinalIref≈0
ModIndex脱离长期饱和
ModHeadroom恢复
```

并标定两组三相电压的比例/相位。

## 第3轮：零功率物理接回

仍从 Reset/Load/t=0开始。

预先：

```text
MASTER=1
MANUAL_REQUEST=1
BREAKER_ACTUATION=1
AUTO_SEQUENCE=0
```

等 `ReconnectReady=1`。

唯一运行时事件：

```text
MANUAL_COMMIT : 0 → 1
```

执行器闭合 ESS2 breaker。

仍然：

```text
RestoreHold=1
RestoreAlpha=0
```

所以接入后没有功率释放。

## 第4轮：功率释放

零功率接入已经 PASS 后再做。

唯一释放动作：

```text
POWER_RELEASE_ENABLE=1
MANUAL_RELEASE : 0 → 1
```

然后：

```text
RestoreAlpha 0→1
```

平滑恢复原 ESS2 P/Q 控制。

## 第5轮：S14自动源

前三阶段 PASS 后，不改模型：

```text
CONTROL_SOURCE=1
AUTO_SEQUENCE=1
```

再验证 S14 stage2 是否可以自动触发 ESS2 完整恢复。

---

# 14. 本次不做什么

仍然不一次性改：

```text
PV1/PV2/EV1/EV2
```

原因不是它们不需要。

而是 ESS2 是通用 GFL 物理恢复样机。

ESS2完整通过后，再一次 Build 把已经验证的同一模板迁入另外四台，并同时完成 PV/EV 分组顺序。

这样避免把未经验证的逻辑一次复制5份。

---

# 15. 这次脚本错误为什么不会再用原判据

R1 报：

```text
G27 is not OpWriteFile
```

实际模型中 G27 是：

```text
BlockType = Reference
SourceBlock = rtlab/DataLogging/OpWriteFile
SourceType = OpWriteFile
```

问题是脚本把 Reference Block 当普通块，只依赖一个 `get_param(...,'SourceType')`。

R2 改为组合检查：

```text
ReferenceBlock
SourceBlock
SourceType
```

并对 Mask/Dialog 参数使用双路径读取。

以后不再用单一 `BlockType` 或单一 `SourceType` 判断 RT-LAB Reference Block。


---

# 16. R1 Patch 已废止

旧文件：

```text
PATCH_K26_K50_ESS2_RECONNECT_STANDBY_R1.m
```

在正式写盘前的只读预审阶段停止：

```text
G27 is not OpWriteFile
```

该失败来自脚本对 RT-LAB `Reference` 块的类型判断方式不正确，不是模型错误。

因此：

- R1 不再运行；
- 不需要回滚模型；
- 当前磁盘模型仍应是未修改基线；
- 后续只使用 `PATCH_K26_K50_ESS2_PHYSICAL_RESTORE_R2.m`。

R2 Patch 最终 SHA256：

```text
7924906d9170b497bb07e0f3acb641065179fa8b3befacebf3f34a09ce0e8dd1
```
