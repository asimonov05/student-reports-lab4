#!/usr/bin/env bash
# Проверка данных и расчёты для командного интерфейса.
fail() {
    printf 'Ошибка: %s\n' "$*" >&2
    exit 2
}
positive_integer() { [[ $1 =~ ^[0-9]{1,9}$ && $1 =~ [1-9] ]]; }
readable_file() {
    [[ -f $1 && -r $1 ]] || fail "Файл отсутствует или недоступен для чтения: $1"
}
safe_component() { [[ -n $1 && $1 != . && $1 != .. && $1 != */* && $1 != *$'\n'* && $1 != *$'\t'* ]]; }

prepare_environment() {
    local candidate charmap
    command -v gawk >/dev/null 2>&1 || fail 'Требуется GNU awk (gawk). Установите пакет gawk.'
    for candidate in C.UTF-8 C.utf8 en_US.UTF-8; do
        charmap=$(LC_ALL=$candidate locale charmap 2>/dev/null) || continue
        [[ $charmap == UTF-8 ]] || continue
        export LC_ALL=$candidate
        break
    done
    [[ ${charmap:-} == UTF-8 ]] || fail 'Нужна локаль UTF-8, например C.UTF-8.'
    [[ -d $DATA_DIR && -r $DATA_DIR && -x $DATA_DIR ]] || fail "Каталог данных отсутствует или недоступен: $DATA_DIR"
    DATA_DIR=$(cd -- "$DATA_DIR" && pwd -P)
    [[ -d $DATA_DIR/students/groups && -r $DATA_DIR/students/groups && -x $DATA_DIR/students/groups ]] || fail 'Не найден доступный каталог students/groups.'
    shopt -s nullglob
    GROUP_FILES=("$DATA_DIR"/students/groups/*)
    ((${#GROUP_FILES[@]})) || fail 'В students/groups нет файлов групп.'
    local file
    for file in "${GROUP_FILES[@]}"; do
        readable_file "$file"
        safe_component "${file##*/}" || fail "Недопустимое имя группы: $file"
    done
}

list_groups() {
    local file
    for file in "${GROUP_FILES[@]}"; do
        printf '%s\n' "${file##*/}"
    done
}
list_subjects() {
    local dir found=0
    for dir in "$DATA_DIR"/*/; do
        [[ ${dir%/} != "$DATA_DIR/students" ]] || continue
        [[ -d ${dir}tests ]] || continue
        dir=${dir%/}
        safe_component "${dir##*/}" || fail "Недопустимое имя предмета: $dir"
        printf '%s\n' "${dir##*/}"
        found=1
    done
    ((found)) || fail 'В базе не найдены предметы с каталогом tests.'
}
check_group() {
    safe_component "$1" || fail 'Некорректный номер группы.'
    readable_file "$DATA_DIR/students/groups/$1"
}
check_subject() {
    if ! safe_component "$1" || [[ $1 == students ]]; then
        fail 'Некорректное название предмета.'
    fi
    [[ -d $DATA_DIR/$1/tests && -r $DATA_DIR/$1/tests && -x $DATA_DIR/$1/tests ]] || fail "Предмет не найден или недоступен: $1"
}
check_test() {
    [[ $2 =~ ^[1-4]$ ]] || fail 'Номер теста должен быть от 1 до 4.'
    readable_file "$DATA_DIR/$1/tests/TEST-$2"
}
list_tests() {
    local number found=0
    for number in 1 2 3 4; do
        if [[ -f $DATA_DIR/$1/tests/TEST-$number ]]; then
            readable_file "$DATA_DIR/$1/tests/TEST-$number"
            printf '%s\n' "$number"
            found=1
        fi
    done
    ((found)) || fail "Нет доступных тестов предмета $1."
}

run_report() {
    local mode=$1 group=$2 subject=$3 test=$4 first=$5 last=$6 file number
    local -a files=("${GROUP_FILES[@]}")
    case $mode in
        attendance)
            file="$DATA_DIR/$subject/$group-attendance"
            readable_file "$file"
            files+=("$file") ;;
        retakes|yearly-best) files+=("$DATA_DIR/$subject/tests/TEST-$test") ;;
        first-pass)
            for number in 1 2 3 4; do
                check_test "$subject" "$number"
                files+=("$DATA_DIR/$subject/tests/TEST-$number")
            done ;;
    esac
    REPORT_ROOT=$DATA_DIR REPORT_MODE=$mode REPORT_GROUP=$group REPORT_SUBJECT=$subject \
    REPORT_TEST=$test REPORT_FIRST=$first REPORT_LAST=$last gawk '
    function error(message) {
        printf "Ошибка: %s (%s:%d)\n", message, FILENAME, FNR > "/dev/stderr"
        bad=1
        exit 2
    }
    function valid_date(value, parts, days, year, month, day) {
        if (value !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) return 0
        split(value,parts,"-")
        year=parts[1]+0
        month=parts[2]+0
        day=parts[3]+0
        if (year<1 || month<1 || month>12 || day<1) return 0
        days=(month==2 ? 28+(year%4==0 && (year%100!=0 || year%400==0)) : (month==4 || month==6 || month==9 || month==11 ? 30 : 31))
        return day<=days
    }
    function heading(title) { print title; print "" }
    function no_results() { print "Подходящих студентов нет." }
    function emit_people(values, type, count, order, i, key, id) {
        count=asorti(values,order)
        if (!count) { no_results(); return }
        for(i=1;i<=count;i++) {
            key=order[i]; id=values[key]
            if(type=="attendance") print names[id],groups[id],visits[id]
            else if(type=="retakes") print names[id],groups[id],attempts[id]-1
            else if(type=="longest-names") print names[id],groups[id],surnames[id],length(surnames[id])
            else print names[id],groups[id]
        }
    }
    BEGIN {
        OFS="\t"
        root=ENVIRON["REPORT_ROOT"]; mode=ENVIRON["REPORT_MODE"]
        group=ENVIRON["REPORT_GROUP"]; subject=ENVIRON["REPORT_SUBJECT"]
        test=ENVIRON["REPORT_TEST"]; first=ENVIRON["REPORT_FIRST"]+0; last=ENVIRON["REPORT_LAST"]+0
    }
    BEGINFILE {
        if(ERRNO!="") error("Не удалось прочитать файл: " ERRNO)
        relative=substr(FILENAME,length(root)+2)
        if(index(relative,"students/groups/")==1) {
            kind="roster"
            current_group=substr(relative,length("students/groups/")+1)
        } else if(index(relative,subject "/tests/")==1) {
            kind="test"
            current_test=substr(relative,length(subject "/tests/TEST-")+1)
        } else kind="attendance"
        rows=0
    }
    {
        sub(/\r$/,"")
        if(FNR==1) sub(/^\xef\xbb\xbf/,"")
        if($0 ~ /^[ \t]*$/) next
        rows++
        if(kind=="roster") {
            if($0 ~ /[;[:space:]]/) error("Ожидался один идентификатор студента в строке")
            # Одинаковые имена в разных группах — это разные студенты.
            id=current_group SUBSEP $0
            if(id in names) error("Студент дважды записан в группе")
            names[id]=$0
            groups[id]=current_group
            if(!match($0,/^[[:upper:]][[:lower:]]*(-[[:upper:]][[:lower:]]+)*/)) error("Не удалось выделить фамилию")
            surnames[id]=substr($0,RSTART,RLENGTH)
        } else if(kind=="test") {
            if(split($0,fields,";")!=5) error("В строке теста должно быть пять полей через точку с запятой")
            id=fields[1] SUBSEP fields[2]
            if(!(id in names)) error("Студент или группа из теста отсутствует в students/groups")
            if(!valid_date(fields[3])) error("Некорректная дата попытки")
            if(fields[4] !~ /^[0-9]+$/ || length(fields[4])>9) error("Количество правильных ответов должно быть неотрицательным целым числом")
            if(fields[5] !~ /^[2-5]([+][+]?|--?)?$/) error("Некорректная оценка")
            if(mode=="retakes" && fields[1]==group) attempts[id]++
            if(mode=="first-pass") {
                tries[id,current_test]++
                grade[id,current_test]=fields[5]+0
            }
            if(mode=="yearly-best") {
                year=substr(fields[3],1,4)
                score=fields[4]+0
                if(!(year in best_year) || score>best_year[year]) best_year[year]=score
                if(!((year SUBSEP id) in person_year) || score>person_year[year,id]) person_year[year,id]=score
            }
        } else {
            line=$0
            sub(/^[ \t]+/,"",line)
            sub(/[ \t]+$/,"",line)
            if(split(line,fields,/[ \t]+/)!=2 || fields[2] !~ /^[01]+$/) error("Посещаемость: ожидается имя и строка из 0 и 1")
            id=group SUBSEP fields[1]
            if(!(id in names)) error("Студент из посещаемости отсутствует в выбранной группе")
            if(id in visits) error("Повторная строка посещаемости студента")
            if(last>length(fields[2])) error("Конец диапазона превышает число занятий (" length(fields[2]) ")")
            visits[id]=0
            for(i=first;i<=last;i++) visits[id]+=substr(fields[2],i,1)
        }
    }
    ENDFILE {
        if(!bad && kind=="roster" && !rows) error("Пустой список группы")
        if(!bad && kind=="attendance" && !rows) error("Пустой файл посещаемости")
    }
    END {
        if(bad) exit 2
        if(mode=="attendance") {
            maximum=-1
            for(id in names) if(groups[id]==group) {
                if(!(id in visits)) error("В посещаемости отсутствует студент " names[id])
                if(visits[id]>maximum) maximum=visits[id]
            }
            for(id in visits) if(visits[id]==maximum) result[names[id] SUBSEP groups[id]]=id
            heading("Лучшая посещаемость")
            print "Группа: " group "; предмет: " subject "; занятия: " first "–" last " включительно"
            print "Студент","Группа","Посещено"
            emit_people(result,mode)
        } else if(mode=="retakes") {
            maximum=-1; chosen=""
            for(id in attempts) {
                key=names[id] SUBSEP groups[id]
                if(attempts[id]>maximum || (attempts[id]==maximum && key<chosen)) {
                    maximum=attempts[id]
                    chosen=key
                    winner=id
                }
            }
            if(chosen!="") result[chosen]=winner
            heading("Максимальное количество пересдач")
            print "Группа: " group "; предмет: " subject "; тест: " test "; все годы"
            print "Студент","Группа","Пересдачи"
            emit_people(result,mode)
        } else if(mode=="first-pass") {
            for(id in names) {
                passed=1
                for(i=1;i<=4;i++) if(tries[id,i]!=1 || grade[id,i]<3) passed=0
                if(passed) result[names[id] SUBSEP groups[id]]=id
            }
            heading("Все тесты с первой попытки")
            print "Предмет: " subject "; все группы; тесты 1–4"
            print "Студент","Группа"
            emit_people(result,mode)
        } else if(mode=="longest-names") {
            maximum=0
            for(id in surnames) if(length(surnames[id])>maximum) maximum=length(surnames[id])
            for(id in surnames) if(length(surnames[id])==maximum) result[names[id] SUBSEP groups[id]]=id
            heading("Самые длинные фамилии")
            print "Область: вся база"
            print "Студент","Группа","Фамилия","Символов"
            emit_people(result,mode)
        } else if(mode=="yearly-best") {
            heading("Лучшие результаты по годам")
            print "Предмет: " subject "; тест: " test "; все группы"
            print "Год","Студент","Группа","Правильных ответов"
            count=asorti(best_year,years)
            if(!count) no_results()
            for(y=1;y<=count;y++) {
                year=years[y]
                delete result
                for(id in names) if(((year SUBSEP id) in person_year) && person_year[year,id]==best_year[year]) result[names[id] SUBSEP groups[id]]=id
                n=asorti(result,order)
                for(i=1;i<=n;i++) {
                    id=result[order[i]]
                    print year,names[id],groups[id],best_year[year]
                }
            }
        }
    }' "${files[@]}"
}
