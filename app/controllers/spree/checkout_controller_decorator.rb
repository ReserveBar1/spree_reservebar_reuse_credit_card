require 'card_reuse'

Spree::CheckoutController.class_eval do
  include CardReuse

  private

  def before_payment
    current_order.payments.destroy_all if request.put?
    current_order.bill_address = Spree::Address.default
    @cards = all_cards_for_user(@order.user, @order.retailer)
    @cards = @cards.reject { |c| c.expired? }
  end

  # we are overriding this method in order to substitue in the exisiting card information
  # since we are also storing the billing address with the existing credit cards, we need to get it from the credit card
  # and dump it into the order:bill_address_id
  def object_params
    # For payment step, filter order parameters to produce the expected nested attributes for a single payment and its source, discarding attributes for payment methods other than the one selected
    if @order.payment?
      if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]

        if params[:order][:bill_address_id] != '0'
          source_params[:address_id] = params[:order][:bill_address_id]
        elsif params[:bill_address].present?
          @order.bill_address_attributes = params[:bill_address]
          bill_address = @order.bill_address
          if bill_address && bill_address.valid?
            @order.update_attribute_without_callbacks(:bill_address_id, bill_address.id)
            bill_address.update_attribute(:user_id, current_user.id) if current_user
            params[:order].delete(:bill_address_id)
            object_params.delete(:bill_address_id)
          else
            raise Exceptions::NewBillAddressError
          end
          @order.reload
          source_params[:address_id] = @order.bill_address_id
        else
          raise 'No Billing Address'
        end

        if params[:existing_card]
          creditcard = Spree::Creditcard.find(params[:existing_card])
          gateway = current_order.retailer.payment_method
          unless gateway.type == 'Spree::Gateway::BraintreeGateway'
            # at this point the user may have selected a credit card that is tokenized on another retailer's account
            # he should have entered the card number and cvv again and we need to tokenize this as a new card duped from the one he selected.
            if creditcard.retailer_id != current_order.retailer.id
              # clone the selected card and tokenize it, than make it the current card.
              begin
                new_card = creditcard.dup
                new_card.number = params[:card_number_confirm]
                new_card.verification_value = params[:card_cvv_confirm]
                new_card.gateway_customer_profile_id = nil
                new_card.gateway_payment_profile_id = nil
                new_card.save!
                Spree::Creditcard.tokenize_card_for_retailer(new_card, current_order.retailer, current_order.user, params[:card_number_confirm])
                new_card.reload
                creditcard = new_card
                # Run tokenization for the other retailers in the background
                Spree::Creditcard.delay.tokenize_card_on_other_retailers(current_order.retailer, new_card, current_order.user, params[:card_number_confirm])
              rescue ActiveMerchant::ConnectionError => e
                creditcard.send(:gateway_error, e)
              end
            end
          end
          # end processing new cards from new retailers
          authorize! :manage, creditcard
          params[:order][:payments_attributes].first[:source] = creditcard
          params[:order][:bill_address_id] = creditcard.address_id
        else
          params[:order][:payments_attributes].first[:source_attributes] = source_params
        end
      end
      if (params[:order][:payments_attributes])
        params[:order][:payments_attributes].first[:amount] = @order.total
      end
    end
    params[:order]
  end

end
