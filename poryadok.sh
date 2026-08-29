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
  printf '\n%s\n' "Ещё не копирую."
  printf '%s\n' "Ночь на размышление — это нормально."
  printf '%s\n' "Когда сами захотите, одна команда: bash poryadok.sh soglasen"
}

ask_consent() {
  if [[ ! -t 0 ]]; then
    printf '%s\n' "Согласие нужно вслух, не пачкой."
    printf '%s\n' "Запустите одну команду: bash poryadok.sh soglasen"
    printf '%s\n' "и напишите «согласен»."
    return 1
  fi
  printf '%s\n' "Файлы ещё на месте."
  printf '%s\n' "Напишите «согласен», если план ваш."
  printf '%s\n' "Или Enter — оставить как есть."
  local ans low
  read -r ans || true
  low="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  if [[ "$low" != "согласен" ]]; then
    printf '%s\n' "Оставляю как есть. Спешки нет."
    return 1
  fi
  return 0
}

cmd_soglasen() {
  if [[ ! -f "$PLAN" ]]; then
    printf '%s\n' "Плана нет. Сначала: bash poryadok.sh plan  — или  bash poryadok.sh kopiya"
    exit 1
  fi

  local kind="" cmd from to dir folder done=0 skip=0
  kind="$(awk -F= '/^KIND=/{print $2; exit}' "$PLAN")"

  if [[ "$kind" == copy ]]; then
    printf '%s\n' "План: запасная копия. Источник не трогаю."
  else
    printf '%s\n' "План: разложить по папкам. Удаления нет."
  fi
  ask_consent || return 0

  printf '%s\n' "Делаю по плану."

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

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

collect_idyll_js() {
  local f="$RABOTA/idilliya.txt"
  if [[ ! -f "$f" ]]; then
    printf 'const IDYLL = "";\n'
    return 0
  fi
  printf 'const IDYLL = "'
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/$/\\n/' "$f" | tr -d '\r' | tr -d '\n'
  printf '";\n'
}

sky_kind_constellation() {
  local file="$1" folder="$2"
  local kind
  kind="$(kind_of "$file")"
  case "$kind" in
    shortcut|tool) printf 'Верстак' ;;
    installer) printf 'Установщики' ;;
    archive) printf 'Архивы' ;;
    document) printf 'Документы' ;;
    image) printf 'Картинки' ;;
    video) printf 'Видео' ;;
    audio) printf 'Музыка' ;;
    *)
      if tidy_folder_name "$folder"; then printf '%s' "$folder"
      else printf 'Россыпь'
      fi
      ;;
  esac
}

collect_sky_js() {
  local ds dl file rel folder name kind sz cons list
  ds="$(desktop_dir || true)"
  dl="$(downloads_dir || true)"
  printf 'const SKY = [\n'
  if [[ -n "${ds:-}" ]]; then
    list="$RABOTA/.skydesk.$$"
    top_level_files "$ds" > "$list"
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if is_noise_name "$file"; then continue; fi
      name="$(pretty_name "$file")"
      kind="$(kind_of "$file")"
      sz="$(file_size "$file")"
      cons="$(sky_kind_constellation "$file" "")"
      printf '  {name:"%s",kind:"%s",size:%s,constellation:"%s"},\n' \
        "$(json_escape "$name")" "$kind" "$sz" "$(json_escape "$cons")"
    done < "$list"
    rm -f "$list"
  fi
  if [[ -n "${dl:-}" ]]; then
    list="$RABOTA/.skydl.$$"
    list_files "$dl" > "$list"
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      rel="${file#"$dl"/}"
      folder=""
      [[ "$rel" == */* ]] && folder="${rel%%/*}"
      name="$(pretty_name "$file")"
      kind="$(kind_of "$file")"
      sz="$(file_size "$file")"
      if [[ -n "$folder" ]] && tidy_folder_name "$folder"; then
        cons="$folder"
      else
        cons="$(sky_kind_constellation "$file" "$folder")"
      fi
      printf '  {name:"%s",kind:"%s",size:%s,constellation:"%s"},\n' \
        "$(json_escape "$name")" "$kind" "$sz" "$(json_escape "$cons")"
    done < "$list"
    rm -f "$list"
  fi
  printf '];\n'
}

cmd_chudo() {
  local out="$RABOTA/chudo.html" sky="$RABOTA/sky.js"
  if [[ ! -f "$RABOTA/idilliya.txt" ]]; then
    cmd_idilliya
    printf '\n'
  fi
  collect_sky_js > "$sky"
  cat > "$out" << 'HTML'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="color-scheme" content="dark light" />
<title>Вечер — Порядок на диске</title>
<style>
  :root {
    --paper:#110f0d; --sheet:#1a1713; --ink:#ece6d6; --muted:#9a8f7c;
    --rule:#3d372e; --gilt:#c4a36a; --star:#f3ead6; --halo:rgba(243,234,214,.22);
  }
  html[data-lamp="on"] {
    --paper:#f3efe6; --sheet:#ebe4d6; --ink:#241f18; --muted:#5a534a;
    --rule:#cfc6b8; --gilt:#8a6a3a; --star:#241f18; --halo:transparent;
  }
  html,body {
    margin:0; background:var(--paper); color:var(--ink);
    font-family: Palatino, "Palatino Linotype", "Book Antiqua", Georgia, "Times New Roman", serif;
    transition: background-color .4s ease, color .4s ease;
  }
  #lamp {
    position:fixed; top:1.25rem; right:1.4rem; background:none; border:0;
    color:var(--muted); letter-spacing:.18em; font: inherit; cursor:pointer;
    font-variant: small-caps; font-size:.95rem;
  }
  #lamp:hover { color:var(--ink); }
  main { max-width:42rem; margin:0 auto; padding:3.6rem 1.4rem 5.5rem; }
  .kicker { letter-spacing:.22em; text-transform:lowercase; color:var(--muted); font-size:.95rem; text-align:center; }
  .hair { height:5px; width:3.2rem; margin:1.5rem auto; border-top:1px solid var(--ink); border-bottom:1px solid var(--ink); opacity:.45; }
  h1 { font-weight:500; font-size:clamp(2.4rem,6vw,3.4rem); line-height:1.08; margin:0; text-align:center; }
  p { line-height:1.7; }
  .lead { text-align:center; margin:1.35rem 0 0; color:var(--muted); letter-spacing:.08em; }
  .sheet { background:var(--sheet); margin:2.4rem 0 0; overflow:hidden; }
  svg { display:block; width:100%; height:auto; }
  #caption { margin:0; padding:.85rem 1rem 1.1rem; text-align:center; color:var(--muted); letter-spacing:.12em; font-size:.92rem; min-height:2.6rem; }
  #idyll { margin:2.6rem 0 0; }
  #idyll p { margin:0 0 1.2rem; }
  .muted { color:var(--muted); text-align:center; margin-top:2.6rem; }
</style>
</head>
<body>
<button id="lamp" type="button">лампа</button>
<main>
  <p class="kicker">вечер</p>
  <div class="hair"></div>
  <h1>Ночная карта</h1>
  <p class="lead">Сегодня вечером.</p>
  <div class="sheet">
    <svg id="atlas" viewBox="0 0 800 560" role="img" aria-label="Ночная карта диска"></svg>
    <p id="caption">·</p>
  </div>
  <div id="idyll"></div>
  <p class="muted">Спешки нет. Это ваш диск.</p>
</main>
<script>
HTML
  cat "$sky" >> "$out"
  collect_idyll_js >> "$out"
  cat >> "$out" << 'HTML'
function hash(s){let h=2166136261;for(let i=0;i<s.length;i++)h=Math.imul(h^s.charCodeAt(i),16777619);return (h>>>0)/4294967296;}
function dist(a,b){return Math.hypot(a.x-b.x,a.y-b.y);}
function mst(nodes,maxLen){
  if(nodes.length<2) return [];
  const used=new Set([0]), links=[];
  while(used.size<nodes.length){
    let best=Infinity, from=-1, to=-1;
    for(const i of used){
      for(let j=0;j<nodes.length;j++){
        if(used.has(j)) continue;
        const d=dist(nodes[i],nodes[j]);
        if(d<best){best=d;from=i;to=j;}
      }
    }
    if(to<0) break;
    used.add(to);
    if(best>8 && best<maxLen) links.push({x1:nodes[from].x,y1:nodes[from].y,x2:nodes[to].x,y2:nodes[to].y});
  }
  return links;
}
function layout(items,w,h){
  const vis=items.slice(0,240);
  const names=[...new Set(vis.map(s=>s.constellation))];
  const cx=w/2, cy=h/2+8, ring=Math.min(w,h)*0.3;
  const centers=new Map();
  names.forEach((name,i)=>{
    const wobble=(hash(name)-0.5)*0.7;
    const a=-Math.PI/2+(i/Math.max(names.length,1))*Math.PI*2+wobble;
    const rad=ring*(0.82+hash(name+"r")*0.28);
    centers.set(name,{x:cx+Math.cos(a)*rad*1.18,y:cy+Math.sin(a)*rad*0.9});
  });
  const stars=vis.map(star=>{
    const c=centers.get(star.constellation)||{x:cx,y:cy};
    const n=vis.filter(s=>s.constellation===star.constellation).length;
    const spread=18+Math.min(n,14)*3.2;
    const ang=hash(star.name+star.constellation)*Math.PI*2;
    const jr=(0.15+hash(star.name+"d")*0.85)*spread;
    return {...star,x:c.x+Math.cos(ang)*jr,y:c.y+Math.sin(ang)*jr*0.78,r:1.15+Math.log10(Math.max(star.size,10))*1.05};
  });
  const links=[];
  names.forEach(name=>{
    const group=stars.filter(s=>s.constellation===name).sort((a,b)=>b.size-a.size).slice(0,6);
    links.push(...mst(group,92));
  });
  const labels=names.map(name=>{
    const group=stars.filter(s=>s.constellation===name);
    const gx=group.reduce((s,p)=>s+p.x,0)/Math.max(group.length,1);
    const gy=group.reduce((s,p)=>s+p.y,0)/Math.max(group.length,1);
    let ox=0, oy=-22, nearest=Infinity;
    names.forEach(other=>{
      if(other===name) return;
      const o=centers.get(other); if(!o) return;
      const d=dist({x:gx,y:gy},o);
      if(d<nearest){
        nearest=d;
        const ux=gx-o.x, uy=gy-o.y, len=Math.hypot(ux,uy)||1;
        ox=(ux/len)*16; oy=(uy/len)*16-8;
      }
    });
    return {name,x:gx+ox,y:gy+oy};
  });
  const field=[];
  for(let i=0;i<90;i++){
    if(hash("keep"+i)<0.22) continue;
    field.push({x:16+hash("x"+i)*(w-32),y:16+hash("y"+i)*(h-32),r:0.25+hash("r"+i)*0.85});
  }
  return {stars,links,labels,field};
}
const svg=document.getElementById("atlas");
const NS="http://www.w3.org/2000/svg";
const cap=document.getElementById("caption");
function el(n,a){const e=document.createElementNS(NS,n);for(const k in a)e.setAttribute(k,a[k]);return e;}
function css(name){return getComputedStyle(document.documentElement).getPropertyValue(name).trim();}
function paint(){
  while(svg.firstChild) svg.removeChild(svg.firstChild);
  const sheet=css("--sheet")||"#1a1713";
  const rule=css("--rule")||"#3d372e";
  const gilt=css("--gilt")||"#c4a36a";
  const star=css("--star")||"#f3ead6";
  const halo=css("--halo")||"rgba(243,234,214,.22)";
  svg.appendChild(el("rect",{width:800,height:560,fill:sheet}));
  const e1=el("ellipse",{cx:400,cy:280,rx:310,ry:214,fill:"none",stroke:rule,"stroke-width":"0.5",opacity:"0.55"});
  e1.setAttribute("transform","rotate(-9 400 280)");
  svg.appendChild(e1);
  const e2=el("ellipse",{cx:400,cy:280,rx:210,ry:148,fill:"none",stroke:rule,"stroke-width":"0.45",opacity:"0.4"});
  e2.setAttribute("transform","rotate(14 400 280)");
  svg.appendChild(e2);
  const laid=layout(SKY,800,560);
  laid.field.forEach(s=>svg.appendChild(el("circle",{cx:s.x,cy:s.y,r:s.r,fill:gilt,opacity:"0.28"})));
  laid.links.forEach(l=>svg.appendChild(el("line",{x1:l.x1,y1:l.y1,x2:l.x2,y2:l.y2,stroke:gilt,"stroke-width":"0.7",opacity:"0.55"})));
  laid.stars.forEach(s=>{
    const g=el("g",{});
    g.appendChild(el("circle",{cx:s.x,cy:s.y,r:s.r*2.4,fill:halo}));
    g.appendChild(el("circle",{cx:s.x,cy:s.y,r:s.r,fill:star}));
    g.addEventListener("mouseenter",()=>{cap.textContent=s.name+" · "+s.constellation.toLowerCase();});
    svg.appendChild(g);
  });
  svg.addEventListener("mouseleave",()=>{cap.textContent="·";});
  laid.labels.forEach(l=>{
    const tx=el("text",{x:l.x,y:l.y,"text-anchor":"middle",fill:gilt,"font-family":"Palatino, Georgia, serif","font-size":"13","letter-spacing":"0.22em"});
    tx.textContent=l.name.toLowerCase();
    svg.appendChild(tx);
  });
}
paint();
const lamp=document.getElementById("lamp");
function applyLamp(on){
  document.documentElement.setAttribute("data-lamp", on ? "on" : "off");
  lamp.textContent = on ? "погасить" : "лампа";
  try { localStorage.setItem("poryadok-lamp", on ? "on" : "off"); } catch(e) {}
  paint();
}
try { if (localStorage.getItem("poryadok-lamp")==="on") applyLamp(true); } catch(e) {}
lamp.addEventListener("click",()=>applyLamp(document.documentElement.getAttribute("data-lamp")!=="on"));
const box=document.getElementById("idyll");
if(typeof IDYLL==="string" && IDYLL.trim()){
  IDYLL.trim().split(/\n{2,}/).forEach(chunk=>{
    const p=document.createElement("p");
    p.textContent=chunk.replace(/\n/g," ").trim();
    box.appendChild(p);
  });
}
</script>
</body>
</html>
HTML

  printf '%s\n' "Ночная карта готова. Можно показать матери."
  printf '%s\n' "$out"
  open_page "$out"
}

open_page() {
  local file="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cmd //c start "" "$(cygpath -w "$file")"
  elif command -v cmd >/dev/null 2>&1; then
    cmd //c start "" "$file"
  else
    xdg-open "$file" >/dev/null 2>&1 || true
  fi
}

cmd_vecher() {
  cmd_idilliya
  printf '\n'
  cmd_chudo
}

cmd_pomoshch() {
  cat << 'EOF'
Порядок на диске. На этом компьютере. В сеть ничего не уходит.

Сначала перейдите в папку:

  cd ~/poryadok-na-diske

Потом одна команда:

  bash poryadok.sh vecher     вечерняя картина и ночная карта
  bash poryadok.sh idilliya   только слова
  bash poryadok.sh chudo      только карта в браузере
  bash poryadok.sh otchet     отчёт. без удаления
  bash poryadok.sh plan       план разбора. файлы ещё на месте
  bash poryadok.sh kopiya     запасная копия «Загрузок». ещё не копирует
  bash poryadok.sh soglasen   выполнить план или копию — спросит «согласен»

Ничего не удаляет.
Трогает файлы только после ясных слов «согласен».
EOF
}

main() {
  local cmd="${1:-vecher}"
  shift || true
  case "$cmd" in
    otchet|отчет|отчёт) cmd_otchet "$@" ;;
    idilliya|idyll|идиллия) cmd_idilliya "$@" ;;
    chudo|чудо|atlas) cmd_chudo "$@" ;;
    vecher|вечер|evening) cmd_vecher "$@" ;;
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
