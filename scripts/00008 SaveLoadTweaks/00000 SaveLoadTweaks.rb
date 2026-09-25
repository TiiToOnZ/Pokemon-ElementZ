# Save Load Tweaks - originally written by FrivolousAqua.
# Local PSDK 26.60 extensions. Serialization, configuration and hooks stay native.
require 'tempfile'

module SaveLoadTweaks
  class WriteError < StandardError; end

  # Stage on the same volume. Keep a rollback copy until final verification.
  module Files
    module_function

    def stage(filename, bytes)
      file = Tempfile.create(['.save-load-tweaks-', '.tmp'], File.dirname(filename))
      path = file.path
      file.close
      begin
        File.binwrite(path, bytes)
        File.open(path, 'r+b') { |handle| handle.fsync }
        verify(path, bytes)
        path
      rescue StandardError
        File.delete(path) if File.exist?(path)
        raise
      end
    end

    def verify(filename, bytes)
      raise WriteError, 'Saved bytes differ from the serialized state' unless File.binread(filename) == bytes
    end

    def write(filename, bytes, backup, rotate_backup:)
      original = File.binread(filename) if File.exist?(filename)
      staged = stage(filename, bytes)
      rollback = stage(filename, original) if original
      installed = false
      File.rename(staged, filename)
      installed = true
      verify(filename, bytes)
      # An invalid principal must never replace an existing (possibly good) .bak.
      File.rename(rollback, backup) if original && rotate_backup
      true
    rescue StandardError
      if installed
        begin
          original ? File.rename(rollback, filename) : File.delete(filename)
        rescue StandardError
          # If rollback itself is denied, retain its file for manual recovery.
          rollback = nil
        end
      end
      raise
    ensure
      [staged, rollback].compact.each do |path|
        begin
          File.delete(path) if File.exist?(path)
        rescue StandardError
          # Cleanup must not turn a confirmed write into a false failure.
        end
      end
    end
  end

  module SaveClass
    attr_reader :save_load_tweaks_write_succeeded, :save_load_tweaks_write_attempted

    # Preserve Save.save's native return value, including no_file mode.
    # Only the scene consumes the separate physical-write result.
    def save(*args)
      @save_load_tweaks_write_succeeded = false
      @save_load_tweaks_write_attempted = false
      super
    rescue StandardError
      @save_load_tweaks_write_succeeded = false
      raise
    end

    private

    # Native save_file swallows I/O errors; Save.save ignores its return value.
    # Only the writer is replaced: serialization and before/after hooks stay native.
    def save_file(filename, bytes)
      @save_load_tweaks_write_attempted = true
      @save_load_tweaks_write_succeeded = Files.write(
        filename, bytes, backup_filename(filename), rotate_backup: valid_principal?(filename)
      )
    rescue StandardError
      @save_load_tweaks_write_succeeded = false
      $scene.display_message_and_wait(text_get(26, 19))
      false
    end

    def valid_principal?(filename)
      previous_state = PFM.game_state
      previous_party = $pokemon_party
      # Native header/decryption/Marshal handling, without applying parameters.
      state = load(filename, no_load_parameter: true)
      state.is_a?(PFM::GameState)
    ensure
      PFM.game_state = previous_state
      $pokemon_party = previous_party
    end
  end

  module LoadScene
    def initialize
      super
      # Load#initialize discards [nil], even for an existing invalid file.
      # Restore it before the title checks should_make_new_game?.
      if @all_saves.empty? && @save_load_tweaks_initial_saves&.size == 1
        filename = save_load_tweaks_filename(0)
        @all_saves = @save_load_tweaks_initial_saves if File.file?(filename) || File.file?("#{filename}.bak")
      end
      @save_load_tweaks_initial_saves = nil
    end

    private

    def save_load_tweaks_filename(index)
      previous_index = GamePlay::Save.save_index
      GamePlay::Save.save_index = Configs.save_config.single_save? ? 0 : index + 1
      GamePlay::Save.save_filename
    ensure
      GamePlay::Save.save_index = previous_index
    end

    def load_all_saves
      saves = super
      saves.map! { |state| state.is_a?(PFM::GameState) ? state : nil }
      # Expose backup-only slots without restoring them automatically.
      unless Configs.save_config.single_save?
        base = save_load_tweaks_filename(0).sub(/-1\z/, '')
        pattern = /\A#{Regexp.escape(base)}-([1-9][0-9]*)\.bak\z/
        Dir.glob("#{base}-*.bak").each do |path|
          match = pattern.match(path)
          next unless match && File.file?(path)
          number = match[1].to_i
          next if !Configs.save_config.unlimited_saves? && number > Configs.save_config.maximum_save_count
          saves[number - 1] = nil if number > saves.size
        end
      end
      @save_load_tweaks_initial_saves = saves.dup
      saves
    end

    def load_sign_data
      super
      # Keep native layout/data binding; correct only empty-slot presentation.
      @signs.each_with_index do |sign, offset|
        index = @index + offset - 1
        next if index < 0 || index >= @all_saves.size || @all_saves[index]
        next if !Configs.save_config.unlimited_saves? && index >= Configs.save_config.maximum_save_count
        sign.data = :new unless File.file?(save_load_tweaks_filename(index))
      end
    end

    def action_a
      Graphics.sort_z
      filename = save_load_tweaks_filename(@index)
      return super if @all_saves[@index]
      principal = File.file?(filename)
      backup = File.file?("#{filename}.bak")
      return super unless principal || backup

      play_buzzer_se
      display_message(ext_text(311_110, 4)) if principal
      display_message(ext_text(311_110, 5)) if backup
      choice = display_message(ext_text(311_110, 6), 2, ext_text(311_110, 1), ext_text(311_110, 2))
      return unless choice == 0

      GamePlay::Save.save_index = Configs.save_config.single_save? ? 0 : @index + 1
      create_new_game
    end
  end

  module SaveScene
    # Boolean derived from the writer, never from the native serialized String.
    def save_game
      super
      success = GamePlay::Save.save_load_tweaks_write_succeeded
      display_message_and_wait(text_get(26, 19)) unless success || GamePlay::Save.save_load_tweaks_write_attempted
      success
    rescue StandardError
      display_message_and_wait(text_get(26, 19))
      false
    end

    private

    # Native action_a announces success even on failure, so it cannot be called.
    def action_a
      Graphics.sort_z
      play_decision_se
      filename = save_load_tweaks_filename(@index)
      if File.file?(filename)
        choice = display_message(ext_text(311_110, 0), 2, ext_text(311_110, 1), ext_text(311_110, 2))
        return unless choice == 0
      end

      GamePlay::Save.save_index = Configs.save_config.single_save? ? 0 : @index + 1
      return unless save_game

      @saved = true
      @all_saves[@index] = PFM.game_state
      load_sign_data
      play_save_se
      display_message(ext_text(311_110, 3))
      @running = false
    end
  end
end

GamePlay::Save.singleton_class.prepend(SaveLoadTweaks::SaveClass)
GamePlay::Load.prepend(SaveLoadTweaks::LoadScene)
GamePlay::Save.prepend(SaveLoadTweaks::SaveScene)
