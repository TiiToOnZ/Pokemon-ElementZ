# Noigrumiers et Boîte Noigrume — PSDK 26.60

## Installation effectuée

Les scripts de ce dossier sont chargés après Crafting. Les sept PNG sont copiés
à l'identique dans `graphics/characters`. La recette `heavy_ball` est ajoutée à
`Data/configs/crafting_config.json`, sur le modèle des six autres recettes.
PSDK régénère son cache de configuration au prochain lancement si le JSON est
plus récent que son RXDATA. Redémarrer le jeu après installation.

Les sources PSDK, SaveLoadTweaks, les effets des Balls, les définitions Studio
des objets et les maps ne sont pas modifiés.

## Créer un arbre

1. Depuis le projet Pokémon Studio, ouvrir la map dans RPG Maker XP et créer
   un événement avec **une seule page sans condition** (aucune case cochée).
2. Lui donner un nom libre, par exemple `Noigrumier` ou `Arbre route 1`.
3. Choisir le déclenchement **Touche action**. Aucun processus parallèle.
4. Dans les commandes de la page, ajouter **Commentaire** et saisir exactement
   `<apricorn_tree: red>` pour un Noigrumier Rouge. Ce n'est pas une commande
   **Script**. Ne pas ajouter d'autres commandes exécutables : la page est
   entièrement gérée par ce système, qui installe en mémoire l'appel générique
   `apricorn_tree`. La liste d'origine dans la map reste intacte.
5. Le character est choisi automatiquement. Pour l'aperçu RMXP, sélectionner le
   PNG `apr_Red`, première ligne/première colonne. Ne pas utiliser de tile.
6. Ne pas créer de page « récolté », ni de condition sur l'interrupteur local D.
   Enregistrer la map, redémarrer le jeu puis interagir avec l'arbre.

Pour les autres variantes, remplacer `red` par `blue`, `yellow`, `green`, `pink`,
`white` ou `black`. Une seule déclaration par page, sur sa propre ligne.
Une couleur inconnue, une balise mal formée commençant par `<apricorn_tree` ou
une déclaration répétée provoque une `ArgumentError` explicite.

### Pourquoi un commentaire sous PSDK 26.60 ?

Vérification des sources installées : `RPG::Event` et `RPG::Event::Page` dans
`psdk_scripts/0_Dependencies.rb` exposent les pages et leurs listes de commandes,
sans champ générique de métadonnées éditable pour ce besoin. `Game_Event#refresh`
et `#refresh_page` dans `4_Systems_003_Map_Engine.rb` sélectionnent la page active
et conservent sa liste source. Les commentaires RMXP (codes 108 et 408 pour une
continuation) portent donc la déclaration sans exécuter de Ruby.

`<apricorn_tree: red>` est une petite convention **de notre système**, pas une
balise native PSDK. `Config.color_from_page` la lit uniquement dans les commentaires
de la page active ; `Config::TYPES` valide la couleur et centralise objet, ID,
charset et Ball. Pas de registre externe ni de nouveau framework. La lecture
au rafraîchissement permet de régler l'apparence avant la première interaction,
en conservant une page sans condition et sans commande exécutable à saisir.

Le nom n'est jamais consulté par le système Noigrumes ; un ancien nom
`apricorn_red` sans commentaire ne déclare plus un arbre. Les autres conventions
natives PSDK sur les noms (`[sprite=off]`, etc.) restent celles du moteur :
ne pas les ajouter à un nom libre si l'on ne veut pas leurs effets.

Les directions fixes, l'absence de marche/animation automatique et la collision
sont imposées par le moteur commun. Les pages conditionnelles restent possibles
pour masquer entièrement un arbre, mais aucune page « récolté » n'est nécessaire.
L'interrupteur local **D** et l'unique temporisation de cet événement sont réservés
au système ; ne pas leur attribuer un autre usage.

L'identité est `[original_map, original_id]`, y compris sur une map liée.
Dupliquer un événement dans RMXP lui donne un autre ID, donc un autre arbre.
Déplacer ou réutiliser des IDs de maps/événements déjà publiés change l'identité
de sauvegarde. Les anciens arbres sans état enregistré sont disponibles.

Le helper interne `apricorn_tree` utilise cette déclaration. Son argument
facultatif (`apricorn_tree(:red)`) ne remplace pas le commentaire : s'il est fourni,
il doit correspondre à la couleur déclarée. Il n'existe pas de seconde méthode
de configuration fondée sur le nom ou sur la commande Script.

## Récolte et animation

Une interaction avec un arbre disponible donne exactement un fruit dans
`PFM.game_state.apricorns`. Le joueur est orienté, passe en état `:apricorn`, utilise
`<charset_base>_m_shake` ou `<charset_base>_f_shake`, puis revient à la marche.
Les ressources `player_m_shake` et `player_f_shake` existent déjà. Un autre jeu de
costumes doit fournir son suffixe `_shake` correspondant.

Frames de l'arbre (ligne/colonne à partir de 1 ; durées en secondes) :

| Frames | Durée par frame |
|---|---:|
| L1C1, L1C2, L1C3, L1C2, L1C1 | 0,08 |
| L1C4, L2C1, L2C2, L2C3 | 0,06 |
| L2C4, L3C1, L3C2 | 0,08 |
| L3C3 | 0,10 |
| L3C4, L4C1, L4C2 | 0,08 |
| L4C3 | 0,02 |

Soit **1,24 s minimum**, légèrement arrondies aux frames rendues. Le joueur
progresse de pattern 0 à 3, un pas par 0,10 s, puis tient sa pose. Les durées
utilisent une horloge monotone et ne dépendent pas du réglage de fréquence vidéo.

L'ajout du fruit et le délai persistant sont validés sans céder la main. Un verrou
transitoire empêche les récoltes simultanées. Une interruption avant validation ne
donne rien ; après validation, le délai bloque une seconde attribution. Une clause
`ensure` restaure joueur/arbre ; un garde-fou libère une animation abandonnée.
Le texte et la fanfare d'obtention natifs sont réutilisés sans ajout au Sac.

L'arbre vide reste en **L4C3** et indique qu'il n'y a plus rien à récolter.

## Repousse et sauvegarde

Le délai expire au **prochain minuit local réel**, même si un événement passe TJN
en mode virtuel. Le writer natif `trigger_event_in` est utilisé via un Interpreter
à horloge réelle ; aucun switch TJN n'est changé. Les données restent au format
natif `user_data[:tjn_events][map_id][event_id] = [minute_cible, 'D']`.

**Pourquoi réserver D ?** Le timer natif exige une lettre d'interrupteur local :
`trigger_event_in` met cette lettre à **false lors de chaque récolte validée** ;
le traitement d'expiration la met à **true** et supprime le timer échu. Notre
rafraîchissement applique le même signal pour les arbres des maps liées et les
échéances déjà passées au chargement. D reste true jusqu'à la récolte suivante.
Avant la première récolte, sa valeur n'est pas utilisée : l'absence de timer
rend l'arbre disponible, même si D est false.

Au prochain minuit local réel, l'arbre redevient disponible et retrouve son
apparence pleine au prochain rafraîchissement ; si le jeu était fermé ou la map
absente, cela est constaté au chargement/retour. D ne choisit ni la couleur ni
l'identité, et ne décide pas de la disponibilité : l'échéance du timer fait foi.
La lettre D est notre choix de réservation, pas une obligation particulière de
TJN ; conserver cette lettre permet de réutiliser le mécanisme natif inchangé.

**Le conflit n'est pas impossible par nature** : une page conditionnée par D
pourrait devenir active à l'expiration. La procédure évite ce conflit avec une
page unique sans condition, et aucun autre usage de D ou du timer de cet événement.
La réservation concerne seulement cet arbre, pas les autres événements.

L'apparence est fixée dès la création/actualisation de l'événement, avant son
premier rendu. Une vérification à chaque changement de minute traite aussi les
arbres des maps voisines affichées par MapLinker, et compense les scans natifs
limités à la map centrale. Les temporisations des autres événements restent intactes.

La date Windows est la référence : avancer l'horloge peut faire repousser plus
tôt ; la reculer peut prolonger l'attente. Il n'y a pas de mécanisme antitriche.
Les échéances sont exprimées en minutes locales comme celles de PSDK.
Fermeture/rechargement fonctionne **après sauvegarde**, comme le reste du jeu ;
la récolte ne déclenche pas une sauvegarde automatique.

`PFM::Apricorns` appartient à `GameState` et est sérialisé nativement par Marshal.
Les anciennes sauvegardes initialisent automatiquement les sept quantités, puis
transfèrent leurs stocks Noigrumes encore présents dans le Sac. Les stocks déjà
acquis ne déclenchent pas à nouveau les quêtes. L'opération est idempotente et ne
modifie aucun fichier de sauvegarde tant que le joueur ne sauvegarde pas.
Les entrées transférées sont retirées de `Bag#@items` (ainsi que leurs références
d'ordre/raccourci) : un second passage ne trouve plus rien à transférer.
Recharger une ancienne sauvegarde non réenregistrée reconstruit son état d'origine
puis effectue ce même transfert une fois ; les quantités ne s'ajoutent pas à
l'état de la session précédente. `PFM::Apricorns` reste l'unique stock.

API : `$apricorns[:red]`, `.quantity(:red)`, `.add(:red, 2)`, `.remove(:red, 1)`.
Types inconnus et quantités non entières/négatives : `ArgumentError`.
Retrait supérieur au stock : `false`, aucune modification. Zéro : opération neutre.
`.quantities` expose une copie gelée des sept valeurs.

Les anciens appels du Sac (`add_item`, `store_item`, `remove_item`, `drop_item`,
`item_quantity`) redirigent ces seuls objets vers le stockage dédié. Aucun stock
Noigrume n'est conservé dans `Bag#@items`. Les opérations normales des autres objets
sont inchangées. La sémantique signée historique du Sac reste compatible.

## Boîte Noigrume

Utiliser l'objet `apricorn_box` depuis le Sac ouvre la collection. Les sept icônes
et quantités sont visibles simultanément ; les flèches parcourent la sélection,
B ferme. Le panneau affiche nom, quantité, description Studio et Ball correspondante.
Aucune action d'utilisation, de fabrication, de don ou de suppression.

Le système ne donne pas automatiquement l'objet rare au joueur. Le prévoir dans
le scénario ; pour un test via événement : `$bag.add_item(:apricorn_box, 1)`.
Posséder l'objet rare n'est pas une condition de récolte : le stockage existe dès
le début de partie, même avant la remise de la Boîte.

## Artisanat et quêtes

Les recettes conservent leurs clés d'objets Studio. Les quantités, leur affichage
et le maximum fabricable lisent désormais le stockage dédié via l'adaptateur du Sac.
Les recettes contenant des Noigrumes sont préparées sur une copie isolée de
l'inventaire. On vérifie le retrait des matériaux ordinaires et l'insertion du
résultat avant de valider stocks et résultat, sans yield. Un échec ou une insertion
silencieuse sans effet ne consomme rien. Les recettes mixtes sont supportées.
Les recettes sans Noigrume continuent d'appeler l'implémentation Crafting existante.

Les sept recettes coûtent une Noigrume et produisent une Ball. Masse Ball suit
exactement la configuration manuelle initialement débloquée des six autres.

Chaque nouvelle acquisition appelle `game_state.quests.add_item(item_symbol, nombre)`
directement. Les objectifs existants `objective_obtain_item` continuent de fonctionner.
Les notifications du résultat fabriqué ne sont émises qu'après validation.
Pour une future quête distinguant récolte et cadeaux, le hook
`ApricornTrees.on_acquire(:nom) { |stock, couleur, nombre, source| ... }` est disponible.
La source vaut `:harvest`, `:legacy_bag` ou celle passée à `add` (`:event` par défaut).
Ce hook fournit un point d'intégration, pas un nouvel objectif Studio préconfiguré.

## Conversion ultérieure des anciens événements

Aucune de ces maps n'a été modifiée. Après validation, convertir chaque événement :
conserver un nom libre, ajouter le commentaire du tableau, supprimer les commandes `$bag.add_item`,
l'activation de A et la page vide conditionnée par A ; conserver une seule page
sans condition, déclenchée par Touche action. Les anciennes valeurs de A peuvent
rester dans les sauvegardes puisqu'aucune page ne les consulte plus.

| Map | Événement | Commentaire à ajouter |
|---:|---:|---|
| 35 | 129 | `<apricorn_tree: blue>` |
| 35 | 130 | `<apricorn_tree: green>` |
| 35 | 131 | `<apricorn_tree: pink>` |
| 52 | 18 | `<apricorn_tree: yellow>` |
| 52 | 19 | `<apricorn_tree: black>` |
| 78 | 4 | `<apricorn_tree: pink>` |
| 78 | 5 | `<apricorn_tree: green>` |
| 78 | 6 | `<apricorn_tree: blue>` |

Avant conversion, ces événements restent des dons uniques, mais leurs appels
au Sac créditent déjà la Boîte. Ne pas conserver simultanément leur ancienne
attribution et un appel de récolte.

## Vérifications

Depuis `scripts` : `ruby "00017 ApricornTrees/tests/run.rb"`.
Le banc charge le véritable GameState, le Sac natif, les méthodes de timer et
d'Interpreter nécessaires et le Crafting existant. L'affichage, l'entrée utilisateur
et certains objets de map sont simulés ; aucune sauvegarde réelle n'est ouverte.
Base conservée : **33 tests, 339 assertions**. Après remplacement de la reconnaissance
par nom : **38 tests, 382 assertions, aucun échec ni erreur**. Les cinq nouveaux tests
couvrent les noms libres/ignorés, les couleurs invalides, l'absence de reconnaissance
par ancien nom ou commande Script, les commentaires continués et leur conservation
au rafraîchissement/changement de page, ainsi que les déclarations mal formées/doubles.
Les tests existants gardent la couverture des identités MapLinker, arbres indépendants,
animations, repousse, migration idempotente, stockage, quêtes, Boîte et artisanat.
Les sept copies de PNG ont aussi été comparées aux originaux (identiques).

À vérifier en jeu sur des événements de test créés manuellement :

- Les sept arbres, les deux sprites de joueur, le rythme et le cadrage des frames.
- Une récolte, double appui, arbre vide, retour des contrôles.
- Boîte : sept quantités, sélection, descriptions sans débordement, B, réouverture.
- Les sept Balls, quantité insuffisante, fabrication multiple et recette ordinaire.
- Sauvegarde/rechargement le même jour, puis le lendemain ; ancienne sauvegarde.
- Deux arbres rouges distincts et un arbre visible depuis une map liée.
- Quête d'obtention existante, migration du stock sans doublonner la progression.

Ne pas confondre les tests headless avec une validation visuelle dans le moteur.
