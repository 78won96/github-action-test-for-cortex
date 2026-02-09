# Docker 이미지 빌드·Cortex 스캔·ECR 푸시 및 EC2 배포

**github-action-test-for-cortex** 리포지토리는 **단일 워크플로** `main.yml`로 다음을 수행합니다.

- Docker 이미지 빌드 → **Cortex CLI로 이미지 스캔** → ECR 푸시  
- 이어서 EC2에서 ECR 이미지 pull → **동일 이미지 Cortex 스캔** → docker run

---

## 워크플로 개요

| 항목 | 내용 |
|------|------|
| **파일** | `.github/workflows/main.yml` |
| **이름** | Build, Scan, Push to ECR and Deploy to EC2 |
| **트리거** | `main` 브랜치 push, `workflow_dispatch`(수동) |

---

## 전체 흐름

1. **build-scan-push** job (GitHub Actions runner)
   - Checkout → **이미지 빌드** (`ECR_REPOSITORY:build`)
   - Java 11 설치 → libhyperscan5 설치 (cortexcli 의존성)
   - Cortex CLI 다운로드 → **빌드된 이미지 스캔** (`image scan`)
   - AWS 자격 증명 → ECR 로그인 → 이미지 태그 및 **ECR 푸시** (`latest`, 커밋 SHA)

2. **deploy** job (`needs: build-scan-push`, EC2에서 스크립트 실행)
   - 기존 `my-web-server` 컨테이너 정리
   - ECR 로그인 → **이미지 pull** (`latest`)
   - Cortex CLI 설치(Java, libhyperscan5, jq) → **Pull한 이미지 스캔**
   - 스캔 통과 후 **docker run** (포트 80)

즉, **리포지토리**는 빌드·스캔·푸시만 하고, **EC2**는 pull·스캔·실행만 담당합니다.

---

## Job 1: build-scan-push

### 역할

- Dockerfile로 이미지 빌드
- **Cortex CLI image scan**으로 빌드된 이미지 스캔 (리포지토리 디렉터리 스캔 아님)
- 스캔 통과 시 ECR에 푸시

### Runner 요구사항 (워크플로에서 처리)

- Java 11 이상 → `actions/setup-java@v4` (Temurin 11)
- `libhs.so.5` → `libhyperscan5` 패키지 설치
- Cortex CLI → API로 다운로드 (`signed_url`, `file_name` 사용)

### 사용 env / secrets

- **env**: `AWS_REGION`, `ECR_REPOSITORY`, `CORTEX_API_URL`, `CORTEX_API_KEY`, `CORTEX_API_KEY_ID`
- **secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

---

## Job 2: deploy

### 역할

- EC2에 SSH 접속 후:
  1. 기존 컨테이너 정리
  2. ECR 로그인 → **docker pull** (`latest`)
  3. **Cortex CLI로 Pull한 이미지 스캔** (`image scan <ECR_IMAGE>`)
  4. 스캔 통과 후 `docker run`으로 배포

### EC2에서 필요한 것

- Docker, AWS CLI
- ECR pull 권한 (IAM 인스턴스 프로파일 또는 AWS 자격 증명)
- Cortex CLI 실행을 위한 패키지: **Java 11+**, **libhyperscan5**, **jq**  
  → 스크립트에서 `apt-get`으로 설치 시도 (`openjdk-11-jre-headless`, `libhyperscan5`, `jq`)

### 사용 env / secrets

- **env**: `AWS_REGION`, `ECR_REPOSITORY`, `CORTEX_API_URL` (스크립트에 치환되어 전달)
- **secrets**: `EC2_HOST`, `EC2_SSH_KEY`, `AWS_ACCOUNT_ID`, `CORTEX_API_KEY`, `CORTEX_API_KEY_ID`  
  (EC2는 GitHub에 접근할 수 없으므로, 스크립트 안에서 위 값들이 runner에서 치환된 뒤 EC2에서 사용됨)

---

## 사전 준비

### 1. AWS ECR 저장소 생성 (최초 1회)

```bash
aws ecr create-repository \
  --repository-name github-action-test-for-cortex \
  --region ap-northeast-2
```

### 2. GitHub Secrets 설정

리포지토리 **Settings → Secrets and variables → Actions**에서 등록:

| Secret | 사용처 | 설명 |
|--------|--------|------|
| `AWS_ACCESS_KEY_ID` | build-scan-push | ECR 푸시용 IAM Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | build-scan-push | 해당 IAM Secret Access Key |
| `AWS_ACCOUNT_ID` | deploy (EC2 스크립트) | ECR 레지스트리 주소 구성 (예: `123456789012`) |
| `EC2_HOST` | deploy | 배포 대상 EC2 호스트 |
| `EC2_SSH_KEY` | deploy | EC2 SSH 비밀키 |
| `CORTEX_API_KEY` | build-scan-push, deploy | Cortex API 키 (CLI 다운로드·이미지 스캔) |
| `CORTEX_API_KEY_ID` | build-scan-push, deploy | Cortex API 키 ID |

### 3. 워크플로 env (main.yml 상단)

- `AWS_REGION`: 예) `ap-northeast-2`
- `ECR_REPOSITORY`: 예) `github-action-test-for-cortex`
- `CORTEX_API_URL`: Cortex API URL (예: `https://api-u-infra-260126-xdr.xdr.sg.paloaltonetworks.com`)
- `CORTEX_API_KEY`, `CORTEX_API_KEY_ID`: secrets 참조

### 4. GitHub에 코드 푸시

```bash
git add .
git commit -m "Add Dockerfile and workflow"
git push origin main
```

`main` push 시 위 워크플로가 한 번에 실행됩니다.

---

## 실행 순서 요약

1. **build-scan-push**  
   빌드 → (Java, libhyperscan5, Cortex CLI 준비) → **이미지 스캔** → ECR 푸시  
2. **deploy** (build-scan-push 성공 후)  
   EC2에서 pull → **이미지 스캔** → docker run  

같은 이미지가 runner에서 한 번, EC2에서 한 번 Cortex CLI `image scan`으로 검사됩니다.

---

## 참고

- **리전**: 예시는 `ap-northeast-2`(서울). `main.yml`의 `AWS_REGION`을 사용 중인 리전에 맞게 수정하세요.
- **계정 ID 확인**: `aws sts get-caller-identity --query Account --output text`
- **ECR 이미지**: AWS 콘솔 → ECR → 해당 리포지토리에서 `latest` 및 커밋 SHA 태그 확인.
- **EC2 OS**: deploy 스크립트의 패키지 설치(`apt-get`)는 **Ubuntu** 기준입니다. Amazon Linux 2 등이면 `yum`/`dnf` 및 패키지 이름을 맞춰 수정해야 합니다.
