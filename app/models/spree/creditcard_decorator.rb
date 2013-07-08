Spree::Creditcard.class_eval do
  attr_accessible :number, :verification_value, :month, :year, :cc_type, :last_digits, :first_name, :last_name, :start_month, :start_year, :issue_number, :address_id, :created_at, :updated_at, :gateway_customer_profile_id, :gateway_payment_profile_id, :deleted_at

  belongs_to :address
  
  def deleted?
    !!deleted_at
  end
  
  
  def self.tokenize_card_on_other_retailers(current_retailer, creditcard, user, card_number)
    # add card to customer profile for all other retailers, or create new customer profile and add card
    Spree::Retailer.active.each do |retailer|
      next if retailer == current_retailer
      next unless retailer.payment_method.respond_to?(:payment_profiles_supported?) && retailer.payment_method.payment_profiles_supported?
      begin
        Spree::Creditcard.tokenize_card_for_retailer(creditcard.dup, retailer, user, card_number)
      rescue
        # For now we don't care if this fails
      end
    end
  end
  
  # tokenize the card
  # if the creditcard passed in has been saved, use it and update it - this is used for the original retailer
  # if the card passed in a  new record, it is a duplicate of the original and needs to be saved
  def self.tokenize_card_for_retailer(creditcard, retailer, user, number)
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
