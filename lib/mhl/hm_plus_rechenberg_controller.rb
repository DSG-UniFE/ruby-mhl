require 'mhl/rechenberg_controller'

module MHL
  class HyperMutationPlusRechenbergController
    DEFAULT_HM_GENERATIONS = 10

    def initialize(params={})
      @opts = { keep_for: DEFAULT_HM_GENERATIONS }.merge!(params)
      @rc = RechenbergController.new
      @gen = @gens_from_last_reset = 1
    end

    def call(solver, best)
      if @pending_reset
        # set mutation_probability to HM value
        solver.mutation_probability = @pending_reset

        # reinitialize controller
        @rc = RechenbergController.new

        # reinitialize counter of generations from last reset
        @gens_from_last_reset = 0

        # undefine pending_reset
        # NOTE: not sure if we should we go as far as calling
        # remove_instance_variable(:@pending_reset) here
        @pending_reset = nil
      end

      # do nothing for the first @opts[:keep_for] generations
      if @gens_from_last_reset > @opts[:keep_for]
        @rc.call(solver, best)
      end

      # update counters
      @gen += 1
      @gens_from_last_reset += 1
    end

    def reset_mutation_probability(value)
      @pending_reset = value
    end
  end
end
