module GTS
  module Settings  
    remove_const :GAMEID
    remove_const :URL
    remove_const :SPECIES_SHOWN
    remove_const :SORT_MODE
    remove_const :BLACK_LIST
    remove_const :GAME_CODE
    remove_const :BGM

    # ID of the game, replace 0 by what you got on the pannel
    GAMEID = 147
    # URL of the GTS server (Don't touch)
    URL = 'http://gts.kawasemi.de/api.php?i='
    # Condition to see the Pokemon in the search result (All/Seen/Owned)
    SPECIES_SHOWN = 'All'
    # How the Pokemon are searched (Alphabetical/Regional)
    SORT_MODE = 'Alphabetical'
    # List of black listed Pokemon (filtered out of the search) put ID or db_symbol here
    BLACK_LIST = []
    # Internal Game Code to know if the Pokemon comes from this game or another (like DPP <-> HGSS), you can change this
    GAME_CODE = '255'
    # Scene BGM (Complete path in lower case without extname)
    BGM = 'audio/bgm/xy_gts'
  end
end