module ZarbiDex
  remove_const(:MARK_FOUND) if const_defined?(:MARK_FOUND)
  remove_const(:MARK_MISSING) if const_defined?(:MARK_MISSING)
  ZarbiDex::MARK_FOUND = "✔"
  ZarbiDex::MARK_MISSING = "✘"

  def self.open
    if $scene.is_a?(GamePlay::Base)
      $scene.call_scene(Scene_ZarbiDex)
    else
      Scene_ZarbiDex.new.main
    end
  end

  def self.display(*)
    open
  end
end

class Window_ZarbiDex < UI::Window

  COLUMNS = 5
  CELL_WIDTH = 58
  CELL_HEIGHT = 18
  START_X = 10
  START_Y = 8

  attr_reader :index

  def initialize(viewport)
    super(viewport, 2, 2, 316, 142)
    @index = 0
    load_cursor
    self.active = true
    create_letters
    update_cursor
  end

  def selected_letter
    ZarbiDex::LETTERS[@index]
  end

  def move_left
    @index = (@index - 1) % ZarbiDex::LETTERS.size
    update_cursor
  end

  def move_right
    @index = (@index + 1) % ZarbiDex::LETTERS.size
    update_cursor
  end

  def move_up
    move_vertical(-1)
  end

  def move_down
    move_vertical(1)
  end

  private

  def create_letters
    letters = $trainer ? $trainer.zarbi_dex_letters : []
    ZarbiDex::LETTERS.each_with_index do |letter, i|
      mark = letters.include?(letter) ? ZarbiDex::MARK_FOUND : ZarbiDex::MARK_MISSING
      add_text(cell_x(i), cell_y(i), CELL_WIDTH, 16, "#{letter} #{mark}", 1, color: 10)
    end
  end

  def move_vertical(delta)
    return if ZarbiDex::LETTERS.empty?

    row = @index / COLUMNS
    col = @index % COLUMNS
    max_row = (ZarbiDex::LETTERS.size.to_f / COLUMNS).ceil

    loop do
      row = (row + delta) % max_row
      new_index = row * COLUMNS + col

      if new_index < ZarbiDex::LETTERS.size
        @index = new_index
        update_cursor
        return
      end
    end
  end

  def update_cursor
    cursor_rect.set(cell_x(@index) - 20, cell_y(@index) - 1, CELL_WIDTH, CELL_HEIGHT)
  end

  def cell_x(index)
    START_X + (index % COLUMNS) * CELL_WIDTH
  end

  def cell_y(index)
    START_Y + (index / COLUMNS) * CELL_HEIGHT
  end

  def refresh_letters
    self.contents.clear
    create_letters
  end
end

class Scene_ZarbiDex < GamePlay::BaseCleanUpdate::FrameBalanced
  def initialize
    super()
  end

  def update_inputs
    if Input.repeat?(:LEFT)
      @window.move_left
      update_selection
    elsif Input.repeat?(:RIGHT)
      @window.move_right
      update_selection
    elsif Input.repeat?(:UP)
      @window.move_up
      update_selection
    elsif Input.repeat?(:DOWN)
      @window.move_down
      update_selection
    elsif Input.trigger?(:B)
      @running = false
    end
    true
  end

  def update_graphics
    @base_ui.update_background_animation
    true
  end

  private

  def create_graphics
    create_viewport
    @base_ui = UI::GenericBase.new(@viewport, [nil, nil, nil, 'Fermer'])
    @window = Window_ZarbiDex.new(@viewport)
    @info_window = UI::Window.new(@viewport, 2, 148, 316, 60)
    @title_text = @info_window.add_text(8, 8, 300, 16, "", 1, color: 10)
    @meaning_text = @info_window.add_text(8, 30, 300, 16, nil.to_s, 1, color: 9)
    refresh_info
  end

  def update_selection
    play_cursor_se
    refresh_info
  end

  def refresh_info
    letter = @window.selected_letter
    captured = $trainer&.zarbi_dex_letters&.include?(letter)
    mark = captured ? ZarbiDex::MARK_FOUND : ZarbiDex::MARK_MISSING
    @title_text.text = "Lettre Zarbi : #{letter} #{mark}"
    @meaning_text.text = captured ? ZarbiDex::ZARBI_MEANINGS[letter] : '?????'
  end
end