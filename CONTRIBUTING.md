# Contribuer à Nanobasic

> ⚖️ **Clause de renonciation aux droits pécuniaires et à toute rémunération commerciale**
> En soumettant une contribution (code, documentation, correction, etc.) à ce projet, le contributeur consent expressément et irrévocablement à céder gratuitement l'ensemble de ses droits patrimoniaux d'exploitation sur ladite contribution, pour toute la durée légale de protection des droits de propriété intellectuelle et dans le monde entier. En conséquence, le contributeur renonce explicitement et définitivement à toute réclamation de rémunération, redevance ou compensation financière liée à l'exploitation commerciale, directe ou indirecte, de ses modifications ou des œuvres dérivées en résultant.
⚖️ **Fin Clause de renonciation aux droits pécuniaires et à toute rémunération commerciale**

Merci de votre intérêt pour Nanobasic ! Voici quelques directives pour vous aider à contribuer efficacement.

Pour l'instant, les modifications ne sont pas acceptées avant la stabilisation complète du projet.

## Signalement de bugs

- Vérifiez d'abord que le bug n'a pas déjà été signalé dans les **issues**.
- Si ce n'est pas le cas, créez une nouvelle issue avec :
  - Un titre clair et descriptif.
  - Une description détaillée du problème.
  - Les étapes pour reproduire le bug.
  - Le résultat attendu et le résultat observé.
  - Votre environnement (système d'exploitation, version de Free Pascal, etc.).

## Demandes de fonctionnalités

- Ouvrez une issue avec le label `enhancement`.
- Expliquez clairement la fonctionnalité souhaitée et son utilité.

## Soumission de code (Pull Requests)

1. **Forkez** le dépôt et créez une branche pour votre contribution.
2. Assurez-vous que votre code suit le style de codage (voir ci-dessous).
3. Si vous ajoutez une nouvelle fonctionnalité, incluez des tests (si possible).
4. Vérifiez que tout compile et que les tests existants passent : `make check && make test` (Unix) ou `tests\run_tests_exe.bat` + `tests\run_tests_bas.bat` (Windows).
5. Soumettez une Pull Request (PR) vers la branche `main`.
   - Décrivez clairement les changements apportés.
   - Référencez l'issue correspondante si elle existe.

## Style de codage

- **Langage** : Pascal (Free Pascal) en mode objet (`-Mobjfpc`).
- **Indentation** : 2 espaces, pas de tabulations.
- **Nommage** :
  - Variables, paramètres, fonctions : `camelCase` (ex: `nombreEleves`).
  - Constantes : `MAJUSCULES_AVEC_SOULIGNES`.
  - Types : `TCamelCase` (préfixé par `T`).
- **Commentaires** :
  - Les commentaires de ligne utilisent `//`.
  - Les commentaires de bloc utilisent `{ ... }`.
  - Documentez les fonctions et procédures avec une brève description (but, paramètres, retour).
- **Limite de ligne** : 80 caractères de préférence, tolérance à 100.
- **Espaces** : Placez des espaces autour des opérateurs (sauf pour les opérateurs unaires) et après les virgules.
- **Utilisation des parenthèses** : Pour clarifier la priorité des opérations.

Exemple :

```pascal
function Additionner(a, b: Integer): Integer;
begin
  Result := a + b;
end;
```

## Structure
Les unités du moteur vivent dans `src/` — une unité par fichier, nommée d'après l'unité :

* `nanotypes.pas` → unité `NanoTypes` (types, arène, AST, tokens, symboles, labels)
* `nanolexer.pas` → unité `NanoLexer` (analyseur lexical)
* `nanoparser.pas` → unité `NanoParser` (parseur descendant récursif + AST)
* `nanovm.pas` → unité `NanoVM` (machine virtuelle Tree-Walk, FFI, VFS)
* `nanobasic.pas` → programme principal (CLI & REPL)

Les tests et harnais batch se trouvent dans `tests/`, les scripts BASIC dans `examples/`.

## Processus de revue
Toute PR sera examinée par le mainteneur. Des commentaires ou demandes de modifications peuvent être formulés. Veuillez répondre rapidement pour accélérer le processus.

## Code de conduite
Soyez respectueux et constructifs dans vos interactions. Nous nous engageons à maintenir un environnement accueillant.

Merci de contribuer !
