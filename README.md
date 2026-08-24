# Nanobasic

**Nanobasic** est un interpréteur BASIC minimaliste écrit en Pascal (Free Pascal). Il implémente un sous-ensemble du langage BASIC, avec un analyseur syntaxique basé sur un arbre syntaxique abstrait (AST). Le projet est conçu pour être léger, facile à comprendre et à étendre.

## Fonctionnalités

- Variables entières et réelles
- Opérations arithmétiques de base (+ - * /)
- Affichage avec `PRINT`
- Saisie utilisateur avec `INPUT`
- Boucles `FOR ... NEXT`
- Conditions `IF ... THEN ... ELSE`
- Sous-programmes `GOSUB` et `RETURN`
- Commentaires avec `REM`
- Gestion des erreurs rudimentaire

## Architecture

Le code est organisé en plusieurs unités Pascal :

- `nanobasic.pas` : point d'entrée, boucle principale (REPL ou exécution de fichier)
- `scanner.pas` : analyse lexicale (reconnaissance des tokens)
- `parser.pas` : analyse syntaxique (construction de l'AST)
- `interpreter.pas` : évaluation de l'AST
- `ast.pas` : définitions des nœuds de l'AST
- `errors.pas` : gestion des erreurs et messages

## Installation et compilation

### Prérequis

- [Free Pascal Compiler](https://www.freepascal.org/) (version 3.0 ou ultérieure)
- `make` (optionnel, mais recommandé)

### Compilation manuelle

```bash
fpc -Mobjfpc -O2 -S2h -Ci -Co -Ct -Cri src/nanobasic.pas -FEbin
```
L'exécutable sera généré dans le dossier bin/.


### Compilation avec Makefile
```bash
make          # compile
make clean    # nettoie les fichiers objets
make test     # exécute les exemples
make install  # installe dans /usr/local/bin (nécessite sudo)
```

## Utilisation
Exécutez le programme avec un fichier source BASIC en argument (exécute le fichier test.bas dans le répertoire examples) :
```bash
./bin/nanobasic examples/test.bas
```

Sans argument, il lance un REPL (Read-Eval-Print Loop) :
```bash
./bin/nanobasic
```
Syntaxe supportée, voici un exemple simple :

```basic
10 PRINT "Hello, World!"
20 INPUT "Entrez votre nom : ", N$
30 PRINT "Bonjour, "; N$
40 FOR I = 1 TO 5
50   PRINT "I = "; I
60 NEXT I
70 END
```
Mots-clés reconnus
PRINT, INPUT, IF, THEN, ELSE, FOR, TO, STEP, NEXT, GOTO, GOSUB, RETURN, REM, END, LET (optionnel).

Opérateurs
Arithmétiques : +, -, *, /
Comparaisons : =, <>, <, >, <=, >=
Logiques : AND, OR, NOT (à implémenter partiellement)

## Tests

Des exemples sont fournis dans le dossier examples/. Pour lancer tous les tests :
```bash
make test
```
Vous pouvez ajouter vos propres scripts dans ce dossier.

## Contribuer

Les contributions sont les bienvenues ! Veuillez consulter le fichier CONTRIBUTING.md (à venir) pour les directives.

## Licence

Ce projet est distribué sous la GNU Affero General Public License v3.0 (AGPL-3.0).
Cependant, une licence commerciale est également disponible pour ceux qui souhaitent l'utiliser dans un contexte propriétaire sans les contraintes de l'AGPL. Contactez l'auteur pour plus d'informations.

Voir le fichier LICENSE pour les détails complets.

## Auteur

Mickaël Cala
GitHub : @mickael-cala

## Remerciements

Merci à la communauté Free Pascal pour ses outils et sa documentation.
