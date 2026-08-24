PRINT "=== TEST TABLEAU 3D (TENSEUR 2x2x2) ==="
DIM V(1, 1, 1)

FOR X = 0 TO 1
  FOR Y = 0 TO 1
    FOR Z = 0 TO 1
      V(X, Y, Z) = (X * 100) + (Y * 10) + Z
    NEXT Z
  NEXT Y
NEXT X

PRINT "V(0, 0, 0) = "; V(0, 0, 0)
PRINT "V(0, 1, 1) = "; V(0, 1, 1)
PRINT "V(1, 0, 1) = "; V(1, 0, 1)
PRINT "V(1, 1, 1) = "; V(1, 1, 1)
PRINT "=== FIN DU TEST 3D ==="
END