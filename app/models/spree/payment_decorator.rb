Spree::Payment.class_eval do
  attr_accessible :source, :source_attributes, :amount, :order_id, :created_at, :updated_at, :source_id, :source_type, :payment_method_id, :state, :response_code, :avs_response
  
  
  private
  # payment.after_save usually saves the credit card to the CIM gateway, if that is enabled. 
  # For reservebar, we need to save it to all retailer's gateways instead and make sure that they are added 
  # to the customer's existing gateway_customer_profile, rather than having anew one created all the time 
  # We only do that for logged-in users, for logged-out users, we simply tokenize the card in the old fashioned way.
  def create_payment_profile_original
    return unless source.is_a?(Spree::Creditcard) && source.number && !source.has_payment_profile?
    payment_method.create_profile(self)
  rescue ActiveMerchant::ConnectionError => e
    source.send(:gateway_error, e)
  end
  
  def create_payment_profile
    return unless source.is_a?(Spree::Creditcard) && source.number && !source.has_payment_profile?
    # If the user is not logged in, use the original function to just tokenize the user on a single retailer's gateway
    return create_payment_profile_original if (order.user.anonymous? || Spree::ReservebarReuseCreditCard::Config.enabled != true)
    # Tokenize the card for the order's retailer
    card_number = source.number # save it for later so we can reload other items
    begin
      Spree::Creditcard.tokenize_card_for_retailer(source, order.retailer, order.user, card_number)
    rescue ActiveMerchant::ConnectionError => e
      source.send(:gateway_error, e)
    end
    source.reload
    # Run tokenization for the other retailers in the background
    Spree::Creditcard.delay.tokenize_card_on_other_retailers(order.retailer, source, order.user, card_number)
  end
  

end
