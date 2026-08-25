PRINT "=================================================="
PRINT "   NANOBASIC V1 - SUITE DE TESTS EXHAUSTIVE       "
PRINT "=================================================="

LET SCORE_PASS = 0
LET SCORE_FAIL = 0

' ==================================================
' 1. MATHS DE BASE & PIEGES
' ==================================================
LET TEST_NAME$ = "Addition & Priorite (10 + 5 * 2)"
LET EXPECTED$ = "20"
LET ACTUAL$ = STR$(10 + 5 * 2)
GOSUB CheckResult

LET TEST_NAME$ = "Soustraction & Negatifs (5 - 10)"
LET EXPECTED$ = "-5"
LET ACTUAL$ = STR$(5 - 10)
GOSUB CheckResult

LET TEST_NAME$ = "Puissance (2 ^ 3)"
LET EXPECTED$ = "8"
LET ACTUAL$ = STR$(2 ^ 3)
GOSUB CheckResult

LET TEST_NAME$ = "Division par zero (10 / 0) -> Survie VM"
LET EXPECTED$ = "0"
LET ACTUAL$ = STR$(10 / 0)
GOSUB CheckResult

' ==================================================
' 2. FONCTIONS MATHEMATIQUES
' ==================================================
LET TEST_NAME$ = "Fonction ABS (-15)"
LET EXPECTED$ = "15"
LET ACTUAL$ = STR$(ABS(-15))
GOSUB CheckResult

LET TEST_NAME$ = "Fonction INT (3.9)"
LET EXPECTED$ = "3"
LET ACTUAL$ = STR$(INT(3.9))
GOSUB CheckResult

LET TEST_NAME$ = "Fonction SQR (16)"
LET EXPECTED$ = "4"
LET ACTUAL$ = STR$(SQR(16))
GOSUB CheckResult

' ==================================================
' 3. CHAINES DE CARACTERES
' ==================================================
LET TEST_NAME$ = "Concatenation (A + B)"
LET EXPECTED$ = "AB"
LET ACTUAL$ = "A" + "B"
GOSUB CheckResult

LET TEST_NAME$ = "Fonction LEN (HELLO)"
LET EXPECTED$ = "5"
LET ACTUAL$ = STR$(LEN("HELLO"))
GOSUB CheckResult

LET TEST_NAME$ = "Fonction LEFT$ (HELLO, 2)"
LET EXPECTED$ = "HE"
LET ACTUAL$ = LEFT$("HELLO", 2)
GOSUB CheckResult

LET TEST_NAME$ = "Fonction MID$ (HELLO, 2, 2)"
LET EXPECTED$ = "EL"
LET ACTUAL$ = MID$("HELLO", 2, 2)
GOSUB CheckResult

LET TEST_NAME$ = "Fonction RIGHT$ (HELLO, 2)"
LET EXPECTED$ = "LO"
LET ACTUAL$ = RIGHT$("HELLO", 2)
GOSUB CheckResult

LET TEST_NAME$ = "Conversion VAL (123)"
LET EXPECTED$ = "123"
LET ACTUAL$ = STR$(VAL("123"))
GOSUB CheckResult

LET TEST_NAME$ = "ASCII CHR$ (65)"
LET EXPECTED$ = "A"
LET ACTUAL$ = CHR$(65)
GOSUB CheckResult

LET TEST_NAME$ = "ASCII ASC (A)"
LET EXPECTED$ = "65"
LET ACTUAL$ = STR$(ASC("A"))
GOSUB CheckResult

' ==================================================
' 4. LOGIQUE BOOLEENNE & BITWISE
' ==================================================
LET TEST_NAME$ = "Logique (TRUE AND FALSE)"
LET EXPECTED$ = "FALSE"
IF (TRUE AND FALSE) THEN LET ACTUAL$ = "TRUE" ELSE LET ACTUAL$ = "FALSE"
GOSUB CheckResult

LET TEST_NAME$ = "Logique (NOT FALSE)"
LET EXPECTED$ = "TRUE"
IF NOT FALSE THEN LET ACTUAL$ = "TRUE" ELSE LET ACTUAL$ = "FALSE"
GOSUB CheckResult

LET TEST_NAME$ = "Bitwise AND (12 AND 10)"
LET EXPECTED$ = "8"
LET ACTUAL$ = STR$(12 AND 10)
GOSUB CheckResult

LET TEST_NAME$ = "Comparaison chaines (A < B)"
LET EXPECTED$ = "TRUE"
IF "A" < "B" THEN LET ACTUAL$ = "TRUE" ELSE LET ACTUAL$ = "FALSE"
GOSUB CheckResult

' ==================================================
' 5. STRUCTURES DE CONTROLE
' ==================================================
LET TEST_NAME$ = "Boucle FOR...STEP (1 TO 5 STEP 2)"
LET S = 0
FOR I = 1 TO 5 STEP 2
  LET S = S + I
NEXT I
LET EXPECTED$ = "9" ' 1 + 3 + 5 = 9
LET ACTUAL$ = STR$(S)
GOSUB CheckResult

LET TEST_NAME$ = "Boucle WHILE et IF/ELSEIF multi-branches"
LET W = 0
LET I = 0
WHILE I < 3
  IF I = 0 THEN
    LET W = W + 1
  ELSEIF I = 1 THEN
    LET W = W + 10
  ELSE
    LET W = W + 100
  END IF
  LET I = I + 1
WEND
LET EXPECTED$ = "111"
LET ACTUAL$ = STR$(W)
GOSUB CheckResult

LET TEST_NAME$ = "Boucle REPEAT et Echappement BREAK"
LET R = 0
LET I = 0
REPEAT
  LET R = R + 1
  IF R = 3 THEN BREAK
  LET I = I + 1
UNTIL I >= 10
LET EXPECTED$ = "3"
LET ACTUAL$ = STR$(R)
GOSUB CheckResult

' ==================================================
' 6. TABLEAUX (ARRAYS 3D)
' ==================================================
LET TEST_NAME$ = "Tableaux multidimensionnels"
DIM TAB(2, 2, 2)
LET TAB(1, 1, 1) = 42
LET EXPECTED$ = "84"
LET ACTUAL$ = STR$(TAB(1, 1, 1) * 2)
GOSUB CheckResult

' ==================================================
' 7. E/S FICHIERS (VFS)
' ==================================================
LET TEST_NAME$ = "Fichiers (OPEN, PRINT#, INPUT#, CLOSE)"
OPEN "test_tmp.txt" FOR OUTPUT AS #1
PRINT #1, "LIGNE_TEST_123"
CLOSE #1

OPEN "test_tmp.txt" FOR INPUT AS #1
INPUT #1, L$
CLOSE #1

LET EXPECTED$ = "LIGNE_TEST_123"
LET ACTUAL$ = L$
GOSUB CheckResult

' ==================================================
' 8. TEMPS SYSTEME
' ==================================================
LET TEST_NAME$ = "Temps (SLEEP 100 & TIMER)"
LET T1 = TIMER
SLEEP 100
LET T2 = TIMER
LET DIFF = T2 - T1
LET EXPECTED$ = "TRUE"
' Tolérance de 10ms pour la précision de l'OS
IF DIFF >= 90 THEN LET ACTUAL$ = "TRUE" ELSE LET ACTUAL$ = "FALSE"
GOSUB CheckResult

' ==================================================
' BILAN FINAL
' ==================================================
PRINT "=================================================="
PRINT "                  SCORE FINAL                     "
PRINT "=================================================="
PRINT " SUCCES : "; SCORE_PASS
PRINT " ECHECS : "; SCORE_FAIL
PRINT " TOTAL  : "; SCORE_PASS + SCORE_FAIL
PRINT "=================================================="
IF SCORE_FAIL = 0 THEN
  PRINT " > EVALUATION : SYSTEME 100% OPERATIONNEL"
ELSE
  PRINT " > EVALUATION : DEFAILLANCES DETECTEES"
END IF
PRINT "=================================================="
END

' ==================================================
' SOUS-ROUTINE DE VALIDATION (ASSERTION)
' ==================================================
CheckResult:
  PRINT "TEST : "; TEST_NAME$
  PRINT "  Attendu : "; EXPECTED$
  PRINT "  Obtenu  : "; ACTUAL$
  IF EXPECTED$ = ACTUAL$ THEN
    PRINT "  -> [ OK ]"
    LET SCORE_PASS = SCORE_PASS + 1
  ELSE
    PRINT "  -> [ ECHEC ]"
    LET SCORE_FAIL = SCORE_FAIL + 1
  END IF
  PRINT "--------------------------------------------------"
  RETURN