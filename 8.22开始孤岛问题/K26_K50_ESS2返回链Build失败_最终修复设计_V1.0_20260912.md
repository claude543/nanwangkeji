# K26_K50｜ESS2 返回链 Build 失败最终修复设计 V1.0

日期：2026-09-12  
当前模型：已经成功保存 ESS2 Physical Restore R3，第一次 RT-LAB Build 在 SS_Slave2 返回包处失败。  
本文件依据：最新专项审计 `ESS2_RETURN_PATH_AUDIT_COMPLETE_REPAIR_CONTRACT_READY`。

---

## 1. 专项审计已经确认的事实

当前模型三个核心算法 SHA 与成功 R3 完全一致：

```text
Current Adapter
1414737b8b1672f6bbadf27a6112fe95efc129dab9a13a1db921926519035223

Restore Executor
c804d9922cde1c0a7b6ea56fa0472606670e9bb69441cba8eb38d85cf4e1260a

G27 Repack
2ac83fa7ac262f2f61be6b58bb8148ecbba9cba09a1e1556ba8efd043668f959
```

说明 Build 失败以后当前磁盘模型仍是我们预期的 R3 版本，不存在算法被意外改变的问题。

真实返回链：

```text
SS_Slave2/Mux
Inputs = 6
↓
AA15_V48_RETURN_APPEND_MUX
Inputs = [30 3]
↓
Memory
IC = zeros(45,1)
↓
ESS_Pmeas_vec2_to_SM
↓
SS_Slave2 out1
↓
SM_Master in2
↓
OpComm3 input2 / output2
↓
SM_Master/Demux1
[1 1 1 1 26 3 12]
```

`Memory input1` 的真实直接 source 已确认就是：

```text
AA15_V48_RETURN_APPEND_MUX out1
```

因此 Build 报：

```text
AA15_V48_RETURN_APPEND_MUX output = 33
Memory expects = 45
```

不是推测，而是端到端链路证据。

---

# 2. R3 错在哪里

仓库历史成功结构：

```text
SS_Slave2/Mux
5 inputs
↓
legacy 30

AA15_V48_RETURN_APPEND_MUX
[30 3]
↓
33
↓
Memory
```

R3 错误地把 12维 Restore Executor 输出接到了：

```text
SS_Slave2/Mux input6
```

但是没有修改真正的最终追加层：

```text
AA15_V48_RETURN_APPEND_MUX
```

于是：

```text
前级虽然多了12维
但最终 append 仍坚持 [30 3]
↓
输出仍然33
↓
Memory要求45
↓
Build失败
```

---

# 3. 还存在第二个必须同时关闭的风险

Restore Executor MATLAB Function 明确：

```matlab
y=zeros(12,1)
```

所以它是显式：

```text
12×1 column
```

仓库 V4.9 已经发生过：

```text
MATLAB Function Nx1
↓
grouped signal保留matrix dimensionality
↓
OpComm
↓
Signal is a matrix
```

真正成功的修复经验是：

```text
MATLAB Function Nx1
↓
scalar Demux
↓
scalar signals
↓
classic Mux
↓
普通 vector
```

因此这次绝不能简单：

```text
Executor 12×1
→ RETURN_APPEND
```

否则很可能修完 33/45 后，下一次 Build 又卡在 matrix。

---

# 4. 本次最终修复结构

冻结为：

```text
Restore Executor 12×1
        ↓
已有 AA15_ESS2_RESTORE_EXECUTOR_DEMUX
        ↓
12个 scalar
        ↓
新增 AA15_ESS2_RESTORE_STATUS_MUX12
        ↓
标准12元素 vector
        ↓
AA15_V48_RETURN_APPEND_MUX input3
```

完整返回链：

```text
原 legacy Mux
5 inputs
→ 30维
                  ┐
原 V4.8 CAP 3维 ──┼→ AA15_V48_RETURN_APPEND_MUX
                  │   [30 3 12]
Restore Mux12 ────┘
                        ↓
                       45维
                        ↓
                 Memory=zeros(45,1)
                        ↓
             ESS_Pmeas_vec2_to_SM
                        ↓
               SS_Slave2 out1
                        ↓
                SM_Master in2
                        ↓
                 OpComm3 port2
                        ↓
       Demux1=[1 1 1 1 26 3 12]
```

---

# 5. 实际修改只有三处

## 修改1：恢复 legacy Mux

```text
SS_Slave2/Mux

Inputs:
6 → 5
```

这会去掉错误的：

```text
Restore Executor -> Mux input6
```

原1~5输入必须完整保持：

```text
1 Bus Selector1
2 Bus Selector2
3 AA15_INV_VAB_DIAG
4 AA15_LCOUT_VAB_DIAG
5 ESS1_Control output3
```

## 修改2：新增 scalar-normalization Mux

```text
SS_Slave2/AA15_ESS2_RESTORE_STATUS_MUX12
```

输入：

```text
Executor_Demux output1 → Mux12 input1
...
Executor_Demux output12 → Mux12 input12
```

原有：

```text
output2 → ESS2_Control input10
output3 → ESS2_Control input9
output5 → breaker router input1
```

全部保留，只新增分支。

## 修改3：修改真正的最终 append 层

```text
AA15_V48_RETURN_APPEND_MUX

[30 3]
→
[30 3 12]
```

新增：

```text
input3 ← RESTORE_STATUS_MUX12
```

---

# 6. 明确保持不动

以下全部保持：

```text
Memory = zeros(45,1)

SM_Master/Demux1
= [1 1 1 1 26 3 12]

SM->SS2 ESS_Group 25维

Restore Executor代码

Current Adapter代码

Power Loop

Breaker router

G27

OpWrite数量=5

PV/EV

SPS物理网络
```

因此这是一次真正的局部接口修复，不重新碰已经通过 Patch R3 持久性验证的控制设计。

---

# 7. 为什么这次比前面更严格

Patch 的 hard preflight 会逐端口要求当前坏模型必须恰好是：

```text
legacy Mux input1..6
每一个source/port完全匹配

append Mux input1..2
source完全匹配

append -> Memory
Memory -> task out
SS2 out1 -> SM in2
SM in -> OpComm3 in2
OpComm3 out2 -> Demux1
Demux1各关键消费者
```

同时要求：

```text
Executor output1
当前恰好只有：
- Executor_Demux input1
- G27 repack input5
- legacy Mux input6
```

如果任何一项不一样：

```text
PATCH ABORT
```

不会猜。

修完以后再逐项检查：

```text
Executor output1
只能剩：
- Executor_Demux
- G27 repack

12个 Demux scalar
每一个都必须进入 Status Mux12

output2/3/5原消费者必须同时保留

Status Mux12
只能进入 RETURN_APPEND input3
```

所以这次不再只是“Inputs参数看起来对”。

---

# 8. 事务

仍采用：

```text
正式磁盘模型只读preflight
↓
字节相同scratch
↓
scratch修改
↓
完整postassert
↓
scratch save exactly once
↓
close/reload
↓
再次postassert
↓
正式整文件backup
↓
正式re-preflight
↓
同一最小修改
↓
完整postassert
↓
正式save exactly once
↓
close/reload
↓
最终postassert
```

正式保存以后失败：

```text
whole-file rollback
+
SHA核验
```

---

# 9. Patch后验证

先运行独立 Verifier。

只有：

```text
RETURN_PATH_FIX_SAVED_AND_PERSISTENCE_VERIFIED
+
ESS2_RETURN_PATH_FIX_VERIFIER_PASS
```

都成立，才重新：

```text
RT-LAB Rebuild All
```

Build仍然是：

```text
compiled width
+
compiled dimensionality
```

的最终裁判。

不能用静态审计代替 Build。

---

# 10. 对“无死角”的准确表述

在**当前已知 Build 错误、当前返回链结构、以及仓库已经出现过的 vector/matrix 维度故障类型**范围内，本次修复已经把两个直接风险同时关闭：

1. `33 -> 45` 元素宽度断裂；
2. `12×1 MATLAB Function column -> OpComm matrix` 潜在故障。

同时不扩大修改面。

但任何静态 MATLAB 脚本都不能数学上保证 RT-LAB/ARTEMiS 编译器不会暴露另一个此前不可见的 compiled-only 问题。

因此工程上的“冻结标准”是：

```text
结构无未知
+
端到端接口无未知
+
历史已知维度风险已处理
+
Patch/Verifier双PASS
+
最终由RT-LAB Rebuild验证compiled contract
```

这比承诺“绝不可能再有任何Build错误”更准确。
