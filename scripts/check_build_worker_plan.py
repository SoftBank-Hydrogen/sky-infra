#!/usr/bin/env python3
"""Accept only adding --deploy-built-image to the existing build worker."""
import argparse
import copy
import json
import sys

from check_platform_image_plan import check_plan as check_image_plan

TASK = "module.worker.aws_ecs_task_definition.this"
SERVICE = "module.worker.aws_ecs_service.this"
BEFORE = ["worker", "--mode", "build"]
AFTER = BEFORE + ["--deploy-built-image"]


def check_plan(plan, expected_image):
    inspected = copy.deepcopy(plan)
    errors = []
    for resource in inspected.get("resource_changes", []):
        change = resource["change"]
        if resource.get("mode") == "data" or change["actions"] == ["no-op"]:
            continue
        address = resource["address"]
        if address not in {TASK, SERVICE}:
            errors.append(f"{address}: outside build worker activation scope")
            continue
        unknown = change.get("after_unknown") or {}
        permitted = {"arn", "arn_without_revision", "revision", "id"} if address == TASK else {"task_definition"}
        for key, value in unknown.items():
            if value is True and key not in permitted:
                errors.append(f"{address}: unknown changed field {key}")
        if address != TASK:
            continue
        try:
            before = json.loads(change["before"]["container_definitions"])
            after = json.loads(change["after"]["container_definitions"])
            if (len(before) != 1 or len(after) != 1 or before[0]["name"] != "sky-platform"
                    or after[0]["name"] != "sky-platform" or before[0].get("command") != BEFORE
                    or after[0].get("command") != AFTER
                    or before[0].get("image") != expected_image or after[0].get("image") != expected_image):
                errors.append(f"{address}: expected unchanged image and exact activation command")
            after[0]["command"] = before[0].get("command")
            change["after"]["container_definitions"] = json.dumps(after)
        except (KeyError, TypeError, ValueError, IndexError):
            errors.append(f"{address}: container comparison unavailable")
    image_errors, changed = check_image_plan(inspected, expected_image)
    return errors + image_errors, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json")
    parser.add_argument("--expected-image", required=True)
    args = parser.parse_args()
    with open(args.plan_json) as source:
        errors, changed = check_plan(json.load(source), args.expected_image)
    print("Changed resources:")
    for line in changed or ["(none)"]:
        print("  " + line)
    for error in errors:
        print("REJECT: " + error)
    if not errors:
        print("PASS: only the build worker activation changes")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
