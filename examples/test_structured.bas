PRINT "=== 1. TEST BOUCLE WHILE ... WEND ==="
LET I = 1
WHILE I <= 3
  PRINT "WHILE Tour #"; I
  LET I = I + 1
WEND

PRINT "=== 2. TEST REPEAT ... UNTIL ==="
LET C = 10
REPEAT
  PRINT "REPEAT Compte a rebours : "; C
  LET C = C - 2
UNTIL C <= 4

PRINT "=== 3. TEST IF MULTI-LIGNES AVEC ELSEIF & ELSE ==="
LET NOTE = 15

IF NOTE >= 16 THEN
  PRINT "Mention : Tres Bien"
ELSEIF NOTE >= 14 THEN
  PRINT "Mention : Bien"
ELSEIF NOTE >= 12 THEN
  PRINT "Mention : Assez Bien"
ELSE
  PRINT "Mention : Passable"
END IF

PRINT "=== 4. TEST BREAK / EXIT DANS UNE BOUCLE ==="
FOR K = 1 TO 10
  IF K = 4 THEN
    PRINT "Interruption du FOR a K = 4"
    EXIT FOR
  END IF
  PRINT "K = "; K
NEXT K

PRINT "=== 5. TEST LABELS TEXTUELS ==="
GOTO SuiteTest:

PRINT "Ce texte saute ne doit jamais apparaitre"

SuiteTest:
PRINT "Saut vers label textuel 'SuiteTest:' reussi !"
PRINT "=== FIN DES TESTS STRUCTURES ==="
END