require 'rubygems'
require 'json'
require 'net/http'

def query_metro(key, query_url, query_parameter = nil)
  url = query_url + key
  resp = Net::HTTP.get_response(URI.parse(url))
  data = resp.body
  result = JSON.parse(data)
  #puts data
  return result
end

def station_type(station_code)
  start_stations = ["A15", "A11"]
  end_stations = ["B11", "B08"]
  return :start if start_stations.include?(station_code)
  return :end if end_stations.include?(station_code)
  return :unknown
end

class PredictedTrain
  attr_accessor :cars, :destination_code, :time, :group, :location_code, :type
  def initialize(cars, destination_code, time, location_code, group, line)
    @cars = cars
    @destination_code = destination_code
    @time = convert_minutes(time)
    @location_code = location_code
    @group = group
    @line = line
    @type = station_type(destination_code)
  end
  def to_s
    "Location Code: #{@location_code}\nDestination Code: #{@destination_code}\nTime: #{@time}\n" +
      "Type: #{@type}\nLine: #{@line}\nGroup: #{@group}\n"
  end
end

class Train
  attr_accessor :predictions, :direction, :velocity
  def initialize(head_station, direction)
    @predictions = [head_station]
    @direction = direction
    @velocity = velocity
  end
  def to_s
    returnstring = "Train:\n---------\n"
    @predictions.each do |predicted_train|
      returnstring += "Location: #{predicted_train.location_code}\nTime: #{predicted_train.time}\nDestination: #{predicted_train.destination_code}\n\n"
    end
    returnstring
  end
  def calculate_velocity(line)
    if @predictions.length > 1
      distance = (line[(@predictions.first.location_code)].station_location - line[(@predictions.last.location_code)].station_location).abs
      return distance
    else
      return nil
    end
  end
end

class Station
  attr_accessor :name, :code, :location, :next, :previous, :predicted_trains
  def initialize(station_name, station_code, station_location)
    @name = station_name
    @code = station_code
    @location = station_location
    @next = nil
    @previous = nil
    @predicted_trains = []
  end 
  def to_s
    "Name: #{@name}\nCode: #{@code}\nLocation: #{@location}\n"
  end
end

class Line
  def initialize(line_array)
    @line_array = line_array
    @line_hash = {}
    @line_array.each do |station|
      @line_hash[station.code] = station
    end
  end
  def [](argument)
    if argument.kind_of? String
      return @line_hash[argument]
    elsif argument.kind_of? Integer
      return @line_array[argument]
    else
      return nil
    end
  end
  def each
    @line_array.each {|station| yield station}
  end
  def reverse_each
    @line_array.reverse_each{|station| yield station}
  end 
  def each_index
    @line_array.each_index {|index| yield index}
  end 
  def each_key
    @line_hash.each_key {|key| yield key}
  end
  def each_value
    @line_hash.each_value {|value| yield value}
  end
  def each_pain
    @line_hash.each_pair {|key, value| yield key, value}
  end
  def length
    @line_array.length
  end
  def first
    @line_array.first
  end
  def last
    @line_array.last
  end
  def add_predicted_train(predicted_train)
    @line_hash[predicted_train.location_code].predicted_trains << predicted_train unless predicted_train.location_code == ""
  end
  def sort_predictions
    @line_array.each do |station|
      station.predicted_trains.sort_by! do |predicted_train|
        if predicted_train.time.nil?
          next(20000)
        else
          next(predicted_train.time)
        end
      end
    end
  end
end   
      
def convert_minutes(minutes)
  if (minutes == "ARR") || (minutes == "BRD")
    return 0
  elsif (minutes == "" || minutes == "---")
    return nil
  else
    return Integer(minutes)
  end
end

def build_real_train(station, train, polarity)
	last_train = train.predictions.last
	last_time = last_train.time
	candidate_prediction = nil
  station.predicted_trains.each do |predicted_train|
    if (predicted_train.type == polarity) && !(predicted_train.time.nil?)
      if (predicted_train.time <= last_time) && (predicted_train.destination_code == last_train.destination_code)
        if candidate_prediction.nil?
          candidate_prediction = predicted_train
        elsif predicted_train.time <= candidate_prediction.time
          candidate_prediction = predicted_train
        end
      end
    end
  end
  if candidate_prediction.nil?
    return
  else
    train.predictions << candidate_prediction
    station.predicted_trains.delete(candidate_prediction)
    if polarity == :start
      build_real_train(station.next, train, polarity) unless station.next.nil?
    elsif polarity == :end
      build_real_train(station.previous, train, polarity) unless station.previous.nil?
    end
  end
  return
end

def consolidate_definite_trains(line, trains, polarity)
  line.sort_predictions
  if polarity == :start
    line.each do |station|
      station.predicted_trains.delete_if do |predicted_train|   
        if (predicted_train.type == polarity) && !(predicted_train.time.nil?)
          new_train = Train.new(predicted_train, predicted_train.type)
          build_real_train(station.next, new_train, polarity) unless station.next == nil
          trains << new_train
          next(true)
        else
          next(nil)
        end
      end
    end
  elsif polarity == :end
    line.reverse_each do |station|
      station.predicted_trains.delete_if do |predicted_train|
        if (predicted_train.type == polarity) && !(predicted_train.time.nil?)
          new_train = Train.new(predicted_train, predicted_train.type)
          build_real_train(station.previous, new_train, polarity) unless station.previous == nil
          trains << new_train
          next(true)
        else
          next(nil)
        end
      end
    end
  end  
end


key = "qy4ybdh9by94z7j3yehkmzde"

puts "Getting station data..."
query = "http://api.wmata.com/Rail.svc/json/JPath?FromStationCode=A15&ToStationCode=B11&api_key="
puts "Retrieved station data,\nparsing now..."
station_list = query_metro(key, query)
red_line_array = []
# location accumulates distance coordinate of station
location = 0
station_list["Path"].each do |current_station|
  location += Integer(current_station["DistanceToPrev"])
  new_station = Station.new(current_station["StationName"], current_station["StationCode"], location)
  red_line_array << new_station
  #puts new_station.to_s
end

red_line_array.each_index do |index|
  if index == 0
    red_line_array[index].previous = nil
    red_line_array[index].next = red_line_array[index + 1]
  elsif index == (red_line_array.length - 1)
    red_line_array[index].previous = red_line_array[red_line_array.length - 2]
    red_line_array[index].next = nil
  else
    red_line_array[index].previous = red_line_array[index - 1]
    red_line_array[index].next = red_line_array[index + 1]
  end
end
red_line = Line.new(red_line_array)
# construct train arrival query
query = "http://api.wmata.com/StationPrediction.svc/json/GetPrediction/"
argument = ""
red_line.each_key {|code| argument += (code + ",")}
argument.chomp!(",")
query = query + argument + "?api_key="

train_list = query_metro(key, query)["Trains"]
train_list.each do |train|
  red_line.add_predicted_train(PredictedTrain.new(train["Car"], train["DestinationCode"],
          train["Min"], train["LocationCode"], train["Group"], train["Line"]))
end
start_trains = []
consolidate_definite_trains(red_line, start_trains, :start)
end_trains = []
consolidate_definite_trains(red_line, end_trains, :end)
puts "START TRAINS\n-----------------------------------\n"
start_trains.each {|train| puts train}


puts "END TRAINS\n-----------------------------------\n"
end_trains.each {|train| puts train}
##############

puts red_line["A10"].name




