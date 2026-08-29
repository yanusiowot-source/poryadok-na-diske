#!/usr/bin/env bash
# Порядок на диске. Вечерняя работа на этом компьютере.
# Ничего не удаляет. В сеть не отправляет. Трогает файлы только после: bash poryadok.sh soglasen
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RABOTA="$ROOT/rabota"
PLAN="$RABOTA/plan.txt"
OTCHET="$RABOTA/otchet.txt"
LIMIT=8000
NOW="$(date +%s)"
OLD_AFTER=$((90 * 24 * 60 * 60))

mkdir -p "$RABOTA"

plural() {
  local n="$1" one="$2" few="$3" many="$4"
  local abs=$(( n < 0 ? -n : n ))
  local mod100=$(( abs % 100 ))
  local last=$(( abs % 10 ))
  if (( mod100 > 10 && mod100 < 20 )); then
    printf '%s' "$many"
  elif (( last == 1 )); then
    printf '%s' "$one"
  elif (( last >= 2 && last <= 4 )); then
    printf '%s' "$few"
  else
    printf '%s' "$many"
  fi
}

format_size() {
  awk -v b="$1" 'BEGIN {
    if (b < 1024) { printf "%d байт", b; exit }
    kb = b / 1024
    if (kb < 1024) { printf "%s Кб", fmt(kb); exit }
    mb = kb / 1024
    if (mb < 1024) { printf "%s Мб", fmt(mb); exit }
    printf "%s Гб", fmt(mb / 1024)
  }
  function fmt(n) {
    if (n >= 10) return sprintf("%d", n + 0.5)
    s = sprintf("%.1f", n)
    gsub(/\./, ",", s)
    return s
  }'
}

season_of() {
  local ts="$1"
  local month year this_year
  month="$(date -d "@$ts" +%m 2>/dev/null || date -r "$ts" +%m)"
  year="$(date -d "@$ts" +%Y 2>/dev/null || date -r "$ts" +%Y)"
  this_year="$(date +%Y)"
  month="${month#0}"
  local s
  if (( month == 12 || month <= 2 )); then s="зимы"
  elif (( month <= 5 )); then s="весны"
  elif (( month <= 8 )); then s="лета"
  else s="осени"
  fi
  if [[ "$year" != "$this_year" ]]; then
    printf '%s %s' "$s" "$year"
  else
    printf '%s' "$s"
  fi
}

first_dir() {
  local p
  for p in "$@"; do
    [[ -n "$p" && -d "$p" ]] || continue
    printf '%s\n' "$p"
    return 0
  done
  return 1
}

downloads_dir() {
  first_dir \
    "${PORYADOK_DOWNLOADS:-}" \
    "$HOME/Downloads" \
    "$HOME/Загрузки"
}

desktop_dir() {
  first_dir \
    "${PORYADOK_DESKTOP:-}" \
    "$HOME/Desktop" \
    "$HOME/Рабочий стол"
}

is_private_dir() {
  local base
  base="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    *почт*|*mail*|*outlook*|*thunderbird*|*picture*|*фото*|*photo*|*dcim*|*icloud*)
      return 0
      ;;
  esac
  return 1
}

ext_of() {
  local name="${1##*/}"
  if [[ "$name" == *.* && "$name" != .* ]]; then
    printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]'
  fi
}

kind_of() {
  local e
  e="$(ext_of "$1")"
  case "$e" in
    exe|msi|msix|dmg|pkg|deb|rpm|apk) printf 'installer' ;;
    jpg|jpeg|png|gif|webp|bmp|svg|heic|tif|tiff) printf 'image' ;;
    pdf|doc|docx|xls|xlsx|ppt|pptx|txt|rtf|odt) printf 'document' ;;
    zip|rar|7z|tar|gz|iso) printf 'archive' ;;
    mp4|mkv|avi|mov|wmv|webm) printf 'video' ;;
    mp3|wav|flac|aac|ogg|m4a) printf 'audio' ;;
    pst|ost|eml|msg|mbox) printf 'mail' ;;
    lnk|url) printf 'shortcut' ;;
    bat|cmd|ps1) printf 'tool' ;;
    *) printf 'other' ;;
  esac
}

kind_folder() {
  case "$1" in
    installer) printf 'Установщики' ;;
    image) printf 'Картинки' ;;
    document) printf 'Документы' ;;
    archive) printf 'Архивы' ;;
    video) printf 'Видео' ;;
    audio) printf 'Музыка' ;;
  esac
}

pretty_name() {
  local n="${1##*/}"
  n="${n%.lnk}"; n="${n%.LNK}"
  n="${n%.url}"; n="${n%.URL}"
  n="${n%.bat}"; n="${n%.BAT}"
  n="${n%.cmd}"; n="${n%.CMD}"
  n="${n%.ps1}"
  printf '%s' "$n"
}

is_noise_name() {
  local n="${1##*/}"
  case "$n" in
    desktop.ini|Desktop.ini|Thumbs.db|thumbs.db|.DS_Store) return 0 ;;
  esac
  return 1
}

join_names() {
  local -a items=("$@")
  local i n="${#items[@]}"
  if (( n == 0 )); then return 0; fi
  if (( n == 1 )); then printf '%s' "${items[0]}"; return 0; fi
  for (( i = 0; i < n; i++ )); do
    if (( i == 0 )); then printf '%s' "${items[i]}"
    elif (( i == n - 1 )); then printf ' и %s' "${items[i]}"
    else printf ', %s' "${items[i]}"
    fi
  done
}

tidy_folder_name() {
  case "$1" in
    Установщики|Картинки|Документы|Архивы|Видео|Музыка) return 0 ;;
  esac
  return 1
}

list_files() {
  local dir="$1"
  find "$dir" \
    -type f \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    ! -path '*/$RECYCLE.BIN/*' \
    2>/dev/null | head -n "$LIMIT" || true
}

file_size() { stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"; }
file_mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"; }

refuse_or_continue() {
  local dir="$1"
  if is_private_dir "$dir"; then
    printf '%s\n' "«$(basename "$dir")» похоже на письма или семейные снимки. Вслепую не беру. Отказ без платы."
    return 1
  fi
  return 0
}

report_one() {
  local dir="$1"
  local title="$2"
  local file count=0 total=0 old=0 oldest="$NOW" installer=0 mail=0
  local -A seen=()
  local -a repeats=()
  local truncated=0

  local list="$RABOTA/.list.$$"
  list_files "$dir" > "$list"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    count=$((count + 1))
    if (( count >= LIMIT )); then truncated=1; fi
    local sz mt name key rel
    sz="$(file_size "$file")"
    mt="$(file_mtime "$file")"
    total=$((total + sz))
    name="${file##*/}"
    if (( NOW - mt > OLD_AFTER )); then
      old=$((old + 1))
      if (( mt < oldest )); then oldest="$mt"; fi
    fi
    rel="${file#"$dir"/}"
    if [[ "$(kind_of "$file")" == installer && "$rel" != */* ]]; then
      installer=$((installer + 1))
    fi
    if [[ "$(kind_of "$file")" == mail ]]; then mail=$((mail + 1)); fi
    key="${name}|${sz}"
    if [[ -n "${seen[$key]:-}" ]]; then
      repeats+=("$name")
    else
      seen[$key]=1
    fi
  done < "$list"
  rm -f "$list"

  if (( count >= 20 && mail * 100 / count >= 20 )); then
    printf '%s\n' "«${title}» — здесь много писем. Вслепую не беру. Отказ без платы."
    return 0
  fi

  printf '%s — %s %s. %s.\n' \
    "$title" "$count" "$(plural "$count" "файл" "файла" "файлов")" "$(format_size "$total")"

  if (( old > 0 )); then
    printf '%s %s с %s.\n' "$old" "$(plural "$old" "лежит" "лежат" "лежат")" "$(season_of "$oldest")"
  else
    printf '%s\n' "Давних почти нет."
  fi

  if ((${#repeats[@]} > 0)); then
    local uniq="" r shown=0 extra=0
    for r in "${repeats[@]}"; do
      case " $uniq " in
        *" $r "*) continue ;;
      esac
      uniq+=" $r"
      if (( shown < 2 )); then
        if (( shown == 0 )); then printf 'Повторы: «%s»' "$r"
        else printf ', «%s»' "$r"
        fi
        shown=$((shown + 1))
      else
        extra=$((extra + 1))
      fi
    done
    if (( extra > 0 )); then printf ' и ещё %s' "$extra"; fi
    printf '.\n'
  else
    printf '%s\n' "Повторов по имени и размеру нет."
  fi

  if (( installer > 0 )); then
    printf 'На виду %s %s.\n' "$installer" "$(plural "$installer" "установщик" "установщика" "установщиков")"
  fi
  if (( truncated )); then
    printf '%s\n' "Список неполный: папка очень большая. Этого довольно для картины."
  fi
  printf '\n'
}

cmd_otchet() {
  local dl ds
  dl="$(downloads_dir || true)"
  ds="$(desktop_dir || true)"
  if [[ -z "${dl:-}" && -z "${ds:-}" ]]; then
    printf '%s\n' "Не нашёл «Загрузки» и «Рабочий стол». Укажите папку: bash poryadok.sh otchet /путь/к/папке"
    exit 1
  fi

  {
    printf '%s\n\n' "Отчёт о диске. Только список. Без удаления."
    if [[ -n "${1:-}" && -d "$1" ]]; then
      refuse_or_continue "$1" || exit 0
      report_one "$1" "$(basename "$1")"
    else
      if [[ -n "${ds:-}" ]]; then
        refuse_or_continue "$ds" || true
        if ! is_private_dir "$ds"; then report_one "$ds" "Рабочий стол"; fi
      fi
      if [[ -n "${dl:-}" ]]; then
        refuse_or_continue "$dl" || true
        if ! is_private_dir "$dl"; then report_one "$dl" "Загрузки"; fi
      fi
    fi
    printf '%s\n' "Спешки нет. Файлы на месте."
  } > "$OTCHET"
  cat "$OTCHET"

  printf '\n%s\n' "Записано: $OTCHET"
}

top_level_files() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f 2>/dev/null | sort || true
}

cmd_plan() {
  local dl ds
  dl="$(downloads_dir || true)"
  ds="$(desktop_dir || true)"
  : > "$PLAN"
  {
    printf '%s\n' "KIND=tidy"
    printf '%s\n' "# План разбора. Файлы ещё на месте."
    printf '%s\n' "# Чтобы выполнить: bash poryadok.sh soglasen"
  } >> "$PLAN"

  local any=0

  plan_dir() {
    local dir="$1" title="$2"
    [[ -n "$dir" ]] || return 0
    if is_private_dir "$dir"; then
      printf '%s\n' "«${title}» не беру."
      return 0
    fi
    local file kind folder dest count=0 left=0 skip=0 bench=0
    printf '\n%s\n' "$title"
    printf 'ROOT=%s\n' "$dir" >> "$PLAN"
    local files="$RABOTA/.top.$$"
    top_level_files "$dir" > "$files"
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if is_noise_name "$file"; then
        continue
      fi
      kind="$(kind_of "$file")"
      if [[ "$kind" == mail ]]; then
        skip=$((skip + 1))
        continue
      fi
      if [[ "$kind" == shortcut || "$kind" == tool ]]; then
        bench=$((bench + 1))
        continue
      fi
      if [[ "$kind" == other ]]; then
        left=$((left + 1))
        continue
      fi
      folder="$(kind_folder "$kind")"
      dest="$folder/${file##*/}"
      printf 'mkdir\t%s\t%s\n' "$dir" "$folder" >> "$PLAN"
      printf 'mv\t%s\t%s\n' "$file" "$dir/$dest" >> "$PLAN"
      printf '  %s → %s\n' "${file##*/}" "$dest"
      count=$((count + 1))
      any=1
    done < "$files"
    rm -f "$files"
    if (( count == 0 )); then
      printf '%s\n' "Наверху нечего раскладывать."
    else
      printf '%s\n' "Это план. $count $(plural "$count" "файл" "файла" "файлов") ещё на месте."
    fi
    if (( left > 0 )); then
      printf 'Неясных оставляю: %s.\n' "$left"
    fi
    if (( bench > 0 )); then
      printf 'Верстак оставляю: %s.\n' "$bench"
    fi
    if (( skip > 0 )); then
      printf '%s\n' "Письма не трогаю."
    fi
  }

  if [[ -n "${1:-}" && -d "$1" ]]; then
    plan_dir "$1" "$(basename "$1")"
  else
    plan_dir "${ds:-}" "Рабочий стол"
    plan_dir "${dl:-}" "Загрузки"
  fi

  if (( any == 0 )); then
    rm -f "$PLAN"
    printf '\n%s\n' "Двигать нечего. Можно оставить как есть."
    return 0
  fi

  printf '\n%s\n' "План записан: $PLAN"
  printf '%s\n' "Ночь на размышление — это нормально."
  printf '%s\n' "Когда будете готовы: bash poryadok.sh soglasen"
}

cmd_kopiya() {
  local src="${1:-}"
  local dest="${2:-}"
  if [[ -z "$src" ]]; then
    src="$(downloads_dir || true)"
  fi
  if [[ -z "$src" || ! -d "$src" ]]; then
    printf '%s\n' "Укажите папку, которую копировать: bash poryadok.sh kopiya /путь/к/папке"
    exit 1
  fi
  if is_private_dir "$src"; then
    printf '%s\n' "Это похоже на письма или семейные снимки. Вслепую не беру. Отказ без платы."
    exit 0
  fi
  if [[ -z "$dest" ]]; then
    dest="$HOME/poryadok-kopiya/$(date +%Y-%m-%d)/$(basename "$src")"
  fi

  {
    printf '%s\n' "KIND=copy"
    printf '%s\n' "# Запасная копия. Источник не трогаем."
    printf '%s\n' "FROM=$src"
    printf '%s\n' "TO=$dest"
    printf 'cp\t%s\t%s\n' "$src" "$dest"
  } > "$PLAN"

  printf '%s\n' "Откуда: $src"
  printf '%s\n' "Куда:   $dest"
  printf '%s\n' "В источнике файлы останутся."
  printf '\n%s\n' "Спешки нет. Чтобы скопировать: bash poryadok.sh soglasen"
}

cmd_soglasen() {
  if [[ ! -f "$PLAN" ]]; then
    printf '%s\n' "Плана нет. Сначала: bash poryadok.sh plan  — или  bash poryadok.sh kopiya"
    exit 1
  fi

  local kind="" line cmd from to dir folder done=0 skip=0
  kind="$(awk -F= '/^KIND=/{print $2; exit}' "$PLAN")"

  printf '%s\n' "Делаю по плану. Удаления нет."

  while IFS=$'\t' read -r cmd from to; do
    [[ "$cmd" == mkdir || "$cmd" == mv || "$cmd" == cp ]] || continue
    case "$cmd" in
      mkdir)
        dir="$from"
        folder="$to"
        mkdir -p "$dir/$folder"
        ;;
      mv)
        if [[ ! -e "$from" ]]; then
          skip=$((skip + 1))
          continue
        fi
        if [[ -e "$to" ]]; then
          printf 'уже есть, не трогаю: %s\n' "$(basename "$from")"
          skip=$((skip + 1))
          continue
        fi
        mkdir -p "$(dirname "$to")"
        if mv "$from" "$to"; then
          done=$((done + 1))
        else
          skip=$((skip + 1))
        fi
        ;;
      cp)
        mkdir -p "$to"
        if cp -R "$from/." "$to/"; then
          printf '%s\n' "Скопировано в $to"
          printf '%s\n' "Откуда: $from. Там всё как было."
          mv "$PLAN" "$RABOTA/plan.sdelano.txt"
          return 0
        else
          printf '%s\n' "Копия оборвалась. Источник не трогал."
          exit 1
        fi
        ;;
    esac
  done < "$PLAN"

  printf 'Готово. Перенёс %s, как в плане.\n' "$done"
  if (( skip > 0 )); then
    printf 'Не тронул: %s.\n' "$skip"
  fi
  printf '%s\n' "Удаления не было."
  mv "$PLAN" "$RABOTA/plan.sdelano.txt"
}

cmd_idilliya() {
  local ds dl out="$RABOTA/idilliya.txt"
  ds="$(desktop_dir || true)"
  dl="$(downloads_dir || true)"

  {
    printf '%s\n\n' "Вечер."
    printf '%s\n\n' "С чувством, с толком, с расстановкой."

    if [[ -n "${ds:-}" ]]; then
      idyll_desktop "$ds"
      printf '\n'
    fi
    if [[ -n "${dl:-}" ]]; then
      idyll_downloads "$dl"
      printf '\n'
    fi

    printf '%s\n\n' "Спешки нет. Файлы на месте."
    printf '%s\n' "Ночь на размышление — это нормально."
  } > "$out"
  cat "$out"
  printf '\n%s\n' "Записано: $out"
}

idyll_desktop() {
  local dir="$1"
  local file kind
  local -a shorts=() tools=() other=()
  local list="$RABOTA/.desk.$$"
  top_level_files "$dir" > "$list"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if is_noise_name "$file"; then continue; fi
    kind="$(kind_of "$file")"
    case "$kind" in
      shortcut) shorts+=("$(pretty_name "$file")") ;;
      tool) tools+=("$(pretty_name "$file")") ;;
      *) other+=("${file##*/}") ;;
    esac
  done < "$list"
  rm -f "$list"

  printf '%s\n\n' "Рабочий стол — верстак."
  if ((${#shorts[@]} > 0)); then
    printf 'Ярлыки: %s.\n\n' "$(join_names "${shorts[@]}")"
  fi
  if ((${#tools[@]} > 0)); then
    printf 'Инструменты: %s.\n\n' "$(join_names "${tools[@]}")"
  fi
  if ((${#other[@]} > 0)); then
    printf 'Ещё наверху: %s.\n\n' "$(join_names "${other[@]}")"
  fi
  if ((${#shorts[@]} == 0 && ${#tools[@]} == 0 && ${#other[@]} == 0)); then
    printf '%s\n\n' "Пусто и тихо."
  fi
  printf '%s\n' "Это не разбирать. Это ваше место работы."
}

idyll_downloads() {
  local dir="$1"
  local file rel kind top=0 nested=0 total=0
  local -a tidy_present=()
  local -A tidy_count=()
  local list="$RABOTA/.dl.$$"
  list_files "$dir" > "$list"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    total=$((total + $(file_size "$file")))
    rel="${file#"$dir"/}"
    if [[ "$rel" != */* ]]; then
      top=$((top + 1))
      continue
    fi
    nested=$((nested + 1))
    local folder="${rel%%/*}"
    if tidy_folder_name "$folder"; then
      tidy_count["$folder"]=$(( ${tidy_count[$folder]:-0} + 1 ))
    fi
  done < "$list"
  rm -f "$list"

  printf '%s\n\n' "Загрузки — $(format_size "$total")."
  if (( top > 0 )); then
    printf 'В корне %s %s россыпью.\n\n' "$top" "$(plural "$top" "файл" "файла" "файлов")"
  else
    printf '%s\n\n' "В корне пусто. Хорошо."
  fi

  local name
  for name in Установщики Архивы Документы Картинки Видео Музыка; do
    if (( ${tidy_count[$name]:-0} > 0 )); then
      printf 'В «%s» — %s.\n' "$name" "${tidy_count[$name]}"
    fi
  done
  if ((${#tidy_count[@]} > 0)); then
    printf '\n%s\n' "Это уже разобранное. Лежит на месте."
  fi
}

cmd_pomoshch() {
  cat << 'EOF'
Порядок на диске. На этом компьютере. В сеть ничего не уходит.

  bash poryadok.sh otchet     отчёт о «Загрузках» и «Рабочем столе»
  bash poryadok.sh idilliya   вечерняя картина. ничего не трогает
  bash poryadok.sh plan       план разбора. файлы ещё на месте
  bash poryadok.sh soglasen   выполнить план или копию
  bash poryadok.sh kopiya     запасная копия «Загрузок»
  bash poryadok.sh kopiya ПАПКА КУДА

Ничего не удаляет.
Трогает файлы только после soglasen.
EOF
}

main() {
  local cmd="${1:-otchet}"
  shift || true
  case "$cmd" in
    otchet|отчет|отчёт) cmd_otchet "$@" ;;
    idilliya|idyll|идиллия) cmd_idilliya "$@" ;;
    plan|план) cmd_plan "$@" ;;
    kopiya|копия) cmd_kopiya "$@" ;;
    soglasen|согласен) cmd_soglasen "$@" ;;
    pomoshch|help|-h|--help) cmd_pomoshch ;;
    *)
      printf '%s\n' "Не знаю команду «$cmd»."
      cmd_pomoshch
      exit 1
      ;;
  esac
}

main "$@"
