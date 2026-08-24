PRINT "=== STRESS TEST : MEMOIRE & TABLEAUX ==="
' Allocation massive : 10 x 10 x 10 = 1000 slots (doit passer sans fuite)
DIM MATRICE(9, 9, 9)

LET MATRICE(0, 0, 0) = "DEBUT"
LET MATRICE(5, 5, 5) = 3.14159
LET MATRICE(9, 9, 9) = "FIN"

PRINT "Lecture (0,0,0) : "; MATRICE(0, 0, 0)
PRINT "Lecture (5,5,5) : "; MATRICE(5, 5, 5)
PRINT "Lecture (9,9,9) : "; MATRICE(9, 9, 9)

' Test de concaténation massive (stress de l'arène string)
LET S$ = "A"
FOR I = 1 TO 10
  LET S$ = S$ + S$
NEXT I
PRINT "Longueur chaine finale (attendu 1024) : "; LEN(S$)

PRINT "=== OK ==="
END