module MHL

  # This class implements a genotype with integer space representation
  class IntegerVectorGenotypeSpace
    def initialize(opts, logger)
      @random_func = opts[:random_func]

      @dimensions = opts[:dimensions].to_i
      unless @dimensions and @dimensions > 0
        raise ArgumentError, 'Must have positive integer dimensions'
      end

      # TODO: enable to choose which recombination function to use
      case opts[:recombination_type].to_s
      when /intermediate/i
        @recombination_func = :extended_intermediate_recombination_int
      when /line/i
        @recombination_func = :extended_line_recombination_int
      else
        raise ArgumentError, 'Recombination function must be either line or intermediate!'
      end

      @constraints = opts[:constraints]
      if @constraints and @constraints.size != @dimensions
        raise ArgumentError, 'Constraints must be provided for every dimension!'
      end

      @logger = logger
    end

    def get_random
      if @random_func
        @random_func.call
      else
        if @constraints
          @constraints.map{|x| x[:from] + SecureRandom.random_number(x[:to] - x[:from]) }
        else
          raise 'Automated random genotype generation when no constraints are provided is not implemented yet!'
        end
      end
    end

    # reproduction with random geometric mutation
    # and intermediate recombination
    def reproduce_from(p1, p2, mutation_rv, recombination_rv)
      # make copies of p1 and p2
      # (we're only interested in the :genotype key)
      c1 = { genotype: p1[:genotype].dup }
      c2 = { genotype: p2[:genotype].dup }

      # mutation comes first
      random_delta_mutation(c1[:genotype], mutation_rv)
      random_delta_mutation(c2[:genotype], mutation_rv)

      # and then recombination
      send(@recombination_func, c1[:genotype], c2[:genotype], recombination_rv)

      if @constraints
        repair_chromosome(c1[:genotype])
        repair_chromosome(c2[:genotype])
      end

      return c1, c2
    end


    private

      # mutation based on random perturbations of (all) the individual's
      # chromosomes, according to a geometric distribution [TORTONESI16]
      def random_delta_mutation(g, mutation_rv)
        g.each_index do |i|
          delta = mutation_rv.next

          if rand() >= 0.5
            # half of the times the variation will be positive ...
            g[i] += delta
          else
            # ... and half of the times it will be negative
            g[i] -= delta
          end
        end
      end

      # integer variant of extended intermediate recombination [MUHLENBEIN93]
      # (see [LUKE15] page 65)
      def extended_intermediate_recombination_int(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        # recombination
        g1.each_index do |i|
          begin
            alpha = recombination_rv.next
            beta  = recombination_rv.next
            t = (alpha * g1[i] + (1.0 - alpha) * g2[i] + 0.5).floor
            s = ( beta * g2[i] + (1.0 -  beta) * g1[i] + 0.5).floor
          end
          g1[i] = t
          g2[i] = s
        end
      end

      # integer variant of extended line recombination [MUHLENBEIN93] (see
      # [LUKE15] page 64)
      def extended_line_recombination_int(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        alpha = recombination_rv.next
        beta  = recombination_rv.next

        # recombination
        g1.each_index do |i|
          t = (alpha * g1[i] + (1.0 - alpha) * g2[i] + 0.5).floor
          s = ( beta * g2[i] + (1.0 -  beta) * g1[i] + 0.5).floor
          g1[i] = t
          g2[i] = s
        end
      end

      def repair_chromosome(g)
        g.each_index do |i|
          if g[i] < @constraints[i][:from]
            range = "[#{@constraints[i][:from]},#{@constraints[i][:to]}]"
            @logger.debug "repairing g[#{i}] #{g[i]} to fit within #{range}" if @logger
            g[i] = @constraints[i][:from]
            @logger.debug "g[#{i}] repaired as: #{g[i]}" if @logger
          elsif g[i] > @constraints[i][:to]
            range = "[#{@constraints[i][:from]},#{@constraints[i][:to]}]"
            @logger.debug "repairing g[#{i}] #{g[i]} to fit within #{range}" if @logger
            g[i] = @constraints[i][:to]
            @logger.debug "g[#{i}] repaired as: #{g[i]}" if @logger
          end
        end
      end

  end

end
