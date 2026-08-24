@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo [INTEGRATION CONTINUE] Build et Tests des Binaires Cibles
echo =======================================================

set COMPILER=fpc
set FLAGS=-O2 -v0

echo.
echo [1/3] Compilation de NanoBasic (CLI)...
%COMPILER% %FLAGS% nanobasic.pas
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo [2/3] Compilation de Test_Host (Embarquement IDE)...
%COMPILER% %FLAGS% test_host.pas
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo [3/3] Compilation de Test_FFI (Automate / Callbacks)...
%COMPILER% %FLAGS% test_ffi.pas
if !ERRORLEVEL! NEQ 0 goto BuildError

echo.
echo =======================================================
echo TOUTES LES COMPILATIONS ONT REUSSI. Lancement des tests.
echo =======================================================
echo.

echo --- EXECUTION : test_host.exe ---
test_host.exe
if !ERRORLEVEL! NEQ 0 goto RunError

echo.
echo --- EXECUTION : test_ffi.exe ---
test_ffi.exe
if !ERRORLEVEL! NEQ 0 goto RunError

echo.
echo =======================================================
echo [STATUS] VALIDATION BIANIRE COMPLETE : 100%% SUCCES.
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