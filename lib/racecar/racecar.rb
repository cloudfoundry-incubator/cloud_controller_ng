class Racecar
  def initialize(expected_race, debug=false)
    @expected_race = expected_race
    @debug = debug
  end

  def drive(id)
    id = "[#{Thread.current[:thread_id]}] #{id}"
    print("[DEBUG] #{id}\n") if @debug

    check_not_empty(id)
    while @expected_race.first.id != id
      sleep(0.1)
      check_not_empty(id)
    end

    print("#{id}\n")
    @expected_race.first.assert
    @expected_race.shift
  end

  private

  def check_not_empty(id)
    throw "'#{id}' waited for its turn indefinitely" if @expected_race.empty?
  end

  Turn = Struct.new(:id, :assertion)
  class Turn
    def self.from(id, &assertion)
      new(id, assertion)
    end

    def assert
      assertion && assertion.call
    end
  end

  class NoneRacecar
    def drive(*); end
  end

  NONE = NoneRacecar.new
end

