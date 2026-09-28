# frozen_string_literal: true
require_relative 'support'

class BoxTest < ApricornTest
  ORDER = %i[red blue yellow green pink white black].freeze

  def setup
    super
    @saved_recipes = CraftSystem::Recipes.instance_variable_get(:@data)
    CraftSystem::Recipes.instance_variable_set(:@data, nil)
    @scenes = []
  end

  def teardown
    @scenes.each(&:dispose)
    CraftSystem::Recipes.instance_variable_set(:@data, @saved_recipes)
  end

  def box
    scene = GamePlay::ApricornBox.new
    @scenes << scene
    scene.send(:create_graphics)
    scene
  end

  def field(scene, name)
    scene.instance_variable_get("@#{name}")
  end

  def select(scene, index)
    scene.instance_variable_set(:@index, index)
    scene.send(:refresh_selection)
  end

  def test_seven_actual_items_and_all_zero_selections
    scene = box
    assert_equal ORDER, ApricornTrees::DISPLAY_ORDER
    assert_equal 7, field(scene, :item_icons).size
    ORDER.each_with_index do |color, i|
      select(scene, i)
      item = data_item(ApricornTrees::TYPES.fetch(color)[:item])
      assert_equal color, scene.selected_color
      assert_equal item.db_symbol, field(scene, :item_icons)[i].data
      assert_equal item.name, field(scene, :name).text
      assert_equal item.description, field(scene, :description_lines).map(&:text).join.strip
      assert_equal '0', field(scene, :quantities)[i].text
      assert_equal '×0', field(scene, :quantity).text
      cx, cy = GamePlay::ApricornBox::CENTRES[i]
      assert_equal [cx - 15, cy - 15], [field(scene, :item_icons)[i].x, field(scene, :item_icons)[i].y]
      assert_equal [cx - 25, cy + 4], [field(scene, :hand).x, field(scene, :hand).y]
    end
  end

  def test_quantities_are_exact_above_99_and_badges_remain_compact
    scene = box
    [0, 1, 2, 15, 99, 100, 247, 10**18].each do |amount|
      $apricorns.instance_variable_get(:@quantities)[:red] = amount
      scene.send(:refresh_selection)
      assert_equal "×#{amount}", field(scene, :quantity).text
      assert_equal(amount <= 99 ? amount.to_s : '+', field(scene, :quantities).first.text)
      assert_equal amount, $apricorns[:red]
    end
  end

  def test_each_direction_from_every_position_and_no_wrap
    expected = {
      LEFT: %i[red red blue yellow pink pink white],
      RIGHT: %i[blue yellow green green white black black],
      UP: %i[red blue yellow green red blue green],
      DOWN: %i[pink white white black pink white black]
    }
    scene = box
    expected.each do |direction, destinations|
      destinations.each_with_index do |color, index|
        select(scene, index)
        Input.key = direction
        scene.update_inputs
        assert_equal color, scene.selected_color, "#{ORDER[index]} #{direction}"
      end
    end
    select(scene, 2)
    scene.move_selection(:DOWN)
    scene.move_selection(:UP)
    assert_equal :blue, scene.selected_color
  end

  def test_all_colours_reachable_using_only_inputs_at_zero_stock
    scene = box
    visited = [scene.selected_color]
    %i[RIGHT RIGHT RIGHT DOWN LEFT LEFT].each do |direction|
      scene.move_selection(direction)
      visited << scene.selected_color
    end
    assert_equal ORDER.sort, visited.sort
    assert $apricorns.quantities.values.all?(&:zero?)
  end

  def test_configured_ball_recipes_and_native_object_data
    expected = %i[level_ball lure_ball moon_ball friend_ball love_ball fast_ball heavy_ball]
    scene = box
    ORDER.each_with_index do |color, index|
      select(scene, index)
      matches = scene.send(:ball_recipes, ApricornTrees::TYPES.fetch(color)[:item])
      assert_equal 1, matches.size
      assert_equal expected[index], matches.first[:result]
      ball = data_item(expected[index])
      assert_equal "1 #{ball.name}", field(scene, :ball_name).text
      assert_equal ball.description, field(scene, :ball_description_lines).map(&:text).join.strip
      assert_equal expected[index], field(scene, :ball_icon).data
      assert field(scene, :ball_icon).visible
      assert_equal "1 #{data_item(ApricornTrees::TYPES.fetch(color)[:item]).name}", field(scene, :ingredient_name).text
      assert_equal ApricornTrees::TYPES.fetch(color)[:item], field(scene, :ingredient_icon).data
      assert_equal '→', field(scene, :recipe_arrow).text
      refute field(scene, :graphics).stack.any? { |object| object.respond_to?(:text) && object.text.include?('Fabrication') }
    end
  end

  def test_result_is_dynamic_and_independent_of_recipe_key_or_old_mapping
    scene = box
    recipe = CraftSystem::Recipes.data[:level_ball]
    old = recipe.dup
    begin
      recipe[:result] = :heavy_ball
      recipe[:ingredients] = {red_apricorn: 3}
      recipe[:quantity] = 2
      scene.send(:refresh_selection)
      assert_equal :heavy_ball, field(scene, :ball_icon).data
      assert_equal "2 #{data_item(:heavy_ball).name}", field(scene, :ball_name).text
      assert_equal "3 #{data_item(:red_apricorn).name}", field(scene, :ingredient_name).text
      assert_equal :red_apricorn, field(scene, :ingredient_icon).data
    ensure
      recipe.replace(old)
    end
  end

  def test_missing_recipe_clears_previous_ball_without_crashing
    scene = box
    CraftSystem::Recipes.data.delete(:level_ball)
    scene.send(:refresh_selection)
    refute field(scene, :ball_icon).visible
    refute field(scene, :ingredient_icon).visible
    assert_empty field(scene, :ingredient_name).text
    assert_empty field(scene, :recipe_arrow).text
    assert_equal 'Aucune recette de Ball.', field(scene, :ball_name).text
    assert field(scene, :ball_description_lines).all? { |line| line.text.empty? }
    scene.move_selection(:RIGHT)
    assert field(scene, :ball_icon).visible
    assert_equal :lure_ball, field(scene, :ball_icon).data
  end

  def test_multiple_ball_recipes_are_explicit_even_with_same_output
    scene = box
    CraftSystem::Recipes.data[:duplicate] = CraftSystem::Recipes.data[:level_ball].dup
    scene.send(:refresh_selection)
    refute field(scene, :ball_icon).visible
    refute field(scene, :ingredient_icon).visible
    assert_empty field(scene, :ingredient_name).text
    assert_empty field(scene, :recipe_arrow).text
    assert_equal 'Plusieurs recettes de Balls.', field(scene, :ball_name).text
    assert field(scene, :ball_description_lines).all? { |line| line.text.empty? }
  end

  def test_invalid_outputs_or_amounts_are_not_ball_recipes
    scene = box
    recipe = CraftSystem::Recipes.data[:level_ball]
    old = recipe.dup
    begin
      [:oran_berry, :missing_item, nil].each do |result|
        recipe[:result] = result
        assert_empty scene.send(:ball_recipes, :red_apricorn)
      end
      recipe[:result] = :level_ball
      [0, -1, nil, '1'].each do |amount|
        recipe[:quantity] = amount
        assert_empty scene.send(:ball_recipes, :red_apricorn)
      end
    ensure
      recipe.replace(old)
    end
  end

  def test_live_names_descriptions_and_icons_come_from_data_item
    scene = box
    apricorn = data_item(:red_apricorn).dup
    ball = data_item(:level_ball).dup
    apricorn.name, apricorn.description, apricorn.icon = 'Nom localisé', 'Description localisée', 'custom_apricorn'
    ball.name, ball.description, ball.icon = 'Ball localisée', 'Description Ball locale', 'custom_ball'
    scene.define_singleton_method(:data_item) do |symbol|
      {red_apricorn: apricorn, level_ball: ball}.fetch(symbol) { super(symbol) }
    end
    scene.send(:refresh_selection)
    assert_equal apricorn.name, field(scene, :name).text
    assert_equal "1 #{apricorn.name}", field(scene, :ingredient_name).text
    assert_equal :red_apricorn, field(scene, :ingredient_icon).data
    assert_equal apricorn.description, field(scene, :description_lines).first.text
    assert_equal "1 #{ball.name}", field(scene, :ball_name).text
    assert_equal ball.description, field(scene, :ball_description_lines).first.text
    assert_equal :level_ball, field(scene, :ball_icon).data
  end

  def test_clock_animation_is_frame_rate_independent
    scene = box
    {0.0 => 0, 0.226 => 1, 0.451 => 0, 4.726 => 1}.each do |time, frame|
      ApricornTrees.test_tick = time
      scene.update_graphics
      assert_equal frame, field(scene, :hand).sy
    end
  end

  def test_rapid_refresh_reuses_all_drawables_and_preserves_gameplay
    $apricorns.add(:red, 247)
    $bag.add_item(:poke_ball, 3)
    before = [$apricorns.quantities, Marshal.dump($bag.instance_variable_get(:@items)),
              Marshal.dump($crafting_data), Marshal.dump(PFM.game_state.quests.acquisitions),
              $game_self_switches.dup, $game_switches.dup]
    trace = TracePoint.new(:call) do |event|
      if event.self.equal?(CraftSystem) && %i[craft state unlocked? available_recipes].include?(event.method_id)
        flunk "Consultation called #{event.method_id}"
      end
    end
    trace.enable do
      scene = box
      objects = field(scene, :graphics).stack.dup
      400.times do |i|
        scene.move_selection(%i[RIGHT DOWN LEFT UP][i % 4])
        scene.update_graphics
      end
      assert_equal objects.map(&:object_id), field(scene, :graphics).stack.map(&:object_id)
      assert_equal before, [$apricorns.quantities, Marshal.dump($bag.instance_variable_get(:@items)),
                            Marshal.dump($crafting_data), Marshal.dump(PFM.game_state.quests.acquisitions),
                            $game_self_switches.dup, $game_switches.dup]
    end
  end

  def test_native_b_action_and_bag_handler_do_not_consume_the_box
    scene = box
    Input.key = :X
    scene.update_inputs
    refute_equal false, field(scene, :running)
    Input.key = :B
    scene.update_inputs
    assert_equal false, field(scene, :running)
    before, handler = PFM::ItemDescriptor::HANDLERS.fetch(:apricorn_box)
    assert before
    parent = Object.new
    def parent.call_scene(klass); @opened = klass; end
    assert_equal :unused, handler.call(nil, parent)
    assert_equal GamePlay::ApricornBox, parent.instance_variable_get(:@opened)
  end

  def test_repeated_open_close_disposes_drawables_once
    20.times do
      scene = box
      objects = field(scene, :graphics).stack.dup + [field(scene, :return_button)]
      scene.dispose
      scene.dispose
      assert_empty field(scene, :graphics).stack
      assert objects.all? { |object| object.dispose_count == 1 }
    end
  end

  def test_production_assets_are_unmodified_source_copies
    %w[apr_background apr_hand].zip([[320, 240], [20, 44]]).each do |name, dimensions|
      original = File.binread(File.join(PROJECT, '../../Noigrumes', "#{name}.png"))
      installed = File.binread(File.join(PROJECT, '../graphics/interface/apricorn_box', "#{name}.png"))
      assert_equal original, installed
      assert_equal dimensions, installed.byteslice(16, 8).unpack('N2')
    end
    refute File.exist?(File.join(PROJECT, '../graphics/interface/apricorn_box/rendu.png'))
    refute File.exist?(File.join(PROJECT, '../graphics/interface/apricorn_box/apr_quantity_window.png'))
  end
end
