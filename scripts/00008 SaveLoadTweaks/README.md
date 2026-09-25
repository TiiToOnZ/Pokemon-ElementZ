# SaveLoadTweaks — PSDK 26.60

Extension locale de l'ancien script de FrivolousAqua. Aucun changement du moteur,
des textes, du format Marshal, de l'en-tête, de la clé ou des noms de sauvegarde.
La sérialisation et les hooks `BEFORE_SAVE_HOOKS` / `AFTER_SAVE_HOOKS` restent
exécutés par le `GamePlay::Save.save` natif.

## Points d'extension

- `GamePlay::Load#initialize` et `#load_all_saves` appellent `super`, puis
  conservent une entrée pour un fichier unique invalide ou un secours seul.
  Le titre peut ainsi proposer le choix de chargement au lieu de lancer
  silencieusement une nouvelle partie. Les objets autres que `PFM::GameState`
  sont traités comme invalides.
- `Load#load_sign_data` conserve le rendu natif et corrige uniquement les fiches
  vides entre deux fichiers. `Load#action_a` délègue au natif pour une sauvegarde
  chargeable ou un emplacement vide ; les avertissements sont ajoutés localement.
- `GamePlay::Save.save` appelle `super` et conserve son retour natif (chaîne
  sérialisée). Deux indicateurs distincts suivent la tentative et sa réussite.
- `Save.save_file` est remplacée : la méthode native intercepte les erreurs sans
  transmettre un résultat fiable et supprime le précédent `.bak` avant écriture.
- `Save#save_game` appelle `super` mais retourne à la scène le résultat réel de
  l'écriture. `Save#action_a` reste remplacée car le natif annonce un succès même
  après un échec. Elle ferme la scène après le message, uniquement après réussite.

## Écriture et secours

1. Préparer le nouveau contenu dans un fichier temporaire du même répertoire.
2. Synchroniser le fichier et comparer sa relecture aux octets sérialisés natifs.
3. Préparer une copie de retour arrière du principal s'il existe.
4. Remplacer le principal par renommage, puis vérifier à nouveau son contenu.
5. Si l'ancien principal est chargeable par le lecteur natif et contient un
   `PFM::GameState`, utiliser sa copie comme `.bak`. Sinon, conserver le `.bak`
   existant sans le modifier.
6. Déclarer la réussite ; actualiser la fiche, jouer le son et afficher le texte.

En cas d'échec avant remplacement, le principal et le secours restent inchangés.
Après remplacement, une erreur de vérification ou de rotation du secours provoque
un retour arrière du principal. Il ne s'agit jamais d'une restauration automatique
du `.bak`. Si le système refuse également le retour arrière, la copie temporaire
de l'ancien principal est conservée pour récupération manuelle. Ces fichiers
`.save-load-tweaks-*.tmp` ne sont pas pris pour des sauvegardes par le catalogue.
La scène annonce alors un échec, jamais un succès.

La vérification compare le fichier aux octets produits par le moteur ; elle ne
constitue pas une validation exhaustive de tous les champs d'anciennes versions
de `PFM::GameState`. Une coupure du processus ou du système n'est pas équivalente
aux erreurs Ruby testées. Aucun nouveau mécanisme de migration n'est introduit.

La confirmation d'écrasement dépend de `File.file?` sur le principal sélectionné.
Les choix et textes français `311110` restent inchangés ; « Non » est sélectionné
par défaut et Retour équivaut à Non. Le texte relatif au secours n'est affiché que
si ce fichier existe ; sa présence ne garantit pas qu'il soit récupérable.
Les banques ES/IT comportent toujours les entrées vides signalées dans l'audit.

## Tests isolés

Depuis le dossier `scripts` :

```powershell
ruby '00008 SaveLoadTweaks/tests/run.rb'
& 'C:\Users\thiba\AppData\Local\Programs\pokemon-studio\resources\psdk-binaries\ruby.exe' '00008 SaveLoadTweaks/tests/run.rb'
```

Le harnais ne dépend d'aucune gem. Il charge le fichier natif Save/Load du projet
en lecture seule, puis l'extension, et simule les dépendances graphiques et les
changements de scène. Chaque test utilise son propre répertoire temporaire ;
aucune sauvegarde réelle n'est lue ni modifiée. Le dossier `tests`, non numéroté,
n'est pas chargé par le chargeur de scripts du jeu.

Les contrôles couvrent les modes unique/multiple, les trous, le fichier unique
corrompu, les secours seuls, les choix, les hooks, les écritures réussies,
partielles ou refusées, le retour arrière et l'absence explicite de faux succès.
Le chargement natif de la carte et les animations de l'interface sont simulés.

## Vérification en jeu

- Vérifier le choix Oui/Non, Non présélectionné et Retour, sans seconde question.
- Vérifier le nom du joueur dans le message, le son et la fiche actualisée avant
  fermeture ; vérifier aussi les informations de la fiche après rechargement.
- Dans une copie isolée du projet, vérifier un trou entre deux fichiers, un seul
  principal invalide et un secours seul : avertissements pertinents, aucune
  restauration automatique, aucun changement de fichier lors de l'annulation.
- Dans cette copie, charger une copie d'une sauvegarde existante, sauvegarder et
  recharger ; vérifier Pokémon, progression, Crafting et CaptureChain.
- Contrôler visuellement qu'après un refus d'écriture l'écran reste utilisable,
  sans son/message de réussite ni fiche faussement actualisée.

## Réversibilité

Le diff est limité à ce dossier. Pour revenir à la version précédente, restaurer
uniquement `00000 SaveLoadTweaks.rb` depuis sa version Git antérieure et retirer
ce README et le dossier de tests si souhaité. Aucun fichier de sauvegarde ni
ressource texte n'a besoin d'être converti.
