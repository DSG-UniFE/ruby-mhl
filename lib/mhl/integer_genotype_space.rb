module MHL

  # This class implements a genotype with integer space representation
  class IntegerVectorGenotypeSpace
    def initialize(opts)
      @random_func = opts[:random_func]

      @dimensions = opts[:dimensions].to_i
      unless @dimensions and @dimensions > 0
        raise ArgumentError, 'Must have positive integer dimensions'
      end

      # TODO: enable to choose which recombination function to use
      case opts[:recombination_type].to_s
      when /intermediate/i
        @recombination_func = :intermediate_recombination
      when /line/i
        @recombination_func = :line_recombination
      else
        raise ArgumentError, 'Recombination function must be either line or intermediate!'
      end
    end

    def get_random
      if @random_func
        @random_func.call
      else
        # TODO: implement this
      end
    end

    # reproduction with random geometric mutation
    # and intermediate recombination
    def reproduce_from(p1, p2, mutation_rv, recombination_rv)
      # make copies of p1 and p2
      # (we're only interested in the :genotype key)
      c1 = { :genotype => p1[:genotype].dup }
      c2 = { :genotype => p2[:genotype].dup }

      # mutation comes first
      random_geometric_mutation(c1[:genotype], mutation_rv)
      random_geometric_mutation(c2[:genotype], mutation_rv)

      # and then recombination
      send(@recombination_func, c1[:genotype], c2[:genotype], recombination_rv)

      return c1, c2
    end


    private

      def random_geometric_mutation(g, mutation_rv)
        g.each_index do |i|
          # being sampled from a geometric distribution, delta will always
          # be a non-negative integer (that is, 0 or greater)
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

      def intermediate_recombination(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        # recombination
        g1.each_index do |i|
          begin
            alpha = recombination_rv.next
            beta  = recombination_rv.next
            t = (alpha * g1[i] + (1.0 - alpha) * g2[i] + 0.5).floor
            s = ( beta * g2[i] + (1.0 -  beta) * g1[i] + 0.5).floor
          end # until t >= 0 and s >= 0 # TODO: implement within-bounds condition checking
          g1[i] = t
          g2[i] = s
        end
      end

      def line_recombination(g1, g2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'g1 and g2 must have the same dimension' unless g1.size == g2.size

        alpha = recombination_rv.next
        beta  = recombination_rv.next

        # recombination
        g1.each_index do |i|
          t = (alpha * g1[i] + (1.0 - alpha) * g2[i] + 0.5).floor
          s = ( beta * g2[i] + (1.0 -  beta) * g1[i] + 0.5).floor
          # if t >= 0 and s >= 0 # TODO: implement within-bounds condition checking
            g1[i] = t
            g2[i] = s
          # end
        end
      end

  end

end
