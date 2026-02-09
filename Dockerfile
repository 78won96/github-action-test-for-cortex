# Dockerfile 이라는 이름으로 새 파일을 만들고 아래 내용 복사
FROM ubuntu:latest
# 취약점: 루트(Root) 권한으로 모든 것을 실행함
USER root
# 취약점: 보안 업데이트를 하지 않고 오래된 패키지 사용
RUN apt-get update && apt-get install -y telnet

