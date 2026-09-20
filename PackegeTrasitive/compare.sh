#!/usr/bin/env bash
# =============================================================================
# compare.sh — Compara execuções net8.0 vs net10.0
#              Saída: terminal · csv · markdown · html · all
# =============================================================================
# Uso:
#   ./compare.sh                              # Debug + Release, terminal
#   ./compare.sh Release                      # só Release
#   ./compare.sh --format markdown            # gera reports/compare_<ts>.md
#   ./compare.sh --format csv                 # gera reports/compare_<ts>/*.csv
#   ./compare.sh --format html                # gera reports/compare_<ts>.html
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
  terminal|csv|markdown|html|all) ;;
  *) echo "Formato inválido: $FORMAT (use: terminal|csv|markdown|html|all)" >&2; exit 1 ;;
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
# HTML helpers
# -----------------------------------------------------------------------------
html_escape() {
  local s="${1-}"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&#39;}"
  printf '%s' "$s"
}

html_tfm_tag() {
  local tfm="$1"
  case "$tfm" in
    net8*)  printf '<span class="tfm-tag tfm-net8">%s</span>'  "$(html_escape "$tfm")" ;;
    net10*) printf '<span class="tfm-tag tfm-net10">%s</span>' "$(html_escape "$tfm")" ;;
    *)      printf '<span class="tfm-tag">%s</span>'           "$(html_escape "$tfm")" ;;
  esac
}

html_delta_span() {
  local d_abs="$1" d_pct="$2"
  if [[ -z "$d_abs" ]]; then printf '—'; return; fi
  local cls="neutral"
  local cmp
  cmp="$(awk -v d="$d_abs" 'BEGIN{ if (d<0) print "neg"; else if (d>0) print "pos"; else print "zero" }')"
  case "$cmp" in
    neg) cls="good" ;;
    pos) cls="bad" ;;
  esac
  printf '<span class="delta %s">%+.3fs <span class="pct">(%+.1f%%)</span></span>' "$cls" "$d_abs" "$d_pct"
}

config_total_delta() {
  local cfg="$1"
  local d8="${CFG_NET8_DIR[$cfg]}" d10="${CFG_NET10_DIR[$cfg]}"
  [[ -z "$d8" || -z "$d10" ]] && { echo "—"; return; }
  local t8 t10
  t8="$(step_time "${d8}report.txt" "TOTAL")"
  t10="$(step_time "${d10}report.txt" "TOTAL")"
  if [[ -n "$t8" && -n "$t10" ]]; then
    awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{ if (a==0) { print "—"; exit } d=b-a; printf "%+.3fs", d }'
  else
    echo "—"
  fi
}

html_pkg_rows() {
  local d8="$1" d10="$2"
  local csv8="${d8}transitive_packages.csv"
  local csv10="${d10}transitive_packages.csv"

  if [[ ! -f "$csv8" || ! -f "$csv10" ]]; then
    printf '<tr class="empty-row"><td colspan="5">CSVs de pacotes ausentes.</td></tr>\n'
    return
  fi

  local pivot
  pivot="$(packages_pivot "$csv8" "$csv10")"

  if [[ -z "$pivot" ]]; then
    printf '<tr class="empty-row"><td colspan="5">Árvores idênticas — nenhuma diferença.</td></tr>\n'
    return
  fi

  while IFS=$'\t' read -r pkg proj v8 v10 status; do
    [[ -z "$pkg" ]] && continue

    local st_cls st_label v10_cls v10_txt search
    case "$status" in
      SO_NET8)  st_cls="only8";   st_label="◀ só NET8"  ;;
      SO_NET10) st_cls="only10";  st_label="▶ só NET10" ;;
      MUDOU)    st_cls="changed"; st_label="≠ mudou"    ;;
      IGUAL)    st_cls="same";    st_label="= igual"    ;;
      *)        st_cls="";        st_label="$status"    ;;
    esac

    if [[ "$v10" == "-" || -z "$v10" ]]; then
      v10_cls="v-none"; v10_txt="—"
    else
      v10_cls="v-net10"; v10_txt="$(html_escape "$v10")"
    fi

    search="$(printf '%s %s' "$pkg" "$proj" | tr '[:upper:]' '[:lower:]')"

    printf '<tr data-search="%s"><td>%s</td><td>%s</td><td>%s</td><td class="%s">%s</td><td><span class="status %s">%s</span></td></tr>\n' \
      "$(html_escape "$search")" \
      "$(html_escape "$pkg")" \
      "$(html_escape "$proj")" \
      "$(html_escape "$v8")" \
      "$v10_cls" "$v10_txt" \
      "$st_cls" "$st_label"
  done <<< "$pivot"
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

      echo "### Metadados"
      echo
      echo "| Campo | NET8 | NET10 |"
      echo "|---|---|---|"
      for key in "TFM" "SDK" "Runtime" "Config" "Pacotes trans"; do
        echo "| $(md_escape_pipe "$key") | $(md_escape_pipe "$(field "${d8}report.txt" "$key")") | $(md_escape_pipe "$(field "${d10}report.txt" "$key")") |"
      done
      echo

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

    {
      echo "Campo,NET8,NET10"
      for key in "TFM" "SDK" "Runtime" "Config" "Pacotes trans"; do
        echo "$(csv_escape "$key"),$(csv_escape "$(field "${d8}report.txt" "$key")"),$(csv_escape "$(field "${d10}report.txt" "$key")")"
      done
    } > "$outdir/metadata_${cfg}.csv"

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

      if [[ -f "$csv8" && -f "$csv10" ]]; then
        cp "$csv8"  "$outdir/packages_${cfg}_net8_raw.csv"
        cp "$csv10" "$outdir/packages_${cfg}_net10_raw.csv"
      fi
    fi
  done

  return 0
}

# =============================================================================
#                          RENDER — HTML
# =============================================================================
render_html_panel() {
  local cfg="$1"
  local d8="${CFG_NET8_DIR[$cfg]}" d10="${CFG_NET10_DIR[$cfg]}"

  printf '    <div class="card">\n'
  printf '      <div class="card-head">\n        <h2>Comparativo — %s</h2>\n      </div>\n' "$(html_escape "$cfg")"

  if [[ "${CFG_OK[$cfg]}" == "0" ]]; then
    printf '      <div class="card-body" style="padding:18px">\n'
    [[ -z "$d8"  ]] && printf '        <p>❌ Nenhuma execução <code>net8.0-%s</code> encontrada.</p>\n'  "$(html_escape "$cfg")"
    [[ -z "$d10" ]] && printf '        <p>❌ Nenhuma execução <code>net10.0-%s</code> encontrada.</p>\n' "$(html_escape "$cfg")"
    printf '      </div>\n    </div>\n'
    return 0
  fi

  # ---- Métricas ----
  printf '      <div class="metrics">\n'
  printf '        <div class="metric"><div class="label">NET8</div><div class="value">%s</div></div>\n' \
    "$(html_escape "$(basename "$d8")")"
  printf '        <div class="metric"><div class="label">NET10</div><div class="value">%s</div></div>\n' \
    "$(html_escape "$(basename "$d10")")"
  printf '        <div class="metric"><div class="label">SDK</div><div class="value">%s → %s</div></div>\n' \
    "$(html_escape "$(field "${d8}report.txt"  "SDK")")" \
    "$(html_escape "$(field "${d10}report.txt" "SDK")")"
  printf '        <div class="metric"><div class="label">Runtime</div><div class="value">%s</div></div>\n' \
    "$(html_escape "$(field "${d10}report.txt" "Runtime")")"

  local csv8="${d8}transitive_packages.csv"
  local csv10="${d10}transitive_packages.csv"
  local c8="—" c10="—"
  [[ -f "$csv8"  ]] && c8="$(( $(wc -l < "$csv8")  - 1 ))"
  [[ -f "$csv10" ]] && c10="$(( $(wc -l < "$csv10") - 1 ))"
  printf '        <div class="metric"><div class="label">Pacotes transitivos</div><div class="value big">%s → %s</div></div>\n' "$c8" "$c10"
  printf '      </div>\n'

  # ---- Tempos ----
  printf '      <div class="table-wrap">\n        <table>\n'
  printf '          <thead><tr><th>Etapa</th><th class="num">NET8</th><th class="num">NET10</th><th class="num">Δ</th></tr></thead>\n'
  printf '          <tbody>\n'

  local step t8 t10 d_abs d_pct
  for step in "dotnet clean" "dotnet restore" "dotnet build" "dotnet test"; do
    t8="$(step_time "${d8}report.txt"  "$step")"
    t10="$(step_time "${d10}report.txt" "$step")"
    d_abs=""; d_pct=""
    if [[ -n "$t8" && -n "$t10" ]]; then
      read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
        if (a==0) { print "", ""; exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
      }')
    fi
    printf '            <tr><td><code>%s</code></td><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td></tr>\n' \
      "$(html_escape "$step")" "${t8:-—}" "${t10:-—}" "$(html_delta_span "$d_abs" "$d_pct")"
  done

  t8="$(run_time "${d8}report.txt")"
  t10="$(run_time "${d10}report.txt")"
  if [[ -n "$t8" || -n "$t10" ]]; then
    d_abs=""; d_pct=""
    if [[ -n "$t8" && -n "$t10" ]]; then
      read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
        if (a==0) { print "", ""; exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
      }')
    fi
    printf '            <tr><td><code>run: Api</code></td><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td></tr>\n' \
      "${t8:-—}" "${t10:-—}" "$(html_delta_span "$d_abs" "$d_pct")"
  fi

  t8="$(step_time "${d8}report.txt"  "TOTAL")"
  t10="$(step_time "${d10}report.txt" "TOTAL")"
  d_abs=""; d_pct=""
  if [[ -n "$t8" && -n "$t10" ]]; then
    read -r d_abs d_pct < <(awk -v a="${t8%s}" -v b="${t10%s}" 'BEGIN{
      if (a==0) { print "", ""; exit } d=b-a; printf "%.6f %.2f", d, 100*(d/a)
    }')
  fi
  printf '            <tr class="total"><td>TOTAL</td><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td></tr>\n' \
    "${t8:-—}" "${t10:-—}" "$(html_delta_span "$d_abs" "$d_pct")"

  printf '          </tbody>\n        </table>\n      </div>\n'

  # ---- Badges de resumo ----
  local only8=0 only10=0 mudou=0 igual=0
  if [[ -f "$csv8" && -f "$csv10" ]]; then
    local pivot
    pivot="$(packages_pivot "$csv8" "$csv10")"
    if [[ -n "$pivot" && "$pivot" != ERRO_* ]]; then
      local counts
      counts="$(packages_counts "$pivot")"
      IFS=$'\t' read -r only8 only10 mudou igual <<< "$counts"
    fi
  fi

  printf '      <div class="summary">\n'
  printf '        <span class="badge only8">◀ <b>%s</b> só NET8</span>\n'   "$only8"
  printf '        <span class="badge only10">▶ <b>%s</b> só NET10</span>\n' "$only10"
  printf '        <span class="badge changed">≠ <b>%s</b> mudou</span>\n'   "$mudou"
  printf '        <span class="badge same">= <b>%s</b> igual</span>\n'      "$igual"
  printf '      </div>\n'

  # ---- Bloco de pacotes ----
  printf '      <div class="pkg-block">\n'
  printf '        <div class="toolbar">\n'
  printf '          <input type="search" class="filter" placeholder="Filtrar por pacote ou projeto…" aria-label="Filtrar pacotes">\n'
  printf '          <span class="counter"></span>\n'
  printf '        </div>\n'
  printf '        <div class="table-wrap">\n'
  printf '          <table class="pkg-table">\n'
  printf '            <thead><tr><th>Pacote</th><th>Projeto</th><th>NET8</th><th>NET10</th><th>Status</th></tr></thead>\n'
  printf '            <tbody>\n'
  html_pkg_rows "$d8" "$d10"
  printf '            </tbody>\n'
  printf '          </table>\n'
  printf '        </div>\n'
  printf '      </div>\n'

  printf '    </div>\n'
}

render_html() {
  local out="$1"
  mkdir -p "$(dirname "$out")"

  # Conta execuções
  local exec_count=0
  shopt -s nullglob
  for rpt in "${ARTIFACTS_ROOT}"/*/report.txt; do
    [[ -f "$rpt" ]] && exec_count=$((exec_count+1))
  done
  shopt -u nullglob

  local pkg_mode="somente diferentes + exclusivos"
  [[ $SHOW_ALL_PKGS -eq 1 ]] && pkg_mode="todos"

  local configs_html="" first=1
  for cfg in "${CONFIGS[@]}"; do
    [[ $first -eq 0 ]] && configs_html+=" · "
    configs_html+="<b>$(html_escape "$cfg")</b>"
    first=0
  done

  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  {
    # ============ HEAD ============
    cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Comparativo .NET — net8.0 vs net10.0</title>
<style>
  :root{
    --bg:#f4f5f7;
    --card:#ffffff;
    --card-2:#fafbfc;
    --text:#1b1f24;
    --muted:#5b6470;
    --border:#e2e6ea;
    --accent:#512bd4;
    --accent-2:#8a2be2;
    --good:#0f7b3f;
    --good-bg:#e6f6ec;
    --bad:#b3261e;
    --bad-bg:#fdeceb;
    --warn:#8a5300;
    --warn-bg:#fff4e0;
    --info:#0b5cad;
    --info-bg:#e7f0fb;
    --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
    --shadow: 0 1px 2px rgba(16,24,40,.05), 0 8px 24px rgba(16,24,40,.06);
  }
  @media (prefers-color-scheme: dark){
    :root{
      --bg:#0f1216;
      --card:#171b21;
      --card-2:#1c2128;
      --text:#e6e9ee;
      --muted:#9aa4b2;
      --border:#262c34;
      --good:#5fd08a;
      --good-bg:#12291c;
      --bad:#ff8a80;
      --bad-bg:#2c1614;
      --warn:#ffc46b;
      --warn-bg:#2b2113;
      --info:#79b8ff;
      --info-bg:#122234;
      --shadow: 0 1px 2px rgba(0,0,0,.4), 0 8px 24px rgba(0,0,0,.35);
    }
  }

  *{box-sizing:border-box}
  html{scroll-behavior:smooth}
  body{
    margin:0;
    background:var(--bg);
    color:var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    font-size:15px;
    line-height:1.5;
    -webkit-font-smoothing:antialiased;
  }

  .hero{
    background:
      radial-gradient(1200px 400px at 10% -20%, rgba(138,43,226,.55), transparent 60%),
      linear-gradient(135deg, #512bd4 0%, #7b3fe4 55%, #9b4dff 100%);
    color:#fff;
    padding:38px 24px 34px;
  }
  .hero-inner{max-width:1180px;margin:0 auto}
  .eyebrow{
    margin:0 0 8px;
    text-transform:uppercase;
    letter-spacing:.14em;
    font-size:11px;
    font-weight:700;
    opacity:.85;
  }
  .hero h1{
    margin:0 0 18px;
    font-size:clamp(24px, 3.4vw, 38px);
    line-height:1.15;
    font-weight:800;
    letter-spacing:-.02em;
  }
  .hero h1 .tfm{
    font-family:var(--mono);
    font-weight:700;
    background:rgba(255,255,255,.16);
    border:1px solid rgba(255,255,255,.28);
    padding:2px 10px;
    border-radius:8px;
    font-size:.82em;
    white-space:nowrap;
  }
  .hero h1 .vs{
    font-weight:500;
    opacity:.75;
    font-size:.7em;
    padding:0 4px;
  }
  .chips{display:flex;flex-wrap:wrap;gap:8px}
  .chip{
    display:inline-flex;
    align-items:center;
    gap:6px;
    background:rgba(255,255,255,.14);
    border:1px solid rgba(255,255,255,.25);
    padding:5px 11px;
    border-radius:999px;
    font-size:12.5px;
    backdrop-filter: blur(4px);
  }
  .chip b{font-weight:700}
  .chip code{font-family:var(--mono);font-size:12px}

  main{max-width:1180px;margin:0 auto;padding:26px 24px 80px}
  section{margin-bottom:26px}
  .card{
    background:var(--card);
    border:1px solid var(--border);
    border-radius:14px;
    box-shadow:var(--shadow);
    overflow:hidden;
  }
  .card-head{
    display:flex;
    align-items:baseline;
    justify-content:space-between;
    gap:12px;
    flex-wrap:wrap;
    padding:16px 18px;
    border-bottom:1px solid var(--border);
    background:var(--card-2);
  }
  .card-head h2{
    margin:0;
    font-size:15px;
    font-weight:700;
    letter-spacing:-.01em;
  }
  .card-head .sub{font-size:12.5px;color:var(--muted);font-family:var(--mono)}
  .card-body{padding:0}

  .table-wrap{overflow-x:auto}
  table{width:100%;border-collapse:collapse;font-size:14px}
  thead th{
    position:sticky;top:0;z-index:1;
    background:var(--card-2);
    text-align:left;
    font-size:11.5px;
    text-transform:uppercase;
    letter-spacing:.06em;
    color:var(--muted);
    font-weight:700;
    padding:10px 14px;
    border-bottom:1px solid var(--border);
    white-space:nowrap;
  }
  tbody td{
    padding:10px 14px;
    border-bottom:1px solid var(--border);
    vertical-align:top;
  }
  tbody tr:last-child td{border-bottom:none}
  tbody tr:hover{background:rgba(81,43,212,.045)}
  @media (prefers-color-scheme: dark){
    tbody tr:hover{background:rgba(155,77,255,.10)}
  }
  .num{text-align:right;font-family:var(--mono);font-variant-numeric:tabular-nums;white-space:nowrap}
  th.num{text-align:right}
  code,.mono{font-family:var(--mono);font-size:12.5px}

  .runs td:first-child code{font-weight:700}
  .tfm-tag{
    display:inline-block;
    font-family:var(--mono);
    font-size:11.5px;
    font-weight:700;
    padding:2px 8px;
    border-radius:6px;
    border:1px solid transparent;
  }
  .tfm-net8{background:var(--info-bg);color:var(--info);border-color:color-mix(in srgb, var(--info) 25%, transparent)}
  .tfm-net10{background:color-mix(in srgb, var(--accent) 12%, transparent);color:var(--accent);border-color:color-mix(in srgb, var(--accent) 30%, transparent)}
  @media (prefers-color-scheme: dark){
    .tfm-net10{background:rgba(155,77,255,.16);color:#c9a6ff;border-color:rgba(155,77,255,.35)}
  }

  .delta{font-family:var(--mono);font-size:12.5px;font-weight:700;white-space:nowrap}
  .delta.good{color:var(--good)}
  .delta.bad{color:var(--bad)}
  .delta.neutral{color:var(--muted)}
  .delta .pct{font-weight:600;opacity:.8;font-size:11.5px}

  tr.total td{
    font-weight:800;
    background:color-mix(in srgb, var(--accent) 6%, transparent);
    border-top:2px solid color-mix(in srgb, var(--accent) 35%, var(--border));
  }
  @media (prefers-color-scheme: dark){
    tr.total td{background:rgba(155,77,255,.10)}
  }

  .tabs{
    display:flex;
    gap:6px;
    padding:6px;
    background:var(--card);
    border:1px solid var(--border);
    border-radius:12px;
    box-shadow:var(--shadow);
    width:max-content;
    max-width:100%;
    margin-bottom:20px;
    overflow-x:auto;
  }
  .tab{
    appearance:none;
    border:0;
    background:transparent;
    color:var(--muted);
    font:inherit;
    font-weight:700;
    font-size:13.5px;
    padding:8px 18px;
    border-radius:8px;
    cursor:pointer;
    display:inline-flex;
    align-items:center;
    gap:8px;
    transition:background .15s, color .15s;
    white-space:nowrap;
  }
  .tab:hover{background:var(--card-2);color:var(--text)}
  .tab[aria-selected="true"]{
    background:linear-gradient(135deg,#512bd4,#8a2be2);
    color:#fff;
    box-shadow:0 2px 10px rgba(81,43,212,.35);
  }
  .tab .tag{
    font-family:var(--mono);
    font-size:11px;
    padding:1px 7px;
    border-radius:999px;
    background:rgba(128,128,128,.18);
  }
  .tab[aria-selected="true"] .tag{background:rgba(255,255,255,.22)}
  .panel[hidden]{display:none}

  .summary{
    display:flex;
    flex-wrap:wrap;
    gap:8px;
    padding:14px 18px;
    border-bottom:1px solid var(--border);
    background:var(--card-2);
  }
  .badge{
    display:inline-flex;
    align-items:center;
    gap:7px;
    font-size:12.5px;
    font-weight:600;
    padding:5px 11px;
    border-radius:999px;
    border:1px solid transparent;
  }
  .badge b{font-family:var(--mono);font-weight:800}
  .badge.only8{background:var(--info-bg);color:var(--info)}
  .badge.only10{background:color-mix(in srgb, var(--accent) 12%, transparent);color:var(--accent)}
  .badge.changed{background:var(--warn-bg);color:var(--warn)}
  .badge.same{background:var(--good-bg);color:var(--good)}
  @media (prefers-color-scheme: dark){
    .badge.only10{background:rgba(155,77,255,.16);color:#c9a6ff}
  }

  .toolbar{
    display:flex;
    align-items:center;
    justify-content:space-between;
    gap:12px;
    flex-wrap:wrap;
    padding:14px 18px;
    border-bottom:1px solid var(--border);
    background:var(--card-2);
  }
  .filter{
    flex:1 1 260px;
    min-width:0;
    font:inherit;
    font-size:13.5px;
    color:var(--text);
    background:var(--card);
    border:1px solid var(--border);
    border-radius:9px;
    padding:8px 12px;
    outline:none;
    transition:border-color .15s, box-shadow .15s;
  }
  .filter::placeholder{color:var(--muted)}
  .filter:focus{
    border-color:var(--accent);
    box-shadow:0 0 0 3px color-mix(in srgb, var(--accent) 20%, transparent);
  }
  .counter{font-size:12.5px;color:var(--muted);font-family:var(--mono);white-space:nowrap}

  .pkg-table td:nth-child(1){font-family:var(--mono);font-size:12.5px;word-break:break-word}
  .pkg-table td:nth-child(2){color:var(--muted);font-size:12.5px;font-family:var(--mono);white-space:nowrap}
  .pkg-table td:nth-child(3),
  .pkg-table td:nth-child(4){font-family:var(--mono);font-size:12.5px;white-space:nowrap;color:var(--muted)}
  .pkg-table .v-net10{color:var(--accent);font-weight:700}
  @media (prefers-color-scheme: dark){
    .pkg-table .v-net10{color:#c9a6ff}
  }
  .pkg-table .v-none{opacity:.45}

  .status{
    display:inline-block;
    font-size:11.5px;
    font-weight:700;
    padding:2px 9px;
    border-radius:999px;
    white-space:nowrap;
    border:1px solid transparent;
  }
  .status.changed{background:var(--warn-bg);color:var(--warn);border-color:color-mix(in srgb, var(--warn) 25%, transparent)}
  .status.only8{background:var(--info-bg);color:var(--info);border-color:color-mix(in srgb, var(--info) 25%, transparent)}
  .status.only10{background:color-mix(in srgb, var(--accent) 12%, transparent);color:var(--accent);border-color:color-mix(in srgb, var(--accent) 30%, transparent)}
  .status.same{background:var(--good-bg);color:var(--good);border-color:color-mix(in srgb, var(--good) 25%, transparent)}

  .empty-row td{
    text-align:center;
    color:var(--muted);
    padding:26px 14px;
    font-style:italic;
  }

  .metrics{
    display:grid;
    grid-template-columns:repeat(auto-fit, minmax(170px,1fr));
    gap:1px;
    background:var(--border);
    border-bottom:1px solid var(--border);
  }
  .metric{
    background:var(--card);
    padding:14px 18px;
  }
  .metric .label{
    font-size:11px;
    text-transform:uppercase;
    letter-spacing:.07em;
    font-weight:700;
    color:var(--muted);
    margin-bottom:5px;
  }
  .metric .value{font-size:14px;font-family:var(--mono);word-break:break-all}
  .metric .value.big{font-size:20px;font-weight:800}

  footer{
    max-width:1180px;
    margin:0 auto;
    padding:0 24px 48px;
    color:var(--muted);
    font-size:12.5px;
    text-align:center;
  }
  footer code{font-size:12px}

  @media (max-width:640px){
    main{padding:20px 14px 60px}
    .hero{padding:28px 16px 26px}
    thead th, tbody td{padding:9px 10px}
    .card-head{padding:13px 14px}
    .toolbar{padding:12px 14px}
    .summary{padding:12px 14px}
  }
</style>
</head>
<body>
HTML_HEAD

    # ============ HERO ============
    printf '<header class="hero">\n'
    printf '  <div class="hero-inner">\n'
    printf '    <p class="eyebrow">Relatório de benchmark</p>\n'
    printf '    <h1>Comparativo .NET <span class="tfm">net8.0</span> <span class="vs">vs</span> <span class="tfm">net10.0</span></h1>\n'
    printf '    <div class="chips">\n'
    printf '      <span class="chip">📅 <b>%s</b></span>\n' "$(html_escape "$now")"
    printf '      <span class="chip">⚙️ %s</span>\n' "$configs_html"
    printf '      <span class="chip">📦 Pacotes: <b>%s</b></span>\n' "$(html_escape "$pkg_mode")"
    printf '      <span class="chip">🏃 <b>%d</b> execuções</span>\n' "$exec_count"
    printf '    </div>\n'
    printf '  </div>\n'
    printf '</header>\n\n'

    printf '<main>\n\n'

    # ============ EXECUÇÕES ============
    printf '  <section>\n    <div class="card">\n'
    printf '      <div class="card-head">\n        <h2>Todas as execuções encontradas</h2>\n        <span class="sub">%d execuções</span>\n      </div>\n' "$exec_count"
    printf '      <div class="table-wrap">\n        <table class="runs">\n'
    printf '          <thead>\n            <tr><th>TFM</th><th>SDK</th><th>Runtime</th><th>Pasta</th><th class="num">Pacotes</th></tr>\n          </thead>\n'
    printf '          <tbody>\n'
    shopt -s nullglob
    for rpt in "${ARTIFACTS_ROOT}"/*/report.txt; do
      [[ -f "$rpt" ]] || continue
      local _dir _folder _tfm _sdk _rt _pkgs
      _dir="$(dirname "$rpt")"
      _folder="$(basename "$_dir")"
      _tfm="$(field "$rpt" "TFM")"
      _sdk="$(field "$rpt" "SDK")"
      _rt="$(field "$rpt" "Runtime" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
      _pkgs="$(field "$rpt" "Pacotes trans")"
      printf '            <tr>\n'
      printf '              <td>%s</td>\n' "$(html_tfm_tag "$_tfm")"
      printf '              <td><code>%s</code></td>\n' "$(html_escape "$_sdk")"
      printf '              <td><code>%s</code></td>\n' "$(html_escape "$_rt")"
      printf '              <td><code>%s</code></td>\n' "$(html_escape "$_folder")"
      printf '              <td class="num">%s</td>\n' "$(html_escape "$_pkgs")"
      printf '            </tr>\n'
    done
    shopt -u nullglob
    printf '          </tbody>\n        </table>\n      </div>\n    </div>\n  </section>\n\n'

    # ============ TABS ============
    printf '  <div class="tabs" role="tablist" aria-label="Configurações de build">\n'
    local i=0
    for cfg in "${CONFIGS[@]}"; do
      local cid
      cid="$(printf '%s' "$cfg" | tr '[:upper:]' '[:lower:]')"
      local sel="false"
      [[ $i -eq 0 ]] && sel="true"
      local delta_tag
      delta_tag="$(config_total_delta "$cfg")"
      printf '    <button class="tab" role="tab" id="tab-%s" aria-controls="panel-%s" aria-selected="%s">%s <span class="tag">%s</span></button>\n' \
        "$cid" "$cid" "$sel" "$(html_escape "$cfg")" "$(html_escape "$delta_tag")"
      i=$((i+1))
    done
    printf '  </div>\n\n'

    # ============ PANELS ============
    i=0
    for cfg in "${CONFIGS[@]}"; do
      local cid
      cid="$(printf '%s' "$cfg" | tr '[:upper:]' '[:lower:]')"
      local hidden=""
      [[ $i -gt 0 ]] && hidden=" hidden"
      printf '  <section class="panel" id="panel-%s" role="tabpanel" aria-labelledby="tab-%s"%s>\n' "$cid" "$cid" "$hidden"
      render_html_panel "$cfg"
      printf '  </section>\n\n'
      i=$((i+1))
    done

    printf '</main>\n\n'

    # ============ FOOTER + SCRIPT ============
    printf '<footer>\n  Gerado por <code>compare.sh</code> · %s\n</footer>\n\n' "$(html_escape "$now")"

    cat <<'HTML_SCRIPT'
<script>
(function () {
  "use strict";

  /* ---------- TABS ---------- */
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  var panels = Array.prototype.slice.call(document.querySelectorAll('[role="tabpanel"]'));

  function selectTab(tab) {
    tabs.forEach(function (t) {
      t.setAttribute("aria-selected", t === tab ? "true" : "false");
    });
    panels.forEach(function (p) {
      p.hidden = p.id !== tab.getAttribute("aria-controls");
    });
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { selectTab(tab); });
    tab.addEventListener("keydown", function (e) {
      var next = null;
      if (e.key === "ArrowRight") next = tabs[(i + 1) % tabs.length];
      if (e.key === "ArrowLeft")  next = tabs[(i - 1 + tabs.length) % tabs.length];
      if (next) { e.preventDefault(); next.focus(); selectTab(next); }
    });
  });

  if (tabs.length > 0) selectTab(tabs[0]);

  /* ---------- FILTRO POR TABELA ---------- */
  document.querySelectorAll('.pkg-block').forEach(function (block) {
    var input   = block.querySelector('.filter');
    var counter = block.querySelector('.counter');
    var tbody   = block.querySelector('.pkg-table tbody');
    var rows    = Array.prototype.slice.call(tbody.querySelectorAll('tr[data-search]'));

    function applyFilter() {
      var q = input.value.trim().toLowerCase();
      var visible = 0;

      rows.forEach(function (tr) {
        var match = !q || (tr.dataset.search || '').indexOf(q) !== -1;
        tr.hidden = !match;
        if (match) visible++;
      });

      var oldEmpty = tbody.querySelector('.empty-row');
      if (oldEmpty) oldEmpty.remove();

      if (visible === 0) {
        var empty = document.createElement('tr');
        empty.className = 'empty-row';
        var td = document.createElement('td');
        td.colSpan = 5;
        td.textContent = 'Nenhum pacote corresponde ao filtro.';
        empty.appendChild(td);
        tbody.appendChild(empty);
      }

      counter.textContent = visible + ' de ' + rows.length + ' linhas';
    }

    input.addEventListener('input', applyFilter);
    applyFilter();
  });
})();
</script>
</body>
</html>
HTML_SCRIPT
  } > "$out"

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
    html)      OUT_DIR="reports" ;;
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

# ---- HTML ----
if [[ "$FORMAT" == "html" || "$FORMAT" == "all" ]]; then
  mkdir -p "$OUT_DIR"
  if [[ "$FORMAT" == "all" ]]; then
    html_file="${OUT_DIR}/compare.html"
  else
    html_file="${OUT_DIR}/compare_${TIMESTAMP}.html"
  fi
  render_html "$html_file"
  printf "%s✓%s HTML gerado: %s\n" "$C_GREEN" "$C_RESET" "$html_file"
fi

echo
exit 0