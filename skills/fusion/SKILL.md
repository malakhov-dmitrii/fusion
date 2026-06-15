---
name: fusion
description: Multi-model consensus planner — Claude + Codex + DeepSeek independently draft a plan, cross-verify each other ("idiot-test"), and must reach consensus on material axes before any plan is emitted. Use when a non-trivial task needs a maximally hardened plan (research, alternatives, spikes, operator interview), not a quick answer. Output is a plan; implementation is out of scope (hand to forge/improve).
---

# fusion — многомодельный консенсус-планировщик

Claude + Codex + DeepSeek V4 Pro **независимо** планируют, кросс-верифицируют друг друга и **обязаны прийти к консенсусу** по material-осям, прежде чем выдать план. Тезис: ансамбль разных семейств обгоняет одну топ-модель, потому что у них разные слепые зоны.

Оркестратор — ты (Claude, главная сессия). Внешние модели зовутся через `skills/fusion/fusion.sh`. **Ты тоже участник** (draft + cross-verify), но **НЕ судья большинством**: консенсус считается механически по голосам, тай разбивает оператор.

## Когда использовать
Нетривиальная задача, где нужен проработанный план с перебором решений и проверкой допущений. **НЕ** для быстрых ответов и тривиальных правок — там это дорого и медленно (≥1 ч/задача, batch-инструмент).

## Инварианты (нарушать нельзя)
- **Жёсткий консенсус-гейт:** synthesize ТОЛЬКО когда все доступные агенты `reached` по material-осям (architecture · approach · key-assumptions). Большинство 2/3 НЕ перебивает несогласного.
- **`decision ∈ {consensus, operator_decision, blocked, degraded}`** — план после тай-брейка оператора = `operator_decision`, не `consensus`. Никогда не маркируй тай-брейк как консенсус.
- **Сырой бриф, не твой пересказ** — внешние модели не должны видеть «репо глазами Claude», иначе твои слепые зоны становятся общими.
- **<2 семейств доступно → `degraded`**, не выдавать за fusion.
- **write_leak=true в status.json → СТОП**, разобрать (модель мутировала target-репо).

## Параметры
`/fusion <task> --dir <target-repo> [--depth lite|full]`  (lite = 1 раунд, full = 2; по умолчанию full)

## Плейбук

Везде: `export FUSION_GUARD_REPO=<target> FUSION_SCRATCH=/tmp/fusion-$TS; RUN=<target>/.fusion/runs/$TS; SH=skills/fusion/fusion.sh`.

### 0. Setup
`bash "$SH" cleanup` — снос сирот-worktree + scratch. `mkdir -p $RUN`.

### 1. Brief (RAW)
Собери `$RUN/brief.md` из сырья: repo-tree (depth-cap), `git -C <target> rev-parse HEAD` + recent log, ADR/CONTEXT/README (cap), файлы задачи (grep/glob), intent-доки. Посчитай `coverage = included/candidates`: <50% → предупреди оператора; <20% → `BLOCKED: insufficient-context`. Никакой Claude-аннотации.

### 2. Round 1 — draft
Собери `$RUN/draft-prompt.txt` = brief + задача + **требование мульти-угла** (рассмотри: не решать / решить сильно проще / зависит от будущих планов / разные сценарии — первый вектор не всегда устойчив).
- Внешние: `bash "$SH" fan draft $RUN/draft-prompt.txt $RUN codex deepseek`.
- Claude: произведи свой draft сам → `$RUN/draft/claude.md`.
- Проверь `$RUN/status.json`: `write_leak=true` → СТОП; <2 участников `ok` → `degraded`.

### 3. Round 1 — cross-verify (ротация, никто не судит себя)
- `bash "$SH" cross-verify deepseek $RUN/draft/claude.md $RUN`   (DeepSeek → план Claude)
- `bash "$SH" cross-verify codex $RUN/draft/deepseek.md $RUN`    (Codex → план DeepSeek)
- Claude → план Codex: сам, по тому же контракту (оси correctness/completeness/assumptions/contradictions/missed-risks + `VERDICT:`-строка) → `$RUN/cross/claude-on-codex.md`.

### 4. Aggregate
`bash "$SH" collect $RUN` → `$RUN/aggregate.md`.

### 5. Round 2 (depth=full) — re-discuss + structured votes
`git -C <target> rev-parse HEAD` — drift-check: HEAD сдвинулся → переснять brief, отметить `drifted:true`.
Re-discuss-промпт: каждый видит весь `aggregate.md`, правит/склоняется к варианту/поднимает DISAGREE и **обязан закончить блоком голосов**:
```
VOTES:
architecture:    reached|split | material:true|false | position:<…> | evidence:<path|none> | would_accept_if:<…>
approach:        …
key-assumptions: …
```
`bash "$SH" fan rediscuss …` + Claude свой → cross-verify ещё раз (та же ротация).

### 6. Consensus-гейт (механически по VOTES)
- Для каждой material-оси (`material:true`): все доступные = `reached`? → ось сошлась.
- Material-ось `split` жива → есть спайкабельное допущение? `bash "$SH" spike "<hypothesis>" --max-files N --max-time S` → structured verdict (`confirmed|refuted|inconclusive`): `confirmed/refuted` обновляет позиции, `inconclusive` → допущение `confidence=LOW`, `UNVERIFIED` в план, ось не блокируется этим пунктом. Дай 1 доп. re-discuss по затронутой оси.
- Не сошлось после cap (draft-rounds=2, +1 post-spike) → **оператор разбивает тай** (`AskUserQuestion`, только реальная развилка) → `decision=operator_decision`. Оператор недоступен → `decision=blocked`, эмить `BLOCKED: no-consensus` с позициями сторон.
- `material:false` (effort/risk/косметика) НЕ гейтят → в план как ranked-assumption / зафиксированное возражение.
- Все material `reached` → `decision=consensus`.

### 7. Synthesize (механический шаблон)
Только при `decision ∈ {consensus, operator_decision}`. Заполни шаблон из сырых артефактов — **каждое claim/boundary/assumption → source-path**, новых claim не добавляй:

Problem · Constraints (объединение, дедуп) · Chosen solution (consensus-подход; при operator_decision — решение оператора) · Alternatives + why-rejected · Implementation steps `[{file, description, est-loc, depends-on:[idx]}]` · Assumptions ranked (HIGH/MED/LOW = согласие × instrumental-backing) · Operator-unknowns · Hard boundaries + STOP · Git stamp + drift status · `decision:`.
→ `$RUN/final/<topic>-plan.md`

`debate.md` = механическая склейка: disagreements всех раундов + таблица resolution (consensus / spike / operator). → `$RUN/final/<topic>-debate.md`.

## Degraded / отказы
- timeout/exit≠0/пустой → `fan` уже сделал retry; пометить `timeout/error`, продолжить если ≥2.
- codex `quota` → выбывание (фолбэк gpt-via-OpenRouter — v2).
- 2 семейства → `degraded: two-model`: cross-verify взаимная, большинства нет → любой неразрешённый material-split → оператор.
- 1 семейство → `degraded: claude-only`, в заголовке плана `DEGRADED`, не выдавать за fusion.
- спайк `refuted` → зависимая ветка блок; `inconclusive` → LOW/UNVERIFIED, не блок.
