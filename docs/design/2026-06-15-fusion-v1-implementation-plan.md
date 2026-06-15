# `/fusion` v1.1 — план реализации (после ревью плана 3 моделями)

- **Дата:** 2026-06-15
- **Источник:** спека v2 (`2026-06-15-fusion-plan-engine-design.md`)
- **Синтез:** независимые драфты Claude + Codex (gpt-5.5) + DeepSeek V4 Pro → консенсус → ревью плана теми же тремя → v1.1.
- **Статус:** буилдабельный после Phase 0 (транспорт 0.1 уже эмпирически прогнан в сессии 2026-06-15).

## Что изменилось v1 → v1.1 (закрытые блокеры ревью)

Тройное единогласие ревью: ядро механизма было не определено, а cut-list срезал несущее. Закрыто:

1. Определены **status.json-схема**, **consensus-рубрика**, **synthesis-шаблон** (ниже) — иначе `collect`/consensus неисполнимы над free-form markdown.
2. Возвращены в v1: **cleanup-trap**, **drift-check между раундами**, **минимальный spike-контракт**.
3. **Claude-step** получает тот же adapter-контракт, что внешние модели.
4. Baseline-A/B переформулирован из «гейт за час» в **eval-день** с рубрикой и анонимизацией; идиот-тест — на **canary-планах с seeded-дефектами**.
5. Разрешено **3 vs 2 семейства**: full fusion = 3; 2 = явный `degraded: two-model` с отдельной таблицей консенсуса.

## Ядро механизма (то, без чего не строится)

### status.json (схема v1)

```json
{
  "run_id": "<ts>", "task": "<...>", "round": 1, "head": "<git-sha-на-момент-брифа>",
  "participants": {
    "claude":   {"status": "ok|timeout|error|quota|degraded", "draft": "<path>", "tokens": 0, "cost": "0|unknown", "retries": 0},
    "codex":    {"...": "..."},
    "deepseek": {"...": "..."}
  },
  "cross_verify": [{"verifier":"claude","target":"codex","findings":"<path>","blockers":0}],
  "disagreements": [{"axis":"architecture","parties":["codex"],"severity":"critical|major|minor","instrumental_proof":"<path>|null"}],
  "consensus": {"architecture":"reached|split","approach":"...","effort":"...","risk":"...","assumptions":"..."},
  "decision": "consensus|operator-interview|degraded",
  "degraded": "none|two-model|claude-only"
}
```

`cost` = реальная цифра per-adapter ИЛИ `"unknown"` — никаких синтетических чисел.

### consensus-рубрика

- **Оси:** architecture · approach · effort · risk · key-assumptions.
- **Состояние оси:** `reached` (все доступные согласны) / `split`.
- **Severity спора:** `critical` (меняет выбранное решение / необратимость / корректность) · `major` · `minor`.
- **Жёсткий консенсус-гейт (никакого большинства):** synthesize/emit плана и любое движение вперёд НЕ происходит, пока по всем **material-осям** (architecture · approach · key-assumptions) не достигнут `reached` — то есть **все доступные агенты согласны**. 2/3 НЕ перебивает несогласного, и Claude-синтезатор не «склоняется к большинству».
  - **Material-split жив** → ещё раунд; спорное допущение идёт в **спайк** (спайк — инструмент *достичь* консенсуса, а не гейт за ним). Спор с `instrumental_proof` весомее спора без пруфа, но даже подтверждённый пруф не «выигрывает голосованием» — он убеждает остальных или эскалируется.
  - **Дожил до cap раундов** → **оператор разбивает тай** (явно решает), не автомат.
  - **Оператор недоступен / отказался решать** → план НЕ эмитится как консенсусный: выдаётся `BLOCKED: no-consensus` со списком разногласий и позициями сторон. Никакого выдуманного согласия.
  - **effort/risk-оценки и косметика — НЕ material:** не гейтят, фиксируются в плане как ranked-assumption / зафиксированное возражение, мёрж механический. Иначе система дедлочится на мелочах.

### synthesis-шаблон (механический fill-in, не творчество Claude)

Фиксированные секции, каждая заполняется из сырых артефактов по правилу:

| Секция | Источник |
|---|---|
| Problem | task + бриф |
| Constraints | объединение constraints всех драфтов, дедуп |
| Chosen solution | подход с `consensus.architecture=reached`; если `blocked` → решение оператора |
| Alternatives + why-rejected | проигравшие драфты + их cross-verify |
| Implementation steps | консенсусные шаги |
| Assumptions (ranked) | из драфтов; confidence = (согласие моделей) × (instrumental-backing) → HIGH/MED/LOW |
| Operator-unknowns | явный список с «почему не определили» |
| Hard boundaries / STOP | из драфтов |
| Git stamp + drift status | HEAD + результат drift-check |

## Phase 0 — префлайт

- **0.1 Транспорт — ПРОГНАН (2026-06-15).** ~10 успешных неинтерактивных вызовов codex `exec` + opencode V4 Pro в этой сессии. Открытые факты к до-замеру: `claude --print` существование, протечка write при `--pure` (V4 Pro записал файл — подтверждено), реальный 1M V4 на 300K-промпте. Гейт: ≥2 семейств надёжны → ок (codex+V4+Claude доступны).
- **0.2 Baseline-A/B — это EVAL-ДЕНЬ, не гейт за час.** Frozen-набор 8 задач × {Claude-only, improve, fusion}. Бинарная рубрика на план: `executable-as-is` / `has-errors` / `useful-insight`. Анонимизация: вывод перемешан, авторство срезано. **Pass:** fusion ≥ Claude-only на большинстве И строго лучше на ≥2. Иначе — не строим full.
- **0.3 Идиот-тест — на canary.** Планы с **seeded-дефектами** (известные reasoning-ошибки). Метрика: catch-rate дефектов + false-block-rate (штраф за ложные блокеры). Только `file:line`-находки без reasoning → архитектура под вопросом.

## Phase 1 — `fusion.sh` (детерминированная труба)

Layout: `runs/<ts>/{brief.md, drafts/, cross/, rediscuss/, spikes/, final/, status.json}`.

Команды:
- `cleanup [--all]` — снос сирот-worktree + `runs/tmp-*`. **Вызывается на старте КАЖДОГО run + `trap`/finally на выходе** (не только ручная).
- `fan <model> <role:draft|rediscuss> <promptfile>` — неинтерактивный вызов, таймаут 300s, **retry по детерминированным tiers** (tier1 full → tier2 без полных чужих планов (саммари) → tier3 truncated бриф, task+свой план), запись в `runs/<ts>/<role>/<model>.md`, обновление `status.json`. Валидирует, что stdout содержит мин. структуру (заголовок) — иначе `error`.
- `cross-verify <verifier-model> --target <draft>` — идиот-тест-шаблон + план → `cross/`.
- `spike <hypothesis> [--allow cmd,...] [--max-files N] [--max-time S]` — throwaway worktree, **structured verdict**: `{hypothesis, verdict: confirmed|refuted|inconclusive, evidence, blocks:[branch-id]}`. no-new-deps по умолчанию. Упал → зависимая ветка плана блок.
- `collect <run-dir>` — склейка артефактов + `status.json` → `aggregate.md`.

Exit: `0` ok · `1` degraded · `2` критично. **Claude — вне шелла, но с тем же контрактом:** SKILL.md зовёт Claude-субагента, кладёт draft в layout и **сам пишет его запись в `status.json`** (status/tokens/retries), как для внешних.

## Phase 2 — `SKILL.md` (оркестратор, исполняет Claude)

1. Парс `/fusion <task> --dir <target-repo> [--depth lite|full]`. **fusion работает НАД target-репо** (`--dir`), артефакты — в `<target>/.fusion/runs/`.
2. **brief-builder (spec):** источники — repo-tree (depth-cap), git HEAD + recent log, ADR/CONTEXT/README (cap), файлы задачи (grep+glob), intent-доки. Лимит per-source + общий ≤30–40% контекста участника. Исключения: секреты, lockfiles, vendored, build-артефакты. **coverage-check:** список кандидатов vs включённых, дропнутое логируется. Сырьё, не Claude-пересказ.
3. **drift-check:** `git rev-parse HEAD` перед каждым раундом и перед synthesize; HEAD сдвинулся → пере-снять затронутые куски брифа, отметить в status.
4. **budget:** per-adapter токены/стоимость ИЛИ `unknown`; жёсткий cap раундов; вывод оператору после раунда.

## Phase 3 — Цикл (2 раунда)

```
R1: draft (3 независимо, ОБЯЗАН мульти-угол: не решать / проще / зависит-от-будущего / сценарии)
    → cross-verify (ротация: Claude→Codex, Codex→DeepSeek, DeepSeek→Claude)
    → collect → aggregate.md
R2: drift-check → re-discuss (все видят пакет; склоняются/правят/DISAGREE)
    → cross-verify (та же ротация) → collect
consensus-ГЕЙТ (по рубрике над status.json): material-split жив → ещё раунд + спайк;
                  дожил до cap → оператор разбивает тай; оператор недоступен → BLOCKED: no-consensus
synthesize ТОЛЬКО после `reached` по всем material-осям (шаблон fill-in) → final/<topic>-plan.md + final/<topic>-debate.md
```

## Phase 4 — Отказы / degraded

| Событие | Реакция |
|---|---|
| timeout/exit≠0/пустой/непарсится | retry по tiers → пометить `timeout/error`, продолжить |
| codex quota | `quota`, выбывание (фолбэк gpt-via-OpenRouter — v2) |
| 2 семейства | `degraded: two-model` (см. таблицу ниже) |
| 1 семейство | `degraded: claude-only`, **не fusion**, план с пометкой |
| spike refuted/упал | допущение «не подтверждено», зависимая ветка — блок |
| нет ответа оператора | `operator-unknown`, не выдуманная уверенность |
| worktree-сирота | `cleanup` на старте + trap на выходе |

**degraded: two-model консенсус:** cross-verify взаимная (A→B, B→A); большинства 2/3 нет → любой неразрешённый спор → оператор (не «один перебил другого»).

## Cut-list v1.1 (что реально откладываем)

adaptive depth · авто-budget-fallback в improve · OpenRouter gpt-фолбэк · БД/персистентность (кроме append `status.json`-лога) · benchmark-suite · hosted `openrouter/fusion` · авто-исполнение кода вне spike · отдельная модель-судья · полировка plugin-манифеста (минимальный install/invoke — НЕ откладываем) · ротация синтезатора (v2-смягчение Claude-конфликта).

## Остаточные риски (честно)

- **Claude-синтезатор-конфликт смягчён, не устранён:** consensus теперь по рубрике над status.json, synthesis — шаблон, ambiguous-critical → оператор. Но Claude всё ещё авторит бриф и крутит рубрику. Полная нейтральность = не-Claude синтезатор (v2).
- **Wall-clock:** ≥1 ч/задача (6×300s × 2 раунда без retry/spike). fusion — НЕ интерактивный планёр; это batch-инструмент. Признано.
- **Качество брифа** — главный quality lever; brief-builder может стать отдельным под-проектом.
- **ROI** доказывается только Phase 0.2 eval-днём.

## Спайкнуть первым

1. Транспорт-замер (latency/tokens/`--print`/write-протечка) — добить 0.1.
2. brief-builder на 1 реальной задаче — влезает ли, покрывает ли.
3. Baseline-A/B eval-день — go/no-go на full.
