Spree::Payment.class_eval do
  attr_accessible :source, :source_attributes, :amount, :order_id,
    :created_at, :updated_at, :source_id, :source_type, :payment_method_id,
    :state, :response_code, :avs_response

  before_save :create_payment_profile, :if => :profiles_supported?

  def build_source
    return if source_attributes.nil?
    if payment_method and payment_method.payment_source_class
      self.source = payment_method.payment_source_class.new(source_attributes)
      self.source.device_data = source_attributes[:device_data]
    end
  end

  private
  # payment.after_save usually saves the credit card to the CIM gateway, if that is enabled. 
  # For reservebar, we need to save it to all retailer's gateways instead and make sure that they are added 
  # to the customer's existing gateway_customer_profile, rather than having anew one created all the time 

  def create_payment_profile
    return unless source.is_a?(Spree::Creditcard) && source.number && !source.has_payment_profile?
    if (order.user.anonymous? || Spree::ReservebarReuseCreditCard::Config.enabled != true)
      order.user.update_attributes(email: order.email)
      source.update_attributes(address_id: order.bill_address_id)
    end
    # save it for later so we can reload other items
    card_number = source.number
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
