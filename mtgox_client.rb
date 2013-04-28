require 'mtgox'
require 'active_support/core_ext/module'

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
