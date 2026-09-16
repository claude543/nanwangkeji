---
title: "K26_K50_CLEAN_P1｜改模、Python Runner、MATLAB DirectMAT、只读审计脚本｜编写规范与成功/失败经验"
date: 2026-09-16
status: "本窗口脚本工程规范冻结"
---

# 0. 目的

本文件不是泛化编程教程，而是把本窗口已经实际遇到的：

- 成功写法；
- 失败写法；
- 为什么失败；
- 如何避免返工；

沉淀成后续 `K26_K50_CLEAN_P1` 项目的脚本规范。

四类：

1. 改模 Patch / 独立 Verifier；
2. RT-LAB Python Runner；
3. MATLAB DirectMAT 大MAT计算；
4. 模型只读 Audit（审计）。

---

# 1. 改模脚本：正确工程范式

## 1.1 必须先审计真实结构，再写修改

禁止：

```text
“这个模块看名字应该是P环”
“端口3应该就是Id”
“这个Ki变量应该能在线改”
```

正确：

```text
精确路径
+ BlockType
+ 参数值
+ 端口号
+ 源/目的连接
+ Stateflow正文
+ workspace/callback
```

都先核实。

本轮最典型的成功：
- P PI 不是 `D1`，而是 `PI regulator with anti-windup D`；
- Q PI 才是 `D1`；
- P Kp4/Kp=0.06；
- P Kp5/Ki=2。

## 1.2 Patch事务必须是“scratch先行”

固定模板：

```text
正式磁盘模型只读preflight
↓
byte-identical scratch copy
↓
scratch修改
↓
postassert
↓
scratch save exactly once
↓
close/reload
↓
再postassert
↓
正式整文件backup
↓
正式re-preflight
↓
同一修改
↓
postassert
↓
正式save exactly once
↓
close/reload
↓
persistence postassert
```

保存后失败：

```text
whole-file rollback
+
SHA256核验
```

为什么：

> Simulink模型不是普通文本。只要修改正式文件后才发现路径/接口错误，就会把错误状态留在磁盘。scratch能把绝大多数脚本错误挡在正式保存之前。

## 1.3 独立Verifier不能调用Patch，也不能写模型

Verifier原则：

```text
read-only
```

禁止：
- `set_param`
- `save_system`
- 调用Patch函数“顺便验证”。

原因：

> 如果验证程序自己修复了模型，那么“验证通过”就失去独立性。

今天 R1H 还提供了另一个教训：
> Patch已经成功，Verifier脚本自身误报时，只修Verifier，不重跑Patch。

## 1.4 Patch与Verifier必须分开处理“结构正确”和“电气正确”

Patch PASS：

```text
结构/默认值/接线/持久化正确
```

不是：

```text
电气稳定PASS
```

Verifier PASS也一样。

最终：
```text
RT-LAB Rebuild
```
才是 compiled dimension / compiled parameter contract 的裁判。

之后：
```text
物理运行数据
```
才裁判动态行为。

## 1.5 标准Simulink块优先，不要为了方便堆 MATLAB Function

能用：
- Constant；
- Switch；
- Product；
- Rate Limiter；
- Mux/Demux；
- Inport/Outport；

就不用新 MATLAB Function。

原因：
- RT-LAB对函数块代码生成/编码/矩阵维度更敏感；
- 普通块更容易静态核对；
- 更容易确定在线 `/Value` 参数。

## 1.6 Stateflow / MATLAB Function句柄：不要函数返回值直接赋属性

本轮失败：

```matlab
chartAt(path).Script = src;
```

当前 R2023b/Stateflow API 把它解释成对象集合属性赋值，报“为82个元素赋值”。

正确：

```matlab
hit = chartAt(path);
hit.Script = src;
```

冻结成 helper：

```matlab
setChartScript(...)
getChartScript(...)
```

## 1.7 Windows长路径要在自测阶段处理，不要让它污染正式修改

R1B经验：

- 自测生成 `slprj/_sfprj`；
- RT-LAB项目路径很深；
- Windows传统260字符路径可能炸。

正确：
- `Simulink.fileGenControl` 临时把 cache/codegen 指向短 temp；
- 测试模型用短名；
- 退出恢复原配置。

不要要求用户到处手动搬工程。

## 1.8 RT-LAB pre-separate编码问题：先判定“代码逻辑 vs 主机编码”

R1I错误：

```text
host_preseparate.py
GBK decode
UnicodeDecodeError
```

不是控制算法错。

正确修复：
- 修改非ASCII注释为ASCII；
- 保证 executable code projection不变；
- Patch包/解压文件夹放短ASCII路径；
- 模型目录不堆中文zip。

禁止：
- 改RT-LAB全局Python；
- 因编码错误重写控制逻辑。

## 1.9 在线参数暴露：Simulink存在 ≠ RT-LAB可在线写

C1失败给出明确规则：

如果要后续在线调：
- 不要假设 masked PI 的 Kp/Ki 自动出现在 target parameter table；
- Build后必须 `GetParametersDescription()` 证实。

最可靠的本项目模式：

```text
显式 Constant（默认值）
→ Product / Switch
→ 原控制链
```

Build后：
```text
.../Constant/Value
```
通常能被稳定发现、写入、readback。

如果参数没暴露：
> 在第一次Execute之前 BLOCK，不要模糊fallback。

---

# 2. Python RT-LAB Runner：正确范式

## 2.1 只能动态发现参数/信号，不能冻结数字ID

成功 Runner 使用：

```python
RtlabApi.GetParametersDescription()
RtlabApi.GetSignalsDescription()
```

根据：
- path suffix；
- leaf；
- property；
- exact signal path；

动态解析。

不要硬写：
```text
parameter id = 145
signal id = 203
```
因为每次Build可能改变。

## 2.2 工程身份硬门

连接前确认：

```text
yanshou_V7
K26_K50_CLEAN_P1
```

并确认：
- 只有正确project；
- 当前 model；
- target step=100us；
- PAUSED；
- target clock≈0。

不符合就不Execute。

## 2.3 参数写入必须全发生在第一次Execute之前

标准：

```text
discover
↓
take controls
↓
snapshot original parameters
↓
write complete t=0 contract
↓
readback every write
↓
enable类参数最后写
↓
hard interlock
↓
first Execute
```

正式执行后：

```python
if execute_attempted:
    reject parameter writes
```

这是因果实验纪律。

## 2.4 “在线可调”不等于“同一次运行里应该在线扫参数”

参数可以在线写，正式A/B却仍应：

```text
fresh Reset/Load
```

否则：
- 积分状态不同；
- 母线状态不同；
- 控制器内部状态不同；
导致比较失真。

## 2.5 不能把“合法配置目标”与“本轮实际零命令”混为一谈

A0 R1错误：

为了 Pref=0，把：
```text
BASETEST target
```
也改成0。

模型合法合同要求：
```text
target=-0.005
```
于是 state9/fail92。

正确思路：

```text
合法配置target保持-0.005
↓
只让实验在state40真正非零命令开始前Pause
↓
实际观察窗口 PrefApplied=0
```

这是重要范式：
> **不要为了想要某个运行窗口，破坏模型自身合法配置。**

## 2.6 Pause策略：让Runner负责“取证窗口”，不要让模型状态替代电气结论

A0/P0：
- first observed state6；
- 再运行4s；
- state40前Pause。

好处：
- A0/P0比较同一个窗口；
- 不进入非零目标；
- 不需要让模型宣布“稳定”。

## 2.7 Runner停止判据分层

结构性立即 stop：
- NaN/Inf；
- contract mismatch；
- forbidden takeover；
- failCode结构异常；
- target clock异常。

普通动态：
- V/f/P/I波动；
- CurrentLimit；
- headroom；
不应被Runner自动裁判稳定性。

## 2.8 结果目录必须自描述

每轮建立唯一：

```text
D:\E2RUN\<case>_<timestamp>_<fileID>
```

至少保存：
- manifest.json；
- discovery.json；
- parameters_before；
- host samples；
- pause clocks；
- runtime events；
- expected MAT filenames；
- exact FileID；
- case config；
- status。

这样 MATLAB analyzer 不必猜“最新MAT”。

## 2.9 动态FileID非常重要

G27/G29/G30使用同一 FileID，文件名带编号。

不要只按：
```text
base_power_r1_g27.mat
```
找文件。

应从 manifest 读取 exact expected name。

## 2.10 C1失败的正确处理

首次 C1：
```text
P-Kp/P-Ki exact runtime candidate = []
```

正确 Runner：
- 在 t=0；
- execute_attempted=false；
- BLOCK。

这是成功的安全失败。

错误做法：
- fallback到 `Ki_Preg`；
- 模糊找任意 Ki；
- 可能误改 Q PI / shared workspace。

---

# 3. MATLAB DirectMAT：正确范式

## 3.1 MAT分析必须从 manifest 开始

流程：

```text
resolve completed run manifest
↓
读 FileID
↓
读 exact expected G27/G29/G30 filename
↓
在 OpREDHAWKtarget 找 exact file
```

不要：
- 按修改时间猜某个rootdiag；
- 人工复制大MAT；
- 用旧 run 的同名MAT。

## 3.2 manifest过滤要同时检查

P0 R1分析器的失败：
从A0机械复制到P0时，残留：

```matlab
strcmpi(char(J.case),'A0')
```

导致正确 P0 manifest 被过滤。

规范：

```text
version prefix
case
status startsWith CAPTURE_COMPLETE
expected_mat_files exists
```

都检查。

错误时应列出候选：
- path；
- version；
- case；
- status。

不要只说“No manifest”。

## 3.3 Windows路径放到 sprintf/error 格式串要小心转义

P0 R1：

```text
D:\E2RUN
```

在 `error/sprintf` 格式串里触发 `\E` warning。

错误信息示例路径可用：
```text
D:/E2RUN/...
```

## 3.4 大MAT先 whos('-file')，再精确加载变量

正式 recorder变量可能带 FileID 后缀。

分析器策略：
1. `whos('-file', path)`；
2. 首选冻结变量名；
3. 若变量名动态后缀，要求：
   - real numeric；
   - 2-D；
   - 冻结 row count；
   - 唯一候选；
4. 有歧义就报错，不猜。

当前：
```text
G27 = 120 rows incl time
G29 = 75
G30 = 145
```

## 3.5 时间行是真实证据，不假设理想采样

必须：
- 读取 row1 target-time；
- 检查非递增；
- gap；
- median dt；
- 用真实时间做窗口。

不要只用样本号 `n*0.0004`。

## 3.6 不插值制造不存在的事件点

事件：
```text
state6
Alpha open
breaker close
```
取真实首个满足样本。

不要为了“精确对齐”插值伪造状态切换时间。

## 3.7 因果比较必须对齐同一事件后的窗口

A0/P0使用：

```text
state6后：
0~2s early
2~4s late
```

核心指标：

```text
late p2p / early p2p
```

A0：
- <1 衰减

P0：
- >1 增长

比单看一次最大值更有因果意义。

## 3.8 FFT只叫描述性频谱，不叫“模态”

4秒窗 FFT 频率分辨率有限。

正确表述：
```text
dominant descriptive frequency
```

不能说：
```text
系统特征值模态 = 0.9992 Hz
```

除非做了正式线性化/特征值分析。

## 3.9 G30不知道的通道不能编名字

有冻结映射就用。
没有的 17-115：
```text
LegacyG30_017...
```

这是严谨性。

## 3.10 Analyzer不应自动宣布电气PASS/FAIL

MATLAB负责：
- 算数；
- 数据质量；
- 窗口指标；
- 图；
- 比较表。

工程结论由后续解释。

好处：
- 不把临时阈值偷偷变成验收标准。

## 3.11 大MAT不要一次全塞内存

按组：
```text
load G27 → calculate → compact → clear
load G29 → calculate → clear
load G30 → calculate → clear
```

最终输出 compact ZIP。

用户上传 compact ZIP，不需要再上传几百MB原始MAT。

---

# 4. 模型只读审计脚本：正确范式

## 4.1 Audit与Patch职责必须分开

Audit：
```text
只读
```

不修改：
- model；
- workspace；
- callback；
- Stateflow；
- Dirty状态。

输出事实后再设计Patch。

## 4.2 Audit必须输出可复核结构文件

好的审计不只打印console。

本轮成功审计输出：
- block index；
- function index；
- ordinary edges；
- exact port map；
- Goto/From route；
- parameters；
- recorder settings；
- source text；
- unresolved list；
- result.json。

这使新窗口无需重新上传整模型也能复核大部分事实。

## 4.3 不要用端口名称替代连线证据

比如：
```text
input3名字像diag
```
不够。

需要：
```text
source block/outport
→ target block/inport
```

## 4.4 protected/physical topology与ordinary Simulink lines要分开

SPS/电气保守端口不是普通 directed signal line。

不要用普通 `get_param(Line)` 逻辑解释所有物理拓扑。

## 4.5 Audit要标注“未解决”，不能自动填补

若无法解析：
```text
UNRESOLVED
```

比“按名称猜”更好。

## 4.6 static audit不能替代 Build

Audit证明：
```text
saved model structure
```

Build才证明：
```text
compiled widths
compiled parameter exposure
codegen compatibility
```

C1就是实际例子：
- static model有Kp/Ki；
- compiled RT-LAB没有online parameter。

---

# 5. 本窗口最典型的失败 → 正确经验映射

| 失败 | 真正原因 | 正确经验 |
|---|---|---|
| R1F Stateflow写Script失败 | `chartAt(path).Script=`对象集合语义 | 先取得唯一handle再赋值 |
| RT-LAB GBK UnicodeDecodeError | host pre-separate编码，不是控制逻辑 | 只ASCII化注释、模型目录保持ASCII卫生 |
| A0 R1 0.5s state9/fail92 | 把合法BASETEST target改成0 | target保持-0.005，用提前Pause获得Pref=0 |
| P0 DirectMAT R1找不到manifest | 从A0复制时case过滤残留A0 | case/version/status三重检查，打印候选 |
| P0 DirectMAT `\E` warning | Windows反斜杠进入sprintf/error格式串 | 错误提示路径用 `/` |
| C1 Runner找不到Kp/Ki | static PI参数未被RT-LAB Build在线暴露 | pre-execute block，显式Constant接口+Rebuild |
| 想把很多参数一次暴露 | 会扩大变量空间，因果不可解释 | 当前只暴露P-Kp/P-Ki |

---

# 6. 成功示范文件应该优先复用哪些

## Patch / Verifier
- `PATCH_K26_K50_ESS2_BASETEST_OBSERVE_R1G.m`
- `VERIFY_K26_K50_ESS2_BASETEST_OBSERVE_R1H.m`
- `PATCH_K26_K50_ESS2_ASCII_R1I.m`
- `VERIFY_K26_K50_ESS2_ASCII_R1I.m`
- `PATCH_K26_K50_ESS2_BASETEST_AB_DIAG_R1.m`
- `VERIFY_K26_K50_ESS2_BASETEST_AB_DIAG_R1.m`

## Python
- `RUN_K26_K50_ESS2_BASE_POWER_OBSERVE_R3.py`
- `RUN_K26_K50_ESS2_PQ_CAUSAL_A0_FORMAL_R2.py`
- `RUN_K26_K50_ESS2_PQ_CAUSAL_P0_FORMAL_R2.py`

## MATLAB DirectMAT
- `ANALYZE_K26_K50_ESS2_BASE_POWER_OBSERVE_R2_DIRECTMAT.m`
- `ANALYZE_K26_K50_ESS2_PQ_CAUSAL_A0_R1.m`
- `ANALYZE_K26_K50_ESS2_PQ_CAUSAL_P0_R2.m`

## Audit
- `ESS2并回改模前审计正确脚本(1).m`
- `AUDIT_K26_K50_ESS2_LOCAL_COMPLETION_R3.m`
- `AUDIT_K26_K50_ESS2_PICKUP_AUTHORITY_FULLCHAIN_R2.m`
- `AUDIT_K26_K50_ESS2_PICKUP_CURRENT_AUTHORITY_R1.m`

---

# 7. 后续脚本生成前必须自问的十个问题

1. 我修改的是正式模型的**确切版本**吗？
2. 精确 path / port / parameter 有没有先审计？
3. 是否有 scratch？
4. 保存前是否 postassert？
5. 保存后能否 rollback？
6. 独立Verifier是否真的只读？
7. Build后参数是否实际在线暴露？
8. Runner是否在第一次Execute前完成全部写入和readback？
9. Analyzer是否根据 manifest + FileID 找数据？
10. 本轮是否真的只改变一个关键变量？

如果其中任一答案不清楚：
> 先补证据，不要继续堆脚本。
