module MHL
  class RechenbergController

    DEFAULT_THRESHOLD = 1.0/5.0
    TAU = 1.10
    P_M_MAX = 0.99
    P_M_MIN = 0.01

    attr_reader :threshold, :generations

    def initialize(generations=5, threshold=DEFAULT_THRESHOLD, logger=nil)
      unless threshold > 0.0 and threshold < 1.0
        raise ArgumentError, "The threshold parameter must be in the (0.0,1.0) range!"
      end
      @generations = generations
      @threshold   = threshold
      @logger      = logger
      @history     = []
    end

    def call(solver, best)
      @history << best

      if @history.size > @generations
        # calculate improvement ratio
        res = @history.each_cons(2).inject(0) {|s,x| s += 1 if x[1][:fitness] > x[0][:fitness]; s } / (@history.size - 1).to_f
        if res > @threshold
          # we had enough improvements - decrease impact of mutation
          # increase mutation probability by 5% or to P_M_MAX
          old_p_m = solver.mutation_probability
          new_p_m = [ old_p_m * TAU, P_M_MAX ].min
          @logger.info "increasing mutation_probability from #{old_p_m} to #{new_p_m}" if @logger
          solver.mutation_probability = new_p_m
        else
          # we didn't have enough improvements - increase impact of mutation
          # decrease mutation probability by 5% or to P_M_MAX
          old_p_m = solver.mutation_probability
          new_p_m = [ old_p_m / TAU, P_M_MIN ].max
          @logger.info "decreasing mutation_probability from #{old_p_m} to #{new_p_m}" if @logger
          solver.mutation_probability = new_p_m
        end

        # reset
        @history.shift(@history.size-1)
      end
    end
  end

end
