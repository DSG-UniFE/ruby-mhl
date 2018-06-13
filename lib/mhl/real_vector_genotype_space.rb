module MHL

  # This class implements a genotype with real space representation
  class RealVectorGenotypeSpace
    def initialize(opts, logger)
      @random_func = opts[:random_func]

      @dimensions = opts[:dimensions].to_i
      unless @dimensions and @dimensions > 0
        raise ArgumentError, 'The number of dimensions must be a positive integer!'
      end

      # TODO: enable to choose which recombination function to use
      case opts[:recombination_type].to_s
      when /intermediate/i
        @recombination_func = :extended_intermediate_recombination
      when /line/i
        @recombination_func = :extended_line_recombination
      else
        raise ArgumentError, 'Recombination function must be either line or intermediate!'
      end

      @constraints = opts[:constraints]
      if !@constraints or @constraints.size != @dimensions
        raise ArgumentError, 'Real-valued GA variants require constraints!'
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

    # reproduction with power mutation and line or intermediate recombination
    def reproduce_from(p1, p2, mutation_rv, recombination_rv)
      # make copies of p1 and p2
      # (we're only interested in the :genotype key)
      c1 = { genotype: p1[:genotype].dup }
      c2 = { genotype: p2[:genotype].dup }

      # mutation comes first
      power_mutation(c1[:genotype], mutation_rv)
      power_mutation(c2[:genotype], mutation_rv)

      # and then recombination
      send(@recombination_func, c1[:genotype], c2[:genotype], recombination_rv)

      if @constraints
        repair_chromosome(c1[:genotype])
        repair_chromosome(c2[:genotype])
      end

      return c1, c2
    end


    private

      # power mutation [DEEP07]
      # NOTE: this mutation operator won't work unless constraints are given
      def power_mutation(parent, mutation_rv)
        s = mutation_rv.next ** 10.0

        min = @constraints.map{|x| x[:from] }
        max = @constraints.map{|x| x[:to] }

        parent.each_index do |i|
          t_i = (parent[i] - min[i]) / (max[i]-min[i])

          if rand() >= t_i
            # sometimes the variation will be positive ...
            parent[i] += s * (max[i] - parent[i])
          else
            # ... and sometimes it will be negative
            parent[i] -= s * (parent[i] - min[i])
          end
        end
      end

      # extended intermediate recombination [MUHLENBEIN93] (see [LUKE15] page 42)
      def extended_intermediate_recombination(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        # recombination
        g1.each_index do |i|
          begin
            alpha = recombination_rv.next
            beta  = recombination_rv.next
            t = alpha * g1[i] + (1.0 - alpha) * g2[i]
            s =  beta * g2[i] + (1.0 -  beta) * g1[i]
          end
          g1[i] = t
          g2[i] = s
        end
      end

      # extended line recombination [MUHLENBEIN93] (see [LUKE15] page 42)
      def extended_line_recombination(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        alpha = recombination_rv.next
        beta  = recombination_rv.next

        # recombination
        g1.each_index do |i|
          t = alpha * g1[i] + (1.0 - alpha) * g2[i]
          s =  beta * g2[i] + (1.0 -  beta) * g1[i]
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
