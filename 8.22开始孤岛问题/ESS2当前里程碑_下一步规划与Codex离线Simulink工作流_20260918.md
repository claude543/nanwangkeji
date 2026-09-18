# ESS2 当前里程碑、下一步规划与 Codex 离线 Simulink 工作流

日期：2026-09-18

---

# 一、当前到底是什么状态

## 1. 本轮最新正式试验已经跑通的链条

最新 DirectMAT 结果表明，本轮正式时序实际发生：

```text
ESS1 构网
↓
ESS2 准备 / 同期 / 真实合闸
↓
Restore-state4
12.4573 s
↓
Restore-state5
12.6573 s
↓
Restore-state6
16.3318 s
↓
-0.005 pu 小功率任务开始
21.3519 s
↓
任务到达
23.2920 s
↓
Restore-state7
33.8370 s
↓
S14-50
33.8371 s
↓
Beta 开始
33.8591 s
↓
Beta = 1
35.8548 s
↓
接管后保持
约 3 s
↓
S14-60
38.8568 s
↓
Correction Gain 开始
38.8608 s
↓
Primary 命令实际开始变化
38.8772 s
↓
Correction Gain = 1
约 42.85 s
↓
持续到约 58 s
```

因此，“恢复 → 资格 → 交权 → 一次协调”这一条链已经真实运行。

---

## 2. Restore-state6 → state7 已经真正闭合

上一轮一直卡 state6 的根因已经证实是 Restore Config 第五个 Mode 源没有写成5。

本轮修正后：

```text
Mode_min = 5
Mode_max = 5
Restore-state7 = 33.8370 s
```

所以此前模式路由问题已经解决。

### 门控本身如何

本轮 state6 正式门控：

```text
PowerError50W
最长连续成立 ≈ 2.9999 s（记录抽取）
RecordedPickup
最长连续成立 ≈ 3.0003 s
```

内部最终在33.837 s进入state7。

说明：

- ±50 W不是永远无法满足；
- 3 s dwell不是逻辑死锁；
- 它确实等到系统明显收敛后才放行。

这套门控目前没有必要再立即放宽。

---

# 二、接管是否成功

## 1. 同任务接管已经成功

关键事件：

```text
S14-50        33.8371 s
Beta start    33.8591 s
Beta full     35.8548 s
```

完整交接约：

```text
1.996 s
```

与设计的约2 s一致。

### 最重要的命令证据

接管过程中：

```text
S14 command = -0.005 pu
Coordinator command = -0.005 pu
Final command = -0.005 pu
```

DirectMAT统计：

```text
Max_CommandMatchError_Handover = 0
```

也就是说，Beta从0变1时只是：

```text
更换命令所有者
```

没有改变实际有功任务。

这是当前接管设计最关键的验证。

---

## 2. 接管没有触发明显新的电气异常

围绕state50、Beta开始、Beta完成的窗口：

```text
CurrentLimit = 0
ModHeadroom = 1
Support实际执行 = 0
```

接管附近：

```text
Vpu P2P ≈ 0.02 ~ 0.035 pu
PLL P2P ≈ 0.002 ~ 0.005 Hz
```

没有出现因为换命令来源导致的明显阶跃或持续恶化。

因此可以冻结：

> **S14 → Coordinator 同任务无扰接管方法已获得动态数据支持。**

---

# 三、Primary 小权限阶段是否成功

## 1. S14-60 已真实进入

```text
S14-60 = 38.8568 s
Correction Gain start = 38.8608 s
Correction Gain full ≈ 42.85 s
```

同时：

```text
SecondaryEnable = 0
```

说明本轮确实只投入了Primary，不是把二次一起混进来。

---

## 2. Primary 真的改变了储能2任务

自然频率约：

```text
50.234 ~ 50.236 Hz
```

高于50 Hz。

正常协调器因此把储能2从：

```text
-0.005 pu
```

逐步推向：

```text
-0.006 pu
```

即让储能2增加吸收功率。

方向在当前系统功率约定下是合理的：

```text
频率偏高
→ 岛内相对功率富余
→ 储能增加吸收
```

---

## 3. 权限和变化速度都受控

state60内：

```text
Pcmd min = -0.006 pu
Pcmd max = -0.005 pu
```

没有突破批准范围：

```text
[-0.006, -0.004] pu
```

state60内最大命令变化速度：

```text
0.0005 pu/s
```

与批准值一致。

注意分析表中的：

```text
Max_CommandRate_All = 0.0025 pu/s
```

不是Primary超速。

这是包含前面小功率pickup阶段的“全程最大值”；小功率0→-0.005本来采用约0.0025 pu/s。

真正state60中的Primary变化率仍是：

```text
0.0005 pu/s
```

---

## 4. Primary阶段没有明显失控

42.85 s之后到结束约15 s：

```text
Pcmd = -0.006 pu
Beta = 1
CorrectionGain ≈ 1
Secondary = 0
ESS2Available = 1
FailCode = 0
```

后段典型2 s窗口：

```text
Vpu约 1.00 ~ 1.03 pu
PLL约 50.234 ~ 50.236 Hz
CurrentLimit = 0
ModHeadroom = 1
```

Pmeas围绕-0.006 pu运行。

因此：

> **小权限Primary投入本身没有引发明显电气失控。**

---

# 四、我们的总体设计规划是否正确

## 结论

**正确，而且最新数据已经验证了设计顺序的合理性。**

当前顺序：

```text
先恢复设备
↓
先证明小功率可执行
↓
资格成立
↓
Coordinator先匹配同一个命令
↓
只交接ownership
↓
接管后保持观察
↓
再开放小权限Primary
```

比下面这种做法更好：

```text
恢复
+
大功率变化
+
换控制器
+
Primary
+
Secondary
一起打开
```

因为当前方法每一步都能解释。

本次数据直接证明：

- 资格成立；
- 交接命令匹配；
- Beta可以平滑完成；
- Primary可以在接管以后再投入；
- 权限和速率边界有效。

因此不建议推翻现有S14-40/50/60分层。

---

# 五、现在能不能推进下一步

**可以。**

但下一步不建议直接：

```text
增加PV/EV
```

也不建议直接：

```text
把ESS2 authority从0.001一下放到0.01/0.02 pu
```

因为当前还有一个关键功能没有单独验证：

> **Coordinator接管后，正常调度任务怎样更新ESS2的基础功率。**

---

# 六、最合理的下一步：正常任务基准更新

当前已经证明：

```text
Pbase = -0.005
+
Primary在±0.001内变化
```

但这还不是完整正常调度。

正常运行需要做到：

```text
上层正常调度给ESS2一个新的基础任务
↓
Coordinator更新baseline
↓
经过限幅和限速
↓
ESS2执行新的基础任务
↓
Primary只在新基础任务上叠加临时修正
```

### 下一轮建议

先关闭Primary实际修正，或者使用Mode4正常任务路径。

不要增加新的物理功率压力。

可以把下一基础任务放在**本轮已经实际证明可承受的范围**内。

例如概念上：

```text
-0.005
→ -0.006 pu
```

因为-0.006本轮已经由Primary真实执行并稳定运行。

这样下一轮只验证：

> “正常任务更新路径是否正确”

而不是同时验证：

> “新的更大功率是否稳定”

这保持了单变量可解释性。

### 下一轮完成后

再考虑：

```text
ESS1动态余量约束
↓
扩大ESS2正常任务范围
↓
扩大Primary authority
↓
恢复下一台GFL资源
```

---

# 七、Codex能否替代我们现在反复RT-LAB试错的大部分过程

## 核心答案

**可以把绝大部分“改模前验证、改模、离线测试、问题定位、脚本生成”前移给Codex + 本地MATLAB/Simulink。**

但是：

> **不能把离线Simulink PASS直接等同于RT-LAB目标机PASS。**

正确定位是：

```text
Codex + Simulink
= 强力预验证 / 自动迭代环境

RT-LAB
= 最终实时目标验收环境
```

不是二选一。

---

# 八、Codex适合承担哪些事情

如果使用本地Codex，让它访问：

```text
仓库
MATLAB
Simulink
脚本
SLX
历史MAT结果
```

可以让它自动完成：

```text
读取当前模型
↓
读最新结果
↓
定位原因
↓
生成改模计划
↓
生成MATLAB Patch
↓
在scratch模型执行Patch
↓
静态Verifier
↓
Simulink Update/Compile
↓
离线测试Harness
↓
跑离线仿真
↓
自动分析logsout
↓
如果失败继续改
↓
直到离线合同全部PASS
↓
生成正式RT-LAB Runner
↓
生成DirectMAT
```

这正是Codex最适合的工程工作：文件、代码、命令和测试闭环。

建议使用**本地Codex**而不是纯云环境，因为：

- MATLAB/Simulink许可证在本机；
- SLX和OPAL-RT库在本机；
- 可以直接运行`matlab -batch`；
- 可以访问你的真实工程文件。

---

# 九、Codex应该怎样“接入Simulink”

不要把主要方案设计成：

```text
Codex用鼠标一直点Simulink GUI
```

这个方案脆弱。

推荐：

```text
Codex
↓
生成/修改 MATLAB 自动化脚本
↓
matlab -batch "..."
↓
Simulink API
```

例如所有改模都继续采用我们已经形成的Patch范式：

```text
load_system
get_param
find_system
add_block
add_line
set_param
save_system
```

并通过：

```text
scratch copy
→ patch
→ postassert
→ reload
→ verifier
```

实现。

Codex负责：

- 写脚本；
- 调脚本；
- 看错误；
- 自动修改；
- 再跑。

---

# 十、没有OpWrite，离线Simulink怎样记录和证明

这是一个关键问题。

**离线Simulink根本不需要OpWrite。**

可以使用：

```text
Signal Logging
logsout
SimulationOutput
Simulation Data Inspector
To Workspace
To File
```

把我们关心的信号记录出来。

例如：

```matlab
out = sim(model);
logs = out.logsout;
```

然后运行离线分析器：

```text
state transition
Pmeas
Pref
Beta
CorrectionGain
CurrentLimit
Vpu
PLL
...
```

最后同样生成：

```text
OFFLINE_EVIDENCE.zip
```

所以：

> “没有OpWrite”不是离线仿真的证据障碍。

OpWrite只是当前RT-LAB目标机上的数据记录方式。

---

# 十一、应该建立三层离线验证

## Layer A：纯控制逻辑Harness

首先把：

```text
Restore Executor
S14
Ownership Blend
Coordinator
```

建立独立测试Harness。

给它们直接输入：

```text
Vpu
PLL
Pmeas
Iref
Imeas
CurrentLimit
Headroom
Mode
任务
```

验证：

- Mode1~5；
- state4/5/6/7；
- dwell；
- PickupQual；
- 第五Mode；
- command match；
- Beta；
- state50/60；
- Primary；
- 限幅；
- timeout；
- severe故障。

这种测试很快。

我们最近遇到的：

```text
Restore内部Mode仍为1
```

这类问题本来就应该在这一层被抓住。

---

## Layer B：历史真实MAT Replay

这是最适合当前项目的一层。

我们已经有大量真实RT-LAB MAT：

```text
G27
G29
G30
```

可以把历史真实测量作为Harness输入：

```text
真实Vpu(t)
真实PLL(t)
真实Pmeas(t)
真实CurrentLimit(t)
...
↓
新的Restore/S14/Coordinator逻辑
```

看新的状态机在同一批真实输入下会怎样运行。

优点：

- 不需要重新RT-LAB；
- 直接复用真实波形；
- 能非常快地验证门控、计时和状态逻辑。

例如上一轮state6问题，如果Replay Harness已经存在：

```text
Mode=5
+
真实PickupQual
↓
应在3 s后state7
```

就能马上发现模式入口问题。

### 边界

Replay是**开环逻辑验证**。

如果修改会反过来明显改变Pmeas/Vpu/PLL，那么用旧MAT不能预测新的物理动态。

所以它不能代替下一层。

---

## Layer C：离线闭环Shadow Model

建立：

```text
ESS1 GFM
+
ESS2 GFL
+
电气网络
+
Restore/S14/Coordinator
```

的桌面Simulink闭环版本。

尽量：

- 固定步长100 μs；
- 保持相同控制采样；
- 保留已有Z^-1；
- 保留滤波、限幅、状态机；
- 保留电气参数。

用它验证：

```text
修改后的控制
↓
会不会改变电气响应
↓
P/V/f/I是否稳定
```

这比Replay更接近RT-LAB。

---

# 十二、为什么离线Simulink仍不能最终替代RT-LAB

即使Layer C全部PASS，也还有以下项目只能由RT-LAB最终确认。

## 1. 实时deadline

桌面Simulink运行10秒仿真可能花：

```text
2秒
20秒
2分钟
```

都无所谓。

RT-LAB要求每个：

```text
100 μs
```

真实墙钟时间内算完。

所以只有目标机才能证明：

```text
Overrun = 0
```

---

## 2. 多核/SM-SS执行顺序

当前模型：

```text
SM
+
SS
+
OpComm
```

存在跨任务边界。

RT-LAB真实多核调度、跨核数据传输顺序与普通桌面单进程Simulink不是一回事。

如果有一拍通信延迟、数据同步和执行先后问题，离线仿真未必自动复现。

---

## 3. ARTEMiS / SSN / Stubline实时语义

当前电气模型不是最普通的Simulink。

我们使用：

```text
ARTEMiS
SSN
Stubline
```

这些本身就是为了实时电磁暂态和分核部署。

桌面离线仿真即使能够运行，也不能自动证明：

```text
目标实时求解
=
桌面结果完全一致
```

---

## 4. Runtime Parameter暴露

刚刚这次就是典型：

```text
模型里面有Constant
```

不等于：

```text
RT-LAB Build后一定暴露成可在线调参数
```

这只能在Build后：

```text
GetParametersDescription
```

确认。

离线Codex无法提前“证明目标机Runtime接口已经暴露”。

---

## 5. Modbus / 外部板卡 / 实际通信

以后Board进入：

```text
100 ms通信周期
网络延迟
丢包
读取/写入顺序
```

这些也必须到CHIL/目标环境验收。

---

# 十三、最合适的新工作流

当前我们是：

```text
设计
↓
改模
↓
Build
↓
Load
↓
Runner
↓
OpWrite MAT
↓
MATLAB
↓
发现问题
↓
重新改
```

建议改成：

```text
          ┌─────────────────────────┐
          │ Codex离线自动迭代区      │
          │                         │
需求 ───→ 结构审计
          ↓
        Patch
          ↓
        Verifier
          ↓
        Simulink Compile/Update
          ↓
        Logic Harness
          ↓
        历史MAT Replay
          ↓
        Shadow闭环仿真
          ↓
        自动结果分析
          ↓
        不通过则Codex继续修
          └─────────┬───────────────┘
                    │
              全部离线PASS
                    ↓
              RT-LAB Build
                    ↓
           Target Interface Verify
                    ↓
          只做一次正式58~60 s试验
                    ↓
                DirectMAT
                    ↓
             最终实时证据
```

---

# 十四、RT-LAB阶段也可以进一步缩短

每次Build之后，不应该立刻跑60秒。

先运行约几十秒以内、甚至不Execute的：

```text
TARGET_CONTRACT_VERIFY.py
```

只查：

- 参数路径；
- 五个Mode；
- 可写性；
- 信号路径；
- G27/G29/G30宽度；
- Runtime参数；
- FileID；
- readback。

全部PASS以后才正式Execute。

这次“第五Mode源”就属于这种Target contract问题，本来应该在正式58秒之前被发现。

以后把它作为固定闸门，可以省很多时间。

---

# 十五、Codex最适合的具体组织方式

建议仓库增加：

```text
offline_validation/
├─ contracts/
│  ├─ restore_contract.json
│  ├─ handover_contract.json
│  └─ primary_contract.json
│
├─ harness/
│  ├─ restore/
│  ├─ handover/
│  └─ primary/
│
├─ replay/
│  ├─ G27/
│  ├─ G29/
│  └─ scenarios/
│
├─ runners/
│  ├─ run_logic_tests.m
│  ├─ run_replay_tests.m
│  └─ run_shadow_sim.m
│
└─ reports/
```

再提供一个总入口：

```matlab
result = RUN_OFFLINE_PREVALIDATION;
```

Codex只需要不断执行：

```text
matlab -batch "RUN_OFFLINE_PREVALIDATION"
```

如果结果不是：

```text
OFFLINE_ALL_PASS
```

就根据报告继续修改。

---

# 十六、最终建议

## 当前工程

现在已经可以冻结：

```text
ESS2黑启动后恢复成功
+
小功率资格成功
+
正常Coordinator接管成功
+
小权限Primary成功
```

但这里的“恢复成功”必须解释为：

> ESS2已经成为Coordinator可用的孤岛GFL资源，并能在小权限范围承担一次有功协调。

不能扩大成：

> ESS2完整正常功率运行已全部验证。

因为“正常基础任务更新”和更大功率范围还没有验证。

## 下一步

优先：

```text
正常任务入口 / baseline update
```

使用本轮已经证明可承受的-0.006附近范围，避免同时增加物理应力。

然后：

```text
ESS1余量监控
→ 扩ESS2任务范围
→ 扩Primary authority
→ 下一台GFL资源
```

## 工程流程

从现在开始：

> **把Codex + 离线Simulink作为主要开发/预验证环境，把RT-LAB降为最终实时验收环境。**

这样可以明显减少“改一点模型就Build一次、跑一分钟再发现纯逻辑错误”的循环。

但RT-LAB不能完全删掉，因为：

- 实时deadline；
- 多核通信；
- ARTEMiS/Stubline；
- Runtime参数暴露；
- HIL通信；

这些都不是普通离线Simulink能够最终证明的。
