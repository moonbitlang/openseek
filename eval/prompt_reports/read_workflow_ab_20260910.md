**read tool → builtin workflow：A/B pilot（2026-09-10）**

版本说明：本文数据来自报告中记录的冻结二进制与资源。提交 PR 时已同步后续主分支改动，但没有重跑模型评测；这些数据不代表同步后版本的性能测量。

**后续勘误：** token 优化复测发现，当时 fixture 虽有独立文件夹，却没有独立 Git 仓库。部分修复运行的 `git status` / `git diff` 读到了父项目的修改，带入无关上下文。因此下方综合 token / 耗时数据保留为原始记录，不能用于归因读取方案的开销；内容正确性及实际读取调用仍可从记录核验。运行器现已修复隔离并加入预检。新的 [token 对照报告](read_workflow_tokens_20260910.md) 使用独立 Git 仓库。归档中的 `evaluator.py` 保留原运行器，当前运行器会因配置哈希变化而拒绝续跑旧目录。

这一轮支持 builtin workflow 能承接读文件及后续编辑，但没有显示整体性能优势。18 次真实模型运行全部完成，内容提取和独立代码测试全部正确；新版减少了 tool 调用，读取本身变慢，整体平均耗时接近，累计 input tokens 增加。这里只是单模型、3 类合成任务的小样本实验。

旧版 A 为干净的 `62a4fb8994122c85e4037c1951c733247671e30d`；新版 B 为该提交加当前未提交的 read workflow 迁移，包括去掉 read 注册、更新默认 prompt、增加 builtin script 及 sandbox 输出识别修复。分别冻结 native debug 可执行文件及对应 share 资源，未在实验中修改产品代码或提示词。旧版独立 checkout 在构建后仍保持干净。

统一请求模型 `deepseek-v4-flash`，high thinking，24 步上限，每次 240 秒；同一 MoonBit 工具链，MCP 关闭，用户全局 skills 关闭，默认系统提示词分别来自各自二进制。两边均保留其他工具，用户任务不指定必须使用哪个读取工具。凭据仅继承环境变量，没有写入命令或报告。

每类任务每个版本重复 3 次，共 9 对、18 次，顺序固定交替 AB/BA，串行运行。每对使用内容哈希完全相同的独立文件夹；读取样本的值随重复编号变化，代码修复样本保持一致。没有剔除、重试或择优挑选 trial；API 内部重试实际发生 0 次，无超时或步数耗尽。没有模型 seed 控制。

- **批量提取**：6 个文件，JSON、普通文本、空格路径、中文，以及含 `Sandbox policy blocked file write`、`@process.spawn(): Permission denied`、`Operation not permitted` 的源码注释。
- **指定行与边界情况**：约 85 KB / 208 KB 的两个文件，指定行、中文和 emoji，另检查空文件、不存在的文件，以及字面文件名 `notes:2026`。这个任务也测试文件状态检查，会涉及额外脚本。
- **三文件修复**：分页边界、向上取整和元素切片，包含 Int 溢出。独立 oracle 在保留原始 manifest/测试的副本中验证提交的实现：每次 5 组测试、24 个断言（含原始 smoke）。原始实现通过 smoke、在 4 组 oracle 中失败，参考实现全部通过。

原始预设评分保留为“严格通过”：读取结果必须是精确 JSON 对象（允许仅包裹 Markdown fence，额外解释不通过）；修复必须通过 oracle；两类均要求正常结束且最终文件变化在许可范围内。看到第一对输出都有额外解释后，另加统一的事后“核心正确”指标：从最终答案开头或 JSON fence 内提取对象并逐字段比对；修复仍以独立 oracle 为准。后者不代表满足全部格式或文件范围要求，不能拿 9/9 充当严格任务通过率。

以下是全部 9 次/版本的汇总；token 为逐响应 usage 的累计值，包含重复上下文和 cache hits。

| 指标 | A：read tool | B：builtin workflow |
| --- | ---: | ---: |
| 核心内容 / 代码正确 | 9/9 | 9/9 |
| 严格通过 | 1/9 | 3/9 |
| 最终文件范围符合要求 | 7/9 | 8/9 |
| 总耗时均值 | 37.63 s | 38.15 s |
| 总耗时中位数 | 19.64 s | 32.09 s |
| 全部 tool 调用数 | 115 | 79 |
| 模型步骤数 | 72 | 79 |
| 专用读取调用数 | 54 read | 17 named mbtx |
| tool 错误数（含预期不存在文件） | 10 | 13 |
| Input tokens | 2,121,746 | 2,330,152 |
| Output tokens（含模型 reasoning） | 42,740 | 38,215 |
| Cache-hit input tokens | 2,021,632 | 2,208,640 |
| Cache-miss input tokens | 100,114 | 121,512 |
| 纯读取批次耗时中位数 | 5 ms（11 批） | 545 ms（10 批） |

新版总 tool 调用减少 31.3%，平均总耗时增加 1.4%，累计 input tokens 增加 9.8%，output tokens 减少 10.6%。每对首次请求 input 都恰好多 396 tokens，约 +1.7%；当前新增的读取说明抵消了移除 read schema 的节省。

纯读取批次耗时来自 durable session 的 assistant/tool-result 时间戳，排除同一轮混有其他工具的批次；它包含分发、脚本启动/执行和记录开销，不含模型生成，也不是单文件 IO 基准。新版约半秒的固定开销很稳定。模型总耗时包含整个 agent 过程，独立 oracle 的运行时间不计入。

按任务看，整体均值接近掩盖了方向不同的变化：

| 任务（各 3 次） | A / B 核心正确 | A / B 严格通过 | A 耗时中位数 | B 耗时中位数 |
| --- | --- | --- | ---: | ---: |
| 批量提取 | 3/3 / 3/3 | 0/3 / 1/3 | 5.73 s | 5.78 s |
| 指定行与边界情况 | 3/3 / 3/3 | 0/3 / 0/3 | 19.64 s | 32.09 s |
| 三文件修复 | 3/3 / 3/3 | 1/3 / 2/3 | 92.23 s | 66.13 s |

新版 9/9 次都实际调用了 `@builtin/read.mbtx`，没有调用已移除的 `read`。三个批量任务均用一次 named workflow 读完 6 个文件，旧版均批量发出 6 次 read（同一模型步骤，并非 6 次模型往返）。新版第三次随后又写脚本验证 JSON，导致该次总耗时从其他重复的约 5 秒升到 26.91 秒；减少读取调用不会自动减少后续模型步骤。

六次修复全部通过独立 oracle；新版使用实际 builtin 输出中的行号和原文调用 `multi_edit`/`edit`，没有发现读取与编辑状态衔接故障。三次 scope 失败来自额外格式化测试/manifest 或留下 `pkg.generated.mbti`：A 的 repair-1、repair-2，B 的 repair-1。模板起始文件没有全部采用 moon fmt 的规范格式，这会诱发额外格式整理，因此不能把这些 scope 失败当作读取差异。其余严格失败均为正确 JSON 旁添加了说明。评分检查最终文件状态，未将创建后删除的临时文件记为 scope 失败。

新版 17 次 builtin 调用中有 3 次返回错误，均可从参数解释：ranges-1 忘记在 `notes:2026` 前放 `--literal`，因此试图读 `notes` 的第 2026 行；随后正确重试。ranges-2 故意批量读了不存在的 `absent.txt`，这是预期错误，后续文件仍返回。repair-2 额外猜测并读取了不存在的 `src/main.mbt`，同批正确文件仍返回。没有 builtin 编译错误、工具参数解码错误或 sandbox 字样误判。其他错误来自模型自行编写的辅助脚本（A 7 次编译错误、1 次 runtime 错误；B 10 次编译错误），以及 A 的一次 edit anchor 错误和一次 remove 所有权限制。

含 sandbox 报错字样的 3 个新版读取结果全部为成功；这验证的是本轮样本中的输出分类，没有关闭或绕过实际 sandbox。这几个 builtin 读取样本中的源码文字，没有被误当作写入拒绝。

实际调用示例（batch-3-candidate，省略 description）：

```json
{
  "filename": "@builtin/read.mbtx",
  "args": [
    "config/release.json",
    "docs/owner.txt",
    "config/retry.json",
    "build/artifact.txt",
    "docs/region name.txt",
    "src/diagnostic.mbt"
  ]
}
```

每对原始结果如下；核心正确均为是，严格通过保留单独列。

| 任务 / 重复 | A 秒 | B 秒 | A / B 步数 | A / B 严格通过 |
| --- | ---: | ---: | --- | --- |
| batch-1 | 5.731 | 5.780 | 2 / 2 | 否 / 否 |
| ranges-1 | 33.857 | 54.124 | 6 / 9 | 否 / 否 |
| repair-1 | 92.227 | 66.127 | 17 / 18 | 否 / 否 |
| batch-2 | 4.305 | 4.505 | 2 / 2 | 否 / 是 |
| ranges-2 | 17.193 | 12.769 | 6 / 3 | 否 / 否 |
| repair-2 | 107.932 | 102.518 | 22 / 19 | 否 / 是 |
| batch-3 | 6.093 | 26.909 | 2 / 6 | 否 / 否 |
| ranges-3 | 19.638 | 32.086 | 5 / 10 | 否 / 否 |
| repair-3 | 51.678 | 38.575 | 10 / 10 | 是 / 是 |

这个样本支持继续使用 builtin 方案验证产品体验，不能证明删除 read 后模型总体更高效，也不能证明任意任务上的功能等价。后续优化优先考虑 named workflow 的编译/启动缓存、精简重复的读取提示，以及避免为已知文件额外探测/重写读取脚本；优化后应作为新变体重新实验。这里没有根据中途结果调整任何产品实现。

局限：单一请求模型名、服务端采样不可控、每类仅 3 次、没有大仓库长会话或多模型覆盖；运行次序交替但并非随机，provider cache 无法强制同等预热，所以不估算货币成本。所有统计是描述性的，没有显著性或普遍优势结论。当前任务混合中位数也不能取代各任务的耗时分布。

复现与材料：

- [运行器](../prompt_task/read_workflow_ab.py)：准备 fixture/oracle，冻结配置哈希，执行和续跑。
- [报告分析器](../prompt_task/read_workflow_ab_report.py)：保留原始严格评分，添加统一的事后内容评分，校验每对 fixture 哈希。
- [完整机器可读结果](read_workflow_ab_20260910.json)：18 次的指标、答案、错误、读取参数和 fixture 哈希。
- 本机原始目录：`/Users/dii/.codex/worktrees/ef2c/openseek/.moonagent/eval_runs/read_workflow_ab_20260910`。包含 frozen binaries/share、candidate patch/untracked snapshots、evaluator.py、plan.json、manifest.json、每次 events.jsonl、durable sessions、calls.json、prompt、workspace 和 oracle.log；此目录被 git 忽略。
- 工具链：moon 0.1.20260904 (94521db)，moonc v0.10.12+1634b282e (2026-09-07)，moonrun 0.1.20260904。运行器使用 POSIX process groups 处理超时。

```bash
python3 eval/prompt_task/read_workflow_ab.py \
  --baseline .moonagent/eval_runs/read_workflow_ab_20260910/bin/baseline \
  --candidate .moonagent/eval_runs/read_workflow_ab_20260910/bin/candidate \
  --baseline-share .moonagent/eval_runs/read_workflow_ab_20260910/baseline-share \
  --candidate-share .moonagent/eval_runs/read_workflow_ab_20260910/candidate-share \
  --out .moonagent/eval_runs/read_workflow_ab_20260910
python3 eval/prompt_task/read_workflow_ab_report.py \
  .moonagent/eval_runs/read_workflow_ab_20260910 \
  eval/prompt_reports/read_workflow_ab_20260910.json
```

原目录续跑会复用已经完成的结果，不会重新付费调用。要完整重跑，用一个新的 `--out` 目录；用 `--prepare-only` 可只验证 fixture 和 oracle。

冻结的 SHA-256：

- A binary：`69fdcc93c960e9e1d8b8600c1614b33e46a5e21981c6d2d4065a841e5c29a6f9`
- B binary：`cd6b3068b1c4d87a87f55a2f2bdbd5f9481f6786d0797db54a5626b48cb628dd`
- B tracked patch：`b742ea3440dc10e66ab9332cb36f39c89d796f07206610f8eca71c12799ff43d`
- Evaluator：`cf3888a13e7f78e4f598ae53b10abb7341f950acc32d87c5d84bd36fbb66d858`
