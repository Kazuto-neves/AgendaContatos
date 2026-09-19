#!/usr/bin/env bash
# =============================================================================
# packge.sh — Build + Run cronometrado + Pacotes transitivos
#
# Cada execução gera UMA pasta autodescritiva:
#   <tfm>-<config>__<ações-executadas>__<timestamp>/
#
# Exemplos de pasta:
#   net8.0-Release__clean-restore-build-test-runApi-packages__20250101_120000/
#   net8.0-Debug__restore-build-test-packages__20250101_120003/
#   net10.0-Release__clean-restore-build-test-runApi-packages__20250101_120050/
# =============================================================================
# Uso:
#   ./packge.sh                              # clean + restore + build + test + packages
#   ./packge.sh --run Api                    # + sobe a Api e aguarda timeout
#   ./packge.sh -c Release --run Api         # modo Release
#   ./packge.sh --run Api --timeout 60       # 60s de execução
#   ./packge.sh --skip-clean                 # sem clean (build incremental)
#   ./packge.sh --no-test                    # sem testes
#   ./packge.sh --url http://localhost:5000  # URL custom da API
#   ./packge.sh --sln ./MinhaSln.sln         # solução específica
# =============================================================================

set -euo pipefail
export DOTNET_CLI_UI_LANGUAGE=en-US
export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# ------------------------- Configuração padrão -------------------------------
SLN=""
CONFIGURATION="Debug"
RUN_PROJECT=""
SKIP_CLEAN=0
SKIP_TEST=0
TIMEOUT_RUN_SECONDS=120
API_READY_TIMEOUT=30            # segundos que aguardamos /health responder
RUN_URL="http://localhost:5299" # URL determinística da API
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARTIFACTS_ROOT="$PWD/artifacts"

# ------------------------- Cores ANSI ----------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m';  C_CYAN=$'\033[36m';  C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""
  C_YELLOW=""; C_RED=""; C_CYAN=""; C_DIM=""
fi

log()  { printf "%s[%s]%s %s\n" "$C_CYAN" "$(date +%H:%M:%S)" "$C_RESET" "$*"; }
ok()   { printf "%s✔%s %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%s⚠%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%s✘%s %s\n" "$C_RED" "$C_RESET" "$*" >&2; }
hr()   { printf "%s%s%s\n" "$C_DIM" "──────────────────────────────────────────────────────────────" "$C_RESET"; }

# ------------------------- Parse de argumentos -------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sln)              SLN="$2"; shift 2 ;;
    --configuration|-c) CONFIGURATION="$2"; shift 2 ;;
    --run)              RUN_PROJECT="$2"; shift 2 ;;
    --skip-clean)       SKIP_CLEAN=1; shift ;;
    --no-test)          SKIP_TEST=1; shift ;;
    --timeout)          TIMEOUT_RUN_SECONDS="$2"; shift 2 ;;
    --url)              RUN_URL="$2"; shift 2 ;;
    --ready-timeout)    API_READY_TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) err "Argumento desconhecido: $1"; exit 1 ;;
  esac
done

# ------------------------- Detecção de SDK / runtime -------------------------
SDK_VERSION_FULL="$(dotnet --version 2>/dev/null || echo "0.0.0")"
SDK_MAJOR_MINOR="$(echo "$SDK_VERSION_FULL" | cut -d. -f1,2)"
SDK_TAG="net${SDK_MAJOR_MINOR}"

RUNTIME_LINE="$(dotnet --list-runtimes 2>/dev/null \
  | grep -E 'Microsoft\.(NETCore|AspNetCore)\.App' | tail -1 || echo 'n/a')"

# ------------------------- Detecção automática de .sln -----------------------
if [[ -z "$SLN" ]]; then
  SLN="$(find "$PWD" -maxdepth 2 -name '*.sln' -print -quit || true)"
fi
if [[ -z "$SLN" || ! -f "$SLN" ]]; then
  err "Nenhum arquivo .sln encontrado. Use --sln ./caminho.sln"
  exit 1
fi

# ------------------------- Descobre TFM real do .csproj ----------------------
# Pega o TargetFramework do primeiro .csproj que encontrar (prefere o da pasta
# informada em --run, senão pega qualquer um). Assim o nome da pasta reflete
# o que o código-fonte realmente compila, não apenas o SDK instalado.
find_tfm() {
  local csproj
  csproj="$(grep -rl '<TargetFramework' "$PWD" --include='*.csproj' 2>/dev/null | head -1 || true)"
  if [[ -n "$csproj" ]]; then
    grep -oE '<TargetFramework>[^<]+' "$csproj" \
      | head -1 | sed 's/<TargetFramework>//' | tr -d ' \r'
  else
    echo "$SDK_TAG"
  fi
}

# Se --run Api foi passado, prefira o TFM daquele projeto
TFM_SOURCE_DIR=""
if [[ -n "$RUN_PROJECT" ]]; then
  TFM_SOURCE_DIR="$(find "$PWD" -maxdepth 4 -type d -iname "*${RUN_PROJECT}*" -print -quit || true)"
fi

if [[ -n "$TFM_SOURCE_DIR" && -d "$TFM_SOURCE_DIR" ]]; then
  csproj_file="$(find "$TFM_SOURCE_DIR" -maxdepth 1 -name '*.csproj' -print -quit || true)"
  if [[ -n "$csproj_file" ]]; then
    DOTNET_TAG="$(grep -oE '<TargetFramework>[^<]+' "$csproj_file" \
      | head -1 | sed 's/<TargetFramework>//' | tr -d ' \r' || echo "$SDK_TAG")"
  else
    DOTNET_TAG="$(find_tfm)"
  fi
else
  DOTNET_TAG="$(find_tfm)"
fi

# ------------------------- Monta nome da pasta -------------------------------
build_actions_slug() {
  local parts=()
  [[ $SKIP_CLEAN -eq 0 ]] && parts+=("clean")
  parts+=("restore")
  parts+=("build")
  [[ $SKIP_TEST -eq 0 ]] && parts+=("test")
  [[ -n "$RUN_PROJECT" ]] && parts+=("run${RUN_PROJECT}")
  parts+=("packages")
  local IFS="-"
  echo "${parts[*]}"
}

ACTIONS_SLUG="$(build_actions_slug)"
FOLDER_NAME="${DOTNET_TAG}-${CONFIGURATION}__${ACTIONS_SLUG}__${TIMESTAMP}"
OUTPUT_DIR="$ARTIFACTS_ROOT/$FOLDER_NAME"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$ARTIFACTS_ROOT"

# Log global (histórico append-only)
printf "%s | %s | cfg=%s | run=%s | sdk=%s | %s\n" \
  "$TIMESTAMP" "$DOTNET_TAG" "$CONFIGURATION" "${RUN_PROJECT:-<none>}" \
  "$SDK_VERSION_FULL" "$FOLDER_NAME" \
  >> "$ARTIFACTS_ROOT/runs.log"

# ------------------------- Utilidades de medição -----------------------------
now() { date +%s.%N; }

fmt_dur() {
  awk -v s="$1" 'BEGIN{
    if (s >= 60) printf "%dm %.3fs", int(s/60), s - int(s/60)*60;
    else          printf "%.3fs", s;
  }'
}

declare -a STEP_NAMES=()
declare -a STEP_TIMES=()
declare -a STEP_STATUS=()

run_step() {
  local name="$1"; shift
  hr
  log "${C_BOLD}${name}${C_RESET}"
  log "${C_DIM}$ $*${C_RESET}"

  local start end dur status=0
  start="$(now)"
  if "$@"; then status=0; else status=$?; fi
  end="$(now)"
  dur="$(awk -v a="$start" -v b="$end" 'BEGIN{printf "%.6f", b-a}')"

  STEP_NAMES+=("$name")
  STEP_TIMES+=("$dur")
  STEP_STATUS+=("$status")

  if [[ $status -eq 0 ]]; then
    ok "$name — $(fmt_dur "$dur")"
  else
    err "$name FALHOU (exit $status) — $(fmt_dur "$dur")"
    return $status
  fi
}

# ------------------------- Banner --------------------------------------------
printf "\n%s%s╔══════════════════════════════════════════════════════════════╗%s\n" "$C_BOLD" "$C_BLUE" "$C_RESET"
printf "%s%s║  PIPELINE .NET — build + run cronometrado + transitivos      ║%s\n" "$C_BOLD" "$C_BLUE" "$C_RESET"
printf "%s%s╚══════════════════════════════════════════════════════════════╝%s\n\n" "$C_BOLD" "$C_BLUE" "$C_RESET"

log "Solução:        ${C_BOLD}$SLN${C_RESET}"
log "Configuração:   ${C_BOLD}$CONFIGURATION${C_RESET}"
log "TFM (projeto):  ${C_BOLD}$DOTNET_TAG${C_RESET}"
log "SDK em uso:     $SDK_VERSION_FULL"
log "Runtime:        $RUNTIME_LINE"
log "Execução:       ${C_BOLD}${RUN_PROJECT:-<nenhuma>}${C_RESET}"
log "Pasta de saída: ${C_BOLD}$OUTPUT_DIR${C_RESET}"
echo

# ------------------------- Steps ---------------------------------------------
if [[ $SKIP_CLEAN -eq 0 ]]; then
  run_step "dotnet clean" dotnet clean "$SLN" -c "$CONFIGURATION" -v quiet
fi

run_step "dotnet restore" dotnet restore "$SLN" --verbosity quiet
run_step "dotnet build"   dotnet build   "$SLN" -c "$CONFIGURATION" --no-restore -v minimal

if [[ $SKIP_TEST -eq 0 ]]; then
  run_step "dotnet test"  dotnet test    "$SLN" -c "$CONFIGURATION" --no-build -v minimal
fi

# ------------------------- Execução (opcional) -------------------------------
RUN_EXIT=""
RUN_TIME=""
RUN_LOG=""
RUN_URL_FILE="$OUTPUT_DIR/run_url.txt"
API_READY_SECONDS=""

if [[ -n "$RUN_PROJECT" ]]; then
  RUN_DIR="$TFM_SOURCE_DIR"

  if [[ -z "$RUN_DIR" || ! -d "$RUN_DIR" ]]; then
    warn "Projeto de execução '$RUN_PROJECT' não encontrado — pulando etapa de run."
  else
    hr
    log "${C_BOLD}Execução: $RUN_PROJECT (timeout ${TIMEOUT_RUN_SECONDS}s)${C_RESET}"

    # Detecta se é um projeto web (ASP.NET Core) para aplicar URL/health check
    IS_WEB=0
    if grep -q 'Microsoft.NET.Sdk.Web' "$RUN_DIR"/*.csproj 2>/dev/null; then IS_WEB=1; fi

    if [[ $IS_WEB -eq 1 ]]; then
      EXTRA_ARGS=(--no-launch-profile --urls "$RUN_URL")
      log "${C_DIM}$ dotnet run -c $CONFIGURATION --project $RUN_DIR --no-build --no-launch-profile --urls $RUN_URL${C_RESET}"
    else
      EXTRA_ARGS=(--no-launch-profile)
      log "${C_DIM}$ dotnet run -c $CONFIGURATION --project $RUN_DIR --no-build --no-launch-profile${C_RESET}"
    fi

    RUN_LOG="$OUTPUT_DIR/run_${RUN_PROJECT}.log"

    start="$(now)"

    set +e
    # -u = unbuffered; -m = respeita timeout; -k = SIGKILL se SIGTERM falhar
    timeout -k 5s "${TIMEOUT_RUN_SECONDS}" \
      stdbuf -oL -eL dotnet run -c "$CONFIGURATION" --project "$RUN_DIR" \
        --no-build "${EXTRA_ARGS[@]}" \
      > >(tee "$RUN_LOG") 2>&1 &
    APP_PID=$!
    set -e

    # ---- Espera a API responder /health (só para projetos web) -------------
    if [[ $IS_WEB -eq 1 ]]; then
      log "Aguardando API responder em ${C_BOLD}${RUN_URL}/health${C_RESET} (até ${API_READY_TIMEOUT}s)..."

      READY=0
      for ((i=1; i<=API_READY_TIMEOUT; i++)); do
        if ! kill -0 "$APP_PID" 2>/dev/null; then
          err "Processo morreu antes de responder /health — veja $RUN_LOG"
          break
        fi
        if curl -fsS --max-time 1 "${RUN_URL}/health" >/dev/null 2>&1; then
          READY=1
          API_READY_SECONDS="$i"
          echo "$RUN_URL" > "$RUN_URL_FILE"
          ok "API PRONTA em ${C_BOLD}${RUN_URL}${C_RESET} (após ${i}s)"
          log "  Swagger: ${C_BOLD}${RUN_URL}/swagger/index.html${C_RESET}"
          log "  Health:  ${C_BOLD}${RUN_URL}/health${C_RESET}"
          break
        fi
        sleep 1
      done

      [[ $READY -eq 0 ]] && warn "API não respondeu /health em ${API_READY_TIMEOUT}s."

      log "API em execução. Vou aguardar até ${TIMEOUT_RUN_SECONDS}s (Ctrl+C interrompe)."
    fi

    wait "$APP_PID"
    RUN_EXIT=$?

    end="$(now)"
    RUN_TIME="$(awk -v a="$start" -v b="$end" 'BEGIN{printf "%.6f", b-a}')"

    # ---- Normaliza exit codes do `timeout` ---------------------------------
    # 124 = SIGTERM (timeout padrão)
    # 137 = SIGKILL (fallback do -k, ou kill -9)
    # Ambos são o comportamento ESPERADO quando passamos --timeout.
    if [[ "$RUN_EXIT" -eq 124 || "$RUN_EXIT" -eq 137 ]]; then
      STEP_NAMES+=("run: $RUN_PROJECT (until timeout)")
      STEP_TIMES+=("$RUN_TIME")
      STEP_STATUS+=(0)
      warn "run executou até o timeout de ${TIMEOUT_RUN_SECONDS}s (esperado) — $(fmt_dur "$RUN_TIME")"
    elif [[ "$RUN_EXIT" -eq 0 ]]; then
      STEP_NAMES+=("run: $RUN_PROJECT")
      STEP_TIMES+=("$RUN_TIME")
      STEP_STATUS+=(0)
      ok "run terminou sozinho — $(fmt_dur "$RUN_TIME") (log: $RUN_LOG)"
    else
      STEP_NAMES+=("run: $RUN_PROJECT")
      STEP_TIMES+=("$RUN_TIME")
      STEP_STATUS+=("$RUN_EXIT")
      err "run retornou exit $RUN_EXIT — $(fmt_dur "$RUN_TIME") (log: $RUN_LOG)"
      warn "Últimas 20 linhas do log:"
      tail -n 20 "$RUN_LOG" | sed 's/^/    /' || true
    fi
  fi
fi

# ------------------------- Pacotes transitivos -------------------------------
hr
log "${C_BOLD}Coletando pacotes transitivos...${C_RESET}"

PACKAGES_TXT="$OUTPUT_DIR/transitive_packages.txt"
PACKAGES_CSV="$OUTPUT_DIR/transitive_packages.csv"
RAW_PACKAGES="$OUTPUT_DIR/raw_packages.txt"

dotnet list "$SLN" package --include-transitive > "$RAW_PACKAGES" 2>/dev/null || true

# Formato bonito (mesma lógica do script original)
awk '
/^Project/ {
    split($0, partes, "\x27")
    projeto = partes[2]
    emTransitivo = 0
    cabecalhoImpresso = 0
}
/Top-level Package/ { emTransitivo = 0 }
/Transitive Package/ {
    emTransitivo = 1
    if (cabecalhoImpresso == 0) {
        print "\nProjeto: " projeto
        print "Pacotes Transitivos:"
        printf "%-60s | %s\n", "Nome do Pacote", "Versão"
        print "-------------------------------------------------------------|---------"
        cabecalhoImpresso = 1
    }
}
/^ *>/ {
    if (emTransitivo == 1) {
        printf "%-60s | %s\n", $2, $NF
    }
}' "$RAW_PACKAGES" > "$PACKAGES_TXT"

# CSV — útil para diff .NET 8 vs .NET 10
echo "Projeto,NomeDoPacote,Versao" > "$PACKAGES_CSV"
awk '
/^Project/ {
    split($0, partes, "\x27")
    projeto = partes[2]
    emTransitivo = 0
}
/Top-level Package/ { emTransitivo = 0 }
/Transitive Package/ { emTransitivo = 1 }
/^ *>/ {
    if (emTransitivo == 1) print projeto "," $2 "," $NF
}' "$RAW_PACKAGES" >> "$PACKAGES_CSV"

TOTAL_PKG="$(($(wc -l < "$PACKAGES_CSV") - 1))"
ok "Pacotes transitivos listados: ${C_BOLD}$TOTAL_PKG${C_RESET}"
log "  → $PACKAGES_TXT"
log "  → $PACKAGES_CSV"

# ------------------------- Relatório final -----------------------------------
REPORT="$OUTPUT_DIR/report.txt"
TOTAL_TIME="$(printf '%s\n' "${STEP_TIMES[@]}" | awk '{s+=$1} END{print s+0}')"

{
  echo "═══════════════════════════════════════════════════════════════"
  echo "  RELATÓRIO DE PIPELINE — $(date '+%Y-%m-%d %H:%M:%S')"
  echo "═══════════════════════════════════════════════════════════════"
  echo "Solução:        $SLN"
  echo "Config:         $CONFIGURATION"
  echo "TFM (projeto):  $DOTNET_TAG"
  echo "SDK:            $SDK_VERSION_FULL"
  echo "Runtime:        $RUNTIME_LINE"
  echo "Ações:          $ACTIONS_SLUG"
  echo "Pasta:          $OUTPUT_DIR"
  echo "Pacotes trans:  $TOTAL_PKG"
  [[ -n "$API_READY_SECONDS" ]] && echo "API pronta em:  ${API_READY_SECONDS}s"
  echo
  printf "%-40s %12s   %s\n" "ETAPA" "TEMPO" "STATUS"
  echo "───────────────────────────────────────────────────────────────"
  for i in "${!STEP_NAMES[@]}"; do
    status_str="OK"
    [[ "${STEP_STATUS[$i]}" -ne 0 ]] && status_str="FAIL(${STEP_STATUS[$i]})"
    printf "%-40s %12s   %s\n" "${STEP_NAMES[$i]}" "$(fmt_dur "${STEP_TIMES[$i]}")" "$status_str"
  done
  echo "───────────────────────────────────────────────────────────────"
  printf "%-40s %12s\n" "TOTAL" "$(fmt_dur "$TOTAL_TIME")"
  echo
  echo "Artefatos:"
  echo "  - $PACKAGES_TXT"
  echo "  - $PACKAGES_CSV"
  [[ -n "$RUN_LOG" ]] && echo "  - $RUN_LOG"
  [[ -f "$RUN_URL_FILE" ]] && echo "  - $RUN_URL_FILE"
} > "$REPORT"

# ------------------------- Resumo no terminal --------------------------------
hr
printf "\n%s%s╔══════════════════════════════════════════════════════════════╗%s\n" "$C_BOLD" "$C_GREEN" "$C_RESET"
printf "%s%s║                    RESUMO DO PIPELINE                        ║%s\n" "$C_BOLD" "$C_GREEN" "$C_RESET"
printf "%s%s╚══════════════════════════════════════════════════════════════╝%s\n\n" "$C_BOLD" "$C_GREEN" "$C_RESET"

printf "  %-40s %12s   %s\n" "ETAPA" "TEMPO" "STATUS"
hr
for i in "${!STEP_NAMES[@]}"; do
  status_str="${C_GREEN}OK${C_RESET}"
  [[ "${STEP_STATUS[$i]}" -ne 0 ]] && status_str="${C_RED}FAIL(${STEP_STATUS[$i]})${C_RESET}"
  printf "  %-40s %12s   %b\n" "${STEP_NAMES[$i]}" "$(fmt_dur "${STEP_TIMES[$i]}")" "$status_str"
done
hr
printf "  %-40s %s%12s%s\n\n" "TOTAL" "$C_BOLD" "$(fmt_dur "$TOTAL_TIME")" "$C_RESET"

printf "%sPasta da execução:%s %s\n" "$C_DIM" "$C_RESET" "$OUTPUT_DIR"
printf "%sRelatório:%s        %s\n" "$C_DIM" "$C_RESET" "$REPORT"
printf "%sPacotes (%s):%s    %s\n" "$C_DIM" "$TOTAL_PKG" "$C_RESET" "$PACKAGES_TXT"
[[ -f "$RUN_URL_FILE" ]] && printf "%sURL da API:%s      %s\n" "$C_DIM" "$C_RESET" "$(cat "$RUN_URL_FILE")"
echo

# ------------------------- Exit code agregado --------------------------------
for s in "${STEP_STATUS[@]}"; do
  [[ "$s" -ne 0 ]] && exit 1
done
exit 0
