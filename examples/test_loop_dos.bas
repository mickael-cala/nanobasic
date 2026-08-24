PRINT "=== TEST DU WATCHDOG ANTI-BOUCLE INFINIE ==="
LET C = 0
10 LET C = C + 1
GOTO 10
PRINT "Ce message ne doit jamais s'afficher"