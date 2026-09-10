**Builtin read 的 token 优化复测（2026-09-10）**

版本说明：本文数据来自报告中记录的冻结二进制与资源。提交 PR 时已同步后续主分支改动，但没有重跑模型评测；这些数据不代表同步后版本的性能测量。

精简后的读取提示在本轮减少了累计 input 和 output tokens，核心内容与代码正确率保持一致。此处 A、B 都使用 builtin read：A 是上一轮冻结的原版 builtin 提示，B 是当前精简版；不是与 native read 的新对照。样本仍是 3 类任务、每版每类 3 次，共 18 次真实模型运行。

先纠正评测：此前 fixture 位于主仓库的子目录且没有独立 Git 根，部分 `git status` / `git diff` 会读到主仓库的修改，污染上下文。原 [read 对照报告](read_workflow_ab_20260910.md) 已加勘误；首次 token 优化尝试在发现此问题后中止，11 次完成结果和 1 次中断记录保留在 `.moonagent/eval_runs/read_workflow_tokens_20260910`，全部排除出本报告。本轮 18 次全部重新运行，没有复用或筛选旧结果。

每个 fixture 现在都建立独立 Git 仓库并提交初始文件，禁用继承的 Git 全局/系统配置，校验 `git rev-parse --show-toplevel` 等于 fixture 本身。预检在脏的父仓库下修改一个文件，确认 diff 仅含该文件。运行完成后，再次核对了全部 18 个 Git 根。模型、high thinking、24 步/240 秒上限、交替 AB/BA 的串行次序、文件内容及 oracle 均与原套件一致；没有 API 重试、超时或步数耗尽。

产品修改集中在 [默认读取提示](../../prompt/default_prompt.mbt.md) 和 [mbtx 的工具说明](../../agent_tool/mbtx/mbtx.mbt)，并更新生成的 prompt。把重复的参数说明集中到工具说明中；预算详情通过 `--help` 按需获取；主提示要求直接批量读取已知文件、利用返回的空/缺失文件状态、仅为未知路径列目录，并仅在内容缺失、截断或改变时重读。行号、截断状态、literal 参数、资源不可用时的替代路径仍保留。没有改动 workflow 源码、输出格式、限制或执行器。

filename-only 调用只向模型接口发送文件名和参数；脚本源码在本地加载执行。因此编译变快本身不会直接减少模型 tokens，读取提示与后续模型回合才是这里的优化对象。

| 指标（每版 9 次） | A：原版 builtin 提示 | B：精简版 builtin 提示 | 变化 |
| --- | ---: | ---: | ---: |
| 累计 input tokens | 2,048,752 | 1,702,957 | -16.9% |
| 累计 output tokens（含 reasoning） | 39,144 | 34,407 | -12.1% |
| Cache-hit input | 1,954,176 | 1,607,936 | -17.7% |
| Cache-miss input | 94,576 | 95,021 | +0.5% |
| 模型步骤 | 71 | 61 | -14.1% |
| 全部 tool 调用 | 78 | 64 | -17.9% |
| Named read 调用 | 15 | 15 | 0 |
| Tool 错误（含预期不存在文件） | 18 | 12 | -6 |
| 核心内容 / 代码正确 | 9/9 | 9/9 | 相同 |
| 严格通过 | 3/9 | 4/9 | +1 |
| 最终修改范围正确 | 9/9 | 9/9 | 相同 |
| 总耗时均值 | 34.31 s | 33.46 s | -2.5% |
| 纯读取批次中位耗时 | 565 ms | 564 ms | 基本相同 |

首请求在全部 9 对中都恰好减少 **344 input tokens**。结合原 native→builtin 首请求曾增加 396 的测量，固定新增量约从 396 缩到 52；这项算术比较不代表已经重新完成 native read 的端到端对照。实际 named read 调用数两版都是 15，减少的是辅助工具工作和模型回合，并非本轮所有任务都少读了文件。

本轮 input 总共减少 345,795。按 `累计 input = 步数 × 首请求 input + 后续上下文` 拆分：固定提示项减少 20,984；步数项减少 234,116；后续上下文项减少 90,695。固定项使用 B 的步数、步数项使用 A 的首请求作为基准。这是账目拆分，不是各条 prompt 指令的因果贡献；减少回合比压缩几百个固定 tokens 的量级大。

Cache miss 只从 94,576 变到 95,021，基本持平。大量减少的 input 是重复发送且已缓存的上下文；不能把 16.9% 的累计 input 降幅直接当作账单降幅。Output 减少 12.1%，但这里不套用价格，也不估计货币节省。服务端缓存和采样未受控。

任务细分揭示了波动：

| 任务（各 3 次） | A input | B input | Input 变化 | A / B 步数 | A / B 核心正确 |
| --- | ---: | ---: | ---: | --- | --- |
| 六文件批量提取 | 141,879 | 163,697 | +15.4% | 6 / 7 | 3/3 / 3/3 |
| 大文件指定行 + 文件状态 | 499,591 | 377,541 | -24.4% | 19 / 15 | 3/3 / 3/3 |
| 三文件分页库修复 | 1,407,282 | 1,161,719 | -17.4% | 46 / 39 | 3/3 / 3/3 |

简单批量任务反而多了一步，所以并非每类任务都节省；收益主要来自复杂读取与修复。六次修复全部在原始 manifest/测试的独立副本中通过 5 组测试、24 个断言；所有最终文件变化均符合任务范围。严格分的未通过全部是正确 JSON 之外附加了解释。核心正确指标允许从最终答案开头或 JSON fence 中提取对象逐字段核对；不把这个宽松指标当成完整任务遵从率。

完整逐对结果：

| 任务 / 次数 | A input | B input | A output | B output | A / B 步数 |
| --- | ---: | ---: | ---: | ---: | --- |
| batch-1 | 47,352 | 46,570 | 683 | 679 | 2 / 2 |
| ranges-1 | 191,901 | 156,609 | 4,163 | 2,868 | 7 / 6 |
| repair-1 | 479,570 | 274,115 | 8,004 | 5,613 | 16 / 10 |
| batch-2 | 47,273 | 70,566 | 738 | 868 | 2 / 3 |
| ranges-2 | 181,980 | 97,869 | 3,319 | 2,138 | 7 / 4 |
| repair-2 | 454,203 | 365,233 | 8,765 | 10,379 | 15 / 12 |
| batch-3 | 47,254 | 46,561 | 475 | 372 | 2 / 2 |
| ranges-3 | 125,710 | 123,063 | 2,659 | 1,882 | 5 / 5 |
| repair-3 | 473,509 | 522,371 | 10,338 | 9,608 | 15 / 17 |

这是观察过同一套 fixture 后的单模型、小样本后续实验，具有样本内调优的局限，不证明其他任务普遍节省同样比例。测试期间产品源码、二进制、提示词保持冻结；预检及全部完成结果都保留。

验证：`just check`、`just test`（3250 native + 3228 JS、24 cram 和 3 个离线 CLI 集成案例）及 `just build` 全部通过；评测额外验证了 Git 边界、18 对应的最终文件范围、每对 fixture 内容相同及六次修复 oracle。

材料与复现：

- [机器可读结果](read_workflow_tokens_20260910.json)：18 次答案、token、调用、错误、fixture 哈希和评分。
- [运行器](../prompt_task/read_workflow_ab.py) 与 [报告分析器](../prompt_task/read_workflow_ab_report.py)。
- 原始目录：`/Users/dii/.codex/worktrees/ef2c/openseek/.moonagent/eval_runs/read_workflow_tokens_isolated_20260910`。包含 frozen binaries/share、源码副本、相对 HEAD 的统一 diff、manifest/plan/evaluator、逐次事件和 durable session、调用参数及 oracle 日志。
- 请求模型：`deepseek-v4-flash`；Moon 0.1.20260904，moonc v0.10.12+1634b282e。
- A binary SHA-256：`cd6b3068b1c4d87a87f55a2f2bdbd5f9481f6786d0797db54a5626b48cb628dd`。
- B binary SHA-256：`df3916ff2d2d3e6bed8b20824b1785b71a265caf711cd308a0556f2f5b743ff2`。
- Evaluator SHA-256：`b2682a5454b1d31502cdc53176662a12bcc10e797cfb0393b434ad911c7cc65d`。

```bash
python3 eval/prompt_task/read_workflow_ab.py \
  --baseline .moonagent/eval_runs/read_workflow_tokens_isolated_20260910/bin/baseline \
  --candidate .moonagent/eval_runs/read_workflow_tokens_isolated_20260910/bin/candidate \
  --baseline-share .moonagent/eval_runs/read_workflow_tokens_isolated_20260910/baseline-share \
  --candidate-share .moonagent/eval_runs/read_workflow_tokens_isolated_20260910/candidate-share \
  --out .moonagent/eval_runs/read_workflow_tokens_isolated_20260910
python3 eval/prompt_task/read_workflow_ab_report.py \
  .moonagent/eval_runs/read_workflow_tokens_isolated_20260910 \
  eval/prompt_reports/read_workflow_tokens_20260910.json
```

使用原目录会复用已完成结果；完整重跑需指定新 `--out`。`--prepare-only` 可仅运行 Git 隔离和 oracle 预检，不调用模型。
