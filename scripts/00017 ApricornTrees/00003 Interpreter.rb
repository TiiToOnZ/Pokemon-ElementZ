# frozen_string_literal: true

class Interpreter
  # Works in both an RMXP Script command and a native text-event Fiber.
  def apricorn_tree(color = nil)
    event = get_character(0)
    return false unless event && event.apricorn_color
    tree = ApricornTrees::ApricornTree.new(event)
    raise ArgumentError, 'Declared Apricorn color does not match the argument' if color && color != tree.color
    if @fiber
      return apricorn_tree_sequence(tree)
    end
    @child_interpreter = Interpreter.new(@depth + 1)
    @child_interpreter.setup(nil, @event_id, proc { apricorn_tree_sequence(tree) })
    true
  end

  private

  def apricorn_tree_sequence(tree)
    unless tree.available?
      tree.refresh
      message(ApricornTrees.text(:empty))
      return false
    end
    token = ApricornTrees.begin_session(tree)
    return false unless token
    obtained = false
    begin
      tree.event.apricorn_animating = true
      $game_player.look_to(tree.event.id)
      $game_player.enter_in_apricorn_state
      ApricornTrees::ANIMATION.each do |direction, pattern, duration|
        return false unless ApricornTrees.session_valid?(token)
        tree.event.apricorn_set_frame(direction, pattern)
        deadline = ApricornTrees.monotonic + duration
        while ApricornTrees.monotonic < deadline
          Fiber.yield(false)
          return false unless ApricornTrees.session_valid?(token)
        end
      end
      obtained = tree.harvest!
    ensure
      ApricornTrees.finish_session(token)
    end
    if obtained
      # Native translated item name, fanfare and acquisition message only.
      # This helper does NOT add anything to the Bag.
      add_item_show_message_got(ApricornTrees::TYPES.fetch(tree.color)[:item], 4, 11)
      message(ApricornTrees.text(:stored))
    end
    obtained
  end
end
