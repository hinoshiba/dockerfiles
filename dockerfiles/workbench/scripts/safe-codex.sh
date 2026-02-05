#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# run_codex_safe.sh
#
# 要件:
# - IMAGE は定数
# - workdir(コンテナ内)はホスト current directory の絶対パスと同一
# - ~/.codex を writable mount（current user の HOME 配下）
# - ~/.codex-cstm/preagent.md を <workdir>/AGENTS.md に overlay（ホストは変更しない）
# - ~/.codex-cstm/.codexignore に従い不可視化 mount を追加（file=/dev/null, dir=空dir）
#
# - ./.codex-build が存在する場合:
#   1) まず “codex コンテナ内で” ./.codex-build を bash 実行（ENTRYPOINT を一時的に /bin/bash に差し替え）
#   2) その後 “ENTRYPOINT に戻して” 通常起動（= entrypoint を上書きしない起動）し、codex を実行
#
# - ユーザー作成などはカスタムイメージ側が担当する前提
#   LOCAL_WHOAMI / LOCAL_GROUP / LOCAL_UID / LOCAL_GID を env で渡すだけ
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
IMAGE="localhost/codex:latest"
# -----------------------------

PROJECT_ROOT="$(pwd)"
WORKDIR_IN_CONTAINER="${PROJECT_ROOT}"   # コンテナ内も同じ絶対パス

LOCAL_UID="$(id -u)"
LOCAL_GID="$(id -g)"
LOCAL_WHOAMI="$(id -un)"
LOCAL_GROUP="$(id -gn)"
LOCAL_DOCKER_GID="$(getent group docker | awk  -F: '{print $3}')"
LOCAL_HOME="${HOME}"
WORK_CUR="$(pwd)"

CODEX_CSTM_DIR="${LOCAL_HOME}/.codex-cstm"
CODEXIGNORE_FILE="${CODEX_CSTM_DIR}/.codexignore"
PREAGENT_FILE="${CODEX_CSTM_DIR}/preagent.md"
LOCAL_CODEX_DIR="${LOCAL_HOME}/.codex"

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
# 1) AGENTS.md overlay（ホスト current directory は触らない）
# ------------------------------------------------------------
AGENT_OVERLAY_PATH=""
if [[ -f "${PREAGENT_FILE}" ]]; then
  AGENT_OVERLAY_PATH="$(mktemp -t codex-agent-XXXXXX.md)"
  TMP_FILES+=("${AGENT_OVERLAY_PATH}")
  cp -f -- "${PREAGENT_FILE}" "${AGENT_OVERLAY_PATH}"
  echo "[prep] Overlay AGENTS.md from: ${PREAGENT_FILE}"
else
  echo "[warn] ${PREAGENT_FILE} not found; AGENTS.md overlay will not be applied."
fi

# ------------------------------------------------------------
# 2) Docker mounts 構築
# ------------------------------------------------------------
DOCKER_MOUNTS=()

# project mount（ホストと同一絶対パスに mount）
DOCKER_MOUNTS+=("-v" "${PROJECT_ROOT}:${WORKDIR_IN_CONTAINER}:rw")

# ~/.codex を writable mount（コンテナ側は /home/<user>/.codex を想定）
CONTAINER_HOME="/home/${LOCAL_WHOAMI}"
mkdir -p -- "${LOCAL_CODEX_DIR}"
DOCKER_MOUNTS+=("-v" "${LOCAL_CODEX_DIR}:${CONTAINER_HOME}/.codex:rw")

# 任意: ~/.codex-cstm（参照用）
if [[ -d "${CODEX_CSTM_DIR}" ]]; then
  DOCKER_MOUNTS+=("-v" "${CODEX_CSTM_DIR}:${CONTAINER_HOME}/.codex-cstm:ro")
fi

# AGENTS.md overlay（コンテナ内は host と同一 workdir）
if [[ -n "${AGENT_OVERLAY_PATH}" ]]; then
  DOCKER_MOUNTS+=("-v" "${AGENT_OVERLAY_PATH}:${WORKDIR_IN_CONTAINER}/AGENTS.md:ro")
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
  "-e" "LOCAL_WHOAMI=${LOCAL_WHOAMI}"
  "-e" "LOCAL_GROUP=${LOCAL_GROUP}"
  "-e" "LOCAL_UID=${LOCAL_UID}"
  "-e" "LOCAL_GID=${LOCAL_GID}"
  "-e" "LOCAL_DOCKER_GID=${LOCAL_DOCKER_GID}"
  "-e" "WORK_CUR=${WORK_CUR}"
)

# ------------------------------------------------------------
# 4) (任意) コンテナ内で ./.codex-build を実行（ENTRYPOINT を一時的に /bin/bash）
# ------------------------------------------------------------
if [[ -f "${PROJECT_ROOT}/.codex-build" ]]; then
  echo "[pre] Running ./.codex-build inside container (temporary entrypoint=/bin/bash)..."

  docker run --rm \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
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
echo "[run] docker run --rm ${IMAGE}"
echo "      project: ${PROJECT_ROOT}"
echo "      workdir : ${WORKDIR_IN_CONTAINER} (same as host)"
echo "      env     : LOCAL_WHOAMI=${LOCAL_WHOAMI} LOCAL_GROUP=${LOCAL_GROUP} LOCAL_UID=${LOCAL_UID} LOCAL_GID=${LOCAL_GID}"

exec docker run --rm \
  -it \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  "${DOCKER_ENVS[@]}" \
  -w "${WORKDIR_IN_CONTAINER}" \
  "${DOCKER_MOUNTS[@]}" \
  "${IMAGE}" \
  codex "$@"
