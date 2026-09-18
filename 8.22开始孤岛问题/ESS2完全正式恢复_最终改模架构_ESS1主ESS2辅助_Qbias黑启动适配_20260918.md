# ESS2 完全正式恢复：最终改模架构
## ESS1 主承担、ESS2 辅助分担、Q-bias 黑启动适配

日期：2026-09-18

---

# 1. 总体结论

下一版不再只是“加一个二次调频”或“把固定小权限放大”。

真正的 ESS2 完全正式恢复，应形成：

```text
ESS1 = 唯一GFM
先承担瞬时功率不平衡
维持V/f
        ↓
正常Coordinator持续监视
ESS1负担 / 余量
系统f / V
ESS2自身能力
        ↓
ESS2作为GFL辅助分担
        ↓
把ESS1维持在有足够调节余量的工作区
```

ESS2不是新的“主调度源”。

---

# 2. 现有V4.8 q-bias能否直接用于黑启动？

结论：

> 控制器核心和执行链可以复用，但黑启动入口不能原样照搬。

保留：

```text
PCC电压误差
→ central q-bias
→ Router
→ transport
→ ESS2 Decoder
→ Finalizer
→ Iq
```

需要做黑启动适配：

1. 电压目标来源
   - planned island原来捕获切岛前PCC电压；
   - black start没有有效的切岛前母线；
   - 黑启动应明确使用ESS1建网后的额定电压目标，例如1.0 pu / ESS1电压参考；
   - 不依赖“捕获失败后碰巧fallback到1.0”。

2. q-bias初始状态
   - ESS2恢复期间保持0；
   - 正常有功恢复完成后才从0平滑建立。

3. 资源资格
   - 第一阶段只有ESS2已恢复；
   - PV/EV未恢复时必须不给它们分q-bias能力。

4. 独立使能
   - Frequency Secondary与Voltage q-bias分开；
   - 不再只靠同一个Stage一起打开。

5. 能力限制
   - ESS2 current / modulation headroom限制q-bias；
   - ESS1 Q/current/modulation状态决定是否确实需要GFL Q辅助。

所以：

```text
V4.8核心算法
= 复用

black-start entry / enable / target / availability
= 需要适配
```

旧Q PI继续不作为黑启动后主要Q控制路径。

---

# 3. ESS1和ESS2的正确主从关系

不是：

```text
ESS2先改变P
↓
ESS1被迫跟着平衡
```

而应该是：

```text
负荷 / 源变化
↓
ESS1 GFM第一时间自动承担
↓
Coordinator观察ESS1负担
↓
如果ESS1仍处于舒适区
    ESS2不必为了“动作”而动作
如果ESS1负担逐渐接近上/下边界
    ESS2缓慢分担
↓
ESS1重新回到有备用余量的工作区
```

例如：

### ESS1输出功率过高

说明ESS1承担太多供电任务。

则：

```text
ESS2增加输出
或
减少充电
```

让ESS1回落。

### ESS1吸收功率过多

则：

```text
ESS2增加吸收
或
减少输出
```

让ESS1回到中间区域。

所以ESS2动作的目的不是追某个固定目标，而是：

> **维持ESS1构网源的调节裕量。**

---

# 4. 正常孤岛有功控制应该分三层

## A. Primary

输入：

```text
频率瞬时偏差
```

作用：

```text
快速让ESS2帮助ESS1
```

已经通过。

## B. Frequency Secondary

输入：

```text
持续频率偏差
```

作用：

```text
慢慢消除Primary后的频差
```

下一步实现。

## C. ESS1负担恢复

输入：

```text
ESS1实际P
+
ESS1安全/舒适工作区
```

作用：

```text
即使频率已经基本恢复
也不要让ESS1长期顶在高负担/低余量位置

通过缓慢移动ESS2的正常有功基准
把ESS1拉回合理工作区
```

这才是“小权限→正常协调”的核心。

它不是EMS。

它属于实时孤岛运行的GFM reserve / load-sharing管理。

---

# 5. 不再采用“固定正常功率目标”

下一版不把：

```text
NEXT_TARGET = -0.020 pu
```

作为正常运行主线。

固定目标只保留为调试接口。

正常运行的ESS2有功基准应由：

```text
ESS1 burden restoration
+
Primary
+
Frequency Secondary
```

共同形成。

以后若加入EMS，EMS可以再提供更慢的偏置/计划任务，但不是当前黑启动完成的前置条件。

---

# 6. 不需要增加新的MATLAB Function模块

当前没有必要再叠一个新的Function。

建议最小改法：

## 现有S14

只扩状态/使能：

```text
60 = Primary
70 = Frequency Secondary
80 = Normal P Responsibility Release
85 = Voltage q-bias Release
88 = ESS2 Normal Restored
90 = Fail（保留）
```

## 现有Normal Island Coordinator

继续作为所有正常P协调的唯一核心。

在现有Coordinator内部增加：

```text
ESS1 P/Q/current/modulation health
ESS1 P reserve
ESS2 capability
```

并增加：

```text
ESS1 burden restoration
```

不另建第二个协调器。

## q-bias

仍使用已有：

```text
AA15_V48_ISLAND_QBIAS_COORDINATOR
```

只增加黑启动专用：
- enable；
- Vtarget选择；
- availability。

---

# 7. “小权限”为什么存在，怎样彻底取消调试性质

现在Coordinator在S14时：

```text
ESS2允许范围
=
当前baseline ± 小范围
```

这是调试保护。

最终正式运行不应该永久由一个固定的小常数限制。

下一版应改成：

```text
调试阶段：
小范围

↓
ESS2正式恢复后：

允许范围
=
ESS1当前可释放的调节空间
∩
ESS2自身可用能力
∩
电流/调制/V/f安全限制
```

不是无限放开，而是自动进入“正常可用范围”。

---

# 8. ESS1负担恢复怎样设计

设定ESS1一个“舒适功率区”，具体边界后续从额定值和真实数据冻结。

逻辑：

```text
ESS1 P位于舒适区
→ 基准修正 = 0

ESS1 P高于舒适区上边界
→ ESS2逐渐增加输出/减少吸收
→ ESS1 P下降

ESS1 P低于舒适区下边界
→ ESS2逐渐减少输出/增加吸收
→ ESS1 P回升
```

使用：
- deadband（死区）；
- low-pass（低通）；
- rate limit（变化速度限制）；
- 上下功率能力限制。

这样避免ESS2围着ESS1微小波动不停追。

---

# 9. ESS1的Q/current/modulation怎么参与

它们不是直接算ESS2目标P，而是“安全许可”。

例如：

```text
ESS1 P很高
理论上需要ESS2多分担
```

但如果：

```text
ESS2已经接近CurrentLimit
```

就不能继续让ESS2加P。

或者：

```text
ESS1 Q / modulation已经紧张
```

即使P还没到硬边界，也说明整个GFM状态不宽裕，应降低继续扩大责任的速度/范围。

所以正常允许范围应该是：

```text
有功负担需求
×
设备执行能力
×
电压/频率健康许可
```

---

# 10. 完整ESS2恢复的阶段

## S14-60 Primary

已验证：

```text
Beta=1
Primary小权限
Secondary OFF
q-bias OFF
```

## S14-70 Frequency Secondary

新增：

```text
Primary继续
Frequency Secondary平滑打开
q-bias仍OFF
```

验收：

```text
持续频差明显减小
方向正确
无持续积分/限幅
V保持健康
```

## S14-80 Normal P Responsibility Release

新增：

```text
不再固定在commissioning小权限

启动ESS1 burden restoration
动态扩大ESS2正常P可用范围
```

ESS2开始真正承担正常孤岛有功责任。

## S14-85 Voltage q-bias Release

复用V4.8，但做黑启动适配：

```text
Vtarget = ESS1建网目标 / 1.0 pu
q-bias初值=0
only restored ESS2 available
从0缓慢投入
```

验收：

```text
V稳态偏差减小
ESS1 Q压力下降或保持健康
ESS2 current/modulation有余量
```

## S14-88 ESS2 Normal Restored

此时：

```text
ESS2物理并回
Coordinator owns P
Primary working
Frequency Secondary working
ESS1 burden restoration working
Voltage q-bias available/working
动态能力约束working
```

S14退出主动调度，只保留健康监视和故障/恢复管理。

---

# 11. Q-bias为什么不是“重新设计一套Q控制”

因为：

```text
中央慢电压误差
→ q-bias
→ 本地finalizer
→ current/modulation capability
```

这些都已存在。

黑启动只补：
- 正确的进入时机；
- 正确的目标初始化；
- 只给已恢复资源；
- 与Frequency Secondary独立使能。

所以属于“黑启动接入适配”，不是推翻V4.8。

---

# 12. 下一次改模建议一次完成基础设施

为了减少Build：

一次改模准备：

1. S14-70 Frequency Secondary
2. S14-80 Normal P Responsibility
3. S14-85 Voltage q-bias
4. S14-88 Normal Restored
5. 独立Frequency Secondary Enable
6. 独立Voltage q-bias Enable
7. ESS1 P/Q/current/modulation状态输入
8. ESS1 burden restoration
9. 动态ESS2 P能力边界
10. q-bias黑启动Vtarget/availability适配
11. 完整记录信号

但在正式测试中仍按：

```text
60
→70
→80
→85
→88
```

逐层自动投入。

不是一次全开。

---

# 13. 最终定义

ESS2完全正式恢复，不是：

```text
P=-某个固定值
```

也不是：

```text
固定authority=某个大数字
```

而是：

```text
ESS1保持唯一GFM主责任

ESS2：
物理并回
+
P主控权交给正常Coordinator
+
Primary
+
Frequency Secondary
+
基于ESS1负担的正常P分担
+
V4.8 q-bias电压辅助
+
动态current/modulation/capability约束
```

达到这里，才真正进入：

> ESS2黑启动后完全正式恢复并进入正常孤岛运行。
