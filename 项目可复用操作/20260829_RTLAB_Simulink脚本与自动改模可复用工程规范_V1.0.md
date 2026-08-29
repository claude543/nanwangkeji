# RT-LAB / Simulink 自动化脚本与模型修改脚本可复用工程规范
## ——本项目 Stage00~Stage15、GFM排错、PB1/PB2 实际踩坑后的统一经验

**版本：V1.0**  
**日期：2026-08-29**  
**用途：以后编写 MATLAB 自动改模脚本、RT-LAB Python 自动实验脚本、Audit / Repair / Takeover 脚本时直接按本文执行，减少半改模型、路径猜错、无效Build和重复返工。**

---

# 0. 总工作流

任何重要自动改模：

```text
定义本轮唯一问题
↓
Audit / Discovery
↓
自动备份
↓
Preflight
↓
发现当前真实结构
↓
最小修改
↓
Update Diagram
↓
端口/维度/路由断言
↓
日志同步
↓
Save
↓
必要时Build一次
↓
Load
↓
Runtime Validation
↓
MAT/TXT验收
↓
冻结结论
```

禁止：

```text
找到块
→ 直接删线
→ 接新线
→ Build碰运气
```

---

# 1. 脚本必须按职责分类

## 1.1 Audit Script

只读，不改。

回答：

```text
当前模型是谁
真实source/destination
Goto/From
端口顺序
Breaker来源
设备Mux来源
参数是否可调
日志是否覆盖
```

代表：

```text
S00_K26_V5_LOCAL15_AUDIT_AND_TUNABILITY_LOCK_V3.m
AUDIT_K26_V5_ISLAND_HANDOVER_ARCHITECTURE_V*.m
AUDIT_K26_V5_PREISLAND_POWER_BALANCE_INTERFACE_V*.m
AUDIT_K26_V5_PB2EXT_ONLINE_SIGNAL_INTERFACE_V1.py
```

不知道真实结构时先Audit，不先Patch。

---

## 1.2 Scaffold

建立：

```text
CFG Panel
Constant
Goto
From
统一接口
```

暂不接管Plant。

---

## 1.3 Shadow

新逻辑：

```text
会算
会记录
但不控制真实Plant
```

复杂算法优先 Shadow。

---

## 1.4 Takeover

真正改变：

```text
Pref
Qref
GridOn/Droop
Breaker
```

必须有更严：

```text
Preflight
Legacy保留
唯一destination
Final Applied断言
Fallback
Mandatory Build
```

---

## 1.5 Extension

已经PASS的模块不重写，优先旁路扩展。

例如：

```text
已有S2/S7 Normalizer
→ 新增P Extension
```

---

## 1.6 Repair

根因明确后只修一个问题：

```text
代数环
维度
漏接端口
日志
路由
```

不要“修一个问题顺便重构整个系统”。

---

## 1.7 Runtime Test / Plot

与结构改模完全分开。

```text
结构脚本
≠
RT-LAB运行脚本
≠
MAT绘图脚本
```

---

# 2. MATLAB改模不要硬编码模型名

正式：

```matlab
mdl = bdroot(gcs);
```

不要：

```matlab
mdl = 'K26_V5';
```

因为用户可能打开：

```text
测试副本
冻结副本
备份副本
```

推荐：

```matlab
mdl = bdroot(gcs);

if isempty(mdl) || strcmp(mdl,'0')
    error('No active Simulink model detected.');
end

load_system(mdl);
```

---

# 3. Python同样先确认Project/Model

不要写死 Model ID。

标准：

```text
GetActiveProjects()
→ OpenProject()
→ GetCurrentModel()
→ 校验工程名/模型名
```

不一致立即STOP。

---

# 4. Discovery First

本项目不同设备Mux曾有：

```text
PV1_IO_Mux12
PV2_IO_Mux12
ESS1_IO_Mux12
ESS2_IO_Mux12
EV1_IO_Mux
EV2_IO_Mux
```

所以按名字猜统一格式会失败。

发现真实链路优先级：

```text
Signal Tag
→ source/destination
→ BlockType
→ port handle/port number
→ 最后才看block name
```

---

# 5. 信号语义优先于块名字

例如 Pref：

```text
V5A_FINAL_PV1
V5A_FINAL_PV2
...
```

正确：

```text
找GotoTag
→ 找From
→ 查From输出去了哪个Mux端口
```

比：

```text
搜索名字含PV1的Mux
```

可靠。

---

# 6. 高风险结构修改前必须自动备份

模板：

```matlab
modelFile = get_param(mdl,'FileName');
stamp = datestr(now,'yyyymmdd_HHMMSS');

[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(
    modelDir,
    sprintf('%s__PRE_CHANGE_%s%s',...
    modelBase,stamp,modelExt)
);

copyfile(modelFile,backupFile,'f');
```

原因：

```text
脚本可能中途异常
模型可能已经被删线/加块
```

不要依赖“我记得另存了”。

---

# 7. Preflight要在碰真实控制线以前全部通过

至少确认：

```text
前置Stage
目标Subsystem
Source
Destination
日志
当前控制源
当前线路来源
```

高风险Takeover还要要求：

```text
当前source属于Legacy
或属于本Patch已完成后的Final
```

否则：

```text
Refusing takeover
```

---

# 8. From改Tag前检查destination数量

如果：

```text
一个From同时服务多个地方
```

改Tag会同时改变多个功能。

所以应：

```text
num destinations == 1
```

否则STOP。

---

# 9. 重复运行脚本必须有明确定义

两种可接受方式：

## A. Idempotent

```text
块存在则验证
线存在则保留
重复运行不重复增加
```

## B. 明确拒绝

发现：

```text
后续Stage已经存在
```

旧脚本立即：

```text
error
```

不要重建旧Subsystem把后面阶段擦掉。

---

# 10. Shadow → Takeover 是降低返工的关键

如果直接：

```text
新算法
→ Plant
```

失败后无法区分：

```text
算法
输入
映射
Plant
```

Shadow：

```text
同源输入
→ Legacy
+ New
→ 同日志
→ 对比
→ PASS
→ Router Takeover
```

LOCAL15 Stage02~07 就是这一方法。

---

# 11. Legacy必须保留Fallback

长期架构：

```text
CONTROL_SOURCE=0 LEGACY
CONTROL_SOURCE=1 LOCAL15
CONTROL_SOURCE=2 BOARD15
```

新算法不要直接删旧链。

---

# 12. 模型保存默认值应透明

F1~F20排错的通用规则：

```text
Saved Default = 正常/透明
↓
测试脚本第一次Execute前
才切测试模式
↓
结束恢复
```

这样模型普通Load/Build不会带上一次特殊工况。

---

# 13. 改线优先使用Port Handle

比字符串：

```text
BlockA/1 -> BlockB/2
```

更稳的是：

```matlab
ph = get_param(block,'PortHandles');
src = ph.Outport(...);
dst = ph.Inport(...);
```

再连接。

---

# 14. 删除旧线前必须记录真实来源

不能：

```text
看到input6有线
→ delete
```

必须先确认：

```text
source block
source port
GotoTag/semantic
destination
```

与预期一致才改。

---

# 15. MATLAB Function / Stateflow 是当前平台特殊风险

在：

```text
RT-LAB 2024.1.1.38
MATLAB R2023b
```

曾做最小：

```text
SM_Master:
Constant
→ MATLAB Function(y=u)
→ Terminator
```

RT-LAB Signals Database / 分离模型阶段仍出现过：

```text
恢复的 Stateflow 图不存在
```

分离的SS模型里还出现SM MATLAB Function恢复副本异常。

永久经验：

1. 新 MATLAB Function 先做最小canary；
2. 已经Build通过的 Function 尽量复用；
3. 简单逻辑优先普通块：
   - Switch
   - Logic
   - Gain
   - Sum
   - Unit Delay
   - Relational Operator；
4. 不一次新增很多Function后才Build；
5. 普通Simulink能跑，不等于RT-LAB分核恢复一定安全。

---

# 16. Linked Library Block不要强行进去改

S15同步设计中 J2测量块属于library link。

正确：

```text
不破library
→ 在SM_Master顶层从已有Vabc分支
→ 新增独立phase estimator
```

优先旁路，不破库链接。

---

# 17. 状态机互相引用要防代数环

S13/S15涉及：

```text
island latch
recovery state
clear-island request
```

采用：

```text
Unit Delay
```

让状态来自上一拍。

禁止：

```text
S13 current
→ S15 current
→ 回S13 current
```

---

# 18. 请求、执行状态、最终命令、物理实际量必须分层

不能看到：

```text
request=1
```

就说动作成功。

例如PCC：

```text
S5/S15 request
→ S13 exec_mode
→ final breaker cmd
→ 100us delay
→ GateA override
→ J1 actual
```

正式验收至少同时看：

```text
request
executed state
final command
physical applied
```

---

# 19. Mux / Group26/28日志只追加，不重排

已有行号是事实契约。

新Stage：

```text
append
```

不要重排，否则：

```text
旧MAT
旧分析脚本
旧文档
```

全部失效。

---

# 20. 改结构后必须Update Diagram

至少检查：

```text
端口数
维度
Goto/From冲突
未连接
代数环
MATLAB Function接口
```

不要把所有错误留到RT-LAB Build。

---

# 21. CompiledPortWidths要在正确时机读

结构改完：

```text
Update Diagram
→ 再读CompiledPortWidths
```

未更新前直接断言可能拿到旧值/不可用值。

---

# 22. Build次数靠“模式参数化”减少

正确：

```text
一次Patch
→ 把mode/gain/enable做成Tunable
→ Build一次
→ 多轮零Build
```

错误：

```text
为了省Build
运行时硬改本应属于结构的内容
```

---

# 23. 单变量因果测试

写脚本前冻结：

```text
唯一修改变量
冻结变量
PASS意味着什么
FAIL意味着什么
哪条路线会被关闭
```

F10/F20之所以有价值，就是因为单变量。

---

# 24. 不用参数扫替代根因定位

无新证据时禁止：

```text
扫PI
扫F4 offset
扫F20 fc
扫MODE3 beta
```

顺序：

```text
第一异常量
→ 结构假设
→ 单变量验证
```

---

# 25. RT-LAB参数发现必须一次性全量Preflight

PB2 V1：

```text
F7 0 hits
→ 一次只报一个
```

低效。

V2之后：

```text
一次扫描全部required
→ 所有missing/ambiguous一次列出
→ 任何写参/Execute以前STOP
```

成为正式规则。

---

# 26. Hard-required 与 Optional build-frozen 分开

F7/F11/F12属于历史诊断项，有些当前Build可能不暴露。

如果本轮不依赖：

```text
允许0 hits并记录
```

真正控制必需：

```text
F3/F4/F8/F9/F10/F20
```

必须唯一存在。

任何：

```text
>1 hits
```

都不能盲选。

---

# 27. 关键动态Signal不要自动猜

PB2经历：

```text
V2：历史path假设 → 0 hits
V3：语义ranking → 仍有3个问题
```

最终：

```text
readonly mapping
→ ID/label/path/value
→ 人工确认
→ 固定字典
```

Breaker、mode、GridOn、Droop等关键状态必须如此。

---

# 28. 变量名字不能代替物理语义

V5把：

```text
Droop=0
```

当作ESS1仍GFL的必要条件。

实际：

```text
GridOn=1 → GFL
GridOn=0 → GFM
```

即使：

```text
GridOn=1
Droop=1
```

仍是GFL。

结果：

```text
P/Q早已满足
状态机却一直不READY
```

永久经验：

> 状态机判据必须来自真实执行语义，而不是变量名字直觉。

---

# 29. 日志窗口在写脚本前算清

V4：

```text
PREPARE deadline=8 s
```

Group26/28：

```text
Ts=100us
Decimation=100
Nb_Samples=1000
```

完整块需要10 s。

8 s Reset：

```text
MAT≈1 KB
```

正确设计：

```text
控制deadline
≠
logger minimum end
```

---

# 30. 受控失败与电气安全失败分开

## 受控失败

例如：

```text
PREPARE timeout
PCC仍闭合
```

可以：

```text
控制结论冻结FAIL
→ 安全补日志
→ Reset
```

## 电气失败

例如 V6：

```text
已经孤岛
f<47Hz
```

必须：

```text
立即Reset
```

即使日志没满。

---

# 31. 预期控制FAIL不要伪装成程序崩溃

例如：

```text
PREPARE没READY
```

最好：

```text
CONTROLLED FAIL
reason=...
restore
reset
return
```

真正程序/API/安全异常再 `raise RuntimeError`。

---

# 32. Restore要知道“是否真的写过”

PB2 V2曾在信号发现失败时打印：

```text
v_nom 10000→10000
```

虽然没影响，但造成困惑。

成熟脚本：

```python
runtime_config_written=False
```

只有真正写参后才置True。

异常恢复只在True时执行。

---

# 33. finally必须释放控制权

否则下一轮可能出现：

```text
Parameter Control already been given
```

即使异常、Ctrl+C，也要：

```text
release system/parameter control
```

---

# 34. Reset后 MODEL_LOADABLE 是正常的

流程：

```text
Reset
→ MODEL_LOADABLE
→ 人工Load
→ MODEL_PAUSED
```

脚本遇到 MODEL_LOADABLE：

```text
提示Load
```

不是判模型坏。

---

# 35. MAT很小不等于实验没运行

先查：

```text
OpWrite flush/block边界
```

V4模型确实跑了8 s，但Group26/28只有1 KB。

原因不是控制没跑，而是没形成完整记录块。

---

# 36. 诊断拓扑不能直接升级为最终策略

Gate A为了隔离GFM根因加了5个诊断AC Breaker。

后来尝试：

```text
ESS2 P=Q=0
→ 诊断Breaker热合
```

亚毫秒强冲击。

重新审计S14才确认：

```text
S14恢复语义
= Pref分阶段释放 + GridOn/Droop
```

并没有定义逐台热合诊断Breaker。

经验：

> 排错临时结构不能未经策略审计直接成为正式架构。

---

# 37. 先解耦“对象本体”与“系统切换”

早期一次Grid→Island同时改变：

```text
J1
GFL→GFM
角度
功率
其它GFL
```

失败无法归因。

Gate A只问：

```text
ESS1本体能否在被动岛网上自主建压
```

是整个排错最重要的方法论之一。

---

# 38. 外置状态机先验证，再内置

不直接先给模型新增：

```text
NORMAL/PREPARE/HANDOVER
```

而先用Python：

```text
条件驱动外置状态机
```

原因：

```text
失败时可以区分
状态逻辑错
vs
物理handover错
```

物理通过以后再一次性内置。

---

# 39. 固定时间只适合第一层诊断

早期：

```text
3.9 s capture
4.0 s handover
```

适合验证动作链。

最终计划切岛必须：

```text
P/Q满足
→ 连续稳定窗口
→ event capture
→ handover
```

---

# 40. PASS表述必须分层

不能：

```text
zero-reference PASS
→ GFM整体PASS
```

应区分：

```text
zero-reference
formation
hold
passive island
GFL coexistence
grid→island
stable island
reclose
```

---

# 41. 文件命名要表达动作和版本

推荐：

```text
AUDIT_...
PATCH_...
RUN_...
PLOT_...
```

以及：

```text
V1/V2/V3
```

日志带日期/时间戳。

---

# 42. Runtime脚本必须打印状态语义

PB2正确：

```text
STATE=NORMAL
STATE=PREPARE_ISLAND
STATE=READY
STATE=CAPTURE
STATE=HANDOVER
STATE=ISLANDED
```

每个Pause直接打印：

```text
P/Q/f/J1/mode/GridOn/Droop/Pref
```

即使MAT不完整，TXT还能复盘。

---

# 43. 同时保留控制证据和物理证据

控制：

```text
Group26/28
request/mode/candidate/final cmd
```

物理：

```text
Group29
V/I/PI/ModIndex/J1
```

不能互相代替。

---

# 44. Rebuild后旧Signal/Parameter契约可能失效

可能变化：

```text
Parameter ID
Signal ID
部分path
```

所以新Build：

```text
先轻量preflight
必要时重新mapping
```

---

# 45. 当前项目最典型返工清单

| 事件 | 表面问题 | 永久教训 |
|---|---|---|
| PB2 V1 F7 0 hits | 参数不存在 | 历史诊断参数别一律hard-required |
| PB2 V2 executed mode 0 hits | 状态不存在 | 不依赖历史path字符串 |
| PB2 V3仍有3个signal问题 | ranking不够 | 关键状态readonly mapping后固定 |
| PB2 V4 MAT约1 KB | logger坏 | 8 s早于10 s完整记录块 |
| PB2 V5 PREPARE timeout | P/Q没平衡 | 实际是Droop语义判错 |
| PB1 V1 PCC不动 | AGC坏 | Step Time=15 s，AGC根本没enable |
| D2清零五台 | 简化工况 | 位于Final Applied后会制造控制器/Plant失配 |
| ESS2诊断Breaker热合FAIL | GFL不能接 | 诊断拓扑不是S14最终语义 |
| F20固定时间 | 可复现 | 最终必须event capture |
| 早期直接Grid→IslandFAIL | GFM不行 | 先解耦GFM本体和系统handover |

---

# 46. 高风险模型修改脚本模板

```text
A. bdroot(gcs)
B. load_system
C. backup
D. verify prerequisites
E. discover source/destination
F. assert recognized current source
G. minimal edit
H. update diagram
I. assert ports/widths/routes
J. append diagnostics
K. save
L. Build
M. runtime validation
```

---

# 47. RT-LAB Python脚本模板

```text
A. connect
B. require MODEL_PAUSED
C. discover ALL params
D. verify ALL signals
E. Take SYSTEM/PARAMETER control
F. save originals
G. initial writes
H. readback
I. hard interlocks
J. SetPauseTime + Execute
K. read online state
L. condition transition
M. safety gate
N. restore
O. Reset
P. release controls
```

---

# 48. 写脚本前的防返工十问

1. 本轮唯一问题是什么？
2. 能不能先只读Audit？
3. 当前Build已有接口够不够？
4. 哪些变量必须冻结？
5. FAIL时能不能找到第一异常量？
6. 日志能不能完整落盘？
7. 有没有把诊断结构当正式结构？
8. 参数/Signal来自当前Target还是旧文档？
9. 状态语义真的确认了吗？
10. PASS/FAIL分别会关闭哪条路线？

十问没答清，不写正式脚本。

---

# 49. 最终原则

> **脚本自动化的目标不是替人点按钮，而是把每轮实验变成：状态明确、修改唯一、路径可审计、失败可归因、数据可复现、异常可安全恢复的工程证据链。**
