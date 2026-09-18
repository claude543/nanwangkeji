# ESS2 下一阶段：频率、电压、Secondary 与“完全放开”设计冻结

日期：2026-09-18

## 一、最重要的结论

当前微电网不是“只设计一次、二次调频”。

必须同时区分两条控制轴：

```text
频率—有功轴：
f ↔ P

电压—无功轴：
V ↔ Q
```

当前黑启动阶段的实际结构是：

```text
ESS1 = 唯一GFM
负责建立并主要维持V/f

ESS2 = GFL
当前只承担P控制
Q外环保持关闭 / Q≈0
```

因此：

```text
Q外环不参与
```

完全不妨碍：

```text
Primary P-f
Secondary frequency restoration
```

因为频率Secondary本质上是：

```text
frequency error
→ active-power integral correction
→ ESS2 P command
```

它不依赖Q外环。

---

# 二、电压是不是不用管？

不是。

电压必须一直监控和约束。

只是当前阶段：

```text
主要电压责任
=
ESS1 GFM本地电压控制
```

而不是：

```text
ESS2 Q外环
```

当前策略的正确含义是：

> ESS2暂时不主动承担独立Q调节；ESS1 GFM先负责母线电压形成与主要Q平衡。

所以必须继续观察：

```text
PCC / island bus Vpu
ESS1 Q
ESS1 current
ESS1 modulation
ESS2 current
ESS2 modulation
```

如果：

```text
V正常
+
ESS1 Q/current/modulation余量健康
```

那么ESS2 Q≈0就是合理的正常角色。

如果后面发现：

```text
电压长期偏离
或
ESS1无功压力/调制压力过大
```

再单独引入ESS2 q-bias / voltage support。

---

# 三、当前模型里其实已经存在电压慢恢复结构

当前模型不是完全没有Voltage Secondary（电压二次恢复）概念。

历史架构已经明确：

```text
旧 Voltage Secondary VSEC
物理作用关闭

Frequency Secondary
保留
```

同时V4.8新增了：

```text
central q-bias coordinator
```

负责：

```text
PCC电压误差
→ 慢速q-bias
→ 各GFL q轴辅助
```

当前S14 central Stage2时：

```text
q-bias reset / off
```

所以这次ESS2恢复、接管和Primary试验没有把电压慢恢复一起打开。

这也是为什么当前数据能单独证明Primary，而没有混入Q/V新机制。

---

# 四、Q外环关闭为什么还能二次调频？

完全可以。

当前Coordinator源码实际是两条分开的慢控制：

```text
Secondary frequency:
psecn
→ dp_secondary
→ P修正
```

以及：

```text
slow voltage restoration:
vsecn
→ dv_secondary
→ voltage/Q方向修正
```

两条不是同一个控制量。

所以：

```text
ESS2 Q PI OFF
```

并不等于：

```text
Secondary frequency OFF
```

Secondary frequency只需要：

```text
频率测量
+
P调节能力
```

即可工作。

---

# 五、现有Coordinator是否已经“针对黑启动完善”？

不能说“全部完善”。

更准确：

> **Coordinator本来是正常孤岛协调器，现在已经做了关键的黑启动适配。**

已经适配并实测的包括：

```text
S14-aware availability
ESS2 available
ownership handover
Beta
CorrectionGain
ESS2 authority
Primary P-f
```

这些已经跑通。

但是当前还没有完成：

```text
S14-70 Secondary正式状态
```

当前事实：

```text
S14-60 = Primary-only
S14-70 = 规划
不是当前已实现动态状态
```

因此不能直接说：

```text
Coordinator黑启动全功能已经完成
```

---

# 六、当前Coordinator的Secondary本体是否能用？

从源码看，Frequency Secondary本体已经存在，而且设计上并不是“关闭后偷偷积分”。

关闭时：

```text
psecn = 0
```

真正打开且Coordinator Stage=3以后才：

```text
psecn
=
psecz + Ki_sec * frequency_error * Ts
```

同时还经过：

```text
sec_slew
```

限速。

所以它具备比较好的“从0开始、慢慢进入”的基础。

这意味着：

> 下一阶段不需要重新发明Secondary控制器。

需要的是：

```text
S14什么时候允许它进入
+
如何与电压慢恢复解耦
+
如何限制ESS2权限
```

---

# 七、为什么不能现在简单把Coordinator Stage从2切到3？

因为当前模型中：

```text
Coordinator Stage3
```

不仅会使Frequency Secondary具备积分条件，

中央：

```text
q-bias coordinator
```

也使用同一个S14-aware Coordinator Stage。

当前Stage2：

```text
q-bias off
```

而Stage3可能进入电压慢恢复逻辑。

如果我们简单：

```text
Stage2 → Stage3
```

就可能同时增加：

```text
Frequency Secondary
+
Voltage q-bias
```

两个新责任。

这会破坏：

> 每一轮只增加一种新控制责任

的原则。

---

# 八、所以下一步模型应该怎么改？

建议做一个“小而明确”的改模，不重写Coordinator。

## 1. 新增S14-70

```text
S14-70 = ESS2_COORD_SECONDARY_FREQ
```

条件：

```text
Restore-state7
Beta=1
Primary已稳定
ESS2 healthy
无严重限流/clip
保持明确dwell
```

进入后：

```text
Primary继续ON
Frequency Secondary ON
```

## 2. 第一轮Secondary试验继续保持Voltage q-bias OFF

也就是说：

```text
Secondary frequency = ON
Voltage Secondary/q-bias = OFF
ESS2 Q PI = OFF
```

只验证：

```text
P-f二次恢复
```

## 3. Secondary从0平滑进入

复用现有：

```text
psec reset when disabled
sec_slew
```

或者在S14侧再加一个明确的Secondary Gain 0→1。

优先选择最少新增状态的方案。

## 4. 小authority先不扩大

第一轮Secondary：

```text
仍使用当前小权限
```

不要同时：

```text
Secondary ON
+
authority大幅扩大
```

先证明Secondary方向和稳定性。

---

# 九、电压下一步怎么处理？

Frequency Secondary通过以后，再单独决定Voltage q-bias。

建议顺序：

```text
A. Primary-only          已完成
↓
B. Frequency Secondary  下一步
↓
C. Voltage/q-bias       单独验证
↓
D. 扩大ESS2 normal authority
```

如果B阶段数据表明：

```text
V一直健康
ESS1 Q/current/modulation余量充足
```

那么C甚至可以继续保持OFF，并把：

```text
ESS2 Q≈0
```

冻结成当前正常角色。

如果V/ESS1 Q压力不好，再做C。

---

# 十、“从小权限到完全放开”是否能实现？

能，但不能理解为：

```text
authority → 无限大
```

所谓“完全放开”应定义成：

> 从调试用小权限，扩大到由ESS1/ESS2实际能力和安全边界允许的正常运行权限。

当前：

```text
authority ≈ 0.001 pu
```

只是commissioning（调试）权限。

最终normal authority必须受：

```text
ESS1 GFM P reserve
ESS1 Q reserve
ESS1 current headroom
ESS1 modulation headroom

ESS2 P capability
ESS2 current headroom
ESS2 modulation headroom

V/f health
```

约束。

---

# 十一、正常权限怎样平滑扩大？

建议分两层。

## 第一层：控制使能平滑

例如Secondary：

```text
SecondaryEnable
→ gain 0→1
```

或利用现有：

```text
sec_slew
```

让二次功率修正从0慢慢建立。

## 第二层：能力范围扩大

不要运行中Python一点一点改：

```text
0.001
0.002
0.005
...
```

最终模型应该计算或至少选择：

```text
Approved Authority
```

再通过模型内部：

```text
AuthorityGain / limiter
```

平滑放大实际可用权限。

当前第一版可以先用：

```text
离线/首次Execute前批准一个保守上限
```

后续再升级成：

```text
ESS1 reserve supervisor
↓
动态authority
```

---

# 十二、现在模型需不需要改？

## 如果只想继续跑Primary小权限

不用改。

已经通过。

## 如果要进入真正的正常ESS2运行

需要小改。

至少要：

```text
1. 实现S14-70 Frequency Secondary
2. 明确Secondary平滑进入
3. 确保第一轮q-bias仍OFF
4. 保持当前小authority
5. 增加/确认ESS1 P/Q/current/modulation取证
```

这不是重做模型，而是补上恢复链最后一个正常控制阶段。

---

# 十三、什么时候可以开始扩大authority？

推荐：

```text
Primary小权限  已通过
↓
Frequency Secondary小权限 通过
↓
检查ESS1/ESS2真实余量
↓
扩大authority
```

所以：

> Secondary验证完成以后，才开始真正的“小权限 → 正常权限”扩展。

不是现在直接把0.001改成0.01/0.02。

---

# 十四、ESS2“正常恢复完成”的最终定义

建议冻结：

```text
物理并回
+
Restore-state7
+
Beta=1
+
Coordinator ownership
+
Primary正常
+
Frequency Secondary正常
+
电压由ESS1 GFM保持健康
+
ESS2 Q策略明确（首版Q≈0）
+
ESS1/ESS2无持续限流/clip
```

达到以上：

> ESS2已经完成黑启动后的正常恢复，并进入正常孤岛运行。

如果以后项目需要：

```text
ESS2主动Q/电压支持
```

再把它作为额外能力增加。

不是完成ESS2基本正常恢复的必选项。

---

# 十五、下一步建议冻结

下一步不要扩大功率，不要恢复PV/EV。

先做：

```text
当前S14-60 Primary-only
↓
小改模
↓
S14-70 Frequency Secondary
↓
保持小authority
↓
保持ESS2 Q PI OFF
↓
保持central q-bias OFF
↓
Frequency Secondary平滑投入
↓
观察频率能否从约50.234 Hz回到50 Hz附近
↓
同时观察：
Vpu
ESS1 P/Q/current/modulation
ESS2 current/modulation
↓
PASS后
开始扩大authority
```

这条路线既管频率，也不忽略电压，同时保持因果清晰。
