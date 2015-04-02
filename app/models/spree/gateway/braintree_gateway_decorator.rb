Spree::Gateway::BraintreeGateway.class_eval do

  def create_guest_profile(user)
    result = Braintree::Customer.create(email: user)
    return result.success? ? result.customer : result.errors.first.message
  end

  def find_or_create_customer_profile(user)
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

  def create_gateway_payment_profile(customer_id, creditcard)
    begin
      result = Braintree::CreditCard.create(
        customer_id: customer_id,
        cardholder_name: creditcard.first_name,
        number: creditcard.number,
        expiration_date: "#{creditcard.month}/#{creditcard.year}",
        cvv: creditcard.verification_value,
        billing_address: { postal_code: creditcard.address.zipcode },
        options: { verify_card: true }
      )
    rescue
      raise 'Something went wrong communicating with Braintree'
    end
  end

end
