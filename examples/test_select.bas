PRINT "=== TEST SELECT CASE ==="

FOR I = 1 TO 6
  PRINT "Test valeur "; I; " : ";
  
  SELECT CASE I
    CASE 1
      PRINT "C'est un UN"
    CASE 2, 3
      PRINT "C'est DEUX ou TROIS"
    CASE 5
      PRINT "C'est CINQ"
    CASE ELSE
      PRINT "Valeur non geree (4 ou 6)"
  END SELECT
NEXT I

PRINT "=== FIN DU TEST ==="
END