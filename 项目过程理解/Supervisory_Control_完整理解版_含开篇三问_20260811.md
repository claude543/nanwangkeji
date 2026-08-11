# 开篇先理解：Supervisor 到底在整个系统里干什么？

> 建议先把这一节看懂，再继续阅读后面的逐模块、逐连线、逐参数说明。

## 问题1：Supervisor 整个模块的作用到底是什么？它怎么串联到整个闭环？

**Supervisor 不是简单“生成 Fref / Vref”，而是在整个微电网层面做频率和电压的二次恢复控制。**

```text
PCC真实三相电压
↓
Supervisor测量
↓
得到 Fpcc、Vpcc
↓
与 50 Hz、10 kV 比较
↓
PI判断偏差大小与修正方向
↓
生成修正后的 Fref / Vref
↓
同时发给六台逆变器
↓
六台本地 Droop / Voltage Control 调整自身参考
↓
PWM / Converter 改变真实输出
↓
PCC频率、电压随之变化
↓
Supervisor重新测量
```

它真正干的是：

> **站在整个微电网层面，观察 PCC 的频率和电压是否偏离额定值，然后统一修正六台逆变器的公共运行基准，把系统频率、电压逐渐拉回 50 Hz 和 10 kV。**

Droop 与 Supervisor 的分工：

```text
Droop：
快速重新建立功率平衡
但允许频率/电压有静差

Supervisor：
在系统已经稳定后
继续消除这个静差
```

例如 Droop 先把系统稳在：

```text
49.8 Hz
9.8 kV
```

Supervisor再根据：

```text
50 - 49.8
10 kV - 9.8 kV
```

持续修正 Fref / Vref，把系统恢复到额定附近。

---

## 问题2：为什么它叫“二次控制”？

因为它不是第一时间直接负责把系统稳住，而是：

> **建立在一次控制已经把系统稳定下来的基础上，再把一次控制留下的频率、电压静差消掉。**

```text
一次控制：Droop
负荷变化
↓
快速重新分担功率
↓
系统先稳定
↓
但可能停在49.8 Hz、9.8 kV
```

然后：

```text
二次控制：Supervisor
测PCC实际F/V
↓
与50 Hz、10 kV比较
↓
PI修正Fref/Vref
↓
六台逆变器重新调整
↓
恢复到50 Hz、10 kV附近
```

最简单的记法：

> **一次控制负责“先稳住”，二次控制负责“稳住以后恢复到额定值”。**

---

## 问题3：那在我们当前实际闭环里，一次、二次控制到底发挥在哪里？为什么感觉不到？

你的感觉是对的。

**当前基线虽然保留了 Droop 一次控制和 Supervisor 二次控制，但真正驱动 PWM 的主执行通道仍然是 Grid-Following，因此它们目前更多是在后台计算，并没有真正主导物理系统。**

当前真正生效的主闭环：

```text
PCC有功
↓
AGC
↓
六路 Pref
↓
Grid-Following Power Control Loop
↓
Id/Iq_ref
↓
Current Regulator
↓
PWM
↓
Converter
↓
设备真实Pmeas / PCC
↓
再反馈
```

所以现在看到：

```text
PCC约 -120 kW
→ AGC投入
→ PCC约 -100 kW
```

主要体现的是：

```text
AGC + GFL功率外环 + 电流内环 + PWM
```

### 为什么一次控制不明显？

3 s 时：

```text
Droop_On = 1
```

只是让六台逆变器内部的 Droop Control 开始计算：

```text
P-f
Q-V
Fout
Vout
theta
GFM Id/Iq_ref
```

但：

```text
Droop开始计算
≠
Droop已经接管PWM
```

真正决定执行路径的是：

```text
GRIDON
→ ConnectMode
→ signal switch
```

当前仍选择 PLL / Grid-Following 路径。

### 为什么二次控制也不明显？

5 s 时：

```text
Ctrl_On / Supervisor Enable = 1
```

Supervisor开始：

```text
测 Fpcc / Vpcc
→ PI
→ 动态生成 Fref / Vref
```

这些参考也确实送到了六台逆变器，但主要服务于：

```text
Droop / Voltage Regulator
= Grid-Forming候选路径
```

而当前真正执行的仍然是：

```text
Grid-Following Power Control
```

### 还有一个原因：当前接着强电网

当前10 kV公共电网本身已经强力支撑：

```text
频率
电压
相角
```

所以也很难看到典型的：

```text
负荷变化
→ Droop让频率掉到49.8 Hz
→ Supervisor再恢复到50 Hz
```

这种一次、二次控制过程。

---

## 三个开关必须这样区分

```text
Droop_On
3 s投入
→ 开启本地Droop的P/Q下垂计算
→ 不能决定GFL/GFM


Ctrl_On / Supervisor Enable
5 s投入
→ 开启Supervisor的F/V二次恢复PI
→ 不能决定GFL/GFM


GRIDON / ConnectMode
→ 控制signal switch最终选路
→ 真正决定公共Current Regulator听GFL还是GFM
```

---

## 开篇最终结论

当前模型中：

```text
Droop一次控制
= 已存在，3 s开始计算

Supervisor二次控制
= 已存在，5 s开始计算

但真正物理执行
= 仍由GFL路径主导
```

当前真正主闭环：

```text
AGC
→ Pref
→ GFL功率环
→ 电流环
→ PWM
→ Converter
→ PCC
```

一次、二次控制真正典型的作用，要在：

```text
ConnectMode切到GFM
或进入孤岛/弱电网场景
```

时才会非常明显：

```text
负荷变化
↓
Droop一次控制先快速稳住
↓
留下F/V静差
↓
Supervisor二次控制再恢复额定值
```

> **一句话：当前 Droop 和 Supervisor 都“在工作”，但当前并没有“掌舵”；真正掌舵的仍是 Grid-Following 路径。**

---

# 暑期南网科技项目｜Microgrid Supervisory Control 彻底理解版
## ——为什么 Droop_On 在 3 s 开启后，六台逆变器仍然是跟网模式？

> 对象：当前 `SM_Master` 中的 `Microgrid Supervisory Control`，以及它与六台 SS 内 `Control System` 的关系。  
> 依据：当前上传的 Supervisor 内部截图、三个参数窗口，以及当前已经确认的分核模型接口。  
> 当前实时基本步长：`Ts = 1e-4 s = 100 μs`。  
>
> **先记住最重要的一句话：**
>
> **`Droop_On`、`Ctrl_On/Enable`、`GRIDON/ConnectMode` 是三个完全不同的信号。**
>
> - `Droop_On`：3 s 开启，只决定本地 **Droop Control 是否开始把 P/Q 反馈加入构网参考计算**；
> - `Ctrl_On → Supervisor Enable`：5 s 开启，决定 **Supervisor 的频率/电压二次调节 PI 是否投入**；
> - `GRIDON → ConnectMode`：决定六台逆变器 **最终公共电流内环到底使用 PLL/GFL 路径，还是 Droop/GFM 路径**。
>
> 因此：
>
> ```text
> Droop_On = 1
> ≠
> 逆变器已经切成 Grid-Forming
> ```
>
> 当前 `GRIDON = 1`，`signal switch` 最终选择的是带 `F` 后缀的 PLL / Grid-Following 上支路，因此即使 3 s 后 Droop 计算已经在后台运行，真正送进公共 Current Regulator 和 PWM 的仍是 **Grid-Following 路径**。

---

# 1. 先把三个容易混淆的“开关”彻底分开

当前模型中存在三个不同层级的控制信号。

## 1.1 `Droop_On`：3 s 开启

当前六台设备都有：

```text
Droop_On:
0 ～ 3 s = 0
3 s以后   = 1
```

它通过每台设备的 12 维控制向量送到 SS 中 `Control System` 的第 5 个输入：

```text
Droop_On
→ Control System
→ Droop Control / Enable
```

它的作用只是：

```text
Droop_On = 0
→ Pmeas、Qmeas 的下垂反馈不参与
→ Droop输出主要保持基础Fref/Vref

Droop_On = 1
→ Pmeas参与 P-f 下垂
→ Qmeas参与 Q-V 下垂
→ 得到新的 Fout、theta_out、Vout
```

所以它的准确含义是：

> **“允许构网那套 Droop 参考在后台真正按照 P/Q 工作。”**

它没有直接接到 `signal switch` 的模式选择端。

---

## 1.2 `Ctrl_On → Enable`：5 s 开启

Supervisor 本身的第二输入是：

```text
Enable
```

当前顶层给它的是：

```text
Ctrl_On
```

当前时序：

```text
0 ～ 5 s = 0
5 s以后   = 1
```

它控制的是 Supervisor 内部：

```text
频率二次调节 PI
电压二次调节 PI
```

也就是：

> **“Supervisor 什么时候开始根据 PCC 的频率和电压偏差，主动修正 Fref / Vref。”**

所以：

```text
Droop_On = 3 s
Ctrl_On  = 5 s
```

是两件不同的事。

---

## 1.3 `GRIDON → ConnectMode`：真正决定 GFL / GFM

六台 Control System 还有第 8 个输入：

```text
GRIDON
```

进入内部后变成：

```text
ConnectMode
```

`ConnectMode` 控制 `signal switch` 中的一整组 Switch。

以电流参考为例：

```text
上支路：
[IdIq_refF]
来自 Power Control Loop + PLL
= Grid-Following

下支路：
[IdIq_ref]
来自 Droop + Voltage Regulators
= Grid-Forming

中间：
[ConnectMode]
决定到底选哪一路
```

不仅电流参考要切，以下信号都必须同步切：

```text
IdIq_ref
IdIq_meas
VdVq_meas
wt/theta
```

否则就会出现：

```text
参考量在PLL坐标系
实际量却在Droop坐标系
```

这种完全错误的混合。

当前模型 `GRIDON = 1` 时，实际使用的是：

```text
IdIq_refF
VdVqF
IdIqF
thetaF
```

也就是 PLL / Grid-Following 路径。

因此：

```text
3 s：
Droop_On = 1
→ GFM路径开始正常计算

但：
GRIDON仍 = 1
→ ConnectMode仍选GFL路径

所以：
实际PWM仍由GFL路径控制
```

可以把它理解为：

> **备用的构网控制器已经开机并在后台算，但“轨道道岔”还指向跟网轨道。**

---

# 2. 当前三个时刻到底发生什么

当前基线可以按时间理解。

```text
0 ～ 3 s
----------------
GRIDON = 1
→ GFL路径实际接管

Droop_On = 0
→ GFM Droop反馈没有投入

Ctrl_On = 0
→ Supervisor PI处于复位/旁路状态


3 s
----------------
Droop_On: 0 → 1

→ 六台Droop Control开始根据P/Q计算
   Fout / theta / Vout

但是：
ConnectMode没有变化

→ 实际公共Current Regulator仍吃GFL数据
→ 逆变器仍然跟网


5 s
----------------
Ctrl_On: 0 → 1

→ Supervisor开始根据PCC：
   Fnom - Fpcc
   Vnom - Vpcc
   调节Fref、Vref

Fref/Vref继续发给六台逆变器

但：
ConnectMode仍没有变化

→ GFL仍然是实际执行路径
```

所以最核心的逻辑是：

> **“某套控制器开始计算”不等于“这套控制器已经被选为实际执行控制器”。**

---

# 3. Supervisor 整体到底是干什么的

`Microgrid Supervisory Control` 位于 SM 中，输入：

```text
In1 = PCC三相原始电压 Vpcc = [Va,Vb,Vc]
In2 = Enable / Ctrl_On
```

输出：

```text
Out1 = Fref
Out2 = Vref
```

它不是 AGC。

AGC解决：

```text
PCC有功应该是多少
→ 六台设备Pref怎么分
```

Supervisor解决：

```text
公共微网频率和电压应该以什么参考值运行
→ 给六台本地Droop/GFM控制器统一Fref、Vref
```

从控制层级上可以理解为：

```text
Supervisor
= 公共频率/电压二次恢复控制

Droop
= 每台设备本地一次控制

Current Regulator / PWM
= 最底层快速执行
```

---

# 4. 图2：Supervisor前半部分——先从三相 Vpcc 得到 Fpcc 和 Vpcc 标量

图2这一半的任务只有一句话：

> **把输入的三相瞬时 PCC 电压，处理成一个稳定的 PCC 频率 `Fpcc` 和一个稳定的 PCC 线电压 RMS `Vpcc`。**

注意这里有一个命名容易混淆：

```text
Supervisor输入端 Vpcc
= 三维 [Va,Vb,Vc] 瞬时电压向量

内部标签 [Vpcc]
= 经过基波提取、RMS换算和滤波后的标量线电压
```

它们名字相同，但维度和含义不同。

---

# 5. 模块1：Inport `Vpcc`

名称：

```text
Vpcc
```

类型：

```text
Inport
```

宽度：

```text
3
```

实际内容：

```text
[Va,Vb,Vc]
```

它直接来自 SM 中 PCC 三相 V-I Measurement 的三相电压输出。

为什么 Supervisor 必须接三相原始电压，而不能只接 `Vab_rms_pcc`？

因为 Supervisor 内部自己的：

```text
PLL
Fundamental
```

都需要三相瞬时波形或同步基准。

所以正确链是：

```text
PCC三相Vabc
→ Supervisor In1
```

不是：

```text
Vab_rms_pcc标量
→ Supervisor In1
```

---

# 6. 模块2：Gain —— PLL 输入归一化

图中：

```text
Vpcc
→ Gain（三角形 -K-）
→ PLL (3ph)
```

名称可以理解为：

```text
Gain / PLL输入电压归一化增益
```

PLL 参数窗口明确写着：

```text
Input:
Vector containing the normalized three-phase signals [Va Vb Vc]
```

所以这个 Gain 存在的直接原因是：

> **PLL希望接收的是归一化三相波形，而不是直接处理10 kV数量级的电压。**

原模型这一级的设计量级对应于：

```text
相电压峰值基值
≈ Vnom × sqrt(2) / sqrt(3)
```

再用它对三相电压归一化。

这样额定情况下：

```text
三相电压幅值
≈ 1 pu量级
```

好处：

```text
电压是9.8 kV还是10.2 kV
不会直接改变PLL调节器的数量级

PLL主要关注：
相位在哪里
频率是多少
```

> 图中 Gain 图标只显示 `-K-`，因此具体表达式的正负号应以当前块参数窗口为最终依据；其功能可以确定为 PLL 输入尺度归一化。

---

# 7. 模块3：`PLL (3ph)` —— 三相锁相环

这是图1左侧参数窗口。

名称：

```text
PLL (3ph)
```

输入：

```text
abc
= 归一化三相PCC电压
```

输出：

```text
Freq
= 测得频率，单位Hz

wt
= 当前基波电气相角，0～2π循环
```

通俗理解：

```text
Freq：
“现在电网转得多快？”

wt：
“现在电网正弦波转到哪一个角度？”
```

Supervisor后续所有基波测量都需要这套共同同步参考。

---

## 7.1 PLL参数：Minimum frequency = 45 Hz

设置：

```text
Minimum frequency = 45 Hz
```

含义：

> PLL允许跟踪的最低频率边界。

为什么不是0？

因为这是一个：

```text
50 Hz 电力系统
```

正常或合理扰动范围不会跑到接近0 Hz。

设置最低45 Hz可以：

```text
防止异常输入、启动暂态或失锁时
PLL把非常低的伪频率当成真实电网频率
```

它不是说系统要运行在45 Hz，而是PLL的保护/有效搜索边界。

---

## 7.2 PLL参数：Initial inputs `[Phase, Frequency] = [0,Fnom]`

当前：

```text
[0,Fnom]
→ [0°,50 Hz]
```

意思：

```text
仿真刚开始时
PLL先假设：
相角 = 0°
频率 = 50 Hz
```

为什么？

因为系统额定就是50 Hz。

如果PLL一开始从：

```text
0 Hz
```

或完全随机角度起步，就会产生很大的启动暂态。

从接近真实工作点的：

```text
50 Hz
```

开始，能更快、更平滑锁定。

---

## 7.3 PLL参数：Regulator gains `[Kp, Ki, Kd] = [180,3200,1]`

这是：

```text
PLL内部相位误差调节器
```

的参数。

不是 Supervisor 后面的 `Kp_Freg=0.03`、`Ki_Freg=2`。

二者完全不是同一个PI。

PLL内部：

```text
相位误差
→ 内部调节器
→ 修正PLL自身估计角速度/相角
```

其中：

```text
Kp = 180
→ 对当前相位误差快速响应

Ki = 3200
→ 消除长期锁相偏差

Kd = 1
→ 对相位误差变化提供额外阻尼/动态修正
```

为什么数值比 Supervisor PI 大很多？

因为PLL是：

```text
快速同步环
```

而Supervisor是：

```text
较慢的上层频率/电压恢复环
```

它们控制的对象和时间尺度根本不同。

这组 `[180,3200,1]` 是当前模型模板已经采用并验证的同步参数，不是电力行业规定的唯一标准值。

---

## 7.4 PLL参数：Derivative time constant = `1e-4 s`

当前：

```text
1e-4 s = 100 μs
```

它用于PLL内部微分作用的实际离散实现/滤波时间尺度。

当前模型：

```text
Ts = 100 μs
```

所以这个值与实时控制基本步长处于同一量级。

目的：

> 让微分项可以在离散模型中稳定实现，而不是对高频噪声无限放大。

---

## 7.5 PLL参数：Maximum rate of change of frequency = 12 Hz/s

作用：

> 限制PLL估计频率每秒最多以多快速度变化。

如果三相电压受到瞬时噪声或暂态冲击，PLL原始计算可能突然认为：

```text
50 Hz
→ 56 Hz
→ 49 Hz
```

这种瞬时大跳不应该直接成为系统频率测量。

所以限制：

```text
最大变化率 = 12 Hz/s
```

本质上是在抑制不真实的频率瞬跳。

---

## 7.6 PLL参数：Filter cut-off frequency = 25 Hz

这是：

```text
PLL内部“频率测量输出”的滤波截止频率
```

作用：

```text
保留频率动态
滤除更高频率的抖动/噪声
```

注意它不是说：

```text
把50 Hz基波滤掉
```

因为这里滤的是：

```text
“频率估计值这个慢变量”
```

不是原始50 Hz电压波形。

---

## 7.7 PLL参数：Sample time = `Ts = 0.0001 s`

即：

```text
100 μs
```

与当前实时模型基本步长完全一致。

因此PLL每一个实时步都更新一次：

```text
Freq
wt
```

---

## 7.8 PLL参数：Enable automatic gain control

当前勾选。

PLL说明写得很明确：

> 开启后，PLL调节器输入的相位误差会根据输入信号幅值自动缩放。

为什么需要？

因为电压幅值可能变化：

```text
0.95 pu
1.00 pu
1.05 pu
```

如果相同相位误差因为电压幅值变化而产生完全不同的PLL误差信号大小，会影响锁相动态。

自动增益控制可以使：

> PLL更关注“相位错了多少”，而不被电压幅值变化过度影响。

---

# 8. PLL的两条输出线为什么要分叉

PLL输出：

```text
Freq
wt
```

在图2中不是只给一个模块。

`Freq` 分成两条用途：

```text
第一条：
→ Fundamental (PLL-Driven)
告诉它当前基波频率

第二条：
→ Second-Order Filter
→ Saturation
→ [Fpcc]
形成Supervisor正式的PCC频率反馈
```

`wt`：

```text
→ Fundamental (PLL-Driven)
```

告诉基波提取器：

```text
“当前参考相角在哪里。”
```

所以PLL既是：

```text
频率测量器
```

也是：

```text
后续同步测量模块的时间/相角基准
```

---

# 9. 模块4：Demux —— 把三相 Vpcc 拆开

图2左上黑色竖条模块：

```text
Demux
```

输入：

```text
[Va,Vb,Vc]
```

输出：

```text
Va
Vb
Vc
```

为什么要拆？

因为Supervisor电压控制需要的是：

```text
PCC线电压 RMS
```

当前选的是：

```text
Vab
```

所以需要把：

```text
Va
Vb
```

单独拿出来。

第三相：

```text
Vc
```

这一条链不需要，因此接：

```text
Terminator
```

---

# 10. 模块5：Terminator —— 终止未使用的 Vc

名称：

```text
Terminator
```

作用很简单：

> 明确告诉Simulink：“这个输出在当前算法中故意不用。”

它不参与计算。

存在意义：

```text
避免未连接输出警告
让模型结构更明确
```

---

# 11. 模块6：Sum `(+,-)` —— 计算线电压 Vab

Demux得到：

```text
Va
Vb
```

送入：

```text
Sum
```

图中的符号：

```text
+
-
```

所以：

```text
Vab = Va - Vb
```

为什么不是直接拿Va？

因为系统额定：

```text
10 kV
```

说的是三相：

```text
线电压 RMS
```

不是单相相对中性点电压。

因此Supervisor要控制：

```text
Vab_rms
```

才与：

```text
Vnom = 10000 V
```

具有同一物理意义。

---

# 12. 模块7：`Fundamental (PLL-Driven)` —— 基波幅值提取

这是图1右侧参数窗口。

名称：

```text
Fundamental (PLL-Driven)
```

三个输入：

```text
Input 1: Freq
Input 2: wt
Input 3: In = Vab瞬时波形
```

两个输出：

```text
|u|
= 基波幅值

∠u
= 基波相角，相对于PLL参考
```

它的官方说明含义是：

> 根据PLL给出的当前基波频率和参考相角，在一个基波周期的滑动窗口内，从输入信号中提取基波幅值和相位。

通俗理解：

```text
Vab(t)
仍然是一条不断上下摆动的50 Hz正弦波

Supervisor真正需要的是：
“这条正弦波的基波到底有多大？”
```

所以这个模块把：

```text
瞬时波形
→ 稳定的基波幅值
```

---

## 12.1 Fundamental参数：Initial frequency = `Fnom = 50 Hz`

刚开始还没积累满一个基波周期的数据。

所以它先按照：

```text
50 Hz
```

建立初始分析窗口。

符合系统额定工作点。

---

## 12.2 Fundamental参数：Minimum frequency = `45 Hz`

频率变化时，一个周期的窗口长度也要跟着变化。

设最低45 Hz，是为了：

```text
允许正常频率偏差
同时防止异常低频导致窗口算法失去合理意义
```

与PLL的最低频率边界一致。

---

## 12.3 Fundamental参数：Initial input `[Mag, Phase] = [1,0]`

官方说明：

```text
仿真第一个完整周期之前
输出先保持 Initial input 给定值
```

所以：

```text
Magnitude = 1
Phase = 0°
```

只是启动时的占位初值。

等滑动窗口收集到足够数据后：

```text
真实Vab基波幅值和相位
```

会替换这个初值。

它不是说实际PCC只有1 V。

---

## 12.4 Fundamental参数：Sample time = `Ts = 100 μs`

每100 μs更新一次滑动窗口。

和当前模型实时步长一致。

---

# 13. Fundamental 的相角输出为什么接 Terminator

当前Supervisor只关心：

```text
PCC电压幅值
```

用于：

```text
Vnom - Vpcc
```

并不需要再次使用：

```text
Vab相位
```

因为相位同步已经由PLL承担。

所以：

```text
∠u
→ Terminator
```

明确丢弃。

---

# 14. 模块8：Gain —— 基波幅值转 RMS

`Fundamental` 输出：

```text
|u|
```

是基波幅值。

后面经过一个：

```text
Gain
```

原模型这一层承担：

```text
峰值 → RMS
```

典型关系：

```text
Vrms = Vpeak / sqrt(2)
```

为什么必须转换？

因为后面的标称电压是：

```text
Vnom = 10000 V RMS
```

所以必须保证反馈的 `Vpcc` 也是：

```text
RMS
```

才能直接比较：

```text
Vnom - Vpcc
```

---

# 15. 模块9：Second-Order Filter —— 电压反馈低通滤波

Gain之后还有一个：

```text
Second-Order Filter
```

图标是下降曲线。

作用：

> 对提取出来的PCC电压幅值进一步平滑。

当前Supervisor原设计的外部反馈滤波参数为：

```text
fn_Filter ≈ 10 Hz
ζ = 1
```

其中：

```text
10 Hz
= 截止频率

ζ = 1
= 临界阻尼
```

为什么还要滤？

因为即使已经做了基波幅值提取：

```text
暂态
谐波
PWM残余
测量噪声
```

仍可能造成反馈抖动。

Supervisor是慢速上层控制，不应该追着每个高频小波动调节。

所以：

```text
PLL/Fundamental
负责“测出基波”

Second-Order Filter
负责“让上层PI看到更平稳的慢变量”
```

---

# 16. 模块10：Goto `[Vpcc]`

名称：

```text
Goto [Vpcc]
```

这里的 `[Vpcc]` 已经不是输入端的三相向量。

它现在表示：

```text
PCC线电压基波RMS标量
```

路径：

```text
三相Vpcc
→ Va-Vb
→ Fundamental
→ RMS Gain
→ Filter
→ [Vpcc]
```

后面图3中：

```text
From [Vpcc]
```

会把同一个标量取出来给电压PI。

Goto/From只是Simulink内部信号路由，不是通信。

---

# 17. 频率支路：PLL Freq 后为什么还有 Second-Order Filter

PLL已经输出：

```text
Freq
```

但Supervisor没有直接拿它做：

```text
Fnom - Freq
```

而是再经过：

```text
Second-Order Filter
```

原因和电压一样：

> Supervisor是慢速二次控制，不应追逐PLL每一个高频抖动。

这里要特别区分两个不同滤波：

```text
PLL参数里的 25 Hz filter
= PLL内部频率测量滤波

Supervisor外面的 Second-Order Filter
≈ 10 Hz
= 上层反馈再次平滑
```

两层不是重复，而是作用位置不同。

---

# 18. 模块11：Saturation —— Fpcc合理范围限幅

频率滤波之后还有一个图标为：

```text
Saturation
```

它的典型图形：

```text
低端平
中间线性
高端平
```

作用：

> 不允许异常测量值无限制进入Supervisor频率闭环。

例如：

```text
PLL启动瞬间
测量异常
短暂失锁
```

可能产生不合理频率。

Saturation把它限制在配置的允许范围。

截图没有显示该块的具体上下限，因此这里不人为写死数值；具体值应以它的 Block Parameters 为准。

---

# 19. 模块12：Goto `[Fpcc]`

频率正式反馈链：

```text
Vpcc三相
→ PLL
→ Freq
→ Second-Order Filter
→ Saturation
→ Goto [Fpcc]
```

所以：

```text
[Fpcc]
```

表示：

> **Supervisor最终认可、准备进入频率二次调节闭环的PCC频率标量。**

---

# 20. 图3：频率闭环——Supervisor怎样生成 Fref

图3上半部分是完整的频率二次调节。

---

# 21. 模块13：From `[Fpcc]`

名称：

```text
From [Fpcc]
```

它取回图2已经处理好的：

```text
PCC频率反馈
```

不是重新测一次。

---

# 22. 模块14：Constant `Fnom`

名称：

```text
Fnom
```

当前：

```text
Fnom = 50 Hz
```

含义：

> 系统希望最终恢复到的额定频率。

它既用于：

```text
频率偏差计算
```

又作为：

```text
Supervisor未投入时的默认Fref
```

---

# 23. 模块15：Sum —— `Fnom - Fpcc`

图中求和符号非常明确：

```text
[Fpcc] 从左进入 “-”
Fnom   从下进入 “+”
```

所以：

```text
e_f = Fnom - Fpcc
```

例如：

```text
Fpcc = 49.90 Hz
Fnom = 50.00 Hz

e_f = +0.10 Hz
```

意思：

> 实际频率偏低，需要把上层Fref往上修。

如果：

```text
Fpcc = 50.10 Hz
```

则：

```text
e_f = -0.10 Hz
```

Supervisor会向下修正Fref。

---

# 24. 模块16：`NOT`

名称：

```text
NOT
```

输入：

```text
Enable
```

输出：

```text
NOT Enable
```

为什么要先取反？

因为PI底部的辅助端口是：

```text
Reset / External reset
```

逻辑是：

```text
Reset = 1
→ PI复位到初始输出

Reset = 0
→ PI正常运行
```

但我们希望：

```text
Enable = 0
→ PI复位

Enable = 1
→ PI运行
```

所以必须：

```text
Reset = NOT(Enable)
```

于是：

```text
Enable=0
→ NOT=1
→ PI保持/恢复到初始状态

Enable=1
→ NOT=0
→ PI正式积分调节
```

---

# 25. 模块17：`PI regulator with anti-windup q`

这是图1中间参数窗口。

名称：

```text
PI regulator with anti-windup q
```

类型：

```text
Discrete PI Controller
```

输入：

```text
e_f = Fnom - Fpcc
```

辅助输入：

```text
Reset = NOT(Enable)
```

输出：

```text
一个绝对频率参考值 Fref_candidate
```

注意：

它不是简单输出：

```text
Δf
```

因为它的：

```text
Output initial value = Fnom = 50
Output limits = [51,49]
```

所以它的输出本身就在：

```text
49～51 Hz
```

附近，是一个绝对频率参考。

---

## 25.1 参数：Kp = `Kp_Freg = 0.03`

作用：

```text
当前频率误差一出现
立即给出比例修正
```

例如频率误差越大：

```text
即时修正越大
```

为什么只有0.03？

因为Supervisor不是PLL，也不是电流内环。

它是慢速上层恢复控制。

如果比例太大：

```text
PCC频率有一点小波动
→ Fref剧烈变化
→ 六台本地控制器都被快速扰动
```

反而容易造成振荡。

所以当前模板使用较温和的比例增益。

这不是国家标准规定值，而是模型当前的控制器整定参数。

---

## 25.2 参数：Ki = `Ki_Freg = 2`

积分作用负责：

> 消除长期存在的小频率静差。

如果只用P：

```text
可能最终稳定在49.97 Hz
但永远还有0.03 Hz误差
```

积分器不断累计：

```text
Fnom - Fpcc
```

最终推动系统回到：

```text
50 Hz附近
```

所以：

```text
P
= 快速纠正当前误差

I
= 消除长期稳态误差
```

---

## 25.3 参数：Output limits = `Freq_Limits = [51,49]`

当前评估值：

```text
Upper = 51 Hz
Lower = 49 Hz
```

也就是说Supervisor不能命令：

```text
Fref > 51 Hz
Fref < 49 Hz
```

为什么？

因为频率二次控制不能因为测量异常就产生：

```text
55 Hz
45 Hz
```

这种危险参考。

所以限幅给Fref一个合理安全边界。

这也是为什么使用：

```text
anti-windup
```

非常重要。

如果Fref已经到51 Hz，但积分器还继续累积正误差，就会发生积分饱和。

Anti-windup会阻止这种“虽然输出做不到，但积分器还一直憋着”的现象。

---

## 25.4 参数：Output initial value = `Fnom = 50`

当：

```text
Enable=0
```

或者PI被reset时，输出回到：

```text
50 Hz
```

为什么不是0？

因为：

```text
0 Hz
```

根本不是一个合理的逆变器频率参考。

所以即使Supervisor尚未正式投入，也应该给系统一个合理基础参考：

```text
Fref = 50 Hz
```

---

## 25.5 参数：Sample time = `Ts = 100 μs`

PI每个实时步都会更新离散状态。

虽然Supervisor的物理调节动态远慢于100 μs，但使用与主模型一致的采样步：

```text
避免跨采样率额外处理
保持RT-LAB离散执行确定性
```

---

# 26. 模块18：Switch —— Enable决定“PI还是Fnom”

频率PI后还有一个三输入：

```text
Switch
```

数据输入：

```text
上端 = PI输出
下端 = Fnom
```

控制输入：

```text
中间 = Enable
```

作用：

```text
Enable = 0
→ 输出 Fnom
→ Fref = 50 Hz

Enable = 1
→ 输出 PI结果
→ Fref根据PCC频率偏差动态修正
```

为什么已经有PI Reset，还要再加Switch？

这是双保险。

PI Reset保证：

```text
后台积分器状态干净
```

Switch保证：

```text
Supervisor未投入时
真正对外输出一定就是Fnom
```

也就是说：

```text
NOT + Reset
负责内部状态管理

Switch
负责最终输出选择
```

---

# 27. 模块19：Goto `[Fref]`

Switch输出一分为二：

```text
→ Goto [Fref]
→ Outport Fref
```

Goto是模型内部标签广播/路由。

Outport则把Fref显式送出Supervisor。

当前分核模型最终将这个Fref：

```text
SM Supervisor
→ 每台设备12维向量第3项
→ Memory / OpComm
→ SS Control System
```

所以六台设备收到同一个公共Fref。

---

# 28. 模块20：Outport `Fref`

名称：

```text
Fref
Port 1
```

这就是Supervisor真正的第一个外部输出。

---

# 29. 图3下半部分：电压闭环——怎样生成 Vref

其思想与频率完全平行：

```text
Vnom - Vpcc
→ PI
→ Vref
```

---

# 30. 模块21：Constant `Vnom`

名称：

```text
Vnom
```

当前：

```text
Vnom = 10000 V
```

因为当前系统是：

```text
10 kV线电压系统
```

Supervisor图2已经把三相瞬时电压处理成：

```text
Vab基波RMS
```

所以：

```text
Vnom = 10000 V
```

可以直接和：

```text
Vpcc
```

比较。

---

# 31. 模块22：From `[Vpcc]`

这里取得的：

```text
[Vpcc]
```

是图2已经处理好的：

```text
PCC线电压基波RMS标量
```

不是三相输入向量。

---

# 32. 模块23：Sum —— `Vnom - Vpcc`

图中：

```text
Vnom → “+”
Vpcc → “-”
```

所以：

```text
e_v = Vnom - Vpcc
```

例如：

```text
Vpcc = 9800 V
Vnom = 10000 V

e_v = +200 V
```

说明：

> PCC电压偏低，Supervisor需要把Vref往上推。

如果：

```text
Vpcc = 10200 V
```

则误差：

```text
-200 V
```

PI会降低Vref。

---

# 33. 模块24：第二个 `NOT`

和频率支路完全相同：

```text
Enable
→ NOT
→ Voltage PI Reset
```

所以：

```text
Enable=0
→ 电压PI复位

Enable=1
→ 电压PI正常运行
```

---

# 34. 模块25：`PI regulator with anti-windup q1`

这是电压二次调节PI。

输入：

```text
e_v = Vnom - Vpcc
```

输出：

```text
Vref
```

当前Supervisor保持的原有参数为：

```text
Kp_Vreg = 0.1
Ki_Vreg = 7
Vreg_Limits = [10400,9600] V
Output initial value = Vnom = 10000 V
Sample time = Ts = 100 μs
```

---

## 34.1 为什么 Kp_Vreg = 0.1

电压变化和频率控制的对象不同。

线路压降、无功变化、负荷扰动都会直接反映在PCC电压上。

因此电压恢复环需要一定即时响应，但仍然是上层控制，不能过激。

当前使用：

```text
Kp = 0.1
```

作为当前模板的整定结果。

---

## 34.2 为什么 Ki_Vreg = 7

电压系统中容易存在：

```text
线路压降
稳态无功需求
变压器/网络压降
```

导致长期静差。

积分作用负责把这种：

```text
Vnom - Vpcc
```

长期误差吃掉。

所以当前电压PI的积分作用比频率Supervisor PI更强。

---

## 34.3 为什么限幅 `[10400,9600] V`

即：

```text
0.96 pu ～ 1.04 pu
```

围绕10 kV上下约4%。

目的：

> Supervisor可以进行合理电压恢复，但不能因为反馈异常把六台设备电压参考推到危险范围。

---

## 34.4 为什么初值 `Vnom = 10000 V`

和频率一样：

```text
Supervisor没投入
```

不代表：

```text
Vref = 0
```

而是应该保持额定参考：

```text
Vref = 10 kV
```

因此PI复位时回到Vnom。

---

# 35. 为什么电压支路没有频率那样的最终 Switch

图3可以看到：

```text
频率：
PI → Switch → Fref

电压：
PI → 直接 Vref
```

原因是电压PI在Reset时本身已经被设置：

```text
Output initial value = Vnom
```

所以：

```text
Enable=0
→ NOT=1
→ PI复位
→ PI输出就是Vnom
```

已经等价于：

```text
旁路时输出额定电压
```

因此这个实现没有再额外放一个Vnom/PI Switch。

频率支路额外放Switch，是更明确地强制：

```text
Enable=0 → Fref=Fnom
```

两种实现的目标一致：

> Supervisor关闭时，Fref/Vref都保持额定值，而不是输出0。

---

# 36. 模块26：Goto `[Vref]`

电压PI输出一分为多路：

```text
→ Goto [Vref]
→ Outport Vref
→ Scope
```

Goto用于内部标签路由。

---

# 37. 模块27：Outport `Vref`

名称：

```text
Vref
Port 2
```

这就是Supervisor第二个正式输出。

最终：

```text
SM Supervisor
→ 六台设备12维向量第4项
→ SS Control System
```

---

# 38. 模块28：Scope

图3右下：

```text
Scope
```

它只是观察：

```text
Vref波形
```

不参与任何闭环计算。

删除Scope不会改变控制算法本身。

---

# 39. Supervisor完整闭环串起来

现在可以把图2和图3合起来。

## 39.1 频率链

```text
PCC三相Vpcc
↓
Gain归一化
↓
PLL (3ph)
↓
Freq
↓
Second-Order Filter
↓
Saturation
↓
Goto [Fpcc]
↓
From [Fpcc]
↓
Fnom - Fpcc
↓
PI regulator with anti-windup q
↓
Enable控制Switch
↓
Fref
↓
六台逆变器
```

---

## 39.2 电压链

```text
PCC三相Vpcc
↓
Demux
↓
Va - Vb
↓
Vab瞬时线电压
↓
Fundamental (PLL-Driven)
   ↑        ↑
  Freq      wt
↓
基波幅值
↓
峰值→RMS Gain
↓
Second-Order Filter
↓
Goto [Vpcc]
↓
From [Vpcc]
↓
Vnom - Vpcc
↓
PI regulator with anti-windup q1
↓
Vref
↓
六台逆变器
```

---

# 40. Supervisor输出到六台以后，为什么当前“看起来没真正控制GFL”？

这一步必须结合 SS 内 Control System 理解。

Supervisor输出：

```text
Fref
Vref
```

六台逆变器确实全部收到。

但收到：

```text
≠
一定被当前执行路径使用
```

在 Control System 中：

```text
Fref / Vref
主要进入：
Droop Control
Voltage Regulators
```

即：

```text
Grid-Forming候选路径
```

而当前实际 `ConnectMode` 选的是：

```text
Grid-Following路径
```

于是公共 Current Regulator 真正得到的是：

```text
PLL锁出的 thetaF
PLL坐标下的VdVqF / IdIqF
Power Control Loop产生的IdIq_refF
```

而不是：

```text
Droop产生的wt
Voltage Regulator产生的IdIq_ref
```

所以即使：

```text
Fref/Vref已经动态变化
Droop_On已经=1
```

当前GFL实际控制仍然主要由：

```text
PLL
Pref/Qref
Power Control Loop
```

决定。

---

# 41. 最关键的“后台计算”和“实际执行”区别

当前可以同时存在：

```text
Droop Control：
正在算 Fout / Vout / theta

Voltage Regulators：
正在算 GFM IdIq_ref

Power Control Loop：
正在算 GFL IdIq_refF

PLL：
正在算 GFL thetaF

Supervisor：
正在算 Fref / Vref
```

所有模块都可以同时运行。

但是最后：

```text
signal switch
```

只会选择一套信号进入：

```text
Current Regulator
→ Vref Generation
→ PWM
→ IGBT
```

所以：

> **Simulink里“模块有输出”不代表“这个输出目前正在控制物理系统”。**

这就是你“明明3 s已经Droop_On=1，为什么仍然跟网”的根本答案。

---

# 42. 用最通俗的比喻彻底理解

把逆变器想成一辆有两套驾驶系统的汽车。

系统A：

```text
Grid-Following
= 自动跟车系统
```

它看前车：

```text
PLL看大电网相位
```

然后根据：

```text
Pref / Qref
```

控制自己输出。

系统B：

```text
Grid-Forming
= 自主导航系统
```

它自己决定：

```text
频率
电压
相角
```

`Droop_On=1` 相当于：

> 把自主导航电脑开机，让它开始实时计算路线。

Supervisor则不断给它：

```text
目标速度 Fref
目标电压 Vref
```

但是：

```text
GRIDON / ConnectMode
```

才是方向盘前面的：

> **“到底让哪台电脑真正接管转向”的选择开关。**

当前选择的还是：

```text
Grid-Following
```

所以自主导航虽然已经在后台算，但车仍然由跟车系统开。

---

# 43. 三个信号最终应这样记

```text
Droop_On
----------------
作用：
开启/关闭Droop的P/Q下垂修正

回答：
“构网控制器要不要根据P/Q真正计算下垂？”

不能回答：
“现在到底是不是构网模式？”


Ctrl_On / Supervisor Enable
----------------
作用：
开启/关闭PCC频率、电压二次恢复PI

回答：
“Fref/Vref要不要根据PCC偏差动态修正？”

不能回答：
“现在到底选GFL还是GFM？”


GRIDON / ConnectMode
----------------
作用：
signal switch最终选路

回答：
“公共Current Regulator当前到底听PLL/GFL还是Droop/GFM？”

这才是：
实际模式选择信号
```

---

# 44. 当前模型的实际时序，用一句话串起来

```text
0～3 s：
跟网实际执行；
Droop还未按P/Q反馈运行；
Supervisor还未投入。

3 s：
Droop开始后台计算；
但ConnectMode不变；
实际仍跟网。

5 s：
Supervisor开始根据PCC F/V修正Fref/Vref；
这些参考继续送六台；
但ConnectMode仍选GFL；
实际仍跟网。

15 s：
AGC开始改六台Pref；
因为当前是GFL，
Power Control Loop根据Pref/Pmeas
真正改变IdIq_refF，
最终改变设备有功功率。
```

这也解释了为什么当前AGC在15 s以后能够直接把：

```text
PCC约 -120 kW
→ -100 kW
```

因为当前实际生效的是：

```text
Pref
→ Grid-Following Power Control Loop
→ Current Regulator
→ PWM
```

---

# 45. Supervisor为什么仍然值得保留

即使当前正式基线主要以GFL运行，Supervisor仍有两个价值。

第一，它使模型具备完整的：

```text
并网 / 孤岛
双模式架构
```

一旦 `ConnectMode` 真正切换到GFM，六台设备已经有：

```text
Fref
Vref
Droop
Voltage Regulator
```

可以立即建立公共电压/频率参考。

第二，它完整保留了原模型的：

```text
一次Droop
+
二次F/V恢复
```

层级关系。

这也是为什么：

```text
Droop_On
Supervisor Enable
ConnectMode
```

要设计成三个不同控制信号，而不是一个开关包办全部功能。

---

# 46. 最终总图

```text
                         SM
┌──────────────────────────────────────────────┐
│                                              │
│ PCC三相Vpcc                                  │
│      │                                       │
│      ▼                                       │
│ Microgrid Supervisory Control                │
│      │                                       │
│      ├→ PLL → Fpcc                           │
│      ├→ Fundamental → Vpcc RMS               │
│      │                                       │
│      ├→ Fnom-Fpcc → F PI → Fref              │
│      └→ Vnom-Vpcc → V PI → Vref              │
│                                              │
│ Ctrl_On(5s) → Supervisor Enable              │
│                                              │
│ Droop_On(3s) ──────────────────────────┐      │
│ GRIDON=1 ──────────────────────────────┼──────┼──→ 12维/设备
│ Fref/Vref ─────────────────────────────┘      │
└──────────────────────────────────────────────┘
                                              │
                                              ▼
                              SS中的 Control System
                         ┌──────────────────────────┐
                         │                          │
                         │ GFL路径                  │
                         │ PLL + Power Control      │
                         │ → IdIq_refF              │
                         │                          │
                         │ GFM路径                  │
                         │ Fref/Vref                │
                         │ + Droop_On               │
                         │ → Droop                  │
                         │ → Voltage Regulator      │
                         │ → IdIq_ref               │
                         │                          │
                         │ GRIDON → ConnectMode     │
                         │          │               │
                         │          ▼               │
                         │     signal switch        │
                         │          │               │
                         │ 当前选GFL                │
                         │          │               │
                         │          ▼               │
                         │ Current Regulator        │
                         │ → Vref Generation        │
                         │ → PWM                    │
                         │ → Converter              │
                         └──────────────────────────┘
```

---

# 47. 最终一句话

> **3 s 的 `Droop_On` 只是让六台逆变器的构网 Droop 控制器开始“会算”；5 s 的 `Ctrl_On` 让 Supervisor 开始“会根据PCC偏差修正 Fref/Vref”；真正决定六台逆变器“现在听哪套控制器”的，是独立的 `GRIDON → ConnectMode → signal switch`。当前 `GRIDON=1` 选择 PLL/Power-Control 的 Grid-Following 路径，所以 Droop 和 Supervisor 即使都已经运行，实际 PWM 仍由跟网控制链产生。**
