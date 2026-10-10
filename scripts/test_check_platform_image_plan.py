"""check_platform_image_plan 단위 테스트. 실행: python3 -m unittest discover -s scripts"""

import copy
import json
import unittest

from check_platform_image_plan import check_plan

TASK_DEFINITION = "module.api.aws_ecs_task_definition.this"
SERVICE = "module.api.aws_ecs_service.this"
WORKER_TASK_DEFINITION = "module.worker.aws_ecs_task_definition.this"
WORKER_SERVICE = "module.worker.aws_ecs_service.this"
OUTBOX_TASK_DEFINITION = "module.outbox.aws_ecs_task_definition.this"
OUTBOX_SERVICE = "module.outbox.aws_ecs_service.this"

REPO = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sky-platform"
OLD = REPO + ":aaaaaaa"
NEW = REPO + ":bbbbbbb"


def containers(image, **extra):
    c = {
        "name": "sky-platform",
        "image": image,
        "essential": True,
        "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
        "environment": [{"name": "SKY_AWS_REGION", "value": "ap-northeast-2"}],
        "linuxParameters": {"initProcessEnabled": True, "capabilities": {"add": []}},
    }
    c.update(extra)
    return json.dumps([c])


def task_definition_change(before_image=OLD, after_image=NEW, after_extra=None, cpu_after="1024",
                           address=TASK_DEFINITION):
    return {
        "address": address,
        "mode": "managed",
        "change": {
            "actions": ["delete", "create"],
            "before": {
                "arn": "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/sky-dev-api:3",
                "revision": 3,
                "cpu": "1024",
                "family": "sky-dev-api",
                "container_definitions": containers(before_image),
            },
            "after": {
                "cpu": cpu_after,
                "family": "sky-dev-api",
                "container_definitions": containers(after_image, **(after_extra or {})),
            },
            "after_unknown": {"arn": True, "revision": True},
        },
    }


def aws_stored_task_definition_change(address=TASK_DEFINITION):
    """state가 AWS가 저장한 표현을 담은 태스크 정의 교체 (설정 값은 같다)."""
    tdc = task_definition_change(address=address)
    before = tdc["change"]["before"]
    before.update({"ipc_mode": "", "pid_mode": "", "tags": {}})
    stored = json.loads(before["container_definitions"])
    # awsvpc에서 AWS가 hostPort = containerPort를 채워 저장한다
    stored[0]["portMappings"] = [{"containerPort": 8080, "hostPort": 8080, "protocol": "tcp"}]
    before["container_definitions"] = json.dumps(stored)
    tdc["change"]["after"].update({"ipc_mode": None, "pid_mode": None, "tags": None})
    return tdc


def service_change(actions=None, desired_after=2, address=SERVICE):
    return {
        "address": address,
        "mode": "managed",
        "change": {
            "actions": actions or ["update"],
            "before": {"task_definition": "arn:...:3", "desired_count": 2, "name": "sky-dev-api"},
            "after": {"desired_count": desired_after, "name": "sky-dev-api"},
            "after_unknown": {"task_definition": True},
        },
    }


def plan(*changes):
    return {"resource_changes": list(changes)}


class CheckPlanTest(unittest.TestCase):
    def test_image_only_change_passes(self):
        errors, changed = check_plan(plan(task_definition_change(), service_change()), NEW)
        self.assertEqual(errors, [])
        self.assertEqual(len(changed), 2)

    def test_no_change_passes(self):
        noop = copy.deepcopy(service_change())
        noop["change"]["actions"] = ["no-op"]
        errors, changed = check_plan(plan(noop), NEW)
        self.assertEqual((errors, changed), ([], []))

    def test_data_sources_are_ignored(self):
        data = {"address": "module.iam.data.aws_iam_policy_document.api", "mode": "data",
                "change": {"actions": ["read"]}}
        errors, _ = check_plan(plan(data, task_definition_change(), service_change()), NEW)
        self.assertEqual(errors, [])

    def test_state_list_order_and_empty_values_are_ignored(self):
        tdc = task_definition_change()
        before = json.loads(tdc["change"]["before"]["container_definitions"])
        before[0]["environment"] = [{"name": "B", "value": "2"}, {"name": "A", "value": "1"}]
        before[0]["volumesFrom"] = []
        before[0]["linuxParameters"].pop("capabilities")
        tdc["change"]["before"]["container_definitions"] = json.dumps(before)
        after = json.loads(tdc["change"]["after"]["container_definitions"])
        after[0]["environment"] = [{"name": "A", "value": "1"}, {"name": "B", "value": "2"}]
        tdc["change"]["after"]["container_definitions"] = json.dumps(after)
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertEqual(errors, [])

    def test_aws_stored_representation_passes(self):
        # PR #3 봇 에러 재현: state는 AWS가 저장한 표현("", {}, hostPort), plan의 after는 설정값(null)
        for tags_before, tags_after in (({}, None), (None, {})):
            with self.subTest(tags_before=tags_before, tags_after=tags_after):
                changes = []
                for td, svc in ((TASK_DEFINITION, SERVICE), (WORKER_TASK_DEFINITION, WORKER_SERVICE)):
                    tdc = aws_stored_task_definition_change(td)
                    tdc["change"]["before"]["tags"] = tags_before
                    tdc["change"]["after"]["tags"] = tags_after
                    changes += [tdc, service_change(address=svc)]
                errors, changed = check_plan(plan(*changes), NEW)
                self.assertEqual(errors, [])
                self.assertEqual(len(changed), 4)

    def test_host_port_different_from_container_port_fails(self):
        tdc = aws_stored_task_definition_change()
        after = json.loads(tdc["change"]["after"]["container_definitions"])
        after[0]["portMappings"] = [{"containerPort": 8080, "hostPort": 9090, "protocol": "tcp"}]
        tdc["change"]["after"]["container_definitions"] = json.dumps(after)
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("이미지 외 값" in e for e in errors))

    def test_ipc_mode_set_to_real_value_fails(self):
        tdc = aws_stored_task_definition_change()
        tdc["change"]["after"]["ipc_mode"] = "host"
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("'ipc_mode'" in e for e in errors))
        self.assertFalse(any("'pid_mode'" in e for e in errors))

    def test_tags_real_change_fails(self):
        cases = {
            "added": ({}, {"Owner": "platform"}),
            "added_from_null": (None, {"Owner": "platform"}),
            "changed": ({"Owner": "platform"}, {"Owner": "data"}),
        }
        for name, (tags_before, tags_after) in cases.items():
            with self.subTest(name):
                tdc = aws_stored_task_definition_change()
                tdc["change"]["before"]["tags"] = tags_before
                tdc["change"]["after"]["tags"] = tags_after
                errors, _ = check_plan(plan(tdc, service_change()), NEW)
                self.assertTrue(any("'tags'" in e for e in errors))

    def test_other_resource_change_fails(self):
        db = {"address": "module.state_db.aws_db_instance.this", "mode": "managed",
              "change": {"actions": ["update"], "before": {}, "after": {}, "after_unknown": {}}}
        errors, _ = check_plan(plan(db, task_definition_change(), service_change()), NEW)
        self.assertTrue(any("aws_db_instance" in e for e in errors))

    def test_api_and_worker_together_pass(self):
        errors, changed = check_plan(plan(
            task_definition_change(), service_change(),
            task_definition_change(address=WORKER_TASK_DEFINITION),
            service_change(address=WORKER_SERVICE),
        ), NEW)
        self.assertEqual(errors, [])
        self.assertEqual(len(changed), 4)

    def test_api_worker_and_outbox_together_pass(self):
        errors, changed = check_plan(plan(
            task_definition_change(), service_change(),
            task_definition_change(address=WORKER_TASK_DEFINITION),
            service_change(address=WORKER_SERVICE),
            task_definition_change(address=OUTBOX_TASK_DEFINITION),
            service_change(address=OUTBOX_SERVICE),
        ), NEW)
        self.assertEqual(errors, [])
        self.assertEqual(len(changed), 6)

    def test_outbox_wrong_image_fails(self):
        errors, _ = check_plan(plan(
            task_definition_change(), service_change(),
            task_definition_change(address=OUTBOX_TASK_DEFINITION, after_image=REPO + ":ccccccc"),
            service_change(address=OUTBOX_SERVICE),
        ), NEW)
        self.assertTrue(any(OUTBOX_TASK_DEFINITION in e and "기대값과 다르다" in e for e in errors))

    def test_outbox_command_change_fails(self):
        tdc = task_definition_change(address=OUTBOX_TASK_DEFINITION, after_extra={"command": ["worker"]})
        errors, _ = check_plan(plan(tdc, service_change(address=OUTBOX_SERVICE)), NEW)
        self.assertTrue(any(OUTBOX_TASK_DEFINITION in e and "이미지 외 값" in e for e in errors))

    def test_worker_wrong_image_fails(self):
        errors, _ = check_plan(plan(
            task_definition_change(), service_change(),
            task_definition_change(address=WORKER_TASK_DEFINITION, after_image=REPO + ":ccccccc"),
            service_change(address=WORKER_SERVICE),
        ), NEW)
        self.assertTrue(any(WORKER_TASK_DEFINITION in e and "기대값과 다르다" in e for e in errors))

    def test_scaling_change_fails(self):
        target = {"address": "module.worker.aws_appautoscaling_target.this[0]", "mode": "managed",
                  "change": {"actions": ["update"], "before": {"max_capacity": 3},
                             "after": {"max_capacity": 5}, "after_unknown": {}}}
        errors, _ = check_plan(plan(target, task_definition_change(), service_change()), NEW)
        self.assertTrue(any("aws_appautoscaling_target" in e for e in errors))

    def test_container_change_besides_image_fails(self):
        tdc = task_definition_change(after_extra={"environment": [{"name": "X", "value": "1"}]})
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("이미지 외 값" in e for e in errors))

    def test_task_definition_attribute_change_fails(self):
        errors, _ = check_plan(plan(task_definition_change(cpu_after="2048"), service_change()), NEW)
        self.assertTrue(any("'cpu'" in e for e in errors))

    def test_unexpected_image_fails(self):
        errors, _ = check_plan(plan(task_definition_change(after_image=REPO + ":ccccccc"), service_change()), NEW)
        self.assertTrue(any("기대값과 다르다" in e for e in errors))

    def test_task_definition_in_place_update_fails(self):
        tdc = task_definition_change()
        tdc["change"]["actions"] = ["update"]
        errors, _ = check_plan(plan(tdc, service_change()), NEW)
        self.assertTrue(any("교체만 허용" in e for e in errors))

    def test_service_replace_fails(self):
        errors, _ = check_plan(plan(task_definition_change(), service_change(["delete", "create"])), NEW)
        self.assertTrue(any("제자리 수정만" in e for e in errors))

    def test_service_other_attribute_fails(self):
        errors, _ = check_plan(plan(task_definition_change(), service_change(desired_after=3)), NEW)
        self.assertTrue(any("'desired_count'" in e for e in errors))

    def test_errored_plan_fails(self):
        p = plan(task_definition_change(), service_change())
        p["errored"] = True
        errors, _ = check_plan(p, NEW)
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
