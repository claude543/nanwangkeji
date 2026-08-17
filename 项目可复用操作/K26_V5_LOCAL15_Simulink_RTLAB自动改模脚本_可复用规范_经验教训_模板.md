# K26_V5 / LOCAL15（本地15策略闭环）脚本编写可复用规范与经验教训
## —— 从 Stage00（阶段00）到 Stage15（阶段15）的 Simulink（仿真模型）/ RT-LAB（实时仿真平台）自动化改造实践中总结

> **用途**：总结本轮 LOCAL15（本地15策略闭环）模型改造过程中所有 MATLAB（矩阵实验室软件）/ Simulink（仿真模型）自动化脚本形成的可复用操作、设计规范、失败模式和经验教训。  
>
> **适用范围**：
>
> - 后续 BOARD15（板端15策略）模型侧接口改造；
> - K26_V5 后续版本升级；
> - RT-LAB（实时仿真平台）自动改模；
> - 新增控制 Subsystem（子系统）；
> - 新增 MATLAB Function（MATLAB函数块）；
> - Goto / From（标签发布/读取）信号管理；
> - Mux / Demux（多路复用/解复用）接口改造；
> - Group28（第28采集组）日志追加；
> - 高风险真实接管；
> - 修复代数环、维度、端口、日志等问题。
>
> **核心结论**：
>
> 本轮最值得长期复用的并不是某一段具体脚本，而是一套已经实际踩坑验证过的脚本工作流：
>
> ```text
> 先审计
> ↓
> 再备份
> ↓
> Preflight（预检查）
> ↓
> 发现真实结构
> ↓
> 最小改造
> ↓
> Update Diagram（更新模型）
> ↓
> 逐端口断言
> ↓
> 日志同步
> ↓
> Save（保存）
> ↓
> Build（编译）
> ↓
> Runtime Validation（运行验证）
> ↓
> MAT（MATLAB数据文件）验收
> ```
>
> 以后新的模型改造脚本应尽量沿用这一模式，而不是“找到块 → 直接删线/接线 → 祈祷能Build”。

---

# 1. 这次脚本大致形成了哪几类

本轮 Stage00（阶段00）～Stage15（阶段15）实际上形成了至少七类可复用脚本。

---

## 1.1 Audit Script（审计脚本）

代表：

```text
S00_K26_V5_LOCAL15_AUDIT_AND_TUNABILITY_LOCK_V3.m
```

作用：

```text
不急着改模型
↓
先确认：
当前活动模型是谁
SM_Master（主任务）是否存在
策略层是否存在
Goto / From（标签发布/读取）数量
六设备Pref（有功参考）真正接到哪个Mux端口
PCC Breaker（公共耦合点断路器）真实源是谁
```

长期用途：

> **任何重要改造前都先运行审计脚本，确定“当前真实模型是什么”，而不是按旧截图或旧文件名猜。**

---

## 1.2 Scaffold Script（框架搭建脚本）

代表：

```text
S01_K26_V5_LOCAL15_PARAMETER_PANEL_V2.m
```

作用：

```text
创建参数面板
创建Constant（常数块）
创建Goto（信号发布）
创建统一配置接口
```

这类脚本主要建立：

```text
“以后所有功能都要用的框架”
```

而不是直接改变Plant（仿真对象）。

---

## 1.3 Shadow Script（影子并行脚本）

代表：

```text
S02_K26_V5_BASELINE_AGC_SHADOW_EQUIVALENCE_V4.m
S03_K26_V5_LOCAL15_S2S7_ARBITRATION_SHADOW.m
S04_K26_V5_LOCAL15_GROUP28_AND_ARBITRATED_AGC_SHADOW.m
S05_K26_V5_LOCAL15_EXECUTION_MAPPER_ROUTER_SHADOW.m
S06_K26_V5_LOCAL15_EXECUTION_FAULT_UAPPLIED_SHADOW.m
```

特点：

```text
新逻辑已经建立
↓
已经会算
↓
已经会记录
↓
但暂时不改变真实Plant
```

长期经验：

> **复杂新算法尽量先 Shadow（影子并行），等结果正确以后再 Takeover（真实接管）。**

---

## 1.4 Takeover Script（真实接管脚本）

代表：

```text
S07_K26_V5_LOCAL15_ACTIVE_P_REAL_TAKEOVER.m
```

特点：

```text
第一次真正改变设备Pref来源
```

这类脚本风险最高。

必须比普通结构脚本增加：

```text
更严格Preflight（预检查）
Legacy（原链）保留
单一目标From验证
单一destination（目的端）验证
最终路由断言
MANDATORY BUILD（强制要求编译）
```

---

## 1.5 Extension Script（功能扩展脚本）

Stage08（阶段08）以后大量属于这一类：

```text
在已有已经通过的控制栈旁边
增加新的Normalizer（标准化器）
Manager（管理器）
Allocator（分配器）
Gate（门控器）
Router（路由器）
```

重点原则：

> **已经通过的模块尽量不重写，优先通过旁路扩展加入新功能。**

例如：

```text
Stage08（阶段08）
没有重写S03（阶段03）已经通过的S2/S7 Normalizer（标准化器）

而是新增：
P Extension（有功扩展标准化）
```

---

## 1.6 Repair Script（修复脚本）

本轮实际出现多次：

```text
代数环修复
日志追加修复
CompiledPortWidths（编译后端口宽度）兼容修复
S15（策略15）向量维度修复
Recovery Core（恢复核心）第27输入漏接修复
```

特点：

```text
不是重新设计整套功能
而是只针对已定位的结构问题做最小修复
```

长期经验：

> **当根因已经明确时，修复脚本应尽量小，不要借修复顺便重构整个模型。**

---

## 1.7 Test / Plot Script（测试/绘图脚本）

例如：

```text
PLOT_LOCAL15_15_STRATEGIES_ALL.m
```

作用：

```text
不改模型
只读MAT
自动输出波形
```

这类脚本应与：

```text
结构改模脚本
```

完全分开。

---

# 2. 第一条铁律：永远不要硬编码模型名

本项目已经冻结规则：

```matlab
mdl = bdroot(gcs);
```

中文含义：

```text
bdroot(gcs)
=
取得当前鼠标所在Simulink模型的根模型
```

而不要：

```matlab
mdl = 'K26_V5';
```

---

## 2.1 为什么

项目实际工作中模型会不断：

```text
另存
复制
冻结
测试
```

例如可能出现：

```text
K26_V5
K26_V5_TEST
K26_V5_LOCAL15_FINAL_FROZEN_20260817
```

如果脚本写死：

```matlab
mdl = 'K26_V5';
```

就可能：

```text
用户明明打开的是副本
脚本却修改另一个模型
```

风险很高。

---

## 2.2 推荐标准开头

```matlab
mdl = bdroot(gcs);

if isempty(mdl) || strcmp(mdl,'0')
    error('No active Simulink model detected.');
end

load_system(mdl);
```

中文逻辑：

```text
当前没有活动模型
→ 立即停止

有活动模型
→ 只操作当前活动模型
```

---

# 3. 第二条铁律：Discovery First（先发现真实结构），不要先猜名字

Stage00（阶段00）中最有价值的做法之一：

> **不是直接假设设备控制Mux名称，而是沿真实Pref信号路径反向/正向追踪。**

例如当时不同设备的Mux名称并不完全统一：

```text
PV1_IO_Mux12
PV2_IO_Mux12
ESS1_IO_Mux12
ESS2_IO_Mux12
EV1_IO_Mux
EV2_IO_Mux
```

如果脚本假设：

```text
所有都叫 *_IO_Mux12
```

就会失败。

---

# 4. 发现真实结构时，优先使用“信号语义”而不是“块名字”

例如设备Pref最终来源有明确Tag（标签）：

```text
V5A_FINAL_PV1
V5A_FINAL_PV2
V5A_FINAL_ESS1
...
```

Stage00（阶段00）采用：

```text
寻找读取该GotoTag（标签）的From
↓
检查From输出去了哪里
↓
发现真正的Mux
↓
确认它接的是physical input 6（物理第6输入）
```

这个方法比：

```text
find block whose name contains PV1_IO_Mux12
```

更可靠。

---

## 4.1 通用原则

以后发现控制链优先按：

```text
Signal Tag（信号标签）
↓
Source / Destination（源/目标）
↓
Block Type（模块类型）
↓
Port Number（端口编号）
```

而不是仅按：

```text
Block Name（块名称）
```

---

# 5. 第三条铁律：任何结构改造前先自动备份

本轮重要结构脚本都会：

```text
读取当前模型文件路径
↓
生成时间戳
↓
copyfile（复制文件）
```

例如：

```text
PRE_LOCAL15_STAGE07_REAL_TAKEOVER_yyyymmdd_HHMMSS.slx
```

---

## 5.1 推荐模板

```matlab
modelFile = get_param(mdl,'FileName');

stamp = datestr(now,'yyyymmdd_HHMMSS');

[modelDir,modelBase,modelExt] = fileparts(modelFile);

backupFile = fullfile(modelDir, ...
    sprintf('%s__PRE_CHANGE_%s%s', ...
    modelBase,stamp,modelExt));

copyfile(modelFile,backupFile,'f');
```

---

## 5.2 为什么必须脚本自动做，而不是靠用户记得另存

因为高强度连续改模时最容易发生：

```text
“我以为已经另存了”
```

一旦：

```text
脚本删错线
脚本中途报错
模型已经处于半改状态
```

没有备份会非常麻烦。

因此：

> **高风险脚本自己负责留下恢复点。**

---

# 6. 第四条铁律：Preflight（预检查）通过以后才能碰真实控制线

S07（阶段07）是最典型。

在真实修改六设备Pref以前，脚本先检查：

```text
LOCAL_CONTROL_STACK（本地控制栈）
存在

Command Source Router（控制源路由）
存在

Execution Fault Injector（执行故障注入）
存在

Group28（第28采集组）
存在

前面Stage03～06诊断
全部存在
```

任何一个缺失：

```text
error
→ 立即退出
```

---

# 7. 高风险Preflight（预检查）必须检查“当前来源是否合法”

S07（阶段07）没有直接：

```text
找到Mux input6
→ 删除旧线
→ 接新线
```

而是检查当前源必须属于：

```text
旧V5A标签
或
已经完成S07后的FINAL标签
```

否则：

```text
Refusing takeover
（拒绝接管）
```

也就是：

```text
当前状态不是我认识的状态
→ 不自动修改
```

这是很重要的防误操作设计。

---

# 8. 更进一步：检查这个From是否只服务当前设备

S07（阶段07）还检查：

```text
当前设备Pref的From
有几个destination（目标端）
```

要求：

```text
只能有1个
```

如果：

```text
一个From同时分支到多个位置
```

脚本就拒绝自动改Tag（标签）。

原因：

```text
如果只想修改设备Pref
但这个From还给别的模块供信号
改变GotoTag以后会把其它支路一起改掉
```

长期原则：

> **修改一个信号源前，先确认它是不是“设备局部专用源”。**

---

# 9. 能改Tag（标签）完成接管，就不要重拉已经验证好的线

S07（阶段07）最终真实接管的做法非常值得复用。

原来：

```text
From V5A_FINAL_PV1
↓
PV1 Mux input6
```

没有：

```text
delete_line
add_line
```

而是只：

```matlab
set_param(prefFrom,'GotoTag','AA15_FINAL_APPLIED_PV1');
```

于是原：

```text
From
→ Mux input6
```

物理线完全保留。

---

## 9.1 为什么这样更安全

如果重拉线：

```text
可能接错端口
可能删掉共享branch（共享支路）
可能改变布局
可能误接其它Mux
```

改Tag：

```text
只改变该From读取哪一个逻辑信号
```

风险小很多。

---

# 10. Preserve Legacy（永远保留原链）是这次脚本最成功的原则之一

LOCAL15（本地15策略）不是：

```text
删除V5-A
→ 换LOCAL15
```

而是：

```text
LEGACY_V5A（原V5-A）
LOCAL15（本地15策略）
BOARD15（未来板端15策略）

↓
Command Source Router（控制源路由）
```

所以旧信号始终保留。

---

## 10.1 为什么

任何新架构都需要：

```text
透明回归
```

如果把旧链删掉：

```text
新链出问题以后
没有可比较的安全基线
```

而保留Legacy（原链）以后：

```text
CONTROL_SOURCE = 0
```

可以严格验证：

```text
新统一执行链
=
原V5-A结果
```

---

# 11. 第五条铁律：删除模块必须证明它真的“没在用”

S01（阶段01）删除4个多余From时，没有：

```matlab
if block exists
    delete_block(block);
end
```

而是：

```text
块存在
↓
必须确认BlockType = From
↓
必须确认输出Line = -1
↓
才能delete
```

如果输出有线：

```text
KEEP
不删
```

---

## 11.1 通用安全删除模板

```matlab
h = getSimulinkBlockHandle(p);

if h > 0
    if ~strcmp(get_param(p,'BlockType'),'From')
        error('Unexpected block type');
    end

    ph = get_param(p,'PortHandles');
    ln = get_param(ph.Outport(1),'Line');

    if isequal(ln,-1)
        delete_block(p);
    else
        error('Block is connected; refusing delete.');
    end
end
```

---

# 12. 不要写“存在就删”的暴力脚本

不推荐：

```matlab
try
    delete_block(p);
catch
end
```

因为它会隐藏：

```text
块类型不对
连接关系变化
当前模型版本已经不是预期版本
```

正确思想：

```text
能证明安全
→ 删除

不能证明安全
→ 停止
```

---

# 13. 第六条铁律：脚本应该“可重复运行”，但不能“无限无脑重跑”

这次逐步形成了两种重跑模式。

---

## 13.1 Stage-local Idempotent（同阶段幂等）

意思：

```text
同一个Stage脚本
在同一个Stage状态下再跑一次

不应该：
重复创建块
重复增加端口
重复加线
```

常用方法：

```text
Block不存在
→ CREATE

Block已存在且类型正确
→ KEEP / REBUILD

Goto已存在
→ VERIFY

Line已存在
→ KEEP
```

---

## 13.2 Forward-only Guard（后续阶段保护）

一个更重要的经验：

> **完成后续Stage以后，不应该再随便重跑早期Stage。**

例如S07（阶段07）检查：

```text
Group28已经存在更多后续输入
```

如果判断：

```text
Later Stage Detected
（检测到后续阶段）
```

直接：

```text
error
→ 不允许重跑
```

否则早期脚本可能：

```text
重建旧Subsystem
↓
把后续Stage新增功能删掉
```

---

# 14. 推荐以后所有Stage脚本都显式定义“允许的输入状态”

例如：

```text
Stage N允许：

Stage N-1完成
或
Stage N已经完成
```

如果发现：

```text
Stage N+1 / N+2已经存在
```

就：

```text
abort（停止）
```

这比“脚本自称幂等，所以任何时候都能重跑”更安全。

---

# 15. 第七条铁律：创建/重建Subsystem（子系统）时要限定修改范围

本轮常用模式：

```text
如果目标Subsystem不存在：
→ 创建

如果存在且BlockType确实是SubSystem：
→ 只重建这个Subsystem内部

如果存在但类型不是Subsystem：
→ error
```

不要：

```text
名字一样就直接delete_block
```

---

## 15.1 推荐模式

```matlab
if getSimulinkBlockHandle(subsys) < 0
    add_block('simulink/Ports & Subsystems/Subsystem',subsys);
else
    if ~strcmp(get_param(subsys,'BlockType'),'SubSystem')
        error('Name conflict');
    end
end
```

然后：

```text
只清理subsys内部
```

不动外部其它结构。

---

# 16. `Simulink.SubSystem.deleteContents`（清空子系统内容）比逐块乱删更适合“确定要重建的专用Subsystem”

对于完全由本Stage管理的专用子系统：

```text
AA15_Active_P_Takeover
AA15_STAGE07_TAKEOVER_DIAGNOSTICS
```

可以：

```text
清空内部
↓
按当前版本完整重建
```

但是前提：

> **这个Subsystem必须明确归当前脚本独占管理。**

不要对：

```text
Control System（设备控制器）
PCC Measurements（PCC测量）
原15策略本体
```

这种共享/核心Subsystem直接整体清空。

---

# 17. 第八条铁律：MATLAB Function（MATLAB函数块）创建后，先Update（更新模型）再按端口接线

S07（阶段07）里：

```text
创建MATLAB Function
↓
写入chart.Script（函数脚本）
↓
set_param(mdl,'SimulationCommand','update')
↓
读取Ports（端口）
↓
确认12输入/8输出
↓
再接线
```

这是非常重要的顺序。

---

## 17.1 为什么

MATLAB Function（MATLAB函数块）的输入输出端口通常由函数签名推断。

刚写入代码后，Simulink可能还没有刷新：

```text
真实端口数量
```

如果马上：

```text
add_line到port12
```

可能失败。

所以：

```text
写代码
→ Update Diagram（更新模型）
→ 确认Ports
→ 再接线
```

更可靠。

---

# 18. 第九条铁律：任何Core（核心函数）都要断言端口数

例如S07：

```text
Final Applied Safety Core
（最终执行安全核心）

expected:
12 inputs
8 outputs
```

脚本Update以后直接检查：

```matlab
corePorts = get_param(core,'Ports');

if corePorts(1) ~= 12 || corePorts(2) ~= 8
    error(...);
end
```

不要假设：

```text
“我代码里写了12个输入，
所以Simulink肯定就是12个”
```

S15（策略15）第27输入漏接已经证明：

```text
“设计上有”
≠
“模型里真的正确”
```

---

# 19. 第十条铁律：不仅检查“有几个端口”，还要检查“每个端口是否真正Driven（有驱动）”

S15（策略15）最终真实踩坑：

```text
Recovery Core（恢复核心）
有30个输入
```

其中：

```text
input27
=
phase_valid（相角有效）
```

脚本创建了：

```text
FROM_REC_27
```

但连接循环写成：

```matlab
for i = 1:26
```

所以：

```text
块存在
From存在
Core端口也存在

但：
input27没有线
```

---

## 19.1 以后必须增加端口驱动断言

例如：

```matlab
ph = get_param(core,'PortHandles');

for i = 1:numel(ph.Inport)
    ln = get_param(ph.Inport(i),'Line');

    if isequal(ln,-1)
        error('Core input %d is undriven.',i);
    end
end
```

---

## 19.2 这条经验比“循环写对”更重要

因为以后：

```text
30输入
40输入
```

靠人工数循环非常容易出错。

正确方案：

```text
连接结束以后
自动逐端口审计
```

这样即使：

```text
for i = 1:26
```

写错，脚本最后也会自动发现。

---

# 20. 第十一条铁律：Mux Inputs（Mux物理输入数）和最终标量宽度不是一回事

本项目多次容易混淆。

例如设备控制Mux：

```text
Physical Inputs（物理输入口）
= 8
```

但语义宽度：

```text
Vabc = 3
Iabc = 3
其它6个标量

总宽度：
12
```

所以：

```text
Mux Inputs = 8
```

不等于：

```text
输出向量宽度 = 8
```

---

# 21. Group28（第28采集组）同样要区分“物理Mux输入口”和“诊断标量数”

最终：

```text
AA15_GROUP28_MUX
Inputs = 13
```

表示：

```text
13个Stage诊断向量输入口
```

而最终标量总数：

```text
292
```

MAT：

```text
293行
=
Target Time
+
292标量
```

以后追加日志时，脚本必须同时维护：

```text
Mux物理端口数
+
每段向量宽度
+
最终标量映射
```

不要混成一个数字。

---

# 22. 第十二条铁律：日志不是“最后顺手加”，而是控制功能的一部分

8月13日 Strategy7（策略7）曾经出现：

```text
控制结构已经改好
但Group26日志维度没加完整
```

后来又发现：

```text
RECONSTRUCTION（状态对齐）
真实执行了
但日志100 Hz采不到
```

这说明：

> **如果一个控制机制无法被正式日志证明，它在验收层面就等于没有完全完成。**

因此以后每个Stage脚本应该同时考虑：

```text
控制
+
诊断
+
MAT证据
```

---

# 23. 推荐每个Stage同时新增一段独立Diagnostics（诊断）Subsystem

当前已经形成风格：

```text
AA15_STAGE03_DIAGNOSTICS
AA15_STAGE04_AGC_DIAGNOSTICS
...
AA15_STAGE15_RECOVERY_DIAGNOSTICS
```

优点：

```text
控制链和日志链分开

某Stage新增多少诊断量一目了然

Group28按Stage追加

以后删除/检查更容易
```

---

# 24. 日志追加脚本必须幂等

推荐逻辑：

```text
如果Stage诊断已经接到Group28目标端口
→ KEEP

如果没有
且当前Group28 Inputs正好是前一阶段数量
→ 扩展一个端口并接入

如果Group28状态异常
→ STOP
```

不要：

```text
每运行一次
Inputs = Inputs + 1
```

否则重跑脚本就会重复扩展。

---

# 25. `CompiledPortWidths（编译后端口宽度）` 兼容性踩坑告诉我们：不要过度依赖易变的内部返回结构

当时脚本假设：

```matlab
w = get_param(mux,'CompiledPortWidths');
sigWidth = w.Outport;
```

当前版本实际返回形式和预期不同，导致：

```text
等号右侧输出数目不足
```

不是接线错。

而是：

```text
脚本依赖了一个版本敏感的数据结构
```

---

## 25.1 后续原则

如果任务只是判断：

```text
某Stage诊断是否已经接到Mux第N口
```

优先检查：

```text
PortHandles（端口句柄）
Line（连线）
SrcBlock（源模块）
DstPort（目标端口）
```

而不是为了一个简单结构判断依赖：

```text
CompiledPortWidths复杂字段格式
```

---

# 26. 第十三条铁律：发现兼容性问题时，修“判断方法”，不要乱改已经正确的模型

当 `CompiledPortWidths（编译后端口宽度）` 报错时：

```text
模型接线本身已经成功
```

正确做法：

```text
改收尾脚本
去掉不可靠的宽度读取方法
```

而不是：

```text
把已接好的Mux删掉重新做
```

长期原则：

> **区分“模型错误”和“验证脚本错误”。**

---

# 27. 第十四条铁律：代数环不是“MATLAB Function不够聪明”，而是系统因果关系没设计清楚

本轮两次典型代数环：

### 8月13日论文算法

```text
AGC
→ Strategy2
→ Pexec
→ AGC
```

### Stage13（阶段13）

```text
S13 execution state（执行状态）
→ S12 Device Mode Router（设备模式路由）
→ route state（路由状态）
→ S13
```

共同问题：

```text
当前步输出
→ 下游
→ 当前步又反馈回来
```

---

# 28. 正确修法：显式 Unit Delay（单位延迟）建立离散时间因果

统一：

```text
k步计算
↓
Unit Delay
↓
k+1步使用
```

当前实时步长：

```text
100 μs
```

因此：

```text
100 μs延迟
```

对于：

```text
秒级AGC
模式管理
孤岛恢复
```

可以忽略性能影响，但能完全明确计算顺序。

---

# 29. Persistent（持久状态）能不能用，要看有没有直接反馈环

本轮形成一个更准确的经验：

不是：

```text
“MATLAB Function里不要用persistent”
```

而是：

```text
没有直接当前步反馈环
→ persistent可以合理使用

存在系统级反馈环
→ 显式Unit Delay/State更清晰
```

例如S6（策略6）平滑：

```text
persistent smooth_ref
```

可以。

而S13（阶段13）系统级：

```text
island latch
black latch
```

最终改成：

```text
外部Unit Delay
```

更安全、更可观测。

---

# 30. 第十五条铁律：状态维度必须为Code Generation（代码生成）明确表达

S15（策略15）Build时遇到：

```text
st
MATLAB Function推断：
[1 15]

Simulink外部传播：
[15]
```

桌面Update（更新）长期可以容忍。

RT-LAB代码生成则失败。

---

# 31. `[1×15]` 和 `[15]` 为什么不同

```text
[1×15]
=
二维行矩阵

[15]
=
一维15元素向量
```

数值元素一样。

代码生成接口语义不同。

---

# 32. 最小修复为什么是 Reshape（维度整形），而不是改算法数组方向

没有直接把：

```matlab
zeros(1,15)
```

改成：

```matlab
zeros(15,1)
```

因为：

```text
[15×1]
```

仍然是二维矩阵。

而且会改变原策略本体的数据方向。

最终：

```text
原MATLAB Function
[1×15]

↓
Reshape

1-D [15]

↓
外部接口
```

解决。

---

## 32.1 长期经验

对于：

```text
固定长度状态向量
cmd[15]
status[15]
```

如果桌面仿真和代码生成对形状理解不同：

> **优先在接口边界增加明确的Shape Adapter（形状适配），不要先改经过长期验证的算法内部表达。**

---

# 33. 第十六条铁律：Linked Block（链接模块）不要轻易改内部，能在外层补功能就外层补

S15（策略15）需要：

```text
Grid phase（电网相角）
PCC phase（PCC相角）
```

而模型内部测量/PLL（锁相环）部分存在链接结构。

最终没有：

```text
打开链接内部
硬改PLL
```

而是在SM_Master顶层新增：

```text
AA15_S15_SYNC_PHASE_ESTIMATOR
（S15同步相角估计器）
```

从两侧真实Vabc（三相电压）统一计算相角。

---

## 33.1 为什么

改链接内部可能带来：

```text
破坏库链接
后续恢复困难
多个实例一起被影响
Build差异扩大
```

如果只需要一个附加观测量：

```text
优先外层旁路计算
```

风险更小。

---

# 34. 第十七条铁律：修改真实设备/Breaker以前，先查“当前真正生效的源”

Stage13（阶段13）V1曾经看到Breaker参数：

```text
SwitchTimes（内部开关时间）
```

但真实：

```text
External = on（外部控制启用）
```

实际控制源：

```text
Pulse Generator（脉冲发生器）
```

如果仅看参数框就去修改：

```text
SwitchTimes
```

根本不会改变当前真正行为。

---

## 34.1 后续任何执行器都按这个顺序查

```text
1. Block参数
2. External/Internal模式
3. 实际Inport
4. 当前SrcBlock
5. 当前真正信号源
```

最终以：

```text
当前实际Source（源）
```

为准。

---

# 35. 第十八条铁律：脚本中要区分 Fatal Error（致命错误）和 Warning（警告）

适合直接 `error`（报错停止）的情况：

```text
SM_Master不存在

核心Prerequisite（前置模块）不存在

设备Pref输入断开

当前Pref来源不是预期Tag

需要修改的From有多个destination

MATLAB Function端口数不正确

关键输入没有驱动

最终Tag数量不是1

Group28阶段顺序异常
```

这些继续执行可能破坏模型。

---

## 35.1 适合 warning（警告）的情况

例如：

```text
某个非关键显示块没找到

某个可选诊断名字不同

某个版本不支持ParameterTunabilityLossMsg
```

即：

```text
不会改变核心正确性
```

可以警告但继续。

---

# 36. 不推荐大量空 `try/catch`

例如：

```matlab
try
    do_critical_change();
catch
end
```

会把真正错误吞掉。

推荐：

```text
非关键UI/显示属性
→ try/catch可以

核心连线/端口/算法
→ 出错必须停止
```

---

# 37. 第十九条铁律：`localEnsureLine（确保连线）` 比直接 `add_line` 更适合自动改模

本轮大量脚本逐步采用辅助函数：

```text
如果正确连线已经存在
→ KEEP

如果不存在
→ ADD

如果目标端口已经被错误来源占用
→ STOP / 明确处理
```

这比直接：

```matlab
add_line(...)
```

更适合可重复脚本。

---

# 38. 推荐建立通用辅助函数库

本轮很多Stage脚本都重复出现相似辅助逻辑。

以后BOARD15阶段建议逐步抽成公共工具，例如：

```text
AA15_SCRIPT_UTILS/
```

候选函数：

```text
getActiveModel()
（取得活动模型）

backupActiveModel()
（备份活动模型）

mustHaveBlock()
（必须存在模块）

safeGetParam()
（安全读取参数）

findUniqueGotoByTag()
（按标签寻找唯一Goto）

findUniqueFromByTag()
（按标签寻找From）

ensureLine()
（确保连线）

deleteIfExists()
（存在则安全删除）

deleteSubsystemContents()
（清空专用子系统）

assertPortDriven()
（断言端口已驱动）

assertUniqueTag()
（断言标签唯一）

findExistingLogPort()
（查找已有日志端口）

findFreeTopLevelPosition()
（寻找顶层空白位置）

writeStageMap()
（输出阶段映射文件）
```

---

# 39. 但是公共辅助库也不能过早抽象

本轮前期每个Stage都在快速变化。

如果一开始就设计很复杂的通用框架：

```text
可能反而花大量时间维护抽象层
```

现在LOCAL15已经冻结，进入BOARD15阶段以后再抽：

```text
稳定重复出现的功能
```

更合适。

原则：

> **先重复三次，看清真正共同部分，再抽象。**

---

# 40. 第二十条铁律：脚本要自动输出“它改了什么”

Stage00（阶段00）会导出：

```text
Audit TXT（审计文本）
CFG Constant CSV（配置常数表）
```

S07（阶段07）会输出：

```text
REAL_TAKEOVER_MAP（真实接管映射文本）
```

这非常值得继续。

---

## 40.1 推荐每个结构脚本结束输出

```text
Active Model（活动模型）
Backup File（备份文件）
Created Blocks（新建模块）
Modified Tags（修改标签）
Rewired Ports（重接端口）
Group Mapping（日志映射）
Expected MAT Rows（预期MAT行数）
Next Required Step（下一强制步骤）
```

这样脚本本身同时是：

```text
执行工具
+
修改日志
```

---

# 41. 第二十一条铁律：控制块名称、GotoTag（信号标签）和物理语义要分清

本轮一个实际容易误读的现象：

设备附近Block Name（模块名）仍可能叫：

```text
V5A_FINAL_ESS1_TO_DEVICE
```

但它当前：

```text
GotoTag
=
AA15_FINAL_APPLIED_ESS1
```

所以：

```text
块显示名称
≠
当前真实信号源
```

---

## 41.1 以后脚本判断信号来源应看

```text
BlockType
+
GotoTag
+
Line
+
Destination Port
```

不要只看：

```text
Name
```

---

# 42. 是否应该顺手改旧Block Name（块名称）？

不一定。

改名的收益：

```text
人更容易读
```

但风险：

```text
旧脚本路径失效
旧文档路径失效
```

所以冻结阶段：

> **真实功能判断以Tag和连接为准；名称清理可以单独做“非功能性整理版本”，不要混在关键功能脚本里。**

---

# 43. 第二十二条铁律：一个Stage脚本只解决一个主要问题

好的Stage拆分：

```text
S05：
Mapper + Router

S06：
Fault Injector

S07：
Real Takeover

S09：
Q闭环

S10：
S6/S8辅助

S11：
Mode Decision

S12：
Device Mode

S13：
Breaker Execution

S14：
Black Start Gate

S15：
Recovery
```

这样某个Stage失败时：

```text
定位范围清楚
```

---

# 44. 不要写“超级脚本一次改完所有15策略”

如果一个脚本同时：

```text
改AGC
改Q
改Breaker
改GFM
改日志
改同步
```

失败以后无法判断：

```text
哪一步出错
```

而且回滚困难。

本轮逐Stage方式虽然脚本数量多，但非常适合高风险实时模型。

---

# 45. 第二十三条铁律：什么时候必须Build（编译），什么时候可以暂缓

本轮逐渐形成了清楚判断。

---

## 45.1 参数值变化

例如：

```text
CFG15_EXEC_S06
0 → 1
```

如果已经Tunable（运行时可调）：

```text
不用Build
```

---

## 45.2 Shadow结构增加

如果只是：

```text
旁路计算
不影响Plant
```

理论上最终仍需要Build才能在Target运行。

但如果连续几个Stage属于一条功能链，可以：

```text
先连续完成
↓
到战略节点统一Build
```

---

## 45.3 真实控制路径变化

例如：

```text
六设备Pref来源改变
PCC Breaker来源改变
GridOn/Droop来源改变
```

必须：

```text
Build
+
Runtime Validation（运行验证）
```

S07（阶段07）脚本甚至明确：

```text
MANDATORY NEXT STEP = BUILD + RUNTIME VALIDATION
```

---

# 46. 真实接管以后，第一轮必须先测试Legacy（原链）透明

S07（阶段07）完成以后，不应该马上：

```text
CONTROL_SOURCE = 1
→ LOCAL15
```

而应先：

```text
CONTROL_SOURCE = 0
→ LEGACY_V5A
```

验证：

```text
虽然真实设备已经经过新统一链
但数值结果仍等于旧V5-A
```

通过以后再LOCAL15接管。

这是：

```text
结构改变
↓
功能关闭/旧源
↓
透明回归
↓
新源接管
```

的标准流程。

---

# 47. 第二十四条铁律：测试脚本和结构脚本分离

结构脚本：

```text
add_block
delete_block
add_line
set_param GotoTag
创建Subsystem
```

测试脚本：

```text
修改Tunable参数
读取MAT
生成波形
判断PASS
```

不要在一个脚本里混成：

```text
先改模型
↓
直接跑测试
↓
再改结构
```

否则复现困难。

---

# 48. 推荐目录分层

以后可整理：

```text
Scripts/
│
├─ 01_Audit/
│
├─ 02_Scaffold/
│
├─ 03_Shadow/
│
├─ 04_Takeover/
│
├─ 05_Repair/
│
├─ 06_Test/
│
└─ 07_Plot/
```

这样看到脚本就知道：

```text
它会不会改模型
```

---

# 49. 第二十五条铁律：修复脚本要明确“只修什么，不修什么”

例如S15维度/phase_valid修复应该说明：

```text
本脚本修：
4个输出Reshape
Recovery input27接线

本脚本不修：
S15同步算法
参数阈值
Mode逻辑
Breaker逻辑
```

这样能避免：

```text
一个Fix脚本偷偷改变控制算法
```

---

# 50. 失败以后第一步不是立即写修复脚本，而是提取“第一条真实错误”

S15 Build日志很多。

真正首个决定性错误：

```text
st size [1 15]
vs
[15]
```

正确流程：

```text
找第一条根因错误
↓
定位SID / Block
↓
检查接口
↓
最小修复
```

而不是：

```text
看到20条后续错误
→ 一次改20处
```

很多后续错误只是第一处失败的连锁反应。

---

# 51. 第26条铁律：桌面 `SimulationCommand update（模型更新）PASS` 不等于 RT-LAB Build PASS

本轮S15明确证明：

```text
Simulink Update
PASS

但是：
RT-LAB Code Generation（代码生成）
FAIL
```

原因：

```text
桌面仿真对向量形状更宽容
代码生成更严格
```

所以正式结构验收至少分：

```text
1. Update Diagram（更新模型）
2. RT-LAB Build（实时编译）
3. Load（加载）
4. Execute（运行）
```

不能只做到第1层就宣布成功。

---

# 52. 第27条铁律：Build PASS 也不等于策略PASS

Build只能证明：

```text
模型能生成代码
```

不能证明：

```text
控制方向正确
```

还必须：

```text
Load
Execute
MAT
波形
因果链
```

例如：

```text
S12 source=12
但dP=0
```

模型完全Build/Run成功。

但策略真实闭环证据仍不足。

---

# 53. 脚本输出状态建议统一三级

推荐：

```text
[OK]
=
检查通过

[CREATE] / [ADD] / [TAKEOVER]
=
发生了修改

[KEEP] / [SKIP]
=
当前已经满足，不重复改

[WARN]
=
非关键异常，需要人工注意

[FAIL]
=
不可继续
```

这种控制台输出本轮已经非常好用。

---

# 54. Error Identifier（错误标识符）也值得保留

例如：

```text
S07:NoActiveModel
S07:MissingPrerequisite
S07:UnexpectedPrefTag
S07:PrefBranch
```

优点：

```text
一眼知道出错阶段
```

以后BOARD15脚本建议继续：

```text
B01:...
B02:...
```

统一命名。

---

# 55. 第二十八条铁律：自动脚本应该拒绝“模棱两可”

例如发现：

```text
多个Mux候选
```

Audit（审计）阶段可以：

```text
WARN
列出来人工核查
```

但到了Takeover（真实接管）阶段：

```text
如果不能唯一确定
→ 应STOP
```

因为：

```text
“猜一个最像的”
```

在自动改真实控制链时不可接受。

---

# 56. Discovery Script（发现脚本）和 Modification Script（修改脚本）的容错标准不同

### Discovery（发现）

目标：

```text
尽可能多报告事实
```

可以：

```text
某个非核心名字不同
→ WARN
```

### Modification（修改）

目标：

```text
只在状态完全确定时改
```

应：

```text
核心状态不一致
→ ERROR
```

这两类脚本不要用同一种宽松程度。

---

# 57. 第二十九条铁律：自动布局不是核心，但要避免脚本把模型堆成一团

本轮使用：

```text
localFindFreeTopLevelPosition
（寻找顶层空闲位置）
```

以及：

```text
按row / col布局
```

自动摆Constant、From、Goto、Subsystem。

这对几十个参数/诊断模块非常有价值。

---

# 58. 模块显示属性可以帮助后续人工理解

例如：

```text
AttributesFormatString
```

设置：

```text
S07 REAL takeover
u_applied -> device Pref
finite-value legacy fallback
```

这种提示：

```text
不改变算法
```

但非常有利于：

```text
以后打开模型时知道块干什么
```

建议继续使用。

---

# 59. 第三十条铁律：脚本应该同时考虑“人以后怎么看模型”

自动改模不应只追求：

```text
能跑
```

还应：

```text
命名清楚
布局清楚
参数集中
Diagnostics独立
Tag语义明确
```

因为后续：

```text
调试
交接
论文复现
BOARD15迁移
```

都需要人重新打开模型理解。

---

# 60. 本轮真实踩坑 → 可复用经验总表

| 实际问题 | 根因 | 最终修法 | 长期经验 |
|---|---|---|---|
| S6（策略6）怎么调PCC都不动作 | 改错了策略真实输入 | 追线到 `PV_profile_pu（光伏可用功率曲线）` | 测试前追真实输入，不按名称猜 |
| Strategy7（策略7）↔AGC代数环 | 当前步闭环反馈 | Pexec加入100 μs Unit Delay（单位延迟） | 状态反馈必须显式离散因果 |
| S13（阶段13）↔S12（阶段12）代数环 | executed mode（执行模式）直接反馈 | 状态和动态证据加入Unit Delay | 系统级状态优先外显状态块 |
| Group26日志维度没更新 | 前面脚本报错导致后段没执行 | 独立日志收尾脚本 | 控制结构和日志完整性分开验收 |
| `CompiledPortWidths`报错 | 版本返回结构差异 | 改用端口/连线结构检查 | 少依赖版本敏感内部接口 |
| RECONSTRUCTION（状态对齐）MAT看不到 | 状态持续时间小于日志周期 | 增加最小驻留0.05 s | 可验证性也应进入状态机设计 |
| Breaker控制源判断错 | 只看SwitchTimes参数 | 检查External和真实输入源 | 当前生效路径比Mask参数更重要 |
| S12 source正确但请求为0 | 测试没有真正激励功能 | 补非零专项工况 | selected source正确不等于闭环PASS |
| S14 Stage3数字有了但设备动作不够明确 | 状态和执行证据分离 | 增加Stage3 PV专项 | 状态机必须验收“状态+动作” |
| S15 `[1×15]` vs `[15]` | MATLAB/Simulink代码生成形状差异 | 接口加Reshape | 代码生成接口要明确维度 |
| S15 input27未接 | 循环边界1:26 | 补第27接线并加驱动审计 | 端口存在不等于端口已驱动 |
| 设备From名字仍叫V5A | 历史Block Name未更新 | 用GotoTag判断真实源 | 名称不等于真实信号源 |
| 早期脚本重跑风险 | 后续Stage已在旧Subsystem上扩展 | Later-stage guard（后续阶段保护） | 幂等只在允许状态内成立 |

---

# 61. 推荐的未来标准结构脚本骨架

以后新增结构脚本可以从下面逻辑开始。

```matlab
function B01_example_modification
% B01 示例结构脚本
% Purpose（目的）:
%   ...
% Changes（修改范围）:
%   ...
% Does NOT change（明确不修改）:
%   ...

%% 1. Resolve active model（取得当前活动模型）
mdl = bdroot(gcs);

if isempty(mdl) || strcmp(mdl,'0')
    error('B01:NoActiveModel', ...
        'Open the intended model and click inside it.');
end

load_system(mdl);

%% 2. Resolve file and backup（确认模型文件并备份）
modelFile = get_param(mdl,'FileName');

if isempty(modelFile) || ~isfile(modelFile)
    error('B01:ModelFile','Save the model first.');
end

% backup...

%% 3. Preflight（预检查）
% mustHaveBlock(...)
% assertExpectedTag(...)
% assertExpectedRoute(...)
% detectLaterStage(...)

%% 4. Create/reuse blocks（创建或复用模块）
% if missing -> CREATE
% if exists with correct type -> KEEP/REBUILD
% if conflict -> ERROR

%% 5. Update before wiring dynamic ports
% （动态端口块先更新模型）
set_param(mdl,'SimulationCommand','update');

%% 6. Wire with ensureLine（安全连线）
% ensureLine(...)

%% 7. Postflight assertions（改后断言）
% assert all inputs driven
% assert tags unique
% assert route exact

%% 8. Diagnostics / Group log（日志）
% append exactly once

%% 9. Final update（最终模型更新）
set_param(mdl,'SimulationCommand','update');

%% 10. Save only after assertions（全部断言通过后保存）
save_system(mdl);

fprintf('B01 COMPLETE\n');
fprintf('NEXT: BUILD + RUNTIME VALIDATION\n');
end
```

---

# 62. 一个更完整的“真实接管脚本”额外骨架

如果脚本要改：

```text
Pref
Qref
GridOn
Droop
Breaker
Fref
```

等真实执行接口，还必须增加：

```text
A. 验证Legacy源仍存在

B. 验证当前目标端口只有一个明确来源

C. 验证该来源只服务目标设备

D. 创建新的Final信号并Update

E. 先确保Final信号可解析

F. 最后一步才改真实From Tag/Line

G. 改后重新断言目标端口真实来源

H. 再断言Legacy仍被Router保留

I. 强制要求Build + Runtime Validation

J. 第一轮先跑Legacy透明回归
```

---

# 63. 推荐未来建立 Stage Manifest（阶段清单）

这是本轮还没有完全自动化、但很值得BOARD15继续做的改进。

每个Stage定义：

```text
Stage ID（阶段编号）

Prerequisites（前置Stage）

Created Blocks（新增模块）

Created Tags（新增标签）

Modified Routes（修改线路）

Group28 Port（日志端口）

Expected Scalar Count（预期标量数）

Requires Build（是否必须编译）

Requires Runtime Test（是否必须运行测试）
```

脚本运行前：

```text
读取当前模型
↓
判断它究竟处于哪个Stage
```

能进一步减少：

```text
重跑旧脚本破坏新模型
```

---

# 64. 推荐未来给每个Stage生成 Modification Report（修改报告）

当前很多脚本已经有TXT/控制台输出。

可以进一步统一生成：

```text
B01_MODIFICATION_REPORT_yyyymmdd_hhmmss.md
```

记录：

```text
模型文件
备份
新增块
删除块
修改Tag
修改线
端口数
日志映射
Update结果
Build待办
```

这样仓库历史会更容易复盘。

---

# 65. 推荐未来加入自动“连接完整性审计”

尤其针对大输入Core（核心）：

```text
Recovery Manager
Mode Manager
Q Allocator
```

自动输出：

```text
Port 1  <- tag xxx
Port 2  <- tag xxx
...
Port N  <- tag xxx
```

并检查：

```text
无未接输入
无重复错误源
```

这会直接避免S15 input27问题再次发生。

---

# 66. 推荐未来加入“Tag唯一性审计”

Global Goto（全局标签发布）适合大模型。

但最大风险：

```text
不小心创建两个相同Global GotoTag
```

所以每个新增Tag以后检查：

```text
Goto count = 1
```

必要时还检查：

```text
From count >= expected
```

---

# 67. 推荐未来把“结构检查”和“数值验收”分成两个脚本

例如：

```text
B01_BUILD_BOARD15_INTERFACE.m
（建立BOARD15接口）

B01_AUDIT_BOARD15_INTERFACE.m
（只读结构审计）
```

这样改完以后：

```text
可以反复运行Audit
```

而不会再次修改模型。

这是比所有检查都混在Modification脚本里更稳的长期结构。

---

# 68. 推荐未来把“模型修改”与“测试工况”彻底解耦

结构脚本只负责：

```text
建立接口
```

工况通过：

```text
Tunable Parameter（在线可调参数）
```

或：

```text
独立Test Harness（测试框架）
```

实现。

不要为了每个测试：

```text
重新写一个改结构脚本
```

LOCAL15已经证明：

```text
Build一次
+
在线改参数
```

效率远高于：

```text
每个工况改结构
```

---

# 69. 什么时候应该写“脚本”，什么时候手工操作反而更安全

适合脚本：

```text
重复创建大量同类块

批量参数面板

6设备相同接口修改

几十路Goto/From

Group28日志

重复端口审计

批量生成波形
```

适合人工确认：

```text
第一次判断陌生模型真正控制源

多个候选块无法唯一确定

高风险电气拓扑变化

链接库内部语义不清楚
```

即：

> **脚本最适合“规则明确、重复性强”的工作；语义不确定时先人工/只读审计，不要让脚本替你猜。**

---

# 70. 这次脚本工作最重要的五个层级观念

## 层级1：模型事实

```text
真实Block
真实Tag
真实Port
真实Line
```

---

## 层级2：脚本结构

```text
创建
连接
断言
```

---

## 层级3：代码生成

```text
Update能不能过
RT-LAB Build能不能过
```

---

## 层级4：实时执行

```text
Load
Execute
Overrun
```

---

## 层级5：功能证据

```text
MAT
波形
PASS判据
```

任何一个Stage只有五层都闭合，才能真正冻结。

---

# 71. “脚本成功”的五级定义

以后不要只说：

```text
脚本运行成功
```

应该具体说：

### Level 1（级别1）

```text
脚本无MATLAB异常
```

### Level 2（级别2）

```text
Simulink Update PASS
```

### Level 3（级别3）

```text
RT-LAB Build PASS
```

### Level 4（级别4）

```text
Load / Execute PASS
```

### Level 5（级别5）

```text
MAT功能验收PASS
```

真正交付只认：

```text
Level 5
```

---

# 72. 脚本版本命名也形成了值得保留的习惯

例如：

```text
S00_..._V3.m
S01_..._V2.m
S02_..._V4.m
```

版本号应该表示：

```text
同一Stage内的脚本修订
```

而不是：

```text
模型总体版本
```

Stage编号：

```text
S00 / S01 / ...
```

表示：

```text
架构推进顺序
```

两者分开。

---

# 73. 修复脚本命名建议

推荐：

```text
FIX_<问题>_V01.m
```

例如：

```text
FIX_STRATEGY7_AGC_RECON_ALGEBRAIC_LOOP_V01.m
```

或者：

```text
S15_BUILD_FIX_V1_VECTOR_SHAPE_AND_PHASE_VALID.m
```

名字应该直接说明：

```text
修什么
```

避免：

```text
fix2.m
newfix_final.m
真的最终版.m
```

---

# 74. 建议脚本头部固定写四件事

每个脚本开头写：

```text
PURPOSE（目的）

PREREQUISITES（前置条件）

CHANGES（会修改什么）

DOES NOT CHANGE（明确不修改什么）
```

S07（阶段07）脚本这方面已经做得很好：

```text
这是第一次真实改变Pref来源
Legacy不会删除
BOARD15仍保留
```

这种说明能显著减少后续误用。

---

# 75. 建议高风险脚本头部直接打印WARNING（警告）

例如：

```text
WARNING:
This stage changes the ACTUAL six-device Pref route.
（警告：本阶段会改变六设备真实有功参考路径）
```

而普通Shadow脚本则明确：

```text
NO REAL TAKEOVER
（不真实接管）
```

让运行脚本的人一眼知道风险级别。

---

# 76. 本轮脚本经验可以进一步形成一个三层资产

建议以后仓库保存：

```text
A. 原始Stage脚本
=
历史和复现

B. Script Engineering Guide
（脚本工程规范）
=
本文件

C. Shared Utilities
（共享辅助函数）
=
以后BOARD15逐步抽取
```

---

# 77. 推荐归档目录

```text
项目可复用操作/
└─ Simulink_RTLAB自动改模/
   │
   ├─ 01_自动改模脚本规范.md
   ├─ 02_真实接管安全规范.md
   ├─ 03_Goto_From与端口审计.md
   ├─ 04_Group日志追加规范.md
   ├─ 05_代数环与UnitDelay处理.md
   ├─ 06_CodeGen维度问题.md
   └─ templates/
      ├─ STAGE_TEMPLATE.m
      ├─ AUDIT_TEMPLATE.m
      └─ TAKEOVER_TEMPLATE.m
```

当前这份文档可以直接作为：

```text
01_自动改模脚本规范.md
```

的基础。

---

# 78. 最终压缩成12条“以后写改模脚本必须遵守”的规则

```text
1.
永远：
mdl = bdroot(gcs)

2.
先Discovery（发现）
再Modification（修改）

3.
任何高风险改造前自动Backup（备份）

4.
Preflight不通过
不碰真实控制线

5.
优先按Tag/Line/Port追真实结构
不要只猜Block Name

6.
能改局部From Tag
就不要重拉已验证的设备线

7.
Legacy（原链）必须保留
新链通过Router接管

8.
所有MATLAB Function创建后
先Update
再断言端口
再接线

9.
不只检查端口数量
还要检查每个输入真正Driven

10.
状态反馈出现环路
用显式Unit Delay建立离散因果

11.
控制功能、日志、Build、Runtime、MAT
五层都通过才算完成

12.
早期Stage脚本检测到后续Stage以后
必须停止，不能无脑重跑
```

---

# 79. 如果只保留一个标准脚本流程，就保留这一套

```text
打开目标模型
↓
点击目标模型
↓
mdl = bdroot(gcs)
↓
确认FileName
↓
自动Backup
↓
审计Prerequisites
↓
发现真实信号源
↓
确认当前状态是允许修改的状态
↓
创建/复用专用Subsystem
↓
创建MATLAB Function / Router / Goto / From
↓
Update Diagram
↓
断言端口数
↓
安全接线
↓
逐输入检查Driven
↓
修改真实路由（如果本Stage需要）
↓
再次Update
↓
断言真实最终路由
↓
追加Diagnostics
↓
断言日志映射
↓
保存修改映射TXT/MD
↓
save_system
↓
RT-LAB Build
↓
Load
↓
Execute
↓
MAT验证
↓
冻结
```

---

# 80. 最后总结

这次LOCAL15脚本工作的真正价值，不只是：

```text
“用MATLAB自动加了很多块”
```

而是逐步形成了一种适合大型RT-LAB实时模型的自动化改造方法：

> **脚本不应该“替人盲改模型”，而应该把人工工程判断固化成可重复的安全检查、最小修改和自动断言。**

最成熟的模式不是：

```text
脚本越短越好
```

而是：

```text
先证明当前模型状态
↓
只在状态明确时修改
↓
每一步都能检查
↓
出错立即停止
↓
修改后能自动证明“我确实改对了”
```

这也是为什么本轮一些脚本看起来比“简单add_block/add_line”长很多。

多出来的部分主要不是控制算法，而是：

```text
安全性
可重复性
版本兼容
可回滚
可验证
```

对于当前这种：

```text
六逆变器
RT-LAB实时运行
15种策略
大量Goto/From
多阶段改造
最终还要迁移BOARD15
```

的项目，这些工程能力本身非常值得长期保存和继续复用。
