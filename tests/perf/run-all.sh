#!/bin/sh
# Phase 7 : charge chaque scénario, chronomètre, puis revient à pme-25. Sauvegarde unique au départ.
cd "$(dirname "$0")/../.."
powershell -NoProfile -File scripts/local-backup.ps1 || exit 1
for s in pme-25 pme-80 eti-200 grande-1000; do
  powershell -NoProfile -File scripts/qa-reset-scenario.ps1 -Scenario $s -NoBackup || exit 1
  node tests/perf/perf.mjs $s > tests/perf/resultats/$s.txt 2>&1
done
powershell -NoProfile -File scripts/qa-reset-scenario.ps1 -Scenario pme-25 -NoBackup
echo FINI
