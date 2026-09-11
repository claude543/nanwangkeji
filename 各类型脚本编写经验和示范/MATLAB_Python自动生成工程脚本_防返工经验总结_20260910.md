# MATLAB / Python 自动生成工程脚本的编写问题与防返工经验｜2026-09-10

> 来源：S8（低压/低频减载）三参数 Tunable（在线可调）改模后的独立 Verifier（静态验证器）出现  
> `字符向量未正常终止`  
> 的 MATLAB 解析错误。  
> 这份文件不是只记录“第488行怎么修”，而是把以后所有 MATLAB / Python 自动生成脚本应该遵守的固定规则整理下来。

---

# 1. 本次问题是什么

运行：

```matlab
BOARD15_S8_TUNABLE_VERIFY_R1
```

MATLAB报：

```text
文件: BOARD15_S8_TUNABLE_VERIFY_R1.m
行: 488
列: 9
字符向量未正常终止
```

定位发现，Verifier里有两处本来应该写成：

```matlab
fprintf('\n--- 11. Non-mutating final sanity ... ---\n');
```

的代码，被实际写成：

```matlab
fprintf('
--- 11. Non-mutating final sanity ... ---
');
```

后面还有另一处同类 `fprintf` 字符串。

MATLAB单引号 `'...'` 表示 character vector（字符向量）。

这种字符向量不能在没有合法续行/构造的情况下直接跨真实物理行，所以MATLAB在**解析源文件阶段**就失败。

---

# 2. 真正根因不是MATLAB，而是“用Python生成MATLAB源码时转义层次搞错”

这次 Verifier 是由 Python 自动拼接/修改已有 `.m` 文件生成的。

如果 Python 普通字符串中写：

```python
"fprintf('\nhello\n');"
```

Python会先把：

```text
\n
```

解释成真正的换行字符。

于是最终写到 `.m` 文件中的不是：

```matlab
fprintf('\nhello\n');
```

而是：

```matlab
fprintf('
hello
');
```

MATLAB就会报“字符向量未正常终止”。

所以以后必须始终区分两层语言：

```text
第一层：Python字符串语法
第二层：最终希望写进MATLAB文件里的字符
```

如果最终 MATLAB 里希望保留两个字符：

```text
\ 和 n
```

Python生成器通常应该写：

```python
"\\n"
```

或者直接使用 Python raw string（原始字符串）：

```python
r"fprintf('\nhello\n');"
```

---

# 3. 最大教训：不能只修MATLAB报出来的第一行

MATLAB只报告了：

`第488行`

但实际全文件有**两处**同类问题。

如果按以前最容易返工的方式：

```text
看到488行
→ 只改488行
→ 再运行
→ 下面第二处又报错
→ 再改一次
```

就会重复浪费现场时间。

以后固定规则：

> **任何“字符串未终止、括号未配对、语法解析错误”，都先把它当成“生成器可能在全文件重复犯了同一类错误”，必须一次扫描完整文件。**

本次R2就是这样处理：

1. 定位第一处；
2. 搜索全文件所有 `fprintf('...`；
3. 扫描所有可能跨物理行的单引号字符向量；
4. 找出第二处；
5. 两处一次修完；
6. 再做全文件静态扫描确认0残留。

---

# 4. 以后所有自动生成 `.m` 文件的固定语法检查

在没有 MATLAB runtime（MATLAB运行环境）的机器上，至少要做下面这些。

## 4.1 单引号字符向量跨行扫描

目标：

> 发现某个 `'` 开始了字符向量，但在同一真实物理行没有正常闭合。

尤其检查：

- `fprintf('...')`
- `error('...')`
- `sprintf('...')`
- `set_param(...,'Value','...')`
- 手工拼接的长错误信息。

注意 MATLAB 的 `'` 还可能是转置符，所以扫描器不能简单数“奇偶个单引号”，需要区分：

```matlab
x'
```

与：

```matlab
'text'
```

## 4.2 所有 `fprintf` 首字符串必须同物理行闭合

对每一行：

```text
fprintf('
```

确认这一行内存在合法闭合 `'`。

如果没有：

直接判静态语法风险。

## 4.3 函数名必须和文件名一致

例如：

文件：

`BOARD15_S8_TUNABLE_VERIFY_R2.m`

第一行必须：

```matlab
function BOARD15_S8_TUNABLE_VERIFY_R2
```

不能出现：

```text
文件R2
函数仍叫R1
```

否则MATLAB调用和追溯都会混乱。

## 4.4 关键表项必须计数

对于类似 Runtime Config 规格表，不能只检查“新参数名字存在”。

必须程序化检查：

```text
总数是不是31
40234是否且仅出现1次
40235是否且仅出现1次
40236是否且仅出现1次
```

这样可以防：

- 漏插一行；
- 重复插入；
- 插入到了错误的规格函数。

---

# 5. “脚本语法通过”和“模型逻辑通过”必须严格分层

以后固定四层：

```text
Layer 1
源代码文本/语法静态检查
↓
Layer 2
Patch自身preflight + post-assert
↓
Layer 3
独立Verifier静态模型结构检查
↓
Layer 4
RT-LAB Rebuild + post-Load Target write/readback/restore
```

不能跨层。

例如本次：

`Verifier R1字符向量未终止`

发生在 Layer 1。

这时根本还没有进入：

`Verifier模型结构逻辑`

更没有进入：

`RT-LAB Build`

所以不能因为这个错误去怀疑：

- 40234接错；
- 168点坏了；
- Board程序坏了；
- S8执行器坏了。

---

# 6. 如何判断“需不需要重新跑Patch”

这是现场非常重要的经验。

本次顺序是：

```text
Patch R1
→ 已经 PASS / SAVED ONCE
→ 再运行 Verifier R1
→ Verifier在MATLAB解析阶段报语法错误
```

因为 Verifier 根本没有执行，所以：

> **已经成功保存的Patch结果不需要因为Verifier语法错误而重新Patch。**

正确动作：

```text
保持当前Patch后的模型
→ 修Verifier
→ 运行新的Verifier R2
```

不要：

```text
重新跑Patch
恢复PRE备份
再改一次模型
```

否则反而可能制造重复修改或partial structure（半成品结构）。

以后判断规则：

### Verifier解析错误

如果 Patch 已经明确：

`PASS / SAVED ONCE`

则：

`只修Verifier，不重跑Patch。`

### Patch自己在解析阶段失败

Patch完全没开始执行：

`模型没有被这个Patch改动。`

### Patch运行到一半发生结构HARD FAIL

必须看Patch有没有：

- 成功前不save；
- catch后reload磁盘基线；
- PRE完整备份。

如果这些安全合同都存在，就先确认日志，不要人工猜测模型当前状态。

---

# 7. 为什么Patch必须“成功终点只保存一次”

结构改模脚本统一遵守：

```text
完整preflight
↓
完整备份
↓
修改
↓
完整post-assert
↓
全部PASS
↓
save_system一次
```

不能：

```text
改一点
→ save
→ 再改一点
→ save
```

原因：

如果后半段失败，磁盘里已经留下半成品。

本项目后续继续要求：

> **结构Patch的主流程 `save_system(mdl)` 成功调用只能在最终终点出现一次。**

---

# 8. 为什么Verifier必须独立于Patch

Patch里的post-assert很重要，但不能只有：

`修改代码自己检查自己。`

所以固定：

```text
Patch：
负责修改 + 自身post-assert

Independent Verifier：
重新从已保存模型读取结构
→ 用另一套代码独立核对
```

这样可以防：

> Patch里“写错了，同时自己的判断也写错了”，最后仍然自报PASS。

---

# 9. 不能为了“验证”调用不适合当前平台的普通Simulink Update

此前项目已经踩过这个坑。

当前 OPAL-RT / ARTEMiS 模型存在：

- Selector；
- masked library；
- RT-LAB Build阶段才能正确处理的一些结构。

普通host-side：

```matlab
set_param(mdl,'SimulationCommand','update')
```

可能因为**与本次Patch无关的原模型路径**报错。

因此当前工程规则：

```text
Patch：
不拿普通host update当最终编译判据

Static Verifier：
也不调用普通host update

真正的可编译性：
由 RT-LAB Rebuild All 判断
```

这能避免“本次改模其实没问题，却被另一个既有Selector问题误判失败”。

---

# 10. Target Verify必须继续使用“真实可逆写入”，不能只看参数表

模型里出现：

`B15_UV_THRESHOLD_PU`

并不等于：

`RT-LAB运行时真的可以在线改。`

所以 Build 之后必须：

```text
Reset
→ Load
→ DO NOT Execute
→ Board STOPPED
→ GetParametersDescription
→ 找唯一Target path
→ 写probe
→ readback
→ restore
→ restore readback
```

只有这样才叫：

`Target Tunable PASS`

本次S8前置探针正是靠这种方法确认：

- 已知B15_TIE_TARGET_KW确实能写；
- S8三项确实NOT_EXPOSED。

因此才有充分证据决定改模。

---

# 11. Target Verify的恢复逻辑要比以前更强

以前最基本的写法：

```python
write(probe)
read()
write(original)
read()
```

有一个风险：

```text
probe写成功
↓
第一次read异常
↓
程序抛出异常
↓
restore还没执行
```

所以以后每一个参数都用独立：

```python
try:
    write probe
    read probe
finally:
    restore original
    read restore
```

只要曾经成功写过probe，就优先恢复。

这条规则现在已经写进：

`BOARD15_S8_TARGET_VERIFY_R1.py`

---

# 12. 所有绑定失败应该一次性收集，而不是“报一个停一个”

旧式写法：

```text
参数A找不到
→ 立即raise
→ 修A
→ 下一次运行才发现B也找不到
```

这是典型返工模式。

以后应该：

```text
先扫描全部31项
↓
收集所有missing / duplicate / ambiguous
↓
任何写操作前
生成统一诊断JSON
↓
一次告诉用户全部真实失败项
```

动态信号绑定也一样：

- exact suffix（精确后缀）；
- hits；
- near candidates；
- semantic label；

一次性收齐。

---

# 13. 不要自动选择“看起来最像”的近似路径

例如本次S8探针能够看到：

```text
CFG_AA_uv_threshold_pu
CFG_AA_uf_threshold_Hz
CFG_AA_load_shed_step_kW
```

但它们是 LOCAL15 参数。

BOARD15 需要的是：

```text
B15_UV_THRESHOLD_PU
B15_UF_THRESHOLD_HZ
B15_LOAD_SHED_STEP_KW
```

如果脚本因为名字相似就自动选择：

`CFG_AA_*`

虽然可能“能写”，却会把两个控制体系混在一起。

所以：

```text
exact path唯一命中 → 才写
near candidate      → 只做诊断，不自动选择
```

这个原则必须长期保留。

---

# 14. 每次修正版都要保留版本和Diff

本次：

```text
R1：失败原件
R2：修正版
02_R1_R2_DIFF.txt：改动差异
03_R2_STATIC_AUDIT.txt：静态审计
```

以后不要直接覆盖掉失败文件。

原因：

- 可以知道到底修了什么；
- 可以判断是不是顺手改了不相关逻辑；
- 后续如果出现新问题能追溯。

---

# 15. 交付用户前的固定“脚本出厂检查表”

以后我生成任何正式 MATLAB/Python 工程脚本，至少逐项检查：

```text
[ ] 文件名与主函数名一致
[ ] 全文件字符串/引号扫描
[ ] 所有fprintf字符向量同物理行正常闭合
[ ] Python compile()语法检查
[ ] 关键规格表数量正确
[ ] 新增参数各且仅出现一次
[ ] 禁止参数没有误加入
[ ] 关键模型路径没有使用模糊猜测
[ ] Patch成功终点只save一次
[ ] Verifier不修改模型
[ ] 不误调用host-side update
[ ] Rebuild与Target Verify仍保留
[ ] Target probe每项都有try/finally restore
[ ] binding错误一次性收集
[ ] R1/R2 diff已生成
[ ] SHA256/ZIP CRC已检查
```

---

# 16. 对本项目后续S8/S5/S14/S15的直接应用

接下来任何结构脚本都继续使用同样流程：

```text
先读取当前真实基线
↓
明确只改哪些点
↓
记录保护对象
↓
备份
↓
最小修改
↓
全局post-assert
↓
一次保存
↓
独立Verifier
↓
RT-LAB Rebuild
↓
Load / DO NOT Execute
↓
Target唯一绑定 + 可逆写入
↓
才进入动态验收Runner
```

特别是后续孤岛专项涉及：

- Mode；
- PCC Breaker；
- Fref；
- GridOn/Droop；
- Black Start；
- Resynchronization；

结构风险远高于S8三参数。

所以更不能采用：

`报一个错 → 临时手改 → 再跑`

的方式。

---

# 17. 本次经验最后压缩成三句话

第一：

> **自动生成另一种语言的源码时，必须检查“生成语言”和“目标语言”两层转义；Python里的 `\n` 不一定等于你想写进MATLAB里的 `\n`。**

第二：

> **一旦发现语法类错误，不只修报错行，而是全文件扫描同类模式，一次清干净。**

第三：

> **脚本本身的语法、模型静态结构、RT-LAB编译、Target运行时可调性是四层不同证据，哪一层失败就只处理哪一层，不能无理由重跑前面已经PASS的结构改模。**
