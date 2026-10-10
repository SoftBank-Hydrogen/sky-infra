# Build consumer 활성화

PR #19가 별도 상시 sky-dev-outbox 서비스를 생성했으므로 sky-dev-worker를 build 모드로 전환한다.
worker는 SQS 대기 메시지로 0~worker_max_count 확장하며 outbox는 계속 1개로 유지한다.
이미지, API, DB schema/data, builder code pin 및 비밀 값은 이 변경에서 바꾸지 않는다.
전체 terraform workflow plan을 검토하고 dev 승인 후 apply해야 한다.

## 적용 후 확인

- outbox running 1, 로그 Outbox confirmed/deferred 확인.
- worker command worker --mode build, 큐 확장 target/policy/alarm 생성 확인.
- 빈 큐일 때 worker 0은 정상이다. 설정 확인용 일회성 task(--check-config)는 소비·DB 변경 없이 종료해야 한다.
- 실제 소비 검증을 위해서는 전용 테스트 앱의 정상 API 승인/접수로 유효한 operation을 만들고
  outbox→SQS→worker→builder→ECR→DB build_ready를 확인한다. 큐에 DB에 없는 ID를 넣지 않는다.
- build_ready는 이미지 준비 완료이며 ECS 사용자 앱 배포 완료가 아니다.
- DB/approval/admission schema가 준비되지 않으면 소비를 시작하지 못한다. runtime은 migration하지 않는다.
- 태스크 보호와 worker 로그, DLQ 및 DB lease/중단 복구는 실환경에서 별도 확인한다.


## Verified image deployment

Platform PR #29 adds `--deploy-built-image`. Once its verified service image is deployed, enable this flag in the worker command. This connects new approved, environment-free HTTP apps from remote build to ECS Express creation and public HTTP verification. It does not migrate the state DB or automatically resume previously parked build_ready operations. Updates/rollback and WebSocket gameplay verification remain separate work.

The platform reads existing sky-core outputs and uses the worker's existing managed-stack/ECS/PassRole permissions; no additional IAM grants are added. An uncertain create request remains needs_attention with its app lock retained. Never requeue such an AWS intent without reconciliation.
