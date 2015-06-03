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
        cardholder_name: creditcard.first_name,
        number: creditcard.number,
        expiration_date: "#{creditcard.month}/#{creditcard.year}",
        cvv: creditcard.verification_value,
        billing_address: { postal_code: creditcard.address.zipcode },
        device_data: creditcard.device_data,
        options: { verify_card: true }
      )
    rescue
      raise 'Something went wrong communicating with Braintree'
    end
  end

  def update_billing_address_for_profile(creditcard, zipcode)
    begin
      result = Braintree::PaymentMethod.update(
        creditcard.gateway_payment_profile_id,
        cvv: creditcard.verification_value,
        billing_address: {
          postal_code: zipcode,
          options: { update_existing: true }
        },
        options: { verify_card: true }
      )
    rescue
      raise 'Something went wrong communicating with Braintree'
    end
  end

  def refund(transaction_id, amount)
    begin
      result = Braintree::Transaction.refund(transaction_id, amount)
    rescue
      return 'Something went wrong communicating with Braintree'
    end
  end

end
