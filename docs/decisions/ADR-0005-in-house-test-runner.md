# ADR-0005: In-house headless test runner

## Status

Accepted 2026-10-26

## Context

The rules core (ADR-0002) is the heart of the game and must be heavily tested, in CI, without a display.
Third-party Godot test frameworks exist, but they add a dependency (an addon that must track Godot
versions), bring features we do not need, and are harder for a small team or an AI agent to reason
about when something breaks. Our tests are mostly pure unit tests of `RefCounted` classes, which need
very little machinery.

## Decision

- Write a tiny runner, `tests/run_tests.gd`, a `SceneTree` script run with
  `godot --headless -s tests/run_tests.gd`.
- It discovers every `tests/**/test_*.gd` file, instantiates it (each extends `tests/test_case.gd`),
  runs every method whose name starts with `test_`, prints a per-test line and a summary, and quits
  with a non-zero exit code if any test fails.
- `tests/test_case.gd` provides a small assertion API (for example equality and truthiness checks with
  failure messages) and records failures without aborting the run.
- Tests mirror source layout: `tests/core/test_dice.gd` covers `src/core/dice`. Method names read as
  behaviour: `test_disadvantage_takes_lower_roll`.
- Randomised behaviour is tested with fixed seeds through the injected RNG.
- CI (GitHub Actions) runs the runner on every push and pull request.

## Consequences

### Positive

- No external dependency; the runner is a few hundred lines anyone can read and fix.
- Works identically on a developer machine and in CI, headless.
- Fast feedback: pure unit tests with no scene setup.
- Simple conventions are easy for new contributors and agents to follow.

### Negative

- Missing features compared with established frameworks: no mocking library, no parameterised tests,
  no editor integration, no rich reports. We add only what we need, when we need it.
- We own the runner's bugs; a broken runner could hide failures, so it must itself fail loudly on
  discovery or load errors.
- Scene and network integration tests (M3 onward) will need extra helpers built on top.
