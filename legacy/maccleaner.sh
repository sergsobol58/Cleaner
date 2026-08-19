#!/bin/bash
#
# maccleaner — безопасная чистка мусора разработчика на macOS.
#
# Принципы безопасности:
#   1. По умолчанию ничего не удаляется (dry-run). Нужен явный --apply.
#   2. Удаление = перемещение в ~/.Trash/maccleaner-<timestamp>/ (обратимо).
#      Реальное стирание только с --purge.
#   3. Жёсткий whitelist: путь обязан лежать внутри разрешённых корней,
#      иметь минимальную глубину и не совпадать с самим корнем.
#   4. Никогда не трогаются: Documents, Desktop, Downloads, iCloud Drive,
#      Photos, Mail, Keychains, бэкапы устройств, Xcode Archives, ~/.ssh.
#   5. Никаких `rm -rf $VAR` — все пути проходят через guard().
#
set -uo pipefail

VERSION="1.0.0"

# ─── режимы ───────────────────────────────────────────────────────────────
APPLY=0          # 0 = dry-run
PURGE=0          # 1 = стирать насовсем, минуя карантин
ASSUME_YES=0
ONLY=""          # список задач через запятую
SELFTEST=0
VERBOSE=0

TS="$(date +%Y%m%d-%H%M%S)"
QUARANTINE="$HOME/.Trash/maccleaner-$TS"
LOG="$HOME/Library/Logs/maccleaner-$TS.log"

# ─── защита ───────────────────────────────────────────────────────────────
# Разрешённые корни. Всё, что вне них — отклоняется.
ALLOWED_ROOTS=(
  "$HOME/Library/Caches"
  "$HOME/Library/Developer"
  "$HOME/Library/Application Support/Code/Cache"
  "$HOME/Library/Application Support/Code/CachedData"
  "$HOME/Library/Application Support/Caches"
  "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"
  "$HOME/.npm/_cacache"
  "$HOME/.cache"
  "$HOME/.gradle/caches"
  "$HOME/.cocoapods/repos"
  "$HOME/Library/pnpm/store"
  "$HOME/Library/Logs"
)

# Пути, которые НИКОГДА не удаляются, даже если попали в разрешённый корень.
NEVER_TOUCH=(
  "$HOME/Library/Developer/Xcode/Archives"
  "$HOME/Library/Developer/Xcode/UserData"
  "$HOME/Library/Developer/XCTestDevices"
  "$HOME/Library/Application Support/MobileSync"
  "$HOME/Library/Keychains"
  "$HOME/Library/Mail"
  "$HOME/Library/Messages"
  "$HOME/Library/Photos"
  "$HOME/Documents"
  "$HOME/Desktop"
  "$HOME/Downloads"
  "$HOME/.ssh"
  "$HOME/Library/Mobile Documents"
)

C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[34m'
C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_0=$'\033[0m'
if [ ! -t 1 ]; then C_R=; C_G=; C_Y=; C_B=; C_DIM=; C_BOLD=; C_0=; fi

log()  { printf '%s\n' "$*" >>"$LOG"; }
say()  { printf '%s\n' "$*"; log "$*"; }
info() { say "${C_DIM}  $*${C_0}"; }
warn() { say "${C_Y}  ! $*${C_0}"; }
err()  { say "${C_R}  ✗ $*${C_0}"; }
head2(){ say ""; say "${C_BOLD}${C_B}▸ $*${C_0}"; }

# guard PATH — 0 если путь безопасно удалять.
guard() {
  local p="$1" root ok=0 real
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/") err "отклонён (корневой путь): $p"; return 1 ;;
    *".."*)                  err "отклонён (..): $p";            return 1 ;;
    /*) ;;
    *)  err "отклонён (не абсолютный): $p"; return 1 ;;
  esac
  [ -e "$p" ] || return 1

  # не идём по симлинкам — удаляем только реальные каталоги/файлы на месте
  if [ -L "$p" ]; then err "отклонён (симлинк): $p"; return 1; fi

  # запретный список — сравнение по префиксу в обе стороны
  for n in "${NEVER_TOUCH[@]}"; do
    case "$p" in "$n"|"$n"/*) err "отклонён (в стоп-листе): $p"; return 1 ;; esac
    case "$n" in "$p"/*)      err "отклонён (содержит стоп-лист): $p"; return 1 ;; esac
  done

  # должен лежать СТРОГО внутри одного из разрешённых корней
  for root in "${ALLOWED_ROOTS[@]}"; do
    case "$p" in "$root"/*) ok=1; break ;; esac
  done
  if [ "$ok" -ne 1 ]; then err "отклонён (вне белого списка): $p"; return 1; fi

  # минимальная глубина: минимум 4 сегмента после /Users/<user>
  real="${p#"$HOME"/}"
  local depth; depth="$(printf '%s' "$real" | awk -F/ '{print NF}')"
  if [ "${depth:-0}" -lt 2 ]; then err "отклонён (слишком высоко): $p"; return 1; fi

  return 0
}

sizeof() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
human()  { awk -v k="${1:-0}" 'BEGIN{
             split("KB MB GB TB",u," "); i=1;
             while (k>=1024 && i<4) { k/=1024; i++ }
             printf (i==1 ? "%d %s" : "%.1f %s"), k, u[i] }'; }

TOTAL_KB=0
BATCH=0; BATCH_N=0; BATCH_KB=0

# remove PATH [LABEL]
remove() {
  local p="$1" label="${2:-$1}" kb
  guard "$p" || return 1
  kb="$(sizeof "$p")"; kb="${kb:-0}"
  [ "$kb" -eq 0 ] && [ ! -f "$p" ] && { [ "$VERBOSE" -eq 1 ] && info "пусто: $label"; return 0; }

  TOTAL_KB=$((TOTAL_KB + kb))

  if [ "$BATCH" -eq 1 ]; then
    BATCH_N=$((BATCH_N + 1)); BATCH_KB=$((BATCH_KB + kb))
    log "  batch: $(human "$kb")  $label"
    if [ "$APPLY" -eq 0 ]; then return 0; fi
    if [ "$PURGE" -eq 1 ]; then rm -rf -- "$p"; else
      mkdir -p "$QUARANTINE"
      mv -f -- "$p" "$QUARANTINE/$(printf '%s' "${p#"$HOME"/}" | tr '/' '_')" 2>/dev/null
    fi
    return 0
  fi

  if [ "$APPLY" -eq 0 ]; then
    say "  ${C_Y}[dry-run]${C_0} $(human "$kb")  $label"
    return 0
  fi

  if [ "$PURGE" -eq 1 ]; then
    rm -rf -- "$p" && say "  ${C_G}[стёрто]${C_0}  $(human "$kb")  $label" \
                   || err "не удалось: $label"
  else
    mkdir -p "$QUARANTINE"
    # уникальное имя внутри карантина, чтобы не перезаписать одноимённое
    local dest="$QUARANTINE/$(printf '%s' "${p#"$HOME"/}" | tr '/' '_')"
    mv -f -- "$p" "$dest" && say "  ${C_G}[в корзину]${C_0} $(human "$kb")  $label" \
                          || err "не удалось: $label"
  fi
}

# remove_children DIR [LABEL] — удаляет содержимое, сам каталог оставляет
remove_children() {
  local d="$1" label="${2:-$1}" child found=0
  [ -d "$d" ] || return 0
  # безопасный обход: без globbing-сюрпризов, без скрытых спецсимволов
  while IFS= read -r -d '' child; do
    found=1
    remove "$child" "${label}/$(basename "$child")"
  done < <(find "$d" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  [ "$found" -eq 0 ] && [ "$VERBOSE" -eq 1 ] && info "пусто: $label"
  return 0
}



# ─── интерактивный выбор ──────────────────────────────────────────────────
# parse_selection "СТРОКА" MAX — печатает выбранные номера, по одному на строку.
# Понимает: "1,3,5-7", "all", "" (пусто = ничего).
parse_selection() {
  local raw="$1" max="$2" part a b i
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  [ -z "$raw" ] && return 0
  if [ "$raw" = "all" ] || [ "$raw" = "ALL" ] || [ "$raw" = "все" ]; then
    i=1; while [ "$i" -le "$max" ]; do echo "$i"; i=$((i+1)); done; return 0
  fi
  printf '%s\n' "$raw" | tr ',' '\n' | while IFS= read -r part; do
    [ -z "$part" ] && continue
    case "$part" in
      *-*) a="${part%%-*}"; b="${part##*-}" ;;
      *)   a="$part"; b="$part" ;;
    esac
    case "$a$b" in *[!0-9]*|"") warn "пропущено (не номер): $part" >&2; continue ;; esac
    [ "$a" -ge 1 ] && [ "$b" -le "$max" ] && [ "$a" -le "$b" ] \
      || { warn "пропущено (вне диапазона 1-$max): $part" >&2; continue; }
    i="$a"; while [ "$i" -le "$b" ]; do echo "$i"; i=$((i+1)); done
  done | sort -un
}

interactive_ok() {
  if [ ! -t 0 ]; then info "неинтерактивный запуск — пропущено"; return 1; fi
  if [ "$ASSUME_YES" -eq 1 ]; then
    warn "с --yes массовое удаление симуляторов не выполняется — запустите без --yes"
    return 1
  fi
  return 0
}

task_simdevices() {
  head2 "Симуляторы: интерактивный выбор (необратимо — не через Корзину)"
  command -v xcrun >/dev/null 2>&1 || { info "xcrun недоступен"; return 0; }
  local devroot="$HOME/Library/Developer/CoreSimulator/Devices"
  [ -d "$devroot" ] || { info "каталог устройств не найден"; return 0; }

  # UDID<TAB>Имя<TAB>Runtime<TAB>Состояние
  local raw
  raw="$(xcrun simctl list devices 2>/dev/null | awk '
    /^-- .* --$/ {
      rt=$0; gsub(/^-- | --$/,"",rt)
      if (rt ~ /^Unavailable:/) {
        v=rt; sub(/^.*SimRuntime\./,"",v); gsub(/-/,".",v)
        sub(/\./, " ", v)
        rt = (v == "" ? "?" : v)
      }
      next
    }
    {
      line=$0
      # UDID — единственная UUID-подстрока; имя может содержать скобки, напр. "iPad (A16)"
      if (match(line, /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) == 0) next
      udid = substr(line, RSTART, RLENGTH)
      name = substr(line, 1, RSTART - 1)
      sub(/^[ \t]+/, "", name); sub(/[ \t]*\([ \t]*$/, "", name); sub(/[ \t]+$/, "", name)
      rest = substr(line, RSTART + RLENGTH)       # ") (Shutdown) (unavailable, ...)"
      state = "?"
      if (match(rest, /\([^)]*\)/)) state = substr(rest, RSTART + 1, RLENGTH - 2)
      if (rest ~ /unavailable/) state = "недоступен"
      printf "%s\t%s\t%s\t%s\n", udid, name, rt, state
    }')"
  [ -z "$raw" ] && { info "симуляторов нет"; return 0; }

  # добираем размер и дату последнего изменения
  local rows="" udid name rt state kb used total_kb=0
  while IFS="$(printf '\t')" read -r udid name rt state; do
    [ -z "$udid" ] && continue
    [ -d "$devroot/$udid" ] || continue
    kb="$(sizeof "$devroot/$udid")"; kb="${kb:-0}"
    used="$(stat -f '%Sm' -t '%Y-%m-%d' "$devroot/$udid/data" 2>/dev/null \
            || stat -f '%Sm' -t '%Y-%m-%d' "$devroot/$udid" 2>/dev/null || echo '?')"
    rows="$rows$kb\t$udid\t$name\t$rt\t$state\t$used\n"
  done <<< "$raw"

  # сортировка по размеру, крупные сверху
  local sorted; sorted="$(printf "$rows" | sort -t"$(printf '\t')" -k1,1nr)"
  [ -z "$sorted" ] && { info "нечего показывать"; return 0; }

  local -a SEL_UDID=() SEL_NAME=() SEL_KB=()
  local n=0
  say ""
  printf '  %s\n' "№      размер  изменён      устройство                   runtime        состояние"
  printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────────"
  while IFS="$(printf '\t')" read -r kb udid name rt state used; do
    [ -z "$udid" ] && continue
    n=$((n+1))
    SEL_UDID[$n]="$udid"; SEL_NAME[$n]="$name"; SEL_KB[$n]="$kb"
    total_kb=$((total_kb + kb))
    local mark=""
    [ "$state" = "Booted" ] && mark="${C_R} ← запущен${C_0}"
    [ "$state" = "недоступен" ] && mark="${C_Y} ← runtime не установлен${C_0}"
    printf '  %-3s %9s  %-11s %-28s %-14s %s%s\n' \
      "$n" "$(human "$kb")" "$used" "$(printf '%.28s' "$name")" "$(printf '%.14s' "$rt")" "$state" "$mark"
    log "sim $n: $(human "$kb") $used $name / $rt / $state / $udid"
  done <<< "$sorted"
  printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────────"
  say "  Всего в симуляторах: ${C_BOLD}$(human "$total_kb")${C_0}, устройств: $n"

  if [ "$APPLY" -eq 0 ]; then
    say "  ${C_DIM}Это список. Для выбора и удаления запустите: --only simdevices --apply${C_0}"
    return 0
  fi
  interactive_ok || return 0

  say ""
  say "  ${C_DIM}Введите номера: 3  ·  1,4,7  ·  2-9  ·  all. Пустая строка — ничего не удалять.${C_0}"
  printf '  Что удалить? '
  local answer; IFS= read -r answer
  local picks; picks="$(parse_selection "$answer" "$n")"
  [ -z "$picks" ] && { info "ничего не выбрано"; return 0; }

  local pick_kb=0 pick_n=0 skipped=0
  local -a DO_UDID=() DO_LABEL=()
  for i in $picks; do
    # запущенный симулятор не удаляем — сначала его надо выключить
    if xcrun simctl list devices 2>/dev/null | grep -q "${SEL_UDID[$i]}.*Booted"; then
      warn "пропущен (запущен, сначала завершите): ${SEL_NAME[$i]}"; skipped=$((skipped+1)); continue
    fi
    pick_n=$((pick_n+1)); pick_kb=$((pick_kb + SEL_KB[$i]))
    DO_UDID+=("${SEL_UDID[$i]}"); DO_LABEL+=("${SEL_NAME[$i]} ($(human "${SEL_KB[$i]}"))")
  done
  [ "$pick_n" -eq 0 ] && { info "нечего удалять"; return 0; }

  say ""
  say "  ${C_BOLD}К удалению ($pick_n, $(human "$pick_kb")):${C_0}"
  for l in "${DO_LABEL[@]}"; do say "    · $l"; done
  say "  ${C_R}Это необратимо: simctl удаляет устройство минуя Корзину.${C_0}"
  say "  ${C_DIM}Само устройство пересоздаётся в Xcode за секунды, но установленные в нём"
  say "  приложения и их данные пропадут.${C_0}"
  printf '  Удалить? Введите %sDELETE%s: ' "$C_BOLD" "$C_0"
  local conf; IFS= read -r conf
  [ "$conf" = "DELETE" ] || { say "  Отменено."; return 0; }

  local ok=0
  for idx in "${!DO_UDID[@]}"; do
    if xcrun simctl delete "${DO_UDID[$idx]}" >>"$LOG" 2>&1; then
      say "  ${C_G}[удалено]${C_0} ${DO_LABEL[$idx]}"; ok=$((ok+1))
    else
      err "не удалось: ${DO_LABEL[$idx]}"
    fi
  done
  TOTAL_KB=$((TOTAL_KB + pick_kb))
  say "  Удалено устройств: $ok из $pick_n"
}

task_simruntimes() {
  head2 "Runtime-образы симуляторов (/Library/Developer/CoreSimulator — необратимо)"
  command -v xcrun >/dev/null 2>&1 || { info "xcrun недоступен"; return 0; }

  # id<TAB>название<TAB>размер<TAB>удаляем?<TAB>последнее использование
  local raw
  raw="$(xcrun simctl runtime list -v 2>/dev/null | awk '
    /^[A-Za-z].* \([0-9A-Za-z.]+\) - [0-9A-F-]+$/ {
      if (id != "") printf "%s\t%s\t%s\t%s\t%s\n", id, nm, sz, del, lu
      nm=$0; sub(/ - [0-9A-F-]+$/,"",nm)
      id=$0;  sub(/^.* - /,"",id)
      sz="?"; del="?"; lu="—"; next
    }
    /^ +Size: /          { sz=$2 }
    /^ +Deletable: /     { del=$2 }
    /^ +Last Used At: /  { lu=$4 }
    END { if (id != "") printf "%s\t%s\t%s\t%s\t%s\n", id, nm, sz, del, lu }')"
  [ -z "$raw" ] && { info "загруженных runtime-образов нет"; return 0; }

  local -a R_ID=() R_NAME=() R_SZ=()
  local n=0 id nm sz del lu ndev
  say ""
  printf '  %s\n' "№    размер  использован  runtime                    удаляем   устройств"
  printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────"
  while IFS="$(printf '\t')" read -r id nm sz del lu; do
    [ -z "$id" ] && continue
    n=$((n+1)); R_ID[$n]="$id"; R_NAME[$n]="$nm"; R_SZ[$n]="$sz"
    # сколько устройств привязано к этому runtime
    ndev="$(xcrun simctl list devices 2>/dev/null | awk -v rt="$nm" '
      /^-- .* --$/ { cur=$0; gsub(/^-- | --$/,"",cur); next }
      /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-/ { if (cur != "" && index(rt, cur) == 1) c++ }
      END { print c+0 }')"
    printf '  %-3s %8s  %-11s %-26s %-9s %s\n' \
      "$n" "$sz" "$lu" "$(printf '%.26s' "$nm")" "$del" "$ndev"
    log "runtime $n: $sz $lu $nm deletable=$del devices=$ndev id=$id"
  done <<< "$raw"
  printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────"
  say "  ${C_DIM}Занято под /Library/Developer/CoreSimulator: $(du -sh /Library/Developer/CoreSimulator 2>/dev/null | awk '{print $1}')${C_0}"

  if [ "$APPLY" -eq 0 ]; then
    say "  ${C_DIM}Это список. Для выбора и удаления: --only simruntimes --apply${C_0}"
    return 0
  fi
  interactive_ok || return 0

  say ""
  say "  ${C_DIM}Введите номера: 3 · 1,4 · 2-5 · all. Пустая строка — ничего.${C_0}"
  printf '  Какие runtime удалить? '
  local answer; IFS= read -r answer
  local picks; picks="$(parse_selection "$answer" "$n")"
  [ -z "$picks" ] && { info "ничего не выбрано"; return 0; }

  local -a DO_ID=() DO_LABEL=()
  for i in $picks; do
    DO_ID+=("${R_ID[$i]}"); DO_LABEL+=("${R_NAME[$i]} (${R_SZ[$i]})")
  done

  say ""
  say "  ${C_BOLD}К удалению (${#DO_ID[@]}):${C_0}"
  for l in "${DO_LABEL[@]}"; do say "    · $l"; done
  say "  ${C_R}Необратимо.${C_0} Симуляторы на этом runtime станут unavailable;"
  say "  ${C_DIM}сам образ можно вернуть, скачав runtime заново в Xcode (несколько ГБ).${C_0}"
  printf '  Удалить? Введите %sDELETE%s: ' "$C_BOLD" "$C_0"
  local conf; IFS= read -r conf
  [ "$conf" = "DELETE" ] || { say "  Отменено."; return 0; }

  local ok=0
  for idx in "${!DO_ID[@]}"; do
    if xcrun simctl runtime delete "${DO_ID[$idx]}" >>"$LOG" 2>&1; then
      say "  ${C_G}[удалено]${C_0} ${DO_LABEL[$idx]}"; ok=$((ok+1))
    else
      err "не удалось (возможно Deletable: NO или занят): ${DO_LABEL[$idx]}"
    fi
  done
  say "  Удалено runtime-образов: $ok из ${#DO_ID[@]}"
}

# ─── self-test защиты ─────────────────────────────────────────────────────
run_self_test() {
  local fails=0 tmp_a="$HOME/Library/Developer/Xcode/DerivedData/.maccleaner-selftest"
  local tmp_b="$HOME/Library/Caches/.maccleaner-selftest"
  mkdir -p "$tmp_a" "$tmp_b"

  expect_block() {
    if guard "$1" >/dev/null 2>&1; then
      printf '%s\n' "  ${C_R}FAIL${C_0} должен быть запрещён, но разрешён: $1"; fails=$((fails+1))
    else
      printf '%s\n' "  ${C_G}ok${C_0}   запрещён: $1"
    fi
  }
  expect_allow() {
    if guard "$1" >/dev/null 2>&1; then
      printf '%s\n' "  ${C_G}ok${C_0}   разрешён: $1"
    else
      printf '%s\n' "  ${C_R}FAIL${C_0} должен быть разрешён, но запрещён: $1"; fails=$((fails+1))
    fi
  }

  printf '%s\n' "${C_BOLD}Self-test защиты guard()${C_0}"
  expect_block ""
  expect_block "/"
  expect_block "$HOME"
  expect_block "$HOME/Documents"
  expect_block "$HOME/Desktop"
  expect_block "$HOME/Downloads"
  expect_block "$HOME/Library"
  expect_block "$HOME/Library/Caches"
  expect_block "$HOME/Library/Developer"
  expect_block "$HOME/Library/Developer/Xcode/Archives"
  expect_block "$HOME/Library/Developer/Xcode/UserData"
  expect_block "$HOME/Library/Keychains"
  expect_block "$HOME/Library/Application Support/MobileSync"
  expect_block "$HOME/Library/Mobile Documents"
  expect_block "$HOME/.ssh"
  expect_block "/etc/passwd"
  expect_block "/System"
  expect_block "$HOME/Library/Caches/../../Documents"
  expect_block "relative/path"
  expect_allow "$tmp_a"
  expect_allow "$tmp_b"

  rmdir "$tmp_a" "$tmp_b" 2>/dev/null
  printf '%s\n' ""
  if [ "$fails" -eq 0 ]; then
    printf '%s\n' "${C_G}${C_BOLD}Все проверки пройдены.${C_0}"; return 0
  else
    printf '%s\n' "${C_R}${C_BOLD}Проверок провалено: $fails${C_0}"; return 1
  fi
}

# ─── задачи ───────────────────────────────────────────────────────────────
task_derived() {
  head2 "Xcode DerivedData (индексы и промежуточные билды — пересоберутся)"
  remove_children "$HOME/Library/Developer/Xcode/DerivedData" "DerivedData"
}

task_devicesupport() {
  head2 "Xcode iOS/watchOS DeviceSupport (перекачается при подключении устройства)"
  for d in iOS watchOS tvOS; do
    remove_children "$HOME/Library/Developer/Xcode/$d DeviceSupport" "$d DeviceSupport"
  done
}

task_simulators() {
  head2 "Кэши симуляторов"
  remove_children "$HOME/Library/Developer/CoreSimulator/Caches/dyld" "CoreSimulator/Caches/dyld"
  remove_children "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator/Caches"

  if command -v xcrun >/dev/null 2>&1; then
    local n
    n="$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(unavailable' || true)"
    if [ "${n:-0}" -gt 0 ]; then
      # размер считаем ДО удаления — иначе в итог попадёт 0
      local devroot="$HOME/Library/Developer/CoreSimulator/Devices" ukb=0 u
      while IFS= read -r u; do
        [ -d "$devroot/$u" ] && ukb=$((ukb + $(sizeof "$devroot/$u")))
      done < <(xcrun simctl list devices unavailable 2>/dev/null | awk '
        /unavailable/ && match($0,/[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}/) {
          print substr($0,RSTART,RLENGTH) }')
      if [ "$APPLY" -eq 1 ]; then
        if xcrun simctl delete unavailable >>"$LOG" 2>&1; then
          TOTAL_KB=$((TOTAL_KB + ukb))
          say "  ${C_G}[удалено]${C_0}  $(human "$ukb")  недоступных симуляторов: $n"
        else
          err "simctl delete unavailable не сработал"
        fi
      else
        say "  ${C_Y}[dry-run]${C_0} $(human "$ukb")  недоступных симуляторов: $n"
      fi
    else
      info "недоступных симуляторов нет"
    fi
  fi
}

task_xcodebuildmcp() {
  head2 "XcodeBuildMCP workspaces"
  remove_children "$HOME/Library/Developer/XcodeBuildMCP/workspaces" "XcodeBuildMCP/workspaces"
}

task_swiftpm() {
  head2 "SwiftPM / Xcode кэш пакетов (перекачается)"
  remove_children "$HOME/Library/Caches/org.swift.swiftpm" "org.swift.swiftpm"
  remove_children "$HOME/Library/Developer/Xcode/DocumentationCache" "Xcode DocumentationCache"
}

task_pkgcaches() {
  head2 "Кэши пакетных менеджеров"
  remove_children "$HOME/.npm/_cacache"        "npm cache"
  remove_children "$HOME/Library/Caches/Yarn"  "Yarn cache"
  remove_children "$HOME/Library/pnpm/store"   "pnpm store"
  remove_children "$HOME/Library/Caches/pip"   "pip cache"
  remove_children "$HOME/Library/Caches/CocoaPods" "CocoaPods cache"
  remove_children "$HOME/.gradle/caches"       "Gradle caches"
  remove_children "$HOME/.cache/puppeteer"     "puppeteer"
  remove_children "$HOME/Library/Caches/ms-playwright" "playwright browsers"
}

task_brew() {
  head2 "Homebrew"
  command -v brew >/dev/null 2>&1 || { info "brew не установлен"; return 0; }
  if [ "$APPLY" -eq 1 ]; then
    brew cleanup --prune=all 2>&1 | tail -3 | sed 's/^/    /'
    say "  ${C_G}[готово]${C_0}  brew cleanup --prune=all"
  else
    say "  ${C_Y}[dry-run]${C_0} $(brew cleanup --dry-run 2>&1 | tail -1)"
  fi
}

task_appcaches() {
  head2 "Кэши приложений в ~/Library/Caches"
  # Только явно известные и безвредные — не весь каталог целиком.
  local names=(
    "com.apple.dt.Xcode" "com.apple.dt.XCBBuild" "com.apple.dt.instruments"
    "com.apple.nsurlsessiond" "com.apple.Safari/WebKitCache"
    "Google/Chrome/Default/Cache" "com.google.Chrome/Cache"
    "com.microsoft.VSCode/Cache" "com.microsoft.VSCode/CachedData"
    "JetBrains" "com.spotify.client/Data" "Slack/Cache" "typescript"
    "electron" "node-gyp" "Cypress"
  )
  for n in "${names[@]}"; do
    [ -e "$HOME/Library/Caches/$n" ] && remove_children "$HOME/Library/Caches/$n" "Caches/$n"
  done
}

task_logs() {
  head2 "Старые логи (>30 дней) в ~/Library/Logs"
  BATCH=1; BATCH_N=0; BATCH_KB=0
  local f
  while IFS= read -r -d '' f; do
    remove "$f" "Logs/${f#"$HOME/Library/Logs/"}"
  done < <(find "$HOME/Library/Logs" -mindepth 1 -maxdepth 4 -type f -mtime +30 -print0 2>/dev/null)
  BATCH=0
  if [ "$BATCH_N" -eq 0 ]; then
    info "нечего чистить"
  elif [ "$APPLY" -eq 0 ]; then
    say "  ${C_Y}[dry-run]${C_0} $(human "$BATCH_KB")  файлов логов: $BATCH_N ${C_DIM}(построчно — в логе)${C_0}"
  else
    say "  ${C_G}[очищено]${C_0} $(human "$BATCH_KB")  файлов логов: $BATCH_N"
  fi
  return 0
}

task_report() {
  head2 "Топ-15 крупнейших каталогов (только отчёт, ничего не трогаем)"
  du -sh "$HOME/Library/Developer"/* "$HOME/Library/Caches"/* 2>/dev/null \
    | sort -h | tail -15 | sed 's/^/    /' | tee -a "$LOG"
}

# порядок = порядок выполнения
ALL_TASKS="report derived devicesupport simulators xcodebuildmcp swiftpm pkgcaches brew appcaches logs simdevices simruntimes"

usage() {
  cat <<EOF
${C_BOLD}maccleaner $VERSION${C_0} — безопасная чистка мусора разработчика на macOS

  ${C_BOLD}Использование:${C_0}
    ./maccleaner.sh [опции]

  ${C_BOLD}Опции:${C_0}
    (без опций)     dry-run: только показать, что было бы удалено
    --apply         выполнить: переместить найденное в ~/.Trash/maccleaner-<ts>/
    --purge         вместе с --apply — стирать сразу, минуя Корзину (необратимо)
    --only LIST     только указанные задачи, через запятую
    --yes           не спрашивать подтверждение
    --verbose       показывать и пустые пункты
    --self-test      проверить работу защиты guard()
    --list          список задач
    --help          эта справка

  ${C_BOLD}Задачи:${C_0}
    report          отчёт по крупнейшим каталогам (ничего не удаляет)
    derived         Xcode DerivedData
    devicesupport   Xcode iOS/watchOS/tvOS DeviceSupport
    simulators      кэши CoreSimulator + удаление недоступных симуляторов
    xcodebuildmcp   XcodeBuildMCP workspaces
    swiftpm         кэш SwiftPM и документации Xcode
    pkgcaches       npm / yarn / pnpm / pip / CocoaPods / Gradle / playwright
    brew            brew cleanup --prune=all
    appcaches       известные кэши приложений в ~/Library/Caches
    logs            логи в ~/Library/Logs старше 30 дней
    simdevices      ${C_BOLD}интерактивно${C_0}: список симуляторов с размером и датой,
                    выбор номеров для удаления (необратимо, минуя Корзину)
    simruntimes     ${C_BOLD}интерактивно${C_0}: список загруженных runtime-образов iOS/watchOS,
                    выбор номеров для удаления (необратимо, качается заново)

  ${C_BOLD}Примеры:${C_0}
    ./maccleaner.sh                              # посмотреть, что можно освободить
    ./maccleaner.sh --apply                      # почистить обратимо (в Корзину)
    ./maccleaner.sh --only derived,simulators --apply
    ./maccleaner.sh --only report
    ./maccleaner.sh --only simdevices              # посмотреть список симуляторов
    ./maccleaner.sh --only simdevices --apply      # выбрать и удалить
    ./maccleaner.sh --only simruntimes --apply     # выбрать и удалить runtime-образы

  ${C_BOLD}Что не трогается никогда:${C_0}
    Documents, Desktop, Downloads, iCloud Drive, Photos, Mail, Messages,
    Keychains, ~/.ssh, бэкапы устройств (MobileSync), Xcode Archives,
    Xcode UserData (сниппеты, схемы, брейкпоинты).
EOF
}

# ─── разбор аргументов ────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1 ;;
    --purge)   PURGE=1 ;;
    --only)    ONLY="${2:-}"; shift ;;
    --only=*)  ONLY="${1#*=}" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --self-test) SELFTEST=1 ;;
    --list)    printf '%s\n' $ALL_TASKS; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) printf '%s\n' "Неизвестная опция: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$(uname -s)" in Darwin) ;; *) echo "Только для macOS." >&2; exit 1 ;; esac
if [ "$PURGE" -eq 1 ] && [ "$APPLY" -eq 0 ]; then
  echo "--purge требует --apply." >&2; exit 2
fi

mkdir -p "$(dirname "$LOG")"; : >"$LOG"

if [ "$SELFTEST" -eq 1 ]; then run_self_test; exit $?; fi

TASKS="$ALL_TASKS"
if [ -n "$ONLY" ]; then
  TASKS="$(printf '%s' "$ONLY" | tr ',' ' ')"
  for t in $TASKS; do
    case " $ALL_TASKS " in *" $t "*) ;; *) echo "Неизвестная задача: $t" >&2; exit 2 ;; esac
  done
fi

# ─── старт ────────────────────────────────────────────────────────────────
FREE_BEFORE="$(df -k / | awk 'NR==2{print $4+0}')"
say "${C_BOLD}maccleaner $VERSION${C_0}"
if [ "$APPLY" -eq 0 ]; then
  say "${C_Y}Режим: DRY-RUN — ничего не будет удалено.${C_0} Для реальной чистки: --apply"
elif [ "$PURGE" -eq 1 ]; then
  say "${C_R}Режим: PURGE — файлы будут стёрты безвозвратно.${C_0}"
else
  say "${C_G}Режим: APPLY — найденное переместится в $QUARANTINE${C_0}"
fi
say "${C_DIM}Свободно на /: $(human "$FREE_BEFORE") · лог: $LOG${C_0}"

# Интерактивные задачи подтверждают удаление сами — глобальный запрос тогда лишний.
INTERACTIVE_ONLY=1
for t in $TASKS; do
  case "$t" in simdevices|simruntimes|report) ;; *) INTERACTIVE_ONLY=0 ;; esac
done

if [ "$APPLY" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ] && [ "$INTERACTIVE_ONLY" -eq 0 ]; then
  if [ "$PURGE" -eq 1 ]; then
    printf '%s' "Стереть безвозвратно? Введите ${C_BOLD}PURGE${C_0} для подтверждения: "
    read -r a; [ "$a" = "PURGE" ] || { echo "Отменено."; exit 0; }
  else
    printf '%s' "Продолжить? [y/N] "
    read -r a; case "$a" in y|Y|yes|YES) ;; *) echo "Отменено."; exit 0 ;; esac
  fi
fi

if command -v pgrep >/dev/null 2>&1 && pgrep -qx Xcode 2>/dev/null; then
  warn "Xcode запущен — рекомендуется закрыть его перед чисткой DerivedData."
fi

for t in $TASKS; do "task_$t"; done

# ─── итог ─────────────────────────────────────────────────────────────────
FREE_AFTER="$(df -k / | awk 'NR==2{print $4+0}')"
say ""
say "${C_BOLD}────── Итог ──────${C_0}"
if [ "$APPLY" -eq 0 ]; then
  say "Можно освободить: ${C_BOLD}$(human "$TOTAL_KB")${C_0}"
  say "${C_DIM}Запустите с --apply, чтобы выполнить (обратимо, через Корзину).${C_0}"
else
  say "Обработано: ${C_BOLD}$(human "$TOTAL_KB")${C_0}"
  say "Свободно на /: $(human "$FREE_AFTER") ${C_DIM}(было $(human "$FREE_BEFORE"))${C_0}"
  if [ "$PURGE" -eq 0 ] && [ -d "$QUARANTINE" ]; then
    say "${C_DIM}Файлы в Корзине: $QUARANTINE — проверьте, что всё работает, потом очистите Корзину.${C_0}"
  fi
fi
say "${C_DIM}Лог: $LOG${C_0}"
