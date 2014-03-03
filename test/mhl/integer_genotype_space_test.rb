require 'test_helper'

describe MHL::IntegerVectorGenotypeSpace do
  it 'should refuse to work with non-positive dimensions' do
    assert_raises(ArgumentError) do
      MHL::IntegerVectorGenotypeSpace.new(
        :dimensions         => -rand(100),
        :recombination_type => :intermediate,
        # :random_func        => lambda { Array.new(2) { rand(20) } }
      )
    end
  end

  it 'should refuse to work with non- line or intermediate recombination' do
    assert_raises(ArgumentError) do
      MHL::IntegerVectorGenotypeSpace.new(
        :dimensions         => 2,
        :recombination_type => :something,
      )
    end
  end

  describe 'with constraints' do
    it 'should enforce constraints on generation' do
      x1 =  rand(100); x2 = x1 + rand(200)
      y1 = -rand(100); y2 = y1 + rand(200)
      is = MHL::IntegerVectorGenotypeSpace.new(
        :dimensions         => 2,
        :recombination_type => :intermediate,
        :constraints => [ { :from => x1, :to => x2 },
                          { :from => y1, :to => y2 } ]
      )
      genotype = is.get_random
      genotype.size.must_equal 2
      genotype[0].must_be :>=, x1
      genotype[0].must_be :<=, x2
      genotype[1].must_be :>=, y1
      genotype[1].must_be :<=, y2
    end

    it 'should enforce constraints on reproduction' do
      x1 =  rand(100); x2 = x1 + rand(200)
      y1 = -rand(100); y2 = y1 + rand(200)
      is = MHL::IntegerVectorGenotypeSpace.new(
        :dimensions         => 2,
        :recombination_type => :intermediate,
        :constraints => [ { :from => x1, :to => x2 },
                          { :from => y1, :to => y2 } ]
      )
      g1 = { :genotype => [ x1, y1 ] }
      g2 = { :genotype => [ x2, y2 ] }
      a, b = is.reproduce_from(
        g1, g2,
        ERV::RandomVariable.new(:distribution           => :geometric,
                                :probability_of_success => 0.05),
        ERV::RandomVariable.new(:distribution => :uniform,
                                :min_value    => -0.25,
                                :max_value    =>  1.25)
      )
      a[:genotype][0].must_be :>=, x1
      a[:genotype][0].must_be :<=, x2
      b[:genotype][1].must_be :>=, y1
      b[:genotype][1].must_be :<=, y2
    end
  end

end
