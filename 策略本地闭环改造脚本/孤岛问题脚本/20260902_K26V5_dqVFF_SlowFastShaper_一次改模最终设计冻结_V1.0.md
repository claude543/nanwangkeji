# K26_V5｜dq-VFF Slow/Fast Shaper 一次改模最终设计冻结 V1.0

> 日期：2026-09-02  
> 当前模型 SHA256：`4812ad1f1acca23173576ee92a926ce8727dc65fa2b3ee62debcd5c44801d36b`  
> 依据：post-Mode6 只读审计全部核心 Gate PASS。  
> 本文件冻结的是**第一次工程根因修复 Harness**，不是宣称某组参数已经是最终最优参数。

---

# 1. 审计已经排除的结构风险

五台 GFL：

```text
PV1 / PV2 / ESS2 / EV1 / EV2
```

全部确认：

```text
old C1
→ C1 axis wrapper
→ Current Regulator/in1
```

同时 logger input5 与 Current Regulator/in1 使用的是同一个 final applied Vdq。

更关键的是 Current Regulator 内部：

```text
in1 VdVq_meas
↓
Demux
├─ Vd → Add1/in1，符号 +
└─ Vq → Add3/in1，符号 +
```

没有其它 fanout。

所以：

> 在 Current Regulator/in1 外部整形这一个二维 Vdq 输入，数学上只会改变我们已经锁定的 `+Vd/+Vq direct terminal-voltage feedforward`，不会改变 Current PI、Rff/Lff 或电流误差。

因此外部插入点正式冻结。

---

# 2. 为什么这次不再修改 Current Regulator 内部

内部真实公式仍保持：

```text
FF_d = shaped_Vd + Rff*Id_ref - Lff*Iq_ref
FF_q = shaped_Vq + Rff*Iq_ref + Lff*Id_ref

Vconv = Current_PI + FF
```

只把：

```text
Vd_meas / Vq_meas
```

换成：

```text
shaped_Vd / shaped_Vq
```

其余所有项原样保留。

这是当前最小侵入修复。

---

# 3. 新模块：AA15_VFF_DQ_SHAPER

输入：

```text
1. RawVdq          [2]
2. Mode7Enable     [1]
3. HoldStep        [1]
```

输出：

```text
1. FinalVdq        [2]
2. Vslow           [2]
3. Kfast_eff       [1]
4. Kfast_target    [1]
```

其中 HoldStep 继续复用已经验证的：

```text
AA15_C_HOLD_STEP
1 → 0 @ 8.1894s
```

---

# 4. SlowTracker 具体算法

不用 MATLAB Function。

只用：

```text
Unit Delay
Sum
Product
Constant
Saturation
```

离散一阶：

```text
Vslow[k]
=
Vslow[k-1]
+
alpha * (Vraw[k] - Vslow[k-1])
```

d/q 使用同一个 alpha 和同一个二维状态，因此保持轴向对称。

从 t=0 开始持续 warm-up。

---

# 5. 最终 feedforward 动态

```text
Vfast = Vraw - Vslow

Vshaped
=
Vslow
+
Kfast_eff * Vfast
```

也可以写成：

```text
Vshaped
=
Vraw
-
(1-Kfast_eff)*(Vraw-Vslow)
```

---

# 6. exact bypass 设计

这是本版相比简单公式更重要的安全改进。

Mode0～6：

```text
FinalVdq = RawVdq
```

由独立 Switch 直接旁路，不经过任何 slow/fast 数学运算。

所以历史 Mode0～6 在模型结构上保持 exact bypass。

Mode7 在 8.1894s 之前也：

```text
FinalVdq = RawVdq
```

SlowTracker 虽然一直 warm-up，但不参与输出。

只有：

```text
Mode7 = 1
且
t >= 8.1894s
```

以后才把 `Vshaped` 接入 Current Regulator。

因此：

```text
过去所有因果模式不被重新定义
+
Mode7干预前完全透明
```

---

# 7. Kfast 采用有界、平滑状态

运行时参数：

```text
AA15_VFF_KFAST_ISLAND
AA15_VFF_KFAST_SLEW
```

模型内部强制：

```text
Kfast_island ∈ [0,1]
abs(Kfast_slew)
```

Kfast 状态初值：

```text
1
```

目标：

```text
Mode7且t<8.1894:
1

Mode7且t>=8.1894:
Kfast_island

Mode0~6:
1
```

更新：

```text
delta = target - Kfast_state

delta_limited
=
clip(delta, -slew, +slew)

Kfast_next
=
Kfast_state + delta_limited
```

因此不会由于一次参数误设得到负 Kfast 或大于1的 target。

---

# 8. 第一轮默认值

`Ts = 100 us`。

第一轮：

```text
fc = 1 Hz
alpha = 0.000628121179965135

Kfast_island = 0

Kfast_slew = 0.01 / sample
```

`0.01/sample` 表示：

```text
1 → 0
约100个采样
≈10ms
```

这些是第一轮**机制闭环参数**，全部可在新 Build 中运行时修改，不需要再 Build。

---

# 9. Mode7 完整合同

新增：

```text
Mode7 = DQ_VFF_SLOW_FAST_SHAPER
```

Mode7：

```text
old C1 = TRACK
C2 = TRACK
D axis = TRACK
Q axis = TRACK
```

只有新 shaper 起作用。

时间：

```text
0 ~ 8.1894:
exact raw bypass
SlowTracker warm-up
Kfast=1

8.1894:
ShapeActive=1
Kfast target -> Kfast_island

8.1894 ~ ≈8.1994:
Kfast平滑1→0

≈8.1994 ~ J1:
Kfast≈0
强网clean settle

≈8.2093:
J1 OPEN
```

---

# 10. diag30

原 scalar01～26 全部保留原语义。

特别是：

```text
07/08 raw Vd/Vq
09/10 final applied Vd/Vq
11/12 Current PI
13/14 Vconv
22 Mode
23/24 old C1/C2
25/26 D/Q axis track
```

新增：

```text
27 Vslow_d
28 Vslow_q
29 Kfast_eff
30 Kfast_target
```

不记录 Vfast：

```text
Vfast = raw - Vslow
```

离线可精确计算。

新宽度：

```text
G26 = 60
G27 = 30
G28 = 60
```

logger块旧名字虽然仍含 `24SCALAR`，为避免破坏已有路径不重命名，只改变其实际输出为30。

---

# 11. OpWrite 最终决策

本次**不删除现有诊断量**。

原因不是保守堆数据，而是：

- diag01~26 仍分别用于排除 P/Q、PI、饱和、PLL、slow-slip 等失败机制；
- G30 虽然含很多旧 handover 诊断，但现在重接/裁剪它会引入与控制修复无关的结构风险；
- 当前最重要的是保证第一次工程闭环没有数据盲区。

因此只改变采样 Decimation：

```text
G26: 2 → 4
G27: 2 → 4
G28: 2 → 4
G29: 2 → 4

G30: 5 → 10
```

根据历史实测文件长度，这会把可记录时间大致从约8秒扩大到约16秒，同时降低写盘负担。

新的时间分辨率：

```text
G26~G29:
0.4ms

G30:
1ms
```

对：

```text
10.6Hz
17Hz
50Hz基波
0.5~1s slow-slip
```

仍然充分。

OpWrite数量仍然严格=5。

---

# 12. 为什么 G30 不删旧量

G30 当前已经确认包含：

```text
ESS1 Fref
ESS1 Fout
ESS1 theta
ESS1 PLL frequency
ESS1 Vabc
P/Q droop feedback
Droop On
GridOn
theta_PLL
theta_target
J1 state
F20/F22/F23/F24/F25 diagnostics
```

下一轮我们第一次要同时证明：

```text
fast instability消失
+
C1 slow-slip没有回来
```

所以第一次工程修复不适合在同一 Build 再“重构诊断系统”。

完成修复闭环以后再做 logger cleanup，风险更合理。

---

# 13. Patch 保存前必须满足

五台全部：

```text
Mode0~6仍在
Mode7新增且不连入旧C1/C2/axis hold logic

axis wrapper output
→ shaper/in1

shaper/out1
→ Current Regulator/in1
→ logger/in5

shaper/out2
→ logger/in20

shaper/out3
→ logger/in21

shaper/out4
→ logger/in22
```

并证明：

```text
Current Regulator/in1 source = shaper/out1
logger input5 = shaper/out1
```

---

# 14. Compile 必须满足

每台：

```text
shaper in widths  = [2 1 1]
shaper out widths = [2 2 1 1]

CurrentReg/in1 = 2
logger output = 30
```

Groups：

```text
G26 = 60
G27 = 30
G28 = 60
G29 = 38
G30 = 115
```

OpWrite：

```text
exactly 5
```

Decimation：

```text
4 / 4 / 4 / 4 / 10
```

---

# 15. 保存后还必须再做一轮

```text
close
reload
compile
```

重新证明：

```text
结构仍在
Mode default=0
diag30宽度正确
OpWrite参数持久化
Dirty=off
```

任何失败：

```text
自动恢复完整SLX backup
```

---

# 16. 为什么还要独立 PREBUILD VERIFY

Patch 自己通过不等于立刻 Build。

还需要第二个完全独立的只读 verifier：

```text
VERIFY_K26_V5_VFF_DQ_SHAPER_PREBUILD_V1.m
```

再次读取已经保存的模型，验证：

```text
SHA变化
Mode7
shaper代数连接
exact bypass
logger semantics
G26~G30 widths
Decimation
OpWrite count
```

只有：

```text
PATCH PASS
+
PREBUILD VERIFY PASS
```

两份独立结果都通过，才允许 RT-LAB Rebuild All。

---

# 17. 本次能承诺和不能承诺的内容

可以非常高置信度承诺：

```text
修改位置精准
不会改变PI/Rff/Lff/PQ/PLL
Mode0~6保持exact bypass
Mode7数据接口足够
0.5~1s后续分析不会因原OpWrite时长再次缺数据
```

不能在试验前科学地承诺：

```text
fc=1Hz/Kfast=0
一定已经是最终性能最优参数
```

但它是由四角因果证据直接导出的最强第一轮工程验证。

如果它失败，仍然可以在同一 Build 中改变：

```text
alpha/fc
Kfast
slew
```

而无需再次改模型。

这就是本次“一次 Build 把实验能力做完整”的核心。
