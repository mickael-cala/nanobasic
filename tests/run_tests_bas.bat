@echo off
setlocal enabledelayedexpansion
REM =======================================================
REM [QUALIFICATION] Harnais de Tests BASIC NanoBasic
REM Lancement : depuis n'importe ou ; se replace a la racine
REM du depot via %~dp0
REM =======================================================
cd /d "%~dp0.."

set BIN=%CD%\bin
set EXE=%BIN%\nanobasic.exe
set EXAMPLES=%CD%\examples

echo =======================================================
echo [QUALIFICATION] Harnais de Tests BASIC NanoBasic
echo =======================================================
echo.

if not exist "%EXE%" (
    echo [ERREUR FATALE] nanobasic.exe introuvable dans "%BIN%".
    echo Compilez d'abord avec :  run_tests_exe.bat   ou : make
    exit /b 1
)

set PASSED=0
set EXPECTED_FAIL=0
set FAILED=0

for %%f in ("%EXAMPLES%\test_*.bas") do (
    set NAME=%%~nxf
    echo -------------------------------------------------------
    echo [TEST] Fichier : %%f

    REM --- Cas negatif volontaire : le linter DOIT rejeter test_bad.bas ---
    if /I "!NAME!"=="test_bad.bas" (
        "%EXE%" --check "%%f" > nul 2>&1
        if !ERRORLEVEL! NEQ 0 (
            echo [ SUCCES ] Rejet syntaxique attendu confirme, cas negatif.
            set /a EXPECTED_FAIL+=1
        ) else (
            echo [ ECHEC ] test_bad.bas aurait du etre rejete par le linter !
            set /a FAILED+=1
        )
    ) else (
        REM --- 1. Validation statique (linter) ---
        "%EXE%" --check "%%f" > nul 2>&1
        if !ERRORLEVEL! NEQ 0 (
            echo [ ECHEC ] Erreur de syntaxe detectee par le Linter !
            set /a FAILED+=1
        ) else (
            REM --- 2. Execution, entree : nul pour eviter tout blocage sur INPUT ---
            "%EXE%" "%%f" < nul
            if !ERRORLEVEL! EQU 0 (
                echo [ SUCCES ]
                set /a PASSED+=1
            ) else (
                echo [ ECHEC ] Runtime Error / Crash de la VM !
                set /a FAILED+=1
            )
        )
    )
)

echo =======================================================
echo BILAN DES TESTS BASIC
echo =======================================================
echo REUSSIS         : !PASSED!
echo REJETS ATTENDUS : !EXPECTED_FAIL!
echo ECHOUES         : !FAILED!

if !FAILED! GTR 0 (
    echo [STATUS] REFUSE. Corrigez les erreurs avant la mise en production.
    exit /b 1
) else (
    echo [STATUS] VALIDE. Qualite de production atteinte.
)
