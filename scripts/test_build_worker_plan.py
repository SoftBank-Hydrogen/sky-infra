import copy
import json
import unittest
from check_build_worker_plan import AFTER, BEFORE, SERVICE, TASK, check_plan

IMAGE = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sky-platform:123abcd"


def plan():
    container = {"name": "sky-platform", "image": IMAGE, "command": BEFORE, "environment": [{"name": "REGION", "value": "ap-northeast-2"}]}
    return {"resource_changes": [
        {"address": TASK, "mode": "managed", "change": {"actions": ["delete", "create"],
         "before": {"container_definitions": json.dumps([container]), "cpu": "512"},
         "after": {"container_definitions": json.dumps([{**container, "command": AFTER}]), "cpu": "512"},
         "after_unknown": {"arn": True, "revision": True}}},
        {"address": SERVICE, "mode": "managed", "change": {"actions": ["update"],
         "before": {"task_definition": "old", "desired_count": 0},
         "after": {"task_definition": None, "desired_count": 0}, "after_unknown": {"task_definition": True}}}
    ]}


class WorkerPlanTests(unittest.TestCase):
    def test_command_only_and_no_input_mutation(self):
        value = plan(); saved = copy.deepcopy(value)
        self.assertEqual(check_plan(value, IMAGE)[0], [])
        self.assertEqual(value, saved)

    def test_unrelated_database_delete_rejected(self):
        value = plan(); value["resource_changes"].append({"address": "module.workload_pool.aws_db_instance.this", "mode": "managed", "change": {"actions": ["delete"]}})
        self.assertTrue(check_plan(value, IMAGE)[0])

    def test_image_or_environment_drift_rejected(self):
        for key, replacement in [("image", "other"), ("environment", []), ("command", ["worker", "--once"])]:
            with self.subTest(key=key):
                value=plan(); change=value["resource_changes"][0]["change"]
                containers=json.loads(change["after"]["container_definitions"]);containers[0][key]=replacement
                change["after"]["container_definitions"]=json.dumps(containers)
                self.assertTrue(check_plan(value, IMAGE)[0])

    def test_unknown_role_and_service_change_rejected(self):
        value=plan();value["resource_changes"][0]["change"]["after_unknown"]["task_role_arn"]=True
        self.assertTrue(check_plan(value, IMAGE)[0])
        value=plan();value["resource_changes"][1]["change"]["after"]["desired_count"]=2
        self.assertTrue(check_plan(value, IMAGE)[0])

    def test_api_task_change_rejected(self):
        value=plan();value["resource_changes"][0]["address"]="module.api.aws_ecs_task_definition.this"
        self.assertTrue(check_plan(value, IMAGE)[0])


if __name__ == "__main__":
    unittest.main()
