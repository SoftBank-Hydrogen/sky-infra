#!/usr/bin/env python3
"""서비스 서버 이미지 배포 plan이 이미지 변경만 담고 있는지 검사한다.

`terraform show -json <planfile>` 결과를 읽어 다음을 확인한다. API·워커·outbox 각각에 대해:
- 바뀌는 자원은 태스크 정의와 ECS 서비스뿐이다 (-target이 끌어온 의존 자원 변경은 거부)
- 태스크 정의는 교체만 허용하고, 컨테이너 이미지 외의 값은 그대로다
- 새 이미지는 기대한 <ECR URL>:<SHA>다
- ECS 서비스는 제자리 수정이고, task_definition 외의 값은 그대로다

사용: check_platform_image_plan.py plan.json --expected-image <ECR URL>:<SHA>
위반이 있으면 종료 코드 1.
"""

import argparse
import json
import sys

SERVICES = ("api", "worker", "outbox")
TASK_DEFINITIONS = {f"module.{name}.aws_ecs_task_definition.this" for name in SERVICES}
ECS_SERVICES = {f"module.{name}.aws_ecs_service.this" for name in SERVICES}
CONTAINER_NAME = "sky-platform"

REPLACE_ACTIONS = (["delete", "create"], ["create", "delete"])
# 새 리비전이 만들어지면 함께 바뀌는 계산 속성
TASK_DEFINITION_COMPUTED = {"arn", "arn_without_revision", "revision", "id"}


def _empty(value):
    return value is None or value is False or value == "" or value == [] or value == {}


def normalize(value):
    """state와 설정의 표현 차이(빈 값, 목록 순서)를 없앤다."""
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            item = normalize(item)
            if not _empty(item):
                out[key] = item
        return out
    if isinstance(value, list):
        items = [normalize(item) for item in value]
        if items and all(isinstance(item, dict) and "name" in item for item in items):
            items.sort(key=lambda item: str(item["name"]))
        return items
    return value


def _same(before, after):
    """normalize한 뒤 비교한다. 빈 값(None, "", [], {}, False)끼리는 같다고 본다."""
    before, after = normalize(before), normalize(after)
    if _empty(before) and _empty(after):
        return True
    return before == after


def _without_default_host_port(container):
    """awsvpc에서 AWS가 채워 넣는 hostPort(= containerPort)를 뺀다. 다른 값이면 남긴다."""
    mappings = container.get("portMappings")
    if not isinstance(mappings, list):
        return container
    stripped = []
    for mapping in mappings:
        if isinstance(mapping, dict) and "hostPort" in mapping \
                and mapping["hostPort"] == mapping.get("containerPort"):
            mapping = {k: v for k, v in mapping.items() if k != "hostPort"}
        stripped.append(mapping)
    return {**container, "portMappings": stripped}


def _containers(raw):
    if raw is None:
        return None
    return json.loads(raw) if isinstance(raw, str) else raw


def changed_keys(change):
    """after 값이 확정된 속성 중 before와 다른 키."""
    before = change.get("before") or {}
    after = change.get("after") or {}
    unknown = change.get("after_unknown") or {}
    keys = set(before) | set(after)
    return sorted(
        key for key in keys
        if unknown.get(key) is not True and not _same(before.get(key), after.get(key))
    )


def check_task_definition(address, change, expected_image):
    errors = []
    actions = change["actions"]
    if actions not in REPLACE_ACTIONS:
        return [f"{address}: 교체만 허용한다 (actions={actions})"]

    for key in changed_keys(change):
        if key in TASK_DEFINITION_COMPUTED or key == "container_definitions":
            continue
        errors.append(f"{address}: 이미지 외 속성 '{key}'이 바뀐다")

    before = _containers((change.get("before") or {}).get("container_definitions"))
    after = _containers((change.get("after") or {}).get("container_definitions"))
    if before is None or after is None:
        return errors + [f"{address}: container_definitions를 비교할 수 없다"]

    def without_image(containers):
        return normalize([
            _without_default_host_port({k: v for k, v in c.items() if k != "image"})
            for c in containers
        ])

    if without_image(before) != without_image(after):
        errors.append(f"{address}: 컨테이너 정의에서 이미지 외 값이 바뀐다")

    images = {c.get("name"): c.get("image") for c in after}
    if images.get(CONTAINER_NAME) != expected_image:
        errors.append(
            f"{address}: {CONTAINER_NAME} 이미지가 기대값과 다르다 "
            f"(plan={images.get(CONTAINER_NAME)}, 기대={expected_image})"
        )
    return errors


def check_service(address, change):
    actions = change["actions"]
    if actions != ["update"]:
        return [f"{address}: 제자리 수정만 허용한다 (actions={actions})"]
    return [
        f"{address}: task_definition 외 속성 '{key}'이 바뀐다"
        for key in changed_keys(change)
        if key != "task_definition"
    ]


def check_plan(plan, expected_image):
    """(위반 목록, 바뀌는 자원 주소 목록)을 돌려준다."""
    errors = []
    changed = []
    if plan.get("errored"):
        errors.append("plan이 오류 상태로 끝났다")

    for rc in plan.get("resource_changes", []):
        if rc.get("mode") == "data":
            continue
        change = rc["change"]
        if change["actions"] == ["no-op"]:
            continue
        address = rc["address"]
        changed.append(f"{address} {change['actions']}")
        if address in TASK_DEFINITIONS:
            errors += check_task_definition(address, change, expected_image)
        elif address in ECS_SERVICES:
            errors += check_service(address, change)
        else:
            errors.append(f"{address}: 이미지 배포 범위 밖 자원이 바뀐다 (actions={change['actions']})")
    return errors, changed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("plan_json")
    parser.add_argument("--expected-image", required=True)
    args = parser.parse_args(argv)

    with open(args.plan_json, encoding="utf-8") as f:
        plan = json.load(f)
    errors, changed = check_plan(plan, args.expected_image)

    print("바뀌는 자원:")
    for line in changed or ["(없음)"]:
        print(f"  - {line}")
    if errors:
        print("검사 실패:")
        for line in errors:
            print(f"  - {line}")
        return 1
    print("검사 통과: 이미지 변경만 있다." if changed else "검사 통과: 바뀌는 것이 없다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
