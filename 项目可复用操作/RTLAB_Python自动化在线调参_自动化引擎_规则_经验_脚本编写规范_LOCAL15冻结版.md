# RT-LAB Python 自动化在线调参｜自动化引擎、规则、经验与脚本编写规范
## —— K26_V5 / LOCAL15 阶段冻结版（暂不包含 S1～S15 Case 定义）

> **冻结日期**：2026-08-17  
> **适用平台**：RT-LAB 2024.1.1.38、MATLAB R2023b、OP5700  
> **当前模型基线**：K26_V5 / LOCAL15（本地15策略闭环）  
> **本文件目的**：冻结本阶段已经实际验证成功的 RT-LAB Python 自动化方法、脚本架构、控制权处理、在线调参方式、仿真时间调度方法、MAT 记录边界、常见错误和后续复用规则。  
>
> **本文件明确不做的事情**：
>
> - 暂不定义 S1～S15 各策略自动测试 Case（工况）；
> - 暂不编写15份策略专用 Python 脚本；
> - 暂不适配未来 BOARD15（板端15策略）的最终寄存器接口；
> - 暂不把论文 Baseline / Proposed（基线 / 改进方法）自动实验写死进当前 LOCAL15 脚本。
>
> 当前只冻结：
>
> ```text
> 自动化引擎
> +
> 脚本设计规则
> +
> 安全规范
> +
> 已验证API使用方法
> +
> MAT记录经验
> +
> 后续脚本编写模板
> ```

---

# 1. 本阶段已经验证到什么程度

当前已经实际验证完成两级自动化能力。

---

## 1.1 P0：模型 Execute 状态下 Python 自动在线改参 —— PASS

已验证链路：

```text
RT-LAB模型正在Execute
↓
Host Python（上位机Python）
↓
RtlabApi.SetParametersByName()
↓
在线修改Tunable Parameter（运行时可调参数）
↓
Target（目标机）实时采用
↓
Group28 MAT真实记录
```

实际验证参数：

```text
CFG15_ISLAND_MASTER
（孤岛构网主机选择）
```

自动变化：

```text
1
→
2
→
1
```

MAT 中真实记录到了对应变化。

因此已经证明：

> **Python不是只修改了上位机显示值，而是正在运行的OP5700实时模型真正采用了新参数。**

---

## 1.2 P1：按照RT-LAB仿真时间自动执行多阶段参数修改 —— PASS

最终成功方式不是：

```text
Windows time.sleep()
```

作为工况计时标准。

也不是：

```text
不停调用GetAcqGroupSyncSignals读取Target Time
```

而是使用：

```text
RtlabApi.SetPauseTime()
```

让RT-LAB按照自身 Simulation Time（仿真时间）自动Pause（暂停）。

已验证流程：

```text
0 s：
CFG15_ISLAND_MASTER = 1

↓ 自动Execute

3.000 s：
RT-LAB自动Pause
Python自动：
1 → 2

↓ 自动继续Execute

6.000 s：
RT-LAB自动Pause
Python自动：
2 → 1

↓ 自动继续Execute

12 s：
自动Pause / Reset
```

实际MAT记录：

```text
0.00～2.99 s：
1

3.00 s：
1 → 2

3.00～5.99 s：
2

6.00 s：
2 → 1

6.00 s以后：
1
```

因此可以正式冻结：

> **“按RT-LAB仿真时间精确触发在线调参”的自动化核心能力已经验证成功。**

---

# 2. 自动化系统的正确定位

当前自动化系统的目标不是：

```text
替代RT-LAB
```

而是：

```text
把人工操作流程
固化成
可重复、可定时、可审计的自动实验过程
```

人工方式：

```text
Load
↓
Execute
↓
盯着Target Time
↓
手工修改Variables Table
↓
再等待
↓
再修改
↓
Reset
```

自动方式：

```text
手动Load
↓
Run Python Script
↓
Python取得控制权
↓
自动Execute
↓
按仿真时间自动Pause
↓
自动改参数
↓
自动继续
↓
自动Reset
↓
自动释放控制权
```

---

# 3. 当前推荐保留一个“人工安全边界”

当前冻结流程建议继续保持：

```text
人工：
Load

自动：
Execute
↓
定时改参
↓
Reset
```

也就是说：

```text
每一轮实验开始前
由人确认模型、工况和安全状态
然后点击一次Load
```

之后：

```text
Python接管实验流程
```

暂时不追求：

```text
Python自动Build
Python自动Load
```

原因：

```text
当前真正有价值的是自动工况执行
不是自动化一切按钮
```

保留人工Load反而形成清晰的安全确认点。

---

# 4. Host Python 和 Target Python 必须区分

当前自动化脚本运行位置是：

```text
Windows Host（上位机）
```

使用：

```text
RtlabApi
```

控制：

```text
RT-LAB Project
Model
Parameters
Execute
Pause
Reset
```

不要使用 OP5700 页面中的：

```text
Execute a Python script on this target
```

那个入口属于：

```text
Target-side Python
（目标机侧Python）
```

与当前：

```text
Host-side RT-LAB automation
（上位机RT-LAB自动控制）
```

不是一回事。

---

# 5. 正式Python脚本应当作为RT-LAB Project资源保存

推荐工程目录：

```text
yanshou_V5/
│
├─ Models/
├─ data/
└─ scripts/
   └─ *.py
```

当前验证成功的参考脚本位于：

```text
yanshou_V5/scripts/
```

正式自动化脚本不要长期作为：

```text
工作区外部临时文件
```

使用。

---

# 6. Interactive Python Console 的正确用途

Interactive Python Console（交互式Python控制台）适合：

```text
import RtlabApi

GetActiveProjects()

GetCurrentModel()

GetModelState()

GetParametersDescription()

GetParametersByName()

SetParametersByName()
```

这种：

```text
单行
短命令
API探索
```

不适合：

```text
几十行while循环
try/finally
复杂状态机
长自动实验脚本
```

本阶段已经实际踩过：

```text
交互Console中途Interrupt
↓
后续缩进行被当作顶层命令
↓
大量IndentationError
```

因此冻结规则：

> **Console只用于调API；正式自动工况必须写成完整 `.py` 文件一次运行。**

---

# 7. 脚本第一条规则：永远先连接“当前真实工程”

不要硬编码：

```text
Model ID
Parameter ID
```

当前工程通过：

```python
RtlabApi.GetActiveProjects()
```

发现。

当前已验证工程：

```text
yanshou_V5
```

模型：

```text
K26_V5.slx
```

推荐脚本根据：

```text
Project path关键词
Model name关键词
```

自动确认当前连接目标。

---

# 8. Parameter ID 不应该写死

曾经得到：

```text
CFG15_PARAM_PROBE
Parameter ID = 1124
```

但是：

```text
重新Build
改变模型结构
新增参数
```

以后：

```text
Parameter ID可能变化
```

因此正式脚本不用：

```python
SetParameters(((1124, 5.0),))
```

而统一使用：

```python
SetParametersByName(...)
```

---

# 9. 当前正式推荐的在线调参API

## 9.1 参数发现

```python
params = RtlabApi.GetParametersDescription()
```

每条记录可以用来得到：

```text
参数ID
Block路径
参数属性
变量名
当前值
```

---

## 9.2 按名称读取

```python
RtlabApi.GetParametersByName(
    (parameter_name,)
)
```

---

## 9.3 按名称修改

```python
RtlabApi.SetParametersByName(
    (parameter_name,),
    (new_value,)
)
```

这是当前冻结的正式写法。

不要继续使用已经提示 deprecated（弃用）的：

```python
SetParameters()
```

---

# 10. 参数路径必须每次从当前Build中自动发现

推荐函数：

```python
def find_value_parameter(key):
    params = RtlabApi.GetParametersDescription()

    hits = [
        p for p in params
        if key in str(p[1])
        and str(p[2]) == "Value"
    ]

    if len(hits) != 1:
        raise RuntimeError(...)

    return hits[0][1] + "/" + hits[0][2]
```

重要思想：

```text
不是：
“我记得路径应该是这个”

而是：
“当前Target告诉我真实参数路径是什么”
```

---

# 11. 每个参数必须“唯一发现”

如果：

```text
hits = 0
```

说明：

```text
没有找到
```

如果：

```text
hits > 1
```

说明：

```text
存在歧义
```

两种情况都应该：

```text
STOP
```

而不是：

```text
默认取第一个
```

正式自动测试禁止猜参数。

---

# 12. 模型状态不能通过字符串模糊比较

本阶段实际踩坑：

RT-LAB返回：

```text
MODEL_PAUSED(7)
```

如果：

```python
str(state) == "MODEL_PAUSED"
```

会得到：

```text
False
```

正确方式：

```python
state == RtlabApi.MODEL_PAUSED
```

同理：

```python
state == RtlabApi.MODEL_RUNNING

state == RtlabApi.MODEL_LOADABLE

state == RtlabApi.MODEL_LOADED
```

冻结规则：

> **OP_MODEL_STATE（模型状态）必须比较枚举，不比较字符串。**

字符串仅用于：

```text
打印
日志
```

---

# 13. 当前自动脚本的启动状态必须明确

当前LOCAL15自动Case推荐：

```text
启动脚本前：
MODEL_PAUSED
```

也就是：

```text
用户已经Load
但没有Execute
```

脚本启动第一件事：

```python
if get_model_state() != RtlabApi.MODEL_PAUSED:
    raise RuntimeError(...)
```

如果当前是：

```text
MODEL_LOADABLE
```

说明：

```text
还没Load
或上一轮已经Reset
```

应该停止。

不要让脚本自动猜：

```text
是不是应该先Load
```

---

# 14. System Control 和 Parameter Control 必须理解

RT-LAB有不同类型的功能控制权。

---

## 14.1 System Control（系统控制权）

用于：

```text
Execute
Reset
系统状态操作
```

---

## 14.2 Parameter Control（参数控制权）

用于：

```text
在线修改参数
```

---

## 14.3 为什么会冲突

曾经出现：

```text
Parameter Control already been given
priority = 127
```

原因：

```text
GUI / 旧Python Console
仍占有普通优先级参数控制权
```

而新脚本再次请求时：

```text
被拒绝
```

---

# 15. 正式自动脚本推荐使用Macro Priority（宏脚本优先级）

最终成功采用：

```python
RtlabApi.TakeFunctionControl(
    RtlabApi.OP_FB_SYSTEM,
    0,
    RtlabApi.OP_CTRL_PRIO_MACRO
)
```

以及：

```python
RtlabApi.TakeFunctionControl(
    RtlabApi.OP_FB_PARAMETER,
    0,
    RtlabApi.OP_CTRL_PRIO_MACRO
)
```

当前理解：

```text
GUI普通控制优先级：
127

Macro Script：
192
```

这样自动化脚本可以明确取得控制权。

冻结规则：

> **正式自动化脚本使用 TakeFunctionControl + Macro Priority，不依赖普通 GetParameterControl(True)。**

---

# 16. 脚本结束必须主动释放控制权

对应：

```python
RtlabApi.ReleaseFunctionControl(
    RtlabApi.OP_FB_PARAMETER,
    0
)
```

以及：

```python
RtlabApi.ReleaseFunctionControl(
    RtlabApi.OP_FB_SYSTEM,
    0
)
```

否则可能发生：

```text
脚本结束
但GUI仍无法Reset / 改参数
```

---

# 17. 所有正式脚本必须有 `try / finally`

自动化脚本模板：

```python
try:

    # 连接工程
    # 检查模型
    # 取得控制权
    # 自动测试

finally:

    # 必要时Reset
    # 释放Parameter Control
    # 释放System Control
```

这是必须项。

原因：

```text
自动化不是只考虑成功路径
还必须考虑：
中途报错
用户Interrupt
API异常
```

---

# 18. Reset不能无条件调用两次

曾出现：

```text
第一次Reset：
成功

第二次Reset：
error 22
model is not loaded
```

这不是系统故障。

只是：

```text
模型已经Reset
```

所以正式脚本的清理逻辑应该先检查状态：

```python
if state in (
    RtlabApi.MODEL_RUNNING,
    RtlabApi.MODEL_PAUSED,
    RtlabApi.MODEL_LOADED,
):
    RtlabApi.Reset()
```

不要：

```python
finally:
    RtlabApi.Reset()
```

无条件Reset。

---

# 19. 当前不推荐使用 acquisition API 做自动定时核心

曾尝试：

```python
GetAcqGroupSyncSignals(...)
```

希望读取：

```text
simulationTime
```

但当前 RT-LAB 2024.1 环境出现：

```text
函数调用阻塞
```

最终需要：

```text
Interrupt / KeyboardInterrupt
```

另外：

```python
GetNumAcqGroup()
```

在当前实际 `RtlabApi` 中：

```text
不存在
```

虽然其它版本/API资料可能出现相关函数，但冻结规则必须以：

```text
当前实际环境
```

为准。

因此：

> **当前LOCAL15自动工况不使用 acquisition API 轮询仿真时间。**

---

# 20. 当前正式推荐的仿真时间调度机制：SetPauseTime

最终成功方法：

```python
RtlabApi.SetPauseTime(3.0)
RtlabApi.Execute(1.0)
```

RT-LAB：

```text
从当前状态继续仿真
```

到：

```text
Simulation Time = 3.0 s
```

自动：

```text
MODEL_PAUSED
```

然后脚本在线改参。

再：

```python
SetPauseTime(6.0)
Execute(1.0)
```

继续运行。

---

# 21. SetPauseTime的本质

不是：

```text
Host等待3秒
```

而是：

```text
RT-LAB自己的仿真时间达到3秒
```

所以：

```text
实验事件时刻
```

由：

```text
Simulation Time
```

定义，而不是：

```text
Windows时间
```

这对实验可重复性非常重要。

---

# 22. 当前LOCAL15自动工况推荐结构

```text
Load
↓
Python Run

SetPauseTime(t1)
↓
Execute
↓
RT-LAB到t1自动Pause
↓
Event 1：改参数

SetPauseTime(t2)
↓
Execute
↓
到t2自动Pause
↓
Event 2

...

SetPauseTime(t_end)
↓
Execute
↓
Pause
↓
Reset
```

---

# 23. Pause方式适合什么阶段

适合：

```text
LOCAL15
纯RT-LAB模型内部验证
参数逻辑验收
自动回归
```

因为：

```text
模型Pause
不会有外部真实控制器继续跑墙钟时间
```

---

# 24. Pause方式不适合未来哪些实验

未来：

```text
BOARD15
真实Modbus闭环
CHIL
```

不能默认使用：

```text
Pause
→ 改参
→ Resume
```

原因：

```text
外部板继续按真实墙钟运行
```

RT-LAB暂停以后：

```text
可能被控制板识别成：
通信停顿
心跳异常
```

所以未来 BOARD15 / CHIL 自动工况需要：

```text
不中断实时执行的事件调度
```

当前Pause引擎只是：

> **LOCAL15阶段自动测试引擎。**

这个边界必须长期保留。

---

# 25. MAT文件大小为什么会出现39 B

这是本阶段非常重要的记录经验。

当前：

```text
AA15_OpWriteFile_Group28
```

记录配置：

```text
Decimation = 100

Nb_Samples = 1000
```

模型基本步长：

```text
100 μs
```

因此日志采样周期：

```text
100 μs × 100
=
10 ms
```

也就是：

```text
100 Hz
```

---

# 26. 一个完整buffer需要多长时间

```text
1000 samples
÷
100 samples/s
=
10 s
```

所以如果自动脚本：

```text
只运行8 s
```

然后：

```text
Reset
```

此时：

```text
尚未形成完整1000点buffer
```

可能得到：

```text
MAT只有变量头
```

约：

```text
39 B
```

---

# 27. 因此当前Group28自动实验必须保证至少超过10 s

冻结规则：

> **如果继续使用当前 Group28 / OpWriteFile 配置，自动实验结束时间必须大于10 s。**

推荐：

```text
最后事件发生后
至少继续运行到12 s以上
```

例如：

```text
3 s：
Event 1

6 s：
Event 2

12 s：
Reset
```

至少可得到：

```text
第一个1000样本buffer
=
0～9.99 s
```

---

# 28. 为什么12 s MAT最后只有0～9.99 s

因为当前：

```text
1000 sample buffer
```

是分块写出的。

12 s结束：

```text
前1000点
完整
→ 写出

10～12 s剩余约200点
不足一个完整buffer
→ 当前配置下不一定写出
```

所以看到：

```text
MAT Target Time：
0～9.99 s
```

是符合当前缓存机制的。

---

# 29. 后续设计自动实验时间必须考虑日志buffer边界

不要只设计：

```text
控制事件什么时候发生
```

还要设计：

```text
日志什么时候能够完整落盘
```

例如希望记录：

```text
0～20 s
```

更稳妥可以设计：

```text
Reset > 20 s
```

且最好：

```text
跨完整10 s buffer边界
```

---

# 30. 当前验证成功的安全测试参数选择原则

自动化基础验证使用：

```text
CFG15_ISLAND_MASTER
```

原因：

```text
它本身进入Group28
```

并且只要：

```text
CFG15_MASTER_ENABLE = 0
CFG15_MODE_ACTUATION_ENABLE = 0
CFG15_PCC_BREAKER_ACTUATION_ENABLE = 0
```

那么：

```text
1 → 2
```

只改变：

```text
“未来如果孤岛，选ESS1还是ESS2”
```

不会真正改变Plant。

---

# 31. 所以正式自动脚本必须先做Safety Preflight（安全预检查）

当前P1至少检查：

```text
MASTER_ENABLE = 0

MODE_ACT = 0

BREAKER_ACT = 0
```

如果不满足：

```text
立即STOP
```

而不是：

```text
继续自动改ISLAND_MASTER
```

后续所有真实策略自动脚本也应该有：

```text
自己的Safety Preflight
```

---

# 32. 自动化脚本的正确成功标准

以后不要只看：

```text
Python Console显示成功
```

完整PASS需要至少三层。

---

## Level 1：Python执行成功

例如：

```text
EVENT 1：
1 → 2

EVENT 2：
2 → 1

RESET COMPLETE
```

---

## Level 2：模型状态链正确

```text
MODEL_PAUSED
↓
MODEL_RUNNING
↓
MODEL_PAUSED
...
↓
MODEL_LOADABLE
```

---

## Level 3：MAT真实证据

例如：

```text
MAT第290行：

3.00 s
1 → 2

6.00 s
2 → 1
```

只有三层一致：

```text
才叫自动化PASS
```

---

# 33. 自动测试脚本必须打印哪些内容

推荐最少打印：

```text
脚本版本

当前Project

当前Model

初始Model State

控制权申请结果

实际参数路径

安全预检查值

Timeline

每一次Run/Pause

每一次事件执行前值

每一次事件执行后值

Reset结果

最终Model State

控制权释放结果
```

这样即使MAT异常，也可以定位脚本执行到了哪里。

---

# 34. 自动化脚本头部必须写清楚Prerequisites（前置条件）

例如：

```text
1.
K26_V5已经Load

2.
当前MODEL_PAUSED

3.
不要手动Execute

4.
脚本运行期间不要手工改Variables Table

5.
MASTER_ENABLE等安全参数必须为指定值
```

不要假设运行脚本的人知道隐含条件。

---

# 35. 脚本必须显式写“本脚本会修改什么”

例如：

```text
本脚本只修改：
CFG15_ISLAND_MASTER

本脚本不修改：
MASTER_ENABLE
MODE_ACT
BREAKER_ACT
Pref
Qref
Breaker
```

这和自动改模脚本一样，是安全工程要求。

---

# 36. 正式脚本的推荐基础结构

```python
import time
import RtlabApi

# Constants
PROJECT_KEY = ...
MODEL_KEY = ...

# Helper functions
connect_project()
find_value_parameter()
read_param()
write_param()
get_model_state()
take_control()
release_control()
run_to_pause_time()

try:

    # 1. Connect
    # 2. State check
    # 3. Take control
    # 4. Parameter discovery
    # 5. Safety preflight
    # 6. Initial values
    # 7. Execute timeline
    # 8. Reset
    # 9. Report PASS

finally:

    # fail-safe Reset if needed
    # release parameter control
    # release system control
```

---

# 37. 以后不要在脚本里写Parameter ID

错误：

```python
probe_id = 1124
```

正确：

```python
find_value_parameter(
    "CFG15_ISLAND_MASTER"
)
```

理由：

```text
脚本应该适配模型重新Build后的参数编号变化
```

---

# 38. 以后不要把项目完整路径写死

不推荐：

```python
"D:\\Users\\linjj\\...\\yanshou_V5\\..."
```

更合理：

```text
通过GetActiveProjects()
寻找工程关键词
```

只固定：

```text
PROJECT_KEY = "yanshou_V5"
MODEL_KEY = "K26_V5"
```

未来模型另存以后：

```text
只改关键词
```

即可。

---

# 39. 自动化引擎和Case（工况）应该分离

虽然本阶段暂时不定义S1～S15 Case，但以后设计时必须坚持：

```text
Engine（引擎）
=
怎么执行

Case（工况）
=
什么时候改什么
```

不要以后写成：

```text
15份几乎一模一样的完整脚本
```

通用引擎应该负责：

```text
控制权
连接
状态
Pause/Execute
SetParametersByName
Reset
日志
异常处理
```

Case只负责：

```text
事件时间
参数名
参数值
预检查
结束时间
```

---

# 40. 当前为什么暂时不写Case定义

当前不急着写S1～S15 Case，原因：

```text
LOCAL15已经完成15/15人工验收

项目下一主线是BOARD15

BOARD15最终参数入口
很可能由：
RT-LAB配置寄存器
→ Modbus
→ Board
实现

而不是直接改：
LOCAL15内部CFG15参数
```

如果现在把15个Case全部按当前LOCAL15路径写死：

```text
BOARD15回来以后还要改一次
```

所以当前只冻结：

```text
引擎
规则
经验
脚本方法
```

是合理的。

---

# 41. 当前建议保留的参考脚本

本阶段可以保留：

```text
P1_LOCAL15_PAUSE_TIME_AUTOMATION_V4.py
```

定位：

> **LOCAL15仿真时间驱动自动在线调参的参考实现。**

它不是：

```text
以后15策略最终统一Runner
```

而是：

```text
已验证自动化能力的Golden Example
（黄金示例）
```

---

# 42. 后续真正开发通用Runner时应该继承哪些内容

必须继承：

```text
GetActiveProjects发现工程

GetCurrentModel确认模型

MODEL_PAUSED枚举检查

TakeFunctionControl Macro Priority

GetParametersDescription发现参数

SetParametersByName修改参数

SetPauseTime定义Simulation Time事件

Execute / Resume

状态等待

Safety Preflight

try / finally

Reset状态判断

ReleaseFunctionControl
```

---

# 43. 后续哪些东西不能直接继承到BOARD15 / CHIL

不能直接继承：

```text
事件时暂停RT-LAB
```

因为BOARD15 / CHIL有外部真实控制板。

也不能直接继承：

```text
LOCAL15 CFG15参数路径
```

因为BOARD15未来很可能变成：

```text
RT-LAB运行时配置
↓
Modbus配置寄存器
↓
Board configuration
```

因此：

```text
Engine思想
可以复用

参数入口
需要适配

Pause调度
需要替换
```

---

# 44. BOARD15未来自动化最可能需要的新执行方式

未来更可能是：

```text
RT-LAB持续Execute
不Pause

↓

自动测试Runner
根据：
RT-LAB simulation time
或
专用TEST_TIME
或
模型内Test Scheduler
触发

↓

在线改：
BOARD15配置寄存器
RT-LAB Plant工况
Execution Fault
```

但是这些留到：

```text
BOARD15接口冻结以后
```

再设计。

当前不提前做。

---

# 45. 论文自动实验未来也复用同一方法学

未来论文：

```text
PAPER_BASELINE

PAPER_EXEC_ONLY

PAPER_EXEC_RECOVERY

PAPER_PROPOSED
```

最终也应该由：

```text
同一个自动测试引擎
```

控制。

不同之处只在：

```text
Profile
Fault
Case
```

而不是：

```text
换不同程序
```

---

# 46. 本阶段最重要的经验教训汇总

---

## 经验1

Python在线改参数本身并不难。

真正容易出问题的是：

```text
RT-LAB控制权
模型状态
日志buffer
脚本执行方式
```

---

## 经验2

先做最安全参数的P0/P1验证非常必要。

不要一开始自动改：

```text
Pref
Breaker
Mode
```

---

## 经验3

交互Console适合探路，不适合正式自动流程。

---

## 经验4

API文档能力不能直接假定当前环境一定暴露。

例如：

```text
GetNumAcqGroup
```

当前环境实际不存在。

因此：

> **当前安装版本的实际返回是最高优先级事实。**

---

## 经验5

SetParameters虽然能工作，但已deprecated。

正式脚本用：

```text
SetParametersByName
```

---

## 经验6

状态比较必须用枚举。

---

## 经验7

自动脚本一定要主动管理Control ownership（控制权）。

---

## 经验8

异常处理必须包含：

```text
Reset
+
Release Control
```

否则GUI可能失去操作权。

---

## 经验9

按仿真时间做自动测试时：

```text
SetPauseTime
```

比：

```text
Host sleep
```

精确得多。

---

## 经验10

MAT是否有数据不仅取决于模型是否运行，还取决于：

```text
OpWriteFile buffer
```

是否形成完整数据块。

---

# 47. 自动化开发建议的成熟度等级

---

## P0

```text
Running状态在线改参
```

当前：

```text
PASS
```

---

## P1

```text
仿真时间驱动
自动Execute / Pause / 改参 / Reset
MAT验证
```

当前：

```text
PASS
```

---

## P2

未来：

```text
通用Engine + Case Data
```

当前：

```text
暂缓
```

---

## P3

未来：

```text
S1～S15自动回归
```

当前：

```text
等BOARD15接口冻结后再做
```

---

## P4

未来：

```text
BOARD15真实闭环不中断自动工况
```

当前：

```text
未开始
```

---

## P5

未来：

```text
论文Baseline / Ablation / Proposed
一键批量实验
```

当前：

```text
未开始
```

---

# 48. 当前冻结后的正确下一步

自动化方面：

```text
到此暂停
```

不再继续：

```text
扩展15个Case
扩展自动绘图
扩展自动PASS
```

当前自动化成果已经足够证明：

```text
技术路线可行
```

下一阶段主线应该回到：

```text
LOCAL15 C接口审计
↓
S1～S15执行周期审计
↓
LOCAL15 → C
↓
BOARD15 Modbus / Runtime Config接口
↓
最终工程程序需求冻结
```

等：

```text
BOARD15最终接口
```

明确以后，再回来做：

```text
正式自动Case Runner
```

---

# 49. 推荐长期保存的自动化资产

```text
项目可复用操作/
└─ RTLAB_Python_Automation/
   │
   ├─ 01_RTLAB_Python自动化在线调参_引擎规则经验.md
   │
   ├─ examples/
   │  └─ P1_LOCAL15_PAUSE_TIME_AUTOMATION_V4.py
   │
   └─ future/
      └─ BOARD15_CaseRunner（以后再建）
```

---

# 50. 最终冻结结论

本阶段已经证明：

> **RT-LAB 2024.1 + OP5700 + K26_V5 可以由Host Python脚本在模型Load后自动取得系统/参数控制权，自动Execute，按照RT-LAB自身Simulation Time通过SetPauseTime精确进入事件时刻，使用SetParametersByName在线修改Tunable Parameter，再继续执行、Reset并释放控制权；Target侧MAT能够真实记录对应参数变化。**

因此后续：

```text
LOCAL15自动测试
BOARD15自动回归
论文自动实验
```

都具备了明确的自动化技术基础。

但当前最合理的节奏是：

> **冻结引擎与规则，不继续为LOCAL15编写15份最终Case；等BOARD15运行时配置接口和最终点表冻结以后，再把当前引擎思想适配为BOARD15正式自动测试框架。**
