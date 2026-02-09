# Docker 이미지 ECR 푸시 및 EC2 배포 (워크플로 분리)

**github-action-test-for-cortex** 리포지토리에서는 워크플로를 두 개로 나눕니다.

| 워크플로 | 파일 | 역할 |
|----------|------|------|
| **Build and Push to ECR** | `build-push-ecr.yml` | Dockerfile로 이미지 빌드 후 **AWS ECR에 push** |
| **Scan and Deploy to EC2** | `main.yml` | Cortex 보안 스캔 후 EC2에서 **ECR에 push된 이미지를 pull → docker run** |

---

## 전체 흐름

1. 코드(및 Dockerfile)를 **GitHub `github-action-test-for-cortex` 리포지토리에 push**
2. **build-push-ecr.yml** 실행: 이미지 빌드 → ECR에 push (`latest` 및 커밋 SHA 태그)
3. **main.yml** 실행: Cortex 스캔 → EC2에 SSH 접속 → ECR 로그인 → **ECR 이미지 pull** → **docker run**으로 배포

두 워크플로는 모두 `main` 브랜치 push 시 트리거됩니다. main.yml이 ECR의 `latest` 이미지를 사용하므로, 배포 직전에 build-push-ecr이 완료되어 있으면 방금 빌드한 이미지가 배포됩니다. (동시 실행 시에는 이전에 push된 `latest`가 pull될 수 있음.)

---

## 1. build-push-ecr.yml — 이미지를 ECR에 push

### 역할

- 리포지토리 체크아웃
- AWS 자격 증명 설정 → ECR 로그인
- `docker build` → ECR 주소로 태그 → `docker push`

### 파일 위치

- **실제 동작용**: `.github/workflows/build-push-ecr.yml`  
  (이 경로에 있어야 GitHub Actions가 실행함)
- **참고/백업용**: 프로젝트 루트의 `build-push-ecr.yml`을 위 경로로 복사해 사용

### 필요한 GitHub Secrets

| Secret | 설명 |
|--------|------|
| `AWS_ACCESS_KEY_ID` | ECR에 push 가능한 IAM 사용자 Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | 해당 IAM 사용자 Secret Access Key |

### 워크플로 요약

- **트리거**: `main` push, `workflow_dispatch`(수동)
- **이미지 태그**: `latest`, `${{ github.sha }}`
- **env**: `AWS_REGION`, `ECR_REPOSITORY` (필요 시 수정)

---

## 2. main.yml — ECR 이미지로 EC2에서 docker run

### 역할

1. **security-scan**: Cortex CLI로 코드 스캔
2. **deploy**: EC2에 SSH 접속 후  
   - 기존 `my-web-server` 컨테이너 중지/삭제  
   - **ECR 로그인** → **ECR 이미지 pull** → **docker run** (포트 80)

즉, **build-push-ecr에서 ECR에 push한 이미지**를 EC2에서 pull해서 실행합니다.

### 파일 위치

- `.github/workflows/main.yml`

### Deploy에 필요한 설정

- **GitHub Secrets**: `EC2_HOST`, `EC2_SSH_KEY` (기존), **`AWS_ACCOUNT_ID`** (ECR 주소 구성용, 예: `123456789012`)
- **env**: `AWS_REGION`, `ECR_REPOSITORY` (main.yml 상단 env에 정의됨)

### EC2 측 요구사항

- Docker, AWS CLI 설치
- **ECR에서 이미지를 pull할 수 있는 자격 증명**  
  - 권장: EC2 **IAM 인스턴스 프로파일**에 `ecr:GetAuthorizationToken`, `ecr:BatchGetImage` 등 ECR 읽기 권한 부여  
  - 또는 EC2에 AWS 자격 증명 설정 후 `aws ecr get-login-password` 사용

---

## 3. 사전 준비 (한 번만)

### 3.1 AWS ECR 저장소 생성

```bash
aws ecr create-repository \
  --repository-name github-action-test-for-cortex \
  --region ap-northeast-2
```

### 3.2 GitHub Secrets 설정

리포지토리 **Settings → Secrets and variables → Actions**에서 등록:

| Secret | 사용 워크플로 | 설명 |
|--------|----------------|------|
| `AWS_ACCESS_KEY_ID` | build-push-ecr | ECR push용 IAM Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | build-push-ecr | 해당 IAM Secret Access Key |
| `AWS_ACCOUNT_ID` | main | ECR 레지스트리 주소용 (예: `123456789012`) |
| `EC2_HOST` | main | 배포 대상 EC2 호스트 |
| `EC2_SSH_KEY` | main | EC2 SSH 비밀키 |
| `CORTEX_API_KEY` | main | Cortex 스캔용 (기존) |
| `CORTEX_API_KEY_ID` | main | Cortex 스캔용 (기존) |

### 3.3 GitHub에 코드 푸시

```bash
git add .
git commit -m "Add Dockerfile and workflows"
git push origin main
```

- **build-push-ecr**를 사용하려면 `.github/workflows/build-push-ecr.yml`이 포함되어 있어야 합니다.  
  루트의 `build-push-ecr.yml`을 복사해 두었으면:

  ```bash
  cp build-push-ecr.yml .github/workflows/build-push-ecr.yml
  git add .github/workflows/build-push-ecr.yml
  git commit -m "Add ECR build-push workflow"
  git push origin main
  ```

---

## 4. 실행 순서 요약

- **build-push-ecr.yml**: push 시 이미지 빌드 후 ECR에 push.
- **main.yml**: push 시 스캔 후 EC2에서 ECR 이미지(`latest`)를 pull해 docker run.

같은 push에 두 워크플로가 모두 돌면, main의 deploy가 먼저 끝나면 **이전에 ECR에 올라간 `latest`**가 배포될 수 있습니다. **방금 빌드한 이미지**를 배포하려면:

- build-push-ecr을 먼저 실행한 뒤, main을 수동 실행하거나  
- main.yml을 **workflow_run**으로 “Build and Push to ECR” 완료 후에만 실행되도록 바꿀 수 있습니다.

---

## 5. 참고

- **리전**: 예시는 `ap-northeast-2`(서울). `build-push-ecr.yml`과 `main.yml`의 `AWS_REGION`을 사용 중인 리전에 맞게 수정하세요.
- **계정 ID 확인**: `aws sts get-caller-identity --query Account --output text`
- **ECR 이미지 확인**: AWS 콘솔 → ECR → 해당 리포지토리에서 `latest` 및 SHA 태그 확인.
