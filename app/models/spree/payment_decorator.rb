Spree::Payment.class_eval do
  attr_accessible :source, :source_attributes, :amount, :order_id,
    :created_at, :updated_at, :source_id, :source_type, :payment_method_id,
    :state, :response_code, :avs_response

  before_save :create_payment_profile, :if => :profiles_supported?

  private
  # payment.after_save usually saves the credit card to the CIM gateway, if that is enabled. 
  # For reservebar, we need to save it to all retailer's gateways instead and make sure that they are added 
  # to the customer's existing gateway_customer_profile, rather than having anew one created all the time 
  # We only do that for logged-in users, for logged-out users, we simply tokenize the card in the old fashioned way.
  def create_payment_profile_original
    return unless source.is_a?(Spree::Creditcard) && source.number && !source.has_payment_profile?
    if payment_method.type == 'Spree::Gateway::BraintreeGateway'
      source.update_attributes(address_id: order.bill_address_id)
      result = Spree::Creditcard.tokenize_card_for_retailer(source,
        order.retailer, order.email, source.number)
      if result.is_a?(Braintree::ErrorResult)
        source.send(:gateway_error,
          ' Make sure payment details were enterered correctly.')
      end
    else
      payment_method.create_profile(self)
    end
  rescue ActiveMerchant::ConnectionError => e
    source.send(:gateway_error, e)
  end

  def create_payment_profile
    return unless source.is_a?(Spree::Creditcard) && source.number && !source.has_payment_profile?
    # If the user is not logged in, use the original function to just tokenize the user on a single retailer's gateway
    return create_payment_profile_original if (order.user.anonymous? || Spree::ReservebarReuseCreditCard::Config.enabled != true)
    card_number = source.number # save it for later so we can reload other items
    begin
      # Tokenize the card for the order's retailer
      # save return value
      response = Spree::Creditcard.tokenize_card_for_retailer(source, order.retailer, order.user, card_number)
      unless response.is_a?(Braintree::ErrorResult)
        source.reload
        # Run tokenization for the other retailers in the background
        # only if successful before
        Spree::Creditcard.delay.tokenize_card_on_other_retailers(order.retailer.id, source, order.user.id, card_number, source.verification_value)
      else
        source.send(:gateway_error,
          ' Make sure payment details were enterered correctly.')
      end
    rescue ActiveMerchant::ConnectionError => e
      source.send(:gateway_error, e)
    end
  end

end
