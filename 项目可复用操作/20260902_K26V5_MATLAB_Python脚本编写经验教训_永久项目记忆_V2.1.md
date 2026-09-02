# K26_V5｜MATLAB / Simulink Patch + RT-LAB Python
# 脚本编写经验教训、强制审计规则与永久项目记忆 V2.0

> 日期：2026-09-01  
> 用途：以后“暑期南网科技项目”任何新窗口，在编写 `.m` 改模/审计脚本、RT-LAB `.py` 试验脚本、MAT离线导出/分析脚本之前，先读本文件。  
> 本文件继承并升级：
>
> ```text
> 20260831_K26V5_Python试验脚本设计教训_窗口交接强制检查清单_永久项目记忆_V1.0.md
> ```
>
> V2.0 新增的重点不是更多“安全判断”，而是把 2026-09-01 RootDiag / B1 / Causal Harness 的真实返工经验固化，包括：
>
> ```text
> Simulink branch删除语义
> 新块几何位置造成auto-attach
> postassert必须描述新图而不是旧图
> intentional logger fanout
> signal label语义过期
> compiled property读取时机
> 一次性mode harness
> RAW->APPLIED->RESPONSE
> OpWrite分段MAT
> C0可存在但不一定要独立run
> ```
>
> 核心目标：
>
> > 以后脚本本身不能成为新的干扰源、误判源和返工源。

---

# 0. 一页永久规则

## MATLAB / Simulink

```text
先读图
再改图

先connectivity
再相信名字

先preflight
再backup
再edit

删branch
不误删source fanout

新block不要压在旧wire上

postassert检查NEW intended graph
不是沿用OLD graph

compiled property只在explicit compile state读

所有logger source接完立即逐port核验

exact bypass必须真的exact

save once
close/reload
persistent audit
```

## Python / RT-LAB

```text
先科学问题
再Phase/State表
再代码

Hard Safety
!= Operating Equivalence
!= Physical Result

model local truth
> high-speed MAT
> Host

J1后 Evidence-First

一个run一个主要因果变量

先验证intervention真的生效
再看系统结果

raw/applied/response同时记录

负面A/B也是有效结果

C2/C3按证据进入
不是预先排队

脚本bug确认后
同一回复直接给修正版
```

---

# 1. 最重要的思想：脚本必须服务于因果问题

最危险的代码不是语法错。

而是：

```text
语法完全正确
运行也完全正常
但它回答不了科学问题
```

例如：

```text
调5个参数
系统稳定了
```

这只能说明：

```text
某个组合可能有效
```

不能说明：

```text
哪个机制是根因
```

因此每一份正式试验脚本开头必须写：

```text
唯一科学问题
唯一干预变量
冻结变量
预期因果签名
结果分叉
```

---

# 2. Python编码前强制Phase/State表

不允许复制旧脚本后边跑边修。

模板：

| Phase | 入口条件 | 模型状态 | 允许动作 | 退出条件 | Hard Stop | Evidence/Warning |
|---|---|---|---|---|---|---|

必须先列出所有关键状态机，例如 F25：

```text
0 BYPASS
1 PREPARE_ESTIMATE
2 PREPARED_HOLD
3 EDGE_ARMED
4 FAST_TRANSFER
5 SMOOTH_COMMIT
6 ISLAND_HOLD
7 FALLBACK_HOLD
```

Causal Harness：

```text
Mode0 C0
Mode1 B1
Mode2 C1
Mode3 C2
Mode4 C3
```

以及当前 run 中：

```text
t<T_INTERVENE
intervention-only
J1-edge
post-J1 evidence
logger flush
```

---

# 3. R2 V1.0教训：local quasi-steady ≠ final system operating point

错误时序：

```text
S7/AGC还在改Pcmd
↓
F25提前PREPARE/HOLD
↓
F25锁的是旧工作点
↓
上层继续移动
↓
脚本再要求回旧PCC点
```

这不是 F25 物理错误，是试验阶段语义错。

永久规则：

```text
system dispatch freeze
必须先于
final local handover prepare
```

典型：

```text
P/Q COMMIT
→ S7/AGC退出
→ frozen operating point
→ F25 Late-Bind PREPARE
```

---

# 4. R2 V1.1教训：Host sample ≠ model edge-latched truth

错误：

```text
Host在edge前2ms采一次Pcmd
↓
模型在真正edge锁存当前值
↓
两者自然略有差
↓
脚本却要求1e-6严格相等
```

永久优先级：

```text
100μs model edge/state
>
high-speed MAT
>
Host async polling
```

边沿后模型 lock 值才是权威。

---

# 5. R2 V1.2教训：三类门槛不能混

必须分：

## Hard Safety / Validity

失败意味着试验没有解释意义：

```text
错误topology
错误mode
P/Q没freeze
J1状态错误
关键intervention没生效
NaN/Inf
runtime/API unusable
```

## Operating-point equivalence / quality

例如：

```text
PCC偏几kW/kvar
和历史run略有偏差
```

一般：

```text
记录
warning
```

不自动 Reset。

## Physical result

例如：

```text
V下降
V升高
频率偏
模态增长
candidate不成熟
limiter动作
```

这本来就是要观察的结果。

---

# 6. R2 V1.3教训：helper不能隐藏状态语义跨Phase复用

错误：

```text
prepared_point_ok()
内部偷偷要求state==2
```

然后：

```text
下一Phase state正常变3
却继续调用同helper
→ false
→误Reset
```

永久规则：

```text
Stage8:
prepared_point_ok()

Stage9:
armed_point_ok()

Stage10:
fast_edge_ok()
```

每个 helper 名称和内部 predicate 必须对应唯一阶段。

---

# 7. J1后必须Evidence-First

J1 前：

```text
严格保证试验入口合法
```

J1 后：

```text
优先保留失败证据
```

有限的：

```text
V=5kV
f=48Hz
limiter=1
timeout=1
candidate=0
```

可能正是最重要的根因证据。

只要 numerical finite、runtime可用：

```text
log
continue
flush data
```

不要为了“看起来安全”立刻 Reset。

---

# 8. timeout必须有物理语义

`F25_FAST_MAX=100ms` 在单ESS1足够，不代表 full-six 足够。

R2-T1通过唯一改变 timeout 上限把 timer confounder移走。

以后每个：

```text
timeout
ready_n
stable_windows
hold duration
```

必须回答：

```text
它在当前topology/phase下代表什么物理假设？
```

不能从历史run机械搬。

---

# 9. 每个raise/Reset必须逐条做“证明目标审计”

对脚本所有：

```text
raise
Reset
fail-safe
```

逐条问：

1. 它在哪个Phase？
2. 该条件失败后，实验是否真的失去解释意义？
3. 还是只是物理结果不好？
4. 它是否使用了旧阶段阈值？
5. 是否依赖异步Host？
6. 是否会掐断最有价值的失稳尾部？
7. 若去掉该hard stop，会不会真实造成数值/设备不可用？

不能回答清楚：

> 不应硬Reset。

---

# 10. Python错误和物理失败必须分开

看到：

```text
FAILED
```

先分类：

```text
A Python supervisory semantics
B RT-LAB API/runtime
C model parameter/signal contract
D physical instability
```

不能看到 Reset 就说“模型又不行”。

如果确认是 Python bug：

> **同一轮回复必须直接交付修正版，不让用户再等一轮。**

---

# 11. Build-specific signal/parameter ID不能继承

新 Build：

```text
signal ID
parameter ID
```

可能变化。

Python必须：

```text
GetParametersDescription
GetSignalsDescription / current available discovery
按path/label重新resolve
```

不能用旧数字ID想当然。

---

# 12. 每个新Build的“透明性”与“单独透明回归”要分开

模型能力层：

```text
Mode0必须设计成exact transparent/bypass
```

试验计划层：

```text
是否值得单独跑一次Mode0
```

是另一问题。

当前用户已经决定：

```text
不做独立C0 run
```

因此新 Python 不得又强行插一个完整 C0 实验。

但 C1 run 自己仍必须在 intervention 前证明：

```text
Mode2正确
C1 track
raw≈applied
B1/C2未干预
```

这叫 embedded validity。

永久规则：

> “exact bypass必须存在”不等于“每次都必须单独跑bypass experiment”。

---

# 13. Causal intervention必须记录RAW→APPLIED→RESPONSE

只记录 raw：

```text
不知道控制器实际收到什么
```

只记录 applied：

```text
不知道干预切掉了什么变化
```

只记录 response：

```text
不知道干预是否真的生效
```

所以当前新 logger标准：

```text
RAW
→ APPLIED
→ RESPONSE
```

例如 C1：

```text
raw VdVqs
applied VdVqs
Current PI
Vconv
branch Ia/PCC
```

C2：

```text
raw IdIq_refF
applied IdIq_ref
Current PI
Vconv
branch Ia/PCC
```

---

# 14. 相关性不等于必要根因

R3/B1中很容易看到：

```text
Vq
≈
Vq_conv
```

高回归、高coherence。

这只能说明：

```text
有强动态通道
```

不能直接证明：

```text
它是必要根因
```

必须主动干预：

```text
C1把dynamic Vdq从实际Current Reg input切掉
```

再看模态是否仍存在。

---

# 15. “首发”必须按时间因果，不按最终最大幅值

R2-T1：

```text
系统37ms先出gross failure
110/120ms才limit
```

所以：

```text
limit不是initiating root
```

同理 C1分析：

不能因为后期某个 PI 最大，就说 PI 是根因。

必须看：

```text
谁先出现增长
谁的增长率变化
干预后谁消失
```

---

# 16. MATLAB审计脚本：结构必须由connectivity反推

最典型错误：

```text
“每个Control应该只有一个BusCreator”
```

真实 EV2 命名/结构不一定符合想象。

永久优先：

```text
从实际Outport
→ line
→ source
→ parent
```

而不是：

```text
按名字猜block
```

---

# 17. EV2别名教训

真实：

```text
K26_V5/SS_Slave/Control System
```

不是：

```text
EV2_Control
```

定位控制器使用：

```text
known alias
+
Measurements
+
Current Regulator
+
Vpwm/meas output fingerprint
+
topology
```

不要匹配到：

```text
EV2_Control_Meas_Term
```

---

# 18. Signal label不是语义真值

B1最严重的一次分析误导来自旧 row 名：

```text
Vd_PLL
Vq_PLL
```

B1 routing改变后，Measurements out5/out6已经使用 coherent held frame。

但 logger 名字没变。

于是“看名字”会错误认为：

```text
这些仍是native PLL frame
```

永久规则：

每次 routing patch 后必须建立：

```text
signal semantic provenance table
source block
frame source
selection condition
actual consumers
```

分析时：

```text
provenance > variable name > comment
```

---

# 19. 在切一个因果edge前必须先枚举完整consumer graph

例如 `Measurements/out5`：

```text
可能同时去Goto12
和RootDiag
```

如果直接删整个line：

```text
会把logger也删
```

所以必须先：

```text
source outport所有dst
```

逐个列清楚。

---

# 20. Simulink line是branch graph，不是“一根线=一个目的地”

这是 V1 的直接教训。

如果 source：

```text
A/out1
├→ B/in1
└→ C/in2
```

要删除 C：

正确：

```text
delete only A→C destination branch
```

错误：

```text
delete whole line
```

否则 B 也会丢。

因此正式 Patch 要有：

```text
localDisconnectIncomingBranch(destination_port)
```

或等价的 destination-specific delete。

---

# 21. 新block几何位置可能导致auto-attach

V1 新 Mux 创建在旧 Mux/旧线束附近后出现：

```text
target port already connected
```

这说明程序化改模不能假设：

```text
add_block只产生一个孤立图形
```

在复杂旧wire几何上可能出现自动挂线。

永久做法：

```text
new block移开旧wire bundle
→创建
→逐input检查是否已有Line
→有则只清该destination branch
→再显式add_line
```

---

# 22. 删除旧diagnostic block之前先清destination branches

正确顺序：

```text
读取oldMux所有input handles
↓
逐个删除into-oldMux destination branch
↓
断开oldMux→Out24
↓
assert all old ports free
↓
delete_block(oldMux)
```

不是：

```text
直接delete_block
然后祈祷所有branch都干净
```

---

# 23. postassert必须验证“新设计图”，不是复用旧断言

V1.1已经把 C1接对：

```text
Applied
├→ control
└→ logger
```

但 postassert仍要求：

```text
Applied只有control一个destination
```

于是误报。

永久规则：

> 在写 postassert 前，先把 NEW graph 用文字/ASCII 画出来，再逐条编码。

对于故意 fanout：

```text
assert exact destination SET
```

而不是：

```text
assert single destination
```

---

# 24. intentional fanout应使用exact set

C1：

```text
AA15_C1_VDQ_TRACK_HOLD/out1
必须且只能：
1 Current Regulator/in1
2 causal logger/in5
```

正确测试：

```text
actual destination set == expected destination set
```

好处：

```text
少一个会报错
多一个隐藏支路也会报错
顺序不同不误报
```

---

# 25. logger接完立即逐port验证source

不要等全模型 update 后才发现：

```text
logger第7路接错
```

当前 V1.2：

```text
localAssertLogger17Sources
```

在 Section6刚接完就核对17个输入。

永久规则：

```text
connect
→ immediate local postassert
→ 再进入global update/compile
```

---

# 26. CompiledPortWidth只能在explicit compiled state读取

RootDiag V3曾出现：

```text
update
↓
读CompiledPortWidth
=0
```

不是向量真是0。

因为 `SimulationCommand='update'` 返回时模型已经不在 compiled state。

正确：

```text
feval(mdl,[],[],[],'compile')
↓
读取CompiledPortWidth
↓
feval(...,'term')
```

并用 `onCleanup` 确保异常也 term。

---

# 27. Static update与compile-state audit是不同证据

```text
SimulationCommand='update'
```

证明：

```text
结构解析
sample-time/基本连接
```

explicit compile-state：

```text
真实compiled signal width
```

两者不能混为一谈。

---

# 28. Vendor block不要猜library path

RootDiag OpWrite创建时：

正确：

```text
从当前已工作OpWrite读ReferenceBlock/SourceBlock
```

得到真实：

```text
rtlab/DataLogging/OpWriteFile
```

再复制。

不要靠记忆猜：

```text
某个OPAL library名字
```

---

# 29. 平台硬资源约束高于“group编号空闲”

即使：

```text
G31/G32/G33编号未用
```

也不意味着可以新增第6个 OpWrite。

当前项目硬约束：

```text
OpWrite block count =5
```

所以策略：

```text
复用G26/G27/G28
```

而不是扩数量。

---

# 30. 不为logger随意扩OpComm

五GFL分散在三个SS。

如果全送到 SM G29：

```text
SS→SM通信宽度变大
```

这会改变：

```text
task delay
realtime load
```

甚至污染所研究动态。

所以 RootDiag优先 local OpWrite。

---

# 31. 诊断Patch和控制Patch要分

RootDiag：

```text
instrumentation-only
```

Causal Harness：

```text
controlled intervention
```

不要同一个 Patch顺手：

```text
改PI
改F25
改PLL
调network
```

否则无法知道后续差异来自哪里。

---

# 32. transaction式Patch固定模板

以后正式 `.m` 改模脚本：

```text
1 load current canonical
2 assert exact model file
3 Dirty=off
4 read-only preflight
5 old contract
6 collision guard
7 resolve ambiguity
8 capture vendor prototypes
9 exact full SLX backup
10 editStarted=true
11 edit
12 immediate local postassert
13 update
14 explicit compile if required
15 global strict postassert
16 save exactly once
17 close_system(...,0)
18 reload
19 persistent audit
20 declare PASS
```

异常：

```text
if editStarted:
close without save
copy backup over canonical
reload
confirm rollback
rethrow
```

---

# 33. 为什么Dirty=off重要

如果 patch 前 Dirty=on：

```text
磁盘模型
≠
内存模型
```

backup复制的是磁盘版本。

一旦失败 rollback：

```text
用户未保存手工修改可能永久丢失
```

所以：

```text
Dirty=off
```

是事务前提，不是形式主义。

---

# 34. Save once的意义

中间多次 save 会让：

```text
backup
canonical
partial patch
```

边界模糊。

正确：

```text
所有assert PASS
↓
save once
↓
close/reload
```

---

# 35. close/reload persistent audit为什么必须有

内存里正确不等于：

```text
磁盘重新打开仍正确
```

所以 final：

```text
close_system(model,0)
load_system(modelFile)
```

重新查：

```text
new blocks存在
default mode
OpWrite count
critical parameters
```

---

# 36. warning要分类，不要“清零强迫症”

当前已知大量 warning：

```text
unmatched old From/Goto
unused outputs
diagnostic ports
shadow/strategy leftovers
```

如果：

```text
compile PASS
critical width PASS
new edge postassert PASS
```

则这些 warning 不应成为顺手改旧模型的理由。

只有：

```text
Build error明确指向它
runtime signal missing
MAT证明链断
```

才升级。

---

# 37. Track/Hold设计的永久规则

当前 vector Track/Hold：

```text
raw
→ switch
→ applied
→ Unit Delay state
```

必须满足：

```text
TRACK期间:
applied=raw
state=previous applied

切HOLD:
applied=last tracked state
```

不是：

```text
HOLD时输出0
```

也不是：

```text
切换瞬间重新采一个异步Host值
```

---

# 38. Unit Delay IC不能脱离warm-up讨论

看到：

```text
InitialCondition=0
```

不要立即说“会在Hold变成0”。

要看：

```text
Hold前是否持续track了足够时间
```

当前：

```text
0~8.1894s一直track
```

所以 state已经warm。

永久规则：

> 离散状态初值是否危险，要结合首次使用时刻，而不是只看参数。

---

# 39. 一次性mode harness的价值

传统做法：

```text
C1改模 Build
跑
C2再改模 Build
跑
C3再改模 Build
```

会反复：

```text
改图
Build
引入新的差异
```

当前采用：

```text
Mode0~4一次性预留
runtime只切mode
```

优点：

```text
同一个Build
同一个代码生成
同一个logger
更强A/B可比性
```

但注意：

> 一次性预留多个mode，不等于要机械把所有mode都跑一遍。

---

# 40. runtime mode必须all-device exact readback

五台各有自己的：

```text
AA15_CAUSAL_MODE
```

Python C1必须：

```text
全部写2
全部读回2
```

不能假设：

```text
写一个代表所有
```

这是 experimental integrity hard gate。

---

# 41. intervention-only窗口是必要反混淆

如果在 J1 同一瞬间才激活 C1：

```text
无法区分
C1切换瞬态
vs
J1失稳
```

所以：

```text
8.1894s C1 hold
↓
约20ms
J1仍closed
↓
8.2094附近J1 open
```

这20ms用来证明：

```text
intervention本身没有先破坏strong-grid工作点
```

不是为了“等稳定参数”。

---

# 42. pre-intervention transparency可以嵌入同一run

当前用户明确跳过独立 C0。

C1 run仍可利用：

```text
0~8.1894s
```

证明：

```text
Mode2下C1 gate仍track
raw≈applied
```

这比额外一条 C0 更直接地证明：

```text
C1模型在切换前没有提前影响系统
```

---

# 43. C1/C2/C3必须按结果分叉，不预排流程

正确：

```text
C1
↓
若strong hit
→工程修复
```

不是：

```text
C1
C2
C3
一定全跑
```

只有 C1不足时 C2。

只有有交互必要时 C3。

---

# 44. MAT文件名不等于完整time history

OpWrite `Nb_Samples=1000` 可能产生：

```text
rootdiag_ev12_data.mat
rootdiag_ev12_data_...
...
```

单一 nominal file可能只是一个 segment。

离线 exporter 必须：

```text
find all segments
audit each
assemble by Target Time
deduplicate
crop
```

---

# 45. MAT segment完整性检查

每个 segment：

```text
variable存在
row count正确
finite
Target Time单调
dt近预期
time range
```

预期：

```text
G26 49 rows dt~0.0002
G27 25 rows dt~0.0002
G28 49 rows dt~0.0002
G29 39 rows dt~0.0002
G30 64 rows dt~0.0005   [当前F25包版本]
```

注意 row count 以当前 build 实际合同为准。

---

# 46. 拼MAT禁止偷偷处理信号

拼接阶段：

```text
不filter
不resample
不插值
不重排行
```

只：

```text
concat
sort time
deduplicate exact/near-exact duplicate timestamp
crop
```

频谱/滤波另开 analysis copy。

---

# 47. row map必须版本化

同一个：

```text
rootdiag_ev12_data.mat
```

在 RootDiag V4 和 Causal Harness 后信号row含义已经不同。

所以分析脚本必须绑定：

```text
Build/Patch version
+
row map
```

不能按文件名猜。

---

# 48. 103Hz误判的永久数据分析教训

早期整个first-onset短窗最大谱峰约103Hz。

后来发现：

```text
nonstationary step
envelope变化
short-window leakage
centered-window future leakage
```

会把能量峰误当增长模态。

永久：

```text
最大FFT峰 != instability eigenmode
```

必须：

```text
raw first
pre/post
causal trailing windows
growth envelope
A/B same method
```

---

# 49. centered window不能用于最终因果onset

如果在 t 时刻用了：

```text
[t-L/2, t+L/2]
```

就偷看未来。

最终 onset：

```text
只能用[t-L,t]
```

报告：

```text
window length
检测延迟
sampling dt
```

---

# 50. 同一个A/B必须用同一分析方法

不能：

```text
A用FFT
B用Prony
然后比较sigma
```

要：

```text
同样time window
同样demodulation
同样fit
```

否则方法差异可以假装成物理差异。

---

# 51. 负面因果结果也必须封板

B1：

```text
干预有效
系统仍等强失稳
```

不是“没结果”。

它关闭：

```text
native PLL active dynamics necessary root
```

永久规则：

> 负结果如果干预有效，是最有价值的排除证据之一。

---

# 52. 已关闭方向不得因普通失稳重开

当前包括：

```text
ESS1 GFM capability
F21
F22 first-layer
F24
P/Q COMMIT
single-ESS1 F25 responsibility
F25 FAST timeout initiating root
F25 authority initiating root
native PLL active frame necessary root
```

只有新数据**直接违反它们自己的执行合同**才重开。

---

# 53. 当前不要再做B2

历史上曾因错误理解 B1 为 mixed-frame 而提出 B2。

V2/V3 live-model audit已经证明：

```text
B1本身就是coherent frame
```

所以：

```text
B2计划作废
```

不要新窗口看到旧md又复活它。

---

# 54. 注释也会过时，执行计划以最新用户决策为准

Patch V1.2 注释里写：

```text
C0 transparency mandatory
```

但用户后来明确：

```text
跳过独立C0
直接C1
```

永久规则：

```text
model contract
!=
later experiment plan
```

旧注释保留的是“当时设计计划”，不是永远最高约束。

新窗口必须识别：

```text
时间更晚的明确用户决策
```

---

# 55. 不要反复要求Overrun泛化确认

实时性在正式新 Build/run中仍然是结果有效性的条件之一，但不能每一步都把用户拉回：

```text
“再确认一次Overrun”
```

当前用户已经多次验证基础透明运行没有超时/Overrun问题。

永久原则：

- 不为纯结构讨论反复追问 Overrun；
- 不为已验证的透明路径再做独立 runtime smoke；
- 只有当前新 Build/run 出现 realtime 异常、或准备冻结正式物理结论时，才把当前 run 的 realtime 状态作为一次性证据检查；
- 不要把 F25 内部 `timeout` 和 RT-LAB `Overrun` 混为同一件事。

---

# 56. Build失败时不要猜

若 RT-LAB Build fail：

先看：

```text
first actionable error
```

然后分类：

```text
unsupported block
codegen
sample time
OpWrite
task mapping
mask
connection
```

不要一上来：

```text
删诊断
回滚F25
改PLL
```

---

# 57. 模型修改位置必须写到能定位

以后给用户改模文档必须至少写：

```text
完整block path
block name
input/output port
old source/destination
new source/destination
为什么插在这里
为什么不插上游/下游
```

例如 C1：

```text
K26_V5/SS_Slave3/PV1_Control/From26(out1)
→ AA15_C1_VDQ_TRACK_HOLD(in1)
→ Current Regulator(in1)
```

不能只说：

```text
“在电压前馈处加Hold”
```

---

# 58. 每个新块都要解释“为什么需要”

禁止只列：

```text
加Constant
加Switch
加Unit Delay
```

要解释：

```text
Constant定义mode
Relational Operator解码mode
OR把Mode2/4合并成C1请求
Step定义同一干预时刻
Switch在非目标mode exact track
Unit Delay保存last actually-applied vector
logger记录track state
```

---

# 59. 审计脚本本身也要审计

曾经出现过 audit：

```text
真实Goto存在
但搜索逻辑返回0
```

所以“审计脚本打印PASS”不是宇宙真理。

审计也要：

```text
structure agnostic
case-insensitive where appropriate
actual path printout
Dirty unchanged
no edit APIs
```

如果 audit 结果与已知图矛盾：

```text
先查audit实现
```

---

# 60. 静态交付检查表：MATLAB Patch

交付 `.m` 前：

```text
[ ] exact model path/bdroot
[ ] Dirty off
[ ] current old contract
[ ] all candidate controls resolved
[ ] ambiguity before edit
[ ] collision guard
[ ] exact backup
[ ] editStarted flag
[ ] branch-specific deletion
[ ] new inports verified free
[ ] no geometry autoattach
[ ] immediate local source audit
[ ] intentional fanout exact-set assert
[ ] no old bypass
[ ] update
[ ] explicit compile
[ ] compile term cleanup
[ ] OpWrite exactly5
[ ] G29/G30 frozen
[ ] no OpComm width
[ ] save once
[ ] close/reload
[ ] persistent mode/default
[ ] rollback path tested
```

---

# 61. 静态交付检查表：Python

交付 `.py` 前：

```text
[ ] unique scientific question
[ ] Phase/State table
[ ] Build-specific discovery
[ ] all five mode write/readback
[ ] no hidden old ID
[ ] no manual Execute dependency
[ ] pre-intervention validity
[ ] intervention-only window
[ ] real J1 edge
[ ] model-local truth preferred
[ ] hard/equivalence/result separated
[ ] post-J1 Evidence-First
[ ] every raise audited
[ ] finite-only catastrophic gate
[ ] commands/topology frozen
[ ] logger flush boundary
[ ] PAUSED end
[ ] restore without further Execute
[ ] current row-map/version logged
[ ] expected files listed
[ ] py_compile
```

---

# 62. C1专用Python未来强制表

C1 Mode2至少：

```text
P0 fresh Reset/Load/Paused
P1 discovery
P2 set all five mode2 + readback
P3 six-GFL strong-grid staging
P4 ESS1 planned GFM staging
P5 P/Q COMMIT
P6 F24/F25 final prep
P7 t<8.1894:
   C1 track=1
   C2 track=1
   raw≈applied
P8 8.1894~J1:
   C1=0
   C2=1
   B1track
   intervention-only validity
P9 real J1
P10 0~first-onset:
   evidence-first
P11 logger flush
P12 PAUSED/restore
```

不要另插一个：

```text
P-1 C0 full run
```

当前用户已取消。

---

# 63. C1结果的因果判定不是固定阈值

核心比较：

```text
A baseline 14~16Hz sigma≈+24~25/s
vs
C1 same-family sigma
```

看：

```text
mode是否仍存在
growth sign
growth magnitude
是否出现新mode
raw/applied cut是否有效
```

不是只看：

```text
V是否落在0.9~1.1pu
```

---

# 64. 如果C1强命中，不要马上“调参数”

先把机制写清：

```text
dynamic terminal Vdq
→ direct feedforward
→ Vconv
→ GFL port admittance
→ network/PCC
→ ESS1 GFM return
```

再设计最终工程方案，例如：

```text
band-limited feedforward
dynamic decoupling
selective damping
frequency-shaped feedforward
```

但最终选哪种必须基于数据，不能现在预定。

---

# 65. 如果C1无效，不代表Vdq不重要

只能说：

```text
把C1这条实际direct feedforward动态切掉
仍然不改变失稳必要性
```

可能还有：

```text
Power Control
current feedback
Current PI
```

所以再进入 C2。

这体现：

```text
必要路径结论必须和干预覆盖范围一一对应
```

---

# 66. 最终方法论一句话

> **K26_V5 后续所有模型Patch、RT-LAB Python和MAT分析都必须围绕“真实模型语义 + 单一因果问题 + 可验证干预 + RAW→APPLIED→RESPONSE + Evidence-First”设计。模型结构不靠名字猜，线不靠视觉猜，compiled属性不脱离compile state读，postassert不沿用旧拓扑，MAT不按文件名猜完整历史，A/B不靠相关性定罪。所有已经关闭的根因分支保持关闭，除非新证据直接违反其执行合同；所有新实验都应减少根因树的不确定性，而不是增加参数组合。**


---

# 67. 2026-09-02 Layer-2 Patch 连续两次维度失败：永久教训

本轮出现：

```text
V1.0 real-model compile：
AA15_L2_IREF_CORE
输出 icandidate 维度未完全确定

V1.1 scratch compile：
AA15_VFF_CORE
输出 v_mode7 维度未完全确定
```

这两次失败必须长期记住，不能只理解为“补一个维度声明即可”。

真正原因：

```text
signal width = 2
```

并不唯一等于：

```text
1-D length-2 vector
```

还可能在 MATLAB Function 编译传播时表现为：

```text
2×1 column
1×2 row
1-D vector
```

因此：

> **CompiledPortWidth 只能证明元素总数，不能证明 MATLAB Function 需要的 shape 已完全确定。**

---

# 68. 新规则：dq/IdIq 新 MATLAB Function 优先标量化

对于本项目新增加的控制/诊断 MATLAB Function：

如果输入是：

```text
[Vd,Vq]
[Id,Iq]
```

默认结构应为：

```text
width-2 signal
↓
Demux
↓
d / q 两个 scalar
↓
MATLAB Function 仅处理 scalar
↓
Mux
↓
width-2 signal
```

除非已经有当前真实模型 compile 证据证明 vector shape 合同稳定，否则不要为了代码简短直接把 width-2 向量送入新 MATLAB Function。

注意：

```text
MATLAB Function 本身仍允许使用
```

本规则不是恢复旧的“禁止 MATLAB Function”。

它只是要求：

```text
新函数的接口形状必须 codegen-safe、compile-safe、明确。
```

---

# 69. Scratch 预检必须复现“真实 signal shape”，不能只复现 width

V1.0 Scratch 使用：

```text
Constant [0.2;0.1]
```

虽然 width=2，但与真实 Simulink Mux/控制链输出的 1-D width-2 signal shape 不完全等价。

所以以后 Scratch：

```text
错误：
直接造一个 MATLAB vector Constant
然后因为 compiled width=2 就认为真实模型一定通过

正确：
scalar d
scalar q
↓
真实同类 Mux
↓
再接被测子系统
```

更高优先级：

```text
如果已有一个真实 Build 中已经编译/运行成功的子系统
→ 直接复制这个 trusted subsystem 到 scratch
→ 只把“本次新增部分”接在后面验证
```

不要重新实现一个“逻辑上相似”的替代版。

---

# 70. Trusted subsystem 冻结原则

Mode7：

```text
AA15_VFF_DQ_SHAPER
```

已经：

```text
Patch成功
Verifier成功
Build成功
Load/Execute成功
MAT逐点公式验证成功
```

因此 Layer-2 不应为了增加慢前馈比例重新改写它。

正确：

```text
trusted Mode7 output
↓
新增 Layer-2 wrapper
↓
Current Regulator
```

意义：

```text
本轮失败只能来自新增Layer-2部分
而不是再次打开已关闭的Mode7实现风险
```

永久规则：

> **已经用正式运行证明的控制子系统，后续优先外接 wrapper，不在没有必要时重写内部。**

---

# 71. Patch 的 Scratch 失败必须发生在 real edit 之前

本轮 V1.1 在：

```text
Stage 1 Scratch Preflight
```

就失败。

因此正确事务结构必须保持：

```text
read-only SHA/Dirty check
↓
scratch/canary compile
↓
只有 scratch PASS
↓
才允许 backup + real edit
```

这样 Scratch fail 时：

```text
K26_V5内存没有被改
磁盘没有被save
```

后续再用：

```text
SHA hard lock
```

确认仍处在冻结基线。

---

# 72. Python 在线信号合同：必要参数硬、内部遥测软

Mode7 Python 曾因五台×2个内部 shaper 输出没有按预想路径暴露，导致：

```text
Exact current-build signal contract failed for 10 items
```

永久规则：

```text
必须决定试验有效性的 runtime parameter
→ exact discover + write + readback，硬合同

模型内部状态量如果最终能由MAT logger严格证明
→ RT-LAB在线发现仅作为best-effort辅助
→ 不因为“没有在线暴露”阻止第一次Execute
```

但不能反过来把真正必要的：

```text
模式
参数
拓扑
旧门状态
```

也全部软化。

---

# 73. MATLAB 自动分析的职责边界永久冻结

以后 MATLAB MAT 分析脚本只做它擅长的：

```text
1. 多目录自动发现/合并MAT segment
2. 时间轴与重复段一致性检查
3. row-map解码
4. 模型本地J1/控制边沿定位
5. 逐点代数合同重构
6. RMS/均值/斜率/积分/相关性
7. 统一模态拟合
8. 事件首次发生时刻
9. 多时间尺度窗口统计
10. 输出结构化CSV/MAT/报告
```

MATLAB 不做：

```text
“根因已锁定”
“方案成功”
“下一步一定是什么”
```

自动科学判决。

最终因果判断仍由：

```text
历史A/B因果试验
+
本轮执行合同
+
MATLAB数值证据
```

综合完成。

---

# 74. 严禁低电压后用裸零交越频率自动定罪

Mode7 数据中，母线电压严重塌陷以后简单零交越曾得到：

```text
约100Hz / 150Hz
```

假频率。

永久规则：

```text
PCC/母线物理零交越频率
必须附带电压有效门限
```

例如只在：

```text
20ms RMS voltage > 0.7pu
```

时统计。

低于门限：

```text
标记 frequency estimate invalid due low voltage
```

同时优先使用：

```text
GFM Fout
GFM theta derivative
```

判断构网频率主线。

---

# 75. Layer-2 根因运行脚本的永久合同

第二层慢塌陷试验：

```text
第一轮必须 L2_MODE=0 同Build复现Mode7
```

只有基线复现以后：

```text
Mode1 慢端口电压路径
Mode2 P/Q-Iref动态路径
Mode3 交互
```

才有因果解释资格。

Python职责：

```text
工况staging
精确runtime parameter write/readback
强网干预窗口
J1真实开断
至少J1后3s Evidence-First观察
共同logger block边界落盘
manifest
PAUSED结束
```

Python不得因为：

```text
有限电压下降
有限频率偏离
F25后续限幅
```

过早停止并丢失慢动态数据。

只对：

```text
non-finite
绝对灾难性数值异常
执行合同破坏
```

做硬失败。
