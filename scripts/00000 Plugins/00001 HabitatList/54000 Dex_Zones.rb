module GamePlay
  class Dex
    MAX_ENCOUNTERS = 12
    def initialize(page_id = false)
      super()
      @pokemonlist = PFM::Pokemon.new(data_dex($pokedex.variant).creatures.first&.db_symbol || 1, 1)
      @arrow_direction = 1
      @state = page_id ? 1 : 0
      @page_id = page_id.is_a?(PFM::Pokemon) ? page_id.id : page_id
      @pkmn = page_id.is_a?(PFM::Pokemon) ? page_id.dup : nil
      generate_selected_pokemon_array(page_id)
      generate_group_list unless page_id #this is the new line
      @unseen_visible = false
      generate_pokemon_object
      Mouse.wheel = 0
    end

    # Create all the graphics
    def create_graphics
      create_viewport
      create_base_ui
      unless @page_id
        create_list
        create_grouplist_buttons #this is new
        create_face_zone #this is new
        create_face_zone_sprites #this is new
        create_arrow
        create_scroll_bar
        create_progression
        create_worldmap
      end
      create_face
      create_frame
      create_info
      change_state(@state)
    end
    
    
    def action_Y #mode_switch is now completely uncalled
      @pokemon_worldmap.on_next_worldmap if @state == 2
      if @state == 0
        change_state(3)
      elsif @state == 3
        change_state(0)
      end
      $game_system.cry_play(@pokemon.id, form: @pokemon.form) if @state == 1 && $pokedex.creature_seen?(@pokemon.id, @pokemon.form)
    end
    def action_B
      $game_system.se_play($data_system.decision_se)
      return @running = false if @state == 0 || @state == 3 || @page_id
      change_state(@state - 1) if @state > 0 
    end
    def action_A
      return $game_system.se_play($data_system.buzzer_se) if @page_id
      return $game_system.se_play($data_system.buzzer_se) unless @state != 2 && @state < 4 #this is new
      $game_system.se_play($data_system.decision_se)
      change_state(@state + 1)
    end
    def change_state(state)
      @state = state
      @base_ui.mode = state
      @frame.set_bitmap((state == 1 || state == 4) ? 'frameinfos' : 'frame', :pokedex)
      update_index unless @page_id || state == 2 #very different starting here
      @pokeface.data = @pokemon if (@pokeface.visible = state < 2)
      if @arrow
        @arrow.visible = @seen_got.visible = (state == 0 || state == 3)
        @pokemon_worldmap.set_pokemon(@pokemon) if (@pokemon_worldmap.visible = state == 2)
      end
      unless @page_id
        MAX_ENCOUNTERS.times do |i| #we first remove all sprites
          @spritelist[i].visible = false
        end
        if (@zoneface.visible = state == 4) #before redrawing them
          @zoneface.data = @allgroups[@index]
          mons = index_to_mons(@index)
          index_to_group(@index).encounters.size.times do |i|
            puts "no sprite available bro, change MAX_ENCOUNTERS" if @spritelist[i].nil? #if this happens the game WILL crash on the following line. change the value of MAX_ENCOUNTERS or put less mons in your group to fix it.
            @spritelist[i].data = mons[i]
            if index_to_group(@index).encounters.size > 6
              half = ((index_to_group(@index).encounters.size)/2.0).ceil
              posx = (40 * (i % half))
              posy = (i > (half - 1) ? 48 : 0)
            else 
              posx = 32 * i
              posy = 24
            end
            @spritelist[i].set_position(posx, posy)
          end
        end
        if @seen_got.visible #this is regarding the number of mons seen and caught
          group = state == 3 ? index_to_group(@index) : nil
          @seen_got.update_progression(group)
        end
      end
      @pokemon_info.visible = state == 1
      if @pokemon_info.visible
        @pokemon_info.data = @pokemon
      end
      @pokemon_descr.visible = (state == 1 || state == 4) #this shows the description of the zone. if you don't want it to, you can remove " || state == 4" and the parenthesis
      if @pokemon_descr.visible
        if $pokedex.creature_caught?(@pokemon.id, @pokemon.form)
          @pokemon_descr.multiline_text = data_creature_form(@pokemon.db_symbol, @pokemon.form).form_description
        else
          @pokemon_descr.multiline_text = ''
        end
        @pokemon_descr.multiline_text = ext_text(100064, index_to_zone(@index).id) unless @pokemon_info.visible
      end
    end

    def index_to_mons(index)
      mons = []
      index_to_group(index).encounters.each_with_index do |enc, i|
        mons << PFM::Pokemon.generate_from_hash(id: enc.specie, level: 1, no_shiny: true, form: enc.form) #this generates data for the sprites. for some reason Meowstic form is wrong.
      end
      return mons
    end
    # Update the UI inputs
    def update_inputs
      return action_A if Input.trigger?(:A)
      return action_X if Input.trigger?(:X)
      return action_Y if Input.trigger?(:Y)
      return action_B if Input.trigger?(:B)
      return false if @page_id
      case @state
      when 0
        max_index = @selected_creatures.size - 1
        list_input(max_index)
      when 1
        max_index = @selected_creatures.size - 1
        update_index_descr if index_changed(:@index, :UP, :DOWN, max_index)
      when 2
        @pokemon_worldmap.update
      when 3
        max_index = @allgroups.size - 1
        list_input(max_index)
      when 4
        max_index = @allgroups.size - 1
        update_index_descr if index_changed(:@index, :UP, :DOWN, max_index)
      end
    end

    def list_input(max_index) #new method, but everything in it is old
      if index_changed(:@index, :UP, :DOWN, max_index)
        update_index
      else
        if index_changed!(:@index, :LEFT, :RIGHT, max_index)
          9.times {index_changed!(:@index, :LEFT, :RIGHT, max_index) }
          update_index
        else
          if Mouse.wheel != 0
            @index = (@index - Mouse.wheel) % (max_index + 1)
            Mouse.wheel = 0
            update_index
          end
        end
      end
    end

    def update_index #this is a bit sloppy.
      @index = 0 if @index > @selected_creatures.size - 1 && @state == 0
      if @state == 3
        if @zoneindex #this makes the UI open on the zone you're actually on. only once, there are some improvements to be made.
          @index = @zoneindex
          @zoneindex = nil
        else
          @index = current_zone if @index > @allgroups.size - 1
        end
        @seen_got.update_progression(index_to_group(@index))
      end
      update_current_creature unless @state > 2
      @pokeface.data = @pokemon unless @state > 2
      @zoneface.data = @allgroups[@index] if @state == 4
      update_list(@state == 0 || @state == 3)
    end

    def update_index_descr
      if @state == 4
        @zoneface.data = @allgroups[@index]
      else
        update_current_creature
        @pokeface.data = @pokemon
      end
      change_state(@state)
    end

    def index_to_group(index) #this is simply convenience
      return @allgroups[index][0]
    end

    def index_to_zone(index) #this is simply convenience
      return @allgroups[index][1]
    end
    # Update the button list
    # @param visible [Boolean]
    def update_list(visible)
      @scrollbar.visible = @scrollbut.visible = visible
      @scrollbut.y = 41 + 150 * @index / (@selected_creatures.size - 1) if @selected_creatures.size > 1 unless @state == 3
      @scrollbut.y = 41 + 150 * @index / (@allgroups.size - 1) if @allgroups.size > 1 if @state == 3
      base_index = calc_base_index
      if @state == 0
        @list.each_with_index do |el, i| #this is the vanilla behavior
          next unless (el.visible = visible)
          pos = base_index + i
          creature = @selected_creatures[pos]
          next((el.visible = false)) unless creature && pos >= 0
          @arrow.y = el.y + 11 if (el.selected = (pos == @index))
          @pokemonlist.id = creature.db_symbol
          @pokemonlist.form = $pokedex.national? ? first_or_prefered_form($pokedex.form_seen(creature.db_symbol), creature.form) : creature.form
          el.data = @pokemonlist
        end
      else
        @list.each_with_index do |el, i| #simply making sure the dex list is hidden when the zone list is shown
          next unless (el.visible = false)
        end
      end
      if @state == 3
        @listgroup.each_with_index do |el, i|
          next unless (el.visible = visible)
          pos = base_index + i
          arr = @allgroups[pos] #this is the important part
          next((el.visible = false)) unless arr && pos >= 0
          @arrow.y = el.y + 11 if (el.selected = (pos == @index))
          el.data = arr
        end
      else
        @listgroup.each_with_index do |el, i| #simply making sure the zone list is hidden when the dex list is shown
          next unless (el.visible = false)
        end
      end
    end
    # Calculate the base index of the list
    # @return [Integer]
    def calc_base_index
      return -1 if @selected_creatures.size < 5 unless @state == 3
      return -1 if @allgroups.size < 5 if @state == 3
      if @index >= 2
        return @index - 2
      else
        if @index < 2
          return -1
        end
      end
    end
    
    # Get the button text for the generic UI
    # @return [Array<Array<String>>]
    def button_texts
      return [[nil, nil, nil, ext_text(9000, 9)]] * 3 if @page_id
      #text 170 is ": habitat" and text 171 is ": regional"
      return [[ext_text(9000, 6), nil, ext_text(9000, 170), ext_text(9000, 9)], [ext_text(9000, 10), $pokedex.national? ? ext_text(9000, 11) : nil, ext_text(9000, 12), ext_text(9000, 13)], [ext_text(9000, 6), nil, ext_text(9000, 8), ext_text(9000, 9)], [ext_text(9000, 6), nil, ext_text(9000, 171), ext_text(9000, 9)], [nil, nil, nil, ext_text(9000, 9)]]
    end

    # @return [Array<Studio::Zone>]
    def zone_list
      return each_data_zone.select {|zone| $env.visited_zone?(zone)}
    end

    # @return [Array<Array<Studio::Group>, <Studio::Zone>>]
    def generate_group_list
      unordered = []
      each_data_group.each do |group|
        if c = group.custom_conditions[0]
          next if c.type == :enabled_switch && (c.value == 13 || c.value == 14) #this skips over the morning and the evening groups to only keep day and night. remove this line if you don't want to.
        end
        zone_list.each do |zone|
          unordered << [group, zone] if zone.wild_groups.include?(group.db_symbol) #this is probably the single most important line
        end
      end
      ordered = []
      zone_list.each do |zone|
        unordered.each do |arr|
          ordered << arr if arr[1] == zone
        end
      end
      @allgroups = ordered
      @zoneindex = current_zone
    end

    def current_zone
      zoneindex = 0
      @allgroups.each_with_index do |arr, i|
        zoneindex = i
        break if arr[1].db_symbol == $env.get_current_zone_data&.db_symbol
        zoneindex = 0
      end
      return zoneindex
    end

    
    # Create the Group list
    def create_grouplist_buttons
      @listgroup = Array.new(6) { |i| DexButtonZone.new(@viewport, i) }
    end
    # Create the face sprite ui
    def create_face_zone
      @zoneface = DexWinZone.new(@viewport)
    end
    # Create the (empty) sprites
    def create_face_zone_sprites
      @spritelist = Array.new(MAX_ENCOUNTERS) { |i| ZoneBattlers.new(@viewport, i) }
    end
  end
end

module UI
  class DexSeenGot
    def create_sprites
      add_background('WinNum')
      @seen_text = add_text(2, 0, 79, 26, ext_text(9000, 20), color: 10)
      @seen_text.bold = true
      @seen_nb = number_seen_text
      @got_text = add_text(2, 28, 79, 26, ext_text(9000, 21), color: 10)
      @got_text.bold = true
      @got_nb = number_got_text
    end
    def number_seen_text
      text = add_text(@seen_text.real_width + 4, 0, 79, 26, :creature_seen, 0, type: SymText, color: 10)
      return text
    end
    def number_got_text
      text = add_text(@got_text.real_width + 4, 28, 79, 26, :creature_caught, 0, type: SymText, color: 10)
      return text
    end
    # Define the Pokemon shown by the UI
    # @param state [Integer]
    def update_progression(group = nil) #brand new method, updates the text to tell how many mons you've seen or caught in a specific zone
      if group
        @seen_nb.text = (group.encounters.select {|mon| $pokedex.creature_seen?(mon.specie, mon.form) }).size.to_s
        @got_nb.text = (group.encounters.select {|mon| $pokedex.creature_caught?(mon.specie, mon.form) }).size.to_s
      else
        @seen_nb.text = data.creature_seen.to_s
        @got_nb.text = data.creature_caught.to_s
      end
    end
  end
  class DexButtonZone < SpriteStack
    # Create a new dex button
    # @param viewport [Viewport]
    # @param index [Integer] index of the sprite in the viewport
    def initialize(viewport, index)
      super(viewport, 147, 62, default_cache: :pokedex)
      create_sprites
      fix_position(index)
    end
    # Change the data
    # @param pokemon [PFM::Pokemon] the Pokemon shown by the button
    def data=(arr)
      super(arr)
      @group = arr[0]
      @zone = arr[1]
      update_text
    end
    # Tell the button if it's selected or not : change the obfuscator visibility & x position
    # @param value [Boolean] the selected state
    def selected=(value)
      @obfuscator.visible = !value
      set_position(value ? 147 : 163, y)
    end
    private
    def create_sprites
      add_background('But_List')
      @catch_icon = add_sprite(119, 9, 'Catch')
      @systag_icon = add_sprite(1, 1, 'Grass')
      @name = symtext_is_dumb
      @obfuscator = add_foreground('But_ListShadow')
    end
    def symtext_is_dumb
      text = add_text(35, 16, 116, 16, '', color: 10)
      return text
    end
    def update_text
      @name.text = @zone.name #duhh
      @systag_icon.set_bitmap(@group.system_tag.to_s, :pokedex)
      @systag_icon.set_bitmap(@group.tool.to_s, :pokedex) unless @group.tool.nil?
      allcaught = (@group.encounters.select {|mon| $pokedex.creature_caught?(mon.specie, mon.form) }).size == @group.encounters.size
      allseen = (@group.encounters.select {|mon| $pokedex.creature_seen?(mon.specie, mon.form) }).size == @group.encounters.size
      @catch_icon.set_bitmap(allcaught ? 'Catch' : allseen ? 'Seen' : '', :pokedex)
    end
    # Adjust the position according to the index
    # @param index [Integer] index of the sprite in the viewport
    def fix_position(index)
      set_position(index == 0 ? 147 : 163, y - 40 + index * 40)
    end
  end
  class DexWinZone < SpriteStack
    # Create a new dex win sprite
    def initialize(viewport)
      super(viewport, 3, 9, default_cache: :pokedex)
      create_sprites
    end
    def data=(arr)
      super(arr)
      @group = arr[0]
      @zone = arr[1]
      update_text
    end
    private
    def create_sprites
      add_background('WinZone')
      @catch_icon = add_sprite(285, 32, 'Catch')
      @systag_icon = add_sprite(277, 53, 'Grass')
      @vstype_icon = add_sprite(277, 89, 'simple')
      @time_icon = add_sprite(277, 108, '')
      @name = zone_name_method
      @name.bold = true
    end
    def zone_name_method
      text = add_text(3, 6, 116, 19, '', 1, color: 10)
      return text
    end

    def update_text #shows group info, name is a bit misleading lol
      @name.text = @zone.name.upcase #duhh
      @systag_icon.set_bitmap(@group.system_tag.to_s, :pokedex) #this shows the system_tag the group is active on. the list can be found in system_tag_db_symbol.
      @systag_icon.set_bitmap(@group.tool.to_s, :pokedex) unless @group.tool.nil? #this overwrites the previous line in case the group is fishing or rock smash.
      @vstype_icon.set_bitmap(@group.vs_type.to_s, :pokedex)
      @time_icon.set_bitmap('')
      if c = @group.custom_conditions[0]
        @time_icon.set_bitmap('daytime', :pokedex) if c.type == :enabled_switch && c.value == 11
        @time_icon.set_bitmap('nighttime', :pokedex) if c.type == :enabled_switch && c.value == 12
      end

      allcaught = (@group.encounters.select {|mon| $pokedex.creature_caught?(mon.specie, mon.form) }).size == @group.encounters.size
      allseen = (@group.encounters.select {|mon| $pokedex.creature_seen?(mon.specie, mon.form) }).size == @group.encounters.size
      @catch_icon.set_bitmap(allcaught ? 'Catch' : allseen ? 'Seen' : '', :pokedex)
    end

  end
  class ZoneBattlers < SpriteStack
    # Create a new dex win sprite
    def initialize(viewport, index)
      super(viewport, 3, 9, default_cache: :pokedex)
      @index = index || 0
      create_sprites
    end
    # Update the graphics
    def update_graphics
      @sprite.update
    end
    def data=(pokemon)
      super
      update_info_visibility(pokemon)
    end
    private
    def create_sprites
      @sprite = add_sprite(50, 100, NO_INITIAL_IMAGE, type: PokemonFaceSprite)
    end
    # Define if the Pokemon is displayed by the UI
    # @param creature [PFM::Pokemon]
    def update_info_visibility(creature)
      is_seen = creature && ($pokedex.creature_seen?(creature.id, creature.form) || $pokedex.creature_caught?(creature.id, creature.form))
      @sprite.set_bitmap('000', :pokedex) unless is_seen #this shows the question mark
      @sprite.visible = true
    end
  end
end