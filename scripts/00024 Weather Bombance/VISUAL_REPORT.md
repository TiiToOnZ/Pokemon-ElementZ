# Nappes de brume en combat — 13 octobre 2026

Le Fog existant est enrichi dans son propre `FogLayer`. Le voile original est
conservé, y compris l'opacité **150** trouvée dans le projet avant intervention.
Aucun second contrôleur ni état météo n'a été ajouté.

## Fichiers

Modifiés :

- `00002 FogVisual.rb` : deux nappes, déplacement et ondulation, fondu commun,
  nettoyage et protection en cas d'échec de construction.
- `tests/support.rb` : primitives de test pour les deux nouvelles Plane.
- `tests/weather_test.rb` : cycle de vie, texture partagée, fondu, boucle,
  stabilité des objets, météo absente et combat suivant.
- `tests/native_visual.rb` : Marsh, captures temporelles, contrôle des bords,
  raccord de boucle, destruction et mesures de performance.
- `README.md` : lien vers ce complément au rapport initial.

Créés :

- `graphics/animations/bombance_weather/mist_wisps.png` : texture RGBA dédiée,
  créée avec le skill imagegen et intégrée au projet.
- `tests/mist_captures/` : 23 captures du banc natif (18 vues avant/Fog sur neuf
  compositions, quatre instants de mouvement et une vue après dissipation).
- `VISUAL_REPORT.md` : ce rapport.

`00001 WeatherIntegration.rb` n'a pas changé : SHA-256 avant/après
`85588AF1497849DD12282F947C86C2040B2C36DC72D850F1CCEFB79873570140`.
Le multiplicateur ×0,8, les annonces, les talents neutralisants, Anti-Brume et la
synchronisation initiale sont donc conservés. Aucun changement PSDK, BBBB, Kit,
Marsh, battlebacks, positions, événements ou textes. Aucun commit créé.

## Rendu et cycle de vie

| Élément | z | Opacité maximale | Défilement | Ondulation verticale |
| --- | --- | --- | --- | --- |
| Voile existant | 60 | 150/255, réglage préexistant | 4 px/s | aucune |
| Nappe arrière | 61 | 52/255 | 6 px/s | amplitude 2 px, période 13 s |
| Nappe avant | 62 | 36/255 | 9 px/s | amplitude 3 px, période 17 s |

Les nappes ont des origines différentes, dont un décalage horizontal de 160 px.
Leurs positions verticales placent les volutes au-dessus du terrain. Les valeurs
figurent dans `MIST_LAYERS`, au début de `00002 FogVisual.rb`.

Les trois Plane appartiennent au même viewport de combat. Les nappes restent sous
les bases (100/500), Pokémon (101+/501+) et interface, ce qui conserve leur
lisibilité. La texture est projetée sur une tuile logique de 320 × 240 pixels.
Ses quatre bords sont entièrement transparents. Le shader natif répète la texture ;
le modulo conserve la continuité, même quand une nappe franchit le bord de l'écran.

Le setter d'opacité existant applique le même facteur de fondu aux deux nappes.
L'animation initiale demeure finie (0,6 s), sans ajout d'attente infinie. Avec les
animations désactivées, les nappes et le voile apparaissent directement et continuent
à se déplacer comme ambiance de terrain.

Le temps écoulé pilote le défilement et les deux sinus. L'update ne crée aucun
sprite, bitmap, shader ou texture. Les deux nappes partagent le même bitmap chargé
dans `RPG::Cache`. Cela représente deux Plane et deux appels de dessin supplémentaires.

Fog → autre météo détruit les trois Plane via le nettoyage existant. `Visual#dispose`
fait de même à la sortie de scène. Les objets sont recréés quand Fog revient et
pour un nouveau combat. Un échec pendant leur construction détruit les Plane déjà
créées avant de remonter l'erreur. Les bitmaps partagés restent sous la propriété
de `RPG::Cache`, comme le voile d'origine : pas de destruction d'une texture encore
partagée, ni d'accumulation d'un bitmap par combat. Le banc natif libère son cache
en fin d'exécution.

## Résultats

Exécutés avec le Ruby 3.0.6 fourni par Studio :

- **27 tests de comportement, 180 assertions, 0 échec, 0 erreur, 0 ignoré.**
  Les tests météo/gameplay préexistants restent verts, dont Air Lock/Cloud Nine,
  bypass de précision, Crachin, Anti-Brume, Boss, ZVBattleMessages et synchronisation.
- **1 test graphique natif, 571 644 assertions, 0 échec, 0 erreur, sortie 0.**
  La majorité des assertions sont des comparaisons de pixels.
- Neuf compositions : fond herbe de nuit et Marsh jour en 1v1, 2v2 et 3v3 ;
  Marsh matin, coucher de soleil et nuit en 1v1.
- Bords de texture transparents vérifiés ; rendu identique de part et d'autre
  du modulo horizontal. Mouvement visible entre les captures à 0, 3, 6 et 9 s.
- Menu inchangé, coordonnées conservées ; après Rain, Sunny ou None, retour
  à l'image sans brouillard. Plane détruites, cache partagé conservé.
- Même identité des objets graphiques après les updates répétés. Recréation au
  combat suivant et absence de nappes sous None vérifiées.

Mesures de la dernière exécution, sur cette machine :

| Mesure | Résultat |
| --- | --- |
| Mise à jour des trois couches, moyenne sur 6 000 updates | 0,0063 ms/frame |
| Rendu natif avec le voile seul, moyenne sur 300 frames | 0,207 ms/frame |
| Rendu natif avec voile + deux nappes, moyenne sur 300 frames | 0,215 ms/frame |

Le surcoût observé est d'environ **0,008 ms/frame** dans ce banc sans limite de FPS.
Ces mesures courtes varient avec la machine ; elles ne constituent pas une mesure
des performances d'un combat complet. Aucun ralentissement notable observé ici.

## Captures

Série temporelle sur Marsh :
[0 s](tests/mist_captures/motion_0s.png),
[3 s](tests/mist_captures/motion_3s.png),
[6 s](tests/mist_captures/motion_6s.png),
[9 s](tests/mist_captures/motion_9s.png),
[après dissipation](tests/mist_captures/motion_after_clear.png).

Autres vues : [Marsh 3v3](tests/mist_captures/marsh_day_3v3_fog.png),
[Marsh nuit](tests/mist_captures/marsh_night_1v1_fog.png).

Les captures ont été inspectées visuellement. Le banc utilise les vrais Plane,
shader et textures LiteRGSS ; il compose des combattants/barres et un menu de test.
Il ne lance pas les contrôleurs complets BBBB/InfoBars ni un combat interactif.
Les mêmes commandes de reproduction que dans README s'appliquent.

Vérification finale conseillée dans le jeu : lancer un combat Fog sur Marsh,
observer les nappes quelques secondes, utiliser Danse Pluie/Anti-Brume, puis lancer
un second combat. Vérifier aussi un double/triple et les animations désactivées.
