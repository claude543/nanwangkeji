---
title: "K26_K50_CLEAN_P1｜脚本编写规范与成功范式：改模、Python运行、MATLAB计算、模型审计"
date: 2026-09-18
project: "暑期南网科技项目 / yanshou_V7 / K26_K50_CLEAN_P1"
status: "截至2026-09-18本窗口成功经验冻结版"
---

# 0. 文件定位

这不是通用编程教程，而是把本窗口在 ESS2（储能2）黑启动接回、BASETEST（基础诊断模式）、A0/P0/C1因果试验、P环参数修复、Restore-state7（恢复状态7）、S14-50接管、S14-60 Primary（一次有功-频率协调）以及完全正式恢复改模前全审计过程中，已经实际验证过的脚本经验冻结下来。

覆盖五类实际工作，其中前四类是用户要求的主类别，第五类是本窗口后期证明必须单独存在的目标机闸门：

1. MATLAB Patch（MATLAB改模脚本）与独立 Verifier（独立验证器）；
2. Python Runner（Python实时运行脚本）；
3. MATLAB DirectMAT（MATLAB直接读取MAT计算脚本）；
4. Audit（模型只读审计脚本）；
5. Target Verify（目标机接口验证脚本，不Execute）。

以后新窗口、Codex（代码代理）或其它助手生成脚本，优先继承本文件，不再从零设计工作流。

总原则：

> **先证明当前结构，再修改；先证明Build后的目标机接口，再Execute（执行）；先保留原始物理证据，再修后处理工具；任何自动化都不能破坏因果试验。**

---

# 1. 所有脚本共同遵守的证据纪律

## 1.1 证据优先级

以后出现脚本、旧MD、当前SLX和实时数据相互矛盾，按下面顺序处理：

```text
最高：
真实 RT-LAB MAT
+ manifest（运行清单）
+ FileID（文件编号）
+ DirectMAT结果

↓
Python Runner运行日志 / events（事件）/ snapshots（快照）

↓
Build后的
GetParametersDescription（参数描述）
GetSignalsDescription（信号描述）
+ 实际write/readback（写入/回读）

↓
当前SLX静态结构

↓
Patch / Verifier / Audit脚本的设计目标

↓
规划MD / 聊天里“下一步准备做”
最低
```

因此必须一直区分：

```text
脚本准备修改
≠ 已经修改

SLX里有参数
≠ RT-LAB在线可调

Build成功
≠ 电气PASS

Runner跑到结束
≠ 动态稳定PASS

Analyzer报错
≠ 物理试验失败
```

## 1.2 各类脚本职责不能互相冒充

### Patch（改模脚本）

证明：

```text
模型结构、默认值、端口、连线和保存持久化被正确修改
```

不证明：

```text
目标机动态稳定
```

### Verifier（独立验证器）

证明：

```text
修改结果在保存/重开后真实存在
```

不能偷偷修模型。

### Python Runner（实时运行脚本）

负责：

```text
Build后接口发现
t=0配置
readback
时序执行
运行证据
manifest
FileID
```

不应该替代MAT数据做最终稳定性裁判。

### MATLAB DirectMAT（MAT直接计算）

负责：

```text
精确找到本轮MAT
真实时间轴
事件对齐计算
指标、图、紧凑结果包
```

不应偷偷把临时阈值变成最终验收标准。

### Audit（只读审计）

证明：

```text
当前保存模型是什么
```

不能替代：

```text
Build后的编译事实
实时动态事实
```

---

# 2. MATLAB Patch（改模脚本）正确规范

## 2.1 Patch前必须先写清“修改合同”

禁止直接根据模块名猜：

```text
这个块应该是P环
端口3应该是Id
这个参数应该能在线写
```

正式改模前至少确认：

```text
精确模型路径
BlockType（模块类型）
精确输入/输出数量
端口真实来源/去向
Stateflow / MATLAB Function完整源码
相关参数和默认值
需要保护的旧行为
修改后的预期行为
如何验证
失败如何回滚
```

本项目已经出现过的典型例子：

```text
PI regulator with anti-windup D
= ESS2 P有功PI

PI regulator with anti-windup D1
= ESS2 Q无功PI
```

如果只按名字或相邻位置猜，很容易改错。

## 2.2 事务式Patch流程固定

正式范式：

```text
正式模型只读 preflight（修改前检查）
↓
byte-identical scratch copy（字节相同试验副本）
↓
scratch修改
↓
postassert（修改后断言）
↓
scratch save exactly once（副本只保存一次）
↓
close / reload（关闭 / 重开）
↓
再次postassert
↓
正式模型 whole-file backup（整文件备份）
↓
正式模型重新preflight
↓
应用相同修改
↓
postassert
↓
正式 save exactly once
↓
close / reload
↓
persistence verify（持久化验证）
↓
独立Verifier
```

如果正式保存后关键步骤失败：

```text
whole-file rollback（整文件回滚）
+
回滚后完整性检查
```

不要在正式模型上边试边改。

## 2.3 whole-file SHA（整文件哈希）只能做来源记录，不再做滚动开发硬门

错误经验：

```text
PATCH_E2_HEALTH_HANDOVER_R2
→ Original-model bytes differ from audited source
→ No write performed
```

用户模型本来就会继续修改。整个SLX字节变化并不说明模型选错。

后续：

### 可以记录

```text
SLX SHA256
文件大小
时间戳
```

作为 provenance（来源记录）。

### 不允许作为唯一硬门

```text
当前SLX必须等于几小时前审计文件的整个SHA
```

### 真正硬门

```text
目标核心路径存在
目标模块类型正确
关键端口数正确
旧语义仍可识别
关键保护连线正确
目标核心没有与本Patch冲突的修改
```

即：

> **用目标语义判定能否安全修改，不用整个SLX哈希阻断正常滚动开发。**

## 2.4 Patch要识别原版、上一版、已是最新版

成熟脚本至少处理：

```text
A. 原版
→ 完整应用

B. 已完整应用上一版
→ 定点升级

C. 已经是当前最新版
→ 不重复修改，只验证

D. 中途失败/混合状态/未知结构
→ 停止写入，要求定点审计
```

避免重复：

- 增加Unit Delay（单位延时）；
- 增加端口；
- 扩Mux（多路复用器）；
- 覆盖已经升级过的函数。

## 2.5 改模包必须自包含

R2.1曾出现：

```text
SELFTEST_E2_HEALTH_HANDOVER_R2_1
```

调用：

```text
e2hh_bundlecheck_R2
```

而包里实际是：

```text
e2hh_bundlecheck_R2_1
```

另外辅助函数不一定在MATLAB path（搜索路径）中。

R2.2正确做法：

每个入口：

```text
PATCH
SELFTEST
VERIFY
```

先用：

```matlab
mfilename('fullpath')
```

找到自身根目录，再临时 `addpath（加入搜索路径）`，结束恢复原path。

交付前做 dependency closure（依赖闭包）：

```text
扫描所有helper调用
↓
每个调用都必须能在包内解析
```

不能依赖“我自己MATLAB环境里碰巧有这个函数”。

## 2.6 脚本包SHA和模型SHA用途分开

`SHA256_MANIFEST.json（SHA256清单）`适合证明：

```text
脚本包没有损坏/缺文件
```

不用于证明：

```text
当前正式SLX必须等于旧SLX
```

## 2.7 普通Simulink块优先，不继续滥用MATLAB Function

能够由：

```text
Constant（常数）
Switch（选择）
Product（乘法）
Min / Max（最小/最大）
Saturation（限幅）
Rate Limiter（变化率限制）
Unit Delay（单位延时）
Memory（记忆）
Mux / Demux（复用 / 解复用）
Relational Operator（关系比较）
Logical Operator（逻辑运算）
```

实现的逻辑，不优先增加新 `MATLAB Function（MATLAB函数模块）`。

原因：

- 连线更透明；
- 审计容易；
- 维度更直观；
- RT-LAB代码生成风险更低；
- 在线参数更容易形成 `/Value`；
- 后续cleanup更容易定位；
- 避免产生第二套隐性控制器。

## 2.8 Stateflow（状态流）/MATLAB Function源码修改先拿唯一句柄

失败写法：

```matlab
chartAt(path).Script = src;
```

当前R2023b下可能命中对象集合。

正确：

```matlab
hit = chartAt(path);
assert(numel(hit)==1);
hit.Script = src;
```

建议统一封装：

```text
getChartScript
setChartScript
```

命中0或>1都停止。

## 2.9 在线参数必须显式暴露，不能假设内部PI参数自动可写

C1第一次没有真正Execute的原因：

```text
SLX有P PI Kp/Ki
但Build后的runtime parameter candidates = []
```

所以：

```text
saved model有参数
≠ target runtime参数存在
```

本项目成功做法：

```text
显式Constant
→ Product / Switch
→ 原控制链
```

例如：

```text
原比例：
Error → Kp4(.06)

修改：
Error
→ Kp4(1)
→ AA15_E2_P_KP_APPLY
   × CFG_E2_DIAG_P_KP_RT(.06)
→ 原后级
```

Ki同理。

之后必须：

```text
Rebuild
→ GetParametersDescription
→ 精确找到/Value
→ write
→ readback
```

才算真正在线可调。

## 2.10 Patch不把自己当Build裁判

Patch自测可以做：

```text
普通Simulink小Harness（测试环境）
函数语法检查
连线检查
保存/重载检查
```

但当前模型涉及：

```text
ARTEMiS
SSN
Stubline
SM / SS
OpComm
OpWrite
```

最终编译事实仍以RT-LAB Rebuild为准。

## 2.11 ASCII（ASCII字符集）代码生成卫生

出现过：

```text
host_preseparate.py
GBK decode
UnicodeDecodeError
```

这不是控制逻辑错误。

正确修：

```text
新增Function源码中的非ASCII注释改ASCII
可执行逻辑不变
```

路径尽量ASCII，模型目录不要堆中文压缩包/临时目录。

禁止修改RT-LAB全局预处理脚本来掩盖工程文件问题。

## 2.12 Patch正确示范骨架

```matlab
function result = PATCH_EXAMPLE(modelRoot)

MODEL = 'K26_K50_CLEAN_P1';
modelFile = fullfile(modelRoot,[MODEL '.slx']);

% A. 只读身份与目标语义
facts = preflight_target(modelFile);
assert(facts.safe);

% B. 自测/依赖
SELFTEST_EXAMPLE;

% C. scratch
scratch = make_byte_identical_scratch(modelFile);
patch_one_model(scratch);
assert_postconditions(scratch);
save_reload_once(scratch);
assert_postconditions(scratch);

% D. 正式备份与二次preflight
backup = backup_whole_file(modelFile);
facts2 = preflight_target(modelFile);
assert(facts2.safe);

try
    patch_one_model(modelFile);
    assert_postconditions(modelFile);
    save_reload_once(modelFile);
    assert_postconditions(modelFile);
    result.status = 'PATCH_SAVED_AND_PERSISTENCE_VERIFIED';
catch ME
    rollback_whole_file_if_needed(modelFile,backup);
    rethrow(ME);
end
end
```

这是结构示范，不代表这些helper已经存在。

---

# 3. 独立 Verifier（验证器）规范

## 3.1 必须真正只读

不能调用：

```text
set_param
add_block
delete_block
add_line
delete_line
save_system
```

也不能：

```text
VERIFY内部调用PATCH
```

否则验证不独立。

## 3.2 必须验证的内容

至少包括：

```text
目标模块存在
模块类型正确
参数默认值正确
端口数正确
关键输入/输出来源正确
函数语义正确
Mux/Demux宽度正确
旧保护路径没有被绕开
save/reload后仍存在
```

## 3.3 Verifier自身错误时只修Verifier

本窗口R1H就是：

```text
Patch已成功
Verifier解析/注释逻辑误报
```

正确：

```text
修Verifier
→ 再只读验证
```

不是再跑一遍Patch。

## 3.4 缺旧Patch PASS日志也不机械返工

如果后续更高等级证据已经证明：

```text
Target参数真实暴露
成功写入/readback
真实Execute使用
```

就不因为历史日志缺一份而重新改已经正确的模型。

---

# 4. Python Runner（RT-LAB实时运行脚本）规范

## 4.1 参数和信号ID必须动态发现

必须调用：

```python
RtlabApi.GetParametersDescription()
RtlabApi.GetSignalsDescription()
```

按：

```text
完整path
suffix
leaf
property
唯一匹配
```

解析。

不能长期冻结数字ID，因为每次Build可能变化。

## 4.2 连接前工程身份硬门

正式Runner至少确认：

```text
project = yanshou_V7
model = K26_K50_CLEAN_P1
state = MODEL_PAUSED
target clock ≈ 0
```

目标步长若能可靠读取，也检查100 μs。

whole-file SLX SHA仍然只记录，不作为滚动模型唯一身份门。

## 4.3 全部控制写入发生在第一次Execute前

标准：

```text
discover
↓
take parameter control
↓
snapshot originals
↓
write完整t=0合同
↓
readback所有写入
↓
总Enable最后写
↓
hard interlock
↓
First Execute
↓
以后禁止控制参数写入
```

正式Runner可以在执行中读信号、记录事件，但不能临时用Host改控制逻辑。

## 4.4 A/B必须 fresh Reset → Load

“在线可调”不等于“同一个Execute里应该扫参数”。

A0/P0/C1等正式因果试验必须：

```text
fresh Reset
→ Load
→ t=0写固定合同
→ Execute
```

否则积分器、滤波器和电气状态不同。

## 4.5 不破坏合法模型合同来得到想要的观察窗

A0第一版为了让Pref=0，错误把BASETEST合法目标改0，导致：

```text
state9
fail92
```

正确：

```text
合法target仍=-0.005
但在真正非零pickup之前Pause
```

这样：

```text
配置合法
+
实际观察PrefApplied=0
```

## 4.6 Runner停止判据分层

可以立即停：

```text
NaN / Inf
参数/信号合同不唯一
关键readback失败
工程/模型身份错误
明确禁止的控制接管
模型明确hard fail
FileID/Recorder结构异常
```

一般只记录，不由Host提前停：

```text
短时V/f/P/I波动
普通功率跟踪越界
短时CurrentLimit
ModHeadroom变化
资格暂时丢失
软timeout
普通振荡
```

用户原则是：

> 普通动态先让它跑并记录，再靠MAT分析；模型自己的严重保护仍然保留。

## 4.7 每轮必须建立唯一自描述Run目录

推荐：

```text
D:/E2RUN/<case>_<timestamp>_<nonce>
```

至少包括：

```text
manifest.json
run.txt
discovery.json
parameter candidates
parameters before/after
host samples
runtime events
pause clocks
MAT inventory
expected_mat_files
FileID
version/case
status
electrical_verdict
```

并明确：

```text
electrical_verdict = NOT_EVALUATED_BY_RUNNER
```

## 4.8 FileID必须统一并回读

正式Run前：

```text
G27
G29
G30
```

使用同一FileID，写入后readback。

当前最终成功Run：

```text
FileID = 695899370
```

对应：

```text
G27 rootdiag_ess2_data_695899370
G29 d1_gfm_superpack_data_695899370
G30 freqdiag_ess1_data_695899370
```

DirectMAT以后直接从manifest读取。

## 4.9 特殊Mode源必须显式列为required

Restore-state6一直不进7的根因不是门控太严，而是第五个Mode源：

```text
K26_K50_CLEAN_P1
/SS_Slave2
/AA15_ESS2_RESTORE_CONFIG
/CFG_ESS2_BASETEST_ENABLE
/Value
```

仍为1。

其它几个Mode写成5并不能替代它。

所以以后：

```text
发现N个通用Mode
```

不能代表所有真实Mode入口都统一。

必须逐个：

```text
exact discovery
write
readback
```

最终成功Run是五个Mode都=5。

## 4.10 Build后先做 Target Verify（目标机接口验证）

以后固定：

```text
Rebuild
↓
Target Contract Verify（目标机接口验证）
↓
正式58~60s Runner
```

Target Verify可以完全不Execute，检查：

```text
参数是否存在
候选是否唯一
可写/回读
恢复原值
Mode源
FileID
Recorder宽度
新Enable
能力摘要
```

这样把“接口错误”挡在正式物理Run之前。

## 4.11 Target Verify必须可逆

标准：

```text
读原值
→ 写probe
→ readback probe
→ 立即恢复原值
→ readback original
→ finally中还有emergency restore
```

## 4.12 57.9999 s不要误判成“没到58 s”

在100 μs步长中：

```text
57.9999 s
```

可能就是计划58秒终点的最后离散采样时刻。

不能因此盲目再Execute。

用：

```text
target >= 57.5s
+
计划事件/尾段覆盖完整
```

等合同判断。

## 4.13 Run结束后优先保留PAUSED，不自动Reset

原因：

```text
DirectMAT还要读取/确认MAT
```

推荐：

```text
到终点
→ Pause
→ finalize manifest
→ 不自动Reset
```

## 4.14 Host收尾工具错误不强迫重跑物理试验

历史Run FileID 659728245：

```text
目标时钟约57.9999s
物理采集完整
但最后Pause确认报工具性问题
```

manifest是：

```text
FAILED_AFTER_EXECUTE
```

分析器后续只在严格条件下把它分类为：

```text
COMPLETE_58S_HOST_FINAL_PAUSE_WARNING
```

而不是假装干净，也不重新跑物理试验。

## 4.15 Runner示范骨架

```python
def main():
    assert_static_experiment_contract()

    assert_project_model_state()
    assert_target_clock_near_zero()

    params = discover_parameters()
    signals = discover_signals()
    assert_unique_required_paths(params, signals)

    take_parameter_control()

    original = snapshot_original_values()

    write_readback(all_t0_config)
    write_readback(file_ids)

    assert_all_special_mode_sources()

    write_readback(master_enable_last)

    execute_attempted = True
    lock_future_parameter_writes()

    run_and_record_model_driven_events()

    pause_preserve_mat()
    finalize_manifest(
        electrical_verdict="NOT_EVALUATED_BY_RUNNER"
    )
```

---

# 5. MATLAB DirectMAT（MAT直接计算脚本）规范

## 5.1 必须从manifest找Run

固定链：

```text
manifest
→ version / case / status
→ FileID
→ exact expected MAT filenames
→ exact MAT
```

不要按“最近修改的rootdiag”猜。

## 5.2 manifest过滤同时检查

至少：

```text
version prefix
case
status / classification
execute_attempted
target clock
expected_mat_files
FileID
```

P0 R1曾因为从A0复制后残留A0 case过滤，把正确P0 Run过滤掉。

错误时必须列出：

```text
候选manifest路径
version
case
status
被拒绝原因
```

不能只写“No manifest”。

## 5.3 支持显式Run目录

最好允许：

```matlab
result = ANALYZE_XXX('D:/E2RUN/exact_run_dir');
```

方便工具修复后重新分析同一物理数据。

## 5.4 `FAILED_AFTER_EXECUTE`不能一概接受

只针对已知Host收尾问题做窄接受，例如必须同时满足：

```text
execute_attempted=true
target_clock >= 57.5
失败原因明确是final Pause确认
model_fail_seen=false
nonfinite_seen=false
FileID有效
expected MAT完整
```

其它失败拒绝。

## 5.5 大MAT先whos再load

```matlab
W = whos('-file',path);
```

然后：

1. 优先冻结变量名；
2. 动态后缀时要求唯一数值二维矩阵；
3. 行数必须符合当前Recorder版本；
4. 多候选时停止，不猜。

当前最终R2：

```text
G27 = 120 rows = 119 signals + time
G29 = 95 rows = 94 signals + time
G30 = 145 rows = 144 signals + time
```

旧版本行数不能继续硬套。

## 5.6 使用真实target-time时间行

检查：

```text
NaN/Inf
非递增
median dt
min/max positive dt
large gaps
short gaps
```

不要简单用样本号乘0.0004或0.001。

## 5.7 不用插值制造State事件

诸如：

```text
Restore-state7
S14-50
Beta start/full
S14-60
```

取第一个真实满足样本。

## 5.8 按事件窗口计算，不只算全程均值

至少按：

```text
state6
state7
S14-50
beta start
beta full
post-handover
S14-60
CorrectionGain full
late window
```

分开计算。

## 5.9 “全程最大变化率”和“Primary阶段变化率”分开

最终Run：

```text
Max_CommandRate_All = 0.0025 pu/s
```

包含前面pickup。

而S14-60 Primary真实上限：

```text
0.0005 pu/s
```

所以Analyzer必须输出阶段化指标，避免误解。

## 5.10 FFT只叫描述性频谱，不叫模态

可以写：

```text
dominant descriptive frequency（主要描述性频率）
```

不能在没有特征值分析时写：

```text
系统模态 = x Hz
```

## 5.11 未映射通道保留Legacy命名

没有正式数据字典：

```text
LegacyG30_017
```

优于凭印象命名。

## 5.12 DirectMAT不自动下最终电气PASS

脚本输出：

```text
事实
时序
窗口指标
限制状态
频谱
图
```

最终工程判断另写MD。

## 5.13 后处理工具出错不重跑RT-LAB

只要：

```text
Runner实际Execute完成
Raw MAT还在
```

如果问题只是：

```text
manifest解析
CSV
figure
路径字符串
```

就修MATLAB分析器。

## 5.14 大MAT分组加载

```text
G27 → calculate → compact → clear
G29 → calculate → compact → clear
G30 → calculate → compact → clear
```

最终上传compact ZIP，不要求再次上传几百MB原始MAT。

## 5.15 DirectMAT示范骨架

```matlab
function result = ANALYZE_EXAMPLE(searchRoot)

C = local_config();

run = resolve_run(searchRoot,C);
validate_manifest(run);

g27 = find_exact_mat(run.expected.G27);
g29 = find_exact_mat(run.expected.G29);
g30 = find_exact_mat(run.expected.G30);

G27 = load_exact_family(g27,C.g27Rows);
[G27,timeAudit] = sanitize_time_axis(G27);

events.state7 = first_time(...);
events.s14_50 = first_time(...);
events.beta_full = first_time(...);
events.s14_60 = first_time(...);

metrics.handover = event_window_metrics(...);
metrics.primary = event_window_metrics(...);

write_csv_json_png(...);
make_compact_zip(...);
end
```

---

# 6. Audit（模型只读审计脚本）规范

## 6.1 Audit和Patch严格分离

Audit不能：

```text
set_param
add/delete block
add/delete line
save_system
SetVariable
连接RT-LAB目标
```

最终全审计还采用：

```text
用户已打开当前模型
SimulationStatus=stopped
Dirty=off
```

并尽量不 `load_system（加载模型）`、不Update Diagram（更新图），避免触发回调。

## 6.2 审计前后证明模型未改变

输出：

```text
source hash before
source hash after
Dirty before/after
SimulationStatus before/after
```

当前最终审计：

```text
before hash = after hash
Dirty off → off
stopped → stopped
```

## 6.3 审计要输出结构数据库，而不是只打印console

成熟结果至少包括：

```text
MODEL_PROPERTIES
ALL_BLOCKS
CRITICAL_SCOPE
DIRECT_EDGES
INPUT_PORTS
PHYSICAL_PORT_INVENTORY
FROM/GOTO
FUNCTION_INDEX
完整FUNCTION SOURCE
PARAMETERS
STATES_AND_INITIALIZATION
SUBSYSTEM_PORT_NAMES
CRITICAL_INPUT_TRACES
OUTPUT_CONSUMERS
RECORDER_SETTINGS
RECORDER_INPUT_ASSEMBLY
COMMUNICATION_BOUNDARIES
TARGETED_PATTERN_INVENTORY
DESIGN_QUESTIONS
ISSUES
BOUNDARY_NOTES
RESULT.json
```

这样新窗口可以直接接手。

## 6.4 语义靠真实路径/端口，不靠名字

审计要证明：

```text
source block/outport
→ destination block/inport
```

`From/Goto（标签传输）`：

```text
From tag
→ 可见Goto
→ Goto输入真实来源
```

名称只是辅助。

## 6.5 普通信号边和物理电气边分开

SPS/专用物理库的保守端口不是普通有向signal line（信号线）。

遇到库边界：

```text
explicit physical/library boundary
```

可以作为合法边界，不强行深入猜内部。

## 6.6 无法证明就REVIEW/UNRESOLVED

不要为了“全PASS”自动填补。

最终审计有：

```text
blocker=0
review=11
```

11项后来逐项人工闭合为：

```text
STUB显式边界
Three-Phase V-I Measurement物理测量边界
明确From/Goto/OpComm路径
```

最终：

```text
remaining static blockers=0
```

## 6.7 Audit要围绕下一次设计问题

最终全审计不是无限导出，而是同时定义了29个设计问题，覆盖：

```text
S14
Frequency Secondary（二次频率恢复）
V4.8 q-bias（q轴偏置）
ESS1余量
ESS2能力
P/Q联合能力
命令所有权
OpComm
G27/G29/G30
planned-island兼容
```

并达到：

```text
MissingAnchors = 0
```

以后Audit固定采用：

```text
全局库存
+
本次Patch定向问题
```

## 6.8 审计输出ZIP必须自动验包

本窗口曾两次上传错包：先上传审计工具包，再上传历史P0结果包。

所以新增：

```text
RUN_AND_VALIDATE_ESS2_COMPLETE_RESTORE_AUDIT_R1.m
```

只有结果ZIP包含：

```text
RESULT.json
00_RUN_LOG.txt
01_MODEL_PROPERTIES.csv
02_CRITICAL_SCOPE.csv
03_DIRECT_EDGES.csv
04_NATIVE_FROM_GOTO.csv
05_FUNCTION_INDEX.csv
06_PARAMETERS.csv
08_CRITICAL_INPUT_TRACES.csv
09_COMMUNICATION_BOUNDARIES.csv
09_RECORDER_SETTINGS.csv
10_TARGETED_PATTERN_INVENTORY.csv
11_DESIGN_QUESTIONS.csv
12_ISSUES.csv
...
```

才打印：

```text
[AUDIT PACKAGE VALIDATION PASS]
```

以后大型审计默认带这种wrapper（包装入口）。

## 6.9 静态设计闭合不等于动态结果提前已知

当前已经正式达到：

```text
PREPATCH_STATIC_DESIGN_INPUTS_CLOSED
```

含义：

```text
下一次正式规划设计不再有已知关键静态接口模糊
```

不代表：

```text
Patch一定Build成功
100 μs一定无Overrun
S14-70/75/80一定稳定
```

这些留给下一阶段动态验证。

## 6.10 Audit示范骨架

```matlab
function result = AUDIT_EXAMPLE

mdl = bdroot;

assert(strcmpi(get_param(mdl,'SimulationStatus'),'stopped'));
assert(strcmpi(get_param(mdl,'Dirty'),'off'));

hashBefore = fileSha256(get_param(mdl,'FileName'));

export_model_properties(...);
export_blocks_and_edges(...);
export_function_sources(...);
export_parameters_and_states(...);
export_port_traces(...);
export_recorders_and_opcomm(...);
export_design_question_coverage(...);
write_issues_and_boundaries(...);

hashAfter = fileSha256(get_param(mdl,'FileName'));
assert(strcmpi(hashBefore,hashAfter));
assert(strcmpi(get_param(mdl,'Dirty'),'off'));

result.archive = zip_results(...);
end
```

---

# 7. Target Verify（目标机接口验证）作为固定中间闸门

虽然用户原任务只列四类脚本，但本窗口已经证明：

> **Build和正式Runner之间必须固定增加Target Verify。**

顺序：

```text
Patch / Verifier
↓
RT-LAB Rebuild
↓
Target Verify：不Execute
↓
正式Runner
```

它检查：

```text
新旧Runtime参数是否存在
候选是否唯一
参数可写/回读
特殊Mode是否完整
FileID
信号是否可读
Recorder宽度
新增Enable/能力接口
```

这层专门拦截“模型改对了，但Target接口没按预期暴露”的问题。

---

# 8. 失败→教训总表

| 失败/返工 | 真正原因 | 后续永久规则 |
|---|---|---|
| `chartAt(path).Script=`失败 | Stateflow对象集合赋值 | 取得唯一handle后再赋Script |
| `GBK UnicodeDecodeError` | RT-LAB预处理编码问题 | 新函数注释ASCII化；不动平台全局脚本 |
| A0第一版fail92 | 为Pref=0破坏合法BASETEST target | 保持合法目标，用时序/Pause得到零命令窗口 |
| P0 Analyzer找不到manifest | 复制A0时遗留case过滤 | version+case+status+expected files联合过滤 |
| `\E` warning | Windows反斜杠进入format string | 报错路径用`D:/...`或正确转义 |
| C1第一次未Execute | PI内部参数Target未暴露 | 显式Constant接口+Rebuild+Target发现 |
| R2正确模型被Patch拒绝 | whole-model SHA硬门 | SHA只记录，目标语义preflight做硬门 |
| R2.1 helper找不到 | 包依赖与函数版本名错误 | 自包含路径+依赖闭包 |
| state6长期不进7 | Restore Config第五Mode仍=1 | 特殊Mode逐项发现、写入、回读 |
| 先怀疑±50W/3s太严 | MAT显示连续28.55s已满足，计数仍不启动 | 先用数据分解门控，不先放宽阈值 |
| Host末尾Pause报错 | 物理Run已完成，工具收尾失败 | 保留MAT，窄分类，不重跑 |
| 57.9999s想再Execute | 离散时间终点理解错误 | 用目标步长/覆盖合同判终点 |
| Primary R1漏第五Mode | 缺Build后Target合同闸门 | Build→Target Verify→正式Run |
| Q Enable打开但Q PI没动作 | `QrefEff≈Qmeas`，误差本身≈0 | 区分“开关有效”和“参考源有无任务” |
| 把Beta当Authority | 控制权和允许幅值混淆 | 变量/文档必须分开 |
| 把S14-60叫完整恢复 | 实际只是ownership+small Primary | 结论按证据等级，不扩大 |
| 想马上删Recorder | 70/75/80/88仍要取证 | Control Cleanup与Recorder Cleanup分开 |

---

# 9. 成功脚本优先参考

## 9.1 改模

第一优先：

```text
PATCH_E2_HEALTH_HANDOVER_R2_2.m
```

学习：

```text
自包含
依赖闭包
语义preflight
自测
scratch
formal
rollback
版本升级识别
```

最小改模范式：

```text
PATCH_K26_K50_ESS2_P_PI_RUNTIME_GAINS_R1.m
```

诊断历史Patch保留主要用于以后cleanup反查新增位置。

## 9.2 Python Runner

当前首选：

```text
RUN_K26_K50_ESS2_HEALTH_HANDOVER_PRIMARY_FORMAL_R2.py
```

因果模板：

```text
RUN_K26_K50_ESS2_PQ_CAUSAL_A0_FORMAL_R2.py
RUN_K26_K50_ESS2_PQ_CAUSAL_P0_FORMAL_R2.py
RUN_K26_K50_ESS2_P_CAUSAL_C1_KI0_FORMAL_R2.py
```

功率参数模板：

```text
RUN_K26_K50_ESS2_PONLY_KI0_SMALLPOWER_FORMAL_R1.py
RUN_K26_K50_ESS2_PONLY_KI05_SMALLPOWER_FORMAL_R1.py
```

## 9.3 MATLAB DirectMAT

当前首选：

```text
ANALYZE_K26_K50_ESS2_HEALTH_HANDOVER_PRIMARY_R2.m
```

历史根因链：

```text
A0
P0_R2
C1_KI0_R2
KI0_SMALLPOWER
KI05_SMALLPOWER
```

## 9.4 Audit

当前首选：

```text
AUDIT_K26_K50_ESS2_COMPLETE_RESTORE_PREPATCH_R1.m
ESS2_COMPLETE_RESTORE_AUDIT_SCOPE_R1.json
RUN_AND_VALIDATE_ESS2_COMPLETE_RESTORE_AUDIT_R1.m
```

## 9.5 Target Verify

```text
VERIFY_K26_K50_ESS2_RESTORE_MODE_TUNABLE_R1_1.py
```

---

# 10. 明确不要再执行的旧版本

```text
PATCH_E2_HEALTH_HANDOVER_R2
```

原因：whole-file SHA/bytes硬门错误。

```text
PATCH_E2_HEALTH_HANDOVER_R2_1
```

原因：helper版本/路径依赖错误。

```text
RUN_K26_K50_ESS2_HEALTH_HANDOVER_PRIMARY_FORMAL_R1.py
```

原因：漏写Restore Config第五Mode源。

```text
ANALYZE...HEALTH_HANDOVER...R1 / R1_1
```

原因：旧manifest筛选假设，已被R1_2/R2修复。

第一次A0 Runner：

```text
错误把合法target改0
```

P0 DirectMAT R1：

```text
残留A0 case过滤
Windows路径format问题
```

---

# 11. 生成新脚本前的固定检查表

## 11.1 Patch前

```text
[ ] 当前目标是否已经Audit？
[ ] 精确path/port/parameter是否确认？
[ ] 哪些模块禁止改？
[ ] whole-file SHA是否只记录？
[ ] 能不能用普通Simulink块？
[ ] 是否有自测？
[ ] 是否scratch first？
[ ] 是否正式整文件backup？
[ ] 是否save once + reload？
[ ] 是否独立只读Verifier？
[ ] 是否可rollback？
[ ] 工具包是否自包含？
```

## 11.2 Build后

```text
[ ] Rebuild PASS？
[ ] Runtime参数是否真的暴露？
[ ] 新信号是否可读？
[ ] 所有Mode源是否完整？
[ ] 参数write/readback是否可逆？
[ ] FileID是否可写？
[ ] Recorder真实行数多少？
[ ] Target Verify是否通过？
```

## 11.3 Runner前

```text
[ ] fresh Reset → Load？
[ ] PAUSED @ t≈0？
[ ] 一轮是否只增加一个控制层？
[ ] t=0全部写入是否readback？
[ ] Enable是否最后打开？
[ ] Execute后是否锁死Host写参？
[ ] 普通波动是否继续取证？
[ ] manifest是否完整自描述？
```

## 11.4 DirectMAT前

```text
[ ] exact manifest？
[ ] exact FileID？
[ ] exact MAT filenames？
[ ] 当前G27/G29/G30行数？
[ ] whos先于load？
[ ] 真实time row？
[ ] 事件对齐窗口？
[ ] 全程指标与阶段指标分开？
[ ] 不插值制造状态事件？
[ ] Legacy通道不乱命名？
[ ] 如果Analyzer错误，原MAT是否还可复用？
```

## 11.5 Audit前

```text
[ ] model stopped？
[ ] Dirty=off？
[ ] Audit完全只读？
[ ] 函数源码完整导出？
[ ] 端口/通信/Recorder导出？
[ ] Issues/Boundary Notes输出？
[ ] 下一Patch定向问题覆盖？
[ ] before/after证明模型未改？
[ ] 结果ZIP自动验包？
```

---

# 12. 当前推荐的最终工作流

以后优先固定为：

```text
问题/需求
↓
只读Audit
↓
设计冻结
↓
Logic Harness（逻辑测试）
↓
历史MAT Replay（历史MAT回放）
↓
Patch
↓
独立Verifier
↓
Simulink离线Compile/Update
↓
RT-LAB Rebuild
↓
Target Contract Verify
↓
fresh Reset / Load
↓
正式Runner
↓
保留PAUSED + 原始MAT
↓
DirectMAT
↓
数据结论MD
↓
再决定下一次改模
```

这比：

```text
想到一点
→ 改一点
→ Build
→ 跑60s
→ 再发现接口问题
```

能显著减少返工。

---

# 13. 后续删除诊断改造时的脚本纪律

用户后续准备删除今天及此前为定位问题添加的一些诊断模型改造。

必须：

```text
从成功Patch归档反查“当初具体加了什么”
↓
当前模型重新Audit
↓
写专用Cleanup Patch（清理改模脚本）
↓
scratch删除
↓
postassert
↓
正式整文件backup
↓
formal cleanup
↓
独立Verifier
↓
Rebuild
↓
Target Verify
```

不能在Simulink GUI里凭名字随便删除。

当前可以列入**诊断清理候选**的主要结构：

```text
AA15_BASETEST_SELECT_DAMP_D
AA15_BASETEST_SELECT_DAMP_Q
AA15_BASETEST_SELECT_SLOW_Q
AA15_BASETEST_SELECT_LF_Q

ESS2_Control/BaseTestDiagEnable
Power Control Loop/BaseTestDiagEnable

CFG_E2_DIAG_P_LOOP_ENABLE
CFG_E2_DIAG_Q_LOOP_ENABLE
CFG_E2_DIAG_DIRECT_IREF_ENABLE
CFG_E2_DIAG_DIRECT_ID_TARGET_PU
CFG_E2_DIAG_DIRECT_IQ_TARGET_PU

AA15_DIAG_P_ALPHA_EFF
AA15_DIAG_Q_ALPHA_EFF
AA15_DIAG_DIRECT_ID_RATE
AA15_DIAG_DIRECT_IQ_RATE
AA15_DIAG_DIRECT_IREF_MUX
AA15_DIAG_DIRECT_IREF_SELECT
```

但当前建议保留：

```text
P Kp/Ki在线可调功能
```

后续可以把名字中的 `DIAG（诊断）` 正式化。

绝对不要在“诊断清理”中误删：

```text
ESS2 Restore Executor正式物理恢复核心
true breaker-inner Vabc（真实断路器内侧三相电压）
Current Adapter（电流执行适配器）
真实Current Regulator（电流调节器）反馈
GFL Stage0/1/2工程结构
S14-40 / S14-50 / S14-60
Ownership Blend（所有权混合）
Coordinator availability/baseline/authority
Restore-state7健康资格
软异常freeze/hold（冻结/保持）语义
ESS1唯一GFM核心
```

Recorder（记录器）当前不要清理：

> **至少等S14-70/75/80/88完成动态验收后，再做Recorder Cleanup（记录器清理）。**

---

# 14. 最终冻结

本项目后续判断一个脚本是否“正确”，不看代码是否复杂，而看：

```text
是否基于当前真实模型
是否保护正式SLX
是否有scratch和rollback
是否自包含
是否只改变本轮变量
是否Build后先验证Target接口
是否Execute前完成配置与回读
是否Execute后停止Host改参
是否保留原始物理MAT
是否能从manifest精确追到FileID/MAT
是否把工具错误和电气错误分开
是否让下一窗口可以直接复核
```

满足这些，才进入“可复用正确脚本”归档。
