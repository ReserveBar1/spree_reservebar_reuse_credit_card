Spree::Gateway::AuthorizeNetCim.class_eval do

  # In order to handle multiple retailers, we add a few methods here to create gateway_custoemr_profiles and add cards to them
  # This is supported by active merchant, but not implemented in Spree. Don't override original methods, add new ones.
  
  # Create only a gateway_customer_profile, without attached credit cards.
  def create_gateway_customer_profile(user, retailer)
    options = options_for_create_gateway_customer_profile(user, retailer)
    response = cim_gateway.create_customer_profile(options)
    if response.success?
      { :customer_profile_id => response.params['customer_profile_id'] }
    else
      # possible failures: 
      # profile already exists => attempt to retrieve profile information
      # gateway credentials wrong, => log error and skip to next gateway, should not happen in production ever
      # raise exception here
      error_code = response.params['messages']['message']['code']
      error_text = response.params['messages']['message']['text']
      case error_code
      when "E00039" # profile already exists, parse the ID from teh response text "A duplicate record with ID 19598889 already exists."
        customer_profile_id = error_text.match(/\w*(\d)+\w*/).to_a.first rescue nil
        return { :customer_profile_id => customer_profile_id } unless customer_profile_id == nil
      when "E00007" # invalid authentication credentials
        raise ActiveMerchant::ConnectionError
      end
      Rails.logger.warn('failed to create customer profile')
      raise ActiveMerchant::ConnectionError
    end
  end
  
  def options_for_create_gateway_customer_profile(user, retailer)
    validation_mode = preferred_validate_on_profile_create ? preferred_server.to_sym : :none
    { :profile => { :merchant_customer_id => "#{user.id}.#{retailer.id}",
                    :email => user.email},
      :validation_mode => validation_mode }
  end
  
  def create_gateway_payment_profile(customer_profile_id, creditcard)
    options = options_for_create_gateway_payment_profile(customer_profile_id, creditcard)
    response = cim_gateway.create_customer_payment_profile(options)
    if response.success?
      {:customer_payment_profile_id => response.params['customer_payment_profile_id'] }
    else
      # possible failure modes
      # gateway credentials, log and skip unless original card (we can tolerate not tokenizing on other retailers, but we must tokenize on original retailer or fail)
      # payment profile already exists => return existing profile id
      # customer profile does not exist => 
    end
  end
  
  def options_for_create_gateway_payment_profile(customer_profile_id, creditcard)
    {:customer_profile_id => customer_profile_id, 
      :payment_profile => {:payment => { :credit_card => creditcard }, :bill_to => generate_address_hash(creditcard.address)}
    }
  end
  

end


