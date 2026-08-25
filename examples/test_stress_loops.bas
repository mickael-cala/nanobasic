PRINT "=== STRESS TEST : BOUCLES IMBRIQUEES ==="
LET COMPTEUR = 0

FOR I = 1 TO 10
  LET J = 1
  WHILE J <= 10
    LET K = 10
    REPEAT
      LET COMPTEUR = COMPTEUR + 1
      IF COMPTEUR = 500 THEN
        PRINT "Break profond declenche !"
        BREAK ' Sort du REPEAT
      END IF
      LET K = K - 1
    UNTIL K <= 0
    LET J = J + 1
  WEND
NEXT I

PRINT "Compteur final (attendu 1000) : "; COMPTEUR
PRINT "=== OK ==="
END