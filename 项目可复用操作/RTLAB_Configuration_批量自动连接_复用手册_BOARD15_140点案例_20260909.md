# RT-LAB Configuration 批量自动连接复用手册
## ——以 BOARD15 新增 140 点自动连接为正式案例

> 项目：暑期南网科技项目 / K26_V5 / BOARD15  
> 平台：RT-LAB v2024.1.1.38  
> MATLAB：R2023b  
> 案例结果：BOARD15 新增 140 个 Modbus Holding Register（保持寄存器）与模型 OpInput / OpOutput（输入/输出接口）已通过 Python + RtlabApi 自动精确连接成功。  
> 本文目标：把这次经验冻结成可复用方法，避免以后再次手工连接上百个点或反复试错。

---

# 1. 这次到底自动化了什么

本轮自动连接对象是 BOARD15 新增的 140 个点：

| 区域 | 数量 | 方向 |
|---|---:|---|
| 40013～40064 | 52 | Board → RT-LAB / Model |
| 40117～40124 | 8 | Model → RT-LAB / Board |
| 40201～40280 | 80 | Model → RT-LAB / Board |
| **合计** | **140** | — |

自动连接解决的是 RT-LAB：

```text
Configuration
模型 OpInput / OpOutput
        ↕
I/O Interfaces → Modbus Slave → Holding Registers
```

这一层的 **一一映射**。

它不负责：

- 创建 Simulink 模型接口；
- 创建 Modbus Holding Registers；
- 修改 RT-LAB I/O Interface 的寄存器地址；
- 修改 Board 程序；
- 修改控制算法；
- Build / Load / Execute。

因此完整流程仍然是：

```text
模型先有 OpInput / OpOutput
        ↓
I/O Interfaces 先建立 Holding Registers
        ↓
Configuration 批量自动连接
        ↓
检查连接
        ↓
Build
```

---

# 2. 为什么这 140 点适合自动连接

这批新接口是在同一轮 BOARD15 Patch 中统一创建的，因此有一个非常重要的工程特征：

> **模型 Alias（别名）和 I/O Holding Register Name（保持寄存器名称）按同一套最终点表命名。**

例如：

```text
模型 Alias：
Op40013_PV1_QREF_raw

I/O 点名：
Op40013_PV1_QREF_raw
```

以及：

```text
模型 Alias：
Op40280_CONTROLLER_RESET_SEQ_raw

I/O 点名：
Op40280_CONTROLLER_RESET_SEQ_raw
```

所以可以实现：

```text
exact model alias
        ↕
exact I/O datapoint
```

这是自动精确连接成立的核心前提。

---

# 3. 什么时候适合使用自动连接脚本

## 3.1 推荐使用的情况

满足以下条件时，非常适合用 Python + RtlabApi：

- 一次新增几十到几百个 I/O 点；
- 模型接口已经存在；
- I/O Interfaces 点表已经存在；
- 两边有稳定、唯一、可预测的命名规则；
- 模型端点可以被 RT-LAB API 通过 Alias 或真实 signal path（信号路径）识别；
- 希望保留连接前后 CSV 证据；
- 不希望人工拖 100+ 条线；
- 后续还可能重复搭建相同工程。

典型适用对象：

```text
大批量 Modbus
大批量 CAN / EtherCAT / UDP / TCP I/O
大量 OpInput / OpOutput 映射
标准化测试平台
多项目复用的固定I/O框架
```

---

## 3.2 不建议直接自动连接的情况

以下情况不要为了“自动化”强行脚本连接：

- 模型侧没有唯一 Alias；
- API 无法稳定枚举真实 signal path；
- 同名信号很多；
- 旧模型接口是不同年代/不同方法创建的；
- 一个 I/O 点对应多个候选模型信号；
- 接口名称已经与点表名称脱节；
- 只能靠“猜这个块可能就是那个信号”完成匹配。

本项目中的旧 28 点就是典型反例：

```text
40001～40012
40101～40116
```

它们来自早期 V3.2 / V4 通信架构。

虽然 GUI 中接口存在，但部分旧接口：

```text
EXT_AGC_ENABLE_raw
CMD_SEQ_raw
Op40101～Op40114
MODEL_STATUS_raw
RTLAB_HEARTBEAT_raw
```

在当前 RT-LAB API 的 Alias / signal-path 暴露方式与新 140 点不同。

因此最终原则是：

> **新140点自动连接；旧28点手动连接。**

不要为了省 28 次操作继续扩大风险。

---

# 4. 正确自动连接流程

## Step 1：先完成模型侧接口

例如本次：

```text
40013～40064 → OpInput
40117～40124 → OpOutput
40201～40280 → OpOutput
```

模型侧接口名称必须冻结。

不能模型还在改名时就开始 Configuration 自动连接。

---

## Step 2：配置 I/O Interfaces 点表

在：

```text
I/O Interfaces
→ Modbus Slave
→ Holding Registers
```

先把：

```text
Name
Address
Initial value
Control from
Register type
```

全部配置正确。

BOARD15 最终：

```text
40001～40064
40101～40124
40201～40280
```

共 168 点。

---

## Step 3：不要依赖 GUI Auto-connections

RT-LAB GUI 有：

```text
Perform Auto-connections
```

但项目验收不建议依赖它做 100+ 点批量连接。

原因：

- 它属于自动匹配；
- 匹配规则对用户不够透明；
- 出现错位时不容易审计；
- 本项目必须防止“连错但看起来有值”的假 PASS。

更推荐：

```python
RtlabApi.CreateConnection()
```

显式提供：

```text
model_point[i]
↔
io_point[i]
```

---

# 5. 成功脚本的核心设计

最终成功版本：

```text
BOARD15_RTLAB_AUTO_CONNECT_R3.py
```

其核心不是“一行 CreateConnection”，而是以下完整安全链。

---

## 5.1 自动找到真实 Modbus I/O Interface

先：

```python
RtlabApi.GetIOInterfaces()
```

然后选择：

```text
Modbus Slave
```

不得直接假定接口数组第几个就是目标。

---

## 5.2 枚举真实 I/O datapoints

调用：

```python
RtlabApi.GetConnectionPointsForIO(io_name)
```

拿回 Modbus Slave 下真实可连接 datapoint。

---

# 6. R1 → R3 的关键经验

这部分是以后最值得复用的经验。

---

## 6.1 R1 失败：不要假设 API 返回的是 tuple

最初错误：

```python
list(item)
```

默认把：

```text
GetIOInterfaces()
```

的每个结果当 tuple。

但 RT-LAB 2024.1 实际返回的是 dict（字典）。

于是：

```text
name='name'
type='type'
subsystem='subsystem'
```

读到的是字典 key，不是 value。

### 经验

写 RT-LAB Python API 脚本时：

> **不要仅根据官方字段说明猜 Python wrapper 的实际返回类型。**

必须兼容：

```text
dict
tuple/list
object attribute
```

---

## 6.2 R2 失败：字段存在不等于字段有值

第二次遇到：

```text
uiName
name
alias
path
```

等多个字段。

RT-LAB datapoint 可能类似：

```python
{
    "uiName": "",
    "name": "Op40274_EV2_EXPECT_TAU_MS_raw"
}
```

如果脚本逻辑是：

```text
只要uiName键存在
→ 就返回uiName
```

就会得到空字符串，导致明明 GUI 有点，脚本却报告 missing。

### 经验

字段选择必须使用：

```text
第一个“非空”有效字段
```

而不是：

```text
第一个“存在”的字段
```

---

## 6.3 R3 成功：不要信任单一字段

R3 最终采用多层匹配：

### 第一层：完整名称精确匹配

```text
Op40274_EV2_EXPECT_TAU_MS_raw
```

如果存在于任一有效字段，优先采用。

---

### 第二层：规范化完整名称匹配

仅处理：

```text
大小写
路径分隔符
空格
```

等格式差异。

仍要求完整语义名称一致。

---

### 第三层：寄存器号唯一匹配

例如：

```text
Op40274_EV2_EXPECT_TAU_MS_raw
```

提取：

```text
40274
```

仅当整个 Modbus datapoint 集合中：

```text
40274
```

只能唯一对应一个点时，才允许作为 fallback（回退匹配）。

### 原则

> fallback 只能用于唯一确认，不能用于“最像”。

---

# 7. 自动连接前必须满足的硬前提

连接前必须完成 preflight（预检查）：

```text
targets       = 140
matched       = 140
missing       = 0
duplicates    = 0
```

只要出现：

```text
missing > 0
```

或者：

```text
duplicates > 0
```

则：

> **一条连接都不能创建。**

这条必须永久保留。

---

# 8. 为什么一定要在写入前备份 Connection

在任何：

```python
CreateConnection()
```

前先执行：

```python
RtlabApi.ExportConnections(...)
```

导出：

```text
BOARD15_connections_PRE_xxx.csv
```

这样如果后面：

```text
CreateConnection failed
POST verification failed
```

可以执行：

```python
RtlabApi.ImportConnections(...)
```

恢复 PRE 状态。

本项目已经实际验证：

```text
[ROLLBACK PASS]
```

这套回滚机制有效。

---

# 9. 脚本必须支持 partial run

工程现场很容易出现：

```text
已经手工连了10条
脚本又要连140条
```

如果脚本不检查现状，可能造成重复连接或错误。

因此成功方案会先读取：

```text
PRE connections CSV
```

判断：

```text
already present
to create
```

只补缺失项。

即：

```text
目标总数 = 140
已有 = N
真正创建 = 140-N
```

### 原则

> 批量连接脚本必须幂等或接近幂等，不能假设每次都是“零连接干净工程”。

---

# 10. CreateConnection 以后不能立即宣布 PASS

这是本项目一贯防“假PASS”的原则。

不能：

```text
API没有抛异常
→ PASS
```

必须：

```text
CreateConnection
↓
ExportConnections POST
↓
检查140个目标Alias全部存在
↓
POST missing = 0
↓
PASS
```

最终保存：

```text
BOARD15_connections_POST_xxx.csv
```

作为正式证据。

---

# 11. 自动连接成功后还需要人工抽查

即使：

```text
140 / 140
```

脚本全部通过，仍建议 GUI 抽查首、中、尾和双方向点。

本项目建议至少检查：

```text
Op40013_PV1_QREF_raw
Op40117_PCC_PHASE_raw
Op40201_CONFIG_SEQ_ECHO_raw
Op40280_CONTROLLER_RESET_SEQ_raw
```

检查：

```text
I/O point
↓
展开
↓
显示正确 From master / From model
↓
Configuration Connections栏有正确对应模型接口
```

### 为什么仍需人工抽查

自动验证解决：

```text
完整性
唯一性
API层连接
```

人工 GUI 抽查解决：

```text
最终显示是否符合人的预期
```

两者互补。

---

# 12. 这次为什么旧28点最终选择手动

R3成功证明：

> RT-LAB API 批量连接本身没有问题。

但旧28点的问题不是“CreateConnection不能用”，而是：

> 旧接口模型侧可寻址名称不统一。

例如 API 已能看到：

```text
K26.../SM_Master/Modbus_4001_raw/OpInput/port1
```

但部分旧接口：

```text
EXT_AGC_ENABLE_raw
CMD_SEQ_raw
Op40101～Op40114
MODEL_STATUS_raw
RTLAB_HEARTBEAT_raw
```

没有按我们预期的旧块名暴露成可唯一使用的 model alias。

继续自动化就需要：

```text
猜路径
猜内部信号
绕过OpInput/OpOutput块
```

这违反了本项目原则：

> connectivity truth（真实连线）优先，不能为了自动化牺牲确定性。

因此最终选择：

```text
140个新点：自动
28个旧点：手动
```

这是合理的工程折中，不是自动化失败。

---

# 13. 后续如何复用这套方法

以后出现一个新项目，例如：

```text
BOARD15_V2
新的CHIL测试平台
新的协议点表
另一个Modbus Slave
```

推荐步骤：

---

## 13.1 先统一命名

设计点表时直接保证：

```text
Model Alias
=
I/O datapoint Name
=
点表 Name
```

例如：

```text
Op40301_XXX_raw
```

三处完全一致。

这样以后自动连接成本最低。

---

## 13.2 模型新增接口时就打开 create_alias

新增 OpInput / OpOutput 时保证：

```text
create_alias = on
```

并冻结：

```text
identifier_hide
```

等 RT-LAB alias 名称。

---

## 13.3 I/O Interface 按同名创建

不要 I/O 里叫：

```text
PV1_QREF
```

模型里叫：

```text
Op40013_PV1_QREF_raw
```

然后指望 Auto-connect 猜。

直接统一为：

```text
Op40013_PV1_QREF_raw
```

更适合自动化。

---

## 13.4 自动连接脚本只维护目标列表

以后复用 R3 框架时，通常只需修改：

```python
PROJECT_HINT
IO_NAME_HINT
TARGET_NAMES
```

核心解析、preflight、backup、rollback、POST verify 逻辑全部保留。

---

# 14. 更进一步：完全相同项目怎样复用

如果模型和 I/O 命名完全不变，后续甚至不必重新运行 CreateConnection。

应长期保存：

```text
BOARD15_Modbus_IO.rios
BOARD15_connections_POST_xxx.csv
```

分别代表：

```text
.rios
→ I/O Interfaces配置

connections.csv
→ Configuration连接
```

后续新项目中：

```text
ImportIOsConfiguration
+
ImportConnections
```

可以直接恢复。

因此本次 BOARD15 连接工作完成后，应把最终：

```text
.rios
POST connections CSV
```

纳入正式验收资料和仓库。

---

# 15. 推荐保存的正式资产

本次最终至少保留：

```text
BOARD15_RTLAB_AUTO_CONNECT_R3.py
```

用途：

```text
以后重新生成/补连接140个新接口
```

同时保留：

```text
BOARD15_connections_PRE_R3_xxx.csv
BOARD15_connections_POST_R3_xxx.csv
```

用途：

```text
连接前后审计
恢复
复盘
```

再导出：

```text
BOARD15_Modbus_IO.rios
```

用途：

```text
I/O Interfaces整体复用
```

---

# 16. 本次形成的固定原则

## 原则1：能精确匹配，才自动连接

```text
exact
unique
auditable
```

三个条件缺一不可。

---

## 原则2：不要把 GUI Auto-connect 当正式验收依据

大批量接口优先：

```text
GetConnectionPointsForIO
+
CreateConnection
+
ExportConnections
```

形成可追踪过程。

---

## 原则3：任何写入前必须 preflight

```text
目标总数
=
唯一匹配总数
```

否则不写。

---

## 原则4：任何写入前必须备份

必须：

```text
ExportConnections PRE
```

---

## 原则5：任何成功后必须再次导出验证

必须：

```text
ExportConnections POST
```

不能把：

```text
CreateConnection未报错
```

等价成：

```text
全部连接正确
```

---

## 原则6：自动化不能凌驾于真实性

遇到：

```text
legacy接口
API无法唯一识别
模型真实路径不透明
```

宁可手动连接少量点。

---

## 原则7：新设计必须为未来自动化服务

以后设计接口时就考虑：

```text
统一名称
统一地址
唯一Alias
清晰方向
标准化点表
```

不要等到 Configuration 阶段再想怎么自动化。

---

# 17. BOARD15 本轮最终结论

截至本轮：

```text
I/O Interfaces：
168个Holding Registers已经配置完成

Configuration：
新增140点已经通过R3自动精确连接成功

剩余旧28点：
由于legacy模型接口API暴露不统一
决定人工同名连接
```

因此本轮真正成功验证的是：

> **RT-LAB 2024.1.1.38 下，可以使用 RtlabApi 完成大批量、可审计、带回滚的 Configuration 精确自动连接。**

适用于：

> **命名统一、Alias明确、I/O datapoint可唯一解析的新设计接口。**

而不是：

> **对所有历史接口无条件强行自动化。**

---

# 18. 一页执行清单

以后再次做大批量 RT-LAB Configuration 时，按下面执行：

```text
[ ] 模型接口已完成
[ ] OpInput/OpOutput名称已冻结
[ ] create_alias已启用
[ ] I/O点表已完成
[ ] Model Alias = I/O Name
[ ] 模型不在Execute/Paused
[ ] GetIOInterfaces找到唯一目标I/O
[ ] GetConnectionPointsForIO成功
[ ] target数正确
[ ] matched = target
[ ] missing = 0
[ ] duplicate = 0
[ ] ExportConnections PRE
[ ] partial-run检查
[ ] CreateConnection
[ ] ExportConnections POST
[ ] POST全部目标存在
[ ] GUI人工抽查首/中/尾
[ ] 保存POST CSV
[ ] 导出.rios
[ ] 再进入Build
```

---

# 19. 一句话记忆

> **RT-LAB批量连接不是“让软件猜着连”，而是先把模型Alias与I/O点名设计成同一个唯一ID，再让Python逐点证明“就是它”，全部证明完成后才批量CreateConnection；任何不确定的旧接口宁可手动。**
