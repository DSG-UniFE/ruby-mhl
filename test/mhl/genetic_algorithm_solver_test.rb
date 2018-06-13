require 'test_helper'

describe MHL::GeneticAlgorithmSolver do

  let :logger do
    :stderr
  end

  let :log_level do
    ENV['DEBUG'] ? Logger::DEBUG : Logger::WARN
  end

  it 'should accept bitstring representation genotypes' do
    MHL::GeneticAlgorithmSolver.new(
      population_size: 128,
      genotype_space_type: :bitstring,
      mutation_threshold: 0.5,
      recombination_threshold: 0.5,
      genotype_space_conf: {
        bitstring_length: 120,
      },
      logger: logger,
      log_level: log_level,
    )
  end

  it 'should accept integer representation genotypes' do
    MHL::GeneticAlgorithmSolver.new(
      population_size: 128,
      genotype_space_type: :integer,
      mutation_probability: 0.5,
      recombination_probability: 0.5,
      genotype_space_conf: {
        dimensions: 6,
        recombination_type: :intermediate,
      },
      logger: logger,
      log_level: log_level,
    )
  end

  it 'should solve a 2-dimension parabola in integer space' do
    solver = MHL::GeneticAlgorithmSolver.new(
      population_size: 40,
      genotype_space_type: :integer,
      mutation_probability: 0.5,
      recombination_probability: 0.5,
      genotype_space_conf: {
        dimensions: 2,
        recombination_type: :intermediate,
        random_func: lambda { Array.new(2) { rand(20) } }
      },
      exit_condition: lambda {|generation,best_sample| best_sample[:fitness] == 0},
      logger: logger,
      log_level: log_level,
    )
    solver.solve(Proc.new{|genotype| -(genotype[0]**2 + genotype[1]**2) })
  end

end
