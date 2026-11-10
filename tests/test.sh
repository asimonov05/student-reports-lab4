#!/usr/bin/env bash
# Integration tests exercise public CLI behavior and independently known answers.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cli="$repo/bin/student-report"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
fixture="$temp/data with spaces"
bash "$repo/tests/make-fixture.sh" "$fixture"
passed=0
failed=0
out=''
status=0

check() {
    local description=$1
    shift
    if "$@"; then
        printf 'ok %02d - %s\n' "$((passed + failed + 1))" "$description"
        passed=$((passed + 1))
    else
        printf 'not ok %02d - %s\n' "$((passed + failed + 1))" "$description"
        printf '  exit=%s\n  stdout: %s\n  stderr: %s\n' "$status" "$out" "$(cat "$temp/stderr")"
        failed=$((failed + 1))
    fi
}
run() {
    status=0
    out=$("$cli" --data "$fixture" "$@" 2> "$temp/stderr") || status=$?
}
row() { grep -Fqx -- "$1" <<< "$out"; }
no_row() { ! row "$1"; }
ok() { [[ $status == 0 ]]; }
bad() { [[ $status != 0 && -s "$temp/stderr" ]]; }
matches() { grep -Eq -- "$1" <<< "$out"; }
match_count() {
    local count
    count=$(grep -Ec -- "$2" <<< "$out") || :
    [[ $count == "$1" ]]
}
row_count() {
    local count
    count=$(grep -Fxc -- "$2" <<< "$out") || :
    [[ $count == "$1" ]]
}
no_results_message() { grep -Eqi 'нет|не найден|отсутств' <<< "$out"; }

run groups
check 'список групп из базы' row 'A-06-23'
check 'список групп включает вторую группу' row 'A-09-22'
run subjects
check 'список предметов из базы' row 'Математика'
check 'второй предмет доступен отдельно' row 'История'
run tests Математика
check 'доступный тест 1' row '1'
check 'доступный тест 4' row '4'

run attendance A-06-23 Математика 2 4
check 'путь с пробелами и успешный запуск' ok
check 'включительный диапазон 2..4, первый лидер' row $'IvanovCD\tA-06-23\t3'
check 'все равные лидеры посещаемости' row $'АлександровскаяАБ\tA-06-23\t3'
check 'студент из другой группы исключён' no_row $'PetrovAB\tA-09-22\t3'
check 'не максимальная посещаемость исключена' no_row $'PetrovAB\tA-06-23\t2'
run attendance A-06-23 Математика 1 1
check 'диапазон из одного занятия' row $'PetrovAB\tA-06-23\t1'
check 'одинаковый максимум за одно занятие' row $'Surovtsev-ButovA\tA-06-23\t1'
run attendance A-09-22 Математика 1 4
check 'фильтр другой группы работает' row $'PetrovAB\tA-09-22\t4'

run retakes A-06-23 Математика 1
check 'пересдачи = попытки минус один, без фильтра лет' matches $'^(Surovtsev-ButovA|MixupGH)\tA-06-23\t2$'
check 'при ничьей пересдач выбран один студент' match_count 1 $'^(Surovtsev-ButovA|MixupGH)\t'
run retakes A-09-22 Математика 1
check 'нулевое число пересдач допустимо' matches $'^[^[:space:]]+\tA-09-22\t0$'

run first-pass Математика
check 'оценки 3-- и 3++ считаются успешными' row $'IvanovCD\tA-06-23'
check 'успешны все четыре теста' row $'АлександровскаяАБ\tA-06-23'
check 'совпавшее имя в другой группе сохраняется' row $'PetrovAB\tA-09-22'
check 'имя с пересдачей исключено только в своей группе' no_row $'PetrovAB\tA-06-23'
check 'неупорядоченные даты не превращают пересдачу в первую попытку' no_row $'MixupGH\tA-06-23'
check 'отсутствие попытки TEST-4 исключает студента' no_row $'OtherIJ\tA-09-22'
run first-pass История
check 'выбор предмета меняет результат первой попытки' no_row $'IvanovCD\tA-06-23'
check 'первая попытка проверяется по выбранному предмету' row $'OtherIJ\tA-09-22'

run longest-names
check 'фамилия с дефисом сохраняется целиком' row $'Surovtsev-ButovA\tA-06-23\tSurovtsev-Butov\t15'
check 'кириллическая длина в символах, а не байтах' row $'АлександровскаяАБ\tA-06-23\tАлександровская\t15'
check 'все максимумы по всей базе' row $'AbcdefghijklmnoAB\tA-09-22\tAbcdefghijklmno\t15'

run yearly-best Математика 1
check 'год взят из даты, максимум 2024' row $'2024\tIvanovCD\tA-06-23\t25'
check 'все лидеры 2024' row $'2024\tАлександровскаяАБ\tA-06-23\t25'
check 'отдельный максимум 2025' row $'2025\tAbcdefghijklmnoAB\tA-09-22\t24'
check 'все лидеры 2025' row $'2025\tOtherIJ\tA-09-22\t24'
check 'попытки не суммируются' no_row $'2024\tPetrovAB\tA-06-23\t30'
run yearly-best История 1
check 'номер теста относится к выбранному предмету' row $'2024\tOtherIJ\tA-09-22\t25'

for range in '0 2' '-1 2' '3 2' '1.5 2' 'x 2' '1 999999999999999999999999999999999999999'; do
    read -r first last <<< "$range"
    run attendance A-06-23 Математика "$first" "$last"
    check "некорректный диапазон $range отклонён" bad
done
run attendance A-06-23 Математика 1 5
check 'диапазон за пределами журнала отклонён' bad
run attendance A-06-23 Математика 1
check 'пропущенный обязательный аргумент отклонён' bad
run retakes A-06-23 Математика 5
check 'отсутствующий тест отклонён' bad
run attendance UNKNOWN Математика 1 2
check 'неизвестная группа отклонена' bad
run yearly-best НетПредмета 1
check 'неизвестный предмет отклонён' bad

good_fixture=$fixture
fixture="$temp/absent"
run longest-names
check 'отсутствующая база даёт понятную ошибку' bad
fixture="$temp/broken attendance"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'PetrovAB 10x0' > "$fixture/Математика/A-06-23-attendance"
run attendance A-06-23 Математика 1 4
check 'недопустимая отметка посещения отклонена' bad
fixture="$temp/broken csv"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'A-06-23;IvanovCD;2024-01-10;25' > "$fixture/Математика/tests/TEST-1"
run yearly-best Математика 1
check 'неполная CSV-строка отклонена' bad
fixture="$temp/empty test"
cp -R -- "$good_fixture" "$fixture"
: > "$fixture/Математика/tests/TEST-1"
run yearly-best Математика 1
check 'пустой корректный тест не является аварией' ok
check 'при отсутствии результатов есть сообщение' no_results_message
fixture=$good_fixture

fixture="$temp/impossible date"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'A-06-23;IvanovCD;2023-02-29;25;5' > "$fixture/Математика/tests/TEST-1"
run yearly-best Математика 1
check 'невозможная календарная дата отклонена' bad
printf '%s\n' 'A-06-23;IvanovCD;2024-02-29;25;5' > "$fixture/Математика/tests/TEST-1"
run yearly-best Математика 1
check '29 февраля високосного года допустимо' row $'2024\tIvanovCD\tA-06-23\t25'

fixture="$temp/invalid grade"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'A-06-23;IvanovCD;2024-01-10;25;6' > "$fixture/Математика/tests/TEST-1"
run first-pass Математика
check 'оценка вне диапазона 2..5 отклонена' bad

fixture="$temp/missing test"
cp -R -- "$good_fixture" "$fixture"
rm -- "$fixture/Математика/tests/TEST-4"
run first-pass Математика
check 'отсутствующий обязательный файл TEST-4 отклонён' bad

fixture="$temp/missing attendance student"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'PetrovAB 1111' > "$fixture/Математика/A-06-23-attendance"
run attendance A-06-23 Математика 1 4
check 'студент из списка группы пропущен в посещаемости' bad

fixture="$temp/duplicate roster"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'PetrovAB' >> "$fixture/students/groups/A-06-23"
run longest-names
check 'дубликат студента внутри одной группы отклонён' bad

fixture="$temp/no first pass"
cp -R -- "$good_fixture" "$fixture"
: > "$fixture/Математика/tests/TEST-4"
run first-pass Математика
check 'отсутствие студентов, сдавших всё, не является ошибкой' ok
check 'нет сдавших все тесты: понятное сообщение' no_results_message

fixture="$temp/repeated yearly maximum"
cp -R -- "$good_fixture" "$fixture"
printf '%s\n' 'A-06-23;IvanovCD;2024-04-10;25;5' >> "$fixture/Математика/tests/TEST-1"
run yearly-best Математика 1
check 'несколько одинаковых лучших попыток не дублируют студента' row_count 1 $'2024\tIvanovCD\tA-06-23\t25'
check 'повторная лучшая попытка не скрывает другого лидера' row $'2024\tАлександровскаяАБ\tA-06-23\t25'

fixture="$temp/all absent"
cp -R -- "$good_fixture" "$fixture"
while IFS= read -r student; do
    printf '%s 0000\n' "$student"
done < "$fixture/students/groups/A-06-23" > "$fixture/Математика/A-06-23-attendance"
run attendance A-06-23 Математика 1 4
check 'нулевой максимум посещаемости включает всю группу' match_count 5 $'^[^[:space:]]+\tA-06-23\t0$'
fixture=$good_fixture

# Checksums include every fixture file; a complete batch must remain read-only.
snapshot() { (cd -- "$fixture" && cksum -- students/groups/* */*-attendance */tests/TEST-*); }
before=$(snapshot)
run attendance A-06-23 Математика 1 4
run retakes A-06-23 Математика 1
run first-pass Математика
run longest-names
run yearly-best Математика 1
after=$(snapshot)
check 'все пять операций сохраняют исходные файлы' test "$before" = "$after"

printf '\nPassed: %s; failed: %s\n' "$passed" "$failed"
[[ $failed == 0 ]]
