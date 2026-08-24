PRINT "=== 1. TEST TABLEAU 1D ==="
DIM A(5)

FOR I = 0 TO 5
  A(I) = I * 10
NEXT I

PRINT "Contenu de A : ";
FOR I = 0 TO 5
  PRINT A(I); " ";
NEXT I
PRINT ""

PRINT "=== 2. TEST TABLEAU 2D (MATRICE) ==="
DIM M(3, 3)

FOR R = 0 TO 3
  FOR C = 0 TO 3
    M(R, C) = (R + 1) * (C + 1)
  NEXT C
NEXT R

PRINT "Table de multiplication 4x4 (0 a 3) :"
FOR R = 0 TO 3
  FOR C = 0 TO 3
    PRINT M(R, C); "	";
  NEXT C
  PRINT ""
NEXT R

PRINT "=== 3. TEST TABLEAU DE CHAINES ==="
DIM NOMS$(2)
NOMS$(0) = "Nano"
NOMS$(1) = "Basic"
NOMS$(2) = "2026"

PRINT "Assemblage : "; NOMS$(0); " "; NOMS$(1); " "; NOMS$(2)

PRINT "=== 4. TEST DU CONTROLE DES BORNES (BOUNDS CHECKING) ==="
PRINT "Tentative d'acces a A(10) (doit lever une Runtime Error propre) :"
PRINT A(10)

PRINT "Ce message ne doit pas apparaitre."
END