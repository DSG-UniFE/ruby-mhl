require 'test_helper'

describe MHL::DominanceUtils do
  describe '.dominates?' do
    it 'should return true when a dominates b in all objectives' do
      assert MHL::DominanceUtils.dominates?([1.0, 2.0], [3.0, 4.0])
    end

    it 'should return true when a dominates b (equal in one, better in another)' do
      assert MHL::DominanceUtils.dominates?([1.0, 2.0], [1.0, 3.0])
    end

    it 'should return false when a and b are equal' do
      refute MHL::DominanceUtils.dominates?([1.0, 2.0], [1.0, 2.0])
    end

    it 'should return false when a is worse in one objective' do
      refute MHL::DominanceUtils.dominates?([1.0, 4.0], [2.0, 3.0])
    end

    it 'should return false when b dominates a' do
      refute MHL::DominanceUtils.dominates?([3.0, 4.0], [1.0, 2.0])
    end
  end

  describe '.fast_non_dominated_sort' do
    it 'should place all non-dominated solutions in the first front' do
      population = [
        { objectives: [1.0, 3.0] },
        { objectives: [2.0, 2.0] },
        { objectives: [3.0, 1.0] }
      ]

      fronts = MHL::DominanceUtils.fast_non_dominated_sort(population)

      assert_equal 1, fronts.size
      assert_equal [0, 1, 2], fronts[0].sort
    end

    it 'should correctly sort into multiple fronts' do
      population = [
        { objectives: [1.0, 4.0] },  # front 0
        { objectives: [2.0, 3.0] },  # front 0
        { objectives: [3.0, 2.0] },  # front 0
        { objectives: [2.0, 4.0] },  # front 1 (dominated by 0)
        { objectives: [3.0, 3.0] },  # front 1 (dominated by 1)
        { objectives: [4.0, 4.0] } # front 2 (dominated by 3,4 and transitively by 0,1,2)
      ]

      fronts = MHL::DominanceUtils.fast_non_dominated_sort(population)

      assert_equal 3, fronts.size
      assert_equal [0, 1, 2], fronts[0].sort
      assert_equal [3, 4], fronts[1].sort
      assert_equal [5], fronts[2].sort
    end

    it 'should handle a single individual' do
      population = [{ objectives: [1.0, 2.0] }]

      fronts = MHL::DominanceUtils.fast_non_dominated_sort(population)

      assert_equal 1, fronts.size
      assert_equal [0], fronts[0]
    end
  end

  describe '.crowding_distance_assignment' do
    it 'should assign infinite distance to boundary solutions' do
      population = [
        { objectives: [1.0, 5.0] },
        { objectives: [3.0, 3.0] },
        { objectives: [5.0, 1.0] }
      ]
      front = [0, 1, 2]

      distances = MHL::DominanceUtils.crowding_distance_assignment(front, population)

      assert_equal Float::INFINITY, distances[0]
      assert_equal Float::INFINITY, distances[2]
    end

    it 'should assign finite distance to interior solutions' do
      population = [
        { objectives: [1.0, 5.0] },
        { objectives: [3.0, 3.0] },
        { objectives: [5.0, 1.0] }
      ]
      front = [0, 1, 2]

      distances = MHL::DominanceUtils.crowding_distance_assignment(front, population)

      assert distances[1] > 0.0
      assert distances[1] < Float::INFINITY
    end

    it 'should handle fronts with two solutions' do
      population = [
        { objectives: [1.0, 3.0] },
        { objectives: [3.0, 1.0] }
      ]
      front = [0, 1]

      distances = MHL::DominanceUtils.crowding_distance_assignment(front, population)

      assert_equal 0.0, distances[0]
      assert_equal 0.0, distances[1]
    end

    it 'should handle identical objective values gracefully' do
      population = [
        { objectives: [1.0, 1.0] },
        { objectives: [1.0, 1.0] },
        { objectives: [1.0, 1.0] }
      ]
      front = [0, 1, 2]

      distances = MHL::DominanceUtils.crowding_distance_assignment(front, population)

      # boundary points still get infinity; interior stays finite
      # (range is zero so no contribution from either objective)
      distances.each_value { |d| assert d >= 0.0 }
    end
  end
end
