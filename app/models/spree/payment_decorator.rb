Spree::Payment.class_eval do
  attr_accessible :source, :source_attributes, :amount, :order_id, :created_at, :updated_at, :source_id, :source_type, :payment_method_id, :state, :response_code, :avs_response
  
  
  private
  # payment.after_save usually saves the credit card to the CIM gateway, if that is enabled. 
  # For reservebar, we need to save it to all retailer's gateways instead and make user that they are added 
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
    # If the user is not logged in, use the original function to just tokenize the the user on a single retailer's gateway
    return create_payment_profile_original if order.user.anonymous?
    # Tokenize the card for the order's retailer
    card_number = source.number # save it for later so we can reload other items
    begin
      tokenize_card_for_retailer(source, order.retailer, order.user, card_number)
    rescue ActiveMerchant::ConnectionError => e
      source.send(:gateway_error, e)
    end
    source.reload
    # Run tokenization for the other retailers in the background
    self.delay.tokenize_card_on_other_retailers(order.retailer, source, order.user, card_number)
  end
  
  private
  
  def tokenize_card_on_other_retailers(current_retailer, creditcard, user, card_number)
    # add card to customer profile for all other retailers, or create new customer profile and add card
    Spree::Retailer.active.each do |retailer|
      next if retailer == current_retailer
      next unless retailer.payment_method.respond_to?(:payment_profiles_supported?) && retailer.payment_method.payment_profiles_supported?
      begin
        tokenize_card_for_retailer(creditcard.dup, retailer, user, card_number)
      rescue
        # For now we don't care if this fails
      end
    end
  end
  
  # tokenize the card
  # if the creditcard passed in has been saved, use it and update it - this is used for the original retailer
  # if the card passed in a  new record, it is a duplicate of the original and needs to be saved
  def tokenize_card_for_retailer(creditcard, retailer, user, number)
    Rails.logger.warn(" ----------------------- Processing retailer #{retailer.id}  ...")
    # Setup gateway for this retailer
    gateway = retailer.payment_method
    gateway.set_provider(retailer.gateway_login, retailer.gateway_password)
    # test if the user already has a customer profile for this retailer, if not create it
    gateway_customer_profile_id = user.gateway_customer_profile_id_for_retailer(retailer)
    if gateway_customer_profile_id.blank?
      Rails.logger.warn(" ----------------------- Creating new customer profile for retailer #{retailer.id}  ...")
      result = gateway.create_gateway_customer_profile(user, retailer)
      Rails.logger.warn("  ---------------------- Result:")
      Rails.logger.warn(result.inspect)
      # TODO: error handlind of gateway errors
      gateway_customer_profile_id = result[:customer_profile_id]
    end
    # test if this card is already tokenized for this retailer
    card = user.creditcards.where(:gateway_customer_profile_id => gateway_customer_profile_id, :last_digits => creditcard.last_digits, :cc_type => creditcard.cc_type, :first_name => creditcard.first_name, :last_name => creditcard.last_name, :month => creditcard.month, :year => creditcard.year).first

    # check if the card passed in is a new record, then it needs to be saved before, otherwise it needs to be updated and tokenized only
    if creditcard.new_record?
      creditcard.gateway_customer_profile_id = gateway_customer_profile_id
    else
      creditcard.update_attribute_without_callbacks(:gateway_customer_profile_id, gateway_customer_profile_id)
    end

    # If not card exists yet, save the copy and tokenize it
    unless card
      creditcard.gateway_payment_profile_id = nil
      creditcard.retailer_id = retailer.id
      creditcard.user_id = user.id
      creditcard.number = number
      creditcard.save!
      Rails.logger.warn(" ----------------------- Tokenizing new card with number #{creditcard.number} for retailer #{retailer.id} ...")
      Rails.logger.warn(creditcard.inspect)
      result = gateway.create_gateway_payment_profile(gateway_customer_profile_id, creditcard)
      Rails.logger.warn("  ---------------------- Result:")
      Rails.logger.warn(result.inspect)
      creditcard.update_attribute_without_callbacks(:gateway_payment_profile_id, result[:customer_payment_profile_id])
    end
    
  end

end
