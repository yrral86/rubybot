$:.unshift '.'
require 'settings'
require 'exchange_interface'
require 'order_manager'

def format_log_entry(msg)
  "#{Time.now.to_s} #{msg}"
end

def log(msg)
  puts format_log_entry(msg)
end

def log_file(msg)
  open("bot.log", "a") do |l|
    l.puts format_log_entry(msg)
  end
end

def retry_forever
  while true
    begin
      return yield
    rescue Exception => e
      log("Exception: #{e.message}")
      log_file("Exception: #{e.message}")
      log_file("Backtrace:")
      e.backtrace.each do |bt|
        log_file bt
      end
      sleep 5
    end
  end
end

om = OrderManager.new
puts om.new_deposit_address
#om.wait_for_price(100, :lt)
#om.wait_for_price(120, :gt)
#om.stop_order(6.65, 15, :buy)
#om.stop_order(5.95, 15, :sell)
#om.stop_order(4.84, 0.01, :sell)
#om.stop_order(4.845, 0.01, :buy)
om.run_loop
om.join
