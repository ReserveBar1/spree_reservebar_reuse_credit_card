Spree::Creditcard.class_eval do
  attr_accessible :number, :verification_value, :month, :year, :cc_type, :last_digits, :first_name, :last_name, :start_month, :start_year, :issue_number, :address_id, :created_at, :updated_at, :gateway_customer_profile_id, :gateway_payment_profile_id, :deleted_at

  belongs_to :address
  
  def deleted?
    !!deleted_at
  end

end
