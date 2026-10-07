#!/usr/bin/env python3
"""Summarize two or more E70Q10 power_diag snapshots; runs on the host."""
import argparse
import csv
import re
from pathlib import Path

HEADER = re.compile(r"^=== SAMPLE seq=(\d+) session=(\S+) .*?wall=(\S+) boottime=([\d.]+) monotonic=([\d.]+) ===$")


def snapshots(paths):
    result = []
    for path in paths:
        current = None
        section = None
        for line in Path(path).read_text(errors="replace").splitlines():
            match = HEADER.match(line)
            if match:
                current = {"seq": int(match[1]), "session": match[2],
                           "wall": match[3], "boottime": float(match[4]),
                           "monotonic": float(match[5]), "sections": {}}
                section = None
            elif line == "=== END SAMPLE ===" and current is not None:
                result.append(current)
                current = None
            elif current is not None and line.startswith("--- ") and line.endswith(" ---"):
                section = line[4:-4]
                current["sections"][section] = []
            elif current is not None and section is not None:
                current["sections"][section].append(line)
    return result


def section(snapshot, path):
    return snapshot["sections"].get(path, [])


def battery(snapshot):
    for path, lines in snapshot["sections"].items():
        if path.startswith("/sys/class/power_supply/") and path.endswith("/uevent"):
            values = dict(line.split("=", 1) for line in lines if "=" in line)
            if (values.get("POWER_SUPPLY_TYPE") == "Battery"
                    or ("battery" in path.lower()
                        and "POWER_SUPPLY_CAPACITY" in values)):
                return values
    return {}


def suspend_stats(snapshot):
    values = {}
    for line in section(snapshot, "/sys/kernel/debug/suspend_stats"):
        match = re.match(r"^([a-z_]+): (\d+)$", line)
        if match:
            values[match[1]] = int(match[2])
    return values


def wake_sources(snapshot):
    values = {}
    for line in section(snapshot, "/sys/kernel/debug/wakeup_sources"):
        parts = line.rsplit(None, 9)
        if len(parts) == 10 and all(part.isdigit() for part in parts[1:]):
            values[parts[0]] = [int(part) for part in parts[1:]]
    return values


def cpu_ticks(snapshot):
    for line in section(snapshot, "/proc/stat"):
        if line.startswith("cpu "):
            return [int(value) for value in line.split()[1:]]
    return []


def app_stats(path):
    values = {}
    packages = {}
    if not path.exists():
        return values, packages
    with path.open(errors="replace", newline="") as source:
        for row in csv.reader(source):
            if len(row) < 5 or not row[1].isdigit():
                continue
            uid, category, kind = int(row[1]), row[2], row[3]
            if category == "i" and kind == "uid" and len(row) >= 6:
                packages.setdefault(row[4], set()).add(row[5])
            if category != "l":
                continue
            if kind == "awl" and len(row) >= 6:
                try:
                    values.setdefault(uid, {})["wakelock_ms"] = int(row[4])
                    values[uid]["background_ms"] = int(row[5])
                except ValueError:
                    pass
            elif kind == "cpu" and len(row) >= 6:
                try:
                    values.setdefault(uid, {})["cpu_ms"] = int(row[4]) + int(row[5])
                except ValueError:
                    pass
    return values, packages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", help="samples.previous.log then samples.log")
    args = parser.parse_args()
    data = snapshots(args.logs)
    if data:
        boot_path = "/proc/sys/kernel/random/boot_id"
        last_boot = section(data[-1], boot_path)
        if last_boot:
            data = [item for item in data if section(item, boot_path) == last_boot]
        session = data[-1]["session"]
        data = [item for item in data if item["session"] == session]
    if len(data) < 2:
        parser.error("at least two complete samples are required")
    start, end = data[0], data[-1]
    # ADB USB is a charger on this device. Prefer two battery-only samples.
    discharging = [item for item in data
                   if battery(item).get("POWER_SUPPLY_STATUS") == "Discharging"]
    if len(discharging) >= 2:
        start, end = discharging[0], discharging[-1]
    elif discharging:
        start = discharging[0]
    elapsed = end["boottime"] - start["boottime"]
    awake = end["monotonic"] - start["monotonic"]
    sleep = max(0.0, elapsed - awake)
    print(f"기간: {start['wall']} → {end['wall']} ({len(data)}개 기록)")
    print(f"전체 {elapsed/3600:.2f}시간 · 커널 깨어 있음 {awake/3600:.2f}시간 · 실제 suspend {sleep/3600:.2f}시간", end="")
    if elapsed > 0:
        print(f" ({100*sleep/elapsed:.1f}%)")
    else:
        print()
    first_battery, last_battery = battery(start), battery(end)
    for key, label, unit in (("POWER_SUPPLY_CAPACITY", "배터리", "%"),
                             ("POWER_SUPPLY_VOLTAGE_NOW", "전압", " µV")):
        if key in first_battery and key in last_battery:
            print(f"{label}: {first_battery[key]}{unit} → {last_battery[key]}{unit}")
    print("배터리 상태:", first_battery.get("POWER_SUPPLY_STATUS", "?"), "→",
          last_battery.get("POWER_SUPPLY_STATUS", "?"))
    before, after = suspend_stats(start), suspend_stats(end)
    for key, label in (("success", "suspend 성공"), ("fail", "suspend 실패")):
        if key in before and key in after:
            print(f"{label}: +{after[key] - before[key]}")
    first_cpu, last_cpu = cpu_ticks(start), cpu_ticks(end)
    if len(first_cpu) >= 5 and len(last_cpu) >= 5:
        ticks = [b - a for a, b in zip(first_cpu, last_cpu)]
        total = sum(ticks)
        if total > 0:
            idle = ticks[3] + ticks[4]
            print(f"깨어 있는 동안 CPU 비유휴 비율(대략): {100*(total-idle)/total:.1f}%")
    first_sources, last_sources = wake_sources(start), wake_sources(end)
    rows = []
    for name, values in last_sources.items():
        old = first_sources.get(name, [0] * 9)
        # active_count,event_count,wakeup_count,expire_count,active_since,
        # total_time,max_time,last_change,prevent_suspend_time (milliseconds).
        prevented = max(0, values[8] - old[8])
        active = max(0, values[5] - old[5])
        wakeups = max(0, values[2] - old[2])
        events = max(0, values[1] - old[1])
        if prevented or active or wakeups or events:
            rows.append((name, prevented, active, wakeups, events))
    rows.sort(key=lambda item: (item[1], item[3], item[2]), reverse=True)
    print("\n깨움 원인 상위 항목 (절전 방해 시간 / 활성 시간 / 실제 깨움 횟수 / 이벤트):")
    for name, prevented, active, wakeups, events in rows[:15]:
        print(f"  {name}: {prevented/60000:.1f}분 / {active/60000:.1f}분 / {wakeups} / {events}")
    if not rows:
        print("  사용 가능한 누적 깨움 원인 차이가 없습니다.")
    reason = [line for line in section(end,
              "/sys/kernel/wakeup_reasons/last_resume_reason") if line]
    if reason:
        print("\n마지막 resume 원인:", ", ".join(reason))
    stats_dir = Path(args.logs[-1]).parent
    app_before, names_before = app_stats(stats_dir / "batterystats-start.txt")
    app_after, names_after = app_stats(stats_dir / "batterystats-end.txt")
    if app_before and app_after:
        reset = any(counters.get(key, 0) < app_before.get(uid, {}).get(key, 0)
                    for uid, counters in app_after.items()
                    for key in ("wakelock_ms", "background_ms", "cpu_ms"))
        if reset:
            print("\nBatteryStats 누적값이 감소했습니다. 충전/통계 재설정 구간이라 앱별 차이를 생략합니다.")
        names_before.update(names_after)
        app_rows = []
        for uid, counters in ({} if reset else app_after).items():
            old = app_before.get(uid, {})
            held = max(0, counters.get("wakelock_ms", 0) - old.get("wakelock_ms", 0))
            background = max(0, counters.get("background_ms", 0)
                             - old.get("background_ms", 0))
            cpu = max(0, counters.get("cpu_ms", 0) - old.get("cpu_ms", 0))
            if held or background or cpu:
                app_rows.append((uid, held, background, cpu))
        app_rows.sort(key=lambda item: (item[2], item[1], item[3]), reverse=True)
        if app_rows:
            print("\n앱별 사용 상위 항목 (백그라운드 wakelock / 전체 wakelock / CPU):")
        for uid, held, background, cpu in app_rows[:15]:
            name = ", ".join(sorted(names_before.get(str(uid), []))) or f"UID {uid}"
            print(f"  {name}: {background/60000:.1f}분 / {held/60000:.1f}분 / {cpu/60000:.1f}분")
    print("\n참고: 깨움 원인 시간은 전력량이 아니며 서로 겹칠 수 있습니다.")
    print("배터리 전류 센서가 없으면 앱별 소비 전력은 이 기록만으로 확정할 수 없습니다.")


if __name__ == "__main__":
    main()
