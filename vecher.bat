@echo off
chcp 65001 >nul
set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if "%BASH%"=="" (
  echo Нужен Git Bash. Спешки нет.
  pause
  exit /b 1
)
cd /d "%~dp0"
"%BASH%" "%~dp0poryadok.sh" vecher
pause
