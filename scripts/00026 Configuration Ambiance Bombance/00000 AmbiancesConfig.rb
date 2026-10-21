# frozen_string_literal: true

# CONFIGURATION UTILISATEUR — seul fichier à modifier pour régler les ambiances.
# Les nuages restent ceux des tilesets/événements : true ne crée aucune texture.
# :native = conserver les nuages existants ; false = masquer uniquement clouds.
# Aucun de ces réglages ne désactive le Fog météo ou une autre texture de brume.
module BombanceAmbiance
  module Settings
    DEFAULTS = {
      clouds: :native, diffuse_light: false, rays: false, atmospherics: false,
      outdoor: :native, light_profile: :natural, rays_profile: :forest_sunlight,
      rays_positions: [].freeze, rays_max: nil, lunar_rays: false,
      fireflies: false, fireflies_profile: :natural_fireflies, fireflies_zones: [].freeze,
      falling_leaves: false, falling_leaves_profile: :enchanted_leaves,
      map_ambient_overlay: false, map_ambient_overlay_texture: nil,
      map_ambient_overlay_profile: :village_night
    }.freeze

    # Groupes facultatifs, appliqués dans l'ordre ; une map prime sur son groupe.
    # Exemple : routes: { maps: [27, 28], effects: { diffuse_light: true } }
    GROUPS = {}.freeze

    # V6 : PNG complet dans graphics/fogs, sans repetition ni halo genere.
    # minutes TJN => pourcentage de max_opacity. TJN desactive => calque absent.
    MAP_AMBIENT_OVERLAY_PROFILES = {
      village_night: {
        max_opacity: 128, blend_type: 0, z: 2900,
        pixels_per_tile: 32, scale: 1.0, offset_x: 0, offset_y: 0,
        time_points: [[0, 100].freeze, [420, 100].freeze, [540, 50].freeze,
                      [660, 0].freeze, [1140, 0].freeze, [1200, 50].freeze,
                      [1230, 100].freeze, [1440, 100].freeze].freeze
      }.freeze
    }.freeze

    MAPS = {
        23 => {
        map_ambient_overlay: true,
        map_ambient_overlay_texture: 'BourgGuignon_Light',
        map_ambient_overlay_profile: :village_night,
        clouds: :native,
        diffuse_light: true,
        outdoor: true,

        rays: true,
        rays_profile: :forest_sunlight,
        rays_max: 10,
        lunar_rays: true,

        fireflies: true,
        fireflies_profile: :natural_fireflies,

        # Pieds des rayons en coordonnées locales.
        # Les trois premiers sont prioritaires la nuit.
        rays_positions: [
          # 1-3 : rayons prioritaires et lunaires
          # Place centrale
          { x: 34.0, y: 18.0, width: 0.90, length: 0.90 }.freeze,
          # Chemin central entre les champs
          { x: 34.0, y: 29.0, width: 0.85, length: 0.95 }.freeze,
          # Jardins près du bâtiment sud-est
          { x: 53.0, y: 43.0, width: 0.85, length: 0.90 }.freeze,

          # 4-6 : maisons et champs
          # Devant la maison nord-ouest
          { x: 19.0, y: 17.0, width: 0.85, length: 0.85 }.freeze,
          # Devant la maison nord-est
          { x: 45.0, y: 17.0, width: 0.90, length: 0.85 }.freeze,
          # Champs de tournesols ouest
          { x: 23.0, y: 30.0, width: 0.85, length: 0.95 }.freeze,

          # 7-8 : champs et jardins
          # Champs de tournesols est
          { x: 42.0, y: 30.0, width: 0.90, length: 0.95 }.freeze,
          # Jardin au nord-est
          { x: 58.0, y: 15.0, width: 0.85, length: 0.90 }.freeze,

          # 9-10 : sud du village
          # Bord de l'étang
          { x: 57.0, y: 31.0, width: 0.85, length: 0.90 }.freeze,
          # Chemin de sortie sud
          { x: 35.0, y: 45.0, width: 0.85, length: 0.90 }.freeze
        ].freeze,

        # Rectangles de lucioles : uniquement végétation.
        # x/y = coin supérieur gauche.
        fireflies_zones: [
          # ===== NORD =====
          # Fleurs près de la maison nord-ouest
          { x: 13.0, y: 14.0, width: 3.0, height: 5.0, count: 5 }.freeze,

          # Jardinière de la maison nord-ouest
          { x: 23.0, y: 14.0, width: 4.0, height: 1.5, count: 3 }.freeze,

          # Jardinière de la maison nord-est
          { x: 40.0, y: 14.0, width: 4.0, height: 1.5, count: 3 }.freeze,

          # Herbes du jardin nord-est
          { x: 53.0, y: 10.0, width: 9.0, height: 5.0, count: 7 }.freeze,

          # ===== CHAMPS OUEST =====
          # Tournesols au nord de la maison
          { x: 12.5, y: 19.0, width: 10.0, height: 3.0, count: 7 }.freeze,

          # Grand champ de tournesols ouest
          { x: 12.5, y: 25.0, width: 10.0, height: 11.0, count: 8 }.freeze,

          # Champ au sud-ouest
          { x: 23.0, y: 29.0, width: 8.0, height: 7.0, count: 7 }.freeze,

          # ===== CHAMPS EST =====
          # Tournesols au nord de la maison
          { x: 36.0, y: 19.0, width: 11.0, height: 3.0, count: 7 }.freeze,

          # Champ de tournesols nord-est
          { x: 47.0, y: 19.0, width: 14.0, height: 3.0, count: 7 }.freeze,

          # Champ au sud de la maison
          { x: 36.0, y: 29.0, width: 9.0, height: 7.0, count: 8 }.freeze,

          # ===== JARDINS SUD-EST =====
          # Fleurs près de l'étang
          { x: 47.0, y: 24.0, width: 5.0, height: 5.0, count: 5 }.freeze,

          # Fleurs près du bâtiment sud-est
          { x: 43.0, y: 40.0, width: 4.0, height: 5.0, count: 5 }.freeze,

          # Parterres au sud du village
          { x: 35.0, y: 45.0, width: 5.0, height: 3.0, count: 5 }.freeze
        ].freeze
      }.freeze,
      27 => {
        clouds: true, diffuse_light: true, outdoor: true,
        rays: true, rays_profile: :forest_sunlight, rays_max: 10, lunar_rays: true,
        fireflies: true, fireflies_profile: :natural_fireflies,
        # Rectangles en tuiles : x/y = coin supérieur gauche, pas le centre.
        # Massif fleuri sud, clairière centrale, herbes/fleurs à l'est.               
        fireflies_zones: [
          # ===== NORD =====
          # Fleurs orangées, près de l'entrée nord
          { x: 51.0, y: 8.0, width: 2.0, height: 2.0, count: 4 }.freeze,
          # Grandes hautes herbes au nord
          { x: 60.0, y: 8.0, width: 6.0, height: 4.0, count: 6 }.freeze,
          # Fleurs multicolores, extrémité nord-est
          { x: 73.0, y: 8.0, width: 2.0, height: 2.0, count: 4 }.freeze,
          # ===== CENTRE / GROTTE =====
          # Hautes herbes au-dessus de la grotte
          { x: 64.0, y: 16.0, width: 4.0, height: 4.0, count: 5 }.freeze,
          # Fleurs au pied des arbres près de la grotte
          { x: 60.0, y: 18.0, width: 2.0, height: 2.0, count: 4 }.freeze,
          # Hautes herbes au nord-est de la grotte
          { x: 70.0, y: 14.0, width: 5.0, height: 4.0, count: 5 }.freeze,
          # Fleurs à l'est de la grotte
          { x: 72.5, y: 20.5, width: 2.0, height: 2.0, count: 4 }.freeze,
          # Fleurs à l'extrémité est
          { x: 80.5, y: 23.5, width: 2.0, height: 3.0, count: 4 }.freeze,
          # ===== CENTRE-OUEST =====
          # Fleurs orangées au bord du chemin
          { x: 45.0, y: 25.0, width: 3.0, height: 1.5, count: 4 }.freeze,
          # Hautes herbes au sud de la grotte
          { x: 56.0, y: 27.0, width: 7.0, height: 3.5, count: 6 }.freeze,
          # ===== SUD-OUEST =====
          # Fleurs violettes de la clairière ouest
          { x: 26.0, y: 31.0, width: 2.5, height: 2.5, count: 5 }.freeze,
          # Hautes herbes de la clairière ouest
          { x: 31.0, y: 31.0, width: 6.0, height: 4.0, count: 5 }.freeze,
          # Fleurs roses de la clairière centrale
          { x: 39.0, y: 31.0, width: 4.0, height: 2.5, count: 5 }.freeze,
          # Hautes herbes à droite des fleurs
          { x: 44.0, y: 31.0, width: 6.0, height: 4.0, count: 5 }.freeze,
          # ===== SUD-EST =====
          # Fleurs multicolores près du panneau
          { x: 55.0, y: 36.0, width: 3.0, height: 3.0, count: 5 }.freeze,
          # Grandes hautes herbes près de la sortie sud
          { x: 63.0, y: 36.0, width: 6.0, height: 5.0, count: 6 }.freeze
        ].freeze,
        # Pied de chaque rayon en TUILES locales (fractions autorisées).
        # Placements éditoriaux : aucune détection automatique des arbres.
        # width/length/opacity = multiplicateurs ; angle = ajout en degrés.
        rays_positions: [
          # 1-3 : rayons prioritaires, également lunaires
          { x: 35.0, y: 22.5, width: 0.90, length: 1.00 }.freeze,
          { x: 52.0, y: 22.5, width: 0.85, length: 0.90 }.freeze,
          { x: 54.0, y: 34.5, width: 0.95, length: 1.00 }.freeze,
          # 4-6 : chemins et clairières
          { x: 23.0, y: 31.5, width: 0.80, length: 0.85 }.freeze,
          { x: 37.5, y: 29.0, width: 0.90, length: 0.90 }.freeze,
          { x: 46.0, y: 19.5, width: 0.85, length: 0.95 }.freeze,
          # 7-8 : clairières du nord
          { x: 51.0, y: 11.0, width: 0.85, length: 0.85 }.freeze,
          { x: 65.5, y: 10.0, width: 0.95, length: 1.00 }.freeze,
          # 9-10 : chemins de l'est
          { x: 72.5, y: 22.0, width: 0.85, length: 0.90 }.freeze,
          { x: 61.0, y: 29.5, width: 0.80, length: 0.85 }.freeze
        ].freeze
      }.freeze,
      # Foret Enchantee actuelle : map 35, 130 x 100, tileset 30 (_30).
      # Fog natif conserve : eterna-forest-style-fog2, zoom 100, opacite 70,
      # vitesse 0/0. FogFix donne 0.5 ; repetition tous les 32 x 20 carreaux.
      # Pieds mesures dans les ouvertures : texture = (x * 32, y * 32) modulo.
      35 => {
        clouds: :native, diffuse_light: false, outdoor: true,
        rays: true, rays_profile: :enchanted_forest_sunlight, rays_max: 8,
        lunar_rays: false, fireflies: true, fireflies_profile: :natural_fireflies,
        falling_leaves: true, falling_leaves_profile: :enchanted_leaves,
        rays_positions: [
          { x: 35.52, y: 66.46, width: 0.85, length: 0.90 }.freeze, # Clairiere ouest
          { x: 81.07, y: 55.49, width: 1.00, length: 1.00 }.freeze, # Prairie de la maison
          { x: 100.22, y: 36.85, width: 0.85, length: 0.85 }.freeze, # Carrefour est
          { x: 71.29, y: 34.44, width: 0.70, length: 0.80, opacity: 0.8 }.freeze,
          { x: 50.49, y: 52.06, width: 0.65, length: 0.75, opacity: 0.7 }.freeze,
          { x: 50.28, y: 82.75, width: 0.95, length: 0.90 }.freeze, # Sous-bois sud
          { x: 35.04, y: 34.07, width: 0.70, length: 0.80, opacity: 0.8 }.freeze,
          { x: 18.28, y: 62.75, width: 0.90, length: 0.90 }.freeze # Clairiere de la souche
        ].freeze,
        fireflies_zones: [
          { x: 23.0, y: 33.0, width: 8.0, height: 5.0, count: 5 }.freeze,
          { x: 42.0, y: 32.0, width: 4.0, height: 4.0, count: 4 }.freeze,
          { x: 33.0, y: 64.0, width: 7.0, height: 5.0, count: 7 }.freeze,
          { x: 19.0, y: 64.0, width: 8.0, height: 4.0, count: 5 }.freeze,
          { x: 50.0, y: 51.0, width: 4.0, height: 6.0, count: 5 }.freeze,
          { x: 47.0, y: 80.0, width: 6.0, height: 4.0, count: 6 }.freeze,
          { x: 75.0, y: 52.0, width: 4.0, height: 7.0, count: 5 }.freeze,
          { x: 84.0, y: 52.0, width: 3.0, height: 8.0, count: 4 }.freeze,
          { x: 76.0, y: 33.0, width: 6.0, height: 3.0, count: 5 }.freeze,
          { x: 104.0, y: 36.0, width: 4.0, height: 6.0, count: 4 }.freeze
        ].freeze
      }.freeze,
      36 => { diffuse_light: false, rays: false, fireflies: false }.freeze,
      80 => { diffuse_light: false, rays: false, fireflies: false }.freeze
    }.freeze

    LIGHT = {
      texture: 'bombance_ambiance/diffuse',
      z: 1, # Sol natif z=0 ; personnages et interfaces au-dessus.
      transition_steps: 180, # Updates logiques PSDK, environ 3 s à 60 Hz.
      step_x: 0.012, step_y: -0.006, # Pixels de texture par update logique.
      variation: 0.06, wave_steps: 1500.0,
      disabled_tjn_period: :day # :morning/:day/:sunset/:night ; nil = lumière OFF.
    }.freeze

    # RGB peu saturé ; opacity = maximum local avant variation et masque alpha.
    # Ces valeurs ne changent jamais le ton global TJN ni celui des événements.
    PROFILES = {
      natural: {
        morning: { rgb: [247, 235, 208].freeze, opacity: 26 }.freeze,
        day:     { rgb: [242, 244, 232].freeze, opacity: 24 }.freeze,
        sunset:  { rgb: [245, 218, 205].freeze, opacity: 25 }.freeze,
        night:   { rgb: [181, 203, 233].freeze, opacity: 14 }.freeze
      }.freeze
    }.freeze

    # La météo effective reste celle de PSDK. Aucun apply_weather ici.
    WEATHER_LIGHT = {
      none: 1.0, rain: 0.3, hardrain: 0.15, fog: 0.0,
      sunny: 0.8, hardsun: 0.5, sandstorm: 0.0, hail: 0.2,
      snow: 0.3, strong_winds: 0.25
    }.freeze
    UNKNOWN_WEATHER_LIGHT = 0.0

    # Viewport carte z=0 : personnages <=999, rayons 2000, nuages 3000.
    # Menus/dialogues : viewports supérieurs, jamais recouverts.
    RAYS = { z: 2000, disabled_tjn_period: nil }.freeze
    # Une texture 7x7, un sprite par luciole. z local au viewport de carte :
    # au-dessus du Fog/nuages (3000), toujours sous les viewports UI/dialogues.
    FIREFLIES_PROFILES = {
      natural_fireflies: {
        texture: 'bombance_ambiance/firefly', z: 3100,
        max_per_zone: 8,
        scale: 1.75,
        halo_strength: 1.0,
        rgb: [255, 250, 165].freeze,
        drift_x: 3.0,
        drift_y: 2.5,
        move_steps: 960.0,
        pulse_steps: 300.0,
        pulse_min: 0.85,
        intensity_variation: 0.05,
        transition_steps: 240, weather_transition_steps: 180,
        # [début, fin] de la période réelle TJN. Densité × count de la zone.        
        periods: {
          morning: {
            density: [0.80, 0.0].freeze,
            opacity: [235, 0].freeze
          }.freeze,
          day: {
            density: [0.0, 0.0].freeze,
            opacity: [0, 0].freeze
          }.freeze,
          sunset: {
            density: [0.65, 0.90].freeze,
            opacity: [220, 250].freeze
          }.freeze,
          night: {
            density: [1.0, 1.0].freeze,
            opacity: [255, 255].freeze
          }.freeze
        }.freeze,
        # Facteur appliqué à l'activité ET à la luminosité. Aucun effet sur Fog.
        weather: {
          none: 1.0, sunny: 1.0, hardsun: 0.5, rain: 0.25, hardrain: 0.0,
          strong_winds: 0.0, sandstorm: 0.0, fog: 0.55, snow: 0.0, hail: 0.0
        }.freeze,
        unknown_weather: 0.0
      }.freeze
    }.freeze

    RAYS_PROFILES = {
      forest_sunlight: {
        texture: 'bombance_ambiance/forest_sunlight',
        count: 10, # Capacité par défaut ; rays_max peut la remplacer par map.
        width: 24.0, length: 108.0, mask_scale: 1.0,
        time_transition_steps: 240, weather_transition_steps: 180,
        # Couverture = obscurcissement moyen à 5 points du pied (0..1).
        # Extinction à 0.20 ; atténuation progressive dès 0.20 - 0.12.
        cloud_threshold: 0.20, cloud_softness: 0.12,
        cloud_fade_steps: 36, # Fondu complet en ~0,6 s à 60 updates/s.
        cloud_sample_steps: 4, # 5 points par rayon actif, tous les 4 ticks.
        density_transition_steps: 180, # Fondu de densité, sans recréer les sprites.
        wave_steps: 2400.0, variation: 0.10, sway_x: 0.4, sway_y: 0.15,
        periods: {
          morning: {
            rgb: [255, 232, 176].freeze,
            opacity: 110,
            angle: 18.0,
            count: 10,
            minimum: 7,
            peak_hour: nil
          }.freeze,

          day: {
            rgb: [255, 249, 226].freeze,
            opacity: 110,
            angle: 24.0,
            count: 10,
            minimum: 10,
            peak_hour: 15.0
          }.freeze,

          sunset: {
            rgb: [255, 207, 151].freeze,
            opacity: 105,
            angle: 32.0,
            count: 10,
            minimum: 7,
            peak_hour: nil
          }.freeze,

          night: {
            rgb: [183, 210, 255].freeze,
            opacity: 78,
            angle: 24.0,
            count: 6,
            minimum: 4,
            peak_hour: 1.0
          }.freeze
        }.freeze,
        weather: {
          none: 1.0, sunny: 1.0, hardsun: 1.0, rain: 0.08,
          hardrain: 0.0, fog: 0.0, sandstorm: 0.0,
          hail: 0.0, snow: 0.0, strong_winds: 0.0
        }.freeze,
        unknown_weather: 0.0
      }.freeze,
      enchanted_forest_sunlight: {
        texture: 'bombance_ambiance/forest_sunlight', count: 8,
        width: 20.0, length: 90.0, mask_scale: 1.0,
        time_transition_steps: 240, weather_transition_steps: 180,
        cloud_threshold: 0.20, cloud_softness: 0.12,
        cloud_fade_steps: 36, cloud_sample_steps: 4, density_transition_steps: 240,
        wave_steps: 2400.0, variation: 0.08, sway_x: 0.2, sway_y: 0.1,
        periods: {
          morning: { rgb: [255, 236, 196].freeze, opacity: 65, angle: 24.0,
                     count: 5, minimum: 2, peak_hour: nil }.freeze,
          day: { rgb: [255, 248, 224].freeze, opacity: 82, angle: 24.0,
                 count: 8, minimum: 6, peak_hour: 15.0 }.freeze,
          sunset: { rgb: [255, 213, 165].freeze, opacity: 52, angle: 24.0,
                    count: 4, minimum: 1, peak_hour: nil }.freeze,
          night: { rgb: [183, 210, 255].freeze, opacity: 0, angle: 24.0,
                   count: 0, minimum: 0, peak_hour: nil }.freeze
        }.freeze,
        weather: {
          none: 1.0, sunny: 1.0, hardsun: 1.0, rain: 0.08, hardrain: 0.0,
          fog: 0.0, sandstorm: 0.0, hail: 0.0, snow: 0.0, strong_winds: 0.0
        }.freeze,
        unknown_weather: 0.0
      }.freeze
    }.freeze

    # Unites : pixels / update logique (60 Hz), durees en updates logiques.
    # count = pool fixe ; ~18-24 visibles en regime etabli sur 320 x 240.
    FALLING_LEAVES_PROFILES = {
      enchanted_leaves: {
        texture: 'bombance_ambiance/enchanted_leaves', frame_size: 16, variants: 3,
        count: 24, seed: 3505, z: 1000, # Comme la meteo native, sous fog et UI.
        fall_speed: 0.40, drift_x: 0.09, speed_variation: 0.22,
        sway_amplitude: 3.5, sway_steps: 330.0, rotation: 18.0,
        opacity: 205, opacity_variation: 0.18, scale: 1.0, scale_variation: 0.12,
        tint: 210,
        # Repetitions volontaires : majorite verte, quelques touches dorees.
        colors: [[126, 166, 84], [126, 166, 84], [143, 180, 94],
                 [143, 180, 94], [170, 184, 97], [170, 184, 97], [201, 181, 101]].map(&:freeze).freeze,
        margin: 10, respawn_steps: 90, fade_steps: 90, weather_transition_steps: 180,
        weather: {
          none: { density: 1.0, fall: 1.0, wind: 1.0 }.freeze,
          sunny: { density: 1.0, fall: 1.0, wind: 1.0 }.freeze,
          hardsun: { density: 0.8, fall: 1.0, wind: 1.0 }.freeze,
          rain: { density: 0.7, fall: 1.15, wind: 1.5 }.freeze,
          hardrain: { density: 0.4, fall: 1.35, wind: 2.4 }.freeze,
          strong_winds: { density: 0.8, fall: 1.3, wind: 3.5 }.freeze,
          fog: { density: 0.85, fall: 1.0, wind: 0.7 }.freeze,
          snow: { density: 0.0, fall: 1.0, wind: 1.0 }.freeze,
          hail: { density: 0.0, fall: 1.0, wind: 1.0 }.freeze,
          sandstorm: { density: 0.0, fall: 1.0, wind: 1.0 }.freeze
        }.freeze,
        unknown_weather: { density: 0.0, fall: 1.0, wind: 1.0 }.freeze
      }.freeze
    }.freeze
  end
end
