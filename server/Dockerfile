# Whenly 백엔드 — Cloud Run 용.
#
# 외부 패키지가 0개라 `npm install` 도 lockfile 도 없습니다. 소스만 복사하면 끝입니다.
# 그래서 빌드 캐시 계층을 나눌 이유도 없습니다.

FROM node:22-alpine

# 루트로 돌리지 않습니다. 이미지에 이미 있는 node 사용자를 씁니다.
WORKDIR /app
COPY package.json ./
COPY src ./src
USER node

# Cloud Run 은 PORT 를 주입하고 0.0.0.0 바인딩을 요구합니다.
# HOST 가 루프백이면 컨테이너 밖에서 닿지 못해 배포가 조용히 죽습니다.
ENV HOST=0.0.0.0
ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "src/server.mjs"]
