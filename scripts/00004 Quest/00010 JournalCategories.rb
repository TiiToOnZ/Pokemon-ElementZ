# Local presentation extension. PFM quest objects and Studio data are never changed.
module ElementZ
  module QuestJournal
    CATEGORIES = %i[primary secondary jobs legendary finished failed].freeze
    LABELS = {
      'fr' => {menu: 'Journal', jobs: 'Métiers', legendary: 'Légendaires'},
      'en' => {menu: 'Newspaper', jobs: 'Professions', legendary: 'Legendary'},
      'es' => {menu: 'Diario', jobs: 'Oficios', legendary: 'Legendarias'},
      'it' => {menu: 'Giornale', jobs: 'Mestieri', legendary: 'Leggendarie'}
    }.freeze

    def self.label(key)
      LABELS.fetch(PFM.game_state.options.language, LABELS['fr']).fetch(key)
    end

    # One read per Journal opening, using the same source priority as Studio::Text.
    # load_data also supports Data/2.dat in a compiled game. Never change @lang,
    # options.language or the active language's Studio::Text cache.
    class FrenchTitles
      FILE_ID = 100_045
      FILENAME = 'Data/Text/Dialogs/100045.fr.dat'.freeze

      def initialize
        @titles = if Studio::Text.marshalized_text_file_exist?(FILENAME)
                    load_data(FILENAME)
                  else
                    require 'csv'
                    rows = CSV.read("Data/Text/Dialogs/#{FILE_ID}.csv", encoding: 'UTF-8')
                    column = rows.first.index { |language| language.to_s.strip.downcase == 'fr' }
                    raise 'Quest Journal: French quest titles are missing' unless column

                    Studio::Text.build_dialog_from_csv_rows(rows, column)
                  end
      end

      def [](id)
        title = @titles.fetch(id).dup
        title.force_encoding(Encoding::UTF_8) if title.encoding == Encoding::ASCII_8BIT
        title.encode(Encoding::UTF_8).unicode_normalize(:nfc)
      end
    end

    # Only secondary active quests are classified by name. Primary data errors
    # remain visible in Principales; this deliberately does not repair Studio data.
    def self.active_category(quest_data, titles)
      return :primary if quest_data.is_primary

      title = titles[quest_data.id]
      return :legendary if title.include?('[Légendaire]')
      return :jobs if /niv\./i.match?(title)

      :secondary
    end

    module CompositionExtension
      private

      # PSDK hard-codes four lists here and offers no filter registration hook.
      # Replace only this factory: all lists still use the native QuestList.
      # Calling super would create an unfiltered secondary list to discard.
      def create_quest_list
        titles = FrenchTitles.new
        groups = CATEGORIES.to_h { |category| [category, {}] }
        @quests.active_quests.each do |id, quest|
          category = QuestJournal.active_category(data_quest(quest.quest_id), titles)
          groups.fetch(category)[id] = quest
        end
        groups[:finished] = @quests.finished_quests
        groups[:failed] = @quests.failed_quests

        @sym_to_list = groups.to_h do |category, quests|
          list = UI::Quest::QuestList.new(@viewport, quests, category) unless quests.empty?
          list.opacity = 0 if list && category != @category
          instance_variable_set("@quest_list_#{category}", list)
          [category, list]
        end
      end
    end

    module CategoryDisplayExtension
      private

      def elementz_category_text(category)
        QuestJournal.label(category)
      end

      # Native arrows enumerate four symbols and retain their previous state.
      # Derive both arrows from the ordered categories, including empty lists.
      def update_arrows
        index = GamePlay::QuestUI::CATEGORIES.index(@category)
        @left_arrow.visible = index > 0
        @right_arrow.visible = index < GamePlay::QuestUI::CATEGORIES.size - 1
      end
    end
  end
end

GamePlay::QuestUI::CATEGORIES.replace(ElementZ::QuestJournal::CATEGORIES)
UI::Quest::CategoryDisplay::TEXT_CATEGORY.merge!(
  jobs: [:elementz_category_text, :jobs],
  legendary: [:elementz_category_text, :legendary]
)
UI::Quest::Composition.prepend(ElementZ::QuestJournal::CompositionExtension)
UI::Quest::CategoryDisplay.prepend(ElementZ::QuestJournal::CategoryDisplayExtension)
