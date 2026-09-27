# Critical Health Audio
#
# Author : Raty
# License : MIT
#
# Documentation :
# https://github.com/RatyHub/Critical-Health-Audio


module Configs
  module Project
    class CriticalHealthAudio
      FILENAME = File.join('plugins', 'critical_health_audio_config')

      attr_accessor :mode
      attr_accessor :sound_effect_mode
      attr_accessor :bgm_replacement_mode

      def initialize
        @mode = 'sound_effect_mode'
        @sound_effect_mode = {
          filename: 'audio/se/low_health',
          volume: 100,
          bgm_volume_reduction_percent: 50
        }
        @bgm_replacement_mode = {
          filename: 'audio/bgm/battle_low_hp',
          volume: 100,
          fade_in_ms: 500,
          restore_fade_in_ms: 500
        }
      end

      def to_h
        return {
          mode: @mode,
          sound_effect_mode: @sound_effect_mode,
          bgm_replacement_mode: @bgm_replacement_mode
        }
      end
    end
  end

  register(
    :critical_health_audio,
    Project::CriticalHealthAudio::FILENAME,
    :json,
    true,
    Project::CriticalHealthAudio
  )
end

module CriticalHealthAudio
  @active = false
  @bgm_reduced = false
  @low_health_bgm_active = false
  @critical_health_audio_start_ready = false
  @sound_effect_hp_target = nil
  @base_bgm = nil
  @base_bgm_position = nil
  @current_bgm = nil

  class << self
    attr_reader :current_bgm

    def active?
      @active || @low_health_bgm_active
    end

    def reload_config
      unless PSDK_CONFIG.release?
        Configs.register(
          :critical_health_audio,
          Configs::Project::CriticalHealthAudio::FILENAME,
          :json,
          true,
          Configs::Project::CriticalHealthAudio
        )
      end
      @config = load_config
      return true
    end

    def register_bgm(bgm)
      clear_low_health_bgm_state
      @current_bgm = bgm
      refresh_bgm_volume if @active || @bgm_reduced
    end

    def clear_bgm
      @current_bgm = nil
      @bgm_reduced = false
      clear_low_health_bgm_state
    end

    def update(scene)
      return update_bgm_replacement(scene) if config[:mode] == :bgm_replacement

      update_sound_effect(scene)
    end

    def update_sound_effect(scene)
      needed = sound_effect_needed?(scene)

      needed ? start_sound_effect : stop_sound_effect
      refresh_bgm_volume if active? || @bgm_reduced
      refresh_alarm_volume if active?
    end

    def update_bgm_replacement(scene)
      needed = bgm_replacement_needed?(scene)

      needed ? start_low_health_bgm : stop_low_health_bgm
    end

    def start_sound_effect
      return if @active

      @active = true
      Audio.critical_health_audio_play(config[:sound_effect_mode][:filename], config[:sound_effect_mode][:volume], 100)
    end

    def stop(restore_bgm: true, stop_bgm: false)
      stop_sound_effect
      stop_low_health_bgm(restore_bgm, stop_bgm)
    end

    def stop_sound_effect
      @sound_effect_hp_target = nil
      return unless @active || @bgm_reduced

      Audio.critical_health_audio_stop
      @active = false
      restore_bgm_volume
    end

    def config
      @config ||= load_config
    end

    def load_config
      return build_config(read_config_file)
    rescue StandardError
      return default_config
    end

    def read_config_file
      data = Configs.critical_health_audio.to_h
      return data if data.is_a?(Hash)

      return {}
    end

    def build_config(data)
      defaults = default_config
      sound_effect_data = data[:sound_effect_mode].is_a?(Hash) ? data[:sound_effect_mode] : {}
      bgm_replacement_data = data[:bgm_replacement_mode].is_a?(Hash) ? data[:bgm_replacement_mode] : {}
      return {
        mode: parse_mode(data[:mode], defaults[:mode]),
        sound_effect_mode: {
          filename: parse_filename(sound_effect_data[:filename], defaults[:sound_effect_mode][:filename]),
          volume: parse_percent(sound_effect_data[:volume], defaults[:sound_effect_mode][:volume]),
          bgm_volume_reduction_percent: parse_percent(sound_effect_data[:bgm_volume_reduction_percent], defaults[:sound_effect_mode][:bgm_volume_reduction_percent])
        },
        bgm_replacement_mode: {
          filename: parse_filename(bgm_replacement_data[:filename], defaults[:bgm_replacement_mode][:filename]),
          volume: parse_percent(bgm_replacement_data[:volume], defaults[:bgm_replacement_mode][:volume]),
          fade_in_ms: parse_duration_ms(bgm_replacement_data[:fade_in_ms], defaults[:bgm_replacement_mode][:fade_in_ms]),
          restore_fade_in_ms: parse_duration_ms(bgm_replacement_data[:restore_fade_in_ms], defaults[:bgm_replacement_mode][:restore_fade_in_ms])
        }
      }
    end

    def default_config
      return {
        mode: :sound_effect,
        sound_effect_mode: {
          filename: 'audio/se/low_health',
          volume: 100,
          bgm_volume_reduction_percent: 35
        },
        bgm_replacement_mode: {
          filename: 'audio/bgm/battle_low_hp',
          volume: 100,
          fade_in_ms: 500,
          restore_fade_in_ms: 500
        }
      }
    end

    def config_filename
      return File.join('Data', 'configs', 'plugins', 'critical_health_audio_config.json')
    end

    def parse_mode(value, fallback)
      return fallback if value.nil?

      normalized = value.to_s.strip.downcase
      return :sound_effect if %w[1 sound_effect sound_effect_mode se].include?(normalized)
      return :bgm_replacement if %w[2 bgm_replacement bgm_replacement_mode bgm music].include?(normalized)

      return fallback
    end

    def parse_filename(value, fallback)
      return fallback if value.nil?

      filename = value.to_s.strip
      return filename unless filename.empty?

      return fallback
    end

    def parse_percent(value, fallback)
      return fallback if value.nil?

      return Float(value).clamp(0, 100)
    rescue ArgumentError, TypeError
      return fallback
    end

    def parse_duration_ms(value, fallback)
      return fallback if value.nil?

      return [Float(value).round, 0].max
    rescue ArgumentError, TypeError
      return fallback
    end

    def critical_health?(pokemon)
      pokemon&.from_player_party? && pokemon.alive? && red_hp_bar_state?(pokemon)
    end

    def notify_hp_entered_critical(pokemon)
      return unless config[:mode] == :sound_effect
      return unless critical_health?(pokemon)

      @sound_effect_hp_target = pokemon
    end

    private

    def sound_effect_needed?(scene)
      return false if %i[pre_transition battle_end].include?(scene&.next_update)

      if @sound_effect_hp_target
        target_needed = sound_effect_needed_for_pokemon?(scene, @sound_effect_hp_target)
        return true if target_needed && !player_turn_phase?(scene)

        current_battler = current_player_battler(scene)
        return true if target_needed && current_battler == @sound_effect_hp_target

        @sound_effect_hp_target = nil if player_turn_phase?(scene) || !target_needed
      end

      sound_effect_needed_for_pokemon?(scene, current_player_battler(scene))
    end

    def bgm_replacement_needed?(scene)
      return false if %i[pre_transition battle_end].include?(scene&.next_update)
      @critical_health_audio_start_ready ||= player_turn_phase?(scene)
      return false unless @critical_health_audio_start_ready

      red_revealed_player_battlers(scene).any?
    end

    def start_low_health_bgm
      return if @low_health_bgm_active

      @base_bgm = @current_bgm
      @base_bgm_position = Audio.bgm_position
      @low_health_bgm_active = true
      bgm_config = config[:bgm_replacement_mode]
      Audio.critical_health_audio_bgm_play(bgm_config[:filename], bgm_config[:volume], 100, fade_ms: bgm_config[:fade_in_ms], position: 0)
    end

    def stop_low_health_bgm(restore_bgm = true, stop_bgm = false)
      return unless @low_health_bgm_active

      @low_health_bgm_active = false
      restore_base_bgm if restore_bgm
      Audio.bgm_stop if stop_bgm && !restore_bgm
      @base_bgm = nil
      @base_bgm_position = nil
    end

    def restore_base_bgm
      return Audio.bgm_stop unless @base_bgm && bgm_name(@base_bgm).to_s != ''

      Audio.critical_health_audio_bgm_play(
        bgm_audio_filename(@base_bgm),
        bgm_volume(@base_bgm) || 100,
        bgm_pitch(@base_bgm) || 100,
        fade_ms: config[:bgm_replacement_mode][:restore_fade_in_ms],
        position: @base_bgm_position
      )
    end

    def clear_low_health_bgm_state
      @low_health_bgm_active = false
      @critical_health_audio_start_ready = false
      @sound_effect_hp_target = nil
      @base_bgm = nil
      @base_bgm_position = nil
    end

    def refresh_alarm_volume
      Audio.critical_health_audio_volume = config[:sound_effect_mode][:volume]
    end

    def refresh_bgm_volume
      active? ? reduce_bgm_volume : restore_bgm_volume
    end

    def reduce_bgm_volume
      Audio.critical_health_audio_bgm_volume = reduced_bgm_volume
      @bgm_reduced = true
    end

    def restore_bgm_volume
      Audio.critical_health_audio_bgm_volume = current_bgm_volume
      @bgm_reduced = false
    end

    def current_bgm_volume
      volume = @current_bgm&.volume || 100
      volume.to_i.clamp(0, 100)
    end

    def reduced_bgm_volume
      reduction = config[:sound_effect_mode][:bgm_volume_reduction_percent]
      (current_bgm_volume * (100 - reduction) / 100.0).round.clamp(0, 100)
    end

    def red_hp_bar_state?(pokemon)
      # UI::Bar uses the first spritesheet row as background; state 0 is the red HP row.
      hp_bar_state_for_rate(pokemon.hp_rate) == 0
    end

    def current_player_battler_sprite(scene, pokemon)
      visual = safe_call(scene, :visual)
      return unless visual&.respond_to?(:battler_sprite)

      visual.battler_sprite(pokemon.bank, pokemon.position)
    rescue StandardError
      nil
    end

    def player_turn_phase?(scene)
      %i[player_action_choice skill_choice target_choice item_choice switch_choice shift_choice].include?(scene&.next_update)
    end

    def sound_effect_needed_for_pokemon?(scene, pokemon)
      critical_health?(pokemon) && player_battler_visible_on_field?(scene, pokemon)
    end

    def current_player_battler(scene)
      index = current_player_battler_index(scene)
      return unless index && scene&.respond_to?(:logic)

      scene.logic.battler(0, index)
    rescue StandardError
      nil
    end

    def current_player_battler_index(scene)
      return unless player_turn_phase?(scene)
      return unless scene&.respond_to?(:battle_info) && scene&.respond_to?(:player_actions)

      index = scene.player_actions.size
      max_index = scene.battle_info.vs_type.to_i - 1
      return if max_index.negative? || index > max_index

      index
    rescue StandardError
      nil
    end

    def red_revealed_player_battlers(scene)
      player_battlers(scene).select do |pokemon|
        critical_health?(pokemon) && player_battler_visible_on_field?(scene, pokemon)
      end
    end

    def player_battler_visible_on_field?(scene, pokemon)
      sprite = current_player_battler_sprite(scene, pokemon)
      return false unless sprite

      safe_call(sprite, :visible) && safe_call(sprite, :in?)
    end

    def player_battlers(scene)
      return [] unless scene&.respond_to?(:battle_info) && scene&.respond_to?(:logic)

      count = scene.battle_info.vs_type.to_i
      count = 1 if count <= 0
      (0...count).map { |position| scene.logic.battler(0, position) }.compact
    rescue StandardError
      []
    end

    def hp_bar_state_for_rate(rate)
      return unless rate

      value = rate.to_f
      value = 0 if value <= 0
      value = 1 if value >= 1
      state_count = hp_bar_state_count
      state = (value * state_count).to_i
      state >= state_count ? state_count - 1 : state
    end

    def hp_bar_state_count
      return BattleUI::InfoBar::HP_BAR_INFO[4] if defined?(BattleUI::InfoBar::HP_BAR_INFO)

      6
    end

    def safe_call(object, method_name)
      return unless object&.respond_to?(method_name)

      object.public_send(method_name)
    rescue StandardError
      nil
    end

    def bgm_audio_filename(bgm)
      name = bgm_name(bgm).to_s
      return name if name.downcase.start_with?('audio/')

      "Audio/BGM/#{name}"
    end

    def bgm_name(bgm)
      return unless bgm&.respond_to?(:name)

      bgm.name
    rescue StandardError
      nil
    end

    def bgm_volume(bgm)
      return unless bgm&.respond_to?(:volume)

      bgm.volume
    rescue StandardError
      nil
    end

    def bgm_pitch(bgm)
      return unless bgm&.respond_to?(:pitch)

      bgm.pitch
    rescue StandardError
      nil
    end
  end
end

module Audio
  class << self
    def critical_health_audio_play(filename, volume = 100, pitch = 100)
      effective_volume = critical_health_audio_effective_sfx_volume(volume)
      @driver&.play_music(:critical_health_audio, filename, effective_volume, pitch, false, 0)
    end

    def critical_health_audio_stop
      @driver&.stop_channel(:critical_health_audio)
    end

    def critical_health_audio_volume=(volume)
      effective_volume = critical_health_audio_effective_sfx_volume(volume)
      @driver&.set_channel_volume(:critical_health_audio, effective_volume)
    end

    def critical_health_audio_bgm_volume=(volume)
      @driver&.set_channel_volume(:bgm, critical_health_audio_effective_music_volume(volume))
    end

    def critical_health_audio_bgm_play(filename, volume = 100, pitch = 100, fade_ms: 0, position: nil)
      fade_in = fade_ms.to_i.positive? ? fade_ms.to_i : false
      bgm_play(filename, volume, pitch, fade_in, position: position)
    end

    def critical_health_audio_effective_sfx_volume(volume)
      volume.to_i.clamp(0, 100) * sfx_volume / 100
    end

    def critical_health_audio_effective_music_volume(volume)
      volume.to_i.clamp(0, 100) * music_volume / 100
    end

    private

    def effective_sfx_volume(volume)
      critical_health_audio_effective_sfx_volume(volume)
    end

    def effective_music_volume(volume)
      critical_health_audio_effective_music_volume(volume)
    end
  end

  if const_defined?(:ALL_CHANNELS_SYM) && !ALL_CHANNELS_SYM.frozen? && !ALL_CHANNELS_SYM.include?(:critical_health_audio)
    ALL_CHANNELS_SYM << :critical_health_audio
  end
end

class Game_System
  module CriticalHealthAudioPatch
    def bgm_play(bgm, position: nil)
      result = super
      CriticalHealthAudio.register_bgm(bgm)
      result
    end

    def temporary_bgm_play(bgm, position: nil)
      result = super
      CriticalHealthAudio.register_bgm(bgm)
      result
    end

    def bgm_stop
      CriticalHealthAudio.stop(restore_bgm: false)
      result = super
      CriticalHealthAudio.clear_bgm
      result
    end

    def bgm_fade(time)
      CriticalHealthAudio.stop(restore_bgm: false)
      result = super
      CriticalHealthAudio.clear_bgm
      result
    end
  end

  prepend CriticalHealthAudioPatch unless ancestors.include?(CriticalHealthAudioPatch)
end

module Battle
  class Visual
    class HPAnimation
      module CriticalHealthAudioPatch
        def update(...)
          was_critical = CriticalHealthAudio.critical_health?(@target)
          super
          CriticalHealthAudio.notify_hp_entered_critical(@target) unless was_critical
        end

        def final_hp_refresh
          was_critical = CriticalHealthAudio.critical_health?(@target)
          super
          CriticalHealthAudio.notify_hp_entered_critical(@target) unless was_critical
        end
      end

      prepend CriticalHealthAudioPatch unless ancestors.include?(CriticalHealthAudioPatch)
    end

    module CriticalHealthAudioPatch
      def update(...)
        super
        CriticalHealthAudio.update(@scene)
      end

      def dispose
        CriticalHealthAudio.stop(restore_bgm: false, stop_bgm: true)
        super
      end
    end

    prepend CriticalHealthAudioPatch unless ancestors.include?(CriticalHealthAudioPatch)
  end
end
