# RT-LAB 中 Model、I/O Interfaces、Configuration 与 Build-Load-Execute 的理解记录

## 1. 总体结论

RT-LAB 中可以把整个实时仿真系统理解成四个环节：

```text
Model              → 定义仿真模型内部怎么计算
I/O Interfaces     → 定义 OP5700 对外怎么通信
Configuration      → 定义外部接口和模型内部信号怎么连接
Build-Load-Execute → 把模型编译、下载并运行到 OP5700 上
```

通俗理解：

```text
Simulink Model = 机器内部
I/O Interfaces = 机器外壳上的通信接口
Configuration = 内部接线表，把通信接口接到模型信号
Build = 把图纸编译成可运行程序
Load = 把程序下载到 OP5700
Execute = 开始实时运行
```

RT-LAB 手册中的基本流程也是先编辑模型，再 Build 编译，然后分配目标机、设置运行属性，最后 Load 和 Execute。

---

## 2. Model 是什么？

Model 指 Simulink/RT-LAB 模型本体。

在当前项目中，主要包括：

```text
sm_circuit
sc_display
PCC 测量
PV / ESS / EV
AGC 控制逻辑
OpInput
OpOutput
OpComm
```

其中：

```text
sm_circuit = 实时计算主体，运行在 OP5700 上
sc_display = 控制台 / 显示界面，用于观察和交互
```

`sm_circuit` 中负责真正的微电网仿真，包括电气对象、测量量、设备控制入口等。

`sc_display` 主要用于上位机显示，例如显示板子写入的 40001~40009，或者模型输出的状态量。RT-LAB 手册也说明，模型运行后可以在 SC 中修改参数和观察下位机解算结果。

---

## 3. I/O Interfaces 是什么？

`I/O Interfaces` 是 RT-LAB 中定义外部接口的地方。

它可以配置多种外部通信或硬件接口，例如：

```text
Modbus Slave
Analog Input / Output
Digital Input / Output
PWM Input / Output
CAN
IEC104
```

当前项目使用的是：

```text
Modbus Slave
```

作用是让 OP5700 对外表现为一个 Modbus TCP 从站 / 服务器。

也就是说：

```text
外部板子通过网线访问 OP5700
板子可以写入 OP5700 的寄存器
板子也可以读取 OP5700 的寄存器
```

当前通信结构是：

```text
板子 = Modbus TCP Master / Client
OP5700 = Modbus TCP Slave / Server
```

在 `I/O Interfaces → Modbus Slave → Slave_1 → Holding registers` 中设置的点，本质上就是一张 Modbus 寄存器表。

---

## 4. Configuration 是什么？

`Configuration(Default*)` 是 RT-LAB 中的"接线表"。

它的作用是：

```text
把 I/O Interfaces 中的外部通信点
连接到
Simulink Model 中的 OpInput / OpOutput
```

如果没有 Configuration 连接，就会出现：

```text
Modbus 寄存器存在
Simulink 里的 OpInput / OpOutput 也存在
但两者没有关系
```

结果就是：

```text
板子写了寄存器，模型内部收不到
或者模型输出了信号，板子读不到
```

所以 Configuration 的核心作用是：

```text
让外部 Modbus 数据真正进入 sm_circuit
让 sm_circuit 的输出真正发布到 Modbus 寄存器
```

---

## 5. Model、I/O Interfaces、Configuration 的关系

整体关系如下：

```text
外部板子
  │
  │ Modbus TCP
  ↓
I/O Interfaces
Modbus Slave / Holding Registers
  │
  │ Configuration 连接
  ↓
Simulink Model
sm_circuit / OpInput / OpOutput
  │
  │ Build → Load → Execute
  ↓
OP5700 实时运行
```

更具体地说：

### 板子写 RT-LAB

```text
板子写 40001~40009
  ↓
I/O Interfaces 里的 Modbus Slave 接收
  ↓
Configuration 把寄存器连接到 sm_circuit 的 OpInput
  ↓
sm_circuit 得到外部控制命令
```

### RT-LAB 给板子读

```text
sm_circuit 输出测量量
  ↓
OpOutput
  ↓
Configuration 把 OpOutput 连接到 Modbus Holding Registers
  ↓
板子读取 40101~40116
```

---

## 6. 当前 9 路写入的含义

已经完成的 9 路是：

```text
40001~40009
Address = 0~8
Control from = Master
```

方向是：

```text
板子 → RT-LAB
```

实际作用是：

```text
板子通过 FC16 写 40001~40009
RT-LAB Modbus Slave 接收这些值
Configuration 把这些值送入 sm_circuit 的 OpInput
sm_circuit 内部可以使用这些控制量
sc_display 可以显示这些值
```

例如：

```text
板子写 40001~40009 = 101~109
RT-LAB SC 显示 101~109
```

说明：

```text
板子 → RT-LAB 的写入链路已经打通
```

---

## 7. 当前 16 路读取的含义

新增的 16 路是：

```text
40101~40116
Address = 100~115
Control from = Model
```

方向是：

```text
RT-LAB → 板子
```

当前测试结构是：

```text
Constant 201 → Op40101
Constant 202 → Op40102
...
Constant 216 → Op40116
```

完整链路是：

```text
Constant 201~216
  ↓
sm_circuit 中的 OpOutput
  ↓
Configuration 连接
  ↓
Modbus Slave Holding Registers 40101~40116
  ↓
板子通过 FC03 读取
```

如果板子读到：

```text
40101 = 201
40102 = 202
...
40116 = 216
```

说明：

```text
RT-LAB → 板子的读取链路已经打通
```

---

## 8. Holding Registers 中各列含义

| 列名 | 含义 | 当前项目中的作用 |
|------|------|----------------|
| Name | RT-LAB 内部给这个寄存器点起的名字 | 用于和 Simulink 里的 OpInput / OpOutput 匹配 |
| Address | Modbus 寄存器 offset 偏移地址 | 40001 对应 Address 0，40101 对应 Address 100 |
| Initial value | 初始值 | 模型启动前的默认值，一般设 0 |
| Control from | 谁控制这个寄存器的值 | Master 表示板子写，Model 表示 RT-LAB 模型写 |
| Register type | 数据类型 | 当前测试用 UINT16 |

---

## 9. Address、offset 和 40001/40101 的关系

RT-LAB 中的 `Address` 是 Modbus offset，不是 40001 或 40101。

关系是：

```text
显示地址 = 40001 + offset
```

所以：

```text
Address 0   → 40001
Address 1   → 40002
Address 8   → 40009
Address 100 → 40101
Address 115 → 40116
```

因此工程师板子程序中应使用：

```text
读 40101~40116：
start offset = 100
quantity = 16
```

而不是直接写：

```text
start address = 40101
```

---

## 10. Control from 的理解

`Control from` 是最关键的一列。

### Control from = Master

意思是：

```text
寄存器值由外部板子控制
```

用于：

```text
40001~40009
```

方向：

```text
板子 → RT-LAB
```

用途：

```text
板子写控制命令给 RT-LAB
```

---

### Control from = Model

意思是：

```text
寄存器值由 RT-LAB 模型控制
```

用于：

```text
40101~40116
```

方向：

```text
RT-LAB → 板子
```

用途：

```text
RT-LAB 把测量量发布给板子读取
```

---

## 11. Build / Load / Execute 的作用

### Build

作用：

```text
把 Simulink / RT-LAB 模型编译成 OP5700 能运行的实时程序
```

Build 会检查：

```text
模型结构是否正确
sm/sc 子系统是否符合 RT-LAB 规则
OpInput / OpOutput / OpComm 是否合法
I/O Interfaces 是否配置正确
Configuration 连接是否有效
```

如果 Build 失败，说明模型还不能交给 OP5700 运行。

---

### Load

作用：

```text
把 Build 生成的实时程序下载到 OP5700
让 OP5700 准备运行
```

Load 阶段会真正涉及目标机和授权，例如：

```text
OP5700 是否能连接
license 是否具备
Modbus Slave 是否能启动
端口是否可用
```

之前 IEC104 方案就是 Build 能通过，但 Load 报 license 错误，说明问题不在模型结构，而在目标机缺少 IEC104 授权。

---

### Execute

作用：

```text
让 OP5700 开始实时运行
```

Execute 后才会真正发生：

```text
板子写 40001~40009 → RT-LAB 模型收到
RT-LAB 输出 40101~40116 → 板子可以读取
```

所以：

```text
Build = 编译
Load = 下载并准备
Execute = 真正开始运行和通信
```

---

## 12. 当前项目中完整数据链路

### 板子写控制量

```text
板子
  ↓ FC16 写 Holding Registers offset 0~8
Modbus Slave 40001~40009
  ↓ Configuration
sm_circuit / OpInput
  ↓
后续接入设备 Pref 控制入口
```

### 板子读测量量

```text
sm_circuit / 测量量
  ↓
OpOutput
  ↓ Configuration
Modbus Slave 40101~40116
  ↓ FC03 读取 offset 100~115
板子
```

---

## 13. 当前阶段完成情况

当前已经完成：

```text
1. 板子 → RT-LAB 的 40001~40009 写入通道
2. RT-LAB → 板子的 40101~40116 固定值读取通道配置
3. Configuration 中 9 路写入点和 16 路读取点的连接
```

当前还没有完成：

```text
1. 40101~40116 替换成真实测量量
2. 板子周期性读取测量量
3. 板子内部运行 AGC
4. 板子输出控制命令并接入设备 Pref
5. EXT_ENABLE 切换内部 AGC / 外部 AGC
6. 完整闭环控制
```

---

## 14. 后续最终闭环目标

最终闭环应为：

```text
RT-LAB 微电网仿真对象
  ↓
采集 PCC / PV / ESS / EV 测量量
  ↓
RT-LAB 通过 40101~40116 发布测量寄存器
  ↓
板子通过 Modbus TCP FC03 读取测量量
  ↓
板子内部运行 AGC 算法
  ↓
板子通过 Modbus TCP FC16 写 40001~40009 控制命令
  ↓
RT-LAB 通过 Configuration 把控制命令送入 sm_circuit
  ↓
控制 PV / ESS / EV 设备 Pref
  ↓
微电网响应
  ↓
再次测量，形成闭环
```

---

## 15. 最核心记忆

```text
Model：模型怎么算
I/O Interfaces：外部怎么访问
Configuration：外部接口和模型信号怎么接
Build：编译
Load：下载到 OP5700
Execute：开始实时运行
```

以及：

```text
40001~40009：板子写 RT-LAB，Control from = Master
40101~40116：RT-LAB 给板子读，Control from = Model
```

最终要做到：

```text
板子读测量量 → 板子算 AGC → 板子写控制量 → RT-LAB 微电网响应
```
