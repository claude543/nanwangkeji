---
title: Simulink / RT-LAB 大模型脚本编写与物理拓扑恢复——可复用经验
date: 2026-09-10
version: V1.0
tags:
  - Simulink
  - RT-LAB
  - OPAL-RT
  - MATLAB
  - 模型审计
  - 自动改模
  - SPS
  - 物理拓扑
  - 脚本经验
---

# Simulink / RT-LAB 大模型脚本编写与物理拓扑恢复——可复用经验 V1.0

> 适用范围：大型 Simulink / Specialized Power Systems（SPS，专用电力系统）/ RT-LAB 模型的只读审计、自动改模、结构整理、物理连接恢复、保存后核验和 Build 前验收。
>
> 核心原则：**先冻结“真值”和允许修改范围，再写脚本；先证明修改前合同，再修改；先在副本验证，再碰正式模型；任何未知都不能自动解释成“可删”“为空”或“通过”。**

---

# 1. 这次问题的本质

本轮并不是控制算法先出错，而是模型整理阶段将 SPS 物理电气分支误当成普通 Simulink 信号线处理，导致原本属于同一电气节点的若干 branch（分支）被删除。

表现为：

```text
原模型：
多个物理端口属于同一个电气节点

整理后：
节点被切成若干彼此孤立的子节点

结果：
phase-to-ground（三相对地）测量在 Build / Update 时报告
“connected between two isolated networks”
```

因此必须长期区分：

```text
普通 Simulink 信号连接
≠
SPS / Simscape conserving physical connection（保守物理连接）
```

不能将两者共用一套“悬空线”“源—目标”“分支树”判断逻辑。

---

# 2. 永久规则一：文件身份与“已加载模型对象”必须分开验证

## 2.1 文件 SHA256 正确，不代表 MATLAB 内存中的同名模型对象就是这个文件

错误思路：

```matlab
确认 D:\...\K26_K50.slx 的 SHA256 正确
↓
发现 bdIsLoaded('K26_K50') == true
↓
直接复用已经加载的 K26_K50
```

问题：

- 已加载对象可能来自另一目录；
- 可能是旧副本；
- 可能由此前脚本加载；
- 可能有未保存修改；
- 文件 SHA 只证明磁盘文件，不证明内存对象。

正确流程：

```text
先确定磁盘源文件绝对路径
↓
校验 SHA256
↓
如果同名模型已经加载：
    running → 停止，不处理
    Dirty=on → 停止，禁止丢弃用户修改
    Dirty=off → 关闭
↓
重新 load_system(精确SHA文件)
↓
再次验证加载对象与精确文件身份
```

### 可复用原则

> **文件身份（disk identity）和模型对象身份（loaded-model identity）是两个不同合同。二者必须分别验证。**

---

# 3. 永久规则二：`.slx` 文件存在性优先使用 `isfile`

本项目环境中，不能用：

```matlab
exist(path,'file') == 2
```

作为 `.slx` 是否存在的唯一判断。

推荐：

```matlab
if ~isfile(path)
    error(...)
end
```

原因：

- MATLAB 对不同文件类型、模型文件和环境可能返回不同 `exist` 编码；
- 将 `==2` 写成硬前置会产生“文件实际存在，但脚本判不存在”的假失败。

### 可复用原则

> **文件语义问题使用 `isfile/isfolder`；不要把 `exist()==2` 当成通用文件合同。**

---

# 4. 永久规则三：模型名称不能作为稳定唯一标识

本轮曾经出现：

```text
J1_Load2
```

在源模型中无法按逐字符显示名称命中的情况。

大型 Simulink 模型中名称可能包含：

- 换行；
- 多个空格；
- Windows / MATLAB 显示差异；
- 历史重命名残留。

因此只要任务允许，应建立**规范化名称（canonical name）**。

本轮采用：

```matlab
lower(regexprep(name,'\s+',''))
```

即：

```text
统一小写
+
删除所有空白
```

但不能过度规范化：

```text
不要删除：
数字
下划线
标点
设备编号
有语义的字符
```

否则：

```text
Transformer1
Transformer 1
Transformer_1
```

可能被错误合并。

### 必须做唯一性检查

```text
canonical name
↓
必须且只能命中1个块
↓
0个 → FAIL
>1个 → FAIL
```

不能自动选择第一个。

---

# 5. 永久规则四：Connectivity first，Name second

任何自动改线，都必须优先按照：

```text
端口
真实连接
消费者
物理节点
```

判断。

名称只用于定位候选。

## 普通信号

正式合同应尽量表达成：

```text
source block / outport
→
destination block / inport
```

而不是：

```text
“附近那个叫 XXX 的块”
```

## 物理网络

正式合同应表达成：

```text
Block A | LConn/RConn
+
Block B | LConn/RConn
+
...
=
一个电气节点
```

而不是只保存“某根线长什么样”。

---

# 6. 永久规则五：SPS 物理 branch 禁止使用普通信号线思维

历史经验已经证明，SPS branched physical connection（分支物理连接）不能可靠依赖：

```text
LineParent
LineChildren
SrcBlockHandle / DstBlockHandle
```

来解释其电气意义。

尤其禁止：

```text
没有普通 Src
→
悬空

没有普通 Dst
→
无消费者

→ delete_line
```

因为物理 branch 可能是：

```text
A
├─ B
├─ C
└─ Ground
```

其中某个 branch 对象本身不具备普通信号线意义下的完整“源→目标”，但仍是完整电气节点不可缺少的一部分。

### 永久禁区

以后所有 Cleanup（清理）脚本：

```text
若端口类型不是标准 Outport/Inport
→
默认保护

若发现：
LConn
RConn
PMIO
Simscape conserving port
SPS physical branch
→
禁止泛化 dangling-line 删除
```

---

# 7. 永久规则六：物理网络按“电气节点”修复，不按“画布上的线段”修复

真正有工程意义的是：

```text
哪些物理端口属于同一个节点
```

而不是：

```text
原来画了几根线
每根线的 Handle 是多少
Branch 几何形状是什么
```

例如：

```text
A + B + C + Ground
```

可以在画布中以多种 branch geometry（分支几何）表示，只要电气连通关系等价。

因此恢复合同应是：

```text
节点成员集合
+
端口身份
+
连通性
+
无组外连接
```

而不是要求 line handle 完全等于历史文件。

---

# 8. 永久规则七：物理拓扑恢复必须有“真值模型”

不要根据报错临时推断：

```text
这里大概应该接地
这里应该接回母线
```

应优先寻找：

1. 最后一个已成功 Build / Load / Run 的模型；
2. 对应 SHA256；
3. 历史审计；
4. 物理拓扑说明；
5. 实验数据与设备映射。

本轮冻结：

```text
K26_K50
SHA256 =
23fc0cd10c8dc12da8e58541d3b137d0f950d9f364ad4556296f83973bcee4e3
```

作为物理拓扑真值。

正确逻辑：

```text
目标模型 != 真值模型
↓
先做差分
↓
只有能由真值模型证明的缺失连接才恢复
```

---

# 9. 永久规则八：不能把“39项端口差异”理解成“39根错误线”

物理差分往往以 endpoint（端点）为单位报告。

同一个被拆坏的大节点：

```text
A
B
C
D
E
F
```

可能导致：

```text
A看到B/C/D/E/F缺失
B看到A/C/D/E/F缺失
...
```

因此几十项差异可能只代表少量真实电气节点。

正确流程：

```text
endpoint differences
↓
按共同成员聚类
↓
形成 electrical node components
↓
确定真正损坏的节点数量
```

本轮：

```text
39项非中性端差异
```

实际收敛为：

```text
PCC/grid-side 三相节点        3
设备公共母线三相节点          3
ESS1/EV1径向中间节点          3
--------------------------------
共                           9

再加6个高压侧Yg中性点         6
--------------------------------
最终已知恢复对象              15个电气节点
```

---

# 10. 永久规则九：修改范围必须先封闭

正式脚本必须有：

```text
ALLOW LIST（允许修改集合）
```

而不是只写：

```text
“不要改其它东西”
```

例如本轮：

```text
允许：
15个已确认损坏的SM_Master物理节点

禁止：
其它SM物理节点
三个SS物理网络
Stubline
PMIO配置
OpComm
OpWrite
控制参数
MATLAB Function
普通控制信号
```

修改前先验证：

```text
所有现存差异
⊆
允许修改集合
```

如果：

```text
出现任何差异 ∉ allow-list
```

立即停止。

这比修改完成后再检查更重要。

---

# 11. 永久规则十：unknown 不能转换成“空”“不存在”或“安全”

危险写法：

```matlab
try
    ...
catch
    result = [];
end
```

随后：

```text
[] → 没连接 → 可以删除
```

这会把：

```text
API读取失败
```

伪装成：

```text
真实无连接
```

正确原则：

```text
read success
+
value known
→ 才允许决策

read failed / ambiguous
→ UNKNOWN
→ 禁止破坏性操作
```

尤其对于：

```text
物理端口
Branch
Goto/From作用域
RT-LAB特殊块
编译属性
```

必须严格执行。

---

# 12. 永久规则十一：Scratch-first，而不是正式模型先试

任何可能破坏结构的自动改模都应：

```text
正式模型
↓
完整字节备份
↓
复制 Scratch
↓
在 Scratch 执行完整修改
↓
postassert
↓
保存
↓
关闭
↓
重新加载
↓
persistent postassert
↓
PASS
↓
才允许修改正式模型
```

Scratch 必须是：

```text
当前正式SLX的字节相同副本
```

不能重新从旧模型创建一个“类似测试模型”，因为无法覆盖当前模型的真实复杂结构。

---

# 13. 永久规则十二：正式修改必须是事务式

推荐固定模板：

```text
0. identity
1. preflight
2. exact backup
3. scratch transaction
4. scratch reload verification
5. formal re-preflight
6. formal in-memory edit
7. postassert
8. save once
9. close/reload
10. persistent postassert
11. report
```

若失败：

### 保存前失败

```text
不保存
关闭内存模型
重新加载磁盘正式文件
```

### 保存后失败

```text
关闭模型
恢复完整字节备份
校验恢复后的SHA256
重新加载
```

不能只“把刚才改的几根线改回来”。

原因：

> 脚本失败时，你未必知道到底修改过哪些内部对象；整文件回滚才是可靠事务。

---

# 14. 永久规则十三：修改后必须验证“没有越界改变”

针对物理拓扑修复，本轮采用多层保护：

## 14.1 全物理拓扑

最终：

```text
目标 SM_Master 全部物理端口邻接关系
=
23fc真值模型
```

这是最强的物理结果判据。

## 14.2 普通 Simulink 信号

建立：

```text
source outport
→
destination inport
```

的完整 fingerprint（指纹）。

修复前后：

```text
必须完全相同
```

## 14.3 MATLAB Function

使用：

```text
Path + Script
```

构建指纹。

非目标改物理线时：

```text
全部源码必须完全不变
```

## 14.4 模块数量

```text
before block count
=
after block count
```

如果任务只是修线，模块数变化就是异常。

## 14.5 物理块参数

至少保护：

```text
BlockType
ReferenceBlock
MaskValues
```

避免“线修好了，但变压器/负荷/测量参数被改”。

---

# 15. 永久规则十四：修改脚本与 Build 验证职责分离

静态脚本可以证明：

```text
结构
连接
代码
参数
保存持久化
```

但不能替代：

```text
Update Diagram
Compiled dimensions
Compiled data types
SPS网络组装
ARTEMiS/SSN合同
RT-LAB代码生成
目标机Build
```

因此状态要明确：

```text
STATIC VERIFIED
≠
BUILD VERIFIED
```

正确状态机：

```text
STATIC_REPAIR_COMPLETE
↓
RT-LAB REBUILD
↓
BUILD_PASS
↓
LOAD
↓
STAGE0
↓
动态试验
```

---

# 16. 永久规则十五：Build 报错后沿“第一个失败点”反向追，不做全局补丁

发生 Build 错误：

```text
不要：
看到维度错 → 全模型到处加 Reshape
看到断线 → 自动把所有悬空线重连
看到物理错误 → 全局加 Ground
```

正确：

```text
错误 sink（失败终点）
↓
向上追 source / physical node
↓
与最后成功基线比较
↓
找到 FIRST DIVERGENCE（第一个差异）
↓
只修该原因
```

本轮就是从：

```text
prim_EV1 phase-to-ground
“two isolated networks”
```

反向追到：

```text
SM_Master物理branch在整理阶段被误删
```

而不是修改 `prim_EV1` 测量模块本身。

---

# 17. 永久规则十六：结构整理与功能改模必须分开

一次脚本不要同时做：

```text
算法修改
+
删模块
+
长线改Goto
+
布局
+
悬空线清理
+
物理线整理
```

否则一旦 Build 或动态行为改变，无法建立因果关系。

推荐拆分：

```text
A. 只读审计
B. 功能补丁
C. 独立验证
D. 结构清理
E. 布局
F. 物理网络操作（若确有必要）
```

其中物理网络应被视为最高风险层之一。

---

# 18. 永久规则十七：大模型自动整理时，物理网络默认“不可触碰”

以后 Cleanup / Layout 脚本的默认规则：

```text
if portType ∈ {
    LConn,
    RConn,
    PMIO,
    Simscape conserving
}
    → PROTECTED
```

只有用户明确提出：

```text
“本轮就是修改这个已验证物理节点”
```

且存在：

```text
精确基线
+
端口合同
+
Scratch
+
回滚
```

时才允许自动修改。

---

# 19. 本轮脚本失败链带来的具体经验

## R1：错误的文件存在性假设

问题：

```text
get_param(Model,'FileName') / exist()==2
```

在 RT-LAB 模型打开方式下不可靠。

结论：

```text
路径解析必须多级
文件检查用 isfile
```

---

## R2：`containers.Map` 键类型假设

问题：

```text
char / string key 类型在运行环境中不一致
```

导致：

```text
adj(u)
key type mismatch
```

结论：

> 对本来规模很小、结构固定的图，不要为了“通用化”引入比问题本身更复杂的数据结构。

若节点只有几项：

```text
cell
struct
logical adjacency matrix
```

通常更透明、更安全、更容易审计。

---

## R3：过早假设“只有6个中性点坏”

R3 的价值不是失败，而是通过全 SM 物理端口差分发现：

```text
还有39项非中性物理端口差异
```

结论：

> 已知一个 Build 报错位置，不代表损坏范围只在那里。

正确步骤：

```text
局部报错
↓
全局只读差分
↓
确定完整损坏边界
↓
一次修复
```

---

## R4：磁盘文件身份与内存同名对象混淆 + 显示名称写死

问题：

```text
23fc磁盘SHA正确
≠
已经加载的 K26_K50 一定来自该文件
```

同时：

```text
J1_Load2
```

逐字符名称匹配无法容忍历史换行/空白差异。

结论：

```text
精确源文件先SHA
↓
关闭同名clean内存对象
↓
重新加载精确文件
↓
名称只作为canonical定位手段
```

---

## R5：最终脚本架构

R5 最重要的不是“更多判断”，而是把合同变成：

```text
精确23fc磁盘源
↓
精确新加载源模型
↓
源/目标独立canonical解析
↓
15节点允许修改集合
↓
全SM物理差分必须全部落入该集合
↓
Scratch
↓
全SM物理拓扑必须等于23fc
↓
正式模型
↓
保存重载
↓
再次全SM物理拓扑等于23fc
```

这是后续类似恢复任务优先复用的设计。

---

# 20. 后续写脚本前的强制检查清单

每次正式写脚本前先回答：

- [ ] 我正在回答的科学/工程问题是什么？
- [ ] 当前唯一工作文件是什么？
- [ ] 是否有 SHA256？
- [ ] 已加载模型对象和磁盘文件是否分别核对？
- [ ] 哪些对象允许改？
- [ ] 哪些对象绝对禁止改？
- [ ] 端口类型是否区分普通信号与物理端口？
- [ ] 是否存在 SPS / Simscape physical branch？
- [ ] 是否错误使用了 Src/Dst 逻辑解释物理 branch？
- [ ] 是否有 ambiguous / unknown 被当成 empty？
- [ ] 是否先建立 preflight？
- [ ] 是否有完整字节备份？
- [ ] 是否能先在 Scratch 完整执行？
- [ ] 修改后验证的是“新合同”还是旧合同？
- [ ] 是否验证非目标代码/参数/连接不变？
- [ ] 是否保存一次后重新加载验证？
- [ ] 是否准备整文件 rollback？
- [ ] 是否明确区分 static PASS 与 Build PASS？
- [ ] Build 失败时能否从第一差异反追，而不是加广泛 workaround？

只要其中任何关键项回答不了：

```text
先不写破坏性脚本
```

---

# 21. 本项目后续 Cleanup 的永久禁令

今后针对 `K26_K50` / `K26_K50_CLEAN_P1` 或其后继模型：

## 禁止

```text
SM_Master 全域 generic dangling-line deletion
SPS branch 使用 no-src/no-dst 判废
LConn/RConn 自动清线
LineParent/LineChildren 推断电气节点
未经基线的自动物理重连
同时进行算法修改 + Cleanup + Layout
```

## 允许

普通控制信号整理必须满足：

```text
标准Outport → 标准Inport
明确source
明确全部consumer
不跨RT-LAB task
不涉及物理端口
独立pre/post connectivity检查
```

物理修改必须满足：

```text
明确电气节点
精确真值模型
端口级合同
完整allow-list
Scratch
整文件backup
persistent postassert
```

---

# 22. 推荐复用的标准脚本架构

```text
01_IDENTITY
    文件路径
    SHA256
    loaded-model identity

02_PRECONDITION
    stopped
    Dirty合同
    必需变量/库/模型对象

03_DISCOVERY
    connectivity first
    canonical name second
    unknown显式化

04_PREFLIGHT
    当前结构必须匹配预期旧合同

05_ALLOWLIST
    冻结唯一允许变化集合

06_BACKUP
    byte-identical complete file

07_SCRATCH
    修改
    postassert
    save
    close/reload
    postassert again

08_FORMAL_REPREFLIGHT
    正式文件必须仍与修改前一致

09_FORMAL_EDIT
    只执行allow-list动作

10_POSTASSERT
    新合同
    非目标不变
    参数不变
    connectivity不变/按预期变化

11_SAVE_ONCE

12_PERSISTENT_VERIFY
    close
    reload
    repeat postassert

13_REPORT
    before SHA
    after SHA
    exact changed objects
    skipped / unknown
    rollback location
    next allowed action
```

---

# 23. 最终浓缩

以后处理大型实时仿真模型，优先记住下面八句话：

```text
1. 磁盘文件身份 ≠ 已加载模型身份。
2. Connectivity first，Name second。
3. 普通信号线 ≠ SPS物理线。
4. 物理拓扑按电气节点理解，不按Line对象理解。
5. unknown 不能自动等于 empty。
6. 先封闭修改范围，再写修改代码。
7. Scratch先成功，正式模型才允许修改。
8. static PASS 后还必须 Build；Build 是下一层验证，不是重复审计。
```

这八条应作为后续所有模型自动化脚本的默认开发规范。
