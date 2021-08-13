require 'test_helper'

class RemoteMokaTest < Test::Unit::TestCase
  def setup
    @gateway = MokaGateway.new(fixtures(:moka))

    @amount = 100
    @credit_card = credit_card('5269111122223332', month: '10', year: '2024')
    @declined_card = credit_card('4000300011112220')
    @options = {
      description: 'Store Purchase'
    }
  end

  def test_invalid_login
    gateway = MokaGateway.new(dealer_code: '', username: '', password: '')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match 'PaymentDealer.CheckPaymentDealerAuthentication.InvalidAccount', response.message
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Success', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response

    assert_equal 'PaymentDealer.DoDirectPayment.VirtualPosNotAvailable', response.message
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'Success', capture.message
  end

  def test_failed_authorize
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'PaymentDealer.DoDirectPayment.VirtualPosNotAvailable', response.error_code
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 0.1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'PaymentDealer.DoCapture.OtherTrxCodeOrVirtualPosOrderIdMustGiven', response.message
  end

  # # Moka does not allow a same-day refund on a purchase/capture. In order to test refund,
  # # you must pass a reference that has 'matured' at least one day.
  # def test_successful_refund
  #   my_matured_reference = 'REPLACE ME'
  #   assert refund = @gateway.refund(0, my_matured_reference)
  #   assert_success refund
  #   assert_equal 'Success', refund.message
  # end

  # # Moka does not allow a same-day refund on a purchase/capture. In order to test refund,
  # # you must pass a reference that has 'matured' at least one day. For the purposes of testing
  # # a partial refund, make sure the original transaction being referenced was for an amount
  # # greater than the 'partial_amount' supplied in the test.
  # def test_partial_refund
  #   my_matured_reference = 'REPLACE ME'
  #   partial_amount = 50
  #   assert refund = @gateway.refund(partial_amount, my_matured_reference)
  #   assert_success refund
  #   assert_equal 'Success', refund.message
  # end

  def test_failed_refund
    response = @gateway.refund(@amount, '')
    assert_failure response
    assert_equal 'PaymentDealer.DoCreateRefundRequest.OtherTrxCodeOrVirtualPosOrderIdMustGiven', response.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'Success', void.message
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
    assert_equal 'PaymentDealer.DoVoid.InvalidRequest', response.message
  end
end
