# K26_V5 V3.4｜端口重构前只读审计 V1.3

## 这次为什么又报错

V1.2 使用了：

```matlab
fflush(fidU)
```

这是我错误地带入了其他语言/运行环境的文件刷新习惯。MATLAB R2023b 没有这个函数。

它与 K26_V5 模型无关，属于审计脚本兼容性错误。

## V1.3 不只删除这一行，而是处理整个同类问题

### 1. 完全移除 `fflush`

当前审计的任何安全判定都不再依赖：

```text
日志文件有没有立刻刷新到磁盘
文件当前bytes是多少
```

失败日志由 `onCleanup -> fclose` 在异常退出时正常落盘。

### 2. 增加真正的 MATLAB 兼容性预检

在：

```text
load_system
compile
任何模型状态动作
```

之前先检查后面实际需要的：

```text
contains
startsWith
endsWith
slResolve
sfroot
```

并执行固定列宽 cell-table 自测。

成功时首先看到：

```text
[AUDIT SELFTEST PASS] R2023b function availability + fixed-width cell append.
```

### 3. 把之前“表宽检查”继续提前

V1.1 虽然在写 CSV 前检查列数，但如果：

```text
第一行5列
第二行4列
```

MATLAB 会在第二次赋值时先报错，根本走不到末尾检查。

V1.3 已把以下所有主要动态表：

```text
interfaceRows
semanticRows
edgeRows
paramRows
keyRows
mgrRows
scriptIndex
awRows
insertRows
frameRows
centralRows
```

全部改成：

```matlab
appendCellRowChecked(...)
```

每一行写入时就检查列宽。

因此 V1.0 那类：

```text
1×5 <- 1×4
```

错误类别已经从结构上封死，而不是只修第448行。

### 4. 保留 V1.2 的状态兼容

当前模型如果是：

```text
paused
```

可以直接运行。

优先复用 PAUSED 编译上下文；只有确实读不到 compiled metadata 时才自动：

```text
SimulationCommand=stop
→ read-only compile
```

仍不修改控制参数、不保存模型。

### 5. 保留 V1.1 的 EMChart 自动解析

不再假设：

```text
AA15_FINAL_COORDINATOR_CORE 本身必须是 Stateflow.EMChart
```

而是从指定块/Subsystem下面解析真实 MATLAB Function。

---

# 直接运行

不要继续使用 V1.0 / V1.1 / V1.2。

直接：

```matlab
result = AUDIT_K26_V5_V34_PORT_RECONSTRUCTION_READONLY_V1_3( ...
'D:\Users\linjj\OPAL-RT\RT-LABv2024.1_Workspace\yanshou_V5\models\K26_V5\K26_V5.slx');
```

当前是 `paused` 也可以。

如果 V1.3 完整结束，上传最新：

```text
V34_PORT_RECONSTRUCTION_READONLY_AUDIT_时间戳
```

整个目录。

本轮仍然是只读审计，不进入模型 Patch。
