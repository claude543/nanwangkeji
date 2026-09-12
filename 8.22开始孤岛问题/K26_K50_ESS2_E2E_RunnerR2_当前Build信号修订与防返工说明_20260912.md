# K26_K50｜ESS2 物理恢复 E2E Runner R2 最终修订说明

日期：2026-09-12  
当前 Build：`K26_K50_CLEAN_P1` 已 Build 成功。  
依据：

1. 仓库成功 Runner：`RUN_K26_K50_LOCAL_S14_STAGE1_GATEA_R2.py`
2. 仓库脚本经验：`20260911_脚本编写_模型审计_RTLAB运行_DirectMAT计算_经验教训与正确示范_V1.0.md`
3. 用户本机当前 Build 只读诊断：
   - `candidate_analysis.json`
   - `matching_signal_rows.csv`
   - `signal_discovery.txt`

---

# 1. 上一版为什么失败

上一版 Runner 把新恢复状态假设成：

```text
SS_Slave2/AA15_ESS2_RESTORE_EXECUTOR_DEMUX/port1..12
```

但当前 Build 的 `GetSignalsDescription()` 明确：

```text
这12个外层 Demux port
= 0 row
= 没有作为在线动态信号暴露
```

S14 stage 同样不是：

```text
.../AA15_Black_Start_Pref_Gate/port9
```

实际当前 Build 暴露的是：

```text
.../AA15_Black_Start_Pref_Gate/
AA15_Black_Start_Pref_Gate_Core/port9
```

另外，Executor `CORE/port1(i)` 虽然能看到 `y(i)`，但当前 Build 同一个文本 path
又出现 `signal1(i)`，且 `signal1` 一直扩到29维。

因此：

```text
CORE/port1(i)
```

不是一个适合直接作为在线语义硬绑定的路径。

R2 不再使用：

```text
EXECUTOR_DEMUX port1..12
CORE/port1(i)
```

作为运行时硬门。

---

# 2. R2 使用当前 Build 真正唯一的模型局部证据

## 2.1 状态机内部状态

当前 Build 唯一暴露：

```text
StateZ/port1(1) = state
StateZ/port1(2) = readyCount
StateZ/port1(3) = postCount
StateZ/port1(4) = releaseAlpha
StateZ/port1(5) = failCode
```

这正对应冻结 Executor：

```text
z = [state, readyCount, postCount, releaseAlpha, failCode]
```

因此 R2 在线状态机判断使用 StateZ，不再猜 `y(1..12)` 路径。

## 2.2 Executor真正使用的48维延迟诊断

当前 Build 唯一暴露：

```text
Diag48_Z1/port1(3)  FinalIdRef
Diag48_Z1/port1(4)  FinalIqRef
Diag48_Z1/port1(5)  IdMeas
Diag48_Z1/port1(6)  IqMeas
Diag48_Z1/port1(15) ModIndex
Diag48_Z1/port1(16) Pmeas
Diag48_Z1/port1(17) Qmeas
Diag48_Z1/port1(19) PLL_Hz
Diag48_Z1/port1(21) Vpu
Diag48_Z1/port1(26) PrefEff
Diag48_Z1/port1(28) QrefEff
Diag48_Z1/port1(35) CurrentLimit
Diag48_Z1/port1(37) MasterF_Hz
Diag48_Z1/port1(42) RawModDemand
Diag48_Z1/port1(43) ModHeadroom
```

这些量就是 Executor 判断 READY / PostOK 时使用的模型局部输入。

所以 Python 不再依赖一个外层未暴露的 `ready` 信号，而是按**同一个公式**重建当前判断：

```text
ReadyNow =
Vpu范围
+ df
+ Iref
+ Imeas
+ CurrentLimit
+ ModHeadroom
```

Phase / Vmatch gate 本轮冻结 OFF，所以这个重建与当前 Executor 的实际有效 READY 条件一致。

PostOK 同理：

```text
PostOKNow =
post V range
+ Imeas
+ CurrentLimit
```

---

# 3. S14 Stage当前Build路径冻结

本轮在线 S14 stage 使用当前 Build 已经明确存在的：

```text
K26_K50_CLEAN_P1
/SM_Master
/AA15_LOCAL_CONTROL_STACK
/AA15_Black_Start_Pref_Gate
/AA15_Black_Start_Pref_Gate_Core
/port9
```

语义：

```text
stage_echo
```

这比继续猜：

```text
SS2 Demux port3
```

或外层 Subsystem port9 更符合项目规则：

> 当前 Build Target 暴露什么，就绑定什么。

---

# 4. Signal discovery 规则也修正

旧逻辑：

```text
GetSignalsDescription
↓
description row 数量 >1
↓
直接判 ambiguous
```

R2：

```text
GetSignalsDescription
↓
先按 normalized path 去重
↓
判断 DISTINCT path 数量
↓
唯一实际path
↓
GetSignalsByName(path)
↓
必须返回1个有限标量
```

也就是说：

```text
同一个path出现2条description row
!=
两个不同信号path
```

但 R2 仍然不会：

```text
多条不同path
→ 取第一条
```

多个 distinct path 仍然 hard fail。

---

# 5. Gate A/B/C现在使用什么

## Gate A：允许第一次合ESS2

必须同时：

```text
StateZ state = 3 READY
ReadyNow = true
readyCount已经达到0.5s dwell
alpha = 0
failCode = 0
final ESS2 breaker = OPEN
S14仍Stage1
```

## Gate B：允许继续零功率接入

必须：

```text
StateZ state = 5 CONNECTED_ZERO
final breaker = CLOSED
alpha = 0
PostOKNow = true
Stage1期间 ReadyNow仍健康
failCode = 0
```

## Gate C：允许释放ESS2功率

必须：

```text
仍为State5
PostOKNow = true
S14 Stage2
ESS2 Pcmd有意义
其余PV/EV/ESS1 Pcmd=0
PCC V在0.8~1.2pu
PCC f在48~52Hz
ESS2 PLL-master df <=0.5Hz
ModHeadroom >=0.05
```

然后才：

```text
MANUAL_RELEASE 0→1
```

---

# 6. Runtime参数漂移保护

每个 Pause checkpoint 不再把全部历史参数机械读一遍。

只检查会破坏本轮解释/物理动作的关键项：

```text
S14 enable/source
五个legacy branch command
restore MASTER/source/request/AUTO
breaker/release enable
phase/vmatch/abort gate
MANUAL_COMMIT
MANUAL_RELEASE
```

其中 Commit/Release 的期望值由 Runner 自己的事件状态决定。

---

# 7. 已经做过的软件级完整走通测试

R2 生成后执行了：

```text
Python py_compile
AST语法检查
禁止Reset/Load扫描
新Build路径与用户上传CSV逐项对照
Signal resolver空/重复path自测
Restore predicate纯函数自测
```

并另外构造了一个 Mock RT-LAB：

```text
PAUSED@0
→ 参数发现
→ 信号发现
→ t=0写参/readback
→ 0~12s
→ Gate A
→ Commit
→ Gate B
→ Stage2
→ Gate C
→ Release
→ Alpha 0→0.5→1
→ State7
→ 35s Pause
```

整条 `main()` 实际走到：

```text
CAPTURE_COMPLETE_NO_ELECTRICAL_VERDICT
```

而不是只检查局部函数。

这次 Mock 不是物理验证，只用于排除：

```text
NameError
Phase变量遗漏
事件flag错误
Gate逻辑自相矛盾
时间轴代码断裂
manifest流程错误
```

---

# 8. DirectMAT也同步修正为R2

上一版 Analyzer 还存在一个潜在后处理问题：

```text
G27 56通道没有直接保存 status(12)=PostOK
```

但旧 Analyzer 直接访问了：

```text
E.PostOK
```

R2 已改为：

```text
使用G27现存：
Vpu
Id/Iq measured
CurrentLimit

+
Runner manifest里的post阈值
↓
离线重建 PostOKDerived
```

并明确**不尝试从G27重建 Ready**，因为原 G27 channel37 `MasterF_Hz`
已被恢复日志重映射为 `PowerReleaseAllowed`；Ready直接使用已记录的
`ReconnectReady` channel32。

---

# 9. 操作

如果当前模型仍然：

```text
MODEL_PAUSED @ t=0
```

不需要因为前面诊断失败而 Reset。

直接运行 R2 Runner。

如果 Runner 自己发现：

```text
target clock != 0
```

它会在任何写参 / Execute 之前明确要求：

```text
Reset → Load
```

否则不要额外Reset。

---

# 10. 文件

Runner：

```text
RUN_K26_K50_LOCAL_S14_ESS2_PHYSICAL_RESTORE_E2E_R2.py
SHA256
dc734ab58ced98f44841c2d1f04801a75b9ed1c23f6942adf43a975392332332
```

Analyzer：

```text
ANALYZE_K26_K50_LOCAL_S14_ESS2_RESTORE_E2E_R2.m
SHA256
a2342a58074c919f65372147d525620a5f071ae75d87783ec171315e2b041ba7
```
