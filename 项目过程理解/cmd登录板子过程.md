# CMD 登录板子过程

> 板子不能从 Windows 直接登录，也不从 OP5700 终端继续 SSH，而是通过 Windows 建立三层转发：

```
Windows 本地 10023
  → RTServer 管理口 192.168.10.87
  → 板子 192.168.1.10:10022
```

> 板子的 SSH 真实端口是 **10022**，不是 22。

---

## 第一步：建立 SSH 隧道

在 Windows 中新开一个 **PowerShell** 窗口，确认提示符为：

```
PS C:\Users\linjj>
```

完整执行以下命令：

```powershell
ssh -N -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o MACs=+hmac-sha1 -o ExitOnForwardFailure=yes -L 127.0.0.1:10023:192.168.1.10:10022 root@192.168.10.87
```

输入 **RTServer 密码**。

输入密码后窗口通常保持空白，这是 **正常现象**，表示隧道正在运行。该窗口：

- 不要输入其他命令；
- 不要关闭；
- 测试期间始终保持打开。

---

## 第二步：检查隧道是否成功

再新开 **第二个 PowerShell 窗口**，执行：

```powershell
Test-NetConnection 127.0.0.1 -Port 10023
```

正常结果应为：

```
TcpTestSucceeded : True
```

这说明本地 `10023` 端口已经通过 RTServer 转发到板子的 `10022` 端口。

---

## 第三步：登录板子

在第二个 PowerShell 窗口继续执行：

```powershell
ssh -p 10023 root@127.0.0.1
```

首次出现主机确认时输入：

```
yes
```

然后输入 **板子密码**。

> 虽然命令中写的是 `127.0.0.1`，最终登录的实际设备是 `192.168.1.10:10022`。

登录成功后执行：

```bash
hostname
uname -m
ip addr show eth1
```

重点确认：

```
uname -m：aarch64
eth1 地址：192.168.1.10
```

这就证明当前终端是 **控制器板子**，不是 OP5700。

---

## 第四步：保留当前 OP5700 窗口

已经登录的 OP5700 窗口继续保留，用于检查 RT-LAB Modbus 服务。

确认正式 V3.2 模型已经：

```
Load → Execute
```

然后在 OP5700 窗口执行：

```bash
ss -lntp | grep ':1502'
```

没有 `ss` 时使用：

```bash
netstat -lntp | grep ':1502'
```

必须看到 `1502` 处于 **`LISTEN`** 状态后，才能启动板端 V3.2 程序。

---

## 最终三个窗口

| 窗口 | 用途 |
|------|------|
| 窗口 1 | 空白，维持 SSH 隧道 |
| 窗口 2 | 登录控制器板子并运行 V3.2 程序 |
| 窗口 3（或现有窗口） | 登录 OP5700，检查 1502 和网络 |

> **先完成到板子登录成功即可，暂时不要启动 V3.2 程序。**
