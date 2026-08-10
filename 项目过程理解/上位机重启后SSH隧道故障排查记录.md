# SSH 隧道与 RT-LAB 故障排查记录

## 一、上午问题的本质

上午并不是"板子坏了"或"RT-LAB 坏了"，而是上位机重启后，原来用于登录板子的 **SSH 端口转发进程消失了**。

板子和上位机不在同一个可直接访问的网络中：

```text
上位机
192.168.10.x
    │
    │ SSH
    ▼
RTServer / OP5700
管理口：192.168.10.87
通信口：192.168.1.100
    │
    │ 内部直连网络
    ▼
控制器板子
192.168.1.10
SSH端口：10022
```

所以不能直接在 Windows 中执行：

```powershell
ssh root@192.168.1.10
```

必须把 RTServer 作为中间跳板，建立：

```text
Windows本地10023端口
→ RTServer
→ 板子10022端口
```

最终正确链路是：

```text
127.0.0.1:10023
→ 192.168.10.87:22
→ 192.168.1.10:10022
```

---

## 二、涉及的四个端口分别是什么

| 端口   | 所在设备      | 实际作用                    |
| ------ | ------------- | --------------------------- |
| 22     | RTServer      | Windows 登录 RTServer 使用   |
| 10022  | 控制器板子    | 板子的 SSH 服务实际监听端口   |
| 10023  | Windows 本机   | 我们人为建立的本地转发入口    |
| 1502   | RTServer      | RT-LAB 的 Modbus TCP Slave 端口 |

最容易混淆的是：

```text
10022 = 板子真实SSH端口
10023 = Windows本地临时转发端口
1502  = 板子程序访问RT-LAB的Modbus端口
```

它们功能完全不同。

---

## 三、为什么电脑重启后不能登录板子

电脑重启前，我们已经建立过 SSH 隧道。这个隧道由一个正在运行的 PowerShell/SSH 进程维持。

上位机重启后：

```text
PowerShell关闭
→ ssh进程结束
→ 127.0.0.1:10023转发消失
```

但是以下内容通常不会因此丢失：

- RT-LAB 工程；
- 已上传到板子的 V1、V2 程序；
- 板子文件系统中的配置文件；
- OP5700 的模型文件。

因此上午需要恢复的主要是：

```text
登录通道
```

而不是重新安装或重新上传所有内容。

---

## 四、第一步遇到的错误：密钥交换算法不匹配

最开始执行：

```powershell
ssh -L 10023:192.168.1.10:22 root@192.168.10.87
```

出现：

```text
no matching key exchange method found
```

RTServer 使用的是较旧的 SSH 服务，只支持：

```text
diffie-hellman-group14-sha1
diffie-hellman-group1-sha1
```

而 Windows 新版 OpenSSH 默认禁用了这些旧算法。

所以增加：

```powershell
-o KexAlgorithms=+diffie-hellman-group14-sha1
```

这一步解决的是：

```text
Windows和RTServer怎样协商会话密钥
```

它与板子和 Modbus 没有关系。

---

## 五、第二步遇到的错误：主机密钥算法不匹配

加入密钥交换算法后，又出现：

```text
no matching host key type found
Their offer: ssh-rsa,ssh-dss
```

说明 RTServer 只能提供较旧的：

```text
ssh-rsa
```

因此继续增加：

```powershell
-o HostKeyAlgorithms=+ssh-rsa
```

这一步解决的是：

```text
Windows如何确认RTServer的主机身份
```

---

## 六、第三步遇到的错误：MAC 算法不匹配

之后又出现：

```text
no matching MAC found
```

RTServer 提供：

```text
hmac-md5
hmac-sha1
……
```

所以继续增加：

```powershell
-o MACs=+hmac-sha1
```

最终 Windows 登录 RTServer 所需的兼容参数是：

```powershell
-o KexAlgorithms=+diffie-hellman-group14-sha1
-o HostKeyAlgorithms=+ssh-rsa
-o MACs=+hmac-sha1
```

完整含义是：

```text
允许旧密钥交换算法
+
允许旧RSA主机密钥
+
允许旧SHA1消息认证算法
```

这些参数只用于兼容老版本 RTServer SSH 服务。

---

## 七、为什么 10023 端口能连接，但登录板子仍然失败

建立旧隧道后，在第二个窗口执行：

```powershell
ssh -p 10023 root@127.0.0.1
```

出现：

```text
kex_exchange_identification: read: Connection reset
Connection reset by 127.0.0.1 port 10023
```

同时 RTServer 窗口出现：

```text
channel 3: open failed: connect failed: Connection refused
```

这两个信息结合起来的含义是：

```text
Windows → RTServer：已经成功
RTServer → 板子目标端口：被拒绝
```

也就是说：

- 本地 10023 已经有人监听；
- SSH 隧道已经建立；
- 连接已经到达 RTServer；
- 但是 RTServer 去连接板子的目标端口时失败了。

因此问题已经不在 Windows 和 RTServer 之间。

---

## 八、为什么先做 ping 测试

我们在 RTServer 执行：

```bash
ping -c 4 192.168.1.10
```

结果正常：

```text
4 packets transmitted
4 received
0% packet loss
```

这证明：

```text
板子已上电
板子IP仍为192.168.1.10
网线连接正常
RTServer与板子处于同一网络
```

因此可以排除：

- 板子断电；
- 网线松动；
- IP 地址错误；
- RTServer 通信口故障。

但是 ping 通只证明 IP 层正常，不代表 SSH 端口正常。

---

## 九、为什么检查 22 端口

接着执行：

```bash
nc -vz -w 3 192.168.1.10 22
```

结果：

```text
Connection refused
```

这表示：

```text
192.168.1.10确实存在
但22端口没有程序监听
```

"Connection refused"与"timeout"不同：

| 现象                     | 含义                        |
| ------------------------ | --------------------------- |
| `Connection refused`     | 目标设备在线，但目标端口未监听  |
| `Connection timed out`   | 网络、设备、路由或防火墙可能有问题 |
| `No route to host`       | 没有到目标地址的有效路径       |

因为板子能 ping 通且 22 端口拒绝，最初怀疑：

```text
板子SSH服务没有启动
```

所以进行了板子重启。

---

## 十、为什么板子重启后仍然不能登录

板子重启后：

```text
ping仍正常
22端口仍Connection refused
```

这说明问题不是一次性的 SSH 服务启动异常。

此时更合理的可能性变成：

```text
板子SSH根本不使用22端口
```

因此我们扫描了几个常见端口：

```bash
for p in 22 2222 10022 2022 10023; do
    echo "checking port $p"
    nc -vz -w 2 192.168.1.10 $p
done
```

结果：

```text
22      refused
2222    refused
10022   succeeded
2022    refused
10023   refused
```

由此确定：

```text
板子的SSH服务实际监听10022端口
```

不是 22 端口。

这才是上午不能登录板子的真正原因。

---

## 十一、原来的转发命令错在哪里

原来建立的是：

```text
Windows 10023
→ RTServer
→ 板子192.168.1.10:22
```

但板子 SSH 实际在：

```text
192.168.1.10:10022
```

所以每次连接时 RTServer 都会报：

```text
connect failed: Connection refused
```

正确的目标必须改为：

```text
192.168.1.10:10022
```

---

## 十二、最终正确的 SSH 隧道命令

专门开一个 PowerShell 窗口，执行：

```powershell
ssh -N `
-o KexAlgorithms=+diffie-hellman-group14-sha1 `
-o HostKeyAlgorithms=+ssh-rsa `
-o MACs=+hmac-sha1 `
-o ExitOnForwardFailure=yes `
-L 127.0.0.1:10023:192.168.1.10:10022 `
root@192.168.10.87
```

写成一行是：

```powershell
ssh -N -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o MACs=+hmac-sha1 -o ExitOnForwardFailure=yes -L 127.0.0.1:10023:192.168.1.10:10022 root@192.168.10.87
```

其中：

```text
-N
```

表示：

> 不进入 RTServer 命令行，只建立和维持端口转发。

因此输入密码后窗口可能变成空白，没有：

```text
[root@RTServer ~]#
```

这是正常状态，不是卡死。

**这个窗口必须保持打开。**

---

## 十三、为什么空白窗口输入命令没有反应

使用了 `-N` 以后，SSH 只负责转发，不给用户提供远程 Shell。

所以窗口表现为：

```text
没有提示符
输入命令没有执行结果
窗口一直停留
```

这恰恰说明它正在专门维持隧道。

不能在这个窗口执行：

```bash
ping
ss
netstat
cd
```

也不能关闭它。

需要操作 RTServer 时，应另外开一个普通登录窗口。

---

## 十四、如何单独登录 RTServer 进行检查

新开一个 PowerShell，执行：

```powershell
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o MACs=+hmac-sha1 root@192.168.10.87
```

这条命令没有 `-N` 和 `-L`，所以登录成功后会出现：

```text
[root@RTServer ~]#
```

这个窗口用于：

```bash
ping -c 4 192.168.1.10
nc -vz -w 3 192.168.1.10 10022
ss -lntp | grep ':1502'
```

但不要在这个窗口再次执行 Windows 建立隧道的完整命令。

---

## 十五、为什么在 RTServer 内部执行兼容命令会报错

上午曾在 `[root@RTServer ~]#` 后输入：

```bash
ssh -o KexAlgorithms=...
```

结果：

```text
Bad configuration option: KexAlgorithms
```

原因是：

- 这条命令本来应该在 Windows PowerShell 中执行；
- RTServer 自身的 SSH 客户端版本更旧；
- 它不认识现代 OpenSSH 的 `KexAlgorithms` 配置项；
- 而且当时我们已经登录 RTServer，不需要再次 SSH 到自身。

判断当前在哪个环境，主要看提示符：

```text
PS C:\Users\...>
```

表示 Windows PowerShell。

```text
[root@RTServer ~]#
```

表示已经进入 RTServer。

板子登录后则应通过以下命令确认身份：

```bash
hostname
uname -m
ip addr show eth1
```

---

## 十六、第二个窗口如何登录板子

隧道建立后，再开一个 PowerShell 窗口：

```powershell
ssh -p 10023 root@127.0.0.1
```

实际连接过程是：

```text
ssh连接127.0.0.1:10023
→ Windows SSH隧道接收
→ RTServer转发
→ 板子192.168.1.10:10022
```

虽然命令中写的是 `127.0.0.1`，但最终登录的是控制器板子。

登录后确认：

```bash
hostname
uname -m
ip addr show eth1
```

应重点看到：

```text
aarch64
192.168.1.10
```

---

## 十七、RT-LAB 和 SSH 登录是什么关系

这两条链路彼此独立。

### SSH 管理链路

用于：

```text
登录板子
上传程序
修改配置文件
启动V2/V3.1程序
看板子日志
```

链路为：

```text
Windows
→ RTServer SSH隧道
→ 板子10022
```

### Modbus 控制链路

用于：

```text
板子读取RT-LAB测量值
板子写入控制指令
```

链路为：

```text
板子192.168.1.10
→ RTServer 192.168.1.100:1502
```

所以：

- 能登录板子，不代表 1502 已经启动；
- 1502 已经启动，不代表 SSH 隧道存在；
- RT-LAB Execute 主要影响 Modbus 1502；
- PowerShell 重启主要影响 SSH 隧道。

---

## 十八、以后电脑重启后的标准恢复流程

### 第 1 步：启动 RT-LAB

完成：

```text
Build
→ Load
→ Execute
```

如果模型和配置没有改动，通常不必每次 Build，可以：

```text
Load
→ Execute
```

但当前正在测试新版本，按实际需要 Build。

Execute 后，Modbus Slave 的 1502 端口才会正式启动。

---

### 第 2 步：建立 SSH 隧道

窗口 1：

```powershell
ssh -N -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o MACs=+hmac-sha1 -o ExitOnForwardFailure=yes -L 127.0.0.1:10023:192.168.1.10:10022 root@192.168.10.87
```

输入 RTServer 密码后，窗口保持空白是正常的。

---

### 第 3 步：测试本地转发端口

窗口 2：

```powershell
Test-NetConnection 127.0.0.1 -Port 10023
```

应看到：

```text
TcpTestSucceeded : True
```

---

### 第 4 步：登录板子

窗口 2 继续执行：

```powershell
ssh -p 10023 root@127.0.0.1
```

登录后确认：

```bash
uname -m
ip addr show eth1
```

---

### 第 5 步：确认 RT-LAB Modbus 端口

另开窗口 3，普通登录 RTServer：

```powershell
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o MACs=+hmac-sha1 root@192.168.10.87
```

进入后：

```bash
ss -lntp | grep ':1502'
```

应看到监听状态。

---

### 第 6 步：启动板子程序

在板子窗口中进入相应版本目录：

```bash
cd /userdata/home/Microgrid/modbus_v3_1
```

检查旧进程：

```bash
ps -ef | grep modbus_tcp_master_test | grep -v grep
```

确保同一时间只有一个版本运行。

然后启动 V3.1。

---

## 十九、以后遇到问题时的判断方法

### 情况 1：本地 10023 直接 Connection refused

```text
ssh: connect to host 127.0.0.1 port 10023: Connection refused
```

说明：

```text
隧道窗口没有启动
或者隧道窗口已经关闭
```

重新建立窗口 1 隧道。

---

### 情况 2：本地 10023 Connection reset

同时隧道窗口显示：

```text
channel open failed: connect failed: Connection refused
```

说明：

```text
Windows到RTServer正常
但RTServer连接板子的目标端口失败
```

检查：

```bash
ping 192.168.1.10
nc -vz 192.168.1.10 10022
```

---

### 情况 3：ping 不通板子

说明重点检查：

```text
板子是否上电
网线是否松动
板子IP是否变化
RTServer的192.168.1.100网口是否正常
```

---

### 情况 4：ping 通，但 10022 拒绝

说明：

```text
板子SSH服务没有监听10022
或者端口再次变化
```

检查常用端口或让工程师检查板子 SSH 服务。

---

### 情况 5：出现 no matching key exchange

说明：

```text
SSH版本算法不兼容
```

在 Windows 到 RTServer 命令中加入：

```powershell
-o KexAlgorithms=+diffie-hellman-group14-sha1
```

---

### 情况 6：出现 no matching host key

加入：

```powershell
-o HostKeyAlgorithms=+ssh-rsa
```

---

### 情况 7：出现 no matching MAC

加入：

```powershell
-o MACs=+hmac-sha1
```

---

### 情况 8：隧道窗口空白

只要使用了 `-N`，空白就是正常状态，表示：

```text
隧道正在运行
```

不要在其中输入命令或关闭窗口。

---

## 二十、上午问题的最终结论

上午实际经历了两个独立问题。

### 问题一：RTServer 的 SSH 协议过旧

通过增加 `KexAlgorithms`、`HostKeyAlgorithms`、`MACs` 解决。

### 问题二：误把板子 SSH 目标端口写成 22

通过端口检测发现板子 SSH 实际端口 = **10022**。

将转发目标从 `192.168.1.10:22` 改为 `192.168.1.10:10022` 解决。

### 最终正确连接结构

```
窗口1：
维持Windows 10023 → 板子10022的SSH隧道

窗口2：
通过127.0.0.1:10023登录板子

窗口3：
需要时单独登录RTServer检查网络和1502端口
```

下次上位机重启后，只需要告诉我：

> 上位机已经重启，需要恢复板子登录。RTServer 是 192.168.10.87，板子是 192.168.1.10，板子 SSH 端口 10022，本地转发端口 10023。

我就应直接按照上述正确链路指导，不再从 22 端口开始排查。
