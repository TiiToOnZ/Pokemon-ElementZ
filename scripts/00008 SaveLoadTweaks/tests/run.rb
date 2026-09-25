require_relative 'support'

class SaveLoadTest
  def test_no_save
    instance = scene(GamePlay::Load)
    assert(instance.should_make_new_game?)
    activate(instance)
    assert(instance.events.include?([:new_game]))
    equal([], messages(instance))
    equal([], Dir.children('.'))
  end

  def test_valid_load_delegates_to_native_action
    original = fixture
    current = PFM.game_state
    instance = scene(GamePlay::Load)
    assert(!instance.should_make_new_game?)
    activate(instance)
    assert(instance.events.include?([:load_game, 'Old player']))
    equal([], messages(instance))
    equal(original, File.binread(filename))
    assert(current.equal?(PFM.game_state))
  end

  def test_empty_hole_is_new_not_corrupt
    fixture(1)
    fixture(3)
    instance = scene(GamePlay::Load, 1)
    instance.__send__(:load_sign_data)
    equal(:new, instance.instance_variable_get(:@signs)[1].data)
    activate(instance)
    equal([], messages(instance))
    assert(instance.events.include?([:new_game]))
    equal(2, GamePlay::Save.save_index)
  end

  def test_empty_hole_does_not_ask_overwrite
    fixture(1)
    fixture(3)
    instance = scene(GamePlay::Save, 1)
    activate(instance)
    assert_success(instance)
    assert(!messages(instance).include?(ext_text(311_110, 0)))
    assert(File.file?(filename(2)))
  end

  def test_unique_corrupt_save_is_not_skipped_by_title
    fixture(1, 'broken')
    instance = scene(GamePlay::Load)
    assert(!instance.should_make_new_game?)
    instance.__send__(:load_sign_data)
    equal(:corrupted, instance.instance_variable_get(:@signs)[1].data)
    activate(instance, 1)
    equal([ext_text(311_110, 4), ext_text(311_110, 6)], messages(instance))
    assert(!instance.events.include?([:new_game]))
    equal('broken', File.binread(filename))
  end

  def test_corrupt_slot_among_valid_saves
    fixture(1)
    fixture(2, 'broken')
    instance = scene(GamePlay::Load, 1)
    activate(instance, 0)
    assert(messages(instance).include?(ext_text(311_110, 4)))
    assert(instance.events.include?([:new_game]))
    equal('broken', File.binread(filename(2)))
  end

  def test_corrupt_principal_with_backup_only_informs
    fixture(1, 'broken')
    backup = bytes('Backup player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene(GamePlay::Load)
    activate(instance, 0)
    equal([4, 5, 6].map { |id| ext_text(311_110, id) }, messages(instance))
    assert(instance.events.include?([:new_game]))
    equal('broken', File.binread(filename))
    equal(backup, File.binread("#{filename}.bak"))
  end

  def test_backup_only_slot_is_visible_without_false_corruption
    File.binwrite("#{filename}.bak", bytes)
    instance = scene(GamePlay::Load)
    assert(!instance.should_make_new_game?)
    activate(instance, 1)
    equal([5, 6].map { |id| ext_text(311_110, id) }, messages(instance))
    assert(!File.exist?(filename))
  end

  def test_backup_only_later_slot_and_finite_limit
    File.binwrite("#{filename(3)}.bak", bytes)
    Configs.save_config.maximum_save_count = 2
    assert(scene(GamePlay::Load).should_make_new_game?)
    Configs.save_config.maximum_save_count = 0
    instance = scene(GamePlay::Load, 2)
    equal(3, instance.instance_variable_get(:@all_saves).size)
    activate(instance, 1)
    assert(messages(instance).include?(ext_text(311_110, 5)))
  end

  def test_overwrite_no_leaves_both_files_unchanged
    original = fixture
    backup = bytes('Older player')
    File.binwrite("#{filename}.bak", backup)
    GamePlay::Save.save_index = 3
    instance = scene
    activate(instance, 1)
    equal(false, instance.saved)
    equal(3, GamePlay::Save.save_index)
    equal(original, File.binread(filename))
    equal(backup, File.binread("#{filename}.bak"))
    equal([], $test_hooks)
    choice = instance.events.find { |event| event[0..1] == [:message, ext_text(311_110, 0)] }
    equal(2, choice[2])
    equal([ext_text(311_110, 1), ext_text(311_110, 2)], choice[3])
  end

  def test_overwrite_cancel_does_not_write
    original = fixture
    instance = scene
    # PSDK maps the cancel key to the second choice (index 1).
    activate(instance, 1)
    equal(original, File.binread(filename))
    equal(false, instance.saved)
    assert(!instance.events.include?([:refresh]))
  end

  def test_overwrite_yes_rotates_backup_after_verified_write
    original = fixture
    File.binwrite("#{filename}.bak", bytes('Older player'))
    current = PFM.game_state
    instance = scene
    activate(instance, 0)
    assert_success(instance)
    equal(original, File.binread("#{filename}.bak"))
    restored = GamePlay::Save.load(filename, no_load_parameter: true)
    equal(current.name, restored.name)
    equal(current.user_data, restored.user_data)
    equal(1, messages(instance).count(ext_text(311_110, 0)))
    assert_hooks
    assert_no_staging_files
  end

  def test_success_on_new_slot_keeps_native_serialization
    current = PFM.game_state
    instance = scene
    activate(instance)
    assert_success(instance)
    equal('PKPRT' + Marshal.dump(current), File.binread(filename))
    assert(!File.exist?("#{filename}.bak"))
    assert_hooks
    assert_no_staging_files
  end

  def test_bad_principal_never_replaces_good_backup
    fixture(1, 'broken')
    backup = bytes('Recovery player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    activate(instance, 0)
    assert_success(instance)
    equal(backup, File.binread("#{filename}.bak"))
    assert(messages(instance).include?(ext_text(311_110, 0)))
  end

  def test_backup_only_is_preserved_when_saving
    backup = bytes('Recovery player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    activate(instance)
    assert_success(instance)
    equal(backup, File.binread("#{filename}.bak"))
    assert(!messages(instance).include?(ext_text(311_110, 0)))
  end

  def test_write_failure_has_no_success_effects
    original = fixture
    backup = bytes('Recovery player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    with_fault(File, :binwrite, ->(*) { raise Errno::ENOSPC }) { activate(instance, 0) }
    assert_failure(instance, previous)
    equal(original, File.binread(filename))
    equal(backup, File.binread("#{filename}.bak"))
    assert_hooks
    assert_no_staging_files
  end

  def test_partial_write_is_rejected_before_replacing_principal
    original = fixture
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    fault = ->(write, path, data) { write.call(path, data.byteslice(0, 6)) }
    with_fault(File, :binwrite, fault) { activate(instance, 0) }
    assert_failure(instance, previous)
    equal(original, File.binread(filename))
    assert_no_staging_files
  end

  def test_failed_final_verification_rolls_back_without_touching_backup
    original = fixture
    backup = bytes('Older player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    fault = lambda do |verify, path, data|
      raise SaveLoadTweaks::WriteError, 'Simulated final read mismatch' if File.basename(path) == filename
      verify.call(path, data)
    end
    with_fault(SaveLoadTweaks::Files, :verify, fault) { activate(instance, 0) }
    assert_failure(instance, previous)
    equal(original, File.binread(filename))
    equal(backup, File.binread("#{filename}.bak"))
    assert_no_staging_files
  end

  def test_backup_rotation_failure_rolls_back_principal
    original = fixture
    backup = bytes('Older player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    fault = lambda do |rename, source, destination|
      raise Errno::EACCES if destination.end_with?('.bak')
      rename.call(source, destination)
    end
    with_fault(File, :rename, fault) { activate(instance, 0) }
    assert_failure(instance, previous)
    equal(original, File.binread(filename))
    equal(backup, File.binread("#{filename}.bak"))
    assert_no_staging_files
  end

  def test_install_failure_preserves_both_files
    original = fixture
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    with_fault(File, :rename, ->(*) { raise Errno::EACCES }) { activate(instance, 0) }
    assert_failure(instance, previous)
    equal(original, File.binread(filename))
    assert_no_staging_files
  end

  def test_final_verification_failure_on_new_slot_removes_failed_file
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    fault = lambda do |verify, path, data|
      raise SaveLoadTweaks::WriteError if File.basename(path) == filename
      verify.call(path, data)
    end
    with_fault(SaveLoadTweaks::Files, :verify, fault) { activate(instance) }
    assert_failure(instance, previous)
    assert(!File.exist?(filename))
    assert_no_staging_files
  end

  def test_rollback_denied_retains_recovery_copy_and_existing_backup
    original = fixture
    backup = bytes('Older player')
    File.binwrite("#{filename}.bak", backup)
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    installs = 0
    rename_fault = lambda do |rename, source, destination|
      installs += 1 if File.basename(destination) == filename
      raise Errno::EACCES if installs > 1
      rename.call(source, destination)
    end
    verify_fault = lambda do |verify, path, data|
      raise SaveLoadTweaks::WriteError if File.basename(path) == filename
      verify.call(path, data)
    end
    with_fault(File, :rename, rename_fault) do
      with_fault(SaveLoadTweaks::Files, :verify, verify_fault) { activate(instance, 0) }
    end
    assert_failure(instance, previous)
    equal(backup, File.binread("#{filename}.bak"))
    copies = Dir.glob('.save-load-tweaks-*')
    equal(1, copies.size)
    equal(original, File.binread(copies.first))
  end

  def test_native_truthy_return_after_failure_is_not_a_success_signal
    instance = scene
    result = nil
    with_fault(File, :binwrite, ->(*) { raise Errno::EACCES }) do
      result = GamePlay::Save.save
    end
    assert(result.is_a?(String) && !result.empty?)
    equal(false, GamePlay::Save.save_load_tweaks_write_succeeded)
    equal(false, instance.saved)
    assert(!File.exist?(filename))
  end

  def test_existing_principal_validation_does_not_replace_current_globals
    fixture
    current = PFM.game_state
    party = $pokemon_party
    instance = scene
    activate(instance, 0)
    assert_success(instance)
    assert(PFM.game_state.equal?(current))
    assert($pokemon_party.equal?(party))
  end

  def test_retry_after_failure_then_success
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    with_fault(File, :binwrite, ->(*) { raise Errno::EACCES }) { activate(instance) }
    assert_failure(instance, previous)
    instance.events.clear
    activate(instance)
    assert_success(instance)
  end

  def test_save_result_does_not_reuse_previous_success
    instance = scene
    activate(instance)
    assert_success(instance)
    failed = scene
    previous = failed.instance_variable_get(:@all_saves).dup
    with_fault(File, :binwrite, ->(*) { raise Errno::EACCES }) { activate(failed, 0) }
    assert_failure(failed, previous)
  end

  def test_native_no_file_mode_keeps_return_contract
    scene
    result = GamePlay::Save.save(nil, true)
    equal('PKPRT' + Marshal.dump(PFM.game_state), result)
    equal(false, GamePlay::Save.save_load_tweaks_write_succeeded)
    equal([], Dir.children('.'))
    assert_hooks
  end

  def test_no_game_temp_cannot_be_success
    instance = scene
    previous = instance.instance_variable_get(:@all_saves).dup
    $game_temp = nil
    activate(instance)
    assert_failure(instance, previous)
    equal([], Dir.children('.'))
  end

  def test_non_game_state_payload_is_invalid
    fixture(1, 'PKPRT' + Marshal.dump('not a GameState'))
    instance = scene(GamePlay::Load)
    assert(!instance.should_make_new_game?)
    activate(instance, 1)
    assert(messages(instance).include?(ext_text(311_110, 4)))
  end

  def test_unreadable_save_is_invalid_not_empty
    fixture
    fault = ->(*) { raise Errno::EACCES }
    with_fault(File, :binread, fault) do
      instance = scene(GamePlay::Load)
      assert(!instance.should_make_new_game?)
      activate(instance, 1)
      assert(messages(instance).include?(ext_text(311_110, 4)))
    end
  end

  def test_single_save_empty_then_overwrite
    Configs.save_config.maximum_save_count = 1
    assert(scene(GamePlay::Load).should_make_new_game?)
    first = scene
    activate(first)
    assert_success(first)
    assert(File.file?(filename(0)))
    equal(0, GamePlay::Save.save_index)
    second = scene
    activate(second, 1)
    equal(false, second.saved)
    assert(messages(second).include?(ext_text(311_110, 0)))
    activate(second, 0)
    assert_success(second)
    assert(File.file?("#{filename(0)}.bak"))
  end

  def test_single_save_corrupt_is_visible_and_requires_confirmation
    Configs.save_config.maximum_save_count = 1
    fixture(0, 'broken')
    load_scene = scene(GamePlay::Load)
    assert(!load_scene.should_make_new_game?)
    activate(load_scene, 1)
    assert(messages(load_scene).include?(ext_text(311_110, 4)))
    save_scene = scene
    activate(save_scene, 1)
    equal(false, save_scene.saved)
    equal('broken', File.binread(filename(0)))
    activate(save_scene, 0)
    assert_success(save_scene)
  end

  def test_single_save_backup_only
    Configs.save_config.maximum_save_count = 1
    File.binwrite("#{filename(0)}.bak", bytes)
    instance = scene(GamePlay::Load)
    assert(!instance.should_make_new_game?)
    activate(instance, 1)
    equal([5, 6].map { |id| ext_text(311_110, id) }, messages(instance))
    assert(!File.exist?(filename(0)))
  end

  def test_temporary_files_are_not_detected_as_saves
    File.binwrite('.save-load-tweaks-12345.tmp', bytes)
    assert(scene(GamePlay::Load).should_make_new_game?)
  end
end

failures = []
tests = SaveLoadTest.instance_methods.grep(/^test_/).sort
tests.each do |name|
  # All filesystem activity performed by the tested native code stays here.
  Dir.mktmpdir('save-load-tweaks-tests-') do |directory|
    Dir.chdir(directory) do
      test = SaveLoadTest.new
      test.setup
      begin
        test.public_send(name)
        puts "PASS #{name}"
      rescue StandardError => error
        failures << name
        warn "FAIL #{name}: #{error.class}: #{error.message}\n#{error.backtrace.first(6).join("\n")}"
      end
    end
  end
end
puts "#{tests.size} tests, #{SaveLoadTest.assertions} assertions, #{failures.size} failures (Ruby #{RUBY_VERSION}, #{RUBY_PLATFORM})"
exit(failures.empty? ? 0 : 1)
