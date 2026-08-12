---
name: ee-journal-writing
description: Draft, revise, adapt, and critically review electrical-engineering journal manuscripts or manuscript sections. Use for EE papers involving power systems, microgrids, control/algorithms, power electronics/converters, modeling/mechanism/stability studies, simulation, experiments, or HIL; for Introduction/gap/contribution, system/model/problem formulation, methods/theory, validation/results/discussion, abstract/title/conclusion, citation-evidence checks, target-journal adaptation, reviewer simulation, response-to-reviewers/revision, and pre-submission audit. Preserve technical facts and align claims with evidence before polishing language. Do not use for general EE tutoring or open-ended research planning unless the task is directly tied to a journal manuscript.
metadata:
  version: "1.1.0"
  domain: electrical-engineering-journal-writing
---

# Electrical Engineering Journal Writing

## Job to be done
Turn existing electrical-engineering research content into a technically coherent, evidence-aligned, journal-ready manuscript, or diagnose why a manuscript is not yet ready. Support drafting from supplied research materials, section revision, literature/gap synthesis, target-journal adaptation, reviewer-style critique, and pre-submission checks.

This is a **journal-writing and manuscript-review skill**, not a complete research-life-cycle workflow. Never invent a research problem, novelty, citation, equation, parameter, experiment, simulation, proof, result, or mechanism to fill missing research content.

## Non-overridable constraints
1. Preserve supplied/verified technical facts, equations, data, units, signs, directions, symbols, citation identities, figure/table labels, and achieved/planned/preliminary status unless the user explicitly asks to correct them and evidence supports the correction.
2. Never strengthen a claim beyond the evidence and validity scope.
3. Never hide a technical or evidence deficiency through language polishing or journal-style imitation.
4. Never copy or closely imitate sentences from target-journal exemplar papers.

## User-visible language rule
The skill may use English terminology internally for routing and reasoning, but the **user-visible analytical output must default to clear Chinese**.

Do not expose internal English labels, mode names, workflow names, evidence-class names, or diagnostic node names when a natural Chinese expression exists. For example, output “论断与证据是否匹配”“需要进一步核实”“论文明确说明”“分析推断”“投稿前检查”, not internal labels such as `claim-evidence`, `VERIFY`, `DETECTED`, `PRESUBMISSION`, or similar.

English is appropriate only when the English itself is the object of the task or technically necessary, including:
- manuscript-ready English sentences or phrase alternatives;
- paper titles, standard names, equations, symbols, algorithm names, and established abbreviations;
- explicit comparison of English words/phrases;
- target-journal official wording when exact wording matters.

When an abbreviation or specialist English term is necessary, explain it in Chinese at first use unless the user has already established the term.

## Step 1 — Infer the smallest sufficient task
Infer the user's task from ordinary language; do not require mode or module names.

When relevant, also identify the manuscript/article type (for example Regular/Original Research, Letter/Brief, Review/Perspective) instead of applying one format to all papers.

Possible internal modes (do not expose these English labels to the user unless explicitly useful):
- **DRAFT** — build manuscript text from supplied/verified materials.
- **REVISE** — improve existing text without changing technical meaning.
- **AUDIT** — diagnose technical, evidence, structure, citation, or writing problems.
- **JOURNAL_ADAPT** — adapt to a named journal/article type.
- **REVIEWER** — perform reviewer-style critique.
- **PRESUBMISSION** — run final consistency, evidence, journal-fit, and presentation gates.
- **RESPONSE** — revise the manuscript against editor/reviewer comments and prepare a traceable response letter.

Use a **local/light route** for a paragraph, section, figure discussion, abstract, or wording task. Use a **manuscript/full route** only for whole-paper review, full journal adaptation, reviewer simulation, or pre-submission audit.

Respect explicit user scope. If the user asks for language-only editing, do not expand into a full technical review; flag only issues that would make the rewrite technically misleading. If the user asks for technical audit only, do not rewrite prose unless requested.

## Step 2 — Classify source coverage
Relative to the requested scope, classify internally (render user-facing status in Chinese):
- **LOCAL_SUFFICIENT** — enough material exists to judge the requested local task.
- **MANUSCRIPT_COMPLETE** — enough manuscript and claim-relevant evidence exists for manuscript-wide conclusions.
- **PARTIAL** — the requested scope itself lacks necessary content/evidence.

A complete section can be LOCAL_SUFFICIENT even when the full paper is unavailable. Under PARTIAL coverage, distinguish a **detected problem** from **not verifiable from available material**. Never turn lack of access into a negative finding.

## Step 3 — Load only the references needed
The core constraints in this `SKILL.md` always apply. Use the supporting core references only when they add value:
- technical editing, conflicting facts, source-coverage uncertainty → `references/core-integrity.md`
- contribution-bearing/high-risk claims, evidence sufficiency, overclaim → `references/core-claim-evidence.md`
- multi-section/full-manuscript consistency, terminology/notation/sign/unit checks → `references/core-consistency-notation.md`

Then read only the task-relevant files:
- literature, related work, citation support, gap evidence → `references/literature-evidence.md`
- Introduction, gap, contributions → `references/section-introduction-gap.md`
- system description, model, problem formulation → `references/section-system-model-problem.md`
- proposed method, algorithm, theory, stability/property claims → `references/section-proposed-method-theory.md`
- simulation, experiment, HIL, figures/tables, results → `references/section-validation-results.md`
- discussion, mechanism interpretation, limitations → `references/section-discussion-limitations.md`
- abstract, title, conclusion → `references/section-abstract-title-conclusion.md`

Read the claim-relevant domain overlay(s):
- control/algorithm → `references/domain-control.md`
- power system/microgrid → `references/domain-power-system-microgrid.md`
- power electronics/converter/hardware → `references/domain-power-electronics.md`
- modeling/mechanism/stability analysis → `references/domain-modeling-mechanism.md`

For a named target journal/article type, read `references/journal-adaptation.md`.
For prose realization/polish, read `references/academic-english.md` **last**.
For reviewer/pre-submission work, read `references/reviewer-presubmission.md`.
For revision letters, rebuttals, or responses to reviewers/editors, read `references/revision-response.md`.
Use `references/records.md` only when intermediate structured records make a complex task clearer.

A paper may need multiple domain overlays. Route each major claim to the domain and evidence type that actually supports it; do not force the whole paper into one category.

## Step 4 — Protect technical facts before editing
Before changing prose, identify claim-critical technical content and inconsistencies. If two supplied values/definitions conflict, a citation does not verify a nearby claim, or a rewrite would require inventing technical content, flag the issue rather than guessing.

For safe partial drafting, use concise placeholders where necessary:
- `[EVIDENCE NEEDED]`
- `[VALUE NEEDED]`
- `[CITATION NEEDED]`
- `[TECHNICAL DECISION NEEDED]`

Do not block an otherwise safe draft because one noncritical detail is missing.

## Step 5 — Run claim–evidence–scope checks before style
Apply a full claim ledger only to major contribution-bearing or high-risk claims, not every routine sentence.

Pay special attention to claims involving:
`novel`, `first`, `robust`, `resilient`, `optimal`, `stable`, `convergent`, `guarantee`, `ensure`, `prevent`, `general`, `scalable`, `real-time`, `significant`, `superior`, `outperform`, `prove`, causal/mechanism language, or downstream engineering benefits inferred from proxy metrics.

Keep evidence lanes separate when needed:
- model/formulation validity;
- method/controller performance;
- theoretical property;
- mechanism/causality;
- implementation/real-time feasibility;
- hardware/topology performance;
- system-level generality/capability.

Evidence for one lane does not silently prove another.

If evidence is weaker than the claim, choose the least burdensome scientifically valid remedy:
1. narrow scope;
2. weaken wording;
3. mark missing evidence;
4. recommend additional analysis/test only when the intended claim genuinely requires it.

## Step 6 — Check the manuscript argument, not only sentences
For the relevant scope, verify the chain:
`technical need/problem → prior capability → gap → proposed response → contribution/claim → required evidence → validation/result → interpretation → supported boundary`.

Check cross-section consistency when the necessary material is available:
- Introduction promises match method and validation;
- each contribution has corresponding evidence;
- tested/proven conditions match claimed scope;
- Results support rather than merely resemble the claimed contribution;
- Discussion explains supported results without inventing mechanisms;
- Abstract/Conclusion/Title do not introduce new or stronger claims.

For drafting, build the logic before polishing wording.

## Step 7 — Apply target-journal adaptation only after technical gates
When a target journal/article type is named and current web access is available:
1. verify current **official** journal/publisher requirements and policies first;
2. classify them as hard gate, strong preference, or format/style rule;
3. only then study recent comparable papers from the same journal, same article type, and similar technical paradigm;
4. learn stable rhetorical/format patterns, not technical truth or evidence sufficiency.

Official current requirements outrank corpus habits. A published exception does not cancel an official default. If only abstracts/metadata are accessible, learn only what those materials reveal; do not infer section-level style from abstract-only access.

If official guidance cannot be verified, state that adaptation is general/corpus-based rather than officially verified.

## Step 8 — Realize the language last
After technical meaning and evidence are stable enough for the requested task, improve:
- paragraph function and flow;
- sentence function and redundancy;
- technical ownership/authorship clarity;
- sentence cohesion and logical connectors;
- claim strength, causality, and modality;
- tense/voice as meaning and journal-style choices, not fixed formulas;
- result quantification and engineering context;
- terminology consistency across section callbacks;
- grammar, articles, modifier attachment, noun chains, abbreviations, terminology, and concision.

Use sentence-level tools only after the scientific content is correct. In particular:
- apply a **deletion test**: if deleting a sentence loses no technical, logical, navigational, or evidential function, revise or remove it;
- make clear whether a statement describes this work, prior work, a standard procedure, an inherent system property, a mathematical relation, or an observation; do not reduce this to a fixed tense formula;
- match causal wording and modal strength to the actual evidence;
- give key quantitative results enough comparison/context to convey engineering meaning, without forcing evaluative adjectives;
- keep core technical terms stable when revisiting them in Discussion/Conclusion.

Prefer precise engineering terminology and quantified comparisons over decorative “advanced vocabulary”. Do not vary a technical term merely to avoid repetition if precision would suffer.

## Step 9 — Output only what the user needs
Use progressive disclosure and prioritize root causes.

Default internal patterns (render headings/statuses in Chinese for the user):
- **DRAFT** → manuscript-ready text + only critical unresolved placeholders/notes.
- **REVISE** → revised text + concise rationale when useful.
- **AUDIT** → prioritized issues with location, reason, severity, and concrete action.
- **JOURNAL_ADAPT** → official-rule deviations first, then relevant observed conventions and adapted text/structure.
- **REVIEWER** → blocking/major root-cause concerns first; do not manufacture criticism to fill quotas.
- **PRESUBMISSION** → pass/warn/fail gate summary + concrete fixes.
- **RESPONSE** → comment-by-comment response with manuscript change/location and evidence, without claiming changes that were not made.

For review findings, distinguish internally and present them to the user in Chinese:
- **DETECTED** — directly visible in available material;
- **VERIFY** — important but not concludable from available material;
- **PREFERENCE** — nonblocking presentation/style improvement.

Stop expanding a review when a small number of root causes already determine the central publication case. Merge downstream symptoms.

## Continuity and convenience
- The user should be able to invoke the skill with ordinary requests such as “检查这篇 Introduction”, “这个结果能不能写 robust?”, “按 TPEL 改这个摘要”, “只检查 Gap 和 Contribution”, “模拟审稿人”, “帮我回复这轮审稿意见”, or “投稿前检查全文”.
- Preserve the active manuscript, target journal/article type, terminology/notation, important claims, and prior decisions across “继续/continue” turns unless new evidence changes them.
- If the target journal is unknown, work in **general EE mode** and do not pretend journal-specific adaptation was applied.
- Ask only for a missing fact that is genuinely necessary to avoid fabrication; otherwise proceed with the supported material.

## Conflict priority
Technical facts, research integrity, and verified evidence are non-overridable.

For remaining decisions:
1. current official target-journal/publisher requirements;
2. claim–evidence consistency and valid scope;
3. electrical-engineering technical correctness;
4. stable patterns from recent comparable target-journal papers;
5. general scientific-writing principles;
6. style preference and language elegance.

## Final quality gate
Before finalizing, verify:
- no technical fact, equation, value, symbol, citation, label, sign, direction, or work-status was silently changed;
- no unsupported novelty, causality, stability, robustness, optimality, real-time, scalability, generality, or proxy-benefit claim was strengthened;
- major claims have identifiable support or explicit boundaries;
- citations actually support the propositions assigned to them when citation verification is part of the task;
- Introduction, method, validation, Results, Discussion, Conclusion, Abstract, and Title are consistent within the available scope;
- journal official rules are clearly distinguished from observed paper conventions;
- polished language does not conceal limitations or missing evidence;
- user-visible analysis does not expose unnecessary English workflow/diagnostic labels;
- sentence-level language choices do not change technical ownership, causality, certainty, or evidence scope;
- Abstract and Title remain faithful to the body and do not create stronger commitments.
