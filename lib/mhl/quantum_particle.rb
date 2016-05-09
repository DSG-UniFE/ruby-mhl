require 'securerandom'

require 'mhl/generic_particle'


module MHL
  class QuantumParticle < GenericParticle
    attr_reader :position

    # move particle using QPSO - Type II algorithm
    def move(alpha, mean_best, swarm_attractor)
      raise 'Particle attractor is nil!' if @attractor.nil?

      dimension = @position.size

      # phi represents the \phi_{i,n} parameter in [SUN11], formula 4.83
      phi = Array.new(dimension) { SecureRandom.random_number }

      # p_i represents the p_{i,n} parameter in [SUN11], formulae 4.82 and 4.83
      p_i = phi.zip(@attractor[:position], swarm_attractor[:position]).map do |phi_j,p_j,g_j|
        phi_j * p_j + (1.0 - phi_j) * g_j
      end

      # delta represents the displacement for the current position.
      # See [SUN11], formula 4.82
      delta = @position.zip(mean_best).map do |x_n,c_n| 
        # \alpha * | X_{i,n} - C_n | * log(\frac{1}{u_{i,n+1}})
        alpha * (x_n - c_n).abs * Math.log(1.0 / SecureRandom.random_number)
      end

      # update position
      if SecureRandom.random_number < 0.5
        @position = p_i.zip(delta).map {|p_in,delta_n| p_in + delta_n }
      else
        @position = p_i.zip(delta).map {|p_in,delta_n| p_in - delta_n }
      end

      @position
    end

    # implement confinement à la SPSO 2011. for more information, see equations
    # 3.14 of [CLERC12].
    def remain_within(constraints)
      @position = @position.map.with_index do |x_j,j|
        d_max = constraints[:max][j]
        d_min = constraints[:min][j]
        if x_j > d_max
          # puts "resetting #{j}-th position component #{x_j} to #{d_max}"
          x_j = d_max
        elsif x_j < d_min
          # puts "resetting #{j}-th position component #{x_j} to #{d_min}"
          x_j = d_min
        end
        x_j
      end
    end

  end
end
