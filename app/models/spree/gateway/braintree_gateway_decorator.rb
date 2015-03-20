Spree::Gateway::BraintreeGateway.class_eval do

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
        number: creditcard.number,
        expiration_date: "#{creditcard.month}/#{creditcard.year}",
        cardholder_name: creditcard.first_name
      )
    rescue
      raise 'Something went wrong communicating with Braintree'
    end
  end

end
