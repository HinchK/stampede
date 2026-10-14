#!/usr/bin/env python3
"""Guided project-local Stampede config and quick launcher."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib


ROLES = (
    ("looper", "agy", "gemini-3.8-flash-low", "low", "briefs/looper.md", "herd"),
    ("pm", "claude", "sonnet", "medium", "briefs/pm-frontier.md", "herd"),
    ("gh", "agy", "gemini-3.8-flash-low", "low", "briefs/gh-frontier.md", "ops"),
    ("docs", "agy", "gemini-3.8-flash-low", "low", "briefs/docs-frontier.md", "ops"),
    ("architect", "opencode", "zai-coding-plan/glm-5.3", "medium", "briefs/arch-frontier.md", "herd"),
    ("helper", "agy", "gemini-3.8-flash-low", "low", "briefs/helper.md", "ops"),
)
KINDS = ("agy", "claude", "opencode")


def ask(label, default):
    answer = input(f"{label} [{default}]: ").strip()
    return answer or default


def parse_assignments(values, flag):
    result = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"{flag} requires role=value: {value}")
        role, selected = value.split("=", 1)
        if role not in {row[0] for row in ROLES} or not selected:
            raise ValueError(f"{flag}: unknown role or empty value: {value}")
        result[role] = selected
    return result


def probe(kind):
    binary = shutil.which(kind)
    if not binary:
        return None
    try:
        subprocess.run([binary, "--version"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5, check=False)
    except subprocess.TimeoutExpired:
        pass
    return binary


def listed_models(kind, binary):
    if kind == "claude":
        return None  # Claude's sonnet/opus/haiku aliases are CLI supported.
    try:
        output = subprocess.run([binary, "models"], capture_output=True, text=True,
                                timeout=15, check=False)
        if output.returncode == 0:
            return {line.split()[0] for line in output.stdout.splitlines() if line.strip()}
    except subprocess.TimeoutExpired:
        pass
    return None


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def toml_value(value):
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, (str, bool, int, float)):
        return json.dumps(value, ensure_ascii=False)
    raise ValueError(f"cannot preserve unsupported TOML value: {type(value).__name__}")


def append_table(lines, path, values):
    name = ".".join(key if re.fullmatch(r"[A-Za-z0-9_-]+", key) else quote(key) for key in path)
    lines += ["", f"[{name}]"]
    for key, value in values.items():
        if not isinstance(value, dict):
            field = key if re.fullmatch(r"[A-Za-z0-9_-]+", key) else quote(key)
            lines.append(f"{field} = {toml_value(value)}")
    for key, value in values.items():
        if isinstance(value, dict):
            append_table(lines, (*path, key), value)


def cost_tier(model):
    model = model.lower()
    if "opus" in model:
        return "high"
    if "flash-low" in model or "haiku" in model or "glm-5.3-flash" in model:
        return "low"
    if "sonnet" in model or "glm" in model or "flash" in model:
        return "medium"
    return "unknown"


def best_listed_model(kind, role, available, recommended):
    if not available or recommended in available:
        return recommended
    if kind == "agy":
        suffix = "flash-medium" if role == "architect" else "flash-low"
        candidates = [model for model in available if model.startswith("gemini-") and model.endswith(suffix)]
    elif kind == "opencode":
        suffix = "glm-5.3-flash" if role == "helper" else "glm-5.3"
        candidates = [model for model in available if model.endswith(suffix) and not model.startswith("ollama/")]
    else:
        candidates = []
    return sorted(candidates, reverse=True)[0] if candidates else None


def launcher_text(stampede, target):
    import shlex
    return f'''#!/usr/bin/env bash
set -euo pipefail
if [[ "${{1:-}}" == --help || "${{1:-}}" == -h ]]; then
  cat <<'HELP'
Usage: yeehaw.sh start --brainstorm|--wayfinder|--seat-only [--topic TEXT]
Leave for now: ctrl+b q detaches Herdr; agents keep running. Return with herdr.
Stop deliberately: {shlex.quote(str(stampede))} down {shlex.quote(str(target))}
Manual arbiter: {shlex.quote(str(stampede))} arbiter {shlex.quote(str(target))} init-ref (once), then drain after GREEN; promote --confirm after review.
HELP
  exit 0
fi
[[ "${{1:-}}" == start ]] || {{ echo 'Usage: yeehaw.sh start --brainstorm|--wayfinder|--seat-only [--topic TEXT]' >&2; exit 2; }}
shift
mode=s; topic=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --brainstorm) mode=b ;;
    --wayfinder) mode=w ;;
    --seat-only) mode=s ;;
    --topic) [[ $# -ge 2 ]] || {{ echo 'Missing topic' >&2; exit 2; }}; topic=$2; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$mode" == s || -n "$topic" ]] || {{ echo 'A topic is required' >&2; exit 2; }}
[[ -x {shlex.quote(str(stampede))} ]] || {{ echo 'Stampede installation is missing' >&2; exit 1; }}
exec {shlex.quote(str(stampede))} up {shlex.quote(str(target))} -m "$mode" -t "$topic"
'''


def render_config(target, choices, counts, attention, existing=None):
    existing = existing or {}
    slug = re.sub(r"[^a-z0-9_-]+", "-", target.name.lower()).strip("-") or "project"
    swarm = {"name": slug, "workspace_label": "swarm-dev", "trace_dir": ".herdr-swarm/traces",
             "worktree_root": ".herdr-swarm/worktrees", **existing.get("swarm", {})}
    attention_config = {**existing.get("attention", {}), "mode": attention, "bounded_looper": True}
    lines = ["# Generated by stampede setup; role choices are project-local."]
    for key, value in existing.items():
        if not isinstance(value, dict):
            lines.append(f"{key} = {toml_value(value)}")
    append_table(lines, ("swarm",), swarm)
    append_table(lines, ("attention",), attention_config)
    generated_keys = set()
    for role, _, _, tier, brief, tab in ROLES:
        count = counts[role] if role in counts else 1
        for index in range(1, count + 1):
            key = f"arch_{index}" if role == "architect" else f"pm_{index}" if role == "pm" and index > 1 else role
            generated_keys.add(key)
            kind, model = choices[role]
            name = key.replace("_", "-")
            lines += ["", f"[seats.{key}]", f"name = {quote(name)}",
                      f"role = {quote(role)}", f"default_kind = {quote(kind)}",
                      f"model = {quote(model)}", f"cost_tier = {quote(cost_tier(model))}",
                      f"brief = {quote(brief)}", f"tab = {quote(tab)}"]
            if role != "looper":
                lines.append("worktree = true")
    reviewer = existing.get("reviewer", {})
    for key, values in existing.items():
        if key not in ("swarm", "attention", "seats") and isinstance(values, dict):
            append_table(lines, (key,), values)
    for key in dict.fromkeys(("reviewer", reviewer.get("failover_seat", ""))):
        if key and key not in generated_keys and key in existing.get("seats", {}):
            seat = {**existing["seats"][key], "worktree": True}
            append_table(lines, ("seats", key), seat)
    return "\n".join(lines) + "\n"


def stage(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=f".{path.name}.", delete=False) as handle:
        handle.write(content)
        staged = Path(handle.name)
    staged.chmod(0o755 if executable else 0o644)
    return staged


def main():
    parser = argparse.ArgumentParser(prog="stampede setup")
    parser.add_argument("repo", type=Path)
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--launcher", type=Path)
    parser.add_argument("--attention", choices=("quiet", "medium", "loud"))
    parser.add_argument("--provider", action="append", default=[], metavar="ROLE=KIND")
    parser.add_argument("--model", action="append", default=[], metavar="ROLE=MODEL")
    parser.add_argument("--pm-count", type=int)
    parser.add_argument("--architect-count", type=int)
    args = parser.parse_args(sys.argv[2:])
    root = Path(sys.argv[1]).resolve()
    target = args.repo.resolve()
    if not target.is_dir():
        parser.error(f"repository directory does not exist: {target}")
    result = subprocess.run(["git", "-C", str(target), "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0 or Path(result.stdout.strip()).resolve() != target:
        parser.error("target must be a Git repository root")
    head = subprocess.run(["git", "-C", str(target), "rev-parse", "--verify", "HEAD"],
                          capture_output=True, text=True, check=False)
    if head.returncode:
        parser.error("repository needs an initial commit before setup; isolated seats branch from HEAD")
    config = target / "swarm.config.toml"
    existing = {}
    if config.exists():
        with config.open("rb") as handle:
            existing = tomllib.load(handle)
    old_choices = {}
    old_counts = {"pm": 0, "architect": 0}
    for key, seat in existing.get("seats", {}).items():
        role = seat.get("role") or ("architect" if key.startswith("arch") else "pm" if key.startswith("pm") else key)
        if role in old_counts:
            old_counts[role] += 1
        if role not in old_choices and seat.get("default_kind") and seat.get("model"):
            old_choices[role] = (seat["default_kind"], seat["model"])
    args.pm_count = args.pm_count if args.pm_count is not None else old_counts["pm"] or 1
    args.architect_count = args.architect_count if args.architect_count is not None else old_counts["architect"] or 2
    if not 1 <= args.pm_count <= 8 or not 1 <= args.architect_count <= 8:
        parser.error("PM and architect counts must be between 1 and 8")
    launcher = (args.launcher or target / "yeehaw.sh").expanduser().resolve()
    if launcher == config:
        parser.error("launcher and configuration cannot be the same file")
    if (config.exists() or launcher.exists()) and not args.force:
        changes = bool(args.provider or args.model or args.attention or
                       any(flag in sys.argv[2:] for flag in ("--pm-count", "--architect-count")))
        if config.exists() and launcher.exists() and not changes:
            if args.non_interactive:
                print(f"Stampede is already configured at {config}; no files changed.")
                return
            print("Existing roster: " + ", ".join(
                f"{role}={kind}/{model}" for role, (kind, model) in old_choices.items()))
            decision = ask("Existing setup: keep or edit", "keep").lower()
            if decision == "keep":
                print(f"Stampede is already configured at {config}; no files changed.")
                return
            if decision == "edit":
                args.force = True
            else:
                parser.error("choose keep or edit")
        else:
            parser.error("configuration or launcher exists; use --force to replace with .bak backups")

    providers = parse_assignments(args.provider, "--provider")
    models = parse_assignments(args.model, "--model")
    detected = {kind: probe(kind) for kind in KINDS}
    print("Harnesses: " + ", ".join(f"{kind} {'available' if binary else 'missing'}" for kind, binary in detected.items()))
    herdr = shutil.which("herdr")
    if herdr:
        try:
            integration = subprocess.run([herdr, "integration", "status"], capture_output=True,
                                         text=True, timeout=10, check=False)
            relevant = [line for line in integration.stdout.splitlines()
                        if any(kind in line.lower() for kind in KINDS)]
            print("Herdr integration status: " + ("; ".join(relevant[:6]) if relevant else
                  "no AGY/Claude/OpenCode integration reported; native conversation restore is unverified"))
        except subprocess.TimeoutExpired:
            print("Herdr integration status: timed out; native conversation restore is unverified")
    else:
        print("Herdr integration status: Herdr is unavailable; install it before launch")
    if not detected["agy"]:
        parser.error("AGY is required for the looper; install it and retry")
    if not args.non_interactive:
        try:
            args.pm_count = int(ask("Project manager count", str(args.pm_count)))
            args.architect_count = int(ask("Architect count", str(args.architect_count)))
        except ValueError:
            parser.error("PM and architect counts must be integers")
        if not 1 <= args.pm_count <= 8 or not 1 <= args.architect_count <= 8:
            parser.error("PM and architect counts must be between 1 and 8")
    catalogs = {kind: listed_models(kind, binary) if binary else None for kind, binary in detected.items()}
    for kind, catalog in catalogs.items():
        if detected[kind] and not catalog and kind != "claude":
            print(f"  {kind} model list unavailable; recommendations will be checked again when seating")
    choices = {}
    for role, recommended_kind, recommended_model, tier, _, _ in ROLES:
        previous = old_choices.get(role)
        kind = providers.get(role, previous[0] if previous else recommended_kind)
        if not args.non_interactive:
            kind = ask(f"{role} harness ({tier} cost recommendation)", kind)
        if role == "looper" and kind != "agy":
            parser.error("the looper must use AGY in this release")
        if kind not in KINDS or not detected.get(kind):
            parser.error(f"{role}: harness {kind} is unavailable; choose an installed harness")
        default_model = recommended_model if kind == recommended_kind else (
            "haiku" if kind == "claude" and role == "helper" else
            "sonnet" if kind == "claude" else
            "gemini-3.8-flash-medium" if kind == "agy" and role == "architect" else
            "gemini-3.8-flash-low" if kind == "agy" else
            "zai-coding-plan/glm-5.3-flash" if role == "helper" else "zai-coding-plan/glm-5.3")
        if previous and kind == previous[0]:
            default_model = previous[1]
        available = catalogs[kind]
        if kind != "claude":
            default_model = best_listed_model(kind, role, available, default_model)
        if default_model is None and role not in models:
            parser.error(f"{role}: no fitted model found in {kind} catalog; pass --model {role}=ID")
        model = models.get(role, default_model)
        if not args.non_interactive:
            model = ask(f"{role} model (recommended {default_model})", model)
        if any(ch.isspace() for ch in model) or not model:
            parser.error(f"{role}: model ID must be one nonempty token")
        if available and model not in available and kind != "claude":
            parser.error(f"{role}: model {model} is not in {kind} models output")
        choices[role] = (kind, model)
        print(f"  {role}: {kind} / {model} ({cost_tier(model)} cost tier; recommended {tier})")

    attention = args.attention or existing.get("attention", {}).get("mode", "medium")
    if not args.non_interactive:
        attention = ask("Attention mode (quiet/medium/loud)", attention)
        if attention not in ("quiet", "medium", "loud"):
            parser.error("attention mode must be quiet, medium, or loud")
        launcher = Path(ask("Save quick launcher at", str(launcher))).expanduser().resolve()
        if launcher.exists() and not args.force:
            parser.error("quick launcher exists; use --force for a backed-up replacement")
    print(f"Setup summary: {args.pm_count} PM, {args.architect_count} architects, attention {attention}")
    print(f"  Configuration: {config}\n  Launcher: {launcher}\n  Launch: Herdr seats only when yeehaw.sh start is run")
    if not args.non_interactive and ask("Write these files? (yes/no)", "yes").lower() not in ("yes", "y"):
        print("Setup cancelled; no files changed.")
        return
    content = render_config(target, choices, {"pm": args.pm_count, "architect": args.architect_count},
                            attention, existing)
    staged_config = stage(config, content)
    staged_launcher = stage(launcher, launcher_text(root / "bin/stampede", target), executable=True)
    try:
        with staged_config.open("rb") as handle:
            tomllib.load(handle)
        check = subprocess.run(["bash", "-c", 'source "$1"; config_dump_env test "$2"',
                                "setup-validator", str(root / "lib/config.sh"), str(staged_config)],
                               capture_output=True, text=True, check=False)
        if check.returncode:
            parser.error(f"generated config failed validation: {check.stderr.strip()}")
        for path in (config, launcher):
            if path.exists():
                shutil.copy2(path, Path(str(path) + ".bak"))
        os.replace(staged_config, config)
        os.replace(staged_launcher, launcher)
    finally:
        staged_config.unlink(missing_ok=True)
        staged_launcher.unlink(missing_ok=True)

    exclude_result = subprocess.run(["git", "-C", str(target), "rev-parse", "--git-path", "info/exclude"],
                                    capture_output=True, text=True, check=True)
    exclude = Path(exclude_result.stdout.strip())
    if not exclude.is_absolute():
        exclude = target / exclude
    exclude.parent.mkdir(parents=True, exist_ok=True)
    if not exclude.exists() or ".herdr-swarm/" not in exclude.read_text():
        with exclude.open("a") as handle:
            handle.write("\n.herdr-swarm/\n")
    print(f"Configuration: {config}\nQuick launch: {launcher}")
    print(f"Start: {launcher} start --brainstorm --topic 'your topic'")
    print("Leave for now: ctrl+b q detaches Herdr; agents keep running. Return with herdr and stampede status.")
    print(f"Stop deliberately: {root / 'bin/stampede'} down {target}")
    print(f"Arbiter is manual: {root / 'bin/stampede'} arbiter {target} init-ref (once, before draining)")
    print(f"After a GREEN gate: inspect status and gate receipt, then run {root / 'bin/stampede'} arbiter {target} drain")
    print(f"After reviewing the integration receipt: {root / 'bin/stampede'} arbiter {target} promote --confirm from a plain human shell.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as exc:
        print(f"setup: {exc}", file=sys.stderr)
        sys.exit(1)
