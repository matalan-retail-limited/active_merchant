require 'test_helper'

class MokaTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MokaGateway.new(dealer_code: '123', username: 'username', password: 'password')
    @credit_card = credit_card
    @amount = 100

    @options = {
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal 'Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c', response.authorization
    assert response.test?
  end

  def test_failed_purchase_with_top_level_error
    @gateway.expects(:ssl_post).returns(failed_response_with_top_level_error)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'PaymentDealer.DoDirectPayment.InvalidRequest', response.error_code
    assert_equal 'PaymentDealer.DoDirectPayment.InvalidRequest', response.message
  end

  def test_failed_purchase_with_nested_error
    @gateway.expects(:ssl_post).returns(failed_response_with_nested_error)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response

    assert_equal 'General error', response.error_code
    assert_equal 'Genel Hata(Geçersiz kart numarası)', response.message
  end

  def test_successful_authorize
    response = stub_comms do
      @gateway.authorize(@amount, credit_card, @options)
    end.check_request do |_endpoint, data, _headers|
      assert_equal 1, JSON.parse(data)['PaymentDealerRequest']['IsPreAuth']
    end.respond_with(successful_response)
    assert_success response

    assert_equal 'Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_response_with_top_level_error)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_response)

    response = @gateway.capture(@amount, 'Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c', @options)
    assert_success response
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture(@amount, 'wrong-authorization', @options)
    assert_failure response
    assert_equal 'PaymentDealer.DoCapture.PaymentNotFound', response.error_code
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(0, 'Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c')
    assert_success response
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund(0, '')
    assert_failure response
    assert_equal 'PaymentDealer.DoCreateRefundRequest.OtherTrxCodeOrVirtualPosOrderIdMustGiven', response.error_code
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_response)

    response = @gateway.void('Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c')
    assert_success response
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_void_response)

    response = @gateway.void('')
    assert_failure response
    assert_equal 'PaymentDealer.DoVoid.InvalidRequest', response.error_code
  end

  def test_buyer_information_is_passed
    options = @options.merge({
      billing_address: address,
      email: 'safiye.ali@example.com'
    })

    stub_comms do
      @gateway.authorize(@amount, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      buyer_info = JSON.parse(data)['PaymentDealerRequest']['BuyerInformation']
      assert_equal buyer_info['BuyerFullName'], [@credit_card.first_name, @credit_card.last_name].join(' ')
      assert_equal buyer_info['BuyerEmail'], 'safiye.ali@example.com'
      assert_equal buyer_info['BuyerAddress'], options[:billing_address][:address1]
      assert_equal buyer_info['BuyerGsmNumber'], options[:billing_address][:phone]
    end.respond_with(successful_response)
  end

  def test_basket_product_is_passed
    options = @options.merge({
      basket_product: [
        {
          product_id: 333,
          product_code: '0173',
          unit_price: 19900,
          quantity: 1
        },
        {
          product_id: 281,
          product_code: '38',
          unit_price: 5000,
          quantity: 1
        }
      ]
    })

    stub_comms do
      @gateway.authorize(24900, @credit_card, options)
    end.check_request do |_endpoint, data, _headers|
      basket = JSON.parse(data)['PaymentDealerRequest']['BasketProduct']
      basket.each_with_index do |product, i|
        assert_equal product['ProductId'], options[:basket_product][i][:product_id]
        assert_equal product['ProductCode'], options[:basket_product][i][:product_code]
        assert_equal product['UnitPrice'], (sprintf '%.2f', options[:basket_product][i][:unit_price] / 100)
        assert_equal product['Quantity'], options[:basket_product][i][:quantity]
      end
    end.respond_with(successful_response)
  end

  private

  def successful_response
    <<-RESPONSE
      {
        "Data": {
          "IsSuccessful": true,
          "ResultCode": "",
          "ResultMessage": "",
          "VirtualPosOrderId": "Test-9732c2ce-08d9-4ff6-a89f-bd3fa345811c"
        },
        "ResultCode": "Success",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end

  def successful_refund_response
    <<-RESPONSE
      {
        "Data": {
          "IsSuccessful": true,
          "ResultCode": "",
          "ResultMessage": "",
          "RefundRequestId": 2320
        },
        "ResultCode": "Success",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end

  def failed_response_with_top_level_error
    <<-RESPONSE
      {
        "Data": null,
        "ResultCode": "PaymentDealer.DoDirectPayment.InvalidRequest",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end

  def failed_response_with_nested_error
    <<-RESPONSE
    {
      "Data": {
        "IsSuccessful": false,
        "ResultCode": "000",
        "ResultMessage": "Genel Hata(Geçersiz kart numarası)",
        "VirtualPosOrderId": ""
      },
      "ResultCode": "Success",
      "ResultMessage": "",
      "Exception": null
    }
    RESPONSE
  end

  def failed_capture_response
    <<-RESPONSE
      {
        "Data": null,
        "ResultCode": "PaymentDealer.DoCapture.PaymentNotFound",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end

  def failed_refund_response
    <<-RESPONSE
      {
        "Data": null,
        "ResultCode": "PaymentDealer.DoCreateRefundRequest.OtherTrxCodeOrVirtualPosOrderIdMustGiven",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end

  def failed_void_response
    <<-RESPONSE
      {
        "Data": null,
        "ResultCode": "PaymentDealer.DoVoid.InvalidRequest",
        "ResultMessage": "",
        "Exception": null
      }
    RESPONSE
  end
end
