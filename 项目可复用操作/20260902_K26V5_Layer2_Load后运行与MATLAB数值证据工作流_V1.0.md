# K26_V5｜Layer-2 Load 后运行 + MATLAB 数值证据工作流 V1.0

> 日期：2026-09-02  
> 本工作流只适用于 Layer-2 Patch/Verify/Rebuild 全部成功后的新 Build。

# 1. 本轮工具分工

## Python

只负责：

```text
Reset/Load 后状态检查
五台运行参数 exact discover
五台参数 write/readback
六机成熟 staging
ESS1 GFL→GFM
F24/F25
P/Q COMMIT
8.1894s 干预
J1真实开断
J1后至少3s Evidence-First观察
运行到共同logger落盘边界
manifest
PAUSED结束
```

Python不做：

```text
根因判决
模态最终判断
慢塌陷是否被“解决”的自动结论
```

---

## MATLAB

只负责：

```text
自动找五类MAT
合并segment
row-map
模型本地边沿
逐点VFF/Iref公式验证
20ms RMS
电压下降斜率/阈值/积分
8~25Hz统一模态拟合
五台Current PI慢斜率
五台P/Q/频率
ESS1 VPI→Iref→actual current→Vconv链
F25限制器事件时间线
电压有效条件下的PCC零交越频率
结构化CSV/MAT/Markdown
```

MATLAB不自动宣布：

```text
根因是谁
哪一模式成功
下一轮跑什么
```

---

# 2. Python 新 Build 硬合同

第一次 Execute 前必须找到并回读：

```text
五台 AA15_CAUSAL_MODE

五台 Mode7：
AA15_VFF_SLOW_ALPHA
AA15_VFF_KFAST_ISLAND
AA15_VFF_KFAST_SLEW

五台 Layer-2：
AA15_L2_MODE
AA15_L2_KSLOW_TARGET
AA15_L2_KSLOW_SLEW
AA15_L2_KPQ_TARGET
AA15_L2_KPQ_SLEW
```

共：

```text
5 causal mode
15 Mode7 params
25 Layer-2 params
```

Layer-2内部：

```text
Vanchor
Kslow_eff
Ianchor
Kpq_eff
```

不要求 RT-LAB 在线导出。

最终由 MAT diag41 硬证明。

---

# 3. 第一轮运行模式

脚本顶部：

```python
L2_RUN_MODE = 0
```

第一轮不得修改。

科学意义：

```text
CAUSAL_MODE=7
L2_MODE=0

Layer-2 exact bypass
↓
新Build应复现当前Mode7
```

必须先看到：

```text
原10~17Hz共同快速正增长仍被抑制
+
当前慢电压塌陷仍按相近时间尺度存在
```

才能证明：

```text
新Build没有偷偷改变基线
```

---

# 4. 后续模式

只有 Mode0 数值证据完成判断后：

```text
Mode1
只降低慢端口电压前馈
Kslow target第一刀=0.5

Mode2
只降低P/Q动态电流指令
Kpq target第一刀=0.5

Mode3
两者同时
只在Mode1/2都显示贡献但单独不足时运行
```

不做：

```text
0.4/0.3/0.2无目标扫描
```

0.25或0只在已有剂量响应证据后使用。

---

# 5. 时间合同

仍使用：

```text
干预目标时刻：8.1894s
J1命令：约8.2092s
```

因此约20ms：

```text
干预已经进入
但强网仍连接
```

用于验证干预本身是否先破坏强网。

J1后：

```text
0~0.2s 快速问题
0.2~1s 慢塌陷形成
1~3s 长期PI/频率/功率演化
```

Python必须至少运行到：

```text
J1 + 3s
```

然后继续到 G26~G30 的下一个共同完整 block 边界。

按当前固定时序：

```text
下一共同边界≈12.0s
最终Pause≈12.02s
```

---

# 6. MAT合同

Layer-2 Build预期：

```text
G26 83 rows
G27 42 rows
G28 83 rows
G29 39 rows
G30 129 rows
```

都包含 Target Time 行。

GFL每台 diag41：

```text
01~30 原Mode7语义保留
31/32 Vanchor d/q
33 Kslow_eff
34 Kslow_target
35/36 Ianchor d/q
37/38 Layer-2最终Iref d/q
39 Kpq_eff
40 Kpq_target
41 L2_MODE
```

MATLAB必须逐点验证：

```text
最终Vdq公式
最终Iref公式
最终Iref是否真正传到下游
```

---

# 7. ESS1新增数值证据

G30 append：

```text
VPI raw dq
Iref saturation前 dq
Iref saturation后 dq
实际 Id/Iq
Vconv dq
Vq测量
Vq参考
Vd测量
```

MATLAB自动计算：

```text
Vq error
Iref saturation residual
Iref→actual current tracking error
Vconv magnitude
```

再与已有F25：

```text
slew
magnitude
 timeout
```

首次动作时间比较。

---

# 8. 低电压频率规则

不再允许：

```text
电压已经塌到很低
仍用裸零交越得到100/150Hz
然后称为物理频率
```

新版 MATLAB：

```text
20ms RMS voltage >= 0.70pu
```

才允许该周期进入 PCC zero-cross frequency 统计。

同时始终保留：

```text
ESS1 Fout
ESS1 theta derivative
```

作为构网频率主线证据。

---

# 9. 正式执行顺序

```text
Layer-2 Patch PASS
↓
Layer-2 PREBUILD VERIFY PASS
↓
RT-LAB Rebuild All
↓
Reset
↓
Load
↓
MODEL_PAUSED @ t=0
↓
运行 RUN_K26_V5_LAYER2_CAUSAL_20260902.py
（第一轮 L2_RUN_MODE=0）
↓
模型最终PAUSED
↓
不要Reset
↓
运行 MATLAB：
result = ANALYZE_K26_V5_LAYER2_CAUSAL_RUN_V1_0('...\\models\\K26_V5');
↓
保全数值证据
↓
再做因果判断
↓
最后Reset
```
