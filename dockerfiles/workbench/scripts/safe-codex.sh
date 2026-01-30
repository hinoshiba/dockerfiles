#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_codex_safe.sh
#
# 要件:
# - IMAGE は定数
# - workdir(コンテナ内)はホスト current directory の絶対パスと同一
# - ~/.codex を writable mount（current user の HOME 配下）
# - ~/.codex-cstm/preagent.md を <workdir>/AGENT.md に overlay（ホストは変更しない）
# - ~/.codex-cstm/.codexignore に従い不可視化 mount を追加（file=/dev/null, dir=空dir）
#
# - ./.codex-build が存在する場合:
#   1) まず “codex コンテナ内で” ./.codex-build を bash 実行（ENTRYPOINT を一時的に /bin/bash に差し替え）
#   2) その後 “ENTRYPOINT に戻して” 通常起動（= entrypoint を上書きしない起動）し、codex を実行
#
# - ユーザー作成などはカスタムイメージ側が担当する前提
#   HOST_USER / HOST_GROUP / HOST_UID / HOST_GID を env で渡すだけ
#
# ============================================================
# ~/.codex-cstm/.codexignore の書き方（ホスト filesystem 基準）
#
# (A) 相対 path（実行時の current directory 基準）
#   ./secrets
#   ./.env
#   config/private.yaml
#
# (B) glob（bash glob / current directory 基準）
#   **/.env
#   secrets/*.pem
#
# (C) 絶対 path（ホスト絶対パス）
#   /home/you/repo/.env
#   /home/you/repo/secrets
#
# 注:
# - current directory しか mount しないため、プロジェクト外の絶対パスは
#   そもそもコンテナに見えないなら効果不要。ただし指定自体は許可する。
# ============================================================

# -----------------------------
# 固定設定（ここだけ編集）
# -----------------------------
IMAGE="myorg/codex:custom"   # <- あなたのカスタム codex イメージ
# -----------------------------

PROJECT_ROOT="$(pwd)"                    # 絶対パス
WORKDIR_IN_CONTAINER="${PROJECT_ROOT}"   # コンテナ内も同じ絶対パス

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"
HOST_GROUP="$(id -gn)"
HOST_HOME="${HOME}"

CODEX_CSTM_DIR="${HOST_HOME}/.codex-cstm"
CODEXIGNORE_FILE="${CODEX_CSTM_DIR}/.codexignore"
PREAGENT_FILE="${CODEX_CSTM_DIR}/preagent.md"
HOST_CODEX_DIR="${HOST_HOME}/.codex"

TMP_DIRS=()
TMP_FILES=()

cleanup() {
  local rc=$?
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f:-}" && -e "$f" ]] && rm -f -- "$f" || true
  done
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "${d:-}" && -d "$d" ]] && rm -rf -- "$d" || true
  done
  exit $rc
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found" >&2; exit 1; }

# ------------------------------------------------------------
# 1) AGENT.md overlay（ホスト current directory は触らない）
# ------------------------------------------------------------
AGENT_OVERLAY_PATH=""
if [[ -f "${PREAGENT_FILE}" ]]; then
  AGENT_OVERLAY_PATH="$(mktemp -t codex-agent-XXXXXX.md)"
  TMP_FILES+=("${AGENT_OVERLAY_PATH}")
  cp -f -- "${PREAGENT_FILE}" "${AGENT_OVERLAY_PATH}"
  echo "[prep] Overlay AGENT.md from: ${PREAGENT_FILE}"
else
  echo "[warn] ${PREAGENT_FILE} not found; AGENT.md overlay will not be applied."
fi

# ------------------------------------------------------------
# 2) Docker mounts 構築
# ------------------------------------------------------------
DOCKER_MOUNTS=()

# project mount（ホストと同一絶対パスに mount）
DOCKER_MOUNTS+=("-v" "${PROJECT_ROOT}:${WORKDIR_IN_CONTAINER}:rw")

# ~/.codex を writable mount（コンテナ側は /home/<user>/.codex を想定）
CONTAINER_HOME="/home/${HOST_USER}"
mkdir -p -- "${HOST_CODEX_DIR}"
DOCKER_MOUNTS+=("-v" "${HOST_CODEX_DIR}:${CONTAINER_HOME}/.codex:rw")

# 任意: ~/.codex-cstm（参照用）
if [[ -d "${CODEX_CSTM_DIR}" ]]; then
  DOCKER_MOUNTS+=("-v" "${CODEX_CSTM_DIR}:${CONTAINER_HOME}/.codex-cstm:ro")
fi

# AGENT.md overlay（コンテナ内は host と同一 workdir）
if [[ -n "${AGENT_OVERLAY_PATH}" ]]; then
  DOCKER_MOUNTS+=("-v" "${AGENT_OVERLAY_PATH}:${WORKDIR_IN_CONTAINER}/AGENT.md:ro")
fi

# ------------------------------------------------------------
# 3) codexignore 解析 → “不可視化 mount” を追加
# ------------------------------------------------------------
if [[ -f "${CODEXIGNORE_FILE}" ]]; then
  echo "[prep] Applying ignore rules from: ${CODEXIGNORE_FILE}"

  shopt -s nullglob globstar dotglob

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw#"${raw%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    matches=()

    if [[ "$line" == /* ]]; then
      while IFS= read -r m; do matches+=("$m"); done < <(compgen -G "$line" || true)
      [[ ${#matches[@]} -eq 0 ]] && matches=("$line")
    else
      while IFS= read -r m; do matches+=("$m"); done < <(cd "${PROJECT_ROOT}" && compgen -G "$line" || true)
      [[ ${#matches[@]} -eq 0 ]] && matches=("$line")
    fi

    for p in "${matches[@]}"; do
      p="${p#./}"

      if [[ "$p" == /* ]]; then
        host_path="$p"
        container_path="$p"
      else
        host_path="${PROJECT_ROOT}/${p}"
        container_path="${WORKDIR_IN_CONTAINER}/${p}"
      fi

      if [[ -d "$host_path" ]]; then
        empty_dir="$(mktemp -d -t codex-emptydir-XXXXXX)"
        TMP_DIRS+=("$empty_dir")
        DOCKER_MOUNTS+=("-v" "${empty_dir}:${container_path}:ro")
        echo "  [hide dir]  ${host_path} -> ${container_path}"
      elif [[ -e "$host_path" ]]; then
        DOCKER_MOUNTS+=("-v" "/dev/null:${container_path}:ro")
        echo "  [hide file] ${host_path} -> ${container_path}"
      else
        echo "  [skip] not found: ${host_path}"
      fi
    done
  done < "${CODEXIGNORE_FILE}"

  shopt -u nullglob globstar dotglob
else
  echo "[info] ${CODEXIGNORE_FILE} not found; no ignore mounts applied."
fi

# 共通 env
DOCKER_ENVS=(
  "-e" "HOST_USER=${HOST_USER}"
  "-e" "HOST_GROUP=${HOST_GROUP}"
  "-e" "HOST_UID=${HOST_UID}"
  "-e" "HOST_GID=${HOST_GID}"
)

# ------------------------------------------------------------
# 4) (任意) コンテナ内で ./.codex-build を実行（ENTRYPOINT を一時的に /bin/bash）
# ------------------------------------------------------------
if [[ -f "${PROJECT_ROOT}/.codex-build" ]]; then
  echo "[pre] Running ./.codex-build inside container (temporary entrypoint=/bin/bash)..."

  docker run --rm -it \
    "${DOCKER_ENVS[@]}" \
    -w "${WORKDIR_IN_CONTAINER}" \
    "${DOCKER_MOUNTS[@]}" \
    --entrypoint /bin/bash \
    "${IMAGE}" \
    -lc 'set -euo pipefail; cd "$PWD"; bash "./.codex-build"'
fi

# ------------------------------------------------------------
# 5) ENTRYPOINT に戻して codex を起動（引数はそのまま）
#    - entrypoint は上書きしない（= イメージ既定に戻る）
# ------------------------------------------------------------
echo "[run] docker run --rm -it ${IMAGE}"
echo "      project: ${PROJECT_ROOT}"
echo "      workdir : ${WORKDIR_IN_CONTAINER} (same as host)"
echo "      env     : HOST_USER=${HOST_USER} HOST_GROUP=${HOST_GROUP} HOST_UID=${HOST_UID} HOST_GID=${HOST_GID}"

exec docker run --rm -it \
  "${DOCKER_ENVS[@]}" \
  -w "${WORKDIR_IN_CONTAINER}" \
  "${DOCKER_MOUNTS[@]}" \
  "${IMAGE}" \
  codex "$@"

