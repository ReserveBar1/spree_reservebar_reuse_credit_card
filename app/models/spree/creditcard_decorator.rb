Spree::Creditcard.class_eval do
  attr_accessible :number, :verification_value, :month, :year, :cc_type,
    :last_digits, :first_name, :last_name, :start_month, :start_year,
    :issue_number, :address_id, :created_at, :updated_at,
    :gateway_customer_profile_id, :gateway_payment_profile_id, :deleted_at,
    :bt_merchant_id

  attr_accessor :device_data
  validates :device_data, :presence => true, :unless => :has_payment_profile?, :on => :create

  belongs_to :address

  scope :active, where(deleted_at: nil)

  def expired?
    exp_year = year.to_i
    exp_month = month.to_i + 1
    if exp_month > 12
      exp_month = 1
      exp_year += 1
    end
    DateTime.new(exp_year, exp_month) < Time.now
  end

  def deleted?
    !!deleted_at
  end

  def self.tokenize_card_on_other_retailers(current_retailer_id, creditcard,
    user_id, card_number, cvv)
    current_retailer = Spree::Retailer.find(current_retailer_id)
    user = Spree::User.find(user_id)
    creditcard.verification_value = cvv

    gateway = current_retailer.payment_method
    if gateway.type == 'Spree::Gateway::BraintreeGateway'
      retailers = Spree::Retailer.active.select(:bt_merchant_id).all
      retailer_merchant_accounts = retailers.map(&:bt_merchant_id).uniq
      retailer_merchant_accounts.delete(creditcard.bt_merchant_id)
      retailer_merchant_accounts.each do |account|
        gateway_card = Spree::Creditcard.active.where(user_id: user.id, bt_merchant_id: account,:last_digits => creditcard.last_digits, :cc_type => creditcard.cc_type, :first_name => creditcard.first_name, :last_name => creditcard.last_name, :month => creditcard.month, :year => creditcard.year).first
        unless gateway_card.present?
          retailer = Spree::Retailer.active.where(bt_merchant_id: account).first
          response = Spree::Creditcard.tokenize_card_for_retailer(creditcard.dup, retailer, user, card_number)
          if response.is_a?(Braintree::ErrorResult)
            raise response.errors
          end
        end
      end
    else
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
  end

  def self.tokenize_card_for_retailer(creditcard, retailer, user, number)
    gateway = retailer.payment_method
    if gateway.type == 'Spree::Gateway::BraintreeGateway'
      gateway.set_provider(
        retailer.bt_merchant_id,
        retailer.bt_public_key,
        retailer.bt_private_key
      )
      begin
        # Create customer profiles on Braintree
        if user.is_a?(Spree::User)
          result = gateway.find_or_create_customer_profile(user)
        end
        if result.class == Braintree::Customer
          # if successful, set the profile id
          gateway_customer_profile_id = result.id
        else
          raise result
        end
      rescue
        raise 'Problem Connecting with Braintree'
      end
    else
      gateway.set_provider(retailer.gateway_login, retailer.gateway_password)
      # test if the user already has a customer profile for this retailer, if not create it
      gateway_customer_profile_id = user.gateway_customer_profile_id_for_retailer(retailer)
      if gateway_customer_profile_id.blank?
        Rails.logger.warn(" ----------------------- Creating new customer profile for retailer #{retailer.id} ...")
        result = gateway.create_gateway_customer_profile(user, retailer)
        Rails.logger.warn(" ---------------------- Result:")
        Rails.logger.warn(result.inspect)
        # TODO: error handlind of gateway errors
        gateway_customer_profile_id = result[:customer_profile_id]
      end
    end

    if gateway.type == 'Spree::Gateway::BraintreeGateway'
      if user.is_a?(Spree::User)
        card = user.creditcards.where(:gateway_customer_profile_id => gateway_customer_profile_id, :last_digits => creditcard.last_digits, :cc_type => creditcard.cc_type, :first_name => creditcard.first_name, :last_name => creditcard.last_name, :month => creditcard.month, :year => creditcard.year, :bt_merchant_id => retailer.bt_merchant_id).first
      end
    else
      # test if this card is already tokenized for this retailer
      card = user.creditcards.where(:gateway_customer_profile_id => gateway_customer_profile_id, :last_digits => creditcard.last_digits, :cc_type => creditcard.cc_type, :first_name => creditcard.first_name, :last_name => creditcard.last_name, :month => creditcard.month, :year => creditcard.year).first
    end

    # check if the card passed in is a new record, then it needs to be saved before, otherwise it needs to be updated and tokenized only
    if creditcard.new_record?
      creditcard.gateway_customer_profile_id = gateway_customer_profile_id
    else
      creditcard.update_attribute_without_callbacks(:gateway_customer_profile_id, gateway_customer_profile_id)
    end

    # If not card exists yet, save the copy and tokenize it
    unless card.present?
      if gateway.type == 'Spree::Gateway::BraintreeGateway'
        creditcard.bt_merchant_id = retailer.bt_merchant_id
      else
        creditcard.gateway_payment_profile_id = nil
        creditcard.retailer_id = retailer.id
      end
      creditcard.user_id = user.id if user.is_a?(Spree::User)
      creditcard.number = number
      creditcard.save!
      Rails.logger.warn(" ----------------------- Tokenizing new card with number #{creditcard.number} for retailer #{retailer.id} ...")
      result = gateway.create_gateway_payment_profile(gateway_customer_profile_id, creditcard)
      Rails.logger.warn("  ---------------------- Result:")
      Rails.logger.warn(result.inspect)
      if result.is_a?(Braintree::SuccessfulResult)
        creditcard.update_attribute_without_callbacks(:gateway_payment_profile_id, result.credit_card.token)
      elsif result.is_a?(Braintree::ErrorResult)
        creditcard.update_attributes(deleted_at: Time.now)
        return result
      else
        creditcard.update_attribute_without_callbacks(:gateway_payment_profile_id, result[:customer_payment_profile_id])
      end
    end
  end

  def update_address(attr = {})
    address = Spree::Address.new(
      :firstname => attr.fetch(:firstname),
      :lastname => attr.fetch(:lastname),
      :address1 => attr.fetch(:address1),
      :address2 => attr.fetch(:address2) { nil },
      :city => attr.fetch(:city),
      :state => Spree::State.find(attr.fetch(:state_id)),
      :zipcode => attr.fetch(:zipcode),
      :country => Spree::Country.find(attr.fetch(:country_id)),
      :county => attr.fetch(:county) { nil },
      :phone => attr.fetch(:phone),
      :user => self.user
    )

    if has_no_matching_address?(address) && address.save!
      self.address = address
      self.save
    end
  end

  private

  def has_matching_address?(addr)
    attr = addr.attributes.except("id", "updated_at", "created_at", "county_lookup_failed")
    matches = user.addresses.select {|a| a.attributes.except("id", "updated_at", "created_at", "county_lookup_failed") == attr}
    matches.count > 0
  end

  def has_no_matching_address?(addr)
    !has_matching_address?(addr)
  end

end
