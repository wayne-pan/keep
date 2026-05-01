# gold_answers.py — Gold answer key points for objective benchmark scoring
#
# Each test has "key_points": facts a correct answer MUST contain.
# Scoring = sum of weights for matched key points (max 10.0).
# This replaces the old pattern-matching scorer that measured output format
# rather than factual correctness.

import re
from typing import Optional

# ── Gold Answer Definitions ──

GOLD_ANSWERS: dict[str, dict] = {
    # ── Comprehension ──
    "codebase-map": {
        "key_points": [
            # Must mention all 4 core modules
            {
                "id": "hooks_mod",
                "weight": 1.5,
                "patterns": [
                    r"\bhooks?\b.{0,30}(execut|run|trigger|lifecycle|event|安全|钩子|执行|触发)"
                ],
            },
            {
                "id": "rules_mod",
                "weight": 1.5,
                "patterns": [
                    r"\brules?\b.{0,30}(load|inject|context|auto|session|规则|加载|注入|上下文)"
                ],
            },
            {
                "id": "scripts_mod",
                "weight": 1.0,
                "patterns": [
                    r"\bscripts?\b.{0,30}(install|setup|deploy|bootstrap|安装|部署|脚本)"
                ],
            },
            {
                "id": "skills_mod",
                "weight": 1.5,
                "patterns": [
                    r"\bskills?\b.{0,30}(on.?demand|activat|trigger|invok|load|技能|按需|激活|调用)"
                ],
            },
            # Must explain inter-module connections
            {
                "id": "hooks_settings",
                "weight": 1.5,
                "patterns": [
                    r"(hooks?.{0,60}(settings?|config|注册|配置|定义|声明))",
                    r"(settings?.{0,60}(hooks?|钩子|注册))",
                    r"(hook|钩子).{0,40}(register|注册|声明|declare|entry|条目)",
                ],
            },
            {
                "id": "install_deploys",
                "weight": 1.5,
                "patterns": [
                    r"(install.{0,60}(deploy|hook|setup|配置|部署|安装|脚本))",
                    r"(deploy.{0,60}(install|setup|安装|部署))",
                    r"(scripts?.{0,40}(install|setup|hook))",
                ],
            },
            {
                "id": "tiered_arch",
                "weight": 1.5,
                "patterns": [
                    r"(tier|layer|progressive|分层|层级|渐进|always.*on.?demand|始终.*按需)"
                ],
            },
        ],
    },
    "code-structure": {
        "key_points": [
            # Must identify main functions in install.sh
            {
                "id": "usage_func",
                "weight": 1.0,
                "patterns": [
                    r"(usage|help|帮助|用法).{0,20}(function|func|def|函数|显示|show|打印|print)"
                ],
            },
            {
                "id": "install_func",
                "weight": 1.5,
                "patterns": [
                    r"(install_mx|install.{0,10}mx|install.{0,10}claude|安装)"
                ],
            },
            {
                "id": "configure_func",
                "weight": 1.5,
                "patterns": [r"(configure|config|setup|env|环境变量|配置)"],
            },
            {
                "id": "phases",
                "weight": 1.5,
                "patterns": [
                    r"(phase|阶段|step|步骤).{0,30}(1|2|3|4|depend|claude|harness|plugin|系统|配置|安装)"
                ],
            },
            {
                "id": "line_refs",
                "weight": 1.5,
                "patterns": [
                    r"(line\s?\d+|:\d+|L\d+|第\d+行|\|\s*\d+\s*\|)",
                    r"行\s*\d+",
                ],
            },
            {
                "id": "copy_rules_func",
                "weight": 1.5,
                "patterns": [
                    r"(copy|deplo|sync|部署|复制|同步|cp\s).{0,20}(rules?|hooks?|skills?|规则|钩子|技能|\.sh)",
                    r"(rules?|hooks?|skills?|Rules|Skills|Hooks).{0,30}(部署|deplo|复制|cop|sync)",
                ],
            },
            {
                "id": "main_entry",
                "weight": 1.5,
                "patterns": [
                    r"(main|entry.?point|入口|主函数|主逻辑|top.?level|顶层|脚本.{0,10}(开始|主体|执行|入口))",
                    r"(整体|线性|脚本.{0,10}(结构|流程|执行|运行)|4.{0,5}阶段|script.{0,10}(structure|flow|execution))",
                ],
            },
        ],
    },
    "cross-file-trace": {
        "key_points": [
            # Must trace the complete chain
            {
                "id": "settings_source",
                "weight": 2.0,
                "patterns": [r"(settings\.json|settings\.local).{0,60}(hook|钩子)"],
            },
            {
                "id": "install_hook_setup",
                "weight": 2.0,
                "patterns": [
                    r"(install\.sh|install).{0,40}(hook|settings|钩子|注册|配置|写入)"
                ],
            },
            {
                "id": "hook_files",
                "weight": 2.0,
                "patterns": [
                    r"(hooks?/[\w-]+\.sh|safety.?guard|auto.?format|protect.?files|sync.?learning)"
                ],
            },
            {
                "id": "lifecycle_event",
                "weight": 1.5,
                "patterns": [
                    r"(PreToolUse|PostToolUse|SessionStart|Stop|UserPromptSubmit|生命周期|事件|触发)"
                ],
            },
            {
                "id": "execution_flow",
                "weight": 1.5,
                "patterns": [
                    r"(execute|invok|trigger|run|执行|调用|触发).{0,30}(hook|script|钩子|脚本)"
                ],
            },
            {
                "id": "line_numbers",
                "weight": 1.0,
                "patterns": [r"(line\s?\d+|:\d+|L\d+|第\d+行)"],
            },
        ],
    },
    # ── Debugging ──
    "error-diagnosis": {
        "key_points": [
            # Must correctly identify the error
            {
                "id": "error_type",
                "weight": 2.0,
                "patterns": [
                    r"(no such file|not found|文件不存在|找不到|不存在的文件|没有这个文件)"
                ],
            },
            {
                "id": "error_command",
                "weight": 1.5,
                "patterns": [
                    r"\bcat\b",
                    r"(command|命令).{0,30}(cat|read|读取|执行|运行)",
                ],
            },
            {
                "id": "reason_path",
                "weight": 2.0,
                "patterns": [
                    r"(path|目录|路径|file|文件).{0,60}(does not exist|not exist|不存在|不存在|没有|missing)",
                    r"(no such file|not found).{0,30}(path|dir|目录|路径|file|文件)",
                ],
            },
            {
                "id": "action_suggestion",
                "weight": 2.0,
                "patterns": [
                    r"(create|touch|mkdir|check|verify|first|创建|检查|先|确认|确保|verify).{0,30}(file|文件|exist|存在)"
                ],
            },
            {
                "id": "exit_code",
                "weight": 1.5,
                "patterns": [
                    r"(exit.{0,5}code|return.{0,5}code|退出码|返回码|exit.{0,5}1)"
                ],
            },
            {
                "id": "nonexistent_path",
                "weight": 1.0,
                "patterns": [r"(nonexistent|不存在|随机|random|临时|临时文件|tmp)"],
            },
        ],
    },
    "bug-review": {
        "key_points": [
            # Must find real issues in safety-guard.sh
            {
                "id": "heredoc_issue",
                "weight": 1.5,
                "patterns": [
                    r"(heredoc|here.?doc|<<)",
                    r"(正则|regex|pattern|匹配).{0,30}(缺陷|问题|bug|issue|error)",
                ],
            },
            {
                "id": "pattern_gaps",
                "weight": 1.5,
                "patterns": [
                    r"(pattern|模式|匹配).{0,30}(miss|bypass|绕过|漏|不全|gaps?|不完整|never.{0,10}match|无法匹配|不能匹配|fails?.{0,10}match)",
                    r"(overly.{0,10}broad|过于宽泛|false.{0,5}positive|误报|substring.{0,20}match)",
                ],
            },
            {
                "id": "input_validation",
                "weight": 1.5,
                "patterns": [
                    r"(input.{0,20}valid|参数.{0,20}验证|unvalidated|未验证|空.{0,20}检查|null.{0,20}check)",
                    r"(inject|注入|option.{0,20}inject|echo.{0,20}inject|command.{0,20}construct|拼接|构造)",
                ],
            },
            {
                "id": "false_positive",
                "weight": 1.5,
                "patterns": [
                    r"(false.{0,5}positive|误报|误判|overly.{0,10}broad|过于宽泛|harmless.{0,10}block)"
                ],
            },
            {
                "id": "exit_code_check",
                "weight": 1.0,
                "patterns": [
                    r"(exit.{0,5}code|退出码|返回值|\$\\?).{0,30}(check|未检查|not.{0,10}check)"
                ],
            },
            {
                "id": "specific_line",
                "weight": 1.5,
                "patterns": [r"(safety.?guard|safety_guard).{0,10}(line|:|L|第)\d+"],
            },
            {
                "id": "fix_suggestion",
                "weight": 1.5,
                "patterns": [
                    r"(fix|repair|修改|修复|建议|replace|replace|添加|改进).{0,60}(具体|specific|code|代码|`[^`]+`)",
                    r"(fix.{0,5}:|修复[：:]).{0,100}`[^`]+`",
                    r"(fix|修复).{0,100}(改为|change.{0,10}to|replace.{0,10}with)",
                ],
            },
        ],
    },
    # ── Design ──
    "feature-plan": {
        "key_points": [
            # Must cover dry-run implementation
            {
                "id": "dry_run_flag",
                "weight": 1.5,
                "patterns": [r"(dry.?run|--dry|dryrun|模拟|预览|dry.?run)"],
            },
            {
                "id": "files_to_change",
                "weight": 1.5,
                "patterns": [
                    r"(install\.sh|scripts/install).{0,80}(change|modify|修改|编辑)",
                    r"(修改|编辑|change|modify).{0,80}(install\.sh|scripts/install)",
                ],
            },
            {
                "id": "approach",
                "weight": 1.5,
                "patterns": [
                    r"(echo|print|log|输出|打印).{0,30}(instead|而不|replace|替代|without.{0,10}actual)",
                    r"(跳过|skip|不执行|不运行|dry.?run|模拟执行|不实际|conditional.{0,20}exec)",
                ],
            },
            {
                "id": "edge_cases",
                "weight": 1.5,
                "patterns": [
                    r"(edge.{0,5}case|边界|corner|特殊|异常|existing|existing.{0,10}config)"
                ],
            },
            {
                "id": "verification",
                "weight": 1.5,
                "patterns": [r"(test|verify|验证|测试|check|检查|smoke|冒烟)"],
            },
            {
                "id": "rollback",
                "weight": 1.0,
                "patterns": [r"(rollback|revert|回滚|恢复|undo|backup|备份)"],
            },
            {
                "id": "user_experience",
                "weight": 1.5,
                "patterns": [
                    r"(user|用户|output|输出|diff|对比|preview|预览|what.{0,10}(would|will))"
                ],
            },
        ],
    },
    "multi-file-design": {
        "key_points": [
            # Must cover all integration points
            {
                "id": "hook_file",
                "weight": 2.0,
                "patterns": [
                    r"(hook|钩子).{0,20}(file|script|文件|脚本).{0,30}(TODO|FIXME|todo|fixme|comment|注释)"
                ],
            },
            {
                "id": "settings_registration",
                "weight": 2.0,
                "patterns": [
                    r"(settings\.json|settings).{0,40}(register|hook|PreCommit|注册|配置|钩子)"
                ],
            },
            {
                "id": "install_integration",
                "weight": 1.5,
                "patterns": [
                    r"(install\.sh|install).{0,30}(hook|cop|deplo|部署|复制|安装)"
                ],
            },
            {
                "id": "git_integration",
                "weight": 1.0,
                "patterns": [
                    r"(git.{0,20}(diff|staged|commit|add)|PreCommit|pre-commit|提交前)"
                ],
            },
            {
                "id": "test_plan",
                "weight": 1.5,
                "patterns": [
                    r"(test|测试|verify|验证).{0,40}(plan|方案|case|用例|scenario|场景)"
                ],
            },
            {
                "id": "todo_pattern",
                "weight": 1.0,
                "patterns": [
                    r"(grep|rg|search|搜索|find|查找).{0,30}(TODO|FIXME|todo|fixme)"
                ],
            },
            {
                "id": "exit_behavior",
                "weight": 1.0,
                "patterns": [r"(exit|block|阻止|exit.{0,5}1|warning|警告|warn|报告)"],
            },
        ],
    },
    # ── Safety ──
    "risk-assess": {
        "key_points": [
            # Must actually read the install script and hooks
            {
                "id": "script_content",
                "weight": 1.5,
                "patterns": [
                    r"(install\.sh).{0,60}(function|phase|deploy|copy|write|安装|部署|复制)",
                    r"(install\.sh).{0,30}(line|:|L)\d+",
                    r"(line|:)\s*\d+.{0,30}(cat\s*>|cp\s|overwrite|Full overwrite)",
                ],
            },
            # Must identify what gets overwritten (settings, hooks, rules)
            {
                "id": "overwrite_risk",
                "weight": 2.0,
                "patterns": [
                    r"(overwrite|覆盖|replace|替换|existing|已有|现有的|重写).{0,60}(settings|hook|rule|config|配置|规则|钩子)",
                    r"(settings|hook|rule|config|配置|规则|钩子).{0,60}(overwrite|覆盖|replace|替换|重写)",
                ],
            },
            # Must analyze hook safety (what the hooks actually do/block)
            {
                "id": "hook_analysis",
                "weight": 1.5,
                "patterns": [
                    r"(safety.?guard|auto.?format|protect.?files|sync.?learn|todo.?check)",
                    r"(hook|钩子).{0,40}(block|拦截|prevent|阻止|安全|guard|protect|扫描|scan)",
                    r"(hook|钩子).{0,40}(cop|复制|install|安装|deploy|部署).{0,40}(safety|guard|protect|format|安全|保护)",
                ],
            },
            # Must mention backup or verification before running
            {
                "id": "backup_verify",
                "weight": 1.5,
                "patterns": [
                    r"(backup|备份|verify|验证|check|检查|snapshot|快照).{0,20}(before|前|existing|现有|first|先)"
                ],
            },
            # Must identify specific files affected
            {
                "id": "affected_paths",
                "weight": 1.5,
                "patterns": [
                    r"(\.claude/(settings|rules|hooks|env)|~/.claude)",
                    r"(CLAUDE\.md|env|settings\.json)",
                ],
            },
            # Must assess severity of potential damage
            {
                "id": "severity_assess",
                "weight": 1.0,
                "patterns": [
                    r"(severity|严重|high.{0,5}risk|danger|风险.{0,10}(高|critical|重要))"
                ],
            },
            {
                "id": "safer_approach",
                "weight": 1.0,
                "patterns": [
                    r"(dry.?run|--dry|sandbox|测试环境|先.{0,10}(测试|验证)|backup.{0,20}first|备份)"
                ],
            },
        ],
    },
    "security-audit": {
        "key_points": [
            # Must identify security vulnerability categories
            {
                "id": "command_injection",
                "weight": 2.0,
                "patterns": [
                    r"(command.{0,10}inject|命令.{0,10}注入|inject|注入|shell.{0,10}inject)"
                ],
            },
            {
                "id": "path_traversal",
                "weight": 1.5,
                "patterns": [
                    r"(path.{0,10}traversal|路径.{0,10}(遍历|穿越)|\.\./|\.\.\\/|directory.{0,10}traversal)",
                    r"(file.{0,20}path|文件.{0,20}路径|目录.{0,20}(穿越|逃逸|跳出|遍历))",
                ],
            },
            {
                "id": "input_validation",
                "weight": 1.5,
                "patterns": [
                    r"(input.{0,10}valid|输入.{0,10}(验证|校验)|unvalidated|sanitiz|未验证|未校验)"
                ],
            },
            {
                "id": "privilege_escalation",
                "weight": 1.0,
                "patterns": [
                    r"(privilege.{0,10}escalat|权限.{0,10}(提升|升级)|sudo|elevation|提权)"
                ],
            },
            {
                "id": "specific_files",
                "weight": 1.5,
                "patterns": [
                    r"(safety.?guard|auto.?format|protect.?files|sync.?learning|session.?stop)"
                ],
            },
            {
                "id": "specific_lines",
                "weight": 1.5,
                "patterns": [r"(line\s?\d+|:\d+|L\d+|第\d+行)"],
            },
            {
                "id": "fix_per_finding",
                "weight": 1.0,
                "patterns": [
                    r"(fix|修复|解决|patch|建议|recommend).{0,40}(具体|specific|code|代码|`[^`]+`|replace)"
                ],
            },
        ],
    },
    # ── Workflow ──
    "implementation-plan": {
        "key_points": [
            # Must have concrete implementation details
            {
                "id": "specific_lines",
                "weight": 2.0,
                "patterns": [r"(line\s?\d+|:\d+|L\d+|第\d+行)"],
            },
            {
                "id": "flag_parsing",
                "weight": 1.5,
                "patterns": [r"(arg|参数|flag|选项|parse|解析|getopt|getopts|\$@|\$1)"],
            },
            {
                "id": "error_messages",
                "weight": 1.0,
                "patterns": [
                    r"(error.{0,20}message|错误.{0,20}(信息|提示)|stderr|usage|help|用法|提示)"
                ],
            },
            {
                "id": "edge_cases",
                "weight": 1.5,
                "patterns": [
                    r"(edge.{0,5}case|边界|corner|特殊|异常|invalid|无效|unknown|未知|extra|多余)"
                ],
            },
            {
                "id": "test_approach",
                "weight": 2.0,
                "patterns": [
                    r"(test|测试|verify|验证|check|检查).{0,40}(case|用例|approach|方案|method|方法|step|步骤)"
                ],
            },
            {
                "id": "rollback_strategy",
                "weight": 1.0,
                "patterns": [
                    r"(rollback|revert|回滚|恢复|undo|backup|备份|git.{0,10}(restore|checkout))"
                ],
            },
            {
                "id": "no_modify",
                "weight": 1.0,
                "patterns": [
                    r"(do not.{0,10}modify|不要.{0,10}(修改|改动)|no.{0,10}changes|plan.{0,20}only|仅.{0,10}计划)",
                    r"(不.{0,10}(修改|改动|变更|编辑)|实现.{0,20}计划|implementation.{0,20}plan)",
                ],
            },
        ],
    },
    # ── Skill-based ──
    "code-review": {
        "key_points": [
            # Must cover multiple issue categories
            {
                "id": "multi_category",
                "weight": 2.0,
                "patterns": [
                    r"(bug|logic|error|缺陷|逻辑|错误).{0,50}(secur|inject|xss|安全|注入|绕过)",
                    r"(secur|inject|安全|注入|绕过).{0,50}(bug|logic|error|缺陷|逻辑|错误)",
                    r"(bug|缺陷|错误).{0,50}(quality|style|perform|质量|风格|性能)",
                    r"(Security|Bug|Code Quality|安全性|代码质量).{0,20}(Issue|Finding|问题|发现)",
                ],
            },
            # Must have severity/confidence ratings
            {
                "id": "severity_rating",
                "weight": 1.5,
                "patterns": [
                    r"(severity|严重|critical|warning|high|medium|low).{0,30}(confidence|置信|certainty)",
                    r"(critical|warning|info|高|中|低).{0,5}(severity|严重)",
                    r"(高|中|低).{0,5}(置信|confidence)",
                    r"(confidence|置信度?).{0,20}(高|中|低|high|medium|low|\d+%)",
                    r"\[(critical|warning|info|high|medium|low).{0,20}\]",
                ],
            },
            # Must reference specific lines
            {
                "id": "line_references",
                "weight": 1.5,
                "patterns": [
                    r"(line\s?\d+|:\d+|L\d+|第\s*\d+)",
                    r"(行|line).{0,5}\d{1,3}",
                ],
            },
            # Must provide concrete fixes
            {
                "id": "concrete_fix",
                "weight": 1.5,
                "patterns": [
                    r"(fix|修复|replace|替换|change|改为|suggestion|建议).{0,40}(`[^`]+`|code|代码|specific|具体)"
                ],
            },
            # Evidence of multi-perspective review (subagents or parallel review)
            {
                "id": "subagent_evidence",
                "weight": 1.5,
                "patterns": [
                    r"(subagent|子代理|子审查|sub.?agent|parallel|并行|perspective|视角|cross.?validat|交叉验证|Bug.?Hunter|Security|审查代理)"
                ],
            },
            # Must find injection/path traversal risks
            {
                "id": "injection_finding",
                "weight": 1.0,
                "patterns": [
                    r"(inject|注入|path.{0,10}traversal|路径.{0,10}(遍历|穿越)|command.{0,10}inject|绕过|bypass)"
                ],
            },
            # Must have structured summary
            {
                "id": "summary_format",
                "weight": 1.0,
                "patterns": [
                    r"(Review.{0,10}Summary|审查.{0,10}摘要|findings?[:：]|发现[:：]|Summary)",
                    r"(审查.{0,10}(总结|摘要|结论)|总结[:：]|核心结论|综合.{0,5}(结果|报告|结论))",
                ],
            },
        ],
    },
    "sprint-plan": {
        "key_points": [
            # Must show research phase (read files, analyzed code flow)
            {
                "id": "research_phase",
                "weight": 2.0,
                "patterns": [
                    r"(research|研究|explore|探索|investigat|调查).{0,80}(file|code|代码|function|函数|hook|guard)",
                    r"(read|读取|analyz|分析|exam|发现|found).{0,40}(safety.?guard|hook|钩子|漏洞|vulnerab|inject)",
                    r"(目标|target).{0,30}(文件|file|hook).{0,40}(行|line|漏洞|vulnerab)",
                ],
            },
            # Must have specific line numbers and change ranges
            {
                "id": "specific_lines",
                "weight": 1.5,
                "patterns": [
                    r"(line\s?\d+|:\d+|L\d+|第\d+行|:\d{1,3})",
                    r"(第[一二三四五六七八九十\d]+行|位置|L\d{1,3})",
                ],
            },
            # Must propose validation approach
            {
                "id": "validation_approach",
                "weight": 1.5,
                "patterns": [
                    r"(whitelist|白名单|blacklist|黑名单|sanitiz|净化|escap|转义|validat|验证|regex|正则|pattern.{0,20}match)",
                    r"(printf.{0,20}%s|printf.{0,20}%q|grep.{0,10}-F|grep.{0,10}固定字符串|固定匹配)",
                ],
            },
            # Must have test plan (broadened to match actual agent output)
            {
                "id": "test_plan",
                "weight": 1.5,
                "patterns": [
                    r"(test|测试|verify|验证|check|检查).{0,60}(case|用例|scenario|场景|approach|方案|malicious|恶意|inject|注入|step|步骤)",
                    r"(测试.{0,30}(验证|确认|通过|覆盖|方法|策略))",
                    r"(实证|actual.{0,10}test|手动.{0,10}测试|manual.{0,10}test)",
                ],
            },
            # Must have rollback strategy
            {
                "id": "rollback",
                "weight": 1.0,
                "patterns": [
                    r"(rollback|revert|回滚|恢复|undo|backup|备份|git.{0,10}(restore|checkout))",
                    r"(git checkout|单文件|还原|恢复原状)",
                ],
            },
            # Must have concrete injection defense (broadened)
            {
                "id": "injection_defense",
                "weight": 1.5,
                "patterns": [
                    r"(`[^`]{10,}`|\$[\w_]+|\$\{)[^`]{0,100}(validat|sanitiz|escap|filter|check|验证|净化|转义|过滤)",
                    r"(shellquote|shlex|printf.{0,20}%q|双引号|single.?quote)",
                    r"(printf.{0,5}'%s'|printf.{0,5}\"%s\"|grep.{0,10}-F|固定字符串匹配|sanitiz|净化函数|strip|剥离)",
                ],
            },
            # Must have confidence assessment (broadened)
            {
                "id": "confidence_level",
                "weight": 1.0,
                "patterns": [
                    r"(confidence|置信|certainty|置信度).{0,30}(level|级别|assessment|评估|高|中|低|high|medium|low)",
                    r"(HIGH|MEDIUM|LOW).{0,5}(confidence|置信|certainty)",
                    r"(置信度|confidence).{0,10}[\d/%]",
                    r"(高|中|低).{0,5}(置信|confidence)",
                ],
            },
        ],
    },
}


# ── Gold-based Scorer ──


class GoldScorer:
    """Score test results by checking coverage of gold answer key points.

    Each key point has regex patterns (OR-matched) and a weight.
    Score = sum of weights for matched key points (max = sum of all weights = 10.0).
    """

    @staticmethod
    def _hit(patterns: list[str], text: str) -> bool:
        return any(re.search(p, text, re.IGNORECASE | re.DOTALL) for p in patterns)

    def score(self, result: str, test_name: str) -> float:
        gold = GOLD_ANSWERS.get(test_name)
        if not gold:
            return 0.0

        total = 0.0
        for kp in gold["key_points"]:
            if self._hit(kp["patterns"], result):
                total += kp["weight"]

        return round(total, 1)

    def score_detail(self, result: str, test_name: str) -> dict:
        """Return detailed scoring breakdown for debugging."""
        gold = GOLD_ANSWERS.get(test_name)
        if not gold:
            return {"total": 0.0, "hits": [], "misses": [], "dimensions": {}}

        hits, misses = [], []
        total = 0.0
        for kp in gold["key_points"]:
            if self._hit(kp["patterns"], result):
                total += kp["weight"]
                hits.append({"id": kp["id"], "weight": kp["weight"]})
            else:
                misses.append({"id": kp["id"], "weight": kp["weight"]})

        return {
            "total": round(total, 1),
            "hits": hits,
            "misses": misses,
            "dimensions": self._compute_dimensions(hits, gold),
        }

    @staticmethod
    def _compute_dimensions(hits: list, gold: dict) -> dict:
        """Map key points to 5 quality dimensions (agent-lightning inspired).

        Dimensions (each 0-2, total = quality score):
          completeness: covers all important aspects
          accuracy: specific claims (line refs, function names, file paths)
          safety: identifies risks, provides warnings
          efficiency: concise, no padding, appropriately scoped
          actionable: developer can act on it immediately
        """
        hit_ids = {h["id"] for h in hits}
        key_points = gold.get("key_points", [])
        total_weight = sum(kp["weight"] for kp in key_points)

        # Map key point IDs to dimensions
        dim_map = {
            "completeness": set(),
            "accuracy": set(),
            "safety": set(),
            "efficiency": set(),
            "actionable": set(),
        }
        for kp in key_points:
            kid = kp["id"]
            if kid in (
                "hooks_mod",
                "rules_mod",
                "scripts_mod",
                "skills_mod",
                "phases",
                "tiered_arch",
                "multi_category",
            ):
                dim_map["completeness"].add(kid)
            elif kid in (
                "line_refs",
                "line_numbers",
                "specific_line",
                "specific_lines",
                "line_references",
            ):
                dim_map["accuracy"].add(kid)
            elif kid in (
                "overwrite_risk",
                "hook_analysis",
                "severity_assess",
                "command_injection",
                "path_traversal",
                "input_validation",
                "privilege_escalation",
                "injection_finding",
                "injection_defense",
            ):
                dim_map["safety"].add(kid)
            elif kid in (
                "safer_approach",
                "rollback",
                "rollback_strategy",
                "no_modify",
            ):
                dim_map["efficiency"].add(kid)
            elif kid in (
                "fix_suggestion",
                "concrete_fix",
                "fix_per_finding",
                "action_suggestion",
                "test_plan",
                "test_approach",
                "validation_approach",
                "verification",
                "user_experience",
            ):
                dim_map["actionable"].add(kid)
            else:
                # Default unmapped to completeness
                dim_map["completeness"].add(kid)

        dims = {}
        for dim_name, dim_ids in dim_map.items():
            dim_total = sum(kp["weight"] for kp in key_points if kp["id"] in dim_ids)
            dim_hit = sum(
                kp["weight"]
                for kp in key_points
                if kp["id"] in dim_ids and kp["id"] in hit_ids
            )
            dims[dim_name] = round(dim_hit, 1) if dim_total > 0 else 0.0

        return dims
