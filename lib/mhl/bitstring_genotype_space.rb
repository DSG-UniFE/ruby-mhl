require 'bitstring'

module MHL

  # This class implements a genotype with bitstring representation
  class BitstringGenotypeSpace
    def initialize(opts)
      @bitstring_length = opts[:bitstring_length].to_i
      unless @bitstring_length and @bitstring_length > 0
        raise ArgumentError, 'Must have positive integer bitstring_length'
      end

      @random_func = opts[:random_func] || default_random_func(opts[:random_one_to_zero_ratio] || 1.0)
    end

    def get_random
      @random_func.call
    end

    # reproduction with bitflip mutation and one-point crossover
    def reproduce_from(p1, p2, mutation_rv, recombination_rv)
      # make copies of p1 and p2
      # (we're only interested in the :genotype key)
      c1 = { :genotype => p1[:genotype].dup }
      c2 = { :genotype => p2[:genotype].dup }

      # mutation comes first
      bitflip_mutation(c1[:genotype], mutation_rv)
      bitflip_mutation(c2[:genotype], mutation_rv)

      # and then recombination
      c1[:genotype], c2[:genotype] =
        onepoint_crossover(c1[:genotype], c2[:genotype], recombination_rv)

      return c1, c2
    end

    private

      def bitflip_mutation(bitstring, mutation_rv)
        # TODO: disable this check in non-debugging mode
        unless bitstring.length == @bitstring_length
          raise 'Error! Different bit string sizes!'
        end

        @bitstring_length.times do |i|
          if mutation_rv.next < @mutation_threshold
            bitval       = bitstring[i]
            bitstring[i] = (bitval == 1 ? '0' : '1')
          end
        end
      end

      def onepoint_crossover(bitstring1, bitstring2, recombination_rv)
        # TODO: disable this check in non-debugging mode
        unless bitstring1.length == @bitstring_length and bitstring2.length == @bitstring_length
          raise 'Error! Different bit string sizes!'
        end

        if recombination_rv.next < @recombination_threshold
          size     = bitstring1.length
          point    = 1 + rand(size - 2)
          hi_mask  = bitstring1.mask(point, BitString::LOW_END) # lowest point bits
          low_mask = bitstring1.mask(size - point, BitString::HIGH_END) # highest size-point bits
          new_b1   = (bitstring1 & hi_mask) | (bitstring2 & low_mask)
          new_b2   = (bitstring2 & hi_mask) | (bitstring1 & low_mask)
          return new_b1, new_b2
        end
        return bitstring1, bitstring2
      end

      def default_random_func(one_to_zero_ratio)
        random_percentage_of_ones = one_to_zero_ratio / (1.0 + one_to_zero_ratio)
        lambda do
          str = (0...@bitstring_length).inject("") do |s,i|
            s << ((rand < random_percentage_of_ones) ? '1' : '0')
          end
          BitString.new(str, size)
        end
      end

  end

end
