<!-- stages: 4 -->
# Contract Verification — Stage-4 Canonical (#498 AC 4.1)

Three contracts every component MUST honour (Issue #1407 post-mortem).

## The three contracts

1. **Type Contract** — every function argument and return value is type-safe. Python: type hints on every new function. Rust: explicit types (no `_` for non-trivial). Bash: validate `$#` + quote `"$@"`. SQL: column types match queries.
2. **Schema Contract** — every persistence write conforms to the schema (Pydantic / SQLModel / Postgres column types / Redis HSET fields). Schema drift = silent failure class — write tests assert exact field-presence + types.
3. **Config Contract** — every config-driven branch documents which config key gates it, and where that key's default lives. Tests cover both the default branch + the override branch.

## Verification (Stage-4 Verification Loop)

- `python3 -m mypy --strict <new modules>` exit 0
- `bash -n <new scripts>` exit 0
- Schema tests assert exact field set: `assert set(record.keys()) == EXPECTED_FIELDS`
- Config-traceability tests: for every `if config["x"] == "y":` branch, test fires with both `y` and `not-y` values.

## Failure mode this prevents

Writer renames a persisted field; reader silently gets `None`; the writer's mocks accept anything so tests stay green; surfaces only in prod. Schema tests force the writer-reader pair to agree on the exact field name at write time.

## Cross-references

- `../../standards/STANDARDS.md` "Contract Verification — Three Contracts" (#1407 post-mortem).
- `../../standards/ANTI-PATTERNS.md` AP #12 (No Observability — write-time enforcement is contract verification's twin).
- `../../standards/stage-4/observability-fail-fast.md` — runtime invariants contract verification supplements.
