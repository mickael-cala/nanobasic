PRINT "=== TEST E/S FICHIERS ==="
PRINT "1. Ecriture initiale (OUTPUT)"
OPEN "test_data.txt" FOR OUTPUT AS #1
PRINT #1, "Ligne 1 : Bonjour NanoBasic"
PRINT #1, "Ligne 2 : Test des fichiers"
CLOSE #1

PRINT "2. Ajout de donnees (APPEND)"
OPEN "test_data.txt" FOR APPEND AS #2
PRINT #2, "Ligne 3 : Ajout reussi !"
CLOSE #2

PRINT "3. Lecture du fichier (INPUT) et test EOF"
OPEN "test_data.txt" FOR INPUT AS #1
WHILE NOT EOF(1)
  INPUT #1, LIGNE$
  PRINT "Lu : "; LIGNE$
ENDWHILE
CLOSE #1

PRINT "=== FIN DU TEST FICHIERS ==="
END