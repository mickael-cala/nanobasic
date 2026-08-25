# 🗺️ FEUILLE DE ROUTE OFFICIELLE : NANOBASIC V1.0

> Architecture : Interpréteur Tree-Walk pur (sans bytecode ni VM à pile)
> Mémoire : Arena Allocator déterministe (sans ramasse-miettes / Garbage Collector)
> Modèle de licence : Double licence (Cœur AGPLv3 / Extensions Commerciales)

---

## 📌 Phase 1 : Les Fondations & Structuration de Base [ ✅ TERMINÉ ]
- [x] Allocateur mémoire par blocs contigus (Arena Allocator jusqu'à 16 Mo, zéro Heap leak).
- [x] Typage dynamique et coercition : T_INT (64-bit), T_NUM (Double), T_STR (PChar), T_BOOL, T_ARR (jusqu'à 3D).
- [x] Structures de contrôle de base :
  - IF ... THEN ... ELSEIF ... ELSE ... ENDIF (mono et multi-lignes).
  - Boucles : WHILE ... WEND, FOR ... TO ... STEP ... NEXT, REPEAT ... UNTIL.
  - Sauts : GOTO, GOSUB ... RETURN, BREAK / EXIT.
- [x] Procédures et Fonctions structurées :
  - SUB ... END SUB et FUNCTION ... END FUNCTION (avec CALL).
  - Environnements locaux empilables (sym_stack) et récursivité profonde.
  - Context Swap pour l'exécution fluide des blocs et boucles internes.
- [x] Standardisation syntaxique :
  - Parenthèses strictes et obligatoires pour toutes les fonctions (ex. TIMER(), RND()).
  - Extraction progressive et conforme pour VAL(str$).
- [x] Sélection multi-branches :
  - SELECT CASE ... CASE v1, v2 ... CASE ELSE ... END SELECT.

---

## 📌 Phase 2 : Sécurité Critique & Durcissement Mémoire [ 🔄 EN COURS / IMMÉDIAT ]
- [ ] 2.1 Bounds Checking strict :
  - Contrôle systématique des indices dans N_ARRAY_GET et N_ARRAY_SET (0 <= index <= limite).
  - Interruption propre avec message d'erreur runtime au lieu d'une corruption mémoire de l'Arena.
- [ ] 2.2 Durcissement du Parser :
  - Arrêt immédiat de l'analyse dès la première erreur syntaxique (pas de génération d'AST corrompu).
- [ ] 2.3 Sécurisation des allocations :
  - Validation systématique du retour nil sur tous les appels arena_alloc.
- [ ] 2.4 Ergonomie & Stabilité du REPL :
  - Implémentation réelle de la commande CLEAR (nettoyage de la table des symboles active).
  - Prise en charge des chemins avec espaces entre guillemets (LOAD "mon fichier.bas").
  - Amélioration de la portabilité de CLS (séquences terminales ANSI).

---

## 📌 Phase 3 : Types Procéduraux & Modularité [ Cœur AGPLv3 ]
- [ ] 3.1 Enregistrements / Structures (C-like) :
  - Déclaration : TYPE Point : x AS INTEGER : y AS INTEGER : END TYPE.
  - Accès direct par point : p.x = 10.
- [ ] 3.2 Constantes nommées (CONST) :
  - Déclaration et substitution dès le parsing (CONST PI = 3.14159).
- [ ] 3.3 Passage d'arguments avancé :
  - Prise en charge explicite de BYVAL (par défaut) et BYREF dans les signatures SUB / FUNCTION.
- [ ] 3.4 Sorties anticipées de routines :
  - Instructions EXIT SUB et EXIT FUNCTION.
- [ ] 3.5 Modularité & Inclusions :
  - Directives #INCLUDE "chemin/fichier.bas" et #INCLUDE_ONCE.
  - Détection automatique des dépendances circulaires et résolution des chemins relatifs.
- [ ] 3.6 Tableaux redimensionnables :
  - Instructions REDIM et REDIM PRESERVE.

---

## 📌 Phase 4 : Bibliothèques Standard & Collections par Handles

### A. Modules du Cœur Standard [ Licence AGPLv3 ]
- [ ] nano_string :
  - Fonctions : INSTR, UCASE$, LCASE$, TRIM$, LTRIM$, RTRIM$, REPLACE$, SPLIT, JOIN$, SPACE$, STRING$.
- [ ] nano_math :
  - Opérateurs et conversions : MOD, SHL, SHR, HEX$, OCT$, BIN$, LOG, EXP, ATN, FORMAT$.
- [ ] nano_collections (Gestion procédurale par descripteurs entiers) :
  - Listes dynamiques : LIST_CREATE(), LIST_ADD(), LIST_GET$(), LIST_COUNT(), LIST_FREE().
  - Piles (LIFO) & Files (FIFO) : STACK_PUSH(), STACK_POP(), QUEUE_PUSH(), QUEUE_POP$().
  - Dictionnaires (Key-Value) : MAP_SET(), MAP_GET$(), MAP_HAS(), MAP_COUNT(), MAP_FREE().
  - Registre de tracking interne pour libération automatique en fin de script / vm_reset.
- [ ] nano_time :
  - Fonctions : TICKS_MS(), TICKS_US(), DATETIME$().

### B. Modules Industriels & Embarqués [ Licence Commerciale ]
- [ ] nano_buffer :
  - Ring buffer circulaire (RING_CREATE, RING_WRITE, RING_READ$), accès PEEK et POKE virtualisés.
- [ ] nano_comm :
  - Communication matérielle et réseau : Port Série RS232/RS485, Sockets TCP/UDP, Client Modbus RTU/TCP.
- [ ] nano_crypto :
  - Hachage et sécurité : CRC32, SHA256, HMAC, AES-128/256.
- [ ] nano_db :
  - Moteurs de stockage embarqués : Connecteur natif SQLite et KV-Store binaire.

---

## 📌 Phase 5 : Robustesse d'Exécution & Sandboxing Système
- [ ] 5.1 Gestion structurée des erreurs runtime [ Cœur AGPLv3 ] :
  - Blocs TRY ... CATCH ... FINALLY ... END TRY (libération garantie des ressources).
- [ ] 5.2 Confinement VFS Sandbox [ Cœur AGPLv3 ] :
  - Restriction des accès fichiers (--sandbox <repertoire_racine>) avec blocage des traversées (anti Path Traversal ../).
- [ ] 5.3 Recyclage mémoire REPL [ Cœur AGPLv3 ] :
  - Implémentation de arena_reset pour vider la mémoire de travail entre deux exécutions interactives.
- [ ] 5.4 API d'Instrumentation & Débogage [ Licence Commerciale ] :
  - Hooks hôtes : vm_step(), vm_set_breakpoint(), vm_dump_symtab(), vm_inspect_var() pour IHM/IDE de supervision.

---

## 📌 Phase 6 : Documentation, Spécification & Assurance Qualité
- [ ] 6.1 Spécification formelle de la grammaire (BNF / EBNF versionnée).
- [ ] 6.2 Manuel de référence complet du langage et guide d'intégration hôte Pascal.
- [ ] 6.3 Bancs de tests de torture automatisés, mesures de charge et profils mémoire.