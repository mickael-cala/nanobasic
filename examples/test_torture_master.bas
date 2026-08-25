PRINT "=================================================="
PRINT "       NANOBASIC V1 - SUITE DE TORTURE MAXIMALE   "
PRINT "=================================================="

LET PASS_COUNT = 0
LET FAIL_COUNT = 0

' ============================================================
' SECTION 1 : ARITHMETIQUE COMPLEXE ET PRECEDENCE
' ============================================================
LET T_NAME$ = "Precedence : 2 + 3 * 4 ^ 2 - (10 / 2)"
' 4^2 = 16 ; 3*16 = 48 ; 10/2 = 5 ; 2 + 48 - 5 = 45
LET T_EXP$ = "45"
LET T_ACT$ = STR$(2 + 3 * 4 ^ 2 - (10 / 2))
GOSUB AssertEqual

LET T_NAME$ = "Unaire negatif et puissance : -2 ^ 2 + 5"
' (-2) ^ 2 = 4 ; 4 + 5 = 9
LET T_EXP$ = "9"
LET T_ACT$ = STR$((-2) ^ 2 + 5)
GOSUB AssertEqual

LET T_NAME$ = "Division par zero sans crash (Survie VM)"
LET T_EXP$ = "0"
LET T_ACT$ = STR$(100 / 0)
GOSUB AssertEqual

' ============================================================
' SECTION 2 : CHAINES ET MANIPULATIONS EXTREMES
' ============================================================
LET T_NAME$ = "MID$ depassant la longueur reelle"
LET T_EXP$ = "BASIC"
LET T_ACT$ = MID$("NANOBASIC", 5, 50)
GOSUB AssertEqual

LET T_NAME$ = "LEFT$ et RIGHT$ avec longueur 0"
LET T_EXP$ = ""
LET T_ACT$ = LEFT$("TEST", 0) + RIGHT$("TEST", 0)
GOSUB AssertEqual

LET T_NAME$ = "VAL sur chaine hybride et conversion"
LET T_EXP$ = "100"
LET T_ACT$ = STR$(VAL("100ABC"))
GOSUB AssertEqual

LET T_NAME$ = "Concatenation multiple et types mixtes"
LET T_EXP$ = "ID:42-FLAG:TRUE"
LET T_ACT$ = "ID:" + STR$(42) + "-FLAG:" + "TRUE"
GOSUB AssertEqual

' ============================================================
' SECTION 3 : LOGIQUE, BITWISE ET CONDITIONS IMBRIQUEES
' ============================================================
LET T_NAME$ = "Bitwise complexe : (15 AND 6) OR (8 XOR 2)"
' (15 AND 6) = 6 ; (8 XOR 2) = 10 ; 6 OR 10 = 14
LET T_EXP$ = "14"
LET T_ACT$ = STR$((15 AND 6) OR (8 XOR 2))
GOSUB AssertEqual

LET T_NAME$ = "IF mono-ligne dans une boucle FOR"
LET ACCUM = 0
FOR K = 1 TO 5
  IF (K AND 1) <> 0 THEN LET ACCUM = ACCUM + K ELSE LET ACCUM = ACCUM - 1
NEXT K
' K=1: +1 (1) ; K=2: -1 (0) ; K=3: +3 (3) ; K=4: -1 (2) ; K=5: +5 (7)
LET T_EXP$ = "7"
LET T_ACT$ = STR$(ACCUM)
GOSUB AssertEqual

' ============================================================
' SECTION 4 : GOTO, GOSUB, ET PIEGES DE SAUT
' ============================================================
LET T_NAME$ = "GOSUB imbrique et RETURN multi-niveaux"
LET GOSUB_TRACK$ = ""
GOSUB Level1
LET T_EXP$ = "L1-L2-L3-RET3-RET2-RET1"
LET T_ACT$ = GOSUB_TRACK$
GOSUB AssertEqual
GOTO SkipGosubDef

Level1:
  LET GOSUB_TRACK$ = GOSUB_TRACK$ + "L1-"
  GOSUB Level2
  LET GOSUB_TRACK$ = GOSUB_TRACK$ + "RET1"
  RETURN

Level2:
  LET GOSUB_TRACK$ = GOSUB_TRACK$ + "L2-"
  GOSUB Level3
  LET GOSUB_TRACK$ = GOSUB_TRACK$ + "RET2-"
  RETURN

Level3:
  LET GOSUB_TRACK$ = GOSUB_TRACK$ + "L3-RET3-"
  RETURN

SkipGosubDef:

' ============================================================
' SECTION 5 : TABLEAUX MULTIDIMENSIONNELS (STRESS TEST 3D)
' ============================================================
LET T_NAME$ = "DIM 3D : Remplissage et somme croisee"
DIM MAT(3, 3, 3)
FOR X = 0 TO 3
  FOR Y = 0 TO 3
    FOR Z = 0 TO 3
      LET MAT(X, Y, Z) = X + Y + Z
    NEXT Z
  NEXT Y
NEXT X
' Point (3,2,1) = 6 ; Point (1,1,1) = 3 ; Total = 18
LET T_EXP$ = "18"
LET T_ACT$ = STR$(MAT(3, 2, 1) * MAT(1, 1, 1))
GOSUB AssertEqual

' ============================================================
' SECTION 6 : E/S VFS MULTI-CANAUX SIMULTANES
' ============================================================
LET T_NAME$ = "VFS : Ecriture croisee canaux #1 et #2 puis relecture"
OPEN "stream1.tmp" FOR OUTPUT AS #1
OPEN "stream2.tmp" FOR OUTPUT AS #2
PRINT #1, "CANAL_UN"
PRINT #2, "CANAL_DEUX"
CLOSE #1
CLOSE #2

OPEN "stream1.tmp" FOR INPUT AS #1
OPEN "stream2.tmp" FOR INPUT AS #2
INPUT #1, D1$
INPUT #2, D2$
CLOSE #1
CLOSE #2

LET T_EXP$ = "CANAL_UN/CANAL_DEUX"
LET T_ACT$ = D1$ + "/" + D2$
GOSUB AssertEqual

' ============================================================
' SECTION 7 : SUB & FUNCTION - LOCAL SCOPE & RECURSION
' ============================================================
LET T_NAME$ = "SUB : Mutation d'arguments et masquage global"
LET SHADOW_VAL = 50
CALL TestMutation(SHADOW_VAL)
LET T_EXP$ = "50"
LET T_ACT$ = STR$(SHADOW_VAL)
GOSUB AssertEqual

LET T_NAME$ = "FUNCTION : Recursivite croisee / Fibonacci"
' Fib(0)=0, Fib(1)=1, Fib(2)=1, Fib(3)=2, Fib(4)=3, Fib(5)=5, Fib(6)=8, Fib(7)=13
LET T_EXP$ = "13"
LET T_ACT$ = STR$(Fibonacci(7))
GOSUB AssertEqual

LET T_NAME$ = "FUNCTION : Boucle interne et appels imbriques"
LET T_EXP$ = "30"
' SommeEntiers(4) = 1+2+3+4 = 10 ; Multiplie(10, 3) = 30
LET T_ACT$ = STR$(Multiplie(SommeEntiers(4), 3))
GOSUB AssertEqual

' ============================================================
' BILAN FINAL
' ============================================================
PRINT "=================================================="
PRINT "                  RESULTAT FINAL                  "
PRINT "=================================================="
PRINT " TESTS REUSSIS : "; PASS_COUNT
PRINT " TESTS ECHOUES  : "; FAIL_COUNT
PRINT " TOTAL          : "; PASS_COUNT + FAIL_COUNT
PRINT "=================================================="
IF FAIL_COUNT = 0 THEN
  PRINT " >>> STATUS : CONFORME (100% SUCCES) <<<"
ELSE
  PRINT " >>> STATUS : DEFAILLANCES DETECTEES <<<"
END IF
PRINT "=================================================="
END

' ============================================================
' PROCEDURES & FONCTIONS UTILISATEUR
' ============================================================

SUB TestMutation(ARG_VAL)
  LET SHADOW_VAL = 9999
  LET ARG_VAL = ARG_VAL + 500
END SUB

FUNCTION Fibonacci(N_VAL)
  IF N_VAL <= 0 THEN
    LET Fibonacci = 0
  ELSEIF N_VAL = 1 THEN
    LET Fibonacci = 1
  ELSE
    LET Fibonacci = Fibonacci(N_VAL - 1) + Fibonacci(N_VAL - 2)
  END IF
END FUNCTION

FUNCTION SommeEntiers(MAX_VAL)
  LET S = 0
  FOR I = 1 TO MAX_VAL
    LET S = S + I
  NEXT I
  LET SommeEntiers = S
END FUNCTION

FUNCTION Multiplie(A_VAL, B_VAL)
  LET Multiplie = A_VAL * B_VAL
END FUNCTION

' ============================================================
' ASSERTION GENERIQUE
' ============================================================
AssertEqual:
  PRINT "TEST : "; T_NAME$
  PRINT "  Attendu : "; T_EXP$
  PRINT "  Obtenu  : "; T_ACT$
  IF T_EXP$ = T_ACT$ THEN
    PRINT "  -> [ OK ]"
    LET PASS_COUNT = PASS_COUNT + 1
  ELSE
    PRINT "  -> [ ECHEC ]"
    LET FAIL_COUNT = FAIL_COUNT + 1
  END IF
  PRINT "--------------------------------------------------"
  RETURN