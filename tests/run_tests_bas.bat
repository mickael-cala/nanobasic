@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo [QUALIFICATION INDUSTRIELLE] Harnais de Tests NanoBasic
echo =======================================================
echo.

if not exist nanobasic.exe (
    echo [ERREUR FATALE] nanobasic.exe est introuvable. Compilez-le d'abord.
    exit /b 1
)

set PASSED=0
set FAILED=0

for %%f in (test_*.bas) do (
    echo -------------------------------------------------------
    echo [TEST] Fichier : %%f
    
    :: 1. Validation de la syntaxe
    nanobasic.exe --check %%f > nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo [ ECHEC ] Erreur de syntaxe detectee par le Linter !
        set /a FAILED+=1
    ) else (
        :: 2. Execution (on redirige NUL vers l'entree pour eviter un blocage sur un INPUT oublie)
        nanobasic.exe %%f < nul
        if !ERRORLEVEL! EQU 0 (
            echo [ SUCCES ]
            set /a PASSED+=1
        ) else (
            echo [ ECHEC ] Runtime Error / Crash de la VM !
            set /a FAILED+=1
        )
    )
)

echo =======================================================
echo BILAN DES TESTS BASIC
echo =======================================================
echo REUSSIS : !PASSED!
echo ECHOUES : !FAILED!

if !FAILED! GTR 0 (
    echo [STATUS] REFUSE. Corrigez les erreurs avant la mise en production.
    exit /b 1
) else (
    echo [STATUS] VALIDE. Qualite de production atteinte.
)