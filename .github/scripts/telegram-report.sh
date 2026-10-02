#!/usr/bin/env bash
set -u

STATUS="${1:-failure}"
ZIP_NAME="${2:-}"
KERNEL_VERSION="${3:-unknown}"
BUILD_DURATION="${4:-unknown}"
IMAGE_SHA256="${5:-unknown}"

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
THREAD_ID="${TELEGRAM_MESSAGE_THREAD_ID:-}"

# ---------------------------------------------------------
# Telegram disabled / not configured
# ---------------------------------------------------------

if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    echo "[Telegram] Not configured. Skipping."
    exit 0
fi

# ---------------------------------------------------------
# Mask secrets in GitHub Actions
# ---------------------------------------------------------

echo "::add-mask::${BOT_TOKEN}"
echo "::add-mask::${CHAT_ID}"

if [[ -n "$THREAD_ID" ]]; then
    echo "::add-mask::${THREAD_ID}"
fi

API="https://api.telegram.org/bot${BOT_TOKEN}"

REPO="${GITHUB_REPOSITORY:-unknown}"
RUN_ID="${GITHUB_RUN_ID:-0}"

RUN_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"

# ---------------------------------------------------------
# Send Telegram message
# ---------------------------------------------------------

send_message() {
    local message="$1"

    local args=(
        -sS
        --fail
        --connect-timeout 10
        --max-time 30
        -X POST
        "${API}/sendMessage"
        --data-urlencode "chat_id=${CHAT_ID}"
        --data-urlencode "text=${message}"
    )

    if [[ -n "$THREAD_ID" ]]; then
        args+=(--data-urlencode "message_thread_id=${THREAD_ID}")
    fi

    if ! curl "${args[@]}" >/dev/null; then
        echo "[Telegram] Failed to send message."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------
# Send file
# ---------------------------------------------------------

send_file() {
    local file="$1"

    [[ -f "$file" ]] || {
        echo "[Telegram] File not found: ${file}"
        return 0
    }

    local args=(
        -sS
        --fail
        --connect-timeout 10
        --max-time 120
        -X POST
        "${API}/sendDocument"
        -F "chat_id=${CHAT_ID}"
        -F "document=@${file}"
    )

    if [[ -n "$THREAD_ID" ]]; then
        args+=(-F "message_thread_id=${THREAD_ID}")
    fi

    if ! curl "${args[@]}" >/dev/null; then
        echo "[Telegram] Failed to send file."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------
# Check bot token
# ---------------------------------------------------------

if ! curl -sS --fail --connect-timeout 10 --max-time 20 \
    "${API}/getMe" >/dev/null; then

    echo "[Telegram] Bot token is invalid or Telegram API is unavailable."
    exit 0
fi

# ---------------------------------------------------------
# SUCCESS
# ---------------------------------------------------------

if [[ "$STATUS" == "success" ]]; then

    MESSAGE="✅ NoobieKernelRE build succeeded

Kernel: ${KERNEL_VERSION}
GPU/package: ${ZIP_NAME}
Duration: ${BUILD_DURATION}
Image SHA256: ${IMAGE_SHA256}

Repository:
${REPO}

Build:
${RUN_URL}"

    send_message "$MESSAGE" || true

    if [[ -n "$ZIP_NAME" && -f "$ZIP_NAME" ]]; then
        send_file "$ZIP_NAME" || true
    fi

# ---------------------------------------------------------
# FAILURE
# ---------------------------------------------------------

else

    MESSAGE="❌ NoobieKernelRE build failed

Kernel: ${KERNEL_VERSION}
Duration: ${BUILD_DURATION}

Repository:
${REPO}

Build:
${RUN_URL}

The complete build log is attached."

    send_message "$MESSAGE" || true

fi

echo "[Telegram] Report completed."
exit 0
