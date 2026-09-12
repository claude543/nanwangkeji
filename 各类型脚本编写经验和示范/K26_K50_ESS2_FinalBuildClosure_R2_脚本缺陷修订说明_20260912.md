# K26_K50｜ESS2 Final Build Closure R2 修订说明

日期：2026-09-12

## 1. R1 这次为什么会在 Scratch 阶段报 `normalizer inputs actual=2`

根因已经精确定位：

```matlab
add_block('simulink/Ports & Subsystems/Subsystem',normalizer,...)
```

从 Simulink 库复制出来的 `Subsystem` 模板**自带默认 `In1` 和 `Out1`**。

R1 随后又直接加入：

```text
In56
Demux56
Mux56
Out56
```

却没有先删除模板默认内容。

因此实际子系统内部是：

```text
默认 In1
新增 In56

默认 Out1
新增 Out56
```

所以外部端口自然变成：

```text
2 inputs
2 outputs
```

Postassert 要求 1/1，于是 Scratch 正确拦截：

```text
actual=2 expected=1
```

### 重要

报错发生在：

```text
Scratch apply
↓
Scratch postassert
```

且发生在 `save_system(scratch)` 之前。

正式模型的 backup/formal edit 尚未开始，因此：

> **当前正式磁盘模型没有被这个 Closure R1 修改，不需要回滚。**

## 2. 这次为什么必须承认是没有真正落实仓库经验

仓库中 LOCAL15 的成熟脚本反复使用：

```matlab
add_block('simulink/Ports & Subsystems/Subsystem',sub,...);
localDeleteSubsystemContents(sub);
```

例如 S03、S09、S10、S11、S13、S15 都采用这一模式。

也就是说：

> **“从库复制 Subsystem 后先清空默认内容，再自己建 Inport/Outport”本来就是已有项目经验。**

Closure R1 忘记调用这一层，是脚本编写遗漏，不是 Simulink 不可预测行为。

## 3. 为什么前一轮 Harness 也没有发现

R1 的 Harness 验证的是：

```text
Constant 56x1
↓
顶层 Demux56
↓
顶层 Mux56
↓
Terminator
```

它证明的是：

```text
Demux56 -> Mux56 的维度正规化方法可编译
```

但生产 Patch 实际做的是：

```text
创建一个库 Subsystem 模板
↓
在里面加 Demux/Mux
```

Harness 没有复刻“创建 Subsystem 模板”这一步。

所以它没有覆盖：

```text
模板默认 In1/Out1
```

这叫：

> **测试构造与真实构造不等价。**

R2 已修正：Harness 现在与正式 Patch 使用**同一个 `buildVectorNormalizerSubsystem()`**。

## 4. R2 采用仓库成熟模板

正式和 Harness 都固定：

```text
add library Subsystem
↓
Simulink.SubSystem.deleteContents
↓
断言：
  external inputs = 0
  external outputs = 0
  direct children = EMPTY
↓
创建：
  In56
  Demux56
  Mux56
  Out56
↓
断言 direct child set 必须且只能：
  In56 / Demux56 / Mux56 / Out56
↓
断言 external ports = 1 in / 1 out
↓
断言 56条 Demux->Mux 连线
```

所以默认 `In1/Out1` 不可能再静默残留。

## 5. 改模范围没有变化

R2 仍然只做：

```text
A. Executor readyBasic 唯一语法修复
B. G27:
   Repack 56x1
   → Normalizer
       Demux56
       → 56 scalar
       → Mux56
   → OpWrite
```

以下继续不动：

```text
stage
return 45维
Power Loop
Current Adapter算法
Restore状态机逻辑
G27 Repack算法
S14
Breaker Router
OpWrite数量
PV/EV
SPS
```

## 6. 执行

R1 废止。

现在只运行：

```matlab
result = PATCH_K26_K50_ESS2_FINAL_BUILD_CLOSURE_R2;
```

必须返回：

```text
FINAL_BUILD_CLOSURE_SAVED_AND_PERSISTENCE_VERIFIED
```

然后：

```matlab
result = VERIFY_K26_K50_ESS2_FINAL_BUILD_CLOSURE_R2;
```

必须返回：

```text
ESS2_FINAL_BUILD_CLOSURE_VERIFIER_PASS
```

再 RT-LAB Rebuild。

Patch R2 SHA256：

```text
bd333652ffbcdb1079f7755c9eba8ae46fe8ac1ba7374f9aa4994a7376bfb705
```

Verifier R2 SHA256：

```text
fa4f995d529d27e6fa4f598733c4842f9510694d1db0d84513653b7e7f922e69
```
