#!/usr/bin/env bash
# =============================================================================
# compare.sh — Compara execuções net8.0 vs net10.0
#              Saída: terminal · csv · markdown · all
# =============================================================================
# Uso:
#   ./compare.sh                              # Debug + Release, terminal
#   ./compare.sh Release                      # só Release
#   ./compare.sh --format markdown            # gera reports/compare_<ts>.md
#   ./compare.sh --format csv                 # gera reports/compare_<ts>/*.csv
#   ./compare.sh --format all                 # todos os formatos
#   ./compare.sh Release --all-packages       # inclui pacotes iguais
#   ./compare.sh --out docs/bench             # pasta/arquivo de saída
# =============================================================================

set -uo pipefail        # <-- ATENÇÃO: sem `-e` (não aborta em falhas de render)

CONFIGS=()
SHOW_DIFF=1
SHOW_CLASSIFY=1
SHOW_ALL_PKGS=0
FORMAT="terminal"
OUT_DIR=""
ARTIFACTS_ROOT="artifacts"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-diff)       SHOW_DIFF=0; shift ;;
    --no-classify)   SHOW_CLASSIFY=0; shift ;;
    --all-packages)  SHOW_ALL_PKGS=1; shift ;;
    --format)        FORMAT="$2"; shift 2 ;;
    --out)           OUT_DIR="$2"; shift 2 ;;
    Debug|Release)   CONFIGS+=("$1"); shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

[[ ${#CONFIGS[@]} -eq 0 ]] && CONFIGS=(Debug Release)

case "$FORMAT" in
  terminal|csv|markdown|all) ;;
  *) echo "Formato inválido: $FORMAT (use: terminal|csv|markdown|all)" >&2; exit 1 ;;
esac

# ------------------------- Cores ANSI ----------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_MAGENTA=$'\033[35m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_BLUE=""; C_GREEN=""
  C_YELLOW=""; C_RED=""; C_CYAN=""; C_MAGENTA=""
fi

hr_thick() { printf "%s%s%s\n" "$C_BOLD" "═══════════════════════════════════════════════════════════════════════════" "$C_RESET"; }
hr_thin()  { printf "%s%s%s\n" "$C_DIM"  "───────────────────────────────────────────────────────────────────────────" "$C_RESET"; }
hr_dash()  { printf "%s%s%s\n" "$C_DIM"  "┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈" "$C_RESET"; }

section() {
  local title="$1"; local color="${2:-$C_BLUE}"
  echo; hr_thick
  printf "%s  %s%s\n" "$color$C_BOLD" "$title" "$C_RESET"
  hr_thick
}

# ------------------------- Helpers -------------------------------------------
field() {
  local file="$1"; local key="$2"
  [[ -f "$file" ]] || { echo ""; return 0; }
  grep -E "^${key}" "$file" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '\r' || true
}

step_time() {
  local file="$1"; local pattern="$2"
  [[ -f "$file" ]] || { echo ""; return 0; }
  grep -E "^${pattern}" "$file" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)?s' | head -1 || true
}

run_time() {
  local file="$1"
  [[ -f "$file" ]] || { echo ""; return 0; }
  grep -E '^run:' "$file" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)?s' | head -1 || true
}

latest_dir() {
  local tfm="$1"; local cfg="$2"
  ls -1dt "${ARTIFACTS_ROOT}/${tfm}-${cfg}__"*/ 2>/dev/null | head -1 || true
}

csv_escape() {
  local s="${1-}"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

# -----------------------------------------------------------------------------
# Pivot de pacotes
#   Entrada : dois CSVs (Projeto,NomeDoPacote,Versao)
#   Saída   : TSV ordenado: Pacote \t Projeto \t NET8 \t NET10 \t Status
#   Status  : SO_NET8 | SO_NET10 | MUDOU | IGUAL
# -----------------------------------------------------------------------------
packages_pivot() {
  local csv8="$1" csv10="$2"

  if [[ ! -f "$csv8" ]]; then
    echo "ERRO_CSV8_AUSENTE"
    return 0
  fi
  if [[ ! -f "$csv10" ]]; then
    echo "ERRO_CSV10_AUSENTE"
    return 0
  fi

  # Normaliza (remove CR e BOM) num tmp
  local tmp8 tmp10
  tmp8="$(mktemp)"; tmp10="$(mktemp)"
  tr -d '\r' < "$csv8"  | sed '1s/^\xEF\xBB\xBF//' > "$tmp8"
  tr -d '\r' < "$csv10" | sed '1s/^\xEF\xBB\xBF//' > "$tmp10"

  awk -F',' -v show_all="$SHOW_ALL_PKGS" '
  NR == FNR {
    if (FNR == 1) next
    key = $2 SUBSEP $1
    v8[key]   = $3
    proj[key] = $1
    pkg[key]  = $2
    seen[key] = 1
    next
  }
  {
    if (FNR == 1) next
    key = $2 SUBSEP $1
    v10[key]  = $3
    proj[key] = $1
    pkg[key]  = $2
    seen[key] = 1
  }
  END {
    for (k in seen) {
      a = v8[k]; b = v10[k]
      if (a == "" && b != "")      status = "SO_NET10"
      else if (a != "" && b == "") status = "SO_NET8"
      else if (a == b)             status = "IGUAL"
      else                         status = "MUDOU"

      if (show_all == 0 && status == "IGUAL") continue

      printf "%s\t%s\t%s\t%s\t%s\n", pkg[k], proj[k],
             (a==""?"-":a), (b==""?"-":b), status
    }
  }
  ' "$tmp8" "$tmp10" | LC_ALL=C sort -t$'\t' -k5,5 -k1,1

  rm -f "$tmp8" "$tmp10"
  return 0
}

# -----------------------------------------------------------------------------
# Contadores derivados do pivot
# -----------------------------------------------------------------------------
packages_counts() {
  local pivot="$1"
  awk -F'\t' '
    $5=="SO_NET8"  { only8++ }
    $5=="SO_NET10" { only10++ }
    $5=="MUDOU"    { mudou++ }
    $5=="IGUAL"    { igual++ }
    END { printf "%d\t%d\t%d\t%d\n", only8+0, only10+0, mudou+0, igual+0 }
  ' <<< "$pivot"
}

# =============================================================================
#                              COLETA
# =============================================================================
declare -A CFG_NET8_DIR CFG_NET10_DIR CFG_OK

collect_config() {
  local cfg="$1"
  local d8 d10
  d8="$(latest_dir "net8.0"  "$cfg")"
  d10="$(latest_dir "net10.0" "$cfg")"
  CFG_NET8_DIR["$cfg"]="$d8"
  CFG_NET10_DIR["$cfg"]="$d10"
  if [[ -n "$d8" && -n "$d10" ]]; then CFG_OK["$cfg"]=1; else CFG_OK["$cfg"]=0; fi
}

for cfg in "${CONFIGS[@]}"; do collect_config "$cfg"; done

# =============================================================================
#                          RENDER — TERMINAL
# =============================================================================
render_terminal_classify() {
  section "TODAS AS EXECUÇÕES ENCONTRADAS" "$C_CYAN"
  printf "  %-10s | %-10s | %-12s | %-38s | %s\n" "TFM" "SDK" "RUNTIME" "PASTA" "PKGS"
  hr_thin

  local found=0
  shopt -s nullglob
  for report in "${ARTIFACTS_ROOT}"/*/report.txt; do
    [[ -f "$report" ]] || continue
    found=1
    local dir folder tfm sdk rt pkgs folder_short rt_color
    dir="$(dirname "$report")"
    folder="$(basename "$dir")"
    tfm="$(field "$report" "TFM")"
    sdk="$(field "$report" "SDK")"
    rt="$(field "$report" "Runtime")"
    rt="$(echo "$rt" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '?')"
    pkgs="$(field "$report" "Pacotes trans")"
    folder_short="$folder"
    [[ ${#folder_short} -gt 38 ]] && folder_short="${folder_short:0:35}..."
    rt_color="$C_RESET"
    if { [[ "$tfm" == net8.0*  && "$rt" == 10.* ]]; } || \
       { [[ "$tfm" == net10.* && "$rt" == 8.*  ]]; }; then
      rt_color="$C_RED"
    fi
    printf "  %-10s | %-10s | %b%-12s%b | %-38s | %s\n" \
      "${tfm:-?}" "${sdk:-?}" "$rt_color" "${rt:-?}" "$C_RESET" "$folder_short" "${pkgs:-?}"
  done
  shopt -u nullglob
  [[ $found -eq 0 ]] && printf "  %s(nenhuma execução encontrada)%s\n" "$C_DIM" "$C_RESET"
  return 0
}

render_terminal_packages() {
  local cfg="$1" d8="$2" d10="$3"

  echo; hr_thin
  printf "  %sPACOTES TRANSITIVOS — COMPARAÇÃO%s\n" "$C_BOLD" "$C_RESET"
  hr_thin

  local csv8="${d8}transitive_packages.csv"
  local csv10="${d10}transitive_packages.csv"

  if [[ ! -f "$csv8" || ! -f "$csv10" ]]; then
    printf "  %s⚠ CSVs ausentes%s\n" "$C_YELLOW" "$C_RESET"
    [[ ! -f "$csv8"  ]] && printf "    falta: %s\n" "$csv8"
    [[ ! -f "$csv10" ]] && printf "    falta: %s\n" "$csv10"
    return 0
  fi

  local c8 c10
  c8="$(( $(wc -l < "$csv8")  - 1 ))"
  c10="$(( $(wc -l < "$csv10") - 1 ))"
  printf "  NET8  total: %s pacotes\n"  "$c8"
  printf "  NET10 total: %s pacotes\n"  "$c10"

  local pivot
  pivot="$(packages_pivot "$csv8" "$csv10")"

  if [[ "$pivot" == ERRO_* ]]; then
    printf "  %s⚠ %s%s\n" "$C_RED" "$pivot" "$C_RESET"
    return 0
  fi
  if [[ -z "$pivot" ]]; then
    printf "  %s(árvore idêntica — nenhuma diferença)%s\n" "$C_DIM" "$C_RESET"
    return 0
  fi

  local counts
  counts="$(packages_counts "$pivot")"
  local only8 only10 mudou igual
  IFS=$'\t' read -r only8 only10 mudou igual <<< "$counts"

  echo
  printf "  Resumo:  %b◀ %d só NET8%b   %b▶ %d só NET10%b   %b≠ %d mudou%b   %b= %d igual%b\n" \
    "$C_RED" "$only8" "$C_RESET" \
    "$C_GREEN" "$only10" "$C_RESET" \
    "$C_YELLOW" "$mudou" "$C_RESET" \
    "$C_DIM" "$igual" "$C_RESET"

  [[ $SHOW_ALL_PKGS -eq 0 ]] && \
    printf "  %s(use --all-packages para incluir os %d iguais)%s\n" "$C_DIM" "$igual" "$C_RESET"

  echo
  printf "  %-52s | %-12s | %-12s | %s\n" "PACOTE [PROJETO]" "NET8" "NET10" "STATUS"
  hr_dash

  local last_proj=""
  while IFS=$'\t' read -r pkg proj v8 v10 status; do
    [[ -z "$pkg" ]] && continue

    if [[ "$proj" != "$last_proj" ]]; then
      printf "  %s── %s ──%s\n" "$C_DIM" "$proj" "$C_RESET"
      last_proj="$proj"
    fi

    local icon color
    case "$status" in
      SO_NET8)  icon="◀ só NET8";  color="$C_RED"    ;;
      SO_NET10) icon="▶ só NET10"; color="$C_GREEN"  ;;
      MUDOU)    icon="≠ mudou";    color="$C_YELLOW" ;;
      IGUAL)    icon="= igual";    color="$C_DIM"    ;;
      *)        icon="$status";    color="$C_RESET"  ;;
    esac

    local label="$pkg"
    [[ ${#label} -gt 52 ]] && label="${label:0:49}..."
    printf "  %-52s | %-12s | %-12s | %b%-12s%b\n" \
      "$label" "$v8" "$v10" "$color" "$icon" "$C_RESET"
  done <<< "$pivot"

  hr_dash
  return 0
}

render_terminal_config() {
  local cfg="$1"
  section "COMPARATIVO — ${cfg^^}" "$C_MAGENTA"

  if [[ "${CFG_OK[$cfg]}" == "0" ]]; then
    [[ -z "${CFG_NET8_DIR[$cfg]}"  ]] && printf "  %s✘ Nenhuma execução net8.0-%s encontrada%s\n" "$C_RED" "$cfg" "$C_RESET"
    [[ -z "${CFG_NET10_DIR[$cfg]}" ]] && printf "  %s✘ Nenhuma execução net10.0-%s encontrada%s\n" "$C_RED" "$cfg" "$C_RESET"
    return 0
  fi

  local d8="${CFG_NET8_DIR[$cfg]}" d10="${CFG_NET10_DIR[$cfg]}"
  printf "  %s NET8  %s %s\n" "$C_GREEN"  "$C_RESET" "$(basename "$d8")"
  printf "  %s NET10 %s %s\n" "$C_YELLOW" "$C_RESET" "$(basename "$d10")"

  echo; hr_thin
  printf "  %sMETADADOS REAIS%s\n" "$C_BOLD" "$C_RESET"
  hr_thin
  printf "  %-18s | %-32s | %s\n" "CAMPO" "NET8" "NET10"
  hr_dash
  for key in "TFM" "SDK" "Runtime" "Config" "Pacotes trans"; do
    printf "  %-18s | %-32s | %s\n" "$key" \
      "$(field "${d8}report.txt"  "$key")" \
      "$(field "${d10}report.txt" "$key")"
  done

  echo; hr_thin
  printf "  %sTEMPOS DE EXECUÇÃO%s\n" "$C_BOLD" "$C_RESET"
  hr_thin
  printf "  %-30s | %14s | %14s | %s\n" "ETAPA" "NET8" "NET10" "Δ"
  hr_dash

  local step t8 t10 delta
  for step in "dotnet clean" "dotnet restore" "dotnet build" "dotnet test"; do
    t8="$(step_time "${d8}report.txt"  "$step")"
    t10="$(step_time "${d10}report.txt" "$step")"
    delta="—"
    if [[ -n "$t8" && -n "$t10" ]]; then
      delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
        if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
      }')"
    fi
    printf "  %-30s | %14s | %14s | %s\n" "$step" "${t8:-—}" "${t10:-—}" "$delta"
  done

  t8="$(run_time "${d8}report.txt")"
  t10="$(run_time "${d10}report.txt")"
  if [[ -n "$t8" || -n "$t10" ]]; then
    delta="—"
    if [[ -n "$t8" && -n "$t10" ]]; then
      delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
        if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
      }')"
    fi
    printf "  %-30s | %14s | %14s | %s\n" "run: Api" "${t8:-—}" "${t10:-—}" "$delta"
  fi

  hr_dash
  t8="$(step_time "${d8}report.txt"  "TOTAL")"
  t10="$(step_time "${d10}report.txt" "TOTAL")"
  delta="—"
  if [[ -n "$t8" && -n "$t10" ]]; then
    delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
      if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
    }')"
  fi
  printf "  %s%-30s | %14s | %14s | %s%s\n" "$C_BOLD" "TOTAL" "${t8:-—}" "${t10:-—}" "$delta" "$C_RESET"

  [[ $SHOW_DIFF -eq 1 ]] && render_terminal_packages "$cfg" "$d8" "$d10"

  return 0
}

# =============================================================================
#                          RENDER — MARKDOWN
# =============================================================================
md_escape_pipe() { local s="${1-}"; printf '%s' "${s//|/\\|}"; }

render_markdown() {
  local out="$1"
  mkdir -p "$(dirname "$out")"

  {
    echo "# Comparativo .NET — net8.0 vs net10.0"
    echo
    echo "- **Data:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- **Configurações:** ${CONFIGS[*]}"
    echo "- **Pacotes:** $([[ $SHOW_ALL_PKGS -eq 1 ]] && echo "todos" || echo "somente diferentes + exclusivos")"
    echo

    # ---- Execuções ----
    echo "## Todas as execuções encontradas"
    echo
    echo "| TFM | SDK | Runtime | Pasta | Pacotes |"
    echo "|---|---|---|---|---|"
    shopt -s nullglob
    for report in "${ARTIFACTS_ROOT}"/*/report.txt; do
      [[ -f "$report" ]] || continue
      local dir folder tfm sdk rt pkgs
      dir="$(dirname "$report")"
      folder="$(basename "$dir")"
      tfm="$(field "$report" "TFM")"
      sdk="$(field "$report" "SDK")"
      rt="$(field "$report" "Runtime" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
      pkgs="$(field "$report" "Pacotes trans")"
      echo "| \`$tfm\` | \`$sdk\` | \`$rt\` | \`$folder\` | $pkgs |"
    done
    shopt -u nullglob
    echo

    # ---- Por config ----
    for cfg in "${CONFIGS[@]}"; do
      echo "## Comparativo — $cfg"
      echo

      if [[ "${CFG_OK[$cfg]}" == "0" ]]; then
        [[ -z "${CFG_NET8_DIR[$cfg]}"  ]] && echo "- ❌ Nenhuma execução \`net8.0-$cfg\` encontrada"
        [[ -z "${CFG_NET10_DIR[$cfg]}" ]] && echo "- ❌ Nenhuma execução \`net10.0-$cfg\` encontrada"
        echo
        continue
      fi

      local d8="${CFG_NET8_DIR[$cfg]}" d10="${CFG_NET10_DIR[$cfg]}"
      echo "- **NET8:**  \`$(basename "$d8")\`"
      echo "- **NET10:** \`$(basename "$d10")\`"
      echo

      # Metadados
      echo "### Metadados"
      echo
      echo "| Campo | NET8 | NET10 |"
      echo "|---|---|---|"
      for key in "TFM" "SDK" "Runtime" "Config" "Pacotes trans"; do
        echo "| $(md_escape_pipe "$key") | $(md_escape_pipe "$(field "${d8}report.txt" "$key")") | $(md_escape_pipe "$(field "${d10}report.txt" "$key")") |"
      done
      echo

      # Tempos
      echo "### Tempos de execução"
      echo
      echo "| Etapa | NET8 | NET10 | Δ |"
      echo "|---|---:|---:|---:|"
      local step t8 t10 delta
      for step in "dotnet clean" "dotnet restore" "dotnet build" "dotnet test"; do
        t8="$(step_time "${d8}report.txt"  "$step")"
        t10="$(step_time "${d10}report.txt" "$step")"
        delta="—"
        if [[ -n "$t8" && -n "$t10" ]]; then
          delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
            if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
          }')"
        fi
        echo "| $step | ${t8:-—} | ${t10:-—} | $delta |"
      done

      t8="$(run_time "${d8}report.txt")"
      t10="$(run_time "${d10}report.txt")"
      if [[ -n "$t8" || -n "$t10" ]]; then
        delta="—"
        if [[ -n "$t8" && -n "$t10" ]]; then
          delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
            if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
          }')"
        fi
        echo "| run: Api | ${t8:-—} | ${t10:-—} | $delta |"
      fi

      t8="$(step_time "${d8}report.txt"  "TOTAL")"
      t10="$(step_time "${d10}report.txt" "TOTAL")"
      delta="—"
      if [[ -n "$t8" && -n "$t10" ]]; then
        delta="$(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
          if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs (%+.1f%%)", d, (d/a)*100
        }')"
      fi
      echo "| **TOTAL** | **${t8:-—}** | **${t10:-—}** | **$delta** |"
      echo

      # ---- Pacotes (sempre renderiza o cabeçalho) ----
      echo "### Pacotes transitivos"
      echo

      local csv8="${d8}transitive_packages.csv"
      local csv10="${d10}transitive_packages.csv"

      if [[ ! -f "$csv8" || ! -f "$csv10" ]]; then
        echo "> ⚠ CSVs de pacotes ausentes:"
        [[ ! -f "$csv8"  ]] && echo "> - \`$csv8\`"
        [[ ! -f "$csv10" ]] && echo "> - \`$csv10\`"
        echo
        continue
      fi

      local c8 c10
      c8="$(( $(wc -l < "$csv8")  - 1 ))"
      c10="$(( $(wc -l < "$csv10") - 1 ))"
      echo "- **NET8 total:** $c8 pacotes"
      echo "- **NET10 total:** $c10 pacotes"
      echo

      local pivot
      pivot="$(packages_pivot "$csv8" "$csv10")"

      if [[ -z "$pivot" ]]; then
        echo "_Árvores idênticas — nenhuma diferença._"
        echo
        continue
      fi

      local counts
      counts="$(packages_counts "$pivot")"
      local only8 only10 mudou igual
      IFS=$'\t' read -r only8 only10 mudou igual <<< "$counts"

      echo "**Resumo:** ◀ $only8 só NET8 · ▶ $only10 só NET10 · ≠ $mudou mudou · = $igual igual"
      echo
      echo "| Pacote | Projeto | NET8 | NET10 | Status |"
      echo "|---|---|---|---|---|"

      while IFS=$'\t' read -r pkg proj v8 v10 status; do
        [[ -z "$pkg" ]] && continue
        local label
        case "$status" in
          SO_NET8)  label="◀ só NET8"  ;;
          SO_NET10) label="▶ só NET10" ;;
          MUDOU)    label="≠ mudou"    ;;
          IGUAL)    label="= igual"    ;;
          *)        label="$status"    ;;
        esac
        echo "| \`$(md_escape_pipe "$pkg")\` | \`$(md_escape_pipe "$proj")\` | $v8 | $v10 | $label |"
      done <<< "$pivot"
      echo
    done
  } > "$out"

  return 0
}

# =============================================================================
#                          RENDER — CSV
# =============================================================================
render_csv() {
  local outdir="$1"
  mkdir -p "$outdir"

  # 1) executions.csv
  {
    echo "TFM,SDK,Runtime,Pasta,Pacotes"
    shopt -s nullglob
    for report in "${ARTIFACTS_ROOT}"/*/report.txt; do
      [[ -f "$report" ]] || continue
      local dir folder tfm sdk rt pkgs
      dir="$(dirname "$report")"
      folder="$(basename "$dir")"
      tfm="$(field "$report" "TFM")"
      sdk="$(field "$report" "SDK")"
      rt="$(field "$report" "Runtime" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
      pkgs="$(field "$report" "Pacotes trans")"
      echo "$(csv_escape "$tfm"),$(csv_escape "$sdk"),$(csv_escape "$rt"),$(csv_escape "$folder"),$(csv_escape "$pkgs")"
    done
    shopt -u nullglob
  } > "$outdir/executions.csv"

  # 2) por config
  for cfg in "${CONFIGS[@]}"; do
    if [[ "${CFG_OK[$cfg]}" == "0" ]]; then
      echo "Config $cfg incompleta — pulando CSVs" >&2
      continue
    fi

    local d8="${CFG_NET8_DIR[$cfg]}" d10="${CFG_NET10_DIR[$cfg]}"

    # metadata
    {
      echo "Campo,NET8,NET10"
      for key in "TFM" "SDK" "Runtime" "Config" "Pacotes trans"; do
        echo "$(csv_escape "$key"),$(csv_escape "$(field "${d8}report.txt" "$key")"),$(csv_escape "$(field "${d10}report.txt" "$key")")"
      done
    } > "$outdir/metadata_${cfg}.csv"

    # timings
    {
      echo "Etapa,NET8,NET10,DeltaSegundos,DeltaPct"
      local step t8 t10 d_abs d_pct
      for step in "dotnet clean" "dotnet restore" "dotnet build" "dotnet test"; do
        t8="$(step_time "${d8}report.txt"  "$step")"
        t10="$(step_time "${d10}report.txt" "$step")"
        d_abs=""; d_pct=""
        if [[ -n "$t8" && -n "$t10" ]]; then
          read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
            if (a==0) { print ",", exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
          }')
        fi
        echo "$(csv_escape "$step"),$(csv_escape "${t8:-}"),$(csv_escape "${t10:-}"),$d_abs,$d_pct"
      done

      t8="$(run_time "${d8}report.txt")"
      t10="$(run_time "${d10}report.txt")"
      if [[ -n "$t8" || -n "$t10" ]]; then
        d_abs=""; d_pct=""
        if [[ -n "$t8" && -n "$t10" ]]; then
          read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
            if (a==0) { print " ", exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
          }')
        fi
        echo "$(csv_escape "run: Api"),$(csv_escape "${t8:-}"),$(csv_escape "${t10:-}"),$d_abs,$d_pct"
      fi

      t8="$(step_time "${d8}report.txt"  "TOTAL")"
      t10="$(step_time "${d10}report.txt" "TOTAL")"
      d_abs=""; d_pct=""
      if [[ -n "$t8" && -n "$t10" ]]; then
        read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
          if (a==0) { print " ", exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
        }')
      fi
      echo "$(csv_escape "TOTAL"),$(csv_escape "${t8:-}"),$(csv_escape "${t10:-}"),$d_abs,$d_pct"
    } > "$outdir/timings_${cfg}.csv"

    # packages
    if [[ $SHOW_DIFF -eq 1 ]]; then
      local csv8="${d8}transitive_packages.csv"
      local csv10="${d10}transitive_packages.csv"
      {
        echo "Pacote,Projeto,NET8,NET10,Status"
        if [[ -f "$csv8" && -f "$csv10" ]]; then
          local pivot
          pivot="$(packages_pivot "$csv8" "$csv10")"
          if [[ -n "$pivot" ]]; then
            while IFS=$'\t' read -r pkg proj v8 v10 status; do
              [[ -z "$pkg" ]] && continue
              echo "$(csv_escape "$pkg"),$(csv_escape "$proj"),$(csv_escape "$v8"),$(csv_escape "$v10"),$(csv_escape "$status")"
            done <<< "$pivot"
          fi
        fi
      } > "$outdir/packages_${cfg}.csv"

      # Também salva o CSV cru lado a lado (para conferência)
      if [[ -f "$csv8" && -f "$csv10" ]]; then
        cp "$csv8"  "$outdir/packages_${cfg}_net8_raw.csv"
        cp "$csv10" "$outdir/packages_${cfg}_net10_raw.csv"
      fi
    fi
  done

  return 0
}

# =============================================================================
#                          EXECUÇÃO PRINCIPAL
# =============================================================================
cd "$(dirname "$0")"

if [[ -z "$OUT_DIR" ]]; then
  case "$FORMAT" in
    csv)       OUT_DIR="reports/compare_${TIMESTAMP}" ;;
    markdown)  OUT_DIR="reports" ;;
    all)       OUT_DIR="reports/compare_${TIMESTAMP}" ;;
  esac
fi

# ---- Terminal ----
if [[ "$FORMAT" == "terminal" || "$FORMAT" == "all" ]]; then
  echo; hr_thick
  printf "%s  COMPARADOR .NET — net8.0 vs net10.0%s\n" "$C_BOLD$C_CYAN" "$C_RESET"
  printf "%s  Configurações: %s%s\n" "$C_DIM" "${CONFIGS[*]}" "$C_RESET"
  hr_thick

  [[ $SHOW_CLASSIFY -eq 1 ]] && render_terminal_classify
  for cfg in "${CONFIGS[@]}"; do render_terminal_config "$cfg"; done

  section "RESUMO FINAL" "$C_GREEN"
  printf "  %s✓%s Comparação concluída para: %s\n" "$C_GREEN" "$C_RESET" "${CONFIGS[*]}"
  echo
fi

# ---- Markdown ----
if [[ "$FORMAT" == "markdown" || "$FORMAT" == "all" ]]; then
  mkdir -p "$OUT_DIR"
  if [[ "$FORMAT" == "all" ]]; then
    md_file="${OUT_DIR}/compare.md"
  else
    md_file="${OUT_DIR}/compare_${TIMESTAMP}.md"
  fi
  render_markdown "$md_file"
  printf "%s✓%s Markdown gerado: %s\n" "$C_GREEN" "$C_RESET" "$md_file"
fi

# ---- CSV ----
if [[ "$FORMAT" == "csv" || "$FORMAT" == "all" ]]; then
  mkdir -p "$OUT_DIR"
  render_csv "$OUT_DIR"
  printf "%s✓%s CSVs gerados em: %s/\n" "$C_GREEN" "$C_RESET" "$OUT_DIR"
  shopt -s nullglob
  for f in "$OUT_DIR"/*.csv; do
    printf "    %-40s (%s linhas)\n" "$(basename "$f")" "$(( $(wc -l < "$f") - 1 ))"
  done
  shopt -u nullglob
fi

echo
exit 0