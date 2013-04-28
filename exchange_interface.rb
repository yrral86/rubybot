require 'mtgox_client'

class ExchangeInterface
  def initialize(dry_run=false)
    @dry_run = dry_run
    MtGox.configure do |c|
      c.key = BotSettings::KEY
      c.secret = BotSettings::SECRET
    end
    @client = MtGox
    @decimals = BotSettings::DECIMAL_PLACES
    puts "initialized ExchangeInterface" if BotSettings::DEBUG
    self
  end

  def new_deposit_address
    retry_forever {@client.address};
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
    puts "in order_array" if BotSettings::DEBUG
    o = retry_forever {@client.orders}
    puts "orders = #{o.inspect}" if BotSettings::DEBUG
    o[:buys] + o[:sells]
  end
end
