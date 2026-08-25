PRINT "=================================================="
PRINT "      TEST : PROCEDURES, FONCTIONS & SCOPE        "
PRINT "=================================================="

LET GLOBAL_VAR = 100
PRINT "Valeur globale au depart : "; GLOBAL_VAR
PRINT "--------------------------------------------------"

' 1. Test d'un SUB simple
PRINT "[TEST 1] Appel de SUB avec arguments :"
CALL MaProcedure("Bonjour NanoBasic", 3)
PRINT "--------------------------------------------------"

' 2. Test du Scope Local (Isolation)
PRINT "[TEST 2] Portee Locale (Local Scope) :"
CALL TestScope(50)
PRINT "De retour dans le programme principal..."
PRINT "Valeur de GLOBAL_VAR (doit etre 100) : "; GLOBAL_VAR
PRINT "--------------------------------------------------"

' 3. Test de FUNCTION (Calcul de retour)
PRINT "[TEST 3] Fonction avec valeur de retour :"
LET PRIX_HT = 200
LET TAXE = 20
LET PRIX_TTC = CalculerTTC(PRIX_HT, TAXE)
PRINT "Prix HT  : "; PRIX_HT
PRINT "Prix TTC : "; PRIX_TTC; " (Attendu: 240)"
PRINT "--------------------------------------------------"

' 4. Test Extreme : Recursivite
PRINT "[TEST 4] Recursivite (Factorielle) :"
LET N = 5
LET FACT = Factorielle(N)
PRINT "Factorielle de "; N; " = "; FACT; " (Attendu: 120)"

PRINT "=================================================="
PRINT "                  TEST TERMINE                    "
PRINT "=================================================="
END

' ============================================================
' DEFINITIONS DES SOUS-ROUTINES
' ============================================================

SUB MaProcedure(TEXTE$, FOIS)
  FOR I = 1 TO FOIS
    PRINT "  Iteration "; I; " -> "; TEXTE$
  NEXT I
END SUB

SUB TestScope(VALEUR)
  ' Lecture : On a acces a la variable globale depuis la procedure
  PRINT "  Lecture GLOBAL_VAR depuis SUB : "; GLOBAL_VAR
  
  ' Ecriture : Ceci va CREER une variable LOCALE masquant la globale
  LET GLOBAL_VAR = 999
  PRINT "  Variable GLOBAL_VAR locale modifiee a : "; GLOBAL_VAR
  
  ' Modification de l'argument (local uniquement)
  LET VALEUR = VALEUR * 2
  PRINT "  Argument VALEUR modifie en local a : "; VALEUR
END SUB

FUNCTION CalculerTTC(HT, TX)
  ' En BASIC, on affecte le resultat au nom de la fonction
  LET CalculerTTC = HT + (HT * TX / 100)
END FUNCTION

FUNCTION Factorielle(VAL)
  ' La fameuse epreuve de la recursivite
  IF VAL <= 1 THEN
    LET Factorielle = 1
  ELSE
    LET Factorielle = VAL * Factorielle(VAL - 1)
  END IF
END FUNCTION