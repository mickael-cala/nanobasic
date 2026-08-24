"# nanobasic"


24-08-2026

24-08-2026 split en unité pascal
Nouvelle architecture :
.\NANOBASIC\src\
├── nanotypes.pas   (Arène, types de base, AST, table des symboles, labels)
├── nanolexer.pas   (Tokens et analyseur lexical)
├── nanoparser.pas  (Analyse syntaxique, validation statique GOTO/GOSUB)
├── nanovm.pas      (Machine virtuelle, boucle d'exécution, piles FOR et GOSUB/RETURN)
└── nanobasic.pas   (Point d'entrée : exécution de fichier .bas ou mode REPL)

