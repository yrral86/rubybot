class OrderManager
  def initialize
    @positions = {}
    @position_sizes = {}
    @exchange = ExchangeInterface.new(BotSettings::DRY_RUN)
    @start_time = Time.now
    @exchange.cancel_all_orders
    @thread_pool = []
    puts "initialized OrderManager" if BotSettings::DEBUG
    self
  end

  def join
    @thread_pool.each do |t|
      t.join
    end
  end

  def new_deposit_address
    @exchange.new_deposit_address
  end

  def reset(start_position=nil)
    @orders = {}

    ticker = @exchange.get_ticker
    @start_position = start_position
    @start_position ||= ticker[:last]
    trade_data = @exchange.get_trade_data
    @start_btc = trade_data[:btc]
    @start_usd = trade_data[:usd]
    log("BTC: #{@start_btc} USD: #{@start_usd}, Starting Price: #{@start_position}")
    log_file("BTC: #{@start_btc} USD: #{@start_usd}, Starting Price: #{@start_position}")

    # Sanity Check
    if get_position(-1) >= ticker[:sell] or get_position(1) <= ticker[:buy]
      log("sanity check failed, data screwy")
      exit
    end

    Range.new(1, BotSettings::ORDER_PAIRS).each do |i|
      place_order(-i, :buy)
      place_order(i, :sell)
    end

    if BotSettings::DRY_RUN
      exit
    end
  end

  def get_position(index)
    @positions[index] ||= (@start_position * (1 + BotSettings::INTERVAL)**index).round(BotSettings::DECIMAL_PLACES)
  end

  def get_position_size(index)
    @position_sizes[index] ||=
      (BotSettings::ORDER_SIZE*(@start_position/get_position(index))+BotSettings::ORDER_SIZE)/2
  end

  def place_order(index, type)
    position = get_position(index)
    size = get_position_size(index)
    order_id = @exchange.place_order(position, size, type)
    @orders[index] = {:id => order_id, :type => type, :price => position}
  end

  def check_orders
    trade_data = @exchange.get_trade_data
    order_ids = trade_data[:orders].collect {|o| o.id}
    old_orders = @orders.dup
    print_status = false
    order_price = 0

    old_orders.each_pair do |index, order|
      unless order_ids.include? order[:id]
        @fast_checks = 8
        log("Order filled, id: #{order[:id]}")
        @orders.delete(index)
        if order[:type] == :buy
          place_order(index + 1, :sell)
        else
          place_order(index - 1, :buy)
        end
        order_price = order[:price]
        print_status(trade_data, order_price)
      end
    end

    num_buys = 0
    num_sells = 0

    @orders.each_pair do |index, order|
      if order[:type] == :buy
        num_buys += 1
      else
        num_sells += 1
      end
    end

    if num_buys < BotSettings::ORDER_PAIRS
      low_index = min(@orders.keys)
      if num_buys == 0
        # No buy orders left, leave a gap
        low_index -= 1
      end
      Range.new(1, BotSettings::ORDER_PAIRS - num_buys).each do |i|
        place_order(low_index - i, :buy)
      end
    end

    if num_sells < BotSettings::ORDER_PAIRS
      high_index = max(@orders.keys)
      if num_sells == 0
        # No sell orders left, leave a gap
        high_index += 1
      end
      Range.new(1, BotSettings::ORDER_PAIRS - num_sells).each do |i|
        place_order(high_index + i, :sell)
      end
    end
  end

  def print_status(trade_data, order_price)
      btc = trade_data[:btc]
      usd = trade_data[:usd]
      btc_profit = btc - @start_btc
      usd_profit = usd - @start_usd
      base_price = usd_profit.abs/btc_profit.abs
      log("\n\nProfit: #{btc_profit} BTC #{usd_profit} USD, Base Price: #{base_price}, Run Time: #{Time.now - @start_time}\n")
      log_file("#{btc_profit},#{usd_profit},#{order_price},#{Time.now - @start_time}")
  end

  def wait_for_price(price, mode=:gt)
    log("waiting for price: $#{price}/BTC")
    price_hit = false
    until price_hit
      ticker = @exchange.get_ticker
      if mode == :gt
        price_hit = true if ticker[:last] >= price
      elsif mode == :lt
        price_hit = true if ticker[:last] <= price
      end
      sleep 20
    end
  end

  def stop_order(price, amount, type)
    log("stop order: #{type.capitalize} #{amount}BTC@$#{price}")
    @thread_pool << Thread.new do
      ticker = @exchange.get_ticker
      if type == :buy
        mode = :gt
        order_price = 100000
      elsif type == :sell
        mode = :lt
        order_price = 0.000001
      end
      wait_for_price(price, mode)
      log("executing stop order: #{type.capitalize} #{amount}BTC@$#{price}")
      @exchange.place_order(order_price, amount, type)
    end
  end

  def run_loop
    log_file("\n\n\nNew run")
    log_file("ORDER_PAIRS,ORDER_SIZE,INTERVAL")
    log_file("#{BotSettings::ORDER_PAIRS},#{BotSettings::ORDER_SIZE},#{BotSettings::INTERVAL}")
    log_file("btc_profit,usd_profit,last_trade_price,time")
    reset
    @fast_checks = 0
    while true
      if @fast_checks > 0
        sleep 15
        @fast_checks -= 1
      else
        sleep 60
      end
      check_orders
      print "."
      $stdout.flush
    end
  end

  private
  def min(array)
    a = array.dup
    min = a.shift
    while n = a.shift
      min = n < min ? n : min
    end
    min
  end

  def max(array)
    a = array.dup
    max = a.shift
    while n = a.shift
      max = n > max ? n : max
    end
    max
  end
end
