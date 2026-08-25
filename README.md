# NanoBasic

**NanoBasic** est un interpréteur BASIC compact, moderne et performant, écrit en **Free Pascal** (`ObjFPC`). Conçu sur une architecture découplée avec **Arbre Syntaxique Abstrait (AST)**, allocateur mémoire par arène et machine virtuelle d'exécution, il allie la simplicité du BASIC historique à des structures de contrôle modernes, une interface de fonctions externes (**FFI**) et une API complète d'embarquement hôte.

---

## Fonctionnalités Clés

* **Typage polymorphe étendu :**
  * Entiers 64 bits (`Int64`), flottants (`Double`), chaînes (`PChar`, allouées dans l'arène), booléens (`Boolean`).
  * Tableaux multidimensionnels de 1 à 3 dimensions via `DIM nom(d1, d2, d3)` (validation des dimensions ; contrôle des bornes en cours — cf. ROADMAP Phase 2.1).

* **Structures de contrôle modernes & vintage :**
  * `FOR ... TO ... STEP ... NEXT [var]`
  * `WHILE ... WEND` (tolère `END WHILE` et `ENDWHILE`)
  * `REPEAT ... UNTIL <cond>`
  * `IF ... THEN ... ELSEIF ... ELSE ... END IF` (multi-lignes)
  * `IF cond THEN stmt [ELSE stmt]` (mono-ligne)
  * Interruption de boucle : `BREAK` et `EXIT [FOR|WHILE|REPEAT]`
  * Sauts par numéros de ligne ou **labels textuels** (`mon_label:`, `GOTO`, `GOSUB`, `RETURN`).

* **Opérateurs complets :**
  * Arithmétique : `+`, `-`, `*`, `/`, `^` (puissance)
  * Comparaisons : `=`, `<>`, `<`, `>`, `<=`, `>=`
  * Logique & Bitwise : `AND`, `OR`, `NOT`, `XOR`

* **Entrées/Sorties Fichiers (Canaux `#1` à `#8`) :**
  * `OPEN <fichier> FOR <INPUT|OUTPUT|APPEND> AS #N`
  * `CLOSE [#N]`
  * `PRINT #N, ...`
  * `INPUT #N, var`
  * Fonction intrinsèque `EOF(N)`

* **Fonctions intégrées standard :**
  * Mathématiques : `ABS`, `INT`, `SQR`, `SIN`, `COS`, `TAN`, `RND`
  * Chaînes : `LEN`, `LEFT$`, `RIGHT$`, `MID$`, `CHR$`, `ASC`, `STR$`, `VAL`
  * Temps & Système : `TIMER()` (millisecondes) et instruction `SLEEP <ms>`

* **Sécurité & Robustesse :**
  * Allocateur d'arène borné (plafond configurable, défaut : 16 Mo) pour zéro fragmentation.
  * Watchdog d'instructions (`DEFAULT_MAX_INSTRUCTIONS`) pour stopper les boucles infinies.

* **Diagnostics & CLI :**
  * Localisation précise des erreurs `[Ligne, Col]` avec affichage de la ligne source et curseur `^`.
  * Mode linter statique `--check` sans exécution.
  * REPL interactif avec commandes `LOAD`, `SAVE`, `RUN`, `CHECK`, `LIST`, `DIR`, `NEW`, `CLS`, `HELP` (`CLEAR` prévu — cf. ROADMAP Phase 2.4).

* **API d'embarquement (Host Interop & FFI) :**
  * Callbacks configurables `on_print` et `on_input`.
  * Fonctions d'injection/lecture de variables côté hôte (`vm_set_int`, `vm_get_str`, etc.).
  * Registre de fonctions externes **FFI** (`vm_register_ffi`) avec dispatch dynamique.

---

## Architecture

Le moteur est découpé en 5 unités spécialisées :

* `src/nanotypes.pas`
  * Définitions des types de valeurs (`Value`)
  * Arène mémoire
  * Nœuds AST (`TNode`)
  * Tokens
  * Tables des symboles
  * Gestion des labels

* `src/nanolexer.pas`
  * Analyseur lexical rapide
  * Suivi précis `(Ligne, Col)`
  * Gestion des commentaires `'` et `REM`

* `src/nanoparser.pas`
  * Parseur descendant récursif
  * Construction de l'AST
  * Vérification des précédences
  * Validation statique des sauts

* `src/nanovm.pas`
  * Machine virtuelle Tree-Walk
  * Gestion des canaux de fichiers
  * Fonctions intégrées
  * FFI
  * Callbacks d'E/S

* `src/nanobasic.pas`
  * Point d'entrée CLI
  * REPL interactif
  * Gestion de `--check`, `--version`, `--help`

---

## Installation et Compilation

### Prérequis

* **Free Pascal Compiler** 3.2.0 ou supérieur recommandé.

### Compilation

Prérequis : **Free Pascal Compiler** 3.2.0 ou supérieur ; pour `make`, un GNU make avec shell POSIX (Linux, macOS, MSYS2).

```bash
# Depuis la racine du dépôt : compilation du binaire CLI (dans bin/)
fpc -O2 -Mobjfpc src/nanobasic.pas -obin/nanobasic

# Compilation des programmes d'intégration / exemples hôtes (depuis la racine)
fpc -O2 -Fu../src tests/test_host.pas
fpc -O2 -Fu../src tests/test_ffi.pas

# Ou via le makefile (recommandé) : lint + tests inclus
make
make check        # lint statique de tous les scripts de test
make test         # lint + exécution (stdin : /dev/null)
```

Sous Windows, le harnais batch équivalent est fourni : `tests\run_tests_exe.bat` puis `tests\run_tests_bas.bat`.

---

## Utilisation

### Mode Fichier direct

```bash
nanobasic.exe mon_script.bas
```

### Mode Linter (Vérification syntaxique statique)

```bash
nanobasic.exe --check mon_script.bas
```

### Mode Interactif (REPL)

```bash
nanobasic.exe
```

---

## Exemple de Script BASIC Moderne

```basic
PRINT "=== AUTOMATION SCRIPT ==="

LET DEBUT = TIMER()

DIM VALEURS(5)

FOR I = 0 TO 5
  LET VALEURS(I) = I * 10
NEXT I

LET C = 1

WHILE C <= 3
  IF (C AND 1) <> 0 THEN
    PRINT "Cycle impair #"; C; " - Valeur : "; VALEURS(C)
  ELSE
    PRINT "Cycle pair   #"; C
  END IF

  LET C = C + 1
WEND

LET FIN = TIMER()

PRINT "Temps execution : "; FIN - DEBUT; " ms"

END
```

---

## Embarquement dans un projet Pascal (Exemple Host API & FFI)

```pascal
uses
  SysUtils, NanoTypes, NanoLexer, NanoParser, NanoVM;

function MonPiloteMateriel(vm: PVM; const args: array of Value): Value;
begin
  WriteLn('[HARDWARE] Action declenchee avec valeur : ', to_int(args[0]));
  Result := MakeInt(1);
end;

var
  arena: TArena;
  symTab: TSymTab;
  P: TParser;
  vm: TVM;

begin
  FillChar(arena, SizeOf(arena), 0);
  FillChar(symTab, SizeOf(symTab), 0);

  symTab.a := @arena;

  parser_init(P, @arena, 'CALL PILOTE(42)');
  parse_program(@P);

  if P.error = 0 then
  begin
    vm_init(vm, @symTab, P.stmts, @P.labels);
    vm_register_ffi(vm, 'PILOTE', @MonPiloteMateriel);
    vm_run(vm);
  end;

  arena_free_all(@arena);
end.
```

---

## Tests

Deux harnais de test sont fournis (Windows : batch ; Unix : makefile) :

### `tests\run_tests_exe.bat`

* Compile le CLI (`bin\nanobasic.exe`) puis les binaires hôte `test_host` / `test_ffi` (unités résolues via `-Fu`).
* Exécute les tests de conformité hôte/FFI.

### `tests\run_tests_bas.bat`

* Valide statiquement via `--check` l'ensemble des scripts `examples\test_*.bas`.
* Exécute chaque script (entrée redirigée vers `nul` pour éviter tout blocage sur `INPUT`).
* Gère le cas négatif `test_bad.bas` : son rejet par le linter est un succès attendu.

### Makefile (Unix / MSYS2)

* `make check` : lint statique de tous les scripts de test.
* `make test` : lint + exécution (stdin redirigé vers `/dev/null`).
* `make test-negative` : vérifie que `test_bad.bas` est bien rejeté par le linter.

> La mise en place d'une intégration continue (GitHub Actions) est prévue — cf. ROADMAP.

---

## Licence

Ce projet est distribué sous double licence :

### GNU Affero General Public License v3.0 (AGPL-3.0)

Pour les projets open-source.

### Licence commerciale

Disponible sur demande pour toute intégration propriétaire sans les obligations de l'AGPL.

Consultez le fichier `LICENSE.txt` pour plus de détails.

---

## Auteur 

**Mickaël Cala**
