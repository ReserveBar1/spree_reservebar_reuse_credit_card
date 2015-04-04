module Spree
  class CreditcardsController < Spree::BaseController
    ssl_allowed
    respond_to :js, :html

    def destroy
      @creditcard = Spree::Creditcard.find(params["id"])
      @user = @creditcard.user
      authorize! :destroy, @creditcard

      if @creditcard.save
        delete_matching_credit_cards
        respond_with @creditcard
      else
        render template: 'spree/creditcards/destroy_error'
      end
    end

    def edit
      @creditcard = Spree::Creditcard.find(params[:id])
      if @creditcard.address.present?
        @address = @creditcard.address.dup
      else
        default_country = Spree::Country.find_by_name("United States")
        @address = @creditcard.build_address(:country => default_country)
      end
    end

    def update
      @creditcard = Spree::Creditcard.find(params[:id])
      @creditcard.verification_value = params[:cvv]

      # Verify billing zip code with Braintree
      if @creditcard.bt_merchant_id.present?
        result = send_zipcode_to_braintree(@creditcard,
          params[:address][:zipcode])
        if result.is_a?(Braintree::ErrorResult)
          flash[:error] = 'Billing address does not match card. Please make sure details are correct.'
          redirect_to spree.edit_creditcard_url(@creditcard) and return
        end
      end

      if @creditcard.update_address(params[:address])
        @user = @creditcard.user
        matching = matching_credit_cards.reject { |c| c.id == @creditcard.id }
        matching.each do |card|
          card.update_attributes(address_id: @creditcard.address_id)
          card.verification_value = params[:cvv]
          result = send_zipcode_to_braintree(card, params[:address][:zipcode])
          if result.is_a?(Braintree::ErrorResult)
            flash[:error] = 'Problem occured updating the billing address on payment gateway.'
            redirect_to spree.edit_creditcard_url(@creditcard) and return
          end
        end
        flash[:notice] = I18n.t(:successfully_updated,
          :resource => I18n.t(:address))
      else
        raise 'Error updating creditcard address'
      end
      redirect_back_or_default(account_path)
    end

    private

    def send_zipcode_to_braintree(creditcard, zipcode)
      account = creditcard.bt_merchant_id
      retailer = Spree::Retailer.active.where(bt_merchant_id: account).first
      gateway = Spree::PaymentMethod.find_by_type('Spree::Gateway::BraintreeGateway')
      gateway.set_provider(retailer.bt_merchant_id, retailer.bt_public_key,
        retailer.bt_private_key)
      gateway.update_billing_address_for_profile(creditcard, zipcode)
    end

    def matching_credit_cards
      conditions = {:month => @creditcard.month,
                    :year => @creditcard.year,
                    :cc_type => @creditcard.cc_type,
                    :last_digits => @creditcard.last_digits,
                    :first_name => @creditcard.first_name,
                    :deleted_at => nil}
      @user.creditcards.find(:all, :conditions => conditions)
    end

    def delete_matching_credit_cards
      matching_credit_cards.each do |cc|
        if cc.bt_merchant_id.present?
          # delete payment methods on all merchant accounts
          retailer = Spree::Retailer.active.where(bt_merchant_id: cc.bt_merchant_id).first
          gateway = retailer.payment_method
          gateway.set_provider(retailer.bt_merchant_id, 
            retailer.bt_public_key, retailer.bt_private_key)
          begin
            card = Braintree::PaymentMethod.find(cc.gateway_payment_profile_id)
            if card.is_a?(Braintree::CreditCard)
              Braintree::PaymentMethod.delete(cc.gateway_payment_profile_id)
            else
              raise "Cannot find card #{cc.gateway_payment_profile_id} on account #{retailer.bt_merchant_id}"
            end
          rescue
            raise 'Problem connecting with Braintree'
          end
        end
        cc.gateway_payment_profile_id = nil
        cc.deleted_at = Time.now
        cc.save
      end
    end
  end

end
