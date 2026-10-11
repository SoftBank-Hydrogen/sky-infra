# PR #21 resources: match the values sangmu1126 used in his local apply. No secrets.
enable_shared_database_queue  = true
enable_shared_workload_pool   = true
enable_allocation_worker      = true
allocation_worker_image_tag   = "fb7df653b9349781fa2c0ce3fd4adcb4060c681b"
allocation_worker_min_count   = 0
allocation_worker_workspace   = "live_20261011c"
enable_dedicated_preparation  = true
dedicated_target_instance_ids = ["sky-validation-dedicated-20261011"]
enable_dedicated_worker       = false
enable_database_cutover_queue = true