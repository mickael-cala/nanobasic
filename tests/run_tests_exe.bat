@echo off
setlocal enabledelayedexpansion
REM =======================================================
REM [INTEGRATION] Build et tests des binaires hote (Host API + FFI)
REM Lancement : depuis n'importe ou ; se replace a la racine
REM du depot via %~dp0
REM =======================================================
cd /d "%~dp0.."

set SRC=%CD%\src
set TESTS=%CD%\tests
set BIN=%CD%\bin
set COMPILER=fpc
set FLAGS=-O2 -v0 -Fu"%SRC%"

if not exist "%BIN%" mkdir "%BIN%"

echo.
echo [1/3] Compilation de NanoBasic (CLI)...
%COMPILER% %FLAGS% "%SRC%\nanobasic.pas" -o"%BIN%\nanobasic.exe"
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo [2/3] Compilation de Test_Host (Embarquement IDE)...
%COMPILER% %FLAGS% "%TESTS%\test_host.pas" -o"%TESTS%\test_host.exe"
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo [3/3] Compilation de Test_FFI (Automate / Callbacks)...
%COMPILER% %FLAGS% "%TESTS%\test_ffi.pas" -o"%TESTS%\test_ffi.exe"
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo =======================================================
echo TOUTES LES COMPILATIONS ONT REUSSI. Lancement des tests.
echo =======================================================
echo.

echo --- EXECUTION : test_host.exe ---
"%TESTS%\test_host.exe"
if !ERRORLEVEL! NEQ 0 goto RunError

echo.
echo --- EXECUTION : test_ffi.exe ---
"%TESTS%\test_ffi.exe"
if !ERRORLEVEL! NEQ 0 goto RunError

echo.
echo =======================================================
echo [STATUS] VALIDATION BINAIRE COMPLETE : 100%% SUCCES.
echo =======================================================
exit /b 0

:BuildError
echo.
echo [ERREUR FATALE] La compilation a echoue. Arret de la chaine de deploiement.
exit /b 1

:RunError
echo.
echo [ERREUR FATALE] Un binaire a retourne un code d'erreur a l'execution.
exit /b 1
