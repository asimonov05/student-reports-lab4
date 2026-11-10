#!/usr/bin/env bash
# Проверка диалогового сценария без графической сессии: Zenity и CLI заменены
# небольшими контрактными заглушками. Реальные расчёты проверяются отдельно.
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/student-gui-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/app/bin" "$test_dir/mock"
cp -- "$project_dir/bin/student-gui" "$test_dir/app/bin/student-gui"
export GUI_TEST_DIR="$test_dir" DISPLAY=:mock

cat >"$test_dir/app/bin/student-report" <<'REPORT'
#!/usr/bin/env bash
set -eu
[[ $1 == --data && $2 == "$GUI_TEST_DIR/data with spaces" ]]
shift 2
printf '%s\t' "$@" >>"$GUI_TEST_DIR/calls"
printf '\n' >>"$GUI_TEST_DIR/calls"
case $1 in
    groups) printf 'A-06-23\nA-09-23\n' ;;
    subjects) printf 'Предмет A\nПредмет B\n' ;;
    tests)
        [[ $2 == 'Предмет B' ]]
        printf '2\n6\n'
        ;;
    *)
        if [[ ${GUI_TEST_FAIL_REPORT:-0} == 1 ]]; then
            printf 'Ошибка: исходный файл повреждён.\n' >&2
            exit 2
        fi
        if [[ ${GUI_TEST_TABLE:-0} == 1 ]]; then
            printf 'Результат\n\nПредмет: Предмет A\n'
            printf 'Студент\tГруппа\tБаллы\n'
            printf 'Surovtsev-ButovA\tA-06-04\t15\n'
            printf 'ИвановИ\tA-09-23\t5\n'
            exit 0
        fi
        printf 'Результат\n'
        printf '%s\t' "$@"
        printf '\n'
        ;;
esac
REPORT

cat >"$test_dir/mock/zenity" <<'ZENITY'
#!/usr/bin/env bash
set -eu
count=$(cat "$GUI_TEST_DIR/counter")
count=$((count + 1))
printf '%s' "$count" >"$GUI_TEST_DIR/counter"
line=$(sed -n "${count}p" "$GUI_TEST_DIR/queue")
if [[ -z $line ]]; then
    printf 'Unexpected Zenity call: %s\n' "$*" >&2
    exit 99
fi
status=${line%%|*}
line=${line#*|}
kind=${line%%|*}
value=${line#*|}
[[ $1 == "--$kind" ]] || { printf 'Unexpected dialog: %s, expected %s\n' "$1" "$kind" >&2; exit 99; }
printf '%s\n' "$@" >>"$GUI_TEST_DIR/dialogs"
if [[ $kind == text-info ]]; then
    for argument in "$@"; do
        if [[ $argument == --filename=* ]]; then
            cat -- "${argument#--filename=}" >>"$GUI_TEST_DIR/displayed"
        fi
    done
fi
if [[ -n $value ]]; then printf '%s\n' "$value"; fi
exit "$status"
ZENITY
chmod +x "$test_dir/app/bin/student-report" "$test_dir/mock/zenity"
export PATH="$test_dir/mock:$PATH"
passed=0

prepare() {
    printf '0' >"$test_dir/counter"
    : >"$test_dir/calls"
    : >"$test_dir/dialogs"
    : >"$test_dir/displayed"
    unset GUI_TEST_FAIL_REPORT GUI_TEST_TABLE
    cat >"$test_dir/queue"
}

run_gui() {
    bash "$test_dir/app/bin/student-gui" --data "$test_dir/data with spaces" \
        >"$test_dir/stdout" 2>"$test_dir/stderr"
    local expected actual
    expected=$(wc -l <"$test_dir/queue")
    actual=$(cat "$test_dir/counter")
    [[ $expected -eq $actual ]] || { printf 'Not all expected dialogs were opened.\n' >&2; exit 1; }
}

pass() {
    passed=$((passed + 1))
    printf 'ok %s - %s\n' "$passed" "$1"
}

prepare <<'EOF'
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/calls && ! -s $test_dir/stderr ]]
pass 'Выход из главного меню'

prepare <<'EOF'
0|list|4
0|text-info|
1|list|
EOF
run_gui
grep -Fqx $'longest-names\t' "$test_dir/calls"
cmp "$test_dir/stdout" "$test_dir/displayed"
grep -Fqx -- '--title=Самые длинные фамилии' "$test_dir/dialogs"
pass 'Функция 4 без параметров; результат одинаков в stdout и окне'

prepare <<'EOF'
0|list|4
0|text-info|
1|list|
EOF
export GUI_TEST_TABLE=1
run_gui
cmp "$test_dir/stdout" "$test_dir/displayed"
cat >"$test_dir/expected-table" <<'EOF'
Результат

Предмет: Предмет A
Студент           Группа   Баллы
Surovtsev-ButovA  A-06-04  15
ИвановИ           A-09-23  5
EOF
cmp "$test_dir/stdout" "$test_dir/expected-table"
grep -Fqx -- '--font=Monospace 11' "$test_dir/dialogs"
pass 'Длинные и кириллические имена выровнены под заголовками; параметры сохранены'

prepare <<'EOF'
0|list|2
0|list|A-06-23
0|list|Предмет B
0|list|6
0|text-info|
1|list|
EOF
run_gui
grep -Fqx $'tests\tПредмет B\t' "$test_dir/calls"
grep -Fqx $'retakes\tA-06-23\tПредмет B\t6\t' "$test_dir/calls"
cmp "$test_dir/stdout" "$test_dir/displayed"
pass 'Функция 2 выбирает группу, предмет, затем тест этого предмета'

prepare <<'EOF'
0|list|5
0|list|Предмет B
0|list|2
0|text-info|
1|list|
EOF
run_gui
grep -Fqx $'yearly-best\tПредмет B\t2\t' "$test_dir/calls"
if grep -Fqx $'groups\t' "$test_dir/calls"; then exit 1; fi
pass 'Функция 5 выбирает предмет и тест без фильтра по группе'

prepare <<'EOF'
0|list|3
0|list|Предмет A
0|text-info|
1|list|
EOF
run_gui
grep -Fqx $'first-pass\tПредмет A\t' "$test_dir/calls"
pass 'Функция 3 передаёт выбранный предмет'

prepare <<'EOF'
0|list|1
0|list|A-06-23
0|list|Предмет A
0|forms||5
0|error|
0|forms|8|3
0|error|
0|forms|1|1000000000
0|error|
0|forms|0004|0010
0|text-info|
1|list|
EOF
run_gui
grep -Fqx $'attendance\tA-06-23\tПредмет A\t4\t10\t' "$test_dir/calls"
[[ $(grep -cx -- '--error' "$test_dir/dialogs") -eq 3 ]]
pass 'Функция 1 повторяет неверный ввод и принимает включительный диапазон'

prepare <<'EOF'
0|list|1
1|list|
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/stderr ]]
pass 'Отмена выбора группы возвращает главное меню'

prepare <<'EOF'
0|list|3
1|list|
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/stderr ]]
pass 'Отмена выбора предмета возвращает главное меню'

prepare <<'EOF'
0|list|5
0|list|Предмет B
1|list|
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/stderr ]]
pass 'Отмена выбора теста возвращает главное меню'

prepare <<'EOF'
0|list|1
0|list|A-06-23
0|list|Предмет A
1|forms|
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/stderr ]]
pass 'Отмена ввода диапазона возвращает главное меню'

prepare <<'EOF'
0|list|4
0|error|
1|list|
EOF
export GUI_TEST_FAIL_REPORT=1
run_gui
[[ ! -s $test_dir/stdout ]]
grep -Fq 'исходный файл повреждён' "$test_dir/stderr"
pass 'Ошибка чтения данных показана пользователю без ложного результата'

prepare <<'EOF'
0|list|
0|error|
1|list|
EOF
run_gui
[[ ! -s $test_dir/stdout && ! -s $test_dir/calls ]]
pass 'Пустой выбор функции предлагает повторить ввод'

printf 'GUI: пройдено %s проверок.\n' "$passed"
