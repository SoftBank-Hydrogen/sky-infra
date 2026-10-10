# 원격 빌드 App/OIDC 연결 준비

## 범위

실제로 생성한 sky-builder 저장소의 immutable ID로 app-builder OIDC 역할을 만들 수 있도록 한다.
worker에 build consumer가 요구하는 App installation ID와 코드 pin을 전달한다.
API의 github_app_id는 변경하지 않는다. builder 전용 App은 소스 감시용 App과 설치 범위가 다르다.
개인 키 값은 Git에 저장하지 않으며 기존 sky-dev/github-app-private-key 실행 비밀을 사용한다.
현재 API도 같은 비밀 ARN을 참조하므로 API 소스 감시용 App을 활성화할 때 별도 비밀 분리가 필요하다.

Secrets Manager PEM을 메모리에서 읽어 App installation token을 발급하고,
sky-builder 저장소/고정 commit/build.yml workflow를 읽기 전용으로 조회하는 검증이 통과했다.
토큰/PEM을 출력하지 않았으며 workflow dispatch는 하지 않았다.

## 적용 시 검토

- builder.auto.tfvars는 dev의 비밀 아닌 실제 ID/code pin이다. 서비스 이미지 7자리 태그와 구분한다.
- app-builder trust: repo:SoftBank-Hydrogen@338183202/sky-builder@1413419159:ref:refs/heads/main.
- builder workflow는 build.yml이다. 기존 build.yaml 입력을 맞춘다.
- builder variables의 SKY_PLATFORM_CODE_SHA와 builder_platform_code_sha를 함께 갱신한다.
- SKY_BUILDER_WORKFLOW는 현재 플랫폼에서 기본 build.yml과 같은 값이다. 다른 파일 지원을 가정하지 않는다.
- 전체 terraform plan을 검토하고 담당자와 apply한다. 새 역할 생성과 worker 환경변수 갱신이 포함된다.
- apply 후 sky-dev-app-builder ARN/trust/정책을 확인하고 builder 변수 AWS_APP_BUILDER_ROLE_ARN을 넣는다.
- 이 환경변수 변경은 이미지 외 변경이므로 서비스 이미지 전용 자동 배포가 대신 적용하지 않는다.
  후속 이미지 PR의 plan 검사도 전체 apply 전까지 환경변수 차이로 실패할 수 있다.

## 실행 활성화는 별도

이 PR은 worker_command(outbox), 워커 최소 실행 수(0), API 명령을 바꾸지 않는다.
별도 상시 outbox publisher(최소 1개)와 SQS 기반 build consumer 서비스 분리를 먼저 구성해야 한다.
현재 worker를 build로만 바꾸면 DB outbox를 SQS에 최초 발행할 프로세스가 사라진다.
최신 서비스 이미지와 DB 마이그레이션도 필요하다. 이 PR에서 운영 apply/DB 변경은 하지 않는다.

검증된 사용자 앱 이미지 준비 후에는 build_ready/awaiting_deployment에서 정지한다.
실제 ECS 배포 실행기와 안전 재개 계약은 다음 플랫폼 작업이다.
