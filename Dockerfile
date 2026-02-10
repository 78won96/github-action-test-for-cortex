# ============================================================
# 취약점 검사 테스트용 Dockerfile (Cortex 이미지 스캔 검증용)
# 프로덕션 환경에서는 사용하지 마세요.
# ============================================================

# 취약점 테스트: 오래된 베이스 이미지 사용 (알려진 CVE 다수)
FROM ubuntu:18.04

# 취약점: Root 권한으로 실행
USER root

# 취약점: 보안 업데이트를 적용하지 않음 (기본 레포지토리의 오래된 패키지 유지)
RUN apt-get update && apt-get install -y --no-install-recommends \
    telnet \
    openssh-client \
    curl \
    wget \
    libcurl4 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 취약점: 불필요하게 넓은 권한 (테스트용)
RUN chmod 777 /tmp 2>/dev/null || true

# 스캔 테스트용 더미 파일 (실제 서비스는 index.html 등으로 대체 가능)
RUN echo "Vulnerability scan test image" > /app.txt
WORKDIR /

# 참고: ubuntu:18.04 EOL로 인해 더 많은 CVE가 보고될 수 있음.
# 테스트 후 프로덕션용은 ubuntu:22.04/24.04 + apt-get upgrade 적용 권장.
