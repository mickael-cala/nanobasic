# Journal des modifications (Changelog)

Toutes les modifications notables apportées à Nanobasic seront documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/), et ce projet respecte le [Semantic Versioning](https://semver.org/lang/fr/).

## [Non publié]

### Ajouté
- Fonctions mathématiques (`SIN`, `COS`, `SQR`, `ABS`, etc.).
- Opérateurs logiques (`AND`, `OR`, `NOT`).
- Prise en charge avancée des chaînes de caractères (concaténation, fonctions `LEN`, `MID$`, etc.).
- Tableaux (dimensionnement simple).
- Meilleure gestion des erreurs (exceptions).

### Modifié
- Optimisation du moteur d'exécution.

## [1.0.0] - 2026-08-24

### Ajouté
- Interpréteur BASIC minimal.
- Analyse lexicale (scanner), syntaxique (parser) et exécution (interpréteur).
- Support des commandes : `PRINT`, `INPUT`, `IF...THEN...ELSE`, `FOR...NEXT`, `GOSUB/RETURN`, `GOTO`, `REM`, `END`.
- Variables entières et réelles.
- Opérations arithmétiques et comparaisons.
- Mode REPL interactif.
- Exécution de fichiers `.bas`.
- Exemples dans le dossier `examples/`.
- Makefile pour la compilation et les tests.
- Documentation (README, LICENSE, etc.).
