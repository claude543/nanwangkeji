# 2026-09-14｜S14 V2 + ESS2首次功率承担架构审计 R1：结论、无遗漏检查与改模设计就绪冻结

> 模型：`K26_K50_CLEAN_P1`  
> 审计：`AUDIT_K26_K50_S14_V2_ESS2_POWER_PICKUP_ARCH_R1.m`  
> 审计状态：`READ_ONLY_ARCHITECTURE_AUDIT_COMPLETE_READY_FOR_S14_V2_DESIGN`  
> 当前SLX SHA256：`9c6f881c68411d023732a30b70554d118fa557b197f9b419f686214b1d5edea3`  
> 结论：**当前架构事实已经足够支撑下一步准确改模规划，不需要再追加一轮同类只读审计。**

---

## 1. 本次审计一次通过形成的固定经验

本次审计脚本一次运行完成，未返工，原因不是“脚本简单”，而是完整复用了此前项目中已经证明有效的审计规则：

1. whole-SLX raw SHA只记录，不作为语义硬门；
2. 当前保存模型结构、当前源码、当前真实连线优先于历史记录；
3. 模型从开始到结束始终要求 `Dirty=off`；
4. 只读审计不执行 `set_param/add_block/add_line/delete/save/update/compile`；
5. 普通信号坚持 connectivity first, name second；
6. Goto/From必须继续追真实源，不能停在标签名字；
7. SPS物理端口不套普通Simulink Src/Dst规则；
8. `UNKNOWN`保持`UNKNOWN`，绝不补0；
9. 可选问题全部收集后统一输出，不遇到第一个问题就提前return；
10. 使用当前正式G27=62通道，而不是复制旧56通道合同；
11. OpWrite按项目成熟识别规则枚举，验证仍为G26~G30五组，不新增G31；
12. 审计结束自动生成：
    - 当前源码；
    - 精确接口；
    - 状态；
    - 路由；
    - 问题矩阵；
    - 修改矩阵；
    - `RESULT.json`。
13. 脚本生成后再次做独立静态语义检查：
    - 无模型修改API；
    - 无RT-LAB API；
    - 无已知 `&&/||` 非法换行；
    - 无主流程提前return；
    - 计划证据输出无缺失。

**以后同类型模型审计应直接复用这一骨架，不重新发明审计框架。**

---

# 2. 当前S14问题已经完全锁定

当前真实 `Advanced_Strategy_Core` 中S14仍是：

```text
black_state = 1
↓
t > 20 s → 2
↓
t > 40 s → 3
↓
t > 60 s → 4
```

且：

```text
无 ESS2 restore state
无 restored ACK
无 breaker status
无 device availability
```

因此原S14仍然是：

> **按绝对时间推进的基础恢复顺序算法，而不是物理恢复闭环策略。**

当前S14顶层仍只有原40个输入，其中没有ESS2恢复状态。

---

# 3. Black Start Pref Gate问题已经锁定

当前 `AA15_Black_Start_Pref_Gate`：

```text
Stage1 → 所有Pref=0
Stage2 → 直接放非master ESS Pref
Stage3 → 直接放PV Pref
Stage4 → 直接放EV Pref
```

并且它：

```text
不知道 RestoreState
不知道 breaker真实恢复状态
不知道 resource availability
```

因此：

> **“S14进入某Stage”与“该设备已经物理恢复完成”当前被错误等价。**

---

# 4. 正常孤岛Coordinator问题已经完全锁定

当前 `AA15_FINAL_ISLAND_COORDINATOR` 有30个输入，包括：

```text
五台Legacy Pref
五台Pmeas
PVmax
SOC
PCC电压
五台Vref/Fref
MasterF
```

但是没有：

```text
resource availability
physical breaker connected
RESTORED ACK
ESS1 GFM current reserve
ESS1 GFM modulation reserve
ESS1 GFM P/Q reserve
```

当前源码明确：

```text
upT = up1 + up2 + up3 + up4 + up5
dnT = dn1 + dn2 + dn3 + dn4 + dn5
```

即默认五台GFL都进入能力池。

ESS2设备能力又直接是：

```text
pmin3 = -1
pmax3 = +1
```

这是**设备能力**，不是黑启动时的安全稳定承担能力。

因此：

> **只恢复ESS2一台时，不能把“当前只剩ESS1+ESS2”理解为ESS2可以承担很大功率。**

ESS1仍是唯一GFM，必须保留V/f、电流、调制及P/Q余量。

---

# 5. R7中ESS2目标不断增大的结构原因进一步清楚

当前Coordinator在Stage3：

```text
一次P-f
+
二次频率积分
→ dpt
→ 按五台up/down能力比例分配
```

当前参数：

```text
KPF_SUM = 0.5
KI_F_SECONDARY = 0.8
SECONDARY_ENTRY = 0 s
SECONDARY_SLEW = 0.2 pu/s
```

而Coordinator不知道PV/EV实际仍物理断开。

因此黑启动阶段存在结构错配：

```text
Coordinator：
仍向“五台资源能力池”分配调频责任

↓

S14 / 物理断路器：
实际上只允许ESS2工作
PV/EV仍断开

↓

未执行的功率分配无法真正作用于系统

↓

频率误差继续存在

↓

二次积分继续累积

↓

ESS2自己的Pref也继续迁移
```

这解释了R7里：

```text
RestoreAlpha还为0
但ESS2 PrefCmd已经不断变化
```

的重要上层原因。

---

# 6. 仅增加availability mask还不够

必须区分两个概念：

## A. 是否允许参与

```text
available_i ∈ {0,1}
```

例如只有ESS2恢复：

```text
PV1=0
PV2=0
ESS2=1
EV1=0
EV2=0
```

## B. 允许承担多少

即使：

```text
ESS2_available = 1
```

也绝不能自动使用：

```text
ESS2 = [-1,+1] pu
```

全部设备能力。

否则五台能力池变成只剩ESS2后，所有调频修正反而可能全部压到ESS2。

因此正常Coordinator未来必须同时考虑：

```text
物理可用资格
+
当前资源功率权限
+
ESS1 GFM剩余支撑能力
```

这三层不能混为一层。

---

# 7. ESS2恢复状态返回链已存在，但S14完全没消费

当前返回链：

```text
SS_Slave2
legacy5
→ status12
→ RETURN_APPEND [30 3 12]
→ Memory45
→ ESS_Pmeas_vec2_to_SM
→ SM Demux1 [1 1 1 1 26 3 12]
```

SM中已经存在：

```text
AA15_ESS2_RESTORE_STATUS_GOTO
tag = AA15_ESS2_RESTORE_STATUS_VEC
```

但当前S14算法：

```text
完全没有读取ESS2 restore status
```

因此下一步无需重新发明返回通道。

正确做法是：

> **复用已经存在的12维ESS2恢复状态，把它真正接入S14决策。**

---

# 8. ESS2 state0~5可以正式冻结

当前源码再次确认：

```text
state3：COMMIT前重新检查READY
state4：breaker closed，hold=0
state4：PostOK持续后进入state5
state5：breaker closed，hold=0
state5：zero-stable dwell
```

全部PASS。

结合R6.1/R7物理实验：

> **state0~5不需要重新设计。**

下一步只在其后继续设计。

---

# 9. state6/state7仍然确认是设计缺陷，但下一轮先不做最终回退律

当前：

```text
state6:
releaseAlpha += Ts/releaseRamp

alpha→1
→ state7
```

state7：

```text
releaseAlpha=1
```

因此仍是：

```text
时间走完 ≠ 物理恢复成功
```

但下一轮为了锁定ESS2能否承担非零功率：

> **先不设计最终复杂的健康门控/回退/重试。**

先消除上层目标漂移，再做固定小功率平台。

---

# 10. Power PI当前事实已经足够清楚

当前P/Q PI：

```text
Discrete PI Controller
P: Kp=0.06, Ki=2, limit ±1.25
Q: Kp=0.06, Ki=2, limit ±1
```

内部有自身PI/限幅结构，但外部只有1个输入。

审计没有发现：

```text
IrefUsed
CurrentLimit
FinalIref
Current Adapter execution
```

反馈给Power PI的下游执行跟踪入口。

因此准确结论是：

> **当前没有发现Power PI对“后级Alpha/限流/Current Adapter实际执行量”的外部tracking/back-calculation。**

这不等于“PI完全没有anti-windup”。

当前只能列为：

```text
REVIEW
```

不能先调Kp/Ki。

---

# 11. 当前正常功率命令所有权也已经看清

实际ESS2 Pref最终路径不是简单：

```text
S14 → ESS2
```

而是：

```text
LOCAL15最终Applied Pref
↓
岛内P/Q覆盖层
↓
作为Coordinator Legacy Pref输入
↓
AA15_FINAL_ISLAND_COORDINATOR
↓
PrefESS2
↓
SM输出4
↓
ESS2_IO_Mux12 input6
↓
SS2 ESS2_Control
```

因此：

> **下一轮仅修改Black Start Pref Gate并不能保证ESS2收到固定小功率。**

因为在工程Stage2/3，中央Coordinator仍可能重新生成最终Pref。

这决定下一步必须显式处理：

```text
S14黑启动首次功率承担
vs
正常孤岛Coordinator
```

的控制权选择。

---

# 12. 下一步准确设计已经具备条件

不需要再做第二轮同类只读审计。

下一步设计必须至少处理：

1. **S14本体**
   - 删除20/40/60 s自动成功推进语义；
   - 接入ESS2恢复状态；
   - 改成事件/物理确认驱动；
   - 时间只作为dwell/timeout。

2. **S14 Pref执行**
   - Stage不能再直接等于完整Pref释放；
   - ESS2未恢复时必须严格0功率；
   - 首次承担阶段必须由S14拥有实际功率目标。

3. **S14与正常Coordinator控制权**
   - 首次功率承担期间正常Coordinator不能覆盖ESS2；
   - 下一轮需要一个明确、唯一的功率所有权选择点；
   - 推荐用普通Simulink Switch/Rate Limiter等原生模块，而不是再造状态机。

4. **ESS2固定小功率因果试验**
   - 首个平台建议约 `-0.003 ~ -0.005 pu`；
   - 缓慢到达；
   - 固定保持3~5 s；
   - 目标不得继续移动；
   - 先回答是否存在非零稳定工作点。

5. **正常Coordinator最终复用**
   - 不增加第二套长期协调器；
   - 后续增加per-resource availability；
   - 加入ESS1 GFM余量约束；
   - 新恢复设备从当前稳定工作点无扰接管；
   - 设备未恢复不进入能力池。

6. **state0~5冻结**
   - 不返工。

7. **state6/7最终完善**
   - 等固定小功率因果试验以后再冻结最终健康门控、回退、重试。

---

# 13. 当前仍“未知”的内容不是审计遗漏

以下内容仍未冻结，但它们是**需要实验回答的设计问题**，不是“模型还没审清”：

```text
ESS2到底能稳定承担多少非零功率？
-0.003~-0.005 pu能否稳定？
稳定边界在哪里？
Power PI下游tracking是否必须增加？
最终state6健康门/回退速度如何设置？
ESS1 GFM安全余量具体阈值是多少？
```

这些不能通过再读一次SLX得到答案。

必须通过下一轮干净的固定功率平台试验回答。

---

# 14. 最终就绪判断

```text
当前结构事实是否清楚？        YES
当前控制权路径是否清楚？      YES
S14为什么必须改是否清楚？     YES
Coordinator为什么必须改是否清楚？ YES
state0~5是否可冻结？          YES
下一轮该验证什么是否清楚？    YES

是否还需要同类只读审计？      NO
是否可进入正式设计规划？      YES
是否已经可以盲写最终Patch？   NO
```

下一步应先形成：

> **S14 V2 + ESS2首次固定小功率承担的正式改模设计 V1.0**

把每一个修改块、输入输出、状态语义、控制权切换点、使用Simulink原生模块还是修改现有Function全部冻结后，再写正式Patch。
