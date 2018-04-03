require 'test_helper'

class RowTest < TransactionalTest
  def test_it_supports_setting_values
    date = '2001-01-01'
    refute_equal Airport.last.temperature[date...'2001-01-01 03:00'], [1,2,3]
    # Update existing
    Airport.last.temperature[date] = [1,2,3]
    assert_equal Airport.last.temperature[date...'2001-01-01 03:00'], [1,2,3]

    future_date = '3001-01-01'
    refute_equal Airport.last.temperature[future_date...'3001-01-01 03:00'], [1,2,3]
    # Create new
    Airport.last.temperature[future_date] = [1,2,3]
    assert_equal Airport.last.temperature[future_date...'3001-01-01 03:00'], [1,2,3]

    # Large update + create together
    random = M.blank(columns: 50_000).random!
    Airport.last.temperature[date] = random
    assert_equal Airport.last.temperature[date...(date.to_time + 50_000.hour).to_s].round(2), random.round(2)
  end

  def test_it_supports_getting_values
    temperatures = Airport.first.temperature['2001-01-01'...'2002-01-01']
    # Assert many non-zero values
    assert temperatures.where.length > 8000
    # Assert correct length
    assert_equal temperatures.length, 8760

    # Length test 2
    temperatures = Airport.first.temperature['2001-01-01'...'2001-06-01']
    assert_equal temperatures.length, 3625

    # Length test 3 (inclusive end)
    temperatures = Airport.first.temperature['2001-01-01'..'2001-06-01']
    assert_equal temperatures.length, 3626

    # Length test 4 start == end
    temperatures = Airport.first.temperature['2001-01-01'..'2001-01-01']
    assert_equal temperatures.length, 1

    # Length test 5 (error - negative array size)
    assert_raises ArgumentError do
      Airport.first.temperature['2001-01-01'...'2000-01-01']
    end
  end

  def test_it_supports_getting_nonexistent_values
    no_data_date  = '3001-01-01'
    no_data_date2 = '3002-01-01'

    # DF 1
    assert_equal Airport.first.temperature[no_data_date].to_f, 0
    assert_equal Airport.first.temperature[no_data_date...no_data_date2].length, 8760
    assert_equal Airport.first.temperature[no_data_date2].to_f, 0

    # DF 2
    assert_equal Airport.first.departures[no_data_date].to_f, 0
    assert_equal Airport.first.departures[no_data_date...no_data_date2].length, 8760
    assert_equal Airport.first.departures[no_data_date2].to_f, 0

    # DF 3
    assert_equal Airport.first.departures[no_data_date].to_f, 0
    assert_equal Airport.first.departures[no_data_date...no_data_date2].length, 8760
    assert_equal Airport.first.departures[no_data_date2].to_f, 0

    assert_equal Airport.first.status[1_000_000], [:normal]
    assert_equal Airport.first.status[1_000_000..1_000_001], [:normal, :normal]
  end
end