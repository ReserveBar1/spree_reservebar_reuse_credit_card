Spree::Gateway::BraintreeGateway.class_eval do

  # In order to handle multiple retailers, we add a few methods here to create gateway_custoemr_profiles and add cards to them
  # This is supported by active merchant, but not implemented in Spree. Don't override original methods, add new ones.
  
  # Create only a gateway_customer_profile, without attached credit cards.
  def create_gateway_customer_profile(user, retailer)
    begin
      braintree_customer = Braintree::Customer.find("RB#{user.id}")
    rescue Braintree::NotFoundError
      result = Braintree::Customer.create(
        id: "RB#{user.id}", email: user.email)
      if result.success?
        return result.customer
      else
        return result.errors.first.message
      end
    end
  end
  
  def create_gateway_payment_profile(customer_profile_id, creditcard)
    begin
      result = Braintree::CreditCard.create(
        customer_id: customer_profile_id,
        number: creditcard.number,
        expiration_date: "#{creditcard.month}/#{creditcard.year}",
        cardholder_name: creditcard.first_name
      )
    rescue
      raise 'Something went wrong communicating with Braintree'
    end
  end

end
