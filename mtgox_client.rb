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

    private
    def request_with_error_checking(method, path, options)
      request_without_error_checking(method, path, options).tap{|x|
        puts x if x['error']
      }
    end
    alias_method_chain :request, :error_checking
  end
end
