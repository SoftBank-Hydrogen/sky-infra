# 서비스 서버(sky-platform) 이미지 태그. 7자리 git SHA. API와 워커가 같은 이미지를 쓴다.
# 이 파일만 바꾼 PR이 main에 머지되면 .github/workflows/deploy.yaml이 태스크 정의와 ECS 서비스만 적용한다.
# 태그에 해당하는 이미지가 ECR sky-platform 레포에 먼저 있어야 한다.
# 0000000은 자리표시자다. 첫 apply 전에 실제 SHA로 바꾼다 (README "처음 한 번").
platform_image_tag = "71eb4b2"
