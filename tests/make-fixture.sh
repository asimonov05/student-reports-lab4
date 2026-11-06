#!/usr/bin/env bash
# Deterministic, hand-calculated examples; no production student data.
set -euo pipefail
target=${1:?Usage: make-fixture.sh TARGET}
mkdir -p "$target/students/groups" "$target/Математика/tests" "$target/История/tests"
cat > "$target/students/groups/A-06-23" <<'EOF'
PetrovAB
IvanovCD
Surovtsev-ButovA
АлександровскаяАБ
MixupGH
EOF
cat > "$target/students/groups/A-09-22" <<'EOF'
PetrovAB
AbcdefghijklmnoAB
OtherIJ
EOF
for subject in Математика История; do
    cat > "$target/$subject/A-06-23-attendance" <<'EOF'
PetrovAB 1110
IvanovCD 0111
Surovtsev-ButovA 1101
АлександровскаяАБ 0111
MixupGH 0000
EOF
    cat > "$target/$subject/A-09-22-attendance" <<'EOF'
PetrovAB 1111
AbcdefghijklmnoAB 0000
OtherIJ 0000
EOF
done
cat > "$target/Математика/tests/TEST-1" <<'EOF'
A-06-23;PetrovAB;2024-05-10;14;2
A-06-23;PetrovAB;2024-01-10;16;3
A-06-23;IvanovCD;2024-03-10;25;3--
A-06-23;Surovtsev-ButovA;2024-01-10;1;2
A-06-23;Surovtsev-ButovA;2024-03-10;2;2+
A-06-23;Surovtsev-ButovA;2025-01-10;16;3
A-06-23;АлександровскаяАБ;2024-02-10;25;4
A-06-23;MixupGH;2024-06-10;3;2
A-06-23;MixupGH;2024-01-10;17;3
A-06-23;MixupGH;2024-04-10;2;2--
A-09-22;PetrovAB;2024-08-10;18;4
A-09-22;AbcdefghijklmnoAB;2025-01-10;24;5
A-09-22;OtherIJ;2025-02-10;24;5+
EOF
for test_number in 2 3 4; do
    cat > "$target/Математика/tests/TEST-$test_number" <<'EOF'
A-06-23;PetrovAB;2024-01-10;20;4
A-06-23;IvanovCD;2024-01-10;18;3++
A-06-23;Surovtsev-ButovA;2024-01-10;20;4
A-06-23;АлександровскаяАБ;2024-01-10;20;4
A-06-23;MixupGH;2024-01-10;20;4
A-09-22;PetrovAB;2024-01-10;20;4
A-09-22;AbcdefghijklmnoAB;2025-01-10;20;4
EOF
    if [[ $test_number != 4 ]]; then
        printf '%s\n' 'A-09-22;OtherIJ;2025-01-10;20;4' >> "$target/Математика/tests/TEST-$test_number"
    fi
done
for test_number in 1 2 3 4; do
    cat > "$target/История/tests/TEST-$test_number" <<'EOF'
A-06-23;PetrovAB;2024-01-10;10;2
A-06-23;PetrovAB;2024-02-10;20;4
A-06-23;IvanovCD;2024-01-10;10;2
A-06-23;IvanovCD;2024-02-10;20;4
A-06-23;Surovtsev-ButovA;2024-01-10;20;4
A-06-23;АлександровскаяАБ;2024-01-10;20;4
A-06-23;MixupGH;2024-01-10;20;4
A-09-22;PetrovAB;2024-01-10;20;4
A-09-22;AbcdefghijklmnoAB;2025-01-10;20;4
A-09-22;OtherIJ;2024-01-10;25;5
EOF
done
