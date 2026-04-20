module ZarbiDex
  LETTERS = ('A'..'Z').to_a.freeze
  remove_const(:ZARBI_MEANINGS) if const_defined?(:ZARBI_MEANINGS)

  ZARBI_MEANINGS = {
    'A' => 'BEGINNING', 'B' => 'BRIGHT', 'C' => 'CREATE', 'D' => 'DESTINY',
    'E' => 'EXISTENCE', 'F' => 'FATE', 'G' => 'GUARDIAN', 'H' => 'HOPE',
    'I' => 'IDEA', 'J' => 'JOY', 'K' => 'KNOWLEDGE', 'L' => 'LIGHT',
    'M' => 'MYSTERY', 'N' => 'NATURE', 'O' => 'ORIGIN', 'P' => 'POWER',
    'Q' => 'QUEST', 'R' => 'REALITY', 'S' => 'SOUL', 'T' => 'TIME',
    'U' => 'UNITY', 'V' => 'VISION', 'W' => 'WISDOM', 'X' => 'UNKNOWN',
    'Y' => 'YOUTH', 'Z' => 'ZERO'
  }.freeze

  def self.add(letter, scene = $scene)
    return unless $trainer && LETTERS.include?(letter)
    $trainer.zarbi_dex_letters ||= []
    return if $trainer.zarbi_dex_letters.include?(letter)

    $trainer.zarbi_dex_letters << letter
    scene&.display_message_and_wait("Nouvelle lettre Zarbi : #{letter} - #{ZARBI_MEANINGS[letter]}")
  end

  def self.register_captured_pokemon(pokemon, scene = $scene)
    return unless pokemon&.db_symbol == :unown

    add(LETTERS[pokemon.form], scene)
  end

  def self.display(scene = $scene)
    letters = $trainer ? $trainer.zarbi_dex_letters : []
    LETTERS.each_slice(7) do |page|
      text = ['=== CARNET ZARBI ===', '']
      page.each do |letter|
        found = letters.include?(letter)
        text << "#{letter} #{found ? '✔' : '❌'} - #{found ? ZARBI_MEANINGS[letter] : '?????'}"
      end
      scene&.display_message_and_wait(text.join("\n"))
    end
  end
end

PFM::ItemDescriptor.define_bag_use(:unown_report) do |_item, scene|
  ZarbiDex.display(scene)
  next true
end

module PFM
  class Trainer
    attr_writer :zarbi_dex_letters

    def zarbi_dex_letters
      @zarbi_dex_letters ||= []
    end
  end
end