# Journal des modifications (Changelog)

Toutes les modifications notables apportées à NanoBasic sont documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/), et ce projet respecte le [Semantic Versioning](https://semver.org/lang/fr/).

## [1.1.0-dev] - 2026-08-25

### Ajouté
- **Programmation structurée & Fonctions utilisateur** :
  - Définition et appel de procédures (`SUB...END SUB`) et de fonctions retournant une valeur (`FUNCTION...END FUNCTION`) avec l'instruction `CALL`.
  - Portée locale étanche des variables avec pile d'environnements chaînés (`sym_stack` jusqu'à 512 niveaux).
  - Prise en charge complète de la récursivité (validée sur le calcul de factorielle et la suite de Fibonacci).
  - Mécanisme de *Context Swap* temporaire pour l'exécution des corps de fonctions avec restauration du compteur ordinal (`pc`).
- **Structure conditionnelle multi-branches** :
  - `SELECT CASE ... CASE ... CASE ELSE ... END SELECT` avec support de listes de valeurs par branche (`CASE 1, 2, 3`) et comparaison polymorphique (entiers, réels, chaînes).
- **Système de fichiers virtuel (VFS Sandboxing)** :
  - Gestion indépendante des canaux d'E/S `#1` à `#8` (`OPEN`, `CLOSE`, `PRINT #`, `INPUT #`, fonction `EOF()`).
  - Callbacks enfichables (`vfs_open`, `vfs_close`, `vfs_print`, `vfs_input`, `vfs_eof`) pour isoler l'hôte ou rediriger les flux.
- **Pont d'extension FFI (Foreign Function Interface)** :
  - Enregistrement dynamique de fonctions natives Pascal exécutables depuis les scripts via `vm_register_ffi`.
- **Structures de contrôle supplémentaires** :
  - Boucles `REPEAT...UNTIL` et `WHILE...WEND` (ou `END WHILE`).
  - Instructions d'interruption `BREAK` et `EXIT` (avec variantes `EXIT FOR`, `EXIT WHILE`, `EXIT REPEAT`).
- **Tableaux multidimensionnels** :
  - Déclaration et indexation de tableaux de 1 à 3 dimensions (`DIM arr(x, y, z)`).
- **Bibliothèque intrinsèque étendue** :
  - Mathématiques : `ABS`, `INT`, `SQR`, `RND`, `SIN`, `COS`, `TAN`.
  - Manipulation de chaînes : `LEFT$`, `RIGHT$`, `MID$`, `CHR$`, `ASC`, `STR$`, `LEN`.
  - Système : `TIMER()` (millisecondes) et `SLEEP`.
  - Opérateurs logiques / bitwise : `AND`, `OR`, `NOT`, `XOR`.
  - Opérateur exponentiation (`^`).
- **Banc de validation** :
  - Suite de tests d'endurance `test_torture_master.bas` (15 scénarios limites validés à 100 %).

### Modifié
- **Standardisation syntaxique stricte** :
  - Parenthèses obligatoires pour l'ensemble des fonctions (`TIMER()`, `RND()`, fonctions FFI et utilisateur), supprimant toute collision avec les noms de variables locales ou globales.
- **Conversion numérique robuste** :
  - Réécriture du moteur d'analyse de `VAL(str$)` avec parseur progressif interrompant la lecture au premier caractère non numérique, conformément au standard BASIC.
- **Architecture de la machine virtuelle** :
  - Découplage strict entre la pile d'appels de sous-programmes (`call_depth`) et la pile d'évaluation des expressions de l'AST (`expr_depth`).
  - Correction du masquage de nœud dans `N_IF_BLOCK` qui tronquait les évaluations récursives imbriquées.
- **Gestion mémoire** :
  - Remplacement des allocations dynamiques standard par un `Arena Allocator` contigu de 16 Mo, éliminant les fuites mémoire sur le tas (*Heap*).

## [1.0.0] - 2026-08-24

### Ajouté
- Interpréteur BASIC minimaliste basé sur un parcours d'arbre AST (*Tree-Walk*).
- Analyse lexicale (scanner), syntaxique (parser) et exécution (VM).
- Support des instructions impératives de base : `PRINT`, `INPUT`, `IF...THEN...ELSE`, `FOR...NEXT`, `GOSUB/RETURN`, `GOTO`, `REM`, `END`.
- Gestion des variables entières 64 bits et réelles double précision.
- Opérateurs arithmétiques standards et comparaisons relationnelles.
- Environnement REPL interactif avec gestion de lignes numérotées et exécution directe de fichiers `.bas`.
- Structure de projet avec exemples et Makefile Free Pascal.