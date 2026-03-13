#!/bin/bash
# ============================================================
#  setup.sh — 동시성과 병렬 프로그래밍을 위한 운영체제
#  GitHub 레포지토리 생성 & 첫 Push 자동화 스크립트
#  사용법: bash setup.sh
# ============================================================

set -e  # 에러 발생 시 즉시 중단

# ── 색상 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_step() { echo -e "\n${BOLD}${BLUE}▶ $1${RESET}"; }
print_ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
print_warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
print_err()  { echo -e "${RED}✗ $1${RESET}"; }

# ── 헤더 ──────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   동시성과 병렬 프로그래밍을 위한 운영체제       ║"
echo "║   GitHub Repository Setup Script                ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── 사전 체크 ─────────────────────────────────────────
print_step "사전 환경 확인"

# git 확인
if ! command -v git &>/dev/null; then
    print_err "git이 설치되어 있지 않습니다."
    echo "  → https://git-scm.com/downloads 에서 설치 후 재실행하세요."
    exit 1
fi
print_ok "git $(git --version | awk '{print $3}')"

# gh CLI 확인
if ! command -v gh &>/dev/null; then
    print_warn "GitHub CLI(gh)가 없습니다. 수동 방법을 안내합니다."
    USE_GH=false
else
    print_ok "GitHub CLI $(gh --version | head -1 | awk '{print $3}')"
    USE_GH=true
fi

# 현재 디렉토리 확인
if [ ! -f "README.md" ] || [ ! -d "Playgrounds" ]; then
    print_err "이 스크립트는 concurrency-os-playground 폴더 안에서 실행해야 합니다."
    echo "  현재 위치: $(pwd)"
    exit 1
fi
print_ok "레포 루트 디렉토리 확인됨"

# ── Git 초기화 ────────────────────────────────────────
print_step "Git 초기화"

if [ ! -d ".git" ]; then
    git init
    git branch -m main
    print_ok "Git 저장소 초기화 (main 브랜치)"
else
    print_ok "이미 Git 저장소입니다"
fi

# git user 설정 확인
if [ -z "$(git config user.email)" ]; then
    echo -e "\n${YELLOW}Git 사용자 정보를 입력하세요:${RESET}"
    read -p "  이메일: " GIT_EMAIL
    read -p "  이름: " GIT_NAME
    git config user.email "$GIT_EMAIL"
    git config user.name "$GIT_NAME"
    print_ok "Git 사용자 설정 완료"
fi

# ── 첫 커밋 ───────────────────────────────────────────
print_step "첫 커밋 생성"

git add -A

# 이미 커밋이 있으면 스킵
if git rev-parse HEAD &>/dev/null 2>&1; then
    print_ok "이미 커밋이 존재합니다"
else
    git commit -m "🚀 init: 동시성과 병렬 프로그래밍을 위한 운영체제

- 11 Units Xcode Playground (Thread~Combine)
- GitHub Pages index.html
- README.md with curriculum table

개발자리 iOS Developer Series"
    print_ok "첫 커밋 완료"
fi

# ── GitHub 레포 생성 & Push ───────────────────────────
print_step "GitHub 레포지토리 생성"

REPO_NAME="concurrency-os-playground"

if [ "$USE_GH" = true ]; then
    # gh CLI로 자동 생성
    echo ""
    echo -e "${BOLD}레포지토리 설정:${RESET}"
    read -p "  공개 여부 (public/private) [public]: " VISIBILITY
    VISIBILITY="${VISIBILITY:-public}"

    read -p "  설명 (Enter 스킵): " DESCRIPTION
    DESCRIPTION="${DESCRIPTION:-동시성과 병렬 프로그래밍을 위한 운영체제 — iOS 개발자 Playground 모음}"

    # gh 로그인 확인
    if ! gh auth status &>/dev/null; then
        echo -e "\n${YELLOW}GitHub 로그인이 필요합니다.${RESET}"
        gh auth login
    fi

    # 레포 생성 (이미 존재하면 연결만)
    if gh repo view "$REPO_NAME" &>/dev/null 2>&1; then
        print_warn "레포지토리가 이미 존재합니다. 연결합니다."
        GITHUB_USER=$(gh api user --jq '.login')
        git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git" 2>/dev/null || \
            git remote set-url origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
    else
        gh repo create "$REPO_NAME" \
            --"$VISIBILITY" \
            --description "$DESCRIPTION" \
            --source=. \
            --remote=origin \
            --push
        print_ok "GitHub 레포지토리 생성 완료"
    fi

    # Push
    git push -u origin main
    print_ok "Push 완료"

    # GitHub Pages 활성화
    echo ""
    GITHUB_USER=$(gh api user --jq '.login')
    gh api repos/$GITHUB_USER/$REPO_NAME/pages \
        -X POST \
        -f source='{"branch":"main","path":"/docs"}' \
        --silent 2>/dev/null && \
        print_ok "GitHub Pages 활성화됨 (docs/ 폴더)" || \
        print_warn "GitHub Pages는 수동으로 활성화하세요 (Settings → Pages → docs/)"

    # 결과 출력
    echo -e "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}✅ 완료!${RESET}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  📦 레포:  ${CYAN}https://github.com/$GITHUB_USER/$REPO_NAME${RESET}"
    echo -e "  🌐 Pages: ${CYAN}https://$GITHUB_USER.github.io/$REPO_NAME${RESET}"
    echo -e "  ${YELLOW}(Pages 배포는 1~3분 소요됩니다)${RESET}"

else
    # ── gh CLI 없음 → 수동 안내 ─────────────────────────
    echo -e "\n${BOLD}GitHub CLI가 없어 수동으로 진행합니다.${RESET}"
    echo ""
    echo -e "${BOLD}Step 1.${RESET} 아래 링크에서 새 레포를 만드세요:"
    echo -e "  ${CYAN}https://github.com/new${RESET}"
    echo -e "  - Repository name: ${BOLD}$REPO_NAME${RESET}"
    echo -e "  - Public or Private 선택"
    echo -e "  - README, .gitignore ${RED}체크 해제${RESET} (이미 있음)"
    echo ""
    echo -e "${BOLD}Step 2.${RESET} 레포 생성 후 아래 명령어를 실행하세요"
    echo -e "  (your-username을 본인 GitHub ID로 교체):"
    echo ""
    echo -e "  ${CYAN}git remote add origin https://github.com/your-username/$REPO_NAME.git${RESET}"
    echo -e "  ${CYAN}git push -u origin main${RESET}"
    echo ""
    echo -e "${BOLD}Step 3.${RESET} GitHub Pages 활성화:"
    echo -e "  레포 Settings → Pages → Branch: main, Folder: /docs → Save"
    echo ""
    echo -e "  🌐 배포 URL: ${CYAN}https://your-username.github.io/$REPO_NAME${RESET}"

    # origin URL 입력 받기 (선택)
    echo ""
    read -p "지금 바로 remote URL을 입력하시겠습니까? (y/N): " DO_REMOTE
    if [[ "$DO_REMOTE" =~ ^[Yy]$ ]]; then
        read -p "GitHub 레포 URL (https://github.com/...git): " REMOTE_URL
        git remote add origin "$REMOTE_URL" 2>/dev/null || \
            git remote set-url origin "$REMOTE_URL"
        print_ok "Remote 설정: $REMOTE_URL"

        echo ""
        read -p "지금 Push 하시겠습니까? (y/N): " DO_PUSH
        if [[ "$DO_PUSH" =~ ^[Yy]$ ]]; then
            git push -u origin main
            print_ok "Push 완료!"
        fi
    fi
fi

echo ""
echo -e "${BOLD}레포 구조:${RESET}"
echo "  concurrency-os-playground/"
echo "  ├── README.md"
echo "  ├── docs/index.html          ← GitHub Pages 사이트"
echo "  └── Playgrounds/"
echo "      ├── Unit01_ThreadVsProcess.playground/"
echo "      ├── Unit02_GCDBasics.playground/"
echo "      ├── ...                   (11개 Unit)"
echo "      └── Unit11_CombineAdvanced.playground/"
echo ""
