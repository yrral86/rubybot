#!/usr/bin/env ruby

require 'mtgox'

$:.unshift '.'
require 'settings'

def log(msg)
  puts "#{Time.now.to_s} #{msg}"
end

def retry_forever
  while true
    begin
      return yield
    rescue Exception => e
      log("Exception: #{e.message}")
      log("Backtrace: #{e.backtrace}")
      sleep 1
    end
  end
end

module MtGox
  class Client
    def buy_id(amount, price)
      retry_forever do
        post('/api/0/buyBTC.php', {:amount => amount, :price => price})['oid']
      end
    end

    def sell_id(amount, price)
      retry_forever do
        post('/api/0/sellBTC.php', {:amount => amount, :price => price})['oid']
      end
    end
  end
end

class ExchangeInterface
  def initialize(dry_run=false)
    @dry_run = dry_run
    MtGox.configure do |c|
      c.key = BotSettings::KEY
      c.secret = BotSettings::SECRET
    end
    @client = MtGox
    @decimals = 5
  end

  def cancel_all_orders
    return if @dry_run

    orders = order_array
    orders.each do |order|
      # skip inactive orders to avoid 404
      next if order.id.to_s[0] == 'X'

      type = :buy if order.class == MtGox::Buy
      type ||= :sell

      log("Cancelling: #{type} #{order.amount}@#{order.price}")
      retry_forever {@client.cancel(order.id)}
    end
  end

  def get_ticker
    t = retry_forever {@client.ticker}
    {:last => t.price, :buy => t.buy, :sell => t.sell}
  end

  def get_trade_data
    if @dry_run
      btc = BotSettings::DRY_BTC
      usd = BotSettings::DRY_USD
      orders = []
    else
      orders = order_array
      balances = retry_forever {@client.balance}
      balances.each do |b|
        btc = b.amount if b.currency == "BTC"
        usd = b.amount if b.currency == "USD"
      end
    end
    {:btc => btc, :usd => usd, :orders => orders}
  end

  def place_order(price, amount, type)
    if @dry_run
      log("#{type.to_s.capitalize}: #{amount}@#{price}")
      return
    else
      if type == :buy
        order_id = @client.buy_id(amount, price)
      elsif type == :sell
        order_id = @client.sell_id(amount, price)
      else
        log("invalid order type")
        exit
      end

      log("#{type.to_s.capitalize}: #{amount}@#{price} id: #{order_id}")
      return order_id
    end
  end

  private
  def order_array
    o = retry_forever {@client.orders}
    o[:buys] + o[:sells]
  end
end

class OrderManager
  def initialize
    @exchange = ExchangeInterface.new(BotSettings::DRY_RUN)
    @start_time = Time.now
    reset
  end

  def reset
    @exchange.cancel_all_orders
    @orders = {}

    ticker = @exchange.get_ticker
    @start_position = ticker[:last]
    trade_data = @exchange.get_trade_data
    @start_btc = trade_data[:btc]
    @start_usd = trade_data[:usd]
    log("BTC: #{@start_btc} USD: #{@start_usd}")

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
    (@start_position * (1 + BotSettings::INTERVAL)**index).round(BotSettings::DECIMAL_PLACES)
  end

  def place_order(index, type)
    position = get_position(index)
    order_id = @exchange.place_order(position, BotSettings::ORDER_SIZE, type)
    @orders[index] = {:id => order_id, :type => type}
  end

  def check_orders
    trade_data = @exchange.get_trade_data
    order_ids = trade_data[:orders].collect {|o| o.id}
    old_orders = @orders.dup
    print_status = false

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
        print_status = true
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
        low_index += 1
      end
      Range.new(1, BotSettings::ORDER_PAIRS - num_sells).each do |i|
        place_order(high_index + i, :sell)
      end
    end


    if print_status
      btc = trade_data[:btc]
      usd = trade_data[:usd]
      btc_profit = btc - @start_btc
      usd_profit = usd - @start_usd
      base_price = usd_profit.abs/btc_profit.abs
      log("Profit: #{btc_profit} BTC #{usd_profit} USD, Base Price: #{base_price}, Run Time: #{Time.now - @start_time}")
    end
  end

  def run_loop
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

om = OrderManager.new
om.run_loop
