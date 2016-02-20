@echo off
rem This file is intended for DiSK use on Windows

:loop
perl tilesGen.pl loop
git pull
sleep 60

goto loop
