PRINT "=== STRESS TEST : MATHS & TYPES ==="
LET A = 10
LET B = 3
LET C = 2.5
LET D = TRUE

' Coercition et priorite des operateurs
LET RES = (A + B) * C - (A / B) + (D AND TRUE)
PRINT "Resultat complexe : "; RES

' Division par zero (doit avertir mais survivre et donner 0)
LET Z = A / 0
PRINT "Division par zero : "; Z

' Fonctions integrees imbriquees
LET STR_VAL = "123.45"
LET CALC = INT(ABS(SIN(VAL(STR_VAL)) * 100)) + LEN(STR_VAL)
PRINT "Calcul imbrique   : "; CALC

PRINT "=== OK ==="
END