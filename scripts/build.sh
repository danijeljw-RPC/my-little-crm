#!/bin/zsh
# Counts every app build: appends a line to builds.log, then runs `flutter build "$@"`.
log=/Users/danijeljw/.claude/jobs/b6fb92bf/tmp/builds.log
touch $log
n=$(( $(wc -l < $log) + 1 ))
start=$(date +%s)
flutter build "$@"; rc=$?
echo "#$n $(date '+%F %T') flutter build $* -> exit $rc ($(( $(date +%s)-start ))s)" >> $log
echo "BUILD #$n exit $rc"
exit $rc
