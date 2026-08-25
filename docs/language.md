# Spécification du langage NanoBasic

> **Version documentée :** 1.1.0-dev — Document lié à la sémantique **réelle** du moteur
> (`src/nanotypes.pas`, `src/nanolexer.pas`, `src/nanoparser.pas`, `src/nanovm.pas`).
> Toute évolution du moteur doit maintenir ce document à jour.

## 1. Modèle d'exécution

NanoBasic est un interpréteur **Tree-Walk** : le source est tokenisé (lexer), transformé en
AST (parseur récursif descendant), puis exécuté directement par la VM en parcourant l'arbre.
Il n'y a ni bytecode, ni VM à pile.

- Mémoire : **arène** contiguë bornée à 16 Mio (`ARENA_MAX_BYTES`), zéro fragmentation, libération globale en fin d'exécution.
- Garde-fous : **watchdog d'instructions** (`DEFAULT_MAX_INSTRUCTIONS` = 10 000 000) qui stoppe les boucles infinies ; profondeurs bornées (voir § 10).
- Sécurité : les E/S fichiers passent par une **VFS enfichable** (`vfs_open`, `vfs_close`, `vfs_print`, `vfs_input`, `vfs_eof`). Le CLI active la VFS standard ; un hôte peut ne rien brancher (sandbox stricte).

## 2. Types & littéraux

| Type | Nom interne | Représentation | Littéral |
|---|---|---|---|
| Entier | `T_INT` | `Int64` | `42`, `-7` (pas de point) |
| Flottant | `T_NUM` | `Double` | `3.14`, `.5`, `1e3`, `1.5e-2` |
| Chaîne | `T_STR` | `PChar` (allouée dans l'arène) | `"abc"` |
| Booléen | `T_BOOL` | `Boolean` | `TRUE`, `FALSE` |
| Tableau | `T_ARR` | pointeur `TArrayData` | via `DIM` |
| Nul | `T_NIL` | — | (interne uniquement) |

- Identifiants : lettres, chiffres, `_`, `$`, `%` ; **insensibles à la casse** (tout est
  converti en majuscules) ; longueur max 63 caractères.
- Chaînes : échappements `\n` (saut de ligne), `\t` (tabulation), `\x` → `x` ; guillemet
  échappé par `""`. Les chaînes sont stockées en octets bruts.
- **Variable non définie = 0 entier** (`T_INT`). Il n'y a pas d'erreur « variable inconnue ».

## 3. Coercitions (conversions implicites)

`to_bool(v)` : booléen → lui-même ; entier → `v ≠ 0` ; flottant → `v ≠ 0.0` ;
chaîne → non vide ; sinon `FALSE`.

`to_int(v)` : entier → lui-même ; flottant → `Trunc` (troncature vers zéro) ; booléen → 0/1 ;
chaîne → `StrToInt64Def(s, 0)` (**0 si la chaîne n'est pas un entier**).

`to_num(v)` : flottant → lui-même ; entier → lui-même ; booléen → 0/1 ;
chaîne → `StrToFloatDef(s, 0.0)`.

> ⚠️ Pièges découlant de ces règles : `"abc" = 0` vaut `TRUE` ; une chaîne non numérique
> `VAL`-ée vaut 0.

## 4. Opérateurs & expressions

Précédence (croissante) : `OR`/`XOR` (1) < `AND` (2) < comparaisons (3) < `+`/`-` (4) <
`*`/`/` (5) < `^` (6). Unaires `NOT`/`-` plus forts que `^` : **`-2 ^ 2` = `(-2) ^ 2` = 4**.

### Arithmétique
- Si **l'un des deux opérandes est une chaîne** : `+` = concaténation (l'autre opérande est
  converti en texte) ; `<`, `>`, `<=`, `>=`, `=`, `<>` = comparaison lexicographique d'octets
  (`StrComp`) ; tout autre opérateur → valeur nulle.
- Si **les deux opérandes sont des entiers** et l'opérateur ∈ {`+`, `-`, `*`, `=`, `<>`, `<`,
  `>`, `<=`, `>=`} : arithmétique **entière** `Int64`.
- Sinon : arithmétique **flottante** (`Double`). **`/` est toujours flottant** : `5 / 2 = 2.5`,
  `4 / 2 = 2.0`.
- `^` : puissance flottante (`Power`).
- **Division par zéro** : avertissement `Runtime Warning: Div 0` + résultat `0.0` (la VM survit).
- Résultat `NaN`/`Inf` : erreur `Flottant corrompu (NaN/Inf)` et **arrêt d'urgence** de la VM.

### Logique & bitwise
- `AND`/`OR`/`XOR` : deux booléens → booléen ; deux entiers → **bitwise** ; mixte → booléen
  (via `to_bool`).
- `NOT` (unaire) : booléen → négation ; entier → **complément bitwise** (`NOT 0 = -1`) ;
  autre → négation logique.

## 5. Variables & portées

- Affectation : `LET x = expr` (`LET` optionnel) ; toujours **par valeur**.
- Table des symboles : table de hachage chaînée (256 buckets), **insensible à la casse**.
- `SUB`/`FUNCTION` créent un **environnement local** chaîné au global (512 niveaux max) :
  - **Lecture** : la globale est visible si absente en local.
  - **Écriture** : crée **toujours** une variable locale (masquage, jamais d'écriture sur la globale).
- Les arguments sont passés **par valeur**.

## 6. Tableaux

- `DIM nom(e1)` / `DIM nom(e1, e2)` / `DIM nom(e1, e2, e3)` : 1 à 3 dimensions.
  Chaque dimension `d` accepte les indices **0 à d** (taille `d+1`).
- Indices `0`-based. Lecture indexée : `nom(i)`, écriture : `nom(i) = expr`.
- Re-`DIM` d'un même nom : erreur `Tableau deja dimensionne` (arrêt VM).
- Écriture sur un non-tableau : erreur `Tableau inconnu` (arrêt VM).
- Appel `nom(...)` d'un **identifiant inconnu** (ni variable, ni tableau) : tenté comme
  **appel de fonction** (utilisateur, FFI, puis intrinsèque) ; sinon erreur
  `Fonction/Sub inconnue`.
- ⚠️ **Aucun contrôle de bornes à ce jour** : `A(10)` sur un `DIM A(5)` lit/écrit de la mémoire
  adjacente de l'arène (comportement indéfini, pas d'erreur). En cours — ROADMAP Phase 2.1.

## 7. Instructions

### PRINT
- Séparateurs `;` et `,` : **équivalents** (simple concaténation, **pas de tabulation**).
- Saut de ligne émis **uniquement si la dernière valeur n'est pas suivie d'un séparateur**.
- `PRINT` seul : ligne vide. `PRINT #N, ...` : écriture sur canal fichier (VFS).

### INPUT
- `INPUT [prompt[,|;]] var` : affiche le prompt (défaut `? `), lit une ligne.
  Conversion : si `var` se termine par `$` → chaîne ; sinon entier (`Int64`), puis flottant,
  sinon chaîne brute.
- `INPUT #N, var` : lecture depuis le canal fichier (mêmes règles de conversion).

### Structures de contrôle
- **IF mono-ligne** : `IF cond THEN stmt [ELSE stmt]`.
- **IF multi-lignes** : `IF cond THEN` / `ELSEIF cond THEN` / `ELSE` / `END IF` (ou `ENDIF`, ou
  `END` + `IF`).
- **WHILE** : `WHILE cond` ... `WEND` (ou `END WHILE`, `ENDWHILE`, `END` + `WHILE`).
- **REPEAT** : `REPEAT` ... `UNTIL cond` — le corps s'exécute **au moins une fois**.
- **FOR** : `FOR var = debut TO fin [STEP pas]` ... `NEXT [var]`.
  - Pas par défaut : 1. Entiers si `var`, `fin` et `pas` sont entiers, sinon flottant.
  - ⚠️ La condition d'arrêt est testée **au `NEXT`** : le corps s'exécute donc **au moins une
    fois**, même si `debut > fin`.
  - Le nom après `NEXT` est **ignoré** (non recoupé avec la variable du `FOR`).
- **BREAK / EXIT [FOR|WHILE|REPEAT]** : interrompt la boucle **la plus interne**.
- **Sauts** : `GOTO` / `GOSUB` / `RETURN` vers un **numéro de ligne** (`10`) ou un **label
  textuel** (`mon_label:`). Cibles vérifiées statiquement au parse (cible inconnue = erreur).
  Numéros de ligne et labels doivent être **uniques**. Pile `GOSUB` : 255 niveaux.
- **END** : arrête l'exécution.
- **SLEEP ms** : pause du processus hôte.

### SUB / FUNCTION / CALL
- `SUB nom(p1, p2) ... END SUB` — procédure, appel : `CALL nom(args)`.
- `FUNCTION nom(p1) ... END FUNCTION` — appelable comme expression (avec ou sans `CALL`).
  La valeur de retour est affectée **au nom de la fonction** dans son corps
  (`LET nom = expr`) ; sans affectation → retourne 0.
- Récursivité supportée (limite 512 appels).
- Ordre de résolution d'un appel : **fonctions utilisateur → FFI → intrinsèques**.
  Une fonction utilisateur peut donc **masquer** une fonction intrinsèque.

### SELECT CASE
- `SELECT CASE expr` / `CASE v1, v2` / `CASE ELSE` / `END SELECT` (ou `END` + `SELECT`).
- Correspondance polymorphe : deux chaînes → égalité exacte ; deux entiers → égalité exacte ;
  sinon **comparaison numérique**. Première branche correspondante exécutée, puis sortie.
- `CASE ELSE` (p1 = nil) attrape tout.

### E/S fichiers (VFS)
- `OPEN fichier FOR INPUT|OUTPUT|APPEND AS #N` (canaux 1 à 8).
- `CLOSE [#N]` ; `CLOSE` seul ferme les 8 canaux.
- `EOF(N)` : fin de fichier (vrai si canal fermé ou VFS absente).

## 8. Fonctions intrinsèques (parenthèses obligatoires)

| Fonction | Sémantique |
|---|---|
| `ABS(x)` | valeur absolue (entière si entier) |
| `INT(x)` | troncature vers zéro (`Trunc`) |
| `SQR(x)` | racine carrée flottante ; `x < 0` → avertissement + 0 |
| `RND` / `RND(n)` | `RND()` : flottant ∈ [0, 1) ; `RND(n>0)` : entier ∈ [0, n-1] ; `RND(n≤0)` : flottant |
| `SIN(x)`, `COS(x)`, `TAN(x)` | trigonométrie (radians) |
| `LEN(x)` | longueur en octets (non-chaîne → chaîne convertie) |
| `LEFT$(s, n)` | n premiers caractères (1-based) ; `n ≤ 0` → vide |
| `RIGHT$(s, n)` | n derniers ; `n ≥ len` → tout |
| `MID$(s, debut[, len])` | sous-chaîne 1-based ; hors bornes → vide |
| `CHR$(n)` | caractère `n AND 255` |
| `ASC(s)` | code du 1er caractère ; chaîne vide → 0 |
| `STR$(x)` | représentation texte (`IntToStr`/`FloatToStr`/`TRUE`/`FALSE`/`<ARRAY>`) |
| `VAL(s)` | **analyse progressive** : signe facultatif, chiffres, un seul point ; s'arrête au premier caractère invalide (`VAL("100ABC") = 100`) ; vide → 0 ; entier si sans point, flottant sinon |
| `EOF(N)` | fin de fichier du canal (vrai si canal fermé) |
| `TIMER()` | `GetTickCount64`, millisecondes — **parenthèses obligatoires** (`TIMER` nu est lu comme une variable non définie) |

## 9. Erreurs & diagnostics

- **Parse** : `Erreur Syntaxique [Ligne, Col]: message` + affichage de la ligne source et du
  curseur `^`. L'analyse s'arrête à la **première** erreur. Lint statique : `--check`.
- **Runtime** : messages sur `stderr` (division par zéro, limites dépassées, etc.). La VM
  s'arrête, mais ⚠️ le **code de sortie du processus reste 0** après une erreur runtime
  (limitation connue pour l'intégration CI).
- **Watchdog** : `Limite Instructions Depassee` — boucles infinies contenues
  (`GOTO`/`WHILE`/`REPEAT`/`FOR`).

## 10. Limites connues

| Ressource | Limite |
|---|---|
| Arène mémoire | 16 Mio |
| Watchdog instructions | 10 000 000 |
| Identifiant | 63 caractères |
| Buckets table des symboles | 256 |
| Pile `FOR` | 64 |
| Pile `GOSUB` | 255 |
| Récursivité SUB/FUNCTION (`call_depth`) | 512 |
| Profondeur expressions (`expr_depth`) | 512 |
| Canaux fichiers | 1 à 8 (`#1`–`#8`) |
| Dimensions de tableaux | 1 à 3 |

## 11. CLI & REPL

- `nanobasic [options] [fichier.bas]` ; options `--check|-c`, `--version|-v`, `--help|-h`.
- Sans argument : **REPL** — édition par numéros de ligne (saisir `10` seul supprime la ligne),
  commandes `LOAD`, `SAVE`, `LIST`, `RUN`, `CHECK`, `NEW`, `DIR`, `CLS`, `HELP`, `EXIT`/`QUIT`.
  ⚠️ `CLEAR` est annoncé dans l'aide mais **pas encore implémenté** (ROADMAP Phase 2.4).
- `--check` affiche : `Syntaxe valide (N instructions statiques).`

## 12. API d'embarquement (hôte Pascal)

- Callbacks : `vm.on_print`, `vm.on_input`.
- Injection/lecture : `vm_set_int`, `vm_set_num`, `vm_set_str`, `vm_get_int`, `vm_get_num`,
  `vm_get_str`.
- FFI : `vm_register_ffi(vm, 'NOM', @maFonction)` — signature
  `function(vm: PVM; const args: array of Value): Value`.
- VFS : `vm_enable_standard_vfs(vm)` (fichiers réels) ou callbacks personnalisés
  (`vfs_open/close/print/input/eof`) pour une sandbox.