# Namespace of the UI collection plugin
module CCUICollection
  # Features the plugin ships, one accessor each, all on once the plugin is installed
  #
  # Assigning one takes effect right away, so a script of the game project can turn a feature off,
  # or back on, at any point. A feature either takes an engine interface over, and its accessor
  # registers or unregisters it, or adds to the engine, and its accessor is read where it applies.
  module Settings
    class << self
      # Whether the cinematic evolution scene replaces the engine one
      # @return [Boolean]
      attr_reader :evolution

      # @param value [Boolean]
      def evolution=(value)
        # Whatever was registered before this plugin, so turning the interface off gives that back
        # instead of assuming the engine scene was there
        @evolve_class_before ||= GamePlay.evolve_class
        @evolution = value
        GamePlay.evolve_class = value ? GamePlay::EvolveCinematic : @evolve_class_before
      end

      # Whether the cinematic hatching scene replaces the engine one
      # @return [Boolean]
      attr_reader :hatching

      # @param value [Boolean]
      def hatching=(value)
        # Whatever was registered before this plugin, so turning the interface off gives that back
        # instead of assuming the engine scene was there
        @hatch_class_before ||= GamePlay.hatch_class
        @hatching = value
        GamePlay.hatch_class = value ? GamePlay::HatchCinematic : @hatch_class_before
      end

      # Whether a Pokemon sent out shakes the camera and raises dust, graded by its weight
      # @return [Boolean]
      attr_accessor :landing_impact
    end
  end
end
