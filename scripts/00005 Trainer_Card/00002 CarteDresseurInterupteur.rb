module GamePlay
  class Menu < BaseCleanUpdate
    CONDITION_LIST[3] = proc { $game_switches[110] }
  end
end
