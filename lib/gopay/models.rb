require "savon"
require "pp"

Savon.configure { |config| config.log = false }

module GoPay

  module Model
    def initialize(attributes = {})
      attributes.each do |key, value|
        instance_variable_set(:"@#{key}", value) if self.respond_to?(key)
      end
    end

  end

  class Payment
    include Model

    attr_accessor :product_name, :total_price_in_cents, :variable_symbol

    def create
      client = Savon::Client.new GoPay.configuration.urls["wsdl"]
      response = client.request "createPaymentSession" do |soap|
        soap.body = {"paymentCommand" => self.to_soap}
      end
      response = response.to_hash[:create_payment_session_response][:create_payment_session_return]
      check_common(response, "WAITING") && check_signature(response, "WAITING")
    end

    def check_common(response, status)
      response[:result] == "CALL_COMPLETED" and
          response[:result_description] == status and
          response[:variable_symbol] == variable_symbol and
          response[:product_name] == product_name and
          response[:total_price].to_i == total_price_in_cents.to_i and
          (response[:eshop_go_id].to_i == GoPay.configuration.goid.to_i or
              response[:buyer_go_id].to_i == GoPay.configuration.goid.to_i)
    end

    def check_signature(response, status)
      payment_result = PaymentResult.new({:goid => GoPay.configuration.goid,
                                  :product_name => self.product_name,
                                  :variable_symbol => self.variable_symbol,
                                  :total_price_in_cents => total_price_in_cents,
                                  :result => "CALL_COMPLETED",
                                  :session_state => status})
      GoPay::Crypt.sha1(payment_result.concat) == GoPay::Crypt.decrypt(response[:encrypted_signature])
    end


    def signature
      GoPay::Crypt.encrypt(self)
    end

    def to_soap
      {"eshopGoId" => GoPay.configuration.goid.to_i,
       "productName" => product_name,
       "totalPrice" => total_price_in_cents,
       "variableSymbol" => variable_symbol,
       "successURL" => GoPay.configuration.success_url,
       "failedURL" => GoPay.configuration.failed_url,
       "encryptedSignature" => signature}
    end

  end

  class PaymentCommand < Payment
    def concat
      [GoPay.configuration.goid, product_name.strip, total_price_in_cents, variable_symbol.strip,
       GoPay.configuration.failed_url, GoPay.configuration.success_url, GoPay.configuration.secret].map { |attr| attr }.join("|")
    end
  end

  class PaymentResult
    include Model

    attr_reader :goid, :product_name, :total_price_in_cents, :variable_symbol, :result, :session_state

    def concat
      [GoPay.configuration.goid.to_s, product_name, total_price_in_cents.to_s, variable_symbol,
       result, session_state, GoPay.configuration.secret].map { |attr| attr.strip }.join("|")
    end

  end

  class PaymentStatus

    attr_reader :goid, :product_name, :total_price_in_cents, :variable_symbol, :result, :session_state, :payment_channel

    def concat
      [GoPay.goid, product_name, total_price_in_cents, variable_symbol,
       result, session_state, payment_channel, GoPay.secret].map { |attr| attr.strip }.join("|")
    end

  end

  class PaymentSession

    attr_reader :payment_session_id

    def concat
      [GoPay.goid, payment_session_id, GoPay.secret].map { |attr| attr.strip }.join("|")
    end

  end

  class PaymentIdentity

    attr_reader :payment_session_id, :variable_symbol

    def concat
      [GoPay.goid, payment_session_id, variable_symbol, GoPay.secret].map { |attr| attr.strip }.join("|")
    end

  end

  class Buyer

    attr_reader :buyer_user_name, :buyer_email

    def concat
      [GoPay.goid, buyer_user_name, buyer_email, GoPay.secret].map { |attr| attr.strip }.join("|")
    end

  end


  class PaymentMethod
    include Model

    attr_reader :code, :offline, :payment_method, :logo

    def self.all
      client = Savon::Client.new GoPay.configuration.urls["wsdl"]
      response = client.request("paymentMethodList")
      response.to_hash[:payment_method_list_response][:payment_method_list_return][:payment_method_list_return].map do |item|
        PaymentMethod.new(item)
      end
    end

  end

end