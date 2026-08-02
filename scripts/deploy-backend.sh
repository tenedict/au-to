#!/usr/bin/env bash
# 백엔드를 Cloud Run(서울)에 배포한다.
#
#   ./scripts/deploy-backend.sh
#
# 처음 한 번은 사람이 해야 하는 일이 있다. 스크립트가 무엇이 빠졌는지 알려 준다.
# 조용히 넘어가지 않는다 — 반쯤 설정된 채로 배포되면 401 과 500 을 구분하지 못한다.

set -uo pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'

SERVICE="${WHENLY_SERVICE:-whenly-backend}"
REGION="${WHENLY_REGION:-asia-northeast3}"   # 서울
# 인스턴스가 늘면 하루 한도가 인스턴스 수만큼 곱해진다. 금액 상한을 확정하려면 여기를 고정한다.
MAX_INSTANCES="${WHENLY_MAX_INSTANCES:-2}"

step() { printf '\n%s▸ %s%s\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '%s  ✓ %s%s\n' "$GRN" "$1" "$OFF"; }
die()  { printf '\n%s✕ %s%s\n' "$RED" "$1" "$OFF"; [ $# -gt 1 ] && printf '%s\n' "$2"; exit 1; }

# ── 준비물 ──────────────────────────────────────────────────
step "준비물"
command -v gcloud >/dev/null 2>&1 || die "gcloud 가 없습니다" "  brew install --cask google-cloud-sdk"
ok "gcloud"

ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
[ -n "$ACCOUNT" ] || die "gcloud 로그인이 필요합니다" "  gcloud auth login"
ok "계정 $ACCOUNT"

PROJECT="${WHENLY_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[ -n "$PROJECT" ] && [ "$PROJECT" != "(unset)" ] || \
  die "프로젝트가 정해져 있지 않습니다" "  gcloud config set project <PROJECT_ID>"
ok "프로젝트 $PROJECT"

# 토큰이 만료돼 있으면 아래 명령들이 각자 다른 방식으로 실패한다. 여기서 한 번에 잡는다.
gcloud projects describe "$PROJECT" >/dev/null 2>&1 || \
  die "인증이 만료됐거나 프로젝트에 접근할 수 없습니다" "  gcloud auth login"
ok "인증 유효"

# ── 비밀 ────────────────────────────────────────────────────
step "비밀"
for secret in OPENAI_API_KEY WHENLY_CLIENT_KEY; do
  if gcloud secrets describe "$secret" --project "$PROJECT" >/dev/null 2>&1; then
    ok "$secret"
  else
    printf '%s  ✕ %s 가 없습니다%s\n' "$RED" "$secret" "$OFF"
    cat <<EOF

  만들기:
    # OpenAI 키
    printf '%s' "sk-proj-실제키" | \\
      gcloud secrets create OPENAI_API_KEY --data-file=- --project $PROJECT

    # 앱과 서버가 나눠 갖는 공유 비밀 (앱 번들에도 들어갑니다)
    printf '%s' "\$(openssl rand -base64 32)" | \\
      gcloud secrets create WHENLY_CLIENT_KEY --data-file=- --project $PROJECT

    # 만든 값 확인 — config/apple/Secrets.xcconfig 에 같은 값을 넣어야 합니다
    gcloud secrets versions access latest --secret WHENLY_CLIENT_KEY --project $PROJECT

EOF
    exit 1
  fi
done

# ── API ─────────────────────────────────────────────────────
step "필요한 API"
for api in run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com; do
  if gcloud services list --enabled --project "$PROJECT" --filter="config.name=$api" \
       --format='value(config.name)' 2>/dev/null | grep -q "$api"; then
    ok "$api"
  else
    printf '%s  … %s 켜는 중%s\n' "$DIM" "$api" "$OFF"
    gcloud services enable "$api" --project "$PROJECT" || die "$api 를 켜지 못했습니다"
    ok "$api"
  fi
done

# ── 비밀 읽기 권한 ──────────────────────────────────────────
# Cloud Run 이 도는 서비스 계정에 secretAccessor 를 주지 않으면 컨테이너 빌드까지
# 다 끝난 뒤 마지막 리비전 생성에서 죽는다. 빌드가 성공해서 다 된 것처럼 보이다가
# 끝에 실패하므로, 원인을 찾는 데 시간이 가장 많이 든다. 미리 준다.
step "비밀 읽기 권한"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for secret in OPENAI_API_KEY WHENLY_CLIENT_KEY; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:$RUNTIME_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --project "$PROJECT" >/dev/null 2>&1 \
    && ok "$secret → $RUNTIME_SA" \
    || die "$secret 에 권한을 주지 못했습니다"
done

# ── 배포 ────────────────────────────────────────────────────
step "배포 ($REGION)"
gcloud run deploy "$SERVICE" \
  --source server \
  --project "$PROJECT" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances "$MAX_INSTANCES" \
  --min-instances 0 \
  --memory 512Mi \
  --cpu 1 \
  --timeout 30s \
  --set-secrets "OPENAI_API_KEY=OPENAI_API_KEY:latest,WHENLY_CLIENT_KEY=WHENLY_CLIENT_KEY:latest" \
  --set-env-vars "HOST=0.0.0.0" \
  || die "배포 실패"

# `--allow-unauthenticated` 는 "구글 IAM 인증을 요구하지 않는다"는 뜻이다.
# 우리 인증은 그 위에서 X-Whenly-Key 헤더로 한다. IAM 을 켜면 앱이 구글
# 토큰을 들고 다녀야 해서 이 제품에는 맞지 않는다.

URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(status.url)')

# ── 확인 ────────────────────────────────────────────────────
step "확인"
HEALTH=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$URL/health")
[ "$HEALTH" = "200" ] && ok "/health 200" || die "/health 가 $HEALTH 를 돌려줬습니다"

NOKEY=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -X POST "$URL/v1/analyze-capture" \
  -H 'Content-Type: application/json' -d '{"recognized_text":"확인"}')
if [ "$NOKEY" = "401" ]; then
  ok "키 없는 요청 401 (인증이 실제로 켜져 있습니다)"
else
  die "키 없는 요청이 $NOKEY 를 돌려줬습니다 — 인증이 걸려 있지 않습니다!" \
      "  WHENLY_CLIENT_KEY 가 서비스에 주입됐는지 확인하세요."
fi

printf '\n%s%s배포 완료%s\n' "$GRN" "$BLD" "$OFF"
printf '  %s\n\n' "$URL"
cat <<EOF
${BLD}앱에 연결하기${OFF}
  1. cp config/apple/Secrets.xcconfig.example config/apple/Secrets.xcconfig   (없으면)
  2. config/apple/Secrets.xcconfig 를 열어 채웁니다

       WHENLY_HOST = ${URL#https://}
       WHENLY_CLIENT_KEY = <아래 명령의 출력>

     ${DIM}gcloud secrets versions access latest --secret WHENLY_CLIENT_KEY --project $PROJECT${OFF}

  3. xcodegen generate && 빌드

${YEL}남은 것${OFF}
  · 한도는 인스턴스마다 따로 셉니다. --max-instances $MAX_INSTANCES 가 실제 금액 상한입니다
  · OpenAI 계정 쪽에도 사용량 한도를 걸어 두세요. 마지막 방어선입니다
EOF
